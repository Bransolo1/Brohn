# Read-only neural views of the complete bounded arrays in an immutable report.
# No averaging across cells, spectral estimation or baseline correction runs here.
.brohn_np_supported <- function(report) identical(report$analysis$kind, "eeg") &&
  identical(report$analysis$engine$name, "Brohn neural worker")
.brohn_np_number <- function(x) if (is.null(x)) "Unavailable" else format(signif(x, 6), trim = TRUE)
.brohn_np_key <- function(x, channel = FALSE) brohn_hash(x[c("recording_id", "condition_id", "group", if (channel) "channel")])
.brohn_np_vector <- function(x, n = NULL, nullable = FALSE, lower = -Inf, upper = Inf) {
  brohn_require((is.list(x) && is.null(names(x)) || is.numeric(x)) && length(x) > 0L &&
    (is.null(n) || length(x) == n), "A saved neural axis/array is absent or has an inconsistent length.")
  brohn_require(all(vapply(as.list(x), function(v) is.null(v) && nullable || brohn_number(v, lower, upper), logical(1))),
    "Saved neural values must be finite numbers or explicit permitted nulls; text and boolean values cannot become measurements.")
  vapply(as.list(x), function(v) if (is.null(v)) NA_real_ else as.numeric(v), numeric(1))
}

