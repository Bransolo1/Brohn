# Complete saved-window display preparation. This operation reads retained
# exports; it neither refits the clock map nor performs scientific scoring.
.brohn_clock_plot_files <- c("R/platform-jobs.R","scripts/analysis-worker.R","R/platform-clock-authority.R","R/platform-clock-preview.R","R/platform-clock-map.R",
  "R/platform-clock-jobs.R","R/platform-clock-window.R","R/platform-clock-resources.R","R/platform-clock-plot.R",
  "scripts/workers/clock_plot.py","scripts/workers/clock_plot_worker.py")
.brohn_clock_plot_loaded <- setNames(lapply(.brohn_clock_plot_files,function(p)digest::digest(file=p,algo="sha256")),.brohn_clock_plot_files)
.brohn_clock_plot_display <- list(profile="original-observation-envelope/0.1",bins=512L)
.brohn_cplot_code <- function(request) {
  brohn_require(.brohn_cm_same(request$implementation,.brohn_clock_plot_loaded)&&
    all(vapply(names(.brohn_clock_plot_loaded),function(p)identical(digest::digest(file=p,algo="sha256"),.brohn_clock_plot_loaded[[p]]),logical(1))),
    "Clock-plot implementation changed. Prepare the saved window with the current installation.")
}
brohn_queue_clock_plot <- function(store,window_ref,project_id,retry=FALSE) {
  authority<-brohn_clock_queue_authority(store,"clock_plot",project_id)
  window<-brohn_clock_window_record(store,window_ref,project_id,FALSE)
  r<-list(schema="brohn-clock-plot-job/0.1",project_id=project_id,window=window_ref,map=window$body$map,
    window_document=window$body$result_object,artifacts=window$body$artifacts,display=.brohn_clock_plot_display,
    implementation=.brohn_clock_plot_loaded,authority=authority)
  brohn_enqueue_job(store,"clock_plot",r,paste0("clock-plot:",brohn_hash(r),if(isTRUE(retry))paste0(":",brohn_id("retry"))else""))
}
.brohn_cplot_context <- function(store,r,verify=TRUE,require_current=TRUE) {
  brohn_fields(r,c("schema","project_id","window","map","window_document","artifacts","display","implementation","authority"),label="Complete clock-plot request")
  brohn_require(identical(r$schema,"brohn-clock-plot-job/0.1")&&.brohn_cm_same(r$display,.brohn_clock_plot_display),
    "Use the complete original-observation display profile.")
  if(require_current).brohn_cplot_code(r)
  metadata<-.brohn_cr_metadata(store,r$window,r$project_id);window<-metadata$record
  brohn_require(.brohn_cm_same(window$body$map,r$map)&&.brohn_cm_same(window$body$result_object,r$window_document)&&
    .brohn_cm_same(window$body$artifacts,r$artifacts),"This plot request no longer binds its exact saved window, map and four original exports.")
  if(verify)brohn_require(.brohn_cm_same(window,brohn_clock_window_record(store,r$window,r$project_id,TRUE)),
    "The saved window changed during complete source verification.")
  artifacts<-lapply(metadata$artifacts,function(a)a[c("kind","path","hash","bytes")])
  list(schema="brohn-analysis-input/1.0",operation="clock_plot",project_id=r$project_id,binding=r,
    window_result=window$body$result,artifacts=artifacts,source_objects=metadata$objects,origin=window$body$origin)
}
brohn_clock_plot_input <- function(store,job,verify=TRUE) {
  brohn_require(identical(job$operation,"clock_plot"),"Choose the complete saved-window plot operation.")
  store<-brohn_clock_job_authorize(store,job)
  .brohn_cplot_context(store,job$request,verify)
}
.brohn_cplot_worker_request <- function(input,directory)list(schema="brohn-clock-plot-input/0.1",
  window_ref=c(input$binding$window,list(project_id=input$project_id)),map_ref=input$binding$map,
  window_result=input$window_result,artifacts=input$artifacts,display=input$binding$display,output_directory=directory)
