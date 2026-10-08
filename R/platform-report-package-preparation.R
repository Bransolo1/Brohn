# Task-capable preparation keeps the original complete-findings lifecycle.
# Only bounded metadata is resolved here. Source replay/full decoding belongs
# to supervised prerequisites; saved scientific scores are never recomputed.
.brohn_rpk_task_profile <- function(x) identical(x$renderer_profile,"controlled-gaze-explicit-task-paired/0.1")
.brohn_rpk_eda_profile <- function(x) .brohn_rpk_eda_report_profile(x$renderer_profile)
.brohn_rpk_eda_preparation_profile <- function(x) {
  brohn_require(.brohn_rpk_eda_profile(x),"Choose a supported EDA report renderer.")
  .brohn_rpk_profile_spec(x$renderer_profile)$eda_preparation
}
.brohn_rpk_eda_plan_schema <- function(x) {
  brohn_require(.brohn_rpk_eda_profile(x),"Choose a supported EDA report renderer.")
  .brohn_rpk_profile_spec(x$renderer_profile)$plan_schema
}
.brohn_rpk_choice_profile <- function(x) identical(x$renderer_profile,"controlled-gaze-explicit-task-choice-paired/0.1")||.brohn_rpk_eda_profile(x)
.brohn_rpk_prepared_profile <- function(x) .brohn_rpk_cardiac_profile(x)||.brohn_rpk_task_profile(x)||.brohn_rpk_choice_profile(x)
.brohn_rpk_limits <- function(x) if(.brohn_rpk_cardiac_profile(x))brohn_report_package_cardiac_limits()else if(.brohn_rpk_eda_profile(x))brohn_report_package_eda_limits()else if(.brohn_rpk_choice_profile(x))brohn_report_package_choice_limits()else if(.brohn_rpk_task_profile(x))brohn_report_package_task_limits()else brohn_report_package_limits()
.brohn_rpk_task_adapters <- c("task-scores","task-trials","task-people")
.brohn_rpk_choice_adapters <- c("choice-counts","choice-utilities")
.brohn_rpk_eda_adapters <- c("eda-events","eda-continuous")
# The mixed renderer does not widen the unchanged questionnaire prerequisite.
.brohn_rpk_distribution_admission_for <- function(request) {
  if(.brohn_rpk_choice_profile(request)||.brohn_rpk_cardiac_profile(request))"task-choice-findings/0.1"else brohn_report_source_admission(request$renderer_profile)
}
.brohn_rpk_normalize_eda_requests <- function(requests,refs) {
  if(is.null(requests))requests<-list()
  brohn_require(brohn_array(requests)&&length(requests)<=8L,"Choose at most one EDA window request per selected source.")
  keys<-character();values<-list()
  for(x in requests){
    brohn_fields(x,c("report_ref","display_request"),label="EDA display window source")
    .brohn_rpk_ref_valid(x$report_ref,"report")
    brohn_require(any(vapply(refs,function(r).brohn_rpk_same(r,x$report_ref),logical(1))),"EDA window choices must belong to an exact selected report.")
    key<-brohn_hash(x$report_ref)
    brohn_require(!key %in% keys,"Choose one EDA window request per exact source.")
    keys<-c(keys,key);value<-brohn_normalize_eda_display_request(x$display_request)
    if(length(value$continuous_windows))values[[key]]<-list(report_ref=x$report_ref,display_request=value)
  }
  # Defaults have one representation; selected source order is canonical.
  result<-list()
  for(ref in refs){key<-brohn_hash(ref);if(!is.null(values[[key]]))result<-c(result,list(values[[key]]))}
  result
}
.brohn_rpk_eda_request_for <- function(request,ref) {
  found<-Filter(function(x).brohn_rpk_same(x$report_ref,ref),request$eda_display_requests)
  brohn_require(length(found)<=1L,"An EDA source has conflicting saved window requests.")
  brohn_normalize_eda_display_request(if(length(found))found[[1L]]$display_request else NULL)
}
.brohn_rpk_eda_requirements_current <- function(store,intent) {
  actual<-.brohn_rpk_eda_requirements(store,intent$request$report_refs,brohn_report_source_admission(intent$request$renderer_profile))
  brohn_require(.brohn_rpk_same(actual,intent$source_requirements),"The required EDA sources changed. Review these choices and prepare a new version.")
  actual
}
.brohn_rpk_choice_section <- function(section) {
  s<-section$selector;d<-section$display
  brohn_require(is.list(s)&&brohn_text(s$scope,64)&&s$scope %in% c("all_exercises","exact_exercises"),"Choose all saved choice exercises or exact prepared exercises.")
  brohn_fields(s,if(s$scope=="all_exercises")"scope"else c("scope","keys"),label="Choice exercise selector")
  if(s$scope=="exact_exercises")brohn_require(brohn_array(s$keys)&&length(s$keys)>0L&&length(s$keys)<=20L&&
    all(vapply(s$keys,.brohn_rpk_hash,logical(1)))&&!anyDuplicated(unlist(s$keys)),"Choose distinct exact choice exercises.")
  brohn_fields(d,c("pages","page_numbers"),label="Choice numerical display")
  brohn_require(brohn_text(d$pages,16)&&d$pages %in% c("all","selected")&&brohn_array(d$page_numbers),"Choose all or selected numerical table pages.")
  if(d$pages=="selected")brohn_require(length(d$page_numbers)>0L&&length(d$page_numbers)<=2L&&
    all(vapply(d$page_numbers,brohn_number,logical(1),min=1,max=2,integer=TRUE))&&!anyDuplicated(unlist(d$page_numbers)),"Choose distinct available 50-row choice table pages.")
  else brohn_require(!length(d$page_numbers),"All choice table pages cannot also specify selected pages.")
  invisible(section)
}
.brohn_rpk_task_section <- function(section) {
  s<-section$selector;d<-section$display;people<-section$adapter=="task-people"
  all<-if(people)"all_metrics"else"all_administrations";exact<-if(people)"exact_metrics"else"exact_administrations";key<-if(people)"metrics"else"keys"
  brohn_require(is.list(s)&&brohn_text(s$scope,64)&&s$scope %in% c(all,exact),"Choose all saved task results or exact prepared results.")
  brohn_fields(s,if(s$scope==all)"scope"else c("scope",key),label="Task result selector")
  if(s$scope==exact)brohn_require(brohn_array(s[[key]])&&length(s[[key]])>0L&&length(s[[key]])<=10000L&&
    all(vapply(s[[key]],if(people)function(x)brohn_text(x,256)else .brohn_rpk_hash,logical(1)))&&!anyDuplicated(unlist(s[[key]])),"Choose distinct exact task results.")
  brohn_require(is.list(d)&&brohn_text(d$pages,16)&&d$pages %in% c("all","selected"),"Choose all or selected numerical table pages.")
  fields<-switch(section$adapter,"task-scores"="pages","task-trials"=c("measure","trial_scope","charts","pages"),"task-people"=c("charts","pages"))
  brohn_fields(d,fields,"page_numbers",label="Task report display")
  if(d$pages=="selected")brohn_require(brohn_array(d$page_numbers)&&length(d$page_numbers)>0L&&length(d$page_numbers)<=100L&&
    all(vapply(d$page_numbers,brohn_number,logical(1),min=1,max=2000,integer=TRUE))&&!anyDuplicated(unlist(d$page_numbers)),"Choose distinct 50-row task table pages.")
  else brohn_require(is.null(d$page_numbers)||(brohn_array(d$page_numbers)&&!length(d$page_numbers)),"All task table pages cannot also specify selected pages.")
  if(section$adapter=="task-trials"){
    brohn_require(brohn_text(d$measure,64)&&d$measure %in% c("profile_default","first_response_ms","final_correct_ms")&&
      brohn_text(d$trial_scope,16)&&d$trial_scope %in% c("all","scored"),"Choose recorded response latency and all or profile test/scoring positions.")
    brohn_require(identical(d$charts,"profile_default")||(brohn_array(d$charts)&&length(d$charts)>0L&&length(d$charts)<=3L&&
      all(vapply(d$charts,function(x)brohn_text(x,32)&&x %in% c("chronology","distribution","outcomes"),logical(1)))&&!anyDuplicated(unlist(d$charts))),"Choose compatible task charts or profile defaults.")
  }
  if(people)brohn_require(identical(d$charts,list("people")),"Task cohort figures show the original saved person values.")
  invisible(section)
}
.brohn_rpk_renderer_implementation_ref <- function() {
  x<-.brohn_rpk_implementation();list(profile=x$profile,hash=brohn_hash(x))
}
.brohn_rpk_execution_plan <- function(request=NULL) {
  if(.brohn_rpk_cardiac_profile(request))return(.brohn_rpcc_execution_plan(request))
  if(.brohn_rpk_eda_profile(request))return(list(schema=.brohn_rpk_eda_plan_schema(request),
    source_admission=brohn_report_source_admission(request$renderer_profile),
    explicit_distribution_implementation_ref=.brohn_rpk_distribution_implementation_ref("task-choice-findings/0.1"),
    task_display_implementation_ref=brohn_task_display_implementation_ref("saved-task-display/0.2"),
    choice_display_implementation_ref=brohn_choice_display_implementation_ref(),
    eda_display_implementation_ref=brohn_eda_display_implementation_ref(.brohn_rpk_eda_preparation_profile(request)),
    renderer_implementation_ref=.brohn_rpk_renderer_implementation_ref()))
  if(.brohn_rpk_choice_profile(request))return(list(schema="brohn-task-choice-report-execution-plan/0.1",
    source_admission=brohn_report_source_admission(request$renderer_profile),
    explicit_distribution_implementation_ref=.brohn_rpk_distribution_implementation_ref("task-choice-findings/0.1"),
    task_display_implementation_ref=brohn_task_display_implementation_ref("saved-task-display/0.2"),
    choice_display_implementation_ref=brohn_choice_display_implementation_ref(),
    renderer_implementation_ref=.brohn_rpk_renderer_implementation_ref()))
  list(schema="brohn-task-report-execution-plan/0.1",
  task_display_implementation_ref=brohn_task_display_implementation_ref(),
  explicit_distribution_implementation_ref=.brohn_rpk_distribution_implementation_ref(),
  renderer_implementation_ref=.brohn_rpk_renderer_implementation_ref())
}
.brohn_rpk_plan_valid <- function(plan,request=NULL) {
  if(isTRUE(plan$schema%in%c("brohn-cardiac-report-execution-plan/0.1","brohn-cardiac-report-execution-plan/0.2")))return(.brohn_rpcc_plan_valid(plan,request))
  eda<-isTRUE(plan$schema %in% c("brohn-eda-report-execution-plan/0.1","brohn-eda-report-execution-plan/0.2","brohn-eda-report-execution-plan/0.3"))
  choice<-eda||identical(plan$schema,"brohn-task-choice-report-execution-plan/0.1")
  fields<-c("schema","task_display_implementation_ref","explicit_distribution_implementation_ref","renderer_implementation_ref")
  brohn_fields(plan,c(fields,if(choice)c("source_admission","choice_display_implementation_ref"),if(eda)"eda_display_implementation_ref"),label="Pinned preparation plan")
  brohn_require(choice||identical(plan$schema,"brohn-task-report-execution-plan/0.1"),"Reopen a supported saved preparation plan.")
  if(!is.null(request))brohn_require(identical(choice,.brohn_rpk_choice_profile(request))&&identical(eda,.brohn_rpk_eda_profile(request))&&.brohn_rpk_prepared_profile(request),"The saved preparation plan belongs to a different renderer.")
  if(eda){
    spec<-.brohn_rpk_admission_spec(plan$source_admission)
    brohn_require(!isTRUE(spec$cardiac)&&!is.null(spec$eda_version)&&identical(plan$schema,spec$plan_schema)&&
      identical(plan$eda_display_implementation_ref$profile,spec$eda_preparation),"The saved EDA plan has incompatible source and preparation profiles.")
    if(!is.null(request))brohn_require(identical(plan$schema,.brohn_rpk_eda_plan_schema(request)),"The saved EDA plan belongs to a different renderer version.")
  }else if(choice)brohn_require(identical(plan$source_admission,"task-choice-findings/0.1"),"The saved plan changed its complete-source admission.")
  for(x in plan[setdiff(names(plan),c("schema","source_admission"))]){brohn_fields(x,c("profile","hash"),label="Pinned implementation");brohn_require(brohn_text(x$profile,128)&&.brohn_rpk_hash(x$hash),"The saved preparation lost its implementation identity.")}
  brohn_require(identical(plan$task_display_implementation_ref$profile,if(choice)"saved-task-display/0.2"else"saved-task-display/0.1")&&
    identical(plan$explicit_distribution_implementation_ref$profile,if(choice)"saved-explicit-distribution/0.2"else"saved-explicit-distribution/0.1")&&
    identical(plan$renderer_implementation_ref$profile,"static-complete-findings/0.1"),"The saved plan has incompatible implementation profiles.")
  if(choice)brohn_require(identical(plan$choice_display_implementation_ref$profile,"saved-choice-display/0.1"),"The saved choice implementation profile is unavailable.")
  invisible(plan)
}
.brohn_rpk_manifest_sources <- function(s) {
  if(.brohn_rpk_cardiac_profile(s))return(.brohn_rpcc_manifest_sources(s))
  if(!.brohn_rpk_prepared_profile(s))return(list(reports=s$report_refs,distributions=s$display_refs))
  refs<-function(adapter)lapply(Filter(function(x)x$adapter==adapter,s$prepared_sources),`[[`,"prepared_ref")
  result<-list(reports=s$report_refs,distributions=refs("explicit-distribution"),task_displays=refs("task-display"))
  if(.brohn_rpk_choice_profile(s))result$choice_displays<-refs("choice-display")
  if(.brohn_rpk_eda_profile(s)){
    result$eda_displays<-refs("eda-display")
    result$related_eda_sources<-s$related_eda_refs
    result$source_identity_graph_binding<-s$source_identity_graph_binding
  }
  result
}
.brohn_rpk_find_pinned_distribution <- function(store,report_ref,implementation_ref,source_admission="task-findings/0.1") {
  .brohn_rpk_ref_catalog(store,report_ref,"report")
  rows<-DBI::dbGetQuery(store$con,paste("SELECT v.id,v.revision,v.body_hash FROM entity_versions v JOIN entities e ON e.kind=v.kind AND e.id=v.id AND e.revision=v.revision",
    "WHERE v.kind='explicit_distributions' AND v.project_id=? AND json_extract(v.body_json,'$.request.report_id')=?",
    "AND json_extract(v.body_json,'$.request.report_revision')=? AND json_extract(v.body_json,'$.request.report_hash')=?",
    "AND json_extract(v.body_json,'$.preparation_implementation_ref.profile')=? AND json_extract(v.body_json,'$.preparation_implementation_ref.hash')=?",
    "ORDER BY e.updated_at DESC,e.id LIMIT 1"),params=list(report_ref$project_id,report_ref$id,report_ref$revision,report_ref$body_hash,implementation_ref$profile,implementation_ref$hash))
  if(!nrow(rows))return(NULL)
  ref<-list(kind="explicit_distributions",id=rows$id[[1L]],revision=rows$revision[[1L]],body_hash=rows$body_hash[[1L]],project_id=report_ref$project_id)
  m<-.brohn_rpk_distribution_metadata(store,ref);j<-brohn_get_job(store,m$processing$job_id)
  brohn_require(.brohn_rpk_same(m$report_ref,report_ref)&&.brohn_rpk_same(j$request$report_ref,report_ref)&&
    .brohn_rpk_same(j$request$preparation_implementation_ref,implementation_ref)&&
    identical(.brohn_rpk_distribution_admission(j$request),source_admission),"Saved response preparation no longer matches its pinned implementation or source admission.")
  ref
}
.brohn_rpk_prepared_sources <- function(deps) lapply(Filter(function(d)!is.null(d$result_ref),deps),function(d)list(
  adapter=switch(d$kind,task_display="task-display",choice_display="choice-display",eda_display="eda-display",cardiac_display="cardiac-display",explicit_distributions="explicit-distribution"),source_report_ref=d$report_ref,
  prepared_ref=d$result_ref,implementation_ref=d$implementation_ref))
