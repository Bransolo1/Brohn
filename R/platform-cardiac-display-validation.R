# Independent parent checks: exact scientific source, complete inventory and
# display identity. These checks do not run any cardiac scientific method.
.brohn_cdd_equal <- function(a,b)identical(brohn_eda_value_hash(a),brohn_eda_value_hash(b))
.brohn_cdd_object_valid <- function(x) {
  brohn_fields(x,c("hash","bytes","media_type","schema"),label="Cardiac evidence object")
  brohn_require(.brohn_rpk_hash(x$hash)&&brohn_number(x$bytes,0,192*1024^2,TRUE)&&
    brohn_text(x$media_type,100)&&brohn_text(x$schema,128),"The cardiac evidence object descriptor is invalid.")
  invisible(TRUE)
}
.brohn_cdd_count_fields <- c("samples","retained_samples","peaks","intervals","null_interval_rows",
  "plausible_intervals","implausible_intervals","spectrum_bins","features")
.brohn_cdd_counts <- function(x) {
  brohn_fields(x,.brohn_cdd_count_fields,label="Complete cardiac counts")
  brohn_require(all(vapply(x,function(n)brohn_number(n,0,1e6,TRUE),logical(1)))&&
    x$retained_samples<=x$samples&&x$intervals+x$null_interval_rows==x$peaks&&
    x$plausible_intervals+x$implausible_intervals==x$intervals,"Complete cardiac counts do not reconcile.")
  invisible(TRUE)
}
.brohn_cdd_evidence_binding <- function(request)brohn_eda_value_hash(list(source=request$source,
  display_request=request$display_request,implementation=request$implementation,
  source_closure_value_hash=brohn_eda_value_hash(request$source_closure)))
