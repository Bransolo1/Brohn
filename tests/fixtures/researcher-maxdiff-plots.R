args<-commandArgs(trailingOnly=TRUE);folder<-normalizePath(args[[2]],winslash="/",mustWork=TRUE)
stopifnot(startsWith(basename(folder),"brohn-maxdiff-plots-"));source("R/platform-load.R",encoding="UTF-8");brohn_load()
file<-file.path(folder,"workspace.json")
if(args[[1]]=="setup")local({
  stopifnot(!file.exists(file));source("tests/fixtures/maxdiff-plots.R");f<-brohn_original_maxdiff_plot_fixture()
  s<-brohn_open_store(file.path(folder,"workspace"));on.exit(brohn_close_store(s));brohn_initialise_library(s)
  study<-brohn_create_study(s,"Original best-worst charts","survey");id<-brohn_id("report")
  r<-brohn_put_entity(s,"report",id,list(id=id,title="Original best-worst chart evidence",study_id=study$id,origin="sample",status="Available",created_at=brohn_now(),
    analysis=list(kind="maxdiff",quality=list(source_exercises=2),choice_tasks=list(f$result,f$empty),limitations=list("Original synthetic choice counts; no real participant inference."))))
  brohn_write_json_file(list(workspace=s$root,study_id=study$id,report_id=id,port=httpuv::randomPort(min=20000L,max=49000L)),file)
}) else if(args[[1]]=="serve"){
  c<-brohn_read_json_file(file);Sys.setenv(BROHN_WORKSPACE=c$workspace,BROHN_APP_MODE="platform")
  stop_owned<-function()if(file.exists(file.path(folder,"stop.request")))shiny::stopApp()else later::later(stop_owned,.2)
  later::later(stop_owned,.2);shiny::runApp(".",host="127.0.0.1",port=c$port,launch.browser=FALSE)
}else stop("Unknown mode")
