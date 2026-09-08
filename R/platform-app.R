# Researcher commands and views. The participant application is served separately.
brohn_server <- function(input, output, session, store_root = brohn_workspace_path()) {
  store <- brohn_open_store(store_root); brohn_initialise_library(store)
  session$onSessionEnded(function() brohn_close_store(store))
  state <- shiny::reactiveValues(page = "home", stage = "Plan", refresh = 0L,
    error = NULL, status = "Workspace ready", study_id = NULL, dataset_id = NULL, report_id = NULL)
  current <- new.env(parent = emptyenv()); current$study <- NULL
  for (kind in c("study", "dataset", "template")) state[[paste0(kind, "_offset")]] <- 0L
  refresh <- function() state$refresh <- state$refresh + 1L
  attempt <- function(fn, clear_error = TRUE) { if (isTRUE(clear_error)) state$error <- NULL; tryCatch(fn(), error = function(e) {state$error <- conditionMessage(e); state$status <- "Needs attention"; NULL}) }
  prepare_download <- function(fn) tryCatch(fn(), error = function(e) {
    state$error <- conditionMessage(e); state$status <- "Download needs attention"
    shiny::showNotification(conditionMessage(e), type = "error", duration = NULL, session = session)
    stop(e)
  })
  output$platform_status <- shiny::renderText(state$status)
  output$service_health <- shiny::renderUI({
    shiny::invalidateLater(2000, session)
    services <- getOption("brohn.services")
    if (is.null(services)) return(NULL)
    affected <- Filter(function(s) !isTRUE(s$ready), services$snapshot)
    if (!length(affected)) return(NULL)
    shiny::div(class = "brohn-alert", role = "status", lapply(affected, function(s) shiny::p(
      if (s$status == "external_unavailable") "The collection service is unavailable. Reopen its local launcher before starting new sessions." else
      if (s$service == "participant") "The collection service is reconnecting. New sessions are temporarily unavailable; participants retain saved progress in their study browsers." else
        "The processing service is restarting. Saved source data and queued analyses are retained.")))
  })
  output$platform_error <- shiny::renderUI(if (!is.null(state$error)) shiny::div(class = "brohn-alert brohn-alert-error", role = "alert", shiny::strong("Please check this"), shiny::p(state$error)))
  message <- function(text) {state$status <- text; invisible(text)}
  brohn_install_multimodal_ui(input, output, session, store, state, current, attempt, message, refresh)
  brohn_install_task_cohort_ui(input, output, session, store, state, current, attempt, message, refresh)
  brohn_install_interchange_server(input, output, session, store, state, attempt, refresh, message, prepare_download)
  brohn_install_header_server(input, output, session, store, state, attempt, refresh, message, prepare_download)
  brohn_install_signal_server(input, output, session, store, state, attempt, message, prepare_download)
  brohn_install_neural_plots(input, output, session, store, state, attempt, message, prepare_download)
  brohn_install_gaze_report_server(input, output, session, store, state)
  brohn_install_acquisition_server(input, output, session, store, state, attempt, refresh, message, prepare_download)
  brohn_install_camera_artifact_ui(input, output, session, store, state, prepare_download)
  brohn_install_stream_curation_ui(input, output, session, store, state, attempt, message, refresh, prepare_download)
  brohn_install_maxdiff_import_ui(input,output,session,store,state)
  task_import_ui <- brohn_install_task_import_ui(input,output,session,store,state,attempt,message)
  brohn_install_ingestion_ui(input, output, session, store, state, current, attempt, refresh, message)
  brohn_install_run_protocol_ui(input, output, session, store, current, state, attempt, prepare_download)
  original_dataset <- function() {
    brohn_require(identical(state$page, "dataset"), "Open the source dataset before downloading its original file.")
    record <- brohn_get_entity(store, "dataset", state$dataset_id)
    brohn_require(!is.null(record) && identical(input$dataset_form_identity, paste(record$id, record$revision, sep = ":")),
      "The source dataset changed. Reopen its current record before downloading.")
    record$body
  }
  output$dataset_original_download <- shiny::downloadHandler(filename = function() basename(original_dataset()$source$filename),
    content = function(file) prepare_download(function() brohn_copy_object_download(store, original_dataset()$source$hash, file)))
  shiny::observe({
    # Updating only after the exact dataset form is bound keeps a delayed
    # selector response from linking the next dataset to the previous study.
    shiny::req(state$page == "dataset", state$dataset_id)
    identity <- if (!is.null(input$multistream_form_identity) && startsWith(input$multistream_form_identity, paste0(state$dataset_id, ":")))
      input$multistream_form_identity else input$dataset_form_identity
    record <- brohn_get_entity(store, "dataset", state$dataset_id)
    shiny::req(!is.null(record), identical(identity, paste(record$id, record$revision, sep = ":")))
    shiny::updateSelectizeInput(session, "map_study", choices = brohn_study_choices(store, record$project_id), selected = brohn_default(record$body$study_id, ""), server = TRUE)
  })
  select_study <- function(id, stage = "Plan") {
    current$study <- brohn_study(store, id); state$study_id <- current$study$id; state$page <- "study"; state$stage <- stage; state$error <- NULL
    if (isTRUE(current$study$body$archived)) state$stage <- "History"
    refresh(); session$sendCustomMessage("brohn-navigation", list(page = "studies", focus = TRUE))
    message(paste("Saved revision", current$study$revision))
  }
  update_study <- function(design, redraw = TRUE) {
    brohn_require(!isTRUE(current$study$body$archived), "Restore this study before editing its design.")
    saved <- brohn_save_study(store, design, current$study$revision)
    current$study <- saved; message(paste("Saved revision", saved$revision)); if (redraw) refresh(); invisible(saved)
  }
  value <- function(id, fallback) if (is.null(input[[id]])) fallback else input[[id]]
  options_from_text <- function(text, previous) {
    lines <- trimws(strsplit(text, "\n", fixed = TRUE)[[1L]]); lines <- lines[nzchar(lines)]
    lapply(seq_along(lines), function(i) {
      parts <- strsplit(lines[i], "|", fixed = TRUE)[[1L]]
      code <- if (length(parts) >= 2) trimws(parts[length(parts)]) else as.character(i)
      # Preserve imported typed codes when the researcher changes only labels.
      if (length(previous) >= i && identical(code, as.character(previous[[i]]$value))) code <- previous[[i]]$value else {
        numeric <- suppressWarnings(as.numeric(code))
        code <- if (identical(code, "true")) TRUE else if (identical(code, "false")) FALSE else if (!is.na(numeric) && nzchar(code)) numeric else code
      }
      list(id = if (length(previous) >= i) previous[[i]]$id else brohn_id("option"), label = trimws(parts[1]), value = code)
    })
  }
  capture <- function() {
    if (is.null(current$study) || state$page != "study") return(invisible(NULL))
    # Old Shiny input values can briefly survive navigation. They must never
    # overwrite another study or a different stage before its DOM is bound.
    if (!identical(input$study_form_identity, paste(current$study$id, state$stage, sep = ":"))) return(invisible(NULL))
    if (isTRUE(current$study$body$archived)) return(invisible(current$study))
    d <- current$study$body
    if (state$stage == "Plan") {
      d$title <- value("study_title", d$title); d$description <- value("study_description", d$description)
      d$order <- value("study_order", d$order); d$seed <- value("study_seed", d$seed)
      d$baseline_ms <- value("baseline_ms", d$baseline_ms); d$fixation_ms <- value("fixation_ms", d$fixation_ms)
      d$instructions <- value("study_instructions", d$instructions)
      d$consent$text <- value("consent_text", d$consent$text); d$debrief <- value("debrief_text", d$debrief)
      d$appearance$background <- value("participant_background", d$appearance$background)
      d$appearance$foreground <- value("participant_foreground", d$appearance$foreground)
      if (!is.null(input$study_measures)) d$measures <- as.list(input$study_measures)
      for (i in seq_along(d$conditions)) {
        d$conditions[[i]]$label <- value(paste0("condition_label_", i), d$conditions[[i]]$label)
        d$conditions[[i]]$role <- value(paste0("condition_role_", i), d$conditions[[i]]$role)
      }
      for (i in seq_along(d$stimuli)) {
        s <- d$stimuli[[i]]; s$title <- value(paste0("stimulus_title_", i), s$title)
        s$content <- value(paste0("stimulus_text_", i), s$content)
        s$duration_ms <- value(paste0("stimulus_duration_", i), s$duration_ms)
        s$condition_id <- value(paste0("stimulus_condition_", i), s$condition_id)
        d$stimuli[[i]] <- s
      }
    }
    if (state$stage == "Questions") for (i in seq_along(d$questions)) {
      q <- d$questions[[i]]
      q$prompt <- value(paste0("q_prompt_", i), q$prompt)
      if (!"questionnaire_sections" %in% names(d)) q$scope <- value(paste0("q_scope_", i), q$scope)
      q$required <- isTRUE(value(paste0("q_required_", i), q$required))
      randomize <- isTRUE(value(paste0("q_random_", i), q$randomize_options))
      # Enabling randomization is a new draft choice. Already-randomized legacy
      # questions retain their named historical behavior until explicitly upgraded.
      if (randomize && !isTRUE(q$randomize_options)) q$option_assignment <- "participant-sha256/1.0"
      q$randomize_options <- randomize
      text <- input[[paste0("q_options_", i)]]
      if (!is.null(text)) q$options <- options_from_text(text, q$options)
      q$min <- value(paste0("q_min_", i), q$min); q$max <- value(paste0("q_max_", i), q$max); q$step <- value(paste0("q_step_", i), q$step)
      row_text <- input[[paste0("q_rows_", i)]]
      if (!is.null(row_text)) {
        labels <- trimws(strsplit(row_text, "\n", fixed = TRUE)[[1]]); labels <- labels[nzchar(labels)]
        q$rows <- lapply(seq_along(labels), function(j) list(id = if (length(q$rows) >= j) q$rows[[j]]$id else brohn_id("row"), label = labels[j]))
      }
      d$questions[[i]] <- q
    }
    if (state$stage == "Tasks") for (i in seq_along(d$blocks)) {
      task <- d$blocks[[i]]
      task$title <- value(paste0("task_title_", i), task$title); task$origin <- value(paste0("task_origin_", i), task$origin)
      task$materials_rights <- value(paste0("task_rights_", i), task$materials_rights)
      task$seed <- value(paste0("task_seed_", i), task$seed)
      task$settings$control_rationale <- value(paste0("task_control_", i), task$settings$control_rationale)
      task$settings$intertrial_ms <- value(paste0("task_interval_", i), task$settings$intertrial_ms)
      task$settings$trial_timeout_ms <- value(paste0("task_timeout_", i), task$settings$trial_timeout_ms)
      for (j in seq_along(task$categories)) task$categories[[j]]$label <- value(paste0("task_category_", i, "_", j), task$categories[[j]]$label)
      for (j in seq_along(task$materials)) if (task$materials[[j]]$type == "text") task$materials[[j]]$content <- value(paste0("task_material_", i, "_", j), task$materials[[j]]$content)
      d$blocks[[i]] <- task
    }
    if (!identical(brohn_hash(d), brohn_hash(current$study$body))) update_study(d, FALSE)
    invisible(current$study)
  }
  navigate <- function(page) attempt(function() {
    capture(); state$page <- page; state$error <- NULL; refresh()
    session$sendCustomMessage("brohn-navigation", list(page = page, focus = TRUE))
  })
  for (page in c("home", "studies", "datasets", "designs", "activity", "settings")) local({p <- page; shiny::observeEvent(input[[paste0("nav_", p)]], navigate(p))})
  for (stage in c("Plan", "Questions", "Tasks", "Collect", "Review", "Results", "History")) local({s <- stage; shiny::observeEvent(input[[paste0("stage_", tolower(s))]], attempt(function() {capture(); state$stage <- s; refresh(); session$sendCustomMessage("brohn-focus", "brohn-main")}))})
  shiny::observeEvent(input$save_study, attempt(function() {capture(); message(paste("Saved revision", current$study$revision))}))
  brohn_install_analysis_plan_ui(input, output, session, current, attempt, capture, update_study, state)
  brohn_install_question_flow_server(input, output, session, current, state, capture, update_study, attempt, message)
  brohn_install_question_sections_ui(input, output, session, current, state, capture, update_study, attempt, message)
  brohn_install_question_revision_ui(input, output, session, current, state, capture, update_study, attempt, message)
  brohn_install_camera_plan_ui(input, output, session, current, state, capture, attempt, update_study, message)
  brohn_install_scale_ui(input, output, session, current, state, attempt, capture, update_study)
  brohn_install_maxdiff_ui(input, output, session, current, state, attempt, capture, update_study)
  shiny::observeEvent(input$brohn_open_study, attempt(function() {capture(); select_study(input$brohn_open_study)}))
  shiny::observeEvent(input$new_study, shiny::showModal(shiny::modalDialog(title = "Start a study",
    shiny::textInput("new_title", "Study name", "My study"),
    shiny::radioButtons("new_template", "Starting point", c("Controlled concept comparison" = "comparison", "Questionnaire" = "survey", "Blank design" = "blank")),
    footer = shiny::tagList(shiny::modalButton("Cancel"), shiny::actionButton("create_study", "Create study", class = "btn-primary")))))
  shiny::observeEvent(input$create_study, attempt(function() {s <- brohn_create_study(store, input$new_title, input$new_template); shiny::removeModal(); select_study(s$id)}))
  shiny::observeEvent(input$open_sample, attempt(function() {s <- brohn_sample_study(store); select_study(s$id)}))
  shiny::observeEvent(input$clone_study, attempt(function() {capture(); shiny::showModal(shiny::modalDialog(title = "Clone study design",
    shiny::p("Copies the design, stimuli, areas and questions into a new draft. Participant observations, results and links stay with the original."),
    shiny::textInput("clone_title", "Name for the new study", paste(current$study$body$title, "copy")),
    footer = shiny::tagList(shiny::modalButton("Cancel"), shiny::actionButton("confirm_clone", "Create clone", class = "btn-primary"))))}))
  shiny::observeEvent(input$confirm_clone, attempt(function() {s <- brohn_clone_study(store, current$study$id, input$clone_title); shiny::removeModal(); select_study(s$id)}))
  shiny::observeEvent(input$save_template, attempt(function() {capture(); brohn_save_template(store, current$study$id); message("Design saved in your library"); refresh()}))
  shiny::observeEvent(input$brohn_use_template, attempt(function() {s <- brohn_use_template(store, input$brohn_use_template); select_study(s$id)}))
  shiny::observeEvent(input$archive_study, attempt(function() {capture(); brohn_archive_study(store, current$study$id, !isTRUE(current$study$body$archived)); select_study(current$study$id, "History")}))
  shiny::observeEvent(input$view_design_revision, attempt(function() {
    selection <- input$view_design_revision
    current$history <- brohn_study(store, selection$id, selection$revision)
    h <- current$history
    shiny::showModal(shiny::modalDialog(title = paste("Design revision", h$revision), size = "l",
      shiny::h2(h$body$title), shiny::p(h$body$description), shiny::p(paste("Saved", h$updated_at)),
      shiny::p(paste(length(h$body$stimuli), "stimuli;", length(h$body$questions), "questions; order:", h$body$order)),
      shiny::tags$details(shiny::tags$summary("Inspect the complete frozen design"), shiny::tags$pre(brohn_json(h$body, TRUE))),
      footer = shiny::tagList(shiny::modalButton("Close"), shiny::downloadButton("export_history_design", "Export this revision", icon = NULL),
        shiny::actionButton("clone_history_design", "Clone this revision", class = "btn-primary"))))
  }))
  shiny::observeEvent(input$clone_history_design, attempt(function() {
    h <- current$history; shiny::req(h)
    copy <- brohn_clone_study(store, h$id, paste(h$body$title, "revision", h$revision, "copy"), revision = h$revision)
    shiny::removeModal(); select_study(copy$id)
  }))
  output$export_history_design <- shiny::downloadHandler(filename = function() paste0(current$history$id, "-revision-", current$history$revision, ".brohn-study.zip"),
    content = function(file) {
      h <- current$history; artifact <- tempfile(fileext = ".brohn-study.zip"); on.exit(unlink(artifact), add = TRUE)
      brohn_export_design(store, h$id, artifact, revision = h$revision)
      brohn_require(file.copy(artifact, file, overwrite = TRUE), "The historical design download could not be prepared.")
    }, contentType = "application/zip")
  shiny::observeEvent(input$inspect_legacy_artifact, attempt(function() {
    request <- input$inspect_legacy_artifact
    migration <- brohn_get_entity(store, "migration", request$migration_id)
    brohn_require(!is.null(migration), "This earlier artifact is unavailable.")
    matches <- Filter(function(a) identical(a$object$hash, request$hash), migration$body$artifacts)
    brohn_require(length(matches) > 0, "Choose an artifact belonging to this imported study.")
    current$legacy_artifact <- matches[[1]]
    a <- current$legacy_artifact; path <- brohn_object_path(store, a$object$hash)
    preview <- if (a$object$size <= 1024^2 && grepl("[.]json$", a$filename, ignore.case = TRUE)) tryCatch(brohn_read_json_file(path), error = function(e) NULL) else NULL
    shiny::showModal(shiny::modalDialog(title = a$filename, size = "l", shiny::p(paste("Preserved original", a$type)),
      shiny::p(paste("Verified SHA-256", a$object$hash)), if (!is.null(preview)) shiny::tags$pre(brohn_json(preview, TRUE)),
      footer = shiny::tagList(shiny::modalButton("Close"), shiny::downloadButton("download_legacy_artifact", "Download original", icon = NULL))))
  }))
  output$download_legacy_artifact <- shiny::downloadHandler(filename = function() basename(current$legacy_artifact$filename), content = function(file) {
    prepare_download(function() brohn_copy_object_download(store, current$legacy_artifact$object$hash, file))
  }, contentType = "application/octet-stream")
  shiny::observeEvent(input$add_stimulus, attempt(function() {
    capture(); d <- current$study$body
    if (!length(d$conditions)) d$conditions <- list(list(id = brohn_id("condition"), label = "Condition 1", role = "other"))
    d$stimuli[[length(d$stimuli)+1L]] <- list(id = brohn_id("stimulus"), title = paste("Stimulus", length(d$stimuli)+1L), condition_id = d$conditions[[1]]$id,
      type = "text", content = "", asset = NULL, duration_ms = 5000, aois = list()); update_study(d)
  }))
  shiny::observeEvent(input$add_condition, attempt(function() {capture(); d <- current$study$body; d$conditions[[length(d$conditions)+1L]] <- list(id = brohn_id("condition"), label = paste("Condition", length(d$conditions)+1L), role = "other"); update_study(d)}))
  # Upload buttons are delegated in one message so dynamically added cards work.
  shiny::observeEvent(input$upload_stimulus, attempt(function() {
    capture(); id <- input$upload_stimulus; current$upload_stimulus <- id
    shiny::showModal(shiny::modalDialog(title = "Attach stimulus image", shiny::fileInput("stimulus_upload", "PNG image", accept = ".png"),
      shiny::p("Replacing an image clears its old areas. Historical revisions keep their original image and areas."), footer = shiny::modalButton("Cancel")))
  }))
  shiny::observeEvent(input$stimulus_upload, attempt(function() {
    shiny::req(input$stimulus_upload$datapath); d <- brohn_attach_png(store, current$study$body, current$upload_stimulus, input$stimulus_upload$datapath, input$stimulus_upload$name)
    update_study(d); shiny::removeModal()
  }))
  show_aoi <- function(stimulus_id, area_id = NULL) {
    capture(); current$aoi_stimulus <- stimulus_id; current$aoi_id <- area_id
    s <- brohn_find(current$study$body$stimuli, current$aoi_stimulus)
    a <- if (is.null(area_id)) NULL else brohn_find(s$aois, area_id)
    if (!is.null(area_id)) brohn_require(!is.null(a), "This area is no longer available. Reload the study.")
    shiny::showModal(shiny::modalDialog(title = paste("Define an area on", s$title), size = "l",
      brohn_aoi_editor(store, s, a),
      footer = shiny::tagList(shiny::modalButton("Cancel"), shiny::actionButton("save_aoi", "Save area", class = "btn-primary"))))
  }
  shiny::observeEvent(input$edit_aoi, attempt(function() show_aoi(input$edit_aoi)))
  shiny::observeEvent(input$suggest_aoi, attempt(function() {
    capture(); brohn_require(!isTRUE(current$study$body$archived), "Restore this study before editing its design.")
    current$proposal_stimulus <- input$suggest_aoi
    stimulus <- brohn_find(current$study$body$stimuli, current$proposal_stimulus)
    brohn_require(!is.null(stimulus) && identical(stimulus$asset$media_type, "image/png"), "Choose a current PNG image.")
    shiny::showModal(shiny::modalDialog(title = paste("Suggest an area on", stimulus$title), size = "l", brohn_aoi_prompt_ui(store, stimulus),
      footer = shiny::tagList(shiny::modalButton("Cancel"), shiny::actionButton("generate_aoi_proposal", "Generate suggestion", class = "btn-primary"))))
  }))
  shiny::observeEvent(input$generate_aoi_proposal, attempt(function() {
    brohn_queue_aoi_proposal(store, current$study$id, current$proposal_stimulus, list(x = input$aoi_prompt_x, y = input$aoi_prompt_y), current$study$revision)
    shiny::removeModal(); message("Suggestion queued. Review it below your stimuli when processing finishes.")
  }))
  shiny::observeEvent(input$review_aoi_proposal, attempt(function() {
    capture(); record <- brohn_get_entity(store, "aoi_proposal", input$review_aoi_proposal)
    brohn_require(!is.null(record) && identical(record$body$study_id, current$study$id), "Choose a suggestion from this study.")
    current$proposal <- record
    stimulus <- brohn_find(current$study$body$stimuli, record$body$stimulus_id)
    reviewable <- identical(record$body$status, "needs_review") && !isTRUE(current$study$body$archived) &&
      !is.null(stimulus) && identical(stimulus$asset$hash, record$body$source_hash)
    current$proposal_study_revision <- current$study$revision
    shiny::showModal(shiny::modalDialog(title = "Review suggested area", size = "l",
      if (reviewable) brohn_proposal_review_ui(store, record, stimulus) else shiny::tagList(
        shiny::p(paste("Suggestion status:", gsub("_", " ", record$body$status))),
        if (identical(record$body$status, "needs_review")) shiny::p("The image changed or this study is archived. Generate a new suggestion from the current image after restoring the study."),
        shiny::tags$pre(brohn_json(record$body, TRUE))),
      footer = shiny::tagList(shiny::modalButton("Close"), if (reviewable) shiny::tagList(
        shiny::actionButton("reject_aoi_proposal", "Reject suggestion"), shiny::actionButton("accept_aoi_proposal", "Accept this rectangle", class = "btn-primary")))))
  }))
  review_proposal <- function(action) {
    brohn_review_aoi_proposal(store, current$proposal$id, action, label = input$aoi_label,
      expected_revision = current$proposal$revision, study_revision = current$proposal_study_revision,
      rectangle = list(x = input$aoi_x, y = input$aoi_y, width = input$aoi_width, height = input$aoi_height),
      note = brohn_default(input$proposal_review_note, ""))
    current$study <- brohn_study(store, current$study$id); shiny::removeModal(); refresh()
    message(if (action == "accept_rectangle") "Reviewed rectangle saved in a new study revision." else "Suggestion rejected. Its evidence remains in history.")
  }
  shiny::observeEvent(input$accept_aoi_proposal, attempt(function() review_proposal("accept_rectangle")))
  shiny::observeEvent(input$reject_aoi_proposal, attempt(function() review_proposal("reject")))
  output$proposal_mask <- shiny::downloadHandler(filename = function() paste0(current$proposal$id, "-mask.png"), content = function(file) {
    prepare_download(function() brohn_copy_object_download(store, current$proposal$body$proposal$mask_object$hash, file))
  }, contentType = "image/png")
  shiny::observeEvent(input$edit_existing_aoi, attempt(function() show_aoi(input$edit_existing_aoi$stimulus_id, input$edit_existing_aoi$aoi_id)))
  shiny::observeEvent(input$remove_aoi, attempt(function() {
    capture(); d <- current$study$body; i <- match(input$remove_aoi$stimulus_id, brohn_ids(d$stimuli))
    brohn_require(!is.na(i), "Choose a current stimulus.")
    d$stimuli[[i]]$aois <- Filter(function(a) !identical(a$id, input$remove_aoi$aoi_id), d$stimuli[[i]]$aois); update_study(d)
  }))
  shiny::observeEvent(input$save_aoi, attempt(function() {
    d <- current$study$body; i <- match(current$aoi_stimulus, brohn_ids(d$stimuli)); s <- d$stimuli[[i]]
    a <- list(id = brohn_default(current$aoi_id, brohn_id("aoi")), label = input$aoi_label, x = input$aoi_x, y = input$aoi_y, width = input$aoi_width, height = input$aoi_height, source = "manual")
    if (!is.null(s$asset)) a$asset_hash <- s$asset$hash
    if (is.null(current$aoi_id)) s$aois[[length(s$aois)+1L]] <- a else s$aois[[match(current$aoi_id, brohn_ids(s$aois))]] <- a
    d$stimuli[[i]] <- s; update_study(d); shiny::removeModal()
  }))
  shiny::observeEvent(input$add_question, attempt(function() {
    capture(); d <- current$study$body; q <- brohn_question("Your question", input$question_type, if (length(d$stimuli)) "after_each" else "end")
    if (q$type == "matrix") q$rows <- list(list(id = "row-1", label = "First statement"))
    if (q$type == "allocation") {q$min <- 0; q$max <- 100}
    if (q$type == "information") q$required <- FALSE
    d <- brohn_question_sections_add(d, q); update_study(d)
  }))
  shiny::observeEvent(input$add_task, attempt(function() {
    capture(); d <- current$study$body; block <- brohn_task_new(input$task_profile)
    d$blocks[[length(d$blocks)+1L]] <- block
    kind <- brohn_task_profile(block$profile)$kind; measure <- if (kind %in% c("simple_rt", "choice_rt")) "rt" else kind
    d$measures <- as.list(unique(c(unlist(d$measures), measure)))
    update_study(d)
  }))
  shiny::observeEvent(input$remove_task, attempt(function() {
    capture(); d <- current$study$body; d$blocks <- Filter(function(b) b$id != input$remove_task, d$blocks); update_study(d)
  }))
  shiny::observeEvent(input$task_image, attempt(function() {
    capture(); current$task_image <- input$task_image
    shiny::showModal(shiny::modalDialog(title = "Task image exemplar", shiny::fileInput("task_image_upload", "PNG image", accept = ".png"),
      shiny::p("Images become immutable task materials. Review their category membership, salience and comparability before collection."), footer = shiny::modalButton("Cancel")))
  }))
  shiny::observeEvent(input$task_image_upload, attempt(function() {
    shiny::req(input$task_image_upload$datapath)
    selection <- current$task_image; d <- current$study$body; i <- match(selection$task_id, brohn_ids(d$blocks))
    brohn_require(!is.na(i), "The task no longer exists."); j <- match(selection$material_id, brohn_ids(d$blocks[[i]]$materials))
    brohn_require(!is.na(j), "The task exemplar no longer exists.")
    image <- new_png_asset(input$task_image_upload$datapath, selection$material_id)
    bytes <- jsonlite::base64_dec(image$data_base64); dimensions <- stimulus_png_header(bytes)
    asset <- brohn_store_object(store, bytes = bytes, media_type = "image/png")
    asset$width <- unname(dimensions[["width"]]); asset$height <- unname(dimensions[["height"]]); asset$filename <- basename(input$task_image_upload$name)
    d$blocks[[i]]$materials[[j]]$asset <- asset; d$blocks[[i]]$materials[[j]]$type <- "image"
    update_study(d); shiny::removeModal()
  }))
  shiny::observeEvent(input$remove_question, attempt(function() {capture(); d <- brohn_question_sections_remove(current$study$body, input$remove_question); update_study(d)}))
  shiny::observeEvent(input$question_assignment_upgrade, attempt(function() {
    command <- input$question_assignment_upgrade
    brohn_fields(command, c("study_id", "question_id", "question_hash"), label = "Question assignment change")
    brohn_require(identical(state$page, "study") && identical(state$stage, "Questions") && !is.null(current$study) &&
      identical(command$study_id, current$study$id) &&
      identical(input$study_form_identity, paste(current$study$id, "Questions", sep = ":")),
      "Open the question in its study before changing its option assignment.")
    index <- match(command$question_id, brohn_ids(current$study$body$questions))
    brohn_require(!is.na(index) && identical(command$question_hash, brohn_hash(current$study$body$questions[[index]])),
      "The question changed. Reopen it before updating its option assignment.")
    capture(); d <- current$study$body; q <- d$questions[[index]]
    brohn_require(isTRUE(q$randomize_options), "Enable option randomization before changing its assignment.")
    q$option_assignment <- "participant-sha256/1.0"; d$questions[[index]] <- q
    update_study(d); message("Participant-specific option order saved for this draft question. Existing releases are unchanged.")
  }))
  shiny::observeEvent(input$question_move, attempt(function() {
    capture(); d <- current$study$body; i <- match(input$question_move$id, brohn_ids(d$questions)); j <- i + as.integer(input$question_move$direction)
    brohn_require(!"questionnaire_sections" %in% names(d), "Move this question with its group in Questionnaire sections.")
    brohn_require(!is.na(i) && j >= 1 && j <= length(d$questions), "Question cannot move further.")
    order <- seq_along(d$questions); order[c(i,j)] <- order[c(j,i)]; d$questions <- d$questions[order]; update_study(d)
  }))
  shiny::observeEvent(input$publish_study, attempt(function() {
    capture(); brohn_require(exists("brohn_publish", mode = "function"), "The participant service is not available.")
    brohn_require(brohn_participant_ready(store$workspace_id), "The participant service is not responding for this workspace. Start Brohn with its local launcher and retry.")
    release <- brohn_publish(store, current$study$id, origin = input$release_origin, quota = input$release_quota, alias_required = isTRUE(input$release_alias))
    message(paste("Study released for", release$origin, "participants")); refresh()
  }))
  shiny::observeEvent(input$deployment_command, attempt(function() {brohn_deployment_state(store, input$deployment_command$id, input$deployment_command$state); message("Collection status updated"); refresh()}))
  output$export_design <- shiny::downloadHandler(filename = function() paste0(gsub("[^A-Za-z0-9_-]", "-", current$study$body$title), ".brohn-study.zip"),
    content = function(file) prepare_download(function() {
      capture(); artifact <- tempfile(fileext = ".brohn-study.zip")
      on.exit(unlink(artifact), add = TRUE)
      brohn_export_design(store, current$study$id, artifact)
      brohn_require(file.copy(artifact, file, overwrite = TRUE), "The design download could not be prepared.")
    }), contentType = "application/zip")
  shiny::observeEvent(input$import_design_file, attempt(function() {
    shiny::req(input$import_design_file$datapath); s <- brohn_import_design(store, input$import_design_file$datapath); select_study(s$id)
  }))
  shiny::observeEvent(input$open_dataset, attempt(function() {capture(); state$dataset_id <- input$open_dataset; state$page <- "dataset"; refresh()}))
  shiny::observeEvent(input$accept_dataset, attempt(function() {
    dataset <- brohn_get_entity(store, "dataset", state$dataset_id)
    brohn_require(identical(input$dataset_form_identity, paste(dataset$id, dataset$revision, sep = ":")), "The dataset mapping changed while this form was open. Reopen the source before saving.")
    if (identical(dataset$body$modality,"implicit")) {
      mapped <- task_import_ui$mapping()
      accepted <- brohn_curate_dataset(store,dataset$id,mapped$metadata,dataset$revision,mapped$study$id,mapped$study$revision)
      brohn_queue_dataset(store,accepted$id,accepted$revision)
      message("Task protocol and mapping saved. Analysis queued."); refresh(); return(invisible(accepted))
    }
    metadata <- brohn_dataset_base_mapping(input, dataset$body)
    if (dataset$body$modality %in% c("gaze", "prepared_gaze")) {
      metadata$gaze_representation <- brohn_default(input$map_gaze_representation, "intervals")
      if (metadata$gaze_representation == "samples") metadata <- c(metadata, brohn_raw_gaze_input(input))
    }
    if (!dataset$body$source$format %in% c("csv", "tsv")) {
      metadata$value_columns <- as.list(brohn_parse_native_channel_input(brohn_default(input$map_native_values, "")))
      if (dataset$body$modality == "audio") metadata$channel_index <- input$map_audio_channel
      if (dataset$body$modality == "fnirs") metadata$parameters <- list(ppf = list(input$map_ppf_1, input$map_ppf_2))
    }
    if (dataset$body$modality == "video") {
      metadata <- list(origin_statement = input$map_origin, profile = input$map_video_profile,
        max_support_gap_s = input$map_video_gap)
      if (identical(metadata$profile, "custom_v1")) metadata$channels <- as.list(input$map_video_channels)
      if (brohn_number(input$map_video_start, 0, 600)) metadata$start_s <- input$map_video_start
      if (brohn_number(input$map_video_end, 0, 600)) metadata$end_s <- input$map_video_end
    }
    if (dataset$body$modality == "eeg") metadata <- brohn_neural_input(input, metadata, dataset$body$source$format)
    if (dataset$body$modality == "eda") metadata <- brohn_eda_events_input(input, metadata, dataset$body$source$format)
    if (dataset$body$modality %in% c("temperature", "movement")) metadata <- brohn_peripheral_input(input, metadata, dataset$body$modality)
    if (dataset$body$modality == "multimodal") metadata <- list(origin_statement = input$map_origin, clock_policy = "preserve_only")
    selected <- input$map_study; study_id <- if (is.null(selected) || !nzchar(selected)) NULL else selected
    selected_revision <- input$map_study_revision
    study_revision <- if (is.null(study_id) || is.null(selected_revision) || identical(selected_revision, "current")) NULL else suppressWarnings(as.numeric(selected_revision))
    if (identical(dataset$body$modality,"maxdiff")) {
      pinned <- brohn_maxdiff_mapping_study(store,dataset,input)
      brohn_require(identical(input$maxdiff_mapping_design_identity,brohn_maxdiff_mapping_identity(dataset,pinned)),
        "The best-worst study version changed while this mapping was open. Reopen its exercise selection before saving.")
      study_id <- pinned$id; study_revision <- pinned$revision
    }
    accepted <- brohn_curate_dataset(store, dataset$id, metadata, dataset$revision, study_id, study_revision)
    if (dataset$body$modality == "multimodal") {
      brohn_queue_multistream(store, accepted$id, accepted$revision)
      message("Source declaration saved. Stream preservation queued.")
    } else {
      brohn_queue_dataset(store, accepted$id, accepted$revision)
      message("Mapping saved. Analysis queued.")
    }
    refresh()
  }))
  shiny::observeEvent(input$analyse_dataset, attempt(function() {
    dataset <- brohn_get_entity(store, "dataset", state$dataset_id)
    if (dataset$body$modality == "multimodal") {
      brohn_queue_multistream(store, dataset$id, dataset$revision, force = TRUE)
      message("A new stream import is queued; earlier imports are retained.")
    } else {
      brohn_queue_dataset(store, dataset$id, dataset$revision, force = TRUE)
      message("A new analysis is queued; earlier reports are retained.")
    }
    refresh()
  }))
  shiny::observeEvent(input$open_report, attempt(function() {
    report <- brohn_get_entity(store, "report", input$open_report)
    brohn_require(!is.null(report), "Choose an available saved report.")
    state$report_id <- report$id; state$page <- "report"; message("Saved report ready for review"); refresh()
  }))
  shiny::observeEvent(input$analyse_cohort, attempt(function() {brohn_queue_cohort(store, input$analyse_cohort); message("A report for this release's completed sessions is queued."); refresh()}))
  output$report_html <- shiny::downloadHandler(filename = function() paste0(state$report_id, ".html"), content = function(file) {
    brohn_export_report_html(brohn_get_entity(store, "report", state$report_id)$body, file, store)
  }, contentType = "text/html")
  output$report_csv <- shiny::downloadHandler(filename = function() paste0(state$report_id, "-observations.csv"), content = function(file) {
    prepare_download(function() {
      brohn_require(identical(state$page, "report") && brohn_valid_id(state$report_id), "Open the saved report before downloading its observations.")
      report <- brohn_get_entity(store, "report", state$report_id)
      brohn_require(!is.null(report), "This saved report is unavailable.")
      if (identical(report$body$analysis$schema, "brohn-task-cohort/1.0")) brohn_export_task_cohort_csv(report$body, file) else brohn_export_report_csv(brohn_complete_questionnaire_report(store, report$body), file)
    })
  }, contentType = "text/csv")
  output$report_scale_csv <- shiny::downloadHandler(filename = function() paste0(state$report_id, "-scale-scores.csv"), content = function(file) {
    prepare_download(function() {
      report <- brohn_get_entity(store, "report", state$report_id)
      brohn_require(!is.null(report), "The selected report is unavailable.")
      report$body <- brohn_complete_questionnaire_report(store, report$body)
      brohn_require(identical(state$page, "report") && !is.null(report$body$analysis$scales), "Choose a saved report containing questionnaire scale scores.")
      brohn_scale_scores_csv(report$body$analysis$scales, file)
    })
  }, contentType = "text/csv")
  output$report_maxdiff_csv <- shiny::downloadHandler(filename = function() paste0(state$report_id,"-best-worst-choices.csv"),content=function(file) {
    prepare_download(function() {
      report<-brohn_get_entity(store,"report",state$report_id)
      brohn_require(!is.null(report), "The selected report is unavailable.")
      report$body <- brohn_complete_questionnaire_report(store, report$body)
      brohn_require(identical(state$page,"report") && length(report$body$analysis$choice_tasks)>0L,"Choose a saved report containing best-worst choices.")
      brohn_export_report_csv(list(analysis=list(observations=brohn_maxdiff_export_rows(report$body$analysis$choice_tasks))),file)
    })
  },contentType="text/csv")
  output$report_task_csv <- shiny::downloadHandler(filename = function() paste0(state$report_id, "-task-scores.csv"), content = function(file) {
    prepare_download(function() {
      brohn_require(identical(state$page, "report"), "Choose a saved report containing task scores.")
      report <- brohn_get_entity(store, "report", state$report_id)
      brohn_require(!is.null(report), "The selected report is unavailable.")
      brohn_export_task_scores_csv(brohn_complete_questionnaire_report(store, report$body), file)
    })
  }, contentType = "text/csv")
  report_artifact <- function() {
    report <- brohn_get_entity(store, "report", state$report_id)
    brohn_require(!is.null(report), "Choose a saved report.")
    artifacts <- Filter(function(a) identical(a$kind, input$report_artifact_kind), report$body$analysis$artifacts)
    brohn_require(length(artifacts) == 1L, "Choose a complete artifact from this report.")
    artifacts[[1]]
  }
  output$report_artifact <- shiny::downloadHandler(filename = function() {
    a <- report_artifact(); paste0(a$kind, "-", substr(a$hash, 1, 12), if (a$media_type == "image/png") ".png" else ".jsonl")
  }, content = function(file) {
    prepare_download(function() {a <- report_artifact(); brohn_copy_object_download(store, a$hash, file)})
  })
  output$report_download <- shiny::downloadHandler(filename = function() paste0(state$report_id, ".json"), content = function(file) {
    prepare_download(function() {
      brohn_require(identical(state$page, "report"), "Open the saved report before downloading it.")
      report <- brohn_get_entity(store, "report", state$report_id)
      brohn_require(!is.null(report), "Report is unavailable.")
      brohn_export_complete_questionnaire_report(store, report$body, file)
    })
  }, contentType = "application/json")
  shiny::observeEvent(input$import_legacy, attempt(function() {
    result <- brohn_import_legacy(store, input$legacy_path)
    failures <- Filter(function(x) x$status == "failed", result)
    message(paste(length(result)-length(failures), "drafts preserved;", length(failures), "need attention"))
    if (length(failures)) state$error <- paste(vapply(failures, function(x) paste(x$filename, x$reason, sep = ": "), character(1)), collapse = "\n")
    refresh()
  }))
  shiny::observeEvent(input$backup_workspace, attempt(function() {
    destination <- input$backup_destination
    brohn_require(brohn_text(destination, 4000), "Choose a new backup folder with an existing parent directory.")
    destination <- normalizePath(destination, winslash = "/", mustWork = FALSE)
    brohn_require(!file.exists(destination) && dir.exists(dirname(destination)), "The backup folder must be new and its parent folder must already exist.")
    brohn_require(!startsWith(tolower(destination), paste0(tolower(store$root), "/")), "Place the backup outside this workspace.")
    brohn_enqueue_job(store, "backup_workspace", list(destination = destination), paste0("backup:", brohn_id("request")))
    message("Verified backup queued. Its progress and destination appear in Activity."); state$page <- "activity"; refresh()
  }))
  shiny::observeEvent(input$resume_workspace, attempt(function() {
    brohn_resume_workspace(store); message("Workspace processing resumed. Closed participant releases remain closed."); refresh()
  }))
  shiny::observeEvent(input$cancel_processing, attempt(function() {
    brohn_cancel_job(store, input$cancel_processing); message("Processing cancelled. Saved sources and earlier results are retained."); if (state$page != "report") refresh()
  }))
  shiny::observeEvent(input$retry_processing, attempt(function() {
    brohn_retry_processing(store, input$retry_processing); message("Processing queued again with the same frozen inputs."); if (state$page != "report") refresh()
  }))
  shiny::observeEvent(input$library_page, attempt(function() {
    command <- input$library_page
    brohn_require(command$kind %in% c("study", "dataset", "template") && command$direction %in% c(-1, 1), "Choose a library page.")
    field <- paste0(command$kind, "_offset"); state[[field]] <- max(0, state[[field]] + command$direction*40L)
  }))
  shiny::observeEvent(input$related_page, attempt(function() brohn_related_page_command(store,state,input$related_page)))
  for (kind in c("study", "dataset", "template")) local({
    k <- kind
    shiny::observeEvent(list(input[[paste0(k, "_search")]], input[[paste0(k, "_filter")]]), {state[[paste0(k, "_offset")]] <- 0L}, ignoreInit = TRUE)
    output[[paste0(k, "_catalog")]] <- shiny::renderUI({
      state$refresh
      query <- brohn_default(input[[paste0(k, "_search")]], "")
      filter <- brohn_default(input[[paste0(k, "_filter")]], "all")
      result <- brohn_search_library(store, k, query, archived = if (k == "study" && filter != "all") identical(filter, "archived") else NULL,
        modality = if (k == "dataset" && filter != "all") filter else NULL, offset = state[[paste0(k, "_offset")]])
      brohn_library_results_ui(result, k)
    })
  })
  output$platform_content <- shiny::renderUI({
    state$refresh
    brohn_render_page(store, state, current$study)
  })
  output$dataset_reports <- shiny::renderUI({
    shiny::invalidateLater(2000, session)
    shiny::req(state$page == "dataset", state$dataset_id)
    brohn_dataset_reports_ui(store, state$dataset_id, state)
  })
  output$mapping_study_revision <- shiny::renderUI({
    shiny::req(state$page == "dataset", input$map_study, nzchar(input$map_study))
    history <- brohn_entity_history(store, "study", input$map_study)
    dataset <- brohn_get_entity(store, "dataset", state$dataset_id)
    selected <- if (identical(dataset$body$study_id, input$map_study) && !is.null(dataset$body$study_revision)) as.character(dataset$body$study_revision) else "current"
    choices <- c("Current draft (frozen when each analysis starts)" = "current", stats::setNames(vapply(history, function(h) as.character(h$revision), character(1)),
      vapply(history, function(h) paste("Saved revision", h$revision, "\u00b7", h$body$title), character(1))))
    shiny::selectInput("map_study_revision", "Study version used for this recording", choices, selected)
  })
  output$aoi_proposals <- shiny::renderUI({
    shiny::invalidateLater(2000, session)
    shiny::req(state$page == "study", state$stage == "Plan", current$study)
    brohn_proposals_ui(store, current$study$id)
  })
  output$collection_sessions <- shiny::renderUI({
    shiny::invalidateLater(2000, session)
    shiny::req(state$page == "study", state$stage == "Collect", current$study)
    brohn_sessions_ui(store, current$study$id, state)
  })
  shiny::observe({
    shiny::invalidateLater(2500, session)
    # A saved report is immutable. Its derived explorers poll their own progress;
    # workspace audit activity must not rebuild those inputs or change selection.
    if (state$page == "activity" || (state$page == "study" && state$stage %in% c("Review", "Results"))) {
      stamp <- DBI::dbGetQuery(store$con, "SELECT coalesce(max(sequence),0) AS n FROM audit_log")$n[[1]]
      if (is.null(current$audit_stamp) || !identical(current$audit_stamp, stamp)) {current$audit_stamp <- stamp; refresh()}
    }
  })
  # Inputs are saved after a quiet period without rebuilding their DOM or stealing focus.
  edits <- shiny::reactive({
    names <- names(shiny::reactiveValuesToList(input))
    selected <- names[grepl("^(study_|condition_(label|role)_|stimulus_(title|text|duration|condition)_|q_(prompt|scope|required|random|options|min|max|step|rows|logic|equals)_|task_(title|origin|rights|seed|control|interval|timeout|category|material)_|baseline_ms$|fixation_ms$|consent_text$|debrief_text$|participant_(background|foreground)$)", names)]
    lapply(selected, function(id) input[[id]])
  })
  quiet <- shiny::debounce(edits, 900)
  # A background save must not dismiss an actionable error from publication or
  # another deliberate command. The next explicit command clears/replaces it.
  shiny::observeEvent(quiet(), {if (!is.null(current$study) && state$page == "study") attempt(function() capture(), clear_error = FALSE)}, ignoreInit = TRUE)
}

