"""Original synthetic multistream, irregular-clock, int64 and corruption fixtures."""
import copy
import csv
import importlib.util
import json
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("brohn_interchange", ROOT / "scripts/workers/interchange.py")
worker = importlib.util.module_from_spec(spec); spec.loader.exec_module(worker)


def varint(value):
    return bytes([1, value]) if value < 256 else b"\x04" + struct.pack("<I", value)


def chunk(tag, payload):
    return varint(len(payload)+2) + struct.pack("<H", tag) + payload


def header(sid, name, kind, fmt, rate, channels, origin="synthetic"):
    channel_xml = "".join("<channel>" + "".join(f"<{key}>{value}</{key}>" for key, value in c.items()) + "</channel>" for c in channels)
    xml = f"<info><name>{name}</name><type>{kind}</type><channel_count>{len(channels)}</channel_count><nominal_srate>{rate}</nominal_srate><channel_format>{fmt}</channel_format><uid>original-uid-{sid}</uid><source_id>original-device</source_id><session_id>original-session</session_id><desc><origin>{origin}</origin><channels>{channel_xml}</channels></desc></info>"
    return chunk(2, struct.pack("<I", sid) + xml.encode())


def samples(sid, fmt, rows):
    body = struct.pack("<I", sid) + varint(len(rows))
    for stamp, values in rows:
        body += b"\x00" if stamp is None else b"\x08" + struct.pack("<d", stamp)
        for value in values:
            if fmt == "string":
                raw = value.encode("utf-8"); body += varint(len(raw)) + raw
            else:
                body += struct.pack({"double64": "<d", "float32": "<f", "int64": "<q"}[fmt], value)
    return chunk(3, body)


def footer(sid, count):
    return chunk(6, struct.pack("<I", sid) + f"<info><sample_count>{count}</sample_count></info>".encode())


def offset(sid, collection, value):
    return chunk(4, struct.pack("<Idd", sid, collection, value))


def xdf_fixture():
    return b"XDF:" + chunk(1, b"<info><version>1.0</version></info>") + \
        header(7, "Original EEG", "EEG", "double64", 8, [{"label": "Fz", "type": "EEG", "unit": "uV"}]) + \
        header(2, "Original markers", "Markers", "string", 0, [{"label": "event"}]) + \
        header(9, "Original counter", "UnknownCounter", "int64", 0, [{}]) + \
        offset(7, 10, .1) + samples(7, "double64", [(10, [1]), (None, [2]), (10.25, [3])]) + \
        samples(2, "string", [(10, ["control"]), (10, [""]), (10.237, ["test"]), (9, ["restart"])] ) + \
        offset(7, 20, .2) + offset(7, 3, 6) + \
        chunk(5, bytes.fromhex("43a546dccbf5410fb30ed5467383cbe4")) + \
        samples(7, "double64", [(11, [float("nan")]), (5, [5]), (5.125, [float("inf")])]) + \
        samples(9, "int64", [(1, [9007199254740993]), (2, [-9007199254740993])]) + \
        chunk(99, b"original opaque extension") + footer(7, 6) + footer(2, 4) + footer(9, 2)


