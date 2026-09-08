"""Brohn acquisition/interchange preparation using synthetic data only.

This is a bounded reference probe, not a participant recorder or product adapter.
All generated streams/files carry synthetic provenance. No hardware enumeration,
camera access, participant dataset download or vendor credentials are used.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import importlib.metadata
import json
import math
import os
from pathlib import Path
import platform
import struct
import sys
import time
import traceback
import uuid


EXPECTED = {
    "pylsl": "1.18.2", "brainflow": "5.22.2", "pyxdf": "1.17.5",
    "pyarrow": "25.0.1", "duckdb": "1.5.5", "mne": "1.12.1",
    "mne-bids": "0.19.0", "mne-connectivity": "0.9.0",
    "snirf": "0.8.0", "pybv": "0.8.1", "mne-nirs": "0.7.3",
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--work-dir", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    work = args.work_dir.resolve()
    if work == root or root in work.parents:
        parser.error("Synthetic artifacts must be outside the repository")
    work.mkdir(parents=True, exist_ok=True)
    run_dir = work / ("synthetic-" + uuid.uuid4().hex)
    run_dir.mkdir()
    os.environ["MPLBACKEND"] = "Agg"
    os.environ["MPLCONFIGDIR"] = str(run_dir / "matplotlib")
    os.environ["MNE_DONTWRITE_HOME"] = "true"
    config = run_dir / "lsl_api.cfg"
    config.write_text("[multicast]\nResolveScope = machine\n[lab]\nSessionID = brohn-synthetic-" + uuid.uuid4().hex + "\n", encoding="utf-8")
    os.environ["LSLAPICFG"] = str(config)
    checks, observations = [], {}

    def check(name, passed, evidence, **details):
        checks.append({"name": name, "passed": bool(passed), "evidence": evidence, **details})

    def section(name, fn):
        try:
            fn()
        except Exception as exc:
            check(name + " execution", False, "execution failure", error=repr(exc), traceback=traceback.format_exc(limit=5))

    versions = {name: importlib.metadata.version(name) for name in EXPECTED}
    check("Pinned engine versions", versions == EXPECTED, "environment identity", observed=versions)
    import numpy as np

    def brainflow_probe():
        from brainflow.board_shim import BoardIds, BoardShim, BrainFlowInputParams
        BoardShim.disable_board_logger()
        board_id = BoardIds.SYNTHETIC_BOARD.value
        board = BoardShim(board_id, BrainFlowInputParams())
        started = False
        try:
            board.prepare_session()
            board.start_stream(2048)
            started = True
            time.sleep(0.25)
            board.insert_marker(73)
            time.sleep(0.35)
            data = board.get_board_data()
            expected_rows = BoardShim.get_num_rows(board_id)
            time_row = BoardShim.get_timestamp_channel(board_id)
            marker_row = BoardShim.get_marker_channel(board_id)
            eeg_rows = BoardShim.get_eeg_channels(board_id)
            rate = BoardShim.get_sampling_rate(board_id)
            check("BrainFlow synthetic board samples", data.shape[0] == expected_rows and 20 <= data.shape[1] <= 2048, "synthetic acquisition", rows=int(data.shape[0]), samples=int(data.shape[1]), nominal_hz=rate)
            check("BrainFlow synthetic clock ordering", np.isfinite(data[time_row]).all() and (np.diff(data[time_row]) > 0).all(), "synthetic acquisition")
            check("BrainFlow inserted marker", np.count_nonzero(data[marker_row] == 73) == 1, "synthetic event transport")
            check("BrainFlow synthetic EEG channels", len(eeg_rows) > 0 and np.isfinite(data[eeg_rows]).all(), "synthetic acquisition", eeg_channels=len(eeg_rows))
            observations["brainflow"] = {"board_id": board_id, "board_name": "SYNTHETIC_BOARD", "sampling_rate_hz": rate, "sample_count": int(data.shape[1]), "row_count": expected_rows, "timestamp_channel": time_row, "marker_channel": marker_row, "eeg_channels": eeg_rows, "interpretation": "Synthetic transport only; no physical sampling latency, hardware units, or clock accuracy established."}
        finally:
            if started:
                board.stop_stream()
            if board.is_prepared():
                board.release_session()
        check("BrainFlow session released", not board.is_prepared(), "resource lifecycle")

    def lsl_probe():
        import pylsl
        source_id = "brohn-synthetic-" + uuid.uuid4().hex
        info = pylsl.StreamInfo("Brohn synthetic loopback", "BrohnSynthetic", 2, 0, "double64", source_id)
        desc = info.desc()
        desc.append_child_value("origin", "synthetic")
        channel = desc.append_child("channels").append_child("channel")
        channel.append_child_value("label", "synthetic_voltage")
        channel.append_child_value("unit", "V")
        outlet = pylsl.StreamOutlet(info, chunk_size=1, max_buffered=5)
        # Resolve only our random source id in an isolated machine-scope session.
        # Direct outlet.get_info() has no resolved host address on this platform.
        matches = pylsl.resolve_byprop("source_id", source_id, minimum=1, timeout=3.0)
        if len(matches) != 1:
            raise RuntimeError("Expected exactly the newly created synthetic outlet")
        inlet = pylsl.StreamInlet(matches[0], max_buflen=5, recover=False, processing_flags=pylsl.proc_none)
        try:
            inlet.open_stream(timeout=3.0)
            if not outlet.wait_for_consumers(timeout=3.0):
                raise RuntimeError("Synthetic local inlet did not connect")
            sent_at = pylsl.local_clock()
            outlet.push_sample([1.25e-6, 73.0], timestamp=sent_at)
            sample, stamp = inlet.pull_sample(timeout=3.0)
            check("LSL synthetic payload", sample == [1.25e-6, 73.0], "same-machine loopback")
            check("LSL explicit original timestamp", stamp == sent_at, "same-machine loopback", postprocessing="proc_none")
            correction = inlet.time_correction(timeout=3.0)
            check("LSL clock correction query", math.isfinite(correction), "same-machine clock API smoke", correction_seconds=correction)
            received_info = inlet.info(timeout=3.0)
            check("LSL synthetic provenance metadata", received_info.source_id() == source_id and received_info.desc().child_value("origin") == "synthetic", "same-machine metadata transport")
            observations["lsl"] = {"native_library_version": pylsl.library_version(), "scope": "machine", "stream_selection": "unique random source_id of newly created outlet only; isolated session id", "processing_flags": "proc_none", "timestamp_clock": "lsl_local_clock seconds; not UTC", "initial_probe_issue": "Opening an inlet using outlet.get_info() timed out; resolving this outlet's unique source_id supplies the required network address.", "interpretation": "Local payload/API check, not inter-device synchronization or stimulus-onset qualification."}
        finally:
            inlet.close_stream()
            del inlet
            del outlet

    def parquet_probe():
        import pyarrow as pa
        import pyarrow.parquet as pq
        import duckdb
        # Int64 values deliberately exceed JavaScript's exact integer range.
        ticks = [2**53 + 1, 2**53 + 4, 2**53 + 7, 2**53 + 10]
        schema = pa.schema([
            pa.field("source_ticks", pa.int64(), metadata={b"unit": b"ns", b"clock_id": b"synthetic-monotonic-1"}),
            pa.field("voltage", pa.float64(), metadata={b"unit": b"V"}),
            pa.field("valid", pa.bool_()),
        ], metadata={b"origin": b"synthetic", b"schema_id": b"brohn-acquisition-reference/0.1"})
        table = pa.Table.from_arrays([pa.array(ticks, type=pa.int64()), pa.array([1e-6, None, 3e-6, 5e-6]), pa.array([True, False, True, True])], schema=schema)
        path = run_dir / "synthetic-signals.parquet"
        pq.write_table(table, path, version="2.6", compression="zstd", row_group_size=2)
        restored = pq.read_table(path)
        check("Parquet exact source ticks above 2^53", restored.column("source_ticks").to_pylist() == ticks, "integer serialization roundtrip")
        check("Parquet channel/clock/schema metadata", restored.schema.equals(schema, check_metadata=True), "metadata roundtrip")
        check("Parquet null and validity remain distinct", restored.column("voltage").to_pylist() == [1e-6, None, 3e-6, 5e-6] and restored.column("valid").to_pylist() == [True, False, True, True], "missingness roundtrip")
        with duckdb.connect(":memory:", config={"memory_limit": "64MB", "threads": "1", "enable_external_access": "false"}) as conn:
            # Register the explicitly loaded bounded Arrow object; external reads disabled.
            conn.register("signals", restored)
            result = conn.execute("SELECT count(*), min(source_ticks), max(source_ticks), count(voltage) FROM signals").fetchone()
            check("DuckDB integer/null aggregation", result == (4, ticks[0], ticks[-1], 3), "bounded analytic query", observed=list(result))
            selected = conn.execute("SELECT source_ticks FROM signals WHERE source_ticks >= ? AND valid ORDER BY source_ticks LIMIT 2", [ticks[2]]).fetchall()
            check("DuckDB parameterized bounded window", selected == [(ticks[2],), (ticks[3],)], "bounded analytic query")
        observations["columnar"] = {"format": "Parquet 2.6 zstd", "ticks_encoding": "signed int64; explicit ns scale and monotonic clock id", "json_boundary": "Represent source_ticks as decimal strings, never JavaScript numeric values", "sample_count": 4, "file_sha256": hashlib.sha256(path.read_bytes()).hexdigest(), "duckdb_memory_limit": "64MB", "duckdb_threads": 1, "external_access": False, "scale_limit": "Four-row serialization test, not a volume/performance benchmark."}

    def xdf_probe():
        import pyxdf
        def varint(value):
            return bytes([1, value]) if value < 256 else b"\x04" + struct.pack("<I", value)
        def chunk(tag, content):
            payload = struct.pack("<H", tag) + content
            return varint(len(payload)) + payload
        timestamps = [10.0, 10.125, 10.25]
        values = [1.25, 2.5, 3.75]
        header = b"<info><name>Brohn synthetic</name><type>BrohnSynthetic</type><channel_count>1</channel_count><nominal_srate>8</nominal_srate><channel_format>double64</channel_format><desc><origin>synthetic</origin><unit>V</unit></desc></info>"
        payload = struct.pack("<I", 1) + varint(len(values)) + b"".join(b"\x08" + struct.pack("<dd", stamp, value) for stamp, value in zip(timestamps, values))
        path = run_dir / "synthetic-reference.xdf"
        path.write_bytes(b"XDF:" + chunk(1, b"<info><version>1.0</version></info>") + chunk(2, struct.pack("<I", 1) + header) + chunk(3, payload) + chunk(6, struct.pack("<I", 1) + b"<info><first_timestamp>10</first_timestamp><last_timestamp>10.25</last_timestamp><sample_count>3</sample_count></info>"))
        streams, file_info = pyxdf.load_xdf(str(path), synchronize_clocks=False, dejitter_timestamps=False)
        check("XDF synthetic numeric stream", len(streams) == 1 and np.array_equal(streams[0]["time_series"].ravel(), values), "synthetic XDF parser fixture")
        check("XDF raw timestamps retained", np.array_equal(streams[0]["time_stamps"], timestamps), "synthetic XDF parser fixture")
        check("XDF unit/provenance retained", streams[0]["info"]["desc"][0]["unit"] == ["V"] and streams[0]["info"]["desc"][0]["origin"] == ["synthetic"], "synthetic XDF parser fixture")
        observations["xdf"] = {"fixture_sha256": hashlib.sha256(path.read_bytes()).hexdigest(), "file_version": file_info, "synchronize_clocks": False, "dejitter_timestamps": False, "interpretation": "Generated minimum numeric fixture; no LabRecorder file, clock-offset/reset recovery or multiple-device alignment tested."}

    def connectivity_probe():
        from mne_connectivity import spectral_connectivity_epochs
        rng = np.random.default_rng(73)
        signals = rng.standard_normal((10, 1, 512)) * 1e-6
        identical = np.concatenate([signals, signals], axis=1)
        coh = spectral_connectivity_epochs(identical, method="coh", indices=([0], [1]), sfreq=128, mode="fourier", fmin=8, fmax=12, faverage=True, verbose=False)
        value = float(coh.get_data()[0, 0])
        check("MNE connectivity identical-channel coherence", math.isclose(value, 1.0, rel_tol=1e-12, abs_tol=1e-12), "analytic identity on synthetic epochs", observed=value)
        observations["connectivity"] = {"method": "coh", "mode": "fourier", "sfreq_hz": 128, "epochs": 10, "samples_per_epoch": 512, "band_hz": [8, 12], "interpretation": "Coherence identity verifies executable API; it does not establish neural directionality, independence from volume conduction, or valid study inference."}

    def bids_probe():
        import mne
        from mne_bids import BIDSPath, read_raw_bids, write_raw_bids
        rate = 100
        times = np.arange(300) / rate
        volts = np.vstack([10e-6 * np.sin(2 * np.pi * 10 * times), 5e-6 * np.cos(2 * np.pi * 5 * times)])
        raw = mne.io.RawArray(volts, mne.create_info(["Fz", "Cz"], rate, "eeg"), verbose=False)
        raw.set_montage("standard_1020")
        path = BIDSPath(subject="synthetic01", task="synthetic", datatype="eeg", root=run_dir / "synthetic-bids")
        written = write_raw_bids(raw, path, format="BrainVision", allow_preload=True, events=np.array([[100, 0, 73]], dtype=int), event_id={"synthetic_control": 73}, overwrite=False, verbose=False)
        restored = read_raw_bids(written, verbose=False)
        observed = restored.get_data()
        max_error = float(np.max(np.abs(observed - volts)))
        check("BIDS EEG voltage and sample roundtrip", restored.info["sfreq"] == rate and observed.shape == volts.shape and max_error < 1e-12, "synthetic BIDS/BrainVision roundtrip", max_error_volts=max_error)
        check("BIDS synthetic event roundtrip", "synthetic_control" in restored.annotations.description, "synthetic event metadata roundtrip")
        observations["bids"] = {"format": "BrainVision via pybv", "channels": 2, "samples": 300, "mne_input_unit": "V", "max_error_volts": max_error, "interpretation": "Synthetic EEG writer/reader check; external BIDS validator and real manufacturer imports not exercised."}

    def snirf_probe():
        from snirf import Snirf, validateSnirf
        path = run_dir / "synthetic-reference.snirf"
        values = np.column_stack([np.linspace(1, 2, 20), np.linspace(2, 3, 20)])
        with Snirf(str(path), "w") as snirf:
            snirf.formatVersion = "1.1"
            snirf.nirs.appendGroup()
            nirs = snirf.nirs[0]
            nirs.metaDataTags.SubjectID = "synthetic"
            nirs.metaDataTags.MeasurementDate = "2026-09-08"
            nirs.metaDataTags.MeasurementTime = "00:00:00Z"
            nirs.metaDataTags.LengthUnit = "mm"
            nirs.metaDataTags.TimeUnit = "s"
            nirs.metaDataTags.FrequencyUnit = "Hz"
            nirs.probe.wavelengths = np.array([760.0, 850.0])
            nirs.probe.sourcePos3D = np.array([[0.0, 0.0, 0.0]])
            nirs.probe.detectorPos3D = np.array([[30.0, 0.0, 0.0]])
            nirs.data.appendGroup()
            data = nirs.data[0]
            data.time = np.arange(20) / 10
            data.dataTimeSeries = values
            for wavelength in [1, 2]:
                data.measurementList.appendGroup()
                entry = data.measurementList[-1]
                entry.sourceIndex = 1
                entry.detectorIndex = 1
                entry.wavelengthIndex = wavelength
                entry.dataType = 1
                entry.dataTypeIndex = 1
            snirf.save()
        validation = validateSnirf(str(path))
        check("SNIRF synthetic structure validation", bool(validation), "synthetic file schema validation", fatal_errors=[str(error) for error in validation.errors])
        with Snirf(str(path), "r") as restored:
            nirs = restored.nirs[0]
            check("SNIRF samples, geometry and units roundtrip", np.array_equal(nirs.data[0].dataTimeSeries, values) and nirs.metaDataTags.TimeUnit == "s" and nirs.metaDataTags.LengthUnit == "mm" and np.array_equal(nirs.probe.wavelengths, [760.0, 850.0]), "synthetic file roundtrip")
        observations["snirf"] = {"sample_count": 20, "channels": 2, "amplitude_units": "synthetic arbitrary intensity units", "measurement_type": "continuous-wave amplitude", "interpretation": "Format/metadata readiness only; no optical-density, haemoglobin conversion or fNIRS GLM tested here."}

    def nirs_probe():
        import mne
        import pandas as pd
        from mne.preprocessing.nirs import optical_density, beer_lambert_law
        from mne_nirs.signal_enhancement import short_channel_regression
        from mne_nirs.statistics import run_glm
        raw = mne.io.read_raw_snirf(str(run_dir / "synthetic-reference.snirf"), preload=True, verbose=False)
        intensity = raw.get_data()
        density = optical_density(raw, verbose=False)
        expected_density = -np.log(intensity / intensity.mean(axis=1, keepdims=True))
        check("fNIRS optical density analytic reference", np.allclose(density.get_data(), expected_density, atol=1e-14, rtol=1e-14), "independent logarithmic arithmetic")
        haemo = beer_lambert_law(density, ppf=6.0)
        check("fNIRS Beer-Lambert executable conversion", haemo.get_channel_types() == ["hbo", "hbr"] and np.isfinite(haemo.get_data()).all(), "synthetic conversion API smoke", ppf=6.0)
        common = np.sin(2 * np.pi * np.arange(100) / 20)
        names = ["S1_D1 760", "S1_D1 850", "S1_D2 760", "S1_D2 850"]
        od_info = mne.create_info(names, 10, "fnirs_od")
        for idx, ch in enumerate(od_info["chs"]):
            distance = 0.03 if idx < 2 else 0.008
            ch["loc"][:3] = [distance / 2, 0, 0]
            ch["loc"][3:6] = [0, 0, 0]
            ch["loc"][6:9] = [distance, 0, 0]
            ch["loc"][9] = 760 if idx % 2 == 0 else 850
        od = mne.io.RawArray(np.vstack([2 * common, 3 * common, common, common]), od_info, verbose=False)
        cleaned = short_channel_regression(od, max_dist=0.01)
        check("fNIRS synthetic shared short-channel regression", np.max(np.abs(cleaned.get_data()[:2])) < 1e-12 and np.array_equal(cleaned.get_data()[2:], od.get_data()[2:]), "analytic common-signal removal", threshold_metres=0.01)
        regressor = np.linspace(-1, 1, 100)
        design = pd.DataFrame({"intercept": np.ones(100), "synthetic_control": regressor})
        coefficients = np.array([[1e-6, 2e-6], [-1e-6, 0.5e-6]])
        h_info = mne.create_info(["S1_D1 hbo", "S1_D1 hbr"], 10, ["hbo", "hbr"])
        h_raw = mne.io.RawArray(coefficients @ design.to_numpy().T, h_info, verbose=False)
        model = run_glm(h_raw, design, noise_model="ols", n_jobs=1)
        observed_coefficients = np.array(model.theta()).squeeze(-1)
        check("fNIRS GLM known coefficients", np.allclose(observed_coefficients, coefficients, atol=1e-18, rtol=1e-12), "independent linear-model arithmetic", max_error=float(np.max(np.abs(observed_coefficients - coefficients))))
        observations["fnirs"] = {"optical_density_formula": "-log(intensity / per-channel arithmetic mean intensity)", "beer_lambert_ppf": 6.0, "short_channel_max_dist_m": 0.01, "glm_noise_model": "ols for analytic fixture only", "short_channel_source_observation": "mne-nirs 0.7.3 chooses nearest short channel by geometry without a wavelength check; exactly max_dist channels are neither short nor long. Brohn must require compatible selected regressors and explicit distance rules; this fixture intentionally gives identical short-channel signals.", "interpretation": "OD and GLM arithmetic references plus conversion/regression smoke; no haemodynamic reference dataset, optimum PPF, nuisance-control or autoregressive inference qualification."}

    for name, fn in [("BrainFlow", brainflow_probe), ("LSL", lsl_probe), ("Parquet/DuckDB", parquet_probe), ("XDF", xdf_probe), ("Connectivity", connectivity_probe), ("BIDS", bids_probe), ("SNIRF", snirf_probe), ("fNIRS", nirs_probe)]:
        section(name, fn)
    passed = sum(item["passed"] for item in checks)
    result = {"schema": "brohn-acquisition-preparation/0.1", "generated_utc": datetime.now(timezone.utc).isoformat(), "origin": "synthetic", "product_enabled": False, "python": platform.python_version(), "platform": platform.platform(), "script_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(), "versions": versions, "summary": {"checks": len(checks), "passed": passed, "failed": len(checks) - passed}, "checks": checks, "observations": observations, "limitations": ["No physical devices, camera or participant data used.", "No sensor/display/response latency or inter-device synchronization qualified.", "No application adapter, job service, recorder recovery or R interoperability implemented by this probe.", "All tests are small synthetic references; they are not volume benchmarks or empirical validity evidence."]}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    def portable(value):
        if isinstance(value, int) and abs(value) > 2**53 - 1:
            return str(value)
        if isinstance(value, dict):
            return {key: portable(item) for key, item in value.items()}
        if isinstance(value, (list, tuple)):
            return [portable(item) for item in value]
        return value
    args.output.write_text(json.dumps(portable(result), indent=2, allow_nan=False) + "\n", encoding="utf-8")
    print(json.dumps(result["summary"]))
    for item in checks:
        if not item["passed"]:
            print(json.dumps(item))
    return 0 if passed == len(checks) else 1


if __name__ == "__main__":
    sys.exit(main())
