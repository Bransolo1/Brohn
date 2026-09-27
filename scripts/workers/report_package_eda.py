"""Bounded complete EDA stream inspection/projection, without scientific processing.

Inspection exposes only complete verified metadata. Projection changes registered
identity metadata only; every original rows record is copied byte-for-byte.
Outputs remain private until the complete result is verified by the caller.
"""
from __future__ import annotations
import argparse, copy, csv, hashlib, io, json, platform, re, sys
from pathlib import Path
import eda_display as eda
import physiology_artifacts as tables

MIB=1024**2
require=eda.require


def load(path, maximum=48*MIB):
    path=Path(path)
    require(path.is_file() and not path.is_symlink(), 'Missing ordinary projection request.')
    eda.bounded(path.stat().st_size, maximum, 'projection_request_bytes')
    return eda.strict_json(path.read_bytes())


def sha(path): return tables.digest_file(path)


def inspect_stream(item, family, source):
    eda.fields(item, ('original','original_verification','path'), 'Complete EDA stream')
    manifest=eda.verifier_manifest(item['original'],item['path'])
    eda.bounded(manifest['bytes'],64*MIB,'stream_bytes',source)
    specs=[]
    def spec(value):
        eda.check_eda_table(value,family,manifest['kind']);specs.append(value)
        eda.bounded(len(specs),256,'source_tables',source)
    rows=0
    def count_rows(table_id,offset,values):
        nonlocal rows
        rows+=len(values);eda.bounded(rows,1000000,'source_rows',source)
    verified=tables.verify_artifact(manifest,on_table=spec,on_rows=count_rows)
    receipt=item['original_verification']
    require(receipt.get('verified') is True and all(receipt.get(k)==manifest[k] for k in ('kind','sha256','bytes','schema','tables','rows','provenance_sha256')), 'Original stream receipt changed.')
    require(verified['rows']==receipt['rows'] and verified['tables']==receipt['tables'], 'Original stream coverage changed.')
    # Re-read metadata through the exact transport parser; the legacy verifier
    # may parse lexical -0 as integer zero. Rows are never rewritten here.
    exact_specs=[];header=None
    with Path(item['path']).open('rb') as f:
        for line in f:
            eda.bounded(len(line),2*MIB,'stream_line_bytes',source)
            record=eda.strict_json(line)
            if record['type']=='header':header=record
            elif record['type']=='table':
                eda.check_eda_table(record,family,manifest['kind']);exact_specs.append(record)
    require(len(exact_specs)==len(specs),'Exact metadata table count changed.')
    specs=exact_specs
    return {'original':item['original'],'original_verification':receipt,'header':header,'tables':specs}


def inspect(request):
    eda.fields(request,('schema','source_report_ref','source_family','streams'),'EDA stream inspection')
    require(request['schema']=='brohn-eda-stream-inspection-request/0.1' and request['source_family'] in ('event','continuous'), 'Unsupported inspection profile.')
    require(isinstance(request['streams'],list) and len(request['streams']) in (0,2),'Current EDA requires zero or two original streams.')
    source=request['source_report_ref']
    streams=[inspect_stream(x,request['source_family'],source) for x in request['streams']]
    require(not streams or sorted(x['original']['kind'] for x in streams)==['physiology-events','physiology-series'],'EDA stream kinds are incomplete or duplicated.')
    counts={'bytes':sum(x['original_verification']['bytes'] for x in streams),'rows':sum(x['original_verification']['rows'] for x in streams),'tables':sum(x['original_verification']['tables'] for x in streams)}
    for k,maximum in [('bytes',96*MIB),('rows',1000000),('tables',256)]:eda.bounded(counts[k],maximum,'source_'+k,source)
    result={'schema':'brohn-eda-stream-inspection/0.1','source_report_ref':source,'source_family':request['source_family'],'streams':streams,'counts':counts,
            'verified_runtime':{'Python':{'implementation':platform.python_implementation(),'version':platform.python_version()}}}
    result['value_hash']=eda.value_hash(result)
    eda.bounded(len(eda.json_bytes(result)),16*MIB,'stream_metadata_bytes',source)
    return result


def allowed_identity(path):
    # These paths are metadata identities, never scientific labels, methods,
    # support flags, numerical cells, clocks, source hashes or column names.
    group=r'(?:participant_id|session_id|exposure_id|segment_id|source_recording_id)'
    if re.fullmatch(r'table/(?:identity|support/source)/group/'+group,path): return True
    if path in ('table/identity/recording_id','table/identity/segment_id','table/support/source/recording_id','table/support/source/segment_id'):return True
    if re.fullmatch(r'header/provenance/parameters/source_mapping/events/[0-9]+/(?:recording_id|exposure_id)',path):return True
    return False


