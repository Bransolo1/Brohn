"""Verify a saved cardiac input, resolve exclusions and process surviving runs.

This operation preserves source time and sample indices. It does not repair
beats, classify normal beats, infer motion artifacts or concatenate recordings.
"""
from __future__ import annotations

import argparse
import copy
import csv
from decimal import Decimal, InvalidOperation, localcontext
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path
import platform
import sys
import tempfile
import warnings


def module(name, filename):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(filename))
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


physiology = module("brohn_review_physiology", "physiology.py")
views = module("brohn_review_views", "signal_preview.py")
artifacts = views.artifacts
np = physiology.np
require = physiology.require
InputError = physiology.InputError
POLICY = "cardiac-source-exclusion/1.0"
REASONS = {"signal_loss", "clipping", "movement_or_distortion", "researcher_exclusion"}


def same(left, right):
    # JSON numbers may be integral floats after a cross-language round trip.
    # Validate index types separately; value comparisons remain exact.
    return left == right


def integer(value, lower, upper):
    return views.finite(value) and value == int(value) and lower <= value <= upper


def immutable_file(path, sha, size):
    path = Path(path).resolve()
    require(path.is_file() and integer(size, 1, physiology.MAX_FILE_BYTES) and
            path.stat().st_size == size and artifacts.digest_file(path) == sha,
            "The original analysis input failed its exact byte/hash check.")
    return path


def normalize_spans(spans, start, end, allow_empty):
    require(isinstance(spans, list) and (0 if allow_empty else 1) <= len(spans) <= 64,
            "Use 1 to 64 exclusion spans before recalculating.")
    ids = set()
    for span in spans:
        require(isinstance(span, dict) and set(span) == {"id", "start_sample", "end_sample", "reason", "note"},
                "Each exclusion needs its identity, exact half-open sample bounds, reason and note.")
        require(isinstance(span["id"], str) and artifacts.ID.fullmatch(span["id"]) and span["id"] not in ids,
                "Exclusion identities must be distinct.")
        ids.add(span["id"])
        require(integer(span["start_sample"], start, end - 1) and integer(span["end_sample"], start + 1, end) and
                span["start_sample"] < span["end_sample"], "Exclusions must stay inside the selected source sample range.")
        require(span["reason"] in REASONS and isinstance(span["note"], str) and len(span["note"].encode("utf-8")) <= 4000,
                "Choose a supported reason and a note of at most 4000 bytes.")
        require(span["reason"] != "researcher_exclusion" or bool(span["note"].strip()),
                "Explain a researcher-selected exclusion in its note.")
    union = []
    for span in sorted(spans, key=lambda s: (s["start_sample"], s["end_sample"], s["id"])):
        lo, hi = int(span["start_sample"]), int(span["end_sample"])
        if union and lo <= union[-1]["end_sample"]:
            union[-1]["end_sample"] = max(union[-1]["end_sample"], hi)
            union[-1]["span_ids"].append(span["id"])
        else:
            union.append({"start_sample": lo, "end_sample": hi, "span_ids": [span["id"]]})
    return union


