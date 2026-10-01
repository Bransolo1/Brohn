# Inactive assigned finalization adapter. Original completion, capture eligibility,
# receipt and analysis-queue transaction remain the source of domain decisions.
.brohn_participant_view_finish_response <- function(store, public_run_id, access_token, request_raw) {
  handle <- brohn_open_participant_view(store, public_run_id, access_token)
  on.exit(handle$close(), add = TRUE)
  original <- handle$read(); context <- original$context
  # One root, schema, view hash, request object and its three scalar values.
  received <- brohn_participant_received_bytes(request_raw, maximum_nodes = 7L)
  value <- received$value
  brohn_fields(value, c("schema", "view_hash", "request"), label = "Assigned finish request")
  .brohn_pvds_require(identical(value$schema, "participant-view-finish/0.1") &&
    identical(value$view_hash, context$view_hash),
    "Finish request belongs to another participant presentation.", "finish_binding", 422L)
  brohn_fields(value$request, c("outcome", "final_sequence", "operation_id"), label = "Assigned finish operation")
  .brohn_pvds_require(brohn_text(value$request$operation_id, 128L) &&
    is.character(value$request$outcome) && length(value$request$outcome) == 1L &&
    !is.na(value$request$outcome) && value$request$outcome %in% c("completed", "withdrawn", "interrupted") &&
    brohn_number(value$request$final_sequence, 0, 10000000, TRUE),
    "Use a supported finish outcome, final sequence and operation identity.", "invalid_request", 400L)
  # Read a genuine legacy row shape under a bounded, admitted source snapshot.
  row <- .brohn_pvds_readonly(store, function() {
    .brohn_pvr_source_cas(store, original)
    answer <- .brohn_pvds_q(store, "SELECT * FROM delivery_runs WHERE id=?", list(original$run$run_id))
    .brohn_pvds_require(nrow(answer) == 1L &&
      identical(charToRaw(enc2utf8(answer$protocol_json[[1L]])), original$source$raw$protocol),
      "The original run changed before finalization.", "source_changed")
    answer
  })
  owned_con <- store$con; owned_workspace <- store$workspace_id
  owned_root <- normalizePath(store$root, winslash = "/", mustWork = TRUE)
  operation <- .brohn_delivery_finish
  scope <- new.env(parent = environment(operation))
  scope$.brohn_delivery_authorize <- function(actual_store, run_id, token) {
    .brohn_pvds_require(identical(actual_store$con, owned_con) && identical(store$con, owned_con) &&
      identical(actual_store$workspace_id, owned_workspace) && identical(store$workspace_id, owned_workspace) &&
      identical(normalizePath(actual_store$root, winslash = "/", mustWork = TRUE), owned_root) &&
      identical(normalizePath(store$root, winslash = "/", mustWork = TRUE), owned_root) &&
      identical(run_id, original$run$run_id) && identical(token, access_token) && RSQLite::sqliteIsTransacting(owned_con),
      "Finalization lost its owned source transaction.", "finish_owner")
    .brohn_pvr_source_cas(store, original)
    row
  }
  original_replay <- .brohn_delivery_replay
  scope$.brohn_delivery_replay <- function(protocol, events, revision_context = NULL) {
    .brohn_pvds_require(RSQLite::sqliteIsTransacting(owned_con) &&
      .brohn_ph_equal(protocol, context$protocol) &&
      (is.null(revision_context) || identical(revision_context, context$revision_context)),
      "Finalization replay lost its admitted original protocol.", "finish_source")
    # The original no-context fallback constructs a legacy revision profile.
    # Explicitly supply this complete admitted assignment's revision context;
    # do not recompile a saved design1.2 assignment through the legacy compiler.
    original_replay(protocol, events, context$revision_context)
  }
  lockEnvironment(scope, bindings = TRUE)
  environment(operation) <- scope
  receipt <- operation(store, original$run$run_id, access_token, value$request)
  brohn_fields(receipt, c("status", "outcome"), label = "Original finish receipt")
  .brohn_pvds_require(identical(receipt$status, "saved") && identical(receipt$outcome, value$request$outcome),
    "The retained finish receipt differs from this operation.", "receipt_integrity")
  document <- brohn_participant_json_bytes(list(schema = "participant-view-finish-result/0.1",
    binding = .brohn_pvcr_binding(context), operation_id = value$request$operation_id, receipt = receipt),
    maximum_bytes = 4 * 1024^2)
  # If reply preparation fails after commit, retain the original receipt and job.
  # A retry still authenticates current access before recovering that receipt.
  handle$current()
  document
}
