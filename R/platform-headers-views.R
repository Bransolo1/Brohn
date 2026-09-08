brohn_native_header_ui <- function(store, record) {
  if (!record$body$source$format %in% brohn_header_formats()) return(NULL)
  shiny::tagList(brohn_card(title = "Read the recording header", subtitle = "Inspect the source's channel names, units, rates and annotations before choosing an analysis mapping.",
    brohn_command("Inspect recording header", "inspect_native_header", list(dataset_id = record$id, revision = record$revision, source_hash = record$body$source$hash)),
    shiny::p(class = "brohn-muted", "Inspection runs in the background. The original recording remains unchanged.")),
    shiny::uiOutput("native_header_progress"), shiny::uiOutput("native_header_review"),
    shiny::numericInput("map_sampling_rate", "Declared sampling rate (Hz; optional until confirmed)",
      brohn_default(record$body$metadata$sampling_rate, NA_real_), min = 1e-9, max = 1e7))
}

brohn_header_review_ui <- function(record, dataset) {
  result <- record$body$inspection; h <- result$header
  names <- vapply(h$channels, `[[`, character(1), "name")
  rows <- lapply(h$channels, function(c) list(name = c$name, type = c$type, source_unit = c$source_unit,
    analysis_unit = c$analysis_unit, sampling_rate_hz = c$sampling_rate_hz, sample_count = c$sample_count, marked_bad = c$marked_bad))
  selected <- unlist(dataset$body$metadata$value_columns, use.names = FALSE)
  if (is.null(selected)) selected <- character()
  selected <- intersect(selected, names)
  audio <- result$source$format == "wav"
  if (audio) {
    channel <- brohn_default(dataset$body$metadata$channel_index, 0)
    selected <- names[min(length(names), max(1, channel+1))]
  }
  brohn_card(title = "Header ready for review", subtitle = paste(h$channel_count, "channels", "\u00b7", result$source$format, "\u00b7", "source revision", record$body$dataset_revision),
    shiny::div(class = "brohn-toolbar", brohn_badge(if (result$status == "needs_attention") "Check source details" else "Header inspected"),
      shiny::downloadButton("native_header_download", "Download header inspection", icon = NULL)),
    brohn_table(rows, maximum = 512L, label = "Native recording channels"),
    shiny::p(if (is.null(h$recording$sampling_rate_hz)) "This recording has no single native sampling rate. Select channels sharing a rate." else
      paste("Recording rate:", h$recording$sampling_rate_hz, "Hz.")),
    if (!is.null(h$recording$duration_s)) shiny::p(paste("Recorded duration:", format(signif(h$recording$duration_s,6),trim=TRUE), "seconds;", h$recording$duration_definition, ".")),
    if (length(h$warnings)) shiny::div(class = "brohn-alert brohn-alert-warning", shiny::tags$ul(lapply(h$warnings, shiny::tags$li))),
    if (!anyDuplicated(names)) shiny::tagList(
      shiny::div(style = "display:none", shiny::textInput("native_header_form_identity", NULL, paste(dataset$id, record$id, record$body$source_hash, sep = ":"))),
      shiny::selectInput("native_header_channels", if (audio) "Audio channel to use" else "Channels to use", stats::setNames(names,names), selected = selected, multiple = !audio),
      shiny::p("Confirm that the selected channels describe the intended measure and that the native unit policy matches the exporter. Source metadata alone does not identify participants or establish calibration."),
      shiny::actionButton("apply_native_header", "Confirm channels and units", class = "btn-primary")) else
      shiny::p("Duplicate source names need a reader-name mapping before this header can populate the analysis form."),
    shiny::tags$details(shiny::tags$summary("Annotations and recording metadata"),
      if (is.null(h$annotations$count)) shiny::p(h$annotations$status) else shiny::p(paste(length(h$annotations$preview), "of", h$annotations$count, "annotations shown. The full original remains available.")),
      brohn_table(h$annotations$preview, maximum = 100L, label = "Native annotation preview"),
      shiny::tags$pre(brohn_json(h$recording, TRUE)),
      shiny::tags$ul(lapply(result$limitations, shiny::tags$li))))
}

