# Genuine unchanged large originals, actual frozen limit and smaller-window recovery.
# No lowered limits, forged source results, scientific rerun, or worker stubs.
args<-commandArgs(TRUE);stopifnot(length(args)==3L)
repo<-normalizePath(args[[1L]],winslash="/",mustWork=TRUE)
originals<-normalizePath(args[[2L]],winslash="/",mustWork=TRUE)
out<-args[[3L]];stopifnot(!file.exists(out));dir.create(out,recursive=TRUE);out<-normalizePath(out,winslash="/",mustWork=TRUE)
stopifnot(dir.exists(file.path(originals,"workspace")),file.copy(file.path(originals,"workspace"),out,recursive=TRUE),file.copy(file.path(originals,"large-report.json"),out,overwrite=FALSE))
config<-list(checkout=repo,out=out)
setwd(repo);source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=FALSE)
local({store<-brohn_open_store(file.path(config$out,"workspace"));checks<-list();timings<-list();handles<-list();scratch_paths<-character();passed<-FALSE;failure<-NULL
 env<-environment(brohn_prepare_eda_display_execution);prepare<-get("brohn_prepare_eda_display_execution",env);publish<-get("brohn_publish_eda_display",env)
 on.exit({assign("brohn_prepare_eda_display_execution",prepare,env);assign("brohn_publish_eda_display",publish,env)
  for(j in brohn_list_jobs(store,limit=1000L))if(j$status %in% c("queued","running"))brohn_cancel_job(store,j$id)
  brohn_write_json_file(list(passed=passed,checks=checks,timings=timings,failure=failure,instrumentation="Parent stage timers call unchanged functions and retain returned native handles only for cleanup checks; child files and frozen limits unchanged."),file.path(config$out,"results.json"));brohn_close_store(store)},add=TRUE)
 check<-function(x,label){if(!isTRUE(x))stop(label);checks[[length(checks)+1L]]<<-label;cat("PASS",label,"\n")}
 rows<-function(t)DBI::dbGetQuery(store$con,paste("SELECT * FROM",t,"ORDER BY rowid"));before<-lapply(c("jobs","entity_versions","objects"),rows)
 assign("brohn_prepare_eda_display_execution",function(store,job,input,scratch,pulse=NULL){t<-proc.time()[[3L]];x<-prepare(store,job,input,scratch,pulse=pulse);timings[[paste0(job$id,"_prepare_seconds")]]<<-proc.time()[[3L]]-t;handles[[job$id]]<<-x$handle;scratch_paths<<-c(scratch_paths,scratch);x},env)
 assign("brohn_publish_eda_display",function(store,output,scratch,job,input,output_path,pulse=NULL){t<-proc.time()[[3L]];on.exit(timings[[paste0(job$id,"_publish_seconds")]]<<-proc.time()[[3L]]-t);publish(store,output,scratch,job,input,output_path,pulse=pulse)},env)
 tryCatch({
  original<-brohn_eda_read_json_file(file.path(config$out,"large-report.json"),16*1024^2);ref<-.brohn_rpk_ref(original)
  check(length(original$body$analysis$recordings)==1L&&original$body$analysis$recordings[[1L]]$samples==500100,"genuine unchanged original exceeds the actual500000 sample display bound")
  catalog<-brohn_eda_source_windows(store,ref);key<-catalog$items[[1L]]$key
  check(catalog$items[[1L]]$focusable&&catalog$total==1L&&is.null(brohn_find_eda_display(store,ref)),"cold exact source bounds are accessible before any prepared display exists")
  run<-function(request){j<-brohn_queue_eda_display(store,ref,request);stopifnot(j$status=="queued");claimed<-brohn_claim_job(store,"eda-actual-bound-qa",lease_seconds=60L);stopifnot(identical(claimed$id,j$id));t<-proc.time()[[3L]];brohn_process_job(store,claimed,timeout_seconds=600);timings[[paste0(j$id,"_total_seconds")]]<<-proc.time()[[3L]]-t;done<-brohn_get_job(store,j$id);check(isTRUE(handles[[j$id]]$state$closed)&&!dir.exists(tail(scratch_paths,1L)),paste(done$status,"attempt releases all source holds and removes owned scratch"));done}
  refused<-run(NULL);e<-refused$error
  check(identical(refused$status,"failed")&&identical(e$schema,"brohn-eda-report-refusal/0.1")&&identical(e$source_preserved,TRUE)&&.brohn_rpk_same(e$source,ref),paste("actual worker returns source-bound typed refusal",brohn_json(e)))
  check(e$measured==500100&&e$maximum==500000&&identical(e$recovery_scope,"smaller_window"),"refusal reports exact actual sample count and frozen limit with valid window recovery")
  check(identical(before[[2L]],rows("entity_versions"))&&identical(before[[3L]],rows("objects")),"typed refusal publishes no partial artifact or entity")
  same<-brohn_eda_source_windows(store,ref);check(identical(same$source_binding_hash,catalog$source_binding_hash)&&identical(same$items[[1L]]$key,key),"failed default keeps exact original window editing available")
  focused<-run(list(schema="brohn-eda-display-request/0.1",continuous_windows=list(list(key=key,start_s="10.0",end_s="20.00"))))
  check(identical(focused$status,"succeeded"),paste("real smaller-window preparation succeeds without scientific rerun",brohn_json(focused$error)))
  r<-brohn_get_entity(store,"eda_display",focused$result$eda_display_id);opened<-brohn_open_eda_display_resources(store,.brohn_rpk_ref(r),ref$project_id)
  tryCatch({brohn_eda_display_resources_current(store,opened$handle);ev<-opened$evidence
   check(ev$coverage$original_rows==sum(vapply(original$body$analysis$artifacts,`[[`,numeric(1),"rows"))&&identical(ev$coverage$complete_processed_rows,TRUE)&&identical(ev$coverage$scientific_processing,FALSE),"focused display retains complete original stream inventory and no-science coverage")
   check(.brohn_rpk_same(ev$cells[[1L]]$requested_bounds,list(start_s="1e1",end_s="2e1"))&&ev$cells[[1L]]$model$counts$selected_samples==101,"focused display binds exact10..20 seconds and101 original samples")
   stopifnot(file.copy(opened$artifact$path,file.path(config$out,"large-evidence.json")),!file.exists(file.path(config$out,"large-prepared.json")))
   report<-list(ref=ref,saved_body=original$body,complete_analysis=original$body$analysis)
   brohn_eda_write_json_file(list(report=report,eda_display=list(ref=.brohn_rpk_ref(r),body=r$body,evidence=ev)),file.path(config$out,"large-prepared.json"),48*1024^2)
  },finally=brohn_release_eda_display_resources(opened$handle))
  after<-lapply(c("jobs","entity_versions","objects"),rows)
  check(identical(before[[1L]],after[[1L]][match(before[[1L]]$id,after[[1L]]$id),,drop=FALSE]),"original ingestion and scientific job rows remain exact")
  check(identical(before[[2L]],after[[2L]][seq_len(nrow(before[[2L]])),,drop=FALSE])&&identical(before[[3L]],after[[3L]][seq_len(nrow(before[[3L]])),,drop=FALSE]),"original report versions and object metadata remain exact")
  for(hash in before[[3L]]$hash)brohn_object_path(store,hash,TRUE)
  check(TRUE,"all original raw and complete processed objects remain byte-exact")
  check(all(vapply(brohn_list_jobs(store,limit=1000L),function(j)!j$status %in% c("queued","running"),logical(1))),"all source and display attempts terminal")
  passed<-TRUE
 },error=function(e){failure<<-conditionMessage(e);stop(e)})
})
