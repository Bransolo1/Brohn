# Combined preparation is an explicit new generation. Existing EDA/task/choice
# requests keep their original closed contracts and are composed unchanged.
.brohn_rpk_cardiac_profile <- function(x) isTRUE(.brohn_rpk_profile_spec(x$renderer_profile,FALSE)$cardiac)
.brohn_rpk_cardiac_admission <- "task-choice-eda-cardiac-findings/0.1"
.brohn_rpk_cardiac_limits_profile <- "controlled-task-choice-eda-cardiac-report-package/0.1"
brohn_report_package_cardiac_limits <- function() {
  x<-brohn_report_package_eda_limits();x$profile<-.brohn_rpk_cardiac_limits_profile
  c(x,list(max_cardiac_sources=32L,max_cardiac_cells=2000L,max_cardiac_source_rows=1000000L,
    max_cardiac_source_tables=256L,max_cardiac_source_bytes=96*1024^2,
    max_cardiac_evidence_bytes=48*1024^2,max_cardiac_projection_bytes=192*1024^2))
}
.brohn_rpcc_ref_member <- function(ref,refs) any(vapply(refs,function(x).brohn_rpk_same(x,ref),logical(1)))
.brohn_rpcc_normalize_requests <- function(requests,refs) {
  if(is.null(requests))requests<-list()
  brohn_require(brohn_array(requests)&&length(requests)<=8L,"Choose one set of cardiac view choices per selected report.")
  values<-list();seen<-character()
  for(x in requests){
    brohn_fields(x,c("report_ref","display_request"),label="Saved cardiac view choices")
    .brohn_rpk_ref_valid(x$report_ref,"report")
    key<-brohn_hash(x$report_ref)
    brohn_require(.brohn_rpcc_ref_member(x$report_ref,refs)&&!key %in% seen,"Cardiac choices must belong to one exact selected report, without duplicates.")
    seen<-c(seen,key)
    value<-brohn_normalize_cardiac_display_request(x$display_request)
    # Global chapters own membership. A per-source selection cannot silently
    # override them; only per-cell view choices belong in this input collection.
    brohn_require(identical(value$figure_cells,list(scope="first_chapter",keys=list())),
      "Choose cardiac figure membership with the report's global chapter control.")
    if(length(value$cell_overrides))values[[key]]<-list(report_ref=x$report_ref,display_request=value)
  }
  unname(Filter(Negate(is.null),lapply(refs,function(ref)values[[brohn_hash(ref)]])))
}
.brohn_rpcc_legacy_request <- function(request,refs) {
  x<-request[c("schema","study_id","project_id","title","report_refs","requested_sections","contents_policy","limits_profile","renderer_profile","eda_display_requests")]
  x$schema<-"brohn-report-package-intent-request/0.1"
  x$renderer_profile<-.brohn_rpk_profile_spec(request$renderer_profile)$legacy_renderer
  x$limits_profile<-"controlled-task-choice-eda-report-package/0.1"
  x$report_refs<-refs
  x$requested_sections<-Filter(function(s)s$adapter!="cardiac",request$requested_sections)
  x
}
.brohn_rpcc_partition <- function(store,refs) {
  metadata<-lapply(refs,function(ref).brohn_rpk_report_metadata(store,ref))
  cardiac<-vapply(metadata,function(m)m$kind %in% c("ecg","ppg"),logical(1))
  list(cardiac_refs=refs[cardiac],noncardiac_refs=refs[!cardiac],metadata=metadata)
}
.brohn_rpcc_requested_section <- function(section,refs) {
  brohn_fields(section,c("id","adapter","adapter_version","source_report_ref","selector","display","order"),label="Cardiac report section")
  brohn_require(brohn_valid_id(section$id)&&identical(section$adapter,"cardiac")&&identical(section$adapter_version,"0.1")&&
    brohn_number(section$order,1,100,TRUE),"Choose an ordered cardiac report section.")
  .brohn_rpk_ref_valid(section$source_report_ref,"report")
  brohn_require(.brohn_rpcc_ref_member(section$source_report_ref,refs),"A cardiac figure section must belong to an exact selected cardiac report.")
  brohn_fields(section$selector,"scope",label="Cardiac section membership")
  brohn_require(identical(section$selector$scope,"prepared_chapter"),"Cardiac figures use the one global chapter selection.")
  d<-section$display
  brohn_fields(d,c("components","show_intervals","show_spectrum"),label="Cardiac chart choices")
  flag<-function(x)is.logical(x)&&length(x)==1L&&!is.na(x)
  brohn_require(brohn_array(d$components)&&length(d$components)>0L&&length(d$components)<=2L&&
    all(vapply(d$components,function(x)brohn_text(x,8)&&x %in% c("raw","clean"),logical(1)))&&
    !anyDuplicated(unlist(d$components))&&flag(d$show_intervals)&&flag(d$show_spectrum),"Choose raw or cleaned waveforms and optional interval/spectrum charts.")
  invisible(section)
}
.brohn_rpcc_request <- function(store,request) {
  brohn_fields(request,c("schema","study_id","project_id","title","report_refs","requested_sections","contents_policy","limits_profile","renderer_profile",
    "eda_display_requests","cardiac_display_requests","cardiac_figure_chapters"),label="Combined cardiac report preparation")
  brohn_require(identical(request$schema,"brohn-report-package-intent-request/0.2")&&.brohn_rpk_cardiac_profile(request)&&
    identical(request$limits_profile,.brohn_rpk_cardiac_limits_profile)&&brohn_text(request$title,500),"Use the exact combined cardiac report profile.")
  .brohn_rpk_study(store,request$study_id,request$project_id);.brohn_rpk_contents(request$contents_policy)
  brohn_require(identical(request$contents_policy$identifier_mode,"source_identifiers"),
    "Cardiac reports currently retain source identifiers. Package aliases require the complete cardiac lineage projection; no alias fallback is applied.")
  refs<-request$report_refs
  brohn_require(brohn_array(refs)&&length(refs)>0L&&length(refs)<=8L,"Select one to eight exact saved reports.")
  for(ref in refs){.brohn_rpk_ref_valid(ref,"report");brohn_require(identical(ref$project_id,request$project_id),"Every selected report must belong to this project.")}
  brohn_require(!anyDuplicated(vapply(refs,brohn_hash,character(1))),"Select each exact saved report once.")
  partition<-.brohn_rpcc_partition(store,refs)
  brohn_require(length(partition$cardiac_refs)>0L,"The cardiac-capable profile requires a selected ECG or PPG report.")
  for(m in partition$metadata)brohn_require(identical(m$study_id,request$study_id),"Every selected report must belong to this actual study.")
  brohn_require(.brohn_rpk_same(request$cardiac_display_requests,.brohn_rpcc_normalize_requests(request$cardiac_display_requests,partition$cardiac_refs))&&
    .brohn_rpk_same(request$cardiac_figure_chapters,brohn_normalize_cardiac_figure_chapters(request$cardiac_figure_chapters)),"Normalize and preserve the exact cardiac chapter and view choices.")
  sections<-request$requested_sections
  brohn_require(brohn_array(sections)&&length(sections)<=100L,"Choose up to 100 report sections; complete findings are retained without figures.")
  for(s in sections)if(identical(s$adapter,"cardiac")) .brohn_rpcc_requested_section(s,partition$cardiac_refs)else .brohn_rpk_section(s,partition$noncardiac_refs)
  brohn_require(!anyDuplicated(vapply(sections,`[[`,character(1),"id"))&&!anyDuplicated(vapply(sections,`[[`,numeric(1),"order")),"Keep section identities and order distinct.")
  legacy<-.brohn_rpcc_legacy_request(request,partition$noncardiac_refs)
  if(length(partition$noncardiac_refs)).brohn_rpk_request(store,legacy)
  else brohn_require(!length(legacy$eda_display_requests)&&!length(legacy$requested_sections),"A cardiac-only report cannot contain unrelated EDA choices or noncardiac figures.")
  # Saving/advancing verifies the full current closure through requirements.
  # Request grammar checks do not repeat that multi-source walk or decode streams.
  brohn_require(nchar(brohn_json(request),type="bytes")<=2*1024^2,"These complete cardiac view choices exceed the bounded request profile.")
  invisible(request)
}
.brohn_rpcc_empty_eda_requirements <- function() list(required_eda_refs=list(),related_eda_refs=list(),
  source_identity_graph_binding=list(schema="brohn-report-source-identity-graph/0.1",root_refs=list(),nodes=list(),edges=list()))
