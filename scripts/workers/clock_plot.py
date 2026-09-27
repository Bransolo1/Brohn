"""Bounded complete-export display preparation; no app authority or clock fitting."""
from __future__ import annotations
import csv
from decimal import Decimal,localcontext,ROUND_HALF_EVEN
from fractions import Fraction
import hashlib
import io
import json
import os
from pathlib import Path
import re

MAX_INPUT=64*1024**2
MAX_ROW=8*1024**2
MAX_OUTPUT=8*1024**2
MAX_VERTICES=32768
MAX_RUNS_BREAKS=8192
MAX_ROWS=2000000
MAX_SEGMENTS=100000
INDIVIDUAL_EVENTS=2000
PROFILE='original-observation-envelope/0.1'
VALUE_PROFILE='bounded-decimal-display/0.1'
UNSAFE_SEGMENTS={'declared_reset','timestamp_reversal','clock_id_change','duplicate_signal_timestamp','clock_offset_collection_reversal'}
NUM=re.compile(r'-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]{1,3})?\Z')
TIME=re.compile(r'[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]{1,3})?\Z')
HASH=re.compile(r'[a-f0-9]{64}\Z')
COLUMNS=['recording_side','track_id','source_stream_id','channel_id','kind','source_sequence','source_segment','source_clock_id','source_timestamp','timestamp_unit','timestamp_state','reconstructed_timestamp','value_json','value_state','unit','origin','identity_json','participant_id','session_id','condition_id','exposure_id','placement','coordinate_policy','original_seconds_numerator','original_seconds_denominator','reference_seconds_numerator','reference_seconds_denominator','reference_relative_seconds_numerator','reference_relative_seconds_denominator','preview_sha256','source_request_sha256','samples_sha256','evidence_sha256']
COUNTS=['source_rows','selected_rows','outside_anchor_span_rows','outside_window_rows','unplaced_rows','missing_source_values','missing_selected_values']

def require(ok,message):
    if not ok: raise ValueError(message)

def pairs(items):
    out={}
    for key,value in items:
        require(key not in out,'Duplicate JSON key.');out[key]=value
    return out

def decode(text):
    return json.loads(text,object_pairs_hook=pairs,parse_constant=lambda _:require(False,'Nonfinite JSON literal.'))

def encoded(value):
    return json.dumps(value,sort_keys=True,ensure_ascii=True,allow_nan=False,separators=(',',':')).encode('ascii')

def bounded_encoded(value,maximum):
    """Bound the complete serialization before allocating its joined byte string."""
    chunks=[];size=0
    for chunk in json.JSONEncoder(sort_keys=True,ensure_ascii=True,allow_nan=False,separators=(',',':')).iterencode(value):
        size+=len(chunk)
        require(size<=maximum,'Plot output exceeds its byte bound; choose a narrower window. Exact original exports remain available.')
        chunks.append(chunk.encode('ascii'))
    return b''.join(chunks)

def sha(value): return hashlib.sha256(value).hexdigest()
def pair(value): return {'numerator':str(value.numerator),'denominator':str(value.denominator)}

def integer(value,lo,hi): return type(value) is int and lo<=value<=hi

def decimal(token,value=False):
    require(type(token) is str and token.isascii() and len(token)<=(128 if value else 120)
            and (NUM if value else TIME).fullmatch(token),'Unsupported decimal display token.')
    exponent=re.split('[eE]',token)
    require(len(exponent)==1 or abs(int(exponent[1]))<=(500 if value else 220),'Decimal exponent exceeds display bound.')
    d=Decimal(token)
    require(d.is_finite() and (d.is_zero() or (-324<=d.adjusted()<=308 if value else -100<=d.adjusted()<=100)),
            'Decimal magnitude exceeds display bound.')
    return Fraction(d)

def fraction(n,d):
    require(type(n) is str and type(d) is str and len(n.lstrip('-'))<=2048 and len(d)<=2048
            and re.fullmatch(r'-?(?:0|[1-9][0-9]*)',n) and re.fullmatch(r'[1-9][0-9]*',d),'Invalid exact coordinate pair.')
    x=Fraction(int(n),int(d))
    require(str(x.numerator)==n and str(x.denominator)==d,'Coordinate is not a canonical reduced fraction.')
    return x

def saved_fraction(value):
    require(type(value) is dict and set(value)=={'numerator','denominator'},'Invalid saved exact fraction.')
    return fraction(value['numerator'],value['denominator'])

