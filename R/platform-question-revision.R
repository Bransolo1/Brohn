# Pure, opt-in questionnaire revision. The receiver owns transport idempotency,
# external step progression, timed evidence and the complete immutable journal.
brohn_questionnaire_navigation <- function() list(schema = "brohn-questionnaire-navigation/1.0",
  profile = "within-occurrence-revision/1.0", dependent_answers = "clear-transitive-on-change", seal = "explicit-review")

brohn_validate_questionnaire_navigation <- function(policy) {
  brohn_fields(policy, c("schema", "profile", "dependent_answers", "seal"), label = "Questionnaire navigation")
  brohn_require(identical(brohn_json(policy), brohn_json(brohn_questionnaire_navigation())),
    "Choose the registered within-occurrence revision policy; dependent answers clear on change and review seals the assessment.")
  invisible(TRUE)
}
.brohn_revision_map <- function() structure(list(), names = character())
.brohn_revision_refs <- function(rule) {
  if (is.null(rule)) return(character())
  if (rule$op %in% c("and", "or")) return(unique(unlist(lapply(rule$rules, .brohn_revision_refs), use.names = FALSE)))
  if (rule$op == "not") return(.brohn_revision_refs(rule[["rule"]]))
  rule$question_id
}
.brohn_revision_equal <- function(a, b) identical(brohn_json(a), brohn_json(b))
.brohn_revision_source <- function(protocol) {
  brohn_require(is.list(protocol) && is.list(protocol$design) && brohn_array(protocol$timeline), "Choose a frozen participant protocol.")
  d <- protocol$design; brohn_validate_questionnaire_navigation(d$questionnaire_navigation)
  base <- d; base$questionnaire_navigation <- NULL; brohn_validate_design(base, publish = TRUE)
  brohn_require(identical(protocol$design_hash, brohn_hash(d)), "Questionnaire revision requires the exact frozen design hash.")
  brohn_require(brohn_number(protocol$allocation_index, 1, 1e9, TRUE), "Keep the exact original participant allocation index.")
  brohn_require(length(protocol$timeline) <= 20000L && !anyDuplicated(brohn_ids(protocol$timeline)) &&
    all(vapply(protocol$timeline, function(s) brohn_valid_id(s$id) && brohn_text(s$type, 64), logical(1))),
    "The questionnaire protocol needs unique valid step IDs within the 20,000-step limit.")
}

