# External supervised original-row window adapter; integration is qualified in
# its own checkout before any application loader or user flow is enabled.
.brohn_clock_window_files <- c("R/platform-clock-authority.R","R/platform-clock-preview.R","R/platform-clock-map.R","R/platform-clock-jobs.R","R/platform-clock-window.R",
  "scripts/workers/clock_window_worker.py","scripts/workers/clock_window.py","scripts/workers/clock_preview_worker.py",
  "scripts/workers/clock_preview.py","scripts/workers/clock_affine.py","scripts/workers/clock_source.py",
  "scripts/workers/stream_extract.py","scripts/workers/validate_clock_preview_math.py")
.brohn_clock_window_loaded <- setNames(lapply(.brohn_clock_window_files,function(p)digest::digest(file=p,algo="sha256")),.brohn_clock_window_files)
.brohn_cw_selection <- function(x) {
  brohn_fields(x,c("start_s","end_s","offset"),label="Original-row window")
  decimal<-function(v)brohn_text(v,120)&&grepl("^[+-]?(?:[0-9]+(?:\\.[0-9]*)?|\\.[0-9]+)(?:[eE][+-]?[0-9]{1,3})?$",v,perl=TRUE)
  brohn_require(decimal(x$start_s)&&decimal(x$end_s)&&brohn_number(x$offset,0,2000000,TRUE)&&x$offset%%100==0,
    "Choose decimal window endpoints and a bounded 100-row page; exact window support is checked against the saved map.")
  invisible(x)
}
brohn_queue_clock_window <- function(store,map_ref,selection,project_id,retry=FALSE) {
  .brohn_cw_selection(selection)
  # Queueing reads the small pinned map and current project authority only.
  # Full original-source hashes and arithmetic run in supervised processing.
  .brohn_cm_record(store,"clock_map",map_ref,project_id,FALSE)
  request<-list(schema="brohn-clock-window-job/0.1",project_id=project_id,map=map_ref,selection=selection,implementation=.brohn_clock_window_loaded,authority=brohn_clock_queue_authority(store,"clock_window",project_id))
  brohn_enqueue_job(store,"clock_window",request,paste0("clock-window:",brohn_hash(request),if(isTRUE(retry))paste0(":",brohn_id("retry"))else""))
}
.brohn_cw_context <- function(store,request,verify=TRUE,validate_map=TRUE,require_current=TRUE) {
  brohn_fields(request,c("schema","project_id","map","selection","implementation"),optional="authority",label="Saved-map window request")
  brohn_require(identical(request$schema,"brohn-clock-window-job/0.1"),"Unsupported saved-map window request.")
  .brohn_cw_selection(request$selection)
  if(require_current)brohn_require(.brohn_cm_same(request$implementation,.brohn_clock_window_loaded)&&
    all(vapply(names(.brohn_clock_window_loaded),function(p)identical(digest::digest(file=p,algo="sha256"),.brohn_clock_window_loaded[[p]]),logical(1))),
    "Clock-window implementation changed after queueing; prepare a new review with the current installation.")
  map<-if(validate_map)brohn_clock_map_record(store,request$map,request$project_id,brohn_clock_preview_runtime(tempdir()),verify)else
    .brohn_cm_record(store,"clock_map",request$map,request$project_id,verify)
  b<-map$body;preview<-.brohn_cm_record(store,"clock_preview",b$preview,request$project_id,verify)
  brohn_require(identical(b$request$project_id,request$project_id)&&.brohn_cm_same(b$request,preview$body$request)&&
    .brohn_cm_same(b$result,preview$body$result)&&.brohn_cm_same(b$implementation,preview$body$implementation)&&
    .brohn_cm_same(b$family,.brohn_cm_family(b$request,b$result)),"The selected map no longer binds its accepted original preview.")
  input<-brohn_clock_map_source_input(store,b$request,verify)
  input$source_objects<-c(input$source_objects,lapply(list(b$result_object,preview$body$result_object),function(a)list(hash=a$hash,bytes=a$size)))
  list(schema="brohn-analysis-input/1.0",operation="clock_window",project_id=request$project_id,binding=request,
    preview_request=input$preview,expected_preview=b$result,origin=b$result$origin,source_objects=input$source_objects)
}
brohn_clock_window_input <- function(store,job,verify=TRUE) {
  brohn_require(identical(job$operation,"clock_window"),"Use a saved-map window job.")
  store<-brohn_clock_job_authorize(store,job)
  .brohn_cw_context(store,job$request,verify)
}
.brohn_cw_worker_request <- function(input,directory)list(schema="brohn-clock-window-worker-request/0.1",
  window=list(schema="brohn-clock-window-input/0.1",preview_request=input$preview_request,selection=input$binding$selection,output_directory=directory),
  expected_preview=input$expected_preview)
