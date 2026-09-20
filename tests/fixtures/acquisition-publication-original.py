"""Original synthetic source created by the production journal writer, without hardware."""
import importlib.util
import json
import os
from pathlib import Path
import sys
import time

spec = importlib.util.spec_from_file_location("original_recorder", "scripts/acquisition/lsl_recorder.py")
recorder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(recorder)
request_path, ready, release, padding = sys.argv[1:]
request = recorder.validate_request(json.loads(Path(request_path).read_text()))
root = Path(request["output_root"]) / request["recording_id"]
root.mkdir()
(root / "chunks").mkdir()
selected = request["streams"][0]
evidence = {"engine": {"script_sha256": recorder.file_sha(spec.origin), "fixture": "original-synthetic-journal"},
            "streams": [{"id": selected["id"], "declared": selected, "observed": {
                "name": "Original synthetic publication source", "type": "EDA", "nominal_srate": 10,
                "source_origin": "synthetic"}}]}
writer = recorder.Writer(root, request, evidence)
writer.chunk(selected, [[1.0], [2.0], [3.0]], [10.0, 10.1, 10.2], 20.0, 20.1)
writer.finish("completed", "original_synthetic_fixture")
# Incidental original diagnostic bytes exercise the whole-source archive path;
# they are explicitly not sensor samples or imported measurement values.
if int(padding):
    with (root / "original-diagnostic.bin").open("xb") as stream:
        for _ in range(int(padding)):
            stream.write(os.urandom(1024 * 1024))
Path(ready).write_text("source complete; awaiting test-owned release")
while not Path(release).exists():
    time.sleep(.01)
