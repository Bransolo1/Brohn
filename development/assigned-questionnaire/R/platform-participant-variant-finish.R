# Inactive assigned finalization adapter. Original completion, capture eligibility,
# receipt and analysis-queue transaction remain the source of domain decisions.
.brohn_participant_variant_finish_response <- function(store, public_run_id, access_token, request_raw) {
  .brohn_pvds_require(!RSQLite::sqliteIsTransacting(store$con),
    "Prepare participant finalization outside an existing transaction.", "finish_transaction")
  handle <- brohn_open_participant_view(store, public_run_id, access_token)
  on.exit(handle$close(), add = TRUE)
  before <- .brohn_pvr_stamp(store)
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
  # Preserve the original receipt-first behavior. A retained operation needs no
  # new replay; its hash/result remain checked by the original finish function.
  # New operations replay the complete received journal one body at a time under
  # a read-only snapshot, before acquiring the original writer transaction.
  proof <- .brohn_pvds_readonly(store, function() {
    .brohn_pvr_source_cas(store, original)
    admitted_schema <- .brohn_pvr_schema_admit(store)
    row <- .brohn_pvds_q(store, "SELECT * FROM delivery_runs WHERE id=?", list(original$run$run_id))
    .brohn_pvds_require(nrow(row) == 1L &&
      identical(charToRaw(enc2utf8(row$protocol_json[[1L]])), original$source$raw$protocol),
      "The original run changed before finalization.", "source_changed")
    prior <- .brohn_pvds_q(store, paste("SELECT count(*) AS n FROM delivery_receipts",
      "WHERE scope=? AND operation='finish' AND operation_id=?"),
      list(original$run$run_id, value$request$operation_id))$n[[1L]]
    .brohn_pvds_require(prior %in% c(0L, 1L), "The saved finish operation is not unique.", "receipt_integrity")
    history <- if (prior == 0L) .brohn_pvcr_history(store, original$run$run_id,
      original$run$acked_sequence, context) else NULL
    # Original camera support has its own lexical event reader. Prepare it here
    # as well; overriding the finish function's reader does not reach that call.
    # Its current aggregate camera-clock scan remains a separate memory gate.
    camera <- NULL
    if (prior == 0L && identical(value$request$outcome, "completed") &&
        !is.null(context$protocol$design$camera)) {
      .brohn_delivery_require(exists("brohn_camera_completion", mode = "function"),
        "The camera completion module is unavailable.", 503L, "camera_module_unavailable")
      camera <- brohn_camera_completion(store, original$run$run_id)
    }
    # No profile is encoded in the original finish receipt. An existing receipt
    # without the distinct named queue key must never be silently migrated.
    # The same snapshot and writer stamp fence this classification.
    legacy_retry <- prior == 1L && identical(value$request$outcome, "completed") &&
      .brohn_pvds_q(store, "SELECT count(*) AS n FROM jobs WHERE idempotency_key=?",
        list(paste0("variant-analysis:0.1:run:", original$run$run_id)))$n[[1L]] == 0L
    list(row = row, schema = admitted_schema, prior = prior == 1L, history = history,
      camera = camera, legacy_retry = legacy_retry)
  })
  .brohn_pvr_same_stamp(store, before)
  row <- proof$row
  owned_con <- store$con; owned_workspace <- store$workspace_id
  owned_root <- normalizePath(store$root, winslash = "/", mustWork = TRUE)
  operation <- .brohn_delivery_finish
  scope <- new.env(parent = environment(operation))
  named_queue <- .brohn_vra_finish_queue(store, original)
  scope$brohn_enqueue_job <- function(actual_store, operation, request, idempotency_key, prepared_id = NULL) {
    if (!proof$legacy_retry) return(named_queue(actual_store, operation, request, idempotency_key, prepared_id))
    # Reached only after the unchanged original receipt/hash lookup accepted
    # this exact operation. Preserve its old reply without creating a new job.
    assert_owned(actual_store)
    .brohn_pvds_require(proof$prior && identical(operation, "analyse_run") && is.null(prepared_id) &&
      .brohn_ph_equal(request, list(run_id = original$run$run_id)) &&
      identical(idempotency_key, paste0("analyse-run:", original$run$run_id)),
      "Historical finalization lost its original queue binding.", "finish_owner")
    .brohn_pvr_same_stamp(store, before)
    .brohn_pvr_source_cas(store, original)
    invisible(NULL)
  }
  assert_owned <- function(actual_store) {
    .brohn_pvds_require(identical(actual_store$con, owned_con) && identical(store$con, owned_con) &&
      identical(actual_store$workspace_id, owned_workspace) && identical(store$workspace_id, owned_workspace) &&
      identical(normalizePath(actual_store$root, winslash = "/", mustWork = TRUE), owned_root) &&
      identical(normalizePath(store$root, winslash = "/", mustWork = TRUE), owned_root) &&
      RSQLite::sqliteIsTransacting(owned_con),
      "Finalization lost its owned source transaction.", "finish_owner")
  }
  scope$.brohn_delivery_authorize <- function(actual_store, run_id, token) {
    assert_owned(actual_store)
    .brohn_pvds_require(identical(run_id, original$run$run_id) && identical(token, access_token),
      "Finalization lost its original participant authority.", "finish_owner")
    .brohn_pvr_same_stamp(store, before)
    .brohn_pvds_require(identical(.brohn_pvr_schema_admit(store), proof$schema),
      "Finalization source schema changed during preparation.", "state_changed")
    .brohn_pvr_source_cas(store, original)
    .brohn_pvr_same_stamp(store, before)
    row
  }
  # Only this private original finish invocation can consume the prepared state.
  # The marker is never an event array, serialized input or caller-owned handle.
  marker <- new.env(parent = emptyenv()); lockEnvironment(marker, bindings = TRUE)
  delivered <- FALSE; replayed <- FALSE
  scope$.brohn_delivery_events <- function(actual_store, run_id) {
    assert_owned(actual_store)
    .brohn_pvds_require(identical(run_id, original$run$run_id) && !proof$prior &&
      !delivered && !is.null(proof$history), "Finalization has no fresh prepared journal.", "finish_source")
    .brohn_pvr_same_stamp(store, before)
    delivered <<- TRUE
    marker
  }
  scope$.brohn_delivery_replay <- function(protocol, events, revision_context = NULL) {
    assert_owned(store)
    .brohn_pvds_require(.brohn_ph_equal(protocol, context$protocol) &&
      (is.null(revision_context) || identical(revision_context, context$revision_context)) &&
      identical(events, marker) && delivered && !replayed && !is.null(proof$history),
      "Finalization replay lost its admitted original journal.", "finish_source")
    .brohn_pvr_same_stamp(store, before)
    replayed <<- TRUE
    proof$history$state
  }
  scope$brohn_camera_completion <- function(actual_store, run_id) {
    assert_owned(actual_store)
    .brohn_pvds_require(identical(run_id, original$run$run_id) && !proof$prior &&
      replayed && !is.null(proof$camera), "Finalization has no fresh prepared camera support.", "finish_source")
    # The global change stamp fences all camera rows/chunks/receipts as well as
    # source/progress, across both peer commits and own-connection changes.
    .brohn_pvr_same_stamp(store, before)
    proof$camera
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
