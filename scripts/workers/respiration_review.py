"""Inspect saved displacement cycles against complete processed samples.

This reader does not filter, detect breaths, rescore a window or infer volume.
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
MAX_CYCLES = 5_000
MAX_CSV = 128 * 1024**2
MAX_JSON = 16 * 1024**2
IDENTITY = ("recording_id", "segment_id", "channel")
EVENT_FIELDS = ("type", "time_s", "peak_time_s", "end_time_s", "duration_s", "inspiration_s", "expiration_s", "amplitude")


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
    if value is None:
        return ""
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return repr(value)
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
            require(stream.tell() <= MAX_CSV, "The complete cycle-review export exceeds its bound; nothing was truncated.")
    return {"name": name, "hash": tables.digest_file(path), "bytes": path.stat().st_size, "rows": count}


def preview(rows):
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
            indices.update((block.start, block.stop - 1, min(block, key=lambda i: items[i]["clean"]), max(block, key=lambda i: items[i]["clean"])))
        result.append({"retained": group["retained"], "source_rows": len(items),
                       "points": [{k: items[i][k] for k in ("time_s", "clean", "source_sample_index")} for i in sorted(indices)]})
    return result


def review(request):
    require(set(request) == {"schema", "binding", "recording", "parameters", "selection", "original_source", "sealed_objects", "artifacts", "export_directory"}
            and request["schema"] == "brohn-respiration-review-request/1.0", "Choose a registered saved respiration review.")
    binding, recording, parameters, selection = (request[k] for k in ("binding", "recording", "parameters", "selection"))
    require(isinstance(binding, dict) and set(selection) == {*IDENTITY, "start_s", "end_s"}, "The cycle review needs an exact source selection.")
    require(all(selection[k] == recording[k] for k in IDENTITY) and recording["status"] == "computed", "The selected recording/segment/channel is unavailable.")
    require(parameters["recipe"] == "respiration-displacement-khodadad/1.0", "This review needs the saved displacement-cycle recipe.")
    quantity, polarity, unit = parameters["source_quantity"], parameters["polarity"], recording["unit"]
    require((quantity == "lung_volume" and unit == "L") or (quantity == "belt_displacement" and unit in ("a.u.", "V", "mV")), "Saved source quantity and amplitude unit disagree.")
    require(polarity in ("positive_inspiration", "negative_inspiration") and
            parameters["source_polarity_multiplier"] == (1 if polarity == "positive_inspiration" else -1), "The saved source polarity declaration changed.")
    require(tables.text(parameters["mapping_source"]) and finite(recording["sampling_rate"]) and recording["sampling_rate"] > 0,
            "Saved phase interpretation needs its source declaration and sample rate.")
    lower, upper = decimal(selection["start_s"]), decimal(selection["end_s"])
    require(lower < upper, "Choose an increasing source-time window.")
    artifacts = request["artifacts"]
    require(len(artifacts) == 2 and {a["kind"] for a in artifacts} == {"physiology-series", "physiology-events"}, "Both complete sample and cycle artifacts are required.")
    original = request["original_source"]
    sources = [original, *request["sealed_objects"]]
    for source in sources:
        check_source(source)
    target_identity = {k: recording[k] for k in (*IDENTITY, "group")}
    cycles, samples, markers, verification, selected_tables = [], [], [], [], {}
    counts = {"complete_sample_artifact_rows": 0, "complete_event_artifact_rows": 0, "segment_samples": 0,
              "segment_cycles": 0, "selected_samples": 0, "selected_cycles": 0, "retained_samples": 0, "excluded_samples": 0}
    wanted_times, points = set(), {}

    def verify(manifest):
        declared = {}
        def on_table(spec):
            declared[spec["table_id"]] = spec
            if any(spec["identity"].get(k) != selection[k] for k in IDENTITY):
                return
            kind = manifest["kind"]
            require(kind not in selected_tables, "Multiple saved tables claim the selected continuous segment.")
            require(spec["identity"] == target_identity and spec["support"]["source"] == recording and
                    spec["support"]["method"] == parameters, "Saved cycle tables changed their source, group, support or effective method.")
            coordinate = spec["coordinates"]
            require(coordinate["reference"] == "seconds relative to original recording start; no source timestamp rebasing" and
                    coordinate["source_time_origin"] == recording["source_time_origin"] and
                    coordinate["axis"] == ("time" if kind == "physiology-series" else "event"), "The saved source clock is incompatible.")
            columns = {c["name"]: c for c in spec["columns"]}
            required = {"time_s": ("float64", "s")}
            if kind == "physiology-series":
                required.update(clean=("float64", unit), source_sample_index=("integer", "sample_index"), retained=("boolean", None))
            else:
                required.update({k: ("float64", "s") for k in EVENT_FIELDS if k not in ("type", "time_s", "amplitude")})
                required.update(type=("string", None), amplitude=("float64", unit))
            require(all(k in columns and (columns[k]["type"], columns[k]["unit"]) == value for k, value in required.items()), "Saved cycle columns use incompatible quantities or support types.")
            selected_tables[kind] = spec

        previous_time = None
        previous_end = None
        def on_rows(table_id, offset, values):
            nonlocal previous_time, previous_end
            spec = declared[table_id]
            if any(spec["identity"].get(k) != selection[k] for k in IDENTITY):
                return
            fields = [c["name"] for c in spec["columns"]]
            for index, value in enumerate(values):
                row = dict(zip(fields, value))
                if manifest["kind"] == "physiology-events":
                    require(row["type"] == "respiration_cycle" and all(finite(row[k]) for k in EVENT_FIELDS if k != "type") and
                            row["time_s"] < row["peak_time_s"] < row["end_time_s"] and all(row[k] > 0 for k in ("duration_s", "inspiration_s", "expiration_s")) and row["amplitude"] >= 0,
                            "A saved cycle has invalid boundaries, phase durations or amplitude.")
                    require(previous_end is None or row["time_s"] >= previous_end, "Saved cycles overlap or reset within a continuous segment.")
                    previous_end = row["end_time_s"]
                    counts["segment_cycles"] += 1
                    if Decimal(str(row["time_s"])) <= upper and Decimal(str(row["end_time_s"])) >= lower:
                        cycles.append({"table_id": table_id, "table_row_index": offset + index, **row})
                        require(len(cycles) <= MAX_CYCLES, "This window exceeds 5,000 saved cycles; narrow the window.")
                        wanted_times.update(row[k] for k in ("time_s", "peak_time_s", "end_time_s"))
                else:
                    require(finite(row["time_s"]) and finite(row["clean"]) and isinstance(row["retained"], bool), "The processed waveform has missing or invalid source samples.")
                    require(previous_time is None or row["time_s"] > previous_time, "Processed sample times reset inside the chosen segment.")
                    require(previous_time is None or row["time_s"] - previous_time <= 1.5 / recording["sampling_rate"] + 1e-12,
                            "A source gap cannot be joined inside one saved continuous segment.")
                    previous_time = row["time_s"]
                    require(row["source_sample_index"] == recording["source_row_start"] + offset + index,
                            "The continuous segment lost its original sample-row identity.")
                    counts["segment_samples"] += 1
                    if row["time_s"] in wanted_times:
                        points[row["time_s"]] = row
                    if lower <= Decimal(str(row["time_s"])) <= upper:
                        samples.append({"table_id": table_id, "table_row_index": offset + index, **row})
                        require(len(samples) <= MAX_SAMPLES, "This window exceeds 500,000 complete samples; narrow the window.")
        result = tables.verify_artifact(manifest, on_table=on_table, on_rows=on_rows)
        provenance = result["provenance"]
        require(provenance["source_sha256"] == original["hash"] and provenance["operation"] == "physiology" and provenance["origin"] == binding["origin"],
                "A processed artifact belongs to another recording, operation or declared origin.")
        verification.append({"kind": manifest["kind"], "sha256": manifest["sha256"], "rows": result["rows"], "tables": result["tables"]})
        counts["complete_sample_artifact_rows" if manifest["kind"] == "physiology-series" else "complete_event_artifact_rows"] = result["rows"]
        return provenance

    # Read complete events first: exact boundary samples may be outside the
    # chosen viewport, but must still exist in this same continuous segment.
    event_provenance = verify(next(a for a in artifacts if a["kind"] == "physiology-events"))
    sample_provenance = verify(next(a for a in artifacts if a["kind"] == "physiology-series"))
    require(event_provenance == sample_provenance and len(selected_tables) == 2, "The matching complete sample/cycle source pair is unavailable.")
    require({k: v for k, v in selected_tables["physiology-events"]["coordinates"].items() if k != "axis"} ==
            {k: v for k, v in selected_tables["physiology-series"]["coordinates"].items() if k != "axis"},
            "The cycle and waveform tables have different original clock declarations.")
    require(counts["segment_samples"] == recording["samples"] == recording["source_row_end_exclusive"] - recording["source_row_start"] and
            counts["segment_cycles"] == recording["complete_cycle_count"], "Complete segment support differs from the original saved analysis.")
    fs = recording["sampling_rate"]
    for cycle in cycles:
        times = [cycle[k] for k in ("time_s", "peak_time_s", "end_time_s")]
        require(all(time in points and points[time]["retained"] is True for time in times), "A saved cycle boundary has no exact retained processed sample.")
        start, peak, end = (points[time] for time in times)
        for key, count in (("duration_s", end["source_sample_index"] - start["source_sample_index"]),
                           ("inspiration_s", peak["source_sample_index"] - start["source_sample_index"]),
                           ("expiration_s", end["source_sample_index"] - peak["source_sample_index"])):
            require(math.isclose(cycle[key], count / fs, rel_tol=1e-12, abs_tol=1e-12), "A saved phase duration differs from its actual extrema indices and declared sample rate.")
        require(math.isclose(cycle["amplitude"], peak["clean"] - start["clean"], rel_tol=1e-12, abs_tol=1e-12), "Saved cycle amplitude differs from its actual processed extrema.")
        for label, point in zip(("inspiration_start", "expiration_start", "cycle_end"), (start, peak, end)):
            markers.append({"cycle_table_row_index": cycle["table_row_index"], "kind": label, "time_s": point["time_s"],
                            "clean": point["clean"], "source_sample_index": point["source_sample_index"], "retained": point["retained"],
                            "in_view": lower <= Decimal(str(point["time_s"])) <= upper})
    counts.update(selected_samples=len(samples), selected_cycles=len(cycles), retained_samples=sum(r["retained"] for r in samples), excluded_samples=sum(not r["retained"] for r in samples))
    directory = Path(request["export_directory"])
    require(directory.is_dir() and not directory.is_symlink(), "Choose an existing owned export directory.")
    sample_fields = ("table_id", "table_row_index", "source_sample_index", "time_s", "clean", "retained")
    cycle_fields = ("table_id", "table_row_index", *EVENT_FIELDS)
    marker_fields = ("cycle_table_row_index", "kind", "time_s", "clean", "source_sample_index", "retained", "in_view")
    exports = [export_csv(directory, name, fields, rows) for name, fields, rows in (
        ("respiration-samples.csv", sample_fields, samples), ("respiration-cycles.csv", cycle_fields, cycles), ("respiration-markers.csv", marker_fields, markers))]
    for source in sources:
        check_source(source)
    result = {"schema": "brohn-respiration-review/1.0", "status": "available" if samples else "no_processed_samples",
              "binding": binding, "selection": selection, "recording": recording, "parameters": parameters, "unit": unit,
              "counts": counts, "cycles": cycles, "markers": markers, "series": preview(samples), "rows": samples[:50],
              "source_tables": list(selected_tables.values()), "verification": verification, "exports": exports,
              "display_policy": "Closed source-time window; exact original processed samples. Actual endpoints/extrema form display envelopes; retained/excluded support stays separate. Complete cycles intersecting this window retain their original untrimmed boundaries and metrics.",
              "duration_policy": "Saved phase durations use extrema sample-index differences divided by the declared sampling rate; original sample timestamps position the markers.",
              "limitations": ["This is the saved polarity-normalized cleaned waveform, not an original signed source overlay.",
                              "These displacement extrema do not establish airflow onsets, breath holds or physical timing accuracy.",
                              "Belt amplitude is not automatically tidal volume. No breath detection, window rescoring or inferred zero breathing is performed."]}
    require(len(json.dumps(result, ensure_ascii=True, allow_nan=False).encode()) <= MAX_JSON, "The complete review exceeds its document bound; narrow the selection.")
    return result


def load_request(path):
    require(path.is_file() and path.stat().st_size <= 1024**2, "The cycle-review request exceeds its bound.")
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
        require(not output.exists(), "The cycle-review output already exists.")
        result = review(load_request(Path(args.request)))
        with output.open("x", encoding="utf-8") as stream:
            json.dump(result, stream, ensure_ascii=True, allow_nan=False, separators=(",", ":"))
    except Exception as error:
        if not output.exists():
            with output.open("x", encoding="utf-8") as stream:
                json.dump({"status": "error", "error": {"message": str(error)[:2000]}}, stream)
        sys.exit(1)
