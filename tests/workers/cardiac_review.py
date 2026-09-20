"""Source-bound cardiac exclusion invariants and independent interval oracles."""
import copy
from decimal import Decimal
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("cardiac_review_test", ROOT / "scripts/workers/cardiac_review.py")
worker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(worker)
np = worker.np


def fixture(root, modality="ppg", fs=100, duration=60, change=None, groups=False):
    root.mkdir(parents=True, exist_ok=True)
    t = np.arange(fs * duration) / fs
    if modality == "ecg":
        x = .01 * np.sin(2 * np.pi * .17 * t)
        for peak in np.arange(.7, duration, .83):
            x += np.exp(-((t - peak) / .015)**2) - .2 * np.exp(-((t - peak - .035) / .018)**2)
    else:
        x = np.sin(2 * np.pi * 1.2 * t) + .2 * np.sin(2 * np.pi * 2.4 * t) + .02 * np.sin(2 * np.pi * .13 * t)
    if change:
        change(x)
    path = root / "source.csv"
    epoch = Decimal("999999999999999999.123")
    with path.open("w", encoding="utf-8") as stream:
        stream.write("clock,signal" + (",person" if groups else "") + "\n")
        for i, value in enumerate(x):
            stream.write(str(epoch + Decimal(i) * Decimal(1000) / Decimal(fs)) + "," + repr(float(value)) +
                         (",one" if groups else "") + "\n")
    metadata = {"time_column": "clock", "time_unit": "ms", "value_columns": ["signal"], "sampling_rate": fs,
        "unit": "mV" if modality == "ecg" else "a.u.", "origin": "sample"}
    if groups:
        metadata["participant_column"] = "person"
    parent_dir = root / "parent"
    parent_dir.mkdir()
    parent = worker.physiology.run({"schema": "brohn-worker-request/1.0", "operation": "physiology", "modality": modality,
        "source_path": str(path), "format": "csv", "metadata": metadata, "artifact_directory": str(parent_dir)})
    manifest = next(a for a in parent["artifacts"] if a["kind"] == "physiology-series")
    receipt = worker.artifacts.verify_manifest(parent["artifacts"])
    catalog = worker.views.catalog({"page": {"offset": 0, "limit": 100}}, manifest)
    return {"schema": "brohn-cardiac-review-request/1.0", "operation": "preview_cardiac_review", "policy": worker.POLICY,
        "source": {"sha256": worker.artifacts.digest_file(path), "bytes": path.stat().st_size}, "source_path": str(path),
        "format": "csv", "modality": modality, "metadata": metadata, "parameters": {}, "artifact": manifest,
        "verification_receipt": receipt, "table": catalog["tables"][0],
        "review_source": {"id": "review-fixture", "revision": 1, "hash": "c" * 64}, "spans": []}, parent


def span(lo, hi, ident="exclude-one", reason="movement_or_distortion"):
    return {"id": ident, "start_sample": lo, "end_sample": hi, "reason": reason, "note": "Independent boundary fixture"}


def artifact_rows(result, kind):
    values = {}
    for manifest in result["artifacts"]:
        if manifest["kind"] != kind:
            continue
        def table(t):
            values[t["table_id"]] = {"table": t, "rows": []}
        worker.artifacts.verify_artifact(manifest, on_table=table, on_rows=lambda tid, offset, rows: values[tid]["rows"].extend(rows))
    return values


