"""Actual optional worker vs separate native Detectorv1 calls on labelled fixtures.

The permitted existing upstream still is composed into synthetic test frames;
this is software agreement, not an emotion/AU accuracy or human-data benchmark.
"""
from __future__ import annotations
import csv
import hashlib
import io
import json
import math
import os
from pathlib import Path
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
WORK = (ROOT / "../../work").resolve()
folder = Path(sys.argv[1]).resolve()
folder.mkdir(parents=True, exist_ok=False)
os.chdir(ROOT)
bin_dir = WORK / "tooling/facial-ffmpeg/ffmpeg-n8.1.3-win64-lgpl-shared-8.1/bin"
model_dir = WORK / "tooling/facial-au-models"
env = {**os.environ, "BROHN_FACIAL_MODEL_DIR": str(model_dir), "BROHN_FACIAL_FFMPEG_DIR": str(bin_dir),
       "HF_HUB_OFFLINE": "1", "HF_HUB_DISABLE_TELEMETRY": "1", "OMP_NUM_THREADS": "1", "OPENBLAS_NUM_THREADS": "1", "MPLBACKEND": "Agg"}
os.environ.update(env)
dll = os.add_dll_directory(str(bin_dir))
os.environ["PATH"] = str(bin_dir) + os.pathsep + os.environ.get("PATH", "")
hash_file = lambda p: hashlib.sha256(Path(p).read_bytes()).hexdigest()
checks = []


def check(ok, label):
    assert ok, label
    checks.append(label)
    print("PASS", label, flush=True)


