"""Exact descriptive interval summaries over one verified processed signal table."""
from __future__ import annotations

import argparse
import copy
import importlib.util
import json
import math
import os
from pathlib import Path

_spec = importlib.util.spec_from_file_location("brohn_window_preview", Path(__file__).with_name("signal_preview.py"))
preview = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(preview)
artifacts, require = preview.artifacts, preview.require
MAX_INTERVALS, MAX_MEASURES, MAX_CONTRIBUTIONS = 64, 16, 20_000_000


def validate_intervals(intervals):
    require(isinstance(intervals, list) and 1 <= len(intervals) <= MAX_INTERVALS, "Save 1 to 64 intervals before summarizing.")
    ids = set()
    for interval in intervals:
        require(isinstance(interval, dict) and set(interval) == {"id", "label", "category", "start_s", "end_s", "note"}, "Interval fields are incomplete or unsupported.")
        for key, maximum, empty in (("id", 160, False), ("label", 240, False), ("category", 120, True), ("note", 4000, True)):
            value = interval[key]
            require(isinstance(value, str) and len(value) <= maximum and (empty or bool(value.strip())) and "\x00" not in value, "Interval labels must be bounded text.")
        require(interval["id"] not in ids, "Interval IDs must be distinct.")
        ids.add(interval["id"])
        require(preview.finite(interval["start_s"]) and preview.finite(interval["end_s"]) and interval["start_s"] < interval["end_s"], "Each interval needs increasing finite start/end seconds.")


def blank():
    return {"selected_rows": 0, "eligible_rows": 0, "missing_value_rows": 0, "excluded_support_rows": 0,
            "mean": None, "standard_deviation_sample": None, "minimum": None, "maximum": None,
            "first_value": None, "last_value": None, "first_time_s": None, "last_time_s": None,
            "_mean": 0.0, "_m2": 0.0}


def observe(summary, point):
    summary["selected_rows"] += 1
    if not preview.finite(point["y"]):
        summary["missing_value_rows"] += 1
    if not point["retained"]:
        summary["excluded_support_rows"] += 1
    if not preview.finite(point["y"]) or not point["retained"]:
        return
    value = float(point["y"])
    summary["eligible_rows"] += 1
    n = summary["eligible_rows"]
    delta = value - summary["_mean"]
    summary["_mean"] += delta / n
    summary["_m2"] += delta * (value - summary["_mean"])
    require(math.isfinite(summary["_mean"]) and math.isfinite(summary["_m2"]), "Values exceed the supported numerical range; no nonfinite summary can be published.")
    if n == 1:
        summary.update(minimum=value, maximum=value, first_value=value, first_time_s=point["x"])
    summary["minimum"] = min(summary["minimum"], value)
    summary["maximum"] = max(summary["maximum"], value)
    summary["last_value"], summary["last_time_s"] = value, point["x"]


