"""Read-only bounded pixel validation of a declared sealed report raster."""
from __future__ import annotations
import argparse,hashlib,io,json,warnings,platform,sys
from pathlib import Path
from PIL import Image, __version__ as PILLOW_VERSION

def require(condition,message):
    if not condition:raise ValueError(message)
def validate(request):
    require(isinstance(request,dict) and set(request)=={'schema','path','sha256','bytes','media_type','width','height'},'Unsupported raster request fields')
    require(request['schema']=='brohn-report-package-raster-request/0.1','Unsupported raster request')
    require(type(request['bytes']) is int and 1<=request['bytes']<=5*1024**2,'Raster exceeds 5 MiB')
    require(all(type(request[k]) is int and 1<=request[k]<=4096 for k in ('width','height')) and request['width']*request['height']<=8000000,'Raster exceeds 4096 side or 8 million pixels')
    require(request['media_type'] in ('image/png','image/jpeg'),'Only PNG and JPEG are supported')
    path=Path(request['path']);require(path.is_absolute() and path.is_file(),'An explicit sealed source is required')
    require(path.stat().st_size==request['bytes'],'Raster size changed')
    with path.open('rb') as stream:raw=stream.read(request['bytes']+1)
    require(len(raw)==request['bytes'] and hashlib.sha256(raw).hexdigest()==request['sha256'],'Raster byte integrity failed')
    Image.MAX_IMAGE_PIXELS=8000000
    with warnings.catch_warnings():
        warnings.simplefilter('error')
        with Image.open(io.BytesIO(raw)) as img:
            require(img.format=={'image/png':'PNG','image/jpeg':'JPEG'}[request['media_type']],'Decoded format differs from declared media')
            require(img.size==(request['width'],request['height']),'Decoded pixel dimensions differ from saved geometry')
            require(getattr(img,'n_frames',1)==1,'Animated rasters require a separately qualified presentation')
            # Applying EXIF rotation or reflection would transform the saved AOI
            # coordinate system; never guess which orientation the study used.
            orientation=img.getexif().get(274,1)
            require(type(orientation) is int and orientation==1,'EXIF-oriented raster geometry is unavailable: exclude the image to retain its labelled saved frame')
            require(img.mode in ('1','L','LA','P','RGB','RGBA','CMYK'),'Unsupported decoded raster mode')
            img.load()
            require(img.size==(request['width'],request['height']),'Decoded dimensions changed')
            result={'schema':'brohn-report-package-raster-result/0.1','passed':True,'sha256':request['sha256'],'bytes':len(raw),
                    'media_type':request['media_type'],'width':img.width,'height':img.height,'mode':img.mode,'frames':1,
                    'orientation':'identity_no_exif_transform','pillow':PILLOW_VERSION,'original_bytes_unchanged':True,
                    'runtime':{'Python':{'implementation':platform.python_implementation(),'version':platform.python_version(),
                                          'executable_sha256':hashlib.sha256(Path(sys.executable).read_bytes()).hexdigest()}}}
    return result
def unique(pairs):
    result={}
    for k,v in pairs:
        require(k not in result,'Duplicate raster field');result[k]=v
    return result
def main():
    p=argparse.ArgumentParser();p.add_argument('--request',required=True);p.add_argument('--output',required=True);args=p.parse_args()
    source=Path(args.request);require(0<source.stat().st_size<=16384,'Raster request exceeds bound')
    request=json.loads(source.read_text(encoding='utf-8'),object_pairs_hook=unique,parse_constant=lambda _:(_ for _ in ()).throw(ValueError('Nonfinite raster field')))
    result=validate(request)
    with Path(args.output).open('x',encoding='utf-8',newline='\n') as f:json.dump(result,f,sort_keys=True,separators=(',',':'),allow_nan=False);f.write('\n')
if __name__=='__main__':
    try:main()
    except Exception as error:
        import sys
        print('Report raster refused: '+str(error),file=sys.stderr);raise SystemExit(1)
