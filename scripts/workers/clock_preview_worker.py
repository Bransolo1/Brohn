"""Bounded CLI adapter for reviewed original-source clock previews.

R owns authorization, source guards, job leases and publication. This executable
does not save a map, infer event equivalence or perform scientific analysis.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

from clock_preview import build_preview, MAX_OUTPUT


def _object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("Duplicate request fields are not supported.")
        result[key] = value
    return result


def _constant(value):
    raise ValueError("Non-finite JSON values are not supported.")


def execute(request_path, output_path):
    request_path, output_path = Path(request_path), Path(output_path)
    if not request_path.is_file() or request_path.stat().st_size > 1024 * 1024:
        raise ValueError("Clock preview request exceeds one MiB or is unavailable.")
    request = json.loads(request_path.read_text(encoding="utf-8"),
                         object_pairs_hook=_object, parse_constant=_constant)
    result = build_preview(request)
    encoded = json.dumps(result, ensure_ascii=True, allow_nan=False,
                         separators=(",", ":")).encode("ascii")
    if len(encoded) > MAX_OUTPUT:
        raise ValueError("Clock preview result exceeds one MiB.")
    # A fresh job-owned output is the only successful publication candidate.
    with output_path.open("xb") as target:
        target.write(encoded)
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--request", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    try:
        execute(args.request, args.output)
    except Exception as error:
        # Return one bounded diagnostic; do not dump the source or request.
        print(json.dumps({"status": "error", "error": {"type": type(error).__name__,
              "message": str(error)[:700]}}))
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
