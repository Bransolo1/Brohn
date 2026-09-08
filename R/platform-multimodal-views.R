# Synthesis authoring keeps report selection, identity review and declared
# comparisons separate. No browser-supplied measure definition is trusted.
brohn_mm_metric_label <- function(metric, design) {
  outcome <- metric$outcome_id
  question <- brohn_find(design$questions, outcome)
  if (!is.null(question)) outcome <- question$prompt
  paste(toupper(metric$modality), gsub("_", " ", metric$metric), "\u00b7", outcome, paste0(" (", metric$unit, ")"))
}
brohn_mm_crosswalk_from_input <- function(catalog, mode, input, uploaded = NULL) {
  brohn_require(mode %in% c("source_codes", "edit", "file"), "Choose how to review participant links.")
  if (mode == "file") {
    brohn_require(!is.null(uploaded), "Upload a reviewed identity mapping first.")
    return(uploaded)
  }
  if (mode == "edit") brohn_require(length(catalog$identities) <= 100L, "Use a mapping file for more than 100 source identities.")
  rows <- lapply(seq_along(catalog$identities), function(i) {
    row <- catalog$identities[[i]]
    person <- if (mode == "source_codes") row$source_participant_id else trimws(brohn_default(input[[paste0("mm_person_", i)]], ""))
    visit <- if (mode == "source_codes") row$source_session_id else trimws(brohn_default(input[[paste0("mm_session_", i)]], ""))
    if (!nzchar(person) && !nzchar(visit)) return(NULL)
    brohn_require(nzchar(person) && nzchar(visit), "Supply both person and session, or leave both blank to keep that source unlinked.")
    c(row[c("report_id", "source_participant_id", "source_session_id")], list(participant_id = person, session_id = visit))
  })
  Filter(Negate(is.null), rows)
}
brohn_mm_read_crosswalk <- function(path, filename, catalog) {
  brohn_require(file.info(path)$size <= 16*1024^2, "Identity mapping exceeds 16 MiB.")
  rows <- if (tolower(tools::file_ext(filename)) == "json") brohn_read_json_file(path, maximum = 16*1024^2) else {
    brohn_require(tolower(tools::file_ext(filename)) == "csv", "Upload an identity mapping in CSV or JSON.")
    brohn_rows(brohn_read_table(path, "csv", max_rows = 20000L))
  }
  .brohn_mm_validate_crosswalk(rows, vapply(catalog$sources, `[[`, character(1), "report_id"))
  known <- vapply(catalog$identities, function(r) .brohn_mm_key(r$report_id, r$source_participant_id, r$source_session_id), character(1))
  supplied <- vapply(rows, function(r) .brohn_mm_key(r$report_id, r$source_participant_id, r$source_session_id), character(1))
  brohn_require(all(supplied %in% known), "The mapping includes a source person/session absent from the selected reports.")
  rows
}
brohn_install_multimodal_ui <- function(input, output, session, store, state, current, attempt, message, refresh) {
  mm <- shiny::reactiveValues(selection = NULL, contrasts = list(), uploaded = NULL)
  source_label <- function(id) {
    item <- Filter(function(r) r$id == id, mm$selection$records)
    if (!length(item)) id else paste(item[[1]]$body$title, substr(id, nchar(id)-5L, nchar(id)))
  }
  shiny::observeEvent(input$combine_measures, attempt(function() {
    study <- brohn_study(store, input$combine_measures)
    choices <- brohn_source_report_choices(store, study$id)
    brohn_require(length(choices) > 0, "Save a source report before combining measures.")
    current$mm_study <- study$id
    shiny::showModal(shiny::modalDialog(title = "Combine study measures", size = "l",
      shiny::p("Choose saved reports from the same study and collection origin. Each measure keeps its own eligible people and sessions."),
      shiny::selectizeInput("mm_reports", "Source reports", choices = NULL, multiple = TRUE, options = list(placeholder = "Search this study's saved reports", maxOptions = 100)),
      shiny::selectInput("mm_origin", "Collection origin", c("Pilot" = "pilot", "Live" = "live", "Imported, origin unclassified" = "imported", "Sample" = "sample", "Preview" = "preview", "Unspecified" = "unspecified")),
      shiny::selectInput("mm_design_policy", "Design versions", c("Exactly the same frozen design" = "exact", "Allow later AOI edits; participant-facing design must match" = "measurement_compatible_aoi_revision")),
      shiny::p("AOI compatibility allows regions to be refined after collection. Different timing, stimuli, task scoring or questionnaires still require separate analyses."),
      footer = shiny::tagList(shiny::modalButton("Cancel"), shiny::actionButton("mm_review", "Review participants and measures", class = "btn-primary"))))
    shiny::updateSelectizeInput(session, "mm_reports", choices = choices, selected = character(), server = TRUE)
  }))
  shiny::observeEvent(input$mm_review, attempt(function() {
    ids <- as.list(input$mm_reports)
    catalog <- brohn_multimodal_catalog(store, current$mm_study, ids, input$mm_origin, input$mm_design_policy)
    selection <- .brohn_mm_select(store, current$mm_study, ids, input$mm_origin, input$mm_design_policy)
    mm$selection <- c(selection, list(catalog = catalog, report_ids = ids, origin = input$mm_origin, policy = input$mm_design_policy))
    mm$contrasts <- list(); mm$uploaded <- NULL
    metrics <- stats::setNames(vapply(catalog$metrics, `[[`, character(1), "id"), vapply(catalog$metrics, brohn_mm_metric_label, character(1), design = selection$design))
    conditions <- stats::setNames(brohn_ids(selection$design$conditions), vapply(selection$design$conditions, `[[`, character(1), "label"))
    control <- Filter(function(c) c$role == "control", selection$design$conditions)
    test <- Filter(function(c) c$role == "test", selection$design$conditions)
    shiny::showModal(shiny::modalDialog(title = "Review how these measures belong together", size = "l",
      shiny::h2("1. Link people and sessions"),
      shiny::p(paste(length(catalog$identities), "source person/session identities. Identical text is linked only after your explicit review.")),
      shiny::selectInput("mm_identity_mode", "Identity review", c("Use the exact source codes after review" = "source_codes", "Edit shared person and session codes" = "edit", "Upload a reviewed mapping" = "file")),
      shiny::uiOutput("mm_identity_editor"),
      shiny::textAreaInput("mm_identity_source", "Evidence for these participant links", "", width = "100%", rows = 2,
        placeholder = "For example: participant register and visit log; explain any differences in source codes."),
      shiny::checkboxInput("mm_identity_confirmed", "I checked that shared person and session codes refer to the same people and visits", FALSE),
      shiny::h2("2. Choose comparisons"),
      shiny::p("Add the outcomes you intend to compare, or keep a descriptive report with no tests. Comparisons chosen after inspecting results are exploratory."),
      if (length(metrics)) shiny::tagList(shiny::selectInput("mm_metric", "Measure and outcome", metrics),
        shiny::div(class = "brohn-form-grid", shiny::selectInput("mm_control", "Reference condition", conditions, if (length(control)) control[[1]]$id else NULL),
          shiny::selectInput("mm_test", "Comparison condition", conditions, if (length(test)) test[[1]]$id else NULL)),
        shiny::actionButton("mm_add_contrast", "Add comparison")) else shiny::p("No registered numerical measures are available in this selection."),
      shiny::uiOutput("mm_comparisons"),
      shiny::numericInput("mm_alpha", "Family error threshold (Holm correction)", .05, min = .0001, max = .2, step = .01),
      shiny::p("Repeated observations are averaged within condition and session, then session differences within person. People receive equal weight; missing measures retain separate denominators."),
      shiny::tags$details(shiny::tags$summary("Source availability and measure definitions"), brohn_table(catalog$sources, label = "Selected report availability"),
        brohn_table(catalog$metrics, columns = c("label", "source_rows", "eligible_source_rows", "definition_hashes"), label = "Available measure definitions")),
      footer = shiny::tagList(shiny::modalButton("Cancel"), shiny::actionButton("mm_queue", "Save combined report", class = "btn-primary"))))
  }))
  output$mm_identity_editor <- shiny::renderUI({
    s <- mm$selection; shiny::req(s)
    rows <- s$catalog$identities; mode <- input$mm_identity_mode
    if (identical(mode, "edit")) return(if (length(rows) > 100L) shiny::p("More than 100 source identities: use the downloadable mapping template to review these efficiently.") else
      shiny::tagList(lapply(seq_along(rows), function(i) {
        r <- rows[[i]]
        shiny::tags$fieldset(class = "brohn-card", shiny::tags$legend(paste("Source", i, "\u00b7", source_label(r$report_id))),
          shiny::p(paste("Person:", r$source_participant_id, "\u00b7 Session:", r$source_session_id)),
          shiny::div(class = "brohn-form-grid", shiny::textInput(paste0("mm_person_", i), paste("Shared person code", i), r$source_participant_id),
            shiny::textInput(paste0("mm_session_", i), paste("Shared session code", i), r$source_session_id)))
      }), shiny::p("Leave both shared codes blank to retain a source without linking it.")))
    if (identical(mode, "file")) return(shiny::tagList(shiny::downloadButton("mm_crosswalk_template", "Download mapping template", icon = NULL),
      shiny::p("Fill participant_id and session_id with shared codes. Remove rows that should remain unlinked. Keep report_id and source identities unchanged."),
      shiny::fileInput("mm_crosswalk_file", "Reviewed identity mapping (CSV or JSON)", accept = c(".csv", ".json")), shiny::uiOutput("mm_mapping_status")))
    brohn_table(lapply(rows, function(r) list(report = source_label(r$report_id), source_participant_id = r$source_participant_id, source_session_id = r$source_session_id)), label = "Source codes to review")
  })
  output$mm_crosswalk_template <- shiny::downloadHandler(filename = function() "brohn-participant-mapping.json", content = function(file) {
    rows <- lapply(mm$selection$catalog$identities, function(r) c(r[c("report_id", "source_participant_id", "source_session_id")], list(participant_id = "", session_id = "")))
    writeLines(enc2utf8(brohn_json(rows, TRUE)), file, useBytes = TRUE)
  }, contentType = "application/json")
  shiny::observeEvent(input$mm_crosswalk_file, attempt(function() {
    mm$uploaded <- NULL
    upload <- input$mm_crosswalk_file; shiny::req(upload$datapath, mm$selection)
    mm$uploaded <- brohn_mm_read_crosswalk(upload$datapath, upload$name, mm$selection$catalog)
  }))
  output$mm_mapping_status <- shiny::renderUI(if (!is.null(mm$uploaded)) shiny::p(role = "status", paste(length(mm$uploaded), "source identities in the reviewed mapping.")))
  shiny::observeEvent(input$mm_add_contrast, attempt(function() {
    s <- mm$selection; shiny::req(s)
    metric <- brohn_find(s$catalog$metrics, input$mm_metric)
    brohn_require(!is.null(metric), "Select an available measure.")
    next_contrast <- c(list(id = brohn_id("comparison")), metric[c("report_ids", "modality", "metric", "outcome_id", "unit")], list(control_id = input$mm_control, test_id = input$mm_test))
    contrasts <- c(mm$contrasts, list(next_contrast))
    .brohn_mm_validate_contrasts(contrasts, unlist(s$report_ids), s$design, list(method = "holm", alpha = input$mm_alpha))
    mm$contrasts <- contrasts
  }))
  shiny::observeEvent(input$mm_remove_contrast, {mm$contrasts <- Filter(function(c) c$id != input$mm_remove_contrast, mm$contrasts)})
  output$mm_comparisons <- shiny::renderUI({
    s <- mm$selection; shiny::req(s)
    if (!length(mm$contrasts)) return(shiny::p("Descriptive report: no comparisons declared."))
    shiny::tags$ul(lapply(mm$contrasts, function(c) shiny::tags$li(
      paste(brohn_mm_metric_label(c, s$design), "\u00b7", brohn_find(s$design$conditions, c$test_id)$label, "minus", brohn_find(s$design$conditions, c$control_id)$label),
      brohn_command("Remove comparison", "mm_remove_contrast", c$id))))
  })
  shiny::observeEvent(input$mm_queue, attempt(function() {
    s <- mm$selection; shiny::req(s)
    brohn_require(isTRUE(input$mm_identity_confirmed), "Confirm your review of participant and visit identities.")
    for (r in s$records) brohn_require(identical(brohn_hash(brohn_get_entity(store, "report", r$id)$body), brohn_hash(r$body)), "A source changed during review. Select the reports again.")
    crosswalk <- brohn_mm_crosswalk_from_input(s$catalog, input$mm_identity_mode, input, mm$uploaded)
    brohn_queue_multimodal(store, s$study$id, s$report_ids, crosswalk, mm$contrasts, s$origin,
      list(method = "holm", alpha = input$mm_alpha), identity_source = input$mm_identity_source, design_policy = s$policy)
    shiny::removeModal(); state$page <- "activity"; refresh(); message("Combined report queued with the reviewed identity links and comparisons.")
  }))
  invisible(TRUE)
}