.brohn_rpcc_requirement_sources <- function(store,request,pulse=NULL) {
  p<-.brohn_rpcc_partition(store,request$report_refs)
  spec<-.brohn_rpk_profile_spec(request$renderer_profile)
  eda<-if(length(p$noncardiac_refs)).brohn_rpk_eda_requirements(store,p$noncardiac_refs,spec$legacy_admission)else .brohn_rpcc_empty_eda_requirements()
  cardiac<-brohn_report_package_cardiac_requirements(lapply(p$cardiac_refs,function(ref){.brohn_rpk_source_pulse(pulse);brohn_cardiac_source_metadata(store,ref)}),
    p$cardiac_refs,request$study_id,request$project_id,source_admission=spec$admission)
  brohn_require(length(eda$source_identity_graph_binding$nodes)+length(cardiac$sources)<=32L,"The combined original report closure exceeds 32 sources.")
  list(schema="brohn-combined-cardiac-requirements/0.1",noncardiac_report_refs=p$noncardiac_refs,
    eda=eda,cardiac=cardiac)
}
.brohn_rpcc_requirements <- function(store,request,pulse=NULL) {
  result<-.brohn_rpcc_requirement_sources(store,request,pulse)
  refs<-result$cardiac$selected_refs
  views<-lapply(refs,function(ref){x<-Filter(function(x).brohn_rpk_same(x$report_ref,ref),request$cardiac_display_requests);if(length(x))x[[1L]]$display_request else NULL})
  result$cardiac_chapter_resolution<-brohn_cardiac_chapter_requests(store,refs,request$cardiac_figure_chapters,views,pulse)
  result
}
.brohn_rpcc_requirements_current <- function(store,body,pulse=NULL) {
  actual<-.brohn_rpcc_requirement_sources(store,body$request,pulse)
  saved<-body$source_requirements
  brohn_require(.brohn_rpk_same(actual,saved[setdiff(names(saved),"cardiac_chapter_resolution")]),
    "The exact report closure changed. Prepare a new version from your saved choices.")
  # Current exact closure hashes include the original record bodies and jobs.
  # The immutable intent already pins the resolved original keys. Recheck their
  # global plan with fresh counts; do not repeat catalogue pagination on polling.
  chapters<-saved$cardiac_chapter_resolution
  sources<-lapply(actual$cardiac$selected_refs,function(ref){s<-Filter(function(s).brohn_rpk_same(s$report_ref,ref),actual$cardiac$sources)[[1L]]
    b<-Filter(function(b).brohn_rpk_same(b$report_ref,ref),actual$cardiac$closure_bindings)[[1L]]
    list(report_ref=ref,closure_hash=b$closure_hash,record_count=s$record_count)})
  brohn_require(.brohn_rpk_same(brohn_cardiac_chapter_plan(sources,body$request$cardiac_figure_chapters),chapters$plan),
    "The frozen global cardiac chapter membership changed.")
  brohn_report_package_cardiac_dependencies(actual$cardiac,chapters,body$execution_plan$cardiac_display_implementation_ref)
  saved
}
.brohn_rpcc_execution_plan <- function(request) {
  plan<-.brohn_rpk_execution_plan(.brohn_rpcc_legacy_request(request,list()))
  spec<-.brohn_rpk_profile_spec(request$renderer_profile)
  plan$schema<-spec$plan_schema
  plan$source_admission<-spec$admission
  plan$cardiac_display_implementation_ref<-brohn_cardiac_display_implementation_ref();plan
}
.brohn_rpcc_plan_valid <- function(plan,request=NULL) {
  brohn_fields(plan,c("schema","source_admission","explicit_distribution_implementation_ref","task_display_implementation_ref","choice_display_implementation_ref",
    "eda_display_implementation_ref","renderer_implementation_ref","cardiac_display_implementation_ref"),label="Pinned combined preparation plan")
  spec<-.brohn_rpk_admission_spec(plan$source_admission)
  brohn_require(isTRUE(spec$cardiac)&&identical(plan$schema,spec$plan_schema)&&
    (is.null(request)||identical(request$renderer_profile,spec$renderer)),"The saved cardiac plan belongs to another renderer.")
  impl<-plan$cardiac_display_implementation_ref;brohn_fields(impl,c("profile","hash"),label="Pinned cardiac implementation")
  brohn_require(identical(impl$profile,"saved-cardiac-display/0.1")&&.brohn_rpk_hash(impl$hash),"Retain the exact cardiac implementation identity.")
  legacy<-plan;legacy$schema<-.brohn_rpk_profile_spec(spec$legacy_renderer)$plan_schema;legacy$source_admission<-spec$legacy_admission;legacy$cardiac_display_implementation_ref<-NULL
  .brohn_rpk_plan_valid(legacy,if(is.null(request))NULL else .brohn_rpcc_legacy_request(request,list()));invisible(plan)
}
.brohn_rpcc_dependency_specs <- function(store,request,plan,requirements) {
  brohn_require(identical(requirements$schema,"brohn-combined-cardiac-requirements/0.1"),"The complete combined source requirements are missing.")
  legacy<-.brohn_rpcc_legacy_request(request,requirements$noncardiac_report_refs)
  spec<-.brohn_rpk_profile_spec(request$renderer_profile)
  oldplan<-plan;oldplan$schema<-.brohn_rpk_profile_spec(spec$legacy_renderer)$plan_schema;oldplan$source_admission<-spec$legacy_admission;oldplan$cardiac_display_implementation_ref<-NULL
  prior<-if(length(legacy$report_refs)).brohn_rpk_task_dependency_specs(store,legacy,oldplan,requirements$eda)else list()
  c(prior,brohn_report_package_cardiac_dependencies(requirements$cardiac,requirements$cardiac_chapter_resolution,plan$cardiac_display_implementation_ref))
}
.brohn_rpcc_pending_dependency <- function(store,spec,previous) {
  if(is.null(previous)||is.null(previous$job_id))return(NULL)
  job<-brohn_get_job(store,previous$job_id)
  if(is.null(job)||!job$status %in% c("queued","running"))return(NULL)
  brohn_report_package_queue_authority(store,"cardiac_display",spec$report_ref$project_id)
  q<-job$request
  brohn_require(identical(job$operation,"cardiac_display")&&identical(q$schema,"brohn-cardiac-display-job/0.1")&&
    .brohn_rpk_same(q$report_ref,spec$report_ref)&&.brohn_rpk_same(q$display_request,spec$display_request)&&
    .brohn_rpk_same(.brohn_td_implementation_ref(q$implementation),spec$implementation_ref)&&
    identical(q$content_fingerprint,brohn_hash(q[setdiff(names(q),c("authority","content_fingerprint"))]))&&
    .brohn_rpk_same(previous[names(spec)],spec),"The pending cardiac prerequisite no longer matches its exact saved slot.")
  # Called only after the whole original closure was freshly checked. A pending
  # status is not evidence: successful jobs still enter the complete saved reader,
  # and execution/publication independently reopen current source authority.
  c(spec,list(job_id=job$id,created_for_intent=isTRUE(previous$created_for_intent),result_ref=NULL,status=job$status))
}
.brohn_rpcc_resolve_sections <- function(store,request,deps) {
  result<-list(sections=list(),panel_count=0L,known_panel_count=0L)
  for(s in request$requested_sections){
    if(s$adapter!="cardiac"){
      legacy<-.brohn_rpcc_legacy_request(request,list(s$source_report_ref));legacy$requested_sections<-list(s)
      x<-.brohn_rpk_resolve_sections(store,legacy,deps)
      result$sections<-c(result$sections,x$sections);result$known_panel_count<-result$known_panel_count+x$known_panel_count
      if(is.null(x$panel_count))result$panel_count<-NULL else if(!is.null(result$panel_count))result$panel_count<-result$panel_count+x$panel_count
      next
    }
    d<-Filter(function(d)d$kind=="cardiac_display"&&.brohn_rpk_same(d$report_ref,s$source_report_ref),deps)
    brohn_require(length(d)==1L&&!is.null(d[[1L]]$result_ref),"Cardiac figures need their exact saved preparation.")
    d<-d[[1L]];m<-brohn_cardiac_display_metadata(store,d$result_ref)
    brohn_require(.brohn_rpk_same(m$report_ref,s$source_report_ref)&&.brohn_rpk_same(m$record$body$display_request,d$display_request),"The prepared cardiac view differs from these saved chapter choices.")
    s$source_ref<-d$result_ref
    s$cardiac_section<-c(list(schema="brohn-cardiac-report-section/0.1",id=s$id,adapter="cardiac",source_report_ref=s$source_report_ref,
      prepared_ref=d$result_ref,figure_cells=d$display_request$figure_cells,complete_source_evidence=TRUE),s$display,
      list(display_request_hash=brohn_eda_value_hash(d$display_request)))
    # The complete prepared model is decoded and authoritatively counted in the
    # supervised assembler. Catalogue counts alone cannot prove marker panels.
    result$sections<-c(result$sections,list(s));result$panel_count<-NULL
  };result
}
.brohn_rpcc_freeze <- function(selection,request,requirements) {
  selection$schema<-.brohn_rpk_profile_spec(request$renderer_profile)$selection_schema
  selection$eda_display_requests<-request$eda_display_requests
  selection$related_eda_refs<-requirements$eda$related_eda_refs
  selection$source_identity_graph_binding<-requirements$eda$source_identity_graph_binding
  selection$cardiac_display_requests<-request$cardiac_display_requests
  selection$cardiac_figure_chapters<-request$cardiac_figure_chapters
  selection$cardiac_source_requirements<-requirements$cardiac
  selection$cardiac_chapter_resolution<-requirements$cardiac_chapter_resolution
  selection$coverage$profile_supported_adapters<-as.list(c("gaze-context","explicit-distribution","paired-findings",.brohn_rpk_task_adapters,.brohn_rpk_choice_adapters,.brohn_rpk_eda_adapters,"cardiac"))
  selection$coverage$numerical_evidence<-"complete_selected_reports_and_required_eda_cardiac_sources"
  selection$coverage$cardiac_identifiers<-"source_identifiers_preserved"
  selection$coverage$cardiac_scientific_processing_performed<-FALSE
  selection
}
.brohn_rpcc_manifest_sources <- function(s) {
  refs<-function(adapter)lapply(Filter(function(x)x$adapter==adapter,s$prepared_sources),`[[`,"prepared_ref")
  list(reports=s$report_refs,distributions=refs("explicit-distribution"),task_displays=refs("task-display"),
    choice_displays=refs("choice-display"),eda_displays=refs("eda-display"),cardiac_displays=refs("cardiac-display"),
    related_eda_sources=s$related_eda_refs,source_identity_graph_binding=s$source_identity_graph_binding,
    cardiac_source_requirements=s$cardiac_source_requirements,cardiac_chapter_resolution=s$cardiac_chapter_resolution)
}

