"""Opt-in maximum-frame/source stress; synthetic observations, no inference.

Creates about 2 GiB outside the repo. 'native-width' has 58 metrics; 'index-limit'
has the accepted 128-metric/name maxima and must explicitly refuse at 256 MiB.
"""
import argparse
import ctypes
from decimal import Decimal
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import time
from types import SimpleNamespace

ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location("vision_limits",ROOT/"scripts/workers/vision_explorer.py")
v=importlib.util.module_from_spec(spec);spec.loader.exec_module(v)


class Memory(ctypes.Structure):
    _fields_=[("cb",ctypes.c_ulong),("PageFaultCount",ctypes.c_ulong)]+[(name,ctypes.c_size_t) for name in
        ("PeakWorkingSetSize","WorkingSetSize","QuotaPeakPagedPoolUsage","QuotaPagedPoolUsage","QuotaPeakNonPagedPoolUsage","QuotaNonPagedPoolUsage","PagefileUsage","PeakPagefileUsage","PrivateUsage")]
def memory(process):
    api=ctypes.WinDLL("psapi",use_last_error=True);api.GetProcessMemoryInfo.argtypes=[ctypes.c_void_p,ctypes.POINTER(Memory),ctypes.c_ulong];api.GetProcessMemoryInfo.restype=ctypes.c_int
    value=Memory();value.cb=ctypes.sizeof(value)
    if not api.GetProcessMemoryInfo(int(process._handle),ctypes.byref(value),value.cb):raise OSError(ctypes.get_last_error())
    return value.PeakWorkingSetSize,value.PeakPagefileUsage


