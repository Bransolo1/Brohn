"""Worker wiring, independent numerical and boundary tests; no empirical device qualification."""
import csv
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

import numpy as np
from scipy import signal

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("brohn_physiology", ROOT / "scripts" / "workers" / "physiology.py")
worker = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(worker)

RESPIRATION_DECLARATION = {"recipe": "respiration-displacement-khodadad/1.0", "source_quantity": "belt_displacement",
                           "polarity": "positive_inspiration", "mapping_source": "Original synthetic displacement: increases for inspiration; no physical device."}


class PhysiologyTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="brohn-worker-test-")
        self.root = Path(self.directory.name)

    def tearDown(self):
        self.directory.cleanup()

    def request(self, modality, values, fs=100, unit=None, times=None, groups=None, parameters=None):
        path = self.root / f"{modality}.csv"
        values = np.asarray(values)
        if values.ndim == 1: values = values[:, None]
        names = [f"channel-{i}" for i in range(values.shape[1])]
        times = np.arange(len(values))/fs if times is None else times
        with path.open("w", newline="", encoding="utf-8") as stream:
            writer = csv.writer(stream)
            writer.writerow(["time", *names, *(groups or {})])
            for i, row in enumerate(values):
                writer.writerow([times[i], *["NA" if not np.isfinite(v) else v for v in row], *[group[i] for group in (groups or {}).values()]])
        metadata = {"time_column": "time", "time_unit": "s", "sampling_rate": fs, "value_columns": names,
                    "unit": unit or {"eda": "uS", "eeg": "uV", "ecg": "mV", "ppg": "a.u.", "respiration": "a.u.", "emg": "uV"}[modality]}
        metadata.update({name + "_column": name for name in groups or {}})
        return {"schema": "brohn-worker-request/1.0", "operation": "physiology", "modality": modality,
                "source_path": str(path), "format": "csv", "metadata": metadata, "parameters": parameters or {}}

    @staticmethod
    def feature(result, name, channel="channel-0", occurrence=0):
        return [item for item in result["features"] if item["name"] == name and item["channel"] == channel][occurrence]["value"]

    def test_eeg_known_sine_units_and_psd(self):
        fs = 256; times = np.arange(fs*20)/fs
        values = np.column_stack([20*np.sin(2*np.pi*10*times), 10*np.sin(2*np.pi*5*times)])
        result = worker.run(self.request("eeg", values, fs=fs))
        self.assertEqual(result["status"], "completed")
        self.assertAlmostEqual(self.feature(result, "psd_total_power"), 200, places=8)
        self.assertAlmostEqual(self.feature(result, "alpha_absolute_power"), 200, places=8)
        self.assertAlmostEqual(self.feature(result, "alpha_relative_power"), 1, places=10)
        self.assertEqual(self.feature(result, "psd_peak_frequency"), 10)
        self.assertAlmostEqual(self.feature(result, "theta_absolute_power", "channel-1"), 50, places=8)
        self.assertLessEqual(len(result["series"]), 2000)
        self.assertGreater(result["quality"]["series_samples_total"], len(result["series"]))
        json.dumps(result, allow_nan=False)

    def test_voltage_scaling_equivalence(self):
        fs = 256; times = np.arange(fs*10)/fs
        uv = 12*np.sin(2*np.pi*10*times)
        first = worker.run(self.request("eeg", uv, fs=fs, unit="uV"))
        second = worker.run(self.request("eeg", uv*1e-6, fs=fs, unit="V"))
        self.assertAlmostEqual(self.feature(first, "alpha_absolute_power"), self.feature(second, "alpha_absolute_power"), places=10)

    def test_group_boundaries_do_not_mix_participants(self):
        fs=100; times=np.arange(fs*12)/fs
        values=np.r_[10*np.sin(2*np.pi*10*times[:600]), 30*np.sin(2*np.pi*10*times[600:])]
        request=self.request("eeg", values, fs, groups={"participant": ["p1"]*600+["p2"]*600, "condition": ["A"]*1200})
        result=worker.run(request)
        features=[item for item in result["features"] if item["name"]=="alpha_absolute_power"]
        self.assertEqual([item["group"]["participant_id"] for item in features], ["p1", "p2"])
        self.assertAlmostEqual(features[0]["value"], 50, places=8)
        self.assertAlmostEqual(features[1]["value"], 450, places=8)
        self.assertTrue(all(item["scope"]=="recording" for item in features))

    def test_missing_and_time_gaps_split_without_concatenation(self):
        fs=100; times=np.arange(1800)/fs; values=np.sin(2*np.pi*10*times)
        values[600:620]=np.nan; times[1200:]+=5
        result=worker.run(self.request("eeg", values, fs, times=times))
        self.assertEqual(result["quality"]["computed_channel_segments"], 3)
        self.assertEqual(result["quality"]["missing_channel_samples"], 20)
        self.assertEqual([item["source_row_start"] for item in result["recordings"]], [0,620,1200])
        self.assertEqual(result["recordings"][0]["channel_quality"]["time_gap_count"], 1)

    def test_explicit_clock_segments_preserve_people_and_independent_spectra(self):
        fs = 100; t = np.arange(1200)/fs
        values = np.r_[20*np.sin(2*np.pi*10*t), 10*np.sin(2*np.pi*20*t)]
        request = self.request("eeg", values, fs, times=np.r_[t, t], groups={
            "participant": ["same-person"]*2400, "session": ["same-visit"]*2400,
            "segment": ["before-reset"]*1200+["after-reset"]*1200})
        result = worker.run(request)
        peaks = [r for r in result["features"] if r["name"] == "psd_peak_frequency"]
        powers = [r for r in result["features"] if r["name"] == "psd_total_power"]
        self.assertEqual([r["value"] for r in peaks], [10, 20])
        self.assertEqual([r["group"]["segment_id"] for r in peaks], ["before-reset", "after-reset"])
        self.assertTrue(all(r["group"]["participant_id"] == "same-person" and
                            r["group"]["session_id"] == "same-visit" and "exposure_id" not in r["group"] for r in peaks))
        self.assertAlmostEqual(powers[0]["value"], 200, places=8)
        self.assertAlmostEqual(powers[1]["value"], 50, places=8)

    def test_segment_identity_cannot_alias_clock_or_participant(self):
        request = self.request("eeg", np.zeros(600), 100, groups={"participant": ["person"]*600})
        request["metadata"]["segment_column"] = "participant"
        with self.assertRaisesRegex(worker.InputError, "must be distinct"):
            worker.run(request)
        request["metadata"]["segment_column"] = "time"
        with self.assertRaisesRegex(worker.InputError, "must be distinct"):
            worker.run(request)

    def test_large_nanosecond_tick_origin_is_not_rounded(self):
        fs=100; values=np.sin(2*np.pi*10*np.arange(600)/fs)
        origin=9007199254740993123
        request=self.request("eeg", values, fs, times=[str(origin+i*10_000_000) for i in range(600)])
        request["metadata"]["time_unit"]="ns"
        result=worker.run(request)
        self.assertEqual(result["recordings"][0]["source_time_origin"], str(origin))
        self.assertAlmostEqual(result["recordings"][0]["end_time_s"], 5.99)

    def test_irregular_timing_and_unknown_units_rejected(self):
        request=self.request("eeg", np.ones(600), 100)
        request["metadata"]["sampling_rate"]=120
        with self.assertRaisesRegex(worker.InputError, "irregular sampling"):
            worker.run(request)
        request["metadata"]["sampling_rate"]=100; request["metadata"]["unit"]="unknown"
        with self.assertRaisesRegex(worker.InputError, "Unsupported or missing"):
            worker.run(request)

    def test_short_support_unavailable_without_zero_metrics(self):
        result=worker.run(self.request("eda", np.ones(1000), 100))
        self.assertEqual(result["status"], "insufficient_support")
        self.assertFalse(result["quality"]["usable"])
        self.assertEqual(result["features"], [])
        self.assertIn("too short", result["recordings"][0]["reason"])

    def test_rr_statistics_independent_and_no_bridge_over_rejection(self):
        p=worker.parameters("ecg", {}, 1000)
        intervals=np.tile([800,1000,1200,1000], 100)
        peaks=np.r_[0,np.cumsum(intervals)]
        features, _, valid=worker.interval_metrics(peaks, 1000, p, "rr")
        result={item["name"]:item for item in features}
        self.assertAlmostEqual(result["rr_mean_interval"]["value"],1000)
        self.assertAlmostEqual(result["rr_sd_interval"]["value"],np.std(intervals,ddof=1))
        self.assertAlmostEqual(result["rr_rmssd"]["value"],200)
        self.assertEqual(result["rr_pnn50_candidate"]["value"],99.75)
        interrupted=np.array([800,1000,4000,1200,1000])
        features,_,valid=worker.interval_metrics(np.r_[0,np.cumsum(interrupted)],1000,p,"rr")
        result={item["name"]:item["value"] for item in features}
        self.assertEqual(result["rr_successive_pair_count"],2)
        self.assertEqual(result["rr_rmssd"],200)
        self.assertIsNone(result["rr_lf_power_candidate"])

    def test_eda_model_smoke_scaling_morphology_and_missingness(self):
        fs=100; t=np.arange(fs*70)/fs
        x=np.ones(len(t))*3
        for onset in [15,30,45]:
            elapsed=t-onset
            x+=np.where(elapsed>=0, .8*(np.exp(-np.maximum(elapsed,0)/2)-np.exp(-np.maximum(elapsed,0)/.5)),0)
        first=worker.run(self.request("eda",x,fs))
        second=worker.run(self.request("eda",x/1e6,fs,unit="S"))
        self.assertEqual(first["status"],"completed")
        self.assertGreater(self.feature(first,"scr_count"),0)
        self.assertAlmostEqual(self.feature(first,"tonic_mean"),self.feature(second,"tonic_mean"),places=7)
        self.assertTrue(all(event["recovery_fraction"]==.5 for event in first["events"]))
        self.assertTrue(all(event["amplitude_us"] is None or event["amplitude_us"]>=0 for event in first["events"]))
        self.assertEqual(first["parameters"]["recording-1"]["threshold_definition"],"candidate_prominence_relative_to_maximum_prominence")

    def test_emg_rms_against_known_sine_filter_response(self):
        fs=1000; t=np.arange(fs*10)/fs; amplitude=20.; frequency=100.
        parameters={"highpass_hz":20.,"lowpass_hz":400.,"edge_exclusion_s":1.}
        result=worker.run(self.request("emg",amplitude*np.sin(2*np.pi*frequency*t),fs,parameters=parameters))
        sos=signal.butter(4,[20,400],btype="bandpass",fs=fs,output="sos")
        _,response=signal.sosfreqz(sos,worN=[frequency],fs=fs)
        expected=amplitude/np.sqrt(2)*abs(response[0])**2
        self.assertAlmostEqual(self.feature(result,"emg_rms"),expected,places=5)
        self.assertAlmostEqual(self.feature(result,"emg_mean_frequency"),100,places=3)
        self.assertFalse(any(item["name"]=="emg_burst_count" for item in result["features"]))

    def test_ecg_ppg_respiration_execution_smokes(self):
        import neurokit2 as nk
        fs=100; duration=60
        ecg=nk.ecg_simulate(duration=duration,sampling_rate=fs,heart_rate=70,noise=0,random_state=42)
        ppg=nk.ppg_simulate(duration=duration,sampling_rate=fs,heart_rate=70,frequency_modulation=0,ibi_randomness=0,drift=0,motion_amplitude=0,powerline_amplitude=0,burst_amplitude=0,random_state=42)
        rsp=np.sin(2*np.pi*.2*np.arange(fs*duration)/fs)
        for modality,values in [("ecg",ecg),("ppg",ppg),("respiration",rsp)]:
            result=worker.run(self.request(modality,values,fs,parameters=RESPIRATION_DECLARATION if modality == "respiration" else None))
            self.assertEqual(result["status"],"completed",str(result["recordings"]))
            self.assertTrue(result["events"])
        self.assertAlmostEqual(self.feature(result,"respiration_rate"),12,places=1)

    def test_native_fif_header_scaling_and_bad_annotations(self):
        import mne
        fs=100; t=np.arange(fs*20)/fs
        raw=mne.io.RawArray((20e-6*np.sin(2*np.pi*10*t))[None,:],mne.create_info(["Cz"],fs,"eeg"),verbose=False)
        raw.set_annotations(mne.Annotations([8],[2],["BAD motion"]))
        source=self.root/"synthetic_raw.fif"; raw.save(source,overwrite=True,verbose=False)
        result=worker.run({"schema":"brohn-worker-request/1.0","operation":"physiology","modality":"eeg","source_path":str(source),"format":"fif","metadata":{"value_columns":["Cz"],"unit":"native","sampling_rate":100}})
        self.assertEqual(result["quality"]["computed_channel_segments"],2)
        self.assertEqual(result["quality"]["missing_channel_samples"],200)
        self.assertAlmostEqual(self.feature(result,"alpha_absolute_power","Cz"),200,places=4)
        self.assertEqual(result["source"]["annotation_count"],1)

    def test_respiration_asymmetric_volume_and_declared_inversion(self):
        # Independent physical construction: volume rises for exactly 2 s and
        # falls for 3 s. Its flow extrema at 1 and 3.5 s are not phase onsets.
        fs=100; t=np.arange(fs*120)/fs; phase=t % 5
        volume=np.where(phase < 2, (1-np.cos(np.pi*phase/2))/2,
                        (1+np.cos(np.pi*(phase-2)/3))/2)
        settings={**RESPIRATION_DECLARATION,"source_quantity":"lung_volume","edge_exclusion_s":20}
        positive=worker.run(self.request("respiration",volume,fs,unit="L",parameters=settings))
        negative=worker.run(self.request("respiration",-volume,fs,unit="L",parameters={**settings,"polarity":"negative_inspiration"}))
        self.assertAlmostEqual(self.feature(positive,"respiration_rate"),12,delta=.02)
        self.assertAlmostEqual(self.feature(positive,"inspiration_duration"),2,delta=.04)
        self.assertAlmostEqual(self.feature(positive,"expiration_duration"),3,delta=.04)
        self.assertAlmostEqual(self.feature(positive,"inspiration_expiration_ratio"),2/3,delta=.02)
        self.assertEqual(positive["features"],negative["features"])
        self.assertEqual(positive["events"],negative["events"])
        np.testing.assert_array_equal([v["raw"] for v in negative["series"]],[-v["raw"] for v in positive["series"]])
        np.testing.assert_array_equal([v["clean"] for v in negative["series"]],[v["clean"] for v in positive["series"]])
        self.assertEqual(next(iter(negative["parameters"].values()))["source_polarity_multiplier"],-1)

    def test_respiration_flow_derivative_cannot_be_interpreted_as_volume(self):
        fs=100; t=np.arange(fs*60)/fs; phase=t % 5
        flow=np.where(phase<2,np.pi/4*np.sin(np.pi*phase/2),-np.pi/6*np.sin(np.pi*(phase-2)/3))
        self.assertEqual(t[np.argmax(flow[:500])],1)
        self.assertEqual(t[np.argmin(flow[:500])],3.5)
        with self.assertRaisesRegex(worker.InputError,"Unsupported.*unit"):
            worker.run(self.request("respiration",flow,fs,unit="L/s",parameters={**RESPIRATION_DECLARATION,"source_quantity":"lung_volume"}))
        with self.assertRaisesRegex(worker.InputError,"Airflow"):
            worker.run(self.request("respiration",flow,fs,parameters={**RESPIRATION_DECLARATION,"source_quantity":"airflow"}))

    def test_respiration_old_or_unspecified_mapping_needs_explicit_review(self):
        x=np.sin(2*np.pi*.2*np.arange(6000)/100)
        for settings in ({},{"recipe":"respiration-khodadad-cycles/1.0"},
                         {**RESPIRATION_DECLARATION,"polarity":None},
                         {**RESPIRATION_DECLARATION,"mapping_source":" "},
                         {**RESPIRATION_DECLARATION,"source_quantity":"lung_volume"}):
            with self.subTest(settings=settings), self.assertRaises(worker.InputError):
                worker.run(self.request("respiration",x,parameters=settings))

    def test_cli_atomic_json_and_error_exit(self):
        fs=100; t=np.arange(fs*6)/fs
        request=self.request("eeg",np.sin(2*np.pi*10*t),fs)
        req=self.root/"request.json"; out=self.root/"result.json"
        req.write_text(json.dumps(request),encoding="utf-8")
        result=subprocess.run([sys.executable,str(ROOT/"scripts/workers/physiology.py"),"--request",str(req),"--output",str(out)],capture_output=True,text=True,timeout=60)
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertEqual(json.loads(out.read_text())["status"],"completed")
        request["parameters"]={"invented":1}; req.write_text(json.dumps(request),encoding="utf-8")
        result=subprocess.run([sys.executable,str(ROOT/"scripts/workers/physiology.py"),"--request",str(req),"--output",str(out)],capture_output=True,text=True,timeout=60)
        self.assertEqual(result.returncode,2)
        self.assertEqual(json.loads(out.read_text())["status"],"error")
        source=Path(request["source_path"]); original=source.read_bytes()
        result=subprocess.run([sys.executable,str(ROOT/"scripts/workers/physiology.py"),"--request",str(req),"--output",str(source)],capture_output=True,text=True,timeout=60)
        self.assertEqual(result.returncode,2)
        self.assertEqual(source.read_bytes(),original)


