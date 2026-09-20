"""Explicit, bounded offline EEG epoch, Morlet and frequency-tagging recipes."""
from __future__ import annotations

import argparse
import copy
import csv
import importlib.util
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
from scipy import signal

# Reuse the bounded source readers and unit/time contracts; never invoke their
# recording-level physiology analysis or mutate the shared worker module.
_spec = importlib.util.spec_from_file_location("brohn_neural_io", Path(__file__).with_name("physiology.py"))
io = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(io)
InputError, require, finite = io.InputError, io.require, io.finite
MORLET_RECIPES = {"eeg-morlet-epochs/1.0", "eeg-morlet-epochs/1.1"}
RECIPES = {"eeg-erp-epochs/1.0", "eeg-frequency-tagging/1.0"} | MORLET_RECIPES
BASELINE_POLICY = "complete-pre-event-wavelet-support/1.0"
MAX_EVENTS = 10000
MAX_ARRAY_VALUES = 500000
MAX_EPOCH_VALUES = 10000000
MAX_TFR_WORK = 40000000


class DelimitedSource:
    """Select the declared delimiter even for content-addressed extensionless files."""
    def __init__(self,path,source_format): self.path=path; self.suffix="."+source_format
    def open(self,*args,**kwargs): return self.path.open(*args,**kwargs)


def text(value, limit=4000):
    return isinstance(value, str) and bool(value.strip()) and len(value) <= limit


def window(value, name, low, high):
    require(isinstance(value, list) and len(value) == 2, f"{name} requires two explicit endpoints.")
    a, b = finite(value[0], name, low, high), finite(value[1], name, low, high)
    require(a < b, f"{name} endpoints must increase.")
    return a, b


def mask_window(times, bounds, inclusive=True):
    tolerance = 1e-10
    return (times >= bounds[0]-tolerance) & ((times <= bounds[1]+tolerance) if inclusive else (times < bounds[1]-tolerance))


