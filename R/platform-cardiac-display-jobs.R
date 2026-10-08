# Native lifecycle for a new, explicit saved-cardiac display operation.
# This candidate is not registered until its complete installation is joined.
.brohn_cdd_one <- function(values, predicate, message) {
  found <- Filter(predicate, values)
  brohn_require(length(found)==1L, message)
  found[[1L]]
}
.brohn_cdd_object <- function(x, schema) {
  c(.brohn_td_object_ref(x), list(schema=schema))
}
.brohn_cdd_original_report <- function(handle, ref=handle$metadata$report_ref) {
  .brohn_cdd_one(handle$reports, function(x).brohn_rpk_same(x$ref,ref),
    "The exact original cardiac report was not sealed.")
}
.brohn_cdd_source_binding <- function(report, metadata, pulse=NULL) {
  selected <- metadata$selected
  brohn_require(.brohn_rpk_same(report$ref,selected$ref),"Cardiac source binding selected another report.")
  .brohn_rpk_source_pulse(pulse)
  native_hash <- brohn_hash(report$complete_analysis);.brohn_rpk_source_pulse(pulse)
  typed_hash <- brohn_eda_value_hash(report$complete_analysis);.brohn_rpk_source_pulse(pulse)
  list(report_ref=report$ref, analysis_hash=native_hash,analysis_value_hash=typed_hash,
    dataset_ref=selected$dataset_ref,
    result_object=.brohn_cdd_object(report$saved_body$result_object,"brohn-analysis-output/1.0"),
    original_stream_descriptors=report$complete_analysis$artifacts,
    source_closure_hash=metadata$closure_hash)
}
.brohn_cdd_worker_request <- function(handle, display_request, implementation, pulse=NULL) {
  .brohn_rpk_source_pulse(pulse)
  brohn_require(is.environment(handle)&&inherits(handle,"brohn_cardiac_source_resources")&&
    environmentIsLocked(handle)&&!isTRUE(handle$state$closed),"Open the original cardiac source before preparing its request.")
  .brohn_cm_guard_check(handle$guards)
  metadata <- handle$metadata
  report <- .brohn_cdd_original_report(handle)
  context <- .brohn_cdd_one(metadata$contexts,function(x).brohn_rpk_same(x$report_ref,report$ref),
    "The exact report has no unique cardiac source context.")
  object <- function(hash) {
    x <- .brohn_cdd_one(metadata$objects,function(o)identical(o$hash,hash),"A cardiac dependency has no unique sealed object.")
    x[c("hash","bytes","path")]
  }
  snapshot <- function(ref, body) {
    .brohn_rpk_source_pulse(pulse);hash <- brohn_eda_value_hash(body);.brohn_rpk_source_pulse(pulse)
    list(ref=ref,body=body,body_value_hash=hash)
  }
  producer <- function(job, result_object, schema) {
    brohn_require(identical(job$status,"succeeded")&&identical(job$result$output_hash,result_object$hash),
      "The cardiac dependency producer does not bind its saved result.")
    # This compact producer receipt mirrors saved_body.processing: its hash
    # identifies the executed input. The distinct original queue request/hash
    # remains complete in source_closure.jobs and original_producer_request.
    brohn_require(.brohn_rpk_hash(job$execution_request_hash),"The original executed cardiac input hash is missing.")
    list(job_id=job$id,operation=job$operation,attempt=job$attempt,request_hash=job$execution_request_hash,
      result_object=.brohn_cdd_object(result_object,schema))
  }
  exclusion <- NULL
  x <- context$exclusion
  if(!is.null(x)) {
    parent <- .brohn_cdd_original_report(handle,x$parent_ref)
    pj <- .brohn_cdd_one(metadata$closure$jobs,function(j)identical(j$id,x$preview$processing$job_id),
      "The accepted cardiac preview has no original successful producer.")
    binding <- list(parent_report_ref=x$parent_ref,review_ref=x$review_ref,
      catalogue_ref=x$catalog_ref,accepted_preview_ref=x$preview_ref,
      preview_producer=producer(pj,x$preview$result_object,"brohn-saved-cardiac-review-preview/1.0"),
      reanalysis_producer=producer(x$producer,report$saved_body$result_object,"brohn-analysis-output/1.0"),
      accepted_preview_ledger_value_hash=brohn_eda_value_hash(x$preview$preview$ledger),
      saved_exclusion_review_value_hash=brohn_eda_value_hash(report$complete_analysis$exclusion_review))
    exclusion <- list(binding=binding,original_producer_request=x$producer$request,
      parent_report=snapshot(x$parent_ref,parent$saved_body),
      review=snapshot(x$review_ref,x$review),catalogue=snapshot(x$catalog_ref,x$catalog),
      accepted_preview=snapshot(x$preview_ref,x$preview))
  }
  curation <- NULL
  if(!is.null(context$lineage$binding$curation_ref)) {
    artifacts <- context$dataset$lineage$artifacts
    decision <- .brohn_cdd_one(artifacts,function(a)identical(a$kind,"curation_decisions_jsonl"),
      "The curated cardiac source lacks its exact complete decisions stream.")
    derived <- .brohn_cdd_one(artifacts,function(a)identical(a$kind,"curated_signal_csv"),
      "The curated cardiac source lacks its exact derived CSV.")
    brohn_require(identical(derived$hash,context$dataset$source$hash),
      "The curated CSV differs from the original analysed source.")
    curation <- list(binding=list(refs=context$lineage$binding,dataset_ref=context$dataset$ref,
      source_provenance=context$dataset$lineage),decisions_object=object(decision$hash),
      derived_csv_object=object(derived$hash),format="csv")
  }
  streams <- lapply(seq_along(report$complete_analysis$artifacts),function(i) {
    a <- report$complete_analysis$artifacts[[i]]
    list(original=a,original_verification=report$complete_analysis$artifact_verification$artifacts[[i]],path=object(a$hash)$path)
  })
  result <- list(schema="brohn-cardiac-display-worker-request/0.1",report=report,
    source=.brohn_cdd_source_binding(report,metadata,pulse),source_closure=metadata$closure,
    display_request=brohn_normalize_cardiac_display_request(display_request),implementation=implementation,
    streams=streams,original_source=object(context$dataset$source$hash),
    sealed_objects=lapply(metadata$objects,function(o)o[c("hash","bytes","path")]),
    lineage=list(exclusion=exclusion,curation=curation))
  .brohn_cm_guard_check(handle$guards)
  result
}

