"""Bounded loss-aware XDF / explicit Brohn stream-bundle interchange importer."""
from __future__ import annotations
import argparse
from collections import OrderedDict
from contextlib import ExitStack
import csv
from decimal import Decimal, InvalidOperation, getcontext
import hashlib
import importlib.metadata
import json
import logging
import math
import os
from pathlib import Path
import platform
import re
import struct
import sys
import tempfile
import warnings
from xml.etree import ElementTree

MAX_BYTES = 512 * 1024**2
MAX_BUNDLE = 64 * 1024**2
MAX_ROWS = 2_000_000
MAX_VALUES = 20_000_000
MAX_STREAMS = 64
MAX_CHANNELS = 256
MAX_CHUNKS = 100_000
MAX_TEXT = 32768
MAX_PREVIEW = 20
MAX_PREVIEW_BYTES = 1024**2
MAX_ARTIFACT_BYTES = 4 * 1024**3
FORMATS = {"double64": (8, "float64"), "float32": (4, "float32"), "int64": (8, "int64"),
           "int32": (4, "int32"), "int16": (2, "int16"), "int8": (1, "int8"), "string": (None, "string")}
VALUE_TYPES = {"float64", "float32", "int64", "int32", "int16", "int8", "string", "boolean"}
TIME_FACTORS = {"s": Decimal(1), "ms": Decimal(".001"), "us": Decimal(".000001"), "ns": Decimal(".000000001")}
IDENTITY = ("participant_id", "session_id", "condition_id", "exposure_id")
getcontext().prec = 300


class InputError(ValueError):
    pass


def require(ok, message):
    if not ok:
        raise InputError(message)


def text(value, name, maximum=MAX_TEXT, nullable=False):
    if value is None and nullable:
        return None
    require(isinstance(value, str) and 0 < len(value.encode("utf-8")) <= maximum, f"{name} must be bounded nonempty text.")
    return value


def fields(value, required, optional=()):
    require(isinstance(value, dict) and set(required) <= set(value) and set(value) <= set(required) | set(optional),
            "Object contains missing or unregistered fields: " + ", ".join(required))


def numeric(value, name, minimum=0, maximum=100000):
    require(isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)
            and minimum <= value <= maximum, f"{name} is outside its finite numeric bounds.")
    return float(value)


def decimal(value, name, nullable=False):
    if value is None and nullable:
        return None
    text(value, name, 120)
    require(re.fullmatch(r"[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?", value) is not None, f"{name} must be a decimal string.")
    try:
        number = Decimal(value)
    except InvalidOperation as error:
        raise InputError(f"Invalid {name}.") from error
    require(number.is_finite() and abs(number.adjusted()) <= 100, f"{name} exponent is unsupported.")
    return number


def digest(path):
    value = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for block in iter(lambda: stream.read(1024**2), b""):
            value.update(block)
    return value.hexdigest()


def unique_pairs(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, "Duplicate JSON key: " + key)
        result[key] = value
    return result


def load_json(path, maximum):
    require(Path(path).stat().st_size <= maximum, "JSON input exceeds its explicit size limit.")
    return json.loads(Path(path).read_text(encoding="utf-8-sig"), object_pairs_hook=unique_pairs,
                      parse_constant=lambda value: (_ for _ in ()).throw(InputError("Nonfinite JSON literal.")))


def json_line(value):
    return json.dumps(value, allow_nan=False, ensure_ascii=True, separators=(",", ":")) + "\n"


def origin(value):
    if value is None:
        return None
    text(value, "source origin", 500)
    lowered = value.lower()
    if lowered in ("sample", "synthetic", "synthetic/reference") or lowered.startswith("synthetic-"):
        return "sample"
    return lowered if lowered in ("imported", "pilot", "live", "mixed") else "unclassified"


def identity(value):
    require(isinstance(value, dict) and set(value) <= set(IDENTITY), "Identity must use declared participant/session/condition/exposure IDs.")
    return {key: text(item, key, 500) for key, item in value.items()}


def xml_read(raw):
    require(len(raw) <= 1024**2, "XDF XML exceeds 1 MiB.")
    decoded = raw.decode("utf-8", errors="strict")
    require("<!DOCTYPE" not in decoded.upper() and "<!ENTITY" not in decoded.upper(), "XDF XML entities and DTDs are unsupported.")
    root = ElementTree.fromstring(decoded)
    require(root.tag == "info", "XDF XML root must be info.")
    return root, decoded


def read_exact(stream, size, boundary):
    require(size >= 0 and stream.tell() + size <= boundary, "XDF chunk/sample exceeds its declared byte boundary.")
    value = stream.read(size)
    require(len(value) == size, "Truncated XDF bytes.")
    return value


def varint(stream, boundary):
    width = read_exact(stream, 1, boundary)[0]
    require(width in (1, 4, 8), "Invalid XDF variable-length integer.")
    return int.from_bytes(read_exact(stream, width, boundary), "little")


