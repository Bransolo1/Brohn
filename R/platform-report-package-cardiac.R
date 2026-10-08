# Pure, separately registered cardiac report-package adapter. No stores/jobs/science.
.brohn_rpca_renderer <- "controlled-gaze-explicit-task-choice-eda-cardiac-paired/0.1"
.brohn_rpca_admission <- "task-choice-eda-cardiac-findings/0.1"
.brohn_rpca_same <- function(a,b)identical(brohn_eda_value_hash(a),brohn_eda_value_hash(b))
.brohn_rpca_ref <- function(x,kind="report") .brohn_rpk_ref_valid(x,kind)
.brohn_rpca_one <- function(xs,predicate,label){hits<-Filter(predicate,xs);brohn_require(length(hits)==1L,label);hits[[1L]]}
.brohn_rpca_key <- function(ref)brohn_eda_value_hash(ref)
.brohn_rpca_object <- function(x)x[c("hash","bytes","media_type","schema")]
brohn_report_package_cardiac_profile <- function(selection)isTRUE(.brohn_rpk_profile_spec(selection$renderer_profile,FALSE)$cardiac)

brohn_report_package_cardiac_requirements <- function(metadata,selected_refs,study_id,project_id,source_admission=.brohn_rpca_admission) {
  brohn_require(isTRUE(.brohn_rpk_admission_spec(source_admission)$cardiac),"Choose an exact registered cardiac complete-source admission.")
  brohn_require(brohn_valid_id(study_id)&&brohn_valid_id(project_id)&&brohn_array(metadata)&&brohn_array(selected_refs)&&
    length(metadata)==length(selected_refs)&&length(metadata)<=8L,"Choose bounded exact cardiac sources in their original study and project.")
  keys<-vapply(selected_refs,.brohn_rpca_key,character(1));brohn_require(!anyDuplicated(keys),"Select each exact cardiac source once.")
  ordered<-list();all<-list();bindings<-list();required_by<-list()
  for(i in seq_along(metadata)) {
    m<-metadata[[i]];ref<-selected_refs[[i]];.brohn_rpca_ref(ref)
    brohn_require(identical(m$schema,"brohn-cardiac-source-metadata/0.1")&&identical(m$profile,"cardiac-saved-findings/0.1")&&
      .brohn_rpca_same(m$report_ref,ref)&&.brohn_rpca_same(m$selected$ref,ref)&&identical(ref$project_id,project_id)&&
      identical(m$closure_hash,brohn_eda_value_hash(m$closure))&&.brohn_rpca_same(m$closure$root_ref,ref),"A cardiac source closure changed its exact selected identity.")
    brohn_require(brohn_array(m$reports)&&length(m$reports)>0L&&length(m$reports)<=32L,"The complete cardiac report closure is absent or oversized.")
    report_keys<-vapply(m$reports,function(x).brohn_rpca_key(x$ref),character(1))
    brohn_require(!anyDuplicated(report_keys)&&keys[[i]] %in% report_keys,"The cardiac closure omits or repeats an exact report.")
    for(report in m$reports) {
      .brohn_rpca_ref(report$ref);key<-.brohn_rpca_key(report$ref)
      brohn_require(identical(report$ref$project_id,project_id)&&identical(report$study_id,study_id)&&report$kind %in% c("ecg","ppg")&&
        brohn_number(report$record_count,0,2000,TRUE),"Every cardiac source and required parent must retain this actual study, project and admitted modality.")
      prior<-all[[key]]
      value<-list(report_ref=report$ref,study_id=report$study_id,kind=report$kind,record_count=report$record_count)
      brohn_require(is.null(prior)||.brohn_rpca_same(prior,value),"The same exact cardiac source has conflicting retained metadata.")
      if(is.null(prior))ordered[[length(ordered)+1L]]<-report$ref
      all[[key]]<-value;required_by[[key]]<-c(required_by[[key]],list(ref))
    }
    bindings[[i]]<-list(report_ref=ref,closure_hash=m$closure_hash,closure=m$closure)
  }
  related<-Filter(function(ref)! .brohn_rpca_key(ref) %in% keys,ordered)
  # Required-only reports have deterministic exact-ref order, not names/labels.
  if(length(related))related<-related[order(vapply(related,.brohn_rpca_key,character(1)),method="radix")]
  refs<-c(selected_refs,related)
  brohn_require(length(refs)<=32L&&sum(vapply(all,`[[`,numeric(1),"record_count"))<=2000L,"The complete selected/parent cardiac report closure exceeds the package bound.")
  sources<-lapply(seq_along(refs),function(i){ref<-refs[[i]];key<-.brohn_rpca_key(ref);c(all[[key]],list(source_ordinal=i,selected=key %in% keys,required_by=required_by[[key]]))})
  value<-list(schema="brohn-report-package-cardiac-requirements/0.1",source_admission=source_admission,
    study_id=study_id,project_id=project_id,selected_refs=selected_refs,related_refs=related,sources=sources,closure_bindings=bindings)
  value$requirements_hash<-brohn_eda_value_hash(value);value
}

