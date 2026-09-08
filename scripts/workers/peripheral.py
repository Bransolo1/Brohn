"""Calibrated temperature/tri-axial acceleration descriptions, never state inference.

Original recipes; NumPy 2.5.3. Full typed artifacts reuse the existing audited
writer, but no physiology cleaner, imputation or event detector is substituted.
"""
from __future__ import annotations
import argparse
import csv
from decimal import Decimal, InvalidOperation
import hashlib
import importlib.util
import json
import math
from pathlib import Path
import re
import sys

import numpy as np

MAX_BYTES = 128 * 1024**2
MAX_ROWS = 1000000
MAX_RECORDINGS = 500
MAX_SEGMENTS = 2000
MAX_PREVIEW = 2000
G0 = 9.80665
TIME = {"s": Decimal(1), "ms": Decimal(".001"), "us": Decimal(".000001"), "ns": Decimal(".000000001")}
RECIPES = {"temperature": "temperature-calibrated-descriptive/1.0", "movement": "acceleration-calibrated-triaxial/1.0"}
GROUPS = ("participant", "session", "condition", "exposure", "segment")
NUMBER = re.compile(r"^[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?$")
HEX = re.compile(r"^[a-f0-9]{64}$")


class InputError(ValueError): pass


def require(condition, message):
    if not condition: raise InputError(message)


def text(value, maximum=4000):
    return isinstance(value, str) and bool(value.strip()) and len(value.encode("utf-8")) <= maximum


def numeric(value, name, low=-1e12, high=1e12):
    require(isinstance(value, (float, int)) and not isinstance(value, bool) and math.isfinite(value) and low <= value <= high,
            f"{name} must be a finite number between {low} and {high}.")
    return float(value)


def fields(value, required, optional=(), label="Record"):
    require(isinstance(value, dict) and set(required) <= set(value) and not set(value)-set(required)-set(optional), f"{label} has missing or unsupported fields.")


def digest_file(path):
    digest = hashlib.sha256()
    with Path(path).open("rb") as source:
        for block in iter(lambda: source.read(1024**2), b""): digest.update(block)
    return digest.hexdigest()


def json_bytes(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True, allow_nan=False).encode("ascii")


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, "Duplicate worker request object key.")
        result[key] = value
    return result


