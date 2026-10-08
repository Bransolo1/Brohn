"""Strict saved cardiac semantics, bounded streaming and presentation transport."""
from __future__ import annotations
import copy
import csv
import hashlib
import math
import re
import shutil
from contextlib import ExitStack
from pathlib import Path

import physiology_artifacts as tables
from cardiac_values import fields, strict_json, json_bytes, value_hash, verifier_manifest
import cardiac_display_policy as policy

MIB = 1024**2
require = tables.require
HASH = re.compile(r"[a-f0-9]{64}")
IDENTITY = ("recording_id", "channel", "group", "segment_id")
GROUPS = {"participant_id", "session_id", "condition_id", "exposure_id", "segment_id", "source_recording_id"}
COUNTS = ("samples", "retained_samples", "peaks", "intervals", "null_interval_rows", "plausible_intervals", "implausible_intervals", "spectrum_bins", "features")


class Refusal(tables.ArtifactError):
    def __init__(self, reason, *, source=None, cell=None, resource=None, measured=None, maximum=None,
                 recovery="repair_source", stage="source_validation", request_hash=None, message=None):
        super().__init__(message or reason.replace("_", " "))
        self.detail = dict(schema="brohn-cardiac-report-refusal/0.1", reason_code=reason, stage=stage,
                           source_ref=source, cell_key=cell, resource=resource or reason, measured=measured,
                           maximum=maximum, recovery_scope=recovery, blocked_request_hash=request_hash or "0"*64,
                           message=str(self))


def limit(actual, maximum, resource, source=None, recovery="fewer_sources", stage="source_validation"):
    if actual > maximum:
        raise Refusal(resource+"_limit", source=source, resource=resource, measured=actual, maximum=maximum,
                      recovery=recovery, stage=stage)


def same(a, b):
    return value_hash(a) == value_hash(b)


def number(n):
    return type(n) in (int, float) and math.isfinite(n)


def integer(n, minimum=0):
    return type(n) is int and minimum <= n <= 2**53-1


def ref_valid(ref):
    fields(ref, ("kind", "id", "revision", "body_hash", "project_id"), "Exact reference")
    require(all(tables.text(ref[k], 500) for k in ("kind", "id", "project_id")) and
            integer(ref["revision"], 1) and isinstance(ref["body_hash"], str) and HASH.fullmatch(ref["body_hash"]),
            "Invalid exact source reference.")


def identity(record):
    # Preserve absence: this exact function is the source-window/cell-key seam.
    return {k: copy.deepcopy(record[k]) for k in IDENTITY if k in record}


def cell_key(ref, ordinal, record):
    return value_hash(dict(report_ref=ref, source_record_index=ordinal, identity=identity(record)))


def page_policy(value):
    fields(value, ("mode", "numbers"), "Page policy")
    require(value["mode"] in ("first", "all", "selected") and isinstance(value["numbers"], list), "Invalid page policy.")
    nums = value["numbers"]
    limit(len(nums), 20000, "display_page_selection_count", recovery="fewer_figures", stage="metadata")
    require(all(integer(n, 1) for n in nums) and len(set(nums)) == len(nums), "Invalid or duplicate page number.")
    require(bool(nums) == (value["mode"] == "selected"), "Page numbers do not match page mode.")
    return dict(mode=value["mode"], numbers=sorted(nums))


