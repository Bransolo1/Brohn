brohn_camera_plan_ui <- function(design) {
  p <- design$camera
  brohn_card(title = "Camera and microphone", subtitle = "Optional session recording can be linked to the same study, responses and source history.",
    shiny::p(if (is.null(p)) "This design does not request camera recording." else paste(
      if (isTRUE(p$required)) "Recording is required for this study." else "Participants can choose to continue without recording.",
      if (isTRUE(p$audio)) "The microphone is included." else "The microphone is disabled.",
      if (identical(p$analysis_profile, "face_geometry_v1")) "Supported recordings from completed sessions automatically enter local face geometry processing." else "Recordings are retained for researcher review.")),
    if (!is.null(p)) shiny::p(class = "brohn-muted", paste("Up to", p$width, "by", p$height, "pixels at", p$frame_rate, "frames per second;", p$max_duration_s, "seconds maximum.")),
    brohn_command("Set up camera recording", "edit_camera_policy", design$id))
}
brohn_install_camera_plan_ui <- function(input, output, session, current, state, capture, attempt, update_study, message) {
  draft <- new.env(parent = emptyenv()); draft$active <- NULL
  shiny::observeEvent(input$edit_camera_policy, attempt(function() {
    capture(); brohn_require(!is.null(current$study), "Choose an editable study first."); d <- current$study$body
    brohn_require(identical(state$page, "study") && identical(input$edit_camera_policy, d$id) && !isTRUE(d$archived), "Open a current editable study to set up recording.")
    id <- brohn_id("camera-policy"); draft$active <- list(id = id, study_id = d$id, hash = brohn_hash(d))
    p <- brohn_default(d$camera, list(required = FALSE, audio = FALSE, consent_text = "This study records your camera video while you take part. Recording is stored with your participant session for the research described in the study information.",
      retention_text = "", width = 640L, height = 480L, frame_rate = 15, max_duration_s = 300, max_bytes = 64*1024^2, analysis_profile = "face_geometry_v1"))
    shiny::showModal(shiny::modalDialog(title = "Set up session recording", size = "l", easyClose = FALSE,
      shiny::tags$input(id = "camera_policy_form", type = "text", class = "shiny-input-text", value = id, style = "display:none", `aria-hidden` = "true", tabindex = "-1"),
      shiny::checkboxInput("camera_policy_enabled", "Request camera recording in this study", !is.null(d$camera)),
      shiny::conditionalPanel("input.camera_policy_enabled",
        shiny::checkboxInput("camera_policy_required", "Recording is required to complete this study", p$required),
        shiny::checkboxInput("camera_policy_audio", "Include the microphone", p$audio),
        shiny::textAreaInput("camera_policy_consent", "Explain the recording to participants", p$consent_text, rows = 3, width = "100%"),
        shiny::textAreaInput("camera_policy_retention", "Explain storage, access and retention to participants", p$retention_text, rows = 3, width = "100%",
          placeholder = "Describe who can access these recordings, where they are stored, how long they are retained and how participants can contact the researcher."),
        shiny::selectInput("camera_policy_analysis", "After a completed recording", c("Automatically process local face geometry" = "face_geometry_v1", "Keep the recording for review" = "none"), p$analysis_profile),
        shiny::p("The local model reports face landmarks and native blendshape outputs. These are not automatically interpreted as emotions, calibrated gaze or attention."),
        shiny::tags$details(shiny::tags$summary("Recording limits"),
          shiny::div(class = "brohn-form-grid",
            shiny::numericInput("camera_policy_width", "Maximum video width (pixels)", p$width, 160, 1920, 1),
            shiny::numericInput("camera_policy_height", "Maximum video height (pixels)", p$height, 120, 1080, 1),
            shiny::numericInput("camera_policy_rate", "Maximum frame rate (Hz)", p$frame_rate, 1, 60, 1),
            shiny::numericInput("camera_policy_duration", "Maximum recording duration (seconds)", p$max_duration_s, 1, 600, 1),
            shiny::numericInput("camera_policy_size", "Maximum recording size (MiB)", p$max_bytes/1024^2, 1/1024, 128, 1)),
          shiny::p("Allow time for instructions and questions as well as stimuli. Reaching a recording limit interrupts the session; a partial recording is retained with that outcome.")),
        shiny::p(class = "brohn-muted", "Participants see a separate camera agreement and positioning step before timed stimuli. The current local profile uses WebM recording; device and browser support are checked during setup.")),
      footer = shiny::tagList(brohn_command("Cancel", "cancel_camera_policy", list(editor_id = id)),
        brohn_command("Save recording settings", "save_camera_policy", list(editor_id = id), "btn btn-primary"))))
  }))
  shiny::observeEvent(input$save_camera_policy, attempt(function() {
    a <- draft$active
    brohn_require(!is.null(a) && is.list(input$save_camera_policy) && identical(input$save_camera_policy$editor_id, a$id), "Choose the current recording setup's Save button.")
    capture(); d <- current$study$body
    brohn_require(!is.null(current$study) && !isTRUE(d$archived) && identical(input$camera_policy_form, a$id) && identical(state$page, "study") &&
      identical(a$study_id, d$id) && identical(a$hash, brohn_hash(d)), "This study changed while recording settings were open. Reopen the setup before saving.")
    brohn_require(.brohn_camera_flag(input$camera_policy_enabled), "Wait for the recording setup fields to finish loading.")
    if (isTRUE(input$camera_policy_enabled)) {
      brohn_require(.brohn_camera_flag(input$camera_policy_required) && .brohn_camera_flag(input$camera_policy_audio), "Choose the recording requirement and microphone setting.")
      p <- list(schema = "brohn-camera-policy/1.0", required = isTRUE(input$camera_policy_required), audio = isTRUE(input$camera_policy_audio),
        consent_text = input$camera_policy_consent, retention_text = input$camera_policy_retention,
        width = input$camera_policy_width, height = input$camera_policy_height, frame_rate = input$camera_policy_rate,
        max_duration_s = input$camera_policy_duration, max_bytes = input$camera_policy_size*1024^2, analysis_profile = input$camera_policy_analysis)
      brohn_validate_camera_policy(p); d$camera <- p
    } else d$camera <- NULL
    update_study(d); draft$active <- NULL; shiny::removeModal(); message("Recording settings saved with this design revision.")
  }))
  shiny::observeEvent(input$cancel_camera_policy, attempt(function() {
    brohn_require(!is.null(draft$active) && is.list(input$cancel_camera_policy) && identical(input$cancel_camera_policy$editor_id, draft$active$id), "Choose the current recording setup's Cancel button.")
    draft$active <- NULL; shiny::removeModal(); message("Recording setup changes discarded.")
  }))
  invisible(list(context = function() draft$active))
}

