# Read only the acquisition records belonging to this original QA study.
args <- commandArgs(trailingOnly = TRUE); stopifnot(length(args) == 2L)
source('R/platform-load.R');brohn_load(ui = FALSE)
store <- brohn_open_store(args[[1L]])
local({
  on.exit(brohn_close_store(store), add = TRUE)
  config <- brohn_read_json_file(args[[2L]])
  config$discoveries <- brohn_lsl_discoveries(store, config$study_id)
  config$recordings <- lapply(brohn_acquisitions(store,config$study_id), function(r) brohn_acquisition(store,r$id))
  config$datasets <- Filter(function(d) identical(d$body$study_id,config$study_id),brohn_list_entities(store,'dataset',limit=10000L))
  brohn_write_json_file(config,args[[2L]])
})