brohn_questionnaire_revision_decorate <- function(protocol) {
  if (!"questionnaire_navigation" %in% names(protocol$design)) return(protocol)
  .brohn_revision_source(protocol)
  brohn_require(is.null(protocol$questionnaire_occurrences) && !any(vapply(protocol$timeline,
    function(s) identical(s$type, "questionnaire_review") || !is.null(s$questionnaire_occurrence_id), logical(1))),
    "Decorate the original assigned timeline once, before publishing its revision manifest.")
  original <- protocol$timeline; result <- list(); manifests <- list(); anchor <- NULL; position <- 1L
  policy_hash <- brohn_hash(protocol$design$questionnaire_navigation)
  seen_whole <- character()
  while (position <= length(original)) {
    step <- original[[position]]
    if (step$type != "question") {
      if (step$type == "stimulus") anchor <- step
      result[[length(result)+1L]] <- step; position <- position+1L; next
    }
    scope <- step$question$scope; start <- position; members <- list()
    if (scope == "before") brohn_require(is.null(anchor), "Before-study revision cannot be placed after an observed stimulus.")
    if (scope == "after_each") brohn_require(!is.null(anchor) && identical(anchor$stimulus_id, step$stimulus_id) &&
      identical(anchor$condition_id, step$condition_id), "After-stimulus revision needs the exact preceding stimulus step.")
    if (scope != "after_each") {
      brohn_require(!scope %in% seen_whole, "Before/end questions must each form one contiguous questionnaire occurrence.")
      seen_whole <- c(seen_whole, scope)
    }
    while (position <= length(original)) {
      s <- original[[position]]
      if (s$type != "question" || !identical(s$question$scope, scope)) break
      q <- s$question; source <- brohn_find(protocol$design$questions, q$id)
      reference <- q; reference$options <- source$options
      brohn_require(!is.null(source) && .brohn_revision_equal(reference, source) &&
        setequal(vapply(q$options, brohn_hash, character(1)), vapply(source$options, brohn_hash, character(1))),
        "A revision question differs from its frozen design or assigned typed options.")
      options <- source$options
      if (isTRUE(source$randomize_options) && length(options)) {
        if (identical(source$option_assignment, "participant-sha256/1.0")) options <- .brohn_participant_options(source,
          protocol$design$seed, protocol$allocation_index, s$stimulus_id) else
          options <- brohn_seeded(((protocol$design$seed+position-1L) %% (.Machine$integer.max-1L))+1L, function() sample(options))
      }
      brohn_require(.brohn_revision_equal(q$options, options), "Question options differ from their exact original participant assignment.")
      brohn_require(identical(s$phase, "active_response") && identical(s$stimulus_id, step$stimulus_id) &&
        identical(s$condition_id, step$condition_id) && (scope == "after_each" || (is.null(s$stimulus_id) && is.null(s$condition_id))),
        "One questionnaire occurrence cannot mix assessment identities or timing phases.")
      members[[length(members)+1L]] <- s; position <- position+1L
    }
    qids <- vapply(members, function(s) s$question$id, character(1))
    brohn_require(!anyDuplicated(qids) && length(qids) <= 200L, "Use each question once in an occurrence, with at most 200 member questions.")
    sectioned <- "questionnaire_sections" %in% names(protocol$design)
    plan <- if (sectioned) .brohn_question_sections_plan_validated(protocol$design, protocol$allocation_index, scope,
      if (scope == "after_each") step$stimulus_id else NULL, protocol$design_hash, brohn_hash(protocol$design$questionnaire_sections)) else
      list(entries = lapply(Filter(function(q) q$scope == scope, protocol$design$questions), function(q) list(question = q, questionnaire = NULL)))
    brohn_require(identical(qids, vapply(plan$entries, function(entry) entry$question$id, character(1))) &&
      all(vapply(seq_along(members), function(i) .brohn_revision_equal(members[[i]]$questionnaire, plan$entries[[i]]$questionnaire), logical(1))),
      "Question order and section labels must match the exact frozen participant assignment.")
    dependencies <- lapply(members, function(s) list(question_id = s$question$id, references = as.list(.brohn_revision_refs(s$question$show_if)), rule_hash = brohn_hash(s$question$show_if)))
    for (i in seq_along(members)) for (ref in .brohn_revision_refs(members[[i]]$question$show_if)) {
      rq <- brohn_find(protocol$design$questions, ref)
      brohn_require(!is.null(rq) && ((rq$scope == "before" && scope != "before") || ref %in% head(qids, i-1L)),
        paste("Keep display-logic driver", ref, "before", qids[[i]], "within its allowed assessment scope."))
    }
    assignments <- unique(Filter(Negate(is.null), lapply(members, function(s) s$questionnaire$assignment_id)))
    brohn_require(length(assignments) <= 1L, "An occurrence cannot mix frozen section assignments.")
    source_identity <- list(schema = "brohn-questionnaire-occurrence/1.0", design_hash = protocol$design_hash,
      scope = scope, stimulus_step_id = if (scope == "after_each") anchor$id else NULL,
      question_step_ids = as.list(brohn_ids(members)), policy_hash = policy_hash)
    digest <- brohn_hash(source_identity); id <- paste0("qocc-", digest)
    review_id <- paste0("qreview-", digest)
    brohn_require(!review_id %in% brohn_ids(original), "The generated questionnaire review identity collides with an original step.")
    manifest <- c(source_identity, list(id = id, first_question_step_id = members[[1L]]$id,
      stimulus_id = step$stimulus_id, condition_id = step$condition_id, review_step_id = review_id,
      section_assignment_id = if (length(assignments)) assignments[[1L]] else NULL,
      dependencies = dependencies, dependency_graph_hash = brohn_hash(dependencies)))
    manifests[[length(manifests)+1L]] <- manifest
    for (s in members) {s$questionnaire_occurrence_id <- id; result[[length(result)+1L]] <- s}
    result[[length(result)+1L]] <- list(id = review_id, type = "questionnaire_review", phase = "active_response",
      questionnaire_occurrence_id = id, stimulus_id = step$stimulus_id, condition_id = step$condition_id)
  }
  for (scope in c("before", "end")) brohn_require(sum(vapply(manifests, function(m) m$scope == scope, logical(1))) ==
    as.integer(any(vapply(protocol$design$questions, function(q) q$scope == scope, logical(1)))), "A frozen whole-study questionnaire occurrence is missing from the timeline.")
  after <- Filter(function(m) m$scope == "after_each", manifests)
  stimulus_steps <- Filter(function(s) s$type == "stimulus", original)
  expected_after <- if (any(vapply(protocol$design$questions, function(q) q$scope == "after_each", logical(1)))) brohn_ids(stimulus_steps) else character()
  actual_after <- vapply(after, `[[`, character(1), "stimulus_step_id")
  brohn_require(!anyDuplicated(actual_after) && setequal(actual_after, expected_after), "Each original stimulus step needs exactly its assigned after-stimulus questionnaire occurrence.")
  total <- length(result)+sum(vapply(Filter(function(s) identical(s$type, "task"), result), function(s) length(s$task$timeline), integer(1)))
  brohn_require(total <= 20000L, "Questionnaire review steps make this protocol exceed 20,000 supported steps. Reduce the design before release.")
  protocol$timeline <- result; protocol$questionnaire_occurrences <- manifests; protocol
}

