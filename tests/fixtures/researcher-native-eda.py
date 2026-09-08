"""Original source bytes and independent arithmetic for browser QA; no devices."""
import csv
import hashlib
import json
import math
from pathlib import Path
import struct
import sys


def edf(missing_unit=False):
    def field(value, size):
        encoded = str(value).encode("ascii")
        assert len(encoded) <= size
        return encoded.ljust(size, b" ")

    channels = {
        "label": ["Cz", "ECG", "EDF Annotations"],
        "transducer": ["Original synthetic EEG", "Original synthetic ECG", ""],
        "unit": ["" if missing_unit else "uV", "mV", ""],
        "physical_min": [-100, -10, -1], "physical_max": [100, 10, 1],
        "digital_min": [-32768] * 3, "digital_max": [32767] * 3,
        "prefilter": ["None", "None", ""],
        "samples": [100, 50, 128], "reserved": ["", "", ""],
    }
    header = b"0       " + field("PRIVATE SYNTHETIC PERSON", 80) + field("PRIVATE SYNTHETIC RECORDING", 80)
    header += field("01.01.01", 8) + field("01.02.03", 8) + field(1024, 8) + field("EDF+C", 44)
    header += field(32, 8) + field(1, 8) + field(3, 4)
    for key, size in (("label", 16), ("transducer", 80), ("unit", 8), ("physical_min", 8),
                      ("physical_max", 8), ("digital_min", 8), ("digital_max", 8),
                      ("prefilter", 80), ("samples", 8), ("reserved", 32)):
        header += b"".join(field(value, size) for value in channels[key])
    actual_uv = []
    body = bytearray()
    for second in range(32):
        digital = []
        for sample in range(100):
            uv = 20 * math.sin(2 * math.pi * 10 * (second + sample / 100))
            tick = round((uv + 100) * 65535 / 200 - 32768)
            digital.append(tick)
            actual_uv.append((tick + 32768) * 200 / 65535 - 100)
        body += struct.pack("<100h", *digital) + struct.pack("<50h", *([0] * 50))
        annotation = f"+{second}\x14\x14\x00".encode()
        if second in (5, 15):
            annotation += f"+{second}.25\x150.5\x14{'control' if second == 5 else 'test'}\x14\x00".encode()
        body += annotation.ljust(256, b"\x00")
    return header + body, math.sqrt(sum(x * x for x in actual_uv) / len(actual_uv))


def generate(root):
    root.mkdir(parents=True, exist_ok=True)
    native, rms = edf()
    (root / "original-native.edf").write_bytes(native)
    (root / "missing-unit.edf").write_bytes(edf(True)[0])
    (root / "truncated-native.edf").write_bytes(native[:-1])
    events = [(20, "A", "complete"), (50, "A", "overlap-a"), (54, "B", "overlap-b"), (115, "B", "edge")]
    by_sample = {round(t * 25): (code, exposure) for t, code, exposure in events}
    with (root / "original-continuous-eda.csv").open("w", newline="", encoding="utf-8") as out:
        writer = csv.writer(out)
        writer.writerow(["time", "participant", "session", "conductance", "onset", "exposure"])
        for sample in range(3000):
            writer.writerow([sample / 25, "SYNTHETIC-P1", "SYNTHETIC-S1", 5, *by_sample.get(sample, ("", ""))])
    event_csv = "time_s,code,exposure_id,recording_id\n" + "\n".join(f"{t},{code},{exposure},recording-1" for t, code, exposure in events)
    (root / "measured-events.csv").write_text(event_csv, encoding="utf-8")
    expected = {"origin": "original_synthetic", "native_sha256": hashlib.sha256(native).hexdigest(),
                "native_channels": ["Cz", "ECG"], "native_rates_hz": [100, 50], "native_units": ["uV", "mV"],
                "native_duration_s": 32, "eeg_peak_hz": 10, "eeg_quantized_rms_uv": rms,
                "eda_baseline_us": 5, "eda_response_us": 5, "eda_change_us": 0,
                "eda_complete_exposure": "complete", "eda_overlap_exposures": ["overlap-a", "overlap-b"],
                "eda_unsupported_exposure": "edge", "eda_source_samples": 3000}
    (root / "expected.json").write_text(json.dumps(expected, indent=2), encoding="utf-8")


if __name__ == "__main__":
    generate(Path(sys.argv[1]))
