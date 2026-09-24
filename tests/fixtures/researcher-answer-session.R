# Original synthetic study; all participant events come from the actual browser.
args<-commandArgs(trailingOnly=TRUE);mode<-args[[1L]]
source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=TRUE)
folder<-normalizePath(args[[2L]],winslash="/",mustWork=TRUE);stopifnot(startsWith(basename(folder),"brohn-answer-session-browser-"))
config_path<-file.path(folder,"fixture.json")
if(mode %in% c("researcher","participant")){
  config<-brohn_read_json_file(config_path)
  if(mode=="researcher"){
    Sys.setenv(BROHN_WORKSPACE=config$workspace,BROHN_APP_MODE="platform",BROHN_PARTICIPANT_PORT=config$participant_port)
    stop_owned<-function()if(file.exists(file.path(folder,"stop.researcher")))shiny::stopApp()else later::later(stop_owned,.2)
    later::later(stop_owned,.2);shiny::runApp(".",host="127.0.0.1",port=config$researcher_port,launch.browser=FALSE)
  }else{
    store<-brohn_open_store(config$workspace);server<-httpuv::startServer("127.0.0.1",config$participant_port,brohn_delivery_app(store))
    while(!file.exists(file.path(folder,"stop.participant")))httpuv::service(50)
    httpuv::stopServer(server);brohn_close_store(store)
  }
}else local({
  store<-brohn_open_store(file.path(folder,"workspace"));on.exit(brohn_close_store(store),add=TRUE)
  if(mode=="setup"){
    stopifnot(!file.exists(config_path));brohn_initialise_library(store)
    d<-brohn_new_design("Original answer to session consumer journey","survey");d$participant_equipment<-NULL;d$instructions<-"Answer the original fictional product questions. No real participant is involved."
    driver<-brohn_question("Would you describe the original concept?","single_choice","end","original-driver")
    driver$options<-list(list(id="show",label="Show detail",value=TRUE),list(id="skip",label="Skip detail",value=FALSE))
    detail<-brohn_question("Original optional concept detail","long_text","end","original-detail");detail$show_if<-list(op="equals",question_id=driver$id,value=TRUE)
    liking<-brohn_question("Original liking from zero to ten","number","end","original-liking");liking$min<-0;liking$max<-10;liking$step<-1
    d$questions<-list(driver,detail,liking);d$questionnaire_navigation<-brohn_questionnaire_navigation()
    brohn_put_entity(store,"study",d$id,d,project_id="default")
    brohn_write_json_file(list(schema="brohn-answer-session-browser/1.0",workspace=store$root,researcher_port=3925L,participant_port=3926L,study_id=d$id,study_title=d$title),config_path)
  }else if(mode=="inspect"){
    runs<-brohn_runs(store)
    records<-lapply(runs,function(r)list(run=r,events=brohn_run_events(store,r$id),receipts=brohn_rows(DBI::dbGetQuery(store$con,"SELECT * FROM delivery_receipts WHERE scope=? ORDER BY operation,operation_id",params=list(r$id))),resolution=brohn_session_resolution(store,r$id)))
    brohn_write_json_file(list(sessions=records,jobs=brohn_list_jobs(store),reports=brohn_list_entities(store,"report"),indexes=brohn_list_entities(store,"questionnaire_index"),reviews=brohn_list_entities(store,"answer_session")),file.path(folder,"snapshot.json"))
  }else stop("Unknown fixture mode")
})
