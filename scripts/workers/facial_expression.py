"""Pinned optional local AU/native-category extraction from consented saved video.

No identity, screen gaze, emotion truth, network inference or implicit downloads.
"""
from __future__ import annotations

import argparse
from collections import Counter
from contextlib import ExitStack
from decimal import Decimal, InvalidOperation
from fractions import Fraction
import csv
import hashlib
import importlib.metadata
import json
import math
import os
from pathlib import Path
import platform
import re
import subprocess
import sys
import tempfile

from vision import InputError, require, digest, read_json, atomic_json, inspect_video

ROOT = Path(__file__).resolve().parents[2]
PROFILE = "facial_au_expression_pyfeat_v1"
AUS = [f"AU{x:02d}" for x in (1, 2, 4, 5, 6, 7, 9, 10, 11, 12, 14, 15, 17, 20, 23, 24, 25, 26, 28, 43)]
CATEGORIES = ["anger", "disgust", "fear", "happiness", "sadness", "surprise", "neutral"]
BOX = ["FaceRectX", "FaceRectY", "FaceRectWidth", "FaceRectHeight", "FaceScore"]
MAX_SELECTED = 300
MAX_FACES = 16
MAX_ARTIFACT_BYTES = 64 * 1024 * 1024


def rational(value):
    return {"numerator": str(value.numerator), "denominator": str(value.denominator)}


def decimal_bound(value, field):
    require(isinstance(value, str) and len(value) <= 80 and re.fullmatch(r"(?:0|[1-9][0-9]*)(?:\.[0-9]+)?", value),
            f"{field} needs nonnegative decimal seconds, without exponent notation.")
    number = Decimal(value)
    require(number.is_finite() and 0 <= number <= 600, f"{field} exceeds the 600-second profile.")
    return Fraction(number)


def validate_request(request):
    require(isinstance(request, dict) and set(request) == {"schema", "source_path", "source_hash", "metadata", "output_directory"},
            "Unsupported facial request fields.")
    require(request["schema"] == "brohn-facial-expression-request/1.0", "Unsupported facial request schema.")
    metadata = request["metadata"]
    require(isinstance(metadata, dict) and set(metadata) <= {"profile", "origin_statement", "consent_statement", "start_s", "end_s", "frame_stride", "max_support_gap_s"},
            "Unsupported facial extraction setting.")
    require(metadata.get("profile") == PROFILE, "Choose the registered modular AU/category profile.")
    for field in ("origin_statement", "consent_statement"):
        require(isinstance(metadata.get(field), str) and 1 <= len(metadata[field].strip()) <= 4000,
                f"A researcher {field.replace('_', ' ')} is required before local facial processing.")
    start = decimal_bound(metadata.get("start_s", "0"), "Window start")
    end = decimal_bound(metadata["end_s"], "Window end") if metadata.get("end_s") is not None else None
    require(end is None or end > start, "Window end must follow its start.")
    stride = metadata.get("frame_stride", 1)
    require(type(stride) is int and 1 <= stride <= 120, "Frame stride must be an integer from 1 to 120.")
    gap = metadata.get("max_support_gap_s", .25)
    require(type(gap) in (int, float) and math.isfinite(gap) and .001 <= gap <= 10, "Support gap must be from 0.001 to 10 seconds.")
    source = Path(request["source_path"]).resolve(strict=True)
    require(source.is_file() and 0 < source.stat().st_size <= 512 * 1024 * 1024, "Video exceeds the 512 MiB source bound.")
    require(isinstance(request["source_hash"], str) and re.fullmatch("[a-f0-9]{64}", request["source_hash"]), "Invalid original source SHA-256.")
    require(digest(source) == request["source_hash"], "Original video bytes changed.")
    directory = Path(request["output_directory"]).resolve(strict=True)
    require(directory.is_dir() and source.parent != directory, "Choose a separate existing attempt artifact directory.")
    return source, directory, start, end, stride, gap


