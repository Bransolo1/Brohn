"""Complete saved facial-output index and exact-range views. No model inference.

Numeric JSON tokens are kept as text for numerical alternatives and CSV. Face
ordinals are local to a frame and are never joined as person identities.
"""
from __future__ import annotations
import argparse
from collections import Counter
from contextlib import contextmanager
import csv
from decimal import Decimal
from fractions import Fraction
import hashlib
import io
import json
import math
import os
from pathlib import Path
import re
import sqlite3
import sys
import tempfile
import vision_explorer as common

SCHEMA='brohn-facial-review-index/1.0'
RECIPE='saved-native-facial-review/1.0'
AUS=[f'AU{x:02d}' for x in (1,2,4,5,6,7,9,10,11,12,14,15,17,20,23,24,25,26,28,43)]
CATEGORIES=['anger','disgust','fear','happiness','sadness','surprise','neutral']
METRICS=AUS+CATEGORIES
STATES=['no_face','single_face','multiple_faces','invalid_native_output']
BOX=['FaceRectX','FaceRectY','FaceRectWidth','FaceRectHeight','FaceScore']
CSV_FIELDS=['frame_index','source_pts','source_time_base','source_pts_s','relative_time_numerator','relative_time_denominator','time_s','state','face_count','eligible','face_ordinal','face_valid']+BOX+METRICS
MAX_ARTIFACT=64*1024**2
MAX_INDEX=64*1024**2
require=common.require
integer=common.integer
loads=common.loads
encoded=common.encoded
digest=common.digest
fields=common.fields
Number=common.Number

def fraction(x):
    fields(x,('numerator','denominator'))
    require(type(x['numerator']) is str and re.fullmatch(r'-?(0|[1-9][0-9]*)',x['numerator']) and len(x['numerator'])<=40,'Invalid saved rational numerator.')
    require(type(x['denominator']) is str and re.fullmatch(r'[1-9][0-9]*',x['denominator']) and len(x['denominator'])<=40,'Invalid saved rational denominator.')
    f=Fraction(int(x['numerator']),int(x['denominator']))
    require(str(f.numerator)==x['numerator'] and str(f.denominator)==x['denominator'],'Saved rational is not canonical.')
    return f

def bound(x):
    require(type(x) is str and len(x)<=80 and re.fullmatch(r'(0|[1-9][0-9]*)(\.[0-9]+)?',x),'Use decimal recording-relative seconds without exponents.')
    f=Fraction(Decimal(x));require(0<=f<=600,'Range exceeds the saved profile.');return f

def value(x,lo=0,hi=1,nullable=False):
    if nullable and x is None:return None
    d=common.number(x);require(lo<=d<=hi,'Native saved value exceeds its declared bounds.');return str(x)

def raw_fraction(frame):return fraction(frame['relative_time'])

def checked_artifacts(request):
    artifacts=request['artifacts'];require(isinstance(artifacts,list) and len(artifacts)==2,'Both complete facial artifacts are required.')
    result={}
    for a in artifacts:
        fields(a,('kind','path','sha256','bytes'));require(a['kind'] in ('facial-observations','facial-values') and a['kind'] not in result,'Duplicate or unsupported artifact.')
        p=Path(a['path']);common.check_file(p,a,MAX_ARTIFACT);require(digest(p)==a['sha256'],'A complete facial artifact changed.');result[a['kind']]=(p,a)
    return result

