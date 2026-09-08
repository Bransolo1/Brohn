"""Explicit machine-scope LSL collection; raw clock evidence, durable chunks."""
from __future__ import annotations
import argparse
from datetime import datetime, timezone
import hashlib
import importlib.metadata
import json
import math
import os
from pathlib import Path
import re
import signal
import struct
import sys
import tempfile
import time
from xml.etree import ElementTree as ET

SCHEMA = "brohn-lsl-recording/1.0"
FORMATS = {1: "float32", 2: "float64", 3: "string", 4: "int32", 5: "int16", 6: "int8", 7: "int64"}
MAX_REQUEST = 2 * 1024**2
MAX_LINE = 2 * 1024**2
MAX_CHUNKS = 100000
_SESSION = None
_CONFIG = None


class RecorderError(ValueError):
    pass


def require(ok, message):
    if not ok:
        raise RecorderError(message)


def safe_id(value):
    require(isinstance(value, str) and re.fullmatch(r"[A-Za-z][A-Za-z0-9_-]{0,95}", value), "Use a safe bounded identifier.")
    return value


def text(value, name, maximum=500, nullable=False):
    if value is None and nullable:
        return value
    require(isinstance(value, str) and 0 < len(value.encode()) <= maximum, name + " needs bounded nonempty text.")
    return value


def number(value, name, low, high, integer=False):
    require(isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)
            and low <= value <= high and (not integer or int(value) == value), name + " exceeds its supported bounds.")
    return value


def encoded(value):
    return json.dumps(value, sort_keys=True, ensure_ascii=True, allow_nan=False, separators=(",", ":")).encode()


def sha(value):
    return hashlib.sha256(value).hexdigest()


def file_sha(path):
    result = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for part in iter(lambda: stream.read(1024**2), b""):
            result.update(part)
    return result.hexdigest()


def unique(pairs):
    value = {}
    for key, item in pairs:
        require(key not in value, "Duplicate JSON field.")
        value[key] = item
    return value


def decode(raw):
    return json.loads(raw, object_pairs_hook=unique, parse_constant=lambda _: (_ for _ in ()).throw(RecorderError("Nonfinite JSON literal.")))


def load(path, maximum=MAX_REQUEST):
    path = Path(path)
    require(path.is_file() and not path.is_symlink() and path.stat().st_size <= maximum, "Input absent, linked or oversized.")
    return decode(path.read_bytes())


def utc():
    return datetime.now(timezone.utc).isoformat()


def atomic(path, value, replace=True):
    path = Path(path)
    require(not path.is_symlink() and (replace or not path.exists()), "Refusing an existing or linked output.")
    raw = encoded(value)
    require(len(raw) <= 16 * 1024**2, "Manifest exceeds 16 MiB.")
    temporary = path.with_name(path.name + ".writing")
    require(not temporary.exists(), "An unfinished write already occupies this recording path.")
    with temporary.open("xb") as stream:
        stream.write(raw); stream.flush(); os.fsync(stream.fileno())
    for attempt in range(50):
        try:
            os.replace(temporary, path)
            break
        except PermissionError:
            if attempt == 49:
                raise
            time.sleep(.01)


def child_path(root, relative):
    require(isinstance(relative, str) and re.fullmatch(r"(?:chunks/)?[A-Za-z0-9_.-]+", relative), "Invalid recording member path.")
    path = root / relative
    require(not path.is_symlink() and not path.parent.is_symlink() and root in path.resolve().parents, "Recording member escapes its root.")
    return path


def check_recording_path_budget(directory):
    # The R archive/review stack also opens these ordinary Windows paths. Short
    # sequence filenames avoid spending 65 characters repeating the manifest's
    # SHA; this is not a claim that every consumer supports extended paths.
    if os.name == "nt":
        units = lambda path: len(str(path).encode("utf-16-le")) // 2
        require(units(directory / "manifest.json.writing") < 260 and
                units(directory / "chunks" / "100000.jsonl") < 260 and
                units(directory / "chunks") < 248,
                "The recording destination is too long for this Windows local profile. "
                "Choose a shorter workspace path before starting collection.")


