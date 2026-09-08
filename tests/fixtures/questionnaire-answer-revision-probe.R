# Read-only current-behaviour probe. No SQLite store, receiver service, job or
# scientific subprocess is created. Original synthetic answers only.
for (module in c("platform-core", "platform-store", "platform-delivery", "platform-analysis", "platform-scales", "platform-jobs"))
  source(paste0("R/", module, ".R"), encoding = "UTF-8")
local({
  design <- brohn_new_design("Original answer-revision seam probe", "survey", "study-revision-probe")
  design$questions <- lapply(1:2, function(i) brohn_question(paste("Original item", i), "rating", "before", paste0("q-probe-", i)))
  design$scales <- list(list(schema = "brohn-questionnaire-scale/1.0", id = "original-mean", label = "Original arithmetic mean",
    version = "original/1", source = "Original synthetic arithmetic probe; not a psychological instrument", scope = "before",
    items = lapply(1:2, function(i) list(question_id = paste0("q-probe-", i), reverse = FALSE, min = 1, max = 7)),
    scoring = list(aggregation = "mean", missing = "complete", minimum_answered = 2L, prorate = FALSE), conversion = NULL))
  protocol <- brohn_compile(design, 1L)
  events <- list(); tick <- 0L
  add <- function(type, step = NULL, payload = list(observed = TRUE)) {
    tick <<- tick + 100L; sequence <- length(events) + 1L
    e <- list(sequence = sequence, id = paste0("probe-event-", sequence), type = type, step_id = step$id,
      stimulus_id = step$stimulus_id, condition_id = step$condition_id,
      question_id = if (!is.null(step) && step$type == "question") step$question$id else NULL,
      phase = if (is.null(step)) "ending" else step$phase,
      clock = list(id = "browser-monotonic", unit = "ms", value = as.character(tick), instance_id = "original-probe-page", time_origin_ms = "1000000"),
      payload = payload)
    events[[sequence]] <<- e; e
  }
  for (step in protocol$timeline) {
    add("step_started", step)
    if (step$type == "question") {
      values <- if (step$question$id == "q-probe-1") c(2, 6) else 4
      for (value in values) add("response", step, list(value = value, response_time_ms = 100, resumed = FALSE))
    }
    add("step_finished", step)
  }
  before_ending <- .brohn_delivery_replay(protocol, events)
  old <- protocol$timeline[[which(vapply(protocol$timeline, function(s) identical(s$type, "question"), logical(1)))[1L]]]
  back_event <- add("step_started", old)
  back_error <- tryCatch({.brohn_delivery_apply(before_ending, back_event, protocol); NULL}, error = conditionMessage)
  events <- head(events, -1L)
  add("run_finished", payload = list(outcome = "completed"))
  state <- .brohn_delivery_replay(protocol, events)
  run <- list(id = "run-original-probe", protocol = protocol, origin = "sample", participant_alias_supplied = TRUE,
    participant_alias = "ORIGINAL-PROBE", deployment_id = "release-original-probe", allocation_index = 1L,
    acked_sequence = length(events), finalized_at = "2026-09-08T00:00:00Z")
  input <- list(design = design, runs = list(run), events = setNames(list(events), run$id))
  report <- brohn_analyse_runs(input)
  q1 <- Filter(function(row) identical(row$question_id, "q-probe-1"), report$analysis$features)[[1L]]
  scale <- report$analysis$scales$observations[[1L]]
  observations <- list(
    repeated_active_answer_replay_completes = isTRUE(state$run_finished),
    receiver_current_answer_is_latest_value = identical(state$answers$before[["q-probe-1"]], 6),
    raw_analysis_counts_both_answers = q1$response_count == 2L && q1$numeric_response_mean == 4,
    raw_total_includes_duplicate_item = report$analysis$quality$response_count == 3L,
    scale_preserves_duplicate_ambiguity = identical(scale$status, "not_scoreable") && identical(scale$missing_reason, "invalid_or_ambiguous_item"),
    completed_question_restart_is_rejected = !is.null(back_error))
  stopifnot(all(vapply(observations, isTRUE, logical(1))))
  evidence <- list(schema = "brohn-answer-revision-current-probe/1.0", origin = "original_synthetic",
    purpose = "Observed current seam; not implementation or scientific qualification of answer revision",
    checks = length(observations), observations = observations, current_state_q1 = state$answers$before[["q-probe-1"]], raw_q1_response_count = q1$response_count,
    raw_q1_mean = q1$numeric_response_mean, raw_total_response_count = report$analysis$quality$response_count,
    scale_status = scale$status, scale_missing_reason = scale$missing_reason, old_step_restart_error = back_error,
    future_explicit_final_value_oracle = list(q1 = 6, q2 = 4, complete_mean = 5),
    design_hash = brohn_hash(design), protocol_hash = brohn_hash(protocol), events_hash = brohn_hash(events),
    source_hashes = setNames(lapply(c("core", "delivery", "analysis", "scales", "jobs"), function(name)
      digest::digest(file = paste0("R/platform-", name, ".R"), algo = "sha256")), c("core", "delivery", "analysis", "scales", "jobs")))
  target <- "../../work/test-runs/brohn-answer-revision-probe"; dir.create(target, recursive = TRUE, showWarnings = FALSE)
  writeLines(brohn_json(evidence), file.path(target, "results.json"), useBytes = TRUE)
  cat("PASS: 6 current answer-revision seam observations; no Back implementation or worker claim\n")
})
