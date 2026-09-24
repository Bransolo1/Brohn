# Empty software-only workspace for real authoring, participant camera and native processing.
args<-commandArgs(trailingOnly=TRUE);mode<-args[[1L]]
source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=TRUE)
folder<-normalizePath(args[[2L]],winslash="/",mustWork=TRUE)
stopifnot(startsWith(basename(folder),"brohn-camera-facial-browser-"));config_path<-file.path(folder,"fixture.json")
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
  original<-normalizePath("C:/Users/User/Documents/Codex/2026-09-20/oka/work/brohn-vision-references-01/face/business-person.png",winslash="/",mustWork=TRUE)
  sha<-digest::digest(file=original,algo="sha256");stopifnot(sha=="1f61cf0603cef77ffca4e24848ddf8290b5651d03b957e93b742c9ef963b5c11")
  movie<-file.path(folder,"licensed-repeated-face-software-camera.y4m")
  processx::run(Sys.which("ffmpeg"),c("-nostdin","-v","error","-loop","1","-i",original,"-vf","scale=640:454,pad=640:480:0:13:black,format=yuv420p","-r","5","-t","30","-an","-f","yuv4mpegpipe","-n",movie),timeout=60000,windows_hide_window=TRUE)
  brohn_write_json_file(list(schema="brohn-camera-facial-browser/1.0",workspace=store$root,researcher_port=3947L,participant_port=3948L,
    original_image=original,original_hash=sha,movie=movie,movie_hash=digest::digest(file=movie,algo="sha256"),
    title="Fictional packaging camera and liking",origin="Apache2 MediaPipe licensed still, repeated into a clearly identified software fake-camera fixture; not an actual research participant."),config_path)
 }else if(mode=="worker"){
  while(!file.exists(file.path(folder,"stop.worker"))){j<-brohn_claim_job(store,"camera-facial-browser",90)
   if(is.null(j))Sys.sleep(.2)else{brohn_process_job(store,j,timeout_seconds=1900);cat(brohn_json(list(id=j$id,status=brohn_get_job(store,j$id)$status)),"\n")}}
 }else if(mode=="inspect"){
  records<-lapply(brohn_runs(store),function(run){
   capture<-brohn_capture(store,run_id=run$id);publication<-if(!is.null(capture))brohn_get_entity(store,"camera_capture",capture$id)else NULL
   dataset<-if(!is.null(publication))brohn_get_entity(store,"dataset",publication$body$dataset_id)else NULL
   chunks<-if(!is.null(capture))brohn_rows(DBI::dbGetQuery(store$con,"SELECT sequence,content_hash,object_hash,observation_hash,byte_count FROM camera_chunks WHERE capture_id=? ORDER BY sequence",params=list(capture$id)))else list()
   list(run=run,events=brohn_run_events(store,run$id),capture=capture,publication=publication,dataset=dataset,chunks=chunks,
    source_path=if(!is.null(dataset))brohn_object_path(store,dataset$body$source$hash,verify=TRUE)else NULL,
    authority=if(!is.null(dataset)&&run$completion_status=="completed"&&capture$status=="completed")brohn_camera_analysis_resolve(store,dataset,"automatic",TRUE)else NULL)
  })
  reports<-brohn_list_entities(store,"report",limit=100L)
  brohn_write_json_file(list(studies=brohn_list_entities(store,"study",limit=100L),sessions=records,reports=reports,jobs=brohn_list_jobs(store,limit=100L),
   report_integrity=lapply(reports,function(r){checked<-brohn_report_for_review(store,r$id);list(id=r$id,hash=brohn_hash(checked$body))})),file.path(folder,"snapshot.json"))
 }else stop("Unknown camera facial fixture mode")
})