def validate(modality, m, supplied=None):
    require(modality in RECIPES, "This worker supports calibrated temperature or tri-axial acceleration only; EOG needs its own qualified montage/detector profile.")
    required = {"time_column", "time_unit", "sampling_rate", "value_columns", "unit", "origin", "origin_statement", "calibration_source", "sensor_site", "acquisition_filters"}
    optional = {f"{g}_column" for g in GROUPS} | {"timestamp_tolerance_s", "parameters"}
    if modality == "movement": required |= {"axis_labels", "gravity_policy"}
    else: required.add("recording_conditions")
    fields(m, required, optional, "Peripheral source mapping")
    for key in ("time_column", "origin_statement", "calibration_source", "sensor_site", "acquisition_filters"):
        require(text(m[key], 500 if key == "time_column" else 4000), f"Declare {key}; units alone do not establish calibration, placement or filtering.")
    if modality == "temperature": require(text(m["recording_conditions"]), "Describe temperature recording conditions and settling time; explicitly state unknown when unavailable.")
    require(m["origin"] in {"sample", "preview", "pilot", "live", "imported"}, "Declare actual immutable source origin.")
    count = 1 if modality == "temperature" else 3
    columns = m["value_columns"]
    require(isinstance(columns, list) and len(columns) == count and all(text(c, 500) for c in columns) and len(set(columns)) == count,
            f"Select exactly {count} distinct channel(s); movement order is source x, y, z.")
    groups = {f"{g}_id": m[f"{g}_column"] for g in GROUPS if m.get(f"{g}_column") is not None}
    require(all(text(c, 500) for c in groups.values()) and (("participant_id" in groups) == ("session_id" in groups)),
            "Map participant and session together; each declared grouping column needs nonempty source identities.")
    selected = [m["time_column"], *columns, *groups.values()]
    require(len(selected) == len(set(selected)), "Time, signal and grouping columns must be distinct.")
    fs = numeric(m["sampling_rate"], "sampling_rate", .1, 1000 if modality == "temperature" else 10000)
    require(m["time_unit"] in {*TIME, "sample"}, "Declare time_unit s, ms, us, ns or sample.")
    tolerance = numeric(m.get("timestamp_tolerance_s", .02/fs), "timestamp_tolerance_s", 0, .25/fs)
    require(m["unit"] in ({"degC", "K", "degF"} if modality == "temperature" else {"g", "m/s2"}), "Select calibrated physical units; raw counts/voltage are not calibrated temperature or acceleration.")
    if modality == "movement":
        require(isinstance(m["axis_labels"], list) and len(m["axis_labels"]) == 3 and all(text(v, 500) for v in m["axis_labels"]) and len(set(m["axis_labels"])) == 3, "Describe the distinct signed source x/y/z axes in their recorded order.")
        require(m["gravity_policy"] in {"included", "removed"}, "Declare whether source acceleration includes gravity or was already gravity-removed by acquisition.")
    p = {"recipe": RECIPES[modality], "minimum_duration_s": max(1.0, 1/fs), "threshold": None}
    if modality == "movement": p["enmo"] = "disabled"
    supplied = m.get("parameters", {}) if supplied is None else supplied
    fields(supplied, (), p, "Peripheral recipe settings")
    p.update(supplied)
    require(p["recipe"] == RECIPES[modality], "The selected peripheral recipe is not implemented.")
    numeric(p["minimum_duration_s"], "minimum_duration_s", 1/fs, 86400)
    if modality == "movement":
        require(p["enmo"] in {"disabled", "untruncated", "zero_truncated"}, "Choose explicit ENMO output handling or disable it.")
        require(p["enmo"] == "disabled" or m["gravity_policy"] == "included", "ENMO subtracts one standard g and requires gravity-included source data.")
    if p["threshold"] is not None:
        h = p["threshold"]
        fields(h, ("metric", "direction", "on", "off", "minimum_duration_s", "source"), label="Opt-in threshold excursion")
        metrics = {"temperature_c"} if modality == "temperature" else {"vector_magnitude_ms2", *( ["enmo_g"] if p["enmo"] != "disabled" else [])}
        require(h["metric"] in metrics and h["direction"] in {"above", "below"} and text(h["source"]), "Choose an available metric, direction and threshold rationale.")
        on = numeric(h["on"], "threshold on"); off = numeric(h["off"], "threshold off")
        require(on >= off if h["direction"] == "above" else on <= off, "Threshold hysteresis off boundary must return toward the inactive side.")
        numeric(h["minimum_duration_s"], "threshold minimum duration", 1/fs, 86400)
    return p, groups, fs, tolerance


def convert(raw, modality, unit):
    value = raw.strip()
    if value in {"", "NA", "N/A", "null"}: return None, "missing_value"
    if value.lower() in {"nan", "inf", "+inf", "-inf", "infinity", "+infinity", "-infinity"}: return None, "nonfinite_value"
    require(len(value) <= 200 and NUMBER.fullmatch(value), "A selected signal cell is neither numeric nor an explicit missing/nonfinite token; text and booleans are not measurements.")
    number = float(value)
    if not math.isfinite(number): return None, "nonfinite_value"
    if modality == "temperature":
        number = number if unit == "degC" else number-273.15 if unit == "K" else (number-32)/1.8
        if number < -273.15: return None, "below_absolute_zero"
    elif unit == "g": number *= G0
    require(math.isfinite(number) and abs(number) <= 1e9, "Converted amplitude exceeds the bounded numeric range; review units/calibration.")
    return number, None