def xdf_preflight(path):
    """Check lengths/counts/UTF-8 before pyxdf can allocate or recover a chunk."""
    size = path.stat().st_size
    streams, chunks, unknown, file_header = OrderedDict(), 0, [], None
    total_rows = total_values = 0
    with path.open("rb") as file:
        require(read_exact(file, 4, size) == b"XDF:", "Only uncompressed XDF is supported.")
        while file.tell() < size:
            start = file.tell(); length = varint(file, size); end = file.tell() + length
            require(2 <= length and end <= size, "Truncated or invalid XDF chunk length.")
            tag = struct.unpack("<H", read_exact(file, 2, end))[0]
            chunks += 1
            require(chunks <= MAX_CHUNKS, "XDF exceeds 100,000 chunks.")
            require(chunks != 1 or tag == 1, "XDF must begin with a file header.")
            sid = None
            if tag in (2, 3, 4, 6):
                sid = struct.unpack("<I", read_exact(file, 4, end))[0]
            if tag == 1:
                require(file_header is None, "Duplicate XDF file header.")
                parsed, file_header = xml_read(read_exact(file, end - file.tell(), end))
                require(parsed.findtext("version") in ("1", "1.0"), "Only XDF version 1/1.0 is supported.")
            elif tag == 2:
                require(sid not in streams and len(streams) < MAX_STREAMS, "Duplicate/reused XDF stream ID or more than 64 streams.")
                parsed, header = xml_read(read_exact(file, end - file.tell(), end))
                count = int(parsed.findtext("channel_count", "-1"))
                rate = float(parsed.findtext("nominal_srate", "nan"))
                fmt = parsed.findtext("channel_format")
                require(1 <= count <= MAX_CHANNELS and fmt in FORMATS, "XDF channel count or sample type is unsupported.")
                numeric(rate, "XDF nominal sample rate")
                streams[sid] = {"id": str(sid), "header": header, "parsed": parsed, "footer": None,
                                "count": count, "rate": rate, "format": fmt, "rows": 0, "chunks": [],
                                "stamp_flags": bytearray(), "stamp_bytes": bytearray(), "offsets": [], "anchored": False}
            elif tag in (3, 4, 6):
                require(sid in streams and streams[sid]["footer"] is None, "XDF stream data lacks an open unique header.")
                current = streams[sid]
                if tag == 3:
                    samples = varint(file, end)
                    total_rows += samples; total_values += samples * current["count"]
                    require(total_rows <= MAX_ROWS and total_values <= MAX_VALUES, "XDF exceeds 2 million rows or 20 million values.")
                    require(samples <= end - file.tell(), "Advertised XDF sample count cannot fit in its chunk.")
                    current["chunks"].append({"chunk_index": chunks, "file_offset": start,
                                              "first_sequence": current["rows"] + 1, "sample_count": samples})
                    for _ in range(samples):
                        width = read_exact(file, 1, end)[0]
                        require(width in (0, 8), "XDF timestamp width must be 0 or 8.")
                        if width:
                            raw = read_exact(file, 8, end)
                            current["stamp_bytes"].extend(raw)
                            current["stamp_flags"].append(0)
                            current["anchored"] = math.isfinite(struct.unpack("<d", raw)[0])
                        else:
                            current["stamp_bytes"].extend(b"\x00" * 8)
                            current["stamp_flags"].append(1 if current["anchored"] else 2)
                        if current["format"] == "string":
                            for _ in range(current["count"]):
                                length = varint(file, end)
                                require(length <= MAX_TEXT, "XDF string value exceeds 32 KiB.")
                                read_exact(file, length, end).decode("utf-8", errors="strict")
                        else:
                            read_exact(file, FORMATS[current["format"]][0] * current["count"], end)
                    current["rows"] += samples
                elif tag == 4:
                    raw = read_exact(file, 16, end); collection, offset = struct.unpack("<dd", raw)
                    current["offsets"].append({"sequence": len(current["offsets"])+1, "chunk_index": chunks,
                        "after_sample_sequence": current["rows"], "collection_timestamp": repr(collection) if math.isfinite(collection) else None,
                        "offset_s": repr(offset) if math.isfinite(offset) else None,
                        "collection_ieee754_le_hex": raw[:8].hex(), "offset_ieee754_le_hex": raw[8:].hex(),
                        "uncertainty_s": None, "reference_clock_id": None, "applied": False})
                else:
                    parsed, current["footer"] = xml_read(read_exact(file, end - file.tell(), end))
                    declared = parsed.findtext("sample_count")
                    require(declared is None or int(declared) == current["rows"], "XDF footer sample count disagrees with complete decoded sample count.")
            elif tag == 5:
                require(read_exact(file, end-file.tell(), end) == bytes.fromhex("43a546dccbf5410fb30ed5467383cbe4"), "Invalid XDF boundary marker.")
            else:
                raw = read_exact(file, end-file.tell(), end)
                unknown.append({"chunk_index": chunks, "tag": tag, "file_offset": start, "bytes": length,
                                "sha256": hashlib.sha256(raw).hexdigest()})
            require(file.tell() == end, "XDF chunk contains unexplained trailing bytes.")
    require(0 < len(streams) <= MAX_STREAMS, "XDF contains no supported streams.")
    return streams, {"header_xml": file_header, "chunk_count": chunks, "unknown_chunks": unknown,
                     "source_rows": total_rows, "source_values": total_values}


