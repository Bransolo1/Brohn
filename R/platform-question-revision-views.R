brohn_question_revision_ui <- function(design) {
  enabled <- !is.null(design$questionnaire_navigation)
  brohn_card(title = "Answer review", subtitle = if (enabled) "Participants can revisit answers within each questionnaire." else "This draft uses forward-only questionnaire steps.",
    shiny::p("Back and Edit stay within the current questionnaire. Continuing from review seals those answers before the next stimulus or study part."),
    if (enabled) shiny::p("Changing a routing answer clears its dependent answers. Reports score the final answers and retain the acknowledged edit history."),
    brohn_command(if (enabled) "Use forward-only" else "Enable answer review", "questionnaire_navigation_change",
      list(study_id = design$id, design_hash = brohn_hash(design), enabled = !enabled)),
    shiny::p(class = "brohn-muted", "This is a draft protocol choice. Existing participant releases retain their saved navigation and scoring evidence."))
}
brohn_install_question_revision_ui <- function(input, output, session, current, state, capture, update_study, attempt, message) {
  shiny::observeEvent(input$questionnaire_navigation_change, attempt(function() {
    command <- input$questionnaire_navigation_change
    brohn_fields(command, c("study_id", "design_hash", "enabled"), label = "Answer review change")
    brohn_require(identical(state$page, "study") && identical(state$stage, "Questions") && !is.null(current$study) &&
      identical(command$study_id, current$study$id) && !isTRUE(current$study$body$archived) &&
      identical(input$study_form_identity, paste(current$study$id, "Questions", sep = ":")) &&
      identical(command$design_hash, brohn_hash(current$study$body)), "Reopen the current study questionnaire before changing answer review.")
    brohn_require(is.logical(command$enabled) && length(command$enabled) == 1L && !is.na(command$enabled), "Choose an explicit answer review setting.")
    capture(); design <- current$study$body
    if (command$enabled) design$questionnaire_navigation <- brohn_questionnaire_navigation() else design$questionnaire_navigation <- NULL
    brohn_validate_design(design)
    update_study(design); message(if (command$enabled) "Answer review enabled for this draft." else "Forward-only questionnaire saved for this draft.")
  }))
  invisible(TRUE)
}
brohn_question_revision_report_ui <- function(analysis) {
  result <- analysis$questionnaire_revision
  if (is.null(result)) return(NULL)
  rows <- unlist(lapply(result$runs, function(run) run$effective_records), recursive = FALSE)
  edits <- sum(vapply(rows, function(r) r$revision_count, numeric(1)))
  invalidations <- sum(vapply(result$runs, function(run) length(run$invalidations), integer(1)))
  brohn_card(title = "Reviewed questionnaire answers", subtitle = "Each question contributes its final effective answer within that assessment.",
    shiny::p(paste(length(result$runs), "sessions;", length(rows), "question records;", edits, "answer revisions;", invalidations, "recorded dependent-answer invalidations.")),
    shiny::p("Hidden and unsubmitted questions remain explicit in the evidence. Revised or resumed answers do not claim an initial uninterrupted response time."),
    shiny::tags$details(shiny::tags$summary("Review final answers and revision counts"),
      shiny::p(class = "brohn-muted", paste("Showing", min(100L, length(rows)), "of", length(rows), "records. Full report JSON contains every final record and the complete acknowledged questionnaire event history.")),
      shiny::div(class = "brohn-table", tabindex = "0", role = "region", `aria-label` = "Final questionnaire answers; scroll horizontally for more columns", shiny::tags$table(shiny::tags$thead(shiny::tags$tr(lapply(c("Session", "Question", "Status", "Final value", "Revisions"), shiny::tags$th))),
        shiny::tags$tbody(lapply(head(rows, 100L), function(r) shiny::tags$tr(shiny::tags$td(r$session_id), shiny::tags$td(r$prompt),
          shiny::tags$td(gsub("_", " ", r$status, fixed = TRUE)), shiny::tags$td(if (is.null(r$value)) "No final value" else brohn_json(r$value)), shiny::tags$td(r$revision_count)))))))
  )
}
