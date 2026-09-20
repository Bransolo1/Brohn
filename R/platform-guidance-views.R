# Guided researcher entry and study overview. These views describe saved state;
# they never qualify a device, release a study or create participant observations.
.brohn_guidance_measure_labels <- c(gaze = "Eye tracking", questionnaire = "Questions", eeg = "EEG", eda = "Skin response",
  ecg = "ECG / HRV", ppg = "PPG", respiration = "Breathing", emg = "Muscle activity", eog = "Eye movement signals", fnirs = "fNIRS",
  temperature = "Temperature", movement = "Movement", webcam_gaze = "Webcam gaze", facial_geometry = "Face geometry",
  facial_expression = "Facial expression", pose = "Body geometry", voice = "Voice", rt = "Reaction time", iat = "IAT", biat = "Brief IAT", aat = "Approach / avoidance")
.brohn_guidance_stages <- c("Overview", "Plan", "Questions", "Tasks", "Collect", "Review", "Results", "History")
.brohn_guidance_count <- function(n, singular, plural = paste0(singular, "s")) paste(n, if (n == 1) singular else plural)
.brohn_guidance_binding <- function(record) list(study_id = record$id, revision = record$revision, design_hash = brohn_hash(record$body))
.brohn_guidance_command <- function(label, record, stage, primary = FALSE, focus = "brohn-main") {
  brohn_command(label, "guidance_stage", c(.brohn_guidance_binding(record), list(stage = stage, focus = focus)),
    class = if (primary) "btn btn-primary" else "btn btn-outline-secondary")
}