def display_request(value=None):
    if value is None:
        value = dict(schema="brohn-cardiac-display-request/0.1", policy=policy.POLICY,
                     figure_cells=dict(scope="first_chapter", keys=[]), cell_overrides=[])
    limit(len(json_bytes(value)), 2*MIB, "display_request_bytes", recovery="fewer_figures", stage="metadata")
    fields(value, ("schema", "policy", "figure_cells", "cell_overrides"), "Cardiac display request")
    require(value["schema"] == "brohn-cardiac-display-request/0.1" and value["policy"] == policy.POLICY,
            "Unsupported cardiac display policy.")
    selector = value["figure_cells"]
    fields(selector, ("scope", "keys"), "Figure selector")
    require(selector["scope"] in ("first_chapter", "all_cells", "exact_cells", "no_cells") and isinstance(selector["keys"], list),
            "Invalid figure cell selector.")
    keys = selector["keys"]
    limit(len(keys), 2000, "figure_cell_keys", recovery="fewer_figures", stage="metadata")
    require(all(isinstance(k, str) and HASH.fullmatch(k) for k in keys) and len(set(keys)) == len(keys) and
            bool(keys) == (selector["scope"] == "exact_cells"), "Figure cell keys are invalid or duplicated.")
    overrides = value["cell_overrides"]
    require(isinstance(overrides, list), "Cell overrides must be an array.")
    limit(len(overrides), 2000, "cell_overrides", recovery="fewer_figures", stage="metadata")
    out, seen, total = [], set(), 0
    for row in overrides:
        fields(row, ("cell_key", "time_focus", "waveform_windows", "marker_pages", "interval_pages", "numerical_pages"), "Cell override")
        key = row["cell_key"]
        require(isinstance(key, str) and HASH.fullmatch(key) and key not in seen, "Duplicate or invalid cell override.")
        seen.add(key)
        focus = row["time_focus"]
        if focus is not None:
            fields(focus, ("start_s", "end_s"), "Time focus")
            normalized = policy.focus_window(focus["start_s"], focus["end_s"])
            focus = {k: normalized[k] for k in ("start_s", "end_s")}
        item = dict(cell_key=key, time_focus=focus)
        for field in ("waveform_windows", "marker_pages", "interval_pages", "numerical_pages"):
            item[field] = page_policy(row[field])
            total += len(item[field]["numbers"])
        limit(total, 20000, "display_page_selection_count", recovery="fewer_figures", stage="metadata")
        out.append(item)
    result = dict(schema=value["schema"], policy=value["policy"], figure_cells=dict(scope=selector["scope"], keys=sorted(keys)),
                  cell_overrides=sorted(out, key=lambda x: x["cell_key"]))
    limit(len(json_bytes(result)), 2*MIB, "display_request_bytes", recovery="fewer_figures", stage="metadata")
    return result


def sealed_registry(objects):
    registry = {}
    require(isinstance(objects, list), "Sealed objects must be an array.")
    limit(len(objects), 1024, "sealed_objects")
    for item in objects:
        fields(item, ("hash", "bytes", "path"), "Sealed source object")
        path = Path(item["path"])
        require(isinstance(item["hash"], str) and HASH.fullmatch(item["hash"]) and integer(item["bytes"], 1)
                and item["bytes"] <= 512*MIB and path.is_file() and not path.is_symlink(), "Invalid sealed object descriptor.")
        resolved = str(path.resolve(strict=True))
        require(resolved not in registry or same(registry[resolved], item), "Conflicting sealed path descriptor.")
        registry[resolved] = item
    return registry


def bound_path(item, registry):
    fields(item, ("hash", "bytes", "path"), "Bound private object")
    path = Path(item["path"])
    require(path.is_file() and not path.is_symlink(), "Declared source is not an ordinary file.")
    found = registry.get(str(path.resolve(strict=True)))
    require(found is not None and same(found, item), "A private path is not an exact declared sealed object.")
    return path


def check_objects(registry, pulse=None):
    for key, item in registry.items():
        if pulse:
            pulse()
        path = Path(key)
        require(path.is_file() and not path.is_symlink() and path.stat().st_size == item["bytes"] and
                tables.digest_file(path) == item["hash"], "A sealed source changed its bytes or SHA-256.")


