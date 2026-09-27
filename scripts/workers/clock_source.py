"""External complete-source qualification component for reviewed clock maps.

Resolves explicitly selected marker rows from pinned canonical artifacts.
Does not authorize a project, match events, fit a map, publish or score data.
"""
from __future__ import annotations

from pathlib import Path
import json
import re

from stream_extract import digest, require, pairs, MAX_ROWS, MAX_BYTES
from clock_affine import parse_decimal

MAX_LINE_BYTES = 8 * 1024**2
MAX_SELECTED_EVENTS = 64
UNSAFE = {"declared_reset", "timestamp_reversal", "clock_id_change",
          "duplicate_signal_timestamp", "clock_offset_collection_reversal"}


class _Number(str):
    """An original floating JSON token, not a binary approximation."""


def _exact_json(value):
    if isinstance(value, _Number):
        return str(value)
    if isinstance(value, list):
        return "[" + ",".join(_exact_json(x) for x in value) + "]"
    if isinstance(value, dict):
        return "{" + ",".join(json.dumps(k, ensure_ascii=False) + ":" + _exact_json(v) for k, v in value.items()) + "}"
    return json.dumps(value, ensure_ascii=False, allow_nan=False, separators=(",", ":"))


def _integer(value, lower, upper):
    return type(value) is int and lower <= value <= upper


def _identity(value):
    require(isinstance(value, dict) and set(value) <= {"participant_id", "session_id", "condition_id", "exposure_id"}
            and all(type(v) is str and bool(v.strip()) and len(v.encode("utf-8")) <= 500 for v in value.values()),
            "Original identities must retain their explicit text encoding.")
    stable = {key: value.get(key) for key in ("participant_id", "session_id")}
    require(all(type(v) is str and bool(v.strip()) for v in stable.values()),
            "Explicit original participant and session identities are required.")
    return stable


def _source(ref):
    require(isinstance(ref, dict) and set(ref) == {"path", "hash", "bytes"},
            "Pin the exact original artifact path, hash and byte count.")
    require(isinstance(ref["path"], str) and _integer(ref["bytes"], 0, MAX_BYTES)
            and isinstance(ref["hash"], str) and re.fullmatch(r"[a-f0-9]{64}", ref["hash"]),
            "Invalid original artifact reference.")
    path = Path(ref["path"]).resolve()
    require(path.is_file() and path.stat().st_size == ref["bytes"] and digest(path) == ref["hash"],
            "Pinned clock source failed its size/SHA-256 check.")
    return path


def _rows(path):
    with path.open("rb") as source:
        while True:
            line = source.readline(MAX_LINE_BYTES + 1)
            if not line:
                return
            require(len(line) <= MAX_LINE_BYTES and line.endswith(b"\n"),
                    "A canonical row is oversized or incomplete.")
            yield json.loads(line.decode("utf-8"), object_pairs_hook=pairs, parse_float=_Number,
                             parse_constant=lambda _: require(False, "Nonfinite JSON literal."))


def _clock(clock):
    require(isinstance(clock, dict) and type(clock.get("id")) is str and bool(clock["id"])
            and clock.get("kind") in ("monotonic", "device", "unix")
            and clock.get("representation") == "decimal_string",
            "Choose an explicit supported original clock.")
    unit = clock.get("unit")
    require(unit in ("s", "ms", "us", "ns", "ticks"), "Unsupported original clock unit.")
    if unit == "ticks":
        require(parse_decimal(clock.get("seconds_per_tick")) > 0, "Clock tick scale must be positive.")
    else:
        require(clock.get("seconds_per_tick") is None, "A standard unit cannot override its clock scale.")
    return clock


