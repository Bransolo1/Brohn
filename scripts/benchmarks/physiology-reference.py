"""Executable library/reference checks, not a production participant pipeline.

Run with the isolated methods Python environment. Downloaded public samples stay
in --data-dir (outside the repository); only aggregates and hashes are exported.
"""
import argparse
import hashlib
import importlib.metadata
import json
import os
from pathlib import Path
import platform
import urllib.request
import warnings

parser = argparse.ArgumentParser()
parser.add_argument("--data-dir", type=Path, required=True)
parser.add_argument("--output", type=Path, required=True)
args = parser.parse_args()
args.data_dir.mkdir(parents=True, exist_ok=True)
os.environ["MPLBACKEND"] = "Agg"
os.environ["MPLCONFIGDIR"] = str(args.data_dir / "matplotlib-cache")
os.environ["MNE_DATA"] = str(args.data_dir)

import mne
import neurokit2 as nk
import numpy as np
import pandas as pd

assert nk.__version__ == "0.2.13" and mne.__version__ == "1.12.1"
mne.set_log_level("ERROR")
commit = "ff419d983568ef492eb8d229af643c0ef0100b32"
sources = {
    "bio_eventrelated_100hz.csv": "8b048d02c3580e4e6c2daaa9d44a86e851a6c5a6a978b636cb7a890238ef0dcd",
    "bio_resting_8min_100hz.csv": "da76e3a9a2c3f978810a5c575f587089b3e13e96078c96ef893f28f7fcb58d22",
}
checks, source_records = [], []

def check(name, passed, evidence, **details):
    checks.append(dict(name=name, passed=bool(passed), evidence=evidence, **details))

def number(value):
    return float(value) if np.isfinite(value) else None

def load_sample(name):
    url = f"https://raw.githubusercontent.com/neuropsychology/NeuroKit/{commit}/data/{name}"
    path = args.data_dir / name
    if not path.exists():
        with urllib.request.urlopen(url, timeout=60) as response:
            payload = response.read(3 * 1024 * 1024 + 1)
        if len(payload) > 3 * 1024 * 1024:
            raise ValueError("Reference download exceeds the expected bound")
        if hashlib.sha256(payload).hexdigest() != sources[name]:
            raise ValueError("Reference download hash mismatch")
        path.write_bytes(payload)
    payload = path.read_bytes()
    if hashlib.sha256(payload).hexdigest() != sources[name]:
        raise ValueError("Cached reference bytes changed")
    data = pd.read_csv(path)
    source_records.append(dict(name=name, url=url, sha256=sources[name], rows=len(data),
                               columns=list(data.columns), sampling_rate_hz=100,
                               origin="public_upstream_developer_example"))
    return data

# Analytic signals are authored here independently of MNE's spectral algorithm.
fs = 256
times = np.arange(fs * 20) / fs
amplitudes = np.array([20e-6, 10e-6])
frequencies = np.array([10., 5.])
signal = amplitudes[:, None] * np.sin(2 * np.pi * frequencies[:, None] * times)
psd, bins = mne.time_frequency.psd_array_welch(
    signal, sfreq=fs, fmin=0, fmax=fs / 2, n_fft=256, n_per_seg=256,
    n_overlap=128, window="hann", average="mean", remove_dc=True, verbose=False)
peaks = bins[np.argmax(psd, axis=1)]
power = np.sum(psd, axis=1) * (bins[1] - bins[0])
expected_power = amplitudes ** 2 / 2
check("EEG Welch locates known frequencies", np.array_equal(peaks, frequencies),
      "independent_analytic", expected_hz=frequencies.tolist(), observed_hz=peaks.tolist())
check("EEG PSD preserves known sine variance in V^2", np.allclose(power, expected_power, rtol=1e-10, atol=0),
      "independent_analytic", expected_v2=expected_power.tolist(), observed_v2=power.tolist(), rtol=1e-10)

