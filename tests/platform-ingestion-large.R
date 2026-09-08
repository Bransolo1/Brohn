# Actual intake adapter, original binary transport bytes, concurrent participant
# receipt. This does not claim an EDF scientific recipe ran on the fixture.
source("R/platform-load.R");brohn_load(ui=FALSE);source("R/platform-ingestion.R")
local({
  args<-commandArgs(TRUE);mib<-if(length(args))as.integer(args[[1]])else 512L
  evidence<-if(length(args)>1L)args[[2]]else NULL
  mode<-if(length(args)>2L)args[[3]]else "prototype"
  stopifnot(mode%in%c("prototype","shared"))
  stopifnot(mib>=64L,mib<=512L)
  root<-tempfile("brohn-ingestion-large-");dir.create(root);root<-normalizePath(root,winslash="/")
  store<-brohn_open_store(file.path(root,"workspace"));brohn_initialise_library(store)
  children<-list();checks<-0L
  on.exit({
    for(child in children)if(child$is_alive()){child$kill_tree();child$wait(2000)}
    for(id in ls(.brohn_ingestion_sources,all.names=TRUE)){
      held<-get(id,envir=.brohn_ingestion_sources,inherits=FALSE)
      if(identical(held$workspace_id,store$workspace_id)){.Call(held$native$close,held$pointer);rm(list=id,envir=.brohn_ingestion_sources)}
    }
    brohn_close_store(store)
    actual<-normalizePath(root,winslash="/",mustWork=FALSE)
    stopifnot(startsWith(tolower(actual),paste0(tolower(normalizePath(tempdir(),winslash="/")),"/")),startsWith(basename(actual),"brohn-ingestion-large-"))
    unlink(actual,recursive=TRUE,force=TRUE)
  },add=TRUE)
  check<-function(name,ok){if(!isTRUE(ok))stop("Large intake QA: ",name);checks<<-checks+1L}
  upload<-tempfile("completed-original-binary-",fileext=".edf");chunk<-as.raw(rep(0:255,length.out=1024^2))
  con<-file(upload,"wb");for(i in seq_len(mib))writeBin(chunk,con);close(con)
  original_hash<-digest::digest(file=upload,algo="sha256")
  started<-as.numeric(Sys.time())
  record<-brohn_queue_ingestion(store,list(path=upload,name="original-transport.edf",size=as.numeric(mib*1024^2),reference="original-large-upload"),
    "Original large source transport","eeg","sample",operation_id="original-large-intake")
  queue_seconds<-as.numeric(Sys.time())-started
  check("large callback moves source and queues without a source hash",!file.exists(upload)&&record$body$source_snapshot$hash_status=="pending_worker_hash")
  check("large callback stays below local eight-second bound",queue_seconds<8)
  job<-brohn_claim_job(store,"original-large-intake-worker",60);input<-brohn_ingestion_input(store,job)
  scratch<-file.path(store$root,"scratch","original-large-intake");dir.create(scratch,recursive=TRUE)
  request_path<-file.path(scratch,"request.json");output_path<-file.path(scratch,"output.json");brohn_write_json_file(input,request_path)
  if(mode=="prototype") {
  worker<-processx::process$new(brohn_rscript(),c("--vanilla","tests/fixtures/platform-ingestion-child.R","analyse",request_path,scratch,output_path),
    env=c("current",R_LIBS_USER=paste(.libPaths(),collapse=.Platform$path.sep)),stdout="|",stderr="|",cleanup_tree=TRUE,windows_hide_window=TRUE)
  children<-c(children,list(worker));started<-as.numeric(Sys.time());last_renew<-started
  while(worker$is_alive()) {
    worker$wait(100)
    if(as.numeric(Sys.time())-last_renew>15){brohn_renew_job(store,job$id,job$worker,job$token,60);last_renew<-as.numeric(Sys.time())}
    stopifnot(as.numeric(Sys.time())-started<60)
  }
  if(worker$get_exit_status()!=0L)stop(worker$read_all_error())
  output<-brohn_read_json_file(output_path)
  check("actual child preserves full binary with no guessed columns",identical(output$report$ingestion$source$hash,original_hash)&&length(output$report$ingestion$columns)==0L&&length(output$report$ingestion$preview)==0L)
  }
  design<-brohn_new_design("Original concurrent intake receipt")
  for(i in seq_along(design$stimuli))design$stimuli[[i]]$content<-paste("Original concept",i)
  brohn_put_entity(store,"study",design$id,design)
  deployment<-brohn_publish(store,design$id,origin="sample",quota=1L)
  run<-.brohn_delivery_start(store,deployment$token,list(consented=TRUE,client_id="original-intake-client",operation_id="start",participant_alias=""))
  request<-list(operation="receive",workspace=store$root,job_id=job$id,ready=file.path(root,"observer-ready"),output=file.path(root,"observer-result"),
    run_id=run$run_id,access_token=run$access_token,event_request=list(operation_id="original-intake-event",events=list(list(sequence=1L,id="original-intake-visibility",type="visibility",
      step_id=NULL,stimulus_id=NULL,condition_id=NULL,question_id=NULL,phase="setup",clock=list(id="browser-monotonic",unit="ms",value="0.000"),payload=list(hidden=FALSE)))))
  observer_request<-file.path(root,"observer-request.rds");saveRDS(request,observer_request)
  observer<-processx::process$new(brohn_rscript(),c("--vanilla","tests/fixtures/platform-publication-observer.R",observer_request),
    env=c("current",R_LIBS_USER=paste(.libPaths(),collapse=.Platform$path.sep)),stdout="|",stderr="|",cleanup_tree=TRUE,windows_hide_window=TRUE)
  children<-c(children,list(observer));deadline<-as.numeric(Sys.time())+15
  while(!file.exists(request$ready)){if(as.numeric(Sys.time())>deadline||!observer$is_alive())stop(observer$read_all_error());Sys.sleep(.01)}
  .brohn_ingestion_qa_clock<<-new.env(parent=emptyenv());.brohn_ingestion_qa_clock$begins<-numeric();.brohn_ingestion_qa_clock$ends<-numeric()
  trace(".brohn_store_transaction_statement",exit=quote({
    if(identical(sql,"BEGIN IMMEDIATE")) .brohn_ingestion_qa_clock$begins<-c(.brohn_ingestion_qa_clock$begins,as.numeric(Sys.time()))
    if(identical(sql,"COMMIT")) .brohn_ingestion_qa_clock$ends<-c(.brohn_ingestion_qa_clock$ends,as.numeric(Sys.time()))
  }),print=FALSE)
  on.exit({untrace(".brohn_store_transaction_statement");rm(".brohn_ingestion_qa_clock",envir=.GlobalEnv)},add=TRUE)
  if(mode=="prototype") published<-brohn_publish_ingestion(store,output,scratch,job,input,output_path) else {
    brohn_process_job(store,job,timeout_seconds=120)
    published<-brohn_get_job(store,job$id)
    if(published$status!="succeeded")stop("Actual shared intake failed: ",brohn_json(published$error))
  }
  observer$wait(15000)
  check("actual concurrent participant observer saves",observer$get_exit_status()==0L&&file.exists(request$output))
  observed<-readRDS(request$output);tx_start<-tail(.brohn_ingestion_qa_clock$begins,1);tx_end<-tail(.brohn_ingestion_qa_clock$ends,1)
  check("participant receipt saves during large preparation before commit",observed$http_status==200L&&observed$response$acked_sequence==1L&&observed$ended<tx_start)
  check("participant receipt remains below local busy timeout",observed$ended-observed$started<5)
  check("final original plus dataset transaction is locally under one second",tx_end-tx_start<1)
  dataset<-brohn_get_entity(store,"dataset",published$result$dataset_id)
  if(mode=="shared")check("actual shared child preserves binary with no guessed columns",dataset$body$source$hash==original_hash&&length(dataset$body$columns)==0L&&length(dataset$body$preview)==0L)
  check("full size hash and origin commit into dataset",dataset$body$source$size==mib*1024^2&&dataset$body$source$hash==original_hash&&dataset$body$origin=="sample")
  check("complete stored original independently verifies",digest::digest(file=brohn_object_path(store,original_hash),algo="sha256")==original_hash)
  brohn_reap_ingestion_guards(store);brohn_close_store(store);store<-brohn_open_store(file.path(root,"workspace"))
  check("reopen preserves whole original and ready intake",brohn_ingestion(store,record$id)$body$status=="ready"&&file.info(brohn_object_path(store,original_hash))$size==mib*1024^2)
  result<-list(schema="brohn-ingestion-evidence/1.0",measured_at=brohn_now(),checks=checks,source_bytes=mib*1024^2,
    queue_seconds=queue_seconds,metadata_transaction_seconds=tx_end-tx_start,participant_receipt_seconds=observed$ended-observed$started,
    participant_status=observed$http_status,participant_phase=observed$phase,source_hash=original_hash,
    dispatch=mode,code_identity=brohn_ingestion(store,record$id)$body$processing$code_hashes,
    limitations=list("Windows same-volume local timing; no universal latency guarantee.","Original binary transport fixture; no EDF scientific interpretation claimed.","Participant request used the actual HTTP application handler in an independent process, not a network round trip."))
  if(!is.null(evidence)){stopifnot(!file.exists(evidence),dir.exists(dirname(evidence)));writeLines(brohn_json(result),evidence,useBytes=TRUE)}
  cat(sprintf("%d large %s intake checks passed; %d MiB queue %.3fs, metadata %.3fs, participant %.3fs HTTP%d.\n",checks,mode,mib,queue_seconds,tx_end-tx_start,observed$ended-observed$started,observed$http_status))
})
