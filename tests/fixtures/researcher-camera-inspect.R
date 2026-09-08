# Read-only inspection of original browser-camera QA records; never exports credentials.
args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) == 2L)
source('R/platform-load.R'); brohn_load(ui = FALSE)
store <- brohn_open_store(args[[1L]])
local({
  on.exit(brohn_close_store(store), add = TRUE)
  config <- brohn_read_json_file(args[[2L]])
  runs <- brohn_runs(store, config$study_id)
  config$runs <- lapply(runs, function(run) {
    capture <- brohn_capture(store, run_id = run$id)
    publication <- if (!is.null(capture)) brohn_get_entity(store, 'camera_capture', capture$id) else NULL
    chunks <- if (!is.null(capture)) DBI::dbGetQuery(store$con, 'SELECT sequence,content_hash,object_hash,observation_hash,byte_count FROM camera_chunks WHERE capture_id=? ORDER BY sequence', params = list(capture$id)) else data.frame()
    observations <- lapply(seq_len(nrow(chunks)), function(i) brohn_read_json_file(brohn_object_path(store, chunks$observation_hash[[i]])))
    dataset <- if (!is.null(publication)) brohn_get_entity(store, 'dataset', publication$body$dataset_id) else NULL
    reports <- if (!is.null(dataset)) Filter(function(r) identical(r$body$dataset_id, dataset$id), brohn_list_entities(store, 'report', limit = 10000L)) else list()
    jobs <- Filter(function(j) identical(j$request$run_id, run$id) || (!is.null(capture) && identical(j$request$capture_id, capture$id)) ||
      (!is.null(dataset) && identical(j$request$dataset_id, dataset$id)), brohn_list_jobs(store, limit = 10000L))
    list(run = run, protocol_hash = brohn_hash(run$protocol), events = brohn_run_events(store, run$id), capture = capture, publication = publication,
      camera_completion = brohn_camera_completion(store, run$id), chunks = brohn_rows(chunks), observations = observations, dataset = dataset,
      reports = reports, jobs = lapply(jobs, function(j) j[c('id','operation','status','request','result','error')]))
  })
  brohn_write_json_file(config, args[[2L]])
})