def read_recordings(path, source_format, m, modality, groups, fs, tolerance):
    factor = Decimal(1)/Decimal(str(fs)) if m["time_unit"] == "sample" else TIME[m["time_unit"]]
    recordings = []; current = None; previous_key = None; count = 0; gaps = 0; missing_duration = 0.0
    csv.field_size_limit(16000)
    with Path(path).open("r", encoding="utf-8-sig", newline="") as stream:
        reader = csv.DictReader(stream, delimiter="\t" if source_format == "tsv" else ",")
        header = reader.fieldnames
        required = {m["time_column"], *m["value_columns"], *groups.values()}
        require(header and len(header) <= 1024 and len(header) == len(set(header)) and all(text(v, 500) for v in header) and required <= set(header), "Source header needs unique named columns including every mapped field.")
        for row in reader:
            count += 1; require(count <= MAX_ROWS, "Peripheral source exceeds the one-million-row bound; split explicitly without truncation.")
            require(None not in row and all(v is not None for v in row.values()), f"Source row {count} has an inconsistent field count.")
            key = tuple(row[column] for column in groups.values())
            require(all(text(v, 240) and v not in {"NA", "N/A", "null"} for v in key), f"Source row {count} has an absent declared identity.")
            raw_time = row[m["time_column"]]
            require(len(raw_time) <= 200 and NUMBER.fullmatch(raw_time.strip()), f"Source row {count} needs an original finite numeric timestamp.")
            try: timestamp = Decimal(raw_time.strip())
            except InvalidOperation as error: raise InputError("Invalid source timestamp.") from error
            require(timestamp.is_finite() and abs(timestamp) <= Decimal("1e30"), "Source clock exceeds its finite decimal bound.")
            if m["time_unit"] == "sample": require(timestamp == timestamp.to_integral_value(), "Sample-index timestamps must be whole numbers.")
            if current is None or key != previous_key:
                require(len(recordings) < MAX_RECORDINGS, "Too many contiguous source groups for one job.")
                current = {"id": f"recording-{len(recordings)+1}", "group": dict(zip(groups, key)), "source_time_origin": raw_time,
                           "origin_decimal": timestamp, "rows": []}
                recordings.append(current); previous_key = key
            relative = float((timestamp-current["origin_decimal"])*factor)
            require(math.isfinite(relative) and 0 <= relative <= 1e9, "Relative recording time exceeds its supported range.")
            gap = False
            if current["rows"]:
                delta_exact = (timestamp-current["rows"][-1]["decimal"])*factor
                require(delta_exact > 0, "Time is duplicated/reversed within an undeclared segment. Map the recorded segment/reset column; rows are never sorted.")
                delta = float(delta_exact)
                gap = delta > 1.5/fs
                require(gap or abs(delta-1/fs) <= tolerance+1e-12, "Source intervals disagree with the declared rate; no resampling is applied.")
                require(relative > current["rows"][-1]["time_s"], "Relative float clock loses adjacent-sample precision; split the source into explicit shorter segments.")
                if gap: gaps += 1; missing_duration += delta-1/fs
            values = [convert(row[column], modality, m["unit"]) for column in m["value_columns"]]
            reasons = sorted(set(reason for _, reason in values if reason))
            current["rows"].append({"source_row": count, "source_timestamp": raw_time, "decimal": timestamp, "time_s": relative,
                                    "values": [v for v, _ in values], "valid_sample": not reasons,
                                    "reason": ";".join(reasons) or None, "gap_before": gap})
    require(count > 0, "Source recording contains no samples.")
    return recordings, {"source_rows": count, "time_gap_count": gaps, "missing_nominal_interval_s": missing_duration}


def excursions(times, values, rows, p):
    if p is None: return []
    above = p["direction"] == "above"
    active = False; start = None; events = []
    def finish(last, recovered):
        duration = float(times[last]-times[start])
        if duration+1e-12 < p["minimum_duration_s"]: return
        segment = values[start:last+1]
        events.append({"type": "declared_threshold_excursion", "metric": p["metric"], "direction": p["direction"],
            "time_s": float(times[start]), "end_time_s": float(times[last]), "observed_span_s": duration,
            "recovery_time_s": float(times[recovered]) if recovered is not None else None,
            "extreme": float(max(segment) if above else min(segment)), "source_start_row": rows[start]["source_row"],
            "source_end_row": rows[last]["source_row"], "left_censored": start == 0, "right_censored": recovered is None})
    for i, value in enumerate(values):
        if not active and (value >= p["on"] if above else value <= p["on"]): active = True; start = i
        elif active and (value < p["off"] if above else value > p["off"]): finish(i-1, i); active = False
    if active: finish(len(times)-1, None)
    return events


