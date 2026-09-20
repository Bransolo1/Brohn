# Pending source intake is separate from complete datasets. No shared worker or
# UI hook is installed by sourcing this module.
# R options are process-scoped. A second loader environment must retain the
# same external pointers instead of losing them while the recorded PID lives.
.brohn_ingestion_sources<-getOption("brohn.ingestion.source_guards")
if(is.null(.brohn_ingestion_sources)) {
  .brohn_ingestion_sources<-new.env(parent=emptyenv())
  options(brohn.ingestion.source_guards=.brohn_ingestion_sources)
}
stopifnot(is.environment(.brohn_ingestion_sources))
.brohn_ingestion_key<-function(store,id)paste0(store$workspace_id,":",id)
.brohn_ingestion_module_hash<-digest::digest(file="R/platform-ingestion.R",algo="sha256")
.brohn_ingestion_snapshot_script<-normalizePath("scripts/workers/ingestion_snapshot.py",winslash="/",mustWork=TRUE)
.brohn_ingestion_snapshot_hash<-digest::digest(file=.brohn_ingestion_snapshot_script,algo="sha256")

.brohn_ingestion_owner <- function() {
  process<-ps::ps_handle(Sys.getpid())
  list(pid=Sys.getpid(),created=sprintf("%.6f",as.numeric(ps::ps_create_time(process))),
    executable=ps::ps_exe(process),command_hash=brohn_hash(as.list(ps::ps_cmdline(process))))
}
.brohn_ingestion_owner_alive <- function(owner) tryCatch({
  process<-ps::ps_handle(as.integer(owner$pid),as.POSIXct(as.numeric(owner$created),origin="1970-01-01",tz="UTC"))
  isTRUE(ps::ps_is_running(process)) && abs(as.numeric(ps::ps_create_time(process))-as.numeric(owner$created))<.001 &&
    identical(ps::ps_exe(process),owner$executable) && identical(brohn_hash(as.list(ps::ps_cmdline(process))),owner$command_hash)
},error=function(e)FALSE)

.brohn_ingestion_snapshot_stop <- function(handle) {
  .brohn_publication_observe_guard(handle)
  if(handle$child$is_alive()){handle$child$kill_tree();handle$child$wait(2000)}
  # An exited Windows venv launcher is not proof its remembered interpreter
  # exited. Only the exact PID/creation/argv child can be stopped here.
  probe<-.brohn_publication_probe_guard(handle)
  if(identical(probe,"owned_alive")) {
    process<-ps::ps_handle(handle$guard_pid,as.POSIXct(handle$guard_created,origin="1970-01-01",tz="UTC"))
    ps::ps_kill(process);deadline<-as.numeric(Sys.time())+2
    repeat {probe<-.brohn_publication_probe_guard(handle);if(probe!="owned_alive"||as.numeric(Sys.time())>=deadline)break;Sys.sleep(.01)}
  }
  !handle$child$is_alive()&&identical(probe,"absent")
}

