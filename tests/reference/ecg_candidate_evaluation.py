"""Frozen offline candidate experiment. Never imports or edits production code."""
import argparse
from concurrent.futures import ThreadPoolExecutor
from collections import Counter
import csv
from datetime import datetime, timezone
import hashlib
import importlib.metadata
import json
from pathlib import Path
import shutil
import subprocess
import sys
import urllib.request
import numpy as np
import wfdb
from wfdb import processing
import wfdb.processing.qrs as qrs_module

ROOT=Path(__file__).resolve().parents[2]
PRIOR=None
METHODS=None
REPRODUCTION=None
DIAGNOSTIC=['100','101','108','200']
HELD_OUT=['103','105','111','117','207','213']
SYMBOLS=set('NLRBAaJSVrFejnE/fQ')

def digest(path): return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def save(path,obj): Path(path).write_text(json.dumps(obj,indent=2,allow_nan=False)+'\n',encoding='utf-8')
def utc(): return datetime.now(timezone.utc).isoformat()
def prepare(out):
    assert not (out==ROOT or ROOT in out.parents)
    out.mkdir(parents=True,exist_ok=True)
    plan=out/'preselection.json'
    if plan.exists(): raise ValueError('Preselection already exists; never replace it after observing results.')
    spec={
      'schema':'brohn-offline-ecg-candidate-plan/1.0','frozen_at':utc(),
      'status':'offline_candidate_only_no_production_modification',
      'diagnostic_records':DIAGNOSTIC,'held_out_records':HELD_OUT,
      'selection_reason':'Preselected unused MLII records spanning low-numbered and arrhythmia-enriched database groups; no candidate outcomes inspected before freezing. Six records are not a representative or full-database qualification.',
      'dataset':'https://physionet.org/content/mitdb/1.0.0/','lead':'first channel must be MLII in mV; otherwise stop, do not silently replace',
      'input_range_s':[0,300],'evaluation_range_s':[2,298],'sample_rate_hz':360,
      'candidate':{'name':'wfdb-xqrs-fixed-initialization-candidate/0.1','wfdb_version':'4.3.0',
         'function':'wfdb.processing.XQRS(sig=original_mV,fs=360,conf=XQRS.Conf()); detect(learn=False)',
         'configuration':vars(processing.XQRS.Conf()),'learn':False,
         'no_added_operations':['no NeuroKit cleaning','no sign flip','no local peak recentering','no correct_peaks','no artifact correction','no NN classification'],
         'rationale':'Squared linear-filter/Ricker moving-wave signal avoids signed-local-maximum localization. Optional positive-peak learning is disabled before evaluation to avoid reintroducing a polarity preference.',
         'limitation':'Default amplitude threshold assumes mV; bandpass, fiducial definition and refractory period differ from production. Energy maxima need not coincide with anatomical R landmarks.'},
      'comparison':{'tolerances_ms':[50,150],'matcher':'WFDB4.3.0 compare_annotations, one-to-one; not bxb/EC57 certification',
         'target_annotation_symbols':sorted(SYMBOLS),'plausible_interval_ms':[300,2000],
         'endpoints':['sensitivity','PPV','FP','FN','signed and absolute timing errors','RR SD','RMSSD','rate from mean interval','consecutive matched-pair interval error'],
         'qualification_rule':'No automatic release decision or universal threshold. Report every record and regression. This one candidate is not retuned after outcomes.'},
      'hypotheses':['Improves morphology-related diagnostic108 errors without a global sign flip.',
        'Synthetic full-signal sign reversal yields identical indices with disabled signed initializer.',
        'Held-out timing and interval errors must be assessed per record; pooled detection alone is insufficient.'],
      'source_hashes':{'harness':digest(__file__),'production_worker':digest(ROOT/'scripts/workers/physiology.py'),
          'candidate_qrs_module':digest(qrs_module.__file__), 'prior_results':digest(PRIOR/'results.json')},
      'primary_sources':['https://github.com/MIT-LCP/wfdb-python/blob/v4.3.0/wfdb/processing/qrs.py',
         'https://wfdb.readthedocs.io/en/latest/processing.html#qrs-detectors',
         'https://physionet.org/content/mitdb/1.0.0/']}
    if REPRODUCTION is not None:
        original=json.loads(REPRODUCTION.read_text(encoding='utf-8'))
        assert original['diagnostic_records']==DIAGNOSTIC and original['held_out_records']==HELD_OUT
        assert original['candidate']['name']==spec['candidate']['name'] and original['candidate']['configuration']==spec['candidate']['configuration']
        spec['experiment_role']='technical_reproduction_not_new_held_out_evidence'
        spec['reproduction_of_preselection_sha256']=digest(REPRODUCTION)
        spec['selection_reason']='Technical repeat of the linked frozen experiment; these records have already been observed and are not a new holdout.'
    else:
        spec['experiment_role']='initial_frozen_selection'
    save(plan,spec);print(json.dumps({'frozen':str(plan),'sha256':digest(plan)}),flush=True)

