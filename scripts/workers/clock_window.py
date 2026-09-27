"""External original-row export from freshly reviewed event-anchor evidence.

No application authorization, persisted map trust, plotting or scientific scoring.
Caller supplies a new owned scratch directory; production still requires native
source handles and R membership/current-project/publication guards.
"""
from __future__ import annotations

import copy
import csv
from fractions import Fraction
import hashlib
import io
import json
import os
from pathlib import Path

from clock_preview import build_preview, _arithmetic_clock
from clock_affine import build_affine, map_position, parse_decimal
from clock_source import _source, _rows, _Number, _exact_json, MAX_LINE_BYTES
from stream_extract import require, pairs, digest, MAX_ROWS

SCHEMA = "brohn-clock-window-input/0.1"
MAX_EXPORT = 64 * 1024**2
PAGE_ROWS = 100
COLUMNS = ["recording_side", "track_id", "source_stream_id", "channel_id", "kind",
           "source_sequence", "source_segment", "source_clock_id", "source_timestamp",
           "timestamp_unit", "timestamp_state", "reconstructed_timestamp", "value_json", "value_state", "unit",
           "origin", "identity_json", "participant_id", "session_id", "condition_id", "exposure_id",
           "placement", "coordinate_policy", "original_seconds_numerator", "original_seconds_denominator",
           "reference_seconds_numerator", "reference_seconds_denominator", "reference_relative_seconds_numerator",
           "reference_relative_seconds_denominator", "preview_sha256", "source_request_sha256",
           "samples_sha256", "evidence_sha256"]


def _json(value):
    return json.dumps(value, ensure_ascii=True, allow_nan=False, sort_keys=True, separators=(",", ":")).encode("ascii")


def _hash(value):
    return hashlib.sha256(_json(value)).hexdigest()


def _fraction(pair):
    return Fraction(int(pair["numerator"]), int(pair["denominator"]))


def _pair(value):
    return {"numerator": str(value.numerator), "denominator": str(value.denominator)}


def _original_request_binding(request):
    """Portable exact request binding: local resolver paths are not authority."""
    value = copy.deepcopy(request)
    for side in ("source", "reference"):
        for track in [value[side]["marker"], *value[side]["tracks"]]:
            for kind in ("samples", "evidence"):
                track[kind].pop("path", None)
    return value


def _exact_rows(path):
    # Preserve every numerical value token, including integer -0. Source
    # sequences are converted separately after complete source qualification.
    with Path(path).open("rb") as source:
        while line := source.readline(MAX_LINE_BYTES + 1):
            require(len(line) <= MAX_LINE_BYTES and line.endswith(b"\n"), "Oversized or incomplete canonical source row.")
            yield json.loads(line.decode("utf-8"), object_pairs_hook=pairs, parse_int=_Number, parse_float=_Number,
                             parse_constant=lambda _: require(False, "Nonfinite canonical JSON literal."))


class _Budget:
    def __init__(self):
        self.bytes = 0

    def add(self, data):
        require(self.bytes + len(data) <= MAX_EXPORT, "Combined clock-window exports exceed64MiB; choose a narrower window.")
        self.bytes += len(data)
        return data


class _CSV:
    def __init__(self, path, budget):
        self.path, self.budget, self.rows = path, budget, 0
        self.file = path.open("xb")
        try:
            self._write(COLUMNS)
        except Exception:
            self.file.close();raise

    def _write(self, values):
        text = io.StringIO(newline="")
        csv.writer(text, lineterminator="\n").writerow(values)
        self.file.write(self.budget.add(text.getvalue().encode("utf-8")))

    def write(self, row):
        self._write([row.get(key) for key in COLUMNS]); self.rows += 1

    def close(self):
        self.file.close()


