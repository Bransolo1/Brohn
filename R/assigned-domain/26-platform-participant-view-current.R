# Inactive current-session reader. No registration, loader or HTTP route.
# Reconstructs original received events; never writes events/device receipts.
.brohn_pvcr_run <- function(store, original) {
  run <- .brohn_pvds_one(.brohn_pvds_q(store, paste(
    "SELECT r.id AS run_id,r.acked_sequence,r.completion_status,r.transfer_status",
    "FROM delivery_runs r JOIN delivery_run_credentials c ON c.run_id=r.id",
    "WHERE r.id=? AND c.token_hash=? AND r.protocol_hash=?"),
    list(original$run$run_id, .brohn_delivery_hash(original$access_token), original$binding$source_protocol_hash)),
    "The participant session changed while its saved responses were loading.", "state_changed")
  .brohn_pvds_require(brohn_number(run$acked_sequence, 0, 10000000, TRUE) &&
    run$completion_status %in% c("in_progress", "completed", "withdrawn", "interrupted") &&
    run$transfer_status %in% c("receiving", "saved"), "Stored session progress is invalid.")
  run
}
.brohn_pvcr_progress <- function(run) run[c("run_id", "acked_sequence", "completion_status", "transfer_status")]
.brohn_pvcr_same_progress <- function(actual, expected) {
  .brohn_pvds_require(.brohn_ph_equal(actual, .brohn_pvcr_progress(expected)),
    "New responses arrived while this session was loading. Reconcile its current saved state.", "state_changed")
  invisible(TRUE)
}
.brohn_pvcr_resolution <- function(store, run_id, project_id) {
  # Existing participant-safe projection remains authoritative. Bound its source
  # body in SQL before the legacy entity reader can hydrate it.
  id <- .brohn_sr_id(run_id)
  read <- function() {
    meta <- .brohn_pvds_q(store, paste(
      "SELECT e.revision,e.project_id,v.project_id AS version_project,v.body_hash,",
      "length(CAST(v.body_json AS BLOB)) AS bytes FROM entities e LEFT JOIN entity_versions v",
      "ON v.kind=e.kind AND v.id=e.id AND v.revision=e.revision",
      "WHERE e.kind='session_resolution' AND e.id=?"), list(id))
    .brohn_pvds_require(nrow(meta) <= 1L, "This session has conflicting researcher resolutions.")
    if (nrow(meta)) {
      .brohn_pvds_size(meta$bytes[[1L]])
      .brohn_pvds_require(meta$revision[[1L]] == 1L && identical(meta$project_id[[1L]], project_id) &&
        identical(meta$version_project[[1L]], project_id) && .brohn_pvds_hash(meta$body_hash[[1L]]),
        "The researcher resolution differs from this original session owner.")
      raw <- .brohn_pvds_one(.brohn_pvds_q(store, paste(
        "SELECT CAST(body_json AS BLOB) AS body FROM entity_versions WHERE kind='session_resolution' AND id=?",
        "AND revision=? AND project_id=? AND body_hash=? AND length(CAST(body_json AS BLOB))=?"),
        list(id, meta$revision[[1L]], project_id, meta$body_hash[[1L]], meta$bytes[[1L]])),
        "The saved researcher resolution changed during reading.")$body
      .brohn_pvds_require(is.raw(raw) && length(raw) == meta$bytes[[1L]] &&
        identical(.brohn_pvds_sha(raw), meta$body_hash[[1L]]), "The researcher resolution failed its original byte hash.")
      literal <- .brohn_pvds_decode(raw)
      .brohn_pvds_require(is.list(literal) && identical(literal$schema, "brohn-session-resolution/1.0") &&
        identical(literal$run_id, run_id), "The saved researcher resolution is inconsistent.")
      # The unchanged legacy projection below uses a decoder with file/URL
      # inference. Admit these exact bytes as a literal object first, inside the
      # same snapshot, so no such string can reach that decoder.
    }
    list(source = meta, projection = brohn_session_resolution_participant(store, run_id))
  }
  # The last authority fence is outside the history snapshot. Its length check
  # and semantic body read must nevertheless share their own read snapshot.
  if (RSQLite::sqliteIsTransacting(store$con)) read() else .brohn_pvds_readonly(store, read)
}
.brohn_pvcr_history <- function(store, run_id, ack, context = NULL) {
  # Called only inside a query-only snapshot. Body reads are one complete row at
  # a time; metadata reads are at most100. There is no aggregate byte/count cap.
  .brohn_pvds_require(RSQLite::sqliteIsTransacting(store$con) &&
    .brohn_pvds_q(store, "PRAGMA query_only")[[1L]][[1L]] == 1L,
    "Saved participant responses require a read-only snapshot.")
  extent <- .brohn_pvds_one(.brohn_pvds_q(store, paste(
    "SELECT count(*) AS n,coalesce(min(sequence),0) AS first,coalesce(max(sequence),0) AS last",
    "FROM delivery_events WHERE run_id=?"), list(run_id)), "The event extent is unavailable.")
  .brohn_pvds_require(extent$n == ack && extent$first == (if (ack == 0) 0 else 1) && extent$last == ack,
    "The acknowledged response journal has missing or extra sequences.", "journal_integrity")
  chain <- .brohn_pvds_sha(charToRaw(paste0("brohn-original-event-prefix/0.1\n", run_id, "\n")))
  state <- if (is.null(context)) NULL else .brohn_delivery_replay(context$protocol, list(), context$revision_context)
  through <- 0L; total_bytes <- 0; peak_body <- 0L; pages <- 0L
  while (through < ack) {
    rows <- .brohn_pvds_q(store, paste(
      "SELECT sequence,typeof(event_json) AS json_type,length(CAST(event_json AS BLOB)) AS bytes,",
      "CASE WHEN length(CAST(event_id AS BLOB)) BETWEEN 1 AND 512 THEN event_id END AS event_id,",
      "CASE WHEN length(CAST(event_hash AS BLOB))=64 THEN event_hash END AS event_hash",
      "FROM delivery_events WHERE run_id=? AND sequence>? AND sequence<=? ORDER BY sequence LIMIT 100"),
      list(run_id, through, ack))
    .brohn_pvds_require(nrow(rows) > 0L, "The saved response journal ended before its acknowledgement.", "journal_integrity")
    pages <- pages + 1L
    for (i in seq_len(nrow(rows))) {
      row <- lapply(rows, function(x) x[[i]])
      .brohn_pvds_require(brohn_number(row$sequence, through + 1, through + 1, TRUE) &&
        identical(row$json_type, "text") && brohn_text(row$event_id, 128L) && .brohn_pvds_hash(row$event_hash),
        "A saved response has an invalid sequence, identity or hash.", "journal_integrity")
      .brohn_pvds_size(row$bytes)
      raw <- .brohn_pvds_one(.brohn_pvds_q(store, paste(
        "SELECT CAST(event_json AS BLOB) AS body FROM delivery_events",
        "WHERE run_id=? AND sequence=? AND event_id=? AND event_hash=?",
        "AND typeof(event_json)='text' AND length(CAST(event_json AS BLOB))=?"),
        list(run_id, row$sequence, row$event_id, row$event_hash, row$bytes)),
        "A saved response changed during reading.", "journal_integrity")$body
      .brohn_pvds_require(is.raw(raw) && length(raw) == row$bytes && identical(.brohn_pvds_sha(raw), row$event_hash),
        "A saved response failed its original byte hash.", "journal_integrity")
      if (!is.null(context)) {
        event <- .brohn_pvds_decode(raw)
        encoded <- brohn_participant_json_bytes(event)
        .brohn_pvds_require(identical(charToRaw(encoded$json), raw) && identical(event$id, row$event_id) &&
          brohn_number(event$sequence, row$sequence, row$sequence, TRUE),
          "Saved response bytes differ from their typed event or row identity.", "journal_integrity")
        state <- .brohn_delivery_apply(state, event, context$protocol, context$revision_context)
      }
      id_utf8 <- enc2utf8(row$event_id)
      chain <- .brohn_pvds_sha(charToRaw(paste0(chain, "\n", sprintf("%.0f", row$sequence), "\n", row$event_hash,
        "\n", nchar(id_utf8, type = "bytes"), ":", id_utf8)))
      through <- as.integer(row$sequence); total_bytes <- total_bytes + length(raw); peak_body <- max(peak_body, length(raw))
    }
  }
  list(state = state, prefix = list(schema = "participant-original-prefix/0.1", run_id = run_id,
    acknowledged_sequence = ack, event_count = through, sha256 = chain, bytes = total_bytes),
    observations = list(metadata_pages = pages, maximum_body_bytes = peak_body))
}
.brohn_pvcr_binding <- function(context) {
  doc <- context$view_document; map <- context$projection$private_map
  list(schema = "participant-view-binding/0.1", run_id = map$public_run_id,
    source_protocol_hash = context$source_protocol_hash, renderer_identity = map$renderer_identity,
    view_codec = doc$codec, view_bytes = doc$bytes, view_hash = doc$sha256)
}
.brohn_pvcr_ending <- function(run, state) {
  pending <- identical(run$completion_status, "in_progress")
  .brohn_pvds_require(identical(run$transfer_status, if (pending) "receiving" else "saved"),
    "Stored session completion and transfer status disagree.", "journal_integrity")
  # The original finish contract permits a received ending before its final
  # receipt, and interrupted/withdrawn finalization without an ending event.
  if (pending) return(invisible(TRUE))
  if (identical(run$completion_status, "completed")) .brohn_pvds_require(
    isTRUE(state$run_finished) && identical(state$ending_outcome, "completed") && !isTRUE(state$withdrawn),
    "A completed session has no complete received ending.", "journal_integrity")
  if (!is.null(state$ending_outcome)) .brohn_pvds_require(identical(run$completion_status, state$ending_outcome),
    "The saved final outcome differs from the received ending.", "journal_integrity")
  if (isTRUE(state$withdrawn)) .brohn_pvds_require(identical(run$completion_status, "withdrawn"),
    "A received withdrawal cannot have another final outcome.", "journal_integrity")
  invisible(TRUE)
}
.brohn_pvcr_session <- function(original, state, resolution) {
  context <- original$context; map <- context$projection$private_map; doc <- context$view_document
  resume <- brohn_project_participant_forward_resume(context,
    .brohn_delivery_resume(state, context$protocol, context$revision_context, original$run$acked_sequence))
  resources <- setNames(lapply(map$resources, function(r) paste0("/api/view/resources/", map$public_run_id, "/", r$key)),
    vapply(map$resources, function(r) r$key, character(1)))
  body <- list(schema = "participant-view-session/0.1", run_id = map$public_run_id, access_token = original$access_token,
    view_json = doc$json, binding = .brohn_pvcr_binding(context), resources = resources,
    expected_sequence = original$run$acked_sequence + 1L, completion_status = original$run$completion_status,
    resume = resume, origin = original$origin, release_status = original$release_status, researcher_resolution = resolution)
  if (!is.null(resume$questionnaire)) {
    # The escaped exact view and outer metadata also consume the HTTP budget.
    # Preserve the literal-null member while measuring its eventual replacement.
    body$resume["questionnaire"] <- list(NULL)
    base <- brohn_participant_json_bytes(body, maximum_bytes = .brohn_pvds_http_limit)
    available <- min(3 * 1024^2, .brohn_pvds_http_limit - base$bytes + 4L)
    .brohn_pvds_require(available >= 1024L,
      "The complete saved session leaves no room for its questionnaire page.", "response_size", 413L)
    body$resume$questionnaire <- .brohn_pvs_fit(resume$questionnaire, available)
  }
  body
}
.brohn_pvcr_request <- function(context, request) {
  .brohn_pvds_require(!is.null(context$revision_context), "This session uses its original forward-only questionnaire.", "legacy_questionnaire")
  brohn_fields(request, c("schema", "offset", "packet_state_token", "view_hash", "source_protocol_hash"), label = "Participant questionnaire page request")
  .brohn_pvds_require(identical(request$schema, "participant-questionnaire-page-request/0.1") &&
    identical(request$view_hash, context$view_hash) && identical(request$source_protocol_hash, context$source_protocol_hash) &&
    brohn_number(request$offset, 0, 20000, TRUE) && (is.null(request$packet_state_token) || .brohn_pvds_hash(request$packet_state_token)) &&
    (request$offset == 0 || !is.null(request$packet_state_token)), "Request a page of this exact saved questionnaire.", "questionnaire_page", 422L)
  invisible(TRUE)
}
.brohn_participant_view_current_response <- function(store, public_run_id, access_token, questionnaire_request = NULL) {
  # Trusted server entry opens its own handle for this actual store. A caller
  # cannot substitute an admitted flag, context, reconstructed state or handle.
  handle <- brohn_open_participant_view(store, public_run_id, access_token)
  on.exit(handle$close(), add = TRUE)
  original <- handle$read(); context <- original$context
  if (!is.null(questionnaire_request)) .brohn_pvcr_request(context, questionnaire_request)
  replay <- .brohn_pvds_readonly(store, function() {
    .brohn_pvcr_same_progress(.brohn_pvcr_run(store, original), original$run)
    resolution <- .brohn_pvcr_resolution(store, original$run$run_id, original$source$metadata$project_id)
    history <- .brohn_pvcr_history(store, original$run$run_id, original$run$acked_sequence, context)
    .brohn_pvcr_ending(original$run, history$state)
    list(history = history, resolution = resolution)
  })
  # Encoding occurs after the read snapshot closes and before final authority.
  value <- if (is.null(questionnaire_request)) .brohn_pvcr_session(original, replay$history$state, replay$resolution$projection) else {
    packet <- .brohn_delivery_questionnaire_packet(replay$history$state, context$protocol, context$revision_context,
      questionnaire_request$offset, original$run$acked_sequence)
    brohn_participant_questionnaire_page_request(context, questionnaire_request, packet)
    brohn_project_participant_questionnaire_packet(context, packet)
  }
  document <- brohn_participant_json_bytes(value, maximum_bytes = .brohn_pvds_http_limit)
  current <- handle$read()
  .brohn_pvcr_same_progress(.brohn_pvcr_progress(current$run), original$run)
  .brohn_pvds_require(identical(current$release_status, original$release_status),
    "Recruitment status changed while this session was loading. Reopen its current state.", "state_changed")
  .brohn_pvds_readonly(store, function() {
    .brohn_pvcr_same_progress(.brohn_pvcr_run(store, current), original$run)
    .brohn_pvds_require(identical(.brohn_pvcr_resolution(store, current$run$run_id, current$source$metadata$project_id), replay$resolution),
      "The researcher resolved this session while it was loading. Reopen its current state.", "state_changed")
    now <- .brohn_pvcr_history(store, current$run$run_id, current$run$acked_sequence)
    .brohn_pvds_require(identical(now$prefix, replay$history$prefix), "The saved response prefix changed during replay.", "journal_integrity")
  })
  last <- handle$read()
  .brohn_pvcr_same_progress(.brohn_pvcr_progress(last$run), original$run)
  .brohn_pvds_require(identical(last$release_status, original$release_status) &&
    identical(.brohn_pvcr_resolution(store, last$run$run_id, last$source$metadata$project_id), replay$resolution),
    "This session changed while its response was being prepared. Reopen its current state.", "state_changed")
  document
}
