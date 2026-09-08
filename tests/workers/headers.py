"""Original native-format fixtures; no participant data or external recordings."""
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location("brohn_headers",ROOT/"scripts/workers/headers.py")
worker=importlib.util.module_from_spec(spec); spec.loader.exec_module(worker)


def edf_fixture(fmt="edf", mixed=True, discontinuous=False, declared=-1, missing_unit=False):
    width=2 if fmt=="edf" else 3
    def field(value,length):
        result=str(value).encode("ascii"); assert len(result)<=length
        return result.ljust(length,b" ")
    arrays={"label":["Cz","ECG",("EDF" if fmt=="edf" else "BDF")+" Annotations"],
        "transducer":["Original fixture EEG","Original fixture ECG",""],"unit":["" if missing_unit else "uV","mV",""],
        "physical_min":[-100,-10,-1],"physical_max":[100,10,1],"digital_min":[-32768,-32768,-32768],
        "digital_max":[32767,32767,32767],"prefilter":["HP:0.1Hz","HP:0.1Hz",""],
        "samples_per_record":[100,50 if mixed else 100,128],"reserved":["","",""]}
    fixed=(b"0       " if fmt=="edf" else b"\xffBIOSEMI")+field("PRIVATE TEST PERSON",80)+field("PRIVATE RECORDING",80)+field("01.01.01",8)+field("01.02.03",8)+field(1024,8)+field(("EDF" if fmt=="edf" else "BDF")+("+D" if discontinuous else "+C"),44)+field(declared,8)+field(1,8)+field(3,4)
    header=b"".join(field(value,size) for key,size in (("label",16),("transducer",80),("unit",8),("physical_min",8),("physical_max",8),("digital_min",8),("digital_max",8),("prefilter",80),("samples_per_record",8),("reserved",32)) for value in arrays[key])
    rows=[]
    for onset,label in [(0,"control"),(4 if discontinuous else 1,"test")]:
        tal=(f"+{onset}\x14\x14\x00+{onset}.25\x150.5\x14{label}\x14\x00").encode()
        rows.append(b"\x00"*(sum(arrays["samples_per_record"][:2])*width)+tal.ljust(128*width,b"\x00"))
    return fixed+header+b"".join(rows)


def snirf_fixture(path):
    import numpy as np
    from snirf import Snirf
    with Snirf(str(path),"w") as file:
        file.formatVersion="1.1"; file.nirs.appendGroup(); nirs=file.nirs[0]
        nirs.metaDataTags.SubjectID="PRIVATE TEST PERSON"; nirs.metaDataTags.MeasurementDate="2026-09-08"; nirs.metaDataTags.MeasurementTime="00:00:00Z"
        nirs.metaDataTags.LengthUnit="mm"; nirs.metaDataTags.TimeUnit="s"; nirs.metaDataTags.FrequencyUnit="Hz"
        nirs.probe.wavelengths=np.array([760.,850.]); nirs.probe.sourcePos3D=np.array([[0.,0.,0.]]); nirs.probe.detectorPos3D=np.array([[30.,0.,0.]])
        nirs.data.appendGroup(); data=nirs.data[0]; data.time=np.arange(100)/10; data.dataTimeSeries=np.ones((100,2))*100
        for wavelength in [1,2]:
            data.measurementList.appendGroup(); item=data.measurementList[-1]
            item.sourceIndex=1; item.detectorIndex=1; item.wavelengthIndex=wavelength; item.dataType=1; item.dataTypeIndex=1
        file.save()


class HeaderTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(prefix="brohn-original-headers-"); self.root=Path(self.temp.name)
    def tearDown(self):
        self.temp.cleanup()
    def request(self,path,fmt):
        return {"schema":"brohn-header-request/1.0","operation":"inspect_header","source_path":str(path),"source_hash":worker.digest(path),"format":fmt}
    def test_edf_bdf_native_rates_units_annotations_and_no_patient_preview(self):
        for fmt in ("edf","bdf"):
            path=self.root/("fixture."+fmt); path.write_bytes(edf_fixture(fmt))
            result=worker.run(self.request(path,fmt)); h=result["header"]
            self.assertEqual(h["channel_count"],2)
            self.assertEqual([c["sampling_rate_hz"] for c in h["channels"]],[100,50])
            self.assertEqual([c["sample_count"] for c in h["channels"]],[200,100])
            self.assertEqual([c["source_unit"] for c in h["channels"]],["uV","mV"])
            self.assertEqual(h["annotations"]["count"],2)
            self.assertEqual(h["annotations"]["preview"][0]["description"],"control")
            self.assertEqual(h["annotations"]["preview"][0]["onset_s"],.25)
            self.assertIsNone(h["recording"]["sampling_rate_hz"])
            self.assertFalse(h["quality"]["signal_samples_read"])
            self.assertNotIn("PRIVATE",json.dumps(result))
    def test_discontinuous_support_distinct_from_elapsed_time_and_unknown_unit(self):
        path=self.root/"fixture.edf"; path.write_bytes(edf_fixture(discontinuous=True,missing_unit=True))
        result=worker.run(self.request(path,"edf")); h=result["header"]
        self.assertEqual(h["recording"]["duration_s"],2)
        self.assertEqual(h["recording"]["elapsed_span_s"],5)
        self.assertTrue(h["recording"]["discontinuous"])
        self.assertIsNone(h["channels"][0]["source_unit"])
        self.assertEqual(result["status"],"needs_attention")
    def test_corrupt_source_signature_records_hash_and_unknown_fields_reject(self):
        path=self.root/"fixture.edf"; path.write_bytes(edf_fixture()[:-1])
        with self.assertRaisesRegex(worker.InputError,"truncated"): worker.run(self.request(path,"edf"))
        path.write_bytes(edf_fixture(declared=5))
        with self.assertRaisesRegex(worker.InputError,"record count"): worker.run(self.request(path,"edf"))
        path.write_bytes(edf_fixture()); request=self.request(path,"edf"); request["source_hash"]="0"*64
        with self.assertRaisesRegex(worker.InputError,"SHA-256"): worker.run(request)
        request=self.request(path,"bdf")
        with self.assertRaisesRegex(worker.InputError,"signature"): worker.run(request)
        request=self.request(path,"edf"); request["participant_id"]="guess"
        with self.assertRaisesRegex(worker.InputError,"fields"): worker.run(request)
    def test_cli_atomic_success_failure_and_source_overwrite_guard(self):
        path=self.root/"fixture.edf"; path.write_bytes(edf_fixture(mixed=False))
        req=self.root/"request.json"; out=self.root/"output.json"; req.write_text(json.dumps(self.request(path,"edf")))
        result=subprocess.run([sys.executable,str(ROOT/"scripts/workers/headers.py"),"--request",str(req),"--output",str(out)],capture_output=True,timeout=60)
        self.assertEqual(result.returncode,0,result.stderr); self.assertEqual(json.loads(out.read_text())["status"],"inspected")
        original=path.read_bytes()
        result=subprocess.run([sys.executable,str(ROOT/"scripts/workers/headers.py"),"--request",str(req),"--output",str(path)],capture_output=True,timeout=60)
        self.assertEqual(result.returncode,2); self.assertEqual(path.read_bytes(),original)
        req.write_text("[]")
        result=subprocess.run([sys.executable,str(ROOT/"scripts/workers/headers.py"),"--request",str(req),"--output",str(out)],capture_output=True,timeout=60)
        self.assertEqual(result.returncode,2); self.assertEqual(json.loads(out.read_text())["status"],"error")
        req.write_text("invalid original JSON")
        result=subprocess.run([sys.executable,str(ROOT/"scripts/workers/headers.py"),"--request",str(req),"--output",str(req)],capture_output=True,timeout=60)
        self.assertEqual(result.returncode,2); self.assertEqual(req.read_text(),"invalid original JSON")
    @unittest.skipUnless(importlib.util.find_spec("mne"),"MNE environment required")
    def test_fif_channels_rate_bad_annotations_and_refusal_of_external_reference(self):
        import mne
        import numpy as np
        from mne._fiff.constants import FIFF
        from mne._fiff.write import start_file,end_file,start_block,end_block,write_string
        path=self.root/"original_raw.fif"
        raw=mne.io.RawArray(np.zeros((2,500)),mne.create_info(["Cz","Pulse"],100,["eeg","ecg"]),verbose=False)
        raw.info["bads"]=["Cz"]; raw.set_annotations(mne.Annotations([1],[.2],["BAD original gap"]))
        raw.save(path,overwrite=True,verbose=False); raw.close()
        result=worker.run(self.request(path,"fif")); h=result["header"]
        self.assertEqual([c["type"] for c in h["channels"]],["eeg","ecg"])
        self.assertEqual(h["channels"][0]["source_unit"],"V")
        self.assertTrue(h["channels"][0]["marked_bad"])
        self.assertEqual(h["recording"]["duration_s"],5)
        self.assertEqual(h["annotations"]["count"],1)
        self.assertFalse(h["quality"]["signal_samples_read"])
        unsafe=self.root/"external_raw.fif"; fid=start_file(unsafe)
        start_block(fid,FIFF.FIFFB_REF); write_string(fid,FIFF.FIFF_REF_FILE_NAME,"../private_raw.fif"); end_block(fid,FIFF.FIFFB_REF); end_file(fid)
        with self.assertRaisesRegex(worker.InputError,"references another file"): worker.run(self.request(unsafe,"fif"))
    @unittest.skipUnless(importlib.util.find_spec("mne"),"MNE environment required")
    def test_standalone_compressed_set_and_fdt_dependency(self):
        from scipy.io import savemat
        import numpy as np
        eeg={"data":np.zeros((2,100)),"srate":100.,"nbchan":2,"pnts":100,"trials":1,"xmin":0.,"xmax":.99,
            "chanlocs":np.array([{"labels":"Cz"},{"labels":"Pz"}],dtype=object),"event":np.array([],dtype=object)}
        path=self.root/"original.set"; savemat(path,{"EEG":eeg},do_compression=True)
        result=worker.run(self.request(path,"set")); h=result["header"]
        self.assertEqual([c["name"] for c in h["channels"]],["Cz","Pz"])
        self.assertEqual(h["recording"]["sample_count"],100)
        self.assertEqual(h["channels"][0]["analysis_unit"],"V")
        self.assertIsNone(h["channels"][0]["source_unit"])
        eeg["data"]="../outside.fdt"; savemat(path,{"EEG":eeg},do_compression=True)
        with self.assertRaisesRegex(worker.InputError,"external FDT"): worker.run(self.request(path,"set"))
    @unittest.skipUnless(importlib.util.find_spec("soundfile"),"Audio environment required")
    def test_wav_full_scale_stereo_duration_not_speaker_identity(self):
        import soundfile as sf
        import numpy as np
        path=self.root/"subject-name.wav"; sf.write(path,np.zeros((24000,2)),8000,subtype="FLOAT")
        result=worker.run(self.request(path,"wav")); h=result["header"]
        self.assertEqual(h["recording"]["duration_s"],3)
        self.assertEqual(h["channels"][1]["index"],1)
        self.assertEqual(h["channels"][1]["analysis_unit"],"FS")
        self.assertNotIn("subject-name",json.dumps(result))
        self.assertIsNone(h["annotations"]["count"])
    @unittest.skipUnless(importlib.util.find_spec("snirf"),"Acquisition environment required")
    def test_snirf_measurement_geometry_units_and_external_links(self):
        import h5py
        path=self.root/"original.snirf"; snirf_fixture(path)
        result=worker.run(self.request(path,"snirf")); h=result["header"]
        self.assertEqual([c["name"] for c in h["channels"]],["S1_D1 760","S1_D1 850"])
        self.assertEqual(h["recording"]["sampling_rate_hz"],10)
        self.assertEqual(h["channels"][0]["calibration_evidence"]["dataType"],1)
        self.assertIsNone(h["channels"][0]["source_unit"])
        self.assertNotIn("PRIVATE",json.dumps(result))
        with h5py.File(path,"a") as file: file["external"]=h5py.ExternalLink("../private.h5","/recording")
        with self.assertRaisesRegex(worker.InputError,"external or soft links"): worker.run(self.request(path,"snirf"))
    @unittest.skipUnless(importlib.util.find_spec("snirf"),"Acquisition environment required")
    def test_snirf_variable_intervals_are_not_silently_resampled(self):
        import h5py
        path=self.root/"original.snirf"; snirf_fixture(path)
        with h5py.File(path,"a") as file: file["nirs/data1/time"][50]=5.01
        with self.assertRaisesRegex(worker.InputError,"variable sampling intervals"): worker.run(self.request(path,"snirf"))


if __name__=="__main__": unittest.main(verbosity=2)
