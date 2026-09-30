"""Independent oracle negative witnesses over previously generated fixtures.
Usage: python -B tests/eda-constant-oracle-refusals.py REPO PURE_COMPONENT_OUT FRESH_OUT
No Brohn module or scientific package is imported.
"""
from pathlib import Path
import copy,hashlib,importlib.util,json,sys
repo,fixtures,out=map(lambda p:Path(p).resolve(),sys.argv[1:]);assert not out.exists();out.mkdir(parents=True)
path=repo/'tests/verify-eda-constant-report-download.py';spec=importlib.util.spec_from_file_location('oracle',path);o=importlib.util.module_from_spec(spec);spec.loader.exec_module(o)
q=o.loads((fixtures/'constant-1/prepared-request.json').read_bytes());e=o.loads((fixtures/'constant-1/evidence.json').read_bytes());a=q['report']['complete_analysis'];cell=e['cells'][0]
checks=[]
def reject(fn,label):
    try:fn()
    except AssertionError:checks.append(label)
    else:raise AssertionError(label)
o.constant_findings(a,cell);checks.append('untouched original constant findings accepted')
for label,change in [
    ('finite zero cannot replace withheld tonic',lambda x,y:x['features'][0].update(value=0)),
    ('amplitude denominator must remain present null',lambda x,y:x['features'][6].pop('denominator')),
    ('non-amplitude denominator must remain absent',lambda x,y:x['features'][0].update(denominator=None)),
    ('boolean zero cannot replace integer candidate count',lambda x,y:y['original_support'].update(numerical_candidate_count=False)),
    ('zero response must not replace unavailable response',lambda x,y:y['original_support'].update(response_status='computed',response_denominator=320)),
    ('nonnull model cannot disappear',lambda x,y:y.update(model=None)),
    ('fake zero waveform refuses',lambda x,y:y['model']['series']['phasic_us'].append(dict(points=[dict(value=0,time_s=0)]))),
    ('coordinate count cannot become ordinary processed count',lambda x,y:y['model']['counts'].update(selected_samples=480)),
    ('constant view cannot secretly narrow bounds',lambda x,y:y['requested_bounds'].update(start_s='1'))]:
    bad_a=copy.deepcopy(a);bad_c=copy.deepcopy(cell);change(bad_a,bad_c)
    reject(lambda:o.constant_findings(bad_a,bad_c),label)
for stream in q['streams']:
    records=[o.loads(line) for line in Path(stream['path']).read_bytes().splitlines()]
    spec=next(x for x in records if x['type']=='table');rows=[r for x in records if x['type']=='rows' for r in x['rows']];kind=stream['original']['kind']
    o.constant_table(spec,rows,kind,cell);checks.append('original complete '+kind+' accepted')
    if kind=='physiology-series':
        for label,change in [
            ('finite phasic substitute refuses',lambda r:r[0].__setitem__(4,0.0)),
            ('retained edge mask corruption refuses',lambda r:r[0].__setitem__(5,True)),
            ('source sample index corruption refuses',lambda r:r[0].__setitem__(1,2)),
            ('dropped last coordinate row refuses',lambda r:r.pop()),
            ('reversed timestamp refuses',lambda r:r[1].__setitem__(0,-1.0))]:
            bad=copy.deepcopy(rows);change(bad);reject(lambda:o.constant_table(spec,bad,kind,cell),label)
    else:reject(lambda:o.constant_table(spec,[[0]],kind,cell),'nonempty bypassed candidate table refuses')
receipt=dict(passed=True,checks=checks,count=len(checks),oracle_sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
    fixture_sha256={n:hashlib.sha256((fixtures/'constant-1'/n).read_bytes()).hexdigest() for n in ('evidence.json','prepared-request.json')},
    scope='Oracle semantic negative copies only; no native export acceptance or scientific scoring')
(out/'results.json').write_text(json.dumps(receipt,indent=2),encoding='utf-8');print(json.dumps(dict(passed=True,checks=len(checks))))
