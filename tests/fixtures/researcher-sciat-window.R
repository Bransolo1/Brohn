# Empty, original synthetic workspace. Every study/session is authored in browser.
args<-commandArgs(trailingOnly=TRUE);mode<-args[[1L]]
source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=TRUE)
folder<-normalizePath(args[[2L]],winslash="/",mustWork=TRUE)
stopifnot(startsWith(basename(folder),"brohn-researcher-sciat-window-"))
config_path<-file.path(folder,"fixture.json")
if(mode %in% c("researcher","participant")){
  cfg<-brohn_read_json_file(config_path)
  if(mode=="researcher"){
    Sys.setenv(BROHN_WORKSPACE=cfg$workspace,BROHN_APP_MODE="platform",BROHN_PARTICIPANT_PORT=cfg$participant_port)
    stop_owned<-function()if(file.exists(file.path(folder,"stop.researcher")))shiny::stopApp()else later::later(stop_owned,.2)
    later::later(stop_owned,.2);shiny::runApp(".",host="127.0.0.1",port=cfg$researcher_port,launch.browser=FALSE)
  }else{
    store<-brohn_open_store(cfg$workspace);server<-httpuv::startServer("127.0.0.1",cfg$participant_port,brohn_delivery_app(store))
    while(!file.exists(file.path(folder,"stop.participant")))httpuv::service(50)
    httpuv::stopServer(server);brohn_close_store(store)
  }
}else local({
  store<-brohn_open_store(file.path(folder,"workspace"));on.exit(brohn_close_store(store),add=TRUE)
  if(mode=="setup"){
    stopifnot(!file.exists(config_path));brohn_initialise_library(store)
    brohn_write_json_file(list(schema="brohn-researcher-sciat-window/1.0",workspace=store$root,researcher_port=3943L,participant_port=3944L,
      title="Original fictional product SC-IAT journey"),config_path)
  }else if(mode=="inspect"){
    studies<-brohn_list_entities(store,"study",limit=100L);runs<-brohn_runs(store);reports<-brohn_list_entities(store,"report",limit=100L)
    records<-lapply(runs,function(r)list(run=r,events=brohn_run_events(store,r$id),
      receipts=brohn_rows(DBI::dbGetQuery(store$con,"SELECT * FROM delivery_receipts WHERE scope=? ORDER BY operation,operation_id",params=list(r$id)))))
    releases<-unlist(lapply(studies,function(s)brohn_deployments(store,s$id)),recursive=FALSE)
    brohn_write_json_file(list(studies=studies,sessions=records,releases=releases,jobs=brohn_list_jobs(store,limit=100L),reports=reports,
      templates=brohn_list_entities(store,"template",limit=100L),datasets=brohn_list_entities(store,"dataset",limit=100L),
      report_integrity=lapply(reports,function(r){p<-brohn_object_path(store,r$body$result_object$hash,verify=TRUE);e<-brohn_read_json_file(p)
        list(id=r$id,hash=digest::digest(file=p,algo="sha256"),exact=identical(brohn_hash(e$report),brohn_hash(r$body[setdiff(names(r$body),"result_object")]))) })),
      file.path(folder,"snapshot.json"))
  }else stop("Unknown SC-IAT fixture mode")
})
