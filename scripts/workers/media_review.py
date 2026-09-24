"""Container-clock video/audio review. No inferred external clock or scoring."""
from __future__ import annotations
import argparse
import csv
from fractions import Fraction
import json
from pathlib import Path
import re
import sys
import audio_extract as media

PROFILE = "saved-container-media-review/1.0"
MAX_FRAMES = 36_000
MAX_LEDGER = 16 * 1024**2
MAX_METADATA = 64 * 1024**2
require, sha = media.require, media.sha


def integer(value, low, high, label):
    require(type(value) is int and low <= value <= high, f"{label} is outside the supported integer range.")
    return value


def ticks(value, label):
    if isinstance(value, str) and re.fullmatch(r"-?[0-9]{1,20}", value):
        value = int(value)
    return integer(value, -(2**63-1), 2**63-1, label)


def rational(value):
    require(isinstance(value, str) and re.fullmatch(r"[0-9]{1,12}/[0-9]{1,12}", value), "Missing original rational time base.")
    q = Fraction(value)
    require(q > 0, "Nonpositive original time base.")
    return q


def exact(value):
    return {"numerator": str(value.numerator), "denominator": str(value.denominator), "display_s": format(float(value), ".17g")}


def file_ref(path, reference, maximum):
    p = Path(path).resolve(strict=True)
    require(p.is_file() and type(reference) is dict and set(reference) == {"hash", "size"}, "Choose a retained exact source artifact.")
    require(type(reference["size"]) is int and 0 < reference["size"] <= maximum and p.stat().st_size == reference["size"] and sha(p) == reference["hash"], "Retained media bytes changed or exceed this reader's limit.")
    return p


def video_track(raw):
    index = integer(raw.get("index"), 0, 63, "Video stream")
    width, height = integer(raw.get("width"), 1, 3840*2160, "Video width"), integer(raw.get("height"), 1, 3840*2160, "Video height")
    require(width * height <= 3840 * 2160, "Video dimensions exceed the exact-frame limit.")
    rational(raw.get("time_base"))
    require(isinstance(raw.get("codec_name"), str) and re.fullmatch(r"[A-Za-z0-9_]{1,64}", raw["codec_name"]), "Video codec is unavailable.")
    return {"stream_index":index,"codec":raw["codec_name"],"width":width,"height":height,"time_base":raw["time_base"],
            "attached_picture":bool(raw.get("disposition", {}).get("attached_pic", 0)),"orientation":"encoded pixels, no autorotation"}