def select_frames(info, start, end, stride):
    require(re.fullmatch(r"[1-9][0-9]*/[1-9][0-9]*", str(info["time_base"])), "Source time base is unavailable or invalid.")
    base = Fraction(info["time_base"])
    times = []
    for frame in info["frames"]:
        pts = frame.get("pts")
        require(type(pts) is int, "Every source frame needs an original integer PTS.")
        stamp = pts * base
        require(not times or stamp > times[-1], "Original integer PTS must increase strictly; no reset reconstruction is permitted.")
        # FFprobe's printed decimal is supplemental; the integer clock is authoritative.
        require(abs(stamp - Fraction(Decimal(frame["pts_time"]))) <= Fraction(1, 1000000), "Printed source PTS disagrees with its integer time base.")
        times.append(stamp)
    relative = [t - times[0] for t in times]
    require(relative[-1] <= 600, "Original video exceeds the 600-second profile.")
    picked = [i for i, t in enumerate(relative) if t >= start and (end is None or t <= end)]
    selected = picked[::stride]
    require(2 <= len(selected) <= MAX_SELECTED, f"Choose a window/explicit stride containing 2 to {MAX_SELECTED} analysed frames; no automatic subsampling is applied.")
    return times, relative, selected, len(picked)


def nullable_number(value, label, low=-math.inf, high=math.inf):
    try:
        number = float(value)
    except (TypeError, ValueError) as error:
        raise InputError(f"Native {label} has a nonnumeric value.") from error
    if math.isnan(number):
        return None
    require(math.isfinite(number) and low <= number <= high, f"Native {label} is outside its declared support.")
    return number


def convert_native(records):
    """Only named native outputs cross the provider boundary; no identity columns."""
    require(isinstance(records, list) and 1 <= len(records) <= MAX_FACES, "Native face rows exceed the supported profile.")
    faces = []
    for record in records:
        require(all(k in record for k in BOX + AUS + CATEGORIES), "Native output columns changed.")
        # Disabled branches must not become real output through a library default.
        for name, value in record.items():
            if re.fullmatch(r"Identity_[0-9]+", name) or name in ("Pitch", "Roll", "Yaw", "gaze_pitch", "gaze_yaw"):
                require(nullable_number(value, "disabled branch") is None, "A disabled identity/pose/gaze branch unexpectedly produced values.")
        score = nullable_number(record["FaceScore"], "face score", 0, 1)
        require(score is not None, "Native face score is missing.")
        if score < .5:
            require(score == 0 and all(nullable_number(record[k], k) is None for k in BOX[:-1] + AUS + CATEGORIES),
                    "Native no-face placeholder contains unsupported measurements.")
            continue
        bbox = {k: nullable_number(record[k], k) for k in BOX[:-1]}
        aus = {k: nullable_number(record[k], k, 0, 1) for k in AUS}
        categories = {k: nullable_number(record[k], k, 0, 1) for k in CATEGORIES}
        valid = all(v is not None for v in list(bbox.values()) + list(aus.values()) + list(categories.values()))
        if valid:
            require(bbox["FaceRectWidth"] > 0 and bbox["FaceRectHeight"] > 0, "Native bounding box has no area.")
            require(abs(sum(categories.values()) - 1) < 1e-4, "Native category softmax scores do not reconcile.")
        faces.append({"face_ordinal": len(faces) + 1, "valid": valid, "detection_score": score, "bbox": bbox,
                      "au_scores": aus, "expression_scores": categories})
    require(not faces or len(faces) == len(records), "Native placeholder and detected faces are mixed in one frame.")
    state = "no_face" if not faces else "multiple_faces" if len(faces) > 1 else "single_face" if faces[0]["valid"] else "invalid_native_output"
    return {"state": state, "face_count": len(faces), "eligible": state == "single_face", "faces": faces}


class Summary:
    def __init__(self, max_gap):
        self.states = Counter()
        self.valid_frames = 0
        self.faces = 0
        self.frames = 0
        self.previous = None
        self.gap = Fraction(Decimal(str(max_gap)))
        self.support = Fraction(0)
        self.sums = {k: 0.0 for k in AUS + CATEGORIES}
        self.integrals = dict(self.sums)

    def add(self, row, relative_time):
        self.frames += 1
        self.faces += row["face_count"]
        self.states[row["state"]] += 1
        if row["eligible"]:
            face = row["faces"][0]
            values = face["au_scores"] | face["expression_scores"]
            self.valid_frames += 1
            for key, value in values.items():
                self.sums[key] += value
            if self.previous is not None:
                prior_time, prior_values = self.previous
                dt = relative_time - prior_time
                if 0 < dt <= self.gap:
                    self.support += dt
                    for key, value in values.items():
                        self.integrals[key] += (value + prior_values[key]) / 2 * float(dt)
            self.previous = (relative_time, values)
        else:
            self.previous = None

    def features(self):
        return [{"family": "action_unit" if k in AUS else "native_expression_category", "metric": k,
                 "value": self.sums[k] / self.valid_frames if self.valid_frames else None,
                 "unit": "native_model_score_0_1", "aggregation": "arithmetic_mean_eligible_sampled_frames",
                 "valid_frames": self.valid_frames, "valid_time_s": float(self.support),
                 "time_weighted_mean": self.integrals[k] / float(self.support) if self.support else None,
                 "scope": "selected_recording_window"} for k in AUS + CATEGORIES]


