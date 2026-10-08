# Inactive researcher-only saved-source dispatch. Load after variant queues.
# Existing queues, retry dispatch, worker and participant files remain exact.
.brohn_sma_scope <- function(store, run_id, study_id, project_id) {
  .brohn_store_ready(store)
  brohn_require(all(vapply(list(run_id, study_id, project_id), brohn_valid_id, logical(1))),
    "Choose a saved session in the open study.")
  scope <- .brohn_run_evidence_source_scope(store, run_id)
  .brohn_run_evidence_scope(scope)
  .brohn_epr_authority(store, scope$project_id)
  brohn_require(identical(scope$study_id, study_id) && identical(scope$project_id, project_id),
    "This saved session is outside the open study and project.")
  scope
}
.brohn_sma_source <- function(store, run_id, study_id, project_id) {
  scope <- .brohn_sma_scope(store, run_id, study_id, project_id)
  original <- .brohn_epr_snapshot(store, run_id, scope$study_id, scope$project_id)
  hashes <- .brohn_epr_integrity(original)
  protocol <- .brohn_epr_decode(original$bodies$protocol)
  schema <- protocol[["schema_version", exact = TRUE]]
  brohn_require(is.character(schema) && length(schema) == 1L && !is.na(schema) &&
      schema %in% c("brohn-protocol/1.0.0", "brohn-protocol/1.2.0"),
    "This saved protocol has no supported manual analysis route. Its original data are unchanged.")
  release <- .brohn_epr_decode(original$bodies$release)
  study <- .brohn_epr_decode(original$bodies$study)
  brohn_require(.brohn_ph_equal(protocol$design, release) && .brohn_ph_equal(release, study),
    "The original run, release and study revision contain different designs.")
  m <- original$metadata
  brohn_require(identical(m$run_id, run_id) && .brohn_ph_equal(m[names(scope)], scope),
    "The saved session changed release or source scope while this action was prepared.")
  brohn_require(identical(protocol$design$id, scope$study_id) &&
      identical(protocol$design$project_id, scope$project_id) &&
      identical(protocol$design_hash, m$design_hash) &&
      .brohn_ph_equal(protocol$allocation_index, m$allocation_index),
    "The saved protocol does not match its original source identities.")
  saved <- list(workspace_id = store$workspace_id, source = m, protocol = protocol,
    protocol_bytes = original$bodies$protocol, release_bytes = original$bodies$release,
    study_bytes = original$bodies$study, raw_sha256 = as.list(hashes))
  # This existing SQL fence has no schema dispatch: it checks original bytes,
  # researcher authority and completed/saved status for either admitted source.
  .brohn_vra_source_cas(store, saved)
  if (identical(schema, "brohn-protocol/1.0.0")) {
    row <- DBI::dbGetQuery(store$con, paste("SELECT id,study_id,deployment_id,origin,participant_alias,",
      "participant_alias_supplied,allocation_index,completion_status,transfer_status,acked_sequence,",
      "created_at,updated_at,finalized_at FROM delivery_runs WHERE id=?"), params = list(run_id))
    brohn_require(nrow(row) == 1L, "The original saved session is unavailable.")
    metadata <- lapply(row, function(column) column[[1L]])
    metadata$run_id <- metadata$id
    metadata$participant_alias_supplied <- as.logical(metadata$participant_alias_supplied)
    metadata$design_revision <- m$design_revision; metadata$design_hash <- m$design_hash
    .brohn_run_evidence_protocol(protocol, metadata, scope$project_id)
  }
  # The named queue performs full1.2 saved-table admission with its actual
  # original handles; the bound enqueue below also fences this earlier source.
  list(scope = scope, saved = saved, schema = schema)
}
.brohn_sma_legacy_row <- function(store, run_id) {
  key <- paste0("analyse-run:", run_id)
  lengths <- DBI::dbGetQuery(store$con,
    "SELECT length(CAST(request_json AS BLOB)) AS bytes FROM jobs WHERE idempotency_key=?",
    params = list(key))
  if (!nrow(lengths)) return(NULL)
  brohn_require(nrow(lengths) == 1L && brohn_number(lengths$bytes[[1L]], 1, 1024^2, TRUE),
    "The earlier analysis request is unavailable or exceeds its retained bound.")
  row <- DBI::dbGetQuery(store$con, "SELECT * FROM jobs WHERE idempotency_key=?", params = list(key))
  brohn_require(nrow(row) == 1L && identical(row$operation[[1L]], "analyse_run"),
    "The earlier analysis identity belongs to another operation.")
  bytes <- charToRaw(enc2utf8(row$request_json[[1L]]))
  brohn_require(identical(.brohn_store_hash(bytes), row$request_hash[[1L]]),
    "The earlier analysis request failed its original byte hash.")
  request <- .brohn_vra_decode(bytes)
  brohn_require(.brohn_ph_equal(request, list(run_id = run_id)),
    "The earlier analysis identity contains a different saved request.")
  row
}
.brohn_sma_row_value <- function(row) lapply(row, function(column) {
  value <- column[[1L]]
  if (length(value) == 1L && is.na(value)) NULL else value
})
.brohn_sma_recovery_id <- function(store, run_id) paste0("analysis-recovery-",
  brohn_hash(list(workspace_id = store$workspace_id, run_id = run_id)))