@unittest.skipUnless(importlib.util.find_spec("parselmouth"), "Run AudioTests with vision-audio-venv")
class AudioTests(unittest.TestCase):
    def test_known_tone_and_silence(self):
        import soundfile as sf
        with tempfile.TemporaryDirectory(prefix="brohn-audio-test-") as directory:
            path=Path(directory)/"tone.wav"; fs=16000
            x=.25*np.sin(2*np.pi*220*np.arange(fs*3)/fs)
            sf.write(path,x,fs,subtype="FLOAT")
            request={"schema":"brohn-worker-request/1.0","operation":"physiology","modality":"audio","source_path":str(path),"format":"wav",
                     "metadata":{"unit":"FS","sampling_rate":fs,"participant_id":"synthetic-1"}}
            result=worker.run(request)
            values={feature["name"]:feature["value"] for feature in result["features"]}
            self.assertAlmostEqual(values["audio_rms"],.25/np.sqrt(2),places=7)
            self.assertAlmostEqual(values["pitch_median"],220,delta=1)
            self.assertEqual(result["features"][0]["group"]["participant_id"],"synthetic-1")
            self.assertLessEqual(len(result["events"]),2000)
            sf.write(path,np.zeros(fs*3),fs,subtype="FLOAT")
            result=worker.run(request)
            values={feature["name"]:feature["value"] for feature in result["features"]}
            self.assertEqual(values["audio_rms"],0)
            self.assertIsNone(values["pitch_median"])
            self.assertIsNone(values["spectral_centroid_mean"])
            json.dumps(result,allow_nan=False)