def intervals(peaks,fs):
    rr=np.diff(peaks)*1000/fs; ok=(rr>=300)&(rr<=2000); v=rr[ok]
    d=np.diff(rr)[ok[:-1]&ok[1:]]
    return {'mean_interval_ms':float(v.mean()) if len(v) else None,
      'sd_interval_ms':float(v.std(ddof=1)) if len(v)>1 else None,
      'rmssd_ms':float(np.sqrt(np.mean(d*d))) if len(d) else None,
      'rate_bpm':float(60000/v.mean()) if len(v) else None,'retained_intervals':int(ok.sum()),
      'rejected_intervals':int((~ok).sum()),'successive_pairs':len(d)}

def distribution(x):
    x=np.asarray(x,dtype=float)
    return {'count':len(x),'mean':float(x.mean()) if len(x) else None,
      'median':float(np.median(x)) if len(x) else None,'median_absolute':float(np.median(abs(x))) if len(x) else None,
      'p95_absolute':float(np.percentile(abs(x),95)) if len(x) else None,'max_absolute':float(max(abs(x))) if len(x) else None}

def agreement(ref,det,fs,labels,negative):
    results=[]
    for tolerance in [50,150]:
        a=processing.compare_annotations(ref,det,int(tolerance*fs/1000))
        matched_ref=np.asarray(a.matched_ref_inds,dtype=int);matched_det=np.asarray(a.matched_test_inds,dtype=int)
        mapped={int(r):int(d) for r,d in zip(matched_ref,matched_det)}
        rr_errors=[]
        for i in range(len(ref)-1):
            if i in mapped and i+1 in mapped and mapped[i+1]==mapped[i]+1:
                rr_errors.append(((det[mapped[i+1]]-det[mapped[i]])-(ref[i+1]-ref[i]))*1000/fs)
        strata={}
        for name,mask in [('negative_local_landmark',negative),('nonnegative_local_landmark',~negative)]+[(f'annotation_{s}',labels==s) for s in sorted(set(labels))]:
            selected=set(np.flatnonzero(mask));count=len(selected);tp=len(selected.intersection(matched_ref.tolist()))
            strata[name]={'reference_count':count,'matched':tp,'missed':count-tp,'sensitivity':tp/count if count else None}
        assert a.tp+a.fp==len(det) and a.tp+a.fn==len(ref) and len(set(matched_det))==a.tp
        results.append({'tolerance_ms':tolerance,'tp':int(a.tp),'fp':int(a.fp),'fn':int(a.fn),
          'sensitivity':float(a.sensitivity),'positive_predictive_value':float(a.positive_predictivity),
          'timing_error_ms':distribution((a.matched_test_sample-a.matched_ref_sample)*1000/fs),
          'consecutive_matched_interval_error_ms':distribution(rr_errors),'reference_strata':strata})
    return results

def candidate(x,fs):
    if np.asarray(x).ndim!=1 or not np.isfinite(x).all():raise ValueError('Candidate only accepts finite one-dimensional constant-cadence segments; no gap repair.')
    detector=processing.XQRS(sig=np.asarray(x),fs=fs,conf=processing.XQRS.Conf())
    detector.detect(learn=False,verbose=False)
    indices=np.asarray(detector.qrs_inds,dtype=int)
    assert np.all(np.diff(indices)>0)
    return indices

