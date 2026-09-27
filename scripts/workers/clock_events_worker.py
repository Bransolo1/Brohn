"""Original marker page CLI; source authority/publication remain R-owned."""
from __future__ import annotations
import argparse
import json
from pathlib import Path

from clock_events import event_page, MAX_OUTPUT_BYTES
from clock_preview_worker import _object, _constant


def execute(request_path, output_path):
    path = Path(request_path)
    if not path.is_file() or path.stat().st_size > 1024 * 1024:
        raise ValueError("Recorded-event request exceeds one MiB or is unavailable.")
    request = json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=_object, parse_constant=_constant)
    if type(request) is not dict or set(request) != {"schema", "track", "query", "offset", "limit"} or request["schema"] != "brohn-clock-event-request/0.1":
        raise ValueError("Use a bounded original recorded-event request.")
    result = event_page(request["track"], request["query"], request["offset"], request["limit"])
    encoded = json.dumps(result, ensure_ascii=True, allow_nan=False, separators=(",", ":")).encode("ascii")
    if len(encoded) > MAX_OUTPUT_BYTES:
        raise ValueError("Recorded-event result exceeds two MiB.")
    with Path(output_path).open("xb") as output:
        output.write(encoded)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--request", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    try:
        execute(args.request, args.output)
    except Exception as error:
        print(json.dumps({"status": "error", "error": {"type": type(error).__name__, "message": str(error)[:700]}}))
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
