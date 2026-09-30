"""Read-only exact old-reader/preparation regression over retained full streams.
Usage: python -B tests/eda-constant-legacy-python.py CANDIDATE BASELINE OLD_PREP_REQUEST FRESH_OUT
The request must bind complete retained originals. This does not establish store
authority; it compares unchanged saved scientific values, rows and CSV bytes.
"""
from pathlib import Path
import copy,hashlib,importlib.util,json,sys
candidate,baseline,request_path,out=map(lambda p:Path(p).resolve(),sys.argv[1:]);assert not out.exists();out.mkdir(parents=True)
sys.path[:0]=[str(candidate/'scripts/workers'),str(baseline/'scripts/workers')]
import eda_display as new
import eda_continuous_review as new_review
def load(name,path):
    spec=importlib.util.spec_from_file_location(name,path);module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);return module
old_review=load('old_saved_continuous',baseline/'scripts/workers/eda_continuous_review.py')
old_event=load('old_saved_event',baseline/'scripts/workers/eda_review.py')
old=load('old_saved_display',baseline/'scripts/workers/eda_display.py');old.eda_continuous_review=old_review;old.eda_review=old_event
q=new.strict_json(request_path.read_bytes());assert q['implementation']['profile']=='saved-eda-display/0.1'
paths=[request_path,*[Path(x['path']) for x in q['streams']],Path(q['original_source']['path']),*[Path(x['path']) for x in q['sealed_objects']]]
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest();before={str(p):sha(p) for p in paths};checks=[]
def check(ok,label):assert ok,label;checks.append(label)
for label,module in [('original',old),('candidate',new)]:
    directory=out/label;directory.mkdir();e,c,v=module.prepare(q,directory)
    (directory/'evidence.json').write_bytes(new.json_bytes(e));(directory/'catalog.json').write_bytes(new.json_bytes(c));(directory/'verification.json').write_bytes(new.json_bytes(v))
for name in ('evidence.json','catalog.json','verification.json'):
    check((out/'original'/name).read_bytes()==(out/'candidate'/name).read_bytes(),'old preparation exact typed output bytes: '+name)
later=copy.deepcopy(q);later['implementation']['profile']='saved-eda-display/0.2';directory=out/'new-profile';directory.mkdir();e,c,v=new.prepare(later,directory)
original=new.strict_json((out/'original/evidence.json').read_bytes())
check(new.value_hash(e['cells'])==new.value_hash(original['cells']),'new preparation keeps every original old1.0 model/cell byte value')
check(e['coverage']['descriptive_only_cells']==e['coverage']['coordinate_only_rows']==0,'old source is never classified as the new constant branch')
analysis=q['report']['complete_analysis'];r=next(r for r in analysis['recordings'] if r['status']=='computed')
identity={k:r[k] for k in new_review.IDENTITY};selection={**identity,'start_s':str(r['start_time_s']),'end_s':str(r['end_time_s'])}
direct=dict(schema='brohn-eda-continuous-review-request/1.0',binding=dict(origin=q['report']['saved_body']['origin']),recording=r,parameters=analysis['parameters'][r['recording_id']],
    features=[f for f in analysis['features'] if all(f[k]==v for k,v in identity.items())],selection=selection,original_source=q['original_source'],sealed_objects=q['sealed_objects'],
    artifacts=[new.verifier_manifest(s['original'],s['path']) for s in q['streams']])
for label,module in [('direct-original',old_review),('direct-candidate',new_review)]:
    directory=out/label;directory.mkdir();direct['export_directory']=str(directory);model=module.review(direct);(directory/'model.json').write_bytes(new.json_bytes(model))
for name in ('model.json','eda-samples.csv','eda-candidates.csv','eda-markers.csv'):
    check((out/'direct-original'/name).read_bytes()==(out/'direct-candidate'/name).read_bytes(),'old direct reader exact bytes: '+name)
check(before=={str(p):sha(p) for p in paths},'all original source/request bytes unchanged')
receipt=dict(passed=True,count=len(checks),checks=checks,original_files=before,
    candidate_hashes={p:sha(candidate/'scripts/workers'/p) for p in ('eda_display.py','eda_continuous_review.py')},
    baseline_hashes={p:sha(baseline/'scripts/workers'/p) for p in ('eda_display.py','eda_continuous_review.py')},
    scope='Exact old1.0 direct and preparation0.1 comparison over retained full original streams; new0.2 model conservation; no science or native publication')
(out/'results.json').write_text(json.dumps(receipt,indent=2),encoding='utf-8');print(json.dumps(dict(passed=True,checks=len(checks))))