# A locked environment is an immutable validated in-process cache, never a JSON
# upload. Build it once at receive/replay boundaries, not once per event.
brohn_questionnaire_revision_context <- function(protocol, expected_protocol_hash = NULL) {
  if (inherits(protocol, "brohn_questionnaire_revision_context") && is.environment(protocol) && environmentIsLocked(protocol)) {
    brohn_require(is.null(expected_protocol_hash) || identical(expected_protocol_hash, protocol$protocol_hash), "The cached questionnaire contract differs from the retained protocol hash.")
    return(protocol)
  }
  brohn_require(is.null(expected_protocol_hash) || identical(expected_protocol_hash, brohn_hash(protocol)), "The questionnaire protocol differs from its retained source hash.")
  brohn_require(!is.null(protocol$design$questionnaire_navigation), "This protocol uses legacy forward-only questionnaire delivery.")
  base <- protocol; base$questionnaire_occurrences <- NULL
  base$timeline <- lapply(Filter(function(s) !identical(s$type, "questionnaire_review"), base$timeline), function(s) {s$questionnaire_occurrence_id <- NULL; s})
  expected <- brohn_questionnaire_revision_decorate(base)
  brohn_require(identical(brohn_hash(expected), brohn_hash(protocol)), "Questionnaire occurrence metadata differs from the exact frozen timeline and policy.")
  ctx <- new.env(parent = emptyenv())
  ctx$protocol_hash <- brohn_hash(protocol); ctx$design_hash <- protocol$design_hash
  ctx$policy_hash <- brohn_hash(protocol$design$questionnaire_navigation)
  ctx$steps <- setNames(protocol$timeline, brohn_ids(protocol$timeline))
  ctx$indices <- setNames(as.list(seq_along(protocol$timeline)), brohn_ids(protocol$timeline))
  ctx$manifests <- setNames(protocol$questionnaire_occurrences, brohn_ids(protocol$questionnaire_occurrences))
  ctx$question_limit <- 200L; ctx$event_limit <- 10000000L; ctx$transport_bytes <- 4L*1024L^2L
  class(ctx) <- "brohn_questionnaire_revision_context"; lockEnvironment(ctx, bindings = TRUE); ctx
}

