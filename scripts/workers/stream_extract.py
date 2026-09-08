"""Explicit analogue-channel curation from a pinned canonical stream JSONL.

Only standard-library code is used. No clock correction, resampling, inference,
device discovery, or scientific scoring is performed here.
"""
from __future__ import annotations
import argparse
import csv
from decimal import Decimal, InvalidOperation, getcontext
import hashlib
import json
import math
import os
from pathlib import Path
import re
import sys
import tempfile

getcontext().prec = 300
MAX_ROWS = 2_000_000
MAX_VALUES = 20_000_000
MAX_BYTES = 4 * 1024**3
MAX_CSV = 512 * 1024**2
MAX_SEGMENTS = 2000
TIME = {"s": Decimal(1), "ms": Decimal(".001"), "us": Decimal(".000001"), "ns": Decimal(".000000001")}
UNITS = {
    "eeg": {"V": ("voltage", Decimal(1)), "mV": ("voltage", Decimal(".001")), "uV": ("voltage", Decimal(".000001"))},
    "ecg": {"V": ("voltage", Decimal(1)), "mV": ("voltage", Decimal(".001")), "uV": ("voltage", Decimal(".000001"))},
    "emg": {"V": ("voltage", Decimal(1)), "mV": ("voltage", Decimal(".001")), "uV": ("voltage", Decimal(".000001"))},
    "eda": {"S": ("conductance", Decimal(1)), "uS": ("conductance", Decimal(".000001"))},
    "ppg": {"a.u.": ("arbitrary", Decimal(1)), "V": ("voltage", Decimal(1)), "mV": ("voltage", Decimal(".001"))},
    "respiration": {"a.u.": ("arbitrary", Decimal(1)), "V": ("voltage", Decimal(1)), "mV": ("voltage", Decimal(".001")), "L": ("volume", Decimal(1)), "L/s": ("flow", Decimal(1))},
}
NUMERIC_TYPES = {"float32", "float64", "int8", "int16", "int32", "int64"}
IDENTITIES = ("participant_id", "session_id", "condition_id", "exposure_id")
LEADING = ["brohn_time_s", "brohn_segment_id", "brohn_participant_id", "brohn_session_id", "brohn_condition_id", "brohn_exposure_id",
           "source_sequence", "source_segment_id", "source_clock_id", "source_timestamp", "source_timestamp_unit",
           "source_timestamp_ieee754_le_hex", "source_reconstructed_timestamp", "source_identity_json"]


class InputError(ValueError):
    pass


def require(value, message):
    if not value:
        raise InputError(message)


def fields(value, keys, optional=()):
    require(isinstance(value, dict) and set(keys) <= set(value) <= set(keys) | set(optional), "Missing or unregistered request fields.")


def text(value, name, maximum=1000, nullable=False):
    if value is None and nullable:
        return None
    require(isinstance(value, str) and bool(value.strip()) and len(value.encode("utf-8")) <= maximum, name + " must be bounded nonempty text.")
    return value


def decimal(value, name):
    require(isinstance(value, str) and len(value) <= 120 and re.fullmatch(r"[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?", value), name + " must be an exact decimal string.")
    try:
        number = Decimal(value)
    except InvalidOperation as error:
        raise InputError(name + " is not a finite decimal.") from error
    require(number.is_finite() and abs(number.adjusted()) <= 100, name + " is outside the bounded decimal range.")
    return number


def digest(path):
    value = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for block in iter(lambda: stream.read(1024**2), b""):
            value.update(block)
    return value.hexdigest()


def pairs(items):
    result = {}
    for key, value in items:
        require(key not in result, "Duplicate JSON key.")
        result[key] = value
    return result


def parse(line):
    return json.loads(line, object_pairs_hook=pairs, parse_constant=lambda x: (_ for _ in ()).throw(InputError("Nonfinite JSON literal.")))


def canonical(value):
    return json.dumps(value, ensure_ascii=True, allow_nan=False, separators=(",", ":"))


def unit(value):
    return value.replace("\u00b5", "u").replace("\u03bc", "u") if isinstance(value, str) else value


