"""Bounded source-channel review; never rescores a saved acoustic report.

SoundFile decodes one explicitly selected channel without mixing. The periodic
Hann, undetrended one-sided density is |rfft(x*w)|^2/(fs*sum(w^2)), with doubled
interior bins. Full windows only: no padding, silence replacement or resampling.
"""
from __future__ import annotations

import argparse
import csv
from decimal import Decimal, InvalidOperation, ROUND_CEILING
import hashlib
import importlib.metadata
import json
from pathlib import Path
import re

import numpy as np
import soundfile as sf

MAX_SOURCE_BYTES = 512 * 1024**2
MAX_SOURCE_VALUES = 20_000_000
MAX_WINDOW_SAMPLES = 2_000_000
MAX_SPECTRAL_CELLS = 2_000_000
MAX_EXPORT_BYTES = 128 * 1024**2
PROFILE = "audio-source-review/1.0"


def require(ok, message):
    if not ok:
        raise ValueError(message)


def sha(path):
    h = hashlib.sha256()
    with Path(path).open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def fields(value, expected, label):
    require(isinstance(value, dict) and set(value) == set(expected), f"{label} fields are invalid.")


def integer(value, low, high, label):
    require(isinstance(value, int) and not isinstance(value, bool) and low <= value <= high,
            f"{label} is outside the supported integer range.")
    return value


def unique_pairs(items):
    result = {}
    for key, value in items:
        require(key not in result, f"Duplicate request field: {key}.")
        result[key] = value
    return result


def export_budget(stream, index):
    if index % 1024 == 0:
        require(stream.tell() <= MAX_EXPORT_BYTES, "Exact audio export exceeds 128 MiB; select a shorter interval.")


def decimal(value, label):
    require(isinstance(value, str) and len(value) <= 64 and re.fullmatch(r"[0-9]+(?:\.[0-9]+)?", value),
            f"{label} must be nonnegative decimal seconds.")
    try:
        result = Decimal(value)
    except InvalidOperation as error:
        raise ValueError(f"{label} is invalid.") from error
    require(result.is_finite(), f"{label} must be finite.")
    return result


def artifact(path, kind, rows):
    require(path.stat().st_size <= MAX_EXPORT_BYTES, "Exact audio export exceeds 128 MiB; select a shorter interval.")
    return {"kind": kind, "filename": path.name, "hash": sha(path), "bytes": path.stat().st_size, "rows": rows}


def partition(count, maximum):
    """Nonempty contiguous bins cover every input exactly once."""
    size = (count + maximum - 1) // maximum if count else 1
    return [(i, min(count, i + size)) for i in range(0, count, size)]