brohn_camera_session_ui <- function(store, run) {
  camera <- run$camera_policy_summary
  if (!is.null(camera)) {
    if (identical(camera$status, "unavailable")) return(shiny::span(class = "brohn-muted", "Camera setting unavailable. Open the assigned protocol to inspect it."))
    if (identical(camera$status, "not_requested")) return(shiny::span(class = "brohn-muted", "Not requested"))
    brohn_require(identical(camera$status, "requested"), "This camera metadata state is unsupported.")
  } else camera <- run$protocol$design$camera
  if (is.null(camera)) return(shiny::span(class = "brohn-muted", "Not requested"))
  capture <- brohn_capture(store, run_id = run$id)
  if (is.null(capture)) return(shiny::span("Awaiting camera decision"))
  labels <- c(recording = "Started; receiving chunks", declined = "Declined", unavailable = "Setup unavailable", completed = "Recording received", interrupted = "Interrupted recording", withdrawn = "Withdrawn recording")
  publication <- brohn_get_entity(store, "camera_capture", capture$id)
  jobs <- brohn_list_jobs(store, request_filters = list(capture_id = capture$id), operation = "assemble_capture")
  shiny::tagList(brohn_badge(brohn_default(unname(labels[capture$status]), capture$status),
    if (capture$status %in% c("interrupted", "withdrawn", "unavailable")) "warning" else "neutral"),
    if (capture$status %in% c("declined", "unavailable")) shiny::p(if (isTRUE(camera$required)) "Required recording was not supplied." else "Explicit decision retained; recording was optional.") else
      shiny::p(paste(capture$acked_sequence, "chunks received;", format(capture$total_bytes, big.mark = ",", scientific = FALSE), "bytes")),
    if (length(jobs) && is.null(publication)) shiny::tagList(shiny::p(paste("Video preparation:", jobs[[1L]]$status)),
      if (!is.null(jobs[[1L]]$error)) shiny::p(jobs[[1L]]$error$message),
      if (jobs[[1L]]$status %in% c("failed", "cancelled")) brohn_command("Retry video preparation", "retry_processing", jobs[[1L]]$id)),
    if (!is.null(publication)) shiny::tagList(shiny::p(if (isTRUE(publication$body$assembly$decoder$supported)) "Video decoding and timestamp checks passed." else "Original bytes retained; video support needs review."),
      brohn_command("Open camera dataset", "open_dataset", publication$body$dataset_id)),
    if (!is.null(capture$final$reason)) shiny::tags$details(shiny::tags$summary("Recording outcome details"), shiny::p(capture$final$reason)))
}