def bind(request):
    require(isinstance(request, dict) and request.get("schema") == "brohn-cardiac-review-request/1.0",
            "Unsupported cardiac review request.")
    allowed = {"schema", "operation", "policy", "source", "source_path", "metadata", "modality", "format",
               "parameters", "artifact", "verification_receipt", "table", "review_source", "spans", "artifact_directory", "curation", "candidate"}
    require(set(request) <= allowed and request.get("operation") in {"preview_cardiac_review", "reanalyse_cardiac"} and
            request.get("policy") == POLICY, "Use the registered source exclusion policy and operation.")
    require("candidate" not in request or request["operation"] == "preview_cardiac_review",
            "Resolve and save a proposed exclusion before recalculating.")
    modality = request.get("modality")
    require(modality in {"ecg", "ppg"} and request.get("format") in {"csv", "tsv"},
            "This review requires one ECG or PPG table from an explicit CSV/TSV mapping.")
    source = request.get("source", {})
    require(isinstance(source, dict) and set(source) == {"sha256", "bytes"}, "Pin the original source bytes and hash.")
    path = immutable_file(request.get("source_path", ""), source["sha256"], source["bytes"])
    require(path.suffix.lower() == "." + request["format"], "Isolate the source with its declared CSV/TSV extension.")
    metadata = request.get("metadata")
    require(isinstance(metadata, dict), "Preserve the original declared source mapping.")
    recordings, source_info = physiology.csv_recordings(path, metadata, modality)
    manifest = views.bind_receipt(request)
    require(manifest["kind"] == "physiology-series", "Review the complete input waveform, not detected events.")
    chosen = request.get("table")
    require(isinstance(chosen, dict) and isinstance(chosen.get("identity"), dict), "Choose one exact saved source table.")
    identity = chosen["identity"]
    matches = [r for r in recordings if r["id"] == identity.get("recording_id")]
    require(len(matches) == 1, "The selected recording is absent from the original mapping.")
    recording = matches[0]
    require(same(recording["group"], identity.get("group")) and identity.get("channel") in recording["channels"],
            "The selected table belongs to another channel or person/session context.")
    params = physiology.parameters(modality, request.get("parameters", {}), recording["fs"])
    selected = {}
    count = 0
    verified_retained = []

    def table(item):
        if item["table_id"] != chosen.get("table_id"):
            return
        require(not selected, "Duplicate selected table.")
        actual = views.descriptor(item)
        actual["support"] = {k: v for k, v in item["support"].items() if k not in {"parameters", "method"}}
        require(all(same(actual.get(k), chosen.get(k)) for k in
                    ("table_id", "identity", "coordinates", "coordinate_column", "value_columns", "rows", "support")),
                "The frozen catalog table differs from the complete source artifact.")
        support = item["support"]
        s = support["source"]
        require(item["coordinates"]["axis"] == "time" and support.get("raw_source_omitted") is False and
                support.get("input_waveform", {}).get("column") == "raw" and
                same(support.get("method"), params), "Reanalyse the original mapping first to preserve input and its exact method.")
        require(s["source_time_origin"] == recording["source_time_origin"] and s["unit"] == recording["unit"] and
                s["source_unit"] == recording["source_unit"] and s["scale_factor"] == recording["scale_factor"] and
                s["sampling_rate"] == recording["fs"] and item["coordinates"]["source_time_unit"] == metadata["time_unit"],
                "Source calibration, clock or sampling declaration differs from the saved input.")
        lo, hi = s["source_row_start"], s["source_row_end_exclusive"]
        base = recording["source_row_start"]
        require(integer(lo, base, base + len(recording["times"]) - 1) and integer(hi, lo + 1, base + len(recording["times"])) and
                hi - lo == item["expected_rows"], "The original sample range is inconsistent.")
        segments, quality = physiology.continuous_segments(recording, recording["channels"].index(identity["channel"]), metadata, modality)
        require((int(lo - base), int(hi - base)) in segments,
                "Review one original continuous table; missing values and clock gaps cannot be crossed.")
        selected.update(item=item, start=int(lo), end=int(hi), offset=int(lo - base), quality=quality)

    def rows(tid, offset, values):
        nonlocal count
        if tid != chosen.get("table_id"):
            return
        item = selected["item"]
        names = [c["name"] for c in item["columns"]]
        require({"source_sample_index", "time_s", "raw", "clean", "retained"} <= set(names),
                "The saved report has no complete pre-cleaning input column.")
        channel = recording["channels"].index(identity["channel"])
        for i, row in enumerate(values):
            value = dict(zip(names, row))
            local = selected["offset"] + offset + i
            require(value["source_sample_index"] == selected["start"] + offset + i and
                    value["time_s"] == float(recording["times"][local]) and
                    value["raw"] == float(recording["values"][channel, local]),
                    "A saved input sample, coordinate or source row differs from the original mapped input.")
            verified_retained.append(value["retained"])
            count += 1

    checked = artifacts.verify_artifact(manifest, on_table=table, on_rows=rows)
    require(selected and count == selected["end"] - selected["start"], "The complete selected source table is missing rows.")
    require(checked["provenance"]["source_sha256"] == source["sha256"], "The saved waveform came from another source file.")
    parent_engine = checked["provenance"]["engine"]
    require(checked["provenance"]["operation"] == "physiology" and
            parent_engine.get("worker_sha256") == artifacts.digest_file(Path(physiology.__file__)) and
            parent_engine.get("python") == platform.python_version() and
            same(parent_engine.get("packages"), physiology.versions(["numpy", "scipy", "neurokit2"])),
            "The parent used another detector implementation or environment. Run a fresh original analysis before reviewing exclusions; historical reports remain unchanged.")
    frozen = checked["provenance"]["parameters"]
    require(same(frozen.get("source_mapping"), metadata) and same(frozen.get("requested", {}), request.get("parameters", {})),
            "Use the parent's exact mapping and requested detector settings.")
    immutable_file(path, source["sha256"], source["bytes"])
    review = request.get("review_source")
    require(isinstance(review, dict) and set(review) == {"id", "revision", "hash"} and artifacts.text(review["id"], 160) and
            integer(review["revision"], 1, 2**31 - 1) and isinstance(review["hash"], str) and artifacts.HEX.fullmatch(review["hash"]),
            "Pin the exact saved review revision and hash.")
    selected.update(recording=recording, parameters=params, source_info=source_info, parent_retained=verified_retained)
    normalize_spans(request.get("spans"), selected["start"], selected["end"], request["operation"] == "preview_cardiac_review")
    selected["crosswalk"] = bind_curation(request, selected)
    return selected