def settings(supplied, fs, channels):
    require(isinstance(supplied, dict) and supplied.get("recipe") in RECIPES, "Select an implemented versioned neural recipe.")
    common = {"recipe", "event_codes", "event_source", "epoch_s", "baseline_s", "reference", "filter", "rejection",
              "minimum_trials", "overlap_policy", "settings_source", "event_tolerance_s"}
    specific = {"eeg-erp-epochs/1.0": {"amplitude_window_s", "peak_polarity"},
                "eeg-morlet-epochs/1.0": {"frequencies_hz", "n_cycles", "power", "power_baseline", "summary_window_s"},
                "eeg-morlet-epochs/1.1": {"frequencies_hz", "n_cycles", "power", "power_baseline", "summary_window_s"},
                "eeg-frequency-tagging/1.0": {"spectral_window_s", "tag_frequencies_hz", "harmonics", "window", "noise_neighbor_bins", "noise_skip_bins", "max_bin_offset_hz"}}[supplied["recipe"]]
    require(not (set(supplied)-common-specific), "Unknown neural recipe setting; no parameter is silently ignored.")
    require((common-{"event_tolerance_s"}) <= set(supplied) and specific <= set(supplied), "Neural recipes require explicit reference, filter, epoch, baseline, rejection and method settings.")
    p = copy.deepcopy(supplied)
    require(text(p["settings_source"]) and text(p["event_source"]), "Declare protocol/settings and event timing provenance.")
    require(isinstance(p["event_codes"], dict) and 1 <= len(p["event_codes"]) <= 100 and
            all(text(k,128) and text(v,128) for k,v in p["event_codes"].items()), "event_codes must map 1 to 100 source codes to condition IDs.")
    lo, hi = window(p["epoch_s"], "epoch_s", -60, 120)
    require(lo <= 0 <= hi, "Epochs must include their event onset.")
    require(all(abs(t*fs-round(t*fs)) < 1e-7 for t in (lo,hi)), "Epoch endpoints must lie on the declared sample grid.")
    if p["baseline_s"] is not None:
        window(p["baseline_s"], "baseline_s", lo, hi)
        require(p["baseline_s"][1] <= 0, "Voltage baseline must end at or before event onset.")
    require(isinstance(p["minimum_trials"],int) and not isinstance(p["minimum_trials"],bool) and 1 <= p["minimum_trials"] <= MAX_EVENTS, "minimum_trials must be a positive integer.")
    require(p["overlap_policy"] in {"allow","reject"}, "Declare the overlapping-epoch policy.")
    p["event_tolerance_s"] = finite(p.get("event_tolerance_s", .5/fs), "event_tolerance_s", 0, .5/fs)
    reference = p["reference"]
    require(isinstance(reference,dict) and set(reference) <= {"mode","source","channels"} and
            reference.get("mode") in {"acquisition","average","channels"} and text(reference.get("source")), "Declare acquisition, average or named-channel reference and provenance.")
    if reference["mode"] == "average": require(len(channels) >= 2, "Average reference requires at least two declared channels.")
    if reference["mode"] == "channels":
        refs = reference.get("channels")
        require(isinstance(refs,list) and refs and all(c in channels for c in refs) and len(refs)==len(set(refs)), "Named reference channels must be unique selected source channels.")
    else: require("channels" not in reference, "Reference channels only apply to named-channel referencing.")
    filt = p["filter"]
    require(isinstance(filt,dict) and filt.get("mode") in {"none","butterworth_bandpass"}, "Declare filter mode none or butterworth_bandpass.")
    if filt["mode"] == "none": require(set(filt)=={"mode"}, "Disabled filtering cannot carry ignored filter settings.")
    else:
        require(set(filt)=={"mode","low_hz","high_hz","order","edge_exclusion_s"}, "Bandpass requires explicit cutoffs, order and edge exclusion.")
        finite(filt["low_hz"], "filter low_hz", .01, fs/2)
        finite(filt["high_hz"], "filter high_hz", filt["low_hz"]+.001, fs/2-.001)
        require(isinstance(filt["order"],int) and not isinstance(filt["order"],bool) and 1 <= filt["order"] <= 8, "Filter order must be 1 to 8.")
        finite(filt["edge_exclusion_s"], "filter edge_exclusion_s", 3/filt["low_hz"], 600)
    reject = p["rejection"]
    require(isinstance(reject,dict) and set(reject)=={"window_s","peak_to_peak_uv","flat_uv"}, "Rejection requires a window and explicit peak-to-peak/flat thresholds (null disables a threshold).")
    window(reject["window_s"], "rejection window", lo, hi)
    for field in ("peak_to_peak_uv","flat_uv"):
        if reject[field] is not None: finite(reject[field], field, .000001, 1e9)
    require(reject["peak_to_peak_uv"] is None or reject["flat_uv"] is None or reject["flat_uv"] < reject["peak_to_peak_uv"], "Flat threshold must be below peak-to-peak rejection threshold.")
    if p["recipe"] == "eeg-erp-epochs/1.0":
        window(p["amplitude_window_s"], "amplitude_window_s", lo, hi)
        require(p["peak_polarity"] in {"positive","negative","absolute","none"}, "Declare ERP peak polarity, or disable peak extraction.")
    elif p["recipe"] in MORLET_RECIPES:
        freqs=p["frequencies_hz"]; cycles=p["n_cycles"]
        require(isinstance(freqs,list) and 1 <= len(freqs) <= 40, "Declare 1 to 40 increasing Morlet frequencies.")
        for f in freqs: finite(f,"Morlet frequency",.1,fs/2-.001)
        require(all(a < b for a,b in zip(freqs,freqs[1:])), "Morlet frequencies must strictly increase.")
        require(isinstance(cycles,list) and len(cycles)==len(freqs), "n_cycles requires one value per frequency.")
        for n in cycles: finite(n,"n_cycles",1,30)
        require(p["power"] in {"total","induced"}, "Select total or evoked-subtracted induced power.")
        window(p["summary_window_s"],"summary_window_s",lo,hi)
        b=p["power_baseline"]
        require(isinstance(b,dict) and b.get("mode") in {"none","subtract","ratio","percent","db"}, "Select an explicit Morlet power baseline transform.")
        if b["mode"]=="none": require(set(b)=={"mode"}, "Disabled power baseline cannot carry ignored settings.")
        else:
            reviewed=p["recipe"]=="eeg-morlet-epochs/1.1"
            require(set(b)=={"mode","window_s","minimum_power_uv2"} | ({"adequacy"} if reviewed else set()), "Power baseline requires window, denominator floor and, for Morlet 1.1, an explicit duration review.")
            window(b["window_s"],"power baseline",lo,hi)
            require(b["window_s"][1] <= 0, "Power baseline must end at or before the event.")
            finite(b["minimum_power_uv2"],"minimum_power_uv2",0,1e12)
            if reviewed:
                a=b["adequacy"]
                require(isinstance(a,dict) and set(a)=={"policy","minimum_cycles","rationale"} and a["policy"]==BASELINE_POLICY and text(a["rationale"]),
                        "Declare the named baseline support policy and a study-specific duration rationale; this declaration does not establish scientific validity.")
                finite(a["minimum_cycles"],"minimum baseline cycles at the lowest frequency",.000001,1e6)
    else:
        window(p["spectral_window_s"],"spectral_window_s",lo,hi)
        require(p["window"] in {"hann","boxcar"}, "Declare Hann or boxcar spectral window.")
        require(isinstance(p["tag_frequencies_hz"],list) and 1 <= len(p["tag_frequencies_hz"]) <= 20, "Declare 1 to 20 tag frequencies.")
        for f in p["tag_frequencies_hz"]: finite(f,"tag frequency",.1,fs/2-.001)
        require(len(p["tag_frequencies_hz"])==len(set(p["tag_frequencies_hz"])), "Tag frequencies must be unique.")
        require(isinstance(p["harmonics"],list) and p["harmonics"] and all(isinstance(h,int) and not isinstance(h,bool) and 1 <= h <= 10 for h in p["harmonics"]) and len(set(p["harmonics"]))==len(p["harmonics"]), "Declare unique positive integer harmonics up to 10.")
        require(max(p["tag_frequencies_hz"])*max(p["harmonics"]) < fs/2, "Every requested harmonic must be below Nyquist.")
        for field, low in (("noise_neighbor_bins",1),("noise_skip_bins",0)):
            require(isinstance(p[field],int) and not isinstance(p[field],bool) and low <= p[field] <= 100, f"{field} must be an integer in the supported range.")
        finite(p["max_bin_offset_hz"],"max_bin_offset_hz",0,fs/2)
    return p


