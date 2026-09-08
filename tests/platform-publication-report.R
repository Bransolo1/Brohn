# Actual generic report publisher under concurrent participant receipt. The
# original large NDJSON is a transport fixture, never claimed as vision science.
source("R/platform-load.R");brohn_load(ui=FALSE)
local({
  args<-commandArgs(TRUE);mib<-if(length(args))as.numeric(args[[1]]) else 1024
  stopifnot(length(mib)==1L,is.finite(mib),mib>=64,mib<=1024,mib==floor(mib))
  evidence<-if(length(args)>1L)args[[2]] else NULL
  root<-tempfile("brohn-report-publication-");dir.create(root);root<-normalizePath(root,winslash="/")
  store<-brohn_open_store(file.path(root,"workspace"));observer<-NULL;checks<-0L
  on.exit({
    if(!is.null(observer)&&observer$is_alive())observer$kill_tree()
    brohn_close_store(store)
    actual<-normalizePath(root,winslash="/",mustWork=FALSE)
    stopifnot(startsWith(tolower(actual),paste0(tolower(normalizePath(tempdir(),winslash="/")),"/")),startsWith(basename(actual),"brohn-report-publication-"))
    Sys.chmod(list.files(actual,recursive=TRUE,full.names=TRUE,all.files=TRUE),"0666");unlink(actual,recursive=TRUE,force=TRUE)
  },add=TRUE)
  check<-function(name,ok){if(!isTRUE(ok))stop("Report publication QA: ",name);checks<<-checks+1L}
  scratch<-file.path(store$root,"scratch","original-large-report");dir.create(file.path(scratch,"artifacts"),recursive=TRUE)
  original<-file.path(scratch,"artifacts","original-transport.ndjson")
  prefix<-'{"original_transport_fixture":"';suffix<-'"}\n'
  chunk<-charToRaw(paste0(prefix,paste(rep("x",1024^2-nchar(prefix)-nchar(suffix)),collapse=""),suffix))
  connection<-file(original,"wb");for(i in seq_len(mib))writeBin(chunk,connection);close(connection)
  artifact<-list(kind="vision-observations",path=normalizePath(original,winslash="/"),sha256=digest::digest(file=original,algo="sha256"),bytes=as.numeric(file.info(original)$size))
  d<-brohn_new_design("Original concurrent report transport",id="study-large-report")
  for(i in seq_along(d$stimuli))d$stimuli[[i]]$content<-paste("Original concept",i)
  brohn_put_entity(store,"study",d$id,d)
  deployment<-brohn_publish(store,d$id,origin="sample",quota=1L)
  run<-.brohn_delivery_start(store,deployment$token,list(consented=TRUE,client_id="original-client",operation_id="start",participant_alias=""))
  input<-list(project_id="default",design=d,operation="original-transport-fixture",origin="sample")
  job<-brohn_enqueue_job(store,"original-transport-fixture",input,"large-report-original")
  job<-brohn_claim_job(store,"original-report-owner",60)
  paths<-c("R/platform-publication.R","scripts/workers/publication.py","src/publication_guard.c")
  result<-list(schema="brohn-analysis-output/1.0",code_identity=setNames(lapply(paths,function(p)digest::digest(file=p,algo="sha256")),paths),
    report=list(title="Original publication transport fixture",study_id=d$id,origin="sample",analysis=list(schema="brohn-vision-result/1.0",kind="original-transport-fixture",
      status="ok",artifacts=list(artifact),limitations=list("Original transport fixture; no scientific estimate or model execution is claimed."))))
  result_path<-file.path(scratch,"result.json");brohn_write_json_file(result,result_path)
  request<-list(operation="receive",workspace=store$root,job_id=job$id,ready=file.path(root,"observer-ready"),output=file.path(root,"observer-result"),
    run_id=run$run_id,access_token=run$access_token,event_request=list(operation_id="original-event",events=list(list(sequence=1L,id="original-visibility",type="visibility",
      step_id=NULL,stimulus_id=NULL,condition_id=NULL,question_id=NULL,phase="setup",clock=list(id="browser-monotonic",unit="ms",value="0.000"),payload=list(hidden=FALSE)))))
  request_path<-file.path(root,"observer-request.rds");saveRDS(request,request_path)
  observer<-processx::process$new(file.path(R.home("bin"),"Rscript.exe"),c("--vanilla","tests/fixtures/platform-publication-observer.R",request_path),
    env=c("current",R_LIBS_USER=paste(.libPaths(),collapse=.Platform$path.sep)),stdout="|",stderr="|",cleanup_tree=TRUE,windows_hide_window=TRUE)
  until<-as.numeric(Sys.time())+15
  while(!file.exists(request$ready)){if(as.numeric(Sys.time())>until||!observer$is_alive())stop(observer$read_all_error());Sys.sleep(.01)}
  # Observe successful fixed transaction statements; leave their code and return
  # values intact. Final BEGIN/COMMIT bracket the actual report publication.
  .brohn_publication_qa_clock<<-new.env(parent=emptyenv())
  .brohn_publication_qa_clock$begins<-numeric();.brohn_publication_qa_clock$ends<-numeric()
  trace(".brohn_store_transaction_statement",exit=quote({
    if(identical(sql,"BEGIN IMMEDIATE")) .brohn_publication_qa_clock$begins<-c(.brohn_publication_qa_clock$begins,as.numeric(Sys.time()))
    if(identical(sql,"COMMIT")) .brohn_publication_qa_clock$ends<-c(.brohn_publication_qa_clock$ends,as.numeric(Sys.time()))
  }),print=FALSE)
  on.exit({untrace(".brohn_store_transaction_statement");rm(".brohn_publication_qa_clock",envir=.GlobalEnv)},add=TRUE)
  began<-as.numeric(Sys.time());published<-brohn_publish_analysis_report(store,job,input,result,scratch,result_path,180);ended<-as.numeric(Sys.time())
  observer$wait(15000)
  check("actual concurrent participant observer completes",identical(observer$get_exit_status(),0L)&&file.exists(request$output))
  receipt<-readRDS(request$output);lock_start<-tail(.brohn_publication_qa_clock$begins,1);lock_end<-tail(.brohn_publication_qa_clock$ends,1)
  check("participant saves during preparation before metadata transaction",receipt$http_status==200L&&receipt$response$acked_sequence==1L&&receipt$started>=began&&receipt$ended<lock_start)
  check("participant receipt avoids busy timeout",receipt$ended-receipt$started<5)
  check("actual report metadata transaction stays below local one-second target",lock_end-lock_start<1)
  saved<-brohn_get_entity(store,"report",published$result$report_id)$body
  # complete_job returns a job record, retaining its result receipt.
  check("actual generic publisher completes exact fenced attempt",brohn_get_job(store,job$id)$status=="succeeded"&&!is.null(saved))
  object<-saved$analysis$artifacts[[1]]
  check("full artifact is registered with exact bytes and source hash",object$size==mib*1024^2&&identical(object$hash,artifact$sha256)&&identical(digest::digest(file=brohn_object_path(store,object$hash),algo="sha256"),artifact$sha256))
  check("report records parent-owned native build provenance",identical(saved$processing$publication$mode,"staged-windows-parent-read-seal/1.0")&&
    identical(saved$processing$publication$native_build$source_sha256,digest::digest(file="src/publication_guard.c",algo="sha256")))
  exported<-brohn_parse(rawToChar(readBin(brohn_object_path(store,saved$result_object$hash),"raw",n=saved$result_object$size)))
  check("frozen exported JSON has exact registered artifact descriptors",identical(brohn_hash(exported$report$analysis$artifacts),brohn_hash(saved$analysis$artifacts)))
  again<-.brohn_delivery_receive(store,run$run_id,run$access_token,request$event_request)
  check("concurrent participant retry remains exactly idempotent",again$acked_sequence==1L&&length(brohn_run_events(store,run$run_id))==1L)
  brohn_close_store(store);store<-brohn_open_store(file.path(root,"workspace"))
  check("complete report and full artifacts survive reopen",identical(brohn_get_entity(store,"report",saved$id)$body,saved)&&file.info(brohn_object_path(store,object$hash))$size==object$size)
  record<-list(schema="brohn-report-publication-evidence/1.0",measured_at=brohn_now(),checks=checks,artifact_bytes=artifact$bytes,
    total_publication_seconds=ended-began,metadata_transaction_seconds=lock_end-lock_start,participant_receipt_seconds=receipt$ended-receipt$started,
    participant_http_status=receipt$http_status,participant_during_phase=receipt$phase,source_sha256=artifact$sha256,native_build=saved$processing$publication$native_build,
    source_identity=lapply(c(paths,"R/platform-jobs.R","R/platform-vision.R","R/platform-store.R","R/platform-delivery.R"),function(path)list(path=path,sha256=digest::digest(file=path,algo="sha256"))),
    limitations=list("Actual generic publisher with an original transport fixture; scientific model qualification is separate.","Windows local timings, not a universal latency guarantee."))
  if(!is.null(evidence)){stopifnot(!file.exists(evidence),dir.exists(dirname(evidence)));writeLines(brohn_json(record),evidence,useBytes=TRUE)}
  cat(sprintf("Generic report %s MiB: metadata %.3fs; participant %.3fs HTTP%s; %d checks passed.\n",mib,lock_end-lock_start,receipt$ended-receipt$started,receipt$http_status,checks))
})
