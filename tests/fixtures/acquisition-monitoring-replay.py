"""Feed original generated samples through the actual durable writer for R/UI QA."""
import importlib.util
import json
from pathlib import Path
import sys

spec = importlib.util.spec_from_file_location("original_recorder", "scripts/acquisition/lsl_recorder.py")
recorder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(recorder)
cases = json.loads(Path(sys.argv[1]).read_text())
output = Path(sys.argv[2])
output.mkdir()
results = []
for case in cases:
    request = case["request"]
    request["output_root"] = str(output)
    recorder.validate_request(request)
    directory = output / request["recording_id"]
    directory.mkdir()
    (directory / "chunks").mkdir()
    writer = recorder.Writer(directory, request, {"engine": {"script_sha256": recorder.file_sha(spec.origin)}, "streams": []})
    selected = request["streams"][0]
    writer.monitor[selected["id"]]["connection"] = "subscribed"
    for chunk in case["chunks"]:
        values = [[float(value["nonfinite"]) if isinstance(value, dict) and "nonfinite" in value else value
                   for value in row] for row in chunk["values"]]
        writer.chunk(selected, values, chunk["stamps"], 100.0, 100.1, reset=chunk.get("reset", False))
    live = recorder.load(directory / "status.json", 2*1024**2)
    writer.finish("completed", "original_software_replay")
    inspection = recorder.inspect_recording(directory)
    results.append({"id": case["id"], "request": request, "live": live,
                    "closed": recorder.load(directory / "status.json", 2*1024**2),
                    "inspection": inspection, "directory": str(directory)})
(output / "results.json").write_bytes(recorder.encoded(results))
