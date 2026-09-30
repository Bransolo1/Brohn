"""Saved constant-coordinate reader/projection tests; no scientific calls.

Usage: python -B tests/eda-constant-pure.py PURE_REPO PRODUCER_REPO BASELINE GENERATED_CORPUS FRESH_OUT
The corpus is produced separately by the public eda-constant-producer.py test.
It supplies component fixtures, not native published reports. A minimal report
envelope below is explicit test scaffolding; original scientific values stay exact.
"""
from pathlib import Path
import copy
import csv
import hashlib
import importlib.util
import json
import math
import sys
from types import SimpleNamespace

pure, producer, baseline, corpus, out = map(lambda x: Path(x).resolve(), sys.argv[1:])
assert not out.exists()
out.mkdir(parents=True)
sys.path[:0] = [str(pure/'scripts/workers'),str(producer/'scripts/workers'),str(baseline/'scripts/workers')]
import eda_continuous_review as review
import eda_display as display
import report_package_eda as projection
import physiology_artifacts as tables

checks=[]
def check(ok,name):
    assert ok,name
    checks.append(name)
def refuses(fn,name):
    try: fn()
    except tables.ArtifactError: checks.append(name)
    else: raise AssertionError(name)
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
originals={str(p.relative_to(corpus)):sha(p) for p in corpus.rglob('*') if p.is_file()}
source_files=['scripts/workers/eda_continuous_review.py','scripts/workers/eda_display.py','scripts/workers/report_package_eda.py']
source_hashes={p:sha(pure/p) for p in source_files}
skipped=[]
models=[]
for number in range(1,7):
    fixture=corpus/f'constant-{number}'
    analysis=display.strict_json((fixture/'result.json').read_bytes())
    record=analysis['recordings'][0]
    with (fixture/'source.csv').open(encoding='utf-8',newline='') as source_csv:
        source_rows=list(csv.DictReader(source_csv))
    n=len(source_rows);fs=round(1/(float(source_rows[1]['time'])-float(source_rows[0]['time'])))
    edge=math.ceil(10*fs);retained=n-2*edge
    ref=dict(kind='report',id=f'component-{number}',revision=1,body_hash='a'*64,project_id='synthetic-project')
    source=dict(hash=analysis['source']['sha256'],bytes=analysis['source']['bytes'],path=str(fixture/'source.csv'))
    artifacts=analysis['artifacts']
    verified=[tables.verify_artifact(a) for a in artifacts]
    origin=verified[0]['provenance']['origin']
    selection={k:record[k] for k in review.IDENTITY}
    selection.update(start_s=display.normalized_decimal(str(record['start_time_s'])),end_s=display.normalized_decimal(str(record['end_time_s'])))
    direct_dir=out/f'constant-{number}'
    direct_dir.mkdir()
    direct=dict(schema='brohn-eda-continuous-review-request/1.1',binding=dict(report_ref=ref,origin=origin),recording=record,
                parameters=analysis['parameters'][record['recording_id']],features=analysis['features'],selection=selection,
                original_source=source,sealed_objects=[],artifacts=artifacts,export_directory=str(direct_dir))
    model=review.review(direct)
    (direct_dir/'request.json').write_bytes(display.json_bytes(direct))
    (direct_dir/'model.json').write_bytes(display.json_bytes(model))
    check(model['status']=='raw_description_only' and model['schema']=='brohn-eda-continuous-review/1.1','constant model has an explicit new status/version')
    check(model['features']==analysis['features'] and len(model['features'])==10,'all ten feature values/nulls/support/order preserved')
    check(model['recording']==record and model['parameters']==direct['parameters'],'source support and method preserved')
    check(model['candidates']==model['markers']==model['rows']==model['processed_components']==[] and all(x==[] for x in model['series'].values()),'no fabricated processed components/zero waveform')
    c=model['counts']
    check(len(c)==11 and c['selected_coordinate_rows']==n and c['selected_retained_coordinate_rows']==retained and c['selected_excluded_coordinate_rows']==2*edge,'coordinate support independently reconciles original source rows and declared edge duration')
    check(c['displayed_processed_points']==0 and c['selected_numerical_candidate_rows']==0 and record['response_denominator'] is None,'structural zero candidates stay distinct from null response support')
    rows=list(csv.DictReader((direct_dir/'eda-samples.csv').open(encoding='utf-8',newline='')))
    check(len(rows)==n and all(all(row[k]=='' for k in review.COMPONENTS) for row in rows),'direct CSV retains complete coordinates and empty null cells')
    check(all(int(row['source_sample_index'])==i and float(row['time_s'])==float(source_rows[i]['time']) for i,row in enumerate(rows)),'CSV time/index coordinates remain exact')
    check(len((direct_dir/'eda-candidates.csv').read_text().splitlines())==1 and len((direct_dir/'eda-markers.csv').read_text().splitlines())==1,'candidate/marker CSVs are explicitly header-only')
    old=copy.deepcopy(direct);old['schema']='brohn-eda-continuous-review-request/1.0'
    refuses(lambda:review.review(old),'new scientific grammar refuses old reader1.0')
    narrowed=copy.deepcopy(direct);narrowed['selection']['start_s']='1'
    refuses(lambda:review.review(narrowed),'constant view refuses narrower bounds')
    bad=copy.deepcopy(direct);bad['features'][0]['value']=0
    refuses(lambda:review.review(bad),'withheld tonic value cannot become finite zero')
    streams=[dict(original=a,original_verification={**v,**{k:a[k] for k in ('kind','sha256','bytes','schema','tables','rows','provenance_sha256')},'verified':True},path=a['path']) for a,v in zip(artifacts,verified)]
    saved_analysis=copy.deepcopy(analysis);saved_analysis['kind']='eda'
    report=dict(ref=ref,saved_body=dict(analysis=saved_analysis,origin=origin),complete_analysis=saved_analysis)
    request=dict(schema='brohn-eda-display-worker-request/0.1',report=report,source=dict(report_ref=ref,analysis_hash='b'*64,original_stream_descriptors=artifacts),
        display_request=dict(schema='brohn-eda-display-request/0.1',continuous_windows=[]),implementation=dict(profile='saved-eda-display/0.2'),
        streams=streams,original_source=source,sealed_objects=[])
    work=direct_dir/'prepared';work.mkdir()
    evidence,catalog,verification=display.prepare(request,work)
    (direct_dir/'prepared-request.json').write_bytes(display.json_bytes(request))
    (direct_dir/'evidence.json').write_bytes(display.json_bytes(evidence))
    (direct_dir/'catalog.json').write_bytes(display.json_bytes(catalog))
    check(evidence['schema']=='brohn-eda-display-evidence/0.2' and evidence['cells'][0]['status']=='raw_description_only','new preparation retains explicit constant model')
    reduced=copy.deepcopy(model);del reduced['rows'];del reduced['exports'];reduced['binding']=evidence['cells'][0]['model']['binding'];reduced['endpoint_coverage']=dict(unobserved=[])
    check(display.value_hash(reduced)==evidence['cells'][0]['model_hash'],'prepared and direct scientific model fields agree exactly')
    check(evidence['coverage']['descriptive_only_cells']==1 and evidence['coverage']['available_cells']==evidence['coverage']['unavailable_cells']==0 and evidence['coverage']['coordinate_only_rows']==n,'new coverage distinguishes coordinate-only cells and rows')
    check(catalog[0]['components']==[] and catalog[0]['marker_page_count']==0 and catalog[0]['focusable'] is False and catalog[0]['scr_status']=='unavailable' and catalog[0]['descriptive_status']=='computed','catalog has one descriptive state with no invented component/pages')
    old=copy.deepcopy(request);old['implementation']['profile']='saved-eda-display/0.1'
    refuses(lambda:display.prepare(old,work),'new scientific source refuses preparation0.1')
    inspect_request=dict(schema='brohn-eda-stream-inspection-request/0.2',source_report_ref=ref,source_family='continuous',streams=streams)
    inspection=projection.inspect(inspect_request)
    old=copy.deepcopy(inspect_request);old['schema']='brohn-eda-stream-inspection-request/0.1'
    refuses(lambda:projection.inspect(old),'constant nullable streams refuse inspection0.1')
    project_request=dict(schema='brohn-eda-stream-projection-request/0.2',inspection=inspection,source_report_ref=ref,source_family='continuous',
        identifier_mode='source_identifiers',streams=streams,projected_metadata=[{k:s[k] for k in ('header','tables')} for s in inspection['streams']],projection_implementation={})
    receipt=projection.project(project_request,direct_dir/'complete')
    check(receipt['schema']=='brohn-eda-stream-projection-result/0.2' and all(r['schema']=='brohn-report-eda-stream-projection/0.2' for r in receipt['streams']),'complete projection uses its own strict schema discriminator')
    check(all(sha(direct_dir/'complete'/r['projected']['path'])==r['original']['sha256'] for r in receipt['streams']),'original identifier mode preserves complete typed stream bytes')
    check(receipt['streams'][0]['table_bindings'][0]['null_counts']['tonic_us']==n,'complete numerical inventory records every null coordinate value')
    models.append(str((direct_dir/'model.json').relative_to(out)))

