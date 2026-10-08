# Inactive small researcher action layer; source after saved-analysis dispatch.
brohn_install_saved_analysis_ui <- function(input, session, store, current, state, attempt, message, refresh) {
  selected <- function(command, fields, stages) {
    brohn_fields(command, fields, label = "Saved analysis selection")
    brohn_require(identical(state$page, "study") && state$stage %in% stages &&
        !is.null(current$study) && identical(command$study_id, current$study$id),
      "Choose a saved analysis in the currently open study.")
    .brohn_epr_authority(store, current$study$project_id)
    invisible(TRUE)
  }
  show <- function(result) {
    job <- result$job
    message(brohn_saved_analysis_status(result)); refresh()
    shiny::showModal(shiny::modalDialog(title = "Saved analysis", easyClose = FALSE,
      shiny::p(role = "status", brohn_saved_analysis_status(result)),
      if (isTRUE(result$reused)) shiny::p("This action returned the existing analysis; it did not create another attempt."),
      if (!is.null(result$recovery)) shiny::tags$details(
        shiny::tags$summary("Analysis history"),
        shiny::p("The earlier failed attempt remains saved with its original request and outcome."),
        shiny::p("Earlier attempt: ", shiny::tags$code(result$recovery$body$earlier_job$id)),
        shiny::p("Named analysis: ", shiny::tags$code(job$id)),
        shiny::p("Both refer to the same original saved session. This relationship is preserved in the study workspace.")),
      footer = shiny::tagList(shiny::actionButton("saved_analysis_activity", "Open Activity"),
        shiny::modalButton("Close"))))
  }
  shiny::observeEvent(input$analyse_saved_run, attempt(function() {
    command <- input$analyse_saved_run
    selected(command, c("run_id", "study_id"), c("Collect", "Review", "Results"))
    show(brohn_queue_saved_run(store, command$run_id, current$study$id, current$study$project_id))
  }))
  shiny::observeEvent(input$analyse_cohort, attempt(function() {
    command <- input$analyse_cohort
    selected(command, c("deployment_id", "study_id"), c("Results", "History"))
    show(brohn_queue_saved_cohort(store, command$deployment_id, current$study$id, current$study$project_id))
  }))
  shiny::observeEvent(input$saved_analysis_activity, attempt(function() {
    shiny::removeModal(); state$page <- "activity"; state$error <- NULL; refresh()
    session$sendCustomMessage("brohn-navigation", list(page = "activity", focus = TRUE))
  }))
  invisible(TRUE)
}