class OutputFiles:
    def __init__(self, directory):
        self.directory = Path(directory).resolve()
        require(self.directory.is_dir() and not self.directory.is_symlink(), "Output directory must be ordinary and owned.")
        self.payloads = []
        self.bytes = 0

    def path(self, name):
        require(re.fullmatch(r"[a-z0-9][a-z0-9.-]*", name) is not None, "Unsafe output filename.")
        path = self.directory/name
        require(not path.exists(), "Output already exists; use a fresh attempt directory.")
        return path

    def register(self, path, schema, role, media_type="application/json"):
        self.bytes += path.stat().st_size
        limit(self.bytes, 192*MIB, "projection_bytes", stage="projection")
        payload = dict(path=path.name, hash=tables.digest_file(path), bytes=path.stat().st_size,
                       media_type=media_type, schema=schema, role=role)
        self.payloads.append(payload)
        return {k: payload[k] for k in ("hash", "bytes", "media_type", "schema")}

    def json(self, name, value, schema, role):
        raw = json_bytes(value)
        limit(len(raw), 48*MIB, "json_object_bytes", stage="projection")
        path = self.path(name)
        with path.open("xb") as stream:
            stream.write(raw)
        return self.register(path, schema, role)

    def copy(self, name, source, schema, role):
        path = self.path(name)
        with Path(source).open("rb") as src, path.open("xb") as dst:
            shutil.copyfileobj(src, dst, length=MIB)
        return self.register(path, schema, role, "application/x-ndjson")


def validate_analysis(analysis):
    required = {"schema", "kind", "modality", "status", "engine", "source", "parameters", "features", "recordings",
                "quality", "limitations", "artifacts", "observations", "contrasts", "title"}
    optional = {"series", "events", "exclusion_review", "warnings", "artifact_verification"}
    require(isinstance(analysis, dict) and required <= set(analysis) and set(analysis) <= required | optional,
            "Unknown or missing complete cardiac analysis fields.")
    kind = analysis["kind"]
    require(kind in ("ecg", "ppg") and analysis["modality"] == kind and analysis["schema"] == "brohn-worker-result/1.0" and
            analysis["status"] in ("completed", "partial", "insufficient_support"), "Unsupported cardiac analysis family/status.")
    for key in ("features", "recordings", "artifacts", "observations", "contrasts", "limitations"):
        require(isinstance(analysis[key], list), "Complete cardiac collections must remain arrays.")
    for key in ("series", "events", "warnings"):
        require(key not in analysis or isinstance(analysis[key], list), "Original optional collection must remain an array.")
    require(isinstance(analysis["parameters"], dict) and isinstance(analysis["quality"], dict) and
            analysis["quality"].get("scientifically_qualified") is False, "Unqualified original method flags are required.")
    recipe = "ecg-neurokit-detected-rr/1.0" if kind == "ecg" else "ppg-elgendi-detected-prv/1.0"
    common = {"correct_artifacts", "detector", "edge_exclusion_s", "frequency_interpolation_hz", "frequency_min_duration_s",
              "frequency_psd_overlap_fraction", "frequency_psd_window", "frequency_psd_window_s", "interval_max_ms",
              "interval_min_ms", "normal_to_normal_qualification", "pnn50_denominator", "recipe"}
    for parameters in analysis["parameters"].values():
        require(isinstance(parameters, dict) and set(parameters) == common | ({"powerline_hz"} if kind == "ecg" else set()),
                "Unknown effective cardiac parameter vocabulary.")
        require(parameters["recipe"] == recipe and parameters["correct_artifacts"] is False and
                parameters["normal_to_normal_qualification"] is False and parameters["pnn50_denominator"] == "retained_intervals" and
                parameters["detector"] == ("neurokit" if kind == "ecg" else "elgendi"), "Saved cardiac recipe or qualification changed.")
    limit(len(analysis["recordings"]), 2000, "catalog_cells")
    for record in analysis["recordings"]:
        base = {"recording_id", "channel", "group", "segment_id", "status", "samples", "sampling_rate", "source_unit", "unit", "scale_factor",
                "source_row_start", "source_row_end_exclusive", "source_time_origin", "start_time_s", "end_time_s", "channel_quality"}
        extras = {"exact_flatline", "reason", "exclusion_policy", "review_source", "detected_peak_count", "filter_edge_samples",
                  "implausible_interval_count", "interval_spectrum", "normal_to_normal_intervals_confirmed", "retained_duration_s", "retained_samples"}
        require(isinstance(record, dict) and base <= set(record) and set(record) <= base | extras,
                "Cardiac recording shape is unregistered (including no-finite-sample records lacking bounds).")
        require(record["status"] in ("computed", "unavailable") and all(tables.text(record[k], 500) for k in ("recording_id", "channel", "segment_id")) and
                isinstance(record["group"], dict) and set(record["group"]) <= GROUPS and all(tables.text(v) for v in record["group"].values()),
                "Cardiac recording identity/status is invalid.")
        require(record["recording_id"] in analysis["parameters"], "Effective per-recording parameters are absent.")
        require(integer(record["source_row_start"]) and integer(record["source_row_end_exclusive"], 1) and
                record["samples"] == record["source_row_end_exclusive"] - record["source_row_start"] and record["samples"] > 0 and
                number(record["start_time_s"]) and number(record["end_time_s"]) and record["start_time_s"] <= record["end_time_s"],
                "Original sample/time bounds are inconsistent.")
        require(record["unit"] in (("uV",) if kind == "ecg" else ("a.u.", "V")), "Unsupported saved amplitude unit.")
        require(number(record["sampling_rate"]) and record["sampling_rate"] > 0 and
                isinstance(record["channel_quality"],dict) and number(record["channel_quality"].get("timestamp_tolerance_s")) and
                record["channel_quality"]["timestamp_tolerance_s"] >= 0, "Saved sample cadence/tolerance is missing or invalid.")
        if record["status"] == "computed":
            require({"detected_peak_count", "filter_edge_samples", "implausible_interval_count", "interval_spectrum",
                     "normal_to_normal_intervals_confirmed", "retained_duration_s", "retained_samples"} <= set(record) and
                    record["normal_to_normal_intervals_confirmed"] is False, "Computed cardiac support is incomplete.")
        else:
            require(tables.text(record.get("reason")), "Unavailable recording must retain its original reason.")
    for feature in analysis["features"]:
        base = {"recording_id", "channel", "group", "segment_id", "scope", "name", "unit", "value"}
        require(isinstance(feature, dict) and base <= set(feature) and set(feature) <= base | {"numerator", "denominator", "unavailable_reason"},
                "Unknown saved cardiac feature field.")
        require(feature["value"] is None or number(feature["value"]), "Feature is neither a finite original value nor null.")
        for key in ("numerator", "denominator"):
            require(key not in feature or feature[key] is None or number(feature[key]), "Feature support must remain numerical/null.")
        prefix = "detected_rr" if kind == "ecg" else "detected_prv"
        units = {"detected_peak_count":"count", **{prefix+suffix:unit for suffix,unit in (
            ("_interval_count","count"),("_retained_interval_count","count"),("_successive_pair_count","count"),
            ("_mean_interval","ms"),("_sd_interval","ms"),("_rmssd","ms"),("_pnn50_candidate","%"),
            ("_rate_from_mean_interval","beats/min"),("_mean_interval_rate","beats/min"),
            ("_lf_power_candidate","ms^2"),("_hf_power_candidate","ms^2"),("_lf_hf_ratio_candidate","ratio"))}}
        require(feature["name"] in units and feature["unit"] == units[feature["name"]] and feature["scope"] == "recording",
                "Unregistered saved cardiac feature name/unit/scope.")
    return kind


