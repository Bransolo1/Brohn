# Dedicated GNAT authoring and saved-score support. This view never scores data.
brohn_gnat_settings_ui <- function(task, index) {
  brohn_gnat_validate(task)
  shiny::tagList(
    shiny::p("One target is paired with positive and negative words. Participants press Space for either named Go category and withhold it for the other words."),
    shiny::selectInput(paste0("task_gnat_context_kind_", index), paste("Task", index, "distractor context"),
      c("Mixed distractors" = "generic", "Another category" = "single_category", "A broader category" = "superordinate"), task$settings$context_kind),
    shiny::textAreaInput(paste0("task_gnat_context_rationale_", index), paste("Task", index, "why these distractors fit the research question"),
      task$settings$context_rationale, rows = 2),
    shiny::textInput(paste0("task_gnat_language_", index), paste("Task", index, "material language"), task$settings$language),
    shiny::p(class = "brohn-muted", "Participant instructions are in English. The language field records your materials; it does not translate instructions."),
    shiny::tags$details(shiny::tags$summary("Procedure, timing and assignment"),
      shiny::numericInput(paste0("task_seed_", index), paste("Task", index, "seed"), task$seed, 1, 2147483646),
      shiny::p("384 trials: 80 category training, 64 pairing practice and 240 test. Practice runs once, without a pass threshold or automatic repetition."),
      shiny::p("Test rounds allow 750 ms and 600 ms, with the same deadline for Go and No-Go words. Each round contains both target pairings; their order is saved."),
      shiny::p("Correct withholding has no response time. Hit, miss, false alarm and correct rejection remain separate outcomes."),
      shiny::p("Each completed trial has 100 ms of feedback within a minimum 500 ms gap before the next word. Release Space before continuing. Instruction screens are self-paced."),
      shiny::p("The named Brohn procedure fixes these rules. Material suitability, reliability and physical timing require their own evidence.")))
}

.brohn_gnat_metric_label <- function(name) {
  labels <- c(GNAT_r1_positive_d_prime = "750 ms: target + positive sensitivity",
    GNAT_r1_negative_d_prime = "750 ms: target + negative sensitivity",
    GNAT_r2_positive_d_prime = "600 ms: target + positive sensitivity",
    GNAT_r2_negative_d_prime = "600 ms: target + negative sensitivity",
    GNAT_r1_positive_criterion = "750 ms: target + positive response criterion",
    GNAT_r1_negative_criterion = "750 ms: target + negative response criterion",
    GNAT_r2_positive_criterion = "600 ms: target + positive response criterion",
    GNAT_r2_negative_criterion = "600 ms: target + negative response criterion",
    GNAT_r1_target_positive_contrast = "750 ms target-positive contrast",
    GNAT_r2_target_positive_contrast = "600 ms target-positive contrast")
  if (name %in% names(labels)) unname(labels[[name]]) else gsub("_", " ", name)
}

.brohn_gnat_display <- function(value) if (is.null(value)) "Unavailable" else format(signif(value, 5), trim = TRUE)

.brohn_gnat_flag_label <- function(flag) {
  labels <- c(incomplete_cell = "Some required trials are unavailable",
    declared_timing_unknown = "Timing definition unknown; scores unavailable",
    endpoint_rate_correction = "A zero or perfect rate used the declared endpoint correction",
    little_or_reversed_discrimination = "Little or reversed Go/No-Go discrimination",
    all_go = "Every retained trial received a Space response",
    all_no_go = "No retained trial received a Space response")
  if (flag %in% names(labels)) unname(labels[[flag]]) else gsub("_", " ", flag)
}

brohn_gnat_score_ui <- function(task) {
  audit <- task$scoring_audit
  if (is.null(audit)) return(NULL)
  cells <- audit$cells
  contrasts <- Filter(function(m) m$name %in% c("GNAT_r1_target_positive_contrast", "GNAT_r2_target_positive_contrast"), task$metrics)
  rows <- lapply(cells, function(cell) list(
    Round = paste(cell$deadline_ms, "ms"),
    Pairing = if (identical(cell$pairing, "target_positive")) "Target + positive" else "Target + negative",
    Hits = cell$hits, Misses = cell$misses, `False alarms` = cell$false_alarms,
    `Correct rejections` = cell$correct_rejections,
    `Sensitivity (d-prime)` = .brohn_gnat_display(if (isTRUE(task$eligible)) cell$d_prime else NULL),
    `Criterion (c)` = .brohn_gnat_display(if (isTRUE(task$eligible)) cell$criterion else NULL),
    Support = paste(c(if (identical(cell$status, "available")) "Complete cell" else brohn_default(cell$reason, cell$status),
      vapply(cell$flags, .brohn_gnat_flag_label, character(1))), collapse = "; ")))
  shiny::tagList(
    shiny::h3("Go/No-Go association results"),
    shiny::p(paste("Target:", brohn_default(audit$target$label, "See the saved task definition"),
      "| Distractor context:", audit$context$label, paste0("(", gsub("_", " ", audit$context$kind), ")."))),
    shiny::p(audit$context$rationale),
    if (!isTRUE(task$eligible)) shiny::p(role = "status", brohn_default(task$reason, "This administration does not have an eligible GNAT score.")),
    shiny::p("Each contrast compares target-positive and target-negative sensitivity within the same deadline. Positive values mean greater sensitivity separating Go words from distractors in the target-positive pairing."),
    shiny::div(class = "brohn-grid", lapply(contrasts, function(metric) shiny::div(
      shiny::h4(.brohn_gnat_metric_label(metric$name)),
      shiny::p(class = "brohn-result-number", .brohn_gnat_display(metric$value))))),
    shiny::p("The two deadlines remain separate. These task results have no individual preference categories."),
    brohn_table(rows, label = "GNAT outcomes and sensitivity by deadline and pairing"),
    shiny::tags$details(shiny::tags$summary("Rates, response times and scoring rules"),
      shiny::p("A hit is a Space response to a Go word; a false alarm is a Space response to a No-Go word. Withholding produces a miss or correct rejection. Only actual responses have a response time."),
      shiny::p("Sensitivity is the normal-score hit rate minus the normal-score false-alarm rate. Exact rates of zero and one use 0.005 and 0.995; the original counts and rates remain saved. Nonpositive sensitivity is retained."),
      shiny::p("Criterion describes response tendency: negative favors responding and positive favors withholding. Training and practice do not enter these test summaries."),
      shiny::tags$pre(tabindex = "0", brohn_json(audit, TRUE))))
}
