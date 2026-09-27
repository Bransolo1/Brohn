"""Bounded deterministic archive for an already assembled Brohn report package."""
from __future__ import annotations
import argparse
import hashlib
import json
import os
import platform
from pathlib import Path
import re
import stat
import sys
import zipfile

SCHEMA = 'brohn-report-package-archive-request/0.1'
MAX_BYTES = 256 * 1024 * 1024
MAX_FILES = 1024
FIXED_TIME = (1980, 1, 1, 0, 0, 0)

def fail(message):
    raise ValueError(message)

def unique_object(pairs):
    value = {}
    for key, item in pairs:
        if key in value:
            fail('Duplicate JSON field')
        value[key] = item
    return value

def strict_json(path, maximum=1024*1024):
    raw = Path(path).read_bytes()
    if not 0 < len(raw) <= maximum:
        fail('JSON request exceeds its bound')
    return json.loads(raw.decode('utf-8'), object_pairs_hook=unique_object,
                      parse_constant=lambda _: fail('Nonfinite JSON'))

def fields(value, expected):
    if not isinstance(value, dict) or set(value) != set(expected):
        fail('Unsupported record fields')

def integer(value, low, high):
    return type(value) is int and low <= value <= high

def safe_name(value):
    if not isinstance(value, str) or len(value) > 180 or not re.fullmatch(r'[a-z0-9][a-z0-9._/-]*', value):
        fail('Archive paths must be generated relative ASCII names')
    if any(part in ('', '.', '..') or part.endswith(('.', ' ')) or
           part.split('.')[0] in {'con','prn','aux','nul',*(f'com{i}' for i in range(1,10)),*(f'lpt{i}' for i in range(1,10))}
           for part in value.split('/')):
        fail('Archive path is unsafe')
    return value

def descriptor(root, item):
    fields(item, ['path','sha256','bytes','media_type','role'])
    safe_name(item['path'])
    if not isinstance(item['sha256'],str) or not re.fullmatch('[a-f0-9]{64}',item['sha256']) or not integer(item['bytes'],0,MAX_BYTES):
        fail('Invalid payload descriptor')
    if not all(isinstance(item[k],str) and 0 < len(item[k]) <= 120 for k in ('media_type','role')):
        fail('Invalid payload semantics')
    path=root/item['path']
    cursor=root
    for part in item['path'].split('/'):
        cursor=cursor/part
        if cursor.is_symlink() or getattr(cursor.lstat(),'st_file_attributes',0) & 0x400:
            fail('Links/reparse entries cannot enter a report archive')
    if not path.is_file() or not path.resolve().is_relative_to(root.resolve()):
        fail('Payload does not resolve inside the owned directory')
    if path.stat().st_size != item['bytes']:
        fail('Payload size changed')
    with path.open('rb') as stream:
        actual=hashlib.file_digest(stream,'sha256').hexdigest()
    if actual != item['sha256']:
        fail('Payload bytes changed')
    return path

def verify_archive(path, entries):
    with zipfile.ZipFile(path) as archive:
        info=archive.infolist()
        if archive.comment or [x.filename for x in info] != [x['path'] for x in entries]:
            fail('Archive ordering or inventory changed')
        for member, expected in zip(info,entries):
            if (member.date_time != FIXED_TIME or member.compress_type != zipfile.ZIP_STORED or
                member.create_system != 0 or member.create_version != 20 or member.extract_version != 20 or
                member.external_attr != (stat.S_IFREG|0o644)<<16 or member.internal_attr != 0 or
                member.extra or member.comment or member.flag_bits or member.is_dir() or
                member.file_size != expected['bytes']):
                fail('Archive metadata violates deterministic profile')
            digest=hashlib.sha256()
            with archive.open(member) as stream:
                while chunk:=stream.read(1024*1024):
                    digest.update(chunk)
            if digest.hexdigest() != expected['sha256']:
                fail('Archive member failed byte integrity')

