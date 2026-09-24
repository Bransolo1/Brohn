# Actual scientific worker, with one deliberate catalog change immediately
# before publication commits. No production source is replaced or edited.
args<-commandArgs(trailingOnly=TRUE);stopifnot(length(args)==2L)
source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=FALSE)
folder<-normalizePath(args[[1]],winslash="/",mustWork=TRUE);output<-normalizePath(args[[2]],winslash="/",mustWork=TRUE)
stopifnot(startsWith(basename(folder),"brohn-audio-extract-browser-"),startsWith(basename(output),"publication-"),!file.exists(file.path(output,"result.json")))
local({
  store<-brohn_open_store(file.path(folder,"workspace"));on.exit(brohn_close_store(store),add=TRUE)
  config<-brohn_read_json_file(file.path(folder,"fixture.json"));parent<-Filter(function(x)identical(x$kind,"multiple"),config$sources)[[1L]]
  ds<-Filter(function(x)identical(x$body$source_provenance$parent_dataset$id,parent$id)&&x$body$status%in%c("accepted","analysed"),brohn_list_entities(store,"dataset"))
  stopifnot(length(ds)==1L,!any(vapply(brohn_list_jobs(store),function(j)j$status%in%c("queued","running"),logical(1))))
  before<-brohn_list_entities(store,"report");before_hashes<-lapply(before,function(r)list(id=r$id,hash=brohn_hash(r$body)))
  prior_parent<-brohn_get_entity(store,"dataset",parent$id);source_hash<-digest::digest(file=brohn_object_path(store,prior_parent$body$source$hash),algo="sha256")
  queued<-brohn_queue_dataset(store,ds[[1L]]$id,force=TRUE);job<-brohn_claim_job(store,"audio-lineage-publication-fault",120);stopifnot(identical(job$id,queued$id))
  original<-brohn_publish_analysis_report;fired<-FALSE
  assign("brohn_publish_analysis_report",function(store,job,input,result,scratch,result_path,timeout_seconds=1900,before_commit=NULL){
    original(store,job,input,result,scratch,result_path,timeout_seconds,before_commit=function(){
      if(!is.null(before_commit))before_commit()
      fired<<-TRUE
      DBI::dbExecute(store$con,"UPDATE entities SET project_id='deliberate-audio-qa-foreign' WHERE kind='dataset' AND id=?",params=list(parent$id))
    })
  },envir=.GlobalEnv)
  on.exit(assign("brohn_publish_analysis_report",original,envir=.GlobalEnv),add=TRUE)
  brohn_process_job(store,job,timeout_seconds=300)
  final<-brohn_get_job(store,job$id);after<-brohn_list_entities(store,"report");restored<-brohn_get_entity(store,"dataset",parent$id)
  checks<-list(callback_reached=fired,job_failed=identical(final$status,"failed"),source_reason=grepl("project|source|authority|unavailable",final$error$message,ignore.case=TRUE),
    no_report_published=length(after)==length(before),all_original_reports_unchanged=all(vapply(before_hashes,function(r)identical(brohn_hash(brohn_get_entity(store,"report",r$id)$body),r$hash),logical(1))),
    catalog_change_rolled_back=identical(restored$project_id,prior_parent$project_id)&&identical(brohn_hash(restored$body),brohn_hash(prior_parent$body)),
    original_video_unchanged=identical(digest::digest(file=brohn_object_path(store,restored$body$source$hash),algo="sha256"),source_hash))
  brohn_write_json_file(list(passed=all(unlist(checks)),checks=checks,job=final[c("id","operation","status","error")],source_sha256=source_hash,
    source_hashes=list(analysis=digest::digest(file="R/platform-analysis.R",algo="sha256"),jobs=digest::digest(file="R/platform-jobs.R",algo="sha256"),extraction=.brohn_audio_extraction_loaded),
    scope="Actual scientific worker with temporary in-process before_commit fault injection. The deliberate failed job remains retained; all source ownership/report changes roll back."),file.path(output,"result.json"))
  stopifnot(all(unlist(checks)));cat(length(checks),"actual publication revocation checks passed\n")
})
