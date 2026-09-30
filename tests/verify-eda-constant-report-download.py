"""Independent saved EDA 0.1/0.2 package conservation/geometry oracle; stdlib only.

Consumes a separately retained original supervised bundle plus actual ZIP/HTML.
Never imports Brohn, fits signals, replays studies or reads a catalog database.
"""
import argparse
import csv
import hashlib
import io
import json
import math
import re
import struct
import zipfile
from collections import Counter
from html.parser import HTMLParser
from pathlib import Path
from xml.etree import ElementTree as ET

csv.field_size_limit(128*1024**2)
NS='{http://www.w3.org/2000/svg}'

def sha(raw):return hashlib.sha256(raw).hexdigest()
def loads(raw):
    def pairs(xs):
        d={}
        for k,v in xs:
            assert k not in d,('duplicate JSON key',k)
            d[k]=v
        return d
    def integer(s):
        n=int(s);assert abs(n)<=2**53-1
        return -0.0 if s=='-0' else n
    def number(s):
        n=float(s);assert math.isfinite(n);return n
    return json.loads(raw,object_pairs_hook=pairs,parse_int=integer,parse_float=number,parse_constant=lambda x:(_ for _ in ()).throw(ValueError(x)))
def same(a,b):
    if type(a) in (int,float) and type(b) in (int,float):return struct.pack('>d',a)==struct.pack('>d',b)
    if type(a) is not type(b):return False
    if isinstance(a,dict):return a.keys()==b.keys() and all(same(a[k],b[k]) for k in a)
    if isinstance(a,list):return len(a)==len(b) and all(same(x,y) for x,y in zip(a,b))
    return a==b

CONSTANT_FEATURES=('tonic_mean','tonic_median','tonic_slope','conductance_raw_mean','scr_count','scr_rate',
                   'scr_amplitude_mean','scr_amplitude_median','phasic_area_signed','phasic_area_positive')
COMPONENTS=('clean_us','tonic_us','phasic_us')
CONSTANT_COUNTS={'complete_sample_artifact_rows','complete_event_artifact_rows','segment_coordinate_rows',
    'segment_retained_coordinate_rows','segment_excluded_coordinate_rows','selected_coordinate_rows',
    'selected_retained_coordinate_rows','selected_excluded_coordinate_rows','segment_numerical_candidate_rows',
    'selected_numerical_candidate_rows','displayed_processed_points'}

def constant_findings(analysis,cell):
    """Check saved semantic distinctions independently; do not score raw data."""
    r=cell['original_support'];m=cell['model'];parameters=analysis['parameters'][r['recording_id']]
    assert parameters['recipe']=='eda-neurokit-highpass/1.1' and parameters['exact_constant_policy']=='raw_description_only/1.0'
    assert r['status']=='descriptive_only' and r['exact_flatline'] is True
    for key,value in dict(processing_branch='exact_constant_raw_description/1.0',descriptive_status='computed',
        response_status='unavailable',response_reason='exact_constant_signal',numerical_candidate_count=0,response_denominator=None).items():
        assert key in r and same(r[key],value),(key,'constant support')
    assert type(r['numerical_candidate_count']) is int
    features=[f for f in analysis['features'] if all(same(f.get(k),r.get(k)) for k in ('recording_id','segment_id','channel'))]
    assert [f['name'] for f in features]==list(CONSTANT_FEATURES)
    for f in features:
        raw=f['name']=='conductance_raw_mean';amplitude=f['name'] in ('scr_amplitude_mean','scr_amplitude_median')
        assert f['eligible'] is raw and f['support_status']==('computed' if raw else 'unavailable')
        assert 'missing_reason' in f and f['missing_reason']==(None if raw else 'exact_constant_signal')
        assert (type(f['value']) in (int,float) and math.isfinite(f['value'])) if raw else f['value'] is None
        assert ('denominator' in f)==amplitude
        if amplitude:assert f['denominator'] is None
    assert cell['status']=='raw_description_only' and cell['reason']=='exact_constant_signal' and cell['original_status']=='descriptive_only'
    assert m is not None and m['schema']=='brohn-eda-continuous-review/1.1' and m['status']=='raw_description_only'
    assert same(m['recording'],r) and same(m['parameters'],parameters) and same(m['features'],features)
    assert m['raw_available'] is False and m['unit']=='uS' and m['processed_components']==[]
    assert m['candidates']==m['markers']==[] and m['series']=={k:[] for k in COMPONENTS} and m['endpoint_coverage']=={'unobserved':[]}
    assert 'rows' not in m and 'exports' not in m and cell['model_hash'] is not None
    assert set(m['counts'])==CONSTANT_COUNTS and all(type(n) in (int,float) and not isinstance(n,bool) and n>=0 and int(n)==n for n in m['counts'].values())
    assert m['counts']['displayed_processed_points']==m['counts']['segment_numerical_candidate_rows']==m['counts']['selected_numerical_candidate_rows']==0
    from decimal import Decimal
    bounds={k:Decimal(str(r[v])) for k,v in (('start_s','start_time_s'),('end_s','end_time_s'))}
    for selection in (cell['original_default_bounds'],cell['requested_bounds'],m['selection']):
        assert all(Decimal(selection[k])==v for k,v in bounds.items())
    return features

