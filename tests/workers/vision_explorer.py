"""Independent complete JSONL oracles; no model inference or person imagery."""
import copy
import csv
from decimal import Decimal
import importlib.util
import json
from pathlib import Path
import sqlite3
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("vision_explorer", ROOT / "scripts/workers/vision_explorer.py")
v = importlib.util.module_from_spec(spec); spec.loader.exec_module(v)


def point(): return {"x": .5, "y": .25, "z": -.125, "visibility": 1, "presence": 1}
def face(state="single"):
    count = 0 if state == "absent" else 2 if state == "multiple" else 1
    return {"count": count, "count_is_lower_bound": count == 2, "valid": state == "single", "state": state,
            "landmarks": [point() for _ in range(478)] if count == 1 else None,
            "geometry": {"outer_eye_distance_image_width": .5, "lip_separation_image_width": .125} if state == "single" else None,
            "blendshapes": {"jawOpen": .25} if state == "single" else None}
def fixture(folder, count=7):
    source = folder / "complete.jsonl"; origin = Decimal("9007199254740992.0000"); states = ["single", "absent", "multiple", "border_geometry", "single", "single", "single"]
    counts = {}; valid = 0
    with source.open("wb") as stream:
        for i in range(count):
            state = states[i % len(states)]; counts[state] = counts.get(state, 0) + 1; valid += state == "single"
            relative = Decimal(i) / 10
            row = {"frame_index": i + 5, "source_pts_s": str(origin + relative), "time_s": float(relative), "model_timestamp_ms": i * 100, "face": face(state)}
            # Exact token spellings deliberately differ from float re-encoding.
            raw = json.dumps(row, separators=(",", ":")).replace('"jawOpen":0.25', '"jawOpen":2.500000000000000000e-1')
            stream.write(raw.encode() + b"\n")
    binding = v.encoded({"project_id": "original-oracle", "report_hash": "a" * 64, "source": "independent_synthetic_observations"}).decode()
    return {"schema": "brohn-vision-explorer-request/1.0", "operation": "build", "artifact_path": str(source), "artifact": v.descriptor(source),
            "index_path": str(folder / "index.sqlite"), "binding_json": binding, "binding_sha256": v.sha(binding.encode()),
            "parameters": {"channels": ["face"], "source_pts_origin_s": str(origin), "max_support_gap_s": .25, "start_s": 0, "end_s": (count-1)/10,
                           "width": 640, "height": 480, "orientation": "encoded pixels, no autorotation"},
            "quality": {"source_frames": count+5, "analysed_frames": count, "channels": {"face": {"valid_frames": valid, "states": counts}}},
            "engine": {"name": "independent_artifact_oracle", "version": "1", "models": []}}
def query(request, result, **extra):
    return {"schema": request["schema"], "index_path": request["index_path"], "index": result["index"], "binding_sha256": request["binding_sha256"], **extra}
def changed(request, transform):
    path = Path(request["artifact_path"]); lines = path.read_text().splitlines(); lines = transform(lines); path.write_text("\n".join(lines) + "\n", encoding="utf-8", newline="")
    request["artifact"] = v.descriptor(path)


class ExplorerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.folder = Path(self.temp.name); self.request = fixture(self.folder)
    def tearDown(self): self.temp.cleanup()
    def build(self): return v.build(self.request)
    def test_exact_complete_catalog_counts(self):
        result = self.build(); m = result["manifest"]
        self.assertEqual(m["frames"], 7); self.assertEqual(m["channels"]["face"], {"valid_frames": 4, "states": {"single": 4, "absent": 1, "multiple": 1, "border_geometry": 1}})
        self.assertEqual(next(x for x in m["metrics"] if x["id"] == "face.blendshape.jawOpen")["valid_frames"], 4)
    def test_numeric_lexeme_and_exact_decimal_origin(self):
        result = self.build(); page = v.page(query(self.request, result, metric="face.blendshape.jawOpen"))
        self.assertEqual(page["rows"][0]["value_text"], "2.500000000000000000e-1")
        self.assertEqual(page["rows"][1]["source_pts_s"], "9007199254740992.1000")
        self.assertEqual(Decimal(page["rows"][1]["relative_exact_text"]), Decimal(".1")); self.assertIsNone(page["rows"][1]["value_text"])
    def test_native_underscore_neutral_name_and_exact_token(self):
        changed(self.request, lambda lines: [line.replace('"jawOpen":', '"_neutral":') for line in lines])
        result = self.build(); page = v.page(query(self.request, result, metric="face.blendshape._neutral"))
        self.assertEqual(page["rows"][0]["value_text"], "2.500000000000000000e-1")
    def test_guarded_verified_read_avoids_rehash_but_keeps_manifest_binding(self):
        result = self.build(); original = v.digest
        try:
            v.digest = lambda _: (_ for _ in ()).throw(AssertionError("Unexpected repeated full-byte hashing"))
            request = query(self.request, result, guarded_verified=True)
            self.assertEqual(v.page(request)["total"], 7)
            request["binding_sha256"] = "b" * 64
            with self.assertRaises(v.InputError): v.page(request)
        finally: v.digest = original
    def test_exact_point_range_not_float_rounding(self):
        result = self.build(); result = v.page(query(self.request, result, metric="face.blendshape.jawOpen", range=["0.10000000000000000000001", "0.4"]))
        self.assertEqual([r["frame_index"] for r in result["rows"]], [7,8,9])
    def test_page_cursor_binding(self):
        result = self.build(); request = query(self.request, result, metric="face.blendshape.jawOpen", limit=2)
        first = v.page(request); second = v.page(dict(request, cursor=first["next_cursor"]))
        self.assertEqual([r["frame_index"] for r in first["rows"]+second["rows"]], [5,6,7,8])
        with self.assertRaises(v.InputError): v.page(dict(request, cursor=first["next_cursor"], metric="face.lip_separation_image_width"))
    def test_detail_exact_original_line_and_landmarks(self):
        result = self.build(); detail = v.detail(query(self.request, result, artifact_path=self.request["artifact_path"], frame_index=5))
        self.assertEqual(detail["schema"], "brohn-vision-frame-detail/1.0")
        self.assertEqual(detail["original_json"], Path(self.request["artifact_path"]).read_text().splitlines(keepends=True)[0])
        self.assertEqual(detail["observation"]["face"]["blendshapes"]["jawOpen"], "2.500000000000000000e-1")
        self.assertEqual(detail["observation"]["face"]["landmarks"][0]["z"], "-0.125")
    def test_late_frame_beyond_report_preview(self):
        with tempfile.TemporaryDirectory() as other:
            request = fixture(Path(other), 2101); result = v.build(request)
            detail = v.detail(query(request, result, artifact_path=request["artifact_path"], frame_index=2105))
            self.assertEqual(detail["frame"]["ordinal"], 2100)
    def test_duplicate_json_key_refused_and_build_removed(self):
        changed(self.request, lambda lines: [lines[0].replace('"frame_index":5', '"frame_index":5,"frame_index":6')]+lines[1:])
        with self.assertRaises(v.InputError): self.build()
        self.assertFalse(Path(self.request["index_path"]).exists()); self.assertFalse(Path(self.request["index_path"]+".building").exists())
    def test_reversed_frame_or_pts_refused(self):
        changed(self.request, lambda lines: [lines[0],lines[0]]+lines[2:])
        with self.assertRaises(v.InputError): self.build()
    def test_source_clock_mismatch_refused(self):
        changed(self.request, lambda lines: [lines[0].replace('"time_s":0.0', '"time_s":0.01')]+lines[1:])
        with self.assertRaises(v.InputError): self.build()
    def test_saved_complete_count_refused(self):
        self.request["quality"]["channels"]["face"]["valid_frames"] += 1
        with self.assertRaises(v.InputError): self.build()
    def test_index_substitution_and_source_binding_refused(self):
        result = self.build()
        with self.assertRaises(v.InputError): v.page(query(self.request, result, binding_sha256="b"*64))
        with open(self.request["index_path"], "r+b") as stream: stream.seek(-1,2); stream.write(b"X")
        with self.assertRaises(v.InputError): v.page(query(self.request, result))
    def test_selected_original_line_substitution_refused(self):
        result = self.build(); path = Path(self.request["artifact_path"])
        raw = path.read_bytes(); path.write_bytes(raw.replace(b'"z":-0.125',b'"z":-0.250',1))
        with self.assertRaises(v.InputError): v.detail(query(self.request, result, artifact_path=str(path), frame_index=5))
    def test_page_and_unknown_metric_bounds(self):
        result = self.build()
        for extra in ({"limit":101},{"metric":"face.emotion.happiness"},{"range":[".2",".1"]}):
            with self.assertRaises(v.InputError): v.page(query(self.request,result,**extra))
    def test_reader_closes_even_with_retained_traceback(self):
        result = self.build(); captured = None
        try:
            with v.opened(query(self.request,result)) as (con,_): raise RuntimeError("retain traceback")
        except RuntimeError as error: captured = error
        self.assertIsNotNone(captured)
        with self.assertRaises(sqlite3.ProgrammingError): con.execute("SELECT 1")
    def test_plot_preserves_invalid_gaps_and_original_points(self):
        result = self.build(); plotted = v.plot(query(self.request,result,metric="face.blendshape.jawOpen",channel="face"))
        self.assertEqual([[p["frame_index"] for p in f["points"]] for f in plotted["fragments"]], [[5],[9,10,11]])
        self.assertEqual(Decimal(plotted["support"]["metric_valid_time_s_text"]), Decimal(".2"))
        self.assertEqual(plotted["support"]["metric_valid_frames"],4)
        self.assertEqual(sum(b["frames"] for b in plotted["states"]),7)
        self.assertTrue(all(p["value_text"] == "2.500000000000000000e-1" for f in plotted["fragments"] for p in f["points"]))
    def test_plot_state_only_and_empty_range(self):
        result = self.build(); plotted = v.plot(query(self.request,result,channel="face"))
        self.assertEqual(plotted["fragments"],[]); self.assertEqual(plotted["support"]["channel_valid_frames"],4)
        empty = v.plot(query(self.request,result,channel="face",range=[".71",".72"]))
        self.assertEqual(empty["status"],"empty_range"); self.assertEqual(empty["states"],[])
    def test_full_csv_preserves_numeric_tokens_and_missing(self):
        result = self.build(); target = self.folder / "exact.csv"
        receipt = v.export_csv(query(self.request,result,metric="face.blendshape.jawOpen",output_path=str(target)))
        with target.open(newline="") as stream: records=list(csv.DictReader(stream))
        self.assertEqual(receipt["rows"],7); self.assertEqual(records[0]["value"],"2.500000000000000000e-1")
        self.assertEqual(records[1]["value"],""); self.assertEqual(records[-1]["frame_index"],"11")
    def test_too_many_fragments_refuses_instead_of_joining(self):
        with tempfile.TemporaryDirectory() as other:
            request=fixture(Path(other),14); result=v.build(request)
            with self.assertRaises(v.InputError):v.plot(query(request,result,metric="face.blendshape.jawOpen",channel="face",max_points=4))


if __name__ == "__main__": unittest.main()
