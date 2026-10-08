"""Draft display contract oracle; not production code or a scientific worker.

Only validates/copies saved rows and resolves presentation membership. Production
must stream complete sources under its native source and job guards. Small
in-memory fixtures here test boundary semantics without pretending to be native
publications, scientific evidence, or a resource/performance qualification.
"""
from decimal import Decimal, ROUND_CEILING, localcontext
from functools import wraps
import math
import re
import json

POLICY = "cardiac-readable-pages/0.1"
WINDOW_SECONDS = Decimal("10")
PLOT_WIDTH = Decimal("280")
MARKER_SPACING = Decimal("8")
INTERVAL_PAGE_ROWS = 2000
NUMERICAL_PAGE_ROWS = 50
MAX_EXACT_INTEGER = 9007199254740991
MAX_CANONICAL_WINDOWS = 20000
MAX_FIXTURE_WINDOWS = 100
CHAPTER_CELLS = 10
MAX_REQUEST_BYTES = 2 * 1024 * 1024
MAX_EXPLICIT_PAGE_NUMBERS = 20000


class ContractError(ValueError):
    pass


class WindowLimit(ContractError):
    """Typed policy failure; native caller must add exact source/request bindings."""
    def __init__(self, measured, maximum):
        self.reason_code = "canonical_window_count_limit"
        self.stage = "display"
        self.resource = "canonical_windows"
        self.measured = measured
        self.maximum = maximum
        self.recovery_scope = "smaller_window"
        super().__init__("The source has too many canonical display windows. Choose an exact time focus from the original bounds; complete saved evidence remains required.")


def require(ok, reason):
    if not ok:
        raise ContractError(reason)


def number(value):
    return type(value) in (int, float) and math.isfinite(value)


def index(value):
    return type(value) is int and 0 <= value <= MAX_EXACT_INTEGER


def exact_decimal_operation(fn):
    @wraps(fn)
    def run(*args, **kwargs):
        # Covers the bounded 80-character request / exponent-1000 domain and
        # every finite binary64 shortest representation, without global context.
        with localcontext() as ctx:
            ctx.prec = 2200
            return fn(*args, **kwargs)
    return run


def coordinate(value):
    """Use saved float64's shortest decimal; never convert huge clock strings."""
    require(number(value), "finite_saved_coordinate_required")
    return Decimal(str(value))


def requested_decimal(value):
    # Exact port of R .brohn_edd_decimal_parts, including its already-canonical
    # extended transport exception. This is shared transport, not EDA science.
    require(type(value) is str and len(value.encode("utf-8")) <= 96, "decimal_string_required")
    require(re.fullmatch(r"[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?", value) is not None,
            "decimal_not_lexical")
    exponent = re.search(r"[eE]([+-]?[0-9]+)$", value)
    submitted_exponent = 0 if exponent is None else int(exponent.group(1))
    require(abs(submitted_exponent) <= 1100, "decimal_exponent_out_of_range")
    try:
        out = Decimal(value)
    except Exception as exc:
        raise ContractError("invalid_decimal") from exc
    require(out.is_finite() and out.copy_abs() <= Decimal("1e12"), "decimal_out_of_range")
    canonical = text_decimal(out)
    ordinary = len(value) <= 80 and abs(submitted_exponent) <= 1000
    require(ordinary or (out != 0 and value == canonical), "decimal_not_canonical_extended_transport")
    require(len(canonical) <= 96, "canonical_decimal_too_long")
    return out


@exact_decimal_operation
def text_decimal(value):
    if value == 0:
        return "0"
    # Coefficient/exponent assembly, never context-dependent normalize/rounding.
    parts = value.as_tuple()
    digits = "".join(str(d) for d in parts.digits).lstrip("0")
    coefficient = digits.rstrip("0")
    exponent = parts.exponent + len(digits) - len(coefficient)
    return ("-" if parts.sign else "") + coefficient + ("e" + str(exponent) if exponent else "")


@exact_decimal_operation
def canonical_window_count(first_time, last_time, maximum=MAX_CANONICAL_WINDOWS):
    """O(1) metadata arithmetic; never allocate one object per ten seconds."""
    first, last = coordinate(first_time), coordinate(last_time)
    require(first <= last, "reversed_observed_extent")
    require(max(abs(first), abs(last)) <= Decimal("1e12"), "source_coordinate_extent_out_of_profile")
    require(index(maximum) and maximum > 0, "invalid_window_limit")
    count = max(1, int(((last-first)/WINDOW_SECONDS).to_integral_value(rounding=ROUND_CEILING)))
    if count > maximum:
        raise WindowLimit(count, maximum)
    return count