def validate_metadata(original, projected, path):
    require(type(original) is type(projected) or (type(original) in (int,float) and type(projected) in (int,float)), 'Projected metadata changed a JSON type at '+path)
    if isinstance(original,dict):
        require(original.keys()==projected.keys(),'Projected metadata changed fields at '+path)
        for k in original:validate_metadata(original[k],projected[k],path+'/'+k)
    elif isinstance(original,list):
        require(len(original)==len(projected),'Projected metadata changed array length at '+path)
        for i,(x,y) in enumerate(zip(original,projected)):validate_metadata(x,y,path+'/'+str(i))
    elif eda.value_hash(original)!=eda.value_hash(projected):
        require(allowed_identity(path) and isinstance(original,str) and original!='' and isinstance(projected,str) and 0<len(projected)<=4096,
                'A nonidentity metadata value changed at '+path)


def csv_cell(value):
    if value is None:return ''
    if isinstance(value,str):return "'"+value if re.match(r'^\s*[=+@-]',value) else value
    return eda.json_bytes(value).decode('ascii')


def descriptor(root,path,media,role):
    p=root/path
    return {'path':path,'sha256':sha(p),'bytes':p.stat().st_size,'media_type':media,'role':role}


def project(request,root):
    eda.fields(request,('schema','inspection','source_family','source_report_ref','identifier_mode','streams','projected_metadata','projection_implementation'),'EDA complete projection')
    require(request['schema']=='brohn-eda-stream-projection-request/0.1' and request['identifier_mode'] in ('package_aliases','source_identifiers'),'Unsupported EDA projection profile.')
    original=inspect({'schema':'brohn-eda-stream-inspection-request/0.1',**{k:request[k] for k in ('source_family','source_report_ref','streams')}})
    require(eda.value_hash(original)==eda.value_hash(request['inspection']),'Complete stream inspection changed before projection.')
    require(isinstance(request['projected_metadata'],list) and len(request['projected_metadata'])==len(original['streams']),'Projected metadata cardinality changed.')
    require(not root.exists(),'Choose a fresh private projection directory.');root.mkdir(parents=True)
    files=[];receipts=[];source=request['source_report_ref'];total=0
    for item,orig,projected in zip(request['streams'],original['streams'],request['projected_metadata']):
        eda.fields(projected,('header','tables'),'Projected stream metadata')
        validate_metadata(orig['header'],projected['header'],'header')
        require(len(orig['tables'])==len(projected['tables']),'Projected table count changed.')
        for x,y in zip(orig['tables'],projected['tables']):validate_metadata(x,y,'table')
        if request['identifier_mode']=='source_identifiers':
            require(eda.value_hash(projected)==eda.value_hash({k:orig[k] for k in ('header','tables')}),'Original identifiers mode changed source metadata.')
        header=copy.deepcopy(projected['header']);header['provenance_sha256']=hashlib.sha256(tables.encode(header['provenance'])).hexdigest()
        stem='series' if orig['original']['kind']=='physiology-series' else 'candidates'
        ndpath=root/(stem+'.ndjson');csvpath=root/(stem+'.csv')
        rows_hash=hashlib.sha256();seen=0;table_index=0;active=None;inventory=[];names=None
        # Binary NDJSON copied rows preserve lexical values, signed zero, integer
        # types, offsets, source indices, chunk boundaries and original ordering.
        with Path(item['path']).open('rb') as src,ndpath.open('xb') as dst,csvpath.open('x',encoding='utf-8',newline='') as cs:
            writer=csv.writer(cs,quoting=csv.QUOTE_ALL,lineterminator='\r\n')
            for line in src:
                eda.bounded(len(line),2*MIB,'stream_line_bytes',source)
                record=eda.strict_json(line);kind=record['type'];new=line
                if kind=='header':
                    if request['identifier_mode']=='package_aliases':new=tables.encode(header)
                elif kind=='table':
                    active=projected['tables'][table_index];table_index+=1
                    if request['identifier_mode']=='package_aliases':new=tables.encode(active)
                    cols=[c['name'] for c in active['columns']]
                    if names is None:names=cols;writer.writerow(['table_id','table_row_index',*cols,'record_json'])
                    else:require(cols==names,'One stream changed its registered column sequence.')
                    inventory.append({'table_id':active['table_id'],'identity':active['identity'],'columns':active['columns'],'coordinates':active['coordinates'],'support':active['support'],
                                      'expected_rows':active['expected_rows'],'rows':0,'retained_rows':0 if 'retained' in cols else None,'null_counts':{k:0 for k in cols}})
                elif kind=='rows':
                    rows_hash.update(line);inv=inventory[-1]
                    for i,row in enumerate(record['rows']):
                        writer.writerow([record['table_id'],record['offset']+i,*[csv_cell(x) for x in row],eda.json_bytes(row).decode('ascii')])
                        inv['rows']+=1;seen+=1
                        for k,v in zip(names,row):
                            if v is None:inv['null_counts'][k]+=1
                            if k=='retained' and v:inv['retained_rows']+=1
                elif kind=='complete' and request['identifier_mode']=='package_aliases':
                    record['provenance_sha256']=header['provenance_sha256'];new=tables.encode(record)
                dst.write(new)
                if kind in ('rows','table_end','complete'):
                    dst.flush();cs.flush()
                    eda.bounded(total+dst.tell()+csvpath.stat().st_size,192*MIB,'projection_bytes',source)
        manifest=eda.verifier_manifest(orig['original'],ndpath)
        manifest.update(sha256=sha(ndpath),bytes=ndpath.stat().st_size,provenance_sha256=header['provenance_sha256'])
        # Published descriptor aliases are not copied into this derived verifier
        # input: their saved identity is preserved separately in the receipt.
        manifest.pop('hash',None);manifest.pop('size',None)
        verified=tables.verify_artifact(manifest)
        verified.update({k:manifest[k] for k in ('sha256','bytes','provenance_sha256')})
        require(seen==orig['original_verification']['rows'] and table_index==orig['original_verification']['tables'],'Complete projected row/table count changed.')
        check_hash=hashlib.sha256()
        with ndpath.open('rb') as f:
            for line in f:
                if eda.strict_json(line)['type']=='rows':check_hash.update(line)
        require(check_hash.digest()==rows_hash.digest(),'Original row-record bytes changed.')
        require(sha(item['path'])==orig['original_verification']['sha256'],'Original stream changed during projection.')
        if request['identifier_mode']=='source_identifiers':require(sha(ndpath)==sha(item['path']),'Original stream bytes changed in source-identifiers mode.')
        for path,media,role in [(stem+'.ndjson','application/x-ndjson','complete_processed_eda_stream'),(stem+'.csv','text/csv; charset=utf-8','complete_processed_eda_rows')]:
            entry=descriptor(root,path,media,role);files.append(entry);total+=entry['bytes']
        receipts.append({'schema':'brohn-report-eda-stream-projection/0.1','source_report_ref':source,'source_family':request['source_family'],'identifier_mode':request['identifier_mode'],
                         'original':orig['original'],'source_verification':orig['original_verification'],'projected':files[-2],
                         'projected_verification':verified,'projection_implementation':request['projection_implementation'],
                         'unchanged_row_record_sha256':rows_hash.hexdigest(),'table_bindings':inventory,
                         'coverage':{'complete':True,'raw_series_included':False,'rows':seen,'tables':table_index}})
    result={'schema':'brohn-eda-stream-projection-result/0.1','source_report_ref':source,'source_family':request['source_family'],'identifier_mode':request['identifier_mode'],
            'files':files,'streams':receipts,'coverage':{'complete':True,'original_streams':len(receipts),'raw_series_included':False,'projected_bytes':total,**original['counts']}}
    require(eda.value_hash(inspect({'schema':'brohn-eda-stream-inspection-request/0.1',**{k:request[k] for k in ('source_family','source_report_ref','streams')}}))==eda.value_hash(original),'Final original stream metadata changed.')
    return result