brohn_neural_plot_model <- function(report) {
  brohn_require(.brohn_np_supported(report), "This report has no registered neural waveform adapter.")
  a <- report$analysis; p <- report$provenance
  brohn_require(identical(a$schema, "brohn-worker-result/1.0") && identical(a$modality, "eeg"), "The saved neural schema is unsupported.")
  brohn_require(brohn_text(p$source$hash, 64) && grepl("^[a-f0-9]{64}$", p$source$hash) &&
    identical(a$source$sha256, p$source$hash), "The neural arrays disagree with the pinned source hash.")
  brohn_require(identical(a$quality$participant_inference_performed, FALSE), "This adapter requires the saved within-recording scope.")
  series <- brohn_default(a$series, list()); recordings <- brohn_default(a$recordings, list())
  brohn_require(length(series) <= 10000L && length(recordings) <= 10000L, "The report exceeds the bounded neural view catalog.")
  expected <- c(erp = "eeg-erp-epochs/1.0", morlet = "eeg-morlet-epochs/1.0", frequency_tagging_psd = "eeg-frequency-tagging/1.0")
  hashes <- vapply(recordings, .brohn_np_key, character(1)); brohn_require(!anyDuplicated(hashes), "Duplicate recording/condition identities cannot be pooled in this view.")
  for (r in recordings) {
    brohn_require(brohn_text(r$recording_id, 500) && brohn_text(r$condition_id, 500) && is.list(r$group), "Recording support lacks its source identity.")
    brohn_require(all(vapply(r[c("requested_trials", "retained_trials", "excluded_trials", "minimum_trials")],
      brohn_number, logical(1), min = 0, max = 10000, integer = TRUE)) &&
      all(c("requested_trials", "retained_trials", "excluded_trials", "minimum_trials") %in% names(r)) &&
      r$requested_trials == r$retained_trials+r$excluded_trials, "Saved trial counts are inconsistent.")
  }
  total <- 0L; report_hash <- brohn_hash(report)
  cells <- lapply(series, function(s) {
    brohn_require(brohn_text(s$channel, 500) && brohn_text(s$type, 100) && s$type %in% names(expected), "Unregistered neural series type or missing channel.")
    index <- which(hashes == .brohn_np_key(s)); brohn_require(length(index) == 1L, "A neural series has no exact recording/condition/source-group support.")
    r <- recordings[[index]]; settings <- a$parameters[[s$recording_id]]
    brohn_require(identical(settings$recipe, unname(expected[[s$type]])) && identical(r$status, "computed") &&
      identical(s$trial_count, r$retained_trials) && s$trial_count >= r$minimum_trials &&
      identical(s$origin, r$origin) && identical(s$origin, report$origin), "The series recipe, origin or retained trial support disagrees with its recording.")
    brohn_require(brohn_text(settings$event_source) && brohn_text(settings$settings_source) && is.list(settings$reference) &&
      is.list(settings$filter) && "baseline_s" %in% names(settings), "The saved event, baseline and processing declarations are incomplete.")
    axis <- .brohn_np_vector(if (s$type == "frequency_tagging_psd") s$frequency_hz else s$time_s)
    brohn_require(all(diff(axis) > 0), "The saved neural axis is not strictly increasing. The view will not sort or repair it.")
    brohn_require(brohn_number(r$sampling_rate, 1, 100000) && brohn_number(r$sample_count_per_epoch, 1, 10000000, TRUE), "The saved sampling support is absent.")
    if (s$type == "frequency_tagging_psd") {
      fft <- r$derived_settings$n_fft
      brohn_require(brohn_number(fft, 4, 10000000, TRUE) && length(axis) == floor(fft/2)+1L &&
        max(abs(axis-(seq_along(axis)-1L)*r$sampling_rate/fft)) <= 1e-8, "Saved spectral bins disagree with the exact FFT sampling grid.")
    } else {
      edge <- if (s$type == "morlet") r$derived_settings$edge_exclusion_samples_each_side else 0L
      brohn_require(brohn_number(edge, 0, r$sample_count_per_epoch, TRUE) && length(axis) == r$sample_count_per_epoch-2L*edge &&
        max(abs(axis-(settings$epoch_s[[1L]]+(edge+seq_along(axis)-1L)/r$sampling_rate))) <= 1e-8,
        "Saved event-relative samples disagree with the declared epoch and excluded edges. Gaps will not be joined.")
    }
    n <- length(axis); values <- list(); frequencies <- NULL
    if (s$type == "erp") {
      values$mean_uv <- .brohn_np_vector(s$mean_uv, n)
      values$sem_uv <- .brohn_np_vector(s$sem_uv, n, TRUE, 0)
      brohn_require(identical(s$sem_scope, "within_recording_trials; not participant inference"), "ERP uncertainty does not have the declared within-trial scope.")
      brohn_require(s$trial_count > 1 || all(is.na(values$sem_uv)), "A single trial cannot provide a saved trial SEM.")
    } else if (s$type == "frequency_tagging_psd") values$density_uv2_hz <- .brohn_np_vector(s$density_uv2_hz, n, TRUE, 0) else {
      frequencies <- .brohn_np_vector(s$frequency_hz, lower = 0)
      brohn_require(all(diff(frequencies) > 0) && identical(unlist(s$array_axes, use.names = FALSE), c("frequency", "time")), "Morlet axes must explicitly be frequency by time, in original order.")
      brohn_require(identical(frequencies, as.numeric(unlist(settings$frequencies_hz, use.names = FALSE))), "Morlet frequencies disagree with the frozen recipe.")
      unit <- switch(settings$power_baseline$mode, none = "uV^2 (wavelet power)", subtract = "uV^2 (wavelet power)", ratio = "ratio", percent = "percent", db = "dB", NULL)
      brohn_require(!is.null(unit) && identical(s$transformed_unit, unit), "Morlet baseline transform and saved units disagree.")
      for (field in c("power_uv2", "transformed_power", "itc")) {
        brohn_require(is.list(s[[field]]) && length(s[[field]]) == length(frequencies), "A Morlet matrix has inconsistent frequency rows.")
        values[[field]] <- lapply(s[[field]], .brohn_np_vector, n = n, nullable = TRUE,
          lower = if (field %in% c("power_uv2", "itc")) 0 else -Inf, upper = if (field == "itc") 1 else Inf)
      }
    }
    total <<- total + n + length(frequencies) + sum(vapply(values, function(v) length(unlist(v, use.names = FALSE)), integer(1)))
    brohn_require(total <= 500000L, "The saved neural arrays exceed the complete 500,000-value worker bound.")
    features <- Filter(function(f) identical(.brohn_np_key(f, TRUE), .brohn_np_key(s, TRUE)), a$features)
    for (f in features) brohn_require(identical(f$scope, "recording_condition") && identical(f$trial_count, s$trial_count), "A saved feature has a different trial scope.")
    identity <- s[c("recording_id", "condition_id", "group", "channel", "origin")]
    parts <- c(paste("Recording", s$recording_id), paste("condition", s$condition_id), paste("channel", s$channel),
      vapply(names(s$group), function(name) paste(name, brohn_json(s$group[[name]])), character(1)))
    list(selector = paste(report_hash, .brohn_np_key(s, TRUE), sep = ":"), label = paste(parts, collapse = " | "),
      identity = identity, type = s$type, source = s, axis = axis, frequencies = frequencies, values = values,
      support = r, parameters = settings, features = features)
  })
  brohn_require(!anyDuplicated(vapply(cells, `[[`, character(1), "selector")), "Duplicate neural channel cells cannot be merged.")
  list(report_id = report$id, report_hash = report_hash, source_hash = p$source$hash, origin = report$origin,
    provenance = p, processing = report$processing, quality = a$quality, cells = cells, recordings = recordings)
}

