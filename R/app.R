research_stages <- c("Plan", "Questions", "Collect", "Review", "Results")
draft_editable <- function(x) {
  !length(x$events) && !length(x$streams) && !length(x$clocks) &&
    x$session$mode %in% c("sample", "preview")
}

stimulus_card <- function(x, index, editable) {
  id <- x$study$stimulus_ids[[index]]
  assets <- x$study$stimulus_assets
  match <- which(vapply(assets, function(a) identical(a$stimulus_id, id), logical(1)))
  asset <- if (length(match)) assets[[match]] else NULL
  label <- c("A", "B")[[index]]
  control <- comparison_settings(x$study)$control_condition
  shiny::div(class = "stimulus-card",
    shiny::p(class = "stimulus-role", paste("Design", label, "-", if (control == "none") "Comparison design" else if (control == label) "Control stimulus" else "Test stimulus")),
    shiny::div(class = "stimulus-slot",
      if (is.null(asset)) shiny::tagList(shiny::span(class = "stimulus-letter", label),
        shiny::strong(paste("Design", label)), shiny::span("Add the image participants will view")) else
          shiny::tags$img(src = paste0("data:image/png;base64,", asset$data_base64),
            alt = paste("Preview of design", label), class = "stimulus-preview")),
    if (editable) shiny::fileInput(paste0("stimulus_", tolower(label)), paste("Design", label, "image"),
      accept = "image/png", buttonLabel = if (is.null(asset)) "Choose PNG" else "Replace PNG", placeholder = "No new file selected") else
        shiny::p(class = "muted", if (is.null(asset)) "No image attached" else "Image included in the draft"),
    if (!is.null(asset)) shiny::tagList(
      shiny::p(class = "muted", paste(length(study_regions(x, id)), if (length(study_regions(x, id)) == 1) "area defined" else "areas defined")),
      if (editable) shiny::actionButton(paste0("edit_aoi_", tolower(label)), paste("Define areas on", label), class = "btn-outline-primary")))
}

research_ui <- function() {
  asset <- function(name) paste0(name, "?v=", as.numeric(file.info(file.path("www", name))$mtime))
  shiny::fluidPage(title = "Brohn - Study workspace", lang = "en",
    theme = bslib::bs_theme(version = 5, bg = "#f6f7fb", fg = "#17233d",
                           primary = "#3158ca", base_font = "system-ui"),
    shiny::tags$head(shiny::tags$link(rel = "stylesheet", href = asset("app.css")),
      shiny::tags$script(src = asset("app.js")), shiny::tags$script(src = asset("aois.js"))),
    shiny::tags$a(href = "#main-content", class = "skip-link", "Skip to study"),
    shiny::tags$header(class = "app-header",
      shiny::div(class = "brand", shiny::span(class = "brand-mark", "B"),
        shiny::div(shiny::strong("Brohn"), shiny::span(class = "brand-caption", "From a question to understanding"))),
      shiny::span(class = "version-label", "EARLY BUILD \u00b7 LOCAL WORKSPACE")),
    shiny::div(class = "app-shell",
      shiny::uiOutput("navigation"),
      shiny::tags$main(id = "main-content", tabindex = "-1",
        shiny::div(role = "status", `aria-live` = "polite", class = "save-status", shiny::textOutput("save_status")),
        shiny::div(id = "draft_edit_state", role = "status", `aria-live` = "polite", class = "edit-status"),
        shiny::uiOutput("error_panel"),
        shiny::uiOutput("workspace"))),
    shiny::tags$footer(class = "app-footer", "Your workspace stays on this computer. This build prepares studies and analyses prepared files. Device recording is not active.")
  )
}

