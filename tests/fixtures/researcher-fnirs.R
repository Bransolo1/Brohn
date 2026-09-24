# Isolated browser copy of already qualified original software-phantom outputs.
args<-commandArgs(trailingOnly=TRUE);mode<-args[[1]];folder<-normalizePath(args[[2]],winslash="/",mustWork=TRUE)
stopifnot(startsWith(basename(folder),"brohn-fnirs-browser-"))
source("R/platform-load.R",encoding="UTF-8");brohn_load()
config_path<-file.path(folder,"fixture.json")
if(mode=="setup")local({
  reference<-brohn_read_json_file(file.path(args[[3]],"acceptance.json"))
  stopifnot(!file.exists(config_path),!dir.exists(file.path(folder,"workspace")),file.copy(reference$workspace,folder,recursive=TRUE))
  store<-brohn_open_store(file.path(folder,"workspace"));on.exit(brohn_close_store(store))
  reports<-lapply(reference$reports,function(r){
    saved<-brohn_get_entity(store,"report",r$report_id);catalog<-brohn_get_entity(store,"signal_view",r$catalog_id)
    a<-Filter(function(a)identical(a$kind,"physiology-series"),saved$body$analysis$artifacts)[[1L]]
    c(r,list(artifact=a,artifact_path=brohn_object_path(store,a$hash),tables=catalog$body$view$tables))
  })
  port<-as.integer(Sys.getenv("BROHN_QA_PORT",unset=as.character(httpuv::randomPort(min=21000L,max=49000L))))
  stopifnot(!is.na(port),port>=1024L,port<=65535L)
  brohn_write_json_file(list(workspace=store$root,port=port,reports=reports,reference=reference$reference,
    baseline_jobs=lapply(brohn_list_jobs(store,limit=500L),function(j)j$id)),config_path)
})else if(mode=="serve"){
  config<-brohn_read_json_file(config_path);Sys.setenv(BROHN_WORKSPACE=config$workspace,BROHN_APP_MODE="platform")
  stop_owned<-function()if(file.exists(file.path(folder,"stop.request")))shiny::stopApp()else later::later(stop_owned,.2)
  later::later(stop_owned,.2);shiny::runApp(".",host="127.0.0.1",port=config$port,launch.browser=FALSE)
}else if(mode=="worker")local({
  config<-brohn_read_json_file(config_path);store<-brohn_open_store(config$workspace);on.exit(brohn_close_store(store))
  repeat{if(file.exists(file.path(folder,"stop.request")))break
    job<-brohn_claim_job(store,"fnirs-browser",300);if(is.null(job))Sys.sleep(.2)else brohn_process_job(store,job,timeout_seconds=300)}
})else if(mode=="inspect")local({
  config<-brohn_read_json_file(config_path);store<-brohn_open_store(config$workspace);on.exit(brohn_close_store(store))
  brohn_write_json_file(list(jobs=brohn_list_jobs(store,limit=500L),reports=lapply(config$reports,function(r){s<-brohn_get_entity(store,"report",r$report_id);list(id=s$id,hash=brohn_hash(s$body))})),file.path(folder,"inspection.json"))
})else stop("Unknown fixture mode")