def xdf_channels(raw):
    nodes = raw["parsed"].findall("desc/channels/channel")
    require(not nodes or len(nodes) == raw["count"], "Declared XDF channel metadata count does not match channel_count.")
    result = []
    for index in range(raw["count"]):
        node = nodes[index] if nodes else None
        get = lambda key: node.findtext(key) if node is not None else None
        for key in ("label", "type", "unit", "scale", "offset"):
            if get(key) is not None:
                text(get(key), "XDF channel " + key, 500)
        result.append({"id": f"channel_{index+1}", "label": get("label"), "type": get("type"), "unit": get("unit"),
                       "value_type": FORMATS[raw["format"]][1], "scale": get("scale"), "offset": get("offset"),
                       "calibration_applied": False, "metadata_xml": ElementTree.tostring(node, encoding="unicode") if node is not None else None})
    return result


def xdf_sources(path):
    import pyxdf
    require(pyxdf.__version__ == "1.17.5", "Use the prepared acquisition environment with pyxdf 1.17.5.")
    preflight, container = xdf_preflight(path)
    class Errors(logging.Handler):
        def emit(self, record):
            if record.levelno >= logging.ERROR:
                raise InputError("pyxdf attempted corruption recovery: " + record.getMessage())
    logger = logging.getLogger("pyxdf.pyxdf"); handler = Errors(); logger.addHandler(handler)
    try:
        with warnings.catch_warnings(record=True) as caught:
            warnings.simplefilter("always")
            parsed, _ = pyxdf.load_xdf(str(path), synchronize_clocks=False, dejitter_timestamps=False, handle_clock_resets=False)
        container["parser_warnings"] = list(dict.fromkeys(str(x.message)[:500] for x in caught))[:20]
    finally:
        logger.removeHandler(handler)
    require(len(parsed) == len(preflight), "pyxdf stream count differs from strict preflight.")
    sources = []
    for stream in parsed:
        sid = stream["info"]["stream_id"]; raw = preflight[sid]; root = raw["parsed"]
        require(len(stream["time_stamps"]) == raw["rows"] and len(stream["time_series"]) == raw["rows"], "pyxdf lost sample rows.")
        declared_type = root.findtext("type")
        marker = (declared_type or "").lower() in ("markers", "marker", "events", "event")
        signal = (declared_type or "").lower() in ("eeg", "eda", "gsr", "ecg", "ppg", "emg", "eog", "gaze", "eyetracking", "respiration", "nirs", "fnirs", "audio", "accelerometer", "temperature")
        declarations = [x for x in (root.findtext("desc/origin"), root.findtext("origin")) if x is not None]
        declaration = (declarations[0] if len({origin(x) for x in declarations}) == 1 else "mixed") if declarations else None
        offsets = raw["offsets"]
        offset_boundaries = {x["after_sample_sequence"]+1 for a, x in zip(offsets, offsets[1:])
                             if x["collection_timestamp"] is not None and a["collection_timestamp"] is not None
                             and Decimal(x["collection_timestamp"]) < Decimal(a["collection_timestamp"])}
        descriptor = {"id": "xdf-"+str(sid), "name": root.findtext("name"), "type": declared_type,
            "kind": "markers" if marker else "signal" if signal else "unclassified", "kind_basis": "declared XDF type; unknown types remain unclassified",
            "source_id": root.findtext("source_id"), "uid": root.findtext("uid"), "source_session_id": root.findtext("session_id"),
            "origin_declaration": declaration, "origin_declarations": declarations, "nominal_srate": raw["rate"], "channels": xdf_channels(raw),
            "clock": {"id": "xdf-source-clock-"+str(sid), "unit": "s", "kind": "unspecified_epoch", "representation": "binary64"},
            "header_xml": raw["header"], "footer_xml": raw["footer"], "orderly_closed": raw["footer"] is not None,
            "clock_offsets": offsets, "chunks": raw["chunks"], "identity": {}}
        def rows(stream=stream, raw=raw, descriptor=descriptor, offset_boundaries=offset_boundaries):
            for index, (stamp, values) in enumerate(zip(stream["time_stamps"], stream["time_series"])):
                flag = raw["stamp_flags"][index]; value = float(stamp)
                if flag == 0:
                    original = struct.unpack("<d", raw["stamp_bytes"][index*8:(index+1)*8])[0]
                    require((math.isnan(value) and math.isnan(original)) or value == original, "pyxdf changed an explicit source timestamp.")
                yield {"timestamp": repr(value) if math.isfinite(value) else None,
                       "timestamp_state": "unanchored_nominal_reconstruction" if flag == 2 else "observed" if math.isfinite(value) else "nonfinite_source",
                       "timestamp_hex": raw["stamp_bytes"][index*8:(index+1)*8].hex() if flag == 0 else None,
                       "reconstructed": flag != 0, "values": list(values), "identity": {},
                       "clock_id": descriptor["clock"]["id"], "boundary": "clock_offset_collection_reversal" if index+1 in offset_boundaries else None}
        sources.append((descriptor, rows()))
    return sources, container


