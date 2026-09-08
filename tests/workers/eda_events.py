"""Independent arithmetic, source-boundary and actual pinned EDA method checks."""
import copy
import csv
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import numpy as np

ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location("brohn_eda_events_test",ROOT/"scripts/workers/eda_events.py")
worker=importlib.util.module_from_spec(spec);spec.loader.exec_module(worker)


class EDAEvents(unittest.TestCase):
    def setUp(self): self.tmp=tempfile.TemporaryDirectory(prefix="brohn-eda-event-tests-");self.root=Path(self.tmp.name)
    def tearDown(self): self.tmp.cleanup()

    def parameters(self,**changes):
        p=dict(recipe="eda-event-highpass/1.0",event_codes={"A":"condition-a","B":"condition-b"},nuisance_codes=["MOVE"],
               event_source="synthetic recorded onset marker, shared conductance clock",settings_source="independent fixture protocol",
               baseline_s=[-2,0],response_s=[0,6],onset_latency_s=[.5,4],recovery_end_s=10,nuisance_effect_s=[0,8],
               overlap_policy="exclude",response_selection="first_onset",minimum_scr_amplitude_us=.05,relative_prominence=.1,
               edge_exclusion_s=10,minimum_segment_s=40)
        p.update(changes);return p

    def event(self,time=20,code="A",exposure="trial-1",**extra):
        return dict(time_s=time,code=code,exposure_id=exposure,**extra)

    def request(self,x=None,fs=25,events=None,people=None,sessions=None,resets=None,times=None,condition_labels=None,
                valid=None,unit="uS",column=False,p=None):
        if x is None:
            t=np.arange(1500)/fs
            dt=np.maximum(t-21,0)
            x=5+.001*t+np.exp(-dt/2)-np.exp(-dt/.7)
        x=np.asarray(x)
        if x.ndim==1: x=x[:,None]
        n=len(x);times=np.arange(n)/fs if times is None else times
        people=people if people is not None else ["person-1"]*n
        sessions=sessions if sessions is not None else ["session-1"]*n
        events=[self.event()] if events is None else events
        markers={int(round(e["time_s"]*fs)):e for e in events} if column else {}
        channels=["eda"+str(i+1) for i in range(x.shape[1])]
        path=self.root/"signal.csv"
        with path.open("w",encoding="utf-8",newline="") as stream:
            writer=csv.writer(stream)
            header=["time","person","session",*channels]
            for name,value in (("reset",resets),("valid",valid),("condition",condition_labels)):
                if value is not None: header.append(name)
            if column: header.extend(["event","exposure"])
            writer.writerow(header)
            for i,row in enumerate(x):
                values=[times[i],people[i],sessions[i],*["NA" if not np.isfinite(v) else v for v in row]]
                for value in (resets,valid,condition_labels):
                    if value is not None: values.append(value[i])
                if column: values.extend([markers.get(i,{}).get("code",""),markers.get(i,{}).get("exposure_id","")])
                writer.writerow(values)
        m=dict(time_column="time",time_unit="s",sampling_rate=fs,value_columns=channels,unit=unit,
               participant_column="person",session_column="session",origin="sample")
        for key,value in (("recording",resets),("valid",valid),("condition",condition_labels)):
            if value is not None: m[key+"_column"]={"recording":"reset"}.get(key,key)
        if column: m.update(event_column="event",exposure_column="exposure")
        else: m["events"]=events
        return dict(schema="brohn-worker-request/1.0",operation="eda_events",modality="eda",source_path=str(path),format="csv",metadata=m,parameters=p or self.parameters())

    def feature(self,result,name,trial="trial-1",person=None,channel="eda1"):
        return next(f for f in result["features"] if f["name"]==name and f["exposure_id"]==trial and f["channel"]==channel and (person is None or f["group"]["participant_id"]==person))

    def hand_bundle(self,candidates=None):
        times=np.arange(0,41,.5)
        # For onset20: baseline18..20 tonic mean39; response20..26 mean47.
        # Phasic21..25 triangle height2 gives area4; all other samples zero.
        phasic=np.maximum(2-abs(times-23),0)
        return dict(times=times,tonic_us=1+2*times,phasic_us=phasic,retained=np.ones(len(times),bool),
                    candidates=candidates or [],detector_error=None,segment_id="hand-segment")

    def hand_event(self,time=20,identifier="event-1",kind="stimulus_event"):
        return dict(id=identifier,time_s=time,type=kind)

    def candidate(self,onset=21,peak=23,amplitude=2,recovery=25):
        return dict(onset_time_s=onset,peak_time_s=peak,amplitude_us=amplitude,recovery_time_s=recovery)

    def summary(self,bundle=None,p=None,events=None):
        e=self.hand_event()
        features,summary=worker.event_summary(e,events or [e],[bundle or self.hand_bundle()],p or self.parameters(),1e-8)
        return {f["name"]:f for f in features},summary

    def test_hand_tonic_means_change_and_triangle_area(self):
        f,s=self.summary()
        self.assertEqual(f["tonic_baseline_mean"]["value"],39)
        self.assertEqual(f["tonic_response_mean"]["value"],47)
        self.assertEqual(f["tonic_response_minus_baseline"]["value"],8)
        self.assertEqual(f["phasic_response_area_signed"]["value"],4)
        self.assertEqual(f["phasic_response_area_positive"]["value"],4)
        self.assertEqual(s["baseline_support"]["samples"],5)
        self.assertEqual(s["response_support"]["duration_s"],6)

    def test_signed_negative_area_is_not_zero_imputation(self):
        b=self.hand_bundle();b["phasic_us"]=-np.ones(len(b["times"]))
        f,_=self.summary(b)
        self.assertEqual(f["phasic_response_area_signed"]["value"],-6)
        self.assertEqual(f["phasic_response_area_positive"]["value"],0)

    def test_hand_scr_amplitude_latency_recovery(self):
        f,s=self.summary(self.hand_bundle([self.candidate()]))
        for key,value in (("scr_response_magnitude",2),("scr_responder_amplitude",2),("scr_onset_latency",1),("scr_peak_latency",3),
                          ("scr_rise_time",2),("scr_half_recovery_time",2),("scr_qualifying_count",1),("scr_nonresponse",0)):
            self.assertEqual(f[key]["value"],value)
        self.assertFalse(s["nonresponse"])

    def test_nonresponse_magnitude_zero_amplitude_null_different_denominators(self):
        f,s=self.summary()
        self.assertEqual(f["scr_response_magnitude"]["value"],0)
        self.assertIsNone(f["scr_responder_amplitude"]["value"])
        self.assertEqual(f["scr_nonresponse"]["value"],1)
        self.assertNotEqual(f["scr_response_magnitude"]["denominator"],f["scr_responder_amplitude"]["denominator"])

    def test_missing_baseline_is_never_nonresponse_zero(self):
        b=self.hand_bundle();b["retained"][37]=False
        f,s=self.summary(b)
        self.assertFalse(s["baseline_support"]["complete"])
        self.assertTrue(s["response_support"]["complete"])
        self.assertTrue(all(v["value"] is None for v in f.values()))

    def test_noncontiguous_baseline_response_is_rejected(self):
        b=self.hand_bundle();first={**b,"retained":b["times"]<=20};second={**b,"retained":b["times"]>=20}
        _,s=worker.event_summary(self.hand_event(),[self.hand_event()],[first,second],self.parameters(),1e-8)
        self.assertTrue(s["baseline_support"]["complete"] and s["response_support"]["complete"])
        self.assertFalse(s["same_continuous_segment"])

    def test_overlap_excludes_or_retains_only_descriptives(self):
        events=[self.hand_event(),self.hand_event(25,"event-2")]
        f,s=self.summary(events=events)
        self.assertTrue(all(v["value"] is None for v in f.values()))
        self.assertEqual(s["overlapping_event_ids"],["event-2"])
        f,s=self.summary(p=self.parameters(overlap_policy="descriptive_only"),events=events)
        self.assertEqual(f["tonic_response_minus_baseline"]["value"],8)
        self.assertIsNone(f["scr_response_magnitude"]["value"])
        self.assertEqual(f["tonic_response_mean"]["interpretation"],"descriptive_window_measure")

    def test_nuisance_effect_interval_blocks_attribution(self):
        f,s=self.summary(events=[self.hand_event(),self.hand_event(16,"movement","nuisance_event")])
        self.assertEqual(s["overlapping_event_ids"],["movement"])
        self.assertIsNone(f["scr_response_magnitude"]["value"])

    def test_preexisting_or_unknown_onsets_are_not_nonresponses(self):
        for candidate in [self.candidate(onset=19),self.candidate(onset=None,amplitude=None)]:
            f,s=self.summary(self.hand_bundle([candidate]))
            self.assertEqual(s["scr_reason"],"unobserved_or_preexisting_scr_onset")
            self.assertIsNone(f["scr_response_magnitude"]["value"])
            self.assertEqual(f["tonic_response_mean"]["value"],47)

    def test_recovery_censoring_preserves_valid_amplitude(self):
        for recovery in [None,31]:
            f,s=self.summary(self.hand_bundle([self.candidate(recovery=recovery)]))
            self.assertEqual(f["scr_response_magnitude"]["value"],2)
            self.assertIsNone(f["scr_half_recovery_time"]["value"])
        f,s=self.summary(self.hand_bundle([self.candidate(recovery=29)]),events=[self.hand_event(),self.hand_event(27,"nuisance","nuisance_event")])
        self.assertEqual(f["scr_response_magnitude"]["value"],2)
        self.assertEqual(s["recovery_missing_reason"],"another_event_precedes_half_recovery")

    def test_selection_threshold_and_boundary_rules(self):
        candidates=[self.candidate(amplitude=.04),self.candidate(22,24,.5,26),self.candidate(24,26,1,29)]
        f,_=self.summary(self.hand_bundle(candidates))
        self.assertEqual(f["scr_response_magnitude"]["value"],.5)
        self.assertEqual(f["scr_qualifying_count"]["value"],2)
        f,_=self.summary(self.hand_bundle(candidates),p=self.parameters(response_selection="largest_amplitude"))
        self.assertEqual(f["scr_response_magnitude"]["value"],1)
        self.assertEqual(f["scr_onset_latency"]["value"],4)

    def test_detector_error_keeps_window_measures_and_no_zero(self):
        b=self.hand_bundle();b["detector_error"]="upstream candidate mismatch"
        f,s=self.summary(b)
        self.assertEqual(f["tonic_response_mean"]["value"],47)
        self.assertIsNone(f["scr_response_magnitude"]["value"])
        self.assertEqual(s["scr_reason"],"scr_detector_failed")

    def test_actual_highpass_matches_upstream_full_recording(self):
        request=self.request();r=worker.run(request)
        source,_=worker.load_source(Path(request["source_path"]),request["metadata"],"csv",worker.settings(request["parameters"],25))
        nk=worker.io.require_neurokit();x=source[0]["values"][0]
        clean=nk.eda_clean(x,sampling_rate=25,method="neurokit")
        components=nk.eda_phasic(clean,sampling_rate=25,method="highpass",cutoff=.05)
        t=source[0]["times"];indices=(t>=18)&(t<=20)
        expected=float(np.trapezoid(components["EDA_Tonic"][indices],t[indices])/2)
        self.assertAlmostEqual(self.feature(r,"tonic_baseline_mean")["value"],expected,places=12)
        # The standard Bateman pulse is detected on the full filtered phasic
        # trace. Independently compare its public upstream onset/amplitude.
        _,peaks=nk.eda_peaks(components["EDA_Phasic"],sampling_rate=25,method="neurokit",amplitude_min=.1)
        chosen=next(i for i,onset in enumerate(peaks["SCR_Onsets"]) if np.isfinite(onset) and 20.5<=t[int(onset)]<=24)
        self.assertAlmostEqual(self.feature(r,"scr_response_magnitude")["value"],peaks["SCR_Amplitude"][chosen],places=12)
        self.assertGreater(self.feature(r,"scr_response_magnitude")["value"],.3)
        self.assertAlmostEqual(self.feature(r,"scr_peak_latency")["value"],2.08,places=8)
        self.assertEqual(len(r["segments"]),1)
        self.assertEqual(r["segments"][0]["samples"],1500)
        self.assertFalse(r["quality"]["participant_inference_performed"])
        json.dumps(r,allow_nan=False)

    def test_short_trial_labels_do_not_split_continuous_filtering(self):
        events=[self.event(20),self.event(40,"B","trial-2")]
        labels=["condition-a" if i//50%2==0 else "condition-b" for i in range(1500)]
        labels[500]="condition-a";labels[1000]="condition-b"
        request=self.request(events=events,column=True,condition_labels=labels)
        original=worker.decompose
        with patch.object(worker,"decompose",wraps=original) as spy: result=worker.run(request)
        self.assertEqual(spy.call_count,1)
        self.assertEqual(len(spy.call_args.args[0]),1500)
        self.assertEqual(result["quality"]["computed_window_cells"],2)
        self.assertEqual([r["exposure_id"] for r in result["recordings"]],["trial-1","trial-2"])

    def test_actual_cvxeda_defaults_run_and_reject_overrides(self):
        fs=25;t=np.arange(1000)/fs;x=1+.001*t
        for onset in [5,21,32]:
            dt=np.maximum(t-onset,0);x+=np.exp(-dt/2)-np.exp(-dt/.7)
        request=self.request(x,p=self.parameters(recipe="eda-event-cvxeda-defaults/1.0"))
        result=worker.run(request)
        self.assertEqual(result["segments"][0]["status"],"computed")
        self.assertEqual(result["parameters"]["recording-1"]["effective"]["cvx_defaults"],worker.CVX_DEFAULTS)
        self.assertTrue(np.isfinite(self.feature(result,"tonic_response_minus_baseline")["value"]))
        request["parameters"]["alpha"]=1
        with self.assertRaises(worker.InputError): worker.run(request)

    def test_cvx_context_bound_has_explicit_unavailable_reason(self):
        p=worker.settings(self.parameters(recipe="eda-event-cvxeda-defaults/1.0"),25)
        with self.assertRaisesRegex(worker.InputError,"10,000"):
            worker.decompose(np.ones(10001),np.arange(10001)/25,25,p)

    def test_people_and_sessions_preprocess_independently(self):
        x=np.concatenate([np.ones(1500)*5,np.ones(1500)*10])
        request=self.request(x,people=["p1"]*1500+["p2"]*1500,times=np.tile(np.arange(1500)/25,2),
                             events=[self.event(recording_id="recording-1"),self.event(recording_id="recording-2")])
        result=worker.run(request)
        self.assertEqual(len(result["segments"]),2)
        self.assertAlmostEqual(self.feature(result,"tonic_response_mean",person="p1")["value"],5,places=8)
        self.assertAlmostEqual(self.feature(result,"tonic_response_mean",person="p2")["value"],10,places=8)
        request["metadata"]["events"][0].pop("recording_id")
        with self.assertRaisesRegex(worker.InputError,"recording_id"): worker.run(request)

    def test_source_reset_required_for_reversed_clock(self):
        times=np.tile(np.arange(1500)/25,2);x=np.ones(3000)*5
        events=[self.event(recording_id="recording-1"),self.event(recording_id="recording-2")]
        with self.assertRaisesRegex(worker.InputError,"duplicate or reversed"):
            worker.run(self.request(x,times=times,events=events))
        result=worker.run(self.request(x,times=times,events=events,resets=["reset1"]*1500+["reset2"]*1500))
        self.assertEqual(len(result["segments"]),2)
        self.assertEqual(result["segments"][0]["group"]["source_recording_id"],"reset1")
        self.assertNotIn("exposure_id",result["segments"][0]["group"])

    def test_explicit_segment_mapping_keeps_same_visit_reset_separate(self):
        times = np.tile(np.arange(1500)/25, 2)
        events = [self.event(recording_id="recording-1"), self.event(recording_id="recording-2")]
        request = self.request(np.r_[np.ones(1500)*5, np.ones(1500)*10], times=times,
                               events=events, resets=["before-reset"]*1500+["after-reset"]*1500)
        request["metadata"]["segment_column"] = request["metadata"].pop("recording_column")
        result = worker.run(request)
        self.assertEqual([s["group"]["segment_id"] for s in result["segments"]], ["before-reset", "after-reset"])
        self.assertTrue(all(s["group"]["participant_id"] == "person-1" and s["group"]["session_id"] == "session-1"
                            and "exposure_id" not in s["group"] for s in result["segments"]))
        means = [f["value"] for f in result["features"] if f["name"] == "tonic_response_mean"]
        self.assertEqual(len(means), 2)
        self.assertAlmostEqual(means[0], 5, places=8)
        self.assertAlmostEqual(means[1], 10, places=8)

    def test_missing_invalid_and_negative_samples_never_reach_filter(self):
        n=3000;x=np.ones(n)*5;x[1500]=np.nan;x[1600]=-1
        valid=[1]*n;valid[1700]=0
        request=self.request(x,valid=valid)
        original=worker.decompose
        with patch.object(worker,"decompose",wraps=original) as spy: result=worker.run(request)
        self.assertTrue(all(np.isfinite(c.args[0]).all() and (c.args[0]>=0).all() for c in spy.call_args_list))
        quality=result["recordings"][0]["channel_quality"]
        self.assertEqual(quality["invalid_amplitude_samples"],1)
        self.assertEqual(quality["source_validity_excluded_samples"],1)
        self.assertEqual(quality["missing_samples"],2)
        self.assertEqual(quality["original_missing_source_samples"],1)
        self.assertEqual({(m["reason"],m["source_row_start"]) for m in result["source_masks"]},
                         {("missing_source_signal",1500),("negative_conductance",1600),("source_validity_exclusion",1700)})

    def test_gap_is_not_filtered_across_or_missing_baseline_zero(self):
        times=np.arange(3000)/25;times[1500:]+=2
        request=self.request(np.ones(3000)*5,times=times,events=[self.event(62)])
        r=worker.run(request)
        self.assertEqual(len(r["segments"]),2)
        self.assertEqual(r["recordings"][0]["channel_quality"]["time_gap_count"],1)
        self.assertAlmostEqual(r["source_masks"][0]["unobserved_duration_s"],2)
        self.assertIsNone(self.feature(r,"scr_response_magnitude")["value"])

    def test_units_si_and_micro_siemens_agree(self):
        x=np.ones(1500)*5
        a=worker.run(self.request(x,unit="uS"));b=worker.run(self.request(x/1e6,unit="S"))
        for af,bf in zip(a["features"],b["features"]): self.assertEqual(af["value"],bf["value"])
        with self.assertRaises(worker.InputError): worker.run(self.request(x,unit="ohm"))

    def test_clock_decimal_ms_origin_preserved_and_alignment_explicit(self):
        times=[str(1000000000000000+i*40) for i in range(1500)]
        request=self.request(np.ones(1500)*5,times=times,events=[self.event(20.01)])
        request["metadata"]["time_unit"]="ms"
        result=worker.run(request)
        self.assertEqual(result["recordings"][0]["source_time_origin"],times[0])
        self.assertAlmostEqual(result["recordings"][0]["alignment_error_s"],-.01)
        self.assertEqual(result["recordings"][0]["time_s"],20)

    def test_event_code_condition_identity_and_alignment_conflicts_reject(self):
        for event in [self.event(code="unknown"),self.event(condition_id="wrong"),self.event(exposure=""),self.event(99)]:
            with self.assertRaises(worker.InputError): worker.run(self.request(events=[event]))
        with self.assertRaises(worker.InputError): worker.run(self.request(events=[self.event(),self.event(30)]))
        request=self.request(events=[self.event(20.019)]);request["parameters"]["event_tolerance_s"]=.001
        with self.assertRaisesRegex(worker.InputError,"alignment tolerance"): worker.run(request)

    def test_declared_tsv_extensionless_source_and_column_events(self):
        request=self.request(column=True)
        source=Path(request["source_path"]);opaque=self.root/"opaque-object"
        opaque.write_text(source.read_text().replace(",","\t"),encoding="utf-8")
        request.update(source_path=str(opaque),format="tsv")
        result=worker.run(request)
        self.assertEqual(result["source"]["source_format"],"tsv")
        self.assertEqual(result["recordings"][0]["source_sample_index"],500)

    def test_irregular_sampling_and_bad_validity_reject(self):
        times=np.arange(1500)/25;times[100]+=.01
        with self.assertRaisesRegex(worker.InputError,"irregular sampling"): worker.run(self.request(times=times))
        valid=[1]*1500;valid[100]="maybe"
        with self.assertRaisesRegex(worker.InputError,"Validity values"): worker.run(self.request(valid=valid))

    def test_protocol_settings_are_required_and_not_silently_ignored(self):
        for key,value in [("baseline_s",None),("edge_exclusion_s",1),("minimum_segment_s",30),("onset_latency_s",[0,7]),
                          ("relative_prominence",0),("recovery_end_s",5),("unknown",True),("response_s",[0,6.001])]:
            p=self.parameters();p[key]=value
            with self.assertRaises(worker.InputError): worker.settings(p,25)
        p=self.parameters();p.pop("settings_source")
        with self.assertRaises(worker.InputError): worker.settings(p,25)

    def test_peakless_decomposition_guard_is_explicit(self):
        nk=worker.io.require_neurokit();p=worker.settings(self.parameters(),25)
        with patch.object(nk,"eda_phasic",return_value={"EDA_Tonic":np.ones(1500)*5,"EDA_Phasic":np.zeros(1500)}),patch.object(nk,"eda_peaks") as peaks:
            b=worker.decompose(np.ones(1500)*5,np.arange(1500)/25,25,p)
        peaks.assert_not_called();self.assertEqual(b["candidates"],[]);self.assertIsNone(b["detector_error"])

    def test_cli_json_receipt_source_protection_and_error(self):
        request=self.request();rq=self.root/"request.json";out=self.root/"result.json"
        rq.write_text(json.dumps(request),encoding="utf-8")
        proc=subprocess.run([sys.executable,str(ROOT/"scripts/workers/eda_events.py"),"--request",str(rq),"--output",str(out)],capture_output=True,text=True)
        self.assertEqual(proc.returncode,0,proc.stderr)
        saved=json.loads(out.read_text(encoding="utf-8"));self.assertEqual(saved["schema"],"brohn-worker-result/1.0")
        before=Path(request["source_path"]).read_bytes()
        proc=subprocess.run([sys.executable,str(ROOT/"scripts/workers/eda_events.py"),"--request",str(rq),"--output",request["source_path"]],capture_output=True,text=True)
        self.assertEqual(proc.returncode,2);self.assertEqual(Path(request["source_path"]).read_bytes(),before)
        rq.write_text('{"schema":"one","schema":"two"}',encoding="utf-8")
        proc=subprocess.run([sys.executable,str(ROOT/"scripts/workers/eda_events.py"),"--request",str(rq),"--output",str(out)],capture_output=True,text=True)
        self.assertEqual(proc.returncode,2);self.assertIn("Duplicate",json.loads(out.read_text())["error"]["message"])


if __name__=="__main__": unittest.main(verbosity=2)
