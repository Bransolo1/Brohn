brohn_stimulus_version_dialog <- function(design, stimulus, token) {
  conditions <- stats::setNames(brohn_ids(design$conditions), vapply(design$conditions,
    function(x) paste0(x$label, " (", x$role, ")"), character(1)))
  sets <- Filter(function(s) stimulus$id %in% vapply(s$members, `[[`, character(1), "stimulus_id"), design$stimulus_assignment$sets)
  assignments <- c("Everyone, as a separate stimulus" = "always",
    stats::setNames(vapply(sets, `[[`, character(1), "id"), vapply(sets, function(s) paste("Add to", s$label), character(1))))
  shiny::modalDialog(title = "Add a stimulus version", size = "m", easyClose = FALSE,
    shiny::div(hidden = NA, shiny::textInput("stimulus_version_dialog_identity", NULL, token)),
    shiny::uiOutput("stimulus_version_error"),
    shiny::p(paste0("Start from ", stimulus$title, ".")),
    shiny::textInput("stimulus_version_title", "Version name", brohn_stimulus_version_name(stimulus, design$stimuli)),
    shiny::selectInput("stimulus_version_condition", "Compare this version as",
      choices = c("A separate condition" = "__new__", conditions), selected = "__new__", selectize = FALSE),
    shiny::conditionalPanel("input.stimulus_version_condition === '__new__'",
      shiny::selectInput("stimulus_version_role", "Role of the new condition",
        c("Test" = "test", "Control" = "control", "Neutral comparator" = "neutral", "Other" = "other"), selected = "test", selectize = FALSE)),
    shiny::p("Copies the material, viewing duration and areas. Edit the new version in Plan."),
    if (identical(design$schema_version, "brohn-design/1.2.0")) shiny::selectInput("stimulus_version_assignment",
      "Who sees the new version?", assignments, selected = if (length(sets)) sets[[1L]]$id else "always", selectize = FALSE) else
      shiny::p(class = "brohn-muted", "Everyone will see this new stimulus. Group alternatives in Plan to assign one version per participant."),
    if (length(sets) && sets[[1L]]$selection == "one") shiny::p(class = "brohn-muted", "Adding to this group makes the new version an alternative for future participants. Existing releases keep their original assignments."),
    shiny::p(class = "brohn-muted", "Same-condition gaze summaries can pool stimuli. Use a separate condition for a separate comparison and review the analysis plan."),
    footer = shiny::tagList(brohn_command("Cancel", "cancel_stimulus_version", list(token = token)),
      brohn_command("Add version", "confirm_stimulus_version", list(token = token), class = "btn btn-primary")))
}

brohn_install_stimulus_versions <- function(input, output, session, store, current, state, capture, update_study, attempt) {
  context <- shiny::reactiveVal(NULL)
  error <- shiny::reactiveVal(NULL)
  plan <- function(id) {
    brohn_require(identical(state$page, "study") && identical(state$stage, "Plan") &&
      identical(state$study_id, id) && !is.null(current$study) && identical(current$study$id, id) &&
      identical(input$study_form_identity, paste(id, "Plan", sep = ":")),
      "Open the source study's current Plan before adding a stimulus version.")
  }
  close <- function(focus = TRUE) {
    pin <- context(); context(NULL); error(NULL); shiny::removeModal(session = session)
    if (focus && !is.null(pin)) session$onFlushed(function()
      session$sendCustomMessage("brohn-focus", paste0("stimulus_version_", pin$stimulus_id)), once = TRUE)
  }
  apply <- function(fn) attempt(function() tryCatch({error(NULL); fn()},
    error = function(e) {error(conditionMessage(e)); stop(e)}))
  output$stimulus_version_error <- shiny::renderUI({
    if (!is.null(error())) shiny::div(class = "brohn-alert brohn-alert-error", role = "alert", error())
  })
  shiny::observeEvent(input$duplicate_stimulus, attempt(function() {
    command <- input$duplicate_stimulus
    brohn_fields(command, c("study_id", "stimulus_id"), label = "Stimulus version command")
    plan(command$study_id)
    capture()
    saved <- brohn_study(store, command$study_id); brohn_project(store, saved$project_id)
    brohn_require(!isTRUE(saved$body$archived) && identical(current$study$revision, saved$revision) &&
      identical(brohn_hash(current$study$body), brohn_hash(saved$body)),
      "Reopen the current saved study before adding a stimulus version.")
    design <- saved$body
    stimulus <- brohn_find(design$stimuli, command$stimulus_id)
    brohn_require(!is.null(stimulus), "Choose a current stimulus.")
    pin <- list(study_id = design$id, stimulus_id = stimulus$id, source_hash = brohn_hash(stimulus),
      revision = saved$revision, design_hash = brohn_hash(design), project_id = saved$project_id, token = brohn_token())
    context(pin); error(NULL)
    shiny::showModal(brohn_stimulus_version_dialog(design, stimulus, pin$token), session = session)
  }), ignoreInit = TRUE)
  shiny::observeEvent(input$confirm_stimulus_version, apply(function() {
    pin <- context(); command <- input$confirm_stimulus_version
    brohn_fields(command, "token", label = "Stimulus version confirmation")
    brohn_require(!is.null(pin) && identical(command$token, pin$token) &&
      identical(input$stimulus_version_dialog_identity, pin$token), "Use the current Add version dialog.")
    plan(pin$study_id)
    # Keep current project/head authority and the single append in one existing
    # store transaction. A refused save must never persist only the condition.
    before <- current$study
    tryCatch(brohn_store_batch(store, function() {
    saved <- brohn_study(store, pin$study_id); brohn_project(store, saved$project_id)
    brohn_require(!isTRUE(saved$body$archived) && identical(saved$project_id, pin$project_id) &&
      identical(saved$revision, pin$revision) && identical(current$study$revision, pin$revision) &&
      identical(brohn_hash(saved$body), pin$design_hash) && identical(brohn_hash(current$study$body), pin$design_hash),
      "This study changed. Open Add version again to review its current design.")
    design <- saved$body
    stimulus <- brohn_find(design$stimuli, pin$stimulus_id)
    brohn_require(!is.null(stimulus) && identical(brohn_hash(stimulus), pin$source_hash),
      "The source stimulus changed. Open Add version again to review its current material.")
    condition <- input$stimulus_version_condition
    brohn_require(brohn_text(condition, 96), "Choose a condition for this version.")
    result <- brohn_add_study_stimulus_version(design, pin$stimulus_id, input$stimulus_version_title,
      condition_id = if (identical(condition, "__new__")) NULL else condition,
      new_condition_role = input$stimulus_version_role,
      assignment = if (identical(design$schema_version, "brohn-design/1.2.0")) input$stimulus_version_assignment else "always")
    update_study(result)
    }), error = function(e) {current$study <- before; stop(e)})
    close()
  }), ignoreInit = TRUE)
  shiny::observeEvent(input$cancel_stimulus_version, {
    pin <- context(); command <- input$cancel_stimulus_version
    if (is.list(command) && !is.null(pin) && identical(command$token, pin$token)) close()
  }, ignoreInit = TRUE)
  shiny::observe({
    pin <- context(); if (is.null(pin)) return()
    if (!identical(state$page, "study") || !identical(state$stage, "Plan") ||
      !identical(state$study_id, pin$study_id) || is.null(current$study) ||
      !identical(current$study$id, pin$study_id)) close(focus = FALSE)
  })
  invisible(context)
}