brohn_questionnaire_revision_new <- function(protocol) {
  ctx <- brohn_questionnaire_revision_context(protocol)
  list(schema = "brohn-questionnaire-revision-state/1.0", protocol_hash = ctx$protocol_hash, policy_hash = ctx$policy_hash,
    active_occurrence_id = NULL, occurrences = .brohn_revision_map(), event_count = 0L, visit_count = 0L,
    last_sequence = 0L, clocks = .brohn_revision_map(), event_ids = .brohn_revision_map(), visit_ids = .brohn_revision_map(), history = list(), invalidations = list())
}
.brohn_revision_state <- function(state, ctx) {
  brohn_require(is.list(state) && identical(state$schema, "brohn-questionnaire-revision-state/1.0") &&
    identical(state$protocol_hash, ctx$protocol_hash) && identical(state$policy_hash, ctx$policy_hash), "Revision state belongs to a different frozen protocol.")
}
.brohn_revision_occurrence <- function(manifest) {
  records <- .brohn_revision_map()
  for (id in unlist(manifest$question_step_ids, use.names = FALSE)) records[[id]] <- list(head = NULL,
    last_answer_event_id = NULL, first_answer_event_id = NULL, answer_version = 0L, dependency_generation = 0L,
    acknowledged = FALSE, ever_visited = FALSE, invalidated = FALSE)
  list(id = manifest$id, version = 0L, sealed = FALSE, visit = NULL, records = records)
}
.brohn_revision_visible <- function(state, occurrence, manifest, ctx) {
  answers <- .brohn_revision_map()
  if (manifest$scope != "before") for (other in state$occurrences) {
    m <- ctx$manifests[[other$id]]
    if (m$scope == "before") {
      brohn_require(isTRUE(other$sealed), "Before-study answers must be sealed before a later questionnaire assessment.")
      for (sid in names(other$records)) if (!is.null(other$records[[sid]]$head))
        answers[ctx$steps[[sid]]$question$id] <- list(other$records[[sid]]$head$value)
    }
  }
  visible <- character()
  for (sid in unlist(manifest$question_step_ids, use.names = FALSE)) {
    q <- ctx$steps[[sid]]$question
    if (brohn_rule(q$show_if, answers)) {
      visible <- c(visible, sid)
      if (!is.null(occurrence$records[[sid]]$head)) answers[q$id] <- list(occurrence$records[[sid]]$head$value)
    }
  }
  visible
}
.brohn_revision_done <- function(record, step) if (step$question$type == "information") isTRUE(record$acknowledged) else !is.null(record$head)
.brohn_revision_rows <- function(state, occurrence, manifest, ctx) {
  visible <- .brohn_revision_visible(state, occurrence, manifest, ctx)
  lapply(unlist(manifest$question_step_ids, use.names = FALSE), function(sid) {
    step <- ctx$steps[[sid]]; item <- occurrence$records[[sid]]; head <- item$head
    shown <- sid %in% visible; information <- step$question$type == "information"
    status <- if (!shown) "not_displayed" else if (information) if (item$acknowledged) "information_acknowledged" else "information_unacknowledged" else
      if (!is.null(head)) if (is.null(head$value)) "optional_omission" else "answered" else if (item$invalidated) "invalidated_unanswered" else "not_submitted"
    list(occurrence_id = manifest$id, question_id = step$question$id, step_id = sid, exposure_id = sid,
      scope = manifest$scope, assessment_id = if (manifest$scope == "after_each") paste0("stimulus-step:", manifest$stimulus_step_id) else paste0("scope:", manifest$scope),
      assessment_exposure_id = manifest$stimulus_step_id, stimulus_id = manifest$stimulus_id, condition_id = manifest$condition_id,
      information = information, status = status, value = if (is.null(head) || !shown) NULL else head$value,
      missing_reason = if (status == "answered") NULL else status, ever_visited = item$ever_visited,
      invalidated = item$invalidated, dependency_generation = item$dependency_generation,
      event_id = if (is.null(head) || !shown) NULL else head$event_id, last_answer_event_id = item$last_answer_event_id,
      first_answer_event_id = item$first_answer_event_id, answer_version = item$answer_version, revision_count = max(0L, item$answer_version-1L),
      sequence = if (is.null(head) || !shown) NULL else head$sequence,
      response_time_ms = if (is.null(head) || !shown) NULL else head$response_time_ms,
      active_segment_response_ms = if (is.null(head) || !shown) NULL else head$active_segment_response_ms,
      resumed = if (is.null(head) || !shown) NULL else head$resumed)
  })
}
.brohn_revision_clock <- function(clock) {
  brohn_fields(clock, c("id", "unit", "value", "instance_id", "time_origin_ms"), label = "Questionnaire event clock")
  decimal <- function(x) brohn_text(x, 64) && grepl("^[0-9]+(\\.[0-9]+)?$", x) && is.finite(suppressWarnings(as.numeric(x)))
  brohn_require(identical(clock$id, "browser-monotonic") && identical(clock$unit, "ms") && decimal(clock$value) &&
    decimal(clock$time_origin_ms) && as.numeric(clock$value) <= 1e12 && brohn_text(clock$instance_id, 128), "Use the actual page monotonic clock and its instance identity.")
  as.numeric(clock$value)
}