def run(request):
    fields(request,['schema','root','files','manifest','limits'])
    if request['schema'] != SCHEMA:
        fail('Unsupported archive request')
    fields(request['limits'],['max_members','max_payload_bytes'])
    limit=request['limits']
    if not integer(limit['max_members'],1,MAX_FILES) or not integer(limit['max_payload_bytes'],1,MAX_BYTES):
        fail('Archive limits exceed the fixed maximum')
    root=Path(request['root'])
    if not root.is_absolute() or not root.is_dir() or root.is_symlink() or getattr(root.lstat(),'st_file_attributes',0)&0x400:
        fail('Archive needs a real owned output directory')
    if not isinstance(request['files'],list):
        fail('Payload inventory must be an array')
    entries=request['files']+[request['manifest']]
    if not 1 <= len(entries) <= limit['max_members']:
        fail('Archive member count exceeds its bound')
    for item in entries:
        descriptor(root,item)
    # Physical archive order is ASCII path order, independent of the display
    # section order and the scientific collection order inside each member.
    entries=sorted(entries,key=lambda item:item['path'])
    paths=[root/item['path'] for item in entries]
    names=[item['path'].casefold() for item in entries]
    if len(set(names)) != len(names) or sum(item['bytes'] for item in entries)>limit['max_payload_bytes']:
        fail('Duplicate archive names or excessive payload bytes')
    if request['manifest']['path']!='manifest.json' or any(x['path'] in ('manifest.json','report.brohn-report.zip') for x in request['files']):
        fail('Manifest inventory contains a circular artifact')
    manifest=strict_json(root/'manifest.json',4*1024*1024)
    if manifest.get('schema')!='brohn-report-package/0.1' or manifest.get('files')!=request['files']:
        fail('Manifest does not name the exact complete payload')
    archive_path=root/'report.brohn-report.zip'
    with zipfile.ZipFile(archive_path,'x',compression=zipfile.ZIP_STORED,allowZip64=False) as archive:
        for item,path in zip(entries,paths):
            info=zipfile.ZipInfo(item['path'],date_time=FIXED_TIME)
            info.compress_type=zipfile.ZIP_STORED
            info.create_system=0
            info.create_version=20
            info.extract_version=20
            info.external_attr=(stat.S_IFREG|0o644)<<16
            info.internal_attr=0
            info.extra=b''
            info.comment=b''
            info.flag_bits=0
            # The complete package is bounded; stream instead of duplicating it.
            with archive.open(info,'w',force_zip64=False) as dest, path.open('rb') as source:
                digest=hashlib.sha256();count=0
                while chunk:=source.read(1024*1024):
                    count+=len(chunk)
                    if count>item['bytes']:
                        fail('Payload grew while archiving')
                    digest.update(chunk);dest.write(chunk)
                if count!=item['bytes'] or digest.hexdigest()!=item['sha256']:
                    fail('Payload changed while archiving')
    verify_archive(archive_path,entries)
    for item in entries:
        descriptor(root,item)
    with archive_path.open('rb') as stream:
        digest=hashlib.file_digest(stream,'sha256').hexdigest()
    return {'schema':'brohn-report-package-archive-result/0.1','passed':True,
            'artifact':{'path':'report.brohn-report.zip','sha256':digest,'bytes':archive_path.stat().st_size,
                        'media_type':'application/zip','role':'report_package'},
            'members':len(entries),'payload_bytes':sum(x['bytes'] for x in entries),
            'runtime':{'Python':{'implementation':platform.python_implementation(),'version':platform.python_version(),
                                  'executable_sha256':hashlib.sha256(Path(sys.executable).read_bytes()).hexdigest()}}}

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--request',required=True)
    parser.add_argument('--output',required=True)
    args=parser.parse_args()
    out=Path(args.output)
    if out.exists():
        fail('Archive receipt already exists')
    result=run(strict_json(args.request))
    with out.open('x',encoding='utf-8',newline='\n') as stream:
        json.dump(result,stream,sort_keys=True,separators=(',',':'),ensure_ascii=False,allow_nan=False)
        stream.write('\n')

if __name__=='__main__':
    try:
        main()
    except Exception as error:
        print('Report archive refused: '+str(error),file=sys.stderr)
        raise SystemExit(1)