@unittest.skipUnless(importlib.util.find_spec("snirf"), "Run FnirsTests with acquisition-venv")
class FnirsTests(unittest.TestCase):
    def test_snirf_conversion_geometry_and_pathlength_scaling(self):
        from snirf import Snirf
        with tempfile.TemporaryDirectory(prefix="brohn-fnirs-test-") as directory:
            path=Path(directory)/"synthetic.snirf"; fs=10
            times=np.arange(600)/fs
            values=np.column_stack([100+2*np.sin(2*np.pi*times)+5*np.sin(2*np.pi*.05*times),90+np.sin(2*np.pi*times)+2*np.sin(2*np.pi*.05*times)])
            with Snirf(str(path),"w") as snirf:
                snirf.formatVersion="1.1"; snirf.nirs.appendGroup(); nirs=snirf.nirs[0]
                nirs.metaDataTags.SubjectID="synthetic-1"; nirs.metaDataTags.MeasurementDate="2026-09-08"; nirs.metaDataTags.MeasurementTime="00:00:00Z"
                nirs.metaDataTags.LengthUnit="mm"; nirs.metaDataTags.TimeUnit="s"; nirs.metaDataTags.FrequencyUnit="Hz"
                nirs.probe.wavelengths=np.array([760.,850.]); nirs.probe.sourcePos3D=np.array([[0.,0.,0.]])
                nirs.probe.detectorPos3D=np.array([[30.,0.,0.]])
                nirs.data.appendGroup(); data=nirs.data[0]; data.time=times; data.dataTimeSeries=values
                for wavelength in [1,2]:
                    data.measurementList.appendGroup(); item=data.measurementList[-1]
                    item.sourceIndex=1; item.detectorIndex=1; item.wavelengthIndex=wavelength; item.dataType=1; item.dataTypeIndex=1
                snirf.save()
            request={"schema":"brohn-worker-request/1.0","operation":"physiology","modality":"fnirs","source_path":str(path),"format":"snirf",
                     "metadata":{"unit":"native","value_columns":["S1_D1 760","S1_D1 850"],"sampling_rate":fs},"parameters":{"ppf":[6,6]}}
            result=worker.run(request)
            self.assertEqual(result["status"],"completed")
            self.assertEqual(result["quality"]["computed_channel_segments"],2)
            self.assertEqual(result["recordings"][0]["source_detector_distance_m"],.03)
            expected=-np.log(values[:,0]/values[:,0].mean())
            features={item["name"]:item["value"] for item in result["features"] if item["channel"]=="S1_D1 hbo"}
            self.assertAlmostEqual(features["source_intensity_optical_density_mean"],expected.mean(),places=12)
            first_sd=features["haemoglobin_sd"]
            request["parameters"]["ppf"]=[12,12]
            result=worker.run(request)
            second_sd=next(item["value"] for item in result["features"] if item["channel"]=="S1_D1 hbo" and item["name"]=="haemoglobin_sd")
            self.assertAlmostEqual(first_sd/second_sd,2,places=10)
            request["parameters"]={}
            with self.assertRaisesRegex(worker.InputError,"pathlength factors"):
                worker.run(request)


if __name__=="__main__":
    unittest.main(verbosity=2)
