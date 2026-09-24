"""Observed queue-to-terminal timestamps, separate from browser responsiveness."""
import datetime as dt
import json
from pathlib import Path
import statistics
import sys

folder = Path(sys.argv[1]).resolve()
receipt = json.loads((folder / "population-results.json").read_text(encoding="utf-8"))
assert receipt["passed"] and len(receipt["new_media_jobs"]) == 42
parse = lambda value: dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
rows = []
for job in receipt["new_media_jobs"]:
    assert job["status"] == "succeeded" and job["attempt"] == 1
    seconds = (parse(job["updated_at"]) - parse(job["created_at"])).total_seconds()
    assert seconds >= 0
    rows.append({"id": job["id"], "cursor_sample": job["request"]["selection"]["cursor_sample"],
                 "created_at": job["created_at"], "terminal_updated_at": job["updated_at"],
                 "queued_to_terminal_seconds": seconds})
values = [row["queued_to_terminal_seconds"] for row in rows]
out = {"scope": "Observed sequential actual saved-media cursor jobs on the copied64x48/160-frame/8kHz fixture. No maximum-load or general hardware claim.",
       "definition": "Terminal updated_at minus queue created_at; excludes source preparation/input validation before queue creation and browser navigation.",
       "count": len(rows), "summary_seconds": {"min": min(values), "median": statistics.median(values),
       "mean": statistics.mean(values), "max": max(values)}, "jobs": rows}
(folder / "preparation-timings.json").write_text(json.dumps(out, indent=2), encoding="utf-8")
print(json.dumps(out["summary_seconds"]))
