# Inactive assigned-view first-start/store boundary. No loader or HTTP activation.
# The current-response coordinator and authorized bounded journal replay are not
# defined here. In particular an initial-size receipt is never a resume response.
.brohn_pvds_profile <- "participant-view-delivery/0.1"
.brohn_pvds_limit <- 16 * 1024^2
.brohn_pvds_http_limit <- 4 * 1024^2
.brohn_pvds_get <- function(x, name) x[[name, exact = TRUE]]
.brohn_pvds_require <- function(ok, message, code = "integrity", status = 409L) {
  .brohn_delivery_require(ok, message, status, code)
}
.brohn_pvds_sha <- function(x) digest::digest(x, algo = "sha256", serialize = FALSE)
.brohn_pvds_hash <- function(x) is.character(x) && length(x) == 1L && !is.na(x) &&
  grepl("^[0-9a-f]{64}$", x)
.brohn_pvds_one <- function(rows, message, code = "integrity", status = 409L) {
  .brohn_pvds_require(nrow(rows) == 1L, message, code, status)
  lapply(rows, function(x) x[[1L]])
}
.brohn_pvds_q <- function(store, sql, params = list()) {
  if (length(params)) DBI::dbGetQuery(store$con, sql, params = params) else DBI::dbGetQuery(store$con, sql)
}
.brohn_pvds_ready <- function(store) {
  .brohn_store_ready(store)
  row <- .brohn_pvds_q(store, "SELECT value FROM metadata WHERE key='workspace_id'")
  .brohn_pvds_require(nrow(row) == 1L && identical(row$value[[1L]], store$workspace_id),
    "This participant workspace changed. Reopen its original link.", "workspace", 403L)
  invisible(TRUE)
}
.brohn_pvds_tables <- function(store) {
  .brohn_pvds_ready(store)
  .brohn_pvds_require(all(c("delivery_view_releases", "delivery_run_presentations",
    "delivery_view_start_receipts") %in% DBI::dbListTables(store$con)),
    "Assigned participant presentation storage is not initialized.", "profile_unavailable", 503L)
}
.brohn_pvds_hosted_run <- function(store, run_id, deployment_id) {
  brohn_hosted_require_run(store, run_id)
  if (!is.null(store$hosted_profile)) {
    policy <- .brohn_pvds_one(.brohn_pvds_q(store,
      "SELECT deployment_id FROM hosted_run_policy WHERE run_id=?", list(run_id)), "The hosted run policy is missing.", "run_access", 403L)
    .brohn_pvds_require(identical(policy$deployment_id, deployment_id),
      "The hosted policy belongs to another release.", "run_access", 403L)
  }
  invisible(TRUE)
}
.brohn_pvds_registration <- function() {
  .brohn_pvds_require(exists(".brohn_participant_view_renderer_registration", mode = "function"),
    "No assigned-view participant renderer is registered.", "renderer_unavailable", 503L)
  r <- .brohn_participant_view_renderer_registration()
  .brohn_ph_domain(r)
  brohn_fields(r, c("profile", "renderer_id", "runtime_manifest_hash"), label = "Server renderer registration")
  .brohn_pvds_require(identical(r$profile, .brohn_pvds_profile) && brohn_text(r$renderer_id, 120L) &&
    !is.object(r$renderer_id) && .brohn_pvds_hash(r$runtime_manifest_hash),
    "The server renderer registration is invalid.", "renderer_unavailable", 503L)
  .brohn_pvc_renderer(.brohn_pvds_renderer(r))
  r
}
.brohn_pvds_renderer <- function(registration) list(schema = "participant-renderer-identity/0.1",
  id = registration$renderer_id, manifest_hash = registration$runtime_manifest_hash)
.brohn_pvds_readonly <- function(store, fn) {
  .brohn_pvds_ready(store)
  .brohn_pvds_require(!RSQLite::sqliteIsTransacting(store$con),
    "Open assigned participant sources outside an existing transaction.", "nested_transaction")
  prior <- .brohn_pvds_q(store, "PRAGMA query_only")[[1L]][[1L]]
  active <- FALSE
  on.exit({
    if (active) try(DBI::dbRollback(store$con), silent = TRUE)
    DBI::dbExecute(store$con, paste0("PRAGMA query_only=", as.integer(prior)))
  }, add = TRUE)
  DBI::dbExecute(store$con, "PRAGMA query_only=ON")
  DBI::dbBegin(store$con); active <- TRUE
  value <- fn()
  DBI::dbCommit(store$con); active <- FALSE
  value
}
.brohn_pvds_size <- function(value, maximum = .brohn_pvds_limit) {
  .brohn_pvds_require(brohn_number(value, 1, maximum, TRUE),
    "An original source or presentation exceeds its declared byte bound.", "source_size", 413L)
}
.brohn_pvds_text <- function(bytes) {
  .brohn_pvds_require(is.raw(bytes) && length(bytes) > 0L && !any(bytes == as.raw(0)),
    "Stored JSON bytes are invalid.")
  value <- rawToChar(bytes); Encoding(value) <- "UTF-8"
  .brohn_pvds_require(validUTF8(value), "Stored JSON is not UTF-8.")
  value
}
.brohn_pvds_decode <- function(bytes) {
  value <- jsonlite::parse_json(.brohn_pvds_text(bytes), simplifyVector = FALSE,
    simplifyDataFrame = FALSE, simplifyMatrix = FALSE, bigint_as_char = FALSE)
  .brohn_ph_domain(value)
  value
}