# Baseline includes t=0; the known response starts later, at t=0.10 seconds.
erp_fs = 100
epochs_data = np.array([np.full((1, 101), baseline * 1e-6) for baseline in [2., 4., 6.]])
epochs_data[:, :, 30:50] += 4e-6
epochs = mne.EpochsArray(epochs_data, mne.create_info(["synthetic_eeg"], erp_fs, "eeg"),
                          tmin=-0.2, baseline=(-0.2, 0), verbose=False)
evoked = epochs.average().data[0]
check("EEG epoch baseline removal", np.allclose(evoked[:21], 0, atol=1e-18), "independent_analytic")
check("EEG evoked mean amplitude", np.allclose(evoked[30:50], 4e-6, atol=1e-18),
      "independent_analytic", expected_v=4e-6, observed_mean_v=float(evoked[30:50].mean()))

# Hand-defined intervals verify units, sample SD and successive-difference math.
rri = np.tile([800., 1000., 1200., 1000.], 100)
hrv = nk.hrv_time({"RRI": rri, "RRI_Time": np.cumsum(rri) / 1000}, sampling_rate=1000, show=False).iloc[0]
hrv_expected = {"HRV_MeanNN": float(rri.mean()), "HRV_SDNN": float(rri.std(ddof=1)),
                "HRV_RMSSD": float(np.sqrt(np.mean(np.diff(rri) ** 2)))}
for key, expected in hrv_expected.items():
    check(key, np.isclose(hrv[key], expected, rtol=1e-10, atol=1e-10), "independent_analytic",
          expected=expected, observed=number(hrv[key]), units="percent" if key.endswith("pNN50") else "ms")

# This implementation divides NN50 by the number of NN intervals, not the
# number of adjacent differences. Keep that convention explicit in the report.
nn50 = int(np.sum(np.abs(np.diff(rri)) > 50))
pnn50_expected = 100 * nn50 / len(rri)
check("pNN50 with explicit total-NN-interval denominator", np.isclose(hrv["HRV_pNN50"], pnn50_expected),
      "explicit_denominator_reference", nn50=nn50, denominator=len(rri), expected=pnn50_expected,
      observed=number(hrv["HRV_pNN50"]), alternative_difference_denominator=100 * nn50 / len(np.diff(rri)))

