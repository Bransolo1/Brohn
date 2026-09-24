"""Original analytic audio fixtures and independent SciPy/numeric expectations."""
import copy
import csv
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile

import numpy as np
from scipy.signal import periodogram
import soundfile as sf

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("audio_review", ROOT / "scripts/workers/audio_review.py")
worker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(worker)
folder = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path(tempfile.mkdtemp(prefix="brohn-audio-review-"))
folder.mkdir(parents=True, exist_ok=False) if not folder.exists() else None
require_empty = not any(folder.iterdir())
assert require_empty, "Use a new empty external evidence directory."
checks, attempts = [], 0


def check(name, condition):
    if not condition:
        (folder/"failure.json").write_text(json.dumps({"failed_check": name, "completed_checks": checks,
            "worker_sha256": worker.sha(ROOT/"scripts/workers/audio_review.py")}, indent=2), encoding="utf-8")
    assert condition, name
    checks.append(name)
    print("PASS", name, flush=True)


def prepared(values, rate=8000, subtype="FLOAT", suffix="wav"):
    global attempts
    attempts += 1
    source = folder / f"original-{attempts}.{suffix}"
    sf.write(source, values, rate, subtype=subtype)
    info = sf.info(source)
    return {"schema": "brohn-audio-review-request/1.0", "profile": worker.PROFILE,
            "binding": {"report_id": f"original-report-{attempts}", "origin": "sample"},
            "source_path": str(source), "source_hash": worker.sha(source),
            "header": {"frames": info.frames, "sampling_rate": info.samplerate, "channels": info.channels},
            "selection": {"channel_index": 0, "start_s": "0", "end_s": format(len(values) / rate, ".9f"),
                          "frame_length_samples": 200, "frame_hop_samples": 80},
            "output_directory": str(folder / f"result-{attempts}")}


def run(request):
    return worker.review(copy.deepcopy(request))


def rejects(request):
    try:
        run(request)
    except (ValueError, RuntimeError, FloatingPointError, FileExistsError):
        return True
    return False


def rows(request, name):
    with (Path(request["output_directory"]) / name).open(encoding="utf-8", newline="") as source:
        return list(csv.DictReader(source))


# Integer PCM decoding is checked against its exact integer full-scale divisor.
native = np.column_stack((np.arange(-1000, 1000, dtype=np.int16), np.full(2000, 8192, dtype=np.int16)))
request = prepared(native, subtype="PCM_16")
request["selection"]["channel_index"] = 1
original_hash = request["source_hash"]
result = run(request)
sample_rows = rows(request, "audio-samples.csv")
check("Explicit second channel preserves all 2000 PCM samples as0.25FS without mixing", len(sample_rows) == 2000 and all(float(r["amplitude_fs"]) == .25 and r["channel_index"] == "1" for r in sample_rows))
check("Exact sample indices and time remain tied to original source", [int(r["source_sample_index"]) for r in sample_rows] == list(range(2000)) and float(sample_rows[-1]["time_s"]) == 1999/8000)
check("DC and Hann sidelobe powers obey the independent constant-signal oracle", abs(result["spectrogram"][0]["cells"][0]["mean_power_fs2_per_hz"] - .00078125) < 1e-14)
check("Original audio remains byte-identical and output manifests verify", worker.sha(request["source_path"]) == original_hash and all(worker.sha(Path(request["output_directory"]) / a["filename"]) == a["hash"] for a in result["artifacts"]))

# Unequal channels and long source exceed waveform/time display point counts.
times = np.arange(128000) / 8000
values = np.column_stack((.5 * np.sin(2*np.pi*1000*times), .125 * np.cos(2*np.pi*2000*times))).astype(np.float32)
request = prepared(values)
result = run(request)
sample_rows = rows(request, "audio-samples.csv")
spectral_rows = rows(request, "audio-spectrum.csv")
check("Long waveform envelopes cover every native sample once", len(result["waveform"]) == 1000 and sum(b["samples"] for b in result["waveform"]) == 128000 and result["waveform"][0]["first_sample"] == 0 and result["waveform"][-1]["stop_sample"] == 128000)
check("Complete CSV includes all128000 samples beyond the visual envelopes", len(sample_rows) == 128000 and all(float(r["amplitude_fs"]) == float(values[i, 0]) for i, r in enumerate(sample_rows)))
frame, hop = 200, 80
count = 1 + (len(values) - frame) // hop
check("Spectrum exports every unaggregated full-frame frequency cell", len(spectral_rows) == count*101 and result["support"]["spectral_cells"] == count*101 and result["support"]["trailing_samples_without_full_spectral_frame"] == 40)
first_power = np.array([float(r["power_fs2_per_hz"]) for r in spectral_rows[:101]])
frequency, oracle = periodogram(values[:frame, 0].astype(float), fs=8000, window="hann", detrend=False, scaling="density")
check("Every first-frame density agrees with independently invoked SciPy periodogram", np.allclose(first_power, oracle, rtol=1e-12, atol=1e-25))
check("Sinusoidal peak and integrated energy have analytic frequency and amplitude", frequency[np.argmax(first_power)] == 1000 and abs(sum(first_power)*40 - .125) < 1e-8)
all_power = np.array([float(r["power_fs2_per_hz"]) for r in spectral_rows]).reshape(count, 101)
check("Heatmap bins cover every native spectral cell exactly once", sum(c["source_cells"] for t in result["spectrogram"] for c in t["cells"]) == all_power.size)
check("Every heatmap aggregate equals complete exported native cell mean", all(np.isclose(c["mean_power_fs2_per_hz"], all_power[t["first_frame"]:t["stop_frame"], c["first_bin"]:c["stop_bin"]].mean(), rtol=1e-14, atol=0) for t in result["spectrogram"] for c in t["cells"]))
check("Display time bins touch without overlapping FFT-window borders", all(a["plot_right_s"] == b["plot_left_s"] for a,b in zip(result["spectrogram"], result["spectrogram"][1:])))

