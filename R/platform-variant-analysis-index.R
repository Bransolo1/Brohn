# Private metadata/event index after named full saved-source admission.
.brohn_vra_protocol_index <- function(protocol, metadata, project_id) {
  brohn_fields(metadata, c("id", "run_id", "study_id", "deployment_id", "origin", "participant_alias", "participant_alias_supplied",
    "allocation_index", "completion_status", "transfer_status", "acked_sequence", "created_at", "updated_at", "finalized_at", "design_revision", "design_hash"), label = "Run source metadata")
  brohn_require(brohn_valid_id(metadata$id) && identical(metadata$id, metadata$run_id) && brohn_valid_id(metadata$study_id) &&
    brohn_valid_id(metadata$deployment_id) && metadata$origin %in% c("sample", "pilot", "live") &&
    brohn_text(metadata$participant_alias, 256) && is.logical(metadata$participant_alias_supplied) && length(metadata$participant_alias_supplied) == 1L && !is.na(metadata$participant_alias_supplied) &&
    brohn_number(metadata$allocation_index, 1, 1e9, TRUE) && brohn_number(metadata$acked_sequence, 1, 10000000, TRUE) &&
    brohn_number(metadata$design_revision, 1, .Machine$integer.max, TRUE) && .brohn_run_evidence_sha(metadata$design_hash) &&
    identical(metadata$completion_status, "completed") && identical(metadata$transfer_status, "saved") &&
    all(vapply(metadata[c("created_at", "updated_at", "finalized_at")], brohn_text, logical(1), max = 128)), "Run source metadata is not a completed, saved session.")
  brohn_require(is.list(protocol) && identical(protocol$schema_version, "brohn-protocol/1.2.0") && is.list(protocol$design) &&
    identical(protocol$design$id, metadata$study_id) && identical(protocol$design$project_id, project_id) &&
    identical(protocol$design_hash, metadata$design_hash) && .brohn_run_evidence_equal(protocol$allocation_index, metadata$allocation_index) && brohn_array(protocol$timeline),
    "Retained protocol does not match its frozen run, study, project or allocation.")
  # Full named saved1.2 admission is completed by the original-source boundary.
  # This is its metadata/event-index check, never a public validator bypass.
  steps <- new.env(hash = TRUE, parent = emptyenv())
  for (step in protocol$timeline) {
    brohn_require(is.list(step) && brohn_text(step$id, 128) && !exists(step$id, steps, inherits = FALSE), "Retained protocol step identities are invalid.")
    assign(step$id, step, steps)
  }
  list(value = protocol, steps = steps)
}
