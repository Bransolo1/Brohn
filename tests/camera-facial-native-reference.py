"""Independent native API and exact-PTS check of the retained browser recording.
No Brohn frame-conversion or summary helper is used. Software agreement only.
"""
from pathlib import Path
from fractions import Fraction
from decimal import Decimal
import csv, hashlib, io, json, math, os, subprocess, sys
ROOT=Path(__file__).resolve().parents[1];WORK=(ROOT/'../../work').resolve();folder=Path(sys.argv[1]).resolve()
assert folder.is_dir() and (folder/'results.json').is_file()
out=folder/'independent-native-reference.json';assert not out.exists()
report=json.loads((folder/'facial-report.json').read_text());rows=[json.loads(x) for x in (folder/'facial-observations.jsonl').read_text().splitlines()]
video=folder/'original-browser-recording.webm';sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest();original=sha(video)
assert original==report['analysis']['source']['sha256']
bin_dir=WORK/'tooling/facial-ffmpeg/ffmpeg-n8.1.3-win64-lgpl-shared-8.1/bin';model_dir=WORK/'tooling/facial-au-models'
os.environ.update(HF_HUB_OFFLINE='1',HF_HUB_DISABLE_TELEMETRY='1',MPLBACKEND='Agg',OMP_NUM_THREADS='1',OPENBLAS_NUM_THREADS='1');os.environ.pop('FEAT_POSE_MLP_PATH',None)
os.environ['PATH']=str(bin_dir)+os.pathsep+os.environ.get('PATH','');dll=os.add_dll_directory(str(bin_dir))
info=json.loads(subprocess.check_output([str(bin_dir/'ffprobe.exe'),'-v','error','-select_streams','v:0','-show_frames','-show_streams','-of','json',str(video)],creationflags=subprocess.CREATE_NO_WINDOW))
stream=info['streams'][0];tb=Fraction(stream['time_base']);times=[int(f['pts'])*tb for f in info['frames']];relative=[x-times[0] for x in times]
p=report['analysis']['parameters'];lo=Fraction(Decimal(p['start_s']));hi=Fraction(Decimal(p['end_s'])) if p['end_s'] is not None else None
selected=[i for i,t in enumerate(relative) if t>=lo and (hi is None or t<=hi)][::p['frame_stride']]
assert [x['frame_index'] for x in rows]==selected
raw=subprocess.check_output([str(bin_dir/'ffmpeg.exe'),'-v','error','-nostdin','-noautorotate','-i',str(video),'-map','0:v:0','-an','-sn','-dn','-pix_fmt','rgb24','-f','rawvideo','-fps_mode','passthrough','pipe:1'],creationflags=subprocess.CREATE_NO_WINDOW)
size=stream['width']*stream['height']*3;assert len(raw)==len(times)*size
import huggingface_hub
manifest=json.loads((ROOT/'scripts/readiness/facial-models.json').read_text());requests=[]
def lookup(repo_id,filename,**kwargs):
    found=[x for x in manifest['files'] if x['repo_id']==repo_id and x['filename']==filename];assert len(found)==1
    f=model_dir/found[0]['relative_path'];assert sha(f)==found[0]['sha256'];requests.append((repo_id,filename));return str(f)
huggingface_hub.hf_hub_download=lookup
import numpy as np
import torch
from feat import Detectorv1
torch.set_num_threads(1);torch.set_num_interop_threads(1)
detector=Detectorv1(face_model='retinaface',landmark_model='mobilefacenet',au_model='xgb',emotion_model='resmasknet',identity_model=None,gaze_model=None,device='cpu')
native=[]
for row,index in zip(rows,selected):
    pixels=raw[index*size:(index+1)*size];assert hashlib.sha256(pixels).hexdigest()==row['decoded_rgb_sha256']
    assert row['source_pts']==str(info['frames'][index]['pts']) and row['source_time_base']==stream['time_base']
    assert Fraction(int(row['relative_time']['numerator']),int(row['relative_time']['denominator']))==relative[index]
    image=np.frombuffer(pixels,dtype=np.uint8).reshape(stream['height'],stream['width'],3).copy()
    tensor=torch.from_numpy(image).permute(2,0,1).unsqueeze(0)
    table=detector.detect(tensor,data_type='tensor',batch_size=1,num_workers=0,pin_memory=False,face_detection_threshold=.5,progress_bar=False)
    found=[x for x in table.to_dict(orient='records') if x['FaceScore']>=.5];assert len(found)==row['face_count']
    for actual,expected in zip(row['faces'],found):
        for k,v in {**actual['au_scores'],**actual['expression_scores'],**actual['bbox'],'FaceScore':actual['detection_score']}.items():assert v==float(expected[k]),k
    native.append([{k:float(v) for k,v in x.items() if k in set(list(table.au_columns)+list(table.emotion_columns)+list(table.facebox_columns))} for x in found])
values=list(csv.DictReader(io.StringIO((folder/'facial-values.csv').read_text())))
assert len(values)==sum(max(1,r['face_count']) for r in rows)
cursor=0
for row in rows:
    for face in row['faces'] or [None]:
        cell=values[cursor];cursor+=1;assert cell['source_pts']==row['source_pts'] and cell['source_time_base']==row['source_time_base']
        for f in report['analysis']['features']:
            key=f['metric'];assert (float(cell[key])=={**face['au_scores'],**face['expression_scores']}[key]) if face else cell[key]==''
eligible=[i for i,r in enumerate(rows) if r['eligible']]
for f in report['analysis']['features']:
    k=f['metric'];assert f['value']==sum(native[i][0][k] for i in eligible)/len(eligible)
    pairs=[(i-1,i,relative[selected[i]]-relative[selected[i-1]]) for i in range(1,len(rows)) if i in eligible and i-1 in eligible and 0<relative[selected[i]]-relative[selected[i-1]]<=Fraction(str(p['max_support_gap_s']))]
    duration=sum((dt for _,_,dt in pairs),Fraction(0));expected=sum((native[i][0][k]+native[j][0][k])/2*float(dt) for i,j,dt in pairs)/float(duration) if duration else None
    assert (f['time_weighted_mean'] is None) if expected is None else abs(f['time_weighted_mean']-expected)<1e-12
assert sha(video)==original
checks=['Exact selected frame indices/PTS/rational relative times match independent ffprobe selection','Every selected decoded RGB byte hash matches direct ffmpeg output','Every AU/category/bounding box/detection score matches independent native Detectorv1 API calls','Every full CSV face-wise value matches native JSONL without absent-face zero imputation','All27 frame means and eligible gap-bounded trapezoidal means reconcile independently','Original browser-recorded source hash stays unchanged']
receipt={'passed':True,'checks':checks,'count':len(checks),'source_hash':original,'source_report_sha256':sha(folder/'facial-report.json'),'jsonl_sha256':sha(folder/'facial-observations.jsonl'),'csv_sha256':sha(folder/'facial-values.csv'),'test_hash':sha(__file__),'models_requested':requests,'selected_frames':selected,'native':native,'qualification':'Software transport/native-library agreement on a repeated licensed still; no empirical AU/emotion accuracy, actual-participant or physical-clock claim.'}
out.write_text(json.dumps(receipt,indent=2,allow_nan=False)+'\n');print(json.dumps({'passed':True,'count':len(checks),'path':str(out)}))
