# Inactive operation-local publication composition. Original publication and
# native sealing functions remain unchanged. No request supplies this guard.
.brohn_vra_counter <- function(x) {
  brohn_require(is.numeric(x) && length(x) == 1L && !is.object(x) &&
    is.finite(x) && x >= 0 && x <= 2^53 - 2 && x == floor(x),
    "The variant publication database counter is unavailable.")
  as.numeric(x)
}
.brohn_vra_stamp <- function(con) list(
  data = .brohn_vra_counter(DBI::dbGetQuery(con, "PRAGMA main.data_version")[[1L]][[1L]]),
  own = .brohn_vra_counter(DBI::dbGetQuery(con, "SELECT total_changes()")[[1L]][[1L]]))
.brohn_vra_schema_pin <- function(con) list(
  user = DBI::dbGetQuery(con, "PRAGMA main.user_version"),
  main_version = DBI::dbGetQuery(con, "PRAGMA main.schema_version"),
  temp_version = DBI::dbGetQuery(con, "PRAGMA temp.schema_version"),
  main = DBI::dbGetQuery(con, "SELECT type,name,tbl_name,sql FROM main.sqlite_master ORDER BY type,name"),
  temp = DBI::dbGetQuery(con, "SELECT type,name,tbl_name,sql FROM temp.sqlite_master ORDER BY type,name"))
