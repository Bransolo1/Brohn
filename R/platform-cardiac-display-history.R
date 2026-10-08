# Historical saved cardiac reads. No current-code gate, worker or mutation.
.brohn_cdh_implementation <- function(x) {
  brohn_fields(x,c("schema","profile","sources","runtime"),label="Saved cardiac implementation")
  brohn_require(identical(x$schema,"brohn-cardiac-display-implementation/0.1")&&
    identical(x$profile,"saved-cardiac-display/0.1")&&is.list(x$sources)&&length(x$sources)>0L&&
    length(x$sources)<=256L&&!is.null(names(x$sources))&&!anyDuplicated(names(x$sources))&&
    all(nzchar(names(x$sources)))&&all(vapply(x$sources,.brohn_rpk_hash,logical(1)))&&
    all(c("R/platform-cardiac-display-jobs.R","scripts/workers/cardiac_display.py") %in% names(x$sources))&&
    is.list(x$runtime)&&nchar(brohn_json(x),type="bytes")<=128*1024,
    "The original cardiac preparation implementation is malformed or unsupported.")
  invisible(TRUE)
}
.brohn_cdh_object <- function(store,x,maximum=192*1024^2) {
  brohn_require(is.list(x)&&.brohn_rpk_hash(x$hash)&&brohn_number(x$bytes,0,maximum,TRUE)&&
    brohn_text(x$media_type,128),"A saved cardiac object descriptor is missing or oversized.")
  path <- brohn_object_path(store,x$hash,FALSE)
  brohn_require(as.numeric(file.info(path)$size)==x$bytes,"A saved cardiac object changed its declared byte count.")
  list(hash=x$hash,bytes=as.numeric(x$bytes),media_type=x$media_type,path=path)
}