def main():
    p=argparse.ArgumentParser();p.add_argument("--folder",required=True);p.add_argument("--case",choices=["native-width","index-limit"],required=True);p.add_argument("--reuse-request");args=p.parse_args()
    folder=Path(args.folder).resolve();assert not folder.exists();folder.mkdir(parents=True)
    count=36000;point={"x":.5,"y":.25,"z":-.125,"visibility":1,"presence":1};large=args.case=="index-limit"
    names=[("native"+str(i).zfill(3)+"X"*87 if large else "native"+str(i).zfill(3)) for i in range(122 if large else 52)]
    assert all(len(n)<=96 for n in names)
    face={"count":1,"count_is_lower_bound":False,"state":"single","valid":True,"landmarks":[point]*478,
          "geometry":{"outer_eye_distance_image_width":.5,"lip_separation_image_width":.125},"blendshapes":dict.fromkeys(names,.25)}
    pose={"count":1,"count_is_lower_bound":False,"state":"single","valid":True,"landmarks":[point]*33,
          "landmark_valid_mask":[True]*33,"geometry":{"left_elbow_angle_deg":90.0,"right_elbow_angle_deg":90.0}}
    hands={"count":2,"count_is_lower_bound":True,"state":"detected","valid":True,"hands":[
        {"frame_index":i,"handedness":label,"handedness_score":.99,"valid":True,"summary_valid":True,"landmarks":[point]*21,
         "geometry":{"thumb_index_distance_over_palm":.5}} for i,label in enumerate(("Left","Right"))]}
    tail=json.dumps({"face":face,"pose":pose,"hands":hands},separators=(",",":"))[1:]
    maximum_line=v.MAX_SOURCE//count-256;padding=max(0,min(115,(maximum_line-len(tail))//553))
    tail=tail.replace('"z":-0.125','"z":-0.125'+'0'*padding).encode();source=folder/"complete.jsonl";origin=Decimal("9007199254740992.0000")
    start=time.monotonic()
    if args.reuse_request:
        previous=json.loads(Path(args.reuse_request).read_bytes());source=Path(previous["artifact_path"])
        assert v.descriptor(source)==previous["artifact"]
    else:
        with source.open("wb") as stream:
            for i in range(count):
                relative=Decimal(i)/100
                prefix=('{"frame_index":'+str(i)+',"source_pts_s":"'+str(origin+relative)+'","time_s":'+format(relative,".2f")+',"model_timestamp_ms":'+str(i*10)+',').encode()
                stream.write(prefix+tail+b"\n")
    assert source.stat().st_size<=v.MAX_SOURCE and source.stat().st_size>v.MAX_SOURCE*.97
    binding=v.encoded({"origin":"independent_maximum_synthetic_artifact","case":args.case}).decode()
    request={"schema":"brohn-vision-explorer-request/1.0","operation":"build","artifact_path":str(source),"artifact":v.descriptor(source),"index_path":str(folder/"index.sqlite"),
        "binding_json":binding,"binding_sha256":v.sha(binding.encode()),"parameters":{"channels":["face","pose","hands"],"source_pts_origin_s":str(origin),"max_support_gap_s":.25,"start_s":0,"end_s":359.99,"width":640,"height":480},
        "quality":{"source_frames":count,"analysed_frames":count,"channels":{c:{"valid_frames":count,"states":{s:count}} for c,s in (("face","single"),("pose","single"),("hands","detected"))}},
        "engine":{"name":"independent_adversarial_artifact_oracle","version":"1"}}
    (folder/"request.json").write_bytes(v.encoded(request));output=folder/"worker-result.json"
    memory_path=folder/"actual-runtime-memory.json"
    child=subprocess.Popen([sys.executable,"-B",str(Path(__file__).resolve()),"--measure-worker",str(folder/"request.json"),str(output),str(memory_path)],creationflags=subprocess.CREATE_NO_WINDOW)
    child.wait(timeout=1200)
    observed_memory=json.loads(memory_path.read_bytes());peak_rss=observed_memory["peak_working_set_bytes"];peak_commit=observed_memory["peak_commit_bytes"]
    result=json.loads(output.read_bytes());checks=[]
    assert peak_rss<192*1024**2 and peak_commit<192*1024**2,(peak_rss,peak_commit);checks.append("Actual peak working set and commit below 192 MiB on 36,000 near-2-GiB complete frames")
    if large:
        assert child.returncode==1 and "256 MiB" in result["error"]["message"],result
        assert not Path(request["index_path"]).exists() and not Path(request["index_path"]+".building").exists();checks.append("128 maximum-length metrics explicitly refuse at the 256-MiB index cap with no partial index")
    else:
        assert child.returncode==0 and result["manifest"]["frames"]==count and len(result["manifest"]["metrics"])==58,result
        q={"index_path":request["index_path"],"index":result["index"],"binding_sha256":request["binding_sha256"],"metric":"face.blendshape.native000","channel":"face"}
        plot=v.plot(q);assert plot["support"]["frames"]==count and plot["support"]["displayed_points"]<=2000 and len(v.encoded(plot))<=v.MAX_RESPONSE
        detail=v.detail(dict(q,artifact_path=str(source),frame_index=count-1));assert detail["frame"]["frame_index"]==count-1 and len(v.encoded(detail))<=v.MAX_RESPONSE
        checks.extend(["58-metric complete index remains within 256 MiB","Complete plot and final-frame detail stay within point/response budgets"])
    receipt={"checks":checks,"case":args.case,"frames":count,"metrics":128 if large else 58,"source_bytes":source.stat().st_size,"peak_working_set_bytes":peak_rss,"peak_commit_bytes":peak_commit,
        "elapsed_seconds":time.monotonic()-start,"worker_exit":child.returncode,"index_bytes":result.get("index",{}).get("bytes"),"source_hash":request["artifact"]["sha256"],"worker_sha256":v.digest(ROOT/"scripts/workers/vision_explorer.py")}
    (folder/"limits-evidence.json").write_bytes(v.encoded(receipt));print(json.dumps(receipt,indent=2))


if __name__=="__main__":
    if len(sys.argv)>1 and sys.argv[1]=="--measure-worker":
        request_path,output_path,memory_path=sys.argv[2:]
        sys.argv=["vision_explorer.py","--request",request_path,"--output",output_path]
        code=v.main()
        # Ask the actual interpreter about itself, not the Windows venv launcher.
        rss,commit=memory(SimpleNamespace(_handle=-1))
        Path(memory_path).write_text(json.dumps({"peak_working_set_bytes":rss,"peak_commit_bytes":commit,"scope":"actual Python interpreter, Win32 lifetime peaks"}))
        sys.exit(code)
    main()
