"""Independent generated recordings through the actual preservation importer."""
import copy
import hashlib
import importlib.util
import json
import sys
from pathlib import Path
import unittest

from clock_test_support import ROOT,fresh_output
HERE=Path(__file__).resolve().parent
import interchange
import clock_source
spec = importlib.util.spec_from_file_location("original", ROOT / "tests/fixtures/researcher-linked-review.py")
original = importlib.util.module_from_spec(spec); spec.loader.exec_module(original)
DESTINATION = fresh_output()


class ClockSourceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = DESTINATION / "original.json"
        cls.source.write_text(json.dumps(original.bundle()), encoding="utf-8")
        cls.imported = interchange.run({"schema":"brohn-interchange-request/1.0", "operation":"import_multistream", "format":"brohn_stream_bundle",
            "source_path":str(cls.source), "source_hash":interchange.digest(cls.source), "output_directory":str(DESTINATION / "import"),
            "metadata":{"origin":"sample", "origin_statement":"Independent generated source qualification fixture; no person or physical timing.", "clock_policy":"preserve_only"}})
        cls.tracks = []
        for s in cls.imported["streams"]:
            def artifact(kind):
                a = next(x for x in s["artifacts"] if x["kind"] == kind)
                return {"path":a["path"], "hash":a["sha256"], "bytes":a["bytes"]}
            cls.tracks.append({"source_stream_id":s["id"], "kind":s["kind"], "origin":"sample", "channel":s["channels"][0],
                "clock":s["clock"], "preservation":s["quality"], "sample_count":s["sample_count"], "segment_count":s["segment_count"],
                "samples":artifact("stream_samples_jsonl"), "evidence":artifact("stream_evidence_jsonl")})
        cls.serial = 0

    def track(self, index):
        return copy.deepcopy(self.tracks[index])

    def edited(self, index, edit):
        t = self.track(index)
        source = Path(t["samples"]["path"])
        rows = [json.loads(line) for line in source.read_text(encoding="utf-8").splitlines()]
        edit(rows)
        type(self).serial += 1
        target = DESTINATION / f"explicit-adversarial-copy-{self.serial}.jsonl"
        target.write_text("".join(json.dumps(row) + "\n" for row in rows), encoding="utf-8")
        t["samples"] = {"path":str(target), "hash":interchange.digest(target), "bytes":target.stat().st_size}
        return t

    def test_complete_source_counts_gap_missing_and_identity(self):
        result = clock_source.inspect_stream(self.track(0))
        self.assertEqual(result["source_rows"], 76)
        self.assertEqual(result["missing_values"], 1)
        self.assertEqual(result["unplaced_rows"], 0)
        self.assertEqual(len(result["segments"]), 2)
        self.assertEqual(result["identity"], {"participant_id":"ORIGINAL-LINKED-01", "session_id":"ORIGINAL-VISIT-01"})

    def test_exact_selected_marker_rows_and_source_order(self):
        result = clock_source.inspect_stream(self.track(2), [3, 1, 2])
        self.assertEqual([x["source_sequence"] for x in result["events"]], [3, 1, 2])
        self.assertEqual([x["source_timestamp"] for x in result["events"]], [str(original.ANCHOR + x) for x in (3250000000,500000000,1250000001)])
        self.assertIn("<script>not executable</script>", result["events"][2]["value_json"])

    def test_unplaced_rows_are_retained_without_reconstruction(self):
        t = self.edited(1, lambda rows: rows[7].update(source_timestamp=None, timestamp_state="missing", reconstructed_timestamp=False))
        self.assertEqual(clock_source.inspect_stream(t)["unplaced_rows"], 1)

    def test_selected_unplaced_or_missing_marker_is_refused(self):
        t = self.edited(2, lambda rows: rows[0].update(reconstructed_timestamp=True))
        with self.assertRaisesRegex(ValueError, "original observed"):
            clock_source.inspect_stream(t, [1])
        t = self.edited(2, lambda rows: rows[0]["values"].update(event=None))
        with self.assertRaisesRegex(ValueError, "original observed"):
            clock_source.inspect_stream(t, [1])

    def test_full_source_identity_audited_beyond_selected_anchors(self):
        t = self.edited(1, lambda rows: rows[-1]["identity"].update(participant_id="OTHER"))
        with self.assertRaisesRegex(ValueError, "different participant/session"):
            clock_source.inspect_stream(t)

    def test_missing_or_blank_session_is_refused(self):
        for value in (None, "", " "):
            t = self.edited(2, lambda rows: rows[-1]["identity"].update(session_id=value))
            with self.assertRaisesRegex(ValueError, "identities|Explicit original"):
                clock_source.inspect_stream(t, [1, 2])

    def test_retained_reset_is_refused(self):
        with self.assertRaisesRegex(ValueError, "reset or ambiguous epoch"):
            clock_source.inspect_stream(self.track(4))

    def test_hidden_reversal_or_duplicate_signal_is_refused(self):
        for same in (False, True):
            t = self.edited(1, lambda rows: rows[5].update(source_timestamp=rows[4 if same else 3]["source_timestamp"]))
            with self.assertRaisesRegex(ValueError, "timestamps|epoch"):
                clock_source.inspect_stream(t)

    def test_changed_original_artifact_refused(self):
        t = self.track(2); t["samples"]["hash"] = "0"*64
        with self.assertRaisesRegex(ValueError, "SHA-256"):
            clock_source.inspect_stream(t, [1, 2])

    def test_timestamp_processing_stage_is_explicit(self):
        for key in ("clock_correction_applied", "dejitter_applied"):
            t = self.track(2); t["preservation"][key] = True
            with self.assertRaisesRegex(ValueError, "preserved timestamp stage"):
                clock_source.inspect_stream(t, [1, 2])

    def test_row_clock_and_counts_checked(self):
        t = self.edited(2, lambda rows: rows[-1].update(clock_id="different"))
        with self.assertRaisesRegex(ValueError, "original clock"):
            clock_source.inspect_stream(t, [1, 2])
        t = self.track(2); t["sample_count"] += 1
        with self.assertRaisesRegex(ValueError, "counts changed"):
            clock_source.inspect_stream(t)

    def test_bounded_distinct_original_event_sequences(self):
        for selection in ([1, 1], [0], [True], [4], [1.0]):
            with self.assertRaisesRegex(ValueError, "bounded original marker"):
                clock_source.inspect_stream(self.track(2), selection)
        with self.assertRaisesRegex(ValueError, "original marker rows"):
            clock_source.inspect_stream(self.track(0), [1, 2])

    def test_unknown_or_scaled_standard_clock_units_refused(self):
        for change in ({"unit":"milliseconds"}, {"seconds_per_tick":".5"}):
            t = self.track(2); t["clock"].update(change)
            with self.assertRaises(ValueError):
                clock_source.inspect_stream(t, [1, 2])

    def test_marker_json_float_lexeme_is_not_rounded(self):
        t = self.edited(2, lambda rows: rows[0]["values"].update(event="replace-exact-number"))
        target = Path(t["samples"]["path"])
        token = "9007199254741013.0000000001"
        target.write_text(target.read_text(encoding="utf-8").replace('"replace-exact-number"', token), encoding="utf-8")
        t["samples"].update(hash=interchange.digest(target), bytes=target.stat().st_size)
        result = clock_source.inspect_stream(t, [1])
        self.assertEqual(result["events"][0]["value_json"], token)

    def test_numeric_identity_cannot_become_text_identity(self):
        for value in (1.25, 12, True):
            t = self.edited(2, lambda rows: rows[-1]["identity"].update(participant_id=value))
            with self.assertRaisesRegex(ValueError, "explicit text encoding"):
                clock_source.inspect_stream(t, [1, 2])

    def test_segment_evidence_clock_count_times_identity_reconciled(self):
        for update in ({"clock_id":"wrong"}, {"sample_count":2}, {"start_timestamp":"0"}, {"end_timestamp":None},
                       {"identity":{"participant_id":"WRONG", "session_id":"ORIGINAL-VISIT-01"}}):
            t = self.track(2)
            source = Path(t["evidence"]["path"])
            rows = [json.loads(line) for line in source.read_text(encoding="utf-8").splitlines()]
            next(x for x in rows if x["type"] == "source_segment").update(update)
            type(self).serial += 1
            target = DESTINATION / f"explicit-adversarial-evidence-{self.serial}.jsonl"
            target.write_text("".join(json.dumps(row)+"\n" for row in rows), encoding="utf-8")
            t["evidence"] = {"path":str(target), "hash":interchange.digest(target), "bytes":target.stat().st_size}
            with self.assertRaisesRegex(ValueError, "segment"):
                clock_source.inspect_stream(t, [1, 2])

    def test_verified_segment_projection_omits_unqualified_derived_fields(self):
        result = clock_source.inspect_stream(self.track(2), [1, 2])
        self.assertEqual(set(result["segments"][0]), {"id", "first_sequence", "last_sequence", "sample_count", "clock_id", "identity", "start_timestamp", "end_timestamp", "boundary_reasons"})


if __name__ == "__main__":
    DESTINATION.mkdir(parents=True, exist_ok=False)
    with (DESTINATION / "tests.log").open("w", encoding="utf-8") as log:
        result = unittest.TextTestRunner(stream=log, verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(ClockSourceTests))
    receipt = {"passed":result.wasSuccessful(), "groups":result.testsRun, "failures":len(result.failures), "errors":len(result.errors),
        "source_sha256":interchange.digest(ROOT / "scripts/workers/clock_source.py"), "test_sha256":interchange.digest(Path(__file__)),
        "scope":"External complete-source inspection of generated canonical streams, including declared adversarial copies. No project authority, cross-stream equivalence, alignment publication, UI or physical timing qualification."}
    (DESTINATION / "results.json").write_text(json.dumps(receipt, indent=2), encoding="utf-8")
    print((DESTINATION / "tests.log").read_text(), end=""); print(json.dumps(receipt))
    sys.exit(0 if result.wasSuccessful() else 1)
