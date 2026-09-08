"""Cache official model artifacts outside the repo; preserve download identities.

The first download records observed hashes, not publisher-signed verification.
Later runs require those hashes and use generation/commit-pinned download URLs.
"""
import argparse
import hashlib
import json
from pathlib import Path
import urllib.request

parser = argparse.ArgumentParser()
parser.add_argument("--model-dir", type=Path, required=True)
parser.add_argument("--manifest", type=Path, required=True)
args = parser.parse_args()
repo = Path(__file__).resolve().parents[2]
cache = args.model_dir.resolve()
if cache == repo or repo in cache.parents:
    raise ValueError("Model cache must be outside the repository")
cache.mkdir(parents=True, exist_ok=True)
base = "https://storage.googleapis.com/mediapipe-models/"
sources = {
    "face_landmarker.task": base + "face_landmarker/face_landmarker/float16/latest/face_landmarker.task",
    "pose_landmarker_lite.task": base + "pose_landmarker/pose_landmarker_lite/float16/latest/pose_landmarker_lite.task",
    "hand_landmarker.task": base + "hand_landmarker/hand_landmarker/float16/latest/hand_landmarker.task",
    "efficientdet_lite0.tflite": base + "object_detector/efficientdet_lite0/int8/latest/efficientdet_lite0.tflite",
    "interactive_segmentation.task": base + "interactive_segmenter_v2/magic_touch/int8/latest/interactive_segmentation.task",
    "silero_vad.onnx": "https://raw.githubusercontent.com/snakers4/silero-vad/be95df9152c0d7618fa1edfeb296fc3dae32376f/src/silero_vad/data/silero_vad.onnx",
}
existing = {}
if args.manifest.exists():
    existing = {item["filename"]: item for item in json.loads(args.manifest.read_text(encoding="utf-8"))["models"]}
records = []
for name, source_url in sources.items():
    path = cache / name
    prior = existing.get(name)
    if path.exists() and not prior:
        raise ValueError(f"Unregistered model already exists: {path}")
    if not path.exists():
        url = prior["pinned_download_url"] if prior else source_url
        with urllib.request.urlopen(url, timeout=60) as response:
            payload = response.read(32 * 1024 * 1024 + 1)
            headers = dict(response.headers)
        if len(payload) > 32 * 1024 * 1024:
            raise ValueError("Model exceeds 32 MiB bound")
        digest = hashlib.sha256(payload).hexdigest()
        if prior and digest != prior["sha256"]:
            raise ValueError(f"Pinned download hash mismatch: {name}")
        lower = {key.lower(): val for key, val in headers.items()}
        generation = lower.get("x-goog-generation")
        pinned = source_url + "?generation=" + generation if generation else source_url
        prior = prior or dict(filename=name, source_url=source_url, pinned_download_url=pinned,
                              sha256=digest, bytes=len(payload), provider_generation=generation,
                              etag=lower.get("etag"), hash_basis="observed_first_official_https_download")
        path.write_bytes(payload)
    if hashlib.sha256(path.read_bytes()).hexdigest() != prior["sha256"]:
        raise ValueError(f"Cached model hash mismatch: {name}")
    records.append(prior)
    # Checkpoint each successful download so an interrupted run is recoverable.
    args.manifest.parent.mkdir(parents=True, exist_ok=True)
    checkpoint = dict(existing)
    checkpoint.update({item["filename"]: item for item in records})
    args.manifest.write_text(json.dumps(dict(schema="brohn-media-models/0.1.0", models=list(checkpoint.values())), indent=2) + "\n", encoding="utf-8")
print(json.dumps(dict(models=len(records), bytes=sum(item["bytes"] for item in records), cache=str(cache))))