brohn_initialize_participant_view_store <- function(store) {
  .brohn_pvds_ready(store)
  .brohn_runner_schema(store)
  .brohn_store_tx(store, function() {
    sql <- c(
      "CREATE TABLE IF NOT EXISTS delivery_view_releases (deployment_id TEXT PRIMARY KEY REFERENCES delivery_deployments(id),profile TEXT NOT NULL CHECK(profile='participant-view-delivery/0.1'),renderer_id TEXT NOT NULL,runtime_manifest_hash TEXT NOT NULL CHECK(length(runtime_manifest_hash)=64),created_at TEXT NOT NULL)",
      paste0("CREATE TABLE IF NOT EXISTS delivery_run_presentations (run_id TEXT PRIMARY KEY REFERENCES delivery_runs(id),public_run_id TEXT NOT NULL UNIQUE,deployment_id TEXT NOT NULL REFERENCES delivery_view_releases(deployment_id),workspace_id TEXT NOT NULL,study_id TEXT NOT NULL,project_id TEXT NOT NULL,study_revision INTEGER NOT NULL CHECK(study_revision>0),allocation_index INTEGER NOT NULL CHECK(allocation_index>0),source_protocol_sha256 TEXT NOT NULL,source_protocol_bytes INTEGER NOT NULL CHECK(source_protocol_bytes BETWEEN 1 AND 16777216),release_raw_sha256 TEXT NOT NULL,release_raw_bytes INTEGER NOT NULL CHECK(release_raw_bytes BETWEEN 1 AND 16777216),study_raw_sha256 TEXT NOT NULL,study_raw_bytes INTEGER NOT NULL CHECK(study_raw_bytes BETWEEN 1 AND 16777216),profile TEXT NOT NULL CHECK(profile='participant-view-delivery/0.1'),renderer_id TEXT NOT NULL,runtime_manifest_hash TEXT NOT NULL,codec TEXT NOT NULL CHECK(codec='brohn-participant-json-bytes/0.1'),view_sha256 TEXT NOT NULL,view_bytes INTEGER NOT NULL CHECK(view_bytes BETWEEN 1 AND 16777216),view_blob BLOB NOT NULL CHECK(typeof(view_blob)='blob' AND length(view_blob)=view_bytes),map_sha256 TEXT NOT NULL,map_bytes INTEGER NOT NULL CHECK(map_bytes BETWEEN 1 AND 16777216),map_blob BLOB NOT NULL CHECK(typeof(map_blob)='blob' AND length(map_blob)=map_bytes),created_at TEXT NOT NULL, CHECK(length(source_protocol_sha256)=64 AND length(release_raw_sha256)=64 AND length(study_raw_sha256)=64 AND length(runtime_manifest_hash)=64 AND length(view_sha256)=64 AND length(map_sha256)=64))"),
      "CREATE TABLE IF NOT EXISTS delivery_view_start_receipts (deployment_id TEXT NOT NULL REFERENCES delivery_view_releases(deployment_id),operation_id TEXT NOT NULL,run_id TEXT NOT NULL REFERENCES delivery_run_presentations(run_id),client_id TEXT NOT NULL,request_codec TEXT NOT NULL CHECK(request_codec='brohn-participant-request-json/0.1'),request_sha256 TEXT NOT NULL CHECK(length(request_sha256)=64),request_bytes INTEGER NOT NULL CHECK(request_bytes BETWEEN 1 AND 4194304),request_blob BLOB NOT NULL CHECK(typeof(request_blob)='blob' AND length(request_blob)=request_bytes),outcome TEXT NOT NULL CHECK(outcome IN ('created','existing')),initial_response_sha256 TEXT NOT NULL CHECK(length(initial_response_sha256)=64),initial_response_bytes INTEGER NOT NULL CHECK(initial_response_bytes BETWEEN 1 AND 4194304),created_at TEXT NOT NULL,PRIMARY KEY(deployment_id,operation_id))",
      "CREATE UNIQUE INDEX IF NOT EXISTS delivery_view_one_creation ON delivery_view_start_receipts(run_id) WHERE outcome='created'",
      "CREATE TRIGGER IF NOT EXISTS delivery_view_release_match BEFORE INSERT ON delivery_view_releases WHEN NOT EXISTS (SELECT 1 FROM delivery_runtimes t WHERE t.deployment_id=NEW.deployment_id AND t.manifest_hash=NEW.runtime_manifest_hash) OR EXISTS (SELECT 1 FROM delivery_runs r WHERE r.deployment_id=NEW.deployment_id) BEGIN SELECT RAISE(ABORT,'Assigned-view release must precede its participants and match its runtime'); END",
      "CREATE TRIGGER IF NOT EXISTS delivery_view_presentation_match BEFORE INSERT ON delivery_run_presentations WHEN NOT EXISTS (SELECT 1 FROM delivery_runs r JOIN delivery_deployments d ON d.id=r.deployment_id JOIN delivery_view_releases f ON f.deployment_id=d.id JOIN delivery_run_runtimes t ON t.run_id=r.id JOIN entity_versions v ON v.kind='study' AND v.id=d.study_id AND v.revision=d.design_revision JOIN entities e ON e.kind=v.kind AND e.id=v.id JOIN metadata w ON w.key='workspace_id' WHERE r.id=NEW.run_id AND r.deployment_id=NEW.deployment_id AND r.study_id=d.study_id AND r.origin=d.origin AND d.study_id=NEW.study_id AND d.project_id=NEW.project_id AND v.project_id=d.project_id AND e.project_id=d.project_id AND d.design_revision=NEW.study_revision AND w.value=NEW.workspace_id AND r.allocation_index=NEW.allocation_index AND r.protocol_hash=NEW.source_protocol_sha256 AND length(CAST(r.protocol_json AS BLOB))=NEW.source_protocol_bytes AND v.body_hash=NEW.study_raw_sha256 AND length(CAST(v.body_json AS BLOB))=NEW.study_raw_bytes AND length(CAST(d.design_json AS BLOB))=NEW.release_raw_bytes AND f.profile=NEW.profile AND f.renderer_id=NEW.renderer_id AND f.runtime_manifest_hash=NEW.runtime_manifest_hash AND t.deployment_id=d.id AND t.manifest_hash=NEW.runtime_manifest_hash) BEGIN SELECT RAISE(ABORT,'Assigned presentation differs from its original source'); END",
      "CREATE TRIGGER IF NOT EXISTS delivery_view_receipt_match BEFORE INSERT ON delivery_view_start_receipts WHEN NOT EXISTS (SELECT 1 FROM delivery_runs r WHERE r.id=NEW.run_id AND r.deployment_id=NEW.deployment_id AND r.client_id=NEW.client_id) BEGIN SELECT RAISE(ABORT,'Start receipt differs from its participant'); END"
    )
    for (statement in sql) DBI::dbExecute(store$con, statement)
    for (table in c("delivery_view_releases", "delivery_run_presentations", "delivery_view_start_receipts")) {
      for (operation in c("UPDATE", "DELETE")) DBI::dbExecute(store$con, paste0(
        "CREATE TRIGGER IF NOT EXISTS ", table, "_no_", tolower(operation), " BEFORE ", operation,
        " ON ", table, " BEGIN SELECT RAISE(ABORT,'Assigned participant bindings are immutable'); END"))
    }
    invisible(TRUE)
  })
}

