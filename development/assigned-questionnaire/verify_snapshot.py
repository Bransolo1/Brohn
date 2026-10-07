"""Read-only stdlib audit of the inactive snapshot. Not a runtime/test runner."""
from pathlib import Path
import hashlib
import json
import re

root = Path(__file__).resolve().parent
manifest = json.loads((root / 'SOURCES.json').read_text(encoding='utf-8'))
dependencies = json.loads((root / 'DEPENDENCIES.json').read_text(encoding='utf-8'))
expected = dependencies['expected_snapshot']
if expected != {'source_files': 76, 'relative_imports': 81}:
    raise ValueError('Unexpected checkpoint composition')
files = {}
for entry in manifest['files']:
    path = root / entry['path']
    if not path.resolve().is_relative_to(root.resolve()):
        raise ValueError('Source path escapes the snapshot')
    raw = path.read_bytes()
    if len(raw) != entry['bytes'] or hashlib.sha256(raw).hexdigest() != entry['sha256']:
        raise ValueError('Source mismatch: ' + entry['path'])
    if entry['path'] in files:
        raise ValueError('Duplicate source: ' + entry['path'])
    files[entry['path']] = raw
inventory = {p.relative_to(root).as_posix() for directory in ('R', 'www', 'scripts')
             for p in (root / directory).rglob('*') if p.is_file()}
if inventory != set(files) or len(files) != expected['source_files']:
    raise ValueError('Source inventory differs from the closed snapshot')
imports = []
for name, raw in files.items():
    if not name.endswith(('.mjs', '.js')):
        continue
    for specifier in re.findall(r"(?:from\s+|import\s*)['\"]([^'\"]+)['\"]", raw.decode('utf-8')):
        if not specifier.startswith('./'):
            raise ValueError('Unexpected import: ' + specifier)
        target = (Path(name).parent / specifier).as_posix()
        if target not in files:
            raise ValueError('Missing dependency: ' + target)
        imports.append({'source': name, 'imported': target,
                        'sha256': hashlib.sha256(files[target]).hexdigest()})
if imports != dependencies['javascript_imports'] or len(imports) != expected['relative_imports']:
    raise ValueError('Dependency identities differ from the closed snapshot')
print(json.dumps({'source_files': len(files), 'relative_imports': len(imports),
                  'result': 'Exact source identity and static relative-import closure only',
                  'runtime_or_scientific_qualification': False}))
