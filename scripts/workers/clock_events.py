"""Bounded original marker selection component; not event matching or authority."""
from __future__ import annotations

import json
from clock_source import inspect_stream, _source, _rows, _exact_json
from stream_extract import require

MAX_VALUE_BYTES = 4096
MAX_OUTPUT_BYTES = 2 * 1024**2


def event_page(track, query="", offset=0, limit=40):
    require(type(track) is dict and track.get("kind") == "markers", "Choose one original marker channel.")
    require(type(query) is str and len(query.encode("utf-8")) <= 240,
            "Search recorded marker values using at most 240 UTF-8 bytes.")
    require(type(offset) is int and 0 <= offset <= 2_000_000 and type(limit) is int and 1 <= limit <= 100,
            "Choose a bounded original-event page.")
    support = inspect_stream(track)
    channel = track["channel"]["id"]
    count = matched = eligible = 0
    events = []
    search = query.casefold()
    for row in _rows(_source(track["samples"])):
        count += 1
        value = _exact_json(row["values"][channel])
        # A long original value is never truncated into an apparently complete
        # selectable anchor. It can be inspected in the complete original source.
        reasons = []
        if len(value.encode("utf-8")) > MAX_VALUE_BYTES:
            reasons.append("event_value_exceeds_4096_byte_anchor_bound")
        if row["timestamp_state"] != "observed" or row["source_timestamp"] is None or row["reconstructed_timestamp"]:
            reasons.append("no_original_observed_timestamp")
        if row["value_states"][channel] != "observed" or row["values"][channel] is None:
            reasons.append("no_original_observed_value")
        if not reasons:
            eligible += 1
        if search not in value.casefold():
            continue
        rank = matched
        matched += 1
        if not offset <= rank < offset + limit:
            continue
        events.append({"source_sequence": row["sequence"], "source_segment": row["segment_id"],
                       "clock_id": row["clock_id"], "source_timestamp": row["source_timestamp"],
                       "timestamp_unit": row["timestamp_unit"], "timestamp_state": row["timestamp_state"],
                       "reconstructed_timestamp": row["reconstructed_timestamp"],
                       "identity": row["identity"], "channel_id": channel,
                       "value_json": value if len(value.encode("utf-8")) <= MAX_VALUE_BYTES else None,
                       "value_state": row["value_states"][channel], "value_bytes": len(value.encode("utf-8")),
                       "selectable": not reasons, "unavailable_reasons": reasons})
    require(count == support["source_rows"], "Complete event source count changed after inspection.")
    _source(track["samples"]); _source(track["evidence"])
    result = {"schema": "brohn-clock-event-page/0.1", "scope": "complete_source_component_only",
            "query": query, "offset": offset, "limit": limit, "matched_rows": matched,
            "source_rows": count, "selectable_source_rows": eligible, "events": events,
            "has_next": offset + len(events) < matched,
            "next_offset": offset + len(events) if offset + len(events) < matched else None,
            "clock": support["clock"], "identity": support["identity"], "origin": support["origin"],
            "samples_sha256": support["samples_sha256"], "evidence_sha256": support["evidence_sha256"],
            "ordering": "original_source_sequence", "event_equivalence": "not_inferred",
            "authorization": "requires_current_R_source_project_and_publication_guards"}
    require(len(json.dumps(result, ensure_ascii=True, allow_nan=False, separators=(",", ":")).encode("ascii")) <= MAX_OUTPUT_BYTES,
            "Event page exceeds two MiB; choose fewer rows per page.")
    return result
