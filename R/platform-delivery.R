# Participant delivery is a separate loopback service. Researcher operations in
# this module are R functions, never unauthenticated HTTP administration routes.
.brohn_delivery_error <- function(message, status = 400L, code = "invalid_request") {
  stop(structure(list(message = message, call = NULL, status = as.integer(status), code = code),
    class = c("brohn_delivery_error", "error", "condition")))
}
.brohn_delivery_require <- function(ok, message, status = 400L, code = "invalid_request") {
  if (!isTRUE(ok)) .brohn_delivery_error(message, status, code)
}
.brohn_delivery_hash <- function(text) digest::digest(charToRaw(enc2utf8(text)), algo = "sha256", serialize = FALSE)
.brohn_delivery_schema <- function(store) {
  .brohn_store_tx(store, function() {
    sql <- c(
      "CREATE TABLE IF NOT EXISTS delivery_deployments (id TEXT PRIMARY KEY, study_id TEXT NOT NULL, project_id TEXT NOT NULL, title TEXT NOT NULL, origin TEXT NOT NULL, status TEXT NOT NULL CHECK(status IN ('open','paused','closed')), quota INTEGER NOT NULL, alias_required INTEGER NOT NULL, design_revision INTEGER NOT NULL, design_json TEXT NOT NULL, design_hash TEXT NOT NULL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL)",
      "CREATE TABLE IF NOT EXISTS delivery_deployment_credentials (deployment_id TEXT PRIMARY KEY, token TEXT NOT NULL, token_hash TEXT NOT NULL UNIQUE, FOREIGN KEY(deployment_id) REFERENCES delivery_deployments(id))",
      "CREATE TABLE IF NOT EXISTS delivery_runs (id TEXT PRIMARY KEY, deployment_id TEXT NOT NULL, study_id TEXT NOT NULL, origin TEXT NOT NULL, participant_alias TEXT NOT NULL, client_id TEXT NOT NULL, start_hash TEXT NOT NULL, protocol_json TEXT NOT NULL, protocol_hash TEXT NOT NULL, allocation_index INTEGER NOT NULL, completion_status TEXT NOT NULL DEFAULT 'in_progress', transfer_status TEXT NOT NULL DEFAULT 'receiving', acked_sequence INTEGER NOT NULL DEFAULT 0, created_at TEXT NOT NULL, updated_at TEXT NOT NULL, finalized_at TEXT, UNIQUE(deployment_id,client_id), UNIQUE(deployment_id,allocation_index), FOREIGN KEY(deployment_id) REFERENCES delivery_deployments(id))",
      "CREATE TABLE IF NOT EXISTS delivery_run_credentials (run_id TEXT PRIMARY KEY, token TEXT NOT NULL, token_hash TEXT NOT NULL UNIQUE, FOREIGN KEY(run_id) REFERENCES delivery_runs(id))",
      "CREATE TABLE IF NOT EXISTS delivery_events (run_id TEXT NOT NULL, sequence INTEGER NOT NULL CHECK(sequence>0), event_id TEXT NOT NULL, event_json TEXT NOT NULL, event_hash TEXT NOT NULL, received_at TEXT NOT NULL, PRIMARY KEY(run_id,sequence), UNIQUE(run_id,event_id), FOREIGN KEY(run_id) REFERENCES delivery_runs(id))",
      "CREATE TABLE IF NOT EXISTS delivery_receipts (scope TEXT NOT NULL, operation TEXT NOT NULL, operation_id TEXT NOT NULL, request_hash TEXT NOT NULL, result_json TEXT NOT NULL, PRIMARY KEY(scope,operation,operation_id))",
      "CREATE INDEX IF NOT EXISTS delivery_runs_study ON delivery_runs(study_id,created_at)",
      "CREATE TRIGGER IF NOT EXISTS delivery_pinned_design BEFORE UPDATE OF study_id,project_id,origin,design_revision,design_json,design_hash ON delivery_deployments BEGIN SELECT RAISE(ABORT,'Released designs are immutable'); END",
      "CREATE TRIGGER IF NOT EXISTS delivery_pinned_run BEFORE UPDATE OF deployment_id,study_id,origin,client_id,protocol_json,protocol_hash,allocation_index ON delivery_runs BEGIN SELECT RAISE(ABORT,'Run protocols are immutable'); END",
      "CREATE TRIGGER IF NOT EXISTS delivery_terminal_run BEFORE UPDATE ON delivery_runs WHEN OLD.completion_status <> 'in_progress' BEGIN SELECT RAISE(ABORT,'Terminal run outcomes are immutable'); END",
      "CREATE TRIGGER IF NOT EXISTS delivery_events_no_update BEFORE UPDATE ON delivery_events BEGIN SELECT RAISE(ABORT,'Received events are immutable'); END",
      "CREATE TRIGGER IF NOT EXISTS delivery_events_no_delete BEFORE DELETE ON delivery_events BEGIN SELECT RAISE(ABORT,'Received events are immutable'); END",
      "CREATE TRIGGER IF NOT EXISTS delivery_receipts_no_update BEFORE UPDATE ON delivery_receipts BEGIN SELECT RAISE(ABORT,'Receipts are immutable'); END",
      "CREATE TRIGGER IF NOT EXISTS delivery_receipts_no_delete BEFORE DELETE ON delivery_receipts BEGIN SELECT RAISE(ABORT,'Receipts are immutable'); END"
    )
    for (statement in sql) DBI::dbExecute(store$con, statement)
    if (!"participant_alias_supplied" %in% DBI::dbListFields(store$con, "delivery_runs"))
      DBI::dbExecute(store$con, "ALTER TABLE delivery_runs ADD COLUMN participant_alias_supplied INTEGER NOT NULL DEFAULT 0")
    DBI::dbExecute(store$con, paste("CREATE TRIGGER IF NOT EXISTS delivery_alias_immutable BEFORE UPDATE OF",
      "participant_alias,participant_alias_supplied ON delivery_runs BEGIN SELECT RAISE(ABORT,'Participant linkage declarations are immutable'); END"))
    invisible(NULL)
  })
}
.brohn_delivery_deployment_row <- function(store, id = NULL, token = NULL) {
  if (!is.null(id)) return(DBI::dbGetQuery(store$con, "SELECT * FROM delivery_deployments WHERE id=?", params = list(id)))
  DBI::dbGetQuery(store$con, paste("SELECT d.* FROM delivery_deployments d JOIN delivery_deployment_credentials c",
    "ON c.deployment_id=d.id WHERE c.token_hash=?"), params = list(.brohn_delivery_hash(token)))
}
.brohn_delivery_deployment <- function(store, row, include_token = FALSE) {
  if (!nrow(row)) return(NULL)
  out <- list(id = row$id[[1]], study_id = row$study_id[[1]], project_id = row$project_id[[1]],
    title = row$title[[1]], origin = row$origin[[1]], status = row$status[[1]], quota = row$quota[[1]],
    alias_required = as.logical(row$alias_required[[1]]), design_revision = row$design_revision[[1]],
    design_hash = row$design_hash[[1]], created_at = row$created_at[[1]], updated_at = row$updated_at[[1]],
    quota_policy = "all_started_sessions_consume_a_place")
  out$started <- DBI::dbGetQuery(store$con, "SELECT count(*) AS n FROM delivery_runs WHERE deployment_id=?",
    params = list(out$id))$n[[1]]
  if (include_token) out$token <- DBI::dbGetQuery(store$con,
    "SELECT token FROM delivery_deployment_credentials WHERE deployment_id=?", params = list(out$id))$token[[1]]
  out
}
brohn_deployment <- function(store, id, include_token = TRUE) {
  .brohn_delivery_schema(store)
  .brohn_delivery_require(brohn_valid_id(id) && is.logical(include_token) && length(include_token) == 1L && !is.na(include_token), "Invalid deployment request.")
  .brohn_delivery_deployment(store, .brohn_delivery_deployment_row(store, id = id), include_token)
}
brohn_deployments <- function(store, study_id = NULL) {
  .brohn_delivery_schema(store)
  if (is.null(study_id)) rows <- DBI::dbGetQuery(store$con, "SELECT * FROM delivery_deployments ORDER BY created_at DESC,id")
  else rows <- DBI::dbGetQuery(store$con, "SELECT * FROM delivery_deployments WHERE study_id=? ORDER BY created_at DESC,id", params = list(study_id))
  lapply(seq_len(nrow(rows)), function(i) .brohn_delivery_deployment(store, rows[i, , drop = FALSE], TRUE))
}
.brohn_delivery_design <- function(row) {
  design <- .brohn_store_decode(row$design_json[[1]])
  .brohn_delivery_require(identical(brohn_hash(design), row$design_hash[[1]]), "Released design integrity check failed.", 500, "integrity")
  design
}
brohn_publish <- function(store, study_id, origin = "pilot", quota = 100, alias_required = FALSE) {
  .brohn_delivery_schema(store)
  .brohn_delivery_require(origin %in% c("pilot", "live", "sample") && length(origin) == 1L, "Choose pilot, live or sample origin.")
  .brohn_delivery_require(brohn_number(quota, 1, 1000000, TRUE) && is.logical(alias_required) &&
    length(alias_required) == 1L && !is.na(alias_required), "Quota or alias policy is invalid.")
  .brohn_store_tx(store, function() {
    .brohn_delivery_require(!.brohn_store_execution_paused(store), "This restored workspace is paused. Resume it explicitly before creating a release.", 409, "workspace_paused")
    entity <- brohn_get_entity(store, "study", study_id)
    .brohn_delivery_require(!is.null(entity), "Study was not found.", 404, "not_found")
    design <- entity$body
    brohn_validate_design(design, publish = TRUE)
    if(brohn_has_illustrations(design))brohn_verify_study_illustrations(store,design)
    .brohn_delivery_require(origin=="sample" || !any(vapply(design$maxdiff,function(exercise) identical(exercise$origin,"synthetic"),logical(1))),
      "Replace the example best-worst materials and declare their research source before pilot or live collection.",422,"sample_materials")
    .brohn_delivery_require(!isTRUE(design$archived), "Restore the study before creating a release.", 409, "archived")
    .brohn_delivery_require(length(design$methods) == 0L, "A method-specific participant compiler must be enabled before releasing this design.", 422, "unsupported_method")
    protocol <- brohn_compile(design, 1L)
    compiled_steps <- sum(vapply(protocol$timeline, function(step) if (identical(step$type, "task")) length(step$task$timeline) else 1L, integer(1)))
    .brohn_delivery_require(compiled_steps <= 20000L, "Compiled study exceeds the supported 20,000-step delivery limit, including task trials.", 422, "study_limit")
    materials <- c(design$stimuli, unlist(lapply(design$blocks, function(block) block$materials), recursive = FALSE))
    if (!is.null(design$welcome$asset)) materials <- c(materials, list(list(type = "image", asset = design$welcome$asset)))
    if(brohn_has_illustrations(design))materials <- c(materials,brohn_study_illustrations(design))
    for (stimulus in materials) {
      .brohn_delivery_require(stimulus$type %in% c("text", "image", "audio", "video"),
        "This local delivery profile supports text, raster images, audio and video stimuli.", 422, "unsupported_stimulus")
      if (!is.null(stimulus$asset)) {
        .brohn_delivery_require(.brohn_delivery_media_allowed(stimulus$asset$media_type),
          "This asset media type cannot be served to participants.", 422, "unsafe_media")
        brohn_object_path(store, stimulus$asset$hash, verify = TRUE)
      }
    }
    id <- brohn_id("release"); token <- brohn_token(); stamp <- brohn_now()
    DBI::dbExecute(store$con, paste("INSERT INTO delivery_deployments",
      "(id,study_id,project_id,title,origin,status,quota,alias_required,design_revision,design_json,design_hash,created_at,updated_at)",
      "VALUES (?,?,?,?,?,'open',?,?,?,?,?,?,?)"), params = list(id, study_id, entity$project_id, design$title,
      origin, as.integer(quota), as.integer(alias_required), entity$revision, .brohn_store_json(design), brohn_hash(design), stamp, stamp))
    DBI::dbExecute(store$con, "INSERT INTO delivery_deployment_credentials VALUES (?,?,?)",
      params = list(id, token, .brohn_delivery_hash(token)))
    .brohn_store_audit(store, "deployment.published", id, list(study_id = study_id, origin = origin, design_revision = entity$revision))
    .brohn_delivery_deployment(store, .brohn_delivery_deployment_row(store, id = id), TRUE)
  })
}
brohn_deployment_state <- function(store, id, state = c("open", "paused", "closed")) {
  .brohn_delivery_schema(store)
  state <- match.arg(state)
  .brohn_store_tx(store, function() {
    row <- .brohn_delivery_deployment_row(store, id = id)
    .brohn_delivery_require(nrow(row) == 1L, "Deployment was not found.", 404, "not_found")
    if (row$status[[1]] == state) return(.brohn_delivery_deployment(store, row, TRUE))
    .brohn_delivery_require(row$status[[1]] != "closed", "A closed release stays closed; publish a new release to collect again.", 409, "closed")
    DBI::dbExecute(store$con, "UPDATE delivery_deployments SET status=?,updated_at=? WHERE id=?", params = list(state, brohn_now(), id))
    .brohn_store_audit(store, paste0("deployment.", state), id)
    .brohn_delivery_deployment(store, .brohn_delivery_deployment_row(store, id = id), TRUE)
  })
}
.brohn_delivery_run <- function(row) {
  if (!nrow(row)) return(NULL)
  protocol <- .brohn_store_decode(row$protocol_json[[1]], row$protocol_hash[[1]])
  list(id = row$id[[1]], run_id = row$id[[1]], study_id = row$study_id[[1]], deployment_id = row$deployment_id[[1]],
    origin = row$origin[[1]], participant_alias = row$participant_alias[[1]],
    participant_alias_supplied = as.logical(row$participant_alias_supplied[[1]]), protocol = protocol,
    allocation_index = row$allocation_index[[1]], completion_status = row$completion_status[[1]],
    transfer_status = row$transfer_status[[1]], acked_sequence = row$acked_sequence[[1]],
    created_at = row$created_at[[1]], updated_at = row$updated_at[[1]],
    finalized_at = if (is.na(row$finalized_at[[1]])) NULL else row$finalized_at[[1]])
}
brohn_run <- function(store, id) {
  .brohn_delivery_schema(store)
  .brohn_delivery_run(DBI::dbGetQuery(store$con, "SELECT * FROM delivery_runs WHERE id=?", params = list(id)))
}
brohn_runs <- function(store, study_id = NULL) {
  .brohn_delivery_schema(store)
  if (is.null(study_id)) rows <- DBI::dbGetQuery(store$con, "SELECT * FROM delivery_runs ORDER BY created_at DESC,id")
  else rows <- DBI::dbGetQuery(store$con, "SELECT * FROM delivery_runs WHERE study_id=? ORDER BY created_at DESC,id", params = list(study_id))
  lapply(seq_len(nrow(rows)), function(i) .brohn_delivery_run(rows[i, , drop = FALSE]))
}
brohn_run_events <- function(store, run_id) {
  .brohn_delivery_schema(store)
  .brohn_delivery_events(store, run_id)
}
.brohn_delivery_events <- function(store, run_id) {
  rows <- DBI::dbGetQuery(store$con, "SELECT * FROM delivery_events WHERE run_id=? ORDER BY sequence", params = list(run_id))
  lapply(seq_len(nrow(rows)), function(i) .brohn_store_decode(rows$event_json[[i]], rows$event_hash[[i]]))
}
.brohn_delivery_receipt <- function(store, scope, operation, operation_id, hash) {
  .brohn_delivery_require(brohn_text(operation_id, 128), "An operation identity is required.")
  row <- DBI::dbGetQuery(store$con, "SELECT * FROM delivery_receipts WHERE scope=? AND operation=? AND operation_id=?",
    params = list(scope, operation, operation_id))
  if (!nrow(row)) return(NULL)
  .brohn_delivery_require(identical(row$request_hash[[1]], hash), "This operation identity was reused with a different request.", 409, "idempotency_conflict")
  .brohn_store_decode(row$result_json[[1]])
}
.brohn_delivery_save_receipt <- function(store, scope, operation, operation_id, hash, result) {
  DBI::dbExecute(store$con, "INSERT INTO delivery_receipts VALUES (?,?,?,?,?)",
    params = list(scope, operation, operation_id, hash, .brohn_store_json(result)))
  result
}
.brohn_delivery_media_allowed <- function(type) type %in% c("image/png", "image/jpeg", "image/webp", "image/gif",
  "audio/wav", "audio/x-wav", "audio/mpeg", "audio/ogg", "audio/webm", "video/mp4", "video/webm", "video/ogg")