def clock_scale(clock):
    scales={'s':Fraction(1),'ms':Fraction(1,1000),'us':Fraction(1,1000000),'ns':Fraction(1,1000000000)}
    if clock['unit']=='ticks':
        scale=decimal(clock['seconds_per_tick']);require(scale>0,'Invalid original tick scale.');return scale
    require(clock['unit'] in scales and clock.get('seconds_per_tick') is None,'Invalid original clock unit or scale.')
    return scales[clock['unit']]

def display_label(value):
    with localcontext() as context:
        context.prec=34;context.rounding=ROUND_HALF_EVEN
        return str(Decimal(value.numerator)/Decimal(value.denominator))

def bounded_bytes(path,maximum):
    require(path.is_file() and path.stat().st_size<=maximum,'Artifact is missing or exceeds its byte bound.')
    with path.open('rb') as source: data=source.read(maximum+1)
    require(len(data)<=maximum,'Artifact grew beyond its byte bound.');return data

def verify(a):
    path=Path(a['path'])
    require(path.is_file() and not path.is_symlink() and path.stat().st_size==a['bytes'],'Saved artifact size/path changed.')
    total=0;h=hashlib.sha256()
    with path.open('rb') as source:
        while chunk:=source.read(min(1024**2,a['bytes']-total+1)):
            total+=len(chunk);require(total<=a['bytes'],'Saved artifact grew during verification.');h.update(chunk)
    require(total==a['bytes'] and h.hexdigest()==a['hash'],'Saved artifact SHA256 changed.')

def lines(a):
    total=0
    with Path(a['path']).open('rb') as source:
        while raw:=source.readline(MAX_ROW+1):
            total+=len(raw)
            require(len(raw)<=MAX_ROW and total<=a['bytes'],'Oversized export line or artifact growth.')
            yield raw.decode('utf-8')
    require(total==a['bytes'],'Export was truncated during reading.')

def csv_rows(a):
    old=csv.field_size_limit(MAX_ROW)
    try:
        reader=csv.DictReader(lines(a),strict=True)
        require(reader.fieldnames==COLUMNS,'Complete export columns changed.')
        for row in reader:
            require(set(row)==set(COLUMNS) and all(type(x) is str for x in row.values())
                    and sum(len(x.encode('utf-8')) for x in row.values())<=MAX_ROW,'Malformed or oversized complete CSV row.')
            yield row
    finally: csv.field_size_limit(old)

def reference(row):
    return {'recording_side':row['recording_side'],'track_id':row['track_id'],
            'source_sequence':int(row['source_sequence']),'samples_sha256':row['samples_sha256']}

def point(row,t,value,bin_id):
    return {'source_sequence':int(row['source_sequence']),'relative_fraction':pair(t),'value_json':row['value_json'],
            'source_segment':row['source_segment'],'original_row_reference':reference(row),'bin':bin_id,'_value':value}

def event(row,t):
    full=len(row['value_json'].encode('utf-8'))<=4096
    return {'original_row_reference':reference(row),'relative_fraction':pair(t),'source_segment':row['source_segment'],
            'value_json':row['value_json'] if full else None,'value_state':row['value_state'],
            'display_label_state':'original_value' if full else 'exact_export_only',
            'reason':None if full else 'Original event value exceeds4096 display bytes; use the exact selected-row export.'}

