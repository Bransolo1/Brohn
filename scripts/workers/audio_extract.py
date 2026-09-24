"""Preserve a selected video audio track as decoded samples and a PTS ledger.

No channel mixing, resampling, time-stretching, silence insertion or inference.
A continuous sample file is accepted only when every frame PTS agrees with its
sample position within the explicitly retained container timestamp precision.
"""
from __future__ import annotations

import argparse
import csv
from fractions import Fraction
import hashlib
import importlib.metadata
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import time

import numpy as np
import soundfile as sf

PROFILE = "video-audio-source/1.0"
MAX_SOURCE_BYTES = 512 * 1024**2
MAX_VALUES = 20_000_000
MAX_FRAMES = 500_000
MAX_METADATA_BYTES = 96 * 1024**2
FORMATS = "mov,matroska,avi,ogg"


def require(ok, message):
    if not ok:
        raise ValueError(message)


def sha(path):
    value = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024**2), b""):
            value.update(chunk)
    return value.hexdigest()


def integer(value, low, high, label):
    require(isinstance(value, int) and not isinstance(value, bool) and low <= value <= high,
            f"{label} must be an integer in the supported range.")
    return value


def pairs(items):
    out = {}
    for key, value in items:
        require(key not in out, "Duplicate JSON field.")
        out[key] = value
    return out


def read_json(path):
    return json.loads(Path(path).read_text(encoding="utf-8-sig"), object_pairs_hook=pairs,
                      parse_constant=lambda _: (_ for _ in ()).throw(ValueError("Nonfinite JSON value.")))


def run_file(args, output, maximum, timeout=180, watched=None):
    """Bound file-backed stdout/stderr and decoded output while the child runs."""
    output = Path(output)
    error_path = output.with_suffix(output.suffix + ".stderr")
    with output.open("xb") as stdout, error_path.open("xb") as stderr:
        process = subprocess.Popen(args, stdin=subprocess.DEVNULL, stdout=stdout, stderr=stderr,
                                   creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0)
        deadline = time.monotonic() + timeout
        try:
            while process.poll() is None:
                require(time.monotonic() < deadline, "Media decoding exceeded its time limit.")
                require(output.stat().st_size <= maximum and error_path.stat().st_size <= 1024**2,
                        "Media decoding exceeded its metadata/log limit.")
                if watched and Path(watched[0]).exists():
                    require(Path(watched[0]).stat().st_size <= watched[1], "Decoded audio exceeds its value limit.")
                time.sleep(.025)
            require(process.returncode == 0, "The selected recording could not be decoded.")
            require(output.stat().st_size <= maximum and error_path.stat().st_size <= 1024**2,
                    "Media decoding exceeded its metadata/log limit.")
            if watched:
                require(Path(watched[0]).is_file() and Path(watched[0]).stat().st_size <= watched[1],
                        "Decoded audio exceeds its value limit.")
        finally:
            if process.poll() is None:
                process.kill()
            process.wait(timeout=10)


def executable(name, directory):
    path = shutil.which(name)
    require(path is not None, f"The prepared {name} executable is unavailable.")
    path = str(Path(path).resolve())
    version_file = directory / f"{name}-version.txt"
    run_file([path, "-version"], version_file, 65536, timeout=15)
    return path, {"sha256": sha(path), "version": version_file.read_text(encoding="utf-8").splitlines()[0]}


def stream_info(stream):
    rate = stream.get("sample_rate")
    require(isinstance(rate, str) and re.fullmatch(r"[0-9]{1,6}", rate), "Audio sample rate is missing.")
    rate = integer(int(rate), 1000, 384000, "Sample rate")
    count = integer(stream.get("channels"), 1, 64, "Channel count")
    index = integer(stream.get("index"), 0, 1023, "Stream index")
    clock = stream.get("time_base")
    require(isinstance(clock, str) and re.fullmatch(r"[0-9]{1,12}/[0-9]{1,12}", clock), "Audio time base is missing.")
    try:
        quantum = Fraction(clock)
    except (ValueError, ZeroDivisionError) as error:
        raise ValueError("Audio time base is invalid.") from error
    require(0 < quantum <= Fraction(1, 100), "Container timestamps are too coarse for this extraction profile.")
    codec = stream.get("codec_name")
    require(isinstance(codec, str) and re.fullmatch(r"[a-zA-Z0-9_]{1,64}", codec), "Audio codec is missing.")
    layout = stream.get("channel_layout")
    require(layout is None or isinstance(layout, str) and len(layout) <= 128, "Audio channel layout is invalid.")
    return {"stream_index": index, "codec": codec, "sampling_rate": rate, "channels": count,
            "channel_layout": layout, "time_base": clock}