brohn_questionnaire_revision_apply <- function(state, event, protocol, protocol_cursor) {
  ctx <- brohn_questionnaire_revision_context(protocol); .brohn_revision_state(state, ctx)
  brohn_fields(event, c("sequence", "id", "type", "step_id", "stimulus_id", "condition_id", "question_id", "phase", "clock", "payload"), label = "Questionnaire event")
  brohn_require(identical(event$type, "questionnaire_event") && brohn_number(event$sequence, 1, ctx$event_limit, TRUE) &&
    event$sequence > state$last_sequence && brohn_text(event$id, 128), "Use a new ordered questionnaire event; transport retries belong to the receiver's existing ACK path.")
  brohn_require(state$event_count < ctx$event_limit && nchar(brohn_json(event), type = "bytes") <= ctx$transport_bytes,
    "The questionnaire event exceeds the existing run or transport limits; preserve the journal and end explicitly.")
  brohn_require(is.null(state$event_ids[[event$id]]), "A questionnaire event identity cannot be reused at another sequence.")
  p <- event$payload
  brohn_require(is.list(p) && brohn_text(p$kind, 32) && p$kind %in% c("visit", "commit", "acknowledge", "seal"), "Choose a supported questionnaire transition.")
  common <- c("schema", "kind", "occurrence_id", "state_version")
  fields <- switch(p$kind, visit = c("visit_id", "reason", "from_visit_id"),
    commit = c("visit_id", "previous_answer_event_id", "dependency_generation", "value", "response_time_ms", "active_segment_response_ms", "resumed"),
    acknowledge = "visit_id", seal = c("visit_id", "projection_hash"))
  brohn_fields(p, c(common, fields), optional = c("clock_segment_id", "time_origin_ms"), label = "Questionnaire transition")
  brohn_require(identical(p$schema, "brohn-questionnaire-event/1.0") && brohn_text(p$occurrence_id, 96) &&
    brohn_number(p$state_version, 0, ctx$event_limit, TRUE), "Questionnaire transition needs its named version and occurrence.")
  manifest <- ctx$manifests[[p$occurrence_id]]; step <- ctx$steps[[event$step_id]]
  brohn_require(!is.null(manifest) && !is.null(step) && identical(step$questionnaire_occurrence_id, manifest$id) &&
    identical(event$phase, step$phase) && identical(event$stimulus_id, step$stimulus_id) && identical(event$condition_id, step$condition_id) &&
    identical(event$question_id, if (step$type == "question") step$question$id else NULL), "Questionnaire event has a foreign assessment, step or typed source reference.")
  brohn_require(brohn_number(protocol_cursor, 1, length(ctx$steps)+1L, TRUE), "Supply the receiver-owned current protocol cursor.")
  occurrence <- state$occurrences[[manifest$id]]
  if (is.null(occurrence)) {
    brohn_require(is.null(state$active_occurrence_id) && identical(p$kind, "visit") && identical(p$reason, "enter") &&
      protocol_cursor == ctx$indices[[manifest$first_question_step_id]], "The receiver has not reached this questionnaire occurrence; timed boundaries cannot be crossed.")
    occurrence <- .brohn_revision_occurrence(manifest)
  }
  brohn_require(!isTRUE(occurrence$sealed) && (is.null(state$active_occurrence_id) || identical(state$active_occurrence_id, manifest$id)) &&
    protocol_cursor == ctx$indices[[manifest$first_question_step_id]], "Only the current unsealed occurrence can be edited; the receiver owns timed progression.")
  brohn_require(p$state_version == occurrence$version, "The questionnaire state changed. Retry or resume its current acknowledged version.")
  time <- .brohn_revision_clock(event$clock); clock <- state$clocks[[event$clock$instance_id]]
  brohn_require((is.null(p$clock_segment_id) || identical(p$clock_segment_id, event$clock$instance_id)) &&
    (is.null(p$time_origin_ms) || identical(p$time_origin_ms, event$clock$time_origin_ms)), "Redundant runner clock fields must match the actual event clock.")
  brohn_require(is.null(clock) || (identical(clock$origin, event$clock$time_origin_ms) && time >= clock$time), "Questionnaire clock reversed or changed origin within a page instance.")
  state$clocks[[event$clock$instance_id]] <- list(origin = event$clock$time_origin_ms, time = time)
  visible <- .brohn_revision_visible(state, occurrence, manifest, ctx); visit <- occurrence$visit
  effects <- list(clear_draft_step_ids = list(), invalidated_step_ids = list(), sealed = FALSE, confirmation = FALSE)
  if (p$kind == "visit") {
    brohn_require(brohn_text(p$visit_id, 128) && is.null(state$visit_ids[[p$visit_id]]) &&
      state$visit_count < ctx$event_limit, "Use a fresh bounded questionnaire visit identity.")
    brohn_require(brohn_text(p$reason, 32) && p$reason %in% c("enter", "next", "back", "edit", "resume") &&
      identical(p$from_visit_id, if (is.null(visit)) NULL else visit$id), "Navigation must name its actual preceding visit.")
    target <- event$step_id; review <- manifest$review_step_id
    if (is.null(visit)) {
      expected <- if (length(visible)) visible[[1L]] else review
      brohn_require(p$reason == "enter" && identical(target, expected), "Enter at the first currently visible question or its empty review.")
    } else if (p$reason == "resume") {
      brohn_require(identical(target, visit$step_id) && !identical(event$clock$instance_id, visit$instance_id), "Resume the current questionnaire visit on a new page clock.")
    } else {
      brohn_require(identical(event$clock$instance_id, visit$instance_id) && identical(event$clock$time_origin_ms, visit$time_origin_ms), "Use explicit resume before navigating on a new page clock.")
      current_index <- if (identical(visit$step_id, review)) length(visible)+1L else match(visit$step_id, visible)
      brohn_require(!is.na(current_index), "The current question is no longer visible; restore the validated questionnaire target.")
      if (p$reason == "next") {
        brohn_require(!identical(visit$step_id, review) && isTRUE(visit$committed), "Continue after this visit's valid answer or information acknowledgement.")
        expected <- if (current_index < length(visible)) visible[[current_index+1L]] else review
        brohn_require(identical(target, expected), "Continue in the current realised visible question order.")
      } else if (p$reason == "back") {
        eligible <- if (current_index > 1L) head(visible, current_index-1L) else character()
        eligible <- Filter(function(sid) occurrence$records[[sid]]$ever_visited, eligible)
        brohn_require(length(eligible) > 0L && identical(target, tail(eligible, 1L)), "Back is limited to the previous visible reached question in this occurrence.")
      } else if (p$reason == "edit") brohn_require(identical(visit$step_id, review) && target %in% visible && occurrence$records[[target]]$ever_visited,
        "Edit only a reached visible question from this occurrence's review.") else brohn_stop("An existing occurrence cannot be entered again.")
    }
    occurrence$visit <- list(id = p$visit_id, step_id = target, instance_id = event$clock$instance_id, time_origin_ms = event$clock$time_origin_ms,
      onset_ms = event$clock$value, resumed = p$reason == "resume", committed = FALSE)
    if (target != review) occurrence$records[[target]]$ever_visited <- TRUE
    state$visit_count <- state$visit_count+1L
    state$visit_ids[[p$visit_id]] <- TRUE
  } else {
    brohn_require(!is.null(visit) && identical(p$visit_id, visit$id) && identical(event$step_id, visit$step_id) &&
      identical(event$clock$instance_id, visit$instance_id) && identical(event$clock$time_origin_ms, visit$time_origin_ms), "The transition must belong to the actual current clock-bound visit.")
    if (p$kind == "seal") {
      brohn_require(identical(event$step_id, manifest$review_step_id), "Seal only from the occurrence review screen.")
      brohn_require(all(vapply(visible, function(sid) .brohn_revision_done(occurrence$records[[sid]], ctx$steps[[sid]]), logical(1))),
        "Answer or explicitly omit every visible question and acknowledge information before sealing.")
      rows <- .brohn_revision_rows(state, occurrence, manifest, ctx)
      brohn_require(identical(p$projection_hash, brohn_hash(rows)), "Review projection changed; show its current effective answers before sealing.")
      occurrence$sealed <- TRUE; occurrence$seal_event_id <- event$id; occurrence$seal_sequence <- event$sequence
      occurrence$projection_hash <- p$projection_hash; effects$sealed <- TRUE
      protocol_cursor <- ctx$indices[[manifest$review_step_id]]+1L
    } else {
      brohn_require(step$type == "question" && event$step_id %in% visible && !isTRUE(visit$committed), "One current visible question may be committed once per visit.")
      item <- occurrence$records[[event$step_id]]
      if (p$kind == "acknowledge") {
        brohn_require(step$question$type == "information", "Only an information question accepts acknowledgement instead of an answer.")
        item$acknowledged <- TRUE; item$invalidated <- FALSE
      } else {
        brohn_require(step$question$type != "information" && identical(p$previous_answer_event_id, item$last_answer_event_id) &&
          brohn_number(p$dependency_generation, 0, ctx$event_limit, TRUE) && p$dependency_generation == item$dependency_generation,
          "The answer must name its current history predecessor and dependency generation.")
        brohn_require(is.logical(p$resumed) && length(p$resumed) == 1L && !is.na(p$resumed) && identical(p$resumed, visit$resumed), "Declare the actual resumed visit state.")
        elapsed <- time-as.numeric(visit$onset_ms)
        brohn_require(brohn_number(p$active_segment_response_ms, 0, 1e12) && abs(p$active_segment_response_ms-elapsed) <= 0.001,
          "Active response time must match this visit's observed clock interval.")
        prior <- !is.null(item$last_answer_event_id)
        if (prior || visit$resumed) brohn_require(is.null(p$response_time_ms), "Revised or resumed answers cannot claim initial uninterrupted response time.") else
          brohn_require(brohn_number(p$response_time_ms, 0, 1e12) && abs(p$response_time_ms-elapsed) <= 0.001,
            "Initial response time must match its actual uninterrupted visit.")
        brohn_require(exists(".brohn_delivery_answer", mode = "function"), "Load the existing typed questionnaire-answer validator before receiving revisions.")
        value <- .brohn_delivery_answer(step$question, list(value = p$value, response_time_ms = p$response_time_ms,
          active_segment_response_ms = p$active_segment_response_ms, resumed = p$resumed))
        confirmation <- !is.null(item$head) && .brohn_revision_equal(item$head$value, value)
        effects$confirmation <- confirmation
        if (!confirmation) {
          item$head <- list(event_id = event$id, sequence = event$sequence, value = value, response_time_ms = p$response_time_ms,
            active_segment_response_ms = p$active_segment_response_ms, resumed = p$resumed, visit_id = visit$id)
          item$last_answer_event_id <- event$id
          if (is.null(item$first_answer_event_id)) item$first_answer_event_id <- event$id
          item$answer_version <- item$answer_version+1L; item$invalidated <- FALSE
          occurrence$records[[event$step_id]] <- item
          # First committed drivers can invalidate locally drafted dependents too;
          # no previous effective answer is resurrected on any routing change.
          descendants <- step$question$id
          for (dep in manifest$dependencies) if (any(unlist(dep$references, use.names = FALSE) %in% descendants)) descendants <- c(descendants, dep$question_id)
          affected <- setdiff(descendants, step$question$id)
          for (sid in unlist(manifest$question_step_ids, use.names = FALSE)) if (ctx$steps[[sid]]$question$id %in% affected) {
            old <- occurrence$records[[sid]]
            old$dependency_generation <- old$dependency_generation+1L
            if (!is.null(old$head) || isTRUE(old$acknowledged)) {
              state$invalidations[[length(state$invalidations)+1L]] <- list(occurrence_id = manifest$id, step_id = sid,
                question_id = ctx$steps[[sid]]$question$id, cause_event_id = event$id, previous_head_event_id = if (is.null(old$head)) NULL else old$head$event_id,
                rule_hash = brohn_hash(ctx$steps[[sid]]$question$show_if), policy_hash = ctx$policy_hash, dependency_generation = old$dependency_generation)
              old$invalidated <- TRUE
              effects$invalidated_step_ids[[length(effects$invalidated_step_ids)+1L]] <- sid
            }
            old["head"] <- list(NULL); old$acknowledged <- FALSE; occurrence$records[[sid]] <- old
            effects$clear_draft_step_ids[[length(effects$clear_draft_step_ids)+1L]] <- sid
          }
        }
      }
      occurrence$records[[event$step_id]] <- item
      occurrence$visit$committed <- TRUE
    }
  }
  occurrence$version <- occurrence$version+1L
  state$occurrences[[manifest$id]] <- occurrence
  state["active_occurrence_id"] <- list(if (occurrence$sealed) NULL else manifest$id)
  state$event_count <- state$event_count+1L; state$last_sequence <- event$sequence
  state$event_ids[[event$id]] <- TRUE
  state$history[[length(state$history)+1L]] <- list(event_id = event$id, sequence = event$sequence, kind = p$kind,
    occurrence_id = manifest$id, step_id = event$step_id, visit_id = p$visit_id, state_version = p$state_version,
    confirmation = effects$confirmation, source_event_hash = brohn_hash(event))
  list(state = state, protocol_cursor = protocol_cursor, effects = effects)
}

