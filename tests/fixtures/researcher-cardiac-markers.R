# Isolated copy of the completed recorded-data workspace; actual app and worker.
args <- commandArgs(trailingOnly = TRUE); mode <- args[[1L]]
folder <- normalizePath(args[[2L]], winslash = "/", mustWork = TRUE)
stopifnot(startsWith(basename(folder), "brohn-cardiac-marker-ui-"))
source("R/platform-load.R", encoding = "UTF-8"); brohn_load()
config_path <- file.path(folder, "fixture.json")
if (mode == "setup") local({
  source_folder <- normalizePath(args[[3L]], winslash = "/", mustWork = TRUE)
  proof <- brohn_read_json_file(file.path(source_folder, "acceptance.json"))
  stopifnot(proof$checks >= 5, identical(proof$detector_accuracy_qualified, FALSE), !file.exists(config_path), !dir.exists(file.path(folder, "workspace")))
  stopifnot(file.copy(proof$workspace, folder, recursive = TRUE))
  brohn_write_json_file(list(workspace = normalizePath(file.path(folder, "workspace"), winslash = "/"),
    port = httpuv::randomPort(min = 20000L, max = 49000L), report_id = proof$report_id, report_hash = proof$report_hash), config_path)
}) else if (mode == "serve") {
  config <- brohn_read_json_file(config_path); Sys.setenv(BROHN_WORKSPACE = config$workspace, BROHN_APP_MODE = "platform")
  stop_owned <- function() if (file.exists(file.path(folder, "stop.request"))) shiny::stopApp() else later::later(stop_owned, .2)
  later::later(stop_owned, .2); shiny::runApp(".", host = "127.0.0.1", port = config$port, launch.browser = FALSE)
} else if (mode == "worker") local({
  config <- brohn_read_json_file(config_path); store <- brohn_open_store(config$workspace); on.exit(brohn_close_store(store))
  repeat {
    if (file.exists(file.path(folder, "stop.request"))) break
    job <- brohn_claim_job(store, "cardiac-marker-browser", 120)
    if (is.null(job)) Sys.sleep(.2) else brohn_process_job(store, job, timeout_seconds = 100)
  }
}) else stop("Unknown fixture mode")