brohn_validate_cardiac_refusal <- function(value) {
  brohn_fields(value,c("schema","reason_code","stage","source_ref","cell_key","resource",
    "measured","maximum","recovery_scope","blocked_request_hash","message"),label="Cardiac preparation refusal")
  quantity <- function(x)is.null(x)||brohn_number(x)
  brohn_require(identical(value$schema,"brohn-cardiac-report-refusal/0.1")&&
    brohn_text(value$reason_code,500)&&brohn_text(value$resource,500)&&
    value$stage %in% c("metadata","source_validation","display","projection","publication")&&
    (is.null(value$cell_key)||.brohn_rpk_hash(value$cell_key))&&quantity(value$measured)&&quantity(value$maximum)&&
    value$recovery_scope %in% c("none","fewer_sources","smaller_window","fewer_figures","repair_source","new_preparation","original_exports_only")&&
    .brohn_rpk_hash(value$blocked_request_hash)&&brohn_text(value$message,4000),"The cardiac refusal is malformed.")
  if(!is.null(value$source_ref)).brohn_rpk_ref_valid(value$source_ref,"report")
  invisible(TRUE)
}
brohn_stop_cardiac_refusal <- function(value) {
  brohn_validate_cardiac_refusal(value)
  stop(structure(list(message=value$message,call=NULL,refusal=value),class=c("brohn_cardiac_refusal","error","condition")))
}

