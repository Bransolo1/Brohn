"""Original numeric/geometry/PTS fixtures; no real person or downloaded media."""
import importlib.metadata
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import struct
import zlib
from types import SimpleNamespace
import unittest

import cv2
import numpy as np

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("brohn_vision", ROOT / "scripts/workers/vision.py")
worker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(worker)
VERSION = importlib.metadata.version("mediapipe")


def point(x=.5, y=.5, z=0, visibility=1):
    return SimpleNamespace(x=x, y=y, z=z, visibility=visibility, presence=1)


def request(source, directory, operation, metadata):
    return {"schema": "brohn-vision-request/1.0", "operation": operation, "source_path": str(source),
            "source_hash": worker.digest(source), "metadata": metadata, "output_directory": str(directory)}


class GeometryTests(unittest.TestCase):
    def test_geometry_and_missing_landmarks(self):
        points = worker.landmark_rows([point(0, 0), point(.5, 0), point(.5, 1)])
        self.assertAlmostEqual(worker.angle(points, 0, 1, 2, 200, 100), 90)
        self.assertAlmostEqual(worker.distance(points, 0, 2, 200, 100), 2 ** -.5)
        points[1]["visibility"] = .1
        self.assertIsNone(worker.angle(points, 0, 1, 2, 200, 100))
        points[0]["x"] = None
        self.assertIsNone(worker.distance(points, 0, 2, 200, 100))

    def test_face_mask_and_native_geometry(self):
        absent = SimpleNamespace(face_landmarks=[])
        self.assertEqual(worker.face_observation(absent, 200, 100)["state"], "absent")
        many = SimpleNamespace(face_landmarks=[[point()], [point()]])
        self.assertIsNone(worker.face_observation(many, 200, 100)["blendshapes"])
        points = [point() for _ in range(478)]
        points[33], points[263] = point(.25, .4), point(.75, .4)
        points[13], points[14] = point(.5, .55), point(.5, .65)
        observed = SimpleNamespace(face_landmarks=[points], face_blendshapes=[[SimpleNamespace(category_name="jawOpen", score=.2)]])
        face = worker.face_observation(observed, 200, 100)
        self.assertTrue(face["valid"])
        self.assertAlmostEqual(face["geometry"]["lip_separation_image_width"], .05)
        self.assertEqual(face["blendshapes"], {"jawOpen": .2})
        points[0] = point(-.1, .5)
        self.assertFalse(worker.face_observation(observed, 200, 100)["valid"])

    def test_hand_geometry_duplicate_label_mask(self):
        points = [point() for _ in range(21)]
        points[0], points[9], points[4], points[8] = point(.3, .5), point(.5, .5), point(.45, .3), point(.55, .3)
        category = SimpleNamespace(category_name="Left", score=.9)
        hand = worker.hand_observation(SimpleNamespace(hand_landmarks=[points], handedness=[[category]]), 200, 100)
        self.assertAlmostEqual(hand["hands"][0]["geometry"]["thumb_index_distance_over_palm"], .5)
        duplicate = worker.hand_observation(SimpleNamespace(hand_landmarks=[points, points], handedness=[[category], [category]]), 200, 100)
        self.assertFalse(duplicate["valid"])

    def test_pts_decimal_origin_nonuniform_rejection(self):
        stamps, ms = worker.validate_pts([{"pts_time": x} for x in ["9007199254740992.000", "9007199254740992.040", "9007199254740992.160"]])
        self.assertEqual(ms, [0, 40, 160])
        for bad in [["0", "0"], ["0", "-1"], ["0", ".0001"], ["0", "601"], ["0", "NaN"]]:
            with self.assertRaises(worker.InputError):
                worker.validate_pts([{"pts_time": x} for x in bad])
        with self.assertRaises(worker.InputError):
            worker.validate_pts([{"pts_time": "0"}, {}])

    def test_support_denominators_no_zero_imputation(self):
        summary = worker.Summary(["face"], .25)
        for stamp, value in [(0, 1), (.1, 3), (.2, None), (.3, 5), (.8, 9)]:
            summary.add({"time_s": stamp, "face": {"valid": value is not None, "state": "single" if value else "absent",
                                                     "geometry": {"test_ratio": value} if value is not None else None}})
        feature = summary.result()[0]
        self.assertEqual(feature["value"], 4.5)
        self.assertEqual(feature["valid_frames"], 4)
        self.assertAlmostEqual(feature["valid_time_s"], .1)
        self.assertAlmostEqual(feature["time_weighted_mean"], 2)
        self.assertAlmostEqual(summary.elapsed_support, .3)

    def test_prompt_component_holes_and_encoding(self):
        foreground = np.zeros((100, 120), dtype=bool)
        foreground[20:80, 30:90] = True
        foreground[40:50, 50:60] = False
        foreground[2:8, 2:8] = True
        categories = np.where(foreground, 0, 255).astype(np.uint8)
        confidence = np.where(foreground, .9, .1).astype(np.float32)
        mask, proposal = worker.component_proposal(categories, confidence, {"x": .3, "y": .3})
        self.assertEqual(proposal["pixel_bbox"], {"x": 30, "y": 20, "width": 60, "height": 60})
        self.assertEqual(proposal["foreground_pixels"], 3500)
        self.assertEqual(proposal["discarded_foreground_pixels"], 36)
        self.assertEqual(int(mask[45, 55]), 0)
        self.assertTrue(any(x["is_hole"] for x in proposal["contours"]))
        self.assertFalse(proposal["accepted"])
        empty, refused = worker.component_proposal(categories, confidence, {"x": .95, "y": .95})
        self.assertIsNone(empty)
        self.assertEqual(refused["status"], "no_proposal")
        shifted = confidence.copy()
        shifted[20, 30] = .4
        same_mask, audited = worker.component_proposal(categories, shifted, {"x": .3, "y": .3})
        self.assertTrue(np.array_equal(mask, same_mask))
        self.assertEqual(audited["category_confidence_disagreement_pixels"], 1)
        with self.assertRaises(worker.InputError):
            worker.component_proposal(np.ones_like(categories), confidence, {"x": .3, "y": .3})

    def test_source_integrity_request_and_cli_guards(self):
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            source = directory / "source.png"
            source.write_bytes(b"not an image")
            value = request(source, directory / "out", "segment_aoi", {"prompt": {"x": .5, "y": .5}})
            value["source_hash"] = "0" * 64
            with self.assertRaises(worker.InputError):
                worker.run(value)
            value["source_hash"] = worker.digest(source)
            request_path = directory / "request.json"
            request_path.write_text(json.dumps(value), encoding="utf-8")
            done = subprocess.run([sys.executable, str(ROOT / "scripts/workers/vision.py"), "--request", str(request_path),
                                   "--output", str(source)], capture_output=True, timeout=30)
            self.assertEqual(done.returncode, 2)
            self.assertEqual(source.read_bytes(), b"not an image")
            for invalid in ([], {"source_path": {"invalid": True}}):
                request_path.write_text(json.dumps(invalid), encoding="utf-8")
                output = directory / "invalid-result.json"
                done = subprocess.run([sys.executable, str(ROOT / "scripts/workers/vision.py"), "--request", str(request_path),
                                       "--output", str(output)], capture_output=True, timeout=30)
                self.assertEqual(done.returncode, 2)
                self.assertEqual(json.loads(output.read_text())["status"], "error")