def synthetic(out):
    fs=360;t=np.arange(35*fs)/fs;times=[1.0]
    while times[-1]<33:times.append(times[-1]+1+.1*np.sin(2*np.pi*.1*times[-1]))
    refs=np.asarray([round(s*fs) for s in times if 2<=s<33],dtype=int)
    cases={}
    for name in ['positive','inverted','mixed_sign','biphasic','dominant_late_negative']:
        x=np.zeros(len(t))
        for i,s in enumerate(times):
            sign=-1 if name=='inverted' or (name=='mixed_sign' and i%2) else 1
            x+=sign*np.exp(-.5*((t-s)/.012)**2)
            if name in ['biphasic','dominant_late_negative']:
                x-=.15*np.exp(-.5*((t-s+.018)/.009)**2)
                x-=(1.5 if name=='dominant_late_negative' else .5)*np.exp(-.5*((t-s-.03)/.012)**2)
        detected=candidate(x,fs);detected=detected[(detected>=2*fs)&(detected<33*fs)]
        negative=np.array([x[r]<0 for r in refs])
        cases[name]={'reference_peaks':refs.tolist(),'detected_peaks':detected.tolist(),
          'comparison':agreement(refs,detected,fs,np.array(['N']*len(refs)),negative),
          'candidate_intervals':intervals(detected,fs),'reference_intervals':intervals(refs,fs),
          'full_signal_sign_reversal_identical':np.array_equal(candidate(x,fs),candidate(-x,fs))}
        np.savez_compressed(out/(name+'.npz'),signal_mv=x,reference_peaks=refs,detected_peaks=detected,fs=fs)
    cases['flat']={'detections':len(candidate(np.zeros(len(t)),fs))}
    try:candidate(np.array([0.,np.nan,1.]),fs)
    except ValueError:cases['nonfinite_rejected']=True
    save(out/'synthetic.json',cases);return cases

