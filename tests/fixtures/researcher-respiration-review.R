# Isolated original synthetic source, researcher import and supervised workers.
args<-commandArgs(trailingOnly=TRUE);stopifnot(length(args)>=2L)
mode<-args[[1]];folder<-normalizePath(args[[2]],winslash="/",mustWork=TRUE)
stopifnot(startsWith(basename(folder),"brohn-respiration-review-browser-"))
source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=TRUE)
config_path<-file.path(folder,"fixture.json")
if(mode=="serve") {
  config<-brohn_read_json_file(config_path);Sys.setenv(BROHN_WORKSPACE=config$workspace,BROHN_APP_MODE="platform")
  stop_owned<-function()if(file.exists(file.path(folder,"stop.request")))shiny::stopApp()else later::later(stop_owned,.2)
  later::later(stop_owned,.2);shiny::runApp(".",host="127.0.0.1",port=config$port,launch.browser=FALSE)
}else local({
  store<-brohn_open_store(file.path(folder,"workspace"));on.exit(brohn_close_store(store),add=TRUE)
  if(mode=="setup") {
    stopifnot(!file.exists(config_path));brohn_initialise_library(store)
    time<-(0:35999)/50;phase<-time%%5
    volume<-ifelse(phase<2,(1-cos(pi*phase/2))/2,(1+cos(pi*(phase-2)/3))/2)
    volume[c(18001L,35001L)]<-NA
    source<-file.path(folder,"original-negative-volume.csv")
    utils::write.csv(data.frame(time=time,participant="SYNTHETIC-P1",session="SYNTHETIC-S1",volume=-volume),source,row.names=FALSE,na="NA",fileEncoding="UTF-8")
    brohn_write_json_file(list(workspace=store$root,port=as.integer(Sys.getenv("BROHN_RESPIRATION_REVIEW_TEST_PORT","3927")),source=source,source_hash=digest::digest(file=source,algo="sha256"),
      origin="original_synthetic",samples=36000,sampling_rate=50,expected=list(inspiration_s=2,expiration_s=3,rate_breaths_per_minute=12,missing_s=list(360,700))),config_path)
  }else if(mode=="worker") {
    while(!file.exists(file.path(folder,"stop.worker"))){j<-brohn_claim_job(store,"respiration-review-browser-fixture",90)
      if(is.null(j))Sys.sleep(.2)else {brohn_process_job(store,j,timeout_seconds=300);cat(brohn_json(list(id=j$id,status=brohn_get_job(store,j$id)$status)),"\n")}}
  }else if(mode=="inspect") {
    brohn_write_json_file(list(reports=brohn_list_entities(store,"report"),reviews=brohn_list_entities(store,"respiration_review"),datasets=brohn_list_entities(store,"dataset"),jobs=brohn_list_jobs(store)),file.path(folder,"snapshot.json"))
  }else stop("Unknown RESPIRATION review fixture mode")
})
