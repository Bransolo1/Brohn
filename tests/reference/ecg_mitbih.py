"""Exploratory published-reference ECG agreement, never a clinical/device claim.

Run with an isolated WFDB4.3.0 reader environment and pass the production methods
Python. Original files and outputs stay outside the source repository. No detector
setting is tuned using these outcomes. This is not the standard bxb benchmark.
"""
import argparse
from collections import Counter
import csv
from datetime import datetime, timezone
import hashlib
import importlib.metadata
import json
from pathlib import Path
import subprocess
import sys
import urllib.request
import numpy as np
import wfdb
from wfdb import processing

ROOT=Path(__file__).resolve().parents[2]
DATASET="https://physionet.org/content/mitdb/1.0.0/"
RECORDS=("100","101","108","200")
BEAT_SYMBOLS=set("NLRBAaJSVrFejnE/fQ")
DURATION=300

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def save(path,value):
    path.write_text(json.dumps(value,ensure_ascii=False,allow_nan=False,indent=2)+"\n",encoding="utf-8")

def reference_metrics(peaks,fs):
    intervals=np.diff(peaks)*1000/fs
    valid=(intervals>=300)&(intervals<=2000)
    retained=intervals[valid];differences=np.diff(intervals)[valid[:-1]&valid[1:]]
    return {"mean_interval":float(np.mean(retained)) if len(retained) else None,
            "sd_interval":float(np.std(retained,ddof=1)) if len(retained)>1 else None,
            "rmssd":float(np.sqrt(np.mean(differences**2))) if len(differences) else None,
            "rate_from_mean_interval":float(60000/np.mean(retained)) if len(retained) else None,
            "retained_intervals":int(len(retained)),"successive_pairs":int(len(differences))}