# Explicit metadata columns only. Credential rejection precedes source/body fetch.
.brohn_pvds_release_meta <- function(store, token = NULL, id = NULL, registered = TRUE) {
  .brohn_pvds_tables(store)
  where <- if (is.null(token)) "d.id=?" else "c.token_hash=?"
  value <- if (is.null(token)) id else .brohn_delivery_hash(token)
  m <- .brohn_pvds_one(.brohn_pvds_q(store, paste(
    "SELECT d.id AS deployment_id,d.study_id,d.project_id,d.origin,d.status,d.quota,d.alias_required,",
    "d.design_revision,d.design_hash,v.body_hash AS study_hash,e.project_id AS owner_project,",
    "c.token_hash AS release_credential,t.manifest_hash,",
    "length(CAST(d.design_json AS BLOB)) AS release_bytes,length(CAST(v.body_json AS BLOB)) AS study_bytes,",
    "length(CAST(t.manifest_json AS BLOB)) AS runtime_bytes",
    "FROM delivery_deployments d JOIN delivery_deployment_credentials c ON c.deployment_id=d.id",
    "JOIN entity_versions v ON v.kind='study' AND v.id=d.study_id AND v.revision=d.design_revision AND v.project_id=d.project_id",
    "JOIN entities e ON e.kind=v.kind AND e.id=v.id AND e.project_id=d.project_id",
    "JOIN delivery_runtimes t ON t.deployment_id=d.id WHERE", where), list(value)),
    "This released participant source is unavailable.", "unauthorized", 403L)
  brohn_hosted_require_project(store, m$project_id)
  for (name in c("release_bytes", "study_bytes", "runtime_bytes")) .brohn_pvds_size(m[[name]])
  .brohn_pvds_require(all(vapply(m[c("deployment_id", "study_id", "project_id")], brohn_valid_id, logical(1))) &&
    .brohn_pvds_hash(m$study_hash) && .brohn_pvds_hash(m$design_hash) && .brohn_pvds_hash(m$manifest_hash) &&
    brohn_number(m$design_revision, 1, .Machine$integer.max, TRUE) &&
    brohn_number(m$quota, 1, 1000000L, TRUE) && brohn_number(m$alias_required, 0, 1, TRUE) &&
    m$status %in% c("open", "paused", "closed") && m$origin %in% c("sample", "pilot", "live"),
    "Released source metadata is invalid.")
  audit <- .brohn_pvds_one(.brohn_pvds_q(store,
    "SELECT sequence,length(CAST(detail_json AS BLOB)) AS bytes FROM audit_log WHERE action='deployment.runtime_pinned' AND target=?", list(m$deployment_id)),
    "The participant runtime has no unique publication record.")
  .brohn_pvds_size(audit$bytes)
  m$audit_id <- audit$sequence; m$audit_bytes <- audit$bytes; m$workspace_id <- store$workspace_id
  r <- .brohn_pvds_registration()
  .brohn_pvds_require(identical(r$runtime_manifest_hash, m$manifest_hash),
    "The release requires its registered assigned-view renderer.", "renderer_unavailable", 503L)
  if (registered) {
    f <- .brohn_pvds_one(.brohn_pvds_q(store,
      "SELECT profile,renderer_id,runtime_manifest_hash FROM delivery_view_releases WHERE deployment_id=?", list(m$deployment_id)),
      "This release has no assigned-view registration.", "profile_unavailable", 503L)
    .brohn_pvds_require(.brohn_ph_equal(f, r), "The saved assigned-view renderer registration changed.")
  }
  m$registration <- r
  m
}
.brohn_pvds_release_bodies <- function(store, m) {
  row <- .brohn_pvds_one(.brohn_pvds_q(store, paste(
    "SELECT CAST(d.design_json AS BLOB) AS release,CAST(v.body_json AS BLOB) AS study,",
    "CAST(t.manifest_json AS BLOB) AS runtime,CAST(a.detail_json AS BLOB) AS audit",
    "FROM delivery_deployments d JOIN entity_versions v ON v.kind='study' AND v.id=d.study_id AND v.revision=d.design_revision",
    "JOIN delivery_runtimes t ON t.deployment_id=d.id JOIN audit_log a ON a.sequence=?",
    "WHERE d.id=? AND length(CAST(d.design_json AS BLOB))=? AND length(CAST(v.body_json AS BLOB))=?",
    "AND length(CAST(t.manifest_json AS BLOB))=? AND length(CAST(a.detail_json AS BLOB))=?"),
    list(m$audit_id, m$deployment_id, m$release_bytes, m$study_bytes, m$runtime_bytes, m$audit_bytes)),
    "The released source became unavailable.")
  sizes <- vapply(m[c("release_bytes", "study_bytes", "runtime_bytes", "audit_bytes")], as.numeric, numeric(1))
  .brohn_pvds_require(all(vapply(row, is.raw, logical(1))) && identical(as.numeric(lengths(row)), unname(sizes)),
    "Released source byte lengths disagree.")
  row
}
.brohn_pvds_release_integrity <- function(snapshot, validate_design = FALSE) {
  m <- snapshot$metadata; b <- snapshot$bodies
  .brohn_pvds_require(identical(.brohn_pvds_sha(b$study), m$study_hash) &&
    identical(.brohn_pvds_sha(b$runtime), m$manifest_hash), "An original source failed its retained byte hash.")
  release <- .brohn_pvds_decode(b$release); study <- .brohn_pvds_decode(b$study)
  .brohn_pvds_require(.brohn_ph_equal(release, study) && identical(release$id, m$study_id) &&
    identical(release$project_id, m$project_id) && identical(brohn_hash(release), m$design_hash),
    "The released design differs from its original study revision.")
  runtime <- .brohn_pvds_decode(b$runtime)
  .brohn_runner_manifest(runtime, m$manifest_hash)
  .brohn_runner_expected_match(data.frame(detail_json = .brohn_pvds_text(b$audit)), m$manifest_hash, length(runtime$files))
  if (validate_design) brohn_validate_variant_design(release, publish = TRUE)
  release
}
.brohn_pvds_release_pin <- function(m) m[setdiff(names(m), c("status", "quota", "alias_required"))]
.brohn_pvds_release_equal <- function(store, old, current) {
  .brohn_pvds_require(identical(.brohn_pvds_release_pin(old$metadata), .brohn_pvds_release_pin(current)),
    "The released source changed during participant preparation.", "source_changed")
  # Exact SQL byte equality, not a digest-only claim. This does not hydrate the
  # source or run a complete model validator under the short writer transaction.
  n <- .brohn_pvds_q(store, paste(
    "SELECT count(*) AS n FROM delivery_deployments d",
    "JOIN entity_versions v ON v.kind='study' AND v.id=d.study_id AND v.revision=d.design_revision",
    "JOIN delivery_runtimes t ON t.deployment_id=d.id JOIN audit_log a ON a.sequence=?",
    "WHERE d.id=? AND CAST(d.design_json AS BLOB)=? AND CAST(v.body_json AS BLOB)=?",
    "AND CAST(t.manifest_json AS BLOB)=? AND CAST(a.detail_json AS BLOB)=?"),
    list(current$audit_id, current$deployment_id, list(old$bodies$release), list(old$bodies$study),
      list(old$bodies$runtime), list(old$bodies$audit)))$n[[1L]]
  .brohn_pvds_require(n == 1L, "The original release bytes changed during preparation.", "source_changed")
}
brohn_register_participant_view_release <- function(store, deployment_id) {
  .brohn_pvds_require(brohn_valid_id(deployment_id), "Choose an original release.", "invalid_request", 400L)
  .brohn_pvds_require(!isTRUE(store$hosted_participant), "Only a researcher can register a new release.", "unauthorized", 403L)
  original <- .brohn_pvds_readonly(store, function() {
    m <- .brohn_pvds_release_meta(store, id = deployment_id, registered = FALSE)
    list(metadata = m, bodies = .brohn_pvds_release_bodies(store, m))
  })
  .brohn_pvds_release_integrity(original, validate_design = TRUE)
  .brohn_store_tx(store, function() {
    m <- .brohn_pvds_release_meta(store, id = deployment_id, registered = FALSE)
    .brohn_pvds_release_equal(store, original, m)
    old <- .brohn_pvds_q(store, "SELECT profile,renderer_id,runtime_manifest_hash FROM delivery_view_releases WHERE deployment_id=?", list(deployment_id))
    if (nrow(old)) {
      .brohn_pvds_require(.brohn_ph_equal(.brohn_pvds_one(old, "Invalid release registration."), m$registration), "The release registration differs.")
      return(invisible(m$registration))
    }
    .brohn_pvds_require(.brohn_pvds_q(store, "SELECT count(*) AS n FROM delivery_runs WHERE deployment_id=?", list(deployment_id))$n[[1L]] == 0L,
      "An existing participant release cannot acquire a new presentation profile.")
    DBI::dbExecute(store$con, "INSERT INTO delivery_view_releases VALUES (?,?,?,?,?)",
      params = c(list(deployment_id), unname(m$registration), list(brohn_now())))
    .brohn_store_audit(store, "deployment.assigned_view_registered", deployment_id, m$registration)
    invisible(m$registration)
  })
}