research_server <- function(input, output, session,
                            store_dir = Sys.getenv("RESEARCH_PLATFORM_DATA", "data/drafts")) {
  state <- shiny::reactiveValues(bundle = NULL, path = NULL, fingerprint = NULL,
                                 stage = "Plan", message = "", error = NULL, library_version = 0L,
                                 sample_report = NULL, report_revision = NULL,
                                 import_report = NULL, import_revision = NULL, import_path = NULL, protocol = NULL)
  attempt <- function(action) {
    state$error <- NULL
    tryCatch({ action(); TRUE }, error = function(e) {
      state$error <- conditionMessage(e); FALSE
    })
  }
  open_draft <- function(x, path = NULL) {
    state$bundle <- x; state$path <- path
    state$fingerprint <- if (is.null(path)) NULL else draft_fingerprint(path)
    state$stage <- "Plan"
    state$message <- if (is.null(path)) "New draft - save when you are ready" else "Saved draft opened"
    state$error <- NULL
    state$sample_report <- NULL; state$report_revision <- NULL
    state$import_report <- NULL; state$import_revision <- NULL; state$import_path <- NULL
    state$protocol <- NULL
    tryCatch({ state$protocol <- open_draft_protocol(x, path) },
      error = function(e) state$error <- paste("Saved protocol could not be reopened:", conditionMessage(e)))
    tryCatch({
      saved <- open_draft_analysis(x, path)
      if (!is.null(saved)) {
        state$import_report <- saved$report; state$import_revision <- x$study$revision
        state$import_path <- saved$path
        state$message <- "Saved draft and prepared analysis opened"
      }
    }, error = function(e) state$error <- paste("Saved analysis could not be reopened:", conditionMessage(e)))
    session$sendCustomMessage("draft-saved", list())
  }
  capture_changes <- function() {
    x <- state$bundle
    if (is.null(x) || !draft_editable(x)) return(x)
    title <- if (state$stage == "Plan" && !is.null(input$study_title)) input$study_title else draft_title(x)
    liking <- if (state$stage == "Questions" && !is.null(input$include_liking)) input$include_liking else length(x$study$questions) > 0L
    prompt <- if (state$stage == "Questions" && !is.null(input$question_prompt)) input$question_prompt else
      if (length(x$study$questions)) x$study$questions[[1]]$prompt else "How much do you like this design?"
    x <- revise_draft(x, title, liking, prompt)
    if (state$stage == "Plan" && !is.null(input$control_condition)) {
      rationale <- if (!is.null(input$control_rationale)) input$control_rationale else comparison_settings(x$study)$rationale
      x <- revise_comparison(x, input$control_condition, rationale)
    }
    if (state$stage == "Plan" && !is.null(input$presentation_order)) {
      seconds <- if (!is.null(input$viewing_seconds)) input$viewing_seconds else presentation_settings(x$study)$viewing_duration_ms / 1000
      x <- revise_presentation(x, input$presentation_order, seconds * 1000)
    }
    x
  }
  persist <- function(x = capture_changes()) {
    if (is.null(x)) return(invisible(NULL))
    if (!dir.exists(store_dir)) record_assert(dir.create(store_dir, recursive = TRUE), "Could not create the local drafts folder.")
    path <- state$path
    if (is.null(path)) path <- tempfile("draft-", tmpdir = store_dir, fileext = ".json")
    receipt <- save_bundle(x, path, overwrite = !is.null(state$path), expected_fingerprint = state$fingerprint)
    state$bundle <- x; state$path <- receipt$path; state$fingerprint <- receipt$fingerprint
    if (!identical(state$report_revision, x$study$revision)) state$sample_report <- NULL
    if (!is.null(state$protocol) && state$protocol$study$revision != x$study$revision) state$protocol <- NULL
    if (!identical(state$import_revision, x$study$revision)) {
      state$import_report <- NULL; state$import_path <- NULL
    }
    state$message <- paste("Saved on this computer at", format(Sys.time(), "%H:%M"))
    state$library_version <- state$library_version + 1L
    session$sendCustomMessage("draft-saved", list())
  }
  go_to <- function(stage) {
    if (attempt(persist)) {
      if (stage == "Results" && identical(state$bundle$session$mode, "sample")) {
        attempt(function() {
          state$sample_report <- build_sample_report(state$bundle)
          state$report_revision <- state$bundle$study$revision
        })
      }
      state$stage <- stage
      session$sendCustomMessage("focus-study", list())
    }
  }
  shiny::observeEvent(input$new_study, open_draft(create_draft("preview")))
  shiny::observeEvent(input$open_sample, open_draft(create_draft("sample")))
  shiny::observeEvent(input$save_protocol_snapshot, attempt(function() {
    persist()
    state$protocol <- save_draft_protocol(state$bundle, state$path)
    state$message <- "Protocol snapshot saved on this computer"
  }))
  shiny::observeEvent(input$copy_for_import, attempt(function() {
    x <- copy_draft_for_import(capture_changes())
    open_draft(x); persist(x); state$stage <- "Collect"
  }))
  shiny::observeEvent(input$gaze_csv, attempt(function() {
    upload <- input$gaze_csv
    shiny::req(upload$datapath)
    x <- capture_changes()
    record_assert(draft_editable(x) && identical(x$session$mode, "preview"),
      "Create a working copy before importing prepared data.")
    record_assert(length(x$study$aois) <= 40, "This local import supports up to 40 areas. Larger analyses need the R workflow.")
    persist(x)
    shiny::withProgress(message = "Checking and calculating prepared intervals", value = 0, {
      report <- build_prepared_report(x, upload$datapath, max_bytes = 1024^2, max_rows = 20000, max_participants = 500)
      shiny::incProgress(0.7)
      path <- save_draft_analysis(report, state$path)
      state$import_report <- report; state$import_revision <- x$study$revision; state$import_path <- path
      state$stage <- "Results"; state$message <- "Prepared analysis saved on this computer"
      session$sendCustomMessage("focus-study", list())
    })
  }))
  shiny::observeEvent(input$save_draft, attempt(persist))
  shiny::observeEvent(input$continue, {
    go_to(research_stages[min(match(state$stage, research_stages) + 1L, length(research_stages))])
  })
  for (stage in research_stages) local({
    selected <- stage
    shiny::observeEvent(input[[paste0("stage_", tolower(selected))]], go_to(selected))
  })
  shiny::observeEvent(input$home, {
    if (is.null(state$bundle) || attempt(persist)) {
      state$bundle <- NULL; state$message <- ""; state$error <- NULL
    }
  })
  shiny::observeEvent(input$open_saved, attempt(function() {
    entries <- list_drafts(store_dir)
    allowed <- vapply(entries, function(e) e$path, character(1))
    record_assert(text_choice(input$saved_file, allowed), "Choose a saved study first.")
    open_draft(read_bundle(input$saved_file), input$saved_file)
  }))
  shiny::observeEvent(input$import_file, attempt(function() {
    shiny::req(input$import_file$datapath)
    open_draft(read_bundle(input$import_file$datapath))
    state$message <- "JSON draft opened \u00b7 Save draft to keep a local copy"
  }))
  for (i in 1:2) local({
    index <- i
    input_id <- paste0("stimulus_", c("a", "b")[[i]])
    shiny::observeEvent(input[[input_id]], attempt(function() {
      upload <- input[[input_id]]
      shiny::req(upload$datapath)
      x <- capture_changes()
      asset <- new_png_asset(upload$datapath, x$study$stimulus_ids[[index]])
      persist(set_stimulus_asset(x, asset))
    }))
  })
  output$export_draft <- shiny::downloadHandler(
    filename = function() "research-study.json",
    content = function(file) .write_draft_bytes(bundle_to_json(capture_changes(), pretty = TRUE), file),
    contentType = "application/json"
  )
  output$export_sample_report <- shiny::downloadHandler(filename = function() "sample-analysis.json",
    content = function(file) {
      record_assert(!is.null(state$sample_report) && identical(state$report_revision, state$bundle$study$revision),
                    "Return to Results to recalculate the sample first.")
      .write_draft_bytes(sample_report_to_json(state$sample_report, pretty = TRUE), file)
    }, contentType = "application/json")
  output$export_import_report <- shiny::downloadHandler(filename = function() "prepared-gaze-analysis.json",
    content = function(file) {
      record_assert(!is.null(state$import_report) && identical(state$import_revision, state$bundle$study$revision),
        "Import prepared data for this study revision first.")
      .write_draft_bytes(prepared_report_to_json(state$import_report, pretty = TRUE), file)
    }, contentType = "application/json")
  output$export_gaze_template <- shiny::downloadHandler(filename = function() "prepared-gaze-columns.csv",
    content = function(file) writeLines("participant_id,stimulus_id,start_ms,end_ms,x,y,valid,phase", file),
    contentType = "text/csv")
  output$export_protocol <- shiny::downloadHandler(filename = function() "study-protocol.json",
    content = function(file) {
      record_assert(!is.null(state$protocol), "Save a protocol snapshot first.")
      .write_draft_bytes(protocol_to_json(state$protocol, pretty = TRUE), file)
    }, contentType = "application/json")
  output$save_status <- shiny::renderText(state$message)
  output$error_panel <- shiny::renderUI({
    if (!is.null(state$error)) shiny::div(class = "error-panel", role = "alert",
      shiny::strong("The action could not be completed. "), state$error)
  })
  output$navigation <- shiny::renderUI({
    x <- state$bundle
    shiny::tags$aside(class = "side-panel", `aria-label` = "Study navigation",
      shiny::actionButton("home", "My studies", class = "library-link"),
      if (!is.null(x)) shiny::tagList(
        shiny::div(class = "eyebrow", "STUDY WORKSPACE"),
        shiny::tags$nav(`aria-label` = "Study stages", lapply(seq_along(research_stages), function(i) {
          stage <- research_stages[[i]]
          shiny::actionButton(paste0("stage_", tolower(stage)),
            shiny::tagList(shiny::span(class = "step-number", i), stage),
            class = paste("stage-link", if (state$stage == stage) "selected"),
            `aria-current` = if (state$stage == stage) "step" else "false")
        })),
        shiny::div(class = "side-note", "Start with one question. The study structure and linked liking item are prepared for you.")))
  })
  output$workspace <- shiny::renderUI({
    x <- state$bundle
    if (is.null(x)) {
      state$library_version
      entries <- list_drafts(store_dir)
      choices <- setNames(vapply(entries, function(e) e$path, character(1)),
                          vapply(entries, function(e) paste(e$title, "\u00b7", e$mode, "\u00b7", format(file.info(e$path)$mtime, "%d %b %H:%M")), character(1)))
      return(shiny::tagList(
        shiny::div(class = "eyebrow", "YOUR RESEARCH, CONNECTED"),
        shiny::h1("A clearer start to your next study."),
        shiny::p(class = "lead", "Prepare an eye-tracking study with two designs and an optional liking question. Save it here and pick up where you left off."),
        shiny::div(class = "welcome-grid",
          shiny::div(class = "panel primary-panel", shiny::span(class = "eyebrow", "START WITH A TEMPLATE"),
            shiny::h2("Compare two designs"), shiny::p("A paired study structure with a ready-to-use seven-point liking question."),
            shiny::actionButton("new_study", "Create study", class = "btn-primary")),
          shiny::div(class = "panel", shiny::span(class = "eyebrow", "EXPLORE FIRST"),
            shiny::h2("Try the guided sample"), shiny::p("Two prepared designs, named areas and a reproducible calculation using fictional gaze intervals."),
            shiny::actionButton("open_sample", "Open guided sample", class = "btn-outline-primary"))),
        shiny::div(class = "panel library-panel", shiny::h2("Your saved studies"),
          if (length(entries)) shiny::tagList(shiny::selectInput("saved_file", "Choose a study", choices, selectize = FALSE),
            shiny::actionButton("open_saved", "Open study", class = "btn-outline-primary")) else
              shiny::p(class = "muted", "Your first saved study will appear here."),
          shiny::tags$details(shiny::tags$summary("Open a draft JSON file"),
            shiny::fileInput("import_file", "Draft JSON file (up to 16 MB)", accept = ".json", buttonLabel = "Choose file"))),
        shiny::div(class = "scope-note", "AVAILABLE NOW", shiny::p("Study planning, control stimuli, image areas, a linked liking question, prepared-data import and reproducible draft calculations. The guided sample uses fictional data. Participant recording and raw device-file conversion are still being built."))))
    }
    editable <- draft_editable(x)
    badge <- if (x$session$mode == "sample") "SAMPLE \u00b7 NO PARTICIPANT DATA" else paste(toupper(x$session$mode), "\u00b7 DRAFT")
    heading <- shiny::div(class = "study-heading", shiny::div(shiny::span(class = "origin-badge", badge),
      shiny::h1(draft_title(x)), shiny::p(class = "muted", "Paired eye-tracking study \u00b7 two designs \u00b7 optional explicit liking")),
      shiny::div(class = "study-actions", shiny::downloadButton("export_draft", "Export JSON", icon = NULL, class = "btn-outline-secondary"),
        shiny::actionButton("save_draft", "Save draft", class = "btn-primary")))
    body <- switch(state$stage,
      Plan = shiny::tagList(
        shiny::div(class = "panel", shiny::span(class = "eyebrow", "1 / PLAN"), shiny::h2("What would you like to compare?"),
          if (editable) shiny::textInput("study_title", "Study name", draft_title(x), placeholder = "e.g. Which packaging gets noticed?") else shiny::p("This imported bundle is read-only because it contains recording metadata or a pilot/live origin."),
          shiny::p("The same participant will view design A and design B. Eye tracking will measure where they look; the separate liking question asks what they prefer."),
          if (editable) shiny::tagList(
            shiny::selectInput("control_condition", "What is the comparison?", selectize = FALSE,
              choices = c("Two designs, no designated control" = "none", "A is the control; B is the test" = "A", "B is the control; A is the test" = "B"),
              selected = comparison_settings(x$study)$control_condition),
            shiny::conditionalPanel("input.control_condition !== 'none'",
              shiny::textAreaInput("control_rationale", "Why is this a suitable control? (optional draft note)",
                comparison_settings(x$study)$rationale, rows = 2, placeholder = "e.g. The current packaging; only the brand position changes."),
              shiny::p(class = "muted", "Keep the viewing task and presentation conditions comparable. A control label records your design choice; it does not establish a causal effect."))) else
                shiny::p(comparison_caption(x$study)),
          shiny::div(class = "stimulus-grid",
            stimulus_card(x, 1, editable), stimulus_card(x, 2, editable)),
          shiny::p(class = "muted", "PNG images, up to 5 MB each. Images are saved inside your draft and included in JSON exports."),
          shiny::div(class = "info-note", "Define matching named areas to compare them. Replacing an image clears its areas.")),
        shiny::div(class = "panel", shiny::h2("Plan a comparable viewing experience."),
          if (editable) shiny::tagList(
            shiny::selectInput("presentation_order", "Planned presentation order", selectize = FALSE,
              choices = c("Counterbalance: plan both A then B and B then A" = "counterbalanced_ab_ba", "Fixed: A then B" = "fixed_ab", "Fixed: B then A" = "fixed_ba"),
              selected = presentation_settings(x$study)$order),
            shiny::numericInput("viewing_seconds", "Planned viewing time for each design (seconds)",
              value = presentation_settings(x$study)$viewing_duration_ms / 1000, min = 0.5, max = 600, step = 0.5)),
          shiny::p(class = "muted", "Both designs share the same planned duration. Five seconds is an editable starting preset; choose a duration appropriate to your research question. Review shows the full sequence."),
          shiny::p(class = "muted", "A and B identify designs, not which comes first. Presentation timing and order assignment are not active yet."))),
      Questions = shiny::tagList(
        shiny::div(class = "panel", shiny::span(class = "eyebrow", "2 / QUESTIONS"), shiny::h2("Pair attention with what people tell you."),
          shiny::p("This question appears after each design. Its answers stay linked to that design and separate from the viewing period."),
          if (editable) shiny::tagList(
            shiny::checkboxInput("include_liking", "Include a liking question after each design", length(x$study$questions) > 0),
            shiny::conditionalPanel("input.include_liking === true",
              shiny::textAreaInput("question_prompt", "Question wording", if (length(x$study$questions)) x$study$questions[[1]]$prompt else "How much do you like this design?", rows = 2),
              shiny::div(class = "question-preview", shiny::span(class = "eyebrow", "ANSWER SCALE \u00b7 PREVIEW ONLY"),
                shiny::div(class = "liking-scale", lapply(1:7, function(n) shiny::span(n))),
                shiny::div(class = "scale-labels", shiny::span("Not at all"), shiny::span("Very much")),
                shiny::p(class = "muted", "Skipping is stored separately from a rating. The preview does not record an answer.")))) else
                  shiny::p(if (length(x$study$questions)) x$study$questions[[1]]$prompt else "No liking question included."))),
      Collect = shiny::tagList(prepared_import_ui(x), shiny::div(class = "panel", shiny::span(class = "eyebrow", "3 / COLLECT"), shiny::h2("Device recording is a later step."),
        shiny::p("Live collection is not available in this build. No camera, eye tracker or other sensor is recording."),
        shiny::div(class = "future-grid", shiny::div(shiny::h3("Convert device exports"), shiny::p("Planned: prepare raw eye-tracker files with source-specific timing, coordinates and quality checks.")),
          shiny::div(shiny::h3("Record a session"), shiny::p("Planned: guided device checks, webcam and lab acquisition."))),
        shiny::p(class = "muted", "Your saved draft will remain available as collection features arrive."))),
      Review = shiny::tagList(shiny::div(class = "panel", shiny::span(class = "eyebrow", "4 / REVIEW"), shiny::h2("A readable check of your draft."),
        shiny::tags$dl(class = "summary-list",
          shiny::tags$dt("Design"), shiny::tags$dd("Same participants, two images (A and B)"),
          shiny::tags$dt("Control comparison"), shiny::tags$dd(comparison_caption(x$study)),
          shiny::tags$dt("Control rationale"), shiny::tags$dd(if (nzchar(comparison_settings(x$study)$rationale)) comparison_settings(x$study)$rationale else "No note recorded"),
          shiny::tags$dt("Questionnaire"), shiny::tags$dd(if (length(x$study$questions)) "One linked, seven-point liking item" else "Not included"),
          shiny::tags$dt("Study images"), shiny::tags$dd(paste(length(x$study$stimulus_assets), "of 2 attached")),
          shiny::tags$dt("Areas of interest"), shiny::tags$dd(paste(length(x$study$aois), "rectangular areas defined")),
          shiny::tags$dt("Prepared analysis"), shiny::tags$dd(if (!is.null(state$import_report)) "Saved for this study revision" else "No import for this revision"),
          shiny::tags$dt("Origin"), shiny::tags$dd(x$session$mode),
          shiny::tags$dt("Draft checks"), shiny::tags$dd("Study and response references are internally consistent")),
        shiny::div(class = "info-note", "These are data-structure checks. Recording quality and scientific validation have not been assessed.")),
        presentation_preview_ui(x$study), protocol_snapshot_ui(x, state$protocol)),
      Results = if (!is.null(state$import_report)) sample_results_ui(state$import_report) else if (!is.null(state$sample_report)) sample_results_ui(state$sample_report) else shiny::div(class = "panel", shiny::span(class = "eyebrow", "5 / RESULTS"), shiny::h2("Results will start with evidence."),
        shiny::p("Open Collect to import prepared intervals for this study revision, or open a guided sample from My studies to explore a fictional worked example."),
        shiny::div(class = "info-note", "Raw device-file conversion and a qualified analysis recipe are still being built. No statistical test has been computed.")))
    shiny::tagList(heading, body,
      shiny::div(class = "bottom-actions", shiny::span(class = "muted", "Changes save when you continue or switch stages."),
        if (state$stage != "Results") shiny::actionButton("continue", paste("Continue to", research_stages[match(state$stage, research_stages) + 1]), class = "btn-primary")))
  })
  bind_aoi_editor(input, output, session, state, capture_changes, persist, attempt)
}
