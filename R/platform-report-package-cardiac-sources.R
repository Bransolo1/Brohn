# Combined source ownership only. Existing profile admission remains unchanged.
.brohn_rpcc_source_selection_valid <- function(s) {
  .brohn_rpk_contents(s$contents_policy)
  brohn_require(is.list(s)&&identical(s$schema,"brohn-report-package-selection/0.4")&&
    brohn_report_package_cardiac_profile(s)&&
    identical(s$limits_profile,"controlled-task-choice-eda-cardiac-report-package/0.1")&&
    identical(s$contents_policy$identifier_mode,"source_identifiers")&&is.null(s$display_refs),
    "Use the exact combined cardiac selection and source-identifier policy.")
  brohn_require(brohn_valid_id(s$study_id)&&brohn_valid_id(s$project_id)&&brohn_array(s$report_refs)&&
    length(s$report_refs)>0L&&length(s$report_refs)<=8L&&brohn_array(s$prepared_sources)&&length(s$prepared_sources)<=128L,
    "Retain the bounded exact selected sources and preparations.")
  for(ref in s$report_refs){.brohn_rpk_ref_valid(ref,"report");brohn_require(identical(ref$project_id,s$project_id),"A selected report belongs to another project.")}
  brohn_require(!anyDuplicated(vapply(s$report_refs,brohn_hash,character(1))),"A selected source is repeated.")
  for(b in s$prepared_sources){
    brohn_fields(b,c("adapter","source_report_ref","prepared_ref","implementation_ref"),label="Frozen combined preparation")
    kinds<-c("explicit-distribution"="explicit_distributions","task-display"="task_display","choice-display"="choice_display","eda-display"="eda_display","cardiac-display"="cardiac_display")
    brohn_require(brohn_text(b$adapter,64)&&b$adapter %in% names(kinds),"This combined preparation adapter is unregistered.")
    .brohn_rpk_ref_valid(b$source_report_ref,"report");.brohn_rpk_ref_valid(b$prepared_ref,kinds[[b$adapter]])
    brohn_fields(b$implementation_ref,c("profile","hash"),label="Frozen preparation implementation")
    brohn_require(brohn_text(b$implementation_ref$profile,128)&&.brohn_rpk_hash(b$implementation_ref$hash)&&
      identical(b$prepared_ref$project_id,s$project_id)&&identical(b$source_report_ref$project_id,s$project_id),"A frozen preparation identity or project changed.")
  }
  brohn_require(!anyDuplicated(vapply(s$prepared_sources,function(b)brohn_hash(b$prepared_ref),character(1))),"A preparation is repeated in the selected inventory.")
  invisible(s)
}
.brohn_rpcc_legacy_selection <- function(s,refs) {
  x<-s;x$schema<-"brohn-report-package-selection/0.3"
  x$renderer_profile<-.brohn_rpk_profile_spec(s$renderer_profile)$legacy_renderer
  x$limits_profile<-"controlled-task-choice-eda-report-package/0.1";x$report_refs<-refs
  x$prepared_sources<-Filter(function(b)b$adapter!="cardiac-display",s$prepared_sources)
  x$sections<-Filter(function(b)b$adapter!="cardiac",s$sections)
  for(k in c("cardiac_display_requests","cardiac_figure_chapters","cardiac_source_requirements","cardiac_chapter_resolution"))x[[k]]<-NULL
  x
}
.brohn_rpcc_objects <- function(collections) {
  objects<-list()
  for(xs in collections)for(o in xs){
    value<-o[c("hash","bytes","media_type","path")]
    brohn_require(.brohn_rpk_hash(value$hash)&&brohn_number(value$bytes,0,1024^3,TRUE)&&
      brohn_text(value$media_type,128)&&brohn_text(value$path,4096),"A combined source object descriptor is invalid.")
    prior<-objects[[value$hash]]
    brohn_require(is.null(prior)||.brohn_rpk_same(prior,value),"The same combined source object has conflicting descriptors.")
    objects[[value$hash]]<-value
  }
  unname(objects[order(names(objects),method="radix")])
}
.brohn_rpcc_limits <- function(reports,objects,legacy,cardiac) {
  .brohn_cds_limit(length(reports),32L,"combined_source_reports")
  .brohn_cds_limit(length(objects),256L,"combined_source_objects")
  .brohn_cds_limit(sum(vapply(objects,`[[`,numeric(1),"bytes")),1024^3,"combined_source_bytes")
  streams<-list();rows<-0;tables<-0;cells<-0
  for(m in reports)if(m$kind %in% c("eda","ecg","ppg")){
    if(m$kind %in% c("ecg","ppg"))cells<-cells+m$record_count
    for(a in m$artifacts){
      prior<-streams[[a$hash]]
      brohn_require(is.null(prior)||.brohn_rpk_same(prior,a),"The same scientific stream has conflicting original descriptors.")
      streams[[a$hash]]<-a;rows<-rows+a$rows;tables<-tables+a$tables
    }
  }
  .brohn_cds_limit(cells,2000L,"complete_cardiac_cells")
  .brohn_cds_limit(sum(vapply(streams,`[[`,numeric(1),"size")),96*1024^2,"combined_scientific_stream_bytes")
  .brohn_cds_limit(rows,1e6,"combined_scientific_rows")
  .brohn_cds_limit(tables,256L,"combined_scientific_tables")
  evidence<-sum(vapply(legacy$eda_displays,function(x)x$object$bytes,numeric(1)))+sum(vapply(cardiac,function(x)x$artifact$bytes,numeric(1)))
  .brohn_cds_limit(evidence,48*1024^2,"combined_prepared_evidence_bytes")
  .brohn_cds_limit(sum(vapply(cardiac,function(x)sum(vapply(x$record$body$payloads,`[[`,numeric(1),"bytes")),numeric(1))),192*1024^2,"complete_cardiac_projection_bytes")
  invisible(TRUE)
}
.brohn_rpcc_selection_sources <- function(store,s,pulse=NULL) {
  .brohn_rpk_source_pulse(pulse)
  .brohn_rpcc_source_selection_valid(s);.brohn_rpk_study(store,s$study_id,s$project_id)
  partition<-.brohn_rpcc_partition(store,s$report_refs)
  brohn_require(length(partition$cardiac_refs)>0L,"The combined cardiac selection has no cardiac source.")
  legacy_selection<-.brohn_rpcc_legacy_selection(s,partition$noncardiac_refs)
  legacy<-if(length(partition$noncardiac_refs)).brohn_rpk_selection_sources(store,legacy_selection)else NULL
  .brohn_rpk_source_pulse(pulse)
  if(is.null(legacy))brohn_require(!length(legacy_selection$prepared_sources)&&!length(legacy_selection$eda_display_requests)&&
    !length(legacy_selection$related_eda_refs)&&.brohn_rpk_same(legacy_selection$source_identity_graph_binding,.brohn_rpcc_empty_eda_requirements()$source_identity_graph_binding),
    "A cardiac-only selection contains unrelated noncardiac evidence.")
  selected<-lapply(partition$cardiac_refs,function(ref){.brohn_rpk_source_pulse(pulse);m<-brohn_cardiac_source_metadata(store,ref);.brohn_rpk_source_pulse(pulse);m})
  requirements<-brohn_report_package_cardiac_requirements(selected,partition$cardiac_refs,s$study_id,s$project_id,.brohn_rpk_profile_spec(s$renderer_profile)$admission)
  brohn_require(.brohn_rpk_same(requirements,s$cardiac_source_requirements),"The complete cardiac requirements or original closure changed.")
  views<-.brohn_rpcc_normalize_requests(s$cardiac_display_requests,partition$cardiac_refs)
  brohn_require(.brohn_rpk_same(views,s$cardiac_display_requests)&&.brohn_rpk_same(s$cardiac_figure_chapters,brohn_normalize_cardiac_figure_chapters(s$cardiac_figure_chapters)),"Frozen cardiac view choices were not normalized.")
  chapters<-s$cardiac_chapter_resolution
  planning<-lapply(selected,function(m)list(report_ref=m$report_ref,closure_hash=m$closure_hash,record_count=m$selected$record_count))
  brohn_require(.brohn_rpk_same(brohn_cardiac_chapter_plan(planning,s$cardiac_figure_chapters),chapters$plan),"The frozen cardiac chapter or exact cell membership changed.")
  # Immutable original closure plus prepared catalogue bind exact record keys;
  # fences recheck the pure chapter plan without repeating source pagination.
  for(ref in partition$cardiac_refs){
    v<-Filter(function(x).brohn_rpk_same(x$report_ref,ref),views)
    expected<-brohn_normalize_cardiac_display_request(if(length(v))v[[1L]]$display_request else NULL)
    resolved<-Filter(function(x).brohn_rpk_same(x$report_ref,ref),chapters$reports)
    brohn_require(length(resolved)==1L,"A selected cardiac source lost its resolved chapter request.")
    expected$figure_cells<-resolved[[1L]]$display_request$figure_cells
    brohn_require(.brohn_rpk_same(brohn_normalize_cardiac_display_request(expected),resolved[[1L]]$display_request),"Frozen per-cell cardiac choices differ from the resolved chapter request.")
  }
  bindings<-Filter(function(b)b$adapter=="cardiac-display",s$prepared_sources)
  brohn_require(length(bindings)==length(requirements$sources),"Each selected or required cardiac source needs exactly one preparation.")
  dependency_plans<-list()
  cardiac<-lapply(requirements$sources,function(source){
    .brohn_rpk_source_pulse(pulse)
    ref<-source$report_ref;matches<-Filter(function(b).brohn_rpk_same(b$source_report_ref,ref),bindings)
    brohn_require(length(matches)==1L,"A required cardiac preparation is missing or ambiguous.");binding<-matches[[1L]]
    plan_key<-brohn_hash(binding$implementation_ref)
    if(is.null(dependency_plans[[plan_key]]))dependency_plans[[plan_key]]<<-brohn_report_package_cardiac_dependencies(requirements,chapters,binding$implementation_ref)
    expected<-dependency_plans[[plan_key]][[source$source_ordinal]]
    m<-brohn_cardiac_display_metadata(store,binding$prepared_ref);.brohn_rpk_source_pulse(pulse)
    actual<-list(profile=m$record$body$implementation$profile,hash=m$record$body$implementation_hash)
    brohn_require(.brohn_rpk_same(m$report_ref,ref)&&.brohn_rpk_same(actual,binding$implementation_ref)&&
      .brohn_rpk_same(m$record$body$display_request,expected$display_request),"A saved cardiac preparation differs from its frozen source, original implementation or chapter choices.")
    if(isTRUE(source$selected)){
      resolved<-Filter(function(x).brohn_rpk_same(x$report_ref,ref),chapters$reports)[[1L]]
      for(cell in resolved$selected_cells){
        cat<-m$record$body$catalog[[cell$source_record_index]]
        brohn_require(!is.null(cat)&&identical(cat$key,cell$key),"A frozen chapter key differs from its exact saved original record.")
      }
    }
    m
  })
  reports<-list()
  add_report<-function(m){key<-brohn_hash(m$ref);prior<-reports[[key]]
    brohn_require(is.null(prior)||.brohn_rpk_same(prior,m),"One exact original report has conflicting complete metadata.");reports[[key]]<<-m}
  for(m in legacy$reports)add_report(m)
  for(m in cardiac)for(report in m$source_metadata$reports)add_report(report)
  ordered<-c(vapply(s$report_refs,brohn_hash,character(1)),setdiff(names(reports),vapply(s$report_refs,brohn_hash,character(1))))
  brohn_require(all(ordered %in% names(reports)),"A selected report is missing from the complete source union.")
  reports<-unname(reports[ordered])
  for(m in reports)brohn_require(identical(m$study_id,s$study_id)&&identical(m$ref$project_id,s$project_id),"A complete source belongs to another actual study or project.")
  objects<-.brohn_rpcc_objects(c(list(legacy$objects),lapply(cardiac,function(m)c(m$objects,m$source_metadata$objects))))
  .brohn_rpcc_limits(reports,objects,legacy,cardiac)
  .brohn_rpk_source_pulse(pulse)
  list(schema="brohn-combined-cardiac-source-metadata/0.1",selection=s,report_refs=s$report_refs,
    source_admission=.brohn_rpk_profile_spec(s$renderer_profile)$admission,legacy=legacy,cardiac_displays=cardiac,
    cardiac_source_requirements=requirements,cardiac_chapter_resolution=chapters,reports=reports,objects=objects,
    assets=if(is.null(legacy))list()else legacy$assets)
}
.brohn_rpcc_release <- function(handle) {
  if(is.environment(handle)&&inherits(handle,"brohn_cardiac_report_source_resources")&&is.environment(handle$state)&&!isTRUE(handle$state$closed)){
    state<-handle$state;state$closed<-TRUE
    on.exit(handle$reader$close(),add=TRUE)
    for(g in handle$state$extra_guards)tryCatch(.brohn_qexplorer_release(g),error=function(e)NULL)
    for(resource in handle$cardiac_resources)tryCatch(brohn_release_cardiac_display_resources(resource$handle),error=function(e)NULL)
    if(!is.null(handle$legacy_handle))tryCatch(.brohn_rpk_release(handle$legacy_handle),error=function(e)NULL)
  };invisible(NULL)
}
.brohn_rpcc_hold_sources <- function(store,metadata,pulse=NULL) {
  brohn_require(identical(metadata$schema,"brohn-combined-cardiac-source-metadata/0.1"),"Open the exact combined source metadata.")
  reader<-.brohn_cardiac_source_reader(store,pulse)
  old<-NULL;resources<-list();ok<-FALSE
  on.exit(if(!ok){reader$close();for(resource in resources)tryCatch(brohn_release_cardiac_display_resources(resource$handle),error=function(e)NULL);if(!is.null(old)).brohn_rpk_release(old)},add=TRUE)
  .brohn_rpk_source_pulse(pulse)
  if(!is.null(metadata$legacy))old<-.brohn_rpk_hold_sources(store,metadata$legacy,pulse)
  for(m in metadata$cardiac_displays){.brohn_rpk_source_pulse(pulse)
    resources[[length(resources)+1L]]<-reader$open(store,m$ref,m$ref$project_id,pulse)
  }
  current<-reader$selection(store,metadata$selection,pulse)
  brohn_require(.brohn_rpk_same(current,metadata),"Combined sources changed while establishing their native read holds.")
  h<-new.env(parent=emptyenv());class(h)<-"brohn_cardiac_report_source_resources"
  h$metadata<-metadata;h$workspace_id<-store$workspace_id;h$legacy_handle<-old;h$cardiac_resources<-resources
  h$reader<-reader;h$state<-new.env(parent=emptyenv());h$state$closed<-FALSE;h$state$extra_guards<-list()
  lockEnvironment(h,bindings=TRUE);reg.finalizer(h,.brohn_rpcc_release,onexit=TRUE)
  .brohn_rpcc_sources_current(store,h,pulse);.brohn_rpk_source_pulse(pulse);ok<-TRUE;h
}
.brohn_rpcc_sources_current <- function(store,handle,pulse=NULL) {
  brohn_require(is.environment(handle)&&inherits(handle,"brohn_cardiac_report_source_resources")&&environmentIsLocked(handle)&&
    !isTRUE(handle$state$closed)&&identical(store$workspace_id,handle$workspace_id),"Reopen these closed or different-workspace combined report sources.")
  .brohn_cm_guard_check(handle$state$extra_guards)
  if(!is.null(handle$legacy_handle)){.brohn_rpk_source_pulse(pulse);brohn_report_package_sources_current(store,handle$legacy_handle);.brohn_rpk_source_pulse(pulse)}
  for(resource in handle$cardiac_resources){.brohn_rpk_source_pulse(pulse);handle$reader$current(store,resource$handle);.brohn_rpk_source_pulse(pulse)}
  current<-handle$reader$selection(store,handle$metadata$selection,pulse)
  brohn_require(.brohn_rpk_same(current,handle$metadata),"The combined source permission, successful producer or original closure changed.")
  .brohn_cm_guard_check(handle$state$extra_guards);invisible(current)
}
.brohn_rpcc_complete_sources <- function(store,handle,pulse=NULL) {
  .brohn_rpk_source_pulse(pulse);m<-.brohn_rpcc_sources_current(store,handle,pulse)
  result<-if(!is.null(handle$legacy_handle)).brohn_rpk_complete_sources(store,handle$legacy_handle,pulse=pulse)else
    list(reports=list(),distributions=list(),task_displays=list(),assets=list(),choice_displays=list(),eda_displays=list(),
      source_identity_graph=.brohn_rpcc_empty_eda_requirements()$source_identity_graph_binding,related_eda_sources=list())
  original<-list()
  add<-function(x){key<-brohn_hash(x$ref);prior<-original[[key]]
    brohn_require(is.null(prior)||.brohn_rpk_same(prior,x),"An exact original report has conflicting complete scientific values.");original[[key]]<<-x}
  for(x in result$reports)add(x)
  entries<-lapply(handle$cardiac_resources,function(resource){.brohn_rpk_source_pulse(pulse)
    handle$reader$current(store,resource$handle)
    entry<-brohn_report_package_cardiac_entry(resource);for(x in entry$source_reports)add(x);entry})
  result$reports<-lapply(m$report_refs,function(ref){x<-original[[brohn_hash(ref)]];brohn_require(!is.null(x),"A selected complete report is missing.");x})
  result$cardiac_displays<-entries
  required<-Filter(function(x)!isTRUE(x$selected),m$cardiac_source_requirements$sources)
  result$related_cardiac_sources<-lapply(required,function(x){
    entry<-Filter(function(e).brohn_rpk_same(e$evidence$source_ref,x$report_ref),entries)
    brohn_require(length(entry)==1L&&!is.null(original[[brohn_hash(x$report_ref)]]),"A required cardiac parent lost its complete preparation.")
    list(source_ordinal=x$source_ordinal,report=original[[brohn_hash(x$report_ref)]],required_by=x$required_by,prepared_ref=entry[[1L]]$ref)
  })
  result$cardiac_source_requirements<-m$cardiac_source_requirements
  result$cardiac_chapter_resolution<-m$cardiac_chapter_resolution
  .brohn_rpk_source_pulse(pulse);.brohn_rpcc_sources_current(store,handle,pulse);result
}
