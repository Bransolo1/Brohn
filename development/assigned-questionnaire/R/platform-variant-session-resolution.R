# Inactive explicit researcher recovery for original saved protocol1.2.
# Original review, immutable decision, receipts and source rows retain their
# existing schemas. No legacy reader, participant route or worker is registered.
.brohn_vsr_snapshot_in_transaction <- function(store, run_id, study_id, project_id) {
  brohn_require(RSQLite::sqliteIsTransacting(store$con),
    "Check the original variant source in its owned catalogue transaction.")
  query <- paste(
    "SELECT r.id AS run_id,r.deployment_id,r.study_id,r.origin,r.allocation_index,",
    "r.protocol_hash,d.project_id,d.design_revision,d.design_hash,",
    "v.body_hash AS study_body_hash,",
    "length(CAST(r.protocol_json AS BLOB)) AS protocol_bytes,",
    "length(CAST(d.design_json AS BLOB)) AS release_bytes,",
    "length(CAST(v.body_json AS BLOB)) AS study_bytes",
    "FROM delivery_runs r JOIN delivery_deployments d ON d.id=r.deployment_id",
    "JOIN entity_versions v ON v.kind='study' AND v.id=d.study_id AND v.revision=d.design_revision",
    "JOIN entities e ON e.kind=v.kind AND e.id=v.id",
    "WHERE r.id=? AND r.study_id=? AND d.study_id=r.study_id AND d.project_id=?",
    "AND v.project_id=d.project_id AND e.project_id=d.project_id AND r.origin=d.origin")
  rows <- DBI::dbGetQuery(store$con, query, params = list(run_id, study_id, project_id))
  brohn_require(nrow(rows) == 1L,
    "This original session is unavailable in the selected study and project.")
  sizes <- vapply(c("protocol_bytes", "release_bytes", "study_bytes"),
    function(name) as.numeric(rows[[name]][[1L]]), numeric(1), USE.NAMES = FALSE)
  brohn_require(length(sizes) == 3L && !anyNA(sizes) && all(is.finite(sizes)) &&
    all(sizes >= 1 & sizes <= .brohn_epr_limit),
    "An original protocol, release or study revision exceeds its 16 MiB source bound.")
  raw <- DBI::dbGetQuery(store$con, paste(
    "SELECT CAST(r.protocol_json AS BLOB) AS protocol,",
    "CAST(d.design_json AS BLOB) AS release,CAST(v.body_json AS BLOB) AS study",
    "FROM delivery_runs r JOIN delivery_deployments d ON d.id=r.deployment_id",
    "JOIN entity_versions v ON v.kind='study' AND v.id=d.study_id AND v.revision=d.design_revision",
    "WHERE r.id=? AND length(CAST(r.protocol_json AS BLOB))<=?",
    "AND length(CAST(d.design_json AS BLOB))<=? AND length(CAST(v.body_json AS BLOB))<=?"),
    params = list(run_id, .brohn_epr_limit, .brohn_epr_limit, .brohn_epr_limit))
  brohn_require(nrow(raw) == 1L, "The original source became unavailable.")
  bodies <- lapply(raw, function(column) column[[1L]])
  brohn_require(identical(names(bodies), c("protocol", "release", "study")) &&
    all(vapply(bodies, is.raw, logical(1))) &&
    identical(as.numeric(lengths(bodies)), sizes), "Original source byte lengths disagree.")
  list(metadata = lapply(rows, function(column) column[[1L]]), bodies = bodies)
}

