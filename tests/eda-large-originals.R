# Optional large synthetic resource/lifetime witness, not detector validation.
# Known legacy highpass recipe yields numerical candidates on a constant signal;
# the original exact-flatline flag must remain visible and values unchanged.
# Rscript this-file <checkout> <fresh-short-external-evidence>
args<-commandArgs(TRUE);stopifnot(length(args)==2L)
repo<-normalizePath(args[[1L]],winslash="/",mustWork=TRUE)
out<-file.path(normalizePath(dirname(args[[2L]]),winslash="/",mustWork=TRUE),basename(args[[2L]]))
inside<-function(x,parent){if(.Platform$OS.type=="windows"){x<-tolower(x);parent<-tolower(parent)};identical(x,parent)||startsWith(x,paste0(parent,"/"))}
stopifnot(!file.exists(out),!inside(out,repo),dir.create(out));cfg<-list(checkout=repo,out=out)
jsonlite::write_json(cfg,file.path(out,"config.json"),auto_unbox=TRUE,pretty=TRUE)
setwd(cfg$checkout);source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=FALSE)
local({
 out<-cfg$out;checks<-list();passed<-FALSE;failure<-NULL
 check<-function(name,value){if(!isTRUE(value))stop(name,call.=FALSE);checks[[length(checks)+1L]]<<-name;cat("PASS",name,"\n")}
 store<-brohn_open_store(file.path(out,"workspace"));brohn_initialise_library(store)
 on.exit({
   for(j in brohn_list_jobs(store))if(j$status %in% c("queued","running"))brohn_cancel_job(store,j$id)
   brohn_write_json_file(list(schema="brohn-eda-original-source-corpus/0.1",passed=passed,checks=checks,failure=failure,
    jobs=lapply(brohn_list_jobs(store),function(j)j[c("id","operation","status","attempt","error","result")]),
    scope="Synthetic continuous flat recording, genuine unchanged ingestion and scientific workers. Software sample-bound witness; no participant or physical device qualification."),file.path(out,"results.json"))
   brohn_close_store(store)
 },add=TRUE)
 tryCatch({
  runjob<-function(job){force(job);claim<-brohn_claim_job(store,"large-eda-original-source",lease_seconds=120L)
   stopifnot(!is.null(claim),identical(job$id,claim$id));brohn_process_job(store,claim,timeout_seconds=600L)
   done<-brohn_get_job(store,job$id);if(done$status!="succeeded")stop("Original worker failed: ",brohn_json(done$error));done}
  study<-brohn_create_study(store,"Synthetic long EDA recording for report bounds", "comparison")
  design<-study$body;design$description<-"Synthetic software qualification of report bounds and retry. No human participant or device recording."
  design$measures<-list("eda");study<-brohn_save_study(store,design,study$revision)
  brohn_write_json_file(study,file.path(out,"study.json"))
  path<-file.path(out,"large-original.csv")
  utils::write.csv(data.frame(time=(0:500099)/10,participant="0001",session="00001",conductance=5),path,row.names=FALSE,fileEncoding="UTF-8")
  upload<-file.path(tempdir(),"large-eda-corpus04-upload.csv");stopifnot(!file.exists(upload),file.copy(path,upload,copy.mode=FALSE))
  pending<-brohn_queue_ingestion(store,list(path=upload,name=basename(path),size=as.numeric(file.info(upload)$size),reference="large-original"),
    "Synthetic long EDA recording","eda","sample",study$id,operation_id="large-original")
  intake<-runjob(brohn_get_job(store,pending$body$job_id));d<-brohn_get_entity(store,"dataset",intake$result$dataset_id)
  mapping<-list(time_column="time",time_unit="s",sampling_rate=10,participant_column="participant",session_column="session",
    value_columns=list("conductance"),unit="uS",parameters=list(recipe="eda-neurokit-highpass/1.0"),
    origin_statement="Synthetic flat500100sample10Hz conductance. Software bounds witness only.")
  d<-brohn_curate_dataset(store,d$id,mapping,d$revision,study$id,study$revision)
  done<-runjob(brohn_queue_dataset(store,d$id,revision=d$revision));r<-brohn_get_entity(store,"report",done$result$report_id)
  brohn_write_json_file(d,file.path(out,"large-dataset.json"));brohn_write_json_file(r,file.path(out,"large-report.json"))
  a<-r$body$analysis;dir.create(file.path(out,"large"))
  for(x in a$artifacts){p<-brohn_object_path(store,brohn_default(x$hash,x$sha256),TRUE);stopifnot(file.copy(p,file.path(out,"large",paste0(x$kind,".ndjson")),copy.mode=FALSE))}
  envelope<-brohn_read_json_file(brohn_object_path(store,r$body$result_object$hash,TRUE),maximum=16*1024^2)
  check("exact original worker envelope and native publication",identical(brohn_json(envelope$report),brohn_json(r$body[setdiff(names(r$body),"result_object")]))&&isTRUE(r$body$processing$publication$native_seal))
  check("original source hash and study binding",r$body$provenance$source$hash==digest::digest(file=path,algo="sha256")&&r$body$provenance$design_hash==brohn_hash(study$body)&&r$body$study_id==study$id)
  check("one computed original segment",length(a$recordings)==1L&&a$quality$computed_channel_segments==1L)
  check("complete genuine stream exceeds display sample bound",length(a$artifacts)==2L&&a$artifacts[[1L]]$rows>500000L&&a$artifacts[[1L]]$rows<=1000000L)
  check("complete stream within original64MiB bound",all(vapply(a$artifacts,function(x)as.numeric(file.info(brohn_object_path(store,brohn_default(x$hash,x$sha256),TRUE))$size)<=64*1024^2,logical(1))))
  jobs<-brohn_list_jobs(store);check("only genuine ingestion and scientific analysis jobs",length(jobs)==2L&&all(vapply(jobs,function(j)j$status=="succeeded",logical(1))))
  brohn_write_json_file(list(source_rows=500100,sampling_rate=10,complete_samples=a$artifacts[[1L]]$rows,computed_segments=1,
    expected_display_limit=500000,scope="No new scientific estimate or validity claim."),file.path(out,"expected-witnesses.json"))
  passed<-TRUE
 },error=function(e){failure<<-conditionMessage(e);stop(e)})
})
