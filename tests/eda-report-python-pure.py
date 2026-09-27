"""Portable exact transport and preflight tests. No store, detector or estimator."""
import argparse
import hashlib
import json
import math
from pathlib import Path
import struct
import sys
from types import SimpleNamespace

p=argparse.ArgumentParser()
p.add_argument('repo',type=Path);p.add_argument('output',type=Path)
p.add_argument('--r-vectors',type=Path,help='results.json from eda-display-primitives.R')
a=p.parse_args();repo=a.repo.resolve();out=a.output.resolve();out.mkdir(parents=True,exist_ok=False)
sys.path.insert(0,str(repo/'scripts/workers'))
import eda_display as e

checks=[]
def check(value,label):
    assert value,label
    checks.append(label)
def refused(fn,label):
    try:fn()
    except Exception:checks.append(label);return
    raise AssertionError(label)

prefix=b'brohn-eda-value-hash/0.1\n'
vectors=[(None,b'n'),(False,b'f'),(True,b't'),([],b'a0:'),({},b'o0:'),
         (-0.0,b'd'+struct.pack('>d',-0.0)),(0,b'd'+struct.pack('>d',0)),
         ('é',b's2:\xc3\xa9'),([None,True],b'a2:nt')]
for value,raw in vectors:
    check(e.value_hash(value)==hashlib.sha256(prefix+raw).hexdigest(),'independent byte grammar '+repr(value))
    check(e.value_hash(e.strict_json(e.json_bytes(value)))==e.value_hash(value),'exact Python roundtrip '+repr(value))
check(math.copysign(1,e.strict_json('-0'))==-1,'lexical negative-zero number preserves sign')
check(e.strict_json('"-0"')=='-0','negative-zero-looking string remains literal')
for raw in ['9007199254740992','-9007199254740992','1e309','NaN','{"x":1,"x":2}']:
    refused(lambda:e.strict_json(raw),'refused malformed transport '+raw)
if a.r_vectors:
    for name,vector in json.loads(a.r_vectors.read_text(encoding='utf-8'))['vectors'].items():
        check(e.value_hash(e.strict_json(vector['json']))==vector['sha256'],'actual R-to-Python exact transport '+name)
for raw,expected in [('+001.2000e+002','12e1'),('-0e-1000','0'),('.00100','1e-3'),('-0002.30E-002','-23e-3')]:
    check(e.normalized_decimal(raw)==expected,'decimal canonical '+raw)

record=dict(recording_id='r',segment_id='s',channel='eda')
request=dict(report=dict(ref={'id':'synthetic'},complete_analysis=dict(parameters={'r':{}})))
def synthetic(kind,count,alternating=False):
    path=out/(kind+'-'+str(count)+'.jsonl')
    columns=['time_s','retained'] if kind=='physiology-series' else ['time_s','onset_time_s','recovery_time_s']
    with path.open('wb') as f:
        for start in range(0,count,1000):
            rows=[[1, bool(i%2) if alternating else True] if kind=='physiology-series' else [1,None,None] for i in range(start,min(start+1000,count))]
            f.write(e.json_bytes({'rows':rows})+b'\n')
    return SimpleNamespace(entries={kind:{'tables':[{'spec':{'identity':record,'columns':[{'name':c} for c in columns]},'path':path}]}})
selection={'start_s':'0','end_s':'2'}
check(e.selected_window_counts(synthetic('physiology-events',5000),'continuous',request,record,selection)['candidates']==5000,'5000 selected candidate boundary accepted')
for kind,count,resource,maximum,alternating in [('physiology-events',5007,'window_candidates',5000,False),('physiology-series',500007,'window_samples',500000,False),('physiology-series',201,'component_groups',200,True)]:
    try:e.selected_window_counts(synthetic(kind,count,alternating),'continuous',request,record,selection)
    except e.Refusal as error:
        d=error.detail
        check(d['schema']=='brohn-eda-report-refusal/0.1' and d['resource']==resource and d['measured']==count and d['maximum']==maximum and d['recovery_scope']=='smaller_window','actual complete selected count in structured '+resource+' refusal')
    else:raise AssertionError('No refusal: '+resource)

result={'passed':True,'checks':checks,'count':len(checks),'source_sha256':hashlib.sha256(Path(e.__file__).read_bytes()).hexdigest(),
        'scope':'Independent scalar byte grammar and actual optional R transport; synthetic complete-count preflight boundaries, not source parsing, native execution, scientific validity or capacity qualification'}
(out/'results.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
print(json.dumps({'passed':True,'checks':len(checks)}))