brohn_validate_cardiac_display_evidence <- function(evidence,request,result,pulse=NULL) {
  .brohn_rpk_source_pulse(pulse)
  brohn_fields(evidence,c("schema","source_ref","closure_hash","display_request","display_request_hash",
    "implementation_hash","input_binding_hash","source_analysis_object","complete_scientific_objects",
    "complete_lineage_objects","exclusion_lineage","outcome","cells","source_counts","projection_mode",
    "scientific_processing_performed"),label="Complete cardiac display evidence")
  report <- request$report;a <- report$complete_analysis
  brohn_require(identical(evidence$schema,"brohn-cardiac-display-evidence/0.1")&&
    .brohn_rpk_same(evidence$source_ref,report$ref)&&identical(evidence$closure_hash,request$source$source_closure_hash)&&
    .brohn_cdd_equal(evidence$display_request,request$display_request)&&
    identical(evidence$display_request_hash,brohn_eda_value_hash(request$display_request))&&
    identical(evidence$implementation_hash,brohn_eda_value_hash(request$implementation))&&
    identical(evidence$input_binding_hash,.brohn_cdd_evidence_binding(request))&&
    identical(evidence$projection_mode,"source_identifiers")&&identical(evidence$scientific_processing_performed,FALSE),
    "Cardiac evidence does not bind the complete original source and selected display request.")
  outcome <- evidence$outcome
  brohn_fields(outcome,c("source_status","original_reason","cell_count","exclusion_review_object","scientific_processing_performed"),label="Original cardiac outcome")
  brohn_require(identical(outcome$source_status,a$status)&&identical(outcome$original_reason,a$quality$reason)&&
    outcome$cell_count==length(a$recordings)&&identical(outcome$scientific_processing_performed,FALSE)&&
    identical(is.null(outcome$exclusion_review_object),is.null(a$exclusion_review)),"The cardiac source outcome was replaced or its exclusion context disappeared.")
  brohn_require(.brohn_cdd_equal(evidence$exclusion_lineage,request$lineage$exclusion$binding),"The original accepted cardiac review/preview binding changed.")
  for(x in c(list(evidence$source_analysis_object),evidence$complete_scientific_objects,evidence$complete_lineage_objects)) .brohn_cdd_object_valid(x)
  brohn_require(brohn_array(evidence$cells)&&length(evidence$cells)==length(a$recordings)&&length(evidence$cells)<=2000L&&
    brohn_array(result$catalog)&&length(result$catalog)==length(evidence$cells),"Cardiac evidence omitted or invented original cells.")
  totals <- stats::setNames(as.list(rep(0,length(.brohn_cdd_count_fields))),.brohn_cdd_count_fields)
  all_indices <- numeric();table_ids <- character();keys <- character()
  selector <- request$display_request$figure_cells
  for(i in seq_along(evidence$cells)) {
    .brohn_rpk_source_pulse(pulse)
    cell <- evidence$cells[[i]];original <- a$recordings[[i]];cat <- cell$catalogue
    brohn_fields(cell,c("catalogue","original_record","feature_indices","original_features","joined_markers_object",
      "waveform_views","interval_views","spectrum_view"),label="Original cardiac display cell")
    identity <- original[intersect(c("recording_id","segment_id","channel","group"),names(original))]
    key <- brohn_cardiac_source_cell_key(report$ref,i,identity);keys <- c(keys,key)
    brohn_require(.brohn_cdd_equal(cell$original_record,original)&&cat$source_record_index==i&&identical(cat$key,key)&&
      .brohn_cdd_equal(cat$identity,identity)&&identical(cat$source_record_value_hash,brohn_eda_value_hash(original))&&
      identical(cat$modality,a$kind)&&identical(cat$interval_basis,if(a$kind=="ecg")"detected_rr"else"detected_prv")&&
      identical(cat$source_status,original$status)&&identical(cat$original_reason,original$reason)&&
      identical(cat$unit,original$unit)&&identical(cat$scientifically_qualified,FALSE)&&identical(cat$normal_to_normal_confirmed,FALSE)&&
      identical(cat$all_marker_joins_checked,TRUE)&&.brohn_cdd_equal(cat,result$catalog[[i]]),
      "A cardiac cell changed its original identity, support, units or detection basis.")
    brohn_require(identical(cat$binding_hash,brohn_eda_value_hash(list(source_record=original,tables=cat$tables))),
      "A cardiac cell changed its complete table binding.")
    model <- cell;model$catalogue["model_hash"] <- list(NULL)
    brohn_require(identical(cat$model_hash,brohn_eda_value_hash(model)),"The cardiac display geometry changed after its model was bound.")
    indices <- cell$feature_indices
    brohn_require(brohn_array(indices)&&all(vapply(indices,function(n)brohn_number(n,0,length(a$features)-1,TRUE),logical(1)))&&
      !anyDuplicated(unlist(indices,use.names=FALSE))&&brohn_array(cell$original_features)&&length(indices)==length(cell$original_features),
      "Cardiac feature indices are absent, duplicated or outside the original report.")
    expected <- lapply(indices,function(j)a$features[[j+1L]])
    brohn_require(.brohn_cdd_equal(expected,cell$original_features),"A cardiac feature value, unit, null or support field changed.")
    for(f in expected)brohn_require(.brohn_cdd_equal(f[intersect(c("recording_id","segment_id","channel","group"),names(f))],identity),
      "A cardiac feature belongs to a different original recording.")
    all_indices <- c(all_indices,unlist(indices,use.names=FALSE))
    .brohn_cdd_counts(cat$counts)
    brohn_require(cat$counts$features==length(indices),"Cardiac feature coverage is incomplete.")
    brohn_fields(cat$tables,c("samples","peaks","spectrum"),label="Exact cardiac table domains")
    computed <- identical(original$status,"computed")
    availability <- function(status,reason=NULL)list(status=status,reason_code=reason,original_reason=reason)
    component <- if(computed)availability("available")else availability("unavailable",original$reason)
    detections <- if(!computed)component else if(cat$counts$peaks>0)availability("available")else availability("empty","no_saved_detections")
    intervals <- if(!computed)component else if(cat$counts$intervals>0)availability("available")else availability("empty","no_saved_intervals")
    spectrum <- if(!is.null(cat$tables$spectrum))availability("available")else
      availability("unavailable",brohn_default(original$interval_spectrum$unavailable_reason,original$reason))
    brohn_require(.brohn_cdd_equal(cat$components,list(raw=component,clean=component))&&
      .brohn_cdd_equal(cat$detections,detections)&&.brohn_cdd_equal(cat$intervals,intervals)&&
      .brohn_cdd_equal(cat$spectrum,spectrum)&&.brohn_cdd_equal(cat$source_sample_start,original$source_row_start)&&
      .brohn_cdd_equal(cat$source_sample_end_exclusive,original$source_row_end_exclusive)&&
      identical(cat$source_time_origin,original$source_time_origin)&&identical(cat$source_time_unit,a$source$time_unit),
      "Cardiac availability, source sample indices or time origin changed.")
    selected <- switch(selector$scope,first_chapter=i<=10,all_cells=TRUE,no_cells=FALSE,exact_cells=key %in% unlist(selector$keys,use.names=FALSE))
    brohn_require(identical(cat$figure_state,if(!computed)"unavailable"else if(selected)"illustrated"else"evidence_only"),
      "The cardiac figure selection omitted or added a recording.")
    if(computed) {
      brohn_require(!is.null(cat$tables$samples)&&!is.null(cat$tables$peaks)&&
        identical(!is.null(cat$tables$spectrum),identical(original$interval_spectrum$status,"available"))&&
        cat$counts$samples==original$samples&&cat$counts$retained_samples==original$retained_samples&&
        cat$counts$peaks==original$detected_peak_count&&cat$counts$implausible_intervals==original$implausible_interval_count,
        "Cardiac complete table/support counts differ from the saved detector result.")
      .brohn_cdd_object_valid(cell$joined_markers_object)
    }else brohn_require(all(vapply(cat$tables,is.null,logical(1)))&&is.null(cell$joined_markers_object)&&
      all(unlist(cat$counts[setdiff(names(cat$counts),"features")],use.names=FALSE)==0),"An unavailable cardiac source acquired invented scientific rows.")
    for(domain in names(cat$tables)) {
      t <- cat$tables[[domain]];if(is.null(t))next
      brohn_fields(t,c("artifact_hash","table_id","domain","rows","column_spec_hash","identity_hash","support_hash"),label="Cardiac source table reference")
      brohn_require(t$artifact_hash %in% vapply(a$artifacts,`[[`,character(1),"hash")&&identical(t$domain,domain)&&
        brohn_number(t$rows,0,1e6,TRUE)&&t$rows==cat$counts[[switch(domain,samples="samples",peaks="peaks",spectrum="spectrum_bins")]]&&
        all(vapply(t[c("artifact_hash","column_spec_hash","identity_hash","support_hash")],.brohn_rpk_hash,logical(1))),
        "A cardiac table reference changed its original domain, object or complete rows.")
      table_ids <- c(table_ids,paste(t$artifact_hash,t$table_id,sep=":"))
    }
    if(!computed||!selected)brohn_require(!length(cell$waveform_views)&&!length(cell$interval_views)&&is.null(cell$spectrum_view),
      "An evidence-only or unavailable cardiac cell acquired illustrated geometry.")
    for(name in names(totals))totals[[name]] <- totals[[name]]+cat$counts[[name]]
  }
  brohn_require(!anyDuplicated(keys)&&!anyDuplicated(table_ids)&&
    length(all_indices)==length(a$features)&&!anyDuplicated(all_indices)&&
    identical(sort(as.double(all_indices)),as.double(seq_along(a$features)-1L)),"Cardiac coverage omitted or duplicated original features or tables.")
  .brohn_cdd_counts(evidence$source_counts)
  brohn_require(.brohn_cdd_equal(totals,evidence$source_counts)&&
    totals$samples+totals$peaks+totals$spectrum_bins==sum(vapply(a$artifacts,`[[`,numeric(1),"rows"))&&
    length(table_ids)==sum(vapply(a$artifacts,`[[`,numeric(1),"tables")),"Complete cardiac coverage differs from the original artifact manifests.")
  states <- vapply(result$catalog,`[[`,character(1),"figure_state")
  coverage <- list(cells=length(a$recordings),illustrated_cells=sum(states=="illustrated"),evidence_only_cells=sum(states=="evidence_only"),
    unavailable_cells=sum(states=="unavailable"),features=length(a$features),original_stream_bytes=sum(vapply(a$artifacts,`[[`,numeric(1),"size")),
    original_rows=sum(vapply(a$artifacts,`[[`,numeric(1),"rows")),original_tables=sum(vapply(a$artifacts,`[[`,numeric(1),"tables")),
    marker_joins=totals$peaks,scientific_processing=FALSE)
  brohn_require(.brohn_cdd_equal(coverage,result$coverage),"The cardiac display coverage summary is incomplete.")
  .brohn_rpk_source_pulse(pulse);invisible(TRUE)
}

