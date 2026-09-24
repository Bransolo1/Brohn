"""Hand-written saved-value oracles, separate from the EMG scientific scorer."""
import copy
import csv
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts/workers"))
import emg_review as reader
import physiology_artifacts as tables


def fixture(folder, change=None, legacy=False, threshold=.5, empty=False, event_clock="s"):
    folder = Path(folder); folder.mkdir(parents=True, exist_ok=True)
    fs = 500
    bounds = [] if empty or threshold is None else [(125, 500), (1000, 1200), (9500, 9875)]
    rows = [dict(time_s=i/fs, source_sample_index=i+1000, raw_uv=(-1 if i % 2 else 1)*(1+(i % 7)/10),
                 clean_uv=(-1 if i % 2 else 1)*.25, rms_uv=1.0 if any(a <= i < b for a,b in bounds) else .1,
                 retained=125 <= i < 9875) for i in range(10001)]
    bursts = [dict(type="emg_threshold_burst", time_s=rows[a]["time_s"], end_time_s=rows[b-1]["time_s"]+1/fs,
                   duration_s=(b-a)/fs, peak_rms_uv=1.0, boundary_truncated=a==125 or b==9875) for a,b in bounds]
    if change: change(rows, bursts)
    original = folder / "original-mv.csv"
    with original.open("w", encoding="utf-8", newline="") as stream:
        w=csv.writer(stream);w.writerow(["time", "voltage"]);w.writerows((r["time_s"],r["raw_uv"]/1000) for r in rows)
    group=dict(participant_id="synthetic-person",session_id="synthetic-session")
    identity=dict(recording_id="recording-1",segment_id="recording-1-segment-1",channel="voltage",group=group)
    parameters=dict(recipe="emg-butterworth-rms/1.0", highpass_hz=20, lowpass_hz=200, rms_window_s=.05, rms_window_samples=25,
        edge_exclusion_s=.25, burst_threshold_uv=threshold, burst_min_duration_s=.1, filter="butterworth_sos_zero_phase",filter_order=4,
        envelope="centered_window_root_mean_square",mvc_normalization=False)
    recording=dict(**identity,status="computed",source_time_origin="1750000000000000000",source_row_start=1000,
        source_row_end_exclusive=11001,samples=10001,sampling_rate=fs,start_time_s=0,end_time_s=20,unit="uV",source_unit="mV",scale_factor=1000,
        retained_samples=9750,retained_duration_s=19.5,filter_edge_samples=250)
    features=[dict(**identity,name="emg_rms",value=.25,unit="uV")]
    if threshold is not None: features += [dict(**identity,name="emg_burst_count",value=len(bursts),unit="count"),
        dict(**identity,name="emg_accepted_burst_time_fraction",value=sum(b["duration_s"] for b in bursts)/19.5,unit="proportion")]
    support=dict(source=recording,method=parameters,retained_support=dict(retained_samples=9750),raw_source_omitted=legacy)
    if not legacy: support["input_waveform"]=dict(column="raw_uv",unit="uV",definition="unit-converted source samples before cleaning; original source bytes remain authoritative",detection_basis="rms_uv")
    coordinate=dict(axis="time",reference="seconds relative to original recording start; no source timestamp rebasing",
        source_time_origin=recording["source_time_origin"],source_time_unit="s")
    provenance=dict(source_sha256=tables.digest_file(original),engine=dict(name="Independent saved-value construction",worker_sha256=tables.digest_file(Path(__file__))),
        operation="physiology",origin="sample",parameters=parameters)
    def col(name,kind,unit,role="measure"):return dict(name=name,type=kind,unit=unit,nullable=False,role=role)
    sample_fields=[col("time_s","float64","s","coordinate"),col("source_sample_index","integer","sample_index","index"),
        *[col(k,"float64","uV") for k in (["clean_uv","rms_uv"] if legacy else ["raw_uv","clean_uv","rms_uv"])],col("retained","boolean",None,"support")]
    kept=[{c["name"]:r[c["name"]] for c in sample_fields} for r in rows]
    series=tables.TableWriter(folder,"physiology-series",provenance,preview_limit=0)
    series.write_table("emg-samples",identity,sample_fields,coordinate,support,kept,len(kept))
    series.write_table("other-channel",{**identity,"channel":"different"},sample_fields,coordinate,support,kept[:3],3)
    a=series.finish()
    event_fields=[col("type","string",None,"label"),*[col(k,"float64","s") for k in ("time_s","end_time_s","duration_s")],
                  col("peak_rms_uv","float64","uV"),col("boundary_truncated","boolean",None,"support")]
    events=tables.TableWriter(folder,"physiology-events",provenance,preview_limit=0)
    events.write_table("emg-bursts",identity,event_fields,{**coordinate,"axis":"event","source_time_unit":event_clock},
        {**support,"end_time_policy":reader.END_POLICY},bursts,len(bursts))
    b=events.finish();export=folder/"exports";export.mkdir()
    request=dict(schema="brohn-emg-review-request/1.0",binding=dict(origin="sample",report_id="original-emg"),recording=recording,parameters=parameters,features=features,
        selection={**{k:identity[k] for k in reader.IDENTITY},"start_s":"0","end_s":"20"},original_source=dict(path=str(original),hash=tables.digest_file(original),bytes=original.stat().st_size),
        sealed_objects=[],artifacts=[a,b],export_directory=str(export))
    return request,rows,bursts


