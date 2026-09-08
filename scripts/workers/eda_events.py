"""Continuous-context EDA decomposition with explicitly supported event windows."""
from __future__ import annotations

import argparse
import contextlib
import copy
import csv
import importlib
import importlib.util
import inspect
import io as string_io
import json
import math
import os
from pathlib import Path
import platform
import sys
import tempfile
import warnings

os.environ.setdefault("OMP_NUM_THREADS", "1")
os.environ.setdefault("OPENBLAS_NUM_THREADS", "1")
os.environ.setdefault("MPLBACKEND", "Agg")
import numpy as np
from scipy.signal import find_peaks

_spec = importlib.util.spec_from_file_location("brohn_eda_io", Path(__file__).with_name("physiology.py"))
io = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(io)
InputError, require, finite = io.InputError, io.require, io.finite
RECIPES = {"eda-event-highpass/1.0", "eda-event-cvxeda-defaults/1.0"}
MAX_EVENTS = 2000
MAX_CELLS = 10000
MAX_CANDIDATES = 20000
MAX_DISPLAY = 2000
MAX_CVX_SAMPLES = 10000
CVX_DEFAULTS = dict(tau0=2, tau1=.7, delta_knot=10, alpha=.0008, gamma=.01, solver=None, reltol=1e-9)


class DelimitedSource:
    def __init__(self, path, source_format): self.path, self.suffix = path, "." + source_format
    def open(self, *args, **kwargs): return self.path.open(*args, **kwargs)


def text(value, limit=4000):
    return isinstance(value, str) and bool(value.strip()) and len(value) <= limit


def settings(supplied, fs):
    keys = {"recipe", "event_codes", "nuisance_codes", "event_source", "settings_source", "baseline_s", "response_s",
            "onset_latency_s", "recovery_end_s", "nuisance_effect_s", "overlap_policy", "response_selection",
            "minimum_scr_amplitude_us", "relative_prominence", "edge_exclusion_s", "minimum_segment_s"}
    require(isinstance(supplied, dict) and keys <= set(supplied) <= keys | {"event_tolerance_s"},
            "EDA event recipes require explicit timing, thresholds, overlap and provenance settings; unknown settings are rejected.")
    p = copy.deepcopy(supplied)
    require(p["recipe"] in RECIPES, "Select an implemented versioned EDA event recipe.")
    finite(fs, "sampling_rate", 8, 2000)
    for name in ("event_source", "settings_source"): require(text(p[name]), f"Declare {name} provenance.")
    require(isinstance(p["event_codes"], dict) and 1 <= len(p["event_codes"]) <= 100 and
            all(text(k,128) and text(v,128) for k,v in p["event_codes"].items()), "event_codes maps source codes to condition IDs.")
    require(isinstance(p["nuisance_codes"], list) and len(p["nuisance_codes"]) <= 100 and
            all(text(k,128) for k in p["nuisance_codes"]) and len(set(p["nuisance_codes"])) == len(p["nuisance_codes"]), "nuisance_codes must be a unique string array.")
    require(not set(p["nuisance_codes"]) & set(p["event_codes"]), "A source code cannot be both a target and nuisance.")
    for name in ("baseline_s", "response_s", "onset_latency_s", "nuisance_effect_s"):
        value = p[name]
        require(isinstance(value,list) and len(value)==2, f"{name} requires two endpoints.")
        a,b = (finite(v,name,-120,300) for v in value)
        require(a < b, f"{name} endpoints must increase.")
        if name in {"baseline_s","response_s"}:
            require(all(abs(v*fs-round(v*fs)) < 1e-7 for v in value), f"{name} endpoints must lie on the declared sample grid.")
    require(p["baseline_s"][1] <= 0 <= p["response_s"][0], "Baseline must end at or before the event; response starts at or after it.")
    require(p["response_s"][0] <= p["onset_latency_s"][0] < p["onset_latency_s"][1] <= p["response_s"][1], "Onset latency must lie inside the response window.")
    finite(p["recovery_end_s"], "recovery_end_s", p["response_s"][1], 300)
    require(p["overlap_policy"] in {"exclude", "descriptive_only"}, "Declare exclude or descriptive_only overlap policy.")
    require(p["response_selection"] in {"first_onset", "largest_amplitude"}, "Declare first_onset or largest_amplitude selection.")
    finite(p["minimum_scr_amplitude_us"], "minimum_scr_amplitude_us", .000001, 100)
    finite(p["relative_prominence"], "relative_prominence", .001, 1)
    finite(p["edge_exclusion_s"], "edge_exclusion_s", 10, 300)
    finite(p["minimum_segment_s"], "minimum_segment_s", max(40, 2*p["edge_exclusion_s"]+20), 3600)
    p["event_tolerance_s"] = finite(p.get("event_tolerance_s", .5/fs), "event_tolerance_s", 0, .5/fs)
    p["effective"] = {"cleaner":"neurokit", "clean_lowpass_hz":3, "clean_order":4,
        "decomposition":"highpass" if p["recipe"]=="eda-event-highpass/1.0" else "cvxeda",
        "phasic_cutoff_hz":.05 if p["recipe"]=="eda-event-highpass/1.0" else None,
        "cvx_defaults":CVX_DEFAULTS if p["recipe"]=="eda-event-cvxeda-defaults/1.0" else None,
        "detector":"neurokit", "relative_threshold_definition":"candidate_prominence_relative_to_segment_maximum_prominence",
        "absolute_threshold_definition":"phasic_onset_to_peak_amplitude_us", "recovery_fraction":.5,
        "integration":"trapezoid_on_measured_endpoints", "window_support":"complete_same_continuous_segment",
        "interpolation":False, "event_time_coordinates":"seconds_relative_to_each_source_recording_first_timestamp"}
    return p


