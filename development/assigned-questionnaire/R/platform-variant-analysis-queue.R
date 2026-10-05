# Inactive explicit profile queues. These do not replace any public legacy queue.
.brohn_vra_key <- function(operation, request) {
  .brohn_vra_membership(operation, request)
  paste0("variant-analysis:0.1:", if (identical(operation, "analyse_run"))
    paste0("run:", request$run_id) else paste0("cohort:", brohn_hash(request)))
}
.brohn_vra_source_cas <- function(store, saved) {
  # The caller owns a real source reader which performed full saved admission.
  # This private SQL fence is also usable inside the queue's short transaction.
  m <- saved$source
  .brohn_epr_authority(store, m$project_id)
  brohn_require(identical(saved$workspace_id, store$workspace_id), "The variant source belongs to another workspace.")
  n <- DBI::dbGetQuery(store$con, paste(
    "SELECT count(*) AS n FROM delivery_runs r JOIN delivery_deployments d ON d.id=r.deployment_id",
    "JOIN entity_versions v ON v.kind='study' AND v.id=d.study_id AND v.revision=d.design_revision",
    "JOIN entities e ON e.kind=v.kind AND e.id=v.id",
    "WHERE r.id=? AND r.deployment_id=? AND r.study_id=? AND r.origin=? AND r.allocation_index=?",
    "AND r.protocol_hash=? AND d.project_id=? AND d.design_revision=? AND d.design_hash=? AND v.body_hash=?",
    "AND d.study_id=r.study_id AND r.origin=d.origin AND v.project_id=d.project_id AND e.project_id=d.project_id",
    "AND r.completion_status='completed' AND r.transfer_status='saved'",
    "AND CAST(r.protocol_json AS BLOB)=? AND CAST(d.design_json AS BLOB)=? AND CAST(v.body_json AS BLOB)=?"),
    params = c(unname(m[c("run_id", "deployment_id", "study_id", "origin", "allocation_index",
      "protocol_hash", "project_id", "design_revision", "design_hash", "study_body_hash")]),
      list(list(saved$protocol_bytes), list(saved$release_bytes), list(saved$study_bytes))))$n[[1L]]
  brohn_require(identical(as.numeric(n), 1), "The completed original variant source changed before queueing.")
  invisible(TRUE)
}
.brohn_vra_enqueue <- function(store, operation, request, retry_id = NULL) {
  .brohn_store_ready(store)
  brohn_require(!RSQLite::sqliteIsTransacting(store$con), "Admit original variant sources before opening the queue transaction.")
  members <- .brohn_vra_membership(operation, request)
  handles <- list(); on.exit(for (h in handles) h$close(), add = TRUE)
  sources <- list(); common <- NULL
  for (i in seq_along(members)) {
    scope <- .brohn_run_evidence_source_scope(store, members[[i]])
    .brohn_run_evidence_scope(scope)
    if (is.null(common)) common <- scope
    brohn_require(.brohn_ph_equal(common, scope), "Variant cohort members require one full original release, study, project and origin.")
    brohn_require((is.null(request$deployment_id) || identical(request$deployment_id, scope$deployment_id)) &&
      (is.null(request$study_id) || identical(request$study_id, scope$study_id)) &&
      (is.null(request$project_id) || identical(request$project_id, scope$project_id)), "Variant request scope differs from its originals.")
    h <- brohn_open_variant_run_protocol(store, members[[i]], scope$study_id, scope$project_id)
    handles[[i]] <- h; sources[[i]] <- h$read()
    .brohn_vra_source_cas(store, sources[[i]])
  }
  for (h in handles) h$current()
  brohn_store_batch(store, function() {
    for (s in sources) .brohn_vra_source_cas(store, s)
    key <- .brohn_vra_key(operation, request)
    if (!is.null(retry_id)) {
      old <- brohn_get_job(store, retry_id)
      brohn_require(!is.null(old) && old$status %in% c("failed", "cancelled") &&
        identical(old$operation, operation) && .brohn_ph_equal(old$request, request) &&
        identical(old$request$analysis_profile, .brohn_vra_profile), "Retry only the same failed or cancelled explicit variant request.")
      key <- paste0("variant-analysis:0.1:retry:", retry_id, ":", brohn_id("request"))
    }
    job <- brohn_enqueue_job(store, operation, request, key)
    if (!is.null(retry_id)) brohn_put_entity(store, "job_retry", brohn_id("retry"),
      list(source_job_id = retry_id, new_job_id = job$id, at = brohn_now(), policy = "same_frozen_inputs_new_attempt"))
    job
  })
}
brohn_queue_variant_run <- function(store, run_id) .brohn_vra_enqueue(store, "analyse_run",
  list(run_id = run_id, analysis_profile = .brohn_vra_profile))
brohn_queue_variant_cohort <- function(store, deployment_id, run_ids) .brohn_vra_enqueue(store, "analyse_cohort",
  list(deployment_id = deployment_id, run_ids = run_ids, recipe = "typed-explicit-responses/1.0.0-draft",
    analysis_profile = .brohn_vra_profile))