def audio_mapping(path, recording, sample):
    rate = integer(recording.get("sampling_rate"), 1000, 384000, "Original sampling rate")
    total = integer(recording.get("samples_per_channel"), 1, 20_000_000, "Original audio samples")
    integer(sample, 0, total-1, "Audio cursor sample")
    q = rational(recording.get("time_base")); origin = ticks(recording.get("source_start_pts_ticks"), "Original audio start PTS") * q
    tolerance = q + Fraction(1, rate)
    require(recording.get("clock_status") == "consistent_within_container_precision" and recording.get("gap_filling") == "none" and recording.get("resampling") == "none", "A preserved continuous audio extraction ledger is required.")
    expected_columns = {"decoder_frame_index","pts_ticks","time_base","pts_time_s","start_sample","end_sample_exclusive","samples","sample_clock_time_s","pts_minus_sample_clock_s"}
    cursor, previous, selected, count, worst = 0, None, None, 0, Fraction(0)
    with Path(path).open(newline="", encoding="utf-8") as file:
        reader = csv.DictReader(file)
        require(set(reader.fieldnames or []) == expected_columns, "Original audio frame ledger has unsupported columns.")
        for row in reader:
            require(count < 500_000, "Original audio frame ledger exceeds this reader's bound.")
            values = {}
            for key in ("decoder_frame_index","start_sample","end_sample_exclusive","samples"):
                require(re.fullmatch(r"[0-9]{1,12}", row[key]) is not None, "Audio frame ledger contains a noninteger sample boundary.")
                values[key] = int(row[key])
            require(values["decoder_frame_index"] == count and values["start_sample"] == cursor and values["samples"] > 0 and values["end_sample_exclusive"] == cursor+values["samples"] and values["end_sample_exclusive"] <= total, "Audio ledger is incomplete, overlapping or reordered.")
            require(row["time_base"] == recording["time_base"], "Audio frame time base changed.")
            stamp = ticks(row["pts_ticks"], "Audio frame PTS") * q
            require(previous is None or stamp > previous, "Audio frame timestamps reset or overlap.")
            nominal = origin + Fraction(cursor, rate); residual = stamp-nominal
            require(abs(residual) <= tolerance, "Audio ledger crosses a gap or drift beyond its declared precision.")
            for key, value in (("pts_time_s",stamp),("sample_clock_time_s",nominal),("pts_minus_sample_clock_s",residual)):
                require(row[key] == format(float(value), ".17g"), "Audio ledger display value disagrees with its exact integer PTS/sample authority.")
            if count == 0:require(stamp == origin, "Audio ledger sample zero differs from the original extraction.")
            if cursor <= sample < values["end_sample_exclusive"]:
                selected = {"decoder_frame_index":count,"pts_ticks":row["pts_ticks"],"start_sample":cursor,"end_sample_exclusive":values["end_sample_exclusive"],
                            "sample_offset":sample-cursor,"container_time":exact(stamp+Fraction(sample-cursor,rate)),"pts_residual":exact(residual)}
            worst = max(worst, abs(residual));cursor=values["end_sample_exclusive"];previous=stamp;count+=1
    require(cursor == total and count == recording.get("frame_count") and selected is not None, "Complete original audio ledger coverage is required.")
    require(recording.get("maximum_pts_residual_s") == format(float(worst), ".17g") and recording.get("pts_consistency_tolerance_s") == format(float(tolerance), ".17g"), "Audio ledger precision differs from its extraction receipt.")
    return {"policy":"original-audio-frame-pts-plus-local-sample/1.0","selected_sample":sample,"sampling_rate":rate,
            "audio_time_base":recording["time_base"],"audio_origin_pts_ticks":recording["source_start_pts_ticks"],"audio_frame":selected,
            "nominal_container_time":exact(origin+Fraction(sample,rate)),"timestamp_consistency_bound":exact(tolerance),
            "maximum_audio_pts_residual":exact(worst),"physical_synchronization":"not_established"}


