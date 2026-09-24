# Actual isolated researcher/participant services; all media are original fixtures.
args<-commandArgs(trailingOnly=TRUE);stopifnot(length(args)==2L);mode<-args[[1]]
source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=TRUE)
folder<-normalizePath(args[[2]],winslash="/",mustWork=TRUE);stopifnot(startsWith(basename(folder),"brohn-audio-extract-browser-"))
cp<-file.path(folder,"fixture.json")
if(mode%in%c("researcher","participant")){
  config<-brohn_read_json_file(cp)
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
    stopifnot(!file.exists(cp));brohn_initialise_library(store);media<-file.path(folder,"media");dir.create(media)
    processx::run(brohn_python_profile("audio"),c("tests/fixtures/audio-extraction-media.py",media),timeout=120,windows_hide_window=TRUE)
    sources<-lapply(c("multiple","no-audio","gap"),function(kind){r<-brohn_ingest_dataset(store,file.path(media,paste0(kind,".mkv")),paste("Original extraction",kind),"video",origin="sample")
      list(kind=kind,id=r$id,revision=r$revision,hash=brohn_hash(r$body),source_hash=r$body$source$hash)})
    d<-brohn_new_design("Original camera audio extraction","survey");d$instructions<-"Observe the original fictional product question."
    d$questions<-list(brohn_question("Original final product liking",scope="end"))
    d$camera<-list(schema="brohn-camera-policy/1.0",required=TRUE,audio=TRUE,consent_text="Record the original generated test pattern and analytic tone for isolated software QA.",
      retention_text="Only this temporary original QA workspace. No person or microphone recording is involved.",width=320L,height=240L,frame_rate=15L,max_duration_s=90,max_bytes=16*1024^2,analysis_profile="none")
    brohn_put_entity(store,"study",d$id,d);release<-brohn_publish(store,d$id,origin="sample",quota=10L,alias_required=TRUE)
    brohn_write_json_file(list(workspace=store$root,researcher_port=3923L,participant_port=3924L,sources=sources,media=media,
      study_id=d$id,participant_url=paste0("http://127.0.0.1:3924/participant/?token=",release$token)),cp)
  }else if(mode=="worker"){
    while(!file.exists(file.path(folder,"stop.worker"))){j<-brohn_claim_job(store,"audio-extraction-browser",120);if(is.null(j))Sys.sleep(.2)else{
      brohn_process_job(store,j,timeout_seconds=300);done<-brohn_get_job(store,j$id);cat(brohn_json(done[c("id","operation","status","error")]),"\n")}}
  }else if(mode=="inspect"){
    config<-brohn_read_json_file(cp);datasets<-brohn_list_entities(store,"dataset",limit=1000L)
    reports<-brohn_list_entities(store,"report",limit=1000L)
    brohn_write_json_file(list(datasets=datasets,extractions=brohn_list_entities(store,"audio_extraction",limit=1000L),
      reviews=brohn_list_entities(store,"audio_review",limit=1000L),reports=lapply(reports,function(r)list(id=r$id,dataset_id=r$body$dataset_id,hash=brohn_hash(r$body),body=r$body)),
      jobs=lapply(brohn_list_jobs(store,limit=1000L),function(j)j[c("id","operation","status","request","result","error")]),
      original_sources=lapply(config$sources,function(ref){r<-brohn_get_entity(store,"dataset",ref$id,ref$revision);list(id=r$id,unchanged=identical(brohn_hash(r$body),ref$hash)&&
        identical(digest::digest(file=brohn_object_path(store,r$body$source$hash),algo="sha256"),ref$source_hash))}),
      runs=lapply(brohn_runs(store),function(r){c<-brohn_capture(store,run_id=r$id);list(id=r$id,status=r$completion_status,transfer=r$transfer_status,capture=c,
        publication=if(is.null(c))NULL else brohn_get_entity(store,"camera_capture",c$id))})),file.path(folder,"snapshot.json"))
  }else stop("Unknown extraction fixture mode")
})
