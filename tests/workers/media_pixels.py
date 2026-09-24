"""Original lossless video/pixel oracle and bounded child-process failure cases."""
from __future__ import annotations
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import sys
from unittest.mock import patch

from PIL import Image  # Independent PNG decoder, not a production dependency.

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("brohn_media_pixels", ROOT / "scripts/workers/media_pixels.py")
pixels = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pixels)
sha = lambda value: hashlib.sha256(value).hexdigest()
parser = argparse.ArgumentParser()
parser.add_argument("--output", required=True)
parser.add_argument("--ffmpeg", required=True)
args = parser.parse_args()
folder = Path(args.output).resolve()
assert not folder.exists(), "Choose a new external evidence directory."
assert not folder.is_relative_to(ROOT), "Keep generated media outside the repository."
folder.mkdir(parents=True)
ffmpeg = Path(args.ffmpeg).resolve()
checks = []
sources = {str(p.relative_to(ROOT)): sha(p.read_bytes()) for p in
           (ROOT / "scripts/workers/media_pixels.py", Path(__file__))}


def check(condition, label):
    assert condition, label
    checks.append(label)
    print("PASS", label, flush=True)


def refused(call, expected, label):
    try:
        call()
    except (ValueError, FileExistsError) as error:
        assert expected.lower() in str(error).lower(), str(error)
        check(True, label)
    else:
        raise AssertionError(label)


