# Receiver-derived questionnaire state. Browser state is never an analysis input.
.brohn_delivery_revision_context <- function(protocol, expected_hash = NULL) {
  if (!"questionnaire_navigation" %in% names(protocol$design)) return(NULL)
  brohn_questionnaire_revision_context(protocol, expected_hash)
}
.brohn_delivery_revision_initial <- function(state, context) {
  if (!is.null(context) && is.null(state$questionnaire)) state$questionnaire <- brohn_questionnaire_revision_new(context)
  state
}
.brohn_delivery_revision_apply <- function(state, event, protocol, context = NULL) {
  if (is.null(context)) context <- .brohn_delivery_revision_context(protocol)
  .brohn_delivery_require(!is.null(context) && is.null(state$active),
    "Questionnaire navigation requires the current untimed assessment boundary.", 409, "questionnaire_order")
  state <- .brohn_delivery_revision_initial(state, context)
  changed <- tryCatch(brohn_questionnaire_revision_apply(state$questionnaire, event, context, state$cursor),
    error = function(e) .brohn_delivery_error(conditionMessage(e), 422, "questionnaire_transition"))
  state$questionnaire <- changed$state; state$cursor <- changed$protocol_cursor
  if (isTRUE(changed$effects$sealed)) {
    id <- event$payload$occurrence_id; manifest <- context$manifests[[id]]
    occurrence <- state$questionnaire$occurrences[[id]]
    visible <- .brohn_revision_visible(state$questionnaire, occurrence, manifest, context)
    state$completed <- c(state$completed, as.list(c(visible, manifest$review_step_id)))
  }
  state
}
.brohn_delivery_questionnaire_packet <- function(state, protocol, context = NULL, offset = 0L, acknowledged_sequence = 0L) {
  if (is.null(context)) context <- .brohn_delivery_revision_context(protocol)
  if (is.null(context)) return(NULL)
  state <- .brohn_delivery_revision_initial(state, context)
  page <- brohn_questionnaire_revision_resume(context, state$questionnaire, offset, 3L*1024L^2L-32768L)
  next_step <- if (state$cursor <= length(protocol$timeline)) protocol$timeline[[state$cursor]] else NULL
  last <- if (length(state$questionnaire$history)) tail(state$questionnaire$history, 1L)[[1L]] else NULL
  oid <- brohn_default(state$questionnaire$active_occurrence_id,
    brohn_default(next_step$questionnaire_occurrence_id, last$occurrence_id))
  occurrence <- NULL; actions <- list(enter_step_id = NULL, next_step_id = NULL, back_step_id = NULL,
    editable_step_ids = list(), can_seal = FALSE)
  if (!is.null(oid)) {
    manifest <- context$manifests[[oid]]
    item <- state$questionnaire$occurrences[[oid]]
    if (is.null(item)) item <- .brohn_revision_occurrence(manifest)
    visible <- .brohn_revision_visible(state$questionnaire, item, manifest, context)
    rows <- .brohn_revision_rows(state$questionnaire, item, manifest, context)
    occurrence <- list(id = oid, state_version = item$version, sealed = item$sealed,
      review_step_id = manifest$review_step_id, projection_hash = brohn_hash(rows), visit = item$visit)
    if (!item$sealed && !state$withdrawn && !state$run_finished) {
      if (is.null(item$visit)) actions$enter_step_id <- if (length(visible)) visible[[1L]] else manifest$review_step_id else {
        sid <- item$visit$step_id; review <- identical(sid, manifest$review_step_id)
        index <- if (review) length(visible)+1L else match(sid, visible)
        if (!is.na(index)) {
          reached <- if (index > 1L) Filter(function(id) item$records[[id]]$ever_visited, head(visible, index-1L)) else character()
          if (length(reached)) actions$back_step_id <- tail(reached, 1L)
          if (!review && isTRUE(item$visit$committed)) actions$next_step_id <- if (index < length(visible)) visible[[index+1L]] else manifest$review_step_id
        }
        if (review) {
          actions$editable_step_ids <- as.list(Filter(function(id) item$records[[id]]$ever_visited, visible))
          actions$can_seal <- all(vapply(visible, function(id) .brohn_revision_done(item$records[[id]], context$steps[[id]]), logical(1)))
        }
      }
    }
  }
  transition <- if (is.null(last)) NULL else {
    previous <- state$questionnaire$occurrences[[last$occurrence_id]]
    list(occurrence_id = last$occurrence_id, kind = last$kind, state_version = previous$version,
      sealed = previous$sealed, projection_hash = previous$projection_hash)
  }
  packet <- list(schema = "brohn-questionnaire-packet/1.0", acknowledged_sequence = acknowledged_sequence,
    protocol_hash = context$protocol_hash, protocol_cursor = state$cursor, next_step_id = next_step$id,
    state_hash = brohn_hash(list(revision_state_hash = page$state_hash, cursor = state$cursor,
      acknowledged_sequence = acknowledged_sequence, withdrawn = state$withdrawn, run_finished = state$run_finished)),
    latest_occurrence = occurrence, last_transition = transition, actions = actions, resume_page = page)
  brohn_require(nchar(brohn_json(packet), type = "bytes") <= 3L*1024L^2L, "The complete questionnaire packet exceeds its supported page budget.")
  packet
}
.brohn_delivery_questionnaire_state <- function(store, run_id, token, request) {
  brohn_fields(request, c("offset", "state_hash"), label = "Questionnaire state page")
  .brohn_delivery_require(brohn_number(request$offset, 0, 20000, TRUE) &&
    (is.null(request$state_hash) || (brohn_text(request$state_hash, 64) && grepl("^[a-f0-9]{64}$", request$state_hash))) &&
    (request$offset == 0L || !is.null(request$state_hash)), "Choose a page bound to the current questionnaire state.", 422, "questionnaire_page")
  read <- function() {
    row <- .brohn_delivery_authorize(store, run_id, token); run <- .brohn_delivery_run(row)
    context <- .brohn_delivery_revision_context(run$protocol, row$protocol_hash[[1L]])
    .brohn_delivery_require(!is.null(context), "This session uses its original forward-only questionnaire.", 409, "legacy_questionnaire")
    state <- .brohn_delivery_replay(run$protocol, .brohn_delivery_events(store, run_id), context)
    packet <- .brohn_delivery_questionnaire_packet(state, run$protocol, context, request$offset, run$acked_sequence)
    .brohn_delivery_require(is.null(request$state_hash) || identical(request$state_hash, packet$state_hash),
      "The questionnaire changed while its pages were loading. Reload the acknowledged state.", 409, "questionnaire_state_changed")
    packet
  }
  if (RSQLite::sqliteIsTransacting(store$con)) read() else DBI::dbWithTransaction(store$con, read())
}

