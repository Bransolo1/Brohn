# Dedicated authoring guidance; connected only with the qualified task route.
brohn_sciat_window_settings_ui <- function(task, index) {
  brohn_sciat_window_validate(task)
  shiny::tagList(
    shiny::p("Use one target and two attribute categories. The two pairings compare this same target with positive and negative attributes; record any separate experimental control in the study design."),
    shiny::p("This named Brohn procedure uses the first response. A wrong key ends that trial, and a missed deadline is recorded separately."),
    shiny::textInput(paste0("task_sciat_language_", index), paste("Task", index, "material language"), task$settings$language),
    shiny::p(class = "brohn-muted", "Participant instructions are in English. The language field records your materials; it does not translate the task."),
    shiny::tags$details(shiny::tags$summary("Procedure, timing and assignment"),
      shiny::numericInput(paste0("task_seed_", index), paste("Task", index, "seed"), task$seed, 1, 2147483646),
      shiny::p("192 trials: 24 practice and 72 test trials for each pairing. Successive allocations alternate which pairing comes first."),
      shiny::p("E is the positive-attribute key and I is the negative-attribute key. The target changes sides between pairings."),
      shiny::p("Each trial has a 1,500 ms response window, followed by 150 ms accuracy feedback or a 500 ms missed-response reminder, then a 250 ms blank interval."),
      shiny::p("Timing and trial counts are fixed by the selected procedure. Changing these requires a separately named method."),
      shiny::p("The standardized score compares target-positive and target-negative response times. Its saved support keeps errors, fast responses and omissions distinct."),
      shiny::p("This is a documented Brohn adaptation. Browser timing is recorded; physical display and response-device timing require separate measurement.")))
}

brohn_sciat_window_score_ui <- function(task) {
  audit <- task$scoring_audit
  if (is.null(audit)) return(NULL)
  mappings <- lapply(audit$mapping, function(m) list(
    Pairing = if (m$mapping == "A") "Target + positive" else "Target + negative",
    Presented = m$presented, Answered = m$responded, Omitted = m$omitted,
    `Below 350 ms` = m$removed_fast, `Retained correct` = m$retained_correct,
    `Retained errors` = m$retained_errors, `Adjusted mean (ms)` = m$adjusted_mean_ms))
  shiny::tagList(
    shiny::h3("What supports this SC-IAT score"),
    shiny::p("Positive values mean faster target-positive responses in this task. The score does not provide an individual preference category."),
    shiny::p("Only the 144 test trials enter scoring. Practice, unanswered trials and responses below 350 ms remain separately recorded."),
    if (isTRUE(audit$qc$below_75pct_response_accuracy)) shiny::p(class = "brohn-warning",
      "Response accuracy is below 75% in at least one pairing. This quality flag does not automatically exclude the administration."),
    brohn_table(mappings, label = "SC-IAT pairing response coverage and adjusted means"),
    shiny::tags$details(shiny::tags$summary("Exact scoring rules and trial audit"),
      shiny::p("Retained errors receive their pairing's mean of all retained original latencies plus 400 ms. The denominator is the sample standard deviation of pooled original correct responses."),
      shiny::p("The displayed target-positive contrast reverses the reference package's A-minus-B sign. Complete scoring support is also included in task-score exports."),
      shiny::tags$pre(brohn_json(audit, TRUE))))
}
