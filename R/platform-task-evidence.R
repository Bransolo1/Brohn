# Native exports read the original complete journal and frozen task. They never
# reconstruct a participant's protocol from the current editable design.
brohn_task_evidence_from_run <- function(run, events, task_id) {
  brohn_require(is.list(run) && brohn_array(events) && brohn_valid_id(task_id), "Choose an original task administration.")
  brohn_require(identical(run$completion_status, "completed") && identical(run$transfer_status, "saved"),
    "Trial export requires a complete, durably saved participant session.")
  protocol <- run$protocol
  brohn_require(identical(.brohn_sv_hash(protocol$design), protocol$design_hash), "The frozen study definition failed its integrity check.")
  state <- .brohn_delivery_replay(protocol, events)
  brohn_require(isTRUE(state$run_finished) && identical(state$ending_outcome, "completed"),
    "Task export requires the complete original study journal, including its final outcome.")
  task <- brohn_find(protocol$design$blocks, task_id)
  steps <- Filter(function(s) identical(s$type, "task") && identical(s$task$id, task_id), protocol$timeline)
  brohn_require(!is.null(task) && length(steps) == 1L, "Choose one task from this session's original design.")
  step <- steps[[1L]]; compiled <- step$task; compiled_hash <- .brohn_sv_hash(compiled)
  registry_id <- paste0("protocol-", compiled_hash)
  registry <- list(schema = "brohn-implicit-protocol-registry/1.0", task = task,
    protocols = list(list(id = registry_id, compiled_hash = compiled_hash, compiled = compiled)))
  brohn_validate_task_protocol_registry(registry, protocol$design, task_id)
  trials <- Filter(function(t) identical(t$type, "task_trial"), compiled$timeline)
  terminal <- Filter(function(e) identical(e$type, "task_event") && identical(e$step_id, step$id) &&
    identical(e$payload$kind, "task_trial_finished"), events)
  ids <- vapply(terminal, function(e) e$payload$data$trial_id, character(1))
  brohn_require(!anyDuplicated(ids) && identical(ids, brohn_ids(trials)), "The saved terminal trial order differs from the original protocol.")
  code <- function(value) if (is.null(value)) "" else if (is.character(value)) value else brohn_json(value)
  rows <- lapply(seq_along(trials), function(i) {
    response <- terminal[[i]]$payload$data
    if (identical(task$profile, "gnat-brohn-single-target/1.0")) return(.brohn_gnat_native_row(trials[[i]], response,
      list(participant_id = brohn_default(run$participant_alias, run$id), participant_linkage = isTRUE(run$participant_alias_supplied),
        session_id = run$id, attempt_id = step$id, protocol_id = registry_id, origin = run$origin,
        source_collection_id = run$deployment_id), i))
    if (identical(task$profile, "sciat-brohn-response-window-im100/1.0")) {
      # Interchange aliases for the existing explicit first-response contract;
      # no correction key or latency is invented for an error or omission.
      response <- list(outcome = if (response$outcome == "omission") "timeout" else if (isTRUE(response$correct)) "correct" else "incorrect",
        response_code = response$response_code, first_correct = isTRUE(response$correct),
        first_response_ms = response$response_ms,
        final_code = if (isTRUE(response$correct)) response$response_code else NULL,
        final_correct_ms = if (isTRUE(response$correct)) response$response_ms else NULL)
    }
    list(participant_id = brohn_default(run$participant_alias, run$id), participant_linkage = code(isTRUE(run$participant_alias_supplied)),
      session_id = run$id, attempt_id = step$id, protocol_id = registry_id, presentation_index = as.character(i),
      trial_id = trials[[i]]$id, presented = "true", outcome = response$outcome,
      first_code = code(response$response_code), final_code = code(response$final_code), first_correct = code(response$first_correct),
      first_response_ms = code(response$first_response_ms), final_correct_ms = code(response$final_correct_ms), missing_reason = "",
      task_id = task_id, origin = run$origin, source_collection_id = run$deployment_id)
  })
  result <- list(schema = "brohn-native-task-export/1.0", run_id = run$id, task_id = task_id, task_step_id = step$id,
    collection_origin = run$origin, material_origin = task$origin, source_collection_id = run$deployment_id,
    registry = registry, rows = rows,
    evidence = list(level = "brohn_journal_replayed", run_protocol_hash = .brohn_sv_hash(protocol), events_hash = .brohn_sv_hash(events),
      compiled_hash = compiled_hash, validation = "brohn-native-task-export/1.0",
      summary_import_evidence_level = "declared_trial_summary",
      timing = "Observed browser timing; physical display and response timing are not qualified by replay."),
    declarations = list(source_software = NULL, source_rt_definition = "first_and_final_correct_ms_from_target_onset",
      terminal_response_rule = if (brohn_task_profile(task$profile)$kind %in% c("iat", "biat"))
        "corrected_response_or_fixed_deadline" else "first_response_or_fixed_deadline",
      note = paste("The original collection renderer code version is not recorded by this protocol. Current validation code is not a collection-time version.",
        if (identical(task$profile, "sciat-brohn-response-window-im100/1.0"))
          "SC-IAT final-correct interchange fields repeat only a correct first response; errors and omissions have no final-correct value. Full native key/feedback observations remain in the original session journal." else "")))
  if (identical(task$profile, "gnat-brohn-single-target/1.0")) {
    result$declarations$adapter <- .brohn_gnat_import_adapter
    result$declarations$source_rt_definition <- "space_ms_from_onset_no_rt_for_withholding"
    result$declarations$terminal_response_rule <- "space_or_visible_deadline"
    result$declarations$note <- paste(result$declarations$note,
      "GNAT retains hit, miss, false alarm and correct rejection. Withholding has no key or response time; completed correct rejections have true accuracy. Original release/key/visibility/feedback evidence remains in the full journal.")
  }
  result
}
brohn_task_run_evidence <- function(store, run_id, study_id, project_id, task_id) {
  # Exact parent/project gate precedes the full private run read. Only explicitly
  # constructed non-credential fields escape in the export document.
  snapshot <- brohn_run_protocol(store, run_id, study_id, project_id)
  run <- brohn_run(store, run_id)
  brohn_require(!is.null(run) && identical(.brohn_sv_hash(run$protocol), .brohn_sv_hash(snapshot$protocol)), "The selected session changed unexpectedly.")
  result <- brohn_task_evidence_from_run(run, brohn_run_events(store, run_id), task_id)
  result$evidence$saved_protocol_bytes_hash <- snapshot$hash
  result
}
brohn_export_task_trial_csv <- function(evidence, path) {
  brohn_require(identical(evidence$schema, "brohn-native-task-export/1.0") && length(evidence$rows) > 0L,
    "Choose a complete native task export.")
  columns <- names(evidence$rows[[1L]])
  table <- as.data.frame(setNames(lapply(columns, function(column)
    vapply(evidence$rows, function(row) row[[column]], character(1))), columns), stringsAsFactors = FALSE)
  # This is an explicit machine interchange file. Preserve original participant
  # codes and decimal strings; spreadsheet-safe score downloads are separate.
  utils::write.csv(table, path, row.names = FALSE, na = "", fileEncoding = "UTF-8")
  invisible(path)
}
brohn_export_task_registry <- function(evidence, path) {
  brohn_require(identical(evidence$schema, "brohn-native-task-export/1.0"), "Choose an original task registry.")
  brohn_write_json_file(evidence$registry, path)
}
