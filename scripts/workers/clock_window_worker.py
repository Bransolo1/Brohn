"""Bind original-row exports to the exact accepted preview supplied by R.

This is a supervised-worker adapter, not an authorization capability. Native
source/output seals, current ownership and atomic publication remain R-owned.
"""
from __future__ import annotations
import argparse
from fractions import Fraction
import hashlib
import json
from pathlib import Path

from clock_preview_worker import _object, _constant
from clock_window import run, _hash, _original_request_binding, _pair, COLUMNS
from clock_preview import _arithmetic_clock
from clock_affine import build_affine, map_position, parse_decimal

MAX_INPUT = 3 * 1024**2
MAX_RESULT = 2 * 1024**2
COUNTS = ("source_rows", "selected_rows", "outside_anchor_span_rows", "outside_window_rows",
          "unplaced_rows", "missing_source_values", "missing_selected_values")


def require(value, message):
    if not value:
        raise ValueError(message)


def same(a, b):
    return json.dumps(a, sort_keys=True, ensure_ascii=True, allow_nan=False, separators=(",", ":")) == json.dumps(
        b, sort_keys=True, ensure_ascii=True, allow_nan=False, separators=(",", ":"))


def read_bounded(path, maximum):
    path = Path(path)
    require(path.is_file() and path.stat().st_size <= maximum, 'Verification file is unavailable or exceeds its byte bound.')
    with path.open('rb') as source:
        raw = source.read(maximum + 1)
    require(len(raw) <= maximum, 'Verification file grew beyond its byte bound.')
    return raw


def bounded_digest(path, expected_size):
    require(type(expected_size) is int and 1 <= expected_size <= 64 * 1024**2, 'Export byte bound is invalid.')
    path = Path(path)
    require(path.is_file() and path.stat().st_size == expected_size, 'Original-row export size changed.')
    total = 0; digest = hashlib.sha256()
    with path.open('rb') as source:
        while chunk := source.read(min(1024**2, expected_size - total + 1)):
            total += len(chunk)
            require(total <= expected_size, 'Original-row export grew beyond its declared size.')
            digest.update(chunk)
    require(total == expected_size, 'Original-row export size changed during verification.')
    return digest.hexdigest()