@exact_decimal_operation
def canonical_window(first_time, last_time, number, maximum=MAX_CANONICAL_WINDOWS):
    """Resolve one requested window without materializing earlier windows."""
    total = canonical_window_count(first_time, last_time, maximum)
    require(index(number) and 1 <= number <= total, "requested_window_absent")
    first, last = coordinate(first_time), coordinate(last_time)
    start = first + WINDOW_SECONDS * (number - 1)
    end = min(start + WINDOW_SECONDS, last)
    return {"number": number, "start_s": text_decimal(start), "end_s": text_decimal(end),
            "boundary": "closed" if number == total else "left_closed_right_open"}


def canonical_windows(first_time, last_time):
    """Tiny-fixture convenience only; production uses count + requested index."""
    count = canonical_window_count(first_time, last_time, MAX_FIXTURE_WINDOWS)
    return [canonical_window(first_time, last_time, n) for n in range(1, count + 1)]


@exact_decimal_operation
def focus_window(start_s, end_s):
    start, end = requested_decimal(start_s), requested_decimal(end_s)
    require(start < end, "focus_requires_increasing_bounds")
    return {"number": 1, "start_s": text_decimal(start),
            "end_s": text_decimal(end), "boundary": "closed"}


def contains(window, time_s):
    value = coordinate(time_s)
    lo, hi = Decimal(window["start_s"]), Decimal(window["end_s"])
    return lo <= value and (value <= hi if window["boundary"] == "closed" else value < hi)


def exact_pages(total_rows, rows_per_page, policy="first", numbers=()):
    require(index(total_rows) and index(rows_per_page) and rows_per_page > 0, "invalid_page_count")
    require(policy in ("first", "all", "selected"), "invalid_page_policy")
    count = (total_rows + rows_per_page - 1) // rows_per_page
    require(isinstance(numbers, (tuple, list)), "page_numbers_array_required")
    require(all(index(n) and n >= 1 for n in numbers), "invalid_page_number")
    require(len(set(numbers)) == len(numbers), "duplicate_page")
    require((policy == "selected" and len(numbers) > 0) or (policy != "selected" and not numbers),
            "inconsistent_page_policy")
    if policy == "selected":
        require(all(n <= count for n in numbers), "requested_page_absent")
        chosen = sorted(numbers)
    elif policy == "all":
        chosen = list(range(1, count + 1))
    else:
        chosen = [1] if count else []
    return [{"number": n, "row_start": (n - 1) * rows_per_page,
            "row_end_exclusive": min(n * rows_per_page, total_rows)} for n in chosen]


def figure_chapters(cell_keys, policy="first", numbers=()):
    """Explicit global presentation partition; never modifies evidence membership.

    Input is frozen report selection order, then original recording-list order.
    Required-but-unselected parent reports are not added to this figure union.
    """
    require(isinstance(cell_keys, list) and len(cell_keys) <= 2000, "chapter_cell_union_limit")
    require(all(type(k) is str and re.fullmatch("[a-f0-9]{64}", k) for k in cell_keys), "chapter_cell_key_invalid")
    require(len(set(cell_keys)) == len(cell_keys), "chapter_cell_key_repeated")
    pages = exact_pages(len(cell_keys), CHAPTER_CELLS, policy, numbers)
    all_pages = exact_pages(len(cell_keys), CHAPTER_CELLS, "all")
    included = [k for p in pages for k in cell_keys[p["row_start"]:p["row_end_exclusive"]]]
    chosen = set(included)
    return {"schema": "brohn-cardiac-figure-chapter-resolution/0.1", "cells_per_chapter": CHAPTER_CELLS,
            "total_cells": len(cell_keys), "total_chapters": len(all_pages),
            "requested": {"mode": policy, "numbers": list(numbers)},
            "selected_chapter_numbers": [p["number"] for p in pages],
            "included_cell_keys": included, "evidence_only_cell_keys": [k for k in cell_keys if k not in chosen],
            "chapters": [{"number": p["number"], "cell_keys": cell_keys[p["row_start"]:p["row_end_exclusive"]]}
                         for p in all_pages]}


def check_request_budget(request):
    """Aggregate budget after closed-schema normalization; raw parser also caps2MiB."""
    size = len(json.dumps(request, ensure_ascii=False, allow_nan=False, separators=(",", ":")).encode("utf-8"))
    require(size <= MAX_REQUEST_BYTES, "display_request_bytes_limit")
    count = sum(len(cell[field]["numbers"]) for cell in request["cell_overrides"]
                for field in ("waveform_windows", "marker_pages", "interval_pages", "numerical_pages"))
    require(count <= MAX_EXPLICIT_PAGE_NUMBERS, "display_page_selection_count_limit")
    return {"normalized_utf8_bytes": size, "explicit_page_numbers": count}


