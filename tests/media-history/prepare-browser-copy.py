"""Prepare a fresh isolated copy only when the coordinated runtime window opens.

Does not start a service/worker. Caller must select a new external destination.
The accepted synthetic source is read through SQLite's backup API and every
retained object is copied and independently SHA checked.
"""
import hashlib
import json
from pathlib import Path
import shutil
import sqlite3
import sys

if len(sys.argv)!=5:
    raise SystemExit('Usage: prepare-browser-copy.py TARGET BASELINE_WORKSPACE BASELINE_RECEIPT RUNTIME_MANIFEST')
target=Path(sys.argv[1]).resolve()
source=Path(sys.argv[2]).resolve()
baseline_path=Path(sys.argv[3]).resolve()
runtime_path=Path(sys.argv[4]).resolve()
baseline=json.loads(baseline_path.read_text(encoding='utf-8-sig'))
runtime=json.loads(runtime_path.read_text(encoding='utf-8-sig'))
if baseline.get('passed') is not True or not all(type(baseline.get(k)) is dict and all(type(baseline[k].get(n)) is str for n in ('parent','report','audio','media')) for k in ('regular','gap')):
    raise ValueError('Supply a successful original regular/gap media researcher receipt with exact saved references.')
for key in ('app_root','rscript','r_libs','publication_python','publication_manifest'):
    if type(runtime.get(key)) is not str or not Path(runtime[key]).is_absolute() or not Path(runtime[key]).exists():
        raise ValueError('Every application/runtime path must be explicitly supplied, absolute and existing: '+key)
for key in ('researcher_port','participant_port'):
    if type(runtime.get(key)) is not int or not 1024<=runtime[key]<=65535:
        raise ValueError('Supply an explicit available test port: '+key)
if runtime['researcher_port']==runtime['participant_port'] or runtime.get('chrome_channel') not in ('chrome','msedge'):
    raise ValueError('Supply distinct test ports and an installed browser channel.')
if not target.name.startswith('brohn-media-history-browser-') or target.exists() or source in target.parents or target==source:
    raise ValueError('Choose a new isolated brohn-media-history-browser-* directory outside the accepted source.')
target.mkdir(parents=True);workspace=target/'workspace';workspace.mkdir()
digest=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
before=digest(source/'catalog.sqlite')
src=sqlite3.connect((source/'catalog.sqlite').as_uri()+'?mode=ro',uri=True)
try:
    dst=sqlite3.connect(workspace/'catalog.sqlite')
    try:src.backup(dst)
    finally:dst.close()
    records=src.execute('SELECT kind,id,revision,body_hash FROM entity_versions ORDER BY kind,id,revision').fetchall()
    objects=src.execute('SELECT hash,size FROM objects ORDER BY hash').fetchall()
finally:src.close()
copied=[]
for expected,size in objects:
    relative=Path('objects/sha256')/expected[:2]/expected
    old,new=source/relative,workspace/relative
    if old.stat().st_size!=size or digest(old)!=expected:raise ValueError('Accepted source object failed its exact bytes/hash check')
    new.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(old,new)
    if new.stat().st_size!=size or digest(new)!=expected:raise ValueError('Isolated object copy failed its exact bytes/hash check')
    copied.append({'sha256':expected,'bytes':size})
if digest(source/'catalog.sqlite')!=before:raise ValueError('Accepted source catalog changed while copying')
manifest={'scope':'Copied accepted synthetic workspace; no new analysis or media jobs yet.',
          'source_workspace':str(source),'source_catalog_sha256':before,'workspace':str(workspace),
          'baseline_receipt':{'path':str(baseline_path),'sha256':digest(baseline_path),'regular':baseline['regular'],'gap':baseline['gap']},
          'runtime_manifest':{'path':str(runtime_path),'sha256':digest(runtime_path)},
          'original_entity_versions':records,'objects':copied,'new_jobs':0}
(target/'copy-receipt.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
(target/'runtime.json').write_text(json.dumps(runtime,indent=2),encoding='utf-8')
print(target)
