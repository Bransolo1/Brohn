"""Reproduce known EDA 1.0 counterexamples, not acceptance of a repaired method.

Usage: python -B tests/eda-flatline-counterexamples.py REPO FRESH_OUT
Run explicitly in the pinned methods environment. Exit 0 means the known
counterexamples were reproduced. Do not count it as scientific readiness.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.metadata
import importlib.util
import json
from pathlib import Path
import platform
import sys
import warnings

sys.dont_write_bytecode = True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("repo", type=Path, metavar="REPO")
    parser.add_argument("fresh_out", type=Path, metavar="FRESH_OUT")
    args = parser.parse_args()
    repo = args.repo.resolve(strict=True)
    out = args.fresh_out.resolve()
    if out.is_relative_to(repo):
        parser.error("FRESH_OUT must be outside REPO.")
    out.mkdir(parents=True, exist_ok=False)
    receipt = {
        "schema": "brohn-eda-flatline-counterexamples/0.1",
        "scope": "Five synthetic arrays through unchanged installed functions; no store, service, native publication or method repair",
        "scientifically_qualified": False,
        "replacement_method_qualified": False,
        "outcome": "incomplete",
        "script_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        "python": platform.python_version(),
        "platform": platform.platform(),
        "checks": [],
        "cases": [],
    }

    def check(condition, label):
        if not condition:
            raise AssertionError(label)
        receipt["checks"].append(label)

    def sha(path):
        return hashlib.sha256(path.read_bytes()).hexdigest()

    try:
        import numpy as np
        import neurokit2 as nk

        receipt["versions"] = {name: importlib.metadata.version(name) for name in ("numpy", "scipy", "neurokit2")}
        check(receipt["python"] == "3.12.10" and receipt["versions"] == {
            "numpy": "2.5.3", "scipy": "1.18.1", "neurokit2": "0.2.13"
        }, "Exact recorded methods runtime; another environment requires its own assessment")
        package = Path(nk.__file__).parent
        source = repo / "scripts/workers/physiology.py"
        files = {"scripts/workers/physiology.py": source}
        for relative in ("eda/eda_clean.py", "eda/eda_phasic.py", "eda/eda_findpeaks.py", "eda/eda_peaks.py", "signal/signal_filter.py", "signal/signal_findpeaks.py"):
            files["neurokit2/" + relative] = package / relative
        receipt["source_hashes"] = {name: sha(path) for name, path in files.items()}
        spec = importlib.util.spec_from_file_location("brohn_original_eda_witness", source)
        original = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(original)
        fs, n = 10, 1200
        parameters = original.parameters("eda", {}, fs)
        check(parameters["recipe"] == "eda-neurokit-highpass/1.0", "Witness targets the saved 1.0 recipe, never silently a replacement")
        receipt["parameters"] = parameters
        cases = [("constant_" + str(level), np.full(n, level, dtype=float), count)
                 for level, count in ((0., None), (.5, 500), (5., 334), (500., 333))]
        dither = np.full(n, 5.)
        dither[::2] = np.nextafter(5., np.inf)
        cases.append(("one_ulp_alternation_at_5", dither, 250))
        for name, x, expected_count in cases:
            input_bytes = x.tobytes()
            row = {"name": name, "samples": n, "sampling_rate": fs,
                   "input_min": float(x.min()), "input_max": float(x.max()),
                   "input_ptp": float(np.ptp(x)), "exact_constant": bool(np.ptp(x) == 0),
                   "input_sha256": hashlib.sha256(input_bytes).hexdigest()}
            receipt["cases"].append(row)
            with warnings.catch_warnings(record=True) as caught:
                warnings.simplefilter("always")
                clean = np.asarray(nk.eda_clean(x, sampling_rate=fs, method="neurokit"))
                components = nk.eda_phasic(clean, sampling_rate=fs, method="highpass", cutoff=.05)
                phasic = np.asarray(components["EDA_Phasic"])
                row.update(clean_ptp=float(np.ptp(clean)),
                           clean_max_absolute_error=float(np.max(np.abs(clean-x))),
                           phasic_min=float(phasic.min()), phasic_max=float(phasic.max()),
                           phasic_ptp=float(np.ptp(phasic)))
                try:
                    _, info = nk.eda_peaks(phasic, sampling_rate=fs, method="neurokit", amplitude_min=.1)
                    row["untrimmed_candidate_count"] = len(info["SCR_Peaks"])
                except Exception as error:
                    row["detector_error"] = {"type": type(error).__name__, "message": str(error)}
                try:
                    result = original.eda(x, np.arange(n)/fs, fs, parameters)
                    row["original_features"] = result["features"]
                except Exception as error:
                    row["original_recipe_error"] = {"type": type(error).__name__, "message": str(error)}
                row["warnings"] = [{"category": item.category.__name__, "message": str(item.message)} for item in caught]
            check(x.tobytes() == input_bytes, name + ": synthetic input unchanged")
            if expected_count is None:
                check(row["exact_constant"] and row["clean_ptp"] == 0 and row["phasic_ptp"] == 0,
                      name + ": numerical stages retain exact zero")
                for key in ("detector_error", "original_recipe_error"):
                    error = row.get(key, {})
                    check(error.get("type") == "ValueError" and "zero-size array" in error.get("message", "") and "maximum" in error.get("message", ""),
                          name + ": known empty-maximum error reproduced in " + key)
            else:
                check("original_recipe_error" not in row, name + ": recipe returned saved features")
                features = {f["name"]: f["value"] for f in row["original_features"]}
                check(features["scr_count"] == expected_count,
                      name + ": recorded 1.0 candidate-count counterexample reproduced")
                if row["exact_constant"]:
                    check(row["clean_ptp"] > 0 and row["phasic_ptp"] > 0,
                          name + ": nonzero numerical variation from exact constant input")
                else:
                    check(row["input_ptp"] == np.spacing(5.), name + ": exactly one-ULP input range; not a real-response witness")
        receipt["source_hashes_after"] = {name: sha(path) for name, path in files.items()}
        check(receipt["source_hashes_after"] == receipt["source_hashes"], "All seven inspected scientific sources unchanged")
        receipt["outcome"] = "known_counterexamples_reproduced"
    except Exception as error:
        receipt["outcome"] = "diagnostic_failed"
        receipt["error"] = {"type": type(error).__name__, "message": str(error)}
    finally:
        (out / "results.json").write_text(json.dumps(receipt, indent=2, ensure_ascii=True, allow_nan=False), encoding="utf-8")
    print(json.dumps({"outcome": receipt["outcome"], "checks": len(receipt["checks"]),
                      "cases": len(receipt["cases"]), "scientifically_qualified": False,
                      "replacement_method_qualified": False}))
    return 0 if receipt["outcome"] == "known_counterexamples_reproduced" else 1


if __name__ == "__main__":
    raise SystemExit(main())
