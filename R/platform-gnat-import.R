# Dedicated, versioned GNAT summary fields. No key/visibility replay is inferred.
.brohn_gnat_import_columns <- function() paste0(c(
  "participant", "participant_linkage", "session", "attempt", "protocol",
  "presentation_index", "trial", "presented", "phase", "round_id", "cell_id",
  "expected_action", "outcome", "response_outcome", "response_code",
  "response_ms", "correct", "missing_reason"), "_column")

.brohn_gnat_import_response <- function(cells, trial, row, timing_known) {
  require <- function(ok, message) brohn_require(ok, paste("GNAT source row", row, message))
  nullable <- function(value) if (identical(value, "")) NULL else value
  require(all(sub("_column$", "", .brohn_gnat_import_columns()) %in% names(cells)),
    "needs the versioned GNAT fields, including distinct withholding and response values.")
  require(identical(trial$task_profile, "gnat-brohn-single-target/1.0") &&
    trial$expected_action %in% c("go", "nogo"), "needs its exact frozen GNAT trial.")
  require(identical(cells$phase, trial$phase) && identical(nullable(cells$round_id), trial$round_id) &&
    identical(nullable(cells$cell_id), trial$cell_id) && identical(cells$expected_action, trial$expected_action),
    "phase, round, cell or expected action disagrees with the frozen protocol.")
  presented <- .brohn_task_import_boolean(cells$presented, "presented", row)
  code <- nullable(cells$response_code)
  latency <- .brohn_task_import_decimal(cells$response_ms, "Space-response latency", row)
  correct <- if (identical(cells$correct, "")) NULL else .brohn_task_import_boolean(cells$correct, "GNAT correctness", row)
  outcome <- cells$outcome; provisional <- nullable(cells$response_outcome)
  reason <- nullable(cells$missing_reason)
  terminal <- c("hit", "miss", "false_alarm", "correct_rejection")
  require(outcome %in% c(terminal, "interrupted", "not_presented"), "has an unsupported GNAT outcome.")
  require(is.null(provisional) || provisional %in% terminal, "has an unsupported provisional response outcome.")
  require(is.null(reason) || brohn_text(reason, 4000), "needs a bounded explicit interruption/missing reason.")
  require(identical(is.null(code), is.null(latency)), "needs both a Space key and latency, or neither; withholding has no latency.")
  require(is.null(code) || identical(code, "Space"), "has an accepted key other than the frozen Space response.")
  if (isTRUE(timing_known) && !is.null(latency)) require(latency < trial$timeout_ms,
    "places a response at or after the exclusive frozen deadline.")
  derived <- if (identical(trial$expected_action, "go")) {
    if (is.null(code)) "miss" else "hit"
  } else if (is.null(code)) "correct_rejection" else "false_alarm"
  if (!presented) {
    require(outcome %in% c("not_presented", "interrupted") && is.null(code) && is.null(latency) &&
      is.null(correct) && is.null(provisional) && !is.null(reason),
      "cannot report an observed outcome or response without presentation.")
  } else if (identical(outcome, "interrupted")) {
    require(is.null(correct) && !is.null(reason) && (is.null(provisional) || identical(provisional, derived)),
      "must retain interrupted evidence without completed-trial accuracy.")
    require(is.null(code) || !is.null(provisional), "must identify the provisional outcome of a retained interrupted response.")
  } else {
    require(outcome %in% terminal && identical(outcome, derived) && identical(provisional, derived) &&
      identical(correct, outcome %in% c("hit", "correct_rejection")) && is.null(reason),
      "outcome, correctness, response and frozen Go/No-Go action disagree.")
  }
  # Compatibility fields remain explicitly absent for a withheld response.
  # Actual GNAT accuracy is `correct`, including true for a correct rejection.
  list(trial_id = trial$id, presented = presented, outcome = outcome,
    response_outcome = provisional, response_code = code, response_ms = latency,
    correct = correct, phase = trial$phase, round_id = trial$round_id, cell_id = trial$cell_id,
    expected_action = trial$expected_action, first_correct = if (is.null(code)) NULL else identical(derived, "hit"),
    first_response_ms = latency, first_response_ms_source = nullable(cells$response_ms),
    final_code = NULL, final_correct_ms = NULL, final_correct_ms_source = NULL,
    missing_reason = reason)
}

.brohn_gnat_import_scoring_response <- function(response) list(
  trial_id = response$trial_id, outcome = response$outcome,
  response_outcome = response$response_outcome, response_code = response$response_code,
  response_ms = response$response_ms, correct = response$correct)

.brohn_gnat_native_row <- function(trial, response, identity, position) {
  brohn_require(identical(trial$task_profile, "gnat-brohn-single-target/1.0") &&
    identical(response$trial_id, trial$id) &&
    response$outcome %in% c("hit", "miss", "false_alarm", "correct_rejection"),
    "Export the exact original completed GNAT trial and response.")
  scalar <- function(value) if (is.null(value)) "" else if (is.character(value)) value else brohn_json(value)
  list(participant_id = identity$participant_id, participant_linkage = scalar(identity$participant_linkage),
    session_id = identity$session_id, attempt_id = identity$attempt_id, protocol_id = identity$protocol_id,
    presentation_index = as.character(position), trial_id = trial$id, presented = "true",
    phase = trial$phase, round_id = scalar(trial$round_id), cell_id = scalar(trial$cell_id),
    expected_action = trial$expected_action, outcome = response$outcome,
    response_outcome = scalar(response$response_outcome), response_code = scalar(response$response_code),
    response_ms = scalar(response$response_ms), correct = scalar(response$correct), missing_reason = "",
    task_id = trial$task_id, origin = identity$origin, source_collection_id = identity$source_collection_id)
}

.brohn_gnat_import_trial_audit <- function(trial, response, source_row, timing_known) {
  disposition <- if (is.null(response)) "missing_expected_source_row" else
    if (!isTRUE(response$presented)) "not_presented" else
    if (identical(response$outcome, "interrupted")) "interrupted" else
    if (!isTRUE(trial$scored)) "unscored_by_profile" else
    if (!isTRUE(timing_known)) "timing_definition_unavailable" else "candidate_for_task_scoring"
  list(trial_id = trial$id, source_row = source_row, derived = is.null(response),
    profile_scored = isTRUE(trial$scored), block_id = trial$block_id,
    score_block = trial$cell_id, category_id = trial$category_id, action = trial$expected_action,
    phase = trial$phase, round_id = trial$round_id, cell_id = trial$cell_id,
    expected_action = trial$expected_action, outcome = response$outcome, correct = response$correct,
    disposition = disposition,
    missing_reason = if (is.null(response)) "Expected frozen trial has no source row." else response$missing_reason,
    declared_latency_ms = response$response_ms, original_fast_below_300 = NULL,
    scoring_latency_ms = NULL,
    scoring_basis = "Four terminal outcome counts; no response latency is imputed or scored.")
}
