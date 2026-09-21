"""Independent complete-stream, range, identity and refusal cases for pupil traces."""
import copy
import json
from pathlib import Path
import sys
import tempfile
import tracemalloc
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "scripts" / "workers"))
import gaze_trace as g


class GazeTrace(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="brohn-gaze-trace-worker-")
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.artdir = self.root / "artifacts"
        self.artdir.mkdir()
        self.provenance = {"source_sha256": "a" * 64, "engine": {"name": "independent fixture", "worker_sha256": "b" * 64},
                           "operation": "gaze", "origin": "synthetic", "parameters": {"trace_profile": g.PROFILE}}

    def fixture(self, count=3):
        identity = {"recording_id": "person-session-exposure", "channel": "pupil", "participant_id": "person", "session_id": "session", "exposure_id": "exposure", "stimulus_id": "stimulus"}
        support = {"trace_profile": g.PROFILE, "blink_boundary_policy": g.POLICY,
                   "generic_line_preview": "forbidden_use_dedicated_gaze_adapter", "pupil_unit": "mm",
                   "time_start_ms": 0, "time_end_ms": (count - 1)*10, "baseline": {"status": "not_requested"},
                   "initial_window": {"start_ms": 0, "end_ms": (min(count, 5000) - 1)*10, "rows": min(count, 5000), "scope": "complete_table" if count <= 5000 else "initial_saved_time_window; full table is longer"}}
        d = {"type": "table", "table_id": "trace_one", "identity": identity,
             "coordinates": {"axis": "time", "reference": "explicit source relative time", "source_time_origin": None, "source_time_unit": "ms"}, "support": support, "expected_rows": count}
        rows = []
        for index in range(count):
            row = {c["name"]: None if c["nullable"] else False if c["type"] == "boolean" else "fixture" if c["type"] == "string" else 0 for c in g.columns("mm")}
            row.update(source_row=index+1, time_s=index*.01, analysis_time_ms=index*10., source_time_text=str(index*10), phase="view",
                       pupil=float(index+4), pupil_text=str(index+4), pupil_finite=True, pupil_positive=True, effective_pupil_valid=True, passive=True,
                       source_gaze_valid=True, source_blink=False, baseline_member=None, exposure_member=True, correction_status="not_requested")
            # Compute coordinate by the documented conversion, not repeated additions.
            row["time_s"] = row["analysis_time_ms"] / 1000
            if index < count-1:
                row.update(following_time_ms=(index+1)*10., following_duration_ms=10., pupil_interval_duration_ms=10., baseline_interval_duration_ms=0.,
                           following_gap=False, following_phase_change=False, following_invalid_pupil=False, pupil_interval_eligible=True, baseline_interval_eligible=False)
            rows.append(row)
        return d, rows

    def exchange(self, d, rows, declared_total=None):
        path = self.root / "exchange.ndjson"
        count = len(rows) if declared_total is None else declared_total
        records = [{"type": "header", "schema": g.EXCHANGE, "source_rows": count}, d]
        for offset in range(0, len(rows), 64):
            records.append({"type": "rows", "table_id": d["table_id"], "offset": offset, "rows": rows[offset:offset+64]})
        records.extend([{"type": "table_end", "table_id": d["table_id"], "rows": len(rows)}, {"type": "complete", "tables": 1, "rows": count}])
        path.write_bytes(b"".join(g.a.encode(r) for r in records))
        return {"schema": g.EXCHANGE, "operation": "write", "exchange_path": str(path), "exchange_sha256": g.a.digest_file(path),
                "source_rows": count, "output_directory": str(self.artdir), "provenance": self.provenance}

    def make(self, count=3):
        d, rows = self.fixture(count)
        result = g.write(self.exchange(d, rows))
        return d, rows, result["artifacts"][0]

    def request(self, d, artifact, **kw):
        return {"schema": g.PREVIEW, "operation": "preview", "artifact": artifact, "table_id": d["table_id"], "identity": d["identity"], **kw}

    def test_exact_rows_range_and_terminal_null(self):
        d, rows, artifact = self.make()
        result = g.preview(self.request(d, artifact, start_ms=10, end_ms=20))
        self.assertEqual(result["selected_rows"], 2)
        self.assertEqual([r["source_row"] for r in result["rows"]], [2, 3])
        self.assertEqual(result["rows"][0]["row_index"], 1)
        self.assertIsNone(result["rows"][1]["following_duration_ms"])
        self.assertNotIn("path", result["artifact"])

    def test_explicit_empty_window(self):
        d, _, artifact = self.make()
        result = g.preview(self.request(d, artifact, start_ms=21, end_ms=30))
        self.assertEqual((result["status"], result["rows"], result["selected_rows"]), ("empty", [], 0))

    def test_every_overlimit_row_counted_but_no_partial_plot(self):
        d, _, artifact = self.make(5001)
        result = g.preview(self.request(d, artifact))
        self.assertEqual((result["status"], result["selected_rows"], result["rows"]), ("too_many_rows", 5001, []))
        catalog = g.catalog({"schema": g.PREVIEW, "operation": "catalog", "artifact": artifact})
        self.assertTrue(catalog["complete"])
        entry = catalog["tables"][0]
        self.assertEqual(entry["end_ms"], 50000)
        initial = g.preview(self.request(d, artifact, start_ms=entry["initial_window"]["start_ms"], end_ms=entry["initial_window"]["end_ms"]))
        self.assertEqual((initial["status"], initial["selected_rows"]), ("available", 5000))
        self.assertEqual(initial["rows"][-1]["source_row"], 5000)
        self.assertNotEqual(entry["initial_window"]["scope"], "complete_table")

    def test_different_person_identity_rejected(self):
        d, _, artifact = self.make()
        request = self.request(d, artifact)
        request["identity"] = {**d["identity"], "participant_id": "other"}
        with self.assertRaisesRegex(g.a.ArtifactError, "identity differs"):
            g.preview(request)

    def test_source_count_cannot_hide_missing_group(self):
        d, rows = self.fixture()
        with self.assertRaisesRegex(g.a.ArtifactError, "every original source row"):
            g.write(self.exchange(d, rows, declared_total=4))
        self.assertEqual(list(self.artdir.iterdir()), [])

    def test_duplicate_or_reordered_source_row_rejected(self):
        for replacement in (1, 4):
            d, rows = self.fixture()
            rows[1]["source_row"] = replacement
            with self.assertRaisesRegex(g.a.ArtifactError, "Source row"):
                g.write(self.exchange(d, rows))
        self.assertEqual(list(self.artdir.iterdir()), [])

    def test_following_endpoint_must_be_actual_next_row(self):
        d, rows = self.fixture()
        rows[0]["following_time_ms"] = 9.
        rows[0]["following_duration_ms"] = 9.
        with self.assertRaisesRegex(g.a.ArtifactError, "next original row"):
            g.write(self.exchange(d, rows))

    def test_terminal_cannot_gain_duration(self):
        d, rows = self.fixture()
        rows[-1]["following_duration_ms"] = 10.
        with self.assertRaisesRegex(g.a.ArtifactError, "Terminal intervals"):
            g.write(self.exchange(d, rows))

    def test_source_text_and_missing_flags_survive(self):
        d, rows = self.fixture()
        rows[0].update(pupil=-0.0, pupil_text=" -0 ", source_pupil_valid=None, source_pupil_valid_text=None)
        artifact = g.write(self.exchange(d, rows))["artifacts"][0]
        result = g.preview(self.request(d, artifact))["rows"][0]
        self.assertEqual(result["pupil_text"], " -0 ")
        self.assertEqual(g.math.copysign(1., result["pupil"]), -1.)
        self.assertIsNone(result["source_pupil_valid"])

    def test_whole_artifact_same_size_mutation_rejected_even_outside_window(self):
        d, _, artifact = self.make()
        path = Path(artifact["path"])
        before = path.read_bytes()
        after = before.replace(b"fixture", b"changed", 1)
        self.assertEqual(len(before), len(after))
        self.assertNotEqual(before, after)
        path.write_bytes(after)
        with self.assertRaisesRegex(g.a.ArtifactError, "SHA-256 mismatch"):
            g.preview(self.request(d, artifact, start_ms=10, end_ms=20))

    def test_exchange_tampering_and_trailing_records_refused(self):
        d, rows = self.fixture()
        request = self.exchange(d, rows)
        path = Path(request["exchange_path"])
        with path.open("ab") as stream: stream.write(g.a.encode({"type": "extra"}))
        with self.assertRaisesRegex(g.a.ArtifactError, "identity mismatch"):
            g.write(request)
        request["exchange_sha256"] = g.a.digest_file(path)
        with self.assertRaisesRegex(g.a.ArtifactError, "trailing records"):
            g.write(request)
        self.assertEqual(list(self.artdir.iterdir()), [])

    def test_generic_mask_substitution_rejected(self):
        d, rows = self.fixture()
        d["support"]["generic_line_preview"] = "use_retained"
        with self.assertRaisesRegex(g.a.ArtifactError, "dedicated mask-aware"):
            g.write(self.exchange(d, rows))

    def test_incomplete_stream_leaves_no_artifact(self):
        d, rows = self.fixture()
        request = self.exchange(d, rows)
        path = Path(request["exchange_path"])
        lines = path.read_bytes().splitlines(True)
        path.write_bytes(b"".join(lines[:-2]))
        request["exchange_sha256"] = g.a.digest_file(path)
        with self.assertRaisesRegex(g.a.ArtifactError, "ended inside a table"):
            g.write(request)
        self.assertEqual(list(self.artdir.iterdir()), [])

    def test_large_legal_source_text_fails_before_unbounded_preview_allocation(self):
        d, rows = self.fixture(250)
        for row in rows:
            for field in ("pupil_text", "source_time_text"):
                row[field] = row[field].rjust(16000)
            row["source_gaze_valid_text"] = "true".rjust(16000)
            row["source_blink_text"] = "false".rjust(16000)
        with g.a.TableWriter(self.artdir, "physiology-series", self.provenance, chunk_rows=8, preview_limit=0) as writer:
            writer.write_table(d["table_id"], d["identity"], g.columns("mm"), d["coordinates"], d["support"], rows, len(rows))
            artifact = writer.finish()
        tracemalloc.start()
        try:
            with self.assertRaisesRegex(g.a.ArtifactError, "16 MiB|byte budget"):
                g.preview(self.request(d, artifact))
            _, peak = tracemalloc.get_traced_memory()
        finally:
            tracemalloc.stop()
        self.assertLess(peak, 48 * 1024**2, "Legal source text must be rejected incrementally, before building an oversized result list and JSON copy.")

    def test_complete_catalog_is_incrementally_bounded_without_partial_return(self):
        d, rows = self.fixture()
        with g.a.TableWriter(self.artdir, "physiology-series", self.provenance, preview_limit=0) as writer:
            for index in range(90):
                identity = {**d["identity"], "participant_id": "p" * 500000 + str(index)}
                writer.write_table(f"trace_{index}", identity, g.columns("mm"), d["coordinates"], d["support"], rows, len(rows))
            artifact = writer.finish()
        tracemalloc.start()
        try:
            with self.assertRaisesRegex(g.a.ArtifactError, "catalog.*(16 MiB|byte budget)"):
                g.catalog({"schema": g.PREVIEW, "operation": "catalog", "artifact": artifact})
            _, peak = tracemalloc.get_traced_memory()
        finally:
            tracemalloc.stop()
        self.assertLess(peak, 48 * 1024**2, "Complete metadata is bounded while reading, not after retaining a large catalog.")


if __name__ == "__main__":
    unittest.main(verbosity=2)
