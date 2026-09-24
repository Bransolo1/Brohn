"""Independent full-source transport/clock/display checks via actual importer."""
import copy
import csv
import importlib.util
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path("scripts/workers").resolve()))
import interchange
import linked_review
spec = importlib.util.spec_from_file_location("fixture", "tests/fixtures/researcher-linked-review.py")
fixture = importlib.util.module_from_spec(spec); spec.loader.exec_module(fixture)

class LinkedReview(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.root = Path(tempfile.mkdtemp(prefix="brohn-linked-worker-")); cls.source = cls.root/"original.json"
        cls.source.write_text(json.dumps(fixture.bundle()), encoding="utf-8")
        cls.imported = interchange.run({"schema":"brohn-interchange-request/1.0","operation":"import_multistream","format":"brohn_stream_bundle",
            "source_path":str(cls.source),"source_hash":interchange.digest(cls.source),"output_directory":str(cls.root/"import"),
            "metadata":{"origin":"sample","origin_statement":"Original independently generated software fixture; shared generator clock only.","clock_policy":"preserve_only"}})
        cls.tracks = []
        for s in cls.imported["streams"]:
            def artifact(kind):
                a = next(x for x in s["artifacts"] if x["kind"] == kind)
                return {"path": a["path"], "hash": a["sha256"], "bytes": a["bytes"]}
            cls.tracks.append({"id":s["id"]+"/"+s["channels"][0]["id"],"stream_id":s["id"],"source_stream_id":s["id"],"title":s["name"],
                "channel":s["channels"][0],"kind":s["kind"],"origin":"sample","clock":s["clock"],"sample_count":s["sample_count"],
                "segment_count":s["segment_count"],"samples":artifact("stream_samples_jsonl"),"evidence":artifact("stream_evidence_jsonl")})
        cls.counter = 0

    def request(self, indices=(0,1,2), start="0", end="4", cursor="1.25", offset=0):
        type(self).counter += 1
        return {"schema":"brohn-linked-review-request/1.0","binding":{"original_source_sha256":interchange.digest(self.source)},
            "tracks":copy.deepcopy([self.tracks[i] for i in indices]),"selection":{"start_s":start,"end_s":end,"cursor_s":cursor,"offset":offset},
            "export_path":str(self.root/f"window-{self.counter}.csv")}

    def test_complete_window_exact_time_and_values(self):
        r = self.request(); result = linked_review.review(r)
        with open(r["export_path"],encoding="utf-8",newline="") as handle:
            rows = list(csv.DictReader(handle))
        self.assertEqual(result["selected_rows"],78); self.assertEqual([t["selected_rows"] for t in result["tracks"]],[35,40,3]); self.assertEqual(len(rows),78)
        for row in rows:
            self.assertEqual(row["relative_time_s"],str((linked_review.decimal(row["source_timestamp"],"oracle")-fixture.ANCHOR)*linked_review.TIME["ns"]))
        marker = next(x for x in rows if "candidate stimulus onset" in x["value_json"])
        self.assertEqual(linked_review.Decimal(marker["relative_time_s"]),linked_review.Decimal("1.250000001"))
        self.assertEqual(result["anchor_timestamp"],str(fixture.ANCHOR)); self.assertEqual(result["tracks"][1]["cursor"]["before"]["value_json"],"124.0")
        self.assertEqual(result["tracks"][1]["cursor"]["after"]["value_json"],"126.0")

    def test_missing_gap_never_connects(self):
        result = linked_review.review(self.request()); track = result["tracks"][0]
        self.assertEqual(track["missing_values"],1); self.assertEqual(len(track["segments"]),2)
        self.assertEqual(len({p["run"] for p in track["points"]}),3)
        points = {p["sequence"]:p for p in track["points"]}
        self.assertNotEqual(points[12]["run"],points[14]["run"]); self.assertNotEqual(points[20]["run"],points[21]["run"])

    def test_exact_half_open_boundary(self):
        r = self.request(start="1.250000001",end="3.25",cursor="2"); result = linked_review.review(r)
        self.assertEqual(len(result["tracks"][2]["markers"]),1)
        self.assertIn("candidate stimulus onset",result["tracks"][2]["markers"][0]["label"])

    def test_incompatible_clock_refused(self):
        with self.assertRaisesRegex(ValueError,"Different source clocks"):
            linked_review.review(self.request((0,3)))

    def test_reset_refuses_export(self):
        r = self.request((0,4)); result = linked_review.review(r)
        self.assertEqual(result["status"],"requires_alignment"); self.assertIsNone(result["csv"]); self.assertFalse(Path(r["export_path"]).exists())

    def test_empty_range_no_fabricated_points(self):
        result = linked_review.review(self.request(start="20",end="21",cursor="20.5"))
        self.assertEqual(result["status"],"empty_window"); self.assertEqual(result["selected_rows"],0)
        self.assertTrue(all(not t["points"] and not t["markers"] for t in result["tracks"]))

    def test_exact_page_beyond_preview(self):
        first = linked_review.review(self.request(end="8",offset=0)); last = linked_review.review(self.request(end="8",offset=100))
        self.assertEqual(first["selected_rows"],158); self.assertEqual(len(first["rows"]),100); self.assertEqual(len(last["rows"]),58)
        self.assertEqual(last["rows"][-1]["relative_time_s"],"3.250000000")

    def test_changed_hash_refused(self):
        r = self.request(); r["tracks"][0]["samples"]["hash"] = "0"*64
        with self.assertRaisesRegex(ValueError,"SHA-256"):
            linked_review.review(r)

    def test_invalid_window_refused(self):
        with self.assertRaisesRegex(ValueError,"positive window"):
            linked_review.review(self.request(start="4",end="0"))

    def test_display_precision_refused_without_rounding(self):
        with self.assertRaisesRegex(ValueError,"representable display"):
            linked_review.review(self.request(start="9007199254741013",end="9007199254741014",cursor="9007199254741013"))

    def test_duplicate_selection_refused(self):
        with self.assertRaisesRegex(ValueError,"distinct source tracks"):
            linked_review.review(self.request((0,0)))

    def test_different_participant_refused(self):
        r = self.request(); ref = r["tracks"][1]["samples"]; original = Path(ref["path"])
        target = self.root/"other-participant-canonical.jsonl"
        rows = [json.loads(line) for line in original.read_text(encoding="utf-8").splitlines()]
        for row in rows:
            row["identity"]["participant_id"] = "EXPLICIT-OTHER-PERSON"
        target.write_text("".join(json.dumps(row)+"\n" for row in rows),encoding="utf-8")
        ref.update(path=str(target),hash=interchange.digest(target),bytes=target.stat().st_size)
        with self.assertRaisesRegex(ValueError,"different participant/session identities"):
            linked_review.review(r)

    def test_missing_timestamp_never_gets_an_invented_place(self):
        r = self.request(); ref = r["tracks"][1]["samples"]; original = Path(ref["path"])
        target = self.root/"declared-missing-time-canonical.jsonl"
        rows = [json.loads(line) for line in original.read_text(encoding="utf-8").splitlines()]
        rows[7].update(source_timestamp=None,timestamp_state="missing",reconstructed_timestamp=False)
        target.write_text("".join(json.dumps(row)+"\n" for row in rows),encoding="utf-8")
        ref.update(path=str(target),hash=interchange.digest(target),bytes=target.stat().st_size)
        result = linked_review.review(r)
        self.assertEqual(result["tracks"][1]["unplaced_source_rows"],1)
        self.assertEqual(result["tracks"][1]["selected_rows"],39)
        self.assertNotIn(8,[p["sequence"] for p in result["tracks"][1]["points"]])

if __name__ == "__main__":
    result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(LinkedReview))
    if os.environ.get("BROHN_LINKED_TEST_RECEIPT"):
        Path(os.environ["BROHN_LINKED_TEST_RECEIPT"]).write_text(json.dumps({"passed":result.wasSuccessful(),"tests":result.testsRun,
            "failures":[(str(t),trace) for t,trace in result.failures],"errors":[(str(t),trace) for t,trace in result.errors],
            "fixture":str(LinkedReview.root),"original_sha256":interchange.digest(LinkedReview.source),
            "source_hashes":{p:interchange.digest(p) for p in ["scripts/workers/linked_review.py","scripts/workers/interchange.py","scripts/workers/stream_extract.py"]},
            "scope":"Original imported synthetic streams; two explicit canonical edge/adversarial cases modify only independent copies. No observed physical signal qualification."},indent=2),encoding="utf-8")
    sys.exit(0 if result.wasSuccessful() else 1)
