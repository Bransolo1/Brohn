"""Read exact saved continuous EDA samples and spontaneous candidate responses.

No filtering, envelope calculation, candidate detection or window rescoring occurs.
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
MAX_CANDIDATES = 5_000
MAX_CSV = 128 * 1024**2
MAX_JSON = 24 * 1024**2
IDENTITY = ("recording_id", "segment_id", "channel")
EVENT_FIELDS = ("type", "time_s", "peak_sample", "source_peak_sample", "onset_time_s", "recovery_time_s", "amplitude_us", "peak_height_us", "rise_time_s", "recovery_time_from_peak_s", "recovery_fraction", "missing_reason")
COMPONENTS = ("clean_us", "tonic_us", "phasic_us")


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
            require(stream.tell() <= MAX_CSV, "The complete EDA export exceeds its bound; nothing was truncated.")
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
            and request["schema"] == "brohn-eda-continuous-review-request/1.0", "Choose a registered saved continuous EDA review.")
    binding, recording, parameters, features, selection = (request[k] for k in ("binding", "recording", "parameters", "features", "selection"))
    require(isinstance(binding, dict) and set(selection) == {*IDENTITY, "start_s", "end_s"}, "The EDA review needs an exact source selection.")
    require(all(selection[k] == recording[k] for k in IDENTITY) and recording["status"] == "computed", "The selected recording/segment/channel is unavailable.")
    fs = recording["sampling_rate"]
    require(parameters["recipe"] == "eda-neurokit-highpass/1.0" and recording["unit"] == "uS" and finite(fs) and fs >= 8 and
            parameters["cleaner"] == "neurokit" and parameters["clean_lowpass_hz"] == 3 and parameters["clean_order"] == 4 and
            parameters["decomposition"] == "highpass" and parameters["phasic_cutoff_hz"] == .05 and parameters["recovery_fraction"] == .5 and
            parameters["threshold_definition"] == "candidate_prominence_relative_to_maximum_prominence" and parameters["no_missing_value_imputation"] is True and
            finite(parameters["amplitude_min_relative_prominence"]) and .001 <= parameters["amplitude_min_relative_prominence"] <= 1 and
            finite(parameters["edge_exclusion_s"]) and parameters["edge_exclusion_s"] >= 10,
            "This review requires the saved continuous EDA recipe and its original relative-prominence, decomposition and edge settings.")
    require(isinstance(features, list) and features and all(all(f[k] == recording[k] for k in IDENTITY) for f in features) and
            len({f["name"] for f in features}) == len(features), "Saved whole-segment EDA features changed source identity.")
    feature_map = {f["name"]: f for f in features}
    require(all(k in feature_map for k in ("scr_count", "scr_rate", "scr_amplitude_mean", "scr_amplitude_median", "tonic_mean")), "Whole-segment EDA counts, conditional amplitude and tonic support are required.")
    require(feature_map["scr_count"]["unit"] == "count" and finite(feature_map["scr_count"]["value"]) and feature_map["scr_count"]["value"] >= 0, "Saved candidate count is invalid.")
    lower, upper = decimal(selection["start_s"]), decimal(selection["end_s"])
    require(lower < upper, "Choose an increasing source-time window.")
    artifacts = request["artifacts"]
    require(len(artifacts) == 2 and {a["kind"] for a in artifacts} == {"physiology-series", "physiology-events"}, "Both complete sample and candidate artifacts are required.")
    original = request["original_source"]
    sources = [original, *request["sealed_objects"]]
    for source in sources: check_source(source)
    target_identity = {k: recording[k] for k in (*IDENTITY, "group")}
    candidates, samples, markers, verification, selected_tables = [], [], [], [], {}
    counts = dict(segment_samples=0, segment_candidates=0, segment_retained_samples=0, segment_amplitude_available=0,
                  segment_onset_missing=0, segment_recovery_missing=0)
    wanted_times, anchors = set(), {}
    amplitude_sum = 0.0

    def verify(manifest):
        declared = {}
        previous_time = None

        def on_table(spec):
            declared[spec["table_id"]] = spec
            if any(spec["identity"].get(k) != selection[k] for k in IDENTITY): return
            kind = manifest["kind"]
            require(kind not in selected_tables and spec["identity"] == target_identity and spec["support"]["source"] == recording and
                    spec["support"]["method"] == parameters, "Saved EDA tables changed their source, group, support or effective method.")
            coordinate = spec["coordinates"]
            require(coordinate["reference"] == "seconds relative to original recording start; no source timestamp rebasing" and
                    coordinate["source_time_origin"] == recording["source_time_origin"] and coordinate["axis"] == ("time" if kind == "physiology-series" else "event"), "The saved source clock is incompatible.")
            columns = {c["name"]: c for c in spec["columns"]}
            required = {"time_s": ("float64", "s")}
            if kind == "physiology-series":
                required.update({k: ("float64", "uS") for k in COMPONENTS})
                required.update(source_sample_index=("integer", "sample_index"), retained=("boolean", None))
                require(spec["support"].get("raw_source_omitted") is True and "raw_us" not in columns, "This saved recipe declares processed evidence only; raw samples cannot be reconstructed.")
            else:
                required.update(type=("string", None), peak_sample=("integer", "segment_sample_index"), source_peak_sample=("integer", "sample_index"),
                    recovery_fraction=("float64", "proportion"), missing_reason=("string", None))
                required.update({k: ("float64", "s") for k in ("onset_time_s", "recovery_time_s", "rise_time_s", "recovery_time_from_peak_s")})
                required.update({k: ("float64", "uS") for k in ("amplitude_us", "peak_height_us")})
            require(all(k in columns and (columns[k]["type"], columns[k]["unit"]) == value for k, value in required.items()), "Saved EDA columns use incompatible quantities or support types.")
            selected_tables[kind] = spec

        def on_rows(table_id, offset, values):
            nonlocal previous_time, amplitude_sum
            spec = declared[table_id]
            if any(spec["identity"].get(k) != selection[k] for k in IDENTITY): return
            fields = [c["name"] for c in spec["columns"]]
            for index, value in enumerate(values):
                row = dict(zip(fields, value))
                require(finite(row["time_s"]) and (previous_time is None or row["time_s"] > previous_time), "Saved EDA times reverse or duplicate within a continuous table.")
                if manifest["kind"] == "physiology-events":
                    require(row["type"] == "scr" and row["recovery_fraction"] == .5 and finite(row["peak_height_us"]) and
                            recording["source_row_start"] <= row["source_peak_sample"] < recording["source_row_end_exclusive"] and
                            row["source_peak_sample"] == recording["source_row_start"] + row["peak_sample"], "A saved EDA candidate has invalid peak identity or recovery definition.")
                    onset, recovery = row["onset_time_s"], row["recovery_time_s"]
                    require((onset is None or (finite(onset) and onset <= row["time_s"])) and
                            (recovery is None or (finite(recovery) and recovery >= row["time_s"])) and
                            ((onset is None and row["amplitude_us"] is None and row["rise_time_s"] is None) or
                             (onset is not None and (row["amplitude_us"] is None or finite(row["amplitude_us"])) and finite(row["rise_time_s"]) and row["rise_time_s"] >= 0)) and
                            ((recovery is None and row["recovery_time_from_peak_s"] is None) or
                             (recovery is not None and finite(row["recovery_time_from_peak_s"]) and row["recovery_time_from_peak_s"] >= 0)) and
                            row["missing_reason"] == (None if onset is not None and recovery is not None else "onset_or_recovery_outside_retained_support"), "Saved candidate endpoints or missingness are inconsistent.")
                    counts["segment_candidates"] += 1
                    counts["segment_onset_missing"] += onset is None
                    counts["segment_recovery_missing"] += recovery is None
                    if row["amplitude_us"] is not None:
                        counts["segment_amplitude_available"] += 1
                        amplitude_sum += row["amplitude_us"]
                    # A closed viewport intersects only the declared known candidate extent.
                    start = row["time_s"] if onset is None else onset
                    end = row["time_s"] if recovery is None else recovery
                    if Decimal(str(start)) <= upper and Decimal(str(end)) >= lower:
                        candidates.append({"table_id": table_id, "table_row_index": offset + index, **row})
                        wanted_times.update(t for t in (onset, row["time_s"], recovery) if t is not None)
                        require(len(candidates) <= MAX_CANDIDATES, "This window exceeds 5,000 saved candidates; narrow the window.")
                else:
                    require(all(finite(row[k]) for k in COMPONENTS) and isinstance(row["retained"], bool), "Saved EDA samples have missing or invalid processed values.")
                    require(previous_time is None or row["time_s"] - previous_time <= 1.5 / fs + 1e-12, "A gap cannot be joined inside one continuous segment.")
                    require(row["source_sample_index"] == recording["source_row_start"] + offset + index, "The continuous segment lost original sample-row identity.")
                    counts["segment_samples"] += 1
                    counts["segment_retained_samples"] += row["retained"]
                    edge = math.ceil(parameters["edge_exclusion_s"] * fs)
                    require(row["retained"] == (edge <= offset + index < recording["samples"] - edge), "Saved processing-edge support differs from the original recipe.")
                    if row["time_s"] in wanted_times: anchors[row["time_s"]] = row.copy()
                    if lower <= Decimal(str(row["time_s"])) <= upper:
                        samples.append({"table_id": table_id, "table_row_index": offset + index, **row})
                        require(len(samples) <= MAX_SAMPLES, "This window exceeds 500,000 complete samples; narrow the window.")
                previous_time = row["time_s"]
        result = tables.verify_artifact(manifest, on_table=on_table, on_rows=on_rows)
        provenance = result["provenance"]
        require(provenance["source_sha256"] == original["hash"] and provenance["operation"] == "physiology" and provenance["origin"] == binding["origin"], "A processed artifact belongs to another recording, operation or origin.")
        verification.append({"kind": manifest["kind"], "sha256": manifest["sha256"], "rows": result["rows"], "tables": result["tables"]})
        counts["complete_sample_artifact_rows" if manifest["kind"] == "physiology-series" else "complete_event_artifact_rows"] = result["rows"]
        return provenance

    event_provenance = verify(next(a for a in artifacts if a["kind"] == "physiology-events"))
    sample_provenance = verify(next(a for a in artifacts if a["kind"] == "physiology-series"))
    require(event_provenance == sample_provenance and len(selected_tables) == 2, "The complete EDA sample/event source pair is unavailable.")
    require({k: v for k, v in selected_tables["physiology-events"]["coordinates"].items() if k != "axis"} ==
            {k: v for k, v in selected_tables["physiology-series"]["coordinates"].items() if k != "axis"}, "Candidate and waveform tables have different original clock declarations.")
    require(counts["segment_samples"] == recording["samples"] == recording["source_row_end_exclusive"] - recording["source_row_start"] and
            counts["segment_retained_samples"] == recording["retained_samples"] and
            counts["segment_candidates"] == feature_map["scr_count"]["value"] and
            math.isclose(feature_map["scr_rate"]["value"], counts["segment_candidates"] / (recording["retained_duration_s"] / 60), rel_tol=1e-12, abs_tol=1e-12),
            "Complete EDA support differs from the saved whole-segment counts or denominator.")
    # Only reconcile saved conditional-amplitude support; no viewport statistic is substituted.
    denominator = counts["segment_amplitude_available"]
    for key in ("scr_amplitude_mean", "scr_amplitude_median"):
        feature = feature_map[key]
        require(feature.get("denominator") == denominator and feature["unit"] == "uS" and
                ((denominator == 0 and feature["value"] is None) or (denominator > 0 and finite(feature["value"]))),
                "Saved conditional amplitude lost its original available-onset denominator.")
    require(denominator == 0 or math.isclose(feature_map["scr_amplitude_mean"]["value"], amplitude_sum / denominator, rel_tol=1e-10, abs_tol=1e-12),
            "Saved conditional amplitude mean differs from complete candidate support.")
    for candidate in candidates:
        attached = {}
        for kind, field in (("onset", "onset_time_s"), ("peak", "time_s"), ("recovery", "recovery_time_s")):
            time = candidate[field]
            if time is None: continue
            point = anchors.get(time)
            require(point is not None and point["retained"], "A candidate endpoint does not match an exact retained original sample.")
            attached[kind] = point
            markers.append(dict(candidate_table_row_index=candidate["table_row_index"], kind=kind, time_s=time, phasic_us=point["phasic_us"],
                                source_sample_index=point["source_sample_index"], retained=True, in_view=lower <= Decimal(str(time)) <= upper))
        peak = attached["peak"]
        require(peak["source_sample_index"] == candidate["source_peak_sample"] and peak["phasic_us"] == candidate["peak_height_us"], "The candidate peak changed its exact source sample or phasic height.")
        if "onset" in attached:
            onset = attached["onset"]
            require((candidate["amplitude_us"] is None or math.isclose(peak["phasic_us"] - onset["phasic_us"], candidate["amplitude_us"], rel_tol=1e-12, abs_tol=1e-12)) and
                    math.isclose((peak["source_sample_index"] - onset["source_sample_index"]) / fs, candidate["rise_time_s"], rel_tol=1e-12, abs_tol=1e-12), "Saved onset-to-peak amplitude or rise time differs from exact samples.")
        if "recovery" in attached:
            require(math.isclose((attached["recovery"]["source_sample_index"] - peak["source_sample_index"]) / fs, candidate["recovery_time_from_peak_s"], rel_tol=1e-12, abs_tol=1e-12), "Saved recovery timing differs from exact sample indices.")
    counts.update(selected_samples=len(samples), selected_candidates=len(candidates), retained_samples=sum(r["retained"] for r in samples), excluded_samples=sum(not r["retained"] for r in samples))
    directory = Path(request["export_directory"])
    require(directory.is_dir() and not directory.is_symlink(), "Choose an existing owned export directory.")
    sample_fields = ("table_id", "table_row_index", "source_sample_index", "time_s", *COMPONENTS, "retained")
    candidate_fields = ("table_id", "table_row_index", *EVENT_FIELDS)
    marker_fields = ("candidate_table_row_index", "kind", "time_s", "phasic_us", "source_sample_index", "retained", "in_view")
    exports = [export_csv(directory, name, fields, rows) for name, fields, rows in (
        ("eda-samples.csv", sample_fields, samples), ("eda-candidates.csv", candidate_fields, candidates), ("eda-markers.csv", marker_fields, markers))]
    for source in sources: check_source(source)
    result = dict(schema="brohn-eda-continuous-review/1.0", status="available" if samples else "no_processed_samples", binding=binding,
        selection=selection, recording=recording, parameters=parameters, features=features, unit="uS", raw_available=False,
        counts=counts, candidates=candidates, markers=markers, series={k: preview(samples, k) for k in COMPONENTS}, rows=samples[:50],
        source_tables=list(selected_tables.values()), verification=verification, exports=exports,
        display_policy="Closed source-time sample window; exact saved clean, tonic and phasic values. Envelopes retain actual endpoints/extrema and separate retained/excluded runs. Candidates intersect the window through known onset-to-recovery support, falling back to the peak only where an endpoint is unavailable.",
        limitations=["Continuous candidates have no stimulus attribution; this view does not create event-related responses or infer emotion.",
            "The saved relative-prominence threshold is dimensionless, not an absolute conductance threshold or a horizontal uS line.",
            "Missing onsets/recoveries remain unavailable. Conditional amplitude summaries use only candidates with a supported onset.",
            "Complete raw source samples were not retained in these processed tables; use the original dataset download. No raw overlay is reconstructed.",
            "No filtering, detection, imputation, decomposition or whole-segment scoring is repeated for the selected viewport."])
    require(len(json.dumps(result, ensure_ascii=True, allow_nan=False).encode()) <= MAX_JSON, "The complete EDA review exceeds its document bound; narrow the window.")
    return result

def load_request(path):
    require(path.is_file() and path.stat().st_size <= 1024**2, "The EDA-review request exceeds its bound.")
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
        require(not output.exists(), "The EDA-review output already exists.")
        result = review(load_request(Path(args.request)))
        with output.open("x", encoding="utf-8") as stream: json.dump(result, stream, ensure_ascii=True, allow_nan=False, separators=(",", ":"))
    except Exception as error:
        if not output.exists():
            with output.open("x", encoding="utf-8") as stream: json.dump({"status": "error", "error": {"message": str(error)[:2000]}}, stream)
        sys.exit(1)
