# Inactive explicit questionnaire identity translation. This is not an event
# receiver: the later authorized transaction must retain exact received bytes,
# apply original replay and atomically persist received/derived evidence.
brohn_translate_participant_questionnaire_event <- function(context, event, current_packet) {
  brohn_assert_participant_view_context(context)
  .brohn_pvq_plain(event); .brohn_pvq_plain(current_packet)
  brohn_fields(event, c("sequence", "id", "type", "step_key", "phase", "clock", "payload"), label = "Participant questionnaire event")
  brohn_require(identical(event$type, "questionnaire_event") && brohn_number(event$sequence, 1, 10000000, TRUE) &&
    brohn_text(event$id, 128L), "Use a named ordered questionnaire event.")
  step <- context$step(event$step_key); s <- step$source_step; m <- step$mapping
  brohn_require(s$type %in% c("question", "questionnaire_review") && !is.null(m$occurrence_id) &&
    identical(event$phase, s$phase), "Questionnaire evidence requires its assigned assessment step and phase.")
  .brohn_revision_clock(event$clock)
  p <- event$payload
  brohn_require(is.list(p) && brohn_text(p$kind, 32L) && p$kind %in% c("visit", "commit", "acknowledge", "seal"),
    "Choose a supported participant questionnaire transition.")
  fields <- switch(p$kind, visit = c("visit_id", "reason", "from_visit_id"),
    commit = c("visit_id", "previous_answer_event_id", "dependency_generation", "value", "response_time_ms", "active_segment_response_ms", "resumed"),
    acknowledge = "visit_id", seal = c("visit_id", "projection_token"))
  brohn_fields(p, c("schema", "kind", "occurrence_key", "state_version", fields, "clock_segment_id", "time_origin_ms"),
    label = "Participant questionnaire transition")
  brohn_require(identical(p$schema, "participant-questionnaire-event/0.1") &&
    brohn_number(p$state_version, 0, 10000000, TRUE) && identical(p$clock_segment_id, event$clock$instance_id) &&
    identical(p$time_origin_ms, event$clock$time_origin_ms), "Keep the original transition version and explicit page clock.")
  occurrence <- context$occurrence(p$occurrence_key)
  brohn_require(identical(occurrence$mapping$source_id, m$occurrence_id), "Event occurrence differs from its assigned step.")
  # The packet must be freshly derived in the enclosing transaction. Projection
  # checks its source/map binding; it does not authenticate a caller's packet.
  projected <- .brohn_pvs_packet(context, current_packet)
  brohn_require(!is.null(projected$latest_occurrence) &&
    identical(projected$latest_occurrence$occurrence_key, p$occurrence_key) &&
    projected$latest_occurrence$state_version == p$state_version && !isTRUE(projected$latest_occurrence$sealed),
    "Questionnaire state changed; restore the current unsealed occurrence.")
  translated <- c(list(schema = "brohn-questionnaire-event/1.0", kind = p$kind, occurrence_id = m$occurrence_id,
    state_version = p$state_version), p[setdiff(fields, "projection_token")], p[c("clock_segment_id", "time_origin_ms")])
  if (p$kind == "commit") {
    brohn_require(identical(s$type, "question") && s$question$type != "information", "This step does not accept an answer.")
    translated["value"] <- list(brohn_translate_participant_answer(context$projection$private_map$questions,
      step$public_step$question_key, p$value, "to_source"))
  } else if (p$kind == "acknowledge") {
    brohn_require(identical(s$type, "question") && identical(s$question$type, "information"), "Only information accepts acknowledgement.")
  } else if (p$kind == "seal") {
    brohn_require(identical(s$type, "questionnaire_review") && .brohn_ph_sha(p$projection_token) &&
      identical(p$projection_token, projected$latest_occurrence$projection_token), "Review the current complete answers before sealing.")
    translated$projection_hash <- current_packet$latest_occurrence$projection_hash
  }
  list(sequence = event$sequence, id = event$id, type = event$type, step_id = m$source_id,
    stimulus_id = m$stimulus_id, condition_id = m$condition_id, question_id = m$question_id, phase = event$phase,
    clock = event$clock, payload = translated)
}
