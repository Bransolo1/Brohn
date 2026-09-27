"""Independent complete scientific projection / CSV / ZIP checks. No R imports."""
import bisect, csv, hashlib, io, json, pathlib, re, sys, zipfile
from decimal import Decimal
from html.parser import HTMLParser
import xml.etree.ElementTree as ET
csv.field_size_limit(128*1024*1024)

root=pathlib.Path(sys.argv[1]);output=pathlib.Path(sys.argv[2]);assert not output.exists()
excluded_names=set(sys.argv[3:])
checks=[];values=0;aliases=0;identifier_mode='package_aliases'
def read(path):return json.loads(path.read_bytes(),parse_float=Decimal)
def loads(text):return json.loads(text,parse_float=Decimal)
def check(label,condition):
    assert condition,label
    checks.append(label)
def numeric(x):return type(x) in (int,Decimal)
def same(a,b):
    if numeric(a) and numeric(b):return a==b
    if type(a)!=type(b):return False
    if isinstance(a,dict):return a.keys()==b.keys() and all(same(a[k],b[k]) for k in a)
    if isinstance(a,list):return len(a)==len(b) and all(same(x,y) for x,y in zip(a,b))
    return a==b
def alias(source,target,path):
    global aliases,values
    if identifier_mode=='source_identifiers':
        assert same(source,target),(path,source,target)
        values+=1;return
    if source is None:assert target is None,path
    elif source=='':assert target=='',path
    else:assert isinstance(target,str) and re.fullmatch(r'(report-\d+|related-source-\d+)-(person|session|administration|source-attempt|source-person|source-session|exposure|assessment|event|step|visit|occurrence|clock-instance)-\d+',target),(path,source,target)
    aliases+=1

def compare(a,b,path='',mapping=None):
    global values
    # Only explicitly registered identity roles may change. The recursive
    # values/ordering/null/type comparison covers every other original field.
    if isinstance(a,dict):
        assert isinstance(b,dict),path
        omitted=set()
        if path.endswith('/parameters/mapping/protocol_registry') or (path.startswith('/native-terminal') and path.endswith('/asset')):omitted={'filename','path'} & a.keys()
        assert a.keys()-omitted==b.keys(),(path,'fields',a.keys(),b.keys())
        for k,v in a.items():
            if k in omitted:continue
            p=path+'/'+k
            identity=False
            if '/source_rows/' in path and path.endswith('/original_cells'):
                identity=mapping is not None and k in [mapping.get(f'{r}_column') for r in ('participant','session','attempt')]
            elif not any('/'+f+'/' in p for f in ('value','previous_value','invalidated_value','item_values','value_before_conversion','original_cells')):
                identity=k in {'participant_id','session_id','run_id','person_id','source_participant_id','source_session_id','source_attempt_id',
                    'exposure_id','source_exposure_id','assessment_exposure_id','assessment_id','event_id','first_answer_event_id','last_answer_event_id','step_id','visit_id','occurrence_id','instance_id',
                    'invalidated_by_event_id','invalidated_event_id','trigger_event_id','previous_answer_event_id','cause_event_id','previous_head_event_id','from_visit_id','clock_segment_id'}
                identity=identity or k=='attempt_id' and ('/task_scores/' in p or '/task_attempts/' in p or '/membership/' in p or '/attempt_metrics/' in p)
                identity=identity or k=='id' and re.search(r'/task_attempts/\d+$',path) is not None
                identity=identity or path.startswith('/native-terminal') and k in {'task_step_id','attempt_id'}
            if identity:alias(v,b[k],p)
            elif k in ('attempt_ids','contributing_attempt_ids','contributing_session_ids'):
                assert len(v)==len(b[k]),p
                for n,(x,y) in enumerate(zip(v,b[k])):alias(x,y,p+'/'+str(n))
            else:compare(v,b[k],p,mapping)
    elif isinstance(a,list):
        assert isinstance(b,list) and len(a)==len(b),(path,'length')
        for i,(x,y) in enumerate(zip(a,b)):compare(x,y,path+'/'+str(i),mapping)
    else:
        assert same(a,b),(path,a,b)
        values+=1

