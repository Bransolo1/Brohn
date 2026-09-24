"""Independent hand-authored saved EDA values; never calls the scientific scorer."""
import copy
import csv
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts/workers"))
import eda_continuous_review as reader
import physiology_artifacts as tables


def fixture(folder, change=None, empty=False, stress=False):
    folder = Path(folder); folder.mkdir(parents=True, exist_ok=True)
    fs = 10
    count = 50201 if stress else 601
    # Exact fixture phasic endpoints differ deliberately from unrelated clean/tonic values.
    rows = [dict(time_s=i/fs, source_sample_index=1000+i, clean_us=4+i/10000,
                 tonic_us=3+i/20000, phasic_us=(i % 17)/10-.8, retained=100 <= i < count-100) for i in range(count)]
    endpoints = [(103+10*j,105+10*j,107+10*j) for j in range(5000)] if stress else [(None, 110, 120), (200, 210, 230), (480, 490, None)]
    events = []
    if not empty:
        for onset, peak, recovery in endpoints:
            rows[peak]["phasic_us"] = 1.25
            if onset is not None: rows[onset]["phasic_us"] = -.25
            if recovery is not None: rows[recovery]["phasic_us"] = .375
            events.append(dict(type="scr", time_s=peak/fs, peak_sample=peak, source_peak_sample=1000+peak,
                onset_time_s=None if onset is None else onset/fs, recovery_time_s=None if recovery is None else recovery/fs,
                amplitude_us=None if onset is None else 1.5, peak_height_us=1.25, rise_time_s=None if onset is None else (peak-onset)/fs,
                recovery_time_from_peak_s=None if recovery is None else (recovery-peak)/fs, recovery_fraction=.5,
                missing_reason=None if onset is not None and recovery is not None else "onset_or_recovery_outside_retained_support"))
    if change: change(rows, events)
    original = folder / "original-conductance.csv"
    with original.open("w", encoding="utf-8", newline="") as stream:
        w=csv.writer(stream);w.writerow(["time","conductance"]);w.writerows((r["time_s"],r["clean_us"]/1e6) for r in rows)
    identity=dict(recording_id="recording-1",segment_id="recording-1-segment-1",channel="conductance",group=dict(participant_id="synthetic-person"))
    parameters=dict(recipe="eda-neurokit-highpass/1.0",phasic_cutoff_hz=.05,amplitude_min_relative_prominence=.1,edge_exclusion_s=10,
        cleaner="neurokit",clean_lowpass_hz=3,clean_order=4,decomposition="highpass",recovery_fraction=.5,
        threshold_definition="candidate_prominence_relative_to_maximum_prominence",no_missing_value_imputation=True)
    recording=dict(**identity,status="computed",source_time_origin="1750000000000000000",source_row_start=1000,source_row_end_exclusive=1000+count,
        samples=count,sampling_rate=fs,start_time_s=0,end_time_s=(count-1)/fs,unit="uS",source_unit="S",scale_factor=1e6,
        retained_samples=count-200,retained_duration_s=(count-200)/fs,filter_edge_samples=200)
    denominator=sum(e["amplitude_us"] is not None for e in events)
    features=[dict(**identity,name="tonic_mean",value=3.015,unit="uS"),dict(**identity,name="scr_count",value=len(events),unit="count"),
        dict(**identity,name="scr_rate",value=len(events)*60/((count-200)/fs),unit="count/min"),
        *[dict(**identity,name=k,value=1.5 if denominator else None,denominator=denominator,unit="uS") for k in ("scr_amplitude_mean","scr_amplitude_median")]]
    support=dict(source=recording,method=parameters,retained_support=dict(retained_samples=count-200,retained_duration_s=(count-200)/fs,filter_edge_samples=200),raw_source_omitted=True)
    coordinate=dict(axis="time",reference="seconds relative to original recording start; no source timestamp rebasing",source_time_origin=recording["source_time_origin"],source_time_unit="s")
    provenance=dict(source_sha256=tables.digest_file(original),engine=dict(name="Independent saved-value construction",worker_sha256=tables.digest_file(Path(__file__))),operation="physiology",origin="sample",parameters=parameters)
    def col(name,kind,unit,nullable=False,role="measure"):return dict(name=name,type=kind,unit=unit,nullable=nullable,role=role)
    columns=[col("time_s","float64","s",role="coordinate"),col("source_sample_index","integer","sample_index",role="index"),
        *[col(k,"float64","uS") for k in reader.COMPONENTS],col("retained","boolean",None,role="support")]
    series=tables.TableWriter(folder,"physiology-series",provenance,preview_limit=0)
    series.write_table("eda-samples",identity,columns,coordinate,support,rows,len(rows))
    series.write_table("unselected-channel",{**identity,"channel":"other"},columns,coordinate,support,rows[:3],3)
    a=series.finish()
    columns=[col("type","string",None),col("time_s","float64","s"),col("peak_sample","integer","segment_sample_index"),col("source_peak_sample","integer","sample_index"),
        *[col(k,"float64","s",True) for k in ("onset_time_s","recovery_time_s","rise_time_s","recovery_time_from_peak_s")],
        *[col(k,"float64","uS",True) for k in ("amplitude_us","peak_height_us")],col("recovery_fraction","float64","proportion"),col("missing_reason","string",None,True)]
    writer=tables.TableWriter(folder,"physiology-events",provenance,preview_limit=0)
    writer.write_table("eda-candidates",identity,columns,{**coordinate,"axis":"event"},support,events,len(events))
    b=writer.finish();export=folder/"exports";export.mkdir()
    request=dict(schema="brohn-eda-continuous-review-request/1.0",binding=dict(origin="sample",report_id="original-continuous-eda"),recording=recording,parameters=parameters,features=features,
        selection={**{k:identity[k] for k in reader.IDENTITY},"start_s":"0","end_s":str((count-1)/fs)},original_source=dict(path=str(original),hash=tables.digest_file(original),bytes=original.stat().st_size),
        sealed_objects=[],artifacts=[a,b],export_directory=str(export))
    return request,rows,events