brohn_cardiac_display_metadata <- function(store,prepared_ref) {
  .brohn_rpk_ref_catalog(store,prepared_ref,"cardiac_display")
  bounded <- DBI::dbGetQuery(store$con,paste("SELECT length(CAST(body_json AS BLOB)) bytes FROM entity_versions",
    "WHERE kind='cardiac_display' AND id=? AND revision=? AND project_id=?"),
    params=list(prepared_ref$id,prepared_ref$revision,prepared_ref$project_id))
  brohn_require(nrow(bounded)==1L&&bounded$bytes[[1L]]<=2*1024^2,"Saved cardiac metadata exceeds its bounded reader.")
  record <- .brohn_rpk_record(store,prepared_ref,"cardiac_display");b <- record$body
  brohn_fields(b,c("schema","study_id","project_id","source","display_request","preparation_profile",
    "implementation","implementation_hash","input_binding_hash","artifact","artifact_schema","payloads",
    "catalog","coverage","outcome","producer","retained_document"),label="Saved cardiac display")
  brohn_require(identical(b$schema,"brohn-saved-cardiac-display/0.1")&&
    identical(b$artifact_schema,"brohn-cardiac-display-evidence/0.1")&&
    identical(b$preparation_profile,"saved-cardiac-display/0.1")&&identical(b$project_id,prepared_ref$project_id)&&
    identical(b$implementation_hash,brohn_hash(b$implementation))&&.brohn_rpk_hash(b$input_binding_hash)&&
    .brohn_rpk_same(b$display_request,brohn_normalize_cardiac_display_request(b$display_request)),
    "The saved cardiac display identity or display request is unsupported.")
  .brohn_cdh_implementation(b$implementation)
  brohn_fields(b$source,c("report_ref","analysis_hash","analysis_value_hash","dataset_ref","result_object",
    "original_stream_descriptors","source_closure_hash"),label="Original cardiac display source")
  .brohn_rpk_ref_valid(b$source$report_ref,"report");.brohn_rpk_ref_valid(b$source$dataset_ref,"dataset")
  brohn_require(identical(b$source$report_ref$project_id,prepared_ref$project_id)&&
    all(vapply(b$source[c("analysis_hash","analysis_value_hash","source_closure_hash")],.brohn_rpk_hash,logical(1))),
    "The saved cardiac source identity is malformed or belongs to another project.")
  source <- brohn_cardiac_source_metadata(store,b$source$report_ref);selected <- source$selected
  brohn_require(identical(b$study_id,selected$study_id)&&
    identical(b$source$source_closure_hash,source$closure_hash)&&
    .brohn_rpk_same(b$source$dataset_ref,selected$dataset_ref)&&
    .brohn_rpk_same(b$source$result_object,.brohn_cdd_object(selected$result_object,"brohn-analysis-output/1.0"))&&
    .brohn_rpk_same(b$source$original_stream_descriptors,selected$artifacts),
    "The saved cardiac display lost its exact authorized original source closure.")
  brohn_require(brohn_array(b$catalog)&&length(b$catalog)==selected$record_count&&length(b$catalog)<=2000L,
    "The saved cardiac catalogue omitted or invented an original record.")
  keys <- character()
  for(i in seq_along(b$catalog)) {
    c <- b$catalog[[i]]
    brohn_require(identical(c$kind,"cardiac_cell")&&.brohn_rpk_hash(c$key)&&.brohn_rpk_hash(c$model_hash)&&
      c$source_record_index==i&&c$source_status %in% c("computed","unavailable")&&
      c$figure_state %in% c("illustrated","evidence_only","unavailable")&&identical(c$modality,selected$kind),
      "A saved cardiac catalogue cell has an unsupported identity or state.")
    .brohn_cdd_counts(c$counts);keys <- c(keys,c$key)
  }
  brohn_require(!anyDuplicated(keys),"The saved cardiac catalogue repeats an original cell.")
  brohn_fields(b$outcome,c("source_status","original_reason","cell_count","exclusion_review_object","scientific_processing_performed"),label="Saved cardiac outcome")
  brohn_require(identical(b$outcome$source_status,selected$status)&&identical(b$outcome$original_reason,selected$quality$reason)&&
    b$outcome$cell_count==length(b$catalog)&&identical(b$outcome$scientific_processing_performed,FALSE),
    "The saved cardiac outcome differs from its original source.")
  brohn_fields(b$coverage,c("cells","illustrated_cells","evidence_only_cells","unavailable_cells","features",
    "original_stream_bytes","original_rows","original_tables","marker_joins","scientific_processing"),label="Saved cardiac coverage")
  brohn_require(all(vapply(b$coverage[setdiff(names(b$coverage),"scientific_processing")],brohn_number,logical(1),min=0,max=192*1024^2,integer=TRUE))&&
    b$coverage$cells==length(b$catalog)&&b$coverage$features==selected$feature_count&&
    identical(b$coverage$scientific_processing,FALSE),"The saved cardiac coverage is malformed or incomplete.")
  .brohn_cdd_payload_inventory(b)
  brohn_fields(b$artifact,c("hash","bytes","media_type"),label="Saved cardiac artifact")
  brohn_fields(b$retained_document,c("hash","bytes","media_type"),label="Retained cardiac document")
  artifact <- .brohn_cdh_object(store,b$artifact,48*1024^2)
  document <- .brohn_cdh_object(store,b$retained_document,2*1024^2)
  brohn_require(artifact$bytes>0&&document$bytes>0&&identical(artifact$media_type,"application/json")&&
    identical(document$media_type,"application/json"),"Saved cardiac evidence and document must be nonempty JSON objects.")
  payloads <- stats::setNames(lapply(b$payloads,function(p)c(p,list(object_path=.brohn_cdh_object(store,p)$path))),
    vapply(b$payloads,`[[`,character(1),"path"))
  e <- .brohn_cdd_one(b$payloads,function(p)identical(p$role,"prepared_display_evidence"),"The saved cardiac evidence must be unique.")
  brohn_require(identical(e$path,"cardiac-display.json")&&identical(e$schema,b$artifact_schema)&&
    .brohn_rpk_same(e[c("hash","bytes","media_type")],b$artifact),"The saved cardiac artifact and complete payload inventory differ.")
  objects <- list()
  for(o in c(list(document,artifact),lapply(payloads,function(p)list(hash=p$hash,bytes=p$bytes,media_type=p$media_type,path=p$object_path)))) {
    old <- objects[[o$hash]]
    brohn_require(is.null(old)||.brohn_rpk_same(old,o),"The same saved cardiac object has conflicting descriptors.")
    objects[[o$hash]] <- o
  }
  p <- b$producer
  brohn_fields(p,c("job_id","attempt","request_hash","worker_result_hash"),label="Original cardiac display producer")
  brohn_require(brohn_valid_id(p$job_id)&&brohn_number(p$attempt,1,1e9,TRUE)&&
    .brohn_rpk_hash(p$request_hash)&&.brohn_rpk_hash(p$worker_result_hash),"The original successful cardiac display receipt is missing.")
  size <- DBI::dbGetQuery(store$con,"SELECT length(CAST(request_json AS BLOB))+coalesce(length(CAST(result_json AS BLOB)),0) bytes FROM jobs WHERE id=?",params=list(p$job_id))
  brohn_require(nrow(size)==1L&&size$bytes[[1L]]<=6*1024^2,"The original cardiac display producer is missing or oversized.")
  job <- brohn_get_job(store,p$job_id);r <- job$request
  brohn_fields(r,c("schema","project_id","study_id","report_ref","display_request","original_closure",
    "source_closure_hash","preparation_profile","implementation","authority","content_fingerprint"),label="Original cardiac display request")
  brohn_require(identical(job$operation,"cardiac_display")&&identical(job$status,"succeeded")&&job$attempt==p$attempt&&
    identical(job$result$cardiac_display_id,prepared_ref$id)&&identical(job$result$report_id,b$source$report_ref$id)&&
    identical(job$result$output_hash,document$hash)&&identical(brohn_hash(r),p$request_hash)&&
    identical(r$schema,"brohn-cardiac-display-job/0.1")&&identical(r$project_id,b$project_id)&&identical(r$study_id,b$study_id)&&
    identical(r$preparation_profile,b$preparation_profile)&&.brohn_rpk_same(r$report_ref,b$source$report_ref)&&
    .brohn_rpk_same(r$display_request,b$display_request)&&.brohn_rpk_same(r$implementation,b$implementation)&&
    identical(r$source_closure_hash,source$closure_hash)&&.brohn_rpk_same(r$original_closure,source$closure)&&
    identical(r$content_fingerprint,b$input_binding_hash)&&
    identical(r$content_fingerprint,brohn_hash(r[setdiff(names(r),c("authority","content_fingerprint"))])),
    "The saved cardiac display differs from its exact original successful job, request or result.")
  # Validate retained authority identity, not its expired producer session.
  a <- r$authority
  brohn_fields(a,c("schema","mode","workspace_id","project_id","operation","profile_id","context"),label="Original cardiac producer authority")
  brohn_require(identical(a$schema,"brohn-report-package-authority/0.1")&&a$mode %in% c("local","hosted")&&
    identical(a$workspace_id,store$workspace_id)&&identical(a$project_id,b$project_id)&&identical(a$operation,"cardiac_display"),
    "The saved cardiac producer authority identifies another workspace or operation.")
  .brohn_rpk_ref_catalog(store,prepared_ref,"cardiac_display")
  list(ref=prepared_ref,record=record,report_ref=b$source$report_ref,source_metadata=source,
    producer=list(id=job$id,operation=job$operation,status=job$status,attempt=job$attempt,request=r,result=job$result),
    artifact=artifact,document=document,payloads=payloads,objects=unname(objects[order(names(objects),method="radix")]))
}