.brohn_ingestion_hold <- function(store,id,path,size) {
  brohn_require(.Platform$OS.type=="windows","Fast guarded upload intake is initially qualified on Windows only.")
  brohn_require(identical(digest::digest(file=.brohn_ingestion_snapshot_script,algo="sha256"),.brohn_ingestion_snapshot_hash),"Restart intake after snapshot helper changes.")
  native<-.brohn_publication_native();directory<-dirname(path)
  request_path<-file.path(directory,"snapshot-request.json");receipt_path<-file.path(directory,"snapshot-receipt.json")
  nonce<-brohn_token();request<-list(schema="brohn-ingestion-snapshot-request/1.0",workspace_root=store$root,workspace_id=store$workspace_id,
    ingestion_id=id,source_path=path,bytes=as.numeric(size),nonce=nonce)
  .brohn_publication_write(request,request_path)
  request_hash<-digest::digest(file=request_path,algo="sha256")
  h<-new.env(parent=emptyenv());h$args<-c(.brohn_ingestion_snapshot_script,"--request",request_path,"--receipt",receipt_path)
  h$guard_owned<-FALSE;h$pointer<-NULL
  h$child<-processx::process$new(.brohn_publication_python(),h$args,stdin="|",stdout=file.path(directory,"snapshot-stdout.txt"),
    stderr=file.path(directory,"snapshot-stderr.txt"),cleanup_tree=TRUE,windows_hide_window=TRUE)
  h$pid<-h$child$get_pid();h$created<-as.numeric(ps::ps_create_time(ps::ps_handle(h$pid)))
  success<-FALSE
  on.exit({
    .brohn_ingestion_snapshot_stop(h)
    if(!success&&!is.null(h$pointer)).Call(native$close,h$pointer)
  },add=TRUE)
  deadline<-as.numeric(Sys.time())+10
  while(!file.exists(receipt_path)) {
    .brohn_publication_observe_guard(h)
    # Process-tree inspection can outlast the helper's small metadata handoff.
    # Recheck readiness before applying the wait deadline; the receipt still
    # undergoes the complete nonce, request, process and native identity checks.
    if(file.exists(receipt_path))break
    brohn_require(h$child$is_alive() && as.numeric(Sys.time())<deadline,"The metadata-only upload snapshot did not become ready within ten seconds.")
    h$child$wait(10)
  }
  receipt<-.brohn_publication_read(receipt_path)
  brohn_require(identical(receipt$schema,"brohn-ingestion-snapshot-ready/1.0") && identical(receipt$request_sha256,request_hash) &&
    identical(receipt$nonce,nonce) && identical(receipt$workspace_id,store$workspace_id) && isTRUE(receipt$metadata_only) &&
    identical(receipt$source_hash_status,"not_yet_computed") && receipt$file_identity$bytes==size,"The upload snapshot receipt changed its request or source identity.")
  if(!h$guard_owned){h$guard_pid<-as.integer(receipt$pid);h$guard_created<-as.numeric(ps::ps_create_time(ps::ps_handle(h$guard_pid)))}
  brohn_require(identical(as.integer(receipt$pid),as.integer(h$guard_pid)) && .brohn_publication_guard(h),"Upload snapshot is not held by this exact owned helper.")
  h$guard_owned<-TRUE
  identity<-receipt$file_identity
  h$pointer<-.Call(native$open,path,identity$volume,identity$file_index,sprintf("%.0f",size))
  brohn_require(.brohn_publication_guard(h),"Upload snapshot helper exited before the parent acquired its own guard.")
  h$child$write_input(paste0(brohn_json(list(operation="release_snapshot",nonce=nonce,request_sha256=request_hash)),"\n"))
  h$child$wait(2000)
  brohn_require(!h$child$is_alive() && identical(h$child$get_exit_status(),0L)&&.brohn_ingestion_snapshot_stop(h),"Upload snapshot helper did not release normally.")
  held<-new.env(parent=emptyenv());held$pointer<-h$pointer;held$native<-native;held$ingestion_id<-id;held$workspace_id<-store$workspace_id
  held$source<-list(path=path,file_identity=identity,owner=.brohn_ingestion_owner(),nonce=nonce,
    snapshot_request_hash=request_hash,snapshot_helper_hash=.brohn_ingestion_snapshot_hash,hash_status="pending_worker_hash")
  key<-.brohn_ingestion_key(store,id)
  brohn_require(!exists(key,envir=.brohn_ingestion_sources,inherits=FALSE),"This workspace already retains an original guard for that intake operation.")
  assign(key,held,envir=.brohn_ingestion_sources);success<-TRUE;held
}

.brohn_ingestion_record <- function(store,id) {
  record<-brohn_get_entity(store,"ingestion",id)
  brohn_require(!is.null(record),"This pending source import is unavailable.");record
}
brohn_ingestion <- function(store,id) {
  record<-.brohn_ingestion_record(store,id)
  job<-if(!is.null(record$body$job_id))brohn_get_job(store,record$body$job_id) else NULL
  record$body$effective_status<-if(!is.null(job)&&job$status%in%c("failed","cancelled"))job$status else
    if(is.null(job)&&identical(record$body$status,"capturing_upload")&&!.brohn_ingestion_owner_alive(record$body$capture_owner))"needs_attention" else
    if(!is.null(job)&&job$status=="queued"&&!.brohn_ingestion_owner_alive(record$body$source_snapshot$owner))"needs_attention" else
      if(!is.null(job)&&job$status=="running")"preserving_source" else record$body$status
  record$body$job_error<-job$error;record
}
brohn_ingestions <- function(store,project_id=NULL,limit=100L) {
  lapply(brohn_list_entities(store,"ingestion",project_id,limit),function(record)brohn_ingestion(store,record$id))
}

