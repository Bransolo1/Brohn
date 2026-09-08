# Authenticated browser camera receipt and isolated one-container assembly.
# Callback clocks remain observations, never a calibrated encoded-frame clock.
brohn_validate_camera_policy <- function(policy) {
  brohn_fields(policy, c("schema", "required", "audio", "consent_text", "retention_text", "width", "height", "frame_rate", "max_duration_s", "max_bytes", "analysis_profile"), label = "Camera policy")
  flag <- function(x) is.logical(x) && length(x) == 1L && !is.na(x)
  brohn_require(identical(policy$schema, "brohn-camera-policy/1.0") && flag(policy$required) && flag(policy$audio), "Camera policy needs its registered schema and explicit required/audio choices.")
  brohn_require(brohn_text(policy$consent_text, 12000) && brohn_text(policy$retention_text, 12000), "Camera collection needs separate participant information and retention text.")
  brohn_require(brohn_number(policy$width, 160, 1920, TRUE) && brohn_number(policy$height, 120, 1080, TRUE) && brohn_number(policy$frame_rate, 1, 60),
    "Camera dimensions must be 160-1920 by 120-1080 pixels at 1-60 frames per second.")
  brohn_require(brohn_number(policy$max_duration_s, 1, 600) && brohn_number(policy$max_bytes, 1024, 128*1024^2, TRUE), "Camera collection must be bounded to 600 seconds and 128 MiB or less.")
  brohn_require(is.character(policy$analysis_profile) && length(policy$analysis_profile) == 1L && policy$analysis_profile %in% c("none", "face_geometry_v1"), "Choose no automatic processing or the registered face geometry profile.")
  invisible(policy)
}
.brohn_camera_flag <- function(x) is.logical(x) && length(x) == 1L && !is.na(x)
.brohn_camera_decimal <- function(x, label) {
  .brohn_delivery_require(brohn_text(x, 64) && grepl("^[0-9]+(\\.[0-9]+)?$", x) && is.finite(suppressWarnings(as.numeric(x))) && as.numeric(x) < 1e16,
    paste(label, "must be a finite nonnegative decimal string."))
  as.numeric(x)
}
.brohn_camera_clock <- function(clock) {
  brohn_fields(clock, c("id", "unit", "value", "instance_id", "time_origin_ms"), label = "Camera clock")
  .brohn_delivery_require(identical(clock$id, "browser-monotonic") && identical(clock$unit, "ms") && brohn_text(clock$instance_id, 128), "Camera timing needs one explicit browser clock instance.")
  .brohn_camera_decimal(clock$value, "Camera clock value"); .brohn_camera_decimal(clock$time_origin_ms, "Camera time origin")
  invisible(clock)
}
.brohn_camera_schema <- function(store) {
  .brohn_delivery_schema(store)
  .brohn_store_tx(store, function() {
    sql <- c(
      "CREATE TABLE IF NOT EXISTS camera_captures (id TEXT PRIMARY KEY, run_id TEXT NOT NULL UNIQUE, project_id TEXT NOT NULL, start_json TEXT NOT NULL, start_hash TEXT NOT NULL, status TEXT NOT NULL, acked_sequence INTEGER NOT NULL DEFAULT 0, total_bytes INTEGER NOT NULL DEFAULT 0, last_callback_ms REAL, last_frame_now_ms REAL, frame_callbacks INTEGER NOT NULL DEFAULT 0, final_json TEXT, final_hash TEXT, created_at TEXT NOT NULL, updated_at TEXT NOT NULL, FOREIGN KEY(run_id) REFERENCES delivery_runs(id))",
      "CREATE TABLE IF NOT EXISTS camera_chunks (capture_id TEXT NOT NULL, sequence INTEGER NOT NULL, content_hash TEXT NOT NULL, object_hash TEXT NOT NULL, observation_hash TEXT NOT NULL, byte_count INTEGER NOT NULL, received_at TEXT NOT NULL, PRIMARY KEY(capture_id,sequence), FOREIGN KEY(capture_id) REFERENCES camera_captures(id))",
      "CREATE TRIGGER IF NOT EXISTS camera_start_immutable BEFORE UPDATE OF id,run_id,project_id,start_json,start_hash ON camera_captures BEGIN SELECT RAISE(ABORT,'Camera recording identity is immutable'); END",
      "CREATE TRIGGER IF NOT EXISTS camera_terminal_immutable BEFORE UPDATE ON camera_captures WHEN OLD.status <> 'recording' BEGIN SELECT RAISE(ABORT,'Camera terminal receipts are immutable'); END",
      "CREATE TRIGGER IF NOT EXISTS camera_chunks_no_update BEFORE UPDATE ON camera_chunks BEGIN SELECT RAISE(ABORT,'Camera chunks are immutable'); END",
      "CREATE TRIGGER IF NOT EXISTS camera_chunks_no_delete BEFORE DELETE ON camera_chunks BEGIN SELECT RAISE(ABORT,'Camera chunks are immutable'); END")
    for (statement in sql) DBI::dbExecute(store$con, statement)
  })
}
.brohn_camera_row <- function(store, id = NULL, run_id = NULL) {
  if (!is.null(id)) DBI::dbGetQuery(store$con, "SELECT * FROM camera_captures WHERE id=?", params = list(id)) else
    DBI::dbGetQuery(store$con, "SELECT * FROM camera_captures WHERE run_id=?", params = list(run_id))
}
.brohn_camera_decode <- function(row) {
  if (!nrow(row)) return(NULL)
  list(id = row$id[[1L]], run_id = row$run_id[[1L]], project_id = row$project_id[[1L]], status = row$status[[1L]],
    start = .brohn_store_decode(row$start_json[[1L]], row$start_hash[[1L]]),
    final = if (is.na(row$final_json[[1L]])) NULL else .brohn_store_decode(row$final_json[[1L]], row$final_hash[[1L]]),
    acked_sequence = row$acked_sequence[[1L]], total_bytes = row$total_bytes[[1L]], frame_callbacks = row$frame_callbacks[[1L]],
    created_at = row$created_at[[1L]], updated_at = row$updated_at[[1L]])
}
brohn_capture <- function(store, capture_id = NULL, run_id = NULL) {
  .brohn_camera_schema(store)
  .brohn_delivery_require((!is.null(capture_id) && brohn_valid_id(capture_id)) || (!is.null(run_id) && brohn_valid_id(run_id)), "Choose a camera capture or participant run.")
  .brohn_camera_decode(.brohn_camera_row(store, capture_id, run_id))
}
.brohn_camera_authorize <- function(store, run_id, token) {
  row <- .brohn_delivery_authorize(store, run_id, token); run <- .brohn_delivery_run(row)
  policy <- run$protocol$design$camera
  .brohn_delivery_require(!is.null(policy), "This frozen study has no camera collection policy.", 403, "camera_not_enabled")
  brohn_validate_camera_policy(policy)
  .brohn_delivery_require(!.brohn_store_execution_paused(store), "This restored workspace is paused.", 409, "workspace_paused")
  list(run = run, policy = policy)
}
.brohn_camera_content <- function(request) {request$operation_id <- NULL; .brohn_delivery_hash(.brohn_store_json(request, maximum = 4*1024^2))}
.brohn_camera_owned <- function(store, capture_id, run_id) {
  row <- .brohn_camera_row(store, id = capture_id)
  .brohn_delivery_require(nrow(row) == 1L && identical(row$run_id[[1L]], run_id), "Capture does not belong to this authenticated run.", 403, "foreign_capture")
  row
}