try:
    width, height = 32, 24
    frames = [bytes((x * 13 + y * 17 + frame * 43 + channel * 61) % 256
                    for y in range(height) for x in range(width) for channel in range(3))
              for frame in range(3)]
    other = [bytes((255 - value) for value in frame) for frame in frames]
    first, second = folder / "original.rgb", folder / "other.rgb"
    first.write_bytes(b"".join(frames)); second.write_bytes(b"".join(other))
    source = folder / "original-two-streams.mkv"
    subprocess.run([str(ffmpeg), "-v", "error", "-nostdin", "-f", "rawvideo", "-pix_fmt", "rgb24",
                    "-s", f"{width}x{height}", "-r", "5", "-i", str(first),
                    "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{width}x{height}",
                    "-r", "5", "-i", str(second), "-map", "0:v:0", "-map", "1:v:0",
                    "-c:v", "ffv1", "-pix_fmt", "bgr0", "-n", str(source)], check=True,
                   capture_output=True, timeout=30, creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
    source_bytes = source.read_bytes()

    def request(name, **changes):
        output = folder / name
        output.mkdir()
        return dict(source_path=str(source), source_sha256=sha(source_bytes), source_bytes=len(source_bytes),
                    stream_index=0, width=width, height=height, frame_index=2, ffmpeg_path=str(ffmpeg),
                    output_directory=str(output), expected_rgb_sha256=sha(frames[2]), **changes)

    original = request("original-last")
    result = pixels.extract_frame(**original)
    check(result["rgb24_sha256"] == sha(frames[2]) and result["decoded_frames_to_selection"] == 3,
          "Third original frame is selected by exact decode index and matches independently authored RGB")
    with Image.open(result["image"]["path"]) as image:
        check(image.mode == "RGB" and image.size == (width, height) and image.tobytes() == frames[2],
              "Independent PNG decoder recovers every original pixel without resizing or rotation")
    check(result["image"]["sha256"] == sha(Path(result["image"]["path"]).read_bytes()) and
          result["image"]["bytes"] == Path(result["image"]["path"]).stat().st_size,
          "PNG descriptor retains exact file bytes and hash")
    q = request("selected-other"); q.update(stream_index=1, frame_index=0, expected_rgb_sha256=sha(other[0]))
    selected = pixels.extract_frame(**q)
    with Image.open(selected["image"]["path"]) as image:
        check(image.tobytes() == other[0] and selected["stream_index"] == 1,
              "Explicit absolute video stream selection cannot silently return stream zero")
    target = Path(result["image"]["path"])
    old_image = target.read_bytes()
    refused(lambda: pixels.extract_frame(**original), "exist", "Existing PNG is never overwritten")
    check(target.read_bytes() == old_image and len(list(target.parent.iterdir())) == 1,
          "Refused duplicate leaves original image unchanged and removes only its owned temporary file")
    # A real nested job path must fit ordinary Windows file APIs without a
    # content hash in its basename. The descriptor, not the name, owns identity.
    long_name = "nested-" + "x" * (210 - len(str(folder)) - 1 - len("nested-"))
    assert len(str(folder / long_name)) == 210
    q = request(long_name)
    long_result = pixels.extract_frame(**q)
    long_target = Path(long_result["image"]["path"])
    check(long_target.is_file() and len(str(long_target)) < 260 and
          len(str(long_target.parent / ("recorded-frame-" + "0" * 64 + ".png"))) >= 260,
          "Actual nested job directory publishes below MAX_PATH without a full-hash basename")
    with Image.open(long_target) as image:
        check(image.tobytes() == frames[2] and long_result["image"]["sha256"] == sha(long_target.read_bytes()),
              "Long-path publication retains every original pixel and exact descriptor identity")
    for name, changes, message in [
        ("wrong-source", {"source_sha256": "0" * 64}, "source"),
        ("wrong-size", {"source_bytes": len(source_bytes) + 1}, "size"),
        ("wrong-rgb", {"expected_rgb_sha256": "0" * 64}, "pixels"),
        ("past-end", {"frame_index": 3, "expected_rgb_sha256": None}, "ended"),
        ("unknown-stream", {"stream_index": 2}, "ended"),
        ("bool-index", {"frame_index": True}, "index"),
        ("oversize-pixels", {"width": 3840, "height": 2161}, "4K"),
        ("unbounded-time", {"timeout_s": 121}, "120"),
        ("relative-source", {"source_path": "original-two-streams.mkv"}, "absolute"),
    ]:
        q = request(name); q.update(changes)
        refused(lambda: pixels.extract_frame(**q), message, f"{name}: refused without publishing a fabricated frame")
        assert not list(Path(q["output_directory"]).iterdir())

    original_popen = subprocess.Popen
    for name, code, timeout, message in [
        ("blocked-decoder", "import time;time.sleep(30)", 1.5, "time limit"),
        ("error-flood", "import sys,time;sys.stderr.buffer.write(b'x'*131072);sys.stderr.flush();time.sleep(30)", 5, "error output"),
    ]:
        children = []

        def child_factory(command, **options):
            child = original_popen([sys.executable, "-c", code], **options)
            children.append(child)
            return child

        q = request(name); q.update(timeout_s=timeout)
        with patch.object(pixels.subprocess, "Popen", child_factory):
            refused(lambda: pixels.extract_frame(**q), message,
                    f"{name}: actual injected child is bounded and no PNG is published")
        check(bool(children) and all(child.poll() is not None for child in children),
              f"{name}: every injected child has terminated")
        assert not list(Path(q["output_directory"]).iterdir())
    check(source.read_bytes() == source_bytes, "All decoding/refusal cases preserve original encoded source bytes")
    changed_source = folder / "late-change-source.mkv"
    changed_source.write_bytes(source_bytes)
    q = request("late-source-change"); q["source_path"] = str(changed_source)
    original_png = pixels._png

    def change_after_png(*arguments):
        original_png(*arguments)
        changed_source.write_bytes(source_bytes[:-1] + bytes([source_bytes[-1] ^ 1]))

    with patch.object(pixels, "_png", change_after_png):
        refused(lambda: pixels.extract_frame(**q), "source", "A source change during PNG preparation prevents publication")
    check(not list(Path(q["output_directory"]).iterdir()) and source.read_bytes() == source_bytes,
          "Late source refusal removes its owned temporary image and preserves the original reference")
    check(all(sha((ROOT / name).read_bytes()) == value for name, value in sources.items()),
          "Helper and test source identities remain unchanged throughout execution")
    receipt = {"status": "passed", "checks": checks, "source_hashes": sources,
               "decoder_sha256": sha(ffmpeg.read_bytes()), "original_video_sha256": sha(source_bytes),
               "limits": ["Original lossless generated two-stream fixture; no model, camera or physical alignment qualification.",
                          "Timeout and log-overflow cases inject real Python children in place of the decoder."]}
except BaseException as error:
    receipt = {"status": "failed", "checks": checks, "source_hashes": sources,
               "error": f"{type(error).__name__}: {error}"}
    raise
finally:
    (folder / "results.json").write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"status": receipt["status"], "checks": len(checks), "folder": str(folder)}))