def bundle_sources(path):
    bundle = load_json(path, MAX_BUNDLE)
    fields(bundle, ("schema", "origin", "streams"), ("description",))
    require(bundle["schema"] == "brohn-stream-bundle/1.0", "Unsupported stream-bundle schema.")
    require(origin(bundle["origin"]) is not None, "Bundle origin must be explicitly declared.")
    require(isinstance(bundle["streams"], list) and 0 < len(bundle["streams"]) <= MAX_STREAMS, "Bundle needs 1 to 64 streams.")
    ids, sources, total_rows, total_values = set(), [], 0, 0
    for stream in bundle["streams"]:
        fields(stream, ("id", "name", "type", "kind", "source_id", "uid", "clock", "nominal_srate", "channels", "samples"),
               ("origin", "identity", "clock_offsets", "metadata"))
        sid = text(stream["id"], "stream id", 96)
        require(re.fullmatch(r"[A-Za-z][A-Za-z0-9_-]*", sid) and sid not in ids, "Stream IDs must be distinct safe identifiers.")
        ids.add(sid)
        for key in ("name", "type", "source_id", "uid"):
            text(stream[key], key, 500, nullable=True)
        require(stream["kind"] in ("signal", "markers", "unclassified"), "Declare signal, markers or unclassified kind.")
        rate = numeric(stream["nominal_srate"], "nominal_srate")
        clock = stream["clock"]
        fields(clock, ("id", "unit", "kind", "representation"), ("seconds_per_tick", "resolution",))
        text(clock["id"], "clock id", 500)
        require(clock["unit"] in (*TIME_FACTORS, "ticks") and clock["kind"] in ("monotonic", "unix", "device", "unspecified_epoch")
                and clock["representation"] == "decimal_string", "Bundle clock must declare units/kind and decimal-string representation.")
        if clock["unit"] == "ticks":
            require(decimal(clock.get("seconds_per_tick"), "seconds_per_tick") > 0, "Tick scale must be positive.")
        if clock.get("resolution") is not None:
            require(decimal(clock["resolution"], "clock resolution") > 0, "Resolution must be positive.")
        channels = stream["channels"]
        require(isinstance(channels, list) and 1 <= len(channels) <= MAX_CHANNELS, "Stream needs 1 to 256 channels.")
        channel_ids = set()
        for channel in channels:
            fields(channel, ("id", "label", "type", "unit", "value_type"), ("scale", "offset"))
            cid = text(channel["id"], "channel id", 96)
            require(re.fullmatch(r"[A-Za-z][A-Za-z0-9_-]*", cid) and cid not in channel_ids, "Channel IDs must be distinct safe identifiers.")
            channel_ids.add(cid)
            require(channel["value_type"] in VALUE_TYPES, "Unsupported typed channel representation.")
            for key in ("label", "type", "unit"):
                text(channel[key], "channel " + key, 500, nullable=True)
            for key in ("scale", "offset"):
                if channel.get(key) is not None:
                    decimal(channel[key], "channel " + key)
            channel["calibration_applied"] = False
        samples = stream["samples"]
        require(isinstance(samples, list), "samples must be an array.")
        total_rows += len(samples); total_values += len(samples) * len(channels)
        require(total_rows <= MAX_ROWS and total_values <= MAX_VALUES, "Bundle exceeds total sample/value bounds.")
        stable_identity = identity(stream.get("identity", {}))
        offsets = stream.get("clock_offsets", [])
        require(isinstance(offsets, list) and len(offsets) <= MAX_CHUNKS, "Clock-offset evidence exceeds its bound.")
        for offset in offsets:
            fields(offset, ("collection_timestamp", "offset_s", "reference_clock_id", "uncertainty_s"))
            decimal(offset["collection_timestamp"], "clock collection timestamp")
            decimal(offset["offset_s"], "clock offset seconds")
            text(offset["reference_clock_id"], "reference clock id", 500)
            if offset["uncertainty_s"] is not None:
                require(decimal(offset["uncertainty_s"], "offset uncertainty") >= 0, "Clock uncertainty cannot be negative.")
            offset["applied"] = False
        declaration = stream.get("origin", bundle["origin"])
        require(origin(declaration) is not None, "Stream origin cannot erase the bundle origin.")
        declarations = [bundle["origin"]] + ([stream["origin"]] if "origin" in stream else [])
        if origin(bundle["origin"]) != "mixed" and origin(declaration) != origin(bundle["origin"]):
            declaration = "mixed"
        descriptor = {key: value for key, value in stream.items() if key not in ("samples", "origin")}
        descriptor.update(origin_declaration=declaration, origin_declarations=declarations, kind_basis="explicit bundle declaration",
                          orderly_closed=None, clock_offsets=offsets, identity=stable_identity)
        def rows(samples=samples, stable_identity=stable_identity, clock=clock):
            for row in samples:
                fields(row, ("timestamp", "values"), ("identity", "clock_id", "reset"))
                decimal(row["timestamp"], "sample timestamp", nullable=True)
                require(isinstance(row["values"], list), "Sample values must be a typed array.")
                require(isinstance(row.get("reset", False), bool), "reset must be boolean.")
                yield {"timestamp": row["timestamp"], "timestamp_state": "observed" if row["timestamp"] is not None else "missing",
                       "timestamp_hex": None, "reconstructed": False, "values": row["values"],
                       "identity": identity(row["identity"]) if "identity" in row else stable_identity,
                       "clock_id": text(row.get("clock_id", clock["id"]), "sample clock id", 500),
                       "boundary": "declared_reset" if row.get("reset") else None}
        sources.append((descriptor, rows()))
    return sources, {"schema": bundle["schema"], "origin_declaration": bundle["origin"],
                     "description": bundle.get("description"), "source_rows": total_rows, "source_values": total_values}


