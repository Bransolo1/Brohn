"""Complete saved pupil/source-label traces. No scientific calculation or interpolation.

The R recipe supplies its actual masks and baseline, in bounded exchange chunks.
This adapter checks completeness and types, then uses the common artifact writer.
Its dedicated reader returns an exact bounded window; it never applies the generic
single-retained-mask signal envelope to these differently supported measures.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import sys

import physiology_artifacts as a

PROFILE = "gaze-pupil-source-trace/1.0"
POLICY = "source-labelled-blink-boundaries/1.1"
EXCHANGE = "brohn-gaze-trace-exchange/1.0"
PREVIEW = "brohn-gaze-trace-preview/1.0"
MAX_ROWS = 2_000_000
MAX_POINTS = 5000
MAX_RESULT = 16 * 1024**2


def columns(unit):
    specs = [
        ("source_row", "integer", "index", False, "source_row_one_based"),
        ("time_s", "float64", "s", False, "coordinate"),
        ("analysis_time_ms", "float64", "ms", False, "original_analysis_coordinate"),
        ("source_time_text", "string", None, True, "original_source_text"),
        ("phase", "string", None, False, "source_phase"),
        ("pupil", "float64", unit, True, "source_measure"),
        ("pupil_text", "string", None, True, "original_source_text"),
    ]
    for field in ("source_gaze_valid", "source_pupil_valid", "source_blink", "left_available", "right_available"):
        specs.extend([(field, "boolean", None, True, "original_source_flag"),
                      (field + "_text", "string", None, True, "original_source_text")])
    for field in ("pupil_finite", "pupil_positive", "effective_pupil_valid", "passive"):
        specs.append((field, "boolean", None, False, "recipe_support"))
    for field in ("baseline_member", "exposure_member"):
        specs.append((field, "boolean", None, True, "declared_window_membership"))
    for field in ("following_time_ms", "following_duration_ms", "pupil_interval_duration_ms", "baseline_interval_duration_ms"):
        specs.append((field, "float64", "ms", True, "following_interval_support"))
    for field in ("following_gap", "following_phase_change", "following_invalid_pupil", "pupil_interval_eligible", "baseline_interval_eligible"):
        specs.append((field, "boolean", None, True, "following_interval_support"))
    specs.extend([("pupil_minus_baseline", "float64", unit, True, "processed_measure"),
                  ("correction_status", "string", None, False, "recipe_support")])
    return [a._column(*spec) for spec in specs]


def finite(value):
    return isinstance(value, (float, int)) and not isinstance(value, bool) and math.isfinite(value)


def declaration(record):
    a.require(isinstance(record, dict) and set(record) == {"type", "table_id", "identity", "coordinates", "support", "expected_rows"}
              and record["type"] == "table", "Invalid gaze exchange table declaration.")
    support = record["support"]
    a.require(isinstance(support, dict) and support.get("trace_profile") == PROFILE
              and support.get("blink_boundary_policy") == POLICY, "Unsupported gaze trace or blink boundary policy.")
    a.require(support.get("generic_line_preview") == "forbidden_use_dedicated_gaze_adapter", "A pupil trace requires its dedicated mask-aware adapter.")
    unit = support.get("pupil_unit") or "unavailable"
    a.require(unit in {"mm", "mm2", "pixels", "pixels2", "device_units", "unavailable"}, "Unknown mapped pupil unit.")
    a.require(finite(support.get("time_start_ms")) and finite(support.get("time_end_ms"))
              and 0 <= support["time_start_ms"] < support["time_end_ms"], "Declare the full original table time bounds.")
    initial = support.get("initial_window")
    a.require(isinstance(initial, dict) and set(initial) == {"start_ms", "end_ms", "rows", "scope"}
              and initial["rows"] == min(record["expected_rows"], MAX_POINTS)
              and initial["start_ms"] == support["time_start_ms"]
              and finite(initial["end_ms"]) and initial["start_ms"] < initial["end_ms"] <= support["time_end_ms"]
              and initial["scope"] == ("complete_table" if record["expected_rows"] <= MAX_POINTS else "initial_saved_time_window; full table is longer"),
              "Initial trace window must declare its bounded source-row scope.")
    return a.table_spec(record["table_id"], record["identity"], columns(unit), record["coordinates"], support, record["expected_rows"])


def write(request):
    a.require(request.get("schema") == EXCHANGE and request.get("operation") == "write", "Unsupported gaze trace write request.")
    source = Path(request.get("exchange_path", ""))
    a.require(source.is_file() and not source.is_symlink() and source.stat().st_size <= a.MAX_BYTES, "Invalid or oversized gaze exchange.")
    sha = request.get("exchange_sha256")
    a.require(a.digest_file(source) == sha, "Gaze exchange identity mismatch.")
    expected = request.get("source_rows")
    a.require(isinstance(expected, int) and not isinstance(expected, bool) and 2 <= expected <= MAX_ROWS, "Declare the complete source row denominator.")
    seen = bytearray(expected)
    records = iter(a._read_records(source))
    try:
        header = next(records, None)
        a.require(header == {"type": "header", "schema": EXCHANGE, "source_rows": expected}, "Gaze exchange header mismatch.")
        with a.TableWriter(request["output_directory"], "physiology-series", request["provenance"], preview_limit=0) as writer:
            complete = False
            for record in records:
                a.require(not complete, "Gaze exchange contains trailing records.")
                if record.get("type") == "complete":
                    a.require(record == {"type": "complete", "tables": writer.tables, "rows": expected}
                              and writer.rows == expected and all(seen), "Gaze exchange does not retain every original source row exactly once.")
                    complete = True
                    continue
                d = declaration(record)
                def rows():
                    count = 0
                    last_source = 0
                    last_time = None
                    previous_next = None
                    for part in records:
                        if part.get("type") == "table_end":
                            a.require(part == {"type": "table_end", "table_id": d["table_id"], "rows": count}
                                      and count == d["expected_rows"], "Incomplete gaze exchange table.")
                            return
                        a.require(set(part) == {"type", "table_id", "offset", "rows"} and part["type"] == "rows"
                                  and part["table_id"] == d["table_id"] and part["offset"] == count
                                  and isinstance(part["rows"], list) and 1 <= len(part["rows"]) <= 128, "Invalid or out-of-sequence gaze exchange chunk.")
                        for row in part["rows"]:
                            names = [c["name"] for c in d["columns"]]
                            a.require(isinstance(row, dict) and set(row) == set(names), "Gaze row does not match its complete typed schema.")
                            for c in d["columns"]: a.scalar(row[c["name"]], c)
                            index = row["source_row"]
                            a.require(last_source < index <= expected and not seen[index - 1], "Source row duplicated, reordered or outside the original denominator.")
                            a.require(last_time is None or row["analysis_time_ms"] > last_time, "Gaze table clocks must strictly increase without sorting.")
                            a.require(previous_next is None or previous_next == row["analysis_time_ms"], "Following interval endpoint differs from the next original row.")
                            a.require(row["time_s"] == row["analysis_time_ms"] / 1000, "Seconds coordinate differs from the saved analysis clock.")
                            terminal = count == d["expected_rows"] - 1
                            a.require(count != 0 or row["analysis_time_ms"] == d["support"]["time_start_ms"], "Trace start differs from its original first row.")
                            a.require(not terminal or row["analysis_time_ms"] == d["support"]["time_end_ms"], "Trace end differs from its original terminal row.")
                            a.require(count != d["support"]["initial_window"]["rows"] - 1 or
                                      row["analysis_time_ms"] == d["support"]["initial_window"]["end_ms"], "Initial trace window differs from its actual retained source row.")
                            interval_fields = ("following_time_ms", "following_duration_ms", "following_gap", "following_phase_change", "following_invalid_pupil",
                                               "pupil_interval_eligible", "baseline_interval_eligible", "pupil_interval_duration_ms", "baseline_interval_duration_ms")
                            a.require(all(row[f] is None for f in interval_fields) if terminal else all(row[f] is not None for f in interval_fields),
                                      "Terminal intervals must be null; nonterminal support must be explicit.")
                            if not terminal:
                                a.require(row["following_time_ms"] > row["analysis_time_ms"] and row["following_duration_ms"] == row["following_time_ms"] - row["analysis_time_ms"], "Following interval clock mismatch.")
                            seen[index - 1] = 1
                            last_source, last_time = index, row["analysis_time_ms"]
                            previous_next = row["following_time_ms"]
                            count += 1
                            yield row
                    raise a.ArtifactError("Gaze exchange ended inside a table.")
                writer.write_table(d["table_id"], d["identity"], d["columns"], d["coordinates"], d["support"], rows(), d["expected_rows"])
            a.require(complete and a.digest_file(source) == sha, "Gaze exchange incomplete or changed during reading.")
            manifest = writer.finish()
        verified = a.verify_artifact(manifest, request["output_directory"])
        return {"schema": EXCHANGE, "status": "complete", "artifacts": [manifest], "source_rows": verified["rows"]}
    finally:
        records.close()


def preview(request):
    a.require(request.get("schema") == PREVIEW and request.get("operation") == "preview", "Unsupported gaze trace preview request.")
    manifest = request.get("artifact")
    table_id = request.get("table_id")
    identity = request.get("identity")
    a.require(isinstance(identity, dict) and identity, "Select an exact saved trace identity.")
    start, end = request.get("start_ms"), request.get("end_ms")
    a.require((start is None and end is None) or finite(start) and finite(end) and 0 <= start < end, "Select a finite increasing time range, or the whole saved trace.")
    selected = None
    total = 0
    points = []
    point_bytes = 0
    def table(d):
        nonlocal selected
        if d["table_id"] != table_id: return
        a.require(selected is None and d["identity"] == identity, "Trace identity differs from the exact requested exposure.")
        expected = declaration({k: v for k, v in d.items() if k != "columns"})
        a.require(d["columns"] == expected["columns"], "Saved gaze trace schema differs from its profile.")
        selected = d
    def rows(tid, offset, chunk):
        nonlocal total, points, point_bytes
        if tid != table_id: return
        a.require(selected is not None, "Trace rows have no matching declaration.")
        names = [c["name"] for c in selected["columns"]]
        ti = names.index("analysis_time_ms")
        for i, row in enumerate(chunk):
            if start is not None and not start <= row[ti] <= end: continue
            total += 1
            if total <= MAX_POINTS:
                native = dict(zip(names, row))
                point = {"row_index": offset + i, **native,
                               "exact_record_json": json.dumps(native, ensure_ascii=True, allow_nan=False, separators=(",", ":")),
                               "pupil_decimal": None if native["pupil"] is None else repr(native["pupil"]),
                               "pupil_minus_baseline_decimal": None if native["pupil_minus_baseline"] is None else repr(native["pupil_minus_baseline"]),
                               "analysis_time_ms_decimal": repr(native["analysis_time_ms"])}
                # Reserve the two bounded metadata records and outer envelope.
                # Reject before storing a large original-text/native-JSON copy.
                encoded_bytes = len(json.dumps(point, ensure_ascii=True, allow_nan=False).encode("ascii")) + 2
                a.require(point_bytes + encoded_bytes <= MAX_RESULT - 2*a.MAX_LINE - 65536,
                          "Trace preview byte budget exceeded; narrow the time window. No partial trace is returned.")
                point_bytes += encoded_bytes
                points.append(point)
            elif points:
                points = []  # No partial plot can masquerade as complete.
                point_bytes = 0
    verified = a.verify_artifact(manifest, on_table=table, on_rows=rows)
    a.require(selected is not None, "The requested table is absent from the complete saved artifact.")
    result = {"schema": PREVIEW, "trace_profile": PROFILE, "status": "too_many_rows" if total > MAX_POINTS else "available" if total else "empty",
              "artifact": {k: manifest[k] for k in ("kind", "sha256", "bytes", "schema", "provenance_sha256")},
              "table": selected, "source_provenance": verified["provenance"], "range": {"start_ms": start, "end_ms": end, "boundary": "both endpoints included"},
              "selected_rows": total, "limit": MAX_POINTS, "rows": points,
              "exactness": "exact_record_json and decimal strings retain original binary64 including signed zero; numeric fields are chart conveniences",
              "display_policy": "exact source rows; no interpolation, filtering or reduction; narrow window required above the display limit"}
    a.require(len(json.dumps(result, ensure_ascii=True, allow_nan=False).encode("ascii")) <= MAX_RESULT, "Trace preview exceeds 16 MiB; narrow the range.")
    return result


def catalog(request):
    a.require(request.get("schema") == PREVIEW and request.get("operation") == "catalog", "Unsupported gaze trace catalog request.")
    tables = []
    table_bytes = 0
    def table(d):
        nonlocal table_bytes
        support = d["support"]
        a.require(support.get("trace_profile") == PROFILE, "This artifact is not a complete gaze trace.")
        expected = declaration({k: v for k, v in d.items() if k != "columns"})
        a.require(d["columns"] == expected["columns"], "Trace table schema differs from its profile.")
        entry = {"table_id": d["table_id"], "identity": d["identity"], "rows": d["expected_rows"],
                       "start_ms": support["time_start_ms"], "end_ms": support["time_end_ms"],
                       "initial_window": support["initial_window"], "pupil_unit": support.get("pupil_unit"),
                       "pupil_source": support.get("pupil_source"), "blink_source": support.get("blink_source"),
                       "baseline_status": support["baseline"]["status"]}
        encoded_bytes = len(json.dumps(entry, ensure_ascii=True, allow_nan=False).encode("ascii")) + 2
        a.require(table_bytes + encoded_bytes <= MAX_RESULT - a.MAX_LINE - 65536,
                  "Complete trace catalog byte budget exceeded; split the original recording. No partial catalog is returned.")
        table_bytes += encoded_bytes
        tables.append(entry)
    verified = a.verify_artifact(request.get("artifact"), on_table=table)
    manifest = request["artifact"]
    result = {"schema": PREVIEW, "operation": "catalog", "trace_profile": PROFILE,
              "artifact": {k: manifest[k] for k in ("kind", "sha256", "bytes", "schema", "provenance_sha256")},
              "source_provenance": verified["provenance"], "complete": True, "source_rows": verified["rows"], "tables": tables}
    a.require(len(json.dumps(result, ensure_ascii=True, allow_nan=False).encode("ascii")) <= MAX_RESULT, "Complete trace catalog exceeds 16 MiB.")
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--request", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    output = Path(args.output)
    a.require(not output.exists() and output.parent.is_dir(), "Use a new result path in an existing owned attempt directory.")
    try:
        request_path = Path(args.request)
        a.require(request_path.is_file() and request_path.stat().st_size <= 2 * 1024**2, "Oversized trace request.")
        request = json.loads(request_path.read_text(encoding="utf-8"), object_pairs_hook=a._unique)
        operation = request.get("operation")
        result = write(request) if operation == "write" else catalog(request) if operation == "catalog" else preview(request)
    except (a.ArtifactError, ValueError, KeyError, OSError) as error:
        result = {"status": "failed", "error": {"message": str(error)}}
        with output.open("x", encoding="utf-8") as stream: json.dump(result, stream, ensure_ascii=True, allow_nan=False)
        return 1
    with output.open("x", encoding="utf-8") as stream: json.dump(result, stream, ensure_ascii=True, allow_nan=False)
    return 0


if __name__ == "__main__":
    sys.exit(main())
