"""Local, bounded vision evidence and researcher-reviewed AOI proposals.

The two operations deliberately run in different pinned MediaPipe environments.
No model download, camera access, face identification or psychological labels.
"""
from __future__ import annotations

import argparse
from contextlib import ExitStack
from decimal import Decimal, InvalidOperation
import hashlib
import importlib.metadata
import json
import math
import os
from pathlib import Path
import platform
import shutil
import struct
import subprocess
import sys
import tempfile

os.environ.setdefault("MPLBACKEND", "Agg")
os.environ.setdefault("OMP_NUM_THREADS", "1")
os.environ.setdefault("OPENBLAS_NUM_THREADS", "1")
ROOT = Path(__file__).resolve().parents[2]
TOOLING = (ROOT / "../../work/tooling").resolve()
MAX_BYTES = 512 * 1024 * 1024
MAX_FRAMES = 36000
MAX_SECONDS = 600
MAX_PIXELS = 3840 * 2160
MAX_PREVIEW = 2000
MAX_PREVIEW_BYTES = 2 * 1024 * 1024
MODELS = {
    "face": ("face_landmarker.task", "64184e229b263107bc2b804c6625db1341ff2bb731874b0bcc2fe6544e0bc9ff"),
    "pose": ("pose_landmarker_lite.task", "59929e1d1ee95287735ddd833b19cf4ac46d29bc7afddbbf6753c459690d574a"),
    "hands": ("hand_landmarker.task", "fbc2a30080c3c557093b5ddfc334698132eb341044ccee322ccf8bcf3607cde1"),
}
SEGMENT_SHA = "e24338a717c1b7ad8d159666677ef400babb7f33b8ad60c4d96db4ecf694cd25"


