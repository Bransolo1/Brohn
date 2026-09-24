brohn_camera_plan_ui <- function(design) {
  p <- design$camera
  brohn_card(title = "Camera and microphone", subtitle = "Optional session recording can be linked to the same study, responses and source history.",
    shiny::p(if (is.null(p)) "This design does not request camera recording." else paste(
      if (isTRUE(p$required)) "Recording is required for this study." else "Participants can choose to continue without recording.",
      if (isTRUE(p$audio)) "The microphone is included." else "The microphone is disabled.",
      if (identical(p$analysis_profile, "face_geometry_v1")) "Supported recordings from completed sessions automatically enter local face geometry processing." else
        if(identical(p$analysis_profile,"facial_au_expression_pyfeat_v1"))"Eligible completed recordings automatically receive local facial action-unit and native category scores for the selected window and stride."else "Recordings are retained for researcher review.")),
    if (!is.null(p)) shiny::p(class = "brohn-muted", paste("Up to", p$width, "by", p$height, "pixels at", p$frame_rate, "frames per second;", p$max_duration_s, "seconds maximum.")),
    if(identical(p$schema,"brohn-camera-policy/1.1"))shiny::p(paste("Facial window:",p$analysis_settings$start_s,"to",brohn_default(p$analysis_settings$end_s,"video end"),"seconds after the first video timestamp; every",p$analysis_settings$frame_stride,"frame(s). Setup lead-in is included.")),
    shiny::p(if (is.null(design$participant_equipment)) "Participant equipment preflight is not enabled for this design." else
      "Equipment checks follow the frozen camera and task requirements. They check transport and input, not physical timing, image, speech or gaze quality."),
    brohn_command("Set up camera recording", "edit_camera_policy", design$id),
    brohn_command("Set up participant equipment checks", "edit_camera_policy", design$id))
}
brohn_install_camera_plan_ui <- function(input, output, session, current, state, capture, attempt, update_study, message) {
  draft <- new.env(parent = emptyenv()); draft$active <- NULL
  output$camera_policy_facial_budget<-shiny::renderUI({
    shiny::req(identical(input$camera_policy_analysis,"facial_au_expression_pyfeat_v1"))
    start<-trimws(brohn_default(input$camera_policy_facial_start,""));end<-trimws(brohn_default(input$camera_policy_facial_end,""))
    if(!.brohn_facial_decimal(start)||nzchar(end)&&!.brohn_facial_decimal(end)||!brohn_number(input$camera_policy_rate,1,60)||
      !brohn_number(input$camera_policy_duration,1,600)||!brohn_number(input$camera_policy_facial_stride,1,120,TRUE)||!brohn_number(input$camera_policy_facial_gap,.001,10))
      return(shiny::p(role="status","Enter supported decimal window, recording limits, stride and support-gap settings to see the processing estimate."))
    p<-list(frame_rate=input$camera_policy_rate,max_duration_s=input$camera_policy_duration,analysis_settings=brohn_camera_analysis_settings(start,if(nzchar(end))end else NULL,input$camera_policy_facial_stride,input$camera_policy_facial_gap))
    b<-brohn_camera_analysis_budget(p)
    shiny::div(role="status",shiny::p(paste("Estimated maximum:",b$conservative_selected_frames,"analysed frames (limit 300). Actual encoded timestamps determine final support.")),
      if(b$conservative_selected_frames>300)shiny::p("Shorten the explicit video window or increase its frame stride before saving."),
      if(!b$nominal_interval_supported)shiny::p("The nominal sampling interval exceeds your support gap. Frame means may be available while adjacent-time averages have no support."))
  })
  shiny::observeEvent(input$edit_camera_policy, attempt(function() {
    capture(); brohn_require(!is.null(current$study), "Choose an editable study first."); d <- current$study$body
    brohn_require(identical(state$page, "study") && identical(input$edit_camera_policy, d$id) && !isTRUE(d$archived), "Open a current editable study to set up recording.")
    id <- brohn_id("camera-policy"); draft$active <- list(id = id, study_id = d$id, hash = brohn_hash(d))
    p <- brohn_default(d$camera, list(required = FALSE, audio = FALSE, consent_text = "This study records your camera video while you take part. Recording is stored with your participant session for the research described in the study information.",
      retention_text = "", width = 640L, height = 480L, frame_rate = 15, max_duration_s = 300, max_bytes = 64*1024^2, analysis_profile = "face_geometry_v1"))
    shiny::showModal(shiny::modalDialog(title = "Set up session recording", size = "l", easyClose = FALSE,
      shiny::tags$input(id = "camera_policy_form", type = "text", class = "shiny-input-text", value = id, style = "display:none", `aria-hidden` = "true", tabindex = "-1"),
      shiny::checkboxInput("camera_policy_enabled", "Request camera recording in this study", !is.null(d$camera)),
      shiny::checkboxInput("participant_equipment_enabled", "Check requested camera recording and required task keys before the study", !is.null(d$participant_equipment)),
      shiny::conditionalPanel("input.participant_equipment_enabled", shiny::checkboxInput("participant_equipment_controls", "Also offer a practice response control for questionnaires and choices", isTRUE(d$participant_equipment$controls))),
      shiny::p(class = "brohn-muted", "Only requested equipment is checked. The consented camera recording includes its setup lead-in. Checks do not establish scientific signal quality."),
      shiny::tags$details(shiny::tags$summary("Check details"), shiny::p("Microphone input is checked only when requested below. Current observations use a 2-second freshness window; the first recording-write check waits 15 seconds before offering retry. These are engineering settings, not scientific signal thresholds. Required task keys are checked once per browser page; existing timed focus guards remain active.")),
      shiny::conditionalPanel("input.camera_policy_enabled",
        shiny::checkboxInput("camera_policy_required", "Recording is required to complete this study", p$required),
        shiny::checkboxInput("camera_policy_audio", "Include the microphone", p$audio),
        shiny::textAreaInput("camera_policy_consent", "Explain the recording to participants", p$consent_text, rows = 3, width = "100%"),
        shiny::textAreaInput("camera_policy_retention", "Explain storage, access and retention to participants", p$retention_text, rows = 3, width = "100%",
          placeholder = "Describe who can access these recordings, where they are stored, how long they are retained and how participants can contact the researcher."),
        shiny::selectInput("camera_policy_analysis", "After a completed recording", c("Automatically process local face geometry" = "face_geometry_v1", "Automatically process local facial action units and categories"="facial_au_expression_pyfeat_v1", "Keep the recording for review" = "none"), p$analysis_profile),
        shiny::conditionalPanel("input.camera_policy_analysis === 'face_geometry_v1'",shiny::p("The local model reports face landmarks and native blendshape outputs. These are not automatically interpreted as emotions, calibrated gaze or attention.")),
        shiny::conditionalPanel("input.camera_policy_analysis === 'facial_au_expression_pyfeat_v1'",
          shiny::p("The optional local Py-Feat profile keeps native model scores. Identity recognition, gaze and pose estimation are disabled; its category labels do not establish feelings, attention or liking."),
          brohn_camera_facial_setup_ui(),
          shiny::div(class="brohn-form-grid",
            shiny::textInput("camera_policy_facial_start","Facial window start after first video timestamp (decimal seconds)",brohn_default(p$analysis_settings$start_s,"0")),
            shiny::textInput("camera_policy_facial_end","Facial window end (blank for video end)",brohn_default(p$analysis_settings$end_s,if(identical(p$schema,"brohn-camera-policy/1.1"))""else "10")),
            shiny::numericInput("camera_policy_facial_stride","Analyse every Nth recorded frame",brohn_default(p$analysis_settings$frame_stride,5),1,120,1),
            shiny::numericInput("camera_policy_facial_gap","Largest supported facial frame interval (seconds)",brohn_default(p$analysis_settings$max_support_gap_s,.5),.001,10)),
          shiny::p("The window is measured from the recording's first presentation timestamp and includes camera setup before stimuli. It does not establish frame alignment to a stimulus. Choose an explicit bounded window or stride; 2 to 300 selected frames are supported."),
          shiny::uiOutput("camera_policy_facial_budget"),
          shiny::tags$details(shiny::tags$summary("Named processing notice shown with the camera agreement"),shiny::p(brohn_camera_analysis_notice()))),
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
        max_duration_s = input$camera_policy_duration, max_bytes = input$camera_policy_size*1024^2, analysis_profile = if(identical(input$camera_policy_analysis,"facial_au_expression_pyfeat_v1"))"none"else input$camera_policy_analysis)
      if(identical(input$camera_policy_analysis,"facial_au_expression_pyfeat_v1")) {
        end<-trimws(brohn_default(input$camera_policy_facial_end,""))
        p<-brohn_camera_analysis_policy(p,brohn_camera_analysis_settings(trimws(brohn_default(input$camera_policy_facial_start,"")),if(nzchar(end))end else NULL,input$camera_policy_facial_stride,input$camera_policy_facial_gap))
      }
      brohn_validate_camera_policy(p); d$camera <- p
    } else d$camera <- NULL
    brohn_require(.brohn_camera_flag(input$participant_equipment_enabled) && .brohn_camera_flag(input$participant_equipment_controls), "Wait for the participant equipment fields to finish loading.")
    d$participant_equipment <- if (isTRUE(input$participant_equipment_enabled)) brohn_participant_equipment_policy(isTRUE(input$participant_equipment_controls)) else NULL
    update_study(d); draft$active <- NULL; shiny::removeModal(); message("Recording and equipment settings saved with this design revision.")
  }))
  shiny::observeEvent(input$cancel_camera_policy, attempt(function() {
    brohn_require(!is.null(draft$active) && is.list(input$cancel_camera_policy) && identical(input$cancel_camera_policy$editor_id, draft$active$id), "Choose the current recording setup's Cancel button.")
    draft$active <- NULL; shiny::removeModal(); message("Recording setup changes discarded.")
  }))
  invisible(list(context = function() draft$active))
}
brohn_camera_facial_setup_ui <- function() {
  paths<-c(Sys.getenv("BROHN_PYTHON_FACIAL_AU"),Sys.getenv("BROHN_FACIAL_MODEL_DIR"),Sys.getenv("BROHN_FACIAL_FFMPEG_DIR"))
  configured<-length(paths)==3L&&all(nzchar(paths))&&all(file.exists(paths))
  shiny::tagList(brohn_badge(if(configured)"Optional facial installation configured"else "Optional facial processing needs setup",if(configured)"neutral"else "warning"),
    shiny::p(if(configured)"The worker verifies pinned models, FFmpeg files, Py-Feat sources and dependency versions before processing."else "Configure the optional facial-au environment, pinned models and shared FFmpeg before analysis. Recording and participant receipts remain saved if this optional processing needs attention."))
}
brohn_camera_authority_ui <- function(authority)brohn_card(title="Camera processing permission",
  shiny::p(if(identical(authority$permission_kind,"original_named_participant"))"Original participant agreement covers the named local facial processing and frozen settings."else "This analysis uses a separate researcher-documented permission statement. It does not replace or rename the original participant camera agreement."),
  shiny::p(paste("Original participant outcome:",gsub("_"," ",authority$original_run_outcome),"; recording outcome:",authority$recording_outcome,".")),
  if(!is.null(authority$review_evidence))shiny::p(authority$review_evidence),
  shiny::tags$details(shiny::tags$summary("Exact original permission and source references"),shiny::p(authority$statement),shiny::tags$pre(brohn_json(authority,TRUE))))

brohn_participant_equipment_evidence_ui <- function(model) {
  required <- if (is.null(model$requirements)) character() else c(if (isTRUE(model$requirements$camera)) "camera recording", if (length(model$requirements$required_codes)) "required task keys", if (isTRUE(model$requirements$controls)) "native response control")
  shiny::tags$details(shiny::tags$summary("Participant equipment check evidence"),
    shiny::p(model$interpretation),
    if (is.null(model$policy)) shiny::p("Not collected by this release.") else shiny::tagList(
      shiny::p(if (!length(required)) "This release has no applicable equipment checks." else paste("Required checks:", paste(required, collapse = ", "), ".")),
      shiny::p(if (length(required) && !length(model$checks)) "No equipment check receipt has been collected for this session." else paste(length(model$checks), "saved check results. These are historical observations, not current device approval.")),
      lapply(model$checks, function(e) shiny::div(class = "brohn-card",
        shiny::h3(switch(e$payload$kind, camera = "Camera recording check", camera_declined = "Optional camera declined", keyboard = "Required task keys checked", controls = "Practice response control checked")),
        shiny::p(paste("Journal sequence", e$sequence, "\u00b7 browser time", e$clock$value, "ms \u00b7 page", e$clock$instance_id)),
        if (e$payload$kind == "camera") shiny::p(paste(e$payload$evidence$video$frames, "observed frame callbacks;",
          e$payload$evidence$recording$browser_bytes, "browser-committed bytes;", e$payload$evidence$recording$acked_bytes, "receiver-acknowledged bytes. Image, speech and gaze quality unknown.")),
        if (e$payload$kind == "camera") shiny::p(if (!isTRUE(e$payload$evidence$audio$requested)) "Microphone was not requested." else paste("Microphone:", e$payload$evidence$audio$blocks,
          "observed input blocks;", e$payload$evidence$audio$samples, "channel samples;", e$payload$evidence$audio$sample_rate, "Hz processing context. Speech quality unknown.")),
        if (e$payload$kind == "keyboard") shiny::p(paste("Observed and released:", paste(unlist(e$payload$evidence$codes), collapse = ", "), ". Physical input latency unknown.")),
        if (e$payload$kind == "controls") shiny::p(paste("Observed activation:", gsub("_", " ", e$payload$evidence$activation, fixed = TRUE), ". This does not establish input latency or physical device identity.")),
        shiny::tags$details(shiny::tags$summary("Exact saved check"), shiny::tags$pre(style = "white-space:pre-wrap;overflow-wrap:anywhere", brohn_json(e, TRUE)))))),
    shiny::downloadButton("run_equipment_download", "Download equipment evidence JSON", icon = NULL))
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
  facial_jobs<-if(!is.null(publication)&&identical(capture$start$policy$schema,"brohn-camera-policy/1.1"))
    brohn_list_jobs(store,request_filters=list(dataset_id=publication$body$dataset_id),operation="analyse_dataset")else list()
  shiny::tagList(brohn_badge(brohn_default(unname(labels[capture$status]), capture$status),
    if (capture$status %in% c("interrupted", "withdrawn", "unavailable")) "warning" else "neutral"),
    if (capture$status %in% c("declined", "unavailable")) shiny::p(if (isTRUE(camera$required)) "Required recording was not supplied." else "Explicit decision retained; recording was optional.") else
      shiny::p(paste(capture$acked_sequence, "chunks received;", format(capture$total_bytes, big.mark = ",", scientific = FALSE), "bytes")),
    if (length(jobs) && is.null(publication)) shiny::tagList(shiny::p(paste("Video preparation:", jobs[[1L]]$status)),
      if (!is.null(jobs[[1L]]$error)) shiny::p(jobs[[1L]]$error$message),
      if (jobs[[1L]]$status %in% c("failed", "cancelled")) brohn_command("Retry video preparation", "retry_processing", jobs[[1L]]$id)),
    if (!is.null(publication)) shiny::tagList(shiny::p(if (isTRUE(publication$body$assembly$decoder$supported)) "Video decoding and timestamp checks passed." else "Original bytes retained; video support needs review."),
      brohn_command("Open camera dataset", "open_dataset", publication$body$dataset_id)),
    if(length(facial_jobs))shiny::tagList(shiny::p(paste("Facial processing:",facial_jobs[[1L]]$status)),
      if(!is.null(facial_jobs[[1L]]$error))shiny::p(facial_jobs[[1L]]$error$message),
      if(facial_jobs[[1L]]$status%in%c("failed","cancelled"))brohn_command("Retry saved facial processing","retry_processing",facial_jobs[[1L]]$id),
      if(identical(facial_jobs[[1L]]$status,"succeeded"))brohn_command("Open facial report","open_report",facial_jobs[[1L]]$result$report_id))else
        if(!is.null(publication)&&identical(capture$start$policy$schema,"brohn-camera-policy/1.1"))shiny::p("Automatic facial processing waits for the original completed session and a supported complete recording."),
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
    if(identical(p$capture_policy$schema,"brohn-camera-policy/1.1"))shiny::tagList(
      shiny::p("The original policy requested named local facial processing. Its immutable recording-start receipt retains the participant's decision; eligible completed sources use the frozen window and stride automatically."),
      shiny::p(p$capture_policy$analysis_notice))else
        if(brohn_is_facial_profile(record$body$metadata))shiny::p("Facial processing of this older camera recording requires separately documented permission. Its original recording or geometry agreement is preserved."),
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