.brohn_delivery_protocol_urls <- function(protocol, token) {
  augment <- function(s) {
    if (!is.null(s$asset)) s$asset$url <- paste0("/api/assets/", token, "/", s$asset$hash)
    s
  }
  # Keep protocol.design byte-semantically unchanged so design_hash remains
  # meaningful. Transport URLs belong only on renderer timeline copies.
  protocol$timeline <- lapply(protocol$timeline, function(step) {
    if(identical(step$type,"question")&&!is.null(step$question$illustration))step$question_image_url<-paste0("/api/assets/",token,"/",step$question$illustration$asset$hash)
    if(identical(step$type,"maxdiff")) {
      images<-Filter(function(i)!is.null(i$illustration),step$choice$items)
      if(length(images))step$item_image_urls<-setNames(lapply(images,function(i)paste0("/api/assets/",token,"/",i$illustration$asset$hash)),brohn_ids(images))
    }
    if (!is.null(step[["stimulus", exact = TRUE]])) step$stimulus <- augment(step[["stimulus", exact = TRUE]])
    if (identical(step$type, "task")) step$task$timeline <- lapply(step$task$timeline, function(trial) {
      if (!is.null(trial$material)) trial$material <- augment(trial$material)
      trial
    })
    step
  })
  protocol
}
.brohn_delivery_authorize <- function(store, run_id, token) {
  .brohn_delivery_require(brohn_valid_id(run_id) && brohn_text(token, 128), "Run access is required.", 401, "unauthorized")
  row <- DBI::dbGetQuery(store$con, paste("SELECT r.* FROM delivery_runs r JOIN delivery_run_credentials c ON c.run_id=r.id",
    "WHERE r.id=? AND c.token_hash=?"), params = list(run_id, .brohn_delivery_hash(token)))
  .brohn_delivery_require(nrow(row) == 1L, "Run access was not accepted.", 401, "unauthorized")
  row
}
.brohn_delivery_start_result <- function(store, row, token) {
  run <- .brohn_delivery_run(row)
  events <- .brohn_delivery_events(store, run$id)
  context <- if (!is.null(run$protocol$design$questionnaire_navigation)) .brohn_delivery_revision_context(run$protocol, row$protocol_hash[[1L]]) else NULL
  state <- .brohn_delivery_replay(run$protocol, events, context)
  secret <- DBI::dbGetQuery(store$con, "SELECT token FROM delivery_run_credentials WHERE run_id=?", params = list(run$id))$token[[1]]
  result <- list(run_id = run$id, access_token = secret, protocol = .brohn_delivery_protocol_urls(run$protocol, token),
    expected_sequence = run$acked_sequence + 1L, completion_status = run$completion_status,
    resume = .brohn_delivery_resume(state, run$protocol, context, run$acked_sequence))
  if (!is.null(context)) result$protocol_hash <- context$protocol_hash
  if (exists("brohn_session_resolution_participant", mode = "function")) result$researcher_resolution <- brohn_session_resolution_participant(store, run$id)
  result
}
.brohn_delivery_start <- function(store, token, request) {
  brohn_fields(request, c("consented", "client_id", "operation_id"), "participant_alias", "Start request")
  .brohn_delivery_require(is.logical(request$consented) && length(request$consented) == 1L && !is.na(request$consented),
    "The consent choice must be explicit.", 403, "consent_required")
  .brohn_delivery_require(brohn_text(request$client_id, 128), "A client identity is required.")
  alias <- brohn_default(request$participant_alias, "")
  .brohn_delivery_require(brohn_text(alias, 200, TRUE), "Participant alias must be short text.")
  hash <- .brohn_delivery_hash(.brohn_store_json(request))
  .brohn_store_tx(store, function() {
    .brohn_delivery_require(!.brohn_store_execution_paused(store), "This restored workspace is paused.", 409, "workspace_paused")
    deployment <- .brohn_delivery_deployment_row(store, token = token)
    .brohn_delivery_require(nrow(deployment) == 1L, "Study link was not found.", 404, "not_found")
    id <- deployment$id[[1]]
    design <- .brohn_delivery_design(deployment)
    .brohn_delivery_require(!isTRUE(design$consent$required) || identical(request$consented, TRUE),
      "Consent is required before a session can start.", 403, "consent_required")
    .brohn_delivery_receipt(store, id, "start", request$operation_id, hash)
    old <- DBI::dbGetQuery(store$con, "SELECT * FROM delivery_runs WHERE deployment_id=? AND client_id=?",
      params = list(id, request$client_id))
    start_hash <- .brohn_delivery_hash(.brohn_store_json(list(client_id = request$client_id, consented = request$consented, participant_alias = alias)))
    if (nrow(old)) {
      .brohn_delivery_require(identical(old$start_hash[[1]], start_hash), "This client identity belongs to a different start request.", 409, "client_conflict")
      return(.brohn_delivery_start_result(store, old, token))
    }
    .brohn_delivery_require(deployment$status[[1]] == "open", "This study is not accepting new participants.", 409, deployment$status[[1]])
    .brohn_delivery_require(!as.logical(deployment$alias_required[[1]]) || nzchar(trimws(alias)), "Your researcher requires a participant alias.", 422, "alias_required")
    count <- DBI::dbGetQuery(store$con, "SELECT count(*) AS n FROM delivery_runs WHERE deployment_id=?", params = list(id))$n[[1]]
    .brohn_delivery_require(count < deployment$quota[[1]], "All places in this study have been allocated.", 409, "quota_full")
    protocol <- brohn_compile(design, count + 1L)
    json <- .brohn_store_json(protocol)
    run_id <- brohn_id("run"); secret <- brohn_token(); stamp <- brohn_now()
    alias_supplied <- nzchar(trimws(alias))
    if (!nzchar(trimws(alias))) alias <- paste0("Participant ", count + 1L)
    DBI::dbExecute(store$con, paste("INSERT INTO delivery_runs",
      "(id,deployment_id,study_id,origin,participant_alias,client_id,start_hash,protocol_json,protocol_hash,allocation_index,created_at,updated_at,participant_alias_supplied)",
      "VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)"), params = list(run_id, id, design$id, deployment$origin[[1]], alias,
      request$client_id, start_hash, json, .brohn_delivery_hash(json), count + 1L, stamp, stamp, as.integer(alias_supplied)))
    DBI::dbExecute(store$con, "INSERT INTO delivery_run_credentials VALUES (?,?,?)",
      params = list(run_id, secret, .brohn_delivery_hash(secret)))
    .brohn_store_audit(store, "participant.started", run_id, list(deployment_id = id, allocation_index = count + 1L,
      origin = deployment$origin[[1]], consented = request$consented, consent_required = design$consent$required,
      participant_alias_supplied = alias_supplied))
    row <- DBI::dbGetQuery(store$con, "SELECT * FROM delivery_runs WHERE id=?", params = list(run_id))
    # Receipt contains no access secret. A retry authenticates the client mapping
    # and derives its response from the private credentials table above.
    .brohn_delivery_save_receipt(store, id, "start", request$operation_id, hash, list(run_id = run_id))
    .brohn_delivery_start_result(store, row, token)
  })
}