def bind_curation(request, source):
    curation = request.get("curation")
    if curation is None:
        return None
    require(isinstance(curation, dict) and set(curation) == {"curation_id", "curation_revision", "curation_hash", "lineage", "decisions", "decisions_path"},
            "Curated input requires its exact curation and complete decisions reference.")
    desc = curation["decisions"]
    path = Path(curation["decisions_path"])
    require(isinstance(desc, dict) and set(desc) == {"sha256", "bytes"} and integer(desc["bytes"], 1, 4 * 1024**3) and
            path.is_file() and path.stat().st_size == desc["bytes"] and artifacts.digest_file(path) == desc["sha256"],
            "The complete curation decisions failed their byte/hash check.")
    selected = {}
    selected_count = 0
    needed = {source["start"], source["end"] - 1}
    for span in request["spans"]:
        needed.update((int(span["start_sample"]), int(span["end_sample"]) - 1))
    included, total = 0, 0
    with Path(request["source_path"]).open(encoding="utf-8-sig", newline="") as stream, path.open(encoding="utf-8") as decisions:
        reader = csv.DictReader(stream, delimiter="\t" if request["format"] == "tsv" else ",")
        required = {"source_sequence", "source_segment_id", "source_clock_id", "source_timestamp", "source_timestamp_unit", "source_identity_json", "brohn_segment_id"}
        require(required <= set(reader.fieldnames or []), "The curated source has no complete acquisition row/clock crosswalk.")
        while True:
            line = decisions.readline(2 * 1024**2 + 1)
            if not line:
                break
            require(len(line.encode("utf-8")) <= 2 * 1024**2 and line.endswith("\n"), "A curation decision exceeds its row bound.")
            d = json.loads(line, object_pairs_hook=artifacts._unique)
            total += 1
            require(total <= physiology.MAX_ROWS and d.get("source_sequence") == total and d.get("disposition") in {"included", "excluded"},
                    "The complete source decision sequence is inconsistent.")
            if d["disposition"] != "included":
                continue
            row = next(reader, None)
            require(row is not None and row["source_sequence"] == str(total) and
                    all(row[k] == str(d[k]) for k in ("source_segment_id", "source_clock_id", "source_timestamp", "source_timestamp_unit", "brohn_segment_id")) and
                    same(json.loads(row["source_identity_json"], object_pairs_hook=artifacts._unique), d["source_identity"]),
                    "The derived row differs from its original included acquisition sequence, clock or identity.")
            if source["start"] <= included < source["end"]:
                selected_count += 1
                if included in needed:
                    selected[included] = {"source_sample_index": included, **{k: d[k] for k in
                        ("source_sequence", "source_segment_id", "source_clock_id", "source_timestamp", "source_timestamp_unit", "source_identity", "brohn_segment_id")}}
            included += 1
        require(next(reader, None) is None and included == source["source_info"]["rows"] and selected_count == source["end"] - source["start"] and set(selected) == needed,
                "The complete decision-to-CSV row counts disagree.")
    require(path.stat().st_size == desc["bytes"] and artifacts.digest_file(path) == desc["sha256"], "Curation decisions changed during reading.")
    return {"binding": {k: v for k, v in curation.items() if k != "decisions_path"}, "rows": selected,
            "all_derived_rows": included, "all_acquisition_rows": total}


