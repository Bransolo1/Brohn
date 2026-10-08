"""Complete saved-row joins, followed only by bounded presentation geometry."""
from contextlib import closing
from decimal import Decimal
import math

from cardiac_values import json_bytes, strict_json
from cardiac_display_core import require, same, limit, Refusal, MIB, COUNTS, table_ref, number
import cardiac_display_policy as policy


def complete_cell(index, domains, record, feature_count, ordinal, outputs, modality):
    counts = dict.fromkeys(COUNTS, 0)
    counts["features"] = feature_count
    if not domains:
        return counts, None
    samples, peaks = domains["samples"], domains["peaks"]
    sample_ref, peak_ref = table_ref(samples), table_ref(peaks)
    target = outputs.path(f"cell-{ordinal:04d}-markers.ndjson")
    previous_sample = previous_peak = None
    with target.open("xb") as dst, closing(index.rows_for(peaks)) as events:
        event = next(events, None)
        for row_index, row in index.rows_for(samples):
            t, source, raw, clean, retained = row
            require(source == record["source_row_start"] + row_index, "Original sample indices do not cover the complete declared run.")
            require(previous_sample is None or t > previous_sample[0], "Saved sample times are not strictly ordered.")
            if row_index == 0:
                require(same(t, record["start_time_s"]), "First saved sample differs from original source bounds.")
            counts["samples"] += 1
            counts["retained_samples"] += int(retained)
            if event is not None:
                ei, e = event
                require(e[3] >= source, "A saved detection has no exact source sample.")
                if e[3] == source:
                    typ, when, local, absolute, interval, plausible = e
                    require(typ == ("r_peak" if modality == "ecg" else "systolic_pulse_peak") and
                            local == row_index and same(when, t) and retained,
                            "Detection must join its exact retained source index, local index and recorded time.")
                    require(previous_peak is None or (absolute > previous_peak[3] and when > previous_peak[1]), "Duplicate or unordered detection.")
                    if ei == 0:
                        require(interval is None and plausible is None, "First saved interval must remain null.")
                        counts["null_interval_rows"] += 1
                    else:
                        require(number(interval) and interval > 0 and type(plausible) is bool, "Later saved interval/plausibility is invalid.")
                        counts["intervals"] += 1
                        counts["plausible_intervals" if plausible else "implausible_intervals"] += 1
                    joined = dict(event_table_ref=peak_ref, event_row_index=ei, series_table_ref=sample_ref,
                                  source_sample_index=source, time_s=t, raw=raw, clean=clean,
                                  previous_interval_ms=interval, previous_interval_plausible=plausible,
                                  alignment="exact_source_sample_and_recorded_time", detection_basis="saved_cleaned_waveform")
                    dst.write(json_bytes(joined)+b"\n")
                    counts["peaks"] += 1
                    if counts["peaks"] % 256 == 0:
                        limit(outputs.bytes+dst.tell(),192*MIB,"projection_bytes",stage="projection")
                    previous_peak = e
                    event = next(events, None)
            previous_sample = row
        require(event is None, "A saved detection lies beyond its complete source run.")
    require(previous_sample is not None and same(previous_sample[0], record["end_time_s"]) and
            counts["samples"] == record["samples"] and counts["retained_samples"] == record["retained_samples"] and
            counts["peaks"] == record["detected_peak_count"] and counts["implausible_intervals"] == record["implausible_interval_count"],
            "Complete rows differ from saved source support/counts.")
    if "spectrum" in domains:
        last_frequency = None
        for _, row in index.rows_for(domains["spectrum"]):
            require(row[0] == "interval_psd_bin" and row[1] >= 0 and row[2] >= 0 and
                    (last_frequency is None or row[1] > last_frequency), "Invalid or unordered saved spectrum bin.")
            counts["spectrum_bins"] += 1
            last_frequency = row[1]
        support = record["interval_spectrum"]
        require(same(domains["spectrum"]["spec"]["support"]["interval_spectrum"], support) and
                counts["spectrum_bins"] == domains["spectrum"]["spec"]["expected_rows"], "Saved spectrum count/support changed.")
    return counts, outputs.register(target, "brohn-cardiac-joined-markers/0.1", "complete_joined_markers", "application/x-ndjson")


