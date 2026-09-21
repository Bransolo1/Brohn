# Dedicated saved-trace renderer. It does not use a generic retained-mask line.
.brohn_gaze_trace_finite <- function(x) is.numeric(x) && length(x) == 1L && is.finite(x)
.brohn_gaze_trace_number <- function(x) if (.brohn_gaze_trace_finite(x)) sprintf("%.17g", x) else "Unavailable"

brohn_gaze_trace_plot_model <- function(view) {
  brohn_require(identical(view$schema, "brohn-gaze-trace-preview/1.0") && identical(view$trace_profile, "gaze-pupil-source-trace/1.0") &&
    view$status %in% c("available", "empty", "too_many_rows"), "This saved trace has no supported visual adapter.")
  table <- view$table; support <- table$support
  brohn_require(identical(support$trace_profile, view$trace_profile) &&
    identical(support$generic_line_preview, "forbidden_use_dedicated_gaze_adapter"), "A pupil trace needs its explicit mask policy.")
  rows <- view$rows
  brohn_require(is.list(rows) && length(rows) <= 5000L && .brohn_gaze_trace_finite(view$selected_rows) && view$selected_rows >= 0 &&
    (identical(view$status, "available") && length(rows) == view$selected_rows ||
     identical(view$status, "empty") && view$selected_rows == 0 && !length(rows) ||
     identical(view$status, "too_many_rows") && view$selected_rows > 5000 && !length(rows)), "Saved trace rows disagree with the explicit display bound.")
  if (length(rows)) {
    clocks <- vapply(rows, function(r) r$analysis_time_ms, numeric(1))
    positions <- vapply(rows, function(r) r$row_index, numeric(1))
    brohn_require(all(is.finite(clocks)) && (length(rows) == 1L || all(diff(clocks) > 0) && all(diff(positions) == 1)),
      "Selected source rows must retain exact time and table order.")
    for (row in rows) brohn_require(.brohn_gaze_trace_finite(row$source_row) && row$source_row >= 1 && row$source_row == floor(row$source_row) &&
      is.logical(row$effective_pupil_valid) && length(row$effective_pupil_valid) == 1L && !is.na(row$effective_pupil_valid) &&
      brohn_text(row$phase, 500) && (is.null(row$pupil) || .brohn_gaze_trace_finite(row$pupil)) &&
      (is.null(row$pupil_minus_baseline) || .brohn_gaze_trace_finite(row$pupil_minus_baseline)), "A saved trace row has invalid typed support.")
  }
  series <- function(field, corrected = FALSE) {
    points <- list(); segments <- list(); current <- integer()
    flush <- function() { if (length(current)) segments[[length(segments)+1L]] <<- current; current <<- integer() }
    for (i in seq_along(rows)) {
      row <- rows[[i]]; value <- row[[field]]
      valid <- .brohn_gaze_trace_finite(value) && isTRUE(row$effective_pupil_valid) && (!corrected || isTRUE(row$passive))
      connected <- i > 1L && valid && length(current) > 0L && isTRUE(rows[[i-1L]]$effective_pupil_valid) &&
        identical(rows[[i-1L]]$following_gap, FALSE) && identical(rows[[i-1L]]$following_phase_change, FALSE) &&
        identical(rows[[i-1L]]$phase, row$phase) && .brohn_gaze_trace_finite(rows[[i-1L]]$following_time_ms) &&
        rows[[i-1L]]$following_time_ms == row$analysis_time_ms &&
        (!corrected || isTRUE(rows[[i-1L]]$pupil_interval_eligible))
      if (!connected) flush()
      if (.brohn_gaze_trace_finite(value)) points[[length(points)+1L]] <- list(index = i, row_index = row$row_index,
        source_row = row$source_row, time_ms = row$analysis_time_ms, value = value, valid = valid, phase = row$phase)
      if (valid) current <- c(current, i)
    }
    flush()
    list(field = field, points = points, segments = segments)
  }
  list(status = view$status, identity = table$identity, support = support, rows = rows, selected_rows = view$selected_rows,
    total_rows = table$expected_rows, range = view$range, raw = series("pupil"), corrected = series("pupil_minus_baseline", TRUE),
    blink_ticks = Filter(function(row) isTRUE(row$source_blink), rows),
    blink_mapped = brohn_text(support$blink_column, 500), pupil_mapped = brohn_text(support$pupil_column, 500))
}

