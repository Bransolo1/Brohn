"""Extract one exact recorded frame; no inference, seeking, tracking or rotation.

The parent retains native guards on source, complete observations and index.
Default index verification and original source hashing remain enabled here.
"""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
from PIL import Image
import vision
import vision_explorer as explorer

MAX_PNG = 32 * 1024**2


def extract(request):
    explorer.require(request.get("schema") == "brohn-vision-frame-request/1.0", "Unsupported recorded-frame request.")
    source = Path(request["source_path"]); reference = request["source"]
    explorer.check_file(source, reference, vision.MAX_BYTES)
    explorer.require(explorer.digest(source) == reference["sha256"], "Original recorded video changed.")
    index_request = {key: request[key] for key in ("index_path", "index", "binding_sha256")}
    with explorer.opened(index_request) as (_, manifest):
        binding = explorer.loads(manifest["binding_json"])
        original = binding.get("original_source")
        explorer.require(isinstance(original, dict) and original.get("hash") == reference["sha256"] and original.get("size") == reference["bytes"], "Index and original video have different source identities.")
    frame_index = explorer.integer(request["frame_index"], 0, vision.MAX_FRAMES - 1)
    detail = explorer.detail(dict(index_request, artifact_path=request["artifact_path"], frame_index=frame_index))
    frame = detail["frame"]; parameters = detail["parameters"]; engine = detail["engine"]
    info = vision.inspect_video(source)
    explorer.require(frame_index < info["frame_count"], "Saved frame index leaves the original decoded stream.")
    explorer.require(str(info["timestamps"][frame_index]) == frame["source_pts_s"] and
                     str(info["timestamps"][0]) == parameters["source_pts_origin_s"] and
                     info["milliseconds"][frame_index] == frame["model_timestamp_ms"], "Original decoded index/PTS/model timestamp differs from the saved observation.")
    explorer.require(parameters.get("orientation") == "encoded pixels, no autorotation" and
                     parameters.get("width") == info["width"] and parameters.get("height") == info["height"] and
                     parameters.get("source_time_base") == info["time_base"], "Original decoded dimensions, orientation or time base differs from the saved analysis.")
    explorer.require(engine.get("ffmpeg") == info["ffmpeg_version"] and engine.get("ffprobe") == info["ffprobe_version"], "This frame needs the original saved compatible FFmpeg/FFprobe versions.")
    directory = Path(request["output_directory"])
    explorer.require(directory.is_dir() and not directory.is_symlink(), "Choose an existing owned frame artifact directory.")
    command = [info["ffmpeg"], "-v", "error", "-nostdin", "-protocol_whitelist", "file,pipe", "-format_whitelist", "mov,matroska,avi",
               "-noautorotate", "-i", str(source), "-map", "0:v:0", "-an", "-sn", "-dn", "-fps_mode", "passthrough", "-pix_fmt", "rgb24", "-f", "rawvideo", "pipe:1"]
    decoder = None; raw = None
    try:
        decoder = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                                   creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
        frame_bytes = info["width"] * info["height"] * 3
        for _ in range(frame_index + 1):
            raw = decoder.stdout.read(frame_bytes)
            explorer.require(len(raw) == frame_bytes, "Decoder ended before the exact selected original frame.")
        # Stop after this original sequentially decoded frame. Full stream PTS
        # and dimensions were already probed; no FPS/time seeking is performed.
    finally:
        if decoder is not None:
            if decoder.poll() is None: decoder.kill()
            decoder.wait(timeout=10)
            if decoder.stdout is not None: decoder.stdout.close()
    explorer.require(explorer.digest(source) == reference["sha256"], "Original video changed during frame extraction.")
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(dir=directory, prefix="recorded-frame-", suffix=".png.tmp", delete=False) as handle:
            temporary = Path(handle.name)
        with Image.frombytes("RGB", (info["width"], info["height"]), raw) as pixels:
            pixels.save(temporary, format="PNG", optimize=False)
        explorer.require(0 < temporary.stat().st_size <= MAX_PNG, "Exact recorded PNG exceeds 32 MiB.")
        image_hash = explorer.digest(temporary); target = directory / ("recorded-frame-" + image_hash + ".png")
        explorer.require(not target.exists(), "Choose a new owned frame output directory.")
        temporary.replace(target); temporary = None
        return {"schema": "brohn-vision-recorded-frame/1.0", "status": "complete", "binding_sha256": request["binding_sha256"],
                "index_sha256": request["index"]["sha256"], "source": reference, "artifact": manifest["artifact"], "frame": frame,
                "image": {"path": str(target.resolve()), "sha256": image_hash, "bytes": target.stat().st_size, "media_type": "image/png", "width": info["width"], "height": info["height"]},
                "extraction": {"policy": "sequential_original_rgb24_no_seek_no_autorotation", "source_frames": info["frame_count"],
                               "decoded_frames_to_selection": frame_index + 1, "rgb24_sha256": hashlib.sha256(raw).hexdigest(),
                               "source_time_base": info["time_base"], "source_pts_origin_s": str(info["timestamps"][0]),
                               "orientation": parameters["orientation"], "ffmpeg": info["ffmpeg_version"], "ffprobe": info["ffprobe_version"],
                               "transform": {"scale_x": 1, "scale_y": 1, "offset_x": 0, "offset_y": 0, "mirror": False, "rotation_degrees": 0}},
                "limitations": ["Recorded pixels plus saved model geometry; no new inference or physical accuracy qualification.",
                                "Native model z is not calibrated depth; no identity, emotion, attention or camera-derived gaze is inferred."]}
    finally:
        if temporary is not None and temporary.exists(): temporary.unlink()


def main():
    parser = argparse.ArgumentParser(); parser.add_argument("--request", required=True); parser.add_argument("--output", required=True); args = parser.parse_args()
    try:
        request = vision.read_json(Path(args.request)); result = extract(request); code = 0
    except Exception as error:
        result = {"schema": "brohn-vision-recorded-frame/1.0", "status": "error", "error": {"type": type(error).__name__, "message": str(error)}}; code = 1
    vision.atomic_json(Path(args.output), result); return code


if __name__ == "__main__": sys.exit(main())