def axis(values, unit, scope):
    lo, hi = min(values), max(values)
    padding = None
    if lo == hi:
        padding = "constant_saved_values"
        # Pure display padding, independent of any scientific signal threshold.
        delta = max(abs(lo)*0.05, 1.0)
        minimum, maximum = lo-delta, hi+delta
    else:
        minimum, maximum = lo, hi
    require(all(math.isfinite(v) for v in (minimum, maximum)), "Display axis exceeds finite geometry.")
    return dict(minimum=minimum, maximum=maximum, observed_minimum=lo, observed_maximum=hi,
                unit=unit, scope=scope, display_padding_reason=padding)


def selected_numbers(total, request):
    return [p["number"] for p in policy.exact_pages(total, 1, request["mode"], request["numbers"])]


def marker_coverage(marker_path, window, request, total):
    pages, last_x = [], []
    lo, hi = Decimal(window["start_s"]), Decimal(window["end_s"])
    with marker_path.open("rb") as stream:
        for line in stream:
            marker = strict_json(line)
            if not policy.contains(window, marker["time_s"]):
                continue
            with policy.localcontext() as context:
                context.prec = 2300
                x = Decimal(0) if lo == hi else (policy.coordinate(marker["time_s"])-lo)*280/(hi-lo)
                page = next((i for i, old in enumerate(last_x) if x-old >= 8), None)
            if page is None:
                page = len(pages)
                # More than 100 possible pages cannot fit the existing figure ceiling.
                limit(page+1, 100, "marker_page_panels", recovery="smaller_window", stage="display")
                pages.append([])
                last_x.append(x)
            pages[page].append(marker["event_row_index"])
            last_x[page] = x
    if not pages:
        pages = [[]]
    chosen = selected_numbers(len(pages), request)
    in_window = sum(map(len, pages))
    return dict(policy=policy.POLICY, all_source_joins_checked=True, source_total=total,
                in_window=in_window, outside_window=total-in_window,
                pages=[dict(number=i+1, event_rows=rows, plotted=len(rows), on_other_pages=in_window-len(rows)) for i, rows in enumerate(pages)],
                requested_pages=request, resolved_page_numbers=chosen,
                omitted_page_numbers=[i+1 for i in range(len(pages)) if i+1 not in chosen])


