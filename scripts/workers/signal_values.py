"""Exact typed processed rows and streaming CSV; no plot or scientific arithmetic."""
from __future__ import annotations

import argparse
import copy
import csv
import hashlib
import importlib.util
import io
import json
import math
import os
from pathlib import Path
import re
import sys
import tempfile

_spec = importlib.util.spec_from_file_location("brohn_values_preview", Path(__file__).with_name("signal_preview.py"))
preview = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(preview)
artifacts = preview.artifacts
require = artifacts.require
InputError = artifacts.ArtifactError
MAX_PAGE_BYTES = 8 * 1024**2
MAX_RESULT_BYTES = 16 * 1024**2
MAX_EXPORT_BYTES = 2 * 1024**3
SCHEMA = "brohn-signal-values/1.0"
BINDING = {"report_id", "report_revision", "report_hash", "project_id", "catalog_id", "catalog_revision", "catalog_hash", "selection_hash"}


def encode(value):
    return json.dumps(value, ensure_ascii=True, allow_nan=False, separators=(",", ":"))


def same(left, right):
    # Booleans must never compare equal to numeric source values.
    if isinstance(left, bool) or isinstance(right, bool):
        return type(left) is type(right) and left == right
    if isinstance(left, dict) and isinstance(right, dict):
        return set(left) == set(right) and all(same(left[k], right[k]) for k in left)
    if isinstance(left, list) and isinstance(right, list):
        return len(left) == len(right) and all(same(a, b) for a, b in zip(left, right))
    if preview.finite(left) and preview.finite(right):
        return left == right
    return type(left) is type(right) and left == right


def decimal(value, kind):
    if value is None:
        return ""
    if kind == "float64":
        return repr(float(value))  # shortest correctly round-tripping binary64, including -0.0
    if kind == "integer":
        return str(value)
    if kind == "boolean":
        return "true" if value else "false"
    return value


def spreadsheet_text(value):
    value = str(value)
    return "'" + value if re.match(r"^[=+\-@\t\r\n]|^\s+[=+\-@]", value) else value


def blank_stats():
    return {**preview.blank_stats(), "unknown_retention_rows": 0, "retained_rows": 0, "undeclared_retention_rows": 0}


def count(stats, point, retention):
    preview.count(stats, point)
    # The plot's eligibility boolean deliberately collapses absent permission to
    # retain. Exact rows distinguish explicit false, unknown and no declaration.
    if retention == "unknown":
        stats["excluded_retention_rows"] -= 1
        stats["unknown_retention_rows"] += 1
    elif retention == "retained":
        stats["retained_rows"] += 1
    elif retention == "not_declared":
        stats["undeclared_retention_rows"] += 1


def validate(request):
    require(isinstance(request, dict) and request.get("schema") == "brohn-signal-values-request/1.0" and
            request.get("operation") in {"signal_values_page", "signal_values_export"}, "Unsupported exact-value request.")
    require(set(request) == {"schema", "operation", "artifact", "verification_receipt", "binding", "table", "selection"} |
            ({"page"} if request["operation"] == "signal_values_page" else {"export_path"}), "Exact-value request contains unknown or missing fields.")
    binding = request["binding"]
    require(isinstance(binding, dict) and set(binding) == BINDING, "Pin the exact report, catalog and selection identities.")
    for k in BINDING - {"report_revision", "catalog_revision"}:
        require(artifacts.text(binding[k], 160), "Source binding fields must be exact nonempty strings.")
    for k in ("report_hash", "catalog_hash", "selection_hash"):
        require(artifacts.HEX.fullmatch(binding[k]), "Source binding needs exact SHA-256 values.")
    for k in ("report_revision", "catalog_revision"):
        require(preview.integer(binding[k], 1, 2**53-1), "Source revisions must be exact positive integers.")
    s = request["selection"]
    require(isinstance(s, dict) and set(s) == {"table_id", "recording_id", "channel", "value_column", "range", "row_policy"}, "Select one exact table, measure, coordinate range and source-row policy.")
    require(s["row_policy"] == "all_source_rows", "Exact values retain missing and analysis-excluded source rows.")
    require(all(artifacts.text(s[k], 500) for k in ("table_id", "recording_id", "channel", "value_column")), "Select explicit table, recording, channel and numeric measure.")
    bounds = s["range"]
    require(bounds is None or isinstance(bounds, list) and len(bounds) == 2 and all(preview.finite(v) for v in bounds) and bounds[0] <= bounds[1], "Use an inclusive finite range or the complete source range.")
    table = request["table"]
    require(isinstance(table, dict) and table.get("table_id") == s["table_id"] and
            {"identity", "coordinates", "coordinate_column", "value_columns", "rows"} <= set(table), "Choose a retained catalog table.")
    if request["operation"] == "signal_values_page":
        page = request["page"]
        require(isinstance(page, dict) and set(page) == {"offset", "limit"} and preview.integer(page["offset"], 0, artifacts.MAX_ROWS) and
                type(page["limit"]) is int and page["limit"] in {25, 50, 100}, "Choose a selected-row offset and 25, 50 or 100 rows.")
    return preview.bind_receipt(request)


