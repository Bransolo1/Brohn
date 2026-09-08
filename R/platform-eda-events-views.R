# Labelled, keyboard-operable disclosure controls; base source mapping stays shared.
brohn_eda_events_settings_ui <- function(m, columns = character(), source_format = "csv") {
  p <- brohn_default(m$parameters, list())
  id <- function(name) paste0("map_eda_event_", name)
  num <- function(name, label, value, fallback = NA_real_, min = NA, max = NA, step = NA)
    shiny::numericInput(id(name), label, brohn_default(value, fallback), min, max, step)
  select <- function(name, label, choices, value, fallback) shiny::selectInput(id(name), label, choices, brohn_default(value, fallback))
  pair <- function(start, end, label, value, fallback = list(NA_real_, NA_real_)) shiny::div(class = "brohn-form-grid",
    num(start, paste(label, "start (s)"), value[[1]], fallback[[1]]), num(end, paste(label, "end (s)"), value[[2]], fallback[[2]]))
  column <- function(name, label, value) shiny::selectInput(id(name), label, c("Choose a column" = "", stats::setNames(columns, columns)), brohn_default(value, ""))
  condition <- function(expr, ...) shiny::conditionalPanel(expr, ...)
  codes <- p$event_codes
  codes_text <- if (is.null(codes)) "" else if (any(grepl("[=\n]", c(names(codes), unlist(codes))))) brohn_json(codes, TRUE) else
    paste(paste(names(codes), "=", unlist(codes)), collapse = "\n")
  if (!source_format %in% c("csv", "tsv")) return(shiny::p("Event-related EDA requires a calibrated continuous CSV or TSV recording with measured event timing."))
  shiny::tagList(shiny::h3("Which EDA response do you want to describe?"),
    select("recipe", "EDA analysis", brohn_eda_events_recipe_choices(), p$recipe, "eda-neurokit-highpass/1.0"),
    condition("input.map_eda_event_recipe === 'eda-neurokit-highpass/1.0'",
      shiny::p("Summarise tonic activity and response candidates within each declared recording segment. Select a stimulus-response recipe to compare explicit baseline and event windows.")),
    condition("input.map_eda_event_recipe !== 'eda-neurokit-highpass/1.0'",
      shiny::p("The continuous person/session recording is processed first. Short trials then receive their own baseline, response and support checks. Condition labels do not restart the filters."),
      shiny::tags$details(open = NA, shiny::tags$summary("1. Connect the continuous recording to measured events"),
        shiny::p(class = "brohn-muted", "Map person, session, sample time, signal unit and exposure identity in the shared source controls above. A target event needs its own exposure ID."),
        shiny::div(class = "brohn-form-grid", column("recording_column", "Acquisition reset or recording ID (optional)", m$recording_column),
          column("valid_column", "Source validity flag (optional; missing means invalid)", m$valid_column)),
        select("event_mode", "Where are the measured onsets?", c("A column in this recording" = "column", "An explicit event list" = "array"),
          if (!is.null(m$events)) "array" else "column", "column"),
        condition("input.map_eda_event_event_mode === 'column'", column("event_column", "Onset code column (blank between events)", m$event_column)),
        condition("input.map_eda_event_event_mode === 'array'", shiny::textAreaInput(id("events"), "Measured event list",
          if (is.null(m$events)) "" else brohn_json(m$events, TRUE), rows = 5, width = "100%",
          placeholder = "time_s,code,exposure_id,recording_id\n20,A,trial-1,recording-1"),
          shiny::p(class = "brohn-muted", "Times are seconds after the first sample of the named recording, before filtering. With several recordings, name recording-1, recording-2, etc., in source order. Optional condition_id and stimulus_id are retained.")),
        shiny::textAreaInput(id("event_codes"), "Match source codes to condition IDs", codes_text, rows = 3, width = "100%", placeholder = "A = control\nB = test"),
        shiny::textAreaInput(id("event_source"), "How were stimulus onsets measured and aligned?", brohn_default(p$event_source, ""), rows = 2, width = "100%",
          placeholder = "Measured marker source, clock alignment and known timing uncertainty."),
        select("alignment", "Align measured onsets to samples", c("Within half one sample interval" = "half_sample", "Use a stricter declared tolerance" = "custom"),
          if (is.null(p$event_tolerance_s)) "half_sample" else "custom", "half_sample"),
        condition("input.map_eda_event_alignment === 'custom'", num("alignment_tolerance", "Largest onset alignment error (s; zero requires an exact sample)", p$event_tolerance_s, 0, 0, 1))),
      shiny::tags$details(open = NA, shiny::tags$summary("2. Define baseline and response windows"),
        shiny::p(class = "brohn-muted", "Choose windows from your protocol. Negative seconds precede onset. Both windows need complete measured support in the same continuous segment; missing baseline is never a zero response."),
        pair("baseline_start", "baseline_end", "Tonic baseline", p$baseline_s),
        pair("response_start", "response_end", "Tonic and phasic response", p$response_s),
        pair("latency_start", "latency_end", "Allowed SCR onset latency", p$onset_latency_s),
        num("recovery_end", "Observe half-recovery until (s after onset)", p$recovery_end_s, min = 0, max = 300)),
      shiny::tags$details(shiny::tags$summary("3. Handle movement, overlap and response selection"),
        shiny::textAreaInput(id("nuisance_codes"), "Other recorded events that can affect EDA (one code per line)", paste(unlist(p$nuisance_codes), collapse = "\n"),
          rows = 2, width = "100%", placeholder = "MOVE\nINSTRUCTION"),
        pair("nuisance_start", "nuisance_end", "Nuisance effect", p$nuisance_effect_s, list(0, 8)),
        select("overlap", "When target windows or nuisance effects overlap", c("Exclude the affected event outcomes" = "exclude", "Keep tonic/phasic descriptives; exclude SCR attribution" = "descriptive_only"), p$overlap_policy, "exclude"),
        select("selection", "When several SCR candidates qualify", c("Use the first qualifying onset" = "first_onset", "Use the largest qualifying amplitude" = "largest_amplitude"), p$response_selection, "first_onset"),
        shiny::div(class = "brohn-form-grid", num("minimum_amplitude", "Minimum onset-to-peak amplitude (microsiemens)", p$minimum_scr_amplitude_us, min = .000001, max = 100),
          num("relative_prominence", "Candidate prominence relative to the segment maximum", p$relative_prominence, .1, .001, 1, .01)),
        shiny::p(class = "brohn-muted", "The absolute amplitude and relative candidate thresholds are different. A valid nonresponse has zero magnitude; missing or ambiguous evidence remains unavailable. Half-recovery can be unavailable even when amplitude is usable.")),
      shiny::tags$details(shiny::tags$summary("4. Review continuous processing and record the method"),
        shiny::div(class = "brohn-form-grid", num("edge", "Exclude at each continuous boundary (s)", p$edge_exclusion_s, 10, 10, 300),
          num("context", "Minimum continuous recording context (s)", p$minimum_segment_s, 40, 40, 3600)),
        shiny::p(class = "brohn-muted", "At least 20 seconds must remain after both edge exclusions. Missing, negative or source-invalid samples and clock gaps always split the recording. The cleaner uses a fixed 3 Hz lowpass."),
        condition("input.map_eda_event_recipe === 'eda-event-highpass/1.0'", shiny::p("This recipe separates tonic and phasic activity using the pinned 0.05 Hz highpass method.")),
        condition("input.map_eda_event_recipe === 'eda-event-cvxeda-defaults/1.0'", shiny::p("This recipe uses verified cvxEDA public defaults, with at most 10,000 samples per continuous segment. It does not resolve which overlapping stimulus caused a response.")),
        shiny::textAreaInput(id("settings_source"), "Protocol version and rationale for the selected settings", brohn_default(p$settings_source, ""), rows = 3, width = "100%",
          placeholder = "Name the reviewed method or analysis plan supporting windows, amplitude threshold, overlap policy and acquisition context."))))
}