def lsl(session):
    global _SESSION, _CONFIG
    safe_id(session)
    if _SESSION is None:
        require("pylsl" not in sys.modules, "Set the machine-scope session before importing pylsl.")
        handle = tempfile.NamedTemporaryFile(prefix="brohn-lsl-", suffix=".cfg", mode="w", delete=False)
        handle.write("[multicast]\nResolveScope = machine\n[lab]\nKnownPeers = {127.0.0.1}\nSessionID = " + session + "\n")
        handle.close(); _CONFIG = Path(handle.name)
        os.environ["LSLAPICFG"] = str(_CONFIG); _SESSION = session
    require(_SESSION == session, "A recorder process cannot switch LSL sessions.")
    import pylsl
    return pylsl


def engine(api):
    return {"adapter": "brohn-lsl/1.0", "script_sha256": file_sha(__file__), "python": sys.version.split()[0],
            "pylsl": importlib.metadata.version("pylsl"), "liblsl": api.library_version(), "liblsl_build": api.library_info(),
            "processing_flags": "proc_none", "recover": False, "resolve_scope": "machine", "known_peers": ["127.0.0.1"]}


def descriptor(info):
    xml = info.as_xml()
    require(len(xml.encode()) <= 1024**2 and "<!DOCTYPE" not in xml.upper() and "<!ENTITY" not in xml.upper(), "Oversized or active stream XML is unsupported.")
    root = ET.fromstring(xml)
    fmt = FORMATS.get(info.channel_format())
    require(fmt and 1 <= info.channel_count() <= 128, "Stream format or channel count is unsupported.")
    nodes = root.findall("./desc/channels/channel")
    require(not nodes or len(nodes) == info.channel_count(), "Source channel metadata count is inconsistent.")
    channels = [{"index": i, "label": nodes[i].findtext("label") if nodes else None,
                 "unit": nodes[i].findtext("unit") if nodes else None,
                 "type": nodes[i].findtext("type") if nodes else None, "value_type": fmt}
                for i in range(info.channel_count())]
    supported = fmt != "int64" or (os.name != "nt" and struct.calcsize("P") != 4)
    return {"uid": info.uid(), "source_id": info.source_id(), "name": info.name(), "type": info.type(),
            "nominal_srate": info.nominal_srate(), "channel_count": info.channel_count(), "value_type": fmt,
            "hostname": info.hostname(), "source_origin": root.findtext("./desc/origin"), "channels": channels,
            "metadata_xml": xml, "metadata_sha256": sha(xml.encode()), "supported": supported,
            "support_reason": None if supported else "Installed pylsl disables int64 transport on Windows/32-bit; choose a supported source representation without converting exact integers to doubles."}


def discover(request):
    require(request.get("schema") == "brohn-lsl-discovery-request/1.0", "Unsupported discovery request.")
    api = lsl(request["lsl_session"])
    timeout = number(request.get("timeout_s", 2), "discovery timeout", .1, 10)
    ids = request.get("source_ids")
    if ids is not None:
        require(isinstance(ids, list) and 1 <= len(ids) <= 16 and len(set(ids)) == len(ids), "Declare 1 to 16 distinct exact source IDs.")
        infos = []
        for source_id in ids:
            text(source_id, "source_id")
            infos.extend(api.resolve_byprop("source_id", source_id, minimum=1, timeout=timeout))
    else:
        require(request.get("allow_machine_discovery") is True, "Confirm metadata discovery or supply exact source IDs.")
        infos = api.resolve_streams(wait_time=timeout)
    require(len(infos) <= 64, "Discovery exceeds 64 streams; narrow exact source IDs.")
    found = []
    for info in infos:
        inlet = api.StreamInlet(info, max_buflen=1, recover=False, processing_flags=api.proc_none)
        try:
            # info() fetches metadata; open_stream()/pull_* are never called.
            found.append(descriptor(inlet.info(timeout=timeout)))
        finally:
            inlet.close_stream(); del inlet
    return {"schema": "brohn-lsl-discovery/1.0", "at": utc(), "lsl_session": request["lsl_session"],
            "metadata_only": True, "streams": found, "engine": engine(api)}