def load_source(path, m, source_format, p):
    require(source_format in {"csv","tsv"}, "EDA event input supports declared CSV or TSV conductance samples.")
    for field in ("participant_column","session_column"):
        require(text(m.get(field),500), "EDA events require explicit participant and session source columns.")
    require(m.get("time_unit") in {"s","ms"}, "EDA event time_unit must be s or ms.")
    group_m = copy.deepcopy(m)
    group_m.pop("condition_column", None)
    group_m.pop("exposure_column", None)
    if m.get("recording_column"): group_m["exposure_column"] = m["recording_column"]
    recordings, source = io.csv_recordings(DelimitedSource(path,source_format), group_m, "eda")
    source["source_format"] = source_format
    for r in recordings:
        if "exposure_id" in r["group"]: r["group"]["source_recording_id"] = r["group"].pop("exposure_id")
        r["events"] = []
        r["source_valid"] = np.ones(len(r["times"]), bool)
    column, explicit = m.get("event_column"), m.get("events")
    require(bool(column) != (explicit is not None), "Supply exactly one onset event_column or explicit events array.")
    if column: require(text(m.get("exposure_column"),500), "Onset rows require an exposure_column for trial identity.")
    selected = [m.get(k) for k in ("participant_column","session_column","recording_column","segment_column","event_column","exposure_column","condition_column","stimulus_column","valid_column","time_column") if m.get(k)] + m["value_columns"]
    require(all(text(c,500) for c in selected) and len(set(selected))==len(selected), "Signal, clock, event, validity and identity columns must be distinct.")
    with path.open("r",encoding="utf-8-sig",newline="") as stream:
        reader = csv.DictReader(stream,delimiter="\t" if source_format=="tsv" else ",")
        require(set(selected) <= set(reader.fieldnames), "A declared event, validity or identity column is absent.")
        ri = 0
        for row_index,row in enumerate(reader):
            while ri+1 < len(recordings) and row_index >= recordings[ri+1]["source_row_start"]: ri += 1
            r = recordings[ri]; i = row_index-r["source_row_start"]
            if m.get("valid_column"):
                value = row[m["valid_column"]].strip().lower()
                require(value in {"1","true","0","false","","na","n/a","null","nan"}, "Validity values must be true/false or 1/0; missing means invalid.")
                r["source_valid"][i] = value in {"1","true"}
            if column and row[column].strip() not in io.MISSING:
                e = {"time_s":float(r["times"][i]), "code":row[column].strip(), "source_sample_index":row_index}
                for name in ("exposure","condition","stimulus"):
                    if m.get(name+"_column"):
                        value = row[m[name+"_column"]].strip()
                        if value not in io.MISSING: e[name+"_id"] = value
                r["events"].append(e)
    if explicit is not None:
        require(isinstance(explicit,list) and len(explicit) <= MAX_EVENTS, "Explicit events must be a bounded onset array.")
        for e in explicit:
            require(isinstance(e,dict) and set(e) <= {"time_s","code","exposure_id","recording_id","condition_id","stimulus_id"}, "Explicit event has unsupported fields.")
            matches = [r for r in recordings if e.get("recording_id", recordings[0]["id"] if len(recordings)==1 else None)==r["id"]]
            require(len(matches)==1, "Each explicit event must name its generated recording_id when multiple recordings exist.")
            matches[0]["events"].append(copy.deepcopy(e))
    count = sum(len(r["events"]) for r in recordings)
    require(0 < count <= MAX_EVENTS and count*len(m["value_columns"]) <= MAX_CELLS, "Select 1 to 2,000 source events and at most 10,000 event/channel cells.")
    for r in recordings:
        r["source_missing"] = ~np.isfinite(r["values"])
        r["values"][:,~r["source_valid"]] = np.nan
        seen = set(); times_seen = set()
        for i,e in enumerate(r["events"]):
            require(text(e.get("code"),128), "Source event code must be a nonempty string.")
            require(e["code"] in p["event_codes"] or e["code"] in p["nuisance_codes"], "Every observed code must be mapped to a condition or declared nuisance.")
            event_time = finite(e.get("time_s"), "event time_s", 0, float(r["times"][-1]))
            index = int(np.argmin(abs(r["times"]-event_time)))
            difference = float(r["times"][index]-event_time)
            require(abs(difference) <= p["event_tolerance_s"]+1e-10, "Event onset has no measured sample within its declared alignment tolerance.")
            require(index not in times_seen, "Multiple event codes at the same measured onset need an explicit combined-event protocol.")
            times_seen.add(index)
            e.update(id=f"{r['id']}-event-{i+1}", requested_time_s=event_time, time_s=float(r["times"][index]),
                     alignment_error_s=difference, source_sample_index=r["source_row_start"]+index,
                     type="stimulus_event" if e["code"] in p["event_codes"] else "nuisance_event")
            if e["type"]=="stimulus_event":
                require(text(e.get("exposure_id"),128) and e["exposure_id"] not in seen, "Every target onset requires a unique exposure_id within its recording.")
                seen.add(e["exposure_id"])
                condition = p["event_codes"][e["code"]]
                require(not e.get("condition_id") or e["condition_id"]==condition, "Onset condition ID conflicts with the frozen code mapping.")
                e["condition_id"] = condition
            elif e.get("condition_id"): raise InputError("Nuisance events cannot silently carry a target condition identity.")
            if "stimulus_id" in e: require(text(e["stimulus_id"],128), "Stimulus identity must be a nonempty string.")
        r["events"].sort(key=lambda e:e["time_s"])
    source["preprocessing_group_columns"] = {k:m.get(k+"_column") for k in ("participant","session","recording")}
    source["condition_exposure_do_not_split_preprocessing"] = True
    return recordings, source


