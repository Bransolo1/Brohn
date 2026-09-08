# Continuous-context EDA contract. Numerical processing runs outside Shiny.
brohn_eda_events_recipe_choices <- function() c("Whole-recording tonic and SCR summaries" = "eda-neurokit-highpass/1.0",
  "Stimulus response with continuous filtering" = "eda-event-highpass/1.0",
  "Stimulus response with cvxEDA decomposition" = "eda-event-cvxeda-defaults/1.0")
brohn_eda_events_is_event <- function(m) !is.null(m$parameters$recipe) && m$parameters$recipe %in% unname(brohn_eda_events_recipe_choices())[-1L]
.brohn_eda_events_window <- function(x, label, low = -120, high = 300) {
  brohn_require(brohn_array(x) && length(x) == 2 && all(vapply(x, brohn_number, logical(1), min = low, max = high)) &&
    x[[1]] < x[[2]], paste(label, "needs two increasing finite endpoints in seconds."))
  unlist(x, use.names = FALSE)
}
brohn_validate_eda_events_mapping <- function(m, columns = NULL, source_format = NULL, design = NULL) {
  brohn_require(is.list(m), "Confirm the EDA source mapping.")
  p <- m$parameters; recipe <- brohn_default(p$recipe, "eda-neurokit-highpass/1.0")
  brohn_require(brohn_text(recipe, 128) && recipe %in% unname(brohn_eda_events_recipe_choices()), "Select an implemented EDA analysis recipe.")
  if (recipe == "eda-neurokit-highpass/1.0") return(invisible(m))
  brohn_require(is.null(source_format) || source_format %in% c("csv", "tsv"), "Event-related EDA accepts calibrated CSV or TSV samples.")
  brohn_require(brohn_number(m$sampling_rate, 8, 2000), "EDA event analysis needs a declared sample rate from 8 to 2,000 Hz.")
  fs <- m$sampling_rate
  brohn_require(brohn_text(m$unit, 32) && m$unit %in% c("uS", "\u00b5S", "\u03bcS", "S"), "Declare conductance in microsiemens (uS) or siemens (S); raw counts or resistance need calibration first.")
  brohn_require(brohn_text(m$time_column, 500) && brohn_text(m$time_unit, 16) && m$time_unit %in% c("s", "ms"), "Map the measured source clock in seconds or milliseconds.")
  brohn_require(brohn_text(m$participant_column, 500) && brohn_text(m$session_column, 500), "Map both person and session identity to keep continuous recordings separate.")
  brohn_require(brohn_array(m$value_columns) && length(m$value_columns) >= 1 && length(m$value_columns) <= 64 &&
    all(vapply(m$value_columns, brohn_text, logical(1), max = 500)) && !anyDuplicated(unlist(m$value_columns)), "Select 1 to 64 distinct calibrated conductance channels.")
  if (!is.null(m$timestamp_tolerance_s)) brohn_require(brohn_number(m$timestamp_tolerance_s, 0, .5/fs), "Timestamp tolerance cannot exceed half a sample interval.")
  fields <- c("time_column", "participant_column", "session_column", "recording_column", "segment_column", "event_column", "exposure_column", "condition_column", "stimulus_column", "valid_column")
  for (field in fields) if (!is.null(m[[field]])) brohn_require(brohn_text(m[[field]], 500), paste(field, "must name a source column or be omitted."))
  selected <- c(unlist(m[fields], use.names = FALSE), unlist(m$value_columns, use.names = FALSE))
  brohn_require(!anyDuplicated(selected), "Time, signals, events, validity and identities need distinct source columns.")
  if (!is.null(columns)) brohn_require(all(selected %in% columns), "A selected source, event, validity or identity column is absent.")
  required <- c("recipe", "event_codes", "nuisance_codes", "event_source", "settings_source", "baseline_s", "response_s",
    "onset_latency_s", "recovery_end_s", "nuisance_effect_s", "overlap_policy", "response_selection", "minimum_scr_amplitude_us",
    "relative_prominence", "edge_exclusion_s", "minimum_segment_s")
  brohn_fields(p, required, "event_tolerance_s", "EDA event recipe")
  brohn_require(brohn_text(p$event_source, 4000) && brohn_text(p$settings_source, 4000), "Describe measured event timing and the protocol supporting these windows and thresholds.")
  codes <- p$event_codes
  brohn_require(is.list(codes) && length(codes) >= 1 && length(codes) <= 100 && !is.null(names(codes)) && !anyDuplicated(names(codes)) &&
    all(vapply(as.list(names(codes)), brohn_text, logical(1), max = 128)) && all(vapply(codes, brohn_text, logical(1), max = 128)), "Map each source onset code to an explicit condition ID.")
  brohn_require(brohn_array(p$nuisance_codes) && length(p$nuisance_codes) <= 100 && all(vapply(p$nuisance_codes, brohn_text, logical(1), max = 128)) &&
    !anyDuplicated(unlist(p$nuisance_codes)) && !any(unlist(p$nuisance_codes) %in% names(codes)), "Nuisance codes must be unique and distinct from target event codes.")
  baseline <- .brohn_eda_events_window(p$baseline_s, "Baseline")
  response <- .brohn_eda_events_window(p$response_s, "Response window")
  latency <- .brohn_eda_events_window(p$onset_latency_s, "SCR onset latency")
  .brohn_eda_events_window(p$nuisance_effect_s, "Nuisance effect window")
  brohn_require(baseline[2] <= 0 && response[1] >= 0 && latency[1] >= response[1] && latency[2] <= response[2], "Baseline must precede onset, and onset latency must lie inside the post-onset response window.")
  brohn_require(all(abs(c(baseline, response)*fs-round(c(baseline, response)*fs)) < 1e-7), "Baseline and response endpoints must lie on the declared sample grid; no interpolation is performed.")
  brohn_require(brohn_number(p$recovery_end_s, response[2], 300), "Recovery may extend from the response end up to 300 seconds after onset.")
  brohn_require(brohn_text(p$overlap_policy, 32) && p$overlap_policy %in% c("exclude", "descriptive_only"), "Choose exclusion or descriptive-only summaries for overlapping events.")
  brohn_require(brohn_text(p$response_selection, 32) && p$response_selection %in% c("first_onset", "largest_amplitude"), "Choose the first qualifying onset or largest qualifying response.")
  brohn_require(brohn_number(p$minimum_scr_amplitude_us, .000001, 100) && brohn_number(p$relative_prominence, .001, 1), "Declare the absolute SCR amplitude threshold and separate relative prominence threshold.")
  brohn_require(brohn_number(p$edge_exclusion_s, 10, 300), "Keep at least ten seconds of edge exclusion at each continuous segment boundary.")
  brohn_require(brohn_number(p$minimum_segment_s, max(40, 2*p$edge_exclusion_s+20), 3600), "Continuous context needs at least 40 seconds and 20 retained seconds after both edge exclusions.")
  if (!is.null(p$event_tolerance_s)) brohn_require(brohn_number(p$event_tolerance_s, 0, .5/fs), "Event alignment tolerance cannot exceed half a sample interval.")
  if (!is.null(design)) brohn_require(all(unlist(codes) %in% brohn_ids(design$conditions)), "A target event maps to a condition absent from the frozen study design.")
  column_event <- brohn_text(m$event_column, 500)
  brohn_require(xor(column_event, !is.null(m$events)), "Choose exactly one onset column or explicit measured event list.")
  if (column_event) brohn_require(brohn_text(m$exposure_column, 500), "Map an exposure ID column with a unique trial identity at each target onset.") else {
    brohn_require(brohn_array(m$events) && length(m$events) >= 1 && length(m$events) <= 2000 &&
      length(m$events)*length(m$value_columns) <= 10000, "Supply 1 to 2,000 onsets and at most 10,000 event/channel cells.")
    seen <- list(); times <- list()
    for (event in m$events) {
      brohn_fields(event, c("time_s", "code"), c("exposure_id", "recording_id", "condition_id", "stimulus_id"), "EDA event onset")
      brohn_require(brohn_number(event$time_s, 0, 1e12) && brohn_text(event$code, 128), "Measured events require nonnegative relative seconds and a text source code.")
      brohn_require(event$code %in% c(names(codes), unlist(p$nuisance_codes)), "Every event code must be mapped to a condition or declared nuisance.")
      for (field in c("exposure_id", "recording_id", "condition_id", "stimulus_id")) if (!is.null(event[[field]])) brohn_require(brohn_text(event[[field]], 128), "Event identities must be nonempty text or omitted.")
      key <- brohn_default(event$recording_id, "recording-1")
      brohn_require(!event$time_s %in% times[[key]], "Simultaneous codes need an explicit combined-event protocol.")
      times[[key]] <- c(times[[key]], event$time_s)
      if (event$code %in% names(codes)) {
        brohn_require(brohn_text(event$exposure_id, 128) && !event$exposure_id %in% seen[[key]], "Target events require unique exposure identities within each recording.")
        seen[[key]] <- c(seen[[key]], event$exposure_id)
        brohn_require(is.null(event$condition_id) || identical(event$condition_id, codes[[event$code]]), "Explicit event condition conflicts with its code mapping.")
      } else brohn_require(is.null(event$condition_id), "A nuisance event cannot carry a target condition identity.")
      if (!is.null(design) && !is.null(event$stimulus_id)) brohn_require(event$stimulus_id %in% brohn_ids(design$stimuli), "An event stimulus is absent from the frozen study design.")
    }
  }
  invisible(m)
}
brohn_eda_events_worker_request <- function(m, source_format = NULL, columns = NULL) {
  brohn_validate_eda_events_mapping(m, columns, source_format)
  event <- brohn_eda_events_is_event(m)
  list(operation = if (event) "eda_events" else "physiology", script = if (event) "scripts/workers/eda_events.py" else "scripts/workers/physiology.py",
    parameters = brohn_default(m$parameters, list()))
}
brohn_eda_events_code_map <- function(value) {
  brohn_require(brohn_text(value, 32000), "Match measured onset codes to study condition IDs.")
  if (startsWith(trimws(value), "{")) return(brohn_parse(value, 32000))
  rows <- trimws(strsplit(value, "\n", fixed = TRUE)[[1]]); rows <- rows[nzchar(rows)]
  pairs <- strsplit(rows, "=", fixed = TRUE)
  brohn_require(length(pairs) && all(lengths(pairs) == 2L), "Use one source code = condition ID per line.")
  keys <- vapply(pairs, function(x) trimws(x[[1]]), character(1)); values <- lapply(pairs, function(x) trimws(x[[2]]))
  brohn_require(!anyDuplicated(keys) && all(nzchar(keys)) && all(nzchar(unlist(values))), "Use distinct nonempty source codes and condition IDs.")
  stats::setNames(values, keys)
}
brohn_eda_events_event_list <- function(value) {
  brohn_require(brohn_text(value, 1024^2), "Paste the measured event list with time_s, code and target exposure_id columns.")
  if (startsWith(trimws(value), "[")) return(brohn_parse(value, 1024^2))
  table <- tryCatch(utils::read.csv(text = value, colClasses = "character", check.names = FALSE, comment.char = "", na.strings = character(), nrows = 2001),
    error = function(e) brohn_stop("The measured EDA event list is not valid CSV."))
  brohn_require(nrow(table) >= 1 && nrow(table) <= 2000 && !anyDuplicated(names(table)) && all(c("time_s", "code") %in% names(table)) &&
    all(names(table) %in% c("time_s", "code", "exposure_id", "recording_id", "condition_id", "stimulus_id")), "Use time_s, code and target exposure_id; optional recording_id, condition_id and stimulus_id are supported.")
  lapply(seq_len(nrow(table)), function(i) {
    event <- as.list(table[i, , drop = FALSE]); event$time_s <- suppressWarnings(as.numeric(event$time_s))
    brohn_require(brohn_number(event$time_s, 0, 1e12), "Event times must be nonnegative finite relative seconds.")
    for (field in setdiff(names(event), c("time_s", "code"))) if (!nzchar(event[[field]])) event[[field]] <- NULL
    event
  })
}
brohn_eda_events_input <- function(input, metadata, source_format = "csv") {
  m <- metadata; get <- function(name) input[[paste0("map_eda_event_", name)]]
  recipe <- get("recipe")
  brohn_require(brohn_text(recipe, 128) && recipe %in% unname(brohn_eda_events_recipe_choices()), "Choose an EDA analysis recipe.")
  if (identical(recipe, "eda-neurokit-highpass/1.0")) {
    old <- m$parameters
    m$parameters <- if (is.null(old$recipe) || identical(old$recipe, recipe)) brohn_default(old, list()) else list()
    m$parameters$recipe <- recipe; m$event_column <- NULL; m$events <- NULL
    m$recording_column <- NULL; m$valid_column <- NULL
    return(m)
  }
  pair <- function(start, end) list(get(start), get(end))
  nuisance <- brohn_default(get("nuisance_codes"), "")
  brohn_require(brohn_text(nuisance, 16000, empty = TRUE), "Nuisance codes must be a list of source codes, one per line.")
  nuisance <- trimws(strsplit(nuisance, "\n", fixed = TRUE)[[1]]); nuisance <- nuisance[nzchar(nuisance)]
  p <- list(recipe = recipe, event_codes = brohn_eda_events_code_map(get("event_codes")), nuisance_codes = as.list(nuisance),
    event_source = get("event_source"), settings_source = get("settings_source"), baseline_s = pair("baseline_start", "baseline_end"),
    response_s = pair("response_start", "response_end"), onset_latency_s = pair("latency_start", "latency_end"),
    recovery_end_s = get("recovery_end"), nuisance_effect_s = pair("nuisance_start", "nuisance_end"), overlap_policy = get("overlap"),
    response_selection = get("selection"), minimum_scr_amplitude_us = get("minimum_amplitude"), relative_prominence = get("relative_prominence"),
    edge_exclusion_s = get("edge"), minimum_segment_s = get("context"))
  if (identical(get("alignment"), "custom")) p$event_tolerance_s <- get("alignment_tolerance") else
    brohn_require(identical(get("alignment"), "half_sample"), "Choose measured onset alignment tolerance.")
  m$parameters <- p
  for (field in c("recording", "valid")) {
    value <- get(paste0(field, "_column"))
    m[[paste0(field, "_column")]] <- if (is.null(value) || identical(value, "")) NULL else value
  }
  if (identical(get("event_mode"), "column")) { m$event_column <- get("event_column"); m$events <- NULL } else {
    brohn_require(identical(get("event_mode"), "array"), "Choose measured onsets from a column or an event list.")
    m$events <- brohn_eda_events_event_list(get("events")); m$event_column <- NULL
  }
  brohn_validate_eda_events_mapping(m, source_format = source_format)
  m
}

