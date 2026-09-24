# Isolated original consumer-comparison browser fixture. Studies, participants
# and closure actions are created through the real UI, never injected here.
args<-commandArgs(trailingOnly=TRUE);mode<-args[[1L]]
source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=TRUE)
folder<-normalizePath(args[[2L]],winslash="/",mustWork=TRUE)
stopifnot(startsWith(basename(folder),"brohn-collection-browser-"))
config_path<-file.path(folder,"fixture.json")
if(mode %in% c("researcher","participant")) {
  config<-brohn_read_json_file(config_path)
  if(mode=="researcher") {
    Sys.setenv(BROHN_WORKSPACE=config$workspace,BROHN_APP_MODE="platform",BROHN_PARTICIPANT_PORT=config$participant_port)
    stop_owned<-function()if(file.exists(file.path(folder,"stop.researcher")))shiny::stopApp()else later::later(stop_owned,.2)
    later::later(stop_owned,.2);shiny::runApp(".",host="127.0.0.1",port=config$researcher_port,launch.browser=FALSE)
  } else {
    store<-brohn_open_store(config$workspace);server<-httpuv::startServer("127.0.0.1",config$participant_port,brohn_delivery_app(store))
    while(!file.exists(file.path(folder,"stop.participant")))httpuv::service(50)
    httpuv::stopServer(server);brohn_close_store(store)
  }
} else local({
  store<-brohn_open_store(file.path(folder,"workspace"));on.exit(brohn_close_store(store),add=TRUE)
  if(mode=="setup") {
    stopifnot(!file.exists(config_path));brohn_initialise_library(store)
    brohn_write_json_file(list(schema="brohn-collection-browser/1.0",workspace=store$root,researcher_port=3891L,participant_port=3892L),config_path)
  } else if(mode=="inspect") {
    runs<-brohn_runs(store)
    brohn_write_json_file(list(studies=brohn_list_entities(store,"study"),releases=brohn_deployments(store),runs=runs,
      events=setNames(lapply(runs,function(r)brohn_run_events(store,r$id)),vapply(runs,`[[`,character(1),"id")),
      jobs=brohn_list_jobs(store),reports=brohn_list_entities(store,"report"),collections=brohn_list_entities(store,"collection")),file.path(folder,"snapshot.json"))
  } else if(mode=="analyse") {
    job<-brohn_claim_job(store,"collection-browser-worker",90)
    stopifnot(!is.null(job),job$operation=="analyse_run")
    brohn_process_job(store,job,timeout_seconds=180)
    result<-brohn_get_job(store,job$id);if(result$status!="succeeded")stop(brohn_json(result$error))
    brohn_write_json_file(result,file.path(folder,"worker-result.json"))
  } else stop("Unknown collection fixture mode")
})
