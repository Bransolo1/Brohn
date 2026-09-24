"""Independent SQLite/object/download audit; imports no Brohn application code."""
from pathlib import Path
import hashlib
import json
import sqlite3
import sys

folder, evidence = (Path(x).resolve() for x in sys.argv[1:3])
assert folder.name.startswith("brohn-runner-provenance-browser-") and evidence.parent == folder
checks = []
def check(ok, label):
    assert ok, label
    checks.append(label)
def sha(data): return hashlib.sha256(data).hexdigest()
def read(name): return json.loads((evidence / name).read_text(encoding="utf-8"))
cfg = json.loads((folder / "fixture.json").read_text())
result = read("results.json")
check(result["passed"], "Actual connected researcher and participant browser journey passed")
joined_path = evidence / "continued-native-evidence.json"
if joined_path.exists():
    joined = read("continued-native-evidence.json")
    source_dir = Path(joined["prior_browser"])
    check(source_dir.parent == folder and source_dir != evidence, "Continuation cites the exact retained native browser phase in the same isolated fixture")
    for receipt in joined["receipts"]:
        source = Path(receipt["source"])
        assert source.parent == source_dir and sha(source.read_bytes()) == receipt["sha256"] and source.read_bytes() == (evidence / source.name).read_bytes()
    check(joined["source_hashes"] == read("source-hashes.json"), "Completed participant phase and read-only continuation use the same frozen production source hashes; copied receipts are byte-exact")
db = sqlite3.connect((folder / "workspace/catalog.sqlite").as_uri() + "?mode=ro", uri=True)
db.row_factory = sqlite3.Row
j = result["journey"]
release = db.execute("SELECT * FROM delivery_deployments WHERE id=?", (j["release_id"],)).fetchone()
run = db.execute("SELECT * FROM delivery_runs WHERE id=?", (j["run_id"],)).fetchone()
runtime = db.execute("SELECT * FROM delivery_runtimes WHERE deployment_id=?", (release["id"],)).fetchone()
assignment = db.execute("SELECT * FROM delivery_run_runtimes WHERE run_id=?", (run["id"],)).fetchone()
manifest_bytes = runtime["manifest_json"].encode()
manifest = json.loads(manifest_bytes)
check(sha(manifest_bytes) == runtime["manifest_hash"] == assignment["manifest_hash"] and assignment["deployment_id"] == run["deployment_id"] == release["id"], "Exact release/session manifest binding and original canonical hash agree")
manifest_names = ["new-release-manifest.json", "run-manifest.json", "collection-code-manifest.json", "report-code-manifest.json", "reopened-code-manifest.json"]
check(all((evidence / name).read_bytes() == manifest_bytes for name in manifest_names), "Every Collect Review History report and reopened manifest download is byte-exact to the stored manifest")
for item in manifest["files"]:
    content = folder / "workspace/objects/sha256" / item["hash"][:2] / item["hash"]
    data = content.read_bytes()
    assert len(data) == item["size"] and sha(data) == item["hash"]
check(True, "Independent oracle verifies every preserved object byte and length, beyond the view's manifest-only check")
check(db.execute("SELECT count(*) FROM delivery_runtimes WHERE deployment_id=?", (cfg["legacy_release"],)).fetchone()[0] == 0 and db.execute("SELECT count(*) FROM delivery_run_runtimes WHERE run_id=?", (cfg["legacy_run"],)).fetchone()[0] == 0, "Explicit historical fixture has no retrospectively inferred release/session assignment")
for name in ["historic-release-code.json", "historic-collection-code.json"]:
    old = read(name)
    check(old["status"] == "legacy_unpinned" and old["manifest"] is None and old["manifest_hash"] is None and old["source"]["deployment_id"] == cfg["legacy_release"], f"{name}: unknown history remains source-bound and explicit")
report = db.execute("SELECT v.* FROM entities e JOIN entity_versions v ON e.kind=v.kind AND e.id=v.id AND e.revision=v.revision WHERE e.kind='report' AND e.id=?", (j["report_id"],)).fetchone()
report_body = json.loads(report["body_json"])
check(sha(report["body_json"].encode()) == report["body_hash"] and report_body == read("native-report-before.json") == read("native-report-after.json"), "Native scientific report and downloaded JSON remain exact through code review")
for name in ["new-release-code.json", "run-code.json", "report-linked-code.json"]:
    record = read(name)
    assert record["source"]["deployment_id"] == release["id"] and record["source"]["study_id"] == cfg["study_id"] and record["manifest"] == manifest and record["manifest_hash"] == runtime["manifest_hash"]
    if record["source"]["kind"] == "run":
        assert record["source"]["id"] == run["id"] and record["source"]["protocol_hash"] == run["protocol_hash"]
