"""Independent exact-sample oracles for unreviewed cardiac marker displays."""
import argparse
import copy
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location("cardiac_view",ROOT/"scripts/workers/signal_preview.py")
worker=importlib.util.module_from_spec(spec);spec.loader.exec_module(worker)


def fixture(root,modality="ecg",n=9,indices=None,change=None):
    values=[0.,-2.,0.,3.,0.,2.,0.,-1.,0.] if n==9 else [float(i%7-3) for i in range(n)]
    indices=[1,3,5,7] if indices is None else indices
    event_type="r_peak" if modality=="ecg" else "systolic_pulse_peak"
    provenance=dict(source_sha256="a"*64,engine=dict(name="original_marker_fixture",worker_sha256="b"*64),
        operation="physiology",origin="sample",parameters={"recipe":"original-independent-marker-fixture/1"})
    identity=dict(recording_id="recording-1",segment_id="segment-1",channel=modality,group={"participant_id":"fictional-person"})
    coordinates=dict(axis="time",reference="original source-relative seconds",source_time_origin="99999999999999",source_time_unit="s")
    support=dict(source=dict(sampling_rate=1,source_row_start=500,source_row_end_exclusive=500+n),method={"recipe":"fixture/1"})
    column=worker.artifacts._column
    series=dict(table_id="series-1",identity=identity,
        specification=[column("time_s","float64","s",role="coordinate"),column("source_sample_index","integer","sample_index",role="index"),
            column("clean","float64","uV" if modality=="ecg" else "a.u.",True),column("retained","boolean",None,role="support")],
        coordinates=coordinates,support=support,
        arrays={"time_s":[10.+i for i in range(n)],"source_sample_index":list(range(500,500+n)),"clean":values,"retained":[True]*n})
    event_rows=[dict(type=event_type,time_s=10.+index,source_sample_index=500+index,
        previous_interval_ms=None if i==0 else 1000.*(index-indices[i-1]),previous_interval_plausible=None if i==0 else i!=2)
        for i,index in enumerate(indices)]
    events=dict(table_id="events-1",identity=copy.deepcopy(identity),
        specification=[column("type","string",None,role="label"),column("time_s","float64","s",role="coordinate"),
            column("source_sample_index","integer","sample_index",role="index"),column("previous_interval_ms","float64","ms",True),
            column("previous_interval_plausible","boolean",None,True,role="support")],
        coordinates={**coordinates,"axis":"event"},support=copy.deepcopy(support),rows=event_rows,row_count=len(event_rows))
    if change:change(series,events,provenance)
    with worker.artifacts.TableWriter(root,"physiology-series",provenance,chunk_rows=17) as writer:
        writer.write_arrays(**series);a=writer.finish()
    with worker.artifacts.TableWriter(root,"physiology-events",provenance,chunk_rows=17) as writer:
        writer.write_table(**events);b=writer.finish()
    return dict(schema="brohn-signal-preview-request/1.0",operation="signal_preview",artifact=a,
        verification_receipt=worker.artifacts.verify_manifest([a,b]),
        selection=dict(table_ids=["series-1"],recording_id="recording-1",channel=modality,value_column="clean",range=None),
        parameters=dict(max_bins=1),marker_overlay=dict(event_artifact=b,event_type=event_type))