.brohn_delivery_answer <- function(q, payload) {
  .brohn_delivery_require(is.list(payload) && !is.null(names(payload)), "Question response payload must be an object.")
  .brohn_delivery_require("value" %in% names(payload), "Question responses need an explicit value or null.")
  if (!is.null(payload$scope)) .brohn_delivery_require(identical(payload$scope, q$scope), "Response scope differs from the frozen question.", 422, "invalid_answer")
  if (!is.null(payload$response_time_ms)) .brohn_delivery_require(brohn_number(payload$response_time_ms, 0, 1e12), "Response time must be nonnegative milliseconds or null.", 422, "invalid_answer")
  if (!is.null(payload$active_segment_response_ms)) .brohn_delivery_require(brohn_number(payload$active_segment_response_ms, 0, 1e12), "Active segment response time is invalid.", 422, "invalid_answer")
  if (isTRUE(payload$resumed)) .brohn_delivery_require(is.null(payload$response_time_ms), "A resumed question cannot claim an uninterrupted response time.", 422, "invalid_answer")
  value <- payload$value
  if (is.null(value)) {
    .brohn_delivery_require(!q$required, "A required question has no response.", 422, "required_answer")
    return(NULL)
  }
  same <- function(a, b) identical(.brohn_store_json(a), .brohn_store_json(b))
  option_ids <- brohn_ids(q$options)
  valid_code <- function(v) any(vapply(q$options, function(o) same(o$value, v), logical(1)))
  if (q$type %in% c("rating", "single_choice", "dropdown")) {
    .brohn_delivery_require(valid_code(value), "Response value is not a declared option.", 422, "invalid_answer")
    if (!is.null(payload$option_id)) {
      option <- brohn_find(q$options, payload$option_id)
      .brohn_delivery_require(!is.null(option) && same(value, option$value), "Option identity and typed response value disagree.", 422, "invalid_answer")
    }
  } else if (q$type == "multiple_choice") {
    .brohn_delivery_require(brohn_array(value) && (!q$required || length(value) > 0L) &&
      all(vapply(value, valid_code, logical(1))) && !anyDuplicated(vapply(value, .brohn_store_json, character(1))), "Multiple-choice values are invalid.", 422, "invalid_answer")
    if (!is.null(payload$option_ids)) {
      ids <- payload$option_ids
      .brohn_delivery_require(brohn_array(ids) && length(ids) == length(value) &&
        all(vapply(ids, brohn_text, logical(1), max = 96)) && !anyDuplicated(unlist(ids)), "Selected option identities are invalid.", 422, "invalid_answer")
      for (i in seq_along(ids)) {
        option <- brohn_find(q$options, ids[[i]])
        .brohn_delivery_require(!is.null(option) && same(option$value, value[[i]]), "Selected option and value disagree.", 422, "invalid_answer")
      }
    }
  } else if (q$type %in% c("number", "slider")) {
    .brohn_delivery_require(brohn_number(value, q$min, q$max) && abs((value-q$min)/q$step - round((value-q$min)/q$step)) < 1e-6,
      "Numeric response is outside its range or increment.", 422, "invalid_answer")
  } else if (q$type %in% c("text", "long_text")) {
    .brohn_delivery_require(brohn_text(value, if (q$type == "text") 20000 else 200000, !q$required), "Text response is missing or too long.", 422, "invalid_answer")
  } else if (q$type == "matrix") {
    rows <- brohn_ids(q$rows)
    .brohn_delivery_require(is.list(value) && !is.null(names(value)) && !anyDuplicated(names(value)) &&
      all(names(value) %in% rows) && (!q$required || setequal(names(value), rows)) &&
      all(vapply(value, function(v) (!q$required && is.null(v)) || valid_code(v), logical(1))),
      "Matrix response must use declared rows and typed option values.", 422, "invalid_answer")
  } else if (q$type == "ranking") {
    .brohn_delivery_require(brohn_array(value) && length(value) == length(option_ids) &&
      all(vapply(value, brohn_text, logical(1), max = 96)) && !anyDuplicated(unlist(value)) && setequal(unlist(value), option_ids),
      "Ranking must contain each option identity exactly once.", 422, "invalid_answer")
    if (!is.null(payload$option_values)) .brohn_delivery_require(brohn_array(payload$option_values) &&
      length(payload$option_values) == length(value) && all(vapply(seq_along(value), function(i)
        same(payload$option_values[[i]], brohn_find(q$options, value[[i]])$value), logical(1))),
      "Ranking option values disagree with their ordered identities.", 422, "invalid_answer")
  } else if (q$type == "allocation") {
    .brohn_delivery_require(is.list(value) && !is.null(names(value)) && !anyDuplicated(names(value)) &&
      setequal(names(value), option_ids) && all(vapply(value, brohn_number, logical(1), min = 0, max = q$max)) &&
      abs(sum(unlist(value))-q$max) < 1e-6, "Allocation must explicitly include each option and total the configured maximum.", 422, "invalid_answer")
  } else .brohn_delivery_error("This step does not accept a scored response.", 422, "invalid_answer")
  value
}
.brohn_delivery_initial_state <- function() list(cursor = 1L, active = NULL, completed = list(),
  responses = list(), answers = list(before = structure(list(), names = character()),
    after_each = structure(list(), names = character()), end = structure(list(), names = character())),
  clocks = list(), withdrawn = FALSE, run_finished = FALSE, ending_outcome = NULL)
