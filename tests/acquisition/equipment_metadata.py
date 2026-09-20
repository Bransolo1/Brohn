"""Production metadata fingerprints from original offline LSL XML declarations."""
import argparse
import copy
import importlib.util
import json
from pathlib import Path
import unittest

ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location("setup_recorder",ROOT/"scripts/acquisition/lsl_recorder.py")
recorder=importlib.util.module_from_spec(spec);spec.loader.exec_module(recorder)

class OriginalInfo:
    def __init__(self,uid="original-outlet",origin="synthetic",channels=None,fmt=3):
        self.live_uid=uid;self.origin=origin;self.fmt=fmt;self.container_reference='original-calibration'
        self.channels=channels or [('Contact A','code','contact','alpha'),('Contact B','code','contact','beta')]
    def uid(self):return self.live_uid
    def source_id(self):return 'original-contact-equipment'
    def name(self):return 'Original contact equipment'
    def type(self):return 'EEG'
    def channel_count(self):return len(self.channels)
    def channel_format(self):return self.fmt
    def nominal_srate(self):return 100.
    def hostname(self):return 'original-offline-fixture'
    def as_xml(self):
        channels=''.join(f'<channel><label>{a}</label><unit>{b}</unit><type>{c}</type><vendor><sensor>{d}</sensor></vendor></channel>' for a,b,c,d in self.channels)
        return f'<info><uid>{self.live_uid}</uid><created_at>123.4</created_at><desc><origin>{self.origin}</origin><channels calibration="{self.container_reference}">{channels}</channels></desc></info>'

def fixtures():
    original=OriginalInfo();variants={'original':original,'restarted':OriginalInfo('restarted-outlet','pilot')}
    for name,position,value in [('renamed',0,'Renamed A'),('unit',1,'native_status'),('type',2,'validity'),('vendor',3,'changed-sensor')]:
        info=OriginalInfo();rows=[list(x) for x in info.channels];rows[0][position]=value;info.channels=rows;variants[name]=info
    reverse=OriginalInfo();reverse.channels=list(reversed(reverse.channels));variants['reordered']=reverse
    variants['native_type']=OriginalInfo(fmt=2)
    container=OriginalInfo();container.container_reference='changed-calibration';variants['container']=container
    return {key:recorder.descriptor(value) for key,value in variants.items()}

class Metadata(unittest.TestCase):
    def test_restart_and_origin_change_do_not_inherit_identity(self):
        f=fixtures();self.assertEqual(f['original']['channel_metadata_sha256'],f['restarted']['channel_metadata_sha256'])
        self.assertNotEqual(f['original']['metadata_sha256'],f['restarted']['metadata_sha256'])
        self.assertNotEqual(f['original']['uid'],f['restarted']['uid'])
    def test_every_ordered_declaration_and_vendor_extension_is_fingerprinted(self):
        f=fixtures()
        for name in ['renamed','unit','type','vendor','reordered']:
            with self.subTest(name=name):self.assertNotEqual(f['original']['channel_metadata_sha256'],f[name]['channel_metadata_sha256'])
    def test_native_type_is_retained_separately_from_channel_xml(self):
        f=fixtures();self.assertEqual(f['original']['value_type'],'string');self.assertEqual(f['native_type']['value_type'],'float64')
        self.assertEqual(f['original']['channel_metadata_sha256'],f['native_type']['channel_metadata_sha256'])
    def test_surrounding_channel_container_metadata_is_not_omitted(self):
        f=fixtures();self.assertEqual(f['original']['channels'],f['container']['channels'])
        self.assertNotEqual(f['original']['channel_metadata_sha256'],f['container']['channel_metadata_sha256'])
    def test_original_exact_labels_units_and_order_survive(self):
        f=fixtures()['original'];self.assertEqual([c['label'] for c in f['channels']],['Contact A','Contact B'])
        self.assertEqual([c['index'] for c in f['channels']],[0,1]);self.assertEqual(f['channels'][0]['unit'],'code')

if __name__=='__main__':
    import sys
    if '--fixture' in sys.argv:
        p=argparse.ArgumentParser();p.add_argument('--fixture',type=Path,required=True);a=p.parse_args()
        a.fixture.write_text(json.dumps(fixtures()),encoding='utf-8')
    else:unittest.main()