class Document(HTMLParser):
    def __init__(self):super().__init__();self.ids=[];self.refs=[];self.tags=[];self.headings=[];self.depth=0;self.current='';self.scrolls=[];self.canvas=0
    def handle_starttag(self,tag,attrs):
        d=dict(attrs);self.tags.append(tag)
        if 'brohn-task-scroll' in d.get('class','').split():self.scrolls.append(d)
        if 'brohn-task-chart-canvas' in d.get('class','').split():self.canvas+=1
        if 'id' in d:self.ids.append(d['id'])
        for k in ('href','src','xlink:href'):
            if k in d:self.refs.append(d[k])
        if tag=='h2':self.depth=1;self.current=''
        elif self.depth:self.depth+=1
    def handle_endtag(self,tag):
        if self.depth:
            self.depth-=1
            if self.depth==0:self.headings.append(self.current)
    def handle_data(self,data):
        if self.depth:self.current+=data

def csv_rows(path):
    rows=list(csv.DictReader(io.StringIO(path.read_text(encoding='utf-8'),newline='')))
    assert all(int(r['source_order'])==i+1 for i,r in enumerate(rows)),path
    return [loads(r['record_json']) for r in rows]

bundles=sorted(root.glob('*-bundle.json'))
assert bundles,'No rendered fixture bundles found'
all_bundle_count=len(bundles)
assert excluded_names<={p.name.removesuffix('-bundle.json') for p in bundles},'Unknown explicit excluded bundle'
bundles=[p for p in bundles if p.name.removesuffix('-bundle.json') not in excluded_names]
for bundle_path in bundles:
    name=bundle_path.name.removesuffix('-bundle.json');directory=root/name
    assert (directory/'report.brohn-report.zip').is_file(),'A selected fixture has no complete archive: '+name
    bundle=read(bundle_path);manifest=read(directory/'manifest.json')
    identifier_mode=bundle['selection']['contents_policy']['identifier_mode']
    for ri,item in enumerate(bundle['reports'],1):
        key=f'report-{ri:02}';a=item['complete_analysis'];p=read(directory/f'evidence/{key}.json')['analysis']
        mapping=a.get('parameters',{}).get('mapping')
        compare(a,p,'/analysis',mapping)
        check(name+'/'+key+' every non-identity scientific value/type/key/order preserved',True)
        for field in ('task_scores','task_attempts','source_rows','membership','attempt_metrics','per_session','per_person','summaries'):
            if field in p:check(name+'/'+key+' complete '+field+' typed CSV matches projection',same(csv_rows(directory/f'data/tasks/{key}-{field.replace("_","-")}.csv'),p[field]))
        if p.get('kind')=='questionnaire':
            for field in ('observations','features'):
                target=directory/f'data/explicit/{key}-{field}.csv'
                if target.exists():check(name+'/'+key+' complete explicit '+field+' CSV matches original typed projection',same(csv_rows(target),p[field]))
            target=directory/f'data/explicit/{key}-scales.csv'
            if target.exists():check(name+'/'+key+' complete scale assessment CSV matches original typed projection',same(csv_rows(target),p['scales']['observations']))
        task=read(directory/f'evidence/tasks/{key}.json');e=task['evidence']
        original_entry=[x for x in bundle['task_displays'] if x['evidence']['source']['report_ref']==item['ref']][0]
        for ai,adm in enumerate(e['administrations'],1):
            original=original_entry['evidence']['administrations'][ai-1];score=p['task_scores'][adm['score_binding']['index']-1]
            stem=f'data/tasks/{key}-administration-{ai:04}'
            check(name+'/'+key+f' administration{ai} all expected rows exact',same(adm['plot_model']['rows'],original['plot_model']['rows']) and
                  same(csv_rows(directory/f'{stem}-positions.csv'),original['plot_model']['rows']))
            if adm['source_kind']=='native':
                terminal=adm['terminal_evidence'];raw=original['terminal_evidence']
                compare(raw,terminal,'/native-terminal',mapping)
                check(name+'/'+key+' full native terminal registry/declarations/scientific values preserved',True)
                if identifier_mode=='package_aliases':check(name+'/'+key+' verified native bridge joins every terminal row',all(r['participant_id']==score['participant_id'] and r['session_id']==score['session_id'] and r['attempt_id']==terminal['task_step_id'] for r in terminal['rows']))
                else:check(name+'/'+key+' original native terminal identities remain exact',all(all(same(x[k],y[k]) for k in ('participant_id','session_id','attempt_id')) for x,y in zip(raw['rows'],terminal['rows'])))
                for x,y in zip(raw['rows'],terminal['rows']):
                    for k in x:
                        if k not in ('participant_id','session_id','attempt_id'):assert same(x[k],y[k]),(name,k)
                check(name+'/'+key+' complete terminal CSV retains all typed source values',same(csv_rows(directory/f'{stem}-terminal.csv'),terminal['rows']))
            else:
                attempt=p['task_attempts'][adm['score_binding']['attempt_index']-1]
                check(name+'/'+key+' canonical/source attempts stay distinct and joined',attempt['id']==score['attempt_id']==adm['plot_model']['id'] and
                      attempt['attempt_id']==attempt['source_attempt_id']==adm['plot_model']['identity']['attempt_id'] and attempt['id']!=attempt['attempt_id'])
                check(name+'/'+key+' saved metric score equals original full administration score',same(attempt['score'],score) and same(adm['plot_model']['saved_score'],score))
                for collection,suffix in [('responses','responses'),('trial_audit','audit')]:
                    check(name+'/'+key+' full '+collection+' CSV retains every row',same(csv_rows(directory/f'{stem}-{suffix}.csv'),attempt[collection]))
        if e['source_family']=='saved_task_cohort':
            check(name+'/'+key+' all saved cohort metric models retained',len(e['cohort_models'])==len(a['summaries']))
            for mi,m in enumerate(e['cohort_models'],1):
                expected=[dict(position=i+1,**r) for i,r in enumerate([r for r in p['per_person'] if r['metric']==m['metric']])]
                check(name+'/'+key+' exact saved metric model '+m['metric'],same(m['plot_model']['rows'],expected) and same(m['plot_model']['summary'],a['summaries'][mi-1]))
            check(name+'/'+key+' explicit complete membership bridge',len(task['identity_relationships'])==len(a['membership']))
    for selection_path in directory.glob('data/tasks/*-selection.json'):
        s=read(selection_path);finite=[]
        for r in s['selected_rows']:
            v=r.get(s['measure']) if s['measure'] else r.get('value')
            if v is not None:finite.append(v)
        check(name+'/'+selection_path.name+' exact finite/withheld/unavailable conservation',len(finite)==s['available'] and s['available']+s['observed_withholding']+s['unavailable']==len(s['selected_rows']))
        bins=s['distribution_bins']
        if bins:
            counts=[0]*len(bins)
            for v in finite:
                hits=[i for i,b in enumerate(bins) if (v>=b['lower_ms'] if b['lower_inclusive'] else v>b['lower_ms']) and v<=b['upper_ms']]
                assert len(hits)==1,(name,v,hits);counts[hits[0]]+=1
            check(name+'/'+selection_path.name+' independent full raw-value bin counts',counts==[b['count'] for b in bins])
    if name=='joined-cohort':
        task=read(directory/'evidence/tasks/report-03.json');sources={json.dumps(r['ref'],sort_keys=True):i+1 for i,r in enumerate(bundle['reports'])}
        for edge in task['identity_relationships']:
            index=sources[json.dumps(edge['source_report_ref'],sort_keys=True)];a=read(directory/f'evidence/report-{index:02}.json')['analysis']
            matches=[x for x in a['task_attempts'] if x['id']==edge['administration_id']]
            check('joined cohort exact source identity relationship',len(matches)==1 and matches[0]['participant_id']==edge['source_person_id'] and
                  matches[0]['session_id']==edge['source_session_id'] and matches[0]['source_attempt_id']==edge['source_attempt_id'])
    members={f['path']:f for f in manifest['files']};members['manifest.json']=dict(sha256=hashlib.sha256((directory/'manifest.json').read_bytes()).hexdigest(),bytes=(directory/'manifest.json').stat().st_size)
    with zipfile.ZipFile(directory/'report.brohn-report.zip') as z:
        check(name+' ZIP exact ordered complete inventory',z.namelist()==sorted(members))
        for member in z.infolist():
            data=z.read(member.filename);f=members[member.filename]
            assert len(data)==f['bytes'] and hashlib.sha256(data).hexdigest()==f['sha256'],member.filename
            assert data==(directory/member.filename).read_bytes(),member.filename
            assert member.date_time==(1980,1,1,0,0,0) and member.compress_type==zipfile.ZIP_STORED and not member.extra and not member.comment
    document=Document();document.feed((directory/'report.html').read_text(encoding='utf-8'))
    check(name+' offline document unique IDs/landmark names',len(document.ids)==len(set(document.ids)) and len(document.headings)==len(set(document.headings)))
    check(name+' keyboard scroll regions have complete unique section labels and resolved instructions',
          len(document.scrolls)>0 and len({d.get('aria-label') for d in document.scrolls})==len(document.scrolls) and
          all(d.get('role')=='region' and d.get('tabindex')=='0' and 'section ' in d.get('aria-label','') and
              d.get('aria-describedby') in document.ids for d in document.scrolls))
    check(name+' every selected task chart has one unshrunk scroll viewport',document.canvas==
          sum('brohn-task-chart-scroll' in d['class'].split() for d in document.scrolls) and document.canvas>0)
    check(name+' document contains no executable or external content','script' not in document.tags and all(not re.match(r'(https?:|//|file:)',x) for x in document.refs))
    for f in manifest['files']:
        if f['media_type']=='image/svg+xml':
            tree=ET.fromstring((directory/f['path']).read_bytes());ids=[e.attrib['id'] for e in tree.iter() if 'id' in e.attrib]
            assert len(ids)==len(set(ids))
            for e in tree.iter():
                for k in ('aria-labelledby','aria-describedby'):
                    if k in e.attrib:assert all(x in ids for x in e.attrib[k].split())
            metadata=tree.find('{http://www.w3.org/2000/svg}metadata')
            binding=loads(metadata.text) if metadata is not None else {}
            if 'selected_rows' in binding:
                rows=binding['selected_rows'];chart=binding['chart']
                marks=[e for e in tree.iter() if e.tag.rsplit('}',1)[-1] in ('circle','rect','path','line') and e.find('{http://www.w3.org/2000/svg}title') is not None]
                if chart=='distribution':
                    check(name+'/'+f['path']+' actual SVG has every exact histogram bin',len(marks)==len(binding['distribution_bins']))
                else:
                    check(name+'/'+f['path']+' actual SVG has every selected position including late rows',len(marks)==len(rows))
                    entry=[e for e in bundle['task_displays'] if same(e['ref'],binding['source'])][0]
                    models=entry['evidence']['administrations']+entry['evidence']['cohort_models']
                    model=[m['plot_model'] for m in models if m['key']==binding['model_key']][0]
                    vals=[r.get('value') if chart=='people' else r.get(binding['measure']) for r in rows]
                    finite=[float(v) for v in vals if v is not None];yr=[min([0]+finite),max([0]+finite)]
                    if chart=='people' and model['unit']=='proportion':yr=[0,1]
                    if yr[0]==yr[1]:yr=[-1,1] if chart=='people' and (model['unit']=='D' or model['metric']=='keyboard_aat_relative_approach_advantage') else [0,1]
                    for r,v,mark in zip(rows,vals,marks):
                        tag=mark.tag.rsplit('}',1)[-1]
                        if chart=='outcomes':
                            states=['hit','miss','false_alarm','correct_rejection','interrupted','not_presented','absent_source']
                            x=113+(r['position']-1)/max(1,len(model['rows'])-1)*(680-18-113)
                            y=55+states.index(r['outcome_state'])*(283-55)/6
                        else:
                            x=65+(r['position']-1)/(max(2,len(model['rows']))-1)*(680-18-65)
                            y=278 if v is None else 258-(float(v)-yr[0])/(yr[1]-yr[0])*(258-38)
                        if tag=='circle':actual=[float(mark.attrib['cx']),float(mark.attrib['cy'])]
                        elif tag=='rect':actual=[float(mark.attrib['x'])+2.5,float(mark.attrib['y'])+2.5]
                        elif tag=='line':actual=[(float(mark.attrib['x1'])+float(mark.attrib['x2']))/2,float(mark.attrib['y1'])]
                        else:
                            coords=mark.attrib['d'].split();actual=[float(coords[1]),float(coords[2])+3.5]
                        assert abs(actual[0]-x)<=.000501 and abs(actual[1]-y)<=.000501,(f['path'],r['position'],actual,[x,y])
                    check(name+'/'+f['path']+' independent actual SVG coordinates match full recorded values/order',True)
    check(name+' every archive hash/byte/metadata and SVG reference verified',True)
output.write_text(json.dumps(dict(passed=True,checks=checks,unchanged_scientific_scalars=values,registered_alias_fields=aliases,
    bundle_count=len(bundles),all_bundle_count=all_bundle_count,explicit_excluded_bundles=sorted(excluded_names),scope='Independent complete projection and artifact check; no scorer, application import, source worker, browser, authority or timing claim.'),indent=2),encoding='utf-8')
print(json.dumps(dict(passed=True,checks=len(checks),scientific_scalars=values,alias_fields=aliases,receipt_sha256=hashlib.sha256(output.read_bytes()).hexdigest())))
