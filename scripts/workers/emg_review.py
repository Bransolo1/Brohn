"""Read exact saved surface-EMG samples and explicitly configured bursts.

No filtering, envelope calculation, burst detection or window rescoring occurs.
"""
from __future__ import annotations
import argparse
import csv
from decimal import Decimal, InvalidOperation
import json
import math
from pathlib import Path
import sys
import physiology_artifacts as tables

require = tables.require
MAX_SAMPLES = 500_000
MAX_BURSTS = 5_000
MAX_CSV = 128 * 1024**2
MAX_JSON = 24 * 1024**2
IDENTITY = ("recording_id", "segment_id", "channel")
EVENT_FIELDS = ("type", "time_s", "end_time_s", "duration_s", "peak_rms_uv", "boundary_truncated")
END_POLICY = "source worker's exclusive sample-cell boundary; final observed timestamp plus one declared sample interval"


def finite(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)


def decimal(value):
    require(isinstance(value, str) and 0 < len(value) <= 80, "Choose explicit decimal source-time bounds.")
    try:
        result = Decimal(value)
    except InvalidOperation:
        raise tables.ArtifactError("Source-time bounds are not decimal numbers.")
    require(result.is_finite() and abs(result) <= Decimal("1e12"), "Source-time bounds exceed the review range.")
    return result


def check_source(source):
    path = Path(source["path"])
    require(path.is_file() and path.stat().st_size == source["bytes"] and tables.digest_file(path) == source["hash"],
            "The original recording or retained report bytes changed.")


def safe(value):
    if value is None: return ""
    if isinstance(value, bool): return "true" if value else "false"
    if isinstance(value, (int, float)): return repr(value)
    value = str(value)
    return "'" + value if value[:1] in ("=", "+", "-", "@", "\t", "\r", "\n") else value


def export_csv(directory, name, fields, rows):
    path = directory / name
    with path.open("x", encoding="utf-8", newline="") as stream:
        writer = csv.writer(stream)
        writer.writerow(fields)
        count = 0
        for row in rows:
            writer.writerow([safe(row.get(field)) for field in fields])
            count += 1
            require(stream.tell() <= MAX_CSV, "The complete EMG export exceeds its bound; nothing was truncated.")
    return {"name": name, "hash": tables.digest_file(path), "bytes": path.stat().st_size, "rows": count}