brohn_gaze_trace_svg <- function(model, compact = FALSE) {
  brohn_require(identical(model$status, "available") && length(model$rows), "Select an available saved trace window first.")
  escape <- function(x) as.character(htmltools::htmlEscape(as.character(x), attribute = TRUE))
  fmt <- function(x) format(round(x, 3), trim = TRUE, scientific = FALSE)
  rows <- model$rows; clocks <- vapply(rows, function(r) r$analysis_time_ms, numeric(1))
  xmin <- min(clocks); xmax <- max(clocks); span <- xmax-xmin
  left <- if (compact) 65 else 70; right <- if (compact) 405 else 910; width <- if (compact) 420 else 940
  x <- function(t) if (span > 0) left + (t-xmin)/span*(right-left) else (left+right)/2
  parts <- c(sprintf('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %d 510" role="img" aria-label="Original and baseline-corrected pupil observations with externally supplied blink labels" style="width:100%%;height:auto;display:block">', width),
    '<title>Saved pupil and source-labelled blink trace</title>',
    '<desc>Observed source points only. Lines break at invalid endpoints, phase changes and unsupported gaps. Red crosses preserve excluded finite original values. Source blink positives are ticks.</desc>',
    sprintf('<rect width="%d" height="510" fill="white"/>', width))
  plot <- function(series, top, bottom, title, color) {
    values <- vapply(series$points, function(p) p$value, numeric(1))
    range_values <- values
    if (identical(series$field, "pupil") && .brohn_gaze_trace_finite(model$support$baseline$mean))
      range_values <- c(range_values, model$support$baseline$mean)
    limits <- if (length(range_values)) range(range_values) else c(0, 1)
    minimum_span <- max(abs(limits))*.05
    if (minimum_span == 0) minimum_span <- .02
    if (diff(limits) < minimum_span) limits <- mean(limits) + c(-.5, .5)*minimum_span
    y <- function(value) bottom-(value-limits[[1L]])/diff(limits)*(bottom-top)
    p <- c(sprintf('<text x="%d" y="%s" font-size="%d" fill="#162f45">%s</text>', left, fmt(top-15), if (compact) 17 else 16, escape(title)),
      sprintf('<path d="M%d %s H%d M%d %s V%s" fill="none" stroke="#627383"/>', left, fmt(bottom), right, left, fmt(top), fmt(bottom)),
      sprintf('<text x="%d" y="%s" text-anchor="end" font-size="%d">%s</text>', left-8, fmt(top+4), if (compact) 14 else 12, escape(format(signif(limits[[2L]], 5), trim = TRUE))),
      sprintf('<text x="%d" y="%s" text-anchor="end" font-size="%d">%s</text>', left-8, fmt(bottom), if (compact) 14 else 12, escape(format(signif(limits[[1L]], 5), trim = TRUE))))
    b <- model$support$baseline
    if (.brohn_gaze_trace_finite(b$start_ms) && .brohn_gaze_trace_finite(b$end_ms) && b$end_ms >= xmin && b$start_ms <= xmax)
      p <- c(p, sprintf('<rect x="%s" y="%s" width="%s" height="%s" fill="#e5eff8" data-gaze-baseline="declared-window"/>',
        fmt(x(max(xmin, b$start_ms))), fmt(top), fmt(max(0, x(min(xmax, b$end_ms))-x(max(xmin, b$start_ms)))), fmt(bottom-top)))
    if (identical(series$field, "pupil") && .brohn_gaze_trace_finite(b$mean))
      p <- c(p, sprintf('<path d="M%d %s H%d" stroke="#785a20" stroke-dasharray="5 4" data-gaze-baseline="stored-mean"/>', left, fmt(y(b$mean)), right))
    for (indices in series$segments) if (length(indices) >= 2L) {
      points <- vapply(indices, function(i) paste(fmt(x(rows[[i]]$analysis_time_ms)), fmt(y(rows[[i]][[series$field]])), sep = ","), character(1))
      p <- c(p, sprintf('<polyline points="%s" fill="none" stroke="%s" stroke-width="1.5" data-gaze-series="%s"/>', paste(points, collapse = " "), color, series$field))
    }
    for (point in series$points) {
      px <- x(point$time_ms); py <- y(point$value)
      detail <- escape(paste("Source row", point$source_row, "|", .brohn_gaze_trace_number(point$time_ms), "ms |", .brohn_gaze_trace_number(point$value), model$support$pupil_unit, "| phase", point$phase))
      p <- c(p, if (point$valid) sprintf('<circle cx="%s" cy="%s" r="2" fill="%s"><title>%s</title></circle>', fmt(px), fmt(py), color, detail) else
        sprintf('<path d="M%s %s l5 5 m-5 0 l5 -5" fill="none" stroke="#a12b30" stroke-width="1.4" data-gaze-invalid="true"><title>%s</title></path>', fmt(px-2.5), fmt(py-2.5), detail))
    }
    if (!length(values)) p <- c(p, sprintf('<text x="%d" y="%s" font-size="14" fill="#526475">No supported values in this window</text>', left+10, fmt((top+bottom)/2)))
    p
  }
  unit <- brohn_default(model$support$pupil_unit, "unit unavailable")
  parts <- c(parts, plot(model$raw, 55, 205, paste(if (compact) "Original pupil (" else "Original pupil observations (", unit, ")", sep = ""), "#17577b"),
    plot(model$corrected, 260, 410, paste("Pupil minus saved baseline (", unit, ")", sep = ""), "#7351a2"),
    sprintf('<text x="%d" y="443" font-size="14">Source blink labels</text>', left),
    sprintf('<path d="M%d 463 H%d" stroke="#a7b4bf"/>', left, right))
  for (row in model$blink_ticks) parts <- c(parts, sprintf('<path d="M%s 450 V471" stroke="#a12b30" stroke-width="2" data-gaze-blink="true"><title>%s</title></path>',
    fmt(x(row$analysis_time_ms)), escape(paste("Positive source label | source row", row$source_row, "| phase", row$phase))))
  if (!model$blink_mapped) parts <- c(parts, sprintf('<text x="%d" y="478" font-size="13" fill="#526475">No source blink labels mapped</text>', left))
  parts <- c(parts, sprintf('<text x="%d" y="493" font-size="13">%s ms</text>', left, escape(.brohn_gaze_trace_number(xmin))),
    sprintf('<text x="%d" y="493" text-anchor="end" font-size="13">%s ms</text>', right, escape(.brohn_gaze_trace_number(xmax))), '</svg>')
  paste(parts, collapse = "\n")
}

