"""Portable deterministic synthetic archive/raster boundaries; no study data."""
from __future__ import annotations
import argparse,copy,hashlib,importlib.util,io,json,subprocess,sys,zipfile
from pathlib import Path
from PIL import Image,__version__ as pillow_version

parser=argparse.ArgumentParser();parser.add_argument('output');args=parser.parse_args()
out=Path(args.output).resolve();out.mkdir(parents=True,exist_ok=False)
base=Path(__file__).parent
if not (base/'report_package_archive.py').is_file():base=base.parent/'scripts'/'workers'
def load(name):
    spec=importlib.util.spec_from_file_location(name,base/(name+'.py'));module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);return module
archive=load('report_package_archive');raster=load('report_package_raster')
checks=[]
def check(name,condition):
    if not condition:raise AssertionError(name)
    checks.append(name)
def refused(name,fn,fragment):
    try:fn()
    except (ValueError,OSError,FileNotFoundError) as e:check(name,fragment in str(e))
    else:raise AssertionError(name+' accepted')
def sha(raw):return hashlib.sha256(raw).hexdigest()
def desc(root,name,media='application/json',role='synthetic_payload'):
    raw=(root/name).read_bytes();return dict(path=name,sha256=sha(raw),bytes=len(raw),media_type=media,role=role)
def archive_request(name):
    root=out/name;root.mkdir();(root/'data.json').write_bytes(b'{"false":false,"null":null,"value":0}\n')
    files=[desc(root,'data.json')]
    (root/'manifest.json').write_text(json.dumps({'schema':'brohn-report-package/0.1','files':files},sort_keys=True,separators=(',',':'))+'\n',encoding='utf-8')
    return dict(schema=archive.SCHEMA,root=str(root),files=files,manifest=desc(root,'manifest.json',role='portable_inventory'),limits={'max_members':10,'max_payload_bytes':10000})
r=archive_request('archive-good');result=archive.run(r)
check('archive creates fixed complete file',result['passed'] and result['members']==2)
r2=archive_request('archive-repeat');again=archive.run(r2)
check('archive independent directory byte determinism',result['artifact']==again['artifact'])
with zipfile.ZipFile(Path(r['root'])/'report.brohn-report.zip') as z:
    check('stdlib independently reads all CRC-protected original bytes',z.testzip() is None and z.read('data.json')==(Path(r['root'])/'data.json').read_bytes())
for name,change,fragment in [
 ('archive-bad-sha',lambda r:r['files'][0].update(sha256='0'*64),'Payload bytes changed'),
 ('archive-bad-size',lambda r:r['files'][0].update(bytes=1),'Payload size changed'),
 ('archive-member-bound',lambda r:r['limits'].update(max_members=1),'member count'),
 ('archive-byte-bound',lambda r:r['limits'].update(max_payload_bytes=1),'excessive payload'),
 ('archive-duplicate',lambda r:r['files'].append(copy.deepcopy(r['files'][0])),'Duplicate archive names'),
 ('archive-unsafe',lambda r:r['files'][0].update(path='../data.json'),'relative ASCII'),
 ('archive-boolean-bound',lambda r:r['limits'].update(max_members=True),'limits exceed')]:
    bad=archive_request(name);change(bad);refused(name,lambda:archive.run(bad),fragment)
bad=archive_request('archive-byte-mutation');p=Path(bad['root'])/'data.json';p.write_bytes(b'X'*p.stat().st_size)
refused('archive detects changed original bytes',lambda:archive.run(bad),'Payload bytes changed')
for path in ('/absolute','a/../../x','con.json','a//b','a/','a./x','x\\y'):
    refused('unsafe path '+path,lambda:archive.safe_name(path),'Archive path')
duplicate=out/'duplicate.json';duplicate.write_text('{"a":1,"a":2}',encoding='utf-8')
refused('strict duplicate JSON refuses',lambda:archive.strict_json(duplicate),'Duplicate JSON field')