def decompose(x, times, fs, p):
    require(len(x)/fs >= p["minimum_segment_s"], "continuous_segment_too_short")
    require(np.isfinite(x).all() and (x>=0).all(), "Decomposition cannot receive invalid samples.")
    nk = io.require_neurokit()
    clean = np.asarray(nk.eda_clean(x,sampling_rate=fs,method="neurokit"),float)
    if p["recipe"]=="eda-event-cvxeda-defaults/1.0":
        require(len(x) <= MAX_CVX_SAMPLES, "cvxEDA segment exceeds 10,000 samples; no automatic cropping or resampling is allowed.")
        require(io.versions(["cvxopt"])["cvxopt"]=="1.3.2", "This recipe requires CVXOPT 1.3.2.")
        helper = importlib.import_module("neurokit2.eda.eda_phasic")._eda_phasic_cvxeda
        require({k:inspect.signature(helper).parameters[k].default for k in CVX_DEFAULTS}==CVX_DEFAULTS, "Pinned cvxEDA public-wrapper defaults changed.")
        with contextlib.redirect_stdout(string_io.StringIO()):
            components = nk.eda_phasic(clean,sampling_rate=fs,method="cvxeda")
    else: components = nk.eda_phasic(clean,sampling_rate=fs,method="highpass",cutoff=.05)
    tonic,phasic = (np.asarray(components[k],float) for k in ("EDA_Tonic","EDA_Phasic"))
    require(np.isfinite(clean).all() and np.isfinite(tonic).all() and np.isfinite(phasic).all(), "Decomposition returned nonfinite samples.")
    edge = int(math.ceil(p["edge_exclusion_s"]*fs))
    retained = (np.arange(len(x)) >= edge) & (np.arange(len(x)) < len(x)-edge)
    candidates, detector_error = [], None
    # The pinned wrapper raises on a truly peakless signal. Checking strict local
    # maxima first gives an explicit, tested zero-candidate case, not a catch-all.
    if len(find_peaks(phasic)[0]):
        try:
            _,info = nk.eda_peaks(phasic,sampling_rate=fs,method="neurokit",amplitude_min=p["relative_prominence"])
            for i,peak in enumerate(info["SCR_Peaks"]):
                peak = int(peak)
                if not retained[peak]: continue
                def index(name):
                    value = io.number(info.get(name,[])[i]) if i < len(info.get(name,[])) else None
                    return int(value) if value is not None and value==int(value) and 0<=value<len(x) else None
                onset,recovery = index("SCR_Onsets"),index("SCR_Recovery")
                onset_ok = onset is not None and retained[onset] and onset < peak
                recovery_ok = recovery is not None and retained[recovery] and recovery >= peak
                amplitude = float(phasic[peak]-phasic[onset]) if onset_ok else None
                candidates.append({"type":"scr_candidate", "peak_time_s":float(times[peak]), "peak_sample_index":peak,
                    "onset_time_s":float(times[onset]) if onset_ok else None,
                    "recovery_time_s":float(times[recovery]) if recovery_ok else None,
                    "amplitude_us":amplitude, "peak_height_us":float(phasic[peak]),
                    "recovery_fraction":.5, "onset_supported":bool(onset_ok), "recovery_supported":bool(recovery_ok)})
        except (ValueError,IndexError,ZeroDivisionError) as error:
            detector_error = str(error)[:500]
            candidates = []
    return {"times":times, "raw_us":x, "clean_us":clean, "tonic_us":tonic, "phasic_us":phasic,
            "retained":retained, "candidates":candidates, "detector_error":detector_error}