def run(request):
    require(isinstance(request, dict) and set(request) == {"schema", "artifact", "verification_receipt", "selection", "annotation_source", "intervals"}
            and request["schema"] == "brohn-signal-window-request/1.0", "Unsupported interval summary request.")
    manifest = preview.bind_receipt(request)
    require(manifest["kind"] == "physiology-series", "Choose a complete continuous-series artifact; event/spectrum rows need their own analysis.")
    selection, source, intervals = request["selection"], request["annotation_source"], request["intervals"]
    require(isinstance(selection, dict) and set(selection) == {"table_id", "identity", "coordinates", "value_columns"}, "Pin an exact saved table, clock and measures.")
    require(artifacts.text(selection["table_id"], 160), "Choose a saved table ID.")
    measures = selection["value_columns"]
    require(isinstance(measures, list) and 1 <= len(measures) <= MAX_MEASURES and all(artifacts.text(m, 500) for m in measures) and len(set(measures)) == len(measures), "Choose 1 to 16 distinct numeric measures.")
    require(isinstance(source, dict) and set(source) == {"id", "revision", "hash"} and artifacts.text(source["id"], 160)
            and preview.integer(source["revision"], 1, 2**31-1) and isinstance(source["hash"], str) and artifacts.HEX.fullmatch(source["hash"]), "Pin the exact saved annotation revision and hash.")
    validate_intervals(intervals)
    selected = {}
    statistics = {(i["id"], m): blank() for i in intervals for m in measures}
    table_support = {"rows": 0, "missing_coordinate_rows": 0, "coordinate_range": None}
    previous = None
    contributions = 0

    def table(t):
        if t["table_id"] != selection["table_id"]:
            return
        require(not selected, "The selected table occurs more than once.")
        require(t["support"].get("trace_profile") != "gaze-pupil-source-trace/1.0", "Pupil/blink interval summaries require their separate validity and baseline policies; generic sample means are unavailable.")
        descriptor = preview.descriptor(t)
        require(t["coordinates"]["axis"] == "time" and descriptor["coordinate_column"]["unit"] == "s", "Intervals apply only to declared time coordinates in seconds, never frequency bins.")
        for field in ("identity", "coordinates"):
            require(json.dumps(selection[field], sort_keys=True, allow_nan=False) == json.dumps(t[field], sort_keys=True, allow_nan=False), "The selected recording/person/session or original clock differs from the saved annotation source.")
        available = {c["name"]: c for c in preview.numeric_fields(t)}
        require(all(m in available for m in measures), "A selected measure is not declared numeric data in this table.")
        selected.update(table=copy.deepcopy(t), descriptor=descriptor, columns=available)

    def rows(tid, offset, values):
        nonlocal previous, contributions
        if not selected or tid != selection["table_id"]:
            return
        t = selected["table"]
        for index, row in enumerate(values):
            point = preview.sample(t, row, offset+index, measures[0])
            x = point["x"]
            table_support["rows"] += 1
            if not preview.finite(x):
                table_support["missing_coordinate_rows"] += 1
                continue
            require(previous is None or x > previous, "Time coordinates must increase inside one table; clock resets require separate annotation sources.")
            previous = x
            table_support["coordinate_range"] = preview.minmax(table_support["coordinate_range"], x)
            active = [i for i in intervals if i["start_s"] <= x < i["end_s"]]
            contributions += len(active) * len(measures)
            require(contributions <= MAX_CONTRIBUTIONS, "This interval selection exceeds the summary work limit; use fewer intervals or measures.")
            if not active:
                continue
            points = {m: preview.sample(t, row, offset+index, m) for m in measures}
            for interval in active:
                for measure, p in points.items():
                    observe(statistics[(interval["id"], measure)], p)

    receipt = artifacts.verify_artifact(manifest, on_table=table, on_rows=rows)
    require(bool(selected), "The saved annotation table is absent; no substitute was selected.")
    result_rows = []
    for interval in intervals:
        for measure in measures:
            stats = statistics[(interval["id"], measure)]
            if stats["eligible_rows"]:
                stats["mean"] = stats["_mean"]
            if stats["eligible_rows"] > 1:
                stats["standard_deviation_sample"] = math.sqrt(max(0.0, stats["_m2"]/(stats["eligible_rows"]-1)))
            del stats["_mean"], stats["_m2"]
            result_rows.append({"interval_id": interval["id"], "label": interval["label"], "category": interval["category"],
                                "start_s": interval["start_s"], "end_s": interval["end_s"], "measure": measure,
                                "unit": selected["columns"][measure]["unit"], "status": "available" if stats["eligible_rows"] else "no_eligible_samples", **stats})
    return {"schema": "brohn-signal-window-summary/1.0", "status": "completed", "annotation_source": source,
            "artifact": {k: manifest[k] for k in ("kind", "sha256", "bytes", "schema", "tables", "rows", "provenance_sha256")},
            "selection": selection, "intervals": intervals, "table": selected["descriptor"], "table_support": table_support,
            "summaries": result_rows, "source_provenance": receipt["provenance"],
            "parameters": {"boundary": "start inclusive, end exclusive", "aggregation": "sample-weighted arithmetic mean of finite retained samples", "standard_deviation": "sample standard deviation, n-1; unavailable below two eligible samples", "interpolation": False},
            "engine": {"name": "Brohn saved interval summaries", "version": "1.0.0", "worker_sha256": artifacts.digest_file(Path(__file__)),
                       "reader_sha256": artifacts.digest_file(Path(artifacts.__file__)), "sample_rules_sha256": artifacts.digest_file(Path(preview.__file__))},
            "limitations": ["Descriptive summaries use complete processed rows, not plotted envelope points. They do not recompute a physiology recipe or establish causality.",
                            "Missing values and excluded support do not become zero; rows with missing time cannot be allocated to intervals.",
                            "Overlapping intervals deliberately reuse their observed samples. Adjacent intervals do not double-count the shared boundary.",
                            "Sample-weighted means are not time-weighted means or interval-level evidence of continuous coverage. Gaps are not interpolated.",
                            "One exact recording/person/session/clock table is used. Independent clocks, resets and participants are never aligned or pooled here."]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--request", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    safe = not os.path.lexists(args.output) and args.output.resolve() != args.request.resolve()
    code = 0
    try:
        require(safe, "Choose a new summary output; existing files cannot be replaced.")
        require(args.request.is_file() and args.request.stat().st_size <= 2*1024**2, "Summary request is absent or exceeds 2 MiB.")
        request = json.loads(args.request.read_text(encoding="utf-8"), object_pairs_hook=artifacts._unique,
                             parse_constant=lambda _: (_ for _ in ()).throw(artifacts.ArtifactError("Nonfinite request JSON.")))
        result = run(request)
    except Exception as error:
        code = 2
        result = {"schema": "brohn-signal-window-error/1.0", "status": "error", "error": {"type": type(error).__name__, "message": str(error)[:1000]}}
    if not safe:
        print(json.dumps(result))
        return code
    require(args.output.parent.is_dir(), "The output directory must already exist.")
    payload = json.dumps(result, ensure_ascii=False, allow_nan=False, separators=(",", ":")).encode("utf-8")
    require(len(payload) <= 16*1024**2, "Interval summary output exceeds 16 MiB.")
    # Exclusive creation never replaces another file that appeared during work.
    with args.output.open("xb") as target:
        target.write(payload)
    return code


if __name__ == "__main__":
    raise SystemExit(main())