def runtime_configuration():
    require(os.name == "nt" and sys.version_info[:2] == (3, 12), "This pinned optional profile currently requires Windows and Python 3.12.")
    manifest_path = ROOT / "scripts/readiness/facial-models.json"
    runtime_path = ROOT / "scripts/readiness/facial-runtime.json"
    manifest = read_json(manifest_path)
    runtime = read_json(runtime_path)
    model_dir = Path(os.environ.get("BROHN_FACIAL_MODEL_DIR", "")).resolve()
    bin_dir = Path(os.environ.get("BROHN_FACIAL_FFMPEG_DIR", "")).resolve()
    require(os.environ.get("BROHN_FACIAL_MODEL_DIR") and os.environ.get("BROHN_FACIAL_FFMPEG_DIR"),
            "Configure BROHN_FACIAL_MODEL_DIR and BROHN_FACIAL_FFMPEG_DIR for the isolated pinned optional profile.")
    checked = []
    for item in manifest["files"]:
        target = (model_dir / item["relative_path"]).resolve()
        require(target.is_relative_to(model_dir) and target.is_file() and target.stat().st_size == item["bytes"] and digest(target) == item["sha256"],
                f"Pinned facial model is missing or changed: {item['relative_path']}.")
        checked.append(target)
    for item in runtime["files"]:
        target = (bin_dir / item["relative_path"]).resolve()
        require(target.is_relative_to(bin_dir) and target.is_file() and target.stat().st_size == item["bytes"] and digest(target) == item["sha256"],
                "Pinned optional shared FFmpeg runtime is missing or changed.")
    package_dir = Path(importlib.metadata.distribution("py-feat").locate_file("")).resolve()
    for item in runtime["package_sources"]:
        require(digest(package_dir / item["path"]) == item["sha256"], "Installed Py-Feat source differs from the pinned wheel.")
    versions = {}
    for line in (ROOT / "scripts/readiness/requirements-facial-au.txt").read_text(encoding="utf-8-sig").splitlines():
        if not line.strip() or line.startswith("#"):
            continue
        name, version = line.split("==")
        actual = importlib.metadata.version(name)
        require(actual == version, f"Optional facial package version changed: {name}.")
        versions[name] = actual
    os.environ.update(HF_HUB_OFFLINE="1", HF_HUB_DISABLE_TELEMETRY="1", MPLBACKEND="Agg", OMP_NUM_THREADS="1", OPENBLAS_NUM_THREADS="1")
    os.environ.pop("FEAT_POSE_MLP_PATH", None)
    os.environ["PATH"] = str(bin_dir) + os.pathsep + os.environ.get("PATH", "")
    dll_handle = os.add_dll_directory(str(bin_dir))
    return manifest, runtime, model_dir, versions, dll_handle


def load_provider():
    manifest, runtime, model_dir, versions, dll_handle = runtime_configuration()
    import huggingface_hub
    loaded = set()

    def pinned_download(repo_id, filename, **kwargs):
        items = [x for x in manifest["files"] if x["repo_id"] == repo_id and x["filename"] == filename]
        require(len(items) == 1, "This auxiliary model is excluded from the AU/category-only profile.")
        item = items[0]
        loaded.add((repo_id, filename))
        return str(model_dir / item["relative_path"])

    # Path resolution only: native prediction code remains unmodified. This
    # rejects hub fallback/default branches before any network call can occur.
    huggingface_hub.hf_hub_download = pinned_download
    import feat
    import torch
    from feat.utils import face_pose_mlp
    require(face_pose_mlp._resolve_weights_path() is None and not face_pose_mlp._CACHE,
            "Unregistered local pose weights would bypass the selected facial profile.")
    torch.set_num_threads(1)
    torch.set_num_interop_threads(1)
    detector = feat.Detectorv1(**manifest["detector"])
    require(loaded == {(x["repo_id"], x["filename"]) for x in manifest["files"]}, "Native detector did not load every pinned selected asset.")
    # A seventeenth detection is a refusal, never a silently truncated result.
    detector.facepose_detector.keep_top_k = MAX_FACES + 1
    engine = {"name": "Py-Feat Detectorv1", "version": "2.0.0", "python": platform.python_version(), "packages": versions,
              "models": manifest["files"], "manifest_sha256": digest(ROOT / "scripts/readiness/facial-models.json"),
              "runtime_manifest_sha256": digest(ROOT / "scripts/readiness/facial-runtime.json"),
              "requirements_sha256": digest(ROOT / "scripts/readiness/requirements-facial-au.txt"),
              "provider_sha256": digest(Path(__file__)), "video_inspector_sha256": digest(ROOT / "scripts/workers/vision.py")}
    return detector, engine, dll_handle