def check_table(spec, kind, analysis):
    require(set(spec["identity"]) == set(IDENTITY), "Typed cardiac table identity vocabulary is incomplete or unknown.")
    unit = spec["support"].get("source", {}).get("unit")
    c = tables._column
    time = c("time_s", "float64", "s", role="coordinate")
    index = c("source_sample_index", "integer", "sample_index", role="index")
    if kind == "physiology-series":
        expected = [time, index, c("raw", "float64", unit), c("clean", "float64", unit), c("retained", "boolean", None, role="support")]
        if not any(x["name"] == "raw" for x in spec["columns"]):
            raise Refusal("historical_input_waveform_not_saved")
        domain, axis = "samples", "time"
    elif spec["coordinates"]["axis"] == "event":
        expected = [c("type", "string", None, role="label"), time, c("sample_index", "integer", "segment_sample_index", role="index"),
                    index, c("previous_interval_ms", "float64", "ms", True), c("previous_interval_plausible", "boolean", None, True, role="support")]
        domain, axis = "peaks", "event"
    else:
        expected = [c("type", "string", None, role="label"), c("frequency_hz", "float64", "Hz", role="coordinate"), c("density_ms2_hz", "float64", "ms^2/Hz")]
        domain, axis = "spectrum", "frequency"
    require(same(spec["columns"], expected) and spec["coordinates"]["axis"] == axis, "Typed cardiac table columns/axis changed.")
    support = spec["support"]
    expected_fields = {"source", "method", "retained_support", "raw_source_omitted", "source_sample_index_definition", "input_waveform"}
    if domain == "spectrum":
        expected_fields.add("interval_spectrum")
    require(set(support) == expected_fields and support["raw_source_omitted"] is False and
            same(support["input_waveform"], dict(column="raw", definition="unit-converted source samples before cleaning; original source bytes remain authoritative",
                 unit=unit, detection_basis="clean")), "Typed cardiac input/support metadata changed.")
    matches = [r for r in analysis["recordings"] if same(identity(r), spec["identity"])]
    require(len(matches) == 1 and matches[0]["status"] == "computed" and same(support["source"], matches[0]) and
            same(support["method"], analysis["parameters"][matches[0]["recording_id"]]), "Table is not bound to one exact computed source recording.")
    record = matches[0]
    require(spec["coordinates"]["source_time_origin"] == record["source_time_origin"] and
            spec["coordinates"]["source_time_unit"] == analysis["source"]["time_unit"], "Table clock differs from its exact source.")
    retained_keys = {"detected_peak_count","filter_edge_samples","implausible_interval_count","interval_spectrum",
                     "normal_to_normal_intervals_confirmed","retained_duration_s","retained_samples"}
    require(set(support["retained_support"]) == retained_keys and all(k in record and same(v, record[k]) for k, v in support["retained_support"].items()),
            "Retained support differs from its original record.")
    require(support["source_sample_index_definition"] == "zero-based original source row/sample index", "Unknown source index definition.")
    return domain


