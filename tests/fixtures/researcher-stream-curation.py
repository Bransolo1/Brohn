"""Original independent consumer-research transport fixture; no physical recordings."""
import json
import math
import sys
from pathlib import Path

directory = Path(sys.argv[1])
directory.mkdir(parents=True, exist_ok=True)
samples = []
for part in range(2):
    for index in range(800):
        amplitude, frequency = (8, 6) if part == 0 else (12, 12)
        value = amplitude * math.sin(2 * math.pi * frequency * index / 100)
        row = {"timestamp": str((9007199254741013 if part == 0 else 2000) + index * 10000000),
               "values": [None if part == 1 and index == 400 else value,
                          None if part == 0 and index == 100 else 2.5]}
        if part == 1 and index == 0:
            row["reset"] = True
        samples.append(row)

clock = {"id": "original-ui-clock", "unit": "ns", "kind": "device", "representation": "decimal_string"}
channels = [{"id": "scalp", "label": "Original scalp signal", "type": "EEG", "unit": "uV", "value_type": "float64"},
            {"id": "unused", "label": "Unselected auxiliary", "type": "EEG", "unit": "uV", "value_type": "float64"}]
regular = {"id": "original-curation-eeg", "name": "Original 6 then12 Hz scalp signal", "type": "EEG", "kind": "signal",
           "source_id": "original-curation-generator", "uid": "original-curation-uid", "clock": clock,
           "nominal_srate": 100, "identity": {"participant_id": "ORIGINAL-C001", "session_id": "ORIGINAL-V001"},
           "channels": channels, "samples": samples}
missing = {**regular, "id": "original-curation-missing", "name": "Original all-missing scalp", "uid": "original-missing-uid",
           "channels": [channels[0]], "samples": [{"timestamp": str(i * 10000000), "values": [None]} for i in range(20)]}
marker = {**regular, "id": "original-curation-marker", "name": "Original explicit markers", "kind": "markers", "type": "Markers",
          "uid": "original-marker-uid", "nominal_srate": 0,
          "channels": [{"id": "condition", "label": "Original condition label", "type": "event", "unit": None, "value_type": "string"}],
          "samples": [{"timestamp": "1000", "values": ["control"]}, {"timestamp": "2000", "values": ["test"]}]}
bundle = {"schema": "brohn-stream-bundle/1.0", "origin": "sample", "streams": [regular, missing, marker]}
(directory / "original-segmented-signals.json").write_text(json.dumps(bundle, allow_nan=False), encoding="utf-8")
(directory / "oracle.json").write_text(json.dumps({"source_rows": 1600, "included_rows": 1599, "excluded_sequence": 1201,
    "segment_rows": [800, 400, 399], "peak_hz": [6, 12], "power_uv2": [32, 72],
    "first_timestamp": "9007199254741013", "reset_timestamp": "2000"}), encoding="utf-8")
