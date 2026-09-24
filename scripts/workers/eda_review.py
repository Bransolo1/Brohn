"""Review exact saved EDA windows/candidates. No filtering, detection or scoring."""
from __future__ import annotations
import argparse
import csv
import hashlib
import json
import math
from pathlib import Path
import sys
import physiology_artifacts as tables

MAX_SELECTED = 500_000
MAX_CSV = 128 * 1024**2
COMPONENTS = ("clean_us", "tonic_us", "phasic_us")
require = tables.require

def finite(x):
    return isinstance(x, (float, int)) and not isinstance(x, bool) and math.isfinite(x)

def safe(x):
    if x is None:
        return ""
    if isinstance(x, bool):
        return "true" if x else "false"
    if isinstance(x, (float, int)):
        return repr(x)
    x = str(x)
    return "'" + x if x and x[:1] in "=+-@\t\r\n" else x

def save_csv(path, fields, rows):
    require(not path.exists(), "EDA review export destination already exists.")
    with path.open("x", encoding="utf-8", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(fields)
        count = 0
        for row in rows:
            writer.writerow([safe(row.get(k)) for k in fields])
            count += 1
            require(f.tell() <= MAX_CSV, "Complete EDA window CSV exceeds 128 MiB; no truncated review was published.")
    return {"name": path.name, "hash": tables.digest_file(path), "bytes": path.stat().st_size, "rows": count}

def preview(rows, component, maximum=1200):
    """Actual endpoints and extrema per bucket, separated by segment/retention.

    These selected samples are display only. Complete CSV and exact numerical
    pages retain every saved value, including excluded processing-edge samples.
    """
    groups = []
    for row in rows:
        key = (row["table_id"], row["retained"])
        if not groups or groups[-1]["key"] != key:
            groups.append({"key": key, "rows": []})
        groups[-1]["rows"].append(row)
    require(len(groups) <= 200, "This window has more than 200 separate trace/support runs; original artifacts remain available.")
    result = []
    for group in groups:
        items = group["rows"]
        target = max(4, maximum * len(items) // max(1, len(rows)))
        step = max(1, math.ceil(len(items) / max(1, target // 4)))
        indices = set()
        for start in range(0, len(items), step):
            block = range(start, min(start + step, len(items)))
            indices.update((block.start, block.stop - 1))
            valid = [i for i in block if finite(items[i][component])]
            if valid:
                indices.add(min(valid, key=lambda i: items[i][component]))
                indices.add(max(valid, key=lambda i: items[i][component]))
        result.append({"table_id": group["key"][0], "retained": group["key"][1], "source_rows": len(items),
                       "points": [{"time_s": items[i]["relative_time_s"], "value": items[i][component],
                                   "source_sample_index": items[i]["source_sample_index"]} for i in sorted(indices)]})
    return result

def review(request):
    require(request.get("schema") == "brohn-eda-review-request/1.0", "Choose a registered saved EDA review.")
    event, parameters, selection = request["event"], request["parameters"], request["binding"]["selection"]
    require(all(event[k] == selection[k] for k in ("recording_id", "event_id", "channel")), "EDA event identity changed.")
    require(parameters["recipe"] in ("eda-event-highpass/1.0", "eda-event-cvxeda-defaults/1.0"), "Unsupported saved EDA recipe.")
    onset = event["time_s"]
    require(finite(onset) and event["unit"] == "uS", "Saved EDA onset or calibrated unit is unavailable.")
    lower, upper = parameters["baseline_s"][0], parameters["recovery_end_s"]
    require(finite(lower) and finite(upper) and lower < upper, "Saved EDA context window is invalid.")
    require(event["baseline_support"]["requested_start_s"] == onset + parameters["baseline_s"][0] and
            event["baseline_support"]["requested_end_s"] == onset + parameters["baseline_s"][1] and
            event["response_support"]["requested_start_s"] == onset + parameters["response_s"][0] and
            event["response_support"]["requested_end_s"] == onset + parameters["response_s"][1], "Saved event windows disagree with the accepted parameters.")
    raw_source = request["original_source"]
    require(Path(raw_source["path"]).stat().st_size == raw_source["bytes"] and tables.digest_file(raw_source["path"]) == raw_source["hash"], "Original recording bytes differ from the saved report.")
    for ref in request.get("sealed_objects", []):
        require(Path(ref["path"]).stat().st_size == ref["bytes"] and tables.digest_file(ref["path"]) == ref["hash"], "Saved report bytes changed.")
    samples, candidates, source_tables, verification = [], [], [], []
    counts = {"complete_artifact_rows": 0, "matched_channel_rows": 0, "selected_rows": 0, "retained_rows": 0, "excluded_rows": 0}
    for manifest in request["artifacts"]:
        declared = {}
        def on_table(spec):
            declared[spec["table_id"]] = spec
            identity = spec["identity"]
            if identity.get("recording_id") != selection["recording_id"] or identity.get("channel") != selection["channel"]:
                return
            coordinate = spec["coordinates"]
            require(coordinate["reference"] == "seconds relative to original source recording start" and
                    coordinate["source_time_origin"] == event["source_time_origin"], "Saved EDA source clock does not match this event.")
            require(spec["support"]["parameters"] == parameters and spec["support"]["source"]["sampling_rate"] == event["sampling_rate"], "Saved continuous segment recipe/rate changed.")
            require(identity["group"]["participant_id"] == event["group"]["participant_id"] and identity["group"]["session_id"] == event["group"]["session_id"], "Saved source person/session changed.")
            if manifest["kind"] == "physiology-series":
                columns = {c["name"]: c for c in spec["columns"]}
                require(all(columns[k]["type"] == "float64" and columns[k]["unit"] == "uS" for k in COMPONENTS) and
                        columns["time_s"]["unit"] == "s" and columns["retained"]["type"] == "boolean", "EDA trace has unsupported quantities or support flags.")
                source_tables.append(spec)
        def on_rows(table_id, offset, rows):
            spec = declared[table_id]
            identity = spec["identity"]
            if identity.get("recording_id") != selection["recording_id"] or identity.get("channel") != selection["channel"]:
                return
            columns = [c["name"] for c in spec["columns"]]
            for i, values in enumerate(rows):
                row = dict(zip(columns, values))
                if manifest["kind"] == "physiology-series":
                    counts["matched_channel_rows"] += 1
                    t = row["time_s"]
                    require(finite(t), "Saved EDA source time is unavailable.")
                    if onset + lower <= t <= onset + upper:
                        samples.append({"table_id": table_id, "segment_id": identity["segment_id"], "table_row_index": offset+i,
                                        "relative_time_s": t-onset, **row})
                        require(len(samples) <= MAX_SELECTED, "EDA review exceeds 500,000 selected rows; no truncated source was used.")
                elif onset + lower <= row["peak_time_s"] <= onset + upper:
                    require(row["type"] == "scr_candidate", "Unexpected EDA candidate type.")
                    candidates.append({"table_id": table_id, "segment_id": identity["segment_id"], **row})
        verified = tables.verify_artifact(manifest, on_table=on_table, on_rows=on_rows)
        p = verified["provenance"]
        require(p["source_sha256"] == raw_source["hash"] and p["operation"] == "eda_events" and
                p["origin"] == request["binding"]["origin"], "Processed EDA artifact belongs to another original recording or operation.")
        verification.append({"kind": manifest["kind"], "sha256": manifest["sha256"], "rows": verified["rows"], "tables": verified["tables"]})
        if manifest["kind"] == "physiology-series":
            counts["complete_artifact_rows"] = verified["rows"]
    samples.sort(key=lambda s: (s["time_s"], s["source_sample_index"]))
    require(len({r["source_sample_index"] for r in samples}) == len(samples), "Saved EDA source segments overlap; no trace was joined.")
    for i, row in enumerate(samples):
        if i:
            require(row["time_s"] > samples[i-1]["time_s"], "Saved EDA source segments have duplicate or decreasing clock positions; no trace was joined.")
    selected = event.get("selected_scr")
    selected_matches = [c for c in candidates if selected and all(c.get(k) == v for k, v in selected.items())]
    require(not selected or len(selected_matches) == 1, "The event-selected SCR does not match one complete saved candidate row.")
    point_by_time = {r["time_s"]: r for r in samples}
    markers = []
    for candidate in candidates:
        is_selected = candidate in selected_matches
        for label, time_key in (("onset", "onset_time_s"), ("peak", "peak_time_s"), ("recovery", "recovery_time_s")):
            time = candidate[time_key]
            point = point_by_time.get(time)
            event_usable = is_selected and (label != "recovery" or not event.get("recovery_missing_reason"))
            markers.append({"candidate_source_peak_sample": candidate["source_peak_sample"], "kind": label,
                            "source_time_s": time, "relative_time_s": None if time is None else time-onset,
                            "phasic_us": None if point is None else point["phasic_us"], "selected_for_event": is_selected,
                            "event_measure_usable": event_usable, "in_view": point is not None,
                            "support": "unobserved" if time is None else "outside_view" if point is None else "saved_candidate"})
    counts.update(selected_rows=len(samples), retained_rows=sum(r["retained"] is True for r in samples), excluded_rows=sum(r["retained"] is False for r in samples))
    features = request["features"]
    require(all(all(f[k] == selection[k] for k in selection) for f in features), "Feature table contains another event/channel.")
    source_events = [e for e in request["source_events"] if onset + lower <= e["time_s"] <= onset + upper or e["id"] in event["overlapping_event_ids"]]
    result = {"schema": "brohn-eda-review/1.0", "status": "available" if samples else "no_processed_samples", "binding": request["binding"],
              "event": event, "parameters": parameters, "features": features, "source_events": source_events,
              "source_masks": request["source_masks"], "source_tables": source_tables, "verification": verification,
              "range_s": [lower, upper], "unit": "uS", "counts": counts, "candidates": candidates, "markers": markers,
              "series": {k: preview(samples, k) for k in COMPONENTS}, "rows": samples[:50],
              "display_policy": "Actual saved endpoints/extrema per bucket; segment and retained/excluded runs stay separate. Complete selected CSV preserves every row; no rescoring or interpolation.",
              "exports": []}
    directory = Path(request["export_directory"]).resolve()
    require(directory.is_dir(), "Choose the owned EDA review export directory.")
    sample_fields = ["table_id", "segment_id", "table_row_index", "source_sample_index", "time_s", "relative_time_s", *COMPONENTS, "retained"]
    feature_fields = ["name", "value", "unit", "eligible", "support_status", "missing_reason", "denominator", "interpretation", "event_id", "exposure_id", "condition_id", "recording_id", "channel"]
    marker_fields = ["candidate_source_peak_sample", "kind", "source_time_s", "relative_time_s", "phasic_us", "selected_for_event", "event_measure_usable", "in_view", "support"]
    for name, fields, rows in (("eda-window-samples.csv", sample_fields, samples), ("eda-event-features.csv", feature_fields, features), ("eda-response-markers.csv", marker_fields, markers)):
        result["exports"].append(save_csv(directory/name, fields, rows))
    return result

if __name__ == "__main__":
    parser = argparse.ArgumentParser();parser.add_argument("--request", required=True);parser.add_argument("--output", required=True)
    args = parser.parse_args()
    try:
        request = json.loads(Path(args.request).read_text(encoding="utf-8"))
        result = review(request)
        Path(args.output).write_text(json.dumps(result, ensure_ascii=True, separators=(",", ":"), allow_nan=False), encoding="utf-8")
    except Exception as error:
        Path(args.output).write_text(json.dumps({"status": "error", "error": {"message": str(error)}}), encoding="utf-8")
        sys.exit(1)