.brohn_camera_start <- function(store, run_id, token, request) {
  brohn_fields(request, c("capture_id", "consented", "clock", "mime_type", "settings", "reason", "operation_id"), label = "Camera start")
  .brohn_delivery_require(brohn_text(request$capture_id, 96) && grepl("^camera-[a-fA-F0-9-]{36}$", request$capture_id) && .brohn_camera_flag(request$consented), "Camera start needs a recorder UUID and an explicit consent choice.")
  .brohn_camera_clock(request$clock)
  .brohn_delivery_require(is.null(request$reason) || brohn_text(request$reason, 4000), "Camera setup reason must be a short description.")
  hash <- .brohn_delivery_hash(.brohn_store_json(request)); .brohn_camera_schema(store)
  brohn_store_batch(store, function() {
    authorized <- .brohn_camera_authorize(store, run_id, token); run <- authorized$run; policy <- authorized$policy
    receipt <- .brohn_delivery_receipt(store, run_id, "camera_start", request$operation_id, hash)
    if (!is.null(receipt)) return(receipt)
    old <- .brohn_camera_row(store, run_id = run_id)
    if (nrow(old)) {
      previous <- .brohn_camera_decode(old)$start$request
      .brohn_delivery_require(identical(old$id[[1L]], request$capture_id) && identical(.brohn_camera_content(previous), .brohn_camera_content(request)),
        "This run already has a different immutable camera start. A new recorder needs a new participant run.", 409, "capture_conflict")
      return(.brohn_delivery_save_receipt(store, run_id, "camera_start", request$operation_id, hash,
        list(capture_id = request$capture_id, status = old$status[[1L]], next_sequence = old$acked_sequence[[1L]]+1L)))
    }
    .brohn_delivery_require(identical(run$completion_status, "in_progress"), "A finalized run cannot start camera recording.", 409, "run_ended")
    status <- if (!request$consented) "declined" else if (is.null(request$mime_type) && is.null(request$settings)) "unavailable" else "recording"
    if (status != "recording") .brohn_delivery_require(is.null(request$mime_type) && is.null(request$settings) && brohn_text(request$reason, 4000), "Declined/unavailable capture must retain its reason and cannot contain recording settings.") else {
      .brohn_delivery_require(brohn_text(request$mime_type, 160) && grepl('^video/webm(?:;\\s*codecs=(?:"?[A-Za-z0-9., -]+"?))?$', request$mime_type, perl = TRUE), "This recorder profile accepts WebM video only.")
      s <- request$settings; brohn_fields(s, c("width", "height", "frame_rate", "audio"), label = "Actual camera settings")
      .brohn_delivery_require(brohn_number(s$width, 1, policy$width, TRUE) && brohn_number(s$height, 1, policy$height, TRUE) &&
        brohn_number(s$frame_rate, .1, policy$frame_rate+.01) && .brohn_camera_flag(s$audio) && identical(s$audio, policy$audio), "Actual camera settings exceed the frozen recording policy or change its audio choice.")
      .brohn_delivery_require(is.null(request$reason), "A recording start cannot also declare a setup failure.")
      events <- .brohn_delivery_events(store, run_id)
      .brohn_delivery_require(!any(vapply(events, function(e) identical(e$type, "step_started"), logical(1))), "Set up camera recording before starting study steps.", 409, "late_camera_start")
    }
    start <- list(schema = "brohn-camera-start/1.0", request = request, policy = policy,
      run_id = run$id, participant_id = run$participant_alias, participant_alias_supplied = run$participant_alias_supplied,
      deployment_id = run$deployment_id, study_id = run$study_id, design = run$protocol$design, design_hash = run$protocol$design_hash,
      protocol_hash = brohn_hash(run$protocol), origin = run$origin, source_timing = "observed_browser_clock_not_encoded_frame_alignment")
    deployment <- brohn_deployment(store, run$deployment_id, FALSE); start$study_revision <- deployment$design_revision
    json <- .brohn_store_json(start); stamp <- brohn_now()
    DBI::dbExecute(store$con, "INSERT INTO camera_captures (id,run_id,project_id,start_json,start_hash,status,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?)",
      params = list(request$capture_id, run_id, run$protocol$design$project_id, json, .brohn_delivery_hash(json), status, stamp, stamp))
    .brohn_store_audit(store, paste0("camera.", status), request$capture_id, list(run_id = run_id, consented = request$consented, origin = run$origin))
    .brohn_delivery_save_receipt(store, run_id, "camera_start", request$operation_id, hash, list(capture_id = request$capture_id, status = status, next_sequence = 1L))
  })
}

.brohn_camera_observation <- function(observation, capture, row, protocol) {
  brohn_fields(observation, c("callback_ms", "event_timecode_ms", "frames", "unretained_frame_callbacks"), label = "Camera chunk observations")
  callback <- .brohn_camera_decimal(observation$callback_ms, "Chunk callback")
  first <- as.numeric(capture$start$request$clock$value)
  .brohn_delivery_require(callback >= first && (is.na(row$last_callback_ms[[1L]]) || callback >= row$last_callback_ms[[1L]]), "Chunk callback clocks must not reverse or precede this recorder.")
  .brohn_delivery_require(is.null(observation$event_timecode_ms) || brohn_number(observation$event_timecode_ms, 0, 1e12), "Recorder event timecode must be finite milliseconds or unavailable.")
  .brohn_delivery_require(brohn_array(observation$frames) && length(observation$frames) <= 500L && brohn_number(observation$unretained_frame_callbacks, 0, 1000000, TRUE), "A chunk may retain at most 500 frame callbacks and an explicit unretained count.")
  frames <- observation$frames; previous <- row$last_frame_now_ms[[1L]]
  for (frame in frames) {
    brohn_fields(frame, c("now_ms", "media_time_s", "presentation_time_ms", "expected_display_time_ms", "capture_time_ms", "presented_frames", "width", "height", "step_id", "phase"), label = "Observed video frame callback")
    .brohn_delivery_require(brohn_number(frame$now_ms, first, callback) && (is.na(previous) || frame$now_ms > previous) && brohn_number(frame$media_time_s, 0, 1e12) &&
      brohn_number(frame$presented_frames, 0, 1e12, TRUE) && brohn_number(frame$width, 1, 1920, TRUE) && brohn_number(frame$height, 1, 1080, TRUE), "Frame callback clocks, counters or dimensions are invalid or repeated.")
    for (key in c("presentation_time_ms", "expected_display_time_ms", "capture_time_ms"))
      .brohn_delivery_require(is.null(frame[[key]]) || brohn_number(frame[[key]], 0, 1e16), "Optional frame clock values must be finite or unavailable.")
    if (is.null(frame$step_id)) .brohn_delivery_require(is.null(frame$phase) || brohn_text(frame$phase, 96), "Frame phase must be a short source label.") else {
      step <- brohn_find(protocol$timeline, frame$step_id)
      .brohn_delivery_require(!is.null(step) && identical(step$phase, frame$phase), "Frame callback refers to a different study step or phase.", 422, "foreign_step")
    }
    previous <- frame$now_ms
  }
  .brohn_delivery_require(row$frame_callbacks[[1L]] + length(frames) <= 60000L, "This capture exceeds 60,000 retained frame callbacks.")
  list(callback_ms = callback, last_frame_now_ms = previous, frame_callbacks = row$frame_callbacks[[1L]]+length(frames))
}

