# Isolated test supervisor; uses the actual production job processor.
args <- commandArgs(trailingOnly=TRUE)
stopifnot(length(args)==2)
source("R/platform-load.R", encoding="UTF-8"); brohn_load(ui=FALSE)
local({
  store <- brohn_open_store(args[[1]]); on.exit(brohn_close_store(store),add=TRUE)
  job <- brohn_get_job(store,args[[2]])
  brohn_process_job(store,job,timeout_seconds=30)
})
