# Original synthetic guided-entry fixture. No participant service is launched.
args <- commandArgs(trailingOnly = TRUE); mode <- args[[1L]]
source("R/platform-load.R", encoding = "UTF-8"); brohn_load(ui = TRUE)
folder <- normalizePath(args[[2L]], winslash = "/", mustWork = TRUE)
stopifnot(startsWith(basename(folder), "brohn-guidance-"))
config_path <- file.path(folder, "fixture.json")
if (mode == "serve") {
  config <- brohn_read_json_file(config_path)
  Sys.setenv(BROHN_WORKSPACE = config$workspace, BROHN_APP_MODE = "platform")
  stop_owned <- function() if (file.exists(file.path(folder, "stop.request"))) shiny::stopApp() else later::later(stop_owned, .2)
  later::later(stop_owned, .2)
  shiny::runApp(".", host = "127.0.0.1", port = config$port, launch.browser = FALSE)
} else local({
  store <- brohn_open_store(file.path(folder, "workspace")); on.exit(brohn_close_store(store), add = TRUE)
  if (mode == "setup") {
    stopifnot(!file.exists(config_path)); brohn_initialise_library(store)
    brohn_write_json_file(list(schema = "brohn-guidance-qa/1.0", workspace = store$root,
      port = httpuv::randomPort(min = 20000L, max = 49000L)), config_path)
  } else if (mode == "inspect") {
    brohn_write_json_file(list(studies = brohn_studies(store), templates = brohn_list_entities(store, "template"),
      runs = if (DBI::dbExistsTable(store$con, "delivery_runs")) DBI::dbGetQuery(store$con, "SELECT count(*) n FROM delivery_runs")$n[[1]] else 0L,
      reports = length(brohn_list_entities(store, "report")), datasets = length(brohn_list_entities(store, "dataset"))), file.path(folder, "snapshot.json"))
  } else if (mode == "seed-long") {
    d <- brohn_new_design("Original sixty-question preparation fixture", "survey", "study-guidance-long")
    d$questions <- lapply(1:60, function(i) brohn_question(paste("Original source question", i), "text", "end", paste0("question-guidance-", i)))
    brohn_put_entity(store, "study", d$id, d)
  } else stop("Unknown fixture mode")
})
