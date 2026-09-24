# Focused source authority test on a private copy of an accepted review workspace.
source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=TRUE)
args<-commandArgs(trailingOnly=TRUE);stopifnot(length(args)==2L)
original<-normalizePath(args[[1]],winslash="/",mustWork=TRUE);folder<-normalizePath(args[[2]],winslash="/",mustWork=FALSE)
stopifnot(!dir.exists(folder),dir.exists(file.path(original,"workspace")));dir.create(folder,recursive=TRUE);dir.create(file.path(folder,"workspace"))
stopifnot(all(file.copy(list.files(file.path(original,"workspace"),full.names=TRUE,all.files=TRUE,no..=TRUE),file.path(folder,"workspace"),recursive=TRUE)))
checks<-character();check<-function(label,value){stopifnot(isTRUE(value));checks<<-c(checks,label);cat("PASS",label,"\n")}
rejects<-function(expr)inherits(try(force(expr),silent=TRUE),"try-error")
local({
  store<-brohn_open_store(file.path(folder,"workspace"));on.exit(brohn_close_store(store),add=TRUE)
  saved<-brohn_list_entities(store,"eda_continuous_review")[[1L]];report<-brohn_get_entity(store,"report",saved$body$report_id)
  before<-digest::digest(report$body,algo="sha256");source<-brohn_eda_continuous_review_record(store,saved$id,report$id,report$project_id)
  check("Complete accepted result validates before authority changes",identical(source$id,saved$id))
  DBI::dbBegin(store$con)
  denied<-tryCatch({DBI::dbExecute(store$con,"UPDATE entities SET project_id=? WHERE kind='report' AND id=?",params=list("deliberate-other-owner",report$id));
    rejects(brohn_eda_continuous_review_record(store,saved$id,report$id,report$project_id))},finally=DBI::dbRollback(store$con))
  check("Successful predicate cache cannot preserve access after report owner changes",denied)
  dataset_id<-report$body$dataset_id;DBI::dbBegin(store$con)
  denied<-tryCatch({DBI::dbExecute(store$con,"UPDATE entities SET project_id=? WHERE kind='dataset' AND id=?",params=list("deliberate-other-owner",dataset_id));
    rejects(brohn_eda_continuous_review_record(store,saved$id,report$id,report$project_id))},finally=DBI::dbRollback(store$con))
  check("Successful predicate cache cannot preserve access after dataset owner changes",denied)
  restored<-brohn_eda_continuous_review_record(store,saved$id,report$id,report$project_id)
  check("Restored original authority opens unchanged saved evidence",identical(restored$body,saved$body)&&identical(before,digest::digest(brohn_get_entity(store,"report",report$id)$body,algo="sha256")))
  brohn_write_json_file(list(passed=TRUE,checks=as.list(checks),copied_from=original,report_id=report$id,source_hashes=.brohn_eda_continuous_review_loaded,
    scope="Focused read-only source access with transient transactionally rolled-back owner substitutions. No new analysis or publication."),file.path(folder,"results.json"))
})