def events_for(recordings, path, metadata, source_format):
    column=metadata.get("event_column"); explicit=metadata.get("events")
    require(bool(column) != (explicit is not None), "Supply exactly one event_column or explicit events array.")
    result={r["id"]:[] for r in recordings}
    if column:
        require(source_format in {"csv","tsv"} and text(column,500), "event_column is supported only for CSV/TSV onsets.")
        forbidden={metadata.get("time_column"), *metadata["value_columns"], *(metadata.get(k) for k in ("participant_column","session_column","condition_column","exposure_column","segment_column"))}
        require(column not in forbidden, "Event onset codes need a distinct source column.")
        with path.open("r",encoding="utf-8-sig",newline="") as stream:
            reader=csv.DictReader(stream,delimiter="\t" if source_format=="tsv" else ",")
            require(column in reader.fieldnames,"The declared event column is absent.")
            recording_index=0
            for row_index,row in enumerate(reader):
                while recording_index+1<len(recordings) and row_index>=recordings[recording_index+1]["source_row_start"]: recording_index+=1
                code=row[column].strip()
                if code in io.MISSING: continue
                r=recordings[recording_index]; i=row_index-r["source_row_start"]
                result[r["id"]].append({"time_s":float(r["times"][i]),"code":code,"source_sample_index":r["source_row_start"]+i})
    else:
        require(isinstance(explicit,list) and len(explicit)<=MAX_EVENTS,"events must be a bounded array of onset objects.")
        for event in explicit:
            require(isinstance(event,dict) and set(event)<={"time_s","code","recording_id","id"}, "Explicit events support only time_s, code, recording_id and optional id.")
            require(text(event.get("code"),128),"Event codes must be nonempty strings; numeric codes must be encoded explicitly as strings.")
            finite(event.get("time_s"),"event time_s",0,1e12)
            if "id" in event: require(text(event["id"],128),"Event id must be a bounded string.")
            recording_id=event.get("recording_id",recordings[0]["id"] if len(recordings)==1 else None)
            require(recording_id in result,"Events in multiple recording segments require an explicit recording_id.")
            result[recording_id].append(dict(event))
    require(0<sum(map(len,result.values()))<=MAX_EVENTS,"Supply 1 to 10,000 measured event onsets.")
    for events in result.values():
        require(all(text(e["code"],128) for e in events),"Event codes must be bounded strings.")
        require(all(a["time_s"] < b["time_s"] for a,b in zip(events,events[1:])),"Event times must strictly increase per recording; simultaneous or reordered codes require a different event recipe.")
        ids=[e["id"] for e in events if "id" in e]
        require(len(ids)==len(set(ids)),"Explicit event IDs must be unique per recording.")
    return result


def preprocess(r,metadata,p):
    times=r["times"]; fs=r["fs"]; raw=r["values"]
    require(len(times)>1,"Every recording segment needs at least two samples.")
    _,quality=io.continuous_segments(r,0,metadata,"eeg")
    gaps=np.diff(times)>1.5/fs
    valid=np.isfinite(raw).all(axis=0)
    starts=np.flatnonzero(valid & np.r_[True, ~valid[:-1] | gaps])
    result=np.full_like(raw,np.nan); support=np.zeros(len(times),bool); segment_ids=np.full(len(times),-1,int)
    spans=[]; filt=p["filter"]; ref=p["reference"]
    sos=None
    if filt["mode"]!="none": sos=signal.butter(filt["order"],[filt["low_hz"],filt["high_hz"]],btype="bandpass",fs=fs,output="sos")
    for segment_id,start in enumerate(starts):
        end=start+1
        while end<len(times) and valid[end] and not gaps[end-1]: end+=1
        x=raw[:,start:end].copy()
        if ref["mode"]=="average": x-=x.mean(axis=0,keepdims=True)
        elif ref["mode"]=="channels": x-=x[[r["channels"].index(c) for c in ref["channels"]]].mean(axis=0,keepdims=True)
        edge=int(math.ceil(filt["edge_exclusion_s"]*fs)) if sos is not None else 0
        span={"start_sample":int(start),"end_sample_exclusive":int(end),"edge_samples_each_side":edge}
        if end-start<=2*edge+2:
            spans.append({**span,"status":"unavailable","reason":"too_short_after_filter_edges"}); continue
        if sos is not None:
            try: x=signal.sosfiltfilt(sos,x,axis=-1,padtype="odd")
            except ValueError:
                spans.append({**span,"status":"unavailable","reason":"too_short_for_filter_padding"}); continue
        require(np.isfinite(x).all(),"Preprocessing returned a nonfinite signal.")
        result[:,start:end]=x
        support[start+edge:end-edge]=True; segment_ids[start+edge:end-edge]=segment_id
        spans.append({**span,"status":"computed"})
    return result,support,segment_ids,{**quality,"joint_missing_samples":int((~valid).sum()),"continuous_spans":spans,
        "filter_sos":sos.tolist() if sos is not None else None,"filter_phase":"forward_backward_zero_phase" if sos is not None else "none"}