def raster_request(name,fmt,mode='RGB',orientation=None):
    image=Image.new(mode,(8,6),(80,120,160) if mode=='RGB' else 80)
    data=io.BytesIO();options={}
    if orientation is not None:
        exif=Image.Exif();exif[274]=orientation;options['exif']=exif
    image.save(data,format=fmt,**options);raw=data.getvalue();path=out/name;path.write_bytes(raw)
    return dict(schema='brohn-report-package-raster-request/0.1',path=str(path),sha256=sha(raw),bytes=len(raw),media_type='image/'+('jpeg' if fmt=='JPEG' else 'png'),width=8,height=6)
png=raster_request('valid.png','PNG');jpg=raster_request('valid.jpg','JPEG')
for r in (png,jpg):
    before=Path(r['path']).read_bytes();v=raster.validate(r)
    check('actual bounded '+r['media_type']+' pixel decode',v['passed'] and v['width']==8 and v['height']==6 and v['pillow']==pillow_version)
    check('original '+r['media_type']+' bytes unchanged',before==Path(r['path']).read_bytes())
for name,change,fragment in [
 ('raster-sha',lambda r:r.update(sha256='0'*64),'integrity'),
 ('raster-width',lambda r:r.update(width=9),'dimensions'),
 ('raster-format',lambda r:r.update(media_type='image/jpeg'),'format'),
 ('raster-pixel-bound',lambda r:r.update(width=4096,height=4096),'8 million'),
 ('raster-side-bound',lambda r:r.update(width=4097),'4096'),
 ('raster-byte-bound',lambda r:r.update(bytes=5*1024**2+1),'5 MiB'),
 ('raster-boolean-width',lambda r:r.update(width=True),'4096')]:
    bad=copy.deepcopy(png);change(bad);refused(name,lambda:raster.validate(bad),fragment)
rotated=raster_request('orientation6.jpg','JPEG',orientation=6)
refused('EXIF orientation ambiguity explicit refusal',lambda:raster.validate(rotated),'EXIF-oriented')
corrupt=copy.deepcopy(png);raw=Path(corrupt['path']).read_bytes()[:40];path=out/'truncated.png';path.write_bytes(raw);corrupt.update(path=str(path),bytes=len(raw),sha256=sha(raw))
refused('valid signature but corrupt pixel body refuses',lambda:raster.validate(corrupt),'cannot identify')
corrupt=copy.deepcopy(jpg);raw=Path(corrupt['path']).read_bytes()[:100];path=out/'truncated.jpg';path.write_bytes(raw);corrupt.update(path=str(path),bytes=len(raw),sha256=sha(raw))
refused('valid JPEG signature but truncated body refuses',lambda:raster.validate(corrupt),'Truncated')
request=out/'raster-cli-request.json';request.write_text(json.dumps(jpg),encoding='utf-8');receipt=out/'raster-cli-result.json'
process=subprocess.run([sys.executable,'-B',str(base/'report_package_raster.py'),'--request',str(request),'--output',str(receipt)],capture_output=True,text=True,check=False)
check('actual raster CLI verifies original JPEG',process.returncode==0 and json.loads(receipt.read_text())['sha256']==jpg['sha256'])
process=subprocess.run([sys.executable,'-B',str(base/'report_package_raster.py'),'--request',str(request),'--output',str(receipt)],capture_output=True,text=True,check=False)
check('raster CLI refuses output overwrite',process.returncode!=0)
request=out/'archive-cli-request.json';request.write_text(json.dumps(archive_request('archive-cli')),encoding='utf-8');receipt=out/'archive-cli-result.json'
process=subprocess.run([sys.executable,'-B',str(base/'report_package_archive.py'),'--request',str(request),'--output',str(receipt)],capture_output=True,text=True,check=False)
check('actual archive CLI succeeds with exact generated bytes',process.returncode==0 and json.loads(receipt.read_text())['passed'])
report=dict(schema='brohn-report-package-helper-tests/0.1',passed=True,check_count=len(checks),checks=checks,python=sys.version,pillow=pillow_version,
            sources={f:sha((base/f).read_bytes()) for f in ('report_package_archive.py','report_package_raster.py')},scope='Self-contained synthetic helper boundaries only; no reader authority or physical devices')
(out/'results.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8');print(json.dumps({k:v for k,v in report.items() if k not in ('checks','sources')}))