class Review(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(prefix="brohn-eda-continuous-reader-");self.root=Path(self.temp.name)
        self.request,self.rows,self.events=fixture(self.root)
    def tearDown(self):self.temp.cleanup()
    def test_every_processed_value_and_source_index_is_exact(self):
        r=reader.review(self.request)
        with (self.root/"exports/eda-samples.csv").open(encoding="utf-8") as stream:rows=list(csv.DictReader(stream))
        self.assertEqual(len(rows),601)
        for actual,expected in zip(rows,self.rows):
            for key in (*reader.COMPONENTS,"time_s","source_sample_index"):self.assertEqual(float(actual[key]),expected[key])
            self.assertEqual(actual["retained"],str(expected["retained"]).lower())
        self.assertEqual(r["counts"]["complete_sample_artifact_rows"],604)
        self.assertEqual(r["counts"]["segment_amplitude_available"],2)
        self.assertFalse(r["raw_available"])
        self.assertEqual(r["features"],self.request["features"])
        for output in r["exports"]:self.assertEqual(tables.digest_file(self.root/"exports"/output["name"]),output["hash"])
    def test_exact_nullable_markers_independent_of_display_envelope(self):
        r=reader.review(self.request)
        self.assertEqual([(m["kind"],m["source_sample_index"]) for m in r["markers"]],[("peak",1110),("recovery",1120),("onset",1200),("peak",1210),("recovery",1230),("onset",1480),("peak",1490)])
        self.assertEqual([{k:c[k] for k in reader.EVENT_FIELDS} for c in r["candidates"]],self.events)
        for m in r["markers"]:self.assertEqual(m["phasic_us"],self.rows[m["source_sample_index"]-1000]["phasic_us"])
        self.assertIsNone(r["candidates"][0]["amplitude_us"])
        self.assertIsNone(r["candidates"][-1]["recovery_time_s"])
    def test_preview_points_are_actual_samples_and_preserve_edges(self):
        r=reader.review(self.request)
        for component,groups in r["series"].items():
            self.assertEqual([g["retained"] for g in groups],[False,True,False])
            self.assertLessEqual(sum(len(g["points"]) for g in groups),2000)
            for g in groups:
                for p in g["points"]:self.assertEqual(p["value"],self.rows[p["source_sample_index"]-1000][component])
    def test_decimal_boundary_keeps_original_candidate_without_rescoring(self):
        self.request["selection"].update(start_s="20.100000000000000001",end_s="20.2")
        r=reader.review(self.request);self.assertEqual(r["counts"]["selected_samples"],1);self.assertEqual(r["rows"][0]["time_s"],20.2)
        self.assertEqual(r["candidates"][0]["time_s"],21);self.assertEqual(r["candidates"][0]["amplitude_us"],1.5)
        self.assertFalse(any(m["in_view"] for m in r["markers"]));self.assertEqual(r["features"],self.request["features"])
    def test_empty_outside_segment_has_no_fabricated_samples(self):
        self.request["selection"].update(start_s="61",end_s="62")
        r=reader.review(self.request);self.assertEqual(r["status"],"no_processed_samples");self.assertEqual(r["candidates"],[])
    def test_zero_candidates_keep_conditional_amplitude_unavailable(self):
        q,_,_=fixture(self.root/"zero",empty=True);r=reader.review(q)
        self.assertEqual(r["counts"]["segment_candidates"],0);self.assertEqual(r["markers"],[])
        self.assertIsNone(next(f for f in r["features"] if f["name"]=="scr_amplitude_mean")["value"])
    def test_peak_or_endpoint_substitution_refused(self):
        changes=[lambda rows,e:e[1].update(source_peak_sample=1211),lambda rows,e:e[1].update(onset_time_s=20.01),
            lambda rows,e:e[1].update(peak_height_us=2),lambda rows,e:e[0].update(missing_reason=None),lambda rows,e:e[1].update(rise_time_s=2),
            lambda rows,e:e[1].update(recovery_time_from_peak_s=3),lambda rows,e:rows[210].update(retained=False),lambda rows,e:rows[210].update(time_s=21.06)]
        for index,change in enumerate(changes):
            with self.subTest(index=index):
                q,_,_=fixture(self.root/f"bad-{index}",change=change)
                with self.assertRaises(tables.ArtifactError):reader.review(q)
    def test_original_bytes_and_offwindow_artifact_hash_verified(self):
        self.request["selection"].update(start_s="20",end_s="21")
        path=Path(self.request["artifacts"][0]["path"])
        with path.open("ab") as stream:stream.write(b" ")
        with self.assertRaises(tables.ArtifactError):reader.review(self.request)
    def test_source_clock_and_relative_threshold_may_not_be_reinterpreted(self):
        self.request["parameters"]["threshold_definition"]="absolute_uS"
        with self.assertRaises(tables.ArtifactError):reader.review(self.request)
    def test_original_source_mutation_refused(self):
        Path(self.request["original_source"]["path"]).write_text("changed")
        with self.assertRaises(tables.ArtifactError):reader.review(self.request)
    def test_all_csv_exports_have_full_candidate_rows_and_missing_cells(self):
        r=reader.review(self.request)
        with (self.root/"exports/eda-candidates.csv").open(encoding="utf-8") as stream:rows=list(csv.DictReader(stream))
        self.assertEqual(len(rows),3);self.assertEqual(rows[0]["onset_time_s"],"");self.assertEqual(rows[-1]["recovery_time_s"],"")
        self.assertEqual(r["exports"][2]["rows"],7)
    def test_cli_result_does_not_publish_paths(self):
        request=self.root/"request.json";out=self.root/"output.json";request.write_text(json.dumps(self.request))
        proc=subprocess.run([sys.executable,str(ROOT/"scripts/workers/eda_continuous_review.py"),"--request",str(request),"--output",str(out)],capture_output=True)
        self.assertEqual(proc.returncode,0,proc.stderr);result=out.read_text();self.assertNotIn(str(self.root).replace("\\","\\\\"),result)
    def test_sample_and_candidate_bounds_refuse_instead_of_truncating(self):
        for name,limit in (("MAX_SAMPLES",600),("MAX_CANDIDATES",2)):
            previous=getattr(reader,name)
            try:
                setattr(reader,name,limit)
                with self.assertRaises(tables.ArtifactError):reader.review(self.request)
                self.assertEqual(list((self.root/"exports").iterdir()),[])
            finally:setattr(reader,name,previous)
    def test_no_private_report_envelope_can_be_substituted(self):
        retained=self.root/"retained.json";retained.write_text('{"exact":"report"}')
        self.request["sealed_objects"]=[dict(path=str(retained),hash=tables.digest_file(retained),bytes=retained.stat().st_size)]
        retained.write_text('{"other":"report"}')
        with self.assertRaises(tables.ArtifactError):reader.review(self.request)


if __name__=="__main__":
    if len(sys.argv)>1 and sys.argv[1]=="--fixture":
        q,_,_=fixture(Path(sys.argv[2]),stress="--stress" in sys.argv);Path(sys.argv[2],"fixture.json").write_text(json.dumps(q));sys.exit(0)
    unittest.main()
