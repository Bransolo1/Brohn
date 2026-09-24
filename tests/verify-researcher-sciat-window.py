"""Independent actual-SQL, first-key, rational arithmetic and download oracle.

Does not import Brohn, its scorer, R or implicitMeasures. All RTs come from
the retained real browser events, never the automation's requested delays.
"""
import csv
from fractions import Fraction as F
import hashlib
import io
import json
import math
from pathlib import Path
import sqlite3
import sys

folder, evidence = (Path(p).resolve() for p in sys.argv[1:3])
assert folder.name.startswith("brohn-researcher-sciat-window-") and evidence.parent == folder
checks = []
def check(ok, label):
    assert ok, label
    checks.append(label)
def sha(b): return hashlib.sha256(b).hexdigest()
def read(name): return json.loads((evidence / name).read_text(encoding="utf-8"))
def csv_rows(name): return list(csv.DictReader(io.StringIO((evidence / name).read_text(encoding="utf-8-sig"))))
def close(a, b): return math.isclose(a, b, rel_tol=1e-12, abs_tol=1e-10)
def avg(values): return sum(values, F(0)) / len(values)
db = sqlite3.connect((folder / "workspace/catalog.sqlite").as_uri() + "?mode=ro", uri=True)
db.row_factory = sqlite3.Row
result = read("results.json")
journey = result["journey"]
check(result["passed"], "Actual connected researcher, participant, import and cohort journey passed")

if "carried_evidence" in result:
    bridge = result["carried_evidence"]
    original = Path(bridge["folder"]).resolve()
    assert original.parent == folder
    check(sha((original / "failure.json").read_bytes()) == bridge["prior_failure_hash"], "Carried partial-phase receipt is bound to its exact original bytes")
    check(len(bridge["files"]) == 40 and all(sha((original / name).read_bytes()) == digest == sha((evidence / name).read_bytes()) for name, digest in bridge["files"].items()), "All forty carried native/import/plot downloads retain exact source bytes and explicit phase attribution")
    check(all(result["source_hashes"][name] == digest for name, digest in bridge["source_hashes"].items()), "Every originally recorded runtime hash remains unchanged in the finish phase")
    check(bridge["known_prior_hash_omission"] == ["R/platform-task-plot-views.R"] and "R/platform-task-plot-views.R" in result["source_hashes"], "Earlier omitted plot-view source hash is disclosed; current render source is pinned without invented prior identity")
    check(read("FAST-final-plot-source.json") == read("ORIGINAL-SCIAT-FAST-plot-source.json") and (evidence / "FAST-final-all-trials.csv").read_bytes() == (evidence / "ORIGINAL-SCIAT-FAST-all-trials.csv").read_bytes(), "Final wording render retains the complete original plot data and byte-identical numerical CSV")
    check(b"Grey = non-scoring block; square = unavailable" in (evidence / "FAST-final-chronology.svg").read_bytes(), "Final standalone chronology explicitly distinguishes block colour from scoring exclusion")
    check(len(result["carried_scans"]) == 12 and all(s["violations"] == 0 and not s["overflow"] for s in result["carried_scans"]), "Twelve carried scans remain attributed to their original accepted phase")
def entity(kind, identity):
    row = db.execute("SELECT v.* FROM entities e JOIN entity_versions v ON e.kind=v.kind AND e.id=v.id AND e.revision=v.revision WHERE e.kind=? AND e.id=?", (kind, identity)).fetchone()
    assert row and sha(row["body_json"].encode()) == row["body_hash"]
    return json.loads(row["body_json"])
def object_bytes(ref):
    data = (folder / "workspace/objects/sha256" / ref["hash"][:2] / ref["hash"]).read_bytes()
    assert sha(data) == ref["hash"]
    return data
def report(identity):
    body = entity("report", identity)
    envelope = json.loads(object_bytes(body["result_object"]))
    assert envelope["report"] == {k:v for k,v in body.items() if k != "result_object"}
    return body
