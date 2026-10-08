"""Complete saved cardiac payload transport; no science or identity inference.

Source-identifiers mode copies every admitted byte exactly. Package aliases are
an explicit unsupported branch until the whole lineage projection is qualified.
The caller owns native read holds, authority, publication and final manifest.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import ntpath
import os
import platform
import re
from pathlib import Path

from cardiac_values import strict_json, json_bytes, value_hash, fields

MIB = 1024 ** 2
HASH = re.compile(r"[a-f0-9]{64}")
NAME = re.compile(r"[a-z0-9][a-z0-9-]*\.(?:json|ndjson|csv)")


def _io_path(value):
    """Filesystem spelling only; never replace a recorded request value."""
    path = Path(value)
    if os.name != "nt":
        return path
    raw = str(path)
    if raw.startswith(("\\\\?\\", "\\\\.\\")):
        return path
    parts = path.parts[1:] if path.anchor else path.parts
    devices = {"con", "prn", "aux", "nul", "conin$", "conout$",
               *(f"{kind}{n}" for kind in ("com", "lpt") for n in "123456789\u00b9\u00b2\u00b3")}
    # Extended syntax must not newly expose names normalized by ordinary Win32.
    if any(p.endswith((".", " ")) or ":" in p or p.split(".")[0].casefold() in devices for p in parts):
        return path
    absolute = ntpath.abspath(raw)
    if absolute.startswith("\\\\"):
        return Path("\\\\?\\UNC\\" + absolute[2:])
    return Path("\\\\?\\" + absolute)


def require(ok, message):
    if not ok:
        raise ValueError(message)


def digest(path):
    h = hashlib.sha256()
    with _io_path(path).open("rb") as stream:
        for chunk in iter(lambda: stream.read(MIB), b""):
            h.update(chunk)
    return h.hexdigest()


def exact_ref(value, kind):
    fields(value, ("kind", "id", "revision", "body_hash", "project_id"), "exact reference")
    require(value["kind"] == kind and isinstance(value["id"], str) and value["id"] and
            type(value["revision"]) is int and 0 < value["revision"] <= 2**53 - 1 and
            isinstance(value["project_id"], str) and value["project_id"] and
            isinstance(value["body_hash"], str) and HASH.fullmatch(value["body_hash"]), "Invalid exact reference")


def project(request, root):
    fields(request, ("schema", "identifier_mode", "source_ref", "prepared_ref", "source_closure_hash",
                     "payloads", "expected_cells", "expected_features"), "cardiac package export")
    require(request["schema"] == "brohn-cardiac-package-projection-request/0.1", "Unsupported cardiac package projection")
    require(request["identifier_mode"] == "source_identifiers",
            "Cardiac package aliases need qualified complete lineage projection; no source-ID fallback")
    exact_ref(request["source_ref"], "report")
    exact_ref(request["prepared_ref"], "cardiac_display")
    require(request["prepared_ref"]["project_id"] == request["source_ref"]["project_id"], "Cross-project cardiac projection")
    require(isinstance(request["source_closure_hash"], str) and HASH.fullmatch(request["source_closure_hash"]), "Invalid source closure hash")
    for name in ("expected_cells", "expected_features"):
        require(type(request[name]) is int and 0 <= request[name] <= 26000, "Invalid expected cardiac inventory")
    payloads = request["payloads"]
    require(isinstance(payloads, list) and 0 < len(payloads) <= 1024, "Missing or oversized complete cardiac payload set")
    names = []
    for p in payloads:
        fields(p, ("path", "hash", "bytes", "media_type", "schema", "role", "object_path"), "held cardiac payload")
        require(isinstance(p["path"], str) and NAME.fullmatch(p["path"]), "Unsafe payload name")
        require(isinstance(p["hash"], str) and HASH.fullmatch(p["hash"]) and type(p["bytes"]) is int and
                0 <= p["bytes"] <= 192*MIB, "Invalid payload byte descriptor")
        require(all(isinstance(p[k], str) and 0 < len(p[k]) <= 4096 for k in ("media_type", "schema", "role", "object_path")), "Invalid payload fields")
        names.append(p["path"])
    require(len(set(names)) == len(names) and sum(p["bytes"] for p in payloads) <= 192*MIB,
            "Duplicate payload or complete cardiac export exceeds 192 MiB")
    root = _io_path(root)
    require(not root.exists(), "Choose a fresh private cardiac export directory")
    # Check every original source before creating any export file.
    for p in payloads:
        source = _io_path(p["object_path"])
        require(source.is_file() and not source.is_symlink() and source.stat().st_size == p["bytes"] and
                digest(source) == p["hash"], "A held cardiac payload changed before export")

    def one(role):
        matches = [p for p in payloads if p["role"] == role]
        require(len(matches) == 1, "Missing unique required cardiac payload: " + role)
        return matches[0]

    evidence = strict_json(_io_path(one("prepared_display_evidence")["object_path"]).read_bytes())
    analysis = strict_json(_io_path(one("complete_original_analysis")["object_path"]).read_bytes())
    closure = strict_json(_io_path(one("complete_original_lineage")["object_path"]).read_bytes())
    one("selected_numerical_page_index")
    require(evidence["schema"] == "brohn-cardiac-display-evidence/0.1" and
            value_hash(evidence["source_ref"]) == value_hash(request["source_ref"]) and
            evidence["closure_hash"] == request["source_closure_hash"] and
            value_hash(closure["source_closure"]) == request["source_closure_hash"], "Changed cardiac source/evidence closure")
    require(analysis["kind"] in ("ecg", "ppg") and len(evidence["cells"]) == len(analysis["recordings"]) == request["expected_cells"] and
            len(analysis["features"]) == request["expected_features"], "Changed complete cardiac cell/feature counts")
    curated = closure["lineage"]["curation"] is not None
    expected = {"complete_original_analysis": 1, "complete_original_lineage": 1,
                "prepared_display_evidence": 1, "selected_numerical_page_index": 1,
                "complete_original_typed_stream": len(analysis["artifacts"]),
                "complete_table_csv": sum(a["tables"] for a in analysis["artifacts"]),
                "complete_joined_markers": sum(c["catalogue"]["source_status"] == "computed" for c in evidence["cells"]),
                "complete_exclusion_review": int(analysis.get("exclusion_review") is not None),
                "complete_original_curation_decisions": int(curated), "complete_curation_crosswalk": int(curated)}
    require(all(p["role"] in expected for p in payloads) and
            all(sum(p["role"] == role for p in payloads) == count for role, count in expected.items()),
            "Incomplete or unexpected cardiac payload roles")
    root.mkdir(parents=True)
    files = []
    for p in payloads:
        source = _io_path(p["object_path"])
        target = root / p["path"]
        written = 0
        h = hashlib.sha256()
        with source.open("rb") as src, target.open("xb") as dst:
            while chunk := src.read(MIB):
                written += len(chunk)
                require(written <= p["bytes"], "Cardiac source grew while copying")
                h.update(chunk)
                dst.write(chunk)
        require(written == p["bytes"] and h.hexdigest() == p["hash"] and digest(target) == p["hash"] and
                source.stat().st_size == p["bytes"] and digest(source) == p["hash"], "Cardiac bytes changed during complete export")
        files.append({k: p[k] for k in ("path", "hash", "bytes", "media_type", "schema", "role")})
    return {"schema": "brohn-cardiac-package-projection-result/0.1", "identifier_mode": "source_identifiers",
            "source_ref": request["source_ref"], "prepared_ref": request["prepared_ref"],
            "source_closure_hash": request["source_closure_hash"], "request_value_hash": value_hash(request),
            "files": files, "coverage": {"complete": True, "cells": request["expected_cells"],
            "features": request["expected_features"], "payloads": len(files), "bytes": sum(p["bytes"] for p in files),
            "scientific_values_changed": False, "recorded_clock_lexemes_changed": False,
            "all_original_payload_bytes_equal": True, "raw_input_bundle_included": False},
            "identifier_notice": "Original source identifiers are retained. This package is not anonymized.",
            "verified_runtime": {"Python": {"implementation": platform.python_implementation(), "version": platform.python_version()}}}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--request", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--artifacts", required=True, type=Path)
    args = parser.parse_args()
    args.request = _io_path(args.request)
    args.output = _io_path(args.output)
    require(args.request.is_file() and not args.request.is_symlink() and args.request.stat().st_size <= 2*MIB,
            "Missing or oversized cardiac projection request")
    require(not args.output.exists(), "Choose a fresh projection receipt")
    try:
        result = project(strict_json(args.request.read_bytes()), args.artifacts)
        result["request_sha256"] = digest(args.request)
    except Exception as exc:
        args.output.write_bytes(json_bytes({"schema": "brohn-cardiac-package-projection-error/0.1", "message": str(exc)}))
        return 1
    args.output.write_bytes(json_bytes(result))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
