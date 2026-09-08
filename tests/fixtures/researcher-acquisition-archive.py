"""Independently read a generated original ZIP without extracting or executing members."""
import hashlib, json, sys, zipfile
from collections import defaultdict
with zipfile.ZipFile(sys.argv[1]) as source:
    manifest = json.loads(source.read('manifest.json'))
    rows = defaultdict(list)
    for chunk in manifest['chunks']:
        content = source.read(chunk['path'])
        assert hashlib.sha256(content).hexdigest() == chunk['sha256']
        assert len(content) == chunk['bytes']
        decoded = [json.loads(line) for line in content.splitlines() if line]
        assert len(decoded) == chunk['rows']
        rows[chunk['stream_id']].extend(decoded)
    print(json.dumps({'manifest': manifest, 'request': json.loads(source.read('request.json')),
        'streams': json.loads(source.read('streams.json')), 'rows': rows,
        'journal': [json.loads(line) for line in source.read('journal.jsonl').splitlines() if line],
        'inventory': [{'path': x.filename, 'hash': hashlib.sha256(source.read(x.filename)).hexdigest(), 'bytes': x.file_size}
            for x in source.infolist() if not x.is_dir()]}))
