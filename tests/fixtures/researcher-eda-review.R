# Isolated original synthetic source, researcher import and supervised workers.
args<-commandArgs(trailingOnly=TRUE);stopifnot(length(args)>=2L)
mode<-args[[1]];folder<-normalizePath(args[[2]],winslash="/",mustWork=TRUE)
stopifnot(startsWith(basename(folder),"brohn-eda-review-browser-"))
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
    time<-(0:4499)/25;dt<-pmax(time-21,0);signal<-5+.0002*time+exp(-dt/2)-exp(-dt/.7);signal[3001]<-NA
    events<-data.frame(time=c(20,70,100,104,121,175),code=c("A","B","A","B","A","B"),exposure=c("responder","nonresponse","overlap-a","overlap-b","gap","edge"))
    onset<-exposure<-rep("",length(time));for(i in seq_len(nrow(events))){row<-events$time[[i]]*25+1;onset[[row]]<-events$code[[i]];exposure[[row]]<-events$exposure[[i]]}
    source<-file.path(folder,"original-conductance.csv")
    utils::write.csv(data.frame(time=time,participant="SYNTHETIC-P1",session="SYNTHETIC-S1",conductance=signal,onset=onset,exposure=exposure),source,row.names=FALSE,na="NA",fileEncoding="UTF-8")
    brohn_write_json_file(list(workspace=store$root,port=as.integer(Sys.getenv("BROHN_EDA_REVIEW_TEST_PORT","3883")),source=source,source_hash=digest::digest(file=source,algo="sha256"),events=lapply(seq_len(nrow(events)),function(i)as.list(events[i,])),
      origin="original_synthetic",samples=4500,sampling_rate=25),config_path)
  }else if(mode=="worker") {
    while(!file.exists(file.path(folder,"stop.worker"))){j<-brohn_claim_job(store,"eda-review-browser-fixture",90)
      if(is.null(j))Sys.sleep(.2)else {brohn_process_job(store,j,timeout_seconds=300);cat(brohn_json(list(id=j$id,status=brohn_get_job(store,j$id)$status)),"\n")}}
  }else if(mode=="inspect") {
    brohn_write_json_file(list(reports=brohn_list_entities(store,"report"),reviews=brohn_list_entities(store,"eda_review"),datasets=brohn_list_entities(store,"dataset"),jobs=brohn_list_jobs(store)),file.path(folder,"snapshot.json"))
  }else stop("Unknown EDA review fixture mode")
})
