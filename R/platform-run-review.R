# Read the original assigned protocol. Never reconstruct it from today's draft.
brohn_run_protocol <- function(store, run_id, study_id, project_id) {
  .brohn_delivery_schema(store)
  brohn_require(all(vapply(list(run_id, study_id, project_id), brohn_valid_id, logical(1))), "Choose a participant session from its study.")
  rows <- DBI::dbGetQuery(store$con, paste(
    "SELECT r.id,r.study_id,r.deployment_id,r.origin,r.participant_alias,r.allocation_index,",
    "r.completion_status,r.transfer_status,r.acked_sequence,r.protocol_json,r.protocol_hash",
    "FROM delivery_runs r JOIN delivery_deployments d ON r.deployment_id=d.id",
    "WHERE r.id=? AND r.study_id=? AND d.study_id=? AND d.project_id=?"),
    params = list(run_id, study_id, study_id, project_id))
  brohn_require(nrow(rows) == 1L, "This session is not available in the selected study and project.")
  protocol <- .brohn_store_decode(rows$protocol_json[[1]], rows$protocol_hash[[1]])
  brohn_require(identical(protocol$design$id, study_id) && identical(protocol$design$project_id, project_id), "The stored protocol does not belong to this study and project.")
  metadata <- as.list(rows[1, setdiff(names(rows), c("protocol_json", "protocol_hash")), drop = FALSE])
  list(run = metadata, protocol = protocol, json = rows$protocol_json[[1]], hash = rows$protocol_hash[[1]])
}
brohn_export_run_protocol <- function(snapshot, file) {
  brohn_require(is.list(snapshot) && brohn_text(snapshot$json, 64*1024^2) &&
    identical(.brohn_store_hash(charToRaw(snapshot$json)), snapshot$hash), "The assigned protocol failed its saved-source integrity check.")
  writeBin(charToRaw(snapshot$json), file)
  invisible(file)
}