scores = {}
for alias, run_id in journey["runs"].items():
    run = db.execute("SELECT * FROM delivery_runs WHERE id=?", (run_id,)).fetchone()
    rows = db.execute("SELECT * FROM delivery_events WHERE run_id=? ORDER BY sequence", (run_id,)).fetchall()
    protocol = json.loads(run["protocol_json"])
    events = [json.loads(row["event_json"]) for row in rows]
    raw = ("[" + ",".join(row["event_json"] for row in rows) + "]").encode()
    check(run["completion_status"] == "completed" and run["transfer_status"] == "saved", f"{alias}: actual completed saved ending")
    check(len(rows) == run["acked_sequence"] and [r["sequence"] for r in rows] == list(range(1, len(rows)+1)), f"{alias}: complete contiguous journal without duplicate retry rows")
    check(sha(run["protocol_json"].encode()) == run["protocol_hash"] and all(sha(r["event_json"].encode()) == r["event_hash"] for r in rows), f"{alias}: every original protocol/event byte hash verifies")
    receipts = db.execute("SELECT * FROM delivery_receipts WHERE scope=?", (run_id,)).fetchall()
    check(sum(r["operation"] == "finish" for r in receipts) == 1, f"{alias}: one genuine finish receipt")
    browser_path = Path(journey["browser_evidence"][alias]).resolve()
    assert browser_path.parent.parent == folder
    browser = json.loads(browser_path.read_text(encoding="utf-8"))
    check(browser["records"]==[], f"{alias}: browser journal is cleared after actual confirmed saved completion")
    receipt_ids = {r["operation_id"] for r in receipts if r["operation"]=="events"}
    check(browser["traffic"] and all(t["operation_id"] in receipt_ids for t in browser["traffic"]), f"{alias}: retained network operations belong to the exact received session")
    if "before_finish" in browser:
        local = next(r for r in browser["before_finish"] if r["run_id"]==run_id)
        check(local["events"]==events[:len(local["events"])] and sum(e["type"]=="task_event" and e["payload"]["kind"]=="task_trial_finished" for e in local["events"])==192, f"{alias}: pre-finish browser journal independently retains all192 exact task outcomes")
    if alias.endswith("001"):
        operations = {}
        repeated = False
        for request in browser["traffic"]:
            if request["operation_id"] in operations:
                assert operations[request["operation_id"]] == request["hash"]
                repeated = True
            operations[request["operation_id"]] = request["hash"]
        check(browser["lost_ack"] and repeated, "An actually received request lost its acknowledgement and retried exact operation bytes")
    compiled = next(s["task"] for s in protocol["timeline"] if s["type"] == "task")
    trials = [t for t in compiled["timeline"] if t["type"] == "task_trial"]
    finished = [e["payload"]["data"] for e in events if e["type"] == "task_event" and e["payload"]["kind"] == "task_trial_finished"]
    check(len(trials) == len(finished) == 192 and [r["trial_id"] for r in finished] == [t["id"] for t in trials], f"{alias}: all192 original frozen positions received in order")
    blocks = []
    for t in trials:
        if not blocks or blocks[-1][0] != t["block_id"]: blocks.append([t["block_id"], t["mapping"], 0])
        blocks[-1][2] += 1
    initial = "A" if protocol["allocation_index"] % 2 else "B"
    check([b[2] for b in blocks] == [24,72,24,72] and [b[1] for b in blocks] == [initial,initial,"B" if initial=="A" else "A","B" if initial=="A" else "A"], f"{alias}: exact opposite-order24/72/24/72 allocation")
    for t, r in zip(trials, finished):
        accepted = [k for k in r["keys"] if k["accepted"]]
        if r["outcome"] == "omission":
            assert not accepted and all(r[x] is None for x in ("response_code","response_ms","correct"))
        else:
            assert len(accepted) == 1
            k = accepted[0]
            assert k["trusted"] and not k["repeat"] and not k["modifiers"] and k["type"] == "down"
            assert k["code"] == r["response_code"] and r["correct"] == (k["code"] == t["correct_code"])
            assert close(k["event_ms"]-r["onset_ms"], r["response_ms"]) and 0 <= r["response_ms"] <= 1500
    check(True, f"{alias}: every first response independently binds its accepted key, event timestamp, accuracy and inclusive deadline")
    test = [(t,r) for t,r in zip(trials,finished) if t["scored"]]
    kept = [(t,r) for t,r in test if r["outcome"] == "response" and r["response_ms"] >= 350]
    correct = [F(str(r["response_ms"])) for t,r in kept if r["correct"]]
    mean_correct = avg(correct)
    sd = math.sqrt(float(sum((x-mean_correct)**2 for x in correct) / (len(correct)-1)))
    means = {}
    for mapping in ("A","B"):
        selected = [r for t,r in kept if t["mapping"] == mapping]
        base = avg([F(str(r["response_ms"])) for r in selected])
        means[mapping] = avg([F(str(r["response_ms"])) if r["correct"] else base+400 for r in selected])
    expected = float(means["B"]-means["A"])/sd
    scores[alias] = expected
    native = report(journey["native_reports"][alias])
    s = native["analysis"]["task_scores"][0]
    check(len(test)==144 and s["counts"]["practice"]==48 and s["counts"]["retained"]==len(kept), f"{alias}: independent practice exclusions and response support agree")
    if alias == "ORIGINAL-SCIAT-EDGE":
        check(s["counts"]["scored_timeouts"]==1 and s["counts"]["removed_fast"]==0 and s["counts"]["retained"]==143, "Actual omission administration preserves its missing response without reclassifying a response at or above350ms as fast")
        absent = [r for r in s["scoring_audit"]["rows"] if r["reason"]=="explicit_omission"]
        check(len(absent)==1 and absent[0]["latency_ms"] is None and absent[0]["correct"] is None and absent[0]["scoring_latency_ms"] is None, "Published omission audit uses explicit null for missing observations and scoring values")
    if alias == "ORIGINAL-SCIAT-FAST":
        check(s["counts"]["scored_timeouts"]==0 and s["counts"]["removed_fast"]==1 and s["counts"]["retained"]==143, "Actual fast administration excludes exactly its observed below350ms test response")
        fast = [r for r in s["scoring_audit"]["rows"] if r["reason"]=="below_350_ms"]
        check(len(fast)==1 and fast[0]["latency_ms"]<350 and fast[0]["scoring_latency_ms"] is None, "Published fast audit preserves raw observed latency and null excluded scoring value")
    check(close(expected,s["metrics"][0]["value"]) and close(sd,s["scoring_audit"]["pooled_correct_sample_sd_ms"]), f"{alias}: Fraction-based error replacement, original-correct N-1 SD and signed D agree")
    check(native == read(f"{alias}-report.json"), f"{alias}: downloaded native report equals independently hashed catalog/envelope")
    check(native["provenance"]["runs"][0]["events_hash"] == sha(raw), f"{alias}: native report pins complete original received journal")
    check(any(o["value"] == (4 if alias.endswith("001") else 5) for o in native["analysis"]["observations"]), f"{alias}: separate explicit liking retained without replacing implicit score")
    plots = read(f"{alias}-plot-source.json")
    plotted = plots["selected_rows"]
    check(len(plotted)==192 and all(p["trial_id"]==t["id"] and p["first_response_ms"]==r["response_ms"] and p["final_correct_ms"]==(r["response_ms"] if r["correct"] else None) for p,t,r in zip(plotted,trials,finished)), f"{alias}: complete plot keeps raw first latencies and no invented corrected error response")
    exported = csv_rows(f"{alias}-native-trials.csv")
    check(len(exported)==192 and all(x["trial_id"]==t["id"] and x["participant_id"]==alias and (x["first_response_ms"]=="" if r["response_ms"] is None else close(float(x["first_response_ms"]),r["response_ms"])) and (x["final_correct_ms"]!="")==bool(r["correct"]) for x,t,r in zip(exported,trials,finished)), f"{alias}: native CSV all192 rows preserve missingness, identity and first-correct aliases")
    imported = report(journey["imports"][alias]["report_id"])
    a = imported["analysis"]["task_attempts"][0]
    check(imported == read(f"{alias}-imported-report.json") and close(a["score"]["metrics"][0]["value"],expected), f"{alias}: actual imported report independently reproduces arithmetic")
    check(a["evidence_level"]=="declared_trial_summary" and not a["timing_quality"]["journal_replayed"] and not a["timing_quality"]["physical_timing_qualified"], f"{alias}: import never inherits native replay or physical qualification")
    check(a["source"]["original_hash"]==sha((evidence/f"{alias}-native-trials.csv").read_bytes()) and a["source"]["registry_object_hash"]==sha((evidence/f"{alias}-native-registry.json").read_bytes()), f"{alias}: imported dataset pins actual downloaded CSV and registry bytes")
    check(len(csv_rows(f"{alias}-all-trials.csv"))==192 and b"<svg" in (evidence/f"{alias}-chronology.svg").read_bytes(), f"{alias}: complete numerical CSV and standalone chronology SVG retained")