def validate(result, preview_request, selection, expected_preview):
    require(type(result) is dict and set(result) == {"schema", "status", "scope", "binding", "source_request", "preview",
        "selection", "window_interval", "mapping_support", "unplaced_scope", "row_order", "counts", "tracks", "rows",
        "page_size", "artifacts", "physical_synchronization", "uncertainty", "scientific_scoring", "authorization"},
        "Clock window result fields changed.")
    require(result["schema"] == "brohn-clock-window/0.1" and result["scope"] == "source_qualified_window_export_component_only"
        and result["physical_synchronization"] == "not_established" and result["uncertainty"] == "unknown"
        and result["scientific_scoring"] == "not_performed"
        and result["authorization"] == "requires_current_R_membership_project_and_native_publication_guards",
        "Clock window changed its supported interpretation.")
    require(same(result["preview"], expected_preview), "Fresh original-source preview differs from the explicitly saved map evidence.")
    source = _original_request_binding(preview_request)
    binding = {"preview_sha256": _hash(expected_preview), "source_request_sha256": _hash(source),
               "selection_sha256": _hash(selection), "mapping_sha256": _hash(expected_preview["mapping"])}
    require(same(result["source_request"], source) and same(result["selection"], selection) and same(result["binding"], binding),
            "Clock window substituted the original sources, saved mapping or selected interval.")
    require(result["window_interval"] == "reference-relative start inclusive, end exclusive"
        and result["mapping_support"] == "closed defining-anchor span; end anchor is retained evidence, not included at an exclusive window end"
        and result["unplaced_scope"] == "complete original selected tracks; no window membership or time inferred"
        and result["row_order"] == "source then reference; marker then selected signals; original sequence within each track"
        and type(result["page_size"]) is int and result["page_size"] == 100, "Clock window changed endpoint, unplaced-row or ordering policy.")
    tracks = [(side, t) for side in ("source", "reference") for t in [preview_request[side]["marker"], *preview_request[side]["tracks"]]]
    require(type(result["tracks"]) is list and len(result["tracks"]) == len(tracks), "Clock window omitted a complete source track.")
    totals = {key: 0 for key in COUNTS}
    for got, (side, track) in zip(result["tracks"], tracks):
        expected = {"recording_side": side, "track_id": track["id"], "source_stream_id": track["source_stream_id"],
                    "channel": track["channel"], "clock": track["clock"], "origin": track["origin"],
                    "samples": {k: track["samples"][k] for k in ("hash", "bytes")},
                    "evidence": {k: track["evidence"][k] for k in ("hash", "bytes")}, "segment_count": track["segment_count"]}
        require(type(got) is dict and set(got) == set(expected) | set(COUNTS)
            and same({k: got[k] for k in expected}, expected), "Clock window changed original track identity or segment support.")
        require(all(type(got[k]) is int and 0 <= got[k] <= track["sample_count"] for k in COUNTS)
            and got["source_rows"] == track["sample_count"]
            and got["source_rows"] == sum(got[k] for k in ("selected_rows", "outside_anchor_span_rows", "outside_window_rows", "unplaced_rows"))
            and got["missing_selected_values"] <= got["selected_rows"]
            and got["missing_selected_values"] <= got["missing_source_values"], "Clock window source coverage counts do not reconcile.")
        for key in COUNTS:
            totals[key] += got[key]
    require(same(totals, result["counts"]) and result["status"] == ("available" if totals["selected_rows"] else "empty_window"),
            "Clock window totals or availability changed.")
    offset = selection["offset"]
    require(type(result["rows"]) is list and len(result["rows"]) == min(100, max(0, totals["selected_rows"] - offset)),
            "Clock window numerical page does not match complete selected rows.")
    source_clock, reference_clock = [expected_preview["recordings"][side]["clock"] for side in ("source", "reference")]
    anchors = [{"source": a["source"]["source_timestamp"], "reference": a["reference"]["source_timestamp"]} for a in expected_preview["anchors"]]
    mapping = build_affine(anchors, _arithmetic_clock(source_clock), _arithmetic_clock(reference_clock))
    require(same(mapping.manifest(), expected_preview["mapping"]), "Saved clock map no longer matches its exact defining evidence.")
    manifest = mapping.manifest()
    reference_start = Fraction(int(manifest["anchors"][0]["reference_seconds"]["numerator"]), int(manifest["anchors"][0]["reference_seconds"]["denominator"]))
    start, end = parse_decimal(selection["start_s"]), parse_decimal(selection["end_s"])
    previous = (-1, -1)
    for row in result["rows"]:
        require(type(row) is dict and set(row) == set(COLUMNS), "Clock window numerical row shape changed.")
        indices = [i for i, (side, t) in enumerate(tracks) if side == row["recording_side"] and t["id"] == row["track_id"]]
        require(len(indices) == 1, "Clock window row refers to an unselected original track.")
        index = indices[0]; side, track = tracks[index]; sequence = row["source_sequence"]
        require(type(sequence) is int and 1 <= sequence <= track["sample_count"] and (index, sequence) > previous,
                "Clock window rows changed original order or repeated a source row.")
        previous = index, sequence
        require(row["source_stream_id"] == track["source_stream_id"] and row["channel_id"] == track["channel"]["id"]
            and row["kind"] == track["kind"] and row["source_clock_id"] == track["clock"]["id"]
            and row["timestamp_unit"] == track["clock"]["unit"] and row["origin"] == track["origin"]
            and row["unit"] == track["channel"].get("unit") and row["samples_sha256"] == track["samples"]["hash"]
            and row["evidence_sha256"] == track["evidence"]["hash"]
            and row["preview_sha256"] == binding["preview_sha256"] and row["source_request_sha256"] == binding["source_request_sha256"]
            and row["placement"] == "selected_window" and row["timestamp_state"] == "observed"
            and row["reconstructed_timestamp"] is False, "Clock window row lost original source support.")
        identity = json.loads(row["identity_json"], object_pairs_hook=_object, parse_constant=_constant)
        require(type(identity) is dict and {"participant_id", "session_id"} <= set(identity)
            and set(identity) <= {"participant_id", "session_id", "condition_id", "exposure_id"}
            and all(same(identity.get(key), row[key]) for key in ("participant_id", "session_id", "condition_id", "exposure_id"))
            and all(identity[key] == expected_preview["identity"][key] for key in ("participant_id", "session_id")),
            "Clock window row changed its original person or visit.")
        json.loads(row["value_json"], object_pairs_hook=_object, parse_constant=_constant)
        clock = manifest["source_clock"] if side == "source" else manifest["reference_clock"]
        scale = clock["seconds_per_unit"]
        original = parse_decimal(row["source_timestamp"]) * Fraction(int(scale["numerator"]), int(scale["denominator"]))
        if side == "source":
            mapped = map_position(mapping, row["source_timestamp"])["mapped_reference_seconds"]
            reference = Fraction(int(mapped["numerator"]), int(mapped["denominator"]))
        else:
            reference = original
        relative = reference - reference_start
        require(start <= relative < end and row["coordinate_policy"] == ("reviewed_affine_source" if side == "source" else "original_reference_coordinate"),
                "Clock window row is outside its original selected interval.")
        for prefix, value in (("original_seconds", original), ("reference_seconds", reference), ("reference_relative_seconds", relative)):
            require(same({"numerator": row[prefix+"_numerator"], "denominator": row[prefix+"_denominator"]}, _pair(value)),
                    "Clock window row changed its exact reduced coordinates.")
    expected_artifacts = [("selected.csv", "selected_original_rows", totals["selected_rows"]),
                          ("unplaced.csv", "all_source_unplaced_rows", totals["unplaced_rows"]),
                          ("segments.jsonl", "complete_original_segments", sum(t["segment_count"] for _, t in tracks))]
    require(type(result["artifacts"]) is list and len(result["artifacts"]) == 3, "Clock window exports are incomplete.")
    for got, (name, kind, rows) in zip(result["artifacts"], expected_artifacts):
        require(type(got) is dict and set(got) == {"file", "sha256", "bytes", "kind", "rows", "binding"}
            and got["file"] == name and got["kind"] == kind and type(got["rows"]) is int and got["rows"] == rows
            and type(got["bytes"]) is int and 1 <= got["bytes"] <= 64 * 1024**2 and same(got["binding"], binding)
            and type(got["sha256"]) is str and len(got["sha256"]) == 64 and all(c in "0123456789abcdef" for c in got["sha256"]),
            "Clock window export descriptor changed.")


