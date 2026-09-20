# Original synthetic answers and a real immutable SQLite index. Storage stubs
# isolate the Shiny component; worker/publication authority is tested separately.
source("R/platform-load.R", encoding = "UTF-8"); brohn_load(ui = TRUE)
source("R/platform-questionnaire-index.R", encoding = "UTF-8")
source("R/platform-questionnaire-explorer-views.R", encoding = "UTF-8")
local({
  checks <- 0L
  check <- function(value, label) {if (!isTRUE(value)) stop(label, call. = FALSE); checks <<- checks+1L; cat("PASS", label, "\n")}
  folder <- tempfile("irp-qx-ui-"); dir.create(folder)
  long <- paste0(strrep("\u00e9\u6f22\U0001f512\n", 20000), "<script>retained</script>")
  values <- c(list(FALSE, 0, "0", NULL, "", list(FALSE, 0), "<script>answer</script>", long), as.list(9:72))
  records <- lapply(seq_along(values), function(i) list(question_id = paste0("q-", i), prompt = paste("Frozen prompt", i),
    participant_id = if (i %% 2) "unlinked:visit-one" else "alias:shared-code", session_id = if (i %% 2) "visit-one" else "visit-two",
    participant_linkage = i %% 2 == 0, occurrence_id = paste0("occurrence-", i), step_id = paste0("step-", i),
    condition_id = "control", stimulus_id = "repeated-label", status = if (is.null(values[[i]])) "optional_omission" else "answered", value = values[[i]], origin = "sample"))
  features <- lapply(1:12, function(i) list(question_id = paste0("q-", i), prompt = paste("Summary prompt", i), condition_id = "control",
    response_count = 72, answered_count = 71, missing_count = 1, numeric_response_mean = 4,
    numeric_summary_status = "declared_quantitative_question", counts = if (i == 12) lapply(1:72, function(j) list(value = j, count = 73-j)) else list()))
  analysis <- list(kind = "questionnaire", features = features, observations = records, quality = list(response_count = 72))
  body <- list(id = "report-qx-ui", study_id = "study-qx-ui", origin = "sample", provenance = list(design = list(id = "study-qx-ui", project_id = "default")), analysis = analysis)
  report_record <- list(id = body$id, revision = 1L, project_id = "default", body = body)
  binding <- list(workspace_id = "workspace-qx-ui", project_id = "default", report_id = body$id, report_revision = 1L,
    report_hash = brohn_hash(body), origin = "sample", analysis_sha256 = brohn_hash(analysis))
  built <- brohn_build_questionnaire_index(list(schema = "brohn-questionnaire-index-input/1.0", binding = binding, report = body), file.path(folder, "index.sqlite"))
  handle <- brohn_questionnaire_index_open(built$index$path, built$index, binding)
  on.exit(brohn_questionnaire_index_close(handle), add = TRUE)
  opened <- list(record = list(id = "index-qx-ui", body = list(origin = "sample", answer_source = "recorded_observations", binding = binding,
    original_counts = handle$manifest$original_counts, source_support = "catalog_revision_without_retained_worker_envelope")), handle = handle,
    context = list(index_hash = brohn_hash(built)))
  command <- list(report_id = body$id, report_revision = 1L, report_hash = brohn_hash(body), project_id = "default")
  job <- list(id = "job-qx-ui", request = command, status = "succeeded", result = list(questionnaire_index_id = "index-qx-ui", index_hash = brohn_hash(built)))
  set_job_status <- function(status) job$status <<- status
  calls <- new.env(parent = emptyenv()); calls$guards <- 0L; calls$opens <- 0L; calls$closes <- 0L; calls$cancel <- 0L; calls$retry <- 0L
  calls$reject_context <- FALSE
  replacements <- list(
    brohn_get_entity = function(store, kind, id, ...) report_record,
    brohn_queue_questionnaire_index = function(...) job,
    brohn_open_questionnaire_index = function(...) {calls$opens <- calls$opens+1L; opened},
    brohn_close_questionnaire_index = function(...) {calls$closes <- calls$closes+1L; invisible(NULL)},
    brohn_check_questionnaire_index_context = function(...) {calls$guards <- calls$guards+1L; if (calls$reject_context) stop("Source access removed"); invisible(TRUE)},
    .brohn_qexplorer_job = function(...) job,
    brohn_cancel_questionnaire_index = function(...) {calls$cancel <- calls$cancel+1L; job$status <<- "cancelled"; job},
    brohn_retry_questionnaire_index = function(...) {calls$retry <- calls$retry+1L; job$status <<- "succeeded"; job})
  before <- lapply(names(replacements), function(name) if (exists(name, envir = .GlobalEnv, inherits = FALSE)) get(name, envir = .GlobalEnv) else NULL)
  names(before) <- names(replacements)
  for (name in names(replacements)) assign(name, replacements[[name]], envir = .GlobalEnv)
  on.exit(for (name in names(before)) if (is.null(before[[name]])) rm(list = name, envir = .GlobalEnv) else assign(name, before[[name]], envir = .GlobalEnv), add = TRUE)
  server <- function(input, output, session) {
    state <- shiny::reactiveValues(page = "report", report_id = body$id, error = NULL, refresh = 0L)
    attempt <- function(fn, ...) {state$error <- NULL; tryCatch(fn(), error = function(e) {state$error <- conditionMessage(e); NULL})}
    explorer <- brohn_install_questionnaire_explorer(input, output, session, list(), state, attempt, function(...) NULL, function(fn) fn())
  }
  shiny::testServer(server, {
    session$setInputs(open_questionnaire_explorer = command)
    if (!is.null(state$error)) stop(state$error)
    check(!is.null(explorer$ready()) && calls$opens == 1, "Successful saved job opens one source-bound index")
    identity <- explorer$ready()$identity
    act <- function(action, collection = NULL, form = list(limit = "50"), ...) {
      session$setInputs(qx_action = c(list(action = action, collection = collection, form = form, form_identity = identity, identity = identity), list(...)))
    }
    row_command <- function(collection, row, generation = 1L, form = list(limit = "50")) act("record", collection, form,
      key = row$record_key, hash = row$source_hash, generation = generation, focus_id = paste0("qx-row-", collection, "-", row$ordinal))
    detail_action <- function(action, ...) act(action, detail_key = explorer$detail$record$record$record_key, ...)
    check(explorer$pages$answers$matching_total == 72 && explorer$pages$answers$returned == 50 && explorer$pages$questions$returned == 12, "Complete collections cross both preview boundaries")
    first_body <- output$qx_body$html
    check(grepl("Match case", first_body, fixed = TRUE) && grepl("Every available final state", first_body, fixed = TRUE), "Stable form advertises literal case matching and all states")
    first <- explorer$pages$answers
    check(grepl("Abbreviated in this list", output$qx_answers$html, fixed = TRUE), "Long values render a safe explicit abbreviation in the result list")
    act("next", "answers", generation = 1L)
    if (!is.null(state$error)) stop(state$error)
    check(explorer$pages$answers$returned == 22 && explorer$pages$answers$rows[[1]]$ordinal == 51, "Next reaches saved answers beyond the fifty-row preview")
    check(grepl("72 matching records; 72 records", output$qx_answers$html, fixed = TRUE), "Page announces matching and full saved source counts")
    state$refresh <- state$refresh+1L; session$flushReact()
    check(identical(output$qx_body$html, first_body) && explorer$pages$answers$rows[[1]]$ordinal == 51, "Unrelated refresh preserves stable form and active page")
    act("next", "answers", form = list(search = "Frozen prompt 72", limit = "50"), generation = 2L)
    check(explorer$pages$answers$returned == 1 && explorer$pages$answers$rows[[1]]$ordinal == 72, "Immediate filter then next atomically starts the new query at its first page")
    target <- explorer$pages$answers$rows[[1]]
    row_command("answers", target, 3L, list(search = "Frozen prompt 72", limit = "50"))
    check(explorer$detail$record$record$ordinal == 72 && grepl("visit-two", output$qx_detail$html, fixed = TRUE), "Exact row opens full participant/session and assessment detail")
    detail_action("changes")
    check(grepl("No edit history was retained for this source", output$qx_detail$html, fixed = TRUE), "Imported records never manufacture zero edits")
    detail_action("close")
    check(is.null(explorer$detail$record) && explorer$pages$answers$rows[[1]]$ordinal == 72, "Closing detail keeps filters and page")
    state$error <- NULL
    act("record", "answers", form = list(search = "Frozen prompt 72", limit = "50"), key = first$rows[[1]]$record_key, hash = first$rows[[1]]$source_hash, generation = 1L)
    check(!is.null(state$error) && is.null(explorer$detail$record), "A stale generation cannot reopen another page's row")
    act("apply", "answers")
    for (i in 1:7) {
      row_command("answers", explorer$pages$answers$rows[[i]], 4L)
      check(identical(explorer$detail$record$record$value_kind, c("boolean", "number", "text", "null", "text", "structured", "text")[[i]]), paste("Native typed detail", i, "retained"))
    }
    check(grepl("&lt;script&gt;answer&lt;/script&gt;", output$qx_detail$html, fixed = TRUE) && !grepl("<script>answer", output$qx_detail$html, fixed = TRUE), "HTML-like values are escaped text")
    row_command("answers", explorer$pages$answers$rows[[8]], 4L)
    check(isTRUE(explorer$detail$record$record_chunked) && identical(explorer$detail$record$full_prompt, "Frozen prompt 8"), "Large source rows keep a full frozen prompt with bounded source content")
    parts <- list(explorer$detail$value$text)
    while (!is.null(explorer$detail$value$next_offset)) {
      offset <- explorer$detail$value$offset
      detail_action("chunk_next", field = "value", chunk_offset = offset)
      parts[[length(parts)+1L]] <- explorer$detail$value$text
    }
    check(identical(paste0(unlist(parts), collapse = ""), long), "All UTF-8 value chunks reproduce the exact complete long answer")
    last <- explorer$detail$value$offset
    detail_action("chunk_previous", field = "value", chunk_offset = last)
    check(explorer$detail$value$offset < last, "Previous chunk returns without losing native text")
    state$error <- NULL
    detail_action("chunk_next", field = "value", chunk_offset = last)
    check(!is.null(state$error), "A stale text-chunk action is rejected")
    detail_action("source")
    check(explorer$detail$source$field == "record" && grepl("Canonical source JSON", output$qx_detail$html, fixed = TRUE), "Complete canonical source is reachable independently of value chunks")
    row_command("questions", explorer$pages$questions$rows[[12]], 1L)
    check(explorer$pages$distribution$returned == 50 && explorer$pages$distribution$source_total == 72, "Question beyond preview opens a separately paged complete distribution")
    act("next", "distribution", generation = 1L)
    check(explorer$pages$distribution$rows[[22]]$summary$count == 1, "Distinctive distribution entry beyond five and fifty retains its saved count")
    act("previous", "distribution", generation = 2L)
    check(explorer$pages$distribution$rows[[1]]$ordinal == 1 && is.null(explorer$pages$distribution$previous_cursor), "Bounded previous cursor returns to the first independent distribution page")
    saved_mean <- explorer$pages$questions$rows[[12]]$summary$numeric_response_mean
    detail_action("answers")
    check(explorer$pages$answers$matching_total == 1 && explorer$pages$answers$rows[[1]]$question_id == "q-12", "See answers applies the exact selected question and condition")
    check(saved_mean == 4 && explorer$pages$questions$rows[[12]]$summary$response_count == 72, "Participant filtering never recalculates whole-report summaries")
    state$error <- NULL
    session$setInputs(qx_action = list(action = "apply", collection = "answers", form = list(limit = "50"), form_identity = "foreign-index"))
    check(!is.null(state$error), "Foreign form identity is rejected before source query")
    check(calls$guards > 20, "Every source action rechecks the bound index authority")
    calls$reject_context <- TRUE; act("apply", "answers")
    check(is.null(explorer$ready()) && is.null(explorer$pages$answers) && is.null(explorer$pages$questions) && is.null(explorer$detail$record) &&
      is.null(explorer$detail$value) && is.null(explorer$detail$source) && calls$closes == 1, "Access loss immediately clears retained source content and closes its handle")
    calls$reject_context <- FALSE
    state$page <- "home"; session$flushReact()
    check(is.null(explorer$ready()) && is.null(explorer$detail$record) && calls$closes == 1, "Navigation immediately clears source content and closes owned handles")
    state$page <- "report"; set_job_status("queued"); session$setInputs(open_questionnaire_explorer = NULL); session$setInputs(open_questionnaire_explorer = command)
    if (is.null(explorer$progress()) || explorer$progress()$status != "queued") stop(paste("Queued opening failed:", state$error))
    check(grepl("Preparing saved answers", output$qx_progress$html, fixed = TRUE) && !grepl("<progress[^>]*value=", output$qx_progress$html), "Preparation reports honest indeterminate progress")
    session$setInputs(qx_cancel = list(job_id = job$id, report_hash = command$report_hash))
    check(calls$cancel == 1 && is.null(explorer$ready()) && explorer$progress()$status == "cancelled", "Cancellation retains the report without opening an index")
    session$setInputs(qx_retry = list(job_id = job$id, report_hash = command$report_hash))
    check(calls$retry == 1 && !is.null(explorer$ready()), "Retry opens the same frozen source after successful preparation")
  })
  html <- as.character(brohn_questionnaire_explorer_ui(report_record))
  check(grepl("Explore all answers", html, fixed = TRUE) && grepl("report_revision", html, fixed = TRUE), "Opening action contains exact report revision and source hash")
  check(identical(.brohn_qx_saved_mean(list(numeric_response_mean = 9, numeric_summary_status = "unavailable_categorical_or_structured_question")), "Unavailable in saved summary"), "A saved categorical status cannot expose a fabricated numeric mean")
  leading <- as.character(.brohn_qx_chunk_ui(list(text = "\nhello<script>", value_kind = "text", field = "value", offset = 0L,
    total_characters = 14L, total_utf8_bytes = 14L, value_hash = brohn_hash("\nhello<script>")), "fixture"))
  check(grepl("<span>\nhello&lt;script&gt;</span></pre>", leading, fixed = TRUE), "Leading newlines survive HTML pre parsing without added whitespace or unsafe markup")
  cat(sprintf("PASS: %d questionnaire explorer UI checks\n", checks))
})