def validate_rows(request):
    a=request['analysis'];require(a.get('schema')=='brohn-facial-expression-result/1.0' and a.get('kind')=='facial_expression' and a.get('status')=='completed','Choose a completed native facial report.')
    p,q=a['parameters'],a['quality'];n=integer(q['analysed_frames'],2,300);integer(q['source_frames'],2,36000)
    require(q.get('identity_tracking') is False and q.get('pts_validated') is True and p.get('identity_model') is None and p.get('gaze_model') is None and p.get('pose_model') is None,'Unsupported native identity/clock declaration.')
    require(p['orientation']=='encoded upright pixels; no autorotation, crop or resize','Unsupported saved pixel orientation.')
    tb=p['source_time_base'];require(isinstance(tb,str) and re.fullmatch(r'[1-9][0-9]*/[1-9][0-9]*',tb),'Missing original rational time base.');tb=Fraction(tb)
    origin=fraction(p['source_time_origin']);gap=Fraction(str(p['max_support_gap_s']));require(Fraction(1,1000)<=gap<=10,'Invalid saved support gap.')
    stride=integer(p['frame_stride'],1,120);lo=bound(p['start_s']);hi=bound(p['end_s']) if p.get('end_s') is not None else None
    artifacts=checked_artifacts(request);lines=artifacts['facial-observations'][0].read_bytes().splitlines();require(len(lines)==n and all(0<len(x)<=common.MAX_LINE for x in lines),'Complete frame count or line size changed.')
    rows=[];states=Counter();face_count=0;eligible=[];previous=None
    for line in lines:
        r=loads(line,tokens=True)
        fields(r,('frame_index','source_pts','source_time_base','source_pts_s','source_time','relative_time','time_s','decoded_rgb_sha256','state','face_count','eligible','faces'))
        index=integer(r['frame_index'],0,q['source_frames']-1);require(previous is None or index==integer(previous['frame_index'])+stride,'Original selected frame stride changed.')
        require(type(r['source_pts']) is str and re.fullmatch(r'-?(0|[1-9][0-9]*)',r['source_pts']) and len(r['source_pts'])<=40,'Original integer PTS is missing.')
        stamp=int(r['source_pts'])*tb;relative=stamp-origin
        require(r['source_time_base']==p['source_time_base'] and fraction(r['source_time'])==stamp and raw_fraction(r)==relative,'Saved integer/rational frame clocks disagree.')
        require(lo<=relative and (hi is None or relative<=hi) and 0<=relative<=600 and (previous is None or relative>raw_fraction(previous)),'Frame leaves original window or strictly increasing clock.')
        require(float(common.number(r['time_s']))==float(relative) and abs(Fraction(Decimal(r['source_pts_s']))-stamp)<=Fraction(1,1000000),'Supplemental frame decimals disagree with original integer PTS.')
        require(common.HASH.fullmatch(r['decoded_rgb_sha256']) and r['state'] in STATES and type(r['eligible']) is bool,'Frame pixel hash or state changed.')
        require(isinstance(r['faces'],list) and len(r['faces'])==integer(r['face_count'],0,16),'Saved face count changed.')
        for ordinal,f in enumerate(r['faces'],1):
            fields(f,('face_ordinal','valid','detection_score','bbox','au_scores','expression_scores'))
            require(integer(f['face_ordinal'],1,16)==ordinal and type(f['valid']) is bool,'Frame-local face ordinal changed.');value(f['detection_score'],Decimal('.5'),1)
            fields(f['bbox'],BOX[:4]);fields(f['au_scores'],AUS);fields(f['expression_scores'],CATEGORIES)
            for x in f['bbox'].values():value(x,-100000,100000,True)
            for x in list(f['au_scores'].values())+list(f['expression_scores'].values()):value(x,0,1,True)
            valid=all(x is not None for x in list(f['bbox'].values())+list(f['au_scores'].values())+list(f['expression_scores'].values()))
            require(f['valid']==valid,'Original native validity changed.')
            if valid:
                require(common.number(f['bbox']['FaceRectWidth'])>0 and common.number(f['bbox']['FaceRectHeight'])>0 and abs(sum(float(x) for x in f['expression_scores'].values())-1)<1e-4,'Saved native geometry/category support changed.')
        state='no_face' if not r['faces'] else 'multiple_faces' if len(r['faces'])>1 else 'single_face' if r['faces'][0]['valid'] else 'invalid_native_output'
        require(r['state']==state and r['eligible']==(state=='single_face'),'Original eligibility/state does not reconcile.')
        states[state]+=1;face_count+=len(r['faces']);rows.append(r);previous=r
        if r['eligible']:eligible.append(r)
    require(dict(states)=={k:v for k,v in q['states'].items() if v} and face_count==q['face_observations'] and len(eligible)==q['eligible_single_face_frames'],'Complete observation support differs from report.')
    # Original preview is only a cross-check; complete lines above are authority.
    require(a['preview']==[json.loads(x) for x in lines[:50]] and len(a['preview'])==min(n,50),'Saved preview differs from complete original observations.')
    csv_rows=list(csv.DictReader(io.StringIO(artifacts['facial-values'][0].read_text(encoding='utf-8'))));require(len(csv_rows)==sum(max(1,len(r['faces'])) for r in rows),'Complete CSV row count changed.')
    expected=[]
    for r in rows:
        for f in r['faces'] or [None]:
            cells={k:r[k] for k in CSV_FIELDS if k in r};cells.update(relative_time_numerator=r['relative_time']['numerator'],relative_time_denominator=r['relative_time']['denominator'])
            if f:cells.update(face_ordinal=f['face_ordinal'],face_valid=f['valid'],FaceScore=f['detection_score'],**f['bbox'],**f['au_scores'],**f['expression_scores'])
            expected.append({k:'' if cells.get(k) is None else str(cells[k]) for k in CSV_FIELDS})
    require(csv_rows==expected,'Complete CSV tokens disagree with original JSONL native values or missingness.')
    pairs=[(x,y,raw_fraction(y)-raw_fraction(x)) for x,y in zip(rows,rows[1:]) if x['eligible'] and y['eligible'] and 0<raw_fraction(y)-raw_fraction(x)<=gap]
    support=sum((dt for _,_,dt in pairs),Fraction(0));require(fraction(q['eligible_time_exact'])==support and q['eligible_time_s']==float(support),'Saved support duration changed.')
    require(q['preview_frames']==min(n,50) and q['preview_truncated']==(n>50) and q['usable']==bool(eligible) and q['interval_frames']-n==q['skipped_interval_frames'],'Saved support/preview declarations changed.')
    require([f['metric'] for f in a['features']]==METRICS,'Original metric vocabulary/order changed.')
    for f in a['features']:
        require(f['unit']=='native_model_score_0_1' and f['aggregation']=='arithmetic_mean_eligible_sampled_frames' and f['valid_frames']==len(eligible) and f['valid_time_s']==float(support) and f['scope']=='selected_recording_window','Original metric support/units changed.')
        metric=f['metric'];family='au_scores' if metric in AUS else 'expression_scores'
        mean=sum(float(r['faces'][0][family][metric]) for r in eligible)/len(eligible) if eligible else None
        weighted=sum((float(x['faces'][0][family][metric])+float(y['faces'][0][family][metric]))*.5*float(dt) for x,y,dt in pairs)/float(support) if support else None
        require(f['value']==mean and (f['time_weighted_mean'] is None if weighted is None else math.isclose(f['time_weighted_mean'],weighted,rel_tol=1e-12,abs_tol=1e-15)),'Original global summaries do not reconcile with complete saved values.')
    return rows,artifacts

