"""Independent saved-value constructions; no respiration detector in these oracles."""
import copy
import csv
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import io
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts/workers"))
import respiration_review as reader
import physiology_artifacts as tables


def fixture(folder, change=None, empty=False, event_clock="s"):
    folder = Path(folder)
    folder.mkdir(parents=True, exist_ok=True)
    fs = 50
    rows = []
    for i in range(6001):
        t = i / fs
        phase = t % 5
        value = phase / 2 if phase <= 2 else (5 - phase) / 3
        rows.append(dict(time_s=t, source_sample_index=i + 1000, clean=value, retained=5 <= t <= 115))
    cycles = [] if empty else [dict(type="respiration_cycle", time_s=float(start), peak_time_s=float(start + 2),
        end_time_s=float(start + 5), duration_s=5.0, inspiration_s=2.0, expiration_s=3.0, amplitude=1.0) for start in range(10, 105, 5)]
    if change:
        change(rows, cycles)
    original = folder / "original-negative-volume.csv"
    with original.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.writer(stream)
        writer.writerow(["time", "signed_original_volume"])
        writer.writerows((row["time_s"], -row["clean"]) for row in rows)
    group = dict(participant_id="original-hand-person", session_id="original-hand-session")
    identity = dict(recording_id="recording-1", segment_id="recording-1-segment-1", channel="volume", group=group)
    parameters = dict(recipe="respiration-displacement-khodadad/1.0", source_quantity="lung_volume", polarity="negative_inspiration",
                      source_polarity_multiplier=-1, mapping_source="Original inverted synthetic volume; hand-labelled extrema", edge_exclusion_s=5)
    recording = dict(**identity, status="computed", source_time_origin="1750000000000000000", source_row_start=1000,
        source_row_end_exclusive=7001, samples=6001, sampling_rate=fs, start_time_s=0, end_time_s=120,
        unit="L", source_unit="L", scale_factor=1, complete_cycle_count=len(cycles))
    support = dict(source=recording, method=parameters, retained_support=dict(complete_cycle_count=len(cycles)), raw_source_omitted=True)
    coordinate = dict(axis="time", reference="seconds relative to original recording start; no source timestamp rebasing",
                      source_time_origin=recording["source_time_origin"], source_time_unit="s")
    provenance = dict(source_sha256=tables.digest_file(original), engine=dict(name="Independent hand construction", worker_sha256=tables.digest_file(Path(__file__))), operation="physiology", origin="sample", parameters=parameters)
    def col(name, kind, unit, role="measure"):
        return dict(name=name, type=kind, unit=unit, nullable=False, role=role)
    sample_fields = [col("time_s", "float64", "s", "coordinate"), col("source_sample_index", "integer", "sample_index", "index"),
                     col("clean", "float64", "L"), col("retained", "boolean", None, "support")]
    series = tables.TableWriter(folder, "physiology-series", provenance, preview_limit=0)
    series.write_table("original-volume-samples", identity, sample_fields, coordinate, support, rows, len(rows))
    # A second source-channel table must not leak into selected values/identity.
    series.write_table("other-channel-samples", {**identity, "channel": "other"}, sample_fields, coordinate, support, rows[:3], 3)
    a = series.finish()
    event_fields = [col("type", "string", None, "label"), *[col(k, "float64", "s", "coordinate" if k == "time_s" else "measure") for k in reader.EVENT_FIELDS if k not in ("type", "amplitude")], col("amplitude", "float64", "L")]
    events = tables.TableWriter(folder, "physiology-events", provenance, preview_limit=0)
    events.write_table("original-volume-cycles", identity, event_fields, {**coordinate, "axis": "event", "source_time_unit": event_clock}, support, cycles, len(cycles))
    b = events.finish()
    export = folder / "exports"
    export.mkdir()
    request = dict(schema="brohn-respiration-review-request/1.0", binding=dict(origin="sample", report_id="original-saved-report"),
        recording=recording, parameters=parameters, selection={**{k: identity[k] for k in reader.IDENTITY}, "start_s": "0", "end_s": "120"},
        original_source=dict(path=str(original), hash=tables.digest_file(original), bytes=original.stat().st_size), sealed_objects=[],
        artifacts=[a, b], export_directory=str(export))
    return request, rows, cycles


