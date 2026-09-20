"""Frozen-plan public PPG pulse-landmark agreement; production is never edited.

Use an isolated reader environment (numpy2.2.6, scipy1.15.3, wfdb4.3.0,
h5py3.14.0). Raw references and all results must remain outside this repository.
prepare freezes the protocol before run downloads/processes selected waveforms.
"""
import argparse
from datetime import datetime, timezone
import csv
import hashlib
import importlib.metadata
import json
from pathlib import Path
import subprocess
import urllib.request

import h5py
import numpy as np
from wfdb import processing

ROOT = Path(__file__).resolve().parents[2]
API = "https://borealisdata.ca/api/datasets/:persistentId/?persistentId=doi:10.5683/SP2/NLB8IT"
DOI = "https://doi.org/10.5683/SP2/NLB8IT"
RANKS = (1, 7, 13, 19, 25, 31, 37, 42)
RECORDS = ("0009", "0029", "0103", "0123", "0142", "0311", "0329", "0370")


def digest(path, algorithm="sha256"):
    h = hashlib.new(algorithm)
    with Path(path).open("rb") as stream:
        for piece in iter(lambda: stream.read(1024*1024), b""):
            h.update(piece)
    return h.hexdigest()


def save(path, value, exclusive=False):
    with Path(path).open("x" if exclusive else "w", encoding="utf-8") as stream:
        json.dump(value, stream, ensure_ascii=False, allow_nan=False, indent=2)
        stream.write("\n")


def download(url, maximum):
    with urllib.request.urlopen(url, timeout=60) as response:
        body = response.read(maximum+1)
    if not 0 < len(body) <= maximum:
        raise ValueError("Public source exceeds its download bound.")
    return body


def outside(path):
    path = path.resolve()
    if path == ROOT or ROOT in path.parents:
        raise ValueError("Reference data/results must stay outside the repository.")
    path.mkdir(parents=True, exist_ok=True)
    return path


def code_hashes():
    return {name: digest(ROOT / name) for name in
            ("scripts/workers/physiology.py", "scripts/workers/physiology_artifacts.py")}


