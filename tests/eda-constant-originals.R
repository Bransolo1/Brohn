# Genuine ingestion and scientific publication from explicit recipe1.1 sources.
# Rscript this-file <config.json>; config binds an immutable candidate and fresh
# workspace copied from the original EDA corpus. Synthetic data is not device evidence.
args<-commandArgs(TRUE);stopifnot(length(args)==1L)
cfg<-jsonlite::fromJSON(args[[1L]],simplifyVector=FALSE)
setwd(cfg$checkout);source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=FALSE)
local({
 out<-cfg$out;store<-brohn_open_store(file.path(out,"workspace"))
 checks<-list();reports<-datasets<-list();passed<-FALSE;failure<-NULL
 check<-function(label,value){if(!isTRUE(value))stop(label,call.=FALSE);checks[[length(checks)+1L]]<<-label;cat("PASS",label,"\n")}
 same<-function(a,b)identical(brohn_json(a),brohn_json(b))
 ref<-function(r)list(kind=r$kind,id=r$id,revision=r$revision,body_hash=brohn_hash(r$body),project_id=r$project_id)
 original<-brohn_read_json_file(file.path(out,"original-results.json"))
 original_jobs<-DBI::dbGetQuery(store$con,"SELECT id,status FROM jobs ORDER BY id")
 on.exit({
  for(j in brohn_list_jobs(store))if(j$status %in% c("queued","running"))brohn_cancel_job(store,j$id)
  brohn_write_json_file(list(schema="brohn-eda-constant-native-corpus/0.1",passed=passed,checks=checks,failure=failure,
   reports=lapply(reports,ref),datasets=lapply(datasets,ref),original_reports=original$reports,
   jobs=lapply(brohn_list_jobs(store),function(j)j[c("id","operation","status","attempt","error","result")]),
   scope="Actual synthetic source ingestion and explicit recipe1.1 native scientific publication. No method, physical device, browser or report-export qualification."),file.path(out,"results.json"))
  brohn_close_store(store)
 },add=TRUE)
 tryCatch({
  old<-brohn_get_entity(store,"report",original$reports$continuous$id)
  study<-brohn_get_entity(store,"study",old$body$study_id,old$body$provenance$study_revision)
  brohn_write_json_file(study,file.path(out,"study.json"))
  runjob<-function(job){force(job);claim<-brohn_claim_job(store,"eda-constant-originals",lease_seconds=60L)
   stopifnot(!is.null(claim),identical(job$id,claim$id));brohn_process_job(store,claim,timeout_seconds=300L)
   done<-brohn_get_job(store,job$id);if(done$status!="succeeded")stop(brohn_json(done$error));done}
  ingest<-function(name,frame,unit,columns,analyse=TRUE){
   path<-file.path(out,paste0(name,"-original.csv"));utils::write.csv(frame,path,row.names=FALSE,na="NA",fileEncoding="UTF-8")
   upload<-file.path(tempdir(),paste0("brohn-constant-",name,".csv"));stopifnot(!file.exists(upload),file.copy(path,upload,copy.mode=FALSE))
   pending<-brohn_queue_ingestion(store,list(path=upload,name=basename(path),size=as.numeric(file.info(upload)$size),reference=paste0("constant-",name)),
    paste("Synthetic exact-constant qualification",name),"eda","sample",study$id,operation_id=paste0("constant-",name))
   intake<-runjob(brohn_get_job(store,pending$body$job_id));d<-brohn_get_entity(store,"dataset",intake$result$dataset_id)
   if(!analyse){datasets[[name]]<<-d;brohn_write_json_file(d,file.path(out,paste0(name,"-dataset.json")));return(d)}
   mapping<-list(time_column="time",time_unit="s",sampling_rate=10,participant_column="participant",session_column="session",
    value_columns=as.list(columns),unit=unit,parameters=list(recipe="eda-neurokit-highpass/1.1"),
    origin_statement="Synthetic source for exact-constant software behavior and preservation; no human or device measurement.")
   d<-brohn_curate_dataset(store,d$id,mapping,d$revision,study$id,study$revision);datasets[[name]]<<-d
   done<-runjob(brohn_queue_dataset(store,d$id,revision=d$revision));r<-brohn_get_entity(store,"report",done$result$report_id);reports[[name]]<<-r
   brohn_write_json_file(d,file.path(out,paste0(name,"-dataset.json")));brohn_write_json_file(r,file.path(out,paste0(name,"-report.json")))
   dir.create(file.path(out,name));for(a in r$body$analysis$artifacts){p<-brohn_object_path(store,brohn_default(a$hash,a$sha256),TRUE)
    stopifnot(file.copy(p,file.path(out,name,paste0(a$kind,".ndjson")),copy.mode=FALSE))}
   envelope<-brohn_read_json_file(brohn_object_path(store,r$body$result_object$hash,TRUE),maximum=16*1024^2)
   check(paste(name,"native first-attempt publication and original envelope"),done$attempt==1L&&isTRUE(r$body$processing$publication$native_seal)&&same(envelope$report,r$body[setdiff(names(r$body),"result_object")]))
   check(paste(name,"exact source study and new explicit recipe retained"),r$body$provenance$source$hash==digest::digest(file=path,algo="sha256")&&r$body$provenance$design_hash==brohn_hash(study$body)&&all(vapply(r$body$analysis$parameters,function(p)identical(p$recipe,"eda-neurokit-highpass/1.1")&&identical(p$exact_constant_policy,"raw_description_only/1.0"),logical(1))))
   r
  }
  frame<-data.frame(time=(0:1199)/10,participant="0007",session="0002",zero=0,half=.5,five=5,five_hundred=500)
  r<-ingest("levels-us",frame,"uS",c("zero","half","five","five_hundred"));a<-r$body$analysis
  check("Four exact-constant channels remain descriptive with all forty features",length(a$recordings)==4L&&length(a$features)==40L&&a$quality$descriptive_channel_segments==4L&&a$quality$computed_channel_segments==0L&&a$quality$unavailable_channel_segments==0L)
  expected<-list(zero=0,half=.5,five=5,five_hundred=500)
  for(cell in a$recordings){
   f<-Filter(function(x)identical(x$recording_id,cell$recording_id)&&identical(x$channel,cell$channel),a$features)
   raw<-Filter(function(x)identical(x$name,"conductance_raw_mean"),f)
   withheld<-Filter(function(x)!identical(x$name,"conductance_raw_mean"),f)
   check(paste(cell$channel,"raw level exact and nine estimates absent"),length(raw)==1L&&raw[[1L]]$value==expected[[cell$channel]]&&isTRUE(raw[[1L]]$eligible)&&length(withheld)==9L&&all(vapply(withheld,function(x)is.null(x$value)&&identical(x$missing_reason,"exact_constant_signal")&&identical(x$eligible,FALSE),logical(1))))
   check(paste(cell$channel,"edge support and text identities preserved"),identical(cell$group$participant_id,"0007")&&identical(cell$group$session_id,"0002")&&cell$samples==1200L&&cell$retained_samples==1000L&&cell$filter_edge_samples==200L&&is.null(cell$response_denominator)&&identical(cell$status,"descriptive_only"))
  }
  check("Full coordinates retained with valid empty candidate stream",length(a$artifacts)==2L&&a$artifacts[[1L]]$rows==4800L&&a$artifacts[[2L]]$rows==0L&&isTRUE(a$quality$complete_processed_artifacts)&&!isTRUE(a$quality$raw_source_duplicated))
  frame<-data.frame(time=(0:1199)/10,participant="0007",session="0002",conductance=5e-6)
  r<-ingest("level-siemens",frame,"S","conductance");a<-r$body$analysis
  raw<-Filter(function(x)identical(x$name,"conductance_raw_mean"),a$features)[[1L]]
  check("Unit conversion enters the same descriptive branch",raw$value==5&&a$recordings[[1L]]$scale_factor==1e6&&a$recordings[[1L]]$source_unit=="S"&&a$recordings[[1L]]$status=="descriptive_only")
  t<-(0:2199)/10;x<-rep(5,length(t));indices<-1002:2001;u<-t[indices]-t[min(indices)]
  x[indices]<-4+.001*u;for(onset in c(15,40,70)){d<-pmax(u-onset,0);x[indices]<-x[indices]+exp(-d/1.8)-exp(-d/.4)}
  x[c(1001,2002)]<-NA
  frame<-data.frame(time=t,participant="0007",session="0002",conductance=x)
  r<-ingest("mixed",frame,"uS","conductance");a<-r$body$analysis
  check("Missing samples split constant ordinary and short segments",length(a$recordings)==3L&&identical(vapply(a$recordings,`[[`,character(1),"status"),c("descriptive_only","computed","unavailable"))&&identical(vapply(a$recordings,`[[`,numeric(1),"samples"),c(1000,1000,198)))
  check("Mixed usability does not convert missing responses to zeros",a$status=="partial"&&a$quality$computed_channel_segments==1L&&a$quality$descriptive_channel_segments==1L&&a$quality$unavailable_channel_segments==1L&&isTRUE(a$quality$usable)&&!isTRUE(a$quality$scientifically_qualified))
  check("Only eligible segments publish coordinates; short segment remains unavailable",a$artifacts[[1L]]$rows==2000L&&length(a$features)==20L)
  draft<-ingest("browser-draft",data.frame(time=(0:1199)/10,participant="0007",session="0002",conductance=5),"uS","conductance",analyse=FALSE)
  check("Separate real imported dataset remains unanalysed for browser mapping",DBI::dbGetQuery(store$con,"SELECT count(*) AS n FROM entity_versions WHERE kind='report' AND json_extract(body_json,'$.dataset_id')=?",params=list(draft$id))$n[[1L]]==0L)
  for(r in original$reports)check(paste("Original report remains exact",r$id),identical(brohn_hash(brohn_get_entity(store,"report",r$id,r$revision)$body),r$body_hash))
  after<-DBI::dbGetQuery(store$con,"SELECT id,status FROM jobs ORDER BY id")
  check("Exactly seven new jobs including browser intake; original jobs untouched",nrow(after)==nrow(original_jobs)+7L&&identical(after[after$id %in% original_jobs$id,,drop=FALSE]$status,original_jobs$status)&&all(after[!after$id %in% original_jobs$id,,drop=FALSE]$status=="succeeded"))
  passed<-TRUE
 },error=function(e){failure<<-conditionMessage(e);stop(e)})
 cat(length(checks),"native exact-constant source checks passed\n")
})