.brohn_cdd_payload_inventory <- function(result) {
  payloads <- result$payloads
  brohn_require(brohn_array(payloads)&&length(payloads)>0L&&length(payloads)<=1024L,"The complete cardiac payload inventory is missing or oversized.")
  roles <- c("complete_original_analysis","complete_original_lineage","complete_original_typed_stream","complete_table_csv",
    "complete_joined_markers","complete_exclusion_review","complete_original_curation_decisions","complete_curation_crosswalk",
    "selected_numerical_page_index","prepared_display_evidence")
  for(p in payloads) {
    brohn_fields(p,c("path","hash","bytes","media_type","schema","role"),label="Cardiac payload")
    .brohn_cdd_object_valid(p[c("hash","bytes","media_type","schema")])
    brohn_require(brohn_text(p$path,180)&&grepl("^[a-z0-9][a-z0-9-]*[.](json|ndjson|csv)$",p$path)&&p$role %in% roles,
      "A cardiac payload has an unsafe name or unregistered role.")
  }
  brohn_require(!anyDuplicated(vapply(payloads,`[[`,character(1),"path"))&&sum(vapply(payloads,`[[`,numeric(1),"bytes"))<=192*1024^2,
    "Cardiac payload names are duplicated or their complete bytes exceed the projection bound.")
  .brohn_cdd_one(payloads,function(p)identical(p$role,"prepared_display_evidence"),"The complete cardiac evidence document must be unique.")
  .brohn_cdd_one(payloads,function(p)identical(p$role,"complete_original_analysis"),"The complete original cardiac analysis must be unique.")
  .brohn_cdd_one(payloads,function(p)identical(p$role,"complete_original_lineage"),"The complete original cardiac lineage must be unique.")
  invisible(payloads)
}

