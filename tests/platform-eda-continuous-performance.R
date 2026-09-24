# Original hand-authored saved-value contract; no scientific scorer is called.
source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=TRUE)
source("R/platform-eda-continuous-review.R",encoding="UTF-8");source("R/platform-eda-continuous-review-views.R",encoding="UTF-8")
args<-commandArgs(trailingOnly=TRUE);folder<-if(length(args))normalizePath(args[[1]],winslash="/",mustWork=FALSE)else tempfile("brohn-eda-continuous-performance-")
stopifnot(!dir.exists(folder));dir.create(folder,recursive=TRUE)
checks<-character();check<-function(label,value){stopifnot(isTRUE(value));checks<<-c(checks,label);cat("PASS",label,"\n")}
rejects<-function(expr)inherits(try(force(expr),silent=TRUE),"try-error")
local({
  reuse<-if(length(args)>1L)normalizePath(args[[2]],winslash="/",mustWork=TRUE)else NULL
  if(is.null(reuse)){
  generated<-processx::run(.brohn_publication_python(),c("tests/workers/eda_continuous_review.py","--fixture",file.path(folder,"hand"),"--stress"),error_on_status=FALSE)
  stopifnot(generated$status==0);f<-brohn_read_json_file(file.path(folder,"hand/fixture.json"))
  }else {
    f<-brohn_read_json_file(file.path(reuse,"hand/fixture.json"))
    dir.create(file.path(folder,"workspace"))
    stopifnot(all(file.copy(list.files(file.path(reuse,"workspace"),full.names=TRUE,all.files=TRUE,no..=TRUE),file.path(folder,"workspace"),recursive=TRUE)))
  }
  store<-brohn_open_store(file.path(folder,"workspace"));on.exit({for(j in brohn_list_jobs(store))if(j$status%in%c("queued","running"))try(brohn_cancel_job(store,j$id),silent=TRUE);brohn_close_store(store)},add=TRUE);brohn_initialise_library(store)
  if(is.null(reuse)){
  d<-brohn_ingest_dataset(store,f$original_source$path,"Original hand-value eda contract","eda",origin="sample")
  d$body$metadata<-list(time_column="time",time_unit="s",sampling_rate=10,value_columns=list("conductance"),unit="S",parameters=f$parameters,origin_statement="Independent saved-value software fixture; no decomposition or human recording.")
  d<-brohn_put_entity(store,"dataset",d$id,d$body,project_id=d$project_id,expected_revision=d$revision)
  artifacts<-lapply(f$artifacts,function(a){o<-brohn_store_object(store,path=a$path,media_type="application/x-ndjson");c(o,a[c("kind","schema","tables","rows","provenance_sha256","complete")])})
  receipt<-list(schema="brohn-physiology-artifact-receipt/1.0",status="verified",artifacts=lapply(f$artifacts,function(a)c(a[c("kind","sha256","bytes","schema","tables","rows","provenance_sha256")],list(verified=TRUE))))
  body<-list(id="report-eda-continuous-hand",dataset_id=d$id,study_id=NULL,origin="sample",title="Original hand-value eda report",provenance=brohn_analysis_provenance(d$body,d$revision),
    analysis=list(kind="eda",modality="eda",source=list(sha256=d$body$source$hash),parameters=list(`recording-1`=f$parameters),
      recordings=list(f$recording),features=f$features,events=list(),artifacts=artifacts,artifact_verification=receipt))
  body$result_object<-brohn_store_object(store,bytes=charToRaw(enc2utf8(brohn_json(list(report=body)))),media_type="application/json")
  r<-brohn_put_entity(store,"report",body$id,body,project_id=d$project_id);original<-brohn_hash(r$body)
  queued<-brohn_queue_eda_continuous_review(store,r$id,r$revision,original,f$selection)
  job<-brohn_claim_job(store,"eda-continuous-bound-fixture",90)
  worker_time<-system.time(brohn_process_job(store,job,timeout_seconds=300))[["elapsed"]]
  terminal<-brohn_get_job(store,queued$id)
  check("Actual supervised reader and native guarded publication succeed at5000candidates",identical(terminal$status,"succeeded"))
  }else {
    r<-brohn_get_entity(store,"report","report-eda-continuous-hand");original<-brohn_hash(r$body)
    job<-Filter(function(j)identical(j$operation,"eda_continuous_review"),brohn_list_jobs(store))[[1L]]
    terminal<-job;worker_time<-NULL
    check("Reused copied5000candidate workspace has a successful actual reader publication",identical(job$status,"succeeded"))
  }
  saved<-brohn_get_entity(store,"eda_continuous_review",terminal$result$eda_continuous_review_id)
  b<-saved$body$result;i<-brohn_eda_continuous_review_input(store,list(operation="eda_continuous_review",request=saved$body$request))
  check("Maximum candidate population retains all5000rows and15000exact markers",length(b$candidates)==5000&&length(b$markers)==15000&&b$counts$selected_samples==50201)
  cold<-system.time(.brohn_ecr_validate_cached(b,i))[["elapsed"]]
  warm<-system.time(.brohn_ecr_validate_cached(b,i))[["elapsed"]]
  bad<-b;bad$markers[[2]]$phasic_us<-bad$markers[[2]]$phasic_us+.1
  check("Same-shape changed numeric marker cannot borrow a successful cached predicate",rejects(.brohn_ecr_validate_cached(bad,i)))
  check("Repeated full predicate is memoized by exact result input and implementation",warm<cold/2&&length(ls(.brohn_ecr_predicates,all.names=TRUE))<=8)
  timings<-new.env(parent=emptyenv());timings$ping<-numeric();timings$verification<-NULL;timings$open<-NULL
  server<-function(input,output,session){
    state<-shiny::reactiveValues(page="report",report_id=r$id,error=NULL)
    attempt<-function(fn)tryCatch(fn(),error=function(e){state$error<-conditionMessage(e);NULL})
    brohn_install_eda_continuous_review(input,output,session,store,state,attempt,function(x)NULL,function(fn)fn())
    output$ping<-shiny::renderText(paste("pong",input$ping))
  }
  shiny::testServer(server,{
    session$setInputs(open_eda_continuous_review=list(report_id=r$id,report_hash=original));session$flushReact()
    session$setInputs(eda_continuous_review_recording=brohn_json(f$selection[c("recording_id","segment_id","channel")]),
      eda_continuous_review_start=f$selection$start_s,eda_continuous_review_end=f$selection$end_s,eda_continuous_review_candidate_start=1)
    start<-proc.time()[["elapsed"]]
    session$setInputs(eda_continuous_review_reopen=list(id=saved$id,hash=.brohn_ecr_view_hash(saved$body)));session$flushReact()
    timings$open<-proc.time()[["elapsed"]]-start
    check("Cold full validation starts in supervised background before numerical output",grepl("background",output$eda_continuous_review_result$html,fixed=TRUE))
    check("Downloads remain unavailable until full background verification",rejects(output$eda_continuous_review_manifest))
    for(n in 1:100){
      elapsed<-system.time({session$setInputs(ping=n);session$flushReact();stopifnot(identical(output$ping,paste("pong",n)))})[["elapsed"]]
      timings$ping<-c(timings$ping,elapsed)
      Sys.sleep(.1);session$elapse(1100);session$flushReact()
      if(grepl("Saved EDA waveform review",output$eda_continuous_review_result$html,fixed=TRUE))break
      stopifnot(is.null(state$error))
    }
    timings$verification<-proc.time()[["elapsed"]]-start
    check("Background maximum-bound verification completes with numeric results",grepl("Saved EDA waveform review",output$eda_continuous_review_result$html,fixed=TRUE))
    check("Shiny answers reactive round trips while maximum-bound predicate runs",length(timings$ping)>1&&max(timings$ping)<1.5)
    session$setInputs(eda_continuous_review_end="5019");session$flushReact()
    check("Selection change immediately refuses a previously verified download",rejects(output$eda_continuous_review_manifest))
  })
  refs<-c(i$source_objects,lapply(saved$body$exports,function(x)list(hash=x$hash,bytes=x$size)),list(list(hash=saved$body$result_object$hash,bytes=saved$body$result_object$size)))
  snapshot<-list(body=saved$body[setdiff(names(saved$body),"result_object")],input=i,
    paths=lapply(refs,function(x)list(path=brohn_object_path(store,x$hash),sha256=x$hash)),retained_path=brohn_object_path(store,saved$body$result_object$hash))
  snapshot$body$result$series$tonic_us[[1]]$points[[1]]$value<-snapshot$body$result$series$tonic_us[[1]]$points[[1]]$value+.1
  proof<-file.path(folder,"same-shape-corrupt.rds");saveRDS(snapshot,proof)
  check("Changed finite sample cannot pass background retained-envelope verification",rejects(.brohn_ecr_verify_snapshot(proof)))
  check("Original source and immutable scientific report remain unchanged",identical(original,brohn_hash(brohn_get_entity(store,"report",r$id)$body))&&identical(digest::digest(file=f$original_source$path,algo="sha256"),f$original_source$hash))
  brohn_write_json_file(list(passed=TRUE,checks=as.list(checks),worker_s=worker_time,cold_predicate_s=cold,warm_predicate_s=warm,
    background_verification_s=timings$verification,open_request_s=timings$open,ping_s=as.list(timings$ping),max_ping_s=max(timings$ping),job_id=job$id,source_hashes=c(.brohn_eda_continuous_review_loaded,list(view=digest::digest(file="R/platform-eda-continuous-review-views.R",algo="sha256"))),reused_from=reuse,
    scope="Independent hand-authored complete50201sample/5000candidate software contract, actual supervised reader/native publication, real Shiny reactive loop and background R process. No physiological model qualification."),file.path(folder,"results.json"))
  cat(length(checks),"continuous EDA bound and background checks passed\n")
})
