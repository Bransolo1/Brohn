# Read-only report retake. Existing source reports are never regenerated.
args <- commandArgs(trailingOnly = TRUE); mode <- args[[1L]]
source('R/platform-load.R'); brohn_load(ui = TRUE)
folder <- normalizePath(args[[2L]], winslash = '/', mustWork = TRUE)
stopifnot(identical(basename(folder), 'brohn-peripheral-ui-leyspE'))
evidence <- file.path(folder, 'presentation-retake'); dir.create(evidence, showWarnings = FALSE)
workspace <- file.path(folder, 'workspace'); config_path <- file.path(evidence, 'config.json')
if (mode == 'serve') {
  config <- brohn_read_json_file(config_path)
  Sys.setenv(BROHN_WORKSPACE = workspace, BROHN_APP_MODE = 'platform')
  check_stop <- function() if (file.exists(file.path(evidence, 'stop.request'))) shiny::stopApp() else later::later(check_stop, .2)
  later::later(check_stop, .2)
  shiny::runApp('.', host = '127.0.0.1', port = config$port, launch.browser = FALSE)
} else local({
  store <- brohn_open_store(workspace); on.exit(brohn_close_store(store), add = TRUE)
  if (mode == 'prepare') {
    stopifnot(!file.exists(config_path))
    original <- brohn_read_json_file(file.path(folder, 'fixture.json'))
    brohn_write_json_file(list(port = httpuv::randomPort(min = 20000L, max = 59000L),
      study_id = original$study_id, title = original$title), config_path)
  }
  reports <- brohn_list_entities(store, 'report', limit = 10000L)
  records <- lapply(reports, function(record) {
    object <- brohn_object_path(store, record$body$result_object$hash, verify = TRUE)
    envelope <- brohn_read_json_file(object)
    list(id = record$id, revision = record$revision, hash = brohn_hash(record$body), body = record$body,
      object_hash = digest::digest(file = object, algo = 'sha256'), envelope_matches =
        identical(brohn_hash(envelope$report), brohn_hash(record$body[setdiff(names(record$body), 'result_object')])) )
  })
  sources <- lapply(brohn_list_entities(store, 'dataset', limit = 10000L), function(record) list(id = record$id,
    revision = record$revision, hash = brohn_hash(record$body), source_hash = digest::digest(file = brohn_object_path(store, record$body$source$hash), algo = 'sha256')))
  jobs <- lapply(brohn_list_jobs(store, limit = 10000L), function(job) job[c('id', 'status', 'attempt')])
  brohn_write_json_file(list(reports = records, sources = sources, jobs = jobs), file.path(evidence, 'snapshot.json'))
})
