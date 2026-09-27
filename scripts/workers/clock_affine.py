"""Bounded, exact two-anchor arithmetic; not a source/device alignment service.

No I/O, source identities, event matching, clock epoch checks, authorization,
window selection, resampling, scientific scoring or physical timing claims.
Build one immutable map, then evaluate original decimal tokens one at a time.
"""
from __future__ import annotations

from dataclasses import dataclass
from decimal import Decimal, Context, localcontext, ROUND_HALF_EVEN, InvalidOperation, DivisionByZero, Overflow
from fractions import Fraction
import json
import re

PROFILE = "reviewed-two-event-affine/0.1.0-draft"
SCHEMA = "brohn-clock-affine-arithmetic/0.1"
MAX_TOKEN_BYTES = 120
MAX_EXPONENT = 220
MAX_ADJUSTED_EXPONENT = 100
MAX_SPAN_SECONDS = 86_400
MAX_RATIONAL_DIGITS = 2_048
MAX_POINT_BYTES = 64 * 1024
MAX_MANIFEST_BYTES = 128 * 1024
DISPLAY_DIGITS = 34
_DECIMAL = re.compile(r"(?P<sign>[+-]?)(?P<mantissa>(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+))(?:[eE](?P<esign>[+-]?)(?P<exponent>[0-9]+))?", re.ASCII)
_UNITS = {"s": Fraction(1), "ms": Fraction(1, 1_000),
          "us": Fraction(1, 1_000_000), "ns": Fraction(1, 1_000_000_000)}


class ArithmeticInputError(ValueError):
    """Unsupported or over-bound arithmetic input; no source status implied."""


def _require(ok: bool, message: str) -> None:
    if not ok:
        raise ArithmeticInputError(message)


def _bounded(value: Fraction, label: str) -> Fraction:
    _require(max(abs(value.numerator).bit_length(), value.denominator.bit_length()) <= MAX_RATIONAL_DIGITS*4,
             label + " exceeds the exact rational output bound.")
    _require(len(str(abs(value.numerator))) <= MAX_RATIONAL_DIGITS and
             len(str(value.denominator)) <= MAX_RATIONAL_DIGITS,
             label + " exceeds the exact rational output bound.")
    return value


def parse_decimal(token: str) -> Fraction:
    """Parse only the declared ASCII lexeme; never binary floating timestamps."""
    _require(type(token) is str and 0 < len(token) <= MAX_TOKEN_BYTES and token.isascii(),
             "Timestamp must be a bounded ASCII decimal string.")
    match = _DECIMAL.fullmatch(token)
    _require(match is not None, "Timestamp must be an exact decimal string.")
    exponent_token = match.group("exponent")
    _require(exponent_token is None or len(exponent_token) <= 3,
             "Decimal exponent has too many digits.")
    exponent = int(exponent_token) if exponent_token is not None else 0
    if match.group("esign") == "-":
        exponent = -exponent
    _require(abs(exponent) <= MAX_EXPONENT, "Decimal exponent exceeds its operational bound.")
    mantissa = match.group("mantissa")
    integer, dot, fraction = mantissa.partition(".")
    coefficient_text = integer + fraction
    significant = coefficient_text.lstrip("0")
    power = exponent - len(fraction)
    # Match the existing Decimal.adjusted envelope, including signed zero.
    adjusted = power + len(significant) - 1 if significant else power
    _require(abs(adjusted) <= MAX_ADJUSTED_EXPONENT,
             "Timestamp is outside the existing bounded decimal range.")
    coefficient = int(coefficient_text)
    if match.group("sign") == "-":
        coefficient = -coefficient
    value = Fraction(coefficient * 10**power, 1) if power >= 0 else Fraction(coefficient, 10**(-power))
    return _bounded(value, "Decimal value")


def _pair(value: Fraction) -> dict:
    value = _bounded(value, "Coordinate")
    return {"numerator": str(value.numerator), "denominator": str(value.denominator)}


def _display(value: Fraction) -> str:
    # Explicit context protects arithmetic/display from the embedding process.
    context = Context(prec=DISPLAY_DIGITS, rounding=ROUND_HALF_EVEN,
                      Emin=-999_999, Emax=999_999, capitals=1, clamp=0,
                      traps=[InvalidOperation, DivisionByZero, Overflow])
    with localcontext(context):
        return str(Decimal(value.numerator) / Decimal(value.denominator))