brohn_queue_ingestion <- function(store,upload,title,modality,origin,study_id=NULL,project_id="default",operation_id) {
  brohn_require(!RSQLite::sqliteIsTransacting(store$con),"Queue source intake outside an enclosing transaction.")
  brohn_fields(upload,c("path","name","size","reference"),label="Completed server upload")
  brohn_require(brohn_text(upload$name,240) && identical(basename(upload$name),upload$name) && brohn_number(upload$size,1,512*1024^2,TRUE) &&
    brohn_text(upload$reference,256) && brohn_text(title,240) && brohn_text(operation_id,256),"Choose a complete upload, stable upload reference and source title.")
  formats<-brohn_dataset_formats();format<-tolower(tools::file_ext(upload$name))
  brohn_require(format%in%names(formats),"This uploaded file format has no registered preservation route.")
  brohn_require(modality%in%c("gaze","prepared_gaze","eda","eeg","ecg","ppg","respiration","emg","eog","fnirs","temperature","movement","audio","video","implicit","questionnaire","maxdiff","multimodal") &&
    origin%in%c("imported","sample","pilot","live"),"Declare the source data family and collection origin.")
  brohn_project(store,project_id)
  study<-if(is.null(study_id))NULL else brohn_study(store,study_id)
  brohn_require(is.null(study)||(!isTRUE(study$body$archived)&&identical(study$project_id,project_id)),"Choose an available study in this project.")
  review<-list(title=title,modality=modality,origin=origin,project_id=project_id,study_id=study_id,study_revision=study$revision,
    study_hash=if(is.null(study))NULL else brohn_hash(study$body),filename=upload$name,format=format,size=as.numeric(upload$size),upload_reference=upload$reference)
  id<-paste0("ingestion-",substr(brohn_hash(list(project_id=project_id,operation_id=operation_id)),1,32))
  previous<-brohn_get_entity(store,"ingestion",id)
  if(!is.null(previous)) {
    brohn_require(identical(previous$body$review_hash,brohn_hash(review)),"This import operation already refers to a different upload or reviewed destination.")
    return(brohn_ingestion(store,id))
  }
  path<-normalizePath(upload$path,winslash="/",mustWork=TRUE)
  temporary_root<-normalizePath(tempdir(),winslash="/",mustWork=TRUE)
  brohn_require(startsWith(tolower(path),paste0(tolower(temporary_root),"/")) && !dir.exists(path) && file.info(path)$size==upload$size,
    "Intake accepts only this server's completed temporary upload; the original local file is not moved.")
  brohn_require(.Platform$OS.type=="windows" && grepl("^[A-Za-z]:/",path) &&
    identical(tolower(substr(path,1,2)),tolower(substr(store$root,1,2))),
    "This initial fast intake route requires upload and workspace on the same Windows volume; a cross-volume asynchronous transfer is not yet installed.")
  incoming<-file.path(store$root,"incoming");dir.create(incoming,showWarnings=FALSE)
  incoming<-.brohn_store_contained(store,incoming);directory<-file.path(incoming,id)
  brohn_require(!dir.exists(directory)&&dir.create(directory),"Cannot create a private incoming source directory.")
  directory<-.brohn_store_contained(store,directory);destination<-file.path(directory,"original.upload")
  body<-list(schema="brohn-ingestion/1.0",id=id,status="capturing_upload",review=review,review_hash=brohn_hash(review),
    incoming_directory=directory,job_id=NULL,dataset_id=NULL,source_snapshot=NULL,capture_owner=.brohn_ingestion_owner(),created_at=brohn_now(),attempts=list())
  record<-brohn_put_entity(store,"ingestion",id,body,project_id=project_id)
  held<-NULL;success<-FALSE
  on.exit(if(!success){
    if(!is.null(held)){.Call(held$native$close,held$pointer);key<-.brohn_ingestion_key(store,id);if(exists(key,envir=.brohn_ingestion_sources,inherits=FALSE))rm(list=key,envir=.brohn_ingestion_sources)}
    try({body$status<-"needs_attention";body$incoming_file_present<-file.exists(destination)
      body$error<-if(body$incoming_file_present) "An incoming file is present, but capture did not complete and its bytes have not been verified. Review the original local file and upload it again." else
        "The upload could not be captured into the workspace. Select the original local file and upload it again."
      brohn_put_entity(store,"ingestion",id,body,record$revision,project_id)},silent=TRUE)
  },add=TRUE)
  # Both paths are resolved; only the completed temporary server upload moves.
  brohn_require(!file.exists(destination)&&file.rename(path,destination),"The completed upload could not move into the workspace without a large blocking copy.")
  destination<-.brohn_store_contained(store,destination)
  held<-.brohn_ingestion_hold(store,id,destination,upload$size)
  job_id<-.brohn_store_id(store$con,"job")
  request<-list(ingestion_id=id,review_hash=body$review_hash,source_snapshot_hash=brohn_hash(held$source),project_id=project_id,recipe="source-preservation/1.0")
  queued<-brohn_store_batch(store,function(){
    job<-brohn_enqueue_job(store,"ingest_source",request,paste0("ingestion:",id),prepared_id=job_id)
    brohn_require(identical(job$id,job_id),"The queued import differs from this captured source operation.")
    body$status<-"queued";body$source_snapshot<-held$source;body$job_id<-job$id;body$attempts<-list(list(job_id=job$id,queued_at=brohn_now()))
    brohn_put_entity(store,"ingestion",id,body,record$revision,project_id)
  })
  held$job_id<-job_id;success<-TRUE;brohn_ingestion(store,id)
}

