"""Bounded Brohn physiology worker. Run in an isolated, pinned analysis environment.

This worker returns recording-level numerical evidence, never independent-subject
inference or universal psychological/clinical construct labels.
"""
from __future__ import annotations

import argparse
import csv
from decimal import Decimal, InvalidOperation
import hashlib
import importlib.metadata
import json
import math
import os
from pathlib import Path
import platform
import sys
import tempfile
import warnings

os.environ.setdefault("MPLBACKEND", "Agg")
os.environ.setdefault("OMP_NUM_THREADS", "1")
os.environ.setdefault("OPENBLAS_NUM_THREADS", "1")

import numpy as np
from scipy import signal, ndimage

MAX_FILE_BYTES = 512 * 1024 * 1024
MAX_ROWS = 2_000_000
MAX_VALUES = 20_000_000
MAX_CHANNELS = 64
MAX_RECORDINGS = 2000
MAX_DISPLAY = 2000
MISSING = {"", "NA", "N/A", "null", "NaN", "nan"}
TIME_FACTORS = {"s": Decimal(1), "ms": Decimal(".001"), "us": Decimal(".000001"), "ns": Decimal(".000000001")}


class InputError(ValueError):
    pass


def require(test, message):
    if not test:
        raise InputError(message)


def finite(value, label, low=-math.inf, high=math.inf):
    require(isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value) and low <= value <= high,
            f"{label} must be a finite number from {low} to {high}.")
    return float(value)


def number(value):
    if value is None:
        return None
    value = float(value)
    return value if math.isfinite(value) else None


