"""Independent saved gaze/projection/CSV conservation. Standard library only."""
from pathlib import Path
import argparse,csv,hashlib,io,json,struct

def unique(rows):
    d={}
    for k,v in rows:
        assert k not in d
        d[k]=v
    return d
def load(raw):
    return json.loads(raw,object_pairs_hook=unique,parse_int=lambda s:-0.0 if s=='-0' else int(s))
def typed(v):
    if v is None:return ('null',)
    if isinstance(v,bool):return ('bool',v)
    if isinstance(v,(int,float)):return ('number',struct.pack('>d',float(v)))
    if isinstance(v,str):return ('str',v)
    if isinstance(v,list):return ('array',tuple(map(typed,v)))
    return ('object',tuple((k,typed(v[k])) for k in sorted(v)))

parser=argparse.ArgumentParser();parser.add_argument('source_body');parser.add_argument('projection');parser.add_argument('features_csv');parser.add_argument('generation');parser.add_argument('out');args=parser.parse_args()
source,projection,csvpath,generation=[Path(x).resolve() for x in (args.source_body,args.projection,args.features_csv,args.generation)]
out=Path(args.out).resolve();assert not out.exists()
inputs={str(x):hashlib.sha256(x.read_bytes()).hexdigest() for x in (source,projection,csvpath,generation)}
a=load(source.read_bytes());b=load(projection.read_bytes());g=load(generation.read_bytes());rows=list(csv.DictReader(io.StringIO(csvpath.read_text(encoding='utf8'))))
checks=[]
def check(n,v):assert v,n;checks.append(n)
check('complete actual saved native gaze analysis is typed exact',typed(a['analysis'])==typed(b['analysis']))
check('every genuine feature CSV record_json is typed exact',len(rows)==len(a['analysis']['features']) and all(typed(load(x['record_json']))==typed(y) for x,y in zip(rows,a['analysis']['features'])))
check('exact declared threshold provenance retained',b['analysis']['parameters']['thresholds']['threshold_source']==a['provenance']['mapping']['parameters']['threshold_source'])
check('genuine classes and degree path retain zero and positive values',any(x.get('angular_path_deg')==0 for x in b['analysis']['features']) and any(x.get('angular_path_deg',0)>0 for x in b['analysis']['features']) and all(x.get('qualified') is False for x in b['analysis']['features'] if 'classification' in x))
check('registration is portable provenance only','projection_registration' in b['provenance'] and 'projection_registration' not in a['analysis'] and 'projection_registration' not in b['analysis'])
check('unqualified source meaning remains explicit',b['analysis']['quality']['qualified'] is False and b['analysis']['limitations']==a['analysis']['limitations'])
check('projection source reference equals exact frozen native original',b['source_ref']==g['reports']['gaze'])
check('read inputs remain byte unchanged',all(hashlib.sha256(Path(p).read_bytes()).hexdigest()==h for p,h in inputs.items()))
receipt={'passed':True,'checks':checks,'count':len(checks),'features':len(rows),'source_method':a['analysis']['parameters']['method'],'source_code_hash':a['processing']['code_hashes']['R/platform-gaze.R'],'inputs':inputs,'scope':'Independent standard-library exact native source/projection/CSV/ref conservation. No jobs, source mutation or scientific calculation.'}
out.write_text(json.dumps(receipt,indent=2)+'\n',encoding='utf8');print(json.dumps({'passed':True,'count':len(checks),'sha256':hashlib.sha256(out.read_bytes()).hexdigest()}))