def fixture_request(name,profile):
    fixture=corpus/name;analysis=display.strict_json((fixture/'result.json').read_bytes());analysis['kind']='eda'
    artifacts=analysis['artifacts'];verified=[tables.verify_artifact(a) for a in artifacts]
    origin=verified[0]['provenance']['origin'] if verified else 'component-test'
    ref=dict(kind='report',id='component-'+name,revision=1,body_hash='a'*64,project_id='synthetic-project')
    streams=[dict(original=a,original_verification={**v,**{k:a[k] for k in ('kind','sha256','bytes','schema','tables','rows','provenance_sha256')},'verified':True},path=a['path']) for a,v in zip(artifacts,verified)]
    return dict(schema='brohn-eda-display-worker-request/0.1',report=dict(ref=ref,saved_body=dict(analysis=analysis,origin=origin),complete_analysis=analysis),
        source=dict(report_ref=ref,analysis_hash='b'*64,original_stream_descriptors=artifacts),
        display_request=dict(schema='brohn-eda-display-request/0.1',continuous_windows=[]),implementation=dict(profile=profile),streams=streams,
        original_source=dict(hash=analysis['source']['sha256'],bytes=analysis['source']['bytes'],path=str(fixture/'source.csv')),sealed_objects=[])

for name in ('mixed-support','segmentation','edge-399','edge-400','legacy-ordinary','legacy-flatline','legacy-zero'):
    request=fixture_request(name,'saved-eda-display/0.2');directory=out/name;directory.mkdir()
    evidence,catalog,_=display.prepare(request,directory)
    (directory/'prepared-request.json').write_bytes(display.json_bytes(request));(directory/'evidence.json').write_bytes(display.json_bytes(evidence));(directory/'catalog.json').write_bytes(display.json_bytes(catalog))
    analysis=request['report']['complete_analysis'];expected=sum(r['samples'] for r in analysis['recordings'] if r['status']=='descriptive_only')
    check(evidence['coverage']['coordinate_only_rows']==expected,'mixed/segmented complete coordinate totals counted once per table: '+name)
    check(evidence['coverage']['cells']==sum(evidence['coverage'][k] for k in ('available_cells','unavailable_cells','descriptive_only_cells')),'available/unavailable/descriptive categories partition every source cell: '+name)
    check([c['original_support'] for c in evidence['cells']]==analysis['recordings'],'original mixed/short/legacy support order retained: '+name)
    if name.startswith('legacy'):
        old=copy.deepcopy(request);old['implementation']['profile']='saved-eda-display/0.1';old_dir=directory/'profile01';old_dir.mkdir()
        old_evidence,old_catalog,_=display.prepare(old,old_dir)
        check([c['model'] for c in evidence['cells']]==[c['model'] for c in old_evidence['cells']],'preparation0.2 preserves old-science model1.0 exactly: '+name)
        check(all(c['descriptive_status'] is None and c['scr_status'] is None for c in old_catalog),'historical preparation0.1 keeps null continuous support catalog: '+name)
        check(all(c['model'] is None or c['model']['schema']=='brohn-eda-continuous-review/1.0' for c in evidence['cells']),'new prep does not relabel old model versions: '+name)

