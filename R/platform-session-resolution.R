# Researcher decisions are separate from original participant/camera receipts.
.brohn_sr_loaded <- setNames(list(digest::digest(file="R/platform-session-resolution.R",algo="sha256")),"R/platform-session-resolution.R")
.brohn_sr_id <- function(run_id)paste0("session-resolution-",run_id)
brohn_session_resolution <- function(store,run_id) {
  brohn_require(brohn_valid_id(run_id),"Choose an existing participant session.")
  record<-brohn_get_entity(store,"session_resolution",.brohn_sr_id(run_id))
  if(!is.null(record))brohn_require(record$revision==1L&&identical(record$body$schema,"brohn-session-resolution/1.0")&&identical(record$body$run_id,run_id),"The saved researcher resolution is inconsistent.")
  record
}
.brohn_sr_snapshot <- function(store,release_id,run_id,study_id,project_id,include_events=FALSE,verify_bytes=FALSE) {
  release<-.brohn_collection_release(store,release_id,study_id,project_id)
  brohn_require(identical(release$status,"closed"),"Close recruitment for this exact release before resolving a session.")
  assigned<-brohn_run_protocol(store,run_id,study_id,project_id);run<-brohn_run(store,run_id)
  brohn_require(identical(run$deployment_id,release_id)&&identical(run$protocol$design_hash,release$design_hash),"Choose a session from this exact closed release.")
  sizes<-DBI::dbGetQuery(store$con,"SELECT count(*) AS n,coalesce(sum(length(CAST(event_json AS BLOB))),0) AS bytes FROM delivery_events WHERE run_id=?",params=list(run_id))
  brohn_require(sizes$n[[1]]<=100000L&&sizes$bytes[[1]]<=64*1024^2,"This recovery review supports at most 100,000 events and 64 MiB. The complete original session remains retained; no partial source was used.")
  rows<-DBI::dbGetQuery(store$con,"SELECT sequence,event_id,event_json,event_hash FROM delivery_events WHERE run_id=? ORDER BY sequence",params=list(run_id))
  brohn_require(nrow(rows)==run$acked_sequence&&identical(as.numeric(rows$sequence),as.numeric(seq_len(nrow(rows)))),"The acknowledged event sequence is incomplete or inconsistent.")
  events<-lapply(seq_len(nrow(rows)),function(i){e<-.brohn_store_decode(rows$event_json[[i]],rows$event_hash[[i]]);brohn_require(identical(e$id,rows$event_id[[i]])&&e$sequence==rows$sequence[[i]],"A saved event identity differs from its received sequence.");e})
  context<-if(!is.null(run$protocol$design$questionnaire_navigation)).brohn_delivery_revision_context(run$protocol,assigned$hash)else NULL
  state<-.brohn_delivery_replay(run$protocol,events,context)
  ending<-state$ending_outcome
  participant_ending<-if(!is.null(ending))list(outcome=ending,source="received_participant_event",
    event=tail(Filter(function(e)e$type %in% c("run_finished","withdrawal"),events),1L)[[1]])else if(run$completion_status!="in_progress")
      list(outcome=run$completion_status,source="original_participant_final_receipt",event=NULL)else NULL
  if(run$completion_status!="in_progress"&&!is.null(ending))brohn_require(identical(run$completion_status,ending),"The original final receipt disagrees with the received participant ending.")
  capture<-if(DBI::dbExistsTable(store$con,"camera_captures"))brohn_capture(store,run_id=run_id)else NULL
  chunks<-if(is.null(capture))list()else brohn_rows(DBI::dbGetQuery(store$con,"SELECT sequence,content_hash,object_hash,observation_hash,byte_count FROM camera_chunks WHERE capture_id=? ORDER BY sequence",params=list(capture$id)))
  if(!is.null(capture)){
    brohn_require(length(chunks)==capture$acked_sequence&&identical(as.numeric(vapply(chunks,`[[`,numeric(1),"sequence")),as.numeric(seq_along(chunks)))&&sum(vapply(chunks,`[[`,numeric(1),"byte_count"))==capture$total_bytes,"The retained recording chunk sequence or byte totals are inconsistent.")
    for(chunk in chunks){raw<-brohn_object_path(store,chunk$object_hash,verify=verify_bytes);observation<-brohn_object_path(store,chunk$observation_hash,verify=verify_bytes)
      brohn_require(file.info(raw)$size==chunk$byte_count&&file.exists(observation),"A retained recording chunk or observation is unavailable.")}
  }
  support<-brohn_camera_completion(store,run_id)
  complete<-isTRUE(state$run_finished)&&identical(ending,"completed")&&!isTRUE(state$withdrawn)&&isTRUE(support$eligible)
  source<-list(release_id=release_id,study_id=study_id,project_id=project_id,run_id=run_id,origin=run$origin,
    design_hash=release$design_hash,protocol_hash=assigned$hash,allocation_index=run$allocation_index,
    original_receipt=list(completion_status=run$completion_status,transfer_status=run$transfer_status,finalized_at=run$finalized_at),
    received_sequence=run$acked_sequence,event_bytes=sizes$bytes[[1]],event_headers_hash=brohn_hash(brohn_rows(rows[c("sequence","event_id","event_hash")])),
    participant_ending=participant_ending,completed_steps=length(state$completed),planned_steps=length(run$protocol$timeline),
    camera=if(is.null(capture))list(status=if(is.null(run$protocol$design$camera))"not_requested"else"no_received_camera_decision",bytes=0,chunks=0,end_observed=FALSE)else
      list(id=capture$id,status=capture$status,hash=brohn_hash(capture),bytes=capture$total_bytes,chunks=capture$acked_sequence,chunk_headers_hash=brohn_hash(chunks),
        end_observed=!is.null(capture$final)&&!identical(capture$final$reason,"page_reload_recording_end_unobserved"),final_receipt_received=!is.null(capture$final)),
    camera_support=support,received_completion_supported=complete)
  list(source=source,hash=brohn_hash(source),run=if(include_events)run else NULL,events=if(include_events)events else NULL)
}
brohn_session_resolution_review <- function(store,release_id,run_id,study_id,project_id) {
  .brohn_delivery_schema(store);brohn_project(store,project_id)
  read<-function(){
    snapshot<-.brohn_sr_snapshot(store,release_id,run_id,study_id,project_id)
    jobs<-brohn_rows(DBI::dbGetQuery(store$con,paste("SELECT id,operation,status,request_hash,request_json FROM jobs WHERE json_extract(request_json,'$.run_id')=? OR",
      "json_extract(request_json,'$.dataset_id') IN (SELECT e.id FROM entities e JOIN entity_versions v ON e.kind=v.kind AND e.id=v.id AND e.revision=v.revision",
      "WHERE e.kind='dataset' AND e.project_id=? AND json_extract(v.body_json,'$.source_provenance.run_id')=?) ORDER BY id"),params=list(run_id,project_id,run_id)))
    jobs<-lapply(jobs,function(j){r<-brohn_parse(j$request_json);j$request_json<-NULL;j$capture_id<-r$capture_id;j$capture_hash<-r$capture_hash;j})
    source<-snapshot$source;old<-brohn_session_resolution(store,run_id)
    unfinished<-identical(source$original_receipt$completion_status,"in_progress")||identical(source$camera$status,"recording")
    failed_capture<-Filter(function(j)j$operation=="assemble_capture"&&j$status %in% c("failed","cancelled"),jobs)
    active<-Filter(function(j)j$status %in% c("queued","running"),jobs)
    body<-list(source=source,source_hash=snapshot$hash,jobs=jobs)
    list(review=body,hash=brohn_hash(body),existing=old,ready=is.null(old)&&(unfinished||length(failed_capture)>0L)&&!length(active),
      active_jobs=active,received_completion_supported=source$received_completion_supported,
      eligible_analysis=isTRUE(source$received_completion_supported)&&identical(source$original_receipt$completion_status,"in_progress"))
  }
  if(RSQLite::sqliteIsTransacting(store$con))read()else DBI::dbWithTransaction(store$con,read())
}
brohn_resolve_session <- function(store,release_id,run_id,study_id,project_id,expected_hash,reason) {
  brohn_require(brohn_text(reason,2000)&&nzchar(trimws(reason)),"Explain why this specific session needs researcher resolution.")
  reason<-trimws(reason)
  .brohn_store_tx(store,function(){
    old<-brohn_session_resolution(store,run_id)
    if(!is.null(old)){
      brohn_require(identical(old$body$release_id,release_id)&&identical(old$body$study_id,study_id)&&identical(old$project_id,project_id)&&
        identical(old$body$review_hash,expected_hash)&&identical(old$body$operator$reason,reason),"This session already has a different immutable researcher decision. Open its saved resolution.")
      return(old)
    }
    brohn_require(!.brohn_store_execution_paused(store),"This restored workspace is paused. Resume processing before recording a new resolution.")
    brohn_require(is.null(brohn_collection_record(store,release_id,study_id,project_id)),"This collection has already been finalized.")
    current<-brohn_session_resolution_review(store,release_id,run_id,study_id,project_id)
    brohn_require(identical(current$hash,expected_hash),"Received evidence or processing changed after review. Refresh this session review before resolving it.")
    brohn_require(current$ready,"Wait for active processing to finish, or cancel it explicitly in Activity, then refresh this session review.")
    verified<-.brohn_sr_snapshot(store,release_id,run_id,study_id,project_id,verify_bytes=TRUE)
    brohn_require(identical(verified$hash,current$review$source_hash),"Received session evidence changed during its integrity check.")
    source<-current$review$source
    body<-list(schema="brohn-session-resolution/1.0",id=.brohn_sr_id(run_id),run_id=run_id,study_id=study_id,release_id=release_id,origin=source$origin,
      review_hash=expected_hash,source_hash=current$review$source_hash,source=source,
      effective_resolution=if(is.null(source$participant_ending))"researcher_interrupted"else if(current$eligible_analysis)"received_completion_confirmed"else"participant_ending_preserved",
      participant_ending=source$participant_ending,participant_final_receipt_missing=identical(source$original_receipt$completion_status,"in_progress"),
      received_completion_analysis_eligible=current$eligible_analysis,
      operator=list(role="workspace_researcher",reason=reason,decided_at=brohn_now()),
      processing_review=current$review$jobs,
      policy=list(events="Original received participant events, protocol and final receipts are unchanged.",
        camera="Only received bytes are retained. An unobserved recording end is not a camera final receipt, clock endpoint, complete container or decoding claim.",
        late_delivery="Exact already-received operations remain idempotent; no new participant evidence is accepted after this explicit resolution.",
        analysis="Only a received completed ending with replayed complete steps and supported camera receipt can enter separate researcher-confirmed analysis."))
    brohn_put_entity(store,"session_resolution",body$id,body,expected_revision=0L,project_id=project_id)
  })
}
brohn_require_session_receiving <- function(store,run_id) {
  .brohn_delivery_require(is.null(brohn_session_resolution(store,run_id)),"This session's received evidence was closed by the researcher. New uploads cannot change its saved resolution; existing local data have not been deleted.",409,"researcher_resolved")
  invisible(TRUE)
}
brohn_session_resolution_participant <- function(store,run_id) {
  record<-brohn_session_resolution(store,run_id);if(is.null(record))return(NULL);b<-record$body
  list(schema="brohn-participant-resolution/1.0",resolved=TRUE,effective_resolution=b$effective_resolution,
    participant_ending=if(is.null(b$participant_ending))NULL else b$participant_ending$outcome,
    acknowledged_sequence=b$source$received_sequence,received_camera_bytes=b$source$camera$bytes,
    final_receipt_missing=b$participant_final_receipt_missing,
    message="The researcher has closed this session using the evidence already received. This is not confirmation that unsent responses or recordings were received. Local saved data remain in this browser.")
}
brohn_session_resolution_capture_omission <- function(record,job=NULL) {
  if(is.null(record))return(FALSE)
  source<-record$body$source
  if(!brohn_valid_id(source$camera$id))return(FALSE)
  partial<-!isTRUE(source$camera_support$eligible)||!identical(source$camera$status,"completed")||
    is.null(source$participant_ending)||!identical(source$participant_ending$outcome,"completed")
  if(is.null(job))return(partial)
  reviewed<-Filter(function(j)identical(j$id,job$id)&&identical(j$operation,job$operation)&&identical(j$status,job$status)&&
    identical(j$request_hash,brohn_hash(job$request))&&identical(j$capture_id,source$camera$id)&&identical(j$capture_hash,source$camera$hash),record$body$processing_review)
  partial&&length(reviewed)==1L&&identical(job$operation,"assemble_capture")&&job$status %in% c("failed","cancelled")&&
    identical(job$request$capture_id,source$camera$id)&&identical(job$request$capture_hash,source$camera$hash)
}
brohn_queue_resolved_session_analysis <- function(store,resolution_id,resolution_hash) {
  record<-brohn_get_entity(store,"session_resolution",resolution_id)
  brohn_require(!is.null(record)&&identical(brohn_hash(record$body),resolution_hash)&&isTRUE(record$body$received_completion_analysis_eligible),"Only the exact researcher-confirmed received completion can use this analysis route.")
  request<-list(resolution_id=resolution_id,resolution_hash=resolution_hash,run_id=record$body$run_id,project_id=record$project_id,implementation=.brohn_sr_loaded)
  # The transport profile is checked before queuing, never by truncating events.
  invisible(brohn_resolved_session_input(store,list(operation="analyse_resolved_run",request=request)))
  brohn_enqueue_job(store,"analyse_resolved_run",request,paste0("resolved-session-analysis:",brohn_hash(request)))
}
brohn_resolved_session_input <- function(store,job) {
  r<-job$request;record<-brohn_get_entity(store,"session_resolution",r$resolution_id)
  brohn_require(identical(job$operation,"analyse_resolved_run")&&!is.null(record)&&record$revision==1L&&identical(record$project_id,r$project_id)&&
    identical(record$body$run_id,r$run_id)&&identical(brohn_hash(record$body),r$resolution_hash)&&identical(brohn_hash(r$implementation),brohn_hash(.brohn_sr_loaded))&&isTRUE(record$body$received_completion_analysis_eligible),"The pinned researcher-confirmed completion or reader implementation changed.")
  b<-record$body;brohn_project(store,record$project_id)
  snapshot<-.brohn_sr_snapshot(store,b$release_id,b$run_id,b$study_id,record$project_id,include_events=TRUE,verify_bytes=TRUE)
  brohn_require(identical(snapshot$hash,b$source_hash)&&isTRUE(snapshot$source$received_completion_supported),"The complete received source no longer supports this confirmed completion.")
  input<-list(schema="brohn-analysis-input/1.0",operation="analyse_resolved_run",project_id=record$project_id,design=snapshot$run$protocol$design,
    runs=list(snapshot$run),events=setNames(list(snapshot$events),b$run_id),resolution=list(id=record$id,hash=r$resolution_hash,body=b))
  brohn_require(nchar(brohn_json(input),type="bytes")<=8*1024^2,"This confirmed completed source exceeds the initial 8 MiB analysis transport profile. Its original evidence and completion decision remain retained; no incomplete classification or partial analysis was substituted.")
  input
}
brohn_analyse_resolved_session <- function(input,scratch) {
  b<-input$resolution$body
  brohn_require(identical(b$schema,"brohn-session-resolution/1.0")&&identical(brohn_hash(b),input$resolution$hash)&&
    isTRUE(b$received_completion_analysis_eligible)&&identical(b$participant_ending$outcome,"completed"),"This analysis requires an immutable researcher-confirmed received completion.")
  run<-input$runs[[1L]];events<-input$events[[b$run_id]]
  brohn_require(length(input$runs)==1L&&length(input$events)==1L&&identical(run$id,b$run_id)&&
    identical(run$deployment_id,b$release_id)&&identical(input$project_id,b$source$project_id)&&
    identical(brohn_hash(run$protocol),b$source$protocol_hash)&&identical(brohn_hash(input$design),b$source$design_hash)&&
    identical(brohn_hash(run$protocol$design),brohn_hash(input$design))&&identical(brohn_hash(b$source),b$source_hash)&&
    identical(run$completion_status,b$source$original_receipt$completion_status)&&identical(run$transfer_status,b$source$original_receipt$transfer_status)&&
    identical(run$finalized_at,b$source$original_receipt$finalized_at)&&length(events)==b$source$received_sequence&&
    identical(as.numeric(vapply(events,`[[`,numeric(1),"sequence")),as.numeric(seq_along(events))),
    "Confirmed completion input differs from the original received run, protocol or event sequence.")
  headers<-lapply(events,function(e)list(sequence=e$sequence,event_id=e$id,event_hash=brohn_hash(e)))
  brohn_require(identical(brohn_hash(headers),b$source$event_headers_hash),"The worker event content differs from the exact received journal.")
  context<-if(!is.null(run$protocol$design$questionnaire_navigation)).brohn_delivery_revision_context(run$protocol,b$source$protocol_hash)else NULL
  state<-.brohn_delivery_replay(run$protocol,events,context)
  brohn_require(isTRUE(state$run_finished)&&identical(state$ending_outcome,"completed")&&!state$withdrawn,"The original participant journal does not establish completed study steps.")
  result<-brohn_analyse_runs(input)
  if(!is.null(input$design$analysis_plan))result$analysis<-brohn_analysis_plan_result(result$analysis,input$design,
    all(vapply(input$runs,function(r)isTRUE(r$participant_alias_supplied),logical(1))),"plan_frozen_before_these_participant_sessions")
  result$title<-"Researcher-confirmed received completion"
  result$provenance$session_resolution<-input$resolution
  result$provenance$cohort_policy<-"One explicitly confirmed received completion; original participant final receipt remains missing. This does not add the session to ordinary completed-run cohorts."
  result$analysis$limitations<-c(list("This report uses a received completed participant ending and complete supported source, confirmed separately by a researcher after the participant final acknowledgment was lost. Original participant and camera receipts were not invented or rewritten."),result$analysis$limitations)
  result
}
brohn_publish_resolved_session <- function(store,output,scratch,job,input,output_path) {
  .brohn_publication_output_identity(output,.brohn_sr_loaded)
  brohn_require(identical(brohn_hash(output$report$provenance$session_resolution),brohn_hash(input$resolution)),"The scientific report lost its original researcher-confirmed completion provenance.")
  check<-function()brohn_require(identical(brohn_hash(brohn_resolved_session_input(store,job)),brohn_hash(input)),"The source-bound researcher-confirmed completion changed before publication.")
  check();brohn_publish_analysis_report(store,job,input,output,scratch,output_path,before_commit=check)
}
