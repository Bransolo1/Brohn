# Reactive exposure coordination and visible-field capture, isolated from storage.
# Full authority/native publication is exercised by the actual saved-job fixture.
source("R/platform-participant-equipment.R")
for (module in c("platform-core", "platform-gaze-traces", "platform-gaze-trace-views")) source(paste0("R/", module, ".R"))
local({
  checks <- 0L; check <- function(name, value) {if (!isTRUE(value)) stop("FAIL: ", name); checks <<- checks+1L; cat("PASS ", name, "\n", sep = "")}
  adapter <- new.env(parent = .GlobalEnv)
  source("R/platform-gaze-trace-server.R", local = adapter)
  hash <- strrep("a", 64)
  table <- function(person) list(table_id = paste0("table-", person), identity = list(recording_id = paste0("rec-", person), channel = "pupil",
    participant_id = person, session_id = "same-session", stimulus_id = "same-stimulus", exposure_id = "same-exposure"),
    rows = 22L, start_ms = 0, end_ms = 210, initial_window = list(start_ms = 0, end_ms = 210, rows = 22L))
  tables <- list(table("person-a"), table("person-b"))
  selector <- function(person) paste(hash, brohn_hash(list(person, "same-session", "same-stimulus", "same-exposure")), sep = ":")
  check("matching includes person identity despite identical clocks/session/stimulus/exposure labels",
    adapter$brohn_gaze_trace_match_exposure(tables, selector("person-b"), hash)$table_id == "table-person-b")
  check("foreign report selector cannot choose this catalog", is.null(adapter$brohn_gaze_trace_match_exposure(tables, selector("person-a"), strrep("b", 64))))
  old <- list(analysis = list(kind = "gaze", parameters = list(input = "raw_gaze_samples"), features = list()), provenance = list(mapping = list()))
  check("x/y-only report does not promise a rerun can create absent pupil or blink data", is.null(adapter$brohn_gaze_trace_report_ui(old)))
  old$provenance$mapping$pupil_column <- "pupil"
  text <- htmltools::renderTags(adapter$brohn_gaze_trace_report_ui(old))$html
  check("mapped historical report clearly requires a new original analysis", grepl("fresh analysis", text, fixed = TRUE))
  record <- list(id = "gaze-catalog", revision = 1L, project_id = "project-a", body = list(operation = "gaze_trace_catalog", result = list(tables = tables)))
  calls <- list(); jobs <- list(); authority <- TRUE
  adapter$.brohn_qexplorer_catalog <- function(...) {brohn_require(authority, "Changed project authority"); "catalog-hash"}
  adapter$brohn_project <- function(...) invisible(TRUE)
  adapter$brohn_gaze_trace_record <- function(...) record
  adapter$brohn_get_job <- function(store, id) jobs[[id]]
  adapter$brohn_queue_gaze_trace <- function(store, report_id, report_revision, report_hash, project_id, catalog = NULL, selection = NULL, retry = FALSE) {
    calls[[length(calls)+1L]] <<- list(report_id = report_id, catalog = catalog, selection = selection)
    id <- paste0("job-", length(calls)); job <- list(id = id, status = "queued", request = list(report_hash = report_hash), operation = "gaze_trace_preview")
    jobs[[id]] <<- job; job
  }
  server <- function(input, output, session) {
    state <- shiny::reactiveValues(page = "report", report_id = "report-a")
    session$userData$state <- state
    attempt <- function(fn) tryCatch(fn(), error = function(e) session$userData$error <- conditionMessage(e))
    session$userData$api <- adapter$brohn_install_gaze_trace_server(input, output, session, list(), state, attempt,
      message = function(text) invisible(text), prepare_download = function(fn) fn())
  }
  shiny::testServer(server, {
    session$flushReact()
    api <- session$userData$api
    api$active(list(report_id = "report-a", revision = 1L, report_hash = hash, project_id = "project-a", catalog_hash = "catalog-hash"))
    api$catalog(record)
    session$setInputs(gaze_report_exposure = selector("person-a"), gaze_trace_table = "table-person-a")
    session$flushReact()
    check("first bounded preview matches the selected gaze participant", length(calls) > 0L && tail(calls, 1)[[1]]$selection$identity$participant_id == "person-a")
    # A previously rendered result must disappear before the new dropdown echo.
    api$preview(list(id = "old-window", body = list(result = list())))
    session$setInputs(gaze_report_exposure = selector("person-b")); session$flushReact()
    check("existing gaze exposure switch immediately clears the old pupil result", is.null(api$preview()))
    session$setInputs(gaze_trace_table = "table-person-b"); session$flushReact()
    check("new exposure window uses the new person's exact source identity", tail(calls, 1)[[1]]$selection$identity$participant_id == "person-b")
    c <- api$catalog(); t <- tables[[2L]]
    payload <- list(action = "preview", catalog_id = c$id, catalog_hash = brohn_hash(c$body), table_id = t$table_id,
      fields = list(form = paste(c$id, c$revision, brohn_hash(c$body), t$table_id, sep = ":"), start = "10", end = "20", full = FALSE), sequence = 1L)
    session$setInputs(gaze_trace_start = "0", gaze_trace_end = "210", gaze_trace_action = payload); session$flushReact()
    latest <- tail(calls, 1)[[1]]$selection
    check("immediate action uses submitted visible fields rather than lagging Shiny inputs", latest$start_ms == 10 && latest$end_ms == 20)
    before <- length(calls); payload$fields$form <- "stale-other-person"; payload$sequence <- 2L
    session$setInputs(gaze_trace_action = payload); session$flushReact()
    check("stale exposure form cannot queue another person's time window", length(calls) == before && grepl("current window controls", session$userData$error, fixed = TRUE))
    session$userData$state$page <- "study"; session$flushReact()
    check("leaving report clears catalog, preview and active binding", is.null(api$active()) && is.null(api$catalog()) && is.null(api$preview()))
  })
  cat(sprintf("PASS: %d isolated gaze-trace server checks; storage/native acceptance remains separate.\n", checks))
})
