# Real shared job dispatcher and scientific child, then ordinary explicit mapping
# and a second actual gaze analysis job. No fixture-specific worker dispatch.
source("R/platform-load.R");brohn_load(ui=FALSE)
source("tests/fixtures/platform-analysis-fixture.R")
local({
  checks<-0L
  check<-function(name,ok){if(!isTRUE(ok))stop("Integrated intake QA: ",name);checks<<-checks+1L}
  rejects<-function(expr)inherits(try(force(expr),silent=TRUE),"try-error")
  near<-function(a,b)is.numeric(a)&&length(a)==1L&&is.finite(a)&&abs(a-b)<1e-9
  root<-tempfile("brohn-ingestion-integration-");dir.create(root);root<-normalizePath(root,winslash="/")
  store<-brohn_open_store(file.path(root,"workspace"));brohn_initialise_library(store)
  on.exit({
    for(key in ls(.brohn_ingestion_sources,all.names=TRUE)){
      held<-get(key,envir=.brohn_ingestion_sources,inherits=FALSE)
      if(identical(held$workspace_id,store$workspace_id)){.Call(held$native$close,held$pointer);rm(list=key,envir=.brohn_ingestion_sources)}
    }
    brohn_close_store(store);actual<-normalizePath(root,winslash="/",mustWork=FALSE)
    stopifnot(startsWith(tolower(actual),paste0(tolower(normalizePath(tempdir(),winslash="/")),"/")),startsWith(basename(actual),"brohn-ingestion-integration-"))
    unlink(actual,recursive=TRUE,force=TRUE)
  },add=TRUE)
  finish<-function(id) {
    job<-brohn_claim_job(store,"original-integrated-intake",60)
    stopifnot(identical(job$id,id))
    brohn_process_job(store,job,timeout_seconds=90)
    final<-brohn_get_job(store,id)
    if(final$status!="succeeded")stop("Actual shared worker failed: ",brohn_json(final$error))
    final
  }
  fixture<-researcher_analysis_fixture();study<-brohn_put_entity(store,"study",fixture$design$id,fixture$design)
  path<-tempfile("completed-original-gaze-",fileext=".csv");utils::write.csv(fixture$gaze,path,row.names=FALSE,na="",fileEncoding="UTF-8")
  original<-readBin(path,"raw",n=file.info(path)$size);hash<-digest::digest(original,algo="sha256",serialize=FALSE)
  upload<-list(path=path,name="original-gaze.csv",size=length(original),reference="original-shared-worker-upload")
  record<-brohn_queue_ingestion(store,upload,"Original integrated gaze source","gaze","sample",study_id=study$id,operation_id="original-shared-worker-intake")
  check("shared loader exposes intake without additional source calls",exists("brohn_analyse_ingestion",mode="function")&&length(brohn_list_entities(store,"dataset"))==0L)
  changed<-fixture$design;changed$title<-"Later study title after reviewed upload";brohn_save_study(store,changed,study$revision)
  completed<-finish(record$body$job_id)
  ready<-brohn_ingestion(store,record$id);dataset<-brohn_get_entity(store,"dataset",completed$result$dataset_id)
  check("actual dispatcher completes intake and creates one full dataset",ready$body$status=="ready"&&dataset$body$status=="needs_mapping"&&length(brohn_list_entities(store,"dataset"))==1L)
  check("upload retains reviewed study revision despite later edit",dataset$body$study_revision==1L&&ready$body$review$study_hash==brohn_hash(fixture$design))
  check("intake does not create a scientific report or infer a mapping",length(brohn_list_entities(store,"report"))==0L&&length(dataset$body$metadata)==0L)
  check("exact uploaded bytes survive shared worker publication",dataset$body$source$hash==hash&&identical(readBin(brohn_object_path(store,hash),"raw",n=length(original)),original))
  check("preview is bounded while complete raw row count remains",length(dataset$body$preview)==min(20,nrow(fixture$gaze))&&nrow(brohn_read_table(brohn_object_path(store,hash),"csv"))==nrow(fixture$gaze))
  identity<-ready$body$processing$code_hashes
  check("actual child pins intake and helper with existing closure",all(c("scripts/analysis-worker.R","R/platform-store.R","R/platform-ingestion.R","scripts/workers/ingestion_snapshot.py","scripts/workers/publication.py","src/publication_guard.c")%in%names(identity))&&
    all(vapply(names(identity),function(p)identical(identity[[p]],digest::digest(file=p,algo="sha256")),logical(1))))
  check("unmapped imported source cannot enter scientific analysis",rejects(brohn_queue_dataset(store,dataset$id)))
  download<-file.path(root,"original-source-download.csv");brohn_copy_object_download(store,hash,download)
  check("shared download helper returns exact writable transfer bytes",identical(readBin(download,"raw",n=length(original)),original)&&file.access(download,2L)==0L)
  envelope<-brohn_read_json_file(brohn_object_path(store,ready$body$result_object$hash))
  check("publication document reproduces complete dataset body",identical(brohn_hash(envelope$dataset),brohn_hash(dataset$body)))
  accepted<-brohn_curate_dataset(store,dataset$id,fixture$gaze_mapping,dataset$revision)
  check("explicit mapping produces a new immutable dataset revision",accepted$revision==2L&&accepted$body$source$hash==hash)
  analysis_job<-brohn_queue_dataset(store,accepted$id);analysis<-finish(analysis_job$id)
  report<-brohn_get_entity(store,"report",analysis$result$report_id)
  check("upload through actual scientific worker reproduces independent gaze oracle",near(report$body$analysis$contrasts[[1]]$estimate,10.833333333333334))
  check("report retains explicitly pinned reviewed design and origin",report$body$provenance$study_revision==1L&&report$body$origin=="sample")
  brohn_reap_ingestion_guards(store)
  check("successful intake releases only its retained original guard",!exists(.brohn_ingestion_key(store,record$id),envir=.brohn_ingestion_sources,inherits=FALSE))
  brohn_close_store(store);store<-brohn_open_store(file.path(root,"workspace"))
  check("study intake source mapping report and histories survive reopen",brohn_ingestion(store,record$id)$body$status=="ready"&&
    length(brohn_entity_history(store,"ingestion",record$id))==3L&&length(brohn_entity_history(store,"dataset",dataset$id))==2L&&
    near(brohn_get_entity(store,"report",report$id)$body$analysis$contrasts[[1]]$estimate,10.833333333333334))
  # Malformed preview is terminal and source-preserving through the real worker.
  bad<-tempfile("completed-malformed-",fileext=".csv");writeLines(c("x,x","0,1"),bad)
  bad_record<-brohn_queue_ingestion(store,list(path=bad,name="original-malformed.csv",size=file.info(bad)$size,reference="original-malformed"),
    "Original malformed columns","gaze","sample",operation_id="original-malformed-intake")
  bad_job<-brohn_claim_job(store,"original-malformed-worker",60);brohn_process_job(store,bad_job,timeout_seconds=90)
  check("actual child failure remains terminal with no partial dataset",brohn_get_job(store,bad_job$id)$status=="failed"&&
    brohn_ingestion(store,bad_record$id)$body$effective_status=="failed"&&is.null(brohn_get_entity(store,"dataset",paste0("dataset-",bad_record$id)))&&file.exists(bad_record$body$source_snapshot$path))
  retry<-brohn_retry_ingestion(store,bad_record$id,bad_record$revision,"original-explicit-retry")
  check("real failed operation supports exact-source explicit retry",retry$body$job_id!=bad_record$body$job_id&&retry$body$review_hash==bad_record$body$review_hash)
  brohn_cancel_ingestion(store,retry$id,retry$revision)
  check("intake-specific cancellation cancels its queued retry only",brohn_get_job(store,retry$body$job_id)$status=="cancelled"&&brohn_get_job(store,analysis$id)$status=="succeeded")
  cat(checks," actual shared intake / mapping / analysis / download checks passed\n",sep="")
})