def prepare(args):
    folder = outside(args.output)
    if (folder / "plan.json").exists():
        raise ValueError("A frozen plan already exists; never replace it after viewing results.")
    metadata = download(API, 2*1024**2)
    (folder / "dataset-metadata.json").write_bytes(metadata)
    version = json.loads(metadata)["data"]["latestVersion"]
    files = sorted((x["dataFile"] for x in version["files"] if x["dataFile"]["filename"].endswith("_8min.mat")), key=lambda x:x["filename"])
    assert len(files) == 42
    selected = [files[k-1] for k in RANKS]
    assert tuple(x["filename"][:4] for x in selected) == RECORDS
    readme = next(x["dataFile"] for x in version["files"] if x["dataFile"]["filename"] == "README.txt")
    (folder / "README-source.txt").write_bytes(download(f"https://borealisdata.ca/api/access/datafile/{readme['id']}", 100000))
    plan = {
        "schema":"brohn-ppg-reference-plan/1.0", "frozen_at":datetime.now(timezone.utc).isoformat(),
        "dataset":DOI, "dataset_api":API, "dataset_version":[version["versionNumber"],version["versionMinorNumber"]],
        "dataset_metadata_sha256":digest(folder / "dataset-metadata.json"),
        "selection":"Fixed lexicographic filename ranks; no selection on waveforms, annotations or detector results.",
        "selected_ranks_one_based":list(RANKS), "files":selected,
        "prior_inspection":"The original 2026-09-20 plan was frozen after only published docs/metadata and 0009 schema inspection. Results are now published in the repository; later executions of this released harness are technical repeats, not newly unseen held-out evidence. Retain/copy the original plan to reproduce its exact protocol identity.",
        "channel":"signal.pleth.y", "unit":"a.u.; retained source scale, no voltage calibration claimed",
        "sample_rate":"Read param.samplingrate.pleth; require300Hz; no resampling.",
        "input_range_s":[0,480], "evaluation_range_s":[2,478],
        "range_convention":"half-open; first144000 samples, excluding optional source endpoint at480s",
        "reference":"Human-rater labels.pleth.peak.x, not ECG detections or monitor rate trends",
        "reference_coordinates":"MATLAB sample indices: require integral1-based values; subtract1 for zero-based CSV/source sample indices. labels.units.x must equal samples. No alignment or lag fitting.",
        "primary_comparison":"One-to-one pulse systolic-peak matching at50ms outside source-labelled PPG artifact intervals",
        "secondary_tolerances_ms":[20,150], "primary_tolerance_ms":50,
        "matcher":"WFDB4.3.0 compare_annotations; not clinical/EC57 qualification",
        "artifact_policy":"Decode labels.pleth.artif.x as consecutive start/end sample pairs (published MATLAB vector or Nx2 array; transpose HDF storage); conservative inclusive endpoints. Remove labelled-artifact samples from primary event scoring. Report all-event comparison separately as descriptive; do not call detections inside labelled artifact verified false pulses. Do not concatenate artifact-free regions for intervals.",
        "endpoints":"Independent mean pulse interval, sample SD, RMSSD and reciprocal mean-interval pulse rate. Preserve300..2000ms profile plausibility screen and adjacency; separately report artifact-free endpoints with every interval intersecting labelled artifact excluded. No normal-to-normal claim.",
        "paired_intervals":"50ms matched consecutive events in both original event lists, excluding intervals crossing any labelled artifact; report signed/absolute interval error and95th percentile.",
        "production":{"profile":"ppg-elgendi-detected-prv/1.0","parameters":{"edge_exclusion_s":2,"interval_min_ms":300,"interval_max_ms":2000},
                      "method":"NeuroKit2 0.2.13 ppg_clean(elgendi), ppg_peaks(elgendi,correct_artifacts=False); unchanged defaults, original polarity/scale, no recentering or fitting"},
        "production_code_sha256":code_hashes(),
        "interpretation":"Descriptive external-reference agreement on8selected surgical-monitoring recordings. No threshold for universal qualification; no tuning, reference changes, NN/ECG-HRV substitution, stress inference or physical hardware claim.",
        "figures":"After results: first2..12seconds of every preselected record; any worst-case diagnostic explicitly post hoc and never used for tuning.",
    }
    save(folder / "plan.json", plan, True)
    (folder / "plan.sha256").write_text(digest(folder / "plan.json")+"\n", encoding="ascii")
    print(json.dumps({"frozen_plan_sha256":digest(folder/"plan.json"),"records":list(RECORDS)}), flush=True)


def hdf_array(file, name):
    dataset = file[name]
    if dataset.attrs.get("MATLAB_empty", 0):
        return np.empty((0, 0))
    return np.asarray(dataset[()]).T


def reference(path):
    with h5py.File(path, "r") as f:
        unit = "".join(chr(int(x)) for x in hdf_array(f,"labels/units/x").ravel())
        assert unit == "samples"
        fs = float(hdf_array(f,"param/samplingrate/pleth").item())
        assert fs == 300
        values = hdf_array(f,"signal/pleth/y").ravel()
        assert len(values) in (144000, 144001) and np.all(np.isfinite(values))
        peaks = hdf_array(f,"labels/pleth/peak/x").ravel()
        assert np.all(peaks == np.floor(peaks)) and np.all(np.diff(peaks)>0) and np.all((peaks>=1)&(peaks<=len(values)))
        raw_artifacts = hdf_array(f,"labels/pleth/artif/x")
        if raw_artifacts.size:
            # Published MATLAB artif.x is also a vector of alternating start/end
            # sample indices. This is representation decoding, not a new mask.
            if raw_artifacts.ndim==2 and 1 in raw_artifacts.shape:
                assert raw_artifacts.size%2==0
                raw_artifacts=raw_artifacts.ravel().reshape(-1,2)
            assert raw_artifacts.ndim==2 and raw_artifacts.shape[1]==2
            assert np.all(np.isfinite(raw_artifacts)) and np.all(raw_artifacts == np.floor(raw_artifacts))
            assert np.all(raw_artifacts[:,0] <= raw_artifacts[:,1]) and np.all((raw_artifacts>=1)&(raw_artifacts<=len(values)))
            artifacts = raw_artifacts.astype(np.int64)-1
        else:
            artifacts = np.empty((0,2),dtype=np.int64)
        peaks = peaks.astype(np.int64)-1
        age = float(hdf_array(f,"meta/subject/age").item())
    return values[:144000], int(fs), peaks, artifacts, "adult" if age>=18 else "paediatric"