def validate(request):
    fields(request, ("schema", "operation", "source_path", "source_hash", "stream", "selection", "output_directory"))
    require(request["schema"] == "brohn-stream-extract-request/1.0" and request["operation"] == "extract_stream", "Unsupported stream extraction request.")
    source = Path(text(request["source_path"], "source_path", 4096)).resolve()
    require(source.is_file() and source.stat().st_size <= MAX_BYTES, "Canonical source is missing or exceeds 4 GiB.")
    require(re.fullmatch(r"[a-f0-9]{64}", request["source_hash"] or "") and digest(source) == request["source_hash"], "Canonical source failed its pinned SHA-256 check.")
    stream = request["stream"]
    require(isinstance(stream, dict) and stream.get("schema") == "brohn-imported-stream/1.0" and stream.get("kind") == "signal", "Choose a declared analogue signal stream; marker or unclassified streams cannot become measurements.")
    require(isinstance(stream.get("sample_count"), int) and not isinstance(stream["sample_count"], bool) and 0 <= stream["sample_count"] <= MAX_ROWS, "Stream sample count is invalid.")
    selection = request["selection"]
    fields(selection, ("schema", "channel_ids", "modality", "unit", "sampling_rate", "participant_id", "session_id", "origin_statement", "unit_rationale", "confirm_source_units", "confirm_boundaries", "run_analysis"))
    require(selection["schema"] == "brohn-stream-selection/1.0" and selection["modality"] in UNITS, "Select an implemented analogue analysis family.")
    require(selection["confirm_source_units"] is True and selection["confirm_boundaries"] is True, "Confirm source units and the explicit gap/missing-value policy.")
    require(isinstance(selection["run_analysis"], bool), "Automatic analysis choice must be an explicit boolean.")
    text(selection["origin_statement"], "Collection and identity rationale", 4000)
    text(selection["unit_rationale"], "Unit declaration rationale", 4000)
    for name in ("participant_id", "session_id"):
        value = text(selection[name], "Explicit missing " + name + " declaration", 200, nullable=True)
        require(value is None or value not in ("NA", "N/A", "null", "NaN", "nan"), "Do not use a reserved missing value as participant/session identity.")
    selected = selection["channel_ids"]
    require(isinstance(selected, list) and 1 <= len(selected) <= 64 and len(set(selected)) == len(selected) and
            all(isinstance(x, str) and re.fullmatch(r"[A-Za-z][A-Za-z0-9_-]*", x) for x in selected), "Select 1 to 64 distinct declared scalar channels.")
    channels = stream.get("channels")
    require(isinstance(channels, list) and all(isinstance(c, dict) and "id" in c for c in channels) and len({c["id"] for c in channels}) == len(channels), "Source channels are invalid.")
    by_id = {c["id"]: c for c in channels}
    require(set(selected) <= set(by_id), "A selected channel does not belong to this stream.")
    require(stream["sample_count"] * len(selected) <= MAX_VALUES, "Selected measurements exceed the 20-million-value bound.")
    fs = selection["sampling_rate"]
    require(isinstance(fs, (int, float)) and not isinstance(fs, bool) and math.isfinite(fs) and 1 <= fs <= 100000 and fs == stream.get("nominal_srate"),
            "Confirm the source's positive nominal rate exactly. Irregular or absent rates need a separate resampling protocol.")
    target = unit(selection["unit"])
    require(target in UNITS[selection["modality"]], "The declared output unit is unsupported for this analysis family.")
    conversions = []
    for cid in selected:
        channel = by_id[cid]
        require(channel.get("value_type") in NUMERIC_TYPES, "Text, boolean, vector or unsupported channels cannot become scalar measurements.")
        require(channel.get("scale") is None or decimal(channel["scale"], "Source scale") == 1, "This source declares calibration scaling. Supply a separately calibrated source before analogue curation.")
        require(channel.get("offset") is None or decimal(channel["offset"], "Source offset") == 0, "This source declares a calibration offset. Supply a separately calibrated source before analogue curation.")
        declared = unit(channel.get("unit"))
        if declared in (None, ""):
            declared = target
            basis = "researcher_declared_missing_source_unit"
        else:
            basis = "source_declared_unit"
        require(declared in UNITS[selection["modality"]] and UNITS[selection["modality"]][declared][0] == UNITS[selection["modality"]][target][0],
                "Source and reviewed units are incompatible; a calibrated source is required.")
        factor = UNITS[selection["modality"]][declared][1] / UNITS[selection["modality"]][target][1]
        conversions.append({"id": cid, "label": channel.get("label"), "value_type": channel["value_type"], "source_unit": channel.get("unit"),
                            "declared_source_unit": declared, "target_unit": target, "factor": str(factor), "basis": basis})
    clock = stream.get("clock")
    require(isinstance(clock, dict) and clock.get("unit") in (*TIME, "ticks"), "The source clock has no registered seconds conversion.")
    factor = TIME.get(clock["unit"])
    if factor is None:
        factor = decimal(clock.get("seconds_per_tick"), "Source seconds_per_tick")
    require(factor > 0, "Clock tick scale must be positive.")
    directory = Path(text(request["output_directory"], "output_directory", 4096)).resolve()
    require(source != directory and source.parent != directory, "Keep derived artifacts separate from the canonical source directory.")
    directory.mkdir(parents=True, exist_ok=True)
    return source, directory, conversions, factor