def constant_table(spec,rows,kind,cell):
    r=cell['original_support'];m=cell['model'];counts=m['counts']
    assert same(spec['support']['source'],r) and same(spec['support']['method'],m['parameters'])
    assert spec['support']['raw_source_omitted'] is True
    if kind=='physiology-events':
        assert spec['expected_rows']==0 and rows==[]
        return 0
    names=[c['name'] for c in spec['columns']]
    assert names==['time_s','source_sample_index',*COMPONENTS,'retained']
    assert all(c['nullable'] is True for c in spec['columns'] if c['name'] in COMPONENTS)
    n=len(rows);retained=0;previous=None;fs=r['sampling_rate'];edge=math.ceil(m['parameters']['edge_exclusion_s']*fs)
    assert n==spec['expected_rows']==r['samples']==r['source_row_end_exclusive']-r['source_row_start']
    for i,values in enumerate(rows):
        t,index,clean,tonic,phasic,keep=values
        assert type(t) in (int,float) and not isinstance(t,bool) and math.isfinite(t)
        assert previous is None or 0<t-previous<=1.5/fs+1e-12
        assert type(index) is int and index==r['source_row_start']+i
        assert clean is tonic is phasic is None and type(keep) is bool
        assert keep==(edge<=i<n-edge)
        retained+=keep;previous=t
    assert same(rows[0][0],r['start_time_s']) and same(rows[-1][0],r['end_time_s'])
    assert retained==r['retained_samples'] and n-retained==r['filter_edge_samples']
    for prefix in ('segment_','selected_'):
        assert counts[prefix+'coordinate_rows']==n and counts[prefix+'retained_coordinate_rows']==retained and counts[prefix+'excluded_coordinate_rows']==n-retained
    return n
def inventory(path):
    with zipfile.ZipFile(path) as z:
        rows=z.infolist();names=[r.filename for r in rows]
        assert names==sorted(set(names)) and len(names)<=1024
        assert sum(r.file_size for r in rows)<=256*1024**2
        for r in rows:
            assert re.fullmatch(r'[A-Za-z0-9._/-]+',r.filename) and not set(r.filename.split('/'))&{'','.','..'}
            assert r.compress_type==zipfile.ZIP_STORED and r.date_time==(1980,1,1,0,0,0) and not r.flag_bits&1
            assert not r.extra and not r.comment and not r.is_dir()
        payload={r.filename:z.read(r) for r in rows}
    manifest=loads(payload['manifest.json']);files=manifest['files']
    assert len({r['path'] for r in files})==len(files)
    assert set(payload)=={r['path'] for r in files}|{'manifest.json'}
    for r in files:assert sha(payload[r['path']])==r['sha256'] and len(payload[r['path']])==r['bytes'],r['path']
    return payload,manifest