def in_artifact(peaks, artifacts):
    mask = np.zeros(len(peaks),dtype=bool)
    for start,end in artifacts:
        mask |= (peaks>=start)&(peaks<=end)
    return mask


def interval_available(peaks, artifacts):
    valid = np.ones(max(0,len(peaks)-1),dtype=bool)
    for start,end in artifacts:
        valid &= ~((peaks[:-1]<=end)&(peaks[1:]>=start))
    return valid


def metrics(peaks, fs, artifacts=()):
    intervals=np.diff(peaks)*1000/fs
    available=interval_available(peaks,artifacts)
    valid=(intervals>=300)&(intervals<=2000)&available
    values=intervals[valid]; differences=np.diff(intervals)[valid[:-1]&valid[1:]]
    return {"mean_interval":float(values.mean()) if len(values) else None,
            "sd_interval":float(values.std(ddof=1)) if len(values)>1 else None,
            "rmssd":float(np.sqrt(np.mean(differences**2))) if len(differences) else None,
            "rate_from_mean_interval":float(60000/values.mean()) if len(values) else None,
            "retained_interval_count":int(valid.sum()),"successive_pair_count":len(differences),
            "artifact_intersecting_interval_count":int((~available).sum()),
            "interval_count":len(intervals)}


def comparison(ref, det, fs, tolerance_ms):
    match=processing.compare_annotations(ref,det,int(tolerance_ms*fs/1000))
    error=(match.matched_test_sample-match.matched_ref_sample)*1000/fs
    assert match.tp+match.fn==len(ref) and match.tp+match.fp==len(det)
    result={"tolerance_ms":tolerance_ms,"tolerance_rule":"absolute sample difference strictly less than the declared window; exact boundary excluded", "matched":int(match.tp),"unmatched_detected":int(match.fp),"missed_reference":int(match.fn),
            "recall":float(match.sensitivity),"precision":float(match.positive_predictivity),
            "median_signed_ms":float(np.median(error)) if len(error) else None,
            "median_absolute_ms":float(np.median(abs(error))) if len(error) else None,
            "p95_absolute_ms":float(np.percentile(abs(error),95)) if len(error) else None}
    return result,match


def read_event_artifact(manifest):
    path=Path(manifest["path"])
    assert digest(path)==manifest["sha256"] and path.stat().st_size==manifest["bytes"]
    active=None; table_count=0; row_count=0; events=[]; declarations=[]; closed=False
    with path.open(encoding="utf-8") as stream:
        header=json.loads(next(stream));assert header["kind"]=="physiology-events"
        for line in stream:
            item=json.loads(line);assert not closed
            if item["type"]=="table":
                assert active is None;active=item;offset=0;table_count+=1;declarations.append(item)
            elif item["type"]=="rows":
                assert item["table_id"]==active["table_id"] and item["offset"]==offset
                names=[x["name"] for x in active["columns"]]
                for row in item["rows"]:
                    assert len(row)==len(names)
                    value=dict(zip(names,row))
                    if value["type"]=="systolic_pulse_peak":events.append(value)
                offset+=len(item["rows"]);row_count+=len(item["rows"])
            elif item["type"]=="table_end":
                assert item["rows"]==offset==active["expected_rows"];active=None
            elif item["type"]=="complete":
                assert active is None and item["rows"]==row_count==manifest["rows"] and item["tables"]==table_count==manifest["tables"];closed=True
            else:raise ValueError("Unexpected artifact record")
    assert closed and digest(path)==manifest["sha256"]
    return events,declarations