brohn_report_package_cardiac_dependencies <- function(requirements,resolved_chapters,implementation_ref) {
  r<-requirements;without<-r;without$requirements_hash<-NULL
  brohn_require(identical(r$schema,"brohn-report-package-cardiac-requirements/0.1")&&
    identical(r$requirements_hash,brohn_eda_value_hash(without)),"The frozen cardiac requirements changed.")
  brohn_fields(implementation_ref,c("profile","hash"),label="Pinned cardiac implementation")
  brohn_require(identical(implementation_ref$profile,"saved-cardiac-display/0.1")&&.brohn_rpk_hash(implementation_ref$hash),"Pin an exact cardiac display implementation.")
  x<-resolved_chapters
  brohn_require(identical(x$schema,"brohn-cardiac-resolved-chapters/0.1")&&brohn_array(x$reports)&&
    .brohn_rpca_same(lapply(x$reports,`[[`,"report_ref"),r$selected_refs)&&
    .brohn_rpca_same(lapply(x$plan$sources,`[[`,"report_ref"),r$selected_refs),"Global chapters must resolve once over the frozen ordered selected cardiac reports.")
  planning_sources<-lapply(r$selected_refs,function(ref){source<-.brohn_rpca_one(r$sources,function(z).brohn_rpca_same(z$report_ref,ref),"A selected cardiac source is missing.")
    binding<-.brohn_rpca_one(r$closure_bindings,function(z).brohn_rpca_same(z$report_ref,ref),"A selected cardiac closure is missing.")
    list(report_ref=ref,closure_hash=binding$closure_hash,record_count=source$record_count)})
  brohn_require(.brohn_rpca_same(x$plan,brohn_cardiac_chapter_plan(planning_sources,x$plan$request)),"Global cardiac chapter membership differs from the complete selected source order.")
  lapply(r$sources,function(source) {
    ref<-source$report_ref
    if(source$selected) {
      v<-.brohn_rpca_one(x$reports,function(z).brohn_rpca_same(z$report_ref,ref),"A selected cardiac source has no exact chapter request.")
      binding<-.brohn_rpca_one(r$closure_bindings,function(z).brohn_rpca_same(z$report_ref,ref),"The selected cardiac closure is missing.")
      brohn_require(identical(v$closure_hash,binding$closure_hash),"The original cardiac closure changed during chapter resolution.")
      request<-brohn_normalize_cardiac_display_request(v$display_request)
      planned<-.brohn_rpca_one(x$plan$sources,function(z).brohn_rpca_same(z$report_ref,ref),"A selected cardiac source is missing from its chapter plan.")
      brohn_require(identical(as.double(unlist(planned$selected_record_indices,use.names=FALSE)),vapply(v$selected_cells,function(z)as.double(z$source_record_index),numeric(1))),"Resolved cardiac cells differ from the exact original-record chapter membership.")
      brohn_require(request$figure_cells$scope %in% c("exact_cells","no_cells")&&
        identical(sort(as.character(unlist(request$figure_cells$keys,use.names=FALSE))),sort(vapply(v$selected_cells,function(z)z$key,character(1)))),"Chapter keys do not match the exact resolved original cells.")
    }else{request<-brohn_normalize_cardiac_display_request();request$figure_cells<-list(scope="no_cells",keys=list())}
    identity<-list(kind="cardiac_display",report_ref=ref,display_request=request)
    c(identity,list(implementation_ref=implementation_ref,required_only=!source$selected,
      source_ordinal=source$source_ordinal,slot=brohn_hash(identity)))
  })
}