def preview(rows, component):
    groups = []
    for row in rows:
        if not groups or groups[-1]["retained"] != row["retained"]:
            groups.append({"retained": row["retained"], "rows": []})
        groups[-1]["rows"].append(row)
    require(len(groups) <= 200, "This selection has too many separate support runs for one chart.")
    result = []
    for group in groups:
        items = group["rows"]
        budget = max(4, 1200 * len(items) // max(1, len(rows)))
        step = max(1, math.ceil(len(items) / max(1, budget // 4)))
        indices = set()
        for start in range(0, len(items), step):
            block = range(start, min(start + step, len(items)))
            indices.update((block.start, block.stop - 1, min(block, key=lambda i: items[i][component]), max(block, key=lambda i: items[i][component])))
        result.append({"retained": group["retained"], "source_rows": len(items),
                       "points": [{"time_s": items[i]["time_s"], "value": items[i][component], "source_sample_index": items[i]["source_sample_index"]} for i in sorted(indices)]})
    require(sum(len(g["points"]) for g in result) <= 2000, "The actual-sample display exceeds its bound; narrow the window.")
    return result


def review(request):
    require(set(request) == {"schema", "binding", "recording", "parameters", "features", "selection", "original_source", "sealed_objects", "artifacts", "export_directory"}
            and request["schema"] == "brohn-emg-review-request/1.0", "Choose a registered saved EMG review.")
    binding, recording, parameters, features, selection = (request[k] for k in ("binding", "recording", "parameters", "features", "selection"))
    require(isinstance(binding, dict) and set(selection) == {*IDENTITY, "start_s", "end_s"}, "The EMG review needs an exact source selection.")
    require(all(selection[k] == recording[k] for k in IDENTITY) and recording["status"] == "computed", "The selected recording/segment/channel is unavailable.")
    require(parameters["recipe"] == "emg-butterworth-rms/1.0" and recording["unit"] == "uV" and parameters["mvc_normalization"] is False,
            "This review requires the saved unnormalized surface-EMG voltage recipe.")
    fs = recording["sampling_rate"]
    require(finite(fs) and fs >= 250 and parameters["filter"] == "butterworth_sos_zero_phase" and parameters["filter_order"] == 4 and
            parameters["envelope"] == "centered_window_root_mean_square" and finite(parameters["rms_window_s"]) and parameters["rms_window_s"] > 0 and
            0 < parameters["highpass_hz"] < parameters["lowpass_hz"] < fs / 2, "Saved EMG filtering or envelope declarations are incomplete.")
    threshold = parameters["burst_threshold_uv"]
    require(threshold is None or (finite(threshold) and threshold > 0), "The saved explicit RMS threshold is invalid.")
    require(finite(parameters["burst_min_duration_s"]) and parameters["burst_min_duration_s"] > 0, "The saved minimum burst duration is invalid.")
    require(isinstance(features, list) and features and all(all(f[k] == recording[k] for k in IDENTITY) for f in features) and
            len({f["name"] for f in features}) == len(features), "Saved whole-segment EMG features changed their source identity.")
    feature_map = {f["name"]: f for f in features}
    require("emg_rms" in feature_map and feature_map["emg_rms"]["unit"] == "uV", "Saved whole-segment RMS evidence is required.")
    if threshold is None:
        require("emg_burst_count" not in feature_map and "emg_accepted_burst_time_fraction" not in feature_map, "Absent threshold cannot acquire burst outcomes.")
    else:
        require("emg_burst_count" in feature_map and "emg_accepted_burst_time_fraction" in feature_map and
                finite(feature_map["emg_burst_count"]["value"]) and feature_map["emg_burst_count"]["value"] >= 0,
                "Configured threshold needs its saved whole-segment burst support.")
    lower, upper = decimal(selection["start_s"]), decimal(selection["end_s"])
    require(lower < upper, "Choose an increasing source-time window.")
    artifacts = request["artifacts"]
    require(len(artifacts) == 2 and {a["kind"] for a in artifacts} == {"physiology-series", "physiology-events"}, "Both complete sample and burst artifacts are required.")
    original = request["original_source"]
    sources = [original, *request["sealed_objects"]]
    for source in sources: check_source(source)
    target_identity = {k: recording[k] for k in (*IDENTITY, "group")}
    bursts, samples, markers, verification, selected_tables = [], [], [], [], {}
    counts = dict(segment_samples=0, segment_bursts=0, segment_retained_samples=0)
    raw_available = False
    segment_first_retained = segment_last_retained = None
    stats = []
    total_burst_duration = 0.0

    def verify(manifest):
        declared = {}
        previous_time = previous_end = None
        active_index = 0

        def on_table(spec):
            nonlocal raw_available
            declared[spec["table_id"]] = spec
            if any(spec["identity"].get(k) != selection[k] for k in IDENTITY): return
            kind = manifest["kind"]
            require(kind not in selected_tables and spec["identity"] == target_identity and spec["support"]["source"] == recording and
                    spec["support"]["method"] == parameters, "Saved EMG tables changed their source, group, support or effective method.")
            coordinate = spec["coordinates"]
            require(coordinate["reference"] == "seconds relative to original recording start; no source timestamp rebasing" and
                    coordinate["source_time_origin"] == recording["source_time_origin"] and coordinate["axis"] == ("time" if kind == "physiology-series" else "event"),
                    "The saved source clock is incompatible.")
            columns = {c["name"]: c for c in spec["columns"]}
            required = {"time_s": ("float64", "s")}
            if kind == "physiology-series":
                required.update(clean_uv=("float64", "uV"), rms_uv=("float64", "uV"), source_sample_index=("integer", "sample_index"), retained=("boolean", None))
                raw_available = "raw_uv" in columns
                if raw_available:
                    required["raw_uv"] = ("float64", "uV")
                    declared_input = spec["support"].get("input_waveform", {})
                    require(spec["support"].get("raw_source_omitted") is False and declared_input.get("column") == "raw_uv" and declared_input.get("unit") == "uV",
                            "The saved input waveform lacks an explicit unit-converted source declaration.")
                else:
                    require(spec["support"].get("raw_source_omitted") is True, "Missing saved input samples must be explicitly declared.")
            else:
                required.update(type=("string", None), end_time_s=("float64", "s"), duration_s=("float64", "s"), peak_rms_uv=("float64", "uV"), boundary_truncated=("boolean", None))
                require(spec["support"].get("end_time_policy") == END_POLICY, "Saved burst end boundaries have an unsupported definition.")
            require(all(k in columns and (columns[k]["type"], columns[k]["unit"]) == value for k, value in required.items()), "Saved EMG columns use incompatible quantities or support types.")
            selected_tables[kind] = spec

        def on_rows(table_id, offset, values):
            nonlocal previous_time, previous_end, active_index, segment_first_retained, segment_last_retained, total_burst_duration
            spec = declared[table_id]
            if any(spec["identity"].get(k) != selection[k] for k in IDENTITY): return
            fields = [c["name"] for c in spec["columns"]]
            for index, value in enumerate(values):
                row = dict(zip(fields, value))
                if manifest["kind"] == "physiology-events":
                    require(threshold is not None and row["type"] == "emg_threshold_burst" and
                            all(finite(row[k]) for k in ("time_s", "end_time_s", "duration_s", "peak_rms_uv")) and
                            row["time_s"] < row["end_time_s"] and row["duration_s"] >= parameters["burst_min_duration_s"] and
                            row["peak_rms_uv"] >= threshold and isinstance(row["boundary_truncated"], bool), "Saved burst threshold, duration or boundary support is invalid.")
                    require(previous_end is None or row["time_s"] >= previous_end, "Saved bursts overlap or reset in a continuous segment.")
                    previous_end = row["end_time_s"]
                    counts["segment_bursts"] += 1
                    total_burst_duration += row["duration_s"]
                    # Closed sample window intersects a half-open saved burst.
                    if Decimal(str(row["time_s"])) <= upper and Decimal(str(row["end_time_s"])) > lower:
                        bursts.append({"table_id": table_id, "table_row_index": offset + index, **row})
                        stats.append(dict(count=0, first=None, last=None, peak=None))
                        require(len(bursts) <= MAX_BURSTS, "This window exceeds 5,000 saved bursts; narrow the window.")
                else:
                    require(finite(row["time_s"]) and all(finite(row[k]) for k in ("clean_uv", "rms_uv")) and row["rms_uv"] >= 0 and
                            (not raw_available or finite(row["raw_uv"])) and isinstance(row["retained"], bool), "Saved EMG samples have missing or invalid values.")
                    require(previous_time is None or 0 < row["time_s"] - previous_time <= 1.5 / fs + 1e-12, "A gap or source-time reset cannot be joined inside one continuous segment.")
                    previous_time = row["time_s"]
                    require(row["source_sample_index"] == recording["source_row_start"] + offset + index, "The continuous segment lost its original sample-row identity.")
                    counts["segment_samples"] += 1
                    if row["retained"]:
                        counts["segment_retained_samples"] += 1
                        if segment_first_retained is None: segment_first_retained = row["source_sample_index"]
                        segment_last_retained = row["source_sample_index"]
                    while active_index < len(bursts) and row["time_s"] >= bursts[active_index]["end_time_s"] - 1e-12: active_index += 1
                    if active_index < len(bursts) and row["time_s"] >= bursts[active_index]["time_s"]:
                        state = stats[active_index]
                        require(row["retained"] and row["rms_uv"] >= threshold, "A saved accepted burst contains an excluded or below-threshold sample.")
                        state["count"] += 1
                        if state["first"] is None: state["first"] = row.copy()
                        state["last"] = row.copy()
                        if state["peak"] is None or row["rms_uv"] > state["peak"]["rms_uv"]: state["peak"] = row.copy()
                    if lower <= Decimal(str(row["time_s"])) <= upper:
                        samples.append({"table_id": table_id, "table_row_index": offset + index, **row, "raw_uv": row.get("raw_uv")})
                        require(len(samples) <= MAX_SAMPLES, "This window exceeds 500,000 complete samples; narrow the window.")
        result = tables.verify_artifact(manifest, on_table=on_table, on_rows=on_rows)
        provenance = result["provenance"]
        require(provenance["source_sha256"] == original["hash"] and provenance["operation"] == "physiology" and provenance["origin"] == binding["origin"],
                "A processed artifact belongs to another recording, operation or origin.")
        verification.append({"kind": manifest["kind"], "sha256": manifest["sha256"], "rows": result["rows"], "tables": result["tables"]})
        counts["complete_sample_artifact_rows" if manifest["kind"] == "physiology-series" else "complete_event_artifact_rows"] = result["rows"]
        return provenance

    events_provenance = verify(next(a for a in artifacts if a["kind"] == "physiology-events"))
    samples_provenance = verify(next(a for a in artifacts if a["kind"] == "physiology-series"))
    require(events_provenance == samples_provenance and len(selected_tables) == 2, "The complete EMG sample/event source pair is unavailable.")
    require({k: v for k, v in selected_tables["physiology-events"]["coordinates"].items() if k != "axis"} ==
            {k: v for k, v in selected_tables["physiology-series"]["coordinates"].items() if k != "axis"}, "The burst and waveform tables have different original clock declarations.")
    require(counts["segment_samples"] == recording["samples"] == recording["source_row_end_exclusive"] - recording["source_row_start"] and
            counts["segment_retained_samples"] == recording["retained_samples"], "Complete EMG support differs from the saved analysis.")
    if threshold is not None:
        require(counts["segment_bursts"] == feature_map["emg_burst_count"]["value"] and
                math.isclose(feature_map["emg_accepted_burst_time_fraction"]["value"], total_burst_duration / (counts["segment_retained_samples"] / fs), rel_tol=1e-12, abs_tol=1e-12),
                "Complete burst support differs from the saved whole-segment measurements.")
    else: require(counts["segment_bursts"] == 0, "An absent threshold cannot yield a detected burst.")
    for burst, state in zip(bursts, stats):
        first, last, peak = (state[k] for k in ("first", "last", "peak"))
        require(first is not None and first["time_s"] == burst["time_s"] and
                math.isclose(last["time_s"] + 1 / fs, burst["end_time_s"], rel_tol=1e-12, abs_tol=1e-12) and
                last["source_sample_index"] - first["source_sample_index"] + 1 == state["count"] and
                math.isclose(state["count"] / fs, burst["duration_s"], rel_tol=1e-12, abs_tol=1e-12) and peak["rms_uv"] == burst["peak_rms_uv"],
                "Saved burst boundaries, duration or maximum differ from exact retained RMS samples.")
        truncated = first["source_sample_index"] == segment_first_retained or last["source_sample_index"] == segment_last_retained
        require(burst["boundary_truncated"] == truncated, "The saved burst boundary-truncation flag changed.")
        for kind, point, time, real_sample in (("onset", first, first["time_s"], True), ("peak_rms", peak, peak["time_s"], True), ("end_boundary", last, burst["end_time_s"], False)):
            markers.append(dict(burst_table_row_index=burst["table_row_index"], kind=kind, time_s=time,
                rms_uv=point["rms_uv"] if real_sample else None, source_sample_index=point["source_sample_index"] if real_sample else None,
                anchor_source_sample_index=point["source_sample_index"], anchor_time_s=point["time_s"], retained=True,
                in_view=lower <= Decimal(str(time)) <= upper, boundary_truncated=burst["boundary_truncated"]))
    counts.update(selected_samples=len(samples), selected_bursts=len(bursts), retained_samples=sum(r["retained"] for r in samples), excluded_samples=sum(not r["retained"] for r in samples))
    directory = Path(request["export_directory"])
    require(directory.is_dir() and not directory.is_symlink(), "Choose an existing owned export directory.")
    sample_fields = ("table_id", "table_row_index", "source_sample_index", "time_s", "raw_uv", "clean_uv", "rms_uv", "retained")
    burst_fields = ("table_id", "table_row_index", *EVENT_FIELDS)
    marker_fields = ("burst_table_row_index", "kind", "time_s", "rms_uv", "source_sample_index", "anchor_source_sample_index", "anchor_time_s", "retained", "in_view", "boundary_truncated")
    exports = [export_csv(directory, name, fields, rows) for name, fields, rows in (
        ("emg-samples.csv", sample_fields, samples), ("emg-bursts.csv", burst_fields, bursts), ("emg-markers.csv", marker_fields, markers))]
    for source in sources: check_source(source)
    components = ["raw_uv", "clean_uv", "rms_uv"] if raw_available else ["clean_uv", "rms_uv"]
    result = dict(schema="brohn-emg-review/1.0", status="available" if samples else "no_processed_samples", binding=binding,
        selection=selection, recording=recording, parameters=parameters, features=features, unit="uV", raw_available=raw_available,
        threshold_status="configured" if threshold is not None else "not_configured", counts=counts, bursts=bursts, markers=markers,
        series={k: preview(samples, k) for k in components}, rows=samples[:50], source_tables=list(selected_tables.values()), verification=verification, exports=exports,
        display_policy="Closed source-time sample window; exact saved processed values. Separate component envelopes use actual endpoints/extrema, with retained/excluded runs kept separate. Saved intersecting bursts retain complete half-open boundaries and metrics.",
        duration_policy=END_POLICY,
        limitations=["Input samples, when retained, are the original unit-converted voltage before cleaning, not source-file bytes or an inferred MVC reference.",
            "Historical reports that omitted input samples retain clean/RMS review; no raw overlay is reconstructed from previews.",
            "Threshold bursts are configured surface-EMG outcomes, not automatic facial/startle events, fatigue, emotion or percent muscle activation.",
            "No threshold is invented. Saved whole-segment features are not rescored for the selected viewport."])
    require(len(json.dumps(result, ensure_ascii=True, allow_nan=False).encode()) <= MAX_JSON, "The complete EMG review exceeds its document bound; narrow the window.")
    return result


def load_request(path):
    require(path.is_file() and path.stat().st_size <= 1024**2, "The EMG-review request exceeds its bound.")
    def unique(pairs):
        result = {}
        for key, value in pairs:
            require(key not in result, "Duplicate JSON request field.")
            result[key] = value
        return result
    return json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=unique,
                      parse_constant=lambda x: (_ for _ in ()).throw(tables.ArtifactError("Nonfinite JSON request value.")))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--request", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    output = Path(args.output)
    try:
        require(not output.exists(), "The EMG-review output already exists.")
        result = review(load_request(Path(args.request)))
        with output.open("x", encoding="utf-8") as stream: json.dump(result, stream, ensure_ascii=True, allow_nan=False, separators=(",", ":"))
    except Exception as error:
        if not output.exists():
            with output.open("x", encoding="utf-8") as stream: json.dump({"status": "error", "error": {"message": str(error)[:2000]}}, stream)
        sys.exit(1)
