# Isolated real researcher service/worker; imports are performed through the browser.
args<-commandArgs(trailingOnly=TRUE);stopifnot(length(args)==2L);mode<-args[[1]]
source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=TRUE)
folder<-normalizePath(args[[2]],winslash="/",mustWork=TRUE);stopifnot(startsWith(basename(folder),"brohn-media-review-browser-"));cp<-file.path(folder,"fixture.json")
if(mode=="researcher"){
  config<-brohn_read_json_file(cp);Sys.setenv(BROHN_WORKSPACE=config$workspace,BROHN_APP_MODE="platform",BROHN_PARTICIPANT_PORT=3964L)
  stop_owned<-function()if(file.exists(file.path(folder,"stop.researcher")))shiny::stopApp()else later::later(stop_owned,.2)
  later::later(stop_owned,.2);shiny::runApp(".",host="127.0.0.1",port=config$researcher_port,launch.browser=FALSE)
}else local({
  store<-brohn_open_store(file.path(folder,"workspace"));on.exit(brohn_close_store(store),add=TRUE)
  if(mode=="setup"){
    stopifnot(!file.exists(cp));brohn_initialise_library(store);media<-file.path(folder,"media");dir.create(media)
    processx::run(brohn_python_profile("audio"),c("tests/fixtures/media-review-media.py",media),timeout=120,windows_hide_window=TRUE)
    brohn_write_json_file(list(workspace=store$root,researcher_port=3963L,media=media),cp)
  }else if(mode=="worker"){
    while(!file.exists(file.path(folder,"stop.worker"))){j<-brohn_claim_job(store,"media-review-browser",120);if(is.null(j))Sys.sleep(.2)else{
      brohn_process_job(store,j,timeout_seconds=300);done<-brohn_get_job(store,j$id);cat(brohn_json(done[c("id","operation","status","error")]),"\n")}}
  }else if(mode=="inspect"){
    datasets<-brohn_list_entities(store,"dataset",limit=1000L);reports<-brohn_list_entities(store,"report",limit=1000L)
    brohn_write_json_file(list(datasets=lapply(datasets,function(r)list(id=r$id,revision=r$revision,hash=brohn_hash(r$body),body=r$body)),
      extractions=brohn_list_entities(store,"audio_extraction",limit=1000L),audio_reviews=brohn_list_entities(store,"audio_review",limit=1000L),
      media_reviews=brohn_list_entities(store,"media_review",limit=1000L),reports=lapply(reports,function(r)list(id=r$id,dataset_id=r$body$dataset_id,hash=brohn_hash(r$body),body=r$body)),
      jobs=lapply(brohn_list_jobs(store,limit=1000L),function(j)j[c("id","operation","status","attempt","request","result","error")])),file.path(folder,"snapshot.json"))
  }else stop("Unknown media fixture mode")
})