def bundle_fixture():
    return {"schema": "brohn-stream-bundle/1.0", "origin": "sample", "streams": [
        {"id": "analog", "name": "Original EDA", "type": "EDA", "kind": "signal", "source_id": "source-a", "uid": "uid-a",
         "clock": {"id": "device-a", "unit": "ns", "kind": "device", "representation": "decimal_string", "resolution": "1000"},
         "nominal_srate": 10, "identity": {"participant_id": "p1", "session_id": "s1"},
         "channels": [{"id": "eda", "label": "EDA", "type": "EDA", "unit": "uS", "value_type": "float64", "scale": "0.01", "offset": "0"},
                      {"id": "counter", "label": "Counter", "type": "counter", "unit": "count", "value_type": "int64"}],
         "clock_offsets": [{"collection_timestamp": "9007199254740993", "offset_s": ".125", "reference_clock_id": "master", "uncertainty_s": ".001"}],
         "samples": [{"timestamp": str(9007199254740993 + i*100000000), "values": [i, str(9007199254740993+i)]} for i in range(3)] +
                    [{"timestamp": "9007199554740993", "values": [None, "-9007199254740993"], "identity": {"participant_id": "p2", "session_id": "s2"}},
                     {"timestamp": "1", "values": [4, "4"], "identity": {"participant_id": "p2", "session_id": "s2"}, "reset": True}]},
        {"id": "events", "name": "Original typed markers", "type": "Markers", "kind": "markers", "source_id": None, "uid": None,
         "clock": {"id": "marker-clock", "unit": "s", "kind": "monotonic", "representation": "decimal_string"}, "nominal_srate": 0,
         "channels": [{"id": "condition", "label": "Condition code", "type": "event", "unit": None, "value_type": "int32"},
                      {"id": "answer", "label": "Answer", "type": "event", "unit": None, "value_type": "boolean"}],
         "samples": [{"timestamp": "10", "values": [0, False]}, {"timestamp": "10", "values": [1, True]}, {"timestamp": None, "values": [None, None]}]}]}


class InterchangeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.root = Path(self.temp.name)
    def tearDown(self):
        self.temp.cleanup()
    def run_source(self, data, format="xdf", origin="sample"):
        path = self.root / ("source.xdf" if format == "xdf" else "source.json")
        path.write_bytes(data if isinstance(data, bytes) else json.dumps(data).encode())
        request = {"schema": "brohn-interchange-request/1.0", "operation": "import_multistream", "format": format,
                   "source_path": str(path), "source_hash": worker.digest(path), "output_directory": str(self.root / "artifacts"),
                   "metadata": {"origin": origin, "origin_statement": "Original synthetic fixture only.", "clock_policy": "preserve_only"}}
        return worker.run(request), request
    def full(self, stream):
        path = next(x["path"] for x in stream["artifacts"] if x["kind"] == "stream_samples_jsonl")
        return [json.loads(x) for x in Path(path).read_text().splitlines()]

    def test_xdf_multistream_raw_values_clocks_offsets_markers(self):
        result, _ = self.run_source(xdf_fixture())
        self.assertEqual([x["id"] for x in result["streams"]], ["xdf-7", "xdf-2", "xdf-9"])
        self.assertEqual(result["quality"]["sample_count"], 12)
        self.assertFalse(result["quality"]["synchronized"])
        eeg, markers, counter = result["streams"]
        rows = self.full(eeg)
        self.assertEqual([x["source_timestamp"] for x in rows], ["10.0", "10.125", "10.25", "11.0", "5.0", "5.125"])
        self.assertTrue(rows[1]["reconstructed_timestamp"])
        self.assertEqual(rows[0]["timestamp_ieee754_le_hex"], struct.pack("<d", 10).hex())
        self.assertIsNone(rows[3]["values"]["channel_1"])
        self.assertEqual(rows[3]["value_states"]["channel_1"], "nan")
        self.assertEqual(rows[5]["value_states"]["channel_1"], "positive_infinity")
        self.assertEqual(eeg["channels"][0]["unit"], "uV")
        self.assertEqual(eeg["uid"], "original-uid-7")
        self.assertEqual(eeg["clock_offset_count"], 3)
        self.assertEqual(eeg["clock_offsets_preview"][2]["offset_s"], "6.0")
        self.assertTrue(any("clock_offset_collection_reversal" in x["boundary_reasons"] for x in eeg["segments_preview"]))
        self.assertTrue(any("timestamp_reversal" in x["boundary_reasons"] for x in eeg["segments_preview"]))
        self.assertEqual([r["values"]["channel_1"] for r in self.full(markers)], ["control", "", "test", "restart"])
        self.assertEqual(markers["kind"], "markers")
        self.assertEqual(markers["quality"]["coincident_marker_count"], 1)
        self.assertEqual([r["values"]["channel_1"] for r in self.full(counter)], ["9007199254740993", "-9007199254740993"])
        self.assertIsNone(counter["channels"][0]["unit"])
        self.assertEqual(counter["kind"], "unclassified")
        self.assertEqual(result["container"]["unknown_chunk_count"], 1)
        for item in result["artifacts"]:
            self.assertEqual(worker.digest(item["path"]), item["sha256"])
            self.assertEqual(Path(item["path"]).stat().st_size, item["bytes"])

    def test_bundle_exact_ticks_types_identity_and_origin(self):
        result, _ = self.run_source(bundle_fixture(), "brohn_stream_bundle", origin="live")
        self.assertEqual(result["origin"], "mixed")
        self.assertTrue(result["quality"]["origin_conflict"])
        self.assertTrue(all(x["origin"] == "sample" for x in result["streams"]))
        analog, events = result["streams"]
        rows = self.full(analog)
        self.assertEqual(rows[1]["time_since_segment_start_s"], "0.100000000")
        self.assertEqual(rows[1]["values"]["counter"], "9007199254740994")
        self.assertEqual(rows[1]["values"]["eda"], 1)  # declared scale is preserved, not applied
        self.assertEqual(analog["channels"][0]["scale"], "0.01")
        self.assertEqual(analog["segment_count"], 3)
        self.assertIn("identity_change", analog["segments_preview"][1]["boundary_reasons"])
        self.assertIn("declared_reset", analog["segments_preview"][2]["boundary_reasons"])
        marker_rows = self.full(events)
        self.assertEqual(marker_rows[0]["values"], {"condition": 0, "answer": False})
        self.assertEqual(marker_rows[1]["values"], {"condition": 1, "answer": True})
        self.assertIsNone(marker_rows[2]["source_timestamp"])
        self.assertEqual(marker_rows[2]["value_states"]["answer"], "missing")
        csv_path = next(x["path"] for x in analog["artifacts"] if x["kind"] == "stream_samples_csv")
        with open(csv_path, newline="", encoding="utf-8") as file:
            table = list(csv.DictReader(file))
        self.assertEqual(table[0]["value_counter"], "9007199254740993")
        self.assertEqual(table[3]["state_eda"], "missing")

    def test_gaps_preview_full_artifact_and_no_sort(self):
        fixture = bundle_fixture(); fixture["streams"] = fixture["streams"][:1]
        stream = fixture["streams"][0]
        stream["clock"]["unit"] = "s"
        stream["samples"] = [{"timestamp": str(i), "values": [i, str(i)]} for i in range(25)]
        result, _ = self.run_source(fixture, "brohn_stream_bundle")
        imported = result["streams"][0]
        self.assertEqual(len(imported["preview"]), 20)
        self.assertTrue(imported["preview_truncated"])
        self.assertEqual(len(self.full(imported)), 25)
        self.assertEqual(imported["segment_count"], 25)
        self.assertEqual(imported["segments_preview"][1]["boundary_reasons"], ["nominal_sampling_gap"])
        self.assertTrue(imported["segments_preview_truncated"])
        evidence_path = next(x["path"] for x in imported["artifacts"] if x["kind"] == "stream_evidence_jsonl")
        evidence = [json.loads(x) for x in Path(evidence_path).read_text().splitlines()]
        self.assertEqual(len([x for x in evidence if x["type"] == "source_segment"]), 25)

    def test_unanchored_omitted_timestamp_and_missing_footer(self):
        content = b"XDF:" + chunk(1,b"<info><version>1.0</version></info>") + header(1,"Original","EEG","float32",2,[{"unit":"V"}]) + samples(1,"float32",[(None,[1]),(1,[2])])
        result, _ = self.run_source(content)
        stream = result["streams"][0]; rows = self.full(stream)
        self.assertEqual(rows[0]["timestamp_state"], "unanchored_nominal_reconstruction")
        self.assertIsNone(rows[0]["time_since_segment_start_s"])
        self.assertFalse(stream["orderly_closed"])
        self.assertEqual(result["status"], "needs_mapping")

    def test_corrupt_xdf_rejected_before_recovery_or_allocation(self):
        cases = [xdf_fixture()[:-2], xdf_fixture() + b"\x03\x00", xdf_fixture().replace(b"<sample_count>6",b"<sample_count>7")]
        prefix = b"XDF:" + chunk(1,b"<info><version>1.0</version></info>") + header(1,"Original","EEG","double64",8,[{}])
        cases.append(prefix + chunk(3,struct.pack("<I",1) + b"\x08" + struct.pack("<Q",2**50)))
        cases.append(prefix + header(1,"Reused identity","EEG","double64",8,[{}]))
        cases.append(prefix + chunk(3,struct.pack("<I",1)+varint(1)+b"\x08"+struct.pack("<d",1)+b"\x00"))
        for case in cases:
            with self.subTest(length=len(case)), self.assertRaises((worker.InputError,ValueError)):
                self.run_source(case)

    def test_bundle_invalid_units_are_unknown_not_guessed_and_types_fail(self):
        value = bundle_fixture(); value["streams"][0]["channels"][0]["unit"] = None
        result, _ = self.run_source(value,"brohn_stream_bundle")
        self.assertEqual(result["streams"][0]["quality"]["unknown_unit_channels"],["eda"])
        for mutate in [lambda v: v["streams"][0]["samples"][0]["values"].__setitem__(1,9007199254740993),
                       lambda v: v["streams"][0]["samples"][0]["values"].__setitem__(0,9007199254740993),
                       lambda v: v["streams"][1]["samples"][0]["values"].__setitem__(1,0),
                       lambda v: v["streams"][0]["samples"][0].__setitem__("timestamp",9007199254740993),
                       lambda v: v["streams"][0]["samples"][0].__setitem__("identity",{"participant":"guessed"})]:
            invalid = bundle_fixture(); mutate(invalid)
            with self.assertRaises(worker.InputError):
                self.run_source(invalid,"brohn_stream_bundle")

    def test_cli_integrity_and_overwrite(self):
        result, request = self.run_source(bundle_fixture(),"brohn_stream_bundle")
        path = self.root/"request.json"; output=self.root/"result.json"
        path.write_text(json.dumps(request))
        command=[sys.executable,str(ROOT/"scripts/workers/interchange.py"),"--request",str(path),"--output",str(output)]
        done=subprocess.run(command,capture_output=True,timeout=30)
        self.assertEqual(done.returncode,0)
        self.assertEqual(json.loads(output.read_text())["quality"]["sample_count"],8)
        request["source_hash"]="0"*64; path.write_text(json.dumps(request))
        done=subprocess.run(command,capture_output=True,timeout=30)
        self.assertEqual(done.returncode,2)
        self.assertEqual(json.loads(output.read_text())["status"],"error")
        original=Path(request["source_path"]).read_bytes()
        done=subprocess.run(command[:-1]+[request["source_path"]],capture_output=True,timeout=30)
        self.assertEqual(done.returncode,2)
        self.assertEqual(Path(request["source_path"]).read_bytes(),original)

    def test_conflicting_source_origins_cannot_upgrade_synthetic(self):
        fixture = bundle_fixture(); fixture["streams"][0]["origin"] = "live"
        result, _ = self.run_source(fixture,"brohn_stream_bundle",origin="live")
        self.assertEqual(result["streams"][0]["origin"],"mixed")
        self.assertEqual(result["streams"][1]["origin"],"sample")
        fixture["streams"][0]["origin"] = None
        with self.assertRaises(worker.InputError):
            self.run_source(fixture,"brohn_stream_bundle")
        prefix = b"XDF:" + chunk(1,b"<info><version>1.0</version></info>")
        original_header = header(1,"Origin conflict","EEG","double64",1,[{"unit":"V"}],origin="live")
        # Reconstruct the header rather than altering encoded chunk lengths.
        xml = original_header[8:] if original_header[0] == 1 else original_header[11:]
        xml = xml.replace(b"</info>",b"<origin>synthetic</origin></info>")
        content = prefix + chunk(2,struct.pack("<I",1)+xml) + samples(1,"double64",[(1,[1]),(2,[2])]) + footer(1,2)
        result, _ = self.run_source(content,origin="live")
        self.assertEqual(result["streams"][0]["origin"],"mixed")


if __name__ == "__main__":
    unittest.main(verbosity=2)
