args<-commandArgs(trailingOnly=TRUE);stopifnot(length(args)==3L)
repo<-normalizePath(args[[1L]],winslash="/",mustWork=TRUE);original<-normalizePath(args[[2L]],winslash="/",mustWork=TRUE)
out<-args[[3L]];stopifnot(!file.exists(out));dir.create(out,recursive=TRUE);out<-normalizePath(out,winslash="/")
setwd(repo);source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=FALSE)
inventory<-function(root){xs<-list.files(root,recursive=TRUE,full.names=TRUE,all.files=TRUE,no..=TRUE);xs<-xs[!dir.exists(xs)];stats::setNames(vapply(xs,function(p)digest::digest(file=p,algo="sha256"),character(1)),substring(xs,nchar(root)+2L))}
original_before<-inventory(original);workspace<-file.path(out,"workspace");dir.create(workspace)
stopifnot(all(file.copy(list.files(file.path(original,"workspace"),full.names=TRUE,all.files=TRUE,no..=TRUE),workspace,recursive=TRUE)))
local({
 store<-brohn_open_store(workspace);on.exit(brohn_close_store(store),add=TRUE);guards<-list();on.exit(for(g in guards).brohn_qexplorer_release(g),add=TRUE)
 checks<-list();failure<-NULL
 check<-function(ok,label){if(!isTRUE(ok))stop(label);checks[[length(checks)+1L]]<<-list(name=label,passed=TRUE)}
 table_snapshot<-function()stats::setNames(lapply(c("jobs","entities","entity_versions","objects"),function(t)DBI::dbGetQuery(store$con,paste("SELECT * FROM",t,"ORDER BY rowid"))),c("jobs","entities","entity_versions","objects"))
 before<-table_snapshot();freeze<-brohn_read_json_file(file.path(original,"FREEZE.json"));x<-freeze$review
 tryCatch({
  r<-brohn_eda_continuous_review_record(store,x$review_id,x$report_ref$id,x$report_ref$project_id)
  check(identical(brohn_hash(r$body),x$review_hash),"exact original standalone1.0 record opens under changed source code")
  check(!.brohn_ecr_same(r$body$request$implementation,.brohn_eda_continuous_review_loaded),"historical acceptance is not accidental current-code equality")
  check(identical(r$body$result$schema,"brohn-eda-continuous-review/1.0")&&identical(r$body$request$recipe,"saved-continuous-eda-review/1.0"),"historical method/request/model remain1.0")
  input<-.brohn_ecr_record_source(store,r$id,r$body$report_id,r$project_id)$input
  check(inherits(try(brohn_eda_continuous_review_input(store,list(operation="eda_continuous_review",request=r$body$request),FALSE),silent=TRUE),"try-error"),"old request cannot silently execute under changed code")
  refs<-c(input$source_objects,lapply(r$body$exports,function(x)list(hash=x$hash,bytes=x$size)),list(list(hash=r$body$result_object$hash,bytes=r$body$result_object$size)))
  refs<-unname(refs[!duplicated(vapply(refs,`[[`,character(1),"hash"))]);input$source_objects<-refs
  guards<-brohn_hold_signal_value_sources(store,input)
  check(length(guards)==length(refs),"native holds cover every original source/document/export before verification")
  snapshot<-file.path(out,"reader-snapshot.rds")
  saveRDS(list(body=r$body[setdiff(names(r$body),"result_object")],input=input,paths=lapply(refs,function(x)list(path=brohn_object_path(store,x$hash,FALSE),sha256=x$hash)),retained_path=brohn_object_path(store,r$body$result_object$hash,FALSE)),snapshot)
  .brohn_ecr_verify_snapshot(snapshot)
  for(g in guards).Call(g$native$check,g$pointer)
  check(TRUE,"held background-reader snapshot verifies exact historical artifacts without current-code gate")
  for(name in names(x$exports)){d<-x$exports[[name]];p<-brohn_object_path(store,d$hash,FALSE);check(file.info(p)$size==d$size&&identical(digest::digest(file=p,algo="sha256"),d$hash),paste(name,"retains original complete bytes"))}
  DBI::dbBegin(store$con)
  failed<-tryCatch({DBI::dbExecute(store$con,"UPDATE jobs SET status='failed' WHERE id=?",params=list(x$job_id));inherits(try(brohn_eda_continuous_review_record(store,r$id,r$body$report_id,r$project_id),silent=TRUE),"try-error")},finally=DBI::dbRollback(store$con))
  check(failed,"current original-producer revocation still refuses historical read")
  check(identical(before,table_snapshot()),"all jobs/entity versions/object metadata unchanged; no new scientific/preparation jobs")
  check(identical(original_before,inventory(original)),"original fixture inventory remains byte exact")
 },error=function(e)failure<<-conditionMessage(e))
 for(g in guards).brohn_qexplorer_release(g);guards<-list()
 brohn_write_json_file(list(schema="brohn-constant-historical-reader-tests/0.1",passed=is.null(failure),count=length(checks),checks=checks,error=failure,
  scope="Actual copied-store native source/export holds and original recipe1.0 cold record/snapshot read under changed R code. Producer revocation is a rolled-back owned-store SQL probe. No browser, hosted identity, new scientific worker or regeneration."),file.path(out,"results.json"))
 if(!is.null(failure))stop(failure);cat("Passed",length(checks),"historical reader checks\n")
})
