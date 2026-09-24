# Read-only derived event windows from complete original saved EDA evidence.
.brohn_eda_review_loaded <- stats::setNames(list(digest::digest(file="R/platform-eda-review.R",algo="sha256")),"R/platform-eda-review.R")
.brohn_er_same <- function(a,b)identical(.brohn_sv_hash(a),.brohn_sv_hash(b))
brohn_eda_review_supported <- function(report)identical(report$analysis$operation,"eda_events")&&identical(report$analysis$modality,"eda")&&length(report$analysis$recordings)>0L
brohn_eda_review_selection <- function(analysis,selection) {
  brohn_fields(selection,c("recording_id","event_id","channel"),label="EDA event selection")
  brohn_require(all(vapply(selection,brohn_text,logical(1),max=500)),"Choose an exact saved recording, event and channel.")
  matches<-Filter(function(e)all(vapply(names(selection),function(k)identical(e[[k]],selection[[k]]),logical(1))),analysis$recordings)
  brohn_require(length(matches)==1L,"Choose one event/channel cell from the complete saved result.")
  event<-matches[[1L]];p<-analysis$parameters[[event$recording_id]]
  brohn_require(p$recipe %in% c("eda-event-highpass/1.0","eda-event-cvxeda-defaults/1.0")&&identical(event$unit,"uS")&&brohn_number(event$time_s),"This saved event needs a supported EDA recipe, conductance unit and measured onset.")
  list(event=event,parameters=p)
}
.brohn_er_source <- function(store,r,verify=FALSE) {
  catalog<-.brohn_qexplorer_catalog(store,"report",r$report_id,r$report_revision,r$project_id);brohn_project(store,r$project_id)
  report<-brohn_get_entity(store,"report",r$report_id,r$report_revision)
  brohn_require(identical(.brohn_sv_hash(report$body),r$report_hash)&&identical(catalog,r$catalog_hash)&&brohn_eda_review_supported(report$body),"The exact saved EDA report or its project authority changed.")
  a<-report$body$analysis;p<-report$body$provenance
  dataset_catalog<-.brohn_qexplorer_catalog(store,"dataset",p$dataset_id,p$dataset_revision,r$project_id)
  dataset<-brohn_get_entity(store,"dataset",p$dataset_id,p$dataset_revision)
  brohn_require(identical(p$dataset_id,report$body$dataset_id)&&identical(.brohn_sv_hash(dataset$body),p$dataset_hash)&&
    identical(dataset$body$modality,"eda")&&.brohn_er_same(dataset$body$metadata,p$mapping)&&.brohn_er_same(dataset$body$source,p$source)&&
    identical(a$source$sha256,p$source$hash)&&identical(report$body$origin,dataset$body$origin)&&identical(p$origin,report$body$origin)&&identical(r$origin,report$body$origin),
    "The EDA report differs from its original dataset, mapping, source or origin.")
  if(!is.null(r$dataset_catalog_hash))brohn_require(identical(dataset_catalog,r$dataset_catalog_hash),"Original EDA dataset authority changed.")
  picked<-brohn_eda_review_selection(a,r$selection)
  artifacts<-lapply(Filter(function(k)any(vapply(a$artifacts,function(x)identical(x$kind,k),logical(1))),c("physiology-series","physiology-events")),function(k)brohn_signal_artifact(report,k))
  brohn_require(!any(vapply(a$segments,function(s)identical(s$status,"computed"),logical(1)))||length(artifacts)==2L,"Complete saved continuous and candidate artifacts are required; display previews cannot replace them.")
  if(!is.null(r$artifacts))brohn_require(.brohn_er_same(artifacts,r$artifacts),"The original EDA processed artifacts changed.")
  refs<-list(list(hash=p$source$hash,bytes=p$source$size))
  retained<-.brohn_sv_retained(store,report,"report",verify)
  brohn_require(!is.null(retained),"This review requires the original retained report envelope.")
  refs<-c(refs,list(retained),lapply(artifacts,function(x)list(hash=x$sha256,bytes=x$bytes)))
  for(ref in refs)brohn_require(file.info(brohn_object_path(store,ref$hash,verify=verify))$size==ref$bytes,"An original EDA object differs from its retained byte count.")
  list(report=report,dataset=dataset,dataset_catalog_hash=dataset_catalog,artifacts=artifacts,retained=retained,source_objects=refs,picked=picked)
}
brohn_queue_eda_review <- function(store,report_id,report_revision,report_hash,selection,retry=FALSE) {
  report<-brohn_get_entity(store,"report",report_id,report_revision)
  brohn_require(!is.null(report)&&identical(.brohn_sv_hash(report$body),report_hash),"Reopen the exact EDA report before choosing an event.")
  r<-list(report_id=report_id,report_revision=report_revision,report_hash=report_hash,project_id=report$project_id,
    catalog_hash=.brohn_qexplorer_catalog(store,"report",report_id,report_revision,report$project_id),selection=selection,
    recipe="saved-eda-event-review/1.0",implementation=.brohn_eda_review_loaded,origin=report$body$origin)
  source<-.brohn_er_source(store,r);r$dataset_catalog_hash<-source$dataset_catalog_hash;r$artifacts<-source$artifacts;r$result_object<-source$retained
  brohn_enqueue_job(store,"eda_review",r,paste0("eda-review:",brohn_hash(r),if(retry)paste0(":",brohn_id("retry"))else""))
}
brohn_eda_review_input <- function(store,job,verify=TRUE) {
  r<-job$request
  brohn_fields(r,c("report_id","report_revision","report_hash","project_id","catalog_hash","selection","recipe","implementation","origin","dataset_catalog_hash","artifacts","result_object"),label="Saved EDA review request")
  brohn_require(identical(job$operation,"eda_review")&&identical(r$recipe,"saved-eda-event-review/1.0")&&.brohn_er_same(r$implementation,.brohn_eda_review_loaded),"Rebuild this EDA review with the current saved-result reader.")
  s<-.brohn_er_source(store,r,verify);a<-s$report$body$analysis;pick<-s$picked;e<-pick$event
  brohn_require(.brohn_er_same(s$retained,r$result_object),"The retained report envelope changed.")
  features<-Filter(function(f)all(vapply(names(r$selection),function(k)identical(f[[k]],r$selection[[k]]),logical(1))),a$features)
  brohn_require(length(features)>0L&&!anyDuplicated(vapply(features,`[[`,character(1),"name")),"The saved EDA event features are incomplete or duplicated.")
  source_events<-Filter(function(x)identical(x$recording_id,e$recording_id)&&x$type %in% c("stimulus_event","nuisance_event"),a$events)
  target<-Filter(function(x)identical(x$id,e$event_id),source_events)
  brohn_require(length(target)==1L&&identical(target[[1L]]$type,"stimulus_event")&&target[[1L]]$time_s==e$time_s&&
    identical(target[[1L]]$exposure_id,e$exposure_id)&&identical(target[[1L]]$condition_id,e$condition_id),"The selected event differs from its original measured source marker.")
  list(schema="brohn-analysis-input/1.0",operation="eda_review",project_id=r$project_id,binding=r,
    event=e,parameters=pick$parameters,features=features,source_events=source_events,
    source_masks=Filter(function(x)identical(x$recording_id,e$recording_id)&&identical(x$channel,e$channel),a$source_masks),
    artifacts=lapply(s$artifacts,function(x)c(x,list(path=brohn_object_path(store,x$sha256,verify=FALSE)))),
    original_source=list(hash=s$dataset$body$source$hash,bytes=s$dataset$body$source$size,path=brohn_object_path(store,s$dataset$body$source$hash,verify=FALSE)),
    sealed_objects=list(c(s$retained,list(path=brohn_object_path(store,s$retained$hash,verify=FALSE)))),source_objects=s$source_objects)
}
brohn_validate_eda_review <- function(result,input) {
  brohn_require(identical(result$schema,"brohn-eda-review/1.0")&&result$status %in% c("available","no_processed_samples")&&
    .brohn_er_same(result$binding,input$binding)&&.brohn_er_same(result$event,input$event)&&.brohn_er_same(result$parameters,input$parameters)&&
    .brohn_er_same(result$features,input$features)&&identical(result$unit,"uS"),"EDA review substituted its source, original event or saved measurements.")
  c<-result$counts
  brohn_require(brohn_number(c$selected_rows,0,500000,TRUE)&&c$retained_rows+c$excluded_rows==c$selected_rows&&
    brohn_number(c$retained_rows,0,c$selected_rows,TRUE)&&brohn_number(c$excluded_rows,0,c$selected_rows,TRUE)&&
    c$matched_channel_rows>=c$selected_rows&&c$complete_artifact_rows>=c$matched_channel_rows&&
    length(result$rows)==min(50,c$selected_rows)&&length(result$exports)==3L&&
    result$exports[[1]]$rows==c$selected_rows&&result$exports[[2]]$rows==length(input$features)&&result$exports[[3]]$rows==length(result$markers),"EDA complete export and display counts do not reconcile.")
  for(item in result$exports)brohn_require(brohn_text(item$hash,64)&&grepl("^[a-f0-9]{64}$",item$hash)&&brohn_number(item$bytes,1,128*1024^2,TRUE),"EDA review export exceeds its supported byte profile.")
  brohn_require(.brohn_er_same(result$range_s,list(input$parameters$baseline_s[[1L]],input$parameters$recovery_end_s))&&
    .brohn_er_same(result$source_masks,input$source_masks)&&length(result$candidates)<=20000L&&length(result$markers)==3L*length(result$candidates),"EDA source windows, omissions or marker support changed.")
  expected<-lapply(input$artifacts,function(a)list(kind=a$kind,sha256=a$sha256,rows=a$rows,tables=a$tables))
  brohn_require(.brohn_er_same(result$verification,expected),"EDA review omitted complete artifact verification.")
  for(component in c("clean_us","tonic_us","phasic_us")) {
    groups<-result$series[[component]]
    brohn_require(brohn_array(groups)&&length(groups)<=200L&&sum(vapply(groups,function(g)length(g$points),integer(1)))<=2000L&&
      sum(vapply(groups,function(g)g$source_rows,numeric(1)))==c$selected_rows,"EDA display exceeds its bounded actual-sample profile or drops support runs.")
    for(g in groups) {
      brohn_require(brohn_text(g$table_id,160)&&is.logical(g$retained)&&length(g$retained)==1L&&brohn_number(g$source_rows,length(g$points),500000,TRUE),"EDA trace group is not a supported saved source run.")
      for(pt in g$points)brohn_require(brohn_number(pt$time_s,result$range_s[[1]],result$range_s[[2]])&&brohn_number(pt$value)&&brohn_number(pt$source_sample_index,0,2^53-1,TRUE),"EDA plot substituted a saved numeric sample or source index.")
      if(length(g$points)>1L)brohn_require(all(diff(vapply(g$points,`[[`,numeric(1),"time_s"))>0),"EDA trace cannot join duplicate or reversed source time.")
    }
  }
  invisible(result)
}
brohn_analyse_eda_review <- function(input,scratch) {
  directory<-file.path(scratch,"artifacts");brohn_require(dir.create(directory),"Cannot prepare EDA review exports.")
  request<-input[setdiff(names(input),c("schema","operation","project_id","source_objects"))]
  request$schema<-"brohn-eda-review-request/1.0";request$export_directory<-normalizePath(directory,winslash="/")
  request_path<-file.path(scratch,"eda-review-input.json");result_path<-file.path(scratch,"eda-review-output.json");brohn_write_json_file(request,request_path)
  child<-processx::run(brohn_python_profile("eda"),c("scripts/workers/eda_review.py","--request",request_path,"--output",result_path),timeout=15*60,error_on_status=FALSE,cleanup_tree=TRUE,windows_hide_window=TRUE)
  brohn_require(file.exists(result_path),paste("EDA review returned no result.",substr(child$stderr,1,500)))
  result<-brohn_read_json_file(result_path);brohn_require(child$status==0&&!identical(result$status,"error"),paste("EDA review needs attention:",result$error$message))
  brohn_validate_eda_review(result,input);list(eda_review=result)
}
brohn_publish_eda_review <- function(store,output,scratch,job,input,output_path) {
  .brohn_publication_output_identity(output,.brohn_eda_review_loaded);.brohn_publication_job(store,job)
  guards<-brohn_hold_signal_value_sources(store,input);on.exit(for(g in guards).brohn_qexplorer_release(g),add=TRUE)
  brohn_require(.brohn_er_same(input,brohn_eda_review_input(store,job))&&.brohn_er_same(output,brohn_read_json_file(output_path)),"EDA review source or child output changed before publication.")
  result<-output$report$eda_review;brohn_validate_eda_review(result,input)
  csv<-document<-NULL;committed<-FALSE
  on.exit({if(!is.null(document))brohn_close_publication(document$guard,committed);if(!is.null(csv))brohn_close_publication(csv$guard,committed)},add=TRUE)
  expected<-c("eda-window-samples.csv","eda-event-features.csv","eda-response-markers.csv")
  brohn_require(identical(vapply(result$exports,`[[`,character(1),"name"),expected),"EDA review changed its complete export identities.")
  csv<-.brohn_publication_stage(store,job,lapply(result$exports,function(x)list(key=x$name,kind="eda-review-csv",path=brohn_checked_artifact_path(store,file.path(scratch,"artifacts",x$name),scratch),sha256=x$hash,bytes=x$bytes,media_type="text/csv")))
  id<-paste0("eda-review-",sub("^job[_-]","",job$id))
  body<-list(schema="brohn-saved-eda-review/1.0",id=id,report_id=input$binding$report_id,origin=input$binding$origin,request=job$request,result=result,
    exports=stats::setNames(lapply(csv$descriptors,function(x)x[c("hash","size","media_type")]),expected),created_at=brohn_now(),
    processing=list(job_id=job$id,attempt=job$attempt,code_hashes=output$code_identity,worker_output_hash=digest::digest(file=output_path,algo="sha256")))
  document<-.brohn_publication_stage_json(store,job,body,file.path(scratch,"published-eda-review.json"))
  receipt<-brohn_store_batch(store,function(){
    brohn_require(.brohn_er_same(input,brohn_eda_review_input(store,job,verify=FALSE)),"EDA source authority changed before publication.")
    for(g in guards).Call(g$native$check,g$pointer)
    .brohn_publication_register(store,csv);body$result_object<-.brohn_publication_register(store,document)[[1L]][c("hash","size","media_type")]
    brohn_put_entity(store,"eda_review",id,body,project_id=input$project_id)
    brohn_complete_job(store,job$id,job$worker,job$token,list(eda_review_id=id,report_id=body$report_id,output_hash=body$result_object$hash))})
  committed<-TRUE;receipt
}
brohn_eda_review_record <- function(store,id,report_id,project_id) {
  r<-brohn_get_entity(store,"eda_review",id)
  brohn_require(!is.null(r)&&identical(r$body$schema,"brohn-saved-eda-review/1.0")&&identical(r$body$report_id,report_id)&&identical(r$project_id,project_id),"Open an EDA review belonging to this report and project.")
  input<-brohn_eda_review_input(store,list(operation="eda_review",request=r$body$request),verify=FALSE)
  brohn_validate_eda_review(r$body$result,input);r
}
