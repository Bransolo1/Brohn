"""Independent distinct-pixel/nonuniform-PTS extraction oracle; no model inference."""
import copy
from decimal import Decimal
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]; sys.path.insert(0, str(ROOT / "scripts/workers"))
import vision_frame as f
import vision_explorer as v


def fixture(folder, selected=(0,1,2,3), shift=Decimal(0), decoder_mismatch=False, orientation="encoded pixels, no autorotation"):
    width, height = 32, 24
    pixels = [bytes((x*7+i*31 if c==0 else y*9+i*17 if c==1 else (x+y)*3+i*23) % 256
                    for y in range(height) for x in range(width) for c in range(3)) for i in range(4)]
    video = folder / "nonuniform.mkv"; ffmpeg = shutil.which("ffmpeg"); ffprobe = shutil.which("ffprobe")
    command = [ffmpeg,"-v","error","-nostdin","-f","rawvideo","-pix_fmt","rgb24","-s","32x24","-framerate","1000","-i","pipe:0",
               "-vf","setpts=if(eq(N\\,0)\\,2/TB\\,if(eq(N\\,1)\\,2.1/TB\\,if(eq(N\\,2)\\,2.35/TB\\,2.9/TB)))",
               "-frames:v","4","-c:v","ffv1","-pix_fmt","bgr0","-fps_mode","passthrough",str(video)]
    subprocess.run(command,input=b"".join(pixels),capture_output=True,check=True,timeout=30,creationflags=subprocess.CREATE_NO_WINDOW)
    source = v.descriptor(video); pts = ["2.000000","2.100000","2.350000","2.900000"]
    # Explicit expected values are independent of the production metadata reader.
    observed = json.loads(subprocess.run([ffprobe,"-v","error","-show_frames","-show_entries","frame=pts_time","-of","json",str(video)],capture_output=True,check=True).stdout)
    assert [x["pts_time"] for x in observed["frames"]] == pts
    artifact = folder / "complete.jsonl"
    rows = [{"frame_index": i, "source_pts_s": str(Decimal(pts[i])+shift), "time_s": float(Decimal(pts[i])-Decimal(2)),
             "model_timestamp_ms": int((Decimal(pts[i])-Decimal(2))*1000),
             "face": {"count": 0,"count_is_lower_bound":False,"valid":False,"state":"absent","landmarks":None,"geometry":None,"blendshapes":None}} for i in selected]
    artifact.write_bytes(b"".join(v.encoded(row)+b"\n" for row in rows))
    binding = v.encoded({"original_source":{"hash":source["sha256"],"size":source["bytes"]},"qualification":"distinct synthetic pixels"}).decode()
    parameters = {"channels":["face"],"source_pts_origin_s":str(Decimal(pts[0])+shift),"source_time_base":"1/1000","max_support_gap_s":.25,
                  "start_s":0,"end_s":.9,"width":width,"height":height,"orientation":orientation}
    engine = {name: subprocess.run([binary,"-version"],capture_output=True,text=True,check=True).stdout.splitlines()[0] for name,binary in (("ffmpeg",ffmpeg),("ffprobe",ffprobe))}
    if decoder_mismatch: engine["ffmpeg"] += " different saved build"
    index_request = {"artifact_path":str(artifact),"artifact":v.descriptor(artifact),"index_path":str(folder/"index.sqlite"),
                     "binding_json":binding,"binding_sha256":v.sha(binding.encode()),"parameters":parameters,"engine":engine,
                     "quality":{"source_frames":4,"analysed_frames":len(rows),"channels":{"face":{"valid_frames":0,"states":{"absent":len(rows)}}}}}
    index = v.build(index_request); output = folder / "frames"; output.mkdir()
    return {"schema":"brohn-vision-frame-request/1.0","source_path":str(video),"source":source,"index_path":index_request["index_path"],"index":index["index"],
            "binding_sha256":index_request["binding_sha256"],"artifact_path":str(artifact),"frame_index":0,"output_directory":str(output)}, pixels


class FrameTests(unittest.TestCase):
    def setUp(self): self.tmp=tempfile.TemporaryDirectory(); self.folder=Path(self.tmp.name)
    def tearDown(self): self.tmp.cleanup()
    def test_first_intermediate_and_final_exact_distinct_pixels_nonuniform_pts(self):
        request,pixels=fixture(self.folder); original=Path(request["source_path"]).read_bytes()
        for index,pts in ((0,"2.000000"),(1,"2.100000"),(3,"2.900000")):
            result=f.extract(dict(request,frame_index=index)); image=Path(result["image"]["path"])
            with Image.open(image) as saved: self.assertEqual(saved.convert("RGB").tobytes(),pixels[index])
            self.assertEqual(result["frame"]["source_pts_s"],pts); self.assertEqual(result["extraction"]["decoded_frames_to_selection"],index+1)
            self.assertEqual(result["extraction"]["rgb24_sha256"],hashlib.sha256(pixels[index]).hexdigest())
        self.assertEqual(Path(request["source_path"]).read_bytes(),original)
    def test_selected_interval_uses_original_frame_index_not_analysed_ordinal(self):
        request,pixels=fixture(self.folder,selected=(1,2)); result=f.extract(dict(request,frame_index=2))
        self.assertEqual(result["frame"]["ordinal"],1); self.assertEqual(result["frame"]["frame_index"],2)
        with Image.open(result["image"]["path"]) as image: self.assertEqual(image.tobytes(),pixels[2])
        with self.assertRaisesRegex(v.InputError,"not analysed"): f.extract(dict(request,frame_index=0))
    def test_saved_pts_shift_refuses_instead_of_using_frame_rate(self):
        request,_=fixture(self.folder,shift=Decimal(".001"))
        with self.assertRaisesRegex(v.InputError,"index/PTS/model"): f.extract(request)
        self.assertEqual(list(Path(request["output_directory"]).iterdir()),[])
    def test_saved_decoder_mismatch_refused(self):
        request,_=fixture(self.folder,decoder_mismatch=True)
        with self.assertRaisesRegex(v.InputError,"compatible FFmpeg"): f.extract(request)
    def test_orientation_mismatch_refused(self):
        request,_=fixture(self.folder,orientation="mirrored view")
        with self.assertRaisesRegex(v.InputError,"orientation"): f.extract(request)
    def test_wrong_original_source_identity_refused(self):
        request,_=fixture(self.folder); request["source"]["sha256"]="b"*64
        with self.assertRaisesRegex(v.InputError,"video changed"): f.extract(request)
    def test_wrong_index_digest_refused(self):
        request,_=fixture(self.folder); request["index"]["sha256"]="b"*64
        with self.assertRaisesRegex(v.InputError,"index bytes changed"): f.extract(request)
    def test_other_video_cannot_use_original_observation_index(self):
        request,_=fixture(self.folder); replacement=self.folder/"other"; replacement.mkdir(); other,_=fixture(replacement)
        # Add harmless trailing container bytes: decodable image content can be
        # identical while source identity differs, and it still must be refused.
        with Path(other["source_path"]).open("ab") as stream: stream.write(b"different original container")
        request.update(source_path=other["source_path"],source=v.descriptor(Path(other["source_path"])))
        with self.assertRaisesRegex(v.InputError,"different source identities"): f.extract(request)


if __name__=="__main__": unittest.main()
