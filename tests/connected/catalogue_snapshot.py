"""Copy a stable saved SQLite catalogue without opening or changing originals."""
from pathlib import Path
import hashlib,os,stat

CATALOGUE_FILES=('catalog.sqlite','catalog.sqlite-wal','catalog.sqlite-shm')
def digest(raw):return hashlib.sha256(raw).hexdigest()

def copy_catalogue(workspace,destination,original_files):
    workspace=Path(workspace).resolve(strict=True);destination=Path(destination).resolve()
    if destination.exists() or destination.is_relative_to(workspace) or workspace.is_relative_to(destination):
        raise ValueError('Use a fresh snapshot directory outside the original workspace.')
    expected={row['path']:row for row in original_files if row['path'] in CATALOGUE_FILES}
    if 'catalog.sqlite' not in expected:raise ValueError('The original saved catalogue is missing.')
    present={name for name in CATALOGUE_FILES if os.path.lexists(workspace/name)}
    if present!=set(expected):raise ValueError('Original catalogue sidecar membership changed.')
    destination.mkdir(parents=True,exist_ok=False);copied=[]
    for name in CATALOGUE_FILES:
        if name not in expected:continue
        source=workspace/name;info=os.lstat(source)
        if not stat.S_ISREG(info.st_mode) or stat.S_ISLNK(info.st_mode) or getattr(info,'st_file_attributes',0)&0x400:
            raise ValueError('Catalogue aliases and non-regular files are not admitted.')
        raw=source.read_bytes();row=dict(path=name,bytes=len(raw),sha256=digest(raw))
        if row!=expected[name]:raise ValueError('Original catalogue bytes changed during copying: '+name)
        target=destination/name;target.write_bytes(raw)
        if target.read_bytes()!=raw:raise ValueError('Copied catalogue bytes differ: '+name)
        copied.append(row)
    return destination/'catalog.sqlite',copied
