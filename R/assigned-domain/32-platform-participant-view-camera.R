# Inactive assigned-camera coordinator; original capture bodies remain unchanged.
.brohn_pvca_request <- function(context, raw, action) {
  received <- brohn_participant_received_bytes(raw)
  value <- received$value
  brohn_fields(value, c("schema", "view_hash", "policy_token", "action", "request"), label = "Assigned camera request")
  .brohn_pvds_require(identical(value$schema, "participant-camera-request/0.1") &&
    identical(value$view_hash, context$view_hash) && identical(value$action, action),
    "Camera request belongs to another presentation or operation.", "camera_binding", 422L)
  policy <- context$protocol$design$camera
  .brohn_pvds_require(!is.null(policy), "This frozen study has no camera collection policy.", "camera_not_enabled", 403L)
  brohn_validate_camera_policy(policy)
  mapping <- context$policy("camera", value$policy_token)
  .brohn_pvds_require(identical(mapping$source_hash, .brohn_ph_hash(policy)),
    "The original camera policy does not match this presentation.", "camera_binding", 422L)
  request <- value$request
  if (identical(action, "start")) {
    brohn_fields(request, c("capture_id", "consented", "clock", "mime_type", "settings", "reason", "operation_id"),
      "analysis_consent", label = "Assigned camera start")
    if (identical(policy$schema, "brohn-camera-policy/1.1")) request$analysis_policy_hash <- policy$analysis_policy_hash
  } else if (identical(action, "chunk")) {
    brohn_fields(request, c("capture_id", "sequence", "data_base64", "sha256", "observation", "operation_id"), label = "Assigned camera chunk")
    brohn_fields(request$observation, c("callback_ms", "event_timecode_ms", "frames", "unretained_frame_callbacks"), label = "Assigned camera observations")
    .brohn_pvds_require(brohn_array(request$observation$frames) && length(request$observation$frames) <= 500L,
      "A camera chunk may contain at most 500 observed frame callbacks.", "camera_frames", 422L)
    request$observation$frames <- lapply(request$observation$frames, function(frame) {
      brohn_fields(frame, c("now_ms", "media_time_s", "presentation_time_ms", "expected_display_time_ms", "capture_time_ms",
        "presented_frames", "width", "height", "step_key", "phase"), label = "Assigned camera frame")
      id <- NULL
      if (!is.null(frame$step_key)) {
        step <- context$step(frame$step_key)
        .brohn_pvds_require(identical(frame$phase, step$source_step$phase),
          "Camera frame refers to another assigned step phase.", "foreign_step", 422L)
        id <- step$source_step$id
      }
      frame$step_key <- NULL
      frame["step_id"] <- list(id)
      frame
    })
  } else {
    brohn_fields(request, c("capture_id", "final_sequence", "total_bytes", "outcome", "container_complete", "clock", "reason", "operation_id"),
      label = "Assigned camera finish")
  }
  list(request = request, policy = policy)
}

.brohn_participant_view_camera_response <- function(store, public_run_id, access_token, action, request_raw) {
  .brohn_pvds_require(is.character(action) && length(action) == 1L && !is.na(action) && action %in% c("start", "chunk", "finish"),
    "Choose a supported camera operation.", "camera_action", 400L)
  handle <- brohn_open_participant_view(store, public_run_id, access_token)
  on.exit(handle$close(), add = TRUE)
  original <- handle$read(); context <- original$context
  input <- .brohn_pvca_request(context, request_raw, action)
  # Keep the original complete run shape, including its real terminal state.
  # This decode is outside the writer and its literal source was fully admitted.
  run <- .brohn_pvds_readonly(store, function() {
    row <- .brohn_pvds_q(store, "SELECT * FROM delivery_runs WHERE id=?", list(original$run$run_id))
    .brohn_pvds_require(nrow(row) == 1L &&
      identical(charToRaw(enc2utf8(row$protocol_json[[1L]])), original$source$raw$protocol),
      "The admitted camera source changed before preparation.", "source_changed")
    value <- .brohn_delivery_run(row)
    .brohn_pvds_require(identical(value$completion_status, original$run$completion_status) &&
      identical(value$acked_sequence, original$run$acked_sequence) &&
      .brohn_ph_equal(value$protocol, context$protocol), "Camera run progress or source changed.", "state_changed")
    value
  })
  body <- switch(action, start = .brohn_camera_start, chunk = .brohn_camera_chunk, finish = .brohn_camera_finish)
  owned_con <- store$con; owned_workspace <- store$workspace_id
  owned_root <- normalizePath(store$root, winslash = "/", mustWork = TRUE)
  scope <- new.env(parent = environment(body))
  scope$.brohn_camera_authorize <- function(actual_store, run_id, token) {
    .brohn_pvds_require(identical(actual_store$con, owned_con) && identical(store$con, owned_con) &&
      identical(actual_store$workspace_id, owned_workspace) && identical(store$workspace_id, owned_workspace) &&
      identical(normalizePath(actual_store$root, winslash = "/", mustWork = TRUE), owned_root) &&
      identical(normalizePath(store$root, winslash = "/", mustWork = TRUE), owned_root) &&
      identical(run_id, original$run$run_id) && identical(token, access_token) && RSQLite::sqliteIsTransacting(owned_con),
      "Camera authorization lost its owned source transaction.", "camera_owner")
    .brohn_pvr_source_cas(store, original)
    list(run = run, policy = input$policy)
  }
  lockEnvironment(scope, bindings = TRUE)
  # Copy-on-modify changes only this operation's lexical authorization lookup.
  # Legacy camera APIs keep their assigned-profile refusal and original parent.
  operation <- body; environment(operation) <- scope
  receipt <- operation(store, original$run$run_id, access_token, input$request)
  fields <- switch(action, start = c("capture_id", "status", "next_sequence"),
    chunk = c("capture_id", "acked_sequence", "total_bytes", "status"),
    finish = c("capture_id", "status", "outcome", "decoding"))
  brohn_fields(receipt, fields, label = "Original camera receipt")
  document <- brohn_participant_json_bytes(list(schema = "participant-camera-result/0.1", binding = .brohn_pvcr_binding(context),
    action = action, operation_id = input$request$operation_id, receipt = receipt), maximum_bytes = 4 * 1024^2)
  handle$current()
  document
}