.brohn_delivery_effective_answers <- function(state, step) {
  scope <- step$question$scope
  scoped <- if (scope == "after_each") state$answers$after_each[[step$stimulus_id]] else if (scope == "end") state$answers$end else list()
  values <- state$answers$before
  for (key in names(scoped)) values[key] <- list(scoped[[key]])
  values
}
.brohn_delivery_advance <- function(state, protocol) {
  while (state$cursor <= length(protocol$timeline)) {
    step <- protocol$timeline[[state$cursor]]
    if (!is.null(step$questionnaire_occurrence_id)) break
    if (step$type != "question" || brohn_rule(step$question$show_if, .brohn_delivery_effective_answers(state, step))) break
    state$cursor <- state$cursor + 1L
  }
  state
}
.brohn_delivery_resume <- function(state, protocol, revision_context = NULL, acknowledged_sequence = 0L) {
  state <- .brohn_delivery_advance(state, protocol)
  result <- list(next_step_id = if (state$cursor <= length(protocol$timeline)) protocol$timeline[[state$cursor]]$id else NULL,
    completed_step_ids = state$completed, answers = state$answers,
    active_step_id = if (is.null(state$active)) NULL else state$active$id,
    active_clock_instance_id = if (is.null(state$active)) NULL else state$active$instance)
  if (!is.null(protocol$design$questionnaire_navigation)) result$questionnaire <-
    .brohn_delivery_questionnaire_packet(state, protocol, revision_context, acknowledged_sequence = acknowledged_sequence)
  result
}
.brohn_delivery_apply <- function(state, event, protocol, revision_context = NULL) {
  brohn_fields(event, c("sequence", "id", "type", "step_id", "stimulus_id", "condition_id", "question_id", "phase", "clock", "payload"), label = "Event")
  .brohn_delivery_require(brohn_number(event$sequence, 1, 10000000, TRUE) && brohn_text(event$id, 128), "Event sequence or identity is invalid.")
  .brohn_delivery_require(event$type %in% c("step_started", "step_finished", "response", "task_event", "questionnaire_event", "equipment_event", "visibility", "run_finished", "withdrawal") && length(event$type) == 1L,
    "Unsupported event type.")
  .brohn_delivery_require(brohn_text(event$phase, 96) && is.list(event$payload) && !is.null(names(event$payload)), "Event phase and payload object are required.")
  brohn_fields(event$clock, c("id", "unit", "value"), c("instance_id", "time_origin_ms"), "Event clock")
  .brohn_delivery_require(identical(event$clock$id, "browser-monotonic") && identical(event$clock$unit, "ms") &&
    brohn_text(event$clock$value, 64) && grepl("^[0-9]+(\\.[0-9]+)?$", event$clock$value), "Observed browser clock must be a decimal millisecond string.")
  time <- suppressWarnings(as.numeric(event$clock$value))
  .brohn_delivery_require(is.finite(time) && time <= 1e12, "Browser elapsed time exceeds the supported range.")
  instance <- brohn_default(event$clock$instance_id, "initial-page")
  .brohn_delivery_require(brohn_text(instance, 128), "Clock instance identity is invalid.")
  if (!is.null(event$clock$time_origin_ms)) .brohn_delivery_require(brohn_text(event$clock$time_origin_ms, 64) &&
    grepl("^[0-9]+(\\.[0-9]+)?$", event$clock$time_origin_ms), "Clock origin must be a decimal string.")
  previous <- state$clocks[[instance]]
  .brohn_delivery_require(is.null(previous) || time >= previous, "Observed clock reversed within one page instance.", 409, "clock_order")
  state$clocks[instance] <- list(time)
  step <- if (is.null(event$step_id)) NULL else brohn_find(protocol$timeline, event$step_id)
  if (!is.null(event$step_id)) .brohn_delivery_require(!is.null(step), "Event refers to a step outside this run.", 422, "foreign_reference")
  if (!is.null(step)) {
    expected_q <- if (step$type == "question") step$question$id else NULL
    .brohn_delivery_require(identical(event$stimulus_id, brohn_default(step$stimulus_id, NULL)) &&
      identical(event$condition_id, brohn_default(step$condition_id, NULL)) && identical(event$question_id, expected_q),
      "Event identities do not match the frozen step.", 422, "foreign_reference")
  } else .brohn_delivery_require(is.null(event$stimulus_id) && is.null(event$condition_id) && is.null(event$question_id),
    "Unscoped events cannot claim stimulus or question identities.", 422, "foreign_reference")
  if (event$type == "visibility") return(state)
  .brohn_delivery_require(!state$withdrawn && !state$run_finished, "The run has already reached its ending event.", 409, "ended")
  if (identical(event$type, "equipment_event")) return(.brohn_equipment_apply(state, event, protocol))
  if (!is.null(protocol$design$participant_equipment)) .brohn_equipment_gate(state, event, protocol)
  if (identical(event$type, "questionnaire_event")) return(.brohn_delivery_revision_apply(state, event, protocol, revision_context))
  if (!is.null(step$questionnaire_occurrence_id) && event$type %in% c("step_started", "step_finished", "response", "task_event"))
    .brohn_delivery_error("Use the current questionnaire visit, answer and review controls for this assessment.", 422, "questionnaire_bypass")
  if (event$type == "step_finished" && isTRUE(event$payload$skipped)) {
    .brohn_delivery_require(!is.null(step) && identical(event$phase, step$phase) && step$type == "question" &&
      is.null(state$active) && state$cursor <= length(protocol$timeline) &&
      identical(step$id, protocol$timeline[[state$cursor]]$id) &&
      identical(event$payload$reason, "display_logic") &&
      !brohn_rule(step$question$show_if, .brohn_delivery_effective_answers(state, step)),
      "Only a question hidden by the frozen display logic can be skipped.", 422, "invalid_skip")
    state$cursor <- state$cursor + 1L
    return(state)
  }
  if (event$type == "withdrawal") { state$withdrawn <- TRUE; state$ending_outcome <- "withdrawn"; return(state) }
  if (event$type == "run_finished") {
    outcome <- brohn_default(event$payload$outcome, "completed")
    .brohn_delivery_require(is.character(outcome) && length(outcome) == 1L && outcome %in% c("completed", "interrupted"), "Ending event outcome is invalid.")
    if (identical(outcome, "completed")) {
      state <- .brohn_delivery_advance(state, protocol)
      .brohn_delivery_require(is.null(state$active) && state$cursor > length(protocol$timeline), "Required study steps have not all finished.", 422, "incomplete_study")
    }
    state$run_finished <- TRUE; state$ending_outcome <- outcome; return(state)
  }
  .brohn_delivery_require(!is.null(step) && identical(event$phase, step$phase), "Step event needs its frozen step and phase.", 422, "foreign_reference")
  if (event$type == "step_started") {
    if (!is.null(state$active) && identical(state$active$id, step$id) && isTRUE(event$payload$resumed) &&
        step$type %in% c("question", "instructions", "maxdiff")) {
      state$active <- list(id = step$id, instance = instance, time = time)
      if (step$type=="maxdiff") state$active$resumed <- TRUE
      return(state)
    }
    state <- .brohn_delivery_advance(state, protocol)
    .brohn_delivery_require(is.null(state$active) && state$cursor <= length(protocol$timeline) &&
      identical(step$id, protocol$timeline[[state$cursor]]$id), "Step order does not match the assigned study.", 409, "step_order")
    state$active <- list(id = step$id, instance = instance, time = time)
    if (identical(step$type, "task")) {
      .brohn_delivery_require(exists(".brohn_task_delivery_new", mode = "function"), "The task receiver is unavailable.", 503, "task_receiver_unavailable")
      state$active$task <- .brohn_task_delivery_new()
    }
    return(state)
  }
  .brohn_delivery_require(!is.null(state$active) && identical(state$active$id, step$id), "This step has not been started.", 409, "step_order")
  if (event$type == "task_event") {
    .brohn_delivery_require(identical(step$type, "task"), "Task evidence must belong to a frozen task step.", 422, "foreign_reference")
    return(.brohn_task_delivery_apply(state, event, step))
  }
  if (event$type == "response") {
    if (step$type=="maxdiff") {
      .brohn_delivery_require(is.null(state$responses[[step$id]]),"This best-worst set already has an acknowledged answer.",409,"duplicate_answer")
      value <- .brohn_maxdiff_delivery_answer(step,event,state)
      state$responses[step$id] <- list(list(value=value)); return(state)
    }
    .brohn_delivery_require(step$type == "question", "Responses must belong to question steps.", 422, "foreign_reference")
    value <- .brohn_delivery_answer(step$question, event$payload)
    state$responses[step$id] <- list(list(value = value))
    scope <- step$question$scope
    if (scope == "after_each") {
      answers <- state$answers$after_each[[step$stimulus_id]]
      if (is.null(answers)) answers <- structure(list(), names = character())
      answers[step$question$id] <- list(value)
      state$answers$after_each[step$stimulus_id] <- list(answers)
    } else state$answers[[scope]][step$question$id] <- list(value)
    return(state)
  }
  if (step$type == "question" && step$question$required && step$question$type != "information")
    .brohn_delivery_require(!is.null(state$responses[[step$id]]), "A required question has not been answered.", 422, "required_answer")
  if (step$type=="maxdiff") .brohn_delivery_require(!is.null(state$responses[[step$id]]),
    "Finish this choice set with a complete answer or an explicit permitted omission.",422,"required_answer")
  if (identical(step$type, "task")) .brohn_task_delivery_complete(state, step, event)
  if (step$type %in% c("baseline", "fixation", "stimulus")) {
    .brohn_delivery_require(identical(instance, state$active$instance),
      "A timed step was interrupted by a page restart. End this run as interrupted and start a fresh session.", 409, "timed_step_interrupted")
    .brohn_delivery_require(time - state$active$time >= step$duration_ms - 1,
      "The observed step duration is shorter than the frozen protocol.", 422, "duration_short")
  }
  state$completed <- c(state$completed, list(step$id)); state$cursor <- state$cursor + 1L; state$active <- NULL
  state
}
.brohn_delivery_replay <- function(protocol, events, revision_context = NULL) {
  state <- .brohn_delivery_initial_state()
  if (!is.null(protocol$design$questionnaire_navigation)) {
    if (is.null(revision_context)) revision_context <- .brohn_delivery_revision_context(protocol)
    state <- .brohn_delivery_revision_initial(state, revision_context)
  }
  for (event in events) state <- .brohn_delivery_apply(state, event, protocol, revision_context)
  state
}
.brohn_delivery_receive <- function(store, run_id, token, request) {
  brohn_fields(request, c("events", "operation_id"), label = "Event batch")
  .brohn_delivery_require(brohn_array(request$events) && length(request$events) >= 1L && length(request$events) <= 1000L,
    "Event batches require 1 to 1,000 events.")
  hash <- .brohn_delivery_hash(.brohn_store_json(request))
  .brohn_store_tx(store, function() {
    .brohn_delivery_require(!.brohn_store_execution_paused(store), "This restored workspace is paused.", 409, "workspace_paused")
    row <- .brohn_delivery_authorize(store, run_id, token)
    receipt <- .brohn_delivery_receipt(store, run_id, "events", request$operation_id, hash)
    if (!is.null(receipt)) {
      result <- list(acked_sequence = row$acked_sequence[[1]])
      run <- .brohn_delivery_run(row)
      if (!is.null(run$protocol$design$questionnaire_navigation)) result$questionnaire <-
        .brohn_delivery_questionnaire_state(store, run_id, token, list(offset = 0L, state_hash = NULL))
      return(result)
    }
    run <- .brohn_delivery_run(row)
    old_events <- .brohn_delivery_events(store, run_id)
    context <- if (!is.null(run$protocol$design$questionnaire_navigation)) .brohn_delivery_revision_context(run$protocol, row$protocol_hash[[1L]]) else NULL
    state <- .brohn_delivery_replay(run$protocol, old_events, context)
    acknowledged <- run$acked_sequence
    previous_sequence <- 0L
    for (event in request$events) {
      .brohn_delivery_require(brohn_number(event$sequence, 1, 10000000, TRUE) && event$sequence > previous_sequence,
        "Batch sequences must increase without duplicates.", 409, "sequence_order")
      previous_sequence <- event$sequence
      json <- .brohn_store_json(event); event_hash <- .brohn_delivery_hash(json)
      old <- DBI::dbGetQuery(store$con, "SELECT event_hash FROM delivery_events WHERE run_id=? AND sequence=?", params = list(run_id, event$sequence))
      if (nrow(old)) {
        .brohn_delivery_require(identical(old$event_hash[[1]], event_hash), "A received sequence was reused with different content.", 409, "sequence_conflict")
        next
      }
      .brohn_delivery_require(run$completion_status == "in_progress", "This run has been finalized.", 409, "finalized")
      if (exists("brohn_require_session_receiving", mode = "function")) brohn_require_session_receiving(store, run_id)
      .brohn_delivery_require(event$sequence == acknowledged + 1L, "An earlier event is missing. Retry from the acknowledged sequence.", 409, "sequence_gap")
      duplicate <- DBI::dbGetQuery(store$con, "SELECT sequence FROM delivery_events WHERE run_id=? AND event_id=?", params = list(run_id, event$id))
      .brohn_delivery_require(nrow(duplicate) == 0L, "Event identity was already used at another sequence.", 409, "event_id_conflict")
      state <- .brohn_delivery_apply(state, event, run$protocol, context)
      if (identical(event$type, "equipment_event")) .brohn_equipment_receive(store, run, event)
      DBI::dbExecute(store$con, "INSERT INTO delivery_events VALUES (?,?,?,?,?,?)",
        params = list(run_id, event$sequence, event$id, json, event_hash, brohn_now()))
      acknowledged <- as.integer(event$sequence)
    }
    if (acknowledged != run$acked_sequence) DBI::dbExecute(store$con,
      "UPDATE delivery_runs SET acked_sequence=?,updated_at=? WHERE id=?", params = list(acknowledged, brohn_now(), run_id))
    result <- .brohn_delivery_save_receipt(store, run_id, "events", request$operation_id, hash, list(acked_sequence = acknowledged))
    if (!is.null(context)) result$questionnaire <- .brohn_delivery_questionnaire_packet(state, run$protocol, context, acknowledged_sequence = acknowledged)
    result
  })
}
.brohn_delivery_finish <- function(store, run_id, token, request) {
  brohn_fields(request, c("outcome", "final_sequence", "operation_id"), label = "Finish request")
  .brohn_delivery_require(request$outcome %in% c("completed", "withdrawn", "interrupted") && length(request$outcome) == 1L &&
    brohn_number(request$final_sequence, 0, 10000000, TRUE), "Completion outcome or final sequence is invalid.")
  hash <- .brohn_delivery_hash(.brohn_store_json(request))
  result <- .brohn_store_tx(store, function() {
    .brohn_delivery_require(!.brohn_store_execution_paused(store), "This restored workspace is paused.", 409, "workspace_paused")
    row <- .brohn_delivery_authorize(store, run_id, token)
    receipt <- .brohn_delivery_receipt(store, run_id, "finish", request$operation_id, hash)
    if (!is.null(receipt)) {
      if (identical(receipt$outcome, "completed")) {
        brohn_enqueue_job(store, "analyse_run", list(run_id = run_id), paste0("analyse-run:", run_id))
        if (exists("brohn_queue_capture_analysis", mode = "function")) brohn_queue_capture_analysis(store, run_id)
      }
      return(receipt)
    }
    run <- .brohn_delivery_run(row)
    .brohn_delivery_require(run$completion_status == "in_progress", "This run already has an immutable final outcome.", 409, "finalized")
    if (exists("brohn_require_session_receiving", mode = "function")) brohn_require_session_receiving(store, run_id)
    .brohn_delivery_require(request$final_sequence == run$acked_sequence, "All final events must have durable receipts before finishing.", 409, "pending_events")
    state <- .brohn_delivery_replay(run$protocol, .brohn_delivery_events(store, run_id))
    if (request$outcome == "completed" && !is.null(run$protocol$design$camera)) {
      .brohn_delivery_require(exists("brohn_camera_completion", mode = "function"), "The camera completion module is unavailable.", 503, "camera_module_unavailable")
      support <- brohn_camera_completion(store, run_id)
      .brohn_delivery_require(isTRUE(support$eligible), paste(unlist(support$reasons), collapse = " "), 409, "camera_incomplete")
    }
    if (request$outcome == "completed") .brohn_delivery_require(state$run_finished && identical(state$ending_outcome, "completed") && !state$withdrawn,
      "The study cannot be completed until all required steps and responses are received.", 422, "incomplete_study")
    if (!is.null(state$ending_outcome)) .brohn_delivery_require(identical(request$outcome, state$ending_outcome),
      "Final outcome must match the received ending event.", 409, "outcome_conflict")
    if (state$withdrawn) .brohn_delivery_require(request$outcome == "withdrawn", "A withdrawn run must retain its withdrawal outcome.", 409, "withdrawn")
    stamp <- brohn_now()
    DBI::dbExecute(store$con, "UPDATE delivery_runs SET completion_status=?,transfer_status='saved',updated_at=?,finalized_at=? WHERE id=?",
      params = list(request$outcome, stamp, stamp, run_id))
    .brohn_store_audit(store, paste0("participant.", request$outcome), run_id, list(final_sequence = request$final_sequence))
    receipt <- .brohn_delivery_save_receipt(store, run_id, "finish", request$operation_id, hash,
      list(status = "saved", outcome = request$outcome))
    # Queue membership and finalization share one transaction. There is no crash
    # gap in which a completed participant is saved without their analysis job.
    if (identical(request$outcome, "completed")) {
      brohn_enqueue_job(store, "analyse_run", list(run_id = run_id), paste0("analyse-run:", run_id))
      if (exists("brohn_queue_capture_analysis", mode = "function")) brohn_queue_capture_analysis(store, run_id)
    }
    receipt
  })
  result
}

