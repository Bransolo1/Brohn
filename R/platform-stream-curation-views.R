brohn_stream_curation_ui <- function(record) {
  b <- record$body; s <- b$manifest
  reason <- if (!identical(s$kind, "signal")) "Marker and unclassified streams remain typed source data; this analysis input route needs a declared analogue signal." else
    if (!brohn_number(s$nominal_srate, 1, 100000)) "This stream has no supported regular nominal sampling rate. Preserve its original samples while a separate resampling protocol is specified." else
      if (!any(vapply(s$channels, function(c) c$value_type %in% c("float32", "float64", "int8", "int16", "int32", "int64"), logical(1)))) "This stream has no declared scalar numeric channels." else NULL
  brohn_card(title = "Use recorded signals in analysis", subtitle = "Choose channels once, review units and identities, and prepare one dataset with explicit recording segments.",
    if (!is.null(reason)) shiny::p(reason) else shiny::tagList(
      shiny::p("The full source remains in this library. Clock resets, gaps and omitted rows become separate segment boundaries; they do not become new participants or exposures."),
      brohn_command("Curate channels for analysis", "open_stream_curation", list(stream_id = record$id, revision = record$revision, hash = brohn_hash(b)))),
    shiny::uiOutput("stream_curation_history"))
}

brohn_curated_stream_dataset_ui <- function(store, record) {
  p <- record$body$source_provenance
  if (!identical(p$acquisition, "curated_stream")) return(NULL)
  q <- p$quality
  brohn_card(title = "Prepared from a preserved signal stream",
    shiny::p(paste(q$included_rows, "included rows from", q$source_rows, "original rows;", q$excluded_rows, "excluded rows;", q$segment_count, "separate signal segments.")),
    shiny::p("The source recording, canonical typed channels and full inclusion/exclusion decisions remain available. Original participant and session identities are preserved; analysis groups use the separate segment column."),
    shiny::div(class = "brohn-toolbar", brohn_command("Open original recording", "open_dataset", p$lineage$raw_dataset_id),
      brohn_command("Review curation decisions", "review_stream_curation", p$curation_id)))
}

