"""Explicit optional download of pinned modular facial models, outside Git.

No recording, device access, inference, implicit upgrade or unpinned fallback.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import tempfile
import urllib.request

ROOT = Path(__file__).resolve().parents[2]


def digest(path):
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def prepare(destination):
    destination = Path(destination).resolve()
    if destination == ROOT or ROOT in destination.parents:
        raise ValueError("Choose a model destination outside the repository.")
    for ancestor in (destination, *destination.parents):
        if ancestor.exists() and (ancestor.is_symlink() or ancestor.is_junction()):
            raise ValueError("Choose a destination without symlink/junction ancestors.")
    manifest = json.loads((ROOT / "scripts/readiness/facial-models.json").read_text(encoding="utf-8"))
    destination.mkdir(parents=True, exist_ok=True)
    for item in manifest["files"]:
        target = destination / item["relative_path"]
        target.parent.mkdir(parents=True, exist_ok=True)
        if target.exists():
            if target.stat().st_size != item["bytes"] or digest(target) != item["sha256"]:
                raise ValueError(f"Existing model differs: {item['relative_path']}; retained unchanged.")
        else:
            # Short temporary names avoid Windows MAX_PATH expansion.
            with tempfile.NamedTemporaryFile(dir=target.parent, suffix=".partial", delete=False) as f:
                temp = Path(f.name)
                with urllib.request.urlopen(item["url"], timeout=120) as response:
                    while block := response.read(1024 * 1024):
                        f.write(block)
                        if f.tell() > item["bytes"]:
                            raise ValueError("Download exceeds pinned model size; partial retained.")
            if temp.stat().st_size != item["bytes"] or digest(temp) != item["sha256"]:
                raise ValueError("Download differs from pinned model bytes; partial retained.")
            temp.rename(target)
        print(f"Verified {item['relative_path']} ({item['bytes']} bytes)", flush=True)
    (destination / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print("Prepared selected MIT-declared modular assets only. No inference ran.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--destination", required=True)
    prepare(parser.parse_args().destination)