class Review(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="brohn-respiration-reader-")
        self.root = Path(self.temp.name)
        self.request, self.rows, self.cycles = fixture(self.root)
    def tearDown(self):
        self.temp.cleanup()
    def run_review(self):
        return reader.review(self.request)
    def test_complete_values_cycles_and_indices(self):
        result = self.run_review()
        with (self.root / "exports/respiration-samples.csv").open(encoding="utf-8") as stream:
            rows = list(csv.DictReader(stream))
        self.assertEqual(len(rows), 6001)
        for i, row in enumerate(rows):
            self.assertEqual(int(row["source_sample_index"]), i + 1000)
            self.assertEqual(float(row["time_s"]), self.rows[i]["time_s"])
            self.assertEqual(float(row["clean"]), self.rows[i]["clean"])
            self.assertEqual(row["retained"], str(self.rows[i]["retained"]).lower())
        self.assertEqual(result["counts"]["complete_sample_artifact_rows"], 6004)
        self.assertEqual(result["counts"]["segment_samples"], 6001)
        self.assertEqual(result["counts"]["selected_cycles"], 19)
        self.assertEqual(result["counts"]["retained_samples"], 5501)
        for i, cycle in enumerate(result["cycles"]):
            self.assertEqual({k: cycle[k] for k in reader.EVENT_FIELDS}, self.cycles[i])
            self.assertEqual(cycle["table_row_index"], i)
        self.assertEqual(result["parameters"]["source_polarity_multiplier"], -1)
        self.assertEqual(result["source_tables"][0]["coordinates"]["source_time_origin"], "1750000000000000000")
        for artifact in result["exports"]:
            self.assertEqual(tables.digest_file(self.root / "exports" / artifact["name"]), artifact["hash"])
    def test_actual_extrema_preview_and_support_breaks(self):
        result = self.run_review()
        self.assertEqual([x["retained"] for x in result["series"]], [False, True, False])
        self.assertLess(sum(len(x["points"]) for x in result["series"]), 1300)
        for group in result["series"]:
            indices = [p["source_sample_index"] for p in group["points"]]
            self.assertEqual(indices, sorted(set(indices)))
            for point in group["points"]:
                self.assertEqual(point["clean"], self.rows[point["source_sample_index"] - 1000]["clean"])
        for marker in result["markers"]:
            row = self.rows[marker["source_sample_index"] - 1000]
            self.assertEqual(marker["clean"], row["clean"])
            self.assertEqual(marker["time_s"], row["time_s"])
            self.assertTrue(marker["retained"])
    def test_partial_cycle_retains_complete_saved_metrics(self):
        self.request["selection"].update(start_s="11.000000000000000001", end_s="12.000000000000000001")
        result = self.run_review()
        self.assertEqual(result["counts"]["selected_samples"], 50)
        self.assertEqual(len(result["cycles"]), 1)
        self.assertEqual(result["cycles"][0]["duration_s"], 5)
        self.assertEqual([m["in_view"] for m in result["markers"]], [False, True, False])
        self.assertEqual([m["time_s"] for m in result["markers"]], [10, 12, 15])
    def test_empty_window_has_no_invented_zero_rate(self):
        self.request["selection"].update(start_s="121", end_s="122")
        result = self.run_review()
        self.assertEqual(result["status"], "no_processed_samples")
        self.assertEqual(result["cycles"], [])
        self.assertNotIn("respiration_rate", result)
        self.assertEqual(result["exports"][0]["rows"], 0)
    def test_empty_detected_cycles_keep_source_and_support(self):
        self.request, _, _ = fixture(self.root / "none", empty=True)
        result = self.run_review()
        self.assertEqual(result["status"], "available")
        self.assertEqual(result["counts"]["selected_cycles"], 0)
        self.assertEqual(result["counts"]["selected_samples"], 6001)
    def test_foreign_source_or_origin_is_rejected(self):
        self.request["binding"]["origin"] = "live"
        with self.assertRaises(tables.ArtifactError): self.run_review()
    def test_invalid_selection_quantity_or_effective_parameters(self):
        for mutate in (lambda r: r["selection"].update(channel="different"), lambda r: r["parameters"].update(source_quantity="airflow"),
                       lambda r: r["parameters"].update(source_polarity_multiplier=1), lambda r: r["selection"].update(start_s="NaN"),
                       lambda r: r["selection"].update(end_s="0"), lambda r: r["recording"].update(complete_cycle_count=18)):
            with self.subTest(mutation=mutate):
                modified = copy.deepcopy(self.request)
                mutate(modified)
                with self.assertRaises(tables.ArtifactError): reader.review(modified)
    def test_changed_original_and_retained_report_are_rejected(self):
        report = self.root / "report.json"
        report.write_text("original", encoding="utf-8")
        self.request["sealed_objects"] = [dict(path=str(report), hash=tables.digest_file(report), bytes=report.stat().st_size)]
        report.write_text("modified", encoding="utf-8")
        with self.assertRaises(tables.ArtifactError): self.run_review()
        self.request["sealed_objects"] = []
        Path(self.request["original_source"]["path"]).write_text("changed", encoding="utf-8")
        with self.assertRaises(tables.ArtifactError): self.run_review()
    def test_changed_artifact_is_rejected(self):
        manifest = self.request["artifacts"][0]
        Path(manifest["path"]).write_bytes(Path(manifest["path"]).read_bytes() + b" ")
        with self.assertRaises(tables.ArtifactError): self.run_review()
    def test_phase_duration_and_amplitude_are_exact_saved_source_checks(self):
        for key in ("duration_s", "inspiration_s", "expiration_s", "amplitude"):
            with self.subTest(key=key):
                req, _, _ = fixture(self.root / key, lambda rows, cycles: cycles[0].update({key: 1.234}))
                with self.assertRaises(tables.ArtifactError): reader.review(req)
    def test_nonexistent_or_excluded_marker_sample_is_rejected(self):
        for name, mutate in (("off-grid", lambda rows, cycles: cycles[0].update(peak_time_s=12.001)),
                             ("excluded", lambda rows, cycles: rows[600].update(retained=False)),
                             ("row-index", lambda rows, cycles: rows[600].update(source_sample_index=123456))):
            with self.subTest(name=name):
                req, _, _ = fixture(self.root / name, mutate)
                with self.assertRaises(tables.ArtifactError): reader.review(req)
    def test_sample_and_cycle_bounds_refuse_truncation(self):
        with patch.object(reader, "MAX_SAMPLES", 500):
            with self.assertRaises(tables.ArtifactError): self.run_review()
        with patch.object(reader, "MAX_CYCLES", 2):
            with self.assertRaises(tables.ArtifactError): self.run_review()
    def test_clock_gap_inside_one_segment_cannot_be_drawn_as_continuous(self):
        def gap(rows, cycles):
            for row in rows[3000:]: row["time_s"] += 1
        request, _, _ = fixture(self.root / "gap", gap)
        with self.assertRaisesRegex(tables.ArtifactError, "gap"):
            reader.review(request)
    def test_event_waveform_clock_declarations_must_match(self):
        request, _, _ = fixture(self.root / "wrong-clock", event_clock="ms")
        with self.assertRaisesRegex(tables.ArtifactError, "clock declarations"):
            reader.review(request)
    def test_output_collision_keeps_existing_file(self):
        path = self.root / "exports/respiration-samples.csv"
        path.write_text("original", encoding="utf-8")
        with self.assertRaises(FileExistsError): self.run_review()
        self.assertEqual(path.read_text(), "original")
    def test_actual_cli_and_duplicate_request(self):
        request_path, output = self.root / "request.json", self.root / "result.json"
        request_path.write_text(json.dumps(self.request), encoding="utf-8")
        command = [sys.executable, str(ROOT / "scripts/workers/respiration_review.py"), "--request", str(request_path), "--output", str(output)]
        child = subprocess.run(command, capture_output=True, text=True, timeout=30)
        self.assertEqual(child.returncode, 0, child.stderr)
        result = json.loads(output.read_text())
        self.assertEqual(result["counts"]["selected_samples"], 6001)
        duplicate = self.root / "duplicate.json"
        duplicate.write_text('{"schema":"x","schema":"y"}', encoding="utf-8")
        with self.assertRaises(tables.ArtifactError): reader.load_request(duplicate)
        self.assertEqual(subprocess.run(command, capture_output=True, timeout=30).returncode, 1)
        self.assertEqual(json.loads(output.read_text()), result)


