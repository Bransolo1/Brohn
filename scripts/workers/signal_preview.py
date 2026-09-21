"""Verified table catalog and extrema-preserving views of processed physiology."""
from __future__ import annotations

import argparse
import copy
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path
import sys
import tempfile

_spec=importlib.util.spec_from_file_location("brohn_signal_artifacts",Path(__file__).with_name("physiology_artifacts.py"))
artifacts=importlib.util.module_from_spec(_spec);_spec.loader.exec_module(artifacts)
InputError=artifacts.ArtifactError
require=artifacts.require
MAX_TABLES=50
MAX_FRAGMENTS=2000
MAX_ENVELOPE_BINS=10000
MAX_CARDIAC_MARKERS=2000


def finite(value): return isinstance(value,(int,float)) and not isinstance(value,bool) and math.isfinite(value)
def integer(value,low,high): return isinstance(value,int) and not isinstance(value,bool) and low<=value<=high


def minmax(pair,value):
    if not finite(value): return pair
    return [value,value] if pair is None else [min(pair[0],value),max(pair[1],value)]


def bind_receipt(request):
    manifest=request.get("artifact");receipt=request.get("verification_receipt")
    require(isinstance(manifest,dict) and manifest.get("kind") in artifacts.KINDS,"Select one complete processed physiology artifact.")
    require(isinstance(receipt,dict) and receipt.get("schema")=="brohn-physiology-artifact-receipt/1.0" and receipt.get("status")=="verified" and isinstance(receipt.get("artifacts"),list),"The immutable artifact needs its original typed verification receipt.")
    matches=[item for item in receipt["artifacts"] if item.get("kind")==manifest["kind"]]
    require(len(matches)==1 and matches[0].get("verified") is True,"No unique verification receipt matches the selected artifact.")
    for field in ("kind","sha256","bytes","schema","tables","rows","provenance_sha256"):
        require(field in manifest and field in matches[0] and type(manifest[field]) is type(matches[0][field]) and manifest[field]==matches[0][field],"Artifact metadata differs from its original verified receipt.")
    return manifest


def numeric_fields(table):
    return [c for c in table["columns"] if c["type"] in {"float64","integer"} and c["role"] not in {"coordinate","index","support","label"}]


def coordinate(table):
    choices=[c for c in table["columns"] if c["role"]=="coordinate" and c["type"] in {"float64","integer"}]
    require(len(choices)==1,"A plotted table must declare exactly one numeric coordinate column.")
    c=choices[0];axis=table["coordinates"]["axis"]
    require((axis in {"time","event"} and c["unit"]=="s") or (axis=="frequency" and c["unit"]=="Hz"),"Plot axis and coordinate unit disagree; no time/frequency relabelling is allowed.")
    return c


def descriptor(table):
    c=coordinate(table)
    return {"table_id":table["table_id"],"identity":table["identity"],"coordinates":table["coordinates"],
            "coordinate_column":c,"value_columns":numeric_fields(table),"rows":table["expected_rows"],
            "support":table["support"],"coordinate_range":None,"observed_coordinate_rows":0}


def source_of(table): return table["support"].get("source",{})


def cadence(table):
    support=table["support"];source=source_of(table);rate=source.get("sampling_rate")
    if finite(rate) and rate>0:
        quality=source.get("channel_quality",{})
        tolerance=quality.get("timestamp_tolerance_s")
        return 1/rate,tolerance if finite(tolerance) and tolerance>=0 else 0
    rate=support.get("source_sampling_rate");hop=support.get("frame_hop_samples")
    if finite(rate) and rate>0 and finite(hop) and hop>0: return hop/rate,0
    return None,None


def blank_stats():
    return {"rows":0,"observed_coordinate_rows":0,"observed_value_rows":0,"eligible_value_rows":0,
            "excluded_retention_rows":0,"missing_value_rows":0,"missing_coordinate_rows":0,
            "coordinate_range":None,"observed_value_range":None,"eligible_value_range":None}


def sample(table,row,offset,value_column):
    names=[c["name"] for c in table["columns"]];coord=coordinate(table)
    x=row[names.index(coord["name"])];y=row[names.index(value_column)]
    retained=True
    if "retained" in names:
        column=table["columns"][names.index("retained")]
        require(column["type"]=="boolean" and column["role"]=="support","Retained support must be explicitly typed boolean.")
        retained=row[names.index("retained")] is True
    index=row[names.index("source_sample_index")] if "source_sample_index" in names else None
    return {"x":x,"y":y,"row_index":offset,"source_sample_index":index,"retained":retained}