def main():
    p=argparse.ArgumentParser();g=p.add_mutually_exclusive_group(required=True);g.add_argument('--inspect');g.add_argument('--request');p.add_argument('--output',required=True);p.add_argument('--artifacts');args=p.parse_args()
    out=Path(args.output);require(not out.exists(),'Output receipt already exists.')
    try:
        runtime={'Python':{'implementation':platform.python_implementation(),'version':platform.python_version()}}
        profile=load(Path(__file__).resolve().parents[1]/'readiness'/'report-package-runtime.json',8192)
        require(profile['schema']=='brohn-report-package-runtime-profile/0.1' and runtime['Python']==profile['runtime']['Python'],'EDA projection Python runtime differs from the pinned report profile.')
        result=inspect(load(args.inspect)) if args.inspect else project(load(args.request),Path(args.artifacts) if args.artifacts else out.parent/'streams')
        result['verified_runtime']=runtime
        out.parent.mkdir(parents=True,exist_ok=True);out.write_bytes(eda.json_bytes(result)+b'\n');return 0
    except Exception as e:
        out.parent.mkdir(parents=True,exist_ok=True)
        out.write_bytes(eda.json_bytes(e.detail if isinstance(e,eda.Refusal) else {'schema':'brohn-eda-stream-error/0.1','message':str(e)})+b'\n');return 1


if __name__=='__main__':sys.exit(main())
