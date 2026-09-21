"""Independent two-wavelength arithmetic oracle against the actual CLI worker.

No MNE preprocessing, absorption loader, matrix solver or Brohn reader supplies
expected numbers. Coefficients are transcribed from OMLC's primary source table:
https://omlc.org/spectra/hemoglobin/summary.html (760 and 850 nm).
The declared MNE recipe uses rounded ln(10)=2.303, not exact math.log(10).
This is a software phantom, not a tissue phantom or neural validation.
"""
import hashlib
import importlib.metadata
import json
import math
from pathlib import Path
import subprocess
import sys

import h5py
import numpy as np
from snirf import Snirf

ROOT = Path(__file__).resolve().parents[2]
OUTPUT = Path(sys.argv[1]).resolve()
OUTPUT.mkdir(parents=True, exist_ok=False)
SOURCE_FILES = [ROOT / 'scripts/workers/physiology.py', ROOT / 'scripts/workers/physiology_artifacts.py']
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
code = {str(p.relative_to(ROOT)): sha(p) for p in SOURCE_FILES}
coefficients = ((586.0, 1548.52), (1058.0, 691.32))
fs = 10.0
time = np.arange(700) / fs
original = np.column_stack((100 + 3*np.sin(2*np.pi*.07*time) + np.sin(2*np.pi*1.1*time),
                            80 + 2*np.cos(2*np.pi*.04*time) + .6*np.sin(2*np.pi*1.1*time)))
cases = []


def make_source(path, values, distance_mm, reverse=False):
    order = [1, 0] if reverse else [0, 1]
    with Snirf(str(path), 'w') as snirf:
        snirf.formatVersion = '1.1'
        snirf.nirs.appendGroup()
        nirs = snirf.nirs[0]
        for key, value in {'SubjectID': 'original-software-phantom', 'MeasurementDate': '2026-09-20',
                           'MeasurementTime': '00:00:00Z', 'LengthUnit': 'mm', 'TimeUnit': 's', 'FrequencyUnit': 'Hz'}.items():
            setattr(nirs.metaDataTags, key, value)
        nirs.probe.wavelengths = np.array([760., 850.])
        nirs.probe.sourcePos3D = np.array([[0., 0., 0.]])
        nirs.probe.detectorPos3D = np.array([[distance_mm, 0., 0.]])
        nirs.data.appendGroup()
        data = nirs.data[0]
        data.time = time
        data.dataTimeSeries = values[:, order]
        for index in order:
            data.measurementList.appendGroup()
            item = data.measurementList[-1]
            item.sourceIndex = 1
            item.detectorIndex = 1
            item.wavelengthIndex = index + 1
            item.dataType = 1
            item.dataTypeIndex = 1
        snirf.save()


def oracle(values, distance_mm, ppf, bounds):
    expected = {}
    for segment_number, (start, end) in enumerate(bounds, 1):
        v = values[start:end]
        od = np.array([[-math.log(float(row[k]) / math.fsum(float(x) for x in v[:, k]) * len(v))
                        for k in range(2)] for row in v])
        # Direct scalar solution of two equations, using cm, mol/L and uM.
        a, b = (x * 2.303 * (distance_mm/10) * ppf[0] / 1e6 for x in coefficients[0])
        c, d = (x * 2.303 * (distance_mm/10) * ppf[1] / 1e6 for x in coefficients[1])
        determinant = a*d-b*c
        hbo = (d*od[:, 0]-b*od[:, 1])/determinant
        hbr = (a*od[:, 1]-c*od[:, 0])/determinant
        for index, kind in enumerate(('hbo', 'hbr')):
            expected[(f'recording-1-segment-{segment_number}', 'S1_D1 '+kind)] = {
                'channel': 'S1_D1 '+kind, 'indices': np.arange(start, end),
                'od': od[:, index], 'hb': (hbo, hbr)[index]}
    return expected