class CardiacReview(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory(prefix="brohn-cardiac-exclusion-")
        cls.root = Path(cls.tmp.name)
        cls.ppg, cls.ppg_parent = fixture(cls.root / "ppg")
        cls.ecg, cls.ecg_parent = fixture(cls.root / "ecg", "ecg", 250)

    @classmethod
    def tearDownClass(cls):
        import gc
        gc.collect()
        cls.tmp.cleanup()

    def request(self, modality="ppg", operation="preview_cardiac_review"):
        r = copy.deepcopy(self.ecg if modality == "ecg" else self.ppg)
        r["operation"] = operation
        if operation == "reanalyse_cardiac":
            directory = self.root / (self.id().rsplit(".", 1)[-1] + "-" + modality)
            directory.mkdir(exist_ok=True)
            r["artifact_directory"] = str(directory)
        return r

    def test_preview_includes_exact_parent_edges_and_epoch_clock(self):
        result = worker.run(self.request())
        self.assertEqual(result["input_preview"]["coordinates"]["source_time_origin"], "999999999999999999.123")
        self.assertEqual([f["status"] for f in result["input_preview"]["fragments"]],
                         ["parent_filter_edge", "parent_retained", "parent_filter_edge"])
        pts = [p for f in result["input_preview"]["fragments"] for p in f["points"]]
        self.assertEqual(pts[0]["source_sample_index"], 0)
        self.assertEqual(pts[-1]["source_sample_index"], 5999)
        self.assertEqual(pts[-1]["time_s"], 59.99)
        self.assertEqual(result["ledger"]["support"]["input_samples"], 6000)

    def test_union_is_independently_counted_with_reasons_and_final_sample(self):
        r = self.request()
        r["spans"] = [span(2000, 2200), span(2190, 2300, "overlap"), span(2300, 2350, "adjacent"), span(5999, 6000, "final")]
        ledger = worker.run(r)["ledger"]
        oracle = set(range(2000, 2200)) | set(range(2190, 2300)) | set(range(2300, 2350)) | {5999}
        self.assertEqual(ledger["support"]["excluded_samples"], len(oracle))
        self.assertEqual(ledger["union"], [dict(start_sample=2000, end_sample=2350, span_ids=["exclude-one", "overlap", "adjacent"]),
                                         dict(start_sample=5999, end_sample=6000, span_ids=["final"])])
        self.assertEqual(ledger["spans"][-1]["first_time_s"], 59.99)
        self.assertEqual([(r["start_sample"], r["end_sample"]) for r in ledger["runs"]], [(0, 2000), (2350, 5999)])

    def test_decimal_time_resolution_uses_actual_source_grid_at_large_epoch(self):
        r = self.request()
        r["candidate"] = dict(id="proposed", start_time_s_text="0.3", end_time_s_text="0.31", reason="clipping", note="exact decimal edge")
        result = worker.run(r)
        x = result["resolved_exclusion"]
        self.assertEqual(x["span"], dict(id="proposed", start_sample=30, end_sample=31, reason="clipping", note="exact decimal edge"))
        self.assertEqual(Decimal(x["first_time_s_text"]), Decimal("0.3"))
        self.assertEqual(result["ledger"]["spans"], [])
        for start, end in [("-1", "1"), ("0", "60"), ("0.301", "0.302"), ("NaN", "1")]:
            r["candidate"].update(start_time_s_text=start, end_time_s_text=end)
            with self.subTest(start=start, end=end), self.assertRaises(ValueError):
                worker.run(r)

    def test_invalid_spans_are_refused(self):
        for bad in [span(-1, 2), span(0, 6001), span(2, 2), span(2.2, 4), span(True, 4), span(0, 1, reason="normal_beat")]:
            with self.subTest(bad=bad), self.assertRaises((ValueError, worker.InputError)):
                worker.normalize_spans([bad], 0, 6000, False)
        with self.assertRaises(ValueError):
            worker.normalize_spans([span(1, 2), span(2, 3)], 0, 6000, False)

    def test_recalculation_requires_an_explicit_exclusion(self):
        r = self.request(operation="reanalyse_cardiac")
        with self.assertRaisesRegex(ValueError, "1 to 64"):
            worker.run(r)

    def test_boundaries_empty_short_all_excluded_do_not_invent_zero_features(self):
        r = self.request(operation="reanalyse_cardiac")
        r["spans"] = [span(0, 6000)]
        output = worker.run(r)
        self.assertEqual(output["status"], "insufficient_support")
        self.assertEqual(output["features"], [])
        self.assertEqual(output["artifacts"], [])
        self.assertFalse(output["quality"]["usable"])
        self.assertFalse(output["quality"]["raw_source_duplicated"])
        r = self.request()
        r["spans"] = [span(100, 5900)]
        self.assertEqual([run["status"] for run in worker.run(r)["ledger"]["runs"]], ["insufficient_support"] * 2)

    def test_changed_source_bytes_refused(self):
        r = self.request()
        r["source"]["sha256"] = "a" * 64
        with self.assertRaisesRegex(ValueError, "byte/hash"):
            worker.run(r)

    def test_mapping_clock_person_and_method_substitutions_refused(self):
        changes = [lambda r: r["metadata"].update(unit="V"),
            lambda r: r["table"]["coordinates"].update(source_time_origin="0"),
            lambda r: r["table"]["identity"].update(group={"participant_id": "other"}),
            lambda r: r.update(parameters={"edge_exclusion_s": 3})]
        for change in changes:
            r = self.request()
            change(r)
            with self.subTest(r=r), self.assertRaises(ValueError):
                worker.run(r)

    def test_ecg_conversion_retains_canonical_values_exactly(self):
        source = worker.bind(self.request("ecg"))
        preview = worker.input_preview(source, worker.plan(self.request("ecg"), source))
        import csv
        with Path(self.ecg["source_path"]).open() as stream:
            values = [float(row["signal"]) * 1000 for row in csv.DictReader(stream)]
        for f in preview["fragments"]:
            for p in f["points"]:
                self.assertEqual(p["value"], values[p["source_sample_index"]])
        self.assertEqual(preview["unit"], "uV")

    def test_each_actual_run_matches_standalone_processing_and_exact_interval_oracle(self):
        for modality in ("ecg", "ppg"):
            with self.subTest(modality=modality):
                r = self.request(modality, "reanalyse_cardiac")
                fs = r["metadata"]["sampling_rate"]
                r["spans"] = [span(20 * fs, 23 * fs)]
                source = worker.bind(r)
                output = worker.run(r)
                self.assertEqual(output["quality"]["computed_channel_segments"], 2)
                series = artifact_rows(output, "physiology-series")
                events = artifact_rows(output, "physiology-events")
                for i, (lo, hi) in enumerate(((0, 20 * fs), (23 * fs, 60 * fs))):
                    separate = worker.physiology.cardiac(source["recording"]["values"][0, lo:hi],
                        source["recording"]["times"][lo:hi], fs, source["parameters"], modality)
                    tid = f"review-run-{i + 1}"
                    rows = series[tid + "-samples"]["rows"]
                    self.assertEqual([row[1] for row in rows], list(range(lo, hi)))
                    self.assertEqual([row[3] for row in rows], separate["series"]["clean"].tolist())
                    table = events[tid + "-events"]["table"]
                    names = [c["name"] for c in table["columns"]]
                    beats = [dict(zip(names, row)) for row in events[tid + "-events"]["rows"]]
                    self.assertGreater(len(beats), 10)
                    self.assertIsNone(beats[0]["previous_interval_ms"])
                    for a, b in zip(beats, beats[1:]):
                        self.assertEqual(b["previous_interval_ms"], (b["source_sample_index"] - a["source_sample_index"]) / fs * 1000)
                    intervals = [(b["source_sample_index"] - a["source_sample_index"]) / fs * 1000 for a, b in zip(beats, beats[1:])]
                    good = [300 <= v <= 2000 for v in intervals]
                    differences = [(b - a)**2 for a, b, ok1, ok2 in zip(intervals, intervals[1:], good, good[1:]) if ok1 and ok2]
                    prefix = "detected_rr" if modality == "ecg" else "detected_prv"
                    feature = next(f for f in output["features"] if f["segment_id"] == tid and f["name"] == prefix + "_rmssd")
                    self.assertAlmostEqual(feature["value"], (sum(differences) / len(differences))**.5, places=12)
                    spectrum = output["recordings"][i]["interval_spectrum"]
                    self.assertEqual(spectrum["status"], "unavailable")

    def test_extreme_excluded_values_do_not_influence_surviving_processing(self):
        r = self.request(operation="reanalyse_cardiac")
        r["spans"] = [span(2000, 2300)]
        original = worker.run(r)
        altered, _ = fixture(self.root / "altered", change=lambda x: x.__setitem__(slice(2000, 2300), np.linspace(-1e8, 1e8, 300)))
        altered.update(operation="reanalyse_cardiac", spans=copy.deepcopy(r["spans"]))
        target = self.root / "altered-output"
        target.mkdir()
        altered["artifact_directory"] = str(target)
        result = worker.run(altered)
        self.assertEqual(original["features"], result["features"])
        self.assertEqual(original["events"], result["events"])
        for kind in ("physiology-series", "physiology-events"):
            a, b = artifact_rows(original, kind), artifact_rows(result, kind)
            self.assertEqual({k: v["rows"] for k, v in a.items()}, {k: v["rows"] for k, v in b.items()})

    def test_one_sample_mask_never_reconnects_detector_or_intervals(self):
        r = self.request(operation="reanalyse_cardiac")
        r["spans"] = [span(3000, 3001)]
        calls = []
        original = worker.physiology.cardiac
        def spy(x, t, fs, p, modality):
            calls.append((float(t[0]), float(t[-1]), len(x)))
            return original(x, t, fs, p, modality)
        with patch.object(worker.physiology, "cardiac", side_effect=spy):
            result = worker.run(r)
        self.assertEqual(calls, [(0., 29.99, 3000), (30.01, 59.99, 2999)])
        for item in artifact_rows(result, "physiology-events").values():
            self.assertIsNone(item["rows"][0][4])


if __name__ == "__main__":
    unittest.main()