def run(args):
    output=args.output.resolve()
    if output==ROOT or ROOT in output.parents:
        raise ValueError("Keep reference recordings and results outside the source repository.")
    output.mkdir(parents=True,exist_ok=True);source=output/"source";source.mkdir(exist_ok=True)
    manifest_path=output/"download-manifest.json"
    prior=json.loads(manifest_path.read_text(encoding="utf-8")) if manifest_path.exists() else None
    files=[]
    for record in RECORDS:
        for extension in ("hea","dat","atr"):
            name=f"{record}.{extension}";path=source/name;url=f"https://physionet.org/files/mitdb/1.0.0/{name}"
            if not path.exists():
                if not args.download:raise ValueError("Missing public reference; use --download for the named MIT-BIH files.")
                with urllib.request.urlopen(url,timeout=45) as response:payload=response.read(3*1024**2+1)
                if not 0<len(payload)<=3*1024**2:raise ValueError("Reference file exceeds its declared download bound.")
                with path.open("xb") as stream:stream.write(payload)
            sha=digest(path)
            if prior:
                original=next(x for x in prior["files"] if x["name"]==name)
                if original["sha256"]!=sha:raise ValueError("A previously retained reference file changed.")
            files.append({"name":name,"url":url,"sha256":sha,"bytes":path.stat().st_size})
    manifest={"dataset":DATASET,"version":"1.0.0","license":"Open Data Commons Attribution License v1.0",
        "citation":"Moody GB, Mark RG. The impact of the MIT-BIH Arrhythmia Database. IEEE Engineering in Medicine and Biology20(3):45-50 (2001).",
        "retrieved_at":prior["retrieved_at"] if prior else datetime.now(timezone.utc).isoformat(),"files":files}
    save(manifest_path,manifest)
    results=[]
    for record in RECORDS:
        folder=output/record;folder.mkdir(exist_ok=True)
        data=wfdb.rdrecord(str(source/record),sampto=DURATION*360,channels=[0],physical=True)
        assert data.fs==360 and data.units==["mV"] and data.sig_name==["MLII"]
        annotations=wfdb.rdann(str(source/record),"atr",sampto=DURATION*360)
        fs=int(data.fs);lo=2*fs;hi=(DURATION-2)*fs
        reference=np.array([int(s) for s,label in zip(annotations.sample,annotations.symbol) if label in BEAT_SYMBOLS and lo<=s<hi],dtype=int)
        assert len(reference)>0 and np.all(np.diff(reference)>0)
        path=folder/"reference-ecg.csv"
        with path.open("w",encoding="utf-8",newline="") as stream:
            writer=csv.writer(stream);writer.writerow(["seconds","ecg_mv"])
            writer.writerows((i/fs,float(x)) for i,x in enumerate(data.p_signal[:,0]))
        request={"schema":"brohn-worker-request/1.0","operation":"physiology","modality":"ecg","source_path":str(path),"format":"csv",
            "metadata":{"time_column":"seconds","time_unit":"s","sampling_rate":fs,"value_columns":["ecg_mv"],"unit":"mV"},
            "parameters":{"powerline_hz":60,"edge_exclusion_s":2},"origin":"public_reference"}
        save(folder/"request.json",request)
        code_hash=digest(ROOT/"scripts/workers/physiology.py")
        child=subprocess.run([str(args.methods_python),str(ROOT/"scripts/workers/physiology.py"),"--request",str(folder/"request.json"),"--output",str(folder/"worker-result.json")],
            cwd=ROOT,capture_output=True,text=True,timeout=120)
        if child.returncode:raise RuntimeError(child.stderr+child.stdout)
        result=json.loads((folder/"worker-result.json").read_text(encoding="utf-8"))
        assert result["status"]=="completed" and digest(ROOT/"scripts/workers/physiology.py")==code_hash
        # A preview must not masquerade as the complete detector event set.
        assert result["quality"]["event_records_total"]==len(result["events"])
        assert len(result["recordings"])==1 and result["recordings"][0]["status"]=="computed"
        detected=np.array([r["source_sample_index"] for r in result["events"] if r["type"]=="r_peak"],dtype=int)
        assert len(detected)==result["recordings"][0]["detected_peak_count"] and np.all(np.diff(detected)>0)
        assert np.all((detected>=lo)&(detected<hi))
        comparisons=[]
        for tolerance_ms in (50,150):
            comparison=processing.compare_annotations(reference,detected,int(tolerance_ms*fs/1000))
            errors=(comparison.matched_test_sample-comparison.matched_ref_sample)*1000/fs
            comparisons.append({"tolerance_ms":tolerance_ms,"matched":int(comparison.tp),"extra":int(comparison.fp),"missed":int(comparison.fn),
                "sensitivity":float(comparison.sensitivity),"positive_predictive_value":float(comparison.positive_predictivity),
                "median_signed_error_ms":float(np.median(errors)) if len(errors) else None,
                "median_absolute_error_ms":float(np.median(abs(errors))) if len(errors) else None,
                "p95_absolute_error_ms":float(np.percentile(abs(errors),95)) if len(errors) else None})
            assert comparison.tp+comparison.fp==len(detected) and comparison.tp+comparison.fn==len(reference)
            assert len(set(comparison.matched_test_inds))==comparison.tp
        ref_metrics=reference_metrics(reference,fs)
        features={r["name"]:r["value"] for r in result["features"]}
        endpoints={key:{"reference_all_beat_annotations_same_plausibility_rule":value,"detected":features[f"detected_rr_{key}"],
            "difference":features[f"detected_rr_{key}"]-value if value is not None and features[f"detected_rr_{key}"] is not None else None}
            for key,value in ref_metrics.items() if key not in {"retained_intervals","successive_pairs"}}
        item={"record":record,"source_channel":"MLII","original_unit":"mV","sample_rate_hz":fs,"source_range_s":[0,DURATION],"evaluation_range_s":[2,DURATION-2],
            "reference_beats":len(reference),"detected_peaks":len(detected),"annotation_symbols":dict(Counter(label for s,label in zip(annotations.sample,annotations.symbol) if lo<=s<hi)),
            "comparison":comparisons,"endpoint_comparison":endpoints,"reference_endpoint_support":ref_metrics,
            "worker_sha256":code_hash,"worker_result_sha256":digest(folder/"worker-result.json"),"prepared_csv_sha256":digest(path)}
        save(folder/"agreement.json",item);results.append(item);print(json.dumps({"record":record,"comparison":comparisons}),flush=True)
    report={"schema":"brohn-ecg-reference-evaluation/1.0","origin":"published_reference_recording","dataset":manifest,"results":results,
        "reader_environment":{d.metadata["Name"]:d.version for d in importlib.metadata.distributions()},
        "comparison_method":"WFDB Python4.3.0 compare_annotations; separate50/150ms one-to-one location comparisons; not bxb/EC57 compliance",
        "limitations":["Four preselected records, first300seconds and firstMLII channel only; not complete database or target-population validation.",
            "All beat annotation classes are detection targets; rhythm/nonbeat markers are excluded. This does not classify arrhythmias or qualify normal-to-normal intervals.",
            "The existing named NeuroKit profile was not tuned to these results. Declared60Hz powerline setting follows this US reference acquisition context.",
            "Endpoint differences include detection and annotation-timing differences. Plausibility screening is not ectopic correction or a clinical HRV analysis.",
            "Actual sensor contact, physical timing, display behavior and vendor hardware remain untested."]}
    save(output/"results.json",report)
    print(json.dumps({"completed":True,"records":len(results),"output":str(output)}),flush=True)

if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument("--output",type=Path,required=True);parser.add_argument("--methods-python",type=Path,required=True);parser.add_argument("--download",action="store_true")
    run(parser.parse_args())
