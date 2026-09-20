# Native browser checks are acquisition evidence, never device qualification.
brohn_participant_equipment_policy <- function(controls = FALSE) list(
  schema = "brohn-participant-equipment-policy/1.0", camera = TRUE, keyboard = TRUE,
  controls = controls, freshness_ms = 2000L, first_write_wait_ms = 15000L)

brohn_validate_participant_equipment <- function(p) {
  brohn_fields(p, c("schema", "camera", "keyboard", "controls", "freshness_ms", "first_write_wait_ms"), label = "Participant equipment policy")
  brohn_require(identical(p$schema, "brohn-participant-equipment-policy/1.0") &&
    all(vapply(p[c("camera", "keyboard", "controls")], function(x) is.logical(x) && length(x) == 1L && !is.na(x), logical(1))) &&
    identical(as.numeric(p$freshness_ms), 2000) && identical(as.numeric(p$first_write_wait_ms), 15000),
    "Choose the registered browser equipment checks: 2-second observation freshness and 15-second first-write wait. These are engineering limits, not scientific thresholds.")
  invisible(p)
}

brohn_equipment_requirements <- function(protocol) {
  p <- protocol$design$participant_equipment
  if (is.null(p)) return(NULL)
  brohn_validate_participant_equipment(p)
  tasks <- Filter(function(s) identical(s$type, "task"), protocol$timeline)
  codes <- sort(unique(unlist(lapply(tasks, function(s) unlist(lapply(s$task$timeline, function(t) t$allowed_codes))), use.names = FALSE)))
  list(schema = "brohn-participant-equipment-requirements/1.0", policy_hash = brohn_hash(p),
    freshness_ms = p$freshness_ms, first_write_wait_ms = p$first_write_wait_ms,
    camera = isTRUE(p$camera) && !is.null(protocol$design$camera),
    audio = isTRUE(p$camera) && isTRUE(protocol$design$camera$audio),
    required_codes = if (isTRUE(p$keyboard)) as.list(codes) else list(),
    controls = isTRUE(p$controls) && any(vapply(protocol$timeline, function(s) s$type %in% c("question", "maxdiff") && !identical(s$question$type, "information"), logical(1))))
}

.brohn_equipment_page_clock <- function(clock) brohn_text(clock$instance_id, 128) &&
  brohn_text(clock$time_origin_ms, 64) && grepl("^[0-9]+(\\.[0-9]+)?$", clock$time_origin_ms) &&
  brohn_number(suppressWarnings(as.numeric(clock$time_origin_ms)), 0, 1e16)

.brohn_equipment_apply <- function(state, event, protocol) {
  r <- brohn_equipment_requirements(protocol); x <- event$payload
  .brohn_delivery_require(!is.null(r) && is.null(event$step_id) && identical(event$phase, "equipment_setup"), "Equipment evidence needs its frozen policy and setup phase.")
  .brohn_delivery_require(.brohn_equipment_page_clock(event$clock),
    "Equipment evidence requires its explicit browser page identity and time origin.")
  brohn_fields(x, c("schema", "policy_hash", "kind", "attempt_id", "evidence"), label = "Equipment evidence")
  .brohn_delivery_require(identical(x$schema, "brohn-participant-equipment-check/1.0") && identical(x$policy_hash, r$policy_hash) &&
    brohn_text(x$attempt_id, 96) && x$kind %in% c("keyboard", "controls", "camera", "camera_declined") &&
    nchar(brohn_json(x), type = "bytes") <= 65536L, "Equipment identity, policy or evidence bound is invalid.")
  e <- x$evidence; time <- as.numeric(event$clock$value)
  fresh <- function(last) brohn_number(last, 0, time) && time-last <= r$freshness_ms
  if (x$kind == "keyboard") {
    brohn_fields(e, c("codes", "released", "focused", "visible", "last_input_ms"), label = "Key check")
    .brohn_delivery_require(length(r$required_codes) > 0L && identical(brohn_hash(e$codes), brohn_hash(r$required_codes)) &&
      isTRUE(e$released) && isTRUE(e$focused) && isTRUE(e$visible) && fresh(e$last_input_ms), "Observe and release every required key in this page before continuing.")
  } else if (x$kind == "controls") {
    brohn_fields(e, c("activation", "trusted", "last_input_ms"), label = "Control check")
    .brohn_delivery_require(r$controls && e$activation %in% c("mouse", "pen", "touch", "keyboard_or_assistive") &&
      isTRUE(e$trusted) && fresh(e$last_input_ms), "Activate the native practice control before continuing.")
  } else if (x$kind == "camera_declined") {
    brohn_fields(e, c("capture_id"), label = "Camera decline check")
    .brohn_delivery_require(r$camera && !isTRUE(protocol$design$camera$required) && brohn_valid_id(e$capture_id), "Only an optional camera can be explicitly declined.")
  } else {
    brohn_fields(e, c("capture_id", "track_generation", "video", "audio", "recording"), label = "Camera check")
    v <- e$video; a <- e$audio; w <- e$recording
    brohn_fields(v, c("live", "enabled", "muted", "frames", "last_frame_ms", "width", "height"), label = "Video observations")
    brohn_fields(a, c("requested", "live", "enabled", "muted", "state", "blocks", "samples", "last_block_ms", "sample_rate", "channels", "rms", "peak"), label = "Audio observations")
    brohn_fields(w, c("browser_sequence", "browser_bytes", "acked_sequence", "acked_bytes"), label = "Recording writes")
    .brohn_delivery_require(r$camera && brohn_valid_id(e$capture_id) && brohn_number(e$track_generation, 1, 1e9, TRUE) &&
      isTRUE(v$live) && isTRUE(v$enabled) && identical(v$muted, FALSE) && brohn_number(v$frames, 2, 1e12, TRUE) && fresh(v$last_frame_ms) &&
      brohn_number(v$width, 1, protocol$design$camera$width, TRUE) && brohn_number(v$height, 1, protocol$design$camera$height, TRUE), "Current camera frames have not met the named transport check.")
    .brohn_delivery_require(identical(a$requested, r$audio), "Microphone observations changed the requested audio choice.")
    if (r$audio) .brohn_delivery_require(isTRUE(a$live) && isTRUE(a$enabled) && identical(a$muted, FALSE) && identical(a$state, "running") &&
      brohn_number(a$blocks, 1, 1e12, TRUE) && brohn_number(a$samples, 1, 1e15, TRUE) && fresh(a$last_block_ms) &&
      brohn_number(a$sample_rate, 1, 1e6) && brohn_number(a$channels, 1, 32, TRUE) && brohn_number(a$rms, 0) && brohn_number(a$peak, a$rms),
      "Requested microphone input support is unavailable or stale; speech quality remains unknown.")
    .brohn_delivery_require(brohn_number(w$browser_sequence, 1, 4096, TRUE) && brohn_number(w$browser_bytes, 1, 128*1024^2, TRUE) &&
      brohn_number(w$acked_sequence, 1, w$browser_sequence, TRUE) && brohn_number(w$acked_bytes, 1, w$browser_bytes, TRUE), "Wait for committed browser bytes and the recording receipt.")
  }
  if (is.null(state$equipment)) state$equipment <- list()
  key <- if (x$kind == "camera_declined") "camera" else x$kind
  state$equipment[[key]] <- list(instance = event$clock$instance_id, time_origin_ms = event$clock$time_origin_ms,
    attempt_id = x$attempt_id, evidence = e, kind = x$kind, sequence = event$sequence)
  state
}

