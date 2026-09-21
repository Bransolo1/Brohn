"""Download official test imagery OUTSIDE the repo and run pinned production models.

Opt-in reference workflow test. Repeated-image video is not a natural motion or
population-accuracy benchmark. Original media are retained with upstream license.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import urllib.request

ROOT=Path(__file__).resolve().parents[2]
COMMIT="c2518ec444c3a3a99689e5d31eddadc240c83a0c"
BASE=f"https://raw.githubusercontent.com/google-ai-edge/mediapipe-samples/{COMMIT}/"
ASSETS={"face":"examples/face_landmarker/ios/FaceLandmarkerTests/business-person.png",
        "pose":"examples/pose_landmarker/ios/PoseLandmarkerTests/test_image.jpg",
        "hands":"examples/hand_landmarker/ios/HandLandmarkerTests/thumbs-up.png"}
def digest(path):
    with path.open("rb") as stream:return hashlib.file_digest(stream,"sha256").hexdigest()
def save(path,value):path.write_text(json.dumps(value,indent=2),encoding="utf-8")


def main():
    p=argparse.ArgumentParser();p.add_argument("--folder",required=True);args=p.parse_args();folder=Path(args.folder).resolve()
    assert ROOT not in folder.parents and not folder.exists();folder.mkdir(parents=True)
    license_url=BASE+"LICENSE";license_path=folder/"UPSTREAM-LICENSE.txt";license_path.write_bytes(urllib.request.urlopen(license_url,timeout=30).read())
    manifest={"schema":"brohn-public-vision-reference/1.0","upstream":"google-ai-edge/mediapipe-samples","commit":COMMIT,
              "license":"Apache-2.0 repository test assets","license_url":license_url,"license_sha256":digest(license_path),"cases":{},
              "qualification":"Static official reference imagery encoded into short videos; software inference/source agreement only, no new person or hardware capture and no accuracy claim."}
    ffmpeg=shutil.which("ffmpeg");assert ffmpeg
    for family,asset in ASSETS.items():
        case=folder/family;case.mkdir();image=case/Path(asset).name;url=BASE+asset
        with urllib.request.urlopen(url,timeout=30) as response:raw=response.read(20*1024**2+1)
        assert 0<len(raw)<=20*1024**2;image.write_bytes(raw);video=case/"official-static-reference.mkv"
        # Lossless fixed dimensions; encoded PTS begins at 2s, not at browser time.
        command=[ffmpeg,"-v","error","-nostdin","-loop","1","-framerate","5","-i",str(image),"-vf","setpts=PTS+2/TB","-frames:v","4","-c:v","ffv1","-pix_fmt","bgr0","-fps_mode","passthrough",str(video)]
        subprocess.run(command,check=True,timeout=60,creationflags=subprocess.CREATE_NO_WINDOW)
        request={"schema":"brohn-vision-request/1.0","operation":"analyse_video","source_path":str(video),"source_hash":digest(video),
                 "metadata":{"profile":"custom_v1","channels":[family]},"output_directory":str(case/"artifacts")}
        save(case/"request.json",request)
        result_path=case/"result.json";python=ROOT/"../../work/tooling/vision-audio-venv/Scripts/python.exe"
        completed=subprocess.run([str(python.resolve()),"-B",str(ROOT/"scripts/workers/vision.py"),"--request",str(case/"request.json"),"--output",str(result_path)],cwd=ROOT,capture_output=True,text=True,timeout=300,creationflags=subprocess.CREATE_NO_WINDOW)
        (case/"worker.log").write_text(completed.stdout+completed.stderr,encoding="utf-8")
        result=json.loads(result_path.read_bytes()) if result_path.exists() else {}
        record={"source_url":url,"upstream_path":asset,"image_sha256":digest(image),"image_bytes":image.stat().st_size,"video_sha256":digest(video),"video_bytes":video.stat().st_size,
                "ffmpeg_command":command,"worker_sha256":digest(ROOT/"scripts/workers/vision.py"),"returncode":completed.returncode,"result_path":str(result_path),
                "status":result.get("status"),"quality":result.get("quality"),"engine":result.get("engine"),"parameters":result.get("parameters")}
        manifest["cases"][family]=record;save(folder/"reference-manifest.json",manifest)
        assert completed.returncode==0 and result["quality"]["channels"][family]["valid_frames"]>0,record
        print("PASS",family,"actual pinned production inference",result["quality"]["channels"][family],flush=True)
    print(str(folder/"reference-manifest.json"))


if __name__=="__main__":main()