brohn_validate_clock_plot <- function(result,input) {
  brohn_fields(result,c("schema","artifact","summary"),label="Complete clock-plot result")
  brohn_require(identical(result$schema,"brohn-clock-plot-worker-result/0.1"),"Unsupported clock-plot worker result.")
  a<-result$artifact;s<-result$summary;r<-input$binding;w<-input$window_result$result
  brohn_fields(a,c("file","kind","sha256","bytes","media_type"),label="Complete plot artifact")
  brohn_require(identical(a$file,"plot.json")&&identical(a$kind,"clock_plot")&&.brohn_cm_hash(a$sha256)&&
    brohn_number(a$bytes,1,8*1024^2,TRUE)&&identical(a$media_type,"application/json"),"The complete plot artifact is absent or exceeds its display bound.")
  brohn_fields(s,c("schema","status","window_ref","map_ref","binding","artifact_hashes","implementation","coverage","axis","scope",
    "physical_synchronization","uncertainty","scientific_scoring"),label="Complete plot summary")
  hashes<-setNames(lapply(input$artifacts,function(x)x[c("hash","bytes")]),vapply(input$artifacts,`[[`,character(1),"kind"))
  brohn_require(identical(s$schema,"brohn-clock-plot/0.1")&&s$status %in% c("available","empty_window","no_supported_numeric_signal")&&
    .brohn_cm_same(s$window_ref,c(r$window,list(project_id=input$project_id)))&&.brohn_cm_same(s$map_ref,r$map)&&
    .brohn_cm_same(s$binding,w$binding)&&.brohn_cm_same(s$artifact_hashes,hashes)&&
    .brohn_cm_same(s$implementation,list("clock_plot.py"=r$implementation[["scripts/workers/clock_plot.py"]]))&&
    identical(s$scope,"complete_saved_export_display_component_only")&&identical(s$physical_synchronization,"not_established")&&
    identical(s$uncertainty,"unknown")&&identical(s$scientific_scoring,"not_performed"),
    "The plot changed its original window, complete exports, implementation or interpretation.")
  c<-s$coverage
  brohn_fields(c,c("complete_selected_rows_read","complete_unplaced_rows_read","complete_segment_records_read","bins","reduction_profile",
    "source_observation_count","numeric_observations_represented","signal_representatives"),label="Complete plot coverage")
  for(k in setdiff(names(c),"reduction_profile"))brohn_require(brohn_number(c[[k]],0,2000000,TRUE),"The plot contains invalid complete-source coverage counts.")
  brohn_require(c$complete_selected_rows_read==w$counts$selected_rows&&c$complete_unplaced_rows_read==w$counts$unplaced_rows&&
    c$complete_segment_records_read==sum(vapply(w$tracks,`[[`,numeric(1),"segment_count"))&&c$source_observation_count==w$counts$source_rows&&
    c$bins==r$display$bins&&identical(c$reduction_profile,r$display$profile)&&c$numeric_observations_represented<=c$complete_selected_rows_read&&
    c$signal_representatives<=min(32768,c$numeric_observations_represented)&&
    identical(s$status,if(w$counts$selected_rows==0)"empty_window"else if(c$numeric_observations_represented>0)"available"else"no_supported_numeric_signal"),
    "Plot coverage does not reconcile to the complete saved exports.")
  invisible(result)
}
.brohn_cplot_check_artifact <- function(result,input,scratch,directory) {
  brohn_validate_clock_plot(result,input)
  paths<-file.path(scratch,paste0("clock-plot-check-",brohn_id("check"),c("-request.json","-result.json","-proof.json")))
  brohn_write_json_file(.brohn_cplot_worker_request(input,directory),paths[[1L]],maximum=3*1024^2)
  brohn_write_json_file(result,paths[[2L]],maximum=256*1024)
  child<-processx::run(brohn_python_profile("eeg"),c("-B","scripts/workers/clock_plot_worker.py","--request",paths[[1L]],"--result",paths[[2L]],"--output",paths[[3L]]),
    timeout=30,error_on_status=FALSE,cleanup_tree=TRUE,windows_hide_window=TRUE)
  brohn_require(child$status==0L&&file.exists(paths[[3L]]),paste("Complete plot verification needs attention:",substr(paste(child$stdout,child$stderr),1,1000)))
  proof<-brohn_read_json_file(paths[[3L]],maximum=16384)
  brohn_require(identical(proof$schema,"brohn-clock-plot-verification/0.1")&&isTRUE(proof$passed)&&
    identical(proof$request_sha256,digest::digest(file=paths[[1L]],algo="sha256"))&&identical(proof$result_sha256,digest::digest(file=paths[[2L]],algo="sha256"))&&
    identical(proof$scope,"schema_binding_and_plot_bytes_not_original_source_reinspection"),"Plot verification does not bind the exact requested window, result and artifact.")
  invisible(result)
}
brohn_analyse_clock_plot <- function(input,scratch) {
  directory<-file.path(scratch,"artifacts");request<-file.path(scratch,"clock-plot-request.json");output<-file.path(scratch,"clock-plot-result.json")
  brohn_write_json_file(.brohn_cplot_worker_request(input,directory),request,maximum=3*1024^2)
  child<-processx::run(brohn_python_profile("eeg"),c("-B","scripts/workers/clock_plot_worker.py","--request",request,"--output",output),
    timeout=900,error_on_status=FALSE,cleanup_tree=TRUE,windows_hide_window=TRUE)
  brohn_require(child$status==0L&&file.exists(output),paste("Complete clock plot needs attention:",substr(paste(child$stdout,child$stderr),1,1000)))
  result<-brohn_read_json_file(output,maximum=256*1024);.brohn_cplot_check_artifact(result,input,scratch,directory)
  list(clock_plot=result)
}
brohn_publish_clock_plot <- function(store,output,scratch,job,input,output_path) {
  brohn_require(!RSQLite::sqliteIsTransacting(store$con),"Publish clock plots outside an enclosing writer transaction.")
  store<-brohn_clock_job_authorize(store,job,"publish")
  .brohn_publication_output_identity(output,.brohn_clock_plot_loaded);.brohn_publication_job(store,job)
  guards<-brohn_hold_signal_value_sources(store,input);on.exit(for(g in guards).brohn_qexplorer_release(g),add=TRUE)
  output_guard<-.brohn_qexplorer_hold(output_path,file.info(output_path)$size);on.exit(.brohn_qexplorer_release(output_guard),add=TRUE)
  brohn_require(.brohn_cm_same(input,brohn_clock_plot_input(store,job))&&.brohn_cm_same(output,brohn_read_json_file(output_path)),
    "Clock-window source authority or original plot worker output changed before publication.")
  result<-output$report$clock_plot;directory<-file.path(scratch,"artifacts")
  .brohn_cplot_check_artifact(result,input,scratch,directory);a<-result$artifact
  staged<-document<-NULL;committed<-FALSE
  on.exit({if(!is.null(document))brohn_close_publication(document$guard,committed);if(!is.null(staged))brohn_close_publication(staged$guard,committed)},add=TRUE)
  staged<-.brohn_publication_stage(store,job,list(list(key=a$kind,kind=a$kind,
    path=brohn_checked_artifact_path(store,file.path(directory,a$file),scratch),sha256=a$sha256,bytes=a$bytes,media_type=a$media_type)))
  object<-staged$descriptors[[1L]];id<-paste0("clock-plot-",job$id)
  body<-list(schema="brohn-saved-clock-plot/0.1",id=id,window=input$binding$window,map=input$binding$map,request=job$request,
    result=result,artifact=c(list(kind=object$kind),object[c("hash","size","media_type")]),origin=input$origin,created_at=brohn_now(),
    processing=list(job_id=job$id,attempt=job$attempt,worker_output_hash=digest::digest(file=output_path,algo="sha256"),code_hashes=output$code_identity))
  document<-.brohn_publication_stage_json(store,job,body,file.path(scratch,"published-clock-plot.json"))
  receipt<-brohn_store_batch(store,function(){
    store<-brohn_clock_job_fence(store,job)
    brohn_require(.brohn_cm_same(input,.brohn_cplot_context(store,job$request,FALSE)),"Clock source or reader authority changed before plot commit.")
    .brohn_cm_guard_check(c(guards,list(output_guard)))
    .brohn_publication_register(store,staged)
    body$result_object<-.brohn_publication_register(store,document)[[1L]][c("hash","size","media_type")]
    brohn_put_entity(store,"clock_plot",id,body,0L,project_id=input$project_id)
    brohn_complete_job(store,job$id,job$worker,job$token,list(clock_plot_id=id,window_id=body$window$id,map_id=body$map$id,output_hash=body$result_object$hash))
  });committed<-TRUE;receipt
}
brohn_clock_plot_record <- function(store,ref,project_id,verify=TRUE) {
  # Read permission belongs to today's reader, never to an expired producer.
  brohn_clock_queue_authority(store,"clock_plot",project_id);.brohn_cm_ref_valid(ref)
  .brohn_qexplorer_catalog(store,"clock_plot",ref$id,ref$revision,project_id)
  record<-brohn_get_entity(store,"clock_plot",ref$id,ref$revision);head<-brohn_get_entity(store,"clock_plot",ref$id)
  brohn_require(!is.null(record)&&!is.null(head)&&!isTRUE(record$body$archived)&&!isTRUE(head$body$archived)&&
    identical(record$body$id,record$id)&&identical(head$body$id,head$id)&&identical(record$body$schema,"brohn-saved-clock-plot/0.1")&&
    identical(head$body$schema,record$body$schema)&&.brohn_cm_same(.brohn_cm_ref(record),ref),"This exact complete clock plot is no longer available.")
  b<-record$body;p<-b$processing;job<-brohn_get_job(store,p$job_id)
  brohn_require(!is.null(job)&&identical(job$operation,"clock_plot")&&identical(job$status,"succeeded")&&job$attempt==p$attempt&&
    identical(record$id,paste0("clock-plot-",job$id))&&identical(job$result$clock_plot_id,record$id)&&identical(job$result$output_hash,b$result_object$hash)&&
    identical(job$result$window_id,b$window$id)&&identical(job$result$map_id,b$map$id)&&.brohn_cm_same(job$request,b$request)&&
    .brohn_cm_same(b$window,b$request$window)&&.brohn_cm_same(b$map,b$request$map)&&.brohn_cm_hash(p$worker_output_hash)&&
    is.list(b$request$implementation)&&length(b$request$implementation)>0L&&
    all(vapply(names(b$request$implementation),function(path).brohn_cm_hash(b$request$implementation[[path]])&&
      identical(p$code_hashes[[path]],b$request$implementation[[path]]),logical(1))),"This plot lacks its matching succeeded supervised publication.")
  input<-.brohn_cplot_context(store,b$request,verify,FALSE);brohn_validate_clock_plot(b$result,input)
  brohn_require(identical(b$origin,input$origin),"This plot changed the declared source origin.")
  a<-b$result$artifact
  brohn_require(.brohn_cm_same(b$artifact,list(kind=a$kind,hash=a$sha256,size=a$bytes,media_type=a$media_type)),"Saved plot object differs from its original worker descriptor.")
  path<-brohn_object_path(store,b$artifact$hash,verify);brohn_require(file.info(path)$size==b$artifact$size,"Saved plot artifact size changed.")
  .brohn_sv_retained(store,record,"clock_plot",verify)
  record
}