brohn_report_package_cardiac_entry <- function(resources) {
  required<-c("record","evidence","analysis","payloads","source_reports","source_metadata")
  brohn_require(is.list(resources)&&all(required %in% names(resources)),"Open the complete exact saved cardiac resources before packaging.")
  r<-resources$record
  entry<-list(schema="brohn-report-package-cardiac-entry/0.1",ref=.brohn_rpk_ref(r),body=r$body,
    evidence=resources$evidence,analysis=resources$analysis,payloads=resources$payloads,
    source_reports=resources$source_reports,source_metadata=resources$source_metadata)
  brohn_report_package_cardiac_entry_validate(entry);entry
}

brohn_report_package_cardiac_entry_validate <- function(entry) .brohn_rpca_entry_core(entry,.brohn_rpca_same)
.brohn_rpca_entry_core <- function(entry,same) {
  brohn_fields(entry,c("schema","ref","body","evidence","analysis","payloads","source_reports","source_metadata"),label="Complete saved cardiac package source")
  .brohn_rpca_ref(entry$ref,"cardiac_display");b<-entry$body;e<-entry$evidence;a<-entry$analysis;m<-entry$source_metadata
  analysis_value_hash<-brohn_eda_value_hash(a);closure_value_hash<-brohn_eda_value_hash(m$closure)
  brohn_require(identical(entry$schema,"brohn-report-package-cardiac-entry/0.1")&&identical(entry$ref$body_hash,brohn_hash(b))&&
    identical(b$schema,"brohn-saved-cardiac-display/0.1")&&identical(b$preparation_profile,"saved-cardiac-display/0.1")&&
    identical(e$schema,"brohn-cardiac-display-evidence/0.1")&&a$kind %in% c("ecg","ppg")&&
    same(b$source$report_ref,e$source_ref)&&same(e$source_ref,m$report_ref)&&
    identical(b$source$analysis_value_hash,analysis_value_hash)&&identical(e$closure_hash,m$closure_hash)&&identical(m$closure_hash,closure_value_hash)&&
    identical(e$closure_hash,b$source$source_closure_hash)&&same(b$display_request,e$display_request)&&
    identical(e$display_request_hash,brohn_eda_value_hash(b$display_request))&&
    identical(e$implementation_hash,brohn_eda_value_hash(b$implementation))&&identical(b$implementation_hash,brohn_hash(b$implementation))&&
    identical(e$input_binding_hash,brohn_eda_value_hash(list(source=b$source,display_request=b$display_request,implementation=b$implementation,source_closure_value_hash=closure_value_hash)))&&
    same(b$catalog,lapply(e$cells,`[[`,"catalogue"))&&same(b$outcome,e$outcome)&&
    identical(entry$ref$project_id,b$project_id)&&identical(b$study_id,m$selected$study_id)&&brohn_valid_id(b$study_id),
    "The saved cardiac entry differs from its original prepared/source values or genuine study binding.")
  selected<-.brohn_rpca_one(entry$source_reports,function(x)same(x$ref,e$source_ref),"The complete exact selected cardiac report is missing.")
  brohn_require(same(selected$complete_analysis,a)&&same(.brohn_td_object_ref(selected$saved_body$result_object),b$source$result_object[c("hash","bytes","media_type")]),"The selected original report changed.")
  expected_refs<-lapply(m$reports,`[[`,"ref")
  brohn_require(setequal(vapply(entry$source_reports,function(x).brohn_rpca_key(x$ref),character(1)),vapply(expected_refs,.brohn_rpca_key,character(1)))&&
    !anyDuplicated(vapply(entry$source_reports,function(x).brohn_rpca_key(x$ref),character(1))),"The complete cardiac parent report inventory changed.")
  brohn_require(is.list(entry$payloads)&&!is.null(names(entry$payloads))&&!anyDuplicated(names(entry$payloads))&&
    setequal(names(entry$payloads),vapply(b$payloads,`[[`,character(1),"path")),"The held cardiac payload inventory changed.")
  roles<-vapply(b$payloads,`[[`,character(1),"role");objects<-list()
  for(p in b$payloads) {
    brohn_fields(p,c("path","hash","bytes","media_type","schema","role"),label="Saved cardiac payload")
    brohn_require(grepl("^[a-z0-9][a-z0-9-]*[.](json|ndjson|csv)$",p$path)&&.brohn_rpk_hash(p$hash)&&brohn_number(p$bytes,0,192*1024^2,TRUE),"The saved cardiac payload path or descriptor is invalid.")
    held<-entry$payloads[[p$path]]
    brohn_require(same(held[names(p)],p)&&brohn_text(held$object_path,4096),"A cardiac payload lost its held exact object.")
    objects[[p$path]]<-.brohn_rpca_object(p)
  }
  role<-function(name).brohn_rpca_one(b$payloads,function(p)identical(p$role,name),paste("Missing unique cardiac payload",name))
  context<-.brohn_rpca_one(m$contexts,function(x)same(x$report_ref,e$source_ref),"The exact cardiac context is absent.")
  curated<-!is.null(context$lineage$binding$curation_ref)
  expect<-c(complete_original_analysis=1,complete_original_lineage=1,selected_numerical_page_index=1,prepared_display_evidence=1,
    complete_original_typed_stream=length(a$artifacts),complete_table_csv=sum(vapply(a$artifacts,`[[`,numeric(1),"tables")),
    complete_joined_markers=sum(vapply(e$cells,function(x)identical(x$catalogue$source_status,"computed"),logical(1))),
    complete_exclusion_review=as.integer(!is.null(a$exclusion_review)),
    complete_original_curation_decisions=as.integer(curated),complete_curation_crosswalk=as.integer(curated))
  brohn_require(all(roles %in% names(expect))&&all(vapply(names(expect),function(k)sum(roles==k)==expect[[k]],logical(1))),"The complete cardiac payload roles are missing, duplicated or unexpected.")
  descriptor<-role("prepared_display_evidence")
  brohn_require(identical(descriptor$path,"cardiac-display.json")&&identical(descriptor$hash,b$artifact$hash)&&descriptor$bytes==b$artifact$bytes&&
    same(e$source_analysis_object,.brohn_rpca_object(role("complete_original_analysis"))),"The cardiac evidence or analysis export reference changed.")
  if(!is.null(a$exclusion_review))brohn_require(same(e$outcome$exclusion_review_object,.brohn_rpca_object(role("complete_exclusion_review"))),"The cardiac outcome refers to another exclusion ledger.")
  indices<-numeric()
  for(i in seq_along(e$cells)) {
    cell<-e$cells[[i]]
    brohn_require(same(cell$original_record,a$recordings[[i]])&&cell$catalogue$source_record_index==i&&
      length(cell$feature_indices)==length(cell$original_features),"A cardiac cell changed its original record or feature membership.")
    for(j in seq_along(cell$feature_indices)) {
      k<-cell$feature_indices[[j]];brohn_require(brohn_number(k,0,length(a$features)-1,TRUE)&&same(cell$original_features[[j]],a$features[[k+1]]),"A cardiac feature changed an original value, optional field, null or support field.")
      indices<-c(indices,k)
    }
    if(!is.null(cell$joined_markers_object))brohn_require(same(cell$joined_markers_object,objects[[sprintf("cell-%04d-markers.ndjson",i)]]),"The cardiac cell refers to another joined-marker payload.")
  }
  brohn_require(length(e$cells)==length(a$recordings)&&length(indices)==length(a$features)&&!anyDuplicated(indices)&&
    identical(sort(as.double(indices)),as.double(seq_along(a$features)-1L)),"The package omitted or duplicated original cardiac features/cells.")
  invisible(TRUE)
}

