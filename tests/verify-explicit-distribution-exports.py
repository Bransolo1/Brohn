"""Independent stdlib oracle for actual researcher downloads, not R summaries."""
import csv
import hashlib
import json
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

fixture = Path(sys.argv[1]).resolve()
evidence = Path(sys.argv[2]).resolve()
assert fixture.name.startswith("brohn-explicit-distributions-")
assert evidence.parent == fixture
config = json.loads((fixture / "fixture.json").read_text(encoding="utf-8"))
source = json.loads((fixture / "independent-source.json").read_text(encoding="utf-8"))


def canonical(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


analysis_hash = hashlib.sha256(canonical(source["analysis"]).encode("utf-8")).hexdigest()
assert analysis_hash == config["original"]["analysis_hash"]
receipt = []
for file in sorted(evidence.glob("distribution-*.json")):
    document = json.loads(file.read_text(encoding="utf-8"))
    group = document["group"]
    assert document["binding"]["analysis_sha256"] == analysis_hash
    assert document["binding"]["report_hash"] == config["original"]["report_hash"]
    item = "q-number-1" if group["family"] == "scale" else group["item_id"]
    records = [r for r in source["analysis"]["observations"]
               if r["question_id"] == item and r["condition_id"] == group["condition_id"]]
    values = [(2 * r["value"] if group["family"] == "scale" else r["value"])
              for r in records if r["status"] == "answered"]
    assert group["source_records"] == len(records) == 30
    assert group["usable_records"] == len(values)
    assert group["assessment_count"] == 30
    assert group["participant_count"] == (10 if group["condition_id"] == "A" else None)
    csv_file = file.with_suffix(".csv")
    with csv_file.open(encoding="utf-8", newline="") as handle:
        rows = list(csv.DictReader(handle))
    assert sum(int(row["count"]) for row in rows) == len(values)
    assert all(row["analysis_sha256"] == analysis_hash for row in rows)
    assert all(int(row["eligible_record_denominator"]) == len(values) for row in rows)
    assert all(json.loads(row["missingness_json"]) == group["states"] for row in rows)
    if group["quantitative"]:
        assert abs(group["summary"]["mean"] - sum(values) / len(values)) < 1e-12
        for row in rows:
            interval = json.loads(row["exact_value_json"])
            count = sum(v >= interval["lower"] and
                        (v <= interval["upper"] if interval["upper_inclusive"] else v < interval["upper"])
                        for v in values)
            assert int(row["count"]) == count
    else:
        assert {row["exact_value_json"]: int(row["count"]) for row in rows} == {canonical(v): 1 for v in values}
        assert next(r for r in rows if r["exact_value_json"] == '"\u96ea"')["label"] == "\u96ea"
        assert next(r for r in rows if r["exact_value_json"] == '"=1+1"')["label"] == "'=1+1"
    receipt.append({"group": group["id"], "csv_rows": len(rows), "eligible_records": len(values),
                    "csv_sha256": hashlib.sha256(csv_file.read_bytes()).hexdigest()})
assert len(receipt) == 8
figures = []
for file in sorted(evidence.glob("distribution-*.svg")):
    svg = ET.fromstring(file.read_bytes())
    metadata = json.loads(svg.find("{http://www.w3.org/2000/svg}metadata").text)
    assert metadata["source"]["analysis_sha256"] == analysis_hash
    assert metadata["source"]["report_hash"] == config["original"]["report_hash"]
    assert metadata["shown"] <= 20
    figures.append({"file": file.name, "group": metadata["group_id"], "offset": metadata["offset"],
                    "sha256": hashlib.sha256(file.read_bytes()).hexdigest()})
assert len(figures) == 9 and sum(f["offset"] == 20 for f in figures) == 1
result = {"passed": True, "oracle": "Python standard library; source arithmetic and original typed values",
          "analysis_sha256": analysis_hash, "report_hash": config["original"]["report_hash"],
          "groups": receipt, "svg_figures": figures, "csv_rows": sum(r["csv_rows"] for r in receipt),
          "browser_results_sha256": hashlib.sha256((evidence / "results.json").read_bytes()).hexdigest()}
(evidence / "independent-export-audit.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
print(json.dumps({"passed": True, "groups": len(receipt), "csv_rows": result["csv_rows"], "svg_figures": len(figures)}))
