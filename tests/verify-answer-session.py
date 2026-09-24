"""Independent retained SQL/byte/export checks; no Brohn or questionnaire scorer."""
import csv
import hashlib
import io
import json
from pathlib import Path
import sqlite3
import sys

folder, evidence = [Path(x).resolve() for x in sys.argv[1:3]]
assert folder.name.startswith("brohn-answer-session-browser-") and evidence.parent == folder
checks = []


def check(ok, label):
    assert ok, label
    checks.append(label)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def read(name):
    return json.loads((evidence / name).read_text(encoding="utf-8"))


db = sqlite3.connect((folder / "workspace/catalog.sqlite").as_uri() + "?mode=ro", uri=True)
db.row_factory = sqlite3.Row
result = read("results.json")
original = read("original-session.json")
check(result["passed"], "Actual connected participant/researcher journey passed")
run = db.execute("SELECT * FROM delivery_runs WHERE id=?", (result["run_id"],)).fetchone()
rows = db.execute("SELECT * FROM delivery_events WHERE run_id=? ORDER BY sequence", (run["id"],)).fetchall()
events = [json.loads(r["event_json"]) for r in rows]
check(events == original["events"] and len(events) == run["acked_sequence"], "All original received events remain unchanged and acknowledged")
check([r["sequence"] for r in rows] == list(range(1, len(rows) + 1)), "Received sequence is complete, ordered and duplicate free")
check(all(sha(r["event_json"].encode("utf-8")) == r["event_hash"] for r in rows), "Every original event row retains its independent byte hash")
complete = ("[" + ",".join(r["event_json"] for r in rows) + "]").encode("utf-8")
check((evidence / "received-events.json").read_bytes() == complete, "Downloaded complete journal equals exact ordered original canonical bytes")
check(read("assigned-protocol.json") == json.loads(run["protocol_json"]) == original["run"]["protocol"], "Assigned protocol download preserves the original protocol independently of received evidence")
check(run["completion_status"] == "completed" and run["transfer_status"] == "saved", "Original genuine completion remains terminal and saved")
receipts = [dict(x) for x in db.execute("SELECT * FROM delivery_receipts WHERE scope=? ORDER BY operation,operation_id", (run["id"],))]
check(receipts == original["receipts"] and sum(r["operation"] == "finish" for r in receipts) == 1, "No invented or replacement final receipt was created")
csv_rows = list(csv.DictReader(io.StringIO((evidence / "received-event-timeline.csv").read_text(encoding="utf-8"))))
check(len(csv_rows) == len(rows) and [int(x["sequence"]) for x in csv_rows] == list(range(1, len(rows) + 1)), "Timeline CSV contains every received event exactly once")
check(all(c["event_sha256"] == r["event_hash"] and c["event_type"] == e["type"] and json.loads(c["clock_json"]) == e["clock"] for c, r, e in zip(csv_rows, rows, events)), "Timeline CSV preserves original event hashes, types and separate clock instances")


def entity(kind, identity):
    row = db.execute("SELECT v.* FROM entities e JOIN entity_versions v ON e.kind=v.kind AND e.id=v.id AND e.revision=v.revision WHERE e.kind=? AND e.id=?", (kind, identity)).fetchone()
    assert row is not None and sha(row["body_json"].encode("utf-8")) == row["body_hash"]
    return row, json.loads(row["body_json"])


_, report = entity("report", result["report_id"])
observations = report["analysis"]["observations"]
check(len(observations) == 2 and next(x for x in observations if x["question_id"] == "original-liking")["value"] == 0, "Original scoring keeps two final observed responses and exact numeric zero")
check(not any(x["question_id"] == "original-detail" for x in observations), "Finally hidden dependent answer was not reintroduced as a scored response")
revision = report["analysis"]["questionnaire_revision"]["runs"][0]
check(len(revision["invalidations"]) > 0 and revision["events_hash"] == sha(complete), "Original dependency clearing retains the exact full received journal binding")
review_ids = [r["id"] for r in db.execute("SELECT id FROM entities WHERE kind='answer_session' ORDER BY id")]
prior_count = len(result.get("priorDerivedJobs", []))
check(len(review_ids) == 2 + prior_count, "Two current selected-answer views and explicitly retained earlier reader attempts are accounted for")
downloaded = read("review-provenance.json")
for identity in review_ids:
    row, view = entity("answer_session", identity)
    request = view["request"]
    check(view["report_id"] == report["id"] and request["run_source"]["events_hash"] == sha(complete) and request["run_source"]["protocol_hash"] == run["protocol_hash"], f"{identity}: exact original report, protocol and complete journal are pinned")
    if identity == downloaded["id"]:
        check(view == downloaded, "Downloaded provenance equals the retained immutable review revision")
    for name, ref in view["exports"].items():
        p = folder / "workspace/objects/sha256" / ref["hash"][:2] / ref["hash"]
        data = p.read_bytes()
        assert sha(data) == ref["hash"] and len(data) == ref["size"]
        if name == "session-evidence.sqlite":
            derived = sqlite3.connect(p.as_uri() + "?mode=ro", uri=True)
            derived_rows = derived.execute("SELECT sequence,event_json,event_hash FROM events ORDER BY sequence").fetchall()
            assert derived_rows == [(r["sequence"], r["event_json"], r["event_hash"]) for r in rows]
            assert derived.execute("SELECT count(*) FROM assigned").fetchone()[0] == len(original["run"]["protocol"]["timeline"])
            derived.close()
    check(True, f"{identity}: every export hash/size verifies and the complete derived SQL rows equal the original journal")
    env = view["result_object"]
    envelope = json.loads((folder / "workspace/objects/sha256" / env["hash"][:2] / env["hash"]).read_text(encoding="utf-8"))
    check(envelope == {k: v for k, v in view.items() if k != "result_object"}, f"{identity}: retained publication envelope matches catalog")
jobs = list(db.execute("SELECT operation,status,attempt FROM jobs"))
check(len(jobs) == 4 + prior_count and all(j["status"] == "succeeded" and j["attempt"] == 1 for j in jobs), "Exact successful attempt-one job count includes explicitly retained earlier readers; reopening/restart added no analysis")
check(sorted(j["operation"] for j in jobs) == ["analyse_run"] + ["answer_session"] * (2 + prior_count) + ["questionnaire_index"], "Only one original scoring job; other jobs are read-only indexes and session reviews")
db.close()
(evidence / "independent-source-audit.json").write_text(json.dumps({"passed": True, "checks": checks, "run_id": run["id"], "original_events_hash": sha(complete)}, indent=2), encoding="utf-8")
print(json.dumps({"passed": True, "checks": len(checks), "evidence": str(evidence)}))
