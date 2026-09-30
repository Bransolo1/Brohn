"""Actual importer + independent Fraction oracle for every original export row."""
from pathlib import Path
from fractions import Fraction
import copy,csv,hashlib,json,sys,unittest
from unittest.mock import patch

from clock_test_support import ROOT,fresh_output
HERE=Path(__file__).resolve().parent
import clock_window,clock_preview,interchange
DEST=fresh_output();DEST.mkdir(parents=True,exist_ok=False)
BASE=9007199254741013

class Token(str):pass

def exact(value):
    if isinstance(value,Token):return str(value)
    if isinstance(value,list):return '['+','.join(map(exact,value))+']'
    if isinstance(value,dict):return '{'+','.join(json.dumps(k,ensure_ascii=False)+':'+exact(v)for k,v in value.items())+'}'
    return json.dumps(value,ensure_ascii=False,separators=(',',':'),allow_nan=False)

def recording(name,side,many=False,reset=False,participant='SYNTHETIC-PERSON',unit=None):
    source=side=='source';unit=unit or ('ns' if source else 'ms')
    clock={'id':name+'-clock','unit':unit,'kind':'device','representation':'decimal_string'}
    if unit=='ticks':clock['seconds_per_tick']='0.000000001'
    identity={'participant_id':participant,'session_id':'SYNTHETIC-VISIT','condition_id':'declared-condition','exposure_id':'original-exposure'}
    if many:
        st=[str(BASE+i*10000000) for i in range(150)] if source else [str(20000+i*10)for i in range(150)]
    else:
        st=[str(BASE+x)if x is not None else None for x in[-500000000,0,250000000,500000000,None,1500000000,2000000000,2500000000]] if source else ['19500','20000','20250','20500',None,'20750','21000','21250','21500','21750','22000','22020','22500']
    mt=[str(BASE),str(BASE+1000000000),str(BASE+2000000000),None] if source else ['20000','21025','22020',None]
    def stream(kind,times):
        samples=[]
        for i,t in enumerate(times):
            v='repeated sync' if kind=='markers' else -0.0 if i==1 else None if i in(0,2,6) else (i+1)/8
            row={'timestamp':t,'values':[v]}
            if reset and i==2:row['reset']=True
            samples.append(row)
        return {'id':name+'-'+kind,'name':name+' '+kind,'type':'Markers' if kind=='markers' else 'Synthetic voltage','kind':kind,
          'source_id':name+'-'+kind,'uid':name+'-'+kind,'clock':clock,'identity':identity,'nominal_srate':0 if kind=='markers' else 100 if many else 4,
          'channels':[{'id':'event' if kind=='markers' else 'voltage','label':'Original event' if kind=='markers' else 'Original voltage','type':'event' if kind=='markers' else 'EEG','unit':None if kind=='markers' else 'uV','value_type':'string' if kind=='markers' else 'float64'}], 'samples':samples}
    path=DEST/(name+'.json');path.write_text(json.dumps({'schema':'brohn-stream-bundle/1.0','origin':'sample','streams':[stream('markers',mt),stream('signal',st)]}),encoding='utf-8')
    imported=interchange.run({'schema':'brohn-interchange-request/1.0','operation':'import_multistream','format':'brohn_stream_bundle','source_path':str(path),'source_hash':interchange.digest(path),'output_directory':str(DEST/(name+'-import')),'metadata':{'origin':'sample','origin_statement':'Original generated clock-window fixture; no hardware or real person.','clock_policy':'preserve_only'}})
    tracks=[]
    for s in imported['streams']:
        def artifact(kind):
            a=next(a for a in s['artifacts']if a['kind']==kind);return {'path':a['path'],'hash':a['sha256'],'bytes':a['bytes']}
        tracks.append({'id':name+'/'+s['id']+'/'+s['channels'][0]['id'],'source_stream_id':s['id'],'kind':s['kind'],'origin':'sample','channel':s['channels'][0],'clock':s['clock'],'preservation':s['quality'],'sample_count':s['sample_count'],'segment_count':s['segment_count'],'samples':artifact('stream_samples_jsonl'),'evidence':artifact('stream_evidence_jsonl')})
    return {'dataset':{'id':'dataset-'+name,'revision':1,'hash':interchange.digest(path)},'imported':{'id':'import-'+name,'revision':1,'hash':hashlib.sha256(json.dumps(imported,sort_keys=True).encode()).hexdigest()},'marker':tracks[0],'tracks':[tracks[1]]}