.brohn_rpcc_report_choice <- function(store,m) {
  result<-tryCatch({
    source<-brohn_cardiac_source_metadata(store,m$ref)
    brohn_report_package_cardiac_requirements(list(source),list(m$ref),m$study_id,m$ref$project_id)
    list(source=source,error=NULL)
  },error=function(e)list(source=NULL,error=substr(conditionMessage(e),1L,1000L)))
  available<-is.null(result$error)
  list(ref=m$ref,title=brohn_default(m$title,m$ref$id),origin=m$origin,kind=m$kind,
    source_family=NULL,source_components=list("cardiac"),choice_source_family=NULL,eda_source_family=NULL,has_required_eda=FALSE,
    cardiac_record_count=if(available)result$source$selected$record_count else NULL,
    cardiac_source_closure_hash=if(available)result$source$closure_hash else NULL,
    design_hash=m$design_hash,adapters=if(available)list("cardiac")else list(),
    status=if(available)"available"else"unsupported_package_adapter",reason=result$error,
    recommended_refs=if(available)list(m$ref)else list(),
    recommendation_reason=if(available)"Includes this saved cardiac result and the complete evidence from any required original parent. Figure chapters use your selected results only."else result$error)
}

# Ownership is durable across sharing: the last remaining intent can cancel a
# prerequisite originally created by an earlier intent that has since stopped.
# Jobs that predated all report intents are never claimed by this cleanup.
.brohn_rpk_dependency_created_by_intent <- function(store,job_id) {
  rows<-DBI::dbGetQuery(store$con,paste("SELECT 1 AS owned FROM entities e JOIN entity_versions v ON e.kind=v.kind AND e.id=v.id AND e.revision=v.revision,",
    "json_each(v.body_json,'$.dependencies') d WHERE e.kind='report_package_intent'",
    "AND json_extract(d.value,'$.job_id')=? AND json_extract(d.value,'$.created_for_intent')=1 LIMIT 1"),params=list(job_id))
  nrow(rows)==1L
}