def collect_epochs(r,events,metadata,p):
    x,support,segments,quality=preprocess(r,metadata,p)
    fs=r["fs"]; start_offset=int(round(p["epoch_s"][0]*fs)); end_offset=int(round(p["epoch_s"][1]*fs))
    times=np.arange(start_offset,end_offset+1)/fs
    require(len(times)*len(r["channels"])*len(events)<=MAX_EPOCH_VALUES,"Requested epoch array exceeds the bounded job limit; split the recording job.")
    rejmask=mask_window(times,p["rejection"]["window_s"])
    require(rejmask.sum()>=2,"Rejection window requires at least two sampled points.")
    if p["baseline_s"] is not None: require(mask_window(times,p["baseline_s"]).any(),"Voltage baseline contains no sampled point.")
    trials=[]; retained=[]; logs=[]; last_end=None; aligned_samples=set()
    for i,event in enumerate(events):
        code=event["code"]; condition=p["event_codes"].get(code)
        log={"trial_id":event.get("id",f"{r['id']}-event-{i+1}"),"event_code":code,"condition_id":condition,
             "event_time_s":event["time_s"],"recording_id":r["id"],"group":r["group"],"origin":metadata.get("origin","unspecified")}
        if condition is None: logs.append({**log,"status":"excluded","reason":"unmapped_event_code"}); continue
        if r["group"].get("condition_id"):
            require(condition==r["group"]["condition_id"],"Mapped event condition disagrees with the source recording condition.")
        insertion=int(np.searchsorted(r["times"],event["time_s"]))
        candidates=[j for j in (insertion-1,insertion) if 0<=j<len(r["times"])]
        index=min(candidates,key=lambda j:abs(r["times"][j]-event["time_s"]))
        error=float(r["times"][index]-event["time_s"])
        log.update(source_sample_index=r["source_row_start"]+index,aligned_time_s=float(r["times"][index]),alignment_error_s=error)
        a,b=index+start_offset,index+end_offset+1
        reason=None
        if abs(error)>p["event_tolerance_s"]+1e-12: reason="event_outside_sample_alignment_tolerance"
        elif a<0 or b>len(r["times"]): reason="epoch_outside_recording"
        elif not support[a:b].all() or len(set(segments[a:b]))!=1: reason="missing_gap_annotation_or_filter_edge"
        elif p["overlap_policy"]=="reject" and last_end is not None and a<last_end: reason="overlapping_epoch"
        if reason: logs.append({**log,"status":"excluded","reason":reason}); continue
        require(index not in aligned_samples,"Multiple events align to the same source sample; repeated-event handling is not implicit.")
        aligned_samples.add(index)
        # The overlap policy is geometric and does not depend on whether a trial
        # later fails amplitude rejection. That avoids outcome-dependent overlap.
        last_end=b
        epoch=x[:,a:b]
        ptp=np.ptp(epoch[:,rejmask],axis=-1)*1e6
        # A rereferenced electrode can be mathematically zero. Flat screening
        # concerns the observed source channel, not a zero created by reference.
        source_ptp=np.ptp(r["values"][:,a:b][:,rejmask],axis=-1)*1e6
        bad=[]
        for c,value,source_value in zip(r["channels"],ptp,source_ptp):
            if p["rejection"]["peak_to_peak_uv"] is not None and value>p["rejection"]["peak_to_peak_uv"]: bad.append({"channel":c,"reason":"peak_to_peak","value_uv":float(value)})
            if p["rejection"]["flat_uv"] is not None and source_value<p["rejection"]["flat_uv"]: bad.append({"channel":c,"reason":"flat","value_uv":float(source_value),"screening_stage":"original_source_voltage"})
        if bad: logs.append({**log,"status":"excluded","reason":"amplitude_rejection","channels":bad}); continue
        trials.append(epoch); retained.append({**log,"status":"retained","reason":None})
        logs.append(retained[-1])
    return np.asarray(trials),times,retained,logs,quality


def clean_array(array):
    a=np.asarray(array)
    return np.where(np.isfinite(a),a,None).tolist()


class BaselineSupportError(InputError):
    def __init__(self, message, derived):
        super().__init__(message)
        self.derived_settings=derived