def preview_request(source,reference):return {'schema':clock_preview.SCHEMA,'source':source,'reference':reference,'anchors':[{'source_sequence':1,'reference_sequence':1},{'source_sequence':3,'reference_sequence':3}],'checks':[{'source_sequence':2,'reference_sequence':2}],'review':{'confirmed':True,'rationale':'Explicit original marker rows identify the two defining synthetic events; retained check is independent.'}}

def loaded_rows(track):
    return [json.loads(line,parse_float=Token,parse_int=Token)for line in Path(track['samples']['path']).read_text(encoding='utf-8').splitlines()]

def expected(request,start,end):
    # Independent known fixture arithmetic, not mapping output or library helper.
    selected=[];unplaced=[];counts={k:0 for k in['source_rows','selected_rows','outside_anchor_span_rows','outside_window_rows','unplaced_rows','missing_source_values','missing_selected_values']}
    for side in('source','reference'):
        for t in [request[side]['marker'],*request[side]['tracks']]:
            for row in loaded_rows(t):
                counts['source_rows']+=1;value=row['values'][t['channel']['id']];state=row['value_states'][t['channel']['id']]
                missing=state!='observed' or value is None;counts['missing_source_values']+=int(missing)
                base={'recording_side':side,'track_id':t['id'],'source_sequence':str(row['sequence']),'value_json':exact(value),'source_timestamp':row['source_timestamp'] or '', 'value_state':state,'source_segment':row['segment_id'],'identity_json':exact(row['identity'])}
                if row['source_timestamp'] is None or row['timestamp_state']!='observed' or row['reconstructed_timestamp']:
                    counts['unplaced_rows']+=1;unplaced.append(base);continue
                raw=Fraction(row['source_timestamp']);original=raw/(10**9 if side=='source' else 1000)
                lo,hi=(Fraction(BASE,10**9),Fraction(BASE+2000000000,10**9))if side=='source' else(Fraction(20),Fraction(1101,50))
                if not lo<=original<=hi:counts['outside_anchor_span_rows']+=1;continue
                mapped=Fraction(20)+(raw-BASE)*Fraction(101,100000000000) if side=='source' else original
                relative=mapped-20
                if not start<=relative<end:counts['outside_window_rows']+=1;continue
                counts['selected_rows']+=1;counts['missing_selected_values']+=int(missing)
                for prefix,v in [('original_seconds',original),('reference_seconds',mapped),('reference_relative_seconds',relative)]:base[prefix+'_numerator']=str(v.numerator);base[prefix+'_denominator']=str(v.denominator)
                selected.append(base)
    return selected,unplaced,counts

class WindowTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.base=preview_request(recording('source','source'),recording('reference','reference'))
        cls.many=preview_request(recording('source-many','source',many=True),recording('reference-many','reference',many=True))
        cls.reset=recording('source-reset','source',reset=True)
        cls.foreign=recording('reference-foreign','reference',participant='ANOTHER-PERSON')
        cls.ticks=recording('source-ticks','source',unit='ticks')
        cls.originals={str(p):interchange.digest(p)for p in DEST.rglob('*')if p.is_file()}
        cls.code={str(p):interchange.digest(p)for p in[ROOT/'scripts/workers/clock_window.py',ROOT/'scripts/workers/clock_preview.py',ROOT/'scripts/workers/clock_source.py',ROOT/'scripts/workers/clock_affine.py',ROOT/'scripts/workers/interchange.py',ROOT/'scripts/workers/stream_extract.py']}
        cls.counter=0
    def request(self,start='0',end='2.02',offset=0,original=None):
        type(self).counter+=1;return {'schema':clock_window.SCHEMA,'preview_request':copy.deepcopy(original or self.base),'selection':{'start_s':start,'end_s':end,'offset':offset},'output_directory':str(DEST/('window-'+str(self.counter)))}
    def exports(self,q):
        result=clock_window.run(q);folder=Path(q['output_directory'])
        return result,list(csv.DictReader((folder/'selected.csv').open(encoding='utf-8',newline=''))),list(csv.DictReader((folder/'unplaced.csv').open(encoding='utf-8',newline='')))
    def oracle(self,q,result,selected,unplaced):
        es,eu,counts=expected(q['preview_request'],Fraction(q['selection']['start_s']),Fraction(q['selection']['end_s']))
        self.assertEqual(result['counts'],counts);self.assertEqual(len(selected),len(es));self.assertEqual(len(unplaced),len(eu))
        for actual,wanted in zip(selected,es):
            for k,v in wanted.items():self.assertEqual(actual[k],v,(k,actual,wanted))
        for actual,wanted in zip(unplaced,eu):
            for k,v in wanted.items():self.assertEqual(actual[k],v)
            self.assertEqual(actual['placement'],'unplaced');self.assertEqual(actual['coordinate_policy'],'no_time_assigned')
            self.assertTrue(all(actual[k]==''for k in clock_window.COLUMNS if k.endswith('_numerator')or k.endswith('_denominator')))
    def test_every_exported_fraction_and_original_value_matches_independent_oracle(self):
        q=self.request();r,s,u=self.exports(q);self.oracle(q,r,s,u)
        self.assertTrue(any(x['value_json']=='-0.0' for x in s));self.assertTrue(any(int(x['source_timestamp'])>2**53 for x in s if x['recording_side']=='source'))
        (DEST/'actual-window.json').write_text(json.dumps(r,indent=2),encoding='utf-8')
    def test_half_open_exact_window_and_separate_missing_counts(self):
        q=self.request('0.505','1.515');r,s,u=self.exports(q);self.oracle(q,r,s,u)
        self.assertGreater(r['counts']['missing_source_values'],r['counts']['missing_selected_values'])
        self.assertTrue(any(x['source_timestamp']==str(BASE+500000000)for x in s));self.assertFalse(any(x['source_timestamp']==str(BASE+1500000000)for x in s))
    def test_sub_binary64_boundary_is_not_rounded(self):
        q=self.request('0.505000000000000000001','1.515');r,s,u=self.exports(q);self.oracle(q,r,s,u)
        self.assertFalse(any(x['source_timestamp']==str(BASE+500000000)for x in s))
    def test_end_anchor_is_evidence_but_not_an_exclusive_window_row(self):
        q=self.request();r,s,u=self.exports(q)
        self.assertFalse(any(x['source_timestamp']==str(BASE+2000000000)for x in s));self.assertFalse(any(x['source_timestamp']=='22020'for x in s))
        self.assertEqual(r['preview']['anchors'][1]['source']['source_timestamp'],str(BASE+2000000000));self.assertGreater(r['counts']['outside_anchor_span_rows'],0);self.assertGreater(r['counts']['outside_window_rows'],0)
    def test_all_unplaced_rows_are_exported_without_guessed_membership(self):
        q=self.request('0.505','0.506');r,s,u=self.exports(q);self.oracle(q,r,s,u)
        self.assertEqual(len(u),4);self.assertEqual(r['unplaced_scope'],'complete original selected tracks; no window membership or time inferred')
    def test_complete_gap_and_segment_json_retained_exactly(self):
        q=self.request();r,_,_=self.exports(q);segments=[json.loads(line)for line in(Path(q['output_directory'])/'segments.jsonl').read_text().splitlines()]
        originals={}
        for side in('source','reference'):
            for t in[q['preview_request'][side]['marker'],*q['preview_request'][side]['tracks']]:
                for line in Path(t['evidence']['path']).read_text(encoding='utf-8').splitlines():
                    item=json.loads(line)
                    if item.get('type')=='source_segment':originals[(side,t['id'],item['id'])]=line
        self.assertEqual(len(segments),len(originals));self.assertTrue(any('sampling_gap' in row['segment_json'] for row in segments))
        for row in segments:self.assertEqual(row['segment_json'],originals[(row['recording_side'],row['track_id'],row['source_segment'])])
    def test_exact_100row_paging_does_not_change_complete_csv(self):
        q=self.request(original=self.many);a,sa,ua=self.exports(q);q2=self.request(original=self.many,offset=100);b,sb,ub=self.exports(q2)
        self.assertEqual(sa,sb);self.assertEqual(ua,ub);self.assertEqual(len(a['rows']),100);self.assertEqual(len(b['rows']),100)
        self.assertEqual([str(x['source_sequence'])for x in b['rows']],[x['source_sequence']for x in sb[100:200]])
        self.assertNotEqual(a['binding']['selection_sha256'],b['binding']['selection_sha256']);self.assertEqual(a['binding']['preview_sha256'],b['binding']['preview_sha256'])
    def test_empty_window_is_header_only_with_unplaced_preserved(self):
        q=self.request('0.001','0.002');r,s,u=self.exports(q);self.oracle(q,r,s,u)
        self.assertEqual(r['status'],'empty_window');self.assertEqual(s,[]);self.assertEqual(len(u),4);self.assertEqual(r['rows'],[])
    def test_declared_ticks_keep_exact_scaling(self):
        original=copy.deepcopy(self.base);original['source']=self.ticks;q=self.request(original=original);r,s,u=self.exports(q);self.oracle(q,r,s,u)
        self.assertTrue(all(x['timestamp_unit']=='ticks'for x in s if x['recording_side']=='source'))
    def test_schema_bounds_and_existing_destination_fail_before_preview_read(self):
        cases=[]
        for start,end,offset in[('-1','1',0),('1','1',0),('0','86400.01',0),('0','1',True),('0','1',1),('0','1',2000100),('NaN','1',0)]:cases.append(self.request(start,end,offset))
        q=self.request();q['output_directory']=str(DEST);cases.append(q)
        q=self.request();q['preview_json']={};cases.append(q)
        for q in cases:
            with patch.object(clock_window,'build_preview',side_effect=AssertionError('source read')):
                with self.assertRaises(ValueError):clock_window.run(q)
    def test_end_outside_anchor_span_refused_without_extrapolation(self):
        q=self.request('0','2.020000000000000000001')
        with self.assertRaisesRegex(ValueError,'anchor span'):clock_window.run(q)
        self.assertFalse(Path(q['output_directory']).exists())
    def test_unsupported_reset_and_different_person_refused_by_fresh_preview(self):
        for side,rec in[('source',self.reset),('reference',self.foreign)]:
            original=copy.deepcopy(self.base);original[side]=rec;q=self.request(original=original)
            with self.assertRaises(ValueError):clock_window.run(q)
            self.assertFalse(Path(q['output_directory']).exists())
    def test_saved_preview_cannot_substitute_original_source_request(self):
        q=self.request();q['preview_request']=clock_preview.build_preview(q['preview_request'])
        with self.assertRaisesRegex(ValueError,'preview request'):clock_window.run(q)
    def test_fresh_preview_and_single_export_mapper_reused_across_rows(self):
        q=self.request();seen=[];original=clock_window.map_position
        def mapped(m,t):seen.append(id(m));return original(m,t)
        with patch.object(clock_window,'build_preview',wraps=clock_window.build_preview)as preview,patch.object(clock_window,'build_affine',wraps=clock_window.build_affine)as build,patch.object(clock_window,'map_position',side_effect=mapped):r,_,_=self.exports(q)
        self.assertEqual(preview.call_count,1);self.assertEqual(build.call_count,1);self.assertGreater(len(seen),2);self.assertEqual(len(set(seen)),1)
    def test_full_request_preview_selection_and_hash_binding_in_every_descriptor(self):
        q=self.request();original=copy.deepcopy(q);r,_,_=self.exports(q);self.assertEqual(q,original)
        self.assertEqual(r['binding']['preview_sha256'],clock_window._hash(clock_preview.build_preview(q['preview_request'])))
        self.assertNotIn(str(DEST),json.dumps(r));self.assertIn('requires_current_R',r['authorization'])
        folder=Path(q['output_directory']);self.assertLessEqual(sum(p.stat().st_size for p in folder.iterdir()),clock_window.MAX_EXPORT)
        for a in r['artifacts']:
            self.assertEqual(a['binding'],r['binding']);self.assertEqual(a['sha256'],interchange.digest(folder/a['file']));self.assertEqual(a['bytes'],(folder/a['file']).stat().st_size)
    def test_combined_output_limit_leaves_no_accepted_manifest(self):
        q=self.request(original=self.many)
        with patch.object(clock_window,'MAX_EXPORT',8192):
            with self.assertRaisesRegex(ValueError,'64MiB'):clock_window.run(q)
        folder=Path(q['output_directory']);self.assertFalse((folder/'manifest.json').exists());self.assertTrue(all(p.name.endswith('.partial')for p in folder.iterdir()));self.assertLessEqual(sum(p.stat().st_size for p in folder.iterdir()),8192)
    def test_late_source_change_refuses_publication(self):
        q=self.request();track=q['preview_request']['source']['tracks'][0];original=Path(track['samples']['path']);copy_path=DEST/'deliberate-late-source.jsonl';copy_path.write_bytes(original.read_bytes());track['samples']['path']=str(copy_path)
        reader=clock_window._exact_rows
        def mutate_after(path):
            yield from reader(path)
            if Path(path)==copy_path:copy_path.write_bytes(copy_path.read_bytes()+b' ')
        with patch.object(clock_window,'_exact_rows',side_effect=mutate_after):
            with self.assertRaisesRegex(ValueError,'SHA-256'):clock_window.run(q)
        self.assertFalse((Path(q['output_directory'])/'manifest.json').exists())
    def test_out_of_range_page_refuses_accepted_manifest(self):
        q=self.request(offset=100)
        with self.assertRaisesRegex(ValueError,'Numerical page'):clock_window.run(q)
        self.assertFalse((Path(q['output_directory'])/'manifest.json').exists())
    def test_zz_original_sources_and_all_dependency_code_remain_unchanged(self):
        self.assertTrue(all(interchange.digest(Path(p))==h for p,h in self.originals.items()));self.assertTrue(all(interchange.digest(Path(p))==h for p,h in self.code.items()))

suite=unittest.defaultTestLoader.loadTestsFromTestCase(WindowTests);result=unittest.TextTestRunner(verbosity=2).run(suite)
receipt={'passed':result.wasSuccessful(),'groups':result.testsRun,'failures':len(result.failures),'errors':len(result.errors),'source_sha256':interchange.digest(ROOT/'scripts/workers/clock_window.py'),'test_sha256':interchange.digest(Path(__file__)),'dependencies':getattr(WindowTests,'code',{}),'scope':'External actual-preservation-importer plus independent every-row exact Fraction/value/endpoint oracle; no application authorization/publication or browser claim.','production_files_changed':0,'services':0,'scientific_jobs':0}
(DEST/'results.json').write_text(json.dumps(receipt,indent=2),encoding='utf-8');sys.exit(0 if result.wasSuccessful() else 1)
