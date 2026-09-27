"""Independent stdlib reader for the synthetic R package test outputs."""
import csv,hashlib,io,json,re,stat,sys,zipfile
from pathlib import Path
from html.parser import HTMLParser
root=Path(sys.argv[1]).resolve()
checks=[]
def check(name,condition):
    if not condition:raise AssertionError(name)
    checks.append(name)
def read(path):return json.loads(path.read_text(encoding='utf-8'))
bundle=read(root/'fixture-bundle.json');manifest=read(root/'first/manifest.json')
package=root/'first'
aliases={'participant_id','proposed_participant_id','session_id','run_id','proposed_session_id',
 'source_participant_id','source_session_id','source_exposure_id','source_recording_id','source_segment_id',
 'exposure_id','assessment_exposure_id','assessment_id','event_id','first_answer_event_id','last_answer_event_id',
 'visit_id','step_id','occurrence_id','instance_id','from_step_id','to_step_id','invalidated_by_event_id','invalidated_event_id','trigger_event_id'}
free={'value','previous_value','invalidated_value','item_values','value_before_conversion'}
def equal(a,b):
    # R JSON encodes integral doubles as integers; scientific numeric equality
    # is exact, while Boolean/number and every string remain distinct types.
    if isinstance(a,(int,float)) and not isinstance(a,bool) and isinstance(b,(int,float)) and not isinstance(b,bool):return a==b
    return type(a) is type(b) and (a==b)
def compare(a,b,path='analysis'):
    if isinstance(a,dict):
        check('all original keys '+path,set(a)==set(b))
        for k,v in a.items():
            if k in free:check('typed response '+path+'/'+k,equal(v,b[k]));continue
            if k in aliases or (k=='id' and '/history_events/' in path+'/'):
                check('identity presence '+path+'/'+k,(v is None and b[k] is None) or (isinstance(v,str) and isinstance(b[k],str) and 'PRIVATE-' not in b[k]));continue
            compare(v,b[k],path+'/'+k)
    elif isinstance(a,list):
        check('full ordered collection '+path,len(a)==len(b))
        for i,(x,y) in enumerate(zip(a,b)):compare(x,y,path+'/'+str(i))
    else:check('saved value '+path,equal(a,b))
for i,item in enumerate(bundle['reports'],1):
    projection=read(package/f'evidence/report-{i:02d}.json')
    compare(item['complete_analysis'],projection['analysis'])
    check(f'source reference report{i}',projection['source_ref']==item['ref'])
    for collection in ('observations','features'):
        family='gaze' if i==1 else 'explicit'
        with (package/f'data/{family}/report-{i:02d}-{collection}.csv').open(encoding='utf-8',newline='') as f:rows=list(csv.DictReader(f))
        check(f'complete CSV {i} {collection}',len(rows)==len(projection['analysis'][collection]))
        for index,(row,original) in enumerate(zip(rows,projection['analysis'][collection]),1):
            check(f'CSV exact typed record {i} {collection} {index}',json.loads(row['record_json'])==original and int(row['source_order'])==index)
    check(f'counts {i}',projection['counts']['features']==len(item['complete_analysis']['features']) and projection['counts']['observations']==len(item['complete_analysis']['observations']))
gaze=read(package/'evidence/report-01.json')['analysis']
check('all 227 fixation candidates plus 14 summary rows',len(gaze['features'])==241)
check('late omitted display candidate retained',gaze['features'][200]['start_ms']==200 and gaze['features'][200]['end_ms']==201)
check('missing support denominator retained',all(x['valid_ms']==1000 and x['inside_ms']==250 and x['valid_share_percent']==25 and x['ttff_ms'] is None for x in gaze['observations']))
paired=read(package/'data/paired/section-003-comparison-001.json')
check('saved contrast estimate 8',paired['saved_contrast']['estimate']==8)
check('51 independent people and 68 paired visits',len(paired['people'])==51 and sum(x['paired'] for x in paired['sessions'])==68)
check('85 full visits and 272 full source rows',len(paired['sessions'])==85 and len(paired['observations'])==272)
check('equal person weighting independently reconstructs saved 8',sum(x['difference'] for x in paired['people'])/len(paired['people'])==8)
distribution=read(package/'evidence/distributions/section-002.json')
check('saved distribution is copied completely',distribution['result']==bundle['distributions'][0]['body']['result'])
check('category over page20 remains present',max(len(g['categories']) for g in distribution['result']['groups'])>20)
class Document(HTMLParser):
    def __init__(self):super().__init__();self.ids=[];self.refs=[];self.resources=[];self.scripts=[];self.svg=0;self.text=[]
    def handle_starttag(self,tag,attrs):
        a=dict(attrs)
        if 'id' in a:self.ids.append(a['id'])
        if tag in ('script','iframe','object','embed','foreignobject'):self.scripts.append(tag)
        if tag=='svg':self.svg+=1
        for k,v in attrs:
            if k.lower().startswith('on'):self.scripts.append(k)
            if k in ('aria-labelledby','aria-describedby'):self.refs+=v.split()
            if k in ('src','href','xlink:href'):
                if v.startswith('#'):self.refs.append(v[1:])
                elif not (tag=='a' and re.fullmatch('[a-z0-9._/-]+',v)):self.resources.append(v)
    def handle_data(self,data):self.text.append(data)
html=(package/'report.html').read_text(encoding='utf-8');doc=Document();doc.feed(html)
check('static escaped document with no active scripts',not doc.scripts)
check('all SVG and document IDs unique',len(doc.ids)==len(set(doc.ids)))
check('all accessibility and local links resolve',set(doc.refs)<=set(doc.ids))
check('no external resources',not doc.resources)
check('no private identifiers or server paths in HTML','PRIVATE-' not in html and 'C:/private' not in html and 'archive_python' not in html)
check('Unicode title and malicious-looking text escaped','\u65e5\u672c\u8a9e' in html and '&lt;script&gt;' in html)
check('complete chosen SVG panel inventory',doc.svg==sum(s['selected_figures'] for s in manifest['coverage']))
entries=manifest['files']
with zipfile.ZipFile(package/'report.brohn-report.zip') as archive:
    check('ZIP includes every payload and manifest once in ASCII order',archive.namelist()==sorted([f['path'] for f in entries]+['manifest.json']))
    for info in archive.infolist():
        check('fixed ZIP metadata '+info.filename,info.date_time==(1980,1,1,0,0,0) and info.compress_type==zipfile.ZIP_STORED and not info.extra and not info.comment and info.flag_bits==0 and info.external_attr==(stat.S_IFREG|0o644)<<16)
        data=archive.read(info)
        check('ZIP exact member bytes '+info.filename,data==(package/info.filename).read_bytes())
        if info.filename!='manifest.json':
            f=next(f for f in entries if f['path']==info.filename)
            check('independent SHA bytes '+info.filename,len(data)==f['bytes'] and hashlib.sha256(data).hexdigest()==f['sha256'])
check('ZIP repeat bytes exact',(package/'report.brohn-report.zip').read_bytes()==(root/'second/report.brohn-report.zip').read_bytes())
output={'schema':'brohn-report-package-independent-reader/0.1','passed':True,'check_count':len(checks),'scope':'Synthetic full numerical projections/CSV/HTML/SVG/ZIP; no authority/device qualification','checks':checks}
(root/'independent-reader.json').write_text(json.dumps(output,ensure_ascii=True,indent=2)+'\n',encoding='utf-8')
print(json.dumps({k:v for k,v in output.items() if k!='checks'}))
