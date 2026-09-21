"""Independent interval arithmetic and exact source/boundary rejection cases."""
import copy
import hashlib
import importlib.util
import json
import math
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("signal_windows", ROOT / "scripts/workers/signal_windows.py")
worker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(worker)
spec2 = importlib.util.spec_from_file_location("original_signal_fixture", ROOT / "tests/workers/signal_preview.py")
fixtures = importlib.util.module_from_spec(spec2)
spec2.loader.exec_module(fixtures)


class Windows(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="brohn-signal-window-tests-")
        self.root = Path(self.temporary.name)
        self.builder = fixtures.Preview()
        self.builder.root = self.root

    def tearDown(self):
        self.temporary.cleanup()

    def request(self, values=None, **table_options):
        table = self.builder.table(values=values or [2, 4, 6, 8, 10, 12], **table_options)
        if "times" in table_options and None in table_options["times"]:
            table["specification"][0]["nullable"] = True
        original = self.builder.artifact([table])
        return {"schema": "brohn-signal-window-request/1.0", "artifact": original["artifact"],
                "verification_receipt": original["verification_receipt"],
                "annotation_source": {"id": "original-intervals", "revision": 1, "hash": "c"*64},
                "selection": {"table_id": table["table_id"], "identity": table["identity"], "coordinates": table["coordinates"], "value_columns": ["measure"]},
                "intervals": [{"id": "baseline", "label": "Before", "category": "baseline", "start_s": 0, "end_s": 3, "note": "Original fixture"},
                              {"id": "task", "label": "During", "category": "task", "start_s": 3, "end_s": 6, "note": ""}]}

    def test_independent_arithmetic_and_adjacent_half_open_boundaries(self):
        result = worker.run(self.request())
        before, during = result["summaries"]
        self.assertEqual((before["mean"], during["mean"]), (4, 10))
        self.assertEqual((before["eligible_rows"], during["eligible_rows"]), (3, 3))
        self.assertEqual((before["standard_deviation_sample"], during["standard_deviation_sample"]), (2, 2))
        self.assertEqual((before["minimum"], before["maximum"], during["minimum"], during["maximum"]), (2, 6, 8, 12))
        self.assertEqual((before["last_time_s"], during["first_time_s"]), (2, 3))
        self.assertEqual(result["table"]["coordinates"]["source_time_origin"], "99999999999999999")

    def test_pupil_trace_cannot_inherit_generic_sample_mean_policy(self):
        table = self.builder.table([4, -1, 6])
        table["support"]["trace_profile"] = "gaze-pupil-source-trace/1.0"
        original = self.builder.artifact([table])
        request = {"schema": "brohn-signal-window-request/1.0", "artifact": original["artifact"],
                   "verification_receipt": original["verification_receipt"],
                   "annotation_source": {"id": "fixture", "revision": 1, "hash": "c"*64},
                   "selection": {"table_id": table["table_id"], "identity": table["identity"],
                                 "coordinates": table["coordinates"], "value_columns": ["measure"]},
                   "intervals": [{"id": "whole", "label": "Whole", "category": "task",
                                  "start_s": 0, "end_s": 3, "note": ""}]}
        with self.assertRaisesRegex(worker.artifacts.ArtifactError, "separate validity and baseline policies"):
            worker.run(request)

    def test_missing_excluded_and_real_zero_remain_distinct(self):
        request = self.request([0, None, 100, 2, 4, 6], retained=[True, True, False, True, True, True])
        row = worker.run(request)["summaries"][0]
        self.assertEqual((row["selected_rows"], row["eligible_rows"], row["missing_value_rows"], row["excluded_support_rows"]), (3, 1, 1, 1))
        self.assertEqual(row["mean"], 0)
        self.assertIsNone(row["standard_deviation_sample"])

    def test_empty_interval_never_fabricates_zero_or_coverage(self):
        request = self.request()
        request["intervals"][0].update(start_s=80, end_s=90)
        row = worker.run(request)["summaries"][0]
        self.assertEqual((row["status"], row["selected_rows"]), ("no_eligible_samples", 0))
        for name in ("mean", "minimum", "maximum", "standard_deviation_sample", "first_value", "last_value"):
            self.assertIsNone(row[name])

    def test_overlapping_intervals_are_explicit_not_collapsed(self):
        request = self.request()
        request["intervals"][1].update(start_s=1, end_s=4)
        rows = worker.run(request)["summaries"]
        self.assertEqual([r["mean"] for r in rows], [4, 6])
        self.assertEqual([r["eligible_rows"] for r in rows], [3, 3])

    def test_missing_coordinates_cannot_enter_an_interval(self):
        result = worker.run(self.request(times=[0, 1, None, 3, 4, 5]))
        self.assertEqual(result["table_support"]["missing_coordinate_rows"], 1)
        self.assertEqual(result["summaries"][0]["eligible_rows"], 2)
        self.assertEqual(result["summaries"][0]["mean"], 3)

    def test_clock_person_measure_table_and_artifact_substitution_rejected(self):
        original = self.request()
        candidates = []
        for key, value in (("table_id", "absent"), ("value_columns", ["unregistered"])):
            altered = copy.deepcopy(original); altered["selection"][key] = value; candidates.append(altered)
        altered = copy.deepcopy(original); altered["selection"]["coordinates"]["source_time_origin"] = "99999999999999998"; candidates.append(altered)
        altered = copy.deepcopy(original); altered["selection"]["identity"]["group"]["participant_id"] = "someone-else"; candidates.append(altered)
        altered = copy.deepcopy(original); altered["artifact"]["sha256"] = "d"*64; candidates.append(altered)
        for candidate in candidates:
            with self.subTest(selection=candidate["selection"]):
                with self.assertRaises(worker.artifacts.ArtifactError): worker.run(candidate)

    def test_frequency_is_not_relabelled_as_time(self):
        with self.assertRaises(worker.artifacts.ArtifactError):
            worker.run(self.request(axis="frequency"))

    def test_reversed_duplicate_coordinates_and_nonfinite_bounds_rejected(self):
        request = self.request(times=[0, 1, 1, 3, 4, 5])
        with self.assertRaises(worker.artifacts.ArtifactError): worker.run(request)
        for bounds in ((4, 2), (1, 1), (0, float("inf")), (True, 3)):
            altered = copy.deepcopy(request); altered["intervals"][0].update(start_s=bounds[0], end_s=bounds[1])
            with self.assertRaises(worker.artifacts.ArtifactError): worker.run(altered)

    def test_full_original_rows_not_plot_envelope(self):
        values = [1.0]*1001; values[501] = 101.0
        request = self.request(values)
        request["intervals"] = [dict(id="all", label="All original rows", category="task", start_s=0, end_s=1001, note="")]
        row = worker.run(request)["summaries"][0]
        self.assertEqual(row["eligible_rows"], 1001)
        self.assertAlmostEqual(row["mean"], 1101/1001, places=13)
        self.assertEqual(row["maximum"], 101)

    def test_independent_multi_measure_units_and_values(self):
        t = self.builder.table([2, 4, 6, 8])
        t["specification"].append(worker.artifacts._column("other", "float64", "mV", True))
        t["arrays"]["other"] = [10, 30, None, 50]
        original = self.builder.artifact([t])
        request = {"schema": "brohn-signal-window-request/1.0", "artifact": original["artifact"], "verification_receipt": original["verification_receipt"],
                   "selection": dict(table_id=t["table_id"], identity=t["identity"], coordinates=t["coordinates"], value_columns=["measure", "other"]),
                   "annotation_source": dict(id="a", revision=1, hash="a"*64),
                   "intervals": [dict(id="i", label="Signal", category="", start_s=0, end_s=4, note="") ]}
        rows = worker.run(request)["summaries"]
        self.assertEqual([r["mean"] for r in rows], [5, 30])
        self.assertEqual([r["unit"] for r in rows], ["uS", "mV"])
        self.assertEqual([r["eligible_rows"] for r in rows], [4, 3])

    def test_request_limits_and_unknown_settings_are_not_silently_ignored(self):
        request = self.request()
        for change in (dict(extra="ignored?"), dict(intervals=[]), dict(intervals=request["intervals"]*33)):
            altered = copy.deepcopy(request); altered.update(change)
            with self.assertRaises(worker.artifacts.ArtifactError): worker.run(altered)

    def test_real_cli_preserves_source_and_existing_output(self):
        request = self.request()
        source = Path(request["artifact"]["path"])
        original = hashlib.sha256(source.read_bytes()).hexdigest()
        input_path, output = self.root/"request.json", self.root/"summary.json"
        input_path.write_text(json.dumps(request), encoding="utf-8")
        command = [sys.executable, str(ROOT/"scripts/workers/signal_windows.py"), "--request", str(input_path), "--output", str(output)]
        completed = subprocess.run(command, capture_output=True, timeout=30)
        self.assertEqual(completed.returncode, 0, completed.stderr)
        self.assertEqual(json.loads(output.read_text(encoding="utf-8"))["summaries"][1]["mean"], 10)
        previous = output.read_bytes()
        self.assertNotEqual(subprocess.run(command, capture_output=True, timeout=30).returncode, 0)
        self.assertEqual(output.read_bytes(), previous)
        self.assertEqual(hashlib.sha256(source.read_bytes()).hexdigest(), original)


if __name__ == "__main__":
    unittest.main()