def window_support(bundles, onset, bounds, tolerance):
    requested = [onset+b for b in bounds]
    result = {"requested_start_s":requested[0], "requested_end_s":requested[1], "complete":False,
              "observed_start_s":None, "observed_end_s":None, "samples":0, "duration_s":None,
              "reason":"missing_gap_filter_edge_or_short_continuous_context"}
    for b in bundles:
        t = b["times"]
        indices = [int(np.argmin(abs(t-value))) for value in requested]
        start,end = indices
        if end <= start or any(abs(t[i]-value)>tolerance+1e-9 for i,value in zip(indices,requested)): continue
        if not b["retained"][start:end+1].all(): continue
        result.update(complete=True,observed_start_s=float(t[start]),observed_end_s=float(t[end]),
                      samples=end-start+1,duration_s=float(t[end]-t[start]),reason=None,
                      start_alignment_error_s=float(t[start]-requested[0]),end_alignment_error_s=float(t[end]-requested[1]),
                      segment_id=b["segment_id"])
        return result, (b,start,end)
    return result, None


def intersects(a,b):
    # Touching endpoints are an overlap under this deliberately conservative recipe.
    return max(a[0],b[0]) <= min(a[1],b[1])+1e-10


def source_masks(r, channel_index):
    """Lossless run-length source masks, separate from bounded display sampling."""
    t=r["times"]; masks=[]
    flags={"missing_source_signal":r["source_missing"][channel_index],"source_validity_exclusion":~r["source_valid"],
           "negative_conductance":np.isfinite(r["values"][channel_index]) & (r["values"][channel_index]<0)}
    for reason,flag in flags.items():
        transitions=np.diff(np.r_[False,flag,False].astype(int))
        for start,end in zip(np.where(transitions==1)[0],np.where(transitions==-1)[0]):
            masks.append({"reason":reason,"source_row_start":int(r["source_row_start"]+start),
                "source_row_end_exclusive":int(r["source_row_start"]+end),"start_time_s":float(t[start]),"end_time_s":float(t[end-1]),"samples":int(end-start)})
    for i in np.where(np.diff(t)>1.5/r["fs"])[0]:
        masks.append({"reason":"clock_gap","source_row_before":int(r["source_row_start"]+i),"source_row_after":int(r["source_row_start"]+i+1),
                      "before_time_s":float(t[i]),"after_time_s":float(t[i+1]),"unobserved_duration_s":float(t[i+1]-t[i]-1/r["fs"])})
    return masks