def row_record(table, row, index, selected_index, measure):
    columns = table["columns"]
    native = {c["name"]: artifacts.scalar(v, c) for c, v in zip(columns, row)}
    coord = preview.coordinate(table)
    value_col = next(c for c in columns if c["name"] == measure)
    x, y = native[coord["name"]], native[measure]
    retained = native.get("retained") if "retained" in native else None
    if "retained" in native:
        c = next(c for c in columns if c["name"] == "retained")
        require(c["type"] == "boolean" and c["role"] == "support", "Retained status must be the explicitly typed source support column.")
    return {"table_row_index": index, "selected_row_index": selected_index,
            "source_sample_index": native.get("source_sample_index"),
            "coordinate_text": decimal(x, coord["type"]), "coordinate_is_null": x is None,
            "value_text": decimal(y, value_col["type"]), "value_is_null": y is None,
            "retention": "not_declared" if "retained" not in native else "retained" if retained is True else "excluded" if retained is False else "unknown",
            "plot_eligible": preview.finite(x) and preview.finite(y) and ("retained" not in native or retained is True),
            "support": {c["name"]: native[c["name"]] for c in columns if c["role"] in {"support", "label", "index"}},
            "exact_record_json": encode(native)}


CSV_COLUMNS = ["report_id", "report_revision", "report_sha256", "catalog_sha256", "artifact_sha256", "selection_sha256",
               "table_id", "recording_id", "channel", "selected_row_index", "table_row_index", "source_sample_index",
               "axis", "coordinate_name", "coordinate_type", "coordinate_unit", "coordinate", "coordinate_is_null",
               "measure_name", "measure_type", "measure_unit", "value", "value_is_null", "retention", "plot_eligible",
               "source_time_origin", "source_time_unit", "coordinate_reference", "identity_json", "coordinates_json", "support_json", "exact_record_json"]


def csv_row(request, table, row):
    b, s = request["binding"], request["selection"]
    coord = preview.coordinate(table)
    value = next(c for c in table["columns"] if c["name"] == s["value_column"])
    v = {"report_id": b["report_id"], "report_revision": str(b["report_revision"]), "report_sha256": b["report_hash"],
         "catalog_sha256": b["catalog_hash"], "artifact_sha256": request["artifact"]["sha256"], "selection_sha256": b["selection_hash"],
         "table_id": s["table_id"], "recording_id": s["recording_id"], "channel": s["channel"],
         "selected_row_index": str(row["selected_row_index"]), "table_row_index": str(row["table_row_index"]),
         "source_sample_index": "" if row["source_sample_index"] is None else str(row["source_sample_index"]),
         "axis": table["coordinates"]["axis"], "coordinate_name": coord["name"], "coordinate_type": coord["type"], "coordinate_unit": coord["unit"],
         "coordinate": row["coordinate_text"], "coordinate_is_null": decimal(row["coordinate_is_null"], "boolean"),
         "measure_name": value["name"], "measure_type": value["type"], "measure_unit": value["unit"], "value": row["value_text"],
         "value_is_null": decimal(row["value_is_null"], "boolean"), "retention": row["retention"], "plot_eligible": decimal(row["plot_eligible"], "boolean"),
         "source_time_origin": table["coordinates"]["source_time_origin"] or "", "source_time_unit": table["coordinates"]["source_time_unit"] or "",
         "coordinate_reference": table["coordinates"]["reference"], "identity_json": encode(table["identity"]),
         "coordinates_json": encode(table["coordinates"]),
         "support_json": encode(row["support"]), "exact_record_json": row["exact_record_json"]}
    numeric = {"report_revision", "selected_row_index", "table_row_index", "source_sample_index", "coordinate", "value"}
    return [v[k] if k in numeric else spreadsheet_text(v[k]) for k in CSV_COLUMNS]


