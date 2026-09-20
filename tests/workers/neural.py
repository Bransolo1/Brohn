"""Independent numerical/boundary checks; synthetic evidence is not device qualification."""
import copy
import csv
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

import numpy as np

ROOT=Path(__file__).resolve().parents[2]
SPEC=importlib.util.spec_from_file_location("brohn_neural_test",ROOT/"scripts"/"workers"/"neural.py")
worker=importlib.util.module_from_spec(SPEC); SPEC.loader.exec_module(worker)


class NeuralTests(unittest.TestCase):
    def setUp(self):
        self.directory=tempfile.TemporaryDirectory(prefix="brohn-neural-test-"); self.root=Path(self.directory.name)

    def tearDown(self): self.directory.cleanup()

    def parameters(self,recipe="eeg-erp-epochs/1.0"):
        p={"recipe":recipe,"event_codes":{"A":"condition-a","B":"condition-b"},"event_source":"Synthetic exact sample-onset fixture",
            "epoch_s":[-.2,.6],"baseline_s":[-.2,-.01],"reference":{"mode":"acquisition","source":"Synthetic common zero reference"},
            "filter":{"mode":"none"},"rejection":{"window_s":[-.2,.6],"peak_to_peak_uv":100,"flat_uv":None},
            "minimum_trials":2,"overlap_policy":"reject","settings_source":"Independent arithmetic fixture, not a device preset",
            "amplitude_window_s":[.2,.39],"peak_polarity":"positive"}
        if recipe!="eeg-erp-epochs/1.0":
            p.pop("amplitude_window_s"); p.pop("peak_polarity")
            p.update(epoch_s=[-2,2],baseline_s=None,rejection={"window_s":[-2,2],"peak_to_peak_uv":100,"flat_uv":None})
        if recipe in {"eeg-morlet-epochs/1.0","eeg-morlet-epochs/1.1"}:
            p.update(frequencies_hz=[10,20],n_cycles=[3,3],power="total",power_baseline={"mode":"ratio","window_s":[-1,-.5],"minimum_power_uv2":1e-20},summary_window_s=[0,.5])
            if recipe=="eeg-morlet-epochs/1.1":
                p["power_baseline"]["adequacy"]={"policy":"complete-pre-event-wavelet-support/1.0","minimum_cycles":4,
                    "rationale":"Independent stationary 10-Hz sine fixture; require four full baseline cycles for this test, not a universal threshold."}
        elif recipe=="eeg-frequency-tagging/1.0":
            p.update(spectral_window_s=[0,2],tag_frequencies_hz=[10],harmonics=[1],window="boxcar",noise_neighbor_bins=2,noise_skip_bins=1,max_bin_offset_hz=1e-8)
        return p

    def request(self,values,fs=100,events=None,parameters=None,unit="uV",times=None,event_column=False,groups=None):
        values=np.asarray(values)
        if values.ndim==1: values=values[:,None]
        channels=[f"channel-{i}" for i in range(values.shape[1])]
        times=np.arange(len(values))/fs if times is None else times
        path=self.root/"signal.csv"
        markers={int(round(e["time_s"]*fs)):e["code"] for e in events or []}
        with path.open("w",newline="",encoding="utf-8") as stream:
            writer=csv.writer(stream); writer.writerow(["time",*channels,*(groups or {}),*(["event"] if event_column else [])])
            for i,row in enumerate(values):
                writer.writerow([times[i],*["NA" if not np.isfinite(v) else v for v in row],*[g[i] for g in (groups or {}).values()],*([markers.get(i,"")] if event_column else [])])
        metadata={"time_column":"time","time_unit":"s","sampling_rate":fs,"value_columns":channels,"unit":unit,"origin":"sample"}
        metadata.update({f"{key}_column":key for key in groups or {}})
        if event_column: metadata["event_column"]="event"
        else: metadata["events"]=events or [{"time_s":2,"code":"A"},{"time_s":5,"code":"A"},{"time_s":8,"code":"A"}]
        return {"schema":"brohn-worker-request/1.0","operation":"neural","modality":"eeg","source_path":str(path),"format":"csv","metadata":metadata,"parameters":parameters or self.parameters()}

    def pulse(self,amplitude=10):
        values=np.full(1100,5.)
        for onset in [200,500,800]: values[onset+20:onset+40]+=amplitude
        return values

    def features(self,result,name,condition="condition-a",channel="channel-0"):
        return [f for f in result["features"] if f["name"]==name and f["condition_id"]==condition and f["channel"]==channel]

    def test_evoked_pulse_baseline_and_trial_sem(self):
        result=worker.run(self.request(self.pulse()))
        self.assertEqual(result["status"],"partial") # A usable, declared B absent.
        self.assertAlmostEqual(self.features(result,"erp_mean_amplitude")[0]["value"],10,places=10)
        self.assertAlmostEqual(self.features(result,"erp_peak_latency")[0]["value"],.2)
        erp=result["series"][0]; self.assertEqual(erp["trial_count"],3)
        np.testing.assert_allclose(erp["sem_uv"],0,atol=1e-12)
        self.assertEqual(result["recordings"][1]["reason"],"insufficient_retained_trials")
        self.assertFalse(result["quality"]["participant_inference_performed"])
        json.dumps(result,allow_nan=False)

    def test_csv_and_explicit_event_agreement(self):
        events=[{"time_s":t,"code":"A"} for t in [2,5,8]]
        explicit=worker.run(self.request(self.pulse(),events=events))
        column=worker.run(self.request(self.pulse(),events=events,event_column=True))
        self.assertEqual(explicit["features"],column["features"])
        self.assertEqual([e["source_sample_index"] for e in column["events"]],[200,500,800])

    def test_declared_tsv_delimiter_works_without_extension(self):
        request=self.request(self.pulse()); source=Path(request["source_path"])
        opaque=self.root/"opaque-hash-object"; opaque.write_text(source.read_text().replace(",","\t"))
        request["source_path"]=str(opaque);request["format"]="tsv"
        result=worker.run(request)
        self.assertAlmostEqual(self.features(result,"erp_mean_amplitude")[0]["value"],10)

    def test_voltage_scaling_and_uncorrected_baseline(self):
        first=worker.run(self.request(self.pulse(),unit="uV"))
        second=worker.run(self.request(self.pulse()*1e-6,unit="V"))
        self.assertEqual(first["features"],second["features"])
        p=self.parameters(); p["baseline_s"]=None
        raw=worker.run(self.request(self.pulse(),parameters=p))
        self.assertAlmostEqual(self.features(raw,"erp_mean_amplitude")[0]["value"],15)

    def test_artifact_missing_and_flat_rejections_are_explicit(self):
        values=self.pulse(); values[220]=200; values[520]=np.nan
        p=self.parameters(); p["minimum_trials"]=1
        result=worker.run(self.request(values,parameters=p))
        self.assertEqual([e["reason"] for e in result["events"]],["amplitude_rejection","missing_gap_annotation_or_filter_edge",None])
        self.assertEqual(result["recordings"][0]["retained_trials"],1)
        self.assertTrue(all(v is None for v in result["series"][0]["sem_uv"]))
        p["rejection"]["flat_uv"]=.1
        flat=worker.run(self.request(np.ones(1100),parameters=p))
        self.assertEqual(flat["status"],"insufficient_support"); self.assertEqual(flat["features"],[])
        self.assertEqual(flat["events"][0]["channels"][0]["reason"],"flat")

    def test_timestamp_gap_never_becomes_epoch_support(self):
        times=np.arange(1100)/100; times[215:]+=.2
        events=[{"time_s":2,"code":"A"},{"time_s":5.2,"code":"A"},{"time_s":8.2,"code":"A"}]
        result=worker.run(self.request(self.pulse(),times=times,events=events))
        self.assertEqual(result["events"][0]["reason"],"missing_gap_annotation_or_filter_edge")
        self.assertEqual(result["recordings"][0]["retained_trials"],2)

    def test_averaged_and_named_reference(self):
        values=np.column_stack([self.pulse(),np.full(1100,5.)])
        p=self.parameters(); p["reference"]={"mode":"average","source":"Explicit two-channel synthetic reference"}
        average=worker.run(self.request(values,parameters=p))
        self.assertAlmostEqual(self.features(average,"erp_mean_amplitude")[0]["value"],5)
        self.assertAlmostEqual(self.features(average,"erp_mean_amplitude",channel="channel-1")[0]["value"],-5)
        p["reference"]={"mode":"channels","channels":["channel-1"],"source":"Explicit synthetic reference electrode"}
        named=worker.run(self.request(values,parameters=p))
        self.assertAlmostEqual(self.features(named,"erp_mean_amplitude")[0]["value"],10)

    def test_reference_zero_does_not_invent_source_flatline(self):
        t=np.arange(1100)/100; reference=3*np.sin(2*np.pi*4*t)
        p=self.parameters();p["reference"]={"mode":"channels","channels":["channel-1"],"source":"Known variable reference signal"}
        p["rejection"]["flat_uv"]=.1
        result=worker.run(self.request(np.column_stack([self.pulse()+reference,reference]),parameters=p))
        self.assertEqual(result["recordings"][0]["retained_trials"],3)
        self.assertAlmostEqual(self.features(result,"erp_mean_amplitude")[0]["value"],10)

    def test_negative_peak_requires_negative_polarity(self):
        p=self.parameters(); p["peak_polarity"]="negative"
        absent=worker.run(self.request(self.pulse(),parameters=p))
        self.assertIsNone(self.features(absent,"erp_peak_amplitude")[0]["value"])
        present=worker.run(self.request(self.pulse(-10),parameters=p))
        self.assertAlmostEqual(self.features(present,"erp_peak_amplitude")[0]["value"],-10)

    def test_condition_trials_and_recordings_do_not_become_people(self):
        values=np.r_[self.pulse(),self.pulse(20)]
        groups={"participant":["p1"]*1100+["p2"]*1100,"session":["s1"]*2200}
        events=[{"recording_id":f"recording-{r}","time_s":t,"code":"A"} for r in [1,2] for t in [2,5,8]]
        result=worker.run(self.request(values,events=events,groups=groups,times=np.tile(np.arange(1100)/100,2)))
        features=self.features(result,"erp_mean_amplitude")
        self.assertEqual([f["group"]["participant_id"] for f in features],["p1","p2"])
        self.assertTrue(all(f["trial_count"]==3 and f["scope"]=="recording_condition" for f in features))
        np.testing.assert_allclose([f["value"] for f in features],[10,20])

    def test_marker_mapping_must_match_declared_recording_condition(self):
        request=self.request(self.pulse(),groups={"condition":["wrong"]*1100})
        with self.assertRaisesRegex(worker.InputError,"disagrees"): worker.run(request)

    def test_epoch_overlap_and_missing_events_are_not_silent(self):
        events=[{"time_s":2,"code":"A"},{"time_s":2.1,"code":"A"},{"time_s":5,"code":"Z"},{"time_s":10.9,"code":"A"}]
        result=worker.run(self.request(self.pulse(),events=events))
        self.assertEqual([e["reason"] for e in result["events"]],[None,"overlapping_epoch","unmapped_event_code","epoch_outside_recording"])
        request=self.request(self.pulse()); request["metadata"]["event_column"]="event"
        with self.assertRaisesRegex(worker.InputError,"exactly one"): worker.run(request)

    def test_event_grid_tolerance_and_repeated_samples(self):
        p=self.parameters(); p["event_tolerance_s"]=.001
        result=worker.run(self.request(self.pulse(),parameters=p,events=[{"time_s":2.004,"code":"A"},{"time_s":5,"code":"A"},{"time_s":8,"code":"A"}]))
        self.assertEqual(result["events"][0]["reason"],"event_outside_sample_alignment_tolerance")
        p["event_tolerance_s"]=.005; p["overlap_policy"]="allow"
        with self.assertRaisesRegex(worker.InputError,"same source sample"):
            worker.run(self.request(self.pulse(),parameters=p,events=[{"time_s":2,"code":"A"},{"time_s":2.001,"code":"A"}]))

    def test_strict_settings_units_rate_and_order(self):
        for update in [{"invented":True},{"settings_source":""},{"epoch_s":[-.205,.6]},{"minimum_trials":False}]:
            p=self.parameters(); p.update(update)
            with self.assertRaises(worker.InputError): worker.run(self.request(self.pulse(),parameters=p))
        for update in [{"unit":"unknown"},{"sampling_rate":90},{"events":[{"time_s":5,"code":"A"},{"time_s":2,"code":"A"}]}]:
            request=self.request(self.pulse()); request["metadata"].update(update)
            with self.assertRaises(worker.InputError): worker.run(request)

    def test_big_timestamp_origin_preserved_before_float_conversion(self):
        origin=9007199254740993123
        request=self.request(self.pulse(),times=[str(origin+i*10000000) for i in range(1100)])
        request["metadata"]["time_unit"]="ns"
        result=worker.run(request)
        self.assertEqual(result["recordings"][0]["source_time_origin"],str(origin))
        self.assertAlmostEqual(self.features(result,"erp_mean_amplitude")[0]["value"],10)

    def test_explicit_filter_has_edges_and_does_not_bridge_missing(self):
        p=self.parameters(); p["filter"]={"mode":"butterworth_bandpass","low_hz":1,"high_hz":30,"order":2,"edge_exclusion_s":3}
        result=worker.run(self.request(self.pulse(),parameters=p))
        self.assertEqual(result["events"][0]["reason"],"missing_gap_annotation_or_filter_edge")
        self.assertIsNotNone(result["recordings"][0]["quality"]["filter_sos"])
        values=self.pulse(); values[550]=np.nan
        lost=worker.run(self.request(values,parameters=p))
        self.assertEqual(lost["status"],"insufficient_support")
        self.assertEqual(len(lost["recordings"][0]["quality"]["continuous_spans"]),2)

    def sine_request(self,recipe,phase_reverse=False):
        fs=100; t=np.arange(1800)/fs
        values=20*np.sin(2*np.pi*10*t)
        if phase_reverse: values[600:1100]*=-1
        return self.request(values,fs=fs,events=[{"time_s":3,"code":"A"},{"time_s":8,"code":"A"},{"time_s":13,"code":"A"}],parameters=self.parameters(recipe))

    def test_morlet_known_stationary_sine_ratio_phase_and_axes(self):
        result=worker.run(self.sine_request("eeg-morlet-epochs/1.0"))
        power=self.features(result,"morlet_power_mean"); phase=self.features(result,"morlet_itc_mean")
        self.assertAlmostEqual(power[0]["value"],1,places=7)
        self.assertAlmostEqual(phase[0]["value"],1,places=10)
        series=result["series"][0]
        self.assertEqual(np.asarray(series["power_uv2"]).shape,(2,len(series["time_s"])))
        # Three-cycle wavelets have broad frequency support; they need not
        # suppress the off-target octave by 100-fold.
        self.assertTrue(np.mean(series["power_uv2"][0])>10*np.mean(series["power_uv2"][1]))
        self.assertTrue(all(-2<t<2 for t in series["time_s"]))
        json.dumps(result,allow_nan=False)

    def test_morlet_opposed_trial_phase_and_induced_removal(self):
        request=self.sine_request("eeg-morlet-epochs/1.0",phase_reverse=True)
        result=worker.run(request)
        self.assertAlmostEqual(self.features(result,"morlet_itc_mean")[0]["value"],1/3,places=8)
        request=self.sine_request("eeg-morlet-epochs/1.0")
        request["parameters"]["power"]="induced"; request["parameters"]["power_baseline"]={"mode":"none"}
        induced=worker.run(request)
        self.assertLess(self.features(induced,"morlet_power_mean")[0]["value"],1e-18)

    def test_morlet_zero_signal_has_no_denominator_or_itc(self):
        request=self.sine_request("eeg-morlet-epochs/1.0")
        request=self.request(np.zeros(1800),events=request["metadata"]["events"],parameters=request["parameters"])
        result=worker.run(request)
        self.assertIsNone(self.features(result,"morlet_power_mean")[0]["value"])
        self.assertIsNone(self.features(result,"morlet_itc_mean")[0]["value"])

    def test_morlet_wavelet_edge_baseline_is_unavailable(self):
        request=self.sine_request("eeg-morlet-epochs/1.0")
        request["parameters"]["power_baseline"]["window_s"]=[-2,-1.9]
        result=worker.run(request)
        self.assertEqual(result["status"],"insufficient_support")
        self.assertIn("wavelet support",result["recordings"][0]["reason"])

    def test_reviewed_morlet_stationary_oracle_and_exact_diagnostics(self):
        request=self.sine_request("eeg-morlet-epochs/1.1")
        result=worker.run(request); support=result["recordings"][0]["derived_settings"]["baseline_support"]
        self.assertAlmostEqual(self.features(result,"morlet_power_mean")[0]["value"],1,places=7)
        self.assertEqual(support["status"],"eligible"); self.assertEqual(support["baseline_sample_count"],51)
        self.assertEqual(support["sample_span_s"],.5); self.assertEqual(support["cycles_at_lowest_frequency"],5)
        self.assertEqual([r["baseline_cycles"] for r in support["frequencies"]],[5,10])
        self.assertAlmostEqual(support["frequencies"][0]["temporal_sigma_s"],3/(20*np.pi))
        self.assertEqual(support["frequencies"][0]["latest_kernel_sample_s"],-.27)
        self.assertIn("zero-phase",support["scope"]); self.assertFalse(result["quality"]["scientifically_qualified"])
        self.assertEqual(request["parameters"]["power_baseline"]["window_s"],[-1,-.5])

    def test_event_only_impulse_reveals_legacy_leakage_and_new_refusal(self):
        # A zero pre-event signal with a 10-uV onset impulse is an independent
        # oracle: every strictly pre-event input is zero. A two-sample baseline
        # near onset nevertheless receives convolution energy in recipe 1.0.
        request=self.sine_request("eeg-morlet-epochs/1.0"); values=np.zeros(1800)
        values[[300,800,1300]]=10
        p=request["parameters"]; p["power_baseline"]["window_s"]=[-.02,-.01]
        p["power_baseline"]["minimum_power_uv2"]=1e-12
        request=self.request(values,events=request["metadata"]["events"],parameters=p)
        legacy=worker.run(request); s=legacy["series"][0]
        before=np.array(s["time_s"])<0
        self.assertGreater(np.max(np.array(s["power_uv2"])[0,before]),.01)
        self.assertIsNotNone(self.features(legacy,"morlet_power_mean")[0]["value"])
        request["parameters"]["recipe"]="eeg-morlet-epochs/1.1"
        request["parameters"]["power_baseline"]["adequacy"]={"policy":worker.BASELINE_POLICY,"minimum_cycles":.1,"rationale":"Deliberately short contamination test; no scientific duration recommendation."}
        rejected=worker.run(request); d=rejected["recordings"][0]["derived_settings"]["baseline_support"]
        self.assertEqual(rejected["status"],"insufficient_support"); self.assertTrue(d["duration_criterion_met"])
        self.assertFalse(d["frequencies"][0]["strictly_before_event"])
        self.assertIn("earlier baseline",rejected["recordings"][0]["reason"])
        request["parameters"]["power_baseline"]["window_s"]=[-1,-.5]
        clean=worker.run(request); s=clean["series"][0]; b=(np.array(s["time_s"])>=-1)&(np.array(s["time_s"])<=-.5)
        self.assertLess(np.max(np.array(s["power_uv2"])[:,b]),1e-20)
        self.assertGreater(np.max(s["power_uv2"][0]),.01)
        self.assertTrue(all(v is None for v in s["transformed_power"][0])) # no positive denominator invented

    def test_exact_kernel_onset_boundary_and_duration_are_separate(self):
        request=self.sine_request("eeg-morlet-epochs/1.1"); b=request["parameters"]["power_baseline"]
        b["adequacy"]["minimum_cycles"]=2; b["window_s"]=[-.5,-.23]
        touched=worker.run(request); d=touched["recordings"][0]["derived_settings"]["baseline_support"]
        self.assertEqual(d["frequencies"][0]["latest_kernel_sample_s"],0)
        self.assertEqual(touched["status"],"insufficient_support")
        b["window_s"]=[-.5,-.24]
        self.assertTrue(worker.run(request)["quality"]["usable"])
        b["window_s"]=[-1.005,-.5]; b["adequacy"]["minimum_cycles"]=5.01
        short=worker.run(request); d=short["recordings"][0]["derived_settings"]["baseline_support"]
        self.assertEqual(d["sample_span_s"],.5); self.assertEqual(d["cycles_at_lowest_frequency"],5)
        self.assertFalse(d["duration_criterion_met"]); self.assertTrue(d["frequencies"][0]["strictly_before_event"])

    def test_every_frequency_support_is_checked_not_only_lowest(self):
        request=self.sine_request("eeg-morlet-epochs/1.1")
        request["parameters"]["n_cycles"]=[1,30]
        b=request["parameters"]["power_baseline"]; b["adequacy"]["minimum_cycles"]=1; b["window_s"]=[-.7,-.5]
        result=worker.run(request); d=result["recordings"][0]["derived_settings"]["baseline_support"]
        self.assertTrue(d["frequencies"][0]["strictly_before_event"])
        self.assertFalse(d["frequencies"][1]["strictly_before_event"])
        self.assertEqual(result["status"],"insufficient_support")

    def test_reviewed_epoch_edges_and_no_baseline_remediation(self):
        request=self.sine_request("eeg-morlet-epochs/1.1")
        request["parameters"]["power_baseline"]["window_s"]=[-2,-1.5]
        result=worker.run(request); d=result["recordings"][0]["derived_settings"]["baseline_support"]
        self.assertFalse(d["frequencies"][0]["complete_epoch_support"])
        self.assertTrue(d["duration_criterion_met"]); self.assertEqual(result["status"],"insufficient_support")
        request["parameters"]["power_baseline"]={"mode":"none"}
        result=worker.run(request)
        self.assertEqual(result["recordings"][0]["derived_settings"]["baseline_support"]["status"],"not_applied")
        self.assertGreater(self.features(result,"morlet_power_mean")[0]["value"],0)

    def test_new_duration_contract_is_required_and_legacy_is_not_rescored(self):
        for a in [None,{}, {"policy":worker.BASELINE_POLICY,"minimum_cycles":0,"rationale":"reason"},
                  {"policy":worker.BASELINE_POLICY,"minimum_cycles":True,"rationale":"reason"},
                  {"policy":"invented","minimum_cycles":4,"rationale":"reason"},
                  {"policy":worker.BASELINE_POLICY,"minimum_cycles":4,"rationale":" "}]:
            request=self.sine_request("eeg-morlet-epochs/1.1")
            if a is None: request["parameters"]["power_baseline"].pop("adequacy")
            else: request["parameters"]["power_baseline"]["adequacy"]=a
            with self.assertRaises(worker.InputError): worker.run(request)
        legacy=worker.run(self.sine_request("eeg-morlet-epochs/1.0"))
        self.assertNotIn("baseline_support",legacy["recordings"][0]["derived_settings"])
        self.assertEqual(legacy["parameters"]["recording-1"]["recipe"],"eeg-morlet-epochs/1.0")

    def test_morlet_db_is_ten_log_power_ratio_after_averaging(self):
        fs=100; times=np.arange(1800)/fs; amplitude=np.full(1800,10.)
        for onset in [3,8,13]: amplitude[(times>=onset)&(times<=onset+2)]=20
        values=amplitude*np.sin(2*np.pi*10*times)
        p=self.parameters("eeg-morlet-epochs/1.0")
        p["summary_window_s"]=[.5,1];p["power_baseline"]["mode"]="db"
        result=worker.run(self.request(values,events=[{"time_s":t,"code":"A"} for t in [3,8,13]],parameters=p))
        # Doubling amplitude quadruples power: 10 log10(4), not log10(4).
        self.assertAlmostEqual(self.features(result,"morlet_power_mean")[0]["value"],10*np.log10(4),delta=1e-6)

    def test_frequency_tagging_known_sine_density(self):
        result=worker.run(self.sine_request("eeg-frequency-tagging/1.0"))
        # A=20 uV sine has variance A^2/2=200 uV^2. Two seconds gives
        # 0.5-Hz bins: exact boxcar target density is 200/0.5=400 uV^2/Hz.
        self.assertAlmostEqual(self.features(result,"tag_bin_density")[0]["value"],400,places=8)
        series=result["series"][0]
        self.assertAlmostEqual(sum(series["density_uv2_hz"])*.5,200,places=8)
        self.assertEqual(self.features(result,"tag_bin_density")[0]["actual_bin_hz"],10)

    def test_frequency_tagging_noise_snr_and_colliding_neighbors(self):
        fs=100;t=np.arange(1800)/fs
        values=20*np.sin(2*np.pi*10*t)
        for f in [8.5,9,11,11.5]: values+=2*np.sin(2*np.pi*f*t)
        p=self.parameters("eeg-frequency-tagging/1.0")
        request=self.request(values,events=[{"time_s":t,"code":"A"} for t in [3,8,13]],parameters=p)
        result=worker.run(request)
        self.assertAlmostEqual(self.features(result,"tag_snr")[0]["value"],100,places=8)
        request["parameters"]["tag_frequencies_hz"]=[10,11]
        collision=worker.run(request)
        self.assertTrue(all(f["value"] is None for f in self.features(collision,"tag_snr")))

    def test_frequency_resolution_mismatch_and_zero_noise(self):
        request=self.sine_request("eeg-frequency-tagging/1.0");request["parameters"]["tag_frequencies_hz"]=[10.1]
        result=worker.run(request)
        self.assertEqual(result["status"],"insufficient_support");self.assertIn("bin tolerance",result["recordings"][0]["reason"])
        request=self.sine_request("eeg-frequency-tagging/1.0")
        zeros=worker.run(self.request(np.zeros(1800),events=request["metadata"]["events"],parameters=request["parameters"]))
        self.assertIsNone(self.features(zeros,"tag_snr")[0]["value"])

    def test_native_fif_units_first_sample_annotations_and_header_rate(self):
        import mne
        raw=mne.io.RawArray(self.pulse()[None]*1e-6,mne.create_info(["Cz"],100,ch_types="eeg"),first_samp=1234,verbose=False)
        raw.set_annotations(mne.Annotations([5.2],[.1],["BAD synthetic artifact"]))
        path=self.root/"synthetic_raw.fif";raw.save(path,overwrite=True,fmt="double",verbose=False)
        request={"schema":"brohn-worker-request/1.0","operation":"neural","modality":"eeg","source_path":str(path),"format":"fif",
            "metadata":{"value_columns":["Cz"],"unit":"native","sampling_rate":100,"origin":"sample","participant_id":"synthetic","session_id":"s1",
                        "events":[{"time_s":t,"code":"A"} for t in [2,5,8]]},"parameters":self.parameters()}
        result=worker.run(request)
        self.assertAlmostEqual(self.features(result,"erp_mean_amplitude",channel="Cz")[0]["value"],10,places=8)
        self.assertEqual(result["source"]["native_first_sample"],1234)
        self.assertEqual(result["events"][0]["source_sample_index"],1434)
        self.assertEqual(result["events"][1]["reason"],"missing_gap_annotation_or_filter_edge")
        request["metadata"]["sampling_rate"]=101
        with self.assertRaisesRegex(worker.InputError,"header"): worker.run(request)

    def test_native_edf_bdf_physical_header_scaling(self):
        # Minimal independently generated calibrated files: one 100-Hz EEG
        # channel, eleven one-second records. No export library rescales them.
        def field(value,width): return str(value).encode("ascii").ljust(width,b" ")
        for extension,bits in [("edf",16),("bdf",24)]:
            digital_min=-(2**(bits-1));digital_max=2**(bits-1)-1
            version=field("0",8) if extension=="edf" else b"\xffBIOSEMI"
            header=version+field("synthetic",80)+field("independent fixture",80)+field("01.01.24",8)+field("00.00.00",8)+field(512,8)+field("",44)+field(11,8)+field(1,8)+field(1,4)
            header+=field("Cz",16)+field("",80)+field("uV",8)+field(-100,8)+field(100,8)+field(digital_min,8)+field(digital_max,8)+field("",80)+field(100,8)+field("",32)
            self.assertEqual(len(header),512)
            digital=np.rint((self.pulse()+100)/200*(digital_max-digital_min)+digital_min).astype(np.int64)
            payload=digital.astype("<i2").tobytes() if bits==16 else np.column_stack([digital&255,(digital>>8)&255,(digital>>16)&255]).astype(np.uint8).tobytes()
            path=self.root/f"synthetic.{extension}";path.write_bytes(header+payload)
            request={"schema":"brohn-worker-request/1.0","operation":"neural","modality":"eeg","source_path":str(path),"format":extension,
                "metadata":{"value_columns":["Cz"],"unit":"native","sampling_rate":100,"origin":"sample","events":[{"time_s":t,"code":"A"} for t in [2,5,8]]},"parameters":self.parameters()}
            result=worker.run(request)
            self.assertAlmostEqual(self.features(result,"erp_mean_amplitude",channel="Cz")[0]["value"],10,delta=.005)
            self.assertEqual(result["source"]["amplitude_scaling"],"validated file header to volts")

    def test_source_immutability_atomic_cli_and_structured_errors(self):
        request=self.request(self.pulse()); source=Path(request["source_path"]); original=source.read_bytes()
        path=self.root/"request.json";output=self.root/"result.json";path.write_text(json.dumps(request))
        done=subprocess.run([sys.executable,str(ROOT/"scripts"/"workers"/"neural.py"),"--request",str(path),"--output",str(output)],capture_output=True,text=True)
        self.assertEqual(done.returncode,0,done.stderr);self.assertEqual(json.loads(output.read_text())["schema"],"brohn-worker-result/1.0")
        self.assertEqual(original,source.read_bytes())
        request["operation"]="arbitrary";path.write_text(json.dumps(request))
        failed=subprocess.run([sys.executable,str(ROOT/"scripts"/"workers"/"neural.py"),"--request",str(path),"--output",str(output)],capture_output=True,text=True)
        self.assertEqual(failed.returncode,2);self.assertEqual(json.loads(output.read_text())["status"],"error")
        self.assertFalse(list(self.root.glob(".brohn-neural-*")))


if __name__=="__main__": unittest.main(verbosity=2)
