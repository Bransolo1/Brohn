"""Real spool handle/exception checks over the public generated continuous source."""
import argparse,hashlib,json,pathlib,sys,tempfile
from unittest.mock import patch
p=argparse.ArgumentParser();p.add_argument('repo',type=pathlib.Path);p.add_argument('originals',type=pathlib.Path);p.add_argument('out',type=pathlib.Path);a=p.parse_args()
repo=a.repo.resolve();originals=a.originals.resolve();out=a.out.resolve();out.mkdir(parents=True,exist_ok=False)
sys.path.insert(0,str(repo/'scripts/workers'))
import eda_display as e
original=e.strict_json((originals/'continuous-report.json').read_bytes());analysis=original['body']['analysis']
streams=[{'original':d,'original_verification':next(r for r in analysis['artifact_verification']['artifacts'] if r['kind']==d['kind']),'path':str(originals/'continuous'/(d['kind']+'.ndjson'))} for d in analysis['artifacts']]
source={'report_ref':{'id':original['id']},'source_hash':analysis['source']['sha256']}
checks=[];handles=[];real_open=pathlib.Path.open
def watch(path,mode='r',*args,**kwargs):
    f=real_open(path,mode,*args,**kwargs)
    if path.name.startswith('t') and path.suffix=='.jsonl' and mode in ('xb','ab'):handles.append((str(path),mode,f))
    return f
with tempfile.TemporaryDirectory(dir=out) as spool:
    with patch.object(pathlib.Path,'open',watch):idx=e.VerifiedIndex(streams,'continuous',source,spool)
    assert len(handles)==idx.table_count and all(m=='xb' and f.closed for _,m,f in handles)
    assert len({p for p,_,_ in handles})==idx.table_count
    checks.append('Exactly one exclusive writer per original table, all closed before any model read')
    assert all(pathlib.Path(p).read_bytes() for p,_,_ in handles)
    checks.append('All complete indexed table bytes immediately readable after flush/close')
checks.append('Normal private index cleanup succeeds on actual filesystem')
class Injected(Exception):pass
verify=e.tables.verify_artifact;handles.clear()
def fail(manifest,on_table=None,on_rows=None):
    def opened(spec):on_table(spec);raise Injected('explicit failure after writer creation')
    return verify(manifest,on_table=opened,on_rows=on_rows)
with tempfile.TemporaryDirectory(dir=out) as spool:
    with patch.object(pathlib.Path,'open',watch),patch.object(e.tables,'verify_artifact',fail):
        try:e.VerifiedIndex(streams,'continuous',source,spool)
        except Injected:pass
        else:raise AssertionError('No injected verifier failure')
    assert handles and all(f.closed for _,_,f in handles)
    checks.append('Verifier failure closes every created writer without masking original exception')
checks.append('Failure private index cleanup succeeds on actual filesystem')
r={'passed':True,'checks':checks,'count':len(checks),'source_sha256':hashlib.sha256(pathlib.Path(e.__file__).read_bytes()).hexdigest(),'scope':'Original typed source verifier and actual file lifetimes with explicit callback fault; no native supervisor or capacity proof'}
(out/'results.json').write_text(json.dumps(r,indent=2)+'\n',encoding='utf-8');print(json.dumps({'passed':True,'checks':len(checks)}))