def numeric_value(value, kind):
    if kind == "int64":
        require(isinstance(value, str) and re.fullmatch(r"-?\d+", value), "int64 source values must remain exact typed decimal strings.")
        number = int(value)
        require(-(2**63) <= number < 2**63 and abs(number) <= 2**53, "A selected int64 measurement exceeds exact binary64 precision. Preserve it as typed source data; do not round it into analysis.")
        return Decimal(value)
    if kind.startswith("int"):
        bits = int(kind[3:])
        require(isinstance(value, int) and not isinstance(value, bool) and -(2**(bits-1)) <= value < 2**(bits-1), "Declared integer source value changed its type or range.")
        return Decimal(value)
    require(isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value), "Declared floating source value changed its numeric type.")
    require(not isinstance(value, int) or int(float(value)) == value, "Selected floating measurement would lose integer precision.")
    return Decimal(str(value))


def identity(row, selection):
    source = row.get("identity")
    require(isinstance(source, dict) and set(source) <= set(IDENTITIES), "Unexpected source identity fields.")
    result = {}
    for key in IDENTITIES:
        value = source.get(key)
        if value is not None:
            text(value, "Source " + key, 200)
            require(value not in ("NA", "N/A", "null", "NaN", "nan"), "A source identity uses a reserved missing token.")
        if value is None and key in ("participant_id", "session_id"):
            value = selection[key]
        if key in ("participant_id", "session_id"):
            require(value is not None, "A source row has no participant/session identity. Supply explicit missing-identity declarations.")
        result[key] = value
    return result