def waveform(index, item, record, window, marker_path, marker_request, peak_count):
    # Streaming first/last/min/max for each time bin and contiguous fragment.
    all_fragments = [[], []]
    active = None
    selected = 0
    first = last = None
    extrema = []
    previous = None
    lo, hi = Decimal(window["start_s"]), Decimal(window["end_s"])
    def flush():
        if active is None:
            return
        for component in range(2):
            points = {}
            for group in active["bins"][component].values():
                for p in group:
                    points[p["table_row_index"]] = p
            representatives = [points[k] for k in sorted(points)]
            limit(len(representatives), 1600, "window_points", recovery="smaller_window", stage="display")
            all_fragments[component].append(dict(table_ref=table_ref(item), retained=active["retained"],
                break_before=active["reason"], source_rows=active["rows"], representative_points=representatives))
    for ordinal, row in index.rows_for(item):
        if not policy.contains(window, row[0]):
            continue
        t, source, raw, clean, retained = row
        reason = None
        if previous is None:
            reason = "table_boundary" if ordinal == 0 else "window_start"
        elif retained != previous[4]:
            reason = "retention_transition"
        elif source != previous[1]+1:
            reason = "source_sample_gap"
        elif t-previous[0] > 1/record["sampling_rate"]+record["channel_quality"]["timestamp_tolerance_s"]:
            reason = "clock_gap"
        if reason is not None:
            flush()
            limit(len(all_fragments[0])+1, 2000, "fragments", recovery="smaller_window", stage="display")
            active = dict(retained=retained, reason=reason, rows=0, bins=[{}, {}])
        with policy.localcontext() as context:
            context.prec = 2300
            bin_number = 0 if lo == hi else min(399, int((policy.coordinate(t)-lo)*400/(hi-lo)))
        for component, value in enumerate((raw, clean)):
            point = dict(table_row_index=ordinal, source_sample_index=source, time_s=t, value=value)
            bins = active["bins"][component]
            if bin_number not in bins:
                bins[bin_number] = [point, point, point, point]
            else:
                group = bins[bin_number]
                group[1] = point
                if value < group[2]["value"]:
                    group[2] = point
                if value > group[3]["value"]:
                    group[3] = point
        active["rows"] += 1
        extrema = [min(extrema[0], raw, clean), max(extrema[1], raw, clean)] if extrema else [min(raw, clean), max(raw, clean)]
        selected += 1
        first = first or row
        last = previous = row
    flush()
    require(sum(f["source_rows"] for f in all_fragments[0]) == selected, "Envelope row coverage is incomplete.")
    resolved = dict(number=window["number"], requested={k:window[k] for k in ("start_s", "end_s")}, boundary=window["boundary"],
                    observed=None if first is None else dict(start_s=policy.text_decimal(policy.coordinate(first[0])), end_s=policy.text_decimal(policy.coordinate(last[0]))),
                    first_source_sample_index=None if first is None else first[1], last_source_sample_index=None if last is None else last[1],
                    selected_samples=selected, state="available" if selected else "empty_range")
    # Schema requires an axis even for an empty focus; honest no-observation axis
    # is impossible under that schema, so refuse rather than fabricate extrema.
    if not selected:
        raise Refusal("empty_focus_has_no_observed_axis", recovery="smaller_window", stage="display",
                      message="The requested range contains no saved samples. Choose a range within the original source bounds.")
    shared = axis(extrema, record["unit"], "paired_raw_clean_window")
    return dict(window=resolved, raw_axis=shared, clean_axis=shared, scale_mode="shared", raw=all_fragments[0], clean=all_fragments[1],
                envelope_source_rows=selected, markers=marker_coverage(marker_path, window, marker_request, peak_count))


def interval_views(index, item, request):
    pages = policy.exact_pages(item["spec"]["expected_rows"], 2000, request["mode"], request["numbers"])
    limit(len(pages), 100, "total_panels", recovery="fewer_figures", stage="display")
    results = []
    for page in pages:
        points, nulls = [], []
        for ordinal, row in index.rows_for(item):
            if not page["row_start"] <= ordinal < page["row_end_exclusive"]:
                continue
            if row[4] is None:
                nulls.append(ordinal)
            else:
                points.append(dict(event_row_index=ordinal, time_s=row[1], interval_ms=row[4], plausible=row[5]))
        results.append(dict(**page, temporal_rows=page["row_end_exclusive"]-page["row_start"], plotted=len(points),
                            null_interval_rows=nulls, points=points,
                            axis=axis([p["interval_ms"] for p in points], "ms", "saved_interval_page") if points else None,
                            connection_policy="none", basis="saved_previous_interval_at_ending_peak"))
    return results


def spectrum_view(index, item, availability, record):
    if item is None:
        return dict(availability=availability, table_ref=None, saved_support=record.get("interval_spectrum"), axis=None,
                    total_bins=0, plotted_bins=0, omitted_bins=0, bin_row_indices=[], rows=[], values_reestimated=False)
    count = item["spec"]["expected_rows"]
    limit(count, 2048, "spectrum_illustration_bins", recovery="original_exports_only", stage="display")
    rows = [row for _, row in index.rows_for(item)]
    require(rows, "Available saved spectrum is empty.")
    a = axis([r[2] for r in rows], "ms^2/Hz", "saved_spectrum")
    if a["observed_minimum"] == a["observed_maximum"] == 0:
        a.update(minimum=0, maximum=1, display_padding_reason="zero_saved_density")
    return dict(availability=availability, table_ref=table_ref(item), saved_support=record["interval_spectrum"], axis=a,
                total_bins=count, plotted_bins=count, omitted_bins=0, bin_row_indices=list(range(count)), rows=rows, values_reestimated=False)