def run_case(name, values, distance_mm=30., ppf=(6., 5.), bounds=((0, 700),), reverse=False, refusal=None):
    folder = OUTPUT/name
    folder.mkdir()
    source = folder/'source.snirf'
    make_source(source, values, distance_mm, reverse)
    # Independently inspect native HDF5 bytes and measurement ordering.
    with h5py.File(source, 'r') as f:
        stored = f['nirs/data1/dataTimeSeries'][:]
        np.testing.assert_array_equal(stored, values[:, [1, 0] if reverse else [0, 1]])
        np.testing.assert_array_equal(f['nirs/data1/time'][:], time)
    source_hash = sha(source)
    artifacts = folder/'artifacts'
    artifacts.mkdir()
    request = dict(schema='brohn-worker-request/1.0', operation='physiology', modality='fnirs',
                   source_path=str(source), format='snirf', artifact_directory=str(artifacts),
                   metadata=dict(unit='native', value_columns=['S1_D1 850', 'S1_D1 760'] if reverse else ['S1_D1 760', 'S1_D1 850'],
                                 sampling_rate=fs, origin='sample', participant_id='software-phantom', session_id=name),
                   parameters={} if ppf is None else dict(ppf=list(ppf)))
    (folder/'request.json').write_text(json.dumps(request), encoding='utf-8')
    child = subprocess.run([sys.executable, str(ROOT/'scripts/workers/physiology.py'), '--request', str(folder/'request.json'),
                            '--output', str(folder/'result.json')], cwd=ROOT, capture_output=True, text=True, timeout=120)
    (folder/'worker.log').write_text(child.stdout+'\n'+child.stderr, encoding='utf-8')
    result = json.loads((folder/'result.json').read_text(encoding='utf-8'))
    assert sha(source) == source_hash
    record = dict(name=name, source_sha256=source_hash, status=result['status'], exit_code=child.returncode)
    if refusal:
        assert child.returncode == 2 and refusal.lower() in result['error']['message'].lower(), result
        record['refusal'] = result['error']['message']
    else:
        assert child.returncode == 0, result
        assert result['quality']['scientifically_qualified'] is False
        assert result['parameters']['recording-1']['ppf'] == list(ppf)
        expected = oracle(values, distance_mm, ppf, bounds)
        manifest = next(a for a in result['artifacts'] if a['kind'] == 'physiology-series')
        artifact = Path(manifest['path'])
        assert sha(artifact) == manifest['sha256'] and artifact.stat().st_size == manifest['bytes']
        tables, rows = {}, {}
        with artifact.open(encoding='utf-8') as stream:
            for line in stream:
                item = json.loads(line)
                if item['type'] == 'table':
                    tables[item['table_id']] = item
                    rows[item['table_id']] = []
                elif item['type'] == 'rows':
                    assert item['offset'] == len(rows[item['table_id']])
                    rows[item['table_id']].extend(item['rows'])
        by_identity = {(table['identity']['segment_id'], table['identity']['channel']): key for key, table in tables.items()}
        assert len(by_identity) == len(tables) and set(by_identity) == set(expected)
        errors = []
        for identity, e in expected.items():
            key = by_identity[identity]
            table = tables[key]
            names = [c['name'] for c in table['columns']]
            actual = {column: np.array([row[i] for row in rows[key]]) for i, column in enumerate(names)}
            assert table['identity']['channel'] == e['channel']
            assert table['identity']['optical_density_source_channel'] == ('S1_D1 760' if e['channel'].endswith('hbo') else 'S1_D1 850')
            np.testing.assert_array_equal(actual['source_sample_index'], e['indices'])
            # The native reader infers cadence from binary64 file timestamps.
            np.testing.assert_allclose(actual['time_s'], e['indices']/fs, rtol=0, atol=4*np.finfo(float).eps*max(time))
            np.testing.assert_allclose(actual['optical_density'], e['od'], rtol=1e-11, atol=1e-14)
            np.testing.assert_allclose(actual['haemoglobin_um'], e['hb'], rtol=1e-10, atol=1e-10)
            feat = {f['name']: f['value'] for f in result['features'] if f['channel'] == e['channel'] and f['segment_id'] == table['identity']['segment_id']}
            mean = math.fsum(float(x) for x in e['hb'])/len(e['hb'])
            sd = math.sqrt(math.fsum((float(x)-mean)**2 for x in e['hb'])/(len(e['hb'])-1))
            for feature, value in [('haemoglobin_mean_change', mean), ('haemoglobin_sd', sd), ('haemoglobin_peak_to_peak', max(e['hb'])-min(e['hb']))]:
                assert math.isclose(feat[feature], value, rel_tol=1e-10, abs_tol=1e-10), (feature, feat[feature], value)
            errors.append(float(np.max(np.abs(actual['haemoglobin_um']-e['hb']))))
        record.update(tables=len(tables), rows=sum(len(v) for v in rows.values()), maximum_hb_error_um=max(errors),
                      invalid_samples=result['quality']['invalid_or_missing_time_samples'],
                      artifact_sha256=manifest['sha256'], versions=result.get('engine'))
    cases.append(record)
    print(json.dumps(record), flush=True)


try:
    run_case('unequal-pathlength', original)
    run_case('double-distance', original, distance_mm=60.)
    run_case('double-pathlength', original, ppf=(12., 10.))
    run_case('reversed-native-order', original, reverse=True)
    broken = original.copy()
    broken[300:310, 0] = 0
    run_case('nonpositive-splits', broken, bounds=((0, 300), (310, 700)))
    run_case('missing-pathlength-refused', original, ppf=None, refusal='pathlength factors')
    run_case('zero-distance-refused', original, distance_mm=0, refusal='geometry')
    assert code == {str(p.relative_to(ROOT)): sha(p) for p in SOURCE_FILES}
    receipt = dict(passed=True, cases=cases, code_hashes=code, coefficients=coefficients,
                   coefficient_source='https://omlc.org/spectra/hemoglobin/summary.html',
                   oracle='Independent scalar determinant, fsum baseline, original HDF5 bytes and complete typed rows',
                   rounded_log_factor=2.303, rounded_vs_exact_log_relative=2.303/math.log(10)-1,
                   tolerance=dict(haemoglobin_um_atol=1e-10, rtol=1e-10, time_s_atol=4*np.finfo(float).eps*max(time)),
                   versions={p: importlib.metadata.version(p) for p in ['numpy', 'scipy', 'mne', 'mne-nirs', 'snirf', 'h5py']},
                   scope='Original software phantom. No SCI, clinical, neural, motion-correction or physical-device qualification.')
    (OUTPUT/'acceptance.json').write_text(json.dumps(receipt, indent=2), encoding='utf-8')
except BaseException as error:
    (OUTPUT/'failure.json').write_text(json.dumps(dict(error=repr(error), completed=cases, code_hashes=code), indent=2), encoding='utf-8')
    raise