brohn_cancel_ingestion <- function(store,id,expected_revision) {
  brohn_store_batch(store,function(){
    record<-.brohn_ingestion_record(store,id)
    brohn_require(identical(record$revision,as.integer(expected_revision)) && !is.null(record$body$job_id),"Review the current pending import before cancelling it.")
    current<-brohn_get_job(store,record$body$job_id)
    brohn_require(current$status%in%c("queued","running","cancelled") && is.null(record$body$dataset_id),"This import has already finished; its saved dataset cannot be cancelled.")
    job<-brohn_cancel_job(store,record$body$job_id)
    body<-record$body;body$status<-"cancelled";body$cancelled_at<-brohn_now()
    brohn_put_entity(store,"ingestion",id,body,record$revision,record$project_id)
  })
}

brohn_retry_ingestion <- function(store,id,expected_revision,operation_id) {
  brohn_require(brohn_text(operation_id,256),"Retry needs its own stable operation identifier.")
  record<-.brohn_ingestion_record(store,id)
  previous<-Filter(function(a)identical(a$retry_operation_id,operation_id),record$body$attempts)
  if(length(previous))return(brohn_ingestion(store,id))
  brohn_require(identical(record$revision,as.integer(expected_revision)),"Review the current import before retrying it.")
  job<-brohn_get_job(store,record$body$job_id)
  brohn_require(!is.null(job)&&job$status%in%c("failed","cancelled")&&is.null(record$body$dataset_id),"Only a failed or cancelled pending import can be retried.")
  key<-.brohn_ingestion_key(store,id)
  brohn_require(exists(key,envir=.brohn_ingestion_sources,inherits=FALSE),"The original upload guard is unavailable. Keep the preserved incoming file and explicitly upload a reviewed source again.")
  held<-get(key,envir=.brohn_ingestion_sources,inherits=FALSE)
  brohn_require(identical(held$workspace_id,store$workspace_id)&&identical(brohn_hash(held$source),brohn_hash(record$body$source_snapshot))&&
    .brohn_ingestion_owner_alive(held$source$owner),"The original source ownership changed; explicitly review and upload it again.")
  .Call(held$native$check,held$pointer)
  brohn_store_batch(store,function(){
    current<-.brohn_ingestion_record(store,id)
    brohn_require(identical(current$revision,record$revision),"The pending import changed during retry.")
    next_job<-brohn_enqueue_job(store,"ingest_source",job$request,paste0("ingestion-retry:",id,":",operation_id))
    body<-current$body;body$status<-"queued";body$job_id<-next_job$id
    body$attempts<-c(body$attempts,list(list(job_id=next_job$id,previous_job_id=job$id,retry_operation_id=operation_id,queued_at=brohn_now())))
    brohn_put_entity(store,"ingestion",id,body,current$revision,current$project_id)
  })
  held$job_id<-brohn_get_entity(store,"ingestion",id)$body$job_id
  brohn_ingestion(store,id)
}

