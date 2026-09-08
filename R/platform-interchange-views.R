# Recorded multistream evidence has its own review flow, separate from reports.
brohn_interchange_dataset_ui <- function(store, record) {
  d <- record$body; m <- d$metadata
  brohn_page(d$title, paste("Multistream recording", "\u00b7", d$source$filename, "\u00b7", "revision", record$revision),
    actions = shiny::downloadButton("multistream_original", "Download original recording", icon = NULL),
    brohn_card(title = "One recording, every source stream",
      subtitle = "Preserve signals, event markers, original clocks and recorded correction evidence together.",
      shiny::div(class = "brohn-toolbar", brohn_badge(d$origin, if (d$origin == "live") "neutral" else "warning"),
        brohn_badge(if (d$status %in% c("accepted", "analysed")) "Source declaration saved" else "Source saved")),
      shiny::p(paste("Original saved", d$source_provenance$imported_at)),
      shiny::tags$details(shiny::tags$summary("Original source identity"), shiny::p(paste("SHA-256", d$source$hash)),
        shiny::p(paste(format(d$source$size, big.mark = ",", scientific = FALSE), "bytes")))),
    brohn_card(title = "Confirm the source", subtitle = "This keeps each recorded stream intact. Scientific analysis follows a separate, explicit mapping step.",
      shiny::div(style = "display:none", shiny::textInput("multistream_form_identity", NULL, paste(record$id, record$revision, sep = ":"))),
      shiny::selectizeInput("map_study", "Link this recording to a study", choices = NULL, options = list(placeholder = "Search studies in this project", maxOptions = 100)),
      shiny::uiOutput("mapping_study_revision"),
      shiny::textAreaInput("map_origin", "Where did this recording come from?", brohn_default(m$origin_statement, ""),
        width = "100%", rows = 3, placeholder = "Recorder/device export, collection setting, participant identity scheme and preprocessing already applied."),
      shiny::checkboxInput("map_preserve_clocks", "Preserve original clocks and recorded corrections without applying synchronization", identical(m$clock_policy, "preserve_only")),
      shiny::p(class = "brohn-muted", "Source-declared sample or pilot data stays labelled as such. Unknown units, missing samples and timing boundaries remain visible."),
      shiny::actionButton("accept_multistream", if (d$status %in% c("accepted", "analysed")) "Save notes and preserve streams" else "Preserve streams", class = "btn-primary")),
    shiny::uiOutput("multistream_progress"), shiny::uiOutput("multistream_history"),
    shiny::uiOutput("multistream_catalog"), shiny::uiOutput("multistream_stream_detail"))
}

brohn_interchange_progress_ui <- function(jobs) {
  brohn_card(title = "Import progress",
    if (!length(jobs)) shiny::p("Confirm the source to extract and preserve its streams.") else
      lapply(head(jobs, 5L), function(job) shiny::div(class = "brohn-stack",
        shiny::div(class = "brohn-toolbar", brohn_badge(switch(job$status, succeeded = "Streams preserved", running = "Preserving streams", queued = "Queued", job$status),
          if (job$status == "failed") "error" else if (job$status == "succeeded") "success" else "neutral"),
          shiny::span(paste("Source revision", job$request$dataset_revision, "\u00b7", job$updated_at))),
        if (!is.null(job$error)) shiny::p(job$error$message),
        if (job$status %in% c("queued", "running")) brohn_command("Cancel import", "cancel_processing", job$id),
        if (job$status %in% c("failed", "cancelled")) brohn_command("Retry saved source", "retry_processing", job$id))))
}