def video_ledger(frames, track, mapping):
    require(isinstance(frames,list) and 1 <= len(frames) <= MAX_FRAMES,"Video frame inventory exceeds the complete reader's bound.")
    q=rational(track["time_base"]);aq=rational(mapping["audio_time_base"]);origin=ticks(mapping["audio_origin_pts_ticks"],"Audio origin")*aq
    position=mapping["audio_frame"]["container_time"];cursor=Fraction(int(position["numerator"]),int(position["denominator"]))
    rows=[];intervals=[];issues=[];previous=None;missing=0
    for i,f in enumerate(frames):
        require(f.get("media_type")=="video" and f.get("stream_index")==track["stream_index"] and f.get("width")==track["width"] and f.get("height")==track["height"],"Video frame changed stream identity or pixel dimensions.")
        pts=None if f.get("pts") is None else ticks(f["pts"],"Video PTS")
        stamp=None if pts is None else pts*q
        if stamp is None:missing+=1
        elif previous is not None and stamp<=previous:issues.append("duplicate_or_reversed_video_pts")
        if stamp is not None:previous=stamp
        supplied=[(k,ticks(f[k],"Video duration")) for k in ("duration","pkt_duration") if f.get(k) is not None]
        require(all(v>=0 for _,v in supplied),"Video frame has negative duration.")
        if len(supplied)==2:require(supplied[0][1]==supplied[1][1],"Video frame duration fields disagree.")
        duration=supplied[0][1] if supplied and supplied[0][1]>0 else None
        end=None if stamp is None or duration is None else stamp+duration*q
        relative=None if stamp is None else stamp-origin
        rows.append({"frame_index":i,"pts_ticks":None if pts is None else str(pts),"time_base":track["time_base"],
                     "pts_numerator":None if stamp is None else str(stamp.numerator),"pts_denominator":None if stamp is None else str(stamp.denominator),
                     "pts_s":None if stamp is None else format(float(stamp),".17g"),"duration_ticks":None if duration is None else str(duration),
                     "duration_field":"|".join(k for k,_ in supplied) or "not_supplied","duration_status":"declared" if duration is not None else "unknown",
                     "end_s":None if end is None else format(float(end),".17g"),"nominal_audio_time_s":None if relative is None else format(float(relative),".17g"),
                     "gap_to_next_s":None,"interval_relation_to_next":"last_frame"})
        intervals.append((stamp,end))
    if missing:issues.append("missing_video_pts")
    gaps=overlaps=unknown=0
    for i,(start,end) in enumerate(intervals):
        if end is None:unknown+=1
        if i+1==len(intervals):continue
        nxt=intervals[i+1][0]
        if end is None or nxt is None:rows[i]["interval_relation_to_next"]="unknown"
        else:
            delta=nxt-end;rows[i]["gap_to_next_s"]=format(float(delta),".17g")
            rows[i]["interval_relation_to_next"]="gap" if delta>0 else "overlap" if delta<0 else "adjacent"
            gaps+=delta>0;overlaps+=delta<0
    matches=[i for i,(start,end) in enumerate(intervals) if start is not None and (start<=cursor<end if end is not None else start==cursor)]
    status="ambiguous_clock" if issues else "overlapping_frames" if len(matches)>1 else "available" if len(matches)==1 else "no_supported_frame"
    chosen=matches[0] if status=="available" else None
    selected=None if chosen is None else dict(rows[chosen])
    if selected is not None:
        start,end=intervals[chosen];distance=min(cursor-start,end-cursor) if end is not None else Fraction(0)
        bound=Fraction(int(mapping["timestamp_consistency_bound"]["numerator"]),int(mapping["timestamp_consistency_bound"]["denominator"]))+q
        selected["cursor_from_pts"]=exact(cursor-start);selected["precision_crosses_frame_boundary"]=distance<=bound
    return rows,{"status":status,"frame":selected,"frame_count":len(rows),"missing_pts":missing,"unknown_duration_frames":unknown,
                 "gaps":gaps,"overlapping_intervals":overlaps,"issues":sorted(set(issues)),"video_time_quantum":exact(q),
                 "policy":"declared_duration_half_open_or_exact_pts_only_no_nominal_fps_fill"}