.brohn_vra_publication_guard <- function(store, job, input, scratch, timeout_seconds = 1900) {
  .brohn_store_ready(store)
  brohn_require(!RSQLite::sqliteIsTransacting(store$con),
    "Verify variant publication sources outside a catalogue transaction.")
  brohn_require(brohn_number(timeout_seconds, 1, 7200), "Variant publication needs its remaining declared time bound.")
  deadline <- .brohn_store_now() + timeout_seconds
  members <- .brohn_vra_membership(job$operation, job$request)
  evidence <- input$run_evidence
  brohn_require(identical(input$operation, job$operation) &&
    identical(evidence$schema, "brohn-variant-run-evidence-input/0.1") &&
    identical(evidence$workspace_id, store$workspace_id) && identical(evidence$job_id, job$id) &&
    .brohn_ph_equal(evidence$attempt, job$attempt) && .brohn_ph_equal(evidence$request, job$request) &&
    identical(evidence$request_hash, brohn_hash(job$request)) &&
    identical(evidence$binding_hash, .brohn_run_evidence_binding(input)) &&
    identical(members, lapply(evidence$runs, function(x) x$metadata$id)),
    "Variant publication differs from the original job or input manifest.")
  con <- store$con; workspace <- store$workspace_id
  root <- normalizePath(store$root, winslash = "/", mustWork = TRUE)
  original_renew <- brohn_renew_job
  schema <- .brohn_vra_schema_pin(con)
  brohn_require(identical(as.numeric(schema$user[[1L]][[1L]]), 1),
    "Variant publication requires the original workspace schema.")
  .brohn_vra_publication_schema_admit(schema)
  expected <- .brohn_vra_stamp(con)
  active <- TRUE; checked_sources <- FALSE; entered_commit <- FALSE; last_check <- -Inf
  heads <- list()
  authority <- function() {
    brohn_require(active && identical(store$con, con) && identical(store$workspace_id, workspace) &&
      identical(normalizePath(store$root, winslash = "/", mustWork = TRUE), root),
      "The variant publication lost its owned store.")
    brohn_require(.brohn_store_now() <= deadline, "Variant source verification or publication exceeded its declared time limit.")
    .brohn_epr_authority(store, input$project_id)
    .brohn_run_evidence_job(store, job)
    invisible(TRUE)
  }
  unchanged <- function() {
    authority()
    brohn_require(identical(.brohn_vra_stamp(con), expected) &&
      identical(.brohn_vra_schema_pin(con), schema),
      "Original variant sources or database schema changed before publication.")
    invisible(TRUE)
  }
  renew <- function(actual_store, id, worker, token, lease_seconds = 60) {
    brohn_require(identical(actual_store, store) && identical(id, job$id) &&
      identical(worker, job$worker) && identical(token, job$token) &&
      is.numeric(lease_seconds) && length(lease_seconds) == 1L && !is.object(lease_seconds) &&
      !is.na(lease_seconds) && lease_seconds == 60,
      "Only this original publication attempt may renew its normal lease.")
    unchanged()
    before <- DBI::dbGetQuery(con, "SELECT * FROM jobs WHERE id=?", params = list(id))
    audit_head <- DBI::dbGetQuery(con, "SELECT coalesce(max(sequence),0) AS last FROM audit_log")$last[[1L]]
    actor <- if (!is.null(store$hosted_context)) brohn_hosted_actor(store) else NULL
    before_time <- .brohn_store_now()
    result <- original_renew(actual_store, id, worker, token, lease_seconds)
    after_time <- .brohn_store_now()
    after <- DBI::dbGetQuery(con, "SELECT * FROM jobs WHERE id=?", params = list(id))
    added <- DBI::dbGetQuery(con, paste("SELECT sequence,occurred_at,action,target,detail_json FROM audit_log",
      "WHERE sequence>? ORDER BY sequence LIMIT 2"), params = list(audit_head))
    stamp <- .brohn_vra_stamp(con)
    brohn_require(nrow(before) == 1L && nrow(after) == 1L &&
      identical(before[setdiff(names(before), c("lease_until", "updated_at"))],
        after[setdiff(names(after), c("lease_until", "updated_at"))]) &&
      after$lease_until[[1L]] >= max(before$lease_until[[1L]], before_time + 60) &&
      after$lease_until[[1L]] <= max(before$lease_until[[1L]], after_time + 60) &&
      identical(result, brohn_get_job(store, id)),
      "Lease renewal changed another owned job field.")
    detail <- list(attempt = job$attempt, worker = worker, lease_until = after$lease_until[[1L]])
    if (!is.null(store$hosted_context)) {
      brohn_require(identical(actor, brohn_hosted_actor(store)), "Researcher authority changed during renewal.")
      detail$actor <- actor
    }
    brohn_require(nrow(added) == 1L && identical(added$action[[1L]], "job.renewed") &&
      identical(added$target[[1L]], id) && identical(added$detail_json[[1L]], .brohn_store_json(detail)) &&
      brohn_text(added$occurred_at[[1L]], 128) && brohn_text(after$updated_at[[1L]], 128) &&
      identical(stamp$data, expected$data) && identical(stamp$own, expected$own + 2) &&
      identical(.brohn_vra_schema_pin(con), schema),
      "Lease renewal made an unexpected database, audit or schema change.")
    # Never adopt an arbitrary observed counter. These are exactly the original
    # jobs UPDATE and job.renewed audit INSERT; an extra trigger write refuses.
    expected$own <<- expected$own + 2
    unchanged()
    result
  }
  pulse <- function(force = FALSE) {
    now <- .brohn_store_now()
    if (force || now - last_check >= 2) {
      unchanged()
      current <- brohn_get_job(store, job$id)
      if (current$lease_until - now < 45) renew(store, job$id, job$worker, job$token, 60)
      last_check <<- now
    }
    invisible(TRUE)
  }
  head <- function(id) DBI::dbGetQuery(con, paste(
    "SELECT id,study_id,deployment_id,origin,participant_alias,participant_alias_supplied,allocation_index,",
    "completion_status,transfer_status,acked_sequence,created_at,updated_at,finalized_at",
    "FROM delivery_runs WHERE id=?"), params = list(id))
  source_head <- function(item) {
    row <- head(item$metadata$id)
    brohn_require(nrow(row) == 1L, "The completed variant source is unavailable.")
    m <- lapply(row, function(x) x[[1L]])
    m$run_id <- m$id; m$participant_alias_supplied <- as.logical(m$participant_alias_supplied)
    if (is.na(m$finalized_at)) m["finalized_at"] <- list(NULL)
    expected_metadata <- item$metadata[setdiff(names(item$metadata), c("design_revision", "design_hash"))]
    brohn_require(.brohn_ph_equal(m, expected_metadata) && identical(m$completion_status, "completed") &&
      identical(m$transfer_status, "saved"), "The completed variant source metadata changed.")
    row
  }
  verify_sources <- function() {
    brohn_require(!checked_sources && !entered_commit && !RSQLite::sqliteIsTransacting(con),
      "Verify each original variant publication only once outside the writer.")
    pulse(TRUE)
    for (i in seq_along(evidence$runs)) {
      item <- evidence$runs[[i]]; m <- item$original$source
      brohn_require(identical(m$project_id, input$project_id), "The original variant project changed.")
      heads[[i]] <<- source_head(item)
      snapshot <- .brohn_epr_snapshot(store, m$run_id, m$study_id, m$project_id)
      .brohn_epr_integrity(snapshot)
      brohn_require(.brohn_ph_equal(snapshot$metadata, m), "Original variant release or revision metadata changed.")
      for (kind in c("protocol", "release", "study")) {
        descriptor <- if (identical(kind, "protocol")) item$protocol else item$original[[kind]]
        path <- if (identical(kind, "protocol"))
          .brohn_run_evidence_path(scratch, descriptor$path, i, "protocol") else
          .brohn_vra_path(scratch, descriptor$path, i, kind)
        bytes <- snapshot$bodies[[kind]]
        brohn_require(length(bytes) == descriptor$bytes &&
          identical(.brohn_run_evidence_hash(bytes), descriptor$sha256) &&
          file.info(path)$size == descriptor$bytes &&
          identical(bytes, readBin(path, "raw", n = 16*1024^2 + 1L)),
          "Original variant bytes differ from the actual worker input.")
      }
      # The worker already admitted every original event and ending. Repeat the
      # entire raw chain here, without recompiling, decoding or hydrating it.
      sequence <- 0; bytes <- 0
      chain <- .brohn_run_evidence_seed(item$metadata, item$protocol$sha256)
      repeat {
        pulse()
        sizes <- DBI::dbGetQuery(con, paste("SELECT sequence,typeof(event_json) AS kind,length(CAST(event_json AS BLOB)) AS bytes",
          "FROM delivery_events WHERE run_id=? AND sequence>? ORDER BY sequence LIMIT 8"),
          params = list(m$run_id, sequence))
        if (!nrow(sizes)) break
        brohn_require(all(sizes$kind == "text") && all(!is.na(sizes$bytes) & sizes$bytes > 0 & sizes$bytes <= 4*1024^2),
          "An original event exceeds its source type or size bound.")
        page <- DBI::dbGetQuery(con, paste("SELECT sequence,event_id,event_hash,CAST(event_json AS BLOB) AS body",
          "FROM delivery_events WHERE run_id=? AND sequence>? ORDER BY sequence LIMIT 8"),
          params = list(m$run_id, sequence))
        brohn_require(identical(page$sequence, sizes$sequence), "The original journal page changed.")
        for (j in seq_len(nrow(page))) {
          sequence <- sequence + 1
          raw <- page$body[[j]]
          brohn_require(sequence <= 10000000 && page$sequence[[j]] == sequence && is.raw(raw) &&
            length(raw) == sizes$bytes[[j]] && brohn_text(page$event_id[[j]], 128) &&
            identical(.brohn_run_evidence_hash(raw), page$event_hash[[j]]),
            "The original variant journal sequence, identity or raw hash changed.")
          chain <- .brohn_run_evidence_chain(chain, sequence, page$event_id[[j]], page$event_hash[[j]], length(raw))
          bytes <- bytes + length(raw) + 1
        }
      }
      brohn_require(sequence == item$journal$event_count && sequence == item$journal$final_sequence &&
        bytes == item$journal$bytes && identical(chain, item$journal$rows_hash) &&
        identical(heads[[i]], source_head(item)), "The complete original journal changed before publication.")
      pulse()
    }
    unchanged(); checked_sources <<- TRUE; invisible(TRUE)
  }
  before_commit <- function() {
    brohn_require(checked_sources && !entered_commit && RSQLite::sqliteIsTransacting(con),
      "Publish only the checked original variant sources in the owned transaction.")
    unchanged()
    for (i in seq_along(evidence$runs)) brohn_require(identical(heads[[i]], source_head(evidence$runs[[i]])),
      "An original completed session changed before publication.")
    unchanged(); entered_commit <<- TRUE; invisible(TRUE)
  }
  close <- function() { active <<- FALSE; invisible(TRUE) }
  list(verify = verify_sources, renew = renew, before_commit = before_commit, close = close)
}
brohn_publish_variant_analysis <- function(store, job, input, result, scratch, result_path, timeout_seconds = 1900) {
  started <- .brohn_store_now()
  .brohn_vra_membership(job$operation, job$request)
  .brohn_vra_worker_output(result, .brohn_vra_worker_identity())
  guard <- .brohn_vra_publication_guard(store, job, input, scratch,
    timeout_seconds - (.brohn_store_now() - started))
  on.exit(guard$close(), add = TRUE)
  guard$verify()
  # Two function copies only. All bodies/formals, original public bindings,
  # original native sealer and commit code remain exact.
  publish <- brohn_publish_analysis_report
  prepare <- brohn_prepare_publication
  brohn_require(identical(environment(publish), environment(prepare)),
    "Load the original publication functions in one registered code environment.")
  scope <- new.env(parent = environment(publish))
  scope$brohn_renew_job <- guard$renew
  environment(prepare) <- scope
  scope$brohn_prepare_publication <- prepare
  environment(publish) <- scope
  lockEnvironment(scope, bindings = TRUE)
  remaining <- timeout_seconds - (.brohn_store_now() - started)
  brohn_require(remaining >= 1, "No time remains for original variant report publication.")
  publish(store, job, input, result, scratch, result_path,
    timeout_seconds = remaining, before_commit = guard$before_commit)
}