.brohn_cdd_queue_request <- function(store,report_ref,display_request=NULL,implementation_ref=NULL) {
  authority <- brohn_report_package_queue_authority(store,"cardiac_display",report_ref$project_id)
  implementation <- brohn_cardiac_display_implementation()
  if(!is.null(implementation_ref))brohn_require(.brohn_rpk_same(implementation_ref,.brohn_td_implementation_ref(implementation)),
    "The cardiac display implementation changed. Review the new preparation before continuing.")
  metadata <- brohn_cardiac_source_metadata(store,report_ref)
  request <- list(schema="brohn-cardiac-display-job/0.1",project_id=report_ref$project_id,
    study_id=metadata$selected$study_id,report_ref=report_ref,
    display_request=brohn_normalize_cardiac_display_request(display_request),
    original_closure=metadata$closure,source_closure_hash=metadata$closure_hash,
    preparation_profile=.brohn_cdd_profile,implementation=implementation,authority=authority)
  request$content_fingerprint <- brohn_hash(request[setdiff(names(request),"authority")])
  request
}
brohn_queue_cardiac_display <- function(store,report_ref,display_request=NULL,retry=FALSE,implementation_ref=NULL) {
  request <- .brohn_cdd_queue_request(store,report_ref,display_request,implementation_ref)
  brohn_store_batch(store,function() {
    old <- .brohn_rpk_latest_job(store,"cardiac_display",request$content_fingerprint)
    if(!is.null(old)&&(!isTRUE(retry)||old$status %in% c("queued","running","succeeded")))return(old)
    brohn_enqueue_job(store,"cardiac_display",request,paste0("cardiac-display:",request$content_fingerprint,
      if(isTRUE(retry))paste0(":",brohn_id("retry"))else""))
  })
}
brohn_cardiac_display_input <- function(store,job,verify=FALSE) {
  store <- brohn_report_package_job_authorize(store,job)
  r <- job$request
  brohn_fields(r,c("schema","project_id","study_id","report_ref","display_request","original_closure",
    "source_closure_hash","preparation_profile","implementation","authority","content_fingerprint"),label="Cardiac display job")
  brohn_require(identical(job$operation,"cardiac_display")&&identical(r$schema,"brohn-cardiac-display-job/0.1")&&
    identical(r$preparation_profile,.brohn_cdd_profile)&&identical(r$project_id,r$report_ref$project_id)&&
    .brohn_rpk_same(r$display_request,brohn_normalize_cardiac_display_request(r$display_request))&&
    .brohn_rpk_same(r$implementation,brohn_cardiac_display_implementation())&&
    identical(r$content_fingerprint,brohn_hash(r[setdiff(names(r),c("authority","content_fingerprint"))])),
    "The cardiac preparation request or implementation changed.")
  metadata <- brohn_cardiac_source_metadata(store,r$report_ref)
  brohn_require(identical(r$source_closure_hash,metadata$closure_hash)&&
    .brohn_rpk_same(r$original_closure,metadata$closure)&&identical(r$study_id,metadata$selected$study_id),
    "The cardiac source closure or its current permission changed.")
  list(schema="brohn-analysis-input/1.0",operation="cardiac_display",project_id=r$project_id,
    report_ref=r$report_ref,content_fingerprint=r$content_fingerprint)
}