def run(request):
    require(type(request) is dict and set(request) == {"schema", "preview_request", "selection", "output_directory"}
            and request["schema"] == SCHEMA, "Unsupported original-row clock-window request.")
    selection = request["selection"]
    require(type(selection) is dict and set(selection) == {"start_s", "end_s", "offset"}, "Choose an exact window and numerical page.")
    start, end = parse_decimal(selection["start_s"]), parse_decimal(selection["end_s"])
    offset = selection["offset"]
    require(0 <= start < end <= 86400, "Choose a positive reference-relative window of at most86400 seconds.")
    require(type(offset) is int and 0 <= offset <= MAX_ROWS and offset % PAGE_ROWS == 0, "Choose a bounded100-row numerical page.")
    require(type(request["output_directory"]) is str and request["output_directory"], "Choose a new owned scratch directory.")
    destination = Path(request["output_directory"]).resolve()
    require(destination.parent.is_dir() and not destination.exists(), "Use a fresh nonexisting directory inside the caller's owned scratch.")
    original = copy.deepcopy(request["preview_request"])
    # Never accept or deserialize a previously saved preview/map as authority.
    preview = build_preview(original)
    source_clock, reference_clock = [preview["recordings"][side]["clock"] for side in ("source", "reference")]
    anchors = [{"source": a["source"]["source_timestamp"], "reference": a["reference"]["source_timestamp"]} for a in preview["anchors"]]
    mapping = build_affine(anchors, _arithmetic_clock(source_clock), _arithmetic_clock(reference_clock))
    manifest = mapping.manifest()
    source_scale = _fraction(manifest["source_clock"]["seconds_per_unit"])
    reference_scale = _fraction(manifest["reference_clock"]["seconds_per_unit"])
    source_start, source_end = [_fraction(a["source_seconds"]) for a in manifest["anchors"]]
    reference_start, reference_end = [_fraction(a["reference_seconds"]) for a in manifest["anchors"]]
    require(end <= reference_end-reference_start, "Window must remain inside the closed defining-anchor span; extrapolation is unsupported.")
    source_binding = _original_request_binding(original)
    binding = {"preview_sha256": _hash(preview), "source_request_sha256": _hash(source_binding),
               "selection_sha256": _hash(selection), "mapping_sha256": _hash(manifest)}
    tracks = [(side, t) for side in ("source", "reference") for t in [original[side]["marker"], *original[side]["tracks"]]]
    artifacts = [t[k] for _, t in tracks for k in ("samples", "evidence")]
    # Recheck at the export boundary, after fresh complete preview qualification.
    for artifact in artifacts:
        _source(artifact)
    destination.mkdir(exist_ok=False)
    budget = _Budget()
    selected_path, unplaced_path, segments_path = [destination/(name+".partial") for name in ("selected.csv", "unplaced.csv", "segments.jsonl")]
    selected = _CSV(selected_path, budget)
    unplaced = None; segment_file = None
    total = {key: 0 for key in ("source_rows", "selected_rows", "outside_anchor_span_rows", "outside_window_rows", "unplaced_rows", "missing_source_values", "missing_selected_values")}
    summaries, ui_rows = [], []
    try:
        unplaced = _CSV(unplaced_path, budget); segment_file = segments_path.open("xb")
        for side, track in tracks:
            samples, evidence = _source(track["samples"]), _source(track["evidence"])
            counts = {key: 0 for key in total}; selected_segments = {}
            for row in _exact_rows(samples):
                counts["source_rows"] += 1
                sequence = int(row["sequence"])
                require(sequence == counts["source_rows"] and sequence <= MAX_ROWS and row["stream_id"] == track["source_stream_id"], "Canonical source sequence or identity changed after preview.")
                channel = track["channel"]["id"]
                value, state = row["values"][channel], row["value_states"][channel]
                missing = state != "observed" or value is None
                counts["missing_source_values"] += int(missing)
                identity = row["identity"]
                record = {"recording_side": side, "track_id": track["id"], "source_stream_id": track["source_stream_id"], "channel_id": channel,
                    "kind": track["kind"], "source_sequence": sequence, "source_segment": row["segment_id"], "source_clock_id": row["clock_id"],
                    "source_timestamp": row["source_timestamp"], "timestamp_unit": row["timestamp_unit"], "timestamp_state": row["timestamp_state"],
                    "reconstructed_timestamp": row["reconstructed_timestamp"], "value_json": _exact_json(value), "value_state": state,
                    "unit": track["channel"].get("unit"), "origin": track["origin"], "identity_json": _exact_json(identity),
                    **{key: identity.get(key) for key in ("participant_id", "session_id", "condition_id", "exposure_id")},
                    "preview_sha256": binding["preview_sha256"], "source_request_sha256": binding["source_request_sha256"],
                    "samples_sha256": track["samples"]["hash"], "evidence_sha256": track["evidence"]["hash"]}
                placeable = row["timestamp_state"] == "observed" and row["source_timestamp"] is not None and row["reconstructed_timestamp"] is False
                if not placeable:
                    counts["unplaced_rows"] += 1;record.update(placement="unplaced",coordinate_policy="no_time_assigned")
                    unplaced.write(record);continue
                original_s = parse_decimal(row["source_timestamp"])*(source_scale if side == "source" else reference_scale)
                lo, hi = (source_start, source_end) if side == "source" else (reference_start, reference_end)
                if not lo <= original_s <= hi:
                    counts["outside_anchor_span_rows"] += 1;continue
                if side == "source":
                    mapped = map_position(mapping, row["source_timestamp"])
                    reference_s = _fraction(mapped["mapped_reference_seconds"])
                    relative_s = _fraction(mapped["mapped_relative_to_reference_anchor_seconds"])
                else:
                    reference_s = original_s;relative_s = original_s-reference_start
                if not start <= relative_s < end:
                    counts["outside_window_rows"] += 1;continue
                counts["selected_rows"] += 1;counts["missing_selected_values"] += int(missing)
                selected_segments[row["segment_id"]] = selected_segments.get(row["segment_id"], 0)+1
                record.update(placement="selected_window",coordinate_policy="reviewed_affine_source" if side == "source" else "original_reference_coordinate")
                for prefix, value in (("original_seconds",original_s),("reference_seconds",reference_s),("reference_relative_seconds",relative_s)):
                    record[prefix+"_numerator"] = str(value.numerator);record[prefix+"_denominator"] = str(value.denominator)
                if offset <= selected.rows < offset+PAGE_ROWS:
                    ui_rows.append(record)
                selected.write(record)
            require(counts["source_rows"] == track["sample_count"], "Complete original source count changed after preview.")
            require(counts["source_rows"] == sum(counts[k] for k in ("selected_rows","outside_anchor_span_rows","outside_window_rows","unplaced_rows")), "Source coverage counts do not reconcile.")
            segments = 0
            # Preserve every complete original boundary record, including gaps
            # outside this viewport, without conflating them with clock accuracy.
            with evidence.open("rb") as source:
                while line := source.readline(MAX_LINE_BYTES+1):
                    require(len(line)<=MAX_LINE_BYTES and line.endswith(b"\n"), "Oversized or incomplete source evidence row.")
                    item = json.loads(line.decode("utf-8"),object_pairs_hook=pairs)
                    if item.get("type") != "source_segment":continue
                    segments += 1
                    evidence_row = {"recording_side":side,"track_id":track["id"],"source_segment":item["id"],
                        "selected_rows":selected_segments.get(item["id"],0),"segment_json":line.decode("utf-8").rstrip("\r\n"),
                        "evidence_sha256":track["evidence"]["hash"],**binding}
                    segment_file.write(budget.add(_json(evidence_row)+b"\n"))
            require(segments == track["segment_count"], "Original segment count changed after preview.")
            summaries.append({"recording_side":side,"track_id":track["id"],"source_stream_id":track["source_stream_id"],
                "channel":copy.deepcopy(track["channel"]),"clock":copy.deepcopy(track["clock"]),"origin":track["origin"],
                "samples":{k:track["samples"][k] for k in ("hash","bytes")},"evidence":{k:track["evidence"][k] for k in ("hash","bytes")},
                "segment_count":segments,**counts})
            for key in total:total[key] += counts[key]
            _source(track["samples"]);_source(track["evidence"])
        require(offset == 0 if not selected.rows else offset < selected.rows, "Numerical page is outside the complete selected row count.")
    finally:
        selected.close()
        if unplaced is not None:unplaced.close()
        if segment_file is not None:segment_file.close()
    descriptors = []
    for tmp, kind, rows in ((selected_path,"selected_original_rows",selected.rows),(unplaced_path,"all_source_unplaced_rows",unplaced.rows),
                             (segments_path,"complete_original_segments",sum(s["segment_count"] for s in summaries))):
        descriptors.append({"file":tmp.name.removesuffix(".partial"),"sha256":digest(tmp),"bytes":tmp.stat().st_size,"kind":kind,"rows":rows,"binding":binding})
    result = {"schema":"brohn-clock-window/0.1","status":"available" if selected.rows else "empty_window",
        "scope":"source_qualified_window_export_component_only","binding":binding,"source_request":source_binding,"preview":preview,
        "selection":copy.deepcopy(selection),"window_interval":"reference-relative start inclusive, end exclusive",
        "mapping_support":"closed defining-anchor span; end anchor is retained evidence, not included at an exclusive window end",
        "unplaced_scope":"complete original selected tracks; no window membership or time inferred","row_order":"source then reference; marker then selected signals; original sequence within each track",
        "counts":total,"tracks":summaries,"rows":ui_rows,"page_size":PAGE_ROWS,"artifacts":descriptors,
        "physical_synchronization":"not_established","uncertainty":"unknown","scientific_scoring":"not_performed",
        "authorization":"requires_current_R_membership_project_and_native_publication_guards"}
    manifest_bytes = _json(result)+b"\n";budget.add(manifest_bytes)
    pending_manifest=destination/"manifest.json.partial"
    with pending_manifest.open("xb") as target:target.write(manifest_bytes)
    for artifact in artifacts:_source(artifact)
    # Only bounded, fully verified outputs receive final names. No accepted
    # manifest exists for an oversized, corrupt or otherwise failed scratch run.
    for tmp in (selected_path,unplaced_path,segments_path):
        final=tmp.with_suffix("");os.link(tmp,final);tmp.unlink()
    for artifact in artifacts:_source(artifact)
    os.link(pending_manifest,destination/"manifest.json");pending_manifest.unlink()
    return result
