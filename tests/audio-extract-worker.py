"""Original PCM oracle, actual lossless/Opus decode and clock boundary checks."""
import copy
import csv
from fractions import Fraction
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile

import numpy as np
import soundfile as sf

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("audio_extract", ROOT / "scripts/workers/audio_extract.py")
worker = importlib.util.module_from_spec(spec);spec.loader.exec_module(worker)
folder = Path(sys.argv[1]).resolve() if len(sys.argv)>1 else Path(tempfile.mkdtemp(prefix="brohn-audio-extract-"))
if not folder.exists():folder.mkdir(parents=True)
assert not any(folder.iterdir()), "Use a new empty external evidence directory."
checks=[];counter=0


def check(label, ok):
    if not ok:(folder/"failure.json").write_text(json.dumps({"failed":label,"passed":checks},indent=2))
    assert ok,label
    checks.append(label);print("PASS",label,flush=True)


def rejects(action):
    try:action()
    except (ValueError, FileNotFoundError):return True
    return False


def request(path, operation="extract", stream=1):
    global counter
    counter+=1
    return {"schema":"brohn-audio-extract-request/1.0","operation":operation,"binding":{"source_id":"original-sample-video","origin":"sample"},
            "source_path":str(path),"source_hash":worker.sha(path),"selection":None if operation=="inspect" else {"stream_index":stream},
            "output_directory":str(folder/f"attempt-{counter}")}


def ff(args):
    subprocess.run(["ffmpeg","-v","error","-nostdin","-n",*map(str,args)],check=True,timeout=60,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)


rate=48000;n=np.arange(rate*3)
original=np.column_stack([np.rint(7000*np.sin(2*np.pi*220*n/rate)),np.rint(10000*np.sin(2*np.pi*440*n/rate))]).astype(np.int16)
wav=folder/"original.wav";sf.write(wav,original,rate,subtype="PCM_16")
video=["-f","lavfi","-i","color=black:s=64x64:r=4:d=3"]
lossless=folder/"lossless.mkv";opus=folder/"browser.webm";multi=folder/"multiple.mkv";silent=folder/"no-audio.mkv";gap=folder/"gap.mkv";aac=folder/"aac.mp4"
ff([*video,"-i",wav,"-map","0:v:0","-map","1:a:0","-c:v","ffv1","-c:a","copy",lossless])
ff([*video,"-i",wav,"-map","0:v:0","-map","1:a:0","-c:v","libvpx-vp9","-c:a","libopus",opus])
ff([*video,"-i",wav,"-map","0:v:0","-map","1:a:0","-c:v","libx264","-c:a","aac",aac])
ff([*video,"-i",wav,"-map","0:v:0","-map","1:a:0","-map","1:a:0","-c:v","ffv1","-c:a","copy",multi])
ff([*video,"-an","-c:v","ffv1",silent])
ff([*video,"-i",wav,"-map","0:v:0","-map","1:a:0","-af",r"asetpts=PTS+if(gte(T\,1.5)\,0.1/TB\,0)","-c:v","ffv1","-c:a","pcm_s16le",gap])
original_hashes={p.name:worker.sha(p) for p in (wav,lossless,opus,multi,silent,gap,aac)}

