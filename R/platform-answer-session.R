# Exact answer-to-session evidence; no questionnaire replay or rescoring.
.brohn_answer_session_loaded <- stats::setNames(list(digest::digest(file="R/platform-answer-session.R",algo="sha256")),"R/platform-answer-session.R")
.brohn_as_same <- function(a,b)identical(brohn_hash(a),brohn_hash(b))
.brohn_as_snapshot <- function(con,run_id,project_id) {
  rows<-DBI::dbGetQuery(con,paste("SELECT r.id,r.study_id,r.deployment_id,r.origin,r.participant_alias,r.participant_alias_supplied,r.protocol_hash,",
    "r.allocation_index,r.completion_status,r.transfer_status,r.acked_sequence,r.finalized_at,",
    "d.design_hash AS design_hash,d.project_id,d.design_hash AS release_design_hash",
    "FROM delivery_runs r JOIN delivery_deployments d ON d.id=r.deployment_id WHERE r.id=? AND d.project_id=? AND r.study_id=d.study_id"),params=list(run_id,project_id))
  brohn_require(nrow(rows)==1L,"No exact local session is available in this report's project. Imported names are not local session identities.")
  run<-brohn_rows(rows)[[1L]]
  receipts<-brohn_rows(DBI::dbGetQuery(con,"SELECT operation_id,request_hash,result_json FROM delivery_receipts WHERE scope=? AND operation='finish' ORDER BY operation_id LIMIT 3",params=list(run_id)))
  brohn_require(length(receipts)<=1L,"The original participant final receipt is ambiguous.")
  receipts<-lapply(receipts,function(x){x$result<-.brohn_store_decode(x$result_json);x$result_json<-NULL;x})
  capture<-if(DBI::dbExistsTable(con,"camera_captures"))brohn_rows(DBI::dbGetQuery(con,paste("SELECT id,project_id,status,start_hash,acked_sequence,total_bytes,final_hash,final_json",
    "FROM camera_captures WHERE run_id=?"),params=list(run_id)))else list()
  brohn_require(length(capture)<=1L,"The session has ambiguous camera evidence.")
  if(length(capture)){capture<-capture[[1L]];brohn_require(identical(capture$project_id,project_id),"The capture belongs to another project.")
    capture$final<-if(is.null(capture$final_json))NULL else .brohn_store_decode(capture$final_json,capture$final_hash);capture$final_json<-NULL}else capture<-NULL
  resolution<-brohn_rows(DBI::dbGetQuery(con,paste("SELECT e.id,e.revision,v.body_hash,v.body_json FROM entities e JOIN entity_versions v ON e.kind=v.kind AND e.id=v.id AND e.revision=v.revision",
    "WHERE e.kind='session_resolution' AND e.id=? AND e.project_id=?"),params=list(paste0("session-resolution-",run_id),project_id)))
  if(length(resolution)){resolution<-resolution[[1L]];resolution$body<-.brohn_store_decode(resolution$body_json,resolution$body_hash);resolution$body_json<-NULL
    brohn_require(resolution$revision==1L&&identical(resolution$body$run_id,run_id)&&identical(resolution$body$study_id,run$study_id),"The researcher resolution differs from this session.")
  }else resolution<-NULL
  brohn_require(run$completion_status!="in_progress"||!is.null(resolution),"This local session is still receiving evidence. Review its collection status first.")
  result<-list(run=run,final_receipts=receipts,capture=capture,resolution=resolution)
  brohn_require(nchar(brohn_json(result),type="bytes")<=512*1024,"This session's metadata exceeds the bounded evidence profile; no records were truncated.")
  result
}
.brohn_as_authority <- function(store,r,verify=FALSE) {
  brohn_project(store,r$project_id)
  brohn_require(identical(r$recipe,"saved-answer-session/1.0")&&.brohn_as_same(r$implementation,.brohn_answer_session_loaded),"Prepare this session review with the current reader.")
  c<-r$index_context
  brohn_require(identical(c$workspace_id,store$workspace_id)&&identical(c$root,store$root)&&identical(c$project_id,r$project_id)&&
    identical(.brohn_qexplorer_catalog(store,"report",c$report_id,c$report_revision,c$project_id),c$report_catalog_hash)&&
    identical(.brohn_qexplorer_catalog(store,"questionnaire_index",c$index_id,c$index_revision,c$project_id),c$index_catalog_hash),"The original report or answer-index authority changed.")
  index<-brohn_get_entity(store,"questionnaire_index",c$index_id,c$index_revision)
  brohn_require(identical(brohn_hash(index$body),c$index_hash)&&.brohn_as_same(index$body$binding,r$binding)&&
    identical(index$body$report_id,c$report_id)&&identical(index$body$report_hash,c$report_hash)&&.brohn_as_same(index$body$index,r$index),"The saved answer index differs from this exact report.")
  job<-brohn_get_job(store,index$body$processing$job_id)
  brohn_require(identical(job$status,"succeeded")&&identical(job$result$questionnaire_index_id,index$id)&&identical(job$result$index_hash,c$index_hash)&&
    identical(job$result$artifact_hash,index$body$index$hash)&&identical(job$result$output_hash,index$body$result_object$hash)&&
    identical(brohn_hash(job$request),index$body$request_hash),"The original answer index has no matching successful publication receipt.")
  snapshot<-.brohn_as_snapshot(store$con,r$run_source$run_id,r$project_id)
  brohn_require(.brohn_as_same(snapshot,r$snapshot)&&identical(snapshot$run$protocol_hash,r$run_source$protocol_hash)&&
    identical(snapshot$run$design_hash,r$run_source$design_hash)&&identical(snapshot$run$release_design_hash,r$run_source$design_hash)&&
    identical(snapshot$run$origin,r$binding$origin),"The exact local protocol, received status, capture or researcher resolution changed. Reopen the saved answer.")
  refs<-c(list(list(hash=r$index$hash,bytes=r$index$size),list(hash=index$body$result_object$hash,bytes=index$body$result_object$size)),
    lapply(Filter(Negate(is.null),list(index$body$request$artifact,index$body$request$result_object)),function(x)list(hash=x$hash,bytes=brohn_default(x$size,x$bytes))))
  refs<-unname(refs[!duplicated(vapply(refs,`[[`,character(1),"hash"))])
  for(ref in refs)brohn_require(file.info(brohn_object_path(store,ref$hash,verify=verify))$size==ref$bytes,"A retained answer source changed byte size.")
  list(index=index,source_objects=refs,snapshot=snapshot)
}
brohn_queue_answer_session <- function(store,opened_index,record_key,record_hash,retry=FALSE) {
  c<-opened_index$context
  brohn_check_questionnaire_index_context(store,opened_index,c$report_id,c$report_revision,c$report_hash,c$project_id)
  d<-brohn_questionnaire_index_record(opened_index$handle,record_key,record_hash);rs<-d$links$run_source
  brohn_require(identical(d$record$collection,"answers")&&identical(d$answer_source,"revision_effective_records")&&
    identical(rs$support,"retained_run_identity")&&brohn_valid_id(rs$run_id)&&identical(d$record$run_id,rs$run_id)&&
    identical(d$record$session_id,rs$run_id)&&opened_index$record$body$binding$origin %in% c("sample","pilot","live"),
    "This answer has no exact native protocol and received-event identity. Its complete saved source remains available.")
  r<-list(recipe="saved-answer-session/1.0",implementation=.brohn_answer_session_loaded,project_id=c$project_id,
    index_context=c,binding=opened_index$record$body$binding,index=opened_index$record$body$index,
    record_key=record_key,record_hash=record_hash,run_source=rs,answer=d$record,snapshot=.brohn_as_snapshot(store$con,rs$run_id,c$project_id))
  brohn_require(nchar(brohn_json(r),type="bytes")<=1024^2,"This exact answer-session request exceeds the 1 MiB metadata profile. No records were truncated.")
  .brohn_as_authority(store,r)
  brohn_enqueue_job(store,"answer_session",r,paste0("answer-session:",brohn_hash(r),if(retry)paste0(":",brohn_id("retry"))else""))
}
brohn_answer_session_input <- function(store,job,verify=TRUE) {
  brohn_require(identical(job$operation,"answer_session"),"Choose a saved-answer session review.")
  r<-job$request;s<-.brohn_as_authority(store,r,verify)
  list(schema="brohn-analysis-input/1.0",operation="answer_session",project_id=r$project_id,binding=r,
    catalog_path=normalizePath(file.path(store$root,"catalog.sqlite"),winslash="/",mustWork=TRUE),
    index_path=brohn_object_path(store,r$index$hash,verify=FALSE),source_objects=s$source_objects)
}
.brohn_as_csv <- function(values)paste(vapply(values,function(x){if(is.null(x))x<-"";x<-as.character(x)
  if(substr(x,1L,1L) %in% c("=","+","@","\t","\r","-"))x<-paste0("'",x)
  paste0('"',gsub('"','""',x,fixed=TRUE),'"')},character(1)),collapse=",")