def digest_file(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def versions(names):
    return {name: importlib.metadata.version(name) for name in names}


def require_neurokit():
    import neurokit2 as nk
    require(nk.__version__ == "0.2.13", "This recipe requires the prepared NeuroKit2 0.2.13 environment.")
    return nk


def require_mne():
    import mne
    require(mne.__version__ == "1.12.1", "This recipe requires the prepared MNE 1.12.1 environment.")
    mne.set_log_level("ERROR")
    return mne


def unit_conversion(modality, unit):
    units = {
        "eda": {"uS": (1.0, "uS"), "\u00b5S": (1.0, "uS"), "\u03bcS": (1.0, "uS"), "S": (1e6, "uS")},
        "eeg": {"V": (1.0, "V"), "mV": (1e-3, "V"), "uV": (1e-6, "V"), "\u00b5V": (1e-6, "V"), "\u03bcV": (1e-6, "V")},
        "ecg": {"V": (1e6, "uV"), "mV": (1e3, "uV"), "uV": (1.0, "uV"), "\u00b5V": (1.0, "uV"), "\u03bcV": (1.0, "uV")},
        "emg": {"V": (1e6, "uV"), "mV": (1e3, "uV"), "uV": (1.0, "uV"), "\u00b5V": (1.0, "uV"), "\u03bcV": (1.0, "uV")},
        "ppg": {"a.u.": (1.0, "a.u."), "V": (1.0, "V"), "mV": (1e-3, "V")},
        "respiration": {"a.u.": (1.0, "a.u."), "V": (1.0, "V"), "mV": (1e-3, "V"), "L": (1.0, "L"), "L/s": (1.0, "L/s")},
    }
    require(unit in units.get(modality, {}), f"Unsupported or missing {modality} amplitude unit {unit!r}. Declare calibrated voltage/conductance or supported source units explicitly.")
    return units[modality][unit]


def parameters(modality, supplied, fs):
    defaults = {
        "eda": {"recipe": "eda-neurokit-highpass/1.0", "phasic_cutoff_hz": .05, "amplitude_min_relative_prominence": .1, "edge_exclusion_s": 10.0},
        "eeg": {"recipe": "eeg-welch-channel/1.0", "window_s": 2.0, "overlap_fraction": .5,
                "bands_hz": {"delta": [1, 4], "theta": [4, 8], "alpha": [8, 13], "beta": [13, 30], "gamma": [30, 45]}, "relative_denominator_hz": [1, 45]},
        "ecg": {"recipe": "ecg-neurokit-detected-rr/1.0", "powerline_hz": 50.0, "edge_exclusion_s": 2.0,
                "interval_min_ms": 300.0, "interval_max_ms": 2000.0, "frequency_min_duration_s": 300.0},
        "ppg": {"recipe": "ppg-elgendi-detected-prv/1.0", "edge_exclusion_s": 2.0,
                "interval_min_ms": 300.0, "interval_max_ms": 2000.0, "frequency_min_duration_s": 300.0},
        "respiration": {"recipe": "respiration-khodadad-cycles/1.0", "edge_exclusion_s": 5.0},
        "emg": {"recipe": "emg-butterworth-rms/1.0", "highpass_hz": 20.0, "lowpass_hz": min(450.0, fs * .4),
                "rms_window_s": .05, "edge_exclusion_s": .25, "burst_threshold_uv": None, "burst_min_duration_s": .1},
    }
    require(isinstance(supplied, dict), "parameters must be an object.")
    result = defaults[modality].copy()
    require(not (set(supplied) - set(result)), f"Unsupported {modality} parameters: {', '.join(sorted(set(supplied) - set(result)))}")
    require("recipe" not in supplied or supplied["recipe"] == result["recipe"], "The requested recipe is not implemented by this worker.")
    result.update(supplied)
    if "edge_exclusion_s" in result:
        finite(result["edge_exclusion_s"], "edge_exclusion_s", defaults[modality]["edge_exclusion_s"], 120)
    if modality == "eda":
        require(fs >= 8, "The EDA cleaner requires at least 8 Hz in this recipe.")
        require(result["phasic_cutoff_hz"] == .05, "This recipe fixes the high-pass decomposition at 0.05 Hz; another cutoff needs its own reviewed recipe.")
        finite(result["amplitude_min_relative_prominence"], "amplitude_min_relative_prominence", .001, 1)
        result.update(cleaner="neurokit", clean_lowpass_hz=3.0, clean_order=4, decomposition="highpass", recovery_fraction=.5,
                      threshold_definition="candidate_prominence_relative_to_maximum_prominence", no_missing_value_imputation=True)
    elif modality == "eeg":
        finite(result["window_s"], "window_s", 1, 30)
        finite(result["overlap_fraction"], "overlap_fraction", 0, .9)
        bands = result["bands_hz"]
        require(isinstance(bands, dict) and 1 <= len(bands) <= 20, "Provide 1 to 20 named EEG bands.")
        for name, bounds in list(bands.items()) + [("relative denominator", result["relative_denominator_hz"])]:
            require(isinstance(name, str) and 0 < len(name) <= 64 and isinstance(bounds, list) and len(bounds) == 2, "Each EEG band needs a name and two frequency boundaries.")
            finite(bounds[0], f"{name} lower frequency", 0, fs / 2)
            finite(bounds[1], f"{name} upper frequency", 0, fs / 2)
            require(bounds[0] < bounds[1], "EEG frequency boundaries must increase and stay within Nyquist.")
        result.update(window="hann", average="mean", remove_dc=True, integration="sum_density_times_bin_width_half_open_bands", preprocessing="none; acquisition reference retained", psd_unit="V^2/Hz")
    elif modality in {"ecg", "ppg"}:
        require(fs >= (100 if modality == "ecg" else 25), f"The {modality} recipe requires at least {'100' if modality == 'ecg' else '25'} Hz.")
        finite(result["interval_min_ms"], "interval_min_ms", 100, 3000)
        finite(result["interval_max_ms"], "interval_max_ms", result["interval_min_ms"] + 1, 10000)
        finite(result["frequency_min_duration_s"], "frequency_min_duration_s", 300, 3600)
        result.update(detector="neurokit" if modality == "ecg" else "elgendi", correct_artifacts=False,
                      normal_to_normal_qualification=False, pnn50_denominator="retained_intervals", frequency_interpolation_hz=4,
                      frequency_psd_window_s=128, frequency_psd_window="hann", frequency_psd_overlap_fraction=.5)
        if modality == "ecg":
            require(result["powerline_hz"] in [50, 60], "Declare a 50 or 60 Hz acquisition environment.")
            require(result["powerline_hz"] <= fs/2, "The selected powerline frequency exceeds Nyquist; provide an acquisition-compatible cleaning profile rather than silently applying it.")
    elif modality == "respiration":
        require(fs >= 10, "The respiration recipe requires at least 10 Hz.")
        result.update(cleaner="khodadad2018", detector="khodadad2018", polarity="positive_excursion_toward_inspiration; confirm sensor mapping")
    elif modality == "emg":
        require(fs >= 250, "The surface EMG recipe requires at least 250 Hz.")
        finite(result["highpass_hz"], "highpass_hz", 5, fs / 2)
        finite(result["lowpass_hz"], "lowpass_hz", result["highpass_hz"] + 1, fs / 2 - .1)
        finite(result["rms_window_s"], "rms_window_s", .005, 2)
        finite(result["burst_min_duration_s"], "burst_min_duration_s", .001, 60)
        if result["burst_threshold_uv"] is not None:
            finite(result["burst_threshold_uv"], "burst_threshold_uv", .000001, 1e9)
        result.update(filter="butterworth_sos_zero_phase", filter_order=4, envelope="centered_window_root_mean_square", mvc_normalization=False)
    return result


def csv_recordings(path, metadata, modality):
    time_column = metadata.get("time_column")
    columns = metadata.get("value_columns")
    require(isinstance(time_column, str) and time_column, "CSV input requires metadata.time_column.")
    require(isinstance(columns, list) and 1 <= len(columns) <= MAX_CHANNELS and all(isinstance(c, str) and c for c in columns) and len(columns) == len(set(columns)), "value_columns must contain 1 to 64 unique declared channels.")
    fs = finite(metadata.get("sampling_rate"), "sampling_rate", .1, 100000)
    time_unit = metadata.get("time_unit")
    require(time_unit in TIME_FACTORS or time_unit == "sample", "time_unit must be s, ms, us, ns or sample.")
    time_factor = Decimal(1) / Decimal(str(fs)) if time_unit == "sample" else TIME_FACTORS[time_unit]
    factor, canonical_unit = unit_conversion(modality, metadata.get("unit"))
    group_columns = {key.removesuffix("_column") + "_id": metadata[key] for key in
                     ["participant_column", "session_column", "condition_column", "exposure_column", "segment_column"] if metadata.get(key)}
    require(all(isinstance(value, str) for value in group_columns.values()), "Grouping columns must be named explicitly.")
    require(time_column not in columns and time_column not in group_columns.values() and
            len(set(group_columns.values())) == len(group_columns) and not (set(columns) & set(group_columns.values())),
            "Time, grouping and signal columns must be distinct.")
    recordings, current, previous_key, rows = [], None, None, 0
    with path.open("r", encoding="utf-8-sig", newline="") as stream:
        reader = csv.DictReader(stream, delimiter="\t" if path.suffix.lower() == ".tsv" else ",")
        require(reader.fieldnames and len(reader.fieldnames) == len(set(reader.fieldnames)), "CSV needs a header with unique names.")
        required = {time_column, *columns, *group_columns.values()}
        require(required <= set(reader.fieldnames), f"CSV is missing declared columns: {sorted(required - set(reader.fieldnames))}")
        for row in reader:
            rows += 1
            require(rows <= MAX_ROWS and rows * len(columns) <= MAX_VALUES, "CSV exceeds the bounded worker sample limit.")
            require(None not in row and all(value is not None for value in row.values()), f"CSV row {rows + 1} has the wrong number of fields.")
            key = tuple(row[column] for column in group_columns.values())
            require(all(value.strip() and value not in MISSING for value in key), f"CSV row {rows + 1} has an empty grouping identity.")
            try:
                timestamp = Decimal(row[time_column])
            except InvalidOperation as error:
                raise InputError(f"CSV row {rows + 1} has a nonnumeric timestamp.") from error
            require(timestamp.is_finite(), f"CSV row {rows + 1} has a nonfinite timestamp.")
            if current is None or key != previous_key:
                require(len(recordings) < MAX_RECORDINGS, "Too many independent recording segments for one job.")
                current = {"id": f"recording-{len(recordings) + 1}", "group": dict(zip(group_columns, key)),
                           "source_time_origin": str(timestamp), "source_row_start": rows - 1,
                           "times": [], "values": [], "channels": columns, "unit": canonical_unit,
                           "source_unit": metadata["unit"], "scale_factor": factor, "fs": fs}
                recordings.append(current)
                previous_key = key
            relative = float((timestamp - Decimal(current["source_time_origin"])) * time_factor)
            require(math.isfinite(relative) and (not current["times"] or relative > current["times"][-1]),
                    f"Time must increase within each contiguous recording group; row {rows + 1} is duplicate or reversed.")
            values = []
            for column in columns:
                text = row[column].strip()
                if text in MISSING:
                    value = math.nan
                else:
                    try:
                        value = float(text) * factor
                    except ValueError as error:
                        raise InputError(f"CSV row {rows + 1}, channel {column}, is not a number or an explicit missing value.") from error
                    require(math.isfinite(value), f"CSV row {rows + 1}, channel {column}, has an infinite value.")
                values.append(value)
            current["times"].append(relative)
            current["values"].append(values)
    require(rows > 1, "Input recording needs at least two samples.")
    for item in recordings:
        item["times"] = np.asarray(item["times"], float)
        item["values"] = np.asarray(item["values"], float).T
    return recordings, {"rows": rows, "time_unit": time_unit, "group_columns": group_columns, "source_format": "csv"}


def native_eeg(path, metadata, source_format):
    import importlib.util
    mne = require_mne()
    require(source_format in {"edf", "bdf", "fif", "set"}, "Unsupported native EEG format.")
    require(metadata.get("unit") in {"native", "V"}, "Native EEG readers use file-header scaling into volts; set unit to native or V.")
    channels = metadata.get("value_columns")
    require(isinstance(channels, list) and 1 <= len(channels) <= MAX_CHANNELS and len(channels) == len(set(channels)), "Select the native EEG channel names explicitly in value_columns.")
    header_path = Path(__file__).with_name("headers.py")
    spec = importlib.util.spec_from_file_location("brohn_native_calibration", header_path)
    headers = importlib.util.module_from_spec(spec); spec.loader.exec_module(headers)
    try:
        inspection = headers.run({"schema":"brohn-header-request/1.0","operation":"inspect_header","format":source_format,
            "source_path":str(path),"source_hash":digest_file(path)})
    except headers.InputError as error:
        raise InputError(str(error)) from error
    native = inspection["header"]
    require(native["quality"]["source_channel_names_unique"], "Native source channel names are not unique; a qualified reader-name mapping is required.")
    channel_info = {channel["name"]:channel for channel in native["channels"]}
    require(all(channel in channel_info for channel in channels), "A selected EEG channel is absent from the native header.")
    selected = [channel_info[channel] for channel in channels]
    require(len({channel["sampling_rate_hz"] for channel in selected}) == 1,
            "Selected native EEG channels have different sampling rates; this recipe does not silently resample them.")
    if source_format in {"edf", "bdf"}:
        require(all(channel["source_unit"] in {"V","mV","uV"} for channel in selected),
                "Selected EDF/BDF channels need declared voltage units V, mV or uV; undocumented or other units cannot be interpreted as volts.")
        require(all(channel["calibration_evidence"]["valid_linear_range"] for channel in selected),
                "Selected EDF/BDF channels need valid, non-flat physical and digital calibration ranges.")
        require(not native["recording"]["discontinuous"] and native["recording"].get("record_timing_contiguous") is not False,
                "Discontinuous or inconsistent EDF/BDF record timing needs a segmented import before this continuous EEG recipe.")
    elif source_format == "fif":
        require(all(channel["source_unit"] == "V" and channel["calibration_evidence"]["native_unit_multiplier"] == 0 and
                    channel["calibration_evidence"]["cal"] not in (None,0) and channel["calibration_evidence"]["range"] not in (None,0)
                    for channel in selected),
                "Selected FIF EEG channels need declared volts, a supported zero unit multiplier and valid nonzero calibration factors.")
    reader = {"edf": mne.io.read_raw_edf, "bdf": mne.io.read_raw_bdf,
              "fif": mne.io.read_raw_fif, "set": mne.io.read_raw_eeglab}[source_format]
    # MNE otherwise raises every EDF channel to the highest *loaded* rate,
    # even when only a slower channel is requested later by get_data().
    kwargs = {"include": channels} if source_format in {"edf","bdf"} else {}
    raw = reader(str(path), preload=False, verbose=False, **kwargs)
    require(all(channel in raw.ch_names for channel in channels), "A selected EEG channel is absent from the file.")
    require(all(raw.get_channel_types(picks=[channel])[0] == "eeg" for channel in channels), "Select EEG channels only; auxiliary channels need their own modality recipe.")
    require(raw.n_times <= MAX_ROWS and raw.n_times * len(channels) <= MAX_VALUES, "Native recording exceeds the bounded worker sample limit.")
    fs = float(raw.info["sfreq"])
    if metadata.get("sampling_rate") is not None:
        declared = finite(metadata["sampling_rate"], "sampling_rate", .1, 100000)
        require(math.isclose(fs, declared, rel_tol=1e-9), "Declared sampling rate disagrees with the native file header.")
    values = raw.get_data(picks=channels, reject_by_annotation="NaN")
    bad_channels = [name for name in channels if name in raw.info["bads"]]
    for index, channel in enumerate(channels):
        if channel in bad_channels:
            values[index, :] = np.nan
    info = {"source_format": source_format, "rows": int(raw.n_times), "native_first_sample": int(raw.first_samp),
            "native_first_time_s": float(raw.first_time), "bad_channels_excluded": bad_channels,
            "annotation_count": len(raw.annotations), "annotation_exclusion": "MNE BAD annotations excluded before segmentation",
            "native_reader": reader.__name__, "amplitude_scaling": "EEGLAB reader microvolt convention to volts" if source_format=="set" else "validated file header to volts",
            "calibration_gate": {"profile":"native-eeg-declared-calibration/1.0","inspector_sha256":digest_file(header_path),
                "source_sha256":inspection["source"]["sha256"],"selected_channels":selected,
                "resampling_applied":False,"external_companions_followed":False}}
    info["annotations"] = [{"onset_s": float(onset), "duration_s": float(duration), "description": str(description)}
                           for onset, duration, description in zip(raw.annotations.onset[:MAX_DISPLAY], raw.annotations.duration[:MAX_DISPLAY], raw.annotations.description[:MAX_DISPLAY])]
    info["annotations_displayed"] = len(info["annotations"])
    recording = {"id": "recording-1", "group": {key: metadata[key] for key in ["participant_id", "session_id", "condition_id", "exposure_id"] if metadata.get(key)},
                 "source_time_origin": str(raw.first_time), "source_row_start": int(raw.first_samp),
                 "times": raw.times.copy(), "values": values, "channels": channels, "unit": "V", "source_unit": "native header", "scale_factor": 1.0, "fs": fs}
    raw.close()
    return [recording], info


def continuous_segments(recording, channel, metadata, modality):
    t = recording["times"]
    x = recording["values"][channel]
    fs = recording["fs"]
    tolerance = finite(metadata.get("timestamp_tolerance_s", .02 / fs), "timestamp_tolerance_s", 0, .5 / fs)
    delta = np.diff(t)
    gaps = delta > 1.5 / fs
    require(np.all(gaps | (np.abs(delta - 1 / fs) <= tolerance + 1e-12)),
            f"Recording {recording['id']} has irregular sampling inconsistent with its declared rate. This recipe does not silently resample.")
    valid = np.isfinite(x)
    physically_invalid = np.zeros(len(x), bool)
    if modality == "eda":
        physically_invalid = valid & (x < 0)
        valid &= ~physically_invalid
    boundaries = np.ones(len(x), bool)
    if len(x) > 1:
        boundaries[1:] = ~valid[:-1] | gaps
    starts = np.flatnonzero(valid & boundaries)
    segments = []
    for start in starts:
        end = start + 1
        while end < len(x) and valid[end] and not gaps[end - 1]:
            end += 1
        segments.append((int(start), int(end)))
    return segments, {"missing_samples": int((~np.isfinite(x)).sum()), "invalid_amplitude_samples": int(physically_invalid.sum()),
                      "time_gap_count": int(gaps.sum()), "time_gap_seconds": float(np.maximum(delta[gaps] - 1 / fs, 0).sum()),
                      "timestamp_tolerance_s": tolerance}


def trim_bounds(n, fs, edge):
    excluded = int(math.ceil(edge * fs))
    require(n - 2 * excluded >= max(2, int(fs)), "Continuous segment is too short after declared filter-edge exclusions.")
    return excluded, n - excluded


def output_pack(features, events, series, parameters, support, limitations=()):
    return {"features": features, "events": events, "series": series, "parameters": parameters,
            "support": support, "limitations": list(limitations)}


def feature(name, value, unit, **extra):
    return {"name": name, "value": number(value), "unit": unit, "scope": "recording", **extra}


def eda(x, t, fs, p):
    nk = require_neurokit()
    lo, hi = trim_bounds(len(x), fs, p["edge_exclusion_s"])
    require((hi - lo) / fs >= 20, "EDA needs at least 20 retained seconds after edge exclusions (40 seconds at default settings).")
    clean = np.asarray(nk.eda_clean(x, sampling_rate=fs, method="neurokit"))
    components = nk.eda_phasic(clean, sampling_rate=fs, method="highpass", cutoff=p["phasic_cutoff_hz"])
    tonic, phasic = np.asarray(components["EDA_Tonic"]), np.asarray(components["EDA_Phasic"])
    require(np.isfinite(tonic).all() and np.isfinite(phasic).all(), "EDA decomposition returned nonfinite components.")
    _, info = nk.eda_peaks(phasic, sampling_rate=fs, method="neurokit", amplitude_min=p["amplitude_min_relative_prominence"])
    peaks = np.asarray(info["SCR_Peaks"], dtype=int)
    events, amplitudes = [], []
    for i, peak in enumerate(peaks):
        if not lo <= peak < hi:
            continue
        def get(key):
            values = info.get(key, [])
            return number(values[i]) if i < len(values) else None
        onset, recovery = get("SCR_Onsets"), get("SCR_Recovery")
        onset_valid = onset is not None and lo <= onset <= peak
        recovery_valid = recovery is not None and peak <= recovery < hi
        amplitude = get("SCR_Amplitude") if onset_valid else None
        if amplitude is not None:
            amplitudes.append(amplitude)
        events.append({"type": "scr", "time_s": float(t[peak]), "peak_sample": int(peak),
                       "onset_time_s": float(t[int(onset)]) if onset_valid else None,
                       "recovery_time_s": float(t[int(recovery)]) if recovery_valid else None,
                       "amplitude_us": amplitude, "peak_height_us": float(phasic[peak]),
                       "rise_time_s": (peak - onset) / fs if onset_valid else None,
                       "recovery_time_from_peak_s": (recovery - peak) / fs if recovery_valid else None,
                       "recovery_fraction": .5, "missing_reason": None if onset_valid and recovery_valid else "onset_or_recovery_outside_retained_support"})
    duration = (hi - lo) / fs
    features = [feature("tonic_mean", tonic[lo:hi].mean(), "uS"), feature("tonic_median", np.median(tonic[lo:hi]), "uS"),
                feature("tonic_slope", np.polyfit(t[lo:hi] - t[lo], tonic[lo:hi], 1)[0], "uS/s"),
                feature("conductance_raw_mean", x[lo:hi].mean(), "uS"), feature("scr_count", len(events), "count"),
                feature("scr_rate", len(events) * 60 / duration, "count/min"),
                feature("scr_amplitude_mean", np.mean(amplitudes) if amplitudes else None, "uS", denominator=len(amplitudes)),
                feature("scr_amplitude_median", np.median(amplitudes) if amplitudes else None, "uS", denominator=len(amplitudes)),
                feature("phasic_area_signed", np.trapezoid(phasic[lo:hi], t[lo:hi]), "uS*s"),
                feature("phasic_area_positive", np.trapezoid(np.maximum(phasic[lo:hi], 0), t[lo:hi]), "uS*s")]
    series = {"time_s": t, "raw_us": x, "clean_us": clean, "tonic_us": tonic, "phasic_us": phasic,
              "retained": (np.arange(len(x)) >= lo) & (np.arange(len(x)) < hi)}
    return output_pack(features, events, series, p, {"retained_samples": hi - lo, "retained_duration_s": duration, "filter_edge_samples": 2 * lo},
                       ["SCR detector threshold is relative prominence, not an absolute conductance threshold.",
                        "No event attribution or baseline contrast is inferred from recording-level peaks.",
                        "Missing onset or recovery remains unavailable; no-response count and finite-amplitude denominator differ."])


def eeg(x, t, fs, p):
    mne = require_mne()
    n = int(round(p["window_s"] * fs))
    require(len(x) >= n * 2, "EEG PSD needs at least two declared analysis windows in each continuous segment.")
    psd, frequencies = mne.time_frequency.psd_array_welch(x, sfreq=fs, fmin=0, fmax=fs / 2, n_fft=n,
        n_per_seg=n, n_overlap=int(n * p["overlap_fraction"]), window="hann", average="mean", remove_dc=True, verbose=False)
    width = float(frequencies[1] - frequencies[0])
    def band(bounds):
        bins = (frequencies >= bounds[0]) & (frequencies < bounds[1])
        require(bins.any(), "An EEG band contains no frequency bin at the declared window resolution.")
        return float(psd[bins].sum() * width)
    denominator = band(p["relative_denominator_hz"])
    features = [feature("signal_rms", np.sqrt(np.mean(x*x)) * 1e6, "uV"),
                feature("psd_total_power", psd.sum() * width * 1e12, "uV^2"),
                feature("psd_peak_frequency", frequencies[np.argmax(psd)] if np.any(psd > 0) else None, "Hz"),
                feature("relative_power_denominator", denominator * 1e12, "uV^2")]
    for name, bounds in p["bands_hz"].items():
        power = band(bounds)
        features.extend([feature(f"{name}_absolute_power", power * 1e12, "uV^2", band_hz=bounds),
                         feature(f"{name}_relative_power", power / denominator if denominator > 0 else None, "proportion", band_hz=bounds)])
    p = {**p, "frequency_bin_width_hz": width, "n_fft": n, "n_per_segment": n, "n_overlap": int(n * p["overlap_fraction"])}
    events = [{"type": "psd_bin", "frequency_hz": float(f), "density_uv2_hz": float(d * 1e12)} for f, d in zip(frequencies, psd)]
    return output_pack(features, events, {"time_s": t, "raw_uv": x * 1e6}, p,
                       {"retained_samples": len(x), "retained_duration_s": len(x) / fs, "filter_edge_samples": 0},
                       ["Channel PSD preserves acquisition reference; no ICA, notch, re-reference or artifact removal is silently applied.",
                        "No ERP is estimated without a separate measured-marker and epoch specification.",
                        "Band power is a signal measure, not a universal attention, engagement or emotion score."])


def interval_metrics(peaks, fs, p, prefix):
    intervals = np.diff(peaks) * 1000 / fs
    valid = (intervals >= p["interval_min_ms"]) & (intervals <= p["interval_max_ms"])
    retained = intervals[valid]
    adjacent = valid[:-1] & valid[1:]
    differences = np.diff(intervals)[adjacent]
    nn50 = int(np.sum(np.abs(differences) > 50))
    features = [feature(f"{prefix}_interval_count", len(intervals), "count"), feature(f"{prefix}_retained_interval_count", len(retained), "count"),
                feature(f"{prefix}_successive_pair_count", len(differences), "count"),
                feature(f"{prefix}_mean_interval", retained.mean() if len(retained) else None, "ms"),
                feature(f"{prefix}_sd_interval", retained.std(ddof=1) if len(retained) > 1 else None, "ms"),
                feature(f"{prefix}_rmssd", np.sqrt(np.mean(differences**2)) if len(differences) else None, "ms"),
                feature(f"{prefix}_pnn50_candidate", 100 * nn50 / len(retained) if len(retained) and len(differences) else None, "%", numerator=nn50, denominator=len(retained)),
                feature(f"{prefix}_rate_from_mean_interval", 60000 / retained.mean() if len(retained) else None, "beats/min"),
                feature(f"{prefix}_mean_interval_rate", np.mean(60000 / retained) if len(retained) else None, "beats/min")]
    duration = (peaks[-1] - peaks[0]) / fs if len(peaks) > 1 else 0
    frequency = {"lf_power": None, "hf_power": None, "lf_hf_ratio": None}
    frequency_reason = "requires_complete_plausible_intervals_and_at_least_300_seconds"
    if len(intervals) >= 10 and valid.all() and duration >= p["frequency_min_duration_s"]:
        times = peaks[1:] / fs
        uniform = np.arange(times[0], times[-1], .25)
        interpolated = np.interp(uniform, times, intervals)
        frequencies, power = signal.welch(interpolated, fs=4, window="hann", nperseg=512, noverlap=256, detrend="constant", scaling="density")
        df = frequencies[1] - frequencies[0]
        lf = float(power[(frequencies >= .04) & (frequencies < .15)].sum() * df)
        hf = float(power[(frequencies >= .15) & (frequencies <= .4)].sum() * df)
        frequency = {"lf_power": lf, "hf_power": hf, "lf_hf_ratio": lf / hf if hf > 0 else None}
        frequency_reason = None
    for name, value in frequency.items():
        features.append(feature(f"{prefix}_{name}_candidate", value, "ratio" if name.endswith("ratio") else "ms^2", unavailable_reason=frequency_reason))
    return features, intervals, valid


def cardiac(x, t, fs, p, modality):
    nk = require_neurokit()
    lo, hi = trim_bounds(len(x), fs, p["edge_exclusion_s"])
    require((hi - lo) / fs >= 10, "Cardiac detection needs at least ten retained seconds after edge exclusions.")
    if modality == "ecg":
        clean = np.asarray(nk.ecg_clean(x, sampling_rate=fs, method="neurokit", powerline=p["powerline_hz"]))
        _, info = nk.ecg_peaks(clean, sampling_rate=fs, method="neurokit", correct_artifacts=False)
        peaks = np.asarray(info["ECG_R_Peaks"], int)
        prefix, event_type = "detected_rr", "r_peak"
    else:
        clean = np.asarray(nk.ppg_clean(x, sampling_rate=fs, method="elgendi"))
        _, info = nk.ppg_peaks(clean, sampling_rate=fs, method="elgendi", correct_artifacts=False)
        peaks = np.asarray(info["PPG_Peaks"], int)
        prefix, event_type = "detected_prv", "systolic_pulse_peak"
    peaks = peaks[(peaks >= lo) & (peaks < hi)]
    features, intervals, valid = interval_metrics(peaks, fs, p, prefix)
    features.insert(0, feature("detected_peak_count", len(peaks), "count"))
    events = [{"type": event_type, "time_s": float(t[peak]), "sample_index": int(peak),
               "previous_interval_ms": float(intervals[i-1]) if i else None,
               "previous_interval_plausible": bool(valid[i-1]) if i else None}
              for i, peak in enumerate(peaks)]
    return output_pack(features, events, {"time_s": t, "raw": x, "clean": clean,
                                         "retained": (np.arange(len(x)) >= lo) & (np.arange(len(x)) < hi)}, p,
                       {"retained_samples": hi-lo, "retained_duration_s": (hi-lo)/fs, "filter_edge_samples": 2*lo,
                        "detected_peak_count": len(peaks), "implausible_interval_count": int((~valid).sum()), "normal_to_normal_intervals_confirmed": False},
                       ["Detected beats/pulses require review; no automatic artifact correction was applied.",
                        "Interval plausibility screening does not establish normal-to-normal intervals or clinical HRV qualification.",
                        "Rejected intervals do not create new successive pairs across the gap.",
                        "LF/HF is not interpreted as sympathovagal balance or stress.",
                        "PPG interval variability is PRV and is not interchangeable with ECG HRV." if modality == "ppg" else "No diagnostic arrhythmia or health interpretation is made."])


def respiration(x, t, fs, p):
    nk = require_neurokit()
    lo, hi = trim_bounds(len(x), fs, p["edge_exclusion_s"])
    require((hi-lo)/fs >= 20, "Respiration requires twenty retained seconds after edge exclusions.")
    clean = np.asarray(nk.rsp_clean(x, sampling_rate=fs, method="khodadad2018"))
    _, info = nk.rsp_peaks(clean, sampling_rate=fs, method="khodadad2018")
    peaks, troughs = np.asarray(info["RSP_Peaks"], int), np.asarray(info["RSP_Troughs"], int)
    events = []
    for start, end in zip(troughs[:-1], troughs[1:]):
        candidates = peaks[(peaks > start) & (peaks < end)]
        if lo <= start < end < hi and len(candidates) == 1:
            peak = int(candidates[0])
            events.append({"type": "respiration_cycle", "time_s": float(t[start]), "end_time_s": float(t[end]),
                           "peak_time_s": float(t[peak]), "duration_s": (end-start)/fs,
                           "inspiration_s": (peak-start)/fs, "expiration_s": (end-peak)/fs,
                           "amplitude": float(clean[peak]-clean[start])})
    durations = np.asarray([item["duration_s"] for item in events])
    inspiration = np.asarray([item["inspiration_s"] for item in events])
    expiration = np.asarray([item["expiration_s"] for item in events])
    amplitudes = np.asarray([item["amplitude"] for item in events])
    mean = lambda a: a.mean() if len(a) else None
    features = [feature("complete_breath_count", len(events), "count"),
                feature("respiration_rate", 60 / durations.mean() if len(durations) else None, "breaths/min"),
                feature("inspiration_duration", mean(inspiration), "s"), feature("expiration_duration", mean(expiration), "s"),
                feature("inspiration_expiration_ratio", mean(inspiration/expiration), "ratio"),
                feature("cycle_amplitude_mean", mean(amplitudes), "source_unit"),
                feature("cycle_amplitude_per_duration_mean", mean(amplitudes/durations), "source_unit/s")]
    return output_pack(features, events, {"time_s": t, "raw": x, "clean": clean,
                                         "retained": (np.arange(len(x)) >= lo) & (np.arange(len(x)) < hi)}, p,
                       {"retained_samples": hi-lo, "retained_duration_s": (hi-lo)/fs, "filter_edge_samples": 2*lo, "complete_cycle_count": len(events)},
                       ["Positive excursion is treated as inspiration; confirm the sensor's polarity.",
                        "Belt/source amplitude is not automatically tidal volume. The amplitude-per-duration output is an explicitly defined cycle metric, not a substituted published RVT algorithm.",
                        "No detected complete breaths yields unavailable rate, not zero breathing."])


def emg(x, t, fs, p):
    lo, hi = trim_bounds(len(x), fs, max(p["edge_exclusion_s"], p["rms_window_s"] / 2))
    sos = signal.butter(4, [p["highpass_hz"], p["lowpass_hz"]], btype="bandpass", fs=fs, output="sos")
    clean = signal.sosfiltfilt(sos, x)
    size = max(1, int(round(p["rms_window_s"] * fs)))
    rms = np.sqrt(np.maximum(ndimage.uniform_filter1d(clean**2, size=size, mode="nearest"), 0))
    rectified = np.abs(clean)
    features = [feature("emg_rms", np.sqrt(np.mean(clean[lo:hi]**2)), "uV"), feature("emg_envelope_mean", rms[lo:hi].mean(), "uV"),
                feature("emg_rectified_mean", rectified[lo:hi].mean(), "uV"),
                feature("emg_integrated_rectified", np.trapezoid(rectified[lo:hi], t[lo:hi]), "uV*s")]
    frequencies, power = signal.welch(clean[lo:hi], fs=fs, nperseg=min(int(fs), hi-lo), window="hann", detrend="constant")
    total = power.sum()
    features.extend([feature("emg_mean_frequency", float(np.sum(frequencies*power)/total) if total > 0 else None, "Hz"),
                     feature("emg_median_frequency", frequencies[np.searchsorted(np.cumsum(power), total/2)] if total > 0 else None, "Hz")])
    events = []
    if p["burst_threshold_uv"] is not None:
        active = rms[lo:hi] >= p["burst_threshold_uv"]
        starts = np.flatnonzero(np.diff(np.r_[False, active].astype(int)) == 1)
        ends = np.flatnonzero(np.diff(np.r_[active, False].astype(int)) == -1) + 1
        for start, end in zip(starts, ends):
            if (end-start)/fs >= p["burst_min_duration_s"]:
                events.append({"type": "emg_threshold_burst", "time_s": float(t[lo+start]),
                               "end_time_s": float(t[lo+end-1] + 1/fs), "duration_s": (end-start)/fs,
                               "peak_rms_uv": float(rms[lo+start:lo+end].max()),
                               "boundary_truncated": bool(start == 0 or end == len(active))})
        features.extend([feature("emg_burst_count", len(events), "count"),
                         feature("emg_accepted_burst_time_fraction", sum(event["duration_s"] for event in events)/((hi-lo)/fs), "proportion")])
    return output_pack(features, events, {"time_s": t, "raw_uv": x, "clean_uv": clean, "rms_uv": rms,
                                         "retained": (np.arange(len(x)) >= lo) & (np.arange(len(x)) < hi)}, {**p, "rms_window_samples": size},
                       {"retained_samples": hi-lo, "retained_duration_s": (hi-lo)/fs, "filter_edge_samples": 2*lo},
                       ["Surface EMG settings are not automatically a facial/startle or MVC-normalized recipe.",
                       "No burst threshold is invented when an explicit calibrated threshold is absent."])


def auxiliary_result(modality, path, packages, parameters, group):
    return {"schema": "brohn-worker-result/1.0", "modality": modality, "status": "completed",
            "engine": {"name": "Brohn physiology worker", "version": "1.0.0", "python": platform.python_version(), "packages": versions(packages)},
            "source": {"sha256": digest_file(path), "bytes": path.stat().st_size}, "parameters": {"recording-1": parameters},
            "features": [], "events": [], "series": [], "recordings": [], "limitations": [], "artifacts": []}


def prepare_artifacts(request, result):
    """Optional full processed outputs; publisher confines the declared directory."""
    if not request.get("artifact_directory"):
        return None
    import importlib.util
    module_path = Path(__file__).with_name("physiology_artifacts.py")
    spec = importlib.util.spec_from_file_location("brohn_physiology_artifact_io", module_path)
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    result["engine"].setdefault("worker_sha256", digest_file(Path(__file__)))
    result["engine"]["artifact_writer_sha256"] = digest_file(module_path)
    metadata = request["metadata"]
    frozen = {"requested": request.get("parameters", metadata.get("parameters", {})), "source_mapping": metadata,
              "source_evidence": result["source"]}
    writers = module.ArtifactSet(request["artifact_directory"], {"source_sha256":result["source"]["sha256"],
        "engine":result["engine"], "operation":request["operation"], "origin":metadata.get("origin", "unspecified"), "parameters":frozen})
    request["_artifact_state"].append(writers)
    return module, writers


def finish_artifacts(result, prepared):
    if prepared is not None:
        result["artifacts"] = prepared[1].finish()
        result["quality"]["complete_processed_artifacts"] = True
        result["quality"]["raw_source_duplicated"] = False


def declared_group(metadata):
    require(not any(metadata.get(key) for key in ["participant_column", "session_column", "condition_column", "exposure_column", "segment_column"]),
            "Native media has no CSV grouping columns. Declare recording identity fields; separate files or prespecified segments are required for different conditions.")
    return {key: metadata[key] for key in ["participant_id", "session_id", "condition_id", "exposure_id"] if metadata.get(key)}


def audio_file(request, path, metadata):
    import soundfile as sf
    import parselmouth
    import librosa
    require(importlib.metadata.version("praat-parselmouth") == "0.4.7", "Audio recipe requires the prepared Praat-Parselmouth 0.4.7 environment.")
    require(request["format"] in {"wav", "flac", "ogg"}, "Audio profile accepts WAV, FLAC or OGG decoded by SoundFile.")
    require(metadata.get("unit") in {"FS", "normalized_full_scale"}, "Audio amplitude unit must be FS (normalized digital full scale); calibrated sound-pressure units need a calibration profile.")
    with sf.SoundFile(path) as source:
        require(0 < source.frames <= MAX_VALUES, "Audio exceeds the bounded sample limit.")
        fs, channel_count = float(source.samplerate), int(source.channels)
        require(channel_count <= MAX_CHANNELS and source.frames*channel_count <= MAX_VALUES, "Decoded multichannel audio exceeds the bounded sample limit.")
        require(source.frames / fs >= 2, "Audio needs at least two seconds for this acoustic recipe.")
        index = metadata.get("channel_index", 0 if channel_count == 1 else None)
        require(isinstance(index, int) and not isinstance(index, bool) and 0 <= index < channel_count,
                "Select metadata.channel_index explicitly for multichannel audio; zero denotes the first channel.")
        if metadata.get("sampling_rate") is not None:
            require(float(metadata["sampling_rate"]) == fs, "Declared audio sampling rate disagrees with its file header.")
        x = source.read(dtype="float64", always_2d=True)[:, index]
    require(np.isfinite(x).all(), "Audio contains nonfinite samples. Explicitly repair/mask separate recordings before acoustic analysis.")
    defaults = {"recipe": "audio-praat-acoustics/1.0", "pitch_floor_hz": 75.0, "pitch_ceiling_hz": 600.0, "frame_step_s": .01, "spectral_frame_s": .025}
    supplied = request.get("parameters", metadata.get("parameters", {}))
    require(isinstance(supplied, dict) and not (set(supplied)-set(defaults)), "Unsupported audio recipe parameters.")
    p = {**defaults, **supplied}
    require(p["recipe"] == defaults["recipe"], "Unsupported audio recipe.")
    finite(p["pitch_floor_hz"], "pitch_floor_hz", 30, 500)
    finite(p["pitch_ceiling_hz"], "pitch_ceiling_hz", p["pitch_floor_hz"]+1, min(2000, fs/2))
    finite(p["frame_step_s"], "frame_step_s", .005, .1)
    finite(p["spectral_frame_s"], "spectral_frame_s", .01, .1)
    p.update(pitch_method="Praat autocorrelation", amplitude_reference="digital full scale", calibration_to_spl=False,
             channel_index=index, channel_mixing="none", voiced_definition="positive Praat selected frequency, not speech recognition")
    group = declared_group(metadata)
    result = auxiliary_result("audio", path, ["numpy", "scipy", "soundfile", "praat-parselmouth", "librosa"], p, group)
    identity = {"recording_id": "recording-1", "segment_id": "recording-1-segment-1", "channel": f"audio-{index}", "group": group}
    pitch = parselmouth.Sound(x, sampling_frequency=fs).to_pitch_ac(time_step=p["frame_step_s"], pitch_floor=p["pitch_floor_hz"], pitch_ceiling=p["pitch_ceiling_hz"])
    f0 = pitch.selected_array["frequency"]
    voiced = f0[np.isfinite(f0) & (f0 > 0)]
    frame = max(32, int(round(fs*p["spectral_frame_s"])))
    hop = max(1, int(round(fs*p["frame_step_s"])))
    rms = librosa.feature.rms(y=x, frame_length=frame, hop_length=hop, center=False)[0]
    spectrum = np.abs(librosa.stft(x, n_fft=frame, hop_length=hop, win_length=frame, window="hann", center=False))
    centroid = librosa.feature.spectral_centroid(S=spectrum, sr=fs, n_fft=frame)[0]
    energy_frames = rms > np.finfo(float).eps
    features = [feature("audio_rms", np.sqrt(np.mean(x*x)), "FS"), feature("audio_absolute_peak", np.max(np.abs(x)), "FS"),
                feature("audio_zero_crossing_rate", np.mean(np.signbit(x[1:]) != np.signbit(x[:-1])), "crossings/sample"),
                feature("pitch_median", np.median(voiced) if len(voiced) else None, "Hz", denominator=len(voiced)),
                feature("pitch_mean", voiced.mean() if len(voiced) else None, "Hz", denominator=len(voiced)),
                feature("pitch_sd", voiced.std(ddof=1) if len(voiced)>1 else None, "Hz", denominator=len(voiced)),
                feature("periodic_frame_fraction", len(voiced)/len(f0) if len(f0) else None, "proportion"),
                feature("spectral_centroid_mean", centroid[energy_frames].mean() if energy_frames.any() else None, "Hz", denominator=int(energy_frames.sum()))]
    result["features"] = [{**identity, **item} for item in features]
    prepared = prepare_artifacts(request, result)
    if prepared is not None:
        module, writers = prepared
        coords = {"axis":"time", "reference":"audio frame centres in seconds after the source start", "source_time_origin":"0", "source_time_unit":"s"}
        support = {"source_samples":len(x), "source_sampling_rate":fs, "frame_length_samples":frame, "frame_hop_samples":hop, "parameters":p, "raw_source_omitted":True}
        columns = [module._column("time_s", "float64", "s", role="coordinate"), module._column("rms_fs", "float64", "FS"),
                   module._column("spectral_centroid_hz", "float64", "Hz", True)]
        writers.series.write_table("audio-spectral-frames", identity, columns, coords, support,
            ([float((i*hop+frame/2)/fs), float(rms[i]), float(centroid[i]) if energy_frames[i] else None] for i in range(len(rms))), len(rms))
        columns = [module._column("type", "string", None, role="label"), module._column("time_s", "float64", "s", role="coordinate"),
                   module._column("pitch_hz", "float64", "Hz", True), module._column("periodic", "boolean", None, role="support")]
        pitch_times = pitch.xs()
        writers.events.write_table("audio-pitch-frames", identity, columns, {**coords,"axis":"event","reference":"Praat measured pitch-frame centre seconds after source start"}, support,
            (["pitch_frame", float(pitch_times[i]), float(f0[i]) if f0[i]>0 else None, bool(f0[i]>0)] for i in range(len(f0))), len(f0))
    selected = np.unique(np.linspace(0, len(rms)-1, min(MAX_DISPLAY, len(rms)), dtype=int))
    for i in selected:
        result["series"].append({**identity, "time_s": float((i*hop+frame/2)/fs), "rms_fs": float(rms[i]),
                                 "spectral_centroid_hz": float(centroid[i]) if energy_frames[i] else None})
    selected = np.unique(np.linspace(0, len(f0)-1, min(MAX_DISPLAY, len(f0)), dtype=int))
    times = pitch.xs()
    result["events"] = [{**identity, "type": "pitch_frame", "time_s": float(times[i]), "pitch_hz": float(f0[i]) if f0[i]>0 else None,
                          "periodic": bool(f0[i]>0)} for i in selected]
    result["recordings"] = [{**identity, "status": "computed", "samples": len(x), "sampling_rate": fs,
                             "unit": "FS", "retained_samples": len(x), "retained_duration_s": len(x)/fs}]
    result["source"].update(source_format=request["format"], native_channels=channel_count, native_sampling_rate=fs)
    result["quality"] = {"usable": True, "requires_research_review": True, "scientifically_qualified": False,
                         "computed_channel_segments": 1, "unavailable_channel_segments": 0,
                         "retained_fraction": 1.0, "full_scale_or_exceeding_samples": int((np.abs(x)>=1).sum()),
                         "exact_silence": bool(np.all(x==0)), "event_records_total": len(f0), "event_records_displayed": len(result["events"]),
                         "series_samples_total": len(rms), "series_samples_displayed": len(result["series"]),
                         "display_sampling": "uniform frame selection; all acoustic metrics use all frames/samples"}
    result["limitations"] = ["Pitch periodicity is not a voice-activity or emotion classifier.",
        "No transcript, speaker identity, diarization, calibrated loudness, emotion or attention inference is produced.",
        "Pitch range must suit the recording/population; unvoiced frames remain unavailable rather than zero hertz.",
        "Recording summaries do not establish condition differences or independent participant observations."]
    finish_artifacts(result, prepared)
    return result


def fnirs_file(request, path, metadata):
    mne = require_mne()
    from mne.preprocessing.nirs import optical_density, beer_lambert_law, scalp_coupling_index, source_detector_distances
    require(request["format"] == "snirf", "This fNIRS recipe requires a native continuous-wave SNIRF file.")
    require(metadata.get("unit") == "native", "fNIRS intensity and geometry units must come from the SNIRF header; declare unit native.")
    group = declared_group(metadata)
    supplied = request.get("parameters", metadata.get("parameters", {}))
    defaults = {"recipe": "fnirs-od-beer-lambert/1.0", "ppf": None, "minimum_segment_s": 20.0}
    require(isinstance(supplied, dict) and not (set(supplied)-set(defaults)), "Unsupported fNIRS recipe parameters.")
    p = {**defaults, **supplied}
    require(p["recipe"] == defaults["recipe"], "Unsupported fNIRS recipe.")
    require(isinstance(p["ppf"], list) and len(p["ppf"]) == 2, "Declare two wavelength-specific partial pathlength factors as parameters.ppf; no universal factor is assumed.")
    for value in p["ppf"]: finite(value, "ppf", .1, 100)
    finite(p["minimum_segment_s"], "minimum_segment_s", 20, 3600)
    raw = mne.io.read_raw_snirf(str(path), preload=False, verbose=False)
    fs = float(raw.info["sfreq"])
    require(fs >= 4, "The fNIRS scalp-coupling recipe requires sampling rate of at least 4 Hz.")
    require(raw.n_times <= MAX_ROWS, "SNIRF exceeds the bounded worker sample limit.")
    if metadata.get("sampling_rate") is not None:
        require(math.isclose(float(metadata["sampling_rate"]),fs,rel_tol=1e-9), "Declared fNIRS sampling rate disagrees with its file header.")
    channels = metadata.get("value_columns")
    require(isinstance(channels,list) and 2 <= len(channels) <= MAX_CHANNELS and all(name in raw.ch_names for name in channels), "Select complete wavelength-paired fNIRS channel names in value_columns.")
    require(len(channels)*raw.n_times <= MAX_VALUES, "Selected SNIRF data exceed the worker sample limit.")
    raw.pick(channels).load_data()
    require(set(raw.get_channel_types()) == {"fnirs_cw_amplitude"}, "The SNIRF file must contain continuous-wave intensity, not already converted or time-domain values.")
    wavelengths = sorted({float(channel["loc"][9]) for channel in raw.info["chs"]})
    require(len(wavelengths)==2 and all(650 <= value <= 1000 for value in wavelengths), "This recipe requires two explicit supported near-infrared wavelengths.")
    distances = source_detector_distances(raw.info)
    require(np.isfinite(distances).all() and np.all((distances>0)&(distances<=.1)), "Missing, zero or implausible source-detector geometry blocks Beer-Lambert conversion.")
    values = raw.get_data(reject_by_annotation="NaN")
    for i,name in enumerate(raw.ch_names):
        if name in raw.info["bads"]: values[i,:]=np.nan
    valid = np.isfinite(values).all(axis=0) & (values>0).all(axis=0)
    starts=np.flatnonzero(np.diff(np.r_[False,valid].astype(int))==1)
    ends=np.flatnonzero(np.diff(np.r_[valid,False].astype(int))==-1)+1
    p.update(wavelengths_nm=wavelengths, optical_density_reference="arithmetic mean intensity in each continuous segment; not an experimental baseline",
             haemoglobin_unit="uM", motion_correction="none", short_channel_regression="none", scalp_coupling_band_hz=[.7,1.5])
    result=auxiliary_result("fnirs",path,["numpy","scipy","mne","mne-nirs","snirf"],p,group)
    bundles=[]; warnings_seen=[]
    prepared = prepare_artifacts(request, result)
    for segment_number,(start,end) in enumerate(zip(starts,ends),1):
        require(segment_number <= MAX_RECORDINGS, "Too many fNIRS discontinuities for one job.")
        identity={"recording_id":"recording-1","segment_id":f"recording-1-segment-{segment_number}","group":group}
        if (end-start)/fs < p["minimum_segment_s"]:
            result["recordings"].append({**identity,"status":"unavailable","source_row_start":int(start),"source_row_end_exclusive":int(end),"reason":"Insufficient continuous positive-intensity support."})
            continue
        segment=mne.io.RawArray(values[:,start:end],raw.info.copy(),verbose=False)
        with warnings.catch_warnings(record=True) as captured:
            warnings.simplefilter("always")
            od=optical_density(segment,verbose=False)
            sci=scalp_coupling_index(od,l_freq=.7,h_freq=1.5,verbose=False)
            hb=beer_lambert_law(od,ppf=np.asarray(p["ppf"]))
            warnings_seen.extend(str(item.message)[:400] for item in captured)
        od_data=od.get_data(); hb_data=hb.get_data()*1e6
        require(np.isfinite(od_data).all() and np.isfinite(hb_data).all(), "fNIRS conversion returned nonfinite concentrations.")
        times=np.arange(start,end)/fs
        for channel_index,channel in enumerate(hb.ch_names):
            ids={**identity,"channel":channel}
            values_hb=hb_data[channel_index]
            feats=[feature("haemoglobin_mean_change",values_hb.mean(),"uM"),feature("haemoglobin_sd",values_hb.std(ddof=1),"uM"),
                   feature("haemoglobin_peak_to_peak",np.ptp(values_hb),"uM"),feature("source_intensity_optical_density_mean",od_data[channel_index].mean(),"dimensionless",source_intensity_channel=od.ch_names[channel_index]),
                   feature("scalp_coupling_index",sci[channel_index],"correlation")]
            result["features"].extend({**ids,**item} for item in feats)
            result["recordings"].append({**ids,"status":"computed","source_row_start":int(start),"source_row_end_exclusive":int(end),
                "source_time_origin":str(raw.first_time),"sampling_rate":fs,"unit":"uM","retained_samples":int(end-start),
                "retained_duration_s":(end-start)/fs,"source_detector_distance_m":float(distances[channel_index]),"haemoglobin_type":hb.get_channel_types()[channel_index]})
            bundles.append(({**ids,"optical_density_source_channel":od.ch_names[channel_index]},times,od_data[channel_index],values_hb))
            if prepared is not None:
                module, writers = prepared
                columns = [module._column("time_s", "float64", "s", role="coordinate"), module._column("source_sample_index", "integer", "sample_index", role="index"),
                           module._column("optical_density", "float64", "dimensionless"), module._column("haemoglobin_um", "float64", "uM")]
                coordinates = {"axis":"time", "reference":"seconds relative to the original recording's sample zero",
                               "source_time_origin":str(raw.first_time), "source_time_unit":"s"}
                writers.series.write_arrays(f"fnirs-{segment_number}-{channel_index}", {**ids,"optical_density_source_channel":od.ch_names[channel_index]},
                    {"time_s":times, "source_sample_index":range(int(start),int(end)), "optical_density":od_data[channel_index], "haemoglobin_um":values_hb},
                    columns, coordinates, {"source":result["recordings"][-1], "parameters":p, "raw_source_omitted":True})
    require(len(bundles)<=MAX_DISPLAY,"Too many fNIRS channel segments for one bounded result.")
    remaining=MAX_DISPLAY
    for index,(ids,times,od_values,hb_values) in enumerate(bundles):
        count=min(len(times),max(1,remaining//(len(bundles)-index)))
        selected=np.unique(np.linspace(0,len(times)-1,count,dtype=int)); remaining-=len(selected)
        result["series"].extend({**ids,"time_s":float(times[i]),"optical_density":float(od_values[i]),"haemoglobin_um":float(hb_values[i])} for i in selected)
    raw.close()
    if not bundles: result["status"]="insufficient_support"
    elif any(item["status"]=="unavailable" for item in result["recordings"]): result["status"]="partial"
    result["quality"]={"usable":bool(bundles),"requires_research_review":True,"scientifically_qualified":False,
        "computed_channel_segments":len(bundles),"unavailable_channel_segments":sum(item["status"]=="unavailable" for item in result["recordings"]),
        "invalid_or_missing_time_samples":int((~valid).sum()),"source_time_samples":len(valid),
        "series_samples_total":sum(len(item[1]) for item in bundles),"series_samples_displayed":len(result["series"]),
        "warnings":sorted(set(warnings_seen))[:100],"scalp_coupling_is_screening_only":True}
    result["limitations"]=["This is optical-density/Beer-Lambert processing, not a task-evoked GLM or brain activation claim.",
        "Pathlength factors are researcher-specified. Geometry and scalp coupling do not substitute for reviewed measurement quality.",
        "Motion repair, short-channel/systemic nuisance regression and experimental baseline contrasts require separate explicit recipes.",
        "A missing or nonpositive channel sample splits the jointly observed wavelength data; no hidden filling or absolute-value correction occurs."]
    finish_artifacts(result, prepared)
    return result


def dispatch(modality, x, t, fs, p):
    if modality == "eda": return eda(x, t, fs, p)
    if modality == "eeg": return eeg(x, t, fs, p)
    if modality in {"ecg", "ppg"}: return cardiac(x, t, fs, p, modality)
    if modality == "respiration": return respiration(x, t, fs, p)
    if modality == "emg": return emg(x, t, fs, p)
    raise InputError("Unsupported physiology modality.")


def _run(request):
    require(isinstance(request, dict) and request.get("schema") == "brohn-worker-request/1.0", "Unsupported worker request schema.")
    require(request.get("operation") == "physiology", "This worker only accepts the physiology operation.")
    modality = request.get("modality")
    require(modality in {"eda", "eeg", "ecg", "ppg", "respiration", "emg", "audio", "fnirs"}, "Supported modalities are eda, eeg, ecg, ppg, respiration, emg, audio and fnirs. Other recipes require a separate worker profile.")
    path = Path(request.get("source_path", "")).resolve()
    require(path.is_file() and 0 < path.stat().st_size <= MAX_FILE_BYTES, "Source file is missing, empty or exceeds 512 MiB.")
    metadata = request.get("metadata")
    require(isinstance(metadata, dict), "metadata must be an object with explicit time, channel and unit information.")
    if modality == "audio": return audio_file(request,path,metadata)
    if modality == "fnirs": return fnirs_file(request,path,metadata)
    source_format = request.get("format")
    with warnings.catch_warnings(record=True) as captured:
        warnings.simplefilter("always")
        recordings, source_info = csv_recordings(path, metadata, modality) if source_format in {"csv", "tsv"} else native_eeg(path, metadata, source_format) if modality == "eeg" else (None, None)
        require(recordings is not None, f"{modality} requires CSV input in this worker profile.")
        output = {"schema": "brohn-worker-result/1.0", "modality": modality, "status": "completed",
                  "engine": {"name": "Brohn physiology worker", "version": "1.0.0", "python": platform.python_version(),
                             "packages": versions(["numpy", "scipy"] + (["mne"] if modality == "eeg" else ["neurokit2"] if modality != "emg" else []))},
                  "source": {"sha256": digest_file(path), "bytes": path.stat().st_size, **source_info},
                  "parameters": {}, "features": [], "events": [], "series": [], "recordings": [], "limitations": [], "artifacts": []}
        prepared = prepare_artifacts(request, output)
        bundles = []
        all_events = []
        limitations = {"Outputs describe independent contiguous recording segments, not independent participant samples or inferred condition effects.",
                       "Missing samples and timestamp gaps split processing; no implicit filling or cross-boundary filtering occurs.",
                       "Device-specific motion/contact/clipping qualification and research interpretation remain separate from successful numerical execution."}
        total_missing, total_invalid, total_rows, total_retained = 0, 0, 0, 0
        for recording in recordings:
            fs = recording["fs"]
            p = parameters(modality, request.get("parameters", metadata.get("parameters", {})), fs)
            output["parameters"][recording["id"]] = p
            for channel_index, channel in enumerate(recording["channels"]):
                segments, quality = continuous_segments(recording, channel_index, metadata, modality)
                total_missing += quality["missing_samples"]
                total_invalid += quality["invalid_amplitude_samples"]
                total_rows += len(recording["times"])
                if not segments:
                    output["recordings"].append({"recording_id": recording["id"], "channel": channel, "group": recording["group"], "status": "unavailable",
                        "reason": "No finite, physically admissible signal samples.", **quality})
                for segment_index, (start, end) in enumerate(segments):
                    require(len(output["recordings"]) < MAX_RECORDINGS, "Too many separate channel segments for one worker job.")
                    x = recording["values"][channel_index, start:end]
                    t = recording["times"][start:end]
                    identity = {"recording_id": recording["id"], "segment_id": f"{recording['id']}-segment-{segment_index+1}", "channel": channel, "group": recording["group"]}
                    summary = {**identity, "source_time_origin": recording["source_time_origin"],
                               "source_row_start": recording["source_row_start"] + start, "source_row_end_exclusive": recording["source_row_start"] + end,
                               "start_time_s": float(t[0]), "end_time_s": float(t[-1]), "samples": end-start, "sampling_rate": fs,
                               "unit": recording["unit"], "source_unit": recording["source_unit"], "scale_factor": recording["scale_factor"],
                               "channel_quality": quality, "exact_flatline": bool(len(x) > 0 and np.ptp(x) == 0)}
                    try:
                        bundle = dispatch(modality, x, t, fs, p)
                    except (InputError, ValueError, IndexError, ZeroDivisionError) as error:
                        summary.update(status="unavailable", reason=str(error)[:500])
                        output["recordings"].append(summary)
                        continue
                    summary.update(status="computed", **bundle["support"])
                    output["recordings"].append(summary)
                    total_retained += bundle["support"]["retained_samples"]
                    if prepared is not None:
                        module, writers = prepared
                        module.write_physiology_bundle(writers.series, writers.events, modality, identity, bundle, summary,
                            source_info.get("time_unit", "s"), f"recording-{len(output['recordings'])}")
                    for item in bundle["features"]:
                        if item["unit"] == "source_unit": item["unit"] = recording["unit"]
                        if item["unit"] == "source_unit/s": item["unit"] = recording["unit"] + "/s"
                        output["features"].append({**identity, **item})
                    for event in bundle["events"]:
                        if "sample_index" in event:
                            event["source_sample_index"] = recording["source_row_start"] + start + event["sample_index"]
                            event["segment_sample_index"] = event.pop("sample_index")
                        if "peak_sample" in event:
                            event["source_peak_sample"] = recording["source_row_start"] + start + event["peak_sample"]
                            event["segment_peak_sample"] = event.pop("peak_sample")
                        all_events.append({**identity, **event})
                    bundles.append((identity, bundle["series"]))
                    limitations.update(bundle["limitations"])
                    output["parameters"][recording["id"]] = bundle["parameters"]
        computed = sum(item["status"] == "computed" for item in output["recordings"])
        sample_display_total = sum(len(series["time_s"]) for _, series in bundles)
        if all_events:
            selection = np.unique(np.linspace(0, len(all_events)-1, min(MAX_DISPLAY, len(all_events)), dtype=int))
            output["events"] = [all_events[i] for i in selection]
        # Allocate a bounded display budget across every computed channel segment.
        require(len(bundles) <= MAX_DISPLAY, "The number of computed channel segments exceeds the display-safe job bound.")
        remaining = MAX_DISPLAY
        for index, (identity, series) in enumerate(bundles):
            count = min(len(series["time_s"]), max(1, remaining // (len(bundles)-index)))
            selection = np.unique(np.linspace(0, len(series["time_s"])-1, count, dtype=int))
            remaining -= len(selection)
            for sample in selection:
                item = {**identity}
                for name, array in series.items():
                    item[name] = bool(array[sample]) if name == "retained" else number(array[sample])
                output["series"].append(item)
        output["quality"] = {"usable": computed > 0, "requires_research_review": True, "scientifically_qualified": False,
            "computed_channel_segments": computed, "unavailable_channel_segments": len(output["recordings"])-computed,
            "channel_samples_total": total_rows, "channel_samples_retained": total_retained,
            "missing_channel_samples": total_missing, "invalid_amplitude_channel_samples": total_invalid,
            "retained_fraction": total_retained/total_rows if total_rows else None,
            "event_records_total": len(all_events), "event_records_displayed": len(output["events"]),
            "series_samples_total": sample_display_total, "series_samples_displayed": len(output["series"]),
            "display_sampling": "uniform index selection; all metrics computed on complete retained support",
            "warnings": sorted({str(item.message)[:400] for item in captured})[:100]}
        if not computed: output["status"] = "insufficient_support"
        elif computed != len(output["recordings"]): output["status"] = "partial"
        output["limitations"] = sorted(limitations)
        finish_artifacts(output, prepared)
        return output


def run(request):
    require(isinstance(request, dict) and "_artifact_state" not in request, "Worker request must be an external request object.")
    internal = dict(request); internal["_artifact_state"] = []
    try:
        return _run(internal)
    finally:
        for writers in internal["_artifact_state"]:
            writers.abort()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--request", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    code = 0
    safe_output = args.output.resolve() != args.request.resolve()
    try:
        require(safe_output, "Output cannot replace the request JSON.")
        require(args.request.is_file() and args.request.stat().st_size <= 2*1024*1024, "Request JSON exceeds the supported 2 MiB bound.")
        def unique_object(pairs):
            result = {}
            for key, value in pairs:
                require(key not in result, f"Duplicate JSON object field: {key}")
                result[key] = value
            return result
        request = json.loads(args.request.read_text(encoding="utf-8"), object_pairs_hook=unique_object,
                             parse_constant=lambda text: (_ for _ in ()).throw(InputError("Nonfinite JSON value is not allowed.")))
        require(isinstance(request, dict), "Worker request must be an object.")
        safe_output = args.output.resolve() != Path(request.get("source_path", "")).resolve()
        require(safe_output, "Output cannot replace source data.")
        result = run(request)
    except Exception as error:
        code = 2
        result = {"schema": "brohn-worker-result/1.0", "status": "error", "error": {"type": type(error).__name__, "message": str(error)[:1000]},
                  "quality": {"usable": False}, "features": [], "events": [], "series": [], "artifacts": []}
    if not safe_output:
        print(json.dumps(result), file=sys.stderr)
        return 2
    args.output.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(prefix=".brohn-result-", suffix=".json", dir=args.output.parent)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8", newline="\n") as stream:
            json.dump(result, stream, ensure_ascii=False, allow_nan=False, indent=2)
            stream.write("\n")
        os.replace(temporary, args.output)
    finally:
        if os.path.exists(temporary): os.unlink(temporary)
    print(json.dumps({"status": result["status"], "output": str(args.output.resolve()), "features": len(result["features"])}))
    return code


if __name__ == "__main__":
    raise SystemExit(main())