class Signal:
    def __init__(self,meta,budget):
        self.meta=meta;self.budget=budget;self.rows=0;self.numeric=0;self.missing=0;self.unsupported=0
        self.runs=[];self.breaks=[];self.run=None;self.group=None;self.last=None;self.pending=None;self.minimum=None;self.maximum=None

    def flush_group(self):
        if self.group is None:return
        g=self.group;points={p['source_sequence']:p for p in [g['first'],g['min'],g['max'],g['last']]}
        ordered=[points[k] for k in sorted(points)];self.budget['vertices']+=len(ordered)
        require(self.budget['vertices']<=MAX_VERTICES,'Display vertex bound exceeded; choose a narrower window.')
        retained={'bin':g['bin'],'observation_count':g['count'],'points':[{k:v for k,v in p.items() if k!='_value'} for p in ordered]}
        self.charge(retained)
        self.run['groups'].append({'bin':g['bin'],'observation_count':g['count'],'points':ordered});self.group=None

    def charge(self,value):
        self.budget['retained_bytes']+=len(bounded_encoded(value,MAX_OUTPUT-self.budget['retained_bytes']))

    def stop(self):
        self.flush_group();self.run=None

    def start(self,row):
        self.budget['runs_breaks']+=1
        require(self.budget['runs_breaks']<=MAX_RUNS_BREAKS,'Display continuity bound exceeded; choose a narrower window.')
        self.run={'run_id':len(self.runs)+1,'first_sequence':int(row['source_sequence']),'last_sequence':int(row['source_sequence']),
                  'source_segment':row['source_segment'],'identity_json':row['identity_json'],'represented_rows':0,'groups':[]}
        self.charge(self.run)
        self.runs.append(self.run)

    def gap(self,cause,row=None,reason=None):
        self.stop()
        if self.pending is None:self.pending={'causes':{},'value_reasons':{},'left_reference':reference(self.last) if self.last else None,
                                             'right_reference':None,'first_unavailable_reference':None,'last_unavailable_reference':None}
        self.pending['causes'][cause]=self.pending['causes'].get(cause,0)+1
        if reason:self.pending['value_reasons'][reason]=self.pending['value_reasons'].get(reason,0)+1
        if row:
            if self.pending['first_unavailable_reference'] is None:self.pending['first_unavailable_reference']=reference(row)
            self.pending['last_unavailable_reference']=reference(row)

    def finish_gap(self,row=None):
        if self.pending is None:return
        self.pending['right_reference']=reference(row) if row else None
        self.budget['runs_breaks']+=1
        require(self.budget['runs_breaks']<=MAX_RUNS_BREAKS,'Display continuity bound exceeded; choose a narrower window.')
        self.charge(self.pending)
        self.breaks.append(self.pending);self.pending=None

    def add(self,row,t,bin_id,segments):
        self.rows+=1
        if row['value_state']!='observed' or row['value_json']=='null':
            self.missing+=1;self.gap('saved_missing_value',row);return
        try:value=decimal(row['value_json'],True)
        except ValueError as error:
            self.unsupported+=1;self.gap('exact_export_only_value',row,str(error));return
        if self.last:
            if int(row['source_sequence'])!=int(self.last['source_sequence'])+1:self.gap('source_sequence_discontinuity')
            if row['source_segment']!=self.last['source_segment']:
                self.gap('original_segment_boundary')
                for reason in segments[row['source_segment']]['boundary_reasons']:self.gap('original:'+reason)
            if decode(row['identity_json'])!=decode(self.last['identity_json']):self.gap('original_identity_context_change')
        self.finish_gap(row)
        if self.run is None:self.start(row)
        p=point(row,t,value,bin_id);self.numeric+=1;self.run['represented_rows']+=1;self.run['last_sequence']=int(row['source_sequence'])
        if self.minimum is None or value<self.minimum['_value']:self.minimum=p
        if self.maximum is None or value>self.maximum['_value']:self.maximum=p
        if self.group is None or self.group['bin']!=bin_id:
            self.flush_group();self.group={'bin':bin_id,'count':1,'first':p,'min':p,'max':p,'last':p}
        else:
            self.group['count']+=1;self.group['last']=p
            if value<self.group['min']['_value']:self.group['min']=p
            if value>self.group['max']['_value']:self.group['max']=p
        self.last=row

    def result(self):
        self.stop();self.finish_gap()
        low=self.minimum['_value'] if self.minimum else None;high=self.maximum['_value'] if self.maximum else None
        points=[p for run in self.runs for group in run['groups'] for p in group['points']]
        require(sum(g['observation_count'] for r in self.runs for g in r['groups'])==self.numeric,'Signal represented counts changed.')
        for p in points:
            value=p['_value'];position=Fraction(1,2) if low==high else (value-low)/(high-low)
            p['display_y_fraction']=pair(position);p['display_y']=float(position)
        def limit(p):return None if p is None else {'value_json':p['value_json'],'value_fraction':pair(p['_value']),'original_row_reference':p['original_row_reference']}
        result={**self.meta,'display_counts':{'selected_rows':self.rows,'numeric_observed':self.numeric,'saved_missing':self.missing,
                'exact_export_only':self.unsupported,'representatives':len(points),'continuity_runs':len(self.runs)},
                'exact_y_range':{'minimum':limit(self.minimum),'maximum':limit(self.maximum),'constant':low is not None and low==high},
                'value_projection_policy':VALUE_PROFILE,'runs':self.runs,'breaks':self.breaks}
        for p in points:p.pop('_value',None)
        return result