.brohn_vsr_with_source <- function(store, release_id, run_id, study_id, project_id, action) {
  .brohn_epr_authority(store, project_id)
  brohn_require(!RSQLite::sqliteIsTransacting(store$con),
    "Open variant session recovery outside an existing catalogue transaction.")
  handle <- brohn_open_variant_run_protocol(store, run_id, study_id, project_id)
  on.exit(handle$close(), add = TRUE)
  original <- handle$read()
  brohn_require(identical(original$source$deployment_id, release_id),
    "Choose the exact release of this original variant session.")
  context <- if (!is.null(original$protocol$design$questionnaire_navigation))
    brohn_variant_revision_context(original$protocol, original$source$protocol_hash) else NULL
  handle$current()
  owned_con <- store$con
  owned_workspace <- store$workspace_id
  owned_root <- normalizePath(store$root, winslash = "/", mustWork = TRUE)
  # Copy only the original closures. Their formals and function bodies remain
  # exact; the private sibling bindings provide this one admitted source context.
  snapshot <- .brohn_sr_snapshot
  review <- brohn_session_resolution_review
  resolve <- brohn_resolve_session
  transaction <- .brohn_store_tx
  parent <- environment(snapshot)
  brohn_require(identical(environment(review), parent) && identical(environment(resolve), parent),
    "The variant recovery reader needs one pinned original resolution module.")
  scope <- new.env(parent = parent)
  active <- TRUE
  on.exit({ active <- FALSE }, add = TRUE)
  assert_source <- function(actual_store, actual_release = release_id, actual_run = run_id,
      actual_study = study_id, actual_project = project_id) {
    brohn_require(active && identical(actual_store$con, owned_con) && identical(store$con, owned_con) &&
      identical(actual_store$workspace_id, owned_workspace) && identical(store$workspace_id, owned_workspace) &&
      identical(normalizePath(actual_store$root, winslash = "/", mustWork = TRUE), owned_root) &&
      identical(normalizePath(store$root, winslash = "/", mustWork = TRUE), owned_root) &&
      identical(actual_release, release_id) && identical(actual_run, run_id) &&
      identical(actual_study, study_id) && identical(actual_project, project_id) &&
      RSQLite::sqliteIsTransacting(owned_con),
      "Variant session recovery lost its owned original source transaction.")
    .brohn_epr_authority(actual_store, project_id)
    current <- .brohn_vsr_snapshot_in_transaction(actual_store, run_id, study_id, project_id)
    brohn_require(identical(current$metadata, original$source) &&
      identical(current$bodies$protocol, original$protocol_bytes) &&
      identical(current$bodies$release, original$release_bytes) &&
      identical(current$bodies$study, original$study_bytes),
      "The original variant protocol, release or released study revision changed. Reopen its recovery review.")
    invisible(TRUE)
  }
  scope$.brohn_delivery_revision_context <- function(protocol, original_protocol_hash = NULL) {
    assert_source(store)
    brohn_require(!is.null(context) && identical(original_protocol_hash, original$source$protocol_hash) &&
      .brohn_ph_equal(protocol, original$protocol),
      "Recovery replay differs from its admitted original variant protocol.")
    context
  }
  environment(snapshot) <- scope
  scope$.brohn_sr_snapshot <- function(store, release_id, run_id, study_id, project_id,
      include_events = FALSE, verify_bytes = FALSE) {
    assert_source(store, release_id, run_id, study_id, project_id)
    snapshot(store, release_id, run_id, study_id, project_id, include_events, verify_bytes)
  }
  # The original resolve function checks a previous decision before building a
  # new snapshot. Fence that branch too, inside its original writer transaction.
  scope$.brohn_store_tx <- function(store, fn) {
    transaction(store, function() { assert_source(store); fn() })
  }
  environment(review) <- scope
  scope$brohn_session_resolution_review <- review
  environment(resolve) <- scope
  scope$brohn_resolve_session <- resolve
  lockEnvironment(scope, bindings = TRUE)
  result <- action(scope)
  # An immutable decision may already have committed if this final current read
  # fails. An exact retry still uses the original decision identity and reason.
  handle$current()
  result
}

brohn_variant_session_resolution_review <- function(store, release_id, run_id, study_id, project_id) {
  .brohn_vsr_with_source(store, release_id, run_id, study_id, project_id, function(scope)
    scope$brohn_session_resolution_review(store, release_id, run_id, study_id, project_id))
}

brohn_resolve_variant_session <- function(store, release_id, run_id, study_id, project_id, expected_hash, reason) {
  .brohn_vsr_with_source(store, release_id, run_id, study_id, project_id, function(scope)
    scope$brohn_resolve_session(store, release_id, run_id, study_id, project_id, expected_hash, reason))
}