spec=importlib.util.spec_from_file_location('baseline_continuous_review',baseline/'scripts/workers/eda_continuous_review.py')
legacy=importlib.util.module_from_spec(spec);spec.loader.exec_module(legacy)
request=fixture_request('legacy-ordinary','saved-eda-display/0.1');a=request['report']['complete_analysis'];r=a['recordings'][0]
selection={k:r[k] for k in review.IDENTITY};selection.update(start_s=str(r['start_time_s']),end_s=str(r['end_time_s']))
direct=dict(schema='brohn-eda-continuous-review-request/1.0',binding=dict(origin=request['report']['saved_body']['origin']),recording=r,parameters=a['parameters'][r['recording_id']],
    features=[f for f in a['features'] if all(f[k]==r[k] for k in review.IDENTITY)],selection=selection,original_source=request['original_source'],sealed_objects=[],artifacts=a['artifacts'])
if direct['artifacts']:
    actual_dir=out/'direct-new-legacy';actual_dir.mkdir();direct['export_directory']=str(actual_dir);actual=review.review(direct)
    old_dir=out/'direct-old-legacy';old_dir.mkdir();direct['export_directory']=str(old_dir);old=legacy.review(direct)
    check(display.value_hash(actual)==display.value_hash(old),'entire old1.0 reader result matches frozen baseline, including nulls/counts/exports')
    check(all((actual_dir/f).read_bytes()==(old_dir/f).read_bytes() for f in ('eda-samples.csv','eda-candidates.csv','eda-markers.csv')),'all old1.0 direct CSV bytes unchanged')