def frame_ledger(frames, track):
    require(isinstance(frames, list) and 1 <= len(frames) <= MAX_FRAMES, "Audio frame count is outside the supported limit.")
    rate, channels = track["sampling_rate"], track["channels"]
    quantum = Fraction(track["time_base"])
    # Differences between two rounded frame timestamps have up to one tick of
    # quantization uncertainty. Retain one additional sample period explicitly.
    tolerance = quantum + Fraction(1, rate)
    rows, samples, origin, previous, worst = [], 0, None, None, Fraction(0)
    for i, frame in enumerate(frames):
        require(frame.get("media_type") == "audio" and frame.get("stream_index") == track["stream_index"],
                "Decoder frame belongs to another track.")
        pts = integer(frame.get("pts"), -(2**53-1), 2**53-1, "Frame PTS")
        count = integer(frame.get("nb_samples"), 1, 1_000_000, "Frame sample count")
        require(frame.get("channels") == channels and
                ("sample_rate" not in frame or str(frame["sample_rate"]) == str(rate)),
                "Audio rate or channel count changes within the recording.")
        stamp = pts * quantum
        if origin is None:
            origin = stamp
        require(previous is None or stamp > previous, "Audio presentation timestamps reset or overlap.")
        expected = origin + Fraction(samples, rate)
        error = stamp - expected
        require(abs(error) <= tolerance, "Audio has a timestamp gap or drift beyond container precision; preserve separate continuous segments before acoustic analysis.")
        rows.append({"decoder_frame_index": i, "pts_ticks": str(pts), "time_base": track["time_base"],
                     "pts_time_s": format(float(stamp), ".17g"), "start_sample": samples,
                     "end_sample_exclusive": samples+count, "samples": count,
                     "sample_clock_time_s": format(float(expected), ".17g"),
                     "pts_minus_sample_clock_s": format(float(error), ".17g")})
        samples += count
        require(samples * channels <= MAX_VALUES, "Decoded audio exceeds twenty million channel values.")
        previous, worst = stamp, max(worst, abs(error))
    return rows, {"frame_count": len(rows), "samples_per_channel": samples,
                  "source_start_pts_ticks": rows[0]["pts_ticks"], "source_start_time_s": rows[0]["pts_time_s"],
                  "sample_duration_s": format(samples/rate, ".17g"),
                  "maximum_pts_residual_s": format(float(worst), ".17g"),
                  "pts_consistency_tolerance_s": format(float(tolerance), ".17g"),
                  "clock_status": "consistent_within_container_precision"}


