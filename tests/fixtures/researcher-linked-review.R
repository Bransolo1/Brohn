# Original source is generated independently in Python and imported in the UI.
args<-commandArgs(trailingOnly=TRUE);mode<-args[[1L]]
source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=TRUE)
folder<-normalizePath(args[[2L]],winslash="/",mustWork=TRUE)
stopifnot(startsWith(basename(folder),"brohn-linked-browser-"))
config_path<-file.path(folder,"fixture.json")
if(mode=="researcher") {
  config<-brohn_read_json_file(config_path)
  Sys.setenv(BROHN_WORKSPACE=config$workspace,BROHN_APP_MODE="platform")
  stop_owned<-function()if(file.exists(file.path(folder,"stop.researcher")))shiny::stopApp()else later::later(stop_owned,.2)
  later::later(stop_owned,.2);shiny::runApp(".",host="127.0.0.1",port=config$port,launch.browser=FALSE)
} else local({
  store<-brohn_open_store(file.path(folder,"workspace"));on.exit(brohn_close_store(store),add=TRUE)
  if(mode=="setup") {
    stopifnot(!file.exists(config_path));brohn_initialise_library(store)
    brohn_write_json_file(list(schema="brohn-linked-browser/1.0",workspace=store$root,port=3901L),config_path)
  } else if(mode=="inspect") {
    brohn_write_json_file(list(studies=brohn_list_entities(store,"study"),datasets=brohn_list_entities(store,"dataset"),
      imports=brohn_list_entities(store,"stream_import"),streams=brohn_list_entities(store,"stream"),
      reviews=brohn_list_entities(store,"linked_review"),jobs=brohn_list_jobs(store)),file.path(folder,"snapshot.json"))
  } else if(mode=="worker") {
    while(!file.exists(file.path(folder,"stop.worker"))) {
      job<-brohn_claim_job(store,"linked-browser-worker",90)
      if(is.null(job))Sys.sleep(.2)else {
        brohn_process_job(store,job,timeout_seconds=300)
        cat(brohn_json(list(id=job$id,status=brohn_get_job(store,job$id)$status)),"\n")
      }
    }
  } else stop("Unknown linked fixture mode")
})
