"""Synthetic clock fixtures only; no research workspace, device or provider access."""
import copy,hashlib,json,sys
from pathlib import Path
from fractions import Fraction
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'scripts/workers'))
import interchange,clock_preview,clock_window
BASE=S=9007199254741013
def digest(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def dump(value):return json.dumps(value,sort_keys=True,ensure_ascii=True,separators=(',',':'),allow_nan=False).encode()
def fresh_output():
    if len(sys.argv)!=2:raise ValueError('Supply one new external evidence directory.')
    path=Path(sys.argv[1]).resolve()
    if path==ROOT or ROOT in path.parents:raise ValueError('Evidence must remain outside the source repository.')
    if path.exists():raise ValueError('Choose a fresh evidence directory; existing evidence is never overwritten.')
    path.parent.mkdir(parents=True,exist_ok=True)
    return path
def preview_recording(folder,name, participant='EXPLICIT-PERSON', origin='sample', reverse=False):
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
    path=folder/(name+'.json')
    path.write_text(json.dumps({'schema':'brohn-stream-bundle/1.0','origin':origin,'streams':[stream('signal',signal_times),stream('markers',marker_times)]}),encoding='utf-8')
    result=interchange.run({'schema':'brohn-interchange-request/1.0','operation':'import_multistream','format':'brohn_stream_bundle',
        'source_path':str(path),'source_hash':interchange.digest(path),'output_directory':str(folder/(name+'-import')),
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

def window_recording(folder,name,side,many=False,reset=False,participant='SYNTHETIC-PERSON',unit=None):
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
    path=folder/(name+'.json');path.write_text(json.dumps({'schema':'brohn-stream-bundle/1.0','origin':'sample','streams':[stream('markers',mt),stream('signal',st)]}),encoding='utf-8')
    imported=interchange.run({'schema':'brohn-interchange-request/1.0','operation':'import_multistream','format':'brohn_stream_bundle','source_path':str(path),'source_hash':interchange.digest(path),'output_directory':str(folder/(name+'-import')),'metadata':{'origin':'sample','origin_statement':'Original generated clock-window fixture; no hardware or real person.','clock_policy':'preserve_only'}})
    tracks=[]
    for s in imported['streams']:
        def artifact(kind):
            a=next(a for a in s['artifacts']if a['kind']==kind);return {'path':a['path'],'hash':a['sha256'],'bytes':a['bytes']}
        tracks.append({'id':name+'/'+s['id']+'/'+s['channels'][0]['id'],'source_stream_id':s['id'],'kind':s['kind'],'origin':'sample','channel':s['channels'][0],'clock':s['clock'],'preservation':s['quality'],'sample_count':s['sample_count'],'segment_count':s['segment_count'],'samples':artifact('stream_samples_jsonl'),'evidence':artifact('stream_evidence_jsonl')})
    return {'dataset':{'id':'dataset-'+name,'revision':1,'hash':interchange.digest(path)},'imported':{'id':'import-'+name,'revision':1,'hash':hashlib.sha256(json.dumps(imported,sort_keys=True).encode()).hexdigest()},'marker':tracks[0],'tracks':[tracks[1]]}

def dense_recording(folder,side):
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
    bundle=folder/(side+'.json');bundle.write_bytes(dump({'schema':'brohn-stream-bundle/1.0','origin':'sample','streams':[stream('markers',[{'timestamp':t,'values':['repeated sync']} for t in marker_times]),stream('signal',signals)]}))
    imported=interchange.run({'schema':'brohn-interchange-request/1.0','operation':'import_multistream','format':'brohn_stream_bundle','source_path':str(bundle),'source_hash':digest(bundle),'output_directory':str(folder/(side+'-import')),'metadata':{'origin':'sample','origin_statement':'Generated clock display fixture; no participant, hardware or inference.','clock_policy':'preserve_only'}})
    tracks=[]
    for s in imported['streams']:
        def artifact(kind):
            a=next(x for x in s['artifacts'] if x['kind']==kind);return{'path':a['path'],'hash':a['sha256'],'bytes':a['bytes']}
        tracks.append({'id':side+'/'+s['id']+'/'+s['channels'][0]['id'],'source_stream_id':s['id'],'kind':s['kind'],'origin':'sample','channel':s['channels'][0],'clock':s['clock'],'preservation':s['quality'],'sample_count':s['sample_count'],'segment_count':s['segment_count'],'samples':artifact('stream_samples_jsonl'),'evidence':artifact('stream_evidence_jsonl')})
    return {'dataset':{'id':side,'revision':1,'hash':digest(bundle)},'imported':{'id':side+'-import','revision':1,'hash':hashlib.sha256(dump(imported)).hexdigest()},'marker':tracks[0],'tracks':[tracks[1]]}

def make_preview(folder,optional=False):
    folder.mkdir(parents=True,exist_ok=False)
    source=window_recording(folder,'source','source') if optional else preview_recording(folder,'source')
    reference=window_recording(folder,'reference','reference') if optional else preview_recording(folder,'reference')
    return {'schema':clock_preview.SCHEMA,'source':source,'reference':reference,
            'anchors':[{'source_sequence':1,'reference_sequence':1},{'source_sequence':3,'reference_sequence':3}],
            'checks':[{'source_sequence':2,'reference_sequence':2}],
            'review':{'confirmed':True,'rationale':'Explicit generated original marker pairs; no physical synchronization or participant claim.'}}
def dense_window(folder):
    folder.mkdir(parents=True,exist_ok=False)
    request={'schema':clock_preview.SCHEMA,'source':dense_recording(folder,'source'),'reference':dense_recording(folder,'reference'),
             'anchors':[{'source_sequence':1,'reference_sequence':1},{'source_sequence':2402,'reference_sequence':2402}],
             'checks':[],'review':{'confirmed':True,'rationale':'Generated original marker pairs identify the known101/100 fixture relationship.'}}
    output=folder/'window'
    result=clock_window.run({'schema':clock_window.SCHEMA,'preview_request':request,
                            'selection':{'start_s':'0','end_s':'2.02','offset':0},'output_directory':str(output)})
    manifest={'file':'manifest.json','kind':'clock_window_manifest','sha256':digest(output/'manifest.json'),
              'bytes':(output/'manifest.json').stat().st_size,'media_type':'application/json'}
    return result,manifest,output
