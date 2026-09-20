source("R/platform-load.R");brohn_load(ui=FALSE);source("R/platform-ingestion.R")
local({
  checks<-0L
  check<-function(name,value){if(!isTRUE(value))stop("Ingestion QA: ",name,call.=FALSE);checks<<-checks+1L}
  rejects<-function(expr)inherits(try(force(expr),silent=TRUE),"try-error")
  root<-tempfile("brohn-ingestion-qa-");dir.create(root);root<-normalizePath(root,winslash="/")
  store<-brohn_open_store(file.path(root,"workspace"));brohn_initialise_library(store)
  children<-list()
  on.exit({
    for(child in children)if(child$is_alive()){child$kill_tree();child$wait(2000)}
    for(id in ls(.brohn_ingestion_sources,all.names=TRUE)){
      held<-get(id,envir=.brohn_ingestion_sources,inherits=FALSE)
      if(identical(held$workspace_id,store$workspace_id)){.Call(held$native$close,held$pointer);rm(list=id,envir=.brohn_ingestion_sources)}
    }
    brohn_close_store(store)
    actual<-normalizePath(root,winslash="/",mustWork=FALSE)
    stopifnot(startsWith(tolower(actual),paste0(tolower(normalizePath(tempdir(),winslash="/")),"/")),grepl("^brohn-ingestion-qa-",basename(actual)))
    unlink(actual,recursive=TRUE,force=TRUE)
  },add=TRUE)
  upload<-function(text,name="original.csv",reference=brohn_id("upload")) {
    path<-tempfile("completed-upload-",fileext=paste0(".",tools::file_ext(name)));writeBin(charToRaw(text),path)
    list(path=path,name=name,size=file.info(path)$size,reference=reference)
  }
  queue<-function(file,operation=brohn_id("operation"),study_id=NULL)brohn_queue_ingestion(store,file,"Original source","gaze","sample",study_id=study_id,operation_id=operation)
  process<-function(record) {
    job<-brohn_claim_job(store,"original-intake-test",60)
    stopifnot(identical(job$id,record$body$job_id))
    input<-brohn_ingestion_input(store,job)
    scratch<-tempfile("ingestion-worker-",tmpdir=store$root);dir.create(scratch)
    request<-file.path(scratch,"request.json");output<-file.path(scratch,"output.json")
    brohn_write_json_file(input,request)
    child<-processx::run(brohn_rscript(),c("--vanilla","tests/fixtures/platform-ingestion-child.R","analyse",request,scratch,output),
      env=c("current",R_LIBS_USER=paste(.libPaths(),collapse=.Platform$path.sep)),timeout=60,cleanup_tree=TRUE,windows_hide_window=TRUE,error_on_status=FALSE)
    if(child$status!=0L||isTRUE(child$timeout))stop(child$stderr)
    list(job=job,input=input,scratch=scratch,output=brohn_read_json_file(output),output_path=output)
  }
  publish<-function(p)brohn_publish_ingestion(store,p$output,p$scratch,p$job,p$input,p$output_path)
  original<-"sample,time,missing,literal,answer\n0,0,,NA,false\n1,0.010,0,NA,true\n"
  file<-upload(original);hash<-digest::digest(file=file$path,algo="sha256")
  started<-proc.time()[["elapsed"]];record<-queue(file,"original-first");queue_seconds<-proc.time()[["elapsed"]]-started
  check("completed temporary upload moved while original filename retained",!file.exists(file$path)&&file.exists(record$body$source_snapshot$path)&&record$body$review$filename=="original.csv")
  check("pending intake creates no partial dataset",length(brohn_list_entities(store,"dataset"))==0L&&record$body$status=="queued")
  check("metadata snapshot honestly has no precomputed SHA",record$body$source_snapshot$hash_status=="pending_worker_hash"&&!"hash"%in%names(record$body$source_snapshot))
  check("same-size pending source overwrite is denied",suppressWarnings(rejects({con<-file(record$body$source_snapshot$path,"r+b");on.exit(close(con));writeBin(as.raw(0),con)})))
  check("pending source rename is denied",!suppressWarnings(file.rename(record$body$source_snapshot$path,paste0(record$body$source_snapshot$path,".swap"))))
  reloaded<-new.env(parent=globalenv());sys.source("R/platform-ingestion.R",reloaded);gc()
  check("different loader environment retains the exact process guard registry",identical(reloaded$.brohn_ingestion_sources,.brohn_ingestion_sources))
  check("reloaded module still denies pending source mutation",suppressWarnings(rejects({con<-file(record$body$source_snapshot$path,"r+b");close(con)})))
  other_store<-brohn_open_store(file.path(root,"other-workspace"));brohn_initialise_library(other_store)
  other_file<-upload(original)
  other_record<-brohn_queue_ingestion(other_store,other_file,"Original source","gaze","sample",operation_id="original-first")
  check("same operation ID in another workspace retains both independent guards",identical(other_record$id,record$id)&&
    exists(.brohn_ingestion_key(store,record$id),envir=.brohn_ingestion_sources,inherits=FALSE)&&exists(.brohn_ingestion_key(other_store,other_record$id),envir=.brohn_ingestion_sources,inherits=FALSE))
  check("second workspace does not drop first source guard",suppressWarnings(rejects({con<-file(record$body$source_snapshot$path,"r+b");close(con)})))
  brohn_cancel_ingestion(other_store,other_record$id,other_record$revision)
  other_key<-.brohn_ingestion_key(other_store,other_record$id);other_held<-get(other_key,envir=.brohn_ingestion_sources,inherits=FALSE)
  .Call(other_held$native$close,other_held$pointer);rm(list=other_key,envir=.brohn_ingestion_sources);brohn_close_store(other_store)
  check("operation retry returns original before looking for consumed upload",identical(queue(file,"original-first")$id,record$id))
  changed<-file;changed$reference<-"different-upload"
  check("changed upload under same operation conflicts",rejects(queue(changed,"original-first")))
  p<-process(record)
  check("actual isolated worker retains zero empty and literal NA",p$output$report$ingestion$preview[[1]]$sample=="0"&&p$output$report$ingestion$preview[[1]]$missing==""&&p$output$report$ingestion$preview[[1]]$literal=="NA"&&p$output$report$ingestion$preview[[1]]$answer=="false")
  check("whole source checksum survives actual worker",identical(p$output$report$ingestion$source$hash,hash))
  check("worker milestones are bounded complete files",all(file.exists(file.path(p$scratch,paste0("ingestion-",c("hashing","preview","verified"),".json")))))
  result<-publish(p);ready<-brohn_ingestion(store,record$id);dataset<-brohn_get_entity(store,"dataset",ready$body$dataset_id)
  check("dataset ingestion and exact job become ready atomically",result$status=="succeeded"&&ready$body$status=="ready"&&dataset$body$status=="needs_mapping")
  check("whole original object bytes preserved",identical(readBin(brohn_object_path(store,dataset$body$source$hash),"raw",n=file$size),charToRaw(original)))
  check("original origin and source snapshot remain explicit",dataset$body$origin=="sample"&&dataset$body$source_provenance$source_snapshot_hash==p$input$source_snapshot_hash)
  check("publication has native parent guards",isTRUE(ready$body$processing$publication$native_seal))
  envelope<-brohn_read_json_file(brohn_object_path(store,ready$body$result_object$hash))
  check("complete export points to the same original and dataset",envelope$dataset$id==dataset$id&&envelope$dataset$source$hash==hash)
  check("only successful committed originals release intake guards",identical(brohn_reap_ingestion_guards(store),record$id)&&!exists(.brohn_ingestion_key(store,record$id),envir=.brohn_ingestion_sources,inherits=FALSE))
  check("completed dataset cannot be cancelled",rejects(brohn_cancel_ingestion(store,record$id,ready$revision)))
  brohn_close_store(store);store<-brohn_open_store(file.path(root,"workspace"))
  check("reopened catalog retains dataset and full source",brohn_get_entity(store,"dataset",dataset$id)$body$source$hash==hash&&file.exists(brohn_object_path(store,hash)))
  cancellation<-queue(upload("x,y\n0,1\n"));cancelled<-brohn_cancel_ingestion(store,cancellation$id,cancellation$revision)
  check("cancelled intake retains original and no dataset",file.exists(cancelled$body$source_snapshot$path)&&is.null(cancelled$body$dataset_id))
  retried<-brohn_retry_ingestion(store,cancellation$id,cancelled$revision,"explicit-retry")
  check("retry keeps exact source and frozen metadata with new job",retried$body$job_id!=cancelled$body$job_id&&retried$body$review_hash==cancelled$body$review_hash&&length(retried$body$attempts)==2L)
  check("retry operation is idempotent",identical(brohn_retry_ingestion(store,cancellation$id,cancelled$revision,"explicit-retry")$body$job_id,retried$body$job_id))
  p<-process(retried);brohn_cancel_ingestion(store,retried$id,retried$revision)
  check("cancel after worker completion refuses all publication",rejects(publish(p))&&is.null(brohn_get_entity(store,"dataset",paste0("dataset-",retried$id))))
  malformed<-queue(upload("x,x\n0,1\n"));job<-brohn_claim_job(store,"malformed",60);input<-brohn_ingestion_input(store,job)
  scratch<-tempfile("bad-preview-",tmpdir=store$root);dir.create(scratch)
  check("ambiguous columns reject before dataset publication",rejects(brohn_analyse_ingestion(input,scratch)))
  brohn_fail_job(store,job$id,job$worker,job$token,list(message="Ambiguous original columns"))
  check("failed preview remains explicit with original retained",brohn_ingestion(store,malformed$id)$body$effective_status=="failed"&&file.exists(input$source_snapshot$path))
  # Another process owns this source: a restart before native handoff must not
  # silently bless an un-hashed file merely because its size/path still match.
  owner_root<-file.path(root,"owner-workspace");owner_store<-brohn_open_store(owner_root);brohn_initialise_library(owner_store);brohn_close_store(owner_store)
  ready_path<-file.path(root,"owner-ready.json")
  child<-processx::process$new(brohn_rscript(),c("--vanilla","tests/fixtures/platform-ingestion-child.R","owner",owner_root,ready_path,as.character(1024^2)),
    env=c("current",R_LIBS_USER=paste(.libPaths(),collapse=.Platform$path.sep)),stdout=file.path(root,"owner-out.txt"),stderr=file.path(root,"owner-err.txt"),cleanup_tree=TRUE,windows_hide_window=TRUE)
  children<-c(children,list(child));deadline<-as.numeric(Sys.time())+20
  while(!file.exists(ready_path)&&child$is_alive()&&as.numeric(Sys.time())<deadline)child$wait(20)
  if(!file.exists(ready_path))stop(paste(readLines(file.path(root,"owner-err.txt"),warn=FALSE),collapse="\n"))
  owner_record<-brohn_read_json_file(ready_path);child$kill_tree();child$wait(2000)
  owner_store<-brohn_open_store(owner_root);owner_job<-brohn_claim_job(owner_store,"after-owner-exit",60)
  check("actual owner exit rejects pre-hash worker handoff",rejects(brohn_ingestion_input(owner_store,owner_job)))
  check("actual owner exit leaves incoming bytes intact",file.exists(brohn_get_entity(owner_store,"ingestion",owner_record$id)$body$source_snapshot$path))
  brohn_fail_job(owner_store,owner_job$id,owner_job$worker,owner_job$token,list(message="Original owner exited"));brohn_close_store(owner_store)
  stale<-queue(upload("a,b\n1,0\n"));p<-process(stale)
  DBI::dbExecute(store$con,"UPDATE jobs SET lease_until=0 WHERE id=?",params=list(p$job$id))
  replacement<-brohn_claim_job(store,"replacement-intake",60)
  check("reclaimed attempt rejects old publication without a dataset",replacement$id==p$job$id&&replacement$token!=p$job$token&&rejects(publish(p))&&is.null(brohn_get_entity(store,"dataset",paste0("dataset-",stale$id))))
  brohn_cancel_ingestion(store,stale$id,stale$revision)
  bound<-queue(upload("a,b\n1,0\n"));p<-process(bound);changed<-brohn_get_entity(store,"ingestion",bound$id)
  changed$body$review$origin<-"live";brohn_put_entity(store,"ingestion",bound$id,changed$body,changed$revision,changed$project_id)
  check("review mutation cannot relabel origin at publication",rejects(publish(p))&&is.null(brohn_get_entity(store,"dataset",paste0("dataset-",bound$id))))
  brohn_fail_job(store,p$job$id,p$job$worker,p$job$token,list(message="Original reviewed origin changed"))
  collision<-queue(upload("unique_original,value\n887,1\n"));p<-process(collision)
  brohn_put_entity(store,"dataset",paste0("dataset-",collision$id),list(marker="Original deliberate collision"))
  before_objects<-as.integer(DBI::dbGetQuery(store$con,"SELECT count(*) AS n FROM objects")$n)
  check("final dataset conflict rolls back original and document registrations",rejects(publish(p))&&
    as.integer(DBI::dbGetQuery(store$con,"SELECT count(*) AS n FROM objects")$n)==before_objects&&
    nrow(.brohn_store_object_row(store,p$output$report$ingestion$source$hash))==0L)
  check("publication rollback preserves pending history job and original",brohn_get_entity(store,"ingestion",collision$id)$revision==collision$revision&&
    brohn_get_job(store,p$job$id)$status=="running"&&file.exists(collision$body$source_snapshot$path))
  brohn_cancel_ingestion(store,collision$id,collision$revision)
  outside<-file.path(root,"outside-this-session.txt");writeLines("a",outside)
  # A format rejection and supplied size disagreement happen before consuming it.
  check("unknown format preserves completed temp upload",rejects(queue(upload("a","original.unsupported"))))
  wrong<-upload("a,b\n1,0\n");wrong$size<-wrong$size+1
  check("supplied byte count mismatch preserves upload",rejects(queue(wrong))&&file.exists(wrong$path))
  # Simulate only the initial rename failing; catalog file operations retain
  # their production implementations in their own function environments.
  fail_move <- brohn_queue_ingestion
  environment(fail_move) <- list2env(list(file.rename = function(from, to) FALSE), parent = environment(brohn_queue_ingestion))
  not_moved <- upload("uncaptured,value\n1,0\n"); failed_operation <- brohn_id("capture-failure")
  check("failed initial rename leaves the completed server transfer intact", rejects(fail_move(store, not_moved,
    "Original failed move", "temperature", "sample", operation_id = failed_operation)) && file.exists(not_moved$path))
  failure_id <- paste0("ingestion-", substr(brohn_hash(list(project_id = "default", operation_id = failed_operation)), 1, 32))
  failure <- brohn_get_entity(store, "ingestion", failure_id)
  check("capture failure never claims an incoming original exists", failure$body$status == "needs_attention" &&
    identical(failure$body$incoming_file_present, FALSE) && is.null(failure$body$source_snapshot) && is.null(failure$body$job_id) &&
    grepl("could not be captured", failure$body$error, fixed = TRUE))
  # Exercise receipt arrival during process inspection with the actual sealed
  # helper. Advance only the polling clock, not the process/file validators.
  racing_hold <- .brohn_ingestion_hold
  clock_calls <- 0L; observed_receipt <- FALSE; forced_initial_poll <- FALSE; clock_start <- Sys.time()
  racing_env <- new.env(parent=environment(racing_hold))
  racing_env$Sys.time <- function(){clock_calls<<-clock_calls+1L;clock_start+if(clock_calls==1L)0 else 20}
  racing_env$file.exists <- function(path){
    if(identical(basename(path),"snapshot-receipt.json")&&!forced_initial_poll){forced_initial_poll<<-TRUE;return(FALSE)}
    file.exists(path)
  }
  racing_env$.brohn_publication_observe_guard <- function(h){
    .brohn_publication_observe_guard(h)
    ready <- h$args[[match("--receipt",h$args)+1L]];until <- Sys.time()+5
    while(!file.exists(ready)&&h$child$is_alive()&&Sys.time()<until)h$child$wait(10)
    observed_receipt<<-file.exists(ready)
  }
  environment(racing_hold)<-racing_env
  racing_queue<-brohn_queue_ingestion
  environment(racing_queue)<-list2env(list(.brohn_ingestion_hold=racing_hold),parent=environment(racing_queue))
  raced<-racing_queue(store,upload("sample,value\n0,1\n"),"Ready during inspection","temperature","sample",operation_id="receipt-during-inspection")
  check("actual sealed receipt arriving during inspection wins over stale wait clock",forced_initial_poll&&observed_receipt&&raced$body$status=="queued"&&clock_calls==1L)
  check("readiness race preserves the original native read seal",suppressWarnings(rejects({con<-file(raced$body$source_snapshot$path,"r+b");close(con)})))
  brohn_cancel_ingestion(store,raced$id,raced$revision)
  cat(checks," ingestion checks passed; metadata-only queue ",sprintf("%.3f",queue_seconds)," seconds\n",sep="")
})
