# Actual original-analysis, complete-trace jobs and source-guard lifecycle.
args<-commandArgs(trailingOnly=TRUE);stopifnot(length(args)==2L)
source("R/platform-load.R",encoding="UTF-8");brohn_load()
local({
  reference<-normalizePath(args[[1]],winslash="/",mustWork=TRUE);folder<-normalizePath(args[[2]],winslash="/",mustWork=FALSE)
  stopifnot(!dir.exists(folder),startsWith(basename(folder),"brohn-gaze-saved-"));dir.create(folder,recursive=TRUE)
  store<-brohn_open_store(file.path(folder,"workspace"));brohn_initialise_library(store);on.exit(brohn_close_store(store))
  checks<-character();check<-function(label,ok){if(!isTRUE(ok))stop(label);checks<<-c(checks,label);cat("PASS ",label,"\n",sep="")}
  rejected<-function(x)inherits(try(force(x),silent=TRUE),"try-error")
  execute<-function(q,success=TRUE){force(q);claim<-brohn_claim_job(store,"gaze-retention-reference",300);stopifnot(claim$id==q$id)
    brohn_process_job(store,claim,timeout_seconds=300);done<-brohn_get_job(store,q$id)
    if(success&&done$status!="succeeded")stop(brohn_json(done$error));done}
  study<-brohn_create_study(store,"Original complete pupil and blink software fixture")
  path<-file.path(reference,"source.csv");payload<-brohn_read_json_file(file.path(reference,"gaze-trace-request.json"))
  mapping<-payload$provenance$parameters$mapping;mapping$origin<-"sample"
  mapping$origin_statement<-"Original hand-specified source rows, with independent 4-to-6 pupil arithmetic and invalid/blink cases; no hardware or physiological qualification."
  imported<-brohn_ingest_dataset(store,path,"Original complete pupil and blink software fixture","gaze",origin="sample")
  dataset<-brohn_curate_dataset(store,imported$id,mapping,imported$revision,study$id,study$revision)
  original<-brohn_object_path(store,dataset$body$source$hash);Sys.chmod(original,"0666")
  probe<-function()processx::run(.brohn_publication_python(),c("-B","-c","import sys;f=open(sys.argv[1],'r+b');f.close()",original),error_on_status=FALSE,windows_hide_window=TRUE)$status==0L
  check("original CSV is writable before native guards after removing ordinary readonly attribute",probe())
  prepare<-brohn_prepare_publication;denied<-FALSE
  assign("brohn_prepare_publication",function(...){denied<<-!probe();prepare(...)},envir=.GlobalEnv)
  on.exit(assign("brohn_prepare_publication",prepare,envir=.GlobalEnv),add=TRUE)
  done<-tryCatch(execute(brohn_queue_dataset(store,dataset$id)),finally=assign("brohn_prepare_publication",prepare,envir=.GlobalEnv))
  check("actual original analysis holds its native source guard through publication",denied)
  check("native source guard releases after original report publication",probe())
  report<-brohn_get_entity(store,"report",done$result$report_id);report_hash<-brohn_hash(report$body);a<-report$body$analysis
  check("actual report retains all47 original source rows and3 exposure groups",a$quality$trace_source_rows==47&&a$quality$trace_tables==3&&a$artifact_verification$status=="verified")
  clean<-Filter(function(x)identical(x$record_type,"pupil_summary")&&identical(x$exposure_id,"clean"),a$features)[[1L]]
  check("automatic report preserves independent4-to-6 subtractive arithmetic",clean$baseline_mean==4&&clean$mean_pupil==6&&clean$baseline_corrected_mean==2)
  check("new boundary policy is explicit and gaze remains unqualified",a$parameters$blink_boundary_policy=="source-labelled-blink-boundaries/1.1"&&!isTRUE(a$quality$qualified))
  q<-brohn_queue_gaze_trace(store,report$id,report$revision,report_hash,report$project_id)
  done<-execute(q);catalog<-brohn_get_entity(store,"gaze_trace_view",done$result$gaze_trace_view_id)
  check("actual complete trace catalog retains the no-view group",length(catalog$body$result$tables)==3&&any(vapply(catalog$body$result$tables,function(t)identical(t$baseline_status,"no_passive_phase"),logical(1))))
  views<-list()
  for(name in c("clean","dirty")) {
    t<-Filter(function(t)identical(t$identity$exposure_id,name),catalog$body$result$tables)[[1L]]
    selection<-list(table_id=t$table_id,identity=t$identity,start_ms=t$initial_window$start_ms,end_ms=t$initial_window$end_ms)
    q<-brohn_queue_gaze_trace(store,report$id,report$revision,report_hash,report$project_id,
      catalog=list(id=catalog$id,revision=catalog$revision,hash=brohn_hash(catalog$body)),selection=selection)
    done<-execute(q);v<-brohn_get_entity(store,"gaze_trace_view",done$result$gaze_trace_view_id)
    check(paste(name,"saved preview preserves exact22rows in source order"),v$body$result$selected_rows==22&&length(v$body$result$rows)==22)
    if(name=="clean")check("all eligible saved pupil corrections equal2",all(vapply(Filter(function(row)!is.null(row$pupil_minus_baseline),v$body$result$rows),function(row)row$pupil_minus_baseline==2,logical(1))))
    if(name=="dirty")check("native row JSON preserves difficult decimal and signedzero after publication",any(vapply(v$body$result$rows,function(row)grepl("6.000000000000001",row$exact_record_json,fixed=TRUE),logical(1)))&&any(vapply(v$body$result$rows,function(row)grepl('"pupil":-0.0',row$exact_record_json,fixed=TRUE),logical(1))))
    views[[name]]<-list(id=v$id,hash=brohn_hash(v$body));brohn_write_json_file(v$body$result,file.path(folder,paste0(name,"-preview.json")))
  }
  numeric_catalog_job<-execute(brohn_queue_signal_view(store,report$id,"physiology-series"))
  numeric_catalog<-brohn_get_entity(store,"signal_view",numeric_catalog_job$result$signal_view_id)
  t<-Filter(function(t)identical(t$identity$exposure_id,"dirty"),numeric_catalog$body$view$tables)[[1L]]
  check("generic catalog retains pupil numeric inspection without granting interval eligibility",length(numeric_catalog$body$view$tables)==3&&
    rejected(brohn_create_signal_annotations(store,numeric_catalog$id,t$table_id,"Unsupported generic pupil interval")))
  selected<-list(table_id=t$table_id,recording_id=t$identity$recording_id,channel=t$identity$channel,value_column="pupil",range=NULL,row_policy="all_source_rows")
  exported<-execute(brohn_queue_signal_values(store,numeric_catalog$id,selected,mode="export"))
  exact<-brohn_get_entity(store,"signal_values",exported$result$signal_values_id)
  csv_path<-brohn_object_path(store,exact$body$csv_object$hash)
  csv<-read.csv(csv_path,colClasses="character",check.names=FALSE,na.strings=NULL,fileEncoding="UTF-8")
  check("complete pupil CSV preserves every22rows and exact native signedzero and decimal",nrow(csv)==22&&exact$body$result$csv$rows==22&&
    any(csv$value=="-0.0")&&any(csv$value=="6.000000000000001"))
  check("complete pupil CSV preserves native pupil eligibility and blink flags",any(grepl('"source_blink":true',csv$exact_record_json,fixed=TRUE))&&
    any(grepl('"effective_pupil_valid":false',csv$exact_record_json,fixed=TRUE)))
  # Revoke current project authority after preparation, before final publication.
  project<-brohn_project(store);revoked<-FALSE
  assign("brohn_prepare_publication",function(...){result<-prepare(...);p<-brohn_project(store);b<-p$body;b$archived<-TRUE
    brohn_put_entity(store,"project",p$id,b,p$revision);revoked<<-TRUE;result},envir=.GlobalEnv)
  refused<-tryCatch(execute(brohn_queue_dataset(store,dataset$id,force=TRUE),FALSE),finally=assign("brohn_prepare_publication",prepare,envir=.GlobalEnv))
  check("authority revoked after preparation prevents final report publication",revoked&&refused$status=="failed"&&is.null(refused$result)&&is.null(brohn_get_entity(store,"report",paste0("report-",refused$id))))
  current<-brohn_get_entity(store,"project","default");brohn_put_entity(store,"project","default",project$body,current$revision)
  retried<-execute(brohn_retry_processing(store,refused$id))
  check("same frozen original analysis can retry after authority restoration",retried$status=="succeeded")
  check("original report and CSV are unchanged by views and retry",identical(brohn_hash(brohn_get_entity(store,"report",report$id)$body),report_hash)&&identical(digest::digest(file=original,algo="sha256"),dataset$body$source$hash))
  Sys.chmod(original,"0444");brohn_close_store(store);store<-brohn_open_store(file.path(folder,"workspace"))
  for(v in views)check(paste(v$id,"reopens unchanged"),identical(brohn_hash(brohn_get_entity(store,"gaze_trace_view",v$id)$body),v$hash))
  brohn_write_json_file(list(checks=checks,workspace=store$root,report_id=report$id,report_hash=report_hash,dataset_id=dataset$id,study_id=study$id,
    catalog_id=catalog$id,views=views,numeric_catalog_id=numeric_catalog$id,numeric_values_id=exact$id,jobs=brohn_list_jobs(store,limit=100L),origin="sample",hardware_qualified=FALSE),file.path(folder,"acceptance.json"))
})