def _output(record: dict, maximum: int) -> dict:
    _require(len(json.dumps(record, ensure_ascii=True, allow_nan=False,
                            separators=(",", ":")).encode("ascii")) <= maximum,
             "Arithmetic output exceeds its declared serialization bound.")
    return record


@dataclass(frozen=True, slots=True)
class _Clock:
    unit: str
    scale: Fraction
    scale_lexeme: str | None

    def manifest(self) -> dict:
        return {"unit": self.unit, "seconds_per_tick_lexeme": self.scale_lexeme,
                "seconds_per_unit": _pair(self.scale)}


def _clock(value: dict) -> _Clock:
    _require(type(value) is dict and type(value.get("unit")) is str,
             "Clock arithmetic requires an explicit registered unit.")
    unit = value["unit"]
    _require(unit in (*_UNITS, "ticks"), "Unsupported clock unit; no alias is inferred.")
    expected = {"unit", "seconds_per_tick"} if unit == "ticks" else {"unit"}
    _require(set(value) == expected, "Clock arithmetic fields do not match the declared unit.")
    if unit == "ticks":
        factor = parse_decimal(value["seconds_per_tick"])
        _require(factor > 0, "Declared seconds per tick must be positive.")
        return _Clock(unit, factor, value["seconds_per_tick"])
    return _Clock(unit, _UNITS[unit], None)


@dataclass(frozen=True, slots=True)
class _Anchor:
    source_lexeme: str
    reference_lexeme: str
    source_s: Fraction
    reference_s: Fraction


@dataclass(frozen=True, slots=True, init=False)
class AffineMap:
    """Immutable validated internal map. Construct only through build_affine.

    A serialized manifest is an explanation, not an accepted executable map or
    authority token. Deserialization and source validation are intentionally absent.
    """
    _source: _Clock
    _reference: _Clock
    _anchors: tuple[_Anchor, _Anchor]
    _scale: Fraction
    _offset_s: Fraction

    def __new__(cls):
        raise ArithmeticInputError("Construct an immutable map through build_affine.")

    def manifest(self) -> dict:
        a, b = self._anchors
        return _output({"schema": SCHEMA, "profile": PROFILE,
            "scope": "pure_arithmetic_component_only",
            "source_clock": self._source.manifest(), "reference_clock": self._reference.manifest(),
            "anchors": [{"source_lexeme": x.source_lexeme, "reference_lexeme": x.reference_lexeme,
                "source_seconds": _pair(x.source_s), "reference_seconds": _pair(x.reference_s)} for x in self._anchors],
            "scale": _pair(self._scale), "offset_seconds": _pair(self._offset_s),
            "source_span_seconds": _pair(b.source_s-a.source_s),
            "reference_span_seconds": _pair(b.reference_s-a.reference_s),
            "mapping_support": "closed_source_anchor_span_only",
            "data_window_selection": "not_performed; caller retains start-inclusive/end-exclusive selection",
            "physical_synchronization": "not_established", "uncertainty": "unknown",
            "display_policy": {"significant_digits": DISPLAY_DIGITS, "rounding": "ROUND_HALF_EVEN",
                "authority": "approximation_only; exact reduced rationals govern all arithmetic and support"},
            "operational_bounds": {"decimal_token_bytes": MAX_TOKEN_BYTES, "exponent_absolute": MAX_EXPONENT,
                "adjusted_exponent_absolute": MAX_ADJUSTED_EXPONENT, "anchor_span_seconds_each": MAX_SPAN_SECONDS,
                "rational_digits_each": MAX_RATIONAL_DIGITS, "point_json_bytes": MAX_POINT_BYTES,
                "manifest_json_bytes": MAX_MANIFEST_BYTES}}, MAX_MANIFEST_BYTES)


