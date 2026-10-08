# Inactive researcher-only admission of original saved protocol1.1 bytes.
# No loader, delivery, export or scoring dispatch is changed by this module.
.brohn_epr_limit <- 16 * 1024^2
.brohn_epr_sha <- function(bytes) digest::digest(bytes, algo = "sha256", serialize = FALSE)
.brohn_epr_authority <- function(store, project_id) {
  .brohn_store_ready(store)
  brohn_require(!isTRUE(store$hosted_participant),
    "Open original study protocols through a current researcher session.")
  if (!is.null(store$hosted_profile)) {
    brohn_hosted_require_session(store)
    brohn_hosted_require_project(store, project_id)
  }
  workspace <- DBI::dbGetQuery(store$con, "SELECT value FROM metadata WHERE key='workspace_id'")
  brohn_require(nrow(workspace) == 1L && identical(workspace$value[[1L]], store$workspace_id),
    "The open workspace identity changed. Reopen the study.")
  invisible(TRUE)
}
.brohn_epr_snapshot <- function(store, run_id, study_id, project_id) {
  .brohn_epr_authority(store, project_id)
  brohn_require(!RSQLite::sqliteIsTransacting(store$con),
    "Open original protocols outside an existing catalogue transaction.")
  # Do not initialise/migrate delivery here. The store must already contain the
  # saved run. Length admission happens before any large value is fetched.
  value <- DBI::dbWithTransaction(store$con, {
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
  })
  # Hash/parse/model checks deliberately occur after the read snapshot closes.
  .brohn_epr_authority(store, project_id)
  value
}
.brohn_epr_decode <- function(bytes) {
  brohn_require(is.raw(bytes) && length(bytes) >= 1L && length(bytes) <= .brohn_epr_limit &&
    !any(bytes == as.raw(0)), "Original source JSON contains an invalid byte or exceeds its bound.")
  text <- rawToChar(bytes)
  Encoding(text) <- "UTF-8"
  brohn_require(validUTF8(text), "Original source JSON is not valid UTF-8.")
  # Preserve the decoded value; the saved reader validates duplicate keys,
  # shapes and canonical identities without substituting a new stored value.
  value <- jsonlite::fromJSON(text, simplifyVector = FALSE)
  .brohn_ph_domain(value)
  value
}
.brohn_epr_integrity <- function(snapshot) {
  m <- snapshot$metadata
  brohn_require(.brohn_ph_sha(m$protocol_hash) && .brohn_ph_sha(m$study_body_hash) &&
    .brohn_ph_sha(m$design_hash) && brohn_valid_id(m$run_id) &&
    brohn_valid_id(m$study_id) && brohn_valid_id(m$deployment_id) && brohn_valid_id(m$project_id) &&
    brohn_number(m$allocation_index, 1, 1e9, TRUE) &&
    brohn_number(m$design_revision, 1, .Machine$integer.max, TRUE) &&
    brohn_text(m$origin, 16) && m$origin %in% c("sample", "pilot", "live"),
    "The original run, release or revision metadata is invalid.")
  hashes <- vapply(snapshot$bodies, .brohn_epr_sha, character(1))
  brohn_require(identical(unname(hashes[["protocol"]]), m$protocol_hash) &&
    identical(unname(hashes[["study"]]), m$study_body_hash),
    "An original protocol or study revision failed its retained byte hash.")
  hashes
}
.brohn_epr_open <- function(store, run_id, study_id, project_id, version) {
  brohn_require(all(vapply(list(run_id, study_id, project_id), brohn_valid_id, logical(1))),
    "Choose an original session from its study and project.")
  original <- .brohn_epr_snapshot(store, run_id, study_id, project_id)
  raw_hashes <- .brohn_epr_integrity(original)
  protocol <- .brohn_epr_decode(original$bodies$protocol)
  release <- .brohn_epr_decode(original$bodies$release)
  study <- .brohn_epr_decode(original$bodies$study)
  if (identical(version, "1.1")) {
    brohn_require(identical(protocol[["schema_version", exact = TRUE]], "brohn-protocol/1.1.0"),
      "This reader admits saved evidence protocols1.1 only.")
    brohn_validate_saved_evidence_protocol(protocol)
  } else if (identical(version, "1.2")) {
    brohn_require(identical(protocol[["schema_version", exact = TRUE]], "brohn-protocol/1.2.0"),
      "This reader admits saved variant protocols1.2 only.")
    brohn_validate_saved_variant_protocol(protocol)
  } else brohn_stop("Unsupported private original-protocol reader registration.")
  brohn_require(.brohn_ph_equal(protocol$design, release) && .brohn_ph_equal(release, study),
    "The original run, release and released study revision contain different designs.")
  m <- original$metadata
  brohn_require(identical(protocol$design$id, m$study_id) &&
    identical(protocol$design$project_id, m$project_id) &&
    identical(protocol$design_hash, m$design_hash) &&
    .brohn_ph_equal(protocol$allocation_index, m$allocation_index),
    "The saved protocol does not match its original study, project, release or allocation.")
  # A local application handle is not serialized authority. Every use rechecks
  # the current researcher and the exact original sources. A new draft/head,
  # run event, completion status or recruitment state does not change this pin.
  state <- new.env(parent = emptyenv())
  state$closed <- FALSE
  recheck <- function() {
    brohn_require(!state$closed, "This original-protocol reader is closed.")
    current <- .brohn_epr_snapshot(store, run_id, study_id, project_id)
    current_hashes <- .brohn_epr_integrity(current)
    brohn_require(identical(current$metadata, original$metadata) && identical(current_hashes, raw_hashes),
      "The original protocol source changed. Reopen the saved session.")
    invisible(TRUE)
  }
  # Check again after potentially expensive complete saved-model validation.
  recheck()
  handle <- new.env(parent = emptyenv())
  handle$read <- function() {
    recheck()
    list(schema = if (identical(version, "1.1")) "brohn-original-evidence-run-source/0.1" else
      "brohn-original-variant-run-source/0.1", workspace_id = store$workspace_id,
      source = m, raw_sha256 = as.list(raw_hashes), protocol = protocol,
      protocol_bytes = original$bodies$protocol, release_bytes = original$bodies$release,
      study_bytes = original$bodies$study)
  }
  handle$current <- recheck
  handle$close <- function() { state$closed <- TRUE; invisible(TRUE) }
  class(handle) <- if (identical(version, "1.1")) "brohn_original_evidence_run_source" else
    "brohn_original_variant_run_source"
  lockEnvironment(handle, bindings = TRUE)
  handle
}

# Existing explicit public1.1 entry retains its exact admission and result.
brohn_open_evidence_run_protocol <- function(store, run_id, study_id, project_id) {
  .brohn_epr_open(store, run_id, study_id, project_id, "1.1")
}
