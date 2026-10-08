# Inactive source-to-view state projection. Inputs must come from fresh original
# receiver replay under the separately admitted stored-view context. This module
# cannot authenticate a journal, source bytes, participant or current authority.
.brohn_pvs_object <- function(value, label) {
  brohn_require(is.list(value) && !is.null(names(value)) && !anyNA(names(value)) &&
    !anyDuplicated(names(value)) && all(nzchar(names(value))), paste(label, "must be a keyed object."))
  invisible(value)
}
.brohn_pvs_array <- function(value, maximum = 20000L) {
  brohn_require(brohn_array(value) && length(value) <= maximum, "State identities require a bounded ordered array.")
  invisible(value)
}
.brohn_pvs_key <- function(context, kind, source_id, nullable = FALSE) {
  if (is.null(source_id)) {
    brohn_require(nullable, "A required state identity is absent.")
    return(NULL)
  }
  brohn_require(brohn_text(source_id, 128L), "State identity must be an actual source identifier.")
  rows <- context$projection$private_map[[kind, exact = TRUE]]
  .brohn_pvc_lookup(rows, "source_id", source_id)$key
}
.brohn_pvs_step <- function(context, source_id) {
  context$step(.brohn_pvs_key(context, "steps", source_id))
}
.brohn_pvs_steps <- function(context, values) {
  .brohn_pvs_array(values)
  result <- lapply(values, function(id) .brohn_pvs_key(context, "steps", id))
  brohn_require(!anyDuplicated(unlist(result, use.names = FALSE)), "State repeats an assigned step identity.")
  result
}
.brohn_pvs_token <- function(context, domain, source_hash, occurrence_key = NULL) {
  brohn_require(.brohn_ph_sha(source_hash), "State requires its exact original digest.")
  value <- list(domain = domain, view_hash = context$view_hash)
  if (identical(domain, "participant-packet-state/0.1")) value$original_packet_state_hash <- source_hash else
    if (identical(domain, "participant-resume-state/0.1")) value$original_resume_state_hash <- source_hash else {
      brohn_require(identical(domain, "participant-questionnaire-projection/0.1") &&
        .brohn_pvc_key(occurrence_key, "pvo"), "Unknown state token domain.")
      value$occurrence_key <- occurrence_key; value$original_projection_hash <- source_hash
    }
  brohn_participant_json_bytes(value)$sha256
}
.brohn_pvs_visit <- function(context, visit, occurrence_id) {
  if (is.null(visit)) return(NULL)
  brohn_fields(visit, c("id", "step_id", "instance_id", "time_origin_ms", "onset_ms", "resumed", "committed"), label = "Original questionnaire visit")
  step <- .brohn_pvs_step(context, visit$step_id)
  brohn_require(identical(step$mapping$occurrence_id, occurrence_id), "Visit belongs to another questionnaire occurrence.")
  c(list(id = visit$id, step_key = step$mapping$key), visit[c("instance_id", "time_origin_ms", "onset_ms", "resumed", "committed")])
}
.brohn_pvs_answer <- function(context, source_id, value, scope, stimulus_id = NULL) {
  map <- context$projection$private_map
  q <- .brohn_pvq_lookup(map$questions$entries, "source_id", source_id)
  brohn_require(identical(q$scope, scope), "Answer scope differs from its original question.")
  assigned <- Filter(function(s) identical(s$question_id, source_id) && identical(s$stimulus_id, stimulus_id), map$steps)
  brohn_require(length(assigned) > 0L, "Answer has no assigned question and stimulus occurrence.")
  list(key = q$question_key, value = brohn_translate_participant_answer(map$questions, q$question_key, value, "to_view"))
}
.brohn_pvs_answers <- function(context, answers) {
  brohn_fields(answers, c("before", "after_each", "end"), label = "Original answer scopes")
  project <- function(values, scope, stimulus_id = NULL) {
    .brohn_pvs_object(values, "Answer scope")
    out <- structure(list(), names = character())
    for (id in names(values)) {
      a <- .brohn_pvs_answer(context, id, values[[id, exact = TRUE]], scope, stimulus_id)
      out[a$key] <- list(a$value)
    }
    out
  }
  .brohn_pvs_object(answers$after_each, "After-stimulus scopes")
  after <- structure(list(), names = character())
  for (id in names(answers$after_each)) after[.brohn_pvs_key(context, "stimuli", id)] <-
    list(project(answers$after_each[[id, exact = TRUE]], "after_each", id))
  list(before = project(answers$before, "before"), end = project(answers$end, "end"), after_each = after)
}
.brohn_pvs_record <- function(context, row) {
  brohn_fields(row, c("occurrence_id", "question_id", "step_id", "exposure_id", "scope", "assessment_id", "assessment_exposure_id",
    "stimulus_id", "condition_id", "information", "status", "value", "missing_reason", "ever_visited", "invalidated", "dependency_generation",
    "event_id", "last_answer_event_id", "first_answer_event_id", "answer_version", "revision_count", "sequence", "response_time_ms",
    "active_segment_response_ms", "resumed"), label = "Original questionnaire record")
  step <- .brohn_pvs_step(context, row$step_id); s <- step$source_step; m <- step$mapping
  brohn_require(identical(s$type, "question") && identical(row$question_id, m$question_id) &&
    identical(row$occurrence_id, m$occurrence_id) && identical(row$stimulus_id, m$stimulus_id) &&
    identical(row$condition_id, m$condition_id) && identical(row$exposure_id, m$source_id) &&
    identical(row$scope, s$question$scope) && identical(row$information, s$question$type == "information"),
    "Questionnaire record differs from its assigned question or occurrence.")
  occurrence <- context$occurrence(.brohn_pvs_key(context, "occurrences", row$occurrence_id))
  o <- occurrence$source_occurrence
  brohn_require(identical(row$assessment_exposure_id, o$stimulus_step_id) &&
    identical(row$assessment_id, if (o$scope == "after_each") paste0("stimulus-step:", o$stimulus_step_id) else paste0("scope:", o$scope)),
    "Questionnaire record has a foreign assessment anchor.")
  a <- .brohn_pvs_answer(context, row$question_id, row$value, row$scope, row$stimulus_id)
  c(list(step_key = m$key, occurrence_key = occurrence$mapping$key, question_key = a$key,
    stimulus_key = .brohn_pvs_key(context, "stimuli", row$stimulus_id, TRUE), scope = row$scope,
    information = row$information, status = row$status, value = a$value),
    row[c("ever_visited", "dependency_generation", "last_answer_event_id", "answer_version", "revision_count")])
}
.brohn_pvs_resume_page <- function(context, page) {
  brohn_fields(page, c("schema", "protocol_hash", "state_hash", "active_occurrence_id", "state_version", "visit", "visible_step_ids",
    "records", "total_records", "offset", "next_offset"), label = "Original questionnaire resume page")
  brohn_require(identical(page$schema, "brohn-questionnaire-revision-resume/1.0") &&
    identical(page$protocol_hash, context$source_protocol_hash), "Resume page belongs to another original protocol.")
  .brohn_pvs_array(page$records)
  brohn_require(brohn_number(page$total_records, 0, 20000, TRUE) && brohn_number(page$offset, 0, page$total_records, TRUE) &&
    length(page$records) <= page$total_records - page$offset, "Resume page has invalid whole-record offsets.")
  end <- page$offset + length(page$records)
  brohn_require(if (end == page$total_records) is.null(page$next_offset) else
    brohn_number(page$next_offset, end, end, TRUE) && end > page$offset, "Resume page has no valid complete-record continuation.")
  visible <- .brohn_pvs_steps(context, page$visible_step_ids)
  active <- .brohn_pvs_key(context, "occurrences", page$active_occurrence_id, TRUE)
  if (is.null(active)) brohn_require(is.null(page$state_version) && is.null(page$visit) && !length(visible),
    "Inactive resume cannot invent an active questionnaire visit.") else {
    brohn_require(brohn_number(page$state_version, 0, 10000000, TRUE), "Active questionnaire state version is invalid.")
    for (key in visible) brohn_require(identical(context$step(key)$mapping$occurrence_id, page$active_occurrence_id),
      "Visible question belongs to another occurrence.")
  }
  records <- lapply(page$records, .brohn_pvs_record, context = context)
  brohn_require(!anyDuplicated(vapply(records, `[[`, character(1), "step_key")), "Resume page repeats a question record.")
  list(schema = "participant-questionnaire-resume/0.1", view_hash = context$view_hash,
    resume_state_token = .brohn_pvs_token(context, "participant-resume-state/0.1", page$state_hash),
    active_occurrence_key = active, state_version = page$state_version,
    visit = .brohn_pvs_visit(context, page$visit, page$active_occurrence_id), visible_step_keys = visible,
    records = records, total_records = page$total_records, offset = page$offset, next_offset = page$next_offset)
}
.brohn_pvs_packet <- function(context, packet) {
  brohn_fields(packet, c("schema", "acknowledged_sequence", "protocol_hash", "protocol_cursor", "next_step_id", "state_hash",
    "latest_occurrence", "last_transition", "actions", "resume_page"), label = "Original questionnaire packet")
  brohn_require(!is.null(context$revision_context) && identical(packet$schema, "brohn-questionnaire-packet/1.0") &&
    identical(packet$protocol_hash, context$source_protocol_hash) && brohn_number(packet$acknowledged_sequence, 0, 10000000, TRUE) &&
    brohn_number(packet$protocol_cursor, 1, length(context$protocol$timeline) + 1L, TRUE), "Questionnaire packet has an invalid original binding.")
  expected_next <- if (packet$protocol_cursor <= length(context$protocol$timeline)) context$protocol$timeline[[packet$protocol_cursor]]$id else NULL
  brohn_require(identical(expected_next, packet$next_step_id), "Packet cursor and next step disagree.")
  latest <- packet$latest_occurrence
  if (!is.null(latest)) {
    brohn_fields(latest, c("id", "state_version", "sealed", "review_step_id", "projection_hash", "visit"), label = "Original latest occurrence")
    key <- .brohn_pvs_key(context, "occurrences", latest$id)
    occurrence <- context$occurrence(key)
    brohn_require(identical(latest$review_step_id, occurrence$source_occurrence$review_step_id), "Occurrence review step differs.")
    latest <- list(occurrence_key = key, state_version = latest$state_version, sealed = latest$sealed,
      review_step_key = .brohn_pvs_key(context, "steps", latest$review_step_id),
      projection_token = .brohn_pvs_token(context, "participant-questionnaire-projection/0.1", latest$projection_hash, key),
      visit = .brohn_pvs_visit(context, latest$visit, latest$id))
  }
  transition <- packet$last_transition
  if (!is.null(transition)) {
    brohn_fields(transition, c("occurrence_id", "kind", "state_version", "sealed", "projection_hash"), label = "Original questionnaire transition")
    key <- .brohn_pvs_key(context, "occurrences", transition$occurrence_id)
    transition <- c(list(occurrence_key = key), transition[c("kind", "state_version", "sealed")], list(projection_token =
      if (is.null(transition$projection_hash)) NULL else .brohn_pvs_token(context, "participant-questionnaire-projection/0.1", transition$projection_hash, key)))
  }
  a <- packet$actions
  brohn_fields(a, c("enter_step_id", "next_step_id", "back_step_id", "editable_step_ids", "can_seal"), label = "Original questionnaire actions")
  actions <- list(enter_step_key = .brohn_pvs_key(context, "steps", a$enter_step_id, TRUE),
    next_step_key = .brohn_pvs_key(context, "steps", a$next_step_id, TRUE), back_step_key = .brohn_pvs_key(context, "steps", a$back_step_id, TRUE),
    editable_step_keys = .brohn_pvs_steps(context, a$editable_step_ids), can_seal = a$can_seal)
  for (key in c(actions[c("enter_step_key", "next_step_key", "back_step_key")], actions$editable_step_keys)) if (!is.null(key))
    brohn_require(!is.null(latest) && identical(context$step(key)$mapping$occurrence_id, packet$latest_occurrence$id),
      "Questionnaire action belongs to another occurrence.")
  list(schema = "participant-questionnaire-packet/0.1", view_hash = context$view_hash, acknowledged_sequence = packet$acknowledged_sequence,
    cursor = packet$protocol_cursor, next_step_key = .brohn_pvs_key(context, "steps", packet$next_step_id, TRUE),
    packet_state_token = .brohn_pvs_token(context, "participant-packet-state/0.1", packet$state_hash), latest_occurrence = latest,
    last_transition = transition, actions = actions, resume_page = .brohn_pvs_resume_page(context, packet$resume_page))
}
# Project first, then reduce only the complete record prefix to the byte budget.
# Metadata/visible question membership and an individual typed answer never shrink.
.brohn_pvs_fit <- function(packet, maximum_bytes) {
  brohn_require(brohn_number(maximum_bytes, 1024, 3L * 1024L^2L, TRUE), "Choose a supported participant packet byte budget.")
  all <- packet$resume_page$records; offset <- packet$resume_page$offset; total <- packet$resume_page$total_records
  prefix <- function(n) {
    result <- packet; result$resume_page$records <- if (n) all[seq_len(n)] else list()
    result$resume_page["next_offset"] <- list(if (offset + n < total) offset + n else NULL)
    result
  }
  minimum <- if (offset < total) 1L else 0L
  brohn_require(length(all) >= minimum, "Source page has no complete next record.")
  base <- prefix(0L)
  base_bytes <- brohn_participant_json_bytes(base, maximum_bytes = maximum_bytes)$bytes
  base_next_bytes <- brohn_participant_json_bytes(base$resume_page$next_offset)$bytes
  count <- 0L; record_bytes <- 0
  for (i in seq_along(all)) {
    record_bytes <- record_bytes + brohn_participant_json_bytes(all[[i]])$bytes
    next_offset <- if (offset + i < total) offset + i else NULL
    # Exactly replace the empty [] contents with complete encoded records and
    # commas. Recompute next_offset's actual encoding, including final null.
    bytes <- base_bytes - base_next_bytes + brohn_participant_json_bytes(next_offset)$bytes + record_bytes + i - 1L
    if (bytes > maximum_bytes) break
    count <- i
  }
  brohn_require(count >= minimum, "Questionnaire metadata or one complete answer exceeds the participant page budget.")
  result <- prefix(count)
  brohn_participant_json_bytes(result, maximum_bytes = maximum_bytes)
  result
}
brohn_project_participant_questionnaire_packet <- function(context, packet, maximum_bytes = 3L * 1024L^2L) {
  brohn_assert_participant_view_context(context); .brohn_pvq_plain(packet)
  .brohn_pvs_fit(.brohn_pvs_packet(context, packet), maximum_bytes)
}
brohn_project_participant_forward_resume <- function(context, resume) {
  brohn_assert_participant_view_context(context); .brohn_pvq_plain(resume)
  brohn_fields(resume, c("next_step_id", "completed_step_ids", "answers", "active_step_id", "active_clock_instance_id"),
    optional = "questionnaire", label = "Original forward resume")
  brohn_require(identical("questionnaire" %in% names(resume), !is.null(context$revision_context)),
    "Resume navigation mode differs from the admitted original.")
  if (is.null(resume$active_step_id)) brohn_require(is.null(resume$active_clock_instance_id), "An inactive step cannot retain a page clock.") else
    brohn_require(brohn_text(resume$active_clock_instance_id, 128L), "An active step needs its original page clock.")
  list(schema = "participant-forward-resume/0.1", view_hash = context$view_hash,
    next_step_key = .brohn_pvs_key(context, "steps", resume$next_step_id, TRUE),
    completed_step_keys = .brohn_pvs_steps(context, resume$completed_step_ids),
    active_step_key = .brohn_pvs_key(context, "steps", resume$active_step_id, TRUE), active_clock_instance_id = resume$active_clock_instance_id,
    answers = .brohn_pvs_answers(context, resume$answers), questionnaire = if (is.null(context$revision_context)) NULL else
      brohn_project_participant_questionnaire_packet(context, resume$questionnaire))
}
brohn_participant_questionnaire_page_request <- function(context, request, current_packet) {
  brohn_assert_participant_view_context(context); .brohn_pvq_plain(request); .brohn_pvq_plain(current_packet)
  brohn_fields(request, c("schema", "offset", "packet_state_token", "view_hash", "source_protocol_hash"), label = "Participant questionnaire page request")
  brohn_require(identical(request$schema, "participant-questionnaire-page-request/0.1") && identical(request$view_hash, context$view_hash) &&
    identical(request$source_protocol_hash, context$source_protocol_hash) && brohn_number(request$offset, 0, 20000, TRUE) &&
    (is.null(request$packet_state_token) || .brohn_ph_sha(request$packet_state_token)) &&
    (request$offset == 0L || !is.null(request$packet_state_token)), "Request a page bound to this exact saved view and state.")
  # Full packet projection binds the supplied original packet; caller must have
  # freshly replayed it under current authority at the requested offset.
  projected <- .brohn_pvs_packet(context, current_packet)
  brohn_require(request$offset == projected$resume_page$offset && (is.null(request$packet_state_token) ||
    identical(request$packet_state_token, projected$packet_state_token)), "Questionnaire state changed; reload from the first page.")
  list(offset = request$offset, state_hash = current_packet$state_hash)
}