class Review(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(prefix="brohn-emg-reader-");self.root=Path(self.temp.name)
        self.request,self.rows,self.bursts=fixture(self.root)
    def tearDown(self):self.temp.cleanup()
    def run_review(self):return reader.review(self.request)
    def test_complete_exact_input_clean_rms_indices_and_all_bursts(self):
        result=self.run_review()
        with (self.root/"exports/emg-samples.csv").open(encoding="utf-8") as stream:rows=list(csv.DictReader(stream))
        self.assertEqual(len(rows),10001)
        for i,row in enumerate(rows):
            for key in ("time_s","raw_uv","clean_uv","rms_uv","source_sample_index"):self.assertEqual(float(row[key]),self.rows[i][key])
            self.assertEqual(row["retained"],str(self.rows[i]["retained"]).lower())
        self.assertEqual(result["counts"]["complete_sample_artifact_rows"],10004)
        self.assertEqual(result["counts"]["selected_bursts"],3)
        self.assertTrue(result["raw_available"])
        self.assertEqual([{k:b[k] for k in reader.EVENT_FIELDS} for b in result["bursts"]],self.bursts)
        for output in result["exports"]:self.assertEqual(tables.digest_file(self.root/"exports"/output["name"]),output["hash"])
    def test_three_components_use_real_points_and_distinct_support(self):
        result=self.run_review()
        for key,groups in result["series"].items():
            self.assertEqual([g["retained"] for g in groups],[False,True,False])
            self.assertLessEqual(sum(len(g["points"]) for g in groups),2000)
            for g in groups:
                for p in g["points"]:self.assertEqual(p["value"],self.rows[p["source_sample_index"]-1000][key])
    def test_exclusive_end_is_boundary_not_invented_sample(self):
        result=self.run_review()
        self.assertEqual([m["kind"] for m in result["markers"][:3]],["onset","peak_rms","end_boundary"])
        for m in result["markers"]:
            if m["kind"]=="end_boundary":
                self.assertIsNone(m["source_sample_index"]);self.assertIsNone(m["rms_uv"])
                self.assertAlmostEqual(m["time_s"],m["anchor_time_s"]+.002,places=12)
            else:self.assertEqual(m["rms_uv"],self.rows[m["source_sample_index"]-1000]["rms_uv"])
    def test_partial_window_keeps_original_burst_and_outside_markers(self):
        self.request["selection"].update(start_s="2.100000000000000001",end_s="2.2")
        result=self.run_review()
        self.assertEqual(result["counts"]["selected_samples"],50)
        self.assertEqual(result["bursts"][0]["duration_s"],.4)
        self.assertFalse(any(m["in_view"] for m in result["markers"]))
        self.assertGreater(result["rows"][0]["time_s"],2.1)
    def test_exact_end_does_not_reinclude_half_open_burst(self):
        self.request["selection"].update(start_s="1",end_s="1.1")
        result=self.run_review();self.assertEqual(result["bursts"],[])
    def test_no_threshold_is_distinct_from_configured_zero_bursts(self):
        for name,threshold in (("absent",None),("zero",.5)):
            request,_,_=fixture(self.root/name,threshold=threshold,empty=True);result=reader.review(request)
            self.assertEqual(result["counts"]["selected_bursts"],0)
            self.assertEqual(result["threshold_status"],"not_configured" if threshold is None else "configured")
            self.assertEqual(any(f["name"]=="emg_burst_count" for f in result["features"]),threshold is not None)
    def test_legacy_report_uses_clean_rms_without_fabricated_input(self):
        request,_,_=fixture(self.root/"legacy",legacy=True);result=reader.review(request)
        self.assertFalse(result["raw_available"]);self.assertEqual(set(result["series"]),{"clean_uv","rms_uv"})
        self.assertTrue(all(r["raw_uv"] is None for r in result["rows"]))
    def test_empty_window_is_not_zero_activation(self):
        self.request["selection"].update(start_s="21",end_s="22");result=self.run_review()
        self.assertEqual(result["status"],"no_processed_samples");self.assertEqual(result["bursts"],[])
        self.assertEqual(result["features"],self.request["features"])
    def test_original_retained_and_artifact_corruption_rejected(self):
        for kind in ("source","report","artifact"):
            request,_,_=fixture(self.root/kind)
            if kind=="report":
                f=self.root/kind/"report.json";f.write_text("original",encoding="utf-8")
                request["sealed_objects"]=[dict(path=str(f),hash=tables.digest_file(f),bytes=f.stat().st_size)]
            else:f=Path(request["original_source"]["path"] if kind=="source" else request["artifacts"][0]["path"])
            f.write_bytes(f.read_bytes()+b" ")
            with self.assertRaises(tables.ArtifactError):reader.review(request)
    def test_invalid_selection_parameters_origin_and_feature_source_rejected(self):
        for change in (lambda r:r["selection"].update(channel="other"),lambda r:r["parameters"].update(mvc_normalization=True),
            lambda r:r["parameters"].update(burst_threshold_uv=-1),lambda r:r["binding"].update(origin="live"),
            lambda r:r["features"][0].update(segment_id="other"),lambda r:r["selection"].update(start_s="NaN")):
            req=copy.deepcopy(self.request);change(req)
            with self.assertRaises(tables.ArtifactError):reader.review(req)
    def test_invalid_saved_burst_does_not_become_supported(self):
        for name,change in (("duration",lambda rs,bs:bs[0].update(duration_s=.8)),("peak",lambda rs,bs:bs[0].update(peak_rms_uv=2)),
            ("truncated",lambda rs,bs:bs[0].update(boundary_truncated=False)),("retained",lambda rs,bs:rs[200].update(retained=False)),
            ("threshold",lambda rs,bs:rs[200].update(rms_uv=.1)),("end",lambda rs,bs:bs[0].update(end_time_s=.999))):
            req,_,_=fixture(self.root/name,change=change)
            with self.assertRaises(tables.ArtifactError):reader.review(req)
    def test_gap_reset_clock_and_source_index_are_refused(self):
        for name,change in (("gap",lambda rs,bs:rs[300].update(time_s=1)),("reset",lambda rs,bs:rs[300].update(time_s=0)),
            ("index",lambda rs,bs:rs[300].update(source_sample_index=42))):
            req,_,_=fixture(self.root/name,change=change)
            with self.assertRaises(tables.ArtifactError):reader.review(req)
        req,_,_=fixture(self.root/"clock",event_clock="ms")
        with self.assertRaises(tables.ArtifactError):reader.review(req)
    def test_actual_cli_duplicate_fields_and_output_collision(self):
        req=self.root/"request.json";out=self.root/"result.json";req.write_text(json.dumps(self.request),encoding="utf-8")
        command=[sys.executable,str(ROOT/"scripts/workers/emg_review.py"),"--request",str(req),"--output",str(out)]
        child=subprocess.run(command,capture_output=True,text=True,timeout=30);self.assertEqual(child.returncode,0,child.stderr)
        saved=out.read_bytes();self.assertEqual(subprocess.run(command,capture_output=True,timeout=30).returncode,1);self.assertEqual(out.read_bytes(),saved)
        req.write_text('{"a":1,"a":2}',encoding="utf-8")
        with self.assertRaises(tables.ArtifactError):reader.load_request(req)


if __name__=="__main__":
    if len(sys.argv)==3 and sys.argv[1]=="--fixture":
        directory=Path(sys.argv[2]);request,_,_=fixture(directory)
        (directory/"fixture.json").write_text(json.dumps(request,ensure_ascii=True,indent=2),encoding="utf-8")
    elif len(sys.argv)==3 and sys.argv[1]=="--evidence":
        directory=Path(sys.argv[2]);directory.mkdir(parents=True,exist_ok=False);stream=io.StringIO()
        result=unittest.TextTestRunner(stream=stream,verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(Review))
        (directory/"test-output.txt").write_text(stream.getvalue(),encoding="utf-8")
        files=[Path(__file__),ROOT/"scripts/workers/emg_review.py",ROOT/"scripts/workers/physiology_artifacts.py"]
        (directory/"results.json").write_text(json.dumps(dict(status="passed" if result.wasSuccessful() else "failed",checks=result.testsRun,failures=len(result.failures),errors=len(result.errors),hashes={str(p.relative_to(ROOT)):tables.digest_file(p) for p in files}),indent=2),encoding="utf-8")
        print(stream.getvalue());sys.exit(0 if result.wasSuccessful() else 1)
    else:unittest.main()