class VerifiedIndex:
    """A complete per-table private chunk spool; no source-array materialization."""
    def __init__(self, streams, analysis, registry, directory, outputs, pulse=None):
        self.tables, self.verified, self.rows, self.bytes = [], [], 0, 0
        self.open_files = set()
        self.directory = Path(directory)
        self.pulse = pulse
        require(isinstance(streams, list) and len(streams) in (0, 2), "Computed cardiac sources require their exact paired streams.")
        if streams:
            require({s["original"]["kind"] for s in streams} == {"physiology-series", "physiology-events"}, "Missing/duplicate stream kind.")
        for stream in streams:
            fields(stream, ("original", "original_verification", "path"), "Sealed typed stream")
            manifest = verifier_manifest(stream["original"], stream["path"])
            original_path = bound_path(dict(hash=manifest["sha256"], bytes=manifest["bytes"], path=stream["path"]), registry)
            limit(manifest["bytes"], 64*MIB, "stream_bytes")
            self.bytes += manifest["bytes"]
            limit(self.bytes, 96*MIB, "source_bytes")
            entry_tables = {}
            def on_table(spec):
                domain = check_table(spec, manifest["kind"], analysis)
                limit(len(self.tables) + 1, 256, "source_tables")
                item = dict(spec=spec, domain=domain, artifact_hash=manifest["sha256"], ordinal=len(self.tables)+1)
                item["path"] = self.directory/f"table-{item['ordinal']:04d}.jsonl"
                self.tables.append(item)
                entry_tables[spec["table_id"]] = item
            def on_rows(table_id, offset, rows):
                self.rows += len(rows)
                limit(self.rows, 1000000, "source_rows")
                if pulse:
                    pulse()
            verified = tables.verify_artifact(manifest, on_table=on_table, on_rows=on_rows)
            receipt = stream["original_verification"]
            require(receipt.get("verified") is True and all(same(receipt.get(k), manifest[k]) for k in
                    ("schema", "kind", "sha256", "bytes", "tables", "rows", "provenance_sha256")), "Original artifact verification receipt changed.")
            expected_operation = "reanalyse_cardiac" if "exclusion_review" in analysis else "physiology"
            require(verified["provenance"]["source_sha256"] == analysis["source"]["sha256"] and
                    verified["provenance"]["operation"] == expected_operation, "Typed stream source/operation differs.")
            self.verified.append(verified)
            # Exact parser preserves negative zero and safe integer token domains.
            with ExitStack() as opened:
                writers = {key: opened.enter_context(item["path"].open("xb")) for key, item in entry_tables.items()}
                with original_path.open("rb") as source:
                    while True:
                        line = source.readline(2*MIB+1)
                        if not line:
                            break
                        limit(len(line), 2*MIB, "stream_line_bytes")
                        record = strict_json(line)
                        if record["type"] == "table":
                            item = entry_tables[record["table_id"]]
                            require(same(record, item["spec"]), "Exact table declaration differs after validation.")
                            item["spec"] = record
                        elif record["type"] == "rows":
                            writers[record["table_id"]].write(json_bytes(record)+b"\n")
                        if pulse:
                            pulse()
            require(original_path.stat().st_size == manifest["bytes"] and tables.digest_file(original_path) == manifest["sha256"], "Source changed while indexing.")
            copied = outputs.copy("source-series.ndjson" if manifest["kind"] == "physiology-series" else "source-events.ndjson",
                                  original_path, tables.SCHEMA, "complete_original_typed_stream")
            require(copied["hash"] == manifest["sha256"] and copied["bytes"] == manifest["bytes"], "Original stream copy changed.")

    def rows_for(self, item):
        expected = 0
        stream = item["path"].open("rb")
        self.open_files.add(stream)
        try:
            for line in stream:
                part = strict_json(line)
                require(part["offset"] == expected, "Private source chunk index is inconsistent.")
                for row in part["rows"]:
                    yield expected, row
                    expected += 1
                if self.pulse:
                    self.pulse()
            require(expected == item["spec"]["expected_rows"], "Private source spool lost rows.")
        finally:
            stream.close()
            self.open_files.discard(stream)

    def close(self):
        for stream in tuple(self.open_files):
            stream.close()
        self.open_files.clear()

    def cell_tables(self, record):
        selected = [item for item in self.tables if same(item["spec"]["identity"], identity(record))]
        by_domain = {item["domain"]: item for item in selected}
        require(len(by_domain) == len(selected), "Multiple tables bind the same cardiac domain/cell.")
        expected = ({"samples", "peaks"} | ({"spectrum"} if record["interval_spectrum"]["status"] == "available" else set())) if record["status"] == "computed" else set()
        require(set(by_domain) == expected, "Computed table pair/spectrum or unavailable table absence disagrees with saved support.")
        return by_domain


