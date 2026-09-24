"""Read-only local runtime checks; no acquisition, model execution or downloads.

Run with the interpreter being checked. Distribution locks cover every pinned
package; imports exercise the concrete entry points used by Brohn's workers.
"""
from __future__ import annotations

import argparse
import ast
import contextlib
import hashlib
import importlib
import importlib.metadata
import io
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
PROFILES = {
    "methods": ("scripts/benchmarks/requirements-methods.txt",
                ["numpy", "scipy.signal", "pandas", "neurokit2", "mne", "cvxopt", "pywt"]),
    "acquisition": ("scripts/readiness/requirements-acquisition.txt",
                    ["numpy", "scipy", "pandas", "mne", "h5py", "snirf", "mne_nirs", "mne_bids",
                     "mne_connectivity", "pyxdf", "pyarrow", "duckdb", "pylsl", "brainflow.board_shim"]),
    "vision-audio": ("scripts/readiness/requirements-media.txt",
                     ["numpy", "scipy", "cv2", "mediapipe.tasks.python.vision", "librosa", "parselmouth", "soundfile", "onnxruntime"]),
    "facial-au": ("scripts/readiness/requirements-facial-au.txt",
                  ["numpy", "torch", "torchvision", "torchcodec", "safetensors", "xgboost", "feat"]),
    "segmentation": ("scripts/readiness/requirements-segmentation.txt",
                     ["numpy", "cv2", "mediapipe.tasks.python.vision.interactive_segmenter"]),
}


def digest(path):
    value = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


def pins(path):
    result = []
    for line in Path(path).read_text(encoding="utf-8-sig").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        match = re.fullmatch(r"([A-Za-z0-9_.-]+)==([A-Za-z0-9_.+!-]+)", line)
        if not match:
            raise ValueError("Requirements must contain only exact name==version pins.")
        name, version = match.groups()
        if any(re.sub(r"[-_.]+", "-", x["name"]).lower() == re.sub(r"[-_.]+", "-", name).lower() for x in result):
            raise ValueError("Duplicate package in requirements.")
        result.append({"name": name, "expected": version})
    if not result:
        raise ValueError("The profile has no pinned requirements.")
    return result


def package_checks(path):
    result = []
    for item in pins(path):
        try:
            distribution = importlib.metadata.distribution(item["name"])
            actual = distribution.version
            location = Path(distribution.locate_file("")).resolve()
            local = location.is_relative_to(Path(sys.prefix).resolve())
            result.append({**item, "actual": actual, "location": str(location), "in_selected_environment": local,
                           "status": "ready" if actual == item["expected"] and local else "mismatch"})
        except importlib.metadata.PackageNotFoundError:
            result.append({**item, "actual": None, "status": "missing"})
    return result


def import_checks(names, require_profile=False):
    result = []
    # Importing numerical libraries can build transient interpreter caches. Never
    # request streams, enumerate devices, initialize models or enable recording.
    os.environ.setdefault("MPLBACKEND", "Agg")
    os.environ.setdefault("OMP_NUM_THREADS", "1")
    os.environ.setdefault("OPENBLAS_NUM_THREADS", "1")
    for name in names:
        try:
            with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
                module = importlib.import_module(name)
            location = Path(module.__file__).resolve() if getattr(module, "__file__", None) else None
            local = location is not None and location.is_relative_to(Path(sys.prefix).resolve())
            result.append({"name": name, "status": "ready" if not require_profile or local else "foreign_environment",
                           "path": str(location) if location else None, "in_selected_environment": local})
        except Exception as error:
            result.append({"name": name, "status": "failed", "message": str(error)[:1200]})
    return result


def executable_check(name):
    path = shutil.which(name)
    if path is None:
        return {"name": name, "status": "missing", "path": None, "message": "Add the selected executable directory to PATH before launching Brohn."}
    try:
        run = subprocess.run([path, "-version"], capture_output=True, text=True, timeout=15, check=False)
        first = run.stdout.splitlines()[0] if run.stdout.splitlines() else ""
        valid = run.returncode == 0 and first.startswith(name + " version ")
        return {"name": name, "status": "ready" if valid else "failed", "path": str(Path(path).resolve()),
                "version": first[:1000], "sha256": digest(path)}
    except Exception as error:
        return {"name": name, "status": "failed", "path": path, "message": str(error)[:1200]}


def model_check(path, expected, size):
    path = Path(path)
    item = {"filename": path.name, "path": str(path.resolve()), "expected_sha256": expected, "expected_bytes": size}
    if not path.is_file():
        return {**item, "status": "missing"}
    if path.stat().st_size != size:
        return {**item, "status": "mismatch", "actual_bytes": path.stat().st_size}
    actual = digest(path)
    return {**item, "status": "ready" if actual == expected else "mismatch", "actual_sha256": actual, "actual_bytes": size}


