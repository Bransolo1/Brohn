brohn_plan_ui <- function(store, d) {
  choices <- stats::setNames(brohn_ids(d$conditions), vapply(d$conditions, function(c) c$label, character(1)))
  measure_choices <- c("Eye tracking" = "gaze", "Questionnaires" = "questionnaire", "EEG" = "eeg", "EDA" = "eda", "ECG / HRV" = "ecg", "PPG" = "ppg", "Respiration" = "respiration", "Muscle activity" = "emg", "EOG" = "eog", "fNIRS" = "fnirs", "Temperature" = "temperature", "Movement" = "movement", "Webcam gaze" = "webcam_gaze", "Facial geometry" = "facial_geometry", "Facial expression" = "facial_expression", "Body pose" = "pose", "Voice" = "voice", "Reaction time" = "rt", "IAT" = "iat", "Brief IAT" = "biat", "Approach / avoidance" = "aat")
  shiny::tagList(
    brohn_guidance_plan_intro_ui(d),
    brohn_card(title = "What are you investigating?",
      shiny::textInput("study_title", "Study name", d$title),
      shiny::textAreaInput("study_description", "Research question and primary comparison", d$description, rows = 2),
      shiny::checkboxGroupInput("study_measures", "Measures in this study", measure_choices, selected = unlist(d$measures), inline = TRUE),
      shiny::p(class = "brohn-muted", "A selected measure describes study intent. Its data source and usable support are checked separately; selecting a sensor does not start recording.")),
    brohn_welcome_authoring_ui(store, d),
    brohn_card(title = "Conditions and controls", subtitle = "Name what you are comparing. A control condition is separate from a physiological baseline.",
      shiny::div(class = "brohn-form-grid", lapply(seq_along(d$conditions), function(i) shiny::div(
        shiny::textInput(paste0("condition_label_", i), paste("Condition", i), d$conditions[[i]]$label),
        shiny::selectInput(paste0("condition_role_", i), paste("Role for condition", i), c("Control" = "control", "Test" = "test", "Neutral comparator" = "neutral", "Other" = "other"), d$conditions[[i]]$role)))),
      shiny::actionButton("add_condition", "Add condition")),
    brohn_card(title = "Stimuli", subtitle = "Use the same viewing policy where the design requires it. Every image and area is versioned.",
      shiny::div(class = "brohn-grid", lapply(seq_along(d$stimuli), function(i) {
        s <- d$stimuli[[i]]
        inline_image <- s$type == "image" && !is.null(s$asset) && s$asset$media_type %in% c("image/png", "image/jpeg") && s$asset$size <= 5*1024^2
        area_ready <- inline_image && !is.null(s$asset$width) && !is.null(s$asset$height)
        shiny::div(class = "brohn-stimulus-card",
          if (inline_image) tryCatch(shiny::tags$img(src = brohn_asset_data_uri(store, s$asset), alt = brohn_material_description(s, "stimulus"), class = "brohn-stimulus-image"),
            error = function(e) shiny::p(class = "brohn-alert brohn-alert-warning", "The saved image is unavailable. Open its material editor to review or replace it.")) else
              shiny::div(class = "brohn-stimulus-placeholder", brohn_icon("study"), shiny::p(if (is.null(s$asset)) "Text or image stimulus" else paste("Saved", s$type, "material"))),
          shiny::textInput(paste0("stimulus_title_", i), paste("Stimulus", i, "name"), s$title),
          shiny::selectInput(paste0("stimulus_condition_", i), paste("Condition for stimulus", i), choices, s$condition_id),
          if (s$type == "text") shiny::textAreaInput(paste0("stimulus_text_", i), paste("Participant text for stimulus", i), s$content, rows = 2),
          shiny::numericInput(paste0("stimulus_duration_", i), paste("Viewing duration", i, "(milliseconds)"), s$duration_ms, min = 100, max = 3600000, step = 100),
          brohn_material_card_ui(d, "stimulus", s),
          shiny::div(class = "brohn-toolbar", if (area_ready) brohn_command("Define area", "edit_aoi", s$id),
            if (!is.null(s$asset) && identical(s$asset$media_type, "image/png")) brohn_command("Suggest area", "suggest_aoi", s$id)),
          if (length(s$aois)) shiny::tags$ul(lapply(s$aois, function(a) shiny::tags$li(paste(a$label, "\u00b7", round(100*a$width), "x", round(100*a$height), "%"),
            shiny::div(class = "brohn-toolbar", if (area_ready) brohn_command(paste("Edit", a$label), "edit_existing_aoi", list(stimulus_id = s$id, aoi_id = a$id)),
              brohn_command(paste("Remove", a$label), "remove_aoi", list(stimulus_id = s$id, aoi_id = a$id)))))))
      })), shiny::actionButton("add_stimulus", "Add stimulus")),
    shiny::uiOutput("aoi_proposals"),
    brohn_card(title = "Order and participant flow",
      shiny::div(class = "brohn-form-grid",
        shiny::selectInput("study_order", "Stimulus order", c("Counterbalanced rotation" = "counterbalanced", "Fixed" = "fixed", "Randomized per allocation" = "randomized"), d$order),
        shiny::numericInput("study_seed", "Reproducible design seed", d$seed, min = 1, max = .Machine$integer.max),
        shiny::numericInput("baseline_ms", "Baseline before each stimulus (ms; 0 disables)", d$baseline_ms, 0, 600000, 100),
        shiny::numericInput("fixation_ms", "Fixation cue before each stimulus (ms)", d$fixation_ms, 0, 600000, 100)),
      shiny::p(class = "brohn-muted", "These are declared presentation settings. Physiological recipes check whether their baseline and response windows have enough support."),
      shiny::h3("Information at each stage"),
      shiny::p(class = "brohn-muted", "Participants see the welcome page first when enabled, then the separate consent information. Instructions follow consent, and debrief appears after the session."),
      shiny::textAreaInput("study_instructions", "Instructions after consent", d$instructions, rows = 3),
      shiny::textAreaInput("consent_text", "Participant information and consent", d$consent$text, rows = 4),
      shiny::textAreaInput("debrief_text", "Debrief and contact information", d$debrief, rows = 3),
      shiny::tags$details(shiny::tags$summary("Participant appearance"),
        shiny::p("These colours belong to the frozen study. The researcher's dark theme does not change them."),
        shiny::textInput("participant_background", "Participant background colour", d$appearance$background),
        shiny::textInput("participant_foreground", "Participant text colour", d$appearance$foreground))),
    brohn_camera_plan_ui(d), brohn_analysis_plan_summary_ui(d))
}
brohn_question_assignment_ui <- function(design, question) {
  legacy <- !identical(question$option_assignment, "participant-sha256/1.0")
  shiny::tagList(
    if (isTRUE(question$randomize_options) && legacy) shiny::div(class = "brohn-alert",
      shiny::p("This older draft uses the same shuffled option order for every participant."),
      brohn_command("Use participant-specific order", "question_assignment_upgrade",
        list(study_id = design$id, question_id = question$id, question_hash = brohn_hash(question))),
      shiny::p(class = "brohn-muted", "Updates this draft question. Existing participant releases keep their saved assignment.")) else
      shiny::p(class = "brohn-muted", "Randomization assigns an option order to each participant and question occurrence. Resuming keeps that order; equal allocation across orders is not guaranteed."),
    if (identical(question$type, "rating")) shiny::p(class = "brohn-muted", "Keep ordered rating anchors in their saved order unless your protocol explicitly requires otherwise."))
}
brohn_questions_ui <- function(d) {
  types <- c("Rating" = "rating", "Single choice" = "single_choice", "Multiple choice" = "multiple_choice", "Dropdown" = "dropdown", "Short text" = "text", "Long text" = "long_text", "Number" = "number", "Slider" = "slider", "Matrix" = "matrix", "Ranking" = "ranking", "Point allocation" = "allocation", "Information" = "information")
  shiny::tagList(brohn_card(title = "Questions connected to the study", subtitle = "Place questions before the study, after each stimulus or at the end. Answers retain the right stimulus and condition.",
    shiny::div(class = "brohn-toolbar", shiny::selectInput("question_type", "Question type", types, selectize = FALSE), shiny::actionButton("add_question", "Add question", class = "btn-primary"))),
    brohn_question_sections_ui(d), brohn_question_revision_ui(d), brohn_scales_summary_ui(d),
    if (!length(d$questions)) brohn_empty("Add the participant's perspective", "Choose a question type above. Questions are optional when the research design does not need them."),
    lapply(seq_along(d$questions), function(i) {
      q <- d$questions[[i]]
      brohn_card(title = paste("Question", i), subtitle = names(types)[match(q$type, types)],
        actions = shiny::div(class = "brohn-toolbar", if (i > 1 && !"questionnaire_sections" %in% names(d)) brohn_command("Move up", "question_move", list(id = q$id, direction = -1)),
          if (i < length(d$questions) && !"questionnaire_sections" %in% names(d)) brohn_command("Move down", "question_move", list(id = q$id, direction = 1)), brohn_command("Remove", "remove_question", q$id)),
        shiny::textAreaInput(paste0("q_prompt_", i), paste("Question", i, "wording"), q$prompt, rows = 2),
        if (!"questionnaire_sections" %in% names(d)) shiny::selectInput(paste0("q_scope_", i), paste("Question", i, "placement"), c("Before stimuli" = "before", "After each stimulus" = "after_each", "End of study" = "end"), q$scope) else
          shiny::p(paste(.brohn_sections_label(q$scope), "\u00b7 Move this question with its group in Questionnaire sections.")),
        shiny::checkboxInput(paste0("q_required_", i), paste("Require an answer to question", i), q$required),
        if (q$type %in% c("rating", "single_choice", "multiple_choice", "dropdown", "matrix", "ranking", "allocation")) shiny::tagList(
          shiny::textAreaInput(paste0("q_options_", i), paste("Question", i, "options: label | code, one per line"),
            paste(vapply(q$options, function(o) paste(o$label, o$value, sep = " | "), character(1)), collapse = "\n"), rows = max(3, min(8, length(q$options)))),
          shiny::checkboxInput(paste0("q_random_", i), paste("Randomize question", i, "option order"), q$randomize_options),
          brohn_question_assignment_ui(d, q)),
        if (q$type == "matrix") shiny::textAreaInput(paste0("q_rows_", i), paste("Question", i, "statements, one per line"), paste(vapply(q$rows, function(r) r$label, character(1)), collapse = "\n")),
        if (q$type %in% c("number", "slider", "allocation")) shiny::div(class = "brohn-form-grid",
          shiny::numericInput(paste0("q_min_", i), paste("Question", i, "minimum"), q$min),
          shiny::numericInput(paste0("q_max_", i), paste("Question", i, if (q$type == "allocation") "points to distribute" else "maximum"), q$max),
          shiny::numericInput(paste0("q_step_", i), paste("Question", i, "step"), q$step, min = .000001)),
        brohn_question_logic_summary_ui(d, q))
    }))
}
brohn_collect_ui <- function(store, record) {
  issues <- brohn_design_issues(record$body, TRUE)
  deployments <- if (exists("brohn_deployments", mode = "function")) brohn_deployments(store, record$id) else list()
  port <- Sys.getenv("BROHN_PARTICIPANT_PORT", "3840")
  shiny::tagList(brohn_card(title = "Prepare and release", subtitle = "A release pins this design and its materials. Later edits do not change a participant's study.",
    if (length(issues)) shiny::div(class = "brohn-alert brohn-alert-warning", shiny::strong("Before starting"), shiny::p(issues)) else brohn_badge("Design checks passed", "success"),
    shiny::div(class = "brohn-form-grid", shiny::selectInput("release_origin", "Collection origin", c("Example walkthrough (sample)" = "sample", "Pilot / practice" = "pilot", "Live study" = "live"),
      if(identical(record$body$lineage$operation, "original_sample_design") || any(vapply(record$body$maxdiff,function(exercise)identical(exercise$origin,"synthetic"),logical(1)))) "sample" else "pilot"),
      shiny::numericInput("release_quota", "Maximum participant starts", 100, 1, 100000, 1)),
    shiny::checkboxInput("release_alias", "Require a researcher-issued participant code to link repeat sessions", FALSE),
    shiny::p(class = "brohn-muted", "Without participant codes, results describe sessions. Codes must follow your study's pseudonymous identity scheme."),
    shiny::p(class = "brohn-muted", "Example walkthroughs retain a sample label in sessions and reports. Use them to learn the software; choose pilot or live only after reviewing your research materials."),
    shiny::actionButton("publish_study", "Release participant study", class = "btn-primary"),
    shiny::p(class = "brohn-muted", "Local lab delivery. Browser onset observations are recorded; physical timing and named sensor support require their own evidence.")),
    brohn_collection_routes_ui(record$body),
    if (length(deployments)) lapply(deployments, function(d) {
      url <- paste0("http://127.0.0.1:", port, "/participant/?token=", d$token)
      brohn_card(title = paste("Release", substr(d$id, 1, 18)), subtitle = paste(d$origin, "\u00b7", "design revision", d$design_revision),
        brohn_badge(d$status, if (d$status == "open") "success" else "neutral"),
        shiny::div(class = "brohn-toolbar", shiny::tags$a(href = url, target = "_blank", rel = "noopener", class = "btn btn-primary", "Open participant study"),
          shiny::tags$button(type = "button", class = "btn btn-outline-secondary", `data-brohn-copy` = url, "Copy participant link")),
        shiny::p(class = "brohn-muted", "This loopback link works on this computer. It is not an internet recruitment link."),
        shiny::div(class = "brohn-toolbar", if (d$status == "open") brohn_command("Pause new starts", "deployment_command", list(id = d$id, state = "paused")),
          if (d$status == "paused") brohn_command("Resume new starts", "deployment_command", list(id = d$id, state = "open")),
          if (d$status %in% c("open", "paused")) brohn_command("Close recruitment", "deployment_command", list(id = d$id, state = "closed"))))
    }), brohn_acquisition_ui(store, record), brohn_import_ui(store, record$id), shiny::uiOutput("collection_sessions"))
}
brohn_sessions_ui <- function(store, study_id, state = NULL) {
  page <- brohn_search_runs(store, study_id, offset = brohn_related_offset(state, "study_runs", study_id))
  runs <- page$records
  brohn_card(title = "Participant sessions", brohn_related_page_ui(page), if (!length(runs)) shiny::p("Sessions will appear after participants enter a released study.") else
    shiny::div(class = "brohn-table", shiny::tags$table(shiny::tags$thead(shiny::tags$tr(lapply(c("Participant", "Origin", "Status", "Received", "Camera", "Assigned protocol"), function(label) shiny::tags$th(scope = "col", label)))),
      shiny::tags$tbody(lapply(runs, function(r) shiny::tags$tr(shiny::tags$td(brohn_default(r$participant_alias, r$id)), shiny::tags$td(r$origin),
        shiny::tags$td(paste(r$completion_status, r$transfer_status, sep = " / ")), shiny::tags$td(brohn_default(r$acked_sequence, 0)), shiny::tags$td(brohn_camera_session_ui(store, r)),
        shiny::tags$td(brohn_command("View assigned protocol", "view_run_protocol", list(run_id = r$id, study_id = study_id)))))))))
}
brohn_import_ui <- function(store, study_id = NULL) {
  brohn_card(title = "Import recorded data", subtitle = "Keep the original file, inspect its columns and confirm the mapping before analysis.",
    shiny::textInput("dataset_title", "Dataset name", "Recorded study data"),
    shiny::selectInput("dataset_origin", "Recording origin", c("Imported; collection type not yet classified" = "imported", "Pilot / practice recording" = "pilot", "Live study recording" = "live", "Synthetic example" = "sample"), "imported"),
    shiny::selectInput("dataset_modality", "Data family", c("Eye tracking" = "gaze", "EDA" = "eda", "EEG" = "eeg", "ECG / HRV" = "ecg", "PPG" = "ppg", "Respiration" = "respiration", "EMG" = "emg", "fNIRS" = "fnirs", "Questionnaire" = "questionnaire", "Best-worst choices (MaxDiff)" = "maxdiff", "Voice" = "audio", "Video / webcam recording" = "video", "Implicit / reaction-time trials" = "implicit", "Multistream recording (XDF / stream bundle)" = "multimodal", "Calibrated acceleration" = "movement", "EOG (retain source)" = "eog", "Calibrated temperature" = "temperature")),
    shiny::p("Choose your file, review its name, origin and destination, then import it. Brohn preserves the original in the background and opens the mapping when it is ready."),
    shiny::fileInput("dataset_upload", "Recording or data file", accept = paste0(".", names(brohn_dataset_formats()))),
    shiny::uiOutput("ingestion_upload_review"),
    shiny::p(class = "brohn-muted", "Original recording provenance is retained. An imported file is not automatically a qualified device recording."),
    shiny::uiOutput("ingestion_history"))
}
brohn_dataset_library_ui <- function(store, state) {
  shiny::tagList(brohn_page("Data library", "Curate once, retain the source and reuse a fixed dataset version.",
    brohn_import_ui(store), shiny::div(class = "brohn-form-grid", shiny::textInput("dataset_search", "Search datasets", placeholder = "Dataset name or source filename"),
      shiny::selectInput("dataset_filter", "Data family filter", c("All families" = "all", "Eye tracking" = "gaze", "EDA" = "eda", "EEG" = "eeg", "ECG" = "ecg", "PPG" = "ppg", "Respiration" = "respiration", "EMG" = "emg", "fNIRS" = "fnirs", "Questionnaire" = "questionnaire", "Best-worst choices (MaxDiff)" = "maxdiff", "Voice" = "audio", "Video" = "video", "Implicit / reaction-time trials" = "implicit", "Multistream" = "multimodal", "Calibrated temperature" = "temperature", "Calibrated acceleration" = "movement"))),
    shiny::uiOutput("dataset_catalog")))
}
brohn_review_ui <- function(store, record, state = NULL) {
  page <- brohn_search_related(store,"study_datasets",record$id,offset=brohn_related_offset(state,"study_datasets",record$id))
  datasets <- page$records
  brohn_card(title = "Review what needs your judgement", subtitle = "Missing or failed measures do not erase valid observations from other channels.",
    if (length(datasets)) lapply(datasets, function(d) shiny::div(class = "brohn-toolbar", shiny::strong(d$body$title), brohn_badge(d$body$status), brohn_command("Inspect dataset", "open_dataset", d$id))) else
      shiny::p("Collect a session or import data to begin review."), brohn_related_page_ui(page), brohn_sessions_ui(store, record$id, state))
}
brohn_results_ui <- function(store, record, state = NULL) {
  page <- brohn_search_related(store,"study_reports",record$id,offset=brohn_related_offset(state,"study_reports",record$id))
  reports <- page$records
  deployments <- brohn_deployments(store, record$id)
  shiny::tagList(if (length(reports)) brohn_card(title = "Bring measures together", subtitle = "Link reviewed participant identities across saved gaze, questionnaire and physiological reports.",
    brohn_command("Combine measures", "combine_measures", record$id, "btn btn-primary")),
    if (length(reports)) brohn_card(title = "Task results across participants", subtitle = "Review original administrations, participant identities and repeat-session weighting before creating a descriptive task summary.",
      brohn_command("Review task participants", "task_cohort_open", record$id)),
    if (length(deployments)) brohn_card(title = "Compare a release's completed sessions", subtitle = "Each report freezes its cohort. Pilot and live observations stay separate.",
    lapply(deployments, function(d) brohn_command(paste("Analyse", d$origin, "release", substr(d$id, nchar(d$id)-5, nchar(d$id))), "analyse_cohort", d$id))),
    if (!length(reports)) brohn_empty("Results follow the evidence", "A completed session or accepted dataset creates an analysis job. Results will retain the exact design and source versions.") else
    lapply(reports, function(r) brohn_card(title = brohn_default(r$body$title, "Study results"), subtitle = paste("Saved", r$created_at),
      brohn_badge(brohn_default(r$body$status, "Available")), brohn_command("Open report", "open_report", r$id, "btn btn-primary"))),brohn_related_page_ui(page))
}
brohn_history_ui <- function(store, record, state = NULL) {
  history <- brohn_entity_history(store, "study", record$id)
  migration_page <- brohn_search_related(store,"study_migrations",record$id,offset=brohn_related_offset(state,"study_migrations",record$id))
  migration <- migration_page$records
  shiny::tagList(brohn_card(title = "A study with a memory", subtitle = "Each saved design revision remains available. Archiving changes library organization, not your evidence.",
    shiny::actionButton("archive_study", if (isTRUE(record$body$archived)) "Restore to active studies" else "Archive study"),
    shiny::tags$ul(lapply(history, function(h) shiny::tags$li(paste("Revision", h$revision, "\u00b7", h$updated_at, "\u00b7", h$body$title),
      brohn_command(paste("Inspect revision", h$revision), "view_design_revision", list(id = h$id, revision = h$revision)))))),
    if (length(migration)) brohn_card(title = "Earlier Brohn artifacts", lapply(migration, function(m) shiny::tags$ul(lapply(m$body$artifacts, function(a) shiny::tags$li(paste(a$type, a$filename, "\u00b7", substr(a$object$hash, 1, 12)),
      brohn_command(paste("Inspect", a$filename), "inspect_legacy_artifact", list(migration_id = m$id, hash = a$object$hash))))))),
    if(migration_page$total) brohn_related_page_ui(migration_page),brohn_results_ui(store, record, state))
}