@unittest.skipUnless(VERSION == "1.0.1", "Video requires the pinned media environment")
class VideoTests(unittest.TestCase):
    def test_actual_vfr_pts_and_negative_all_models(self):
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            source = directory / "original-blank-vfr.mp4"
            # Ten original black frames with a deliberate 120 ms middle interval.
            subprocess.run([worker.executable("ffmpeg"), "-v", "error", "-f", "lavfi", "-i", "color=c=black:s=160x120:r=25:d=0.4",
                            "-vf", r"setpts=if(lt(N\,5)\,N/(25*TB)\,(N+2)/(25*TB))", "-fps_mode", "vfr", "-c:v", "libx264",
                            "-pix_fmt", "yuv420p", "-y", str(source)], check=True, capture_output=True, timeout=30)
            value = request(source, directory / "artifacts", "analyse_video", {"profile": "face_pose_hands_v1"})
            result = worker.run(value)
            self.assertEqual(result["status"], "insufficient_support")
            self.assertTrue(result["quality"]["pts_validated"])
            self.assertEqual(result["quality"]["analysed_frames"], 10)
            pts = [x["model_timestamp_ms"] for x in result["observations"]]
            self.assertEqual(pts, [0, 40, 80, 120, 160, 280, 320, 360, 400, 440])
            self.assertEqual(result["features"], [])
            for channel in ("face", "pose", "hands"):
                self.assertEqual(result["quality"]["channels"][channel]["valid_frames"], 0)
                self.assertEqual(result["quality"]["channels"][channel]["valid_time_s"], 0)
            artifact = result["artifacts"][0]
            self.assertEqual(worker.digest(artifact["path"]), artifact["sha256"])
            self.assertEqual(len(Path(artifact["path"]).read_text().splitlines()), 10)
            self.assertEqual(result["source"]["sha256"], worker.digest(source))
            self.assertEqual(len(result["engine"]["models"]), 3)


