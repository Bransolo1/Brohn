# R owns the declared EEG recipe boundary; numerical epochs run outside Shiny.
brohn_neural_recipe_choices <- function() c("Recording spectrum (Welch)" = "eeg-welch-channel/1.0",
  "Event-related response (ERP)" = "eeg-erp-epochs/1.0", "Time-frequency response (Morlet)" = "eeg-morlet-epochs/1.1",
  "Frequency-tagged response (SSVEP)" = "eeg-frequency-tagging/1.0")
brohn_neural_morlet_recipes <- function() c("eeg-morlet-epochs/1.0", "eeg-morlet-epochs/1.1")
brohn_neural_registered_recipes <- function() unique(c(unname(brohn_neural_recipe_choices()), brohn_neural_morlet_recipes()))
brohn_neural_is_epoch <- function(m) !is.null(m$parameters$recipe) && m$parameters$recipe %in% setdiff(brohn_neural_registered_recipes(), "eeg-welch-channel/1.0")
.brohn_neural_numbers <- function(x, label, minimum = -Inf, maximum = Inf, count = NULL, integer = FALSE) {
  brohn_require(brohn_array(x) && length(x) > 0 && (is.null(count) || length(x) == count) &&
    all(vapply(x, brohn_number, logical(1), min = minimum, max = maximum, integer = integer)), paste(label, "needs an array of finite numbers in its allowed range."))
  unlist(x, use.names = FALSE)
}
.brohn_neural_window <- function(x, label, minimum, maximum) {
  value <- .brohn_neural_numbers(x, label, minimum, maximum, 2L)
  brohn_require(value[1] < value[2], paste(label, "needs an earlier start and a later end.")); value
}
brohn_validate_neural_mapping <- function(m, columns = NULL, source_format = NULL) {
  brohn_require(is.list(m), "Confirm the EEG mapping first.")
  p <- m$parameters
  recipe <- brohn_default(p$recipe, "eeg-welch-channel/1.0")
  brohn_require(recipe %in% brohn_neural_registered_recipes(), "Select an available EEG analysis recipe.")
  if (recipe == "eeg-welch-channel/1.0") return(invisible(m))
  brohn_require(is.null(source_format) || source_format %in% c("csv", "tsv", "edf", "bdf", "fif"), "Event-related EEG recipes accept CSV, TSV, EDF, BDF or FIF.")
  brohn_require(brohn_number(m$sampling_rate, 1, 100000), "Declare the EEG sample rate in Hz; native headers must agree.")
  fs <- m$sampling_rate
  brohn_require(brohn_array(m$value_columns) && length(m$value_columns) >= 1 && length(m$value_columns) <= 64 &&
    all(vapply(m$value_columns, brohn_text, logical(1), max = 200)) && !anyDuplicated(unlist(m$value_columns)), "Select 1 to 64 distinct EEG signal channels.")
  channels <- unlist(m$value_columns, use.names = FALSE)
  if (!is.null(columns) && source_format %in% c("csv", "tsv")) brohn_require(all(channels %in% columns), "A selected EEG signal channel is absent.")
  if (is.null(source_format) || source_format %in% c("csv", "tsv")) {
    brohn_require(m$unit %in% c("V", "mV", "uV", "\u00b5V", "\u03bcV", if (is.null(source_format)) "native"), "Confirm the EEG voltage unit.")
  } else brohn_require(m$unit %in% c("native", "V"), "Native EEG uses file-header scaling into volts.")
  if (!is.null(source_format) && source_format %in% c("csv", "tsv")) {
    brohn_require(brohn_text(m$time_column, 500) && m$time_unit %in% c("s", "ms", "us", "ns", "sample"), "Map the EEG sample clock and its unit.")
    brohn_require(identical(brohn_text(m$participant_column, 500), brohn_text(m$session_column, 500)), "Map participant and session identity together, or retain recording-only summaries.")
  } else if (!is.null(source_format)) brohn_require(identical(brohn_text(m$participant_id, 500), brohn_text(m$session_id, 500)), "Supply native participant and session identities together.")
  common <- c("recipe", "event_codes", "event_source", "epoch_s", "baseline_s", "reference", "filter", "rejection", "minimum_trials", "overlap_policy", "settings_source")
  specific <- switch(recipe, `eeg-erp-epochs/1.0` = c("amplitude_window_s", "peak_polarity"),
    `eeg-morlet-epochs/1.0` = , `eeg-morlet-epochs/1.1` = c("frequencies_hz", "n_cycles", "power", "power_baseline", "summary_window_s"),
    `eeg-frequency-tagging/1.0` = c("spectral_window_s", "tag_frequencies_hz", "harmonics", "window", "noise_neighbor_bins", "noise_skip_bins", "max_bin_offset_hz"))
  brohn_fields(p, c(common, specific), "event_tolerance_s", "EEG recipe")
  brohn_require(brohn_text(p$settings_source, 4000) && brohn_text(p$event_source, 4000), "Describe the protocol settings and measured event timing source.")
  brohn_require(is.list(p$event_codes) && length(p$event_codes) >= 1 && length(p$event_codes) <= 100 && !is.null(names(p$event_codes)) &&
    all(vapply(as.list(names(p$event_codes)), brohn_text, logical(1), max = 128)) && !anyDuplicated(names(p$event_codes)) &&
    all(vapply(p$event_codes, brohn_text, logical(1), max = 128)), "Map each onset code to one explicit condition ID.")
  epoch <- .brohn_neural_window(p$epoch_s, "Epoch window", -60, 120)
  brohn_require(epoch[1] <= 0 && epoch[2] >= 0 && all(abs(epoch*fs-round(epoch*fs)) < 1e-7), "Epochs must include onset and their endpoints must lie on the sample grid.")
  if (!is.null(p$baseline_s)) {
    baseline <- .brohn_neural_window(p$baseline_s, "Voltage baseline", epoch[1], epoch[2])
    brohn_require(baseline[2] <= 0, "The voltage baseline must end at or before event onset.")
  }
  brohn_require(brohn_number(p$minimum_trials, 1, 10000, integer = TRUE), "Declare the minimum retained trials per condition.")
  brohn_require(p$overlap_policy %in% c("allow", "reject"), "Choose how overlapping epochs are handled.")
  if (!is.null(p$event_tolerance_s)) brohn_require(brohn_number(p$event_tolerance_s, 0, .5/fs), "Event alignment tolerance cannot exceed half a sample interval.")
  brohn_fields(p$reference, c("mode", "source"), "channels", "EEG reference")
  brohn_require(p$reference$mode %in% c("acquisition", "average", "channels") && brohn_text(p$reference$source, 4000), "Declare the reference mode and its source.")
  if (p$reference$mode == "average") brohn_require(length(channels) >= 2, "Average reference requires at least two selected channels.")
  if (p$reference$mode == "channels") brohn_require(brohn_array(p$reference$channels) && length(p$reference$channels) > 0 &&
    all(vapply(p$reference$channels, brohn_text, logical(1), max = 200)) && all(unlist(p$reference$channels) %in% channels) &&
    !anyDuplicated(unlist(p$reference$channels)), "Named reference electrodes must be distinct selected channels.") else
      brohn_require(!"channels" %in% names(p$reference), "Reference channel names apply only to named-channel referencing.")
  brohn_require(is.list(p$filter) && p$filter$mode %in% c("none", "butterworth_bandpass"), "Select no additional filter or the explicit Butterworth bandpass.")
  if (p$filter$mode == "none") brohn_fields(p$filter, "mode", label = "Disabled filter") else {
    f <- p$filter; brohn_fields(f, c("mode", "low_hz", "high_hz", "order", "edge_exclusion_s"), label = "Bandpass filter")
    brohn_require(brohn_number(f$low_hz, .01, fs/2) && brohn_number(f$high_hz, f$low_hz+.001, fs/2-.001) &&
      brohn_number(f$order, 1, 8, TRUE) && brohn_number(f$edge_exclusion_s, 3/f$low_hz, 600), "Declare compatible filter cutoffs, order and at least three high-pass cycles of edge exclusion per side.")
  }
  rejection <- p$rejection
  brohn_fields(rejection, c("window_s", "peak_to_peak_uv", "flat_uv"), label = "Artifact rejection")
  .brohn_neural_window(rejection$window_s, "Artifact rejection window", epoch[1], epoch[2])
  for (field in c("peak_to_peak_uv", "flat_uv")) if (!is.null(rejection[[field]])) brohn_require(brohn_number(rejection[[field]], .000001, 1e9), "Artifact thresholds must be positive microvolt values or explicitly disabled.")
  brohn_require(is.null(rejection$peak_to_peak_uv) || is.null(rejection$flat_uv) || rejection$flat_uv < rejection$peak_to_peak_uv, "Flat threshold must be below peak-to-peak rejection.")
  column_event <- brohn_text(m$event_column, 500)
  brohn_require(xor(column_event, !is.null(m$events)), "Select exactly one event onset column or explicit events array.")
  if (column_event) {
    brohn_require(is.null(source_format) || source_format %in% c("csv", "tsv"), "Native EEG events require an explicit event array.")
    brohn_require(is.null(columns) || m$event_column %in% columns, "The selected onset-code column is absent.")
    reserved <- unlist(m[c("time_column", "value_columns", "participant_column", "session_column", "condition_column", "exposure_column", "segment_column")], use.names = FALSE)
    brohn_require(!m$event_column %in% reserved, "Event onset codes require a separate source column.")
  } else {
    brohn_require(brohn_array(m$events) && length(m$events) >= 1 && length(m$events) <= 10000, "Supply 1 to 10,000 explicit event onsets.")
    previous <- list(); seen <- list()
    for (event in m$events) {
      brohn_fields(event, c("time_s", "code"), c("recording_id", "id"), "Event onset")
      brohn_require(brohn_number(event$time_s, 0, 1e12) && brohn_text(event$code, 128), "Event onsets need relative seconds and a text code.")
      for (field in c("recording_id", "id")) if (!is.null(event[[field]])) brohn_require(brohn_text(event[[field]], 128), "Event identities must be nonempty text.")
      key <- brohn_default(event$recording_id, "recording-1")
      brohn_require(is.null(previous[[key]]) || event$time_s > previous[[key]], "Event onsets must strictly increase within each recording.")
      if (!is.null(event$id)) brohn_require(!event$id %in% seen[[key]], "Event IDs must be unique within a recording.")
      previous[[key]] <- event$time_s; seen[[key]] <- c(seen[[key]], event$id)
    }
  }
  if (recipe == "eeg-erp-epochs/1.0") {
    .brohn_neural_window(p$amplitude_window_s, "ERP amplitude window", epoch[1], epoch[2])
    brohn_require(p$peak_polarity %in% c("positive", "negative", "absolute", "none"), "Choose ERP peak polarity or no peak extraction.")
  } else if (recipe %in% brohn_neural_morlet_recipes()) {
    f <- .brohn_neural_numbers(p$frequencies_hz, "Morlet frequencies", .1, fs/2-.001)
    brohn_require(length(f) <= 40 && all(diff(f) > 0), "Provide up to 40 increasing Morlet frequencies.")
    .brohn_neural_numbers(p$n_cycles, "Morlet cycle counts", 1, 30, length(f))
    brohn_require(p$power %in% c("total", "induced"), "Choose total or induced power.")
    .brohn_neural_window(p$summary_window_s, "Morlet summary window", epoch[1], epoch[2])
    b <- p$power_baseline
    brohn_require(is.list(b) && b$mode %in% c("none", "subtract", "ratio", "percent", "db"), "Select a power-baseline transform.")
    if (b$mode == "none") brohn_fields(b, "mode", label = "Disabled power baseline") else {
      brohn_fields(b, c("mode", "window_s", "minimum_power_uv2", if (recipe == "eeg-morlet-epochs/1.1") "adequacy"), label = "Power baseline")
      window <- .brohn_neural_window(b$window_s, "Power baseline", epoch[1], epoch[2])
      brohn_require(window[2] <= 0 && brohn_number(b$minimum_power_uv2, 0, 1e12), "Power baseline needs pre-onset support and an explicit nonnegative denominator floor.")
      if (recipe == "eeg-morlet-epochs/1.1") {
        brohn_fields(b$adequacy, c("policy", "minimum_cycles", "rationale"), label = "Power baseline duration review")
        brohn_require(identical(b$adequacy$policy, "complete-pre-event-wavelet-support/1.0") &&
          brohn_number(b$adequacy$minimum_cycles, .000001, 1e6) && brohn_text(b$adequacy$rationale, 4000),
          "Declare a positive minimum baseline duration in cycles at the lowest frequency and explain its study-specific rationale. This declaration does not establish scientific validity.")
      }
    }
  } else {
    .brohn_neural_window(p$spectral_window_s, "Frequency-tagging window", epoch[1], epoch[2])
    f <- .brohn_neural_numbers(p$tag_frequencies_hz, "Tag frequencies", .1, fs/2-.001)
    h <- .brohn_neural_numbers(p$harmonics, "Tag harmonics", 1, 10, integer = TRUE)
    brohn_require(length(f) <= 20 && !anyDuplicated(f) && !anyDuplicated(h) && max(f)*max(h) < fs/2, "Tag frequencies and harmonics must be unique and below Nyquist.")
    brohn_require(p$window %in% c("hann", "boxcar") && brohn_number(p$noise_neighbor_bins, 1, 100, TRUE) &&
      brohn_number(p$noise_skip_bins, 0, 100, TRUE) && brohn_number(p$max_bin_offset_hz, 0, fs/2), "Confirm taper, noise neighbors, skipped bins and target-bin tolerance.")
  }
  invisible(m)
}
brohn_neural_worker_request <- function(m, source_format = NULL, columns = NULL) {
  brohn_validate_neural_mapping(m, columns, source_format)
  epoch <- brohn_neural_is_epoch(m)
  list(operation = if (epoch) "neural" else "physiology",
    script = if (epoch) "scripts/workers/neural.py" else "scripts/workers/physiology.py",
    parameters = brohn_default(m$parameters, list()))
}
.brohn_neural_csv_numbers <- function(value, label, integer = FALSE) {
  brohn_require(brohn_text(value, 8000), paste("Supply", label, "as comma-separated numbers."))
  fields <- trimws(strsplit(value, ",", fixed = TRUE)[[1]])
  numbers <- suppressWarnings(as.numeric(fields))
  brohn_require(length(fields) && all(nzchar(fields)) && all(is.finite(numbers)) &&
    (!integer || all(numbers == floor(numbers))), paste(label, "contains an invalid number."))
  as.list(if (integer) as.integer(numbers) else numbers)
}
brohn_neural_code_map <- function(value) {
  brohn_require(brohn_text(value, 32000), "Map source onset codes to condition IDs.")
  if (startsWith(trimws(value), "{")) return(brohn_parse(value, 32000))
  rows <- trimws(strsplit(value, "\n", fixed = TRUE)[[1]]); rows <- rows[nzchar(rows)]
  pairs <- strsplit(rows, "=", fixed = TRUE)
  brohn_require(length(pairs) && all(lengths(pairs) == 2L), "Use one source code = condition ID per line.")
  keys <- vapply(pairs, function(p) trimws(p[[1]]), character(1)); values <- lapply(pairs, function(p) trimws(p[[2]]))
  brohn_require(!anyDuplicated(keys) && all(nzchar(keys)) && all(nzchar(unlist(values))), "Each source code needs one nonempty condition ID, with no duplicate codes.")
  stats::setNames(values, keys)
}
brohn_neural_event_list <- function(value) {
  brohn_require(brohn_text(value, 1024*1024), "Paste a measured event list with time_s and code columns.")
  if (startsWith(trimws(value), "[")) return(brohn_parse(value, 1024*1024))
  table <- tryCatch(utils::read.csv(text = value, colClasses = "character", check.names = FALSE,
    comment.char = "", na.strings = character(), nrows = 10001), error = function(e) brohn_stop("The event list is not valid CSV."))
  brohn_require(nrow(table) >= 1 && nrow(table) <= 10000 && !anyDuplicated(names(table)) &&
    all(c("time_s", "code") %in% names(table)) && all(names(table) %in% c("time_s", "code", "recording_id", "id")), "Event lists need time_s and code, with optional recording_id and id columns.")
  lapply(seq_len(nrow(table)), function(i) {
    event <- as.list(table[i, , drop = FALSE]); event$time_s <- suppressWarnings(as.numeric(event$time_s))
    brohn_require(brohn_number(event$time_s, 0, 1e12), "Event times must be finite, nonnegative relative seconds.")
    for (field in c("recording_id", "id")) if (!is.null(event[[field]]) && !nzchar(event[[field]])) event[[field]] <- NULL
    event
  })
}
brohn_neural_input <- function(input, metadata, source_format = "csv") {
  m <- metadata; get <- function(name) input[[paste0("map_neural_", name)]]
  recipe <- get("recipe")
  brohn_require(recipe %in% unname(brohn_neural_recipe_choices()), "Choose an EEG analysis recipe.")
  if (recipe == "eeg-welch-channel/1.0") {
    old <- m$parameters
    m$parameters <- if (is.null(old$recipe) || identical(old$recipe, recipe)) brohn_default(old, list()) else list()
    m$parameters$recipe <- recipe; m$event_column <- NULL; m$events <- NULL
    return(m)
  }
  pair <- function(start, end) as.list(c(get(start), get(end)))
  optional_number <- function(enabled, name) if (isTRUE(get(enabled))) get(name) else NULL
  p <- list(recipe = recipe, event_codes = brohn_neural_code_map(get("event_codes")), event_source = get("event_source"),
    epoch_s = pair("epoch_start", "epoch_end"), baseline_s = if (identical(get("voltage_baseline"), "subtract")) pair("baseline_start", "baseline_end") else NULL,
    reference = list(mode = get("reference"), source = get("reference_source")), filter = list(mode = get("filter")),
    rejection = list(window_s = pair("reject_start", "reject_end"), peak_to_peak_uv = optional_number("reject_peak", "peak_uv"), flat_uv = optional_number("reject_flat", "flat_uv")),
    minimum_trials = get("minimum_trials"), overlap_policy = get("overlap"), settings_source = get("settings_source"))
  if (identical(p$reference$mode, "channels")) p$reference$channels <- as.list(trimws(strsplit(brohn_default(get("reference_channels"), ""), ",", fixed = TRUE)[[1]]))
  if (identical(p$filter$mode, "butterworth_bandpass")) p$filter <- list(mode = p$filter$mode, low_hz = get("filter_low"), high_hz = get("filter_high"), order = get("filter_order"), edge_exclusion_s = get("filter_edge"))
  if (identical(recipe, "eeg-erp-epochs/1.0")) {
    p$amplitude_window_s <- pair("amplitude_start", "amplitude_end"); p$peak_polarity <- get("polarity")
  } else if (recipe %in% brohn_neural_morlet_recipes()) {
    p$frequencies_hz <- .brohn_neural_csv_numbers(get("frequencies"), "Morlet frequencies")
    p$n_cycles <- .brohn_neural_csv_numbers(get("cycles"), "Morlet cycle counts")
    p$power <- get("power"); p$summary_window_s <- pair("summary_start", "summary_end")
    p$power_baseline <- list(mode = get("power_baseline"))
    if (!identical(p$power_baseline$mode, "none")) p$power_baseline <- list(mode = p$power_baseline$mode,
      window_s = pair("power_baseline_start", "power_baseline_end"), minimum_power_uv2 = get("power_floor"),
      adequacy = list(policy = "complete-pre-event-wavelet-support/1.0", minimum_cycles = get("baseline_minimum_cycles"), rationale = get("baseline_rationale")))
  } else {
    p$spectral_window_s <- pair("spectral_start", "spectral_end")
    p$tag_frequencies_hz <- .brohn_neural_csv_numbers(get("tags"), "Tag frequencies")
    p$harmonics <- .brohn_neural_csv_numbers(get("harmonics"), "Harmonics", integer = TRUE)
    p$window <- get("taper"); p$noise_neighbor_bins <- get("neighbors"); p$noise_skip_bins <- get("skip_bins"); p$max_bin_offset_hz <- get("bin_tolerance")
  }
  m$parameters <- p
  if (identical(get("event_mode"), "column")) { m$event_column <- get("event_column"); m$events <- NULL } else {
    brohn_require(identical(get("event_mode"), "array"), "Choose an event onset column or measured event list.")
    m$events <- brohn_neural_event_list(get("events")); m$event_column <- NULL
  }
  if (!source_format %in% c("csv", "tsv")) {
    m$sampling_rate <- get("native_rate"); m$participant_id <- get("participant"); m$session_id <- get("session")
    if (identical(m$participant_id, "")) m$participant_id <- NULL
    if (identical(m$session_id, "")) m$session_id <- NULL
  }
  brohn_validate_neural_mapping(m, source_format = source_format)
  m
}