def build(request):
    require(request.get('schema')=='brohn-facial-review-request/1.0','Unsupported facial review request.')
    rows,artifacts=validate_rows(request);binding=request['binding_json'];require(common.sha(binding.encode())==request['binding_sha256'],'Exact binding digest changed.')
    binding_value=loads(binding);a=request['analysis'];require(binding_value['original_source']['hash']==a['source']['sha256'] and binding_value['original_source']['size']==a['source']['bytes'],'Original source binding changed.')
    path=Path(request['index_path']);require(not path.exists() and path.parent.is_dir(),'Choose a fresh owned facial index.')
    manifest={'schema':SCHEMA,'recipe':RECIPE,'binding_json':binding,'binding_sha256':request['binding_sha256'],'parameters':a['parameters'],'engine':a['engine'],'quality':a['quality'],'features':a['features'],
              'artifacts':[{k:v for k,v in artifacts[name][1].items() if k!='path'} for name in ('facial-observations','facial-values')],
              'frames':len(rows),'face_rows':sum(len(r['faces']) for r in rows),'metrics':METRICS,'first_time':str(rows[0]['time_s']),'last_time':str(rows[-1]['time_s']),
              'interpretation':'Saved native outputs only; frame-local ordinals, no identity tracking, no selected-window rescoring.'}
    text=encoded(manifest);con=sqlite3.connect(path)
    try:
        con.executescript('PRAGMA journal_mode=DELETE; CREATE TABLE metadata(key TEXT PRIMARY KEY,value TEXT NOT NULL); CREATE TABLE frames(frame_index INTEGER PRIMARY KEY,time_s REAL NOT NULL,json TEXT NOT NULL,original_json TEXT NOT NULL);')
        con.execute('INSERT INTO metadata VALUES(?,?)',('manifest',text.decode()))
        for r,raw in zip(rows,artifacts['facial-observations'][0].read_bytes().splitlines()):con.execute('INSERT INTO frames VALUES(?,?,?,?)',(int(r['frame_index']),float(r['time_s']),encoded(r).decode(),raw.decode()))
        con.commit();require(con.execute('PRAGMA integrity_check').fetchone()==('ok',),'Derived index is inconsistent.')
    finally:con.close()
    require(path.stat().st_size<=MAX_INDEX,'Derived index exceeds its resource bound.')
    return {'schema':'brohn-facial-review-result/1.0','status':'complete','manifest':manifest,'index':{'path':str(path.resolve()),**common.descriptor(path),'schema':SCHEMA,'manifest_sha256':common.sha(text)}}

