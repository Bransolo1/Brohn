"""Independent offline landmark-name regression, including repeated adapters.

Accepts one or more rendered package directories and a new receipt path. This
checks accessible names rather than merely unique IDs. No browser or service.
"""
import argparse
import hashlib
import json
from html.parser import HTMLParser
from pathlib import Path

class Document(HTMLParser):
    def __init__(self):
        super().__init__()
        self.sections = []
        self.headings = {}
        self.current = None
        self.section = None
        self.caption = None
        self.captions = {}

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == 'section' and 'aria-labelledby' in attrs:
            self.sections.append((attrs.get('id'), attrs['aria-labelledby'].split()))
            self.section = attrs.get('id')
            self.captions[self.section] = []
        if tag == 'p' and self.section is not None and 'muted' in attrs.get('class', '').split():
            self.caption = []
            self.captions[self.section].append(self.caption)
        if tag == 'h2' and 'id' in attrs:
            assert attrs['id'] not in self.headings, 'Duplicate heading ID'
            self.current = attrs['id']
            self.headings[self.current] = []

    def handle_data(self, data):
        if self.current is not None:
            self.headings[self.current].append(data)
        if self.caption is not None:
            self.caption.append(data)

    def handle_endtag(self, tag):
        if tag == 'h2':
            self.current = None
        if tag == 'p':
            self.caption = None
        if tag == 'section':
            self.section = None

def inspect(package):
    path = package / 'report.html'
    doc = Document()
    doc.feed(path.read_text(encoding='utf-8'))
    manifest = json.loads((package / 'manifest.json').read_text(encoding='utf-8'))
    sections = sorted(manifest['selection']['sections'], key=lambda section: section['order'])
    assert len(doc.sections) == len(sections), 'Every selected section needs one named region'
    names = []
    source_contexts = []
    for (region_id, refs), selected in zip(doc.sections, sections):
        assert refs and all(ref in doc.headings for ref in refs), 'Region label must resolve to visible headings'
        text = ' '.join(' '.join(doc.headings[ref]) for ref in refs)
        name = ' '.join(text.split()).casefold()
        assert name, 'Every region needs a nonempty accessible name'
        names.append(name)
        source_index = manifest['sources']['reports'].index(selected['source_report_ref']) + 1
        projection = json.loads((package / f'evidence/report-{source_index:02d}.json').read_text(encoding='utf-8'))
        assert projection['source_ref'] == selected['source_report_ref'], 'Caption must identify the exact selected source'
        captions = [' '.join(' '.join(text).split()) for text in doc.captions[region_id]]
        assert len(captions) == 1, 'Each section needs one complete visible source context caption'
        expected = f"Source {source_index} \u2014 {projection['report']['title']} | origin: {projection['report']['origin']}"
        assert captions[0] == ' '.join(expected.split()), 'Complete saved source title and origin must remain visible below its heading'
        source_contexts.append({'index': source_index, 'caption': captions[0]})
    assert len(names) == len(set(names)), 'Region role/name pairs must be unique, including deliberately repeated panels'
    assert all(name.endswith(f"source {source['index']}") for name, source in zip(names, source_contexts)), 'Concise region name must end with its source ordinal; full saved title belongs in the following caption'
    return {'package': str(package), 'html_sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
            'regions': len(names), 'accessible_names': names, 'source_contexts': source_contexts, 'passed': True}

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('packages', nargs='+', type=Path)
    args = parser.parse_args()
    results = []
    for package in args.packages:
        try:
            results.append(inspect(package))
        except (AssertionError, KeyError, ValueError) as error:
            results.append({'package': str(package), 'passed': False, 'error': str(error)})
    receipt = {'schema': 'brohn-report-package-landmark-check/0.1',
               'passed': all(result['passed'] for result in results), 'results': results,
               'scope': 'Offline semantic section-region names and visible heading/source bindings; no browser layout or complete WCAG claim.'}
    with args.output.open('x', encoding='utf-8') as stream:
        json.dump(receipt, stream, ensure_ascii=True, indent=2)
        stream.write('\n')
    print(json.dumps(receipt))
    raise SystemExit(0 if receipt['passed'] else 1)