class Markers:
    def __init__(self,meta):self.meta=meta;self.rows=0;self.missing=0;self.exact_only=0;self.bins={};self.individual=[]
    def add(self,row,t,bin_id):
        self.rows+=1;missing=row['value_state']!='observed' or row['value_json']=='null';self.missing+=int(missing);p=event(row,t)
        exact_only=p['display_label_state']=='exact_export_only';self.exact_only+=int(exact_only)
        if self.rows<=INDIVIDUAL_EVENTS:self.individual.append(p)
        else:self.individual=[]
        if bin_id not in self.bins:self.bins[bin_id]={'bin':bin_id,'count':0,'missing_values':0,'exact_export_only_values':0,'first':p,'last':p}
        b=self.bins[bin_id];b['count']+=1;b['missing_values']+=int(missing);b['exact_export_only_values']+=int(exact_only);b['last']=p
    def result(self):
        require(sum(b['count'] for b in self.bins.values())==self.rows,'Event counts changed.')
        return {**self.meta,'mode':'individual' if self.rows<=INDIVIDUAL_EVENTS else 'counted_bins','selected_rows':self.rows,
                'missing_selected_values':self.missing,'exact_export_only_values':self.exact_only,'events':self.individual if self.rows<=INDIVIDUAL_EVENTS else [],
                'bins':[] if self.rows<=INDIVIDUAL_EVENTS else list(self.bins.values())}

