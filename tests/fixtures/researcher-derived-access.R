# Read-only browser review on an isolated copy of the accepted synthetic media.
args<-commandArgs(trailingOnly=TRUE);stopifnot(length(args)%in%c(2L,3L));mode<-args[[1L]]
source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=TRUE)
folder<-normalizePath(args[[2L]],winslash="/",mustWork=TRUE)
stopifnot(startsWith(basename(folder),"brohn-derived-access-"))
cp<-file.path(folder,"fixture.json");workspace<-file.path(folder,"workspace")
if(mode=="setup"){
  fixture<-normalizePath(args[[3L]],winslash="/",mustWork=TRUE)
  stopifnot(startsWith(basename(fixture),"brohn-audio-extract-browser-"),!dir.exists(workspace))
  stopifnot(file.copy(file.path(fixture,"workspace"),folder,recursive=TRUE))
}
if(mode=="researcher"){
  Sys.setenv(BROHN_WORKSPACE=workspace,BROHN_APP_MODE="platform",BROHN_PARTICIPANT_PORT="3936")
  stop_owned<-function()if(file.exists(file.path(folder,"stop.researcher")))shiny::stopApp()else later::later(stop_owned,.2)
  later::later(stop_owned,.2);shiny::runApp(".",host="127.0.0.1",port=3935,launch.browser=FALSE)
}else local({
  store<-brohn_open_store(workspace);on.exit(brohn_close_store(store),add=TRUE)
  if(mode=="setup"){
    jobs<-brohn_list_jobs(store,limit=1000L);stopifnot(!any(vapply(jobs,function(j)j$status%in%c("queued","running"),logical(1))))
    reports<-brohn_list_entities(store,"report",limit=1000L)
    candidates<-Filter(function(r)!is.null(r$body$provenance$derived_audio_lineage),reports);stopifnot(length(candidates)==1L)
    r<-candidates[[1L]];d<-brohn_get_entity(store,"dataset",r$body$dataset_id)
    parent<-brohn_get_entity(store,"dataset",r$body$provenance$derived_audio_lineage$binding$parent_dataset$id)
    brohn_write_json_file(list(report_id=r$id,report_title=r$body$title,dataset_id=d$id,dataset_title=d$body$title,
      parent_id=parent$id,project_id=parent$project_id,original_jobs=length(jobs),
      original_reports=lapply(reports,function(x)list(id=x$id,hash=brohn_hash(x$body))),
      original_source_hash=parent$body$source$hash,derived_source_hash=d$body$source$hash),cp)
  }else{
    c<-brohn_read_json_file(cp)
    if(mode%in%c("revoke","restore")){
      DBI::dbExecute(store$con,"UPDATE entities SET project_id=? WHERE kind='dataset' AND id=?",
        params=list(if(mode=="revoke")"deliberate-derived-access-foreign"else c$project_id,c$parent_id))
    }else if(mode=="verify"){
      stopifnot(length(brohn_list_jobs(store,limit=1000L))==c$original_jobs,
        all(vapply(c$original_reports,function(r)identical(brohn_hash(brohn_get_entity(store,"report",r$id)$body),r$hash),logical(1))),
        identical(digest::digest(file=brohn_object_path(store,c$original_source_hash),algo="sha256"),c$original_source_hash),
        identical(digest::digest(file=brohn_object_path(store,c$derived_source_hash),algo="sha256"),c$derived_source_hash))
      brohn_report_for_review(store,c$report_id)
      brohn_write_json_file(list(passed=TRUE,new_jobs=0L,original_reports_unchanged=TRUE,original_video_and_derived_audio_unchanged=TRUE),file.path(folder,"verified.json"))
    }else stop("Unknown isolated access-fixture mode")
  }
})
