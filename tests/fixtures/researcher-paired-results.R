args<-commandArgs(trailingOnly=TRUE);stopifnot(length(args)>=2L)
mode<-args[[1L]];folder<-normalizePath(args[[2L]],winslash="/",mustWork=TRUE)
stopifnot(startsWith(basename(folder),"brohn-paired-browser-"))
source("R/platform-load.R",encoding="UTF-8");brohn_load()
source("tests/fixtures/paired-results-fixture.R")
config_path<-file.path(folder,"fixture.json")
if(mode=="setup")local({
  stopifnot(!file.exists(config_path),!dir.exists(file.path(folder,"workspace")))
  store<-brohn_open_store(file.path(folder,"workspace"));on.exit(brohn_close_store(store))
  brohn_initialise_library(store);f<-researcher_paired_fixture();brohn_put_entity(store,"study",f$design$id,f$design)
  explicit<-do.call(rbind,lapply(f$responses,function(r)data.frame(person=r$participant_id,visit=r$session_id,condition=r$condition_id,
    stimulus=r$stimulus_id,exposure=r$exposure_id,question=r$question_id,value=brohn_default(r$value,NA_real_))))
  common<-list(origin_statement="Original fictional paired-results QA; no participants or device qualification.",participant_column="person",session_column="visit",
    condition_column="condition",stimulus_column="stimulus",exposure_column="exposure",time_unit="ms")
  maps<-list(questionnaire=c(common,list(question_column="question",value_columns=list("value"),unit="numeric_rating")),
    gaze=c(common,list(start_column="start",end_column="end",x_column="x",y_column="y",valid_column="valid",source_phase="passive_viewing_only",unit="stimulus_normalized")))
  intervals<-unlist(lapply(f$gaze,function(r){row<-function(start,end,x,valid)data.frame(person=r$participant_id,visit=r$session_id,condition=r$condition_id,
    stimulus=r$stimulus_id,exposure=r$exposure_id,start=start,end=end,x=x,y=if(valid).5 else NA_real_,valid=if(valid)"true"else"false")
    if(is.null(r$valid_share_percent))list(row(0,1000,NA_real_,FALSE))else list(row(0,r$inside_ms,.25,TRUE),row(r$inside_ms,1000,.75,TRUE))}),recursive=FALSE)
  gaze<-do.call(rbind,intervals);jobs<-list();sources<-list()
  for(kind in c("questionnaire","gaze")) {
    file<-file.path(folder,paste0("original-",kind,".csv"));utils::write.csv(if(kind=="gaze")gaze else explicit,file,row.names=FALSE,na="")
    d<-brohn_ingest_dataset(store,file,paste("Paired original",kind),kind,study_id=f$design$id,origin="sample")
    d<-brohn_curate_dataset(store,d$id,maps[[kind]],d$revision);job<-brohn_queue_dataset(store,d$id)
    jobs[[kind]]<-job$id;sources[[kind]]<-d$body$source$hash
  }
  port<-suppressWarnings(as.integer(Sys.getenv("BROHN_PAIRED_TEST_PORT","3891")))
  stopifnot(port>=1024L,port<=65535L)
  brohn_write_json_file(list(workspace=store$root,port=port,study_id=f$design$id,jobs=jobs,sources=sources,expected=f$expected),config_path)
})else if(mode=="seed")local({
  config<-brohn_read_json_file(config_path);store<-brohn_open_store(config$workspace);on.exit(brohn_close_store(store));reports<-list()
  for(kind in names(config$jobs)) {
    repeat{j<-brohn_claim_job(store,"paired-fixture",300);if(is.null(j))break;brohn_process_job(store,j,timeout_seconds=300)}
    j<-brohn_get_job(store,config$jobs[[kind]]);stopifnot(j$status=="succeeded")
    r<-brohn_get_entity(store,"report",j$result$report_id);stopifnot(r$body$analysis$contrasts[[1]]$estimate==8)
    reports[[kind]]<-list(id=r$id,hash=brohn_hash(r$body),revision=r$revision)
  }
  f<-researcher_paired_fixture();crosswalk<-unlist(lapply(reports,function(ref){r<-brohn_get_entity(store,"report",ref$id)
    keys<-unique(vapply(r$body$analysis$observations,function(o)brohn_json(list(o$participant_id,o$session_id)),character(1)))
    lapply(keys,function(k){v<-brohn_parse(k);list(report_id=ref$id,source_participant_id=v[[1]],source_session_id=v[[2]],participant_id=v[[1]],session_id=v[[2]])})}),recursive=FALSE,use.names=FALSE)
  specs<-list(list(id="paired-gaze",report_ids=list(reports$gaze$id),modality="gaze",metric="valid_gaze_share",outcome_id="Logo",unit="percentage points",control_id="condition-a",test_id="condition-b"),
    list(id="paired-liking",report_ids=list(reports$questionnaire$id),modality="questionnaire",metric="explicit_numeric_response",outcome_id="q-liking",unit="response units",control_id="condition-a",test_id="condition-b"))
  job<-brohn_queue_multimodal(store,config$study_id,unname(lapply(reports,`[[`,"id")),crosswalk,specs,origin="sample",identity_source="Original synthetic QA register: P1-P4 and V1-V5 are the same fictional people and visits in the two independently imported sources.")
  claimed<-brohn_claim_job(store,"paired-fixture",300);stopifnot(claimed$id==job$id);brohn_process_job(store,claimed,timeout_seconds=300)
  job<-brohn_get_job(store,job$id);stopifnot(job$status=="succeeded");r<-brohn_get_entity(store,"report",job$result$report_id)
  stopifnot(length(r$body$analysis$contrasts)==2L,all(vapply(r$body$analysis$contrasts,function(c)c$estimate==8,logical(1))))
  reports$multimodal<-list(id=r$id,hash=brohn_hash(r$body),revision=r$revision);config$reports<-reports
  brohn_write_json_file(config,config_path);cat("PASS three actual workers published independently specified paired reports\n")
})else if(mode=="seed-stress")local({
  config<-brohn_read_json_file(config_path);stopifnot(is.null(config$reports$stress))
  store<-brohn_open_store(config$workspace);on.exit(brohn_close_store(store))
  base<-utils::read.csv(file.path(folder,"original-questionnaire.csv"),stringsAsFactors=FALSE)[1:3,]
  rows<-do.call(rbind,lapply(1:1000,function(i){r<-base;r$person<-paste0("Person",sprintf("%04d",i));r}))
  csv<-file.path(folder,"original-thousand-people.csv");utils::write.csv(rows,csv,row.names=FALSE,na="")
  d<-brohn_ingest_dataset(store,csv,"Original 1000-person paired responsiveness QA","questionnaire",study_id=config$study_id,origin="sample")
  mapping<-list(origin_statement="Original synthetic arithmetic, 1000 fictional people with three response observations each.",participant_column="person",session_column="visit",condition_column="condition",
    stimulus_column="stimulus",exposure_column="exposure",question_column="question",value_columns=list("value"),time_unit="ms",unit="numeric_rating")
  d<-brohn_curate_dataset(store,d$id,mapping,d$revision);job<-brohn_queue_dataset(store,d$id);claimed<-brohn_claim_job(store,"paired-stress-fixture",300)
  stopifnot(claimed$id==job$id);brohn_process_job(store,claimed,timeout_seconds=300);job<-brohn_get_job(store,job$id);stopifnot(job$status=="succeeded")
  r<-brohn_get_entity(store,"report",job$result$report_id);stopifnot(r$body$analysis$contrasts[[1]]$estimate==2,r$body$analysis$contrasts[[1]]$participant_count==1000)
  config$reports$stress<-list(id=r$id,hash=brohn_hash(r$body),revision=r$revision);brohn_write_json_file(config,config_path)
  cat("PASS actual worker published3000 original observations for1000 fictional people\n")
})else if(mode=="serve") {
  config<-brohn_read_json_file(config_path);Sys.setenv(BROHN_WORKSPACE=config$workspace,BROHN_APP_MODE="platform")
  stop_owned<-function()if(file.exists(file.path(folder,"stop.request")))shiny::stopApp()else later::later(stop_owned,.2)
  later::later(stop_owned,.2);shiny::runApp(".",host="127.0.0.1",port=config$port,launch.browser=FALSE)
}else if(mode=="inspect")local({
  config<-brohn_read_json_file(config_path);store<-brohn_open_store(config$workspace);on.exit(brohn_close_store(store))
  reports<-lapply(config$reports,function(ref){r<-brohn_get_entity(store,"report",ref$id);list(id=r$id,hash=brohn_hash(r$body),unchanged=identical(ref$hash,brohn_hash(r$body)))})
  jobs<-brohn_list_jobs(store,limit=100L)
  brohn_write_json_file(list(reports=reports,jobs=lapply(jobs,function(j)j[c("id","operation","status")]),source_hashes=config$sources),file.path(folder,"inspection.json"))
})else stop("Unknown paired browser fixture mode.")
