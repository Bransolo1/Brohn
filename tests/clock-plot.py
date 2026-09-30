"""Complete importer/window artifacts plus independent integer/rational oracle."""
import copy,csv,hashlib,io,json,sqlite3,sys,unittest,shutil
from decimal import Decimal,localcontext
from fractions import Fraction
from pathlib import Path
from unittest.mock import patch
from clock_test_support import ROOT,fresh_output
HERE=Path(__file__).resolve().parent
import clock_plot as plot
import interchange,clock_window,clock_preview,clock_source
OUT=fresh_output();OUT.mkdir(parents=True,exist_ok=False);sys.argv=sys.argv[:1]
BASE=9007199254741013
def digest(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def dump(v):return json.dumps(v,sort_keys=True,ensure_ascii=True,separators=(',',':'),allow_nan=False).encode()

def recording(side):
    source=side=='source';unit='ns' if source else 'ms'
    clock={'id':side+'-clock','unit':unit,'kind':'device','representation':'decimal_string'}
    identity={'participant_id':'SYNTHETIC-PERSON','session_id':'SYNTHETIC-VISIT','condition_id':'condition-a','exposure_id':'exposure-a'}
    def timestamp(i,marker=False):
        if marker:return str(BASE+i*800000) if source else str(Fraction(20000)+Fraction(i*808,1000))
        return str(BASE+i*1000000) if source else str(20000+i*2)
    # Reference marker coordinates are exact decimal milliseconds, never fraction syntax.
    marker_times=[str(BASE) if source else '20000']
    for i in range(1,2401):marker_times.append(str(BASE+i*800000) if source else f'{20000+i*808//1000}.{i*808%1000:03d}')
    marker_times.append(str(BASE+2000000000) if source else '22020')
    signals=[]
    for i in range(1200 if source else 700):
        row={'timestamp':None if i==300 else timestamp(i),'values':[None if i==200 else 10000 if i==777 else -5000 if i==950 else ((i%17)-8)/8]}
        if i>=500:row['identity']={**identity,'condition_id':'condition-b'}
        signals.append(row)
    def stream(kind,samples):return {'id':side+'-'+kind,'name':side+' '+kind,'type':'Markers' if kind=='markers' else 'Original voltage','kind':kind,
        'source_id':side+'-'+kind,'uid':side+'-'+kind,'clock':clock,'identity':identity,'nominal_srate':0 if kind=='markers' else 1000 if source else 500,
        'channels':[{'id':'event' if kind=='markers' else 'voltage','label':'Original event' if kind=='markers' else 'Original voltage','type':'event' if kind=='markers' else 'EEG','unit':None if kind=='markers' else 'uV','value_type':'string' if kind=='markers' else 'float64'}],'samples':samples}
    bundle=OUT/(side+'.json');bundle.write_bytes(dump({'schema':'brohn-stream-bundle/1.0','origin':'sample','streams':[stream('markers',[{'timestamp':t,'values':['repeated sync']} for t in marker_times]),stream('signal',signals)]}))
    imported=interchange.run({'schema':'brohn-interchange-request/1.0','operation':'import_multistream','format':'brohn_stream_bundle','source_path':str(bundle),'source_hash':digest(bundle),'output_directory':str(OUT/(side+'-import')),'metadata':{'origin':'sample','origin_statement':'Generated clock display fixture; no participant, hardware or inference.','clock_policy':'preserve_only'}})
    tracks=[]
    for s in imported['streams']:
        def artifact(kind):
            a=next(x for x in s['artifacts'] if x['kind']==kind);return{'path':a['path'],'hash':a['sha256'],'bytes':a['bytes']}
        tracks.append({'id':side+'/'+s['id']+'/'+s['channels'][0]['id'],'source_stream_id':s['id'],'kind':s['kind'],'origin':'sample','channel':s['channels'][0],'clock':s['clock'],'preservation':s['quality'],'sample_count':s['sample_count'],'segment_count':s['segment_count'],'samples':artifact('stream_samples_jsonl'),'evidence':artifact('stream_evidence_jsonl')})
    return {'dataset':{'id':side,'revision':1,'hash':digest(bundle)},'imported':{'id':side+'-import','revision':1,'hash':hashlib.sha256(dump(imported)).hexdigest()},'marker':tracks[0],'tracks':[tracks[1]]}

class Tests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.n=0;cls.original={'schema':clock_preview.SCHEMA,'source':recording('source'),'reference':recording('reference'),
           'anchors':[{'source_sequence':1,'reference_sequence':1},{'source_sequence':2402,'reference_sequence':2402}],'checks':[],
           'review':{'confirmed':True,'rationale':'Explicit original generated marker rows select a known positive101/100 mapping.'}}
        cls.window=cls.make_window();cls.page=cls.make_window(offset=100);cls.last_page=cls.make_window(offset=6600);cls.empty=cls.make_window(start='1.999',end='2.001')
        cls.original_files={str(p):digest(p) for p in OUT.rglob('*') if p.is_file()}
        cls.code={str(p):digest(p) for p in [ROOT/'scripts/workers/clock_plot.py',*(ROOT/'scripts/workers').glob('clock_*.py')]}
    @classmethod
    def make_window(cls,offset=0,start='0',end='2.02'):
        cls.n+=1;folder=OUT/f'original-window-{cls.n}'
        r=clock_window.run({'schema':clock_window.SCHEMA,'preview_request':copy.deepcopy(cls.original),'selection':{'start_s':start,'end_s':end,'offset':offset},'output_directory':str(folder)})
        a={'kind':'clock_window_manifest','file':'manifest.json','sha256':digest(folder/'manifest.json'),'bytes':(folder/'manifest.json').stat().st_size,'media_type':'application/json'}
        return {'schema':'brohn-clock-window-worker-result/0.1','result':r,'manifest_artifact':a},folder
    def request(self,window=None):
        type(self).n+=1;envelope,folder=window or self.window
        return {'schema':'brohn-clock-plot-input/0.1','window_ref':{'id':'generated-window','revision':1,'hash':hashlib.sha256(dump(envelope)).hexdigest(),'project_id':'sample'},
                'map_ref':{'id':'generated-map','revision':1,'hash':hashlib.sha256(dump(envelope['result']['preview'])).hexdigest()},'window_result':copy.deepcopy(envelope),
                'artifacts':[{'kind':a['kind'],'path':str(folder/a['file']),'hash':a['sha256'],'bytes':a['bytes']} for a in [*envelope['result']['artifacts'],envelope['manifest_artifact']]],
                'display':{'profile':plot.PROFILE,'bins':512},'output_directory':str(OUT/f'plot-{self.n}')}
    def rows(self,q,kind='selected_original_rows'):
        a=next(x for x in q['artifacts'] if x['kind']==kind)
        with Path(a['path']).open(encoding='utf-8',newline='') as source:return list(csv.DictReader(source))
    def altered(self,change):
        q=self.request();folder=OUT/f'variant-{self.n}';folder.mkdir();r=q['window_result']['result'];rows=self.rows(q);change(rows,r)
        for a in q['artifacts']:
            old=Path(a['path']);new=folder/next(x['file'] for x in [*r['artifacts'],q['window_result']['manifest_artifact']] if x['kind']==a['kind'])
            if a['kind']=='selected_original_rows':
                with new.open('w',encoding='utf-8',newline='') as f:w=csv.DictWriter(f,fieldnames=plot.COLUMNS,lineterminator='\n');w.writeheader();w.writerows(rows)
            elif a['kind']!='clock_window_manifest':new.write_bytes(old.read_bytes())
            a['path']=str(new)
        for a in q['artifacts']:
            if a['kind']=='clock_window_manifest':continue
            a['hash']=digest(a['path']);a['bytes']=Path(a['path']).stat().st_size
            descriptor=next(x for x in r['artifacts'] if x['kind']==a['kind']);descriptor['sha256']=a['hash'];descriptor['bytes']=a['bytes']
        manifest=next(a for a in q['artifacts'] if a['kind']=='clock_window_manifest');Path(manifest['path']).write_bytes(dump(r)+b'\n');manifest['hash']=digest(manifest['path']);manifest['bytes']=Path(manifest['path']).stat().st_size
        q['window_result']['manifest_artifact'].update(sha256=manifest['hash'],bytes=manifest['bytes'])
        return q
    def test_01_complete_unequal_rate_oracle_every_representative(self):
        q=self.request();r=plot.prepare_plot(q);rows=self.rows(q);lookup={(x['recording_side'],x['track_id'],int(x['source_sequence'])):x for x in rows}
        self.assertEqual(r['coverage']['complete_selected_rows_read'],len(rows));self.assertTrue(all(x['kind']=='markers' for x in rows[:100]))
        for lane in r['lanes']:
            expected=[x for x in rows if x['track_id']==lane['track_id'] and x['value_state']=='observed' and x['value_json']!='null']
            values=[Fraction(x['value_json']) for x in expected]
            self.assertEqual(lane['display_counts']['numeric_observed'],len(values));self.assertEqual(Fraction(lane['exact_y_range']['minimum']['value_json']),min(values));self.assertEqual(Fraction(lane['exact_y_range']['maximum']['value_json']),max(values))
            for run in lane['runs']:
                for group in run['groups']:
                    candidates=[]
                    for x in expected:
                        sequence=int(x['source_sequence'])
                        if not run['first_sequence']<=sequence<=run['last_sequence']:continue
                        t=(Fraction(x['source_timestamp'])-BASE)*Fraction(101,100000000000) if lane['recording_side']=='source' else Fraction(x['source_timestamp'])/1000-20
                        if int(t*Fraction(51200,202))==group['bin']:candidates.append(x)
                    self.assertEqual(group['observation_count'],len(candidates))
                    retained=[candidates[0],candidates[-1],min(candidates,key=lambda x:Fraction(x['value_json'])),max(candidates,key=lambda x:Fraction(x['value_json']))]
                    self.assertEqual([p['source_sequence'] for p in group['points']],sorted({int(x['source_sequence']) for x in retained}))
                    for p in group['points']:
                        x=lookup[(lane['recording_side'],lane['track_id'],p['source_sequence'])]
                        t=(Fraction(x['source_timestamp'])-BASE)*Fraction(101,100000000000) if lane['recording_side']=='source' else Fraction(x['source_timestamp'])/1000-20
                        self.assertEqual(p['relative_fraction'],{'numerator':str(t.numerator),'denominator':str(t.denominator)})
                        self.assertEqual(p['value_json'],x['value_json']);self.assertEqual(group['bin'],int(t*Fraction(51200,202)))
            self.assertEqual(sum(g['observation_count'] for x in lane['runs'] for g in x['groups']),len(values))
        source=next(x for x in r['lanes'] if x['recording_side']=='source');self.assertEqual(source['exact_y_range']['maximum']['value_json'],'10000.0');self.assertEqual(source['exact_y_range']['maximum']['original_row_reference']['source_sequence'],778)
        (OUT/'actual-plot.json').write_bytes(dump(r))
    def test_02_numerical_offset_never_truncates_plot(self):
        a=plot.prepare_plot(self.request())
        for window in (self.page,self.last_page):
            b=plot.prepare_plot(self.request(window))
            for key in ('lanes','events','coverage','axis'):self.assertEqual(a[key],b[key])
            self.assertNotEqual(a['binding']['selection_sha256'],b['binding']['selection_sha256'])
    def test_03_gap_missing_unplaced_context_never_join_runs(self):
        r=plot.prepare_plot(self.request())
        for lane in r['lanes']:
            causes={k for b in lane['breaks'] for k in b['causes']}
            self.assertTrue({'saved_missing_value','source_sequence_discontinuity','original_segment_boundary','original_identity_context_change'}<=causes)
            for run in lane['runs']:
                seqs=[p['source_sequence'] for g in run['groups'] for p in g['points']]
                self.assertFalse(min(seqs)<201<max(seqs));self.assertFalse(min(seqs)<301<max(seqs));self.assertFalse(min(seqs)<501<=max(seqs))
        self.assertEqual(r['coverage']['complete_unplaced_rows_read'],2)
    def test_04_marker_bins_count_every_repeated_event(self):
        q=self.request();r=plot.prepare_plot(q)
        for lane in r['events']:
            self.assertEqual(lane['mode'],'counted_bins');self.assertEqual(lane['events'],[]);self.assertEqual(sum(b['count'] for b in lane['bins']),2401)
            for b in lane['bins']:
                self.assertEqual(json.loads(b['first']['value_json']),'repeated sync');self.assertLessEqual(b['first']['original_row_reference']['source_sequence'],b['last']['original_row_reference']['source_sequence'])
    def test_05_empty_is_not_flat_zero(self):
        r=plot.prepare_plot(self.request(self.empty));self.assertEqual(r['status'],'empty_window')
        self.assertTrue(all(x['runs']==[] and x['exact_y_range']['minimum'] is None for x in r['lanes']))
    def test_06_projection_envelope_keeps_unsupported_separate(self):
        def change(rows,_):next(x for x in rows if x['kind']=='signal')['value_json']='1e309'
        r=plot.prepare_plot(self.altered(change));lane=r['lanes'][0]
        self.assertEqual(lane['display_counts']['exact_export_only'],1);self.assertEqual(lane['display_counts']['saved_missing'],1)
    def test_07_truncation_after_first100_is_refused(self):
        q=self.altered(lambda rows,_:rows.__delitem__(slice(100,None)))
        with self.assertRaisesRegex(ValueError,'count'):plot.prepare_plot(q)
        self.assertFalse(Path(q['output_directory']).exists())
    def test_08_wrong_track_or_order_refused(self):
        for mutate in [lambda rows,_:rows.reverse(),lambda rows,_:rows[0].__setitem__('track_id','another')]:
            with self.assertRaises(ValueError):plot.prepare_plot(self.altered(mutate))
    def test_09_exclusive_end_and_reduced_fraction_refused(self):
        for n,d in [('202','100'),('101','50')]:
            def change(rows,_,n=n,d=d):rows[0]['reference_relative_seconds_numerator']=n;rows[0]['reference_relative_seconds_denominator']=d
            with self.assertRaises(ValueError):plot.prepare_plot(self.altered(change))
    def test_10_wrong_binding_or_artifact_hash_refused(self):
        q=self.request();q['artifacts'][0]['hash']='0'*64
        with self.assertRaises(ValueError):plot.prepare_plot(q)
        q=self.request();q['window_result']['result']['binding']['preview_sha256']='0'*64
        with self.assertRaises(ValueError):plot.prepare_plot(q)
    def test_11_every_display_bound_refuses_without_partial_plot(self):
        for name,value in [('MAX_VERTICES',2),('MAX_RUNS_BREAKS',1),('MAX_OUTPUT',300)]:
            q=self.request()
            with patch.object(plot,name,value):
                with self.assertRaises(ValueError):plot.prepare_plot(q)
            self.assertFalse((Path(q['output_directory'])/'plot.json').exists())
    def test_12_late_byte_mutation_cannot_publish(self):
        q=self.altered(lambda *_:None);a=q['artifacts'][0];path=Path(a['path']);old=path.read_bytes();calls=0;verify=plot.verify
        def mutate(item):
            nonlocal calls
            calls+=1
            if calls==9:path.write_bytes(old[:-1]+b' ')
            return verify(item)
        try:
            with patch.object(plot,'verify',mutate):
                with self.assertRaises(ValueError):plot.prepare_plot(q)
            self.assertFalse((Path(q['output_directory'])/'plot.json').exists());self.assertTrue((Path(q['output_directory'])/'plot.json.partial').exists())
        finally:path.write_bytes(old)
    def test_13_numeric_decimal_parser_boundaries(self):
        self.assertEqual(plot.decimal('-0.0',True),0);self.assertEqual(plot.decimal('1e-324',True),Fraction(1,10**324));self.assertEqual(plot.decimal('1e308',True),10**308)
        for token in ['true','null','"3"','+3','01','1e309','1e-325','0e501','1e999999','9'*129,'NaN']:
            with self.assertRaises(ValueError,msg=token):plot.decimal(token,True)
    def test_14_exact_bin_boundary_large_epoch_and_negative_values(self):
        # Independent boundary ratios, injected as an explicitly synthetic display contract variant.
        q=self.request();rows=self.rows(q);lane=[x for x in rows if x['kind']=='signal'];self.assertTrue(any(int(x['source_timestamp'])>2**53 for x in lane if x['recording_side']=='source'))
        values=[Fraction(x['value_json']) for x in lane if x['value_json']!='null'];self.assertLess(min(values),0);self.assertIn(0,values)
        edge=Fraction(101,25600);self.assertEqual(int(edge/Fraction(101,50)*512),1);self.assertEqual(int((edge-Fraction(1,10**30))/Fraction(101,50)*512),0)
        self.assertEqual(plot.fraction(str(edge.numerator),str(edge.denominator)),edge)
    def test_16_constant_signal_keeps_real_first_last_and_exact_value(self):
        def change(rows,_):
            for row in rows:
                if row['kind']=='signal' and row['value_state']=='observed' and row['value_json']!='null':row['value_json']='-0.0'
        r=plot.prepare_plot(self.altered(change))
        for lane in r['lanes']:
            self.assertTrue(lane['exact_y_range']['constant']);self.assertEqual(lane['exact_y_range']['minimum']['value_json'],'-0.0')
            for run in lane['runs']:
                for group in run['groups']:
                    self.assertLessEqual(len(group['points']),2)
                    self.assertTrue(all(p['value_json']=='-0.0' and p['display_y_fraction']=={'numerator':'1','denominator':'2'} for p in group['points']))
    def test_17_exact_bin_edge_component_not_binary64_projection(self):
        edge=Fraction(101,25600);epsilon=Fraction(1,10**30)
        def change(rows,_):
            signals=[x for x in rows if x['kind']=='signal' and x['recording_side']=='source']
            # This explicit synthetic export variant keeps all original/mapped
            # coordinate pairs consistent, rather than changing only display time.
            for x,t in zip(signals[3:6],[edge-epsilon,edge,edge+epsilon]):
                original=Fraction(BASE,10**9)+t*Fraction(100,101)
                with localcontext() as context:
                    context.prec=150
                    x['source_timestamp']=format(Decimal((original*10**9).numerator)/Decimal((original*10**9).denominator),'f')
                # A finite decimal timestamp needs a terminating rational. Use
                # epsilon with factor101 so that scale inversion cancels exactly.
                actual=Fraction(x['source_timestamp'])/10**9
                self.assertEqual(actual,original)
                for prefix,value in [('original_seconds',original),('reference_seconds',20+t),('reference_relative_seconds',t)]:
                    x[prefix+'_numerator']=str(value.numerator);x[prefix+'_denominator']=str(value.denominator)
        epsilon=Fraction(101,10**32)
        r=plot.prepare_plot(self.altered(change));lane=next(x for x in r['lanes'] if x['recording_side']=='source')
        points={p['source_sequence']:p for run in lane['runs'] for g in run['groups'] for p in g['points']}
        self.assertEqual(points[4]['bin'],0);self.assertEqual(points[5]['bin'],1)
        self.assertEqual(points[4]['relative_fraction'],{'numerator':str((edge-epsilon).numerator),'denominator':str((edge-epsilon).denominator)})
    def test_18_existing_output_refusal_never_replaces_original(self):
        q=self.request();r=plot.prepare_plot(q);out=Path(q['output_directory'])/'plot.json';before=out.read_bytes()
        with self.assertRaises(ValueError):plot.prepare_plot(q)
        self.assertEqual(out.read_bytes(),before)
    def test_19_coordinate_relationships_cannot_be_rewritten_independently(self):
        for prefix in ('original_seconds','reference_seconds','reference_relative_seconds'):
            def change(rows,_,prefix=prefix):
                row=next(x for x in rows if x['kind']=='signal')
                value=Fraction(int(row[prefix+'_numerator']),int(row[prefix+'_denominator']))+Fraction(1,10**20)
                row[prefix+'_numerator']=str(value.numerator);row[prefix+'_denominator']=str(value.denominator)
            with self.assertRaisesRegex(ValueError,'coordinate changed'):plot.prepare_plot(self.altered(change))
    def test_20_bounded_serialization_matches_canonical_bytes_and_stops_early(self):
        data={'text':'\u00e9\n','zero':-0.0,'values':[1,True,None]};expected=dump(data)
        self.assertEqual(plot.bounded_encoded(data,len(expected)),expected)
        with self.assertRaises(ValueError):plot.bounded_encoded(data,len(expected)-1)
        class Explode(dict):
            def items(self):raise AssertionError('Encoder should stop before traversing the next large object.')
        with self.assertRaises(ValueError):plot.bounded_encoded(['x'*200,Explode({'test':1})],100)
    def test_21_marker_only_window_is_not_a_zero_signal(self):
        # Both selected signals end before1.92, but the original marker streams continue.
        r=plot.prepare_plot(self.request(self.make_window(start='1.91',end='1.93')))
        self.assertEqual(r['status'],'no_supported_numeric_signal')
        self.assertTrue(all(x['runs']==[] and x['exact_y_range']['minimum'] is None for x in r['lanes']))
        self.assertTrue(all(x['mode']=='individual' and len(x['events'])>0 for x in r['events']))
    def test_22_all_unavailable_signal_values_never_form_vertices(self):
        def change(rows,r):
            for row in rows:
                if row['kind']=='signal':row['value_json']='null';row['value_state']='missing'
            for track in r['tracks']:
                if track['channel']['id']=='voltage':
                    track['missing_selected_values']=track['selected_rows'];track['missing_source_values']=track['source_rows']
            for key in ('missing_selected_values','missing_source_values'):r['counts'][key]=sum(t[key] for t in r['tracks'])
        r=plot.prepare_plot(self.altered(change));self.assertEqual(r['status'],'no_supported_numeric_signal')
        for lane in r['lanes']:
            self.assertEqual(lane['runs'],[]);self.assertEqual(lane['display_counts']['representatives'],0)
            self.assertEqual(lane['display_counts']['saved_missing'],lane['display_counts']['selected_rows'])
    def test_23_upstream_optional_identity_omission_is_distinct_from_null(self):
        identity={'participant_id':'SYNTHETIC-PERSON','session_id':'SYNTHETIC-VISIT'}
        self.assertEqual(clock_source._identity(identity),identity)
        self.assertEqual(interchange.identity(identity),identity)
        for key in ('condition_id','exposure_id'):
            with self.assertRaises(ValueError):clock_source._identity({**identity,key:None})
            with self.assertRaises(ValueError):interchange.identity({**identity,key:None})
    def test_24_large_epoch_tiny_window_retains_distinct_axis_and_real_singleton(self):
        window=self.make_window(start='0.00403999999999999999',end='0.00404000000000000001')
        q=self.request(window);r=plot.prepare_plot(q)
        self.assertEqual(r['coverage']['complete_selected_rows_read'],3)
        self.assertEqual(r['coverage']['numeric_observations_represented'],1)
        lane=next(x for x in r['lanes'] if x['recording_side']=='source');point=lane['runs'][0]['groups'][0]['points'][0]
        self.assertEqual(point['source_sequence'],5);self.assertEqual(point['relative_fraction'],{'numerator':'101','denominator':'25000'})
        self.assertEqual(point['display_x'],0.5);self.assertEqual(point['display_y'],0.5)
        self.assertEqual(len({t['display_offset_label'] for t in r['axis']['ticks']}),5)
        self.assertEqual(r['axis']['display_base_exact_decimal'],'0.00403999999999999999')
    def test_99_original_artifacts_and_accepted_code_unchanged(self):
        for file,h in {**self.original_files,**self.code}.items():self.assertEqual(digest(file),h,file)

suite=unittest.defaultTestLoader.loadTestsFromTestCase(Tests);result=unittest.TextTestRunner(verbosity=2).run(suite)
receipt={'passed':result.wasSuccessful(),'tests':result.testsRun,'failures':[(str(t),e) for t,e in result.failures+result.errors],
 'scope':'External display component: fresh actual synthetic importer+window fixtures; saved-catalog reuse is covered separately. No application authorization, jobs, UI or scientific validation claim.',
 'source':{str(ROOT/'scripts/workers/clock_plot.py'):digest(ROOT/'scripts/workers/clock_plot.py'),str(Path(__file__)):digest(Path(__file__))}}
(OUT/'results.json').write_text(json.dumps(receipt,indent=2),encoding='utf-8');raise SystemExit(0 if result.wasSuccessful() else 1)