brohn_find_cardiac_display <- function(store,report_ref,display_request=NULL,implementation_ref=NULL) {
  # Discovery may choose a saved preparation; exact reads never replace it later.
  brohn_cardiac_source_metadata(store,report_ref)
  request <- brohn_normalize_cardiac_display_request(display_request)
  condition <- "";params <- list(report_ref$project_id,report_ref$id,report_ref$revision,
    report_ref$body_hash,"saved-cardiac-display/0.1",brohn_json(request))
  if(!is.null(implementation_ref)) {
    brohn_fields(implementation_ref,c("profile","hash"),label="Expected saved cardiac implementation")
    brohn_require(identical(implementation_ref$profile,"saved-cardiac-display/0.1")&&.brohn_rpk_hash(implementation_ref$hash),
      "Choose an exact supported cardiac preparation implementation.")
    condition <- "AND json_extract(v.body_json,'$.implementation_hash')=?"
    params <- c(params,list(implementation_ref$hash))
  }
  rows <- DBI::dbGetQuery(store$con,paste(
    "SELECT v.id,v.revision,v.body_hash FROM entities e JOIN entity_versions v ON e.kind=v.kind AND e.id=v.id AND e.revision=v.revision",
    "WHERE e.kind='cardiac_display' AND e.project_id=? AND json_extract(v.body_json,'$.source.report_ref.id')=?",
    "AND json_extract(v.body_json,'$.source.report_ref.revision')=? AND json_extract(v.body_json,'$.source.report_ref.body_hash')=?",
    "AND json_extract(v.body_json,'$.preparation_profile')=? AND json_extract(v.body_json,'$.display_request')=json(?)",
    condition,"ORDER BY e.updated_at DESC,e.id DESC LIMIT 1"),params=params)
  if(!nrow(rows))return(NULL)
  ref <- list(kind="cardiac_display",id=rows$id[[1L]],revision=rows$revision[[1L]],body_hash=rows$body_hash[[1L]],project_id=report_ref$project_id)
  brohn_cardiac_display_metadata(store,ref);ref
}

