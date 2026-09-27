# Plot files are owned here; the already verified original-window handle is
# borrowed. The caller releases the plot before releasing that window.
brohn_find_clock_plot <- function(store,window_ref,project_id) {
  brohn_clock_queue_authority(store,"clock_plot",project_id);.brohn_cm_ref_valid(window_ref)
  brohn_clock_window_record(store,window_ref,project_id,FALSE)
  rows<-DBI::dbGetQuery(store$con,paste(
    "SELECT v.id,v.revision,v.body_hash FROM entities e JOIN entity_versions v",
    "ON v.kind=e.kind AND v.id=e.id AND v.revision=e.revision",
    "JOIN jobs j ON j.id=json_extract(v.body_json,'$.processing.job_id')",
    "WHERE e.kind='clock_plot' AND e.project_id=? AND v.project_id=?",
    "AND json_extract(v.body_json,'$.schema')='brohn-saved-clock-plot/0.1'",
    "AND coalesce(json_extract(v.body_json,'$.archived'),0)=0",
    "AND json_extract(v.body_json,'$.window.id')=? AND json_extract(v.body_json,'$.window.revision')=?",
    "AND json_extract(v.body_json,'$.window.hash')=?",
    "AND json_extract(v.body_json,'$.request.display.profile')=? AND json_extract(v.body_json,'$.request.display.bins')=?",
    "AND j.operation='clock_plot' AND j.status='succeeded'",
    "ORDER BY v.created_at DESC,v.id ASC LIMIT 1"),
    params=list(project_id,project_id,window_ref$id,window_ref$revision,window_ref$hash,.brohn_clock_plot_display$profile,.brohn_clock_plot_display$bins))
  if(!nrow(rows))return(NULL)
  ref<-list(id=rows$id[[1L]],revision=rows$revision[[1L]],hash=rows$body_hash[[1L]])
  # A failed retained proof never becomes a reusable artifact. Its historical
  # record stays available for diagnosis; preparing a fresh plot is separate.
  result<-tryCatch(brohn_clock_plot_record(store,ref,project_id,FALSE),error=function(e)NULL)
  if(is.null(result))return(NULL)
  brohn_clock_queue_authority(store,"clock_plot",project_id)
  ref
}
.brohn_cpr_handle <- function(handle) {
  brohn_require(is.environment(handle)&&inherits(handle,"brohn_clock_plot_resources")&&environmentIsLocked(handle)&&
    is.environment(handle$state)&&!isTRUE(handle$state$closed),"Reopen this closed complete clock plot.")
  handle
}
brohn_release_clock_plot_resources <- function(handle) {
  if(is.environment(handle)&&inherits(handle,"brohn_clock_plot_resources")&&is.environment(handle$state)&&!isTRUE(handle$state$closed)){
    state<-handle$state;state$closed<-TRUE
    for(g in handle$guards)tryCatch(.brohn_qexplorer_release(g),error=function(e)NULL)
  }
  invisible(NULL)
}
.brohn_cpr_metadata <- function(store,ref,window_handle) {
  window<-brohn_clock_window_resources_current(store,window_handle)$record
  record<-brohn_clock_plot_record(store,ref,window_handle$project_id,FALSE)
  brohn_require(.brohn_cm_same(record$body$window,.brohn_cm_ref(window)),"Open this plot with its exact original-row window, including its numerical-page identity.")
  a<-record$body$artifact;doc<-record$body$result_object
  brohn_require(.brohn_cm_hash(doc$hash)&&brohn_number(doc$size,1,2*1024^2,TRUE),"This saved plot lacks its bounded retained publication document.")
  objects<-list(list(hash=a$hash,bytes=a$size),list(hash=doc$hash,bytes=doc$size))
  brohn_require(a$hash!=doc$hash,"The plot artifact and retained publication must remain distinct.")
  artifact<-list(file="plot.json",path=brohn_object_path(store,a$hash,FALSE),hash=a$hash,bytes=a$size,media_type=a$media_type)
  document<-list(path=brohn_object_path(store,doc$hash,FALSE),hash=doc$hash,bytes=doc$size)
  brohn_require(file.info(artifact$path)$size==artifact$bytes&&file.info(document$path)$size==document$bytes,"Saved complete plot resource sizes changed.")
  list(record=record,artifact=artifact,document=document,objects=objects)
}
brohn_open_clock_plot_resources <- function(store,ref,window_handle) {
  metadata<-.brohn_cpr_metadata(store,ref,window_handle)
  guards<-list();success<-FALSE
  on.exit(if(!success)for(g in guards)tryCatch(.brohn_qexplorer_release(g),error=function(e)NULL),add=TRUE)
  # Both new files are sealed before either is fully hashed or parsed. Original
  # source seals and full-byte verification belong to the borrowed window.
  guards<-brohn_hold_signal_value_sources(store,list(source_objects=metadata$objects))
  brohn_object_path(store,metadata$artifact$hash,TRUE)
  brohn_object_path(store,metadata$document$hash,TRUE)
  plot<-brohn_read_json_file(metadata$artifact$path,maximum=8*1024^2)
  publication<-brohn_read_json_file(metadata$document$path,maximum=2*1024^2)
  b<-metadata$record$body;summary<-b$result$summary
  brohn_require(all(names(summary) %in% names(plot))&&.brohn_cm_same(plot[names(summary)],summary)&&
    .brohn_cm_same(publication,b[setdiff(names(b),"result_object")]),"The complete plot or retained publication differs from its original saved result.")
  current<-.brohn_cpr_metadata(store,ref,window_handle)
  brohn_require(.brohn_cm_same(current,metadata),"Plot identity or source authority changed while opening its complete artifact.")
  .brohn_cm_guard_check(guards)
  handle<-new.env(parent=emptyenv());class(handle)<-"brohn_clock_plot_resources"
  handle$state<-new.env(parent=emptyenv());handle$state$closed<-FALSE
  handle$reference<-ref;handle$window_handle<-window_handle;handle$metadata<-metadata;handle$guards<-guards
  lockEnvironment(handle,bindings=TRUE);reg.finalizer(handle,brohn_release_clock_plot_resources,onexit=TRUE)
  success<-TRUE
  list(record=metadata$record,handle=handle,plot=plot,artifact=metadata$artifact)
}
brohn_clock_plot_resources_current <- function(store,handle) {
  handle<-.brohn_cpr_handle(handle);.brohn_cm_guard_check(handle$guards)
  current<-.brohn_cpr_metadata(store,handle$reference,handle$window_handle)
  brohn_require(.brohn_cm_same(current,handle$metadata),"This plot no longer matches its opened original window and publication.")
  .brohn_cm_guard_check(handle$guards)
  list(record=current$record,artifact=current$artifact)
}
