"""Actual stream extraction -> cardiac source review, using original synthetic data.

Set BROHN_TEST_OUTPUT to retain the generated canonical source, derived files,
requests and acceptance receipt outside the repository. No physical-device or
detector-accuracy qualification is implied by these source-association tests.
"""
import copy
import csv
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[2]


def load(name, relative):
    spec = importlib.util.spec_from_file_location(name, ROOT / relative)
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


review = load("curation_peer_review", "scripts/workers/cardiac_review.py")
extract = load("curation_peer_extract", "scripts/workers/stream_extract.py")


def save(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding="utf-8")


def exclusion(lo, hi, identity="original-exclusion"):
    return {"id": identity, "start_sample": lo, "end_sample": hi,
            "reason": "researcher_exclusion", "note": "Original source-coordinate fixture, not an expert artifact label."}


def original_fixture(folder):
    """Two people, a device-clock change, and seven deliberately omitted rows."""
    missing = {0, 1, 2, 2003, 2004, 2105, 8008}
    rows = []
    for i in range(8009):
        first = i < 2003
        local = i if first else i - 2003
        epoch = 9007199254740993 if first else 999999999999999999123
        value = math.sin(2 * math.pi * 1.2 * local / 100) + .2 * math.sin(2 * math.pi * 2.4 * local / 100)
        rows.append({"sequence": i + 1, "stream_id": "original-ppg", "segment_id": "device-a" if first else "device-b",
            "clock_id": "clock-a" if first else "clock-b", "timestamp_unit": "ns",
            "source_timestamp": str(epoch + local * 10000000), "timestamp_state": "observed",
            "timestamp_ieee754_le_hex": None, "reconstructed_timestamp": False,
            "time_since_segment_start_s": str(local / 100),
            "identity": {"participant_id": "person-a" if first else "person-\u03b2", "session_id": "visit-a" if first else "visit-b"},
            "values": {"pulse": None if i in missing else value},
            "value_states": {"pulse": "missing" if i in missing else "observed"}})
    source = folder / "original-canonical.jsonl"
    source.write_text("".join(json.dumps(r, ensure_ascii=False, allow_nan=False) + "\n" for r in rows), encoding="utf-8")
    request = {"schema": "brohn-stream-extract-request/1.0", "operation": "extract_stream",
        "source_path": str(source), "source_hash": extract.digest(source),
        "stream": {"schema": "brohn-imported-stream/1.0", "id": "original-ppg", "kind": "signal",
            "sample_count": len(rows), "nominal_srate": 100,
            "clock": {"id": "clock-a", "unit": "ns", "kind": "device", "representation": "decimal_string"},
            "channels": [{"id": "pulse", "label": "Original pulse generator", "type": "PPG", "unit": "a.u.", "value_type": "float64"}]},
        "selection": {"schema": "brohn-stream-selection/1.0", "channel_ids": ["pulse"], "modality": "ppg", "unit": "a.u.",
            "sampling_rate": 100, "participant_id": None, "session_id": None,
            "origin_statement": "Original deterministic source; no measured person or device.",
            "unit_rationale": "Generator amplitudes are arbitrary units.", "confirm_source_units": True,
            "confirm_boundaries": True, "run_analysis": False}, "output_directory": str(folder / "extracted")}
    extracted = extract.extract(request)
    csv_artifact = next(a for a in extracted["artifacts"] if a["kind"] == "curated_signal_csv")
    decisions = next(a for a in extracted["artifacts"] if a["kind"] == "curation_decisions_jsonl")
    metadata = {**extracted["metadata"], "origin": "sample"}
    parent_directory = folder / "parent-artifacts"
    parent_directory.mkdir()
    parent_request = {"schema": "brohn-worker-request/1.0", "operation": "physiology", "modality": "ppg",
        "source_path": csv_artifact["path"], "format": "csv", "metadata": metadata, "artifact_directory": str(parent_directory)}
    parent = review.physiology.run(parent_request)
    manifest = next(a for a in parent["artifacts"] if a["kind"] == "physiology-series")
    catalog = review.views.catalog({"page": {"offset": 0, "limit": 100}}, manifest)
    chosen = next(t for t in catalog["tables"] if t["support"]["source"]["source_row_start"] == 2100)
    curation = {"curation_id": "curation-original-fixture", "curation_revision": 1,
        "curation_hash": hashlib.sha256(json.dumps(extracted, sort_keys=True).encode()).hexdigest(),
        "lineage": {"canonical_hash": request["source_hash"], "stream_id": "original-ppg",
                    "origin": "original synthetic worker fixture; R entity authority is tested separately"},
        "decisions": {"sha256": decisions["sha256"], "bytes": decisions["bytes"]}, "decisions_path": decisions["path"]}
    cardiac_request = {"schema": "brohn-cardiac-review-request/1.0", "operation": "preview_cardiac_review",
        "policy": review.POLICY, "source": {"sha256": csv_artifact["sha256"], "bytes": csv_artifact["bytes"]},
        "source_path": csv_artifact["path"], "modality": "ppg", "format": "csv", "metadata": metadata,
        "parameters": {}, "artifact": manifest, "verification_receipt": review.artifacts.verify_manifest(parent["artifacts"]),
        "table": chosen, "review_source": {"id": "review-original-fixture", "revision": 1, "hash": "b" * 64},
        "spans": [exclusion(4100, 4400)], "curation": curation}
    for name, value in (("extraction-request", request), ("extraction-result", extracted), ("parent-request", parent_request),
                        ("parent-result", parent), ("cardiac-request", cardiac_request)):
        save(folder / (name + ".json"), value)
    return rows, missing, extracted, cardiac_request


