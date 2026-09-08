"""Model/API smoke and independent signal/geometry checks; no camera or microphone."""
import argparse
import hashlib
import importlib.metadata
import json
import os
from pathlib import Path
import platform

parser = argparse.ArgumentParser()
parser.add_argument("--model-dir", type=Path, required=True)
parser.add_argument("--manifest", type=Path, required=True)
parser.add_argument("--output", type=Path, required=True)
args = parser.parse_args()
os.environ["MPLBACKEND"] = "Agg"
import cv2
import numpy as np
import mediapipe as mp
from mediapipe.tasks.python import BaseOptions, vision
import onnxruntime as ort
import parselmouth
import librosa

checks = []
unavailable = []
def check(name, value, evidence, **details):
    checks.append(dict(name=name, passed=bool(value), evidence=evidence, **details))

manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
for model in manifest["models"]:
    actual = hashlib.sha256((args.model_dir / model["filename"]).read_bytes()).hexdigest()
    check("cached model hash: " + model["filename"], actual == model["sha256"], "artifact_integrity")
if not all(c["passed"] for c in checks):
    raise ValueError("Model bytes do not match manifest")

def base(name):
    return BaseOptions(model_asset_path=str((args.model_dir / name).resolve()), delegate=BaseOptions.Delegate.CPU)
blank = mp.Image(image_format=mp.ImageFormat.SRGB, data=np.zeros((256, 256, 3), dtype=np.uint8))
with vision.FaceLandmarker.create_from_options(vision.FaceLandmarkerOptions(
        base_options=base("face_landmarker.task"), output_face_blendshapes=True,
        output_facial_transformation_matrixes=True, num_faces=1)) as detector:
    face = detector.detect(blank)
    check("blank frame has no detected face", len(face.face_landmarks) == 0, "synthetic_negative_model_smoke")
with vision.PoseLandmarker.create_from_options(vision.PoseLandmarkerOptions(
        base_options=base("pose_landmarker_lite.task"), num_poses=1)) as detector:
    pose = detector.detect(blank)
    check("blank frame has no detected body", len(pose.pose_landmarks) == 0, "synthetic_negative_model_smoke")
with vision.HandLandmarker.create_from_options(vision.HandLandmarkerOptions(
        base_options=base("hand_landmarker.task"), num_hands=2)) as detector:
    hand = detector.detect(blank)
    check("blank frame has no detected hands", len(hand.hand_landmarks) == 0, "synthetic_negative_model_smoke")
with vision.ObjectDetector.create_from_options(vision.ObjectDetectorOptions(
        base_options=base("efficientdet_lite0.tflite"), max_results=10, score_threshold=0.5)) as detector:
    objects = detector.detect(blank)
    check("object detector returns bounded detection list", isinstance(objects.detections, list) and len(objects.detections) <= 10,
          "model_execution_smoke", detections=len(objects.detections))

scene = np.full((256, 256, 3), 240, dtype=np.uint8)
scene[60:196, 80:176] = [190, 30, 40]
scene_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=scene)
try:
    with vision.InteractiveSegmenter.create_from_options(vision.InteractiveSegmenterOptions(
            base_options=base("interactive_segmentation.task"))) as segmenter:
        # MediaPipe 1.0.1 has a stateful image + strokes API, unlike old point-ROI examples.
        segmenter.set_image(scene_image)
        mask = segmenter.segment([vision.InteractiveSegmenterStroke(
            brush_mode=vision.InteractiveSegmenterBrushMode.POSITIVE,
            points=[vision.InteractiveSegmenterStrokePoint(x=0.5, y=0.5)], is_completed=True)]).numpy_view()
        check("interactive segmentation returns aligned finite mask", mask.shape[:2] == (256, 256) and np.isfinite(mask).all(),
              "synthetic_model_execution_not_accuracy", shape=list(mask.shape), minimum=float(mask.min()), maximum=float(mask.max()))
except AttributeError as error:
    if "MpInteractiveSegmenterCreate" not in str(error):
        raise
    unavailable.append(dict(capability="mediapipe-1.0.1-interactive-segmentation-windows",
                            attempted=True, failure=str(error), fallback="OpenCV GrabCut; separately assessed compatible model version"))

grab_mask = np.zeros((256, 256), dtype=np.uint8)
cv2.grabCut(scene, grab_mask, (65, 45, 125, 165), np.zeros((1, 65), dtype=np.float64),
            np.zeros((1, 65), dtype=np.float64), 3, cv2.GC_INIT_WITH_RECT)
foreground = (grab_mask == cv2.GC_FGD) | (grab_mask == cv2.GC_PR_FGD)
expected = np.zeros((256, 256), dtype=bool)
expected[60:196, 80:176] = True
iou = float(np.logical_and(foreground, expected).sum() / np.logical_or(foreground, expected).sum())
check("GrabCut recovers known two-colour foreground", iou > 0.98, "synthetic_geometry_not_natural_image_accuracy", iou=iou)

