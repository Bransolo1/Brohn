"""Original pixels/PCM, full PTS coverage and independently calculated cursor oracle."""
import copy
import csv
from fractions import Fraction
import importlib.util
import json
import math
from pathlib import Path
import struct
import subprocess
import sys
import wave

ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/"scripts/workers"))
import media_review as worker
import audio_extract
from PIL import Image
folder=Path(sys.argv[1]).resolve();folder.mkdir(parents=True,exist_ok=True)
assert not any(folder.iterdir()),"Use an empty external evidence folder."
checks=[];counter=0

def check(label,ok):
    if not ok:(folder/"failure.json").write_text(json.dumps({"failed":label,"passed":checks},indent=2))
    assert ok,label
    checks.append(label);print("PASS",label,flush=True)

def rejects(action):
    try:action()
    except (ValueError,FileNotFoundError):return True
    return False

def ff(args):subprocess.run(["ffmpeg","-v","error","-nostdin","-n",*map(str,args)],check=True,timeout=60,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)

rate=8000;frames=160;width=64;height=48
raw=folder/"original.rgb";pixels=[bytes((n,255-n,(n*3)%256))*(width*height) for n in range(frames)];raw.write_bytes(b"".join(pixels))
audio=folder/"original.wav"
with wave.open(str(audio),"wb") as f:
    f.setparams((1,2,rate,0,"NONE","not compressed"));f.writeframes(b"".join(struct.pack("<h",round(9000*math.sin(2*math.pi*250*n/rate))) for n in range(rate*4)))
regular=folder/"regular.mkv";gap=folder/"gap.mkv"
inputs=["-f","rawvideo","-pixel_format","rgb24","-video_size",f"{width}x{height}","-framerate","40","-i",raw,"-i",audio]
ff([*inputs,"-map","0:v:0","-map","1:a:0","-c:v","ffv1","-c:a","copy",regular])
ff([*inputs,"-map","0:v:0","-map","1:a:0","-vf",r"setpts=PTS+if(gte(N\,80)\,0.5/TB\,0)","-fps_mode","passthrough","-c:v","ffv1","-c:a","copy",gap])

def extraction(source):
    directory=folder/(source.stem+"-audio")
    r=audio_extract.analyse({"schema":"brohn-audio-extract-request/1.0","operation":"extract","binding":{"original":True},"source_path":str(source),"source_hash":worker.sha(source),"selection":{"stream_index":1},"output_directory":str(directory)})
    return r,directory

ext,extdir=extraction(regular);gap_ext,gapdir=extraction(gap)

def request(source=regular,cursor=8000,operation="media_review",ex=ext,directory=extdir):
    global counter
    counter+=1;ledger=directory/"audio-frames.csv"
    return {"schema":"brohn-media-review-request/1.0","operation":operation,"binding":{"original_source":"software-fixture","origin":"sample"},
            "source_path":str(source),"source":{"hash":worker.sha(source),"size":source.stat().st_size},"audio_ledger_path":str(ledger),"audio_ledger":{"hash":worker.sha(ledger),"size":ledger.stat().st_size},
            "recording":ex["recording"],"selection":None if operation=="media_tracks" else {"video_stream_index":0,"cursor_sample":cursor},"output_directory":str(folder/f"review-{counter}")}