.brohn_pvds_run_snapshot <- function(store, public_run_id, secret) .brohn_pvds_readonly(store, function() {
  .brohn_pvds_tables(store)
  r <- .brohn_pvds_one(.brohn_pvds_q(store, paste(
    "SELECT r.id AS run_id,r.deployment_id,r.study_id,r.origin,r.client_id,r.start_hash,r.protocol_hash,",
    "r.allocation_index,r.completion_status,r.transfer_status,r.acked_sequence,r.participant_alias,r.participant_alias_supplied,",
    "c.token_hash AS run_credential,length(CAST(r.protocol_json AS BLOB)) AS protocol_bytes",
    "FROM delivery_runs r JOIN delivery_run_credentials c ON c.run_id=r.id",
    "JOIN delivery_run_presentations p ON p.run_id=r.id WHERE p.public_run_id=? AND c.token_hash=?"),
    list(public_run_id, .brohn_delivery_hash(secret))), "Run access was not accepted.", "unauthorized", 401L)
  .brohn_pvds_hosted_run(store, r$run_id, r$deployment_id)
  .brohn_pvds_size(r$protocol_bytes)
  .brohn_pvds_require(brohn_number(r$allocation_index, 1, 1e9, TRUE) && brohn_number(r$acked_sequence, 0, 10000000, TRUE) &&
    r$completion_status %in% c("in_progress", "completed", "withdrawn", "interrupted") && r$transfer_status %in% c("receiving", "saved"),
    "The current participant run metadata is invalid.")
  m <- .brohn_pvds_release_meta(store, id = r$deployment_id)
  .brohn_pvds_require(identical(r$study_id, m$study_id) && identical(r$origin, m$origin), "The run belongs to another released source.")
  t <- .brohn_pvds_one(.brohn_pvds_q(store, "SELECT deployment_id,manifest_hash FROM delivery_run_runtimes WHERE run_id=?", list(r$run_id)),
    "The run has no original runtime assignment.")
  .brohn_pvds_require(identical(t$deployment_id, m$deployment_id) && identical(t$manifest_hash, m$manifest_hash),
    "The participant runtime assignment changed.")
  p <- .brohn_pvds_one(.brohn_pvds_q(store, paste(
    "SELECT run_id,public_run_id,deployment_id,workspace_id,study_id,project_id,study_revision,allocation_index,",
    "source_protocol_sha256,source_protocol_bytes,release_raw_sha256,release_raw_bytes,study_raw_sha256,study_raw_bytes,",
    "profile,renderer_id,runtime_manifest_hash,codec,view_sha256,view_bytes,map_sha256,map_bytes,created_at,",
    "typeof(view_blob) AS view_type,length(view_blob) AS view_length,typeof(map_blob) AS map_type,length(map_blob) AS map_length",
    "FROM delivery_run_presentations WHERE run_id=?"), list(r$run_id)), "The assigned presentation is missing.")
  for (name in c("source_protocol_bytes", "release_raw_bytes", "study_raw_bytes", "view_bytes", "map_bytes")) .brohn_pvds_size(p[[name]])
  .brohn_pvds_require(identical(p$view_type, "blob") && identical(p$map_type, "blob") &&
    p$view_length == p$view_bytes && p$map_length == p$map_bytes, "Stored presentation BLOB metadata disagrees.")
  receipt <- .brohn_pvds_one(.brohn_pvds_q(store, paste(
    "SELECT deployment_id,operation_id,run_id,client_id,request_codec,request_sha256,request_bytes,outcome,",
    "initial_response_sha256,initial_response_bytes,typeof(request_blob) AS type,length(request_blob) AS bytes",
    "FROM delivery_view_start_receipts WHERE run_id=? AND outcome='created'"), list(r$run_id)),
    "The original creation receipt is missing.")
  .brohn_pvds_size(receipt$request_bytes, .brohn_pvds_http_limit)
  .brohn_pvds_size(receipt$initial_response_bytes, .brohn_pvds_http_limit)
  .brohn_pvds_require(identical(receipt$type, "blob") && receipt$bytes == receipt$request_bytes &&
    identical(receipt$deployment_id, m$deployment_id) && identical(receipt$client_id, r$client_id) &&
    identical(receipt$request_codec, "brohn-participant-request-json/0.1") &&
    .brohn_pvds_hash(receipt$request_sha256) && .brohn_pvds_hash(receipt$initial_response_sha256),
    "The original creation receipt metadata disagrees.")
  b <- .brohn_pvds_release_bodies(store, m)
  raw <- .brohn_pvds_one(.brohn_pvds_q(store, paste(
    "SELECT CAST(r.protocol_json AS BLOB) AS protocol,p.view_blob AS view,p.map_blob AS map FROM delivery_runs r",
    "JOIN delivery_run_presentations p ON p.run_id=r.id WHERE r.id=? AND length(CAST(r.protocol_json AS BLOB))=?",
    "AND length(p.view_blob)=? AND length(p.map_blob)=?"), list(r$run_id, r$protocol_bytes, p$view_bytes, p$map_bytes)),
    "The stored presentation became unavailable.")
  .brohn_pvds_require(all(vapply(raw, is.raw, logical(1))) && identical(as.numeric(lengths(raw)),
    as.numeric(c(r$protocol_bytes, p$view_bytes, p$map_bytes))), "Presentation body lengths disagree.")
  request <- .brohn_pvds_one(.brohn_pvds_q(store,
    "SELECT request_blob AS request FROM delivery_view_start_receipts WHERE run_id=? AND outcome='created' AND length(request_blob)=?",
    list(r$run_id, receipt$request_bytes)), "The original creation request became unavailable.")
  .brohn_pvds_require(is.raw(request$request) && length(request$request) == receipt$request_bytes,
    "The original creation request length disagrees.")
  list(metadata = m, run = r, presentation = p, receipt = receipt, bodies = c(b, raw, request))
})
.brohn_pvds_run_integrity <- function(s) {
  m <- s$metadata; r <- s$run; p <- s$presentation; b <- s$bodies
  expected <- list(run_id = r$run_id, deployment_id = m$deployment_id, workspace_id = m$workspace_id,
    study_id = m$study_id, project_id = m$project_id, study_revision = m$design_revision, allocation_index = r$allocation_index,
    source_protocol_sha256 = r$protocol_hash, source_protocol_bytes = r$protocol_bytes,
    release_raw_sha256 = .brohn_pvds_sha(b$release), release_raw_bytes = length(b$release),
    study_raw_sha256 = m$study_hash, study_raw_bytes = length(b$study),
    profile = m$registration$profile, renderer_id = m$registration$renderer_id, runtime_manifest_hash = m$manifest_hash,
    codec = "brohn-participant-json-bytes/0.1", view_sha256 = .brohn_pvds_sha(b$view), view_bytes = length(b$view),
    map_sha256 = .brohn_pvds_sha(b$map), map_bytes = length(b$map))
  .brohn_pvds_require(.brohn_ph_equal(p[names(expected)], expected) &&
    identical(.brohn_pvds_sha(b$protocol), r$protocol_hash) && identical(.brohn_pvds_sha(b$study), m$study_hash) &&
    identical(.brohn_pvds_sha(b$request), s$receipt$request_sha256),
    "The original participant binding failed byte or owner verification.")
  .brohn_pvds_require(.brohn_pvc_key(p$public_run_id, "pvu"), "Stored public run key is invalid.")
  invisible(TRUE)
}
.brohn_pvds_run_pin <- function(r) r[setdiff(names(r), c("completion_status", "transfer_status", "acked_sequence"))]
.brohn_pvds_document <- function(s, name) list(codec = s$presentation$codec,
  json = .brohn_pvds_text(s$bodies[[name]]), bytes = length(s$bodies[[name]]), sha256 = s$presentation[[paste0(name, "_sha256")]])
