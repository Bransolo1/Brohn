# Real SQLite participant receipts and actual guarded source assembly.
# The still-nonloaded facial camera policy does not enter the runtime here.
source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=FALSE)
source("R/platform-camera-analysis.R",encoding="UTF-8")
source("R/platform-camera-analysis-store.R",encoding="UTF-8")
local({
  args<-commandArgs(trailingOnly=TRUE);folder<-if(length(args))args[[1L]]else tempfile("brohn-camera-authority-")
  stopifnot(!dir.exists(folder));dir.create(folder,recursive=TRUE);folder<-normalizePath(folder,winslash="/",mustWork=TRUE)
  checks<-character();check<-function(label,value){if(!isTRUE(value))stop(label,call.=FALSE);checks<<-c(checks,label);cat("PASS",label,"\n")}
  rejects<-function(expr)inherits(try(force(expr),silent=TRUE),"try-error")
  source_files<-c("R/platform-camera-analysis.R","R/platform-camera-analysis-store.R","R/platform-capture.R","R/platform-delivery.R","R/platform-session-resolution.R","R/platform-jobs.R","scripts/analysis-worker.R")
  source_hashes<-setNames(lapply(source_files,function(p)digest::digest(file=p,algo="sha256")),source_files)
  brohn_write_json_file(list(source_hashes=source_hashes),file.path(folder,"start.json"))
  passed<-FALSE
  on.exit(if(!passed)brohn_write_json_file(list(status="failed",checks=as.list(checks),source_hashes=source_hashes,note="Execution stopped; inspect retained stdout/stderr and workspace. No automatic policy1.1 or native facial inference was run."),file.path(folder,"failure.json")),add=TRUE)
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
  create<-function(){
    d<-brohn_new_design("Generated camera authority study","survey");d$participant_equipment<-NULL;d$instructions<-""
    q<-brohn_question("Explicit liking for software fixture","number","end");q$min<-0;q$max<-10;q$step<-1;d$questions<-list(q);d$camera<-policy
    s<-brohn_put_entity(store,"study",d$id,d,project_id="default");release<-brohn_publish(store,s$id,origin="sample",quota=10)
    r<-.brohn_delivery_start(store,release$token,list(consented=TRUE,participant_alias=paste0("SOFTWARE-",uuid()),client_id=uuid(),operation_id=uuid()))
    request<-list(capture_id=paste0("camera-",uuid()),consented=TRUE,clock=clock(1000),mime_type="video/webm;codecs=vp8",settings=list(width=320,height=240,frame_rate=5,audio=FALSE),reason=NULL,operation_id=uuid())
    .brohn_camera_start(store,r$run_id,r$access_token,request)
    .brohn_camera_chunk(store,r$run_id,r$access_token,list(capture_id=request$capture_id,sequence=1L,data_base64=gsub("[\r\n]","",jsonlite::base64_enc(bytes)),sha256=original_hash,
      observation=list(callback_ms="3000",event_timecode_ms=2000,frames=list(),unretained_frame_callbacks=0L),operation_id=uuid()))
    .brohn_camera_finish(store,r$run_id,r$access_token,list(capture_id=request$capture_id,final_sequence=1L,total_bytes=length(bytes),outcome="completed",container_complete=TRUE,clock=clock(4000),reason=NULL,operation_id=uuid()))
    job<-brohn_claim_job(store,"camera-authority-fixture",lease_seconds=120);stopifnot(job$operation=="assemble_capture",job$request$capture_id==request$capture_id)
    brohn_process_job(store,job,timeout_seconds=90);done<-brohn_get_job(store,job$id)
    if(!identical(done$status,"succeeded"))stop("Actual camera assembly failed: ",brohn_json(done$error))
    d<-brohn_get_entity(store,"dataset",done$result$dataset_id);d<-brohn_curate_dataset(store,d$id,metadata,d$revision)
    list(run_id=r$run_id,token=r$access_token,protocol=r$protocol,study_id=s$id,release_id=release$id,project_id="default",capture_id=request$capture_id,dataset=d,assembly_job=job$id)
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
    for(job in Filter(function(j)j$status=="queued",brohn_list_jobs(store)))brohn_cancel_job(store,job$id)
  }
  original<-function(r)list(run=DBI::dbGetQuery(store$con,"SELECT * FROM delivery_runs WHERE id=?",params=list(r$run_id)),events=DBI::dbGetQuery(store$con,"SELECT * FROM delivery_events WHERE run_id=? ORDER BY sequence",params=list(r$run_id)),
    receipts=DBI::dbGetQuery(store$con,"SELECT * FROM delivery_receipts WHERE scope=? ORDER BY operation_id",params=list(r$run_id)),capture=brohn_capture(store,r$capture_id),
    chunks=DBI::dbGetQuery(store$con,"SELECT * FROM camera_chunks WHERE capture_id=? ORDER BY sequence",params=list(r$capture_id)),dataset=brohn_get_entity(store,"dataset",r$dataset$id,1L),publication=brohn_get_entity(store,"camera_capture",r$capture_id))
  a<-create();complete(a);before<-original(a)
  authority<-brohn_camera_analysis_resolve(store,a$dataset,"manual",TRUE)
  check("Actual received recording and guarded assembly retain original bytes",identical(authority$source_hash,original_hash)&&identical(brohn_capture(store,a$capture_id)$status,"completed"))
  check("Actual later facial mapping keeps original retain-only permission distinct",authority$permission_kind=="researcher_attestation"&&!authority$original_named_permission&&authority$original_dataset$revision==1L&&authority$dataset_revision==2L)
  check("Original generated camera artifact envelope plus chunk observations are pinned",length(authority$source_refs)>=6L&&!is.null(authority$original_chunks_hash))
  check("Actual completed journal and original final receipt stay separate",authority$received_journal$participant_ending$outcome=="completed"&&authority$received_journal$original_receipt$completion_status=="completed")
  check("Metadata-only and byte-verified resolution have identical pins",identical(brohn_hash(authority),brohn_hash(brohn_camera_analysis_resolve(store,a$dataset,"manual",FALSE))))
  check("A real policy1.0 publication cannot automatically acquire facial permission",rejects(brohn_camera_analysis_resolve(store,a$dataset,"automatic",TRUE)))
  check("Read-only resolution leaves actual original SQL receipts and sources unchanged",identical(before,original(a)))
  forged<-a$dataset;forged$body$metadata$consent_statement<-"Substituted outside catalog"
  check("Caller cannot substitute unsaved facial permission metadata",rejects(brohn_camera_analysis_resolve(store,forged,"manual",TRUE)))
  imported<-brohn_ingest_dataset(store,fixture,"Separately reviewed generated import","video",origin="sample");imported<-brohn_curate_dataset(store,imported$id,metadata,imported$revision)
  check("Genuine ordinary reviewed imports remain independent of camera authority",is.null(brohn_camera_analysis_resolve(store,imported,"manual",TRUE)))
  b<-create();prior<-brohn_camera_analysis_resolve(store,b$dataset,"manual",TRUE)
  check("A manual supported source retains raw unfinished outcome without inventing completion",prior$original_run_outcome=="in_progress"&&is.null(prior$received_journal$participant_ending))
  withdrawal<-event(1L,"withdrawal",4500,payload=list(outcome="withdrawn"))
  .brohn_delivery_receive(store,b$run_id,b$token,list(events=list(withdrawal),operation_id=uuid()))
  lost<-original(b)
  check("Received withdrawal blocks facial processing despite a missing participant final receipt",brohn_run(store,b$run_id)$completion_status=="in_progress"&&rejects(brohn_camera_analysis_resolve(store,b$dataset,"manual",TRUE)))
  brohn_deployment_state(store,b$release_id,"closed")
  review<-brohn_session_resolution_review(store,b$release_id,b$run_id,b$study_id,"default")
  resolution<-brohn_resolve_session(store,b$release_id,b$run_id,b$study_id,"default",review$hash,"Software fixture: final acknowledgement never arrived after received withdrawal.")
  check("Actual researcher resolution preserves withdrawal and remains ineligible",resolution$body$participant_ending$outcome=="withdrawn"&&rejects(brohn_camera_analysis_resolve(store,b$dataset,"manual",TRUE)))
  check("Withdrawal denial and its sidecar leave original camera/run receipts unchanged",identical(lost,original(b)))
  c<-create();brohn_deployment_state(store,c$release_id,"closed")
  cv<-brohn_session_resolution_review(store,c$release_id,c$run_id,c$study_id,"default")
  closed<-brohn_resolve_session(store,c$release_id,c$run_id,c$study_id,"default",cv$hash,"Software fixture: session abandoned after its original camera source was received.")
  ca<-brohn_camera_analysis_resolve(store,c$dataset,"manual",TRUE)
  check("Actual interruption sidecar is pinned without changing source outcome or permission",identical(ca$session_resolution$id,closed$id)&&ca$original_run_outcome=="in_progress"&&ca$permission_kind=="researcher_attestation"&&is.null(ca$received_journal$participant_ending))
  # In-place transactions exercise stale catalog/head protections without leaving
  # corruption in the retained fixture or manufacturing a permitted source.
  mutate<-function(code,expr){DBI::dbBegin(store$con);on.exit(DBI::dbRollback(store$con));force(code);rejects(force(expr))}
  changed<-a$dataset$body;changed$source_provenance<-list(acquisition="manual_import",source_hash=changed$source$hash)
  check("A newer mapping cannot strip original camera acquisition lineage",mutate({brohn_put_entity(store,"dataset",a$dataset$id,changed,expected_revision=a$dataset$revision,project_id="default")},brohn_camera_analysis_resolve(store,a$dataset,"manual",TRUE)))
  check("Historical source cannot silently cross project boundaries",mutate({DBI::dbExecute(store$con,"UPDATE entities SET project_id='foreign' WHERE kind='dataset' AND id=?",params=list(a$dataset$id))},brohn_camera_analysis_resolve(store,a$dataset,"manual",TRUE)))
  # Alter only a retained artifact in this isolated workspace, restoring exact
  # bytes and attributes after the refusal. Original incoming fixture is untouched.
  publication<-brohn_get_entity(store,"camera_capture",a$capture_id);manifest<-Filter(function(x)x$kind=="camera-manifest",publication$body$artifacts)[[1L]]
  object<-brohn_object_path(store,manifest$hash);saved<-readBin(object,"raw",n=file.info(object)$size)
  stopifnot(Sys.chmod(object,"0666"));writeBin(c(saved,as.raw(32L)),object)
  refused<-rejects(brohn_camera_analysis_resolve(store,a$dataset,"manual",TRUE));writeBin(saved,object);stopifnot(Sys.chmod(object,"0444"))
  check("Actual changed retained assembly bytes are refused",refused&&identical(digest::digest(file=object,algo="sha256"),manifest$hash))
  brohn_close_store(store);store<-brohn_open_store(file.path(folder,"workspace"))
  check("Reopen retains exact source and authority without new analysis jobs",identical(brohn_hash(authority),brohn_hash(brohn_camera_analysis_resolve(store,a$dataset,"manual",TRUE)))&&length(Filter(function(j)j$operation=="analyse_dataset",brohn_list_jobs(store)))==0L)
  check("Original generated source and loaded worker source identities stay unchanged",identical(digest::digest(file=fixture,algo="sha256"),original_hash)&&identical(source_hashes,setNames(lapply(source_files,function(p)digest::digest(file=p,algo="sha256")),source_files)))
  jobs<-lapply(brohn_list_jobs(store),function(j)list(id=j$id,operation=j$operation,status=j$status))
  receipt<-list(status="passed",count=length(checks),checks=as.list(checks),source_hashes=source_hashes,test_hash=digest::digest(file="tests/platform-camera-analysis-store.R",algo="sha256"),
    original_source_hash=original_hash,authority=authority,jobs=jobs,scope="Actual policy1.0 SQLite session/camera receipts, generated WebM, three actual guarded assembly children and reviewed manual facial mapping. New policy1.1 remains nonloaded; no native facial inference or browser acceptance claimed.")
  brohn_write_json_file(receipt,file.path(folder,"results.json"));passed<-TRUE;cat("TOTAL",length(checks),"\n")
})
