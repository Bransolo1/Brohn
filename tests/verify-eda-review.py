"""Independent retained-source/export/figure oracle. No production reader import."""
import csv
import hashlib
import io
import json
from pathlib import Path
import sys
import xml.etree.ElementTree as ET

folder=Path(sys.argv[1]);output=Path(sys.argv[2])
config=json.loads((folder/"fixture.json").read_text(encoding="utf-8"))
snapshot=json.loads((folder/"snapshot.json").read_text(encoding="utf-8"))
receipt=json.loads((output/"results.json").read_text(encoding="utf-8"))
checks=[]
def check(value,label):
    assert value,label
    checks.append(label);print("PASS",label)
def object_bytes(ref):
    h=ref["hash"];p=Path(config["workspace"])/"objects/sha256"/h[:2]/h
    raw=p.read_bytes();assert hashlib.sha256(raw).hexdigest()==h and len(raw)==ref["size"]
    return raw
report=next(r["body"] for r in snapshot["reports"] if r["id"]==receipt["report_id"])
original=json.loads((output/"original-report.json").read_text(encoding="utf-8"))
check(report==original,"Original report is unchanged from the actual pre-review browser download")
check(hashlib.sha256(Path(config["source"]).read_bytes()).hexdigest()==config["source_hash"],"Original imported conductance bytes are unchanged")
source=[];candidate_rows=[]
for artifact in report["analysis"]["artifacts"]:
    if artifact["kind"] not in ("physiology-series","physiology-events"):continue
    stream=[json.loads(line) for line in object_bytes(artifact).splitlines()]
    check(stream[0]["type"]=="header" and stream[-1]["type"]=="complete",f"{artifact['kind']} complete original typed stream is present with matching hash")
    specs={r["table_id"]:r for r in stream if r["type"]=="table"}
    for chunk in (r for r in stream if r["type"]=="rows"):
        spec=specs[chunk["table_id"]];fields=[c["name"] for c in spec["columns"]]
        for n,values in enumerate(chunk["rows"]):
            row=dict(zip(fields,values));row.update(table_id=chunk["table_id"],segment_id=spec["identity"]["segment_id"],table_row_index=chunk["offset"]+n,identity=spec["identity"])
            (source if artifact["kind"]=="physiology-series" else candidate_rows).append(row)
check(len(source)==4499 and 3000 not in [r["source_sample_index"] for r in source],"Complete processed source preserves 4499 observed rows and omits the actual missing sample")
for saved in snapshot["reviews"]:
    b=saved["body"];r=b["result"];e=r["event"];sel=r["binding"]["selection"]
    original_event=next(x for x in report["analysis"]["recordings"] if all(x[k]==v for k,v in sel.items()))
    expected_features=[x for x in report["analysis"]["features"] if all(x[k]==v for k,v in sel.items())]
    check(e==original_event and r["features"]==expected_features,f"{e['exposure_id']}: exact original support and every original feature remain unchanged")
    retained=json.loads(object_bytes(b["result_object"]))
    check(retained=={k:v for k,v in b.items() if k!="result_object"},f"{e['exposure_id']}: published sealed result agrees with the catalog")
    lo=e["time_s"]+r["parameters"]["baseline_s"][0];hi=e["time_s"]+r["parameters"]["recovery_end_s"]
    expected=sorted([row for row in source if row["identity"]["recording_id"]==sel["recording_id"] and row["identity"]["channel"]==sel["channel"] and lo<=row["time_s"]<=hi],key=lambda row:row["time_s"])
    csv_rows=list(csv.DictReader(io.StringIO(object_bytes(b["exports"]["eda-window-samples.csv"]).decode("utf-8"))))
    assert len(csv_rows)==len(expected)==r["counts"]["selected_rows"]
    for actual,want in zip(csv_rows,expected):
        for field in ("time_s","source_sample_index","table_row_index","clean_us","tonic_us","phasic_us"):assert float(actual[field])==want[field]
        assert actual["retained"]==str(want["retained"]).lower() and actual["table_id"]==want["table_id"]
        assert float(actual["relative_time_s"])==want["time_s"]-e["time_s"]
    check(True,f"{e['exposure_id']}: every complete CSV row independently matches the original typed artifact")
    check(sum(x["retained"] for x in expected)==r["counts"]["retained_rows"] and sum(not x["retained"] for x in expected)==r["counts"]["excluded_rows"],f"{e['exposure_id']}: retained/excluded denominators reconcile independently")
    by_index={row["source_sample_index"]:row for row in expected}
    for component,groups in r["series"].items():
        for group in groups:
            for pt in group["points"]:
                source_row=by_index[pt["source_sample_index"]]
                assert pt["value"]==source_row[component] and pt["time_s"]==source_row["time_s"]-e["time_s"] and group["table_id"]==source_row["table_id"] and group["retained"]==source_row["retained"]
    check(True,f"{e['exposure_id']}: all three plotted components contain actual source values and separated support runs")
    for m in r["markers"]:
        c=next(x for x in candidate_rows if x["source_peak_sample"]==m["candidate_source_peak_sample"])
        key={"onset":"onset_time_s","peak":"peak_time_s","recovery":"recovery_time_s"}[m["kind"]]
        assert m["source_time_s"]==c[key]
        if m["selected_for_event"]:assert all(c[k]==v for k,v in e["selected_scr"].items())
        if m["kind"]=="recovery" and e["recovery_missing_reason"]:assert not m["event_measure_usable"]
    marker_csv=list(csv.DictReader(io.StringIO(object_bytes(b["exports"]["eda-response-markers.csv"]).decode("utf-8"))))
    check(len(marker_csv)==len(r["markers"]),f"{e['exposure_id']}: complete candidate markers retain exact source timing and recovery eligibility")
ns={"s":"http://www.w3.org/2000/svg"}
svg=ET.fromstring((output/"responder.svg").read_bytes());meta=json.loads(svg.find("s:metadata",ns).text)
check(meta["event"]==next(e for e in report["analysis"]["recordings"] if e["exposure_id"]=="responder") and meta["component"]=="phasic_us","SVG metadata binds the exact original response and conductance component")
for g in svg.findall("s:g",ns):
    if g.attrib.get("data-selected")=="true" and g.attrib.get("data-marker")=="peak":
        peak=meta["event"]["selected_scr"]["peak_time_s"];expected_x=96+(peak-meta["event"]["time_s"]+2)/12*(878-96)
        actual_x=float(g.find("s:path",ns).attrib["d"].split(",")[0][1:]);assert abs(actual_x-expected_x)<1e-7
check(True,"SVG selected peak geometry preserves exact measured onset-relative source timing")
check(all(j["status"]=="succeeded" and j["attempt"]==1 for j in receipt["jobs"]),"All accepted import/scientific/derived jobs succeeded on one actual attempt")
result=dict(passed=True,checks=checks,scope="Original synthetic software evidence; no clinical, emotion, hardware timing or scientific qualification claim.",receipt_sha256=hashlib.sha256((output/"results.json").read_bytes()).hexdigest())
(output/"independent-source-audit.json").write_text(json.dumps(result,indent=2),encoding="utf-8")
print(len(checks),"independent checks passed")
