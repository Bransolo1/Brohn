"""Independent FFT and original waveform evidence; no physical-device qualification."""
import csv
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest
import numpy as np

ROOT = Path(__file__).resolve().parents[2]
def module(name, path):
    spec = importlib.util.spec_from_file_location(name, ROOT/path)
    value = importlib.util.module_from_spec(spec); spec.loader.exec_module(value)
    return value
worker = module("cardiac_worker", "scripts/workers/physiology.py")
artifacts = module("cardiac_artifacts", "scripts/workers/physiology_artifacts.py")

def peak_train(duration=350):
    peaks = [1.]
    while peaks[-1] < duration-1:
        t = peaks[-1]
        peaks.append(t+1+.08*np.sin(2*np.pi*.1*t)+.04*np.sin(2*np.pi*.25*t))
    return np.asarray(peaks[:-1])

def source_fixture(directory, modality):
    fs = 250 if modality == "ecg" else 100
    t = np.arange(350*fs)/fs; x = np.zeros(len(t)); peaks = peak_train()
    for peak in peaks:
        mask = np.abs(t-peak)<.6; z=t[mask]-peak
        if modality == "ecg":
            x[mask] += np.exp(-.5*(z/.012)**2)-.15*np.exp(-.5*((z+.025)/.008)**2)-.2*np.exp(-.5*((z-.025)/.008)**2)+.2*np.exp(-.5*((z-.25)/.045)**2)
        else:
            x[mask] += np.exp(-.5*(z/.055)**2)+.25*np.exp(-.5*((z-.2)/.07)**2)
    path = Path(directory)/(modality+".csv")
    with path.open("w", newline="", encoding="utf-8") as stream:
        writer=csv.writer(stream);writer.writerow(["time",modality]);writer.writerows(zip(t,x))
    return path, fs

def independent_psd(peaks, fs):
    # Independent segment-wise DFT with a periodic Hann; no scipy Welch call.
    endpoints=peaks[1:]/fs; intervals=np.diff(peaks)*1000/fs
    grid=np.arange(endpoints[0], endpoints[-1], .25)
    ix=np.minimum(np.searchsorted(endpoints,grid,side="right"),len(endpoints)-1)
    left=np.maximum(ix-1,0)
    fraction=(grid-endpoints[left])/(endpoints[ix]-endpoints[left])
    values=intervals[left]+fraction*(intervals[ix]-intervals[left])
    window=.5-.5*np.cos(2*np.pi*np.arange(512)/512)
    powers=[]
    for start in range(0,len(values)-511,256):
        segment=values[start:start+512]; transformed=np.fft.rfft((segment-segment.mean())*window)
        density=np.abs(transformed)**2/(4*np.sum(window**2));density[1:-1]*=2;powers.append(density)
    return np.arange(257)/128,np.mean(powers,axis=0),len(powers)