# One effective projection feeds explicit summaries, scales and downstream
# synthesis. Legacy repeated responses keep their original ambiguity semantics.
brohn_questionnaire_run_projection <- function(run, events, require_sealed = TRUE) {
  context <- .brohn_delivery_revision_context(run$protocol)
  if (is.null(context)) return(NULL)
  state <- .brohn_delivery_replay(run$protocol, events, context)
  if (require_sealed) brohn_require(isTRUE(state$run_finished) && identical(state$ending_outcome, "completed") && !state$withdrawn,
    "Completed questionnaire analysis requires the original complete receiver journal.")
  result <- brohn_questionnaire_revision_projection(context, state$questionnaire, require_sealed)
  originals <- setNames(events, vapply(events, `[[`, character(1), "id"))
  result$history_events <- lapply(result$history_records, function(ref) {
    event <- originals[[ref$event_id]]
    brohn_require(!is.null(event) && identical(brohn_hash(event), ref$source_event_hash) && event$sequence == ref$sequence,
      "Questionnaire history differs from its original journal evidence.")
    event
  })
  participant <- if (isTRUE(run$participant_alias_supplied)) paste0("alias:", run$participant_alias) else paste0("unlinked:", run$id)
  result$effective_records <- lapply(result$effective_records, function(r) {
    r$participant_id <- participant; r$session_id <- run$id; r$participant_linkage <- isTRUE(run$participant_alias_supplied)
    r$origin <- run$origin; r$prompt <- context$steps[[r$step_id]]$question$prompt; r
  })
  result$source_projection_hash <- result$projection_hash
  result$projection_hash <- brohn_hash(result$effective_records)
  result$run_id <- run$id; result$events_hash <- brohn_hash(events)
  result
}