brohn_camera_dataset_ui <- function(store, record) {
  p <- record$body$source_provenance
  if (!identical(p$acquisition, "browser_camera")) return(NULL)
  labels <- c("camera-recording" = "Original camera recording (WebM)", "camera-observations" = "Chunk clocks and frame callbacks (JSONL)",
    "camera-decoded-frames" = "Decoded frames and native timestamps (JSON)", "camera-manifest" = "Capture and transfer manifest (JSON)")
  artifacts <- Filter(function(a) a$kind %in% names(labels), p$artifacts)
  values <- vapply(artifacts, function(a) brohn_json(list(dataset_id = record$id, revision = record$revision, source_hash = record$body$source$hash, kind = a$kind, hash = a$hash)), character(1))
  shiny::tagList(brohn_card(title = "Participant camera recording",
    shiny::p(paste("Run:", p$run_id, "\u00b7 participant code:", p$participant_id, "\u00b7 origin:", record$body$origin)),
    brohn_badge(paste("Recording outcome:", p$recording_outcome), if (p$recording_outcome == "completed") "neutral" else "warning"),
    shiny::p(if (isTRUE(p$container_complete_declared)) "All declared recorder chunks were received and the recorder reported a complete container." else "The original received bytes are retained as a partial recording; this file may not play."),
    shiny::p(if (isTRUE(p$decoder$supported)) "Saved video passed decoding, channel and timestamp support checks." else "Decoder support is incomplete or unavailable. Inspect the retained evidence before selecting an analysis."),
    shiny::p("Preview callback clocks do not establish encoded-frame alignment to study stimuli. Face geometry and native blendshapes do not automatically measure emotion, gaze or attention."),
    if (length(artifacts)) shiny::tagList(shiny::selectInput("camera_dataset_artifact", "Recording artifact", stats::setNames(values, vapply(artifacts, function(a) unname(labels[a$kind]), character(1))), values[[1L]]),
      shiny::downloadButton("camera_dataset_download", "Download recording artifact", icon = NULL)),
    shiny::tags$details(shiny::tags$summary("Frozen capture policy and source evidence"),
      shiny::p(paste("Capture:", p$capture_id)), shiny::p(paste("Design SHA-256:", p$design_hash)), shiny::p(paste("Protocol SHA-256:", p$protocol_hash)),
      brohn_table(list(p$decoder), maximum = 1L, label = "Saved video decoder evidence"),
      shiny::tags$pre(brohn_json(p$capture_policy, TRUE)))))
}

brohn_camera_dataset_artifact <- function(store, request, dataset_id) {
  brohn_fields(request, c("dataset_id", "revision", "source_hash", "kind", "hash"), label = "Camera artifact selection")
  brohn_require(identical(request$dataset_id, dataset_id), "Choose an artifact from the dataset currently open.")
  record <- brohn_get_entity(store, "dataset", dataset_id)
  brohn_require(!is.null(record) && identical(record$body$source_provenance$acquisition, "browser_camera") &&
    identical(as.numeric(record$revision), as.numeric(request$revision)) && identical(record$body$source$hash, request$source_hash),
    "The dataset changed. Choose its current recording artifact again.")
  artifacts <- Filter(function(a) identical(a$kind, request$kind) && identical(a$hash, request$hash), record$body$source_provenance$artifacts)
  brohn_require(length(artifacts) == 1L && artifacts[[1L]]$kind %in% c("camera-recording", "camera-observations", "camera-decoded-frames", "camera-manifest"),
    "The selected artifact does not belong to this camera recording.")
  brohn_object_path(store, artifacts[[1L]]$hash)
  artifacts[[1L]]
}

brohn_install_camera_artifact_ui <- function(input, output, session, store, state, prepare_download) {
  selected <- function() {
    brohn_require(identical(state$page, "dataset") && brohn_text(input$camera_dataset_artifact, 2000), "Open a camera dataset and choose its recording artifact.")
    brohn_camera_dataset_artifact(store, brohn_parse(input$camera_dataset_artifact, max_bytes = 2000), state$dataset_id)
  }
  output$camera_dataset_download <- shiny::downloadHandler(filename = function() {
    a <- selected(); paste0(a$kind, "-", substr(a$hash, 1, 12), switch(a$kind, "camera-recording" = ".webm", "camera-observations" = ".jsonl", ".json"))
  }, content = function(file) prepare_download(function() {a <- selected(); brohn_copy_object_download(store, a$hash, file)}))
  invisible(list(selected = selected))
}