# Only a fully committed original has an independent cryptographic identity.
# Cancelled/failed pre-hash originals remain held for an explicit same-process
# retry. Process exit releases OS handles, but never deletes incoming bytes.
brohn_reap_ingestion_guards <- function(store) {
  released<-character()
  for(key in ls(.brohn_ingestion_sources,all.names=TRUE)) {
    held<-get(key,envir=.brohn_ingestion_sources,inherits=FALSE)
    if(!identical(held$workspace_id,store$workspace_id))next
    id<-held$ingestion_id
    record<-brohn_get_entity(store,"ingestion",id)
    if(is.null(record)||!identical(record$body$status,"ready")||is.null(record$body$dataset_id))next
    job<-brohn_get_job(store,record$body$job_id)
    if(!identical(job$status,"succeeded"))next
    .Call(held$native$close,held$pointer);rm(list=key,envir=.brohn_ingestion_sources);released<-c(released,id)
  }
  invisible(released)
}

.brohn_ingestion_pin <- function(store,job) {
  .brohn_publication_job(store,job);r<-job$request
  brohn_require(identical(job$operation,"ingest_source"),"This is not a pending source import job.")
  record<-.brohn_ingestion_record(store,r$ingestion_id);body<-record$body
  brohn_require(identical(body$job_id,job$id)&&identical(body$status,"queued")&&is.null(body$dataset_id)&&
    identical(record$project_id,r$project_id)&&identical(body$review_hash,r$review_hash)&&
    identical(brohn_hash(body$review),r$review_hash)&&identical(brohn_hash(body$source_snapshot),r$source_snapshot_hash)&&
    identical(r$recipe,"source-preservation/1.0"),"This import attempt differs from its frozen source and reviewed destination.")
  if(!is.null(body$review$study_id)) {
    study<-brohn_study(store,body$review$study_id,body$review$study_revision)
    brohn_require(identical(study$project_id,record$project_id)&&identical(brohn_hash(study$body),body$review$study_hash),"The reviewed study revision failed its integrity check.")
  }
  record
}

brohn_ingestion_input <- function(store,job) {
  record<-.brohn_ingestion_pin(store,job)
  snapshot<-record$body$source_snapshot
  path<-.brohn_store_contained(store,snapshot$path)
  expected<-file.path(store$root,"incoming",record$id,"original.upload")
  brohn_require(identical(path,normalizePath(expected,winslash="/",mustWork=TRUE))&&
    .brohn_ingestion_owner_alive(snapshot$owner),"The original upload owner stopped before worker handoff. Keep the source and explicitly review/upload it again.")
  list(schema="brohn-analysis-input/1.0",operation="ingest_source",workspace_root=store$root,workspace_id=store$workspace_id,
    ingestion_id=record$id,ingestion_revision=record$revision,project_id=record$project_id,
    review=record$body$review,review_hash=record$body$review_hash,source_snapshot=snapshot,source_snapshot_hash=job$request$source_snapshot_hash,
    media_type=unname(brohn_dataset_formats()[[record$body$review$format]]),recipe=job$request$recipe)
}

