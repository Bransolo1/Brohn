import json,pathlib,shutil,hashlib,sqlite3,sys
mode=sys.argv[1];target=pathlib.Path(sys.argv[2]).resolve()
assert target.name.startswith('brohn-media-history-browser-')
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def records(con):return {name:con.execute('SELECT * FROM '+name+' ORDER BY '+order).fetchall() for name,order in [('entities','kind,id'),('entity_versions','kind,id,revision'),('jobs','id')]}
if mode=='copy':
 source=pathlib.Path(sys.argv[3]).resolve();runtime_file=pathlib.Path(sys.argv[4]).resolve();assert not target.exists() and source!=target and source not in target.parents
 runtime=json.loads(runtime_file.read_text(encoding='utf-8-sig'));assert runtime['researcher_port']!=runtime['participant_port']
 for key in ('app_root','rscript','r_libs','publication_python','publication_manifest'):assert pathlib.Path(runtime[key]).exists()
 fixture=json.loads((source/'fixture.json').read_text(encoding='utf-8'));receipt=json.loads((source/'copy-receipt.json').read_text(encoding='utf-8'));assert receipt.get('baseline_receipt')
 target.mkdir();shutil.copytree(source/'workspace',target/'workspace',ignore=shutil.ignore_patterns('catalog.sqlite','catalog.sqlite-wal','catalog.sqlite-shm'))
 with sqlite3.connect((source/'workspace/catalog.sqlite').as_uri()+'?mode=ro',uri=True) as src,sqlite3.connect(target/'workspace/catalog.sqlite') as dst:
  src.backup(dst);assert records(src)==records(dst)
 files=[p for p in (source/'workspace/objects/sha256').rglob('*') if p.is_file()]
 for p in files:assert sha(p)==sha(target/'workspace'/p.relative_to(source/'workspace'))
 fixture.update(workspace=(target/'workspace').as_posix(),researcher_port=runtime['researcher_port'],participant_port=runtime['participant_port'])
 receipt['workspace']=(target/'workspace').as_posix()
 for name,value in [('fixture.json',fixture),('copy-receipt.json',receipt),('runtime.json',runtime)]: (target/name).write_text(json.dumps(value,indent=2),encoding='utf-8')
 shutil.copyfile(source/'population-results.json',target/'population-results.json')
 result={'source':str(source),'target':str(target),'source_objects_verified':len(files),'new_jobs':0,'runtime_manifest':str(runtime_file),'runtime_manifest_sha256':sha(runtime_file)}
 (target/'feedback-copy-receipt.json').write_text(json.dumps(result,indent=2),encoding='utf-8');print(json.dumps(result))
else:
 source=pathlib.Path(json.loads((target/'feedback-copy-receipt.json').read_text())['source']);fixture=json.loads((target/'fixture.json').read_text());r=fixture['original']['regular']['media']
 with sqlite3.connect(target/'workspace/catalog.sqlite') as con:
  if mode in ('revoke','restore'):
   parent=r['body']['request']['dataset']['id'];project=r['project_id'];old,new=(project,'foreign-feedback-fixture') if mode=='revoke' else ('foreign-feedback-fixture',project)
   current=con.execute("SELECT project_id FROM entities WHERE kind='dataset' AND id=?",(parent,)).fetchone()[0];assert current in (old,new)
   con.execute("UPDATE entities SET project_id=? WHERE kind='dataset' AND id=?",(new,parent));con.commit();print(json.dumps({'mode':mode,'project_id':new}))
  elif mode in ('before','after'):
   current=json.loads(json.dumps(records(con)))
   if mode=='before':(target/'browser-original-catalog.json').write_text(json.dumps(current),encoding='utf-8')
   else:
    assert current==json.loads((target/'browser-original-catalog.json').read_text())
    for p in (source/'workspace/objects/sha256').rglob('*'):
     if p.is_file():assert sha(p)==sha(target/'workspace'/p.relative_to(source/'workspace'))
    print(json.dumps({'passed':True,'all_current_and_immutable_records_unchanged':True,'original_job_count':len(current['jobs']),'original_objects_unchanged':True,'new_jobs':0}))
  else:raise ValueError('Unsupported fixture mode')
