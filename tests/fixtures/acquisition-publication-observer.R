# Independent process: observes real native staging and writes through the real
# store/receiver APIs. There are no copy delays or publisher replacements.
source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=FALSE)
r<-readRDS(commandArgs(TRUE)[[1L]]);store<-brohn_open_store(r$workspace)
if(identical(r$operation,"hold-owner")) {
  manager<-brohn_acquisition_manager(store);record<-brohn_acquisition(store,r$acquisition_id)
  job<-.brohn_acq_publication_job(store,record,manager,"acquisition_preserve")
  saveRDS(list(job_id=job$id,manager_id=manager$id,identity=manager$identity),r$output)
  writeLines("ready",r$ready)
  repeat Sys.sleep(.1)
}
if(!is.null(r$event_request))app<-brohn_delivery_app(store,"www/participant")
writeLines("ready",r$ready);began<-as.numeric(Sys.time());phase<-NULL;job<-NULL
repeat {
  ids<-DBI::dbGetQuery(store$con,"SELECT id FROM jobs WHERE operation=? AND status='running'",params=list(r$publication_operation))$id
  candidates<-lapply(ids,function(id)brohn_get_job(store,id))
  matching<-Filter(function(j)identical(j$request$acquisition_id,r$acquisition_id),candidates)
  if(length(matching)==1L) {
    job<-matching[[1L]]
    paths<-list.files(file.path(store$root,"scratch","publication"),pattern="^status.json$",full.names=TRUE,recursive=TRUE)
    for(path in paths) {
      status<-tryCatch(brohn_read_json_file(path),error=function(e)NULL)
      request<-tryCatch(brohn_read_json_file(file.path(dirname(path),"request.json")),error=function(e)NULL)
      if(!is.null(status)&&!is.null(request)&&identical(request$owner$job_id,job$id)&&status$phase %in% c("copying","verifying_sealed_bytes")) {
        phase<-status$phase;break
      }
    }
  }
  if(!is.null(phase))break
  if(as.numeric(Sys.time())-began>90)stop("Acquisition did not reach real native staging.")
  Sys.sleep(.002)
}
started<-as.numeric(Sys.time());out<-list(job_id=job$id,phase=phase)
if(!is.null(r$event_request)) {
  bytes<-charToRaw(brohn_json(r$event_request))
  response<-app$call(list(PATH_INFO=paste0("/api/events/",r$run_id),REQUEST_METHOD="POST",HTTP_HOST="127.0.0.1:3840",
    HTTP_AUTHORIZATION=paste("Bearer",r$access_token),CONTENT_TYPE="application/json",CONTENT_LENGTH=as.character(length(bytes)),
    rook.input=list(read=function(n=-1L)bytes)))
  out$http_status<-response$status;out$response<-brohn_parse(response$body)
}
out$writer_seconds<-as.numeric(Sys.time())-started
if(r$operation=="cancel")out$status<-brohn_cancel_job(store,job$id)$status else if(r$operation=="stale") {
  current<-brohn_acquisition(store,r$acquisition_id);body<-current$body;body$fixture_revision_note<-"Concurrent source revision"
  out$revision<-brohn_put_entity(store,"acquisition",current$id,body,current$revision,current$project_id)$revision
} else stop("Unsupported observer action.")
saveRDS(out,r$output);brohn_close_store(store)