.brohn_pvds_admit <- function(s, store) {
  .brohn_pvds_run_integrity(s)
  .brohn_pvds_require(identical(s$presentation$workspace_id, store$workspace_id), "The presentation belongs to another workspace.")
  release <- .brohn_pvds_release_integrity(s)
  request <- .brohn_pvds_start_request(s$bodies$request)
  .brohn_pvds_require(identical(request$request$client_id, s$run$client_id) && identical(request$start_hash, s$run$start_hash) &&
    identical(request$request$operation_id, s$receipt$operation_id) &&
    (!isTRUE(release$consent$required) || isTRUE(request$request$consented)), "The original start receipt differs from its source participant.")
  protocol <- .brohn_pvds_decode(s$bodies$protocol)
  context <- brohn_participant_view_context(protocol, s$run$protocol_hash,
    .brohn_pvds_document(s, "view"), .brohn_pvds_document(s, "map"))
  .brohn_pvds_require(.brohn_ph_equal(protocol$design, release) && identical(protocol$design_hash, s$metadata$design_hash) &&
    .brohn_ph_equal(protocol$allocation_index, s$run$allocation_index) &&
    identical(context$binding()$public_run_id, s$presentation$public_run_id) &&
    .brohn_ph_equal(context$binding()$renderer_identity, .brohn_pvds_renderer(s$metadata$registration)),
    "The admitted presentation differs from its complete original release or assignment.")
  context
}
.brohn_pvds_handle <- function(store, original, context, secret, outcome) {
  root <- normalizePath(store$root, winslash = "/", mustWork = TRUE); con <- store$con; workspace <- store$workspace_id
  closed <- FALSE
  recheck <- function() {
    .brohn_pvds_require(!closed, "This participant presentation handle is closed.", "closed")
    .brohn_pvds_require(identical(con, store$con) && identical(workspace, store$workspace_id) &&
      identical(root, normalizePath(store$root, winslash = "/", mustWork = TRUE)), "The open participant workspace changed.")
    now <- .brohn_pvds_run_snapshot(store, original$presentation$public_run_id, secret)
    .brohn_pvds_run_integrity(now)
    .brohn_pvds_require(identical(now$bodies, original$bodies) && identical(now$presentation, original$presentation) && identical(now$receipt, original$receipt) &&
      identical(.brohn_pvds_release_pin(now$metadata), .brohn_pvds_release_pin(original$metadata)) &&
      identical(.brohn_pvds_run_pin(now$run), .brohn_pvds_run_pin(original$run)),
      "The committed participant binding changed. Reopen the original session.", "source_changed")
    now
  }
  recheck()
  h <- new.env(parent = emptyenv())
  h$schema <- "participant-view-store-handle/0.1"; h$outcome <- outcome
  h$binding <- context$binding()
  h$read <- function() {
    now <- recheck()
    list(schema = "participant-view-store-internal/0.1", context = context, binding = context$binding(),
      source = list(metadata = now$metadata, presentation = now$presentation, receipt = now$receipt, raw = original$bodies),
      run = now$run, access_token = secret, origin = now$metadata$origin, release_status = now$metadata$status)
  }
  h$current <- function() { recheck(); invisible(TRUE) }
  h$close <- function() { closed <<- TRUE; invisible(TRUE) }
  class(h) <- "brohn_participant_view_store_handle"
  lockEnvironment(h, bindings = TRUE)
  h
}
brohn_open_participant_view <- function(store, public_run_id, access_token) {
  .brohn_pvds_require(.brohn_pvc_key(public_run_id, "pvu") && brohn_text(access_token, 128L),
    "Run access is required.", "unauthorized", 401L)
  s <- .brohn_pvds_run_snapshot(store, public_run_id, access_token)
  context <- .brohn_pvds_admit(s, store)
  .brohn_pvds_handle(store, s, context, access_token, "existing")
}