with warnings.catch_warnings(record=True) as captured:
    warnings.simplefilter("always")
    resting = load_sample("bio_resting_8min_100hz.csv")
    event_data = load_sample("bio_eventrelated_100hz.csv")
    eda_outputs = {}
    for name, data in [("resting", resting), ("event_example", event_data)]:
        # Explicit method components avoid eda_analyze's duration-based auto selection.
        clean = nk.eda_clean(data["EDA"].to_numpy(), sampling_rate=100, method="neurokit")
        components = nk.eda_phasic(clean, sampling_rate=100, method="highpass", cutoff=0.05)
        peak_signals, peak_info = nk.eda_peaks(components["EDA_Phasic"], sampling_rate=100,
                                              method="neurokit", amplitude_min=0.1)
        peak_indices = np.asarray(peak_info["SCR_Peaks"], dtype=int)
        amplitude = np.asarray(peak_info["SCR_Amplitude"], dtype=float)
        check(f"EDA {name}: length and finite decomposition", len(clean) == len(data) and
              np.isfinite(components.to_numpy()).all(), "upstream_example_execution")
        check(f"EDA {name}: peak indices are ordered and bounded", np.all(np.diff(peak_indices) > 0) and
              np.all((peak_indices >= 0) & (peak_indices < len(data))), "upstream_example_execution")
        check(f"EDA {name}: signal markers agree with peak records", int(peak_signals["SCR_Peaks"].sum()) == len(peak_indices),
              "upstream_example_execution")
        eda_outputs[name] = dict(samples=len(data), scr_peaks=len(peak_indices),
                                tonic_mean_source_units=float(components["EDA_Tonic"].mean()),
                                phasic_mean_source_units=float(components["EDA_Phasic"].mean()),
                                scr_amplitude_mean_source_units=number(np.nanmean(amplitude)),
                                scr_amplitude_missing=int(np.isnan(amplitude).sum()))
    # Published upstream table is rounded to six decimal places; not independent labels.
    resting_output = eda_outputs["resting"]
    check("EDA upstream resting example peak count", resting_output["scr_peaks"] == 2,
          "upstream_documented_regression", expected=2, observed=resting_output["scr_peaks"])
    check("EDA upstream resting example mean amplitude", np.isclose(resting_output["scr_amplitude_mean_source_units"], 1.872206, atol=5e-6, rtol=0),
          "upstream_documented_regression", expected_rounded=1.872206,
          observed=resting_output["scr_amplitude_mean_source_units"], atol=5e-6)

    # These demonstrate usable APIs only, with no ground-truth heart/breath labels.
    # Pinned ecg_process hardcodes correct_artifacts=True and forwards kwargs to
    # cleaning only. This count is after that correction, not raw detections.
    ecg_signals, ecg_info = nk.ecg_process(resting["ECG"], sampling_rate=100, method="neurokit")
    rsp_signals, rsp_info = nk.rsp_process(resting["RSP"], sampling_rate=100, method="khodadad2018")
    check("ECG example processing returns aligned series", len(ecg_signals) == len(resting) and len(ecg_info["ECG_R_Peaks"]) > 1,
          "execution_smoke")
    check("Respiration example processing returns aligned series", len(rsp_signals) == len(resting) and len(rsp_info["RSP_Peaks"]) > 1,
          "execution_smoke")
    other_outputs = dict(ecg_r_peaks=len(ecg_info["ECG_R_Peaks"]),
                         ecg_mean_rate_bpm=number(ecg_signals["ECG_Rate"].mean()),
                         respiration_peaks=len(rsp_info["RSP_Peaks"]),
                         respiration_mean_rate_bpm=number(rsp_signals["RSP_Rate"].mean()))
    warning_records = sorted(set(str(w.message) for w in captured))

result = dict(schema_version="brohn-method-reference/0.1.0", production_enabled=False,
              status="reference_checks_passed" if all(x["passed"] for x in checks) else "reference_mismatch",
              python=platform.python_version(),
              packages={p: importlib.metadata.version(p) for p in ["mne", "neurokit2", "numpy", "scipy", "pandas"]},
              sources=source_records, checks=checks, eda=eda_outputs, other_example_outputs=other_outputs,
              warnings=warning_records,
              implementation_observations=[
                  "Initial pNN50 check assumed adjacent-difference denominator (100%). Source inspection resolved the pinned NeuroKit convention: 399 / 400 NN intervals = 99.75%; both are retained above.",
                  "Resting EDA example has two detected peaks but only one finite amplitude; amplitude means must show their own valid denominator."],
              settings=dict(eda_clean="neurokit", eda_phasic="highpass", eda_cutoff_hz=0.05,
                            eda_peaks="neurokit", eda_amplitude_min_relative=0.1,
                            empirical_sampling_rate_hz=100,
                            ecg_process_method="neurokit", ecg_peaks_correct_artifacts=True,
                            ecg_kwargs_scope="cleaning_only_in_pinned_ecg_process",
                            rsp_process_method="khodadad2018"),
              limitations=["Public developer examples do not supply independent event labels.",
                           "Source amplitude units are preserved; calibration units were not independently established.",
                           "No continuous-to-trial EDA attribution or real device timing was evaluated.",
                           "No production Brohn importer, job or participant runner is enabled by this benchmark."])
args.output.parent.mkdir(parents=True, exist_ok=True)
args.output.write_text(json.dumps(result, indent=2, allow_nan=False) + "\n", encoding="utf-8")
print(json.dumps({"status": result["status"], "passed": sum(x["passed"] for x in checks),
                  "checks": len(checks), "output": str(args.output)}, indent=2))
raise SystemExit(0 if all(x["passed"] for x in checks) else 1)
