"""Synthetic cvxEDA feasibility check; no empirical response attribution claim."""
import argparse
import contextlib
import importlib.metadata
import importlib
import hashlib
import inspect
import io
import json
import os
from pathlib import Path
from unittest.mock import patch

parser = argparse.ArgumentParser()
parser.add_argument("--output", type=Path, required=True)
args = parser.parse_args()
os.environ["MPLBACKEND"] = "Agg"
import numpy as np
import neurokit2 as nk

assert nk.__version__ == "0.2.13"
assert importlib.metadata.version("cvxopt") == "1.3.2"
fs = 25
t = np.arange(40 * fs) / fs
tonic = 1 + 0.001 * t
phasic = np.zeros_like(t)
for onset in [5., 12., 20.]:
    elapsed = np.maximum(t - onset, 0)
    phasic += np.exp(-elapsed / 2) - np.exp(-elapsed / 0.7)
signal = tonic + phasic
settings = dict(tau0=2.0, tau1=0.7, delta_knot=10.0, alpha=8e-4, gamma=1e-2,
                solver=None, reltol=1e-9)
eda_module = importlib.import_module("neurokit2.eda.eda_phasic")
helper = eda_module._eda_phasic_cvxeda
actual_defaults = {key: inspect.signature(helper).parameters[key].default for key in settings}
# Pinned public wrapper drops CVX kwargs. Prove the behavior without another fit;
# never pretend user-selected parameters reached the solver.
with patch.object(eda_module, "_eda_phasic_cvxeda", return_value=(tonic, phasic)) as probe:
    nk.eda_phasic(signal, sampling_rate=fs, method="cvxeda", alpha=1.0, tau0=8.0)
    kwargs_dropped = len(probe.call_args.args) == 2 and probe.call_args.kwargs == {}
with contextlib.redirect_stdout(io.StringIO()):
    result = nk.eda_phasic(signal, sampling_rate=fs, method="cvxeda")
estimated_tonic = result["EDA_Tonic"].to_numpy()
estimated_phasic = result["EDA_Phasic"].to_numpy()
reconstruction_rmse = float(np.sqrt(np.mean((signal - estimated_tonic - estimated_phasic) ** 2)))
tonic_mae = float(np.mean(np.abs(estimated_tonic - tonic)))
phasic_mae = float(np.mean(np.abs(estimated_phasic - phasic)))
# Predeclared tolerances are specific to this noiseless model-compatible signal.
checks = [
    dict(name="pinned effective CVX helper defaults", passed=actual_defaults == settings),
    dict(name="public wrapper ignores CVX kwargs: explicit adoption constraint", passed=kwargs_dropped,
         evidence="upstream_wrapper_behavior_probe"),
    dict(name="aligned finite components", passed=len(result) == len(signal) and bool(np.isfinite(result.to_numpy()).all())),
    dict(name="synthetic reconstruction RMSE < 0.05 source units", passed=reconstruction_rmse < 0.05, observed=reconstruction_rmse),
    dict(name="synthetic tonic MAE < 0.10 source units", passed=tonic_mae < 0.10, observed=tonic_mae),
    dict(name="synthetic phasic MAE < 0.10 source units", passed=phasic_mae < 0.10, observed=phasic_mae),
]
report = dict(schema_version="brohn-method-reference/0.1.0", production_enabled=False,
              evidence="synthetic_model_compatible_recovery", status="reference_checks_passed" if all(x["passed"] for x in checks) else "reference_mismatch",
              packages={p: importlib.metadata.version(p) for p in ["neurokit2", "cvxopt", "numpy"]},
              sampling_rate_hz=fs, samples=len(signal), settings=settings, checks=checks,
              settings_origin="verified_private_helper_defaults_used_by_public_wrapper",
              implementation_sha256=hashlib.sha256(inspect.getsource(eda_module).encode()).hexdigest(),
              api_observation="NeuroKit 0.2.13 eda_phasic ignores cvxEDA kwargs. Only the pinned defaults were fitted; reject configurable CVX options until an adapter is verified.",
              method_source="https://github.com/lciti/cvxEDA",
              limitations=["Known signal matches the fitted response model; this is not external empirical validation.",
                           "No noise, motion, gaps, individual response variability or overlapping event attribution was benchmarked.",
                           "Original cvxEDA and CVXOPT have GPL-family terms; inspect applicable distribution requirements."])
args.output.parent.mkdir(parents=True, exist_ok=True)
args.output.write_text(json.dumps(report, indent=2, allow_nan=False) + "\n", encoding="utf-8")
print(json.dumps(dict(status=report["status"], checks=len(checks), passed=sum(x["passed"] for x in checks), reconstruction_rmse=reconstruction_rmse)))
raise SystemExit(0 if all(x["passed"] for x in checks) else 1)