brohn_validate_clock_window <- function(result,input,scratch,directory) {
  # This checker validates exact arithmetic and export bytes; original complete
  # source inspection is performed by the worker while native source seals hold.
  paths<-file.path(scratch,paste0("clock-window-check-",brohn_id("check"),c("-request.json","-result.json","-proof.json")))
  brohn_write_json_file(.brohn_cw_worker_request(input,directory),paths[[1L]],maximum=3*1024^2)
  brohn_write_json_file(result,paths[[2L]],maximum=2*1024^2)
  child<-processx::run(brohn_python_profile("eeg"),c("-B","scripts/workers/clock_window_worker.py","--request",paths[[1L]],"--result",paths[[2L]],"--output",paths[[3L]]),
    timeout=15,error_on_status=FALSE,cleanup_tree=TRUE,windows_hide_window=TRUE)
  brohn_require(child$status==0L&&file.exists(paths[[3L]]),paste("Original-row export verification needs attention:",substr(paste(child$stdout,child$stderr),1,1000)))
  proof<-brohn_read_json_file(paths[[3L]],maximum=16384)
  brohn_require(identical(proof$schema,"brohn-clock-window-verification/0.1")&&isTRUE(proof$passed)&&
    identical(proof$request_sha256,digest::digest(file=paths[[1L]],algo="sha256"))&&identical(proof$result_sha256,digest::digest(file=paths[[2L]],algo="sha256"))&&
    identical(proof$scope,"schema_exact_arithmetic_and_export_bytes_not_original_source_reinspection"),"Window verification does not bind the exact requested map, result and exports.")
  invisible(result)
}
brohn_analyse_clock_window <- function(input,scratch) {
  directory<-file.path(scratch,"artifacts")
  request<-file.path(scratch,"clock-window-request.json");output<-file.path(scratch,"clock-window-result.json")
  brohn_write_json_file(.brohn_cw_worker_request(input,directory),request,maximum=3*1024^2)
  child<-processx::run(brohn_python_profile("eeg"),c("-B","scripts/workers/clock_window_worker.py","--request",request,"--output",output),
    timeout=900,error_on_status=FALSE,cleanup_tree=TRUE,windows_hide_window=TRUE)
  brohn_require(child$status==0L&&file.exists(output),paste("Original-row window needs attention:",substr(paste(child$stdout,child$stderr),1,1000)))
  result<-brohn_read_json_file(output,maximum=2*1024^2)
  brohn_validate_clock_window(result,input,scratch,directory)
  list(clock_window=result)
}
.brohn_cw_artifacts <- function(result) {
  c(lapply(result$result$artifacts,function(a)c(a,list(media_type=if(identical(a$file,"segments.jsonl"))"application/x-ndjson"else"text/csv"))),
    list(result$manifest_artifact))
}
brohn_publish_clock_window <- function(store,output,scratch,job,input,output_path) {
  brohn_require(!RSQLite::sqliteIsTransacting(store$con),"Publish original-row windows outside an enclosing writer transaction.")
  store<-brohn_clock_job_authorize(store,job,"publish")
  .brohn_publication_output_identity(output,.brohn_clock_window_loaded);.brohn_publication_job(store,job)
  guards<-brohn_hold_signal_value_sources(store,input);on.exit(for(g in guards).brohn_qexplorer_release(g),add=TRUE)
  output_guard<-.brohn_qexplorer_hold(output_path,file.info(output_path)$size);on.exit(.brohn_qexplorer_release(output_guard),add=TRUE)
  brohn_require(.brohn_cm_same(input,brohn_clock_window_input(store,job))&&.brohn_cm_same(output,brohn_read_json_file(output_path)),
    "Saved map, source authority or original worker output changed before publication.")
  result<-output$report$clock_window;directory<-file.path(scratch,"artifacts")
  brohn_validate_clock_window(result,input,scratch,directory)
  staged<-document<-NULL;committed<-FALSE
  on.exit({if(!is.null(document))brohn_close_publication(document$guard,committed);if(!is.null(staged))brohn_close_publication(staged$guard,committed)},add=TRUE)
  staged<-.brohn_publication_stage(store,job,lapply(.brohn_cw_artifacts(result),function(a)list(key=a$kind,kind=a$kind,
    path=brohn_checked_artifact_path(store,file.path(directory,a$file),scratch),sha256=a$sha256,bytes=a$bytes,media_type=a$media_type)))
  objects<-lapply(staged$descriptors,function(a)c(list(kind=a$kind),a[c("hash","size","media_type")]))
  id<-paste0("clock-window-",job$id)
  body<-list(schema="brohn-saved-clock-window/0.1",id=id,map=input$binding$map,request=job$request,result=result,artifacts=objects,
    origin=input$origin,created_at=brohn_now(),processing=list(job_id=job$id,attempt=job$attempt,
      worker_output_hash=digest::digest(file=output_path,algo="sha256"),code_hashes=output$code_identity))
  document<-.brohn_publication_stage_json(store,job,body,file.path(scratch,"published-clock-window.json"))
  receipt<-brohn_store_batch(store,function(){
    store<-brohn_clock_job_fence(store,job)
    brohn_require(.brohn_cm_same(input,.brohn_cw_context(store,job$request,FALSE,FALSE)),"Clock map or source authority changed before export commit.")
    .brohn_cm_guard_check(c(guards,list(output_guard)))
    .brohn_publication_register(store,staged)
    body$result_object<-.brohn_publication_register(store,document)[[1L]][c("hash","size","media_type")]
    brohn_put_entity(store,"clock_window",id,body,0L,project_id=input$project_id)
    brohn_complete_job(store,job$id,job$worker,job$token,list(clock_window_id=id,map_id=body$map$id,output_hash=body$result_object$hash))
  });committed<-TRUE;receipt
}
brohn_clock_window_record <- function(store,ref,project_id,verify=TRUE) {
  brohn_hosted_require_session(store);brohn_hosted_require_project(store,project_id);brohn_project(store,project_id);.brohn_cm_ref_valid(ref)
  .brohn_qexplorer_catalog(store,"clock_window",ref$id,ref$revision,project_id)
  record<-brohn_get_entity(store,"clock_window",ref$id,ref$revision);head<-brohn_get_entity(store,"clock_window",ref$id)
  brohn_require(!is.null(record)&&!is.null(head)&&!isTRUE(record$body$archived)&&!isTRUE(head$body$archived)&&
    identical(record$body$id,record$id)&&identical(head$body$id,head$id)&&identical(record$body$schema,"brohn-saved-clock-window/0.1")&&
    identical(head$body$schema,record$body$schema)&&.brohn_cm_same(.brohn_cm_ref(record),ref),"This exact original-row window is no longer available.")
  b<-record$body;p<-b$processing;job<-brohn_get_job(store,p$job_id)
  brohn_require(!is.null(job)&&identical(job$operation,"clock_window")&&identical(job$status,"succeeded")&&job$attempt==p$attempt&&
    identical(record$id,paste0("clock-window-",job$id))&&identical(job$result$clock_window_id,record$id)&&identical(job$result$output_hash,b$result_object$hash)&&
    identical(job$result$map_id,b$map$id)&&.brohn_cm_same(job$request,b$request)&&.brohn_cm_same(b$map,b$request$map)&&.brohn_cm_hash(p$worker_output_hash)&&
    is.list(b$request$implementation)&&length(b$request$implementation)>0L&&
    all(vapply(names(b$request$implementation),function(path).brohn_cm_hash(b$request$implementation[[path]])&&
      identical(p$code_hashes[[path]],b$request$implementation[[path]]),logical(1))),"This window lacks its matching succeeded supervised publication.")
  context<-.brohn_cw_context(store,b$request,verify,FALSE,FALSE)
  brohn_require(.brohn_cm_same(b$result$result$preview,context$expected_preview)&&identical(b$origin,context$origin),"Saved export substituted its reviewed mapping or source origin.")
  originals<-.brohn_cw_artifacts(b$result)
  brohn_require(length(originals)==4L&&length(b$artifacts)==4L,"Original-row exports are incomplete.")
  for(i in seq_along(originals)) {
    a<-originals[[i]];saved<-b$artifacts[[i]]
    brohn_require(.brohn_cm_same(saved,list(kind=a$kind,hash=a$sha256,size=a$bytes,media_type=a$media_type)),"Saved export object differs from its original worker descriptor.")
    path<-brohn_object_path(store,saved$hash,verify);brohn_require(file.info(path)$size==saved$size,"Saved export size changed.")
  }
  .brohn_sv_retained(store,record,"clock_window",verify)
  record
}