# Human-readable support rows; counts retain modality/measure-specific eligibility.
brohn_eda_events_support <- function(result) {
  brohn_require(identical(result$operation, "eda_events") && identical(result$modality, "eda"), "Expected an EDA event result.")
  rows <- lapply(result$recordings, function(r) list(person = r$group$participant_id, session = r$group$session_id,
    recording = r$recording_id, exposure = r$exposure_id, condition = r$condition_id, channel = r$channel,
    event_time_s = r$time_s, window_status = r$status, window_reason = r$reason,
    scr_status = r$scr_status, scr_reason = r$scr_reason, baseline_complete = isTRUE(r$baseline_support$complete),
    response_complete = isTRUE(r$response_support$complete), same_continuous_segment = isTRUE(r$same_continuous_segment),
    overlapping_events = brohn_default(r$overlapping_event_ids, list()), recovery_reason = r$recovery_missing_reason))
  measures <- lapply(unique(vapply(result$features, function(f) f$name, character(1))), function(name) {
    values <- Filter(function(f) identical(f$name, name), result$features)
    eligible <- vapply(values, function(f) isTRUE(f$eligible) && identical(f$support_status, "computed") && brohn_number(f$value), logical(1))
    list(name = name, eligible_event_channel_cells = sum(eligible), unavailable_event_channel_cells = sum(!eligible),
      missing_reasons = unique(unlist(lapply(values[!eligible], function(f) f$missing_reason), use.names = FALSE)),
      denominator_scope = "event/channel support; not independent people")
  })
  list(rows = rows, measures = measures)
}
