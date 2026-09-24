"""Independent stdlib contract checks; native inference has separate evidence."""
from __future__ import annotations
import copy
from fractions import Fraction
import importlib.util
import json
import math
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts/workers"))
spec = importlib.util.spec_from_file_location("brohn_facial", ROOT / "scripts/workers/facial_expression.py")
worker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(worker)


def native(valid=True):
    if not valid:
        return {**{k: math.nan for k in worker.BOX[:-1] + worker.AUS + worker.CATEGORIES}, "FaceScore": 0.0}
    return {**dict.fromkeys(worker.AUS, 0.0), **dict.fromkeys(worker.CATEGORIES, 0.0), "neutral": 1.0,
            "FaceRectX": 10.25, "FaceRectY": 20.5, "FaceRectWidth": 100.0, "FaceRectHeight": 150.0, "FaceScore": .9,
            "Identity_1": math.nan, "Pitch": math.nan, "gaze_pitch": math.nan}


class Contract(unittest.TestCase):
    def test_zero_is_a_valid_native_score(self):
        output = worker.convert_native([native()])
        self.assertEqual(output["state"], "single_face")
        self.assertTrue(output["eligible"])
        self.assertEqual(output["faces"][0]["au_scores"]["AU12"], 0.0)
        self.assertNotIn("Identity_1", json.dumps(output))

    def test_no_face_remains_empty_not_neutral(self):
        self.assertEqual(worker.convert_native([native(False)]), {"state": "no_face", "face_count": 0, "eligible": False, "faces": []})

    def test_multiple_faces_remain_unlinked_and_ineligible(self):
        output = worker.convert_native([native(), native()])
        self.assertEqual(output["state"], "multiple_faces")
        self.assertFalse(output["eligible"])
        self.assertEqual([x["face_ordinal"] for x in output["faces"]], [1, 2])

    def test_partial_native_output_is_preserved_as_missing(self):
        row = native(); row["AU01"] = math.nan
        output = worker.convert_native([row])
        self.assertEqual(output["state"], "invalid_native_output")
        self.assertIsNone(output["faces"][0]["au_scores"]["AU01"])

    def test_unsupported_native_substitution_refused(self):
        for field, value in [("FaceScore", math.inf), ("AU12", -1), ("neutral", 1.5), ("FaceRectWidth", 0), ("Identity_1", .1), ("Pitch", 10), ("gaze_pitch", .1)]:
            with self.subTest(field=field):
                row = native(); row[field] = value
                with self.assertRaises(worker.InputError): worker.convert_native([row])

    def test_native_vocabulary_missing_placeholder_and_capacity_refused(self):
        rows = native(); del rows["AU07"]
        for values in [[rows], [native(False), native()], [native()] * 17, []]:
            with self.assertRaises(worker.InputError): worker.convert_native(values)
        self.assertEqual(worker.convert_native([native()] * 16)["face_count"], 16)

    def test_decimal_selection_and_stride_use_original_integer_pts(self):
        info = {"time_base": "1/1000", "frames": [{"pts": p, "pts_time": f"{p/1000:.6f}"} for p in [2000,2040,2110,2310,2710,2910]]}
        times, relative, indexes, count = worker.select_frames(info, Fraction(".040000000000000001"), Fraction(".91"), 2)
        self.assertEqual(indexes, [2,4]); self.assertEqual(count,4)
        self.assertEqual(relative, [Fraction(0),Fraction('.04'),Fraction('.11'),Fraction('.31'),Fraction('.71'),Fraction('.91')])
        self.assertEqual(times[0], 2)

    def test_large_integer_pts_keep_exact_clock(self):
        origin = 2**53 + 1
        info = {"time_base": "1/1000", "frames": [{"pts": origin+i, "pts_time": str((worker.Decimal(origin)+i)/1000)} for i in [0,7,21]]}
        times, relative, indexes, _ = worker.select_frames(info, Fraction(0), None, 1)
        self.assertEqual(times[0].numerator, origin)
        self.assertEqual(relative, [Fraction(0),Fraction(7,1000),Fraction(21,1000)])
        self.assertEqual(indexes,[0,1,2])

    def test_inconsistent_or_reset_clock_and_capacity_refused(self):
        original = {"time_base": "1/1000", "frames": [{"pts": i, "pts_time": str(i/1000)} for i in [0,10,20]]}
        for mode in ['reset','printed','missing']:
            info=copy.deepcopy(original)
            if mode=='reset':info['frames'][2]['pts']=0
            elif mode=='printed':info['frames'][2]['pts_time']='0.3'
            else:del info['frames'][2]['pts']
            with self.assertRaises(worker.InputError):worker.select_frames(info,Fraction(0),None,1)
        with self.assertRaises(worker.InputError):worker.select_frames(original,Fraction('.02'),None,1)
        many={'time_base':'1/1000','frames':[{'pts':i,'pts_time':str(i/1000)} for i in range(301)]}
        with self.assertRaises(worker.InputError):worker.select_frames(many,Fraction(0),None,1)

    def test_support_excludes_no_face_multiple_and_long_gaps(self):
        summary=worker.Summary(.25)
        values=[(0,[native()]),(.1,[native()]),(.2,[native(False)]),(.3,[native()]),(.4,[native(),native()]),(.5,[native()]),(1,[native()])]
        for t,rows in values:summary.add(worker.convert_native(rows),Fraction(str(t)))
        self.assertEqual(summary.support,Fraction('.1'))
        self.assertEqual(summary.valid_frames,5)
        self.assertEqual(summary.features()[0]['value'],0)
        self.assertEqual(summary.features()[0]['time_weighted_mean'],0)

    def test_absent_support_is_null_not_zero(self):
        summary=worker.Summary(.25);summary.add(worker.convert_native([native(False)]),Fraction(0))
        self.assertTrue(all(x['value'] is None and x['time_weighted_mean'] is None for x in summary.features()))

    def test_request_consent_range_source_identity_and_unknown_fields(self):
        with tempfile.TemporaryDirectory() as d:
            source=Path(d)/'original.mp4';source.write_bytes(b'authored contract bytes, not a decoded video')
            artifacts=Path(d)/'artifacts';artifacts.mkdir()
            request={'schema':'brohn-facial-expression-request/1.0','source_path':str(source),'source_hash':worker.digest(source),'output_directory':str(artifacts),
                     'metadata':{'profile':worker.PROFILE,'origin_statement':'Synthetic test.','consent_statement':'No participant recording.','start_s':'0','end_s':'1','frame_stride':1}}
            self.assertEqual(worker.validate_request(request)[2],Fraction(0))
            for key,value in [('consent_statement',''),('start_s','1e0'),('end_s','0'),('frame_stride',True),('unknown',1)]:
                changed=copy.deepcopy(request);changed['metadata'][key]=value
                with self.assertRaises(worker.InputError):worker.validate_request(changed)
            changed=copy.deepcopy(request);changed['source_hash']='0'*64
            with self.assertRaises(worker.InputError):worker.validate_request(changed)


if __name__=='__main__':
    folder=Path(sys.argv[1]).resolve() if len(sys.argv)>1 else Path(tempfile.mkdtemp(prefix='brohn-facial-contract-'))
    folder.mkdir(parents=True,exist_ok=True)
    result=unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(Contract))
    receipt={'passed':result.wasSuccessful(),'tests':result.testsRun,'failures':[(str(t),e) for t,e in result.failures],'errors':[(str(t),e) for t,e in result.errors],
             'scope':'Independent stdlib request/clock/missingness/native-value boundary; no native model inference.',
             'worker_sha256':worker.digest(ROOT/'scripts/workers/facial_expression.py')}
    (folder/'results.json').write_text(json.dumps(receipt,indent=2)+'\n',encoding='utf-8')
    sys.exit(0 if result.wasSuccessful() else 1)