.brohn_sma_lineage <- function(store, source, old, job) {
  if (is.null(old) || !identical(old$status[[1L]], "failed")) return(NULL)
  brohn_require(RSQLite::sqliteIsTransacting(store$con), "Record recovery with its queued analysis.")
  m <- source$saved$source
  body <- list(schema = "brohn-saved-analysis-recovery/0.1",
    policy = "new_named_analysis_same_saved_run", workspace_id = store$workspace_id,
    run_id = m$run_id, study_id = m$study_id, project_id = m$project_id,
    source = m, source_sha256 = source$saved$raw_sha256,
    earlier_job = .brohn_sma_row_value(old), new_job_id = job$id,
    new_request = job$request, new_request_sha256 = brohn_hash(job$request),
    analysis_profile = .brohn_vra_profile)
  id <- .brohn_sma_recovery_id(store, m$run_id)
  head <- DBI::dbGetQuery(store$con,
    "SELECT project_id,revision FROM entities WHERE kind='analysis_recovery' AND id=?", params = list(id))
  prior <- brohn_get_entity(store, "analysis_recovery", id)
  if (nrow(head)) {
    brohn_require(nrow(head) == 1L && head$revision[[1L]] == 1L &&
        identical(head$project_id[[1L]], m$project_id) && !is.null(prior) &&
        identical(prior$revision, 1L) && identical(prior$project_id, m$project_id) &&
        .brohn_ph_equal(prior$body, body), "The saved analysis relationship changed. Review its history before continuing.")
    # Verify the original idempotency receipt too. A missing or conflicting
    # operation receipt must not turn a damaged relationship into healthy reuse.
    return(brohn_put_entity(store, "analysis_recovery", id, body, expected_revision = 0L,
      project_id = m$project_id, operation_id = paste0("saved-analysis-recovery:", id)))
  }
  brohn_require(is.null(prior) && DBI::dbGetQuery(store$con,
      "SELECT count(*) AS n FROM entity_versions WHERE kind='analysis_recovery' AND id=?", params = list(id))$n[[1L]] == 0L &&
      DBI::dbGetQuery(store$con, "SELECT count(*) AS n FROM entity_operations WHERE operation_id=?",
        params = list(paste0("saved-analysis-recovery:", id)))$n[[1L]] == 0L,
    "The saved analysis relationship has an incomplete history. Review it before continuing.")
  brohn_put_entity(store, "analysis_recovery", id, body, expected_revision = 0L,
    project_id = m$project_id, operation_id = paste0("saved-analysis-recovery:", id))
}
.brohn_sma_queue <- local({
  original_queue <- .brohn_vra_enqueue
  original_enqueue <- brohn_enqueue_job
  stopifnot(is.function(original_queue), is.function(original_enqueue))
  function(store, sources, operation, request, key, variant, old = NULL) {
    owned_con <- store$con; owned_workspace <- store$workspace_id
    owned_root <- normalizePath(store$root, winslash = "/", mustWork = TRUE)
    lineage <- NULL; reused <- FALSE
    enqueue <- function(actual_store, actual_operation, actual_request, idempotency_key, prepared_id = NULL) {
      brohn_require(identical(actual_store$con, owned_con) && identical(store$con, owned_con) &&
          identical(actual_store$workspace_id, owned_workspace) && identical(store$workspace_id, owned_workspace) &&
          identical(normalizePath(actual_store$root, winslash = "/", mustWork = TRUE), owned_root) &&
          identical(normalizePath(store$root, winslash = "/", mustWork = TRUE), owned_root) &&
          RSQLite::sqliteIsTransacting(owned_con) && identical(actual_operation, operation) &&
          .brohn_ph_equal(actual_request, request) && identical(idempotency_key, key) && is.null(prepared_id),
        "The saved analysis queue lost its original operation or transaction.")
      for (source in sources) .brohn_vra_source_cas(store, source$saved)
      if (variant && identical(operation, "analyse_run")) {
        current_old <- .brohn_sma_legacy_row(store, request$run_id)
        brohn_require(identical(current_old, old), "The earlier analysis changed while this action was prepared.")
      }
      reused <<- nrow(DBI::dbGetQuery(store$con, "SELECT id FROM jobs WHERE idempotency_key=?", params = list(key))) == 1L
      job <- original_enqueue(store, operation, request, key)
      if (variant && identical(operation, "analyse_run")) lineage <<- .brohn_sma_lineage(store, sources[[1L]], old, job)
      job
    }
    if (variant) {
      environment_bound_queue <- original_queue
      bindings <- new.env(parent = environment(original_queue))
      bindings$brohn_enqueue_job <- enqueue
      lockEnvironment(bindings, bindings = TRUE)
      environment(environment_bound_queue) <- bindings
      job <- environment_bound_queue(store, operation, request)
    } else job <- brohn_store_batch(store, function() enqueue(store, operation, request, key))
    list(schema = "brohn-saved-analysis-action/0.1", job = job, recovery = lineage, reused = reused,
      protocol_schema = sources[[1L]]$schema,
      run_ids = lapply(sources, function(source) source$saved$source$run_id))
  }
})
brohn_queue_saved_run <- function(store, run_id, study_id, project_id) {
  .brohn_store_ready(store)
  brohn_require(!RSQLite::sqliteIsTransacting(store$con), "Prepare a saved analysis outside another transaction.")
  source <- .brohn_sma_source(store, run_id, study_id, project_id)
  variant <- identical(source$schema, "brohn-protocol/1.2.0")
  request <- list(run_id = run_id)
  if (variant) request$analysis_profile <- .brohn_vra_profile
  key <- if (variant) .brohn_vra_key("analyse_run", request) else paste0("analyse-run:", run_id)
  old <- if (variant) .brohn_sma_legacy_row(store, run_id) else NULL
  brohn_require(is.null(old) || identical(old$status[[1L]], "failed"),
    "An earlier analysis of this session has not failed. Review that attempt in Activity before creating a different analysis.")
  .brohn_sma_queue(store, list(source), "analyse_run", request, key, variant, old)
}
brohn_queue_saved_cohort <- function(store, deployment_id, study_id, project_id) {
  .brohn_store_ready(store)
  brohn_require(all(vapply(list(deployment_id, study_id, project_id), brohn_valid_id, logical(1))) &&
      !RSQLite::sqliteIsTransacting(store$con), "Choose a saved release in the open study.")
  release <- DBI::dbGetQuery(store$con,
    "SELECT study_id,project_id FROM delivery_deployments WHERE id=?", params = list(deployment_id))
  brohn_require(nrow(release) == 1L, "Choose an available saved release.")
  .brohn_epr_authority(store, release$project_id[[1L]])
  brohn_require(identical(release$study_id[[1L]], study_id) && identical(release$project_id[[1L]], project_id),
    "This saved release is outside the open study and project.")
  ids <- DBI::dbGetQuery(store$con, paste("SELECT id FROM delivery_runs WHERE deployment_id=?",
    "AND completion_status='completed' AND transfer_status='saved' ORDER BY id"), params = list(deployment_id))$id
  brohn_require(length(ids) > 0L, "No completed and saved sessions are available for this release yet.")
  ids <- sort(ids)
  # Membership is frozen here. Later completions are not silently added.
  sources <- lapply(ids, function(id) .brohn_sma_source(store, id, study_id, project_id))
  schemas <- vapply(sources, `[[`, character(1), "schema")
  brohn_require(length(unique(schemas)) == 1L && all(vapply(sources,
      function(source) identical(source$scope$deployment_id, deployment_id) &&
        .brohn_ph_equal(source$scope, sources[[1L]]$scope), logical(1))),
    "A saved cohort requires one original release, study, project, origin and protocol schema.")
  variant <- identical(schemas[[1L]], "brohn-protocol/1.2.0")
  request <- list(deployment_id = deployment_id, run_ids = as.list(ids), recipe = "typed-explicit-responses/1.0.0-draft")
  if (variant) request$analysis_profile <- .brohn_vra_profile
  key <- if (variant) .brohn_vra_key("analyse_cohort", request) else paste0("cohort:", brohn_hash(request))
  .brohn_sma_queue(store, sources, "analyse_cohort", request, key, variant)
}
brohn_saved_analysis_status <- function(result) {
  job <- result$job
  label <- switch(job$status, queued = if (isTRUE(result$reused)) "The saved analysis is already queued." else "The saved analysis is queued.",
    running = "The saved analysis is already running.",
    succeeded = "The saved analysis is complete. Its existing report is ready in Results.",
    failed = "The saved analysis previously failed. Open Activity to review it or retry the same saved request.",
    cancelled = "The saved analysis was cancelled. Open Activity to retry the same saved request.",
    "Open Activity to review this saved analysis.")
  if (!is.null(result$recovery)) label <- paste(label,
    "The earlier failed attempt remains unchanged; no participant recollection is needed.")
  paste(label, "Analysis job:", job$id)
}