.brohn_equipment_gate <- function(state, event, protocol) {
  r <- brohn_equipment_requirements(protocol)
  if (is.null(r) || !event$type %in% c("step_started", "questionnaire_event")) return(invisible(TRUE))
  required <- c(if (r$camera) "camera", if (length(r$required_codes)) "keyboard", if (r$controls) "controls")
  if (length(required)) .brohn_delivery_require(.brohn_equipment_page_clock(event$clock),
    "Equipment-gated entry requires the current browser page identity and time origin.")
  for (kind in required) {
    e <- state$equipment[[kind]]
    .brohn_delivery_require(!is.null(e) && identical(e$instance, event$clock$instance_id) && identical(e$time_origin_ms, event$clock$time_origin_ms),
      paste("Complete this page's", kind, "equipment check before entering the study."), 409, "equipment_check_required")
  }
  invisible(TRUE)
}

.brohn_equipment_receive <- function(store, run, event) {
  if (!identical(event$type, "equipment_event") || !event$payload$kind %in% c("camera", "camera_declined")) return(invisible(TRUE))
  e <- event$payload$evidence; capture <- brohn_capture(store, run_id = run$id)
  .brohn_delivery_require(!is.null(capture) && identical(capture$id, e$capture_id), "Camera check belongs to another capture.")
  if (event$payload$kind == "camera_declined") .brohn_delivery_require(identical(capture$status, "declined"), "The optional camera decline has no saved receiver receipt.") else {
    w <- e$recording; initial <- capture$start$request$clock
    .brohn_delivery_require(capture$status %in% c("recording", "completed", "interrupted", "withdrawn") && identical(initial$instance_id, event$clock$instance_id) &&
      identical(initial$time_origin_ms, event$clock$time_origin_ms) && w$acked_sequence <= capture$acked_sequence && w$acked_bytes <= capture$total_bytes &&
      e$video$width == capture$start$request$settings$width && e$video$height == capture$start$request$settings$height,
      "Camera check needs its original page recording and actual receiver byte receipts.")
    observed <- as.numeric(event$clock$value)
    unobserved_end <- identical(capture$final$reason, "page_reload_recording_end_unobserved") && identical(capture$status, "interrupted") &&
      identical(capture$final$container_complete, FALSE) && identical(brohn_hash(capture$final$clock), brohn_hash(initial))
    .brohn_delivery_require(observed >= as.numeric(initial$value) && (is.null(capture$final) || unobserved_end || observed <= as.numeric(capture$final$clock$value)),
      "Historical equipment evidence lies outside the recording's observed browser bounds.")
    exact <- DBI::dbGetQuery(store$con, "SELECT SUM(byte_count) AS bytes,COUNT(*) AS count FROM camera_chunks WHERE capture_id=? AND sequence<=?",
      params = list(capture$id, w$acked_sequence))
    .brohn_delivery_require(nrow(exact) == 1L && exact$count[[1L]] == w$acked_sequence && exact$bytes[[1L]] == w$acked_bytes,
      "Camera check receipt totals do not match the exact committed chunk prefix.")
  }
  invisible(TRUE)
}

brohn_equipment_evidence <- function(store, run_id) {
  run <- brohn_run(store, run_id); brohn_require(!is.null(run), "Choose a saved participant session.")
  list(schema = "brohn-participant-equipment-evidence/1.0", run_id = run_id, protocol_hash = brohn_hash(run$protocol),
    policy = run$protocol$design$participant_equipment, requirements = brohn_equipment_requirements(run$protocol),
    checks = Filter(function(e) identical(e$type, "equipment_event"), .brohn_delivery_events(store, run_id)),
    interpretation = "Observed browser transport/input and durable receipts; physical timing, image, speech and physiological quality unqualified.")
}