def execute(request_path, output_path):
    request_path = Path(request_path)
    require(request_path.is_file() and request_path.stat().st_size <= MAX_INPUT, "Clock window request exceeds three MiB or is unavailable.")
    request = json.loads(read_bounded(request_path, MAX_INPUT), object_pairs_hook=_object, parse_constant=_constant)
    require(type(request) is dict and set(request) == {"schema", "window", "expected_preview"}
        and request["schema"] == "brohn-clock-window-worker-request/0.1", "Use a source-bound saved clock-window request.")
    result = run(request["window"])
    validate(result, request["window"]["preview_request"], request["window"]["selection"], request["expected_preview"])
    manifest = Path(request["window"]["output_directory"]) / "manifest.json"
    raw = read_bounded(manifest, MAX_RESULT)
    require(len(raw) <= MAX_RESULT and same(json.loads(raw), result), "Clock window display manifest exceeds two MiB or changed.")
    output = {"schema": "brohn-clock-window-worker-result/0.1", "result": result,
              "manifest_artifact": {"file": "manifest.json", "kind": "clock_window_manifest", "sha256": hashlib.sha256(raw).hexdigest(),
                                    "bytes": len(raw), "media_type": "application/json"}}
    encoded = json.dumps(output, ensure_ascii=True, allow_nan=False, separators=(",", ":")).encode("ascii")
    require(len(encoded) <= MAX_RESULT, "Clock window result exceeds two MiB; choose a narrower window.")
    with Path(output_path).open("xb") as target:
        target.write(encoded)
    return output


