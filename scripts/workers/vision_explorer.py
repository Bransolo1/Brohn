"""Derived, bounded browsing index of complete saved video observations.

This module performs no inference. Numeric JSON tokens survive unchanged.
The calling domain owns current authority and retains native file read guards.
"""
from __future__ import annotations
import argparse
import base64
import csv
from contextlib import contextmanager
from decimal import Decimal, InvalidOperation, localcontext
import hashlib
import json
import math
from pathlib import Path
import re
import sqlite3
import sys
import tempfile

SCHEMA = "brohn-vision-explorer-index/1.0"
RECIPE = "saved-video-geometry-explorer/1.0"
MAX_SOURCE = 2 * 1024**3
MAX_INDEX = 256 * 1024**2
MAX_LINE = 1024**2
MAX_RESPONSE = 2 * 1024**2
MAX_FRAMES = 36000
MAX_METRICS = 128
MAX_POINTS = 2000
MAX_PAGE = 100
HASH = re.compile(r"^[a-f0-9]{64}$")
NAME = re.compile(r"^[A-Za-z_][A-Za-z0-9_]{0,95}$")


class InputError(ValueError): pass
class Number(str): pass
def require(ok, message):
    if not ok: raise InputError(message)
def encoded(value): return json.dumps(value, ensure_ascii=False, allow_nan=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
def sha(value): return hashlib.sha256(value).hexdigest()
def digest(path):
    with open(path, "rb") as stream: return hashlib.file_digest(stream, "sha256").hexdigest()
def object_pairs(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, "Duplicate JSON object key."); result[key] = value
    return result
def loads(raw, tokens=False):
    try:
        return json.loads(raw, object_pairs_hook=object_pairs,
            parse_float=Number if tokens else float, parse_int=Number if tokens else int,
            parse_constant=lambda _: (_ for _ in ()).throw(InputError("Nonfinite JSON constant.")))
    except (ValueError, UnicodeError, RecursionError) as error: raise InputError("Invalid bounded JSON: " + str(error)) from error
def fields(value, required, optional=()):
    require(isinstance(value, dict) and set(required) <= set(value) <= set(required) | set(optional), "Incompatible observation fields.")
def integer(value, low=0, high=MAX_FRAMES):
    if isinstance(value, Number):
        require(re.fullmatch(r"-?(0|[1-9][0-9]*)", value) is not None, "Expected original integer token."); value = int(value)
    require(type(value) is int and low <= value <= high, "Integer outside the supported bounds."); return value
def number(value, nullable=False):
    if value is None and nullable: return None
    require(isinstance(value, Number) and len(value) <= 128, "Expected a bounded original numeric token.")
    try: result = Decimal(value)
    except InvalidOperation as error: raise InputError("Invalid numeric token.") from error
    require(result.is_finite() and math.isfinite(float(result)), "Nonfinite observation value."); return result
def decimal_text(value):
    require(type(value) is str and 0 < len(value) <= 128, "Enter a finite decimal coordinate.")
    try: result = Decimal(value)
    except InvalidOperation as error: raise InputError("Invalid decimal coordinate.") from error
    require(result.is_finite(), "Nonfinite decimal coordinate."); return result
def difference(a, b):
    with localcontext() as context:
        context.prec = 300
        return a - b
def descriptor(path): return {"sha256": digest(path), "bytes": path.stat().st_size}
def check_file(path, reference, maximum):
    require(isinstance(reference, dict) and HASH.fullmatch(reference.get("sha256", "")), "Missing exact file digest.")
    integer(reference.get("bytes"), 1, maximum)
    require(path.is_file() and not path.is_symlink() and path.stat().st_size == reference["bytes"], "Saved file size or type changed.")
def bound_response(result):
    require(len(encoded(result)) <= MAX_RESPONSE, "This response exceeds 2 MiB; request a narrower view or exact artifact download."); return result


def native_points(points, count):
    require(isinstance(points, list) and len(points) == count, "Unexpected native landmark count.")
    for point in points:
        fields(point, ("x", "y", "z", "visibility", "presence"))
        for value in point.values(): number(value, nullable=True)


def observations(row, channels):
    """Return saved eligible metrics; invalid raw observations stay in the source."""
    metrics, states = {}, {}
    for channel in channels:
        item = row[channel]
        common = ("count", "count_is_lower_bound", "valid", "state")
        fields(item, common + (("hands",) if channel == "hands" else ("landmarks", "geometry")),
               ("blendshapes", "image_border_contact") if channel == "face" else ("landmark_valid_mask",) if channel == "pose" else ())
        count = integer(item["count"], 0, 2)
        require(type(item["valid"]) is bool and type(item["count_is_lower_bound"]) is bool and item["count_is_lower_bound"] == (count == 2), "Detection count/validity declaration is inconsistent.")
        allowed = {"absent", "detected"} if channel == "hands" else {"absent", "multiple", "single", "invalid_geometry", "border_geometry"} if channel == "face" else {"absent", "multiple", "single", "insufficient_visible_joints"}
        require(item["state"] in allowed, "Unknown saved geometry state.")
        require((count == 0) == (item["state"] == "absent"), "Absent state and detection count disagree.")
        if channel != "hands":
            require((count == 2) == (item["state"] == "multiple"), "Multiple state and detection count disagree.")
            if count != 1:
                require(item["valid"] is False and item["landmarks"] is None and item["geometry"] is None and item.get("blendshapes") is None, "Absent/multiple observations cannot supply a selected person.")
            else:
                native_points(item["landmarks"], 478 if channel == "face" else 33)
                if channel == "pose":
                    require(isinstance(item.get("landmark_valid_mask"), list) and len(item["landmark_valid_mask"]) == 33 and all(type(x) is bool for x in item["landmark_valid_mask"]), "Missing saved pose point validity.")
                if item["valid"]:
                    require(item["state"] == "single", "Eligible geometry needs the saved single-person state.")
                    keys = ("outer_eye_distance_image_width", "lip_separation_image_width") if channel == "face" else ("left_elbow_angle_deg", "right_elbow_angle_deg")
                    fields(item["geometry"], keys)
                    for key, value in item["geometry"].items():
                        if number(value, nullable=True) is not None: metrics[channel + "." + key] = str(value)
                    if channel == "face":
                        require(isinstance(item.get("blendshapes"), dict) and len(item["blendshapes"]) <= 124, "Missing/bounded native blendshape outputs.")
                        for key, value in item["blendshapes"].items():
                            require(NAME.fullmatch(key) and 0 <= number(value) <= 1, "Invalid native blendshape name or value.")
                            metrics["face.blendshape." + key] = str(value)
        else:
            require(isinstance(item["hands"], list) and len(item["hands"]) == count, "Hand count differs from native observations.")
            labels = []
            for hand in item["hands"]:
                fields(hand, ("frame_index", "handedness", "handedness_score", "valid", "landmarks", "geometry", "summary_valid"))
                integer(hand["frame_index"], 0, 1); require(hand["handedness"] in ("Left", "Right"), "Unknown native handedness.")
                require(0 <= number(hand["handedness_score"]) <= 1 and type(hand["valid"]) is bool and type(hand["summary_valid"]) is bool, "Invalid hand validity/score.")
                native_points(hand["landmarks"], 21); fields(hand["geometry"], ("thumb_index_distance_over_palm",))
                number(hand["geometry"]["thumb_index_distance_over_palm"], nullable=True); labels.append(hand["handedness"])
            require(len({int(hand["frame_index"]) for hand in item["hands"]}) == count, "Duplicate within-frame hand index.")
            for hand in item["hands"]:
                require(hand["summary_valid"] == (hand["valid"] and labels.count(hand["handedness"]) == 1), "Ambiguous native handedness cannot form a stable series.")
                if hand["summary_valid"]:
                    value = hand["geometry"]["thumb_index_distance_over_palm"]; number(value)
                    metrics["hands." + hand["handedness"] + ".thumb_index_distance_over_palm"] = str(value)
            require(item["valid"] == any(hand["summary_valid"] for hand in item["hands"]), "Hand channel validity disagrees with saved per-hand support.")
        states[channel] = {"state": item["state"], "valid": item["valid"], "count": count, "count_is_lower_bound": item["count_is_lower_bound"]}
    return metrics, states


def metric_descriptor(name):
    return {"id": name, "channel": name.split(".")[0], "unit": "degrees" if name.endswith("_deg") else "model_score_0_1" if ".blendshape." in name else "ratio"}


def build(request):
    source, target = Path(request["artifact_path"]), Path(request["index_path"])
    check_file(source, request["artifact"], MAX_SOURCE)
    require(not target.exists() and source.resolve() != target.resolve(), "Choose a new owned index path.")
    binding_json = request["binding_json"]
    require(type(binding_json) is str and len(binding_json.encode()) <= MAX_RESPONSE and sha(binding_json.encode()) == request["binding_sha256"], "Exact source binding changed.")
    loads(binding_json)
    parameters, quality = request["parameters"], request["quality"]
    channels = parameters.get("channels")
    require(isinstance(channels, list) and 1 <= len(channels) <= 3 and len(set(channels)) == len(channels) and set(channels) <= {"face", "pose", "hands"}, "Choose saved geometry channels.")
    origin = decimal_text(parameters["source_pts_origin_s"])
    gap = Decimal(str(parameters["max_support_gap_s"])); require(Decimal(".001") <= gap <= 10, "Invalid saved support gap.")
    expected = integer(quality["analysed_frames"], 2, MAX_FRAMES); source_frames = integer(quality["source_frames"], expected, MAX_FRAMES)
    target.parent.mkdir(parents=True, exist_ok=True)
    temporary = target.with_name(target.name + ".building")
    require(not temporary.exists(), "An unfinished index already owns this build path.")
    con = None; success = False
    try:
        con = sqlite3.connect(temporary)
        con.execute("PRAGMA page_size=4096"); con.execute(f"PRAGMA max_page_count={MAX_INDEX // 4096}")
        con.execute("PRAGMA journal_mode=OFF"); con.execute("PRAGMA synchronous=OFF"); con.execute("PRAGMA cache_size=-8192"); con.execute("PRAGMA temp_store=FILE")
        con.executescript("CREATE TABLE metadata(key TEXT PRIMARY KEY,value TEXT NOT NULL) WITHOUT ROWID; CREATE TABLE frames(ordinal INTEGER PRIMARY KEY,frame_index INTEGER UNIQUE NOT NULL,source_pts_text TEXT NOT NULL,time_text TEXT NOT NULL,relative_exact_text TEXT NOT NULL,time_value REAL NOT NULL,model_timestamp_ms INTEGER NOT NULL,source_offset INTEGER NOT NULL,source_bytes INTEGER NOT NULL,row_sha256 TEXT NOT NULL,states_json TEXT NOT NULL); CREATE TABLE metric_values(metric TEXT NOT NULL,ordinal INTEGER NOT NULL,value_text TEXT NOT NULL,PRIMARY KEY(metric,ordinal)) WITHOUT ROWID;")
        names = set(); counts = {c: {"valid_frames": 0, "states": {}} for c in channels}
        previous_index = -1; previous_pts = None; previous_ms = -1; observed = 0; offset = 0; hashed = hashlib.sha256()
        with source.open("rb") as stream:
            while True:
                raw = stream.readline(MAX_LINE + 1)
                if not raw: break
                require(len(raw) <= MAX_LINE and raw.endswith(b"\n"), "Observation line exceeds 1 MiB or lacks its final newline.")
                hashed.update(raw); row = loads(raw, tokens=True)
                fields(row, ("frame_index", "source_pts_s", "time_s", "model_timestamp_ms", *channels))
                index = integer(row["frame_index"], 0, source_frames - 1); pts = decimal_text(row["source_pts_s"])
                stamp = number(row["time_s"]); milliseconds = integer(row["model_timestamp_ms"], 0, 600000)
                relative = difference(pts, origin)
                require(index > previous_index and (previous_pts is None or pts > previous_pts) and milliseconds > previous_ms, "Frame index/PTS/model time must increase strictly.")
                require(0 <= relative <= 600 and float(stamp) == float(relative) and milliseconds == int(relative * 1000), "Saved source PTS, relative time and model time disagree.")
                require(Decimal(str(parameters["start_s"])) <= stamp <= Decimal(str(parameters["end_s"])), "Frame leaves the saved analysed interval.")
                metrics, states = observations(row, channels); names.update(metrics)
                require(len(names) <= MAX_METRICS, "More than 128 saved metric channels; use a supported report.")
                con.execute("INSERT INTO frames VALUES(?,?,?,?,?,?,?,?,?,?,?)", (observed, index, row["source_pts_s"], str(row["time_s"]), str(relative), float(relative), milliseconds, offset, len(raw), sha(raw), encoded(states).decode()))
                con.executemany("INSERT INTO metric_values VALUES(?,?,?)", ((name, observed, token) for name, token in metrics.items()))
                for channel, state in states.items():
                    counts[channel]["valid_frames"] += int(state["valid"])
                    bucket = counts[channel]["states"]; bucket[state["state"]] = bucket.get(state["state"], 0) + 1
                observed += 1; offset += len(raw); previous_index, previous_pts, previous_ms = index, pts, milliseconds
                require(observed <= expected and offset <= MAX_SOURCE, "Complete observation count/size exceeds its saved declaration.")
                if observed % 128 == 0: con.commit()
        require(offset == request["artifact"]["bytes"] and hashed.hexdigest() == request["artifact"]["sha256"], "Complete observation artifact failed its byte/hash check.")
        require(observed == expected, "Complete analysed frame count differs from the saved report.")
        for channel in channels:
            saved = quality["channels"][channel]
            require(saved["valid_frames"] == counts[channel]["valid_frames"] and saved["states"] == counts[channel]["states"], "Complete saved channel counts/states differ from the report.")
        metrics = [dict(metric_descriptor(name), valid_frames=con.execute("SELECT count(*) FROM metric_values WHERE metric=?", (name,)).fetchone()[0]) for name in sorted(names)]
        manifest = {"schema": SCHEMA, "recipe": RECIPE, "binding_json": binding_json, "binding_sha256": request["binding_sha256"],
                    "artifact": request["artifact"], "parameters": parameters, "engine": request["engine"], "frames": observed, "channels": counts, "metrics": metrics,
                    "limits": {"index_bytes": MAX_INDEX, "source_bytes": MAX_SOURCE, "line_bytes": MAX_LINE, "metrics": MAX_METRICS, "page_rows": MAX_PAGE, "response_bytes": MAX_RESPONSE, "display_points": MAX_POINTS},
                    "number_encoding": "original_json_number_tokens", "landmarks": "verified_original_artifact_line"}
        con.execute("INSERT INTO metadata VALUES('manifest',?)", (encoded(manifest).decode(),)); con.commit()
        require(con.execute("PRAGMA integrity_check").fetchone()[0] == "ok", "Built index failed SQLite integrity.")
        con.close(); con = None
        require(temporary.stat().st_size <= MAX_INDEX, "Index exceeds 256 MiB; use a shorter analysed interval.")
        temporary.replace(target); success = True
        return {"schema": "brohn-vision-index-result/1.0", "status": "complete", "manifest": manifest,
                "index": {"path": str(target.resolve()), **descriptor(target), "schema": SCHEMA, "manifest_sha256": sha(encoded(manifest)), "media_type": "application/vnd.sqlite3"}}
    except sqlite3.OperationalError as error:
        raise InputError("Index storage failed or exceeded 256 MiB; use a shorter analysed interval: " + str(error)) from error
    finally:
        if con is not None: con.close()
        if not success and temporary.exists(): temporary.unlink()


@contextmanager
def opened(request):
    path = Path(request["index_path"]); reference = request["index"]
    check_file(path, reference, MAX_INDEX)
    # Only the trusted domain supplies this flag after complete background
    # verification while retaining native handles that deny mutation. It is
    # never accepted from a browser selection. Standalone reads verify fully.
    guarded = request.get("guarded_verified") is True
    if not guarded: require(digest(path) == reference["sha256"], "Immutable index bytes changed.")
    con = sqlite3.connect(path.resolve().as_uri() + "?mode=ro&immutable=1", uri=True)
    try:
        con.execute("PRAGMA query_only=ON"); con.execute("PRAGMA trusted_schema=OFF"); con.execute("PRAGMA cache_size=-4096")
        if not guarded: require(con.execute("PRAGMA quick_check").fetchone()[0] == "ok", "Saved index is corrupt.")
        found = con.execute("SELECT value FROM metadata WHERE key='manifest'").fetchone()
        require(found is not None and len(found[0].encode()) <= MAX_RESPONSE, "Missing bounded index manifest.")
        manifest = loads(found[0]); require(manifest["schema"] == SCHEMA and manifest["recipe"] == RECIPE and sha(encoded(manifest)) == reference["manifest_sha256"], "Index schema/manifest changed.")
        require(manifest["binding_sha256"] == request["binding_sha256"] and sha(manifest["binding_json"].encode()) == request["binding_sha256"], "Index belongs to another source.")
        if not guarded: require(con.execute("SELECT count(*) FROM frames").fetchone()[0] == manifest["frames"], "Index frame count changed.")
        yield con, manifest
    finally: con.close()


def selection(request, manifest):
    metric = request.get("metric")
    require(metric is None or metric in {x["id"] for x in manifest["metrics"]}, "Choose a saved metric in this source.")
    bounds = request.get("range")
    require(bounds is None or isinstance(bounds, list) and len(bounds) == 2, "Choose two exact recording-relative bounds.")
    if bounds is not None:
        bounds = [decimal_text(x) for x in bounds]; require(bounds[0] <= bounds[1], "Range bounds are reversed.")
    return metric, bounds
def rows(con, metric, bounds):
    for row in con.execute("SELECT f.*,v.value_text FROM frames f LEFT JOIN metric_values v ON v.ordinal=f.ordinal AND v.metric=? ORDER BY f.ordinal", (metric,)):
        if bounds is None or bounds[0] <= Decimal(row[4]) <= bounds[1]: yield row
def row_value(row):
    return {"ordinal": row[0], "frame_index": row[1], "source_pts_s": row[2], "time_s_text": row[3], "relative_exact_text": row[4],
            "model_timestamp_ms": row[6], "states": loads(row[10]), "value_text": row[11]}
def query_identity(request): return sha(encoded({key: request.get(key) for key in ("binding_sha256", "index", "metric", "range")}))
def page(request):
    limit = integer(request.get("limit", MAX_PAGE), 1, MAX_PAGE); after = -1; identity = query_identity(request)
    if request.get("cursor"):
        require(type(request["cursor"]) is str and len(request["cursor"]) <= 2048, "Page cursor exceeds its bound.")
        try: cursor = loads(base64.urlsafe_b64decode(request["cursor"]))
        except Exception as error: raise InputError("Invalid page cursor.") from error
        require(cursor.get("query") == identity, "Page cursor belongs to another exact source or selection.")
        after = integer(cursor.get("after"), 0, MAX_FRAMES - 1)
    with opened(request) as (con, manifest):
        metric, bounds = selection(request, manifest); result = []; total = 0; more = False
        for row in rows(con, metric, bounds):
            total += 1
            if row[0] <= after: continue
            if len(result) < limit: result.append(row_value(row))
            else: more = True
        next_cursor = base64.urlsafe_b64encode(encoded({"query": identity, "after": result[-1]["ordinal"]})).decode() if more else None
        return bound_response({"schema": "brohn-vision-frame-page/1.0", "binding_sha256": request["binding_sha256"], "metric": metric,
                               "rows": result, "returned": len(result), "total": total, "next_cursor": next_cursor, "number_encoding": "original_json_number_tokens"})


def detail(request):
    index = integer(request["frame_index"], 0, MAX_FRAMES - 1)
    with opened(request) as (con, manifest):
        row = con.execute("SELECT *,NULL FROM frames WHERE frame_index=?", (index,)).fetchone(); require(row is not None, "Frame was not analysed in this report.")
        source = Path(request["artifact_path"]); check_file(source, manifest["artifact"], MAX_SOURCE)
        # Caller holds the original artifact native guard and has verified its
        # full hash. The index's immutable offset/length/hash binds this read.
        with source.open("rb") as stream: stream.seek(row[7]); raw = stream.read(row[8])
        require(len(raw) == row[8] and sha(raw) == row[9], "Selected original observation line changed.")
        observed = loads(raw, tokens=True); observations(observed, manifest["parameters"]["channels"])
        require(int(observed["frame_index"]) == index and observed["source_pts_s"] == row[2], "Selected line belongs to another frame/PTS.")
        return bound_response({"schema": "brohn-vision-frame-detail/1.0", "binding_sha256": request["binding_sha256"], "frame": row_value(row),
            "observation": observed, "original_json": raw.decode("utf-8"), "number_encoding": "JSON numbers in observation are their exact original token strings; original_json retains original JSON types",
            "parameters": manifest["parameters"], "engine": manifest["engine"]})


def numeric_point(row):
    return {"frame_index": row[1], "ordinal": row[0], "source_pts_s": row[2], "time_s_text": row[3],
            "relative_exact_text": row[4], "value_text": row[11], "x": float(Decimal(row[4])), "y": float(Decimal(row[11]))}


def plot(request):
    maximum = integer(request.get("max_points", MAX_POINTS), 4, MAX_POINTS)
    with opened(request) as (con, manifest):
        metric, bounds = selection(request, manifest); channel = request.get("channel")
        require(channel in manifest["channels"] and (metric is None or metric.startswith(channel + ".")), "Choose the channel belonging to this saved metric.")
        gap = Decimal(str(manifest["parameters"]["max_support_gap_s"])); previous = None; sizes = []; total = 0; valid = 0; seconds = Decimal(0)
        first_time = last_time = None; state_counts = {}; family_valid = 0
        # Pass one counts complete support and independent fragments, not pixels.
        for row in rows(con, metric, bounds):
            total += 1; stamp = Decimal(row[4]); last_time = stamp
            if first_time is None: first_time = stamp
            state = loads(row[10])[channel]; state_counts[state["state"]] = state_counts.get(state["state"], 0) + 1; family_valid += state["valid"]
            if row[11] is None:
                previous = None; continue
            valid += 1
            contiguous = previous is not None and row[0] == previous[0] + 1 and row[1] == previous[1] + 1 and 0 < difference(stamp, Decimal(previous[4])) <= gap
            if contiguous:
                sizes[-1] += 1; seconds += difference(stamp, Decimal(previous[4]))
            else:
                sizes.append(1)
                require(sum(min(4, count) for count in sizes) <= maximum, "Separate valid fragments exceed the display budget; choose a narrower interval.")
            previous = row
        require(sum(min(4, count) for count in sizes) <= maximum, "Separate valid fragments exceed the display budget; choose a narrower interval.")
        per_fragment = max(1, maximum // max(1, 4 * len(sizes)))
        widths = [max(1, math.ceil(count / per_fragment)) for count in sizes]
        fragments = []; previous = None; fragment = -1; position = 0; bucket = []
        state_bins = {}; timeline_bins = 128
        def flush():
            nonlocal bucket
            if bucket:
                candidates = {row[0]: row for row in (bucket[0], min(bucket,key=lambda r:Decimal(r[11])), max(bucket,key=lambda r:Decimal(r[11])), bucket[-1])}
                fragments[-1]["points"].extend(numeric_point(candidates[key]) for key in sorted(candidates)); bucket = []
        # Each reduction bucket itself retains only first/min/max/last, bounded
        # independently of source cadence or the complete number of rows.
        for row in rows(con, metric, bounds):
            stamp = Decimal(row[4]); state = loads(row[10])[channel]
            bin_id = 0 if first_time == last_time else min(timeline_bins-1, int((stamp-first_time)/(last_time-first_time)*timeline_bins))
            item = state_bins.setdefault(bin_id,{"first_time_text":str(stamp),"last_time_text":str(stamp),"frames":0,"valid_frames":0,"states":{}})
            item["last_time_text"] = str(stamp); item["frames"] += 1; item["valid_frames"] += state["valid"]; item["states"][state["state"]] = item["states"].get(state["state"],0)+1
            if row[11] is None:
                flush(); previous = None; continue
            contiguous = previous is not None and row[0] == previous[0] + 1 and row[1] == previous[1] + 1 and 0 < difference(stamp, Decimal(previous[4])) <= gap
            if not contiguous:
                flush(); fragment += 1; position = 0; fragments.append({"complete_points":sizes[fragment],"first_frame":row[1],"last_frame":row[1],"points":[]})
            if position and position % widths[fragment] == 0: flush()
            if not bucket: bucket = [row]
            else:
                candidates = [bucket[0],min([*bucket,row],key=lambda r:Decimal(r[11])),max([*bucket,row],key=lambda r:Decimal(r[11])),row]
                bucket = [dict((r[0],r) for r in candidates)[key] for key in sorted({r[0] for r in candidates})]
            fragments[-1]["last_frame"] = row[1]; position += 1; previous = row
        flush(); displayed = sum(len(f["points"]) for f in fragments)
        require(displayed <= maximum, "Display point budget exceeded; choose a narrower interval.")
        return bound_response({"schema":"brohn-vision-plot/1.0","binding_sha256":request["binding_sha256"],"status":"completed" if total else "empty_range",
            "channel":channel,"metric":None if metric is None else metric_descriptor(metric),"range":request.get("range"),"fragments":fragments,
            "states":[state_bins[key] for key in sorted(state_bins)],"support":{"frames":total,"channel_valid_frames":family_valid,"metric_valid_frames":valid,
                "metric_valid_time_s_text":str(seconds),"state_counts":state_counts,"displayed_points":displayed,"fragment_count":len(fragments)},
            "sampling":"Chronological first/min/max/last within each contiguous valid fragment; no interpolation across absent values, skipped frames or saved support gaps.",
            "time_support_policy":manifest["parameters"].get("time_support_policy","Adjacent valid metric endpoint pairs within saved support gap; no last-frame extrapolation.")})


def export_csv(request):
    target = Path(request["output_path"]); require(not target.exists(), "Choose a new owned numeric export path.")
    count = 0; success = False
    try:
        with opened(request) as (con, manifest):
            metric, bounds = selection(request, manifest)
            require(metric is not None, "Choose one exact saved metric for numeric export.")
            with target.open("x", encoding="utf-8", newline="") as stream:
                writer = csv.writer(stream); writer.writerow(["frame_index","source_pts_s","recording_relative_s_exact","saved_time_s","model_timestamp_ms","metric","value","states_json"])
                for row in rows(con,metric,bounds):
                    writer.writerow([row[1],row[2],row[4],row[3],row[6],metric,"" if row[11] is None else row[11],row[10]]); count += 1
                    require(stream.tell() <= MAX_INDEX, "Selected numeric export exceeds 256 MiB; choose a narrower interval.")
        success = True
        return {"schema":"brohn-vision-numeric-export/1.0","binding_sha256":request["binding_sha256"],"metric":metric,"range":request.get("range"),
                "rows":count,"path":str(target.resolve()),**descriptor(target),"number_encoding":"original_json_number_tokens; recording_relative_s_exact is decimal source PTS minus declared origin", "missing_value":"empty cell, never zero"}
    finally:
        if not success and target.exists(): target.unlink()


def main():
    parser = argparse.ArgumentParser(); parser.add_argument("--request", required=True); parser.add_argument("--output", required=True); args = parser.parse_args()
    try:
        raw = Path(args.request).read_bytes(); require(len(raw) <= MAX_RESPONSE, "Request exceeds 2 MiB."); request = loads(raw)
        require(request.get("schema") == "brohn-vision-explorer-request/1.0", "Unsupported explorer request.")
        operation = request.get("operation"); require(operation in {"build", "page", "detail", "catalog", "plot", "export_csv"}, "Unsupported explorer operation.")
        if operation == "catalog":
            with opened(request) as (_, manifest): result = bound_response({"schema": "brohn-vision-catalog/1.0", "manifest": manifest})
        else: result = {"build": build, "page": page, "detail": detail,"plot":plot,"export_csv":export_csv}[operation](request)
        Path(args.output).write_bytes(encoded(result))
    except Exception as error:
        Path(args.output).write_bytes(encoded({"schema": "brohn-vision-explorer-error/1.0", "status": "error", "error": {"type": type(error).__name__, "message": str(error)}})); return 1
    return 0


if __name__ == "__main__": sys.exit(main())
