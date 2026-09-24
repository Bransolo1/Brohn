"""Download/verify the optional pinned Windows LGPL shared FFmpeg, outside Git."""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import tempfile
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[2]


def digest(path):
    h = hashlib.sha256()
    with path.open("rb") as f:
        for b in iter(lambda: f.read(1024 * 1024), b""): h.update(b)
    return h.hexdigest()


def prepare(destination):
    destination = Path(destination).absolute()
    for ancestor in (destination, *destination.parents):
        if ancestor.exists() and (ancestor.is_symlink() or ancestor.is_junction()):
            raise ValueError("Choose a destination without symlink/junction ancestors.")
    destination = destination.resolve()
    if destination == ROOT or ROOT in destination.parents:
        raise ValueError("Choose an isolated destination outside the repository.")
    if destination.exists():
        raise ValueError("Choose a new destination; an existing runtime is never overwritten.")
    manifest = json.loads((ROOT / "scripts/readiness/facial-runtime.json").read_text(encoding="utf-8"))
    destination.mkdir(parents=True)
    archive = destination / "ffmpeg-shared.zip"
    with urllib.request.urlopen(manifest["url"], timeout=120) as response, archive.open("xb") as output:
        while block := response.read(1024 * 1024):
            output.write(block)
            if output.tell() > manifest["bytes"]:
                raise ValueError("Runtime archive exceeds pinned size; partial destination retained.")
    if archive.stat().st_size != manifest["bytes"] or digest(archive) != manifest["sha256"]:
        raise ValueError("Runtime archive differs from publisher digest; partial destination retained.")
    with zipfile.ZipFile(archive) as z:
        for item in z.infolist():
            if not (destination / item.filename).resolve().is_relative_to(destination) or (item.external_attr >> 16) & 0o170000 == 0o120000:
                raise ValueError("Unsafe runtime archive member; retained without extraction.")
        z.extractall(destination)
    for item in manifest["files"]:
        target = destination / item["path"]
        if target.stat().st_size != item["bytes"] or digest(target) != item["sha256"]:
            raise ValueError("Extracted runtime differs from pinned file manifest.")
    print("Verified optional shared runtime. No system PATH or installed runtime was changed.")
    print("BROHN_FACIAL_FFMPEG_DIR=" + str((destination / manifest["files"][0]["path"]).parent))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--destination", required=True)
    prepare(parser.parse_args().destination)
