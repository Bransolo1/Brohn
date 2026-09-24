"""Download pinned official fixture tools outside this repository; no installation.

Hashes are vendor GitHub release asset digests checked on the lock date. This
does not claim an independent signature verification or production deployment.
Nothing is added to PATH, OS certificate stores, services or firewall rules.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import tarfile
import urllib.request
import zipfile


def sha(path):
    with path.open('rb') as handle:
        return hashlib.file_digest(handle, 'sha256').hexdigest()


def safe_target(root, name):
    if '\\' in name or ':' in name or name.startswith('/'):
        raise ValueError('Unsafe vendor archive member')
    target = (root / name).resolve()
    if not target.is_relative_to(root.resolve()):
        raise ValueError('Vendor archive escaped its destination')
    return target


def extract(archive, target):
    target.mkdir()
    if archive.name.endswith('.zip'):
        with zipfile.ZipFile(archive) as source:
            for member in source.infolist():
                dest = safe_target(target, member.filename)
                if (member.external_attr >> 16) & 0o170000 == 0o120000:
                    raise ValueError('Vendor symlinks are unsupported')
                if member.is_dir():
                    dest.mkdir(parents=True, exist_ok=True)
                else:
                    dest.parent.mkdir(parents=True, exist_ok=True)
                    with source.open(member) as reader, dest.open('xb') as writer:
                        shutil.copyfileobj(reader, writer)
    else:
        with tarfile.open(archive, 'r:gz') as source:
            for member in source:
                dest = safe_target(target, member.name)
                if member.isdir():
                    dest.mkdir(parents=True, exist_ok=True)
                elif member.isfile():
                    dest.parent.mkdir(parents=True, exist_ok=True)
                    with source.extractfile(member) as reader, dest.open('xb') as writer:
                        shutil.copyfileobj(reader, writer)
                else:
                    raise ValueError('Non-file vendor archive member')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('destination', type=Path)
    parser.add_argument('--lock', type=Path, default=Path(__file__).resolve().parents[1] / 'tests/fixtures/hosted-oidc/vendor-lock.json')
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[1]
    root = args.destination.resolve()
    if root.is_relative_to(repo):
        raise ValueError('Keep downloaded runtimes outside the source repository')
    root.mkdir(parents=True, exist_ok=True)
    lock = json.loads(args.lock.read_text(encoding='utf-8'))
    receipt = {'schema': 'brohn-hosted-tooling/1.0', 'lock_sha256': sha(args.lock), 'vendors': []}
    for vendor in lock['vendors']:
        archive = root / vendor['archive']
        if not archive.exists():
            temporary = archive.with_suffix(archive.suffix + '.partial')
            if temporary.exists():
                raise ValueError('Retained partial download exists: ' + str(temporary))
            request = urllib.request.Request(vendor['url'], headers={'User-Agent': 'Brohn-pinned-local-fixture'})
            with urllib.request.urlopen(request, timeout=60) as reader, temporary.open('xb') as writer:
                shutil.copyfileobj(reader, writer, 1024 * 1024)
            if sha(temporary) != vendor['sha256']:
                raise ValueError('Vendor archive hash differs; retained partial: ' + str(temporary))
            temporary.rename(archive)
        if sha(archive) != vendor['sha256']:
            raise ValueError('Existing vendor archive hash differs')
        target = root / (vendor['id'] + '-' + vendor['version'])
        marker = target / '.brohn-extracted.json'
        if not target.exists():
            extract(archive, target)
            marker.write_text(json.dumps({'archive_sha256': vendor['sha256']}), encoding='utf-8')
        if not marker.is_file() or json.loads(marker.read_text())['archive_sha256'] != vendor['sha256']:
            raise ValueError('Incomplete or mismatched extraction; retained for inspection')
        exe = target / vendor['executable']
        if not exe.is_file():
            raise ValueError('Pinned executable missing: ' + str(exe))
        receipt['vendors'].append(dict(vendor, directory=str(target), executable_path=str(exe), executable_sha256=sha(exe)))
        print('Verified', vendor['id'], vendor['version'], flush=True)
    output = root / 'tooling-receipt.json'
    output.write_text(json.dumps(receipt, indent=2), encoding='utf-8')
    print(str(output), flush=True)


if __name__ == '__main__':
    main()