.brohn_camera_chunk <- function(store, run_id, token, request) {
  brohn_fields(request, c("capture_id", "sequence", "data_base64", "sha256", "observation", "operation_id"), label = "Camera chunk")
  .brohn_delivery_require(brohn_valid_id(request$capture_id) && brohn_number(request$sequence, 1, 4096, TRUE) && brohn_text(request$sha256, 64) && grepl("^[a-f0-9]{64}$", request$sha256), "Chunk identity, sequence or SHA-256 is invalid.")
  .brohn_delivery_require(brohn_text(request$data_base64, 4*ceiling(2*1024^2/3)) && nchar(request$data_base64, type = "bytes") %% 4L == 0L &&
    grepl("^[A-Za-z0-9+/]*={0,2}$", request$data_base64), "Chunk bytes require canonical base64 within the 2 MiB raw limit.")
  bytes <- tryCatch(jsonlite::base64_dec(request$data_base64), error = function(e) raw())
  .brohn_delivery_require(length(bytes) > 0L && length(bytes) <= 2*1024^2 && identical(gsub("[\r\n]", "", jsonlite::base64_enc(bytes)), request$data_base64) &&
    identical(digest::digest(bytes, algo = "sha256", serialize = FALSE), request$sha256), "Chunk bytes or declared SHA-256 failed verification.")
  json <- .brohn_store_json(request, maximum = 4*1024^2); hash <- .brohn_delivery_hash(json); content_hash <- .brohn_camera_content(request)
  .brohn_camera_schema(store)
  brohn_store_batch(store, function() {
    authorized <- .brohn_camera_authorize(store, run_id, token)
    receipt <- .brohn_delivery_receipt(store, run_id, "camera_chunk", request$operation_id, hash)
    if (!is.null(receipt)) return(receipt)
    row <- .brohn_camera_owned(store, request$capture_id, run_id); capture <- .brohn_camera_decode(row)
    old <- DBI::dbGetQuery(store$con, "SELECT * FROM camera_chunks WHERE capture_id=? AND sequence=?", params = list(request$capture_id, request$sequence))
    if (nrow(old)) {
      .brohn_delivery_require(identical(old$content_hash[[1L]], content_hash), "An accepted camera chunk was retried with different bytes or observations.", 409, "chunk_conflict")
      return(.brohn_delivery_save_receipt(store, run_id, "camera_chunk", request$operation_id, hash,
        list(capture_id = capture$id, acked_sequence = capture$acked_sequence, total_bytes = capture$total_bytes, status = "saved")))
    }
    .brohn_delivery_require(identical(capture$status, "recording"), "This camera recording already has its final receipt.", 409, "capture_ended")
    .brohn_delivery_require(request$sequence == capture$acked_sequence+1L, "An earlier camera chunk is missing. Retry the next unacknowledged sequence.", 409, "chunk_gap")
    .brohn_delivery_require(capture$total_bytes + length(bytes) <= capture$start$policy$max_bytes, "Measured recording bytes exceed the frozen collection limit.", 413, "capture_byte_limit")
    observed <- .brohn_camera_observation(request$observation, capture, row, authorized$run$protocol)
    object <- brohn_store_object(store, bytes = bytes, media_type = "application/octet-stream")
    metadata <- c(list(schema = "brohn-camera-chunk-observation/1.0", capture_id = capture$id, sequence = request$sequence,
      bytes = length(bytes), sha256 = request$sha256, clock_instance_id = capture$start$request$clock$instance_id,
      time_origin_ms = capture$start$request$clock$time_origin_ms), request$observation)
    evidence <- brohn_store_object(store, bytes = charToRaw(enc2utf8(brohn_json(metadata))), media_type = "application/json")
    DBI::dbExecute(store$con, "INSERT INTO camera_chunks VALUES (?,?,?,?,?,?,?)", params = list(capture$id, request$sequence, content_hash, object$hash, evidence$hash, length(bytes), brohn_now()))
    total <- capture$total_bytes + length(bytes)
    DBI::dbExecute(store$con, "UPDATE camera_captures SET acked_sequence=?,total_bytes=?,last_callback_ms=?,last_frame_now_ms=?,frame_callbacks=?,updated_at=? WHERE id=?",
      params = list(request$sequence, total, observed$callback_ms, observed$last_frame_now_ms, observed$frame_callbacks, brohn_now(), capture$id))
    .brohn_delivery_save_receipt(store, run_id, "camera_chunk", request$operation_id, hash,
      list(capture_id = capture$id, acked_sequence = request$sequence, total_bytes = total, status = "saved"))
  })
}

.brohn_camera_finish <- function(store, run_id, token, request) {
  brohn_fields(request, c("capture_id", "final_sequence", "total_bytes", "outcome", "container_complete", "clock", "reason", "operation_id"), label = "Camera finish")
  .brohn_camera_clock(request$clock)
  .brohn_delivery_require(brohn_valid_id(request$capture_id) && brohn_number(request$final_sequence, 0, 4096, TRUE) && brohn_number(request$total_bytes, 0, 128*1024^2, TRUE) &&
    is.character(request$outcome) && length(request$outcome) == 1L && request$outcome %in% c("completed", "interrupted", "withdrawn") && .brohn_camera_flag(request$container_complete), "Camera final outcome or totals are invalid.")
  .brohn_delivery_require(is.null(request$reason) || brohn_text(request$reason, 4000), "Camera ending reason must be a short description.")
  if (request$outcome == "completed") .brohn_delivery_require(request$container_complete && request$final_sequence > 0 && request$total_bytes > 0 && is.null(request$reason), "Completed capture needs a stopped complete container and nonempty fully received bytes.") else
    .brohn_delivery_require(brohn_text(request$reason, 4000), "Interrupted or withdrawn capture needs its observed reason.")
  hash <- .brohn_delivery_hash(.brohn_store_json(request)); .brohn_camera_schema(store)
  brohn_store_batch(store, function() {
    .brohn_camera_authorize(store, run_id, token)
    receipt <- .brohn_delivery_receipt(store, run_id, "camera_finish", request$operation_id, hash)
    if (!is.null(receipt)) return(receipt)
    row <- .brohn_camera_owned(store, request$capture_id, run_id); capture <- .brohn_camera_decode(row)
    if (!is.null(capture$final)) {
      .brohn_delivery_require(identical(.brohn_camera_content(capture$final), .brohn_camera_content(request)), "This recording already has a different immutable ending.", 409, "capture_outcome_conflict")
      return(.brohn_delivery_save_receipt(store, run_id, "camera_finish", request$operation_id, hash,
        list(capture_id = capture$id, status = "saved", outcome = capture$status, decoding = "separate_processing")))
    }
    .brohn_delivery_require(identical(capture$status, "recording"), "This camera start did not create a recording.", 409, "capture_not_recording")
    .brohn_delivery_require(request$final_sequence == capture$acked_sequence && request$total_bytes == capture$total_bytes, "Final camera totals must match all durable chunk receipts.", 409, "pending_camera_chunks")
    initial <- capture$start$request$clock
    .brohn_delivery_require(identical(request$clock$instance_id, initial$instance_id) && identical(request$clock$time_origin_ms, initial$time_origin_ms), "A new page or recorder cannot finish this camera container.", 409, "camera_clock_conflict")
    final_time <- as.numeric(request$clock$value); start_time <- as.numeric(initial$value)
    unobserved_end <- identical(request$outcome, "interrupted") && !request$container_complete &&
      identical(request$reason, "page_reload_recording_end_unobserved") && identical(brohn_hash(request$clock), brohn_hash(initial))
    .brohn_delivery_require(unobserved_end || final_time >= start_time && (is.na(row$last_callback_ms[[1L]]) || final_time >= row$last_callback_ms[[1L]]), "Camera finish clock precedes recorded callbacks.")
    if (request$outcome == "completed") .brohn_delivery_require(final_time-start_time <= capture$start$policy$max_duration_s*1000 + 1000,
      "Observed recording duration exceeds the frozen limit; retain it as interrupted.", 422, "camera_duration_limit")
    json <- .brohn_store_json(request)
    DBI::dbExecute(store$con, "UPDATE camera_captures SET status=?,final_json=?,final_hash=?,updated_at=? WHERE id=?",
      params = list(request$outcome, json, .brohn_delivery_hash(json), brohn_now(), capture$id))
    if (capture$total_bytes > 0L) brohn_enqueue_capture(store, capture$id)
    .brohn_store_audit(store, paste0("camera.", request$outcome), capture$id, list(run_id = run_id, bytes = capture$total_bytes, chunks = capture$acked_sequence))
    .brohn_delivery_save_receipt(store, run_id, "camera_finish", request$operation_id, hash,
      list(capture_id = capture$id, status = "saved", outcome = request$outcome, decoding = "separate_processing"))
  })
}