def analyse(request):
    require(type(request) is dict and set(request)=={"schema","operation","binding","source_path","source","audio_ledger_path","audio_ledger","recording","selection","output_directory"},"Media review request fields are invalid.")
    require(request["schema"]=="brohn-media-review-request/1.0" and request["operation"] in {"media_tracks","media_review"} and type(request["binding"]) is dict,"Unsupported saved media review request.")
    source=file_ref(request["source_path"],request["source"],512*1024**2)
    ledger=file_ref(request["audio_ledger_path"],request["audio_ledger"],96*1024**2)
    directory=Path(request["output_directory"]).resolve();require(not directory.exists(),"Choose a new owned media-review directory.");directory.mkdir()
    probe,probe_identity=media.executable("ffprobe",directory)
    prefix=[probe,"-v","error","-protocol_whitelist","file,pipe","-format_whitelist",media.FORMATS]
    inventory=directory/"streams.json"
    media.run_file(prefix+["-show_streams","-show_entries","stream=index,codec_type,codec_name,width,height,time_base:stream_disposition=attached_pic:stream_tags=","-of","json",str(source)],inventory,1024**2)
    streams=media.read_json(inventory).get("streams",[]);require(isinstance(streams,list) and 1<=len(streams)<=64,"Container stream inventory exceeds its bound.")
    tracks=[video_track(s) for s in streams if s.get("codec_type")=="video"]
    result={"schema":"brohn-media-review-result/1.0","profile":PROFILE,"operation":request["operation"],"binding":request["binding"],"source":request["source"],
            "audio_ledger":request["audio_ledger"],"tracks":tracks,"selection":request["selection"],"mapping":None,"coverage":None,"rows":[],"artifacts":[],"engine":{"ffprobe":probe_identity},
            "limitations":["Container presentation timestamps do not establish physical synchronization or relate unrelated sensor clocks.","Encoded orientation is preserved; no autorotation, resampling or inferred frames.","Unknown frame duration supports its exact PTS only; gaps are never filled using nominal frame rate."]}
    if request["operation"]=="media_tracks":require(request["selection"] is None,"Inventory does not silently choose a video stream.")
    else:
        selection=request["selection"];require(type(selection) is dict and set(selection)=={"video_stream_index","cursor_sample"},"Choose an exact video stream and audio sample cursor.")
        integer(selection["video_stream_index"],0,63,"Selected video stream")
        chosen=[t for t in tracks if t["stream_index"]==selection["video_stream_index"]];require(len(chosen)==1 and not chosen[0]["attached_picture"],"Choose an actual video track, not a cover image.");track=chosen[0]
        mapping=audio_mapping(ledger,request["recording"],selection["cursor_sample"])
        frames_path=directory/"frames.json"
        media.run_file(prefix+["-select_streams",str(track["stream_index"]),"-show_frames","-show_entries","frame=media_type,stream_index,pts,duration,pkt_duration,width,height","-of","json",str(source)],frames_path,MAX_METADATA)
        rows,coverage=video_ledger(media.read_json(frames_path).get("frames"),track,mapping)
        csv_path=directory/"video-frames.csv"
        with csv_path.open("x",encoding="utf-8",newline="") as file:
            writer=csv.DictWriter(file,fieldnames=list(rows[0]));writer.writeheader();writer.writerows(rows)
        require(csv_path.stat().st_size<=MAX_LEDGER,"Complete video frame ledger exceeds its bound.")
        result.update(mapping=mapping,coverage=coverage,rows=rows[:100]);result["artifacts"].append({"kind":"video-frame-ledger","path":"video-frames.csv","hash":sha(csv_path),"size":csv_path.stat().st_size,"media_type":"text/csv","rows":len(rows)})
        if coverage["frame"] is not None:
            decoder,decoder_identity=media.executable("ffmpeg",directory);result["engine"]["ffmpeg"]=decoder_identity
            import media_pixels
            picture=media_pixels.extract_frame(source_path=str(source),source_sha256=request["source"]["hash"],source_bytes=request["source"]["size"],
                    stream_index=track["stream_index"],width=track["width"],height=track["height"],frame_index=coverage["frame"]["frame_index"],ffmpeg_path=decoder,output_directory=str(directory))
            image=picture["image"]
            image_path=Path(image["path"]).resolve();require(image_path.parent==directory,"Recorded frame left the owned artifact directory.")
            picture["image"]={"path":image_path.name,"hash":image["sha256"],"size":image["bytes"],"media_type":image["media_type"],"width":image["width"],"height":image["height"]}
            result["frame_extraction"]=picture
            result["artifacts"].append(dict(picture["image"],kind="recorded-video-frame"))
    require(sha(source)==request["source"]["hash"] and sha(ledger)==request["audio_ledger"]["hash"] and sha(probe)==probe_identity["sha256"],"Media source, ledger or probe changed during review.")
    if "ffmpeg" in result["engine"]:require(sha(decoder)==result["engine"]["ffmpeg"]["sha256"],"Media decoder changed during review.")
    return result


def main():
    parser=argparse.ArgumentParser();parser.add_argument("--request",required=True);parser.add_argument("--output",required=True);args=parser.parse_args()
    try:result=analyse(media.read_json(args.request));code=0
    except Exception as error:result={"schema":"brohn-media-review-result/1.0","status":"error","error":{"type":type(error).__name__,"message":str(error)}};code=1
    Path(args.output).write_text(json.dumps(result,allow_nan=False,separators=(",",":")),encoding="utf-8");return code


if __name__=="__main__":sys.exit(main())
