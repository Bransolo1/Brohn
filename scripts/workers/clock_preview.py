"""External source-qualified preview; R authorization/publication remain required.

Reads original artifacts and selected event rows. Never accepts typed anchor
times, infers event equivalence, changes source timestamps or scores a signal.
"""
from __future__ import annotations

import copy
import json
import re

from clock_source import inspect_stream, _source
from clock_affine import build_affine, check_event, PROFILE
from stream_extract import require, MAX_ROWS, MAX_BYTES

SCHEMA = "brohn-clock-preview-input/0.1"
MAX_OUTPUT = 1024 * 1024
MAX_CHECKS = 16


def _text(value, maximum):
    return type(value) is str and bool(value.strip()) and len(value.encode("utf-8")) <= maximum


def _reference(value):
    require(type(value) is dict and set(value) == {"id", "revision", "hash"}
            and _text(value["id"], 500) and type(value["revision"]) is int and value["revision"] > 0
            and type(value["hash"]) is str and re.fullmatch(r"[a-f0-9]{64}", value["hash"]),
            "Pin the exact dataset/import reference supplied by the authorized R request.")


def _side(value):
    require(type(value) is dict and set(value) == {"dataset", "imported", "marker", "tracks"},
            "Choose a pinned recording/import, one original marker channel and one or two signal channels.")
    _reference(value["dataset"]); _reference(value["imported"])
    require(type(value["tracks"]) is list and 1 <= len(value["tracks"]) <= 2,
            "Choose one or two source signal channels on each recording.")
    tracks = [value["marker"], *value["tracks"]]
    require(all(type(t) is dict and _text(t.get("id"), 1000) for t in tracks),
            "Each selected track requires its pinned stream/channel identity.")
    require(len({t["id"] for t in tracks}) == len(tracks), "Choose distinct marker and signal tracks.")
    require(value["marker"].get("kind") == "markers" and all(t.get("kind") == "signal" for t in value["tracks"]),
            "Anchor evidence must use a marker channel; displayed tracks must be signal channels.")
    return tracks


def _pairs(values, count, label):
    require(type(values) is list and count[0] <= len(values) <= count[1], label + " count is outside its bound.")
    for pair in values:
        require(type(pair) is dict and set(pair) == {"source_sequence", "reference_sequence"}
                and all(type(n) is int and 1 <= n <= MAX_ROWS for n in pair.values()),
                "Select explicit original marker row numbers; typed times and inferred labels are not anchors.")


def _arithmetic_clock(clock):
    return {"unit": clock["unit"], **({"seconds_per_tick": clock["seconds_per_tick"]} if clock["unit"] == "ticks" else {})}


def _summary(track, inspected):
    # The full segment audit is performed by inspect_stream. Preview carries
    # counts and exact original artifact refs, not an unbounded segment dump.
    return {"id": track["id"], "source_stream_id": track["source_stream_id"],
            "channel_id": track["channel"]["id"], "kind": track["kind"],
            "samples": {k: track["samples"][k] for k in ("hash", "bytes")},
            "evidence": {k: track["evidence"][k] for k in ("hash", "bytes")},
            "source_rows": inspected["source_rows"], "segment_count": len(inspected["segments"]),
            "missing_values": inspected["missing_values"], "unplaced_rows": inspected["unplaced_rows"],
            "timestamp_stage": inspected["timestamp_stage"],
            "upstream_timestamp_processing": "unknown_unless_separately_source_declared"}