def event_summary(event, all_events, bundles, p, tolerance):
    onset = event["time_s"]
    baseline,b_slice = window_support(bundles,onset,p["baseline_s"],tolerance)
    response,r_slice = window_support(bundles,onset,p["response_s"],tolerance)
    complete = bool(b_slice and r_slice and b_slice[0] is r_slice[0])
    intervals = [onset+p["baseline_s"][0],onset+p["response_s"][1]]
    conflicts = []
    for other in all_events:
        if other["id"]==event["id"]: continue
        bounds = p["nuisance_effect_s"] if other["type"]=="nuisance_event" else [p["baseline_s"][0],p["response_s"][1]]
        if intersects(intervals,[other["time_s"]+v for v in bounds]): conflicts.append(other["id"])
    descriptives_ok = complete and (not conflicts or p["overlap_policy"]=="descriptive_only")
    reason = None if descriptives_ok else "ambiguous_overlapping_events" if complete else "incomplete_baseline_response_or_continuous_context"
    features = []
    def add(name,value,unit,eligible,missing_reason=None,**extra):
        features.append({"name":name,"value":io.number(value),"unit":unit,"scope":"event",
            "eligible":bool(eligible),"support_status":"computed" if eligible else "unavailable",
            "missing_reason":None if eligible else missing_reason,**extra})
    baseline_mean=response_mean=signed=positive=None
    if descriptives_ok:
        bb,bs,be=b_slice; rb,rs,re=r_slice
        baseline_mean=float(np.trapezoid(bb["tonic_us"][bs:be+1],bb["times"][bs:be+1])/baseline["duration_s"])
        response_mean=float(np.trapezoid(rb["tonic_us"][rs:re+1],rb["times"][rs:re+1])/response["duration_s"])
        signed=float(np.trapezoid(rb["phasic_us"][rs:re+1],rb["times"][rs:re+1]))
        positive=float(np.trapezoid(np.maximum(rb["phasic_us"][rs:re+1],0),rb["times"][rs:re+1]))
    for name,value,unit in (("tonic_baseline_mean",baseline_mean,"uS"),("tonic_response_mean",response_mean,"uS"),
        ("tonic_response_minus_baseline",response_mean-baseline_mean if descriptives_ok else None,"uS"),
        ("phasic_response_area_signed",signed,"uS*s"),("phasic_response_area_positive",positive,"uS*s")):
        add(name,value,unit,descriptives_ok,reason,interpretation="descriptive_window_measure" if conflicts else "event_window_measure")
    scr_ok=complete and not conflicts; scr_reason=reason if not complete else "ambiguous_overlapping_events" if conflicts else None
    candidates=[]; selected=None; recovery_reason=None
    if scr_ok:
        b=r_slice[0]
        if b["detector_error"]: scr_ok=False; scr_reason="scr_detector_failed"
        else:
            in_window=[c for c in b["candidates"] if onset+p["response_s"][0]-1e-10 <= c["peak_time_s"] <= onset+p["response_s"][1]+1e-10]
            unknown=[c for c in in_window if c["onset_time_s"] is None or c["amplitude_us"] is None]
            ongoing=[c for c in in_window if c["onset_time_s"] is not None and c["amplitude_us"] >= p["minimum_scr_amplitude_us"] and c["onset_time_s"] < onset+p["onset_latency_s"][0]-1e-10]
            if unknown or ongoing: scr_ok=False; scr_reason="unobserved_or_preexisting_scr_onset"
            candidates=[c for c in in_window if c["onset_time_s"] is not None and c["amplitude_us"] >= p["minimum_scr_amplitude_us"] and
                        onset+p["onset_latency_s"][0]-1e-10 <= c["onset_time_s"] <= onset+p["onset_latency_s"][1]+1e-10]
            if scr_ok and candidates:
                selected=sorted(candidates,key=(lambda c:(c["onset_time_s"],c["peak_time_s"])) if p["response_selection"]=="first_onset" else (lambda c:(-c["amplitude_us"],c["onset_time_s"])))[0]
    magnitude=selected["amplitude_us"] if selected else 0 if scr_ok else None
    add("scr_response_magnitude",magnitude,"uS",scr_ok,scr_reason,denominator="all_eligible_events_including_nonresponses")
    add("scr_responder_amplitude",selected["amplitude_us"] if selected else None,"uS",scr_ok and selected is not None,scr_reason or "no_qualifying_response",denominator="eligible_responder_events_only")
    add("scr_qualifying_count",len(candidates) if scr_ok else None,"count",scr_ok,scr_reason)
    add("scr_nonresponse",int(not candidates) if scr_ok else None,"indicator",scr_ok,scr_reason)
    for name,key in (("scr_onset_latency","onset_time_s"),("scr_peak_latency","peak_time_s")):
        add(name,selected[key]-onset if selected else None,"s",selected is not None,scr_reason or "no_qualifying_response")
    add("scr_rise_time",selected["peak_time_s"]-selected["onset_time_s"] if selected else None,"s",selected is not None,scr_reason or "no_qualifying_response")
    recovery=None
    if selected:
        candidate_recovery=selected["recovery_time_s"]
        if candidate_recovery is None: recovery_reason="half_recovery_not_observed_in_retained_segment"
        elif candidate_recovery>onset+p["recovery_end_s"]+1e-10: recovery_reason="half_recovery_after_declared_boundary"
        elif any(other["id"]!=event["id"] and onset < other["time_s"] <= candidate_recovery+1e-10 for other in all_events): recovery_reason="another_event_precedes_half_recovery"
        else: recovery=candidate_recovery-selected["peak_time_s"]
    add("scr_half_recovery_time",recovery,"s",recovery is not None,recovery_reason or scr_reason or "no_qualifying_response")
    summary={"status":"computed" if descriptives_ok else "unavailable", "reason":reason,
             "scr_status":"computed" if scr_ok else "unavailable","scr_reason":scr_reason,
             "baseline_support":baseline,"response_support":response,"same_continuous_segment":complete,
             "overlapping_event_ids":conflicts,"response_candidates":len(candidates) if scr_ok else None,
             "selected_scr":selected,"recovery_missing_reason":recovery_reason,
             "nonresponse":bool(not candidates) if scr_ok else None}
    return features,summary


