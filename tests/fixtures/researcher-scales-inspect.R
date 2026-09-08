# Read-only original scale researcher fixtures, reports and job status.
args <- commandArgs(trailingOnly = TRUE)
source('R/platform-load.R'); brohn_load(ui = FALSE)
store <- brohn_open_store(args[[1L]])
local({
  on.exit(brohn_close_store(store), add = TRUE)
  config <- brohn_read_json_file(args[[2L]])
  config$study <- brohn_get_entity(store, 'study', config$study_id)
  config$runs <- brohn_runs(store, config$study_id)
  config$reports <- Filter(function(r) identical(r$body$study_id, config$study_id), brohn_list_entities(store, 'report', limit = 10000L))
  config$datasets <- Filter(function(r) identical(r$body$study_id, config$study_id), brohn_list_entities(store, 'dataset', limit = 10000L))
  run_ids <- vapply(config$runs, `[[`, character(1), 'id')
  dataset_ids <- vapply(config$datasets, `[[`, character(1), 'id')
  deployments <- vapply(brohn_deployments(store, config$study_id), `[[`, character(1), 'id')
  config$jobs <- lapply(Filter(function(j) isTRUE(j$request$run_id %in% run_ids) || isTRUE(j$request$deployment_id %in% deployments) ||
    isTRUE(j$request$dataset_id %in% dataset_ids), brohn_list_jobs(store, limit = 10000L)), function(j) j[c('id','operation','status','request','result','error')])
  brohn_write_json_file(config, args[[2L]])
})