@exact_decimal_operation
def marker_pages(joined_markers, window):
    """Minimum earliest-fit pages of exact-x markers, deterministic by row order.

    Full joins must have succeeded already. No marker is jittered or selected
    by its plausibility/value. Production can stream memberships to scratch.
    """
    ordered = []
    previous = None
    for marker in joined_markers:
        when = coordinate(marker["time_s"])
        require(previous is None or when > previous, "markers_not_strictly_ordered")
        previous = when
        require(index(marker["event_row_index"]), "invalid_marker_row_identity")
        if contains(window, marker["time_s"]):
            ordered.append(marker)
    require(len({m["event_row_index"] for m in joined_markers}) == len(joined_markers), "duplicate_marker_identity")
    lo, hi = Decimal(window["start_s"]), Decimal(window["end_s"])
    require(lo <= hi, "reversed_window")
    pages, last_x = [], []
    for marker in ordered:
        x = Decimal(0) if lo == hi else (coordinate(marker["time_s"]) - lo) * PLOT_WIDTH / (hi - lo)
        page = next((i for i, previous_x in enumerate(last_x) if x - previous_x >= MARKER_SPACING), None)
        if page is None:
            page = len(pages)
            pages.append([])
            last_x.append(x)
        pages[page].append(marker["event_row_index"])
        last_x[page] = x
    # A clean trace with no peaks still has one empty, honestly labelled page.
    if not pages:
        pages = [[]]
    return {"policy": POLICY, "source_total": len(joined_markers),
            "in_window": len(ordered), "outside_window": len(joined_markers) - len(ordered),
            "pages": [{"number": i + 1, "event_rows": members,
                       "plotted": len(members), "on_other_pages": len(ordered) - len(members)}
                      for i, members in enumerate(pages)]}


def validate_and_join(sample_rows, peak_rows, source_row_start=0, event_type="r_peak"):
    """Read-only contract fixture join. Does not calculate any interval/feature."""
    require(index(source_row_start), "invalid_source_start")
    require(event_type in ("r_peak", "systolic_pulse_peak"), "invalid_event_type")
    by_index = {}
    last_index = last_time = None
    for row in sample_rows:
        require(set(row) == {"time_s", "source_sample_index", "raw", "clean", "retained"}, "sample_fields")
        i, t = row["source_sample_index"], row["time_s"]
        require(index(i) and number(t) and number(row["raw"]) and number(row["clean"])
                and type(row["retained"]) is bool, "sample_types")
        require(last_index is not None or i == source_row_start, "first_sample_source_bound_mismatch")
        require(last_index is None or (i == last_index + 1 and t > last_time), "sample_order_or_missing_row")
        require(i >= source_row_start and i not in by_index, "source_index_reused")
        by_index[i] = row
        last_index, last_time = i, t
    joined = []
    last_index = last_time = None
    for row_index, event in enumerate(peak_rows):
        require(set(event) == {"type", "time_s", "sample_index", "source_sample_index",
                               "previous_interval_ms", "previous_interval_plausible"}, "peak_fields")
        i, t, local = event["source_sample_index"], event["time_s"], event["sample_index"]
        require(event["type"] == event_type and index(i) and index(local) and number(t), "peak_types")
        require(local + source_row_start == i, "local_global_index_mismatch")
        require(last_index is None or (i > last_index and t > last_time), "peak_order_or_duplicate")
        interval, plausible = event["previous_interval_ms"], event["previous_interval_plausible"]
        if row_index == 0:
            require(interval is None and plausible is None, "first_interval_not_null")
        else:
            require(number(interval) and interval > 0 and type(plausible) is bool, "later_interval_invalid")
        require(i in by_index, "marker_sample_missing")
        sample = by_index[i]
        require(sample["time_s"] == t and sample["retained"], "marker_not_exact_retained_sample")
        joined.append({"event_row_index": row_index, "source_sample_index": i, "time_s": t,
                       "raw": sample["raw"], "clean": sample["clean"],
                       "previous_interval_ms": interval, "previous_interval_plausible": plausible})
        last_index, last_time = i, t
    return joined


def interval_page(peak_rows, page):
    lo, hi = page["row_start"], page["row_end_exclusive"]
    require(index(lo) and index(hi) and lo <= hi <= len(peak_rows), "interval_page_out_of_bounds")
    points, null_rows = [], []
    for row_index in range(lo, hi):
        row = peak_rows[row_index]
        if row["previous_interval_ms"] is None:
            null_rows.append(row_index)
        else:
            points.append({"event_row_index": row_index, "time_s": row["time_s"],
                           "interval_ms": row["previous_interval_ms"],
                           "plausible": row["previous_interval_plausible"]})
    return {"row_start": lo, "row_end_exclusive": hi, "temporal_rows": hi - lo,
            "plotted": len(points), "null_interval_rows": null_rows, "points": points,
            "connection_policy": "none", "basis": "saved_previous_interval_at_ending_peak"}


def recovery(resource, source_count=1):
    """Resource recovery cannot offer visual edits for complete-source failure."""
    if resource in {"source_rows", "source_bytes", "projection_bytes"}:
        return "fewer_sources" if source_count > 1 else "original_exports_only"
    if resource in {"canonical_windows", "window_points", "fragments", "marker_page_panels"}:
        return "smaller_window"
    if resource == "total_panels":
        return "fewer_figures"
    raise ContractError("unregistered_resource")
