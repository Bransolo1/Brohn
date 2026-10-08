# Inactive receiver. No route/loader/renderer registration or legacy mutation.
.brohn_pvr_profile <- "participant-view-event-derivation/0.1"
.brohn_pvr_require <- function(ok, message, code = "integrity", status = 409L)
  .brohn_pvds_require(ok, message, code, status)
.brohn_pvr_tables <- c("delivery_view_operations", "delivery_view_derivations")
.brohn_pvr_ready <- function(store) {
  .brohn_pvds_tables(store)
  .brohn_pvr_require(all(.brohn_pvr_tables %in% DBI::dbListTables(store$con)),
    "Assigned response storage is not initialized.", "profile_unavailable", 503L)
  invisible(TRUE)
}
.brohn_pvr_schema_statements <- function() {
  statements <- c(
      paste0("CREATE TABLE IF NOT EXISTS delivery_view_operations (run_id TEXT NOT NULL REFERENCES delivery_run_presentations(run_id),operation_id TEXT NOT NULL,",
        "profile TEXT NOT NULL CHECK(profile='participant-view-event-derivation/0.1'),source_hash TEXT NOT NULL,view_hash TEXT NOT NULL,map_hash TEXT NOT NULL,",
        "request_codec TEXT NOT NULL CHECK(request_codec='brohn-participant-request-json/0.1'),request_bytes INTEGER NOT NULL CHECK(request_bytes BETWEEN 1 AND 4194304),request_sha256 TEXT NOT NULL,request_blob BLOB NOT NULL CHECK(typeof(request_blob)='blob' AND length(request_blob)=request_bytes),",
        "first_sequence INTEGER NOT NULL,last_sequence INTEGER NOT NULL,event_count INTEGER NOT NULL,prior_ack INTEGER NOT NULL,committed_ack INTEGER NOT NULL,",
        "implementation_bytes INTEGER NOT NULL CHECK(implementation_bytes BETWEEN 1 AND 16777216),implementation_sha256 TEXT NOT NULL,implementation_blob BLOB NOT NULL CHECK(typeof(implementation_blob)='blob' AND length(implementation_blob)=implementation_bytes),",
        "model_bytes INTEGER NOT NULL CHECK(model_bytes BETWEEN 1 AND 4194304),model_sha256 TEXT NOT NULL,model_blob BLOB NOT NULL CHECK(typeof(model_blob)='blob' AND length(model_blob)=model_bytes),",
        "receipt_bytes INTEGER NOT NULL CHECK(receipt_bytes BETWEEN 1 AND 4194304),receipt_sha256 TEXT NOT NULL,receipt_blob BLOB NOT NULL CHECK(typeof(receipt_blob)='blob' AND length(receipt_blob)=receipt_bytes),",
        "result_bytes INTEGER NOT NULL CHECK(result_bytes BETWEEN 1 AND 4194304),result_sha256 TEXT NOT NULL,result_blob BLOB NOT NULL CHECK(typeof(result_blob)='blob' AND length(result_blob)=result_bytes),created_at TEXT NOT NULL,",
        "PRIMARY KEY(run_id,operation_id),CHECK(prior_ack BETWEEN 0 AND 9999999 AND first_sequence=prior_ack+1 AND last_sequence=committed_ack AND last_sequence BETWEEN first_sequence AND 10000000 AND event_count BETWEEN 1 AND 1000 AND last_sequence-first_sequence+1=event_count),",
        "CHECK(length(source_hash)=64 AND length(view_hash)=64 AND length(map_hash)=64 AND length(request_sha256)=64 AND length(implementation_sha256)=64 AND length(model_sha256)=64 AND length(receipt_sha256)=64 AND length(result_sha256)=64))"),
      paste0("CREATE TABLE IF NOT EXISTS delivery_view_derivations (run_id TEXT NOT NULL,operation_id TEXT NOT NULL,input_index INTEGER NOT NULL CHECK(input_index BETWEEN 1 AND 1000),sequence INTEGER NOT NULL,event_id TEXT NOT NULL,",
        "derived_codec TEXT NOT NULL CHECK(derived_codec='brohn-participant-json-bytes/0.1'),derived_bytes INTEGER NOT NULL CHECK(derived_bytes BETWEEN 1 AND 16777216),derived_sha256 TEXT NOT NULL CHECK(length(derived_sha256)=64),",
        "PRIMARY KEY(run_id,operation_id,input_index),UNIQUE(run_id,sequence),UNIQUE(run_id,event_id),",
        "FOREIGN KEY(run_id,operation_id) REFERENCES delivery_view_operations(run_id,operation_id),FOREIGN KEY(run_id,sequence) REFERENCES delivery_events(run_id,sequence))"),
      "CREATE TRIGGER IF NOT EXISTS delivery_view_derivation_match BEFORE INSERT ON delivery_view_derivations WHEN NOT EXISTS (SELECT 1 FROM delivery_view_operations o JOIN delivery_events e ON e.run_id=o.run_id AND e.sequence=NEW.sequence WHERE o.run_id=NEW.run_id AND o.operation_id=NEW.operation_id AND NEW.input_index<=o.event_count AND NEW.sequence=o.first_sequence+NEW.input_index-1 AND e.event_id=NEW.event_id AND e.event_hash=NEW.derived_sha256 AND typeof(e.event_json)='text' AND length(CAST(e.event_json AS BLOB))=NEW.derived_bytes) BEGIN SELECT RAISE(ABORT,'Derived event differs from its received operation'); END"
  )
  for (table in .brohn_pvr_tables) for (operation in c("UPDATE", "DELETE")) statements <- c(statements, paste0(
      "CREATE TRIGGER IF NOT EXISTS ", table, "_no_", tolower(operation), " BEFORE ", operation, " ON ", table,
      " BEGIN SELECT RAISE(ABORT,'Received operation evidence is immutable'); END"))
  statements
}
brohn_initialize_participant_view_receiving <- function(store) {
  .brohn_pvds_tables(store)
  .brohn_pvr_require(!RSQLite::sqliteIsTransacting(store$con), "Initialize response storage outside a caller transaction.", "nested_transaction")
  .brohn_store_tx(store, function() {
    for (sql in .brohn_pvr_schema_statements()) DBI::dbExecute(store$con, sql)
    invisible(TRUE)
  })
}
.brohn_pvr_counter <- function(rows, name) {
  .brohn_pvr_require(is.data.frame(rows) && nrow(rows) == 1L && ncol(rows) == 1L && identical(names(rows), name),
    "SQLite response-change observation is unavailable.", "change_fence")
  value <- rows[[1L]]
  .brohn_pvr_require(is.numeric(value) && !is.object(value) && length(value) == 1L && is.finite(value) &&
    value >= 0 && value == floor(value) && value <= 2^53 - 1, "SQLite response-change observation is invalid.", "change_fence")
  as.numeric(value)
}
.brohn_pvr_stamp <- function(store) list(
  data_version = .brohn_pvr_counter(.brohn_pvds_q(store, "PRAGMA main.data_version"), "data_version"),
  total_changes = .brohn_pvr_counter(.brohn_pvds_q(store, "SELECT total_changes() AS total_changes"), "total_changes"))
