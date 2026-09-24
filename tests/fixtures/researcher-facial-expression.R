# Isolated copied/composed licensed software media; never a participant capture.
args<-commandArgs(trailingOnly=TRUE);stopifnot(length(args)>=2L)
mode<-args[[1]];folder<-normalizePath(args[[2]],winslash="/",mustWork=TRUE)
stopifnot(startsWith(basename(folder),"brohn-facial-browser-"))
source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=TRUE)
config_path<-file.path(folder,"fixture.json")
if(mode=="serve") {
  config<-brohn_read_json_file(config_path);Sys.setenv(BROHN_WORKSPACE=config$workspace,BROHN_APP_MODE="platform",BROHN_PARTICIPANT_PORT="3946")
  stop_owned<-function()if(file.exists(file.path(folder,"stop.request")))shiny::stopApp()else later::later(stop_owned,.2)
  later::later(stop_owned,.2);shiny::runApp(".",host="127.0.0.1",port=config$port,launch.browser=FALSE)
}else local({
  store<-brohn_open_store(file.path(folder,"workspace"));on.exit(brohn_close_store(store),add=TRUE)
  if(mode=="setup") {
    stopifnot(!file.exists(config_path));brohn_initialise_library(store)
    upstream<-normalizePath("../../work/test-runs/brohn-facial-native-20260924-01",winslash="/",mustWork=TRUE)
    original<-file.path(upstream,"authored-vfr-face-reference.mkv");sha<-digest::digest(file=original,algo="sha256")
    stopifnot(sha=="251248e52a49b17a258e59ce31b27b5a05ff0bdc39f116e355c1959a09f0bf6c")
    copied<-file.path(folder,"licensed-composed-facial-fixture.mkv");stopifnot(file.copy(original,copied),identical(digest::digest(file=copied,algo="sha256"),sha))
    brohn_write_json_file(list(workspace=store$root,port=3945,source=copied,source_hash=sha,upstream=upstream,
      origin="composed_licensed_software_fixture",description="Six independently timed frames composed from the existing Apache2 MediaPipe image; blank/single/single/multiple/blank/single. No actual participant, motion or emotion-validity claim.",
      expected=list(pts=as.list(c("2000","2040","2110","2310","2710","2910")),time_base="1/1000",eligible_frames=3,eligible_time=.07)),config_path)
  }else if(mode=="worker") {
    while(!file.exists(file.path(folder,"stop.worker"))){j<-brohn_claim_job(store,"facial-browser-fixture",90)
      if(is.null(j))Sys.sleep(.2)else {brohn_process_job(store,j,timeout_seconds=1900);cat(brohn_json(list(id=j$id,status=brohn_get_job(store,j$id)$status)),"\n")}}
  }else if(mode=="inspect") {
    brohn_write_json_file(list(reports=brohn_list_entities(store,"report"),datasets=brohn_list_entities(store,"dataset"),jobs=brohn_list_jobs(store)),file.path(folder,"snapshot.json"))
  }else stop("Unknown facial fixture mode")
})