gray = np.zeros((200, 240), dtype=np.uint8)
gray[40:130, 60:180] = 255
contours, _ = cv2.findContours(gray, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
check("AOI contour bounding box matches known geometry", cv2.boundingRect(contours[0]) == (60, 40, 120, 90), "independent_geometry")
rng = np.random.default_rng(42)
image_a = cv2.GaussianBlur(rng.integers(0, 256, (200, 240), dtype=np.uint8), (5, 5), 0)
image_b = cv2.warpAffine(image_a, np.float32([[1, 0, 4], [0, 1, 3]]), (240, 200))
points = np.array([[[x, y]] for y in [60, 100, 140] for x in [60, 100, 140, 180]], dtype=np.float32)
tracked, status, _ = cv2.calcOpticalFlowPyrLK(image_a, image_b, points, None,
                                            winSize=(21, 21), maxLevel=3,
                                            criteria=(cv2.TERM_CRITERIA_EPS | cv2.TERM_CRITERIA_COUNT, 30, 0.01))
valid = status.ravel().astype(bool)
delta = np.median((tracked - points)[valid, 0, :], axis=0)
check("optical flow recovers known image translation", valid.sum() >= 8 and np.allclose(delta, [4, 3], atol=0.2),
      "independent_geometry", median_translation_px=delta.tolist(), retained_points=int(valid.sum()))

fs = 16000
signal = 0.25 * np.sin(2 * np.pi * 220 * np.arange(fs * 2) / fs)
pitch = parselmouth.Sound(signal, sampling_frequency=fs).to_pitch_ac(pitch_floor=75, pitch_ceiling=500)
f0 = pitch.selected_array["frequency"]
voiced = f0[f0 > 0]
check("Praat pitch recovers known 220 Hz tone", len(voiced) > 0 and abs(float(np.median(voiced)) - 220) < 1,
      "independent_analytic", observed_hz=float(np.median(voiced)))
rms = float(librosa.feature.rms(y=signal, frame_length=len(signal), hop_length=len(signal), center=False)[0, 0])
check("audio RMS agrees with sine amplitude", np.isclose(rms, 0.25 / np.sqrt(2), atol=1e-7, rtol=0),
      "independent_analytic", observed=rms, expected=float(0.25 / np.sqrt(2)))

session = ort.InferenceSession(str(args.model_dir / "silero_vad.onnx"), providers=["CPUExecutionProvider"])
state = np.zeros((2, 1, 128), dtype=np.float32)
context = np.zeros((1, 64), dtype=np.float32)
probabilities = []
for _ in range(8):
    chunk = np.zeros((1, 512), dtype=np.float32)
    probability, state = session.run(None, {"input": np.concatenate([context, chunk], axis=1),
                                          "state": state, "sr": np.array(16000, dtype=np.int64)})
    probabilities.append(float(probability[0, 0]))
    context = chunk[:, -64:]
check("Silero returns finite recurrent probabilities", np.isfinite(probabilities).all() and all(0 <= p <= 1 for p in probabilities)
      and state.shape == (2, 1, 128), "model_execution_smoke")
check("Silero silence remains below 0.5 threshold", max(probabilities) < 0.5, "synthetic_negative_model_smoke",
      maximum_probability=max(probabilities))

report = dict(schema="brohn-media-readiness/0.1.0", production_enabled=False,
              status=("passed_with_unavailable_capability" if unavailable else "passed") if all(c["passed"] for c in checks) else "mismatch",
              python=platform.python_version(), packages={name: importlib.metadata.version(name) for name in
              ["mediapipe", "opencv-contrib-python", "onnxruntime", "praat-parselmouth", "librosa", "soundfile", "numpy"]},
              checks=checks, passed=sum(c["passed"] for c in checks), unavailable_capabilities=unavailable,
              model_manifest_sha256=hashlib.sha256(args.manifest.read_bytes()).hexdigest(),
              limitations=["No camera, microphone, real person or external media was used.",
                           "Blank-frame and silence checks do not establish positive detection accuracy, affect validity or live timing.",
                           "Interactive segmentation was checked for executable output shape, not object-boundary accuracy.",
                           "Geometry, blendshapes, object classes and voice activity are not emotion, screen gaze, transcription or rPPG."])
args.output.parent.mkdir(parents=True, exist_ok=True)
args.output.write_text(json.dumps(report, indent=2, allow_nan=False) + "\n", encoding="utf-8")
print(json.dumps(dict(status=report["status"], passed=report["passed"], checks=len(checks), unavailable=unavailable)))
raise SystemExit(0 if all(c["passed"] for c in checks) else 1)