brohn_interchange_summary_ui <- function(record) {
  b <- record$body
  brohn_card(title = "Preserved stream catalog",
    subtitle = paste(b$stream_count, "streams", "\u00b7", format(b$sample_count, big.mark = ",", scientific = FALSE),
      "sample/event rows in total", "\u00b7", "source revision", b$dataset_revision),
    shiny::div(class = "brohn-toolbar", brohn_badge(b$origin, if (b$origin %in% c("mixed", "sample", "pilot")) "warning" else "neutral"),
      brohn_badge(if (b$status == "needs_mapping") "Source details need review" else "All streams preserved"), brohn_badge("Original clocks")),
    if (isTRUE(b$manifest$quality$origin_conflict)) shiny::div(class = "brohn-alert brohn-alert-warning", role = "note",
      "The source and import declarations differ. Individual stream labels retain their source declaration; the recording is marked mixed."),
    shiny::p("These counts describe recorded rows, not participants. Signals and markers retain their own order and clock boundaries."),
    shiny::div(class = "brohn-toolbar", shiny::downloadButton("multistream_manifest", "Download stream manifest", icon = NULL),
      shiny::downloadButton("multistream_container", "Download recording evidence", icon = NULL)),
    shiny::tags$details(shiny::tags$summary("Import settings and source declarations"),
      shiny::p(b$manifest$origin_statement), shiny::tags$pre(brohn_json(b$manifest$parameters, TRUE)),
      shiny::tags$ul(lapply(b$manifest$limitations, shiny::tags$li))))
}

brohn_interchange_stream_ui <- function(record) {
  b <- record$body; s <- b$manifest; q <- s$quality
  channel_rows <- lapply(s$channels, function(channel) list(id = channel$id, label = channel$label, type = channel$type,
    unit = channel$unit, value_type = channel$value_type, missing_count = q$missing_values_by_channel[[channel$id]],
    scale = channel$scale, offset = channel$offset))
  # A bounded table stays readable even when a source has hundreds of channels.
  shown <- head(vapply(s$channels, `[[`, character(1), "id"), 6L)
  rows <- lapply(s$preview, function(row) {
    values <- list(sequence = row$sequence, segment = row$segment_id, timestamp = row$source_timestamp,
      timestamp_state = row$timestamp_state, identity = row$identity)
    for (id in shown) {
      values[paste0(id, " value")] <- list(row$values[[id]])
      values[paste0(id, " state")] <- list(row$value_states[[id]])
    }
    values
  })
  brohn_card(title = b$title, subtitle = paste(s$type, "\u00b7", s$sample_count, if (s$kind == "markers") "events" else "samples", "\u00b7", length(s$channels), "channels"),
    shiny::div(class = "brohn-toolbar", brohn_badge(switch(s$kind, signal = "Signal", markers = "Event markers", "Unclassified stream")),
      brohn_badge(b$origin, if (b$origin %in% c("live", "imported")) "neutral" else "warning"), brohn_badge("Mapping not yet confirmed")),
    if (isTRUE(q$requires_mapping)) shiny::p(class = "brohn-alert brohn-alert-warning",
      if (length(q$unknown_unit_channels)) paste("No unit was declared for:", paste(unlist(q$unknown_unit_channels), collapse = ", "), ". Keep these uncalibrated until their source documentation is checked.") else
        "The source stream type is unclassified. Its original values are retained."),
    if (identical(s$orderly_closed, FALSE)) shiny::p(class = "brohn-alert brohn-alert-warning", "The source has no closing stream footer. All recoverable rows are retained, but completeness needs review."),
    shiny::p(paste("Clock:", s$clock$id, "\u00b7", "timestamp unit:", s$clock$unit, "\u00b7", s$segment_count, "separate source segments")),
    shiny::p(if (s$nominal_srate > 0) paste("Declared nominal sampling rate:", s$nominal_srate, "Hz. Actual source intervals remain unchanged.") else
      "The source declares an irregular sampling rate. No regular interval is assumed."),
    shiny::div(class = "brohn-toolbar", shiny::downloadButton("multistream_jsonl", "Download complete data (JSONL)", icon = NULL),
      shiny::downloadButton("multistream_csv", "Download CSV", icon = NULL),
      shiny::downloadButton("multistream_evidence", "Download clock and metadata evidence", icon = NULL)),
    shiny::p(class = "brohn-muted", "JSONL retains exact large integers, typed marker values and missing states. Use CSV with its state columns and the schema in the manifest."),
    shiny::tags$details(open = NA, shiny::tags$summary("Source preview"),
      shiny::p(paste("Showing", length(rows), "of", s$sample_count, "rows and", length(shown), "of", length(s$channels), "channels. Complete downloads retain every row and channel.")),
      if (!s$sample_count) shiny::p("This declared stream contains no samples. Its metadata is still retained.") else brohn_table(rows, maximum = 20L, label = "Recorded stream preview")),
    shiny::tags$details(shiny::tags$summary("Channel labels, units and missing values"),
      brohn_table(channel_rows, maximum = 256L, label = "Declared channels"),
      shiny::p("Any declared scale and offset are preserved as evidence; this import has not applied calibration.")),
    shiny::tags$details(shiny::tags$summary("Timing, gaps and identity boundaries"),
      shiny::p(paste(q$reconstructed_timestamp_count, "timestamps reconstructed from the declared nominal rate;", q$invalid_or_unanchored_timestamp_count, "timestamps missing or unanchored.")),
      shiny::p(paste(s$clock_offset_count, "recorded clock corrections; none applied.")),
      shiny::p(paste("Showing", length(s$segments_preview), "of", s$segment_count, "segments. Full boundaries are included in the clock and metadata download.")),
      brohn_table(s$segments_preview, columns = c("first_sequence", "last_sequence", "sample_count", "clock_id", "identity", "boundary_reasons", "start_timestamp", "end_timestamp", "span_s"), label = "Source segment boundaries"),
      if (length(s$clock_offsets_preview)) shiny::tagList(shiny::p(paste("Showing", length(s$clock_offsets_preview), "of", s$clock_offset_count, "recorded corrections.")),
        brohn_table(s$clock_offsets_preview, label = "Recorded clock correction evidence"))),
    shiny::tags$details(shiny::tags$summary("Source identity and import checks"),
      brohn_table(list(list(source_id = s$source_id, uid = s$uid, source_session_id = s$source_session_id,
        origin = s$origin, origin_basis = s$origin_basis, origin_declaration = s$origin_declaration)), label = "Stream source identity"),
      shiny::tags$pre(brohn_json(q, TRUE))))
}