def validate_request(request):
    require(request.get("schema") == "brohn-lsl-record-request/1.0", "Unsupported recording request.")
    safe_id(request["recording_id"]); safe_id(request["lsl_session"])
    require(request.get("origin") in ("sample", "pilot", "live"), "Declare sample, pilot or live collection origin.")
    text(request.get("origin_statement"), "origin_statement", 4000)
    identity = request.get("identity")
    require(isinstance(identity, dict) and {"participant_id", "session_id"} <= set(identity)
            and set(identity) <= {"participant_id", "session_id", "condition_id", "exposure_id"}, "Supply participant/session identity explicitly.")
    for key, value in identity.items():
        text(value, key)
    references = request.get("references", {})
    require(isinstance(references, dict) and set(references) <= {"study_id", "design_hash", "run_id", "deployment_id"}, "Unknown research reference.")
    for key, value in references.items():
        text(value, key)
    streams = request.get("streams")
    require(isinstance(streams, list) and 1 <= len(streams) <= 16, "Select 1 to 16 streams explicitly.")
    ids, uids = set(), set()
    for stream in streams:
        sid = safe_id(stream["id"])
        require(sid not in ids and stream.get("uid") not in uids, "Duplicate selected stream.")
        ids.add(sid); uids.add(stream.get("uid"))
        for key in ("uid", "source_id", "clock_id", "unit_provenance"):
            text(stream.get(key), key, 1000)
        require(stream.get("clock_kind") in ("monotonic", "unix", "device", "unspecified_epoch"), "Declare the source timestamp clock kind; LSL transport timestamps are encoded in seconds.")
        require(re.fullmatch(r"[0-9a-f]{64}", stream.get("metadata_sha256", "")), "Freeze the discovered metadata hash.")
        require(stream.get("kind") in ("signal", "markers", "unclassified"), "Declare stream kind.")
        channels = stream.get("channels")
        require(isinstance(channels, list) and 1 <= len(channels) <= 128, "Explicit channels required.")
        cids = set()
        for channel in channels:
            cid = safe_id(channel["id"]); require(cid not in cids, "Duplicate channel ID."); cids.add(cid)
            require(channel.get("value_type") in FORMATS.values(), "Declare the original channel type.")
            for key in ("label", "type", "unit"):
                text(channel.get(key), "channel " + key, nullable=key == "unit")
            require(channel["unit"] is not None or channel["value_type"] == "string", "Numeric units must be declared, including explicit 'unknown' when unavailable.")
        if stream.get("gap_threshold_s") is not None:
            number(stream["gap_threshold_s"], "gap threshold", .000001, 3600)
    limits = request.get("limits", {})
    for key, low, high, integer in (("max_duration_s", .1, 86400, False), ("max_samples", 1, 2000000, True),
                                   ("max_bytes", 65536, 512*1024**2, True), ("chunk_samples", 1, 512, True),
                                   ("inlet_buffer", 1, 60, True)):
        number(limits.get(key), key, low, high, integer)
    require(limits["max_samples"] * max(len(s["channels"]) for s in streams) <= 20000000, "Recording exceeds 20 million potential channel values.")
    return request


def value_record(value, fmt):
    if fmt == "string":
        require(isinstance(value, str) and len(value.encode()) <= 32768, "Source string exceeds 32 KiB.")
        return value, "observed", None
    if fmt.startswith("int"):
        require(isinstance(value, int), "LSL integer payload changed type.")
        return str(value) if fmt == "int64" else value, "observed", None
    value = float(value)
    bits = struct.pack("<f" if fmt == "float32" else "<d", value).hex()
    state = "observed" if math.isfinite(value) else "nan" if math.isnan(value) else "positive_infinity" if value > 0 else "negative_infinity"
    return value if state == "observed" else None, state, bits