brohn_camera_completion <- function(store, run_id) {
  run <- brohn_run(store, run_id); brohn_require(!is.null(run), "Choose an available participant run.")
  policy <- run$protocol$design$camera
  if (is.null(policy)) return(list(eligible = TRUE, required = FALSE, status = "not_requested", reasons = list()))
  brohn_validate_camera_policy(policy); capture <- brohn_capture(store, run_id = run_id)
  if (is.null(capture)) return(list(eligible = FALSE, required = policy$required, status = "missing_camera_decision", reasons = list("Receive the participant's explicit camera decision before finishing.")))
  if (capture$status %in% c("declined", "unavailable")) return(list(eligible = !policy$required, required = policy$required, status = capture$status,
    reasons = if (policy$required) list("This required camera recording was declined or unavailable.") else list(), capture_id = capture$id))
  reasons <- list()
  if (!identical(capture$status, "completed") || !isTRUE(capture$final$container_complete) || capture$total_bytes == 0L) reasons <- c(reasons, "Camera recording is not fully stopped and durably transferred.")
  events <- .brohn_delivery_events(store, run_id)
  steps <- Filter(function(e) e$type %in% c("step_started", "step_finished", "response", "task_event"), events)
  start <- capture$start$request$clock; end <- capture$final$clock
  if (length(steps) && !is.null(end)) {
    clocks <- lapply(steps, `[[`, "clock")
    supported <- all(vapply(clocks, function(c) identical(c$instance_id, start$instance_id) && identical(c$time_origin_ms, start$time_origin_ms) &&
      is.finite(suppressWarnings(as.numeric(c$value))) && as.numeric(c$value) >= as.numeric(start$value) && as.numeric(c$value) <= as.numeric(end$value), logical(1)))
    if (!supported) reasons <- c(reasons, "Observed browser recording bounds do not cover all study steps in the same page clock.")
  }
  list(eligible = !length(reasons), required = policy$required, status = capture$status, reasons = as.list(reasons), capture_id = capture$id,
    timing_evidence = "observed_browser_bounds_only", encoded_frame_alignment = "not_established", decoding = "separate_processing")
}

brohn_enqueue_capture <- function(store, capture_id) {
  capture <- brohn_capture(store, capture_id)
  brohn_require(!is.null(capture$final) && capture$total_bytes > 0L, "Only finalized received camera bytes can be assembled.")
  request <- list(capture_id = capture_id, run_id = capture$run_id, project_id = capture$project_id, capture_hash = brohn_hash(capture),
    recipe = "browser-camera-one-container/1.0")
  brohn_enqueue_job(store, "assemble_capture", request, paste0("camera-assembly:", brohn_hash(request)))
}

brohn_capture_input <- function(store, job) {
  r <- job$request; capture <- brohn_capture(store, r$capture_id)
  brohn_require(!is.null(capture) && identical(brohn_hash(capture), r$capture_hash) && identical(capture$run_id, r$run_id) && identical(capture$project_id, r$project_id), "The pinned camera receipt failed its integrity check.")
  rows <- DBI::dbGetQuery(store$con, "SELECT * FROM camera_chunks WHERE capture_id=? ORDER BY sequence", params = list(capture$id))
  brohn_require(nrow(rows) == capture$acked_sequence && identical(as.numeric(rows$sequence), as.numeric(seq_len(nrow(rows)))) && sum(rows$byte_count) == capture$total_bytes,
    "The finalized capture has missing or inconsistent chunk receipts.")
  chunks <- lapply(seq_len(nrow(rows)), function(i) list(sequence = rows$sequence[[i]], hash = rows$object_hash[[i]], bytes = rows$byte_count[[i]],
    source_path = brohn_object_path(store, rows$object_hash[[i]]), observation_hash = rows$observation_hash[[i]], observation_path = brohn_object_path(store, rows$observation_hash[[i]])))
  list(schema = "brohn-analysis-input/1.0", operation = "assemble_capture", project_id = capture$project_id, capture = capture, chunks = chunks)
}

# Walk container element boundaries, never scan encoded packet bytes for magic.
# A second independently initialized EBML document is not one recorder segment.
.brohn_camera_webm_container <- function(path) {
  con <- file(path, "rb"); on.exit(close(con), add = TRUE); size <- file.info(path)$size; visited <- 0L
  bytes <- function(position, count) {seek(con, where = position, origin = "start"); readBin(con, "raw", n = count)}
  vint <- function(position, id = FALSE) {
    first <- bytes(position, 1L); brohn_require(length(first) == 1L && as.integer(first) > 0L, "WebM element header is truncated or invalid.")
    v <- as.integer(first); length <- 1L; marker <- 128L
    while (bitwAnd(v, marker) == 0L) {length <- length+1L; marker <- marker/2L}
    brohn_require(length <= if (id) 4L else 8L, "WebM variable-length field exceeds its defined size.")
    data <- bytes(position, length); brohn_require(length(data) == length, "WebM element header is truncated.")
    if (id) return(list(value = paste(sprintf("%02x", as.integer(data)), collapse = ""), length = length))
    raw <- as.integer(data); value <- bitwAnd(raw[[1L]], marker-1L)
    unknown <- value == marker-1L && (length == 1L || all(raw[-1L] == 255L))
    if (length > 1L) for (part in raw[-1L]) value <- value*256+part
    brohn_require(unknown || value <= size, "WebM element size exceeds the retained source.")
    list(value = value, length = length, unknown = unknown)
  }
  element <- function(position) {
    visited <<- visited+1L; brohn_require(visited <= 150000L, "WebM element count exceeds the bounded capture profile.")
    id <- vint(position, TRUE); length <- vint(position+id$length); offset <- position+id$length+length$length
    brohn_require(length$unknown || offset+length$value <= size, "WebM source ends inside an element.")
    list(id = id$value, offset = offset, end = if (length$unknown) NA_real_ else offset+length$value, unknown = length$unknown)
  }
  header <- element(0); brohn_require(header$id == "1a45dfa3" && !header$unknown && header$end <= 4096, "A camera source needs one bounded EBML header.")
  cursor <- header$offset; doctype <- NULL
  while (cursor < header$end) {item <- element(cursor); brohn_require(!item$unknown && item$end <= header$end, "WebM header boundary is invalid.")
    if (item$id == "4282") {brohn_require(item$end-item$offset <= 16, "WebM document type is oversized."); doctype <- rawToChar(bytes(item$offset, item$end-item$offset))}; cursor <- item$end}
  brohn_require(identical(doctype, "webm"), "The camera container is not declared WebM.")
  segment <- element(header$end); brohn_require(segment$id == "18538067" && (segment$unknown || segment$end == size), "Multiple or trailing recorder containers cannot be concatenated into one capture.")
  levels <- c("114d9b74", "1549a966", "1654ae6b", "1f43b675", "1c53bb6b", "1941a469", "1043a770", "1254c367")
  cursor <- segment$offset; clusters <- 0L
  while (cursor < size) {
    item <- element(cursor)
    brohn_require(item$id %in% c(levels, "ec", "bf"), "Unexpected top-level WebM data or a second recorder header was found.")
    if (item$id == "1f43b675") clusters <- clusters+1L
    if (!item$unknown) {cursor <- item$end; next}
    brohn_require(item$id == "1f43b675", "Only recorder clusters and their enclosing segment may have unknown length.")
    cursor <- item$offset
    while (cursor < size) {
      child <- element(cursor)
      if (child$id %in% levels) break
      brohn_require(child$id %in% c("e7", "5854", "a7", "ab", "a3", "a0", "af", "ec", "bf") && !child$unknown,
        "An unknown-length cluster contains unsupported boundaries or another recorder document.")
      cursor <- child$end
    }
  }
  brohn_require(clusters > 0L, "This WebM recording contains no media clusters.")
  list(status = "single_webm_container", clusters = clusters, elements_checked = visited, byte_count = size)
}

