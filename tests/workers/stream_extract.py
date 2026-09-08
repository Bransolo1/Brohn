"""Original synthetic stream curation fixtures; no physical device evidence."""
import copy
import csv
import hashlib
import importlib.util
import json
import math
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("extract", ROOT / "scripts/workers/stream_extract.py")
worker = importlib.util.module_from_spec(spec); spec.loader.exec_module(worker)


def original_rows(count=1000, rate=100):
    return [{"sequence": i+1, "stream_id": "original-eeg", "segment_id": "original-segment-1", "clock_id": "original-device-clock",
             "timestamp_unit": "ns", "source_timestamp": str(9007199254740993 + i*int(1e9/rate)), "timestamp_state": "observed",
             "timestamp_ieee754_le_hex": None, "reconstructed_timestamp": False,
             "time_since_segment_start_s": str(i/rate), "identity": {"participant_id": "original-person", "session_id": "original-visit"},
             "values": {"eeg": 20*math.sin(2*math.pi*10*i/rate)}, "value_states": {"eeg": "observed"}} for i in range(count)]


def original_request(directory, rows=None):
    rows = original_rows() if rows is None else rows
    source = directory / "source" / "original.jsonl"; source.parent.mkdir(exist_ok=True)
    source.write_text("".join(json.dumps(r, allow_nan=False)+"\n" for r in rows), encoding="utf-8")
    return {"schema": "brohn-stream-extract-request/1.0", "operation": "extract_stream", "source_path": str(source), "source_hash": worker.digest(source),
            "stream": {"schema": "brohn-imported-stream/1.0", "id": "original-eeg", "kind": "signal", "sample_count": len(rows), "nominal_srate": 100,
                "clock": {"id": "original-device-clock", "unit": "ns", "kind": "device", "representation": "decimal_string"},
                "channels": [{"id": "eeg", "label": "Original EEG", "type": "EEG", "unit": "uV", "value_type": "float64"}]},
            "selection": {"schema": "brohn-stream-selection/1.0", "channel_ids": ["eeg"], "modality": "eeg", "unit": "V", "sampling_rate": 100,
                "participant_id": None, "session_id": None, "origin_statement": "Original generated 10 Hz source; no person or device.",
                "unit_rationale": "Generator amplitude is declared in microvolts; explicit volts conversion.", "confirm_source_units": True, "confirm_boundaries": True, "run_analysis": False},
            "output_directory": str(directory / "artifacts")}


def bundle_fixture():
    rows = original_rows()
    samples = [{"timestamp": r["source_timestamp"], "values": [r["values"]["eeg"]]} for r in rows]
    return {"schema": "brohn-stream-bundle/1.0", "origin": "sample", "streams": [{"id": "original-eeg", "name": "Original 10 Hz EEG", "type": "EEG", "kind": "signal",
        "source_id": "original-generator", "uid": "original-eeg-uid", "clock": {"id": "original-device-clock", "unit": "ns", "kind": "device", "representation": "decimal_string"},
        "nominal_srate": 100, "identity": {"participant_id": "original-person", "session_id": "original-visit"},
        "channels": [{"id": "eeg", "label": "Original EEG", "type": "EEG", "unit": "uV", "value_type": "float64"}], "samples": samples}]}


class ExtractionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="brohn-stream-extract-"); self.root = Path(self.temp.name)
    def tearDown(self): self.temp.cleanup()
    def run_fixture(self, rows=None, adjust=None):
        request = original_request(self.root, rows)
        if adjust: adjust(request)
        return request, worker.extract(request)
    def csv_rows(self, result):
        artifact = next(a for a in result["artifacts"] if a["kind"] == "curated_signal_csv")
        with Path(artifact["path"]).open(encoding="utf-8", newline="") as stream: return list(csv.DictReader(stream))
    def decisions(self, result):
        artifact = next(a for a in result["artifacts"] if a["kind"] == "curation_decisions_jsonl")
        return [json.loads(x) for x in Path(artifact["path"]).read_text().splitlines()]
    def test_exact_clock_units_and_original_rows(self):
        request, result = self.run_fixture()
        rows = self.csv_rows(result)
        self.assertEqual(result["quality"]["included_rows"], 1000)
        self.assertEqual(rows[0]["source_timestamp"], "9007199254740993")
        self.assertEqual(rows[1]["brohn_time_s"], "0.010000000")
        self.assertAlmostEqual(float(rows[1]["value_eeg"]), 20e-6*math.sin(.2*math.pi), places=15)
        self.assertEqual(worker.digest(request["source_path"]), request["source_hash"])
        self.assertEqual(len(self.decisions(result)), 1000)
        self.assertEqual(result["metadata"]["segment_column"], "brohn_segment_id")
        self.assertNotIn("exposure_column", result["metadata"])
    def test_independent_10hz_spectrum(self):
        _, result = self.run_fixture(); rows = self.csv_rows(result)
        values = [float(row["value_eeg"]) for row in rows]
        amplitude = 2/len(values)*abs(sum(value*complex(math.cos(-2*math.pi*10*i/100), math.sin(-2*math.pi*10*i/100)) for i, value in enumerate(values)))
        self.assertAlmostEqual(amplitude, 20e-6, places=14)
        self.assertAlmostEqual(sum(x*x for x in values)/len(values), 2e-10, places=20)
    def test_reset_and_identity_are_separate_fields(self):
        rows = original_rows(6)
        for i in range(3,6):
            rows[i]["source_timestamp"] = str(1000+(i-3)*10000000)
            rows[i]["segment_id"] = "original-clock-reset"
        request, result = self.run_fixture(rows)
        output = self.csv_rows(result)
        self.assertEqual(result["quality"]["segment_count"], 2)
        self.assertNotEqual(output[0]["brohn_segment_id"], output[3]["brohn_segment_id"])
        self.assertEqual(output[0]["brohn_session_id"], output[3]["brohn_session_id"])
        self.assertEqual(output[0]["brohn_participant_id"], output[3]["brohn_participant_id"])
        self.assertEqual(output[3]["source_timestamp"], "1000")
    def test_source_gaps_split_without_interpolation(self):
        rows = original_rows(6)
        for row in rows[3:]: row["source_timestamp"] = str(int(row["source_timestamp"])+1000000000)
        _, result = self.run_fixture(rows)
        self.assertEqual(result["quality"]["segment_count"], 2)
        self.assertEqual(result["quality"]["included_rows"], 6)
        self.assertIn("source_sampling_gap", result["segments"][1]["boundary_reasons"])
    def test_listwise_missingness_preserves_full_decisions(self):
        rows = original_rows(7)
        rows[2]["values"]["eeg"] = None; rows[2]["value_states"]["eeg"] = "nan"
        rows[4]["source_timestamp"] = None; rows[4]["timestamp_state"] = "missing"
        _, result = self.run_fixture(rows)
        self.assertEqual(result["quality"]["included_rows"], 5)
        self.assertEqual(result["quality"]["excluded_rows"], 2)
        self.assertEqual(result["quality"]["segment_count"], 3)
        self.assertEqual(len(self.decisions(result)), 7)
        self.assertEqual([x["source_sequence"] for x in self.decisions(result) if x["disposition"] == "excluded"], [3,5])
    def test_no_source_id_overwrite(self):
        def adjust(request): request["selection"].update(participant_id="replacement-is-not-used", session_id="replacement-is-not-used")
        _, result = self.run_fixture(adjust=adjust)
        self.assertEqual(result["segments"][0]["group"]["participant_id"], "original-person")
        self.assertEqual(result["segments"][0]["group"]["session_id"], "original-visit")
    def test_missing_identity_requires_explicit_declaration(self):
        rows = original_rows(3)
        for row in rows: row["identity"] = {}
        with self.assertRaisesRegex(worker.InputError, "participant/session"): self.run_fixture(rows)
        _, result = self.run_fixture(rows, lambda request: request["selection"].update(participant_id="declared-person",session_id="declared-visit"))
        self.assertEqual(result["segments"][0]["group"]["participant_id"], "declared-person")
    def test_numeric_string_is_not_float_measurement(self):
        rows = original_rows(3); rows[1]["values"]["eeg"] = "1"
        with self.assertRaisesRegex(worker.InputError, "numeric type"): self.run_fixture(rows)
    def test_boolean_is_not_measurement(self):
        rows = original_rows(3); rows[1]["values"]["eeg"] = True
        with self.assertRaisesRegex(worker.InputError, "numeric type"): self.run_fixture(rows)
    def test_unsafe_int64_remains_typed_source(self):
        rows = original_rows(3)
        for row in rows: row["values"]["eeg"] = "9007199254740993"
        with self.assertRaisesRegex(worker.InputError, "binary64 precision"):
            self.run_fixture(rows, lambda request: request["stream"]["channels"][0].update(value_type="int64"))
    def test_irregular_rate_rejects_without_resampling(self):
        rows = original_rows(4); rows[2]["source_timestamp"] = str(int(rows[2]["source_timestamp"])+1000000)
        with self.assertRaisesRegex(worker.InputError, "does not resample"): self.run_fixture(rows)
    def test_markers_and_nonidentity_calibration_reject(self):
        with self.assertRaisesRegex(worker.InputError, "analogue signal"):
            self.run_fixture(adjust=lambda request: request["stream"].update(kind="markers"))
        with self.assertRaisesRegex(worker.InputError, "calibration scaling"):
            self.run_fixture(adjust=lambda request: request["stream"]["channels"][0].update(scale="2"))
    def test_unknown_units_require_review_rationale(self):
        def adjust(request): request["stream"]["channels"][0]["unit"] = None
        _, result = self.run_fixture(adjust=adjust)
        self.assertEqual(result["parameters"]["unit_conversions"][0]["basis"], "researcher_declared_missing_source_unit")
        def blank(request): adjust(request); request["selection"]["unit_rationale"] = ""
        with self.assertRaisesRegex(worker.InputError, "rationale"): self.run_fixture(adjust=blank)
    def test_source_hash_and_count_mismatch_reject(self):
        with self.assertRaisesRegex(worker.InputError, "SHA-256"): self.run_fixture(adjust=lambda request: request.update(source_hash="0"*64))
        with self.assertRaisesRegex(worker.InputError, "row count"): self.run_fixture(adjust=lambda request: request["stream"].update(sample_count=1001))
    def test_no_usable_rows_returns_support_evidence(self):
        rows = original_rows(3)
        for row in rows: row["values"]["eeg"] = None; row["value_states"]["eeg"] = "missing"
        _, result = self.run_fixture(rows)
        self.assertEqual(result["status"], "needs_attention")
        self.assertEqual(result["quality"]["excluded_rows"], 3)
        self.assertFalse(result["quality"]["dataset_eligible"])
        self.assertEqual(self.csv_rows(result), [])


if __name__ == "__main__": unittest.main()