brohn_questionnaire_revision_projection <- function(protocol, state, require_sealed = TRUE) {
  ctx <- brohn_questionnaire_revision_context(protocol); .brohn_revision_state(state, ctx)
  brohn_require(is.logical(require_sealed) && length(require_sealed) == 1L && !is.na(require_sealed), "Declare whether completed sealed assessments are required.")
  if (require_sealed) brohn_require(length(state$occurrences) == length(ctx$manifests) &&
    all(vapply(state$occurrences, function(o) isTRUE(o$sealed), logical(1))), "Completed analysis requires every questionnaire occurrence to be sealed.")
  rows <- list()
  for (manifest in ctx$manifests) {
    occurrence <- state$occurrences[[manifest$id]]
    if (is.null(occurrence)) next
    current <- .brohn_revision_rows(state, occurrence, manifest, ctx)
    if (isTRUE(occurrence$sealed)) brohn_require(identical(occurrence$projection_hash, brohn_hash(current)), "Sealed effective answers no longer match their recorded projection.")
    rows <- c(rows, current)
  }
  list(schema = "brohn-questionnaire-revision-projection/1.0", protocol_hash = ctx$protocol_hash, design_hash = ctx$design_hash,
    policy_hash = ctx$policy_hash, effective_records = rows, projection_hash = brohn_hash(rows), history_records = state$history,
    invalidations = state$invalidations, quality = list(event_count = state$event_count, visit_count = state$visit_count,
      occurrence_count = length(state$occurrences), sealed_occurrence_count = sum(vapply(state$occurrences, function(o) isTRUE(o$sealed), logical(1))),
      history_values = "join exact source event IDs and hashes to the retained immutable journal; history references never replace source bytes"))
}

