"""Original browser EEG fixtures and independent arithmetic; no device claims."""
import csv
import hashlib
import json
import math
from pathlib import Path
import struct
import sys


def generate(root):
    root.mkdir(parents=True, exist_ok=True)
    fs, seconds, onsets = 100, 18, [3, 8, 13]
    def field(value, width):
        raw = str(value).encode("ascii")
        assert len(raw) <= width
        return raw.ljust(width, b" ")
    # Exact identity calibration: one signed int16 count is one physical uV.
    # The entire fixture is authored here, without borrowing recording bytes.
    header = b"0       " + field("ORIGINAL SYNTHETIC", 80) + field("ORIGINAL PULSE FIXTURE", 80)
    header += field("01.01.01", 8) + field("00.00.00", 8) + field(768, 8) + field("", 44)
    header += field(seconds, 8) + field(1, 8) + field(2, 4)
    values = [[5 + (10 if any(onset+.2 <= i/fs < onset+.4 for onset in onsets) else 0) for i in range(fs*seconds)],
              [7 + (20 if any(onset+.2 <= i/fs < onset+.4 for onset in onsets) else 0) for i in range(fs*seconds)]]
    specs = [(16, ["Cz", "Pz"]), (80, ["Original generated voltage"]*2), (8, ["uV"]*2),
             (8, [-32768]*2), (8, [32767]*2), (8, [-32768]*2), (8, [32767]*2),
             (80, ["None"]*2), (8, [fs]*2), (32, [""]*2)]
    for width, entries in specs:
        header += b"".join(field(value, width) for value in entries)
    body = b"".join(struct.pack("<100h", *channel[second*fs:(second+1)*fs])
                    for second in range(seconds) for channel in values)
    (root / "original-pulse.edf").write_bytes(header+body)
    for name in ["morlet", "tagging"]:
        with (root / (name+".csv")).open("w", newline="", encoding="utf-8") as stream:
            writer = csv.writer(stream)
            writer.writerow(["time", "participant", "session", "Cz", "Pz"])
            for i in range(fs*seconds):
                time = i/fs
                value = 20*math.sin(2*math.pi*10*time)
                if name == "tagging":
                    value += sum(2*math.sin(2*math.pi*f*time) for f in [8.5, 9, 11, 11.5])
                writer.writerow([repr(time), "ORIGINAL-P1", "ORIGINAL-S1", repr(value), 0])
    (root / "events.csv").write_text("time_s,code\n3,A\n8,A\n13,A", encoding="utf-8")
    oracle = {"origin": "original_synthetic", "sampling_rate": fs, "onsets": onsets,
              "erp_uv": {"Cz": 10, "Pz": 20}, "erp_trials": 3,
              "tag_target_hz": 10, "tag_density_uv2_hz": 400,
              "tag_noise_density_uv2_hz": 4, "tag_snr": 100,
              "zero_channel": "Pz", "hashes": {name: hashlib.sha256((root/name).read_bytes()).hexdigest()
                  for name in ["original-pulse.edf", "morlet.csv", "tagging.csv"]}}
    (root / "oracle.json").write_text(json.dumps(oracle, indent=2), encoding="utf-8")


if __name__ == "__main__":
    generate(Path(sys.argv[1]))
