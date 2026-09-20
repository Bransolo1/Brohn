# Researcher exclusions create separate reports; parent sources stay immutable.
.brohn_cardiac_policy <- "cardiac-source-exclusion/1.0"
brohn_validate_cardiac_spans <- function(spans, table, allow_empty=TRUE) {
  s<-table$support$source
  brohn_require(brohn_array(spans)&&length(spans)<=64L&&(allow_empty||length(spans)>0L),"Save between 1 and 64 exclusions before recalculating.")
  for(x in spans) {
    brohn_fields(x,c("id","start_sample","end_sample","reason","note"),label="Cardiac exclusion")
    brohn_require(brohn_valid_id(x$id)&&nchar(x$id)<=160&&brohn_number(x$start_sample,s$source_row_start,s$source_row_end_exclusive-1,TRUE)&&
      brohn_number(x$end_sample,s$source_row_start+1,s$source_row_end_exclusive,TRUE)&&x$start_sample<x$end_sample,
      "Choose increasing whole source sample bounds inside this exact recording. The end is excluded.")
    brohn_require(isTRUE(x$reason%in%c("signal_loss","clipping","movement_or_distortion","researcher_exclusion"))&&
      brohn_text(x$note,4000,TRUE)&&(!identical(x$reason,"researcher_exclusion")||nzchar(trimws(x$note))),
      "Choose a reason; explain a researcher-selected exclusion in its note.")
  }
  brohn_require(!anyDuplicated(brohn_ids(spans)),"Each exclusion needs a distinct identity.")
  invisible(spans)
}
.brohn_cardiac_lineage <- function(store,dataset,verify=FALSE) {
  p<-dataset$body$source_provenance
  if(!identical(p$acquisition,"curated_stream"))return(NULL)
  c<-brohn_get_entity(store,"stream_curation",p$curation_id)
  brohn_require(!is.null(c)&&identical(c$project_id,dataset$project_id)&&identical(c$body$dataset_id,dataset$id)&&
    identical(brohn_hash(c$body$lineage),brohn_hash(p$lineage)),"The original stream curation is unavailable or changed.")
  lineage<-p$lineage
  for(binding in list(c("stream","stream_id","stream_revision","stream_hash"),c("stream_import","import_id","import_revision","import_hash"),
      c("dataset","raw_dataset_id","raw_dataset_revision","raw_dataset_hash"))) {
    current<-brohn_get_entity(store,binding[[1]],lineage[[binding[[2]]]])
    frozen<-brohn_get_entity(store,binding[[1]],lineage[[binding[[2]]]],lineage[[binding[[3]]]])
    brohn_require(!is.null(current)&&!is.null(frozen)&&identical(current$project_id,dataset$project_id)&&identical(frozen$project_id,dataset$project_id)&&
      identical(brohn_hash(frozen$body),lineage[[binding[[4]]]]),"A source recording, import or dataset in the curation lineage is unavailable or changed project.")
  }
  csv<-Filter(function(a)identical(a$kind,"curated_signal_csv"),p$artifacts)
  decisions<-Filter(function(a)identical(a$kind,"curation_decisions_jsonl"),p$artifacts)
  brohn_require(length(csv)==1L&&length(decisions)==1L&&identical(csv[[1]]$hash,dataset$body$source$hash)&&
    identical(brohn_hash(p$artifacts),brohn_hash(c$body$extraction$artifacts)),"The derived CSV or full curation decisions no longer match their original publication.")
  # Read-only verification includes original acquisition bytes and canonical stream
  # artifacts. The CSV itself retains each included row's original sequence/clock.
  hashes<-unique(c(lineage$raw_source$hash,lineage$canonical_hash,
    vapply(lineage$original_stream_artifacts,function(a)brohn_default(a$hash,a$sha256),character(1)),
    vapply(p$artifacts,`[[`,character(1),"hash")))
  paths<-lapply(hashes,function(h)brohn_object_path(store,h,verify=verify))
  list(curation_id=c$id,curation_revision=c$revision,curation_hash=brohn_hash(c$body),lineage=lineage,
    decisions=list(sha256=decisions[[1]]$hash,bytes=decisions[[1]]$size),
    decisions_path=brohn_object_path(store,decisions[[1]]$hash,verify=verify),
    guard_objects=lapply(hashes,function(h){row<-.brohn_store_object_row(store,h);brohn_require(nrow(row)==1L,"A curation source object is unavailable.")
      list(hash=h,bytes=as.numeric(row$size[[1]]))}))
}
.brohn_cardiac_context <- function(store,body,project_id,verify=FALSE) {
  source<-.brohn_annotations_source(store,body,project_id,verify=verify)
  p<-source$report$body$provenance
  current<-brohn_get_entity(store,"dataset",p$dataset_id)
  dataset<-brohn_get_entity(store,"dataset",p$dataset_id,p$dataset_revision)
  brohn_require(!is.null(current)&&!is.null(dataset)&&identical(current$project_id,project_id)&&identical(dataset$project_id,project_id)&&
    identical(brohn_hash(dataset$body),p$dataset_hash)&&identical(source$report$body$dataset_id,dataset$id),
    "The parent's original mapped dataset is unavailable, changed or belongs to another project.")
  d<-dataset$body
  brohn_require(d$modality%in%c("ecg","ppg")&&d$source$format%in%c("csv","tsv")&&
    identical(source$report$body$analysis$kind,d$modality)&&is.null(source$report$body$analysis$exclusion_review),
    "Start artifact review from an original ECG or PPG CSV/TSV report. Reopen its saved review to revise an existing exclusion analysis.")
  brohn_validate_dataset_mapping(d)
  brohn_require(identical(brohn_hash(p$source),brohn_hash(d$source))&&identical(brohn_hash(p$mapping),brohn_hash(d$metadata)),
    "The parent report mapping differs from the original dataset.")
  source$dataset<-dataset;source$input_path<-brohn_object_path(store,d$source$hash,verify=verify)
  source$curation<-.brohn_cardiac_lineage(store,dataset,verify)
  source
}
brohn_create_cardiac_review <- function(store,catalog_id,table_id,title="Artifact review") {
  brohn_require(brohn_text(title,240)&&nzchar(trimws(title)),"Name this artifact review.")
  catalog<-brohn_get_entity(store,"signal_view",catalog_id)
  brohn_require(!is.null(catalog)&&identical(catalog$body$operation,"signal_catalog")&&
    identical(catalog$body$view$artifact$kind,"physiology-series"),"Open the complete waveform catalog first.")
  source<-.brohn_cardiac_context(store,catalog$body,catalog$project_id)
  tables<-Filter(function(t)identical(t$table_id,table_id),catalog$body$view$tables)
  brohn_require(length(tables)==1L&&identical(tables[[1]]$coordinates$axis,"time")&&
    any(vapply(tables[[1]]$value_columns,function(c)identical(c$name,"raw"),logical(1)))&&
    identical(tables[[1]]$support$raw_source_omitted,FALSE),"This historical report needs a new analysis that preserves the pre-cleaning input before artifact review.")
  id<-brohn_id("cardiac-review")
  body<-list(schema_version="brohn-cardiac-review/1.0",id=id,title=title,policy=.brohn_cardiac_policy,
    report_id=source$report$id,report_revision=source$report$revision,report_hash=brohn_hash(source$report$body),
    artifact_hash=source$artifact$sha256,origin=source$report$body$origin,
    catalog_id=catalog$id,catalog_revision=catalog$revision,catalog_hash=brohn_hash(catalog$body),table=tables[[1]],
    dataset_id=source$dataset$id,dataset_revision=source$dataset$revision,dataset_hash=brohn_hash(source$dataset$body),
    spans=list(),review_attribution="Local researcher action; no authenticated reviewer identity asserted",created_at=brohn_now())
  brohn_put_entity(store,"cardiac_review",id,body,project_id=catalog$project_id)
}
brohn_cardiac_review <- function(store,id,revision=NULL,hash=NULL,verify=FALSE) {
  value<-brohn_get_entity(store,"cardiac_review",id,revision);current<-brohn_get_entity(store,"cardiac_review",id)
  brohn_require(!is.null(value)&&!is.null(current)&&identical(value$project_id,current$project_id)&&
    identical(value$body$schema_version,"brohn-cardiac-review/1.0")&&identical(value$body$policy,.brohn_cardiac_policy)&&
    (is.null(hash)||identical(brohn_hash(value$body),hash)),"Reopen the exact saved artifact review version.")
  source<-.brohn_cardiac_context(store,value$body,value$project_id,verify)
  brohn_require(identical(source$dataset$id,value$body$dataset_id)&&identical(source$dataset$revision,value$body$dataset_revision)&&
    identical(brohn_hash(source$dataset$body),value$body$dataset_hash),"The review references another mapped source.")
  catalog<-brohn_get_entity(store,"signal_view",value$body$catalog_id,value$body$catalog_revision)
  current_catalog<-brohn_get_entity(store,"signal_view",value$body$catalog_id)
  brohn_require(!is.null(catalog)&&!is.null(current_catalog)&&identical(catalog$project_id,value$project_id)&&identical(current_catalog$project_id,value$project_id)&&
    identical(brohn_hash(catalog$body),value$body$catalog_hash),"The original reviewed catalog is unavailable.")
  tables<-Filter(function(t)identical(t$table_id,value$body$table$table_id),catalog$body$view$tables)
  brohn_require(length(tables)==1L&&identical(brohn_hash(tables[[1]]),brohn_hash(value$body$table)),"The exact reviewed table, calibration or clock changed.")
  brohn_validate_cardiac_spans(value$body$spans,value$body$table)
  value
}
brohn_save_cardiac_span <- function(store,id,expected_revision,start_sample,end_sample,reason,note="",span_id=NULL) {
  r<-brohn_cardiac_review(store,id)
  brohn_require(brohn_number(expected_revision,1,Inf,TRUE)&&expected_revision==r$revision,"This review changed; reopen its current version before saving.")
  if(is.null(span_id))span_id<-brohn_id("exclusion")else brohn_require(span_id%in%brohn_ids(r$body$spans),"Choose an exclusion from this review before editing.")
  x<-list(id=span_id,start_sample=start_sample,end_sample=end_sample,reason=reason,note=note)
  i<-match(span_id,brohn_ids(r$body$spans));body<-r$body
  if(is.na(i))body$spans[[length(body$spans)+1L]]<-x else body$spans[[i]]<-x
  brohn_validate_cardiac_spans(body$spans,body$table)
  brohn_put_entity(store,"cardiac_review",id,body,expected_revision=r$revision,project_id=r$project_id)
}
brohn_remove_cardiac_span <- function(store,id,expected_revision,span_id) {
  r<-brohn_cardiac_review(store,id)
  brohn_require(brohn_number(expected_revision,1,Inf,TRUE)&&expected_revision==r$revision&&span_id%in%brohn_ids(r$body$spans),"Reopen this exclusion before removing it.")
  body<-r$body;body$spans<-Filter(function(x)!identical(x$id,span_id),body$spans)
  brohn_put_entity(store,"cardiac_review",id,body,expected_revision=r$revision,project_id=r$project_id)
}
brohn_restore_cardiac_review <- function(store,id,expected_revision,revision,hash) {
  current<-brohn_cardiac_review(store,id);earlier<-brohn_cardiac_review(store,id,revision,hash)
  brohn_require(brohn_number(expected_revision,1,Inf,TRUE)&&expected_revision==current$revision&&earlier$revision<current$revision,
    "Reopen the current review and inspect an earlier version before restoring.")
  body<-current$body;body$spans<-earlier$body$spans
  brohn_put_entity(store,"cardiac_review",id,body,expected_revision=current$revision,project_id=current$project_id)
}
brohn_queue_cardiac_review <- function(store,id,revision,hash,preview_id=NULL) {
  r<-brohn_cardiac_review(store,id,revision,hash,verify=TRUE)
  operation<-if(is.null(preview_id))"preview_cardiac_review"else"reanalyse_cardiac"
  request<-list(review_id=id,review_revision=r$revision,review_hash=brohn_hash(r$body),project_id=r$project_id,policy=.brohn_cardiac_policy)
  if(!is.null(preview_id)) {
    brohn_validate_cardiac_spans(r$body$spans,r$body$table,FALSE)
    p<-brohn_get_entity(store,"cardiac_review_preview",preview_id)
    brohn_require(!is.null(p)&&is.null(p$body$preview$resolved_exclusion)&&identical(p$project_id,r$project_id)&&identical(brohn_hash(p$body$preview$ledger$review_source),
      brohn_hash(list(id=r$id,revision=r$revision,hash=brohn_hash(r$body)))),"Preview this exact saved review version before recalculating.")
    request$preview_id<-p$id;request$preview_revision<-p$revision;request$preview_hash<-brohn_hash(p$body)
  }
  brohn_enqueue_job(store,operation,request,paste0(operation,":",brohn_hash(request)))
}
brohn_queue_cardiac_resolution <- function(store,id,revision,hash,start_time_s_text,end_time_s_text,reason,note="",span_id=NULL) {
  r<-brohn_cardiac_review(store,id,revision,hash,verify=TRUE)
  brohn_require(brohn_text(start_time_s_text,128)&&brohn_text(end_time_s_text,128),"Enter both boundaries in relative seconds.")
  if(is.null(span_id))span_id<-brohn_id("exclusion")else brohn_require(span_id%in%brohn_ids(r$body$spans),"Choose the saved exclusion to edit.")
  candidate<-list(id=span_id,start_time_s_text=start_time_s_text,end_time_s_text=end_time_s_text,reason=reason,note=note)
  request<-list(review_id=id,review_revision=r$revision,review_hash=brohn_hash(r$body),project_id=r$project_id,policy=.brohn_cardiac_policy,candidate=candidate)
  brohn_enqueue_job(store,"preview_cardiac_review",request,paste0("resolve-cardiac-exclusion:",brohn_hash(request)))
}
brohn_accept_cardiac_resolution <- function(store,preview_id,expected_revision) {
  p<-brohn_get_entity(store,"cardiac_review_preview",preview_id)
  brohn_require(!is.null(p)&&!is.null(p$body$preview$resolved_exclusion),"Preview these time boundaries before saving the exclusion.")
  binding<-p$body$review_source;r<-brohn_cardiac_review(store,binding$id)
  brohn_require(identical(p$project_id,r$project_id)&&expected_revision==r$revision&&binding$revision==r$revision&&
    identical(binding$hash,brohn_hash(r$body)),"This resolved exclusion belongs to an earlier review version. Preview the current one.")
  x<-p$body$preview$resolved_exclusion$span
  body<-r$body;i<-match(x$id,brohn_ids(body$spans))
  if(is.na(i))body$spans[[length(body$spans)+1L]]<-x else body$spans[[i]]<-x
  brohn_validate_cardiac_spans(body$spans,body$table,FALSE)
  brohn_put_entity(store,"cardiac_review",r$id,body,expected_revision=r$revision,project_id=r$project_id)
}
brohn_cardiac_review_input <- function(store,job,verify=TRUE) {
  q<-job$request;r<-brohn_cardiac_review(store,q$review_id,q$review_revision,q$review_hash,verify=verify)
  brohn_require(identical(q$project_id,r$project_id)&&identical(q$policy,.brohn_cardiac_policy),"The cardiac review job belongs to another project or policy.")
  source<-.brohn_cardiac_context(store,r$body,r$project_id,verify=verify)
  expected<-NULL
  if(identical(job$operation,"reanalyse_cardiac")) {
    p<-brohn_get_entity(store,"cardiac_review_preview",q$preview_id,q$preview_revision);latest<-brohn_get_entity(store,"cardiac_review_preview",q$preview_id)
    brohn_require(!is.null(p)&&!is.null(latest)&&is.null(p$body$preview$resolved_exclusion)&&identical(p$project_id,r$project_id)&&identical(latest$project_id,r$project_id)&&
      identical(brohn_hash(p$body),q$preview_hash),"The accepted recalculation preview is unavailable or changed.")
    brohn_validate_cardiac_spans(r$body$spans,r$body$table,FALSE);expected<-p$body$preview$ledger
    brohn_require(identical(brohn_hash(expected$review_source),brohn_hash(list(id=r$id,revision=r$revision,hash=brohn_hash(r$body)))),
      "The preview belongs to another saved exclusion version.")
  }
  list(schema="brohn-analysis-input/1.0",operation=job$operation,project_id=r$project_id,review=r$body,
    review_source=list(id=r$id,revision=r$revision,hash=brohn_hash(r$body)),dataset=source$dataset$body,dataset_revision=source$dataset$revision,
    source_path=source$input_path,artifact=source$artifact,artifact_path=source$path,verification_receipt=source$report$body$analysis$artifact_verification,
    parent_report=list(id=source$report$id,revision=source$report$revision,hash=brohn_hash(source$report$body),title=source$report$body$title,
      provenance=source$report$body$provenance),curation=source$curation,expected_ledger=expected,
    candidate=q$candidate,source_objects=c(list(list(hash=source$dataset$body$source$hash,bytes=source$dataset$body$source$size),
      list(hash=source$artifact$sha256,bytes=source$artifact$bytes)),source$curation$guard_objects))
}
brohn_cardiac_worker_request <- function(input,scratch) {
  d<-input$dataset;m<-d$metadata;m$origin<-d$origin;parameters<-m$parameters;m$parameters<-NULL
  source<-file.path(scratch,paste0("cardiac-source.",d$source$format))
  brohn_require(file.copy(input$source_path,source,overwrite=FALSE),"Cannot isolate the reviewed source.")
  request<-list(schema="brohn-cardiac-review-request/1.0",operation=input$operation,policy=.brohn_cardiac_policy,
    source=list(sha256=d$source$hash,bytes=d$source$size),source_path=normalizePath(source,winslash="/"),modality=d$modality,
    format=d$source$format,metadata=m,artifact=c(input$artifact,list(path=input$artifact_path)),verification_receipt=input$verification_receipt,
    table=input$review$table,review_source=input$review_source,spans=input$review$spans)
  if(length(parameters))request$parameters<-parameters
  if(!is.null(input$candidate))request$candidate<-input$candidate
  if(!is.null(input$curation))request$curation<-input$curation[setdiff(names(input$curation),"guard_objects")]
  if(identical(input$operation,"reanalyse_cardiac")) {
    directory<-file.path(scratch,"artifacts");brohn_require(dir.create(directory),"Cannot prepare the reviewed output directory.")
    request$artifact_directory<-normalizePath(directory,winslash="/")
  }
  request
}
brohn_validate_cardiac_result <- function(result,input) {
  preview<-identical(input$operation,"preview_cardiac_review")
  brohn_require(identical(result$schema,if(preview)"brohn-cardiac-review-preview/1.0"else"brohn-worker-result/1.0")&&
    result$status%in%c("completed","partial","insufficient_support"),"The cardiac review returned an incompatible result.")
  ledger<-if(preview)result$ledger else result$exclusion_review
  brohn_require(identical(ledger$schema,"brohn-cardiac-exclusion-ledger/1.0")&&identical(ledger$policy,.brohn_cardiac_policy)&&
    identical(brohn_hash(ledger$review_source),brohn_hash(input$review_source))&&identical(brohn_hash(ledger$table),brohn_hash(input$review$table))&&
    identical(brohn_hash(ledger$source),brohn_hash(list(sha256=input$dataset$source$hash,bytes=input$dataset$source$size))),
    "The review substituted another source, table, method or revision.")
  spans<-lapply(ledger$spans,function(s)s[c("id","start_sample","end_sample","reason","note")])
  brohn_require(identical(brohn_hash(spans),brohn_hash(input$review$spans)),"The resolved exclusions differ from the saved researcher decisions.")
  s<-ledger$support;t<-input$review$table$support$source
  brohn_require(brohn_number(s$input_samples,1,2e6,TRUE)&&s$input_samples==t$source_row_end_exclusive-t$source_row_start&&
    brohn_number(s$excluded_samples,0,s$input_samples,TRUE)&&s$remaining_samples+s$excluded_samples==s$input_samples&&
    brohn_array(ledger$runs)&&length(ledger$runs)<=65L&&brohn_array(ledger$union)&&length(ledger$union)<=64L,
    "The excluded and surviving support does not reconcile with the original table.")
  if(!is.null(input$candidate)) {
    x<-result$resolved_exclusion
    brohn_require(preview&&identical(brohn_hash(x$candidate),brohn_hash(input$candidate)),"The time resolution substituted another visible boundary or reason.")
    brohn_validate_cardiac_spans(list(x$span),input$review$table,FALSE)
    brohn_require(identical(x$span$id,input$candidate$id)&&identical(x$span$reason,input$candidate$reason)&&identical(x$span$note,input$candidate$note)&&
      x$samples==x$span$end_sample-x$span$start_sample,"The resolved source span is inconsistent.")
  } else brohn_require(is.null(result$resolved_exclusion),"An unexpected proposed exclusion entered this saved review.")
  if(!is.null(input$curation)) {
    fields<-c("curation_id","curation_revision","curation_hash","lineage","decisions")
    brohn_require(identical(brohn_hash(ledger$curation[fields]),brohn_hash(input$curation[fields])),"The review changed its acquisition row/clock lineage.")
  } else brohn_require(is.null(ledger$curation),"The review invented a curation lineage.")
  if(!preview)brohn_require(identical(result$modality,input$dataset$modality)&&identical(brohn_hash(ledger),brohn_hash(input$expected_ledger))&&
    identical(result$quality$scientifically_qualified,FALSE)&&identical(result$quality$normal_to_normal_confirmed,FALSE),
    "Recalculation must use the exact previewed support without claiming normal-beat or physiological qualification.")
  invisible(result)
}
brohn_analyse_cardiac_review <- function(input,scratch) {
  request<-brohn_cardiac_worker_request(input,scratch)
  request_path<-file.path(scratch,"cardiac-review-request.json");result_path<-file.path(scratch,"cardiac-review-result.json")
  brohn_write_json_file(request,request_path,maximum=2*1024^2)
  child<-processx::run(brohn_python_profile(input$dataset$modality),c("scripts/workers/cardiac_review.py","--request",request_path,"--output",result_path),
    timeout=1800,error_on_status=FALSE,cleanup_tree=TRUE,windows_hide_window=TRUE)
  brohn_require(file.exists(result_path),paste("Artifact review returned no result.",substr(child$stderr,1,1000)))
  result<-brohn_read_json_file(result_path)
  brohn_require(child$status==0&&!identical(result$status,"error"),paste("Artifact review needs attention:",brohn_default(result$error$message,substr(child$stderr,1,1000))))
  brohn_validate_cardiac_result(result,input)
  if(identical(input$operation,"preview_cardiac_review"))return(list(cardiac_review_preview=result))
  result<-brohn_verify_physiology_artifacts(result,scratch,input$dataset$modality)
  list(title=paste(input$review$title,"-",toupper(input$dataset$modality),"after exclusions"),study_id=input$dataset$study_id,
    dataset_id=input$dataset$id,origin=input$dataset$origin,provenance=c(input$parent_report$provenance,
      list(cardiac_review=list(parent_report=input$parent_report[c("id","revision","hash")],review_source=input$review_source,policy=.brohn_cardiac_policy))),
    analysis=c(list(kind=input$dataset$modality,title="Cardiac analysis after researcher exclusions",observations=list(),contrasts=list()),result))
}
.brohn_hold_cardiac_sources <- function(store,input) {
  brohn_require(.Platform$OS.type=="windows","Cardiac review publication currently requires the qualified Windows source read guard.")
  guards<-list();success<-FALSE;seen<-character()
  on.exit(if(!success)for(g in guards).brohn_qexplorer_release(g),add=TRUE)
  for(ref in input$source_objects)if(!ref$hash%in%seen) {
    guards[[length(guards)+1L]]<-.brohn_qexplorer_hold(brohn_object_path(store,ref$hash,verify=FALSE),ref$bytes)
    seen<-c(seen,ref$hash)
  }
  success<-TRUE;guards
}
brohn_publish_cardiac_review <- function(store,output,scratch,job,input,output_path,timeout_seconds=1900) {
  .brohn_publication_job(store,job)
  guards<-.brohn_hold_cardiac_sources(store,input)
  on.exit(for(g in guards).brohn_qexplorer_release(g),add=TRUE)
  brohn_require(identical(brohn_hash(input),brohn_hash(brohn_cardiac_review_input(store,job))),"Review source, authority or preview changed before publication.")
  before_commit<-function() {
    for(g in guards).Call(g$native$check,g$pointer)
    brohn_require(identical(brohn_hash(input),brohn_hash(brohn_cardiac_review_input(store,job,verify=FALSE))),
      "Review source authority changed before the saved result could be committed.")
  }
  if(identical(job$operation,"reanalyse_cardiac")) {
    brohn_validate_cardiac_result(output$report$analysis,input)
    return(brohn_publish_analysis_report(store,job,input,output,scratch,output_path,timeout_seconds,before_commit=before_commit))
  }
  result<-output$report$cardiac_review_preview;brohn_validate_cardiac_result(result,input)
  id<-paste0("cardiac-preview-",sub("^job[-_]","",job$id))
  body<-list(schema_version="brohn-saved-cardiac-review-preview/1.0",id=id,report_id=input$parent_report$id,
    review_source=input$review_source,preview=result,created_at=brohn_now(),processing=list(job_id=job$id,attempt=job$attempt,
      request_hash=brohn_hash(input),worker_output_hash=digest::digest(file=output_path,algo="sha256"),code_hashes=output$code_identity))
  path<-file.path(scratch,"published-cardiac-preview.json");brohn_write_json_file(body,path)
  brohn_publish_entity_result(store,job,input,output,"cardiac_review_preview",body,path,list(cardiac_preview_id=id,review_id=input$review_source$id),before_commit=before_commit)
}
