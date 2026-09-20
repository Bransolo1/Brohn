source("R/platform-participant-equipment.R") # Registered optional new-draft policy.
# Actual SQLite writer contention and participant error classification. No busy
# function or storage statement is mocked, and the 5-second timeout is retained.
for(module in c("platform-core","platform-store","platform-delivery")) source(paste0("R/",module,".R"),encoding="UTF-8")
local({
  root<-tempfile("brohn-store-busy-");dir.create(root);root<-normalizePath(root,winslash="/")
  store<-brohn_open_store(file.path(root,"workspace"));second<-brohn_open_store(store$root)
  on.exit({
    try(DBI::dbExecute(second$con,"ROLLBACK"),silent=TRUE)
    brohn_close_store(second);brohn_close_store(store)
    actual<-normalizePath(root,winslash="/",mustWork=FALSE)
    stopifnot(startsWith(tolower(actual),paste0(tolower(normalizePath(tempdir(),winslash="/")),"/")),startsWith(basename(actual),"brohn-store-busy-"))
    unlink(actual,recursive=TRUE,force=TRUE)
  },add=TRUE)
  checks<-0L;check<-function(name,ok) {if(!isTRUE(ok))stop("Busy classification: ",name);checks<<-checks+1L}
  design<-brohn_new_design("Original contention study",id="study-busy")
  for(i in seq_along(design$stimuli))design$stimuli[[i]]$content<-paste("Original concept",i)
  invisible(brohn_put_entity(store,"study",design$id,design));deployment<-brohn_publish(store,design$id,origin="sample",quota=1L)
  run<-.brohn_delivery_start(store,deployment$token,list(consented=TRUE,client_id="original-client",operation_id="start",participant_alias=""))
  app<-brohn_delivery_app(store,"www/participant")
  event<-list(sequence=1L,id="original-visibility",type="visibility",step_id=NULL,stimulus_id=NULL,condition_id=NULL,question_id=NULL,phase="setup",
    clock=list(id="browser-monotonic",unit="ms",value="0.000"),payload=list(hidden=FALSE))
  request<-list(events=list(event),operation_id="original-operation")
  call<-function(text=brohn_json(request)) {
    bytes<-charToRaw(text)
    response<-app$call(list(PATH_INFO=paste0("/api/events/",run$run_id),REQUEST_METHOD="POST",HTTP_HOST="127.0.0.1:3840",
      HTTP_AUTHORIZATION=paste("Bearer",run$access_token),CONTENT_TYPE="application/json",CONTENT_LENGTH=as.character(length(bytes)),
      rook.input=list(read=function(n=-1L)bytes)))
    response$value<-brohn_parse(response$body);response
  }
  check("production busy timeout retained",DBI::dbGetQuery(store$con,"PRAGMA busy_timeout")[[1]][[1]]==5000L)
  DBI::dbExecute(second$con,"BEGIN IMMEDIATE")
  began<-as.numeric(Sys.time());failure<-tryCatch(brohn_put_entity(store,"fixture","blocked",list(original=TRUE)),error=identity)
  elapsed<-as.numeric(Sys.time())-began
  check("actual database lock becomes structured store busy",inherits(failure,"brohn_store_busy") && identical(failure$code,"busy"))
  check("busy wait remains bounded and no entity is published",elapsed>=4.5 && elapsed<15 && is.null(brohn_get_entity(store,"fixture","blocked")))
  response<-call()
  check("actual participant write lock returns retryable 503",response$status==503L && response$value$error$code=="workspace_busy" && isTRUE(response$value$error$retryable))
  check("retry guidance carries no native database error",identical(response$headers[["Retry-After"]],"1") && response$value$error$retry_after_seconds==1L && !grepl("database is locked",response$body,fixed=TRUE))
  check("failed receipt does not acknowledge unsaved data",DBI::dbGetQuery(store$con,"SELECT acked_sequence FROM delivery_runs WHERE id=?",params=list(run$run_id))$acked_sequence[[1]]==0L && length(.brohn_delivery_events(store,run$run_id))==0L)
  malformed<-call("{broken")
  check("genuinely malformed request remains 400 while workspace busy",malformed$status==400L && malformed$value$error$code=="invalid_request")
  DBI::dbExecute(second$con,"ROLLBACK")
  retry<-call();again<-call()
  check("exact retry and replay succeed after lock release",retry$status==200L && again$status==200L && retry$value$acked_sequence==1L && again$value$acked_sequence==1L)
  check("same operation creates exactly one event and one receipt",length(brohn_run_events(store,run$run_id))==1L &&
    DBI::dbGetQuery(store$con,"SELECT count(*) AS n FROM delivery_receipts WHERE scope=? AND operation='events'",params=list(run$run_id))$n[[1]]==1L)
  callback<-tryCatch(brohn_store_batch(store,function()stop("database is locked",call.=FALSE)),error=identity)
  check("same-text arbitrary callback is not recategorized",inherits(callback,"simpleError") && !inherits(callback,"brohn_store_error") && identical(conditionMessage(callback),"database is locked"))
  check("callback failure rolls its transaction back",!RSQLite::sqliteIsTransacting(store$con))
  # Exercise the unchanged participant catch with a deliberate callback error
  # only. The actual lock above is never simulated. Restore the function before
  # leaving this isolated process so other tests cannot inherit the fixture.
  original<-.brohn_delivery_receive
  assign(".brohn_delivery_receive",function(...)brohn_store_batch(store,function()stop("database is locked",call.=FALSE)),envir=.GlobalEnv)
  arbitrary<-tryCatch(call(),finally=assign(".brohn_delivery_receive",original,envir=.GlobalEnv))
  check("unrelated callback same text still returns 400",arbitrary$status==400L && arbitrary$value$error$code=="invalid_request" && is.null(arbitrary$headers[["Retry-After"]]))
  cat("SQLite busy handling:",checks,"scoped checks passed.\n")
})
