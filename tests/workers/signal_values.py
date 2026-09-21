"""Independent exact-decimal, typed-source, selection and failure oracles."""
import copy
import csv
import hashlib
import importlib.util
import json
import math
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("brohn_values_test", ROOT / "scripts/workers/signal_values.py")
w = importlib.util.module_from_spec(spec)
spec.loader.exec_module(w)


class Values(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="brohn-exact-values-")
        self.folder = Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def request(self, rows=None, axis="time", unit="uS", kind="physiology-series", index_type="integer", retained=True):
        rows = [[float(i), float(i), True, i, "", False] for i in range(137)] if rows is None else rows
        columns = [w.artifacts._column("coordinate", "float64", "Hz" if axis == "frequency" else "s", True, "coordinate"),
                   w.artifacts._column("measure", "float64", unit, True),
                   w.artifacts._column("retained", "boolean", None, True, "support"),
                   w.artifacts._column("source_sample_index", index_type, "sample_index" if index_type == "integer" else None, True, "index" if index_type == "integer" else "label"),
                   w.artifacts._column("note", "string", None, True, "label"),
                   w.artifacts._column("detected", "boolean", None, True, "support")]
        if not retained:
            columns.pop(2)
            rows = [r[:2] + r[3:] for r in rows]
        provenance = {"source_sha256": "a"*64, "engine": {"name": "independent typed fixture", "worker_sha256": "b"*64}, "operation": "physiology", "origin": "sample", "parameters": {"recipe": "fixture-only/1"}}
        with w.artifacts.TableWriter(self.folder, kind, provenance, chunk_rows=17) as writer:
            writer.write_table("exact-table", {"recording_id": "recording-1", "channel": "-1+2", "group": {"participant_id": "original"}}, columns,
                {"axis": axis, "reference": "source-relative", "source_time_origin": "999999999999999999123", "source_time_unit": "ns"},
                {"fixture_only": True}, rows, len(rows))
            manifest = writer.finish()
        table = w.preview.catalog({"page": {"offset": 0, "limit": 100}}, manifest)["tables"][0]
        return {"schema": "brohn-signal-values-request/1.0", "operation": "signal_values_page", "artifact": manifest,
                "verification_receipt": w.artifacts.verify_manifest([manifest]),
                "binding": {"report_id": "report-1", "report_revision": 1, "report_hash": "1"*64, "project_id": "project-1", "catalog_id": "catalog-1", "catalog_revision": 1, "catalog_hash": "2"*64, "selection_hash": "3"*64},
                "table": table, "selection": {"table_id": "exact-table", "recording_id": "recording-1", "channel": "-1+2", "value_column": "measure", "range": None, "row_policy": "all_source_rows"}, "page": {"offset": 0, "limit": 25}}

    def export(self, request, name="values.csv"):
        request = copy.deepcopy(request)
        request.pop("page")
        request.update(operation="signal_values_export", export_path=str(self.folder/name))
        return request

    def read_csv(self, request):
        with Path(request["export_path"]).open(encoding="utf-8", newline="") as stream:
            return list(csv.DictReader(stream))

    def test_complete_export_independent_of_page_and_preserves_original_order(self):
        request = self.request()
        page = w.run(request)
        self.assertEqual(len(page["rows"]), 25)
        self.assertEqual(page["page"]["total_rows"], 137)
        self.assertEqual(page["page"]["next_offset"], 25)
        export = self.export(request)
        receipt = w.run(export)
        rows = self.read_csv(export)
        self.assertEqual([int(r["table_row_index"]) for r in rows], list(range(137)))
        self.assertEqual([float(r["value"]) for r in rows], list(range(137)))
        self.assertEqual(receipt["csv"]["rows"], 137)
        self.assertEqual(hashlib.sha256(Path(export["export_path"]).read_bytes()).hexdigest(), receipt["csv"]["sha256"])

    def test_binary64_roundtrip_including_signed_zero_subnormal_and_adjacent_values(self):
        numbers = [-0.0, math.nextafter(1., 2.), math.nextafter(1., 0.), 5e-324, sys.float_info.max, -1e-200]
        request = self.export(self.request([[float(i), n, True, i, "", False] for i, n in enumerate(numbers)]))
        w.run(request)
        self.assertEqual([float(r["value"]).hex() for r in self.read_csv(request)], [n.hex() for n in numbers])

    def test_missing_retention_is_separate_from_explicit_false(self):
        request = self.request([[0., -0., True, 3, "", False], [1., 2., False, 8, None, True], [None, None, None, None, "\u96ea", None]])
        page = w.run(request)
        stats = page["full_source"]
        self.assertEqual([stats[k] for k in ["rows", "retained_rows", "excluded_retention_rows", "unknown_retention_rows", "eligible_value_rows"]], [3, 1, 1, 1, 1])
        self.assertEqual([r["retention"] for r in page["rows"]], ["retained", "excluded", "unknown"])
        exact = [json.loads(r["exact_record_json"]) for r in page["rows"]]
        self.assertEqual(exact[0]["note"], "")
        self.assertIs(exact[0]["detected"], False)
        self.assertIsNone(exact[1]["note"])
        self.assertEqual(exact[2]["note"], "\u96ea")
        self.assertTrue(page["rows"][2]["coordinate_is_null"])
        self.assertTrue(page["rows"][2]["value_is_null"])

    def test_absent_retention_is_not_invented_true_support(self):
        page = w.run(self.request(retained=False))
        self.assertEqual(page["full_source"]["undeclared_retention_rows"], 137)
        self.assertEqual(page["full_source"]["retained_rows"], 0)
        self.assertEqual(page["rows"][0]["retention"], "not_declared")

    def test_range_is_inclusive_keeps_excluded_rows_and_discloses_null_coordinates(self):
        request = self.request([[2., 9., False, 0, "", False], [1., None, True, 1, "", False], [2., 7., None, 2, "", False], [None, 8., True, 3, "", False]])
        request["selection"]["range"] = [2., 2.]
        result = w.run(request)
        self.assertEqual([r["table_row_index"] for r in result["rows"]], [0, 2])
        self.assertEqual(result["unplaceable_coordinate_rows"], 1)
        self.assertEqual(result["selected_source"]["eligible_value_rows"], 0)
        request["selection"]["range"] = [9., 10.]
        empty = w.run(request)
        self.assertEqual(empty["status"], "empty_range")
        self.assertEqual(empty["full_source"]["rows"], 4)

    def test_page_bound_and_absolute_continuation_do_not_drop_rows(self):
        request = self.request()
        with patch.object(w, "MAX_PAGE_BYTES", 1900):
            first = w.run(request)
            self.assertTrue(first["page"]["byte_limited"])
            self.assertLess(first["page"]["returned"], 25)
            request["page"]["offset"] = first["page"]["next_offset"]
            second = w.run(request)
        self.assertEqual(second["rows"][0]["table_row_index"], first["rows"][-1]["table_row_index"]+1)
        request["page"]["offset"] = 1000
        self.assertEqual(w.run(request)["rows"], [])

    def test_all_allowed_page_sizes(self):
        request = self.request()
        for size in [25, 50, 100]:
            request["page"]["limit"] = size
            self.assertEqual(len(w.run(request)["rows"]), size)
        request["page"]["limit"] = 200
        with self.assertRaises(w.InputError):
            w.run(request)

    def test_time_event_and_frequency_coordinates_keep_native_units(self):
        for axis, unit, kind in [("time", "uV", "physiology-series"), ("event", "ms", "physiology-events"), ("frequency", "ms^2/Hz", "physiology-events")]:
            request = self.request(axis=axis, unit=unit, kind=kind)
            result = w.run(request)
            self.assertEqual(result["table"]["coordinates"]["axis"], axis)
            export = self.export(request, axis+".csv")
            w.run(export)
            row = self.read_csv(export)[0]
            self.assertEqual(row["coordinate_unit"], "Hz" if axis == "frequency" else "s")
            self.assertEqual(row["measure_unit"], unit)
            self.assertEqual(row["source_time_origin"], "999999999999999999123")

    def test_spreadsheet_formula_text_never_exempts_name_inferred_index(self):
        request = self.request([[0., 1., True, "=1+2", "", False]], index_type="string")
        with self.assertRaisesRegex(w.InputError, "integer index"):
            w.run(request)
        export = self.export(request)
        with self.assertRaises(w.InputError):
            w.run(export)
        self.assertFalse(Path(export["export_path"]).exists())

    def test_text_formula_protection_and_original_json_keep_unicode_and_whitespace(self):
        hostile = ["=1+2", "-1+2", "+2", "@SUM(A1)", "\t=3", "\r=4", "\n=5", "  =6", "\u96ea\U0001f600"]
        for value in hostile[:-1]:
            self.assertEqual(w.spreadsheet_text(value), "'"+value)
        export = self.export(self.request([[0., -2., True, 4, hostile[-1], False]]))
        w.run(export)
        row = self.read_csv(export)[0]
        self.assertEqual(row["channel"], "'-1+2")
        self.assertEqual(row["value"], "-2.0")
        self.assertEqual(json.loads(row["identity_json"])["channel"], "-1+2")
        self.assertEqual(json.loads(row["exact_record_json"])["note"], hostile[-1])

    def test_wrong_source_receipt_catalog_channel_measure_and_clock_rejected(self):
        request = self.request()
        mutations = [lambda r:r["artifact"].update(sha256="0"*64), lambda r:r["table"].update(rows=999),
            lambda r:r["selection"].update(channel="other"), lambda r:r["selection"].update(value_column="source_sample_index"),
            lambda r:r["table"]["coordinates"].update(source_time_origin="0")]
        for mutate in mutations:
            bad = copy.deepcopy(request)
            mutate(bad)
            with self.assertRaises(w.InputError):
                w.run(bad)

    def test_missing_and_tampered_artifact_remove_new_export(self):
        request = self.export(self.request())
        source = Path(request["artifact"]["path"])
        source.write_bytes(source.read_bytes()+b" ")
        with self.assertRaises(w.InputError):
            w.run(request)
        self.assertFalse(Path(request["export_path"]).exists())
        source.unlink()
        with self.assertRaises(Exception):
            w.run(request)
        self.assertFalse(Path(request["export_path"]).exists())

    def test_existing_export_is_not_replaced_or_removed(self):
        request = self.export(self.request())
        path = Path(request["export_path"])
        path.write_bytes(b"existing important bytes")
        with self.assertRaises(w.InputError):
            w.run(request)
        self.assertEqual(path.read_bytes(), b"existing important bytes")

    def test_export_budget_failure_leaves_no_partial_complete_file(self):
        request = self.export(self.request())
        with patch.object(w, "MAX_EXPORT_BYTES", 1000), self.assertRaisesRegex(w.InputError, "narrower range"):
            w.run(request)
        self.assertFalse(Path(request["export_path"]).exists())

    def test_receipt_missing_directory_does_not_create_csv(self):
        request = self.export(self.request())
        path = self.folder/"request.json"
        path.write_text(json.dumps(request), encoding="utf-8")
        child = subprocess.run([sys.executable, str(ROOT/"scripts/workers/signal_values.py"), "--request", str(path), "--output", str(self.folder/"absent"/"result.json")], capture_output=True)
        self.assertNotEqual(child.returncode, 0)
        self.assertFalse(Path(request["export_path"]).exists())

    def test_empty_table_still_requires_declared_boolean_retention(self):
        request = self.request(rows=[])
        path = Path(request["artifact"]["path"])
        records = list(w.artifacts._read_records(path))
        declaration = next(r for r in records if r.get("type") == "table")
        # Build through the writer so all source receipts remain internally valid.
        bad = copy.deepcopy(declaration["columns"])
        retained = next(c for c in bad if c["name"] == "retained")
        retained.update(type="string", role="label")
        dest = self.folder/"empty-other"; dest.mkdir()
        provenance = {"source_sha256":"a"*64,"engine":{"name":"typed empty fixture","worker_sha256":"b"*64},"operation":"physiology","origin":"sample","parameters":{}}
        with w.artifacts.TableWriter(dest,"physiology-series",provenance) as writer:
            writer.write_table("exact-table",declaration["identity"],bad,declaration["coordinates"],{},[],0)
            manifest = writer.finish()
        request["artifact"] = manifest
        request["verification_receipt"] = w.artifacts.verify_manifest([manifest])
        request["table"] = w.preview.catalog({"page":{"offset":0,"limit":100}},manifest)["tables"][0]
        with self.assertRaisesRegex(w.InputError,"boolean support"):
            w.run(request)


if __name__ == "__main__":
    unittest.main()
