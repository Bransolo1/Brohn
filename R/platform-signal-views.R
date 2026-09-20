brohn_signal_label <- function(value) {
  labels <- c(clean = "Saved cleaned waveform", density_uv2_hz = "Power spectral density", density_ms2_hz = "Detected interval power spectrum", tonic_us = "Tonic conductance", phasic_us = "Phasic conductance",
    raw_us = "Recorded skin conductance", clean_us = "Cleaned skin conductance", cleaned_us = "Cleaned skin conductance",
    time_s = "Time", frequency_hz = "Frequency", amplitude_us = "Response amplitude", onset_time_s = "Response onset",
    temperature_c = "Temperature", acceleration_x_ms2 = "X-axis acceleration", acceleration_y_ms2 = "Y-axis acceleration",
    acceleration_z_ms2 = "Z-axis acceleration", vector_magnitude_ms2 = "Acceleration vector magnitude",
    vector_derivative_ms3 = "Change in the acceleration vector per second", enmo_g = "Acceleration norm minus one gravity",
    extreme = "Excursion extreme", end_time_s = "Last active sample", observed_span_s = "Observed duration", recovery_time_s = "Observed recovery")
  if (length(value) == 1L && value %in% names(labels)) unname(labels[[value]]) else gsub("_", " ", value, fixed = TRUE)
}
brohn_signal_number <- function(value) if (is.null(value)) "Unavailable" else format(signif(value, 6), trim = TRUE, scientific = FALSE)
brohn_signal_exact_number <- function(value) if (is.null(value)) "Unavailable" else format(value, digits = 17, trim = TRUE, scientific = FALSE)
brohn_signal_markers <- function(view) {
  m <- view$marker_overlay
  if (is.null(m)) return(NULL)
  brohn_require(identical(m$schema, "brohn-cardiac-marker-overlay/1.0") &&
    identical(m$review_status, "unreviewed_algorithm_detections") && m$status %in% c("available", "empty", "too_many_markers") &&
    m$event_type %in% c("r_peak", "systolic_pulse_peak") && identical(view$axis$value_column, "clean") &&
    identical(m$time_unit, "s") && identical(m$value_unit, view$axis$value_unit) &&
    identical(m$alignment, if (identical(m$status, "too_many_markers")) "not_checked_display_limit_exceeded" else "exact_source_sample_and_recorded_time"),
    "Reopen the verified cleaned-waveform view before inspecting its detections.")
  brohn_require(brohn_number(m$selected_marker_count, 0, 1e8, TRUE) && identical(as.numeric(m$limit), 2000) && brohn_array(m$markers) &&
    switch(m$status, available = length(m$markers) > 0 && length(m$markers) <= 2000L && length(m$markers) == m$selected_marker_count,
      empty = m$selected_marker_count == 0 && !length(m$markers), too_many_markers = m$selected_marker_count > 2000 && !length(m$markers)),
    "The saved detection display has incomplete marker support.")
  m
}
brohn_signal_marker_description <- function(view) {
  m <- brohn_signal_markers(view)
  if (is.null(m)) return(NULL)
  paste(brohn_signal_exact_number(m$selected_marker_count), "unreviewed algorithm detections in the selected window.",
    if (m$status == "available") "Hollow circles mark exact saved detections on the cleaned waveform; their positions are not interpolated from the display line."
    else if (m$status == "empty") "No saved detections fall in this window; this does not imply absent heartbeats or usable signal quality."
    else "No markers are drawn because the window exceeds the 2000-marker display limit. This counts saved event records; their waveform positions have not been checked. Narrow the time range to check each source sample.",
    if (m$event_type == "r_peak") "Detected R peaks and RR intervals have not been confirmed as normal-to-normal intervals."
    else "Detected systolic pulse peaks support PRV, not interchangeable ECG HRV.")
}
brohn_signal_marker_ui <- function(view) {
  m <- brohn_signal_markers(view)
  if (is.null(m)) return(NULL)
  rows <- lapply(m$markers, function(p) list(source_sample = brohn_signal_exact_number(p$source_sample_index),
    time_s = brohn_signal_exact_number(p$time_s), cleaned_value = brohn_signal_exact_number(p$value),
    previous_interval_ms = brohn_signal_exact_number(p$previous_interval_ms),
    interval_screen = if (is.null(p$previous_interval_plausible)) "Not available" else if (isTRUE(p$previous_interval_plausible)) "Within declared bounds" else "Outside declared bounds",
    series_table = p$series_table_id, event_table = p$event_table_id, event_row = brohn_signal_exact_number(p$event_row_index)))
  shiny::div(class = "brohn-cardiac-markers", `data-marker-status` = m$status,
    shiny::h3(if (m$event_type == "r_peak") "Unreviewed R-peak detections" else "Unreviewed pulse-peak detections"),
    shiny::p(if (m$status == "available") paste(length(rows), "saved detections. Hollow circles mark their exact cleaned-waveform values.",
      if (m$event_type == "r_peak") "Normal-to-normal intervals are not confirmed." else "These are pulse intervals (PRV), not interchangeable ECG HRV.")
      else if (m$status == "empty") "No saved detections fall in this window. This does not imply absent heartbeats or usable signal quality."
      else paste(brohn_signal_exact_number(m$selected_marker_count), "saved event records exceed the 2000-marker display limit. Their waveform positions have not been checked; no partial overlay is drawn.")),
    if (m$status == "too_many_markers") shiny::p("To check each source sample, clear 'Show the complete recorded range', enter a shorter start and end, then choose 'Show signal'. The complete event output remains downloadable from the report."),
    if (length(rows)) shiny::tags$details(class = "brohn-cardiac-marker-table", shiny::tags$summary(paste("Inspect all", length(rows), "selected detections")),
      shiny::p("This is the saved cleaned waveform. Opening this view does not review, correct or approve a detection. The original recording and complete processed output remain available from the report."),
      shiny::p("Sample and event-row indices are zero-based. A saved previous interval may begin before this displayed window. Unavailable means no interval was saved; outside declared bounds is a plausibility flag, not a beat classification. Values below retain full numeric precision; the JSON also retains source and segment identities."),
      brohn_table(rows, maximum = 2000L, label = "Exact saved detection coordinates and intervals", labels = c("Source sample", "Time (s)",
        paste0("Cleaned value (", m$value_unit, ")"), "Previous interval (ms)", "Interval screen", "Waveform table", "Event table", "Event row"))))
}
brohn_signal_interval_spectra <- function(view) {
  if (!identical(view$axis$kind, "frequency") || !identical(view$axis$value_column, "density_ms2_hz")) return(list())
  Filter(function(s) identical(s$schema, "brohn-cardiac-interval-spectrum/1.0") && identical(s$status, "available") &&
    identical(s$density_unit, "ms^2/Hz") && identical(s$normal_to_normal_confirmed, FALSE),
    lapply(view$tables, function(t) t$support$interval_spectrum))
}
brohn_signal_interval_spectrum_ui <- function(view) {
  spectra <- brohn_signal_interval_spectra(view)
  if (!length(spectra)) return(NULL)
  shiny::tagList(lapply(spectra, function(s) shiny::div(class = "brohn-stack",
    shiny::p(shiny::strong(s$rhythm_basis), ". Detected intervals require review; these results do not establish normal-to-normal HRV. LF/HF is not a stress or sympathovagal-balance measure."),
    shiny::p(paste("Welch density from linearly interpolated intervals at", brohn_signal_number(s$interpolation_hz), "Hz;",
      s$window, "window of", brohn_signal_number(s$window_s), "s;", brohn_signal_number(s$overlap_fraction*100),
      "% overlap; constant detrending per segment;", brohn_signal_number(s$support$welch_segments), "averaged windows.",
      "Bin width:", brohn_signal_number(s$frequency_bin_width_hz), "Hz.")),
    brohn_table(lapply(s$bands, function(b) list(band = b$name,
      frequency_interval_hz = paste0(if (isTRUE(b$lower_inclusive)) "[" else "(", brohn_signal_number(b$lower_hz), ", ",
        brohn_signal_number(b$upper_hz), if (isTRUE(b$upper_inclusive)) "]" else ")"),
      full_spectrum_power_ms2 = s$integrated_bands_ms2[[b$name]])), label = "Full spectrum band power in ms squared"),
    shiny::p(class = "brohn-muted", paste("Band powers sum the complete included density bins multiplied by their bin width; no band-edge interpolation.",
      "These saved full-spectrum powers do not change when you narrow the displayed frequency range.",
      brohn_signal_number(s$support$plausible_interval_count), "plausible intervals over a detected peak span of",
      brohn_signal_number(s$support$detected_peak_span_s), "s; minimum required span", brohn_signal_number(s$support$minimum_peak_span_s), "s.",
      "No rejected intervals, extrapolation or automatic beat correction entered this spectrum.")))))
}
brohn_signal_explorer_ui <- function(report) {
  items <- Filter(function(a) a$kind %in% c("physiology-series", "physiology-events") && isTRUE(a$complete), report$body$analysis$artifacts)
  if (!length(items)) return(NULL)
  shiny::tagList(brohn_card(title = "Explore processed signals", subtitle = "Inspect the saved recording, then choose a channel, measure and time window. Views preserve peaks and gaps in the complete output.",
    shiny::div(class = "brohn-toolbar", lapply(items, function(a) brohn_command(
      if (a$kind == "physiology-series") "Explore signal traces and spectra" else if (identical(report$body$analysis$kind, "eeg")) "Explore frequency spectra" else "Explore events and spectral features", "open_signal_catalog",
      list(report_id = report$id, report_hash = brohn_hash(report$body), kind = a$kind))))),
    shiny::uiOutput("signal_progress"), shiny::uiOutput("signal_catalog"), shiny::uiOutput("signal_plot"),
    shiny::uiOutput("signal_annotation_controls"),shiny::uiOutput("signal_annotation_editor"),
    shiny::uiOutput("signal_annotation_progress"),shiny::uiOutput("signal_annotation_summary"))
}
brohn_signal_svg <- function(view, title = NULL, width = 920) {
  brohn_require(identical(view$schema, "brohn-signal-preview/1.0"), "Choose a saved signal preview.")
  if (!length(view$envelopes)) return(NULL)
  spectra <- brohn_signal_interval_spectra(view)
  overlay <- brohn_signal_markers(view)
  markers <- overlay$markers
  title <- brohn_default(title, paste(brohn_signal_label(view$axis$value_column), "in", view$axis$value_unit))
  xlim <- unlist(view$effective_range); ylim <- unlist(view$selected_range$eligible_value_range)
  brohn_require(length(xlim) == 2L && length(ylim) == 2L && all(is.finite(c(xlim, ylim))), "This signal has no finite supported plot range.")
  if (length(markers)) {
    marker_x <- vapply(markers, `[[`, numeric(1), "time_s"); marker_y <- vapply(markers, `[[`, numeric(1), "value")
    brohn_require(all(is.finite(c(marker_x, marker_y))) && all(marker_x >= xlim[1L] & marker_x <= xlim[2L]), "A saved detection falls outside its exact signal window.")
    ylim <- range(c(ylim, marker_y))
  }
  if (diff(xlim) == 0) xlim <- xlim + c(-0.5, 0.5)
  ypad <- if (diff(ylim) == 0) max(abs(ylim[1L])*0.05, 0.05) else diff(ylim)*0.06
  ylim <- ylim + c(-ypad, ypad)
  if (length(spectra) && view$selected_range$eligible_value_range[[1L]] >= 0) ylim[1L] <- 0
  brohn_require(brohn_number(width, 300, 1600, TRUE), "Choose a supported chart width.")
  compact <- width < 560
  height <- if (compact) 300 else 360; left <- if (compact && length(spectra)) 80 else if (compact) 68 else 94; right <- if (compact) 20 else 28; top <- 22; bottom <- 66
  tick_label <- function(value) if (compact) format(signif(value, 3), trim = TRUE) else brohn_signal_number(value)
  sx <- function(x) left + (x-xlim[1L])/diff(xlim)*(width-left-right)
  sy <- function(y) height-bottom - (y-ylim[1L])/diff(ylim)*(height-top-bottom)
  n <- function(x) formatC(x, digits = 3, format = "f", decimal.mark = ".")
  band_regions <- if (length(spectra) == 1L) shiny::tagList(lapply(spectra[[1L]]$bands, function(b) {
    low <- max(xlim[1L], b$lower_hz); high <- min(xlim[2L], b$upper_hz)
    if (high <= low) return(NULL)
    shiny::tags$rect(x = n(sx(low)), y = top, width = n(sx(high)-sx(low)), height = height-top-bottom,
      fill = if (identical(b$name, "LF")) "#6682c4" else "#4ebaa6", `fill-opacity` = 0.16,
      shiny::tags$title(paste(b$name, "band", b$lower_hz, "to", b$upper_hz, "Hz; full band power is listed below")))
  })) else NULL
  ticks_x <- seq(xlim[1L], xlim[2L], length.out = if (compact) 3 else 5); ticks_y <- seq(ylim[1L], ylim[2L], length.out = 5)
  grid <- shiny::tagList(lapply(ticks_y, function(y) shiny::tagList(
    shiny::tags$line(x1 = left, x2 = width-right, y1 = n(sy(y)), y2 = n(sy(y)), stroke = "#3f5058", `stroke-width` = 1),
    shiny::tags$text(x = left-10, y = n(sy(y)+4), `text-anchor` = "end", fill = "#d2dedd", `font-size` = 12, tick_label(y)))),
    lapply(ticks_x, function(x) shiny::tags$text(x = n(sx(x)), y = height-bottom+24, `text-anchor` = "middle", fill = "#d2dedd", `font-size` = 12, tick_label(x))))
  traces <- lapply(view$fragments, function(fragment) {
    bins <- Filter(function(b) identical(b$fragment_id, fragment$id), view$envelopes)
    points <- unlist(lapply(bins, `[[`, "points"), recursive = FALSE)
    if (!length(points)) return(NULL)
    xs <- vapply(points, `[[`, numeric(1), "x"); ys <- vapply(points, `[[`, numeric(1), "y")
    brohn_require(all(is.finite(c(xs, ys))), "A plotted fragment contains an unavailable coordinate.")
    description <- paste(fragment$table_id, "\u00b7", fragment$rows, "eligible rows; begins after", brohn_signal_label(fragment$break_before))
    if (identical(fragment$connection_policy, "within_this_fragment_only") && length(points) > 1L)
      shiny::tags$polyline(points = paste(paste0(n(sx(xs)), ",", n(sy(ys))), collapse = " "), fill = "none", stroke = "#a7e9d3", `stroke-width` = 1.8,
        `vector-effect` = "non-scaling-stroke", shiny::tags$title(description)) else shiny::tagList(lapply(points, function(p)
          shiny::tags$circle(cx = n(sx(p$x)), cy = n(sy(p$y)), r = 2.5, fill = "#a7e9d3", shiny::tags$title(paste(description,
            "\u00b7", brohn_signal_number(p$x), view$axis$unit, "\u00b7", brohn_signal_number(p$y), view$axis$value_unit, "\u00b7 row", p$row_index)))))
  })
  marker_nodes <- lapply(markers, function(p) shiny::tags$circle(class = "brohn-cardiac-marker", cx = n(sx(p$time_s)), cy = n(sy(p$value)), r = 4,
    fill = "none", stroke = "#ffc28b", `stroke-width` = 2, `vector-effect` = "non-scaling-stroke",
    `data-source-sample` = brohn_signal_exact_number(p$source_sample_index), `data-event-row` = brohn_signal_exact_number(p$event_row_index),
    `data-event-table` = p$event_table_id, `data-series-table` = p$series_table_id,
    shiny::tags$title(paste("Unreviewed algorithm detection; source sample", brohn_signal_exact_number(p$source_sample_index),
      "at", brohn_signal_exact_number(p$time_s), "s; cleaned value", brohn_signal_exact_number(p$value), overlay$value_unit,
      "; previous interval", brohn_signal_exact_number(p$previous_interval_ms), "ms;", p$event_table_id, "row", brohn_signal_exact_number(p$event_row_index)))))
  shiny::tags$svg(xmlns = "http://www.w3.org/2000/svg", viewBox = paste(0, 0, width, height), width = "100%", role = "img",
    `aria-labelledby` = paste0("brohn-signal-title-", width, " brohn-signal-description-", width), style = "display:block;max-width:100%;background:#131d24;border-radius:12px;font-family:system-ui,sans-serif",
    shiny::tags$title(id = paste0("brohn-signal-title-", width), title),
    shiny::tags$desc(id = paste0("brohn-signal-description-", width), paste(view$selected_range$eligible_value_rows, "eligible observations summarized without joining gaps.",
      "Exact selected minimum", brohn_signal_number(view$selected_range$eligible_value_range[[1L]]), "and maximum", brohn_signal_number(view$selected_range$eligible_value_range[[2L]]), view$axis$value_unit,
      ". The numerical summary and full output download accompany this chart.",
      if (length(spectra)) paste(vapply(spectra, `[[`, character(1), "rhythm_basis"), collapse = "; "),
      brohn_signal_marker_description(view))), band_regions, grid, traces, marker_nodes,
    shiny::tags$text(x = (left+width-right)/2, y = height-12, `text-anchor` = "middle", fill = "#edf5f3", `font-size` = 14,
      paste(if (view$axis$kind == "frequency") "Frequency" else if (view$axis$kind == "event") "Event onset" else "Time", paste0("(", view$axis$unit, ")"))),
    shiny::tags$text(x = 18, y = (top+height-bottom)/2, transform = paste0("rotate(-90 18 ", (top+height-bottom)/2, ")"), `text-anchor` = "middle", fill = "#edf5f3", `font-size` = 14, view$axis$value_unit))
}
brohn_signal_plot_ui <- function(saved) {
  view <- saved$body$view; selected <- view$selected_range; full <- view$full_range
  rows <- lapply(list(list(label = "Full selected tables", s = full), list(label = "Selected window", s = selected)), function(x)
    list(scope = x$label, source_rows = x$s$rows, eligible_rows = x$s$eligible_value_rows,
      missing_values = x$s$missing_value_rows, missing_coordinates = x$s$missing_coordinate_rows,
      excluded_rows = x$s$excluded_retention_rows,
      eligible_minimum = if (is.null(x$s$eligible_value_range)) NULL else x$s$eligible_value_range[[1L]],
      eligible_maximum = if (is.null(x$s$eligible_value_range)) NULL else x$s$eligible_value_range[[2L]]))
  brohn_card(title = brohn_signal_label(view$axis$value_column),
    subtitle = paste(view$selection$channel, "\u00b7", view$selection$recording_id, "\u00b7", view$axis$value_unit),
    if (view$status == "empty_range") shiny::p("No eligible observations fall in this window. Choose another range or inspect the support counts below.") else
      shiny::div(role = "region", `aria-label` = "Processed signal chart",
        shiny::div(class = "brohn-signal-wide", brohn_signal_svg(view)),
        shiny::div(class = "brohn-signal-compact", brohn_signal_svg(view, width = 320))),
    shiny::p(paste(brohn_signal_number(selected$eligible_value_rows), "eligible values in this window across", length(view$fragments),
      if (length(view$fragments) == 1L) "continuous section." else "continuous sections.",
      "The plot preserves observed peaks within each bin. Gaps are left disconnected.")),
    brohn_signal_interval_spectrum_ui(view),
    brohn_signal_marker_ui(view),
    brohn_table(rows, label = "Exact source and selected signal support"),
    shiny::p(class = "brohn-muted", paste("Clock reference:", view$axis$reference, "\u00b7 original origin:", brohn_default(view$axis$source_time_origin, "not supplied"), brohn_default(view$axis$source_time_unit, ""))),
    shiny::div(class = "brohn-toolbar", if (length(view$envelopes)) shiny::downloadButton("signal_svg_download", "Download chart", icon = NULL),
      shiny::downloadButton("signal_json_download", "Download view + provenance", icon = NULL)),
    shiny::tags$details(shiny::tags$summary("View support and boundaries"), brohn_table(view$fragments, label = "Disconnected signal support fragments"),
      shiny::p("This view is linked to its immutable report and full processed artifact. Changing the window does not recalculate or replace the scientific result.")))
}
brohn_install_signal_server <- function(input, output, session, store, state, attempt, message, prepare_download) {
  selection <- shiny::reactiveValues(report_id = NULL, kind = NULL, catalog_job = NULL, preview_job = NULL)
  report <- shiny::reactive({shiny::req(identical(state$page, "report"), state$report_id); brohn_get_entity(store, "report", state$report_id)})
  context <- shiny::reactive({r <- report(); shiny::req(identical(r$id, selection$report_id)); r})
  jobs <- shiny::reactive({context(); shiny::invalidateLater(1000, session)
    list(catalog = if (!is.null(selection$catalog_job)) brohn_get_job(store, selection$catalog_job), preview = if (!is.null(selection$preview_job)) brohn_get_job(store, selection$preview_job))})
  saved <- function(which) {
    value <- shiny::reactiveVal(NULL)
    shiny::observe({job <- jobs()[[which]]
      if (is.null(job) || !identical(job$status, "succeeded") || is.null(job$result$signal_view_id)) {value(NULL); return()}
      record <- brohn_get_entity(store, "signal_view", job$result$signal_view_id)
      if (!identical(record$body$report_id, context()$id)) value(NULL) else value(record)
    })
    # reactiveVal ignores identical snapshots. Progress polls must not recreate a
    # completed catalog's inputs, reset a typed range, or erase an error correction.
    shiny::reactive({r <- value(); shiny::req(r, identical(r$body$report_id, context()$id)); r})
  }
  catalog <- saved("catalog"); preview <- saved("preview")
  current_catalog <- shiny::reactive({r <- catalog(); shiny::req(identical(input$signal_form_identity, paste(context()$id, r$id, sep = ":"))); r})
  table <- shiny::reactive({c <- current_catalog(); shiny::req(input$signal_table); matches <- Filter(function(t) identical(t$table_id, input$signal_table), c$body$view$tables)
    shiny::req(length(matches) == 1L); matches[[1L]]})
  shiny::observeEvent(input$open_signal_catalog, attempt(function() {
    r <- report(); command <- input$open_signal_catalog
    brohn_require(identical(command$report_id, r$id) && identical(command$report_hash, brohn_hash(r$body)), "Reopen this report before exploring its signals.")
    job <- brohn_queue_signal_view(store, r$id, command$kind)
    selection$report_id <- r$id; selection$kind <- command$kind; selection$catalog_job <- job$id; selection$preview_job <- NULL
    message("Reading the complete processed artifact in the background.")
  }))
  for (direction in c("previous", "next")) local({dir <- direction; shiny::observeEvent(input[[paste0("signal_page_", dir)]], attempt(function() {
    c <- current_catalog(); p <- c$body$view$pagination
    offset <- if (dir == "next") p$next_offset else max(0L, p$offset-p$limit)
    brohn_require(!is.null(offset), "There are no more tables on that page.")
    job <- brohn_queue_signal_view(store, context()$id, selection$kind, offset = offset)
    selection$catalog_job <- job$id; selection$preview_job <- NULL
  }))})
  output$signal_progress <- shiny::renderUI({j <- Filter(Negate(is.null), jobs()); if (!length(j)) return(NULL)
    active <- Filter(function(x) x$status != "succeeded", j); if (!length(active)) return(NULL)
    brohn_card(title = "Signal view progress", lapply(active, function(job) shiny::div(class = "brohn-stack",
      brohn_badge(switch(job$status, running = "Reading verified output", queued = "Queued", job$status)),
      if (!is.null(job$error)) shiny::p(job$error$message),
      if (job$status %in% c("running", "queued")) brohn_command("Cancel view", "cancel_processing", job$id),
      if (job$status %in% c("failed", "cancelled")) shiny::p("Your report and complete output remain available. Reopen the explorer or choose a narrower view to retry."))))
  })
  output$signal_catalog <- shiny::renderUI({c <- catalog(); v <- c$body$view; p <- v$pagination
    choices <- stats::setNames(vapply(v$tables, `[[`, character(1), "table_id"), vapply(v$tables, function(t) paste(
      t$identity$channel, "\u00b7", t$coordinates$axis, "\u00b7", t$identity$recording_id,
      if (!is.null(t$identity$group$participant_id)) paste("\u00b7", t$identity$group$participant_id), "\u00b7", t$table_id), character(1)))
    brohn_card(title = "Choose a signal view", subtitle = paste("Showing", p$returned, "tables from position", p$offset+1L, "of", p$total_tables, "saved tables."),
      shiny::tags$input(id = "signal_form_identity", type = "text", class = "shiny-input-text", value = paste(context()$id, c$id, sep = ":"), style = "display:none", `aria-hidden` = "true", tabindex = "-1"),
      if (length(choices)) shiny::selectInput("signal_table", "Recording and channel", choices),
      shiny::uiOutput("signal_measure_controls"),
      shiny::div(class = "brohn-toolbar", if (p$offset > 0) shiny::actionButton("signal_page_previous", "Previous tables"), if (!is.null(p$next_offset)) shiny::actionButton("signal_page_next", "Next tables")))
  })
  output$signal_measure_controls <- shiny::renderUI({t <- table(); c <- current_catalog()
    choices <- stats::setNames(vapply(t$value_columns, `[[`, character(1), "name"), vapply(t$value_columns, function(v) paste(brohn_signal_label(v$name), paste0("(", v$unit, ")")), character(1)))
    if (!length(choices)) return(shiny::p("This table has no numeric measurement columns to plot."))
    shiny::tagList(shiny::tags$input(id = "signal_measure_identity", type = "text", class = "shiny-input-text", value = paste(c$id, t$table_id, sep = ":"), style = "display:none", `aria-hidden` = "true", tabindex = "-1"),
      shiny::selectInput("signal_measure", "Processed measure", choices),
      shiny::checkboxInput("signal_full_range", "Show the complete recorded range", TRUE),
      shiny::conditionalPanel("!input.signal_full_range", shiny::div(class = "brohn-form-grid",
        shiny::numericInput("signal_range_start", paste("Start", paste0("(", t$coordinate_column$unit, ")")), if (length(t$coordinate_range)) t$coordinate_range[[1L]] else NA_real_),
        shiny::numericInput("signal_range_end", paste("End", paste0("(", t$coordinate_column$unit, ")")), if (length(t$coordinate_range)) t$coordinate_range[[2L]] else NA_real_))),
      shiny::actionButton("create_signal_preview", "Show signal", class = "btn-primary"))
  })
  shiny::observeEvent(input$create_signal_preview, attempt(function() {
    r <- context(); c <- current_catalog(); t <- table()
    brohn_require(identical(input$signal_measure_identity, paste(c$id, t$table_id, sep = ":")), "Wait for this recording's controls before creating its view.")
    brohn_require(input$signal_measure %in% vapply(t$value_columns, `[[`, character(1), "name"), "Choose a processed measure from this table.")
    chosen <- list(table_ids = list(t$table_id), recording_id = t$identity$recording_id, channel = t$identity$channel,
      value_column = input$signal_measure, range = if (isTRUE(input$signal_full_range)) NULL else list(input$signal_range_start, input$signal_range_end))
    job <- brohn_queue_signal_view(store, r$id, selection$kind, chosen)
    selection$preview_job <- job$id; message("Building the view from the complete processed output.")
  }))
  output$signal_plot <- shiny::renderUI(brohn_signal_plot_ui(preview()))
  output$signal_json_download <- shiny::downloadHandler(filename = function() paste0(preview()$id, ".json"),
    content = function(file) prepare_download(function() brohn_copy_object_download(store, preview()$body$result_object$hash, file)), contentType = "application/json")
  output$signal_svg_download <- shiny::downloadHandler(filename = function() paste0(preview()$id, ".svg"),
    content = function(file) prepare_download(function() {svg <- brohn_signal_svg(preview()$body$view); brohn_require(!is.null(svg), "This view has no supported chart.")
      writeLines(enc2utf8(as.character(svg)), file, useBytes = TRUE)}), contentType = "image/svg+xml")
  brohn_install_signal_annotations_ui(input,output,session,store,state,attempt,message,prepare_download,context,catalog,table)
  invisible(NULL)
}