def native_frame(detector, rgb):
    import numpy as np
    import torch
    tensor = torch.from_numpy(np.array(rgb, dtype=np.uint8, copy=True)).permute(2, 0, 1).unsqueeze(0)
    detections = detector.facepose_detector(tensor)
    require(len(detections) == 1 and len(detections[0]) <= MAX_FACES, "Frame exceeds the 16-face profile; no partial-face export is published.")
    fex = detector.detect(tensor, data_type="tensor", batch_size=1, num_workers=0, pin_memory=False,
                          face_detection_threshold=.5, progress_bar=False)
    require(list(fex.au_columns) == AUS and list(fex.emotion_columns) == CATEGORIES and list(fex.facebox_columns) == BOX,
            "Native model output vocabulary changed.")
    return convert_native(fex.to_dict(orient="records"))


def promote_artifact(temp, kind, media_type):
    # Content identity is in the manifest; short persistent names support long workspaces.
    path = temp.with_suffix("")
    require(not path.exists(), "Artifact output collision.")
    temp.rename(path)
    return {"kind": kind, "path": str(path), "sha256": digest(path), "bytes": path.stat().st_size,
            "media_type": media_type, "complete": True, "schema": "brohn-facial-observations/1.0"}


def analyse(request):
    source, directory, start, end, stride, gap = validate_request(request)
    detector, engine, dll_handle = load_provider()
    import numpy as np
    info = inspect_video(source)
    times, relative, selected, interval_frames = select_frames(info, start, end, stride)
    selected_set = set(selected)
    frame_bytes = info["width"] * info["height"] * 3
    summary, preview = Summary(gap), []
    decoder = None
    source_sha = request["source_hash"]
    headers = ["frame_index", "source_pts", "source_time_base", "source_pts_s", "relative_time_numerator", "relative_time_denominator", "time_s", "state", "face_count", "eligible", "face_ordinal", "face_valid"] + BOX + AUS + CATEGORIES
    try:
        with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", suffix=".tmp", dir=directory, delete=False) as ndjson, \
             tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", newline="", suffix=".tmp", dir=directory, delete=False) as csvfile:
            jsonpath, csvpath = Path(ndjson.name), Path(csvfile.name)
            writer = csv.DictWriter(csvfile, fieldnames=headers)
            writer.writeheader()
            decoder = subprocess.Popen([info["ffmpeg"], "-v", "error", "-nostdin", "-protocol_whitelist", "file,pipe", "-noautorotate", "-i", str(source),
                                        "-map", "0:v:0", "-an", "-sn", "-dn", "-pix_fmt", "rgb24", "-f", "rawvideo", "-fps_mode", "passthrough", "pipe:1"],
                                       stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, creationflags=subprocess.CREATE_NO_WINDOW)
            for index, frame in enumerate(info["frames"]):
                raw = decoder.stdout.read(frame_bytes)
                require(len(raw) == frame_bytes, "Decoded video and pinned PTS frame counts disagree.")
                if index not in selected_set:
                    continue
                observed = native_frame(detector, np.frombuffer(raw, np.uint8).reshape(info["height"], info["width"], 3))
                row = {"frame_index": index, "source_pts": str(frame["pts"]), "source_time_base": info["time_base"],
                       "source_pts_s": frame["pts_time"], "source_time": rational(times[index]), "relative_time": rational(relative[index]),
                       "time_s": float(relative[index]), "decoded_rgb_sha256": hashlib.sha256(raw).hexdigest(), **observed}
                ndjson.write(json.dumps(row, allow_nan=False, separators=(",", ":")) + "\n")
                for face in row["faces"] or [None]:
                    cells = {k: row[k] for k in headers if k in row}
                    cells.update(relative_time_numerator=row["relative_time"]["numerator"], relative_time_denominator=row["relative_time"]["denominator"])
                    if face:
                        cells.update(face_ordinal=face["face_ordinal"], face_valid=face["valid"], FaceScore=face["detection_score"], **face["bbox"], **face["au_scores"], **face["expression_scores"])
                    writer.writerow(cells)
                require(ndjson.tell() <= MAX_ARTIFACT_BYTES and csvfile.tell() <= MAX_ARTIFACT_BYTES, "Complete facial artifacts exceed the 64 MiB bound.")
                summary.add(row, relative[index])
                if len(preview) < 50:
                    preview.append(row)
            require(decoder.stdout.read(1) == b"" and decoder.wait(timeout=30) == 0, "Decoded video has extra frames or a decode failure.")
        require(digest(source) == source_sha, "Original video changed during inference.")
        # No mid-run model replacement can acquire a trusted result receipt.
        model_dir = Path(os.environ["BROHN_FACIAL_MODEL_DIR"])
        require(all(digest(model_dir / x["relative_path"]) == x["sha256"] for x in engine["models"]), "Facial model bytes changed during inference.")
        artifacts = [promote_artifact(jsonpath, "facial-observations", "application/x-ndjson"), promote_artifact(csvpath, "facial-values", "text/csv")]
        return {"schema": "brohn-facial-expression-result/1.0", "status": "completed", "kind": "facial_expression",
                "title": "Native facial action units and expression categories", "source": {"sha256": source_sha, "bytes": source.stat().st_size},
                "engine": {**engine, "ffprobe": info["ffprobe_version"], "ffmpeg": info["ffmpeg_version"]},
                "parameters": {**request["metadata"], "frame_stride": stride, "max_support_gap_s": gap, "face_detection_threshold": .5,
                               "identity_model": None, "gaze_model": None, "pose_model": None, "device": "cpu", "threads": 1,
                               "width": info["width"], "height": info["height"], "source_time_base": info["time_base"],
                               "source_time_origin": rational(times[0]), "source_pts_origin_s": info["frames"][0]["pts_time"],
                               "orientation": "encoded upright pixels; no autorotation, crop or resize",
                               "frame_selection": "closed exact relative-PTS window, then every declared Nth frame from its first included frame",
                               "bbox_coordinates": "native encoded-image pixels; not calibrated physical geometry",
                               "time_support_policy": "adjacent eligible sampled frames only; trapezoidal support; no last-frame extrapolation; gaps above cutoff excluded"},
                "quality": {"source_frames": info["frame_count"], "interval_frames": interval_frames, "analysed_frames": summary.frames,
                            "skipped_interval_frames": interval_frames - summary.frames, "face_observations": summary.faces,
                            "eligible_single_face_frames": summary.valid_frames, "states": dict(summary.states),
                            "eligible_time_s": float(summary.support), "eligible_time_exact": rational(summary.support),
                            "identity_tracking": False, "pts_validated": True, "preview_frames": len(preview), "preview_truncated": summary.frames > len(preview),
                            "usable": summary.valid_frames > 0},
                "features": summary.features(), "preview": preview, "artifacts": artifacts, "contrasts": [],
                "limitations": ["Native AU/category scores are model estimates, not FACS intensity annotations or measured inner emotion, happiness, attention or preference.",
                                "Native category names are preserved. AU07 uses a different decision objective; its score need not behave like the other AU scores.",
                                "No-face rows are missing, never neutral or zero expression. Multiple faces remain separate within the frame and are excluded from aggregate summaries.",
                                "Per-frame face ordinals do not identify or link a person across frames. Even a single-face sequence is not proof that the same participant remained present.",
                                "Video PTS is the imported file clock, not qualified acquisition timing or synchronization to study events.",
                                "Selected stride skips unobserved source frames explicitly; no detection or physiological value is inferred for those frames.",
                                "Software agreement with the native library does not establish accuracy, demographic fairness or construct validity for a study."]}
    finally:
        if decoder is not None:
            if decoder.poll() is None:
                decoder.kill()
                decoder.wait(timeout=15)
            decoder.stdout.close()
        dll_handle.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--request", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    require(not args.output.exists(), "Refusing to overwrite an existing worker result.")
    try:
        result = analyse(read_json(args.request))
    except Exception as error:
        result = {"schema": "brohn-facial-expression-result/1.0", "status": "error",
                  "error": {"type": type(error).__name__, "message": str(error)[:1500] if isinstance(error, InputError) else "Optional facial provider failed; inspect the retained attempt log and pinned installation."}}
        atomic_json(args.output, result)
        raise
    atomic_json(args.output, result)


if __name__ == "__main__":
    main()
