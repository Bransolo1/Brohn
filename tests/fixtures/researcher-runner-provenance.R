# Historical fixture is explicitly synthetic; new publication/response/report
# are collected through actual researcher and participant browsers.
args<-commandArgs(trailingOnly=TRUE);mode<-args[[1L]]
source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=TRUE)
folder<-normalizePath(args[[2L]],winslash="/",mustWork=TRUE)
stopifnot(startsWith(basename(folder),"brohn-runner-provenance-browser-"))
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
    study<-brohn_create_study(store,"Original participant code history","survey")
    d<-study$body;d$instructions<-"";d$participant_equipment<-NULL
    d$questions<-list(brohn_question("How much do you like the original concept?","rating","end","original-code-history-rating"))
    d$consent$text<-"Original automated software QA only. No human observations or camera recording."
    study<-brohn_save_study(store,d,study$revision)
    legacy<-.brohn_publish_release(store,study$id,"sample")
    old<-.brohn_delivery_start(store,legacy$token,list(consented=TRUE,client_id="synthetic-historical-client",participant_alias="SYNTHETIC-HISTORIC",operation_id="synthetic-historical-start"))
    .brohn_delivery_finish(store,old$run_id,old$access_token,list(outcome="withdrawn",final_sequence=0,operation_id="synthetic-historical-withdrawal"))
    brohn_deployment_state(store,legacy$id,"closed")
    review<-brohn_collection_review(store,legacy$id,study$id,study$project_id)
    collection<-brohn_finalize_collection(store,legacy$id,study$id,study$project_id,review$hash)
    brohn_write_json_file(list(schema="brohn-researcher-runner-provenance/1.0",workspace=store$root,researcher_port=3951L,participant_port=3952L,
      study_id=study$id,title=study$body$title,project_id=study$project_id,legacy_release=legacy$id,legacy_run=old$run_id,legacy_collection=collection$id),config_path)
  }else if(mode=="inspect"){
    cfg<-brohn_read_json_file(config_path);runs<-brohn_runs(store,cfg$study_id);reports<-brohn_list_entities(store,"report",limit=100L)
    brohn_write_json_file(list(study=brohn_study(store,cfg$study_id),releases=brohn_deployments(store,cfg$study_id),
      sessions=lapply(runs,function(r)list(run=r,events=brohn_run_events(store,r$id),
        receipts=brohn_rows(DBI::dbGetQuery(store$con,"SELECT * FROM delivery_receipts WHERE scope=? ORDER BY operation,operation_id",params=list(r$id))))),
      reports=reports,jobs=brohn_list_jobs(store,limit=100L),collections=brohn_list_entities(store,"collection",limit=100L),
      runtimes=if(DBI::dbExistsTable(store$con,"delivery_runtimes"))brohn_rows(DBI::dbGetQuery(store$con,"SELECT * FROM delivery_runtimes ORDER BY deployment_id"))else list(),
      assignments=if(DBI::dbExistsTable(store$con,"delivery_run_runtimes"))brohn_rows(DBI::dbGetQuery(store$con,"SELECT * FROM delivery_run_runtimes ORDER BY run_id"))else list()),file.path(folder,"snapshot.json"))
  }else stop("Unknown participant-code provenance fixture mode")
})
