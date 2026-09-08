# Independent observer of a test-owned preparation; no production timing hooks.
for(module in c("platform-core","platform-store","platform-delivery"))source(paste0("R/",module,".R"),encoding="UTF-8")
r<-readRDS(commandArgs(TRUE)[[1]])
store<-brohn_open_store(r$workspace)
if(r$operation=="receive")app<-brohn_delivery_app(store,"www/participant")
writeLines("ready",r$ready)
began<-as.numeric(Sys.time());phase<-NULL
repeat {
  paths<-list.files(file.path(r$workspace,"scratch","publication"),pattern="^status.json$",full.names=TRUE,recursive=TRUE)
  for(path in paths) {
    status<-tryCatch(jsonlite::fromJSON(path,simplifyVector=FALSE),error=function(e)NULL)
    request<-tryCatch(jsonlite::fromJSON(file.path(dirname(path),"request.json"),simplifyVector=FALSE),error=function(e)NULL)
    eligible<-!is.null(status) && !is.null(request) && identical(request$owner$job_id,r$job_id) && status$phase %in% c("copying","verifying_sealed_bytes")
    if(identical(r$operation,"crash")) {
      fragments<-list.files(dirname(path),pattern="^[a-f0-9]{32}\\.object-pending$",full.names=TRUE)
      eligible<-eligible && identical(status$phase,"copying") && length(fragments)>0L &&
        sum(file.info(fragments)$size,na.rm=TRUE)>=16*1024^2
    }
    if(eligible) {phase<-status$phase;break}
  }
  if(!is.null(phase))break
  if(as.numeric(Sys.time())-began>30)stop("Original preparation did not reach its expected phase.")
  Sys.sleep(.002)
}
started<-as.numeric(Sys.time())
if(r$operation=="cancel") {
  result<-brohn_cancel_job(store,r$job_id)
  out<-list(status=result$status,phase=phase,started=started,ended=as.numeric(Sys.time()))
} else if(r$operation=="crash") {
  process<-ps::ps_handle(as.integer(status$pid));created<-as.numeric(ps::ps_create_time(process))
  expected<-c(normalizePath("scripts/workers/publication.py",winslash="/"),"--request",file.path(dirname(path),"request.json"),
    "--receipt",file.path(dirname(path),"receipt.json"),"--status",path)
  stopifnot(identical(tail(ps::ps_cmdline(process),length(expected)),expected))
  fragments<-list.files(dirname(path),pattern="^[a-f0-9]{32}\\.object-pending$",full.names=TRUE)
  bytes_before<-sum(file.info(fragments)$size)
  ps::ps_kill(process)
  out<-list(status="owned_guard_killed",pid=status$pid,created=created,phase=phase,fragment_bytes_before=bytes_before,
    directory=dirname(path),started=started,ended=as.numeric(Sys.time()))
} else if(r$operation=="receive") {
  bytes<-charToRaw(brohn_json(r$event_request))
  response<-app$call(list(PATH_INFO=paste0("/api/events/",r$run_id),REQUEST_METHOD="POST",HTTP_HOST="127.0.0.1:3840",
    HTTP_AUTHORIZATION=paste("Bearer",r$access_token),CONTENT_TYPE="application/json",CONTENT_LENGTH=as.character(length(bytes)),
    rook.input=list(read=function(n=-1L)bytes)))
  out<-list(phase=phase,started=started,ended=as.numeric(Sys.time()),http_status=response$status,response=brohn_parse(response$body))
} else stop("Unsupported original observer operation.")
saveRDS(out,r$output)
brohn_close_store(store)
