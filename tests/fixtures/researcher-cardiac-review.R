# Isolated copy of retained public-reference inputs; never alters original bytes.
args<-commandArgs(trailingOnly=TRUE);mode<-args[[1]];folder<-normalizePath(args[[2]],winslash="/",mustWork=TRUE)
stopifnot(startsWith(basename(folder),"brohn-cardiac-review-browser-"))
source("R/platform-load.R",encoding="UTF-8");brohn_load()
config_path<-file.path(folder,"fixture.json")
if(mode=="setup")local({
  original<-normalizePath(args[[3]],winslash="/",mustWork=TRUE);proof<-brohn_read_json_file(file.path(original,"acceptance.json"))
  stopifnot(length(proof$checks)>=22L,!file.exists(config_path),!dir.exists(file.path(folder,"workspace")),file.copy(proof$workspace,folder,recursive=TRUE))
  brohn_write_json_file(list(workspace=normalizePath(file.path(folder,"workspace"),winslash="/"),port=httpuv::randomPort(min=20000L,max=49000L),reports=proof$reports,source=original),config_path)
})else if(mode=="serve"){
  config<-brohn_read_json_file(config_path);Sys.setenv(BROHN_WORKSPACE=config$workspace,BROHN_APP_MODE="platform")
  stop_owned<-function()if(file.exists(file.path(folder,"stop.request")))shiny::stopApp()else later::later(stop_owned,.2)
  later::later(stop_owned,.2);shiny::runApp(".",host="127.0.0.1",port=config$port,launch.browser=FALSE)
}else if(mode=="worker")local({
  config<-brohn_read_json_file(config_path);store<-brohn_open_store(config$workspace);on.exit(brohn_close_store(store))
  repeat{if(file.exists(file.path(folder,"stop.request")))break
    job<-brohn_claim_job(store,"cardiac-review-browser",300)
    if(is.null(job))Sys.sleep(.2)else brohn_process_job(store,job,timeout_seconds=300)}
})else if(mode=="inspect")local({
  config<-brohn_read_json_file(config_path);store<-brohn_open_store(config$workspace);on.exit(brohn_close_store(store))
  brohn_write_json_file(list(reviews=brohn_list_entities(store,"cardiac_review",limit=100L),previews=brohn_list_entities(store,"cardiac_review_preview",limit=100L),
    reports=brohn_list_entities(store,"report",limit=100L),jobs=brohn_list_jobs(store)),file.path(folder,"inspection.json"))
})else stop("Unknown fixture mode")
