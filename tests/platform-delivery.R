# End-to-end researcher/participant delivery contract using isolated synthetic
# studies, real SQLite persistence and a separate loopback HTTP server process.
.libPaths(c(normalizePath("../../work/r-library-brohn", winslash = "/", mustWork = FALSE), .libPaths()))
for (module in c("platform-core", "platform-store", "platform-delivery")) source(paste0("R/", module, ".R"))
local({
  directory <- tempfile("brohn-delivery-")
  dir.create(directory)
  cleanup_root <- normalizePath(directory, winslash = "/")
  store <- brohn_open_store(file.path(directory, "workspace"))
  process <- NULL
  on.exit({
    if (!is.null(process) && process$is_alive()) process$kill()
    brohn_close_store(store)
    stopifnot(identical(normalizePath(directory, winslash = "/"), cleanup_root),
      startsWith(cleanup_root, paste0(normalizePath(tempdir(), winslash = "/"), "/")))
    Sys.chmod(list.files(directory, recursive = TRUE, full.names = TRUE, all.files = TRUE), "0666")
    unlink(directory, recursive = TRUE)
  }, add = TRUE)
  count <- 0L
  check <- function(name, value) { if (!isTRUE(value)) stop("FAIL: ", name); count <<- count + 1L }
  rejects <- function(expr) inherits(try(force(expr), silent = TRUE), "try-error")
  object <- function(...) list(...)
  empty <- function() structure(list(), names = character())
  static <- file.path(directory, "static"); dir.create(static)
  writeLines("<!doctype html><html lang='en'><title>Synthetic runner fixture</title><body>Fixture</body></html>", file.path(static, "index.html"))
  writeLines("/* synthetic runner fixture */", file.path(static, "runner.js"))
  writeLines("body { color: black; }", file.path(static, "runner.css"))
  app <- brohn_delivery_app(store, static)
  call <- function(path, payload = NULL, bearer = NULL, method = if (is.null(payload)) "GET" else "POST",
                   origin = "http://127.0.0.1:3840", host = "127.0.0.1:3840", raw = NULL, declared = NULL) {
    if (is.null(raw)) raw <- if (is.null(payload)) raw() else charToRaw(.brohn_store_json(payload))
    request <- list(PATH_INFO = path, REQUEST_METHOD = method, HTTP_HOST = host,
      HTTP_ORIGIN = origin, CONTENT_TYPE = "application/json", CONTENT_LENGTH = as.character(brohn_default(declared, length(raw))),
      rook.input = list(read = function(n = -1L) raw))
    if (!is.null(bearer)) request$HTTP_AUTHORIZATION <- paste("Bearer", bearer)
    response <- app$call(request)
    if (is.character(response$body) && grepl("^application/json", response$headers[["Content-Type"]]))
      response$value <- jsonlite::fromJSON(response$body, simplifyVector = FALSE)
    response
  }
  design <- brohn_new_design("Consumer concept comparison", id = "study-delivery")
  design$stimuli[[1]]$content <- "Control concept"
  design$stimuli[[2]]$content <- "Candidate concept"
  for (i in 1:2) design$stimuli[[i]]$duration_ms <- 100L
  design$baseline_ms <- 100L; design$fixation_ms <- 100L
  before <- brohn_question("Would you like the optional detail?", "single_choice", "before", "q-before")
  before$options <- list(list(id = "no", label = "No", value = FALSE), list(id = "yes", label = "Yes", value = TRUE))
  conditional <- brohn_question("Required only when yes", "text", "before", "q-hidden")
  conditional$show_if <- list(op = "equals", question_id = "q-before", value = TRUE)
  matrix <- brohn_question("Rate these attributes", "matrix", "end", "q-matrix")
  matrix$rows <- list(list(id = "clarity", label = "Clarity"), list(id = "interest", label = "Interest"))
  matrix$required <- FALSE
  ranking <- brohn_question("Rank the two concepts", "ranking", "end", "q-ranking")
  ranking$options <- ranking$options[1:2]
  allocation <- brohn_question("Allocate 100 points", "allocation", "end", "q-allocation")
  allocation$options <- allocation$options[1:2]; allocation$min <- 0; allocation$max <- 100
  design$questions <- c(list(before, conditional), design$questions, list(matrix, ranking, allocation))
  brohn_put_entity(store, "study", design$id, design)
  deployment <- brohn_publish(store, design$id, origin = "pilot", quota = 2)
  entry_path <- paste0("/api/entry/", deployment$token)
  start_path <- paste0("/api/start/", deployment$token)
  check("release pins a real study revision", deployment$design_revision == 1L && deployment$status == "open" &&
    deployment$origin == "pilot" && nchar(deployment$token) == 64L)
  check("release entry exposes no design or private tokens", call(entry_path)$status == 200L &&
    is.null(call(entry_path)$value$protocol) && !grepl(deployment$token, call(entry_path)$body, fixed = TRUE))
  check("unknown study link rejected", call("/api/entry/unknown")$status == 404L)
  check("cross-origin browser rejected", call(entry_path, origin = "https://foreign.example")$status == 403L)
  check("host rebinding rejected", call(entry_path, host = "foreign.example", origin = NULL)$status == 403L)
  check("static route allowlist is exact", call("/participant/")$status == 200L &&
    call("/participant/runner.js")$status == 200L && call("/participant/../catalog.sqlite")$status == 404L)
  check("unsupported methods and body size bounded", call(entry_path, method = "DELETE")$status == 405L &&
    call(start_path, raw = charToRaw("{}"), method = "POST", declared = 4 * 1024^2 + 1)$status == 413L)
  check("malformed request JSON rejected", call(start_path, raw = charToRaw("{broken"), method = "POST")$status == 400L)
  request <- list(consented = FALSE, client_id = "client-one", operation_id = "start-one", participant_alias = "")
  check("consent is required before allocation", call(start_path, request)$status == 403L && length(brohn_runs(store)) == 0L)
  request$consented <- TRUE
  response <- call(start_path, request)
  if (response$status != 200L) stop(response$body)
  start <- response$value
  check("participant starts with a fresh pinned run", start$expected_sequence == 1L && length(start$protocol$timeline) > 0L && nchar(start$access_token) == 64L)
  replay <- call(start_path, request)$value
  check("start retry reuses identity and quota place", identical(replay$run_id, start$run_id) &&
    identical(replay$access_token, start$access_token) && length(brohn_runs(store)) == 1L)
  changed <- request; changed$participant_alias <- "changed"
  check("reused start operation cannot change payload", call(start_path, changed)$status == 409L)
  body <- brohn_get_entity(store, "study", design$id)$body; body$title <- "Edited after publication"
  brohn_put_entity(store, "study", design$id, body, expected_revision = 1L)
  check("released entry remains pinned after draft edit", identical(call(entry_path)$value$deployment$title, design$title))
  second_request <- list(consented = TRUE, client_id = "client-two", operation_id = "start-two")
  second_start <- call(start_path, second_request)$value
  check("counterbalance assignment is recorded", identical(start$protocol$realized_stimulus_order,
    rev(second_start$protocol$realized_stimulus_order)) && second_start$protocol$allocation_index == 2L)
  check("quota rejects further starts", call(start_path, list(consented = TRUE, client_id = "third", operation_id = "third"))$status == 409L)
  check("researcher run records never contain access tokens", !grepl(start$access_token,
    .brohn_store_json(brohn_runs(store)), fixed = TRUE))
  check("generated display aliases do not assert participant linkage", !brohn_run(store, start$run_id)$participant_alias_supplied &&
    identical(brohn_run(store, start$run_id)$participant_alias, "Participant 1"))
  # Create the actual assigned timeline as observed participant events. Hidden
  # required questions are explicitly skipped and zero allocations are retained.
  events <- list(); time <- 1000L
  event <- function(type, step = NULL, payload = empty(), instance = "page-one") {
    time <<- time + 1L
    item <- list(sequence = length(events) + 1L, id = paste0("event-", length(events)+1L), type = type,
      step_id = if (is.null(step)) NULL else step$id,
      stimulus_id = if (is.null(step)) NULL else brohn_default(step$stimulus_id, NULL),
      condition_id = if (is.null(step)) NULL else brohn_default(step$condition_id, NULL),
      question_id = if (!is.null(step) && step$type == "question") step$question$id else NULL,
      phase = if (is.null(step)) "completion" else step$phase,
      clock = list(id = "browser-monotonic", unit = "ms", value = as.character(time), instance_id = instance,
        time_origin_ms = "1788854400000.125"), payload = payload)
    events[[length(events)+1L]] <<- item
    item
  }
  for (step in start$protocol$timeline) {
    if (step$type == "question" && step$question$id == "q-hidden") {
      event("step_finished", step, list(skipped = TRUE, reason = "display_logic", elapsed_ms = NULL))
      next
    }
    event("step_started", step)
    if (step$type == "question") {
      value <- switch(step$question$id, "q-before" = FALSE, "q-liking" = 7,
        "q-matrix" = list(clarity = 3, interest = NULL), "q-ranking" = list("option-2", "option-1"),
        "q-allocation" = list("option-1" = 0, "option-2" = 100))
      event("response", step, list(value = value, response_time_ms = 1, scope = step$question$scope))
    } else if (step$type %in% c("stimulus", "baseline", "fixation")) time <- time + step$duration_ms
    event("step_finished", step)
  }
  event("run_finished")
  events_path <- paste0("/api/events/", start$run_id)
  finish_path <- paste0("/api/finish/", start$run_id)
  check("unauthenticated event append rejected", call(events_path, list(events = events[1], operation_id = "no-auth"))$status == 401L)
  check("cross-run access rejected", call(paste0("/api/events/", second_start$run_id),
    list(events = events[1], operation_id = "cross-run"), start$access_token)$status == 401L)
  check("sequence gaps rejected without writes", call(events_path, list(events = events[2], operation_id = "gap"),
    start$access_token)$status == 409L && brohn_run(store, start$run_id)$acked_sequence == 0L)
  bad_events <- events
  index <- which(vapply(bad_events, function(e) e$type == "response" && identical(e$question_id, "q-liking"), logical(1)))[1]
  bad_events[[index]]$payload$value <- 99
  check("invalid typed answer rolls back complete batch", call(events_path,
    list(events = bad_events, operation_id = "bad-batch"), start$access_token)$status == 422L &&
    length(brohn_run_events(store, start$run_id)) == 0L)
  invalid_skip <- events
  hidden <- which(vapply(events, function(e) identical(e$question_id, "q-hidden"), logical(1)))[1]
  before_index <- which(vapply(events, function(e) identical(e$question_id, "q-before") && e$type == "response", logical(1)))[1]
  invalid_skip[[before_index]]$payload$value <- TRUE
  check("visible required question cannot be skipped", call(events_path,
    list(events = invalid_skip, operation_id = "bad-skip"), start$access_token)$status == 422L)
  missing_response <- events[-index]
  for (i in seq_along(missing_response)) missing_response[[i]]$sequence <- i
  check("required response cannot be omitted", call(events_path,
    list(events = missing_response, operation_id = "missing-response"), start$access_token)$status == 422L)
  foreign <- events[1]; foreign[[1]]$stimulus_id <- "foreign-stimulus"
  check("foreign stimulus reference rejected", call(events_path,
    list(events = foreign, operation_id = "foreign"), start$access_token)$status == 422L)
  premature <- list(outcome = "completed", final_sequence = 0L, operation_id = "premature")
  check("completion cannot fabricate a finished study", call(finish_path, premature, start$access_token)$status == 422L)
  first_half <- seq_len(floor(length(events)/2))
  first_batch <- list(events = events[first_half], operation_id = "first-events")
  receipt <- call(events_path, first_batch, start$access_token)
  if (receipt$status != 200L) stop(receipt$body)
  check("contiguous validated batch receives durable acknowledgement", receipt$value$acked_sequence == length(first_half))
  check("exact event replay is idempotent", call(events_path, first_batch, start$access_token)$value$acked_sequence == length(first_half))
  conflict <- first_batch; conflict$events[[1]]$payload <- list(changed = TRUE)
  check("batch operation conflict rejected", call(events_path, conflict, start$access_token)$status == 409L)
  conflict$operation_id <- "new-operation-old-sequence"
  check("sequence content conflict rejected", call(events_path, conflict, start$access_token)$status == 409L)
  reuse <- events[max(first_half)+1L]; reuse[[1]]$id <- events[[1]]$id
  check("event ID cannot migrate to another sequence", call(events_path,
    list(events = reuse, operation_id = "reused-event-id"), start$access_token)$status == 409L)
  paused <- brohn_deployment_state(store, deployment$id, "paused")
  check("pause is visible while existing run recovers", paused$status == "paused" &&
    call(start_path, request)$value$expected_sequence == length(first_half)+1L &&
    !is.null(call(start_path, request)$value$resume$next_step_id))
  brohn_deployment_state(store, deployment$id, "closed")
  check("closed release cannot reopen", rejects(brohn_deployment_state(store, deployment$id, "open")))
  remaining <- setdiff(seq_along(events), first_half)
  receipt <- call(events_path, list(events = events[remaining], operation_id = "remaining-events"), start$access_token)
  if (receipt$status != 200L) stop(receipt$body)
  check("closed release accepts previously started run uploads", receipt$value$acked_sequence == length(events))
  pending <- list(outcome = "completed", final_sequence = length(events)+1L, operation_id = "pending")
  check("finalization requires exact final receipt", call(finish_path, pending, start$access_token)$status == 409L)
  finish <- list(outcome = "completed", final_sequence = length(events), operation_id = "finish-one")
  DBI::dbExecute(store$con, "CREATE TRIGGER fail_analysis_queue BEFORE INSERT ON jobs BEGIN SELECT RAISE(ABORT,'injected queue failure'); END")
  check("analysis queue failure rolls back finalization and receipt", call(finish_path, finish, start$access_token)$status != 200L &&
    brohn_run(store, start$run_id)$completion_status == "in_progress")
  DBI::dbExecute(store$con, "DROP TRIGGER fail_analysis_queue")
  saved <- call(finish_path, finish, start$access_token)
  if (saved$status != 200L) stop(saved$body)
  check("completion is durably saved and analysis queued", saved$value$status == "saved" &&
    brohn_run(store, start$run_id)$completion_status == "completed" && length(brohn_list_jobs(store)) == 1L &&
    brohn_list_jobs(store)[[1]]$operation == "analyse_run")
  check("finish retry is idempotent without duplicate analysis", call(finish_path, finish, start$access_token)$status == 200L && length(brohn_list_jobs(store)) == 1L)
  changed_finish <- finish; changed_finish$outcome <- "withdrawn"; changed_finish$operation_id <- "changed-finish"
  check("final outcome cannot be rewritten", call(finish_path, changed_finish, start$access_token)$status == 409L)
  extra <- events[length(events)]; extra[[1]]$sequence <- length(events)+1L; extra[[1]]$id <- "late-event"
  check("new events after finalization rejected", call(events_path, list(events = extra, operation_id = "late"), start$access_token)$status == 409L)
  check("original events still replay after finalization", call(events_path, first_batch, start$access_token)$status == 200L)
  all_events <- brohn_run_events(store, start$run_id)
  allocation_event <- Filter(function(e) identical(e$question_id, "q-allocation") && e$type == "response", all_events)[[1]]
  check("zero allocation and optional missing matrix stay distinct", allocation_event$payload$value[["option-1"]] == 0 &&
    is.null(Filter(function(e) identical(e$question_id, "q-matrix") && e$type == "response", all_events)[[1]]$payload$value$interest))
  second_finish <- list(outcome = "withdrawn", final_sequence = 0L, operation_id = "withdraw-second")
  check("withdrawal preserves separate terminal outcome", call(paste0("/api/finish/", second_start$run_id),
    second_finish, second_start$access_token)$status == 200L && brohn_run(store, second_start$run_id)$completion_status == "withdrawn")
  check("public credentials remain in separate private tables", !any(c("token", "token_hash") %in%
    DBI::dbListFields(store$con, "delivery_runs")))
  # Independently exercise the timed restart rule and typed response families.
  timed <- Filter(function(step) step$type == "stimulus", start$protocol$timeline)[[1]]
  tiny_protocol <- list(timeline = list(timed))
  tiny_state <- .brohn_delivery_initial_state()
  first_event <- list(sequence = 1L, id = "timed-start", type = "step_started", step_id = timed$id,
    stimulus_id = timed$stimulus_id, condition_id = timed$condition_id, question_id = NULL, phase = timed$phase,
    clock = list(id = "browser-monotonic", unit = "ms", value = "100", instance_id = "page-a"), payload = empty())
  tiny_state <- .brohn_delivery_apply(tiny_state, first_event, tiny_protocol)
  last_event <- first_event; last_event$type <- "step_finished"; last_event$id <- "timed-finish"; last_event$sequence <- 2L
  last_event$clock$value <- "101"
  check("too-short timed exposure rejected", rejects(.brohn_delivery_apply(tiny_state, last_event, tiny_protocol)))
  last_event$clock$value <- "300"; last_event$clock$instance_id <- "page-b"
  check("timed exposure cannot span a page restart", rejects(.brohn_delivery_apply(tiny_state, last_event, tiny_protocol)))
  check("incomplete ranking and allocation rejected", rejects(.brohn_delivery_answer(ranking, list(value = list("option-1")))) &&
    rejects(.brohn_delivery_answer(allocation, list(value = list("option-1" = 100)))))
  check("missing required matrix row rejected", rejects(.brohn_delivery_answer(within(matrix, required <- TRUE),
    list(value = list(clarity = 3, interest = NULL)))))
  numeric <- brohn_question("Numeric", "number", "end", "q-number"); numeric$min <- 0; numeric$max <- 10; numeric$step <- 2
  check("numeric zero accepted and wrong increment rejected", identical(.brohn_delivery_answer(numeric, list(value = 0)), 0) &&
    rejects(.brohn_delivery_answer(numeric, list(value = 3))))
  untimed <- start$protocol$timeline[[1]]
  untimed_state <- .brohn_delivery_initial_state()
  question_start <- first_event
  question_start$step_id <- untimed$id; question_start["stimulus_id"] <- list(NULL); question_start["condition_id"] <- list(NULL)
  question_start$phase <- untimed$phase
  untimed_protocol <- list(timeline = list(untimed))
  untimed_state <- .brohn_delivery_apply(untimed_state, question_start, untimed_protocol)
  resumed <- question_start; resumed$sequence <- 2L; resumed$id <- "resumed-start"; resumed$payload <- list(resumed = TRUE)
  resumed$clock$value <- "1"; resumed$clock$instance_id <- "new-page"
  check("untimed step resumes with a new observed clock segment", identical(.brohn_delivery_apply(untimed_state,
    resumed, untimed_protocol)$active$instance, "new-page"))
  check("resumed answer cannot claim uninterrupted RT", rejects(.brohn_delivery_answer(numeric,
    list(value = 2, resumed = TRUE, response_time_ms = 100))))
  interrupted_event <- first_event; interrupted_event$type <- "run_finished"; interrupted_event$sequence <- 2L
  interrupted_event$id <- "interrupted-ending"; interrupted_event$payload <- list(outcome = "interrupted")
  check("interrupted ending preserves unfinished timed evidence", identical(.brohn_delivery_apply(tiny_state,
    interrupted_event, tiny_protocol)$ending_outcome, "interrupted"))
  optional_design <- design; optional_design$id <- "study-optional-consent"; optional_design$consent$required <- FALSE
  brohn_put_entity(store, "study", optional_design$id, optional_design)
  optional_release <- brohn_publish(store, optional_design$id, quota = 1, alias_required = TRUE)
  optional_path <- paste0("/api/start/", optional_release$token)
  optional_request <- list(consented = FALSE, client_id = "optional-client", operation_id = "optional-start", participant_alias = "")
  check("required alias is enforced before allocation", call(optional_path, optional_request)$status == 422L)
  optional_request$participant_alias <- "P-test"
  optional_start <- call(optional_path, optional_request)
  check("optional acknowledgement follows frozen consent policy", optional_start$status == 200L &&
    brohn_run(store, optional_start$value$run_id)$participant_alias == "P-test" &&
    brohn_run(store, optional_start$value$run_id)$participant_alias_supplied)
  # Actual server subprocess uses the same retained workspace; this catches
  # httpuv request/response adapters beyond the in-process request mocks.
  port <- httpuv::randomPort()
  executable <- file.path(R.home("bin"), "Rscript.exe")
  if (!file.exists(executable)) executable <- file.path(R.home("bin"), "Rscript")
  process <- processx::process$new(executable, c("--vanilla", "scripts/run-participant.R", "--root", store$root,
    "--port", as.character(port), "--static-root", static), stdout = "|", stderr = "|", windows_hide_window = TRUE)
  read_url <- function(address) {
    connection <- url(address, open = "rb", method = "libcurl")
    on.exit(close(connection), add = TRUE)
    readLines(connection, warn = FALSE)
  }
  response_text <- NULL; deadline <- Sys.time() + 15
  while (Sys.time() < deadline && process$is_alive()) {
    response_text <- tryCatch(suppressWarnings(read_url(paste0("http://127.0.0.1:", port, entry_path))), error = function(e) NULL)
    if (!is.null(response_text)) break
    Sys.sleep(.1)
  }
  if (is.null(response_text)) stop("Loopback service failed: ", process$read_all_error())
  check("separate-process loopback HTTP reads pinned release", identical(jsonlite::fromJSON(paste(response_text,
    collapse = ""))$deployment$title, design$title))
  page <- paste(read_url(paste0("http://127.0.0.1:", port, "/participant/")), collapse = "")
  check("separate-process static interface is served", grepl("Synthetic runner fixture", page, fixed = TRUE))
  process$kill(); process$wait()
  retained <- brohn_run(store, start$run_id)
  brohn_close_store(store)
  store <- brohn_open_store(file.path(directory, "workspace"))
  check("restart preserves runs, receipts and pinned protocols", identical(brohn_run(store, start$run_id), retained) &&
    length(brohn_run_events(store, start$run_id)) == length(events))
  cat(sprintf("PASS: %d participant delivery checks (researcher release, assignment, consent, responses, receipts, recovery, HTTP)\n", count))
})