# Both the source seals and the bundle seal outlive the R/Python descendants.
# The supervisor calls this release only after terminating its complete tree.
brohn_release_cardiac_display_execution <- function(execution) {
  if(is.environment(execution)&&inherits(execution,"brohn_cardiac_execution_resources")&&!isTRUE(execution$state$closed)) {
    state <- execution$state;state$closed <- TRUE
    on.exit(brohn_release_cardiac_display_sources(execution$sources),add=TRUE)
    if(!is.null(execution$bundle_guard)).brohn_qexplorer_release(execution$bundle_guard)
  }
  invisible(NULL)
}
brohn_prepare_cardiac_display_execution <- function(store,job,input,scratch,pulse=NULL) {
  .brohn_rpk_source_pulse(pulse)
  store <- brohn_report_package_job_authorize(store,job)
  .brohn_cdd_check_code(job$request$implementation)
  brohn_require(.brohn_rpk_same(input,brohn_cardiac_display_input(store,job)),"The cardiac input changed before sealing.")
  sources <- brohn_open_cardiac_display_sources(store,job$request$report_ref,job$request$source_closure_hash,pulse)
  guard <- NULL;ok <- FALSE
  on.exit(if(!ok){if(!is.null(guard)).brohn_qexplorer_release(guard);brohn_release_cardiac_display_sources(sources)},add=TRUE)
  request <- .brohn_cdd_worker_request(sources,job$request$display_request,job$request$implementation,pulse)
  bundle <- list(schema="brohn-cardiac-display-input-bundle/0.1",worker_request=request,request_hash=brohn_hash(job$request))
  path <- file.path(scratch,"cardiac-display-input.json")
  brohn_require(!file.exists(path),"The cardiac preparation bundle already exists.")
  .brohn_rpk_source_pulse(pulse)
  brohn_eda_write_json_file(bundle,path,48*1024^2)
  guard <- .brohn_qexplorer_hold(path,file.info(path)$size)
  input$cardiac_display <- list(schema="brohn-cardiac-display-prepared-input/0.1",
    bundle=list(file="cardiac-display-input.json",sha256=digest::digest(file=path,algo="sha256"),bytes=as.numeric(file.info(path)$size)))
  brohn_cardiac_display_sources_current(store,sources)
  brohn_report_package_job_authorize(store,job);.brohn_rpk_source_pulse(pulse)
  handle <- new.env(parent=emptyenv());class(handle) <- "brohn_cardiac_execution_resources"
  handle$sources <- sources;handle$bundle_guard <- guard;handle$state <- new.env(parent=emptyenv());handle$state$closed <- FALSE
  lockEnvironment(handle,bindings=TRUE);reg.finalizer(handle,brohn_release_cardiac_display_execution,onexit=TRUE)
  ok <- TRUE;list(input=input,handle=handle)
}
.brohn_cdd_bundle <- function(input,scratch) {
  x <- input$cardiac_display
  brohn_fields(x,c("schema","bundle"),label="Prepared cardiac input")
  d <- x$bundle;brohn_fields(d,c("file","sha256","bytes"),label="Sealed cardiac bundle")
  brohn_require(identical(x$schema,"brohn-cardiac-display-prepared-input/0.1")&&
    identical(d$file,"cardiac-display-input.json")&&.brohn_rpk_hash(d$sha256)&&brohn_number(d$bytes,1,48*1024^2,TRUE),
    "The prepared cardiac bundle descriptor is invalid.")
  path <- normalizePath(file.path(scratch,d$file),winslash="/",mustWork=TRUE)
  root <- normalizePath(scratch,winslash="/",mustWork=TRUE);link <- Sys.readlink(path)
  brohn_require(identical(dirname(path),root)&&(is.na(link)||!nzchar(link))&&file.info(path)$size==d$bytes&&
    identical(digest::digest(file=path,algo="sha256"),d$sha256),"The cardiac bundle changed or left owned scratch.")
  b <- brohn_eda_read_json_file(path,48*1024^2)
  brohn_fields(b,c("schema","worker_request","request_hash"),label="Complete cardiac input bundle")
  brohn_require(identical(b$schema,"brohn-cardiac-display-input-bundle/0.1")&&
    .brohn_rpk_same(b$worker_request$report$ref,input$report_ref),"The cardiac bundle belongs to another source.")
  b
}
brohn_analyse_cardiac_display <- function(input,scratch) {
  bundle <- .brohn_cdd_bundle(input,scratch);request <- bundle$worker_request
  .brohn_cdd_check_code(request$implementation)
  request_path <- file.path(scratch,"cardiac-display-worker-request.json")
  result_path <- file.path(scratch,"cardiac-display-worker-result.json")
  directory <- file.path(scratch,"artifacts")
  brohn_require(!file.exists(request_path)&&!file.exists(result_path)&&!dir.exists(directory),"Cardiac display output paths must be fresh.")
  brohn_eda_write_json_file(request,request_path,48*1024^2)
  child <- processx::run(brohn_python_profile("ecg"),c("scripts/workers/cardiac_display.py","--request",request_path,
    "--output",result_path,"--artifacts",directory),timeout=300,error_on_status=FALSE,cleanup_tree=TRUE,windows_hide_window=TRUE)
  brohn_require(file.exists(result_path),paste("Cardiac display returned no bounded result.",substr(child$stderr,1,500)))
  result <- brohn_eda_read_json_file(result_path,3*1024^2)
  if(child$status!=0L) {
    if(identical(result$schema,"brohn-cardiac-report-refusal/0.1")){
      brohn_validate_cardiac_refusal(result);return(list(cardiac_display=result))
    }
    brohn_stop(paste("Cardiac display preparation failed:",substr(brohn_default(result$error$message,substr(child$stderr,1,500)),1,1000)))
  }
  brohn_fields(result,c("schema","artifact","source","display_request","implementation","catalog","coverage","payloads","verification"),
    label="Cardiac display worker result")
  brohn_require(identical(result$schema,"brohn-cardiac-display-worker-result/0.1")&&
    .brohn_rpk_same(result$source,request$source)&&.brohn_rpk_same(result$display_request,request$display_request)&&
    .brohn_rpk_same(result$implementation,request$implementation)&&
    identical(result$verification$request_sha256,digest::digest(file=request_path,algo="sha256"))&&
    identical(result$verification$analysis_value_hash,request$source$analysis_value_hash)&&
    identical(result$verification$source_closure_value_hash,brohn_eda_value_hash(request$source_closure)),
    "The cardiac worker changed its source, request or complete values.")
  result$input_binding_hash <- input$content_fingerprint
  list(cardiac_display=result)
}

