"""Original analytic media and an independent RIFF/PCM equality oracle."""
import argparse
import array
import hashlib
import json
import math
from pathlib import Path
import struct
import subprocess
import sys
import wave

parser=argparse.ArgumentParser();parser.add_argument("folder");parser.add_argument("--verify");args=parser.parse_args()
folder=Path(args.folder).resolve()
def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def pcm(path):
    data=path.read_bytes();assert data[:4]==b"RIFF" and data[8:12]==b"WAVE"
    offset=12;fmt=None;payload=None
    while offset+8<=len(data):
        key=data[offset:offset+4];size=struct.unpack_from("<I",data,offset+4)[0];part=data[offset+8:offset+8+size]
        if key==b"fmt ":fmt=struct.unpack_from("<HHIIHH",part)
        if key==b"data":payload=part
        offset+=8+size+(size%2)
    assert fmt and payload is not None
    code,channels,rate,_,_,bits=fmt
    if code==1 and bits==16:values=[v[0]/32768 for v in struct.iter_unpack("<h",payload)]
    elif code==3 and bits==64:values=[v[0] for v in struct.iter_unpack("<d",payload)]
    else:raise AssertionError((code,bits))
    return channels,rate,values
if args.verify:
    expected=pcm(folder/"original.wav");actual=pcm(Path(args.verify));assert actual==expected
    print(json.dumps({"passed":True,"channel_values":len(actual[2]),"channels":actual[0],"rate":actual[1]}));sys.exit()
folder.mkdir(parents=True,exist_ok=True)
assert not (folder/"media.json").exists(),"Use a new fixture directory."
rate=48000;n=rate*3;values=array.array("h")
for i in range(n):values.extend((round(7000*math.sin(2*math.pi*220*i/rate)),round(10000*math.sin(2*math.pi*440*i/rate))))
if sys.byteorder!="little":values.byteswap()
with wave.open(str(folder/"original.wav"),"wb") as f:f.setnchannels(2);f.setsampwidth(2);f.setframerate(rate);f.writeframes(values.tobytes())
def ff(args):subprocess.run(["ffmpeg","-v","error","-nostdin","-n",*map(str,args)],check=True,timeout=60,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)
video=["-f","lavfi","-i","color=c=0x284b63:s=320x240:r=15:d=3"]
base=[*video,"-i",folder/"original.wav","-map","0:v:0","-map","1:a:0"]
ff([*base,"-c:v","ffv1","-c:a","copy",folder/"lossless.mkv"])
ff([*base,"-map","1:a:0","-c:v","ffv1","-c:a","copy",folder/"multiple.mkv"])
ff([*video,"-an","-c:v","ffv1",folder/"no-audio.mkv"])
ff([*base,"-af",r"asetpts=PTS+if(gte(T\,1.5)\,0.1/TB\,0)","-c:v","ffv1","-c:a","pcm_s16le",folder/"gap.mkv"])
ff([*video,"-pix_fmt","yuv420p","-f","yuv4mpegpipe",folder/"camera.y4m"])
names=["original.wav","lossless.mkv","multiple.mkv","no-audio.mkv","gap.mkv","camera.y4m"]
(folder/"media.json").write_text(json.dumps({"origin":"original_analytic_media_no_person", "hashes":{name:digest(folder/name) for name in names}},indent=2))
print(json.dumps({"passed":True,"folder":str(folder)}))