def typed_value(value, kind, xdf=False):
    if value is None:
        return None, "missing"
    if kind == "string":
        require(isinstance(value, str) and len(value.encode("utf-8")) <= MAX_TEXT, "Marker/text value is invalid or too long.")
        return value, "observed"
    if kind == "boolean":
        require(isinstance(value, bool), "Boolean channel needs true, false or null.")
        return value, "observed"
    if kind.startswith("int"):
        bits = int(kind[3:])
        if not xdf and bits == 64:
            require(isinstance(value, str) and re.fullmatch(r"[+-]?\d+", value), "int64 values must be exact decimal strings.")
        elif not xdf:
            require(isinstance(value, int) and not isinstance(value, bool), "Integer channel requires a JSON integer.")
        integer = int(value)
        require(-(2**(bits-1)) <= integer < 2**(bits-1), "Integer value exceeds declared channel width.")
        return str(integer) if bits == 64 else integer, "observed"
    require(not isinstance(value, (str, bool)), "Floating-point channel requires numeric values.")
    converted = float(value)
    if isinstance(value, int):
        require(converted == value, "Integer cannot be represented exactly by this floating-point channel; declare int64 decimal strings.")
    if not math.isfinite(converted):
        require(xdf, "Nonfinite bundle numbers are unsupported; use explicit null.")
        return None, "nan" if math.isnan(converted) else "positive_infinity" if converted > 0 else "negative_infinity"
    if kind == "float32" and not xdf:
        try:
            restored = struct.unpack("<f", struct.pack("<f", converted))[0]
        except OverflowError as error:
            raise InputError("Value exceeds finite float32 range.") from error
        require(math.isfinite(restored) and restored == converted, "Declared float32 value is not exactly representable; use float64 or an exact float32 value.")
    return converted, "observed"