brohn_validate_cardiac_payload_contents <- function(result,request,evidence,paths,pulse=NULL) {
  payloads <- .brohn_cdd_payload_inventory(result)
  brohn_require(identical(names(paths),vapply(payloads,`[[`,character(1),"path")),"Cardiac payload paths do not match their complete declared order.")
  role <- function(name).brohn_cdd_one(payloads,function(p)identical(p$role,name),paste("Missing unique cardiac payload",name))
  object <- function(p)p[c("hash","bytes","media_type","schema")]
  read_role <- function(name) {
    p <- role(name);.brohn_rpk_source_pulse(pulse)
    brohn_eda_read_json_file(paths[[p$path]],48*1024^2)
  }
  expected_roles <- list(complete_original_analysis=1,complete_original_lineage=1,
    complete_original_typed_stream=length(request$streams),complete_table_csv=result$coverage$original_tables,
    complete_joined_markers=sum(vapply(evidence$cells,function(c)c$catalogue$source_status=="computed",logical(1))),
    complete_exclusion_review=as.integer(!is.null(request$lineage$exclusion)),
    complete_original_curation_decisions=as.integer(!is.null(request$lineage$curation)),
    complete_curation_crosswalk=as.integer(!is.null(request$lineage$curation)),
    selected_numerical_page_index=1,prepared_display_evidence=1)
  for(name in names(expected_roles))brohn_require(sum(vapply(payloads,function(p)identical(p$role,name),logical(1)))==expected_roles[[name]],
    paste("Complete cardiac evidence has missing or unexpected",name,"companions."))
  schemas <- list(complete_original_analysis=request$report$complete_analysis$schema,
    complete_original_lineage="brohn-cardiac-complete-source-closure/0.1",complete_table_csv="brohn-cardiac-complete-table-csv/0.1",
    complete_joined_markers="brohn-cardiac-joined-markers/0.1",complete_exclusion_review=request$report$complete_analysis$exclusion_review$schema,
    complete_original_curation_decisions="brohn-stream-curation-decisions/1.0",complete_curation_crosswalk="brohn-cardiac-curation-crosswalk/0.1",
    selected_numerical_page_index="brohn-cardiac-numerical-pages/0.1",prepared_display_evidence="brohn-cardiac-display-evidence/0.1")
  for(p in payloads) {
    .brohn_rpk_source_pulse(pulse)
    if(p$role!="complete_original_typed_stream")brohn_require(identical(p$schema,schemas[[p$role]]),"A cardiac companion changed its declared schema.")
    brohn_require(file.exists(paths[[p$path]])&&file.info(paths[[p$path]])$size==p$bytes&&
      identical(digest::digest(file=paths[[p$path]],algo="sha256"),p$hash),"A complete cardiac payload changed or disappeared.")
  }
  brohn_require(.brohn_cdd_equal(read_role("complete_original_analysis"),request$report$complete_analysis)&&
    .brohn_cdd_equal(evidence$source_analysis_object,object(role("complete_original_analysis"))),"The exported cardiac analysis omits or changes scientific values.")
  lineage <- request$lineage
  if(!is.null(lineage$curation))for(k in c("decisions_object","derived_csv_object"))lineage$curation[[k]]$path <- NULL
  brohn_require(.brohn_cdd_equal(read_role("complete_original_lineage"),list(source_closure=request$source_closure,lineage=lineage)),
    "The exported cardiac source graph or complete original lineage changed.")
  scientific_roles <- c("complete_original_analysis","complete_original_typed_stream","complete_table_csv","complete_joined_markers")
  scientific <- lapply(Filter(function(p)p$role %in% scientific_roles,payloads),object)
  others <- lapply(Filter(function(p)!p$role %in% c(scientific_roles,"prepared_display_evidence"),payloads),object)
  same_set <- function(a,b)identical(sort(vapply(a,brohn_eda_value_hash,character(1))),sort(vapply(b,brohn_eda_value_hash,character(1))))
  brohn_require(same_set(scientific,evidence$complete_scientific_objects)&&same_set(others,evidence$complete_lineage_objects),
    "The cardiac evidence document dropped or invented an exported object.")
  original_streams <- Filter(function(p)identical(p$role,"complete_original_typed_stream"),payloads)
  brohn_require(length(original_streams)==length(request$streams),"The complete original cardiac stream membership changed.")
  for(i in seq_along(original_streams))brohn_require(original_streams[[i]]$hash==request$streams[[i]]$original$hash&&
    original_streams[[i]]$bytes==request$streams[[i]]$original$size&&identical(original_streams[[i]]$schema,request$streams[[i]]$original$schema),"An original typed cardiac stream was altered for export.")
  brohn_require(length(Filter(function(p)p$role=="complete_table_csv",payloads))==result$coverage$original_tables&&
    length(Filter(function(p)p$role=="complete_joined_markers",payloads))==sum(vapply(evidence$cells,function(c)c$catalogue$source_status=="computed",logical(1))),
    "Complete cardiac table or joined-marker companions are absent.")
  for(i in seq_along(evidence$cells)) {
    cell <- evidence$cells[[i]]
    if(is.null(cell$joined_markers_object))next
    marker <- .brohn_cdd_one(payloads,function(p)identical(p$role,"complete_joined_markers")&&
      identical(p$path,sprintf("cell-%04d-markers.ndjson",i)),"The exact cardiac cell's complete joined markers are missing.")
    brohn_require(.brohn_cdd_equal(cell$joined_markers_object,object(marker)),
      "The cardiac cell refers to another or absent joined-marker export.")
  }
  if(!is.null(request$lineage$exclusion))brohn_require(.brohn_cdd_equal(read_role("complete_exclusion_review"),request$report$complete_analysis$exclusion_review)&&
    .brohn_cdd_equal(evidence$outcome$exclusion_review_object,object(role("complete_exclusion_review"))),
    "The exported original exclusion ledger or its outcome reference changed.")
  if(!is.null(request$lineage$curation))brohn_require(identical(role("complete_original_curation_decisions")$hash,request$lineage$curation$decisions_object$hash),
    "The complete original curation decisions changed for export.")
  .brohn_rpk_source_pulse(pulse);invisible(TRUE)
}

