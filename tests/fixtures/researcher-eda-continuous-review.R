# Isolated original synthetic source, researcher import and supervised workers.
args<-commandArgs(trailingOnly=TRUE);stopifnot(length(args)>=2L)
mode<-args[[1]];folder<-normalizePath(args[[2]],winslash="/",mustWork=TRUE)
stopifnot(startsWith(basename(folder),"brohn-eda-continuous-review-browser-"))
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
    time<-(0:4300)/10;conductance<-4+.001*time
    for(onset in seq(3,429,6)){dt<-time-onset;conductance<-conductance+ifelse(dt>=0,exp(-pmax(dt,0)/1.8)-exp(-pmax(dt,0)/.4),0)}
    conductance[c(3601L,4251L)]<-NA
    source<-file.path(folder,"original-synthetic-conductance-siemens.csv")
    utils::write.csv(data.frame(time=time,participant="SYNTHETIC-P1",session="SYNTHETIC-S1",conductance=conductance/1e6),source,row.names=FALSE,na="NA",fileEncoding="UTF-8")
    brohn_write_json_file(list(workspace=store$root,port=as.integer(Sys.getenv("BROHN_EDA_CONTINUOUS_REVIEW_TEST_PORT","3933")),source=source,source_hash=digest::digest(file=source,algo="sha256"),
      origin="original_synthetic",samples=4301,sampling_rate=10,expected=list(pulse_spacing_s=6,synthetic_decay_s=1.8,synthetic_rise_s=.4,missing_s=list(360,425))),config_path)
  }else if(mode=="worker") {
    while(!file.exists(file.path(folder,"stop.worker"))){j<-brohn_claim_job(store,"eda-continuous-review-browser-fixture",90)
      if(is.null(j))Sys.sleep(.2)else {brohn_process_job(store,j,timeout_seconds=300);cat(brohn_json(list(id=j$id,status=brohn_get_job(store,j$id)$status)),"\n")}}
  }else if(mode=="inspect") {
    brohn_write_json_file(list(reports=brohn_list_entities(store,"report"),reviews=brohn_list_entities(store,"eda_continuous_review"),datasets=brohn_list_entities(store,"dataset"),jobs=brohn_list_jobs(store)),file.path(folder,"snapshot.json"))
    reports<-brohn_list_entities(store,"report");if(length(reports))for(a in reports[[1]]$body$analysis$artifacts)file.copy(brohn_object_path(store,brohn_default(a$sha256,a$hash)),file.path(folder,paste0(a$kind,".ndjson")),overwrite=TRUE)
  }else stop("Unknown EDA review fixture mode")
})