class ArtifactWriter:
    def __init__(self, directory):
        self.directory, self.temporary, self.total_bytes = directory, [], 0

    def create(self, stack, suffix):
        file = stack.enter_context(tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", newline="", dir=self.directory, suffix=suffix+".tmp", delete=False))
        self.temporary.append(Path(file.name))
        return file

    def promote(self, path, stream_id, kind, suffix):
        require(path in self.temporary and path.suffix == ".tmp", "Promote only this writer's temporary artifact.")
        size = path.stat().st_size
        self.total_bytes += size
        require(self.total_bytes <= MAX_ARTIFACT_BYTES, "Generated artifacts exceed 4 GiB; split the source recording explicitly.")
        sha = digest(path)
        # Scratch names are temporary transport locations, not content identity.
        # Reuse the already-created unique name without its .tmp extension: a
        # successful temporary write must not fail because promotion adds a long
        # kind plus SHA filename on Windows. The full hash remains in the pinned
        # manifest and the manager's immutable object store.
        target = path.with_suffix("")
        if target.exists():
            require(digest(target) == sha, "Existing artifact hash mismatch.")
            path.unlink()
        else:
            os.replace(path, target)
        self.temporary.remove(path)
        return {"stream_id": stream_id, "kind": kind, "path": str(target), "sha256": sha, "bytes": size}

    def cleanup(self):
        for path in self.temporary:
            if path.exists():
                path.unlink()


def write_stream(descriptor, source_rows, writer, request_origin, preview_budget, is_xdf):
    stream_id = descriptor["id"]; channels = descriptor["channels"]
    factor = TIME_FACTORS.get(descriptor["clock"]["unit"])
    if factor is None:
        factor = decimal(descriptor["clock"]["seconds_per_tick"], "tick scale")
    rate = descriptor["nominal_srate"]
    expected_interval = Decimal(1) / Decimal(str(rate)) if rate > 0 else None
    segments, preview, count, missing = [], [], 0, {channel["id"]: 0 for channel in channels}
    previous, current, reconstructed, tied_markers, invalid_timestamps = None, None, 0, 0, 0
    with ExitStack() as stack:
        full = writer.create(stack, ".jsonl"); table = writer.create(stack, ".csv"); evidence = writer.create(stack, ".evidence.jsonl")
        output = csv.writer(table)
        leading = ["sequence", "segment_id", "clock_id", "timestamp_unit", "source_timestamp", "timestamp_state", "timestamp_ieee754_le_hex", "reconstructed_timestamp", "time_since_segment_start_s", *IDENTITY]
        value_fields = [field for c in channels for field in ("value_"+c["id"], "state_"+c["id"])]
        output.writerow(leading + value_fields)
        for correction in descriptor.get("clock_offsets", []):
            evidence.write(json_line({"type": "clock_offset", **correction}))
        for chunk in descriptor.get("chunks", []):
            evidence.write(json_line({"type": "source_chunk", **chunk}))
        for source in source_rows:
            count += 1
            require(len(source["values"]) == len(channels), "Sample width does not match its declared channels.")
            timestamp = decimal(source["timestamp"], "source timestamp", nullable=True)
            valid_time = timestamp is not None and source["timestamp_state"] == "observed"
            invalid_timestamps += int(not valid_time)
            reasons = [source["boundary"]] if source["boundary"] else []
            gap = None
            if previous is None:
                reasons.append("first_sample")
            else:
                if previous["identity"] != source["identity"]:
                    reasons.append("identity_change")
                if previous["clock_id"] != source["clock_id"]:
                    reasons.append("clock_id_change")
                if not valid_time or not previous["valid_time"]:
                    reasons.append("missing_or_unanchored_time")
                elif timestamp < previous["timestamp"]:
                    reasons.append("timestamp_reversal")
                elif timestamp == previous["timestamp"]:
                    if descriptor["kind"] == "markers":
                        tied_markers += 1
                    else:
                        reasons.append("duplicate_signal_timestamp")
                elif not reasons:
                    gap = (timestamp - previous["timestamp"]) * factor
                    if expected_interval is not None and gap > expected_interval * Decimal("1.5"):
                        reasons.append("nominal_sampling_gap")
            if reasons:
                current = {"id": stream_id+"-segment-"+str(len(segments)+1), "first_sequence": count, "last_sequence": count,
                           "sample_count": 0, "clock_id": source["clock_id"], "identity": source["identity"],
                           "start_timestamp": source["timestamp"] if valid_time else None, "end_timestamp": None,
                           "boundary_reasons": reasons, "preceding_interval_s": str(gap) if gap is not None else None}
                segments.append(current)
                require(len(segments) <= 100000, "Stream exceeds 100,000 explicit boundary segments.")
            current["last_sequence"] = count; current["sample_count"] += 1
            current["end_timestamp"] = source["timestamp"] if valid_time else None
            elapsed = (timestamp - Decimal(current["start_timestamp"])) * factor if valid_time and current["start_timestamp"] is not None else None
            values, states = {}, {}
            for channel, value in zip(channels, source["values"]):
                values[channel["id"]], states[channel["id"]] = typed_value(value, channel["value_type"], is_xdf)
                missing[channel["id"]] += int(states[channel["id"]] != "observed")
            reconstructed += int(source["reconstructed"])
            row = {"sequence": count, "stream_id": stream_id, "segment_id": current["id"], "clock_id": source["clock_id"],
                   "timestamp_unit": descriptor["clock"]["unit"], "source_timestamp": source["timestamp"], "timestamp_state": source["timestamp_state"],
                   "timestamp_ieee754_le_hex": source["timestamp_hex"], "reconstructed_timestamp": source["reconstructed"],
                   "time_since_segment_start_s": str(elapsed) if elapsed is not None else None,
                   "identity": source["identity"], "values": values, "value_states": states}
            encoded = json_line(row); full.write(encoded)
            output.writerow([count, current["id"], source["clock_id"], descriptor["clock"]["unit"], source["timestamp"], source["timestamp_state"],
                             source["timestamp_hex"], source["reconstructed"], row["time_since_segment_start_s"],
                             *[source["identity"].get(key) for key in IDENTITY], *[v for c in channels for v in (values[c["id"]], states[c["id"]])]])
            if len(preview) < MAX_PREVIEW and len(encoded) <= preview_budget[0]:
                preview.append(row); preview_budget[0] -= len(encoded)
            require(full.tell() + table.tell() + evidence.tell() + writer.total_bytes <= MAX_ARTIFACT_BYTES,
                    "Generated stream artifacts exceed the 4 GiB bound.")
            previous = {"timestamp": timestamp, "valid_time": valid_time, "identity": source["identity"], "clock_id": source["clock_id"]}
        for segment in segments:
            span = (Decimal(segment["end_timestamp"]) - Decimal(segment["start_timestamp"])) * factor if segment["start_timestamp"] is not None and segment["end_timestamp"] is not None else None
            segment["span_s"] = str(span) if span is not None else None
            segment["observed_row_rate_hz"] = float(Decimal(segment["sample_count"]-1) / span) if span is not None and span > 0 else None
            evidence.write(json_line({"type": "source_segment", **segment}))
        evidence.write(json_line({"type": "original_stream_metadata", "descriptor": {key: value for key, value in descriptor.items() if key not in ("clock_offsets", "chunks")}}))
        paths = [Path(full.name), Path(table.name), Path(evidence.name)]
    artifacts = [writer.promote(path, stream_id, kind, suffix) for path, kind, suffix in zip(paths,
                 ("stream_samples_jsonl", "stream_samples_csv", "stream_evidence_jsonl"), (".jsonl", ".csv", ".jsonl"))]
    declared_origin = origin(descriptor.get("origin_declaration"))
    result_origin = declared_origin or request_origin
    unknown_units = [c["id"] for c in channels if c.get("unit") in (None, "") and descriptor["kind"] != "markers"]
    result = {key: descriptor.get(key) for key in ("id", "name", "type", "kind", "kind_basis", "source_id", "uid", "source_session_id", "clock", "nominal_srate", "orderly_closed")}
    result["channels"] = [{key: value for key, value in channel.items() if key != "metadata_xml"} for channel in channels]
    result.update(schema="brohn-imported-stream/1.0", origin=result_origin, origin_declaration=descriptor.get("origin_declaration"),
        origin_basis="source_declared" if declared_origin else "researcher_declared_unverified", origin_conflict=declared_origin is not None and declared_origin != request_origin,
        sample_count=count, value_count=count*len(channels), segment_count=len(segments), segments_preview=segments[:20],
        segments_preview_truncated=len(segments)>20, clock_offset_count=len(descriptor.get("clock_offsets", [])),
        clock_offsets_preview=descriptor.get("clock_offsets", [])[:20], clock_offsets_preview_truncated=len(descriptor.get("clock_offsets", []))>20,
        preview=preview, preview_count=len(preview), preview_truncated=len(preview)<count, artifacts=artifacts,
        csv_schema={"leading_columns": leading, "channel_columns": [{"column": "value_"+c["id"], "state_column": "state_"+c["id"], "channel_id": c["id"], "value_type": c["value_type"]} for c in channels],
                    "canonical_format": "JSONL; CSV empty cells need the corresponding state column"},
        quality={"unknown_unit_channels": unknown_units, "requires_mapping": bool(unknown_units) or descriptor["kind"] == "unclassified",
                 "missing_values_by_channel": missing, "reconstructed_timestamp_count": reconstructed, "coincident_marker_count": tied_markers,
                 "invalid_or_unanchored_timestamp_count": invalid_timestamps,
                 "invalid_clock_offset_count": sum(x.get("collection_timestamp") is None or x.get("offset_s") is None for x in descriptor.get("clock_offsets", [])),
                 "source_order_preserved": True, "clock_correction_applied": False, "dejitter_applied": False, "calibration_applied": False,
                 "complete_source_samples_retained": True, "physical_synchronization_qualified": False})
    return result


def run(request):
    fields(request, ("schema", "operation", "format", "source_path", "source_hash", "output_directory", "metadata"))
    require(request["schema"] == "brohn-interchange-request/1.0" and request["operation"] == "import_multistream", "Unsupported interchange request.")
    require(request["format"] in ("xdf", "brohn_stream_bundle"), "Select XDF or brohn_stream_bundle.")
    source = Path(text(request["source_path"], "source_path", 4096)).resolve()
    require(source.is_file() and 0 < source.stat().st_size <= MAX_BYTES, "Source must be a local file of at most 512 MiB.")
    sha = text(request["source_hash"], "source_hash", 64)
    require(re.fullmatch(r"[a-f0-9]{64}", sha) and digest(source) == sha, "Source failed its pinned SHA-256 check.")
    fields(request["metadata"], ("origin", "origin_statement", "clock_policy"))
    metadata = request["metadata"]
    require(metadata["origin"] in ("imported", "sample", "pilot", "live") and metadata["clock_policy"] == "preserve_only", "Declare an origin and preserve_only clock policy.")
    text(metadata["origin_statement"], "origin_statement", 4000)
    directory = Path(text(request["output_directory"], "output_directory", 4096)).resolve()
    require(directory != source, "Artifact directory cannot be the source.")
    directory.mkdir(parents=True, exist_ok=True)
    is_xdf = request["format"] == "xdf"
    sources, container = xdf_sources(source) if is_xdf else bundle_sources(source)
    writer, preview_budget, results = ArtifactWriter(directory), [MAX_PREVIEW_BYTES], []
    container_artifacts = []
    try:
        for descriptor, rows in sources:
            results.append(write_stream(descriptor, rows, writer, metadata["origin"], preview_budget, is_xdf))
        require(digest(source) == sha, "Source changed during import.")
        with ExitStack() as stack:
            file = writer.create(stack, ".json"); file.write(json_line(container)); path = Path(file.name)
        container_artifacts = [writer.promote(path, None, "container_evidence_json", ".json")]
    finally:
        writer.cleanup()
    all_origins = {x["origin"] for x in results}
    conflict = any(x["origin_conflict"] for x in results)
    overall_origin = "mixed" if len(all_origins) != 1 or conflict else next(iter(all_origins))
    issues = any(x["quality"]["requires_mapping"] or x["orderly_closed"] is False for x in results) or conflict
    container_preview = {key: container.get(key) for key in ("schema", "source_rows", "source_values", "chunk_count", "origin_declaration")}
    container_preview.update(unknown_chunk_count=len(container.get("unknown_chunks", [])), unknown_chunks_preview=container.get("unknown_chunks", [])[:20],
                             parser_warnings=container.get("parser_warnings", []), evidence_artifact=container_artifacts[0])
    result = {"schema": "brohn-interchange-result/1.0", "operation": "import_multistream", "status": "needs_mapping" if issues else "imported",
            "source": {"sha256": sha, "bytes": source.stat().st_size, "format": request["format"]},
            "engine": {"name": "Brohn multistream importer", "version": "1.0.0", "python": platform.python_version(),
                       "pyxdf": importlib.metadata.version("pyxdf") if is_xdf else None, "script_sha256": digest(Path(__file__))},
            "origin": overall_origin, "origin_request": metadata["origin"], "origin_statement": metadata["origin_statement"],
            "streams": results, "artifacts": [a for stream in results for a in stream["artifacts"]] + container_artifacts, "container": container_preview,
            "quality": {"stream_count": len(results), "sample_count": sum(x["sample_count"] for x in results),
                        "value_count": sum(x["value_count"] for x in results), "origin_conflict": conflict,
                        "complete_source_samples_retained": True, "synchronized": False},
            "parameters": {"clock_policy": "preserve_only", "synchronize_clocks": False, "dejitter_timestamps": False,
                           "handle_clock_resets": "explicit Brohn source-order boundaries; pyxdf correction disabled",
                           "gap_policy": "split positive nominal-rate intervals above 1.5 nominal periods; never impute; irregular streams have no inferred gap threshold",
                           "preview_limit_per_stream": MAX_PREVIEW, "preview_limit_total_bytes": MAX_PREVIEW_BYTES,
                           "calibration_policy": "preserve declared units/scale/offset; no conversion", "canonical_format": "JSONL"},
            "limitations": ["This imports recorded stream evidence; it does not establish physical-device operation or synchronization accuracy.",
                            "Clock offsets, resets and original timestamps are retained. No fit, correction, resampling, sorting or stream merge is applied.",
                            "Timestamp reversal can mean reset or out-of-order data. Its boundary remains explicit rather than asserting a cause.",
                            "Coincident marker events retain file order. Markers are not analogue channels, and unknown stream types remain unclassified.",
                            "XDF omitted timestamp decompression follows its declared nominal rate and is individually flagged; unanchored values are not usable timing evidence.",
                            "Unit, channel-type, identity and calibration mappings must be reviewed before downstream scientific analysis.",
                            "JSONL is canonical for null, exact int64 and typed marker values; CSV is secondary and needs its schema/state columns."]}
    require(len(json_line(result)) <= 8*1024**2, "Compact stream manifest exceeds 8 MiB; split the source explicitly.")
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--request", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args(); request = {}; conflict = args.output.resolve() == args.request.resolve()
    try:
        require(not conflict, "Output must not overwrite request.")
        value = load_json(args.request, 2*1024**2)
        require(isinstance(value, dict), "Request must be an object.")
        request = value
        if isinstance(request.get("source_path"), str):
            conflict = args.output.resolve() == Path(request["source_path"]).resolve()
        require(not conflict, "Output must not overwrite source.")
        result = run(request)
    except Exception as error:
        result = {"schema": "brohn-interchange-result/1.0", "operation": "import_multistream", "status": "error",
                  "error": {"type": type(error).__name__, "message": str(error)}, "streams": [], "artifacts": [],
                  "quality": {"complete_source_samples_retained": False}}
    if conflict:
        print(json_line(result), file=sys.stderr)
        return 2
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=args.output.parent, delete=False) as stream:
        temporary = Path(stream.name); stream.write(json_line(result))
    os.replace(temporary, args.output)
    print(json_line({"status": result["status"], "streams": len(result["streams"])}).strip())
    return 2 if result["status"] == "error" else 0


if __name__ == "__main__":
    sys.exit(main())