def morlet_baseline_support(times, p, fs, wavelets):
    """A finite-kernel separation policy, not a universal baseline recommendation.

    Duration is last sampled centre minus first, not N/fs. Using actual discrete
    wavelet lengths makes an onset-touching kernel fail even at a grid boundary.
    This cannot rule out smearing from earlier acquisition or zero-phase filters.
    """
    b=p["power_baseline"]; enabled=b["mode"]!="none"
    indices=np.flatnonzero(mask_window(times,b["window_s"])) if enabled else np.array([],dtype=int)
    duration=float((indices[-1]-indices[0])/fs) if len(indices) else None
    rows=[]
    for f,n,w in zip(p["frequencies_hz"],p["n_cycles"],wavelets):
        half=(len(w)-1)//2; sigma=float(n/(2*np.pi*f))
        first=int(indices[0])-half if len(indices) else None
        last=int(indices[-1])+half if len(indices) else None
        # The epoch includes onset on its declared grid. Strictly earlier than
        # that integer index excludes the onset sample as well as later samples.
        before=bool(last < round(-p["epoch_s"][0]*fs)) if last is not None else None
        rows.append({"frequency_hz":f,"n_cycles":n,"temporal_sigma_s":sigma,
            "kernel_samples":len(w),"half_support_s":half/fs,
            "baseline_cycles":duration*f if duration is not None else None,
            "centre_separation_sigma":float(-times[indices[-1]]/sigma) if len(indices) else None,
            "latest_kernel_sample_s":float(p["epoch_s"][0]+last/fs) if last is not None else None,
            "complete_epoch_support":bool(first>=0 and last<len(times)) if first is not None else None,
            "strictly_before_event":before})
    observed_cycles=duration*min(p["frequencies_hz"]) if duration is not None else None
    duration_ok=bool(observed_cycles is not None and observed_cycles+1e-10>=b["adequacy"]["minimum_cycles"]) if enabled else None
    eligible=bool(len(indices)>=2 and duration_ok and all(r["complete_epoch_support"] and r["strictly_before_event"] for r in rows)) if enabled else None
    return {"policy":BASELINE_POLICY,"status":"eligible" if eligible else "unavailable" if enabled else "not_applied",
        "mode":b["mode"],"baseline_sample_count":len(indices),
        "first_sample_s":float(times[indices[0]]) if len(indices) else None,
        "last_sample_s":float(times[indices[-1]]) if len(indices) else None,
        "sample_span_s":duration,"duration_convention":"last sample centre minus first sample centre",
        "cycles_at_lowest_frequency":observed_cycles,
        "minimum_cycles":b["adequacy"]["minimum_cycles"] if enabled else None,
        "rationale":b["adequacy"]["rationale"] if enabled else None,
        "duration_criterion_met":duration_ok,"frequencies":rows,
        "filter_mode":p["filter"]["mode"],
        "scope":"Finite Morlet kernel support only. Prior filtering, including forward/backward zero-phase filters, can spread activity in time. Event timing and baseline suitability require study-specific review; eligibility is not scientific qualification."}


