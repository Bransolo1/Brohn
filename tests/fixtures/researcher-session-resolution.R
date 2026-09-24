# Only creates original fixture designs. Participant journals, recording bytes,
# researcher decisions and analysis requests are produced by connected browsers.
args<-commandArgs(trailingOnly=TRUE);mode<-args[[1L]]
source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=TRUE)
folder<-normalizePath(args[[2L]],winslash="/",mustWork=TRUE)
stopifnot(startsWith(basename(folder),"brohn-session-browser-"))
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
    studies<-lapply(c("camera","completion"),function(kind){
      d<-brohn_new_design(paste("Original recovery",kind),"survey");d$participant_equipment<-NULL
      d$description<-"Original automated consumer response recovery fixture. No natural participant, emotion or device qualification claims."
      d$instructions<-"Read the original fictional product question, then give your answer."
      q<-brohn_question("Original product liking from zero to ten","number","end");q$min<-0;q$max<-10;q$step<-1;d$questions<-list(q)
      if(kind=="camera"){q2<-q;q2$id<-brohn_id("q");q2$prompt<-"Another original product question";d$questions<-c(d$questions,list(q2))}
      if(kind=="camera")d$camera<-list(schema="brohn-camera-policy/1.0",required=TRUE,audio=FALSE,
        consent_text="Record only the original synthetic browser camera test pattern during this automated fixture.",retention_text="Retained only in this isolated QA workspace. No person or microphone is recorded.",
        width=640,height=480,frame_rate=15,max_duration_s=120,max_bytes=16*1024^2,analysis_profile="none")
      brohn_put_entity(store,"study",d$id,d,project_id="default");list(id=d$id,kind=kind)
    })
    brohn_write_json_file(list(schema="brohn-session-browser/1.0",workspace=store$root,researcher_port=3883L,participant_port=3884L,studies=studies),config_path)
  } else if(mode=="inspect") {
    runs<-brohn_runs(store)
    details<-lapply(runs,function(r){capture<-brohn_capture(store,run_id=r$id)
      chunks<-if(is.null(capture))list()else brohn_rows(DBI::dbGetQuery(store$con,"SELECT sequence,content_hash,object_hash,observation_hash,byte_count FROM camera_chunks WHERE capture_id=? ORDER BY sequence",params=list(capture$id)))
      for(chunk in chunks)brohn_object_path(store,chunk$object_hash,verify=TRUE)
      list(run=r,protocol=brohn_run_protocol(store,r$id,r$study_id,"default"),events=brohn_run_events(store,r$id),
        original_receipts=brohn_rows(DBI::dbGetQuery(store$con,"SELECT * FROM delivery_receipts WHERE scope=? ORDER BY operation,operation_id",params=list(r$id))),capture=capture,chunks=chunks,
        resolution=brohn_session_resolution(store,r$id))
    })
    brohn_write_json_file(list(studies=brohn_list_entities(store,"study"),releases=brohn_deployments(store),sessions=details,
      jobs=brohn_list_jobs(store),reports=brohn_list_entities(store,"report"),collections=brohn_list_entities(store,"collection")),file.path(folder,"snapshot.json"))
  } else if(mode=="analyse") {
    job<-brohn_claim_job(store,"session-resolution-browser-worker",90)
    stopifnot(!is.null(job),job$operation=="analyse_resolved_run")
    brohn_process_job(store,job,timeout_seconds=180)
    result<-brohn_get_job(store,job$id);brohn_write_json_file(result,file.path(folder,"worker-result.json"))
    if(result$status!="succeeded")stop(brohn_json(result$error))
  } else if(mode=="backup") {
    backup<-brohn_backup_workspace(store,file.path(folder,"backup"));brohn_restore_workspace(backup$path,file.path(folder,"restored"))
    restored<-brohn_open_store(file.path(folder,"restored"));on.exit(brohn_close_store(restored),add=TRUE)
    resolutions<-brohn_list_entities(store,"session_resolution");collections<-brohn_list_entities(store,"collection")
    for(r in resolutions)stopifnot(identical(brohn_hash(r$body),brohn_hash(brohn_get_entity(restored,"session_resolution",r$id)$body)))
    for(r in collections)stopifnot(identical(brohn_hash(r$body),brohn_hash(brohn_get_entity(restored,"collection",r$id)$body)))
    brohn_write_json_file(list(passed=TRUE,paused=brohn_workspace_execution_status(restored)$paused,resolutions=length(resolutions),collections=length(collections)),file.path(folder,"restore-result.json"))
  } else stop("Unknown session recovery fixture mode")
})
