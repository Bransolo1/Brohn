# Real SQLite participant receipts and actual guarded source assembly.
# Loaded policy1.1, real receipts, guarded assembly and original-source automatic queue.
source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=FALSE)
source("R/platform-camera-analysis.R",encoding="UTF-8")
source("R/platform-camera-analysis-store.R",encoding="UTF-8")
local({
  args<-commandArgs(trailingOnly=TRUE);folder<-if(length(args))args[[1L]]else tempfile("brohn-camera-automatic-")
  stopifnot(!dir.exists(folder));dir.create(folder,recursive=TRUE);folder<-normalizePath(folder,winslash="/",mustWork=TRUE)
  checks<-character();check<-function(label,value){if(!isTRUE(value))stop(label,call.=FALSE);checks<<-c(checks,label);cat("PASS",label,"\n")}
  rejects<-function(expr)inherits(try(force(expr),silent=TRUE),"try-error")
  source_files<-c("R/platform-camera-analysis.R","R/platform-camera-analysis-store.R","R/platform-capture.R","R/platform-delivery.R","R/platform-session-resolution.R","R/platform-jobs.R","scripts/analysis-worker.R")
  source_hashes<-setNames(lapply(source_files,function(p)digest::digest(file=p,algo="sha256")),source_files)
  brohn_write_json_file(list(source_hashes=source_hashes),file.path(folder,"start.json"))
  passed<-FALSE
  on.exit(if(!passed)brohn_write_json_file(list(status="failed",checks=as.list(checks),source_hashes=source_hashes,note="Execution stopped; inspect retained stdout/stderr and workspace. Loaded1.1 integration stopped; inspect retained receipts; no native inference is claimed."),file.path(folder,"failure.json")),add=TRUE)
  store<-brohn_open_store(file.path(folder,"workspace"));on.exit(brohn_close_store(store),add=TRUE);brohn_initialise_library(store)
  fixture<-file.path(folder,"original-generated-pattern.webm")
  processx::run(Sys.which("ffmpeg"),c("-nostdin","-v","error","-f","lavfi","-i","testsrc2=size=320x240:rate=5","-t","1","-an","-c:v","libvpx","-deadline","realtime","-cpu-used","8","-n",fixture),timeout=30000,windows_hide_window=TRUE)
  bytes<-readBin(fixture,"raw",n=file.info(fixture)$size);original_hash<-digest::digest(bytes,algo="sha256",serialize=FALSE)
  counter<-0L;uuid<-function(){counter<<-counter+1L;paste0("00000000-0000-4000-8000-",sprintf("%012d",counter))}
  clock<-function(value)list(id="browser-monotonic",unit="ms",value=as.character(value),instance_id="software-page",time_origin_ms="1700000000000")
  policy<-list(schema="brohn-camera-policy/1.0",required=TRUE,audio=FALSE,consent_text="Generated software recording only; no person.",retention_text="Retain source evidence for isolated software QA.",
    width=320,height=240,frame_rate=5,max_duration_s=10,max_bytes=8*1024^2,analysis_profile="none")
  metadata<-list(profile=.brohn_facial_profile,origin_statement="Original synthetic pattern recorded through actual participant transport and guarded source assembly.",
    consent_statement="Researcher separately attests permission for manual local facial processing of this generated software pattern; no participant or human data.",start_s="0",frame_stride=1L,max_support_gap_s=.25)
  policy<-brohn_camera_analysis_policy(policy,brohn_camera_analysis_settings("0",NULL,1L,.25))
  create<-function(assemble=TRUE){
    d<-brohn_new_design("Generated camera authority study","survey");d$participant_equipment<-NULL;d$instructions<-""
    q<-brohn_question("Explicit liking for software fixture","number","end");q$min<-0;q$max<-10;q$step<-1;d$questions<-list(q);d$camera<-policy
    s<-brohn_put_entity(store,"study",d$id,d,project_id="default");release<-brohn_publish(store,s$id,origin="sample",quota=10)
    r<-.brohn_delivery_start(store,release$token,list(consented=TRUE,participant_alias=paste0("SOFTWARE-",uuid()),client_id=uuid(),operation_id=uuid()))
    request<-list(capture_id=paste0("camera-",uuid()),consented=TRUE,clock=clock(1000),mime_type="video/webm;codecs=vp8",settings=list(width=320,height=240,frame_rate=5,audio=FALSE),reason=NULL,operation_id=uuid())
    request$analysis_consent<-TRUE;request$analysis_policy_hash<-policy$analysis_policy_hash
    bad<-request;bad$analysis_policy_hash<-paste(rep("a",64),collapse="")
    stopifnot(rejects(.brohn_camera_start(store,r$run_id,r$access_token,bad)))
    .brohn_camera_start(store,r$run_id,r$access_token,request)
    .brohn_camera_chunk(store,r$run_id,r$access_token,list(capture_id=request$capture_id,sequence=1L,data_base64=gsub("[\r\n]","",jsonlite::base64_enc(bytes)),sha256=original_hash,
      observation=list(callback_ms="3000",event_timecode_ms=2000,frames=list(),unretained_frame_callbacks=0L),operation_id=uuid()))
    .brohn_camera_finish(store,r$run_id,r$access_token,list(capture_id=request$capture_id,final_sequence=1L,total_bytes=length(bytes),outcome="completed",container_complete=TRUE,clock=clock(4000),reason=NULL,operation_id=uuid()))
    result<-list(run_id=r$run_id,token=r$access_token,protocol=r$protocol,study_id=s$id,release_id=release$id,project_id="default",capture_id=request$capture_id)
    if(assemble)result<-assemble_source(result)
    result
  }
  event<-function(sequence,type,time,step=NULL,payload=list(software_fixture=TRUE))list(sequence=sequence,id=uuid(),type=type,step_id=step$id,stimulus_id=step$stimulus_id,condition_id=step$condition_id,
    question_id=step$question$id,phase=if(is.null(step))"complete"else step$phase,clock=clock(time),payload=payload)
  complete<-function(r){
    events<-list();time<-1500
    add<-function(type,step=NULL,payload=list(software_fixture=TRUE)){events[[length(events)+1L]]<<-event(length(events)+1L,type,time,step,payload);time<<-time+100}
    for(step in r$protocol$timeline){add("step_started",step);if(step$type=="question")add("response",step,list(value=0,response_time_ms=100));add("step_finished",step)}
    add("run_finished",payload=list(outcome="completed"))
    .brohn_delivery_receive(store,r$run_id,r$token,list(events=events,operation_id=uuid()))
    .brohn_delivery_finish(store,r$run_id,r$token,list(outcome="completed",final_sequence=length(events),operation_id=uuid()))
    for(job in Filter(function(j)j$status=="queued"&&j$operation=="analyse_run",brohn_list_jobs(store)))brohn_cancel_job(store,job$id)
  }
  original<-function(r)list(run=DBI::dbGetQuery(store$con,"SELECT * FROM delivery_runs WHERE id=?",params=list(r$run_id)),events=DBI::dbGetQuery(store$con,"SELECT * FROM delivery_events WHERE run_id=? ORDER BY sequence",params=list(r$run_id)),
    receipts=DBI::dbGetQuery(store$con,"SELECT * FROM delivery_receipts WHERE scope=? ORDER BY operation_id",params=list(r$run_id)),capture=brohn_capture(store,r$capture_id),
    chunks=DBI::dbGetQuery(store$con,"SELECT * FROM camera_chunks WHERE capture_id=? ORDER BY sequence",params=list(r$capture_id)),dataset=brohn_get_entity(store,"dataset",r$dataset$id,1L),publication=brohn_get_entity(store,"camera_capture",r$capture_id))
  assemble_source<-function(r){
    job<-Filter(function(j)j$operation=="assemble_capture"&&j$request$capture_id==r$capture_id,brohn_list_jobs(store))[[1L]]
    claimed<-brohn_claim_job(store,"camera-automatic-fixture",120);stopifnot(identical(claimed$id,job$id))
    brohn_process_job(store,claimed,timeout_seconds=90);done<-brohn_get_job(store,job$id)
    if(!identical(done$status,"succeeded"))stop("Actual named camera assembly failed: ",brohn_json(done$error))
    r$dataset<-brohn_get_entity(store,"dataset",done$result$dataset_id);r$assembly_job<-job$id;r
  }
  facial_jobs<-function()Filter(function(j)j$operation=="analyse_dataset"&&!is.null(j$request$camera_analysis_authority),brohn_list_jobs(store))
  a<-create();check("Original named policy assembles before final participant receipt without premature inference",length(facial_jobs())==0L&&a$dataset$revision==1L)
  complete(a);before<-original(a);jobs<-facial_jobs();check("Original completed participant receipt automatically queues the frozen source exactly once",length(jobs)==1L&&jobs[[1L]]$status=="queued")
  authority<-brohn_camera_analysis_resolve(store,a$dataset,"automatic",TRUE)
  check("Original named agreement retains exact digest, settings and separate raw completion",authority$permission_kind=="original_named_participant"&&authority$original_named_permission&&authority$mode=="automatic"&&identical(brohn_hash(a$dataset$body$metadata),brohn_hash(brohn_camera_analysis_metadata(brohn_capture(store,a$capture_id)))))
  check("Metadata finalization pin equals full supervised byte and journal validation",identical(brohn_hash(authority),brohn_hash(brohn_camera_analysis_resolve(store,a$dataset,"automatic",FALSE))))
  check("Automatic job request and actual supervised input contain identical authority",identical(brohn_hash(jobs[[1L]]$request$camera_analysis_authority),brohn_hash(authority))&&identical(brohn_hash(brohn_job_input(store,jobs[[1L]])$camera_analysis_authority),brohn_hash(authority)))
  for(i in 1:3)brohn_queue_capture_analysis(store,a$run_id)
  check("Repeated completion or assembly scheduling cannot duplicate the same automatic job",length(facial_jobs())==1L)
  oldenv<-Sys.getenv(c("BROHN_PYTHON_FACIAL_AU","BROHN_FACIAL_MODEL_DIR","BROHN_FACIAL_FFMPEG_DIR"),unset=NA)
  on.exit(for(key in names(oldenv))if(is.na(oldenv[[key]]))Sys.unsetenv(key)else do.call(Sys.setenv,setNames(list(oldenv[[key]]),key)),add=TRUE)
  Sys.setenv(BROHN_PYTHON_FACIAL_AU="C:/unavailable-brohn-optional-runtime/python.exe",BROHN_FACIAL_MODEL_DIR="C:/unavailable-brohn-optional-models",BROHN_FACIAL_FFMPEG_DIR="C:/unavailable-brohn-optional-decoder")
  job<-brohn_claim_job(store,"camera-optional-unavailable",120);stopifnot(job$id==jobs[[1L]]$id)
  brohn_process_job(store,job,timeout_seconds=90);failed<-brohn_get_job(store,job$id)
  check("Unavailable optional runtime fails processing while original receipt and source stay durable",failed$status=="failed"&&identical(before,original(a))&&identical(brohn_object_path(store,a$dataset$body$source$hash,verify=TRUE),brohn_object_path(store,a$dataset$body$source$hash)))
  retry<-brohn_retry_processing(store,failed$id);check("Retry keeps exact original named authority and setting pins",identical(brohn_hash(retry$request),brohn_hash(failed$request)))
  brohn_cancel_job(store,retry$id)
  b<-create(FALSE);complete(b);check("A completed participant receipt waits for actual assembly when source arrives later",length(facial_jobs())==2L)
  b<-assemble_source(b);check("Actual later assembly automatically queues the original completed recording",length(facial_jobs())==3L&&brohn_camera_analysis_resolve(store,b$dataset,"automatic",TRUE)$original_named_permission)
  for(job in Filter(function(j)j$status=="queued",facial_jobs()))brohn_cancel_job(store,job$id)
  brohn_capture_catalog_integrity(store$con);check("Loaded named policy and original digest pass full camera backup catalog validation",TRUE)
  alljobs<-lapply(brohn_list_jobs(store),function(j)list(id=j$id,operation=j$operation,status=j$status))
  brohn_close_store(store);store<-brohn_open_store(file.path(folder,"workspace"))
  check("Reopen preserves original authority and all unchanged camera/source receipts",identical(before,original(a))&&identical(brohn_hash(authority),brohn_hash(brohn_camera_analysis_resolve(store,a$dataset,"automatic",TRUE))))
  check("Original generated recording and all implementation identities remain unchanged",identical(digest::digest(file=fixture,algo="sha256"),original_hash)&&identical(source_hashes,setNames(lapply(source_files,function(p)digest::digest(file=p,algo="sha256")),source_files)))
  brohn_write_json_file(list(status="passed",count=length(checks),checks=as.list(checks),source_hashes=source_hashes,test_hash=digest::digest(file="tests/platform-camera-automatic.R",algo="sha256"),
    original_source_hash=original_hash,authority=authority,jobs=alljobs,scope="Actual loaded1.1 participant receipts, generated WebM, two guarded assembly children, both completion/assembly orderings, exact automatic queue authority, missing optional runtime and immutable restart. No browser or native facial inference acceptance claimed."),file.path(folder,"results.json"))
  passed<-TRUE;cat("TOTAL",length(checks),"\n")
})
