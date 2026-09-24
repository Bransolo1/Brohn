"""Hand-authored contract tests; optional original native reference, no inference."""
import argparse,copy,csv,hashlib,json,os,sys,tempfile,unittest
from pathlib import Path
from fractions import Fraction
sys.path.insert(0,str(Path(__file__).resolve().parents[2]/'scripts/workers'))
import facial_review as f

def author(directory):
    directory.mkdir(parents=True,exist_ok=True)
    face={'face_ordinal':1,'valid':True,'detection_score':.9,'bbox':{'FaceRectX':1.0,'FaceRectY':2.0,'FaceRectWidth':3.0,'FaceRectHeight':4.0},'au_scores':{k:.5 for k in f.AUS},'expression_scores':{k:float(k=='neutral') for k in f.CATEGORIES}}
    rows=[]
    for i in range(61):
        t=Fraction(i,10)+(1 if i==60 else 0);faces=[] if i in (0,12) else [copy.deepcopy(face)]
        if i==15:faces.append(dict(copy.deepcopy(face),face_ordinal=2))
        if i==20:faces[0]['valid']=False;faces[0]['au_scores']['AU01']=None
        state='no_face' if not faces else 'multiple_faces' if len(faces)>1 else 'single_face' if faces[0]['valid'] else 'invalid_native_output'
        rows.append({'frame_index':i,'source_pts':str(int((t+2)*1000)),'source_time_base':'1/1000','source_pts_s':format(float(t+2),'.6f'),'source_time':{'numerator':str((t+2).numerator),'denominator':str((t+2).denominator)},'relative_time':{'numerator':str(t.numerator),'denominator':str(t.denominator)},'time_s':float(t),'decoded_rgb_sha256':'a'*64,'state':state,'face_count':len(faces),'eligible':state=='single_face','faces':faces})
    obs=directory/'observations.jsonl';obs.write_text(''.join(json.dumps(r,separators=(',',':'))+'\n' for r in rows))
    values=directory/'values.csv'
    with values.open('w',newline='') as out:
        w=csv.DictWriter(out,fieldnames=f.CSV_FIELDS);w.writeheader()
        for r in rows:
            for face in r['faces'] or [None]:
                x={k:r[k] for k in f.CSV_FIELDS if k in r};x.update(relative_time_numerator=r['relative_time']['numerator'],relative_time_denominator=r['relative_time']['denominator'])
                if face:x.update(face_ordinal=face['face_ordinal'],face_valid=face['valid'],FaceScore=face['detection_score'],**face['bbox'],**face['au_scores'],**face['expression_scores'])
                w.writerow(x)
    # 57 eligible samples; 52 adjacent supported intervals of0.1s, last isolated.
    support=Fraction(26,5)
    a={'schema':'brohn-facial-expression-result/1.0','kind':'facial_expression','status':'completed','source':{'sha256':'b'*64,'bytes':100},'parameters':{'identity_model':None,'gaze_model':None,'pose_model':None,'orientation':'encoded upright pixels; no autorotation, crop or resize','source_time_base':'1/1000','source_time_origin':{'numerator':'2','denominator':'1'},'max_support_gap_s':.25,'frame_stride':1,'start_s':'0','end_s':None},'engine':{'fixture':'hand-authored contract values, not model evidence'},'quality':{'analysed_frames':61,'source_frames':61,'interval_frames':61,'skipped_interval_frames':0,'identity_tracking':False,'pts_validated':True,'states':{'no_face':2,'single_face':57,'multiple_faces':1,'invalid_native_output':1},'face_observations':60,'eligible_single_face_frames':57,'eligible_time_exact':{'numerator':'26','denominator':'5'},'eligible_time_s':5.2,'preview_frames':50,'preview_truncated':True,'usable':True},'preview':rows[:50],'features':[{'family':'action_unit' if k in f.AUS else 'native_expression_category','metric':k,'value':.5 if k in f.AUS else float(k=='neutral'),'time_weighted_mean':.5 if k in f.AUS else float(k=='neutral'),'unit':'native_model_score_0_1','aggregation':'arithmetic_mean_eligible_sampled_frames','valid_frames':57,'valid_time_s':float(support),'scope':'selected_recording_window'} for k in f.METRICS]}
    artifacts=[{'kind':kind,'path':str(path),**f.common.descriptor(path)} for kind,path in [('facial-observations',obs),('facial-values',values)]]
    return a,artifacts