.brohn_rpca_measure_label <- function(name) {
  key<-sub("^detected_(rr|prv)_","",name)
  labels<-c(detected_peak_count="Detected peaks",interval_count="Saved intervals",retained_interval_count="Retained intervals",
    successive_pair_count="Successive pairs",mean_interval="Mean interval",sd_interval="Interval sample SD",rmssd="RMSSD",
    pnn50_candidate="pNN50 candidate",rate_from_mean_interval="Rate from mean interval",mean_interval_rate="Mean interval rate",
    lf_power_candidate="LF power candidate",hf_power_candidate="HF power candidate",lf_hf_ratio_candidate="LF/HF ratio candidate")
  if(key %in% names(labels))unname(labels[[key]])else gsub("_"," ",name,fixed=TRUE)
}
brohn_report_package_cardiac_overview <- function(entry,chapter_resolution=NULL) {
  brohn_report_package_cardiac_entry_validate(entry)
  .brohn_rpca_overview_core(entry,chapter_resolution)
}
.brohn_rpca_overview_core <- function(entry,chapter_resolution=NULL) {
  e<-entry$evidence;a<-entry$analysis
  cells<-lapply(e$cells,function(c){cat<-c$catalogue
    list(key=cat$key,index=cat$source_record_index,label=paste(toupper(a$kind),"run",cat$source_record_index),
      identity=cat$identity,source_status=cat$source_status,reason=cat$original_reason,unit=cat$unit,
      original_bounds=cat$original_bounds,figure_state=cat$figure_state,counts=cat$counts,
      measures=lapply(seq_along(c$original_features),function(j){f<-c$original_features[[j]]
        list(original_index=c$feature_indices[[j]],name=f$name,label=.brohn_rpca_measure_label(f$name),value=f$value,unit=f$unit,
          reason=if("unavailable_reason" %in% names(f))f$unavailable_reason else NULL,original=f)}))})
  list(schema="brohn-cardiac-package-overview/0.1",title=paste("Saved",toupper(a$kind),"findings"),
    basis=if(a$kind=="ecg")"Detected RR; not NN-confirmed"else"Detected PRV; pulse-derived",
    outcome=if(!length(cells))"No runs remain in this saved result."else if(!any(vapply(cells,function(x)x$source_status=="computed",logical(1))))"No processed cardiac runs were saved."else NULL,
    total_cells=length(cells),illustrated_cells=sum(vapply(cells,function(x)x$figure_state=="illustrated",logical(1))),
    complete_feature_count=length(a$features),chapter_resolution=chapter_resolution,cells=cells,
    details=list(engine=a$engine,parameters=a$parameters,quality=a$quality,limitations=a$limitations,exclusion_review=a$exclusion_review),
    complete_evidence_retained=TRUE,scientific_processing_performed=FALSE)
}