brohn_cardiac_display_catalog <- function(store,prepared_ref,cursor=NULL,limit=25L) {
  meta <- brohn_cardiac_display_metadata(store,prepared_ref);b <- meta$record$body
  brohn_require(brohn_number(limit,1,100,TRUE),"Choose between 1 and 100 saved cardiac catalogue cells.")
  scope <- brohn_hash(list(prepared_ref=prepared_ref,closure_hash=meta$source_metadata$closure_hash));offset <- 0L
  if(!is.null(cursor)) {
    brohn_fields(cursor,c("scope","offset"),label="Saved cardiac catalogue page")
    brohn_require(identical(cursor$scope,scope)&&brohn_number(cursor$offset,0,length(b$catalog),TRUE),
      "Reopen this exact authorized cardiac preparation page.");offset <- cursor$offset
  }
  items <- if(offset>=length(b$catalog))list()else b$catalog[seq.int(offset+1L,min(length(b$catalog),offset+limit))]
  list(schema="brohn-cardiac-display-catalog/0.1",report_ref=meta$report_ref,prepared_ref=prepared_ref,state="ready",
    total=length(b$catalog),items=items,cursor=cursor,
    next_cursor=if(offset+length(items)<length(b$catalog))list(scope=scope,offset=offset+length(items))else NULL,
    display_request=b$display_request,display_request_hash=brohn_hash(b$display_request),
    outcome=b$outcome,coverage=b$coverage,requires_display_preparation=FALSE)
}

