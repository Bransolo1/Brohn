"""Source-declared shared-clock review; no clock fitting or scientific scoring.

Reads complete pinned canonical streams using the importer's decimal contract.
Reset/epoch ambiguity is refused, rather than merged by coincident timestamps.
"""
from __future__ import annotations
import argparse
import csv
from decimal import Decimal
import json
import math
from pathlib import Path
import sys
from stream_extract import decimal, digest, require, parse, TIME, MAX_ROWS, MAX_BYTES

MAX_LINE = 8 * 1024**2
MAX_EXPORT = 64 * 1024**2
UNSAFE = {"declared_reset", "timestamp_reversal", "clock_id_change", "duplicate_signal_timestamp", "clock_offset_collection_reversal"}
COLUMNS = ["track_id", "stream_id", "channel_id", "source_sequence", "source_segment", "source_clock_id", "source_timestamp", "timestamp_unit",
           "relative_time_s", "value_json", "value_state", "unit", "origin", "participant_id", "session_id", "condition_id", "exposure_id", "canonical_sha256"]

class Number(str):
    """Retain the canonical source's floating JSON token without binary64 loss."""

def exact_parse(line):
    return json.loads(line, parse_float=Number, parse_constant=lambda x: (_ for _ in ()).throw(ValueError("Nonfinite literal")))

def value_json(value):
    return str(value) if isinstance(value, Number) else json.dumps(value, ensure_ascii=False, allow_nan=False, separators=(",", ":"))

def lines(path):
    with Path(path).open("r", encoding="utf-8", newline="") as source:
        while True:
            line = source.readline(MAX_LINE + 1)
            if not line:
                break
            require(len(line.encode("utf-8")) <= MAX_LINE, "A canonical row exceeds the bounded eight-MiB reader.")
            yield line

def sources(track):
    for name in ("samples", "evidence"):
        ref = track[name]
        p = Path(ref["path"]).resolve()
        require(p.is_file() and p.stat().st_size == ref["bytes"] and p.stat().st_size <= MAX_BYTES and digest(p) == ref["hash"], "Pinned stream source failed its size/SHA-256 check.")
    return Path(track["samples"]["path"]), Path(track["evidence"]["path"])

