"""Independent literals/integer oracle plus bounded refusal/component evidence."""
from __future__ import annotations
from dataclasses import FrozenInstanceError
from decimal import Decimal, getcontext
from fractions import Fraction
import hashlib
import json
from pathlib import Path
import sys
import time
import unittest

from clock_test_support import ROOT,fresh_output
import clock_affine as component


def same_pair(actual, numerator, denominator=1):
    # Independent integer cross multiplication; expected fixtures do not call
    # the component parser, Fraction reducer or affine implementation.
    n, d = int(actual["numerator"]), int(actual["denominator"])
    return d > 0 and n*denominator == numerator*d


def build(x0="10", x1="20", y0="100", y1="110", source=None, reference=None):
    return component.build_affine([{"source": x0, "reference": y0}, {"source": x1, "reference": y1}],
                                  source or {"unit": "s"}, reference or {"unit": "s"})


class ExactAffineTests(unittest.TestCase):
    def test_01_known_translation_and_literal_nonzero_residual(self):
        m = build(); manifest = m.manifest()
        self.assertTrue(same_pair(manifest["scale"], 1));self.assertTrue(same_pair(manifest["offset_seconds"], 90))
        p = component.map_position(m, "15")
        self.assertTrue(same_pair(p["mapped_reference_seconds"], 105))
        self.assertTrue(same_pair(p["mapped_relative_to_reference_anchor_seconds"], 5))
        c = component.check_event(m, "15", "105.125")
        self.assertTrue(same_pair(c["signed_mapped_minus_reference_residual_seconds"], -1, 8))
        self.assertEqual(c["display_approx_residual_seconds"], "-0.125")
        self.assertFalse(c["refit"]);self.assertEqual(c["uncertainty"], "unknown")

    def test_02_nonunit_drift_mixed_milliseconds_and_seconds(self):
        m = build("1000", "9000", "2", "10.0008", {"unit": "ms"})
        self.assertTrue(same_pair(m.manifest()["scale"], 10001, 10000))
        self.assertTrue(same_pair(m.manifest()["offset_seconds"], 9999, 10000))
        self.assertTrue(same_pair(component.map_position(m, "5000")["mapped_reference_seconds"], 15001, 2500))
        c = component.check_event(m, "5000", "6.0006")
        self.assertTrue(same_pair(c["signed_mapped_minus_reference_residual_seconds"], -1, 5000))

    def test_03_ticks_and_microseconds_preserve_original_lexemes(self):
        m = build("+008000.0e0", "16000", "2000000", "4000000",
                  {"unit": "ticks", "seconds_per_tick": "+0.0001250"}, {"unit": "us"})
        p = component.map_position(m, "+0012000.0e0")
        self.assertTrue(same_pair(p["source_seconds"], 3, 2));self.assertTrue(same_pair(p["mapped_reference_seconds"], 3))
        self.assertEqual(p["source_lexeme"], "+0012000.0e0")
        self.assertEqual(m.manifest()["anchors"][0]["source_lexeme"], "+008000.0e0")
        self.assertEqual(m.manifest()["source_clock"]["seconds_per_tick_lexeme"], "+0.0001250")

    def test_04_huge_nanosecond_epoch_with_microsecond_drift(self):
        m = build("9007199254740993000000", "9007199254740993002000",
                  "1700000000.000000001", "1700000000.000003001", {"unit": "ns"})
        self.assertTrue(same_pair(m.manifest()["scale"], 3, 2))
        p = component.map_position(m, "9007199254740993001000")
        self.assertTrue(same_pair(p["mapped_reference_seconds"], 1700000000000001501, 1_000_000_000))
        self.assertTrue(same_pair(p["mapped_relative_to_reference_anchor_seconds"], 3, 2_000_000))
        self.assertEqual(p["display_approx_relative_to_reference_anchor_seconds"], "0.0000015")

    def test_05_relative_approximation_keeps_subms_difference_when_absolute_rounds(self):
        base = "1" + "0"*99
        m = build(base+".0000", base+".0010", base+".0000", base+".0010")
        a, b = component.map_position(m, base+".0001"), component.map_position(m, base+".0002")
        self.assertEqual(a["display_approx_seconds"], b["display_approx_seconds"])
        self.assertNotEqual(a["mapped_reference_seconds"], b["mapped_reference_seconds"])
        self.assertEqual(a["display_approx_relative_to_reference_anchor_seconds"], "0.0001")
        self.assertEqual(b["display_approx_relative_to_reference_anchor_seconds"], "0.0002")

    def test_06_closed_endpoints_no_extrapolation_or_clamping(self):
        m = build()
        self.assertTrue(same_pair(component.map_position(m, "10")["mapped_reference_seconds"], 100))
        self.assertTrue(same_pair(component.map_position(m, "20")["mapped_reference_seconds"], 110))
        for token in ("9.999999999999999999999999999999999999", "20.00000000000000000000000000000000001"):
            with self.subTest(token=token), self.assertRaises(component.ArithmeticInputError):component.map_position(m, token)
        self.assertIn("start-inclusive/end-exclusive", m.manifest()["data_window_selection"])

    def test_07_defining_anchors_zero_only_by_construction(self):
        m = build()
        for x, y in (("10", "100"), ("20", "110")):
            self.assertTrue(same_pair(component.check_event(m, x, y)["signed_mapped_minus_reference_residual_seconds"], 0))
        c = component.check_event(m, "15", "99")
        self.assertFalse(c["reference_within_anchor_span"])
        self.assertTrue(same_pair(c["signed_mapped_minus_reference_residual_seconds"], 6))
        self.assertEqual(m.manifest()["physical_synchronization"], "not_established")
        with self.assertRaises(component.ArithmeticInputError):component.check_event(m, "21", "111")

    def test_08_negative_coordinates_and_signed_zero_preserved(self):
        m = build("-2", "-1", "-6", "-3")
        self.assertTrue(same_pair(component.map_position(m, "-1.5")["mapped_reference_seconds"], -9, 2))
        m = build("-0.00", "1", "+0", "2")
        self.assertEqual(m.manifest()["anchors"][0]["source_lexeme"], "-0.00")
        self.assertTrue(same_pair(component.map_position(m, "-0")["mapped_reference_seconds"], 0))

    def test_09_every_registered_standard_unit_has_exact_scale(self):
        for unit, count in (("s", "1"), ("ms", "1000"), ("us", "1000000"), ("ns", "1000000000")):
            m = build("0", count, "0", "1", {"unit": unit})
            self.assertTrue(same_pair(m.manifest()["scale"], 1));self.assertTrue(same_pair(m.manifest()["source_span_seconds"], 1))

    def test_10_parser_matches_independent_decimal_ratio_and_envelope(self):
        valid = ["0", "-0.000", "+001.2300e-2", ".5", "5.", "1E+100", "1e-100", "9.9e100", "00100e-2",
                 "0.000"+"1"+"0"*100, "0e100"]
        for token in valid:
            with self.subTest(token=token):
                actual = component.parse_decimal(token);expected = Decimal(token).as_integer_ratio()
                self.assertEqual((actual.numerator, actual.denominator), expected)
        for token in ("0e-101", "1e-101", "1e101", "0.000e-100"):
            with self.subTest(token=token), self.assertRaises(component.ArithmeticInputError):component.parse_decimal(token)

    def test_11_nondecimal_and_binary_values_are_refused(self):
        for value in (True, False, 1, 1.0, float('nan'), float('inf'), None, {}, [], b"1", "", " ", " 1", "1 ", "NaN", "Infinity", "-inf", "+", ".", "1_000", "1/2", "0x1", "1,2", "1.2.3", "1\n", "\uff11", "\u0661", "1\x00"):
            with self.subTest(value=repr(value)), self.assertRaises(component.ArithmeticInputError):component.parse_decimal(value)

    def test_12_digit_exponent_limits_refuse_before_large_powers(self):
        for token in ("1"*121, "0"*121, "1e1000", "1e0001", "1e+221", "1e-221", "1e"+"9"*115):
            with self.subTest(token=token), self.assertRaises(component.ArithmeticInputError):component.parse_decimal(token)
        token = "0."+"0"*100+"1e101"
        self.assertEqual(component.parse_decimal(token), 1)

    def test_13_unsupported_units_scales_and_extra_fields_refused(self):
        for clock in (None, {}, {"unit": True}, {"unit": "seconds"}, {"unit": "tick"}, {"unit": "\u00b5s"},
                      {"unit": "ticks"}, {"unit": "ticks", "seconds_per_tick": "0"}, {"unit": "ticks", "seconds_per_tick": "-1"},
                      {"unit": "ticks", "seconds_per_tick": True}, {"unit": "s", "seconds_per_tick": "2"}, {"unit": "s", "id": "not-a-source-check"}):
            with self.subTest(clock=clock), self.assertRaises(component.ArithmeticInputError):
                component.build_affine([{"source": "0", "reference": "0"}, {"source": "1", "reference": "1"}],clock,{"unit": "s"})

    def test_14_exactly_two_unambiguous_ordered_numeric_pairs(self):
        for args in (("1", "1.0", "0", "1"), ("2", "1", "0", "1"), ("0", "1", "1", "1.00"), ("0", "1", "2", "1")):
            with self.subTest(args=args), self.assertRaises(component.ArithmeticInputError):build(*args)
        for anchors in ([], [{"source": "0", "reference": "0"}], [None, None],
                        [{"source": "0", "reference": "0", "event_id": "unchecked"}, {"source": "1", "reference": "1"}],
                        [{"source": "0", "reference": "0"}]*3):
            with self.subTest(anchors=anchors), self.assertRaises(component.ArithmeticInputError):component.build_affine(anchors,{"unit":"s"},{"unit":"s"})

    def test_15_one_day_operational_duration_on_both_clocks(self):
        m = build("0", "86400", "0", "86400")
        self.assertTrue(same_pair(component.map_position(m, "86400")["mapped_reference_seconds"], 86400))
        for args in (("0", "86400.0000001", "0", "1"), ("0", "1", "0", "86400.0000001")):
            with self.assertRaises(component.ArithmeticInputError):build(*args)
        self.assertTrue(same_pair(build("0", "1e-100", "0", "1").manifest()["scale"], 10**100))

    def test_16_exact_outputs_reduced_and_bounded(self):
        m = build("0", "3", "0", "1");p=component.map_position(m,"1")
        self.assertEqual(p["mapped_reference_seconds"],{"numerator":"1","denominator":"3"})
        self.assertEqual(p["display_approx_seconds"],"0."+"3"*34)
        self.assertLess(len(json.dumps(p)),component.MAX_POINT_BYTES)
        with self.assertRaises(component.ArithmeticInputError):component._pair(Fraction(10**2048))
        with self.assertRaises(component.ArithmeticInputError):component._pair(Fraction(1,10**2048))
        with self.assertRaises(component.ArithmeticInputError):component._output({"oversized":"x"*(64*1024)},64*1024)

    def test_17_immutable_map_not_mutable_inputs_or_serialized_manifest(self):
        anchors=[{"source":"0","reference":"0"},{"source":"2","reference":"4"}];clock={"unit":"s"}
        m=component.build_affine(anchors,clock,clock);anchors[1]["source"]="200";clock["unit"]="ns"
        with self.assertRaises(FrozenInstanceError):m._scale=Fraction(99)
        with self.assertRaises(FrozenInstanceError):m._anchors[0].source_s=Fraction(99)
        manifest=m.manifest();manifest["anchors"][1]["source_lexeme"]="200"
        self.assertTrue(same_pair(component.map_position(m,"1")["mapped_reference_seconds"],2))
        with self.assertRaises(component.ArithmeticInputError):component.map_position(manifest,"1")
        with self.assertRaises(component.ArithmeticInputError):component.AffineMap()

    def test_18_streaming_points_do_not_reparse_or_serialize_map(self):
        m=build("0","100","0","200");original_parse=component.parse_decimal;original_manifest=component.AffineMap.manifest;calls=[]
        def count(token):calls.append(token);return original_parse(token)
        def refused(_):raise AssertionError("Manifest was rebuilt for a point")
        component.parse_decimal=count;component.AffineMap.manifest=refused
        try:
            for n in range(101):self.assertTrue(same_pair(component.map_position(m,str(n))["mapped_reference_seconds"],2*n))
            self.assertEqual(len(calls),101)
        finally:component.parse_decimal=original_parse;component.AffineMap.manifest=original_manifest

    def test_19_caller_decimal_context_is_unchanged_and_does_not_change_arithmetic(self):
        before=getcontext().copy();getcontext().prec=2
        try:
            m=build("0","3","0","1");p=component.map_position(m,"1")
            self.assertEqual(p["display_approx_seconds"],"0."+"3"*34);self.assertEqual(getcontext().prec,2)
        finally:
            from decimal import setcontext
            setcontext(before)

    def test_20_independent_integer_crossproduct_oracle_unequal_scales(self):
        for x0,x1,y0,y1 in ((-47,91,3,701),(1100,9201,-210,557),(0,99991,2,5)):
            # Integer source milliseconds and reference microseconds; independent
            # common-denominator formula avoids component conversion/reducer.
            m=build(str(x0),str(x1),str(y0),str(y1),{"unit":"ms"},{"unit":"us"})
            for x in (x0,(x0+x1)//2,x1):
                expected_n=y0*(x1-x0)+(x-x0)*(y1-y0);expected_d=(x1-x0)*1_000_000
                self.assertTrue(same_pair(component.map_position(m,str(x))["mapped_reference_seconds"],expected_n,expected_d))

    def test_21_caller_rounding_traps_do_not_break_approximate_display(self):
        from decimal import Inexact, Rounded, setcontext
        before=getcontext().copy();getcontext().traps[Inexact]=True;getcontext().traps[Rounded]=True
        try:
            m=build("0","3","0","1");p=component.map_position(m,"1")
            self.assertEqual(p["mapped_reference_seconds"],{"numerator":"1","denominator":"3"})
            self.assertEqual(p["display_approx_seconds"],"0."+"3"*34)
            self.assertTrue(getcontext().traps[Inexact]);self.assertTrue(getcontext().traps[Rounded])
        finally:setcontext(before)


if __name__ == "__main__":
    destination=fresh_output()
    destination.mkdir(exist_ok=False)
    suite=unittest.defaultTestLoader.loadTestsFromTestCase(ExactAffineTests)
    with (destination/"tests.log").open("w",encoding="utf-8") as log:
        result=unittest.TextTestRunner(stream=log,verbosity=2).run(suite)
    # This receipt is a component measurement, not a complete artifact reader.
    start=time.perf_counter();m=build("0","1000","0","1000.1")
    for i in range(10_000):component.map_position(m,str(i%1001))
    benchmark=time.perf_counter()-start
    examples={"offset":build().manifest(),"drift":build("1000","9000","2","10.0008",{"unit":"ms"}).manifest(),
              "held_out_nonzero":component.check_event(build(),"15","105.125")}
    (destination/"examples.json").write_text(json.dumps(examples,indent=2,allow_nan=False),encoding="utf-8")
    receipt={"passed":result.wasSuccessful(),"test_groups":result.testsRun,"failures":len(result.failures),"errors":len(result.errors),
             "source_sha256":hashlib.sha256(Path(component.__file__).read_bytes()).hexdigest(),
             "test_sha256":hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
             "mapped_points":10_000,"mapping_seconds":benchmark,"new_jobs":0,
             "scope":"Pure bounded arithmetic only. No source/event/epoch/participant/project authority, devices, files, windows, worker publication or UI integration qualified."}
    (destination/"results.json").write_text(json.dumps(receipt,indent=2),encoding="utf-8")
    print((destination/"tests.log").read_text(),end="");print(json.dumps(receipt));sys.exit(0 if result.wasSuccessful() else 1)