brohn_release_cardiac_display_resources <- function(handle) {
  if(is.environment(handle)&&inherits(handle,"brohn_cardiac_display_resources")&&is.environment(handle$state)&&!isTRUE(handle$state$closed)) {
    state <- handle$state;state$closed <- TRUE
    on.exit(brohn_release_cardiac_display_sources(handle$source_handle),add=TRUE)
    for(g in handle$guards)tryCatch(.brohn_qexplorer_release(g),error=function(e)NULL)
  }
  invisible(NULL)
}
brohn_open_cardiac_display_resources <- function(store,prepared_ref,project_id=prepared_ref$project_id,pulse=NULL) {
  brohn_require(identical(prepared_ref$project_id,project_id),"Choose the exact saved cardiac display project.")
  .brohn_rpk_source_pulse(pulse);meta <- brohn_cardiac_display_metadata(store,prepared_ref)
  sources <- NULL;guards <- list();ok <- FALSE
  on.exit(if(!ok){for(g in guards)tryCatch(.brohn_qexplorer_release(g),error=function(e)NULL);brohn_release_cardiac_display_sources(sources)},add=TRUE)
  sources <- brohn_open_cardiac_display_sources(store,meta$report_ref,meta$source_metadata$closure_hash,pulse)
  guards <- brohn_hold_signal_value_sources(store,list(source_objects=lapply(meta$objects,function(o)o[c("hash","bytes")])))
  for(o in meta$objects){.brohn_rpk_source_pulse(pulse);brohn_object_path(store,o$hash,TRUE)}
  b <- meta$record$body
  retained <- brohn_eda_read_json_file(meta$document$path,2*1024^2)
  brohn_require(.brohn_cdd_equal(retained,b[setdiff(names(b),"retained_document")]),
    "The saved cardiac catalogue differs from its exact retained publication document.")
  request <- .brohn_cdd_worker_request(sources,b$display_request,b$implementation,pulse)
  brohn_require(.brohn_cdd_equal(request$source,b$source)&&.brohn_cdd_equal(request$source_closure,meta$producer$request$original_closure),
    "The historical cardiac request lost its complete original scientific source.")
  evidence <- brohn_eda_read_json_file(meta$artifact$path,48*1024^2)
  paths <- stats::setNames(vapply(meta$payloads,`[[`,character(1),"object_path"),names(meta$payloads))
  brohn_validate_cardiac_display_evidence(evidence,request,b,pulse)
  brohn_validate_cardiac_payload_contents(b,request,evidence,paths,pulse)
  brohn_cardiac_display_sources_current(store,sources);.brohn_cm_guard_check(guards)
  brohn_require(.brohn_rpk_same(brohn_cardiac_display_metadata(store,prepared_ref),meta),
    "Current cardiac authority, producer proof or prepared evidence changed while opening.")
  h <- new.env(parent=emptyenv());class(h) <- "brohn_cardiac_display_resources"
  h$state <- new.env(parent=emptyenv());h$state$closed <- FALSE;h$ref <- prepared_ref
  h$metadata <- meta;h$source_handle <- sources;h$guards <- guards;h$workspace_id <- store$workspace_id
  lockEnvironment(h,bindings=TRUE);reg.finalizer(h,brohn_release_cardiac_display_resources,onexit=TRUE);ok <- TRUE
  list(record=meta$record,handle=h,evidence=evidence,analysis=request$report$complete_analysis,
    source_reports=sources$reports,source_metadata=meta$source_metadata,artifact=meta$artifact,payloads=meta$payloads)
}
brohn_cardiac_display_resources_current <- function(store,handle) {
  brohn_require(is.environment(handle)&&inherits(handle,"brohn_cardiac_display_resources")&&environmentIsLocked(handle)&&
    !isTRUE(handle$state$closed)&&identical(handle$workspace_id,store$workspace_id),
    "Reopen this closed or different-workspace saved cardiac display.")
  .brohn_cm_guard_check(handle$guards);brohn_cardiac_display_sources_current(store,handle$source_handle)
  meta <- brohn_cardiac_display_metadata(store,handle$ref)
  brohn_require(.brohn_rpk_same(meta,handle$metadata),"Current saved cardiac permission, owner, original producer or exact payload binding changed.")
  .brohn_cm_guard_check(handle$guards)
  list(record=meta$record,source_metadata=meta$source_metadata,artifact=meta$artifact,payloads=meta$payloads)
}