def review(request):
    require(request.get("schema") == "brohn-linked-review-request/1.0", "Unsupported linked review request.")
    tracks, selection = request["tracks"], request["selection"]
    require(2 <= len(tracks) <= 4 and len({t["id"] for t in tracks}) == len(tracks), "Choose two to four distinct source tracks.")
    clock = tracks[0]["clock"]
    require(clock["kind"] in ("monotonic", "device", "unix") and clock["representation"] == "decimal_string", "This clock representation requires a supported alignment route.")
    require(all(t["clock"] == clock for t in tracks), "Different source clocks require an explicit saved alignment map; close timestamps do not establish synchronization.")
    factor = TIME.get(clock["unit"])
    if factor is None:
        factor = decimal(clock.get("seconds_per_tick"), "Clock tick scale")
    require(factor > 0, "Clock scale must be positive.")
    start, end, cursor = [decimal(selection[k], k) for k in ("start_s", "end_s", "cursor_s")]
    require(start < end and end-start <= Decimal(86400) and start <= cursor <= end, "Choose a positive window of at most one day and a cursor inside it.")
    require(max(abs(start), abs(end)) <= Decimal(1_000_000_000) and float(start) < float(end),
            "Choose a representable display window within one billion relative seconds; exact source timestamps remain unchanged.")
    offset = selection["offset"]
    require(isinstance(offset, int) and not isinstance(offset, bool) and 0 <= offset <= 8_000_000 and offset % 100 == 0, "Choose an exact-value page of 100 rows.")
    output = Path(request["export_path"]).resolve()
    require(output.parent.is_dir() and not output.exists(), "Use a new job-owned CSV destination.")
    prepared, issues, anchor = [], [], None
    for track in tracks:
        source, evidence = sources(track)
        segments = {}
        for line in lines(evidence):
            item = parse(line)
            if item.get("type") == "source_segment":
                require(item["id"] not in segments, "Duplicate retained source segment.")
                segments[item["id"]] = item
                require(len(segments) <= 100000, "Source segment limit exceeded.")
                if UNSAFE.intersection(item["boundary_reasons"]):
                    issues.append({"track_id": track["id"], "sequence": item["first_sequence"], "reason": "Clock reset, reversal or epoch ambiguity needs a retained alignment/epoch map; this stream is not overlaid."})
        require(len(segments) == track["segment_count"], "Full source boundary count changed.")
        if track is tracks[0]:
            for line in lines(source):
                row = parse(line)
                if row["timestamp_state"] == "observed" and row["source_timestamp"] is not None and not row["reconstructed_timestamp"]:
                    anchor = decimal(row["source_timestamp"], "Timeline anchor")
                    break
        prepared.append((track, source, segments))
    require(anchor is not None, "The reference stream has no observed timestamp for a timeline origin.")
    base = {"schema": "brohn-linked-review/1.0", "binding": request["binding"], "selection": selection,
            "clock": clock, "anchor_timestamp": str(anchor), "anchor_unit": clock["unit"],
            "alignment": "source_declared_shared_clock_accuracy_unverified", "interval": "start inclusive, end exclusive", "issues": issues}
    if issues:
        return {**base, "status": "requires_alignment", "tracks": [], "rows": [], "selected_rows": 0, "csv": None}
    result_tracks, table, total_selected = [], [], 0
    source_identity = None
    with output.open("x", encoding="utf-8", newline="") as target:
        writer = csv.DictWriter(target, fieldnames=COLUMNS); writer.writeheader()
        for track, source, segments in prepared:
            count = chosen = missing = unplaced = 0
            buckets, markers, cursor_rows, bounds = {}, [], {"before": None, "after": None}, [None, None]
            previous_segment = None; run = 0; plotted = 0; display_limited = False
            selected_segments = set()
            for line in lines(source):
                row = exact_parse(line); count += 1
                require(count <= MAX_ROWS and row["sequence"] == count and row["stream_id"] == track["source_stream_id"], "Canonical source ordering/identity changed.")
                require(row["clock_id"] == clock["id"] and row["timestamp_unit"] == clock["unit"] and row["segment_id"] in segments, "A row has an undeclared source clock or segment.")
                identity = row["identity"]
                stable = {k: identity.get(k) for k in ("participant_id", "session_id")}
                require(all(isinstance(v, str) and v for v in stable.values()), "Explicit participant and session identities are required for linked review.")
                if source_identity is None:
                    source_identity = stable
                require(stable == source_identity, "Selected streams contain different participant/session identities; do not align them by timestamps.")
                if row["segment_id"] != previous_segment:
                    run += 1; previous_segment = row["segment_id"]
                valid_time = row["timestamp_state"] == "observed" and row["source_timestamp"] is not None and not row["reconstructed_timestamp"]
                if not valid_time:
                    unplaced += 1; run += 1; continue
                x = (decimal(row["source_timestamp"], "Source time")-anchor)*factor
                bounds = [x if bounds[0] is None else min(bounds[0], x), x if bounds[1] is None else max(bounds[1], x)]
                if not start <= x < end:
                    continue
                chosen += 1; selected_segments.add(row["segment_id"])
                value = row["values"][track["channel"]["id"]]; state = row["value_states"][track["channel"]["id"]]
                record = {"track_id": track["id"], "stream_id": track["stream_id"], "channel_id": track["channel"]["id"],
                          "source_sequence": count, "source_segment": row["segment_id"], "source_clock_id": clock["id"],
                          "source_timestamp": row["source_timestamp"], "timestamp_unit": clock["unit"], "relative_time_s": str(x),
                          "value_json": value_json(value), "value_state": state, "unit": track["channel"].get("unit"), "origin": track["origin"],
                          **{k: identity.get(k) for k in ("participant_id", "session_id", "condition_id", "exposure_id")}, "canonical_sha256": track["samples"]["hash"]}
                writer.writerow(record)
                if offset <= total_selected < offset+100:
                    table.append(record)
                total_selected += 1
                require(target.tell() <= MAX_EXPORT, "Window CSV exceeds 64 MiB; choose a narrower time range.")
                if x <= cursor:
                    cursor_rows["before"] = record
                if x >= cursor and cursor_rows["after"] is None:
                    cursor_rows["after"] = record
                if state != "observed" or value is None:
                    missing += 1; run += 1; continue
                if track["kind"] == "markers":
                    if len(markers) < 200:
                        markers.append({"x": float(x), "time_s": str(x), "sequence": count, "label": record["value_json"][:160]})
                    else:
                        display_limited = True
                    continue
                require(track["channel"]["value_type"] in ("float64", "float32", "int64", "int32", "int16", "int8"), "Only scalar numeric signal channels can be plotted.")
                y = Decimal(str(value)); require(y.is_finite(), "Observed numeric source value is not finite.")
                if not math.isfinite(float(y)) or abs(y) > Decimal("1e100"):
                    display_limited = True; run += 1; continue
                point = {"x": float(x), "y": float(y), "sequence": count, "run": run}
                key = (run, int((x-start)/(end-start)*400))
                if key not in buckets:
                    if len(buckets) >= 2000:
                        display_limited = True; continue
                    buckets[key] = [point, point, point, point]
                b = buckets[key]; b[1] = point
                if point["y"] < b[2]["y"]: b[2] = point
                if point["y"] > b[3]["y"]: b[3] = point
                plotted += 1
            require(count == track["sample_count"], "Complete stream sample count changed.")
            # Never present a silently truncated plot. Exact CSV remains complete.
            points = [] if display_limited else sorted({p["sequence"]: p for b in buckets.values() for p in b}.values(), key=lambda p: p["sequence"])
            if display_limited: markers = []
            result_tracks.append({"id": track["id"], "title": track["title"], "channel": track["channel"], "kind": track["kind"], "origin": track["origin"],
                                  "source_rows": count, "selected_rows": chosen, "missing_values": missing, "unplaced_source_rows": unplaced,
                                  "bounds_s": [None if x is None else str(x) for x in bounds], "segments": [segments[s] for s in segments if s in selected_segments],
                                  "points": points, "markers": markers, "cursor": cursor_rows, "display_limited": display_limited,
                                  "display_policy": "First, last, minimum and maximum source points per 1/400-window bin within each continuous source/value run; no cross-gap lines. Full source window in CSV."})
            sources(track)
    return {**base, "status": "available" if total_selected else "empty_window", "identity": source_identity, "tracks": result_tracks,
            "rows": table, "selected_rows": total_selected, "csv": {"hash": digest(output), "bytes": output.stat().st_size, "rows": total_selected, "columns": COLUMNS}}

def main():
    parser = argparse.ArgumentParser(); parser.add_argument("--request", required=True); parser.add_argument("--output", required=True); args = parser.parse_args()
    try:
        request = parse(Path(args.request).read_text(encoding="utf-8")); result = review(request)
        Path(args.output).write_text(json.dumps(result, ensure_ascii=False, allow_nan=False, separators=(",", ":")), encoding="utf-8")
    except Exception as error:
        Path(args.output).write_text(json.dumps({"status": "error", "error": {"message": str(error)}}), encoding="utf-8")
        return 1
    return 0

if __name__ == "__main__":
    sys.exit(main())
