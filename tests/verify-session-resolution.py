"""Independent SQLite, original-byte and downloaded-export oracle; no R scorer."""
import hashlib
import json
from pathlib import Path
import sqlite3
import sys

folder, evidence = map(lambda x: Path(x).resolve(), sys.argv[1:3])
assert folder.name.startswith("brohn-session-browser-") and evidence.parent == folder
checks = []

def check(value, label):
    assert value, label
    checks.append(label)

def read(name):
    return json.loads((evidence / name).read_text(encoding="utf-8"))

db = sqlite3.connect((folder / "workspace" / "catalog.sqlite").as_uri() + "?mode=ro", uri=True)
db.row_factory = sqlite3.Row

def entity(kind, identity):
    row = db.execute("SELECT v.* FROM entities e JOIN entity_versions v ON e.kind=v.kind AND e.id=v.id AND e.revision=v.revision WHERE e.kind=? AND e.id=?", (kind, identity)).fetchone()
    assert row is not None
    assert hashlib.sha256(row["body_json"].encode("utf-8")).hexdigest() == row["body_hash"]
    return row, json.loads(row["body_json"])

oracle = read("source-oracle.json")
receipt = read("results.json")
check(receipt["passed"], "Executed researcher and participant journey passed")
for kind in ("camera", "completion"):
    decision = read(f"{kind}-resolution.json")
    record, body = entity("session_resolution", decision["id"])
    check(record["revision"] == 1 and body == decision, f"{kind}: downloaded decision equals immutable SQLite revision")
    run_id = decision["run_id"]
    run = db.execute("SELECT * FROM delivery_runs WHERE id=?", (run_id,)).fetchone()
    check(run["completion_status"] == "in_progress" and run["transfer_status"] == "receiving" and run["finalized_at"] is None, f"{kind}: original final receipt remains missing")
    check(hashlib.sha256(run["protocol_json"].encode("utf-8")).hexdigest() == run["protocol_hash"] == decision["source"]["protocol_hash"], f"{kind}: original assigned protocol bytes and pin agree")
    rows = db.execute("SELECT sequence,event_json,event_hash FROM delivery_events WHERE run_id=? ORDER BY sequence", (run_id,)).fetchall()
    events = []
    for i, row in enumerate(rows, 1):
        assert row["sequence"] == i
        assert hashlib.sha256(row["event_json"].encode("utf-8")).hexdigest() == row["event_hash"]
        events.append(json.loads(row["event_json"]))
    check(events == oracle[kind]["events"] and len(events) == decision["source"]["received_sequence"] == run["acked_sequence"], f"{kind}: complete original journal preserved without late response insertion")
    check(db.execute("SELECT count(*) FROM delivery_receipts WHERE scope=? AND operation='finish'", (run_id,)).fetchone()[0] == 0, f"{kind}: no invented participant finish receipt")
    collection = read(f"{kind}-collection.json")
    _, saved = entity("collection", collection["id"])
    check(collection == saved and collection["counts"]["completed"] == 0 and collection["resolutions"][0]["hash"] == record["body_hash"], f"{kind}: collection export pins separate resolution while preserving original completion denominator")
    if kind == "camera":
        capture = db.execute("SELECT * FROM camera_captures WHERE run_id=?", (run_id,)).fetchone()
        chunks = db.execute("SELECT * FROM camera_chunks WHERE capture_id=? ORDER BY sequence", (capture["id"],)).fetchall()
        total = 0
        for chunk in chunks:
            sha = chunk["object_hash"]
            data = (folder / "workspace" / "objects" / "sha256" / sha[:2] / sha).read_bytes()
            assert hashlib.sha256(data).hexdigest() == sha
            observation_sha = chunk["observation_hash"]
            observation_bytes = (folder / "workspace" / "objects" / "sha256" / observation_sha[:2] / observation_sha).read_bytes()
            assert hashlib.sha256(observation_bytes).hexdigest() == observation_sha
            assert json.loads(observation_bytes)["sha256"] == sha
            original = next(c for c in oracle[kind]["chunks"] if c["sequence"] == chunk["sequence"])
            assert all(chunk[k] == v for k, v in original.items())
            assert len(data) == chunk["byte_count"]
            total += len(data)
        check(capture["status"] == "recording" and capture["final_json"] is None and total == capture["total_bytes"] == decision["source"]["camera"]["bytes"] > 0, "camera: actual original partial bytes retained with no invented endpoint or container completion")
        check(decision["participant_ending"] is None and not decision["received_completion_analysis_eligible"] and not collection["reports"], "camera: operator interruption produces no invented participant ending or scientific report")
    else:
        response = [e for e in events if e["type"] == "response"]
        ending = [e for e in events if e["type"] == "run_finished"]
        report = read("confirmed-completion-report.json")
        _, saved_report = entity("report", receipt["report_id"])
        check(len(response) == 1 and response[0]["payload"]["value"] == 0 and len(ending) == 1 and ending[0]["payload"]["outcome"] == "completed", "completion: independent raw journal establishes one actual zero answer and completed ending")
        check(report == saved_report and report["analysis"]["observations"][0]["value"] == response[0]["payload"]["value"] and report["provenance"]["session_resolution"]["hash"] == record["body_hash"], "completion: actual report export preserves exact original answer and pinned decision provenance")
        check(report["provenance"]["runs"][0]["finalized_at"] is None and collection["reports"][0]["id"] == receipt["report_id"], "completion: separate confirmed report is in collection without fabricating participant finalization")
jobs = [dict(r) for r in db.execute("SELECT id,operation,status,attempt FROM jobs ORDER BY id")]
check(len(jobs) == 1 and jobs[0]["operation"] == "analyse_resolved_run" and jobs[0]["status"] == "succeeded" and jobs[0]["attempt"] == 1, "Exactly one actual successful confirmed-completion worker attempt; no hidden camera or response jobs")
result = {"passed": True, "checks": checks, "jobs": jobs, "scope": "Independent read-only SQLite/source byte/download oracle; no natural participant or decoder qualification claim."}
(evidence / "independent-audit.json").write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
print(json.dumps({"passed": True, "checks": len(checks), "evidence": str(evidence)}))
