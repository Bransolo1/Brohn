"""Post-close original data inspection only; never queues or recalculates analysis."""
from pathlib import Path
import json,hashlib,sqlite3,sys,traceback
from decimal import Decimal
from catalogue_snapshot import copy_catalogue
decode=lambda text:json.loads(text,parse_float=Decimal)
cfg=json.loads(Path(sys.argv[1]).read_text(encoding='utf-8-sig'))
out=Path(sys.argv[2]);out.mkdir(exist_ok=False)
workspace=Path(cfg['workspace']).resolve();installation=Path(cfg['installation']).resolve()
browser=json.loads(Path(cfg['browser_result']).read_text(encoding='utf-8-sig'))
read=lambda p:decode(Path(p).read_text(encoding='utf-8-sig'))
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
digest=lambda raw:hashlib.sha256(raw).hexdigest()
result=dict(passed=False,checks=[],scope='Closed normal-launcher workspace, original browser collection and automatic worker report. No recalculation or scientific/device qualification.')
connection=None;before=None;copied_catalogue=None
def check(name,ok):
 if not ok:raise AssertionError(name)
 result['checks'].append(name)
def snapshot():
 return [dict(path=p.relative_to(workspace).as_posix(),bytes=p.stat().st_size,sha256=sha(p)) for p in sorted(workspace.rglob('*')) if p.is_file()]
def rows(sql,args=()):return [dict(r) for r in connection.execute(sql,args)]
def one(sql,args=()):
 found=rows(sql,args);assert len(found)==1,(sql,len(found));return found[0]