class Writer:
    def __init__(self, directory, request, evidence):
        self.root, self.request = directory, request
        self.tip = "0"*64; self.index = 0; self.chunks = []; self.rows = 0; self.bytes = 0; self.journal_bytes = 0
        self.counts = {stream["id"]: 0 for stream in request["streams"]}
        self.previous = {}; self.segments = {sid: 1 for sid in self.counts}; self.quality = {sid: {"nonfinite_values": 0, "gaps": 0, "resets": 0} for sid in self.counts}
        self.evidence = evidence
        self.journal = child_path(directory, "journal.jsonl").open("xb")
        atomic(directory / "request.json", request, replace=False)
        atomic(directory / "streams.json", evidence, replace=False)
        self.log("opened", request_sha256=sha(encoded(request)), streams_sha256=sha(encoded(evidence)))
        self.status("starting")

    def log(self, kind, **fields):
        self.index += 1
        record = dict(index=self.index, previous_sha256=self.tip, type=kind, at=utc(), **fields)
        self.tip = sha(encoded(record)); record["sha256"] = self.tip
        raw = encoded(record) + b"\n"
        require(len(raw) <= MAX_LINE, "Journal record exceeds limit.")
        require(self.journal_bytes + len(raw) <= 64*1024**2, "Journal exceeds 64 MiB; stop and inspect the committed recording.")
        self.journal.write(raw); self.journal.flush(); os.fsync(self.journal.fileno())
        self.journal_bytes += len(raw)

    def status(self, status, reason=None):
        atomic(self.root / "status.json", {"schema": SCHEMA, "recording_id": self.request["recording_id"],
            "request_sha256": sha(encoded(self.request)), "completion_status": status, "reason": reason, "updated_at": utc(),
            "samples": self.rows, "sample_bytes": self.bytes, "stream_counts": self.counts, "chunks": len(self.chunks),
            "journal_tip": self.tip, "quality": self.quality, "quality_qualified": False})

    def chunk(self, selected, values, stamps, before, after, reset=False):
        sid = selected["id"]; fmt = selected["channels"][0]["value_type"]
        prior = (self.previous.get(sid), self.segments[sid], dict(self.quality[sid]))
        records = []
        for offset, (sample, timestamp) in enumerate(zip(values, stamps)):
            require(len(sample) == len(selected["channels"]) and math.isfinite(timestamp), "LSL payload width or timestamp is invalid.")
            previous = self.previous.get(sid); boundaries = []
            if (reset and offset == 0) or (previous is not None and timestamp < previous):
                self.segments[sid] += 1; self.quality[sid]["resets"] += 1; boundaries.append("clock_reset" if reset else "timestamp_reversal")
            if previous is not None and timestamp == previous:
                boundaries.append("coincident_timestamp")
            gap = selected.get("gap_threshold_s")
            if gap is not None and previous is not None and timestamp - previous > gap:
                self.quality[sid]["gaps"] += 1; boundaries.append("declared_gap_threshold")
            self.previous[sid] = timestamp
            typed = [value_record(value, fmt) for value in sample]
            self.quality[sid]["nonfinite_values"] += sum(item[1] != "observed" for item in typed)
            records.append({"sequence": self.counts[sid] + offset + 1, "segment": self.segments[sid],
                "source_timestamp": repr(timestamp), "source_timestamp_ieee754_le_hex": struct.pack("<d", timestamp).hex(),
                "receive_before_s": repr(before), "receive_after_s": repr(after), "receive_scope": "pull_chunk",
                "values": [v[0] for v in typed], "value_states": [v[1] for v in typed],
                "value_ieee754_le_hex": [v[2] for v in typed], "boundary_reasons": boundaries})
        raw = b"".join(encoded(record) + b"\n" for record in records)
        require(all(len(encoded(record)) < MAX_LINE for record in records), "Sample exceeds size limit.")
        if self.bytes + len(raw) > self.request["limits"]["max_bytes"]:
            if prior[0] is None:
                self.previous.pop(sid, None)
            else:
                self.previous[sid] = prior[0]
            self.segments[sid], self.quality[sid] = prior[1:]
            self.log("unwritten_received_samples", stream_id=sid, count=len(records), reason="max_bytes")
            return False
        require(len(self.chunks) < MAX_CHUNKS, "Chunk count exceeds 100,000; choose larger chunks or shorter recordings.")
        # Hashes remain explicit in both the chained journal and final manifest.
        # A bounded owned filename also permits realistic nested workspaces on
        # Windows without exceeding the legacy archive stack's path limit.
        digest = sha(raw); relative = f"chunks/{len(self.chunks)+1:06d}.jsonl"
        path = child_path(self.root, relative)
        with path.open("xb") as file:
            file.write(raw); file.flush(); os.fsync(file.fileno())
        entry = {"path": relative, "sha256": digest, "bytes": len(raw), "stream_id": sid, "rows": len(records),
                 "first_sequence": self.counts[sid]+1, "last_sequence": self.counts[sid]+len(records)}
        self.log("chunk", chunk=entry)
        self.chunks.append(entry); self.counts[sid] += len(records); self.rows += len(records); self.bytes += len(raw)
        self.status("recording")
        return True

    def finish(self, status, reason):
        self.log("closed", completion_status=status, reason=reason, samples=self.rows)
        manifest = {"schema": SCHEMA, "recording_id": self.request["recording_id"], "completion_status": status,
            "complete": status == "completed", "orderly_closed": True, "reason": reason,
            "request_sha256": sha(encoded(self.request)), "streams_sha256": sha(encoded(self.evidence)),
            "journal_tip": self.tip, "chunks": self.chunks, "samples": self.rows, "sample_bytes": self.bytes,
            "quality": self.quality, "quality_qualified": False, "signal_quality": "not_qualified",
            "clock_synchronized": False, "closed_at": utc()}
        atomic(self.root / "manifest.json", manifest, replace=False)
        self.status(status, reason); self.journal.close()
        return manifest