brohn_resolve_cardiac_report_section <- function(section,entry) {
  brohn_report_package_cardiac_entry_validate(entry)
  .brohn_rpca_section_core(section,entry)
}
.brohn_rpca_section_core <- function(section,entry) {
  s<-section;e<-entry$evidence
  brohn_fields(s,c("schema","id","adapter","source_report_ref","prepared_ref","figure_cells","complete_source_evidence","components","show_intervals","show_spectrum","display_request_hash"),label="Cardiac report section")
  brohn_require(identical(s$schema,"brohn-cardiac-report-section/0.1")&&identical(s$adapter,"cardiac")&&brohn_text(s$id,500)&&
    .brohn_rpca_same(s$source_report_ref,e$source_ref)&&.brohn_rpca_same(s$prepared_ref,entry$ref)&&
    identical(s$display_request_hash,e$display_request_hash)&&identical(s$complete_source_evidence,TRUE)&&
    brohn_array(s$components)&&length(s$components)>0L&&length(s$components)<=2L&&!anyDuplicated(unlist(s$components))&&
    all(unlist(s$components) %in% c("raw","clean"))&&is.logical(s$show_intervals)&&length(s$show_intervals)==1L&&!is.na(s$show_intervals)&&
    is.logical(s$show_spectrum)&&length(s$show_spectrum)==1L&&!is.na(s$show_spectrum),"The cardiac section lost its frozen source, request or display identity.")
  selector<-.brohn_cdd_figure_cells(s$figure_cells);keys<-vapply(e$cells,function(c)c$catalogue$key,character(1))
  requested<-switch(selector$scope,all_cells=keys,first_chapter=head(keys,10L),exact_cells=unlist(selector$keys,use.names=FALSE),no_cells=character())
  brohn_require(all(requested %in% keys),"A requested cardiac figure cell is absent from the exact preparation.")
  models<-lapply(e$cells,function(c){cat<-c$catalogue;chosen<-cat$key %in% requested
    if(chosen&&identical(cat$source_status,"computed"))brohn_require(identical(cat$figure_state,"illustrated"),"A requested cardiac figure was not prepared; explicitly Prepare the new chapter.")
    cost<-0L
    if(chosen&&identical(cat$figure_state,"illustrated")) {
      for(v in c$waveform_views)if(identical(v$window$state,"available"))cost<-cost+length(s$components)*max(1L,length(v$markers$resolved_page_numbers))
      if(s$show_intervals)cost<-cost+sum(vapply(c$interval_views,function(v)length(v$points)>0L,logical(1)))
      if(s$show_spectrum&&!is.null(c$spectrum_view)&&identical(c$spectrum_view$availability$status,"available"))cost<-cost+1L
    }
    list(key=cat$key,model_hash=cat$model_hash,source_record_index=cat$source_record_index,selected=chosen,figure_state=cat$figure_state,panel_count=cost)
  })
  list(section=s,models=models,panel_count=sum(vapply(models,`[[`,numeric(1),"panel_count")),complete_cells=length(e$cells),complete_features=length(entry$analysis$features))
}

