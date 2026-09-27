# Process-local ownership of exact saved-window files. HTTP capability tokens,
# cancellation and session disconnect are owned by the calling UI/service.
.brohn_cr_handle <- function(handle) {
  brohn_require(is.environment(handle)&&inherits(handle,"brohn_clock_window_resources")&&environmentIsLocked(handle)&&
    is.environment(handle$state)&&!isTRUE(handle$state$closed),"Reopen this closed original-row window.")
  handle
}
brohn_release_clock_window_resources <- function(handle) {
  if(is.environment(handle)&&inherits(handle,"brohn_clock_window_resources")&&is.environment(handle$state)&&!isTRUE(handle$state$closed)) {
    state<-handle$state;state$closed<-TRUE
    # Release every owned seal even if a prior close reports an error.
    for(g in handle$guards)tryCatch(.brohn_qexplorer_release(g),error=function(e)NULL)
  }
  invisible(NULL)
}
.brohn_cr_metadata <- function(store,ref,project_id) {
  # Reuse the current server-side reader/profile validator without queueing any
  # work. A plain service store cannot inherit access in configured hosted mode.
  brohn_clock_queue_authority(store,"clock_window",project_id)
  record<-brohn_clock_window_record(store,ref,project_id,FALSE)
  context<-.brohn_cw_context(store,record$body$request,FALSE,FALSE,FALSE)
  objects<-c(context$source_objects,list(list(hash=record$body$result_object$hash,bytes=record$body$result_object$size)),
    lapply(record$body$artifacts,function(a)list(hash=a$hash,bytes=a$size)))
  # Two recordings, each marker plus one/two scalar signals; two retained map
  # documents, this window document and its four complete export artifacts.
  brohn_require(length(objects)>=19L&&length(objects)<=23L,"This window has an unsupported original-object resource set.")
  for(a in objects)brohn_require(.brohn_cm_hash(a$hash)&&brohn_number(a$bytes,1,2^53-1,TRUE),"A saved window object lacks an exact bounded identity and byte size.")
  hashes<-vapply(objects,`[[`,character(1),"hash")
  for(hash in unique(hashes))brohn_require(length(unique(vapply(objects[hashes==hash],`[[`,numeric(1),"bytes")))==1L,
    "The same original object has inconsistent byte sizes.")
  originals<-.brohn_cw_artifacts(record$body$result)
  artifacts<-lapply(seq_along(record$body$artifacts),function(i){a<-record$body$artifacts[[i]];original<-originals[[i]]
    list(kind=a$kind,file=original$file,path=brohn_object_path(store,a$hash,FALSE),hash=a$hash,bytes=a$size,media_type=a$media_type)})
  brohn_require(length(artifacts)==4L&&!anyDuplicated(vapply(artifacts,`[[`,character(1),"kind")),"Retain all four distinct original-row exports.")
  list(record=record,objects=objects[!duplicated(hashes)],artifacts=artifacts)
}
brohn_open_clock_window_resources <- function(store,ref,project_id) {
  brohn_require(.Platform$OS.type=="windows","Saved clock resources require the qualified Windows native read seals.")
  metadata<-.brohn_cr_metadata(store,ref,project_id)
  guards<-list();success<-FALSE
  on.exit(if(!success)for(g in guards)tryCatch(.brohn_qexplorer_release(g),error=function(e)NULL),add=TRUE)
  # All original inputs and every delivered byte are held before the first full
  # SHA check. The helper's internal failed-open cleanup owns partial handles.
  guards<-brohn_hold_signal_value_sources(store,list(source_objects=metadata$objects))
  verified<-brohn_clock_window_record(store,ref,project_id,TRUE)
  current<-.brohn_cr_metadata(store,ref,project_id)
  brohn_require(.brohn_cm_same(metadata,current)&&.brohn_cm_same(verified,metadata$record),"Saved source authority or result identity changed while opening this window.")
  .brohn_cm_guard_check(guards)
  handle<-new.env(parent=emptyenv());class(handle)<-"brohn_clock_window_resources"
  handle$state<-new.env(parent=emptyenv());handle$state$closed<-FALSE
  handle$workspace_id<-store$workspace_id;handle$root<-normalizePath(store$root,winslash="/",mustWork=TRUE)
  handle$project_id<-project_id;handle$reference<-ref;handle$metadata<-metadata;handle$guards<-guards
  lockEnvironment(handle,bindings=TRUE)
  reg.finalizer(handle,brohn_release_clock_window_resources,onexit=TRUE)
  success<-TRUE
  list(record=verified,handle=handle,artifacts=metadata$artifacts)
}
brohn_clock_window_resources_current <- function(store,handle) {
  handle<-.brohn_cr_handle(handle)
  brohn_require(identical(store$workspace_id,handle$workspace_id)&&
    identical(normalizePath(store$root,winslash="/",mustWork=TRUE),handle$root),"Open this saved window in its original workspace.")
  .brohn_cm_guard_check(handle$guards)
  # Source/job/catalog and CURRENT reader authorization are never cached. The
  # original producer may have expired; its successful immutable proof remains.
  current<-.brohn_cr_metadata(store,handle$reference,handle$project_id)
  brohn_require(.brohn_cm_same(current,handle$metadata),"This original-row resource no longer matches its opened source and publication.")
  .brohn_cm_guard_check(handle$guards)
  list(record=current$record,artifacts=current$artifacts)
}
