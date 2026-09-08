brohn_analysis_plan_summary_ui <- function(design) {
  plan <- design$analysis_plan
  brohn_card(title = "Decide what the analysis should answer",
    subtitle = "Save the comparison family with your study, so reused designs keep their analysis intentions.",
    if (is.null(plan)) shiny::p("No explicit comparison plan saved. Available automatic comparisons are exploratory.") else
      shiny::tagList(shiny::p(plan$rationale), shiny::p(paste(length(plan$comparisons), "declared comparisons; family error threshold", plan$multiplicity$alpha))),
    shiny::actionButton("edit_analysis_plan", if (is.null(plan)) "Set analysis plan" else "Edit analysis plan"))
}
brohn_install_analysis_plan_ui <- function(input, output, session, current, attempt, capture, update_study, state = NULL) {
  draft <- shiny::reactiveValues(study_id = NULL, comparisons = list(), active = FALSE, token = NULL, revision = NULL, design_hash = NULL)
  guard <- function() {
    brohn_require(isTRUE(draft$active) && identical(current$study$id, draft$study_id) &&
      identical(current$study$revision, draft$revision) && identical(brohn_hash(current$study$body), draft$design_hash) &&
      identical(input$plan_form_identity, draft$token) &&
      (is.null(state) || (identical(state$page, "study") && identical(state$stage, "Plan"))),
      "This study or analysis-plan draft changed. Reopen its analysis plan.")
  }
  label <- function(spec, design) {
    metric <- brohn_find(brohn_analysis_plan_metrics(), spec$measure)
    outcome <- if (identical(spec$measure, "questionnaire_scale")) brohn_find(design$scales, spec$outcome_id)$label else
      if (metric$modality == "questionnaire") brohn_find(design$questions, spec$outcome_id)$prompt else spec$outcome_id
    paste(metric$label, "\u00b7", outcome, "\u00b7", brohn_find(design$conditions, spec$test_id)$label, "minus", brohn_find(design$conditions, spec$control_id)$label)
  }
  shiny::observeEvent(input$edit_analysis_plan, attempt(function() {
    capture(); design <- current$study$body
    brohn_require(!isTRUE(design$archived), "Restore this study before editing its analysis plan.")
    plan <- brohn_default(design$analysis_plan, brohn_new_analysis_plan())
    draft$study_id <- design$id; draft$comparisons <- plan$comparisons; draft$active <- TRUE
    draft$revision <- current$study$revision; draft$design_hash <- brohn_hash(design); draft$token <- brohn_id("plan-form")
    measures <- brohn_analysis_plan_metrics()
    conditions <- stats::setNames(brohn_ids(design$conditions), vapply(design$conditions, `[[`, character(1), "label"))
    reference <- Filter(function(c) c$role == "control", design$conditions); test <- Filter(function(c) c$role == "test", design$conditions)
    shiny::showModal(shiny::modalDialog(title = "Plan the study comparisons", size = "l",
      shiny::div(style = "display:none", shiny::textInput("plan_form_identity", NULL, draft$token)),
      shiny::p("Choose the outcomes and control comparisons before collecting data where possible. A saved plan is versioned with the design; it is not external preregistration."),
      shiny::textAreaInput("plan_rationale", "Research question and comparison rationale", plan$rationale, width = "100%", rows = 3),
      shiny::selectInput("plan_measure", "Measure", stats::setNames(brohn_ids(measures), vapply(measures, `[[`, character(1), "label"))),
      shiny::uiOutput("plan_outcome"),
      shiny::div(class = "brohn-form-grid", shiny::selectInput("plan_control", "Reference condition", conditions, if (length(reference)) reference[[1]]$id else NULL),
        shiny::selectInput("plan_test", "Comparison condition", conditions, if (length(test)) test[[1]]$id else NULL)),
      shiny::actionButton("plan_add", "Add planned comparison"), shiny::uiOutput("plan_comparisons"),
      shiny::numericInput("plan_alpha", "Family error threshold", plan$multiplicity$alpha, min = .0001, max = .2, step = .01),
      shiny::p("The complete family uses Holm correction. A report containing only part of the family uses conservative Bonferroni bounds until the measures are combined. Intervals remain unadjusted."),
      shiny::p("Keep the list empty for descriptive results only. These recipes compare numeric responses, saved after-stimulus scales or AOI gaze outcomes. Repeated assessments stay within their original person and session."),
      footer = shiny::tagList(shiny::actionButton("plan_cancel", "Cancel"), shiny::actionButton("plan_save", "Save analysis plan", class = "btn-primary"))))
  }))
  output$plan_outcome <- shiny::renderUI({
    shiny::req(draft$active, draft$study_id, identical(current$study$id, draft$study_id), input$plan_measure)
    design <- current$study$body
    if (input$plan_measure == "questionnaire_numeric") {
      questions <- Filter(function(q) q$type %in% c("rating", "slider", "number") && q$scope == "after_each", design$questions)
      choices <- stats::setNames(brohn_ids(questions), vapply(questions, `[[`, character(1), "prompt"))
    } else if (input$plan_measure == "questionnaire_scale") {
      scales <- Filter(function(s) identical(s$scope, "after_each"), design$scales)
      choices <- stats::setNames(brohn_ids(scales), vapply(scales, `[[`, character(1), "label"))
    } else {
      areas <- unique(unlist(lapply(design$stimuli, function(s) vapply(s$aois, `[[`, character(1), "label")), use.names = FALSE))
      choices <- stats::setNames(areas, areas)
    }
    shiny::tagList(shiny::selectInput("plan_outcome_id", switch(input$plan_measure, questionnaire_numeric = "Numeric question",
      questionnaire_scale = "After-stimulus scale", "AOI label shared by both conditions"), c("Choose an outcome" = "", choices)),
      if (!length(choices)) shiny::p(if (input$plan_measure == "questionnaire_scale")
        "Open Questions and save a scale with items after each stimulus before planning its condition comparison." else
        "Add a matching after-stimulus numeric question or an AOI on each condition before adding this comparison."))
  })
  make_plan <- function() list(schema = "brohn-analysis-plan/1.0", recipe = "paired-consumer-comparisons/1.0-draft",
    rationale = input$plan_rationale, comparisons = draft$comparisons, multiplicity = list(method = "holm", alpha = input$plan_alpha))
  shiny::observeEvent(input$plan_add, attempt(function() {
    guard()
    plan <- make_plan()
    plan$comparisons <- c(plan$comparisons, list(list(id = brohn_id("comparison"), measure = input$plan_measure,
      outcome_id = input$plan_outcome_id, control_id = input$plan_control, test_id = input$plan_test)))
    brohn_validate_analysis_plan(plan, current$study$body); draft$comparisons <- plan$comparisons
  }))
  shiny::observeEvent(input$plan_remove, attempt(function() {
    guard(); brohn_require(is.list(input$plan_remove) && identical(input$plan_remove$token, draft$token), "Reopen this comparison draft before removing an outcome.")
    draft$comparisons <- Filter(function(c) c$id != input$plan_remove$id, draft$comparisons)
  }))
  output$plan_comparisons <- shiny::renderUI({
    shiny::req(draft$active, draft$study_id)
    if (!length(draft$comparisons)) return(shiny::p("Descriptive results only: no hypotheses declared."))
    shiny::tags$ul(lapply(draft$comparisons, function(c) shiny::tags$li(label(c, current$study$body), brohn_command("Remove planned comparison", "plan_remove", list(id = c$id, token = draft$token)))))
  })
  shiny::observeEvent(input$plan_cancel, {draft$active <- FALSE; shiny::removeModal()})
  shiny::observeEvent(input$plan_save, attempt(function() {
    guard()
    design <- current$study$body; plan <- make_plan()
    brohn_validate_analysis_plan(plan, design); design$analysis_plan <- plan
    update_study(design); draft$active <- FALSE; shiny::removeModal()
  }))
  invisible(list(context = function() list(active = draft$active, token = draft$token, revision = draft$revision)))
}