@contextmanager
def opened(request):
    path=Path(request['index_path']);ref=request['index'];common.check_file(path,ref,MAX_INDEX)
    if request.get('guarded_verified') is not True:require(digest(path)==ref['sha256'],'Saved facial index changed.')
    con=sqlite3.connect(path.resolve().as_uri()+'?mode=ro&immutable=1',uri=True)
    try:
        con.execute('PRAGMA trusted_schema=OFF');row=con.execute("SELECT value FROM metadata WHERE key='manifest'").fetchone();require(row is not None,'Missing index manifest.')
        m=loads(row[0]);require(m['schema']==SCHEMA and m['binding_sha256']==request['binding_sha256'] and common.sha(row[0].encode())==ref['manifest_sha256'],'Saved facial manifest identity changed.')
        require(con.execute('SELECT count(*) FROM frames').fetchone()[0]==m['frames']<=300,'Complete facial index count changed.')
        yield con,m
    finally:con.close()

def selection(request,con):
    metric=request.get('metric');require(metric in METRICS,'Choose a saved AU or native category.')
    rg=request.get('range');require(rg is None or isinstance(rg,list) and len(rg)==2,'Choose an exact closed recording-relative range.')
    lo,hi=(bound(rg[0]),bound(rg[1])) if rg else (Fraction(0),Fraction(600));require(lo<=hi,'Range end precedes its start.')
    # At most300 complete frame records; exact rational comparison, never rounded SQL filtering.
    rows=[loads(x[0]) for x in con.execute('SELECT json FROM frames ORDER BY frame_index')]
    return [r for r in rows if lo<=raw_fraction(r)<=hi],metric