def build_affine(anchors: list | tuple, source_clock: dict, reference_clock: dict) -> AffineMap:
    """Validate two ordered numeric correspondences, not their event identities."""
    _require(type(anchors) in (list, tuple) and len(anchors) == 2,
             "Exactly two ordered anchor pairs are required.")
    source, reference = _clock(source_clock), _clock(reference_clock)
    parsed = []
    for item in anchors:
        _require(type(item) is dict and set(item) == {"source", "reference"},
                 "An arithmetic anchor requires only source and reference decimal tokens.")
        parsed.append(_Anchor(item["source"], item["reference"],
            _bounded(parse_decimal(item["source"]) * source.scale, "Source anchor"),
            _bounded(parse_decimal(item["reference"]) * reference.scale, "Reference anchor")))
    a, b = parsed
    source_span, reference_span = b.source_s-a.source_s, b.reference_s-a.reference_s
    _require(0 < source_span <= MAX_SPAN_SECONDS and 0 < reference_span <= MAX_SPAN_SECONDS,
             "Each anchor span must be positive and at most86400 exact seconds.")
    scale = _bounded(reference_span/source_span, "Positive affine scale")
    offset = _bounded(a.reference_s-a.source_s*scale, "Affine offset")
    result = object.__new__(AffineMap)
    for name, value in (("_source", source), ("_reference", reference), ("_anchors", tuple(parsed)),
                        ("_scale", scale), ("_offset_s", offset)):
        object.__setattr__(result, name, value)
    result.manifest()  # Bound the explanatory output once, not for every row.
    return result


def _evaluate(mapping: AffineMap, source_token: str) -> tuple[Fraction, Fraction, Fraction]:
    _require(type(mapping) is AffineMap, "Use a validated immutable arithmetic map, not a manifest.")
    x = _bounded(parse_decimal(source_token) * mapping._source.scale, "Original position")
    a, b = mapping._anchors
    _require(a.source_s <= x <= b.source_s, "Original position is outside the closed anchor span; extrapolation is not supported.")
    relative = _bounded((x-a.source_s) * mapping._scale, "Mapped relative position")
    return x, _bounded(a.reference_s+relative, "Mapped position"), relative


def map_position(mapping: AffineMap, source_token: str) -> dict:
    """Map one supplied original position; does not infer or select an observation."""
    x, mapped, relative = _evaluate(mapping, source_token)
    return _output({"schema": "brohn-clock-affine-position/0.1", "source_lexeme": source_token,
        "source_unit": mapping._source.unit, "source_seconds": _pair(x),
        "mapped_reference_seconds": _pair(mapped), "mapped_relative_to_reference_anchor_seconds": _pair(relative),
        "display_approx_seconds": _display(mapped), "display_approx_relative_to_reference_anchor_seconds": _display(relative),
        "support": "within_closed_anchor_span", "display_authority": "approximation_only"}, MAX_POINT_BYTES)


def check_event(mapping: AffineMap, source_token: str, reference_token: str) -> dict:
    """Signed mapped-minus-observed residual; the caller establishes the epoch.

    Source must be inside its anchor span. A supplied observed reference value
    may lie outside its reference anchors; that fact is explicit, never clamped.
    No fitting is repeated and no observation is interpreted as uncertainty.
    """
    x, mapped, relative = _evaluate(mapping, source_token)
    observed = _bounded(parse_decimal(reference_token)*mapping._reference.scale, "Observed reference event")
    residual = _bounded(mapped-observed, "Check-event residual")
    a, b = mapping._anchors
    return _output({"schema": "brohn-clock-affine-check/0.1", "source_lexeme": source_token,
        "reference_lexeme": reference_token, "source_unit": mapping._source.unit, "reference_unit": mapping._reference.unit,
        "source_seconds": _pair(x), "observed_reference_seconds": _pair(observed),
        "mapped_reference_seconds": _pair(mapped), "mapped_relative_to_reference_anchor_seconds": _pair(relative),
        "signed_mapped_minus_reference_residual_seconds": _pair(residual),
        "reference_within_anchor_span": a.reference_s <= observed <= b.reference_s,
        "display_approx_seconds": _display(mapped), "display_approx_relative_to_reference_anchor_seconds": _display(relative),
        "display_approx_residual_seconds": _display(residual), "display_authority": "approximation_only",
        "source_event_equivalence_and_epoch": "caller_must_validate; not_established_by_arithmetic",
        "refit": False, "uncertainty": "unknown"}, MAX_POINT_BYTES)
