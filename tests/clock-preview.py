"""Exact independent source pairs passed through the real preservation importer."""
from pathlib import Path
import copy
import hashlib
import json
import sys
import unittest
from unittest.mock import patch

from clock_test_support import ROOT,fresh_output
HERE=Path(__file__).resolve().parent
import clock_preview
import interchange

DEST = fresh_output()
DEST.mkdir(parents=True, exist_ok=False)
S = 9007199254741013


def recording(name, participant='EXPLICIT-PERSON', origin='sample', reverse=False):
    source = name.startswith('source')
    clock = {'id': name+'-clock', 'unit':'ns' if source else 'ms', 'kind':'device', 'representation':'decimal_string'}
    identity = {'participant_id':participant, 'session_id':'EXPLICIT-VISIT'}
    signal_times = [str(S+i*500000000) for i in range(5)] if source else [str(20000+i*250) for i in range(9)]
    marker_times = [str(S), str(S+1000000000), str(S+2000000000)] if source else ['20000', '21025', '22020']
    if reverse:
        marker_times[-1] = marker_times[0]
    def stream(kind, times):
        return {'id':name+'-'+kind, 'name':name+' '+kind, 'source_id':name+'-'+kind, 'uid':name+'-'+kind,
                'clock':clock, 'identity':identity, 'kind':kind, 'type':'Markers' if kind=='markers' else 'Synthetic voltage',
                'nominal_srate':0 if kind=='markers' else (2 if source else 4),
                'channels':[{'id':'event' if kind=='markers' else 'voltage', 'label':'Recorded marker' if kind=='markers' else 'Voltage',
                             'unit':None if kind=='markers' else 'uV', 'type':'event' if kind=='markers' else 'EEG',
                             'value_type':'string' if kind=='markers' else 'float64'}],
                'samples':[{'timestamp':t, 'values':['repeated sync' if kind=='markers' else (None if i==2 else i*2)]} for i,t in enumerate(times)]}
    path=DEST/(name+'.json')
    path.write_text(json.dumps({'schema':'brohn-stream-bundle/1.0','origin':origin,'streams':[stream('signal',signal_times),stream('markers',marker_times)]}),encoding='utf-8')
    result=interchange.run({'schema':'brohn-interchange-request/1.0','operation':'import_multistream','format':'brohn_stream_bundle',
        'source_path':str(path),'source_hash':interchange.digest(path),'output_directory':str(DEST/(name+'-import')),
        'metadata':{'origin':origin,'origin_statement':'Original generated comparison fixture; no physical timing or person.','clock_policy':'preserve_only'}})
    tracks=[]
    for s in result['streams']:
        def artifact(kind):
            a=next(x for x in s['artifacts'] if x['kind']==kind)
            return {'path':a['path'],'hash':a['sha256'],'bytes':a['bytes']}
        tracks.append({'id':name+'/'+s['id']+'/'+s['channels'][0]['id'], 'source_stream_id':s['id'],'kind':s['kind'],'origin':origin,
            'channel':s['channels'][0],'clock':s['clock'],'preservation':s['quality'],'sample_count':s['sample_count'],'segment_count':s['segment_count'],
            'samples':artifact('stream_samples_jsonl'),'evidence':artifact('stream_evidence_jsonl')})
    return {'dataset':{'id':'dataset-'+name,'revision':1,'hash':interchange.digest(path)},
            'imported':{'id':'import-'+name,'revision':1,'hash':hashlib.sha256(json.dumps(result,sort_keys=True).encode()).hexdigest()},
            'marker':tracks[1], 'tracks':[tracks[0]]}


class PreviewTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.base={'schema':clock_preview.SCHEMA,'source':recording('source'), 'reference':recording('reference'),
            'anchors':[{'source_sequence':1,'reference_sequence':1},{'source_sequence':3,'reference_sequence':3}],
            'checks':[{'source_sequence':2,'reference_sequence':2}],
            'review':{'confirmed':True,'rationale':'The two explicit recorded pulses identify the same events; held-out pulse tests residual only.'}}
        cls.mismatch=recording('reference-other-person','OTHER-PERSON')
        cls.origin=recording('reference-pilot',origin='pilot')
        cls.reset=recording('reference-reversal',reverse=True)
        cls.originals={str(p):interchange.digest(p) for p in DEST.rglob('*') if p.is_file()}

    def request(self):
        return copy.deepcopy(self.base)

    def test_exact_nonunit_scale_and_nonzero_heldout_residual(self):
        r=clock_preview.build_preview(self.request())
        self.assertEqual(r['mapping']['scale'],{'numerator':'101','denominator':'100'})
        self.assertEqual(r['checks'][0]['comparison']['signed_mapped_minus_reference_residual_seconds'],{'numerator':'-3','denominator':'200'})
        self.assertEqual(r['checks'][0]['comparison']['mapped_reference_seconds'],{'numerator':'2101','denominator':'100'})
        self.assertEqual([a['comparison']['signed_mapped_minus_reference_residual_seconds'] for a in r['anchors']],2*[{'numerator':'0','denominator':'1'}])
        self.assertEqual(r['anchors'][0]['source']['source_timestamp'],str(S))
        (DEST/'actual-preview.json').write_text(json.dumps(r,indent=2),encoding='utf-8')

    def test_unequal_rates_missing_values_and_complete_counts_remain_separate(self):
        r=clock_preview.build_preview(self.request())
        self.assertEqual([t['source_rows'] for t in r['recordings']['source']['tracks']],[3,5])
        self.assertEqual([t['source_rows'] for t in r['recordings']['reference']['tracks']],[3,9])
        self.assertEqual([r['recordings'][s]['tracks'][1]['missing_values'] for s in ('source','reference')],[1,1])
        self.assertEqual(r['uncertainty'],'unknown');self.assertEqual(r['scientific_scoring'],'not_performed')

    def test_repeated_labels_use_selected_original_row_not_first_match(self):
        r=clock_preview.build_preview(self.request())
        self.assertEqual([a['source']['source_sequence'] for a in r['anchors']],[1,3])
        self.assertEqual(r['checks'][0]['source']['source_sequence'],2)
        self.assertEqual(len({a['source']['value_json'] for a in r['anchors']}),1)

    def test_complete_recording_identity_mismatch_refused_despite_rationale(self):
        q=self.request();q['reference']=copy.deepcopy(self.mismatch)
        with self.assertRaisesRegex(ValueError,'same participant and session'):
            clock_preview.build_preview(q)

    def test_origin_mixing_refused(self):
        q=self.request();q['reference']=copy.deepcopy(self.origin)
        with self.assertRaisesRegex(ValueError,'Keep sample'):
            clock_preview.build_preview(q)

    def test_actual_clock_reversal_refused(self):
        q=self.request();q['reference']=copy.deepcopy(self.reset)
        with self.assertRaisesRegex(ValueError,'epoch'):
            clock_preview.build_preview(q)

    def test_different_valid_signal_clock_cannot_use_marker_clock(self):
        q=self.request();q['source']['tracks'][0]=copy.deepcopy(q['reference']['tracks'][0])
        with self.assertRaisesRegex(ValueError,'same explicitly preserved clock'):
            clock_preview.build_preview(q)

    def test_duplicate_or_typed_anchors_and_check_reuse_refused(self):
        for pairs in ([{'source_sequence':1,'reference_sequence':1}]*2,[{'source':'0','reference':'1'}]*2):
            q=self.request();q['anchors']=pairs
            with self.assertRaises(ValueError):clock_preview.build_preview(q)
        q=self.request();q['checks']=[q['anchors'][0]]
        with self.assertRaisesRegex(ValueError,'distinct original events'):clock_preview.build_preview(q)

    def test_reversed_defining_pairs_refused(self):
        q=self.request();q['anchors'].reverse()
        with self.assertRaisesRegex(ValueError,'positive'):clock_preview.build_preview(q)

    def test_explicit_review_and_relationship_required(self):
        for value in ({'confirmed':False,'rationale':'reason'},{'confirmed':True,'rationale':' '},{'confirmed':1,'rationale':'reason'}):
            q=self.request();q['review']=value
            with self.assertRaisesRegex(ValueError,'Explicitly review'):clock_preview.build_preview(q)

    def test_preview_does_not_authorize_or_expose_local_paths(self):
        q=self.request();snapshot=copy.deepcopy(q);r=clock_preview.build_preview(q)
        self.assertEqual(q,snapshot)
        self.assertIn('requires_current_R',r['authorization'])
        self.assertNotIn(str(DEST),json.dumps(r))
        r['review']['rationale']='changed';self.assertEqual(q,snapshot)

    def test_budget_and_schema_fail_before_any_source_read(self):
        cases=[]
        q=self.request();q['source']['tracks'][0]['sample_count']=2000000;cases.append(q)
        q=self.request();q['source']['marker']['evidence']['bytes']=4*1024**3;cases.append(q)
        q=self.request();q['checks']*=17;cases.append(q)
        q=self.request();q['extra']=True;cases.append(q)
        for q in cases:
            with patch.object(clock_preview,'inspect_stream',side_effect=AssertionError('unexpected read')):
                with self.assertRaises(ValueError):clock_preview.build_preview(q)

    def test_corrupt_source_refused_and_originals_unchanged(self):
        q=self.request();q['source']['marker']['samples']['hash']='0'*64
        with self.assertRaisesRegex(ValueError,'SHA-256'):clock_preview.build_preview(q)
        self.assertTrue(all(interchange.digest(Path(p))==h for p,h in self.originals.items()))


suite=unittest.defaultTestLoader.loadTestsFromTestCase(PreviewTests)
result=unittest.TextTestRunner(verbosity=2).run(suite)
receipt={'schema':'brohn-external-component-evidence/1.0','passed':result.wasSuccessful(),'groups':result.testsRun,
         'failures':len(result.failures),'errors':len(result.errors),'source_sha256':interchange.digest(ROOT/'scripts/workers/clock_preview.py'),
         'test_sha256':interchange.digest(Path(__file__)),'production_files_changed':0,'services':0,'jobs':0,
         'scope':'Actual preservation importer then source-qualified exact preview component; No R authorization, publication or UI qualification by this suite.'}
(DEST/'results.json').write_text(json.dumps(receipt,indent=2),encoding='utf-8')
sys.exit(0 if result.wasSuccessful() else 1)
