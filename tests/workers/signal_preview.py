"""Independent extrema/count/support oracles for verified processed signal views."""
import copy
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import numpy as np

ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location("brohn_preview_test",ROOT/"scripts/workers/signal_preview.py")
worker=importlib.util.module_from_spec(spec);spec.loader.exec_module(worker)


class Preview(unittest.TestCase):
    def setUp(self): self.tmp=tempfile.TemporaryDirectory(prefix="brohn-signal-preview-tests-");self.root=Path(self.tmp.name)
    def tearDown(self): self.tmp.cleanup()
    def table(self,values=None,times=None,retained=None,indices=None,identifier="segment-1",axis="time",origin="99999999999999999",unit="uS",rate=1):
        values=[5,1,8,4] if values is None else values;n=len(values)
        times=list(range(n)) if times is None else times
        retained=[True]*n if retained is None else retained
        coordinate="frequency_hz" if axis=="frequency" else "time_s"
        cols=[worker.artifacts._column(coordinate,"float64","Hz" if axis=="frequency" else "s",role="coordinate"),
              worker.artifacts._column("measure","float64",unit,True),worker.artifacts._column("retained","boolean",None,role="support")]
        arrays={coordinate:times,"measure":values,"retained":retained}
        if indices is not None:
            cols.append(worker.artifacts._column("source_sample_index","integer","sample_index",role="index"));arrays["source_sample_index"]=indices
        return dict(table_id=identifier,identity=dict(recording_id="recording-1",channel="eda",group=dict(participant_id="p1",session_id="s1")),
            arrays=arrays,specification=cols,coordinates=dict(axis=axis,reference="frequency bins" if axis=="frequency" else "source-relative seconds",source_time_origin=origin,source_time_unit="ms"),
            support=dict(source=dict(sampling_rate=rate)) if rate else {})
    def artifact(self,tables=None):
        p=dict(source_sha256="a"*64,engine=dict(name="fixture",worker_sha256="b"*64),operation="physiology",origin="sample",parameters={"recipe":"fixture/1"})
        with worker.artifacts.TableWriter(self.root,"physiology-series",p,chunk_rows=17) as writer:
            for table in tables or [self.table()]: writer.write_arrays(**table)
            manifest=writer.finish()
        receipt=worker.artifacts.verify_manifest([manifest])
        return dict(schema="brohn-signal-preview-request/1.0",operation="signal_preview",artifact=manifest,verification_receipt=receipt,
                    selection=dict(table_ids=[(tables or [self.table()])[0]["table_id"]],recording_id="recording-1",channel="eda",value_column="measure",range=None),parameters=dict(max_bins=1))
    def points(self,result): return [p for b in result["envelopes"] for p in b["points"]]

    def test_pupil_trace_requires_dedicated_masks_but_keeps_catalog(self):
        table = self.table([4, -1, 6], retained=[True, True, True])
        table["support"]["trace_profile"] = "gaze-pupil-source-trace/1.0"
        request = self.artifact([table])
        with self.assertRaisesRegex(worker.InputError, "dedicated gaze adapter"):
            worker.run(request)
        catalog_request = {k: v for k, v in request.items() if k not in {"selection", "parameters"}}
        catalog_request["operation"] = "signal_catalog"
        catalog = worker.run(catalog_request)
        self.assertEqual(catalog["tables"][0]["rows"], 3)
        self.assertEqual(catalog["tables"][0]["support"]["trace_profile"], "gaze-pupil-source-trace/1.0")

    def test_hand_envelope_keeps_first_min_max_last_in_source_order(self):
        result=worker.run(self.artifact())
        self.assertEqual([p["y"] for p in self.points(result)],[5,1,8,4])
        self.assertEqual([p["row_index"] for p in self.points(result)],[0,1,2,3])
        self.assertEqual(result["envelopes"][0]["count"],4)
        self.assertEqual(result["full_range"]["eligible_value_range"],[1,8])
        self.assertEqual(result["tables"][0]["coordinate_range"],[0,3])
        self.assertEqual(result["tables"][0]["observed_coordinate_rows"],4)
        self.assertEqual(result["quality"]["envelope_rows"],4)

    def test_sparse_spikes_not_lost_by_uniform_preview_sampling(self):
        values=[0.]*10001;values[3337]=100;values[5558]=-60
        request=self.artifact([self.table(values,indices=list(range(len(values))))]);request["parameters"]["max_bins"]=100
        result=worker.run(request);points=self.points(result)
        self.assertIn(100,[p["y"] for p in points]);self.assertIn(-60,[p["y"] for p in points])
        self.assertEqual(result["selected_range"]["rows"],10001)
        self.assertEqual(result["selected_range"]["eligible_value_range"],[-60,100])
        self.assertEqual(sum(b["count"] for b in result["envelopes"]),10001)
        self.assertLessEqual(len(points),400)
        self.assertEqual(next(p["source_sample_index"] for p in points if p["y"]==100),3337)

    def test_inclusive_selected_range_and_full_source_counts(self):
        request=self.artifact([self.table(list(range(10)))]);request["selection"]["range"]=[5,7]
        result=worker.run(request)
        self.assertEqual(result["full_range"]["rows"],10)
        self.assertEqual(result["selected_range"]["rows"],3)
        self.assertEqual(result["selected_range"]["eligible_value_range"],[5,7])
        self.assertEqual(result["full_range"]["eligible_value_range"],[0,9])
        self.assertEqual([p["row_index"] for p in self.points(result)],[5,7])

    def test_outside_range_reports_empty_without_invented_points(self):
        request=self.artifact();request["selection"]["range"]=[10,20]
        result=worker.run(request)
        self.assertEqual(result["status"],"empty_range");self.assertEqual(result["envelopes"],[])
        self.assertEqual(result["selected_range"]["rows"],0)
        self.assertIsNone(result["selected_range"]["eligible_value_range"])
        self.assertEqual(result["full_range"]["rows"],4)

    def test_null_and_excluded_support_do_not_become_zero_or_connected(self):
        request=self.artifact([self.table([1,None,100,4],retained=[True,True,False,True])])
        result=worker.run(request)
        self.assertEqual([p["y"] for p in self.points(result)],[1,4])
        self.assertEqual(result["selected_range"]["observed_value_range"],[1,100])
        self.assertEqual(result["selected_range"]["eligible_value_range"],[1,4])
        self.assertEqual(result["selected_range"]["missing_value_rows"],1)
        self.assertEqual(result["selected_range"]["excluded_retention_rows"],1)
        self.assertEqual(len(result["fragments"]),2)
        self.assertEqual(result["fragments"][1]["break_before"],"retention_exclusion")

    def test_source_index_gap_disconnects_inside_same_bin(self):
        result=worker.run(self.artifact([self.table([1,2,3,4],indices=[0,1,8,9])]))
        self.assertEqual(len(result["envelopes"]),2)
        self.assertEqual(result["fragments"][1]["break_before"],"source_sample_gap")
        self.assertEqual(result["quality"]["envelope_rows"],4)

    def test_declared_clock_gap_disconnects_without_guessing_sample_indices(self):
        result=worker.run(self.artifact([self.table([1,2,3,4],times=[0,1,10,11])]))
        self.assertEqual(result["fragments"][1]["break_before"],"declared_clock_cadence_gap")
        self.assertEqual([(f["first_x"],f["last_x"]) for f in result["fragments"]],[(0,1),(10,11)])

    def test_separate_tables_remain_disconnected(self):
        tables=[self.table(identifier="segment-1"),self.table(times=[10,11,12,13],identifier="segment-2")]
        request=self.artifact(tables);request["selection"]["table_ids"]=["segment-1","segment-2"];request["parameters"]["max_bins"]=2
        result=worker.run(request)
        self.assertEqual(result["full_range"]["rows"],8)
        self.assertEqual(len(result["fragments"]),2)
        self.assertTrue(all(f["connection_policy"]=="within_this_fragment_only" for f in result["fragments"]))
        self.assertNotEqual(result["fragments"][0]["id"],result["fragments"][1]["id"])

    def test_different_origin_recording_and_channel_cannot_be_silently_joined(self):
        for field,value in [("origin","999"),("unit","mV")]:
            tables=[self.table(identifier="segment-1"),self.table(identifier="segment-2",**{field:value})]
            request=self.artifact(tables);request["selection"]["table_ids"]=["segment-1","segment-2"];request["parameters"]["max_bins"]=2
            with self.assertRaises(worker.InputError): worker.run(request)
        request=self.artifact();request["selection"]["channel"]="wrong"
        with self.assertRaisesRegex(worker.InputError,"different recording or channel"): worker.run(request)

    def test_frequency_axis_is_spectrum_hz_and_never_time(self):
        request=self.artifact([self.table([0,5,100,2],times=[0,5,10,15],axis="frequency",unit="uV^2/Hz",rate=None)])
        result=worker.run(request)
        self.assertEqual(result["axis"]["kind"],"frequency");self.assertEqual(result["axis"]["unit"],"Hz")
        self.assertEqual(result["fragments"][0]["rendering"],"spectrum")
        self.assertEqual(result["envelopes"][0]["maximum"]["x"],10)

    def test_person_session_identity_not_joined_by_equal_recording_labels(self):
        first=self.table(identifier="segment-1");second=self.table(identifier="segment-2")
        second["identity"]["group"]["participant_id"]="p2"
        request=self.artifact([first,second]);request["selection"]["table_ids"]=["segment-1","segment-2"];request["parameters"]["max_bins"]=2
        with self.assertRaisesRegex(worker.InputError,"person/session/reset"): worker.run(request)

    def test_event_axis_has_no_connecting_trace(self):
        result=worker.run(self.artifact([self.table(axis="event",times=[1,4,10,20])]))
        self.assertEqual(result["axis"]["kind"],"event")
        self.assertEqual(result["fragments"][0]["connection_policy"],"none")
        self.assertEqual(result["fragments"][0]["rendering"],"scatter")

    def test_unknown_cadence_does_not_invent_continuous_time_support(self):
        result=worker.run(self.artifact([self.table(rate=None,times=[0,2,8,10])]))
        self.assertEqual(result["fragments"][0]["rendering"],"scatter")
        self.assertIsNone(result["fragments"][0]["declared_interval_s"])

    def test_large_clock_origin_stays_exact_string(self):
        result=worker.run(self.artifact())
        self.assertEqual(result["axis"]["source_time_origin"],"99999999999999999")
        self.assertIsInstance(result["axis"]["source_time_origin"],str)
        self.assertEqual(result["effective_range"],[0,3])

    def test_catalog_pagination_is_explicit_and_reports_actual_ranges(self):
        tables=[self.table(identifier="segment-"+str(i),times=[i*10+j for j in range(4)]) for i in range(5)]
        request=self.artifact(tables);request.update(operation="signal_catalog",page=dict(offset=2,limit=2));request.pop("selection");request.pop("parameters")
        result=worker.run(request)
        self.assertEqual(result["pagination"],dict(offset=2,limit=2,returned=2,total_tables=5,next_offset=4))
        self.assertEqual([t["table_id"] for t in result["tables"]],["segment-2","segment-3"])
        self.assertEqual(result["tables"][0]["coordinate_range"],[20,23])
        self.assertEqual(result["tables"][0]["value_columns"][0]["unit"],"uS")
        request["page"]["offset"]=4
        self.assertIsNone(worker.run(request)["pagination"]["next_offset"])

    def test_null_selection_catalog_and_empty_table(self):
        request=self.artifact([self.table([],times=[],retained=[])]);request["selection"]=None;request.pop("parameters")
        result=worker.run(request)
        self.assertEqual(result["schema"],"brohn-signal-catalog/1.0")
        self.assertIsNone(result["tables"][0]["coordinate_range"])
        self.assertEqual(result["tables"][0]["rows"],0)

    def test_receipt_missing_swapped_or_artifact_corruption_rejects(self):
        for field in ["verification_receipt","rows"]:
            request=self.artifact()
            if field=="rows": request["verification_receipt"]["artifacts"][0]["rows"]=999
            else: request.pop(field)
            with self.assertRaises(worker.InputError): worker.run(request)
        request=self.artifact();Path(request["artifact"]["path"]).write_text("corrupt")
        with self.assertRaisesRegex(worker.InputError,"SHA-256"): worker.run(request)

    def test_unavailable_table_or_measure_never_substituted(self):
        for field,value in [("table_ids",["absent"]),("value_column","time_s"),("value_column","retained")]:
            request=self.artifact();request["selection"][field]=value
            with self.assertRaises(worker.InputError): worker.run(request)

    def test_clock_reversal_or_axis_unit_mismatch_rejects(self):
        with self.assertRaisesRegex(worker.InputError,"strictly increase"): worker.run(self.artifact([self.table(times=[0,1,.5,2])]))
        table=self.table();table["specification"][0]["unit"]="Hz"
        with self.assertRaisesRegex(worker.InputError,"axis and coordinate unit"): worker.run(self.artifact([table]))

    def test_missing_coordinate_has_explicit_counts_and_break(self):
        table=self.table(times=[0,None,2,3]);table["specification"][0]["nullable"]=True
        result=worker.run(self.artifact([table]))
        self.assertEqual(result["full_range"]["missing_coordinate_rows"],1)
        self.assertEqual(result["selected_range"]["eligible_value_rows"],3)
        self.assertEqual(len(result["fragments"]),2)

    def test_one_sample_has_defined_zero_width_range(self):
        result=worker.run(self.artifact([self.table([42],times=[20])]))
        self.assertEqual(result["effective_range"],[20,20])
        self.assertEqual(len(self.points(result)),1)
        self.assertEqual(result["envelopes"][0]["count"],1)

    def test_bad_ranges_unbounded_bins_and_unknown_settings_reject(self):
        for value in [[2,1],[1,1],[0,float("nan")]]:
            request=self.artifact();request["selection"]["range"]=value
            with self.assertRaises(worker.InputError): worker.run(request)
        request=self.artifact();request["parameters"]["max_bins"]=100000
        with self.assertRaises(worker.InputError): worker.run(request)
        request=self.artifact();request["parameters"]["interpolate"]=True
        with self.assertRaises(worker.InputError): worker.run(request)

    def test_cli_new_receipt_and_error_are_structured(self):
        request=self.artifact();path=self.root/"request.json";out=self.root/"view.json"
        path.write_text(json.dumps(request),encoding="utf-8")
        args=[sys.executable,str(ROOT/"scripts/workers/signal_preview.py"),"--request",str(path),"--output",str(out)]
        process=subprocess.run(args,capture_output=True,text=True)
        self.assertEqual(process.returncode,0,process.stderr)
        result=json.loads(out.read_text());self.assertEqual(result["schema"],"brohn-signal-preview/1.0")
        before=out.read_bytes();process=subprocess.run(args,capture_output=True,text=True)
        self.assertEqual(process.returncode,2);self.assertEqual(out.read_bytes(),before)
        self.assertEqual(out.parent,self.root);out.unlink()
        request["selection"]["value_column"]="absent";path.write_text(json.dumps(request),encoding="utf-8")
        process=subprocess.run(args,capture_output=True,text=True)
        self.assertEqual(process.returncode,2);self.assertEqual(json.loads(out.read_text())["status"],"error")

    def test_actual_eda_artifact_view_matches_complete_processed_array(self):
        ps=importlib.util.spec_from_file_location("preview_actual_eda",ROOT/"tests/workers/eda_events.py")
        fixture=importlib.util.module_from_spec(ps);ps.loader.exec_module(fixture)
        case=fixture.EDAEvents();case.setUp()
        try:
            times=np.arange(3000)/25;dt=np.maximum(times-21,0);x=5+.001*times+np.exp(-dt/2)-np.exp(-dt/.7)
            request=case.request(x);request["artifact_directory"]=str(self.root)
            complete=fixture.worker.run(request)
            manifest=next(a for a in complete["artifacts"] if a["kind"]=="physiology-series")
            receipt=worker.artifacts.verify_manifest([manifest])
            cat=worker.run(dict(schema="brohn-signal-preview-request/1.0",operation="signal_catalog",artifact=manifest,verification_receipt=receipt))
            t=cat["tables"][0]
            req=dict(schema="brohn-signal-preview-request/1.0",operation="signal_preview",artifact=manifest,verification_receipt=receipt,
                selection=dict(table_ids=[t["table_id"]],recording_id="recording-1",channel="eda1",value_column="phasic_us",range=[18,27]),parameters=dict(max_bins=8))
            result=worker.run(req)
            b=fixture.worker.decompose(x,times,25,fixture.worker.settings(request["parameters"],25))
            mask=(times>=18)&(times<=27)
            expected=b["phasic_us"][mask]
            self.assertEqual(result["full_range"]["rows"],3000)
            self.assertEqual(result["full_range"]["eligible_value_rows"],2500)
            self.assertEqual(result["selected_range"]["eligible_value_rows"],226)
            self.assertEqual(result["selected_range"]["eligible_value_range"],[float(expected.min()),float(expected.max())])
            self.assertEqual(min(p["y"] for p in self.points(result)),float(expected.min()))
            self.assertEqual(max(p["y"] for p in self.points(result)),float(expected.max()))
            self.assertEqual(result["axis"]["value_unit"],"uS")
        finally: case.tearDown()


if __name__=="__main__": unittest.main(verbosity=2)