def run(args):
    folder=outside(args.output);plan_path=folder/"plan.json"
    assert digest(plan_path)==(folder/"plan.sha256").read_text(encoding="ascii").strip()
    plan=json.loads(plan_path.read_text(encoding="utf-8"))
    assert plan["production_code_sha256"]==code_hashes()
    if (folder/"results.json").exists():raise ValueError("Retain completed evidence; use a new frozen output for a new evaluation.")
    source=folder/"source";source.mkdir(exist_ok=True)
    results=[]
    for entry in plan["files"]:
        name=entry["filename"];record=name[:4];original=source/name
        if not original.exists():
            original.write_bytes(download(f"https://borealisdata.ca/api/access/datafile/{entry['id']}",2*1024**2))
        assert original.stat().st_size==entry["filesize"] and digest(original,"md5")==entry["md5"]
        values,fs,allref,artifacts,group=reference(original)
        ref=allref[(allref>=2*fs)&(allref<478*fs)]
        work=folder/record;work.mkdir(exist_ok=True);(work/"complete").mkdir(exist_ok=True)
        csv_path=work/"reference-ppg.csv"
        if args.resume and (work/"agreement.json").exists():
            retained=json.loads((work/"agreement.json").read_text(encoding="utf-8"))
            assert retained["record"]==record and retained["source_sha256"]==digest(original)
            # Historical evidence called the result-file digest worker_sha256.
            # Production source digests live in plan.production_code_sha256.
            result_hash=retained.get("worker_result_sha256",retained.get("worker_sha256"))
            assert retained["prepared_csv_sha256"]==digest(csv_path) and result_hash==digest(work/"worker-result.json")
            read_event_artifact(retained["event_artifact"])
            results.append(retained)
            print(json.dumps({"retained_completed_record":record}),flush=True)
            continue
        with csv_path.open("w",encoding="utf-8",newline="") as stream:
            writer=csv.writer(stream);writer.writerow(["seconds","ppg_au"])
            writer.writerows((i/fs,float(value)) for i,value in enumerate(values))
        request={"schema":"brohn-worker-request/1.0","operation":"physiology","modality":"ppg","source_path":str(csv_path),"format":"csv","artifact_directory":str(work/"complete"),
                 "metadata":{"time_column":"seconds","time_unit":"s","sampling_rate":fs,"value_columns":["ppg_au"],"unit":"a.u.","origin":"public_reference"},
                 "parameters":plan["production"]["parameters"],"origin":"public_reference"}
        save(work/"request.json",request)
        child=subprocess.run([str(args.methods_python),str(ROOT/"scripts/workers/physiology.py"),"--request",str(work/"request.json"),"--output",str(work/"worker-result.json")],cwd=ROOT,capture_output=True,text=True,timeout=180)
        (work/"worker.log").write_text(child.stdout+child.stderr,encoding="utf-8")
        if child.returncode:raise RuntimeError(child.stdout+child.stderr)
        assert plan["production_code_sha256"]==code_hashes()
        output=json.loads((work/"worker-result.json").read_text(encoding="utf-8"))
        assert output["status"]=="completed" and len(output["recordings"])==1 and output["recordings"][0]["status"]=="computed"
        parameter_sets=list(output["parameters"].values())
        assert len(parameter_sets)==1 and parameter_sets[0]["recipe"]=="ppg-elgendi-detected-prv/1.0"
        event_manifest=next(x for x in output["artifacts"] if x["kind"]=="physiology-events")
        events,tables=read_event_artifact(event_manifest)
        detected=np.array([x["source_sample_index"] for x in events],dtype=np.int64)
        assert np.all(np.diff(detected)>0) and np.all((detected>=2*fs)&(detected<478*fs))
        assert len(detected)==output["recordings"][0]["detected_peak_count"]
        features={x["name"]:x["value"] for x in output["features"]}
        independent=metrics(detected,fs)
        for name,value in independent.items():
            if name=="artifact_intersecting_interval_count":continue
            got=features["detected_prv_"+name]
            assert (got is None and value is None) or np.isclose(got,value,rtol=1e-12,atol=1e-10)
        ref_good=ref[~in_artifact(ref,artifacts)];det_good=detected[~in_artifact(detected,artifacts)]
        primary=[];descriptive=[]
        for tolerance in (20,50,150):
            cmp,matched=comparison(ref_good,det_good,fs,tolerance);primary.append(cmp)
            descriptive.append(comparison(ref,detected,fs,tolerance)[0])
            if tolerance==50:paired=matched
        # Original index adjacency and explicit interval intersection prevent
        # treating removals, missed/extra beats or artifact gaps as RR/PP pairs.
        pairs=sorted(zip(paired.matched_ref_sample,paired.matched_test_sample))
        lookup_r={x:i for i,x in enumerate(ref)};lookup_d={x:i for i,x in enumerate(detected)}
        errors=[]
        for (r0,d0),(r1,d1) in zip(pairs[:-1],pairs[1:]):
            if lookup_r[r1]-lookup_r[r0]==1 and lookup_d[d1]-lookup_d[d0]==1 and interval_available(np.array([r0,r1]),artifacts)[0] and interval_available(np.array([d0,d1]),artifacts)[0]:
                errors.append(((d1-d0)-(r1-r0))*1000/fs)
        errors=np.asarray(errors)
        endpoint_comparison={}
        for label,mask in (("full_record",()),("artifact_free_intervals",artifacts)):
            r=metrics(ref,fs,mask);d=metrics(detected,fs,mask)
            endpoint_comparison[label]={"reference":r,"detected":d,"differences":{key:d[key]-r[key] if d[key] is not None and r[key] is not None else None for key in ("mean_interval","sd_interval","rmssd","rate_from_mean_interval")}}
        result={"record":record,"group":group,"source_sha256":digest(original),"prepared_csv_sha256":digest(csv_path),"sample_rate_hz":fs,
                "reference_pulses":len(ref),"detected_pulses":len(detected),"reference_scored":len(ref_good),"detected_scored":len(det_good),
                "artifact_intervals_samples_zero_based_inclusive":artifacts.tolist(),"artifact_reference_pulses":int(len(ref)-len(ref_good)),"artifact_detections":int(len(detected)-len(det_good)),
                "primary_artifact_free":primary,"all_events_descriptive":descriptive,"endpoint_comparison":endpoint_comparison,
                "paired_intervals_50ms":{"count":len(errors),"mean_signed_error_ms":float(errors.mean()) if len(errors) else None,"median_absolute_error_ms":float(np.median(abs(errors))) if len(errors) else None,"p95_absolute_error_ms":float(np.percentile(abs(errors),95)) if len(errors) else None,"maximum_absolute_error_ms":float(abs(errors).max()) if len(errors) else None},
                "worker_result_sha256":digest(work/"worker-result.json"),"event_artifact":event_manifest,
                "reference_peak_samples":ref.tolist(),"detected_peak_samples":detected.tolist(),"saved_event_tables":tables}
        save(work/"agreement.json",result);results.append(result)
        save(folder/"progress.json",{"completed_records":len(results),"records":[x["record"] for x in results],"plan_sha256":digest(plan_path)})
        print(json.dumps({"record":record,"artifact_free_50ms":primary[1],"paired_intervals":result["paired_intervals_50ms"]}),flush=True)
    pooled=[]
    for k,tolerance in enumerate((20,50,150)):
        tp=sum(x["primary_artifact_free"][k]["matched"] for x in results);fp=sum(x["primary_artifact_free"][k]["unmatched_detected"] for x in results);fn=sum(x["primary_artifact_free"][k]["missed_reference"] for x in results)
        pooled.append({"tolerance_ms":tolerance,"matched":tp,"unmatched_detected":fp,"missed_reference":fn,"recall":tp/(tp+fn),"precision":tp/(tp+fp)})
    save(folder/"results.json",{"schema":"brohn-ppg-recorded-reference/1.0","plan_sha256":digest(plan_path),"completed_at":datetime.now(timezone.utc).isoformat(),
         "plan":plan,"pooled_artifact_free":pooled,"records":results,"reader_environment":{x:importlib.metadata.version(x) for x in ("numpy","scipy","wfdb","h5py")},"production_code_sha256":code_hashes()})
    print(json.dumps({"complete":True,"records":len(results),"pooled":pooled}),flush=True)


