"""Immutable shared typed transport algorithms from c43c54d EDA reader; no science imports."""
import hashlib,json,math,struct
import physiology_artifacts as tables
require=tables.require
HASH_PROFILE="brohn-eda-value-hash/0.1"

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


def verifier_manifest(original, path):
    """Keep published hash/size descriptor untouched; adapt only parser input."""
    sha = original.get("hash", original.get("sha256"))
    size = original.get("size", original.get("bytes"))
    require(("hash" not in original or "sha256" not in original or original["hash"] == original["sha256"]) and
            ("size" not in original or "bytes" not in original or original["size"] == original["bytes"]), "Conflicting original artifact descriptor aliases.")
    return {**original, "sha256": sha, "bytes": size, "path": str(path)}