inspected=worker.analyse(request(lossless,"inspect"))
check("Inspection identifies the actual container audio stream and original rate/channels",len(inspected["tracks"])==1 and inspected["tracks"][0]["stream_index"]==1 and inspected["tracks"][0]["sampling_rate"]==48000 and inspected["tracks"][0]["channels"]==2 and not inspected["artifacts"])
check("Video without audio retains an explicit empty track inventory",worker.analyse(request(silent,"inspect"))["tracks"]==[])
check("All audio tracks retained before explicit choice",[t["stream_index"] for t in worker.analyse(request(multi,"inspect"))["tracks"]]==[1,2])
r=request(lossless);result=worker.analyse(r);directory=Path(r["output_directory"])
decoded,fs=sf.read(directory/"audio.wav",dtype="float64",always_2d=True)
check("Lossless extraction exactly preserves all 288000 original PCM16 channel values",fs==rate and np.array_equal(decoded,original.astype(float)/32768))
check("Derived WAV keeps two channels and DOUBLE precision",sf.info(directory/"audio.wav").subtype=="DOUBLE" and result["recording"]["channels"]==2 and result["recording"]["samples_per_channel"]==len(original))
with (directory/"audio-frames.csv").open(newline="") as f:rows=list(csv.DictReader(f))
check("Frame ledger covers every sample exactly once",int(rows[0]["start_sample"])==0 and int(rows[-1]["end_sample_exclusive"])==len(original) and all(int(a["end_sample_exclusive"])==int(b["start_sample"]) for a,b in zip(rows,rows[1:])))
check("Exported PTS and sample clocks independently reproduce declared residuals",all(abs(float(Fraction(x["pts_ticks"])*Fraction(x["time_base"])-Fraction(int(x["start_sample"]),rate))-float(x["pts_minus_sample_clock_s"]))<1e-12 for x in rows))
check("Both artifacts retain exact size/hash",all((directory/a["path"]).stat().st_size==a["bytes"] and worker.sha(directory/a["path"])==a["sha256"] for a in result["artifacts"]))
check("Existing output directory is never overwritten",rejects(lambda:worker.analyse(r)))
check("Wrong source hash refused before extraction",rejects(lambda:worker.analyse({**request(lossless),"source_hash":"0"*64})))
check("Video stream cannot be selected as audio",rejects(lambda:worker.analyse(request(lossless,stream=0))))
check("Missing audio stream refused",rejects(lambda:worker.analyse(request(lossless,stream=3))))
r=request(multi,stream=2);second=worker.analyse(r)
check("Explicit second audio stream selected without mixing",second["recording"]["stream_index"]==2 and np.array_equal(sf.read(Path(r["output_directory"])/"audio.wav",always_2d=True)[0],original.astype(float)/32768))
r=request(opus);browser=worker.analyse(r);opdir=Path(r["output_directory"])
reference=folder/"independent-opus.f64"
ff(["-i",opus,"-map","0:1","-c:a","pcm_f64le","-f","f64le",reference])
check("Opus retains decoder samples exactly, without claiming compressed input equals original PCM",np.array_equal(sf.read(opdir/"audio.wav",always_2d=True)[0],np.fromfile(reference,dtype="<f8").reshape(-1,2)))
check("Opus trimming and timestamp quantization remain explicit",browser["recording"]["samples_per_channel"]==144000 and browser["recording"]["frame_count"]==151 and float(browser["recording"]["maximum_pts_residual_s"])>0 and browser["recording"]["time_base"]=="1/1000")
r=request(aac);mp4=worker.analyse(r);reference_aac=folder/"independent-aac.f64"
ff(["-i",aac,"-map","0:1","-c:a","pcm_f64le","-f","f64le",reference_aac])
check("MP4 AAC decoded padding/sample extent remains explicit and matches complete decoder output",np.array_equal(sf.read(Path(r["output_directory"])/"audio.wav",always_2d=True)[0],np.fromfile(reference_aac,dtype="<f8").reshape(-1,2)) and mp4["recording"]["samples_per_channel"]*16==reference_aac.stat().st_size)
check("Actual container timestamp gap is rejected instead of concatenated",rejects(lambda:worker.analyse(request(gap))))

track={"stream_index":1,"sampling_rate":1000,"channels":1,"time_base":"1/1000"}
base=[{"media_type":"audio","stream_index":1,"pts":0,"nb_samples":10,"channels":1},
      {"media_type":"audio","stream_index":1,"pts":10,"nb_samples":10,"channels":1}]
for label,change in [("reset",{"pts":0}),("missing PTS",{"pts":None}),("noninteger PTS",{"pts":1.5}),("channel change",{"channels":2}),("rate change",{"sample_rate":"2000"}),("foreign stream",{"stream_index":2}),("excess drift",{"pts":13})]:
    bad=copy.deepcopy(base);bad[1].update(change)
    check("Frame ledger rejects "+label,rejects(lambda:worker.frame_ledger(bad,track)))
edge=copy.deepcopy(base);edge[1]["pts"]=12
check("Declared precision boundary is inclusive",worker.frame_ledger(edge,track)[1]["maximum_pts_residual_s"]=="0.002")
negative=copy.deepcopy(base)
for f in negative:f["pts"]-=100
check("Negative original timestamp origin is preserved",worker.frame_ledger(negative,track)[1]["source_start_pts_ticks"]=="-100")
check("Coarse time bases require another declared profile",rejects(lambda:worker.stream_info({"index":1,"codec_name":"pcm_s16le","sample_rate":"1000","channels":1,"time_base":"1/10"})))
check("Repeated JSON fields rejected",rejects(lambda:json.loads('{"x":1,"x":2}',object_pairs_hook=worker.pairs)))
check("Boolean stream index cannot alias stream one",rejects(lambda:worker.analyse(request(lossless,stream=True))))
request_file=folder/"cli-request.json";request_file.write_text(json.dumps(request(lossless,"inspect")))
cli_output=folder/"cli-result.json"
process=subprocess.run([sys.executable,str(ROOT/"scripts/workers/audio_extract.py"),"--input",str(request_file),"--output",str(cli_output)],capture_output=True,timeout=30)
check("Actual command-line inspection preserves requested source binding",process.returncode==0 and json.loads(cli_output.read_text())["binding"]=={"source_id":"original-sample-video","origin":"sample"})
request_file.write_text('{"schema":"x","schema":"y"}')
bad_cli=folder/"bad-cli-result.json"
process=subprocess.run([sys.executable,str(ROOT/"scripts/workers/audio_extract.py"),"--input",str(request_file),"--output",str(bad_cli)],capture_output=True,timeout=30)
check("Malformed command-line request produces no successful output",process.returncode!=0 and not bad_cli.exists())
check("Original source recordings remain unchanged",original_hashes=={p.name:worker.sha(p) for p in (wav,lossless,opus,multi,silent,gap,aac)})
(folder/"results.json").write_text(json.dumps({"passed":True,"checks":checks,"worker_sha256":worker.sha(ROOT/"scripts/workers/audio_extract.py"),"engine":result["engine"],"source_hashes":original_hashes,"limitations":["Original analytic/software fixtures; no human recording, microphone calibration or physical timing qualification."]},indent=2))
print(json.dumps({"passed":len(checks),"output":str(folder)}))
