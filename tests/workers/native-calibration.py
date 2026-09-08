"""Source calibration gates apply equally to manual physiology and neural jobs."""
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import numpy as np

ROOT=Path(__file__).resolve().parents[2]
def load(name,path):
    spec=importlib.util.spec_from_file_location(name,path); module=importlib.util.module_from_spec(spec); spec.loader.exec_module(module); return module
physiology=load("native_gate_physiology",ROOT/"scripts/workers/physiology.py")
neural=load("native_gate_neural",ROOT/"scripts/workers/neural.py")
fixtures=load("native_gate_original",ROOT/"tests/workers/headers.py")


def header_field(data,name,value,index=0):
    fields=[("label",16),("transducer",80),("unit",8),("physical_min",8),("physical_max",8),("digital_min",8),("digital_max",8),("prefilter",80),("samples_per_record",8),("reserved",32)]
    start=256
    for key,width in fields:
        if key==name:
            encoded=str(value).encode("ascii").ljust(width,b" "); assert len(encoded)==width
            return data[:start+index*width]+encoded+data[start+(index+1)*width:]
        start+=3*width
    raise AssertionError(name)


class NativeCalibrationTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(prefix="brohn-original-calibration-"); self.root=Path(self.temp.name)
    def tearDown(self): self.temp.cleanup()
    def write(self,data,fmt="edf"):
        path=self.root/("original."+fmt); path.write_bytes(data); return path
    def metadata(self,channel="Cz",fs=100): return {"unit":"native","value_columns":[channel],"sampling_rate":fs}
    def test_native_physical_to_voltage_arithmetic_and_negative_gain(self):
        for fmt in ("edf","bdf"):
            path=self.write(fixtures.edf_fixture(fmt=fmt,mixed=False,declared=2),fmt)
            rows,info=physiology.native_eeg(path,self.metadata(),fmt)
            expected=(-100+(0+32768)*200/65535)*1e-6
            np.testing.assert_allclose(rows[0]["values"],expected,rtol=1e-8,atol=1e-18)
            self.assertEqual(info["calibration_gate"]["inspector_sha256"],physiology.digest_file(ROOT/"scripts/workers/headers.py"))
            data=header_field(path.read_bytes(),"physical_min",100); data=header_field(data,"physical_max",-100); path.write_bytes(data)
            rows,_=physiology.native_eeg(path,self.metadata(),fmt)
            np.testing.assert_allclose(rows[0]["values"],-expected,rtol=1e-8,atol=1e-18)
    def test_missing_wrong_units_and_invalid_ranges_reject_before_mne_interpretation(self):
        cases=[("unit",""),("unit","a.u."),("physical_max",-100),("physical_max","nan"),
               ("digital_max",-32768),("digital_max",-40000),("digital_max",32768),("digital_min",-32768.5)]
        for field,value in cases:
            with self.subTest(field=field,value=value):
                path=self.write(header_field(fixtures.edf_fixture(declared=2),field,value))
                with patch("mne.io.read_raw_edf",side_effect=AssertionError("MNE must not see an unqualified source")):
                    with self.assertRaisesRegex(physiology.InputError,"voltage units|calibration ranges"):
                        physiology.native_eeg(path,self.metadata(),"edf")
    def test_selected_lower_rate_is_not_upsampled_by_unselected_higher_rate(self):
        path=self.write(fixtures.edf_fixture(mixed=True,declared=2))
        recordings,_=physiology.native_eeg(path,self.metadata("ECG",50),"edf")
        self.assertEqual(recordings[0]["fs"],50)
        self.assertEqual(recordings[0]["values"].shape,(1,100))
        np.testing.assert_allclose(np.diff(recordings[0]["times"]),.02,atol=1e-14)
        metadata=self.metadata(); metadata["value_columns"]=["Cz","ECG"]
        with self.assertRaisesRegex(physiology.InputError,"different sampling rates"): physiology.native_eeg(path,metadata,"edf")
    def test_discontinuous_record_clock_cannot_become_continuous_eeg(self):
        path=self.write(fixtures.edf_fixture(discontinuous=True,declared=2))
        with self.assertRaisesRegex(physiology.InputError,"Discontinuous"): physiology.native_eeg(path,self.metadata(),"edf")
        data=path.read_bytes().replace(b"EDF+D",b"EDF+C"); path.write_bytes(data)
        with self.assertRaisesRegex(physiology.InputError,"inconsistent"): physiology.native_eeg(path,self.metadata(),"edf")
    def test_neural_manual_request_cannot_bypass_shared_unit_gate(self):
        path=self.write(fixtures.edf_fixture(missing_unit=True,declared=2))
        request={"schema":"brohn-worker-request/1.0","operation":"neural","modality":"eeg","format":"edf","source_path":str(path),"metadata":self.metadata()}
        with self.assertRaisesRegex(neural.io.InputError,"declared voltage units"): neural.run(request)
    def test_fif_undeclared_volts_rejected(self):
        import mne
        from mne._fiff.constants import FIFF
        path=self.root/"original_raw.fif"
        raw=mne.io.RawArray(np.zeros((1,200)),mne.create_info(["Cz"],100,"eeg"),verbose=False)
        raw.info["chs"][0]["unit"]=FIFF.FIFF_UNIT_NONE
        raw.save(path,overwrite=True,verbose=False); raw.close()
        with self.assertRaisesRegex(physiology.InputError,"declared volts"): physiology.native_eeg(path,self.metadata(),"fif")


if __name__=="__main__": unittest.main(verbosity=2)