class Markers(unittest.TestCase):
    def setUp(self):self.tmp=tempfile.TemporaryDirectory(prefix="brohn-cardiac-markers-");self.root=Path(self.tmp.name)
    def tearDown(self):self.tmp.cleanup()
    def run_fixture(self,**kwargs):return worker.run(fixture(self.root,**kwargs))
    def test_all_exact_markers_survive_one_bin_decimation(self):
        view=self.run_fixture();m=view["marker_overlay"]
        points=[p["source_sample_index"] for b in view["envelopes"] for p in b["points"]]
        self.assertNotIn(505,points);self.assertNotIn(507,points)
        self.assertEqual([x["source_sample_index"] for x in m["markers"]],[501,503,505,507])
        self.assertEqual([x["time_s"] for x in m["markers"]],[11,13,15,17])
        self.assertEqual([x["value"] for x in m["markers"]],[-2,3,2,-1])
        self.assertEqual(m["review_status"],"unreviewed_algorithm_detections")
        self.assertEqual(m["selected_marker_count"],4);self.assertNotIn('"path"',json.dumps(m))
    def test_ppg_keeps_pulse_identity_and_native_unit(self):
        m=self.run_fixture(modality="ppg")["marker_overlay"]
        self.assertEqual(m["event_type"],"systolic_pulse_peak");self.assertEqual(m["value_unit"],"a.u.")
    def test_inclusive_range_preserves_previous_interval_and_false(self):
        request=fixture(self.root);request["selection"]["range"]=[13,15]
        markers=worker.run(request)["marker_overlay"]["markers"]
        self.assertEqual(len(markers),2);self.assertEqual(markers[0]["previous_interval_ms"],2000)
        self.assertIs(markers[0]["previous_interval_plausible"],True)
        self.assertIs(markers[1]["previous_interval_plausible"],False)
        self.assertIsNone(worker.run(fixture(self.root))["marker_overlay"]["markers"][0]["previous_interval_ms"])
    def test_empty_range_has_zero_markers_not_zero_signal(self):
        request=fixture(self.root);request["selection"]["range"]=[30,40]
        view=worker.run(request);self.assertEqual(view["status"],"empty_range")
        self.assertEqual(view["marker_overlay"]["status"],"empty");self.assertEqual(view["marker_overlay"]["markers"],[])
    def test_declared_empty_event_table_is_available_as_empty(self):
        m=self.run_fixture(indices=[])["marker_overlay"]
        self.assertEqual(m["status"],"empty");self.assertEqual(m["selected_marker_count"],0)
    def test_excess_markers_are_counted_without_partial_display(self):
        m=self.run_fixture(n=5005,indices=list(range(1,5005,2)))["marker_overlay"]
        self.assertEqual(m["status"],"too_many_markers");self.assertEqual(m["selected_marker_count"],2502);self.assertEqual(m["markers"],[])
        self.assertEqual(m["alignment"],"not_checked_display_limit_exceeded")
    def test_exact_limit_retains_every_marker(self):
        m=self.run_fixture(n=4001,indices=list(range(1,4001,2)))["marker_overlay"]
        self.assertEqual(m["status"],"available");self.assertEqual(len(m["markers"]),2000)
    def test_timestamp_proximity_is_not_alignment(self):
        with self.assertRaisesRegex(worker.InputError,"exact retained"):
            self.run_fixture(change=lambda s,e,p:e["rows"][0].update(time_s=11.001))
    def test_missing_source_sample_is_not_interpolated(self):
        with self.assertRaisesRegex(worker.InputError,"sample bounds"):
            self.run_fixture(change=lambda s,e,p:e["rows"][-1].update(source_sample_index=999))
    def test_overlimit_out_of_bounds_samples_or_times_reject(self):
        for field,value in (("source_sample_index",999999),("time_s",999999.)):
            with self.subTest(field=field),self.assertRaisesRegex(worker.InputError,"sample bounds"):
                self.run_fixture(n=5005,indices=list(range(1,5005,2)),change=lambda s,e,p:e["rows"][-1].update({field:value}))
    def test_overlimit_in_bounds_time_mismatch_is_unchecked_then_rejects_when_narrowed(self):
        request=fixture(self.root,n=5005,indices=list(range(1,5005,2)),change=lambda s,e,p:e["rows"][0].update(time_s=11.001))
        m=worker.run(request)["marker_overlay"]
        self.assertEqual(m["alignment"],"not_checked_display_limit_exceeded");self.assertEqual(m["markers"],[])
        request["selection"]["range"]=[10,20]
        with self.assertRaisesRegex(worker.InputError,"exact retained"):worker.run(request)
    def test_overlimit_retention_is_unchecked_then_rejects_when_narrowed(self):
        request=fixture(self.root,n=5005,indices=list(range(1,5005,2)),change=lambda s,e,p:s["arrays"]["retained"].__setitem__(1,False))
        m=worker.run(request)["marker_overlay"]
        self.assertEqual(m["alignment"],"not_checked_display_limit_exceeded");self.assertEqual(m["markers"],[])
        request["selection"]["range"]=[10,20]
        with self.assertRaisesRegex(worker.InputError,"exact retained"):worker.run(request)
    def test_duplicate_sample_is_rejected(self):
        with self.assertRaisesRegex(worker.InputError,"distinct increasing"):
            self.run_fixture(change=lambda s,e,p:e["rows"][1].update(source_sample_index=501))
    def test_clock_origin_mismatch_is_rejected(self):
        with self.assertRaisesRegex(worker.InputError,"clocks differ"):
            self.run_fixture(change=lambda s,e,p:e["coordinates"].update(source_time_origin="other-clock"))
    def test_segment_identity_cannot_be_substituted(self):
        with self.assertRaisesRegex(worker.InputError,"uniquely matching"):
            self.run_fixture(change=lambda s,e,p:e["identity"].update(segment_id="segment-2"))
    def test_wrong_method_support_rejected(self):
        with self.assertRaisesRegex(worker.InputError,"recipe differ"):
            self.run_fixture(change=lambda s,e,p:e["support"]["method"].update(recipe="different/1"))
    def test_wrong_event_type_rejected(self):
        with self.assertRaisesRegex(worker.InputError,"Unexpected cardiac"):
            self.run_fixture(change=lambda s,e,p:e["rows"][0].update(type="systolic_pulse_peak"))
    def test_nonfinite_or_excluded_waveform_sample_is_not_a_valid_join(self):
        for field,value in (("clean",None),("retained",False)):
            with self.subTest(field=field),self.assertRaisesRegex(worker.InputError,"exact retained"):
                self.run_fixture(change=lambda s,e,p:s["arrays"][field].__setitem__(1,value))
    def test_manifest_substitution_rejected(self):
        request=fixture(self.root);request["marker_overlay"]["event_artifact"]["sha256"]="f"*64
        with self.assertRaisesRegex(worker.InputError,"metadata differs"):worker.run(request)


if __name__=="__main__":
    import sys
    if "--fixture" in sys.argv:
        parser=argparse.ArgumentParser();parser.add_argument("--fixture",type=Path,required=True);args=parser.parse_args()
        args.fixture.mkdir(parents=True,exist_ok=True)
        for modality in ("ecg","ppg"):
            request=fixture(args.fixture,modality=modality)
            (args.fixture/f"{modality}-request.json").write_text(json.dumps(request,allow_nan=False),encoding="utf-8")
    else:unittest.main()