brohn_report_package_cardiac_export_request <- function(entry,identifier_mode="source_identifiers") {
  brohn_report_package_cardiac_entry_validate(entry)
  .brohn_rpca_export_request_core(entry,identifier_mode)
}
.brohn_rpca_export_request_core <- function(entry,identifier_mode="source_identifiers") {
  brohn_require(identical(identifier_mode,"source_identifiers"),"Cardiac package aliases require a qualified complete lineage projection. Choose explicit source identifiers; no alias/anonymization fallback is permitted.")
  list(schema="brohn-cardiac-package-projection-request/0.1",identifier_mode=identifier_mode,
    source_ref=entry$evidence$source_ref,prepared_ref=entry$ref,source_closure_hash=entry$evidence$closure_hash,
    payloads=unname(entry$payloads[vapply(entry$body$payloads,`[[`,character(1),"path")]),expected_cells=length(entry$evidence$cells),expected_features=length(entry$analysis$features))
}

# The caller owns publication, payload registration, complete-source holds and
# current authorization. All paths below stay within its fresh private attempt.
brohn_report_package_cardiac_write_complete <- function(bundle,entry,ordinal,output_dir,private,json,add) {
  brohn_require(brohn_number(ordinal,1,32,TRUE)&&is.function(json)&&is.function(add),"Choose a unique bounded cardiac source ordinal and host payload callbacks.")
  request<-brohn_report_package_cardiac_export_request(entry,bundle$selection$contents_policy$identifier_mode)
  .brohn_rpca_write_complete_core(bundle,entry,ordinal,output_dir,private,json,add,request)
}
.brohn_rpca_write_complete_core <- function(bundle,entry,ordinal,output_dir,private,json,add,request) {
  helper<-file.path(dirname(bundle$implementation$archive_script),"report_package_cardiac.py")
  brohn_require(file.exists(.brohn_rp_io_path(helper))&&identical(digest::digest(file=.brohn_rp_io_path(helper),algo="sha256"),bundle$implementation$sources[["scripts/workers/report_package_cardiac.py"]]),"The cardiac package helper changed from the pinned implementation.")
  stem<-sprintf("cardiac-%03d",ordinal);q<-file.path(private,paste0(stem,"-request.json"));r<-file.path(private,paste0(stem,"-result.json"));artifacts<-file.path(private,paste0(stem,"-files"))
  brohn_require(dir.exists(.brohn_rp_io_path(private))&&dir.exists(.brohn_rp_io_path(output_dir))&&!file.exists(.brohn_rp_io_path(q))&&!file.exists(.brohn_rp_io_path(r))&&!file.exists(.brohn_rp_io_path(artifacts)),"Choose fresh private cardiac projection paths.")
  brohn_eda_write_json_file(request,.brohn_rp_io_path(q),2*1024^2)
  child<-processx::run(bundle$implementation$archive_python,c("-B",helper,"--request",q,"--output",r,"--artifacts",artifacts),
    timeout=120,error_on_status=FALSE,cleanup_tree=TRUE,windows_hide_window=TRUE,
    stdout=.brohn_rp_io_path(file.path(private,paste0(stem,"-stdout.log"))),stderr=.brohn_rp_io_path(file.path(private,paste0(stem,"-stderr.log"))))
  brohn_require(file.exists(.brohn_rp_io_path(r)),"The complete cardiac payload helper returned no receipt.")
  result<-brohn_eda_read_json_file(.brohn_rp_io_path(r),2*1024^2)
  brohn_require(identical(child$status,0L)&&identical(result$schema,"brohn-cardiac-package-projection-result/0.1"),paste("Complete cardiac export refused:",result$message))
  brohn_require(.brohn_rpca_same(result$source_ref,request$source_ref)&&.brohn_rpca_same(result$prepared_ref,request$prepared_ref)&&
    identical(result$request_value_hash,brohn_eda_value_hash(request))&&identical(result$request_sha256,digest::digest(file=.brohn_rp_io_path(q),algo="sha256"))&&
    identical(result$source_closure_hash,request$source_closure_hash)&&identical(result$identifier_mode,"source_identifiers")&&
    .brohn_rpca_same(result$verified_runtime$Python,bundle$implementation$runtime$Python)&&
    identical(result$coverage$complete,TRUE)&&identical(result$coverage$all_original_payload_bytes_equal,TRUE)&&
    .brohn_rpca_same(result$files,entry$body$payloads),"The complete cardiac export lost its exact source, runtime or payload membership.")
  prefix<-sprintf("evidence/cardiac/source-%03d/",ordinal);files<-list()
  for(p in result$files) {
    original<-file.path(artifacts,p$path);relative<-paste0(prefix,p$path);target<-file.path(output_dir,relative)
    brohn_require(identical(digest::digest(file=.brohn_rp_io_path(original),algo="sha256"),p$hash)&&file.info(.brohn_rp_io_path(original))$size==p$bytes,"A complete cardiac export changed before collection.")
    dir.create(.brohn_rp_io_path(dirname(target)),recursive=TRUE,showWarnings=FALSE)
    brohn_require(!file.exists(.brohn_rp_io_path(target))&&file.copy(.brohn_rp_io_path(original),.brohn_rp_io_path(target),overwrite=FALSE)&&
      identical(digest::digest(file=.brohn_rp_io_path(target),algo="sha256"),p$hash),"The complete cardiac payload could not be retained exactly.")
    add(relative,p$media_type,p$role);files[[length(files)+1L]]<-c(list(path=relative),p[setdiff(names(p),"path")])
  }
  # No internal path or private alias map is included in this public receipt.
  receipt<-result;receipt$files<-files;json(receipt,paste0(prefix,"projection-receipt.json"),"complete_cardiac_projection_receipt")
  list(prefix=prefix,files=files,receipt=receipt,evidence=entry$evidence,analysis=entry$analysis)
}
