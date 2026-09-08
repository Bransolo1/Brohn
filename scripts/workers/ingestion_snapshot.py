"""Fast metadata-only handoff for one completed local upload; never hashes it.

The caller first moves a completed temporary server upload into its own workspace.
This helper holds a Windows read seal while R acquires its own matching handles.
It is not a scientific worker, acquisition adapter or background uploader.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import sys

from publication import WindowsReadSeal, contained, require, write_json, MAX_DOCUMENT


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--request", required=True, type=Path)
    parser.add_argument("--receipt", required=True, type=Path)
    args = parser.parse_args()
    raw = args.request.read_bytes()
    require(len(raw) <= MAX_DOCUMENT, "Upload snapshot request is oversized.")
    request = json.loads(raw)
    require(request.get("schema") == "brohn-ingestion-snapshot-request/1.0", "Unsupported upload snapshot request.")
    root = Path(request["workspace_root"]).resolve(strict=True)
    source = contained(root, Path(request["source_path"]))
    request_path = contained(root, args.request)
    receipt_path = contained(root, args.receipt)
    require(source.parent == request_path.parent == receipt_path.parent and source.name == "original.upload",
            "Upload snapshot paths must belong to the same private incoming request.")
    require(source.parent.parent == root / "incoming" and source.parent.name.startswith("ingestion-"),
            "Upload snapshot is not in its declared incoming directory.")
    require(isinstance(request.get("bytes"), int) and 0 < request["bytes"] <= 512 * 1024**2,
            "Upload snapshot byte count exceeds its bound.")
    request_hash = hashlib.sha256(raw).hexdigest()
    seal = WindowsReadSeal(source)
    try:
        require(seal.identity["bytes"] == request["bytes"], "The completed upload changed size before capture.")
        write_json(receipt_path, {"schema": "brohn-ingestion-snapshot-ready/1.0", "request_sha256": request_hash,
                   "nonce": request["nonce"], "workspace_id": request["workspace_id"],
                   "pid": os.getpid(), "file_identity": seal.identity,
                   "source_hash_status": "not_yet_computed", "metadata_only": True})
        command = sys.stdin.buffer.readline(MAX_DOCUMENT + 1)
        require(0 < len(command) <= MAX_DOCUMENT, "The snapshot owner disconnected before acknowledgement.")
        require(json.loads(command) == {"operation": "release_snapshot", "nonce": request["nonce"],
                                       "request_sha256": request_hash}, "Snapshot release does not match its owner.")
    finally:
        seal.close()


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(str(error)[:2000], file=sys.stderr)
        sys.exit(1)
