# Copy original completed native reference only; never rerun model inference.
args<-commandArgs(trailingOnly=TRUE);mode<-args[[1L]];folder<-normalizePath(args[[2L]],winslash="/",mustWork=TRUE)
stopifnot(startsWith(basename(folder),"brohn-facial-review-"))
source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=TRUE)
if(!exists("brohn_prepare_facial_review"))source("R/platform-facial-review.R",encoding="UTF-8")
config_path<-file.path(folder,"fixture.json")
if(mode=="setup")local({
  reference<-normalizePath(args[[3L]],winslash="/",mustWork=TRUE);original<-brohn_read_json_file(file.path(reference,"fixture.json"))
  stopifnot(!file.exists(config_path),!dir.exists(file.path(folder,"workspace")),file.copy(original$workspace,folder,recursive=TRUE))
  store<-brohn_open_store(file.path(folder,"workspace"));on.exit(brohn_close_store(store),add=TRUE)
  reports<-Filter(function(r)brohn_facial_supported(r$body$analysis)&&r$body$analysis$quality$analysed_frames==6L,brohn_list_entities(store,"report",limit=100L));stopifnot(length(reports)==1L)
  r<-reports[[1L]];s<-.brohn_freview_source(store,r$id,r$revision,brohn_hash(r$body),r$project_id,TRUE)
  refs<-lapply(s$source_objects,function(x)c(x,list(path=brohn_object_path(store,x$hash),original_path=file.path(original$workspace,substring(brohn_object_path(store,x$hash),nchar(store$root)+2L)))))
  brohn_write_json_file(list(workspace=store$root,original_workspace=original$workspace,report_id=r$id,report_hash=brohn_hash(r$body),revision=r$revision,project_id=r$project_id,
    study_id=r$body$study_id,dataset_id=r$body$dataset_id,dataset_title=brohn_get_entity(store,"dataset",r$body$dataset_id)$body$title,source_objects=refs,analysis=r$body$analysis,baseline_jobs=vapply(brohn_list_jobs(store,limit=500L),`[[`,character(1),"id"),
    port=as.integer(Sys.getenv("BROHN_QA_PORT","3955"))),config_path)
})else if(mode=="serve"){
  cfg<-brohn_read_json_file(config_path);Sys.setenv(BROHN_WORKSPACE=cfg$workspace,BROHN_APP_MODE="platform")
  stop_owned<-function()if(file.exists(file.path(folder,"stop.request")))shiny::stopApp()else later::later(stop_owned,.2)
  later::later(stop_owned,.2);shiny::runApp(".",host="127.0.0.1",port=cfg$port,launch.browser=FALSE)
}else if(mode=="worker")local({
  cfg<-brohn_read_json_file(config_path);store<-brohn_open_store(cfg$workspace);on.exit(brohn_close_store(store),add=TRUE)
  while(!file.exists(file.path(folder,"stop.request"))){if(file.exists(file.path(folder,"worker.pause"))){Sys.sleep(.2);next};j<-brohn_claim_job(store,"facial-review-browser",300)
    if(is.null(j))Sys.sleep(.2)else {brohn_process_job(store,j,timeout_seconds=300);cat(brohn_json(list(id=j$id,status=brohn_get_job(store,j$id)$status)),"\n")}}
})else if(mode=="inspect")local({
  cfg<-brohn_read_json_file(config_path);store<-brohn_open_store(cfg$workspace);on.exit(brohn_close_store(store),add=TRUE)
  report<-brohn_report_for_review(store,cfg$report_id);stopifnot(identical(brohn_hash(report$body),cfg$report_hash))
  originals<-lapply(cfg$source_objects,function(x){stopifnot(identical(digest::digest(file=x$path,algo="sha256"),x$hash),identical(digest::digest(file=x$original_path,algo="sha256"),x$hash));list(hash=x$hash,bytes=x$bytes,unchanged=TRUE)})
  brohn_write_json_file(list(report_hash=brohn_hash(report$body),originals=originals,jobs=brohn_list_jobs(store,limit=500L),reviews=brohn_list_entities(store,"facial_review",limit=100L),frames=brohn_list_entities(store,"facial_frame",limit=100L)),file.path(folder,"inspection.json"))
})else stop("Unknown fixture mode")