brohn_eda_events_support_ui <- function(result) {
  support <- brohn_eda_events_support(result)
  reason_text <- function(reason) {
    if (is.null(reason)) return(NULL)
    phrases <- c(ambiguous_overlapping_events = "Overlapping events prevent a clear response attribution",
      incomplete_baseline_response_or_continuous_context = "The baseline, response window or surrounding recording is incomplete",
      missing_gap_filter_edge_or_short_continuous_context = "Missing data, a recording gap, filter edge or short recording limits support",
      no_qualifying_response = "No response met the selected detection criteria",
      half_recovery_not_observed_in_retained_segment = "Half-recovery was not observed in the retained recording",
      half_recovery_after_declared_boundary = "Half-recovery occurs after the chosen observation window",
      another_event_precedes_half_recovery = "Another event occurs before half-recovery",
      unavailable = "Unavailable", observed_response = "Response observed", nonresponse = "No qualifying response")
    result <- as.character(reason)
    for (code in names(phrases)) result <- gsub(code, phrases[[code]], result, fixed = TRUE)
    gsub("_", " ", result, fixed = TRUE)
  }
  scroll_table <- function(label, ...) shiny::div(class = "brohn-table", tabindex = "0", role = "region",
    `aria-label` = paste0(label, "; scroll horizontally for more columns"), shiny::tags$table(shiny::tags$caption(label), ...))
  shiny::tagList(shiny::h2("Event support"),
    shiny::p("Eligibility belongs to each measure. Event/channel counts are not independent participant counts."),
    scroll_table("Available event/channel cells by measure",
      shiny::tags$thead(shiny::tags$tr(shiny::tags$th(scope = "col", "Measure"), shiny::tags$th(scope = "col", "Available"), shiny::tags$th(scope = "col", "Unavailable"), shiny::tags$th(scope = "col", "Reasons"))),
      shiny::tags$tbody(lapply(support$measures, function(m) shiny::tags$tr(shiny::tags$th(scope = "row", gsub("_", " ", m$name)),
        shiny::tags$td(m$eligible_event_channel_cells), shiny::tags$td(m$unavailable_event_channel_cells), shiny::tags$td(paste(vapply(m$missing_reasons, reason_text, character(1)), collapse = "; ")))))),
    shiny::tags$details(shiny::tags$summary("Review each event's baseline and response support"),
      scroll_table("Measured event support within each person, session and channel",
        shiny::tags$thead(shiny::tags$tr(lapply(c("Person / session", "Exposure / channel", "Baseline", "Response", "SCR", "Reason"), function(x) shiny::tags$th(scope = "col", x)))),
        shiny::tags$tbody(lapply(support$rows, function(r) shiny::tags$tr(shiny::tags$th(scope = "row", paste(r$person, r$session, sep = " / ")),
          shiny::tags$td(paste(r$exposure, r$channel, sep = " / ")), shiny::tags$td(if (r$baseline_complete) "Complete" else "Unavailable"),
          shiny::tags$td(if (r$response_complete) "Complete" else "Unavailable"), shiny::tags$td(reason_text(r$scr_status)),
          shiny::tags$td(paste(vapply(unique(Filter(Negate(is.null), list(r$window_reason, r$scr_reason, r$recovery_reason))), reason_text, character(1)), collapse = "; "))))))))
}