def build_preview(request):
    require(type(request) is dict and set(request) == {"schema", "source", "reference", "anchors", "checks", "review"}
            and request["schema"] == SCHEMA, "Unsupported exact source-qualified preview request.")
    source, reference = request["source"], request["reference"]
    sides = {"source": _side(source), "reference": _side(reference)}
    require(source["dataset"]["id"] != reference["dataset"]["id"]
            and source["imported"]["id"] != reference["imported"]["id"],
            "Choose two distinct recordings/imports; use shared-clock review within one recording.")
    _pairs(request["anchors"], (2, 2), "Defining anchor")
    _pairs(request["checks"], (0, MAX_CHECKS), "Optional held-out event")
    review = request["review"]
    require(type(review) is dict and set(review) == {"confirmed", "rationale"}
            and review["confirmed"] is True and _text(review["rationale"], 4000),
            "Explicitly review the two event correspondences and explain the relationship between recordings.")
    pairs = request["anchors"] + request["checks"]
    sequences = {name: [p[name + "_sequence"] for p in pairs] for name in sides}
    require(all(len(set(rows)) == len(rows) for rows in sequences.values()),
            "Defining and held-out pairs must use distinct original events on each side.")
    all_tracks = [t for tracks in sides.values() for t in tracks]
    require(all(type(t.get("sample_count")) is int and 1 <= t["sample_count"] <= MAX_ROWS for t in all_tracks)
            and sum(t["sample_count"] for t in all_tracks) <= MAX_ROWS,
            "The complete selected sources exceed the two-million-row preview budget.")
    artifacts = [t[k] for t in all_tracks for k in ("samples", "evidence")]
    require(all(type(a) is dict and type(a.get("bytes")) is int and 0 <= a["bytes"] <= MAX_BYTES for a in artifacts)
            and sum(a["bytes"] for a in artifacts) <= MAX_BYTES,
            "The complete selected sources exceed the four-GiB preview budget.")
    inspected = {name: [inspect_stream(t, sequences[name] if i == 0 else ()) for i, t in enumerate(tracks)]
                 for name, tracks in sides.items()}
    baseline = inspected["reference"][0]
    for name, records in inspected.items():
        marker = records[0]
        require(all(r["clock"] == marker["clock"] for r in records),
                "Signal and marker channels need the same explicitly preserved clock within each recording.")
        require(all(r["identity"] == baseline["identity"] for r in records),
                "Every complete source must retain the same participant and session; a rationale cannot join different identities.")
        require(all(r["origin"] == baseline["origin"] for r in records),
                "Keep sample, pilot, live and imported recordings separate.")
    events = {name: records[0]["events"] for name, records in inspected.items()}
    numeric = [{"source": events["source"][i]["source_timestamp"], "reference": events["reference"][i]["source_timestamp"]} for i in range(2)]
    mapping = build_affine(numeric, _arithmetic_clock(inspected["source"][0]["clock"]), _arithmetic_clock(baseline["clock"]))
    def event_pair(i):
        return {"source": events["source"][i], "reference": events["reference"][i],
                "comparison": check_event(mapping, events["source"][i]["source_timestamp"], events["reference"][i]["source_timestamp"])}
    # Recheck all originals after both recordings have been inspected, so a
    # changed first-side file cannot be hidden by a later side's successful read.
    # Production publication additionally requires held native handles.
    for artifact in artifacts:
        _source(artifact)
    result = {"schema": "brohn-clock-preview/0.1", "profile": PROFILE,
              "scope": "source_qualified_preview_component_only", "review": copy.deepcopy(review),
              "identity": baseline["identity"], "origin": baseline["origin"],
              "recordings": {name: {"dataset": copy.deepcopy(request[name]["dataset"]),
                                     "imported": copy.deepcopy(request[name]["imported"]),
                                     "clock": copy.deepcopy(inspected[name][0]["clock"]),
                                     "tracks": [_summary(t, r) for t, r in zip(sides[name], inspected[name])]} for name in sides},
              "anchors": [event_pair(i) for i in range(2)],
              "checks": [event_pair(i) for i in range(2, len(pairs))], "mapping": mapping.manifest(),
              "physical_synchronization": "not_established", "event_equivalence": "researcher_declared_only",
              "uncertainty": "unknown", "authorization": "requires_current_R_source_project_and_publication_guards",
              "scientific_scoring": "not_performed"}
    require(len(json.dumps(result, ensure_ascii=True, allow_nan=False, separators=(",", ":")).encode("ascii")) <= MAX_OUTPUT,
            "The source-qualified preview exceeds its one-MiB output bound.")
    return result