def plan(request, source):
    start, end = source["start"], source["end"]
    union = normalize_spans(request.get("spans"), start, end, request["operation"] == "preview_cardiac_review")
    recording = source["recording"]
    fs = recording["fs"]
    edge = int(math.ceil(source["parameters"]["edge_exclusion_s"] * fs))
    times = recording["times"]
    base = recording["source_row_start"]
    runs = []
    cursor = start
    for span in union + [{"start_sample": end, "end_sample": end}]:
        if cursor < span["start_sample"]:
            hi = span["start_sample"]
            remaining = hi - cursor - 2 * edge
            ready = remaining >= max(2, int(fs)) and remaining / fs >= 10
            runs.append({"run_id": f"review-run-{len(runs) + 1}", "start_sample": cursor, "end_sample": hi,
                "samples": hi - cursor, "first_time_s": float(times[cursor - base]), "last_time_s": float(times[hi - base - 1]),
                "edge_guard_samples_each_end": edge, "predicted_retained_samples": remaining if ready else 0,
                "status": "ready_to_attempt" if ready else "insufficient_support",
                "reason": None if ready else "Fewer than ten retained seconds after independent edge exclusions."})
        cursor = span["end_sample"]
    excluded = sum(s["end_sample"] - s["start_sample"] for s in union)
    decisions = []
    for span in request["spans"]:
        decisions.append({**span, "samples": span["end_sample"] - span["start_sample"],
            "first_time_s": float(times[int(span["start_sample"]) - base]),
            "last_time_s": float(times[int(span["end_sample"]) - base - 1])})
    result = {"schema": "brohn-cardiac-exclusion-ledger/1.0", "policy": POLICY,
        "review_source": request["review_source"], "table": request["table"], "source": request["source"],
        "boundary": "zero-based original analysis-input rows; start inclusive, end exclusive",
        "spans": decisions, "union": union, "runs": runs,
        "support": {"input_samples": end - start, "excluded_samples": excluded,
            "remaining_samples": end - start - excluded, "predicted_retained_samples": sum(r["predicted_retained_samples"] for r in runs),
            "excluded_nominal_seconds": excluded / fs, "sampling_rate_hz": fs,
            "edge_guard_seconds": source["parameters"]["edge_exclusion_s"],
            "guard_basis": "unchanged parent engineering policy; not proof of transient removal",
            "nominal_support_definition": "sample count divided by declared sampling rate; not physical timing qualification"}}
    crosswalk = source.get("crosswalk")
    if crosswalk is not None:
        result["curation"] = {**crosswalk["binding"], "all_derived_rows": crosswalk["all_derived_rows"],
            "all_acquisition_rows": crosswalk["all_acquisition_rows"], "selected_first": crosswalk["rows"][start], "selected_last": crosswalk["rows"][end - 1],
            "index_definition": "source_sample_index is a zero-based derived CSV row; source_sequence is the original one-based acquisition row; full crosswalk remains in the pinned CSV and decisions"}
        for span in decisions:
            span["curated_first"] = crosswalk["rows"][int(span["start_sample"])]
            span["curated_last"] = crosswalk["rows"][int(span["end_sample"]) - 1]
    return result


