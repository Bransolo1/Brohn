"""Read-only pin checks and scoped DLL imports; never instantiate a detector."""
from __future__ import annotations

from contextlib import contextmanager
import hashlib
import importlib.metadata
import json
import os
from pathlib import Path


def digest(path):
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


def checked_file(base, relative, expected, size=None):
    base = Path(base).resolve()
    target = (base / relative).resolve()
    result = {"path": str(target), "expected_sha256": expected}
    if not target.is_relative_to(base):
        return {**result, "status": "mismatch", "message": "Asset escapes its declared directory."}
    if not target.is_file():
        return {**result, "status": "missing"}
    actual_size = target.stat().st_size
    if size is not None and actual_size != size:
        return {**result, "status": "mismatch", "actual_bytes": actual_size, "expected_bytes": size}
    actual = digest(target)
    return {**result, "status": "ready" if actual == expected else "mismatch",
            "actual_sha256": actual, "actual_bytes": actual_size}


def assets(root):
    root = Path(root)
    models = json.loads((root / "scripts/readiness/facial-models.json").read_text(encoding="utf-8"))
    runtime = json.loads((root / "scripts/readiness/facial-runtime.json").read_text(encoding="utf-8"))
    result = []
    for variable, manifest in (("BROHN_FACIAL_MODEL_DIR", models), ("BROHN_FACIAL_FFMPEG_DIR", runtime)):
        directory = os.environ.get(variable)
        if not directory or not Path(directory).is_dir():
            result.append({"name": variable, "status": "missing", "message": "Configure the explicit installed asset directory."})
            continue
        result.extend({"group": variable, **checked_file(directory, item["relative_path"], item["sha256"], item["bytes"])}
                      for item in manifest["files"])
    try:
        package = Path(importlib.metadata.distribution("py-feat").locate_file(""))
        result.extend({"group": "pinned_provider_source", **checked_file(package, item["path"], item["sha256"])}
                      for item in runtime["package_sources"])
    except importlib.metadata.PackageNotFoundError:
        result.append({"name": "py-feat source", "status": "missing"})
    return result


@contextmanager
def import_environment():
    """Restore even when imports fail. No persistent PATH or model cache changes."""
    if os.name != "nt":
        raise RuntimeError("The optional facial profile is currently qualified on Windows only.")
    directory = Path(os.environ["BROHN_FACIAL_FFMPEG_DIR"]).resolve()
    values = {"PATH": str(directory) + os.pathsep + os.environ.get("PATH", ""),
              "HF_HUB_OFFLINE": "1", "HF_HUB_DISABLE_TELEMETRY": "1",
              "MPLBACKEND": "Agg", "OMP_NUM_THREADS": "1", "OPENBLAS_NUM_THREADS": "1"}
    previous = {key: os.environ.get(key) for key in values}
    handle = None
    try:
        os.environ.update(values)
        handle = os.add_dll_directory(str(directory))
        yield
    finally:
        if handle is not None:
            handle.close()
        for key, value in previous.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value