# Internal size admission only: never called by a committed retry/current open.
.brohn_pvds_initial_response <- function(context, secret, origin, release_status) {
  protocol <- context$protocol; revision <- context$revision_context
  state <- .brohn_delivery_replay(protocol, list(), revision)
  resume <- brohn_project_participant_forward_resume(context,
    .brohn_delivery_resume(state, protocol, revision, 0L))
  map <- context$projection$private_map; doc <- context$view_document
  resources <- setNames(lapply(map$resources, function(r) paste0("/api/view/resources/", map$public_run_id, "/", r$key)),
    vapply(map$resources, function(r) r$key, character(1)))
  body <- list(schema = "participant-view-session/0.1", run_id = map$public_run_id, access_token = secret,
    view_json = doc$json, binding = list(schema = "participant-view-binding/0.1", run_id = map$public_run_id,
      source_protocol_hash = context$source_protocol_hash, renderer_identity = map$renderer_identity,
      view_codec = doc$codec, view_bytes = doc$bytes, view_hash = doc$sha256), resources = resources,
    expected_sequence = 1L, completion_status = "in_progress", resume = resume, origin = origin,
    release_status = release_status, researcher_resolution = NULL)
  brohn_participant_json_bytes(body, maximum_bytes = .brohn_pvds_http_limit)
}
.brohn_pvds_start_request <- function(request_raw) {
  # Closed start object = one root + at most four scalar values. This derived
  # bound admits every valid start without changing the generic codec profile.
  received <- brohn_participant_received_bytes(request_raw, maximum_nodes = 5L)
  request <- received$value
  brohn_fields(request, c("consented", "client_id", "operation_id"), "participant_alias", "Assigned-view start")
  .brohn_pvds_require(is.logical(request$consented) && length(request$consented) == 1L && !is.na(request$consented),
    "The consent choice must be explicit.", "consent_required", 403L)
  .brohn_pvds_require(brohn_text(request$client_id, 128L) && brohn_text(request$operation_id, 128L),
    "Client and operation identities are required.", "invalid_request", 400L)
  alias <- brohn_default(.brohn_pvds_get(request, "participant_alias"), "")
  .brohn_pvds_require(brohn_text(alias, 200L, TRUE), "Participant alias must be short text.", "invalid_request", 400L)
  list(received = received, request = request, alias = alias,
    start_hash = .brohn_delivery_hash(.brohn_store_json(list(client_id = request$client_id,
      consented = request$consented, participant_alias = alias))))
}
.brohn_pvds_prior <- function(store, deployment_id, input) {
  op <- .brohn_pvds_q(store, paste(
    "SELECT run_id,client_id,request_codec,request_sha256,request_bytes,typeof(request_blob) AS type,length(request_blob) AS bytes",
    "FROM delivery_view_start_receipts WHERE deployment_id=? AND operation_id=?"),
    list(deployment_id, input$request$operation_id))
  prior_run <- NULL
  if (nrow(op)) {
    o <- .brohn_pvds_one(op, "Start receipt is ambiguous.")
    .brohn_pvds_size(o$request_bytes, .brohn_pvds_http_limit)
    .brohn_pvds_require(identical(o$type, "blob") && o$bytes == o$request_bytes,
      "Start receipt BLOB metadata disagrees.")
    raw <- .brohn_pvds_q(store, "SELECT request_blob FROM delivery_view_start_receipts WHERE deployment_id=? AND operation_id=? AND length(request_blob)=?",
      list(deployment_id, input$request$operation_id, o$request_bytes))$request_blob[[1L]]
    .brohn_pvds_require(is.raw(raw) && identical(.brohn_pvds_sha(raw), o$request_sha256), "Start receipt byte integrity failed.")
    .brohn_pvds_require(identical(o$request_codec, input$received$codec) && identical(raw, input$received$raw) &&
      identical(o$client_id, input$request$client_id), "This operation identity was reused with different bytes.", "idempotency_conflict")
    prior_run <- o$run_id
  }
  old <- .brohn_pvds_q(store, "SELECT id,start_hash FROM delivery_runs WHERE deployment_id=? AND client_id=?",
    list(deployment_id, input$request$client_id))
  if (!nrow(old)) {
    .brohn_pvds_require(is.null(prior_run), "A committed start receipt has no original run.")
    return(NULL)
  }
  r <- .brohn_pvds_one(old, "Client mapping is ambiguous.")
  .brohn_pvds_require(identical(r$start_hash, input$start_hash), "This client belongs to a different start request.", "client_conflict")
  .brohn_pvds_require(is.null(prior_run) || identical(prior_run, r$id), "The operation and client name different runs.")
  p <- .brohn_pvds_one(.brohn_pvds_q(store, paste(
    "SELECT p.public_run_id,c.token FROM delivery_run_presentations p JOIN delivery_run_credentials c ON c.run_id=p.run_id WHERE p.run_id=?"), list(r$id)),
    "The original assigned presentation is missing; it cannot be regenerated.")
  .brohn_pvds_hosted_run(store, r$id, deployment_id)
  list(run_id = r$id, public_run_id = p$public_run_id, secret = p$token, has_receipt = !is.null(prior_run))
}
.brohn_pvds_enroll <- function(store, m, input) {
  .brohn_pvds_require(identical(m$status, "open"), "This study is not accepting new participants.", m$status)
  brohn_hosted_require_release(store, m$deployment_id, "enroll")
  .brohn_pvds_require(!as.logical(m$alias_required) || nzchar(trimws(input$alias)),
    "Your researcher requires a participant alias.", "alias_required", 422L)
  count <- .brohn_pvds_q(store, "SELECT count(*) AS n FROM delivery_runs WHERE deployment_id=?", list(m$deployment_id))$n[[1L]]
  .brohn_pvds_require(brohn_number(m$quota, 1, 1000000L, TRUE) && count < m$quota,
    "All places in this study have been allocated.", "quota_full")
  as.integer(count + 1L)
}
.brohn_pvds_receipt_insert <- function(store, m, input, run_id, outcome, response) {
  DBI::dbExecute(store$con, "INSERT INTO delivery_view_start_receipts VALUES (?,?,?,?,?,?,?,?,?,?,?,?)",
    params = list(m$deployment_id, input$request$operation_id, run_id, input$request$client_id,
      input$received$codec, input$received$sha256, input$received$bytes, list(input$received$raw), outcome,
      response$sha256, response$bytes, brohn_now()))
}
.brohn_pvds_existing_receipt <- function(store, release_token, input, snapshot, prior) {
  # Admit all retained source/view/map bytes before a new operation may acquire
  # an immutable receipt. This never recompiles or reprojects a committed run.
  handle <- brohn_open_participant_view(store, prior$public_run_id, prior$secret)
  success <- FALSE
  on.exit(if (!success) handle$close(), add = TRUE)
  original <- handle$read()
  .brohn_store_tx(store, function() {
    .brohn_pvds_require(!.brohn_store_execution_paused(store), "This restored workspace is paused.", "workspace_paused")
    m <- .brohn_pvds_release_meta(store, token = release_token)
    .brohn_pvds_release_equal(store, snapshot, m)
    current <- .brohn_pvds_prior(store, m$deployment_id, input)
    .brohn_pvds_require(!is.null(current) && identical(current$run_id, prior$run_id) &&
      identical(current$public_run_id, prior$public_run_id) && identical(current$secret, prior$secret),
      "The committed participant mapping changed.", "source_changed")
    # Exact byte AND metadata CAS before any write, including optional metadata
    # that immutable triggers normally protect. No BLOB hydration occurs here.
    pnames <- c("run_id", "public_run_id", "deployment_id", "workspace_id", "study_id", "project_id", "study_revision",
      "allocation_index", "source_protocol_sha256", "source_protocol_bytes", "release_raw_sha256", "release_raw_bytes",
      "study_raw_sha256", "study_raw_bytes", "profile", "renderer_id", "runtime_manifest_hash", "codec", "view_sha256",
      "view_bytes", "map_sha256", "map_bytes", "created_at")
    rnames <- c("deployment_id", "study_id", "origin", "client_id", "start_hash", "allocation_index", "participant_alias", "participant_alias_supplied")
    snames <- c("deployment_id", "operation_id", "run_id", "client_id", "request_codec", "request_sha256", "request_bytes",
      "outcome", "initial_response_sha256", "initial_response_bytes")
    n <- .brohn_pvds_q(store, paste(
      "SELECT count(*) AS n FROM delivery_runs r JOIN delivery_run_presentations p ON p.run_id=r.id",
      "JOIN delivery_run_credentials c ON c.run_id=r.id JOIN delivery_run_runtimes t ON t.run_id=r.id",
      "JOIN delivery_view_start_receipts s ON s.run_id=r.id AND s.outcome='created'",
      "WHERE r.id=? AND r.protocol_hash=? AND p.public_run_id=? AND CAST(r.protocol_json AS BLOB)=?",
      "AND p.view_blob=? AND p.map_blob=? AND c.token_hash=? AND c.token=? AND t.deployment_id=? AND t.manifest_hash=? AND",
      paste(paste0("p.", pnames, " IS ?"), collapse = " AND "), "AND",
      paste(paste0("r.", rnames, " IS ?"), collapse = " AND "), "AND",
      paste(paste0("s.", snames, " IS ?"), collapse = " AND "), "AND s.request_blob=?"),
      c(list(prior$run_id, original$binding$source_protocol_hash, prior$public_run_id, list(original$source$raw$protocol),
        list(original$source$raw$view), list(original$source$raw$map), .brohn_delivery_hash(prior$secret), prior$secret,
        m$deployment_id, m$manifest_hash), unname(original$source$presentation[pnames]), unname(original$run[rnames]),
        unname(original$source$receipt[snames]), list(list(original$source$raw$request))))$n[[1L]]
    .brohn_pvds_require(n == 1L, "The admitted participant bytes changed before receipt commit.", "source_changed")
    if (!current$has_receipt) {
      size <- .brohn_pvds_one(.brohn_pvds_q(store,
        "SELECT initial_response_sha256 AS sha256,initial_response_bytes AS bytes FROM delivery_view_start_receipts WHERE run_id=? AND outcome='created'", list(prior$run_id)),
        "The original creation-size receipt is missing.")
      .brohn_pvds_size(size$bytes, .brohn_pvds_http_limit)
      .brohn_pvds_require(.brohn_pvds_hash(size$sha256), "The original creation-size receipt is invalid.")
      .brohn_pvds_receipt_insert(store, m, input, prior$run_id, "existing", size)
    }
  })
  handle$current(); success <- TRUE; handle
}
brohn_start_participant_view <- function(store, release_token, request_raw) {
  .brohn_pvds_require(brohn_text(release_token, 128L), "Study access is required.", "unauthorized", 401L)
  .brohn_pvds_readonly(store, function() {
    .brohn_pvds_require(!.brohn_store_execution_paused(store), "This restored workspace is paused.", "workspace_paused")
    .brohn_pvds_release_meta(store, token = release_token)
    invisible(TRUE)
  })
  input <- .brohn_pvds_start_request(request_raw)
  snapshot <- .brohn_pvds_readonly(store, function() {
    .brohn_pvds_require(!.brohn_store_execution_paused(store), "This restored workspace is paused.", "workspace_paused")
    m <- .brohn_pvds_release_meta(store, token = release_token)
    prior <- .brohn_pvds_prior(store, m$deployment_id, input)
    list(metadata = m, bodies = .brohn_pvds_release_bodies(store, m), prior = prior,
      index = if (is.null(prior)) .brohn_pvds_enroll(store, m, input) else NULL)
  })
  design <- .brohn_pvds_release_integrity(snapshot, validate_design = is.null(snapshot$prior))
  .brohn_pvds_require(!isTRUE(design$consent$required) || isTRUE(input$request$consented),
    "Consent is required before a session can start.", "consent_required", 403L)
  if (!is.null(snapshot$prior)) return(.brohn_pvds_existing_receipt(store, release_token, input, snapshot, snapshot$prior))
  prepared <- NULL
  if (is.null(snapshot$prior)) {
    protocol <- brohn_compile_variant_design(design, snapshot$index)
    source_json <- .brohn_store_json(protocol); source_raw <- charToRaw(enc2utf8(source_json)); source_sha <- .brohn_pvds_sha(source_raw)
    .brohn_pvds_size(length(source_raw))
    projection <- brohn_project_participant_view(protocol, source_sha, .brohn_pvds_renderer(snapshot$metadata$registration))
    view <- brohn_participant_json_bytes(projection$view); map <- brohn_participant_json_bytes(projection$private_map)
    context <- brohn_participant_view_context(protocol, source_sha, view, map)
    secret <- brohn_token()
    response <- .brohn_pvds_initial_response(context, secret, snapshot$metadata$origin, snapshot$metadata$status)
    prepared <- list(protocol = protocol, source_json = source_json, source_raw = source_raw, source_sha = source_sha,
      context = context, view = view, map = map, secret = secret, response = list(sha256 = response$sha256, bytes = response$bytes))
  }
  committed <- .brohn_store_tx(store, function() {
    .brohn_pvds_ready(store)
    .brohn_pvds_require(!.brohn_store_execution_paused(store), "This restored workspace is paused.", "workspace_paused")
    m <- .brohn_pvds_release_meta(store, token = release_token)
    .brohn_pvds_release_equal(store, snapshot, m)
    old <- .brohn_pvds_prior(store, m$deployment_id, input)
    if (!is.null(old)) {
      # A winner may have committed while we prepared. Do not add a receipt for
      # its presentation until its actual bytes have had complete admission.
      return(c(old, list(outcome = "existing")))
    }
    .brohn_pvds_require(!is.null(prepared), "The original participant disappeared during admission.", "source_changed")
    index <- .brohn_pvds_enroll(store, m, input)
    .brohn_pvds_require(index == snapshot$index, "Another start used this allocation. Retry the same exact request.", "allocation_retry")
    id <- brohn_id("run"); stamp <- brohn_now(); supplied <- nzchar(trimws(input$alias))
    alias <- if (supplied) input$alias else paste0("Participant ", index)
    DBI::dbExecute(store$con, paste("INSERT INTO delivery_runs",
      "(id,deployment_id,study_id,origin,participant_alias,client_id,start_hash,protocol_json,protocol_hash,allocation_index,created_at,updated_at,participant_alias_supplied)",
      "VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)"), params = list(id, m$deployment_id, m$study_id, m$origin, alias,
      input$request$client_id, input$start_hash, prepared$source_json, prepared$source_sha, index, stamp, stamp, as.integer(supplied)))
    DBI::dbExecute(store$con, "INSERT INTO delivery_run_credentials VALUES (?,?,?)", params = list(id, prepared$secret, .brohn_delivery_hash(prepared$secret)))
    DBI::dbExecute(store$con, "INSERT INTO delivery_run_runtimes VALUES (?,?,?,?)", params = list(id, m$deployment_id, m$manifest_hash, stamp))
    brohn_hosted_register_run(store, id, m$deployment_id)
    p <- prepared; public_id <- p$context$binding()$public_run_id
    DBI::dbExecute(store$con, paste("INSERT INTO delivery_run_presentations VALUES (", paste(rep("?", 25L), collapse = ","), ")"),
      params = list(id, public_id, m$deployment_id, store$workspace_id, m$study_id, m$project_id, m$design_revision, index,
        p$source_sha, length(p$source_raw), .brohn_pvds_sha(snapshot$bodies$release), length(snapshot$bodies$release),
        m$study_hash, length(snapshot$bodies$study), m$registration$profile, m$registration$renderer_id, m$manifest_hash,
        p$view$codec, p$view$sha256, p$view$bytes, list(charToRaw(p$view$json)), p$map$sha256, p$map$bytes, list(charToRaw(p$map$json)), stamp))
    .brohn_store_audit(store, "participant.started", id, list(deployment_id = m$deployment_id, allocation_index = index,
      origin = m$origin, consented = input$request$consented, consent_required = design$consent$required,
      participant_alias_supplied = supplied, presentation_profile = m$registration$profile))
    .brohn_pvds_receipt_insert(store, m, input, id, "created", p$response)
    list(run_id = id, public_run_id = public_id, secret = p$secret, outcome = "created")
  })
  if (identical(committed$outcome, "existing")) return(.brohn_pvds_existing_receipt(store, release_token, input, snapshot, committed))
  original <- .brohn_pvds_run_snapshot(store, committed$public_run_id, committed$secret)
  .brohn_pvds_run_integrity(original)
  .brohn_pvds_require(identical(original$bodies[names(snapshot$bodies)], snapshot$bodies) &&
    identical(.brohn_pvds_release_pin(original$metadata), .brohn_pvds_release_pin(snapshot$metadata)) &&
    identical(original$bodies$request, input$received$raw) &&
    identical(original$bodies$protocol, prepared$source_raw) &&
    identical(original$bodies$view, charToRaw(prepared$view$json)) && identical(original$bodies$map, charToRaw(prepared$map$json)),
    "Committed presentation bytes differ from their admitted preparation.")
  .brohn_pvds_handle(store, original, prepared$context, committed$secret, "created")
}

# Narrow guards for a later explicit legacy integration patch. They do not
# initialize tables and do nothing for a genuinely unmarked legacy release.
.brohn_participant_view_require_legacy <- function(store, deployment_id = NULL, release_token = NULL, run_id = NULL) {
  if (!"delivery_view_releases" %in% DBI::dbListTables(store$con)) return(invisible(TRUE))
  rows <- if (!is.null(run_id)) .brohn_pvds_q(store,
    "SELECT f.deployment_id FROM delivery_view_releases f JOIN delivery_runs r ON r.deployment_id=f.deployment_id WHERE r.id=?", list(run_id)) else
    if (!is.null(release_token)) .brohn_pvds_q(store,
      "SELECT f.deployment_id FROM delivery_view_releases f JOIN delivery_deployment_credentials c ON c.deployment_id=f.deployment_id WHERE c.token_hash=?", list(.brohn_delivery_hash(release_token))) else
      .brohn_pvds_q(store, "SELECT deployment_id FROM delivery_view_releases WHERE deployment_id=?", list(deployment_id))
  .brohn_pvds_require(nrow(rows) == 0L, "This study requires its assigned participant presentation route.", "assigned_view_required", 409L)
  invisible(TRUE)
}
