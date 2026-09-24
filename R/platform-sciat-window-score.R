# Complete frozen-procedure arithmetic. Native delivery replays the full journal;
# imported summaries retain their separate, explicitly weaker evidence level.
brohn_sciat_window_score <- function(compiled, responses, completed = TRUE) {
  brohn_sciat_window_validate_compiled(compiled)
  brohn_require(brohn_array(responses), "SC-IAT scoring requires response records.")
  trials <- Filter(function(t) identical(t$type, "task_trial"), compiled$timeline)
  ids <- brohn_ids(trials)
  received <- vapply(responses, function(r) brohn_default(r$trial_id, ""), character(1))
  brohn_require(!anyDuplicated(received) && all(received %in% ids), "SC-IAT responses contain duplicate or unknown frozen trials.")
  result <- list(schema_version = "brohn-task-score/1.0", task_id = compiled$id,
    profile = compiled$profile, origin = compiled$origin, design_hash = compiled$design_hash,
    scoring_recipe = "brohn-sciat-response-window-score/1.0", procedure_hash = compiled$procedure_hash,
    sequence_hash = compiled$sequence_hash, status = "unavailable", eligible = FALSE,
    metrics = list(), counts = list(expected = length(ids), received = length(received)), reason = NULL,
    limitations = as.list(c(
      "Named Brohn first-response procedure; not equivalent to a correction-inclusive IAT or an exact original/vendor SC-IAT implementation.",
      "Descriptive task-level contrast; positive values mean faster target-positive responses. No individual preference or diagnostic bands.",
      "Source evidence, material validity, physical timing and population applicability remain separate from scoring arithmetic.")))
  if (!isTRUE(completed) || !setequal(ids, received)) {
    result$reason <- "Complete uninterrupted evidence for all 192 assigned trials is required."
    return(result)
  }
  ordered <- responses[match(ids, received)]
  if (any(vapply(ordered, function(r) identical(r$outcome, "interrupted"), logical(1)))) {
    result$reason <- "The task contains an interrupted trial."
    return(result)
  }
  rows <- lapply(seq_along(trials), function(i) {
    trial <- trials[[i]]; r <- ordered[[i]]
    brohn_require(all(c("trial_id", "outcome", "response_outcome", "response_code", "response_ms", "correct") %in% names(r)),
      "Keep explicit SC-IAT first-response fields, including null omission values.")
    brohn_require(brohn_text(r$outcome, 24) && r$outcome %in% c("response", "omission") && identical(r$response_outcome, r$outcome),
      "SC-IAT requires an actual first response or explicit omission.")
    if (r$outcome == "response") {
      brohn_require(brohn_text(r$response_code, 16) && r$response_code %in% c("KeyE", "KeyI") &&
        brohn_number(r$response_ms, 0, 1500) && is.logical(r$correct) && length(r$correct) == 1L &&
        !is.na(r$correct) && identical(r$correct, identical(r$response_code, trial$correct_code)),
        "SC-IAT first response, accuracy or inclusive 1500 ms window conflicts with the frozen trial.")
    } else brohn_require(is.null(r$response_code) && is.null(r$response_ms) && is.null(r$correct),
      "An omission has no response key, latency or observed accuracy.")
    data.frame(trial_id = trial$id, mapping = trial$mapping, outcome = r$outcome,
      latency_ms = brohn_default(r$response_ms, NA_real_), correct = brohn_default(r$correct, NA),
      stringsAsFactors = FALSE)
  })
  all_rows <- do.call(rbind, rows)
  scored <- vapply(trials, function(t) isTRUE(t$scored), logical(1))
  data <- all_rows[scored, , drop = FALSE]
  brohn_require(nrow(data) == 144L && all(table(factor(data$mapping, levels = c("A", "B"))) == 72L),
    "SC-IAT scoring requires both complete frozen 72-trial test mappings.")
  audit <- brohn_sciat_window_candidate_reduce(data)
  available <- identical(audit$status, "available_arithmetic")
  result$status <- if (available) "computed" else "unavailable"
  result$eligible <- available; result$reason <- audit$reason
  result$counts <- c(result$counts, list(practice = sum(!scored), scored = nrow(data),
    scored_responded = audit$counts$responded, scored_timeouts = audit$counts$omitted,
    removed_fast = audit$counts$removed_fast, retained = audit$counts$retained,
    retained_correct = audit$counts$retained_correct, retained_errors = audit$counts$retained_errors))
  result$metrics <- list(list(name = "SCIAT_target_positive_D", value = audit$target_positive_d, unit = "D",
    direction = "(Target-negative adjusted mean minus target-positive adjusted mean) / pooled original-correct sample SD; positive means faster target-positive responses.",
    support = list(test_trials = 144L, retained_responses = audit$counts$retained,
      pooled_correct_responses = audit$counts$retained_correct,
      sample_sd_divisor = max(0L, audit$counts$retained_correct - 1L))))
  result$scoring_audit <- list(schema = "brohn-sciat-response-window-audit/1.0",
    mapping_order = audit$mapping_order, mapping = audit$mapping, counts = audit$counts,
    minimum_retained_ms = 350L, response_window_ms = 1500L, error_penalty_ms = 400L,
    error_base = "All retained original response latencies in the same mapping, including errors",
    pooled_correct_sample_sd_ms = audit$pooled_correct_sample_sd_ms,
    reference_package_d = audit$reference_package_d, displayed_d = audit$target_positive_d,
    reference_sign = "The displayed target-positive contrast reverses the reference package's A-minus-B sign.",
    reference = brohn_sciat_window_candidate()$reference, qc = audit$qc,
    rows = lapply(seq_len(nrow(audit$rows)), function(i) lapply(as.list(audit$rows[i, , drop = FALSE]), function(value) {
      # Explicit omissions and excluded scoring latencies use NA internally.
      # Retain their named cells as JSON null; unexpected NaN/Inf still fail.
      if (length(value) == 1L && is.na(value) && !is.nan(value)) NULL else value
    })))
  result
}

# A summary import has already validated first/final fields against the frozen
# key and first-response terminal rule. This conversion adds no key/clock replay.
brohn_sciat_window_import_response <- function(response) {
  outcome <- if (response$outcome %in% c("correct", "incorrect")) "response" else
    if (identical(response$outcome, "timeout")) "omission" else response$outcome
  list(trial_id = response$trial_id, outcome = outcome, response_outcome = outcome,
    response_code = response$response_code, response_ms = response$first_response_ms,
    correct = if (identical(outcome, "response")) response$first_correct else NULL)
}