def _run(request):
    require(isinstance(request,dict) and request.get("schema")=="brohn-worker-request/1.0" and request.get("operation")=="eda_events" and request.get("modality")=="eda", "EDA event worker requires the eda_events / eda request contract.")
    path=Path(request.get("source_path","")).resolve()
    require(path.is_file() and 0<path.stat().st_size<=io.MAX_FILE_BYTES, "Source is absent, empty or exceeds 512 MiB.")
    m=request.get("metadata")
    require(isinstance(m,dict), "Explicit EDA source metadata is required.")
    require(m.get("origin","unspecified") in {"sample","preview","pilot","live","imported","unspecified"}, "Unsupported source origin.")
    p=settings(request.get("parameters",m.get("parameters")),m.get("sampling_rate"))
    with warnings.catch_warnings(record=True) as caught:
        warnings.simplefilter("always")
        recordings,source=load_source(path,m,request.get("format"),p)
        packages=["numpy","scipy","neurokit2"]+(["cvxopt"] if p["recipe"]=="eda-event-cvxeda-defaults/1.0" else [])
        output={"schema":"brohn-worker-result/1.0","operation":"eda_events","modality":"eda","status":"completed",
            "engine":{"name":"Brohn EDA event worker","version":"1.0.0","python":platform.python_version(),"packages":io.versions(packages),
                      "worker_sha256":io.digest_file(Path(__file__)),"shared_io_sha256":io.digest_file(Path(io.__file__))},
            "source":{"sha256":io.digest_file(path),"bytes":path.stat().st_size,**source},"parameters":{},
            "features":[],"recordings":[],"events":[],"series":[],"artifacts":[],"segments":[],"source_masks":[]}
        prepared=io.prepare_artifacts(request,output)
        displays=[]; candidates_count=0; total=0; valid_total=0
        for r in recordings:
            output["parameters"][r["id"]]=p
            origin=m.get("origin","unspecified")
            output["events"].extend({**e,"recording_id":r["id"],"group":r["group"],"origin":origin} for e in r["events"])
            for ci,channel in enumerate(r["channels"]):
                bundles=[]
                segments,quality=io.continuous_segments(r,ci,m,"eda")
                quality["source_validity_excluded_samples"]=int(np.sum(~r["source_valid"]))
                quality["original_missing_source_samples"]=int(np.sum(r["source_missing"][ci]))
                masks=source_masks(r,ci)
                require(len(output["source_masks"])+len(masks)<=MAX_CANDIDATES, "More than 20,000 lossless source-mask intervals; split the source into explicit recording jobs.")
                output["source_masks"].extend({"recording_id":r["id"],"channel":channel,"group":r["group"],**mask} for mask in masks)
                total+=len(r["times"])
                for si,(start,end) in enumerate(segments):
                    require(len(output["segments"])<io.MAX_RECORDINGS, "More than 2,000 channel segments; split the source into explicit recording jobs.")
                    identity={"recording_id":r["id"],"segment_id":f"{r['id']}-{channel}-segment-{si+1}","channel":channel,"group":r["group"],"origin":origin}
                    x,t=r["values"][ci,start:end],r["times"][start:end]
                    summary={**identity,"source_row_start":r["source_row_start"]+start,"source_row_end_exclusive":r["source_row_start"]+end,
                             "source_time_origin":r["source_time_origin"],"start_time_s":float(t[0]),"end_time_s":float(t[-1]),"samples":end-start,
                             "unit":"uS","source_unit":r["source_unit"],"scale_factor":r["scale_factor"],"sampling_rate":r["fs"],"channel_quality":quality,
                             "exact_flatline":bool(np.ptp(x)==0)}
                    try: b=decompose(x,t,r["fs"],p)
                    except (InputError,ValueError,IndexError,ZeroDivisionError) as error:
                        output["segments"].append({**summary,"status":"unavailable","reason":str(error)[:500]}); continue
                    if prepared is not None:
                        prepared[0].write_eda_event_segment(prepared[1],identity,b,summary,m["time_unit"],p,f"eda-segment-{len(output['segments'])+1}")
                    b["segment_id"]=identity["segment_id"]; bundles.append(b); displays.append((identity,b))
                    valid_total+=int(b["retained"].sum())
                    candidates_count+=len(b["candidates"])
                    require(candidates_count<=MAX_CANDIDATES, "More than 20,000 SCR candidates; split into explicit recording jobs.")
                    output["events"].extend({**identity,**c,"source_peak_sample":r["source_row_start"]+start+c["peak_sample_index"]} for c in b["candidates"])
                    output["segments"].append({**summary,"status":"computed","retained_samples":int(b["retained"].sum()),
                        "retained_start_time_s":float(t[b["retained"]][0]),"retained_end_time_s":float(t[b["retained"]][-1]),"scr_detector_error":b["detector_error"]})
                for e in r["events"]:
                    if e["type"]!="stimulus_event": continue
                    identity={"recording_id":r["id"],"event_id":e["id"],"channel":channel,"condition_id":e["condition_id"],"exposure_id":e["exposure_id"],
                              "stimulus_id":e.get("stimulus_id"),"group":{**r["group"],"condition_id":e["condition_id"],"exposure_id":e["exposure_id"]},"origin":origin}
                    features,summary=event_summary(e,r["events"],bundles,p,m.get("timestamp_tolerance_s",.02/r["fs"]))
                    output["features"].extend({**identity,**f} for f in features)
                    output["recordings"].append({**identity,**summary,"time_s":e["time_s"],"requested_time_s":e["requested_time_s"],"alignment_error_s":e["alignment_error_s"],
                        "source_time_origin":r["source_time_origin"],"source_sample_index":e["source_sample_index"],"sampling_rate":r["fs"],
                        "source_unit":r["source_unit"],"unit":"uS","scale_factor":r["scale_factor"],"channel_quality":quality,
                        "participant_linkage":"declared_source_identity","analysis_unit":"event_within_person_session"})
        remaining=MAX_DISPLAY
        for i,(identity,b) in enumerate(displays):
            count=min(len(b["times"]),max(1,remaining//(len(displays)-i)))
            indices=np.unique(np.linspace(0,len(b["times"])-1,count,dtype=int));remaining-=len(indices)
            for j in indices:
                output["series"].append({**identity,"time_s":float(b["times"][j]),"retained":bool(b["retained"][j]),
                    **{key:io.number(b[key][j]) for key in ("raw_us","clean_us","tonic_us","phasic_us")}})
        computed=sum(r["status"]=="computed" for r in output["recordings"])
        scr_computed=sum(r["scr_status"]=="computed" for r in output["recordings"])
        output["status"]="completed" if computed==len(output["recordings"]) and scr_computed==computed and computed else "partial" if computed else "insufficient_support"
        output["quality"]={"usable":computed>0,"scientifically_qualified":False,"requires_research_review":True,"participant_inference_performed":False,
            "requested_event_channel_cells":len(output["recordings"]),"computed_window_cells":computed,"computed_scr_cells":scr_computed,
            "unavailable_window_cells":len(output["recordings"])-computed,"source_events":sum(len(r["events"]) for r in recordings),
            "scr_candidates":candidates_count,"channel_samples_total":total,"channel_samples_retained":valid_total,
            "display_sampling":"uniform index selection within continuous segments; all numerical windows use full measured support",
            "series_samples_displayed":len(output["series"]),"warnings":sorted({str(w.message)[:500] for w in caught})[:100]}
        output["limitations"]=[
            "Continuous preprocessing precedes trial slicing. Person/session/source-reset, missing, invalid and clock-gap boundaries are never bridged or imputed.",
            "Filter margins and minimum context are explicit conservative recipe constraints, not universal proof of settling or motion-artifact removal. Review acquisition and event alignment.",
            "Only mapped target and nuisance onsets are considered. Missing source markers, unmeasured movement and physiological carryover can still confound event windows.",
            "Overlapping target windows or declared nuisance effects prohibit SCR attribution. Descriptive-only overlap permits tonic/phasic window summaries without resolving causal attribution.",
            "cvxEDA decomposes a recording; it does not assign overlapping responses to events. This adapter uses pinned public defaults and exposes no driver or convergence diagnostics.",
            "Positive phasic area clips negative samples before trapezoid integration; signed area remains separate. Highpass tonic and phasic need not add exactly to the clean source.",
            "No qualifying SCR is zero magnitude only with complete support and successful detection. Responder amplitude and missing onset/recovery are never imputed as zero.",
            "SCR onset/peak/recovery are detector candidates on phasic conductance. Thresholds, timing and half-recovery require the declared protocol; an EDA response is not an emotion label.",
            "Events, channels and repeated sessions are not independent people. This worker computes no participant-level inference or multimodal construct score."]
        io.finish_artifacts(output,prepared)
        return output


def run(request):
    require(isinstance(request,dict) and "_artifact_state" not in request,"Worker request must be an external request object.")
    internal=dict(request);internal["_artifact_state"]=[]
    try: return _run(internal)
    finally:
        for writers in internal["_artifact_state"]: writers.abort()


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--request",required=True,type=Path);parser.add_argument("--output",required=True,type=Path)
    args=parser.parse_args();code=0;safe=args.output.resolve()!=args.request.resolve()
    try:
        require(safe,"Output cannot replace request JSON.")
        require(args.request.is_file() and args.request.stat().st_size<=2*1024*1024,"Request exceeds 2 MiB.")
        def unique(pairs):
            result={}
            for key,value in pairs:
                require(key not in result,"Duplicate JSON object field.");result[key]=value
            return result
        request=json.loads(args.request.read_text(encoding="utf-8"),object_pairs_hook=unique,
            parse_constant=lambda x: (_ for _ in ()).throw(InputError("Nonfinite JSON values are not allowed.")))
        require(isinstance(request,dict),"Request must be a JSON object.")
        safe=args.output.resolve()!=Path(request.get("source_path","")).resolve()
        require(safe,"Output cannot replace source data.")
        result=run(request)
    except Exception as error:
        code=2;result={"schema":"brohn-worker-result/1.0","status":"error","error":{"type":type(error).__name__,"message":str(error)[:1000]},
                       "quality":{"usable":False},"features":[],"events":[],"series":[],"artifacts":[]}
    if not safe: print(json.dumps(result),file=sys.stderr);return 2
    args.output.parent.mkdir(parents=True,exist_ok=True)
    descriptor,temporary=tempfile.mkstemp(prefix=".brohn-eda-events-",suffix=".json",dir=args.output.parent)
    try:
        with os.fdopen(descriptor,"w",encoding="utf-8",newline="\n") as stream:
            json.dump(result,stream,allow_nan=False,ensure_ascii=False);stream.write("\n")
        os.replace(temporary,args.output)
    finally:
        if os.path.exists(temporary): os.unlink(temporary)
    print(json.dumps({"status":result["status"],"features":len(result["features"])}));return code


if __name__=="__main__": raise SystemExit(main())