def review(request):
    fields(request, ["schema", "profile", "binding", "source_path", "source_hash", "header",
                     "selection", "output_directory"], "Audio review")
    require(request["schema"] == "brohn-audio-review-request/1.0" and request["profile"] == PROFILE,
            "Unsupported audio review profile.")
    require(isinstance(request["binding"], dict) and request["binding"], "A saved report binding is required.")
    path = Path(request["source_path"]).resolve()
    require(path.is_file() and 0 < path.stat().st_size <= MAX_SOURCE_BYTES, "Audio source must be a retained file up to 512 MiB.")
    require(isinstance(request["source_hash"], str) and re.fullmatch(r"[a-f0-9]{64}", request["source_hash"]), "Invalid audio source hash.")
    require(sha(path) == request["source_hash"], "The retained audio source does not match its saved hash.")
    fields(request["header"], ["frames", "sampling_rate", "channels"], "Saved audio header")
    for key in request["header"]:
        integer(request["header"][key], 1, MAX_SOURCE_VALUES, f"Saved header {key}")
    fields(request["selection"], ["channel_index", "start_s", "end_s", "frame_length_samples", "frame_hop_samples"], "Audio selection")
    selected = request["selection"]
    start = decimal(selected["start_s"], "Window start")
    end = decimal(selected["end_s"], "Window end")
    require(start < end, "Choose an increasing audio interval.")
    with sf.SoundFile(path) as source:
        require(source.format in {"WAV", "WAVEX", "FLAC", "OGG"}, "This review accepts retained WAV, FLAC or OGG audio.")
        rate = integer(source.samplerate, 1, 384000, "Source sampling rate")
        frames = integer(source.frames, 1, MAX_SOURCE_VALUES, "Source frames")
        channels = integer(source.channels, 1, 64, "Source channels")
        require(frames * channels <= MAX_SOURCE_VALUES, "Decoded source exceeds twenty million channel values.")
        require(request["header"] == {"frames": frames, "sampling_rate": rate, "channels": channels}, "Saved acoustic header differs from the source.")
        channel = integer(selected["channel_index"], 0, channels - 1, "Selected channel")
        first = int((start * rate).to_integral_value(rounding=ROUND_CEILING))
        stop = int((end * rate).to_integral_value(rounding=ROUND_CEILING))
        require(0 <= first < stop <= frames, "Choose a nonempty interval inside the recorded source duration.")
        require(stop - first <= MAX_WINDOW_SAMPLES, "Select at most two million source samples per audio review.")
        frame = integer(selected["frame_length_samples"], 32, 38400, "Spectral frame length")
        hop = integer(selected["frame_hop_samples"], 1, frame, "Spectral frame hop")
        require(frame <= rate // 2, "Spectral frames must not exceed half a second.")
        n_windows = max(0, 1 + (stop - first - frame) // hop)
        n_frequencies = frame // 2 + 1
        require(n_windows * n_frequencies <= MAX_SPECTRAL_CELLS,
                "Exact spectrogram exceeds two million cells; choose a shorter interval.")
        source.seek(first)
        samples = source.read(stop - first, dtype="float64", always_2d=True)[:, channel]
        require(len(samples) == stop - first and np.isfinite(samples).all(), "Selected audio contains unavailable or nonfinite samples; no replacements were made.")
        source_format, subtype = source.format, source.subtype
    directory = Path(request["output_directory"]).resolve()
    directory.mkdir(parents=True, exist_ok=True)
    require(directory != path.parent and directory != path, "Audio review output requires its own worker directory.")
    waveform_path = directory / "audio-samples.csv"
    spectrum_path = directory / "audio-spectrum.csv"
    # Short deterministic names stay inside the job's already-unique directory.
    # Exclusive creation prevents accidental replacement if a request is repeated.
    with waveform_path.open("x", encoding="utf-8", newline="") as target:
        writer = csv.writer(target, lineterminator="\n")
        writer.writerow(["source_sample_index", "time_s", "channel_index", "amplitude_fs"])
        for offset, value in enumerate(samples):
            index = first + offset
            writer.writerow([index, format(index / rate, ".17g"), channel, format(float(value), ".17g")])
            export_budget(target, offset)
    waveform = []
    for left, right in partition(len(samples), 1000):
        values = samples[left:right]
        low = left + int(np.argmin(values))
        high = left + int(np.argmax(values))
        waveform.append({"first_sample": first + left, "stop_sample": first + right, "samples": right - left,
                         "minimum_fs": float(samples[low]), "maximum_fs": float(samples[high]),
                         "minimum_sample": first + low, "maximum_sample": first + high})
    window = .5 - .5 * np.cos(2 * np.pi * np.arange(frame) / frame)
    scale = rate * float(np.dot(window, window))
    frequencies = np.fft.rfftfreq(frame, 1 / rate)
    density = np.empty((n_windows, n_frequencies), dtype=np.float64)
    with spectrum_path.open("x", encoding="utf-8", newline="") as target:
        writer = csv.writer(target, lineterminator="\n")
        writer.writerow(["frame_index", "first_source_sample", "stop_source_sample", "centre_time_s", "frequency_hz", "power_fs2_per_hz"])
        for index in range(n_windows):
            left = index * hop
            values = samples[left:left + frame]
            with np.errstate(over="raise", invalid="raise"):
                spectrum = np.abs(np.fft.rfft(values * window))**2 / scale
                spectrum[1:-1 if frame % 2 == 0 else None] *= 2
            require(np.isfinite(spectrum).all(), "Spectral arithmetic exceeded finite supported values.")
            density[index] = spectrum
            centre = (first + left + frame / 2) / rate
            for frequency, power in zip(frequencies, spectrum):
                writer.writerow([index, first + left, first + left + frame, format(centre, ".17g"),
                                 format(float(frequency), ".17g"), format(float(power), ".17g")])
            require(target.tell() <= MAX_EXPORT_BYTES, "Exact spectrum export exceeds 128 MiB; select a shorter interval.")
    time_bins = partition(n_windows, 120)
    frequency_bins = partition(n_frequencies, 80)
    heatmap = [{"first_frame": left, "stop_frame": right,
                "start_s": (first + left * hop) / rate,
                "end_s": (first + (right - 1) * hop + frame) / rate,
                "centre_s": (first + ((left + right - 1) * hop + frame) / 2) / rate,
                "plot_left_s": (first + left * hop + frame / 2 - hop / 2) / rate,
                "plot_right_s": (first + (right - 1) * hop + frame / 2 + hop / 2) / rate,
                "cells": [{"first_bin": low, "stop_bin": high, "lowest_hz": float(frequencies[low]),
                           "highest_hz": float(frequencies[high - 1]), "source_cells": (right-left)*(high-low),
                           "mean_power_fs2_per_hz": float(density[left:right, low:high].mean())}
                          for low, high in frequency_bins]} for left, right in time_bins]
    require(sha(path) == request["source_hash"], "Source changed during audio review; outputs are not accepted.")
    return {"schema": "brohn-audio-review-result/1.0", "profile": PROFILE, "binding": request["binding"],
            "source_hash": request["source_hash"], "selection": selected,
            "source": {**request["header"], "format": source_format, "subtype": subtype, "unit": "FS", "channel_mixing": "none"},
            "support": {"first_sample": first, "stop_sample": stop, "selected_samples": len(samples),
                        "full_scale_or_exceeding_samples": int((np.abs(samples) >= 1).sum()),
                        "exact_silence": bool(np.all(samples == 0)), "spectral_frames": n_windows,
                        "frequency_bins": n_frequencies, "spectral_cells": n_windows * n_frequencies,
                        "trailing_samples_without_full_spectral_frame": len(samples) if not n_windows else len(samples) - ((n_windows - 1) * hop + frame)},
            "parameters": {"window": "periodic Hann", "detrend": False, "padding": "none", "resampling": "none",
                           "spectrum": "one-sided power spectral density", "power_unit": "FS^2/Hz",
                           "time_reference": "seconds after original decoded source start", "range": "start included; end excluded",
                           "waveform_display": "contiguous-bin minimum and maximum with exact sample positions",
                           "spectrogram_display": "arithmetic mean of complete native spectral cells per display bin; exported native cells are unaggregated"},
            "waveform": waveform, "spectrogram": heatmap,
            "artifacts": [artifact(waveform_path, "audio-source-samples", len(samples)),
                          artifact(spectrum_path, "audio-source-spectrum", n_windows * n_frequencies)],
            "versions": {name: importlib.metadata.version(name) for name in ("numpy", "soundfile")},
            "limitations": ["Digital full scale is not calibrated sound pressure or perceived loudness.",
                            "This source view does not replace or recompute the saved acoustic result, pitch or periodicity.",
                            "Spectral energy is not speech activity, emotion, speaker identity or attention.",
                            "Only complete spectral frames inside this selection are shown. Short selections may contain no spectrum."]}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--request", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    target = Path(args.output)
    try:
        request_path = Path(args.request)
        require(request_path.stat().st_size <= 1024**2, "Audio review request exceeds one MiB.")
        result = review(json.loads(request_path.read_text(encoding="utf-8-sig"), object_pairs_hook=unique_pairs,
                                   parse_constant=lambda value: (_ for _ in ()).throw(ValueError("Nonfinite request number."))))
    except Exception as error:
        target.write_text(json.dumps({"status": "error", "error": {"message": str(error)}}), encoding="utf-8")
        return 1
    target.write_text(json.dumps(result, allow_nan=False, separators=(",", ":")), encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
