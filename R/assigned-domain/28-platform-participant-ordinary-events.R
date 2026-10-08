# Inactive public-event translation. Original replay remains the authority for
# timing, sequence, task completion, equipment and questionnaire transitions.
# These helpers do not authenticate a request or persist received evidence.
.brohn_pve_bool <- function(x) is.logical(x) && length(x) == 1L && !is.na(x)
.brohn_pve_number <- function(x, nullable = FALSE, min = 0, integer = FALSE) {
  (nullable && is.null(x)) || brohn_number(x, min, 1e12, integer)
}
.brohn_pve_measurements <- function(x, fields, nullable = character(), signed = character()) {
  brohn_fields(x, fields, label = "Participant measurement")
  for (name in fields) brohn_require(.brohn_pve_number(x[[name, exact = TRUE]], name %in% nullable,
    if (name %in% signed) -1e12 else 0), "Participant measurements require finite numbers or their declared null.")
  invisible(x)
}
.brohn_pve_envelope <- function(context, event) {
  brohn_assert_participant_view_context(context); .brohn_pvq_plain(event)
  brohn_fields(event, c("sequence", "id", "type", "step_key", "phase", "clock", "payload"), label = "Participant event")
  brohn_require(brohn_number(event$sequence, 1, 10000000, TRUE) && brohn_text(event$id, 128L) &&
    brohn_text(event$type, 40L) && brohn_text(event$phase, 96L), "Use a named ordered participant event.")
  .brohn_revision_clock(event$clock)
  .brohn_pvs_object(event$payload, "Participant event payload")
  step <- if (is.null(event$step_key)) NULL else context$step(event$step_key)
  brohn_require(identical(event$phase, if (is.null(step)) if (event$type == "equipment_event") "equipment_setup" else "session" else step$mapping$phase),
    "Event phase differs from its assigned step.")
  step
}
.brohn_pve_extras <- function(event, fields) {
  brohn_fields(event$payload, c(fields, "clock_segment_id", "time_origin_ms"), label = "Participant event payload")
  brohn_require(identical(event$payload$clock_segment_id, event$clock$instance_id) &&
    identical(event$payload$time_origin_ms, event$clock$time_origin_ms), "Keep the exact explicit page clock on its event.")
  invisible(event$payload)
}
.brohn_pve_source_event <- function(event, step, payload) {
  m <- if (is.null(step)) list(source_id = NULL, stimulus_id = NULL, condition_id = NULL, question_id = NULL) else step$mapping
  list(sequence = event$sequence, id = event$id, type = event$type, step_id = m$source_id,
    stimulus_id = m$stimulus_id, condition_id = m$condition_id, question_id = m$question_id,
    phase = event$phase, clock = event$clock, payload = payload)
}
.brohn_pve_equipment <- function(context, event) {
  p <- event$payload
  brohn_fields(p, c("schema", "policy_token", "kind", "attempt_id", "evidence"), label = "Participant equipment event")
  brohn_require(is.null(event$step_key) && identical(p$schema, "participant-equipment-event/0.1") &&
    brohn_text(p$attempt_id, 96L) && brohn_text(p$kind, 32L) && p$kind %in% c("keyboard", "controls", "camera", "camera_declined"),
    "Use the assigned equipment policy and its setup evidence.")
  policy <- context$policy("equipment", p$policy_token); e <- p$evidence
  if (p$kind == "keyboard") {
    brohn_fields(e, c("codes", "released", "focused", "visible", "last_input_ms"), label = "Keyboard evidence")
    brohn_require(brohn_array(e$codes) && all(vapply(e$codes, brohn_text, logical(1), max = 64L)) &&
      all(vapply(e[c("released", "focused", "visible")], .brohn_pve_bool, logical(1))) &&
      .brohn_pve_number(e$last_input_ms), "Keyboard evidence changed its observed types.")
  } else if (p$kind == "controls") {
    brohn_fields(e, c("activation", "trusted", "last_input_ms"), label = "Control evidence")
    brohn_require(brohn_text(e$activation, 32L) && .brohn_pve_bool(e$trusted) && .brohn_pve_number(e$last_input_ms),
      "Control evidence changed its observed types.")
  } else if (p$kind == "camera_declined") {
    brohn_fields(e, "capture_id", label = "Camera decline evidence")
    brohn_require(brohn_valid_id(e$capture_id), "Keep the observed capture identity.")
  } else {
    brohn_fields(e, c("capture_id", "track_generation", "video", "audio", "recording"), label = "Camera equipment evidence")
    brohn_require(brohn_valid_id(e$capture_id) && .brohn_pve_number(e$track_generation, integer = TRUE), "Invalid camera equipment identity.")
    brohn_fields(e$video, c("live", "enabled", "muted", "frames", "last_frame_ms", "width", "height"), label = "Video evidence")
    brohn_fields(e$audio, c("requested", "live", "enabled", "muted", "state", "blocks", "samples", "last_block_ms", "sample_rate", "channels", "rms", "peak"), label = "Audio evidence")
    brohn_fields(e$recording, c("browser_sequence", "browser_bytes", "acked_sequence", "acked_bytes"), label = "Recording evidence")
    brohn_require(all(vapply(c(e$video[c("live", "enabled", "muted")], e$audio[c("requested", "live", "enabled", "muted")]),
      .brohn_pve_bool, logical(1))) && brohn_text(e$audio$state, 64L), "Media evidence changed its observed flags.")
    for (name in c("frames", "last_frame_ms", "width", "height")) brohn_require(.brohn_pve_number(e$video[[name]], name != "frames"), "Invalid video observation type.")
    for (name in c("blocks", "samples", "last_block_ms", "sample_rate", "channels", "rms", "peak"))
      brohn_require(is.null(e$audio[[name]]) && name %in% c("last_block_ms", "sample_rate", "rms", "peak") ||
        brohn_number(e$audio[[name]], 0, if (name == "samples") 1e15 else 1e12), "Invalid audio observation type.")
    brohn_require(all(vapply(e$recording, .brohn_pve_number, logical(1), integer = TRUE)), "Invalid recording byte/sequence types.")
  }
  list(schema = "brohn-participant-equipment-check/1.0", policy_hash = policy$source_hash, kind = p$kind,
    attempt_id = p$attempt_id, evidence = e)
}

