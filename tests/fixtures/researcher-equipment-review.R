args<-commandArgs(trailingOnly=TRUE);mode<-args[[1]];source_folder<-normalizePath(args[[2]],winslash="/",mustWork=TRUE);output<-normalizePath(args[[3]],winslash="/",mustWork=TRUE)
stopifnot(startsWith(basename(source_folder),"brohn-participant-equipment-"),startsWith(basename(output),"brohn-equipment-review-"))
source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=TRUE)
if(mode=="serve"){
  config<-brohn_read_json_file(file.path(output,"fixture.json"));Sys.setenv(BROHN_WORKSPACE=file.path(source_folder,"workspace"),BROHN_APP_MODE="platform")
  stop_owned<-function()if(file.exists(file.path(output,"stop.researcher")))shiny::stopApp()else later::later(stop_owned,.2)
  later::later(stop_owned,.2);shiny::runApp(".",host="127.0.0.1",port=config$port,launch.browser=FALSE)
}else local({store<-brohn_open_store(file.path(source_folder,"workspace"));on.exit(brohn_close_store(store),add=TRUE)
  if(mode=="prepare"){
    brohn_initialise_library(store)
    releases<-brohn_read_json_file(file.path(source_folder,"fixture.json"));clone<-brohn_clone_study(store,releases$camera$study_id)
    brohn_write_json_file(list(port=httpuv::randomPort(min=20000L,max=34000L),clone=clone,releases=releases,runs=brohn_runs(store)),file.path(output,"fixture.json"))
  }else if(mode=="inspect")brohn_write_json_file(list(studies=brohn_studies(store)),file.path(output,"snapshot.json"))else stop("Unknown equipment review mode")
})