def input_preview(source, ledger):
    """Extrema/first/last per status segment and bin; includes parent edge rows."""
    recording = source["recording"]
    begin = source["offset"]
    n = source["end"] - source["start"]
    channel = recording["channels"].index(source["item"]["identity"]["channel"])
    x, t = recording["values"][channel, begin:begin + n], recording["times"][begin:begin + n]
    status = np.array(["parent_retained" if v else "parent_filter_edge" for v in source["parent_retained"]], dtype=object)
    for span in ledger["union"]:
        status[span["start_sample"] - source["start"]:span["end_sample"] - source["start"]] = "researcher_excluded"
    breaks = np.r_[0, np.flatnonzero(status[1:] != status[:-1]) + 1, n]
    fragments = []
    width = max(1, math.ceil(n / 800))
    for lo, hi in zip(breaks[:-1], breaks[1:]):
        points = []
        for a in range(int(lo), int(hi), width):
            b = min(a + width, int(hi))
            indices = sorted({a, b - 1, a + int(np.argmin(x[a:b])), a + int(np.argmax(x[a:b]))})
            points.extend({"source_sample_index": source["start"] + i, "time_s": float(t[i]), "value": float(x[i])} for i in indices)
        fragments.append({"status": str(status[lo]), "source_start_sample": source["start"] + int(lo),
            "source_end_sample": source["start"] + int(hi), "points": points})
    return {"unit": recording["unit"], "coordinates": source["item"]["coordinates"], "fragments": fragments,
        "definition": "Unit-converted original input including saved filter edges; no new cleaning or detection.",
        "sampling": "Observed first/last/min/max within each bin and status span; exact samples in original order.",
        "displayed_samples": sum(len(f["points"]) for f in fragments), "complete_samples": n}


def resolve_candidate(request, source):
    c = request["candidate"]
    require(isinstance(c, dict) and set(c) == {"id", "start_time_s_text", "end_time_s_text", "reason", "note"},
            "A proposed exclusion needs two exact relative times, its identity, reason and note.")
    for key in ("start_time_s_text", "end_time_s_text"):
        require(isinstance(c[key], str) and 1 <= len(c[key].encode("utf-8")) <= 128,
                "Enter bounded decimal times in this recording's relative seconds.")
    try:
        lower, upper = Decimal(c["start_time_s_text"]), Decimal(c["end_time_s_text"])
    except InvalidOperation as error:
        raise InputError("Enter numeric relative seconds for both boundaries.") from error
    require(lower.is_finite() and upper.is_finite() and lower < upper, "Start time must precede its exclusive end.")
    indices = []
    first_time = last_time = selected_first = selected_last = None
    metadata = request["metadata"]
    with localcontext() as context:
        context.prec = 300
        factor = Decimal(1) / Decimal(str(source["recording"]["fs"])) if metadata["time_unit"] == "sample" else physiology.TIME_FACTORS[metadata["time_unit"]]
        origin = Decimal(source["recording"]["source_time_origin"])
        with Path(request["source_path"]).open(encoding="utf-8-sig", newline="") as stream:
            rows = csv.DictReader(stream, delimiter="\t" if request["format"] == "tsv" else ",")
            for index, row in enumerate(rows):
                if index < source["start"]:
                    continue
                if index >= source["end"]:
                    break
                relative = (Decimal(row[metadata["time_column"]]) - origin) * factor
                if first_time is None:
                    first_time = relative
                last_time = relative
                if lower <= relative < upper:
                    if not indices:
                        indices.append(index)
                        selected_first = relative
                    selected_last = relative
                    end = index + 1
    require(first_time <= lower and upper <= last_time,
            "Keep typed time bounds inside the observed recording. To include its final sample, use the exact source-sample end bound.")
    require(indices, "These times select no original samples; widen the interval.")
    span = {"id": c["id"], "start_sample": indices[0], "end_sample": end, "reason": c["reason"], "note": c["note"]}
    normalize_spans([span], source["start"], source["end"], False)
    return {"candidate": c, "span": span, "samples": end - indices[0], "first_time_s": float(selected_first), "last_time_s": float(selected_last),
            "first_time_s_text": str(selected_first), "last_time_s_text": str(selected_last),
            "resolution": "Membership read from original decimal source timestamps; start inclusive, end exclusive; no sampling-rate index inference."}


