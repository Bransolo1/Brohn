# Opt-in large-file comparison of the new stage/commit API. The baseline
# production publishers stay unchanged until the adapters are reviewed.
for(module in c("platform-core","platform-store","platform-delivery","platform-publication"))source(paste0("R/",module,".R"),encoding="UTF-8")
local({
  args<-commandArgs(TRUE);mib<-if(length(args))as.numeric(args[[1]]) else 1024
  stopifnot(length(mib)==1L,is.finite(mib),mib>=64,mib<=1024,mib==floor(mib))
  evidence<-if(length(args)>1L)args[[2L]] else NULL
  root<-tempfile("brohn-publication-large-");dir.create(root);root<-normalizePath(root,winslash="/")
  store<-brohn_open_store(file.path(root,"workspace"));h<-NULL;observer<-NULL;checks<-0L
  on.exit({
    if(!is.null(observer)&&observer$is_alive())observer$kill_tree()
    if(!is.null(h))try(brohn_close_publication(h),silent=TRUE)
    brohn_close_store(store)
    actual<-normalizePath(root,winslash="/",mustWork=FALSE)
    stopifnot(startsWith(tolower(actual),paste0(tolower(normalizePath(tempdir(),winslash="/")),"/")),startsWith(basename(actual),"brohn-publication-large-"))
    Sys.chmod(list.files(actual,recursive=TRUE,full.names=TRUE,all.files=TRUE),"0666");unlink(actual,recursive=TRUE,force=TRUE)
  },add=TRUE)
  check<-function(name,ok){if(!isTRUE(ok))stop("Large publication QA: ",name);checks<<-checks+1L}
  original<-file.path(store$root,"original-large.bin");chunk<-rep(as.raw(0:255),4096)
  connection<-file(original,"wb");for(i in seq_len(mib))writeBin(chunk,connection);close(connection)
  spec<-list(key="original-large",kind="original-fixture",path=normalizePath(original,winslash="/"),
    sha256=digest::digest(file=original,algo="sha256"),bytes=as.numeric(file.info(original)$size),media_type="application/octet-stream")
  d<-brohn_new_design("Original simultaneous save",id="study-stage-receipt")
  for(i in seq_along(d$stimuli))d$stimuli[[i]]$content<-paste("Original concept",i)
  invisible(brohn_put_entity(store,"study",d$id,d));deployment<-brohn_publish(store,d$id,origin="sample",quota=1L)
  run<-.brohn_delivery_start(store,deployment$token,list(consented=TRUE,client_id="original-client",operation_id="start",participant_alias=""))
  job<-brohn_enqueue_job(store,"original-stage-fixture",list(origin="sample",bytes=spec$bytes),"large-original-stage")
  job<-brohn_claim_job(store,"large-stage-owner",60)
  request<-list(operation="receive",workspace=store$root,job_id=job$id,ready=file.path(root,"observer-ready"),output=file.path(root,"observer-result"),
    run_id=run$run_id,access_token=run$access_token,event_request=list(operation_id="original-event",
      events=list(list(sequence=1L,id="original-visibility",type="visibility",step_id=NULL,stimulus_id=NULL,condition_id=NULL,question_id=NULL,phase="setup",
        clock=list(id="browser-monotonic",unit="ms",value="0.000"),payload=list(hidden=FALSE)))))
  input<-file.path(root,"observer-request.rds");saveRDS(request,input)
  observer<-processx::process$new(file.path(R.home("bin"),"Rscript.exe"),c("--vanilla","tests/fixtures/platform-publication-observer.R",input),
    env=c("current",R_LIBS_USER=paste(.libPaths(),collapse=.Platform$path.sep)),stdout="|",stderr="|",cleanup_tree=TRUE,windows_hide_window=TRUE)
  until<-as.numeric(Sys.time())+15
  while(!file.exists(request$ready)) {if(as.numeric(Sys.time())>until||!observer$is_alive())stop(observer$read_all_error());Sys.sleep(.01)}
  began<-as.numeric(Sys.time());h<-brohn_prepare_publication(store,job,list(spec),timeout_seconds=180);prepared<-as.numeric(Sys.time())
  observer$wait(15000)
  check("independent observer exits normally",identical(observer$get_exit_status(),0L) && file.exists(request$output))
  receipt<-readRDS(request$output)
  check("participant receipt succeeds while bulk preparation is underway",receipt$http_status==200L && receipt$response$acked_sequence==1L && receipt$started>=began && receipt$ended<prepared)
  check("receipt does not wait for the five-second writer timeout",receipt$ended-receipt$started<5)
  check("no object catalog metadata exists before fenced commit",DBI::dbGetQuery(store$con,"SELECT count(*) AS n FROM objects")$n[[1]]==0L)
  tx_began<-as.numeric(Sys.time());lock_entered<-NULL
  objects<-brohn_store_batch(store,function(){
    lock_entered<<-as.numeric(Sys.time());objects<-brohn_commit_prepared_objects(store,h)
    brohn_put_entity(store,"fixture_report","large-report",list(origin="sample",objects=objects))
    brohn_complete_job(store,job$id,job$worker,job$token,list(report_id="large-report"));objects
  })
  committed<-as.numeric(Sys.time());brohn_close_publication(h,committed=TRUE)
  check("metadata transaction meets the local one-second acceptance target",committed-lock_entered<1)
  check("completed exact attempt retains complete original bytes",brohn_get_job(store,job$id)$status=="succeeded" &&
    objects[[1]]$size==spec$bytes && identical(digest::digest(file=brohn_object_path(store,objects[[1]]$hash),algo="sha256"),spec$sha256))
  again<-.brohn_delivery_receive(store,run$run_id,run$access_token,request$event_request)
  check("simultaneous receipt remains exactly idempotent after publication",again$acked_sequence==1L && length(brohn_run_events(store,run$run_id))==1L)
  record<-list(schema="brohn-staged-publication-evidence/1.0",measured_at=brohn_now(),checks=checks,artifact_bytes=spec$bytes,
    preparation_seconds=prepared-began,metadata_transaction_seconds=committed-lock_entered,metadata_total_seconds=committed-tx_began,
    participant_receipt_seconds=receipt$ended-receipt$started,participant_http_status=receipt$http_status,participant_during_phase=receipt$phase,
    exact_retry_acked=again$acked_sequence,source_sha256=spec$sha256,
    source_identity=lapply(c("R/platform-publication.R","scripts/workers/publication.py","R/platform-store.R","R/platform-delivery.R"),
      function(path)list(path=path,sha256=digest::digest(file=path,algo="sha256"))),
    limitations=list("New staging API measured before production publisher integration.","Original generated fixture and Windows local timings only; no universal latency guarantee.",
      "The native guard is Windows-qualified; POSIX sealing is explicitly unsupported."))
  if(!is.null(evidence)){stopifnot(!file.exists(evidence),dir.exists(dirname(evidence)));writeLines(brohn_json(record),evidence,useBytes=TRUE)}
  cat(sprintf("Staged %s MiB: preparation %.3fs; metadata lock %.3fs; participant %.3fs HTTP %s; %d checks passed.\n",
    mib,prepared-began,committed-lock_entered,receipt$ended-receipt$started,receipt$http_status,checks))
})
