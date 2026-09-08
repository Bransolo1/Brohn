# Actual original outlet and forced metadata-discovery process interruption.
# Uses a unique local LSL session and exact IDs; never discovers hardware.
source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=FALSE)
local({
  checks<-0L
  check<-function(name,ok) {if(!isTRUE(ok)) stop(paste("Discovery recovery QA failed:",name),call.=FALSE);checks<<-checks+1L}
  rejected<-function(value) inherits(try(force(value),silent=TRUE),"try-error")
  until<-function(fn,timeout=20) {end<-as.numeric(Sys.time())+timeout;repeat {
    if(isTRUE(fn())) return(TRUE);if(as.numeric(Sys.time())>=end) return(FALSE);Sys.sleep(.02)
  }}
  root<-tempfile("brohn-discovery-recovery-");dir.create(root);root<-normalizePath(root,winslash="/")
  store<-brohn_open_store(file.path(root,"workspace"));brohn_initialise_library(store);children<-list()
  on.exit({
    for(child in children) if(child$is_alive()) {child$kill_tree();child$wait(5000)}
    brohn_close_store(store)
    actual<-normalizePath(root,winslash="/",mustWork=FALSE)
    stopifnot(startsWith(tolower(actual),paste0(tolower(normalizePath(tempdir(),winslash="/")),"/")),grepl("^brohn-discovery-recovery-",basename(actual)))
    unlink(actual,recursive=TRUE,force=TRUE)
  },add=TRUE)
  lsl_session<-brohn_id("synthetic");source_id<-brohn_id("source")
  config<-file.path(root,"lsl.cfg");fixture<-file.path(root,"original-outlet.py")
  writeLines(c("[multicast]","ResolveScope = machine","[lab]","KnownPeers = {127.0.0.1}",paste("SessionID =",lsl_session)),config)
  writeLines(c("import os,time", "from pathlib import Path", "import pylsl",
    "info=pylsl.StreamInfo('Brohn original discovery recovery','Markers',1,0,'string',os.environ['BROHN_QA_SOURCE'])",
    "info.desc().append_child_value('origin','synthetic')",
    "outlet=pylsl.StreamOutlet(info)","Path(os.environ['BROHN_QA_READY']).write_text('ready')",
    "while True:","    time.sleep(.05)"),fixture)
  outlet<-processx::process$new(.brohn_acq_python(),fixture,
    env=c("current",LSLAPICFG=config,BROHN_QA_SOURCE=source_id,BROHN_QA_READY=file.path(root,"ready")),
    stdout=file.path(root,"outlet.stdout"),stderr=file.path(root,"outlet.stderr"),windows_hide_window=TRUE,cleanup_tree=TRUE)
  children[[length(children)+1L]]<-outlet
  check("original isolated outlet is running",until(function() file.exists(file.path(root,"ready"))))
  start_manager<-function(label) {
    p<-processx::process$new(brohn_rscript(),c("--vanilla","scripts/run-acquisition.R","--root",store$root),
      env=c("current",R_LIBS_USER=paste(.libPaths(),collapse=.Platform$path.sep)),
      stdout=file.path(root,paste0(label,".stdout")),stderr=file.path(root,paste0(label,".stderr")),windows_hide_window=TRUE,cleanup_tree=TRUE)
    children[[length(children)+1L]]<<-p
    check(paste(label,"manager ready"),until(function() brohn_acquisition_ready(store$root,store$workspace_id)))
    p
  }
  manager<-start_manager("first");study<-brohn_create_study(store,"Original discovery interruption")
  complete<-brohn_queue_lsl_discovery(store,study$id,lsl_session,source_id)
  check("baseline discovery finishes normally",until(function() identical(brohn_get_entity(store,"acquisition_discovery",complete$id)$body$status,"ready")))
  complete<-brohn_get_entity(store,"acquisition_discovery",complete$id);completed_hash<-complete$body$result_object$hash
  # Four exact nonexistent test IDs make the in-flight process observable without
  # a sleep stub, broad scan or source instrumentation.
  interrupted<-brohn_queue_lsl_discovery(store,study$id,lsl_session,c(source_id,replicate(4,brohn_id("absent"))))
  child_identity<-NULL
  child_started<-until(function() {
    r<-brohn_get_entity(store,"acquisition_discovery",interrupted$id)
    if(!identical(r$body$status,"running")) return(FALSE)
    handles<-tryCatch(ps::ps_children(ps::ps_handle(manager$get_pid()),recursive=TRUE),error=function(e) list())
    found<-Filter(function(p) tryCatch(any(grepl("lsl_recorder.py",ps::ps_cmdline(p),fixed=TRUE)) && "discover" %in% ps::ps_cmdline(p),error=function(e) FALSE),handles)
    if(length(found)) child_identity<<-.brohn_acq_process(ps::ps_pid(found[[1L]]))
    length(found)>0
  })
  if(!child_started) {
    cat(brohn_json(brohn_get_entity(store,"acquisition_discovery",interrupted$id)),"\n")
    cat(paste(readLines(file.path(root,"first.stderr"),warn=FALSE),collapse="\n"),"\n")
  }
  check("actual metadata child starts while catalog is running",child_started)
  interrupted<-brohn_get_entity(store,"acquisition_discovery",interrupted$id)
  frozen_request<-interrupted$body$request;frozen_hash<-interrupted$body$request_hash
  check("running request records exact manager and workspace evidence",identical(interrupted$body$execution$workspace_id,store$workspace_id) &&
    identical(interrupted$body$execution$manager_id,interrupted$body$manager_id) &&
    identical(.brohn_acq_probe(interrupted$body$execution$manager_process),"owned_alive"))
  request_path<-interrupted$body$execution$request_path
  check("frozen request is present before child execution",identical(.brohn_acq_hash(request_path),interrupted$body$execution$request_file_hash))
  manager$kill_tree();manager$wait(5000)
  check("only the test-owned manager and discovery child are killed",!manager$is_alive() && identical(.brohn_acq_probe(child_identity),"absent") && outlet$is_alive())
  manager<-start_manager("restart")
  check("restart terminates stale discovery honestly",until(function() identical(brohn_get_entity(store,"acquisition_discovery",interrupted$id)$body$status,"interrupted")))
  recovered<-brohn_get_entity(store,"acquisition_discovery",interrupted$id)
  check("request and on-disk source evidence remain unchanged",identical(recovered$body$request,frozen_request) && identical(recovered$body$request_hash,frozen_hash) &&
    identical(.brohn_acq_hash(request_path),interrupted$body$execution$request_file_hash))
  check("recovery binds the absent former manager and workspace",identical(recovered$body$recovery$previous_manager_id,interrupted$body$manager_id) &&
    identical(recovered$body$recovery$workspace_id,store$workspace_id) && identical(recovered$body$recovery$owner_status,"absent"))
  history<-brohn_entity_history(store,"acquisition_discovery",interrupted$id)
  check("immutable history keeps running and interrupted revisions",all(c("queued","running","interrupted") %in% vapply(history,function(r) r$body$status,character(1))))
  check("completed discoveries and immutable results are unchanged",identical(brohn_get_entity(store,"acquisition_discovery",complete$id)$revision,complete$revision) &&
    identical(.brohn_acq_hash(brohn_object_path(store,completed_hash)),completed_hash))
  # Manager ticks continue, but no child or new request is created by recovery.
  before<-length(brohn_lsl_discoveries(store));Sys.sleep(.6)
  check("restart does not automatically rescan or start collection",length(brohn_lsl_discoveries(store))==before &&
    length(brohn_acquisitions(store))==0 && length(brohn_list_jobs(store))==0)
  check("stale retry revision is rejected",rejected(brohn_retry_lsl_discovery(store,recovered$id,recovered$revision-1L)))
  retry<-brohn_retry_lsl_discovery(store,recovered$id,recovered$revision)
  check("explicit retry creates separate scoped request with lineage",retry$id!=recovered$id && identical(retry$body$request,frozen_request) &&
    identical(retry$body$retry_of$id,recovered$id) && identical(retry$body$retry_of$request_hash,frozen_hash))
  check("explicit retry completes against original local source",until(function() identical(brohn_get_entity(store,"acquisition_discovery",retry$id)$body$status,"ready")))
  ready<-brohn_get_entity(store,"acquisition_discovery",retry$id)
  check("retried discovery retains exact original source",length(ready$body$result$streams)==1 && identical(ready$body$result$streams[[1L]]$source_id,source_id))
  check("ready discoveries cannot be retried through interrupted control",rejected(brohn_retry_lsl_discovery(store,ready$id,ready$revision)))
  # Legacy rows can use immutable service history as ownership evidence. A
  # conflicting new execution scope must stay unverified, never falsely dead.
  legacy_body<-interrupted$body;legacy_body$id<-brohn_id("discovery-legacy");legacy_body$execution<-NULL
  legacy<-brohn_put_entity(store,"acquisition_discovery",legacy_body$id,legacy_body,project_id=study$project_id)
  foreign_body<-interrupted$body;foreign_body$id<-brohn_id("discovery-foreign");foreign_body$execution$workspace_id<-"another-workspace"
  foreign<-brohn_put_entity(store,"acquisition_discovery",foreign_body$id,foreign_body,project_id=study$project_id)
  service<-brohn_get_entity(store,"acquisition_service","local")
  brohn_store_batch(store,function() .brohn_acq_reconcile_discoveries(store,list(id=service$body$manager_id)))
  check("legacy running row recovers using absent same-workspace service history",identical(brohn_get_entity(store,"acquisition_discovery",legacy$id)$body$status,"interrupted"))
  foreign<-brohn_get_entity(store,"acquisition_discovery",foreign$id)
  check("conflicting workspace is explicitly unverified, not falsely interrupted",identical(foreign$body$status,"attention_required") && identical(foreign$body$recovery$owner_status,"unverified"))
  check("unverified ownership cannot reuse the shortcut retry",rejected(brohn_retry_lsl_discovery(store,foreign$id,foreign$revision)))
  cat(sprintf("Acquisition discovery recovery: %d actual-process checks passed.\n",checks))
})