def analyse(request, source, ledger):
    recording, params = source["recording"], source["parameters"]
    modality = request["modality"]
    engine = {"name": "Brohn cardiac source exclusion", "version": "1.0.0", "python": platform.python_version(),
        "worker_sha256": artifacts.digest_file(Path(__file__)), "detector_worker_sha256": artifacts.digest_file(Path(physiology.__file__)),
        "artifact_writer_sha256": artifacts.digest_file(Path(artifacts.__file__)),
        "packages": physiology.versions(["numpy", "scipy", "neurokit2"])}
    frozen = {"requested": request.get("parameters", {}), "source_mapping": request["metadata"],
              "source_evidence": request["source"], "exclusion_review": ledger}
    output = {"schema": "brohn-worker-result/1.0", "modality": modality, "status": "completed", "engine": engine,
        "source": {**request["source"], **source["source_info"]}, "parameters": {recording["id"]: params},
        "features": [], "events": [], "series": [], "recordings": [], "artifacts": [], "exclusion_review": ledger,
        "limitations": ["Researcher exclusions are decisions, not automatic artifact detection or normal-beat classification.",
            "Surviving runs are filtered and detected independently. No interval or filter state crosses an exclusion.",
            "Per-run endpoints have different support from the parent. No pooled RMSSD, spectrum or participant inference is produced.",
            "The unchanged parent edge guard is an engineering policy, not proof of transient removal or physiological validity."]}
    require(request.get("artifact_directory"), "Recalculation requires a complete artifact destination.")
    original_identity = source["item"]["identity"]
    channel = recording["channels"].index(original_identity["channel"])
    retained, computed, total_events = 0, 0, 0
    with artifacts.ArtifactSet(request["artifact_directory"], {"source_sha256": request["source"]["sha256"], "engine": engine,
            "operation": "reanalyse_cardiac", "origin": request["metadata"].get("origin", "unspecified"), "parameters": frozen}) as writers:
        for run in ledger["runs"]:
            identity = {**original_identity, "segment_id": run["run_id"]}
            lo, hi = run["start_sample"] - recording["source_row_start"], run["end_sample"] - recording["source_row_start"]
            summary = {**identity, "source_time_origin": recording["source_time_origin"], "source_row_start": run["start_sample"],
                "source_row_end_exclusive": run["end_sample"], "start_time_s": run["first_time_s"], "end_time_s": run["last_time_s"],
                "samples": run["samples"], "sampling_rate": recording["fs"], "unit": recording["unit"], "source_unit": recording["source_unit"],
                "scale_factor": recording["scale_factor"], "channel_quality": source["quality"],
                "review_source": request["review_source"], "exclusion_policy": POLICY}
            try:
                bundle = physiology.cardiac(recording["values"][channel, lo:hi], recording["times"][lo:hi], recording["fs"], params, modality)
            except (InputError, ValueError, IndexError, ZeroDivisionError) as error:
                summary.update(status="unavailable", reason=str(error)[:500])
                output["recordings"].append(summary)
                continue
            summary.update(status="computed", **bundle["support"])
            output["recordings"].append(summary)
            computed += 1
            retained += bundle["support"]["retained_samples"]
            total_events += len(bundle["events"])
            artifacts.write_physiology_bundle(writers.series, writers.events, modality, identity, bundle, summary,
                                               request["metadata"]["time_unit"], run["run_id"])
            output["features"].extend({**identity, **item} for item in bundle["features"])
            budget = max(1, physiology.MAX_DISPLAY // max(1, len(ledger["runs"])))
            for index in np.unique(np.linspace(0, len(bundle["events"]) - 1, min(budget, len(bundle["events"])), dtype=int)):
                event = copy.deepcopy(bundle["events"][index])
                if "sample_index" in event:
                    event["source_sample_index"] = run["start_sample"] + event["sample_index"]
                    event["segment_sample_index"] = event.pop("sample_index")
                output["events"].append({**identity, **event})
            for index in np.unique(np.linspace(0, hi - lo - 1, min(budget, hi - lo), dtype=int)):
                output["series"].append({**identity, **{k: bool(v[index]) if k == "retained" else physiology.number(v[index]) for k, v in bundle["series"].items()}})
            output["limitations"].extend(v for v in bundle["limitations"] if v not in output["limitations"])
        output["artifacts"] = writers.finish()
    output["status"] = "insufficient_support" if not computed else "partial" if computed != len(ledger["runs"]) else "completed"
    output["quality"] = {"usable": computed > 0, "requires_research_review": True, "scientifically_qualified": False,
        "normal_to_normal_confirmed": False, "computed_channel_segments": computed,
        "unavailable_channel_segments": len(ledger["runs"]) - computed, "channel_samples_total": ledger["support"]["input_samples"],
        "researcher_excluded_samples": ledger["support"]["excluded_samples"], "channel_samples_retained": retained,
        "retained_fraction": retained / ledger["support"]["input_samples"], "event_records_total": total_events,
        "event_records_displayed": len(output["events"]), "series_samples_displayed": len(output["series"]),
        "complete_processed_artifacts": True, "raw_source_duplicated": bool(output["artifacts"]),
        "display_sampling": "bounded uniform index selection; full per-run outputs in typed artifacts"}
    return output


def run(request):
    source = bind(request)
    ledger = plan(request, source)
    with warnings.catch_warnings(record=True) as observed:
        warnings.simplefilter("always")
        if request["operation"] == "preview_cardiac_review":
            output = {"schema": "brohn-cardiac-review-preview/1.0", "status": "completed", "ledger": ledger,
                      "input_preview": input_preview(source, ledger)}
            if "candidate" in request:
                output["resolved_exclusion"] = resolve_candidate(request, source)
        else:
            output = analyse(request, source, ledger)
        output["warnings"] = sorted({str(w.message)[:400] for w in observed})[:100]
    immutable_file(request["source_path"], request["source"]["sha256"], request["source"]["bytes"])
    artifacts.verify_artifact(request["artifact"])
    return output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--request", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    safe = not os.path.lexists(args.output) and args.output.resolve() != args.request.resolve()
    code = 0
    try:
        require(safe, "Use a new output path; existing files cannot be replaced.")
        require(args.request.is_file() and args.request.stat().st_size <= 2 * 1024**2, "Review request is missing or exceeds 2 MiB.")
        request = json.loads(args.request.read_text(encoding="utf-8"), object_pairs_hook=artifacts._unique,
            parse_constant=lambda value: (_ for _ in ()).throw(InputError("Nonfinite request JSON.")))
        result = run(request)
    except Exception as error:
        code = 2
        result = {"schema": "brohn-cardiac-review-error/1.0", "status": "error", "error": {"type": type(error).__name__, "message": str(error)[:1000]}}
    if not safe:
        print(json.dumps(result), file=sys.stderr)
        return code
    fd, filename = tempfile.mkstemp(prefix=".cardiac-review-", suffix=".tmp", dir=args.output.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            json.dump(result, stream, allow_nan=False, separators=(",", ":"))
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        require(Path(filename).stat().st_size <= 16 * 1024**2, "Review result exceeds the 16 MiB document limit.")
        os.replace(filename, args.output)
    finally:
        if os.path.exists(filename):
            os.unlink(filename)
    print(json.dumps({"status": result["status"]}))
    return code


if __name__ == "__main__":
    raise SystemExit(main())