.brohn_cdd_original_header <- function(path) {
  con <- file(path,"rb");on.exit(close(con),add=TRUE)
  raw <- readBin(con,"raw",n=2*1024^2+1)
  end <- match(as.raw(10),raw)
  brohn_require(!is.na(end)&&end<=2*1024^2,"The original cardiac stream header exceeds its bound.")
  text <- rawToChar(raw[seq_len(end-1L)]);Encoding(text) <- "UTF-8"
  brohn_parse(.brohn_edd_json_text(text),2*1024^2)
}
brohn_validate_cardiac_verification <- function(result,request,request_path,pulse=NULL) {
  v <- result$verification;a <- result$artifact
  brohn_fields(v,c("schema","request_sha256","analysis_value_hash","source_closure_value_hash","evidence_sha256",
    "evidence_bytes","original_streams","source_objects","runtime","complete","scientific_processing"),label="Cardiac worker verification")
  brohn_require(identical(v$schema,"brohn-cardiac-display-verification/0.1")&&
    identical(v$request_sha256,digest::digest(file=request_path,algo="sha256"))&&
    identical(v$analysis_value_hash,request$source$analysis_value_hash)&&
    identical(v$source_closure_value_hash,brohn_eda_value_hash(request$source_closure))&&
    identical(v$evidence_sha256,a$sha256)&&v$evidence_bytes==a$bytes&&
    .brohn_cdd_equal(v$runtime$Python,request$implementation$runtime$Python)&&
    identical(v$complete,TRUE)&&identical(v$scientific_processing,FALSE),"Cardiac verification changed its complete source, bytes or runtime binding.")
  expected <- lapply(request$sealed_objects,function(o)o[c("hash","bytes")])
  brohn_require(.brohn_cdd_equal(v$source_objects,expected)&&brohn_array(v$original_streams)&&length(v$original_streams)==length(request$streams),
    "The cardiac worker omitted or substituted an original held source object.")
  for(i in seq_along(request$streams)) {
    .brohn_rpk_source_pulse(pulse)
    stream <- request$streams[[i]];original <- stream$original
    header <- .brohn_cdd_original_header(stream$path)
    observed <- v$original_streams[[i]]
    brohn_fields(observed,c("schema","kind","rows","tables","provenance","verified"),label="Verified original cardiac stream")
    brohn_require(identical(observed$schema,original$schema)&&identical(observed$kind,original$kind)&&
      observed$rows==original$rows&&observed$tables==original$tables&&identical(observed$verified,TRUE)&&
      identical(header$provenance_sha256,original$provenance_sha256)&&.brohn_cdd_equal(observed$provenance,header$provenance),
      "The cardiac verification changed original stream counts or scientific provenance.")
  }
  invisible(TRUE)
}