class CardiacCuration(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        output = os.environ.get("BROHN_TEST_OUTPUT")
        if output:
            Path(output).mkdir(parents=True, exist_ok=True)
            cls.root = Path(tempfile.mkdtemp(prefix="cardiac-review-curation-", dir=output))
            cls.temporary = None
        else:
            cls.temporary = tempfile.TemporaryDirectory(prefix="cardiac-review-curation-")
            cls.root = Path(cls.temporary.name)
        cls.original, cls.missing, cls.extracted, cls.request = original_fixture(cls.root)
        cls.expected = [r for i, r in enumerate(cls.original) if i not in cls.missing]
        cls.decisions = [json.loads(line) for line in Path(cls.request["curation"]["decisions_path"]).read_text(encoding="utf-8").splitlines()]
        cls.hashes = {name: review.artifacts.digest_file(ROOT / "scripts/workers" / name) for name in
                      ("cardiac_review.py", "stream_extract.py", "physiology.py", "physiology_artifacts.py", "signal_preview.py")}

    @classmethod
    def tearDownClass(cls):
        if cls.temporary:
            cls.temporary.cleanup()

    def variant(self, label, change=None, rehash=True):
        request = copy.deepcopy(self.request)
        decisions = copy.deepcopy(self.decisions)
        if change:
            change(decisions)
        path = self.root / (label + ".jsonl")
        path.write_text("".join(json.dumps(row, ensure_ascii=False) + "\n" for row in decisions), encoding="utf-8")
        request["curation"]["decisions_path"] = str(path)
        if rehash:
            request["curation"]["decisions"] = {"sha256": review.artifacts.digest_file(path), "bytes": path.stat().st_size}
        return request

    def assert_crosswalk(self, value, index):
        original = self.expected[index]
        self.assertEqual(value["source_sample_index"], index)
        self.assertEqual(value["source_sequence"], original["sequence"])
        self.assertEqual(value["source_segment_id"], original["segment_id"])
        self.assertEqual(value["source_clock_id"], original["clock_id"])
        self.assertEqual(value["source_timestamp"], original["source_timestamp"])
        self.assertEqual(value["source_timestamp_unit"], "ns")
        self.assertEqual(value["source_identity"], original["identity"])

    def test_extractor_preserves_every_decision_and_explicit_omissions(self):
        self.assertEqual(len(self.decisions), 8009)
        self.assertEqual([d["source_sequence"] for d in self.decisions if d["disposition"] == "excluded"], [i + 1 for i in sorted(self.missing)])
        self.assertEqual(self.extracted["quality"]["included_rows"], 8002)
        with Path(self.request["source_path"]).open(encoding="utf-8", newline="") as stream:
            actual = list(csv.DictReader(stream))
        self.assertEqual([int(r["source_sequence"]) for r in actual], [r["sequence"] for r in self.expected])
        for row, original in zip(actual, self.expected):
            self.assertEqual(row["source_timestamp"], original["source_timestamp"])
            self.assertEqual(json.loads(row["source_identity_json"]), original["identity"])

    def test_preview_has_exact_acquisition_endpoint_crosswalk(self):
        result = review.run(copy.deepcopy(self.request))
        ledger = result["ledger"]
        self.assertEqual(ledger["support"]["input_samples"], 5902)
        self.assertEqual(ledger["curation"]["all_acquisition_rows"], 8009)
        self.assertEqual(ledger["curation"]["all_derived_rows"], 8002)
        for value, index in ((ledger["curation"]["selected_first"], 2100), (ledger["curation"]["selected_last"], 8001),
                             (ledger["spans"][0]["curated_first"], 4100), (ledger["spans"][0]["curated_last"], 4399)):
            self.assert_crosswalk(value, index)
            self.assertNotEqual(value["source_sample_index"], value["source_sequence"])
        self.assertEqual(ledger["curation"]["selected_first"]["source_timestamp"], "1000000000001029999123")
        self.assertEqual(ledger["spans"][0]["first_time_s"], 20)
        self.assertEqual(ledger["spans"][0]["last_time_s"], 22.99)
        save(self.root / "accepted-preview.json", result)

    def test_crosswalk_retention_is_bounded_to_130_requested_endpoints(self):
        request = copy.deepcopy(self.request)
        request["spans"] = [exclusion(2110 + 4*i, 2112 + 4*i, "span-" + str(i)) for i in range(64)]
        source = review.bind(request)
        self.assertEqual(len(source["crosswalk"]["rows"]), 130)
        self.assertEqual(source["crosswalk"]["all_derived_rows"], 8002)
        self.assert_crosswalk(source["crosswalk"]["rows"][2100], 2100)
        self.assertNotIn(2101, source["crosswalk"]["rows"])

    def test_reanalysis_keeps_one_person_and_global_indices_without_intervals_across_mask(self):
        request = copy.deepcopy(self.request)
        request["operation"] = "reanalyse_cardiac"
        directory = self.root / "reanalysed"
        directory.mkdir()
        request["artifact_directory"] = str(directory)
        result = review.run(request)
        samples, event_tables = [], []
        for manifest in result["artifacts"]:
            tables = {}
            def table(t):
                tables[t["table_id"]] = {"table": t, "rows": []}
            review.artifacts.verify_artifact(manifest, on_table=table, on_rows=lambda tid, offset, rows: tables[tid]["rows"].extend(rows))
            for entry in tables.values():
                self.assertEqual(entry["table"]["identity"]["group"]["participant_id"], "person-\u03b2")
                self.assertEqual(entry["table"]["identity"]["group"]["session_id"], "visit-b")
                if manifest["kind"] == "physiology-series":
                    samples.extend(entry["rows"])
                else:
                    event_tables.append(entry)
        self.assertEqual([row[1] for row in samples], list(range(2100, 4100)) + list(range(4400, 8002)))
        for row in samples:
            index = row[1]
            self.assertEqual(row[0], (index - 2100) / 100)
            self.assertEqual(row[2], self.expected[index]["values"]["pulse"])
        self.assertEqual(len(event_tables), 2)
        for table in event_tables:
            self.assertIsNone(table["rows"][0][4])
        self.assertFalse(result["quality"]["normal_to_normal_confirmed"])
        self.assertEqual(result["exclusion_review"]["support"]["excluded_samples"], 300)
        save(self.root / "accepted-reanalysis.json", result)

    def test_decision_bytes_changed_without_new_receipt_are_refused(self):
        request = self.variant("unchanged-receipt", lambda rows: rows[5000].update(source_clock_id="different-clock"), rehash=False)
        with self.assertRaisesRegex(ValueError, "byte/hash"):
            review.run(request)

    def test_rehashed_included_identity_clock_timestamp_and_segment_mismatches_are_refused(self):
        for field, value in (("source_clock_id", "other-clock"), ("source_timestamp", "0"),
                             ("source_timestamp_unit", "ms"), ("source_segment_id", "other-source-segment"),
                             ("brohn_segment_id", "other-derived-segment"), ("source_identity", {"participant_id": "other-person"})):
            request = self.variant("mismatch-" + field, lambda rows: rows[5000].update({field: value}))
            with self.subTest(field=field), self.assertRaisesRegex(ValueError, "derived row differs"):
                review.run(request)

    def test_complete_decision_order_and_included_coverage_are_enforced(self):
        variants = (("missing-interior-excluded-row", lambda rows: rows.pop(2)),
                    ("swapped-source-order", lambda rows: rows.__setitem__(slice(5000, 5002), rows[5000:5002][::-1])),
                    ("included-row-hidden", lambda rows: rows[5000].update(disposition="excluded")),
                    ("truncated-included-tail", lambda rows: rows.__delitem__(slice(8000, None))))
        for label, mutate in variants:
            with self.subTest(label=label), self.assertRaises(ValueError):
                review.run(self.variant(label, mutate))

    def test_truncated_original_excluded_tail_fails_pinned_descriptor(self):
        request = self.variant("truncated-excluded-tail", lambda rows: rows.pop(), rehash=False)
        with self.assertRaisesRegex(ValueError, "byte/hash"):
            review.run(request)

    def test_person_or_continuous_table_boundary_cannot_be_substituted(self):
        for change in (lambda r: r["table"]["identity"]["group"].update(participant_id="person-a"),
                       lambda r: r["spans"].__setitem__(0, exclusion(2099, 2200)),
                       lambda r: r["spans"].__setitem__(0, exclusion(7900, 8003))):
            request = copy.deepcopy(self.request)
            change(request)
            with self.assertRaises(ValueError):
                review.run(request)

    def test_decisions_mutated_during_read_are_refused(self):
        request = self.variant("changed-during-read")
        target = Path(request["curation"]["decisions_path"])
        original_open = Path.open
        class MutatingReader:
            def __init__(self, handle):
                self.handle = handle
                self.changed = False
            def __enter__(self):
                return self
            def __exit__(self, *args):
                self.handle.close()
            def readline(self, *args):
                line = self.handle.readline(*args)
                if not line and not self.changed:
                    self.changed = True
                    with original_open(target, "a", encoding="utf-8") as writer:
                        writer.write("\n")
                return line
        def intercepted(path, *args, **kwargs):
            handle = original_open(path, *args, **kwargs)
            if path == target and not args and kwargs.get("encoding") == "utf-8":
                return MutatingReader(handle)
            return handle
        with patch.object(Path, "open", intercepted), self.assertRaisesRegex(ValueError, "changed during reading"):
            review.run(request)

    def test_source_files_and_worker_closure_remain_unchanged(self):
        self.assertEqual(review.artifacts.digest_file(self.request["source_path"]), self.request["source"]["sha256"])
        self.assertEqual(review.artifacts.digest_file(self.request["curation"]["decisions_path"]), self.request["curation"]["decisions"]["sha256"])
        self.assertEqual(self.hashes, {name: review.artifacts.digest_file(ROOT / "scripts/workers" / name) for name in self.hashes})


if __name__ == "__main__":
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(CardiacCuration)
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    if os.environ.get("BROHN_TEST_OUTPUT") and hasattr(CardiacCuration, "root"):
        save(CardiacCuration.root / "acceptance.json", {"tests": result.testsRun, "passed": result.wasSuccessful(),
            "failures": [(str(test), text) for test, text in result.failures],
            "errors": [(str(test), text) for test, text in result.errors], "worker_hashes": getattr(CardiacCuration, "hashes", {}),
            "scope": "Original generated source through actual stream_extract and cardiac review; R authority and hardware not qualified."})
        print("Evidence:", CardiacCuration.root)
    raise SystemExit(0 if result.wasSuccessful() else 1)