def read(request):
    op=request['operation']
    with opened(request) as (con,m):
        if op=='catalog':return {'status':'complete','manifest':m}
        if op=='detail':
            index=integer(request['frame_index'],0,35999);row=con.execute('SELECT json,original_json FROM frames WHERE frame_index=?',(index,)).fetchone();require(row is not None,'Choose an actual analysed saved frame, not a skipped source frame.')
            return {'status':'complete','observation':loads(row[0]),'original_json':row[1],'parameters':m['parameters'],'engine':m['engine']}
        rows,metric=selection(request,con);family='au_scores' if metric in AUS else 'expression_scores';gap=Fraction(str(m['parameters']['max_support_gap_s']))
        points=[]
        for i,r in enumerate(rows):
            prior=rows[i-1] if i else None;reason='first_in_window' if prior is None else 'missing_or_multiple_native_support' if not(prior['eligible'] and r['eligible']) else 'saved_support_gap' if raw_fraction(r)-raw_fraction(prior)>gap else 'adjacent_supported_sample'
            points.append({k:r[k] for k in ('frame_index','source_pts','source_time_base','source_pts_s','relative_time','time_s','state','face_count','eligible')}|{'value':r['faces'][0][family][metric] if r['eligible'] else None,'connection':reason})
        if op=='plot':return common.bound_response({'status':'complete','metric':metric,'range':request.get('range'),'points':points,'frames':len(rows),'saved_global_feature':next(f for f in m['features'] if f['metric']==metric)})
        if op=='page':
            offset=integer(request.get('offset',0),0,300);limit=integer(request.get('limit',25),1,100)
            return {'status':'complete','metric':metric,'rows':points[offset:offset+limit],'total':len(points),'offset':offset,'limit':limit}
        if op=='export_csv':
            path=Path(request['output_path']);require(not path.exists() and path.parent.is_dir(),'Choose a fresh owned exact CSV file.')
            headers=['frame_index','source_pts','source_time_base','source_pts_s','relative_time_numerator','relative_time_denominator','time_s','state','eligible','face_count','face_ordinal','face_valid','metric','native_value']
            count=0
            with path.open('x',encoding='utf-8',newline='') as stream:
                writer=csv.DictWriter(stream,fieldnames=headers);writer.writeheader()
                for r in rows:
                    for f in r['faces'] or [None]:
                        values={k:r[k] for k in headers if k in r};values.update(relative_time_numerator=r['relative_time']['numerator'],relative_time_denominator=r['relative_time']['denominator'],metric=metric)
                        if f:values.update(face_ordinal=f['face_ordinal'],face_valid=f['valid'],native_value=f[family][metric])
                        writer.writerow(values);count+=1
            return {'schema':'brohn-facial-numeric-export/1.0','status':'complete','binding_sha256':request['binding_sha256'],'path':str(path.resolve()),**common.descriptor(path),'rows':count,'frames':len(rows),'metric':metric,'range':request.get('range'),'complete':True,'number_encoding':'original numeric JSON tokens','missing_value':'empty cell; no-face row retained'}
        raise common.InputError('Unsupported facial read operation.')


