# Isolated original synthetic source, researcher import and supervised workers.
args<-commandArgs(trailingOnly=TRUE);stopifnot(length(args)>=2L)
mode<-args[[1]];folder<-normalizePath(args[[2]],winslash="/",mustWork=TRUE)
stopifnot(startsWith(basename(folder),"brohn-emg-review-browser-"))
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
    time<-(0:32599)/500;phase<-time%%1
    amplitude<-ifelse(phase<.5,.02,.002);voltage<-amplitude*sin(2*pi*80*time)
    voltage[c(30001L,32501L)]<-NA
    source<-file.path(folder,"original-modulated-emg-mv.csv")
    utils::write.csv(data.frame(time=time,participant="SYNTHETIC-P1",session="SYNTHETIC-S1",voltage=voltage),source,row.names=FALSE,na="NA",fileEncoding="UTF-8")
    brohn_write_json_file(list(workspace=store$root,port=as.integer(Sys.getenv("BROHN_EMG_REVIEW_TEST_PORT","3931")),source=source,source_hash=digest::digest(file=source,algo="sha256"),
      origin="original_synthetic",samples=32600,sampling_rate=500,expected=list(carrier_hz=80,active_peak_uv=20,inactive_peak_uv=2,period_s=1,active_duration_s=.5,threshold_uv=8,missing_s=list(60,65))),config_path)
  }else if(mode=="worker") {
    while(!file.exists(file.path(folder,"stop.worker"))){j<-brohn_claim_job(store,"emg-review-browser-fixture",90)
      if(is.null(j))Sys.sleep(.2)else {brohn_process_job(store,j,timeout_seconds=300);cat(brohn_json(list(id=j$id,status=brohn_get_job(store,j$id)$status)),"\n")}}
  }else if(mode=="inspect") {
    brohn_write_json_file(list(reports=brohn_list_entities(store,"report"),reviews=brohn_list_entities(store,"emg_review"),datasets=brohn_list_entities(store,"dataset"),jobs=brohn_list_jobs(store)),file.path(folder,"snapshot.json"))
  }else stop("Unknown EMG review fixture mode")
})