brohn_publish_cardiac_display <- function(store,output,scratch,job,input,output_path,pulse=NULL) {
  .brohn_rpk_source_pulse(pulse)
  store <- brohn_report_package_job_authorize(store,job,"publish")
  .brohn_publication_job(store,job);.brohn_cdd_check_code(job$request$implementation)
  .brohn_publication_output_identity(output,job$request$implementation$sources)
  brohn_cardiac_display_input(store,job)
  bundle <- .brohn_cdd_bundle(input,scratch);request <- bundle$worker_request
  brohn_require(identical(bundle$request_hash,brohn_hash(job$request))&&
    .brohn_rpk_same(request$implementation,job$request$implementation)&&
    .brohn_rpk_same(request$display_request,job$request$display_request),"The cardiac bundle lost its original queued identity.")
  sources <- brohn_open_cardiac_display_sources(store,job$request$report_ref,job$request$source_closure_hash,pulse)
  on.exit(brohn_release_cardiac_display_sources(sources),add=TRUE)
  original <- .brohn_cdd_original_report(sources)
  brohn_require(.brohn_cdd_equal(request$source,.brohn_cdd_source_binding(original,sources$metadata,pulse))&&
    .brohn_cdd_equal(request$source_closure,sources$metadata$closure),"The prepared cardiac source differs from its exact current authorized original.")
  guards <- list();on.exit(for(g in guards)tryCatch(.brohn_qexplorer_release(g),error=function(e)NULL),add=TRUE)
  hold <- function(path,bytes) {
    g <- .brohn_qexplorer_hold(path,bytes);guards[[length(guards)+1L]] <<- g;path
  }
  hold(output_path,file.info(output_path)$size)
  brohn_require(.brohn_cdd_equal(brohn_eda_read_json_file(output_path),output),"Cardiac worker output changed before publication.")
  result <- output$report$cardiac_display
  request_path <- file.path(scratch,"cardiac-display-worker-request.json")
  hold(request_path,file.info(request_path)$size)
  brohn_require(.brohn_cdd_equal(brohn_eda_read_json_file(request_path,48*1024^2),request),
    "The cardiac child request differs from the sealed source bundle.")
  if(identical(result$schema,"brohn-cardiac-report-refusal/0.1")) {
    brohn_validate_cardiac_refusal(result)
    brohn_require(identical(result$blocked_request_hash,digest::digest(file=request_path,algo="sha256")),
      "The cardiac refusal belongs to another attempted request.")
    return(brohn_store_batch(store,function() {
      brohn_cardiac_display_sources_current(store,sources);brohn_report_package_job_fence(store,job)
      .brohn_cm_guard_check(guards);error <- result;error$source_preserved <- TRUE
      brohn_fail_job(store,job$id,job$worker,job$token,error)
    }))
  }
  brohn_fields(result,c("schema","artifact","source","display_request","implementation","catalog","coverage","payloads",
    "verification","input_binding_hash"),label="Cardiac display publication")
  brohn_require(identical(result$schema,"brohn-cardiac-display-worker-result/0.1")&&
    identical(result$input_binding_hash,job$request$content_fingerprint)&&.brohn_cdd_equal(result$source,request$source)&&
    .brohn_cdd_equal(result$display_request,request$display_request)&&.brohn_cdd_equal(result$implementation,request$implementation),
    "The cardiac publication differs from its exact source and preparation intent.")
  a <- result$artifact
  brohn_fields(a,c("path","sha256","bytes","media_type"),label="Complete cardiac display artifact")
  brohn_require(identical(a$path,"cardiac-display.json")&&.brohn_rpk_hash(a$sha256)&&
    brohn_number(a$bytes,1,48*1024^2,TRUE)&&identical(a$media_type,"application/json"),"The cardiac evidence artifact descriptor is invalid.")
  payloads <- .brohn_cdd_payload_inventory(result)
  paths <- stats::setNames(vapply(payloads,function(p) {
    .brohn_rpk_source_pulse(pulse)
    path <- brohn_checked_artifact_path(store,file.path(scratch,"artifacts",p$path),scratch)
    hold(path,p$bytes)
  },character(1)),vapply(payloads,`[[`,character(1),"path"))
  e <- .brohn_cdd_one(payloads,function(p)identical(p$role,"prepared_display_evidence"),"The cardiac evidence payload is missing.")
  brohn_require(identical(e$path,a$path)&&identical(e$hash,a$sha256)&&e$bytes==a$bytes&&identical(e$media_type,a$media_type),
    "The cardiac evidence artifact differs from its complete payload inventory.")
  evidence <- brohn_eda_read_json_file(paths[[a$path]],48*1024^2)
  brohn_validate_cardiac_display_evidence(evidence,request,result,pulse)
  brohn_validate_cardiac_payload_contents(result,request,evidence,paths,pulse)
  brohn_validate_cardiac_verification(result,request,request_path,pulse)
  .brohn_cm_guard_check(guards);.brohn_rpk_source_pulse(pulse)
  specifications <- lapply(seq_along(payloads),function(i) {
    p <- payloads[[i]]
    list(key=paste0("cardiac-payload-",i),kind="cardiac-display-payload",path=paths[[i]],sha256=p$hash,bytes=p$bytes,media_type=p$media_type)
  })
  staged <- document <- NULL;committed <- FALSE
  on.exit({if(!is.null(document))brohn_close_publication(document$guard,committed);if(!is.null(staged))brohn_close_publication(staged$guard,committed)},add=TRUE)
  staged <- .brohn_publication_stage(store,job,specifications)
  for(i in seq_along(payloads))brohn_require(.brohn_cdd_equal(.brohn_td_object_ref(staged$descriptors[[i]]),payloads[[i]][c("hash","bytes","media_type")]),
    "Staging changed a complete cardiac payload descriptor.")
  id <- paste0("cardiac-display-",sub("^job[_-]","",job$id))
  body <- list(schema="brohn-saved-cardiac-display/0.1",study_id=job$request$study_id,project_id=job$request$project_id,
    source=result$source,display_request=result$display_request,preparation_profile=.brohn_cdd_profile,
    implementation=result$implementation,implementation_hash=brohn_hash(result$implementation),
    input_binding_hash=job$request$content_fingerprint,artifact=.brohn_td_object_ref(a),
    artifact_schema=evidence$schema,payloads=payloads,catalog=result$catalog,coverage=result$coverage,outcome=evidence$outcome,
    producer=list(job_id=job$id,attempt=job$attempt,request_hash=brohn_hash(job$request),
      worker_result_hash=digest::digest(file=output_path,algo="sha256")))
  brohn_require(nchar(brohn_json(body),type="bytes")<=2*1024^2,"The complete cardiac display catalogue exceeds its publication bound.")
  .brohn_rpk_source_pulse(pulse)
  document <- .brohn_publication_stage_json(store,job,body,file.path(scratch,"published-cardiac-display.json"))
  receipt <- brohn_store_batch(store,function() {
    brohn_cardiac_display_sources_current(store,sources);brohn_report_package_job_fence(store,job)
    .brohn_cm_guard_check(guards)
    .brohn_publication_register(store,staged)
    body$retained_document <- .brohn_td_object_ref(.brohn_publication_register(store,document)[[1L]])
    brohn_put_entity(store,"cardiac_display",id,body,0L,job$request$project_id)
    brohn_complete_job(store,job$id,job$worker,job$token,list(cardiac_display_id=id,report_id=job$request$report_ref$id,output_hash=body$retained_document$hash))
  })
  committed <- TRUE;receipt
}