def extract(request):
    import vision
    import media_pixels
    require(request.get('schema')=='brohn-facial-frame-request/1.0','Unsupported facial frame request.')
    source=Path(request['source_path']);reference=request['source'];common.check_file(source,reference,512*1024**2)
    require(digest(source)==reference['sha256'],'Original video bytes changed.')
    with opened(request) as (con,m):
        binding=loads(m['binding_json']);require(binding['original_source']=={'hash':reference['sha256'],'size':reference['bytes']},'Saved index belongs to another source.')
        index=integer(request['frame_index'],0,35999);row=con.execute('SELECT json FROM frames WHERE frame_index=?',(index,)).fetchone();require(row is not None,'Choose an actual analysed saved frame.')
        frame=loads(row[0]);saved_rows=[loads(x[0]) for x in con.execute('SELECT json FROM frames ORDER BY frame_index')]
    p,e=m['parameters'],m['engine'];runtime_path=Path(__file__).resolve().parents[1]/'readiness/facial-runtime.json'
    require(digest(runtime_path)==e['runtime_manifest_sha256'],'This saved frame requires its original pinned decoder manifest.')
    require(os.environ.get('BROHN_FACIAL_FFMPEG_DIR'),'Configure the original pinned facial FFmpeg directory to inspect recorded pixels; model packages are not required.')
    directory=Path(os.environ['BROHN_FACIAL_FFMPEG_DIR']).resolve();runtime=loads(runtime_path.read_bytes())
    def check_runtime():
        for ref in runtime['files']:
            path=(directory/ref['relative_path']).resolve();require(path.is_relative_to(directory),'Decoder asset leaves configured directory.')
            common.check_file(path,ref,512*1024**2);require(digest(path)==ref['sha256'],'Original pinned decoder asset changed.')
    check_runtime();old_path=os.environ.get('PATH','');os.environ['PATH']=str(directory)+os.pathsep+old_path
    try:
        info=vision.inspect_video(source)
        # inspect_video resolves v:0; retrieve its absolute stream index for exact -map0:N.
        overview=vision.probe_json([str(directory/'ffprobe.exe'),'-v','error','-protocol_whitelist','file,pipe','-select_streams','v:0','-show_entries','stream=index','-of','json',str(source)])
        stream_index=integer(overview['streams'][0]['index'],0,63)
    finally:os.environ['PATH']=old_path
    require(info['frame_count']==m['quality']['source_frames'] and info['width']==p['width'] and info['height']==p['height'] and info['time_base']==p['source_time_base'],'Original full frame ledger/dimensions/time base changed.')
    require(info['ffmpeg_version']==e['ffmpeg'] and info['ffprobe_version']==e['ffprobe'],'Original decoder versions changed.')
    tb=Fraction(p['source_time_base']);origin=fraction(p['source_time_origin'])
    require(int(info['frames'][0]['pts'])*tb==origin and info['frames'][0]['pts_time']==p['source_pts_origin_s'],'Original recording origin changed.')
    for r in saved_rows:
        actual=info['frames'][int(r['frame_index'])]
        require(str(actual['pts'])==r['source_pts'] and actual['pts_time']==r['source_pts_s'] and int(actual['pts'])*tb-origin==raw_fraction(r),'Complete saved observation PTS does not match its exact original decoded frame.')
    image=media_pixels.extract_frame(source,reference['sha256'],reference['bytes'],stream_index,p['width'],p['height'],index,directory/'ffmpeg.exe',request['output_directory'],frame['decoded_rgb_sha256'])
    check_runtime()
    return {'schema':'brohn-facial-recorded-frame/1.0','status':'complete','binding_sha256':request['binding_sha256'],'index_sha256':request['index']['sha256'],'source':reference,'artifacts':m['artifacts'],'frame':frame,'image':image['image'],
      'extraction':{**{k:v for k,v in image.items() if k!='image'},'source_frames':info['frame_count'],'source_time_base':info['time_base'],'source_pts_origin_s':p['source_pts_origin_s'],'orientation':p['orientation'],'ffmpeg':e['ffmpeg'],'ffprobe':e['ffprobe'],'runtime_manifest_sha256':e['runtime_manifest_sha256']},
      'limitations':['Exact source pixels and retained native outputs only; no inference rerun or identity matching.','Native category names are model outputs, not measured inner emotions, attention or preference.']}

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--request',required=True);parser.add_argument('--output',required=True);args=parser.parse_args()
    try:
        raw=Path(args.request).read_bytes();require(len(raw)<=2*1024**2,'Request exceeds2MiB.');request=loads(raw.decode('utf-8-sig'));result=build(request) if request.get('operation')=='build' else extract(request) if request.get('operation')=='frame' else read(request);code=0
    except Exception as error:result={'schema':'brohn-facial-review-result/1.0','status':'error','error':{'type':type(error).__name__,'message':str(error)}};code=1
    Path(args.output).write_bytes(encoded(result)+b'\n');return code
if __name__=='__main__':sys.exit(main())
