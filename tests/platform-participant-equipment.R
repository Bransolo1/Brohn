source("R/platform-load.R"); brohn_load(ui = TRUE)
local({
  checks <- 0L; check <- function(name, x) {if (!isTRUE(x)) stop(name, call. = FALSE); checks <<- checks+1L; cat("PASS", name, "\n")}
  rejects <- function(x) inherits(try(force(x), silent = TRUE), "try-error")
  d <- brohn_new_design("Original equipment checks", "survey"); d$questions <- list(brohn_question(scope = "end"))
  p <- brohn_compile(d); check("New survey has no unnecessary camera/key/control requirement", !p$equipment$camera && !p$equipment$controls && !length(p$equipment$required_codes))
  d$participant_equipment <- NULL; old <- brohn_compile(d); check("Historical absent policy stays absent", is.null(old$equipment))
  d$participant_equipment <- brohn_participant_equipment_policy(TRUE); p <- brohn_compile(d)
  check("Actual questionnaire enables explicitly selected practice", p$equipment$controls)
  bad <- d$participant_equipment; bad$freshness_ms <- 2001; check("Unknown engineering setting rejects", rejects(brohn_validate_participant_equipment(bad)))
  clock <- function(n=1000, page="original-page") list(id="browser-monotonic",unit="ms",value=as.character(n),instance_id=page,time_origin_ms="1700000000000")
  event <- function(kind, evidence, n=1000, sequence=1L) list(sequence=sequence,id=paste0("original-",sequence),type="equipment_event",step_id=NULL,stimulus_id=NULL,condition_id=NULL,question_id=NULL,
    phase="equipment_setup",clock=clock(n),payload=list(schema="brohn-participant-equipment-check/1.0",policy_hash=p$equipment$policy_hash,kind=kind,attempt_id="original-attempt",evidence=evidence))
  control <- event("controls",list(activation="touch",trusted=TRUE,last_input_ms=1000))
  state <- .brohn_delivery_replay(p,list(control)); check("Practice result does not advance cursor or create answers", state$cursor==1L && !length(state$completed) && is.null(state$active))
  entry <- control; entry$type <- "step_started";entry$payload <- list();entry$clock<-clock(2000)
  check("Current page receipt satisfies gate", isTRUE(.brohn_equipment_gate(state,entry,p)))
  entry$clock<-clock(2000,"other-page");check("New page cannot reuse previous approval",rejects(.brohn_equipment_gate(state,entry,p)))
  check("Missing result cannot pass gate",rejects(.brohn_equipment_gate(.brohn_delivery_initial_state(),entry,p)))
  bad <- control;bad$payload$evidence$trusted<-FALSE;check("Untrusted practice rejects",rejects(.brohn_delivery_replay(p,list(bad))))
  bad <- control;bad$clock$instance_id<-NULL;bad$clock$time_origin_ms<-NULL
  check("Legacy absent clock identity cannot enter a new equipment check",rejects(.brohn_delivery_replay(p,list(bad))))
  entry$clock<-clock(2000);entry$clock$instance_id<-NULL;entry$clock$time_origin_ms<-NULL
  check("Gated entry cannot omit its page identity",rejects(.brohn_equipment_gate(state,entry,p)))
  bad <- control;bad$clock<-clock(3000);check("Exact freshness boundary accepted",!rejects(.brohn_delivery_replay(p,list(bad))))
  bad$clock<-clock(3001);check("Stale input rejects",rejects(.brohn_delivery_replay(p,list(bad))))
  bad <- control;bad$payload$policy_hash<-paste(rep("0",64),collapse="");check("Foreign policy rejects",rejects(.brohn_delivery_replay(p,list(bad))))
  bad<-control;bad$payload$evidence$activation<-"touch_capability_only";check("Declared capability is not observed input",rejects(.brohn_delivery_replay(p,list(bad))))
  d$camera <- list(schema="brohn-camera-policy/1.0",required=TRUE,audio=FALSE,consent_text="Original synthetic camera recording consent.",retention_text="Only original software evidence in isolated storage.",width=320L,height=240L,frame_rate=15,max_duration_s=30,max_bytes=1024*1024,analysis_profile="none")
  p<-brohn_compile(d);check("Requested camera preserves audio disabled",p$equipment$camera&&!p$equipment$audio)
  root<-tempfile("brohn-equipment-domain-");dir.create(root);store<-brohn_open_store(file.path(root,"workspace"))
  on.exit({brohn_close_store(store);actual<-normalizePath(root,winslash="/",mustWork=TRUE);stopifnot(startsWith(actual,normalizePath(tempdir(),winslash="/")));unlink(actual,recursive=TRUE)},add=TRUE)
  saved<-brohn_put_entity(store,"study",d$id,d);deployment<-brohn_publish(store,d$id,origin="sample",quota=10,alias_required=FALSE)
  start<-.brohn_delivery_start(store,deployment$token,list(consented=TRUE,client_id=brohn_id("client"),operation_id=brohn_id("operation"),participant_alias=""))
  run<-brohn_run(store,start$run_id);p<-run$protocol
  capture_id<-"camera-00000000-0000-4000-8000-000000000001"
  .brohn_camera_start(store,run$id,start$access_token,list(capture_id=capture_id,consented=TRUE,clock=clock(100),mime_type="video/webm",settings=list(width=320L,height=240L,frame_rate=15,audio=FALSE),reason=NULL,operation_id=brohn_id("operation")))
  bytes<-charToRaw("Original bytes for receipt accounting; not a decodable camera recording")
  .brohn_camera_chunk(store,run$id,start$access_token,list(capture_id=capture_id,sequence=1L,sha256=digest::digest(bytes,algo="sha256",serialize=FALSE),data_base64=gsub("[\r\n]","",jsonlite::base64_enc(bytes)),observation=list(callback_ms="500",event_timecode_ms=NULL,frames=list(),unretained_frame_callbacks=0L),operation_id=brohn_id("operation")))
  evidence<-list(capture_id=capture_id,track_generation=1L,video=list(live=TRUE,enabled=TRUE,muted=FALSE,frames=2L,last_frame_ms=900,width=320L,height=240L),
    audio=list(requested=FALSE,live=FALSE,enabled=FALSE,muted=TRUE,state="unavailable",blocks=0L,samples=0L,last_block_ms=NULL,sample_rate=NULL,channels=0L,rms=NULL,peak=NULL),
    recording=list(browser_sequence=1L,browser_bytes=length(bytes),acked_sequence=1L,acked_bytes=length(bytes)))
  camera<-event("camera",evidence)
  request<-list(events=list(camera),operation_id=brohn_id("operation"))
  receipt<-.brohn_delivery_receive(store,run$id,start$access_token,request)
  check("Actual receiver accepts exact current capture and saved prefix",receipt$acked_sequence==1L)
  check("Original retry deduplicates evidence",.brohn_delivery_receive(store,run$id,start$access_token,request)$acked_sequence==1L&&length(.brohn_delivery_events(store,run$id))==1L)
  bad<-camera;bad$sequence<-2L;bad$id<-"original-second";bad$payload$evidence$recording$acked_bytes<-1L
  check("Invented acknowledged byte prefix rejects",rejects(.brohn_delivery_receive(store,run$id,start$access_token,list(events=list(bad),operation_id=brohn_id("operation")))))
  bad$payload$evidence<-evidence;bad$payload$evidence$capture_id<-"camera-00000000-0000-4000-8000-000000000002"
  check("Other recording identity rejects",rejects(.brohn_delivery_receive(store,run$id,start$access_token,list(events=list(bad),operation_id=brohn_id("operation")))))
  bad$payload$evidence<-evidence;bad$payload$evidence$video$muted<-TRUE
  check("Muted live camera cannot pass",rejects(.brohn_delivery_replay(p,list(bad))))
  model<-brohn_equipment_evidence(store,run$id);check("Saved researcher model retains exact policy and source evidence",length(model$checks)==1L&&identical(model$checks[[1L]]$payload$evidence$capture_id,capture_id))
  .brohn_camera_finish(store,run$id,start$access_token,list(capture_id=capture_id,final_sequence=1L,total_bytes=length(bytes),outcome="interrupted",container_complete=FALSE,
    clock=clock(100),reason="page_reload_recording_end_unobserved",operation_id=brohn_id("operation")))
  check("Historical pending check retains original page after unobserved reload ending", !rejects(.brohn_equipment_receive(store,run,camera)))
  late<-camera;late$clock<-clock(1000,"new-page");check("Historical camera check cannot switch to reload clock",rejects(.brohn_equipment_receive(store,run,late)))
  html<-as.character(brohn_participant_equipment_evidence_ui(model));check("Researcher evidence exposes independent counts and unknown quality",grepl("browser-committed bytes",html,fixed=TRUE)&&grepl("quality unknown",html,fixed=TRUE))
  brohn_close_store(store);store<-brohn_open_store(file.path(root,"workspace"));check("Reopened workspace retains identical equipment evidence",identical(brohn_hash(model),brohn_hash(brohn_equipment_evidence(store,run$id))))
  microphone_design<-brohn_new_design("Original constant-buffer microphone receipt", "survey")
  microphone_design$questions<-list(brohn_question(scope="end"))
  microphone_design$camera<-d$camera;microphone_design$camera$audio<-TRUE
  brohn_put_entity(store,"study",microphone_design$id,microphone_design)
  microphone_release<-brohn_publish(store,microphone_design$id,origin="sample",quota=1,alias_required=FALSE)
  microphone_start<-.brohn_delivery_start(store,microphone_release$token,list(consented=TRUE,client_id=brohn_id("client"),operation_id=brohn_id("operation"),participant_alias=""))
  microphone_run<-brohn_run(store,microphone_start$run_id);p<-microphone_run$protocol
  microphone_id<-"camera-00000000-0000-4000-8000-000000000003"
  .brohn_camera_start(store,microphone_run$id,microphone_start$access_token,list(capture_id=microphone_id,consented=TRUE,clock=clock(100),mime_type="video/webm",settings=list(width=320L,height=240L,frame_rate=15,audio=TRUE),reason=NULL,operation_id=brohn_id("operation")))
  .brohn_camera_chunk(store,microphone_run$id,microphone_start$access_token,list(capture_id=microphone_id,sequence=1L,sha256=digest::digest(bytes,algo="sha256",serialize=FALSE),data_base64=gsub("[\r\n]","",jsonlite::base64_enc(bytes)),observation=list(callback_ms="500",event_timecode_ms=NULL,frames=list(),unretained_frame_callbacks=0L),operation_id=brohn_id("operation")))
  microphone_evidence<-evidence;microphone_evidence$capture_id<-microphone_id
  # Exact binary32 representation of 0.3: a constant signal has RMS = |amplitude|.
  microphone_evidence$audio<-list(requested=TRUE,live=TRUE,enabled=TRUE,muted=FALSE,state="running",blocks=38L,samples=4864L,last_block_ms=900,sample_rate=48000,channels=1L,rms=0.30000001192092896,peak=0.30000001192092896)
  microphone_receipt<-.brohn_delivery_receive(store,microphone_run$id,microphone_start$access_token,list(events=list(event("camera",microphone_evidence)),operation_id=brohn_id("operation")))
  microphone_saved<-brohn_equipment_evidence(store,microphone_run$id)$checks[[1L]]$payload$evidence$audio
  check("Actual receiver preserves finite constant Float32 microphone RMS and peak",microphone_receipt$acked_sequence==1L&&identical(microphone_saved$rms,microphone_evidence$audio$rms)&&identical(microphone_saved$peak,microphone_evidence$audio$peak))
  cat("Participant equipment domain checks:",checks,"\n")
})
