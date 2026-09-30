"""Worker-adapter checks reuse fresh deterministic synthetic importer artifacts; no new import or scientific job."""
import copy
import hashlib
import json
from pathlib import Path
import subprocess
import shutil
import sys
import unittest
from unittest.mock import patch
from types import SimpleNamespace

from clock_test_support import ROOT,fresh_output,make_preview
HERE=Path(__file__).resolve().parent
import clock_window_worker as worker
import clock_window
from clock_preview import build_preview

DEST = fresh_output()
DEST.mkdir(exist_ok=False)
sys.argv = sys.argv[:1]

def digest(path): return hashlib.sha256(Path(path).read_bytes()).hexdigest()

class WorkerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = make_preview(DEST/'synthetic-input')
        cls.originals = {t[k]['path']: digest(t[k]['path']) for side in ('source','reference')
            for t in [cls.source[side]['marker'], *cls.source[side]['tracks']] for k in ('samples','evidence')}
        cls.preview = build_preview(cls.source)
        cls.counter = 0
        cls.request = cls.make_request()
        cls.accepted = cls.execute(cls.request)
    @classmethod
    def make_request(cls, start='0', end='2.02', offset=0):
        cls.counter += 1
        return {'schema':'brohn-clock-window-worker-request/0.1','window':{'schema':'brohn-clock-window-input/0.1',
            'preview_request':copy.deepcopy(cls.source), 'selection':{'start_s':start,'end_s':end,'offset':offset},
            'output_directory':str(DEST/f'exports-{cls.counter}')},'expected_preview':copy.deepcopy(cls.preview)}
    @classmethod
    def execute(cls, request):
        path=DEST/f'request-{cls.counter}.json'; path.write_text(json.dumps(request),encoding='utf-8')
        return worker.execute(path,DEST/f'result-{cls.counter}.json')
    def check_changed(self, mutate):
        result=copy.deepcopy(self.accepted['result']); mutate(result)
        with self.assertRaises((ValueError, KeyError, TypeError)):
            worker.validate(result,self.source,self.request['window']['selection'],self.preview)
    def test_original_optional_identity_remains_absent(self):
        rows=self.accepted['result']['rows']; self.assertGreater(len(rows),0)
        for row in rows:
            self.assertEqual(set(json.loads(row['identity_json'])),{'participant_id','session_id'})
            self.assertIsNone(row['condition_id']); self.assertIsNone(row['exposure_id'])
    def test_existing_imported_optional_identity_is_preserved(self):
        original=make_preview(DEST/'optional-identity-input',optional=True)
        r=clock_window.run({'schema':clock_window.SCHEMA,'preview_request':original,'selection':{'start_s':'0','end_s':'2.02','offset':0},'output_directory':str(DEST/'optional-identity-window')})
        worker.validate(r,r['source_request'],r['selection'],r['preview'])
        self.assertTrue(all(row['condition_id']=='declared-condition' and row['exposure_id']=='original-exposure' for row in r['rows']))
    def test_manifest_and_all_export_hashes_match_actual_files(self):
        out=Path(self.request['window']['output_directory'])
        for item in [*self.accepted['result']['artifacts'], self.accepted['manifest_artifact']]:
            self.assertEqual(digest(out/item['file']),item['sha256'])
            self.assertEqual((out/item['file']).stat().st_size,item['bytes'])
    def test_repeated_export_is_exact_and_saved_preview_unchanged(self):
        new=self.execute(self.make_request())
        self.assertEqual(new,self.accepted)
        self.assertEqual(self.accepted['result']['preview'],self.preview)
    def test_empty_window_retains_complete_source_accounting(self):
        new=self.execute(self.make_request('0.00001','0.00002'))
        self.assertEqual(new['result']['status'],'empty_window');self.assertEqual(new['result']['rows'],[])
        self.assertEqual(new['result']['counts']['source_rows'],20)
    def test_tampered_saved_preview_never_publishes_output(self):
        q=self.make_request();q['expected_preview']['review']['rationale']='A different researcher review'
        with self.assertRaisesRegex(ValueError,'differs from') : self.execute(q)
        self.assertFalse((DEST/f'result-{self.counter}.json').exists())
    def test_changed_coordinates_are_refused(self):
        self.check_changed(lambda r:r['rows'][0].__setitem__('reference_seconds_numerator','7'))
    def test_changed_identity_is_refused(self):
        self.check_changed(lambda r:r['rows'][0].__setitem__('participant_id','another person'))
    def test_invented_optional_identity_is_refused(self):
        self.check_changed(lambda r:r['rows'][0].__setitem__('condition_id','invented condition'))
    def test_changed_row_order_is_refused(self):
        self.check_changed(lambda r:r['rows'].reverse())
    def test_invented_source_track_is_refused(self):
        self.check_changed(lambda r:r['rows'][0].__setitem__('track_id','another original'))
    def test_changed_count_is_refused(self):
        self.check_changed(lambda r:r['counts'].__setitem__('selected_rows',True))
    def test_changed_export_binding_is_refused(self):
        self.check_changed(lambda r:r['artifacts'][0]['binding'].__setitem__('mapping_sha256','0'*64))
    def test_changed_export_name_is_refused(self):
        self.check_changed(lambda r:r['artifacts'][0].__setitem__('file','../selected.csv'))
    def test_changed_mapping_claim_is_refused(self):
        self.check_changed(lambda r:r.__setitem__('physical_synchronization','established'))
    def test_duplicate_request_key_is_refused_before_artifacts(self):
        path=DEST/'duplicate.json';path.write_text('{"schema":"one","schema":"two"}')
        with self.assertRaises(ValueError):worker.execute(path,DEST/'duplicate-output.json')
        self.assertFalse((DEST/'duplicate-output.json').exists())
    def test_nonfinite_request_is_refused(self):
        path=DEST/'nonfinite.json';path.write_text('{"x":NaN}')
        with self.assertRaises(ValueError):worker.execute(path,DEST/'nonfinite-output.json')
    def test_oversized_request_is_refused(self):
        path=DEST/'oversized.json';path.write_bytes(b' '*(worker.MAX_INPUT+1))
        with self.assertRaises(ValueError):worker.execute(path,DEST/'oversized-output.json')
    def test_publication_checker_binds_exact_request_result_and_exports(self):
        proof=worker.check(DEST/'request-1.json',DEST/'result-1.json',DEST/'verification.json')
        self.assertTrue(proof['passed']);self.assertEqual(proof['request_sha256'],digest(DEST/'request-1.json'))
        self.assertEqual(proof['result_sha256'],digest(DEST/'result-1.json'))
    def test_publication_checker_refuses_equal_size_export_corruption(self):
        q=copy.deepcopy(self.request);folder=DEST/'corrupted-exports'
        shutil.copytree(q['window']['output_directory'],folder);q['window']['output_directory']=str(folder)
        path=folder/'selected.csv';raw=bytearray(path.read_bytes());raw[-2]^=1;path.write_bytes(raw)
        qp=DEST/'corrupted-request.json';qp.write_text(json.dumps(q))
        with self.assertRaisesRegex(ValueError,'bytes changed'):worker.check(qp,DEST/'result-1.json',DEST/'corruption-proof.json')
        self.assertFalse((DEST/'corruption-proof.json').exists())
    def test_bounded_reader_checks_size_before_reading(self):
        path=DEST/'bounded-overflow';path.write_bytes(b'x'*101)
        with patch.object(Path,'open',side_effect=AssertionError('unbounded read')):
            with self.assertRaises(ValueError):worker.read_bounded(path,100)
    def test_bounded_reader_refuses_growth_after_stat(self):
        path=DEST/'bounded-growth';path.write_bytes(b'x'*101)
        with patch.object(Path,'is_file',return_value=True),patch.object(Path,'stat',return_value=SimpleNamespace(st_size=100)):
            with self.assertRaisesRegex(ValueError,'grew'):worker.read_bounded(path,100)
    def test_streamed_digest_refuses_growth_after_stat(self):
        path=DEST/'digest-growth';path.write_bytes(b'x'*101)
        with patch.object(Path,'is_file',return_value=True),patch.object(Path,'stat',return_value=SimpleNamespace(st_size=100)):
            with self.assertRaisesRegex(ValueError,'grew'):worker.bounded_digest(path,100)
    @classmethod
    def tearDownClass(cls):
        assert all(digest(p)==h for p,h in cls.originals.items()), 'Retained original artifact changed'

suite=unittest.defaultTestLoader.loadTestsFromTestCase(WorkerTests)
result=unittest.TextTestRunner(verbosity=2).run(suite)
(DEST/'results.json').write_text(json.dumps({'schema':'brohn-external-clock-window-worker-tests/0.1',
    'passed':result.wasSuccessful(),'tests':result.testsRun,'errors':[(str(t),e)for t,e in result.errors],
    'failures':[(str(t),e)for t,e in result.failures], 'scope':'worker adapter using fresh deterministic synthetic importer artifacts; no R authorization, saved-map job or publication qualification',
    'originals_unchanged':all(digest(p)==h for p,h in WorkerTests.originals.items()),
    'code':{str(p):digest(p)for p in [ROOT/'scripts/workers/clock_window_worker.py',Path(__file__),ROOT/'scripts/workers/clock_window.py']}} ,indent=2),encoding='utf-8')
raise SystemExit(0 if result.wasSuccessful() else 1)