brohn_guidance_snapshot <- function(store, record) {
  brohn_project(store, record$project_id)
  brohn_require(identical(record$id, record$body$id) && identical(record$project_id, record$body$project_id), "Reopen this study in its original project.")
  read <- function() {
    # Aggregate current catalog metadata in SQLite. Never hydrate report analyses
    # or participant protocols just to draw the study overview.
    sources <- DBI::dbGetQuery(store$con, paste("SELECT e.kind,coalesce(json_extract(v.body_json,'$.status'),'') AS status,",
      "coalesce(json_extract(v.body_json,'$.origin'),'not_recorded') AS origin,count(*) AS n FROM entities e JOIN entity_versions v",
      "ON e.kind=v.kind AND e.id=v.id AND e.revision=v.revision WHERE e.project_id=? AND e.kind IN ('dataset','report')",
      "AND json_extract(v.body_json,'$.study_id')=? GROUP BY e.kind,status,origin"), params = list(record$project_id, record$id))
    deployments <- if (DBI::dbExistsTable(store$con, "delivery_deployments")) DBI::dbGetQuery(store$con,
      "SELECT status,origin,design_revision,count(*) AS n FROM delivery_deployments WHERE project_id=? AND study_id=? GROUP BY status,origin,design_revision",
      params = list(record$project_id, record$id)) else data.frame(status = character(), origin = character(), design_revision = integer(), n = integer())
    runs <- if (DBI::dbExistsTable(store$con, "delivery_runs")) DBI::dbGetQuery(store$con, paste(
      "SELECT r.completion_status,r.transfer_status,r.origin,count(*) AS n FROM delivery_runs r JOIN delivery_deployments d ON r.deployment_id=d.id",
      "WHERE d.project_id=? AND r.study_id=? GROUP BY r.completion_status,r.transfer_status,r.origin"), params = list(record$project_id, record$id)) else
      data.frame(completion_status = character(), transfer_status = character(), origin = character(), n = integer())
    origins <- if (nrow(sources)) stats::aggregate(sources$n, list(kind = sources$kind, origin = sources$origin), sum) else data.frame(kind = character(), origin = character(), x = integer())
    list(datasets = sum(sources$n[sources$kind == "dataset"]), reports = sum(sources$n[sources$kind == "report"]),
      needs_mapping = sum(sources$n[sources$kind == "dataset" & sources$status == "needs_mapping"]),
      releases = sum(deployments$n), open_releases = sum(deployments$n[deployments$status == "open"]),
      paused_releases = sum(deployments$n[deployments$status == "paused"]), older_releases = sum(deployments$n[deployments$design_revision != record$revision]),
      sessions = sum(runs$n), completed_sessions = sum(runs$n[runs$completion_status == "completed"]),
      source_origins = lapply(seq_len(nrow(origins)), function(i) list(kind = origins$kind[[i]], origin = origins$origin[[i]], n = origins$x[[i]])),
      session_origins = if (nrow(runs)) stats::aggregate(runs$n, list(origin = runs$origin), sum) else data.frame(origin = character(), x = integer()))
  }
  if (RSQLite::sqliteIsTransacting(store$con)) read() else DBI::dbWithTransaction(store$con, read())
}
brohn_guidance_model <- function(record, snapshot) {
  d <- record$body; issues <- brohn_design_issues(d, TRUE)
  missing <- which(vapply(d$stimuli, function(s) if (s$type == "text") !nzchar(trimws(s$content)) else s$type %in% c("image", "audio", "video") && is.null(s$asset), logical(1)))
  materials <- length(d$stimuli) + length(d$questions) + length(d$blocks) + length(d$maxdiff)
  next_step <- list(title = "Prepare your participant release", description = "Review the collection origin, participant codes and collection routes before opening a saved study version.",
    label = "Prepare collection", stage = "Collect", focus = "brohn-main")
  if (length(issues)) next_step <- list(title = "Finish the design before release", description = issues[[1L]], label = "Continue planning", stage = "Plan", focus = "study_title")
  if (!materials) next_step <- list(title = "Give participants something to respond to", description = "Add a question, a study material or a configured task. Your starting design is already saved.",
    label = if (d$template == "survey") "Add your first question" else "Build your study", stage = if (d$template == "survey") "Questions" else "Plan", focus = if (d$template == "survey") "question_type" else "study_title")
  if (length(missing)) next_step <- list(title = "Add your comparison materials", description = paste(length(missing), if (length(missing) == 1L) "study material still needs content." else "study materials still need content.", "Name each concept and attach an image or write its participant text."),
    label = "Add study materials", stage = "Plan", focus = if (d$stimuli[[missing[[1L]]]]$type == "text") paste0("stimulus_text_", missing[[1L]]) else paste0("stimulus_title_", missing[[1L]]))
  if (snapshot$releases > 0) next_step <- list(title = if (snapshot$open_releases) "Your participant release is open" else "Return to collection", description = if (snapshot$open_releases)
      "Use the saved participant link and follow incoming sessions. New design edits leave that released version unchanged." else "Review the saved releases and choose whether to resume a paused release or prepare a new version.",
    label = "Open collection", stage = "Collect", focus = "brohn-main")
  if (snapshot$datasets > 0 || snapshot$sessions > 0) next_step <- list(title = "Follow the evidence you have collected", description = "Review linked datasets and session status. Completed sources and available results remain separate from missing or partial data.",
    label = "Review study data", stage = "Review", focus = "brohn-main")
  if (snapshot$reports > 0) next_step <- list(title = "Your saved results are ready to inspect", description = "Open a report to see its original source, usable support and frozen design. Different collection origins stay labelled.", label = "View saved results", stage = "Results", focus = "brohn-main")
  if (snapshot$needs_mapping > 0) next_step <- list(title = "Review the recordings waiting for mapping", description = paste(snapshot$needs_mapping,
    if (snapshot$needs_mapping == 1L) "dataset needs" else "datasets need", "column, unit and study-link checks before analysis."), label = "Review data mapping", stage = "Review", focus = "brohn-main")
  if (isTRUE(d$archived)) next_step <- list(title = "This study is preserved in your library", description = "Inspect saved designs, sessions and reports. Restore the study from History when you need to edit it again.", label = "Review preserved history", stage = "History", focus = "brohn-main")
  list(record = record, snapshot = snapshot, issues = issues, missing_materials = missing, next_step = next_step,
    sample = identical(d$lineage$operation, "original_sample_design"), design_ready = !length(issues),
    question_count = length(d$questions), task_count = length(d$blocks), stimuli_count = length(d$stimuli))
}
.brohn_guidance_example_image <- function(letter) {
  path <- file.path("examples", "stimuli", paste0("sample-design-", letter, ".png"))
  if (!file.exists(path) || file.info(path)$size > 1024^2) return(NULL)
  paste0("data:image/png;base64,", gsub("[\r\n]", "", jsonlite::base64_enc(readBin(path, "raw", file.info(path)$size))))
}
brohn_guided_home_ui <- function(store) {
  studies <- brohn_studies(store, limit = 4L)
  shiny::div(class = "brohn-guidance", brohn_page(if (length(studies)) "Welcome back to your research." else "Bring your whole study together.",
    "A clear path from your research question to evidence you can explain.",
    actions = shiny::actionButton("new_study", "Start my study", class = if (length(studies)) "btn-primary" else "btn-outline-secondary"),
    if (length(studies)) shiny::tags$section(`aria-labelledby` = "guidance-recent-title", shiny::h2(id = "guidance-recent-title", "Continue a study"),
      shiny::div(class = "brohn-guidance-recent", lapply(studies, function(record) {
        model <- tryCatch(brohn_guidance_model(record, brohn_guidance_snapshot(store, record)), error = function(e) NULL)
        brohn_card(title = record$body$title, subtitle = paste("Saved revision", record$revision),
          shiny::p(if (is.null(model)) "Open the study to review its saved state." else model$next_step$title),
          if (!is.null(model)) shiny::p(class = "brohn-muted", paste(.brohn_guidance_count(model$stimuli_count, "material"), "\u00b7", .brohn_guidance_count(model$question_count, "question"), "\u00b7", .brohn_guidance_count(model$snapshot$reports, "saved report"))),
          brohn_command("Open study overview", "brohn_open_study", record$id))
      }))),
    brohn_card(class = "brohn-guidance-example", title = "See how a complete study fits together",
      subtitle = "An original fictional packaging comparison, ready to explore and make your own.",
      shiny::div(class = "brohn-guidance-example-grid", shiny::div(
        brohn_badge("Practice design \u00b7 no participant data", "lavender"),
        shiny::h3("Which pack draws attention to the product label?"),
        shiny::p("Start with two concepts, a control comparison and a liking question after each exposure. Inspect the study sequence, then replace the materials when you are ready."),
        shiny::actionButton("open_sample", "Create a practice study", class = if (!length(studies)) "btn-primary" else "btn-outline-secondary"),
        shiny::p(class = "brohn-muted", "Creates a separate saved design. It contains no recorded responses or scientific results.")),
        shiny::div(class = "brohn-guidance-specimens", lapply(c("a", "b"), function(letter) shiny::tags$figure(
          shiny::tags$img(src = .brohn_guidance_example_image(letter), alt = paste("Original fictional packaging concept", toupper(letter))),
          shiny::tags$figcaption(paste("Concept", toupper(letter)))))))),
    shiny::tags$section(`aria-labelledby` = "guidance-route-title", shiny::h2(id = "guidance-route-title", "One study, five connected stages"),
      shiny::tags$ol(class = "brohn-guidance-path", lapply(seq_along(c("Plan", "Questions", "Collect", "Review", "Results")), function(i) {
        titles <- c("Plan", "Questions", "Collect", "Review", "Results"); descriptions <- c("Define the comparison and materials.", "Connect responses and tasks to the study.", "Release a saved design or import recordings.", "Resolve the source checks that need judgement.", "Inspect, explain and share the retained evidence.")
        shiny::tags$li(shiny::span(class = "brohn-guidance-step", i), shiny::div(shiny::h3(titles[[i]]), shiny::p(descriptions[[i]])))
      }))),
    brohn_card(title = "Bring a study structure you already trust", subtitle = "Reuse a saved design or import a portable Brohn study. Participant observations stay with their original study.",
      brohn_command("Browse design library", "guidance_templates", TRUE))))
}
brohn_start_study_ui <- function() shiny::modalDialog(title = "Start with your research question", size = "l",
  shiny::div(class = "brohn-guidance",
    shiny::p("Choose a starting structure. You can add measures, materials and tasks as the design develops."),
    shiny::textInput("new_title", "Study name", "My study", placeholder = "For example, Packaging clarity comparison"),
    shiny::radioButtons("new_template", "What will participants do?", c("Compare concepts or experiences" = "comparison", "Answer a questionnaire" = "survey", "Follow a custom study or task" = "blank")),
    shiny::conditionalPanel("input.new_template === 'comparison'", shiny::div(class = "brohn-guidance-start-note", shiny::strong("Your starting structure"),
      shiny::p("Two named conditions, two material slots and a liking question after each exposure. Counterbalanced order is selected; all settings remain inspectable."))),
    shiny::conditionalPanel("input.new_template === 'survey'", shiny::div(class = "brohn-guidance-start-note", shiny::strong("Your starting structure"),
      shiny::p("An empty questionnaire with participant information and consent fields. Add your wording, response types and any branching in Questions."))),
    shiny::conditionalPanel("input.new_template === 'blank'", shiny::div(class = "brohn-guidance-start-note", shiny::strong("Your starting structure"),
      shiny::p("A saved empty design. Add materials in Plan, explicit responses in Questions and supported procedures in Tasks."))),
    shiny::p(class = "brohn-muted", "Creating a design does not open recruitment, start recording or create participant data.")),
  footer = shiny::tagList(shiny::modalButton("Cancel"), shiny::actionButton("create_study", "Create study", class = "btn-primary")))