brohn_questionnaire_revision_resume <- function(protocol, state, offset = 0L, max_bytes = 3L*1024L^2L) {
  ctx <- brohn_questionnaire_revision_context(protocol); .brohn_revision_state(state, ctx)
  brohn_require(brohn_number(offset, 0, 20000, TRUE) && brohn_number(max_bytes, 1024, 3L*1024L^2L, TRUE), "Choose a bounded questionnaire resume page.")
  all_rows <- list()
  for (manifest in ctx$manifests) if (!is.null(state$occurrences[[manifest$id]])) all_rows <- c(all_rows,
    .brohn_revision_rows(state, state$occurrences[[manifest$id]], manifest, ctx))
  brohn_require(offset <= length(all_rows), "Resume offset exceeds the retained questionnaire records.")
  active <- state$occurrences[[brohn_default(state$active_occurrence_id, "")]]
  result <- list(schema = "brohn-questionnaire-revision-resume/1.0", protocol_hash = ctx$protocol_hash,
    state_hash = brohn_hash(state), active_occurrence_id = state$active_occurrence_id,
    state_version = if (is.null(active)) NULL else active$version, visit = if (is.null(active)) NULL else active$visit,
    visible_step_ids = if (is.null(active)) list() else as.list(.brohn_revision_visible(state, active, ctx$manifests[[active$id]], ctx)),
    records = list(), total_records = length(all_rows), offset = offset, next_offset = NULL)
  brohn_require(nchar(brohn_json(result), type = "bytes") <= max_bytes, "The resume metadata needs a larger supported page budget; never truncate its visible question identities.")
  cursor <- offset
  while (cursor < length(all_rows)) {
    candidate <- result; candidate$records[[length(candidate$records)+1L]] <- all_rows[[cursor+1L]]
    candidate["next_offset"] <- list(if (cursor+1L < length(all_rows)) cursor+1L else NULL)
    if (nchar(brohn_json(candidate), type = "bytes") > max_bytes) break
    result <- candidate; cursor <- cursor+1L
  }
  brohn_require(cursor > offset || cursor == length(all_rows), "One typed answer exceeds this resume-page budget; retrieve it with a larger supported page, never truncate it.")
  brohn_require(nchar(brohn_json(result), type = "bytes") <= max_bytes, "The complete resume page exceeds its declared byte budget.")
  result
}
