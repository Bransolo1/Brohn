"""Independent researcher QA: original arithmetic and semantic counterexamples.

No empirical participants or devices. Oracles use rational arithmetic and explicit
sample lists, not the production helper functions or upstream expected outputs.
Run with the prepared methods Python environment (NumPy 2.5.3).
"""
import csv
from fractions import Fraction
import hashlib
import importlib.util
import json
import math
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("brohn_peripheral_independent", ROOT / "scripts/workers/peripheral.py")
WORKER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(WORKER)
G = 9.80665  # Exact standard-gravity conversion factor, not local measured gravity.


class IndependentPeripheral(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="brohn-peripheral-independent-")
        self.root = Path(self.temp.name)
        self.serial = 0

    def tearDown(self):
        self.temp.cleanup()

    def source(self, rows, modality="temperature", unit=None, parameters=None,
               mapping=None, groups=False, artifacts=False):
        self.serial += 1
        path = self.root / f"original-{self.serial}.csv"
        signals = ["T"] if modality == "temperature" else ["X", "Y", "Z"]
        header = ["clock", *signals, *(["person", "visit", "condition", "exposure", "reset"] if groups else [])]
        with path.open("w", newline="", encoding="utf-8") as file:
            writer = csv.writer(file)
            writer.writerow(header)
            writer.writerows(rows)
        metadata = {
            "time_column": "clock", "time_unit": "s", "sampling_rate": 1,
            "value_columns": signals, "unit": unit or ("degC" if modality == "temperature" else "m/s2"),
            "origin": "sample", "origin_statement": "Original synthetic arithmetic; no physical recording.",
            "calibration_source": "Original generator specifies already calibrated quantities; no empirical calibration claim.",
            "sensor_site": "Synthetic signed Cartesian frame; no person or sensor site.",
            "acquisition_filters": "None. These are original generated values.",
            "parameters": parameters or {},
        }
        if modality == "movement":
            metadata.update(axis_labels=["+X right", "+Y forward", "+Z up"], gravity_policy="included")
        else:
            metadata["recording_conditions"] = "Original synthetic values; no room conditions or settling procedure were measured."
        if groups:
            metadata.update(participant_column="person", session_column="visit", condition_column="condition",
                            exposure_column="exposure", segment_column="reset")
        metadata.update(mapping or {})
        request = {"schema": "brohn-worker-request/1.0", "operation": "peripheral", "modality": modality,
                   "format": "csv", "source_path": str(path), "source_hash": hashlib.sha256(path.read_bytes()).hexdigest(),
                   "metadata": metadata}
        if artifacts:
            directory = self.root / f"artifacts-{self.serial}"
            directory.mkdir()
            request["artifact_directory"] = str(directory)
        return request

    def run_source(self, *args, **kwargs):
        request = self.source(*args, **kwargs)
        before = Path(request["source_path"]).read_bytes()
        result = WORKER.run(request)
        self.assertEqual(Path(request["source_path"]).read_bytes(), before)
        self.assertEqual(result["source"]["sha256"], hashlib.sha256(before).hexdigest())
        self.assertFalse(result["quality"]["scientifically_qualified"])
        self.assertFalse(result["quality"]["physical_device_qualified"])
        return result

    def features(self, result, name):
        return [item for item in result["features"] if item["name"] == name]

    def value(self, result, name):
        values = self.features(result, name)
        self.assertEqual(len(values), 1, name)
        return values[0]["value"]

    def threshold(self, **overrides):
        result = {"metric": "temperature_c", "direction": "above", "on": 20, "off": 19,
                  "minimum_duration_s": 1, "source": "Original operational sample-span threshold, not a physiological detector."}
        result.update(overrides)
        return {"threshold": result}

    def test_nonlinear_temperature_sample_and_time_means_have_different_denominators(self):
        result = self.run_source([[0, 1], [1, 2], [2, 4]])
        self.assertAlmostEqual(self.value(result, "temperature_mean"), float(Fraction(7, 3)))
        self.assertEqual(self.value(result, "temperature_time_weighted_mean"), 2.25)
        self.assertAlmostEqual(self.value(result, "temperature_sd"), math.sqrt(Fraction(7, 3)))
        self.assertEqual(self.value(result, "temperature_linear_slope"), 90)
        self.assertEqual(self.value(result, "temperature_endpoint_change"), 3)
        self.assertEqual(self.value(result, "supported_observed_span"), 2)

    def test_allowed_clock_jitter_uses_actual_intervals_for_slope_and_integration(self):
        result = self.run_source([[0, 0], ["0.8", 4], [2, 2]], mapping={"timestamp_tolerance_s": .25})
        t = [Fraction(0), Fraction(4, 5), Fraction(2)]
        values = [Fraction(0), Fraction(4), Fraction(2)]
        mt, mv = sum(t)/3, sum(values)/3
        slope = sum((x-mt)*(y-mv) for x, y in zip(t, values))/sum((x-mt)**2 for x in t)*60
        self.assertAlmostEqual(self.value(result, "temperature_time_weighted_mean"), 2.6)
        self.assertAlmostEqual(self.value(result, "temperature_linear_slope"), float(slope))
        self.assertEqual(self.value(result, "temperature_mean"), 2)
        self.assertEqual(result["quality"]["time_gap_count"], 0)

    def test_temperature_unit_offsets_do_not_change_endpoint_difference(self):
        outputs = []
        for unit, values in [("degC", [-40, 0, 100]), ("K", [233.15, 273.15, 373.15]), ("degF", [-40, 32, 212])]:
            result = self.run_source([[i, value] for i, value in enumerate(values)], unit=unit)
            outputs.append(result)
            self.assertAlmostEqual(self.value(result, "temperature_endpoint_change"), 140)
            self.assertAlmostEqual(self.value(result, "temperature_time_weighted_mean"), 15)
        for result in outputs:
            self.assertAlmostEqual(self.value(result, "temperature_mean"), 20)

    def test_enmo_truncation_precedes_averaging_and_preserves_selected_policy(self):
        rows = [[0, 0, 0, .5], [1, 0, 0, 1.5], [2, 0, 0, .5]]
        truncated = self.run_source(rows, "movement", unit="g", parameters={"enmo": "zero_truncated"})
        untruncated = self.run_source(rows, "movement", unit="g", parameters={"enmo": "untruncated"})
        self.assertAlmostEqual(self.value(truncated, "enmo_mean"), float(Fraction(1, 6)))
        self.assertAlmostEqual(self.value(untruncated, "enmo_mean"), float(Fraction(-1, 6)))
        self.assertEqual([r["enmo_g"] for r in truncated["series"]], [0, .5, 0])
        self.assertEqual(self.features(truncated, "enmo_mean")[0]["negative_policy"], "zero_truncated")

    def test_rotation_of_gravity_has_zero_enmo_but_nonzero_vector_derivative(self):
        # Pure orientation change in this synthetic frame is not translational jerk.
        result = self.run_source([[0, 1, 0, 0], [1, 0, 1, 0], [2, -1, 0, 0], [3, 0, -1, 0]],
                                 "movement", unit="g", parameters={"enmo": "zero_truncated"})
        self.assertEqual(self.value(result, "enmo_mean"), 0)
        self.assertAlmostEqual(self.value(result, "acceleration_magnitude_mean"), G)
        self.assertAlmostEqual(self.value(result, "acceleration_vector_derivative_rms"), G*math.sqrt(2))
        feature = self.features(result, "acceleration_vector_derivative_rms")[0]
        self.assertEqual((feature["interval_count"], feature["unit"]), (3, "m/s3"))
        self.assertIsNone(result["series"][0]["vector_derivative_ms3"])
        self.assertIn("rotation", " ".join(result["limitations"]).lower())

    def test_vector_derivative_uses_actual_differences_not_magnitude_difference(self):
        result = self.run_source([[0, 3, 4, 0], ["0.8", -3, 4, 0], [2, -3, -4, 0]], "movement",
                                 mapping={"timestamp_tolerance_s": .25, "gravity_policy": "removed"})
        expected = math.sqrt((Fraction(15, 2)**2+Fraction(20, 3)**2)/2)
        self.assertEqual(self.value(result, "acceleration_magnitude_mean"), 5)
        self.assertAlmostEqual(self.value(result, "acceleration_vector_derivative_rms"), expected)
        self.assertNotIn("enmo_mean", [f["name"] for f in result["features"]])

    def test_axis_permutation_and_sign_leave_norm_invariant_without_rewriting_source_axes(self):
        original = self.run_source([[0, 3, 4, 12], [1, 4, 0, 3]], "movement")
        changed = self.run_source([[0, -12, 3, -4], [1, -3, 4, 0]], "movement")
        self.assertEqual(self.value(original, "acceleration_magnitude_mean"), 9)
        self.assertEqual(self.value(changed, "acceleration_magnitude_mean"), 9)
        self.assertAlmostEqual(self.value(original, "acceleration_vector_derivative_rms"), math.sqrt(98))
        self.assertEqual(self.value(original, "acceleration_vector_derivative_rms"), self.value(changed, "acceleration_vector_derivative_rms"))
        self.assertEqual(changed["series"][0]["acceleration_x_ms2"], -12)

    def test_return_to_same_identity_is_separate_contiguous_support_not_pooled(self):
        rows = []
        for condition, exposure, values in [("control", "e1", [10, 12]), ("test", "e2", [20, 22]), ("control", "e1", [30, 32])]:
            rows.extend([[i, value, "001", "visit-A", condition, exposure, "reset-A"] for i, value in enumerate(values)])
        result = self.run_source(rows, groups=True)
        means = self.features(result, "temperature_mean")
        self.assertEqual([f["value"] for f in means], [11, 21, 31])
        self.assertEqual(len({f["recording_id"] for f in means}), 3)
        self.assertEqual([f["group"]["condition_id"] for f in means], ["control", "test", "control"])
        self.assertEqual({f["group"]["participant_id"] for f in means}, {"001"})
        self.assertIsNone(result["quality"]["participant_count"])

    def test_declared_reset_and_time_gap_do_not_create_derivatives_between_segments(self):
        result = self.run_source([[0, 0, 0, 0], [1, 1, 0, 0], [10, 1000, 0, 0], [11, 1002, 0, 0]], "movement")
        self.assertEqual([f["value"] for f in self.features(result, "acceleration_vector_derivative_rms")], [1, 2])
        self.assertEqual([r["vector_derivative_ms3"] for r in result["series"]], [None, 1, None, 2])
        self.assertEqual(result["quality"]["missing_nominal_interval_s"], 8)
        self.assertEqual(result["quality"]["supported_observed_span_s"], 2)

    def test_partial_axis_missingness_retains_measured_axes_without_vector_imputation(self):
        result = self.run_source([[0, 0, 0, 1], [1, 0, 0, 1], [2, 2, "NA", 3], [3, 0, 0, 1], [4, 0, 0, 1]], "movement")
        middle = result["series"][2]
        self.assertEqual((middle["acceleration_x_ms2"], middle["acceleration_z_ms2"]), (2, 3))
        self.assertIsNone(middle["acceleration_y_ms2"])
        self.assertIsNone(middle["vector_magnitude_ms2"])
        self.assertFalse(middle["analysis_eligible"])
        self.assertEqual([f["value"] for f in self.features(result, "supported_sample_count")], [2, 2])

    def test_below_threshold_inclusive_entry_and_strict_recovery_are_explicit(self):
        result = self.run_source([[i, x] for i, x in enumerate([23, 20, 19, 22, 23])],
                                 parameters=self.threshold(direction="below", on=20, off=22, minimum_duration_s=2))
        self.assertEqual(result["quality"]["event_count"], 1)
        event = result["events"][0]
        self.assertEqual([event[k] for k in ("time_s", "end_time_s", "recovery_time_s", "observed_span_s", "extreme")], [1, 3, 4, 2, 19])
        self.assertFalse(event["left_censored"])
        self.assertFalse(event["right_censored"])

    def test_missing_recovery_censors_each_excursion_and_never_adds_unobserved_duration(self):
        result = self.run_source([[0, 22], [1, 22], [2, "NA"], [3, 22], [4, 22]], parameters=self.threshold())
        self.assertEqual(result["quality"]["event_count"], 2)
        for event in result["events"]:
            self.assertTrue(event["left_censored"])
            self.assertTrue(event["right_censored"])
            self.assertIsNone(event["recovery_time_s"])
            self.assertEqual(event["observed_span_s"], 1)
        self.assertEqual(sum(f["value"] for f in self.features(result, "declared_threshold_observed_span")), 2)

    def test_minimum_excursion_does_not_count_an_extrapolated_final_sample_cell(self):
        result = self.run_source([[0, 22], [1, 22], [2, 18]], parameters=self.threshold(minimum_duration_s=2))
        self.assertEqual(result["quality"]["event_count"], 0)
        self.assertEqual(self.value(result, "declared_threshold_observed_span"), 0)
        self.assertTrue(result["quality"]["usable"])

    def test_no_usable_event_support_is_unavailable_not_zero_detected_events(self):
        # Zero is a valid negative finding only after some eligible support was examined.
        for rows in [[[0, "NA"], [1, "NA"]], [[0, 22]], [[0, 22], [1, "NA"], [2, 22]]]:
            with self.subTest(rows=rows):
                result = self.run_source(rows, parameters=self.threshold())
                self.assertFalse(result["quality"]["usable"])
                self.assertEqual(result["quality"]["usable_samples"], 0)
                self.assertEqual(result["features"], [])
                self.assertIsNone(result["quality"]["event_count"])

    def test_low_rate_default_is_valid_at_declared_supported_point_one_hz(self):
        result = self.run_source([[0, 20], [10, 21], [20, 22]], mapping={"sampling_rate": .1})
        self.assertTrue(result["quality"]["usable"])
        self.assertEqual(self.value(result, "supported_observed_span"), 20)

    def test_slow_rate_default_repair_does_not_override_explicit_invalid_duration(self):
        request = self.source([[0, 20], [10, 21]], mapping={"sampling_rate": .1}, parameters={"minimum_duration_s": 1})
        with self.assertRaisesRegex(WORKER.InputError, "minimum_duration"):
            WORKER.run(request)

    def test_large_exact_decimal_origin_and_full_artifact_keep_original_clock_and_rows(self):
        # Original string origin cannot be represented as a binary64 integer.
        origin = 9007199254740993123456789
        rows = [[str(origin+i), 20+(i % 2)] for i in range(2003)]
        result = self.run_source(rows, mapping={"time_unit": "sample"}, artifacts=True)
        self.assertEqual(len(result["series"]), 2000)
        artifact = next(a for a in result["artifacts"] if a["kind"] == "physiology-series")
        path = Path(artifact["path"])
        self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(), artifact["sha256"])
        records = [json.loads(line) for line in path.read_text("utf-8").splitlines()]
        self.assertEqual(records[0]["type"], "header")
        self.assertEqual(records[-1]["type"], "complete")
        table = next(r for r in records if r["type"] == "table")
        names = [column["name"] for column in table["columns"]]
        saved = [dict(zip(names, row)) for block in records if block["type"] == "rows" for row in block["rows"]]
        self.assertEqual(len(saved), 2003)
        self.assertEqual(saved[-1]["source_timestamp"], str(origin+2002))
        self.assertEqual(saved[-1]["source_row"], 2003)
        self.assertEqual(saved[-1]["time_s"], 2002)
        self.assertEqual(table["coordinates"]["source_time_origin"], str(origin))
        self.assertEqual(result["quality"]["usable_samples"], 2003)

    def downstream_preview(self, result, kind, value):
        spec = importlib.util.spec_from_file_location("brohn_independent_signal_preview", ROOT / "scripts/workers/signal_preview.py")
        preview = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(preview)
        manifest = next(a for a in result["artifacts"] if a["kind"] == kind)
        records = [json.loads(line) for line in Path(manifest["path"]).read_text("utf-8").splitlines()]
        table = next(r for r in records if r["type"] == "table")
        request = {"selection": {"table_ids": [table["table_id"]], "recording_id": table["identity"]["recording_id"],
                                 "channel": table["identity"]["channel"], "value_column": value, "range": None},
                   "parameters": {"max_bins": 20}}
        # This helper independently verifies the full immutable artifact twice.
        # Receipt/API integration is a separate queued-job/browser acceptance.
        return preview.preview(request, manifest), table

    def test_full_artifact_preview_cannot_connect_gaps_or_plot_ineligible_finite_samples(self):
        result = self.run_source([[0, 20], [1, 21], [2, "NA"], [3, 50], [4, 60], [10, 70], [11, 80],
                                  [12, "NA"], [13, 900]], artifacts=True)
        view, table = self.downstream_preview(result, "physiology-series", "temperature_c")
        self.assertEqual(view["selected_range"]["eligible_value_rows"], 6)
        self.assertEqual([(f["first_x"], f["last_x"]) for f in view["fragments"]], [(0, 1), (3, 4), (10, 11)])
        self.assertEqual(view["fragments"][-1]["break_before"], "declared_clock_cadence_gap")
        self.assertTrue(all(f["rendering"] == "trace" for f in view["fragments"]))
        self.assertEqual(table["support"]["source"]["sampling_rate"], 1)
        self.assertEqual(table["support"]["source"]["channel_quality"]["timestamp_tolerance_s"], .02)
        points = [point for envelope in view["envelopes"] for point in envelope["points"]]
        self.assertEqual(sorted({p["source_sample_index"] for p in points}), [0, 1, 3, 4, 5, 6])
        self.assertEqual(max(p["y"] for p in points), 80)

    def test_event_artifact_has_one_time_axis_and_discrete_points(self):
        result = self.run_source([[i, value] for i, value in enumerate([18, 20, 20, 18, 20, 20])],
                                 parameters=self.threshold(), artifacts=True)
        view, table = self.downstream_preview(result, "physiology-events", "extreme")
        self.assertEqual([c["name"] for c in table["columns"] if c["role"] == "coordinate"], ["time_s"])
        self.assertEqual(view["axis"]["value_unit"], "degC")
        self.assertEqual(view["selected_range"]["eligible_value_rows"], 2)
        self.assertTrue(all(f["rendering"] == "scatter" and f["connection_policy"] == "none" for f in view["fragments"]))
        points = [point for envelope in view["envelopes"] for point in envelope["points"]]
        self.assertEqual([(p["x"], p["y"]) for p in points], [(1, 20), (4, 20)])


if __name__ == "__main__":
    unittest.main(verbosity=2)