if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "--fixture":
        directory = Path(sys.argv[2])
        request, _, _ = fixture(directory)
        (directory / "fixture.json").write_text(json.dumps(request, ensure_ascii=True, indent=2), encoding="utf-8")
        print(str(directory / "fixture.json"))
    elif len(sys.argv) == 3 and sys.argv[1] == "--evidence":
        directory = Path(sys.argv[2])
        directory.mkdir(parents=True, exist_ok=False)
        stream = io.StringIO()
        suite = unittest.defaultTestLoader.loadTestsFromTestCase(Review)
        result = unittest.TextTestRunner(stream=stream, verbosity=2).run(suite)
        (directory / "test-output.txt").write_text(stream.getvalue(), encoding="utf-8")
        files = [Path(__file__), ROOT / "scripts/workers/respiration_review.py", ROOT / "scripts/workers/physiology_artifacts.py"]
        (directory / "results.json").write_text(json.dumps(dict(status="passed" if result.wasSuccessful() else "failed", checks=result.testsRun,
            failures=len(result.failures), errors=len(result.errors), hashes={str(p.relative_to(ROOT)): tables.digest_file(p) for p in files}), indent=2), encoding="utf-8")
        print(stream.getvalue())
        sys.exit(0 if result.wasSuccessful() else 1)
    else:
        unittest.main()
