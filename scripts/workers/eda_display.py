"""Prepare complete saved EDA display evidence; never import scientific workers.

Original typed streams are verified once and indexed in bounded private chunks.
Existing read-only review functions receive those verified rows through a local
function namespace, not a global patch or a scientific replay. All outputs are
provisional until source hashes and final bounded evidence are checked.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
import math
import platform
import re
import struct
import tempfile
import types
from contextlib import ExitStack
from decimal import Decimal, InvalidOperation
from pathlib import Path

import physiology_artifacts as tables
import eda_review
import eda_continuous_review

COMPONENTS = ("clean_us", "tonic_us", "phasic_us")
HASH_PROFILE = "brohn-eda-value-hash/0.1"
MIB = 1024**2
require = tables.require


class Refusal(tables.ArtifactError):
    def __init__(self, source, resource, measured, maximum, recovery_scope):
        super().__init__(f"EDA {resource} exceeds {maximum}; complete evidence was not truncated.")
        self.detail = dict(schema="brohn-eda-report-refusal/0.1",reason_code="eda_limit", source=source, resource=resource,
                           measured=measured, maximum=maximum, recovery_scope=recovery_scope, message=str(self))


def bounded(value, maximum, resource, source=None, recovery="fewer_sources"):
    if value > maximum:
        raise Refusal(source, resource, value, maximum, recovery)


def value_bytes(value, depth=0):
    require(depth < 64, "EDA typed-value nesting exceeds 63 levels.")
    if value is None:
        return b"n"
    if isinstance(value, bool):
        return b"t" if value else b"f"
    if isinstance(value, (int, float)):
        require(math.isfinite(value) and (not isinstance(value, int) or abs(value) <= 2**53-1),
                "EDA typed-value number is nonfinite or outside the exact integer bound.")
        return b"d" + struct.pack(">d", float(value))
    if isinstance(value, str):
        raw = value.encode("utf-8", errors="strict")
        return b"s" + str(len(raw)).encode("ascii") + b":" + raw
    if isinstance(value, list):
        return b"a" + str(len(value)).encode("ascii") + b":" + b"".join(value_bytes(v, depth+1) for v in value)
    require(isinstance(value, dict) and all(isinstance(k, str) for k in value), "EDA typed value is not a JSON value.")
    keys = sorted(value, key=lambda k: k.encode("utf-8", errors="strict"))
    return b"o" + str(len(keys)).encode("ascii") + b":" + b"".join(value_bytes(k, depth+1)+value_bytes(value[k], depth+1) for k in keys)


def value_hash(value):
    return hashlib.sha256(HASH_PROFILE.encode("ascii") + b"\n" + value_bytes(value)).hexdigest()


def json_bytes(value):
    return json.dumps(value, ensure_ascii=True, sort_keys=True, separators=(",", ":"), allow_nan=False).encode("utf-8")


def strict_json(raw):
    def integer(text):
        number = int(text)
        require(abs(number) <= 2**53-1, "JSON integer token exceeds the exact integer bound.")
        return -0.0 if text == "-0" else number

    def real(text):
        number = float(text)
        require(math.isfinite(number), "Nonfinite JSON number.")
        return number

    return json.loads(raw, object_pairs_hook=tables._unique,
                      parse_int=integer, parse_float=real,
                      parse_constant=lambda x: (_ for _ in ()).throw(tables.ArtifactError("Nonfinite JSON.")))


def fields(value, required, label):
    require(isinstance(value, dict) and set(value) == set(required), f"{label} has missing or unknown fields.")


def normalized_decimal(text):
    require(isinstance(text, str) and 0 < len(text) <= 96 and
            re.fullmatch(r"[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?", text, flags=re.ASCII),
            "Use an explicit bounded decimal time string.")
    exponent = re.split("[eE]", text)
    submitted = len(text) <= 80 and (len(exponent) == 1 or abs(int(exponent[1])) <= 1000)
    require(submitted or (len(exponent) == 1 or abs(int(exponent[1])) <= 1100), "Decimal exponent exceeds the profile.")
    try:
        number = Decimal(text)
    except InvalidOperation as error:
        raise tables.ArtifactError("Invalid decimal bound.") from error
    require(number.is_finite() and abs(number) <= Decimal("1e12"), "Decimal time exceeds the profile.")
    if number.is_zero():
        require(submitted or text == "0", "Extended decimal must already be canonical.")
        return "0"
    sign, digits, power = number.as_tuple()
    coefficient = "".join(str(d) for d in digits).lstrip("0")
    while coefficient.endswith("0"):
        coefficient = coefficient[:-1]
        power += 1
    result = ("-" if sign else "") + coefficient + ("e"+str(power) if power else "")
    require(len(result) <= 96, "Normalized decimal exceeds its bound.")
    require(submitted or result == text, "Extended decimal must already be canonical.")
    return result


def display_request(value):
    fields(value, ("schema", "continuous_windows"), "EDA display request")
    require(value["schema"] == "brohn-eda-display-request/0.1" and isinstance(value["continuous_windows"], list), "Unsupported display request.")
    bounded(len(value["continuous_windows"]), 2000, "continuous_windows")
    result = []
    seen = set()
    for item in value["continuous_windows"]:
        fields(item, ("key", "start_s", "end_s"), "Continuous override")
        require(isinstance(item["key"], str) and re.fullmatch("[a-f0-9]{64}", item["key"]) and item["key"] not in seen, "Duplicate or invalid window key.")
        seen.add(item["key"])
        start, end = (normalized_decimal(item[k]) for k in ("start_s", "end_s"))
        require(Decimal(start) < Decimal(end), "Continuous window must increase.")
        result.append(dict(key=item["key"], start_s=start, end_s=end))
    return dict(schema=value["schema"], continuous_windows=sorted(result, key=lambda item: item["key"]))


def check_object(item):
    fields(item, ("hash", "bytes", "path"), "Sealed source")
    path = Path(item["path"])
    require(isinstance(item["hash"], str) and re.fullmatch("[a-f0-9]{64}", item["hash"]) and
            isinstance(item["bytes"], int) and not isinstance(item["bytes"], bool) and 0 < item["bytes"] <= 512*MIB and
            path.is_file() and not path.is_symlink() and path.stat().st_size == item["bytes"] and tables.digest_file(path) == item["hash"],
            "A sealed original source changed its bytes or identity.")


def verifier_manifest(original, path):
    """Keep published hash/size descriptor untouched; adapt only parser input."""
    sha = original.get("hash", original.get("sha256"))
    size = original.get("size", original.get("bytes"))
    require(("hash" not in original or "sha256" not in original or original["hash"] == original["sha256"]) and
            ("size" not in original or "bytes" not in original or original["size"] == original["bytes"]), "Conflicting original artifact descriptor aliases.")
    return {**original, "sha256": sha, "bytes": size, "path": str(path)}


def check_eda_table(spec, family, kind, profile="0.1"):
    require(profile in ("0.1", "0.2"), "Unsupported EDA preparation grammar.")
    identity = spec["identity"]
    require(set(identity) == {"recording_id", "segment_id", "channel", "group", *( ["origin"] if family == "event" else [])}, "Unsupported EDA table identity fields.")
    require(isinstance(identity["group"], dict) and set(identity["group"]) <=
            {"participant_id", "session_id", "condition_id", "exposure_id", "segment_id", "source_recording_id"}, "Unsupported EDA group identity.")
    support = spec["support"]
    constant = family == "continuous" and support.get("source", {}).get("status") == "descriptive_only"
    if family == "continuous":
        method = support.get("method", {})
        recipe = method.get("recipe")
        require(recipe == "eda-neurokit-highpass/1.0" or
                (profile == "0.2" and recipe == "eda-neurokit-highpass/1.1"),
                "EDA table method is outside this exact preparation grammar.")
        if recipe == "eda-neurokit-highpass/1.1":
            eda_continuous_review._constant_parameters(method)
        if constant:
            require(profile == "0.2", "Constant coordinate support requires preparation 0.2.")
            eda_continuous_review.constant_support(support["source"], method)
            retained = support.get("retained_support")
            expected = {"retained_samples", "retained_duration_s", "filter_edge_samples", *eda_continuous_review.CONSTANT_SUPPORT}
            require(isinstance(retained, dict) and set(retained) == expected and
                    all(retained[k] == support["source"][k] for k in retained),
                    "Constant stream lost its exact withheld-response support.")
            require(kind != "physiology-events" or spec["expected_rows"] == 0,
                    "A bypassed detector cannot have stored candidate rows.")
    common = [tables._column("time_s", "float64", "s", role="coordinate"),
              tables._column("source_sample_index", "integer", "sample_index", role="index"),
              *[tables._column(k, "float64", "uS", constant) for k in COMPONENTS], tables._column("retained", "boolean", None, role="support")]
    if kind == "physiology-series":
        expected = common
    elif family == "event":
        expected = [tables._column("type", "string", None, role="label"), tables._column("peak_time_s", "float64", "s", role="coordinate"),
                    tables._column("peak_sample_index", "integer", "segment_sample_index", role="index"),
                    tables._column("source_peak_sample", "integer", "sample_index", role="index"),
                    *[tables._column(k, "float64", "s", True, role="derived_event") for k in ("onset_time_s", "recovery_time_s")],
                    *[tables._column(k, "float64", "uS", True) for k in ("amplitude_us", "peak_height_us")],
                    tables._column("recovery_fraction", "float64", "proportion"),
                    *[tables._column(k, "boolean", None, role="support") for k in ("onset_supported", "recovery_supported")]]
    else:
        expected = [tables._column("type", "string", None, role="label"), tables._column("time_s", "float64", "s", role="coordinate"),
                    tables._column("peak_sample", "integer", "segment_sample_index", role="index"),
                    tables._column("source_peak_sample", "integer", "sample_index", role="index"),
                    *[tables._column(k, "float64", "s", True, role="derived_event") for k in ("onset_time_s", "recovery_time_s")],
                    *[tables._column(k, "float64", "uS", True) for k in ("amplitude_us", "peak_height_us")],
                    *[tables._column(k, "float64", "s", True) for k in ("rise_time_s", "recovery_time_from_peak_s")],
                    tables._column("recovery_fraction", "float64", "proportion"), tables._column("missing_reason", "string", None, True, role="support")]
    require(spec["columns"] == expected, "Complete EDA stream column schema differs from its registered producer.")
    support = {"source", "raw_source_omitted", "source_sample_index_definition"} | (
        {"parameters", "detector_error"} if family == "event" else {"method", "retained_support"})
    require(set(spec["support"]) == support and spec["support"]["raw_source_omitted"] is True,
            "EDA table support changed or falsely claims raw samples.")


class VerifiedIndex:
    """Private verified chunk spool; no source or row arrays enter the catalog."""
    def __init__(self, streams, family, source, directory, profile="0.1"):
        self.entries = {}
        self.family = family
        self.directory = Path(directory)
        self.source = source
        self.rows = self.table_count = self.bytes = 0
        require(isinstance(streams, list) and len(streams) in (0, 2), "Registered EDA needs zero or two original streams.")
        if streams:
            require({s["original"]["kind"] for s in streams} == {"physiology-series", "physiology-events"}, "EDA source pair has duplicate or missing kinds.")
        for stream in streams:
            fields(stream, ("original", "original_verification", "path"), "EDA stream input")
            original = stream["original"]
            manifest = verifier_manifest(original, stream["path"])
            bounded(manifest["bytes"], 64*MIB, "stream_bytes", source["report_ref"])
            self.bytes += manifest["bytes"]
            bounded(self.bytes, 96*MIB, "source_stream_bytes", source["report_ref"])
            entry = dict(original=original, manifest=manifest, tables=[])
            by_id = {}
            # Keep one exclusive writer per bounded table. Reopening a growing
            # spool for each chunk is not reliable under Windows supervision.
            # ExitStack also closes every writer on a verifier/parser failure,
            # before model reads or TemporaryDirectory cleanup can begin.
            with ExitStack() as writer_lifetime:
                writers={}
                def on_table(spec):
                    check_eda_table(spec, family, manifest["kind"], profile)
                    self.table_count += 1
                    bounded(self.table_count, 256, "source_tables", source["report_ref"])
                    path = self.directory/f"t{self.table_count:04d}.jsonl"
                    writers[spec["table_id"]]=writer_lifetime.enter_context(path.open("xb"))
                    record = dict(spec=spec, path=path)
                    entry["tables"].append(record)
                    by_id[spec["table_id"]] = record
                def on_rows(table_id, offset, rows):
                    spec = by_id[table_id]["spec"]
                    if family == "continuous" and spec["support"]["source"]["status"] == "descriptive_only":
                        require(manifest["kind"] == "physiology-series" and all(all(row[i] is None for i in (2,3,4)) for row in rows),
                                "Constant coordinate tables cannot contain finite processed substitutes.")
                    self.rows += len(rows)
                    bounded(self.rows, 1000000, "source_rows", source["report_ref"])
                verified = tables.verify_artifact(manifest, on_table=on_table, on_rows=on_rows)
                # The legacy verifier proves framing and values but json.loads
                # may treat lexical -0 as integer zero. Index verified bytes
                # through the exact parser, retaining signed zero and types.
                indexed_rows=0
                with Path(stream["path"]).open("rb") as source_stream:
                    for line in source_stream:
                        bounded(len(line),2*MIB,"stream_line_bytes",source["report_ref"])
                        raw=strict_json(line)
                        if raw["type"]=="table":
                            check_eda_table(raw,family,manifest["kind"],profile);by_id[raw["table_id"]]["spec"]=raw
                        elif raw["type"]=="rows":
                            indexed_rows+=len(raw["rows"])
                            writers[raw["table_id"]].write(json_bytes(dict(offset=raw["offset"],rows=raw["rows"]))+b"\n")
            require(indexed_rows==verified["rows"],"Exact typed index row coverage changed after original verification.")
            receipt = stream["original_verification"]
            require(receipt.get("verified") is True and all(receipt.get(k) == manifest[k] for k in
                    ("kind", "sha256", "bytes", "schema", "tables", "rows", "provenance_sha256")), "Original typed verification receipt differs from its stream.")
            require(verified["provenance"]["source_sha256"] == source["source_hash"] and
                    verified["provenance"]["operation"] == ("eda_events" if family == "event" else "physiology"), "Typed stream belongs to another source or operation.")
            entry["verified"] = verified
            self.entries[manifest["kind"]] = entry

    def replay(self, manifest, identity, on_table=None, on_rows=None):
        entry = self.entries.get(manifest["kind"])
        require(entry is not None and manifest == entry["manifest"], "Read-only model requested a different stream.")
        for table in entry["tables"]:
            spec = table["spec"]
            if on_table:
                on_table(copy.deepcopy(spec))
            if on_rows and all(spec["identity"].get(k) == v for k, v in identity.items()):
                with table["path"].open("rb") as stream:
                    for line in stream:
                        part = strict_json(line)
                        on_rows(spec["table_id"], part["offset"], part["rows"])
        return copy.deepcopy(entry["verified"])


def selected_window_counts(index, family, request, record, selection):
    """Count the exact saved selection before legacy review allocates row lists.

    These predicates mirror the published read-only review's coordinate rules,
    not a detector or estimator. Counts finish over every matching source row so
    a refusal states the true selected total rather than the first excess row.
    """
    parameters=request["report"]["complete_analysis"]["parameters"][record["recording_id"]]
    if family=="event":
        lower=record["time_s"]+parameters["baseline_s"][0]
        upper=record["time_s"]+parameters["recovery_end_s"]
    else:lower,upper=Decimal(selection["start_s"]),Decimal(selection["end_s"])
    identity={k:record[k] for k in (("recording_id","channel") if family=="event" else ("recording_id","segment_id","channel"))}
    counts=dict(samples=0,candidates=0,groups=0)
    for kind,entry in index.entries.items():
        for table in entry["tables"]:
            spec=table["spec"]
            if not all(spec["identity"].get(k)==v for k,v in identity.items()):continue
            columns=[c["name"] for c in spec["columns"]];previous=None
            with table["path"].open("rb") as stream:
                for line in stream:
                    for values in strict_json(line)["rows"]:
                        row=dict(zip(columns,values))
                        if kind=="physiology-series":
                            time=row["time_s"] if family=="event" else Decimal(str(row["time_s"]))
                            selected=lower<=time<=upper
                            if selected:
                                counts["samples"]+=1
                                if previous is None or previous!=row["retained"]:counts["groups"]+=1
                                previous=row["retained"]
                        elif family=="event":counts["candidates"]+=lower<=row["peak_time_s"]<=upper
                        else:
                            onset=row["time_s"] if row["onset_time_s"] is None else row["onset_time_s"]
                            recovery=row["time_s"] if row["recovery_time_s"] is None else row["recovery_time_s"]
                            counts["candidates"]+=Decimal(str(onset))<=upper and Decimal(str(recovery))>=lower
    source=request["report"]["ref"];recovery="smaller_window" if family=="continuous" else "fewer_sources"
    if family == "continuous" and record.get("status") == "descriptive_only":
        if counts["samples"] > 500000:
            refusal = Refusal(source,"coordinate_rows",counts["samples"],500000,"none")
            refusal.detail.update(reason_code="coordinate_rows_limit", message="The complete constant-signal coordinate view exceeds the current 500000-row capacity. A smaller response window cannot repair withheld processing; no evidence was truncated.")
            raise refusal
        require(counts["candidates"] == 0, "Constant coordinate support cannot contain detected candidates.")
        return counts
    # A fixed event method window cannot be narrowed by a figure request.
    bounded(counts["samples"],500000,"window_samples",source,recovery)
    bounded(counts["candidates"],20000 if family=="event" else 5000,"window_candidates",source,recovery)
    bounded(counts["groups"],200,"component_groups",source,recovery)
    return counts


def original_models(index, family, request, record, selection, features, directory, verified_objects):
    counted=selected_window_counts(index,family,request,record,selection)
    module = eda_review if family == "event" else eda_continuous_review
    identity = {k: record[k] for k in ("recording_id", "channel")}
    if family == "continuous":
        identity["segment_id"] = record["segment_id"]
    paths = {str(Path(o["path"]).resolve()): o for o in verified_objects}
    artifact_paths = {str(Path(e["manifest"]["path"]).resolve()): e["manifest"]["sha256"] for e in index.entries.values()}
    def verified_digest(path):
        key = str(Path(path).resolve())
        if key in artifact_paths: return artifact_paths[key]
        found = paths.get(key)
        require(found is not None, "The read-only model tried to access an unbound source.")
        return found["hash"]
    proxy = types.SimpleNamespace(require=require, digest_file=verified_digest, _column=tables._column, ArtifactError=tables.ArtifactError,
        verify_artifact=lambda manifest, on_table=None, on_rows=None: index.replay(manifest, identity, on_table, on_rows))
    # Function-local dependency adaptation: the imported modules themselves stay untouched.
    namespace = dict(module.review.__globals__)
    # Clone module-local helpers too: dispatcher branches must resolve the same
    # verified local dependencies without modifying imported module globals.
    for name, function in list(namespace.items()):
        if isinstance(function, types.FunctionType) and function.__globals__ is module.__dict__:
            namespace[name] = types.FunctionType(function.__code__, namespace, function.__name__, function.__defaults__, function.__closure__)
    namespace["tables"] = proxy
    namespace["save_csv"] = lambda path, fields, rows: {"rows": len(rows)}
    namespace["export_csv"] = lambda directory, name, fields, rows: {"rows": len(rows) if hasattr(rows,"__len__") else sum(1 for _ in rows)}
    if family == "continuous":
        def already_checked(source):
            require(paths.get(str(Path(source["path"]).resolve())) == source, "A read-only source descriptor changed.")
        namespace["check_source"] = already_checked
        def indexed_coordinate_rows(manifest, spec):
            entry = index.entries[manifest["kind"]]
            require(manifest == entry["manifest"], "Coordinate export requested an unbound stream.")
            target = next(t for t in entry["tables"] if t["spec"]["table_id"] == spec["table_id"])
            require(target["spec"] == spec, "Coordinate export changed its original table.")
            with target["path"].open("rb") as stream:
                for line in stream:
                    part = strict_json(line)
                    for i, row in enumerate(part["rows"]):
                        yield {"table_id":spec["table_id"],"table_row_index":part["offset"]+i,
                               **dict(zip((c["name"] for c in spec["columns"]),row))}
        namespace["coordinate_csv_rows"] = indexed_coordinate_rows
    review = types.FunctionType(module.review.__code__, namespace, module.review.__name__, module.review.__defaults__)
    analysis = request["report"]["complete_analysis"]
    parameters = analysis["parameters"][record["recording_id"]]
    base = dict(binding={"report_ref": request["report"]["ref"], "analysis_hash": request["source"]["analysis_hash"],
                         "origin": request["report"]["saved_body"]["origin"], "selection": selection},
                parameters=parameters, features=features, original_source=request["original_source"],
                sealed_objects=request["sealed_objects"], artifacts=[e["manifest"] for e in index.entries.values()],
                export_directory=str(directory))
    if family == "event":
        base.update(schema="brohn-eda-review-request/1.0", event=record,
                    source_events=[e for e in analysis["events"] if e["recording_id"] == record["recording_id"] and e["type"] in ("stimulus_event", "nuisance_event")],
                    source_masks=[m for m in analysis["source_masks"] if m["recording_id"] == record["recording_id"] and m["channel"] == record["channel"]])
    else:
        version = "1.1" if parameters["recipe"] == "eda-neurokit-highpass/1.1" else "1.0"
        base.update(schema="brohn-eda-continuous-review-request/"+version, recording=record, selection=selection)
    model = review(base)
    count_key = "selected_rows" if family=="event" else "selected_coordinate_rows" if model["status"]=="raw_description_only" else "selected_samples"
    require(model["counts"][count_key]==counted["samples"] and
            len(model["candidates"])==counted["candidates"],"Bounded selection count differs from the original read-only review.")
    del model["rows"]
    del model["exports"]
    if family == "continuous":
        missing = [dict(candidate_table_row_index=c["table_row_index"], kind=kind, support="unobserved")
                   for c in model["candidates"] for kind, field in (("onset", "onset_time_s"), ("recovery", "recovery_time_s")) if c[field] is None]
        model["endpoint_coverage"] = dict(unobserved=missing)
    bounded(len(model["candidates"]), 20000 if family == "event" else 5000, "window_candidates", request["report"]["ref"], "smaller_window" if family == "continuous" else "fewer_sources")
    for groups in model["series"].values():
        bounded(len(groups), 200, "component_groups", request["report"]["ref"], "smaller_window")
        bounded(sum(len(g["points"]) for g in groups), 2000, "component_points", request["report"]["ref"], "smaller_window")
    return model


def catalog_item(cell, family, profile="0.1"):
    model, support = cell["model"], cell["original_support"]
    has_trace = model is not None and cell["status"] == "available"
    components = list(COMPONENTS) if has_trace else []
    points = {k: dict(points=sum(len(g["points"]) for g in model["series"][k]) if model else 0,
                      groups=len(model["series"][k]) if model else 0) for k in COMPONENTS}
    candidates = len(model["candidates"]) if model else 0
    markers = model["markers"] if model else []
    if family == "event":
        unobserved = sum(m["support"] == "unobserved" for m in markers)
        outside = sum(m["support"] == "outside_view" for m in markers)
        observed = sum(m["support"] == "saved_candidate" for m in markers)
    else:
        unobserved = len(model["endpoint_coverage"]["unobserved"]) if model else 0
        outside = sum(not m["in_view"] for m in markers)
        observed = sum(m["in_view"] for m in markers)
    identity = cell["identity"]
    label = " | ".join(str(identity[k]) for k in identity if identity[k] is not None)
    raw = cell["status"] == "raw_description_only"
    descriptive_status = support["status"] if family == "event" else ("computed" if support["status"] in ("computed","descriptive_only") else "unavailable") if profile=="0.2" else None
    descriptive_reason = support.get("reason") if family=="event" else (None if descriptive_status=="computed" else support.get("reason")) if profile=="0.2" else None
    scr_status = support["scr_status"] if family=="event" else ("computed" if support["status"]=="computed" else "unavailable") if profile=="0.2" else None
    scr_reason = support.get("scr_reason") if family=="event" else ("exact_constant_signal" if raw else None if scr_status=="computed" else support.get("reason")) if profile=="0.2" else None
    return dict(kind="eda_cell", key=cell["key"], source_family=family, identity=identity, label=label,
        source_record_index=cell["source_record_index"], focusable=family == "continuous" and support["status"] == "computed",
        focus_reason=None if family == "continuous" and support["status"] == "computed" else "fixed_event_method_window" if family == "event" else "exact_constant_signal" if raw else support.get("reason", "no_processed_segment"),
        original_default_bounds=cell["original_default_bounds"], requested_bounds=cell["requested_bounds"],
        status=cell["status"], reason=cell["reason"], original_status=cell["original_status"],
        descriptive_status=descriptive_status, descriptive_reason=descriptive_reason,
        scr_status=scr_status, scr_reason=scr_reason,
        model_hash=cell["model_hash"], components=components, feature_count=len(cell["feature_indices"]), candidate_count=candidates,
        marker_count=observed+outside+unobserved, observed_marker_count=observed, unobserved_marker_count=unobserved, out_of_view_marker_count=outside,
        component_counts=points, numerical_page_counts=dict(points={k: math.ceil(v["points"]/50) for k, v in points.items()}, candidates=math.ceil(candidates/50)),
        marker_page_count=max(1, math.ceil(candidates/50)) if has_trace else 0)


def prepare(request, directory):
    fields(request, ("schema", "report", "source", "display_request", "implementation", "streams", "original_source", "sealed_objects"), "EDA worker request")
    require(request["schema"] == "brohn-eda-display-worker-request/0.1", "Unsupported EDA worker request.")
    report, source = request["report"], request["source"]
    profiles={"saved-eda-display/0.1":"0.1","saved-eda-display/0.2":"0.2"}
    require(request["implementation"].get("profile") in profiles, "Choose an exact EDA preparation profile.")
    profile=profiles[request["implementation"]["profile"]]
    fields(report, ("ref", "saved_body", "complete_analysis"), "Complete saved EDA report")
    analysis = report["complete_analysis"]
    require(analysis == report["saved_body"]["analysis"] and analysis["kind"] == "eda" and analysis["schema"] == "brohn-worker-result/1.0" and
            source["report_ref"] == report["ref"] and source["original_stream_descriptors"] == analysis["artifacts"], "Complete EDA analysis/source binding differs.")
    family = "event" if analysis.get("operation") == "eda_events" else "continuous"
    require(family == "event" or "operation" not in analysis, "Continuous source contains an unsupported operation field.")
    recipes = {"eda-event-highpass/1.0", "eda-event-cvxeda-defaults/1.0"} if family == "event" else {"eda-neurokit-highpass/1.0", *(["eda-neurokit-highpass/1.1"] if profile=="0.2" else [])}
    require(isinstance(analysis["parameters"], dict) and all(p["recipe"] in recipes for p in analysis["parameters"].values()), "Unsupported saved EDA method.")
    normalized = display_request(request["display_request"])
    require(normalized == request["display_request"], "Display request must already use the shared canonical decimal form.")
    require(family == "continuous" or not normalized["continuous_windows"], "Event method windows cannot be overridden.")
    objects = [request["original_source"], *request["sealed_objects"]]
    require(len(objects) <= 256 and sum(o["bytes"] for o in objects) <= 1024*MIB, "Source closure exceeds its held-object profile.")
    for obj in objects:
        check_object(obj)
    require(request["original_source"]["hash"] == analysis["source"]["sha256"] and request["original_source"]["bytes"] == analysis["source"]["bytes"], "Original source differs from scientific provenance.")
    require([s["original"] for s in request["streams"]] == analysis["artifacts"], "Typed stream descriptors changed order or membership.")
    records = analysis["recordings"]
    require(isinstance(records, list) and len(records) > 0, "EDA source has no original event or recording findings.")
    bounded(len(records), 2000, "catalog_cells", report["ref"])
    cells = []
    seen = set()
    overrides = {r["key"]: r for r in normalized["continuous_windows"]}
    used = set()
    with tempfile.TemporaryDirectory(prefix="eda-index-", dir=directory) as spool:
        index = VerifiedIndex(request["streams"], family, {"report_ref": report["ref"], "source_hash": analysis["source"]["sha256"]}, spool,profile)
        for number, record in enumerate(records, 1):
            keys = ("recording_id", "event_id", "channel") if family == "event" else ("recording_id", "segment_id", "channel")
            identity = {k: record.get(k) for k in keys}
            require(all(isinstance(v, str) and v for k, v in identity.items() if k != "segment_id") and
                    (identity.get("segment_id") is None or isinstance(identity["segment_id"], str)), "EDA cell lacks its exact original identity.")
            key = value_hash(dict(report_ref=report["ref"], source_family=family, identity=identity))
            require(key not in seen, "EDA cell identity occurs more than once.")
            seen.add(key)
            p = analysis["parameters"][record["recording_id"]]
            default = (dict(start_s=normalized_decimal(str(p["baseline_s"][0])), end_s=normalized_decimal(str(p["recovery_end_s"]))) if family == "event" else
                       dict(start_s=normalized_decimal(str(record["start_time_s"])), end_s=normalized_decimal(str(record["end_time_s"]))) if record["status"] in ("computed","descriptive_only") else None)
            bounds = copy.deepcopy(default)
            if key in overrides:
                require(family == "continuous" and default is not None and record["status"] == "computed", "Unavailable/event cell cannot have a new window.")
                override = overrides[key]
                require(Decimal(default["start_s"]) <= Decimal(override["start_s"]) < Decimal(override["end_s"]) <= Decimal(default["end_s"]), "Requested window leaves its original observed segment.")
                bounds = {k: override[k] for k in ("start_s", "end_s")}
                used.add(key)
            feature_indices = [i for i, f in enumerate(analysis["features"], 1) if all(f.get(k) == v for k, v in identity.items())]
            features = [analysis["features"][i-1] for i in feature_indices]
            selection = copy.deepcopy(identity)
            if family == "continuous" and bounds is not None:
                selection.update(bounds)
            model = None
            if request["streams"] and (family == "event" or record["status"] in ("computed","descriptive_only")):
                model = original_models(index, family, request, record, selection, features, directory, objects)
            cell = dict(key=key, identity=identity, source_record_index=number, original_status=record["status"],
                status=model["status"] if model else "unavailable", reason=None if model and model["status"] == "available" else
                "exact_constant_signal" if model and model["status"]=="raw_description_only" else "no_processed_samples_in_saved_window" if model else record.get("reason") or "no_processed_artifacts",
                selection=selection, original_default_bounds=default, requested_bounds=bounds, original_support=record,
                feature_indices=feature_indices, model=model, model_hash=value_hash(model) if model is not None else None,
                coverage=dict(features=len(features), source_record_preserved=True, scientific_processing=False))
            cells.append(cell)
            bounded(len(json_bytes(cells)), 24*MIB, "prepared_evidence_bytes", report["ref"], "smaller_window")
        require(used == set(overrides), "Window request refers to a missing original EDA cell.")
        catalog = [catalog_item(cell, family,profile) for cell in cells]
        bounded(len(json_bytes(catalog)), 2*MIB, "catalog_bytes", report["ref"])
        coverage = dict(cells=len(cells), available_cells=sum(c["status"] == "available" for c in cells),
                        unavailable_cells=sum(c["status"] in ("unavailable","no_processed_samples") for c in cells), features=len(analysis["features"]),
                        original_artifacts=len(request["streams"]), original_stream_bytes=index.bytes,
                        original_rows=index.rows, original_tables=index.table_count, complete_processed_rows=True,
                        complete_raw_series_included=False, original_raw_preview_preserved=True, scientific_processing=False)
        if profile=="0.2":
            coverage.update(descriptive_only_cells=sum(c["status"]=="raw_description_only" for c in cells),complete_coordinate_rows=True,
                coordinate_only_rows=sum(t["spec"]["expected_rows"] for e in index.entries.values() if e["manifest"]["kind"]=="physiology-series"
                    for t in e["tables"] if family=="continuous" and t["spec"]["support"]["source"]["status"]=="descriptive_only"))
        evidence = dict(schema="brohn-eda-display-evidence/"+profile, source_family=family, source=source,
                        display_request=normalized, implementation=request["implementation"], cells=cells, coverage=coverage)
        bounded(len(json_bytes(evidence)), 24*MIB, "prepared_evidence_bytes", report["ref"], "smaller_window")
        verified = [entry["verified"] for entry in index.entries.values()]
    # Held sources must still be the same original files after model extraction.
    for obj in objects:
        check_object(obj)
    for stream in request["streams"]:
        manifest = verifier_manifest(stream["original"], stream["path"])
        require(Path(stream["path"]).stat().st_size == manifest["bytes"] and tables.digest_file(stream["path"]) == manifest["sha256"], "Typed source changed after preparation.")
    return evidence, catalog, verified


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--request", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--artifacts", type=Path)
    args = parser.parse_args()
    require(not args.output.exists() and args.output.parent.is_dir(), "Result output must be a new file in an owned directory.")
    artifact = None
    artifact_created = False
    try:
        require(args.request.is_file() and args.request.stat().st_size <= 48*MIB, "EDA request exceeds 48 MiB or is absent.")
        raw = args.request.read_bytes()
        request = strict_json(raw)
        runtime = {"Python": {"implementation": platform.python_implementation(), "version": platform.python_version()}}
        require(runtime["Python"] == request["implementation"].get("runtime", {}).get("Python"), "EDA display Python runtime differs from its pinned profile.")
        directory = args.artifacts or args.output.parent/"artifacts"
        directory.mkdir(exist_ok=True)
        require(directory.is_dir() and not directory.is_symlink(), "Choose an owned ordinary artifact directory.")
        artifact = directory/"eda-display.json"
        require(not artifact.exists(), "Prepared evidence output already exists.")
        evidence, catalog, streams = prepare(request, directory)
        data = json_bytes(evidence)
        digest = hashlib.sha256(data).hexdigest()
        result = dict(schema="brohn-eda-display-worker-result/0.1", artifact=dict(path=artifact.name, sha256=digest, bytes=len(data), media_type="application/json"),
            source_family=evidence["source_family"], source=evidence["source"], display_request=evidence["display_request"],
            implementation=evidence["implementation"], catalog=catalog, coverage=evidence["coverage"],
            verification=dict(schema="brohn-eda-display-verification/0.1", request_sha256=hashlib.sha256(raw).hexdigest(),
                analysis_value_hash=value_hash(request["report"]["complete_analysis"]), evidence_sha256=digest, evidence_bytes=len(data),
                original_streams=streams, source_objects=[{k: o[k] for k in ("hash", "bytes")} for o in [request["original_source"], *request["sealed_objects"]]],
                runtime=runtime, complete=True, scientific_processing=False))
        with artifact.open("xb") as output:
            artifact_created = True
            output.write(data)
        with args.output.open("xb") as output:
            output.write(json_bytes(result))
        return 0
    except Exception as error:
        # Only this invocation's artifact may be removed. Never remove an input.
        if artifact_created and artifact is not None and artifact.exists():
            artifact.unlink()
        result = dict(schema="brohn-eda-display-worker-error/0.1", status="error", error={"type": type(error).__name__, "message": str(error)[:2000]})
        if isinstance(error, Refusal):
            result = error.detail
        with args.output.open("xb") as output:
            output.write(json_bytes(result))
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
