"""Independent, narrowly scoped full-to-evidence-only comparison; stdlib only.

Does not replace the existing oracle's strict --compare-zip mode, which requires
the same scientific AND prepared source sets and every complete companion.
"""
import argparse
import csv
import hashlib
import io
import json
from pathlib import Path
import zipfile


def sha(data):
    return hashlib.sha256(data).hexdigest()


def strict(a, b):
    return json.dumps(a, sort_keys=True, separators=(',', ':'), ensure_ascii=True) == json.dumps(b, sort_keys=True, separators=(',', ':'), ensure_ascii=True)


def inventory(path):
    raw = path.read_bytes()
    with zipfile.ZipFile(io.BytesIO(raw)) as z:
        assert len(z.namelist()) == len(set(z.namelist())), 'duplicate ZIP member'
        files = {name: z.read(name) for name in z.namelist()}
    m = json.loads(files['manifest.json'])
    descriptors = {f['path']: f for f in m['files']}
    assert len(descriptors) == len(m['files']), 'duplicate manifest member'
    assert set(files) == set(descriptors) | {'manifest.json'}, 'manifest/member mismatch'
    for name, f in descriptors.items():
        assert len(files[name]) == f['bytes'] and sha(files[name]) == f['sha256'], name
    return raw, files, m, descriptors


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--full', type=Path, required=True)
    p.add_argument('--evidence-only', type=Path, required=True)
    p.add_argument('--full-oracle', type=Path, required=True)
    p.add_argument('--evidence-oracle', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    args = p.parse_args()
    assert not args.output.exists(), 'Use a fresh receipt path; do not replace evidence.'
    araw, af, a, ad = inventory(args.full)
    braw, bf, b, bd = inventory(args.evidence_only)
    assert len(af) == 82 and len(bf) == 52
    assert len(a['selection']['sections']) == 7 and b['selection']['sections'] == []
    assert len(a['sources']['reports']) == 6 and len(a['sources']['eda_displays']) == 5
    assert set(a['sources']) == set(b['sources'])
    assert [k for k in a['sources'] if not strict(a['sources'][k], b['sources'][k])] == ['distributions']
    assert len(a['sources']['distributions']) == 1 and b['sources']['distributions'] == []
    assert strict([x for x in a['selection']['prepared_sources'] if x['adapter'] != 'explicit-distribution'], b['selection']['prepared_sources'])
    changed_selection = [k for k in a['selection'] if not strict(a['selection'][k], b['selection'].get(k))]
    assert set(changed_selection) == {'frozen_at', 'id', 'prepared_sources', 'sections', 'title'}
    for key in ['choice_source_coverage', 'eda_source_coverage', 'implementation', 'profile', 'projection', 'schema', 'scope', 'task_material_coverage']:
        assert strict(a[key], b[key]), key
    assert b['coverage'] == []
    science = sorted(n for n in bf if n.startswith(('evidence/', 'data/')))
    assert len(science) == 49
    for n in science + ['schemas/numerical-evidence.json']:
        assert af[n] == bf[n] and strict(ad[n], bd[n]), n
    assert set(bf) <= set(af)
    removed = set(af) - set(bf)
    assert len(removed) == 30 and sum(n.startswith('figures/') for n in removed) == 25
    whitelist = {
        'evidence/distributions/section-006.json': 'complete_saved_distribution',
        'data/explicit/section-006-group-001.csv': 'complete_distribution_rows',
        'data/explicit/section-006-group-002.csv': 'complete_distribution_rows',
        'data/paired/section-007-comparison-001.json': 'complete_saved_paired_model',
        'data/paired/section-007-comparison-001.csv': 'complete_paired_evidence',
    }
    assert {n for n in removed if not n.startswith('figures/')} == set(whitelist)
    assert all(ad[n]['role'] == role for n, role in whitelist.items())
    assert sorted(n for n in set(af) & set(bf) if af[n] != bf[n]) == ['manifest.json', 'report.html']
    distribution_section, paired_section = a['selection']['sections'][5:7]
    assert distribution_section['adapter'] == 'explicit-distribution' and distribution_section['order'] == 6
    assert paired_section['adapter'] == 'paired-findings' and paired_section['order'] == 7
    report_ref = a['sources']['reports'][5]
    assert strict(distribution_section['source_report_ref'], report_ref) and strict(paired_section['source_report_ref'], report_ref)
    distribution = json.loads(af['evidence/distributions/section-006.json'])
    assert strict(distribution['source_ref'], distribution_section['source_ref'])
    assert strict(distribution['source_ref'], a['sources']['distributions'][0])
    assert strict(distribution['source_report_ref'], report_ref)
    assert len(distribution['result']['groups']) == 2
    for n in [k for k in whitelist if k.endswith('.csv')]:
        rows = list(csv.DictReader(io.StringIO(af[n].decode('utf-8'))))
        # The established paired CSV writer protects its ID display cell with
        # an apostrophe; typed JSON supplies the exact unprefixed identity.
        csv_id = "'" + report_ref['id'] if n.startswith('data/paired/') else report_ref['id']
        assert rows and all(r['report_id'] == csv_id and r['report_hash'] == report_ref['body_hash'] for r in rows), n
    paired = json.loads(af['data/paired/section-007-comparison-001.json'])
    assert (paired['report_id'], paired['report_revision'], paired['report_hash']) == (report_ref['id'], report_ref['revision'], report_ref['body_hash'])
    retained = json.loads(bf['evidence/report-06.json'])
    assert strict(retained['source_ref'], report_ref)
    assert len(retained['analysis']['contrasts']) == 1 and len(retained['analysis']['observations']) == 4
    assert strict(paired['saved_contrast'], retained['analysis']['contrasts'][0])
    assert strict([row['source_record'] for row in paired['observations']], retained['analysis']['observations'])
    oracle_proofs = []
    for source, expected_zip, expected_checks in [(args.full_oracle, araw, 171), (args.evidence_oracle, braw, 131)]:
        raw = source.read_bytes()
        oracle = json.loads(raw)
        assert oracle['passed'] is True and oracle['zip_sha256'] == sha(expected_zip)
        assert oracle['check_count'] == expected_checks
        assert (oracle['scientific_leaves'], oracle['identity_fields'], oracle['constant_coordinate_rows']) == (109863, 38232, 7000)
        oracle_proofs.append({'receipt_path': str(source), 'receipt_sha256': sha(raw), 'zip_sha256': oracle['zip_sha256'], 'checks': expected_checks,
                             'scientific_leaves': oracle['scientific_leaves'], 'identity_fields': oracle['identity_fields'], 'constant_coordinate_rows': oracle['constant_coordinate_rows']})
    assert sha(args.full.read_bytes()) == sha(araw) and sha(args.evidence_only.read_bytes()) == sha(braw)
    result = {'schema': 'brohn-peer-native-variant-conservation/0.1', 'passed': True,
        'scope': 'Exact six-source/five-EDA full-to-no-sections presentation variant only; no generic optional-adapter compatibility claim.',
        'full_zip_sha256': sha(araw), 'evidence_only_zip_sha256': sha(braw), 'script_sha256': sha(Path(__file__).read_bytes()),
        'scientific_report_refs': b['sources']['reports'], 'eda_prepared_refs': b['sources']['eda_displays'],
        'source_identity_graph_unchanged': True, 'source_projection_and_eda_coverage_unchanged': True,
        'complete_members_unchanged': [bd[n] for n in science], 'complete_member_count': 49,
        'schema_bytes_unchanged': True, 'removed_figure_count': 25, 'removed_section_companions': [ad[n] for n in sorted(whitelist)],
        'optional_distribution_ref': a['sources']['distributions'][0],
        'section_binding_proofs': {'distribution_section': distribution_section['id'], 'paired_section': paired_section['id'], 'source_report_ref': report_ref,
            'distribution_group_count': 2, 'all_removed_csv_rows_bind_exact_report': True, 'paired_csv_exact_spreadsheet_safe_id_prefix': "'",
            'paired_saved_contrast_equals_retained_contrast': True, 'paired_source_records_equal_all_retained_observations': True,
            'retained_complete_observations': 4, 'retained_complete_contrasts': 1},
        'strict_compare_mode_failure_preserved': {'assertion': 'figure-only revision retains exact frozen source identities',
            'full_sources_equal': strict(a['sources'], b['sources']), 'reason': 'One optional prepared distribution source was removed with its whole figure section. Strict mode requires the same scientific AND prepared sources and all companions.',
            'existing_oracle_modified': False, 'original_frozen_attempt_modified': False, 'note': 'Original strict invocation failure reported in the parent run is retained. This receipt independently evaluates its failing predicate; it does not fabricate a traceback or rerun that oracle.'},
        'standalone_original_source_oracles': oracle_proofs,
        'inputs_unchanged': True, 'scientific_processing_started': False}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
    print(json.dumps({'passed': True, 'complete_members': 49, 'scientific_sources': 6, 'EDA_preparations': 5, 'receipt_sha256': sha(args.output.read_bytes())}))


if __name__ == '__main__':
    main()