for n in (199, 200):
    values = np.cos(np.pi * np.arange(2000)).astype(np.float32)
    request = prepared(values)
    request["selection"]["frame_length_samples"] = n
    result = run(request)
    spectral_rows = rows(request, "audio-spectrum.csv")[:n//2+1]
    frequency, oracle = periodogram(values[:n].astype(float), fs=8000, window="hann", detrend=False, scaling="density")
    # Two independent floating-point Hann/FFT implementations differ at roundoff
    # in extremely small sidelobes; use a density-scale absolute roundoff bound.
    check(f"Odd/even frame{n} preserves one-sided edge-bin scaling", np.allclose([float(r["power_fs2_per_hz"]) for r in spectral_rows], oracle, rtol=1e-12, atol=10*np.finfo(float).eps*max(oracle)))

request = prepared(np.zeros(2000, dtype=np.float32))
result = run(request)
check("Silence remains real zero energy with valid spectral cells", result["support"]["exact_silence"] and all(c["mean_power_fs2_per_hz"] == 0 for t in result["spectrogram"] for c in t["cells"]))
request = prepared(np.arange(2000, dtype=np.float32)/2000)
request["selection"].update(start_s="0.0001250000000000001", end_s="0.0005")
result = run(request)
sample_rows = rows(request, "audio-samples.csv")
check("Exact decimal half-open boundary retains indices2and3 only", [int(r["source_sample_index"]) for r in sample_rows] == [2,3])
check("Short selection retains samples but no invented zero-padded spectrum", result["support"]["spectral_frames"] == 0 and not result["spectrogram"] and len(rows(request, "audio-spectrum.csv")) == 0)
request = prepared(np.full(2000, 1.25, dtype=np.float32))
result = run(request)
check("Over-full-scale float samples remain original and visibly counted", result["support"]["full_scale_or_exceeding_samples"] == 2000 and result["waveform"][0]["maximum_fs"] == 1.25)

base = prepared(np.zeros(2000, dtype=np.float32))
for name, mutation in [
    ("Wrong source hash", lambda r: r.update(source_hash="0"*64)),
    ("Wrong source frame declaration", lambda r: r["header"].update(frames=2001)),
    ("Wrong sample-rate declaration", lambda r: r["header"].update(sampling_rate=16000)),
    ("Boolean header integer", lambda r: r["header"].update(channels=True)),
    ("Foreign channel", lambda r: r["selection"].update(channel_index=1)),
    ("Negative selection", lambda r: r["selection"].update(start_s="-1")),
    ("Empty selection", lambda r: r["selection"].update(end_s="0")),
    ("Beyond-source selection", lambda r: r["selection"].update(end_s="1")),
    ("Unsupported hop", lambda r: r["selection"].update(frame_hop_samples=201)),
    ("Output alongside original source", lambda r: r.update(output_directory=str(folder))),
]:
    changed = copy.deepcopy(base); mutation(changed)
    check(name+" is refused", rejects(changed))
nonfinite = prepared(np.array([np.nan]*2000, dtype=np.float32))
check("Nonfinite source samples are refused rather than filled", rejects(nonfinite))
check("Repeated output request cannot overwrite a prior review", rejects(request))

small_request = prepared(np.zeros(2000, dtype=np.float32))
old = worker.MAX_WINDOW_SAMPLES
worker.MAX_WINDOW_SAMPLES = 100
check("Decoded window bound rejects before any export is written", rejects(small_request) and not Path(small_request["output_directory"]).exists())
worker.MAX_WINDOW_SAMPLES = old
old = worker.MAX_SPECTRAL_CELLS
worker.MAX_SPECTRAL_CELLS = 100
check("Native spectral-cell bound rejects before allocating output", rejects(small_request) and not Path(small_request["output_directory"]).exists())
worker.MAX_SPECTRAL_CELLS = old

cli = prepared(np.zeros(2000, dtype=np.float32))
request_file, output_file = folder/"request.json", folder/"result.json"
request_file.write_text(json.dumps(cli), encoding="utf-8")
child = subprocess.run([sys.executable, str(ROOT/"scripts/workers/audio_review.py"), "--request", str(request_file), "--output", str(output_file)], capture_output=True, text=True)
check("Actual command-line worker returns the same declared source and finite result", child.returncode == 0 and json.loads(output_file.read_text())["source_hash"] == cli["source_hash"])
request_file.write_text('{"schema":"first","schema":"second"}', encoding="utf-8")
child = subprocess.run([sys.executable, str(ROOT/"scripts/workers/audio_review.py"), "--request", str(request_file), "--output", str(output_file)], capture_output=True, text=True)
check("CLI rejects duplicate JSON fields with a structured error", child.returncode == 1 and "Duplicate" in json.loads(output_file.read_text())["error"]["message"])
receipt = {"passed": True, "checks": checks, "origin": "original_analytic_audio_not_participant_speech",
           "worker_sha256": worker.sha(ROOT/"scripts/workers/audio_review.py"), "scope": "Independent source/DFT/unit/export/bounds checks; no saved R publication or researcher browser claim."}
(folder/"results.json").write_text(json.dumps(receipt, indent=2), encoding="utf-8")
print(json.dumps({"checks": len(checks), "folder": str(folder)}))