partial = db.execute("SELECT * FROM delivery_runs WHERE participant_alias='ORIGINAL-SCIAT-REFRESH'").fetchone()
check(partial["completion_status"]=="interrupted", "Actual refresh remains a separate interrupted administration")
cohort = report(journey["cohort_id"])
a = cohort["analysis"]
summary = next(s for s in a["summaries"] if s["metric"]=="SCIAT_target_positive_D")
check(cohort==read("cohort-report.json") and summary["contributing_person_count"]==2 and summary["selected_attempt_count"]==2 and close(summary["mean"],(scores["ORIGINAL-SCIAT-001"]+scores["ORIGINAL-SCIAT-002"])/2), "Reviewed cohort has exactly its two selected people/administrations and their equal-person mean; the later edge administration is not silently added")
check(len(read("cohort-plot-source.json")["selected_rows"])==len(csv_rows("cohort-people.csv"))==2, "Cohort plot/CSV retain exactly both complete person-level records")
check(read("before-reopen.json")["sessions"]==read("final-snapshot.json")["sessions"] and read("before-reopen.json")["reports"]==read("final-snapshot.json")["reports"], "Restart/reopen changed neither received sessions nor published reports")
jobs = [dict(j) for j in db.execute("SELECT operation,status,attempt FROM jobs ORDER BY created_at,id")]
check(all(j["status"]=="succeeded" and j["attempt"]==1 for j in jobs), "Every actual queued job is explicitly accounted for at successful attempt one")
check(len(jobs)==13 and sum(j["operation"]=="analyse_run" for j in jobs)==4 and sum(j["operation"]=="ingest_source" for j in jobs)==4 and sum(j["operation"]=="analyse_dataset" for j in jobs)==4 and sum(j["operation"]=="analyse_task_cohort" for j in jobs)==1, "Exactly four native analyses, four actual source intakes, four summary imports and one cohort calculation; no original rescoring")
check(all(s["violations"]==0 and not s["overflow"] for s in result["scans"]), "Accepted current journey scans contain no automated WCAG violations or viewport overflow")
db.close()
(evidence/"independent-source-audit.json").write_text(json.dumps({"passed":True,"checks":checks,"scores":scores,"jobs":jobs},indent=2),encoding="utf-8")
print(json.dumps({"passed":True,"checks":len(checks),"evidence":str(evidence)}))