def count(stats,point):
    stats["rows"]+=1
    x,y=point["x"],point["y"]
    if finite(x):
        stats["observed_coordinate_rows"]+=1;stats["coordinate_range"]=minmax(stats["coordinate_range"],x)
    else: stats["missing_coordinate_rows"]+=1
    if finite(y):
        stats["observed_value_rows"]+=1;stats["observed_value_range"]=minmax(stats["observed_value_range"],y)
    else: stats["missing_value_rows"]+=1
    if not point["retained"]: stats["excluded_retention_rows"]+=1
    if finite(x) and finite(y) and point["retained"]:
        stats["eligible_value_rows"]+=1;stats["eligible_value_range"]=minmax(stats["eligible_value_range"],y)


def catalog(request,manifest):
    page=request.get("page",{})
    require(isinstance(page,dict) and set(page)<={"offset","limit"},"Catalog pagination supports offset and limit.")
    offset,limit=page.get("offset",0),page.get("limit",100)
    require(integer(offset,0,10000) and integer(limit,1,200),"Catalog page needs offset 0..10000 and limit 1..200.")
    descriptors=[];selected={};table_counter=0
    def table(t):
        nonlocal table_counter
        if offset<=table_counter<offset+limit:
            d=descriptor(t)
            # The catalog returns support identities and method evidence, without
            # a full second copy of embedded source headers or per-row arrays.
            d["support"]={k:v for k,v in t["support"].items() if k not in {"parameters","method"}}
            descriptors.append(d);selected[t["table_id"]]=(t,d)
        table_counter+=1
    def rows(tid,start,values):
        if tid not in selected: return
        t,d=selected[tid];names=[c["name"] for c in t["columns"]];i=names.index(d["coordinate_column"]["name"])
        for row in values:
            x=row[i]
            if finite(x):
                d["coordinate_range"]=minmax(d["coordinate_range"],x);d["observed_coordinate_rows"]+=1
    artifacts.verify_artifact(manifest,on_table=table,on_rows=rows)
    return {"schema":"brohn-signal-catalog/1.0","status":"completed","tables":descriptors,
            "pagination":{"offset":offset,"limit":limit,"returned":len(descriptors),"total_tables":table_counter,
                          "next_offset":offset+len(descriptors) if descriptors and offset+len(descriptors)<table_counter else None}}


