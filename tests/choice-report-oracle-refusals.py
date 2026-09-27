"""Adversarial scientific/download-oracle checks, using copied package bytes."""
import argparse
import copy
import hashlib
import json
import subprocess
import sys
import zipfile
from pathlib import Path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("bundle", type=Path)
    parser.add_argument("archive", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    assert not args.output.exists()
    args.output.mkdir(parents=True)
    verifier = Path(__file__).with_name("verify_choice_download.py")
    with zipfile.ZipFile(args.archive) as z:
        original = {name: z.read(name) for name in z.namelist()}
    changes = [
        ("dropped-excluded-row", "evidence/report-01.json", lambda d: d["analysis"]["source_rows"].pop()),
        ("partial-null-becomes-blank", "evidence/report-01.json", lambda d: d["analysis"]["observations"][-2].__setitem__("worst_id", "")),
        ("false-becomes-zero", "evidence/report-01.json", lambda d: d["analysis"]["observations"][-1].__setitem__("presented", 0)),
        ("opaque-response-substitution", "evidence/report-01.json", lambda d: d["analysis"]["observations"][0].__setitem__("id", "another-response")),
        ("unknown-scientific-field", "evidence/report-01.json", lambda d: d["analysis"]["choice_tasks"][0].__setitem__("new_value", 0)),
        ("blank-mapped-cell-substitution", "evidence/report-01.json", lambda d: d["analysis"]["source_rows"][-2]["mapped_cells"].__setitem__("best_id", "invented-item")),
        ("broken-selected-alias-link", "evidence/report-01.json", lambda d: d["analysis"]["source_rows"][0]["mapped_cells"].__setitem__("person_code", "report-01-person-9999")),
        ("saved-null-se-becomes-zero", "evidence/choices/report-01.json", lambda d: d["evidence"]["exercises"][0]["original_result"]["model"]["utilities"][0].__setitem__("standard_error", 0)),
        ("false-coverage", "manifest.json", lambda d: d["choice_source_coverage"][0]["collections"][0].__setitem__("rows", 0)),
    ]
    outcomes = []
    for name, path, change in changes:
        payload = copy.copy(original)
        data = json.loads(payload[path])
        change(data)
        payload[path] = json.dumps(data, separators=(",", ":"), ensure_ascii=True).encode()
        manifest = json.loads(payload["manifest.json"])
        for descriptor in manifest["files"]:
            raw = payload[descriptor["path"]]
            descriptor.update(bytes=len(raw), sha256=hashlib.sha256(raw).hexdigest())
        payload["manifest.json"] = json.dumps(manifest, separators=(",", ":"), ensure_ascii=True).encode()
        archive = args.output / (name + ".zip")
        with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_STORED) as z:
            for member in sorted(payload):
                z.writestr(zipfile.ZipInfo(member, (1980, 1, 1, 0, 0, 0)), payload[member])
        completed = subprocess.run([sys.executable, str(verifier), "--bundle", str(args.bundle), "--zip", str(archive), "--output", str(args.output / name)], capture_output=True, text=True, timeout=60)
        (args.output / (name + ".stderr.txt")).write_text(completed.stderr, encoding="utf-8")
        assert completed.returncode != 0 and "AssertionError" in completed.stderr, name
        outcomes.append(dict(case=name, refused=True, reason=completed.stderr.splitlines()[-1]))
    result = dict(schema="brohn-choice-independent-oracle-refusals/0.1", passed=True, checks=len(outcomes), outcomes=outcomes,
                  verifier_sha256=hashlib.sha256(verifier.read_bytes()).hexdigest(), original_archive_sha256=hashlib.sha256(args.archive.read_bytes()).hexdigest(),
                  scope="Synthetic mutations of copied artifact bytes with internally consistent new manifest hashes. Original files untouched; no application or scorer imports.")
    (args.output / "results.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(dict(passed=True, checks=len(outcomes))))


if __name__ == "__main__":
    main()