def metrics(rows, modality, p):
    t = np.asarray([r["time_s"] for r in rows], float)
    x = np.asarray([r["values"] for r in rows], float)
    features = []; derived = {}; span = float(t[-1]-t[0]); unit = "degC" if modality == "temperature" else "m/s2"
    def f(name, value, units=unit, **details):
        require(value is None or math.isfinite(float(value)), "Descriptive calculation returned a nonfinite result.")
        features.append({"name": name, "value": float(value) if value is not None else None, "unit": units, "scope": "recording", **details})
    if modality == "temperature":
        values = x[:, 0]; centered = t-t.mean()
        f("temperature_mean", values.mean()); f("temperature_sd", values.std(ddof=1), denominator="n_minus_one")
        f("temperature_minimum", values.min()); f("temperature_maximum", values.max()); f("temperature_range", np.ptp(values))
        f("temperature_first", values[0]); f("temperature_last", values[-1]); f("temperature_endpoint_change", values[-1]-values[0])
        f("temperature_linear_slope", np.dot(centered, values-values.mean())/np.dot(centered, centered)*60, "degC/min")
        f("temperature_time_weighted_mean", np.trapezoid(values, t)/span, integration="trapezoids over observed adjacent samples only")
        derived["temperature_c"] = values
    else:
        for axis, values in zip("xyz", x.T):
            f(f"acceleration_{axis}_mean", values.mean()); f(f"acceleration_{axis}_sd", values.std(ddof=1), denominator="n_minus_one")
            f(f"acceleration_{axis}_rms", np.sqrt(np.mean(values**2)))
        magnitude = np.linalg.norm(x, axis=1); derived["vector_magnitude_ms2"] = magnitude
        f("acceleration_magnitude_mean", magnitude.mean()); f("acceleration_magnitude_rms", np.sqrt(np.mean(magnitude**2)))
        f("acceleration_magnitude_maximum", magnitude.max())
        differences = np.linalg.norm(np.diff(x, axis=0)/np.diff(t)[:, None], axis=1)
        f("acceleration_vector_derivative_rms", np.sqrt(np.mean(differences**2)), "m/s3", denominator="valid adjacent vector differences", interval_count=len(differences))
        derived["vector_derivative_ms3"] = [None, *[float(v) for v in differences]]
        if p["enmo"] != "disabled":
            enmo = magnitude/G0-1
            if p["enmo"] == "zero_truncated": enmo = np.maximum(enmo, 0)
            derived["enmo_g"] = enmo
            f("enmo_mean", enmo.mean(), "g", negative_policy=p["enmo"])
    events = excursions(t, derived[p["threshold"]["metric"]], rows, p["threshold"]) if p["threshold"] else []
    f("supported_sample_count", len(rows), "samples"); f("supported_observed_span", span, "s")
    if p["threshold"]:
        f("declared_threshold_excursion_count", len(events), "events")
        f("declared_threshold_observed_span", sum(e["observed_span_s"] for e in events), "s")
    for index, row in enumerate(rows):
        for name, values in derived.items(): row[name] = None if values[index] is None else float(values[index])
    return features, events


def artifact_module():
    path = Path(__file__).with_name("physiology_artifacts.py")
    spec = importlib.util.spec_from_file_location("brohn_peripheral_artifacts", path)
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    return module, path


