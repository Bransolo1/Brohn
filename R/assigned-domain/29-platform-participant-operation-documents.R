# Inactive pure encoder. Descriptors/state are caller declarations, not source,
# request-admission or authority proofs. Never reconstruct a historical receipt.
.brohn_pvod_object <- function(x, fields, label) {
  brohn_require(typeof(x) == "list" && !is.null(names(x)), paste(label, "must be an object."))
  brohn_fields(x, fields, label = label)
  invisible(TRUE)
}
.brohn_pvod_bool <- function(x) is.logical(x) && length(x) == 1L && !is.na(x)
.brohn_pvod_key <- function(x, prefix, nullable = FALSE) isTRUE(nullable) && is.null(x) || .brohn_pvc_key(x, prefix)
.brohn_pvod_keys <- function(x, prefix, label) {
  brohn_require(typeof(x) == "list" && is.null(names(x)) && length(x) <= 20000L &&
    all(vapply(x, .brohn_pvc_key, logical(1), prefix = prefix)), paste(label, "requires an array of participant keys."))
  brohn_require(!anyDuplicated(unlist(x, use.names = FALSE)), paste(label, "repeats a participant key."))
}
.brohn_pvod_visit <- function(x) {
  if (is.null(x)) return(invisible(TRUE))
  .brohn_pvod_object(x, c("id", "step_key", "instance_id", "time_origin_ms", "onset_ms", "resumed", "committed"), "Projected visit")
  decimal <- function(v) brohn_text(v, 64L) && grepl("^[0-9]+([.][0-9]+)?$", v)
  brohn_require(brohn_text(x$id, 128L) && .brohn_pvc_key(x$step_key, "pvs") && brohn_text(x$instance_id, 128L) &&
    decimal(x$time_origin_ms) && decimal(x$onset_ms) && .brohn_pvod_bool(x$resumed) && .brohn_pvod_bool(x$committed),
    "Projected visit fields have invalid types.")
  invisible(TRUE)
}
.brohn_pvod_answers <- function(x) {
  .brohn_pvod_object(x, c("before", "after_each", "end"), "Projected answer scopes")
  scope <- function(v) {
    brohn_require(typeof(v) == "list" && !is.null(names(v)) &&
      all(vapply(as.list(names(v)), .brohn_pvc_key, logical(1), prefix = "pvq")),
      "Projected answers require participant question keys.")
    # Values retain the accepted question-specific representation. This encoder
    # has no question/map authority and must not coerce or reinterpret answers.
  }
  scope(x$before); scope(x$end)
  brohn_require(typeof(x$after_each) == "list" && !is.null(names(x$after_each)) &&
    all(vapply(as.list(names(x$after_each)), .brohn_pvc_key, logical(1), prefix = "pvi")),
    "Projected after-stimulus answers require participant stimulus keys.")
  for (v in x$after_each) scope(v)
  invisible(TRUE)
}
.brohn_pvod_record <- function(x) {
  .brohn_pvod_object(x, c("step_key", "occurrence_key", "question_key", "stimulus_key", "scope", "information", "status", "value",
    "ever_visited", "dependency_generation", "last_answer_event_id", "answer_version", "revision_count"), "Projected questionnaire record")
  brohn_require(.brohn_pvc_key(x$step_key, "pvs") && .brohn_pvc_key(x$occurrence_key, "pvo") &&
    .brohn_pvc_key(x$question_key, "pvq") && .brohn_pvod_key(x$stimulus_key, "pvi", TRUE) &&
    is.character(x$scope) && length(x$scope) == 1L && x$scope %in% c("before", "after_each", "end") &&
    .brohn_pvod_bool(x$information) && .brohn_pvod_bool(x$ever_visited) &&
    is.character(x$status) && length(x$status) == 1L && x$status %in% c("not_displayed", "information_acknowledged",
      "information_unacknowledged", "optional_omission", "answered", "invalidated_unanswered", "not_submitted") &&
    (is.null(x$last_answer_event_id) || brohn_text(x$last_answer_event_id, 128L)) &&
    all(vapply(x[c("dependency_generation", "answer_version", "revision_count")], brohn_number,
      logical(1), min = 0, max = 10000000, integer = TRUE)), "Projected questionnaire record fields have invalid types.")
  invisible(TRUE)
}
.brohn_pvod_packet <- function(x, view_hash, ack) {
  .brohn_pvod_object(x, c("schema", "view_hash", "acknowledged_sequence", "cursor", "next_step_key", "packet_state_token",
    "latest_occurrence", "last_transition", "actions", "resume_page"), "Projected questionnaire packet")
  brohn_require(identical(x$schema, "participant-questionnaire-packet/0.1") && identical(x$view_hash, view_hash) &&
    brohn_number(x$acknowledged_sequence, ack, ack, TRUE) && brohn_number(x$cursor, 1, 20001, TRUE) &&
    .brohn_pvod_key(x$next_step_key, "pvs", TRUE) && .brohn_ph_sha(x$packet_state_token),
    "Projected questionnaire packet differs from the committed view or ACK.")
  latest <- x$latest_occurrence
  if (!is.null(latest)) {
    .brohn_pvod_object(latest, c("occurrence_key", "state_version", "sealed", "review_step_key", "projection_token", "visit"), "Projected latest occurrence")
    brohn_require(.brohn_pvc_key(latest$occurrence_key, "pvo") && brohn_number(latest$state_version, 0, 10000000, TRUE) &&
      .brohn_pvod_bool(latest$sealed) && .brohn_pvc_key(latest$review_step_key, "pvs") && .brohn_ph_sha(latest$projection_token),
      "Projected latest occurrence fields have invalid types.")
    .brohn_pvod_visit(latest$visit)
  }
  transition <- x$last_transition
  if (!is.null(transition)) {
    .brohn_pvod_object(transition, c("occurrence_key", "kind", "state_version", "sealed", "projection_token"), "Projected last transition")
    brohn_require(.brohn_pvc_key(transition$occurrence_key, "pvo") && is.character(transition$kind) && length(transition$kind) == 1L &&
      transition$kind %in% c("visit", "commit", "acknowledge", "seal") && brohn_number(transition$state_version, 0, 10000000, TRUE) &&
      .brohn_pvod_bool(transition$sealed) && (is.null(transition$projection_token) || .brohn_ph_sha(transition$projection_token)),
      "Projected last transition fields have invalid types.")
  }
  a <- x$actions
  .brohn_pvod_object(a, c("enter_step_key", "next_step_key", "back_step_key", "editable_step_keys", "can_seal"), "Projected questionnaire actions")
  brohn_require(all(vapply(a[c("enter_step_key", "next_step_key", "back_step_key")], .brohn_pvod_key,
    logical(1), prefix = "pvs", nullable = TRUE)) && .brohn_pvod_bool(a$can_seal), "Projected questionnaire action fields have invalid types.")
  .brohn_pvod_keys(a$editable_step_keys, "pvs", "Projected editable steps")
  p <- x$resume_page
  .brohn_pvod_object(p, c("schema", "view_hash", "resume_state_token", "active_occurrence_key", "state_version", "visit", "visible_step_keys",
    "records", "total_records", "offset", "next_offset"), "Projected questionnaire resume page")
  brohn_require(identical(p$schema, "participant-questionnaire-resume/0.1") && identical(p$view_hash, view_hash) &&
    .brohn_ph_sha(p$resume_state_token) && .brohn_pvod_key(p$active_occurrence_key, "pvo", TRUE) &&
    (is.null(p$state_version) || brohn_number(p$state_version, 0, 10000000, TRUE)) &&
    typeof(p$records) == "list" && is.null(names(p$records)) && brohn_number(p$total_records, 0, 20000, TRUE) &&
    brohn_number(p$offset, 0, p$total_records, TRUE) && length(p$records) <= p$total_records - p$offset,
    "Projected questionnaire page has invalid fields or offsets.")
  .brohn_pvod_visit(p$visit); .brohn_pvod_keys(p$visible_step_keys, "pvs", "Projected visible steps")
  if (is.null(p$active_occurrence_key)) brohn_require(is.null(p$state_version) && is.null(p$visit) && !length(p$visible_step_keys),
    "An inactive projected page cannot retain an active visit.") else
    brohn_require(!is.null(p$state_version), "An active projected page needs its state version.")
  end <- p$offset + length(p$records)
  brohn_require(if (end == p$total_records) is.null(p$next_offset) else
    end > p$offset && brohn_number(p$next_offset, end, end, TRUE), "Projected page has no complete-record continuation.")
  for (r in p$records) .brohn_pvod_record(r)
  brohn_require(!anyDuplicated(vapply(p$records, `[[`, character(1), "step_key")), "Projected page repeats a questionnaire record.")
  brohn_require(brohn_participant_json_bytes(x)$bytes <= 3 * 1024^2, "Projected packet exceeds its 3 MiB input bound.")
  invisible(TRUE)
}
.brohn_pvod_inputs <- function(binding, operation, commit) {
  # Plain domain and original text checks happen before keyed access. Final
  # encoding separately enforces the wire codec's node, depth and byte limits.
  for (x in list(binding, operation, commit)) .brohn_vad_domain(x)
  .brohn_pvod_object(binding, c("schema", "run_id", "source_protocol_hash", "renderer_identity", "view_codec", "view_bytes", "view_hash"), "Commit binding")
  brohn_require(identical(binding$schema, "participant-view-binding/0.1") && .brohn_pvc_key(binding$run_id, "pvu") &&
    .brohn_ph_sha(binding$source_protocol_hash) && .brohn_ph_sha(binding$view_hash) &&
    identical(binding$view_codec, "brohn-participant-json-bytes/0.1") && brohn_number(binding$view_bytes, 1, 16 * 1024^2, TRUE),
    "Commit binding has an invalid presentation descriptor.")
  .brohn_pvc_renderer(binding$renderer_identity)
  .brohn_pvod_object(operation, c("operation_id", "request", "sequence"), "Operation declaration")
  brohn_require(brohn_text(operation$operation_id, 128L), "Operation identity is required.")
  .brohn_pvod_object(operation$request, c("codec", "bytes", "sha256"), "Received request descriptor")
  brohn_require(identical(operation$request$codec, "brohn-participant-request-json/0.1") &&
    brohn_number(operation$request$bytes, 1, 4 * 1024^2, TRUE) && .brohn_ph_sha(operation$request$sha256),
    "Received request descriptor is invalid.")
  s <- operation$sequence
  .brohn_pvod_object(s, c("first", "last", "count", "prior_ack", "committed_ack"), "Operation sequence declaration")
  brohn_require(brohn_number(s$prior_ack, 0, 9999999, TRUE) && brohn_number(s$count, 1, 1000, TRUE) &&
    brohn_number(s$first, s$prior_ack + 1, s$prior_ack + 1, TRUE) && brohn_number(s$last, s$first, 10000000, TRUE) &&
    brohn_number(s$committed_ack, s$last, s$last, TRUE) && s$last - s$first + 1 == s$count,
    "Operation must declare one complete next contiguous suffix.")
  .brohn_pvod_object(commit, c("completion_status", "resume", "origin", "release_status"), "Commit-state declaration")
  brohn_require(identical(commit$completion_status, "in_progress") && is.character(commit$origin) && length(commit$origin) == 1L &&
    commit$origin %in% c("sample", "pilot", "live") && is.character(commit$release_status) && length(commit$release_status) == 1L &&
    commit$release_status %in% c("open", "paused", "closed"), "New-operation commit metadata is invalid.")
  r <- commit$resume
  .brohn_pvod_object(r, c("schema", "view_hash", "next_step_key", "completed_step_keys", "active_step_key", "active_clock_instance_id", "answers", "questionnaire"),
    "Projected forward resume")
  brohn_require(identical(r$schema, "participant-forward-resume/0.1") && identical(r$view_hash, binding$view_hash) &&
    .brohn_pvod_key(r$next_step_key, "pvs", TRUE) && .brohn_pvod_key(r$active_step_key, "pvs", TRUE) &&
    (if (is.null(r$active_step_key)) is.null(r$active_clock_instance_id) else brohn_text(r$active_clock_instance_id, 128L)),
    "Projected resume differs from the committed view or active step.")
  .brohn_pvod_keys(r$completed_step_keys, "pvs", "Projected completed steps"); .brohn_pvod_answers(r$answers)
  if (!is.null(r$questionnaire)) {
    .brohn_pvod_packet(r$questionnaire, binding$view_hash, s$committed_ack)
    brohn_require(identical(r$questionnaire$next_step_key, r$next_step_key), "Projected packet and resume cursors disagree.")
  }
  invisible(TRUE)
}
.brohn_pvod_encode <- function(binding, operation, commit) {
  .brohn_pvod_inputs(binding, operation, commit)
  limit <- 4 * 1024^2; packet <- commit$resume$questionnaire
  all <- if (is.null(packet)) NULL else packet$resume_page$records
  candidate <- function(n) {
    resume <- commit$resume
    if (!is.null(packet)) {
      resume$questionnaire$resume_page$records <- if (n) all[seq_len(n)] else list()
      end <- packet$resume_page$offset + n
      resume$questionnaire$resume_page["next_offset"] <- list(if (end < packet$resume_page$total_records) end else NULL)
      if (brohn_participant_json_bytes(resume$questionnaire)$bytes > 3 * 1024^2) return(NULL)
    }
    model_value <- list(schema = "participant-view-commit-model/0.1", binding = binding,
      acknowledged_sequence = operation$sequence$committed_ack, expected_sequence = operation$sequence$committed_ack + 1,
      completion_status = commit$completion_status, resume = resume, origin = commit$origin,
      release_status = commit$release_status, researcher_resolution = NULL)
    model <- brohn_participant_json_bytes(model_value)
    if (model$bytes > limit) return(NULL)
    receipt_value <- list(schema = "participant-view-operation-receipt/0.1", binding = binding,
      operation_id = operation$operation_id, request = operation$request, sequence = operation$sequence,
      model = model[c("codec", "bytes", "sha256")])
    receipt <- brohn_participant_json_bytes(receipt_value)
    result <- brohn_participant_json_bytes(list(schema = "participant-view-events-result/0.1", receipt = receipt_value, model_json = model$json))
    if (result$bytes > limit) return(NULL)
    list(model = model, receipt = receipt, result = result)
  }
  count <- if (is.null(packet)) 0L else length(all)
  full <- candidate(count)
  if (!is.null(full)) return(full)
  brohn_require(!is.null(packet), "The complete forward-only operation result exceeds 4 MiB; nothing may be truncated.")
  minimum <- if (packet$resume_page$offset < packet$resume_page$total_records) 1L else 0L
  best <- candidate(minimum)
  brohn_require(!is.null(best), "Operation metadata or one complete questionnaire record exceeds the escaped result budget.")
  low <- minimum; high <- count - 1L
  # At most ceiling(log2(20000)) probes after the full/minimum candidates.
  # No maximal-page guarantee: only the exact measured successful prefix is used.
  while (low < high) {
    middle <- as.integer(ceiling((low + high) / 2))
    next_candidate <- candidate(middle)
    if (is.null(next_candidate)) high <- middle - 1L else { low <- middle; best <- next_candidate }
  }
  best
}