class CardiacSpectrum(unittest.TestCase):
    def calculate(self, peaks=None, prefix="detected_rr", **settings):
        peaks=np.round(peak_train()*1000) if peaks is None else peaks
        p=worker.parameters("ecg", settings, 1000)
        f, intervals, valid, spectrum=worker.interval_metrics(peaks,1000,p,prefix,return_spectrum=True)
        return {x["name"]:x for x in f},spectrum

    def test_every_bin_matches_independent_segment_fft_and_saved_integrals(self):
        peaks=np.round(peak_train()*1000);f,s=self.calculate(peaks)
        freq,power,count=independent_psd(peaks,1000)
        observed=np.array([[r["frequency_hz"],r["density_ms2_hz"]] for r in s["rows"]])
        np.testing.assert_array_equal(observed[:,0],freq)
        np.testing.assert_allclose(observed[:,1],power,rtol=2e-12,atol=2e-9)
        self.assertEqual(s["support"]["welch_segments"],count)
        self.assertEqual(len(s["rows"]),257);self.assertEqual(s["frequency_range_hz"],[0,2])
        for band,mask in [("LF",(freq>=.04)&(freq<.15)),("HF",(freq>=.15)&(freq<=.4))]:
            exact=float(observed[mask,1].sum()/128)
            self.assertEqual(exact,s["integrated_bands_ms2"][band])
            self.assertEqual(exact,f["detected_rr_"+band.lower()+"_power_candidate"]["value"])
            peak=freq[mask][np.argmax(observed[mask,1])]
            self.assertLess(abs(peak-(.1 if band=="LF" else .25)),1/128)
        self.assertAlmostEqual(f["detected_rr_lf_hf_ratio_candidate"]["value"],s["integrated_bands_ms2"]["LF"]/s["integrated_bands_ms2"]["HF"])
        self.assertFalse(s["normal_to_normal_confirmed"])

    def test_unavailable_support_is_not_a_zero_spectrum(self):
        for peaks,settings in [(np.arange(30)*1000,{}),(np.r_[0,np.cumsum([1000]*350+[4000])],{}),
                               (np.arange(400)*1000,{"frequency_min_duration_s":600})]:
            with self.subTest(settings=settings,count=len(peaks)):
                f,s=self.calculate(peaks,**settings)
                self.assertEqual(s["status"],"unavailable");self.assertEqual(s["rows"],[])
                self.assertTrue(s["unavailable_reason"])
                self.assertIsNone(f["detected_rr_lf_power_candidate"]["value"])
                self.assertIsNone(f["detected_rr_hf_power_candidate"]["value"])
                self.assertIsNone(f["detected_rr_lf_hf_ratio_candidate"]["value"])

    def test_observed_constant_intervals_have_real_zero_power_and_unavailable_ratio(self):
        f,s=self.calculate(np.arange(351)*1000)
        self.assertEqual(s["status"],"available")
        self.assertTrue(all(r["density_ms2_hz"]==0 for r in s["rows"]))
        self.assertEqual(f["detected_rr_lf_power_candidate"]["value"],0)
        self.assertIsNone(f["detected_rr_lf_hf_ratio_candidate"]["value"])
        self.assertEqual(f["detected_rr_lf_hf_ratio_candidate"]["unavailable_reason"],"hf_power_is_zero")

    def test_prv_and_detected_rr_remain_different_rhythm_bases(self):
        _,rr=self.calculate();_,prv=self.calculate(prefix="detected_prv")
        self.assertNotEqual(rr["interval_basis"],prv["interval_basis"])
        self.assertIn("PRV",prv["rhythm_basis"]);self.assertNotIn("NN",prv["rhythm_basis"])
        self.assertFalse(prv["normal_to_normal_confirmed"])
        self.assertEqual(prv["rows"],rr["rows"])

    def test_actual_detectors_preserve_all_spectrum_bins_in_separate_typed_tables(self):
        for modality in ["ecg","ppg"]:
            with self.subTest(modality=modality), tempfile.TemporaryDirectory(prefix="brohn-cardiac-spectrum-") as directory:
                path,fs=source_fixture(directory,modality)
                result=worker.run({"schema":"brohn-worker-request/1.0","operation":"physiology","modality":modality,
                    "source_path":str(path),"format":"csv","metadata":{"time_column":"time","time_unit":"s","sampling_rate":fs,
                    "value_columns":[modality],"unit":"mV" if modality=="ecg" else "a.u."},"artifact_directory":directory,"origin":"sample"})
                self.assertEqual(result["status"],"completed")
                manifest=next(a for a in result["artifacts"] if a["kind"]=="physiology-events")
                tables=[];rows={}
                artifacts.verify_artifact(manifest,on_table=tables.append,on_rows=lambda tid,o,r:rows.setdefault(tid,[]).extend(r))
                spectrum=next(t for t in tables if t["coordinates"]["axis"]=="frequency")
                temporal=next(t for t in tables if t["coordinates"]["axis"]=="event")
                s=spectrum["support"]["interval_spectrum"];matrix=rows[spectrum["table_id"]]
                self.assertEqual(len(matrix),257);self.assertEqual(spectrum["columns"][-1]["unit"],"ms^2/Hz")
                self.assertTrue(all(r[0]=="interval_psd_bin" for r in matrix))
                self.assertTrue(all(r[0]!="interval_psd_bin" for r in rows[temporal["table_id"]]))
                self.assertEqual(manifest["rows"],result["quality"]["event_records_total"])
                prefix="detected_rr" if modality=="ecg" else "detected_prv"
                for band,lower,upper in [("lf",.04,.15),("hf",.15,.4)]:
                    integral=sum(r[2] for r in matrix if r[1]>=lower and (r[1]<upper if band=="lf" else r[1]<=upper))/128
                    metric=next(f for f in result["features"] if f["name"]==prefix+"_"+band+"_power_candidate")
                    self.assertAlmostEqual(integral,metric["value"],places=9)
                self.assertEqual(s["interval_basis"],"detected_pulse_intervals_prv" if modality=="ppg" else "detected_r_peak_intervals_rr")
                self.assertEqual(s["support"]["detected_peak_count"],len(rows[temporal["table_id"]]))
                json.dumps(result,allow_nan=False)

if __name__=="__main__":
    if len(sys.argv)>1 and sys.argv[1]=="--fixture":
        directory=Path(sys.argv[2]);directory.mkdir(parents=True,exist_ok=True)
        for modality in ["ecg","ppg"]:source_fixture(directory,modality)
    else: unittest.main()