def render(args):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    folder=outside(args.output)
    result=json.loads((folder/"results.json").read_text(encoding="utf-8"))
    assert digest(folder/"plan.json")==result["plan_sha256"]
    rows=result["records"]
    fig,axes=plt.subplots(4,2,figsize=(14,11),layout="constrained")
    for ax,row in zip(axes.ravel(),rows):
        values,fs,_,artifacts,_=reference(folder/"source"/(row["record"]+"_8min.mat"))
        lo,hi=2,12;idx=np.arange(lo*fs,hi*fs)
        ax.plot(idx/fs,values[idx],color="#416a80",lw=1,label="Original PPG samples")
        for key,marker,color,label in (("reference_peak_samples","x","#bb4b26","Human reference"),("detected_peak_samples","o","#137c61","Production detection")):
            peaks=np.asarray(row[key]);peaks=peaks[(peaks>=lo*fs)&(peaks<hi*fs)]
            options={"facecolors":"none"} if marker=="o" else {}
            ax.scatter(peaks/fs,values[peaks],marker=marker,color=color,s=32,lw=1.2,label=label,**options)
        ax.set(title=f"{row['record']} | {row['group']} | unchanged raw scale",xlabel="Recording time (s)",ylabel="PPG (a.u.)",xlim=(lo,hi))
        ax.grid(alpha=.15)
    handles,labels=axes.ravel()[0].get_legend_handles_labels()
    fig.legend(handles,labels,loc="outside lower center",ncol=3,frameon=False)
    fig.suptitle("CapnoBase: first preselected 2–12 s window of every evaluated record\nMarkers show saved source sample positions; no lag fitting or peak recentering",fontsize=13)
    fig.savefig(folder/"reference-waveforms.png",dpi=160);plt.close(fig)
    fig,axes=plt.subplots(1,2,figsize=(12,5),layout="constrained")
    x=np.arange(len(rows));width=.36
    axes[0].bar(x-width/2,[r["primary_artifact_free"][1]["p95_absolute_ms"] for r in rows],width,label="Pulse location |error| p95")
    axes[0].bar(x+width/2,[r["paired_intervals_50ms"]["p95_absolute_error_ms"] for r in rows],width,label="Consecutive interval |error| p95")
    axes[0].set(ylabel="Milliseconds",title="Artifact-free timing agreement")
    axes[0].legend(fontsize=8)
    axes[1].bar(x-width/2,[r["endpoint_comparison"]["full_record"]["differences"]["rmssd"] for r in rows],width,label="Full-record production")
    axes[1].bar(x+width/2,[r["endpoint_comparison"]["artifact_free_intervals"]["differences"]["rmssd"] for r in rows],width,label="Independent artifact exclusion")
    axes[1].axhline(0,lw=.8,color="black")
    axes[1].set(ylabel="Detected minus annotated RMSSD (ms)",title="Artifact effects on PRV endpoints")
    axes[1].legend(fontsize=8)
    for ax in axes:
        ax.set_xticks(x,[r["record"] for r in rows],rotation=45);ax.grid(axis="y",alpha=.2)
    fig.suptitle("5,400 artifact-free pulses matched at <50 ms; endpoint agreement still needs review\nSample percentiles and raw differences, not confidence intervals",fontsize=12)
    fig.savefig(folder/"timing-and-prv-errors.png",dpi=160);plt.close(fig)
    # These cases are explicitly post hoc diagnostics of the largest observed
    # full-record endpoint discrepancies. No detector parameter is changed.
    selected=[r for r in rows if r["record"] in {"0123","0370"}]
    fig,axes=plt.subplots(2,2,figsize=(14,7),layout="constrained")
    for col,row in enumerate(selected):
        values,fs,_,artifacts,_=reference(folder/"source"/(row["record"]+"_8min.mat"))
        start,end=artifacts[0];lo=max(2,start/fs-2);hi=min(478,end/fs+2)
        indices=np.arange(int(lo*fs),int(hi*fs))
        worker=json.loads((folder/row["record"]/"worker-result.json").read_text(encoding="utf-8"))
        manifest=next(a for a in worker["artifacts"] if a["kind"]=="physiology-series")
        assert digest(manifest["path"])==manifest["sha256"]
        clean=np.full(len(values),np.nan)
        with Path(manifest["path"]).open(encoding="utf-8") as stream:
            for line in stream:
                item=json.loads(line)
                if item["type"]=="table":names=[c["name"] for c in item["columns"]]
                elif item["type"]=="rows":
                    for record in item["rows"]:
                        d=dict(zip(names,record));clean[int(d["source_sample_index"])]=d["clean"]
        for ax,signal,label in ((axes[0,col],values,"Original PPG"),(axes[1,col],clean,"Saved cleaned PPG")):
            ax.plot(indices/fs,signal[indices],color="#416a80",lw=1,label=label)
            for a,b in artifacts:
                if a/fs<hi and b/fs>lo:ax.axvspan(max(lo,a/fs),min(hi,b/fs),color="#dda35a",alpha=.2,label="Labelled artifact" if (a,b)==tuple(artifacts[0]) else None)
            for key,marker,color,legend in (("reference_peak_samples","x","#bb4b26","Human label (not reliable in artifact)"),("detected_peak_samples","o","#137c61","Unreviewed detection")):
                peaks=np.asarray(row[key]);peaks=peaks[(peaks>=lo*fs)&(peaks<hi*fs)]
                ax.scatter(peaks/fs,signal[peaks],marker=marker,color=color,s=38,lw=1.2,label=legend,**({"facecolors":"none"} if marker=="o" else {}))
            ax.set(xlim=(lo,hi),xlabel="Recording time (s)",ylabel=f"{label} (a.u.)",title=row["record"])
    handles,labels=axes[0,0].get_legend_handles_labels();fig.legend(handles,labels,loc="outside lower center",ncol=2,frameon=False,fontsize=9)
    fig.suptitle("Post hoc artifact context: first labelled interval in two discrepant records\nSource labels are retained; masked periods are excluded from primary pulse scoring",fontsize=12)
    fig.savefig(folder/"artifact-context.png",dpi=160);plt.close(fig)
    print(json.dumps({"figures":["reference-waveforms.png","timing-and-prv-errors.png","artifact-context.png"]}),flush=True)


if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument("mode",choices=("prepare","run","render"));parser.add_argument("--output",type=Path,required=True);parser.add_argument("--methods-python",type=Path);parser.add_argument("--resume",action="store_true",help="Retain completed record outputs after a reader/setup interruption; never changes the frozen plan")
    args=parser.parse_args()
    if args.mode=="run" and args.methods_python is None:parser.error("run requires --methods-python")
    {"prepare":prepare,"run":run,"render":render}[args.mode](args)
