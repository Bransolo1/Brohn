"""Independent original pixel, PCM, full-ledger and immutable report oracle.

Never imports the product reader, mapper, scorer or source-extraction code.
"""
import csv, hashlib, json, struct, sys, wave
from fractions import Fraction
from pathlib import Path
from PIL import Image
folder=Path(sys.argv[1]).resolve();output=Path(sys.argv[2]).resolve();config=json.loads((folder/'fixture.json').read_text());media=Path(config['media']);partial=len(sys.argv)>3 and sys.argv[3]=='--regular-only'
checks=[]
def check(name,ok):
    assert ok,name
    checks.append(name);print('PASS',name)
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def rows(name):
    with (output/name).open(newline='',encoding='utf-8') as f:return list(csv.DictReader(f))
with wave.open(str(media/'original.wav'),'rb') as f:pcm=struct.unpack('<32000h',f.readframes(32000))
for kind in (('regular',) if partial else ('regular','gap')):
    body=json.loads((output/f'{kind}-mapping.json').read_text());audio=json.loads((output/f'{kind}-original-audio-review.json').read_text());report=json.loads((output/f'{kind}-original-report.json').read_text())
    check(f'{kind}: parent, extraction, report and saved window identities retained',body['request']['source']['hash']==sha(media/f'{kind}.mkv') and body['request']['audio_review']['id']==audio['id'] and body['request']['report']['id']==report['id'] and audio['request']['extraction_lineage']==report['provenance']['derived_audio_lineage']['binding'])
    samples=rows(f'{kind}-samples.csv')
    check(f'{kind}: all32000originalPCM samples exported without preview reduction or resampling',len(samples)==32000 and all(int(r['source_sample_index'])==i and int(r['channel_index'])==0 and abs(float(r['time_s'])-i/8000)<1e-15 and float(r['amplitude_fs'])==pcm[i]/32768 for i,r in enumerate(samples)))
    ledger=rows(f'{kind}-video-frames.csv')
    check(f'{kind}: all160originalvideo PTS and durations equal independent original specification',len(ledger)==160 and all(int(r['frame_index'])==i and int(r['pts_ticks'])==i*25+(500 if kind=='gap' and i>=80 else 0) and Fraction(r['time_base'])==Fraction(1,1000) and int(r['duration_ticks'])==25 for i,r in enumerate(ledger)))
    check(f'{kind}: only original gap is present and never filled',sum(r['interval_relation_to_next']=='gap' for r in ledger)==(1 if kind=='gap' else 0))
    al=rows(f'{kind}-audio-frames.csv');selected=body['result']['mapping']['selected_sample'];containing=next(r for r in al if int(r['start_sample'])<=selected<int(r['end_sample_exclusive']))
    mapped=Fraction(containing['pts_ticks'])*Fraction(containing['time_base'])+Fraction(selected-int(containing['start_sample']),8000);actual=body['result']['mapping']['audio_frame']['container_time']
    check(f'{kind}: selectedtime independently equals containing-original-frame PTS plus sampleoffset',mapped==Fraction(int(actual['numerator']),int(actual['denominator'])) and sum(int(r['samples']) for r in al)==32000 and all(int(r['end_sample_exclusive'])-int(r['start_sample'])==int(r['samples']) for r in al))
    original=next(a for a in audio['csv_objects'] if a['kind']=='audio-source-samples')
    check(f'{kind}: exported selectedsamples are exactly the existing saved review object',sha(output/f'{kind}-samples.csv')==original['hash'])
    svg=(output/f'{kind}-waveform.svg').read_text();check(f'{kind}: exported SVG pins actual cursor, mapping and source',f'data-media-cursor-sample="{selected}"' in svg and body['request']['source']['hash'] in svg and 'brohn-media-mapping' in svg)
with Image.open(output/'regular-frame.png') as image:actual=image.convert('RGB').tobytes()
original=(media/'original.rgb').read_bytes()[40*64*48*3:41*64*48*3]
body=json.loads((output/'regular-mapping.json').read_text());check('PNG independently decoded pixels equal original frame40 RGB bytes',actual==original and hashlib.sha256(actual).hexdigest()==body['result']['frame_extraction']['rgb24_sha256'])
if not partial:
    gap=json.loads((output/'gap-mapping.json').read_text());check('Actual2.25s gap has no frame, no image artifact and no physical synchronization claim',gap['result']['coverage']['frame'] is None and len(gap['artifacts'])==1 and gap['result']['mapping']['physical_synchronization']=='not_established')
    check('Original mapping and frame survive process restart exactly',json.loads((output/'regular-restarted.json').read_text())==body and sha(output/'regular-frame.png')==sha(output/'regular-restarted-frame.png') and sha(output/'regular-samples.csv')==sha(output/'regular-restarted-samples.csv'))
(output/('regular-independent-oracle.json' if partial else 'independent-oracle.json')).write_text(json.dumps({'passed':True,'checks':checks,'scope':'Independent original generated source bytes, rational clocks and complete exports; no product numerical helpers imported.','partial_regular_only':partial},indent=2));print(json.dumps({'passed':True,'checks':len(checks)}))
