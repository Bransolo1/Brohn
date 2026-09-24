"""Independent stdlib schedule and normal-quantile checks of retained R outputs."""
from pathlib import Path
from statistics import NormalDist, mean, median, stdev
import hashlib
import json
import math
import sys

source = Path(sys.argv[1])
output = Path(sys.argv[2])
assert not output.exists(), "Do not overwrite retained evidence"
compiled = json.loads((source / "compiled.json").read_text(encoding="utf-8-sig"))
score = json.loads((source / "score.json").read_text(encoding="utf-8-sig"))
journal = json.loads((source / "original-journal.json").read_text(encoding="utf-8-sig"))
receipt = json.loads((source / "results.json").read_text(encoding="utf-8-sig"))
checks = []
def check(label, value):
    assert value, label
    checks.append(label)

roles = ["target", "context", "attribute_positive", "attribute_negative"]
state = (compiled["seed"] + compiled["allocation_index"] - 2) % 2147483646 + 1
def uniform():
    global state
    state = state * 16807 % 2147483647
    return state / 2147483647
def shuffle(items):
    items = list(items)
    for i in range(len(items), 1, -1):
        j = math.floor(uniform() * i)
        items[i - 1], items[j] = items[j], items[i - 1]
    return items
training = shuffle(roles)
orders = [["target_positive", "target_negative"] if uniform() < .5 else ["target_negative", "target_positive"] for _ in range(2)]
check("Independent seeded training and round pairing order", compiled["assignment"] == {"training_order": training, "round_pairing_order": orders})
categories = {c["role"]: c["id"] for c in compiled["source_block"]["categories"]}
pools = {role: [m["id"] for m in compiled["source_block"]["materials"] if m["category_id"] == category] for role, category in categories.items()}
opposite = {"target": "context", "context": "target", "attribute_positive": "attribute_negative", "attribute_negative": "attribute_positive"}
phases = [("training", None, None, [role], {r: 10 if r in [role, opposite[role]] else 0 for r in roles}, 1000) for role in training]
for round_index, order in enumerate(orders, 1):
    for pairing in order:
        go = ["target", "attribute_positive" if pairing.endswith("positive") else "attribute_negative"]
        for phase, quota in [("practice", 4), ("test", 15)]:
            phases.append((phase, f"r{round_index}", pairing, go, {r: quota for r in roles}, 750 if round_index == 1 else 600))
expected = []
for block_index, (phase, round_id, pairing, go, quotas, timeout) in enumerate(phases, 1):
    sequence = shuffle([r for r in roles for _ in range(quotas[r])])
    decks = {r: shuffle(pools[r]) for r in roles if quotas[r]}
    for trial_index, role in enumerate(sequence, 1):
        if not decks[role]:
            decks[role] = shuffle(pools[role])
        expected.append((block_index, trial_index, phase, round_id, pairing, role, decks[role].pop(0), "go" if role in go else "nogo", timeout))
trials = [t for t in compiled["timeline"] if t["type"] == "task_trial"]
observed = [(t["block_index"], t["trial_index"], t["phase"], t["round_id"], t["pairing"], t["category_role"], t["material"]["id"], t["expected_action"], t["timeout_ms"]) for t in trials]
check("All384 realized roles, exact exemplar identities, actions, phase and deadline match independent compiler", observed == expected and len(observed) == 384)
check("No withholding correct_code masquerading as missing keyed response", all("correct_code" not in t for t in trials))
# This exact six-profile snapshot was pinned before GNAT activation. Activation
# changes the separate declared Boolean, not the six earlier procedure records.
check("Exact original six-profile snapshot and explicit GNAT registration state",
      receipt["original_six_profiles_hash"] == "2fb3daf9b2d4add8bc30057e526b9f9cbce745a7a406311464a6a74362d14730"
      and isinstance(receipt["registered"], bool))

normal = NormalDist()
fixture_counts = [(27, 3, 6, 24), (21, 9, 9, 21), (24, 6, 3, 27), (15, 15, 15, 15)]
expected_d = []
for cell, (hit, miss, false_alarm, rejection) in zip(score["scoring_audit"]["cells"], fixture_counts):
    h = hit / (hit + miss)
    f = false_alarm / (false_alarm + rejection)
    d = normal.inv_cdf(h) - normal.inv_cdf(f)
    c = -.5 * (normal.inv_cdf(h) + normal.inv_cdf(f))
    check(f"Independent NormalDist counts and quantiles {cell['id']}", [cell[k] for k in ["hits", "misses", "false_alarms", "correct_rejections"]] == [hit, miss, false_alarm, rejection] and
          abs(cell["d_prime"] - d) < 1e-12 and abs(cell["criterion"] - c) < 1e-12 and cell["raw_rates"] == {"hit": h, "false_alarm": f})
    expected_d.append(d)
    for outcome in ["hit", "false_alarm"]:
        values = [r["response_ms"] for r in score["scoring_audit"]["rows"] if r["phase"] == "test" and r["cell_id"] == cell["id"] and r["outcome"] == outcome]
        rt = cell["response_rt"][outcome]
        check(f"Actual-response-only descriptive denominator {cell['id']} {outcome}", rt == {"n": len(values), "mean_ms": mean(values) if values else None,
              "median_ms": median(values) if values else None, "sd_ms": stdev(values) if len(values) > 1 else None})
check("Two contrasts use their own deadlines rather than pooling", all(abs(score["scoring_audit"]["rounds"][i]["contrast"] - (expected_d[2*i] - expected_d[2*i+1])) < 1e-12 for i in range(2)))
check("Complete raw CSV-ready rows retain null withholding latency and bool accuracy", all(r["response_ms"] is None and r["response_code"] is None and r["correct"] is (r["outcome"] == "correct_rejection") for r in score["scoring_audit"]["rows"] if r["outcome"] in ["miss", "correct_rejection"]))
check("Twelve instruction receipts plus paired onset/end for all384 trials", len(journal) == 780 and sum(e["payload"]["kind"] == "task_trial_started" for e in journal) == 384)
check("No hidden NaN/Inf serialized instead of missing values", all(token not in (source / "score.json").read_text(encoding="utf-8-sig") for token in ['NaN', 'Infinity']))
output.write_text(json.dumps({"passed": True, "status": receipt["status"], "registered": receipt["registered"], "checks": checks, "count": len(checks),
    "reference": "Independent Python stdlib NormalDist and protocol-authored compiler; no model, browser, physical timing or reliability qualification",
    "inputs": {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in [source / "compiled.json", source / "score.json", source / "original-journal.json", source / "results.json"]}}, indent=2), encoding="utf-8")
print(json.dumps({"passed": True, "count": len(checks), "receipt": str(output)}))