def inspect_stream(track, event_sequences=()):
    """Read every original row; return selected marker evidence and full support.

    This first profile refuses any ambiguous/reset clock epoch in the stream.
    Declared acquisition gaps and missing/unplaced values remain counted.
    Calling code must still compare identity/clock domains across chosen tracks.
    """
    require(isinstance(track, dict), "Choose one pinned original stream.")
    clock = _clock(track.get("clock"))
    quality = track.get("preservation")
    require(isinstance(quality, dict) and quality.get("complete_source_samples_retained") is True
            and quality.get("clock_correction_applied") is False and quality.get("dejitter_applied") is False,
            "Use the importer's preserved timestamp stage without another correction or dejitter step.")
    require(track.get("origin") in ("sample", "pilot", "live", "imported"), "Declare one original data origin.")
    require(track.get("kind") in ("signal", "markers"), "Choose a classified signal or marker stream.")
    require(_integer(track.get("sample_count"), 1, MAX_ROWS)
            and _integer(track.get("segment_count"), 1, 100_000), "Invalid complete source counts.")
    require(type(track.get("source_stream_id")) is str and bool(track["source_stream_id"]), "Pin the source stream identity.")
    channel = track.get("channel")
    require(isinstance(channel, dict) and type(channel.get("id")) is str and bool(channel["id"]), "Pin one source channel.")
    if track["kind"] == "signal":
        require(channel.get("value_type") in ("float64", "float32", "int64", "int32", "int16", "int8"),
                "Choose a scalar numeric signal channel.")
    require(isinstance(event_sequences, (list, tuple)) and len(event_sequences) <= MAX_SELECTED_EVENTS
            and all(_integer(x, 1, track["sample_count"]) for x in event_sequences)
            and len(set(event_sequences)) == len(event_sequences), "Select distinct bounded original marker row numbers.")
    require(not event_sequences or track["kind"] == "markers", "Anchor evidence must come from selected original marker rows.")
    samples, evidence = _source(track["samples"]), _source(track["evidence"])
    segments = {}
    for item in _rows(evidence):
        if item.get("type") != "source_segment":
            continue
        require(type(item.get("id")) is str and item["id"] not in segments, "Duplicate or absent source segment identity.")
        reasons = item.get("boundary_reasons")
        require(isinstance(reasons, list) and all(type(x) is str for x in reasons), "Original segment reasons are unavailable.")
        require(not UNSAFE.intersection(reasons), "Clock reset or ambiguous epoch needs a separately supported epoch map.")
        require(_integer(item.get("first_sequence"), 1, track["sample_count"])
                and _integer(item.get("last_sequence"), item["first_sequence"], track["sample_count"]),
                "Invalid original segment row bounds.")
        require(type(item.get("clock_id")) is str and item["clock_id"] == clock["id"]
                and _integer(item.get("sample_count"), 1, track["sample_count"])
                and item["sample_count"] == item["last_sequence"] - item["first_sequence"] + 1,
                "Original segment clock or sample count is inconsistent.")
        _identity(item.get("identity"))
        for name in ("start_timestamp", "end_timestamp"):
            require(name in item, "Original segment timestamp boundary is unavailable.")
            if item[name] is not None:
                parse_decimal(item[name])
        segments[item["id"]] = item
        require(len(segments) <= 100_000, "Too many original source segments.")
    require(len(segments) == track["segment_count"], "Complete source segment count changed.")
    identity = None
    count = missing = unplaced = 0
    selected = {}
    previous_observed = None
    actual_segments = {}
    previous_segment = None
    closed_segments = set()
    for row in _rows(samples):
        count += 1
        require(count <= MAX_ROWS and type(row.get("sequence")) is int and row["sequence"] == count
                and type(row.get("stream_id")) is str and row["stream_id"] == track["source_stream_id"], "Original source ordering or stream identity changed.")
        segment = row.get("segment_id")
        require(type(segment) is str and segment in segments and segments[segment]["first_sequence"] <= count <= segments[segment]["last_sequence"],
                "A source row changed its declared segment.")
        if segment != previous_segment:
            require(segment not in closed_segments, "Original source segments are not contiguous.")
            if previous_segment is not None:
                closed_segments.add(previous_segment)
            previous_segment = segment
        actual_segments.setdefault(segment, [count, count])[1] = count
        require(type(row.get("clock_id")) is str and type(row.get("timestamp_unit")) is str
                and row["clock_id"] == clock["id"] and row["timestamp_unit"] == clock["unit"],
                "A source row changed its declared original clock.")
        declared = row.get("identity")
        stable = _identity(declared)
        if identity is None:
            identity = stable
        require(stable == identity, "A stream contains different participant/session identities.")
        require(declared == segments[segment]["identity"], "Original segment identity differs from its source rows.")
        require(isinstance(row.get("values"), dict) and channel["id"] in row["values"]
                and isinstance(row.get("value_states"), dict) and channel["id"] in row["value_states"],
                "A source row lacks the selected channel.")
        state, value = row["value_states"][channel["id"]], row["values"][channel["id"]]
        if state != "observed" or value is None:
            missing += 1
        require(type(row.get("reconstructed_timestamp")) is bool, "Original reconstructed-timestamp status is unavailable.")
        observed_time = row.get("timestamp_state") == "observed" and row.get("source_timestamp") is not None
        boundary_time = row["source_timestamp"] if observed_time else None
        if count == segments[segment]["first_sequence"]:
            require(boundary_time == segments[segment]["start_timestamp"], "Original segment start timestamp differs from its source row.")
        if count == segments[segment]["last_sequence"]:
            require(boundary_time == segments[segment]["end_timestamp"], "Original segment end timestamp differs from its source row.")
        placeable = observed_time and row["reconstructed_timestamp"] is False
        if not placeable:
            unplaced += 1
        else:
            time = parse_decimal(row["source_timestamp"])
            require(previous_observed is None or time >= previous_observed, "Original timestamps reverse without an unambiguous epoch.")
            if track["kind"] == "signal":
                require(previous_observed is None or time != previous_observed, "Duplicate signal timestamps need epoch review.")
            previous_observed = time
        if count in event_sequences:
            require(placeable and state == "observed" and value is not None, "Selected marker has no original observed timestamp/value.")
            value_json = _exact_json(value)
            require(len(value_json.encode("utf-8")) <= 4096, "Selected marker value exceeds the bounded event preview.")
            selected[count] = {"source_sequence": count, "source_segment": segment,
                               "source_timestamp": row["source_timestamp"], "timestamp_unit": clock["unit"],
                               "clock_id": clock["id"], "channel_id": channel["id"],
                               "value_json": value_json, "value_state": state, "identity": declared}
    require(count == track["sample_count"] and set(actual_segments) == set(segments), "Complete original source counts changed.")
    require(all(actual_segments[key] == [segment["first_sequence"], segment["last_sequence"]]
                for key, segment in segments.items()), "Original segment endpoints do not match their full source rows.")
    require(len(selected) == len(event_sequences), "A selected original marker row is missing.")
    # A caller still needs immutable native handles during publication. These
    # complete after-reads additionally refuse changed standalone fixtures.
    _source(track["samples"]); _source(track["evidence"])
    return {"schema": "brohn-clock-source-inspection/0.1", "clock": clock,
            "identity": identity, "origin": track["origin"], "source_rows": count,
            "missing_values": missing, "unplaced_rows": unplaced,
            "segments": [{key: segment[key] for key in ("id", "first_sequence", "last_sequence", "sample_count", "clock_id",
                         "identity", "start_timestamp", "end_timestamp", "boundary_reasons")} for segment in segments.values()],
            "events": [selected[x] for x in event_sequences],
            "samples_sha256": track["samples"]["hash"], "evidence_sha256": track["evidence"]["hash"],
            "timestamp_stage": "importer_preserved_coordinates", "physical_synchronization": "not_established"}
