# Genuine preparation/publication on a fresh copy of explicit original fixtures.
args<-commandArgs(TRUE);stopifnot(length(args)==3L)
repo<-normalizePath(args[[1L]],winslash="/",mustWork=TRUE)
originals<-normalizePath(args[[2L]],winslash="/",mustWork=TRUE)
out<-args[[3L]];stopifnot(!file.exists(out));dir.create(out,recursive=TRUE);out<-normalizePath(out,winslash="/",mustWork=TRUE)
stopifnot(dir.exists(file.path(originals,"workspace")),file.copy(file.path(originals,"workspace"),out,recursive=TRUE))
cases<-Filter(function(n)file.exists(file.path(originals,paste0(n,"-report.json"))),c("event","continuous","cvxeda","unavailable","controlled"))
stopifnot(length(cases)>0L)
for(name in cases)stopifnot(file.copy(file.path(originals,paste0(name,"-report.json")),out,overwrite=FALSE))
cfg<-list(checkout=repo,out=out,cases=cases);config<-cfg
setwd(repo);source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=FALSE)
local({out<-config$out;store<-brohn_open_store(file.path(out,"workspace"));checks<-list();prepared<-list();passed<-FALSE;failure<-NULL
 on.exit({for(j in brohn_list_jobs(store,limit=1000L))if(j$status %in% c("queued","running"))brohn_cancel_job(store,j$id);brohn_write_json_file(list(passed=passed,checks=checks,prepared=prepared,failure=failure),file.path(out,"results.json"));brohn_close_store(store)},add=TRUE)
 check<-function(value,label){if(!isTRUE(value))stop(label);checks[[length(checks)+1L]]<<-label;cat("PASS",label,"\n")}
 rows<-function(table)DBI::dbGetQuery(store$con,paste0("SELECT * FROM ",table," ORDER BY rowid"))
 beforejobs<-rows("jobs");beforeversions<-rows("entity_versions");beforeobjects<-rows("objects")
 tryCatch({
  for(name in brohn_default(config$cases,c("event","continuous","cvxeda","unavailable","controlled"))){
   original<-brohn_eda_read_json_file(file.path(out,paste0(name,"-report.json")),16*1024^2);ref<-.brohn_rpk_ref(original)
   queued<-brohn_queue_eda_display(store,ref);check(identical(queued$status,"queued"),paste(name,"cheap exact source queue"))
   job<-brohn_claim_job(store,"eda-display-source-qa",lease_seconds=60L);stopifnot(identical(job$id,queued$id),identical(job$operation,"eda_display"))
   brohn_process_job(store,job,timeout_seconds=600)
   done<-brohn_get_job(store,job$id);check(identical(done$status,"succeeded"),paste(name,"genuine worker publishes",brohn_json(done$error)))
   record<-brohn_get_entity(store,"eda_display",done$result$eda_display_id);displayref<-.brohn_rpk_ref(record)
   opened<-brohn_open_eda_display_resources(store,displayref,ref$project_id)
   current<-brohn_eda_display_resources_current(store,opened$handle)
   check(.brohn_rpk_same(current$record$body,record$body),paste(name,"fresh exact saved current reader"))
   stopifnot(file.copy(opened$artifact$path,file.path(out,paste0(name,"-evidence.json")),overwrite=FALSE)); evidence<-brohn_eda_read_json_file(opened$artifact$path,24*1024^2)
   report<-list(ref=ref,saved_body=original$body,complete_analysis=original$body$analysis)
   brohn_validate_eda_display_evidence(evidence,report,record$body)
   brohn_eda_write_json_file(list(report=report,eda_display=list(ref=displayref,body=record$body,evidence=evidence)),file.path(out,paste0(name,"-prepared.json")),48*1024^2)
   check(identical(brohn_eda_value_hash(evidence$source$original_stream_descriptors),brohn_eda_value_hash(original$body$analysis$artifacts)),paste(name,"all original stream descriptors preserved"))
   brohn_release_eda_display_resources(opened$handle);brohn_release_eda_display_resources(opened$handle)
   check(.brohn_rpk_same(brohn_find_eda_display(store,ref),displayref),paste(name,"exact reusable preparation"))
   prepared[[name]]<-list(report_ref=ref,display_ref=displayref,job_id=job$id)
  }
  check(identical(beforejobs,rows("jobs")[match(beforejobs$id,rows("jobs")$id),,drop=FALSE]),"original scientific job rows unchanged")
  after<-rows("entity_versions");keep<-seq_len(nrow(beforeversions));check(identical(beforeversions,after[keep,,drop=FALSE]),"all original saved source revisions unchanged")
  after<-rows("objects");check(identical(beforeobjects,after[seq_len(nrow(beforeobjects)),,drop=FALSE]),"original object metadata unchanged")
  for(hash in beforeobjects$hash)brohn_object_path(store,hash,TRUE)
  check(TRUE,"all original object bytes still verify");passed<-TRUE
 },error=function(e){failure<<-conditionMessage(e);stop(e)})
})
