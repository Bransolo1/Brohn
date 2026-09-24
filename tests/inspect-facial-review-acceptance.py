"""Join retained browser phases without relabelling a failed export as a fullpass."""
import argparse,hashlib,json,collections
from pathlib import Path
parser=argparse.ArgumentParser();parser.add_argument('fixture');parser.add_argument('full');parser.add_argument('navigation');parser.add_argument('export');args=parser.parse_args()
folder=Path(args.fixture).resolve();dirs=[Path(getattr(args,k)).resolve() for k in ('full','navigation','export')];assert all(p.parent==folder for p in dirs)
def read(p):return json.loads(p.read_text(encoding='utf-8'))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
paths=[dirs[0]/'results.json',dirs[1]/'failure.json',dirs[2]/'results.json'];full,nav,export=map(read,paths)
assert full['status']=='passed' and len(full['checks'])==21 and len(full['scans'])==6
assert len(nav['checks'])==7 and len(nav['scans'])==2 and 'Received: 3' in nav['error']
assert export['status']=='passed' and len(export['checks'])==5 and len(export['scans'])==4 and export['newJobs']==[]
assert export['parentNavigationFailureSha256']==sha(paths[1])
for evidence in (full,nav,export):
 assert evidence['errors']==[]
 for scan in evidence['scans']:
  assert scan['violations']==0 and not scan.get('overflow',False)
  if 'glyph' in scan:assert scan['glyph']>=11.5
for file,expected in export['sourceHashes'].items():assert sha(Path(file))==expected,file
assert [k for k in full['sourceHashes'] if full['sourceHashes'][k]!=nav['sourceHashes'][k]]==['R/platform-facial-review-views.R']
assert [k for k in nav['sourceHashes'] if nav['sourceHashes'][k]!=export['sourceHashes'][k]]==['R/platform-facial-review-views.R']
cfg=read(folder/'fixture.json');inspection=read(folder/'inspection.json');assert inspection['report_hash']==cfg['report_hash']
for original in cfg['source_objects']:
 assert sha(Path(original['path']))==original['hash'] and sha(Path(original['original_path']))==original['hash']
new=[j for j in inspection['jobs'] if j['id'] not in cfg['baseline_jobs']]
counts=dict(collections.Counter(j['operation']+':'+j['status'] for j in new))
assert counts=={'facial_frame:succeeded':6,'facial_frame:cancelled':1,'facial_review:succeeded':1,'facial_review:cancelled':1}
frames=inspection['frames'];assert sorted(int(f['body']['frame']['frame']['frame_index']) for f in frames)==list(range(6))
for frame in frames:
 b=frame['body'];index=int(b['frame']['frame']['frame_index']);assert b['frame']['extraction']['rgb24_sha256']==cfg['analysis']['preview'][index]['decoded_rgb_sha256']
 for file,expected in b['processing']['code_hashes'].items():assert sha(Path(file))==expected,file
for index,p in [(1,dirs[0]/'frame1.png'),(5,dirs[1]/'frame5.png')]:
 assert sha(p)==next(f['body']['frame']['image']['hash'] for f in frames if int(f['body']['frame']['frame']['frame_index'])==index)
receipt={'schema':'brohn-facial-review-joined-acceptance/1.0','status':'passed_with_explicit_joined_phases','phases':[{'path':str(p),'sha256':sha(p),'successful_groups':len(x['checks']),'clean_scans':len(x['scans'])} for p,x in zip(paths,[full,nav,export])],
 'current_source_hashes':export['sourceHashes'],'source_transition':'Only facial review views changed: bounded debounced navigation, then corrected standalonehead serialization. Original failed export is retained. No unbroken-source/fullrun claim.',
 'browser_groups':33,'clean_scans':12,'inherited_original_jobs':cfg['baseline_jobs'],'new_derived_jobs':new,'new_job_counts':counts,'inference_rerun':False,'original_report_hash':cfg['report_hash'],'all_original_bytes_unchanged':True,
 'independent_inspection':'Closed-store exact source hashes, all6 frameRGB identities, downloadedPNG hashes, completedworker implementationhashes and phase receipts rechecked.',
 'scope':'Six original actual-native mixed-state frames; no model accuracy, person continuity, psychological construct or hardware/capacity signoff. Separate61-frame authored contract fixture covers beyond-preview paging.'}
out=folder/'acceptance.json';assert not out.exists();out.write_text(json.dumps(receipt,indent=2));print(json.dumps({'receipt':str(out),'sha256':sha(out),'groups':33,'scans':12,'new_jobs':len(new)}))