brohn_command <- function(label, event, value, class = "btn btn-outline-secondary", ...) {
  shiny::tags$button(type = "button", class = class, `data-brohn-event` = event,
    `data-brohn-value` = brohn_json(value), label, ...)
}
brohn_study_card <- function(record) brohn_card(title = record$body$title,
  subtitle = paste("Revision", record$revision, "\u00b7", length(record$body$stimuli), "stimuli", "\u00b7", length(record$body$questions), "questions"),
  shiny::p(record$body$description), brohn_badge(if (isTRUE(record$body$archived)) "Archived" else "Design saved"),
  shiny::div(class = "brohn-toolbar", brohn_command("Open study", "brohn_open_study", record$id, "btn btn-primary")))
brohn_render_page <- function(store, state, record) {
  page <- state$page
  if (page == "home") {
    studies <- brohn_studies(store, limit = 6L)
    return(brohn_page("Your next discovery starts here.", "Bring the question, the study and the evidence together.",
      actions = shiny::actionButton("new_study", "Create a study", class = "btn-primary"),
      brohn_card(title = "Start with a complete example", subtitle = "Learn the workflow using original fictional packaging. Your study starts without participant data.",
        shiny::actionButton("open_sample", "Explore a practice design", class = "btn-primary")),
      if (length(studies)) shiny::tagList(shiny::h2("Recent studies"), shiny::div(class = "brohn-grid", lapply(head(studies, 6), brohn_study_card))) else
        brohn_empty("A clear place to begin", "Create your first study or explore the practice design.")))
  }
  if (page == "studies") return(brohn_page("Studies", "Every design, dataset and result stays connected to its study.",
    actions = shiny::actionButton("new_study", "Create a study", class = "btn-primary"),
    shiny::div(class = "brohn-form-grid", shiny::textInput("study_search", "Search studies", placeholder = "Name, research question or tag"),
      shiny::selectInput("study_filter", "Study status", c("All studies" = "all", "Active studies" = "active", "Archived studies" = "archived"))),
    shiny::uiOutput("study_catalog"),
    shiny::tags$details(shiny::tags$summary("Import a portable design"), shiny::fileInput("import_design_file", "Brohn study design", accept = ".zip"))))
  if (page == "designs") {
    return(brohn_page("Design library", "Reuse a study structure without bringing its participants or results with it.",
      shiny::fileInput("import_design_file", "Import a Brohn study design", accept = ".zip"),
      shiny::textInput("template_search", "Search saved designs", placeholder = "Design name"), shiny::uiOutput("template_catalog")))
  }
  if (page == "settings") return(brohn_page("Workspace settings", "Your research has a visible home.",
    brohn_card(title = "Storage", shiny::p("Workspace: ", shiny::tags$code(store$workspace_id)), shiny::p("Folder: ", shiny::tags$code(store$root)),
      shiny::p("The catalog retains saved versions and content-addressed source files. A source-code repository is separate from this research storage.")),
    brohn_card(title = "Preserve earlier Brohn drafts", subtitle = "Copies drafts and every neighboring report/protocol into this workspace. Original files are retained.",
      shiny::textInput("legacy_path", "Earlier draft folder", normalizePath("data/drafts", winslash = "/", mustWork = FALSE)), shiny::actionButton("import_legacy", "Import earlier research", class = "btn-primary")),
    brohn_card(title = "Verified local backup", subtitle = "Copies a consistent catalog and every registered source object. The backup includes private participant records and credentials; store it in a protected location.",
      shiny::textInput("backup_destination", "New backup folder", file.path(dirname(store$root), paste0("brohn-backup-", format(Sys.time(), "%Y%m%d-%H%M%S")))),
      shiny::actionButton("backup_workspace", "Create verified backup", class = "btn-primary"),
      shiny::p("Restoring creates a separate workspace, rotates credentials and keeps execution paused. A cancelled backup may leave a verified artifact; Activity retains its requested destination.")),
    if (exists("brohn_workspace_execution_status", mode = "function") && isTRUE(brohn_workspace_execution_status(store)$paused))
      brohn_card(title = "Restored workspace is paused", shiny::p("Review this copy before restarting queued processing. Earlier recruitment links remain closed."), shiny::actionButton("resume_workspace", "Resume workspace processing", class = "btn-primary")),
    brohn_card(title = "Collection profile", shiny::p("Local lab participant service. Public hosting is available only after its authentication, access and deployment requirements are satisfied."))))
  if (page == "activity") {
    jobs <- brohn_list_jobs(store)
    return(brohn_page("Activity", "Processing and recovery are recorded alongside your research.",
      if (!length(jobs)) brohn_empty("No processing jobs yet", "Accepted recordings and datasets create their own analysis jobs.") else
        shiny::div(class = "brohn-stack", lapply(jobs, function(job) brohn_card(title = gsub("_", " ", job$operation),
          brohn_badge(job$status, if (job$status == "failed") "error" else if (job$status == "succeeded") "success" else "neutral"),
          shiny::p(paste("Attempt", job$attempt, "\u00b7", job$updated_at)), if (!is.null(job$request$destination)) shiny::p(job$request$destination),
          if (!is.null(job$result$path)) shiny::p(paste("Verified artifact:", job$result$path)),
          if (!is.null(job$result$report_id)) brohn_command("Open result", "open_report", job$result$report_id),
          if (identical(job$operation, "ingest_source")) brohn_command("Inspect source import", "open_ingestion", job$request$ingestion_id),
          if (job$status %in% c("queued", "running") && !identical(job$operation, "ingest_source")) brohn_command("Cancel processing", "cancel_processing", job$id),
          if (job$status %in% c("failed", "cancelled") && job$operation %in% c("analyse_dataset", "analyse_run", "analyse_cohort", "analyse_task_cohort", "analyse_multimodal", "segment_aoi", "normalise_dataset", "import_multistream", "inspect_header", "signal_catalog", "signal_preview", "assemble_capture", "extract_stream")) brohn_command("Retry saved inputs", "retry_processing", job$id),
          if (!is.null(job$error)) shiny::p(paste(unlist(job$error), collapse = " ")))))))
  }
  if (page == "datasets") return(brohn_dataset_library_ui(store, state))
  if (page == "ingestion") return(brohn_page("Preparing your source", "The original upload and its processing history stay connected.", shiny::uiOutput("ingestion_detail")))
  if (page == "dataset") return(brohn_dataset_detail_ui(store, state$dataset_id))
  if (page == "report") return(brohn_report_detail_ui(store, state$report_id))
  if (page != "study" || is.null(record)) return(brohn_empty("Choose a study", "Open a saved design from Studies."))
  d <- record$body
  stages <- if (isTRUE(d$archived)) c("Review", "Results", "History") else c("Plan", "Questions", "Tasks", "Collect", "Review", "Results", "History")
  body <- switch(state$stage, Plan = brohn_plan_ui(store, d), Questions = brohn_questions_ui(d), Tasks = brohn_tasks_ui(d), Collect = brohn_collect_ui(store, record),
    Review = brohn_review_ui(store, record, state), Results = brohn_results_ui(store, record, state), History = brohn_history_ui(store, record, state))
  brohn_page(d$title, paste("Saved revision", record$revision, "\u00b7", if (isTRUE(d$archived)) "Archived study" else "Research workspace"),
    shiny::tags$div(hidden = NA, shiny::textInput("study_form_identity", NULL, paste(d$id, state$stage, sep = ":"))),
    actions = shiny::tagList(if (!isTRUE(d$archived)) shiny::actionButton("save_study", "Save", class = "btn-primary"),
      shiny::actionButton("clone_study", "Clone design"), shiny::actionButton("save_template", "Save as template"),
      shiny::downloadButton("export_design", "Export design", icon = NULL)),
    shiny::tags$nav(class = "brohn-stage-nav", `aria-label` = "Study stages", lapply(stages, function(s) shiny::actionButton(paste0("stage_", tolower(s)), s,
      class = if (state$stage == s) "active" else "", `aria-current` = if (state$stage == s) "step" else NULL))), body)
}