def table_ref(item):
    spec = item["spec"]
    return dict(artifact_hash=item["artifact_hash"], table_id=spec["table_id"], domain=item["domain"], rows=spec["expected_rows"],
                column_spec_hash=value_hash(spec["columns"]), identity_hash=value_hash(spec["identity"]), support_hash=value_hash(spec["support"]))


def export_csv(index, item, outputs):
    path = outputs.path(f"table-{item['ordinal']:04d}.csv")
    names = [c["name"] for c in item["spec"]["columns"]]
    def scalar(value):
        if value is None:
            return ""
        if isinstance(value, str):
            return "'"+value if re.match(r"\s*[=+@-]", value) else value
        return json_bytes(value).decode("utf-8")
    with path.open("x", encoding="utf-8", newline="") as stream:
        writer = csv.writer(stream)
        writer.writerow(["table_row_index", *names, "record_json"])
        for ordinal, values in index.rows_for(item):
            record = dict(zip(names, values))
            writer.writerow([ordinal, *[scalar(v) for v in values], json_bytes(record).decode("utf-8")])
            if ordinal % 4096 == 0:
                limit(outputs.bytes + path.stat().st_size, 192*MIB, "projection_bytes", stage="projection")
    return outputs.register(path, "brohn-cardiac-complete-table-csv/0.1", "complete_table_csv", "text/csv")