check(True, "All separate provenance downloads retain exact scientific-source identity without altering its original schema")
linked = read("report-linked-code.json")
check(linked["report"] == {"id":report["id"], "revision":report["revision"], "hash":report["body_hash"]}, "Report code link pins exact report revision and original body hash")
check(sha(run["protocol_json"].encode()) == run["protocol_hash"] and (evidence / "assigned-protocol-before.json").read_bytes() == (evidence / "assigned-protocol-after.json").read_bytes() == run["protocol_json"].encode(), "Assigned scientific protocol is byte-identical before and after nested code review")
check((evidence / "historic-collection-before.json").read_bytes() == (evidence / "historic-collection-after.json").read_bytes(), "Historical finalized inventory stays byte-identical through separate unknown-code review")
check((evidence / "new-finalized-collection.json").read_bytes() == (evidence / "reopened-collection.json").read_bytes(), "New finalized collection remains byte-identical after actual restart")
events = db.execute("SELECT * FROM delivery_events WHERE run_id=? ORDER BY sequence", (run["id"],)).fetchall()
check(run["completion_status"] == "completed" and run["transfer_status"] == "saved" and [e["sequence"] for e in events] == list(range(1,len(events)+1)) and run["acked_sequence"] == len(events), "Actual participant has one complete contiguous saved journal")
for event in events:
    assert sha(event["event_json"].encode()) == event["event_hash"]
values = [json.loads(e["event_json"])["payload"]["value"] for e in events if json.loads(e["event_json"])["type"] == "response"]
check(values == [5] and [o["value"] for o in report_body["analysis"]["observations"]] == [5], "Original received rating5 is retained by the actual native report")
credentials = [r[0] for r in db.execute("SELECT token FROM delivery_deployment_credentials")] + [r[0] for r in db.execute("SELECT token FROM delivery_run_credentials")]
code_names = manifest_names + ["historic-release-code.json", "historic-collection-code.json", "new-release-code.json", "run-code.json", "report-linked-code.json"]
check(all(not any(value in (evidence / name).read_text(encoding="utf-8") for value in credentials + ["ORIGINAL-CODE-SESSION", "SYNTHETIC-HISTORIC", "synthetic-historical-client"]) for name in code_names), "Code downloads expose no capabilities participant aliases or original browser client identifiers")
jobs = [dict(r) for r in db.execute("SELECT operation,status,attempt FROM jobs")]
check(jobs == [{"operation":"analyse_run","status":"succeeded","attempt":1}], "Exactly one actual native analysis succeeded; all code views and exports queued zero jobs")
before, after = read("after-participant.json"), read("final-snapshot.json")
check(before["sessions"] == after["sessions"] and before["reports"] == after["reports"], "Code review and restart preserved every original received session and scientific report")
check(all(x["violations"] == 0 and not x["overflow"] for x in result["scans"]), "Current recorded narrow and desktop scans have zero automated WCAG violations or page overflow")
db.close()
(evidence / "independent-source-audit.json").write_text(json.dumps({"passed":True,"checks":checks,"manifest_hash":runtime["manifest_hash"],"files":len(manifest["files"]),"jobs":jobs},indent=2),encoding="utf-8")
print(json.dumps({"passed":True,"checks":len(checks),"evidence":str(evidence)}))


if len(sys.argv) > 3:
    visual = Path(sys.argv[3]).resolve()
    assert visual.parent == folder
    visible = json.loads((visual / "results.json").read_text())
    rectangles = json.loads((visual / "advanced-source-text-bounds.json").read_text())
    delta_checks = []
    assert visible["passed"] and all(x["violations"] == 0 and not x["overflow"] for x in visible["scans"])
    assert all(b["left"] >= row["container"]["left"] and b["right"] <= min(row["container"]["right"], 390) for row in rectangles for b in row["bounds"])
    delta_checks.append("Actual wrapped source text lines all fit the 390px visible panel and current scans pass")
    assert (visual / "inspection-manifest.json").read_bytes() == manifest_bytes
    delta_checks.append("Post-fix download is byte-identical to the original preserved assignment, including its original runner bytes")
    assert visible["jobs"] == result["jobs"]
    delta_checks.append("The exact original successful job remains the only job after read-only visual verification")
    changed = {k for k,v in result["source_hashes"].items() if visible["source_hashes"].get(k) != v}
    assert changed == {"R/platform-runner-provenance-views.R", "www/participant/runner.js"}
    delta_checks.append("Joined source transition is limited to the approved wrapping view and separately qualified runner recovery patch")
    (visual / "independent-visual-delta.json").write_text(json.dumps({"passed":True,"checks":delta_checks,"manifest_hash":runtime["manifest_hash"],"jobs":visible["jobs"],"changed_sources":sorted(changed)},indent=2),encoding="utf-8")
    print(json.dumps({"passed":True,"visual_checks":len(delta_checks),"evidence":str(visual)}))
