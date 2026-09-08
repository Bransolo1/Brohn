"""Original synthetic outlets only; isolated machine-scope session."""
import copy
import importlib.util
import json
import os
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import time
import unittest
import uuid

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts/acquisition/lsl_recorder.py"
spec = importlib.util.spec_from_file_location("brohn_lsl_recorder", SCRIPT)
recorder = importlib.util.module_from_spec(spec); spec.loader.exec_module(recorder)


class RecorderTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.context = tempfile.TemporaryDirectory(prefix="brohn-lsl-synthetic-")
        cls.session = "synthetic-" + uuid.uuid4().hex
        config = Path(cls.context.name) / "lsl.cfg"
        config.write_text("[multicast]\nResolveScope = machine\n[lab]\nKnownPeers = {127.0.0.1}\nSessionID = " + cls.session + "\n")
        cls.previous = os.environ.get("LSLAPICFG")
        os.environ["LSLAPICFG"] = str(config)
        import pylsl
        cls.api = pylsl

    @classmethod
    def tearDownClass(cls):
        if cls.previous is None:
            os.environ.pop("LSLAPICFG", None)
        else:
            os.environ["LSLAPICFG"] = cls.previous
        cls.context.cleanup()

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="brohn-recorder-test-")
        self.root = Path(self.temp.name); self.children = []; self.outlets = []; self.n = 0

    def tearDown(self):
        for process in self.children:
            if process.poll() is None:
                process.kill(); process.wait(timeout=10)
        self.outlets.clear()
        for attempt in range(30):
            try:
                self.temp.cleanup(); break
            except PermissionError:
                if attempt == 29:
                    raise
                time.sleep(.05)

    def until(self, fn, timeout=10):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            try:
                if fn():
                    return
            except PermissionError:
                pass  # Atomic replacement can briefly deny a Windows reader.
            time.sleep(.02)
        self.fail("Timed out waiting for isolated recorder state")

    def cli(self, operation, request=None, recording=None, extra=(), wait=True):
        self.n += 1; output = self.root / f"receipt-{self.n}.json"
        args = [sys.executable, str(SCRIPT), operation, "--output", str(output)]
        if request is not None:
            path = self.root / f"request-{self.n}.json"; path.write_text(json.dumps(request))
            args += ["--request", str(path)]
        if recording is not None:
            args += ["--recording", str(recording)]
        args += list(extra)
        child = subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0)
        self.children.append(child)
        if not wait:
            return child, output
        stdout, stderr = child.communicate(timeout=20)
        self.assertTrue(output.exists(), (stdout, stderr))
        return child.returncode, json.loads(output.read_text()), stderr.decode(errors="replace")

    def outlet(self, fmt="double64", count=1, rate=0):
        source = "source-" + uuid.uuid4().hex
        info = self.api.StreamInfo("Original synthetic QA", "BrohnSynthetic", count, rate, fmt, source)
        info.desc().append_child_value("origin", "synthetic")
        channels = info.desc().append_child("channels")
        for i in range(count):
            channel = channels.append_child("channel")
            channel.append_child_value("label", "original-" + str(i))
            channel.append_child_value("unit", "marker" if fmt == "string" else "count")
            channel.append_child_value("type", "synthetic")
        outlet = self.api.StreamOutlet(info, chunk_size=1, max_buffered=5); self.outlets.append(outlet)
        code, result, errors = self.cli("discover", {"schema": "brohn-lsl-discovery-request/1.0",
            "lsl_session": self.session, "source_ids": [source], "timeout_s": 2})
        self.assertEqual(code, 0, errors); self.assertEqual(len(result["streams"]), 1)
        self.assertTrue(result["metadata_only"]); self.assertFalse(outlet.have_consumers())
        observed = result["streams"][0]
        selection = {"id": "stream-" + str(len(self.outlets)), "uid": observed["uid"], "source_id": source,
            "metadata_sha256": observed["metadata_sha256"], "clock_id": "source-clock-" + str(len(self.outlets)),
            "clock_kind": "monotonic",
            "kind": "markers" if fmt == "string" else "signal", "unit_provenance": "Original synthetic outlet declaration; no hardware.",
            "channels": [{"id": "channel-"+str(i), "label": c["label"], "type": "synthetic", "unit": c["unit"],
                          "value_type": c["value_type"]} for i, c in enumerate(observed["channels"])]}
        return outlet, selection

    def request(self, streams, samples=10000, duration=10):
        return {"schema": "brohn-lsl-record-request/1.0", "recording_id": "recording-"+uuid.uuid4().hex,
            "output_root": str(self.root), "lsl_session": self.session, "origin": "sample",
            "origin_statement": "Original synthetic acceptance data, no device or participants.",
            "identity": {"participant_id": "explicit-P1", "session_id": "explicit-S1"},
            "references": {"study_id": "synthetic-study", "design_hash": "a"*64}, "streams": streams,
            "limits": {"max_duration_s": duration, "max_samples": samples, "max_bytes": 4*1024**2,
                       "chunk_samples": 4, "inlet_buffer": 2}}

    def start(self, request):
        child, output = self.cli("record", request=request, wait=False)
        directory = self.root / request["recording_id"]
        self.until(lambda: (directory/"status.json").exists() and json.loads((directory/"status.json").read_text())["completion_status"] == "recording")
        for outlet in self.outlets:
            self.assertTrue(outlet.wait_for_consumers(timeout=3), "Synthetic transport must finish subscribing before original samples are sent")
        return child, output, directory

    def control(self, request, directory, operation="stop"):
        recorder.atomic(directory / "control.json", {"recording_id": request["recording_id"],
            "request_sha256": recorder.sha(recorder.encoded(request)), "operation": operation}, replace=False)

    def finish(self, child, output):
        stdout, stderr = child.communicate(timeout=15)
        self.assertEqual(child.returncode, 0, (output.read_text() if output.exists() else None, stdout, stderr))
        return json.loads(output.read_text())

    def rows(self, inspection, directory, sid=None):
        rows = []
        for chunk in inspection["chunks"]:
            if sid is None or chunk["stream_id"] == sid:
                rows += [json.loads(line) for line in (directory/chunk["path"]).read_text().splitlines()]
        return rows

    def test_real_numeric_gaps_reset_nonfinite_clock_and_bounded_samples(self):
        outlet, selected = self.outlet(); selected["gap_threshold_s"] = .5
        request = self.request([selected], samples=7)
        child, output, directory = self.start(request)
        stamps = [10., 10.1, 12., 12., 2., 2.1, 2.2]
        values = [0., -0., float("nan"), float("inf"), -2., 4., 8.]
        for value, timestamp in zip(values, stamps):
            outlet.push_sample([value], timestamp=timestamp)
        result = self.finish(child, output)
        self.assertEqual(result["reason"], "max_samples"); self.assertTrue(result["complete"])
        inspection = recorder.inspect_recording(directory); rows = self.rows(inspection, directory)
        self.assertEqual([float(r["source_timestamp"]) for r in rows], stamps)
        self.assertEqual([r["sequence"] for r in rows], list(range(1, 8)))
        self.assertEqual(rows[0]["values"], [0.]); self.assertEqual(rows[1]["value_ieee754_le_hex"], [struct.pack("<d", -0.).hex()])
        self.assertEqual(rows[2]["value_states"], ["nan"]); self.assertIsNone(rows[2]["values"][0])
        self.assertEqual(rows[3]["value_states"], ["positive_infinity"])
        self.assertIn("declared_gap_threshold", rows[2]["boundary_reasons"])
        self.assertIn("coincident_timestamp", rows[3]["boundary_reasons"])
        self.assertIn("timestamp_reversal", rows[4]["boundary_reasons"]); self.assertEqual(rows[4]["segment"], 2)
        self.assertTrue(all(float(r["receive_after_s"]) >= float(r["receive_before_s"]) for r in rows))
        self.assertTrue(all(c["rows"] <= 4 for c in inspection["chunks"]))
        self.assertFalse(result["clock_synchronized"]); self.assertEqual(result["signal_quality"], "not_qualified")
        self.assertEqual(inspection["request"]["identity"]["participant_id"], "explicit-P1")
        self.assertEqual(inspection["evidence"]["streams"][0]["observed"]["source_origin"], "synthetic")
        self.assertIsNotNone(child.poll())  # Child exit destroys its inlet handles.

    def test_real_multistream_int32_strings_and_existing_interchange(self):
        counter, integer = self.outlet("int32"); markers, marker = self.outlet("string")
        request = self.request([integer, marker]); child, output, directory = self.start(request)
        counter.push_sample([0], timestamp=1.25); counter.push_sample([-2147483647], timestamp=1.5)
        markers.push_sample([""], timestamp=1.25); markers.push_sample(["control"], timestamp=1.25); markers.push_sample(["test"], timestamp=1.75)
        self.until(lambda: json.loads((directory/"status.json").read_text())["samples"] == 5)
        time.sleep(1.2); self.control(request, directory); self.finish(child, output)
        inspection = recorder.inspect_recording(directory)
        self.assertEqual([r["values"][0] for r in self.rows(inspection, directory, integer["id"])], [0, -2147483647])
        self.assertEqual([r["values"][0] for r in self.rows(inspection, directory, marker["id"])], ["", "control", "test"])
        self.assertTrue(inspection["clock_corrections"])
        self.assertTrue(all(c["applied"] is False and c["uncertainty_s"] is None for c in inspection["clock_corrections"]))
        bundle_path = self.root/"portable.json"; exported = recorder.export_bundle(directory, bundle_path)
        self.assertTrue(exported["complete"])
        spec = importlib.util.spec_from_file_location("brohn_interchange", ROOT/"scripts/workers/interchange.py")
        importer = importlib.util.module_from_spec(spec); spec.loader.exec_module(importer)
        result = importer.run({"schema": "brohn-interchange-request/1.0", "operation": "import_multistream", "format": "brohn_stream_bundle",
            "source_path": str(bundle_path), "source_hash": recorder.file_sha(bundle_path), "output_directory": str(self.root/"normalised"),
            "metadata": {"origin": "sample", "origin_statement": "Original synthetic recorder QA.", "clock_policy": "preserve_only"}})
        self.assertEqual(result["quality"]["sample_count"], 5)
        imported_path = next(a["path"] for a in result["streams"][0]["artifacts"] if a["kind"] == "stream_samples_jsonl")
        imported_rows = [json.loads(line) for line in Path(imported_path).read_text().splitlines()]
        self.assertEqual(imported_rows[0]["identity"]["participant_id"], "explicit-P1")
        self.assertEqual(json.loads(bundle_path.read_text())["streams"][0]["metadata"]["parent_recording"]["journal_tip"], inspection["journal_tip"])

    @unittest.skipUnless(os.name == "nt" or struct.calcsize("P") == 4, "Only this platform has the upstream int64 transport restriction")
    def test_real_int64_source_is_declared_unsupported_before_subscription(self):
        outlet, selected = self.outlet("int64")
        code, result, _ = self.cli("record", self.request([selected]))
        self.assertEqual(code, 2); self.assertIn("disables int64", result["error"]["message"])
        self.assertFalse(outlet.have_consumers())

    def test_exact_int64_disk_values_never_pass_through_float(self):
        writer, selected, directory = self.fake_writer()
        writer.journal.close()
        # A separate fresh original fixture declares int64 at the writer boundary.
        selected["channels"][0]["value_type"] = "int64"
        request = self.request([selected]); directory = self.root/request["recording_id"]
        directory.mkdir(); (directory/"chunks").mkdir()
        writer = recorder.Writer(directory, request, {"synthetic": True})
        writer.chunk(selected, [[9007199254740993], [-9007199254740993], [0]], [1., 2., 3.], 4., 5.)
        writer.finish("completed", "original_fixture")
        rows = self.rows(recorder.inspect_recording(directory), directory)
        self.assertEqual([r["values"][0] for r in rows], ["9007199254740993", "-9007199254740993", "0"])

    def test_real_cancel_closes_and_requires_explicit_recovered_export(self):
        outlet, selected = self.outlet("float32"); request = self.request([selected])
        child, output, directory = self.start(request); outlet.push_sample([1.25], timestamp=10.)
        self.until(lambda: json.loads((directory/"status.json").read_text())["samples"] == 1)
        self.control(request, directory, "cancel"); result = self.finish(child, output)
        self.assertEqual(result["completion_status"], "cancelled"); self.assertFalse(result["complete"])
        with self.assertRaises(recorder.RecorderError):
            recorder.export_bundle(directory, self.root/"disallowed.json")
        self.assertFalse(recorder.export_bundle(directory, self.root/"recovered.json", True)["complete"])
        self.assertIsNotNone(child.poll())

    def test_real_crash_keeps_verified_commits_and_never_false_complete(self):
        outlet, selected = self.outlet(); request = self.request([selected])
        child, _, directory = self.start(request)
        for i in range(6):
            outlet.push_sample([float(i)], timestamp=float(i+1))
        self.until(lambda: json.loads((directory/"status.json").read_text())["samples"] == 6)
        child.kill(); child.communicate(timeout=10)
        self.assertFalse((directory/"manifest.json").exists())
        inspection = recorder.inspect_recording(directory)
        self.assertEqual(inspection["completion_status"], "interrupted"); self.assertFalse(inspection["complete"])
        self.assertIsNone(inspection["quality_qualified"]); self.assertIsNone(inspection["signal_quality"])
        self.assertEqual(inspection["quality_evidence"], "missing_final_manifest")
        self.assertEqual(inspection["samples"], 6)
        with (directory/"journal.jsonl").open("ab") as file:
            file.write(b'{"torn":')
        (directory/"chunks"/"uncommitted.jsonl").write_text("untrusted")
        recovered = recorder.inspect_recording(directory)
        self.assertTrue(recovered["torn_journal_tail"]); self.assertEqual(recovered["orphan_files_not_trusted"], 1)
        self.assertEqual(recovered["samples"], 6)

    def test_real_frozen_selection_metadata_mismatch_never_subscribes(self):
        outlet, selected = self.outlet()
        selected["metadata_sha256"] = "0"*64
        code, result, _ = self.cli("record", self.request([selected]))
        self.assertEqual(code, 2); self.assertIn("metadata changed", result["error"]["message"])
        self.assertFalse(outlet.have_consumers())

    def test_real_synthetic_origin_cannot_be_relabelled_live(self):
        outlet, selected = self.outlet(); request = self.request([selected]); request["origin"] = "live"
        code, result, _ = self.cli("record", request)
        self.assertEqual(code, 2); self.assertIn("origin conflicts", result["error"]["message"])
        self.assertFalse(outlet.have_consumers())

    def test_real_frozen_uid_never_reconnects_by_source_id(self):
        outlet, selected = self.outlet(); selected["uid"] = "wrong-outlet-instance"
        code, result, _ = self.cli("record", self.request([selected]))
        self.assertEqual(code, 2); self.assertIn("Frozen source UID", result["error"]["message"])
        self.assertFalse(outlet.have_consumers())

    def test_real_wrong_control_bound_identity_marks_incomplete(self):
        outlet, selected = self.outlet(); request = self.request([selected])
        child, output, directory = self.start(request)
        recorder.atomic(directory/"control.json", {"recording_id": "another-recording", "request_sha256": "0"*64, "operation": "stop"})
        child.communicate(timeout=10)
        self.assertEqual(child.returncode, 2)
        self.assertEqual(recorder.inspect_recording(directory)["completion_status"], "incomplete")

    def test_real_duration_bound_with_no_samples(self):
        outlet, selected = self.outlet(); request = self.request([selected], duration=.2)
        child, output, directory = self.start(request); result = self.finish(child, output)
        self.assertEqual(result["reason"], "max_duration"); self.assertEqual(result["samples"], 0)
        self.assertTrue(result["complete"]); self.assertFalse(result["quality_qualified"])
        inspected = recorder.inspect_recording(directory)
        self.assertFalse(inspected["quality_qualified"])
        self.assertEqual(inspected["signal_quality"], "not_qualified")
        self.assertEqual(inspected["quality_evidence"], "verified_final_manifest")
        self.assertEqual(inspected["manifest_sha256"], recorder.file_sha(directory / "manifest.json"))

    @unittest.skipUnless(os.name == "nt", "Windows path profile")
    def test_real_unsupported_path_rejected_before_subscribing_or_creating_recording(self):
        outlet, selected = self.outlet(); request = self.request([selected])
        # The existing parent is valid, but the complete owned recording layout
        # would exceed the ordinary Windows API profile.
        parent = self.root / ("p" * (240-len(str(self.root))-1)); parent.mkdir()
        request["output_root"] = str(parent)
        code, result, _ = self.cli("record", request)
        self.assertEqual(code, 2); self.assertIn("shorter workspace path", result["error"]["message"])
        self.assertFalse(outlet.have_consumers())
        self.assertFalse((parent/request["recording_id"]).exists())

    def fake_writer(self, maximum=65536):
        selected = {"id": "synthetic", "uid": "u", "source_id": "s", "clock_id": "c", "clock_kind": "monotonic", "metadata_sha256": "a"*64,
                    "kind": "signal", "unit_provenance": "Synthetic fixture", "channels": [{"id": "x", "label": "x", "type": "x", "unit": "V", "value_type": "float64"}]}
        request = self.request([selected]); request["limits"]["max_bytes"] = maximum
        directory = self.root/request["recording_id"]; directory.mkdir(); (directory/"chunks").mkdir()
        writer = recorder.Writer(directory, request, {"synthetic": True})
        return writer, selected, directory

    def test_arithmetic_size_bound_and_no_false_completion(self):
        writer, selected, directory = self.fake_writer()
        try:
            for index in range(500):
                if not writer.chunk(selected, [[0.]], [float(index)], 1., 2.):
                    break
            else:
                self.fail("Expected byte bound")
            result = writer.finish("incomplete", "max_bytes")
            self.assertLessEqual(result["sample_bytes"], 65536); self.assertFalse(result["complete"])
            self.assertEqual(recorder.inspect_recording(directory)["samples"], result["samples"])
        finally:
            writer.journal.close()

    def test_corrupt_committed_chunk_is_rejected(self):
        writer, selected, directory = self.fake_writer()
        writer.chunk(selected, [[1.]], [1.], 2., 3.); writer.finish("completed", "test")
        chunk = directory/writer.chunks[0]["path"]; chunk.write_bytes(chunk.read_bytes().replace(b'1.0', b'9.0', 1))
        with self.assertRaisesRegex(recorder.RecorderError, "absent or corrupt"):
            recorder.inspect_recording(directory)

    def test_absent_committed_chunk_is_rejected(self):
        writer, selected, directory = self.fake_writer()
        writer.chunk(selected, [[1.]], [1.], 2., 3.); writer.finish("completed", "test")
        (directory/writer.chunks[0]["path"]).unlink()
        with self.assertRaisesRegex(recorder.RecorderError, "absent or corrupt"):
            recorder.inspect_recording(directory)

    def test_final_manifest_cannot_forge_completion(self):
        writer, selected, directory = self.fake_writer(); writer.finish("cancelled", "test")
        manifest = json.loads((directory/"manifest.json").read_text()); manifest["complete"] = True
        (directory/"manifest.json").write_text(json.dumps(manifest))
        with self.assertRaisesRegex(recorder.RecorderError, "Terminal status"):
            recorder.inspect_recording(directory)

    def test_final_manifest_cannot_forge_scientific_qualification(self):
        writer, selected, directory = self.fake_writer(); writer.finish("completed", "test")
        manifest = json.loads((directory/"manifest.json").read_text()); manifest["quality_qualified"] = True
        (directory/"manifest.json").write_text(json.dumps(manifest))
        with self.assertRaisesRegex(recorder.RecorderError, "unsupported signal-quality"):
            recorder.inspect_recording(directory)

    def test_missing_legacy_quality_fields_remain_unknown(self):
        writer, selected, directory = self.fake_writer(); writer.finish("completed", "test")
        manifest = json.loads((directory/"manifest.json").read_text())
        del manifest["quality_qualified"]; del manifest["signal_quality"]
        (directory/"manifest.json").write_text(json.dumps(manifest))
        inspection = recorder.inspect_recording(directory)
        self.assertTrue(inspection["complete"])
        self.assertIsNone(inspection["quality_qualified"]); self.assertIsNone(inspection["signal_quality"])
        self.assertEqual(inspection["quality_evidence"], "missing_quality_fields")

    def test_owned_chunk_names_are_bounded_and_checksum_is_still_enforced(self):
        writer, selected, directory = self.fake_writer()
        writer.chunk(selected, [[0.], [-0.]], [1., 2.], 3., 4.); writer.finish("completed", "test")
        inspection = recorder.inspect_recording(directory); entry = inspection["chunks"][0]
        self.assertEqual(entry["path"], "chunks/000001.jsonl")
        self.assertEqual(entry["sha256"], recorder.file_sha(directory/entry["path"]))
        self.assertEqual([r["values"][0] for r in self.rows(inspection, directory)], [0., -0.])
        (directory/entry["path"]).write_text("same-name corruption")
        with self.assertRaisesRegex(recorder.RecorderError, "absent or corrupt"):
            recorder.inspect_recording(directory)

    def test_full_journal_hash_corruption_is_not_salvaged_as_torn_tail(self):
        writer, selected, directory = self.fake_writer(); writer.finish("completed", "test")
        path = directory/"journal.jsonl"
        path.write_bytes(path.read_bytes().replace(b'"opened"', b'"forged"', 1))
        with self.assertRaisesRegex(recorder.RecorderError, "Journal chain"):
            recorder.inspect_recording(directory)

    def test_containment_and_missing_identity_rejected(self):
        for path in ("../secret", "/absolute", "chunks/../../secret", "chunks\\evil"):
            with self.assertRaises(recorder.RecorderError):
                recorder.child_path(self.root, path)
        writer, selected, directory = self.fake_writer(); writer.finish("completed", "test")
        request = copy.deepcopy(writer.request); request["identity"] = {}
        with self.assertRaises(recorder.RecorderError):
            recorder.validate_request(request)
        request = copy.deepcopy(writer.request); request["recording_id"] = "../other"
        with self.assertRaises(recorder.RecorderError):
            recorder.validate_request(request)
        with self.assertRaisesRegex(recorder.RecorderError, "never overwrite"):
            recorder.record(writer.request)


if __name__ == "__main__":
    unittest.main(verbosity=2)