brohn_neural_plot_selection <- function(model, selector = NULL, metric = NULL, frequency_hz = NULL, start_index = 1L, maximum_points = 2000L) {
  brohn_require(length(model$cells) > 0L, "No supported channel waveform was retained. See the saved trial support and exclusion reasons.")
  if (is.null(selector)) selector <- model$cells[[1L]]$selector
  hits <- Filter(function(x) identical(x$selector, selector), model$cells)
  brohn_require(length(hits) == 1L, "Choose a channel cell belonging to this exact saved report.")
  cell <- hits[[1L]]
  allowed <- switch(cell$type, erp = "mean_uv", frequency_tagging_psd = "density_uv2_hz", morlet = c("transformed_power", "power_uv2", "itc"))
  metric <- brohn_default(metric, allowed[[1L]]); brohn_require(metric %in% allowed, "Choose a retained measure for this channel cell.")
  fi <- NULL
  if (cell$type == "morlet") {
    frequency_hz <- brohn_default(frequency_hz, cell$frequencies[[1L]])
    brohn_require(brohn_number(frequency_hz) && frequency_hz %in% cell$frequencies, "Choose one exact recorded Morlet frequency. Frequencies are not interpolated.")
    fi <- match(frequency_hz, cell$frequencies)
  }
  brohn_require(brohn_number(start_index, 1, length(cell$axis), TRUE) && brohn_number(maximum_points, 1, 2000, TRUE), "Choose a saved sample index and a plot window of at most 2,000 points.")
  indices <- seq.int(start_index, min(length(cell$axis), start_index+maximum_points-1L))
  y <- if (is.null(fi)) cell$values[[metric]] else cell$values[[metric]][[fi]]
  unit <- switch(metric, mean_uv = "uV", density_uv2_hz = "uV^2/Hz", transformed_power = cell$source$transformed_unit, power_uv2 = "uV^2 (wavelet power)", itc = "proportion (0 to 1)")
  label <- switch(metric, mean_uv = "Evoked voltage", density_uv2_hz = "Mean trial spectral density", transformed_power = paste("Morlet", cell$parameters$power, "power after the declared baseline transform"),
    power_uv2 = paste("Morlet", cell$parameters$power, "power before the power-baseline transform"), itc = "Inter-trial phase consistency of the original total signal")
  rows <- lapply(indices, function(i) list(sample_index = i, coordinate = cell$axis[[i]], value = if (is.na(y[[i]])) NULL else y[[i]],
    sem_uv = if (cell$type == "erp" && !is.na(cell$values$sem_uv[[i]])) cell$values$sem_uv[[i]] else NULL))
  list(schema = "brohn-neural-plot/1.0", report_hash = model$report_hash, source_hash = model$source_hash, cell = cell,
    selector = selector, metric = metric, frequency_hz = frequency_hz, unit = unit, label = label,
    axis_unit = if (cell$type == "frequency_tagging_psd") "Hz" else "s from measured event onset",
    indices = indices, x = cell$axis[indices], y = y[indices], sem = if (cell$type == "erp") cell$values$sem_uv[indices] else NULL,
    rows = rows, total_points = length(cell$axis), missing_points = sum(is.na(y)), window_missing_points = sum(is.na(y[indices])))
}

