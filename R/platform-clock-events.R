# Original recorded-marker selection candidate. Metadata preparation is cheap;
# complete-source inspection runs only through a supervised background request.
# Event equivalence is never inferred from a matching label or close timestamp.
.brohn_clock_event_files <- c("R/platform-clock-authority.R", "R/platform-clock-events.R", "R/platform-clock-preview.R", "R/platform-clock-map.R",
  "scripts/workers/clock_events_worker.py", "scripts/workers/clock_events.py", "scripts/workers/clock_preview_worker.py",
  "scripts/workers/clock_preview.py", "scripts/workers/clock_source.py", "scripts/workers/clock_affine.py", "scripts/workers/stream_extract.py")
.brohn_clock_events_loaded <- setNames(lapply(.brohn_clock_event_files,function(p)digest::digest(file=p,algo="sha256")),.brohn_clock_event_files)
.brohn_ce_decimal <- function(x)brohn_text(x,120)&&grepl("^[+-]?([0-9]+(\\.[0-9]*)?|\\.[0-9]+)([eE][+-]?[0-9]+)?$",x)&&
  is.finite(suppressWarnings(as.numeric(x)))

brohn_prepare_clock_events <- function(store,selection,project_id,query="",offset=0L,limit=40L) {
  brohn_hosted_require_session(store);brohn_hosted_require_project(store,project_id);brohn_project(store,project_id)
  brohn_require(brohn_text(query,240,empty=TRUE)&&brohn_number(offset,0,2000000,TRUE)&&brohn_number(limit,1,100,TRUE),
    "Use a search of at most 240 UTF-8 bytes and a bounded original-event page.")
  recording<-.brohn_clock_select_recording(store,selection,project_id)
  list(schema="brohn-clock-events-job/0.1",project_id=project_id,selection=selection,recording=recording,
    page=list(query=query,offset=as.integer(offset),limit=as.integer(limit)),implementation=.brohn_clock_events_loaded)
}
brohn_queue_clock_events <- function(store,selection,project_id,query="",offset=0L,limit=40L,retry=FALSE) {
  request<-brohn_prepare_clock_events(store,selection,project_id,query,offset,limit)
  request$authority<-brohn_clock_queue_authority(store,"clock_event_page",project_id)
  brohn_enqueue_job(store,"clock_event_page",request,paste0("clock-events:",brohn_hash(request),
    if(isTRUE(retry))paste0(":",brohn_id("retry"))else""))
}
.brohn_clock_events_context <- function(store,r,verify=TRUE,require_current=TRUE) {
  brohn_fields(r,c("schema","project_id","selection","recording","page","implementation"),optional="authority",label="Recorded-event job")
  brohn_fields(r$page,c("query","offset","limit"),label="Recorded-event page")
  brohn_require(identical(r$schema,"brohn-clock-events-job/0.1"),"Choose a registered original-event operation.")
  fresh<-brohn_prepare_clock_events(store,r$selection,r$project_id,r$page$query,r$page$offset,r$page$limit)
  same_source<-.brohn_cm_same(fresh[setdiff(names(fresh),"implementation")],r[setdiff(names(r),c("implementation","authority"))])
  brohn_require(same_source&&(!require_current||(.brohn_cm_same(fresh$implementation,r$implementation)&&all(vapply(names(.brohn_clock_events_loaded),function(p)
    identical(digest::digest(file=p,algo="sha256"),.brohn_clock_events_loaded[[p]]),logical(1))))),
    "Recorded-event sources, permission or implementation changed. Load the current recording again.")
  objects<-list();object<-function(a){objects[[length(objects)+1L]]<<-list(hash=a$hash,bytes=a$size)
    list(path=brohn_object_path(store,a$hash,verify=verify),hash=a$hash,bytes=a$size)}
  recording<-r$recording;object(recording$original_source);retained<-object(recording$retained_import)
  original<-brohn_read_json_file(retained$path,maximum=16*1024^2)
  imported<-brohn_get_entity(store,"stream_import",recording$imported$id,recording$imported$revision)
  fields<-c("schema_version","id","dataset_id","dataset_revision","dataset_hash","source","raw_origin","origin",
    "stream_ids","stream_count","sample_count","value_count","manifest","processing")
  brohn_require(identical(original$schema,"brohn-analysis-output/1.0")&&is.list(original$stream_import)&&
    all(fields %in% names(original$stream_import))&&all(fields %in% names(imported$body))&&
    .brohn_cm_same(original$stream_import[fields],imported$body[fields]),
    "The selected import differs from its retained original source manifest and publication.")
  ref<-recording$marker;stream<-brohn_get_entity(store,"stream",ref$stream$id,ref$stream$revision);s<-stream$body$manifest
  track<-list(id=ref$id,source_stream_id=s$id,kind=s$kind,origin=stream$body$origin,channel=brohn_find(s$channels,ref$channel_id),
    clock=s$clock,preservation=s$quality,sample_count=s$sample_count,segment_count=s$segment_count,
    samples=object(ref$samples),evidence=object(ref$evidence))
  list(schema="brohn-analysis-input/1.0",operation="clock_event_page",project_id=r$project_id,binding=r,
    events=list(schema="brohn-clock-event-request/0.1",track=track,query=r$page$query,offset=r$page$offset,limit=r$page$limit),source_objects=objects)
}
brohn_clock_events_input <- function(store,job,verify=TRUE) {
  store<-brohn_clock_job_authorize(store,job)
  brohn_require(identical(job$operation,"clock_event_page"),"Choose a registered original-event operation.")
  .brohn_clock_events_context(store,job$request,verify)
}
brohn_validate_clock_events <- function(result,input) {
  r<-input$binding;p<-r$page;t<-input$events$track
  brohn_fields(result,c("schema","scope","query","offset","limit","matched_rows","source_rows","selectable_source_rows",
    "events","has_next","next_offset","clock","identity","origin","samples_sha256","evidence_sha256","ordering",
    "event_equivalence","authorization"),label="Recorded-event result")
  brohn_require(nchar(brohn_json(result),type="bytes")<=2*1024^2&&identical(result$schema,"brohn-clock-event-page/0.1")&&
    identical(result$scope,"complete_source_component_only")&&identical(result$query,p$query)&&
    brohn_number(result$offset,0,2000000,TRUE)&&brohn_number(result$limit,1,100,TRUE)&&result$offset==p$offset&&result$limit==p$limit&&
    .brohn_cm_same(result$clock,t$clock)&&identical(result$origin,t$origin)&&identical(result$samples_sha256,t$samples$hash)&&
    identical(result$evidence_sha256,t$evidence$hash)&&identical(result$ordering,"original_source_sequence")&&
    identical(result$event_equivalence,"not_inferred")&&identical(result$authorization,"requires_current_R_source_project_and_publication_guards"),
    "Recorded-event result changed its source, clock, search or selection policy.")
  brohn_fields(result$identity,c("participant_id","session_id"),label="Original recording identity")
  brohn_require(all(vapply(result$identity,brohn_text,logical(1),max=500))&&brohn_number(result$source_rows,1,2000000,TRUE)&&
    result$source_rows==t$sample_count&&brohn_number(result$matched_rows,0,result$source_rows,TRUE)&&
    brohn_number(result$selectable_source_rows,0,result$source_rows,TRUE)&&brohn_array(result$events)&&
    length(result$events)==min(p$limit,max(0,result$matched_rows-p$offset)),"Recorded-event page counts or complete source identity changed.")
  next_page<-p$offset+length(result$events)<result$matched_rows
  brohn_require(identical(result$has_next,next_page)&&if(next_page)
    (brohn_number(result$next_offset,0,2000000,TRUE)&&result$next_offset==p$offset+length(result$events))else is.null(result$next_offset),
    "Recorded-event page boundary is inconsistent.")
  last<-0
  for(e in result$events) {
    brohn_fields(e,c("source_sequence","source_segment","clock_id","source_timestamp","timestamp_unit","timestamp_state",
      "reconstructed_timestamp","identity","channel_id","value_json","value_state","value_bytes","selectable","unavailable_reasons"),label="Original event row")
    brohn_require(brohn_number(e$source_sequence,last+1,result$source_rows,TRUE)&&brohn_text(e$source_segment,1000)&&
      identical(e$clock_id,t$clock$id)&&identical(e$timestamp_unit,t$clock$unit)&&identical(e$channel_id,t$channel$id)&&
      (is.null(e$source_timestamp)||brohn_text(e$source_timestamp,120,empty=TRUE))&&brohn_text(e$timestamp_state,100)&&
      is.logical(e$reconstructed_timestamp)&&length(e$reconstructed_timestamp)==1L&&!is.na(e$reconstructed_timestamp),
      "Recorded-event order, original timestamp or channel identity changed.")
    last<-e$source_sequence
    brohn_fields(e$identity,c("participant_id","session_id"),c("condition_id","exposure_id"),label="Original event identities")
    brohn_require(all(vapply(e$identity,function(x)is.null(x)||brohn_text(x,500,empty=TRUE),logical(1)))&&
      .brohn_cm_same(e$identity[c("participant_id","session_id")],result$identity)&&brohn_text(e$value_state,100)&&
      brohn_number(e$value_bytes,1,8*1024^2,TRUE),"Recorded-event value support or identity is invalid.")
    if(e$value_bytes>4096L)brohn_require(is.null(e$value_json),"Oversized original values cannot be truncated into selectable anchors.")else
      brohn_require(brohn_text(e$value_json,4096)&&jsonlite::validate(e$value_json)&&nchar(e$value_json,type="bytes")==e$value_bytes,"Original event JSON value changed.")
    reasons<-list()
    if(e$value_bytes>4096L)reasons<-c(reasons,list("event_value_exceeds_4096_byte_anchor_bound"))
    if(!identical(e$timestamp_state,"observed")||is.null(e$source_timestamp)||isTRUE(e$reconstructed_timestamp))reasons<-c(reasons,list("no_original_observed_timestamp"))
    if(!identical(e$value_state,"observed")||identical(e$value_json,"null"))reasons<-c(reasons,list("no_original_observed_value"))
    brohn_require(identical(e$selectable,length(reasons)==0L)&&.brohn_cm_same(e$unavailable_reasons,reasons),"Event eligibility differs from its original observed timestamp/value support.")
    if(isTRUE(e$selectable))brohn_require(.brohn_ce_decimal(e$source_timestamp),"Selectable original timestamps must be finite decimal coordinates.")
  }
  invisible(result)
}
brohn_analyse_clock_events <- function(input,scratch) {
  request_path<-file.path(scratch,"clock-events-request.json");result_path<-file.path(scratch,"clock-events-result.json")
  brohn_write_json_file(input$events,request_path,maximum=1024^2)
  child<-processx::run(brohn_python_profile("eeg"),c("-B","scripts/workers/clock_events_worker.py","--request",request_path,"--output",result_path),
    timeout=900,error_on_status=FALSE,cleanup_tree=TRUE,windows_hide_window=TRUE)
  diagnostic<-if(nzchar(trimws(child$stdout)))child$stdout else child$stderr
  brohn_require(child$status==0L&&file.exists(result_path),paste("Recorded-event inspection needs attention:",substr(diagnostic,1,1000)))
  result<-brohn_read_json_file(result_path,maximum=2*1024^2);brohn_validate_clock_events(result,input)
  list(clock_events=result)
}
brohn_publish_clock_events <- function(store,output,scratch,job,input,output_path) {
  brohn_require(!RSQLite::sqliteIsTransacting(store$con),"Publish event pages outside an enclosing transaction.")
  store<-brohn_clock_job_authorize(store,job,"publish")
  .brohn_publication_output_identity(output,.brohn_clock_events_loaded);.brohn_publication_job(store,job)
  guards<-brohn_hold_signal_value_sources(store,input);on.exit(for(g in guards).brohn_qexplorer_release(g),add=TRUE)
  guard<-.brohn_qexplorer_hold(output_path,file.info(output_path)$size);on.exit(.brohn_qexplorer_release(guard),add=TRUE)
  brohn_require(.brohn_cm_same(input,brohn_clock_events_input(store,job))&&.brohn_cm_same(output,brohn_read_json_file(output_path)),
    "Recorded-event source authority or worker output changed before publication.")
  result<-output$report$clock_events;brohn_validate_clock_events(result,input)
  id<-paste0("clock-events-",job$id)
  body<-list(schema="brohn-saved-clock-events/0.1",id=id,request=job$request,result=result,created_at=brohn_now(),origin=result$origin,
    processing=list(job_id=job$id,attempt=job$attempt,worker_output_hash=digest::digest(file=output_path,algo="sha256"),code_hashes=output$code_identity))
  document<-NULL;committed<-FALSE;on.exit(if(!is.null(document))brohn_close_publication(document$guard,committed),add=TRUE)
  document<-.brohn_publication_stage_json(store,job,body,file.path(scratch,"published-clock-events.json"))
  receipt<-brohn_store_batch(store,function(){
    store<-brohn_clock_job_fence(store,job)
    brohn_require(.brohn_cm_same(input,brohn_clock_events_input(store,job,FALSE)),"Recorded-event authority changed before commit.")
    .brohn_cm_guard_check(c(guards,list(guard)))
    body$result_object<-.brohn_publication_register(store,document)[[1L]][c("hash","size","media_type")]
    brohn_put_entity(store,"clock_events",id,body,0L,project_id=input$project_id)
    brohn_complete_job(store,job$id,job$worker,job$token,list(clock_events_id=id,output_hash=body$result_object$hash))
  });committed<-TRUE;receipt
}
brohn_clock_events_record <- function(store,ref,project_id,verify=TRUE) {
  brohn_hosted_require_session(store);brohn_hosted_require_project(store,project_id);brohn_project(store,project_id);.brohn_cm_ref_valid(ref)
  .brohn_qexplorer_catalog(store,"clock_events",ref$id,ref$revision,project_id)
  record<-brohn_get_entity(store,"clock_events",ref$id,ref$revision);head<-brohn_get_entity(store,"clock_events",ref$id)
  brohn_require(!is.null(record)&&!is.null(head)&&!isTRUE(head$body$archived)&&!isTRUE(record$body$archived)&&
    identical(head$body$schema,"brohn-saved-clock-events/0.1")&&identical(record$body$schema,"brohn-saved-clock-events/0.1")&&
    identical(head$id,head$body$id)&&identical(record$id,record$body$id)&&.brohn_cm_same(ref,.brohn_cm_ref(record)),"This recorded-event page is no longer available.")
  b<-record$body;job<-brohn_get_job(store,b$processing$job_id)
  brohn_require(!is.null(job)&&identical(job$status,"succeeded")&&identical(job$operation,"clock_event_page")&&
    identical(job$result$clock_events_id,record$id)&&identical(job$result$output_hash,b$result_object$hash)&&
    job$attempt==b$processing$attempt&&.brohn_cm_same(job$request,b$request),"Recorded-event page has no matching successful guarded publication.")
  brohn_require(.brohn_cm_hash(b$processing$worker_output_hash)&&all(vapply(names(b$request$implementation),function(p)
    identical(b$processing$code_hashes[[p]],b$request$implementation[[p]]),logical(1))),
    "Recorded-event publication differs from its queued implementation identity.")
  input<-.brohn_clock_events_context(store,job$request,verify,FALSE);brohn_validate_clock_events(b$result,input)
  brohn_require(!is.null(b$result_object),"Recorded-event page lacks its original retained publication.")
  .brohn_sv_retained(store,record,"clock_events",verify)
  record
}