class Contract(unittest.TestCase):
    def setUp(self):
        self.directory=Path(tempfile.mkdtemp(prefix='facial-review-'));self.a,self.artifacts=author(self.directory)
        binding=f.encoded({'original_source':{'hash':self.a['source']['sha256'],'size':100}}).decode()
        self.request={'schema':'brohn-facial-review-request/1.0','operation':'build','analysis':self.a,'artifacts':self.artifacts,'binding_json':binding,'binding_sha256':f.common.sha(binding.encode()),'index_path':str(self.directory/'index.sqlite')}
    def built(self):
        x=f.build(self.request);return {'index_path':x['index']['path'],'index':x['index'],'binding_sha256':self.request['binding_sha256']}
    def test_complete_and_preview_independence(self):
        r=self.built();x=f.read(dict(r,operation='plot',metric='AU01'));self.assertEqual(x['frames'],61);self.assertEqual(x['points'][60]['frame_index'],'60');self.assertEqual(x['points'][60]['value'],'0.5');self.assertEqual(x['points'][60]['connection'],'saved_support_gap')
    def test_exact_decimal_boundary(self):
        r=self.built();x=f.read(dict(r,operation='plot',metric='AU01',range=['0.10000000000000000001','0.2']));self.assertEqual([p['frame_index'] for p in x['points']],['2'])
    def test_state_only_and_empty(self):
        r=self.built();x=f.read(dict(r,operation='plot',metric='AU01',range=['1.5','1.5']));self.assertIsNone(x['points'][0]['value']);self.assertEqual(x['points'][0]['state'],'multiple_faces');self.assertEqual(f.read(dict(r,operation='plot',metric='AU01',range=['8','9']))['frames'],0)
    def test_all_native_categories_and_no_invented_zero(self):
        r=self.built()
        for metric in f.METRICS:
            x=f.read(dict(r,operation='plot',metric=metric));self.assertIsNone(x['points'][0]['value']);self.assertIsNone(x['points'][20]['value']);self.assertEqual(x['points'][1]['value'],'0.5' if metric in f.AUS else ('1.0' if metric=='neutral' else '0.0'))
    def test_pages_beyond_preview(self):
        r=self.built();x=f.read(dict(r,operation='page',metric='AU12',offset=50,limit=25));self.assertEqual(len(x['rows']),11);self.assertEqual(x['rows'][0]['frame_index'],'50')
    def test_frame_local_faces_preserved(self):
        r=self.built();x=f.read(dict(r,operation='detail',frame_index=15));self.assertEqual([y['face_ordinal'] for y in x['observation']['faces']],['1','2'])
    def test_full_export(self):
        r=self.built();x=f.read(dict(r,operation='export_csv',metric='AU12',output_path=str(self.directory/'export.csv')));self.assertEqual(x['rows'],62);self.assertEqual(x['frames'],61);rows=list(csv.DictReader(open(x['path'])));self.assertEqual(rows[-1]['native_value'],'0.5');self.assertEqual(rows[0]['native_value'],'');self.assertEqual(x['sha256'],hashlib.sha256(Path(x['path']).read_bytes()).hexdigest())
    def test_empty_export_keeps_header(self):
        r=self.built();x=f.read(dict(r,operation='export_csv',metric='AU12',range=['8','9'],output_path=str(self.directory/'empty.csv')));self.assertEqual(x['rows'],0);self.assertTrue(Path(x['path']).read_text().startswith('frame_index,'))
    def test_original_artifact_tamper(self):
        Path(self.artifacts[0]['path']).write_bytes(b'{}');self.assertRaises(ValueError,f.build,self.request)
    def test_original_csv_token_disagreement(self):
        p=Path(self.artifacts[1]['path']);p.write_text(p.read_text().replace('0.5','0.500',1));self.artifacts[1].update(f.common.descriptor(p));self.assertRaises(ValueError,f.build,self.request)
    def test_preview_mismatch(self):
        self.a['preview'][0]['source_pts']='2001';self.assertRaises(ValueError,f.build,self.request)
    def test_summary_mismatch(self):
        self.a['features'][0]['value']=.6;self.assertRaises(ValueError,f.build,self.request)
    def test_source_binding_mismatch(self):
        self.a['source']['bytes']=101;self.assertRaises(ValueError,f.build,self.request)
    def test_index_mutation(self):
        r=self.built();p=Path(r['index_path']);p.write_bytes(p.read_bytes()+b'X');self.assertRaises(ValueError,f.read,dict(r,operation='catalog'))
    def test_range_refusals(self):
        r=self.built()
        for rg in [['1e-2','2'],['2','1'],['0','600.0001'],['-1','2']]:self.assertRaises(ValueError,f.read,dict(r,operation='plot',metric='AU01',range=rg))
    def test_unanalysed_frame_refused(self):
        r=self.built();self.assertRaises(ValueError,f.read,dict(r,operation='detail',frame_index=61))
    def test_no_clobber(self):
        self.built();self.assertRaises(ValueError,f.build,self.request)

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--evidence');args=parser.parse_args()
    result=unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(Contract))
    if args.evidence:
        p=Path(args.evidence);p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps({'fixture':'hand-authored61-frame native-output contract data; not model accuracy evidence','tests':result.testsRun,'failures':len(result.failures),'errors':len(result.errors),'successful':result.wasSuccessful(),'sources':{str(x):hashlib.sha256(x.read_bytes()).hexdigest() for x in [Path(__file__),Path(f.__file__),Path(f.common.__file__)]}},indent=2))
    sys.exit(not result.wasSuccessful())