# Each path contains adjacent available samples only. Disjoint/null support is
# disconnected; shaded ERP uncertainty is mean +/- the already-saved trial SEM.
brohn_neural_plot_svg <- function(view, width = 680) {
  brohn_require(width %in% c(320, 680), "Use the accessible compact or wide chart layout.")
  height <- 330; left <- 76; right <- width-20; top <- 28; bottom <- 265
  yr <- view$y; if (!is.null(view$sem)) yr <- c(yr, view$y-view$sem, view$y+view$sem)
  yr <- yr[is.finite(yr)]; if (!length(yr)) return(NULL)
  xrange <- range(view$x); if (diff(xrange) == 0) xrange <- xrange+c(-.5, .5)
  yrange <- if (view$metric == "itc") c(0, 1) else range(c(0, yr))
  if (diff(yrange) == 0) yrange <- yrange+c(-1, 1)
  ticks <- pretty(yrange, n = 3)
  ticks <- ticks[is.finite(ticks) & ticks >= yrange[[1L]] & ticks <= yrange[[2L]]]
  # Tick labels are display annotations only. A sub-femtovolt residual in the
  # actual waveform remains untouched in geometry, numerical rows and exports.
  tick_label <- function(x) format(signif(x, 3), trim = TRUE)
  px <- function(x) left+(x-xrange[[1L]])/diff(xrange)*(right-left)
  py <- function(y) bottom-(y-yrange[[1L]])/diff(yrange)*(bottom-top)
  fmt <- function(x) formatC(x, digits = 3, format = "f", decimal.mark = ".")
  runs <- function(ok) {ids <- cumsum(c(TRUE, diff(ok) != 0)); unname(split(which(ok), ids[ok]))}
  groups <- runs(is.finite(view$y)); bands <- if (is.null(view$sem)) list() else runs(is.finite(view$y) & is.finite(view$sem))
  line <- function(x1, y1, x2, y2, ...) shiny::tags$line(x1 = fmt(x1), y1 = fmt(y1), x2 = fmt(x2), y2 = fmt(y2), ...)
  title <- paste(view$label, if (!is.null(view$frequency_hz)) paste("at", view$frequency_hz, "Hz"), "in", view$unit, "|", view$cell$label)
  id <- paste0("neural-", substr(brohn_hash(list(view$selector, view$metric, view$frequency_hz, view$indices, width)), 1, 20))
  target <- if (view$cell$type == "frequency_tagging_psd") Filter(function(f) f$name == "tag_bin_density" && brohn_number(f$actual_bin_hz), view$cell$features) else list()
  shiny::tags$svg(xmlns = "http://www.w3.org/2000/svg", viewBox = paste(0, 0, width, height), role = "img", `aria-labelledby` = paste(id, paste0(id, "-desc")),
    style = "display:block;width:100%;height:auto;max-width:100%;background:#11171c;border-radius:8px", focusable = "false",
    shiny::tags$title(id = id, title), shiny::tags$desc(id = paste0(id, "-desc"), paste("Exact saved samples", min(view$indices), "through", max(view$indices), "of", view$total_points,
      ". Missing values break the line. Numerical alternatives follow. Positive voltage is plotted upward; no condition or participant averaging occurs in this view.",
      "Report SHA-256", view$report_hash, "; source SHA-256", view$source_hash, "; retained trials", view$cell$support$retained_trials,
      "; voltage baseline", brohn_json(view$cell$parameters$baseline_s), "; recipe", view$cell$parameters$recipe)),
    lapply(ticks, function(y) shiny::tagList(line(left, py(y), right, py(y), stroke = "#415057"),
      shiny::tags$text(x = left-8, y = py(y)+4, `text-anchor` = "end", fill = "#edf2f2", `font-size` = 12, tick_label(y)))),
    lapply(c(xrange[[1L]], mean(xrange), xrange[[2L]]), function(x) shiny::tags$text(x = px(x), y = bottom+22, `text-anchor` = "middle", fill = "#edf2f2", `font-size` = 12, tick_label(x))),
    if (view$cell$type != "frequency_tagging_psd" && xrange[[1L]] <= 0 && xrange[[2L]] >= 0)
      line(px(0), top, px(0), bottom, stroke = "#d6c48a", `stroke-dasharray` = "5 4"),
    lapply(bands, function(i) shiny::tags$polygon(points = paste(paste(fmt(px(c(view$x[i], rev(view$x[i])))), fmt(py(c(view$y[i]-view$sem[i], rev(view$y[i]+view$sem[i])))), sep = ","), collapse = " "), fill = "#97d8c4", `fill-opacity` = ".24")),
    lapply(groups, function(i) if (length(i) == 1L) shiny::tags$circle(cx = fmt(px(view$x[i])), cy = fmt(py(view$y[i])), r = 3, fill = "#97d8c4") else
      shiny::tags$polyline(points = paste(paste(fmt(px(view$x[i])), fmt(py(view$y[i])), sep = ","), collapse = " "), fill = "none", stroke = "#97d8c4", `stroke-width` = 2)),
    lapply(target, function(f) if (f$actual_bin_hz >= xrange[[1L]] && f$actual_bin_hz <= xrange[[2L]])
      shiny::tagList(line(px(f$actual_bin_hz), top, px(f$actual_bin_hz), bottom, stroke = "#d6c48a", `stroke-dasharray` = "3 4"),
        shiny::tags$title(paste("Saved target", f$target_hz, "Hz; observed bin", f$actual_bin_hz, "Hz")))),
    shiny::tags$text(x = (left+right)/2, y = height-22, `text-anchor` = "middle", fill = "#edf2f2", `font-size` = 12, view$axis_unit),
    shiny::tags$text(x = left, y = 16, fill = "#edf2f2", `font-size` = 12, view$unit))
}

