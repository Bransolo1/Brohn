# Runs only on an owned fresh copy of an explicit closed prepared fixture.
args<-commandArgs(TRUE);stopifnot(length(args)==3L)
repo<-normalizePath(args[[1L]],winslash="/",mustWork=TRUE)
prepared<-normalizePath(args[[2L]],winslash="/",mustWork=TRUE)
out<-args[[3L]];stopifnot(!file.exists(out));dir.create(out,recursive=TRUE);out<-normalizePath(out,winslash="/",mustWork=TRUE)
stopifnot(dir.exists(file.path(prepared,"workspace")),file.copy(file.path(prepared,"workspace"),out,recursive=TRUE))
for(name in c("continuous-report.json","event-report.json"))if(file.exists(file.path(prepared,name)))stopifnot(file.copy(file.path(prepared,name),out,overwrite=FALSE))
stopifnot(file.copy(file.path(prepared,"results.json"),file.path(out,"original-results.json"),overwrite=FALSE))
config<-list(checkout=repo,out=out)
setwd(repo);source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=FALSE)
local({
 store<-brohn_open_store(file.path(config$out,"workspace"));checks<-list();timings<-list();handles<-list();scratch_paths<-character();passed<-FALSE;failure<-NULL
 env<-environment(brohn_prepare_eda_display_execution);original_prepare<-get("brohn_prepare_eda_display_execution",env);original_publish<-get("brohn_publish_eda_display",env)
 on.exit({assign("brohn_prepare_eda_display_execution",original_prepare,env);assign("brohn_publish_eda_display",original_publish,env)
   for(j in brohn_list_jobs(store,limit=1000L))if(j$status %in% c("queued","running"))brohn_cancel_job(store,j$id)
   brohn_write_json_file(list(passed=passed,checks=checks,timings=timings,failure=failure,
    instrumentation="Parent prepare/publish wrappers call unchanged functions and retain handles/timings for cleanup inspection; genuine child/source files unchanged."),file.path(config$out,"results.json"));brohn_close_store(store)},add=TRUE)
 check<-function(x,label){if(!isTRUE(x))stop(label);checks[[length(checks)+1L]]<<-label;cat("PASS",label,"\n")}
 refusal<-function(expr)inherits(try(force(expr),silent=TRUE),"try-error")
 rows<-function(t)DBI::dbGetQuery(store$con,paste("SELECT * FROM",t,"ORDER BY rowid"))
 before<-lapply(c("jobs","entity_versions","objects"),rows)
 assign("brohn_prepare_eda_display_execution",function(store,job,input,scratch,pulse=NULL){t<-proc.time()[[3L]];x<-original_prepare(store,job,input,scratch,pulse=pulse);timings[[paste0(job$id,"_parent_prepare_seconds")]]<<-proc.time()[[3L]]-t;handles[[job$id]]<<-x$handle;scratch_paths<<-c(scratch_paths,scratch);x},env)
 assign("brohn_publish_eda_display",function(store,output,scratch,job,input,output_path,pulse=NULL){t<-proc.time()[[3L]];on.exit(timings[[paste0(job$id,"_parent_publish_seconds")]]<<-proc.time()[[3L]]-t);original_publish(store,output,scratch,job,input,output_path,pulse=pulse)},env)
 tryCatch({
  original<-brohn_eda_read_json_file(file.path(config$out,"continuous-report.json"),16*1024^2);ref<-.brohn_rpk_ref(original)
  existing<-brohn_read_json_file(file.path(config$out,"original-results.json"))$prepared$continuous$display_ref
  opened<-brohn_open_eda_display_resources(store,existing,ref$project_id);on.exit(brohn_release_eda_display_resources(opened$handle),add=TRUE)
  catalog<-brohn_eda_display_catalog(store,existing,limit=1L);key<-catalog$items[[1L]]$key
  check(!is.null(catalog$next_cursor)&&identical(catalog$prepared_ref,existing),"bounded exact catalog exposes independently paged cells")
  check(refusal(brohn_eda_display_catalog(store,existing,list(scope=paste(rep("0",64),collapse=""),offset=1L))),"catalog rejects another exact preparation cursor")
  object_path<-get("brohn_object_path",env);reader<-get("brohn_eda_read_json_file",env)
  tryCatch({assign("brohn_object_path",function(store,hash,verify=FALSE){if(isTRUE(verify))stop("unexpected current-reader rehash");object_path(store,hash,verify)},env)
   assign("brohn_eda_read_json_file",function(...)stop("unexpected full evidence read in current/catalog"),env)
   brohn_eda_display_resources_current(store,opened$handle);brohn_eda_display_catalog(store,existing)
   check(TRUE,"fresh current and catalog checks perform no full evidence read or object rehash")
  },finally={assign("brohn_object_path",object_path,env);assign("brohn_eda_read_json_file",reader,env)})
  producer<-opened$record$body$producer$job_id
  for(id in c(producer,original$body$processing$job_id)){
   DBI::dbBegin(store$con);denied<-tryCatch({stopifnot(DBI::dbExecute(store$con,"UPDATE jobs SET status='failed' WHERE id=?",params=list(id))==1L);refusal(brohn_eda_display_resources_current(store,opened$handle))},finally=DBI::dbRollback(store$con))
   check(denied,"current reader refuses individually revoked preparation or original scientific producer")
  }
  check(refusal(brohn_open_eda_display_resources(store,existing,"another-project")),"opening refuses wrong current project")
  brohn_release_eda_display_resources(opened$handle);brohn_release_eda_display_resources(opened$handle)
  check(refusal(brohn_eda_display_resources_current(store,opened$handle)),"release is idempotent and closed resources cannot be reused")
  run<-function(request,label){j<-brohn_queue_eda_display(store,ref,request);check(identical(j$status,"queued"),paste(label,"queues exact normalized window"));claimed<-brohn_claim_job(store,"eda-boundary-qa",lease_seconds=60L);stopifnot(identical(claimed$id,j$id));t<-proc.time()[[3L]];brohn_process_job(store,claimed,timeout_seconds=600);timings[[paste0(j$id,"_total_seconds")]]<<-proc.time()[[3L]]-t;done<-brohn_get_job(store,j$id);check(isTRUE(handles[[j$id]]$state$closed)&&!dir.exists(tail(scratch_paths,1L)),paste(label,"releases sealed sources and removes owned scratch"));done}
  empty<-run(list(schema="brohn-eda-display-request/0.1",continuous_windows=list(list(key=key,start_s="0.01",end_s="0.02"))),"empty between-sample window")
  check(identical(empty$status,"succeeded"),paste("empty window publishes exact explanatory evidence",brohn_json(empty$error)))
  er<-brohn_get_entity(store,"eda_display",empty$result$eda_display_id);eo<-brohn_open_eda_display_resources(store,.brohn_rpk_ref(er),ref$project_id)
  tryCatch({cell<-Filter(function(x)identical(x$key,key),eo$evidence$cells)[[1L]];item<-Filter(function(x)identical(x$key,key),er$body$catalog)[[1L]]
   check(identical(cell$status,"no_processed_samples")&&!is.null(cell$model)&&.brohn_rpk_hash(cell$model_hash)&&!length(item$components)&&item$marker_page_count==0L,"empty view retains model/hash and one explanatory state without invented component figures")
   check(identical(brohn_eda_value_hash(cell$original_support),brohn_eda_value_hash(original$body$analysis$recordings[[1L]])),"empty view preserves complete original segment support")
   stopifnot(file.copy(eo$artifact$path,file.path(config$out,"empty-evidence.json")))
  },finally=brohn_release_eda_display_resources(eo$handle))
  saved_entities<-rows("entity_versions");saved_objects<-rows("objects")
  bad<-run(list(schema="brohn-eda-display-request/0.1",continuous_windows=list(list(key=paste(rep("f",64),collapse=""),start_s="0.01",end_s="0.02"))),"unknown original cell")
  check(identical(bad$status,"failed")&&!identical(bad$error$schema,"brohn-eda-report-refusal/0.1")&&is.null(bad$result),"ordinary genuine child error terminates without invented limit refusal")
  check(identical(saved_entities,rows("entity_versions"))&&identical(saved_objects,rows("objects")),"ordinary child error publishes no partial evidence or entity")
  after<-lapply(c("jobs","entity_versions","objects"),rows)
  check(identical(before[[1L]],after[[1L]][match(before[[1L]]$id,after[[1L]]$id),,drop=FALSE]),"all prior scientific and preparation jobs unchanged")
  check(identical(before[[2L]],after[[2L]][seq_len(nrow(before[[2L]])),,drop=FALSE])&&identical(before[[3L]],after[[3L]][seq_len(nrow(before[[3L]])),,drop=FALSE]),"all original saved revisions and object metadata unchanged")
  for(hash in before[[3L]]$hash)brohn_object_path(store,hash,TRUE)
  check(TRUE,"all original objects remain byte-exact after success and ordinary failure")
  check(all(vapply(brohn_list_jobs(store,limit=1000L),function(j)!j$status %in% c("queued","running"),logical(1))),"all attempts terminal; no background work remains")
  passed<-TRUE
 },error=function(e){failure<<-conditionMessage(e);stop(e)})
})