brohn_install_stream_curation_ui <- function(input, output, session, store, state, attempt, message, refresh, prepare_download) {
  draft <- new.env(parent = emptyenv()); draft$active <- NULL; draft$review <- NULL
  current_stream <- function(id = input$multistream_stream_id) {
    brohn_require(identical(state$page, "dataset") && brohn_text(id, 200), "Open a preserved stream in the original dataset first.")
    record <- brohn_get_entity(store, "stream", id)
    brohn_require(!is.null(record) && identical(state$dataset_id, record$body$source_dataset_id), "Choose a stream from the original recording currently open.")
    record
  }
  shiny::observeEvent(input$open_stream_curation, attempt(function() {
    command <- input$open_stream_curation
    brohn_fields(command, c("stream_id", "revision", "hash"), label = "Stream selection command")
    record <- current_stream(command$stream_id)
    brohn_require(identical(input$multistream_stream_id, record$id) && identical(as.numeric(command$revision), as.numeric(record$revision)) &&
      identical(command$hash, brohn_hash(record$body)), "The selected source changed. Reopen its current curation controls.")
    brohn_project(store, record$project_id)
    s <- record$body$manifest
    brohn_require(identical(s$kind, "signal") && brohn_number(s$nominal_srate, 1, 100000), "This source needs a supported analogue stream and positive nominal sampling rate.")
    channels <- Filter(function(c) c$value_type %in% c("float32", "float64", "int8", "int16", "int32", "int64"), s$channels)
    brohn_require(length(channels) > 0L, "This stream has no scalar numeric channels.")
    id <- brohn_id("stream-editor"); draft$active <- list(id = id, stream_id = record$id, revision = record$revision, hash = brohn_hash(record$body), sampling_rate = s$nominal_srate)
    known_units <- unique(vapply(channels, function(c) brohn_default(c$unit, ""), character(1)))
    choices <- stats::setNames(vapply(channels, `[[`, character(1), "id"), vapply(channels, function(c) paste(c$id, "-", brohn_default(c$label, c$id), "(", brohn_default(c$unit, "unit not recorded"), ")"), character(1)))
    shiny::showModal(shiny::modalDialog(title = "Prepare recorded channels for analysis", size = "l", easyClose = FALSE,
      shiny::tags$input(id = "stream_curation_form", type = "text", class = "shiny-input-text", value = id, style = "display:none", `aria-hidden` = "true", tabindex = "-1"),
      shiny::p(paste(s$sample_count, "source samples at a declared", s$nominal_srate, "Hz;", s$segment_count, "preserved source segments.")),
      shiny::selectInput("stream_curation_channels", "Numeric channels", choices, selected = if (length(channels) == 1L) channels[[1L]]$id else character(), multiple = TRUE),
      shiny::selectInput("stream_curation_modality", "Analysis family", c("Choose an analysis family" = "", "EEG" = "eeg", "EDA" = "eda", "ECG" = "ecg", "PPG" = "ppg", "Respiration" = "respiration", "EMG" = "emg"), ""),
      shiny::textInput("stream_curation_unit", "Reviewed output unit", if (length(known_units) == 1L) known_units[[1L]] else ""),
      shiny::p(class = "brohn-muted", "EEG/ECG/EMG: V, mV or uV. EDA: S or uS. PPG: a.u., V or mV. Respiration: a.u., V, mV, L or L/s. Compatible source units are converted explicitly; recorded calibration scale/offset needs a separately calibrated source."),
      shiny::textAreaInput("stream_curation_unit_rationale", "Evidence for these units", "", rows = 2, width = "100%",
        placeholder = "Recorded channel unit or source documentation. Explain any unit missing from the source; choosing a unit alone does not calibrate raw device counts."),
      shiny::tags$details(shiny::tags$summary("Participant and session identity"),
        shiny::p("Existing source identities are kept exactly. These fields only fill identities missing from a source row; leave them empty if every source row already has both codes."),
        shiny::textInput("stream_curation_participant", "Participant code for rows with no participant ID", ""),
        shiny::textInput("stream_curation_session", "Session code for rows with no session ID", ""),
        brohn_table(lapply(head(s$preview, 5), function(r) list(source_sequence = r$sequence, original_identity = r$identity)), maximum = 5, label = "Original identity preview")),
      shiny::textAreaInput("stream_curation_origin", "Source and identity review", "", rows = 2, width = "100%",
        placeholder = "Which recording/people these selected signals represent, and any collection limitations."),
      shiny::checkboxInput("stream_curation_units_confirmed", "I reviewed the source units and any missing-unit declaration", FALSE),
      shiny::checkboxInput("stream_curation_boundaries_confirmed", "Keep resets and gaps separate, and omit rows missing any selected channel without interpolation", FALSE),
      shiny::checkboxInput("stream_curation_run_analysis", "Run standard channel analysis after preparation", TRUE),
      shiny::conditionalPanel("input.stream_curation_modality === 'respiration' && input.stream_curation_run_analysis",
        brohn_respiration_settings_ui(prefix = "stream_curation_respiration")),
      shiny::uiOutput("stream_curation_recipe"),
      shiny::p("Short segments and method-specific exclusions remain visible. No condition or exposure identity is invented. Uncheck automatic analysis to prepare the dataset for a separately configured supported recipe."),
      footer = shiny::tagList(brohn_command("Cancel", "cancel_stream_curation", list(editor_id = id)),
        brohn_command("Prepare analysis dataset", "save_stream_curation", list(editor_id = id), "btn btn-primary"))))
  }))
  output$stream_curation_recipe <- shiny::renderUI({
    a <- draft$active; if (is.null(a)) return(NULL)
    modality <- input$stream_curation_modality
    if (is.null(modality) || !modality %in% brohn_stream_modalities()) return(shiny::p("Choose an analysis family to preview its standard channel recipe."))
    summary <- switch(modality,
      eeg = "EEG: channel Welch spectra with 2-second Hann windows and 50% overlap; fixed delta/theta/alpha/beta/gamma bands. The acquisition reference is retained; no ERP or condition effect is assumed.",
      eda = "EDA: NeuroKit cleaning, tonic/phasic decomposition at 0.05 Hz, relative-prominence response peaks and 10-second edge exclusions. This is descriptive channel activity, not an inferred stress score.",
      ecg = "ECG: NeuroKit cleaning/detected intervals, 50 Hz mains setting, 2-second edge exclusions and 300-2000 ms interval screening. Confirm a 50 Hz acquisition environment; this is not automatically qualified normal-to-normal HRV.",
      ppg = "PPG: Elgendi pulse detection, 2-second edge exclusions and 300-2000 ms interval screening. Pulse-rate variability is retained separately from ECG HRV.",
      respiration = "Respiration: explicitly declared belt displacement or calibrated lung volume, reviewed inspiration direction, Khodadad cleaning/cycle detection and 5-second edge exclusions. Airflow can be prepared with automatic analysis unchecked.",
      emg = "EMG: zero-phase Butterworth filtering, 50 ms RMS envelope and 0.25-second edge exclusions. Burst thresholds and MVC normalisation are not invented.")
    shiny::tagList(shiny::p(summary), shiny::p(class = "brohn-muted", "These are descriptive channel/recording analyses. Participant comparisons, experimental baselines and condition effects require their own supported design and mapping."),
      shiny::tags$details(shiny::tags$summary("Standard recipe parameters saved for this analysis"), shiny::tags$pre(brohn_json(brohn_stream_standard_parameters(modality, a$sampling_rate,
        if (identical(modality, "respiration")) brohn_respiration_input(input, "stream_curation_respiration") else NULL), TRUE))))
  })
  shiny::observeEvent(input$cancel_stream_curation, attempt(function() {
    brohn_require(!is.null(draft$active) && is.list(input$cancel_stream_curation) && identical(input$cancel_stream_curation$editor_id, draft$active$id), "Choose the current curation dialog's Cancel button.")
    draft$active <- NULL; shiny::removeModal(); message("Stream curation changes discarded.")
  }))
  shiny::observeEvent(input$save_stream_curation, attempt(function() {
    a <- draft$active
    brohn_require(!is.null(a) && is.list(input$save_stream_curation) && identical(input$save_stream_curation$editor_id, a$id) && identical(input$stream_curation_form, a$id), "Choose the current source curation dialog's Prepare button.")
    record <- current_stream(a$stream_id)
    brohn_require(identical(input$multistream_stream_id, record$id) && identical(record$revision, a$revision) && identical(brohn_hash(record$body), a$hash), "The selected source changed. Reopen curation before saving.")
    blank <- function(value) if (is.null(value) || !nzchar(trimws(value))) NULL else value
    selection <- list(schema = "brohn-stream-selection/1.0", channel_ids = as.list(input$stream_curation_channels), modality = input$stream_curation_modality,
      unit = input$stream_curation_unit, sampling_rate = record$body$manifest$nominal_srate,
      participant_id = blank(input$stream_curation_participant), session_id = blank(input$stream_curation_session), origin_statement = input$stream_curation_origin,
      unit_rationale = input$stream_curation_unit_rationale, confirm_source_units = isTRUE(input$stream_curation_units_confirmed), confirm_boundaries = isTRUE(input$stream_curation_boundaries_confirmed),
      run_analysis = if (is.logical(input$stream_curation_run_analysis) && length(input$stream_curation_run_analysis) == 1L) input$stream_curation_run_analysis else NULL)
    if (identical(selection$modality, "respiration") && isTRUE(selection$run_analysis)) selection$respiration <- brohn_respiration_input(input, "stream_curation_respiration")
    brohn_queue_stream_curation(store, record$id, selection, record$revision)
    draft$active <- NULL; shiny::removeModal(); message("Selected channels queued for curation. The original source remains preserved."); refresh()
  }))
  history <- shiny::reactiveVal(NULL)
  shiny::observe({
    shiny::invalidateLater(1000, session)
    record <- tryCatch(current_stream(), error = function(e) NULL)
    next_value <- if (is.null(record)) NULL else {
      jobs <- brohn_list_jobs(store, request_filters = list(stream_id = record$id), operation = "extract_stream")
      results <- head(brohn_stream_curations(store, stream_id = record$id), 5L)
      analysis_status <- lapply(results, function(r) if (!is.null(r$body$analysis_job_id)) brohn_get_job(store, r$body$analysis_job_id)$status else NULL)
      list(stream_id = record$id, jobs = lapply(head(jobs, 5L), function(j) j[c("id", "status", "error")]), results = results, analysis_status = analysis_status)
    }
    if (!identical(shiny::isolate(history()), next_value)) history(next_value)
  })
  output$stream_curation_history <- shiny::renderUI({
    value <- history(); if (is.null(value)) return(NULL)
    jobs <- value$jobs; results <- value$results
    if (!length(jobs) && !length(results)) return(NULL)
    shiny::tagList(lapply(head(jobs, 5), function(j) shiny::div(class = "brohn-toolbar", brohn_badge(paste("Curation", j$status)),
      if (!is.null(j$error)) shiny::p(j$error$message),
      if (j$status %in% c("failed", "cancelled")) brohn_command("Retry saved curation", "retry_processing", j$id))),
      lapply(seq_along(results), function(i) {r <- results[[i]]; shiny::div(class = "brohn-stack",
        shiny::p(paste(r$body$extraction$quality$included_rows, "of", r$body$extraction$quality$source_rows, "source rows retained in", r$body$extraction$quality$segment_count, "explicit segments.")),
        if (!is.null(r$body$analysis_job_id)) shiny::p(paste("Standard channel analysis:", value$analysis_status[[i]])),
        if (is.null(r$body$dataset_id)) shiny::p("No segment has at least two usable rows. Inspect the preserved decisions before selecting another source or channel set."),
        shiny::div(class = "brohn-toolbar", if (!is.null(r$body$dataset_id)) brohn_command("Open curated dataset", "open_dataset", r$body$dataset_id, "btn btn-primary"),
          brohn_command("Review curation decisions", "review_stream_curation", r$id)))}))
  })
  reviewed <- function(id = if (!is.null(draft$review)) draft$review$id else NULL) {
    brohn_require(identical(state$page, "dataset") && brohn_text(id, 200), "Open the curation from its source or derived dataset.")
    r <- brohn_get_entity(store, "stream_curation", id)
    brohn_require(!is.null(r) && state$dataset_id %in% c(r$body$source_dataset_id, r$body$dataset_id), "This curation does not belong to the dataset currently open.")
    if (!is.null(draft$review) && identical(id, draft$review$id)) brohn_require(identical(brohn_hash(r$body), draft$review$hash), "The curation evidence changed. Reopen its current review.")
    r
  }
  shiny::observeEvent(input$review_stream_curation, attempt(function() {
    r <- reviewed(input$review_stream_curation); draft$review <- list(id = r$id, hash = brohn_hash(r$body))
    e <- r$body$extraction; q <- e$quality
    shiny::showModal(shiny::modalDialog(title = "Recorded stream curation decisions", size = "l", easyClose = TRUE,
      shiny::p(paste(q$source_rows, "original rows;", q$included_rows, "included;", q$excluded_rows, "excluded;", q$segment_count, "independent signal segments.")),
      brohn_table(list(q), label = "Complete curation support counts"),
      shiny::p(paste("Showing", min(20, length(e$segments)), "of", length(e$segments), "segments. The full manifest includes every segment; the decision JSONL includes every original row.")),
      brohn_table(e$segments, maximum = 20, label = "Derived segment support"),
      shiny::tags$details(shiny::tags$summary("Reviewed channels, units and source identity"),
        brohn_table(e$parameters$unit_conversions, maximum = 64, label = "Explicit unit conversions"),
        shiny::tags$pre(brohn_json(r$body$lineage, TRUE)), shiny::tags$pre(brohn_json(e$selection, TRUE))),
      shiny::div(class = "brohn-toolbar", shiny::downloadButton("stream_curation_manifest_download", "Download full curation manifest", icon = NULL),
        shiny::downloadButton("stream_curation_decisions_download", "Download every source-row decision", icon = NULL),
        if (!is.null(r$body$dataset_id)) shiny::downloadButton("stream_curation_csv_download", "Download complete curated CSV", icon = NULL)),
      footer = shiny::modalButton("Close")))
  }))
  output$stream_curation_manifest_download <- shiny::downloadHandler(filename = function() paste0(reviewed()$id, ".json"),
    content = function(file) prepare_download(function() brohn_copy_object_download(store, reviewed()$body$result_object$hash, file)))
  output$stream_curation_decisions_download <- shiny::downloadHandler(filename = function() paste0(reviewed()$id, "-decisions.jsonl"),
    content = function(file) prepare_download(function() {
      a <- Filter(function(a) identical(a$kind, "curation_decisions_jsonl"), reviewed()$body$extraction$artifacts)
      brohn_require(length(a) == 1L, "The full decision artifact is unavailable."); brohn_copy_object_download(store, a[[1L]]$hash, file)
    }))
  output$stream_curation_csv_download <- shiny::downloadHandler(filename = function() paste0(reviewed()$id, "-curated.csv"), contentType = "text/csv",
    content = function(file) prepare_download(function() {
      r <- reviewed(); brohn_require(!is.null(r$body$dataset_id), "This curation has no usable derived dataset.")
      a <- Filter(function(a) identical(a$kind, "curated_signal_csv"), r$body$extraction$artifacts)
      brohn_require(length(a) == 1L, "The complete curated CSV artifact is unavailable.")
      brohn_copy_object_download(store, a[[1L]]$hash, file)
    }))
  invisible(list(context = function() draft$active, reviewed = reviewed))
}