.brohn_np_view_ui <- function(model, view) {
  r <- view$cell$support; p <- view$cell$parameters
  shiny::div(class = "brohn-neural-plots", style = "min-width:0;max-width:100%;overflow-wrap:anywhere",
    shiny::tags$style(htmltools::HTML(".brohn-neural-plots .brohn-signal-compact{display:none}.brohn-neural-plots .brohn-signal-wide{display:block}@media(max-width:600px){.brohn-neural-plots .brohn-signal-wide{display:none}.brohn-neural-plots .brohn-signal-compact{display:block}}")),
    shiny::h3(view$label), shiny::p(view$cell$label),
    shiny::p(paste(r$retained_trials, "retained of", r$requested_trials, "requested trials;", r$excluded_trials, "excluded; minimum", r$minimum_trials, ". Origin:", model$origin, ".")),
    shiny::p(paste("Units:", view$unit, if (!is.null(view$frequency_hz)) paste("; recorded frequency", view$frequency_hz, "Hz"))),
    if (!any(is.finite(view$y))) shiny::p("This saved window is unavailable. Missing values remain missing; no zero-valued response is drawn.") else
      shiny::div(style = "min-width:0;max-width:100%", shiny::div(class = "brohn-signal-wide", brohn_neural_plot_svg(view)), shiny::div(class = "brohn-signal-compact", brohn_neural_plot_svg(view, 320))),
    shiny::p(paste("Showing exact saved samples", min(view$indices), "to", max(view$indices), "of", view$total_points, ";", view$window_missing_points,
      "unavailable in this window and", view$missing_points, "in this complete trace. No samples are averaged or decimated by the view.")),
    shiny::p(if (view$cell$type == "erp") "The shaded band is mean plus/minus the saved pointwise trial SEM within this recording and condition. It is not a participant confidence interval. Single-trial SEM stays unavailable. Positive voltage is upward." else
      if (view$cell$type == "morlet") "Choose an actual recorded frequency to inspect its time course. Frequencies are separate measured analysis rows, with no interpolated heatmap. ITC uses the original total-signal phases, including when induced power was chosen." else
      "Dashed gold lines mark saved target bins. Density is mean trial power per Hz, not integrated power or oscillation amplitude. SNR and neighboring noise values below are the saved worker outputs."),
    shiny::p(paste("Voltage baseline:", if (is.null(p$baseline_s)) "no subtraction" else paste(brohn_json(p$baseline_s), "s, inclusive"),
      "; reference:", p$reference$mode, "; filtering:", p$filter$mode, ".")),
    if (view$cell$type == "morlet") shiny::p(paste("Power:", p$power, "; power baseline:", brohn_json(p$power_baseline),
      "; excluded wavelet samples at each edge:", r$derived_settings$edge_exclusion_samples_each_side, ". Only retained support is plotted.")),
    if (view$cell$type == "frequency_tagging_psd") shiny::p(paste("Spectral window:", brohn_json(p$spectral_window_s), "s, end excluded; taper:", p$window,
      "; bin width:", r$derived_settings$frequency_bin_width_hz, "Hz. Baseline and timing settings remain those of the frozen recipe.")),
    shiny::tags$details(shiny::tags$summary("Exact plotted values and saved features"),
      shiny::p(paste("The numerical preview shows the first", min(50L, length(view$rows)), "points in this window. Download the complete series for every saved point/frequency; nulls are empty CSV fields.")),
      brohn_table(view$rows, maximum = 50L, label = paste("Neural waveform numerical alternative; coordinate in", view$axis_unit, "and value in", view$unit)),
      brohn_table(view$cell$features, maximum = 100L, label = "Saved channel and condition features; no recalculation")),
    shiny::tags$details(shiny::tags$summary("Trial support, measured event alignment and source versions"),
      brohn_table(list(r), label = "Complete saved recording and condition support"), shiny::p(p$event_source), shiny::p(p$settings_source),
      shiny::tags$pre(brohn_json(p, TRUE)), shiny::p(paste("Report SHA-256:", model$report_hash)), shiny::p(paste("Source SHA-256:", model$source_hash)),
      shiny::p("This plot does not establish device synchronization, a psychological component, attention, or participant-level significance.")))
}