def run(request):
    manifest = validate(request)
    selection = request["selection"]
    export = request["operation"] == "signal_values_export"
    page = request.get("page", {"offset": 0, "limit": 0})
    chosen = None
    page_rows = []
    page_bytes = 0
    page_full = False
    full = blank_stats()
    selected = blank_stats()
    output = None
    output_path = None
    output_created = False
    output_hash = hashlib.sha256()
    output_bytes = 0
    succeeded = False

    def write(fields):
        nonlocal output_bytes
        buffer = io.StringIO(newline="")
        csv.writer(buffer, quoting=csv.QUOTE_ALL, lineterminator="\r\n").writerow(fields)
        raw = buffer.getvalue().encode("utf-8")
        require(output_bytes + len(raw) <= MAX_EXPORT_BYTES, "Selected CSV exceeds 2 GiB. Choose a narrower range; the complete typed source artifact remains available.")
        output.write(raw)
        output_hash.update(raw)
        output_bytes += len(raw)

    def table(t):
        nonlocal chosen
        if t["table_id"] != selection["table_id"]:
            return
        expected = request["table"]
        require(t["identity"]["recording_id"] == selection["recording_id"] and t["identity"]["channel"] == selection["channel"], "The table belongs to another recording or channel.")
        for actual, wanted in ((t["identity"], expected["identity"]), (t["coordinates"], expected["coordinates"]),
                               (preview.coordinate(t), expected["coordinate_column"]), (preview.numeric_fields(t), expected["value_columns"]),
                               (t["expected_rows"], expected["rows"])):
            require(same(actual, wanted), "The table differs from its pinned catalog identity, clock, units or declarations.")
        require(selection["value_column"] in [c["name"] for c in preview.numeric_fields(t)], "Choose a declared numeric measure from this exact table.")
        index_column = next((c for c in t["columns"] if c["name"] == "source_sample_index"), None)
        require(index_column is None or index_column["type"] == "integer" and index_column["role"] == "index",
                "A source sample index must be declared as an integer index; no text is inferred as a numeric source position.")
        retained_column = next((c for c in t["columns"] if c["name"] == "retained"), None)
        require(retained_column is None or retained_column["type"] == "boolean" and retained_column["role"] == "support",
                "Retained status must be declared as boolean support, including an empty table.")
        chosen = t

    def rows(tid, offset, values):
        nonlocal page_bytes, page_full
        if chosen is None or tid != chosen["table_id"]:
            return
        bounds = selection["range"]
        names = [c["name"] for c in chosen["columns"]]
        for i, native in enumerate(values):
            point = preview.sample(chosen, native, offset+i, selection["value_column"])
            retained = native[names.index("retained")] if "retained" in names else None
            retention = "not_declared" if "retained" not in names else "retained" if retained is True else "excluded" if retained is False else "unknown"
            count(full, point, retention)
            if bounds is not None and not (preview.finite(point["x"]) and bounds[0] <= point["x"] <= bounds[1]):
                continue
            number = selected["rows"]
            count(selected, point, retention)
            if export:
                record = row_record(chosen, native, offset+i, number, selection["value_column"])
                write(csv_row(request, chosen, record))
            elif not page_full and number >= page["offset"]:
                record = row_record(chosen, native, offset+i, number, selection["value_column"])
                size = len(encode(record).encode("ascii"))
                if len(page_rows) >= page["limit"] or page_bytes + size > MAX_PAGE_BYTES:
                    require(page_rows, "A source row exceeds the exact-value page bound; download its complete typed artifact.")
                    page_full = True
                else:
                    page_rows.append(record)
                    page_bytes += size

    try:
        if export:
            require(artifacts.text(request["export_path"], 4000), "Choose a new owned CSV output path.")
            output_path = Path(request["export_path"])
            require(output_path.parent.is_dir() and not os.path.lexists(output_path) and output_path.resolve() != Path(manifest["path"]).resolve(), "CSV output must be new and separate from the original artifact.")
            output = output_path.open("xb")
            output_created = True
            write(CSV_COLUMNS)
        artifacts.verify_artifact(manifest, on_table=table, on_rows=rows)
        require(chosen is not None, "The exact selected table is absent; no substitute was used.")
        result = {"schema": SCHEMA, "status": "completed" if selected["rows"] else "empty_range", "operation": request["operation"],
                  "binding": copy.deepcopy(request["binding"]), "selection": copy.deepcopy(selection), "table": chosen,
                  "artifact": {k: manifest[k] for k in ("kind", "sha256", "bytes", "schema", "tables", "rows", "provenance_sha256")},
                  "full_source": full, "selected_source": selected, "unplaceable_coordinate_rows": full["missing_coordinate_rows"] if selection["range"] is not None else 0,
                  "numeric_encoding": "Python binary64 repr: shortest round-trip decimal, signed zero preserved; explicit native types/null flags",
                  "row_policy": "All source rows matching the coordinate selection, including missing values and excluded retention. No plot eligibility filter.",
                  "engine": {"name": "Brohn exact processed values", "version": "1.0", "worker_sha256": artifacts.digest_file(Path(__file__)),
                             "artifact_reader_sha256": artifacts.digest_file(Path(artifacts.__file__)), "selection_reader_sha256": artifacts.digest_file(Path(preview.__file__))}}
        if export:
            output.flush()
            os.fsync(output.fileno())
            output.close()
            output = None
            result["csv"] = {"sha256": output_hash.hexdigest(), "bytes": output_bytes, "rows": selected["rows"], "media_type": "text/csv; charset=utf-8", "columns": CSV_COLUMNS}
        else:
            next_offset = page["offset"] + len(page_rows)
            result["page"] = {**page, "returned": len(page_rows), "total_rows": selected["rows"],
                              "previous_offset": max(0, page["offset"]-page["limit"]) if page["offset"] > 0 else None,
                              "next_offset": next_offset if page_rows and next_offset < selected["rows"] else None,
                              "byte_limited": page_full and len(page_rows) < page["limit"], "max_encoded_rows_bytes": MAX_PAGE_BYTES}
            result["rows"] = page_rows
        require(len(encode(result).encode("ascii")) <= MAX_RESULT_BYTES, "Exact-value result exceeds its 16 MiB response bound; the original artifact remains available.")
        succeeded = True
        return result
    finally:
        if output is not None:
            output.close()
        if export and output_created and not succeeded and output_path is not None and output_path.exists():
            output_path.unlink()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--request", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    safe = args.output.parent.is_dir() and not os.path.lexists(args.output) and args.output.resolve() != args.request.resolve()
    code = 0
    try:
        require(safe, "Exact-value receipt requires a new output path.")
        require(args.request.is_file() and args.request.stat().st_size <= 4*1024**2, "Exact-value request is absent or exceeds 4 MiB.")
        request = json.loads(args.request.read_text(encoding="utf-8"), object_pairs_hook=artifacts._unique,
                             parse_constant=lambda x: (_ for _ in ()).throw(InputError("Nonfinite request JSON.")))
        if "export_path" in request:
            require(Path(request["export_path"]).resolve() not in {args.request.resolve(), args.output.resolve()}, "CSV and request/receipt paths must be distinct.")
        result = run(request)
    except Exception as error:
        code = 2
        result = {"schema": "brohn-signal-values-error/1.0", "status": "error", "error": {"type": type(error).__name__, "message": str(error)[:1000]}}
    if not safe:
        print(encode(result), file=sys.stderr)
        return code
    require(args.output.parent.is_dir(), "Exact-value receipt directory must exist.")
    descriptor, name = tempfile.mkstemp(prefix=".brohn-values-", suffix=".json.tmp", dir=args.output.parent)
    try:
        with os.fdopen(descriptor, "w", encoding="ascii") as stream:
            stream.write(encode(result)+"\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.link(name, args.output)  # exclusive final name: never replace another file
    finally:
        if os.path.exists(name):
            os.unlink(name)
    print(encode({"status": result["status"]}))
    return code


if __name__ == "__main__":
    raise SystemExit(main())