brohn_guidance_plan_intro_ui <- function(design) {
  if (nzchar(trimws(design$description))) return(NULL)
  brohn_card(class = "brohn-guidance-plan-intro", title = "Start with the question you want to answer",
    subtitle = "Your design is saved. Add the comparison and materials below, then use the overview to see the next step.",
    brohn_command("View study overview", "stage_overview", 1L))
}
brohn_study_overview_ui <- function(store, record) {
  tryCatch({
    model <- brohn_guidance_model(record, brohn_guidance_snapshot(store, record)); d <- record$body; s <- model$snapshot; next_step <- model$next_step
    jump <- function(label, stage, primary = FALSE, focus = "brohn-main") .brohn_guidance_command(label, record, stage, primary, focus)
    checkpoints <- list(
      list(title = "Plan", status = if (model$design_ready) "Design checks passed" else "Design needs attention", detail = paste(model$stimuli_count, "materials", "\u00b7", length(d$conditions), "conditions"), stage = "Plan"),
      list(title = "Questions and tasks", status = paste(.brohn_guidance_count(model$question_count, "question"), "\u00b7", .brohn_guidance_count(model$task_count, "task block")), detail = "Optional when your research design does not need them.", stage = if (model$question_count || !model$task_count) "Questions" else "Tasks"),
      list(title = "Collection", status = if (s$releases) paste(s$releases, "saved releases") else "No participant release yet", detail = paste(s$sessions, "sessions", "\u00b7", s$completed_sessions, "marked complete"), stage = "Collect"),
      list(title = "Review", status = if (s$needs_mapping) paste(s$needs_mapping, "datasets need mapping") else if (s$datasets) paste(s$datasets, "linked datasets") else "No imported datasets yet", detail = "Keep original sources and review their usable support.", stage = "Review"),
      list(title = "Results", status = if (s$reports) paste(s$reports, "saved reports") else "Waiting for analysed evidence", detail = "Every report keeps its original design and source.", stage = "Results"))
    shiny::div(class = "brohn-guidance", if (model$sample) shiny::div(class = "brohn-guidance-practice", brohn_badge("Practice design", "lavender"),
        shiny::p("These materials are fictional. Explore the saved design and sequence, then clone the structure for your own research.")),
      brohn_card(class = "brohn-guidance-next", title = next_step$title, subtitle = next_step$description,
        shiny::div(class = "brohn-toolbar", jump(next_step$label, next_step$stage, TRUE, next_step$focus),
          if (model$design_ready && !isTRUE(d$archived)) brohn_command("Preview participant sequence", "guidance_preview", .brohn_guidance_binding(record), id = "guidance-preview-open")),
        if (s$older_releases) shiny::p(class = "brohn-muted", paste(s$older_releases, "saved releases use an earlier design revision. They keep their original participant sequence."))),
      shiny::div(class = "brohn-guidance-overview-grid", brohn_card(title = "The question behind this study",
        shiny::p(if (nzchar(trimws(d$description))) d$description else "Write the research question and the primary comparison so the whole study has a clear purpose."),
        if (!isTRUE(d$archived)) jump(if (nzchar(trimws(d$description))) "Edit study purpose" else "Add the research question", "Plan", focus = "study_description"),
        shiny::tags$dl(class = "brohn-guidance-facts", shiny::tags$dt("Study design"), shiny::tags$dd(paste(length(d$conditions), "conditions", "\u00b7", model$stimuli_count, "materials")),
          shiny::tags$dt("Planned order"), shiny::tags$dd(switch(d$order, counterbalanced = "Counterbalanced rotation", fixed = "Fixed order", randomized = "Randomized per allocation")),
          shiny::tags$dt("Selected measures"), shiny::tags$dd(if (length(d$measures)) paste(unname(.brohn_guidance_measure_labels[unlist(d$measures)]), collapse = ", ") else "No measures selected")),
        shiny::p(class = "brohn-muted", "Selected measures describe intent. Review each collection route before collecting or interpreting its data.")),
        brohn_card(title = "Your saved study at a glance", shiny::div(class = "brohn-guidance-metrics",
          lapply(list(list(n = s$sessions, label = "Participant sessions"), list(n = s$datasets, label = "Linked datasets"), list(n = s$reports, label = "Saved reports")), function(item)
            shiny::div(shiny::strong(item$n), shiny::span(item$label)))),
          shiny::p(class = "brohn-muted", "Sessions are separate visits. These counts do not imply unique people, complete observations or scientific validity."),
          shiny::tags$details(shiny::tags$summary("Collection origins"),
            if (!nrow(s$session_origins) && !length(s$source_origins)) shiny::p("No recorded sources are linked yet. Sample, pilot, live and imported sources will remain labelled here.") else shiny::tagList(
              lapply(seq_len(nrow(s$session_origins)), function(i) shiny::p(paste(s$session_origins$origin[[i]], "\u00b7", s$session_origins$x[[i]], "sessions"))),
              lapply(s$source_origins, function(origin) shiny::p(paste(origin$origin, "\u00b7", origin$n, if (origin$kind == "report") "reports" else "datasets"))))))),
      brohn_card(title = "Move through the study", subtitle = "Each stage keeps the same saved study, materials and evidence together.",
        shiny::tags$ol(class = "brohn-guidance-checkpoints", lapply(checkpoints, function(checkpoint) shiny::tags$li(
          shiny::div(shiny::h3(checkpoint$title), shiny::strong(checkpoint$status), shiny::p(class = "brohn-muted", checkpoint$detail)),
          if (!isTRUE(d$archived) || checkpoint$stage %in% c("Review", "Results")) jump(paste("Open", tolower(checkpoint$title)), checkpoint$stage))))),
      if (length(model$issues)) brohn_card(title = "Before the next participant release", shiny::p(model$issues[[1L]]),
        shiny::p(class = "brohn-muted", "This is the current saved-design validation message. Recheck after making the correction; further checks may then become available."),
        if (!isTRUE(d$archived)) jump("Review planning details", "Plan")),
      shiny::tags$details(class = "brohn-guidance-disclosure", shiny::tags$summary("Review the collection route for each selected measure"), brohn_collection_routes_ui(d)),
      shiny::tags$details(class = "brohn-guidance-disclosure", shiny::tags$summary("Saved version and reuse"),
        shiny::p(paste("Design revision", record$revision, "\u00b7 last saved", record$updated_at)),
        shiny::p("Clone design creates a new draft. Save as template keeps a reusable structure. Export design includes its permitted materials; participant observations stay with this study."),
        jump("Open version history", "History")))
  }, error = function(e) brohn_card(title = "The study overview needs attention", shiny::p(conditionMessage(e)),
    shiny::p("Your saved study remains in the library. Open its history to inspect the retained version and reopen the overview after resolving access or source issues."),
    .brohn_guidance_command("Open study history", record, "History")))
}