.brohn_camera_probe <- function(path, directory, policy, settings) {
  executable <- Sys.which("ffprobe")
  brohn_require(nzchar(executable), "Install or configure ffprobe before inspecting assembled camera containers.")
  version <- processx::run(executable, "-version", error_on_status = FALSE, timeout = 10, cleanup_tree = TRUE, windows_hide_window = TRUE)$stdout
  stdout <- file.path(directory, "decoder.json"); stderr <- file.path(directory, "decoder-errors.txt")
  args <- c("-v", "error", "-protocol_whitelist", "file,pipe", "-probesize", "8388608", "-analyzeduration", "5000000", "-f", "matroska",
    "-show_frames", "-show_streams", "-show_entries", "frame=media_type,pts_time,duration_time,width,height:stream=index,codec_type,codec_name,width,height,avg_frame_rate",
    "-of", "json", normalizePath(path, winslash = "/", mustWork = TRUE))
  child <- processx::process$new(executable, args, stdout = stdout, stderr = stderr, windows_hide_window = TRUE, cleanup_tree = TRUE)
  on.exit(if (child$is_alive()) child$kill_tree(), add = TRUE); began <- Sys.time()
  while (child$is_alive()) {
    child$wait(100)
    brohn_require(as.numeric(difftime(Sys.time(), began, units = "secs")) <= 180, "Camera decoder exceeded its 180-second processing limit.")
    brohn_require(file.info(stdout)$size <= 16*1024^2 && file.info(stderr)$size <= 1024^2, "Camera decoder output exceeded its bounds.")
  }
  result <- tryCatch(brohn_read_json_file(stdout, maximum = 16*1024^2), error = function(e) NULL)
  diagnostics <- if (file.info(stderr)$size) paste(readLines(stderr, warn = FALSE), collapse = "\n") else ""
  frames <- brohn_default(result$frames, list()); streams <- brohn_default(result$streams, list())
  brohn_require(length(frames) <= 100000L && length(streams) <= 2L, "Camera decoded frame or stream count exceeds this profile.")
  videos <- Filter(function(s) identical(s$codec_type, "video"), streams); audios <- Filter(function(s) identical(s$codec_type, "audio"), streams)
  video_frames <- Filter(function(f) identical(f$media_type, "video"), frames)
  timestamps <- vapply(video_frames, function(f) suppressWarnings(as.numeric(brohn_default(f$pts_time, NA_character_))), numeric(1))
  timestamp_support <- length(timestamps) > 0L && all(is.finite(timestamps)) && all(diff(timestamps) > 0)
  dimensions <- length(videos) == 1L && identical(as.numeric(videos[[1L]]$width), as.numeric(settings$width)) && identical(as.numeric(videos[[1L]]$height), as.numeric(settings$height)) &&
    all(vapply(video_frames, function(f) identical(as.numeric(f$width), as.numeric(settings$width)) && identical(as.numeric(f$height), as.numeric(settings$height)), logical(1)))
  channels <- length(videos) == 1L && length(audios) == as.integer(policy$audio)
  duration <- if (timestamp_support) max(timestamps)-min(timestamps) else NULL
  within_duration <- !is.null(duration) && duration <= policy$max_duration_s+1
  decoded <- child$get_exit_status() == 0L && !nzchar(diagnostics) && length(video_frames) > 0L
  list(schema = "brohn-camera-decoder/1.0", decoded = decoded, supported = decoded && timestamp_support && dimensions && channels && within_duration,
    video_frames = length(video_frames), audio_frames = sum(vapply(frames, function(f) identical(f$media_type, "audio"), logical(1))),
    streams = streams, timestamp_support = timestamp_support, declared_settings_match = dimensions && channels,
    observed_frame_pts_span_s = duration, first_frame_pts_s = if (timestamp_support) timestamps[[1L]] else NULL,
    last_frame_pts_s = if (timestamp_support) tail(timestamps, 1L) else NULL, within_duration_limit = within_duration,
    decoder = list(name = "ffprobe", version = strsplit(version, "\n", fixed = TRUE)[[1L]][[1L]], executable_sha256 = digest::digest(file = executable, algo = "sha256")),
    diagnostics = substr(diagnostics, 1, 4000), frame_manifest_path = stdout,
    encoded_alignment_to_browser_clock = "not_established", physically_qualified = FALSE)
}

