# Isolated empty workspace; the browser authors every dataset mapping and job.
args <- commandArgs(trailingOnly=TRUE); mode <- args[[1L]]
folder <- normalizePath(args[[2L]], winslash="/", mustWork=TRUE)
stopifnot(startsWith(basename(folder), "brohn-neural-map-"))
source("R/platform-load.R", encoding="UTF-8"); brohn_load()
config_path <- file.path(folder, "fixture.json")
if (mode == "setup") local({
  stopifnot(!file.exists(config_path)); store <- brohn_open_store(file.path(folder,"workspace")); on.exit(brohn_close_store(store))
  brohn_initialise_library(store)
  processx::run(brohn_python_profile("eeg"), c("-B", "tests/fixtures/researcher-neural-plots.py", folder), windows_hide_window=TRUE)
  brohn_write_json_file(list(workspace=store$root, port=httpuv::randomPort(min=20000L,max=49000L)), config_path)
}) else if (mode == "serve") {
  config <- brohn_read_json_file(config_path); Sys.setenv(BROHN_WORKSPACE=config$workspace, BROHN_APP_MODE="platform")
  stop_owned <- function() if (file.exists(file.path(folder,"stop.request"))) shiny::stopApp() else later::later(stop_owned,.2)
  later::later(stop_owned,.2); shiny::runApp(".",host="127.0.0.1",port=config$port,launch.browser=FALSE)
} else if (mode == "worker") local({
  config <- brohn_read_json_file(config_path); store <- brohn_open_store(config$workspace); on.exit(brohn_close_store(store))
  repeat {
    if (file.exists(file.path(folder,"stop.request"))) break
    job <- brohn_claim_job(store,"neural-map-browser",120)
    if (is.null(job)) Sys.sleep(.2) else brohn_process_job(store,job,timeout_seconds=100)
  }
}) else stop("Unknown fixture mode")
