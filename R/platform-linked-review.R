# Shared-clock inspection of preserved original streams. No fitted alignment,
# resampling, scientific aggregation or inferred participant/stimulus joins.
.brohn_linked_loaded <- stats::setNames(list(digest::digest(file="R/platform-linked-review.R",algo="sha256")),"R/platform-linked-review.R")
.brohn_linked_ref <- function(r)list(id=r$id,revision=r$revision,hash=brohn_hash(r$body))
.brohn_linked_decimal <- function(x)brohn_text(x,120)&&grepl("^[+-]?([0-9]+(\\.[0-9]*)?|\\.[0-9]+)([eE][+-]?[0-9]+)?$",x)&&is.finite(suppressWarnings(as.numeric(x)))
brohn_linked_choices <- function(store,dataset_id,project_id) {
  dataset<-brohn_get_entity(store,"dataset",dataset_id)
  brohn_require(!is.null(dataset)&&identical(dataset$project_id,project_id)&&identical(dataset$body$modality,"multimodal"),"Open a preserved multistream dataset in this project.")
  imports<-brohn_stream_imports(store,dataset_id,project_id,limit=100L)
  list(dataset=dataset,imports=imports)
}
brohn_prepare_linked_review <- function(store,dataset_id,import_id,tracks,selection,project_id) {
  choices<-brohn_linked_choices(store,dataset_id,project_id)
  imported<-brohn_stream_import(store,import_id)
  brohn_require(identical(imported$project_id,project_id)&&identical(imported$body$dataset_id,dataset_id),"Select a preserved import from this recording.")
  source<-brohn_get_entity(store,"dataset",dataset_id,imported$body$dataset_revision)
  brohn_require(!is.null(source)&&identical(brohn_hash(source$body),imported$body$dataset_hash)&&identical(source$body$source$hash,imported$body$source$hash),"The preserved import does not match its original dataset revision.")
  brohn_require(brohn_array(tracks)&&length(tracks)>=2L&&length(tracks)<=4L,"Select two to four signal or marker channels.")
  brohn_fields(selection,c("start_s","end_s","cursor_s","offset","clock_rationale","confirmed"),label="Linked window")
  brohn_require(all(vapply(selection[c("start_s","end_s","cursor_s")],.brohn_linked_decimal,logical(1)))&&
    brohn_number(selection$offset,0,8000000,TRUE)&&selection$offset%%100==0&&isTRUE(selection$confirmed)&&brohn_text(selection$clock_rationale,4000),
    "Review the shared source clock, explain its declaration, and enter exact relative seconds for the window and cursor.")
  refs<-lapply(tracks,function(t){brohn_fields(t,c("stream_id","channel_id"),label="Selected track")
    stream<-brohn_get_entity(store,"stream",t$stream_id)
    brohn_require(!is.null(stream)&&identical(stream$project_id,project_id)&&identical(stream$body$import_id,import_id)&&
      identical(stream$body$source_dataset_id,dataset_id)&&identical(stream$body$source_hash,source$body$source$hash)&&
      stream$id %in% unlist(imported$body$stream_ids),"All tracks must come from the same preserved recording/import; matching clock names in unrelated recordings are insufficient.")
    s<-stream$body$manifest;channel<-brohn_find(s$channels,t$channel_id)
    brohn_require(!is.null(channel)&&s$kind %in% c("signal","markers")&&stream$body$origin %in% c("sample","pilot","live","imported"),"Choose classified signal/marker tracks with an explicit consistent origin.")
    if(s$kind=="signal")brohn_require(channel$value_type %in% c("float64","float32","int64","int32","int16","int8"),"A signal track needs a scalar numeric source channel.")
    artifacts<-lapply(c("stream_samples_jsonl","stream_evidence_jsonl"),function(kind){a<-Filter(function(x)identical(x$kind,kind),s$artifacts);brohn_require(length(a)==1L,"The complete preserved stream or clock evidence is unavailable.");a[[1L]][c("hash","size","media_type")]})
    list(id=paste(stream$id,channel$id,sep="/"),stream=.brohn_linked_ref(stream),channel_id=channel$id,clock=s$clock,origin=stream$body$origin,
      samples=artifacts[[1L]],evidence=artifacts[[2L]])})
  brohn_require(!anyDuplicated(vapply(refs,`[[`,character(1),"id")),"Choose distinct stream/channel tracks.")
  brohn_require(length(unique(vapply(refs,function(x)brohn_hash(x$clock),character(1))))==1L,
    "Different source clocks require an explicit saved alignment map. Similar timestamps and row order cannot link these tracks. Select channels with the same declared recording clock.")
  brohn_require(length(unique(vapply(refs,`[[`,character(1),"origin")))==1L,"Keep sample, pilot, live and imported origins separate.")
  clock<-refs[[1L]]$clock
  brohn_require(clock$kind %in% c("monotonic","device","unix")&&identical(clock$representation,"decimal_string"),
    "This source clock representation requires a supported alignment route before linked review.")
  list(schema="brohn-linked-review-job/1.0",dataset_id=dataset_id,source=.brohn_linked_ref(source),imported=.brohn_linked_ref(imported),
    project_id=project_id,study_id=source$body$study_id,origin=refs[[1L]]$origin,tracks=refs,selection=selection)
}
brohn_queue_linked_review <- function(store,dataset_id,import_id,tracks,selection,project_id) {
  request<-brohn_prepare_linked_review(store,dataset_id,import_id,tracks,selection,project_id)
  brohn_enqueue_job(store,"linked_review",request,paste0("linked-review:",brohn_hash(request)))
}
brohn_linked_review_input <- function(store,job,verify=TRUE) {
  r<-job$request
  .brohn_qexplorer_catalog(store,"dataset",r$source$id,r$source$revision,r$project_id)
  .brohn_qexplorer_catalog(store,"stream_import",r$imported$id,r$imported$revision,r$project_id)
  source<-brohn_get_entity(store,"dataset",r$source$id,r$source$revision);imported<-brohn_stream_import(store,r$imported$id,r$imported$revision)
  brohn_require(identical(brohn_hash(source$body),r$source$hash)&&identical(brohn_hash(imported$body),r$imported$hash)&&
    identical(imported$body$dataset_id,r$dataset_id)&&identical(imported$body$source$hash,source$body$source$hash),"Pinned linked-review recording/import changed.")
  objects<-list();tracks<-lapply(r$tracks,function(ref){
    .brohn_qexplorer_catalog(store,"stream",ref$stream$id,ref$stream$revision,r$project_id)
    stream<-brohn_get_entity(store,"stream",ref$stream$id,ref$stream$revision);s<-stream$body$manifest
    brohn_require(identical(brohn_hash(stream$body),ref$stream$hash)&&identical(stream$body$import_id,imported$id)&&stream$id %in% unlist(imported$body$stream_ids),"A selected stream changed its saved identity.")
    for(kind in c("stream_samples_jsonl","stream_evidence_jsonl")) {
      found<-Filter(function(a)identical(a$kind,kind),s$artifacts)
      pinned<-if(kind=="stream_samples_jsonl")ref$samples else ref$evidence
      brohn_require(length(found)==1L&&identical(brohn_hash(found[[1L]][c("hash","size","media_type")]),brohn_hash(pinned)),"A linked stream substituted its preserved artifact reference.")
    }
    brohn_require(identical(brohn_hash(ref$clock),brohn_hash(s$clock))&&identical(ref$origin,stream$body$origin)&&
      identical(ref$id,paste(stream$id,ref$channel_id,sep="/")),"A linked stream substituted its clock, origin or channel identity.")
    channel<-brohn_find(s$channels,ref$channel_id);brohn_require(!is.null(channel),"The saved source channel is unavailable.")
    add<-function(a){objects[[length(objects)+1L]]<<-list(hash=a$hash,bytes=a$size);list(hash=a$hash,bytes=a$size,path=brohn_object_path(store,a$hash,verify=verify))}
    list(id=ref$id,stream_id=stream$id,source_stream_id=s$id,title=stream$body$title,channel=channel,kind=s$kind,origin=stream$body$origin,
      clock=s$clock,sample_count=s$sample_count,segment_count=s$segment_count,samples=add(ref$samples),evidence=add(ref$evidence))})
  list(schema="brohn-analysis-input/1.0",operation="linked_review",binding=r,project_id=r$project_id,tracks=tracks,selection=r$selection,source_objects=objects)
}
brohn_validate_linked_review <- function(result,input) {
  brohn_require(identical(result$schema,"brohn-linked-review/1.0")&&result$status %in% c("available","empty_window","requires_alignment")&&
    identical(brohn_hash(result$binding),brohn_hash(input$binding))&&identical(brohn_hash(result$selection),brohn_hash(input$selection))&&
    identical(result$alignment,"source_declared_shared_clock_accuracy_unverified")&&identical(result$interval,"start inclusive, end exclusive"),"Linked review substituted its source, range or alignment policy.")
  brohn_require(.brohn_linked_decimal(result$anchor_timestamp)&&identical(brohn_hash(result$clock),brohn_hash(input$tracks[[1L]]$clock))&&
    brohn_array(result$rows)&&length(result$rows)<=100&&brohn_number(result$selected_rows,0,8000000,TRUE),"Linked-review clock or row support is inconsistent.")
  if(result$status=="requires_alignment")brohn_require(length(result$issues)>0&&!length(result$tracks)&&is.null(result$csv),"Ambiguous alignment cannot expose linked data.") else {
    brohn_require(length(result$tracks)==length(input$tracks)&&identical(vapply(result$tracks,`[[`,character(1),"id"),vapply(input$tracks,`[[`,character(1),"id"))&&
      sum(vapply(result$tracks,`[[`,numeric(1),"selected_rows"))==result$selected_rows&&result$csv$rows==result$selected_rows&&
      brohn_number(result$csv$bytes,1,64*1024^2,TRUE),"Linked-review track/CSV counts do not reconcile.")
    for(i in seq_along(result$tracks)){t<-result$tracks[[i]];s<-input$tracks[[i]]
      brohn_require(t$source_rows==s$sample_count&&t$selected_rows<=t$source_rows&&t$missing_values<=t$selected_rows&&t$unplaced_source_rows<=t$source_rows&&
        identical(brohn_hash(t$channel),brohn_hash(s$channel))&&length(t$points)<=8000&&length(t$markers)<=200,"Linked track support or bounded display changed.")
    }
  }
  invisible(result)
}
brohn_analyse_linked_review <- function(input,scratch) {
  directory<-file.path(scratch,"artifacts");brohn_require(dir.create(directory),"Cannot prepare linked-review artifacts.")
  request<-list(schema="brohn-linked-review-request/1.0",binding=input$binding,tracks=input$tracks,selection=input$selection,
    export_path=normalizePath(file.path(directory,"linked-window.csv"),winslash="/",mustWork=FALSE))
  request_path<-file.path(scratch,"linked-request.json");result_path<-file.path(scratch,"linked-result.json");brohn_write_json_file(request,request_path)
  child<-processx::run(brohn_python_profile("eeg"),c("scripts/workers/linked_review.py","--request",request_path,"--output",result_path),
    timeout=15*60,error_on_status=FALSE,cleanup_tree=TRUE,windows_hide_window=TRUE)
  brohn_require(file.exists(result_path),paste("Linked review returned no result.",substr(child$stderr,1,500)))
  result<-brohn_read_json_file(result_path);brohn_require(child$status==0&&!identical(result$status,"error"),paste("Linked review needs attention:",result$error$message))
  brohn_validate_linked_review(result,input);list(linked_review=result)
}
brohn_publish_linked_review <- function(store,output,scratch,job,input,output_path) {
  brohn_require(!RSQLite::sqliteIsTransacting(store$con),"Publish linked review outside an enclosing writer transaction.")
  .brohn_publication_output_identity(output,.brohn_linked_loaded);.brohn_publication_job(store,job)
  guards<-brohn_hold_signal_value_sources(store,input);on.exit(for(g in guards).brohn_qexplorer_release(g),add=TRUE)
  brohn_require(identical(brohn_hash(input),brohn_hash(brohn_linked_review_input(store,job))),"The linked-review sources changed during processing.")
  result<-output$report$linked_review;brohn_validate_linked_review(result,input)
  csv<-document<-NULL;committed<-FALSE
  on.exit({if(!is.null(document))brohn_close_publication(document$guard,committed);if(!is.null(csv))brohn_close_publication(csv$guard,committed)},add=TRUE)
  if(!is.null(result$csv))csv<-.brohn_publication_stage(store,job,list(list(key="linked-window",kind="linked-window-csv",
    path=brohn_checked_artifact_path(store,file.path(scratch,"artifacts","linked-window.csv"),scratch),sha256=result$csv$hash,bytes=result$csv$bytes,media_type="text/csv")))
  id<-paste0("linked-review-",job$id)
  body<-list(schema="brohn-saved-linked-review/1.0",id=id,dataset_id=input$binding$dataset_id,study_id=input$binding$study_id,origin=input$binding$origin,
    request=job$request,result=result,csv_object=if(is.null(csv))NULL else csv$descriptors[[1L]][c("hash","size","media_type")],created_at=brohn_now(),
    processing=list(job_id=job$id,attempt=job$attempt,worker_output_hash=digest::digest(file=output_path,algo="sha256"),code_hashes=output$code_identity))
  document<-.brohn_publication_stage_json(store,job,body,file.path(scratch,"published-linked-review.json"))
  receipt<-brohn_store_batch(store,function(){
    brohn_require(identical(brohn_hash(input),brohn_hash(brohn_linked_review_input(store,job,verify=FALSE))),"Linked-review authority changed before publication.")
    for(g in guards).Call(g$native$check,g$pointer)
    if(!is.null(csv)).brohn_publication_register(store,csv)
    body$result_object<-.brohn_publication_register(store,document)[[1L]][c("hash","size","media_type")]
    brohn_put_entity(store,"linked_review",id,body,project_id=input$project_id)
    brohn_complete_job(store,job$id,job$worker,job$token,list(linked_review_id=id,dataset_id=body$dataset_id,output_hash=body$result_object$hash))})
  committed<-TRUE;receipt
}
brohn_linked_review_record <- function(store,id,dataset_id,project_id) {
  record<-brohn_get_entity(store,"linked_review",id)
  brohn_require(!is.null(record)&&identical(record$project_id,project_id)&&identical(record$body$dataset_id,dataset_id),"Open a linked review belonging to this recording and project.")
  input<-brohn_linked_review_input(store,list(request=record$body$request),verify=FALSE)
  brohn_validate_linked_review(record$body$result,input);record
}
