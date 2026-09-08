# Read-only verification of this original source's curation/report catalog.
args <- commandArgs(trailingOnly = TRUE)
source('R/platform-load.R'); brohn_load(ui = FALSE)
store <- brohn_open_store(args[[1L]])
local({
  on.exit(brohn_close_store(store), add = TRUE)
  config <- brohn_read_json_file(args[[2L]])
  config$source <- brohn_get_entity(store, 'dataset', config$dataset_id)
  config$curations <- brohn_stream_curations(store, source_dataset_id = config$dataset_id)
  ids <- vapply(Filter(function(x) !is.null(x$body$dataset_id), config$curations), function(x) x$body$dataset_id, character(1))
  config$datasets <- lapply(ids, function(id) brohn_get_entity(store, 'dataset', id))
  config$reports <- Filter(function(r) r$body$dataset_id %in% ids, brohn_list_entities(store, 'report', limit = 10000L))
  config$jobs <- lapply(Filter(function(j) isTRUE(j$request$dataset_id %in% ids) ||
    (!is.null(j$request$stream_id) && j$request$stream_id %in% vapply(config$curations, function(c) c$body$stream_id, character(1))),
    brohn_list_jobs(store, limit = 10000L)), function(j) j[c('id','operation','status','request','result','error')])
  brohn_write_json_file(config, args[[2L]])
})