def preview(request,manifest):
    selection=request.get("selection");p=request.get("parameters",{})
    require(isinstance(selection,dict) and set(selection)=={"table_ids","recording_id","channel","value_column","range"},"Select exact table IDs, recording, channel, value column and an explicit range or null.")
    ids=selection["table_ids"]
    require(isinstance(ids,list) and 1<=len(ids)<=MAX_TABLES and all(artifacts.text(i,160) for i in ids) and len(set(ids))==len(ids),"Select 1 to 50 unique table IDs from the artifact catalog.")
    for field in ("recording_id","channel","value_column"): require(artifacts.text(selection[field],500),"Select explicit recording, channel and value identities.")
    bounds=selection["range"]
    require(bounds is None or (isinstance(bounds,list) and len(bounds)==2 and all(finite(v) for v in bounds) and bounds[0]<bounds[1]),"Range needs two increasing finite coordinates or explicit null for the full range.")
    require(isinstance(p,dict) and set(p)<={"max_bins"},"Only max_bins is configurable; views never change the scientific recipe.")
    max_bins=p.get("max_bins",800)
    require(integer(max_bins,1,2000) and max_bins>=len(ids),"Use 1 to 2,000 total bins, at least one per selected table.")
    chosen={};table_stats={};full=blank_stats();selected_stats=blank_stats();previous_coordinates={}
    def table(t):
        if t["table_id"] not in ids: return
        require(t["support"].get("trace_profile") != "gaze-pupil-source-trace/1.0", "Pupil/blink traces require the dedicated gaze adapter with separate source and interval masks. Exact source values remain available.")
        require(t["identity"]["recording_id"]==selection["recording_id"] and t["identity"]["channel"]==selection["channel"],"A selected table belongs to a different recording or channel.")
        require(selection["value_column"] in [c["name"] for c in numeric_fields(t)],"The selected column is not a declared numeric measure in every table.")
        descriptor(t);chosen[t["table_id"]]=t;table_stats[t["table_id"]]=blank_stats()
    def rows(tid,offset,values):
        if tid not in chosen: return
        t=chosen[tid]
        for i,row in enumerate(values):
            point=sample(t,row,offset+i,selection["value_column"])
            x=point["x"]
            if finite(x):
                previous=previous_coordinates.get(tid)
                require(previous is None or x>previous,"Coordinates must strictly increase within each table; resets need distinct tables.")
                previous_coordinates[tid]=x
            count(full,point);count(table_stats[tid],point)
            if bounds is None or (finite(x) and bounds[0]<=x<=bounds[1]): count(selected_stats,point)
    artifacts.verify_artifact(manifest,on_table=table,on_rows=rows)
    require(set(chosen)==set(ids),"One or more selected table IDs are absent; no automatic substitute was used.")
    tables=[chosen[tid] for tid in ids]
    signatures=[(t["coordinates"]["axis"],coordinate(t)["unit"],next(c["unit"] for c in t["columns"] if c["name"]==selection["value_column"])) for t in tables]
    require(len(set(signatures))==1,"Selected table axes or value units differ; request separate views.")
    # One recording ID alone cannot authorize joining a different clock origin.
    clocks=[(t["coordinates"]["source_time_origin"],t["coordinates"]["source_time_unit"],t["coordinates"]["reference"]) for t in tables]
    require(len(set(clocks))==1,"Selected tables use different declared clock origins/references; view them separately.")
    people=[tuple(t["identity"].get("group",{}).get(k) for k in ("participant_id","session_id","source_recording_id")) for t in tables]
    require(len(set(people))==1,"Selected tables belong to different person/session/reset identities; request separate views.")
    effective=bounds if bounds is not None else full["coordinate_range"]
    axis,x_unit,y_unit=signatures[0]
    descriptions=[]
    for t in tables:
        d=descriptor(t);stats=table_stats[t["table_id"]]
        d.update(coordinate_range=stats["coordinate_range"],observed_coordinate_rows=stats["observed_coordinate_rows"],full_range=stats)
        descriptions.append(d)
    output={"schema":"brohn-signal-preview/1.0","status":"completed","selection":selection,
            "axis":{"kind":axis,"unit":x_unit,"value_unit":y_unit,"value_column":selection["value_column"],
                    "source_time_origin":clocks[0][0],"source_time_unit":clocks[0][1],"reference":clocks[0][2]},
            "effective_range":effective,"full_range":full,"selected_range":selected_stats,"tables":descriptions,
            "envelopes":[],"fragments":[],"parameters":{"max_bins":max_bins,"envelope":"observed first/last/min/max per bin, in original row order"}}
    if effective is None or not selected_stats["eligible_value_rows"]:
        output["status"]="empty_range";return output
    budgets={tid:max_bins//len(ids)+(i<max_bins%len(ids)) for i,tid in enumerate(ids)}
    states={tid:{"previous":None,"last_coordinate":None,"fragment":None,"pending_reason":"table_boundary","bucket":None} for tid in ids}
    def emit(state):
        bucket=state["bucket"]
        if bucket is None: return
        points={p["row_index"]:p for p in [bucket["first"],bucket["minimum"],bucket["maximum"],bucket["last"]]}
        bucket["points"]=[points[i] for i in sorted(points)]
        output["envelopes"].append(bucket);state["bucket"]=None
        require(len(output["envelopes"])<=MAX_ENVELOPE_BINS,"The selected range has too many disconnected envelope bins; narrow the range.")
    def second_rows(tid,offset,values):
        if tid not in chosen: return
        t=chosen[tid];state=states[tid];step,tolerance=cadence(t)
        for i,row in enumerate(values):
            point=sample(t,row,offset+i,selection["value_column"]);x,y=point["x"],point["y"]
            if not finite(x) or not (effective[0]<=x<=effective[1]):
                emit(state);state["previous"]=None;state["fragment"]=None;state["pending_reason"]="outside_range_or_missing_coordinate";continue
            if not finite(y) or not point["retained"]:
                emit(state);state["previous"]=None;state["fragment"]=None;state["pending_reason"]="unavailable_value" if not finite(y) else "retention_exclusion";continue
            previous=state["previous"]
            reason=None
            if previous is not None:
                if point["source_sample_index"] is not None and previous["source_sample_index"] is not None and point["source_sample_index"]!=previous["source_sample_index"]+1: reason="source_sample_gap"
                rounding=32*sys.float_info.epsilon*max(1,abs(x),abs(previous["x"]))
                if axis=="time" and step is not None and abs((x-previous["x"])-step)>tolerance+rounding: reason="declared_clock_cadence_gap"
            if reason:
                emit(state);state["fragment"]=None;state["pending_reason"]=reason
            if state["fragment"] is None:
                fragment_id=f"fragment-{len(output['fragments'])+1}"
                style="scatter" if axis=="event" or (axis=="time" and step is None) else "spectrum" if axis=="frequency" else "trace"
                fragment={"id":fragment_id,"table_id":tid,"break_before":state["pending_reason"],"first_x":x,"last_x":x,
                          "rows":0,"rendering":style,"connection_policy":"none" if style=="scatter" else "within_this_fragment_only",
                          "declared_interval_s":step if axis=="time" else None}
                output["fragments"].append(fragment);state["fragment"]=fragment
                require(len(output["fragments"])<=MAX_FRAGMENTS,"The selected range contains more than 2,000 support fragments; narrow the view.")
            state["fragment"]["rows"]+=1;state["fragment"]["last_x"]=x
            bin_index=min(budgets[tid]-1,max(0,int((x-effective[0])/(effective[1]-effective[0])*budgets[tid]))) if effective[1]>effective[0] else 0
            if state["bucket"] is None or state["bucket"]["bin_index"]!=bin_index:
                emit(state)
                state["bucket"]={"table_id":tid,"fragment_id":state["fragment"]["id"],"bin_index":bin_index,"count":0,
                                 "first":point,"last":point,"minimum":point,"maximum":point}
            bucket=state["bucket"];bucket["count"]+=1;bucket["last"]=point
            if y<bucket["minimum"]["y"]: bucket["minimum"]=point
            if y>bucket["maximum"]["y"]: bucket["maximum"]=point
            state["previous"]=point
    artifacts.verify_artifact(manifest,on_rows=second_rows)
    for state in states.values(): emit(state)
    # Output preserves the declared table selection order, then original rows.
    rank={tid:i for i,tid in enumerate(ids)}
    output["envelopes"].sort(key=lambda b:(rank[b["table_id"]],b["first"]["row_index"]))
    output["quality"]={"selected_eligible_rows":selected_stats["eligible_value_rows"],"envelope_rows":sum(b["count"] for b in output["envelopes"]),
                       "emitted_bins":len(output["envelopes"]),"emitted_points":sum(len(b["points"]) for b in output["envelopes"]),
                       "support_fragments":len(output["fragments"]),"verified_twice":True,"scientific_resampling":False}
    require(output["quality"]["envelope_rows"]==selected_stats["eligible_value_rows"],"Preview envelope lost selected eligible source rows.")
    return output


def cardiac_markers(request,manifest,view):
    """Join saved detections by exact source sample and clock, never nearest time."""
    overlay=request["marker_overlay"]
    require(isinstance(overlay,dict) and set(overlay)=={"event_artifact","event_type"} and
            overlay["event_type"] in {"r_peak","systolic_pulse_peak"},"Choose the saved ECG or PPG detection type.")
    require(manifest["kind"]=="physiology-series" and view["axis"]["kind"]=="time" and view["axis"]["unit"]=="s" and
            view["selection"]["value_column"] in {"raw","clean"},"Cardiac markers require their saved input or cleaned waveform in seconds.")
    events=bind_receipt({"artifact":overlay["event_artifact"],"verification_receipt":request["verification_receipt"]})
    require(events["kind"]=="physiology-events" and events["provenance_sha256"]==manifest["provenance_sha256"],
            "Waveform and detections must share one exact processing provenance.")
    fields=("kind","sha256","bytes","schema","tables","rows","provenance_sha256")
    result={"schema":"brohn-cardiac-marker-overlay/1.1","status":"empty","event_artifact":{k:events[k] for k in fields},
            "waveform_column":view["selection"]["value_column"],"detection_basis":"saved_cleaned_waveform",
            "review_status":"unreviewed_algorithm_detections","event_type":overlay["event_type"],"markers":[],
            "selected_marker_count":0,"limit":MAX_CARDIAC_MARKERS,"alignment":"exact_source_sample_and_recorded_time",
            "value_unit":view["axis"]["value_unit"],"time_unit":"s"}
    selected={t["table_id"]:t for t in view["tables"]};event_tables={};matched_series=set();previous={};marker_keys={}
    def on_table(t):
        if t["coordinates"]["axis"]!="event":return
        matches=[s for s in selected.values() if s["identity"]==t["identity"]]
        if not matches:return
        require(len(matches)==1,"An event table has an ambiguous saved waveform identity.")
        s=matches[0];sid=s["table_id"]
        require(sid not in matched_series,"Multiple event tables refer to the same selected waveform.")
        require(all(s["coordinates"][k]==t["coordinates"][k] for k in ("reference","source_time_origin","source_time_unit")),
                "Event and waveform clocks differ; proximity cannot establish synchronization.")
        names={c["name"]:c for c in t["columns"]}
        required={"type":("string",None),"time_s":("float64","s"),"source_sample_index":("integer","sample_index"),
                  "previous_interval_ms":("float64","ms"),"previous_interval_plausible":("boolean",None)}
        require(all(k in names and (names[k]["type"],names[k]["unit"])==v for k,v in required.items()),
                "Saved detections lack exact typed sample, time or interval evidence.")
        require(t["support"].get("source")==s["support"].get("source") and t["support"].get("method")==s["support"].get("method"),
                "Event and waveform source support or processing recipe differ.")
        source=s["support"].get("source",{})
        require(integer(source.get("source_row_start"),0,2**53-1) and integer(source.get("source_row_end_exclusive"),1,2**53-1) and
                source["source_row_start"]<source["source_row_end_exclusive"],"Cardiac markers need their declared original sample bounds.")
        event_tables[t["table_id"]]=(t,sid);matched_series.add(sid)
    def on_rows(tid,offset,rows):
        if tid not in event_tables:return
        t,sid=event_tables[tid];names=[c["name"] for c in t["columns"]]
        for i,row in enumerate(rows):
            event=dict(zip(names,row));index=event["source_sample_index"];when=event["time_s"]
            require(event["type"]==overlay["event_type"] and integer(index,0,2**53-1) and finite(when),"Unexpected cardiac event or missing original coordinate.")
            source=t["support"]["source"];extent=selected[sid]["coordinate_range"]
            require(source["source_row_start"]<=index<source["source_row_end_exclusive"] and extent is not None and extent[0]<=when<=extent[1],
                    "A cardiac event exceeds the original sample bounds or observed waveform time extent.")
            prev=previous.get(tid)
            require(prev is None or (index>prev[0] and when>prev[1]),"Cardiac markers must retain distinct increasing source samples and times.")
            previous[tid]=(index,when)
            bounds=view["effective_range"]
            if bounds is None or not bounds[0]<=when<=bounds[1]:continue
            result["selected_marker_count"]+=1
            if result["selected_marker_count"]>MAX_CARDIAC_MARKERS:
                result["markers"]=[];marker_keys.clear();continue
            marker={"event_table_id":tid,"event_row_index":offset+i,"series_table_id":sid,"source_sample_index":index,
                    "time_s":when,"value":None,"previous_interval_ms":event["previous_interval_ms"],
                    "previous_interval_plausible":event["previous_interval_plausible"]}
            result["markers"].append(marker);marker_keys[(sid,index)]=marker
    artifacts.verify_artifact(events,on_table=on_table,on_rows=on_rows)
    require(matched_series==set(selected),"A selected waveform has no uniquely matching saved detection table.")
    if result["selected_marker_count"]>MAX_CARDIAC_MARKERS:
        # This is an exact count of saved event rows in the requested time range,
        # not a claim that their per-sample/retention joins were checked. Narrowing
        # the range performs those checks before any marker can be displayed.
        result["status"]="too_many_markers";result["alignment"]="not_checked_display_limit_exceeded";return result
    matched=set()
    def values(tid,offset,rows):
        if tid not in selected:return
        # Descriptors omit non-measure support columns; use the full declaration
        # collected during this independently verified pass instead.
        t=declarations[tid]
        for i,row in enumerate(rows):
            point=sample(t,row,offset+i,view["selection"]["value_column"]);key=(tid,point["source_sample_index"])
            if key not in marker_keys:continue
            marker=marker_keys[key]
            require(key not in matched and point["x"]==marker["time_s"] and finite(point["y"]) and point["retained"],
                    "A saved detection does not match an exact retained waveform sample and time.")
            marker["value"]=point["y"];matched.add(key)
    declarations={}
    def waveform(t):
        if t["table_id"] in selected:declarations[t["table_id"]]=t
    artifacts.verify_artifact(manifest,on_table=waveform,on_rows=values)
    require(matched==set(marker_keys),"A saved detection has no exact sample in the selected waveform.")
    if result["selected_marker_count"]:result["status"]="available"
    return result


def run(request):
    require(isinstance(request,dict) and request.get("schema")=="brohn-signal-preview-request/1.0" and request.get("operation") in {"signal_catalog","signal_preview"},"Unsupported processed-signal view request.")
    allowed={"schema","operation","artifact","verification_receipt","selection","parameters","page","marker_overlay"}
    require(set(request)<=allowed,"Unknown signal view setting; no input is silently ignored.")
    manifest=bind_receipt(request)
    is_catalog=request["operation"]=="signal_catalog" or ("selection" in request and request["selection"] is None)
    if is_catalog:
        require("marker_overlay" not in request,"Marker overlays belong to a waveform view, not its catalog.")
        require(request.get("selection") is None and not request.get("parameters"),"Catalog requests do not accept preview selections or parameters.")
        result=catalog(request,manifest)
    else:
        require("page" not in request,"Preview requests do not use catalog pagination.")
        result=preview(request,manifest)
        if "marker_overlay" in request:result["marker_overlay"]=cardiac_markers(request,manifest,result)
    result["artifact"]={key:manifest[key] for key in ("kind","sha256","bytes","schema","tables","rows","provenance_sha256")}
    result["engine"]={"name":"Brohn processed signal view","version":"1.2.0","worker_sha256":artifacts.digest_file(Path(__file__)),"artifact_reader_sha256":artifacts.digest_file(Path(artifacts.__file__))}
    result["limitations"]=["Views preserve observed extrema and support boundaries; they do not recompute physiology features, align independent clocks or create new scientific scores.",
        "Coordinates remain relative to the artifact's declared clock origin. The exact original origin is a string; plotting uses the recorded finite float64 relative coordinates.",
        "Min/max envelopes retain spikes inside each displayed bin but are a bounded visual summary. Full typed source rows remain available in the immutable artifact."]
    require(len(json.dumps(result,allow_nan=False,separators=(",",":")).encode("utf-8"))<=16*1024**2,"Preview output exceeds 16 MiB; request fewer tables or a smaller catalog page.")
    return result


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--request",type=Path,required=True);parser.add_argument("--output",type=Path,required=True)
    args=parser.parse_args();code=0;safe=not os.path.lexists(args.output) and args.output.resolve()!=args.request.resolve()
    try:
        require(safe,"Preview receipt requires a new output path; existing files cannot be replaced.")
        require(args.request.is_file() and args.request.stat().st_size<=2*1024**2,"Preview request is absent or exceeds 2 MiB.")
        request=json.loads(args.request.read_text(encoding="utf-8"),object_pairs_hook=artifacts._unique,
                           parse_constant=lambda x: (_ for _ in ()).throw(InputError("Nonfinite request JSON.")))
        result=run(request)
    except Exception as error:
        code=2;result={"schema":"brohn-signal-view-error/1.0","status":"error","error":{"type":type(error).__name__,"message":str(error)[:1000]}}
    if not safe: print(json.dumps(result),file=sys.stderr);return code
    require(args.output.parent.is_dir(),"Preview output directory must already exist.")
    descriptor,name=tempfile.mkstemp(prefix=".brohn-signal-preview-",suffix=".json.tmp",dir=args.output.parent)
    try:
        with os.fdopen(descriptor,"w",encoding="utf-8") as stream:
            json.dump(result,stream,allow_nan=False,separators=(",",":"));stream.write("\n");stream.flush();os.fsync(stream.fileno())
        require(Path(name).stat().st_size<=16*1024**2,"Preview output exceeds 16 MiB; request fewer tables or a smaller catalog page.")
        os.replace(name,args.output)
    finally:
        if os.path.exists(name): os.unlink(name)
    print(json.dumps({"status":result["status"]}));return code


if __name__=="__main__": raise SystemExit(main())