brohn_install_interchange_server <- function(input, output, session, store, state, attempt, refresh, message, prepare_download) {
  selected_dataset <- shiny::reactive({
    state$refresh
    shiny::req(state$page == "dataset", state$dataset_id)
    record <- brohn_get_entity(store, "dataset", state$dataset_id)
    shiny::req(!is.null(record), identical(record$body$modality, "multimodal"))
    record
  })
  # Poll data separately so typing source notes and exploring previews keeps focus.
  snapshot <- shiny::reactivePoll(2000, session,
    checkFunc = function() {
      id <- state$dataset_id
      if (!identical(state$page, "dataset") || is.null(id)) return(NULL)
      jobs <- brohn_list_jobs(store, request_filters = list(dataset_id = id), operation = c("normalise_dataset", "import_multistream"))
      brohn_hash(list(id, lapply(jobs, function(j) list(j$id, j$status, j$updated_at)), lapply(brohn_stream_imports(store, id), function(r) list(r$id, r$revision))))
    }, valueFunc = function() {
      record <- selected_dataset()
      list(jobs = brohn_list_jobs(store, request_filters = list(dataset_id = record$id), operation = c("normalise_dataset", "import_multistream")),
        imports = brohn_stream_imports(store, record$id))
    })
  selected_import <- shiny::reactive({
    items <- snapshot()$imports; shiny::req(length(items) > 0L)
    selected <- which(vapply(items, function(x) identical(x$id, input$multistream_import_id), logical(1)))
    items[[if (length(selected)) selected[[1L]] else 1L]]
  })
  selected_stream <- shiny::reactive({
    imported <- selected_import()
    records <- brohn_streams(store, import_id = imported$id)
    shiny::req(length(records) > 0L)
    selected <- which(vapply(records, function(x) identical(x$id, input$multistream_stream_id), logical(1)))
    records[[if (length(selected)) selected[[1L]] else 1L]]
  })
  shiny::observeEvent(input$accept_multistream, attempt(function() {
    d <- selected_dataset()
    brohn_require(identical(input$multistream_form_identity, paste(d$id, d$revision, sep = ":")), "This source changed. Reopen it before confirming its declaration.")
    brohn_require(isTRUE(input$map_preserve_clocks), "Confirm the original-clock preservation policy.")
    metadata <- list(origin_statement = input$map_origin, clock_policy = "preserve_only")
    chosen <- input$map_study; study_id <- if (is.null(chosen) || !nzchar(chosen)) NULL else chosen
    chosen_revision <- input$map_study_revision
    study_revision <- if (is.null(study_id) || is.null(chosen_revision) || identical(chosen_revision, "current")) NULL else suppressWarnings(as.numeric(chosen_revision))
    accepted <- brohn_curate_dataset(store, d$id, metadata, d$revision, study_id, study_revision)
    brohn_queue_multistream(store, accepted$id, accepted$revision)
    message("Source declaration saved. Stream preservation queued."); refresh()
  }))
  output$multistream_progress <- shiny::renderUI({selected_dataset(); brohn_interchange_progress_ui(snapshot()$jobs)})
  output$multistream_history <- shiny::renderUI({
    selected_dataset(); items <- snapshot()$imports
    if (!length(items)) return(NULL)
    choices <- stats::setNames(vapply(items, `[[`, character(1), "id"), vapply(items, function(r)
      paste("Source revision", r$body$dataset_revision, "\u00b7", r$created_at, "\u00b7", r$body$stream_count, "streams"), character(1)))
    selected <- shiny::isolate(input$multistream_import_id)
    if (is.null(selected) || !selected %in% unname(choices)) selected <- unname(choices[[1L]])
    shiny::selectInput("multistream_import_id", "Preserved version", choices, selected)
  })
  output$multistream_catalog <- shiny::renderUI({
    imported <- selected_import(); records <- brohn_streams(store, import_id = imported$id)
    shiny::req(length(records) > 0L)
    choices <- stats::setNames(vapply(records, `[[`, character(1), "id"), vapply(records, function(r)
      paste(r$body$source_index, r$body$title, "\u00b7", r$body$manifest$kind, "\u00b7", r$body$manifest$sample_count, "rows"), character(1)))
    selected <- shiny::isolate(input$multistream_stream_id)
    if (is.null(selected) || !selected %in% unname(choices)) selected <- unname(choices[[1L]])
    shiny::tagList(brohn_interchange_summary_ui(imported), shiny::selectInput("multistream_stream_id", "Stream to inspect", choices, selected))
  })
  output$multistream_stream_detail <- shiny::renderUI({
    record <- selected_stream()
    shiny::tagList(brohn_interchange_stream_ui(record), if (!is.null(record)) brohn_stream_curation_ui(record))
  })
  output$multistream_original <- shiny::downloadHandler(filename = function() basename(selected_dataset()$body$source$filename),
    content = function(file) prepare_download(function() brohn_copy_object_download(store, selected_dataset()$body$source$hash, file)))
  output$multistream_manifest <- shiny::downloadHandler(filename = function() paste0(selected_import()$id, ".json"),
    content = function(file) prepare_download(function() brohn_copy_object_download(store, selected_import()$body$result_object$hash, file)), contentType = "application/json")
  output$multistream_container <- shiny::downloadHandler(filename = function() paste0(selected_import()$id, "-recording-evidence.json"),
    content = function(file) prepare_download(function() brohn_copy_object_download(store, selected_import()$body$manifest$container$evidence_artifact$hash, file)), contentType = "application/json")
  for (kind in c(jsonl = "stream_samples_jsonl", csv = "stream_samples_csv", evidence = "stream_evidence_jsonl")) local({
    artifact_kind <- kind; suffix <- if (kind == "stream_samples_csv") "csv" else if (kind == "stream_samples_jsonl") "jsonl" else "evidence"
    output[[paste0("multistream_", suffix)]] <- shiny::downloadHandler(
      filename = function() paste0(selected_stream()$id, "-", suffix, if (suffix == "csv") ".csv" else ".jsonl"),
      content = function(file) prepare_download(function() brohn_download_stream_artifact(store, selected_stream()$id, artifact_kind, file)),
      contentType = if (suffix == "csv") "text/csv" else "application/x-ndjson")
  })
  invisible(NULL)
}
