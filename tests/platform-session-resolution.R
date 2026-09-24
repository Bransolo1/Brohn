# Synthetic original journals exercise researcher recovery independently of UI.
source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=FALSE)
source("R/platform-session-resolution.R",encoding="UTF-8")
local({
  checks<-character();check<-function(label,x){if(!isTRUE(x))stop(label,call.=FALSE);checks<<-c(checks,label);cat("PASS",label,"\n")}
  rejects<-function(x)inherits(try(force(x),silent=TRUE),"try-error")
  folder<-Sys.getenv("BROHN_SESSION_TEST_ROOT",tempfile("brohn-session-domain-"));dir.create(folder,recursive=TRUE,showWarnings=FALSE)
  stopifnot(startsWith(basename(folder),"brohn-session-"),!file.exists(file.path(folder,"workspace","catalog.sqlite")))
  store<-brohn_open_store(file.path(folder,"workspace"));on.exit(brohn_close_store(store),add=TRUE);brohn_initialise_library(store)
  counter<-0L;uuid<-function(){counter<<-counter+1L;paste0("00000000-0000-4000-8000-",sprintf("%012d",counter))}
  clock<-function(value)list(id="browser-monotonic",unit="ms",value=as.character(value),instance_id="original-page",time_origin_ms="1700000000000")
  policy<-list(schema="brohn-camera-policy/1.0",required=TRUE,audio=FALSE,consent_text="Original synthetic recording consent.",retention_text="Original generated test bytes only.",width=640,height=480,frame_rate=15,max_duration_s=10,max_bytes=8*1024^2,analysis_profile="none")
  new_run<-function(camera=NULL){
    d<-brohn_new_design("Original session recovery fixture","survey");d$participant_equipment<-NULL;d$instructions<-""
    q<-brohn_question("Original numeric answer","number","end");q$min<-0;q$max<-10;q$step<-1;d$questions<-list(q);d$camera<-camera
    study<-brohn_put_entity(store,"study",d$id,d,project_id="default");release<-brohn_publish(store,study$id,origin="sample",quota=10)
    start<-.brohn_delivery_start(store,release$token,list(consented=TRUE,client_id=uuid(),participant_alias=paste0("SYNTHETIC-",uuid()),operation_id=uuid()))
    list(run_id=start$run_id,token=start$access_token,protocol=start$protocol,study_id=d$id,release_id=release$id,project_id="default")
  }
  binding<-function(r)r[c("release_id","run_id","study_id","project_id")]
  review<-function(r)do.call(brohn_session_resolution_review,c(list(store=store),binding(r)))
  resolve<-function(r,v,reason="Participant browser unavailable after recruitment closed.")do.call(brohn_resolve_session,c(list(store=store),binding(r),list(expected_hash=v$hash,reason=reason)))
  closed<-function(r){brohn_deployment_state(store,r$release_id,"closed");r}
  event<-function(sequence,type,time,step=NULL,payload=list(original_fixture=TRUE))list(sequence=sequence,id=uuid(),type=type,step_id=step$id,stimulus_id=step$stimulus_id,condition_id=step$condition_id,question_id=step$question$id,phase=if(is.null(step))"complete"else step$phase,clock=clock(time),payload=payload)
  receive<-function(r,events){req<-list(events=events,operation_id=uuid());ack<-.brohn_delivery_receive(store,r$run_id,r$token,req);list(request=req,ack=ack)}
  complete<-function(r){events<-list();time<-100
    add<-function(type,step=NULL,payload=list(original_fixture=TRUE)){events[[length(events)+1L]]<<-event(length(events)+1L,type,time,step,payload);time<<-time+100}
    for(step in r$protocol$timeline){add("step_started",step);if(step$type=="question")add("response",step,list(value=0,response_time_ms=100));add("step_finished",step)}
    add("run_finished",payload=list(outcome="completed"));receive(r,events)
  }
  original<-function(r)list(run=DBI::dbGetQuery(store$con,"SELECT * FROM delivery_runs WHERE id=?",params=list(r$run_id)),
    events=DBI::dbGetQuery(store$con,"SELECT * FROM delivery_events WHERE run_id=? ORDER BY sequence",params=list(r$run_id)),
    receipts=DBI::dbGetQuery(store$con,"SELECT * FROM delivery_receipts WHERE scope=? ORDER BY operation_id",params=list(r$run_id)),
    camera=if(DBI::dbExistsTable(store$con,"camera_captures"))brohn_capture(store,run_id=r$run_id)else NULL)
  a<-new_run();check("Open recruitment refuses operator resolution review",rejects(review(a)));a<-closed(a)
  wrong<-a;wrong$study_id<-"unrelated-study";check("Foreign study cannot review this session",rejects(review(wrong)))
  v<-review(a);check("No participant ending is eligible only as researcher interruption",v$ready&&is.null(v$review$source$participant_ending)&&!v$eligible_analysis)
  check("An operator reason is required",rejects(resolve(a,v," ")))
  received<-receive(a,list(event(1,"visibility",100,payload=list(state="visible"))))
  check("New received event makes prior review stale without writing a decision",rejects(resolve(a,v))&&is.null(brohn_session_resolution(store,a$run_id)))
  v<-review(a);before<-original(a);saved<-resolve(a,v)
  check("Resolution preserves exact original SQL run, journal, receipts and camera",identical(before,original(a)))
  check("Interruption sidecar never invents participant completion or finalization",saved$body$effective_resolution=="researcher_interrupted"&&is.null(saved$body$participant_ending)&&brohn_run(store,a$run_id)$completion_status=="in_progress"&&is.null(brohn_run(store,a$run_id)$finalized_at))
  check("Same resolution retry is idempotent",identical(brohn_hash(saved$body),brohn_hash(resolve(a,v)$body)))
  check("A different reason cannot replace immutable decision",rejects(resolve(a,v,"A changed reason")))
  check("Participant-facing resolution excludes operator reason and credentials",!grepl(saved$body$operator$reason,brohn_json(brohn_session_resolution_participant(store,a$run_id)),fixed=TRUE)&&!grepl(a$token,brohn_json(brohn_session_resolution_participant(store,a$run_id)),fixed=TRUE))
  check("New receive guard rejects resolved session",rejects(brohn_require_session_receiving(store,a$run_id)))
  check("Exact already-received event operation stays idempotent after resolution",identical(brohn_hash(received$ack),brohn_hash(.brohn_delivery_receive(store,a$run_id,a$token,received$request))))
  check("A new late event is rejected without changing received sequence",rejects(receive(a,list(event(2,"visibility",200,payload=list(state="hidden")))))&&brohn_run(store,a$run_id)$acked_sequence==1L)
  check("A new late final receipt cannot overwrite operator decision",rejects(.brohn_delivery_finish(store,a$run_id,a$token,list(outcome="interrupted",final_sequence=1L,operation_id=uuid())))&&identical(before,original(a)))
  b<-new_run();received_complete<-complete(b);b<-closed(b);v<-review(b);before<-original(b)
  check("Actual replayed completed ending without camera qualifies separate confirmation",v$ready&&v$eligible_analysis&&v$review$source$participant_ending$outcome=="completed")
  confirmed<-resolve(b,v);check("Confirmed completion keeps raw in-progress and original missing receipt",confirmed$body$effective_resolution=="received_completion_confirmed"&&confirmed$body$participant_final_receipt_missing&&identical(before,original(b)))
  job<-brohn_queue_resolved_session_analysis(store,confirmed$id,brohn_hash(confirmed$body));input<-brohn_resolved_session_input(store,job)
  result<-brohn_analyse_resolved_session(input,file.path(folder,"scratch"))
  check("Existing response scorer retains numeric zero and original provenance",length(result$analysis$observations)==1L&&identical(as.numeric(result$analysis$observations[[1]]$value),0)&&result$provenance$runs[[1]]$run_id==b$run_id&&is.null(result$provenance$runs[[1]]$finalized_at)&&identical(brohn_hash(result$provenance$session_resolution$body),brohn_hash(confirmed$body)))
  altered<-input;altered$events[[b$run_id]][[2]]$payload$value<-1
  check("Child adapter refuses changed journal content",rejects(brohn_analyse_resolved_session(altered,folder)))
  altered_job<-job;altered_job$request$run_id<-a$run_id
  check("Coordinator refuses cross-run request binding",rejects(brohn_resolved_session_input(store,altered_job)))
  normal<-list(operation="analyse_run",request=list(run_id=b$run_id))
  check("Raw in-progress run still cannot use ordinary analysis route",rejects(brohn_job_input(store,normal)))
  brohn_cancel_job(store,job$id)
  c<-new_run(policy);complete(c);c<-closed(c);v<-review(c);missing<-resolve(c,v)
  check("Actual completed ending with missing required recording remains explicit and ineligible",missing$body$participant_ending$outcome=="completed"&&missing$body$effective_resolution=="participant_ending_preserved"&&!missing$body$received_completion_analysis_eligible&&missing$body$source$camera$status=="no_received_camera_decision")
  check("Missing recording cannot be queued as confirmed completion",rejects(brohn_queue_resolved_session_analysis(store,missing$id,brohn_hash(missing$body))))
  for(outcome in c("withdrawn","interrupted")){
    r<-new_run();receive(r,list(event(1,if(outcome=="withdrawn")"withdrawal"else"run_finished",100,payload=list(outcome=outcome))));r<-closed(r);z<-resolve(r,review(r))
    check(paste("Actual received",outcome,"ending is preserved independently of absent final receipt"),z$body$participant_ending$outcome==outcome&&z$body$participant_final_receipt_missing&&!z$body$received_completion_analysis_eligible)
  }
  r<-new_run(policy);start_req<-list(capture_id=paste0("camera-",uuid()),consented=TRUE,clock=clock(0),mime_type="video/webm;codecs=vp8",settings=list(width=640,height=480,frame_rate=15,audio=FALSE),reason=NULL,operation_id=uuid())
  .brohn_camera_start(store,r$run_id,r$token,start_req)
  bytes<-as.raw(c(26,69,223,163,0));chunk_req<-list(capture_id=start_req$capture_id,sequence=1L,data_base64=jsonlite::base64_enc(bytes),sha256=digest::digest(bytes,algo="sha256",serialize=FALSE),observation=list(callback_ms="100",event_timecode_ms=100,frames=list(),unretained_frame_callbacks=0),operation_id=uuid())
  .brohn_camera_chunk(store,r$run_id,r$token,chunk_req);r<-closed(r);v<-review(r);before<-original(r);open_camera<-resolve(r,v)
  check("Lost recorder resolution preserves original recording status and no endpoint",identical(before,original(r))&&brohn_capture(store,start_req$capture_id)$status=="recording"&&is.null(brohn_capture(store,start_req$capture_id)$final)&&!open_camera$body$source$camera$end_observed&&brohn_session_resolution_capture_omission(open_camera))
  raw<-DBI::dbGetQuery(store$con,"SELECT object_hash FROM camera_chunks WHERE capture_id=?",params=list(start_req$capture_id))$object_hash[[1]]
  check("Original partial chunk bytes remain byte-for-byte available",identical(readBin(brohn_object_path(store,raw,verify=TRUE),"raw",n=5),bytes))
  check("Exact camera start and chunk retries remain acknowledged after resolution",.brohn_camera_start(store,r$run_id,r$token,start_req)$status=="recording"&&.brohn_camera_chunk(store,r$run_id,r$token,chunk_req)$acked_sequence==1L)
  new_chunk<-chunk_req;new_chunk$sequence<-2L;new_chunk$operation_id<-uuid();new_chunk$observation$callback_ms<-"200"
  check("New recording bytes reject after resolution",rejects(.brohn_camera_chunk(store,r$run_id,r$token,new_chunk))&&identical(before,original(r)))
  check("Late camera finish cannot invent an endpoint",rejects(.brohn_camera_finish(store,r$run_id,r$token,list(capture_id=start_req$capture_id,final_sequence=1L,total_bytes=5L,outcome="interrupted",container_complete=FALSE,clock=clock(300),reason="late_fixture_end",operation_id=uuid())))&&is.null(brohn_capture(store,start_req$capture_id)$final))
  r2<-new_run(policy);s2<-start_req;s2$capture_id<-paste0("camera-",uuid());s2$operation_id<-uuid();.brohn_camera_start(store,r2$run_id,r2$token,s2)
  c2<-chunk_req;c2$capture_id<-s2$capture_id;c2$operation_id<-uuid();.brohn_camera_chunk(store,r2$run_id,r2$token,c2)
  .brohn_camera_finish(store,r2$run_id,r2$token,list(capture_id=s2$capture_id,final_sequence=1L,total_bytes=5L,outcome="interrupted",container_complete=FALSE,clock=clock(200),reason="original_synthetic_interruption",operation_id=uuid()))
  r2<-closed(r2);v<-review(r2)
  check("Active partial assembly blocks researcher resolution",!v$ready&&length(v$active_jobs)==1L&&rejects(resolve(r2,v)))
  camera_job<-Filter(function(j)identical(j$request$capture_id,s2$capture_id),brohn_list_jobs(store))[[1]];brohn_cancel_job(store,camera_job$id)
  check("Processing change invalidates earlier recovery review",rejects(resolve(r2,v)))
  partial<-resolve(r2,review(r2));camera_job<-brohn_get_job(store,camera_job$id)
  check("Cancelled exact partial assembly can be explicitly acknowledged as missing results",brohn_session_resolution_capture_omission(partial,camera_job)&&partial$body$source$camera$bytes==5)
  later_job<-camera_job;later_job$id<-"job-unreviewed-attempt"
  check("A later failed attempt cannot inherit reviewed omission",!brohn_session_resolution_capture_omission(partial,later_job))
  different<-camera_job;different$request$capture_hash<-paste(rep("0",64),collapse="")
  check("Different capture input cannot inherit partial assembly acknowledgement",!brohn_session_resolution_capture_omission(partial,different))
  # A supported original container and original camera receipt can qualify the
  # separate response analysis; cancelled full-record assembly is NOT omitted.
  movie<-file.path(folder,"original-pattern.webm")
  processx::run(Sys.which("ffmpeg"),c("-nostdin","-v","error","-f","lavfi","-i","testsrc2=size=640x480:rate=15","-t","1","-an","-c:v","libvpx","-deadline","realtime","-cpu-used","8","-y",movie),timeout=30000,windows_hide_window=TRUE)
  video<-readBin(movie,"raw",n=file.info(movie)$size);full<-new_run(policy);fs<-start_req;fs$capture_id<-paste0("camera-",uuid());fs$operation_id<-uuid()
  .brohn_camera_start(store,full$run_id,full$token,fs);fc<-chunk_req;fc$capture_id<-fs$capture_id;fc$operation_id<-uuid();fc$data_base64<-gsub("[\r\n]","",jsonlite::base64_enc(video));fc$sha256<-digest::digest(video,algo="sha256",serialize=FALSE);fc$observation$callback_ms<-"800";fc$observation$event_timecode_ms<-800
  .brohn_camera_chunk(store,full$run_id,full$token,fc);complete(full)
  .brohn_camera_finish(store,full$run_id,full$token,list(capture_id=fs$capture_id,final_sequence=1L,total_bytes=length(video),outcome="completed",container_complete=TRUE,clock=clock(1000),reason=NULL,operation_id=uuid()))
  full<-closed(full);full_job<-Filter(function(j)identical(j$request$capture_id,fs$capture_id),brohn_list_jobs(store))[[1L]];brohn_cancel_job(store,full_job$id)
  fv<-review(full);full_resolution<-resolve(full,fv)
  check("Actual completed steps plus supported required-camera receipt qualify separate response analysis",fv$eligible_analysis&&full_resolution$body$received_completion_analysis_eligible&&full_resolution$body$source$camera$end_observed)
  check("A failed full-recording assembly is not hidden by partial-capture omission",!brohn_session_resolution_capture_omission(full_resolution,brohn_get_job(store,full_job$id)))
  full_analysis<-brohn_queue_resolved_session_analysis(store,full_resolution$id,brohn_hash(full_resolution$body));full_input<-brohn_resolved_session_input(store,full_analysis)
  check("Required-camera confirmed response scoring retains original numeric zero",brohn_analyse_resolved_session(full_input,folder)$analysis$observations[[1L]]$value==0)
  brohn_cancel_job(store,full_analysis$id)
  dataset<-list(id="dataset-original-descendant",source_provenance=list(run_id=c$run_id));brohn_put_entity(store,"dataset",dataset$id,dataset)
  # A new unresolved session with a linked dataset verifies descendant job fencing.
  descendant<-closed(new_run());dataset$id<-"dataset-unresolved-descendant";dataset$source_provenance$run_id<-descendant$run_id;brohn_put_entity(store,"dataset",dataset$id,dataset)
  child<-brohn_enqueue_job(store,"analyse_dataset",list(dataset_id=dataset$id),"synthetic-descendant-job");dv<-review(descendant)
  check("Active linked dataset processing also blocks resolution",!dv$ready&&length(dv$active_jobs)==1L);brohn_cancel_job(store,child$id)
  pending<-closed(new_run());backup<-brohn_backup_workspace(store,file.path(folder,"backup"));brohn_restore_workspace(backup$path,file.path(folder,"restored"))
  restored<-brohn_open_store(file.path(folder,"restored"));on.exit(brohn_close_store(restored),add=TRUE)
  check("Backup restore preserves sidecar and untouched partial camera evidence",identical(brohn_hash(brohn_session_resolution(restored,r$run_id)$body),brohn_hash(open_camera$body))&&brohn_capture(restored,start_req$capture_id)$status=="recording"&&identical(readBin(brohn_object_path(restored,raw,verify=TRUE),"raw",n=5),bytes))
  rv<-do.call(brohn_session_resolution_review,c(list(store=restored),binding(pending)))
  check("Paused restore rejects new operator decisions",rejects(do.call(brohn_resolve_session,c(list(store=restored),binding(pending),list(expected_hash=rv$hash,reason="Synthetic restore decision")))))
  brohn_write_json_file(list(passed=TRUE,checks=as.list(checks),scope="Original synthetic receipt/byte fixtures; direct scorer arithmetic, no child or decoder or human claims.",jobs=lapply(brohn_list_jobs(store),function(j)list(id=j$id,operation=j$operation,status=j$status))),file.path(folder,"results.json"))
  cat(length(checks),"session resolution domain checks passed;",folder,"\n")
})