class InputError(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise InputError(message)


def finite(value, name, low=-math.inf, high=math.inf):
    require(isinstance(value, (int, float)) and not isinstance(value, bool)
            and math.isfinite(value) and low <= value <= high,
            f"{name} must be a finite number from {low} to {high}.")
    return float(value)


def digest(path):
    value = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


def pairs(items):
    result = {}
    for key, value in items:
        require(key not in result, f"Duplicate JSON key: {key}.")
        result[key] = value
    return result


def read_json(path):
    require(Path(path).stat().st_size <= 2 * 1024 * 1024, "Request exceeds 2 MiB.")
    return json.loads(Path(path).read_text(encoding="utf-8-sig"), object_pairs_hook=pairs,
                      parse_constant=lambda x: (_ for _ in ()).throw(InputError("Nonfinite JSON number.")))


def atomic_json(path, result):
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", suffix=".tmp", dir=path.parent, delete=False) as stream:
        temporary = Path(stream.name)
        json.dump(result, stream, ensure_ascii=True, allow_nan=False, separators=(",", ":"))
        stream.write("\n")
    os.replace(temporary, path)


def artifact(path, directory, kind, suffix):
    sha = digest(path)
    target = directory / (kind + "-" + sha + suffix)
    if target.exists():
        require(digest(target) == sha, "Existing artifact hash mismatch.")
        path.unlink()
    else:
        os.replace(path, target)
    return {"kind": kind, "path": str(target), "sha256": sha, "bytes": target.stat().st_size}


def validate_request(request):
    require(isinstance(request, dict) and request.get("schema") == "brohn-vision-request/1.0", "Unsupported request schema.")
    require(request.get("operation") in ("analyse_video", "segment_aoi"), "Unsupported vision operation.")
    require(isinstance(request.get("metadata"), dict), "metadata must be an object.")
    require(isinstance(request.get("source_path"), str) and bool(request["source_path"].strip()), "source_path must name a local file.")
    source = Path(request["source_path"]).resolve()
    require(source.is_file() and 0 < source.stat().st_size <= MAX_BYTES, "Source must be a local file of at most 512 MiB.")
    sha = request.get("source_hash")
    require(isinstance(sha, str) and len(sha) == 64 and all(c in "0123456789abcdef" for c in sha), "source_hash must be lowercase SHA-256.")
    require(digest(source) == sha, "Source bytes do not match the pinned source_hash.")
    directory = request.get("output_directory")
    require(isinstance(directory, str) and bool(directory.strip()), "output_directory is required.")
    directory = Path(directory).resolve()
    require(directory != source, "Artifact directory cannot be the source.")
    directory.mkdir(parents=True, exist_ok=True)
    return source, directory


def pinned_model(channel):
    filename, sha = MODELS[channel]
    directory = Path(os.environ.get("BROHN_MEDIA_MODEL_DIR", str(TOOLING / "media-models")))
    path = directory / filename
    require(path.is_file() and digest(path) == sha, f"Missing or mismatched pinned {channel} model.")
    manifest = json.loads((ROOT / "docs/preparation/media-models.json").read_text(encoding="utf-8"))
    provenance = next((x for x in manifest["models"] if x["filename"] == filename and x["sha256"] == sha), None)
    require(provenance is not None, "Pinned model provenance is missing from the preparation manifest.")
    return path, {"channel": channel, "filename": filename, "sha256": sha, "bytes": path.stat().st_size,
                  "source_url": provenance["source_url"], "provider_generation": provenance["provider_generation"]}


def package_versions(names):
    return {name: importlib.metadata.version(name) for name in names}


def base_result(request, source):
    return {"schema": "brohn-vision-result/1.0", "operation": request["operation"],
            "source": {"sha256": request["source_hash"], "bytes": source.stat().st_size},
            "features": [], "observations": [], "quality": {}, "parameters": {},
            "limitations": [], "artifacts": []}


def executable(name):
    path = shutil.which(name)
    require(path is not None, f"Prepared {name} executable is unavailable on PATH.")
    return path


def probe_json(command):
    # FFprobe writes into a temporary file, so even a malformed source cannot
    # inflate the worker's JSON memory before the explicit size check.
    with tempfile.TemporaryFile() as output:
        completed = subprocess.run(command, stdout=output, stderr=subprocess.PIPE, timeout=120, check=False)
        require(completed.returncode == 0, "FFprobe could not decode the imported video.")
        require(output.tell() <= 20 * 1024 * 1024, "Video metadata exceeds 20 MiB.")
        output.seek(0)
        return json.load(output)


def validate_pts(frames):
    require(2 <= len(frames) <= MAX_FRAMES, "Video must contain 2 to 36,000 decoded frames.")
    timestamps = []
    for frame in frames:
        value = frame.get("pts_time")
        require(isinstance(value, str), "A decoded frame has no presentation timestamp; FPS reconstruction is not allowed.")
        try:
            stamp = Decimal(value)
        except InvalidOperation as error:
            raise InputError("Invalid video presentation timestamp.") from error
        require(stamp.is_finite(), "Nonfinite video presentation timestamp.")
        require(not timestamps or stamp > timestamps[-1], "Video PTS must be strictly increasing; duplicate/reversed frames are unsupported.")
        timestamps.append(stamp)
    require(0 < timestamps[-1] - timestamps[0] <= MAX_SECONDS, "Video PTS span must be at most 600 seconds.")
    milliseconds = [int((stamp - timestamps[0]) * 1000) for stamp in timestamps]
    require(all(b > a for a, b in zip(milliseconds, milliseconds[1:])),
            "Frame timestamps collide at the MediaPipe millisecond resolution.")
    return timestamps, milliseconds


def inspect_video(source):
    ffprobe = executable("ffprobe")
    prefix = [ffprobe, "-v", "error", "-protocol_whitelist", "file,pipe", "-format_whitelist", "mov,matroska,avi", "-select_streams", "v:0"]
    overview = probe_json(prefix + ["-count_frames", "-show_streams", "-show_format", "-of", "json", str(source)])
    streams = overview.get("streams", [])
    require(len(streams) == 1, "No readable video stream.")
    stream = streams[0]
    count = int(stream.get("nb_read_frames", 0))
    require(2 <= count <= MAX_FRAMES, "Decoded video frame count exceeds the 2 to 36,000 frame bounds.")
    width, height = int(stream.get("width", 0)), int(stream.get("height", 0))
    require(width > 0 and height > 0 and width * height <= MAX_PIXELS, "Video dimensions exceed the 4K pixel bound.")
    require(stream.get("sample_aspect_ratio", "1:1") in ("1:1", "N/A"), "Non-square pixels require an explicitly transformed source export.")
    rotations = [float(x.get("rotation", 0)) for x in stream.get("side_data_list", [])]
    require(all(x % 360 == 0 for x in rotations), "Rotate the source into upright pixels before analysis; implicit rotation is not applied.")
    frames = probe_json(prefix + ["-show_frames", "-show_entries", "frame=pts,pts_time,width,height", "-of", "json", str(source)]).get("frames", [])
    require(len(frames) == count, "FFprobe frame-count and timestamp passes disagree.")
    require(all(x.get("width") == width and x.get("height") == height for x in frames), "Changing video frame dimensions are unsupported.")
    timestamps, milliseconds = validate_pts(frames)
    version = subprocess.run([ffprobe, "-version"], capture_output=True, text=True, check=True, timeout=15).stdout.splitlines()[0]
    ffmpeg = executable("ffmpeg")
    decode_version = subprocess.run([ffmpeg, "-version"], capture_output=True, text=True, check=True, timeout=15).stdout.splitlines()[0]
    require(version.split()[2] == decode_version.split()[2], "FFprobe and FFmpeg versions must match for frame/PTS alignment.")
    return {"width": width, "height": height, "frames": frames, "timestamps": timestamps, "milliseconds": milliseconds,
            "ffmpeg": ffmpeg, "ffprobe_version": version, "ffmpeg_version": decode_version,
            "codec": stream.get("codec_name"), "time_base": stream.get("time_base"), "frame_count": count}


def landmark_rows(points):
    rows = []
    for point in points:
        row = {}
        for key in ("x", "y", "z", "visibility", "presence"):
            value = getattr(point, key, None)
            row[key] = float(value) if value is not None and math.isfinite(value) else None
        rows.append(row)
    return rows


def point_valid(point, visibility=False):
    valid = all(point.get(key) is not None and math.isfinite(point[key]) for key in ("x", "y", "z"))
    if visibility:
        valid = valid and point.get("visibility") is not None and point["visibility"] >= .5
    return bool(valid)


def distance(points, a, b, width, height):
    # Isotropic image-plane units: distance in pixels divided by image width.
    if not (point_valid(points[a]) and point_valid(points[b])):
        return None
    return math.hypot(points[a]["x"] - points[b]["x"], (points[a]["y"] - points[b]["y"]) * height / width)


def angle(points, a, b, c, width, height):
    if not all(point_valid(points[index], visibility=True) for index in (a, b, c)):
        return None
    u = ((points[a]["x"] - points[b]["x"]) * width, (points[a]["y"] - points[b]["y"]) * height)
    v = ((points[c]["x"] - points[b]["x"]) * width, (points[c]["y"] - points[b]["y"]) * height)
    divisor = math.hypot(*u) * math.hypot(*v)
    return math.degrees(math.acos(max(-1, min(1, sum(x * y for x, y in zip(u, v)) / divisor)))) if divisor > 0 else None


def face_observation(result, width, height):
    count = len(result.face_landmarks)
    output = {"count": count, "count_is_lower_bound": count == 2, "valid": False,
              "state": "absent" if count == 0 else "multiple" if count > 1 else "single",
              "landmarks": None, "blendshapes": None, "geometry": None}
    # Multiple faces are intentionally masked; no arbitrary first-face choice.
    if count != 1:
        return output
    points = landmark_rows(result.face_landmarks[0])
    require(len(points) >= 468, "Unexpected face landmark count.")
    finite_points = all(point_valid(p) for p in points)
    border = any(not (0 <= p["x"] <= 1 and 0 <= p["y"] <= 1) for p in points if point_valid(p))
    output.update(landmarks=points, image_border_contact=border, valid=finite_points and not border)
    if not output["valid"]:
        output["state"] = "invalid_geometry" if not finite_points else "border_geometry"
        return output
    shapes = {str(x.category_name): float(x.score) for x in result.face_blendshapes[0]}
    require(all(math.isfinite(x) and 0 <= x <= 1 for x in shapes.values()), "Invalid model blendshape output.")
    output["blendshapes"] = shapes
    output["geometry"] = {"outer_eye_distance_image_width": distance(points, 33, 263, width, height),
                          "lip_separation_image_width": distance(points, 13, 14, width, height)}
    return output


def pose_observation(result, width, height):
    count = len(result.pose_landmarks)
    output = {"count": count, "count_is_lower_bound": count == 2, "valid": False,
              "state": "absent" if count == 0 else "multiple" if count > 1 else "single", "landmarks": None, "geometry": None}
    if count != 1:
        return output
    points = landmark_rows(result.pose_landmarks[0])
    require(len(points) == 33, "Unexpected pose landmark count.")
    output["landmarks"] = points
    output["landmark_valid_mask"] = [point_valid(p, visibility=True) for p in points]
    geometry = {"left_elbow_angle_deg": angle(points, 11, 13, 15, width, height),
                "right_elbow_angle_deg": angle(points, 12, 14, 16, width, height)}
    output["valid"] = any(value is not None for value in geometry.values())
    output["state"] = "single" if output["valid"] else "insufficient_visible_joints"
    output["geometry"] = geometry
    return output


def hand_observation(result, width, height):
    output = {"count": len(result.hand_landmarks), "count_is_lower_bound": len(result.hand_landmarks) == 2,
              "valid": False, "state": "absent" if not result.hand_landmarks else "detected", "hands": []}
    labels = []
    for index, raw in enumerate(result.hand_landmarks):
        points = landmark_rows(raw)
        require(len(points) == 21, "Unexpected hand landmark count.")
        category = result.handedness[index][0]
        label, score = str(category.category_name), float(category.score)
        valid = all(point_valid(p) for p in points) and math.isfinite(score) and score >= .5
        palm = distance(points, 0, 9, width, height)
        pinch = distance(points, 4, 8, width, height)
        ratio = pinch / palm if valid and palm and pinch is not None else None
        labels.append(label)
        output["hands"].append({"frame_index": index, "handedness": label, "handedness_score": score,
                                "valid": valid and ratio is not None, "landmarks": points,
                                "geometry": {"thumb_index_distance_over_palm": ratio}})
    # Duplicate labels cannot be pooled into a stable left/right time series.
    for hand in output["hands"]:
        hand["summary_valid"] = hand["valid"] and labels.count(hand["handedness"]) == 1
    output["valid"] = any(x["summary_valid"] for x in output["hands"])
    return output


def metrics_for(row):
    values = {}
    for channel in ("face", "pose"):
        current = row.get(channel)
        if current and current["valid"]:
            for key, value in (current.get("geometry") or {}).items():
                if value is not None:
                    values[channel + "." + key] = value
            for key, value in (current.get("blendshapes") or {}).items():
                values["face.blendshape." + key] = value
    for hand in row.get("hands", {}).get("hands", []):
        if hand["summary_valid"]:
            values["hands." + hand["handedness"] + ".thumb_index_distance_over_palm"] = hand["geometry"]["thumb_index_distance_over_palm"]
    return values


def preview_row(row):
    """Large native landmark arrays remain in the complete hashed JSONL."""
    result = {key: row[key] for key in ("frame_index", "source_pts_s", "time_s", "model_timestamp_ms")}
    for channel in ("face", "pose"):
        if channel in row:
            result[channel] = {key: value for key, value in row[channel].items() if key not in ("landmarks", "landmark_valid_mask")}
    if "hands" in row:
        result["hands"] = {key: value for key, value in row["hands"].items() if key != "hands"}
        result["hands"]["hands"] = [{key: value for key, value in hand.items() if key != "landmarks"} for hand in row["hands"]["hands"]]
    return result


class Summary:
    def __init__(self, channels, max_gap):
        self.channels, self.max_gap = channels, max_gap
        self.frames, self.previous, self.elapsed_support = 0, None, 0.0
        self.channel_support = {x: {"valid_frames": 0, "valid_time_s": 0.0, "states": {}} for x in channels}
        self.metrics = {}

    def add(self, row):
        values = metrics_for(row)
        delta = row["time_s"] - self.previous["time_s"] if self.previous else 0
        supported_delta = delta if 0 < delta <= self.max_gap else 0
        self.elapsed_support += supported_delta
        previous_values = metrics_for(self.previous) if self.previous else {}
        self.frames += 1
        for channel, support in self.channel_support.items():
            state = row[channel]["state"]
            support["states"][state] = support["states"].get(state, 0) + 1
            support["valid_frames"] += int(row[channel]["valid"])
            if row[channel]["valid"] and self.previous and self.previous[channel]["valid"]:
                support["valid_time_s"] += supported_delta
        for key, value in values.items():
            info = self.metrics.setdefault(key, {"sum": 0.0, "n": 0, "area": 0.0, "seconds": 0.0})
            info["sum"] += value
            info["n"] += 1
            if key in previous_values:
                info["area"] += (previous_values[key] + value) / 2 * supported_delta
                info["seconds"] += supported_delta
        self.previous = row

    def result(self):
        features = []
        for key, info in sorted(self.metrics.items()):
            unit = "degrees" if key.endswith("_deg") else "model_score_0_1" if ".blendshape." in key else "ratio"
            features.append({"name": key, "value": info["sum"] / info["n"], "unit": unit,
                             "scope": "recording", "aggregation": "arithmetic_mean_valid_frames",
                             "valid_frames": info["n"], "valid_time_s": info["seconds"],
                             "time_weighted_mean": info["area"] / info["seconds"] if info["seconds"] > 0 else None})
        return features


def analyse_video(request, source, directory):
    import numpy as np
    import mediapipe as mp
    from mediapipe.tasks.python import BaseOptions, vision
    require(mp.__version__ == "1.0.1", "Video operation requires the prepared MediaPipe 1.0.1 environment.")
    meta = request["metadata"]
    require(set(meta) <= {"profile", "channels", "start_s", "end_s", "max_support_gap_s"}, "Unknown video metadata setting.")
    profile = meta.get("profile", "face_geometry_v1")
    profiles = {"face_geometry_v1": ["face"], "face_pose_hands_v1": ["face", "pose", "hands"]}
    require(profile in (*profiles, "custom_v1"), "Unsupported video profile.")
    channels = meta.get("channels") if profile == "custom_v1" else profiles[profile]
    require(isinstance(channels, list) and 0 < len(channels) <= 3 and len(set(channels)) == len(channels)
            and set(channels) <= set(MODELS), "Select unique face, pose or hands channels.")
    require("channels" not in meta or profile == "custom_v1", "Explicit channels require custom_v1 profile.")
    max_gap = finite(meta.get("max_support_gap_s", .25), "max_support_gap_s", .001, 10)
    info = inspect_video(source)
    first = info["timestamps"][0]
    relative = [float(x - first) for x in info["timestamps"]]
    start = finite(meta.get("start_s", 0), "start_s", 0, relative[-1])
    end = finite(meta.get("end_s", relative[-1]), "end_s", start, relative[-1])
    selected = [index for index, stamp in enumerate(relative) if start <= stamp <= end]
    require(len(selected) >= 2, "Selected interval must contain at least two decoded frames.")
    models = [pinned_model(channel) for channel in channels]
    result = base_result(request, source)
    result["engine"] = {"name": "MediaPipe", "version": mp.__version__, "python": platform.python_version(),
                        "packages": package_versions(["mediapipe", "numpy"]), "models": [x[1] for x in models],
                        "ffprobe": info["ffprobe_version"], "ffmpeg": info["ffmpeg_version"]}
    result["parameters"] = {"profile": profile, "channels": channels, "delegate": "CPU", "running_mode": "VIDEO",
                            "min_detection_confidence": .5, "min_presence_confidence": .5, "min_tracking_confidence": .5,
                            "max_faces": 2, "max_poses": 2, "max_hands": 2, "pose_visibility_cutoff": .5,
                            "start_s": start, "end_s": end, "max_support_gap_s": max_gap,
                            "timestamp_policy": "decoded presentation PTS; subtract first source PTS then floor to ms for model",
                            "source_pts_origin_s": str(first), "source_time_base": info["time_base"],
                            "width": info["width"], "height": info["height"], "orientation": "encoded pixels, no autorotation",
                            "landmark_coordinates": "normalized image x/y; native model z, not calibrated depth",
                            "geometry_coordinates": "isotropic image plane; distances divided by image width",
                            "preview_policy": "first up to 2000 compact analysed frames or 2 MiB; full native landmarks in JSONL artifact",
                            "time_support_policy": "adjacent valid endpoint pairs only; trapezoidal integral; gaps above cutoff excluded; no last-frame extrapolation"}
    summary, preview, preview_bytes, preview_full = Summary(channels, max_gap), [], 0, False
    temp_path = None
    decoder = None
    try:
        with ExitStack() as stack:
            detectors = {}
            for channel, (path, _) in zip(channels, models):
                common = {"base_options": BaseOptions(model_asset_path=str(path), delegate=BaseOptions.Delegate.CPU),
                          "running_mode": vision.RunningMode.VIDEO}
                if channel == "face":
                    detector = vision.FaceLandmarker.create_from_options(vision.FaceLandmarkerOptions(
                        **common, num_faces=2, output_face_blendshapes=True, output_facial_transformation_matrixes=False))
                elif channel == "pose":
                    detector = vision.PoseLandmarker.create_from_options(vision.PoseLandmarkerOptions(**common, num_poses=2))
                else:
                    detector = vision.HandLandmarker.create_from_options(vision.HandLandmarkerOptions(**common, num_hands=2))
                detectors[channel] = stack.enter_context(detector)
            stream = stack.enter_context(tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", suffix=".jsonl.tmp", dir=directory, delete=False))
            temp_path = Path(stream.name)
            decoder = subprocess.Popen([info["ffmpeg"], "-v", "error", "-nostdin", "-protocol_whitelist", "file,pipe",
                                        "-format_whitelist", "mov,matroska,avi", "-noautorotate", "-i", str(source),
                                        "-map", "0:v:0", "-an", "-sn", "-dn", "-fps_mode", "passthrough", "-pix_fmt", "rgb24",
                                        "-f", "rawvideo", "pipe:1"], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
            selected_set = set(selected)
            frame_bytes = info["width"] * info["height"] * 3
            for index in range(info["frame_count"]):
                raw = decoder.stdout.read(frame_bytes)
                require(len(raw) == frame_bytes, "FFmpeg decoded fewer frames than the pinned PTS timeline.")
                if index not in selected_set:
                    continue
                pixels = np.frombuffer(raw, dtype=np.uint8).reshape(info["height"], info["width"], 3)
                image = mp.Image(image_format=mp.ImageFormat.SRGB, data=np.ascontiguousarray(pixels))
                row = {"frame_index": index, "source_pts_s": str(info["timestamps"][index]), "time_s": relative[index],
                       "model_timestamp_ms": info["milliseconds"][index]}
                for channel, detector in detectors.items():
                    observed = detector.detect_for_video(image, info["milliseconds"][index])
                    mapper = {"face": face_observation, "pose": pose_observation, "hands": hand_observation}[channel]
                    row[channel] = mapper(observed, info["width"], info["height"])
                summary.add(row)
                stream.write(json.dumps(row, allow_nan=False, separators=(",", ":")) + "\n")
                require(stream.tell() <= 2 * 1024 * 1024 * 1024, "Full observation artifact exceeds 2 GiB; use a shorter explicit interval.")
                if not preview_full:
                    compact = preview_row(row)
                    encoded_size = len(json.dumps(compact, separators=(",", ":")))
                    if len(preview) < MAX_PREVIEW and preview_bytes + encoded_size <= MAX_PREVIEW_BYTES:
                        preview.append(compact)
                        preview_bytes += encoded_size
                    else:
                        preview_full = True
            require(decoder.stdout.read(1) == b"", "FFmpeg decoded additional frames absent from the PTS timeline.")
            require(decoder.wait(timeout=30) == 0, "FFmpeg decoding failed.")
        require(digest(source) == request["source_hash"], "Source changed during analysis.")
        result["artifacts"] = [artifact(temp_path, directory, "vision-observations", ".jsonl")]
        temp_path = None
    finally:
        if decoder is not None:
            if decoder.poll() is None:
                decoder.kill()
                decoder.wait(timeout=15)
            decoder.stdout.close()
        if temp_path is not None and temp_path.exists():
            temp_path.unlink()
    result["features"] = summary.result()
    result["observations"] = preview
    result["quality"] = {"source_frames": info["frame_count"], "analysed_frames": summary.frames,
                         "preview_frames": len(preview), "preview_truncated": summary.frames > len(preview),
                         "observed_span_s": relative[selected[-1]] - relative[selected[0]],
                         "adjacent_time_support_s": summary.elapsed_support, "channels": summary.channel_support,
                         "pts_validated": True, "identity_tracking": False,
                         "usable": any(x["valid_frames"] for x in summary.channel_support.values())}
    result["status"] = "completed" if result["quality"]["usable"] else "insufficient_support"
    result["limitations"] = [
        "Native face blendshapes are rendering coefficients, not FACS AUs, emotion, happiness, calibrated gaze, attention or rPPG.",
        "No person identity or stable track is assigned. Counts saturate at two; multiple faces/poses are masked from summaries.",
        "Model thresholds do not establish detection accuracy or reveal all occlusion, lighting, demographic or camera failure modes.",
        "Image geometry is perspective-dependent; model z is not calibrated physical depth. Handedness is model-native and affected by mirroring.",
        "Frame means and adjacent-support time means are distinct; missing detections and long gaps are never replaced by zero.",
        "PTS is the imported file presentation clock, not a qualified camera capture clock or synchronization with study events.",
        "CPU delegate is explicit; native model thread scheduling is not controlled by the Python API. No temporal smoothing is added by Brohn.",
    ]
    return result


def component_proposal(categories, confidence, prompt):
    import cv2
    import numpy as np
    require(categories.ndim == 2 and categories.dtype == np.uint8 and set(np.unique(categories)) <= {0, 255}, "Unexpected MagicTouch category encoding.")
    require(confidence.shape == categories.shape and np.isfinite(confidence).all()
            and (confidence >= 0).all() and (confidence <= 1).all(), "Invalid MagicTouch confidence mask.")
    foreground = categories == 0
    # Pinned C++ category output interpolates logits on an aligned-corner grid;
    # confidence output activates first and uses cv::INTER_LINEAR. Their
    # thresholded edges can differ. Preserve the native category assignment.
    disagreements = int(np.count_nonzero(foreground != (confidence > .5)))
    count, labels, statistics, _ = cv2.connectedComponentsWithStats(foreground.astype(np.uint8), connectivity=8)
    height, width = categories.shape
    px, py = min(width - 1, int(prompt["x"] * width)), min(height - 1, int(prompt["y"] * height))
    selected = int(labels[py, px])
    base = {"status": "needs_review", "accepted": False, "prompt": prompt, "prompt_pixel": {"x": px, "y": py},
            "component_policy": "8-connected component containing prompt; no nearest/largest fallback; preserve its holes in mask",
            "foreground_components": int(count - 1), "raw_foreground_pixels": int(foreground.sum()),
            "category_confidence_disagreement_pixels": disagreements,
            "confidence_policy": "native category mask authoritative; confidence has a different upstream resizing path",
            "coordinate_space": "normalized immutable source pixels, top-left origin", "width_px": width, "height_px": height}
    if selected == 0:
        return None, {**base, "status": "no_proposal", "reason": "Prompt is outside predicted foreground.",
                      "x": None, "y": None, "width": None, "height": None, "contours": []}
    mask = (labels == selected).astype(np.uint8) * 255
    x, y, w, h, area = [int(v) for v in statistics[selected]]
    contours, hierarchy = cv2.findContours(mask, cv2.RETR_CCOMP, cv2.CHAIN_APPROX_SIMPLE)
    rings, total_points = [], 0
    for index, contour in enumerate(contours):
        approximation = cv2.approxPolyDP(contour, 1.0, True).reshape(-1, 2)
        total_points += len(approximation)
        if total_points <= 10000:
            rings.append({"id": index, "parent": int(hierarchy[0, index, 3]),
                          "is_hole": bool(hierarchy[0, index, 3] >= 0),
                          "points": [{"x": float(a) / width, "y": float(b) / height} for a, b in approximation]})
    proposal = {**base, "x": x / width, "y": y / height, "width": w / width, "height": h / height,
                "pixel_bbox": {"x": x, "y": y, "width": w, "height": h}, "foreground_pixels": area,
                "image_area_fraction": area / (width * height), "mean_foreground_confidence": float(confidence[labels == selected].mean()),
                "discarded_foreground_pixels": int(foreground.sum()) - area,
                "contours": rings if total_points <= 10000 else [], "contour_points_total": total_points,
                "contours_omitted_for_size": total_points > 10000,
                "contour_policy": "pixel-center contours, 1 px Douglas-Peucker tolerance, CCOMP hole hierarchy; exact mask authoritative",
                "mask_encoding": {"foreground": 255, "background": 0},
                "touches_image_border": x == 0 or y == 0 or x + w == width or y + h == height}
    return mask, proposal


def segment_aoi(request, source, directory):
    import cv2
    import numpy as np
    import mediapipe as mp
    from mediapipe.tasks.python import BaseOptions
    from mediapipe.tasks.python.components.containers import keypoint
    from mediapipe.tasks.python.vision import interactive_segmenter
    require(mp.__version__ == "0.10.21", "AOI segmentation requires the separate prepared MediaPipe 0.10.21 environment.")
    require(set(request["metadata"]) == {"prompt"}, "Segmentation metadata must contain only a normalized prompt.")
    prompt = request["metadata"]["prompt"]
    require(isinstance(prompt, dict) and set(prompt) == {"x", "y"}, "Prompt must contain exactly x and y.")
    prompt = {key: finite(prompt[key], "prompt." + key, 0, 1) for key in ("x", "y")}
    with source.open("rb") as stream:
        header = stream.read(33)
    require(len(header) == 33 and header[:8] == b"\x89PNG\r\n\x1a\n" and header[12:16] == b"IHDR", "AOI source must be a PNG image.")
    width, height, depth, color = struct.unpack(">IIBB", header[16:26])
    require(width >= 2 and height >= 2 and width * height <= MAX_PIXELS and depth == 8 and color in (0, 2, 3, 4, 6),
            "PNG must be 8-bit grayscale, palette, RGB or opaque alpha variants, within 4K pixel bounds.")
    decoded = cv2.imdecode(np.frombuffer(source.read_bytes(), dtype=np.uint8), cv2.IMREAD_UNCHANGED)
    require(decoded is not None and decoded.shape[:2] == (height, width), "PNG decode dimensions disagree with header.")
    require(decoded.dtype == np.uint8 and (decoded.ndim == 2 or (decoded.ndim == 3 and decoded.shape[2] in (3, 4))), "PNG colour channels are unsupported.")
    if decoded.ndim == 2:
        rgb = cv2.cvtColor(decoded, cv2.COLOR_GRAY2RGB)
    else:
        require(decoded.shape[2] == 3 or bool((decoded[:, :, 3] == 255).all()), "Transparent PNG needs an explicitly frozen opaque stimulus background before segmentation.")
        rgb = cv2.cvtColor(decoded[:, :, :3], cv2.COLOR_BGR2RGB)
    model = Path(os.environ.get("BROHN_SEGMENTATION_MODEL_PATH", str(TOOLING / "segmentation-venv/models/magic_touch_v1.tflite")))
    require(model.is_file() and digest(model) == SEGMENT_SHA, "Missing or mismatched pinned MagicTouch v1 model.")
    options = interactive_segmenter.InteractiveSegmenterOptions(
        base_options=BaseOptions(model_asset_path=str(model), delegate=BaseOptions.Delegate.CPU),
        output_category_mask=True, output_confidence_masks=True)
    roi = interactive_segmenter.RegionOfInterest(format=interactive_segmenter.RegionOfInterest.Format.KEYPOINT,
                                                keypoint=keypoint.NormalizedKeypoint(**prompt))
    with interactive_segmenter.InteractiveSegmenter.create_from_options(options) as detector:
        observed = detector.segment(mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb), roi)
        categories = observed.category_mask.numpy_view().copy()
        confidence = [x.numpy_view().copy() for x in observed.confidence_masks]
    require(len(confidence) == 1 and categories.shape == (height, width), "Unexpected MagicTouch mask dimensions/channels.")
    mask, proposal = component_proposal(categories, confidence[0], prompt)
    require(digest(source) == request["source_hash"], "Source changed during analysis.")
    result = base_result(request, source)
    result["status"] = proposal["status"]
    result["engine"] = {"name": "MediaPipe MagicTouch v1", "version": mp.__version__, "python": platform.python_version(),
                        "packages": package_versions(["mediapipe", "numpy", "opencv-contrib-python"]),
                        "model": {"sha256": SEGMENT_SHA, "bytes": model.stat().st_size, "provider_generation": "1683146867404767"}}
    result["parameters"] = {"delegate": "CPU", "source_width": width, "source_height": height, "prompt": prompt,
                            "source_png_bit_depth": depth, "source_png_color_type": color,
                            "input_color_normalization": {0: "grayscale replicated into RGB", 2: "native RGB", 3: "palette expanded into RGB",
                                                          4: "grayscale replicated into RGB; verified fully opaque alpha removed", 6: "verified fully opaque alpha removed"}[color],
                            "native_foreground_category": 0, "native_background_category": 255, "native_foreground_cutoff": ">0.5",
                            "component_policy": proposal["component_policy"], "source_transform": "identity",
                            "threads": "native engine managed; no Python API thread-count control"}
    if mask is not None:
        encoded_ok, encoded = cv2.imencode(".png", mask)
        require(encoded_ok, "Mask PNG encoding failed.")
        with tempfile.NamedTemporaryFile(dir=directory, suffix=".png.tmp", delete=False) as stream:
            stream.write(encoded.tobytes())
            temp = Path(stream.name)
        saved = artifact(temp, directory, "aoi-mask", ".png")
        result["artifacts"].append(saved)
        proposal.update(mask_path=saved["path"], mask_sha256=saved["sha256"])
    proposal["source_hash"] = request["source_hash"]
    result["proposal"] = proposal
    result["quality"] = {"usable_proposal": mask is not None, "researcher_review_required": True,
                         "semantic_aoi_label": None, "accuracy_qualification": "synthetic contract checks only"}
    result["limitations"] = ["A prompted object mask is a proposal, not an accepted scientific AOI or semantic region label.",
                             "The exact binary mask preserves holes; its bounding rectangle includes pixels outside the mask.",
                             "Model confidence is not measured boundary accuracy. Products, text and occlusion require researcher inspection.",
                             "No temporal AOI propagation, gaze integration or automatic acceptance is performed."]
    return result


def run(request):
    source, directory = validate_request(request)
    operation = analyse_video if request["operation"] == "analyse_video" else segment_aoi
    return operation(request, source, directory)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--request", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    request = {}
    source_output_conflict = False
    try:
        require(output != args.request.resolve(), "Output must not overwrite the request.")
        parsed = read_json(args.request)
        require(isinstance(parsed, dict), "Request must be a JSON object.")
        request = parsed
        if isinstance(request.get("source_path"), str):
            source_output_conflict = output == Path(request["source_path"]).resolve()
        require(not source_output_conflict, "Output must not overwrite the source.")
        result = run(request)
    except Exception as error:
        result = {"schema": "brohn-vision-result/1.0", "operation": request.get("operation"), "status": "error",
                  "error": {"type": type(error).__name__, "message": str(error)}, "features": [], "observations": [],
                  "quality": {"usable": False}, "parameters": {}, "limitations": [], "artifacts": []}
        if output == args.request.resolve() or source_output_conflict:
            print(json.dumps(result, allow_nan=False), file=sys.stderr)
            return 2
    atomic_json(output, result)
    print(json.dumps({"status": result["status"], "operation": result["operation"]}))
    return 2 if result["status"] == "error" else 0


if __name__ == "__main__":
    sys.exit(main())