def check(request_path, result_path, output_path):
    """Revalidate the worker envelope and exact exports before guarded R publication.

    This repeats schema/arithmetic/artifact consistency, not full original-source
    inspection. R keeps the original sources and child output sealed throughout.
    """
    request_raw = read_bounded(request_path, MAX_INPUT)
    result_raw = read_bounded(result_path, MAX_RESULT)
    require(len(request_raw) <= MAX_INPUT and len(result_raw) <= MAX_RESULT, "Oversized clock-window verification input.")
    request = json.loads(request_raw, object_pairs_hook=_object, parse_constant=_constant)
    output = json.loads(result_raw, object_pairs_hook=_object, parse_constant=_constant)
    require(type(request) is dict and set(request) == {"schema", "window", "expected_preview"}
        and request["schema"] == "brohn-clock-window-worker-request/0.1", "Unsupported verification request.")
    require(type(output) is dict and set(output) == {"schema", "result", "manifest_artifact"}
        and output["schema"] == "brohn-clock-window-worker-result/0.1", "Unsupported original-row worker envelope.")
    validate(output['result'], request['window']['preview_request'], request['window']['selection'], request['expected_preview'])
    a = output['manifest_artifact']
    require(type(a) is dict and set(a) == {'file','kind','sha256','bytes','media_type'}
        and a['file'] == 'manifest.json' and a['kind'] == 'clock_window_manifest'
        and a['media_type'] == 'application/json' and type(a['bytes']) is int and 1 <= a['bytes'] <= MAX_RESULT,
        'Clock-window manifest descriptor changed.')
    folder = Path(request['window']['output_directory']).resolve(strict=True)
    total = 0
    for artifact in [*output['result']['artifacts'], a]:
        path = folder / artifact['file']
        require(not path.is_symlink() and path.resolve(strict=True).parent == folder and path.is_file(), 'Export escaped its owned artifact directory.')
        require(path.stat().st_size == artifact['bytes'], 'Original-row export size changed.')
        total += artifact['bytes']
        require(total <= 64 * 1024**2, 'Combined clock-window exports exceed64MiB.')
        require(bounded_digest(path, artifact['bytes']) == artifact['sha256'], 'Original-row export bytes changed.')
    require(same(json.loads(read_bounded(folder/'manifest.json', MAX_RESULT), object_pairs_hook=_object, parse_constant=_constant), output['result']),
            'The retained display manifest differs from the verified result.')
    receipt = {'schema':'brohn-clock-window-verification/0.1','passed':True,
        'request_sha256':hashlib.sha256(request_raw).hexdigest(),'result_sha256':hashlib.sha256(result_raw).hexdigest(),
        'scope':'schema_exact_arithmetic_and_export_bytes_not_original_source_reinspection'}
    with Path(output_path).open('xb') as target:
        target.write(json.dumps(receipt, separators=(',',':')).encode('ascii'))
    return receipt


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--request", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--result")
    args = parser.parse_args()
    try:
        if args.result:
            check(args.request, args.result, args.output)
        else:
            execute(args.request, args.output)
    except Exception as error:
        print(json.dumps({"status": "error", "error": {"type": type(error).__name__, "message": str(error)[:700]}}))
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