brohn_analyse_ingestion <- function(input,scratch) {
  brohn_require(identical(input$operation,"ingest_source")&&identical(input$recipe,"source-preservation/1.0")&&
    identical(brohn_hash(input$review),input$review_hash)&&identical(brohn_hash(input$source_snapshot),input$source_snapshot_hash),"Invalid frozen source intake input.")
  path<-.brohn_store_contained(list(root=input$workspace_root),input$source_snapshot$path)
  brohn_require(identical(path,normalizePath(file.path(input$workspace_root,"incoming",input$ingestion_id,"original.upload"),winslash="/",mustWork=TRUE)),"The source is outside its exact incoming operation.")
  native<-.brohn_publication_native();identity<-input$source_snapshot$file_identity
  pointer<-.Call(native$open,path,identity$volume,identity$file_index,sprintf("%.0f",input$review$size))
  on.exit(.Call(native$close,pointer),add=TRUE)
  brohn_require(.brohn_ingestion_owner_alive(input$source_snapshot$owner),"The original source owner exited before guarded worker handoff; the retained file requires explicit review.")
  milestone<-function(name,details=list()) {
    directory<-.brohn_store_contained(list(root=input$workspace_root),scratch)
    destination<-file.path(directory,paste0("ingestion-",name,".json"))
    pending<-tempfile(".ingestion-status-",tmpdir=directory)
    brohn_write_json_file(c(list(schema="brohn-ingestion-progress/1.0",ingestion_id=input$ingestion_id,
      source_snapshot_hash=input$source_snapshot_hash,stage=name,at=brohn_now()),details),pending)
    brohn_require(!file.exists(destination)&&file.rename(pending,destination),"Cannot record this worker's completed intake stage.")
  }
  milestone("hashing")
  # This is the first full hash. The parent guard and then this own native guard
  # cover its entire pre-hash interval; no inference from mtime or permissions.
  hash<-digest::digest(file=path,algo="sha256")
  milestone("preview",list(source_hash=hash))
  columns<-list();preview<-list()
  if(input$review$format%in%c("csv","tsv")) {
    table<-utils::read.table(path,header=TRUE,sep=if(input$review$format=="csv")"," else "\t",nrows=20,
      colClasses="character",check.names=FALSE,comment.char="",quote="\"",fileEncoding="UTF-8",na.strings=character(),blank.lines.skip=FALSE)
    brohn_require(ncol(table)>0&&ncol(table)<=1024&&!anyDuplicated(names(table))&&all(nzchar(names(table))),"Data columns must have unique nonempty names.")
    columns<-as.list(names(table));preview<-lapply(seq_len(nrow(table)),function(i)as.list(table[i,,drop=FALSE]))
  }
  .Call(native$check,pointer)
  result<-list(kind="source_ingestion",title=input$review$title,ingestion=list(schema="brohn-ingestion-result/1.0",ingestion_id=input$ingestion_id,
    review_hash=input$review_hash,source_snapshot_hash=input$source_snapshot_hash,source=list(path=path,hash=hash,size=input$review$size,
      media_type=input$media_type,filename=input$review$filename,format=input$review$format),columns=columns,preview=preview,
    source_preservation="whole_original",scientific_interpretation="not_performed",preview_rows=length(preview),guard_handoff="parent-and-worker-native-read-seal/1.0"))
  brohn_require(nchar(brohn_json(result),type="bytes")<=8*1024^2,"The source preview is too large for the bounded intake receipt; retain and review the original source.")
  milestone("verified",list(source_hash=hash,preview_rows=length(preview)))
  result
}

