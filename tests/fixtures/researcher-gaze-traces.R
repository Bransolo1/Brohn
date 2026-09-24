args <- commandArgs(trailingOnly = TRUE); stopifnot(length(args) >= 2L)
mode <- args[[1L]]; folder <- normalizePath(args[[2L]], winslash = "/", mustWork = TRUE)
stopifnot(startsWith(basename(folder), "brohn-gaze-browser-"))
source("R/platform-load.R", encoding = "UTF-8"); brohn_load()
config_path <- file.path(folder, "fixture.json")
if (mode == "setup") local({
  reference <- brohn_read_json_file(file.path(args[[3L]], "acceptance.json"))
  stopifnot(!file.exists(config_path), !dir.exists(file.path(folder, "workspace")), file.copy(reference$workspace, folder, recursive = TRUE))
  store <- brohn_open_store(file.path(folder, "workspace")); on.exit(brohn_close_store(store))
  report <- brohn_get_entity(store, "report", reference$report_id)
  artifact <- brohn_signal_artifact(report, "physiology-series")
  candidates <- Filter(function(r) !identical(r$id, report$id) && identical(r$body$analysis$kind, "gaze"), brohn_list_entities(store, "report", limit = 100L))
  port <- suppressWarnings(as.integer(Sys.getenv("BROHN_GAZE_TEST_PORT", unset = NA_character_)))
  if (is.na(port)) port <- httpuv::randomPort(min = 21000L, max = 49000L)
  stopifnot(port >= 1024L, port <= 65535L)
  config <- list(workspace = store$root, port = port,
    report_id = report$id, report_hash = brohn_hash(report$body), study_id = reference$study_id, artifact = artifact,
    second_report_id = if (length(candidates)) candidates[[1L]]$id else NULL)
  brohn_write_json_file(config, config_path)
}) else if (mode == "serve") {
  config <- brohn_read_json_file(config_path); Sys.setenv(BROHN_WORKSPACE = config$workspace, BROHN_APP_MODE = "platform")
  stop_owned <- function() if (file.exists(file.path(folder, "stop.request"))) shiny::stopApp() else later::later(stop_owned, .2)
  later::later(stop_owned, .2); shiny::runApp(".", host = "127.0.0.1", port = config$port, launch.browser = FALSE)
} else if (mode == "worker") local({
  config <- brohn_read_json_file(config_path); store <- brohn_open_store(config$workspace); on.exit(brohn_close_store(store))
  repeat {
    if (file.exists(file.path(folder, "stop.request"))) break
    if (file.exists(file.path(folder, "worker.pause"))) {Sys.sleep(.2); next}
    job <- brohn_claim_job(store, "gaze-trace-browser", 300)
    if (is.null(job)) Sys.sleep(.2) else brohn_process_job(store, job, timeout_seconds = 300)
  }
}) else if (mode == "inspect") local({
  config <- brohn_read_json_file(config_path); store <- brohn_open_store(config$workspace); on.exit(brohn_close_store(store))
  brohn_write_json_file(list(views = brohn_list_entities(store, "gaze_trace_view", limit = 100L), jobs = brohn_list_jobs(store, limit = 200L),
    original_report_hash = brohn_hash(brohn_get_entity(store, "report", config$report_id)$body),
    artifact_hash = digest::digest(file = brohn_object_path(store, config$artifact$sha256), algo = "sha256")), file.path(folder, "inspection.json"))
}) else stop("Unknown gaze browser fixture mode.")