brohn_gaze_trace_ui <- function(view, numeric_download_id = NULL, artifact_download_id = NULL, heading_level = 2L) {
  brohn_require(heading_level %in% 2:6, "Choose a heading level within the saved report.")
  model <- brohn_gaze_trace_plot_model(view)
  summary <- paste(format(model$selected_rows, big.mark = ","), "source rows in this window;", format(model$total_rows, big.mark = ","), "in the complete exposure trace.")
  content <- if (identical(model$status, "too_many_rows")) shiny::p("This range contains more than 5,000 rows. Narrow the time window to show every selected observation; the complete saved trace remains available.") else
    if (identical(model$status, "empty")) shiny::p("No source rows fall in this time window.") else shiny::tagList(
      shiny::tags$style(shiny::HTML(".brohn-gaze-trace{container-type:inline-size}.brohn-gaze-trace-compact{display:none}@container (max-width:600px){.brohn-gaze-trace-wide{display:none}.brohn-gaze-trace-compact{display:block}}")),
      shiny::div(class = "brohn-gaze-trace-wide", shiny::HTML(brohn_gaze_trace_svg(model))),
      shiny::div(class = "brohn-gaze-trace-compact", shiny::HTML(brohn_gaze_trace_svg(model, compact = TRUE))))
  numeric_rows <- head(model$rows, 100L)
  numeric <- if (length(numeric_rows)) shiny::tags$table(class = "table table-sm", shiny::tags$caption("Exact source values: first 100 selected rows at most. Complete values remain in the saved artifact."),
    shiny::tags$thead(shiny::tags$tr(lapply(c("Source row", "Time (ms)", "Phase", "Original pupil", "Pupil minus baseline", "Source blink"), shiny::tags$th))),
    shiny::tags$tbody(lapply(numeric_rows, function(r) shiny::tags$tr(shiny::tags$td(r$source_row), shiny::tags$td(brohn_default(r$analysis_time_ms_decimal, .brohn_gaze_trace_number(r$analysis_time_ms))),
      shiny::tags$td(r$phase), shiny::tags$td(brohn_default(r$pupil_decimal, "Unavailable")), shiny::tags$td(brohn_default(r$pupil_minus_baseline_decimal, "Unavailable")),
      shiny::tags$td(if (is.null(r$source_blink)) "Unavailable" else if (r$source_blink) "Positive source label" else "False source label"))))) else NULL
  b <- model$support$baseline
  shiny::tags$section(class = "brohn-gaze-trace", `data-gaze-trace-profile` = "gaze-pupil-source-trace/1.0",
    do.call(shiny::tags[[paste0("h", heading_level)]], list("Pupil and source-labelled blink trace")), shiny::p(summary), content,
    shiny::p("Points are saved observations. Red crosses retain excluded finite pupil values; blink ticks are positive source labels. Lines stop at invalid samples, phase changes and unsupported gaps. Blue shading marks the declared baseline window; the dashed line is its saved mean."),
    shiny::p(paste("Baseline:", b$status, "| supported duration", .brohn_gaze_trace_number(b$valid_ms), "ms.",
      "Eligibility means the declared duration and coverage were met; it does not establish physiological suitability.")),
    if (!is.null(numeric_download_id)) shiny::downloadButton(numeric_download_id, "Download exact selected values"),
    if (!is.null(artifact_download_id)) shiny::downloadButton(artifact_download_id, "Download complete source trace"),
    shiny::tags$details(shiny::tags$summary("Exact values and saved support"),
      shiny::p(paste("Pupil source:", brohn_default(model$support$pupil_source, "not mapped"))),
      shiny::p(paste("Blink source:", brohn_default(model$support$blink_source, "not mapped"))),
      shiny::p(brohn_gaze_blink_policy_disclosure(list(blink_boundary_policy = model$support$blink_boundary_policy))),
      shiny::p("Source rows are one-based CSV data rows; table rows are zero-based. The final sample has no inferred following interval. Arithmetic correction does not give an isolated sample duration support."),
      shiny::tags$div(style = "overflow-x:auto;max-width:100%", role = "region", tabindex = "0", `aria-label` = "Exact pupil and blink values, horizontally scrollable", numeric)))
}