brohn_assemble_capture <- function(input, scratch) {
  capture <- input$capture; brohn_require(identical(input$operation, "assemble_capture") && !is.null(capture$final), "Choose a finalized camera assembly input.")
  brohn_validate_camera_policy(capture$start$policy)
  brohn_require(length(input$chunks) == capture$acked_sequence && capture$total_bytes <= capture$start$policy$max_bytes, "Camera assembly counts exceed their frozen policy.")
  directory <- file.path(scratch, "artifacts"); brohn_require(dir.exists(directory) || dir.create(directory), "Cannot create isolated camera artifact space.")
  destination <- file.path(directory, "recording.webm"); observations <- file.path(directory, "chunk-observations.jsonl")
  con <- file(destination, "wb"); evidence <- file(observations, "wb")
  on.exit(try(close(con), silent = TRUE), add = TRUE); on.exit(try(close(evidence), silent = TRUE), add = TRUE)
  total <- 0; chunk_manifest <- list()
  for (i in seq_along(input$chunks)) {
    chunk <- input$chunks[[i]]
    brohn_require(chunk$sequence == i && file.exists(chunk$source_path) && file.info(chunk$source_path)$size == chunk$bytes &&
      chunk$bytes <= 2*1024^2 && identical(digest::digest(file = chunk$source_path, algo = "sha256"), chunk$hash), "A camera chunk failed its pinned byte/hash check.")
    metadata <- brohn_read_json_file(chunk$observation_path, maximum = 1024^2)
    brohn_require(identical(digest::digest(file = chunk$observation_path, algo = "sha256"), chunk$observation_hash) && identical(metadata$capture_id, capture$id) &&
      metadata$sequence == i && identical(metadata$sha256, chunk$hash) && identical(metadata$clock_instance_id, capture$start$request$clock$instance_id), "Chunk timing evidence belongs to a different recorder or was changed.")
    writeBin(readBin(chunk$source_path, "raw", n = chunk$bytes), con); writeBin(charToRaw(enc2utf8(paste0(brohn_json(metadata), "\n"))), evidence)
    total <- total + chunk$bytes; chunk_manifest[[i]] <- chunk[c("sequence", "hash", "bytes", "observation_hash")]
  }
  close(con); close(evidence); brohn_require(total == capture$total_bytes, "Assembled camera bytes disagree with the final receipt.")
  container <- tryCatch(.brohn_camera_webm_container(destination), error = function(e) list(status = "unsupported_or_partial_container", reason = conditionMessage(e)))
  decoder <- if (container$status == "single_webm_container") tryCatch(.brohn_camera_probe(destination, directory, capture$start$policy, capture$start$request$settings),
    error = function(e) list(decoded = FALSE, supported = FALSE, reason = conditionMessage(e))) else list(decoded = FALSE, supported = FALSE, reason = container$reason)
  artifact <- function(path, kind, type) list(kind = kind, path = normalizePath(path, winslash = "/", mustWork = TRUE), sha256 = digest::digest(file = path, algo = "sha256"),
    bytes = unname(file.info(path)$size), media_type = type)
  artifacts <- list(artifact(destination, "camera-recording", "video/webm"), artifact(observations, "camera-observations", "application/x-ndjson"))
  if (!is.null(decoder$frame_manifest_path)) {artifacts[[length(artifacts)+1L]] <- artifact(decoder$frame_manifest_path, "camera-decoded-frames", "application/json"); decoder$frame_manifest_path <- NULL}
  manifest <- list(schema = "brohn-camera-assembly/1.0", capture_id = capture$id, capture_hash = brohn_hash(capture), run_id = capture$run_id,
    chunks = chunk_manifest, total_bytes = total, frame_callbacks = capture$frame_callbacks,
    origin = capture$start$origin, start = capture$start$request, final = capture$final,
    policy = capture$start$policy,
    study = capture$start[c("study_id", "study_revision", "deployment_id", "design_hash", "protocol_hash")],
    participant = capture$start[c("participant_id", "participant_alias_supplied")],
    recording_end_observed = !identical(capture$final$reason, "page_reload_recording_end_unobserved"),
    container = container, decoder = decoder, complete_transport = TRUE,
    recording_outcome = capture$status, container_complete_declared = capture$final$container_complete,
    limitations = list("Only bytes from one recorder identity are assembled. Individual chunks are not required to decode independently.",
      "Complete transfer and decodability do not establish encoded-frame alignment to stimulus or camera physical accuracy.",
      "Video frame callback timestamps refer to the preview track; no equivalence to encoded recorder frame timing is assumed.",
      "Partial and withdrawn bytes are retained. Neither qualifies for automatic face geometry processing."))
  manifest_path <- file.path(directory, "capture-manifest.json"); brohn_write_json_file(manifest, manifest_path)
  artifacts[[length(artifacts)+1L]] <- artifact(manifest_path, "camera-manifest", "application/json")
  list(title = "Participant camera recording", capture_id = capture$id, capture_hash = brohn_hash(capture), origin = capture$start$origin,
    camera_assembly = manifest, artifacts = artifacts)
}

.brohn_capture_publication_hash <- digest::digest(file="R/platform-capture.R",algo="sha256")
.brohn_publish_capture_legacy <- function(store, output, scratch, job, input, output_path) {
  brohn_store_batch(store, function() {
    brohn_renew_job(store, job$id, job$worker, job$token, 60)
    current <- brohn_capture(store, job$request$capture_id)
    brohn_require(identical(brohn_hash(current), job$request$capture_hash) && identical(brohn_hash(input$capture), job$request$capture_hash) &&
      identical(input$project_id, job$request$project_id) && identical(output$report$capture_hash, job$request$capture_hash), "Camera publication cannot substitute a different recording receipt.")
    report <- output$report; a <- report$camera_assembly
    brohn_require(identical(a$schema, "brohn-camera-assembly/1.0") && identical(a$capture_id, current$id) && identical(a$capture_hash, brohn_hash(current)) &&
      a$total_bytes == current$total_bytes && identical(a$origin, current$start$origin) && identical(a$final, current$final) &&
      identical(brohn_hash(a$policy), brohn_hash(current$start$policy)) &&
      identical(brohn_hash(a$study), brohn_hash(current$start[c("study_id", "study_revision", "deployment_id", "design_hash", "protocol_hash")])) &&
      identical(brohn_hash(a$participant), brohn_hash(current$start[c("participant_id", "participant_alias_supplied")])), "Camera worker output changed its pinned source, policy, study or outcome.")
    items <- report$artifacts
    brohn_require(brohn_array(items) && length(items) %in% c(3L, 4L) && !anyDuplicated(vapply(items, `[[`, character(1), "kind")) &&
      all(vapply(items, function(item) item$kind %in% c("camera-recording", "camera-observations", "camera-decoded-frames", "camera-manifest"), logical(1))), "Camera artifact manifest is incomplete or unsupported.")
    checked <- lapply(items, function(item) {
      expected_type <- if (item$kind == "camera-recording") "video/webm" else if (item$kind == "camera-observations") "application/x-ndjson" else "application/json"
      brohn_require(identical(item$media_type, expected_type), "Camera artifact media type disagrees with its registered kind.")
      path <- brohn_checked_artifact_path(store, item$path, scratch)
      brohn_require(brohn_number(item$bytes, 1, 128*1024^2, TRUE) && file.info(path)$size == item$bytes && identical(digest::digest(file = path, algo = "sha256"), item$sha256), "Camera artifact failed its publication size/hash check.")
      list(path = path, item = item)
    })
    raw_path <- Filter(function(x) identical(x$item$kind, "camera-recording"), checked)[[1L]]$path
    original <- file(raw_path, "rb"); on.exit(try(close(original), silent = TRUE), add = TRUE)
    for (chunk in input$chunks) brohn_require(identical(digest::digest(readBin(original, "raw", n = chunk$bytes), algo = "sha256", serialize = FALSE), chunk$hash),
      "Assembled source bytes do not match the immutable ordered chunks.")
    brohn_require(length(readBin(original, "raw", n = 1L)) == 0L, "Assembled source contains undeclared trailing bytes."); close(original)
    manifest_path <- Filter(function(x) identical(x$item$kind, "camera-manifest"), checked)[[1L]]$path
    brohn_require(identical(brohn_hash(brohn_read_json_file(manifest_path)), brohn_hash(a)), "Camera manifest artifact differs from its publication record.")
    promoted <- lapply(checked, function(x) {
      object <- brohn_store_object(store, path = x$path, media_type = x$item$media_type)
      brohn_require(identical(object$hash, x$item$sha256) && object$size == x$item$bytes, "Camera artifact bytes changed during publication.")
      c(list(kind = x$item$kind, complete = TRUE), object)
    })
    pick <- function(kind) Filter(function(item) identical(item$kind, kind), promoted)[[1L]]
    raw <- pick("camera-recording"); brohn_require(raw$size == current$total_bytes, "The published recording has a different byte count.")
    source <- raw[c("hash", "size", "media_type")]; source$filename <- paste0(current$id, ".webm"); source$format <- "webm"
    dataset_id <- paste0("dataset-", current$id)
    metadata <- list(origin_statement = paste("Browser camera collection for participant run", current$run_id, "; source origin", current$start$origin,
      ". Encoded-frame alignment and physical camera qualification are not established."), profile = "face_geometry_v1")
    eligible_source <- identical(current$status, "completed") && isTRUE(current$final$container_complete) && isTRUE(a$decoder$supported)
    body <- list(schema_version = "brohn-dataset/1.0.0", id = dataset_id, title = paste("Camera recording", current$start$participant_id), modality = "video",
      origin = current$start$origin, study_id = current$start$study_id, study_revision = current$start$study_revision, source = source,
      columns = list(), preview = list(), metadata = metadata, status = if (eligible_source && current$start$policy$analysis_profile == "face_geometry_v1") "accepted" else "needs_mapping",
      data_revision = 1L, notes = "", source_provenance = list(imported_at = brohn_now(), source_hash = raw$hash, acquisition = "browser_camera",
        capture_id = current$id, run_id = current$run_id, participant_id = current$start$participant_id, participant_alias_supplied = current$start$participant_alias_supplied,
        origin = current$start$origin, design_hash = current$start$design_hash, protocol_hash = current$start$protocol_hash,
        recording_outcome = current$status, complete_transport = TRUE, container_complete_declared = current$final$container_complete,
        decoder = a$decoder, timing_alignment = "not_established", physically_qualified = FALSE,
        artifacts = promoted, capture_policy = current$start$policy))
    brohn_put_entity(store, "dataset", dataset_id, body, expected_revision = 0L, project_id = input$project_id)
    entity <- list(schema = "brohn-camera-publication/1.0", id = current$id, capture_id = current$id, run_id = current$run_id,
      dataset_id = dataset_id, source_hash = source$hash, origin = current$start$origin, capture_hash = brohn_hash(current), assembly = a,
      artifacts = promoted, processing = list(job_id = job$id, request_hash = brohn_hash(input), worker_output_hash = digest::digest(file = output_path, algo = "sha256"), code_hashes = output$code_identity))
    brohn_put_entity(store, "camera_capture", current$id, entity, expected_revision = 0L, project_id = input$project_id)
    brohn_renew_job(store, job$id, job$worker, job$token, 60)
    receipt <- brohn_complete_job(store, job$id, job$worker, job$token, list(capture_id = current$id, dataset_id = dataset_id, source_hash = source$hash,
      status = if (eligible_source) "decoded" else "retained_needs_review", decoded = isTRUE(a$decoder$decoded)))
    brohn_queue_capture_analysis(store, current$run_id)
    receipt
  })
}