brohn_install_header_server <- function(input, output, session, store, state, attempt, refresh, message, prepare_download) {
  dataset <- shiny::reactive({
    state$refresh
    shiny::req(state$page == "dataset", state$dataset_id)
    record <- brohn_get_entity(store, "dataset", state$dataset_id)
    shiny::req(!is.null(record), record$body$source$format %in% brohn_header_formats())
    record
  })
  snapshot <- shiny::reactivePoll(2000, session,
    checkFunc = function() {
      if (!identical(state$page, "dataset") || is.null(state$dataset_id)) return(NULL)
      jobs <- brohn_list_jobs(store, request_filters = list(dataset_id = state$dataset_id), operation = "inspect_header")
      brohn_hash(list(state$dataset_id,lapply(jobs,function(j) list(j$id,j$status,j$updated_at)),lapply(brohn_header_inspections(store,state$dataset_id),function(r) list(r$id,r$revision))))
    },valueFunc = function() {
      d <- dataset()
      list(record = brohn_header_for_dataset(store,d),jobs = brohn_list_jobs(store, request_filters = list(dataset_id = d$id), operation = "inspect_header"))
    })
  inspected <- shiny::reactive({r <- snapshot()$record; shiny::req(!is.null(r)); r})
  shiny::observeEvent(input$inspect_native_header, attempt(function() {
    command <- input$inspect_native_header; d <- dataset()
    brohn_require(is.list(command) && identical(command$dataset_id,d$id) && identical(command$source_hash,d$body$source$hash) &&
      identical(as.numeric(command$revision),as.numeric(d$revision)),"This source changed. Reopen it before inspecting its header.")
    brohn_queue_header_inspection(store,d$id,d$revision)
    message("Header inspection queued. Your recording and current form are retained.")
  }))
  shiny::observeEvent(input$apply_native_header, attempt(function() {
    d <- dataset(); r <- snapshot()$record
    brohn_require(!is.null(r), "Inspect this recording before confirming its channels; the previous header belongs to another source.")
    brohn_require(identical(input$native_header_form_identity,paste(d$id,r$id,r$body$source_hash,sep=":")),"This header belongs to another source or an earlier view. Reopen the recording before confirming channels.")
    selected <- brohn_default(input$native_header_channels,character())
    brohn_require(length(selected)>0L,"Choose the channels to use from the inspected header.")
    defaults <- brohn_header_mapping_defaults(r,selected)
    audio <- d$body$source$format == "wav"
    if (audio) {
      brohn_require(length(selected)==1L,"Choose one audio channel for this recipe.")
      channel <- Filter(function(c) identical(c$name,selected[[1L]]),r$body$inspection$header$channels)[[1L]]
      shiny::updateNumericInput(session,"map_audio_channel",value=channel$index)
    } else {
      shiny::updateTextInput(session,"map_native_values",value=brohn_native_channel_input_text(selected))
    }
    shiny::updateTextInput(session,"map_unit",value=defaults$unit)
    if (!is.null(defaults$sampling_rate)) shiny::updateNumericInput(session,"map_sampling_rate",value=defaults$sampling_rate)
    message("Selected channels, sampling rate and native unit policy copied to the mapping form. Add collection notes, then confirm the analysis mapping.")
  }))
  output$native_header_progress <- shiny::renderUI({
    dataset(); jobs <- snapshot()$jobs
    if (!length(jobs)) return(NULL)
    brohn_card(title="Header inspection progress",lapply(head(jobs,3L),function(job) shiny::div(class="brohn-stack",
      shiny::div(class="brohn-toolbar",brohn_badge(switch(job$status,succeeded="Header saved",running="Reading header",queued="Queued",job$status),
        if(job$status=="failed") "error" else if(job$status=="succeeded") "success" else "neutral"),shiny::span(job$updated_at)),
      if(!is.null(job$error)) shiny::p(job$error$message),
      if(job$status %in% c("queued","running")) brohn_command("Cancel inspection","cancel_processing",job$id),
      if(job$status %in% c("failed","cancelled")) brohn_command("Retry saved source","retry_processing",job$id))))
  })
  output$native_header_review <- shiny::renderUI(brohn_header_review_ui(inspected(),dataset()))
  output$native_header_download <- shiny::downloadHandler(filename=function() paste0(inspected()$id,".json"),
    content=function(file) prepare_download(function() brohn_copy_object_download(store,inspected()$body$result_object$hash,file)),contentType="application/json")
  invisible(NULL)
}