try:
    import numpy as np
    from PIL import Image
    original = Path("C:/Users/User/Documents/Codex/2026-09-20/oka/work/brohn-vision-references-01/face/business-person.png")
    assert hash_file(original) == "1f61cf0603cef77ffca4e24848ddf8290b5651d03b957e93b742c9ef963b5c11"
    face = Image.open(original).convert("RGB").resize((320,454), Image.Resampling.BILINEAR)
    blank = Image.new("RGB",(640,454)); single=blank.copy();single.paste(face,(160,0)); multiple=blank.copy();multiple.paste(face,(0,0));multiple.paste(face,(320,0))
    frames=[blank,single,single,multiple,blank,single]
    raw_hashes=[]
    for i,image in enumerate(frames):
        image.save(folder/f"frame-{i:03d}.png");raw_hashes.append(hashlib.sha256(image.tobytes()).hexdigest())
    pts=[2000,2040,2110,2310,2710,2910]
    expression=str(pts[-1])
    for i in reversed(range(len(pts)-1)):expression=f"if(eq(N,{i}),{pts[i]},{expression})"
    source=folder/'authored-vfr-face-reference.mkv'
    command=[str(bin_dir/'ffmpeg.exe'),'-v','error','-nostdin','-framerate','25','-i',str(folder/'frame-%03d.png'),'-vf',f"settb=1/1000,setpts='{expression}'",'-frames:v','6','-c:v','ffv1','-pix_fmt','bgr0','-enc_time_base','1/1000','-fps_mode','passthrough',str(source)]
    subprocess.run(command,check=True,capture_output=True,timeout=60)
    code_files=['scripts/workers/facial_expression.py','scripts/workers/vision.py','scripts/readiness/facial-models.json','scripts/readiness/facial-runtime.json','scripts/readiness/requirements-facial-au.txt']
    code_hashes={p:hash_file(ROOT/p) for p in code_files}
    fixture={'schema':'brohn-facial-native-fixture/1.0','source_hash':hash_file(source),'source':str(source),'source_bytes':source.stat().st_size,'pts':pts,'time_base':'1/1000','rgb_sha256':raw_hashes,
             'upstream_image_sha256':hash_file(original),'upstream_url':'https://raw.githubusercontent.com/google-ai-edge/mediapipe-samples/c2518ec444c3a3a99689e5d31eddadc240c83a0c/examples/face_landmarker/ios/FaceLandmarkerTests/business-person.png',
             'license':'Apache-2.0 upstream repository test asset; no new participant capture','composition':'One existing permitted still resized to320x454, centered/duplicated on640x454canvas; blank/single/single/multiple/blank/single. No motion/accuracy claim.',
             'ffmpeg_command':command,'code_hashes':code_hashes}
    (folder/'fixture.json').write_text(json.dumps(fixture,indent=2),encoding='utf-8')
    artifacts=folder/'artifacts';artifacts.mkdir()
    request={'schema':'brohn-facial-expression-request/1.0','source_path':str(source),'source_hash':fixture['source_hash'],'output_directory':str(artifacts),
             'metadata':{'profile':'facial_au_expression_pyfeat_v1','origin_statement':fixture['composition'],'consent_statement':'Software fixture from permitted upstream test imagery; no participant recording.','start_s':'0','end_s':None,'frame_stride':1,'max_support_gap_s':.25}}
    request_path=folder/'request.json';request_path.write_text(json.dumps(request),encoding='utf-8');result_path=folder/'result.json'
    start=time.perf_counter()
    with (folder/'worker.log').open('wb') as log:
        executed=subprocess.run([sys.executable,str(ROOT/'scripts/workers/facial_expression.py'),'--request',str(request_path),'--output',str(result_path)],env=env,stdout=log,stderr=log,timeout=1200)
    result=json.loads(result_path.read_text(encoding='utf-8'));assert executed.returncode==0,result.get('error')
    worker_seconds=time.perf_counter()-start
    artifact=next(x for x in result['artifacts'] if x['kind']=='facial-observations');csvartifact=next(x for x in result['artifacts'] if x['kind']=='facial-values')
    rows=[json.loads(line) for line in Path(artifact['path']).read_text(encoding='utf-8').splitlines()];values=list(csv.DictReader(Path(csvartifact['path']).open(encoding='utf-8',newline='')))
    check([int(r['source_pts']) for r in rows]==pts and all(r['source_time_base']=='1/1000' for r in rows),'actual VFR decode preserves independently authored integer PTS and nonzero origin')
    check([r['decoded_rgb_sha256'] for r in rows]==raw_hashes,'lossless decoder pixels match every independently composed frame')
    check([r['face_count'] for r in rows]==[0,1,1,2,0,1] and [r['state'] for r in rows]==['no_face','single_face','single_face','multiple_faces','no_face','single_face'],'actual native detector preserves blank single and multiple-face states')
    check(result['quality']['eligible_single_face_frames']==3 and result['quality']['eligible_time_exact']=={'numerator':'7','denominator':'100'},'no-face and multi-face states interrupt exact eligible time support')
    check(len(rows)==6 and len(values)==7 and hash_file(artifact['path'])==artifact['sha256'] and hash_file(csvartifact['path'])==csvartifact['sha256'],'complete JSONL and face-wise CSV match retained counts and immutable hashes')
    # Independent caller: use the public native API, not Brohn's native_frame or
    # conversion/summary helpers. Only explicitly pinned local path resolution is shared as a contract.
    import huggingface_hub
    manifest=json.loads((ROOT/'scripts/readiness/facial-models.json').read_text(encoding='utf-8'))
    requests=[]
    def lookup(repo_id,filename,**kwargs):
        requests.append((repo_id,filename))
        chosen=[x for x in manifest['files'] if x['repo_id']==repo_id and x['filename']==filename]
        if len(chosen)!=1:raise RuntimeError('Unselected auxiliary model remains unavailable offline.')
        target=model_dir/chosen[0]['relative_path'];assert hash_file(target)==chosen[0]['sha256'];return str(target)
    huggingface_hub.hf_hub_download=lookup
    os.environ.pop('FEAT_POSE_MLP_PATH',None)
    import torch
    from feat import Detectorv1
    torch.set_num_threads(1);torch.set_num_interop_threads(1)
    detector=Detectorv1(face_model='retinaface',landmark_model='mobilefacenet',au_model='xgb',emotion_model='resmasknet',identity_model=None,gaze_model=None,device='cpu')
    native=[]
    for image,row in zip(frames,rows):
        tensor=torch.from_numpy(np.asarray(image).copy()).permute(2,0,1).unsqueeze(0)
        output=detector.detect(tensor,data_type='tensor',batch_size=1,num_workers=0,pin_memory=False,face_detection_threshold=.5,progress_bar=False)
        raw=output.to_dict(orient='records');detected=[x for x in raw if x['FaceScore']>=.5]
        assert len(detected)==row['face_count']
        for actual,expected in zip(row['faces'],detected):
            for name,value in actual['au_scores'].items():assert value==float(expected[name]),name
            for name,value in actual['expression_scores'].items():assert value==float(expected[name]),name
            for name,value in actual['bbox'].items():assert value==float(expected[name]),name
            assert actual['detection_score']==float(expected['FaceScore'])
        native.append([{k:(float(x[k]) if math.isfinite(float(x[k])) else None) for k in list(output.au_columns)+list(output.emotion_columns)+list(output.facebox_columns)} for x in raw])
    (folder/'independent-native.json').write_text(json.dumps(native,indent=2,allow_nan=False),encoding='utf-8')
    check(True,'every native AU category bounding-box and detection score agrees exactly with independent Detectorv1 calls')
    for feature in result['features']:
        key=feature['metric'];expected=sum(native[i][0][key] for i in [1,2,5])/3
        assert feature['value']==expected
        assert abs(feature['time_weighted_mean']-(native[1][0][key]+native[2][0][key])/2)<1e-12
    check(True,'all27 frame means and gap-bounded trapezoidal means reconcile to independent native values')
    serialized=Path(artifact['path']).read_text(encoding='utf-8')+Path(csvartifact['path']).read_text(encoding='utf-8')
    check('Identity_' not in serialized and 'identity_embedding' not in serialized and 'gaze_pitch' not in serialized and all(not r['faces'] for r in [rows[0],rows[4]]),'no identity gaze or fabricated neutral scores escape the provider boundary')
    check(hash_file(source)==fixture['source_hash'] and {p:hash_file(ROOT/p) for p in code_files}==code_hashes,'source media and explicit provider/runtime identities stay unchanged across worker and reference inference')
    receipt={'passed':True,'checks':checks,'source_hash':fixture['source_hash'],'code_hashes':code_hashes,'worker_seconds':worker_seconds,'model_requests':requests,
             'result_sha256':hash_file(result_path),'native_sha256':hash_file(folder/'independent-native.json'),'artifact_sha256':artifact['sha256'],'csv_sha256':csvartifact['sha256'],
             'qualification':'Software source/clock/native-output agreement only. Synthetic repeated/composed upstream reference image; no empirical AU accuracy, inner-emotion, physical timing or identity claim.'}
    (folder/'results.json').write_text(json.dumps(receipt,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'passed':True,'checks':len(checks),'folder':str(folder)}),flush=True)
except Exception as error:
    (folder/'failure.json').write_text(json.dumps({'passed':False,'checks':checks,'type':type(error).__name__,'error':str(error)},indent=2),encoding='utf-8')
    raise
finally:
    dll.close()
