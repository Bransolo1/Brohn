"""Bounded arithmetic consistency only; does not inspect or authorize sources."""
from pathlib import Path
import hashlib
import importlib.util
import json
import sys

MAX_BYTES = 1024 * 1024


def load_json(path):
    raw = Path(path).read_bytes()
    if len(raw) > MAX_BYTES:
        raise ValueError("Clock arithmetic validation document exceeds one MiB.")
    return json.loads(raw), hashlib.sha256(raw).hexdigest()


def same(actual, expected):
    # JSON shape/type matters: True must not equal 1, unreduced fractions must
    # not equal reduced coordinates, and approximations are not authoritative.
    return json.dumps(actual, sort_keys=True, separators=(",", ":"), allow_nan=False) == json.dumps(
        expected, sort_keys=True, separators=(",", ":"), allow_nan=False)


def main():
    helper_path, request_path, result_path, output_path = map(Path, sys.argv[1:])
    helper_hash = hashlib.sha256(helper_path.read_bytes()).hexdigest()
    spec = importlib.util.spec_from_file_location("brohn_pinned_clock_affine", helper_path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    request, request_hash = load_json(request_path)
    result, result_hash = load_json(result_path)
    anchors = result["anchors"]
    if len(anchors) != 2 or len(result["checks"]) > 16:
        raise ValueError("Exact defining/check event count changed.")
    def clock(side):
        c = request[side]["marker"]["clock"]
        return {"unit": c["unit"], **({"seconds_per_tick": c["seconds_per_tick"]} if c["unit"] == "ticks" else {})}
    mapping = module.build_affine([
        {"source": a["source"]["source_timestamp"], "reference": a["reference"]["source_timestamp"]}
        for a in anchors], clock("source"), clock("reference"))
    if not same(result["mapping"], mapping.manifest()):
        raise ValueError("Exact reduced mapping/schema differs from reconstruction of the selected event lexemes.")
    for pair in anchors + result["checks"]:
        expected = module.check_event(mapping, pair["source"]["source_timestamp"], pair["reference"]["source_timestamp"])
        if not same(pair["comparison"], expected):
            raise ValueError("Exact reduced event coordinates/residuals differ from reconstruction; no refit is allowed.")
    if hashlib.sha256(helper_path.read_bytes()).hexdigest() != helper_hash:
        raise ValueError("Exact arithmetic helper changed during validation.")
    Path(output_path).write_text(json.dumps({
        "schema": "brohn-clock-math-check/0.1", "passed": True,
        "request_sha256": request_hash, "result_sha256": result_hash,
        "helper_sha256": helper_hash,
        "scope": "schema_and_exact_arithmetic_consistency_only_not_original_source_reinspection",
    }, sort_keys=True, separators=(",", ":")), encoding="utf-8")


if __name__ == "__main__":
    main()