def worker_pins(root):
    # Read literal identities without importing a worker or initializing a model.
    tree = ast.parse((root / "scripts/workers/vision.py").read_text(encoding="utf-8-sig"))
    values = {}
    for node in tree.body:
        if isinstance(node, ast.Assign) and len(node.targets) == 1 and isinstance(node.targets[0], ast.Name):
            if node.targets[0].id in ("MODELS", "SEGMENT_SHA"):
                values[node.targets[0].id] = ast.literal_eval(node.value)
    return values


def models(profile, root):
    values = worker_pins(root)
    tooling = (root / "../../work/tooling").resolve()
    if profile == "segmentation":
        record = json.loads((root / "docs/preparation/segmentation-results.json").read_text(encoding="utf-8"))["model"]
        if record["sha256"] != values["SEGMENT_SHA"]:
            raise ValueError("Segmentation manifest and worker model identities disagree.")
        path = os.environ.get("BROHN_SEGMENTATION_MODEL_PATH") or str(tooling / "segmentation-venv/models/magic_touch_v1.tflite")
        return [model_check(path, record["sha256"], record["bytes"])]
    records = json.loads((root / "docs/preparation/media-models.json").read_text(encoding="utf-8"))["models"]
    directory = Path(os.environ.get("BROHN_MEDIA_MODEL_DIR") or tooling / "media-models")
    result = []
    for filename, sha in values["MODELS"].values():
        matches = [x for x in records if x["filename"] == filename and x["sha256"] == sha]
        if len(matches) != 1:
            raise ValueError("Vision manifest and worker model identities disagree.")
        result.append(model_check(directory / filename, sha, matches[0]["bytes"]))
    return result


def check(profile, root=ROOT):
    result = {"schema": "brohn-scientific-runtime-check/1.0", "profile": profile,
              "python": {"executable": str(Path(sys.executable).resolve()), "version": platform.python_version(),
                         "implementation": platform.python_implementation(), "isolated_environment": sys.prefix != sys.base_prefix},
              "packages": [], "imports": [], "models": [], "executables": [], "limitations": [
                  "Readiness checks installed software and pinned assets; it is not a hardware, scientific-method or model-accuracy qualification.",
                  "No acquisition, device discovery, camera, microphone, model inference or network download is requested."]}
    if profile == "portability":
        result["python"]["status"] = "ready" if sys.version_info >= (3, 9) else "mismatch"
        result["imports"] = import_checks(["json", "zipfile", "hashlib", "zlib", "struct", "unicodedata"])
        ast.parse((root / "scripts/portable-design.py").read_text(encoding="utf-8"))
        result["helper_sha256"] = digest(root / "scripts/portable-design.py")
    else:
        requirements, imports = PROFILES[profile]
        result["python"]["status"] = "ready" if sys.version_info[:2] == (3, 12) and sys.prefix != sys.base_prefix and sys.implementation.name == "cpython" else "mismatch"
        result["python"]["expected"] = "CPython 3.12 in an isolated environment; Windows AMD64 is the currently exercised profile."
        result["requirements"] = {"path": requirements, "sha256": digest(root / requirements)}
        result["packages"] = package_checks(root / requirements)
        if profile == "facial-au":
            from readiness.facial_runtime_check import assets, import_environment
            result["models"] = assets(root)
            if os.name != "nt":
                result["python"]["status"] = "mismatch"
            result["python"]["expected"] = "CPython 3.12 in an isolated Windows environment."
            if all(item["status"] == "ready" for item in result["models"]):
                with import_environment():
                    result["imports"] = import_checks(imports, require_profile=True)
            else:
                result["imports"] = [{"name": name, "status": "not_checked", "message": "Restore the pinned assets before loading the optional native libraries."} for name in imports]
        else:
            result["imports"] = import_checks(imports, require_profile=True)
        if profile in ("vision-audio", "segmentation"):
            result["models"] = models(profile, root)
        if profile == "vision-audio":
            result["executables"] = [executable_check("ffprobe"), executable_check("ffmpeg")]
        try:
            pip = subprocess.run([sys.executable, "-B", "-m", "pip", "check"], capture_output=True, text=True, timeout=30, check=False)
            result["dependency_consistency"] = {"status": "ready" if pip.returncode == 0 else "failed", "message": (pip.stdout + pip.stderr).strip()[:4000]}
        except Exception as error:
            result["dependency_consistency"] = {"status": "failed", "message": str(error)[:1200]}
    all_checks = [result["python"]] + result["packages"] + result["imports"] + result["models"] + result["executables"]
    if "dependency_consistency" in result:
        all_checks.append(result["dependency_consistency"])
    result["status"] = "ready" if all(x["status"] == "ready" for x in all_checks) else "not_ready"
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--profile", choices=["portability", *PROFILES], required=True)
    parser.add_argument("--root", type=Path, default=ROOT)
    args = parser.parse_args()
    try:
        result = check(args.profile, args.root.resolve())
    except Exception as error:
        result = {"schema": "brohn-scientific-runtime-check/1.0", "profile": args.profile, "status": "not_ready", "message": str(error)[:2000]}
    print(json.dumps(result, ensure_ascii=True, allow_nan=False))
    return 0 if result["status"] == "ready" else 1


if __name__ == "__main__":
    raise SystemExit(main())