@unittest.skipUnless(VERSION == "0.10.21", "Segmentation requires the isolated legacy environment")
class SegmentationTests(unittest.TestCase):
    def test_real_existing_sample_and_opaque_palette_and_grayscale(self):
        def png_chunk(kind, payload):
            return struct.pack(">I", len(payload)) + kind + payload + struct.pack(">I", zlib.crc32(kind + payload) & 0xffffffff)
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            palette = directory / "original-palette.png"
            indexes = np.zeros((120, 160), dtype=np.uint8); indexes[25:95, 45:115] = 1
            rows = b"".join(b"\x00" + row.tobytes() for row in indexes)
            palette.write_bytes(b"\x89PNG\r\n\x1a\n" + png_chunk(b"IHDR", struct.pack(">IIBBBBB", 160, 120, 8, 3, 0, 0, 0))
                                + png_chunk(b"PLTE", bytes([220,220,220,30,100,210])) + png_chunk(b"IDAT", zlib.compress(rows)) + png_chunk(b"IEND", b""))
            grayscale = directory / "original-grayscale.png"
            cv2.imwrite(str(grayscale), np.where(indexes == 1, 40, 220).astype(np.uint8))
            for source, color in [(ROOT / "examples/stimuli/sample-design-a.png", 3), (palette, 3), (grayscale, 0)]:
                original = worker.digest(source)
                value = request(source, directory / "artifacts", "segment_aoi", {"prompt": {"x": .5, "y": .5}})
                result = worker.run(value)
                self.assertEqual(result["status"], "needs_review")
                self.assertEqual(result["parameters"]["source_png_color_type"], color)
                self.assertEqual(worker.digest(source), original)
                self.assertEqual(result["source"]["sha256"], original)
                self.assertEqual(result["parameters"]["source_transform"], "identity")
            transparent = directory / "transparent-palette.png"
            data = palette.read_bytes(); marker = data.index(b"IDAT") - 4
            transparent.write_bytes(data[:marker] + png_chunk(b"tRNS", bytes([0,255])) + data[marker:])
            with self.assertRaisesRegex(worker.InputError, "Transparent"):
                worker.run(request(transparent, directory / "artifacts", "segment_aoi", {"prompt": {"x": .5, "y": .5}}))

    def test_real_magictouch_original_rectangle(self):
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            source = directory / "original-synthetic.png"
            rgb = np.full((240, 320, 3), 220, dtype=np.uint8)
            rgb[55:185, 95:225] = [30, 100, 210]
            rgb[75:90, 105:215] = [210, 120, 20]
            self.assertTrue(cv2.imwrite(str(source), cv2.cvtColor(rgb, cv2.COLOR_RGB2BGR)))
            value = request(source, directory / "artifacts", "segment_aoi", {"prompt": {"x": .5, "y": .5}})
            result = worker.run(value)
            self.assertEqual(result["status"], "needs_review")
            proposal = result["proposal"]
            self.assertFalse(proposal["accepted"])
            mask = cv2.imread(proposal["mask_path"], cv2.IMREAD_GRAYSCALE)
            self.assertEqual(set(np.unique(mask)), {0, 255})
            expected = np.zeros((240, 320), dtype=bool)
            expected[55:185, 95:225] = True
            predicted = mask == 255
            iou = (expected & predicted).sum() / (expected | predicted).sum()
            self.assertGreater(iou, .8)  # Only this original, deliberately simple fixture.
            self.assertEqual(worker.digest(proposal["mask_path"]), proposal["mask_sha256"])
            self.assertEqual(proposal["source_hash"], worker.digest(source))
            self.assertEqual(result["parameters"]["native_foreground_category"], 0)
            self.assertTrue(result["quality"]["researcher_review_required"])

    def test_transparency_and_prompt_bounds_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            source = directory / "transparent.png"
            cv2.imwrite(str(source), np.zeros((32, 32, 4), dtype=np.uint8))
            value = request(source, directory / "artifacts", "segment_aoi", {"prompt": {"x": .5, "y": .5}})
            with self.assertRaisesRegex(worker.InputError, "Transparent"):
                worker.run(value)
            value["metadata"]["prompt"]["x"] = 1.1
            with self.assertRaisesRegex(worker.InputError, "prompt.x"):
                worker.run(value)


if __name__ == "__main__":
    unittest.main(verbosity=2)