.brohn_pvr_same_stamp <- function(store, expected) .brohn_pvr_require(identical(.brohn_pvr_stamp(store), expected),
  "Saved data changed while these responses were prepared. Retry the same operation.", "state_changed")
.brohn_pvr_schema <- function(store) .brohn_pvds_q(store,
  "SELECT type,name,tbl_name,sql FROM sqlite_master ORDER BY type,name")
.brohn_pvr_schema_admit <- function(store) {
  # Source-owned SQL, never inferred from the live database. SQLite removes the
  # IF NOT EXISTS clause in sqlite_master; the remaining source spelling is exact.
  expected <- c(.brohn_pvr_schema_statements(),
    "CREATE TABLE IF NOT EXISTS delivery_events (run_id TEXT NOT NULL, sequence INTEGER NOT NULL CHECK(sequence>0), event_id TEXT NOT NULL, event_json TEXT NOT NULL, event_hash TEXT NOT NULL, received_at TEXT NOT NULL, PRIMARY KEY(run_id,sequence), UNIQUE(run_id,event_id), FOREIGN KEY(run_id) REFERENCES delivery_runs(id))",
    "CREATE TRIGGER IF NOT EXISTS delivery_events_no_update BEFORE UPDATE ON delivery_events BEGIN SELECT RAISE(ABORT,'Received events are immutable'); END",
    "CREATE TRIGGER IF NOT EXISTS delivery_events_no_delete BEFORE DELETE ON delivery_events BEGIN SELECT RAISE(ABORT,'Received events are immutable'); END")
  expected <- sub(" IF NOT EXISTS", "", expected, fixed = TRUE)
  for (sql in expected) {
    fields <- strsplit(sql, " ", fixed = TRUE)[[1L]]
    actual <- .brohn_pvds_q(store, "SELECT type,name,sql FROM sqlite_master WHERE name=?", list(fields[[3L]]))
    .brohn_pvr_require(nrow(actual) == 1L && identical(actual$type[[1L]], tolower(fields[[2L]])) &&
      identical(actual$sql[[1L]], sql), "The required response storage contract is missing or changed.", "schema_integrity")
  }
  foreign_keys <- .brohn_pvr_counter(.brohn_pvds_q(store, "PRAGMA foreign_keys"), "foreign_keys")
  checks_ignored <- .brohn_pvr_counter(.brohn_pvds_q(store, "PRAGMA ignore_check_constraints"), "ignore_check_constraints")
  .brohn_pvr_require(foreign_keys == 1 && checks_ignored == 0,
    "Response storage requires its foreign-key and CHECK constraints.", "schema_integrity")
  .brohn_pvr_schema(store)
}
.brohn_pvr_request <- function(raw) {
  received <- brohn_participant_received_bytes(raw)
  x <- received$value
  brohn_fields(x, c("schema", "view_hash", "operation_id", "events"), label = "Assigned response operation")
  .brohn_pvr_require(identical(x$schema, "participant-view-events/0.1") && .brohn_ph_sha(x$view_hash) &&
    brohn_text(x$operation_id, 128L) && brohn_array(x$events) && length(x$events) >= 1L && length(x$events) <= 1000L,
    "Use one complete assigned response operation.", "invalid_request", 400L)
  for (i in seq_along(x$events)) {
    event <- x$events[[i]]
    brohn_fields(event, c("sequence", "id", "type", "step_key", "phase", "clock", "payload"), label = "Assigned response event")
    .brohn_pvr_require(brohn_number(event$sequence, 1, 10000000, TRUE) && brohn_text(event$id, 128L),
      "Each response needs its original identity and sequence.", "invalid_request", 400L)
    if (i > 1L) .brohn_pvr_require(event$sequence == x$events[[i - 1L]]$sequence + 1L,
      "Response operations must contain a contiguous suffix.", "sequence_order")
  }
  .brohn_pvr_require(!anyDuplicated(vapply(x$events, `[[`, character(1), "id")), "Event identity repeats in this operation.", "event_id_conflict")
  list(received = received, request = x)
}
.brohn_pvr_operation <- function(input) {
  events <- input$request$events; first <- events[[1L]]$sequence; last <- events[[length(events)]]$sequence
  list(operation_id = input$request$operation_id, request = input$received[c("codec", "bytes", "sha256")],
    sequence = list(first = first, last = last, count = length(events), prior_ack = first - 1, committed_ack = last))
}
.brohn_pvr_identity_validate <- function(x) {
  .brohn_vad_domain(x)
  brohn_fields(x, c("schema", "profile", "assigned_profile", "renderer_identity", "runtime", "files", "packages"), label = "Saved derivation implementation")
  .brohn_pvr_require(identical(x$schema, "participant-view-derivation-implementation/0.1") && identical(x$profile, .brohn_pvr_profile) &&
    identical(x$assigned_profile, "participant-view-delivery/0.1") && brohn_array(x$files) && length(x$files) > 0L &&
    brohn_array(x$packages) && length(x$packages) > 0L, "Unsupported saved derivation implementation descriptor.")
  .brohn_pvc_renderer(x$renderer_identity)
  brohn_fields(x$runtime, c("r_version", "platform"), label = "Derivation R runtime")
  .brohn_pvr_require(brohn_text(x$runtime$r_version, 128L) && brohn_text(x$runtime$platform, 256L),
    "Invalid derivation R runtime descriptor.")
  for (f in x$files) {
    brohn_fields(f, c("path", "bytes", "sha256"), label = "Derivation source file")
    .brohn_pvr_require(brohn_text(f$path, 512L) && grepl("^[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)*$", f$path) &&
      !any(strsplit(f$path, "/", fixed = TRUE)[[1L]] %in% c(".", "..")) && !grepl("[\r\n]", f$path) &&
      brohn_number(f$bytes, 1, 2^53 - 1, TRUE) && .brohn_ph_sha(f$sha256), "Invalid logical derivation file descriptor.")
  }
  for (p in x$packages) {
    brohn_fields(p, c("name", "version"), label = "Derivation runtime package")
    .brohn_pvr_require(brohn_text(p$name, 120L) && brohn_text(p$version, 128L), "Invalid runtime package descriptor.")
  }
  .brohn_pvr_require(!anyDuplicated(tolower(vapply(x$files, `[[`, character(1), "path"))) &&
    !anyDuplicated(vapply(x$packages, `[[`, character(1), "name")), "Derivation implementation repeats a file or runtime package.")
  invisible(TRUE)
}
.brohn_pvr_identity <- function(binding) {
  .brohn_pvr_require(exists(".brohn_participant_view_derivation_registration", mode = "function"),
    "No assigned response derivation implementation is registered.", "derivation_unavailable", 503L)
  value <- .brohn_participant_view_derivation_registration()
  .brohn_pvr_identity_validate(value)
  .brohn_pvr_require(.brohn_ph_equal(value$renderer_identity, binding$renderer_identity),
    "The saved presentation requires its compatible registered response derivation.", "derivation_unavailable", 503L)
  .brohn_pvr_require(identical(value$runtime$r_version, as.character(getRversion())) &&
    identical(value$runtime$platform, R.version$platform), "The registered derivation R runtime changed.", "derivation_unavailable", 503L)
  for (p in value$packages) {
    actual <- if (identical(p$name, "R")) as.character(getRversion()) else as.character(utils::packageVersion(p$name))
    .brohn_pvr_require(identical(actual, p$version), "The registered derivation runtime changed.", "derivation_unavailable", 503L)
  }
  brohn_participant_json_bytes(value)
}
.brohn_pvr_source_cas <- function(store, original) {
  # Reuse the existing release metadata and SQL raw-byte comparison. They never
  # hydrate the source BLOBs or rebuild a complete context here.
  .brohn_pvds_ready(store)
  .brohn_pvr_require(!.brohn_store_execution_paused(store), "This restored workspace is paused.", "workspace_paused")
  run <- original$run; source <- original$source
  .brohn_pvds_hosted_run(store, run$run_id, run$deployment_id)
  m <- .brohn_pvds_release_meta(store, id = run$deployment_id)
  .brohn_pvds_release_equal(store, list(metadata = source$metadata, bodies = source$raw), m)
  .brohn_pvr_require(identical(m, source$metadata), "Release settings changed while responses were prepared.", "state_changed")
  pnames <- c("run_id", "public_run_id", "deployment_id", "workspace_id", "study_id", "project_id", "study_revision", "allocation_index",
    "source_protocol_sha256", "source_protocol_bytes", "release_raw_sha256", "release_raw_bytes", "study_raw_sha256", "study_raw_bytes",
    "profile", "renderer_id", "runtime_manifest_hash", "codec", "view_sha256", "view_bytes", "map_sha256", "map_bytes", "created_at")
  rnames <- c("deployment_id", "study_id", "origin", "client_id", "start_hash", "allocation_index", "participant_alias", "participant_alias_supplied",
    "acked_sequence", "completion_status", "transfer_status")
  snames <- c("deployment_id", "operation_id", "run_id", "client_id", "request_codec", "request_sha256", "request_bytes", "outcome",
    "initial_response_sha256", "initial_response_bytes")
  n <- .brohn_pvds_q(store, paste(
    "SELECT count(*) AS n FROM delivery_runs r JOIN delivery_run_presentations p ON p.run_id=r.id",
    "JOIN delivery_run_credentials c ON c.run_id=r.id JOIN delivery_run_runtimes t ON t.run_id=r.id",
    "JOIN delivery_view_start_receipts s ON s.run_id=r.id AND s.outcome='created'",
    "WHERE r.id=? AND r.protocol_hash=? AND CAST(r.protocol_json AS BLOB)=? AND p.view_blob=? AND p.map_blob=?",
    "AND c.token_hash=? AND c.token=? AND t.deployment_id=? AND t.manifest_hash=? AND",
    paste(paste0("p.", pnames, " IS ?"), collapse = " AND "), "AND", paste(paste0("r.", rnames, " IS ?"), collapse = " AND "),
    "AND", paste(paste0("s.", snames, " IS ?"), collapse = " AND "), "AND s.request_blob=?"),
    c(list(run$run_id, original$binding$source_protocol_hash, list(source$raw$protocol), list(source$raw$view), list(source$raw$map),
      .brohn_delivery_hash(original$access_token), original$access_token, m$deployment_id, m$manifest_hash),
      unname(source$presentation[pnames]), unname(run[rnames]), unname(source$receipt[snames]), list(list(source$raw$request))))$n[[1L]]
  .brohn_pvr_require(n == 1L, "The admitted participant bytes or progress changed before response commit.", "source_changed")
  invisible(TRUE)
}
.brohn_pvr_unresolved <- function(store, run_id) {
  rows <- .brohn_pvds_q(store, "SELECT revision FROM entities WHERE kind='session_resolution' AND id=?", list(.brohn_sr_id(run_id)))
  .brohn_pvr_require(nrow(rows) == 0L,
    "This session's received evidence was closed by the researcher. New uploads cannot change its saved resolution; existing local data have not been deleted.", "researcher_resolved")
  invisible(TRUE)
}
.brohn_pvr_equipment_check <- function(store, original, capture) {
  # Private operation-local adapter, reached only after captured row admission.
  # Copy-on-modify changes its lexical lookup, never the original function body
  # or environment. All other lookups retain the original lexical parent.
  original_check <- .brohn_equipment_receive
  scope <- new.env(parent = environment(original_check))
  scope$brohn_capture <- function(actual_store, capture_id = NULL, run_id = NULL) {
    .brohn_pvr_require(identical(actual_store$con, store$con) && identical(actual_store$workspace_id, store$workspace_id) &&
      is.null(capture_id) && identical(run_id, original$run$run_id), "Camera validation attempted a different captured source.")
    capture
  }
  lockEnvironment(scope, bindings = TRUE)
  check <- original_check; environment(check) <- scope
  check
}
.brohn_pvr_equipment <- function(store, original, events) {
  selected <- Filter(function(e) identical(e$type, "equipment_event") && e$payload$kind %in% c("camera", "camera_declined"), events)
  if (!length(selected)) return(NULL)
  .brohn_pvr_require(all(c("camera_captures", "camera_chunks") %in% DBI::dbListTables(store$con)),
    "Camera equipment evidence has no saved receiver storage.", "equipment_receipt")
  run_id <- original$run$run_id
  columns <- c("id", "run_id", "project_id", "start_hash", "status", "acked_sequence", "total_bytes", "last_callback_ms",
    "last_frame_now_ms", "frame_callbacks", "final_hash", "created_at", "updated_at")
  meta <- .brohn_pvds_one(.brohn_pvds_q(store, paste("SELECT", paste(columns, collapse = ","),
    ",typeof(start_json) AS start_type,length(CAST(start_json AS BLOB)) AS start_bytes,",
    "typeof(final_json) AS final_type,length(CAST(final_json AS BLOB)) AS final_bytes FROM camera_captures WHERE run_id=?"), list(run_id)),
    "Camera equipment evidence has no unique original capture.")
  .brohn_pvds_size(meta$start_bytes)
  .brohn_pvr_require(identical(meta$start_type, "text") && .brohn_ph_sha(meta$start_hash) &&
    identical(meta$project_id, original$source$metadata$project_id), "Camera receipt owner or original bytes are invalid.")
  has_final <- !identical(meta$final_type, "null")
  if (has_final) {
    .brohn_pvds_size(meta$final_bytes)
    .brohn_pvr_require(identical(meta$final_type, "text") && .brohn_ph_sha(meta$final_hash), "Camera final receipt bytes are invalid.")
  }
  raw <- .brohn_pvds_one(.brohn_pvds_q(store,
    "SELECT CAST(start_json AS BLOB) AS start,CAST(final_json AS BLOB) AS final FROM camera_captures WHERE id=? AND run_id=?", list(meta$id, run_id)),
    "The camera receipt changed during preparation.")
  .brohn_pvr_require(is.raw(raw$start) && length(raw$start) == meta$start_bytes && identical(.brohn_pvds_sha(raw$start), meta$start_hash),
    "Camera original receipt failed its raw hash.")
  parsed_start <- .brohn_pvds_decode(raw$start)
  .brohn_pvr_require(is.list(parsed_start) && !is.null(names(parsed_start)), "Camera start receipt must be a literal object.")
  if (has_final) {
    .brohn_pvr_require(is.raw(raw$final) && length(raw$final) == meta$final_bytes && identical(.brohn_pvds_sha(raw$final), meta$final_hash),
      "Camera final receipt failed its raw hash.")
    parsed_final <- .brohn_pvds_decode(raw$final)
    .brohn_pvr_require(is.list(parsed_final) && !is.null(names(parsed_final)), "Camera final receipt must be a literal object.")
  } else .brohn_pvr_require(is.null(raw$final) || length(raw$final) == 1L && is.na(raw$final), "Missing camera final receipt changed type.")
  row <- as.data.frame(meta[columns], stringsAsFactors = FALSE)
  row$start_json <- .brohn_pvds_text(raw$start); row$final_json <- if (has_final) .brohn_pvds_text(raw$final) else NA_character_
  capture <- .brohn_camera_decode(row)
  check <- .brohn_pvr_equipment_check(store, original, capture)
  for (event in selected) check(store, list(id = run_id), event)
  prefixes <- lapply(selected, function(event) {
    if (identical(event$payload$kind, "camera_declined")) return(NULL)
    through <- event$payload$evidence$recording$acked_sequence
    row <- .brohn_pvds_one(.brohn_pvds_q(store, "SELECT count(*) AS count,sum(byte_count) AS bytes FROM camera_chunks WHERE capture_id=? AND sequence<=?",
      list(meta$id, through)), "Camera byte prefix is unavailable.")
    list(through = through, row = row)
  })
  list(metadata = meta[columns], raw = list(start = raw$start, final = if (has_final) raw$final else NULL), prefixes = Filter(Negate(is.null), prefixes))
}
.brohn_pvr_equipment_cas <- function(store, proof) {
  if (is.null(proof)) return(invisible(TRUE))
  names <- names(proof$metadata)
  n <- .brohn_pvds_q(store, paste("SELECT count(*) AS n FROM camera_captures WHERE",
    paste(paste0(names, " IS ?"), collapse = " AND "), "AND CAST(start_json AS BLOB)=? AND CAST(final_json AS BLOB) IS ?"),
    c(unname(proof$metadata), list(list(proof$raw$start)), list(if (is.null(proof$raw$final)) NA_character_ else list(proof$raw$final))))$n[[1L]]
  .brohn_pvr_require(n == 1L, "Camera receipt changed while responses were prepared.", "state_changed")
  for (p in proof$prefixes) {
    now <- .brohn_pvds_one(.brohn_pvds_q(store,
      "SELECT count(*) AS count,sum(byte_count) AS bytes FROM camera_chunks WHERE capture_id=? AND sequence<=?", list(proof$metadata$id, p$through)),
      "Camera byte prefix is unavailable.")
    .brohn_pvr_require(identical(now, p$row), "Camera byte prefix changed while responses were prepared.", "state_changed")
  }
  invisible(TRUE)
}
.brohn_pvr_document <- function(raw, bytes, hash, maximum = 4 * 1024^2) {
  .brohn_pvds_size(bytes, maximum)
  .brohn_pvr_require(is.raw(raw) && length(raw) == bytes && .brohn_ph_sha(hash) && identical(.brohn_pvds_sha(raw), hash),
    "A saved operation document failed its original byte hash.")
  value <- .brohn_pvds_decode(raw)
  encoded <- brohn_participant_json_bytes(value, maximum_bytes = maximum)
  .brohn_pvr_require(identical(charToRaw(encoded$json), raw), "A saved operation document is not its canonical original encoding.")
  list(document = list(codec = "brohn-participant-json-bytes/0.1", json = .brohn_pvds_text(raw), bytes = bytes, sha256 = hash), value = value)
}
.brohn_pvr_has_operation <- function(store, run_id, operation_id) {
  rows <- .brohn_pvds_q(store, "SELECT operation_id FROM delivery_view_operations WHERE run_id=? AND operation_id=?", list(run_id, operation_id))
  .brohn_pvr_require(nrow(rows) <= 1L, "Operation identity is ambiguous.")
  nrow(rows) == 1L
}
.brohn_pvr_prior <- function(store, original, input) {
  run_id <- original$run$run_id; operation_id <- input$request$operation_id
  if (!.brohn_pvr_has_operation(store, run_id, operation_id)) return(NULL)
  names <- c("request", "implementation", "model", "receipt", "result")
  meta <- .brohn_pvds_one(.brohn_pvds_q(store, paste(
    "SELECT run_id,operation_id,profile,source_hash,view_hash,map_hash,request_codec,first_sequence,last_sequence,event_count,prior_ack,committed_ack,created_at,",
    paste(unlist(lapply(names, function(n) c(paste0(n, "_bytes"), paste0(n, "_sha256"), paste0("typeof(", n, "_blob) AS ", n, "_type"),
      paste0("length(", n, "_blob) AS ", n, "_length")))), collapse = ","),
    "FROM delivery_view_operations WHERE run_id=? AND operation_id=?"), list(run_id, operation_id)), "The saved response operation is unavailable.")
  .brohn_pvr_require(identical(meta$profile, .brohn_pvr_profile) && identical(meta$source_hash, original$binding$source_protocol_hash) &&
    identical(meta$view_hash, original$context$view_hash) && identical(meta$map_hash, original$source$presentation$map_sha256),
    "The saved response operation belongs to another source or unsupported derivation profile.")
  for (name in names) {
    .brohn_pvds_size(meta[[paste0(name, "_bytes")]], if (name == "implementation") 16 * 1024^2 else 4 * 1024^2)
    .brohn_pvr_require(identical(meta[[paste0(name, "_type")]], "blob") && meta[[paste0(name, "_length")]] == meta[[paste0(name, "_bytes")]],
      "Saved operation BLOB metadata disagrees.")
  }
  raw <- .brohn_pvds_one(.brohn_pvds_q(store, paste("SELECT", paste(paste0(names, "_blob AS ", names), collapse = ","),
    "FROM delivery_view_operations WHERE run_id=? AND operation_id=?"), list(run_id, operation_id)), "Saved operation bytes changed.")
  .brohn_pvr_require(is.raw(raw$request) && length(raw$request) == meta$request_bytes && identical(.brohn_pvds_sha(raw$request), meta$request_sha256),
    "The original received operation failed its byte hash.")
  .brohn_pvr_require(identical(raw$request, input$received$raw) && identical(meta$request_codec, input$received$codec),
    "This operation identity was reused with different bytes.", "idempotency_conflict")
  documents <- lapply(setdiff(names, "request"), function(n) .brohn_pvr_document(raw[[n]], meta[[paste0(n, "_bytes")]], meta[[paste0(n, "_sha256")]],
    if (n == "implementation") 16 * 1024^2 else 4 * 1024^2))
  names(documents) <- setdiff(names, "request")
  .brohn_pvr_identity_validate(documents$implementation$value)
  operation <- .brohn_pvr_operation(input); binding <- .brohn_pvcr_binding(original$context)
  .brohn_pvr_require(.brohn_ph_equal(documents$implementation$value$renderer_identity, binding$renderer_identity),
    "The saved derivation implementation belongs to another presentation renderer.")
  .brohn_pvr_require(identical(as.numeric(unlist(meta[c("first_sequence", "last_sequence", "event_count", "prior_ack", "committed_ack")], use.names = FALSE)),
    as.numeric(unlist(operation$sequence, use.names = FALSE))), "Saved receipt sequence metadata differs from its exact request.")
  .brohn_pvr_require(original$run$acked_sequence >= operation$sequence$committed_ack,
    "The saved run acknowledgement precedes its committed operation.", "journal_integrity")
  model <- documents$model$value; receipt <- documents$receipt$value; result <- documents$result$value
  brohn_fields(model, c("schema", "binding", "acknowledged_sequence", "expected_sequence", "completion_status", "resume", "origin", "release_status", "researcher_resolution"), label = "Saved commit model")
  brohn_fields(receipt, c("schema", "binding", "operation_id", "request", "sequence", "model"), label = "Saved operation receipt")
  brohn_fields(result, c("schema", "receipt", "model_json"), label = "Saved operation result")
  .brohn_pvr_require(identical(model$schema, "participant-view-commit-model/0.1") && identical(receipt$schema, "participant-view-operation-receipt/0.1") &&
    identical(result$schema, "participant-view-events-result/0.1") && .brohn_ph_equal(model$binding, binding) && .brohn_ph_equal(receipt$binding, binding) &&
    .brohn_ph_equal(receipt[c("operation_id", "request", "sequence")], operation) &&
    .brohn_ph_equal(receipt$model, documents$model$document[c("codec", "bytes", "sha256")]) &&
    .brohn_ph_equal(result$receipt, receipt) && identical(result$model_json, documents$model$document$json) && is.null(model$researcher_resolution) &&
    model$acknowledged_sequence == operation$sequence$committed_ack && model$expected_sequence == operation$sequence$committed_ack + 1 &&
    identical(model$origin, original$origin), "Saved operation documents disagree with their exact committed source or interval.")
  .brohn_pvod_inputs(binding, operation, model[c("completion_status", "resume", "origin", "release_status")])
  rows <- .brohn_pvds_q(store, paste("SELECT d.input_index,d.sequence,d.event_id,d.derived_codec,d.derived_bytes,d.derived_sha256,",
    "e.event_hash,typeof(e.event_json) AS type,length(CAST(e.event_json AS BLOB)) AS bytes,e.event_id AS original_id",
    "FROM delivery_view_derivations d LEFT JOIN delivery_events e ON e.run_id=d.run_id AND e.sequence=d.sequence",
    "WHERE d.run_id=? AND d.operation_id=? ORDER BY d.input_index LIMIT 1001"), list(run_id, operation_id))
  .brohn_pvr_require(nrow(rows) == operation$sequence$count, "Saved operation has an incomplete derivation relation.")
  for (i in seq_len(nrow(rows))) {
    r <- lapply(rows, function(x) x[[i]])
    .brohn_pvds_size(r$derived_bytes)
    .brohn_pvr_require(r$input_index == i && r$sequence == input$request$events[[i]]$sequence && identical(r$event_id, input$request$events[[i]]$id) &&
      identical(r$original_id, r$event_id) && identical(r$derived_codec, "brohn-participant-json-bytes/0.1") &&
      identical(r$type, "text") && r$bytes == r$derived_bytes && identical(r$event_hash, r$derived_sha256), "Saved derivation relation changed.")
    b <- .brohn_pvds_one(.brohn_pvds_q(store, "SELECT CAST(event_json AS BLOB) AS body FROM delivery_events WHERE run_id=? AND sequence=?", list(run_id, r$sequence)),
      "A derived original event is missing.")$body
    event <- .brohn_pvr_document(b, r$derived_bytes, r$derived_sha256, 16 * 1024^2)$value
    .brohn_pvr_require(identical(event$id, r$event_id) && event$sequence == r$sequence, "Derived original event identity changed.")
  }
  documents$result$document
}
.brohn_pvr_insert <- function(store, original, input, operation, documents, derived) {
  s <- operation$sequence; source <- original$source; run_id <- original$run$run_id
  values <- list(run_id, operation$operation_id, .brohn_pvr_profile, original$binding$source_protocol_hash,
    original$context$view_hash, source$presentation$map_sha256, input$received$codec, input$received$bytes, input$received$sha256,
    list(input$received$raw), s$first, s$last, s$count, s$prior_ack, s$committed_ack)
  for (document in documents)
    values <- c(values, list(document$bytes, document$sha256, list(document$raw)))
  stamp <- brohn_now(); values <- c(values, list(stamp))
  n <- DBI::dbExecute(store$con, paste0("INSERT INTO delivery_view_operations VALUES(", paste(rep("?", length(values)), collapse = ","), ")"), params = values)
  .brohn_pvr_require(n == 1L, "The received operation was not inserted atomically.")
  for (i in seq_along(derived)) {
    d <- derived[[i]]; event <- input$request$events[[i]]
    n <- DBI::dbExecute(store$con, "INSERT INTO delivery_events(run_id,sequence,event_id,event_json,event_hash,received_at) VALUES(?,?,?,?,?,?)",
      params = list(run_id, event$sequence, event$id, d$json, d$sha256, stamp))
    .brohn_pvr_require(n == 1L, "An original response was not inserted atomically.")
    n <- DBI::dbExecute(store$con, "INSERT INTO delivery_view_derivations VALUES(?,?,?,?,?,?,?,?)",
      params = list(run_id, operation$operation_id, i, event$sequence, event$id, d$codec, d$bytes, d$sha256))
    .brohn_pvr_require(n == 1L, "A response derivation was not inserted atomically.")
  }
  n <- DBI::dbExecute(store$con, paste("UPDATE delivery_runs SET acked_sequence=?,updated_at=?",
    "WHERE id=? AND acked_sequence=? AND completion_status='in_progress' AND transfer_status='receiving'"),
    params = list(s$committed_ack, stamp, run_id, s$prior_ack))
  .brohn_pvr_require(n == 1L, "The participant acknowledgement changed before commit.", "state_changed")
  invisible(TRUE)
}
brohn_receive_participant_view_events <- function(store, public_run_id, access_token, request_raw) {
  .brohn_pvr_ready(store)
  .brohn_pvr_require(!RSQLite::sqliteIsTransacting(store$con), "Prepare responses outside an existing transaction.", "nested_transaction")
  .brohn_pvr_require(is.raw(request_raw) && is.null(attributes(request_raw)) && length(request_raw) >= 1L && length(request_raw) <= 4 * 1024^2,
    "Supply the complete original response request bytes.", "invalid_request", 400L)
  handle <- brohn_open_participant_view(store, public_run_id, access_token)
  on.exit(handle$close(), add = TRUE)
  input <- .brohn_pvr_request(request_raw)
  connection <- store$con; workspace <- store$workspace_id; root <- normalizePath(store$root, winslash = "/", mustWork = TRUE)
  assert_owned <- function() .brohn_pvr_require(identical(store$con, connection) && identical(store$workspace_id, workspace) &&
    identical(normalizePath(store$root, winslash = "/", mustWork = TRUE), root), "The owned response workspace changed.", "source_changed")
  read_prior <- function() {
    assert_owned(); before <- .brohn_pvr_stamp(store); original <- handle$read()
    .brohn_pvr_require(identical(input$request$view_hash, original$context$view_hash), "Responses belong to another saved participant view.", "view_conflict")
    value <- .brohn_pvds_readonly(store, function() .brohn_pvr_prior(store, original, input))
    last <- handle$read(); .brohn_pvcr_same_progress(.brohn_pvcr_progress(last$run), original$run)
    .brohn_pvr_same_stamp(store, before)
    value
  }
  previous <- read_prior()
  if (!is.null(previous)) return(previous)
  # No schema initialization, caller callback or own writes occur during this
  # operation-local preparation. The stamp covers replay, source checks and all
  # expensive translation/encoding until the original writer transaction begins.
  before <- .brohn_pvr_stamp(store); original <- handle$read(); context <- original$context
  .brohn_pvr_require(identical(input$request$view_hash, context$view_hash), "Responses belong to another saved participant view.", "view_conflict")
  operation <- .brohn_pvr_operation(input); binding <- .brohn_pvcr_binding(context)
  proof <- .brohn_pvds_readonly(store, function() {
    admitted_schema <- .brohn_pvr_schema_admit(store)
    implementation <- .brohn_pvr_identity(binding)
    .brohn_pvr_require(!.brohn_store_execution_paused(store), "This restored workspace is paused.", "workspace_paused")
    .brohn_pvcr_same_progress(.brohn_pvcr_run(store, original), original$run)
    .brohn_pvr_require(identical(original$run$completion_status, "in_progress") && identical(original$run$transfer_status, "receiving"),
      "This run has been finalized.", "finalized")
    .brohn_pvr_unresolved(store, original$run$run_id)
    .brohn_pvr_require(operation$sequence$prior_ack == original$run$acked_sequence,
      "An earlier response is missing or this operation overlaps saved responses. Reconcile the saved sequence.", "sequence_conflict")
    history <- .brohn_pvcr_history(store, original$run$run_id, original$run$acked_sequence, context)
    .brohn_pvcr_ending(original$run, history$state)
    state <- history$state; derived <- list(); events <- list(); ack <- original$run$acked_sequence
    for (event in input$request$events) {
      duplicate <- .brohn_pvds_q(store, "SELECT sequence FROM delivery_events WHERE run_id=? AND event_id=?", list(original$run$run_id, event$id))
      .brohn_pvr_require(nrow(duplicate) == 0L, "Event identity was already used at another sequence.", "event_id_conflict")
      applied <- brohn_apply_participant_view_event(context, state, event, ack)
      state <- applied$state; ack <- event$sequence
      events[[length(events) + 1L]] <- applied$source_event
      derived[[length(derived) + 1L]] <- brohn_participant_json_bytes(applied$source_event)
    }
    equipment <- .brohn_pvr_equipment(store, original, events)
    resume <- brohn_project_participant_forward_resume(context,
      .brohn_delivery_resume(state, context$protocol, context$revision_context, operation$sequence$committed_ack))
    docs <- .brohn_pvod_encode(binding, operation, list(completion_status = original$run$completion_status,
      resume = resume, origin = original$origin, release_status = original$release_status))
    documents <- lapply(c(list(implementation), docs[c("model", "receipt", "result")]), function(d)
      list(bytes = d$bytes, sha256 = d$sha256, raw = charToRaw(d$json)))
    .brohn_pvr_require(identical(.brohn_pvr_schema(store), admitted_schema), "Response storage schema changed during preparation.", "state_changed")
    list(history = history$prefix, derived = derived, documents = documents, equipment = equipment, schema = admitted_schema)
  })
  current <- handle$read(); .brohn_pvcr_same_progress(.brohn_pvcr_progress(current$run), original$run)
  .brohn_pvr_require(identical(current$source$metadata, original$source$metadata), "Released source settings changed during response preparation.", "state_changed")
  .brohn_pvds_readonly(store, function() {
    .brohn_pvr_unresolved(store, original$run$run_id)
    now <- .brohn_pvcr_history(store, original$run$run_id, original$run$acked_sequence)
    .brohn_pvr_require(identical(now$prefix, proof$history), "The saved response prefix changed during preparation.", "journal_integrity")
  })
  .brohn_pvr_same_stamp(store, before)
  used <- FALSE
  commit <- function() {
    .brohn_pvr_require(!used, "The response preparation has already been consumed.")
    used <<- TRUE; assert_owned()
    .brohn_store_tx(store, function() {
      # Another exact operation may have won before this writer acquired its
      # lock. Hydrate/validate it only after closing this no-write transaction.
      if (.brohn_pvr_has_operation(store, original$run$run_id, input$request$operation_id)) return(invisible(FALSE))
      .brohn_pvr_same_stamp(store, before)
      .brohn_pvr_require(identical(.brohn_pvr_schema_admit(store), proof$schema), "Response source schema changed during preparation.", "state_changed")
      .brohn_pvr_source_cas(store, original)
      .brohn_pvr_unresolved(store, original$run$run_id)
      .brohn_pvr_equipment_cas(store, proof$equipment)
      .brohn_pvr_same_stamp(store, before)
      .brohn_pvr_insert(store, original, input, operation, proof$documents, proof$derived)
      invisible(TRUE)
    })
  }
  commit()
  # Post-commit authority/byte failure must leave the immutable evidence intact.
  # The exact request can subsequently recover its original commit result.
  saved <- read_prior()
  .brohn_pvr_require(!is.null(saved), "The committed response receipt is unavailable.")
  saved
}
