"""Real child execution/verification, exported-byte faults, and complete coverage."""
import copy,hashlib,json,shutil,subprocess,sys,unittest
from pathlib import Path
from unittest.mock import patch
from clock_test_support import ROOT,fresh_output,dense_window
import clock_plot as plot
import clock_plot_worker as worker

HERE=Path(__file__).resolve().parent
OUT=fresh_output();OUT.mkdir(parents=True,exist_ok=False);sys.argv=sys.argv[:1]

def digest(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def write(path,value):Path(path).write_bytes(plot.encoded(value)+b'\n')

class Tests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.n=0;cls.source={str(p):digest(p) for p in (ROOT/'scripts/workers/clock_plot.py',ROOT/'scripts/workers/clock_plot_worker.py')}
        result,manifest,folder=dense_window(OUT/'generated-input')
        cls.q={'schema':'brohn-clock-plot-input/0.1','window_ref':{'id':'generated-window','revision':1,'hash':'a'*64,'project_id':'sample'},
               'map_ref':{'id':'generated-map','revision':1,'hash':'b'*64},
               'window_result':{'schema':'brohn-clock-window-worker-result/0.1','result':result,'manifest_artifact':manifest},
               'artifacts':[{'kind':a['kind'],'path':str(folder/a['file']),'hash':a['sha256'],'bytes':a['bytes']} for a in [*result['artifacts'],manifest]],
               'display':{'profile':plot.PROFILE,'bins':512},'output_directory':str(OUT/'artifacts')}
        cls.original={str(p):digest(p) for p in folder.rglob('*') if p.is_file()}
        cls.request=OUT/'request.json';cls.result=OUT/'result.json';write(cls.request,cls.q)
        run=subprocess.run([sys.executable,str(ROOT/'scripts/workers/clock_plot_worker.py'),'--request',str(cls.request),'--output',str(cls.result)],capture_output=True,text=True,timeout=60)
        (OUT/'execute.stdout').write_text(run.stdout);(OUT/'execute.stderr').write_text(run.stderr)
        if run.returncode:raise AssertionError(run.stderr)
        cls.wrapper=json.loads(cls.result.read_text());cls.full=json.loads((OUT/'artifacts/plot.json').read_text())
    def test_01_actual_child_complete_plot_and_small_wrapper(self):
        self.assertEqual(self.wrapper['summary']['coverage']['complete_selected_rows_read'],6700)
        self.assertLess(self.result.stat().st_size,worker.MAX_RESULT)
        self.assertGreater(len(self.full['lanes']),0)
        self.assertEqual(self.wrapper['artifact']['bytes'],(OUT/'artifacts/plot.json').stat().st_size)
        self.assertNotIn('lanes',self.wrapper['summary'])
        self.assertNotIn(str(OUT),json.dumps(self.wrapper))
    def test_02_actual_cli_verification_returns_exact_request_and_result_hashes(self):
        output=OUT/'verification.json'
        run=subprocess.run([sys.executable,str(ROOT/'scripts/workers/clock_plot_worker.py'),'--request',str(self.request),'--result',str(self.result),'--output',str(output)],capture_output=True,text=True,timeout=60)
        self.assertEqual(run.returncode,0,run.stderr);v=json.loads(output.read_text())
        self.assertEqual(v,{'schema':'brohn-clock-plot-verification/0.1','passed':True,'request_sha256':digest(self.request),'result_sha256':digest(self.result),'scope':worker.SCOPE})
    def variant(self,change):
        type(self).n+=1;folder=OUT/f'variant-{self.n}';folder.mkdir()
        q=copy.deepcopy(self.q);q['output_directory']=str(folder);v=copy.deepcopy(self.full);change(v)
        path=folder/'plot.json';write(path,v);result=copy.deepcopy(self.wrapper)
        result['artifact']['sha256']=digest(path);result['artifact']['bytes']=path.stat().st_size;result['summary']=worker.summary(v)
        return q,result
    def test_03_changed_plot_bytes_refused(self):
        q,r=self.variant(lambda _:None);path=Path(q['output_directory'])/'plot.json';path.write_bytes(path.read_bytes()+b' ')
        with self.assertRaises(ValueError):worker.check(q,r)
    def test_04_wrong_ref_or_summary_or_implementation_refused(self):
        for change in (lambda v:v['window_ref'].__setitem__('hash','c'*64),lambda v:v['map_ref'].__setitem__('id','another'),lambda v:v['implementation'].__setitem__('clock_plot.py','0'*64)):
            with self.assertRaises(ValueError):worker.check(*self.variant(change))
        r=copy.deepcopy(self.wrapper);r['summary']['status']='empty_window'
        with self.assertRaises(ValueError):worker.check(self.q,r)
    def test_05_partial_lanes_vertices_or_counted_events_refused(self):
        changes=[lambda v:v['lanes'].pop(),lambda v:v['lanes'][0]['runs'][0]['groups'][0]['points'].pop(),
                 lambda v:v['events'][0]['bins'][0].__setitem__('count',1),
                 lambda v:v['lanes'][0]['runs'][0]['groups'][0]['points'][0].__setitem__('display_x',0.99)]
        for change in changes:
            with self.assertRaises(ValueError):worker.check(*self.variant(change))
    def test_06_path_escape_and_oversized_artifact_refused(self):
        for change in (lambda r:r['artifact'].__setitem__('file','../plot.json'),lambda r:r['artifact'].__setitem__('bytes',plot.MAX_OUTPUT+1)):
            r=copy.deepcopy(self.wrapper);change(r)
            with self.assertRaises(ValueError):worker.check(self.q,r)
    def test_07_request_and_result_size_and_duplicate_key_refusals(self):
        for name,raw in [('oversized',b' '*(worker.MAX_REQUEST+1)),('duplicate',b'{"schema":"a","schema":"b"}')]:
            path=OUT/(name+'.json');path.write_bytes(raw)
            with self.assertRaises(ValueError):worker.read_json(path,worker.MAX_REQUEST)
    def test_08_validator_does_not_reinspect_original_sources(self):
        with patch.object(plot,'prepare_plot',side_effect=AssertionError('Should not reprepare')),patch.object(plot,'csv_rows',side_effect=AssertionError('Should not read originals')):
            self.assertEqual(worker.check(self.q,self.wrapper)['schema'],'brohn-clock-plot/0.1')
    def test_09_existing_result_refusal_precedes_preparation(self):
        old=self.result.read_bytes();q=copy.deepcopy(self.q);q['output_directory']=str(OUT/'must-not-create');request=OUT/'existing-output-request.json';write(request,q)
        run=subprocess.run([sys.executable,str(ROOT/'scripts/workers/clock_plot_worker.py'),'--request',str(request),'--output',str(self.result)],capture_output=True,text=True,timeout=10)
        self.assertNotEqual(run.returncode,0);self.assertEqual(self.result.read_bytes(),old);self.assertFalse(Path(q['output_directory']).exists())
    def test_10_renderer_projections_are_finite_and_axis_labels_are_distinct(self):
        ticks=self.full['axis']['ticks'];self.assertEqual(len({t['display_offset_label'] for t in ticks}),5)
        self.assertEqual([t['position'] for t in ticks],[0,0.25,0.5,0.75,1])
        for lane in self.full['lanes']:
            for run in lane['runs']:
                for group in run['groups']:
                    for point in group['points']:
                        self.assertTrue(0<=point['display_x']<=1 and 0<=point['display_y']<=1)
    def test_11_axis_labels_and_original_lane_metadata_are_bound(self):
        for change in (lambda v:v['axis']['ticks'][1].__setitem__('display_offset_label','0'),
                       lambda v:v['axis'].__setitem__('display_base_exact_decimal','1'),
                       lambda v:v['lanes'][0].__setitem__('origin','live')):
            with self.assertRaises(ValueError):worker.check(*self.variant(change))
    def test_12_actual_R_brohn_json_wrapper_roundtrip_preserves_meaning(self):
        fixture=OUT/'actual-r-roundtrip.json'
        import os
        rscript=os.environ.get('BROHN_TEST_RSCRIPT') or shutil.which('Rscript')
        self.assertTrue(rscript,'Set BROHN_TEST_RSCRIPT or run the registered R launcher for the real R roundtrip.')
        child=subprocess.run([rscript,'--vanilla',str(HERE/'clock-json-roundtrip.R'),str(self.result),str(fixture)],cwd=ROOT,capture_output=True,text=True,timeout=30)
        self.assertEqual(child.returncode,0,child.stderr);before=digest(fixture)
        r=json.loads(fixture.read_text());self.assertIs(type(r['summary']['axis']['ticks'][0]['position']),int)
        self.assertIs(type(self.wrapper['summary']['axis']['ticks'][0]['position']),float)
        self.assertEqual(worker.check(self.q,r)['schema'],'brohn-clock-plot/0.1')
        self.assertEqual(digest(fixture),before)
    def test_13_numeric_equivalence_never_coerces_bool_string_or_rounded_values(self):
        for left,right in [(1,True),(0,False),('1',1),(9007199254740993,float(9007199254740993)),(float('inf'),float('inf'))]:
            self.assertFalse(worker.json_equivalent(left,right))
        self.assertTrue(worker.json_equivalent({'x':[0.0,0.25,1.0]},{'x':[0,0.25,1]}))
        for replacement in (True,'0',0.00000000000000001):
            r=copy.deepcopy(self.wrapper);r['summary']['axis']['ticks'][0]['position']=replacement
            with self.assertRaises(ValueError):worker.check(self.q,r)
    def test_99_original_artifacts_and_component_sources_unchanged(self):
        for path,h in {**self.original,**self.source}.items():self.assertEqual(digest(path),h,path)

suite=unittest.defaultTestLoader.loadTestsFromTestCase(Tests);result=unittest.TextTestRunner(verbosity=2).run(suite)
receipt={'passed':result.wasSuccessful(),'tests':result.testsRun,'failures':[(str(t),e) for t,e in result.failures+result.errors],
         'scope':'Real Python CLI component and bounded output verification only; no R job/publication, current-reader authority or browser acceptance.',
         'sources':{str(path):digest(path) for path in (ROOT/'scripts/workers/clock_plot.py',ROOT/'scripts/workers/clock_plot_worker.py',Path(__file__))}}
write(OUT/'results.json',receipt);raise SystemExit(0 if result.wasSuccessful() else 1)
