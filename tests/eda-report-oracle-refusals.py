"""Malformed copied exports with valid ZIP inventory hashes must still refuse."""
import argparse,copy,hashlib,importlib.util,json,subprocess,sys,zipfile
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('bundle',type=Path);p.add_argument('archive',type=Path);p.add_argument('output',type=Path);a=p.parse_args()
a.output.mkdir(parents=True,exist_ok=False)
verifier=Path(__file__).with_name('verify-eda-report-download.py')
spec=importlib.util.spec_from_file_location('independent_eda_oracle',verifier);oracle=importlib.util.module_from_spec(spec);spec.loader.exec_module(oracle)
original,manifest=oracle.inventory(a.archive)
bundle=oracle.loads(a.bundle.read_bytes());reports=bundle['reports']+[x['report'] for x in bundle['related_eda_sources']]
i=next(i for i,r in enumerate(reports,1) if r['complete_analysis']['kind']=='eda')
report=f'evidence/report-{i:02}.json';display=f'evidence/eda/source-{i:03}/display.json';stream=f'evidence/eda/source-{i:03}/streams/series.ndjson'
def changed_value(d):
    row=next(f for f in d['analysis']['features'] if type(f['value']) in (int,float));row['value']+=0.12345
def unknown_field(d):d['analysis']['features'][0]['new_unregistered_value']=0
def false_number(d):
    row=next((f for f in d['analysis']['features'] if isinstance(f.get('eligible'),bool)),None)
    if row is not None:row['eligible']=int(row['eligible'])
    else:
        row=next(r for r in d['analysis']['recordings'] if isinstance(r.get('exact_flatline'),bool));row['exact_flatline']=int(row['exact_flatline'])
def dropped_feature(d):d['analysis']['features'].pop()
def model_value(d):
    cell=next(c for c in d['cells'] if c['model'] and any(c['model']['series']['phasic_us']))
    cell['model']['series']['phasic_us'][0]['points'][0]['value']+=0.125
cases=[('saved-value-substitution',report,changed_value),('unknown-scientific-field',report,unknown_field),('boolean-coerced-to-number',report,false_number),('dropped-full-feature',report,dropped_feature),('prepared-point-substitution',display,model_value)]
paired=next((n for n,r in enumerate(reports,1) if r['complete_analysis']['kind']=='multimodal'),None)
if paired is not None:
    def merged_visits(d):
        rows=next(c['session_differences'] for c in d['analysis']['contrasts'] if len(c['session_differences'])>1)
        assert rows[0]['participant_id']!=rows[1]['participant_id']
        rows[1]['session_id']=rows[0]['session_id']
    def wrong_parent(d):
        row=next(o for o in d['analysis']['observations'] if o['modality']=='eda')
        row['source_participant_id']='report-99-person-0001'
    def broken_context(d):
        node=next(n for n in d['nodes'] if n['projected_provenance_context'].get('crosswalk'))
        node['projected_provenance_context']['crosswalk'][0]['source_participant_id']='report-99-person-0001'
    cases.extend([('distinct-person-visits-merged',f'evidence/report-{paired:02}.json',merged_visits),('wrong-exact-parent-namespace',f'evidence/report-{paired:02}.json',wrong_parent),('broken-crosswalk-context-link','evidence/eda/identity-relationships.json',broken_context)])
outcomes=[]
for name,path,mutate in cases+[('typed-source-row-substitution',stream,None)]:
    payload=copy.copy(original)
    if mutate:
        data=oracle.loads(payload[path]);mutate(data);payload[path]=json.dumps(data,separators=(',',':'),ensure_ascii=True).encode()
    else:
        lines=payload[path].splitlines(keepends=True)
        for n,line in enumerate(lines):
            data=oracle.loads(line)
            if data['type']=='rows' and data['rows']:
                data['rows'][0][-1]=not data['rows'][0][-1]
                lines[n]=json.dumps(data,separators=(',',':'),ensure_ascii=True).encode()+b'\n';break
        else:raise AssertionError('No original complete row')
        payload[path]=b''.join(lines)
    m=oracle.loads(payload['manifest.json'])
    for f in m['files']:
        raw=payload[f['path']];f.update(bytes=len(raw),sha256=hashlib.sha256(raw).hexdigest())
    payload['manifest.json']=json.dumps(m,separators=(',',':'),ensure_ascii=True).encode()
    archive=a.output/(name+'.zip')
    with zipfile.ZipFile(archive,'w',compression=zipfile.ZIP_STORED) as z:
        for member in sorted(payload):z.writestr(zipfile.ZipInfo(member,(1980,1,1,0,0,0)),payload[member])
    oracle.inventory(archive)  # Prove rejection below is not ZIP inventory damage.
    r=subprocess.run([sys.executable,'-B',str(verifier),'--bundle',str(a.bundle),'--zip',str(archive),'--output',str(a.output/name)],capture_output=True,text=True,timeout=90)
    (a.output/(name+'.stderr.txt')).write_text(r.stderr,encoding='utf-8')
    assert r.returncode!=0 and 'AssertionError' in r.stderr,name
    outcomes.append({'case':name,'refused':True,'reason':r.stderr.splitlines()[-1]})
result={'passed':True,'checks':len(outcomes),'outcomes':outcomes,'verifier_sha256':hashlib.sha256(verifier.read_bytes()).hexdigest(),'original_archive_sha256':hashlib.sha256(a.archive.read_bytes()).hexdigest(),'scope':'Copied scientific/model/typed-row mutations with independently valid ZIP inventories; originals untouched, no application or science imports'}
(a.output/'results.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8');print(json.dumps({'passed':True,'checks':len(outcomes)}))