.brohn_delivery_response <- function(status = 200L, value = NULL, body = NULL, type = "application/json; charset=utf-8") {
  if (is.null(body)) body <- .brohn_store_json(value)
  list(status = as.integer(status), headers = list("Content-Type" = type, "Cache-Control" = "no-store",
    "X-Content-Type-Options" = "nosniff", "Referrer-Policy" = "no-referrer",
    "Content-Security-Policy" = paste("default-src 'none'; script-src 'self'; style-src 'self' 'unsafe-inline';",
      "img-src 'self' data:; media-src 'self'; connect-src 'self'; font-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'")), body = body)
}
.brohn_delivery_request <- function(req) {
  declared <- suppressWarnings(as.numeric(brohn_default(req$CONTENT_LENGTH, "0")))
  .brohn_delivery_require(is.finite(declared) && declared >= 0 && declared <= 4 * 1024^2, "Request body exceeds 4 MiB.", 413, "request_limit")
  content_type <- tolower(brohn_default(req$CONTENT_TYPE, ""))
  .brohn_delivery_require(grepl("^application/json([;[:space:]]|$)", content_type), "Use application/json for participant requests.", 415, "content_type")
  raw <- req$rook.input$read(4 * 1024^2 + 1L)
  if (is.character(raw)) raw <- charToRaw(paste(raw, collapse = ""))
  .brohn_delivery_require(is.raw(raw) && length(raw) > 0L && length(raw) <= 4 * 1024^2, "Request body is empty or exceeds 4 MiB.", 413, "request_limit")
  text <- rawToChar(raw)
  Encoding(text) <- "UTF-8"
  .brohn_delivery_require(!is.na(iconv(text, from = "UTF-8", to = "UTF-8")), "Request JSON must be UTF-8.")
  value <- jsonlite::fromJSON(text, simplifyVector = FALSE)
  .brohn_store_json(value, maximum = 4 * 1024^2)
  value
}
.brohn_delivery_origin <- function(req) {
  host <- brohn_default(req$HTTP_HOST, paste0("127.0.0.1:", brohn_default(req$SERVER_PORT, "3840")))
  .brohn_delivery_require(grepl("^(127\\.0\\.0\\.1|localhost)(:[0-9]{1,5})?$", host), "This service accepts loopback hosts only.", 403, "host")
  origin <- req$HTTP_ORIGIN
  if (!is.null(origin) && nzchar(origin)) .brohn_delivery_require(identical(origin, paste0("http://", host)),
    "Requests from another browser origin are not accepted.", 403, "origin")
  site <- req$HTTP_SEC_FETCH_SITE
  if (!is.null(site)) .brohn_delivery_require(site %in% c("same-origin", "none"), "Cross-site browser requests are not accepted.", 403, "origin")
}
brohn_delivery_app <- function(store, static_root = "www/participant") {
  .brohn_delivery_schema(store)
  static_root <- normalizePath(static_root, winslash = "/", mustWork = FALSE)
  list(call = function(req) {
    tryCatch({
      .brohn_delivery_origin(req)
      path <- brohn_default(req$PATH_INFO, "/")
      method <- toupper(brohn_default(req$REQUEST_METHOD, "GET"))
      .brohn_delivery_require(method %in% c("GET", "POST"), "HTTP method is not supported.", 405, "method")
      if (method == "GET" && identical(path, "/api/health")) return(.brohn_delivery_response(value =
        list(service = "brohn-participant", schema = "brohn-delivery/1.0", workspace_id = store$workspace_id)))
      routes <- c("/participant" = "index.html", "/participant/" = "index.html", "/participant/runner.js" = "runner.js", "/participant/tasks.js" = "tasks.js", "/participant/camera.js" = "camera.js", "/participant/runner.css" = "runner.css", "/participant/maxdiff.js" = "maxdiff.js", "/participant/maxdiff.css" = "maxdiff.css",
        "/participant/equipment.js" = "equipment.js", "/participant/audio-worklet.js" = "audio-worklet.js",
        "/participant/question-revision.js" = "question-revision.js", "/participant/illustrations.js" = "illustrations.js", "/participant/welcome.js" = "welcome.js", "/participant/welcome.css" = "welcome.css", "/brand/brohn-app-icon.svg" = "../brand/brohn-app-icon.svg")
      if (method == "GET" && path %in% names(routes)) {
        filename <- routes[[path]]; file <- file.path(static_root, filename)
        .brohn_delivery_require(file.exists(file) && !dir.exists(file), "Participant interface is unavailable.", 503, "interface_unavailable")
        type <- if (filename %in% c("runner.js", "tasks.js", "camera.js", "equipment.js", "audio-worklet.js", "maxdiff.js", "question-revision.js", "illustrations.js", "welcome.js")) "application/javascript; charset=utf-8" else if (filename %in% c("runner.css", "maxdiff.css", "welcome.css")) "text/css; charset=utf-8" else if (filename == "../brand/brohn-app-icon.svg") "image/svg+xml" else "text/html; charset=utf-8"
        return(.brohn_delivery_response(body = readBin(file, "raw", n = file.info(file)$size), type = type))
      }
      parts <- strsplit(sub("^/", "", path), "/", fixed = TRUE)[[1]]
      .brohn_delivery_require(length(parts) >= 3L && identical(parts[[1]], "api"), "Route was not found.", 404, "not_found")
      operation <- parts[[2]]; identity <- parts[[3]]
      if (method == "GET" && operation == "assets" && length(parts) == 4L) {
        row <- .brohn_delivery_deployment_row(store, token = identity)
        .brohn_delivery_require(nrow(row) == 1L, "Asset was not found.", 404, "not_found")
        hash <- parts[[4]]; design <- .brohn_delivery_design(row)
        materials <- c(design$stimuli, unlist(lapply(design$blocks, function(block) block$materials), recursive = FALSE))
        if (!is.null(design$welcome$asset)) materials <- c(materials, list(design$welcome))
        if(brohn_has_illustrations(design))materials <- c(materials,brohn_study_illustrations(design))
        assets <- Filter(function(s) !is.null(s$asset) && identical(s$asset$hash, hash), materials)
        .brohn_delivery_require(length(assets) > 0L && .brohn_delivery_media_allowed(assets[[1]]$asset$media_type), "Asset is not part of this release.", 404, "not_found")
        file <- brohn_object_path(store, hash, verify = TRUE)
        return(.brohn_delivery_response(body = list(file = file, owned = FALSE), type = assets[[1]]$asset$media_type))
      }
      .brohn_delivery_require(length(parts) == 3L, "Route was not found.", 404, "not_found")
      if (method == "GET" && operation == "session_status") {
        authorization <- brohn_default(req$HTTP_AUTHORIZATION, "")
        .brohn_delivery_require(grepl("^Bearer [a-f0-9]{64}$", authorization), "Run access is required.", 401, "unauthorized")
        row <- .brohn_delivery_authorize(store, identity, substring(authorization, 8L))
        return(.brohn_delivery_response(value = list(run_id = identity, completion_status = row$completion_status[[1L]],
          researcher_resolution = if (exists("brohn_session_resolution_participant", mode = "function")) brohn_session_resolution_participant(store, identity) else NULL)))
      }
      if (method == "GET" && operation == "entry") {
        row <- .brohn_delivery_deployment_row(store, token = identity)
        .brohn_delivery_require(nrow(row) == 1L, "Study link was not found.", 404, "not_found")
        design <- .brohn_delivery_design(row)
        value <- list(deployment = list(id = row$id[[1]], title = row$title[[1]], origin = row$origin[[1]], status = row$status[[1]]),
          consent = design$consent, appearance = design$appearance, supported = TRUE,
          alias_required = as.logical(row$alias_required[[1]]), debrief = design$debrief)
        # Keep the frozen manifest unchanged. The release capability only grants
        # image access to the asset retained in this release's original design.
        if (!is.null(design$welcome)) {
          value$welcome <- design$welcome
          if (!is.null(design$welcome$asset)) value$welcome_image_url <- paste0("/api/assets/", identity, "/", design$welcome$asset$hash)
        }
        return(.brohn_delivery_response(value = value))
      }
      .brohn_delivery_require(method == "POST" && operation %in% c("start", "events", "finish", "questionnaire_state", "camera_start", "camera_chunk", "camera_finish"), "Route was not found.", 404, "not_found")
      request <- .brohn_delivery_request(req)
      if (operation == "start") value <- .brohn_delivery_start(store, identity, request)
      else {
        authorization <- brohn_default(req$HTTP_AUTHORIZATION, "")
        .brohn_delivery_require(grepl("^Bearer [a-f0-9]{64}$", authorization), "Run access is required.", 401, "unauthorized")
        token <- substring(authorization, 8L)
        value <- switch(operation, events = .brohn_delivery_receive(store, identity, token, request), finish = .brohn_delivery_finish(store, identity, token, request),
          questionnaire_state = .brohn_delivery_questionnaire_state(store, identity, token, request),
          camera_start = .brohn_camera_start(store, identity, token, request), camera_chunk = .brohn_camera_chunk(store, identity, token, request), camera_finish = .brohn_camera_finish(store, identity, token, request))
      }
      .brohn_delivery_response(value = value)
    }, error = function(e) {
      if (inherits(e, "brohn_delivery_error")) return(.brohn_delivery_response(e$status, list(error = list(code = e$code, message = conditionMessage(e)))))
      if (inherits(e, "brohn_store_error")) {
        if (identical(e$code, "busy")) {
          response <- .brohn_delivery_response(503L, list(error = list(code = "workspace_busy", retryable = TRUE,
            retry_after_seconds = 1L, message = "The study is briefly busy saving data. Your browser keeps this request; please retry shortly.")))
          response$headers[["Retry-After"]] <- "1"
          return(response)
        }
        status <- if (e$code %in% c("revision_conflict", "idempotency_conflict")) 409L else if (e$code == "too_large") 413L else 500L
        return(.brohn_delivery_response(status, list(error = list(code = e$code,
          message = if (status == 500L) "The workspace could not safely save this request. Retry or contact your researcher." else conditionMessage(e)))))
      }
      # Domain/JSON validation errors are user-correctable. Do not expose SQL,
      # filesystem paths or backend internals from arbitrary runtime failures.
      message <- conditionMessage(e)
      if (inherits(e, "simpleError") && !grepl("SQL|sqlite|connection|cannot open|no such|syntax error", message, ignore.case = TRUE))
        return(.brohn_delivery_response(400L, list(error = list(code = "invalid_request", message = substr(message, 1, 400)))))
      .brohn_delivery_response(500L, list(error = list(code = "internal", message = "The request could not be saved. Please retry or contact your researcher.")))
    })
  })
}