inventory=worker.analyse(request(operation="media_tracks"))
check("Inventory names actual video stream and encoded dimensions without inventing a cursor",inventory["tracks"][0]["stream_index"]==0 and inventory["tracks"][0]["width"]==width and inventory["mapping"] is None and not inventory["artifacts"])
r=request();result=worker.analyse(r);out=Path(r["output_directory"])
check("Exact one-second audio sample maps to actual frame40 using frame-local PTS",result["coverage"]["frame"]["frame_index"]==40 and result["mapping"]["audio_frame"]["container_time"]=={"numerator":"1","denominator":"1","display_s":"1"})
image=result["artifacts"][1]
with Image.open(out/image["path"]) as f:actual=f.convert("RGB").tobytes()
check("Actual preserved frame pixels equal the independent original RGB frame",actual==pixels[40] and result["frame_extraction"]["rgb24_sha256"]==__import__("hashlib").sha256(pixels[40]).hexdigest())
rows=list(csv.DictReader((out/"video-frames.csv").open(newline="",encoding="utf-8")))
check("Complete160frame ledger exceeds preview but retains exact independent PTS and durations",len(rows)==160 and len(result["rows"])==100 and all(Fraction(int(row["pts_ticks"]))*Fraction(row["time_base"])==Fraction(i,40) and Fraction(int(row["duration_ticks"]))*Fraction(row["time_base"])==Fraction(1,40) for i,row in enumerate(rows)))
check("Exact frame boundary is disclosed as within timestamp precision without physical sync claim",result["coverage"]["frame"]["precision_crosses_frame_boundary"] and result["mapping"]["physical_synchronization"]=="not_established")
inside=worker.analyse(request(cursor=8100))
check("Interior cursor retains exact local sample offset and frame40",inside["coverage"]["frame"]["frame_index"]==40 and not inside["coverage"]["frame"]["precision_crosses_frame_boundary"])
g=worker.analyse(request(gap,18000,ex=gap_ext,directory=gapdir))
check("Actual encoded timestamp gap produces no invented held frame or PNG",g["coverage"]["status"]=="no_supported_frame" and g["coverage"]["gaps"]==1 and len(g["artifacts"])==1)
check("Wrong selected stream fails before media publication",rejects(lambda:worker.analyse(dict(request(),selection={"video_stream_index":1,"cursor_sample":8000}))))
check("Source substitution is rejected",rejects(lambda:worker.analyse(dict(request(),source={"hash":"0"*64,"size":regular.stat().st_size}))))
check("Audio ledger substitution is rejected",rejects(lambda:worker.analyse(dict(request(),audio_ledger={"hash":"0"*64,"size":(extdir/"audio-frames.csv").stat().st_size}))))
check("Boolean cursor cannot alias an exact numeric sample",rejects(lambda:worker.analyse(dict(request(),selection={"video_stream_index":0,"cursor_sample":True}))))
track=result["tracks"][0];mapping=result["mapping"]
frameset=[{"media_type":"video","stream_index":0,"pts":i*25,"duration":25,"width":width,"height":height} for i in range(60)]
_,base=worker.video_ledger(frameset,track,mapping)
missing=copy.deepcopy(frameset);missing[2].pop("pts")
check("Missing original PTS suppresses image selection even away from that row",worker.video_ledger(missing,track,mapping)[1]["status"]=="ambiguous_clock")
reset=copy.deepcopy(frameset);reset[41]["pts"]=0
check("Duplicate or reset PTS cannot acquire an invented epoch correspondence",worker.video_ledger(reset,track,mapping)[1]["status"]=="ambiguous_clock")
unknown=copy.deepcopy(frameset);unknown[40].pop("duration")
check("Unknown duration can expose only the original exact PTS point",worker.video_ledger(unknown,track,mapping)[1]["frame"]["frame_index"]==40 and worker.video_ledger(unknown,track,inside["mapping"])[1]["frame"] is None)
overlap=copy.deepcopy(frameset);overlap[39]["duration"]=100
check("Overlapping declared frames are explicit and do not pick arbitrary pixels",worker.video_ledger(overlap,track,mapping)[1]["status"]=="overlapping_frames")
conflict=copy.deepcopy(frameset);conflict[0]["pkt_duration"]=26
check("Conflicting duration fields refuse inferred coverage",rejects(lambda:worker.video_ledger(conflict,track,mapping)))
large=copy.deepcopy(frameset);[f.update(pts=f["pts"]+9007199254741013) for f in large]
large_rows,_=worker.video_ledger(large,track,mapping)
check("Video PTS above binary64 integer precision remains exact decimal text",large_rows[0]["pts_ticks"]=="9007199254741013" and large_rows[1]["pts_ticks"]=="9007199254741038")
check("No review changes the original video or extraction bytes",worker.sha(regular)==r["source"]["hash"] and worker.sha(extdir/"audio-frames.csv")==r["audio_ledger"]["hash"])
(folder/"results.json").write_text(json.dumps({"passed":True,"checks":checks,"source_hashes":{p:worker.sha(ROOT/p) for p in ("scripts/workers/media_review.py","scripts/workers/media_pixels.py","scripts/workers/audio_extract.py")},"regular_result":result,"gap_result":g},indent=2))
print(json.dumps({"passed":True,"checks":len(checks),"folder":str(folder)}))
