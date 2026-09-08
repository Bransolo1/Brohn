# Faithful new retained reproduction of the original receiver boundary.
# The historical R-temp source is absent; this does not resurrect its journal.
brohn_original_questionnaire_boundary <- function(store) {
  d <- brohn_new_design("Original full questionnaire boundary", "survey"); d$instructions <- ""
  d$questions <- lapply(seq_len(200L), function(i) brohn_question(paste("Original text", i), "long_text", "end", paste0("boundary-q-", i)))
  d$questionnaire_navigation <- brohn_questionnaire_navigation()
  brohn_put_entity(store, "study", d$id, d)
  release <- brohn_publish(store, d$id, origin = "sample", quota = 1L)
  first <- .brohn_delivery_start(store, release$token, list(consented = TRUE, client_id = "boundary-client", operation_id = "boundary-start"))
  p <- first$protocol; ctx <- .brohn_delivery_revision_context(p)
  state <- .brohn_delivery_revision_initial(.brohn_delivery_initial_state(), ctx)
  manifest <- p$questionnaire_occurrences[[1L]]; journal <- list(); tick <- 0
  occurrence <- function() state$questionnaire$occurrences[[manifest$id]]
  emit <- function(kind, sid, extra) {
    item <- occurrence(); step <- brohn_find(p$timeline, sid); tick <<- tick+100
    event <- list(sequence = length(journal)+1L, id = paste0("boundary-event-", length(journal)+1L), type = "questionnaire_event",
      step_id = sid, stimulus_id = step$stimulus_id, condition_id = step$condition_id, question_id = if (step$type == "question") step$question$id else NULL,
      phase = step$phase, clock = list(id = "browser-monotonic", unit = "ms", value = as.character(tick), instance_id = "boundary-clock", time_origin_ms = "1"),
      payload = c(list(schema = "brohn-questionnaire-event/1.0", kind = kind, occurrence_id = manifest$id,
        state_version = if (is.null(item)) 0L else item$version), extra))
    state <<- .brohn_delivery_apply(state, event, p, ctx); journal[[length(journal)+1L]] <<- event
  }
  visit <- function(sid, reason) emit("visit", sid, list(visit_id = paste0("boundary-visit-", length(journal)+1L), reason = reason, from_visit_id = occurrence()$visit$id))
  ids <- unlist(manifest$question_step_ids, use.names = FALSE)
  text <- strrep("a", 19000L)
  for (pass in 1:2) {
    visit(ids[[1L]], if (pass == 1L) "enter" else "edit")
    for (i in seq_along(ids)) {
      item <- occurrence(); row <- item$records[[ids[[i]]]]; v <- item$visit
      emit("commit", ids[[i]], list(visit_id = v$id, previous_answer_event_id = row$last_answer_event_id,
        dependency_generation = row$dependency_generation, value = paste(text, pass, i),
        response_time_ms = if (pass == 1L) 100 else NULL, active_segment_response_ms = 100, resumed = FALSE))
      visit(if (i < length(ids)) ids[[i+1L]] else manifest$review_step_id, "next")
    }
  }
  # Full saved response page exceeds one transport page, and must page without
  # losing answers or changing either source/global state identity.
  for (indices in split(seq_along(journal), ceiling(seq_along(journal)/100))) {
    body <- list(operation_id = paste0("boundary-batch-", indices[[1L]]), events = journal[indices])
    stopifnot(nchar(brohn_json(body), type = "bytes") < 4*1024^2)
    packet <- .brohn_delivery_receive(store, first$run_id, first$access_token, body)$questionnaire
  }
  recovered <- packet$resume_page$records; next_offset <- packet$resume_page$next_offset
  stopifnot(!is.null(next_offset))
  while (!is.null(next_offset)) {
    page <- .brohn_delivery_questionnaire_state(store, first$run_id, first$access_token, list(offset = next_offset, state_hash = packet$state_hash))
    stopifnot(identical(page$state_hash, packet$state_hash), identical(page$resume_page$state_hash, packet$resume_page$state_hash),
      nchar(brohn_json(page), type = "bytes") <= 3*1024^2)
    recovered <- c(recovered, page$resume_page$records); next_offset <- page$resume_page$next_offset
  }
  stopifnot(length(recovered) == 200L, !anyDuplicated(vapply(recovered, `[[`, character(1), "step_id")))
  emit("seal", manifest$review_step_id, list(visit_id = occurrence()$visit$id, projection_hash = packet$latest_occurrence$projection_hash))
  last <- tail(journal, 1L)[[1L]]
  .brohn_delivery_receive(store, first$run_id, first$access_token, list(operation_id = "boundary-seal", events = list(last)))
  ending <- list(sequence = length(journal)+1L, id = "boundary-ending", type = "run_finished", step_id = NULL, stimulus_id = NULL, condition_id = NULL,
    question_id = NULL, phase = "session", clock = list(id = "browser-monotonic", unit = "ms", value = as.character(tick+100), instance_id = "boundary-clock", time_origin_ms = "1"), payload = list(outcome = "completed"))
  .brohn_delivery_receive(store, first$run_id, first$access_token, list(operation_id = "boundary-ending-request", events = list(ending)))
  .brohn_delivery_finish(store, first$run_id, first$access_token, list(operation_id = "boundary-finish", outcome = "completed", final_sequence = ending$sequence))
  job <- brohn_list_jobs(store, request_filters=list(run_id=first$run_id))[[1L]]
  brohn_cancel_job(store,job$id)
  list(study_id=d$id,run_id=first$run_id,original_job_id=job$id,
    independent=list(question_count=200L,entered_answer_count=400L,final_record_count=200L,text_characters=19000L,
      final_values=lapply(seq_len(200L),function(i)paste(text,2L,i)),
      first_values=lapply(seq_len(200L),function(i)paste(text,1L,i))),
    recovered_page_count=length(recovered),journal_hash=brohn_hash(c(journal,list(ending))))
}