brohn_translate_participant_ordinary_event <- function(context, event, sealed_trial_keys = list()) {
  step <- .brohn_pve_envelope(context, event); p <- event$payload; kind <- event$type
  brohn_require(kind %in% c("step_started", "step_finished", "response", "task_event", "equipment_event", "visibility", "withdrawal", "run_finished"),
    "Choose a supported ordinary participant event; questionnaire events use their own transition adapter.")
  if (kind == "equipment_event") return(.brohn_pve_source_event(event, step, .brohn_pve_equipment(context, event)))
  if (kind == "visibility") {
    .brohn_pve_extras(event, c("reason", "hidden", "focused", "viewport"))
    brohn_require(brohn_text(p$reason, 4 * 1024^2, TRUE) && .brohn_pve_bool(p$hidden) && .brohn_pve_bool(p$focused), "Visibility observation changed type.")
    .brohn_pve_measurements(p$viewport, c("width", "height"))
  } else if (kind %in% c("withdrawal", "run_finished")) {
    .brohn_pve_extras(event, c("outcome", "reason"))
    brohn_require(brohn_text(p$outcome, 32L) && p$outcome %in% if (kind == "withdrawal") "withdrawn" else c("completed", "interrupted"), "Ending event has a different outcome.")
    brohn_require(is.null(p$reason) || brohn_text(p$reason, 4 * 1024^2, TRUE), "Keep the observed ending reason or explicit null.")
  } else {
    brohn_require(!is.null(step) && is.null(step$mapping$occurrence_id), "Use the assigned ordinary step, or the questionnaire transition for a reviewable assessment.")
    s <- step$source_step; timed <- s$type %in% c("baseline", "fixation", "stimulus")
    if (kind == "step_started") {
      if (timed) {
        .brohn_pve_extras(event, c("scheduled_duration_ms", "timing_reference", "viewport", "stimulus_rect", "media_current_time", "media_playback_observed_ms"))
        brohn_require(brohn_number(p$scheduled_duration_ms) && p$scheduled_duration_ms == s$duration_ms &&
          identical(p$timing_reference, "requestAnimationFrame_before_paint") && .brohn_pve_number(p$media_current_time, TRUE) &&
          .brohn_pve_number(p$media_playback_observed_ms, TRUE), "Timed start must preserve its schedule and actual media observations.")
        .brohn_pve_measurements(p$viewport, c("width", "height", "device_pixel_ratio"))
        .brohn_pve_measurements(p$stimulus_rect, c("x", "y", "width", "height"), signed = c("x", "y"))
      } else if (s$type == "task") {
        .brohn_pve_extras(event, c("resumed", "task_key")); task <- context$task(event$step_key)
        brohn_require(identical(p$resumed, FALSE) && identical(p$task_key, task$mapping$task_key), "A timed task cannot resume or change task identity.")
        p$task_id <- task$mapping$task_id; p$task_key <- NULL
      } else {
        brohn_require(s$type %in% c("question", "instructions", "maxdiff"), "This step has no ordinary start.")
        .brohn_pve_extras(event, "resumed"); brohn_require(.brohn_pve_bool(p$resumed), "Resume must be an observed flag.")
      }
    } else if (kind == "step_finished") {
      if ("skipped" %in% names(p)) {
        .brohn_pve_extras(event, c("skipped", "reason", "elapsed_ms"))
        brohn_require(identical(s$type, "question") && identical(p$skipped, TRUE) && identical(p$reason, "display_logic") &&
          is.null(p$elapsed_ms), "Only declared question display logic admits a skipped step.")
      } else {
        brohn_require(timed || s$type %in% c("question", "instructions", "maxdiff", "task"), "This step has no ordinary completion.")
        extra <- if (timed) c("scheduled_duration_ms", "observed_duration_ms", "frames", "max_frame_gap_ms") else if (s$type == "task") "task_outcome" else character()
        .brohn_pve_extras(event, c("elapsed_ms", "resumed", extra))
        brohn_require(.brohn_pve_bool(p$resumed) && .brohn_pve_number(p$elapsed_ms, TRUE) &&
          (!p$resumed || is.null(p$elapsed_ms)), "Keep the elapsed observation and resumed timing omission.")
        if (timed) brohn_require(identical(p$resumed, FALSE) && .brohn_pve_number(p$scheduled_duration_ms) &&
          p$scheduled_duration_ms == s$duration_ms && .brohn_pve_number(p$observed_duration_ms) &&
          .brohn_pve_number(p$frames, integer = TRUE) && .brohn_pve_number(p$max_frame_gap_ms), "Timed completion changed its observations.")
        if (s$type == "task") brohn_require(identical(p$resumed, FALSE) && identical(p$task_outcome, "completed"), "Task completion requires its actual completed outcome.")
      }
    } else if (kind == "response") {
      brohn_require(s$type %in% c("question", "maxdiff") && !identical(s$question$type, "information"), "This step does not accept an ordinary answer.")
      .brohn_pve_extras(event, c("value", "response_time_ms", "active_segment_response_ms", "resumed", if (s$type == "question") "scope"))
      brohn_require(.brohn_pve_bool(p$resumed) && .brohn_pve_number(p$response_time_ms, TRUE) &&
        .brohn_pve_number(p$active_segment_response_ms, TRUE) && (!p$resumed || is.null(p$response_time_ms)), "Keep original response timing and resumed omission.")
      if (s$type == "question") {
        brohn_require(identical(p$scope, s$question$scope), "Response scope differs from its assigned question.")
        p["value"] <- list(brohn_translate_participant_answer(context$projection$private_map$questions, step$public_step$question_key, p$value, "to_source"))
        if (s$question$type == "ranking" && !is.null(p$value)) p$option_values <- lapply(p$value, function(id) brohn_find(s$question$options, id)$value)
      } else p["value"] <- list(brohn_translate_participant_choice(context$projection$private_map$choices,
        step$public_step$choice$trial_key, p$value, "to_source", "answer"))
    } else {
      brohn_require(identical(kind, "task_event") && identical(s$type, "task"), "Nested task evidence needs its assigned task.")
      .brohn_pve_extras(event, c("kind", "data")); task <- context$task(event$step_key)
      p$data <- brohn_translate_participant_task_data(task$mapping, p$kind, p$data, "to_source", sealed_trial_keys)
    }
  }
  .brohn_pve_source_event(event, step, p)
}

