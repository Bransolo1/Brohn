"""Read-only independent audit of a retained native-width resource run.

Run vision_explorer_limits.py --case native-width --reuse-request first. This
does not generate/copy source observations or rebuild the index. It reads the
complete original stream once to verify count/hash, then checks saved index
counts and exact detail/plot responses against the known synthetic fixture.
"""
import argparse
from decimal import Decimal
import hashlib
import importlib.util
import json
from pathlib import Path
import sqlite3


ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--folder", required=True)
    parser.add_argument("--expected-worker-sha256", required=True)
    args = parser.parse_args()
    folder = Path(args.folder).resolve()
    output = folder / "source-exactness-review.json"
    assert not output.exists(), "Preserve the previous evidence; use a fresh audit destination."
    request = json.loads((folder / "request.json").read_bytes())
    result = json.loads((folder / "worker-result.json").read_bytes())
    limits = json.loads((folder / "limits-evidence.json").read_bytes())
    memory = json.loads((folder / "actual-runtime-memory.json").read_bytes())
    checks = []

    def check(condition, label):
        assert condition, label
        checks.append(label)

    worker = ROOT / "scripts/workers/vision_explorer.py"
    worker_hash = hashlib.sha256(worker.read_bytes()).hexdigest()
    check(worker_hash == args.expected_worker_sha256 == limits["worker_sha256"],
          "Executed and current worker hashes match the explicit frozen implementation")
    check(limits["worker_exit"] == 0 and result["status"] == "complete", "Actual worker completed successfully")
    check(memory["scope"] == "actual Python interpreter, Win32 lifetime peaks" and
          0 < memory["peak_working_set_bytes"] == limits["peak_working_set_bytes"] < 192 * 1024**2 and
          0 < memory["peak_commit_bytes"] == limits["peak_commit_bytes"] < 192 * 1024**2,
          "Actual-interpreter Win32 lifetime peak receipt matches the successful run and both 192 MiB bounds")

    source = Path(request["artifact_path"])
    digest = hashlib.sha256()
    count = 0
    last = None
    with source.open("rb") as stream:
        for last in stream:
            digest.update(last)
            count += 1
    check(count == 36000 and source.stat().st_size == 2140382779,
          "Independent complete original-stream scan confirms all 36000 frames and 2140382779 bytes")
    check(digest.hexdigest() == request["artifact"]["sha256"] == limits["source_hash"] ==
          "6cbd6c0d7b796595e96ba0d2377a8cde69109e2e3034d08617679d40badeb01e",
          "Original source remains byte-identical to the historical retained fixture after the current worker")

    index = Path(request["index_path"])
    check(index.parent == folder and source.parent != folder and not (folder / "complete.jsonl").exists(),
          "Only a new derived index is local to this run; the large original was reused without copying")
    with sqlite3.connect(index.resolve().as_uri() + "?mode=ro&immutable=1", uri=True) as con:
        check(con.execute("SELECT count(*),min(frame_index),max(frame_index) FROM frames").fetchone() ==
              (36000, 0, 35999), "Independent SQLite query confirms complete ordered frame coverage")
        check(con.execute("SELECT count(*),count(DISTINCT metric) FROM metric_values").fetchone() ==
              (36000 * 58, 58), "Independent SQLite query confirms all 58 native metrics across every frame")
    check(result["manifest"]["frames"] == 36000 and len(result["manifest"]["metrics"]) == 58 and
          index.stat().st_size == result["index"]["bytes"] == limits["index_bytes"] < 256 * 1024**2,
          "Complete saved manifest and derived-index byte count agree within the 256 MiB cap")

    spec = importlib.util.spec_from_file_location("vision_resource_review", worker)
    v = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(v)
    query = {"index_path": str(index), "index": result["index"], "binding_sha256": request["binding_sha256"],
             "metric": "face.blendshape.native000", "channel": "face"}
    detail = v.detail(dict(query, artifact_path=str(source), frame_index=35999))
    check(detail["original_json"].encode("utf-8") == last,
          "Last-frame native JSON exactly matches the independent complete-stream final line")
    original_tokens = json.loads(last, parse_float=str, parse_int=str)
    check(detail["observation"] == original_tokens,
          "All last-frame native numeric token strings and original booleans/types are preserved")
    origin = Decimal("9007199254740992.0000")
    check(detail["frame"]["frame_index"] == 35999 and
          detail["frame"]["source_pts_s"] == "9007199254741351.9900" and
          Decimal(detail["frame"]["relative_exact_text"]) == Decimal("359.99") and
          Decimal(detail["frame"]["time_s_text"]) == Decimal("359.99") and
          detail["frame"]["model_timestamp_ms"] == 359990,
          "Independent final-frame timing oracle survives a PTS origin above binary64 exact integer range")
    check(len(original_tokens["face"]["landmarks"]) == 478 and len(original_tokens["pose"]["landmarks"]) == 33 and
          [len(hand["landmarks"]) for hand in original_tokens["hands"]["hands"]] == [21, 21] and
          original_tokens["face"]["blendshapes"]["native000"] == "0.25" and
          Decimal(original_tokens["face"]["landmarks"][0]["z"]) == Decimal("-.125"),
          "Final native frame retains the known face/pose/two-hand landmark counts and exact synthetic values")
    plot = v.plot(query)
    points = [point for fragment in plot["fragments"] for point in fragment["points"]]
    check(plot["support"]["frames"] == plot["support"]["channel_valid_frames"] ==
          plot["support"]["metric_valid_frames"] == 36000 and
          Decimal(plot["support"]["metric_valid_time_s_text"]) == Decimal("359.99") and
          plot["support"]["state_counts"] == {"single": 36000},
          "Plot denominators and adjacent-interval support match all 36000 frames without terminal extrapolation")
    check(len(plot["fragments"]) == 1 and plot["fragments"][0]["complete_points"] == 36000 and
          0 < len(points) == plot["support"]["displayed_points"] <= 2000 and
          points[0]["frame_index"] == 0 and points[-1]["frame_index"] == 35999,
          "Bounded display preserves both source endpoints and discloses complete versus displayed counts")
    check(all(point["value_text"] == "0.25" and point["y"] == .25 and
              Decimal(point["relative_exact_text"]) == Decimal(point["frame_index"]) / 100 and
              Decimal(point["source_pts_s"]) == origin + Decimal(point["frame_index"]) / 100
              for point in points),
          "Every displayed point retains independently expected original metric and exact source timing values")
    detail_bytes = v.encoded(detail)
    plot_bytes = v.encoded(plot)
    check(len(detail_bytes) <= 2 * 1024**2 and len(plot_bytes) <= 2 * 1024**2,
          "Complete final-frame detail and bounded plot fit the explicit 2 MiB response cap")
    (folder / "last-frame-detail.json").write_bytes(detail_bytes)
    (folder / "complete-plot.json").write_bytes(plot_bytes)
    receipt = {"checks": checks, "worker_sha256": worker_hash, "source_sha256_after": digest.hexdigest(),
               "source_frames": count, "source_bytes": source.stat().st_size, "index_bytes": index.stat().st_size,
               "metric_values": 36000 * 58, "plot_displayed_points": len(points),
               "plot_response_bytes": len(plot_bytes), "last_frame_response_bytes": len(detail_bytes),
               "peak_working_set_bytes": memory["peak_working_set_bytes"], "peak_commit_bytes": memory["peak_commit_bytes"],
               "memory_scope": memory["scope"], "scope": "Synthetic maximum accepted frame count and near-maximum source size at 58 native metrics; no inference or device/model qualification"}
    output.write_text(json.dumps(receipt, indent=2), encoding="utf-8")
    print(json.dumps(receipt, indent=2))


if __name__ == "__main__":
    main()