def record(request):
    validate_request(request)
    parent = Path(request["output_root"])
    require(parent.is_dir() and not parent.is_symlink(), "Choose an existing nonlinked output root.")
    parent = parent.resolve(); directory = parent / request["recording_id"]
    require(not directory.exists(), "Recordings never overwrite or append to an existing session directory.")
    check_recording_path_budget(directory)
    directory.mkdir(); (directory / "chunks").mkdir()
    api = lsl(request["lsl_session"]); inlets = []; writer = None
    from pylsl.util import TimeoutError as LSLTimeoutError
    cancel = {"signal": False}
    previous_handlers = {}
    for sig in (signal.SIGINT, signal.SIGTERM):
        previous_handlers[sig] = signal.signal(sig, lambda *_: cancel.update(signal=True))
    try:
        evidence = {"engine": engine(api), "streams": [], "receiver_clock_id": "lsl-receiver-" + request["recording_id"],
            "limitations": ["Receipt sequence is not a device packet counter; upstream drops may be undetectable.",
                "Native inlet bounds use seconds at regular rates, or multiples of 100 samples for irregular streams.",
                "Receive intervals describe pull_chunk calls, not measured per-sample network arrival.",
                "Clock correction is observed but never applied; this recorder does not establish inter-device or stimulus timing accuracy.",
                "Finite numeric values are not proof of physiological validity; source units are unqualified declarations.",
                "String length is checked after the native library receives it; this is not a hardened arbitrary-network ingestion service."]}
        for selected in request["streams"]:
            matches = api.resolve_byprop("source_id", selected["source_id"], minimum=1, timeout=3)
            exact = [info for info in matches if info.uid() == selected["uid"]]
            require(len(exact) == 1, "Frozen source UID is absent or ambiguous; discover and select the new outlet explicitly.")
            inlet = api.StreamInlet(exact[0], max_buflen=int(request["limits"]["inlet_buffer"]),
                max_chunklen=int(request["limits"]["chunk_samples"]), recover=False, processing_flags=api.proc_none)
            inlets.append((selected, inlet))
            observed = descriptor(inlet.info(timeout=3))
            require(observed["supported"], observed["support_reason"])
            source_origin = (observed["source_origin"] or "").lower()
            classified = "sample" if source_origin in ("synthetic", "sample", "synthetic/reference") else source_origin
            require(classified not in ("sample", "pilot", "live") or classified == request["origin"],
                    "Declared collection origin conflicts with the source's own origin; separate synthetic, pilot and live recordings.")
            require(observed["metadata_sha256"] == selected["metadata_sha256"], "Selected stream metadata changed; review it before recording.")
            require(len(selected["channels"]) == observed["channel_count"] and all(c["value_type"] == observed["value_type"] for c in selected["channels"]), "Declared channels must match the complete original LSL channel layout.")
            number(observed["nominal_srate"], "nominal sample rate", 0, 100000)
            buffered_samples = max(observed["nominal_srate"], 100) * request["limits"]["inlet_buffer"]
            require(buffered_samples * len(selected["channels"]) <= 4000000, "Declared inlet buffer exceeds four million channel values.")
            evidence["streams"].append({"id": selected["id"], "observed": observed, "declared": selected})
        writer = Writer(directory, request, evidence)
        for _, inlet in inlets:
            inlet.open_stream(timeout=3)
        writer.log("subscribed", receiver_timestamp_s=repr(api.local_clock()))
        writer.status("recording")
        started = time.monotonic(); correction_at = started; reason = None; status = "completed"
        while reason is None:
            elapsed = time.monotonic() - started
            if cancel["signal"]:
                reason, status = "signal_cancel", "cancelled"; break
            control = directory / "control.json"
            if control.exists():
                command = load(control, 4096)
                require(command.get("recording_id") == request["recording_id"] and command.get("request_sha256") == sha(encoded(request))
                        and command.get("operation") in ("stop", "cancel"), "Control does not match this exact recording request.")
                reason = "requested_" + command["operation"]
                status = "cancelled" if command["operation"] == "cancel" else "completed"
                writer.log("control_received", operation=command["operation"], receiver_timestamp_s=repr(api.local_clock()))
                break
            if elapsed >= request["limits"]["max_duration_s"]:
                reason = "max_duration"; break
            if writer.rows >= request["limits"]["max_samples"]:
                reason = "max_samples"; break
            received = False
            for selected, inlet in inlets:
                remaining = int(request["limits"]["max_samples"] - writer.rows)
                if remaining <= 0:
                    reason = "max_samples"; break
                before = api.local_clock()
                values, stamps = inlet.pull_chunk(timeout=0, max_samples=min(int(request["limits"]["chunk_samples"]), remaining))
                after = api.local_clock()
                if stamps:
                    received = True
                    if not writer.chunk(selected, values, stamps, before, after, inlet.was_clock_reset()):
                        reason, status = "max_bytes", "incomplete"; break
            if time.monotonic() >= correction_at and reason is None:
                for selected, inlet in inlets:
                    before = api.local_clock()
                    try:
                        offset = inlet.time_correction(timeout=.01)
                        writer.log("clock_correction", stream_id=selected["id"], collection_timestamp=repr(api.local_clock()),
                            query_before_s=repr(before), offset_s=repr(offset), reference_clock_id=evidence["receiver_clock_id"],
                            uncertainty_s=None, remote_time_s=None, applied=False)
                    except LSLTimeoutError:
                        writer.log("clock_correction_unavailable", stream_id=selected["id"], receiver_timestamp_s=repr(api.local_clock()), reason="timeout")
                correction_at = time.monotonic() + 1
                writer.status("recording")
            if not received:
                time.sleep(.005)
        # Manual stop drains a bounded immediately available tail. Every pull
        # is already fsynced, so there is no application-side pending buffer.
        if reason == "requested_stop":
            drain_deadline = time.monotonic() + .25
            drained = 0
            while time.monotonic() < drain_deadline and drained < 4096 and writer.rows < request["limits"]["max_samples"]:
                got_any = False
                for selected, inlet in inlets:
                    available = min(int(request["limits"]["chunk_samples"]), int(request["limits"]["max_samples"]-writer.rows), 4096-drained)
                    if available <= 0:
                        break
                    before = api.local_clock(); values, stamps = inlet.pull_chunk(timeout=0, max_samples=available); after = api.local_clock()
                    if stamps:
                        got_any = True; drained += len(stamps)
                        if not writer.chunk(selected, values, stamps, before, after, inlet.was_clock_reset()):
                            reason, status = "max_bytes_during_stop", "incomplete"; break
                if not got_any or status != "completed":
                    break
            writer.log("stop_drain", samples=drained, maximum_samples=4096, maximum_duration_s=.25,
                       receiver_timestamp_s=repr(api.local_clock()), includes_post_control_receipt=True)
        # close_stream drops queued/in-flight data; record the known queue size
        # as an observation, never a claim that all device data arrived.
        for selected, inlet in inlets:
            writer.log("closing_inlet", stream_id=selected["id"], buffered_samples_observed=inlet.samples_available(),
                receiver_timestamp_s=repr(api.local_clock()), tail_policy="bounded_manual_stop_drain_then_close; no exact device cutoff implied")
            inlet.close_stream()
        return writer.finish(status, reason)
    except BaseException as error:
        if writer is not None and not writer.journal.closed:
            try:
                for _, inlet in inlets:
                    inlet.close_stream()
                writer.log("error", message=str(error)[:2000])
                writer.finish("incomplete", "recorder_error")
            except Exception:
                writer.journal.close()
        raise
    finally:
        for _, inlet in inlets:
            try:
                inlet.close_stream()
            except Exception:
                pass
        inlets.clear()
        for sig, handler in previous_handlers.items():
            signal.signal(sig, handler)


