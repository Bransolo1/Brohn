"""Bounded exact-index video pixels shared by saved-result review workers.

The caller verifies the original stream/PTS ledger, dimensions, decoder version
and source authority, and keeps its source read guards for this operation.
This helper performs no inference, temporal seeking, rotation or rescaling.
It uses only the standard library; viewing a saved frame needs no model weights.
"""
from __future__ import annotations

import hashlib
import math
import os
from pathlib import Path
import re
import struct
import subprocess
import tempfile
import threading
import time
import zlib

MAX_SOURCE_BYTES = 512 * 1024**2
MAX_FRAMES = 36000
MAX_PIXELS = 3840 * 2160
MAX_PNG_BYTES = 32 * 1024**2
MAX_ERROR_BYTES = 64 * 1024
POLICY = "sequential_original_rgb24_no_seek_no_autorotation"


class MediaPixelError(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise MediaPixelError(message)


def _integer(value, low, high, label):
    require(type(value) is int and low <= value <= high, f"{label} is outside the supported range.")


def _sha(value, label):
    require(isinstance(value, str) and re.fullmatch(r"[0-9a-f]{64}", value) is not None,
            f"{label} must be a lowercase SHA-256 identity.")


def _time(deadline):
    require(time.monotonic() < deadline, "Exact recorded-frame preparation exceeded its time limit.")


def _digest(path, deadline):
    value = hashlib.sha256()
    with path.open("rb") as handle:
        while chunk := handle.read(1024 * 1024):
            _time(deadline)
            value.update(chunk)
    return value.hexdigest()


def _source(path, size, sha, deadline):
    require(path.is_file() and not path.is_symlink() and path.stat().st_size == size,
            "Original video size or file identity changed.")
    require(_digest(path, deadline) == sha, "Original video bytes differ from the saved source.")


def _png(handle, rgb, width, height, deadline):
    """Encode exactly the supplied RGB bytes with filter zero and lossless zlib."""
    written = 0

    def write(value):
        nonlocal written
        require(written + len(value) <= MAX_PNG_BYTES, "Exact recorded PNG exceeds 32 MiB.")
        handle.write(value)
        written += len(value)

    def chunk(kind, value):
        write(struct.pack(">I", len(value)))
        write(kind)
        write(value)
        write(struct.pack(">I", zlib.crc32(value, zlib.crc32(kind)) & 0xffffffff))

    write(b"\x89PNG\r\n\x1a\n")
    chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
    compressor = zlib.compressobj(level=6)
    stride = width * 3
    for row in range(height):
        _time(deadline)
        value = compressor.compress(b"\0" + rgb[row * stride:(row + 1) * stride])
        if value:
            chunk(b"IDAT", value)
    tail = compressor.flush()
    if tail:
        chunk(b"IDAT", tail)
    chunk(b"IEND", b"")
    handle.flush()
    os.fsync(handle.fileno())


def extract_frame(source_path, source_sha256, source_bytes, stream_index, width,
                  height, frame_index, ffmpeg_path, output_directory,
                  expected_rgb_sha256=None, *, timeout_s=120):
    """Return one exact PNG and decoding identities, never an inferred frame.

    ``stream_index`` is the absolute FFprobe stream index (``-map 0:N``).
    ``frame_index`` is zero-based within that stream's original decode order.
    The caller must have verified that stream's complete PTS/dimension ledger.
    An expected RGB digest is required by the facial review caller and optional
    for sources which did not preserve decoded pixels during their first job.
    """
    _sha(source_sha256, "Original source")
    if expected_rgb_sha256 is not None:
        _sha(expected_rgb_sha256, "Saved decoded RGB")
    _integer(source_bytes, 1, MAX_SOURCE_BYTES, "Original video byte count")
    _integer(stream_index, 0, 63, "Video stream index")
    _integer(width, 1, MAX_PIXELS, "Recorded frame width")
    _integer(height, 1, MAX_PIXELS, "Recorded frame height")
    require(width * height <= MAX_PIXELS, "Recorded frame exceeds the 4K pixel bound.")
    _integer(frame_index, 0, MAX_FRAMES - 1, "Original frame index")
    require(type(timeout_s) in (int, float) and math.isfinite(timeout_s) and 0 < timeout_s <= 120,
            "Frame preparation needs a positive time limit of at most 120 seconds.")
    deadline = time.monotonic() + timeout_s
    source, decoder_path, directory = map(Path, (source_path, ffmpeg_path, output_directory))
    require(all(p.is_absolute() for p in (source, decoder_path, directory)),
            "Use explicit absolute source, decoder and owned output paths.")
    require(decoder_path.is_file() and not decoder_path.is_symlink(), "The selected local decoder is unavailable.")
    require(directory.is_dir() and not directory.is_symlink(), "Choose an existing owned frame output directory.")
    _source(source, source_bytes, source_sha256, deadline)
    decoder_sha = _digest(decoder_path, deadline)
    command = [str(decoder_path), "-v", "error", "-nostdin", "-protocol_whitelist", "file,pipe",
               "-format_whitelist", "mov,matroska,avi", "-noautorotate", "-i", str(source),
               "-map", f"0:{stream_index}", "-an", "-sn", "-dn", "-fps_mode", "passthrough",
               "-pix_fmt", "rgb24", "-f", "rawvideo", "pipe:1"]
    decoder = None
    timer = None
    error_reader = None
    timed_out, error_overflow = threading.Event(), threading.Event()
    errors = bytearray()
    raw = None

    def stop():
        if decoder is not None:
            try:
                decoder.kill()
            except ProcessLookupError:
                pass

    def expire():
        timed_out.set()
        stop()

    def read_errors():
        while chunk := decoder.stderr.read(4096):
            remaining = MAX_ERROR_BYTES - len(errors)
            errors.extend(chunk[:remaining])
            if len(chunk) > remaining:
                error_overflow.set()
                stop()
                return

    try:
        _time(deadline)
        decoder = subprocess.Popen(command, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE, creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
        error_reader = threading.Thread(target=read_errors, daemon=True)
        error_reader.start()
        timer = threading.Timer(max(0.001, deadline - time.monotonic()), expire)
        timer.daemon = True
        timer.start()
        frame_bytes = width * height * 3
        for _ in range(frame_index + 1):
            raw = decoder.stdout.read(frame_bytes)
            require(not timed_out.is_set(), "Exact recorded-frame preparation exceeded its time limit.")
            require(not error_overflow.is_set(), "Decoder error output exceeded its bounded limit.")
            _time(deadline)
            require(len(raw) == frame_bytes, "Decoder ended before the complete selected original frame.")
        require(decoder.poll() in (None, 0), "The selected original video could not be decoded completely to this frame.")
    finally:
        if timer is not None:
            timer.cancel()
        if decoder is not None:
            stop()
            decoder.wait(timeout=10)
            if error_reader is not None:
                error_reader.join(timeout=10)
            decoder.stdout.close()
            decoder.stderr.close()
    require(not timed_out.is_set() and not error_overflow.is_set(), "Recorded-frame decoding exceeded its resource limits.")
    rgb_sha = hashlib.sha256(raw).hexdigest()
    require(expected_rgb_sha256 is None or rgb_sha == expected_rgb_sha256,
            "Decoded pixels differ from the exact saved frame observation.")
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(dir=directory, prefix="recorded-frame-", suffix=".png.tmp", delete=False) as handle:
            temporary = Path(handle.name)
            _png(handle, raw, width, height, deadline)
        image_hash = _digest(temporary, deadline)
        _source(source, source_bytes, source_sha256, deadline)
        require(_digest(decoder_path, deadline) == decoder_sha, "The selected decoder changed during frame preparation.")
        # One frame belongs to each owned job directory. Keep the basename short
        # for ordinary Windows paths; exact content identity is in the descriptor.
        target = directory / "recorded-frame.png"
        # Hard-link publication is atomic and refuses an existing path. The
        # owned temporary file stays on the same filesystem as its destination.
        os.link(temporary, target)
        temporary.unlink()
        temporary = None
        return {"image": {"path": str(target), "sha256": image_hash, "bytes": target.stat().st_size,
                          "media_type": "image/png", "width": width, "height": height},
                "rgb24_sha256": rgb_sha, "policy": POLICY, "stream_index": stream_index,
                "frame_index": frame_index, "decoded_frames_to_selection": frame_index + 1,
                "decoder_sha256": decoder_sha,
                "orientation": "encoded pixels, no autorotation"}
    finally:
        if temporary is not None and temporary.exists():
            temporary.unlink()
