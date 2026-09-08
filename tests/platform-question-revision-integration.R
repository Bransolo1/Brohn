# Real catalog/receiver receipts plus canonical scoring. No browser or hardware.
source("R/platform-load.R", encoding = "UTF-8"); brohn_load()
local({
  checks <- 0L
  check <- function(label, ok) {if (!isTRUE(ok)) stop("FAIL: ", label); checks <<- checks+1L}
  rejected <- function(expr, pattern = NULL) {
    error <- tryCatch({force(expr); NULL}, error = conditionMessage)
    if (!is.null(pattern) && !is.null(error) && !grepl(pattern, error, fixed = TRUE)) cat("Unexpected rejection: ", error, "\n")
    !is.null(error) && (is.null(pattern) || grepl(pattern, error, fixed = TRUE))
  }
  d <- brohn_new_design("Original reviewed answers", "survey", "study-reviewed-original"); d$instructions <- ""
  driver <- brohn_question("Original routing choice", "single_choice", "before", "q-route")
  driver$options <- list(list(id = "no", label = "No", value = FALSE), list(id = "zero", label = "Zero", value = 0))
  follow <- brohn_question("Original dependent answer", "text", "before", "q-follow")
  follow$show_if <- list(op = "not_equals", question_id = driver$id, value = FALSE)
  info <- brohn_question("Original information", "information", "before", "q-info")
  optional <- brohn_question("Original optional answer", "text", "before", "q-optional"); optional$required <- FALSE
  items <- lapply(1:2, function(i) brohn_question(paste("Original mean item", i), "rating", "end", paste0("q-mean-", i)))
  d$questions <- c(list(driver, follow, info, optional), items)
  d$scales <- list(list(schema = "brohn-questionnaire-scale/1.0", id = "original-mean", label = "Original final mean", version = "1.0",
    source = "Original arithmetic fixture; no instrument qualification", scope = "end",
    items = lapply(items, function(q) list(question_id = q$id, reverse = FALSE, min = 1, max = 7)),
    scoring = list(aggregation = "mean", missing = "complete", minimum_answered = 2, prorate = FALSE), conversion = NULL))
  legacy <- brohn_compile(d); legacy_bytes <- brohn_json(legacy)
  d$questionnaire_navigation <- brohn_questionnaire_navigation(); p <- brohn_compile(d)
  check("actual compiler creates separate adjacent before and end occurrences", length(p$questionnaire_occurrences) == 2L && length(p$timeline) == length(legacy$timeline)+2L)
  stripped <- lapply(Filter(function(s) s$type != "questionnaire_review", p$timeline), function(s) {s$questionnaire_occurrence_id <- NULL; s})
  check("original step identities and options are unchanged by second pass", identical(brohn_json(stripped), brohn_json(legacy$timeline)))
  store <- brohn_open_store(tempfile("brohn-revision-integration-")); on.exit(brohn_close_store(store), add = TRUE)
  brohn_initialise_library(store); saved <- brohn_put_entity(store, "study", d$id, d)
  zip <- tempfile(fileext = ".brohn-study.zip"); brohn_export_design(store, d$id, zip); cloned <- brohn_import_design(store, zip)
  check("actual portable design remaps questions and retains the opt-in policy", identical(brohn_json(cloned$body$questionnaire_navigation), brohn_json(d$questionnaire_navigation)) &&
    length(brohn_compile(cloned$body)$questionnaire_occurrences) == 2L && !identical(brohn_ids(cloned$body$questions), brohn_ids(d$questions)))
  release <- brohn_publish(store, d$id, origin = "sample", quota = 2, alias_required = TRUE)
  start <- list(consented = TRUE, client_id = "original-review-client", operation_id = "original-review-start", participant_alias = "001")
  first <- .brohn_delivery_start(store, release$token, start); packet <- first$resume$questionnaire
  check("first response pins canonical protocol and first legal target", identical(first$protocol_hash, brohn_hash(p)) && packet$acknowledged_sequence == 0L && identical(packet$actions$enter_step_id, p$timeline[[1]]$id))
  check("identical start receipt retains the assigned revision manifest", identical(first, .brohn_delivery_start(store, release$token, start)))
  changed <- d; changed$questionnaire_navigation <- NULL; brohn_save_study(store, changed, saved$revision)
  check("saved release retains opt-in after draft changes", !is.null(.brohn_delivery_start(store, release$token, start)$protocol$design$questionnaire_navigation))
  tick <- 0; instance <- "original-review-clock"; origin <- "1000000"; sequence <- 0L; journal <- list(); latest_request <- NULL
  sid <- function(qid) Filter(function(s) identical(s$type, "question") && identical(s$question$id, qid), p$timeline)[[1L]]$id
  event <- function(type, id = NULL, payload) {
    tick <<- tick+100; step <- if (is.null(id)) NULL else brohn_find(p$timeline, id)
    list(sequence = sequence+1L, id = paste0("original-review-event-", sequence+1L), type = type, step_id = id,
      stimulus_id = step$stimulus_id, condition_id = step$condition_id, question_id = if (identical(step$type, "question")) step$question$id else NULL,
      phase = if (is.null(step)) "session" else step$phase,
      clock = list(id = "browser-monotonic", unit = "ms", value = as.character(tick), instance_id = instance, time_origin_ms = origin), payload = payload)
  }
  send <- function(e) {
    request <- list(operation_id = paste0("original-review-operation-", e$sequence), events = list(e))
    result <- .brohn_delivery_receive(store, first$run_id, first$access_token, request)
    sequence <<- e$sequence; packet <<- result$questionnaire; journal[[length(journal)+1L]] <<- e; latest_request <<- request; result
  }
  transition <- function(kind, id, ...) event("questionnaire_event", id,
    c(list(schema = "brohn-questionnaire-event/1.0", kind = kind, occurrence_id = packet$latest_occurrence$id,
      state_version = packet$latest_occurrence$state_version), list(...)))
  visit <- function(id, reason) send(transition("visit", id, visit_id = paste0("original-visit-", sequence+1L), reason = reason,
    from_visit_id = packet$latest_occurrence$visit$id))
  commit <- function(value) {
    v <- packet$latest_occurrence$visit; row <- Filter(function(r) identical(r$step_id, v$step_id), packet$resume_page$records)[[1L]]
    elapsed <- tick+100-as.numeric(v$onset_ms)
    send(transition("commit", v$step_id, visit_id = v$id, previous_answer_event_id = row$last_answer_event_id,
      dependency_generation = row$dependency_generation, value = value,
      response_time_ms = if (is.null(row$last_answer_event_id) && !v$resumed) elapsed else NULL,
      active_segment_response_ms = elapsed, resumed = v$resumed))
  }
  seal <- function() send(transition("seal", packet$latest_occurrence$review_step_id, visit_id = packet$latest_occurrence$visit$id,
    projection_hash = packet$latest_occurrence$projection_hash))
  check("legacy start cannot bypass revision boundary", rejected(send(event("step_started", sid(driver$id), list(resumed = FALSE))), "questionnaire"))
  visit(packet$actions$enter_step_id, "enter"); commit(0)
  visit(packet$actions$next_step_id, "next"); commit("Earlier dependent answer")
  visit(packet$actions$back_step_id, "back"); commit(FALSE)
  row <- Filter(function(r) r$question_id == follow$id, packet$resume_page$records)[[1L]]
  check("changed false driver hides and clears original zero-branch answer", is.null(row$value) && row$status == "not_displayed" && row$invalidated && row$dependency_generation == 2L)
  check("original dependent predecessor remains evidence", !is.null(row$last_answer_event_id) && row$answer_version == 1L)
  before_hash <- packet$state_hash
  check("receipt replay returns same current version without a new event", identical(brohn_json(.brohn_delivery_receive(store, first$run_id, first$access_token, latest_request)$questionnaire), brohn_json(packet)) && length(brohn_run_events(store, first$run_id)) == sequence)
  stale <- transition("visit", packet$actions$next_step_id, visit_id = "stale-version-visit", reason = "next", from_visit_id = packet$latest_occurrence$visit$id)
  stale$payload$state_version <- 0L
  check("fresh event with stale questionnaire version is atomically rejected", rejected(send(stale), "state changed") && length(brohn_run_events(store, first$run_id)) == sequence)
  visit(packet$actions$next_step_id, "next")
  send(transition("acknowledge", sid(info$id), visit_id = packet$latest_occurrence$visit$id))
  visit(packet$actions$next_step_id, "next"); commit(NULL)
  visit(packet$actions$next_step_id, "next")
  check("review offers only reached visible edits and explicit seal", packet$actions$can_seal && !sid(follow$id) %in% unlist(packet$actions$editable_step_ids))
  bad <- transition("seal", packet$latest_occurrence$review_step_id, visit_id = packet$latest_occurrence$visit$id, projection_hash = strrep("0", 64))
  check("seal binds the current opaque server projection hash", rejected(send(bad), "projection changed"))
  before_id <- packet$latest_occurrence$id; seal()
  check("adjacent assessment packet retains prior seal and next entry separately", packet$last_transition$sealed && identical(packet$last_transition$occurrence_id, before_id) &&
    !identical(packet$latest_occurrence$id, before_id) && !is.null(packet$actions$enter_step_id))
  visit(packet$actions$enter_step_id, "enter"); commit(2); visit(packet$actions$next_step_id, "next"); commit(4); visit(packet$actions$next_step_id, "next")
  visit(sid(items[[1]]$id), "edit"); commit(6); visit(packet$actions$next_step_id, "next")
  initial <- .brohn_delivery_start(store, release$token, start)
  check("actual start resume returns acknowledged current visit and all exact records", identical(brohn_json(initial$resume$questionnaire), brohn_json(packet)))
  old_hash <- packet$state_hash; instance <- "original-review-clock-restarted"; origin <- "2000000"; tick <- 0
  visit(packet$latest_occurrence$visit$step_id, "resume"); commit(4); visit(packet$actions$next_step_id, "next")
  check("new page confirmation does not add another scored value", Filter(function(r) r$question_id == items[[2]]$id, packet$resume_page$records)[[1L]]$answer_version == 1L)
  check("paged state rejects changed snapshot and foreign authorization", rejected(.brohn_delivery_questionnaire_state(store, first$run_id, first$access_token, list(offset = 0L, state_hash = old_hash)), "changed") &&
    rejected(.brohn_delivery_questionnaire_state(store, first$run_id, strrep("0", 64), list(offset = 0L, state_hash = NULL)), "access"))
  check("current paged state matches the acknowledged canonical packet", identical(brohn_json(.brohn_delivery_questionnaire_state(store, first$run_id, first$access_token,
    list(offset = 0L, state_hash = packet$state_hash))), brohn_json(packet)))
  seal(); send(event("run_finished", payload = list(outcome = "completed")))
  .brohn_delivery_finish(store, first$run_id, first$access_token, list(operation_id = "original-review-finish", outcome = "completed", final_sequence = sequence))
  run <- brohn_run(store, first$run_id); recorded <- brohn_run_events(store, first$run_id)
  check("completion retains every acknowledged original transition", run$completion_status == "completed" && identical(brohn_json(recorded), brohn_json(journal)))
  input <- list(design = d, runs = list(run), events = setNames(list(recorded), run$id))
  report <- brohn_analyse_runs(input); a <- report$analysis; projection <- a$questionnaire_revision$runs[[1L]]
  check("explicit summaries use final six once instead of earlier two", Filter(function(f) f$question_id == items[[1]]$id, a$features)[[1L]]$numeric_response_mean == 6 &&
    Filter(function(f) f$question_id == items[[1]]$id, a$features)[[1L]]$response_count == 1L)
  check("independent final scale is (six plus four)/two = five", length(a$scales$observations) == 1L && a$scales$observations[[1L]]$status == "scored" && a$scales$observations[[1L]]$value == 5)
  check("hidden follow-up and information never become ordinary response rows", !any(vapply(a$observations, function(r) r$question_id %in% c(follow$id, info$id), logical(1))) && a$quality$response_count == 4L)
  item <- Filter(function(r) r$question_id == items[[1]]$id, projection$effective_records)[[1L]]
  check("revised final answer retains explicit history and no initial RT", item$revision_count == 1L && is.null(item$response_time_ms) && item$active_segment_response_ms == 100 &&
    length(projection$history_events) == length(projection$history_records) && length(projection$invalidations) == 1L)
  check("all original edit values remain separate from effective score input", any(vapply(projection$history_events, function(e) identical(e$payload$value, "Earlier dependent answer"), logical(1))) &&
    identical(projection$projection_hash, brohn_hash(projection$effective_records)))
  partial <- recorded[-length(recorded)]
  check("canonical scoring rejects incomplete journals", rejected(brohn_questionnaire_run_projection(run, partial), "complete receiver journal"))
  check("report view names final answers and complete history", grepl("Reviewed questionnaire answers", htmltools::renderTags(brohn_report_content(report))$html, fixed = TRUE))
  old <- d; old$questionnaire_navigation <- NULL
  check("legacy compiler bytes remain unchanged", identical(brohn_json(brohn_compile(old)), legacy_bytes))
  # Keep automatic jobs explicit: direct-analysis checks above do not claim a worker.
  jobs <- brohn_list_jobs(store); for (job in jobs) if (job$status == "queued") brohn_cancel_job(store, job$id)
  check("receiver fixture leaves no running or queued scientific work", !any(vapply(brohn_list_jobs(store), function(j) j$status %in% c("queued", "running"), logical(1))))
  cat(sprintf("PASS: %d questionnaire revision compiler/receiver/receipt/projection/scale checks\n", checks))
})