brohn_analyse_answer_session <- function(input,scratch) {
  r<-input$binding;dir<-file.path(scratch,"artifacts");brohn_require(dir.create(dir),"Cannot create session evidence output.")
  source<-DBI::dbConnect(RSQLite::SQLite(),input$catalog_path,flags=RSQLite::SQLITE_RO,loadable.extensions=FALSE)
  on.exit(DBI::dbDisconnect(source),add=TRUE);DBI::dbExecute(source,"PRAGMA query_only=ON");DBI::dbBegin(source);on.exit(try(DBI::dbRollback(source),silent=TRUE),add=TRUE)
  brohn_require(.brohn_as_same(.brohn_as_snapshot(source,r$run_source$run_id,r$project_id),r$snapshot),"Session evidence changed before the reader snapshot.")
  handle<-brohn_questionnaire_index_open(input$index_path,r$index,r$binding);on.exit(brohn_questionnaire_index_close(handle),add=TRUE)
  d<-brohn_questionnaire_index_record(handle,r$record_key,r$record_hash)
  brohn_require(identical(d$record$collection,"answers")&&.brohn_as_same(d$record,r$answer)&&.brohn_as_same(d$links$run_source,r$run_source),"The worker answer is not the pinned source record.")
  p<-DBI::dbGetQuery(source,"SELECT protocol_json,protocol_hash FROM delivery_runs WHERE id=?",params=list(r$run_source$run_id))
  brohn_require(nchar(p$protocol_json[[1]],type="bytes")<=64*1024^2,"The original assigned protocol exceeds 64 MiB; it was not truncated.")
  protocol<-.brohn_store_decode(p$protocol_json[[1]],p$protocol_hash[[1]])
  brohn_require(identical(brohn_hash(protocol),r$run_source$protocol_hash)&&identical(brohn_hash(protocol$design),r$run_source$design_hash)&&
    identical(protocol$design$id,r$snapshot$run$study_id)&&identical(protocol$design$project_id,r$project_id)&&length(protocol$timeline)<=20000L,
    "The original protocol/design is inconsistent or exceeds 20,000 assigned steps.")
  steps<-stats::setNames(protocol$timeline,vapply(protocol$timeline,`[[`,character(1),"id"))
  brohn_require(!anyDuplicated(names(steps))&&r$answer$step_id %in% names(steps)&&identical(steps[[r$answer$step_id]]$question$id,r$answer$question_id),"The answer has no exact assigned question step.")
  index_path<-file.path(dir,"session-evidence.sqlite");out<-DBI::dbConnect(RSQLite::SQLite(),index_path,loadable.extensions=FALSE);on.exit(try(DBI::dbDisconnect(out),silent=TRUE),add=TRUE)
  DBI::dbBegin(out)
  DBI::dbExecute(out,"CREATE TABLE events (sequence INTEGER PRIMARY KEY,event_id TEXT NOT NULL UNIQUE,event_type TEXT NOT NULL,kind TEXT,step_id TEXT,question_id TEXT,occurrence_id TEXT,clock_json TEXT,received_at TEXT NOT NULL,event_hash TEXT NOT NULL,event_json TEXT NOT NULL)")
  DBI::dbExecute(out,"CREATE TABLE assigned (ordinal INTEGER PRIMARY KEY,step_id TEXT NOT NULL UNIQUE,type TEXT NOT NULL,title TEXT NOT NULL,step_json TEXT NOT NULL)")
  for(i in seq_along(steps)){s<-steps[[i]];title<-brohn_default(s[["question"]]$prompt,brohn_default(s[["stimulus"]]$title,brohn_default(s[["task"]]$title,brohn_default(s[["text"]],s$type))))
    DBI::dbExecute(out,"INSERT INTO assigned VALUES (?,?,?,?,?)",params=list(i,s$id,s$type,title,brohn_json(s)))}
  events_path<-file.path(dir,"received-events.json");csv_path<-file.path(dir,"received-event-timeline.csv")
  ec<-file(events_path,"wb");cc<-file(csv_path,"wb");on.exit({try(close(ec),silent=TRUE);try(close(cc),silent=TRUE)},add=TRUE)
  writeBin(charToRaw("["),ec);writeLines(.brohn_as_csv(c("sequence","event_type","kind","step_id","question_id","occurrence_id","clock_json","received_at","event_sha256")),cc,useBytes=TRUE)
  count<-0L;bytes<-2;ending<-NULL;finished<-character();types<-list();headings<-list();last<-0L
  repeat {
    rows<-DBI::dbGetQuery(source,"SELECT sequence,event_id,event_json,event_hash,received_at FROM delivery_events WHERE run_id=? AND sequence>? ORDER BY sequence LIMIT 25",params=list(r$run_source$run_id,last))
    if(!nrow(rows))break
    for(i in seq_len(nrow(rows))){
      text<-rows$event_json[[i]];brohn_require(nchar(text,type="bytes")<=4*1024^2,"A received event exceeds 4 MiB. No partial event was substituted.")
      e<-.brohn_store_decode(text,rows$event_hash[[i]]);canonical<-brohn_json(e);count<-count+1L;bytes<-bytes+nchar(canonical,type="bytes")+as.integer(count>1L)
      brohn_require(count<=1000000L&&bytes<=256*1024^2,"The complete session exceeds one million events or 256 MiB; no partial session is shown.")
      brohn_require(e$sequence==count&&rows$sequence[[i]]==count&&identical(e$id,rows$event_id[[i]])&&identical(brohn_hash(e),rows$event_hash[[i]]),"The received journal sequence or event content is inconsistent.")
      brohn_require(is.null(e$step_id)||e$step_id %in% names(steps),"A received event names a step outside the original protocol.")
      if(count>1L)writeBin(charToRaw(","),ec);writeBin(charToRaw(enc2utf8(canonical)),ec)
      kind<-brohn_default(e$payload$kind,"");occ<-brohn_default(e$payload$occurrence_id,"");clk<-brohn_json(e$clock)
      writeLines(.brohn_as_csv(list(count,e$type,kind,e$step_id,e$question_id,occ,clk,rows$received_at[[i]],rows$event_hash[[i]])),cc,useBytes=TRUE)
      DBI::dbExecute(out,"INSERT INTO events VALUES (?,?,?,?,?,?,?,?,?,?,?)",params=list(count,e$id,e$type,kind,brohn_default(e$step_id,NA_character_),brohn_default(e$question_id,NA_character_),occ,clk,rows$received_at[[i]],rows$event_hash[[i]],canonical))
      types[[e$type]]<-brohn_default(types[[e$type]],0L)+1L
      if(identical(e$type,"step_finished")&&!is.null(e$step_id))finished<-union(finished,e$step_id)
      if(e$type %in% c("run_finished","withdrawal")){brohn_require(is.null(ending),"Multiple participant endings require an explicit supported review.");ending<-list(type=e$type,outcome=brohn_default(e$payload$outcome,if(e$type=="withdrawal")"withdrawn"else NULL),sequence=e$sequence,event_id=e$id,event_hash=rows$event_hash[[i]])}
    };last<-tail(rows$sequence,1L)
  }
  writeBin(charToRaw("]"),ec);close(ec);close(cc)
  brohn_require(count==r$snapshot$run$acked_sequence&&identical(digest::digest(file=events_path,algo="sha256"),r$run_source$events_hash),"The complete received journal does not match the saved answer's event hash.")
  # Every saved revision event must match the exact immutable local event, without
  # treating the final answer projection as another independent response.
  cursor<-0L;history_count<-0L
  repeat{rows<-DBI::dbGetQuery(handle$con,"SELECT ordinal,source_hash,links_json FROM records WHERE collection='history' AND ordinal>? AND run_id=? ORDER BY ordinal LIMIT 100",params=list(cursor,r$run_source$run_id))
    if(!nrow(rows))break
    for(row in brohn_rows(rows)){ref<-brohn_parse(row$links_json)$reference
      hit<-DBI::dbGetQuery(out,"SELECT event_hash,step_id FROM events WHERE sequence=? AND event_id=?",params=list(ref$sequence,ref$event_id))
      brohn_require(nrow(hit)==1L&&identical(hit$event_hash[[1]],ref$source_event_hash)&&identical(row$source_hash,ref$source_event_hash)&&identical(hit$step_id[[1]],ref$step_id),"Saved answer history does not match its received local event.");history_count<-history_count+1L}
    cursor<-tail(rows$ordinal,1L)}
  DBI::dbExecute(out,"CREATE INDEX events_step ON events(step_id,sequence)");DBI::dbCommit(out);DBI::dbDisconnect(out);out<-NULL
  assigned_path<-file.path(dir,"assigned-protocol.json");writeBin(charToRaw(enc2utf8(brohn_json(protocol))),assigned_path)
  descriptor<-function(name,type){path<-file.path(dir,name);list(name=name,hash=digest::digest(file=path,algo="sha256"),bytes=as.numeric(file.info(path)$size),media_type=type)}
  exports<-list(descriptor("session-evidence.sqlite","application/vnd.sqlite3"),descriptor("received-events.json","application/json"),descriptor("received-event-timeline.csv","text/csv"),descriptor("assigned-protocol.json","application/json"))
  result<-list(schema="brohn-answer-session/1.0",binding=r,received=list(events=count,canonical_bytes=bytes,events_hash=r$run_source$events_hash,event_types=types,step_finish_count=length(finished),ending=ending),
    assigned=list(steps=length(steps),camera_requested=!is.null(protocol$design$camera)),verified_history_events=history_count,exports=exports,
    policy="Received browser events are preserved evidence, not physical timing qualification. Assigned steps do not prove presentation or response. Saved final answers and acknowledged revisions keep their original report semantics; no rescoring occurred.")
  brohn_require(nchar(brohn_json(result),type="bytes")<=1024^2,"The bounded session summary exceeds 1 MiB.")
  list(answer_session=result)
}
brohn_validate_answer_session <- function(result,input) {
  brohn_require(identical(result$schema,"brohn-answer-session/1.0")&&.brohn_as_same(result$binding,input$binding)&&
    result$received$events==input$binding$snapshot$run$acked_sequence&&identical(result$received$events_hash,input$binding$run_source$events_hash)&&
    result$received$canonical_bytes<=256*1024^2&&result$assigned$steps<=20000L&&length(result$exports)==4L,
    "The session review changed its exact answer source or complete journal counts.")
  expected<-c("session-evidence.sqlite","received-events.json","received-event-timeline.csv","assigned-protocol.json")
  brohn_require(identical(vapply(result$exports,`[[`,character(1),"name"),expected),"The session exports are incomplete.")
  for(x in result$exports)brohn_require(.brohn_questionnaire_artifact_hash(x$hash)&&brohn_number(x$bytes,1,1024^3,TRUE),"A session export exceeds its bounded artifact profile.")
  brohn_require(identical(result$exports[[2]]$hash,input$binding$run_source$events_hash)&&result$exports[[2]]$bytes==result$received$canonical_bytes,"The complete event export differs from the original journal.")
  invisible(TRUE)
}
brohn_publish_answer_session <- function(store,output,scratch,job,input,output_path) {
  .brohn_publication_output_identity(output,.brohn_answer_session_loaded);.brohn_publication_job(store,job)
  guards<-brohn_hold_signal_value_sources(store,input);on.exit(for(g in guards).brohn_qexplorer_release(g),add=TRUE)
  brohn_require(.brohn_as_same(input,brohn_answer_session_input(store,job))&&.brohn_as_same(output,brohn_read_json_file(output_path)),"The received session or reader output changed before publication.")
  result<-output$report$answer_session;brohn_validate_answer_session(result,input);assets<-document<-NULL;committed<-FALSE
  on.exit({if(!is.null(document))brohn_close_publication(document$guard,committed);if(!is.null(assets))brohn_close_publication(assets$guard,committed)},add=TRUE)
  assets<-.brohn_publication_stage(store,job,lapply(result$exports,function(x)list(key=x$name,kind="answer-session-evidence",path=brohn_checked_artifact_path(store,file.path(scratch,"artifacts",x$name),scratch),sha256=x$hash,bytes=x$bytes,media_type=x$media_type)))
  id<-paste0("answer-session-",sub("^job[_-]","",job$id));body<-list(schema="brohn-saved-answer-session/1.0",id=id,report_id=input$binding$binding$report_id,origin=input$binding$binding$origin,
    request=job$request,result=result,exports=stats::setNames(lapply(assets$descriptors,function(x)x[c("hash","size","media_type")]),vapply(result$exports,`[[`,character(1),"name")),
    created_at=brohn_now(),processing=list(job_id=job$id,attempt=job$attempt,code_hashes=output$code_identity,worker_output_hash=digest::digest(file=output_path,algo="sha256")))
  document<-.brohn_publication_stage_json(store,job,body,file.path(scratch,"published-answer-session.json"))
  receipt<-brohn_store_batch(store,function(){brohn_require(.brohn_as_same(input,brohn_answer_session_input(store,job,verify=FALSE)),"Session authority changed at publication.")
    for(g in guards).Call(g$native$check,g$pointer)
    .brohn_publication_register(store,assets);body$result_object<-.brohn_publication_register(store,document)[[1L]][c("hash","size","media_type")]
    brohn_put_entity(store,"answer_session",id,body,project_id=input$project_id)
    brohn_complete_job(store,job$id,job$worker,job$token,list(answer_session_id=id,report_id=body$report_id,output_hash=body$result_object$hash))})
  committed<-TRUE;receipt
}
brohn_answer_session_record <- function(store,id,request) {
  r<-brohn_get_entity(store,"answer_session",id)
  brohn_require(!is.null(r)&&identical(r$body$schema,"brohn-saved-answer-session/1.0")&&identical(r$project_id,request$project_id)&&.brohn_as_same(r$body$request,request),"Reopen the session from this exact saved answer.")
  input<-brohn_answer_session_input(store,list(operation="answer_session",request=request),verify=FALSE);brohn_validate_answer_session(r$body$result,input)
  job<-brohn_get_job(store,r$body$processing$job_id)
  brohn_require(job$status=="succeeded"&&identical(job$result$answer_session_id,id)&&identical(job$result$output_hash,r$body$result_object$hash)&&.brohn_as_same(job$request,request),"The saved session review has no successful matching job receipt.")
  r
}
brohn_answer_session_page <- function(con,collection,after=0L,step_id=NULL) {
  brohn_require(collection %in% c("events","assigned")&&brohn_number(after,0,1000000L,TRUE),"Choose a valid session evidence page.")
  if(collection=="events"){
    where<-"sequence>?";params<-list(after)
    if(!is.null(step_id)){brohn_require(brohn_text(step_id,1024),"Choose an exact assigned step.");where<-paste(where,"AND step_id=?");params<-c(params,list(step_id))}
    rows<-DBI::dbGetQuery(con,paste("SELECT sequence,event_id,event_type,kind,step_id,question_id,occurrence_id,clock_json,received_at,event_hash,length(event_json) AS characters FROM events WHERE",where,"ORDER BY sequence LIMIT 26"),params=params)
    cursor<-"sequence"
  }else{rows<-DBI::dbGetQuery(con,"SELECT ordinal,step_id,type,substr(title,1,240) AS title,length(title) AS title_characters FROM assigned WHERE ordinal>? ORDER BY ordinal LIMIT 26",params=list(after));cursor<-"ordinal"}
  more<-nrow(rows)>25L;rows<-head(rows,25L)
  list(collection=collection,after=after,rows=brohn_rows(rows),next_after=if(more)tail(rows[[cursor]],1L)else NULL)
}
brohn_answer_session_event_chunk <- function(con,sequence,event_hash,offset=0L) {
  brohn_require(brohn_number(sequence,1,1000000L,TRUE)&&.brohn_questionnaire_artifact_hash(event_hash)&&brohn_number(offset,0,4*1024^2,TRUE)&&offset%%4000L==0L,"Choose a current received event chunk.")
  rows<-DBI::dbGetQuery(con,"SELECT substr(event_json,?,4000) AS text,length(event_json) AS characters,event_hash FROM events WHERE sequence=?",params=list(offset+1L,sequence))
  brohn_require(nrow(rows)==1L&&identical(rows$event_hash[[1]],event_hash)&&offset<rows$characters[[1]],"This event chunk is unavailable in the current source.")
  list(sequence=sequence,event_hash=event_hash,offset=offset,text=rows$text[[1]],characters=rows$characters[[1]],more=offset+4000L<rows$characters[[1]])
}