def prepare_plot(request):
    require(type(request) is dict and set(request)=={'schema','window_ref','map_ref','window_result','artifacts','display','output_directory'}
            and request['schema']=='brohn-clock-plot-input/0.1','Unsupported plot request.')
    require(request['display']=={'profile':PROFILE,'bins':512},'Use the declared bounded display profile.')
    for field,keys in [('window_ref',{'id','revision','hash','project_id'}),('map_ref',{'id','revision','hash'})]:
        r=request[field];require(type(r) is dict and set(r)==keys and integer(r['revision'],1,2**31-1)
                and type(r['hash']) is str and HASH.fullmatch(r['hash']) and all(type(r[k]) is str and 0<len(r[k])<=1000 for k in keys-{'hash','revision'}),'Invalid caller-bound saved reference.')
    destination=Path(request['output_directory']);require(destination.parent.is_dir() and not destination.exists(),'Use a fresh nonexisting owned output directory.')
    envelope=request['window_result'];require(type(envelope) is dict and envelope.get('schema')=='brohn-clock-window-worker-result/0.1','Use the exact saved window result.')
    result=envelope['result'];require(result['schema']=='brohn-clock-window/0.1' and len(bounded_encoded(envelope,2*1024**2))<=2*1024**2,'Unsupported or oversized saved window.')
    require(result['physical_synchronization']=='not_established' and result['uncertainty']=='unknown' and result['scientific_scoring']=='not_performed','Saved interpretation changed.')
    descriptors=[*result['artifacts'],envelope['manifest_artifact']]
    require(len(descriptors)==4 and len(request['artifacts'])==4,'Supply all four complete saved artifacts.')
    kinds=['selected_original_rows','all_source_unplaced_rows','complete_original_segments','clock_window_manifest'];artifacts={}
    for a,old in zip(request['artifacts'],descriptors):
        require(type(a) is dict and set(a)=={'kind','path','hash','bytes'} and a['kind']==old['kind'] and a['kind'] in kinds
                and a['kind'] not in artifacts and a['hash']==old['sha256'] and a['bytes']==old['bytes'] and integer(a['bytes'],1,MAX_INPUT)
                and type(a['hash']) is str and HASH.fullmatch(a['hash']) and type(a['path']) is str,'Saved artifact descriptor changed.')
        artifacts[a['kind']]=a
    require(set(artifacts)==set(kinds) and sum(a['bytes'] for a in artifacts.values())<=MAX_INPUT,'Combined export bound exceeded.')
    for a in artifacts.values():verify(a)
    require(encoded(decode(bounded_bytes(Path(artifacts['clock_window_manifest']['path']),2*1024**2)))==encoded(result),'Complete manifest differs from saved result.')
    binding=result['binding'];require(set(binding)=={'preview_sha256','source_request_sha256','selection_sha256','mapping_sha256'} and all(type(v) is str and HASH.fullmatch(v) for v in binding.values()),'Invalid window binding.')
    for key,value in [('preview_sha256',result['preview']),('source_request_sha256',result['source_request']),('selection_sha256',result['selection']),('mapping_sha256',result['preview']['mapping'])]:require(sha(encoded(value))==binding[key],'Window binding changed.')
    require(all(a['binding']==binding for a in result['artifacts']),'Export binding changed.')
    start,end=decimal(result['selection']['start_s']),decimal(result['selection']['end_s']);require(0<=start<end<=86400,'Invalid exact display window.')
    mapping=result['preview']['mapping'];scale=saved_fraction(mapping['scale']);offset=saved_fraction(mapping['offset_seconds'])
    source_start,source_end=[saved_fraction(a['source_seconds']) for a in mapping['anchors']]
    reference_start,reference_end=[saved_fraction(a['reference_seconds']) for a in mapping['anchors']]
    require(scale>0 and source_start<source_end and reference_start<reference_end
            and source_start*scale+offset==reference_start and source_end*scale+offset==reference_end
            and end<=reference_end-reference_start,'Saved mapping support or arithmetic changed.')
    original=[(side,t) for side in ('source','reference') for t in [result['source_request'][side]['marker'],*result['source_request'][side]['tracks']]]
    require(4<=len(original)<=6 and len(result['tracks'])==len(original),'Invalid original track inventory.')
    tracks={};order={};totals={k:0 for k in COUNTS}
    for index,((side,t),saved) in enumerate(zip(original,result['tracks'])):
        key=(side,t['id']);require(key not in tracks and saved['recording_side']==side and saved['track_id']==t['id'],'Original track order changed.')
        require(all(integer(saved[k],0,MAX_ROWS) for k in COUNTS) and saved['source_rows']==sum(saved[k] for k in ['selected_rows','outside_anchor_span_rows','outside_window_rows','unplaced_rows']),'Original track counts do not reconcile.')
        for k in COUNTS:totals[k]+=saved[k]
        require(saved['source_stream_id']==t['source_stream_id'] and saved['channel']==t['channel'] and saved['clock']==t['clock']
                and saved['samples']=={k:t['samples'][k] for k in ('hash','bytes')} and saved['evidence']=={k:t['evidence'][k] for k in ('hash','bytes')},'Original track metadata changed.')
        require(integer(t['sample_count'],1,MAX_ROWS) and t['sample_count']==saved['source_rows'],'Original sample inventory changed.')
        tracks[key]={'track':t,'saved':saved,'segments':{},'selected':0,'unplaced':0,'missing':0,'selected_segments':{},
                     'seen_sequences':bytearray((t['sample_count']+7)//8),'segment_end':0,'clock_scale':clock_scale(t['clock'])};order[key]=index
    require(totals==result['counts'] and totals['source_rows']<=MAX_ROWS,'Complete source totals changed.')
    segment_count=0
    for line in lines(artifacts['complete_original_segments']):
        record=decode(line);key=(record['recording_side'],record['track_id']);require(key in tracks and all(record[k]==binding[k] for k in binding),'Segment binding changed.')
        x=tracks[key];s=decode(record['segment_json']);sid=record['source_segment'];require(sid not in x['segments'] and s['id']==sid and s['type']=='source_segment'
            and s['clock_id']==x['track']['clock']['id'] and record['evidence_sha256']==x['track']['evidence']['hash'] and type(s['boundary_reasons']) is list,'Original segment changed.')
        require(integer(s['first_sequence'],1,MAX_ROWS) and integer(s['last_sequence'],s['first_sequence'],x['track']['sample_count'])
                and s['first_sequence']==x['segment_end']+1 and s['sample_count']==s['last_sequence']-s['first_sequence']+1
                and integer(record['selected_rows'],0,s['sample_count']) and all(type(reason) is str for reason in s['boundary_reasons']),
                'Original segment range, order or counts changed.')
        require(not UNSAFE_SEGMENTS.intersection(s['boundary_reasons']),'Unsupported original clock reset or ambiguous epoch.')
        x['segment_end']=s['last_sequence']
        x['segments'][sid]={**s,'expected_selected':record['selected_rows']};segment_count+=1;require(segment_count<=MAX_SEGMENTS*len(tracks),'Too many complete segments.')
    require(segment_count==next(a['rows'] for a in descriptors if a['kind']=='complete_original_segments'),'Complete segment export count changed.')
    budget={'vertices':0,'runs_breaks':0,'retained_bytes':0};lanes={}
    for key,x in tracks.items():
        t=x['track'];require(len(x['segments'])==x['saved']['segment_count'] and x['segment_end']==t['sample_count'],'Original segment inventory changed.')
        meta={'recording_side':key[0],'track_id':key[1],'source_stream_id':t['source_stream_id'],'channel':t['channel'],'unit':t['channel'].get('unit'),
              'origin':t['origin'],'clock':t['clock'],'saved_counts':{k:x['saved'][k] for k in COUNTS}}
        require(t['kind'] in ('signal','markers'),'Unsupported track kind.')
        lanes[key]=Signal(meta,budget) if t['kind']=='signal' else Markers(meta)
    def validate_row(row,placed):
        key=(row['recording_side'],row['track_id']);require(key in tracks,'Unselected exported track.');x=tracks[key];t=x['track']
        require(re.fullmatch(r'[1-9][0-9]*',row['source_sequence']) and len(row['source_sequence'])<=7,'Invalid original row number.');seq=int(row['source_sequence'])
        require(seq<=t['sample_count'] and row['source_segment'] in x['segments'],'Original row support changed.');s=x['segments'][row['source_segment']]
        slot,bit=divmod(seq-1,8);require(not x['seen_sequences'][slot]&(1<<bit),'Original row appears in both selected and unplaced exports.')
        x['seen_sequences'][slot]|=1<<bit
        require(s['first_sequence']<=seq<=s['last_sequence'],'Row escaped its original segment.')
        expected={'source_stream_id':t['source_stream_id'],'channel_id':t['channel']['id'],'kind':t['kind'],'source_clock_id':t['clock']['id'],
                  'timestamp_unit':t['clock']['unit'],'unit':t['channel'].get('unit') or '', 'origin':t['origin'],'samples_sha256':t['samples']['hash'],
                  'evidence_sha256':t['evidence']['hash'],'preview_sha256':binding['preview_sha256'],'source_request_sha256':binding['source_request_sha256']}
        require(all(row[k]==v for k,v in expected.items()),'Exported original row metadata changed.')
        identity=decode(row['identity_json']);require(identity==s['identity'] and all(identity.get(k,'')==row[k] for k in ('participant_id','session_id','condition_id','exposure_id'))
                and all(identity[k]==result['preview']['identity'][k] for k in ('participant_id','session_id')),'Exported original identity changed.')
        decode(row['value_json'])
        require(row['reconstructed_timestamp'] in ('True','False'),'Invalid timestamp provenance flag.')
        can_place=row['timestamp_state']=='observed' and row['source_timestamp']!='' and row['reconstructed_timestamp']=='False'
        require(can_place==placed and row['placement']==('selected_window' if placed else 'unplaced'),'Export placement changed.')
        if placed:
            coordinates={prefix:fraction(row[prefix+'_numerator'],row[prefix+'_denominator']) for prefix in ('original_seconds','reference_seconds','reference_relative_seconds')}
            original=decimal(row['source_timestamp'])*x['clock_scale'];mapped=original*scale+offset if key[0]=='source' else original
            lo,hi=(source_start,source_end) if key[0]=='source' else (reference_start,reference_end)
            t=coordinates['reference_relative_seconds']
            require(coordinates=={'original_seconds':original,'reference_seconds':mapped,'reference_relative_seconds':mapped-reference_start}
                    and lo<=original<=hi,'Retained original, reference or relative coordinate changed.')
            require(start<=t<end and row['coordinate_policy']==('reviewed_affine_source' if key[0]=='source' else 'original_reference_coordinate'),'Displayed coordinate escaped saved support.')
        else:
            require(row['coordinate_policy']=='no_time_assigned' and all(row[k]=='' for k in COLUMNS if k.endswith(('_numerator','_denominator'))),'Unplaced row acquired an invented time.');t=None
        return key,seq,t
    for placed,kind in [(True,'selected_original_rows'),(False,'all_source_unplaced_rows')]:
        previous=(-1,0);count=0;previous_time={}
        for row in csv_rows(artifacts[kind]):
            key,seq,t=validate_row(row,placed);position=(order[key],seq);require(position>previous,'Complete CSV original order/repetition changed.');previous=position;count+=1
            require(count<=MAX_ROWS,'Complete export row bound exceeded.');x=tracks[key]
            if placed:
                if key in previous_time:require(t>=previous_time[key] and (t!=previous_time[key] or row['kind']=='markers'),'Original time ordering changed.')
                previous_time[key]=t;x['selected']+=1;x['missing']+=int(row['value_state']!='observed' or row['value_json']=='null')
                sid=row['source_segment'];x['selected_segments'][sid]=x['selected_segments'].get(sid,0)+1
                bin_id=((t-start)*512//(end-start));require(0<=bin_id<512,'Exact bin escaped display span.')
                if row['kind']=='signal':lanes[key].add(row,t,bin_id,x['segments'])
                else:lanes[key].add(row,t,bin_id)
            else:x['unplaced']+=1
        require(count==next(a['rows'] for a in descriptors if a['kind']==kind),'Complete export count was truncated or changed.')
    for x in tracks.values():
        require(x['selected']==x['saved']['selected_rows'] and x['unplaced']==x['saved']['unplaced_rows'] and x['missing']==x['saved']['missing_selected_values'],'Complete per-track coverage changed.')
        require(all(x['selected_segments'].get(k,0)==s['expected_selected'] for k,s in x['segments'].items()),'Complete segment selection counts changed.')
    signals=[lane.result() for lane in lanes.values() if isinstance(lane,Signal)];events=[lane.result() for lane in lanes.values() if isinstance(lane,Markers)]
    def project_x(item):item['display_x']=float((saved_fraction(item['relative_fraction'])-start)/(end-start))
    for signal in signals:
        for run in signal['runs']:
            for group in run['groups']:
                for item in group['points']:project_x(item)
    for lane in events:
        for item in lane['events']:project_x(item)
        for group in lane['bins']:
            project_x(group['first']);project_x(group['last'])
    ticks=[{'position':i/4,'relative_seconds':pair(start+(end-start)*i/4),'offset_seconds':pair((end-start)*i/4),
            'display_offset_label':display_label((end-start)*i/4)} for i in range(5)]
    require(len({tick['display_offset_label'] for tick in ticks})==5,'Display axis labels are not distinct.')
    numeric=sum(s['display_counts']['numeric_observed'] for s in signals)
    output={'schema':'brohn-clock-plot/0.1','status':'empty_window' if not totals['selected_rows'] else 'available' if numeric else 'no_supported_numeric_signal',
        'window_ref':request['window_ref'],'map_ref':request['map_ref'],'binding':binding,
        'artifact_hashes':{k:{'hash':a['hash'],'bytes':a['bytes']} for k,a in artifacts.items()},
        'implementation':{'clock_plot.py':sha(Path(__file__).read_bytes())},
        'coverage':{'complete_selected_rows_read':totals['selected_rows'],'complete_unplaced_rows_read':totals['unplaced_rows'],'complete_segment_records_read':segment_count,
                    'bins':512,'reduction_profile':PROFILE,'source_observation_count':totals['source_rows'],'numeric_observations_represented':numeric,'signal_representatives':budget['vertices']},
        'axis':{'start_relative_seconds':pair(start),'end_relative_seconds':pair(end),'end_exclusive':True,
                'reference_anchor_seconds':result['preview']['mapping']['anchors'][0]['reference_seconds'],
                'display_base_relative_seconds':pair(start),'display_base_exact_decimal':result['selection']['start_s'],'ticks':ticks,
                'tick_labels':'seconds after the displayed relative base; 34 significant digit approximation',
                'positions':'display_only_unit_interval; exact coordinate fractions remain authoritative'},
        'lanes':signals,'events':events,'mapping_evidence':{'anchors':result['preview']['anchors'],'checks':result['preview']['checks']},
        'unplaced_scope':result['unplaced_scope'],'physical_synchronization':'not_established','uncertainty':'unknown','scientific_scoring':'not_performed',
        'authorization':'caller_must_enforce_current_saved_window_and_source_authority','scope':'complete_saved_export_display_component_only'}
    raw=bounded_encoded(output,MAX_OUTPUT-1)+b'\n'
    for a in artifacts.values():verify(a)
    destination.mkdir();partial=destination/'plot.json.partial'
    with partial.open('xb') as target:target.write(raw)
    for a in artifacts.values():verify(a)
    final=destination/'plot.json';os.link(partial,final);partial.unlink()
    return output