# Standalone display export, derived only from the verified saved window.
# Complete values remain in its paired native JSON and typed source artifact.
brohn_gaze_trace_export_svg <- function(view) {
  model <- brohn_gaze_trace_plot_model(view)
  svg <- brohn_gaze_trace_svg(model)
  metadata <- list(schema = "brohn-gaze-trace-svg/1.0", trace_profile = view$trace_profile,
    binding = view$binding, artifact = view$artifact, source_provenance = view$source_provenance,
    identity = view$table$identity, table_id = view$table$table_id, range = view$range,
    selected_rows = view$selected_rows, support = view$table$support,
    display = "Exact selected observations and separate eligibility masks; SVG positions rounded to 0.001 display units. Native values remain in the paired saved window JSON and complete source artifact. No interpolation or physiological blink qualification.")
  escaped <- as.character(htmltools::htmlEscape(brohn_json(metadata)))
  svg <- sub('viewBox="0 0 940 510"', 'viewBox="0 0 940 590"', svg, fixed = TRUE)
  svg <- sub('<rect width="940" height="510" fill="white"/>', '<rect width="940" height="590" fill="white"/>', svg, fixed = TRUE)
  legend <- paste0('<metadata id="brohn-gaze-trace-source">', escaped, '</metadata>\n',
    '<text x="70" y="532" font-size="13" fill="#162f45">Red crosses: excluded finite source values. Ticks: positive source blink labels.</text>\n',
    '<text x="70" y="553" font-size="13" fill="#162f45">Shading: declared baseline window. Dashed line: saved mean. Gaps are not interpolated.</text>\n',
    '<text x="70" y="574" font-size="13" fill="#162f45">', view$selected_rows, ' source rows; exact identity, range and source hashes are embedded in metadata.</text>\n</svg>')
  sub('</svg>', legend, svg, fixed = TRUE)
}
