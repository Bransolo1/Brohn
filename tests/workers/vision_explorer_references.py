"""Opt-in reader agreement against actual pinned model outputs retained in work/."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("vision_explorer", ROOT / "scripts/workers/vision_explorer.py")
v = importlib.util.module_from_spec(spec); spec.loader.exec_module(v)


def main():
    p = argparse.ArgumentParser(); p.add_argument("--references", required=True); p.add_argument("--folder", required=True); args = p.parse_args()
    references = Path(args.references); output = Path(args.folder); assert not output.exists(); output.mkdir(parents=True)
    source_manifest = json.loads((references / "reference-manifest.json").read_bytes()); checks = []; cases = {}
    for family in ("face", "pose", "hands"):
        result = json.loads(Path(source_manifest["cases"][family]["result_path"]).read_bytes())
        artifact = next(x for x in result["artifacts"] if x["kind"] == "vision-observations")
        original_lines = Path(artifact["path"]).read_bytes().decode("utf-8").splitlines(keepends=True)
        original = [json.loads(line, parse_int=str, parse_float=str) for line in original_lines]
        assert len(original) == 4 and result["quality"]["channels"][family]["valid_frames"] == 4
        binding = v.encoded({"original_video": result["source"], "original_artifact": artifact["sha256"], "model": result["engine"], "qualification": "official static reference, no accuracy inference"}).decode()
        request = {"artifact_path": artifact["path"], "artifact": {"sha256": artifact["sha256"], "bytes": artifact["bytes"]},
                   "index_path": str(output / (family + ".sqlite")), "binding_json": binding, "binding_sha256": v.sha(binding.encode()),
                   "parameters": result["parameters"], "quality": result["quality"], "engine": result["engine"]}
        indexed = v.build(request); query = {"index_path": request["index_path"], "index": indexed["index"], "binding_sha256": request["binding_sha256"]}
        assert indexed["manifest"]["frames"] == len(original)
        assert indexed["manifest"]["channels"][family] == {k: result["quality"]["channels"][family][k] for k in ("states", "valid_frames")}
        for row, raw in zip(original, original_lines):
            detail = v.detail(dict(query, artifact_path=artifact["path"], frame_index=int(row["frame_index"])))
            assert detail["original_json"] == raw and detail["observation"] == row
            assert detail["frame"]["source_pts_s"] == row["source_pts_s"]
        checks.append(f"{family}: complete original frame, PTS, native landmark tokens and saved states match actual inference")
        for metric in indexed["manifest"]["metrics"]:
            name = metric["id"]; page = v.page(dict(query, metric=name)); assert page["total"] == 4
            for row, shown in zip(original, page["rows"]):
                parts = name.split(".")
                if family == "face":
                    expected = row[family]["blendshapes"][parts[2]] if parts[1] == "blendshape" else row[family]["geometry"][parts[1]]
                elif family == "pose": expected = row[family]["geometry"][parts[1]]
                else:
                    selected = [hand for hand in row[family]["hands"] if hand["handedness"] == parts[1] and hand["summary_valid"]]
                    expected = selected[0]["geometry"][parts[2]] if len(selected) == 1 else None
                assert shown["value_text"] == expected, (name, shown["value_text"], expected)
        checks.append(f"{family}: every indexed metric token equals its native original field")
        cases[family] = {"index": indexed["index"], "metrics": len(indexed["manifest"]["metrics"]), "frames": len(original), "engine": result["engine"]}
    receipt = {"checks": checks, "cases": cases, "reference_manifest_sha256": hashlib.sha256((references / "reference-manifest.json").read_bytes()).hexdigest(),
               "worker_sha256": v.digest(ROOT / "scripts/workers/vision_explorer.py"), "qualification": "Actual pinned inference and exact saved artifact agreement; not model or physical measurement accuracy"}
    (output / "results.json").write_text(json.dumps(receipt, indent=2), encoding="utf-8")
    print("PASS", len(checks), "actual reference reader checks")


if __name__ == "__main__": main()