class Document(HTMLParser):
    def __init__(self):super().__init__();self.ids=[];self.refs=[];self.tags=[]
    def handle_starttag(self,tag,attrs):
        a=dict(attrs);self.tags.append(tag);assert not any(k.lower().startswith('on') for k in a)
        if 'id' in a:self.ids.append(a['id'])
        for key in ('href','src','xlink:href'):
            if key in a:self.refs.append(a[key])

def main():
    p=argparse.ArgumentParser();p.add_argument('--bundle',type=Path,required=True);p.add_argument('--zip',type=Path,required=True)
    p.add_argument('--html',type=Path);p.add_argument('--compare-zip',type=Path);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
    assert not a.output.exists();a.output.mkdir(parents=True)
    checks=[];leaves=0;identity_fields=0;links={};reverse={};source_files={};constant_count=0;constant_coordinates=0
    def check(label,ok):assert ok,label;checks.append(label)
    bundle_raw=a.bundle.read_bytes();bundle=loads(bundle_raw);payload,manifest=inventory(a.zip)
    profile=bundle['selection']['renderer_profile']
    assert profile in ('controlled-gaze-explicit-task-choice-eda-paired/0.1','controlled-gaze-explicit-task-choice-eda-paired/0.2')
    version=profile.rsplit('/',1)[1]
    original_mode=bundle['selection']['contents_policy']['identifier_mode']=='source_identifiers'
    check('independent ZIP CRC, deterministic inventory, bytes and SHA',True)
    check('exact frozen selection',same(manifest['selection'],{k:v for k,v in bundle['selection'].items() if k not in ('intent_ref','generation')}))
    if a.html:check('actual downloaded HTML matches ZIP bytes',a.html.read_bytes()==payload['report.html'])
    for key in ('reports','distributions','task_displays','choice_displays','eda_displays'):
        check('exact ordered '+key,same(manifest['sources'][key],[x['ref'] for x in bundle[key]]))
    for key in ('related_eda_sources','source_identity_graph_binding'):
        expected=bundle['selection']['related_eda_refs' if key=='related_eda_sources' else key]
        check('exact frozen '+key,same(manifest['sources'][key],expected))
    reports=bundle['reports']+[x['report'] for x in bundle['related_eda_sources']]
    graph=bundle['source_identity_graph']
    identity_refs=[r['ref'] for r in reports]+[n['ref'] for n in graph['nodes'] if n['source_ordinal'] is None]
    projections=[];displays={};original_displays={}
    def alias(old,new,source,kind,recording,channel,group,path):
        nonlocal identity_fields
        if original_mode or old is None or old=='':assert same(old,new),(path,'original/null/blank identity');return
        assert isinstance(old,str) and isinstance(new,str) and re.fullmatch(r'(?:report-\d+|related-source-\d+)-[a-z-]+-\d+',new),(path,old,new)
        assert new.startswith(f'report-{source:02}-'),(path,'wrong exact source namespace')
        person=group.get('participant_id');session=group.get('session_id')
        scope=() if kind=='person' else (person,) if kind=='session' else (person,session)
        if kind in ('segment','event','exposure'):scope+=(recording,)
        if kind=='segment':scope+=(channel,)
        key=(source,kind,*scope,old)
        assert key not in links or links[key]==new,(path,'same original scope split')
        rev=(source,kind,new);assert rev not in reverse or reverse[rev]==key,(path,'distinct original scopes merged')
        links[key]=new;reverse[rev]=key;identity_fields+=1
    def compare(old,new,source,path='',recording=None,channel=None,group=None,protected=False):
        nonlocal leaves
        group=group or {}
        if isinstance(old,dict):
            assert isinstance(new,dict),(path,'object type')
            r=old.get('recording_id',recording);ch=old.get('channel',channel);g=dict(old.get('group',group))
            # Paired/questionnaire rows carry person/session directly; equal
            # visit text from different people is not the same original scope.
            for identity_key in ('participant_id','session_id'):
                if identity_key in old:g[identity_key]=old[identity_key]
            source_index=source
            parent_id=old.get('source_report_id') or (old.get('report_id') if 'source_participant_id' in old else None)
            if parent_id is not None:
                matches=[n for n,v in enumerate(identity_refs,1) if v['id']==parent_id and
                         ('source_report_hash' not in old or v['body_hash']==old['source_report_hash']) and
                         ('source_report_revision' not in old or v['revision']==old['source_report_revision'])]
                assert len(matches)==1,(path,'exact selected/related identity parent');source_index=matches[0]
            if path=='/analysis/parameters' and source in recording_maps:
                rm=recording_maps[source];assert set(new)=={rm[k] for k in old},(path,'parameter recording keys')
                for k,v in old.items():compare(v,new[rm[k]],source,path+'/'+k,k,None,groups[source].get(k,{}),True)
                return
            omitted=set()
            if path=='/provenance/source':omitted=set(old)-{'hash','size','bytes','media_type','format'}
            if path.startswith('/provenance') and path.endswith('/asset'):omitted|={'filename','path'}&old.keys()
            assert old.keys()-omitted==new.keys(),(path,'fields/null/absence conservation',old.keys()-new.keys(),new.keys()-old.keys())
            for k,v in old.items():
                if k in omitted:continue
                nxt=path+'/'+k;kind=None;lock=protected or k in ('engine','artifacts','artifact_verification','verification','columns','coordinates','endpoint_coverage','display_policy') or (k=='source' and not path.endswith('/support'))
                if not lock:
                    kind={'participant_id':'person','session_id':'session','run_id':'session','recording_id':'recording','segment_id':'source-segment' if path.endswith('/group') else 'segment','source_recording_id':'source-recording' if path.endswith('/group') else 'recording','source_segment_id':'segment','source_participant_id':'person','source_session_id':'session','exposure_id':'exposure','source_exposure_id':'exposure','event_id':'event'}.get(k)
                    if k=='id' and old.get('type') in ('stimulus_event','nuisance_event'):kind='event'
                if kind:
                    if k.startswith('source_') and not path.endswith('/group'):
                        alias(v,new[k],source_index,kind,old.get('source_recording_id',r),old.get('support',{}).get('channel',old.get('outcome_id',ch)),{'participant_id':old.get('source_participant_id'),'session_id':old.get('source_session_id')},nxt)
                    else:alias(v,new[k],source,kind,r,ch,g,nxt)
                elif k=='overlapping_event_ids' and not lock:
                    assert len(v)==len(new[k])
                    for x,y in zip(v,new[k]):alias(x,y,source,'event',r,ch,g,nxt)
                elif k=='support' and 'source_recording_id' in old:
                    compare(v,new[k],source_index,nxt,old['source_recording_id'],old.get('outcome_id',ch),{'participant_id':old.get('source_participant_id'),'session_id':old.get('source_session_id')},lock)
                else:compare(v,new[k],source,nxt,r,ch,g,lock)
        elif isinstance(old,list):
            assert isinstance(new,list) and len(old)==len(new),(path,'array length/order')
            for i,(x,y) in enumerate(zip(old,new)):compare(x,y,source,path+'/'+str(i),recording,channel,group,protected)
        else:assert same(old,new),(path,old,new);leaves+=1
    groups={};recording_maps={}
    for i,report in enumerate(reports,1):
        projected=loads(payload[f'evidence/report-{i:02}.json']);projections.append(projected)
        original=report['complete_analysis'];groups[i]={};recording_maps[i]={}
        if original['kind']=='eda':
            for x,y in zip(original['recordings'],projected['analysis']['recordings']):
                rid=x['recording_id'];groups[i][rid]=x.get('group',{})
                assert rid not in recording_maps[i] or recording_maps[i][rid]==y['recording_id']
                recording_maps[i][rid]=y['recording_id']
        else:recording_maps.pop(i)
    relationships=loads(payload['evidence/eda/identity-relationships.json'])
    check('identity graph retains exact roots and parent edges',same(relationships['root_refs'],graph['root_refs']) and same(relationships['edges'],graph['edges']) and len(relationships['nodes'])==len(graph['nodes']))
    for old,new in zip(graph['nodes'],relationships['nodes']):
        check('exact source context binding '+old['ref']['id'],all(same(new[k],old[k]) for k in ('ref','source_ordinal','analysis_kind')) and new['original_context_hash']==old['context_hash'])
        source=next(i for i,ref in enumerate(identity_refs,1) if same(ref,old['ref']))
        compare(old['provenance_context'],new['projected_provenance_context'],source,'/provenance')
    for i,(report,projection) in enumerate(zip(reports,projections),1):
        original=report['complete_analysis'];projected=projection['analysis']
        check(f'source{i} exact original report and result reference',same(projection['source_ref'],report['ref']) and same(projection['source_result_object'],report['saved_body'].get('result_object')))
        # The external companion relationship assertions below bind combined
        # source labels; full recursive comparison still checks every value.
        compare(original,projected,i,'/analysis')
        compare(report['saved_body']['provenance'],projection['provenance'],i,'/provenance')
        check(f'source{i} every original scientific field, value, null and order',True)
        family={'eda':'eda','questionnaire':'explicit','multimodal':'paired'}[original['kind']]
        for collection in ('features','observations'):
            if collection not in original:continue
            rows=list(csv.DictReader(io.StringIO(payload[f'data/{family}/report-{i:02}-{collection}.csv'].decode('utf-8'),newline='')))
            check(f'source{i} full {collection} CSV',len(rows)==len(projected[collection]) and all(int(r['source_order'])==n+1 and same(loads(r['record_json']),projected[collection][n]) for n,r in enumerate(rows)))
        if original['kind']!='eda':continue
        entry=next(d for d in bundle['eda_displays'] if same(d['body']['source']['report_ref'],report['ref']))
        evidence_path=Path(entry['evidence']['path']);raw=evidence_path.read_bytes();source_files[str(evidence_path)]=sha(raw)
        check(f'source{i} exact saved display bytes',sha(raw)==entry['evidence']['hash'] and len(raw)==entry['evidence']['bytes'])
        old=loads(raw);new=loads(payload[f'evidence/eda/source-{i:03}/display.json']);original_displays[i]=old;displays[i]=new
        check(f'source{i} exact renderer/preparation/evidence generation',entry['body']['schema']=='brohn-saved-eda-display/'+version and entry['body']['implementation']['profile']=='saved-eda-display/'+version and old['schema']=='brohn-eda-display-evidence/'+version)
        constants=[]
        assert len(old['cells'])==len(original['recordings'])
        for position,cell in enumerate(old['cells'],1):
            assert cell['source_record_index']==position and same(cell['original_support'],original['recordings'][position-1])
            if original['recordings'][position-1]['status']=='descriptive_only':assert cell['status']=='raw_description_only'
            recipe=original['parameters'][cell['identity']['recording_id']]['recipe']
            if recipe=='eda-neurokit-highpass/1.1':assert version=='0.2'
            if cell['status']=='raw_description_only':
                constant_findings(original,cell);constants.append(cell)
                constant_count+=1
                check(f'source{i} constant ten findings/null denominators/non-null model',True)
            elif recipe=='eda-neurokit-highpass/1.0' and cell['model'] is not None:
                assert cell['model']['schema']=='brohn-eda-continuous-review/1.0' and 'processed_components' not in cell['model']
                check(f'source{i} old scientific recipe keeps exact old model grammar inside new package',True)
        check(f'source{i} exact complete prepared display bindings',all(same(old[k],new[k]) for k in old if k!='cells') and len(old['cells'])==len(new['cells']))
        for x,y in zip(old['cells'],new['cells']):
            assert set(y)==set(x)|{'projected_model_value_hash'}
            for key in x:
                if key in ('identity','selection','original_support','model'):
                    compare(x[key],y[key],i,'/display/'+key,x['identity']['recording_id'],x['identity']['channel'],x['original_support'].get('group',{}))
                else:assert same(x[key],y[key]),('original cell wrapper',key)
        check(f'source{i} all prepared points, candidates, support and original hashes',True)
        receipt=loads(payload[f'evidence/eda/source-{i:03}/projection-receipt.json'])
        check(f'source{i} exact complete-stream projection generation',receipt['schema']=='brohn-eda-stream-projection-result/'+version and all(x['schema']=='brohn-report-eda-stream-projection/'+version for x in receipt['streams']))
        check(f'source{i} full processed stream inventory',len(receipt['streams'])==len(entry['streams']) and receipt['coverage']['complete'] is True)
        coordinate_only_rows=0;constant_tables=set()
        for cell in constants:
            for kind,key in (('physiology-series','complete_sample_artifact_rows'),('physiology-events','complete_event_artifact_rows')):
                source_stream=next(s for s in entry['streams'] if s['original']['kind']==kind)
                assert cell['model']['counts'][key]==source_stream['original']['rows']
        for stream,pr in zip(entry['streams'],receipt['streams']):
            path=Path(stream['path']);data=path.read_bytes();source_files[str(path)]=sha(data)
            check(f'source{i} original stream byte binding',sha(data)==stream['original']['hash'] and len(data)==stream['original']['size'] and same(pr['original'],stream['original']) and same(pr['source_verification'],stream['original_verification']))
            stem='series' if stream['original']['kind']=='physiology-series' else 'candidates';name=f'evidence/eda/source-{i:03}/streams/{stem}.ndjson'
            derived=payload[name];before=data.splitlines(keepends=True);after=derived.splitlines(keepends=True)
            assert len(before)==len(after)
            actual_rows=[];row_bytes=[];table=None;tables_by_id={};rows_by_id={}
            for x,y in zip(before,after):
                xo,yo=loads(x),loads(y);assert xo['type']==yo['type']
                if xo['type']=='rows':
                    assert x==y,(name,'source row record bytes');row_bytes.append(x)
                    for n,row in enumerate(xo['rows']):actual_rows.append((xo['table_id'],xo['offset']+n,row))
                    rows_by_id[xo['table_id']].extend(xo['rows'])
                elif xo['type']=='table':
                    table=xo;compare(xo,yo,i,'/table',xo['identity']['recording_id'],xo['identity']['channel'],xo['identity'].get('group',{}))
                    tables_by_id[xo['table_id']]=xo;rows_by_id[xo['table_id']]=[]
                elif xo['type']=='header':
                    assert xo.keys()==yo.keys();compare(xo['provenance'],yo['provenance'],i,'/header/provenance',protected=True)
                    assert same({k:v for k,v in xo.items() if k not in ('provenance','provenance_sha256')},{k:v for k,v in yo.items() if k not in ('provenance','provenance_sha256')})
                elif xo['type']=='complete':assert same({k:v for k,v in xo.items() if k!='provenance_sha256'},{k:v for k,v in yo.items() if k!='provenance_sha256'})
                else:assert x==y
            if original_mode:assert data==derived
            check(f'source{i} {stem} all exact original row records',len(actual_rows)==stream['original']['rows'] and sha(b''.join(row_bytes))==pr['unchanged_row_record_sha256'])
            csv_rows=list(csv.DictReader(io.StringIO(payload[f'evidence/eda/source-{i:03}/streams/{stem}.csv'].decode('utf-8'),newline='')))
            check(f'source{i} {stem} complete typed CSV rows',len(csv_rows)==len(actual_rows) and all(r['table_id']==t and int(r['table_row_index'])==n and same(loads(r['record_json']),row) for r,(t,n,row) in zip(csv_rows,actual_rows)))
            assert sha(derived)==pr['projected']['sha256'] and len(derived)==pr['projected']['bytes']
            for tid,spec in tables_by_id.items():
                matches=[c for c in constants if all(same(c['identity'][k],spec['identity'][k]) for k in ('recording_id','segment_id','channel'))]
                if matches:
                    assert len(matches)==1
                    coordinate_only_rows+=constant_table(spec,rows_by_id[tid],stream['original']['kind'],matches[0])
                    constant_tables.add((matches[0]['key'],stream['original']['kind']))
                    check(f'source{i} {tid} exact constant coordinate/null/mask or empty candidate rows',True)
                elif stream['original']['kind']=='physiology-series' and 'method' in spec['support']:
                    assert spec['support']['method']['recipe'] in ('eda-neurokit-highpass/1.0','eda-neurokit-highpass/1.1')
                    assert spec['support']['source']['status']=='computed'
                    columns={c['name']:c for c in spec['columns']}
                    assert all(columns[k]['nullable'] is False for k in COMPONENTS)
                    names=[c['name'] for c in spec['columns']]
                    for row in rows_by_id[tid]:
                        assert all(type(row[names.index(k)]) in (int,float) and math.isfinite(row[names.index(k)]) for k in COMPONENTS)
                    check(f'source{i} {tid} ordinary/legacy table keeps finite nonnullable processed grammar',True)
        assert len(constant_tables)==2*len(constants)
        assert len(constants)==sum(r['status']=='descriptive_only' for r in original['recordings'])
        if version=='0.2':
            coverage=old['coverage']
            check(f'source{i} complete coordinate-only coverage and no full raw waveform',coverage['descriptive_only_cells']==len(constants) and coverage['coordinate_only_rows']==coordinate_only_rows and coverage['complete_coordinate_rows'] is True and coverage['complete_raw_series_included'] is False and coverage['original_raw_preview_preserved'] is True and coverage['cells']==coverage['available_cells']+coverage['unavailable_cells']+coverage['descriptive_only_cells'])
        constant_coordinates+=coordinate_only_rows
    for i,(report,projection) in enumerate(zip(reports,projections),1):
        for o in projection['analysis'].get('observations',[]):
            if o.get('modality')!='eda':continue
            j=next(j for j,r in enumerate(reports) if r['ref']['id']==o['source_report_id'] and r['ref']['revision']==o['source_report_revision'] and r['ref']['body_hash']==o['source_report_hash'])
            f=projections[j]['analysis']['features'][o['source_row']-1]
            check(f'combined source{i} exact original EDA feature/alias edge',same(o['value'],f['value']) and o['source_recording_id']==f['recording_id'] and o['source_segment_id']==f['segment_id'] and o['source_participant_id']==f['group']['participant_id'] and o['source_session_id']==f['group']['session_id'])
    doc=Document();doc.feed(payload['report.html'].decode('utf-8'))
    check('offline HTML unique IDs and no executable/network resources',len(doc.ids)==len(set(doc.ids)) and not set(doc.tags)&{'script','iframe','object','embed'} and all(not re.match(r'(https?:|file:|//)',r) for r in doc.refs))
    figures=0;points=0;markers=0;scales={}
    for f in manifest['files']:
        if f['media_type']!='image/svg+xml':continue
        tree=ET.fromstring(payload[f['path']]);ids=[x.attrib['id'] for x in tree.iter() if 'id' in x.attrib];assert len(ids)==len(set(ids))
        for x in tree.iter():
            for key in ('aria-labelledby','aria-describedby'):
                assert key not in x.attrib or all(t in ids for t in x.attrib[key].split())
        node=tree.find(NS+'metadata');meta=loads(node.text) if node is not None else {}
        if 'cell_key' not in meta:continue
        figures+=1;i=next(i for i,r in enumerate(reports,1) if same(r['ref'],meta['source']))
        cell=next(c for c in displays[i]['cells'] if c['key']==meta['cell_key']);model=cell['model']
        check(f['path']+' self-contained background',any(x.tag==NS+'rect' and x.attrib.get('fill')=='#14202b' and x.attrib.get('width')=='900' for x in tree))
        if model is None or cell['status'] in ('no_processed_samples','raw_description_only'):
            assert not any('data-group' in x.attrib or 'data-marker-kind' in x.attrib for x in tree.iter())
            if cell['status']=='raw_description_only':
                assert not any(x.tag in {NS+'polyline',NS+'circle',NS+'path',NS+'line'} for x in tree.iter())
                assert 'No waveform or physiological zero response is inferred' in ''.join(tree.itertext())
                check(f['path']+' raw-description status has no numerical waveform or zero-response claim',True)
            continue
        component=meta['component'];axis=meta['axis'];lo,hi=axis['bounds'];assert lo<hi
        xr=model.get('range_s') or [float(model['selection']['start_s']),float(model['selection']['end_s'])]
        xx=lambda x:80+(x-xr[0])/(xr[1]-xr[0])*780
        yy=lambda y:340-(y-lo)/(hi-lo)*220
        polylines=[x for x in tree.iter() if 'data-group' in x.attrib]
        assert len(polylines)==len(model['series'][component])
        for line,group in zip(polylines,model['series'][component]):
            coords=[tuple(map(float,p.split(','))) for p in line.attrib['points'].split()];assert len(coords)==len(group['points'])
            for (x,y),sample in zip(coords,group['points']):assert abs(x-xx(sample['time_s']))<1e-7 and abs(y-yy(sample['value']))<1e-7;points+=1
        if model.get('event') is not None:
            key=(i,cell['identity']['channel'],component);assert key not in scales or same(scales[key],axis);scales[key]=axis
            assert any(x.attrib.get('data-measured-onset')=='0' for x in tree.iter())
            assert {x.attrib['data-window'] for x in tree.iter() if 'data-window' in x.attrib}=={'baseline','response'}
        if component=='phasic_us':
            page=int(meta['marker_page']);candidates=model['candidates'][(page-1)*50:page*50];event=model.get('event') is not None
            def belongs(mark):return mark['candidate_source_peak_sample'] in [c['source_peak_sample'] for c in candidates] if event else mark['candidate_table_row_index'] in [c['table_row_index'] for c in candidates]
            expected=[m for m in model['markers'] if (belongs(m) or m.get('selected_for_event') is True) and m['in_view'] and type(m.get('phasic_us')) in (int,float) and type(m.get('relative_time_s' if event else 'time_s')) in (int,float)]
            marks=[x for x in tree.iter() if 'data-marker-kind' in x.attrib];assert len(marks)==len(expected)
            for mark,old in zip(marks,expected):
                assert mark.attrib['data-marker-kind']==old['kind'] and mark.attrib['data-page-member']==str(belongs(old)).lower() and mark.attrib['data-reference-anchor']==str(old.get('selected_for_event') is True).lower();markers+=1
        check(f['path']+' all representative geometry, boundaries and exact marker membership',True)
    if a.compare_zip:
        previous,prior=inventory(a.compare_zip)
        check('figure-only revision retains exact frozen source identities',same(prior['sources'],manifest['sources']))
        def complete(data,m):return Counter((f['role'],f['media_type'],f['bytes'],sha(data[f['path']])) for f in m['files'] if f['path'].startswith(('evidence/','data/')))
        check('figure-only revision retains every complete companion byte and multiplicity',complete(payload,manifest)==complete(previous,prior))
    check('original artifact files unchanged after oracle',all(sha(Path(p).read_bytes())==h for p,h in source_files.items()))
    result={'passed':True,'check_count':len(checks),'checks':checks,'scientific_leaves':leaves,'identity_fields':identity_fields,'eda_figures':figures,'representative_coordinates':points,'observed_marker_membership':markers,'constant_cells':constant_count,'constant_coordinate_rows':constant_coordinates,'renderer_profile':profile,'bundle_sha256':sha(bundle_raw),'zip_sha256':sha(a.zip.read_bytes()),'html_sha256':sha(payload['report.html']),'oracle_sha256':sha(Path(__file__).read_bytes()),'original_artifacts':source_files,'scope':'Independent complete original EDA/mixed questionnaire/paired scientific and typed-stream conservation, constant null/descriptive/coordinate distinctions, original identity joins, deterministic ZIP/HTML and actual SVG geometry; no scientific estimator or browser/authority qualification.'}
    (a.output/'results.json').write_text(json.dumps(result,indent=2,ensure_ascii=True),encoding='utf-8')
    print(json.dumps({k:v for k,v in result.items() if k not in ('checks','original_artifacts')}))

if __name__=='__main__':main()