def analyse(request):
    require(isinstance(request, dict) and set(request) == {"schema", "operation", "binding", "source_path", "source_hash", "selection", "output_directory"}, "Extraction request fields are invalid.")
    require(request["schema"] == "brohn-audio-extract-request/1.0" and request["operation"] in {"inspect", "extract"}, "Unsupported audio extraction request.")
    require(isinstance(request["binding"], dict), "A saved source binding is required.")
    require(isinstance(request["source_path"], str) and isinstance(request["source_hash"], str) and re.fullmatch(r"[a-f0-9]{64}", request["source_hash"]), "The source path/hash is invalid.")
    source = Path(request["source_path"]).resolve(strict=True)
    require(source.is_file() and 0 < source.stat().st_size <= MAX_SOURCE_BYTES, "Choose a saved video within the 512 MiB source limit.")
    require(sha(source) == request["source_hash"], "The original video source changed.")
    selection = request["selection"]
    if request["operation"] == "inspect":
        require(selection is None, "Track inspection does not select an audio stream.")
    else:
        require(isinstance(selection, dict) and set(selection) == {"stream_index"}, "Select one exact container audio stream.")
        integer(selection["stream_index"], 0, 1023, "Selected stream")
    directory = Path(request["output_directory"]).resolve()
    require(not directory.exists(), "Use a new empty extraction directory.")
    directory.mkdir(parents=False)
    ffprobe, probe_version = executable("ffprobe", directory)
    prefix = [ffprobe, "-v", "error", "-protocol_whitelist", "file,pipe", "-format_whitelist", FORMATS]
    metadata = directory / "streams.json"
    run_file(prefix + ["-show_streams", "-show_entries", "stream=index,codec_type,codec_name,sample_rate,channels,channel_layout,time_base:stream_disposition=:stream_tags=", "-of", "json", str(source)], metadata, 1024**2)
    streams = read_json(metadata).get("streams", [])
    require(isinstance(streams, list) and 1 <= len(streams) <= 64 and any(s.get("codec_type") == "video" for s in streams), "A bounded video container is required.")
    tracks = [stream_info(s) for s in streams if s.get("codec_type") == "audio"]
    result = {"schema": "brohn-audio-extract-result/1.0", "profile": PROFILE, "operation": request["operation"],
              "binding": request["binding"], "source": {"sha256": request["source_hash"], "bytes": source.stat().st_size},
              "tracks": tracks, "selection": selection, "recording": None, "artifacts": [],
              "engine": {"ffprobe": probe_version, "numpy": importlib.metadata.version("numpy"),
                         "soundfile": importlib.metadata.version("soundfile"), "libsndfile": sf.__libsndfile_version__},
              "limitations": ["Decoded digital samples; no microphone calibration or emotion/speech interpretation.",
                              "Container timestamps do not establish physical synchrony with participant events."]}
    if request["operation"] == "extract":
        chosen = [t for t in tracks if t["stream_index"] == selection["stream_index"]]
        require(len(chosen) == 1, "The selected audio stream is absent.")
        track = chosen[0]
        frames_path = directory / "frames.json"
        run_file(prefix + ["-select_streams", str(track["stream_index"]), "-show_frames", "-show_entries",
                          "frame=media_type,stream_index,pts,nb_samples,sample_rate,channels", "-of", "json", str(source)], frames_path, MAX_METADATA_BYTES)
        rows, clock = frame_ledger(read_json(frames_path).get("frames"), track)
        ffmpeg, decoder_version = executable("ffmpeg", directory)
        result["engine"]["ffmpeg"] = decoder_version
        raw_path = directory / "decoded.f64"
        expected_bytes = clock["samples_per_channel"] * track["channels"] * 8
        run_file([ffmpeg, "-v", "error", "-xerror", "-nostdin", "-n", "-protocol_whitelist", "file,pipe", "-format_whitelist", FORMATS,
                  "-i", str(source), "-map", f"0:{track['stream_index']}", "-vn", "-sn", "-dn", "-map_metadata", "-1",
                  "-c:a", "pcm_f64le", "-f", "f64le", str(raw_path)], directory / "decode.stdout", 65536, watched=(raw_path, expected_bytes))
        require(raw_path.stat().st_size == expected_bytes, "Decoded sample count disagrees with the complete frame ledger.")
        wave_path = directory / "audio.wav"
        with raw_path.open("rb") as raw, sf.SoundFile(wave_path, mode="x", samplerate=track["sampling_rate"], channels=track["channels"], subtype="DOUBLE", format="WAV") as wave:
            while chunk := raw.read(65536 * track["channels"] * 8):
                samples = np.frombuffer(chunk, dtype="<f8").reshape(-1, track["channels"])
                require(np.isfinite(samples).all(), "Decoded audio contains nonfinite samples.")
                wave.write(samples)
        info = sf.info(wave_path)
        require(info.frames == clock["samples_per_channel"] and info.samplerate == track["sampling_rate"] and info.channels == track["channels"], "Saved audio changed its sample dimensions.")
        ledger_path = directory / "audio-frames.csv"
        with ledger_path.open("x", encoding="utf-8", newline="") as file:
            writer = csv.DictWriter(file, fieldnames=list(rows[0]));writer.writeheader();writer.writerows(rows)
        result["recording"] = {**track, **clock, "unit": "FS", "sample_zero_definition": "first decoded retained audio sample",
                               "sample_format": "float64", "channel_mixing": "none", "resampling": "none", "gap_filling": "none"}
        result["artifacts"] = [{"kind": kind, "path": path.name, "sha256": sha(path), "bytes": path.stat().st_size}
                               for kind, path in [("decoded-audio", wave_path), ("audio-frame-ledger", ledger_path)]]
        raw_path.unlink()
    require(sha(ffprobe) == probe_version["sha256"], "The probing executable changed during extraction.")
    if request["operation"] == "extract":
        require(sha(ffmpeg) == decoder_version["sha256"], "The decoder executable changed during extraction.")
    require(sha(source) == request["source_hash"], "The original video source changed during extraction.")
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser();parser.add_argument("--input", required=True);parser.add_argument("--output", required=True)
    args = parser.parse_args()
    require(Path(args.input).stat().st_size <= 1024**2, "Extraction request exceeds one MiB.")
    output = analyse(read_json(args.input))
    with Path(args.output).open("x", encoding="utf-8") as file:
        json.dump(output, file, allow_nan=False, ensure_ascii=True, separators=(",", ":"))