.brohn_rpk_preparation_view <- function(deps,count=NULL,maximum=NULL,reason=NULL) list(
  prepared_sources=.brohn_rpk_prepared_sources(deps),resolved_panel_count=count,maximum_panels=maximum,reason_code=reason)
.brohn_rpk_preparation_failure <- function(deps,job,previous=NULL) {
  # A new attempt's ordinary error must not inherit an earlier typed refusal.
  result<-.brohn_rpk_preparation_view(deps,previous$resolved_panel_count,previous$maximum_panels)
  failure<-job$error
  if(is.list(failure)&&identical(failure$schema,"brohn-eda-report-refusal/0.1")){
    refusal<-failure[setdiff(names(failure),"source_preserved")]
    brohn_validate_eda_refusal(refusal)
    for(key in setdiff(names(refusal),"schema"))result[key]<-refusal[key]
  }
  result
}
.brohn_rpk_retain_dependencies <- function(updated,previous) {
  # An early refusal at one slot does not detach later owned/shared jobs.
  # Keep their references until the whole unchanged request can be reconciled.
  slots<-vapply(updated,`[[`,character(1),"slot")
  c(updated,Filter(function(d)!d$slot %in% slots,previous))
}
.brohn_rpk_task_catalog_all <- function(store,ref) {
  items<-list();cursor<-NULL
  repeat{
    page<-brohn_task_display_catalog(store,ref,cursor=cursor,limit=100L)
    items<-c(items,page$items);brohn_require(length(items)<=10000L,"This prepared task catalog exceeds the report selection profile.")
    cursor<-page$next_cursor;if(is.null(cursor))break
  };items
}
.brohn_rpk_choice_catalog_all <- function(store,ref) {
  items<-list();cursor<-NULL
  repeat{
    page<-brohn_choice_display_catalog(store,ref,cursor=cursor,limit=25L)
    items<-c(items,page$items);brohn_require(length(items)<=20L,"This prepared choice catalog exceeds the report selection profile.")
    cursor<-page$next_cursor;if(is.null(cursor))break
  };items
}
.brohn_rpk_eda_catalog_all <- function(store,ref) {
  items<-list();cursor<-NULL
  repeat{
    page<-brohn_eda_display_catalog(store,ref,cursor=cursor,limit=25L)
    items<-c(items,page$items);brohn_require(length(items)<=2000L,"This prepared EDA catalog exceeds the report selection profile.")
    cursor<-page$next_cursor;if(is.null(cursor))break
  };items
}
.brohn_rpk_task_dependency_specs <- function(store,request,plan,source_requirements=NULL) {
  if(.brohn_rpk_cardiac_profile(request))return(.brohn_rpcc_dependency_specs(store,request,plan,source_requirements))
  specs<-list()
  eda<-.brohn_rpk_eda_profile(request)
  if(eda){
    actual<-.brohn_rpk_eda_requirements(store,request$report_refs,plan$source_admission)
    if(!is.null(source_requirements))brohn_require(.brohn_rpk_same(actual,source_requirements),"Required EDA source membership differs from the saved preparation.")
    source_requirements<-actual
  }
  for(ref in request$report_refs){
    selected<-Filter(function(s).brohn_rpk_same(s$source_report_ref,ref),request$requested_sections)
    if(any(vapply(selected,function(s)s$adapter=="explicit-distribution",logical(1))))specs<-c(specs,list(list(kind="explicit_distributions",report_ref=ref,implementation_ref=plan$explicit_distribution_implementation_ref)))
    m<-.brohn_rpk_report_metadata(store,ref)
    task<-"task" %in% unlist(m$source_components)||m$kind %in% c("implicit","implicit_cohort")||(identical(m$kind,"questionnaire")&&m$task_score_count>0L)
    # Full task evidence is mandatory even when all of its figures are removed.
    if(task)specs<-c(specs,list(list(kind="task_display",report_ref=ref,implementation_ref=plan$task_display_implementation_ref)))
    if(.brohn_rpk_choice_profile(request)&&"choice" %in% unlist(m$source_components))
      specs<-c(specs,list(list(kind="choice_display",report_ref=ref,implementation_ref=plan$choice_display_implementation_ref)))
    if(eda&&any(vapply(source_requirements$required_eda_refs,function(r).brohn_rpk_same(r,ref),logical(1))))
      specs<-c(specs,list(list(kind="eda_display",report_ref=ref,display_request=.brohn_rpk_eda_request_for(request,ref),implementation_ref=plan$eda_display_implementation_ref)))
  }
  if(eda)for(related in source_requirements$related_eda_refs)specs<-c(specs,list(list(kind="eda_display",report_ref=related$report_ref,
    display_request=brohn_normalize_eda_display_request(),implementation_ref=plan$eda_display_implementation_ref)))
  lapply(specs,function(x){identity<-list(kind=x$kind,report_ref=x$report_ref)
    if(x$kind=="eda_display")identity$display_request<-x$display_request
    x$slot<-brohn_hash(identity);x})
}
.brohn_rpk_explicit_panel_count <- function(store,section) {
  ref<-section$source_ref
  rows<-DBI::dbGetQuery(store$con,paste("SELECT json_extract(j.value,'$.id') id,CASE WHEN json_extract(j.value,'$.quantitative')=1",
    "THEN coalesce(json_array_length(j.value,'$.bins'),0) ELSE coalesce(json_array_length(j.value,'$.categories'),0) END n",
    "FROM entity_versions v,json_each(v.body_json,'$.result.groups') j WHERE v.kind=? AND v.id=? AND v.revision=? AND v.project_id=? ORDER BY CAST(j.key AS INTEGER)"),
    params=list(ref$kind,ref$id,ref$revision,ref$project_id))
  brohn_require(nrow(rows)<=10000L,"The complete distribution catalog exceeds this report profile.")
  rows<-rows[match(unlist(section$resolved_group_ids),rows$id),,drop=FALSE]
  brohn_require(!anyNA(rows$id),"A frozen response group is unavailable.")
  sum(vapply(rows$n,function(n){
    if(section$display$pages=="all")return(ceiling(n/20L))
    brohn_require(all(vapply(section$display$offsets,function(x)x<=max(0,n-1L),logical(1))),"Choose actual saved distribution pages.")
    if(n==0L)0L else length(section$display$offsets)
  },numeric(1)))
}
.brohn_rpk_resolve_sections <- function(store,request,deps) {
  if(.brohn_rpk_cardiac_profile(request))return(.brohn_rpcc_resolve_sections(store,request,deps))
  sections<-list();known_panels<-0L;complete<-TRUE
  for(s in request$requested_sections){
    s$source_ref<-s$source_report_ref
    if(s$adapter %in% .brohn_rpk_task_adapters){
      d<-Filter(function(x)x$kind=="task_display"&&.brohn_rpk_same(x$report_ref,s$source_report_ref),deps)
      brohn_require(length(d)==1L&&!is.null(d[[1L]]$result_ref),"Task figures need their exact complete prepared source.")
      s$source_ref<-d[[1L]]$result_ref
      resolved<-brohn_resolve_task_report_section(s,.brohn_rpk_task_catalog_all(store,s$source_ref))
      s<-resolved$section;known_panels<-known_panels+resolved$panel_count
    }else if(s$adapter %in% .brohn_rpk_choice_adapters){
      d<-Filter(function(x)x$kind=="choice_display"&&.brohn_rpk_same(x$report_ref,s$source_report_ref),deps)
      brohn_require(.brohn_rpk_choice_profile(request)&&length(d)==1L&&!is.null(d[[1L]]$result_ref),"Choice figures need their exact complete prepared source.")
      s$source_ref<-d[[1L]]$result_ref
      resolved<-brohn_resolve_choice_report_section(s,.brohn_rpk_choice_catalog_all(store,s$source_ref))
      s<-resolved$section;known_panels<-known_panels+resolved$panel_count
    }else if(s$adapter %in% .brohn_rpk_eda_adapters){
      d<-Filter(function(x)x$kind=="eda_display"&&.brohn_rpk_same(x$report_ref,s$source_report_ref),deps)
      brohn_require(.brohn_rpk_eda_profile(request)&&length(d)==1L&&!is.null(d[[1L]]$result_ref),"EDA figures need their exact complete prepared source.")
      s$source_ref<-d[[1L]]$result_ref
      resolved<-brohn_resolve_eda_report_section(s,.brohn_rpk_eda_catalog_all(store,s$source_ref))
      s<-resolved$section;known_panels<-known_panels+resolved$panel_count
    }else if(s$adapter=="explicit-distribution"){
      d<-Filter(function(x)x$kind=="explicit_distributions"&&.brohn_rpk_same(x$report_ref,s$source_report_ref),deps)
      brohn_require(length(d)==1L&&!is.null(d[[1L]]$result_ref),"Response figures need their exact complete prepared source.")
      s$source_ref<-d[[1L]]$result_ref;s$resolved_group_ids<-.brohn_rpk_group_ids(store,s$source_ref,s$selector)
      known_panels<-known_panels+.brohn_rpk_explicit_panel_count(store,s)
    }else{
      # These source families can require complete paired-model verification.
      # The supervised worker performs the authoritative all-source preflight,
      # before any artifact is written. Metadata cannot stand in for that work.
      complete<-FALSE
    }
    sections<-c(sections,list(s))
  }
  list(sections=sections,panel_count=if(complete)known_panels else NULL,known_panel_count=known_panels)
}
.brohn_rpk_continue_task_intent <- function(store,intent_ref,action) {
  brohn_store_batch(store,function(){
    r<-.brohn_rpk_reconcile(store,.brohn_rpk_intent(store,intent_ref));b<-r$body
    if(b$status %in% c("succeeded","superseded","assembly_queued"))return(.brohn_rpk_intent_view(r))
    if(action=="advance")brohn_require(b$status %in% c("prepared","waiting_for_display","ready_to_freeze"),"This preparation needs an explicit Resume or Retry.")
    if(action=="resume")brohn_require(b$status=="needs_authority","Only an authorization pause can be resumed.")
    if(action=="retry")brohn_require(b$status %in% c("failed","cancelled","needs_attention"),"Only a stopped preparation can be retried.")
    .brohn_rpk_request(store,b$request);.brohn_rpk_plan_valid(b$execution_plan,b$request)
    if(.brohn_rpk_eda_profile(b$request)).brohn_rpk_eda_requirements_current(store,b)
    if(.brohn_rpk_cardiac_profile(b$request)).brohn_rpcc_requirements_current(store,b)
    if(!.brohn_rpk_same(b$execution_plan$renderer_implementation_ref,.brohn_rpk_renderer_implementation_ref())){
      b$status<-"needs_attention";b$reason<-"The report implementation changed since Prepare. Review your saved choices and prepare them as a new version; the original plan was preserved."
      b$preparation<-.brohn_rpk_preparation_view(b$dependencies,reason="implementation_changed")
      return(.brohn_rpk_intent_view(.brohn_rpk_put_intent(store,r,b)))
    }
    retrying<-action!="advance"
    if(retrying&&!is.null(b$selection_ref)){
      frozen<-.brohn_rpk_record(store,b$selection_ref,"report_package_selection")
      brohn_require(identical(frozen$body$intent_ref$id,r$id)&&frozen$body$generation==b$generation,"The retry no longer belongs to its original frozen contents.")
      if(.brohn_rpk_eda_profile(b$request))b$preparation<-.brohn_rpk_preparation_view(b$dependencies,b$preparation$resolved_panel_count,b$preparation$maximum_panels)
      b$status<-"ready_to_freeze";b$reason<-NULL;b$job_ref<-NULL;b$package_ref<-NULL;r<-.brohn_rpk_put_intent(store,r,b)
      job<-brohn_queue_report_package(store,b$selection_ref,retry=TRUE);b<-r$body;b$status<-"assembly_queued";b$job_ref<-list(id=job$id,status=job$status)
      return(.brohn_rpk_intent_view(.brohn_rpk_put_intent(store,r,b)))
    }
    deps<-list();waiting<-FALSE;admission<-.brohn_rpk_distribution_admission_for(b$request)
    for(spec in .brohn_rpk_task_dependency_specs(store,b$request,b$execution_plan,b$source_requirements)){
      task<-spec$kind=="task_display";choice<-spec$kind=="choice_display";eda<-spec$kind=="eda_display";cardiac<-spec$kind=="cardiac_display";ref<-spec$report_ref;impl<-spec$implementation_ref
      if(cardiac){
        prior<-Filter(function(d)identical(d$slot,spec$slot),b$dependencies)
        pending<-.brohn_rpcc_pending_dependency(store,spec,if(length(prior))prior[[1L]]else NULL)
        if(!is.null(pending)){deps<-c(deps,list(pending));waiting<-TRUE;next}
      }
      saved<-if(cardiac)brohn_find_cardiac_display(store,ref,spec$display_request,impl)else if(task)brohn_find_task_display(store,ref,impl$profile,impl)else if(choice)brohn_find_choice_display(store,ref,impl$profile,impl)else if(eda)brohn_find_eda_display(store,ref,spec$display_request,impl$profile,impl)else .brohn_rpk_find_pinned_distribution(store,ref,impl,admission)
      old<-Filter(function(d)identical(d$slot,spec$slot),b$dependencies);old<-if(length(old))old[[1L]]else NULL
      d<-c(spec,list(job_id=if(is.null(old))NULL else old$job_id,created_for_intent=if(is.null(old))FALSE else old$created_for_intent,result_ref=saved,status=if(is.null(saved))NULL else"succeeded"))
      if(!is.null(saved)){deps<-c(deps,list(d));next}
      current<-if(cardiac)brohn_cardiac_display_implementation_ref()else if(task)brohn_task_display_implementation_ref(impl$profile)else if(choice)brohn_choice_display_implementation_ref()else if(eda)brohn_eda_display_implementation_ref(impl$profile)else .brohn_rpk_distribution_implementation_ref(admission)
      if(!.brohn_rpk_same(impl,current)){
        b$status<-"needs_attention";b$dependencies<-.brohn_rpk_retain_dependencies(deps,b$dependencies);b$reason<-"A pinned display implementation is unavailable. Prepare these saved choices as a new version; no different code was substituted."
        b$preparation<-.brohn_rpk_preparation_view(b$dependencies,reason="implementation_changed")
        return(.brohn_rpk_intent_view(.brohn_rpk_put_intent(store,r,b)))
      }
      request<-if(cardiac).brohn_cdd_queue_request(store,ref,spec$display_request,impl)else if(task).brohn_task_display_request(store,ref,impl)else if(choice).brohn_choice_display_request(store,ref,impl)else if(eda).brohn_eda_display_request(store,ref,spec$display_request,impl,impl$profile)else .brohn_rpk_distribution_request(store,ref,impl,admission)
      fingerprint<-if(task||choice||eda||cardiac)request$content_fingerprint else brohn_hash(request[setdiff(names(request),"authority")])
      previous<-.brohn_rpk_latest_job(store,spec$kind,fingerprint)
      # A new intent may replace a cancelled prerequisite it never attached.
      # Attached cancellations and all failures still need explicit Retry.
      retry_dependency<-retrying||(is.null(old)&&!is.null(previous)&&identical(previous$status,"cancelled"))
      j<-if(cardiac)brohn_queue_cardiac_display(store,ref,spec$display_request,retry=retry_dependency,implementation_ref=impl)else if(task)brohn_queue_task_display(store,ref,retry=retry_dependency,implementation_ref=impl)else if(choice)brohn_queue_choice_display(store,ref,retry=retry_dependency,implementation_ref=impl)else if(eda)brohn_queue_eda_display(store,ref,spec$display_request,retry=retry_dependency,implementation_ref=impl,preparation_profile=impl$profile)else brohn_queue_explicit_distributions_ref(store,ref,retry=retry_dependency,implementation_ref=impl,source_admission=admission)
      d$job_id<-j$id;d$status<-j$status;d$created_for_intent<-if(!is.null(old)&&identical(old$job_id,j$id))isTRUE(old$created_for_intent)else is.null(previous)||!identical(previous$id,j$id)
      deps<-c(deps,list(d))
      if(j$status %in% c("failed","cancelled")){
        b$status<-j$status;b$dependencies<-.brohn_rpk_retain_dependencies(deps,b$dependencies);b$reason<-.brohn_rpk_job_error(j,"Saved display preparation stopped. Review the source and explicitly retry.")
        b$preparation<-if(.brohn_rpk_eda_profile(b$request)).brohn_rpk_preparation_failure(b$dependencies,j)else .brohn_rpk_preparation_view(b$dependencies)
        return(.brohn_rpk_intent_view(.brohn_rpk_put_intent(store,r,b)))
      }
      brohn_require(j$status %in% c("queued","running"),"A successful display job has no retained complete result.");waiting<-TRUE
    }
    b$dependencies<-deps;b$reason<-NULL;b$preparation<-.brohn_rpk_preparation_view(deps)
    if(waiting){b$status<-"waiting_for_display";return(.brohn_rpk_intent_view(.brohn_rpk_put_intent(store,r,b)))}
    resolved<-tryCatch(.brohn_rpk_resolve_sections(store,b$request,deps),error=function(e)e)
    if(inherits(resolved,"error")){
      b$status<-"needs_attention";b$reason<-substr(conditionMessage(resolved),1L,2000L)
      b$preparation<-.brohn_rpk_preparation_view(deps,reason="selection_review")
      return(.brohn_rpk_intent_view(.brohn_rpk_put_intent(store,r,b)))
    }
    maximum<-.brohn_rpk_limits(b$request)$max_panels
    b$preparation<-.brohn_rpk_preparation_view(deps,resolved$panel_count,maximum)
    if(!is.null(resolved$panel_count)&&resolved$panel_count>maximum){
      b$status<-"needs_attention";b$reason<-paste("These choices contain",resolved$panel_count,"figures; this profile supports",maximum,". Change the figure choices; all complete numerical evidence stays included.")
      b$preparation$reason_code<-"panel_limit"
      return(.brohn_rpk_intent_view(.brohn_rpk_put_intent(store,r,b)))
    }
    if(retrying)b$generation<-b$generation+1L
    b$status<-"ready_to_freeze";b$job_ref<-NULL;b$package_ref<-NULL;b$selection_ref<-NULL;r<-.brohn_rpk_put_intent(store,r,b)
    id<-brohn_id("report-selection")
    selection<-c(list(schema=if(.brohn_rpk_eda_profile(b$request))"brohn-report-package-selection/0.3"else"brohn-report-package-selection/0.2",id=id,intent_ref=.brohn_rpk_ref(r),generation=b$generation),
      b$request[c("study_id","project_id","title","report_refs")],list(prepared_sources=.brohn_rpk_prepared_sources(deps),sections=resolved$sections),
      b$request[c("contents_policy","limits_profile","renderer_profile")],list(frozen_at=brohn_now(),coverage=list(
        full_platform_scope=list(capabilities=50L,packages=17L),profile_supported_adapters=as.list(c("gaze-context","explicit-distribution","paired-findings",.brohn_rpk_task_adapters,if(.brohn_rpk_choice_profile(b$request)).brohn_rpk_choice_adapters,if(.brohn_rpk_eda_profile(b$request)).brohn_rpk_eda_adapters)),
        numerical_evidence="complete_selected_reports",raw_recordings="excluded_by_profile",original_raw_bytes_reverified=FALSE)))
    if(.brohn_rpk_eda_profile(b$request)){
      selection$eda_display_requests<-b$request$eda_display_requests
      selection$related_eda_refs<-b$source_requirements$related_eda_refs
      selection$source_identity_graph_binding<-b$source_requirements$source_identity_graph_binding
      selection$coverage$numerical_evidence<-"complete_selected_reports_and_related_eda"
      selection$coverage$raw_conductance<-"original_bounded_previews_retained_complete_raw_series_excluded"
    }
    if(.brohn_rpk_cardiac_profile(b$request))selection<-.brohn_rpcc_freeze(selection,b$request,b$source_requirements)
    saved<-brohn_put_entity(store,"report_package_selection",id,selection,0L,r$project_id);b<-r$body;b$selection_ref<-.brohn_rpk_ref(saved)
    r<-.brohn_rpk_put_intent(store,r,b);job<-brohn_queue_report_package(store,b$selection_ref,retry=FALSE)
    b<-r$body;b$status<-"assembly_queued";b$job_ref<-list(id=job$id,status=job$status)
    .brohn_rpk_intent_view(.brohn_rpk_put_intent(store,r,b))
  })
}
.brohn_rpk_publish_eda_refusal <- function(store,result,job,input,selection,source_guards,output_guard) {
  brohn_validate_eda_refusal(result)
  if(!is.null(result$source)){
    refs<-c(selection$report_refs,lapply(selection$related_eda_refs,`[[`,"report_ref"))
    brohn_require(any(vapply(refs,function(ref).brohn_rpk_same(ref,result$source),logical(1))),"This preparation refusal refers to an unrelated source.")
  }
  brohn_store_batch(store,function(){
    current<-.brohn_rpk_selection_sources(store,selection)
    brohn_require(identical(brohn_hash(current),input$source_binding),"Source authority changed before the refusal could be retained.")
    .brohn_cm_guard_check(c(source_guards,list(output_guard)));brohn_report_package_job_fence(store,job)
    r<-.brohn_rpk_selection_live(store,input$selection_ref,job)$intent;b<-r$body
    b$status<-"needs_attention";b$reason<-result$message;b$job_ref<-list(id=job$id,status="failed")
    b$preparation<-.brohn_rpk_preparation_failure(b$dependencies,list(error=result))
    .brohn_rpk_put_intent(store,r,b)
    brohn_fail_job(store,job$id,job$worker,job$token,c(result,list(source_preserved=TRUE)))
  })
}
.brohn_rpk_publish_panel_refusal <- function(store,result,job,input,selection,source_guards,output_guard) {
  brohn_fields(result,c("schema","reason_code","resolved_panel_count","maximum_panels"),"section_counts",label="Complete report preflight refusal")
  brohn_require(identical(result$schema,"brohn-report-package-refusal/0.1")&&identical(result$reason_code,"panel_limit")&&
    brohn_number(result$resolved_panel_count,1,1e9,TRUE)&&brohn_number(result$maximum_panels,1,1e9,TRUE)&&result$maximum_panels==input$limits$max_panels&&
    result$resolved_panel_count>result$maximum_panels,"The report preflight refusal does not match its frozen profile.")
  if(!is.null(result$section_counts)){
    brohn_require(brohn_array(result$section_counts)&&length(result$section_counts)==length(selection$sections),"The report preflight omitted a requested section.")
    ids<-vapply(selection$sections,`[[`,character(1),"id")
    for(x in result$section_counts){brohn_fields(x,c("section_id","panel_count"),label="Section preflight count")
      brohn_require(brohn_valid_id(x$section_id)&&x$section_id %in% ids&&brohn_number(x$panel_count,0,1e9,TRUE),"The report preflight has a foreign section or invalid count.")}
    brohn_require(!anyDuplicated(vapply(result$section_counts,`[[`,character(1),"section_id"))&&
      sum(vapply(result$section_counts,`[[`,numeric(1),"panel_count"))==result$resolved_panel_count,"The report preflight counts are inconsistent.")
  }
  message<-paste("These choices contain",result$resolved_panel_count,"figures; this profile supports",result$maximum_panels,
    ". Change the figure choices; completed preparation and complete numerical evidence are preserved.")
  brohn_store_batch(store,function(){
    current<-.brohn_rpk_selection_sources(store,selection)
    brohn_require(identical(brohn_hash(current),input$source_binding),"Source authority changed before the report preflight could be retained.")
    .brohn_cm_guard_check(c(source_guards,list(output_guard)));brohn_report_package_job_fence(store,job)
    r<-.brohn_rpk_selection_live(store,input$selection_ref,job)$intent;b<-r$body
    b$status<-"needs_attention";b$reason<-message;b$job_ref<-list(id=job$id,status="failed")
    b$preparation<-.brohn_rpk_preparation_view(b$dependencies,result$resolved_panel_count,result$maximum_panels,"panel_limit")
    .brohn_rpk_put_intent(store,r,b)
    brohn_fail_job(store,job$id,job$worker,job$token,list(message=message,reason_code="panel_limit",source_preserved=TRUE,
      resolved_panel_count=result$resolved_panel_count,maximum_panels=result$maximum_panels,selection_ref=input$selection_ref))
  })
}