def analyse_cell(epochs,times,p,fs):
    features=[]; series=[]; channels=epochs.ch_names; data=epochs.get_data(copy=True); count=len(epochs)
    def add(name,value,unit,channel,**extra):
        features.append({"name":name,"value":io.number(value),"unit":unit,"channel":channel,"scope":"recording_condition","trial_count":count,**extra})
    if p["recipe"]=="eeg-erp-epochs/1.0":
        waveform=epochs.average().data*1e6
        sem=data.std(axis=0,ddof=1)*1e6/math.sqrt(count) if count>1 else np.full_like(waveform,np.nan)
        selected=mask_window(times,p["amplitude_window_s"])
        require(selected.any(),"ERP amplitude window contains no sampled points.")
        indices=np.flatnonzero(selected)
        for ci,c in enumerate(channels):
            values=waveform[ci,selected]
            add("erp_mean_amplitude",values.mean(),"uV",c,window_s=p["amplitude_window_s"])
            if p["peak_polarity"]!="none":
                score=values if p["peak_polarity"]=="positive" else -values if p["peak_polarity"]=="negative" else np.abs(values)
                peak=int(np.argmax(score)); eligible=p["peak_polarity"]=="absolute" or score[peak]>0
                add("erp_peak_amplitude",values[peak] if eligible else None,"uV",c,polarity=p["peak_polarity"],edge_peak=peak in (0,len(values)-1),missing_reason=None if eligible else "no_requested_polarity")
                add("erp_peak_latency",times[indices[peak]] if eligible else None,"s",c,polarity=p["peak_polarity"])
            series.append({"type":"erp","channel":c,"time_s":times.tolist(),"mean_uv":waveform[ci].tolist(),"sem_uv":clean_array(sem[ci]),"trial_count":count,"sem_scope":"within_recording_trials; not participant inference"})
        return features,series,{}
    if p["recipe"] in MORLET_RECIPES:
        mne=io.require_mne(); freqs=p["frequencies_hz"]; cycles=p["n_cycles"]
        wavelets=mne.time_frequency.morlet(fs,freqs,n_cycles=cycles,zero_mean=True)
        half=max((len(w)-1)//2 for w in wavelets)
        derived={"wavelet_samples":[len(w) for w in wavelets],"edge_exclusion_samples_each_side":half,"power_normalization_order":"average trial power, then baseline transform","decimation":1,"zero_mean":True}
        if p["recipe"]=="eeg-morlet-epochs/1.1":
            support=morlet_baseline_support(times,p,fs,wavelets); derived["baseline_support"]=support
            if support["status"]=="unavailable":
                raise BaselineSupportError("Morlet 1.1 baseline is unavailable: it needs at least two samples, the declared duration, complete epoch wavelet support and every kernel strictly before event onset. Choose an earlier baseline, lengthen the epoch, or select no power baseline; inspect saved baseline_support for actual duration and per-frequency separation.",derived)
        require(2*half+2<len(times),"Epoch has insufficient support after the complete Morlet wavelet edges are excluded.")
        require(data.size*len(freqs)<=MAX_TFR_WORK,"Morlet trial/channel/frequency workload exceeds the bounded job limit.")
        valid=np.zeros(len(times),bool); valid[half:len(times)-half]=True
        selected=mask_window(times,p["summary_window_s"])
        require(selected.any() and np.all(valid[selected]),"The Morlet summary window intersects unsupported wavelet edges.")
        b=p["power_baseline"]
        if b["mode"]!="none":
            baseline=mask_window(times,b["window_s"])
            require(baseline.sum()>=2 and np.all(valid[baseline]),"The Morlet power baseline needs two samples and complete wavelet support.")
        mean_wave=data.mean(axis=0)
        power_sum=np.zeros((len(channels),len(freqs),len(times)))
        phase_sum=np.zeros_like(power_sum,dtype=complex); phase_count=np.zeros_like(power_sum,dtype=int)
        for trial in data:
            z=mne.time_frequency.tfr_array_morlet(trial[None],fs,freqs,n_cycles=cycles,zero_mean=True,use_fft=True,decim=1,output="complex",n_jobs=1,verbose=False)[0]
            amplitude=np.abs(z); usable=amplitude>np.finfo(float).tiny
            phase_sum[usable]+=z[usable]/amplitude[usable]; phase_count+=usable
            if p["power"]=="induced":
                z=mne.time_frequency.tfr_array_morlet((trial-mean_wave)[None],fs,freqs,n_cycles=cycles,zero_mean=True,use_fft=True,decim=1,output="complex",n_jobs=1,verbose=False)[0]
            power_sum+=np.abs(z)**2
        power=power_sum/count*1e12
        itc=np.divide(np.abs(phase_sum),phase_count,out=np.full_like(power,np.nan),where=phase_count>=2)
        itc=np.minimum(itc,1)
        transformed=power.copy(); unit="uV^2 (wavelet power)"
        if b["mode"]!="none":
            base=power[:,:,baseline].mean(axis=-1,keepdims=True)
            eligible=base>b["minimum_power_uv2"]
            if b["mode"]=="subtract": transformed=power-base
            else:
                ratio=np.divide(power,base,out=np.full_like(power,np.nan),where=eligible)
                if b["mode"]=="ratio": transformed=ratio; unit="ratio"
                elif b["mode"]=="percent": transformed=(ratio-1)*100; unit="percent"
                else:
                    transformed=np.full_like(power,np.nan)
                    np.log10(ratio,out=transformed,where=ratio>0); transformed*=10; unit="dB"
            transformed=np.where(eligible,transformed,np.nan)
        for ci,c in enumerate(channels):
            for fi,f in enumerate(freqs):
                values=transformed[ci,fi,selected]
                add("morlet_power_mean",values.mean() if np.isfinite(values).all() else None,unit,c,frequency_hz=f,power=p["power"],window_s=p["summary_window_s"])
                phase=itc[ci,fi,selected]
                add("morlet_itc_mean",phase.mean() if np.isfinite(phase).all() else None,"proportion",c,frequency_hz=f,phase_scope="original total signal",minimum_phase_trials=int(phase_count[ci,fi,selected].min()))
            series.append({"type":"morlet","channel":c,"time_s":times[valid].tolist(),"frequency_hz":freqs,
                "power_uv2":clean_array(power[ci,:,valid].T),"transformed_power":clean_array(transformed[ci,:,valid].T),
                "itc":clean_array(itc[ci,:,valid].T),"array_axes":["frequency","time"],"transformed_unit":unit,"trial_count":count})
        return features,series,derived
    selected=mask_window(times,p["spectral_window_s"],inclusive=False)
    require(selected.sum()>=4,"Frequency tagging requires at least four sampled points inside the half-open spectral window.")
    psd,freqs=io.require_mne().time_frequency.psd_array_welch(data[:,:,selected],sfreq=fs,n_fft=int(selected.sum()),n_per_seg=int(selected.sum()),n_overlap=0,window=p["window"],average="mean",remove_dc=True,verbose=False)
    mean_psd=psd.mean(axis=0)*1e12; width=float(freqs[1]-freqs[0])
    targets=sorted(set(f*h for f in p["tag_frequencies_hz"] for h in p["harmonics"]))
    bins={f:int(np.argmin(abs(freqs-f))) for f in targets}
    require(len(set(bins.values()))==len(bins),"Requested tags/harmonics collide at this frequency resolution.")
    for f,k in bins.items():
        require(abs(freqs[k]-f)<=p["max_bin_offset_hz"]+1e-12,"Requested tag misses the allowed frequency-bin tolerance; revise the declared spectral window.")
    for ci,c in enumerate(channels):
        for f,k in bins.items():
            offsets=np.arange(p["noise_skip_bins"]+1,p["noise_skip_bins"]+p["noise_neighbor_bins"]+1)
            neighbors=np.r_[k-offsets,k+offsets]
            good=(neighbors>0)&(neighbors<len(freqs)-1)&~np.isin(neighbors,list(bins.values()))
            noise=float(mean_psd[ci,neighbors].mean()) if np.all(good) else None
            power=float(mean_psd[ci,k]); ratio=power/noise if noise is not None and noise>0 else None
            add("tag_bin_density",power,"uV^2/Hz",c,target_hz=f,actual_bin_hz=float(freqs[k]),frequency_bin_width_hz=width)
            add("tag_noise_density",noise,"uV^2/Hz",c,target_hz=f,noise_bins=freqs[neighbors].tolist() if np.all(good) else [],missing_reason=None if np.all(good) else "noise_neighbors_outside_spectrum_or_other_tag")
            add("tag_snr",ratio,"ratio",c,target_hz=f,missing_reason=None if ratio is not None else "unavailable_or_zero_noise_denominator")
        series.append({"type":"frequency_tagging_psd","channel":c,"frequency_hz":freqs.tolist(),"density_uv2_hz":mean_psd[ci].tolist(),"trial_count":count})
    return features,series,{"frequency_bin_width_hz":width,"n_fft":int(selected.sum()),"spectral_window_policy":"half_open","remove_dc":True,"power_averaging":"mean trial density before SNR"}


def run(request):
    require(isinstance(request,dict) and request.get("schema")=="brohn-worker-request/1.0" and request.get("operation")=="neural" and request.get("modality")=="eeg","Neural worker requires brohn-worker-request/1.0, operation neural and modality eeg.")
    path=Path(request.get("source_path","")).resolve()
    require(path.is_file() and 0<path.stat().st_size<=io.MAX_FILE_BYTES,"Source is absent, empty or exceeds 512 MiB.")
    metadata=request.get("metadata"); source_format=request.get("format")
    require(isinstance(metadata,dict),"Explicit source metadata is required.")
    finite(metadata.get("sampling_rate"),"sampling_rate",1,100000)
    require(metadata.get("origin","unspecified") in {"sample","preview","pilot","live","imported","unspecified"},"Declare a supported source origin.")
    require(source_format in {"csv","tsv","edf","bdf","fif"},"Neural recipes support CSV/TSV or native EDF/BDF/FIF.")
    if source_format in {"csv","tsv"}:
        require(bool(metadata.get("participant_column"))==bool(metadata.get("session_column")),"Participant and session columns must be declared together.")
    else:
        require(bool(metadata.get("participant_id"))==bool(metadata.get("session_id")),"Participant and session identity must be declared together.")
    mne=io.require_mne()
    with warnings.catch_warnings(record=True) as caught:
        warnings.simplefilter("always")
        recordings,source=io.csv_recordings(DelimitedSource(path,source_format),metadata,"eeg") if source_format in {"csv","tsv"} else io.native_eeg(path,metadata,source_format)
        events=events_for(recordings,path,metadata,source_format)
        output={"schema":"brohn-worker-result/1.0","modality":"eeg","status":"completed",
            "engine":{"name":"Brohn neural worker","version":"1.0.0","python":platform.python_version(),"packages":io.versions(["numpy","scipy","mne"]),"worker_sha256":io.digest_file(Path(__file__)),"shared_io_sha256":io.digest_file(Path(io.__file__))},
            "source":{"sha256":io.digest_file(path),"bytes":path.stat().st_size,**source},"parameters":{},"features":[],"series":[],"events":[],"recordings":[],"artifacts":[]}
        total_requested=0; total_retained=0; computed=0; unavailable=0; arrays=0
        for r in recordings:
            p=settings(request.get("parameters",metadata.get("parameters")),r["fs"],r["channels"])
            output["parameters"][r["id"]]=p
            data,times,retained,logs,quality=collect_epochs(r,events[r["id"]],metadata,p)
            output["events"].extend(logs); total_requested+=len(logs); total_retained+=len(retained)
            for condition in dict.fromkeys(p["event_codes"].values()):
                indices=[i for i,e in enumerate(retained) if e["condition_id"]==condition]
                requested=sum(e["condition_id"]==condition for e in logs)
                identity={"recording_id":r["id"],"condition_id":condition,"group":r["group"],"origin":metadata.get("origin","unspecified")}
                summary={**identity,"source_time_origin":r["source_time_origin"],"source_row_start":r["source_row_start"],"sampling_rate":r["fs"],
                    "source_unit":r["source_unit"],"unit":"V","scale_factor":r["scale_factor"],"requested_trials":requested,"retained_trials":len(indices),
                    "excluded_trials":requested-len(indices),"minimum_trials":p["minimum_trials"],"sample_count_per_epoch":len(times),"quality":quality,
                    "participant_linkage":"declared_source_identity" if r["group"].get("participant_id") else "recording_only_no_participant_inference"}
                if len(indices)<p["minimum_trials"]:
                    output["recordings"].append({**summary,"status":"unavailable","reason":"insufficient_retained_trials"}); unavailable+=1; continue
                epochs=mne.EpochsArray(data[indices],mne.create_info(r["channels"],r["fs"],ch_types="eeg"),tmin=p["epoch_s"][0],baseline=tuple(p["baseline_s"]) if p["baseline_s"] is not None else None,proj=False,verbose=False)
                try: features,series,derived=analyse_cell(epochs,times,p,r["fs"])
                except InputError as error:
                    diagnostic={"derived_settings":error.derived_settings} if isinstance(error,BaselineSupportError) else {}
                    output["recordings"].append({**summary,"status":"unavailable","reason":str(error),**diagnostic}); unavailable+=1; continue
                for record in series:
                    arrays+=sum(np.asarray(value).size for value in record.values() if isinstance(value,list))
                require(arrays<=MAX_ARRAY_VALUES,"Neural result arrays exceed 500,000 inline values; split into smaller recording jobs.")
                output["features"].extend({**identity,**f} for f in features)
                output["series"].extend({**identity,**s} for s in series)
                output["recordings"].append({**summary,"status":"computed","derived_settings":derived}); computed+=1
        output["status"]="completed" if computed and not unavailable else "partial" if computed else "insufficient_support"
        output["quality"]={"usable":computed>0,"scientifically_qualified":False,"requires_research_review":True,"computed_recording_conditions":computed,"unavailable_recording_conditions":unavailable,
            "requested_event_count":total_requested,"retained_epoch_count":total_retained,"excluded_event_count":total_requested-total_retained,"array_values":arrays,
            "warnings":sorted({str(w.message)[:500] for w in caught})[:100],"participant_inference_performed":False}
        output["limitations"]=["Epochs and repeated trials are not independent people. Results stay within contiguous recording/condition cells; no group significance is inferred.",
            "Source origins and measured-event timing provenance are retained; no successful computation establishes device timing or scientific qualification.",
            "Jointly missing selected channels, native BAD annotations and time gaps exclude whole epochs. No filling, cross-gap filtering, ICA or automated repair occurs.",
            "Reference and filter settings are explicit. The declared artifact thresholds and filter edges require protocol/device review; amplitude screening does not detect every artifact.",
            "ERP peak windows and polarity are prespecified; a waveform feature is not an automatically identified psychological component.",
            "Morlet output is wavelet power, not PSD density. ITC depends on retained trial count and phase support; induced power subtracts the within-cell evoked waveform.",
            "Frequency tagging reports declared spectral bins and neighboring-bin SNR; harmonics, leakage and reference effects remain protocol dependent.",
            "No outputs supply causal emotion, universal attention, engagement, diagnosis or source-localized activation scores."]
        return output


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--request",required=True,type=Path); parser.add_argument("--output",required=True,type=Path)
    args=parser.parse_args(); code=0; safe=args.output.resolve()!=args.request.resolve()
    try:
        require(safe,"Output cannot replace request JSON.")
        require(args.request.is_file() and args.request.stat().st_size<=2*1024*1024,"Request exceeds 2 MiB.")
        def unique(pairs):
            result={}
            for k,v in pairs:
                require(k not in result,"Duplicate JSON object field."); result[k]=v
            return result
        request=json.loads(args.request.read_text(encoding="utf-8"),object_pairs_hook=unique,
            parse_constant=lambda x: (_ for _ in ()).throw(InputError("Nonfinite JSON values are not allowed.")))
        require(isinstance(request,dict),"Request must be a JSON object.")
        safe=args.output.resolve()!=Path(request.get("source_path","")).resolve()
        require(safe,"Output cannot replace source data.")
        result=run(request)
    except Exception as error:
        code=2; result={"schema":"brohn-worker-result/1.0","status":"error","error":{"type":type(error).__name__,"message":str(error)[:1000]},"quality":{"usable":False},"features":[],"events":[],"series":[],"artifacts":[]}
    if not safe:
        print(json.dumps(result),file=sys.stderr); return 2
    args.output.parent.mkdir(parents=True,exist_ok=True)
    descriptor,temporary=tempfile.mkstemp(prefix=".brohn-neural-",suffix=".json",dir=args.output.parent)
    try:
        with os.fdopen(descriptor,"w",encoding="utf-8",newline="\n") as stream:
            json.dump(result,stream,allow_nan=False,ensure_ascii=False); stream.write("\n")
        os.replace(temporary,args.output)
    finally:
        if os.path.exists(temporary): os.unlink(temporary)
    print(json.dumps({"status":result["status"],"features":len(result["features"])})); return code


if __name__=="__main__": raise SystemExit(main())
