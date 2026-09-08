"""Pinned legacy MediaPipe/MagicTouch CPU contract probe on an in-memory fixture."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ENV = (ROOT / "../../work/tooling/segmentation-venv").resolve()
os.environ.setdefault("MPLCONFIGDIR", str(ENV / "matplotlib-cache"))
os.environ.setdefault("MPLBACKEND", "Agg")
MODEL_SHA256 = "e24338a717c1b7ad8d159666677ef400babb7f33b8ad60c4d96db4ecf694cd25"
MODEL_URL = "https://storage.googleapis.com/mediapipe-models/interactive_segmenter/magic_touch/float32/1/magic_touch.tflite"
MODEL_GENERATION = "1683146867404767"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", type=Path, default=ENV / "models/magic_touch_v1.tflite")
    parser.add_argument("--output", type=Path, default=ROOT / "docs/preparation/segmentation-results.json")
    args = parser.parse_args()
    import numpy as np
    import mediapipe as mp
    from mediapipe.tasks.python import BaseOptions
    from mediapipe.tasks.python.components.containers import keypoint
    from mediapipe.tasks.python.vision import interactive_segmenter

    checks = []

    def check(name: str, passed: bool, actual: object) -> None:
        checks.append({"id": name, "passed": bool(passed), "actual": actual,
                       "evidence": "synthetic model execution / output contract"})
        if not passed:
            raise AssertionError(f"{name}: {actual}")

    check("pinned_mediapipe", mp.__version__ == "0.10.21", mp.__version__)
    digest = hashlib.sha256(args.model.read_bytes()).hexdigest()
    check("pinned_magictouch_v1_hash", digest == MODEL_SHA256, digest)

    # Original synthetic fixture, never read from a camera and never written as an image.
    rgb = np.full((240, 320, 3), 220, dtype=np.uint8)
    rgb[55:185, 95:225] = [30, 100, 210]
    rgb[75:90, 105:215] = [210, 120, 20]
    image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)
    options = interactive_segmenter.InteractiveSegmenterOptions(
        base_options=BaseOptions(model_asset_path=str(args.model), delegate=BaseOptions.Delegate.CPU),
        output_category_mask=True,
        output_confidence_masks=True,
    )
    roi = interactive_segmenter.RegionOfInterest(
        format=interactive_segmenter.RegionOfInterest.Format.KEYPOINT,
        keypoint=keypoint.NormalizedKeypoint(x=0.5, y=0.5),
    )
    with interactive_segmenter.InteractiveSegmenter.create_from_options(options) as segmenter:
        result = segmenter.segment(image, roi)
        categories = result.category_mask.numpy_view().copy()
        confidence = [mask.numpy_view().copy() for mask in result.confidence_masks]
    check("category_shape", categories.shape == (240, 320), list(categories.shape))
    # This particular model has one confidence channel. The pinned upstream C++
    # calculator assigns 0 to foreground and 255 to background at a >0.5 cutoff.
    check("category_type_and_ids", categories.dtype == np.uint8 and set(np.unique(categories)) <= {0, 255},
          {"dtype": str(categories.dtype), "ids": [int(x) for x in np.unique(categories)]})
    check("confidence_shape", len(confidence) == 1 and all(x.shape == (240, 320) for x in confidence),
          [list(x.shape) for x in confidence])
    check("confidence_finite_and_bounded", all(np.isfinite(x).all() and (x >= 0).all() and (x <= 1).all()
          for x in confidence), [{"min": float(x.min()), "max": float(x.max())} for x in confidence])

    report = {
        "schema": "brohn-segmentation-reference/0.1", "generated": datetime.now(timezone.utc).isoformat(),
        "python": platform.python_version(), "platform": platform.platform(),
        "origin": "synthetic/reference", "application_integration": False,
        "mediapipe": mp.__version__, "numpy": np.__version__, "delegate": "CPU",
        "model": {"name": "MagicTouch v1 float32", "bytes": args.model.stat().st_size,
                  "source_url": MODEL_URL, "provider_generation": MODEL_GENERATION,
                  "pinned_download_url": MODEL_URL + "?generation=" + MODEL_GENERATION,
                  "sha256": digest},
        "checks_passed": len(checks), "checks": checks,
        "foreground_pixels": int(np.count_nonzero(categories == 0)),
        "mask_encoding": {"foreground_category": 0, "background_category": 255,
                          "confidence_channels": 1, "upstream_foreground_cutoff": ">0.5"},
        "probe_correction": "Initial two-class 0/1 assumption failed. Pinned upstream C++ source establishes single-channel MagicTouch uses foreground 0/background 255; assertions now require that specific encoding.",
        "limitations": [
            "This is a synthetic inference and shape/finite-value probe; no segmentation accuracy benchmark was run.",
            "A keypoint prompts an object/background mask; no semantic AOI label, temporal tracking or human-reviewed AOI is produced.",
            "The installed combination is MediaPipe 0.10.21 with MagicTouch v1, not MagicTouch v2 or MediaPipe 1.0.1.",
            "No participant media, camera/microphone capture or model weights were added to the repository.",
        ],
    }
    args.output.write_text(json.dumps(report, indent=2, allow_nan=False) + "\n", encoding="utf-8")
    print(f"{len(checks)} segmentation checks passed; {report['foreground_pixels']} foreground pixels")


if __name__ == "__main__":
    main()
