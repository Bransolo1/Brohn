source("R/platform-load.R", encoding = "UTF-8"); brohn_load()
source("tests/fixtures/question-sections-original.R")
local({
  checks <- 0L
  check <- function(label, ok) {if (!isTRUE(ok)) stop("FAILED: ", label); checks <<- checks+1L}
  canonical <- function(value) brohn_json(value)
  original <- brohn_sections_fixture(); flat <- brohn_compile(original, 3)
  check("flat protocols gain no section fields", !"questionnaire_assignments" %in% names(flat) && all(vapply(flat$timeline, function(s) !"questionnaire" %in% names(s), logical(1))))
  # Actual whole-design cloning previously partially matched rules as rule.
  cloned <- brohn_clone_design(original)
  expected_rule <- list(op = "and", rules = list(list(op = "answered", question_id = cloned$questions[[2]]$id),
    list(op = "not", rule = list(op = "equals", question_id = cloned$questions[[2]]$id, value = FALSE))))
  check("whole-design clone correctly remaps nested AND and NOT without an extra child", identical(canonical(cloned$questions[[3]]$show_if), canonical(expected_rule)))
  d <- brohn_sections_order_fixture(); protocol <- brohn_compile(d, 3)
  oracle <- brohn_parse(paste(readLines("tests/fixtures/question-sections-oracle.json", warn = FALSE), collapse = "\n"))
  expected <- Filter(function(r) r$allocation_index == 3, oracle$rows)
  for (row in expected) {
    assigned <- Filter(function(m) m$scope == row$scope && identical(m$stimulus_id, row$stimulus_id), protocol$questionnaire_assignments)[[1]]
    actual <- Filter(function(s) s$type == "question" && identical(s$questionnaire$assignment_id, assigned$assignment_id), protocol$timeline)
    check("actual compiler follows the independent realized order for each assessment", identical(assigned$realized_question_order, row$question_order) && identical(as.list(vapply(actual, function(s) s$question$id, character(1))), row$question_order))
    check("compiler keeps assessment metadata outside frozen question definitions", all(vapply(actual, function(s) identical(canonical(s$question), canonical(brohn_find(d$questions, s$question$id))), logical(1))))
  }
  unsectioned <- d; unsectioned$questionnaire_sections <- NULL
  nonquestions <- function(p) Filter(function(s) s$type != "question", p$timeline)
  check("section ordering preserves passive stimuli and physiological phase durations", identical(canonical(nonquestions(protocol)), canonical(nonquestions(brohn_compile(unsectioned, 3)))))
  store <- brohn_open_store(tempfile("brohn-section-integration-")); on.exit(brohn_close_store(store), add = TRUE)
  brohn_initialise_library(store); saved <- brohn_put_entity(store, "study", d$id, d)
  archive <- tempfile(fileext = ".brohn-study.zip"); brohn_export_design(store, d$id, archive)
  imported <- brohn_import_design(store, archive)
  check("actual design ZIP retains remapped sections and nested rules", !identical(imported$id, d$id) && length(imported$body$questionnaire_sections$sections) == length(d$questionnaire_sections$sections) && length(brohn_compile(imported$body, 3)$questionnaire_assignments) == 4L && is.null(imported$body$questions[[3]]$show_if[["rule"]]))
  release <- brohn_publish(store, saved$id, origin = "sample", quota = 3)
  first <- .brohn_delivery_start(store, release$token, list(consented = TRUE, client_id = "original-section-start", operation_id = "original-section-first"))
  changed <- d; changed$questionnaire_sections$sections[[1]]$label <- "Changed draft section label"
  brohn_save_study(store, changed, saved$revision)
  later <- .brohn_delivery_start(store, release$token, list(consented = TRUE, client_id = "original-section-later", operation_id = "original-section-later"))
  check("new enrollment on old release keeps its frozen section definition", identical(canonical(later$protocol$design$questionnaire_sections), canonical(d$questionnaire_sections)))
  replay <- .brohn_delivery_start(store, release$token, list(consented = TRUE, client_id = "original-section-start", operation_id = "original-section-retry"))
  check("duplicate start preserves exact section and question assignment", identical(first, replay))
  # Complete a scale-enabled, conditional survey through the actual receiver.
  survey <- brohn_new_design("Original sectioned scale delivery", "survey"); survey$instructions <- ""
  driver <- brohn_question("Original optional follow-up driver", "single_choice", "before", "q-driver")
  driver$options <- list(list(id = "no", label = "No", value = FALSE), list(id = "yes", label = "Yes", value = TRUE))
  follow <- brohn_question("Original hidden required follow-up", "text", "before", "q-follow")
  follow$show_if <- list(op = "and", rules = list(list(op = "answered", question_id = driver$id), list(op = "not", rule = list(op = "equals", question_id = driver$id, value = FALSE))))
  items <- lapply(1:2, function(i) brohn_question(paste("Original scale item", i), "rating", "end", paste0("q-scale-", i)))
  survey$questions <- c(list(driver, follow), items)
  survey$scales <- list(list(schema = "brohn-questionnaire-scale/1.0", id = "original-scale", label = "Original paired item mean", version = "1.0",
    source = "Original arithmetic fixture, not an established instrument", scope = "end",
    items = lapply(items, function(q) list(question_id = q$id, reverse = FALSE, min = 1, max = 7)),
    scoring = list(aggregation = "mean", missing = "complete", minimum_answered = 2, prorate = FALSE), conversion = NULL))
  survey$questionnaire_sections <- brohn_question_sections_new(survey)
  brohn_put_entity(store, "study", survey$id, survey)
  deployment <- brohn_publish(store, survey$id, origin = "sample", quota = 1)
  started <- .brohn_delivery_start(store, deployment$token, list(consented = TRUE, client_id = "original-scale-sections", operation_id = "original-scale-section-start"))
  journal <- list(); sequence <- 0L; time <- 0L
  event <- function(type, step = NULL, payload) {
    sequence <<- sequence+1L; time <<- time+10L
    list(id = paste0("original-section-event-", sequence), sequence = sequence, type = type, step_id = if (is.null(step)) NULL else step$id,
      stimulus_id = NULL, condition_id = NULL, question_id = if (is.null(step)) NULL else step$question$id,
      phase = if (is.null(step)) "session" else step$phase,
      clock = list(id = "browser-monotonic", unit = "ms", value = as.character(time), instance_id = "original-section-clock", time_origin_ms = "1000"), payload = payload)
  }
  for (step in started$protocol$timeline) {
    if (step$question$id == follow$id) journal <- c(journal, list(event("step_finished", step, list(skipped = TRUE, reason = "display_logic")))) else {
      value <- if (step$question$id == driver$id) FALSE else if (step$question$id == items[[1]]$id) 1 else 5
      journal <- c(journal, list(event("step_started", step, list(resumed = FALSE)), event("response", step, list(value = value, response_time_ms = 10)), event("step_finished", step, list(elapsed_ms = 20))))
    }
  }
  journal <- c(journal, list(event("run_finished", payload = list(outcome = "completed"))))
  .brohn_delivery_receive(store, started$run_id, started$access_token, list(operation_id = "original-section-responses", events = journal))
  .brohn_delivery_finish(store, started$run_id, started$access_token, list(operation_id = "original-section-finish", outcome = "completed", final_sequence = sequence))
  check("actual receiver preserves hidden reason and boolean false within assigned sections", brohn_run(store, started$run_id)$completion_status == "completed" &&
    any(vapply(brohn_run_events(store, started$run_id), function(e) identical(e$payload$reason, "display_logic"), logical(1))))
  job <- brohn_claim_job(store, "section-worker", lease_seconds = 60)
  brohn_process_job(store, job, timeout_seconds = 45); done <- brohn_get_job(store, job$id)
  check(paste("section-enabled actual worker succeeds", brohn_json(done$error)), done$status == "succeeded")
  report <- brohn_get_entity(store, "report", done$result$report_id)
  check("section groups do not split one scale assessment into extra observations", length(report$body$analysis$scales$observations) == 1L && report$body$analysis$scales$observations[[1]]$value == 3)
  check("actual worker retains its section compiler source identity", identical(report$body$processing$code_hashes$`R/platform-question-sections.R`, digest::digest(file = "R/platform-question-sections.R", algo = "sha256")))
  snapshot <- brohn_run_protocol(store, started$run_id, survey$id, survey$project_id)
  destination <- tempfile(fileext = ".json"); brohn_export_run_protocol(snapshot, destination)
  check("assigned-protocol download retains complete realized section evidence", identical(digest::digest(file = destination, algo = "sha256"), snapshot$hash) && length(snapshot$protocol$questionnaire_assignments) == 2L)
  check("saved report has intact publication bytes", identical(digest::digest(file = brohn_object_path(store, report$body$result_object$hash), algo = "sha256"), report$body$result_object$hash))
  cat(sprintf("PASS: %d sections compiler, nested clone/ZIP, receiver and saved-worker checks\n", checks))
})