else:
    skipped.append('Direct old1.0 model/CSV comparison: generated legacy ordinary fixture has artifacts disabled. Its no-artifact preparation state is tested above; no trace regression claim.')

# A genuine count boundary, using synthetic indexed coordinates rather than
# invoking a scientific producer or changing the declared capacity.
path=out/'coordinate-boundary.jsonl';n=500001
with path.open('wb') as stream:
    for start in range(0,n,1000):
        stream.write(display.json_bytes(dict(rows=[[i/10,True] for i in range(start,min(start+1000,n))]))+b'\n')
record=dict(recording_id='r',segment_id='s',channel='eda',status='descriptive_only')
index=SimpleNamespace(entries={'physiology-series':dict(tables=[dict(spec=dict(identity={k:record[k] for k in review.IDENTITY},columns=[dict(name='time_s'),dict(name='retained')]),path=path)])})
request=dict(report=dict(ref={'id':'synthetic-coordinate-boundary'},complete_analysis=dict(parameters={'r':{}})))
try: display.selected_window_counts(index,'continuous',request,record,dict(start_s='0',end_s='50000'))
except display.Refusal as refusal:
    check(refusal.detail['measured']==500001 and refusal.detail['maximum']==500000 and refusal.detail['resource']=='coordinate_rows' and refusal.detail['reason_code']=='coordinate_rows_limit' and refusal.detail['recovery_scope']=='none','actual coordinate ceiling reports full count and forbids smaller-window recovery')
else: raise AssertionError('constant capacity boundary did not refuse')
check(originals=={str(p.relative_to(corpus)):sha(p) for p in corpus.rglob('*') if p.is_file()},'all original component fixture bytes unchanged')
result=dict(schema='brohn-eda-constant-pure-component-tests/0.1',passed=True,checks=checks,skipped=skipped,source_hashes=source_hashes,fixture_manifest_sha256=sha(corpus/'results.json'),models=models,
            scope='read-only component fixtures and explicit synthetic report wrappers; no native published source or scientific reprocessing')
(out/'results.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
print(json.dumps(dict(passed=True,checks=len(checks),output=str(out))))
