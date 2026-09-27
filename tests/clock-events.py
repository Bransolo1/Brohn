from pathlib import Path
import copy
import json
import sys
import unittest
from unittest.mock import patch

from clock_test_support import ROOT,fresh_output,make_preview
HERE=Path(__file__).resolve().parent
import clock_events
from stream_extract import digest

DEST=fresh_output();DEST.mkdir(parents=True,exist_ok=False)
INPUT=make_preview(DEST/'synthetic-input')
BASE=INPUT['source']['marker']


class EventTests(unittest.TestCase):
    serial=0

    def changed(self, edit):
        t=copy.deepcopy(BASE);rows=[json.loads(s) for s in Path(t['samples']['path']).read_text().splitlines()]
        edit(rows);type(self).serial+=1;p=DEST/f'adversarial-{self.serial}.jsonl'
        p.write_text(''.join(json.dumps(r)+'\n' for r in rows),encoding='utf-8')
        t['samples']={'path':str(p),'hash':digest(p),'bytes':p.stat().st_size};return t

    def test_repeated_labels_preserve_distinct_rows_across_pages(self):
        first=clock_events.event_page(BASE,limit=2);last=clock_events.event_page(BASE,offset=first['next_offset'],limit=2)
        self.assertEqual([r['source_sequence'] for r in first['events']+last['events']],[1,2,3])
        self.assertEqual(first['matched_rows'],3);self.assertFalse(last['has_next'])
        self.assertEqual(len({r['source_timestamp'] for r in first['events']+last['events']}),3)
        self.assertEqual(first['selectable_source_rows'],3)

    def test_query_searches_complete_values_without_matching_events(self):
        self.assertEqual(clock_events.event_page(BASE,'REPEATED')['matched_rows'],3)
        self.assertEqual(clock_events.event_page(BASE,'absent')['events'],[])
        self.assertEqual(clock_events.event_page(BASE)['event_equivalence'],'not_inferred')

    def test_empty_end_page_retains_complete_counts(self):
        r=clock_events.event_page(BASE,offset=40)
        self.assertEqual(r['source_rows'],3);self.assertEqual(r['matched_rows'],3)
        self.assertEqual(r['events'],[]);self.assertIsNone(r['next_offset'])

    def test_missing_and_reconstructed_rows_remain_visible_but_unselectable(self):
        t=self.changed(lambda r:r[1].update(reconstructed_timestamp=True))
        r=clock_events.event_page(t);self.assertEqual(r['selectable_source_rows'],2)
        self.assertFalse(r['events'][1]['selectable']);self.assertIn('no_original_observed_timestamp',r['events'][1]['unavailable_reasons'])
        t=self.changed(lambda r:r[1]['values'].update(event=None))
        r=clock_events.event_page(t);self.assertEqual(r['selectable_source_rows'],2)
        self.assertEqual(r['events'][1]['value_json'],'null');self.assertFalse(r['events'][1]['selectable'])

    def test_oversized_value_is_not_a_truncated_selectable_anchor(self):
        t=self.changed(lambda r:r[1]['values'].update(event='A'*4096))
        r=clock_events.event_page(t,'AAA')
        self.assertEqual(r['matched_rows'],1);self.assertIsNone(r['events'][0]['value_json'])
        self.assertEqual(r['events'][0]['value_bytes'],4098);self.assertFalse(r['events'][0]['selectable'])

    def test_json_number_lexeme_is_preserved(self):
        t=self.changed(lambda r:r[1]['values'].update(event='REPLACE-NUMBER'))
        p=Path(t['samples']['path']);token='9007199254741013.000000000001'
        p.write_text(p.read_text().replace('"REPLACE-NUMBER"',token),encoding='utf-8')
        t['samples'].update(hash=digest(p),bytes=p.stat().st_size)
        r=clock_events.event_page(t,token)
        self.assertEqual(r['events'][0]['value_json'],token)

    def test_invalid_page_and_signal_route_refused_before_read(self):
        for kwargs in ({'offset':True},{'limit':101},{'query':'x'*241},{'offset':-1}):
            with patch.object(clock_events,'inspect_stream',side_effect=AssertionError('unexpected read')):
                with self.assertRaises(ValueError):clock_events.event_page(BASE,**kwargs)
        with self.assertRaises(ValueError):clock_events.event_page(INPUT['source']['tracks'][0])

    def test_source_and_identity_corruption_beyond_page_refused(self):
        t=self.changed(lambda r:r[-1]['identity'].update(session_id='OTHER'))
        with self.assertRaisesRegex(ValueError,'participant/session'):clock_events.event_page(t,limit=1)
        t=copy.deepcopy(BASE);t['samples']['hash']='0'*64
        with self.assertRaisesRegex(ValueError,'SHA-256'):clock_events.event_page(t)

    def test_original_bytes_unchanged_and_paths_not_returned(self):
        r=clock_events.event_page(BASE)
        self.assertNotIn(BASE['samples']['path'],json.dumps(r))
        for key in ('samples','evidence'):
            self.assertEqual(digest(Path(BASE[key]['path'])),BASE[key]['hash'])

    def test_output_bound_refuses_instead_of_truncating_evidence(self):
        with patch.object(clock_events,'MAX_OUTPUT_BYTES',100):
            with self.assertRaisesRegex(ValueError,'fewer rows'):clock_events.event_page(BASE)


result=unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(EventTests))
(DEST/'results.json').write_text(json.dumps({'passed':result.wasSuccessful(),'groups':result.testsRun,'failures':len(result.failures),'errors':len(result.errors),
    'source_sha256':digest(ROOT/'scripts/workers/clock_events.py'),'test_sha256':digest(Path(__file__)),'new_jobs':0,'production_files_changed':0,
    'scope':'Read-only actual retained importer artifacts plus labelled adversarial copies; no R authority or browser event picker.'},indent=2),encoding='utf-8')
sys.exit(0 if result.wasSuccessful() else 1)