def run(request):
    fields(request, ("schema", "operation", "modality", "format", "source_path", "source_hash", "metadata"), ("parameters", "artifact_directory"), "Peripheral worker request")
    require(request["schema"] == "brohn-worker-request/1.0" and request["operation"] == "peripheral", "Unsupported peripheral worker envelope.")
    require(np.__version__ == "2.5.3", "This recipe requires the prepared NumPy 2.5.3 methods environment.")
    modality, m = request["modality"], request["metadata"]
    p, groups, fs, tolerance = validate(modality, m, request.get("parameters"))
    if "parameters" in request and "parameters" in m: require(p == validate(modality, m, m["parameters"])[0], "Top-level and mapped parameters conflict.")
    require(request["format"] in {"csv", "tsv"}, "Peripheral analysis currently accepts explicitly mapped CSV or TSV only.")
    path = Path(request["source_path"])
    require(path.is_file() and 0 < path.stat().st_size <= MAX_BYTES, "Original peripheral source is absent, empty or exceeds 128 MiB.")
    require(isinstance(request["source_hash"], str) and HEX.fullmatch(request["source_hash"]) and digest_file(path) == request["source_hash"], "Original source bytes do not match the pinned SHA-256.")
    recordings, quality = read_recordings(path, request["format"], m, modality, groups, fs, tolerance)
    require(digest_file(path) == request["source_hash"], "Original source changed while its data were read.")
    module, writer_path = artifact_module()
    engine = {"name": "Brohn peripheral descriptive", "version": "1.0.0", "numpy": np.__version__,
              "worker_sha256": digest_file(__file__), "artifact_writer_sha256": digest_file(writer_path)}
    parameters = {"recipe": p, "mapping": m, "effective_timestamp_tolerance_s": tolerance,
                  "standard_gravity_ms2": G0, "filtering": "none", "imputation": "none", "resampling": "none",
                  "segment_duration": "last observed timestamp minus first; no extrapolated final sample cell",
                  "threshold_timing": "sample-indexed boundaries; censored at segment edge; no interpolated crossings"}
    output = {"schema": "brohn-worker-result/1.0", "modality": modality, "operation": "peripheral", "engine": engine,
              "source": {"sha256": request["source_hash"], "origin": m["origin"], "format": request["format"]},
              "parameters": parameters, "features": [], "events": [], "series": [], "recordings": [], "segments": [], "quality": quality, "artifacts": [],
              "limitations": ["Calibrated imported channel descriptions are not arousal, stress, attention, emotion, core body temperature, gait or physical activity intensity classifications.",
                  "Calibration, signed sensor placement and acquisition filtering are researcher declarations; no physical device or calibration accuracy was independently established.",
                  "Each contiguous identity/segment, missing span and clock gap is separate. No experimental baseline, condition effect, participant pooling, clock fusion or missing-value imputation is inferred.",
                  "Source temperature endpoint change is not a protocol baseline contrast. Acceleration magnitude/vector derivative may include gravity, rotation and sensor noise; they are not displacement or translation estimates.",
                  "ENMO, when explicitly enabled, subtracts one standard g from vector magnitude with its named negative-value policy. It does not perfectly separate gravity from movement.",
                  "Optional threshold excursions are protocol-declared operational events with sample timing and censoring evidence, not a validated physiological detector.",
                  "The minimum-duration setting is a computational support requirement, not scientific validation of the recording length. Sensor clipping and environmental confounds require source review."]}
    writers = None
    if request.get("artifact_directory"):
        writers = module.ArtifactSet(request["artifact_directory"], {"source_sha256": request["source_hash"], "engine": engine,
            "operation": "peripheral", "origin": m["origin"], "parameters": parameters})
    valid_count = usable_count = event_count = 0; supported_span = 0.0
    try:
        for recording in recordings:
            rows = recording["rows"]; identity = {"recording_id": recording["id"], "group": recording["group"], "channel": m["value_columns"][0] if modality == "temperature" else "source-xyz-vector"}
            start = 0; record_events = []
            while start < len(rows):
                end = start+1; valid = rows[start]["valid_sample"]
                while end < len(rows) and rows[end]["valid_sample"] == valid and not rows[end]["gap_before"]: end += 1
                require(len(output["segments"]) < MAX_SEGMENTS, "More than 2,000 support segments; split explicitly before analysis.")
                subset = rows[start:end]; span = subset[-1]["time_s"]-subset[0]["time_s"]
                eligible = valid and len(subset) >= 2 and span+1e-12 >= p["minimum_duration_s"]
                sid = f"support-{len(output['segments'])+1}"
                reason = None if eligible else "insufficient_contiguous_duration" if valid else "selected_channel_missing_or_invalid"
                support = {**identity, "support_segment_id": sid, "status": "usable" if eligible else "unavailable", "reason": reason,
                    "source_row_start": subset[0]["source_row"], "source_row_end": subset[-1]["source_row"], "sample_count": len(subset),
                    "time_s": subset[0]["time_s"], "end_time_s": subset[-1]["time_s"], "observed_span_s": span,
                    "source_time_origin": recording["source_time_origin"], "source_time_unit": m["time_unit"],
                    "gap_before": subset[0]["gap_before"], "minimum_duration_s": p["minimum_duration_s"]}
                output["segments"].append(support)
                if valid: valid_count += len(subset)
                for row in subset:
                    row["support_segment_id"] = sid; row["analysis_eligible"] = eligible
                    row["retained"] = eligible; row["source_sample_index"] = row["source_row"]-1
                    if valid and not eligible: row["reason"] = reason
                if eligible:
                    usable_count += len(subset); supported_span += span
                    features, events = metrics(subset, modality, p)
                    output["features"].extend({**item, **identity, "support_segment_id": sid, "support": {"sample_count": len(subset), "observed_span_s": span}} for item in features)
                    record_events.extend({**event, "support_segment_id": sid} for event in events)
                    output["events"].extend({**event, **identity, "support_segment_id": sid} for event in events[:max(0, MAX_PREVIEW-len(output["events"]))])
                    event_count += len(events)
                start = end
            require(len(output["features"]) <= 40000, "Peripheral feature table exceeds its bounded output; split the source explicitly.")
            names = ["temperature_c"] if modality == "temperature" else ["acceleration_x_ms2", "acceleration_y_ms2", "acceleration_z_ms2", "vector_magnitude_ms2", "vector_derivative_ms3", *(["enmo_g"] if p["enmo"] != "disabled" else [])]
            for row in rows:
                if modality == "temperature": row["temperature_c"] = row["values"][0]
                else:
                    for axis, value in zip("xyz", row["values"]): row[f"acceleration_{axis}_ms2"] = value
                item = {key: row.get(key) for key in ["source_row", "source_sample_index", "source_timestamp", "time_s", "support_segment_id", "valid_sample", "analysis_eligible", "retained", "reason", *names]}
                row["artifact_row"] = item
                if len(output["series"]) < MAX_PREVIEW: output["series"].append({**identity, **item})
            output["recordings"].append({**identity, "source_time_origin": recording["source_time_origin"], "source_time_unit": m["time_unit"],
                "source_row_start": rows[0]["source_row"], "source_row_end": rows[-1]["source_row"], "sample_count": len(rows)})
            if writers:
                col = module._column
                columns = [col("source_row", "integer", "one_based_data_row", role="index"), col("source_sample_index", "integer", "zero_based_data_row", role="index"), col("source_timestamp", "string", None, role="source_clock_text"),
                    col("time_s", "float64", "s", role="coordinate"), col("support_segment_id", "string", None, role="identity"),
                    col("valid_sample", "boolean", None, role="support"), col("analysis_eligible", "boolean", None, role="support"), col("retained", "boolean", None, role="support"), col("reason", "string", None, True, role="support")]
                columns += [col(name, "float64", "degC" if modality == "temperature" else "g" if name == "enmo_g" else "m/s3" if name == "vector_derivative_ms3" else "m/s2", True) for name in names]
                coordinate = {"axis": "time", "reference": "seconds relative to this contiguous source group's exact clock origin",
                    "source_time_origin": recording["source_time_origin"], "source_time_unit": m["time_unit"]}
                support = {"source_channel_order": m["value_columns"], "source_rows_retained_in_full": True,
                           "listwise_selected_channel_validity": True, "source_row_index": "one-based data row excluding header",
                           "retained_definition": "identical to analysis_eligible: valid selected channels and sufficient contiguous duration",
                           "source": {"sampling_rate": fs, "channel_quality": {"timestamp_tolerance_s": tolerance},
                               "source_row_start": rows[0]["source_row"]-1, "source_row_end_exclusive": rows[-1]["source_row"],
                               "source_time_origin": recording["source_time_origin"], "unit": "degC" if modality == "temperature" else "m/s2"}}
                writers.series.write_table(recording["id"]+"-samples", identity, columns, coordinate, support,
                                           (row["artifact_row"] for row in rows), len(rows))
                event_columns = [col(name, "string", None, role="identity" if name == "support_segment_id" else "label") for name in ("type", "metric", "direction", "support_segment_id")]
                event_columns += [col(name, "float64", "s", name == "recovery_time_s", role="coordinate" if name == "time_s" else "derived_event") for name in ("time_s", "end_time_s", "observed_span_s", "recovery_time_s")]
                event_unit = "degC" if modality == "temperature" else "g" if p["threshold"] and p["threshold"]["metric"] == "enmo_g" else "m/s2"
                event_columns += [col("extreme", "float64", event_unit), *[col(name, "integer", "one_based_data_row", role="index") for name in ("source_start_row", "source_end_row")],
                    col("left_censored", "boolean", None, role="support"), col("right_censored", "boolean", None, role="support")]
                writers.events.write_table(recording["id"]+"-events", identity, event_columns, {**coordinate, "axis": "event"},
                    {**support, "threshold": p["threshold"], "disabled_detector_is_not_zero_physiological_events": p["threshold"] is None}, record_events, len(record_events))
        quality.update(valid_samples=valid_count, invalid_samples=quality["source_rows"]-valid_count, usable_samples=usable_count,
            insufficient_duration_samples=valid_count-usable_count, supported_observed_span_s=supported_span, recording_count=len(recordings),
            support_segment_count=len(output["segments"]), event_count=event_count if p["threshold"] and usable_count else None,
            event_detection_requested=p["threshold"] is not None, preview_rows=len(output["series"]), preview_events=len(output["events"]),
            preview_policy="first 2000 source rows/events; full artifacts retain every row/event; features use full eligible support",
            usable=usable_count > 0, participant_count=None, scientifically_qualified=False, physical_device_qualified=False,
            complete_processed_artifacts=writers is not None)
        if writers: output["artifacts"] = writers.finish()
        require(len(json_bytes(output)) <= 16*1024**2, "Compact peripheral result exceeds 16 MiB; split source explicitly.")
        return output
    except BaseException:
        if writers: writers.abort()
        raise


