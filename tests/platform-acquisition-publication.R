# Actual Windows processes, native seals and SQLite rollback; no real capture.
source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=FALSE)
local({
  root<-tempfile("brohn-acq-publication-");dir.create(root);root<-normalizePath(root,winslash="/")
  store<-brohn_open_store(file.path(root,"workspace"));brohn_initialise_library(store)
  children<-list();other<-NULL;checks<-0L
  on.exit({
    for(child in children)if(child$is_alive()){child$kill_tree();child$wait(5000)}
    if(!is.null(other))brohn_close_store(other)
    brohn_close_store(store)
    actual<-normalizePath(root,winslash="/",mustWork=FALSE)
    stopifnot(identical(dirname(actual),normalizePath(tempdir(),winslash="/")),startsWith(basename(actual),"brohn-acq-publication-"))
    Sys.chmod(list.files(actual,recursive=TRUE,full.names=TRUE,all.files=TRUE),"0666");unlink(actual,recursive=TRUE,force=TRUE)
  },add=TRUE)
  check<-function(name,ok){if(!isTRUE(ok))stop("Acquisition publication QA: ",name);checks<<-checks+1L;cat("PASS ",name,"\n",sep="")}
  fails<-function(expr)inherits(try(force(expr),silent=TRUE),"try-error")
  wait_ready<-function(child,path,seconds=30){deadline<-as.numeric(Sys.time())+seconds
    while(!file.exists(path)){if(as.numeric(Sys.time())>deadline||!child$is_alive())stop(child$read_all_error());Sys.sleep(.01)}}
  start_child<-function(script,args){child<-processx::process$new(brohn_rscript(),c("--vanilla",script,args),
    env=c("current",R_LIBS_USER=paste(.libPaths(),collapse=.Platform$path.sep)),stdout="|",stderr="|",cleanup_tree=TRUE,windows_hide_window=TRUE)
    children[[length(children)+1L]]<<-child;child}
  study<-brohn_create_study(store,"Original acquisition publication QA");manager<-brohn_acquisition_manager(store)
  original<-function(label,padding=0L) {
    id<-brohn_id("acquisition");parent<-.brohn_acq_path(store,"recordings");if(!dir.exists(parent))dir.create(parent)
    request<-list(schema="brohn-lsl-record-request/1.0",recording_id=id,output_root=parent,lsl_session="original-publication",
      origin="sample",origin_statement="Original synthetic journal fixture; no physical source.",
      identity=list(participant_id="original-person",session_id="original-session"),references=list(study_id=study$id,design_hash=brohn_hash(study$body)),
      streams=list(list(id="eda",uid="original-uid",source_id="original-source",metadata_sha256=strrep("0",64),clock_id="declared-original-clock",
        clock_kind="monotonic",kind="signal",unit_provenance="Original fixture declaration",channels=list(list(id="eda",label="Original EDA",type="EDA",unit="uS",value_type="float64")))),
      limits=list(max_duration_s=5,max_samples=100,max_bytes=1024^2,chunk_samples=32,inlet_buffer=1))
    path<-file.path(root,paste0(label,"-request.json"));ready<-file.path(root,paste0(label,"-ready"));release<-file.path(root,paste0(label,"-release"))
    brohn_write_json_file(request,path)
    child<-processx::process$new(.brohn_acq_python(),c("tests/fixtures/acquisition-publication-original.py",path,ready,release,as.character(padding)),
      stdout="|",stderr="|",cleanup_tree=TRUE,windows_hide_window=TRUE);children[[length(children)+1L]]<<-child
    wait_ready(child,ready);identity<-.brohn_acq_process(child$get_pid());writeLines("release exact source writer",release);child$wait(5000)
    check(paste(label,"original journal writer exited"),identical(child$get_exit_status(),0L)&&identical(.brohn_acq_probe(identity),"absent"))
    brohn_put_entity(store,"acquisition",id,list(id=id,title=label,status="stopping",study_id=study$id,study_revision=study$revision,
      design_hash=brohn_hash(study$body),origin="sample",request=request,request_hash=brohn_hash(request),script_hash=.brohn_acq_hash(.brohn_acq_script()),process=identity),project_id=study$project_id)
  }
  scratch<-function(label){path<-tempfile(paste0(label,"-"),tmpdir=store$root);dir.create(path);path}
  objects<-function()DBI::dbGetQuery(store$con,"SELECT COUNT(*) AS n FROM objects")$n[[1L]]
  record<-original("small")
  # Both queued reservations and expired running reservations remain manager-owned.
  for(op in c("acquisition_preserve","acquisition_prepare")) {
    q<-brohn_enqueue_job(store,op,list(original_fixture=TRUE),paste0("queued-",op))
    check(paste(op,"queued job cannot be stolen"),is.null(brohn_claim_job(store,"generic-worker",60)));brohn_cancel_job(store,q$id)
    j<-.brohn_acq_publication_job(store,record,manager,op)
    DBI::dbExecute(store$con,"UPDATE jobs SET lease_until=? WHERE id=?",params=list(as.numeric(Sys.time())-1,j$id))
    check(paste(op,"expired owner cannot be stolen"),is.null(brohn_claim_job(store,"generic-worker",60))&&fails(.brohn_acq_publication_owner(store,record,manager,j)))
    brohn_cancel_job(store,j$id)
  }
  ordinary<-brohn_enqueue_job(store,"normalise_dataset",list(original_fixture=TRUE),"ordinary-fixture")
  check("ordinary scientific jobs still claim normally",identical(brohn_claim_job(store,"generic-worker",60)$id,ordinary$id));brohn_cancel_job(store,ordinary$id)
  forged<-new.env(parent=emptyenv());for(key in ls(manager))forged[[key]]<-manager[[key]];forged$identity$cwd<-root
  check("same manager ID with substituted process rejected",fails(.brohn_acq_publication_job(store,record,forged,"acquisition_preserve")))
  fenced<-.brohn_acq_publication_job(store,record,manager,"acquisition_preserve");brohn_cancel_job(store,fenced$id)
  check("cancelled exact fence cannot continue",fails(.brohn_acq_publication_checkpoint(store,record,manager,fenced)(TRUE)))
  check("publication refuses enclosing SQL writer transaction",fails(brohn_store_batch(store,function().brohn_acq_publish_preservation(store,record,manager,scratch("nested")))))
  before<-objects();revision<-record$revision
  DBI::dbExecute(store$con,"CREATE TRIGGER original_acquisition_rollback BEFORE INSERT ON entity_versions WHEN NEW.kind='acquisition' BEGIN SELECT RAISE(ABORT,'Original controlled acquisition rollback'); END")
  rollback<-tryCatch(.brohn_acq_publish_preservation(store,record,manager,scratch("rollback")),error=identity)
  DBI::dbExecute(store$con,"DROP TRIGGER original_acquisition_rollback")
  check("archive final SQL failure rolls back object and acquisition metadata",inherits(rollback,"error")&&grepl("Original controlled acquisition rollback",conditionMessage(rollback),fixed=TRUE)&&objects()==before&&brohn_acquisition(store,record$id)$revision==revision&&is.null(brohn_acquisition(store,record$id)$body$original))
  record<-.brohn_acq_publish_preservation(store,record,manager,scratch("preserve"))
  archive_hash<-record$body$original$hash;archive<-brohn_object_path(store,archive_hash)
  check("fresh attempt publishes retained original and result atomically",identical(.brohn_acq_hash(archive),archive_hash)&&
    identical(brohn_get_job(store,record$body$preservation$job_id)$status,"succeeded")&&isTRUE(record$body$preservation$publication$native_seal))
  # Deliberate original-tree damage proves the reviewed import is derived from
  # the registered archive, never silently from a changed live filesystem tree.
  original_path<-.brohn_acq_directory(store,record);writeLines("changed mutable source",file.path(original_path,"request.json"))
  reviewed<-brohn_review_acquisition(store,record$id,record$revision);before<-objects();dataset_count<-length(brohn_list_entities(store,"dataset"))
  dependent_count<-DBI::dbGetQuery(store$con,"SELECT COUNT(*) AS n FROM jobs WHERE operation='normalise_dataset'")$n[[1L]]
  DBI::dbExecute(store$con,"CREATE TRIGGER original_review_rollback BEFORE INSERT ON entity_versions WHEN NEW.kind='acquisition' BEGIN SELECT RAISE(ABORT,'Original controlled review rollback'); END")
  rollback<-tryCatch(.brohn_acq_publish_review(store,reviewed,manager,scratch("review-rollback")),error=identity)
  DBI::dbExecute(store$con,"DROP TRIGGER original_review_rollback")
  check("review rollback includes dataset bundle receipt and dependent job",inherits(rollback,"error")&&grepl("Original controlled review rollback",conditionMessage(rollback),fixed=TRUE)&&objects()==before&&
    length(brohn_list_entities(store,"dataset"))==dataset_count&&DBI::dbGetQuery(store$con,"SELECT COUNT(*) AS n FROM jobs WHERE operation='normalise_dataset'")$n[[1L]]==dependent_count&&
    brohn_acquisition(store,record$id)$revision==reviewed$revision&&is.null(brohn_acquisition(store,record$id)$body$import_job_id))
  prepared<-.brohn_acq_publish_review(store,reviewed,manager,scratch("review"))
  data<-brohn_get_entity(store,"dataset",prepared$body$import_dataset_id);dependent<-brohn_get_job(store,prepared$body$import_job_id)
  check("review succeeds from immutable archive despite mutable tree damage",data$body$origin=="sample"&&identical(data$body$source_provenance$parent_acquisition$original$hash,archive_hash)&&
    identical(.brohn_acq_hash(archive),archive_hash))
  check("atomic dataset revision exactly matches the frozen processing request",identical(data$revision,1L)&&identical(dependent$request$dataset_hash,brohn_hash(data$body))&&
    dependent$request$dataset_revision==data$revision&&dependent$request$source_hash==data$body$source$hash)
  brohn_cancel_job(store,dependent$id)
  # A 128 MiB incompressible incidental original member makes real bulk sealing
  # observable without any artificial timing hook or delay in production code.
  large<-original("bulk",128L);source_file<-file.path(.brohn_acq_directory(store,large),"original-diagnostic.bin");source_hash<-.brohn_acq_hash(source_file)
  d<-brohn_new_design("Original concurrent participant save",id="study-acq-participant")
  for(i in seq_along(d$stimuli))d$stimuli[[i]]$content<-paste("Original concept",i)
  brohn_put_entity(store,"study",d$id,d);deployment<-brohn_publish(store,d$id,origin="sample",quota=1L)
  run<-.brohn_delivery_start(store,deployment$token,list(consented=TRUE,client_id="original-acq-client",operation_id="start",participant_alias=""))
  observer<-function(label,operation,event=FALSE) {
    request<-list(operation=operation,workspace=store$root,publication_operation="acquisition_preserve",acquisition_id=large$id,
      ready=file.path(root,paste0(label,"-observer-ready")),output=file.path(root,paste0(label,"-observer-output")))
    if(event){request$run_id<-run$run_id;request$access_token<-run$access_token;request$event_request<-list(operation_id="original-acq-event",events=list(list(
      sequence=1L,id="original-acq-visibility",type="visibility",step_id=NULL,stimulus_id=NULL,condition_id=NULL,question_id=NULL,phase="setup",
      clock=list(id="browser-monotonic",unit="ms",value="0.000"),payload=list(hidden=FALSE))))}
    path<-file.path(root,paste0(label,"-observer.rds"));saveRDS(request,path)
    child<-start_child("tests/fixtures/acquisition-publication-observer.R",path);wait_ready(child,request$ready)
    list(child=child,request=request)
  }
  seen<-observer("cancel","cancel",TRUE);before<-objects();denied<-fails(.brohn_acq_publish_preservation(store,large,manager,scratch("cancel")))
  seen$child$wait(5000);if(seen$child$get_exit_status()!=0L)stop(seen$child$read_all_error());cancel<-readRDS(seen$request$output)
  check("participant receiver writes during actual bulk archive sealing",cancel$http_status==200L&&cancel$response$acked_sequence==1L&&cancel$writer_seconds<5&&
    cancel$phase %in% c("copying","verifying_sealed_bytes"))
  check("other-process cancellation stops archive publication with source retained",denied&&objects()==before&&brohn_get_job(store,cancel$job_id)$status=="cancelled"&&
    is.null(brohn_acquisition(store,large$id)$body$original)&&identical(.brohn_acq_hash(source_file),source_hash))
  again<-.brohn_delivery_receive(store,run$run_id,run$access_token,seen$request$event_request)
  check("concurrent participant receipt remains exactly idempotent",again$acked_sequence==1L&&length(brohn_run_events(store,run$run_id))==1L)
  seen<-observer("stale","stale");stale_result<-tryCatch(.brohn_acq_publish_preservation(store,large,manager,scratch("stale")),error=identity)
  denied<-inherits(stale_result,"error")
  seen$child$wait(5000);if(seen$child$get_exit_status()!=0L)stop(seen$child$read_all_error());stale<-readRDS(seen$request$output)
  cat("Stale evidence: ",brohn_json(list(denied=denied,error=if(denied)conditionMessage(stale_result) else NULL,
    objects=objects(),before=before,current_revision=brohn_acquisition(store,large$id)$revision,observed_revision=stale$revision,
    original_absent=is.null(brohn_acquisition(store,large$id)$body$original),source_equal=identical(.brohn_acq_hash(source_file),source_hash))),"\n",sep="")
  check("concurrent acquisition revision fences off old prepared bytes",denied&&objects()==before&&brohn_acquisition(store,large$id)$revision==stale$revision&&
    is.null(brohn_acquisition(store,large$id)$body$original)&&identical(.brohn_acq_hash(source_file),source_hash))
  # A real killed manager retains its publication request. Only a new verified
  # owner may cancel that attempt and make a new, differently fenced job.
  other<-brohn_open_store(file.path(root,"recovery"));brohn_initialise_library(other)
  recovery_study<-brohn_create_study(other,"Original owner crash")
  recovery<-brohn_put_entity(other,"acquisition","acquisition-owner-crash",list(id="acquisition-owner-crash",status="attention_required"),project_id=recovery_study$project_id)
  request<-list(operation="hold-owner",workspace=other$root,acquisition_id=recovery$id,ready=file.path(root,"owner-ready"),output=file.path(root,"owner-output"))
  path<-file.path(root,"owner.rds");saveRDS(request,path);child<-start_child("tests/fixtures/acquisition-publication-observer.R",path);wait_ready(child,request$ready)
  ownership<-readRDS(request$output)
  check("live owner cannot be replaced despite reserved job presence",fails(brohn_acquisition_manager(other))&&brohn_get_job(other,ownership$job_id)$status=="running")
  child$kill_tree();child$wait(5000);replacement<-brohn_acquisition_manager(other)
  check("proven dead manager leaves source but cancels only its old attempt",identical(.brohn_acq_probe(ownership$identity),"absent")&&
    brohn_get_job(other,ownership$job_id)$status=="cancelled"&&identical(brohn_acquisition(other,recovery$id)$body,recovery$body))
  next_job<-.brohn_acq_publication_job(other,recovery,replacement,"acquisition_preserve")
  check("recovered manager gets new unique job and ownership fence",!identical(next_job$id,ownership$job_id)&&
    identical(next_job$request$owner$manager_id,replacement$id)&&!identical(replacement$id,ownership$manager_id)&&is.null(brohn_claim_job(other,"generic-worker",60)))
  brohn_cancel_job(other,next_job$id);brohn_close_store(other);other<-NULL
  brohn_close_store(store);store<-brohn_open_store(file.path(root,"workspace"))
  check("reopen retains exact original dataset and publication receipts",identical(.brohn_acq_hash(brohn_acquisition_download(store,record$id)),archive_hash)&&
    identical(brohn_get_entity(store,"dataset",data$id)$body,data$body)&&!is.null(brohn_acquisition(store,record$id)$body$review$publication$result_object))
  cat(sprintf("Acquisition publication: %d scoped checks passed; concurrent participant receipt %.6f seconds during %s.\n",checks,cancel$writer_seconds,cancel$phase))
})