brohn_retry_variant_analysis <- function(store, job_id) {
  old <- brohn_get_job(store, job_id)
  brohn_require(!is.null(old) && old$status %in% c("failed", "cancelled") &&
    identical(old$request[["analysis_profile", exact = TRUE]], .brohn_vra_profile),
    "Choose a failed or cancelled explicit saved-variant analysis job; historical requests are not upgraded.")
  .brohn_vra_enqueue(store, old$operation, old$request, retry_id = job_id)
}

# This admission runs inside the separately named claimant's own transaction,
# before its unchanged attempt/token/lease/audit mutation. It does not upgrade a
# historical request or choose another queued row.
.brohn_vra_claim_admit <- function(store, rows) {
  decode_row <- function(row) {
    brohn_require(nrow(row) == 1L && is.character(row$request_json) &&
      !is.na(row$request_json[[1L]]) && nchar(row$request_json[[1L]], type = "bytes") <= 1024^2,
      "The explicit variant job request exceeds its original catalogue bound.")
    bytes <- charToRaw(enc2utf8(row$request_json[[1L]]))
    brohn_require(identical(.brohn_store_hash(bytes), row$request_hash[[1L]]),
      "The explicit variant job request failed its original raw hash.")
    request <- .brohn_vra_decode(bytes)
    members <- .brohn_vra_membership(row$operation[[1L]], request)
    list(request = request, members = members, operation = row$operation[[1L]])
  }
  decoded <- decode_row(rows)
  key <- rows$idempotency_key[[1L]]
  if (!identical(key, .brohn_vra_key(decoded$operation, decoded$request))) {
    parts <- if (brohn_text(key, 256)) strsplit(key, ":", fixed = TRUE)[[1L]] else character()
    brohn_require(length(parts) == 5L && identical(parts[1:3], c("variant-analysis", "0.1", "retry")) &&
      brohn_valid_id(parts[[4L]]) && nchar(parts[[5L]], type = "bytes") == 40L && grepl("^request-[a-f0-9]{32}$", parts[[5L]]),
      "The explicit variant job has no registered request identity.")
    prior <- DBI::dbGetQuery(store$con, "SELECT * FROM jobs WHERE id=?", params = list(parts[[4L]]))
    original <- decode_row(prior)
    brohn_require(prior$status[[1L]] %in% c("failed", "cancelled") &&
      identical(decoded$operation, original$operation) && .brohn_ph_equal(decoded$request, original$request),
      "A variant retry must retain the same failed or cancelled explicit request.")
  }
  common <- NULL
  for (id in decoded$members) {
    source <- .brohn_run_evidence_source_scope(store, id)
    .brohn_run_evidence_scope(source)
    .brohn_epr_authority(store, source$project_id)
    if (is.null(common)) common <- source
    brohn_require(.brohn_ph_equal(source, common) &&
      (is.null(decoded$request$study_id) || identical(decoded$request$study_id, source$study_id)) &&
      (is.null(decoded$request$project_id) || identical(decoded$request$project_id, source$project_id)) &&
      (is.null(decoded$request$deployment_id) || identical(decoded$request$deployment_id, source$deployment_id)),
      "The explicit variant job is outside its current original-source scope.")
  }
  invisible(TRUE)
}

# Private composition seam for the assigned finish owner. `original` is the
# closure-bound result of its real handle$read(), never request JSON. That owner
# retains its current authority/replay/transaction entry and owns handle close.
.brohn_vra_finish_queue <- function(store, original) {
  owned_con <- store$con; owned_workspace <- store$workspace_id
  owned_root <- normalizePath(store$root, winslash = "/", mustWork = TRUE)
  context <- original$context
  brohn_require(is.environment(context) && environmentIsLocked(context) &&
    identical(context$protocol$schema_version, "brohn-protocol/1.2.0") &&
    identical(context$source_protocol_hash, original$binding$source_protocol_hash),
    "The finish queue requires its actual admitted variant context.")
  # The original finish changes only these progress values before queueing a
  # completed run. Preserve every other source/credential/assignment pin.
  completed <- original
  completed$run$completion_status <- "completed"
  completed$run$transfer_status <- "saved"
  function(actual_store, operation, request, idempotency_key, prepared_id = NULL) {
    brohn_require(identical(actual_store$con, owned_con) && identical(store$con, owned_con) &&
      identical(actual_store$workspace_id, owned_workspace) && identical(store$workspace_id, owned_workspace) &&
      identical(normalizePath(actual_store$root, winslash = "/", mustWork = TRUE), owned_root) &&
      identical(normalizePath(store$root, winslash = "/", mustWork = TRUE), owned_root) &&
      RSQLite::sqliteIsTransacting(owned_con), "The variant finish queue lost its owned transaction.")
    brohn_require(identical(operation, "analyse_run") && is.null(prepared_id) &&
      .brohn_ph_equal(request, list(run_id = original$run$run_id)) &&
      identical(idempotency_key, paste0("analyse-run:", original$run$run_id)),
      "The original finish attempted a different analysis request.")
    .brohn_pvr_source_cas(store, completed)
    variant_request <- list(run_id = original$run$run_id, analysis_profile = .brohn_vra_profile)
    brohn_enqueue_job(store, operation, variant_request, .brohn_vra_key(operation, variant_request))
  }
}