def main():
    parser = argparse.ArgumentParser(); parser.add_argument("--request", required=True); parser.add_argument("--output", required=True)
    args = parser.parse_args(); output_path = Path(args.output); output_safe = False; request = None
    try:
        request_path = Path(args.request)
        require(output_path.resolve() != request_path.resolve(), "Worker output must not overwrite its request.")
        require(request_path.is_file() and request_path.stat().st_size <= 1024**2, "Request JSON exceeds 1 MiB or is unavailable.")
        request = json.loads(request_path.read_text(encoding="utf-8-sig"), object_pairs_hook=unique_object,
                            parse_constant=lambda value: (_ for _ in ()).throw(InputError("Request contains nonfinite JSON.")))
        require(output_path.resolve() not in {request_path.resolve(), Path(request.get("source_path", "")).resolve()}, "Worker output must not overwrite source or request.")
        output_safe = True
        result = run(request); code = 0
    except Exception as error:
        result = {"schema": "brohn-worker-result/1.0", "operation": "peripheral", "status": "error", "error": {"type": type(error).__name__, "message": str(error)},
                  "modality": request.get("modality") if isinstance(request, dict) else None,
                  "features": [], "events": [], "series": [], "artifacts": [], "quality": {"usable": False}}
        code = 1
    if output_safe: output_path.write_bytes(json_bytes(result))
    else: sys.stderr.write(json_bytes(result).decode("ascii")+"\n")
    return code


if __name__ == "__main__": sys.exit(main())