brohn_neural_report_plots <- function(report, selector = NULL, metric = NULL, frequency_hz = NULL, start_index = 1L, maximum_points = 2000L) {
  if (!.brohn_np_supported(report)) return(NULL)
  tryCatch({model <- brohn_neural_plot_model(report)
    brohn_card(title = "Neural responses in context",
      if (length(model$cells)) shiny::tagList(.brohn_np_view_ui(model, brohn_neural_plot_selection(model, selector, metric, frequency_hz, start_index, maximum_points)),
        shiny::p(paste("This view contains one of", length(model$cells), "separate recording/condition/channel cells. The complete report JSON retains all cells and arrays."))) else
        shiny::p("No supported waveform was retained. The trial support below explains why; missing conditions are not plotted as zero."),
      shiny::tags$details(shiny::tags$summary("All saved recording and condition outcomes"), brohn_table(model$recordings, maximum = 100L, label = "Neural trial eligibility including unavailable conditions")))
  }, error = function(e) brohn_card(title = "Neural plot needs attention", shiny::p(conditionMessage(e)), shiny::p("The saved numerical report remains available. No repair or replacement calculation is performed by this view.")))
}

brohn_neural_explorer_ui <- function(report) {
  if (!.brohn_np_supported(report)) return(NULL)
  tryCatch({model <- brohn_neural_plot_model(report)
    if (!length(model$cells)) return(brohn_neural_report_plots(report))
    shiny::tagList(brohn_card(title = "Explore neural responses", shiny::p("Inspect one recorded channel and condition at a time. Every source person, session and segment remains separate."),
      shiny::selectInput("neural_plot_cell", "Recording, condition and channel", stats::setNames(vapply(model$cells, `[[`, character(1), "selector"), vapply(model$cells, `[[`, character(1), "label"))),
      shiny::uiOutput("neural_plot_controls")), shiny::uiOutput("neural_plot_view"))
  }, error = function(e) brohn_card(title = "Neural plot needs attention", shiny::p(conditionMessage(e))))
}

brohn_neural_plot_csv <- function(model, selector, path) {
  view <- brohn_neural_plot_selection(model, selector); c <- view$cell; n <- length(c$axis)
  base <- function() data.frame(sample_index = seq_len(n), coordinate = c$axis, stringsAsFactors = FALSE)
  if (c$type == "morlet") rows <- do.call(rbind, lapply(seq_along(c$frequencies), function(i) cbind(base(), frequency_hz = c$frequencies[[i]],
    power_uv2 = c$values$power_uv2[[i]], transformed_power = c$values$transformed_power[[i]], itc = c$values$itc[[i]]))) else
      rows <- if (c$type == "erp") cbind(base(), mean_uv = c$values$mean_uv, sem_uv = c$values$sem_uv) else cbind(base(), density_uv2_hz = c$values$density_uv2_hz)
  # Metadata is separate from measurement columns and never changes scientific
  # numbers. Spreadsheet formula prefixes apply to source text only.
  safe <- function(x) if (grepl("^[=+@\\t\\r]|^-[^0-9.]", x)) paste0("'", x) else x
  for (field in c("recording_id", "condition_id", "channel", "origin")) rows[[field]] <- safe(c$identity[[field]])
  rows$group_json <- safe(brohn_json(c$identity$group)); rows$report_sha256 <- model$report_hash; rows$source_sha256 <- model$source_hash
  rows$coordinate_unit <- view$axis_unit
  if (c$type == "morlet") rows$transformed_unit <- c$source$transformed_unit
  utils::write.csv(rows, path, row.names = FALSE, na = "", fileEncoding = "UTF-8")
  invisible(path)
}