brohn_publish_capture <- function(store, output, scratch, job, input, output_path) {
  if(.Platform$OS.type!="windows")return(.brohn_publish_capture_legacy(store,output,scratch,job,input,output_path))
  brohn_require(!RSQLite::sqliteIsTransacting(store$con),"Prepare camera publication outside an enclosing transaction.")
  .brohn_publication_output_identity(output,list("R/platform-capture.R"=.brohn_capture_publication_hash))
  .brohn_publication_job(store,job)
  current<-brohn_capture(store,job$request$capture_id)
  validate_pin<-function(observed)brohn_require(identical(brohn_hash(observed),job$request$capture_hash) &&
    identical(brohn_hash(input$capture),job$request$capture_hash) && identical(input$project_id,job$request$project_id) &&
    identical(output$report$capture_hash,job$request$capture_hash),"Camera publication cannot substitute a different recording receipt.")
  validate_pin(current)
  report<-output$report;a<-report$camera_assembly
  brohn_require(identical(a$schema,"brohn-camera-assembly/1.0") && identical(a$capture_id,current$id) && identical(a$capture_hash,brohn_hash(current)) &&
    a$total_bytes==current$total_bytes && identical(a$origin,current$start$origin) && identical(a$final,current$final) &&
    identical(brohn_hash(a$policy),brohn_hash(current$start$policy)) &&
    identical(brohn_hash(a$study),brohn_hash(current$start[c("study_id","study_revision","deployment_id","design_hash","protocol_hash")])) &&
    identical(brohn_hash(a$participant),brohn_hash(current$start[c("participant_id","participant_alias_supplied")])),
    "Camera worker output changed its pinned source, policy, study or outcome.")
  items<-report$artifacts
  brohn_require(brohn_array(items) && length(items)%in%c(3L,4L) && !anyDuplicated(vapply(items,`[[`,character(1),"kind")) &&
    all(vapply(items,function(item)item$kind%in%c("camera-recording","camera-observations","camera-decoded-frames","camera-manifest"),logical(1))) &&
    all(c("camera-recording","camera-observations","camera-manifest")%in%vapply(items,`[[`,character(1),"kind")),"Camera artifact manifest is incomplete or unsupported.")
  specs<-lapply(items,function(item){
    type<-if(item$kind=="camera-recording")"video/webm" else if(item$kind=="camera-observations")"application/x-ndjson" else "application/json"
    brohn_require(identical(item$media_type,type) && brohn_number(item$bytes,1,128*1024^2,TRUE),"Camera artifact type or size is invalid.")
    list(key=item$kind,kind=item$kind,path=brohn_checked_artifact_path(store,item$path,scratch),sha256=item$sha256,bytes=item$bytes,media_type=type)
  })
  artifact_context<-.brohn_publication_stage(store,job,specs);document_context<-NULL;committed<-FALSE
  on.exit({if(!is.null(document_context))brohn_close_publication(document_context$guard,committed);brohn_close_publication(artifact_context$guard,committed)},add=TRUE)
  checkpoint<-.brohn_publication_checkpoint(store,job)
  # Domain checks consume already sealed final bytes. Each bounded chunk read
  # permits cancellation and lease renewal without holding a writer transaction.
  original<-file(artifact_context$paths[["camera-recording"]],"rb");on.exit(try(close(original),silent=TRUE),add=TRUE)
  for(chunk in input$chunks){
    brohn_require(identical(digest::digest(readBin(original,"raw",n=chunk$bytes),algo="sha256",serialize=FALSE),chunk$hash),
      "Assembled source bytes do not match the immutable ordered chunks.")
    checkpoint()
  }
  brohn_require(length(readBin(original,"raw",n=1L))==0L,"Assembled source contains undeclared trailing bytes.");close(original)
  brohn_require(identical(brohn_hash(brohn_read_json_file(artifact_context$paths[["camera-manifest"]])),brohn_hash(a)),"Camera manifest differs from its publication record.")
  promoted<-lapply(artifact_context$descriptors,function(x)c(list(kind=x$kind,complete=TRUE),x[c("hash","size","media_type")]))
  raw<-Filter(function(x)x$kind=="camera-recording",promoted)[[1L]]
  brohn_require(raw$size==current$total_bytes,"The published recording has a different byte count.")
  source<-raw[c("hash","size","media_type")];source$filename<-paste0(current$id,".webm");source$format<-"webm"
  dataset_id<-paste0("dataset-",current$id)
  metadata<-list(origin_statement=paste("Browser camera collection for participant run",current$run_id,"; source origin",current$start$origin,
    ". Encoded-frame alignment and physical camera qualification are not established."),profile="face_geometry_v1")
  eligible_source<-identical(current$status,"completed") && isTRUE(current$final$container_complete) && isTRUE(a$decoder$supported)
  publication<-.brohn_publication_processing(artifact_context)
  dataset<-list(schema_version="brohn-dataset/1.0.0",id=dataset_id,title=paste("Camera recording",current$start$participant_id),modality="video",
    origin=current$start$origin,study_id=current$start$study_id,study_revision=current$start$study_revision,source=source,
    columns=list(),preview=list(),metadata=metadata,status=if(eligible_source && current$start$policy$analysis_profile=="face_geometry_v1")"accepted" else "needs_mapping",
    data_revision=1L,notes="",source_provenance=list(imported_at=brohn_now(),source_hash=raw$hash,acquisition="browser_camera",
      capture_id=current$id,run_id=current$run_id,participant_id=current$start$participant_id,participant_alias_supplied=current$start$participant_alias_supplied,
      origin=current$start$origin,design_hash=current$start$design_hash,protocol_hash=current$start$protocol_hash,
      recording_outcome=current$status,complete_transport=TRUE,container_complete_declared=current$final$container_complete,
      decoder=a$decoder,timing_alignment="not_established",physically_qualified=FALSE,artifacts=promoted,capture_policy=current$start$policy,publication=publication))
  entity<-list(schema="brohn-camera-publication/1.0",id=current$id,capture_id=current$id,run_id=current$run_id,dataset_id=dataset_id,
    source_hash=source$hash,origin=current$start$origin,capture_hash=brohn_hash(current),assembly=a,artifacts=promoted,
    processing=list(job_id=job$id,request_hash=brohn_hash(input),worker_output_hash=digest::digest(file=output_path,algo="sha256"),code_hashes=output$code_identity,publication=publication))
  checkpoint(TRUE)
  document_context<-.brohn_publication_stage_json(store,job,entity,file.path(scratch,"published-camera-capture.json"))
  receipt<-brohn_store_batch(store,function(){
    validate_pin(brohn_capture(store,job$request$capture_id))
    .brohn_publication_register(store,artifact_context)
    result_object<-.brohn_publication_register(store,document_context)[[1L]][c("hash","size","media_type")]
    entity$result_object<-result_object
    brohn_put_entity(store,"dataset",dataset_id,dataset,expected_revision=0L,project_id=input$project_id)
    brohn_put_entity(store,"camera_capture",current$id,entity,expected_revision=0L,project_id=input$project_id)
    receipt<-brohn_complete_job(store,job$id,job$worker,job$token,list(capture_id=current$id,dataset_id=dataset_id,source_hash=source$hash,
      status=if(eligible_source)"decoded" else "retained_needs_review",decoded=isTRUE(a$decoder$decoded)))
    brohn_queue_capture_analysis(store,current$run_id)
    receipt
  })
  committed<-TRUE;receipt
}

