"""Original independent timing fixture; no device, person or natural signal."""
import copy
import json
from pathlib import Path
import sys

ANCHOR = 9007199254741013

def bundle():
    clock = {"id": "original-shared-generator-clock", "unit": "ns", "kind": "monotonic", "representation": "decimal_string"}
    identity = {"participant_id": "ORIGINAL-LINKED-01", "session_id": "ORIGINAL-VISIT-01"}
    def stream(id, name, channel, samples, kind="signal", selected_clock=None):
        return {"id": id, "name": name, "type": "Markers" if kind == "markers" else "Original test signal", "kind": kind,
                "source_id": id+"-source", "uid": id+"-uid", "clock": selected_clock or clock, "nominal_srate": 0 if kind == "markers" else 10,
                "identity": identity, "channels": [channel], "samples": samples}
    a = stream("original-conductance", "Original conductance with gap", {"id": "eda", "label": "Conductance", "type": "EDA", "unit": "uS", "value_type": "float64"},
               [{"timestamp": str(ANCHOR+i*100000000), "values": [None if i == 12 else i/10]} for i in range(81) if not 20 <= i <= 24])
    b = stream("original-voltage", "Original independent voltage", {"id": "voltage", "label": "Voltage", "type": "EEG", "unit": "uV", "value_type": "float64"},
               [{"timestamp": str(ANCHOR+i*100000000), "values": [100+i*2]} for i in range(81)])
    markers = stream("original-events", "Original stimulus events", {"id": "event", "label": "Stimulus/event marker", "type": "event", "unit": None, "value_type": "string"},
                     [{"timestamp": str(ANCHOR+500000000), "values": ["control stimulus onset"]},
                      {"timestamp": str(ANCHOR+1250000001), "values": ["candidate stimulus onset <script>not executable</script>"]},
                      {"timestamp": str(ANCHOR+3250000000), "values": ["candidate offset"]}], "markers")
    other = copy.deepcopy(b); other["id"] = "original-other-clock"; other["name"] = "Original incompatible clock"
    other["uid"] = "other-clock-uid"; other["clock"] = {**clock, "id": "unrelated-device-clock"}
    reset = copy.deepcopy(b); reset["id"] = "original-reset"; reset["name"] = "Original reset ambiguity"; reset["uid"] = "reset-clock-uid"
    reset["samples"][40] = {"timestamp": str(ANCHOR), "values": [999], "reset": True}
    return {"schema": "brohn-stream-bundle/1.0", "origin": "sample", "streams": [a, b, markers, other, reset]}

if __name__ == "__main__":
    target = Path(sys.argv[1]); target.mkdir(parents=True, exist_ok=True)
    (target/"original-linked-recording.json").write_text(json.dumps(bundle(), allow_nan=False), encoding="utf-8")
    (target/"oracle.json").write_text(json.dumps({"anchor": str(ANCHOR), "selected_0_4": [35, 40, 3], "total_0_4": 78,
        "selected_0_8": [75, 80, 3], "total_0_8": 158, "missing_0_4": [1, 0, 0], "exact_candidate_seconds": "1.250000001",
        "gap_first_sequence": 21, "post_gap_seconds": "2.5", "cursor_before_voltage": 124, "cursor_after_voltage": 126}), encoding="utf-8")