def inspect_recording(path):
    root = Path(path)
    require(root.is_dir() and not root.is_symlink(), "Choose a real recording directory.")
    root = root.resolve(); request = load(child_path(root, "request.json")); validate_request(request)
    evidence = load(child_path(root, "streams.json"), 16*1024**2)
    journal = child_path(root, "journal.jsonl")
    require(journal.is_file() and journal.stat().st_size <= 128*1024**2, "Journal absent or oversized.")
    tip = "0"*64; index = 0; chunks = []; counts = {s["id"]: 0 for s in request["streams"]}; offsets = []; torn_tail = False; last = None
    with journal.open("rb") as stream:
        while True:
            line = stream.readline(MAX_LINE+1)
            if not line:
                break
            require(len(line) <= MAX_LINE, "Oversized journal line.")
            if not line.endswith(b"\n"):
                torn_tail = True; break
            item = decode(line); claimed = item.pop("sha256")
            require(claimed == sha(encoded(item)) and item["previous_sha256"] == tip and item["index"] == index+1, "Journal chain is corrupt.")
            tip = claimed; index += 1; last = item
            if index == 1:
                require(item["type"] == "opened" and item["request_sha256"] == sha(encoded(request)) and item["streams_sha256"] == sha(encoded(evidence)), "Recording source manifests do not match journal.")
            if item["type"] == "chunk":
                entry = item["chunk"]; sid = entry["stream_id"]
                require(sid in counts and entry["first_sequence"] == counts[sid]+1 and len(chunks) < MAX_CHUNKS, "Chunk sequence is invalid.")
                part = child_path(root, entry["path"])
                require(part.is_file() and part.stat().st_size == entry["bytes"] and file_sha(part) == entry["sha256"], "Committed sample chunk is absent or corrupt.")
                rows = 0
                with part.open("rb") as samples:
                    for line in samples:
                        require(len(line) <= MAX_LINE and line.endswith(b"\n"), "Malformed sample row.")
                        row = decode(line); rows += 1
                        require(row["sequence"] == counts[sid]+rows, "Sample sequence mismatch.")
                require(rows == entry["rows"] and entry["last_sequence"] == counts[sid]+rows, "Chunk row count mismatch.")
                counts[sid] += rows; chunks.append(entry)
            elif item["type"] == "clock_correction":
                offsets.append(item)
    require(index > 0, "No committed journal header exists.")
    manifest_path = child_path(root, "manifest.json")
    manifest = load(manifest_path, 16*1024**2) if manifest_path.exists() else None
    quality_qualified = None; signal_quality = None
    quality_evidence = "missing_final_manifest"
    if manifest:
        require(not torn_tail and last["type"] == "closed" and manifest["journal_tip"] == tip and manifest["chunks"] == chunks
                and manifest["samples"] == sum(counts.values()) and manifest["request_sha256"] == sha(encoded(request))
                and manifest["streams_sha256"] == sha(encoded(evidence)), "Final manifest does not match committed journal.")
        require(manifest["completion_status"] == last["completion_status"] and manifest["complete"] == (manifest["completion_status"] == "completed"), "Terminal status is inconsistent.")
        quality_evidence = "missing_quality_fields"
        if "quality_qualified" in manifest or "signal_quality" in manifest:
            # This collection recipe never qualifies physiology. An altered or
            # unsupported quality claim cannot become a checked terminal fact.
            require(manifest.get("quality_qualified") is False and manifest.get("signal_quality") == "not_qualified",
                    "Final manifest has an unsupported signal-quality claim.")
            quality_qualified = manifest["quality_qualified"]
            signal_quality = manifest["signal_quality"]
            quality_evidence = "verified_final_manifest"
    committed = {entry["path"] for entry in chunks}
    orphan_count = sum("chunks/" + file.name not in committed for file in (root/"chunks").iterdir())
    return {"schema": "brohn-lsl-inspection/1.0", "recording_id": request["recording_id"], "request": request, "evidence": evidence,
        "completion_status": manifest["completion_status"] if manifest else "interrupted", "complete": bool(manifest and manifest["complete"]),
        "quality_qualified": quality_qualified, "signal_quality": signal_quality, "quality_evidence": quality_evidence,
        "samples": sum(counts.values()), "stream_counts": counts, "chunks": chunks, "clock_corrections": offsets,
        "journal_tip": tip, "torn_journal_tail": torn_tail, "orphan_files_not_trusted": orphan_count,
        "request_sha256": sha(encoded(request)), "manifest_sha256": file_sha(manifest_path) if manifest else None}


