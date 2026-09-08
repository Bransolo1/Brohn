"""Independent original temperature/acceleration oracles and bounded I/O tests."""
import copy
import csv
import importlib.util
import json
import math
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("peripheral", ROOT / "scripts/workers/peripheral.py")
worker = importlib.util.module_from_spec(spec); spec.loader.exec_module(worker)


def fixture(directory, modality="temperature", rows=None, rate=1, unit=None, parameters=None, identities=False):
    channels = ["temperature"] if modality == "temperature" else ["axis_x", "axis_y", "axis_z"]
    header = ["time", *channels, *(["person", "visit", "segment"] if identities else [])]
    if rows is None: rows = [[i, 20+i] for i in range(5)] if modality == "temperature" else [[i, 0, 0, 1] for i in range(5)]
    path = directory / "original.csv"
    with path.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.writer(stream); writer.writerow(header); writer.writerows(rows)
    m = {"time_column": "time", "time_unit": "s", "sampling_rate": rate, "value_columns": channels,
         "unit": unit or ("degC" if modality == "temperature" else "g"), "origin": "sample",
         "origin_statement": "Original numerical fixture; no person/device recording.", "calibration_source": "Original generator declares calibrated source values.",
         "sensor_site": "Original synthetic location", "acquisition_filters": "No source filters", "parameters": parameters or {}}
    if modality == "movement": m.update(axis_labels=["positive right", "positive anterior", "positive up"], gravity_policy="included")
    else: m["recording_conditions"] = "Original numerical generator; no ambient exposure, contact or equilibration period."
    if identities: m.update(participant_column="person", session_column="visit", segment_column="segment")
    artifacts = directory / "artifacts"; artifacts.mkdir(exist_ok=True)
    return {"schema": "brohn-worker-request/1.0", "operation": "peripheral", "modality": modality, "format": "csv", "source_path": str(path),
            "source_hash": worker.digest_file(path), "metadata": m, "artifact_directory": str(artifacts)}


class PeripheralTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="brohn-peripheral-"); self.root = Path(self.temp.name)
    def tearDown(self): self.temp.cleanup()
    def feature(self, output, name): return next(f["value"] for f in output["features"] if f["name"] == name)
    def artifact(self, output, kind):
        manifest = next(a for a in output["artifacts"] if a["kind"] == kind)
        module, _ = worker.artifact_module(); tables = []; rows = []
        def collect(table_id, offset, chunk):
            table = next(t for t in tables if t["table_id"] == table_id)
            names = [c["name"] for c in table["columns"]]
            rows.extend(dict(zip(names, r)) for r in chunk)
        module.verify_artifact(manifest, self.root/"artifacts", on_table=lambda t: tables.append(t), on_rows=collect)
        return manifest, tables, rows
    def test_temperature_independent_linear_and_conversion_oracle(self):
        for unit, values in (("degC", [20,21,22,23,24]), ("K", [293.15,294.15,295.15,296.15,297.15]), ("degF", [68,69.8,71.6,73.4,75.2])):
            request = fixture(self.root, rows=[[i,v] for i,v in enumerate(values)], unit=unit)
            result = worker.run(request)
            self.assertAlmostEqual(self.feature(result, "temperature_mean"), 22)
            self.assertAlmostEqual(self.feature(result, "temperature_sd"), math.sqrt(2.5))
            self.assertAlmostEqual(self.feature(result, "temperature_linear_slope"), 60)
            self.assertAlmostEqual(self.feature(result, "temperature_time_weighted_mean"), 22)
            self.assertAlmostEqual(self.feature(result, "temperature_endpoint_change"), 4)
            self.assertIsNone(result["quality"]["event_count"])
    def test_static_gravity_and_linear_acceleration_oracles(self):
        result = worker.run(fixture(self.root, "movement", parameters={"enmo": "zero_truncated"}))
        self.assertAlmostEqual(self.feature(result, "acceleration_magnitude_mean"), 9.80665)
        self.assertEqual(self.feature(result, "acceleration_vector_derivative_rms"), 0)
        self.assertEqual(self.feature(result, "enmo_mean"), 0)
        request = fixture(self.root, "movement", [[i, 2*i, 0, 0] for i in range(5)], unit="m/s2")
        request["metadata"]["gravity_policy"] = "removed"
        result = worker.run(request)
        self.assertAlmostEqual(self.feature(result, "acceleration_x_rms"), math.sqrt(24))
        self.assertEqual(self.feature(result, "acceleration_vector_derivative_rms"), 2)
        self.assertNotIn("enmo_mean", [f["name"] for f in result["features"]])
    def test_enmo_negative_policy_is_explicit_and_not_reapplied_to_removed_gravity(self):
        rows = [[i,0,0,.5] for i in range(5)]
        request = fixture(self.root, "movement", rows, parameters={"enmo": "untruncated"})
        self.assertEqual(self.feature(worker.run(request), "enmo_mean"), -.5)
        request["metadata"]["parameters"]["enmo"] = "zero_truncated"
        self.assertEqual(self.feature(worker.run(request), "enmo_mean"), 0)
        request["metadata"]["gravity_policy"] = "removed"
        with self.assertRaisesRegex(worker.InputError, "gravity-included"): worker.run(request)
    def test_opt_in_threshold_uses_observed_sample_span_and_recovery(self):
        h = {"metric":"temperature_c", "direction":"above", "on":22, "off":21, "minimum_duration_s":1, "source":"Original operational threshold, no physiological classification."}
        result = worker.run(fixture(self.root, rows=[[i,v] for i,v in enumerate([20,22,23,21,20,24,24])], parameters={"threshold":h}))
        self.assertEqual(result["quality"]["event_count"], 2)
        first, last = result["events"]
        self.assertEqual((first["time_s"],first["end_time_s"],first["recovery_time_s"],first["observed_span_s"]),(1,3,4,2))
        self.assertFalse(first["left_censored"]); self.assertFalse(first["right_censored"])
        self.assertTrue(last["right_censored"])
        self.assertEqual(self.feature(result, "declared_threshold_observed_span"), 3)
    def test_missing_gap_and_explicit_segment_boundaries_never_pool(self):
        rows = [[0,20,"p","v","first"],[1,22,"p","v","first"],[2,"NA","p","v","first"],
                [3,30,"p","v","first"],[4,32,"p","v","first"],[10,40,"p","v","first"],[11,42,"p","v","first"],
                [0,50,"p","v","reset"],[1,52,"p","v","reset"],[0,60,"q","v","reset"],[1,62,"q","v","reset"]]
        result = worker.run(fixture(self.root, rows=rows, identities=True))
        means = [f["value"] for f in result["features"] if f["name"] == "temperature_mean"]
        self.assertEqual(means, [21,31,41,51,61])
        self.assertEqual(result["quality"]["recording_count"],3)
        self.assertEqual(result["quality"]["time_gap_count"],1)
        self.assertEqual(result["quality"]["invalid_samples"],1)
        self.assertEqual(result["quality"]["supported_observed_span_s"],5)
        self.assertIsNone(result["quality"]["participant_count"])
        self.assertEqual(result["features"][-1]["group"]["participant_id"],"q")
    def test_listwise_axis_missing_and_nonfinite_are_retained_not_zero(self):
        result = worker.run(fixture(self.root,"movement",[[0,0,0,1],[1,0,0,1],[2,"NaN",0,1],[3,0,"Inf",1],[4,0,0,1],[5,0,0,1]]))
        self.assertEqual(result["quality"]["invalid_samples"],2)
        self.assertIsNone(result["series"][2]["acceleration_x_ms2"])
        self.assertFalse(result["series"][2]["analysis_eligible"])
        self.assertIsNone(result["series"][2]["vector_magnitude_ms2"])
        self.assertEqual(result["series"][2]["acceleration_z_ms2"],9.80665)
        self.assertEqual(len([f for f in result["features"] if f["name"]=="acceleration_vector_derivative_rms"]),2)
    def test_threshold_never_bridges_missing_or_clock_gap(self):
        h={"metric":"temperature_c","direction":"above","on":20,"off":19,"minimum_duration_s":2,"source":"Original two-second operational span."}
        rows=[[0,22],[1,22],[2,"NA"],[3,22],[4,22],[10,22],[11,22]]
        result=worker.run(fixture(self.root,rows=rows,parameters={"threshold":h}))
        self.assertEqual(result["quality"]["event_count"],0)
        self.assertEqual(result["quality"]["supported_observed_span_s"],3)
    def test_full_threshold_events_survive_the_display_cap(self):
        h={"metric":"temperature_c","direction":"above","on":20,"off":19,"minimum_duration_s":1,"source":"Original operational event-cap fixture."}
        rows=[[i,[22,22,18][i%3]] for i in range(6303)]
        result=worker.run(fixture(self.root,rows=rows,parameters={"threshold":h}))
        self.assertEqual(result["quality"]["event_count"],2101)
        self.assertEqual(len(result["events"]),2000)
        manifest,_,events=self.artifact(result,"physiology-events")
        self.assertEqual(manifest["rows"],2101);self.assertEqual(len(events),2101)
        self.assertEqual(events[-1]["source_end_row"],6302)
        self.assertEqual(self.feature(result,"declared_threshold_excursion_count"),2101)
        self.assertEqual(self.feature(result,"declared_threshold_observed_span"),2101)
    def test_rotation_affects_vector_derivative_without_inventing_translation(self):
        rows=[[i,*axes] for i,axes in enumerate([(1,0,0),(0,1,0),(-1,0,0),(0,-1,0),(1,0,0)])]
        result=worker.run(fixture(self.root,"movement",rows,parameters={"enmo":"untruncated"}))
        self.assertEqual(self.feature(result,"enmo_mean"),0)
        self.assertAlmostEqual(self.feature(result,"acceleration_vector_derivative_rms"),9.80665*math.sqrt(2))
        self.assertTrue(any("rotation" in text for text in result["limitations"]))
    def test_full_typed_artifacts_preserve_clock_text_after_preview_cap(self):
        origin=9007199254740993
        request=fixture(self.root,rows=[[str(origin+i*1000000000),30] for i in range(2101)])
        request["metadata"]["time_unit"]="ns"
        result=worker.run(request)
        self.assertEqual(len(result["series"]),2000)
        manifest,tables,rows=self.artifact(result,"physiology-series")
        self.assertEqual(manifest["rows"],2101)
        self.assertEqual(rows[0]["source_timestamp"],str(origin))
        self.assertEqual(rows[-1]["source_row"],2101)
        self.assertEqual(rows[-1]["time_s"],2100)
        self.assertEqual(tables[0]["coordinates"]["source_time_origin"],str(origin))
        events,_,event_rows=self.artifact(result,"physiology-events")
        self.assertEqual(events["rows"],0);self.assertEqual(event_rows,[])
        self.assertEqual(self.feature(result,"supported_sample_count"),2101)
    def test_short_and_physically_invalid_segments_have_explicit_failure_support(self):
        result=worker.run(fixture(self.root,rows=[[0,20],[1,-300],[2,20]]))
        self.assertFalse(result["quality"]["usable"])
        self.assertEqual(result["quality"]["invalid_samples"],1)
        self.assertEqual(result["quality"]["insufficient_duration_samples"],2)
        self.assertEqual(result["features"],[])
        self.assertEqual(result["series"][1]["reason"],"below_absolute_zero")
        self.assertEqual(len(result["segments"]),3)
    def test_malformed_units_identity_calibration_and_typed_values_fail(self):
        request=fixture(self.root)
        mutations=[lambda r:r["metadata"].update(unit="V"),lambda r:r["metadata"].update(calibration_source=""),
                   lambda r:r["metadata"].update(sampling_rate=True),lambda r:r["metadata"].update(participant_column="temperature"),
                   lambda r:r["metadata"].update(value_columns=["temperature","time"]),lambda r:r["metadata"].update(extra=True),
                   lambda r:r.update(modality="eog"),lambda r:r.update(source_hash="0"*64)]
        for mutate in mutations:
            bad=copy.deepcopy(request);mutate(bad)
            with self.subTest(bad=bad),self.assertRaises(worker.InputError): worker.run(bad)
        for token in ["true","false","not-a-number"]:
            with self.subTest(token=token),self.assertRaises(worker.InputError): worker.run(fixture(self.root,rows=[[0,20],[1,token]]))
    def test_reversed_duplicate_irregular_and_nonfinite_clock_fail(self):
        for rows in [[[0,20],[0,21]],[[1,20],[0,21]],[[0,20],[.6,21]],[[0,20],["NaN",21]]]:
            with self.subTest(rows=rows),self.assertRaises(worker.InputError):worker.run(fixture(self.root,rows=rows))
    def test_parameter_conflict_and_invalid_threshold_are_rejected(self):
        request=fixture(self.root);request["parameters"]={"minimum_duration_s":2}
        with self.assertRaisesRegex(worker.InputError,"conflict"):worker.run(request)
        request=fixture(self.root);request["parameters"]={"recipe":worker.RECIPES["temperature"],"minimum_duration_s":1,"threshold":None}
        self.assertTrue(worker.run(request)["quality"]["usable"])
        request["metadata"]["parameters"]={"threshold":{"metric":"temperature_c","direction":"above","on":20,"off":21,"minimum_duration_s":1,"source":"Declared"}}
        request.pop("parameters")
        with self.assertRaisesRegex(worker.InputError,"hysteresis"):worker.run(request)
    def test_actual_cli_envelope_hashes_and_overwrite_protection(self):
        request=fixture(self.root);path=self.root/"request.json";path.write_text(json.dumps(request),encoding="utf-8")
        output=self.root/"result.json"
        process=subprocess.run([sys.executable,str(ROOT/"scripts/workers/peripheral.py"),"--request",str(path),"--output",str(output)],capture_output=True,text=True)
        self.assertEqual(process.returncode,0,process.stderr)
        result=json.loads(output.read_text());self.assertEqual(result["source"]["sha256"],request["source_hash"])
        self.assertEqual(result["engine"]["worker_sha256"],worker.digest_file(ROOT/"scripts/workers/peripheral.py"))
        original=Path(request["source_path"]).read_bytes()
        process=subprocess.run([sys.executable,str(ROOT/"scripts/workers/peripheral.py"),"--request",str(path),"--output",request["source_path"]],capture_output=True,text=True)
        self.assertNotEqual(process.returncode,0);self.assertEqual(Path(request["source_path"]).read_bytes(),original)
    def test_bounded_sources_do_not_silently_truncate(self):
        request=fixture(self.root);old=worker.MAX_ROWS
        try:
            worker.MAX_ROWS=3
            with self.assertRaisesRegex(worker.InputError,"bound"):worker.run(request)
        finally:worker.MAX_ROWS=old
    def test_actual_cli_failure_retains_target_modality_and_actionable_reason(self):
        request=fixture(self.root,"movement",[[0,0,0,1],[1,0,0,1],[0,0,0,1]])
        path=self.root/"request.json";path.write_text(json.dumps(request),encoding="utf-8");output=self.root/"error.json"
        process=subprocess.run([sys.executable,str(ROOT/"scripts/workers/peripheral.py"),"--request",str(path),"--output",str(output)],capture_output=True,text=True)
        result=json.loads(output.read_text())
        self.assertNotEqual(process.returncode,0);self.assertEqual(result["modality"],"movement")
        self.assertEqual(result["status"],"error");self.assertIn("duplicated/reversed",result["error"]["message"])
        self.assertEqual(result["artifacts"],[])


if __name__=="__main__":unittest.main()
