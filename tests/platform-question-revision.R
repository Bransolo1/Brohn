# Original pure reducer fixtures. No browser, receiver, store or worker claim.
for (name in c("core", "store", "delivery", "analysis", "scales", "question-sections", "question-revision")) source(paste0("R/platform-", name, ".R"), encoding = "UTF-8")
local({
  checks <- 0L
  check <- function(label, ok) {if (!isTRUE(ok)) stop("FAIL: ", label); checks <<- checks+1L}
  rejects <- function(expr, pattern = NULL) {
    error <- tryCatch({force(expr); NULL}, error = conditionMessage)
    !is.null(error) && (is.null(pattern) || grepl(pattern, error, fixed = TRUE))
  }
  rating <- function(id, scope = "before") brohn_question(paste("Original item", id), "rating", scope, id)
  survey <- function(questions) {d <- brohn_new_design("Original revision fixture", "survey", "study-original-revision"); d$instructions <- ""; d$questions <- questions; d}
  # Existing core deliberately does not yet accept the extension. Tests compile
  # its original timeline first and attach the policy/design hash for decoration.
  assigned <- function(design, allocation = 1L) {
    base <- design; base$questionnaire_navigation <- NULL; p <- brohn_compile(base, allocation)
    p$design <- design; p$design_hash <- brohn_hash(design)
    if ("questionnaire_sections" %in% names(design)) for (i in seq_along(p$questionnaire_assignments)) {
      old <- p$questionnaire_assignments[[i]]
      plan <- .brohn_question_sections_plan_validated(design, allocation, old$scope, old$stimulus_id, p$design_hash, brohn_hash(design$questionnaire_sections))
      p$questionnaire_assignments[[i]] <- plan$manifest
      for (entry in plan$entries) for (j in seq_along(p$timeline)) if (p$timeline[[j]]$type == "question" &&
        identical(p$timeline[[j]]$question$id, entry$question$id) && identical(p$timeline[[j]]$stimulus_id, old$stimulus_id)) p$timeline[[j]]$questionnaire <- entry$questionnaire
    }
    p
  }
  prepare <- function(design) {design$questionnaire_navigation <- brohn_questionnaire_navigation(); brohn_questionnaire_revision_decorate(assigned(design))}
  driver <- function(protocol) {
    d <- new.env(); d$protocol <- protocol; d$ctx <- brohn_questionnaire_revision_context(protocol)
    d$state <- brohn_questionnaire_revision_new(d$ctx); d$cursor <- 1L; d$sequence <- 0L; d$tick <- 0; d$page <- "original-page-1"; d$origin <- "1000000"
    d$current <- function(oid = d$state$active_occurrence_id) d$state$occurrences[[oid]]
    d$event <- function(sid, kind, ..., oid = d$ctx$steps[[sid]]$questionnaire_occurrence_id) {
      d$sequence <- d$sequence+1L; d$tick <- d$tick+100; step <- d$ctx$steps[[sid]]; o <- d$state$occurrences[[oid]]
      list(sequence = d$sequence, id = paste0("original-event-", d$sequence), type = "questionnaire_event", step_id = sid,
        stimulus_id = step$stimulus_id, condition_id = step$condition_id, question_id = if (step$type == "question") step$question$id else NULL,
        phase = step$phase, clock = list(id = "browser-monotonic", unit = "ms", value = as.character(d$tick), instance_id = d$page, time_origin_ms = d$origin),
        payload = c(list(schema = "brohn-questionnaire-event/1.0", kind = kind, occurrence_id = oid, state_version = if (is.null(o)) 0L else o$version), list(...)))
    }
    d$send <- function(event) {result <- brohn_questionnaire_revision_apply(d$state, event, d$ctx, d$cursor); d$state <- result$state; d$cursor <- result$protocol_cursor; result}
    d$visit <- function(sid, reason = "next") {
      oid <- d$ctx$steps[[sid]]$questionnaire_occurrence_id; o <- d$state$occurrences[[oid]]
      event <- d$event(sid, "visit", visit_id = paste0("original-visit-", d$sequence+1L), reason = reason, from_visit_id = if (is.null(o$visit)) NULL else o$visit$id)
      d$send(event)
    }
    d$commit_event <- function(value) {
      o <- d$current(); visit <- o$visit; item <- o$records[[visit$step_id]]; elapsed <- d$tick+100-as.numeric(visit$onset_ms)
      d$event(visit$step_id, "commit", visit_id = visit$id, previous_answer_event_id = item$last_answer_event_id,
        dependency_generation = item$dependency_generation, value = value,
        response_time_ms = if (!is.null(item$last_answer_event_id) || visit$resumed) NULL else elapsed,
        active_segment_response_ms = elapsed, resumed = visit$resumed)
    }
    d$commit <- function(value) d$send(d$commit_event(value))
    d$seal <- function() {
      o <- d$current(); rows <- Filter(function(r) r$occurrence_id == o$id,
        brohn_questionnaire_revision_projection(d$ctx, d$state, FALSE)$effective_records)
      d$send(d$event(o$visit$step_id, "seal", visit_id = o$visit$id, projection_hash = brohn_hash(rows)))
    }
    d
  }
  p0 <- brohn_compile(survey(list(rating("q-a"), rating("q-b"))))
  check("absent policy returns exact old protocol bytes without a field", identical(brohn_json(brohn_questionnaire_revision_decorate(p0)), brohn_json(p0)))
  check("legacy protocol cannot accidentally enter revision state", rejects(brohn_questionnaire_revision_new(p0), "legacy"))
  bad_policy <- brohn_questionnaire_navigation(); bad_policy$dependent_answers <- "keep_stale"
  check("unsupported policy cannot retain stale dependent answers", rejects(brohn_validate_questionnaire_navigation(bad_policy)))
  bad_policy <- brohn_questionnaire_navigation(); bad_policy$back_to_stimulus <- TRUE
  check("undeclared policy fields are refused", rejects(brohn_validate_questionnaire_navigation(bad_policy), "unsupported fields"))
  p <- prepare(p0$design); ctx <- brohn_questionnaire_revision_context(p)
  check("one occurrence adds one explicit untimed review", length(p$questionnaire_occurrences) == 1L && length(p$timeline) == length(p0$timeline)+1L && tail(p$timeline, 1L)[[1L]]$type == "questionnaire_review")
  stripped <- lapply(Filter(function(s) s$type != "questionnaire_review", p$timeline), function(s) {s$questionnaire_occurrence_id <- NULL; s})
  check("decoration keeps exact original step IDs and source questions", identical(brohn_json(stripped), brohn_json(p0$timeline)))
  check("validated context is immutable and reused instead of full per-event hashes", identical(ctx, brohn_questionnaire_revision_context(ctx)) && rejects(ctx$protocol_hash <- "mutated"))
  check("public source boundary checks the retained full protocol hash", identical(ctx, brohn_questionnaire_revision_context(ctx, brohn_hash(p))) && rejects(brohn_questionnaire_revision_context(p, "foreign-retained-hash"), "retained source hash"))
  bad <- p; bad$questionnaire_occurrences[[1]]$question_step_ids <- rev(bad$questionnaire_occurrences[[1]]$question_step_ids)
  check("shape-valid altered manifest is rejected by exact derivation", rejects(brohn_questionnaire_revision_context(bad), "differs"))
  bad <- p; bad$timeline[[1]]$question$options[[1]]$value <- "1"
  check("typed question mutation is rejected at protocol boundary", rejects(brohn_questionnaire_revision_context(bad), "differs"))
  bad <- p; bad$timeline[[1]]$question$options <- rev(bad$timeline[[1]]$question$options)
  check("shape-valid changed option order is rejected against assignment", rejects(brohn_questionnaire_revision_context(bad), "original participant assignment"))
  bad <- p; bad$timeline[1:2] <- rev(bad$timeline[1:2])
  check("shape-valid reordered source question steps cannot define a new manifest", rejects(brohn_questionnaire_revision_context(bad), "Question order"))
  check("double decoration cannot insert additional review steps", rejects(brohn_questionnaire_revision_decorate(p), "once"))
  sectioned <- p0$design; sectioned$questionnaire_sections <- brohn_question_sections_new(sectioned)
  sectioned$questionnaire_sections$sections[[1]]$groups <- lapply(sectioned$questionnaire_sections$sections[[1]]$groups, function(g) {g$placement <- "shuffle"; g})
  sectioned$questionnaire_navigation <- brohn_questionnaire_navigation(); sections_original <- assigned(sectioned)
  sp <- brohn_questionnaire_revision_decorate(sections_original); sc <- brohn_questionnaire_revision_context(sp)
  check("section-assigned groups keep exact frozen labels and question order inside one occurrence", length(sc$manifests) == 1L &&
    identical(brohn_ids(Filter(function(s) s$type == "question", sp$timeline)), brohn_ids(sections_original$timeline)) &&
    all(vapply(seq_along(sections_original$timeline), function(i) identical(sp$timeline[[i]]$questionnaire, sections_original$timeline[[i]]$questionnaire), logical(1))))
  bad <- sp; bad$timeline[[1]]$questionnaire$section_label <- "Unassigned replacement label"
  check("mutated section text cannot be accepted as a shape-only manifest", rejects(brohn_questionnaire_revision_context(bad), "section labels"))
  d <- driver(p); m <- p$questionnaire_occurrences[[1]]; a <- m$question_step_ids[[1]]; b <- m$question_step_ids[[2]]; review <- m$review_step_id
  d$visit(a, "enter"); event <- d$commit_event(2); d$send(event)
  check("transport duplicate is not applied twice by pure reducer", rejects(d$send(event), "ordered"))
  event2 <- d$commit_event(3)
  check("new event cannot commit same visit twice", rejects(d$send(event2), "once per visit"))
  d$visit(b); d$commit(4); d$visit(review)
  d$visit(a, "edit"); e <- d$commit_event(6); bad <- e; bad$payload$response_time_ms <- bad$payload$active_segment_response_ms
  check("changed answers must not claim initial response latency", rejects(d$send(bad), "initial uninterrupted"))
  d$send(e); d$visit(b); confirmed <- d$commit(4); d$visit(review)
  check("unchanged confirmation preserves original independent head", confirmed$effects$confirmation && d$current()$records[[b]]$answer_version == 1L)
  bad <- d$event(review, "seal", visit_id = d$current()$visit$id, projection_hash = paste(rep("0",64), collapse = ""))
  check("seal binds exact currently reviewed values", rejects(d$send(bad), "projection changed"))
  d$seal(); projected <- brohn_questionnaire_revision_projection(ctx, d$state)
  values <- vapply(projected$effective_records, `[[`, numeric(1), "value")
  check("independent two-item oracle is exactly six plus four divided by two", identical(unname(values), c(6,4)) && sum(values)/2 == 5 && length(projected$effective_records) == 2L)
  check("initial submission is not counted as an answer correction", identical(vapply(projected$effective_records, `[[`, numeric(1), "revision_count"), c(1,0)))
  check("revised initial RT is null while the first independent RT survives", is.null(projected$effective_records[[1]]$response_time_ms) && projected$effective_records[[2]]$response_time_ms == 100)
  check("sealed projection keeps full source references without duplicate scoring rows", length(projected$history_records) == d$state$event_count && sum(vapply(projected$history_records, function(h) h$kind == "commit", logical(1))) == 4L)
  sealed_hash <- brohn_hash(d$state)
  check("finished occurrence cannot reopen even under matching references", rejects(d$visit(a, "edit"), "unsealed") && identical(sealed_hash, brohn_hash(d$state)))
  foreign <- prepare(survey(list(rating("q-foreign"))))
  check("state is rejected under another frozen protocol", rejects(brohn_questionnaire_revision_projection(foreign, d$state), "different frozen"))

  # Actual existing scale domain consumes the final projection, with its original
  # one-assessment duplicate safeguards still enabled.
  sd <- p0$design
  sd$scales <- list(list(schema = "brohn-questionnaire-scale/1.0", id = "original-mean", label = "Original arithmetic mean", version = "original/1",
    source = "Original arithmetic fixture, not a psychological instrument", scope = "before",
    items = list(list(question_id = "q-a", reverse = FALSE, min = 1, max = 7), list(question_id = "q-b", reverse = FALSE, min = 1, max = 7)),
    scoring = list(aggregation = "mean", missing = "complete", minimum_answered = 2L, prorate = FALSE), conversion = NULL))
  rows <- lapply(projected$effective_records, function(r) c(r, list(participant_id = "original-person", session_id = "original-session", participant_linkage = TRUE, origin = "sample")))
  score <- brohn_score_scales(rows, sd)
  check("existing scale recipe scores one final assessment as five", length(score$observations) == 1L && score$observations[[1]]$value == 5 && score$observations[[1]]$answered_items == 2L)
  duplicate <- brohn_score_scales(c(rows, list(rows[[1]])), sd)
  check("unqualified duplicate item records remain ambiguous", duplicate$observations[[1]]$status == "not_scoreable" && duplicate$observations[[1]]$missing_reason == "invalid_or_ambiguous_item")

  driver_q <- brohn_question("Original typed driver", "single_choice", "before", "q-driver")
  driver_q$options <- list(list(id = "false", label = "Original false", value = FALSE), list(id = "true", label = "Original true", value = TRUE),
    list(id = "zero", label = "Original numeric zero", value = 0), list(id = "text-zero", label = "Original text zero", value = "0"))
  qb <- rating("q-dependent"); qb$show_if <- list(op = "equals", question_id = "q-driver", value = FALSE)
  qc <- rating("q-transitive"); qc$show_if <- list(op = "and", rules = list(list(op = "answered", question_id = "q-dependent"), list(op = "not", rule = list(op = "equals", question_id = "q-driver", value = TRUE))))
  independent <- rating("q-independent")
  bp <- prepare(survey(list(driver_q, qb, qc, independent))); bctx <- brohn_questionnaire_revision_context(bp); bd <- driver(bp)
  bm <- bp$questionnaire_occurrences[[1]]; ids <- unlist(bm$question_step_ids); br <- bm$review_step_id
  bd$visit(ids[[1]], "enter"); initial <- bd$commit(FALSE)
  check("first routing commit does not falsely announce invalidated saved answers", !length(initial$effects$invalidated_step_ids) && length(initial$effects$clear_draft_step_ids) == 2L)
  bd$visit(ids[[2]]); bd$commit(2); bd$visit(ids[[3]]); bd$commit(3); bd$visit(ids[[4]]); bd$commit(4); bd$visit(br)
  old_independent <- bd$current()$records[[ids[[4]]]]$head
  old_b <- bd$current()$records[[ids[[2]]]]$last_answer_event_id
  bd$visit(ids[[1]], "edit"); change <- bd$commit(TRUE)
  check("changed false driver clears direct and transitive heads/drafts", setequal(unlist(change$effects$clear_draft_step_ids), ids[2:3]) &&
    all(vapply(bd$current()$records[ids[2:3]], function(r) is.null(r$head) && r$invalidated, logical(1))))
  partial <- brohn_questionnaire_revision_projection(bctx, bd$state, FALSE)
  check("hidden historical answers cannot enter effective data", all(vapply(partial$effective_records[2:3], function(r) r$status == "not_displayed" && is.null(r$value), logical(1))) && length(partial$invalidations) == 2L)
  check("independent later answer keeps exact original evidence", identical(bd$current()$records[[ids[[4]]]]$head, old_independent))
  check("hidden dependent cannot be navigated to as a next item", rejects(bd$visit(ids[[2]]), "visible question order"))
  bd$visit(ids[[4]]); bd$commit(4); bd$visit(br); bd$visit(ids[[1]], "edit"); bd$commit(FALSE)
  check("reappearing dependents never resurrect prior values", is.null(bd$current()$records[[ids[[2]]]]$head) && identical(bd$current()$records[[ids[[2]]]]$last_answer_event_id, old_b))
  bd$visit(ids[[2]]); stale <- bd$commit_event(2); stale$payload$dependency_generation <- 0L
  check("stale draft generation cannot restore old conditional answer", rejects(bd$send(stale), "dependency generation"))
  bd$commit(2); bd$visit(ids[[3]]); bd$commit(3); bd$visit(ids[[4]]); bd$commit(4); bd$visit(br)
  check("fresh same-value conditional answer is a new head with null initial RT", bd$current()$records[[ids[[2]]]]$answer_version == 2L && is.null(bd$current()$records[[ids[[2]]]]$head$response_time_ms))
  bd$visit(ids[[1]], "edit"); bd$commit(0)
  visible <- brohn_questionnaire_revision_resume(bctx, bd$state)$visible_step_ids
  check("numeric zero is distinct from false for branch evaluation", identical(visible, as.list(ids[c(1,4)])))
  bd$visit(ids[[4]]); bd$commit(4); bd$visit(br); bd$visit(ids[[1]], "edit"); z <- bd$commit("0")
  check("text zero change is not a coerced unchanged confirmation", !z$effects$confirmation && identical(bd$current()$records[[ids[[1]]]]$head$value, "0"))
  nullable_design <- bp$design; nullable_design$questionnaire_navigation <- NULL; nullable_design$questions[[1]]$required <- FALSE
  np <- prepare(nullable_design); nd <- driver(np); nm <- np$questionnaire_occurrences[[1]]; ni <- unlist(nm$question_step_ids)
  nd$visit(ni[[1]], "enter"); nd$commit(FALSE); nd$visit(ni[[2]]); nd$commit(2); nd$visit(ni[[3]]); nd$commit(3); nd$visit(ni[[4]]); nd$commit(4); nd$visit(nm$review_step_id)
  nd$visit(ni[[1]], "edit"); nd$commit(NULL); nrows <- brohn_questionnaire_revision_projection(nd$ctx, nd$state, FALSE)$effective_records
  check("explicit null is a committed omission that clears former false-driven answers", nrows[[1]]$status == "optional_omission" && !is.null(nd$current()$records[[ni[[1]]]]$head) &&
    all(vapply(nrows[2:3], function(r) r$status == "not_displayed" && is.null(r$value), logical(1))))
  nd$visit(ni[[4]]); nd$commit(4); nd$visit(nm$review_step_id); nd$seal()
  check("hidden required dependents do not block a legitimate seal", brohn_questionnaire_revision_projection(nd$ctx, nd$state)$quality$sealed_occurrence_count == 1L)

  # Dependency remains visible: changing one answered rating still clears its
  # answered-dependent, rather than silently retaining context-sensitive data.
  always <- rating("q-always-follow"); always$show_if <- list(op = "answered", question_id = "q-a")
  ap <- prepare(survey(list(rating("q-a"), always))); ad <- driver(ap); am <- ap$questionnaire_occurrences[[1]]; ai <- unlist(am$question_step_ids)
  ad$visit(ai[[1]], "enter"); ad$commit(1); ad$visit(ai[[2]]); ad$commit(2); ad$visit(am$review_step_id); ad$visit(ai[[1]], "edit"); ad$commit(3)
  check("still-visible dependent is invalidated under the named conservative policy", is.null(ad$current()$records[[ai[[2]]]]$head) && ai[[2]] %in% unlist(brohn_questionnaire_revision_resume(ad$ctx, ad$state)$visible_step_ids))
  check("incomplete current assessment is refused by completed projection", rejects(brohn_questionnaire_revision_projection(ad$ctx, ad$state), "sealed"))

  optional <- rating("q-optional"); optional$required <- FALSE
  info <- brohn_question("Original information", "information", "before", "q-information")
  op <- prepare(survey(list(optional, info))); od <- driver(op); om <- op$questionnaire_occurrences[[1]]; oi <- unlist(om$question_step_ids)
  od$visit(oi[[1]], "enter")
  check("Back from first question has no fabricated target", rejects(od$visit(oi[[1]], "back"), "previous visible"))
  check("unfinished optional answer is not automatically omitted by Continue", rejects(od$visit(oi[[2]]), "valid answer"))
  od$commit(NULL); od$visit(oi[[2]])
  check("information is not a scored null response", rejects(od$commit(NULL), "history predecessor"))
  od$send(od$event(oi[[2]], "acknowledge", visit_id = od$current()$visit$id)); od$visit(om$review_step_id); od$seal()
  orows <- brohn_questionnaire_revision_projection(od$ctx, od$state)$effective_records
  check("explicit optional null and information acknowledgement remain distinct", orows[[1]]$status == "optional_omission" && is.null(orows[[1]]$value) && orows[[2]]$status == "information_acknowledged" && orows[[2]]$information)
  ci <- info; ci$show_if <- list(op = "answered", question_id = "q-information-driver")
  ip <- prepare(survey(list(rating("q-information-driver"), ci))); id <- driver(ip); im <- ip$questionnaire_occurrences[[1]]; ii <- unlist(im$question_step_ids)
  id$visit(ii[[1]], "enter"); id$commit(1); id$visit(ii[[2]]); id$send(id$event(ii[[2]], "acknowledge", visit_id = id$current()$visit$id))
  id$visit(im$review_step_id); id$visit(ii[[1]], "edit"); id$commit(2)
  check("conditional information acknowledgement is invalidated with its routing context", !id$current()$records[[ii[[2]]]]$acknowledged && id$current()$records[[ii[[2]]]]$invalidated)
  id$visit(ii[[2]]); id$send(id$event(ii[[2]], "acknowledge", visit_id = id$current()$visit$id)); id$visit(im$review_step_id); id$seal()
  check("fresh information acknowledgement clears current invalidity without a scored response", !id$current(im$id)$records[[ii[[2]]]]$invalidated && brohn_questionnaire_revision_projection(id$ctx, id$state)$effective_records[[2]]$status == "information_acknowledged")
  required <- driver(prepare(survey(list(rating("q-required"))))); reqid <- required$protocol$questionnaire_occurrences[[1]]$question_step_ids[[1]]
  required$visit(reqid, "enter"); before <- brohn_hash(required$state)
  check("required null fails atomically without changing the visible visit or version", rejects(required$commit(NULL), "required question") && identical(before, brohn_hash(required$state)))
  duplicated <- required$event(reqid, "commit", visit_id = required$current()$visit$id, previous_answer_event_id = NULL, dependency_generation = 0L,
    value = 2, response_time_ms = 200, active_segment_response_ms = 200, resumed = FALSE)
  duplicated$id <- required$state$history[[1]]$event_id
  check("new sequence cannot reuse an accepted event identity", rejects(required$send(duplicated), "identity cannot be reused"))

  rp <- prepare(survey(list(rating("q-resume")))); rd <- driver(rp); rm <- rp$questionnaire_occurrences[[1]]; ri <- rm$question_step_ids[[1]]
  rd$visit(ri, "enter"); rd$page <- "original-page-2"; rd$origin <- "2000000"; rd$tick <- 0
  check("new page cannot submit against an old page visit", rejects(rd$commit(2), "clock-bound visit"))
  rd$visit(ri, "resume"); rd$commit(2)
  check("resumed first commit has null initial RT and actual active interval", is.null(rd$current()$records[[ri]]$head$response_time_ms) && rd$current()$records[[ri]]$head$active_segment_response_ms == 100)
  decorated_event <- rd$event(rm$review_step_id, "visit", visit_id = "runner-clock-fields", reason = "next", from_visit_id = rd$current()$visit$id)
  decorated_event$payload$clock_segment_id <- decorated_event$clock$instance_id; decorated_event$payload$time_origin_ms <- decorated_event$clock$time_origin_ms
  accepted_clock <- brohn_questionnaire_revision_apply(rd$state, decorated_event, rd$ctx, rd$cursor)
  check("current runner redundant clock fields are accepted only when exact", accepted_clock$state$event_count == rd$state$event_count+1L)
  decorated_event$payload$clock_segment_id <- "foreign-clock"
  check("redundant runner clock alias cannot contradict its envelope", rejects(rd$send(decorated_event), "Redundant runner clock"))
  stale <- rd$event(rm$review_step_id, "visit", visit_id = "stale-version", reason = "next", from_visit_id = rd$current()$visit$id); stale$payload$state_version <- 0L
  check("stale transition version cannot advance", rejects(rd$send(stale), "state changed"))
  mixed <- rd$event(rm$review_step_id, "visit", visit_id = "mixed-origin", reason = "next", from_visit_id = rd$current()$visit$id); mixed$clock$time_origin_ms <- "different"
  check("malformed page clock is rejected", rejects(rd$send(mixed), "actual page"))
  mixed <- rd$event(rm$review_step_id, "visit", visit_id = "changed-origin", reason = "next", from_visit_id = rd$current()$visit$id); mixed$clock$time_origin_ms <- "3000000"
  check("same page identity cannot acquire a different time origin", rejects(rd$send(mixed), "changed origin"))
  bad <- rd$event(rm$review_step_id, "visit", visit_id = "foreign-question", reason = "next", from_visit_id = rd$current()$visit$id); bad$question_id <- "q-resume"
  check("review cannot claim an ordinary question identity", rejects(rd$send(bad), "foreign assessment"))

  mix <- prepare(survey(list(rating("q-before"), rating("q-end", "end")))); md <- driver(mix)
  mm <- mix$questionnaire_occurrences
  check("adjacent before and end are distinct occurrences", length(mm) == 2L && mm[[1]]$scope == "before" && mm[[2]]$scope == "end" && mm[[1]]$id != mm[[2]]$id)
  md$visit(mm[[1]]$question_step_ids[[1]], "enter")
  check("active occurrence refuses direct entry to end scope", rejects(md$visit(mm[[2]]$question_step_ids[[1]], "enter"), "not reached"))
  md$commit(2); md$visit(mm[[1]]$review_step_id); md$seal(); md$visit(mm[[2]]$question_step_ids[[1]], "enter"); md$commit(4); md$visit(mm[[2]]$review_step_id); md$seal()
  mr <- brohn_questionnaire_revision_projection(md$ctx, md$state)$effective_records
  check("mixed scopes preserve original scale assessment identities", identical(vapply(mr, `[[`, character(1), "assessment_id"), c("scope:before", "scope:end")))

  timed <- brohn_new_design("Original control and test", "comparison", "study-original-timed"); timed$instructions <- ""; timed$order <- "fixed"
  for (i in seq_along(timed$stimuli)) timed$stimuli[[i]]$content <- paste("Original synthetic concept", i)
  timed$questions <- list(rating("q-after", "after_each")); timed$questions[[1]]$randomize_options <- TRUE; timed$questions[[1]]$option_assignment <- NULL
  original_timed <- brohn_compile(timed, 2L); timed$questionnaire_navigation <- brohn_questionnaire_navigation()
  tp <- brohn_questionnaire_revision_decorate(assigned(timed, 2L)); td <- driver(tp); tm <- tp$questionnaire_occurrences
  remove_review <- lapply(Filter(function(s) s$type != "questionnaire_review", tp$timeline), function(s) {s$questionnaire_occurrence_id <- NULL; s})
  check("two-pass decoration preserves later legacy timeline-seeded option order", identical(brohn_json(remove_review), brohn_json(original_timed$timeline)))
  check("first questionnaire cannot bypass initial baseline or stimulus", rejects(td$visit(tm[[1]]$question_step_ids[[1]], "enter"), "timed boundaries"))
  td$cursor <- td$ctx$indices[[tm[[1]]$first_question_step_id]] # stands for receiver-validated timed completion
  td$visit(tm[[1]]$question_step_ids[[1]], "enter"); td$commit(2); td$visit(tm[[1]]$review_step_id); td$seal()
  check("seal stops at next original timed step without authorising its completion", tp$timeline[[td$cursor]]$type %in% c("baseline", "fixation", "stimulus"))
  check("next exposure cannot start from an uncompleted timed boundary", rejects(td$visit(tm[[2]]$question_step_ids[[1]], "enter"), "timed boundaries"))
  td$cursor <- td$ctx$indices[[tm[[2]]$first_question_step_id]]
  td$visit(tm[[2]]$question_step_ids[[1]], "enter"); td$commit(6); td$visit(tm[[2]]$review_step_id); td$seal()
  tr <- brohn_questionnaire_revision_projection(td$ctx, td$state)$effective_records
  check("same question across actual exposures remains two anchored assessments", length(tr) == 2L && tr[[1]]$question_id == tr[[2]]$question_id && tr[[1]]$assessment_exposure_id != tr[[2]]$assessment_exposure_id &&
    tr[[1]]$assessment_id != tr[[2]]$assessment_id && identical(vapply(tr, `[[`, numeric(1), "value"), c(2,6)))
  missing <- assigned(timed); missing$timeline <- Filter(function(s) s$type != "question", missing$timeline)
  check("source-derived manifest cannot silently omit all after-stimulus questions", rejects(brohn_questionnaire_revision_decorate(missing), "Each original stimulus"))
  missing <- p0; missing$design$questionnaire_navigation <- brohn_questionnaire_navigation(); missing$design_hash <- brohn_hash(missing$design); missing$timeline <- list()
  check("source-derived manifest cannot silently omit before/end questions", rejects(brohn_questionnaire_revision_decorate(missing), "occurrence is missing"))

  # A lower-level original protocol fixture repeats a source stimulus under a
  # different original step. Current study authoring still has no repeat feature.
  repeated <- assigned(timed)
  stim_positions <- which(vapply(repeated$timeline, function(s) s$type == "stimulus", logical(1)))
  first <- repeated$timeline[[stim_positions[[1]]]]; second_id <- repeated$timeline[[stim_positions[[2]]]]$id
  for (i in seq.int(stim_positions[[1]]+2L, length(repeated$timeline))) {
    if (!is.null(repeated$timeline[[i]]$stimulus_id)) {repeated$timeline[[i]]$stimulus_id <- first$stimulus_id; repeated$timeline[[i]]$condition_id <- first$condition_id}
    if (repeated$timeline[[i]]$type == "stimulus") repeated$timeline[[i]]$stimulus <- first$stimulus
  }
  repeated <- brohn_questionnaire_revision_decorate(repeated); rms <- repeated$questionnaire_occurrences
  check("occurrence identity never merges repeated source IDs under distinct stimulus steps", rms[[1]]$stimulus_id == rms[[2]]$stimulus_id && rms[[1]]$id != rms[[2]]$id && rms[[2]]$stimulus_step_id == second_id)

  textq <- function(i) {q <- brohn_question(paste("Original long answer", i), "long_text", "before", paste0("q-text-", i)); q}
  pages <- prepare(survey(lapply(1:3, textq))); pd <- driver(pages); pm <- pages$questionnaire_occurrences[[1]]
  for (i in 1:3) {pd$visit(pm$question_step_ids[[i]], if (i == 1L) "enter" else "next"); pd$commit(paste(rep(as.character(i), 3000), collapse = ""))}
  page <- brohn_questionnaire_revision_resume(pd$ctx, pd$state, max_bytes = 6000); gathered <- page$records; n <- 1L
  while (!is.null(page$next_offset)) {page <- brohn_questionnaire_revision_resume(pd$ctx, pd$state, offset = page$next_offset, max_bytes = 6000); gathered <- c(gathered, page$records); n <- n+1L}
  check("bounded resume pages preserve full typed answer bytes with explicit offsets", n > 1L && length(gathered) == 3L && all(vapply(gathered, function(r) nchar(r$value) == 3000, logical(1))))
  check("too-small resume budget fails explicitly instead of truncating", rejects(brohn_questionnaire_revision_resume(pd$ctx, pd$state, max_bytes = 1024), "never truncate"))
  check("invalid resume offset cannot silently return another range", rejects(brohn_questionnaire_revision_resume(pd$ctx, pd$state, offset = 4L), "offset exceeds"))
  full <- pd$state; pd$state$event_count <- 10000000L
  check("existing run event budget is enforced before state mutation", rejects(pd$visit(pm$review_step_id), "existing run or transport"))
  pd$state <- full
  many <- prepare(survey(lapply(1:200, function(i) rating(paste0("q-many-", i))))); ld <- driver(many); lm <- many$questionnaire_occurrences[[1]]
  for (i in seq_along(lm$question_step_ids)) {ld$visit(lm$question_step_ids[[i]], if (i == 1L) "enter" else "next"); ld$commit(4)}
  # Independent review counterexample: zero remaining rows must not bypass the
  # byte bound when the current visible-step metadata itself exceeds that bound.
  check("empty final resume page still bounds the complete visible-step envelope", rejects(brohn_questionnaire_revision_resume(ld$ctx, ld$state, offset = 200L, max_bytes = 1024L), "metadata needs"))
  ld$visit(lm$review_step_id); ld$seal()
  check("normal maximum 200-question occurrence completes without a low edit quota", length(brohn_questionnaire_revision_projection(ld$ctx, ld$state)$effective_records) == 200L && ld$state$event_count == 402L)
  cat(sprintf("PASS: %d pure questionnaire revision checks (source decoration, typed invalidation, edits, seal, clocks, projection and bounds)\n", checks))
})
