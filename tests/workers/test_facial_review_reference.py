"""Original saved native reference agreement; never imports or reruns a model."""
import argparse,csv,hashlib,json,os,struct,sys,zlib
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[2]/'scripts/workers'))
import facial_review as f
parser=argparse.ArgumentParser();parser.add_argument('reference');parser.add_argument('evidence');args=parser.parse_args()
base=Path(args.reference).resolve();out=Path(args.evidence).resolve();out.mkdir(parents=True,exist_ok=False)
a=json.loads((base/'result.json').read_text());source=base/'authored-vfr-face-reference.mkv';originals={str(p):f.digest(p) for p in [source,*[Path(x['path']) for x in a['artifacts']]]}
b=f.encoded({'original_source':{'hash':a['source']['sha256'],'size':a['source']['bytes']}}).decode();request={'schema':'brohn-facial-review-request/1.0','operation':'build','analysis':a,'artifacts':[{k:x[k] for k in ('kind','path','sha256','bytes')} for x in a['artifacts']],'binding_json':b,'binding_sha256':f.common.sha(b.encode()),'index_path':str(out/'index.sqlite')}
result=f.build(request);r={'index_path':result['index']['path'],'index':result['index'],'binding_sha256':request['binding_sha256']};checks=[];frames=[]
def check(name,condition):
    assert condition,name;checks.append(name)
original=[f.loads(line,tokens=True) for line in Path(a['artifacts'][0]['path']).read_bytes().splitlines()]
check('Complete six mixed-state native frames',result['manifest']['frames']==6 and a['quality']['states']=={'no_face':2,'single_face':3,'multiple_faces':1})
for metric in f.METRICS:
    p=f.read(dict(r,operation='plot',metric=metric));family='au_scores' if metric in f.AUS else 'expression_scores'
    for got,expected in zip(p['points'],original):assert got['value']==(expected['faces'][0][family][metric] if expected['eligible'] else None)
check('All27 complete original score-token series agree exactly',True)
check('Closed exact0.04000000000000000001 bound excludes0.04', [x['frame_index'] for x in f.read(dict(r,operation='plot',metric='AU12',range=['0.04000000000000000001','0.11']))['points']]==['2'])
for i in range(6):
    directory=out/f'frame-{i}';directory.mkdir()
    result=f.extract(dict(r,schema='brohn-facial-frame-request/1.0',operation='frame',source_path=str(source),source=a['source'],frame_index=i,output_directory=str(directory)))
    data=Path(result['image']['path']).read_bytes();at=8;compressed=b'';width=height=None
    while at<len(data):
        n=struct.unpack('>I',data[at:at+4])[0];kind=data[at+4:at+8];body=data[at+8:at+8+n];at+=n+12
        if kind==b'IHDR':width,height=struct.unpack('>II',body[:8]);assert body[8:]==bytes([8,2,0,0,0])
        if kind==b'IDAT':compressed+=body
    scan=zlib.decompress(compressed);stride=width*3+1;assert len(scan)==height*stride
    # Shared helper deliberately writes filter0; independent PNG decode verifies RGB bytes.
    assert all(scan[y*stride]==0 for y in range(height));raw=b''.join(scan[y*stride+1:(y+1)*stride] for y in range(height))
    check(f'Original frame{i}: integerPTS,640x454PNG and exact independentlydecoded RGB',str(result['frame']['source_pts'])==str([2000,2040,2110,2310,2710,2910][i]) and (width,height)==(640,454) and hashlib.sha256(raw).hexdigest()==original[i]['decoded_rgb_sha256']==result['extraction']['rgb24_sha256'])
    frames.append(result)
export=f.read(dict(r,operation='export_csv',metric='happiness',output_path=str(out/'native-category.csv')))
check('Complete CSV includes both frame-local faces plus noface rows',export['rows']==7 and export['frames']==6)
check('Original video/nativeJSONL/CSV remain byte-identical',all(f.digest(Path(p))==sha for p,sha in originals.items()))
(out/'results.json').write_text(json.dumps({'status':'passed','checks':checks,'count':len(checks),'originals':originals,'derived_frames':frames,'sources':{p:f.digest(Path('scripts/workers')/p) for p in ['facial_review.py','vision_explorer.py','vision.py','media_pixels.py']},'scope':'Saved native model outputs/pixels agreement only; no new inference, identity tracking, model accuracy or emotion construct validation'},indent=2))
print(json.dumps({'status':'passed','checks':len(checks),'receipt':str(out/'results.json')}))
