# Actual separate-process loopback append/retry/finalization of complete original
# maximum-key SC-IAT evidence. No scoring worker or physical timing claim.
source("R/platform-load.R",encoding="UTF-8");brohn_load()
source("tests/fixtures/sciat-window-journal.R",encoding="UTF-8")
local({
  args<-commandArgs(trailingOnly=TRUE);stopifnot(length(args)==1L)
  folder<-args[[1L]];stopifnot(!dir.exists(folder));dir.create(folder,recursive=TRUE)
  folder<-normalizePath(folder,winslash="/");store<-brohn_open_store(file.path(folder,"workspace"));process<-NULL
  checks<-character();timings<-list();source_files<-c("R/platform-store.R","R/platform-delivery.R","R/platform-sciat-window.R",
    "R/platform-sciat-window-delivery.R","R/platform-participant-equipment.R","R/platform-load.R","scripts/run-participant.R",
    "www/participant/event-batch.js","www/participant/runner.js","tests/fixtures/sciat-window-journal.R",
    "tests/fixtures/participant-large-journal.mjs","tests/fixtures/participant-http-request.mjs","tests/platform-participant-large-receiver.R")
  hashes<-function()setNames(lapply(source_files,function(p)digest::digest(file=p,algo="sha256")),source_files)
  before<-hashes();brohn_write_json_file(before,file.path(folder,"source-start.json"))
  on.exit({
    if(!is.null(process)&&process$is_alive()){process$kill();process$wait()}
    for(j in brohn_list_jobs(store,limit=100L))if(j$status=="queued")brohn_cancel_job(store,j$id)
    if(!file.exists(file.path(folder,"results.json")))brohn_write_json_file(list(passed=FALSE,checks=as.list(checks),timings=timings,
      source_hashes=hashes()),file.path(folder,"failure-progress.json"))
    brohn_close_store(store)
  },add=TRUE)
  check<-function(label,ok){if(!isTRUE(ok))stop(label,call.=FALSE);checks<<-c(checks,label);cat("PASS",label,"\n");flush.console()}
  brohn_initialise_library(store)
  design<-brohn_new_design("Original maximum-key HTTP transaction","blank",id="original-large-receiver-study")
  task<-brohn_task_new("sciat-brohn-response-window-im100/1.0",id="original-large-receiver-task")
  design$blocks<-list(task);brohn_put_entity(store,"study",design$id,design)
  release<-brohn_publish(store,design$id,origin="sample",quota=1L)
  port<-httpuv::randomPort(min=20000L,max=34000L);base<-paste0("http://127.0.0.1:",port)
  executable<-file.path(R.home("bin"),"Rscript.exe");if(!file.exists(executable))executable<-file.path(R.home("bin"),"Rscript")
  process<-processx::process$new(executable,c("--vanilla","scripts/run-participant.R","--root",store$root,"--port",as.character(port)),
    stdout=file.path(folder,"receiver.stdout.log"),stderr=file.path(folder,"receiver.stderr.log"),windows_hide_window=TRUE)
  ready<-FALSE;deadline<-Sys.time()+40
  read_url<-function(address){con<-url(address,open="rb",method="libcurl");on.exit(close(con));readLines(con,warn=FALSE)}
  while(Sys.time()<deadline&&process$is_alive()){
    response<-tryCatch(suppressWarnings(read_url(paste0(base,"/participant/"))),error=function(e)NULL)
    if(!is.null(response)){ready<-TRUE;break};Sys.sleep(.1)
  }
  check("Fresh separate-process participant receiver is ready on loopback",ready)
  call<-function(label,route,payload=NULL,token=NULL,path=NULL){
    request_path<-file.path(folder,"pending-http-request.json");response_path<-file.path(folder,paste0(label,"-transport.json"))
    brohn_write_json_file(list(base=base,route=route,token=token,path=path,json=if(is.null(path)).brohn_store_json(payload)else NULL),request_path)
    status<-system2(Sys.which("node"),c("tests/fixtures/participant-http-request.mjs",shQuote(request_path)),stdout=response_path,stderr=file.path(folder,paste0(label,"-transport.stderr.log")))
    unlink(request_path);stopifnot(status==0L)
    r<-brohn_read_json_file(response_path);seconds<-r$elapsed_s;text<-r$body;value<-jsonlite::fromJSON(text,simplifyVector=FALSE)
    receipt<-list(label=label,route=if(label=="start")"/api/start/[synthetic-release-token]"else route,status=r$status,wire_bytes=r$wire_bytes,elapsed_s=seconds,
      within_runner_15s=seconds<15,response=if(label=="start")list(run_id=value$run_id,allocation_index=value$protocol$allocation_index)else value)
    timings[[length(timings)+1L]]<<-receipt
    brohn_write_json_file(timings,file.path(folder,"http-receipts.json"))
    cat("HTTP",label,r$status,r$wire_bytes,"bytes",seconds,"seconds\n");flush.console()
    if(r$status!=200L)stop("Receiver rejected ",label,": ",text,call.=FALSE)
    value
  }
  start<-call("start",paste0("/api/start/",release$token),list(consented=TRUE,client_id="original-large-client",operation_id="original-large-start",participant_alias="original-large-person"))
  # Same complete independent outer wrapper used by integration, including frozen equipment policy.
  events<-list();now<-10
  clock<-function(t)list(id="browser-monotonic",unit="ms",value=format(t,scientific=FALSE,trim=TRUE,digits=17),instance_id="original-sciat-probe-page",time_origin_ms="1000000")
  append<-function(type,step=NULL,payload=structure(list(),names=character()),at=now+1){
    now<<-at;events[[length(events)+1L]]<<-list(sequence=length(events)+1L,id=paste0("original-event-",length(events)+1L),type=type,
      step_id=step$id,stimulus_id=step$stimulus_id,condition_id=step$condition_id,question_id=NULL,
      phase=if(type=="equipment_event")"equipment_setup"else if(is.null(step))"completion"else step$phase,clock=clock(at),payload=payload)
  }
  requirement<-brohn_equipment_requirements(start$protocol)
  if(length(requirement$required_codes))append("equipment_event",payload=list(schema="brohn-participant-equipment-check/1.0",policy_hash=requirement$policy_hash,
    kind="keyboard",attempt_id="original-keyboard-check",evidence=list(codes=requirement$required_codes,released=TRUE,focused=TRUE,visible=TRUE,last_input_ms=now)))
  if(isTRUE(requirement$controls))append("equipment_event",payload=list(schema="brohn-participant-equipment-check/1.0",policy_hash=requirement$policy_hash,
    kind="controls",attempt_id="original-controls-check",evidence=list(activation="keyboard_or_assistive",trusted=TRUE,last_input_ms=now)))
  for(step in start$protocol$timeline){
    append("step_started",step)
    if(step$type=="task")for(e in original_sciat_window_journal(step$task))append("task_event",step,e$payload,as.numeric(e$clock$value))
    append("step_finished",step)
  }
  append("run_finished",payload=list(outcome="completed"))
  original_path<-file.path(folder,"original-journal.json");brohn_write_json_file(events,original_path)
  original_hash<-digest::digest(file=original_path,algo="sha256")
  status<-system2(Sys.which("node"),c("tests/fixtures/participant-large-journal.mjs",shQuote(folder)),
    stdout=file.path(folder,"fixture.stdout.log"),stderr=file.path(folder,"fixture.stderr.log"));stopifnot(status==0L)
  manifest<-brohn_read_json_file(file.path(folder,"batches.json"));journal<-brohn_read_json_file(file.path(folder,"large-journal.json"))
  compiled<-Filter(function(s)s$type=="task",start$protocol$timeline)[[1L]]$task
  replay<-brohn_sciat_window_replay(compiled,Filter(function(e)e$type=="task_event",journal))
  check("Complete192trial synthetic journal independently replays all three5000key trials",replay$complete&&length(replay$state$responses)==192L&&length(manifest$changed)==3L)
  check("JS selector preserves394contiguous events and a single3MiB-bounded batch with allthree maximum-key trials",length(journal)==394L&&identical(vapply(journal,function(e)as.integer(e$sequence),integer(1)),seq_len(394L))&&
    all(vapply(manifest$batches,function(b)b$wire_bytes<=3*1024^2,logical(1)))&&any(vapply(manifest$batches,function(b)b$maximum_key_trials==3L,logical(1))))
  route<-paste0("/api/events/",start$run_id)
  for(i in seq_along(manifest$batches)){
    batch<-manifest$batches[[i]];path<-file.path(folder,batch$filename)
    result<-call(paste0("append-",i),route,token=start$access_token,path=path)
    check(paste("Actual HTTP durably acknowledges exact contiguous batch",i),result$acked_sequence==batch$batch$last)
    if(batch$maximum_key_trials==3L){
      repeated<-call("exact-large-retry",route,token=start$access_token,path=path)
      check("Exact large operation retry preserves its acknowledgement without duplicate events",identical(result,repeated)&&length(brohn_run_events(store,start$run_id))==batch$batch$last)
    }
  }
  finish<-list(outcome="completed",final_sequence=length(journal),operation_id="original-large-finish")
  done<-call("finish",paste0("/api/finish/",start$run_id),finish,start$access_token)
  jobs<-brohn_list_jobs(store,limit=100L)
  check("Final HTTP completion queues exactly one scientific analysis without running it",done$status=="saved"&&length(jobs)==1L&&jobs[[1L]]$operation=="analyse_run"&&jobs[[1L]]$status=="queued"&&jobs[[1L]]$attempt==0L)
  brohn_cancel_job(store,jobs[[1L]]$id)
  check("Finish retry preserves one cancelled automatic job",identical(done,call("finish-retry",paste0("/api/finish/",start$run_id),finish,start$access_token))&&
    length(brohn_list_jobs(store,limit=100L))==1L&&brohn_list_jobs(store,limit=100L)[[1L]]$status=="cancelled")
  saved<-brohn_run_events(store,start$run_id);expected<-brohn_hash(journal)
  check("Persistence retains every source event field and all15000maximum-key observations",identical(brohn_hash(saved),expected)&&
    sum(vapply(Filter(function(e)e$type=="task_event"&&e$payload$kind=="task_trial_finished",saved),function(e)length(e$payload$data$keys)==5000L,logical(1)))==3L)
  process$kill();process$wait();brohn_close_store(store);store<-brohn_open_store(file.path(folder,"workspace"))
  check("Reopened store retains terminal run, exact full journal and cancelled attempt0 job",brohn_run(store,start$run_id)$completion_status=="completed"&&
    identical(brohn_hash(brohn_run_events(store,start$run_id)),expected)&&brohn_list_jobs(store,limit=100L)[[1L]]$attempt==0L)
  check("Original fixture bytes and all loaded product sources remain unchanged",identical(original_hash,digest::digest(file=original_path,algo="sha256"))&&identical(before,hashes()))
  within<-all(vapply(timings,function(t)t$within_runner_15s,logical(1)))
  brohn_write_json_file(list(passed=TRUE,functional_passed=TRUE,latency_passed=within,checks=as.list(checks),timings=timings,
    runner_timeout_s=15,test_transport_timeout_s=180,run_id=start$run_id,events_hash=expected,original_journal_hash=original_hash,
    batch_manifest=manifest,source_hashes=before,jobs=lapply(brohn_list_jobs(store,limit=100L),function(j)list(id=j$id,status=j$status,attempt=j$attempt)),
    scope="Original synthetic full192trial protocol over separate-process loopback HTTP; max5000retained key observations on three trials, exact retry and finalization. No real person, physical timing or scientific worker qualification."),file.path(folder,"results.json"))
  cat("FUNCTIONAL PASS",length(checks),"checks; allHTTPbelow15s:",within,"\n",folder,"\n")
})
