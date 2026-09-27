# Integration candidate: copied into a separate qualification checkout before
# registering its hooks. Do not source this against the ongoing UI qualification.
.brohn_clock_job_files <- c("R/platform-clock-authority.R", "R/platform-clock-preview.R", "R/platform-clock-map.R", "R/platform-clock-jobs.R",
  "scripts/workers/clock_preview_worker.py", "scripts/workers/clock_preview.py", "scripts/workers/clock_affine.py",
  "scripts/workers/clock_source.py", "scripts/workers/stream_extract.py", "scripts/workers/validate_clock_preview_math.py")
.brohn_clock_jobs_loaded <- setNames(lapply(.brohn_clock_job_files,function(p)digest::digest(file=p,algo="sha256")),.brohn_clock_job_files)

brohn_clock_preview_runtime <- function(scratch) {
  brohn_clock_map_runtime(brohn_python_profile("eeg"),"scripts/workers/clock_affine.py",
    "scripts/workers/validate_clock_preview_math.py",scratch)
}
brohn_queue_clock_preview <- function(store,source,reference,anchors,checks,review,project_id,retry=FALSE) {
  preview<-brohn_prepare_clock_preview(store,source,reference,anchors,checks,review,project_id)
  request<-list(schema="brohn-clock-preview-dispatch/0.1",project_id=project_id,preview=preview,implementation=.brohn_clock_jobs_loaded,
    authority=brohn_clock_queue_authority(store,"preview_clock_alignment",project_id))
  brohn_enqueue_job(store,"preview_clock_alignment",request,paste0("clock-preview:",brohn_hash(request),
    if(isTRUE(retry))paste0(":",brohn_id("retry"))else""))
}
brohn_clock_preview_job_input <- function(store,job,verify=TRUE) {
  store<-brohn_clock_job_authorize(store,job)
  r<-job$request
  brohn_fields(r,c("schema","project_id","preview","implementation","authority"),label="Reviewed clock preview job")
  brohn_require(identical(job$operation,"preview_clock_alignment")&&identical(r$schema,"brohn-clock-preview-dispatch/0.1")&&
    identical(r$project_id,r$preview$project_id)&&.brohn_cm_same(r$implementation,.brohn_clock_jobs_loaded)&&
    all(vapply(names(.brohn_clock_jobs_loaded),function(p)identical(digest::digest(file=p,algo="sha256"),.brohn_clock_jobs_loaded[[p]]),logical(1))),
    "Clock preview code or project changed after queueing; review a new preview with the current installation.")
  brohn_clock_preview_input(store,r$preview,verify)
}
brohn_analyse_clock_preview <- function(input,scratch) {
  request_path<-file.path(scratch,"clock-preview-request.json");result_path<-file.path(scratch,"clock-preview-result.json")
  brohn_write_json_file(input$preview,request_path,maximum=1024^2)
  child<-processx::run(brohn_python_profile("eeg"),c("-B","scripts/workers/clock_preview_worker.py",
    "--request",request_path,"--output",result_path),timeout=15*60,error_on_status=FALSE,cleanup_tree=TRUE,windows_hide_window=TRUE)
  diagnostic<-if(nzchar(trimws(child$stdout)))child$stdout else child$stderr
  brohn_require(child$status==0L&&file.exists(result_path),paste("Clock preview needs attention:",substr(diagnostic,1,1000)))
  result<-brohn_read_json_file(result_path,maximum=1024^2)
  runtime<-brohn_clock_preview_runtime(scratch)
  brohn_validate_clock_preview_result(result,input,runtime)
  list(clock_preview=result,clock_preview_implementation=runtime$identity)
}
brohn_publish_clock_preview <- function(store,output,scratch,job,input,output_path) {
  brohn_require(!RSQLite::sqliteIsTransacting(store$con),"Publish reviewed clock previews outside an enclosing writer transaction.")
  store<-brohn_clock_job_authorize(store,job,"publish")
  .brohn_publication_output_identity(output,.brohn_clock_jobs_loaded);.brohn_publication_job(store,job)
  guards<-brohn_hold_signal_value_sources(store,input)
  on.exit(for(g in guards).brohn_qexplorer_release(g),add=TRUE)
  output_guard<-.brohn_qexplorer_hold(output_path,file.info(output_path)$size)
  on.exit(.brohn_qexplorer_release(output_guard),add=TRUE)
  brohn_require(.brohn_cm_same(input,brohn_clock_preview_job_input(store,job))&&
    .brohn_cm_same(output,brohn_read_json_file(output_path)),"Clock source authority or exact worker output changed before publication.")
  runtime<-brohn_clock_preview_runtime(scratch);result<-output$report$clock_preview
  brohn_require(.brohn_cm_same(output$report$clock_preview_implementation,runtime$identity),"Clock validator implementation changed during processing.")
  brohn_validate_clock_preview_result(result,input,runtime)
  id<-paste0("clock-preview-",job$id)
  body<-list(schema="brohn-saved-clock-preview/0.1",id=id,request=input$binding,result=result,
    implementation=runtime$identity,created_at=brohn_now(),origin=result$origin,
    processing=list(job_id=job$id,attempt=job$attempt,worker_output_hash=digest::digest(file=output_path,algo="sha256"),code_hashes=output$code_identity))
  document<-NULL;committed<-FALSE
  on.exit(if(!is.null(document))brohn_close_publication(document$guard,committed),add=TRUE)
  document<-.brohn_publication_stage_json(store,job,body,file.path(scratch,"published-clock-preview.json"))
  receipt<-brohn_store_batch(store,function(){
    store<-brohn_clock_job_fence(store,job)
    brohn_require(.brohn_cm_same(input,brohn_clock_preview_job_input(store,job,FALSE)),"Clock source authority changed before the preview could be committed.")
    .brohn_cm_guard_check(c(guards,list(output_guard)))
    body$result_object<-.brohn_publication_register(store,document)[[1L]][c("hash","size","media_type")]
    brohn_put_entity(store,"clock_preview",id,body,0L,project_id=input$project_id)
    brohn_complete_job(store,job$id,job$worker,job$token,list(clock_preview_id=id,output_hash=body$result_object$hash))
  })
  committed<-TRUE;receipt
}
