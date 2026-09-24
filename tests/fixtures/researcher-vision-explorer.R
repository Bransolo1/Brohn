# Browser-only copy of actual pinned-model reference reports; no inference rerun.
args<-commandArgs(trailingOnly=TRUE);stopifnot(length(args)>=2L)
mode<-args[[1L]];folder<-normalizePath(args[[2L]],winslash="/",mustWork=TRUE)
stopifnot(startsWith(basename(folder),"brohn-vision-browser-"))
source("R/platform-load.R",encoding="UTF-8");brohn_load()
config_path<-file.path(folder,"fixture.json")
if(mode=="setup")local({
  reference<-brohn_read_json_file(file.path(args[[3L]],"acceptance.json"))
  stopifnot(!file.exists(config_path),!dir.exists(file.path(folder,"workspace")),file.copy(reference$workspace,folder,recursive=TRUE))
  store<-brohn_open_store(file.path(folder,"workspace"));on.exit(brohn_close_store(store))
  cases<-lapply(reference$cases,function(x){
    report<-brohn_get_entity(store,"report",x$report_id);dataset<-brohn_get_entity(store,"dataset",x$dataset_id)
    stopifnot(identical(brohn_hash(report$body),x$report_hash))
    c(x,list(title=dataset$body$title,artifact_path=brohn_object_path(store,x$artifact$hash),
      source_path=brohn_object_path(store,report$body$provenance$source$hash),source=report$body$provenance$source,
      parameters=report$body$analysis$parameters,engine=report$body$analysis$engine))
  })
  port<-as.integer(Sys.getenv("BROHN_QA_PORT","3885"));stopifnot(!is.na(port),port>=1024L,port<=65535L)
  brohn_write_json_file(list(workspace=store$root,port=port,cases=cases,reference_manifest=reference$reference_manifest,
    baseline_jobs=lapply(brohn_list_jobs(store,limit=500L),function(j)j$id)),config_path)
})else if(mode=="serve"){
  config<-brohn_read_json_file(config_path);Sys.setenv(BROHN_WORKSPACE=config$workspace,BROHN_APP_MODE="platform")
  stop_owned<-function()if(file.exists(file.path(folder,"stop.request")))shiny::stopApp()else later::later(stop_owned,.2)
  later::later(stop_owned,.2);shiny::runApp(".",host="127.0.0.1",port=config$port,launch.browser=FALSE)
}else if(mode=="worker")local({
  config<-brohn_read_json_file(config_path);store<-brohn_open_store(config$workspace);on.exit(brohn_close_store(store))
  repeat{if(file.exists(file.path(folder,"stop.request")))break
    if(file.exists(file.path(folder,"worker.pause"))){Sys.sleep(.2);next}
    job<-brohn_claim_job(store,"vision-browser",300)
    if(is.null(job))Sys.sleep(.2)else brohn_process_job(store,job,timeout_seconds=300)
  }
})else if(mode=="inspect")local({
  config<-brohn_read_json_file(config_path);store<-brohn_open_store(config$workspace);on.exit(brohn_close_store(store))
  reports<-lapply(config$cases,function(x){report<-brohn_get_entity(store,"report",x$report_id)
    list(id=report$id,hash=brohn_hash(report$body),artifact_hash=digest::digest(file=brohn_object_path(store,x$artifact$hash),algo="sha256"),
      original_source_hash=digest::digest(file=brohn_object_path(store,x$source$hash),algo="sha256"))})
  brohn_write_json_file(list(reports=reports,jobs=brohn_list_jobs(store,limit=500L),frames=brohn_list_entities(store,"vision_frame",limit=100L),
    retries=brohn_list_entities(store,"job_retry",limit=100L)),file.path(folder,"inspection.json"))
})else stop("Unknown saved-video browser fixture mode.")
