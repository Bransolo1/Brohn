"""File receipts shared by the portable connected test and independent closer."""
from pathlib import Path
import hashlib,json,os,stat
FLAGS=0x08000000 if os.name=='nt' else 0
R_NAMES={'rscript.exe','r.exe','rterm.exe','r','rscript'}
def read(path):return json.loads(Path(path).read_text(encoding='utf-8-sig'))
def sha(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def entry(path):
    path=Path(path).resolve();return dict(path=str(path),bytes=path.stat().st_size,sha256=sha(path))
def write(path,value):
    with Path(path).open('x',encoding='utf-8',newline='\n') as stream:
        json.dump(value,stream,indent=2,ensure_ascii=False);stream.write('\n')
def source_path(path):
    """Refuse every lexical alias before resolving or traversing source."""
    path=Path(os.path.abspath(path))
    for part in [*reversed(path.parents),path]:
        info=os.lstat(part)
        if stat.S_ISLNK(info.st_mode) or getattr(info,'st_file_attributes',0)&0x400:
            raise ValueError('Source aliases/reparse points are not admitted: '+str(part))
    if os.path.normcase(str(path))!=os.path.normcase(str(path.resolve(strict=True))):
        raise ValueError('Source lexical/resolved path differs: '+str(path))
    return path

def source_files(checkout):
    checkout=source_path(checkout);files=[]
    def walk(folder):
        with os.scandir(folder) as stream:children=sorted(stream,key=lambda p:p.name)
        for item in children:
            p=source_path(Path(item.path))
            info=item.stat(follow_symlinks=False)
            if item.name=='__pycache__':continue
            if stat.S_ISDIR(info.st_mode):walk(p)
            elif stat.S_ISREG(info.st_mode):files.append(p)
            else:raise ValueError('Source is not a regular file or directory: '+str(p))
    for name in ['R','scripts','www','config','registry','src','docs','examples','tests']:
        folder=checkout/name
        if os.path.lexists(folder):
            folder=source_path(folder)
            if not folder.is_dir():raise ValueError('Source directory is not a directory: '+str(folder))
            walk(folder)
    with os.scandir(checkout) as stream:children=sorted(stream,key=lambda p:p.name)
    for item in children:
        info=item.stat(follow_symlinks=False)
        if stat.S_ISREG(info.st_mode) or item.is_symlink() or getattr(info,'st_file_attributes',0)&0x400:
            p=source_path(item.path)
            if not p.is_file():raise ValueError('Root source is not a regular file: '+str(p))
            files.append(p)
    return [dict(entry(p),path=p.relative_to(checkout).as_posix()) for p in sorted(set(files))]

def process_issue(issues,phase,error,pid=None):
    row=dict(phase=phase,pid=pid,type=type(error).__name__,message=str(error))
    if row not in issues:issues.append(row)

def scan_r(psutil,issues,phase):
    rows=[]
    try:
        for process in psutil.process_iter():
            try:
                name=process.name();created=process.create_time()
                if not isinstance(name,str) or not name:raise ValueError('Process name is unavailable')
                if name.lower() in R_NAMES:rows.append(dict(pid=process.pid,name=name,create_time=created))
            except psutil.NoSuchProcess:pass
            except Exception as error:process_issue(issues,phase,error,process.pid)
    except Exception as error:process_issue(issues,phase,error)
    return rows

def verify(output):
    saved=read(Path(output)/'INPUTS.json')
    assert source_files(saved['checkout'])==saved['source_files'],'Checkout source changed.'
    for row in saved['test_files']+saved['tools']:
        assert entry(row['path'])==row,row['path']
    return saved