def export_bundle(path, output, allow_incomplete=False):
    inspection = inspect_recording(path)
    require(inspection["complete"] or allow_incomplete, "Recording is incomplete/cancelled; explicitly accept a recovered subset before export.")
    request = inspection["request"]; root = Path(path).resolve()
    output = Path(output)
    require(not output.exists() and output.parent.resolve() != root and root not in output.parent.resolve().parents, "Export needs a new destination outside the canonical recording.")
    temporary = output.with_name(output.name + ".writing")
    require(not temporary.exists(), "An unfinished export occupies this destination.")
    # Stream the secondary export without materialising the sample population.
    # Its strict 64 MiB cap matches the current interchange importer.
    size = 0; digest = hashlib.sha256()
    def write(file, raw):
        nonlocal size
        size += len(raw)
        require(size <= 64*1024**2, "Bundle exceeds importer 64 MiB limit; keep original recording for a future streaming adapter.")
        file.write(raw); digest.update(raw)

    def stream_metadata(selected):
        observed = next(s["observed"] for s in inspection["evidence"]["streams"] if s["id"] == selected["id"])
        return {"id": selected["id"], "name": observed["name"], "type": observed["type"], "kind": selected["kind"],
            "source_id": selected["source_id"], "uid": selected["uid"], "nominal_srate": observed["nominal_srate"],
            "clock": {"id": selected["clock_id"], "unit": "s", "kind": selected["clock_kind"], "representation": "decimal_string"},
            "identity": request["identity"], "channels": selected["channels"],
            "clock_offsets": [{key: observation[key] for key in ("collection_timestamp", "offset_s", "reference_clock_id", "uncertainty_s")}
                              for observation in inspection["clock_corrections"] if observation["stream_id"] == selected["id"]],
            "metadata": {"parent_recording": {"schema": SCHEMA, "recording_id": request["recording_id"],
                "request_sha256": inspection["request_sha256"], "manifest_sha256": inspection["manifest_sha256"],
                "journal_tip": inspection["journal_tip"], "completion_status": inspection["completion_status"],
                "canonical_chunks": inspection["chunks"]}, "references": request.get("references", {}),
                "source_origin": observed["source_origin"], "unit_provenance": selected["unit_provenance"],
                "secondary_export": "Keep original recording: receive clocks and raw IEEE/nonfinite states remain there; no correction applied."}}
    try:
        with temporary.open("xb") as file:
            header = {"schema": "brohn-stream-bundle/1.0", "origin": request["origin"], "description": request["origin_statement"]}
            write(file, encoded(header)[:-1] + b',"streams":[')
            for index, selected in enumerate(request["streams"]):
                if index:
                    write(file, b",")
                write(file, encoded(stream_metadata(selected))[:-1] + b',"samples":[')
                first = True
                for entry in inspection["chunks"]:
                    if entry["stream_id"] != selected["id"]:
                        continue
                    path = child_path(root, entry["path"])
                    require(file_sha(path) == entry["sha256"], "Chunk changed after inspection.")
                    with path.open("rb") as part:
                        for line in part:
                            row = decode(line)
                            sample = {"timestamp": row["source_timestamp"], "values": row["values"], "clock_id": selected["clock_id"],
                                "reset": any(b in ("clock_reset", "timestamp_reversal") for b in row["boundary_reasons"])}
                            write(file, (b"" if first else b",") + encoded(sample)); first = False
                    require(file_sha(path) == entry["sha256"], "Chunk changed during export.")
                write(file, b"]}")
            write(file, b"]}"); file.flush(); os.fsync(file.fileno())
        # Link creates the final name atomically and refuses an existing target.
        os.link(temporary, output)
    finally:
        if temporary.exists():
            temporary.unlink()
    return {"schema": "brohn-lsl-export/1.0", "path": str(output.resolve()), "sha256": digest.hexdigest(), "bytes": size,
            "parent_recording_id": request["recording_id"], "parent_journal_tip": inspection["journal_tip"], "complete": inspection["complete"]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("operation", choices=("discover", "record", "inspect", "export-bundle"))
    parser.add_argument("--request", type=Path); parser.add_argument("--recording", type=Path)
    parser.add_argument("--bundle-output", type=Path); parser.add_argument("--allow-incomplete", action="store_true")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args(); code = 0
    require(not args.output.exists(), "Receipt output must be absent.")
    try:
        if args.operation == "discover":
            result = discover(load(args.request))
        elif args.operation == "record":
            result = record(load(args.request))
        elif args.operation == "inspect":
            result = inspect_recording(args.recording)
        else:
            result = export_bundle(args.recording, args.bundle_output, args.allow_incomplete)
    except Exception as error:
        result = {"schema": SCHEMA, "status": "error", "error": {"type": type(error).__name__, "message": str(error)[:2000]}}
        code = 2
    finally:
        if _CONFIG is not None:
            _CONFIG.unlink(missing_ok=True)
    atomic(args.output, result, replace=False)
    return code


if __name__ == "__main__":
    sys.exit(main())