def run(out):
    plan=json.loads((out/'preselection.json').read_text());assert plan['source_hashes']['harness']==digest(__file__)
    assert plan['source_hashes']['production_worker']==digest(ROOT/'scripts/workers/physiology.py')
    assert plan['source_hashes']['candidate_qrs_module']==digest(qrs_module.__file__)
    if (out/'results.json').exists():raise ValueError('This frozen experiment already completed; never overwrite outcomes.')
    source=out/'source';source.mkdir(exist_ok=True)
    def fetch(item):
        record,extension=item;name=f'{record}.{extension}';target=source/name;url=f'https://physionet.org/files/mitdb/1.0.0/{name}'
        if not target.exists():
            if record in DIAGNOSTIC:shutil.copyfile(PRIOR/'source'/name,target)
            else:
                with urllib.request.urlopen(url,timeout=60) as response:data=response.read(3*1024**2+1)
                if not 0<len(data)<=3*1024**2:raise ValueError('Source exceeds expected bounded file size')
                with target.open('xb') as f:f.write(data)
        return {'name':name,'url':url,'bytes':target.stat().st_size,'sha256':digest(target)}
    with ThreadPoolExecutor(max_workers=4) as pool:files=list(pool.map(fetch,[(r,e)for r in DIAGNOSTIC+HELD_OUT for e in ['hea','dat','atr']]))
    save(out/'download-manifest.json',{'retrieved_at':utc(),'dataset':plan['dataset'],'license':'Open Data Commons Attribution License v1.0','files':files})
    synth=out/'synthetic';synth.mkdir(exist_ok=True);synthetic_results=synthetic(synth)
    results=[]
    for record in DIAGNOSTIC+HELD_OUT:
        folder=out/record;folder.mkdir(exist_ok=True)
        raw=wfdb.rdrecord(str(source/record),sampto=108000,channels=[0]);ann=wfdb.rdann(str(source/record),'atr',sampto=108000)
        assert raw.fs==360 and raw.sig_name==['MLII'] and raw.units==['mV'];x=raw.p_signal[:,0];fs=360
        targets=[(int(s),label)for s,label in zip(ann.sample,ann.symbol)if label in SYMBOLS and 720<=s<107280]
        ref=np.array([s for s,l in targets]);labels=np.array([l for s,l in targets]);assert len(ref) and np.all(np.diff(ref)>0)
        negative=np.array([x[s]-np.median(x[s-54:s+55])<0 for s in ref])
        baseline_path=PRIOR/record/'worker-result.json'
        if record in DIAGNOSTIC:
            parent=json.loads((PRIOR/record/'agreement.json').read_text());assert digest(baseline_path)==parent['worker_result_sha256']
            assert parent['worker_sha256']==plan['source_hashes']['production_worker'];shutil.copyfile(baseline_path,folder/'baseline-worker.json')
        else:
            csv_path=folder/'reference-ecg.csv'
            with csv_path.open('w',encoding='utf-8',newline='') as f:
                writer=csv.writer(f);writer.writerow(['seconds','ecg_mv']);writer.writerows((i/fs,float(v))for i,v in enumerate(x))
            request={'schema':'brohn-worker-request/1.0','operation':'physiology','modality':'ecg','source_path':str(csv_path),'format':'csv',
              'metadata':{'time_column':'seconds','time_unit':'s','sampling_rate':fs,'value_columns':['ecg_mv'],'unit':'mV'},
              'parameters':{'powerline_hz':60,'edge_exclusion_s':2},'origin':'public_reference'}
            save(folder/'baseline-request.json',request)
            child=subprocess.run([str(METHODS.resolve()),str(ROOT/'scripts/workers/physiology.py'),'--request',str(folder/'baseline-request.json'),'--output',str(folder/'baseline-worker.json')],
              cwd=ROOT,capture_output=True,text=True,timeout=120,creationflags=subprocess.CREATE_NO_WINDOW if sys.platform=='win32'else 0)
            (folder/'baseline.log').write_text(child.stdout+'\n'+child.stderr)
            if child.returncode:raise RuntimeError(child.stderr)
        baseline=json.loads((folder/'baseline-worker.json').read_text());events=[e for e in baseline['events']if e['type']=='r_peak']
        assert baseline['quality']['event_records_total']==len(baseline['events'])
        det=np.array([e['source_sample_index']for e in events]);assert len(det)==baseline['recordings'][0]['detected_peak_count']
        cand=candidate(x,fs);cand=cand[(cand>=720)&(cand<107280)]
        item={'record':record,'partition':'diagnostic_seen'if record in DIAGNOSTIC else'preselected_held_out',
          'reference_count':len(ref),'annotation_symbols':dict(Counter(labels)),
          'reference_intervals':intervals(ref,fs),
          'baseline':{'count':len(det),'comparison':agreement(ref,det,fs,labels,negative),'intervals':intervals(det,fs),'worker_result_sha256':digest(folder/'baseline-worker.json')},
          'candidate':{'count':len(cand),'comparison':agreement(ref,cand,fs,labels,negative),'intervals':intervals(cand,fs)},
          'candidate_full_signal_sign_reversal_identical':np.array_equal(candidate(x,fs),candidate(-x,fs))}
        save(folder/'events.json',{'reference':ref.tolist(),'reference_labels':labels.tolist(),'baseline':det.tolist(),'candidate':cand.tolist()})
        save(folder/'agreement.json',item);results.append(item)
        print(json.dumps({'record':record,'partition':item['partition'],'baseline':item['baseline']['comparison'][0],'candidate':item['candidate']['comparison'][0]}),flush=True)
    assert plan['source_hashes']['production_worker']==digest(ROOT/'scripts/workers/physiology.py')
    report={'schema':'brohn-offline-ecg-candidate-results/1.0','completed_at':utc(),'preselection_sha256':digest(out/'preselection.json'),
      'plan':plan,'records':results,'environment':{d.metadata['Name']:d.version for d in importlib.metadata.distributions()},
      'synthetic':synthetic_results,'production_changed':False,'normal_to_normal_qualified':False,'hardware_qualified':False}
    save(out/'results.json',report);print(json.dumps({'complete':str(out/'results.json'),'records':len(results)}),flush=True)

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('mode',choices=['prepare','run']);parser.add_argument('output',type=Path);parser.add_argument('--prior',type=Path,required=True);parser.add_argument('--methods-python',type=Path,required=True);parser.add_argument('--reproduce-plan',type=Path);args=parser.parse_args()
    PRIOR=args.prior.resolve();METHODS=args.methods_python.resolve();REPRODUCTION=args.reproduce_plan
    (prepare if args.mode=='prepare'else run)(args.output.resolve())