brohn_guidance_preview_ui <- function(preview, offset = 0L) {
  protocol <- preview$protocol; total <- length(protocol$timeline); steps <- head(tail(protocol$timeline, max(0L, total-offset)), 25L)
  shiny::tagList(shiny::p("Example allocation 1 from this exact saved design. This preview creates no participant session and records no responses."),
    shiny::p(paste("Design revision", preview$record$revision, "\u00b7", total, "outer study steps")),
    shiny::h3(id = "guidance-preview-page-title", tabindex = "-1", "Saved study steps"),
    shiny::p(role = "status", paste("Showing", if (length(steps)) offset+1L else 0L, "to", offset+length(steps), "of", total, "study steps")),
    shiny::tags$ol(class = "brohn-guidance-preview", start = offset+1L, lapply(steps, function(step) {
      title <- switch(step$type, instructions = "Participant instructions", baseline = "Baseline", fixation = "Fixation cue", stimulus = brohn_default(step$stimulus$title, "Study material"),
        question = if (identical(step$question$type, "information")) "Information" else "Question", task = "Configured task block", maxdiff = "Best-worst choice", questionnaire_review = "Questionnaire answer review", "Study step")
      shiny::tags$li(shiny::h3(title), shiny::p(switch(step$type, instructions = step$text, question = step$question$prompt,
        stimulus = if (identical(step$stimulus$type, "text")) step$stimulus$content else "Saved media asset", task = "This block retains its own trial timeline. Review the complete procedure and mappings in Tasks.",
        maxdiff = step$choice$prompt, questionnaire_review = "Review the answers in this questionnaire occurrence before continuing. Displayed questions still follow their saved visibility rules.",
        paste("Saved duration:", brohn_default(step$duration_ms, "Unavailable"), "ms"))),
        if (!is.null(step$condition_id)) shiny::p(class = "brohn-muted", paste("Condition:", step$condition_id, "\u00b7 stimulus:", step$stimulus_id)),
        if (!is.null(step$question$options) && length(step$question$options)) shiny::p(paste("Response options:", paste(vapply(step$question$options, `[[`, character(1), "label"), collapse = " / "))))
    })),
    shiny::div(class = "brohn-toolbar", if (offset > 0) brohn_command("Previous study steps", "guidance_preview_page", list(identity = preview$identity, offset = offset, direction = -1L)),
      if (offset+length(steps) < total) brohn_command("Next study steps", "guidance_preview_page", list(identity = preview$identity, offset = offset, direction = 1L))),
    shiny::tags$details(shiny::tags$summary("Exact saved source"), shiny::p(paste("Study:", preview$record$id)), shiny::p(paste("Design SHA-256:", protocol$design_hash)),
      shiny::p("Study order, question placement and task blocks come from the saved compiler. This inspection does not qualify physical display or response timing.")))
}
brohn_install_guidance_ui <- function(input, output, session, store, state, current, attempt, capture, refresh) {
  preview <- shiny::reactiveVal(NULL); offset <- shiny::reactiveVal(0L)
  bound <- function(command) {
    record <- current$study
    brohn_require(identical(state$page, "study") && !is.null(record) && identical(command$study_id, record$id) &&
      identical(as.numeric(command$revision), as.numeric(record$revision)) && identical(command$design_hash, brohn_hash(record$body)),
      "This saved study changed. Reopen its overview before following this action.")
    brohn_project(store, record$project_id)
    saved <- brohn_study(store, record$id)
    brohn_require(identical(saved$revision, record$revision) && identical(brohn_hash(saved$body), command$design_hash), "A newer study version is available. Reopen it before continuing.")
    record
  }
  shiny::observeEvent(input$guidance_stage, attempt(function() {
    command <- input$guidance_stage; record <- bound(command)
    brohn_require(command$stage %in% .brohn_guidance_stages && (!isTRUE(record$body$archived) || command$stage %in% c("Overview", "History", "Review", "Results")), "Restore this study before editing its design.")
    focus <- brohn_default(command$focus, "brohn-main")
    brohn_require(brohn_text(focus, 96) && (focus %in% c("brohn-main", "study_title", "study_description", "question_type") || grepl("^stimulus_(text|title)_[1-9][0-9]{0,2}$", focus)), "Use a current study preparation action.")
    capture(); state$stage <- command$stage; refresh()
    session$onFlushed(function() session$sendCustomMessage("brohn-focus", focus), once = TRUE)
  }))
  shiny::observeEvent(input$guidance_templates, attempt(function() {
    capture(); shiny::removeModal(); state$page <- "designs"; refresh(); session$sendCustomMessage("brohn-navigation", list(page = "designs", focus = TRUE))
  }))
  shiny::observeEvent(input$guidance_preview, attempt(function() {
    record <- bound(input$guidance_preview); protocol <- brohn_compile(record$body, 1L)
    preview(list(record = record[c("id", "revision")], protocol = protocol, identity = brohn_hash(list(study = record$id, revision = record$revision, design_hash = protocol$design_hash))))
    offset(0L)
    shiny::showModal(shiny::modalDialog(title = "Preview the saved participant sequence", size = "l", shiny::uiOutput("guidance_preview_content"),
      footer = shiny::actionButton("guidance_preview_close", "Close preview"), easyClose = FALSE))
  }))
  output$guidance_preview_content <- shiny::renderUI({p <- preview(); shiny::req(p); brohn_guidance_preview_ui(p, offset())})
  shiny::observeEvent(input$guidance_preview_page, attempt(function() {
    p <- preview(); command <- input$guidance_preview_page
    brohn_require(!is.null(p) && identical(command$identity, p$identity) && identical(as.numeric(command$offset), as.numeric(offset())) && command$direction %in% c(-1L, 1L), "Use the current preview page controls.")
    tryCatch(bound(list(study_id = p$record$id, revision = p$record$revision, design_hash = p$protocol$design_hash)),
      error = function(e) {preview(NULL); shiny::removeModal(); stop(e)})
    next_offset <- offset()+25L*command$direction
    brohn_require(next_offset >= 0 && next_offset < length(p$protocol$timeline), "This preview has no more steps in that direction.")
    offset(next_offset)
    session$onFlushed(function() session$sendCustomMessage("brohn-focus", "guidance-preview-page-title"), once = TRUE)
  }))
  shiny::observeEvent(input$guidance_preview_close, {preview(NULL); shiny::removeModal(); session$sendCustomMessage("brohn-focus", "guidance-preview-open")})
  shiny::observeEvent(list(state$page, state$study_id), {p <- preview(); if (!is.null(p) && (!identical(state$page, "study") || !identical(state$study_id, p$record$id))) {preview(NULL); shiny::removeModal()}}, ignoreInit = FALSE)
  invisible(list(preview = preview, offset = offset))
}