brohn_apply_participant_view_event <- function(context, state, event, acknowledged_sequence) {
  # The caller owns fresh source replay and the authorized transaction. A prior
  # state is not an authority token. This function only derives and applies one
  # event, retaining the original replay checks instead of duplicating them.
  brohn_assert_participant_view_context(context); .brohn_pvq_plain(state)
  brohn_require(brohn_number(acknowledged_sequence, 0, 10000000, TRUE) &&
    brohn_number(event$sequence, 1, 10000000, TRUE) && event$sequence == acknowledged_sequence + 1L,
    "Apply the next exact event after the acknowledged source sequence.")
  if (identical(event$type, "questionnaire_event")) {
    brohn_require(!is.null(context$revision_context), "This study has no reviewable questionnaire context.")
    packet <- .brohn_delivery_questionnaire_packet(state, context$protocol, context$revision_context,
      offset = 0L, acknowledged_sequence = acknowledged_sequence)
    source <- brohn_translate_participant_questionnaire_event(context, event, packet)
  } else {
    sealed <- list()
    if (identical(event$type, "task_event") && identical(event$payload$kind, "task_interrupted") &&
        "contradiction" %in% names(event$payload$data)) {
      task <- context$task(event$step_key)
      brohn_require(identical(task$mapping$profile, "gnat-brohn-single-target/1.0") &&
        identical(state$active$id, context$step(event$step_key)$mapping$source_id), "Contradiction evidence needs its current outer GNAT state.")
      sealed <- lapply(state$active$task$sealed, function(row) .brohn_pvt_lookup(task$mapping$steps, "source_id", row$trial_id)$key)
    }
    source <- brohn_translate_participant_ordinary_event(context, event, sealed)
  }
  result <- .brohn_delivery_apply(state, source, context$protocol, context$revision_context)
  list(source_event = source, state = result)
}