brohn_queue_capture_analysis <- function(store, run_id) {
  run <- brohn_run(store, run_id)
  if (is.null(run) || !identical(run$completion_status, "completed") || !identical(run$transfer_status, "saved")) return(invisible(NULL))
  capture <- brohn_capture(store, run_id = run_id)
  if (is.null(capture) || !identical(capture$status, "completed") || !identical(capture$start$policy$analysis_profile, "face_geometry_v1")) return(invisible(NULL))
  publication <- brohn_get_entity(store, "camera_capture", capture$id)
  if (is.null(publication) || !isTRUE(publication$body$assembly$decoder$supported)) return(invisible(NULL))
  brohn_queue_dataset(store, publication$body$dataset_id, revision = 1L)
}

# The backup layer copies every registered object and all SQLite tables/triggers.
# This read-only extra check verifies camera references and JSON hashes too.
brohn_capture_catalog_integrity <- function(con) {
  tables <- DBI::dbListTables(con)
  if (!any(c("camera_captures", "camera_chunks") %in% tables)) return(invisible(TRUE))
  brohn_require(all(c("camera_captures", "camera_chunks", "delivery_runs", "objects") %in% tables), "Camera backup tables are incomplete.")
  captures <- DBI::dbGetQuery(con, "SELECT * FROM camera_captures")
  brohn_require(nrow(captures) <= 100000L, "Camera backup catalog exceeds its capture bound.")
  for (i in seq_len(nrow(captures))) {
    row <- captures[i, , drop = FALSE]; capture <- .brohn_camera_decode(row); start <- capture$start
    brohn_validate_camera_policy(start$policy)
    brohn_require(identical(brohn_hash(start$design), start$design_hash) && identical(brohn_hash(start$policy), brohn_hash(start$design$camera)), "A camera backup changed its frozen design or policy.")
    run <- DBI::dbGetQuery(con, "SELECT protocol_json,protocol_hash FROM delivery_runs WHERE id=?", params = list(capture$run_id))
    brohn_require(nrow(run) == 1L, "A camera backup refers to a missing participant run.")
    protocol <- .brohn_store_decode(run$protocol_json[[1L]], run$protocol_hash[[1L]])
    brohn_require(identical(brohn_hash(protocol), start$protocol_hash) && identical(protocol$design_hash, start$design_hash), "A camera backup refers to a different frozen run protocol.")
    chunks <- DBI::dbGetQuery(con, "SELECT * FROM camera_chunks WHERE capture_id=? ORDER BY sequence", params = list(capture$id))
    brohn_require(nrow(chunks) <= 4096L && nrow(chunks) == capture$acked_sequence && identical(as.numeric(chunks$sequence), as.numeric(seq_len(nrow(chunks)))) &&
      sum(chunks$byte_count) == capture$total_bytes && capture$total_bytes <= start$policy$max_bytes, "A camera backup has inconsistent chunk counts or byte totals.")
    for (j in seq_len(nrow(chunks))) {
      objects <- DBI::dbGetQuery(con, "SELECT hash,size,media_type FROM objects WHERE hash=? OR hash=?", params = list(chunks$object_hash[[j]], chunks$observation_hash[[j]]))
      raw <- objects[objects$hash == chunks$object_hash[[j]], , drop = FALSE]; observation <- objects[objects$hash == chunks$observation_hash[[j]], , drop = FALSE]
      brohn_require(nrow(raw) == 1L && raw$size[[1L]] == chunks$byte_count[[j]] && raw$size[[1L]] > 0L && raw$size[[1L]] <= 2*1024^2 &&
        nrow(observation) == 1L && observation$media_type[[1L]] == "application/json" && grepl("^[a-f0-9]{64}$", chunks$content_hash[[j]]),
        "A camera backup has missing or mismatched chunk objects.")
    }
    if (capture$status %in% c("completed", "interrupted", "withdrawn")) brohn_require(!is.null(capture$final) &&
      capture$final$final_sequence == capture$acked_sequence && capture$final$total_bytes == capture$total_bytes && identical(capture$final$outcome, capture$status), "A camera backup final receipt disagrees with retained bytes.") else
      brohn_require(capture$status %in% c("recording", "declined", "unavailable") && is.null(capture$final), "A camera backup has an invalid receipt state.")
  }
  invisible(TRUE)
}