brohn_publish_ingestion <- function(store,output,scratch,job,input,output_path) {
  brohn_require(!RSQLite::sqliteIsTransacting(store$con),"Prepare source intake publication outside a transaction.")
  .brohn_publication_output_identity(output,list("R/platform-ingestion.R"=.brohn_ingestion_module_hash,
    "scripts/workers/ingestion_snapshot.py"=.brohn_ingestion_snapshot_hash))
  record<-.brohn_ingestion_pin(store,job);r<-output$report$ingestion;review<-record$body$review
  brohn_require(identical(input$ingestion_revision,record$revision)&&identical(brohn_hash(input$review),record$body$review_hash)&&
    identical(input$source_snapshot_hash,job$request$source_snapshot_hash)&&identical(r$schema,"brohn-ingestion-result/1.0")&&
    identical(r$ingestion_id,record$id)&&identical(r$review_hash,record$body$review_hash)&&identical(r$source_snapshot_hash,job$request$source_snapshot_hash)&&
    identical(r$source_preservation,"whole_original")&&identical(r$scientific_interpretation,"not_performed")&&
    identical(r$guard_handoff,"parent-and-worker-native-read-seal/1.0")&&brohn_array(r$columns)&&brohn_array(r$preview)&&length(r$preview)<=20&&
    identical(r$source$path,record$body$source_snapshot$path)&&identical(as.numeric(r$source$size),as.numeric(review$size))&&
    identical(r$source$filename,review$filename)&&identical(r$source$format,review$format)&&identical(r$source$media_type,unname(brohn_dataset_formats()[[review$format]])),
    "The intake output changed its reviewed source, preview contract or destination.")
  brohn_require(all(vapply(r$columns,brohn_text,logical(1),max=10000))&&!anyDuplicated(unlist(r$columns))&&
    all(vapply(r$preview,function(row)is.list(row)&&setequal(names(row),unlist(r$columns))&&!anyDuplicated(names(row))&&all(vapply(row,brohn_text,logical(1),max=8*1024^2,empty=TRUE)),logical(1))),
    "The source preview has inconsistent columns or unpreserved typed text.")
  spec<-list(key="original-source",kind="original-source",path=r$source$path,sha256=r$source$hash,bytes=r$source$size,media_type=r$source$media_type)
  artifacts<-.brohn_publication_stage(store,job,list(spec));document<-NULL;committed<-FALSE
  on.exit({if(!is.null(document))brohn_close_publication(document$guard,committed);brohn_close_publication(artifacts$guard,committed)},add=TRUE)
  object<-artifacts$descriptors[[1]][c("hash","size","media_type")]
  dataset_id<-paste0("dataset-",record$id)
  processing<-list(job_id=job$id,attempt=job$attempt,recipe=input$recipe,request_hash=brohn_hash(input),
    worker_output_hash=digest::digest(file=output_path,algo="sha256"),code_hashes=output$code_identity,publication=.brohn_publication_processing(artifacts))
  dataset<-list(schema_version="brohn-dataset/1.0.0",id=dataset_id,title=review$title,modality=review$modality,origin=review$origin,
    study_id=review$study_id,study_revision=review$study_revision,source=c(object,list(filename=review$filename,format=review$format)),
    columns=r$columns,preview=r$preview,metadata=list(),status="needs_mapping",data_revision=1L,notes="",
    source_provenance=list(imported_at=brohn_now(),source_hash=object$hash,ingestion_id=record$id,review_hash=record$body$review_hash,
      source_snapshot_hash=job$request$source_snapshot_hash,source_preservation="whole_original",processing=processing))
  body<-record$body;body$status<-"ready";body$dataset_id<-dataset_id;body$source_object<-object;body$completed_at<-brohn_now();body$processing<-processing
  document<-.brohn_publication_stage_json(store,job,list(schema="brohn-ingestion-publication/1.0",ingestion=body,dataset=dataset),file.path(scratch,"published-ingestion.json"))
  receipt<-brohn_store_batch(store,function(){
    current<-.brohn_ingestion_pin(store,job)
    brohn_require(identical(current$revision,record$revision),"Pending intake changed before final publication.")
    .brohn_publication_register(store,artifacts)
    body$result_object<-.brohn_publication_register(store,document)[[1]][c("hash","size","media_type")]
    brohn_put_entity(store,"dataset",dataset_id,dataset,expected_revision=0L,project_id=record$project_id)
    brohn_put_entity(store,"ingestion",record$id,body,record$revision,record$project_id)
    brohn_complete_job(store,job$id,job$worker,job$token,list(ingestion_id=record$id,dataset_id=dataset_id,status="ready",source_hash=object$hash,output_hash=body$result_object$hash))
  })
  committed<-TRUE;receipt
}