def extract(request):
    source, directory, conversions, time_factor = validate(request)
    stream, selection = request["stream"], request["selection"]
    fs = Decimal(str(selection["sampling_rate"]))
    interval = Decimal(1) / fs
    tolerance = Decimal(".02") / fs + Decimal(".000000000001")
    columns = LEADING + ["value_" + item["id"] for item in conversions]
    paths = []
    handles = []
    def temporary(suffix):
        f = tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", newline="", dir=directory, suffix=suffix, delete=False)
        paths.append(Path(f.name)); handles.append(f); return f
    csv_file, decisions_file = temporary(".csv"), temporary(".jsonl")
    writer = csv.writer(csv_file); writer.writerow(columns)
    count, included, reconstructed = 0, 0, 0
    reasons_count, channel_missing, segments, preview = {}, {x["id"]: 0 for x in conversions}, [], []
    previous, current = None, None
    complete_conditions, complete_exposures = True, True
    try:
        with source.open("r", encoding="utf-8", newline="") as source_file:
            for line in source_file:
                require(len(line.encode("utf-8")) <= 16*1024**2 and line.endswith("\n"), "Canonical JSONL contains an oversized or incomplete row.")
                row = parse(line); count += 1
                require(count <= MAX_ROWS and isinstance(row, dict) and row.get("sequence") == count and not isinstance(row.get("sequence"), bool) and row.get("stream_id") == stream["id"], "Canonical source sequence or stream identity changed.")
                require(row.get("timestamp_unit") == stream["clock"]["unit"] and isinstance(row.get("reconstructed_timestamp"), bool), "Canonical source clock declaration changed.")
                text(row.get("segment_id"), "Source segment", 200); text(row.get("clock_id"), "Source clock ID", 500)
                group = identity(row, selection)
                values, reasons = {}, []
                stamp = None
                if row.get("timestamp_state") != "observed" or row.get("source_timestamp") is None:
                    reasons.append("missing_nonfinite_or_unanchored_timestamp")
                else:
                    stamp = decimal(row["source_timestamp"], "Original source timestamp")
                require(isinstance(row.get("values"), dict) and isinstance(row.get("value_states"), dict), "Canonical channel values or state evidence is missing.")
                for channel in conversions:
                    cid = channel["id"]
                    require(cid in row["values"] and cid in row["value_states"], "A selected channel is absent from a canonical row.")
                    state, value = row["value_states"][cid], row["values"][cid]
                    require(state in ("observed", "missing", "nan", "positive_infinity", "negative_infinity"), "Unsupported selected-value state.")
                    if state != "observed":
                        require(value is None, "Missing-value state contradicts a retained numeric value.")
                        channel_missing[cid] += 1
                        reasons.append("selected_channel_missing_or_nonfinite")
                    else:
                        require(value is not None, "An observed selected channel cannot be null.")
                        converted = numeric_value(value, channel["value_type"]) * Decimal(channel["factor"])
                        require(math.isfinite(float(converted)), "Declared unit conversion exceeds finite analysis range.")
                        values[cid] = str(converted)
                boundary = []
                if previous is None:
                    boundary.append("first_sample_or_after_exclusion")
                else:
                    if previous["source_segment"] != row["segment_id"]: boundary.append("source_segment_boundary")
                    if previous["clock_id"] != row["clock_id"]: boundary.append("source_clock_boundary")
                    if previous["group"] != group: boundary.append("source_identity_boundary")
                    if not reasons and not boundary:
                        delta = (stamp - previous["stamp"]) * time_factor
                        if delta <= 0: boundary.append("source_clock_reset_or_duplicate")
                        elif delta > interval * Decimal("1.5"): boundary.append("source_sampling_gap")
                        else: require(abs(delta-interval) <= tolerance, "Source sampling is irregular beyond the named 2% interval tolerance. This curation does not resample or fabricate timestamps.")
                decision = {"source_sequence": count, "source_segment_id": row["segment_id"], "source_clock_id": row["clock_id"],
                            "source_timestamp": row.get("source_timestamp"), "source_timestamp_unit": row["timestamp_unit"], "source_identity": row["identity"],
                            "disposition": "excluded" if reasons else "included", "reasons": sorted(set(reasons)), "brohn_segment_id": None}
                if reasons:
                    for reason in set(reasons): reasons_count[reason] = reasons_count.get(reason, 0)+1
                    previous = None
                else:
                    if boundary:
                        require(len(segments) < MAX_SEGMENTS, "More than 2,000 independent segments; explicitly split the recording before analysis.")
                        current = {"id": "segment-"+str(len(segments)+1), "first_source_sequence": count, "last_source_sequence": count,
                                   "sample_count": 0, "source_clock_id": row["clock_id"], "source_start_timestamp": row["source_timestamp"],
                                   "source_end_timestamp": row["source_timestamp"], "source_timestamp_unit": row["timestamp_unit"],
                                   "group": group, "boundary_reasons": boundary, "duration_s": "0"}
                        segments.append(current)
                    elapsed = (stamp - Decimal(current["source_start_timestamp"])) * time_factor
                    finite_elapsed = float(elapsed)
                    require(math.isfinite(finite_elapsed) and (current["sample_count"] == 0 or finite_elapsed > float(current["duration_s"])), "Relative clock conversion loses increasing timestamp precision.")
                    current["last_source_sequence"] = count; current["sample_count"] += 1
                    current["source_end_timestamp"] = row["source_timestamp"]; current["duration_s"] = str(elapsed)
                    included += 1; reconstructed += int(row["reconstructed_timestamp"])
                    complete_conditions = complete_conditions and group["condition_id"] is not None
                    complete_exposures = complete_exposures and group["exposure_id"] is not None
                    output = [str(elapsed), current["id"], *[group[x] for x in IDENTITIES], count, row["segment_id"], row["clock_id"],
                              row["source_timestamp"], row["timestamp_unit"], row.get("timestamp_ieee754_le_hex"), row["reconstructed_timestamp"], canonical(row["identity"]),
                              *[values[x["id"]] for x in conversions]]
                    writer.writerow(output)
                    decision["brohn_segment_id"] = current["id"]
                    if len(preview) < 20: preview.append(dict(zip(columns, output)))
                    previous = {"source_segment": row["segment_id"], "clock_id": row["clock_id"], "group": group, "stamp": stamp}
                decisions_file.write(canonical(decision)+"\n")
                require(csv_file.tell() <= MAX_CSV and decisions_file.tell() <= MAX_BYTES, "Derived artifacts exceed their explicit bounds; split the source recording.")
        require(count == stream["sample_count"], "Canonical row count disagrees with the pinned manifest.")
        require(digest(source) == request["source_hash"], "Canonical source changed during extraction.")
        for f in handles: f.close()
        for segment in segments: segment["analysis_candidate"] = segment["sample_count"] >= 2
        eligible = any(x["analysis_candidate"] for x in segments)
        result = {"schema": "brohn-stream-extract-result/1.0", "operation": "extract_stream", "status": "extracted" if eligible else "needs_attention",
                  "source": {"sha256": request["source_hash"], "bytes": source.stat().st_size, "stream_id": stream["id"], "sample_count": count},
                  "selection": selection, "parameters": {"recipe": "analogue-stream-curation/1.0", "missing_policy": "listwise_selected_channels",
                      "resampling": False, "clock_correction_applied": False, "nominal_interval_tolerance_fraction": .02,
                      "clock_conversion": "decimal seconds relative to each explicit derived segment", "unit_conversions": conversions},
                  "quality": {"source_rows": count, "included_rows": included, "excluded_rows": count-included, "reason_counts": reasons_count,
                      "missing_by_selected_channel": channel_missing, "segment_count": len(segments), "analysis_candidate_segments": sum(x["analysis_candidate"] for x in segments),
                      "reconstructed_timestamps_included": reconstructed, "source_order_preserved": True, "source_clock_text_preserved": True,
                      "identities_inferred": False, "synchronized": False, "dataset_eligible": eligible},
                  "segments": segments, "preview": preview, "columns": columns,
                  "metadata": {"origin_statement": selection["origin_statement"], "time_column": "brohn_time_s", "time_unit": "s", "segment_column": "brohn_segment_id",
                      "participant_column": "brohn_participant_id", "session_column": "brohn_session_id", "unit": unit(selection["unit"]),
                      "sampling_rate": selection["sampling_rate"], "value_columns": ["value_"+x["id"] for x in conversions]},
                  "limitations": ["Curation prepares a declared numeric input; it does not score a research method or qualify hardware.",
                      "Rows missing any selected channel or an anchored finite timestamp are excluded listwise; every source row and decision remains traceable.",
                      "Original source clocks and correction evidence remain separate; no synchronization or interpolation is applied.",
                      "Method-specific minimum durations, exclusions and analysis eligibility are checked by the selected scientific recipe."], "artifacts": []}
        if included and complete_conditions: result["metadata"]["condition_column"] = "brohn_condition_id"
        if included and complete_exposures: result["metadata"]["exposure_column"] = "brohn_exposure_id"
        for path, kind, suffix, media in zip(paths, ("curated_signal_csv", "curation_decisions_jsonl"), (".csv", ".jsonl"), ("text/csv", "application/x-ndjson")):
            sha = digest(path); target = directory / (kind+"-"+sha+suffix)
            if target.exists(): require(digest(target) == sha, "Existing artifact failed its hash check."); path.unlink()
            else: os.replace(path, target)
            result["artifacts"].append({"kind": kind, "path": str(target), "sha256": sha, "bytes": target.stat().st_size, "media_type": media})
        return result
    finally:
        for f in handles:
            if not f.closed: f.close()
        for path in paths:
            if path.exists(): path.unlink()


def main():
    parser = argparse.ArgumentParser(description=__doc__); parser.add_argument("--request", required=True, type=Path); parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    try:
        require(args.request.stat().st_size <= 8*1024**2, "Request exceeds 8 MiB.")
        result = extract(parse(args.request.read_text(encoding="utf-8-sig"))); code = 0
    except Exception as error:
        result = {"schema": "brohn-stream-extract-result/1.0", "operation": "extract_stream", "status": "error", "error": {"message": str(error)[:4000]}}
        code = 1
    args.output.write_text(canonical(result)+"\n", encoding="utf-8")
    return code


if __name__ == "__main__":
    raise SystemExit(main())