brohn_install_neural_plots <- function(input, output, session, store, state, attempt, message, prepare_download) {
  model <- shiny::reactive({shiny::req(identical(state$page, "report"), state$report_id)
    r <- brohn_get_entity(store, "report", state$report_id); shiny::req(r, .brohn_np_supported(r$body)); brohn_neural_plot_model(r$body)})
  cell <- shiny::reactive({m <- model(); shiny::req(input$neural_plot_cell)
    brohn_neural_plot_selection(m, input$neural_plot_cell)$cell})
  output$neural_plot_controls <- shiny::renderUI({c <- cell()
    shiny::tagList(shiny::tags$input(id = "neural_plot_form", type = "text", class = "shiny-input-text", value = c$selector, style = "display:none", `aria-hidden` = "true", tabindex = "-1"),
      if (c$type == "morlet") shiny::div(class = "brohn-form-grid",
        shiny::selectInput("neural_plot_metric", "Retained time-frequency measure", c("Power after the declared baseline transform" = "transformed_power", "Power before the power-baseline transform" = "power_uv2", "Inter-trial phase consistency" = "itc")),
        shiny::selectInput("neural_plot_frequency", "Recorded analysis frequency (Hz)", stats::setNames(seq_along(c$frequencies), format(c$frequencies, digits = 15, trim = TRUE)))),
      shiny::numericInput("neural_plot_start", "First saved sample index (up to 2,000 consecutive points per view)", 1, min = 1, max = length(c$axis), step = 1),
      shiny::div(class = "brohn-toolbar", shiny::downloadButton("neural_plot_csv", "Download complete channel series", icon = NULL),
        shiny::downloadButton("neural_plot_json", "Download series + provenance", icon = NULL), shiny::downloadButton("neural_plot_svg", "Download displayed chart", icon = NULL)))
  })
  selected <- shiny::reactive({m <- model(); c <- cell()
    shiny::req(identical(input$neural_plot_form, c$selector), input$neural_plot_start)
    fi <- if (c$type == "morlet") {index <- suppressWarnings(as.numeric(input$neural_plot_frequency));
      brohn_require(brohn_number(index, 1, length(c$frequencies), TRUE), "Choose a recorded frequency."); c$frequencies[[index]]} else NULL
    brohn_neural_plot_selection(m, c$selector, if (c$type == "morlet") input$neural_plot_metric else NULL, fi, input$neural_plot_start)
  })
  output$neural_plot_view <- shiny::renderUI({tryCatch({v <- selected(); brohn_card(title = "Saved neural trace", .brohn_np_view_ui(model(), v))},
    error = function(e) {if (inherits(e, "shiny.silent.error")) stop(e); shiny::div(class = "brohn-alert", role = "status", conditionMessage(e))})})
  output$neural_plot_csv <- shiny::downloadHandler(filename = function() paste0(model()$report_id, "-channel.csv"), contentType = "text/csv",
    content = function(file) prepare_download(function() {v <- selected(); brohn_neural_plot_csv(model(), v$selector, file)}))
  output$neural_plot_json <- shiny::downloadHandler(filename = function() paste0(model()$report_id, "-channel.json"), contentType = "application/json",
    content = function(file) prepare_download(function() {v <- selected(); m <- model(); brohn_write_json_file(list(schema = "brohn-neural-channel-export/1.0",
      report_id = m$report_id, report_hash = m$report_hash, source_hash = m$source_hash, series = v$cell$source, features = v$cell$features,
      support = v$cell$support, parameters = v$cell$parameters, provenance = m$provenance, processing = m$processing,
      displayed_window = list(first_index = min(v$indices), last_index = max(v$indices), metric = v$metric, frequency_hz = v$frequency_hz)), file)}))
  output$neural_plot_svg <- shiny::downloadHandler(filename = function() paste0(model()$report_id, "-neural.svg"), contentType = "image/svg+xml",
    content = function(file) prepare_download(function() {v <- selected(); svg <- brohn_neural_plot_svg(v); brohn_require(!is.null(svg), "This window has no supported chart to download.")
      writeLines(enc2utf8(as.character(svg)), file, useBytes = TRUE)}))
  invisible(list(model = model, selected = selected))
}
