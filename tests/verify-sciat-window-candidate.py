"""Independent rational arithmetic oracle; no R, Brohn or reference package."""
from fractions import Fraction
import hashlib
import json
import math
from pathlib import Path
import sys

folder = Path(sys.argv[1]).resolve()
assert folder.name.startswith("brohn-sciat-window-candidate-")
receipt = json.loads((folder / "results.json").read_text(encoding="utf-8"))
checks = []


def check(ok, label):
    assert ok, label
    checks.append(label)


def near(a, b):
    return math.isclose(a, float(b), rel_tol=1e-12, abs_tol=1e-12)


check(receipt["passed"] and len(receipt["checks"]) == 44, "Executed candidate and independent package checks passed")
check(receipt["candidate"]["registered"] is False, "Prototype is explicitly unregistered")
for name, rows in receipt["cases"].items():
    observed = receipt["results"][name]
    kept = [r for r in rows if r["outcome"] == "response" and r["latency_ms"] >= 350]
    correct = [Fraction(str(r["latency_ms"])) for r in kept if r["correct"] is True]
    avg = sum(correct) / len(correct)
    variance = sum((x - avg) ** 2 for x in correct) / (len(correct) - 1)
    sd = math.sqrt(variance)
    means = {}
    adjusted_by_id = {}
    for mapping in ("A", "B"):
        subset = [r for r in kept if r["mapping"] == mapping]
        base = sum(Fraction(str(r["latency_ms"])) for r in subset) / len(subset)
        adjusted = [Fraction(str(r["latency_ms"])) if r["correct"] else base + 400 for r in subset]
        means[mapping] = sum(adjusted) / len(adjusted)
        adjusted_by_id.update({r["trial_id"]: a for r, a in zip(subset, adjusted)})
        check(near(observed["mapping"][mapping]["error_replacement_base_ms"], base)
              and near(observed["mapping"][mapping]["adjusted_mean_ms"], means[mapping]),
              f"{name}: mapping {mapping} original-error base and adjusted mean match exact rational arithmetic")
    display = float(means["B"] - means["A"]) / sd
    check(near(observed["pooled_correct_sample_sd_ms"], sd)
          and near(observed["target_positive_d"], display)
          and near(observed["reference_package_d"], -display),
          f"{name}: correct-only N-1 variance and both explicit directions match")
    check(all(out["latency_ms"] == row["latency_ms"] and out["correct"] == row["correct"]
              and (out["scoring_latency_ms"] is None if row["trial_id"] not in adjusted_by_id
                   else near(out["scoring_latency_ms"], adjusted_by_id[row["trial_id"]]))
              for out, row in zip(observed["rows"], rows)),
          f"{name}: original values and rowwise omission/replacement inputs remain separate")
    expected = {"presented": len(rows), "responded": sum(r["outcome"] == "response" for r in rows),
                "omitted": sum(r["outcome"] == "omission" for r in rows),
                "removed_fast": sum(r["outcome"] == "response" and r["latency_ms"] < 350 for r in rows),
                "retained": len(kept), "retained_correct": len(correct),
                "retained_errors": len(kept) - len(correct)}
    check(observed["counts"] == expected and observed["qualified_task_result"] is False,
          f"{name}: exact denominators agree without a collected-task qualification claim")
check(all(x["status"] == "unavailable" and x["target_positive_d"] is None
          for x in receipt["unavailable"].values()), "All insufficient-support examples remain unavailable")
check("differing number of rows" in receipt["reference"]["single_administration_mixed_fast_error"],
      "Actual single-administration external reference error is disclosed")
check(receipt["reference_outputs"]["all_correct"]["cond_ord"] == "MappingB_First"
      and receipt["results"]["all_correct"]["mapping_order"] == "A_then_B",
      "Reference order-label defect is recorded without changing actual order")
audit = {"passed": True, "checks": checks,
         "input_receipt_sha256": hashlib.sha256((folder / "results.json").read_bytes()).hexdigest(),
         "scope": "Independent arithmetic only; no participant or vendor-runtime qualification"}
(folder / "independent-arithmetic-audit.json").write_text(json.dumps(audit, indent=2), encoding="utf-8")
print(json.dumps({"passed": True, "checks": len(checks), "folder": str(folder)}))
