"""Independent constant/support witnesses and unchanged-path regression.

Usage: python -B tests/eda-constant-producer.py CANDIDATE BASELINE FRESH_OUT
The baseline supplies the unchanged 1.0 path only for regression comparisons.
Constant expectations use source values and independent coordinate arithmetic.
This component test is not native publication, device or scientific validation.
"""
from pathlib import Path
import csv
import copy
import hashlib
import importlib.util
import json
import math
import sys
from unittest.mock import patch

import numpy as np

repo, baseline, out = [Path(x).resolve() for x in sys.argv[1:]]
assert not out.exists(), "Use a fresh evidence directory"
out.mkdir(parents=True)
checks = []
cases = []
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
source_files = ["scripts/workers/physiology.py", "scripts/workers/physiology_artifacts.py"]
source_hashes = {p: sha(repo / p) for p in source_files}
baseline_hashes = {p: sha(baseline / p) for p in source_files}


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


worker = load("constant_candidate", repo / source_files[0])
old = load("constant_original", baseline / source_files[0])
tables = load("constant_tables", repo / source_files[1])


def check(condition, description):
    assert condition, description
    checks.append(description)


def run_and_retain(req):
    result = worker.run(req)
    directory = Path(req["source_path"]).parent
    (directory / "result.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    return result


def request(name, values, fs=10, unit="uS", times=None, version="1.1", artifacts=True):
    directory = out / name
    directory.mkdir()
    values = np.asarray(values)
    times = np.arange(len(values)) / fs if times is None else np.asarray(times)
    path = directory / "source.csv"
    with path.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.writer(stream)
        writer.writerow(["time", "conductance", "person", "visit"])
        for t, x in zip(times, values):
            writer.writerow([format(float(t), ".17g"), "NA" if not np.isfinite(x) else format(float(x), ".17g"), "0007", "0002"])
    result = dict(schema="brohn-worker-request/1.0", operation="physiology", modality="eda",
                  source_path=str(path), format="csv", parameters={"recipe": "eda-neurokit-highpass/" + version},
                  metadata=dict(time_column="time", time_unit="s", sampling_rate=fs,
                                value_columns=["conductance"], unit=unit, participant_column="person",
                                session_column="visit", origin="sample"))
    if artifacts:
        artifact_dir = directory / "artifacts"
        artifact_dir.mkdir()
        result["artifact_directory"] = str(artifact_dir)
    return result


def retained_tables(result):
    observed = {}
    for artifact in result["artifacts"]:
        specs, rows = {}, {}
        def on_table(spec):
            specs[spec["table_id"]] = spec
            rows[spec["table_id"]] = []
        def on_rows(table_id, offset, chunk):
            check(offset == len(rows[table_id]), "continuous chunk offsets: " + table_id)
            rows[table_id].extend(chunk)
        tables.verify_artifact(artifact, on_table=on_table, on_rows=on_rows)
        observed[artifact["kind"]] = (specs, rows)
    return observed


def inspect_constant(result, level, samples, fs):
    check(result["status"] == "completed", "constant job completes descriptively")
    r = result["recordings"][0]
    check(r["status"] == "descriptive_only" and r["exact_flatline"] is True, "exact constant has separate descriptive status")
    check(r["response_status"] == "unavailable" and r["response_reason"] == "exact_constant_signal" and
          r["response_denominator"] is None and r["numerical_candidate_count"] == 0,
          "unavailable response and zero generated candidates stay distinct")
    edge = math.ceil(10 * fs)
    check(r["retained_samples"] == samples - 2 * edge and r["retained_duration_s"] == (samples - 2 * edge) / fs,
          "independent retained sample and duration arithmetic")
    features = {f["name"]: f for f in result["features"]}
    names = {"tonic_mean", "tonic_median", "tonic_slope", "conductance_raw_mean", "scr_count", "scr_rate",
             "scr_amplitude_mean", "scr_amplitude_median", "phasic_area_signed", "phasic_area_positive"}
    check(set(features) == names and len(result["features"]) == 10, "all ten original measure rows preserved")
    check(features["conductance_raw_mean"]["value"] == level and features["conductance_raw_mean"]["eligible"] is True,
          "raw mean equals converted constant, independently")
    check(all(f["value"] is None and f["eligible"] is False and f["missing_reason"] == "exact_constant_signal"
              for n, f in features.items() if n != "conductance_raw_mean"), "all nine processed measures withheld, never zero")
    check(all(f.get("denominator", "absent") == (None if n.startswith("scr_amplitude_") else "absent")
              for n, f in features.items()), "null amplitude denominators versus absent other denominators")
    q = result["quality"]
    check(q["usable"] is True and q["computed_channel_segments"] == 0 and q["descriptive_channel_segments"] == 1
          and q["unavailable_channel_segments"] == 0 and q["scientifically_qualified"] is False,
          "descriptive usability does not claim computed response or scientific qualification")
    check(result["events"] == [] and all(p["raw_us"] == level and
          all(p[c] is None for c in ("clean_us", "tonic_us", "phasic_us")) for p in result["series"]),
          "bounded raw preview preserved without a fabricated processed trace")
    check(all(f["group"]["participant_id"] == "0007" and f["group"]["session_id"] == "0002" for f in features.values()),
          "leading-zero person and visit identities remain text")
    streams = retained_tables(result)
    check(set(streams) == {"physiology-series", "physiology-events"}, "constant result has two genuine typed streams")
    specs, rows = streams["physiology-series"]
    spec = next(iter(specs.values()))
    data = next(iter(rows.values()))
    check(len(data) == samples and [c["name"] for c in spec["columns"]] ==
          ["time_s", "source_sample_index", "clean_us", "tonic_us", "phasic_us", "retained"],
          "all source coordinate rows retained with exact six-column grammar")
    check([c["nullable"] for c in spec["columns"]] == [False, False, True, True, True, False],
          "nullable processed columns are explicit")
    check(all(row[1] == i and row[2:5] == [None, None, None] and row[5] == (edge <= i < samples-edge)
              for i, row in enumerate(data)), "every original row index, null and retained flag matches independent source arithmetic")
    check(all(not v for v in streams["physiology-events"][1].values()), "candidate tables are valid empty tables, not missing files")
    check(spec["support"]["raw_source_omitted"] is True and "raw_us" not in [c["name"] for c in spec["columns"]],
          "complete raw waveform exclusion stays explicit")


passed = False
failure = None
try:
    for fs, level, unit in [(8, 0., "uS"), (10, .5, "uS"), (25, 5., "uS"),
                             (10, 500., "uS"), (10, .000005, "S"), (10, 1e307, "uS")]:
        name = f"constant-{len(cases)+1}"
        req = request(name, np.full(fs*60, level), fs, unit)
        result = run_and_retain(req)
        converted = level * (1e6 if unit == "S" else 1)
        inspect_constant(result, converted, fs*60, fs)
        json.dumps(result, allow_nan=False)
        (out / name / "result.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
        cases.append(dict(name=name, fs=fs, level=level, unit=unit, rows=fs*60))

    class NoNumericalPipeline:
        def __getattr__(self, name):
            raise AssertionError("Constant branch invoked numerical pipeline: " + name)
    with patch.object(worker, "require_neurokit", return_value=NoNumericalPipeline()):
        result = worker.eda(np.zeros(600), np.arange(600)/10, 10,
                            worker.parameters("eda", {"recipe":"eda-neurokit-highpass/1.1"}, 10))
        check(result["status"] == "descriptive_only", "constant branch never calls cleaning, decomposition or peak detection")

    for samples, expected in [(399, "unavailable"), (400, "descriptive_only")]:
        r = run_and_retain(request("edge-"+str(samples), np.full(samples, 5.)))
        check(r["recordings"][0]["status"] == expected, "exact minimum retained duration boundary: " + str(samples))
        if expected == "unavailable":
            check(r["features"] == [] and r["artifacts"] == [], "short constant does not bypass input eligibility")

    values = np.r_[np.full(600, 1.), np.nan, np.full(600, 2.), np.full(600, 3.)]
    times = np.arange(len(values))/10
    times[1201:] += 3
    r = run_and_retain(request("segmentation", values, times=times))
    check([x["source_row_start"] for x in r["recordings"]] == [0, 601, 1201], "missing sample and measured gap split exact source rows")
    check([f["value"] for f in r["features"] if f["name"] == "conductance_raw_mean"] == [1., 2., 3.],
          "distinct constant levels retain distinct segment descriptions")
    check(r["quality"]["descriptive_channel_segments"] == 3 and r["quality"]["missing_channel_samples"] == 1,
          "segmentation quality counts agree with source")

    t = np.arange(1200)/10
    ordinary = 5 + .03*np.sin(t/3) + .2*np.exp(-((t-40)/2)**2)
    witnesses = {"next-float": np.resize([5., np.nextafter(5., np.inf)], len(t)),
                 "small-ramp": 5 + np.arange(len(t))*1e-12, "ordinary": ordinary}
    for name, x in witnesses.items():
        p0 = old.parameters("eda", {"recipe":"eda-neurokit-highpass/1.0"}, 10)
        p1 = worker.parameters("eda", {"recipe":"eda-neurokit-highpass/1.1"}, 10)
        before, after = old.eda(x.copy(), t.copy(), 10, p0), worker.eda(x.copy(), t.copy(), 10, p1)
        check(after.get("status") is None, name + " is not collapsed by a tolerance")
        check(before["features"] == after["features"] and before["events"] == after["events"] and before["support"] == after["support"],
              name + " preserves exact existing numerical features, events and support")
        check(all(np.array_equal(before["series"][k], after["series"][k]) for k in before["series"]),
              name + " preserves every original numerical array value")

    mixed = np.r_[np.full(600, 5.), np.nan, ordinary, np.nan, np.full(100, 0.)]
    mixed_result = run_and_retain(request("mixed-support", mixed))
    check([r["status"] for r in mixed_result["recordings"]] == ["descriptive_only", "computed", "unavailable"],
          "one result distinguishes descriptive, computed and too-short segments")
    check(mixed_result["status"] == "partial" and
          [mixed_result["quality"][k] for k in ("computed_channel_segments", "descriptive_channel_segments", "unavailable_channel_segments")] == [1,1,1],
          "mixed result quality counts reconcile independently")
    mixed_streams = retained_tables(mixed_result)
    mixed_specs = list(mixed_streams["physiology-series"][0].values())
    check(len(mixed_specs) == 2 and [s["columns"][2]["nullable"] for s in mixed_specs] == [True, False],
          "constant and ordinary tables keep distinct nullability within one complete stream")
    check(sum(len(rows) for rows in mixed_streams["physiology-series"][1].values()) == 1800,
          "only eligible segments contribute complete coordinate or processed rows")

    for supplied in ({"recipe":"eda-neurokit-highpass/1.2"},
                     {"recipe":"eda-neurokit-highpass/1.1", "exact_constant_policy":"invent-zero-responses"}):
        try:
            worker.parameters("eda", supplied, 10)
        except worker.InputError:
            check(True, "unknown recipe or adjustable constant policy refused")
        else:
            raise AssertionError("An unsupported method/policy was accepted")

    original_result = json.loads((out / "constant-3/result.json").read_text(encoding="utf-8"))
    source_support = original_result["recordings"][0]
    parameters = original_result["parameters"][source_support["recording_id"]]
    identity = {k:source_support[k] for k in ("recording_id", "segment_id", "channel", "group")}
    bundle = worker.eda(np.full(1500, 5.), np.arange(1500)/25, 25, parameters)
    provenance = tables.verify_artifact(original_result["artifacts"][0])["provenance"]
    for fault in ("legacy-status", "finite-substitute", "missing-denominator", "boolean-count", "source-boolean-count", "source-flatline-false", "conflicting-source"):
        bad, support = copy.deepcopy(bundle), copy.deepcopy(source_support)
        if fault == "legacy-status": bad["parameters"]["recipe"] = "eda-neurokit-highpass/1.0"
        elif fault == "finite-substitute": bad["series"]["clean_us"][0] = 0.
        elif fault == "missing-denominator": del bad["support"]["response_denominator"]
        elif fault == "boolean-count": bad["support"]["numerical_candidate_count"] = False
        elif fault == "source-boolean-count": support["numerical_candidate_count"] = False
        elif fault == "source-flatline-false": support["exact_flatline"] = False
        else: support["numerical_candidate_count"] = 1
        directory = out / ("malformed-" + fault)
        directory.mkdir()
        writers = tables.ArtifactSet(directory, provenance)
        try:
            try:
                tables.write_physiology_bundle(writers.series, writers.events, "eda", identity, bad, support, "s", "segment-1")
            except tables.ArtifactError:
                check(True, "malformed constant artifact refused: " + fault)
            else:
                raise AssertionError("Malformed artifact accepted: " + fault)
        finally:
            writers.abort()
        check(list(directory.iterdir()) == [], "malformed attempt leaves no partial artifact: " + fault)

    for name, x in {"legacy-flatline": np.full(1200, 5.), "legacy-ordinary": ordinary, "legacy-zero": np.zeros(1200)}.items():
        req = request(name, x, version="1.0", artifacts=False)
        before, after = old.run(req), run_and_retain(req)
        check(before == after, name + " complete 1.0 result remains exact")
    check({p:sha(repo/p) for p in source_files} == source_hashes and
          {p:sha(baseline/p) for p in source_files} == baseline_hashes, "candidate and original source files remained unchanged during checks")
    passed = True
except Exception as error:
    failure = {"type":type(error).__name__, "message":str(error)}
    raise
finally:
    receipt = dict(schema="brohn-eda-constant-producer-component/0.1", passed=passed,
                   source_hashes=source_hashes, baseline_hashes=baseline_hashes,
                   checks=checks, cases=cases, failure=failure,
                   native_publication=False, scientifically_qualified=False)
    (out / "results.json").write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(dict(passed=passed, checks=len(checks), cases=len(cases), failure=failure)))
