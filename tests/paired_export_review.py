"""Independent XML/CSV review of original synthetic paired browser exports.

Usage: python tests/paired_export_review.py <browser-evidence-directory>
Never opens a participant dataset or regenerates scientific outputs.
"""
import csv
import hashlib
import json
import math
import sys
import xml.etree.ElementTree as ET
from pathlib import Path


def main():
    folder = Path(sys.argv[1]).resolve(strict=True)
    assert folder.name.startswith("browser-")
    checks = []

    def check(value, name):
        assert value, name
        checks.append(name)

    def read(name):
        return json.loads((folder / name).read_text(encoding="utf-8"))

    def svg(name):
        root = ET.parse(folder / name).getroot()
        ns = {"s": "http://www.w3.org/2000/svg"}
        return root, ns, json.loads(root.find("s:metadata", ns).text)

    model = read("explicit-paired.json")
    acceptance = read("acceptance.json")
    reference = acceptance["fixture"]["reports"]["questionnaire"]
    check(model["report_id"] == reference["id"] and model["report_hash"] == reference["hash"]
          and model["origin"] == "sample" and acceptance["reports_unchanged"] is True,
          "Export remains bound to the actual unchanged synthetic worker report")
    check([p["control_mean"] for p in model["people"]] == [11, 10, 10]
          and [p["test_mean"] for p in model["people"]] == [15, 18, 22]
          and [p["difference"] for p in model["people"]] == [4, 8, 12],
          "Complete means/differences match original repeated-visit arithmetic")
    # Closed-form t(.975,df=2), independently of R's saved qt()/sd() path.
    margin = math.sqrt(2 * .95 ** 2 / (1 - .95 ** 2)) * 4 / math.sqrt(3)
    interval = model["saved_contrast"]["interval95"]
    check(abs(interval["lower"] - (8 - margin)) < 1e-9
          and abs(interval["upper"] - (8 + margin)) < 1e-9,
          "Saved uncertainty matches independent df2 closed form")
    root, ns, metadata = svg("explicit-means.svg")
    check(metadata["report_hash"] == model["report_hash"]
          and metadata["source_hash"] == model["source_hash"]
          and metadata["people"] == model["people"],
          "SVG exact metadata identifies every plotted source person")
    groups = {g.attrib["data-person"]: g for g in root.findall("s:g", ns)}
    check(set(groups) == {"P1", "P2", "P3"}, "Paired SVG contains exactly three original people")
    endpoints = {person: (float(g.find("s:line", ns).attrib["y1"]),
                          float(g.find("s:line", ns).attrib["y2"]))
                 for person, g in groups.items()}
    y10 = endpoints["P2"][0]
    unit = y10 - endpoints["P1"][0]
    check(unit > 0 and abs(endpoints["P3"][0] - y10) < .001
          and all(abs(endpoints[p][1] - (y10 - delta * unit)) < .01
                  for p, delta in [("P1", 5), ("P2", 8), ("P3", 12)]),
          "Actual SVG condition endpoints preserve independent value distances")
    check(all(abs(float(g.find("s:circle", ns).attrib["cy"]) - endpoints[p][0]) < .001
              for p, g in groups.items()), "Hollow control marks coincide with original condition endpoints")
    root, ns, metadata = svg("explicit-differences.svg")
    positions = {c.attrib["data-person"]: float(c.attrib["cx"])
                 for c in root.findall("s:circle", ns)}
    step = positions["P2"] - positions["P1"]
    check(step > 0 and abs((positions["P3"] - positions["P2"]) - step) < .002,
          "Difference SVG preserves equal original four-unit increments")
    line = next(l for l in root.findall("s:line", ns) if l.attrib.get("stroke") == "#f4c67a")
    span = float(line.attrib["x2"]) - float(line.attrib["x1"])
    check(abs(span / (step / 4) - 2 * margin) < .002
          and metadata["saved_estimate"] == 8 and metadata["saved_interval95"] == interval,
          "Drawn interval has the original saved uncertainty width and estimate")
    with (folder / "explicit-paired.csv").open(newline="", encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle))
    sources = [r for r in rows if r["record_type"] == "source_observation"]
    people = [r for r in rows if r["record_type"] == "person"]
    check(len(rows) == 25 and len(sources) == 16 and len(people) == 3
          and all(r["report_hash"] == model["report_hash"] for r in rows),
          "CSV retains all source/visit/person records and original report identity")
    check(sum(r["value"] == "" for r in sources) == 2
          and sum(r["missing_reason"] == "outside_selected_conditions" for r in sources) == 5,
          "CSV missing values and outside-condition observations retain exact support")
    if (folder / "thousand-person-page2.svg").exists():
        _, _, metadata = svg("thousand-person-page2.svg")
        expected = [f"Person{i:04d}" for i in range(51, 101)]
        check(metadata["page"] == 2 and metadata["total_people"] == 1000
              and [p["participant_id"] for p in metadata["people"]] == expected
              and all(p["control_mean"] == 12 and p["test_mean"] == 14 and p["difference"] == 2
                      for p in metadata["people"]),
              "Large SVG page preserves all fifty exact original people and values")
        complete = read("thousand-person-complete.json")
        check(len(complete["people"]) == 1000 and len(complete["observations"]) == 3000
              and complete["people"][-1]["participant_id"] == "Person1000",
              "Full exported selection includes the original final source person")
    result = {"schema": "brohn-paired-export-review/1.0", "origin": "original_synthetic",
              "checks": checks,
              "export_sha256": {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
                                for p in folder.iterdir() if p.suffix in {".svg", ".csv"}}}
    (folder / "independent-export-review.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
    print(json.dumps({"checks": len(checks), "receipt": str(folder / "independent-export-review.json")}))


if __name__ == "__main__":
    main()
