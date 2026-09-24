# Retained synthetic source before/after scoped duplicate-validation removal.
source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=TRUE)
args<-commandArgs(trailingOnly=TRUE);stopifnot(length(args)==1L);folder<-normalizePath(args[[1L]],winslash="/",mustWork=TRUE)
stopifnot(startsWith(basename(folder),"brohn-media-review-browser-"))
local({s<-brohn_open_store(file.path(folder,"workspace"));on.exit(brohn_close_store(s),add=TRUE)
  old<-brohn_read_json_file(file.path(folder,"source-before-optimization.json"));ref<-.brohn_mr_ref(old$review)
  elapsed<-numeric();value<-NULL;for(i in 1:3){t<-system.time(value<-brohn_media_review_source(s,ref,old$review$project_id,FALSE));elapsed<-c(elapsed,unname(t[["elapsed"]]))}
  checks<-character();check<-function(name,x){stopifnot(isTRUE(x));checks<<-c(checks,name);cat("PASS",name,"\n")}
  check("Every complete source and artifact reference equals the preoptimization fixture",.brohn_mr_same(value$source_objects,old$source_objects))
  check("All original source records and exact artifact descriptors are unchanged",.brohn_mr_same(value,old))
  DBI::dbBegin(s$con);revoked<-FALSE
  tryCatch({DBI::dbExecute(s$con,"UPDATE entities SET project_id='media-revoked' WHERE kind='dataset' AND id=?",params=list(old$parent$id))
    revoked<-inherits(try(brohn_media_review_source(s,ref,old$review$project_id,FALSE),silent=TRUE),"try-error")},finally=DBI::dbRollback(s$con))
  check("Source ownership revoked after caching is freshly refused",revoked)
  check("Restored source authority returns exact original refs after rollback",.brohn_mr_same(brohn_media_review_source(s,ref,old$review$project_id,FALSE),old))
  body<-brohn_read_json_file(file.path(folder,"fixture.json"));brohn_write_json_file(list(passed=TRUE,checks=as.list(checks),elapsed_seconds=as.list(elapsed),source_hashes=.brohn_media_review_loaded),file.path(folder,"responsiveness-source-checks.json"))
  cat("Source seconds:",paste(elapsed,collapse=", "),"\n")
})