try:
 check('actual browser journey passed before read-only inspection',browser['passed'])
 before=snapshot()
 db,copied_catalogue=copy_catalogue(workspace,out/'catalogue-snapshot',before)
 check('closed original catalogue and every present WAL/SHM sidecar copied exactly',
       bool(copied_catalogue) and before==snapshot())
 connection=sqlite3.connect(db.as_uri()+'?mode=ro',uri=True);connection.row_factory=sqlite3.Row
 connection.execute('PRAGMA query_only=ON')
 check('only the copied WAL-aware catalogue is opened read-only',
       connection.execute('PRAGMA query_only').fetchone()[0]==1 and db.is_relative_to(out.resolve()))
 result['catalogue_snapshot_before_read']=copied_catalogue
 study_id=browser['study_id'];report_id=browser['report_id']
 study=one("SELECT * FROM entities WHERE kind='study' AND id=?",(study_id,))
 release=one('SELECT * FROM delivery_deployments WHERE study_id=?',(study_id,))
 run=one('SELECT * FROM delivery_runs WHERE deployment_id=?',(release['id'],))
 runtime=decode(one('SELECT * FROM delivery_runtimes WHERE deployment_id=?',(release['id'],))['manifest_json'])
 index=next(row for row in runtime['files'] if row['path']=='participant/index.html')
 actual_document=next(row for row in browser['responses'] if row['status']==200 and row['path'].endswith('/participant/index.html'))
 check('genuine navigation served the exact original stored runtime document',actual_document['body_bytes']==index['size'] and actual_document['body_sha256']==index['hash'])
 version=one("SELECT * FROM entity_versions WHERE kind='study' AND id=? AND revision=?",(study_id,release['design_revision']))
 design=decode(release['design_json']);protocol=decode(run['protocol_json'])
 history=rows("SELECT body_json,body_hash,revision FROM entity_versions WHERE kind='study' AND id=? ORDER BY revision",(study_id,))
 check('explicit UI equipment change preserves the earlier policy and final camera-free source',
       design.get('participant_equipment') is None and design.get('camera') is None and
       any(row['revision']<release['design_revision'] and decode(row['body_json']).get('participant_equipment') is not None for row in history) and
       all(digest(row['body_json'].encode('utf-8'))==row['body_hash'] for row in history))
 check('original retained protocol bytes match their stored hash',digest(run['protocol_json'].encode('utf-8'))==run['protocol_hash'])
 check('real UI source is the exact selected immutable release revision',release['design_json'].encode('utf-8')==version['body_json'].encode('utf-8') and
       digest(version['body_json'].encode('utf-8'))==version['body_hash'] and design['schema_version']=='brohn-design/1.2.0')
 check('original protocol preserves the declared instructions and entire saved design',protocol['schema_version']=='brohn-protocol/1.2.0' and
       protocol['design']==design and protocol['design_hash']==release['design_hash'] and
       protocol['design']['instructions']=='Look at the control and packaging version naturally, then answer the question.')
 stimuli={s['title']:s for s in design['stimuli']};assignment=protocol['stimulus_assignment'];selected=assignment['selected_stimulus_ids']
 check('shared control and one original version are actually assigned',len(stimuli)==3 and len(selected)==2 and
       stimuli['Shared control']['id'] in selected and sum(stimuli[t]['id'] in selected for t in ['Packaging original','Packaging variant'])==1)
 check('all six declared timed steps survive original compilation',[s['type'] for s in protocol['timeline'] if s['type'] in ['baseline','fixation','stimulus']]==
       ['baseline','fixation','stimulus','baseline','fixation','stimulus'])
 check('actual original run is complete and saved',run['completion_status']=='completed' and run['transfer_status']=='saved')
 jobs=rows('SELECT * FROM jobs');check('continuous worker processed only the real Finish-created analysis job',len(jobs)==1)
 job=jobs[0];request=decode(job['request_json']);job_result=decode(job['result_json'])
 check('job request bytes retain their original hash',digest(job['request_json'].encode('utf-8'))==job['request_hash'])
 check('named original run job succeeded once',request==dict(run_id=run['id'],analysis_profile='saved-variant-run-analysis/0.1') and
       job['idempotency_key']=='variant-analysis:0.1:run:'+run['id'] and job['status']=='succeeded' and job['attempt']==1 and job_result['report_id']==report_id)
 receipts=rows("SELECT * FROM delivery_receipts WHERE scope=? AND operation='finish'",(run['id'],))
 check('original Finish receipt is unique',len(receipts)==1)
 event_rows=rows('SELECT * FROM delivery_events WHERE run_id=? ORDER BY sequence',(run['id'],))
 events=[decode(r['event_json']) for r in event_rows]
 check('all source event bytes and final sequence remain intact',len(events)==run['acked_sequence'] and all(
       r['sequence']==i+1 and r['event_hash']==digest(r['event_json'].encode('utf-8')) for i,r in enumerate(event_rows)))
 check('single original completed terminal is last',events[-1]['type']=='run_finished' and events[-1]['payload']['outcome']=='completed' and
       sum(e['type']=='run_finished' for e in events)==1)
 network=[r for r in browser['requests'] if r['path'].startswith('/api/view/events/')]
 operations=rows('SELECT * FROM delivery_view_operations WHERE run_id=? ORDER BY first_sequence',(run['id'],))
 check('original native event request bytes equal all retained operation bytes',len(network)==len(operations) and
       [r['body'].encode('utf-8') for r in network]==[r['request_blob'] for r in operations])
 report_row=one("SELECT v.* FROM entities e JOIN entity_versions v ON "
                "v.kind=e.kind AND v.id=e.id AND v.revision=e.revision AND v.project_id=e.project_id "
                "WHERE e.kind='report' AND e.id=?",(report_id,));report=decode(report_row['body_json'])
 check('saved report bytes match their original entity hash',digest(report_row['body_json'].encode('utf-8'))==report_row['body_hash'])
 exported=read(browser['downloads'][0])
 check('ordinary report download is the whole saved report',exported==report and report['study_id']==study_id and report['processing']['job_id']==job['id'])
 object_path=workspace/'objects/sha256'/job_result['output_hash'][:2]/job_result['output_hash'];raw=object_path.read_bytes();published=decode(raw)
 body=dict(report);body.pop('result_object')
 check('original native sealed output matches report and job receipt',digest(raw)==job_result['output_hash']==report['result_object']['hash'] and
       len(raw)==report['result_object']['size'] and published['report']==body and report['processing']['publication']['native_seal'] is True)
 identity=report['processing']['code_hashes']
 check('worker59 identity remains the exact original installed bytes',published['code_identity']==identity and len(identity)==59 and all(
       (installation/name).resolve().is_relative_to(installation) and sha(installation/name)==value for name,value in identity.items()))
 source=report['provenance']['variant_source']['runs'][0]
 check('report provenance binds original protocol release and saved study bytes',source['run_id']==run['id'] and source['assignment']==assignment and
       source['protocol']['sha256']==digest(run['protocol_json'].encode('utf-8')) and
       source['release']['sha256']==digest(release['design_json'].encode('utf-8')) and
       source['study']['sha256']==version['body_hash'])
 observations=report['analysis']['observations'];commits=[e for e in events if e['type']=='questionnaire_event' and e['payload']['kind']=='commit']
 check('original end rating is represented once with its real evidence',len(observations)==len(commits)==1 and
       observations[0]['value']==commits[0]['payload']['value']==7 and observations[0]['event_id']==commits[0]['id'] and
       observations[0]['response_time_ms']==commits[0]['payload']['response_time_ms'])
 result.update(study_id=study_id,release_id=release['id'],run_id=run['id'],job_id=job['id'],report_id=report_id,output_hash=job_result['output_hash'])
 result['passed']=True
except Exception as error:
 result['failure']=dict(message=str(error),traceback=traceback.format_exc())
finally:
 if connection:connection.close()
 if copied_catalogue is not None:
  result['catalogue_snapshot_after_read']=[dict(path=p.name,bytes=p.stat().st_size,sha256=sha(p))
       for p in sorted((out/'catalogue-snapshot').iterdir()) if p.is_file()]
 result['store_closed']=True
 if before is not None:
  result['original_workspace_files_unchanged']=before==snapshot()
  if not result['original_workspace_files_unchanged']:result['passed']=False
 (out/'RESULTS.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
sys.exit(0 if result['passed'] else 1)
