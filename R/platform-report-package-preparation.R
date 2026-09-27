# Task-capable preparation keeps the original complete-findings lifecycle.
# Only bounded metadata is resolved here. Source replay/full decoding belongs
# to supervised prerequisites; saved scientific scores are never recomputed.
.brohn_rpk_task_profile <- function(x) identical(x$renderer_profile,"controlled-gaze-explicit-task-paired/0.1")
.brohn_rpk_limits <- function(x) if(.brohn_rpk_task_profile(x))brohn_report_package_task_limits()else brohn_report_package_limits()
.brohn_rpk_task_adapters <- c("task-scores","task-trials","task-people")
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
.brohn_rpk_execution_plan <- function() list(schema="brohn-task-report-execution-plan/0.1",
  task_display_implementation_ref=brohn_task_display_implementation_ref(),
  explicit_distribution_implementation_ref=.brohn_rpk_distribution_implementation_ref(),
  renderer_implementation_ref=.brohn_rpk_renderer_implementation_ref())
.brohn_rpk_plan_valid <- function(plan) {
  brohn_fields(plan,c("schema","task_display_implementation_ref","explicit_distribution_implementation_ref","renderer_implementation_ref"),label="Pinned preparation plan")
  brohn_require(identical(plan$schema,"brohn-task-report-execution-plan/0.1"),"Reopen a supported saved preparation plan.")
  for(x in plan[setdiff(names(plan),"schema")]){brohn_fields(x,c("profile","hash"),label="Pinned implementation");brohn_require(brohn_text(x$profile,128)&&.brohn_rpk_hash(x$hash),"The saved preparation lost its implementation identity.")}
  invisible(plan)
}
.brohn_rpk_manifest_sources <- function(s) {
  if(!.brohn_rpk_task_profile(s))return(list(reports=s$report_refs,distributions=s$display_refs))
  refs<-function(adapter)lapply(Filter(function(x)x$adapter==adapter,s$prepared_sources),`[[`,"prepared_ref")
  list(reports=s$report_refs,distributions=refs("explicit-distribution"),task_displays=refs("task-display"))
}
.brohn_rpk_find_pinned_distribution <- function(store,report_ref,implementation_ref) {
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
    .brohn_rpk_same(j$request$preparation_implementation_ref,implementation_ref),"Saved response preparation no longer matches its pinned implementation.")
  ref
}
.brohn_rpk_prepared_sources <- function(deps) lapply(Filter(function(d)!is.null(d$result_ref),deps),function(d)list(
  adapter=if(d$kind=="task_display")"task-display"else"explicit-distribution",source_report_ref=d$report_ref,
  prepared_ref=d$result_ref,implementation_ref=d$implementation_ref))
.brohn_rpk_preparation_view <- function(deps,count=NULL,maximum=NULL,reason=NULL) list(
  prepared_sources=.brohn_rpk_prepared_sources(deps),resolved_panel_count=count,maximum_panels=maximum,reason_code=reason)
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
.brohn_rpk_task_dependency_specs <- function(store,request,plan) {
  specs<-list()
  for(ref in request$report_refs){
    selected<-Filter(function(s).brohn_rpk_same(s$source_report_ref,ref),request$requested_sections)
    if(any(vapply(selected,function(s)s$adapter=="explicit-distribution",logical(1))))specs<-c(specs,list(list(kind="explicit_distributions",report_ref=ref,implementation_ref=plan$explicit_distribution_implementation_ref)))
    m<-.brohn_rpk_report_metadata(store,ref)
    task<-m$kind %in% c("implicit","implicit_cohort")||(identical(m$kind,"questionnaire")&&m$task_score_count>0L)
    # Full task evidence is mandatory even when all of its figures are removed.
    if(task)specs<-c(specs,list(list(kind="task_display",report_ref=ref,implementation_ref=plan$task_display_implementation_ref)))
  }
  lapply(specs,function(x){x$slot<-brohn_hash(list(kind=x$kind,report_ref=x$report_ref));x})
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
  sections<-list();known_panels<-0L;complete<-TRUE
  for(s in request$requested_sections){
    s$source_ref<-s$source_report_ref
    if(s$adapter %in% .brohn_rpk_task_adapters){
      d<-Filter(function(x)x$kind=="task_display"&&.brohn_rpk_same(x$report_ref,s$source_report_ref),deps)
      brohn_require(length(d)==1L&&!is.null(d[[1L]]$result_ref),"Task figures need their exact complete prepared source.")
      s$source_ref<-d[[1L]]$result_ref
      resolved<-brohn_resolve_task_report_section(s,.brohn_rpk_task_catalog_all(store,s$source_ref))
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
    .brohn_rpk_request(store,b$request);.brohn_rpk_plan_valid(b$execution_plan)
    if(!.brohn_rpk_same(b$execution_plan$renderer_implementation_ref,.brohn_rpk_renderer_implementation_ref())){
      b$status<-"needs_attention";b$reason<-"The report implementation changed since Prepare. Review your saved choices and prepare them as a new version; the original plan was preserved."
      b$preparation<-.brohn_rpk_preparation_view(b$dependencies,reason="implementation_changed")
      return(.brohn_rpk_intent_view(.brohn_rpk_put_intent(store,r,b)))
    }
    retrying<-action!="advance"
    if(retrying&&!is.null(b$selection_ref)){
      frozen<-.brohn_rpk_record(store,b$selection_ref,"report_package_selection")
      brohn_require(identical(frozen$body$intent_ref$id,r$id)&&frozen$body$generation==b$generation,"The retry no longer belongs to its original frozen contents.")
      b$status<-"ready_to_freeze";b$reason<-NULL;b$job_ref<-NULL;b$package_ref<-NULL;r<-.brohn_rpk_put_intent(store,r,b)
      job<-brohn_queue_report_package(store,b$selection_ref,retry=TRUE);b<-r$body;b$status<-"assembly_queued";b$job_ref<-list(id=job$id,status=job$status)
      return(.brohn_rpk_intent_view(.brohn_rpk_put_intent(store,r,b)))
    }
    deps<-list();waiting<-FALSE
    for(spec in .brohn_rpk_task_dependency_specs(store,b$request,b$execution_plan)){
      task<-spec$kind=="task_display";ref<-spec$report_ref;impl<-spec$implementation_ref
      saved<-if(task)brohn_find_task_display(store,ref,impl$profile,impl)else .brohn_rpk_find_pinned_distribution(store,ref,impl)
      old<-Filter(function(d)identical(d$slot,spec$slot),b$dependencies);old<-if(length(old))old[[1L]]else NULL
      d<-c(spec,list(job_id=if(is.null(old))NULL else old$job_id,created_for_intent=if(is.null(old))FALSE else old$created_for_intent,result_ref=saved,status=if(is.null(saved))NULL else"succeeded"))
      if(!is.null(saved)){deps<-c(deps,list(d));next}
      current<-if(task)brohn_task_display_implementation_ref()else .brohn_rpk_distribution_implementation_ref()
      if(!.brohn_rpk_same(impl,current)){
        b$status<-"needs_attention";b$dependencies<-.brohn_rpk_retain_dependencies(deps,b$dependencies);b$reason<-"A pinned display implementation is unavailable. Prepare these saved choices as a new version; no different code was substituted."
        b$preparation<-.brohn_rpk_preparation_view(b$dependencies,reason="implementation_changed")
        return(.brohn_rpk_intent_view(.brohn_rpk_put_intent(store,r,b)))
      }
      request<-if(task).brohn_task_display_request(store,ref,impl)else .brohn_rpk_distribution_request(store,ref,impl)
      fingerprint<-if(task)request$content_fingerprint else brohn_hash(request[setdiff(names(request),"authority")])
      previous<-.brohn_rpk_latest_job(store,spec$kind,fingerprint)
      j<-if(task)brohn_queue_task_display(store,ref,retry=retrying,implementation_ref=impl)else brohn_queue_explicit_distributions_ref(store,ref,retry=retrying,implementation_ref=impl)
      d$job_id<-j$id;d$status<-j$status;d$created_for_intent<-if(!is.null(old)&&identical(old$job_id,j$id))isTRUE(old$created_for_intent)else is.null(previous)||!identical(previous$id,j$id)
      deps<-c(deps,list(d))
      if(j$status %in% c("failed","cancelled")){
        b$status<-j$status;b$dependencies<-.brohn_rpk_retain_dependencies(deps,b$dependencies);b$reason<-.brohn_rpk_job_error(j,"Saved display preparation stopped. Review the source and explicitly retry.")
        b$preparation<-.brohn_rpk_preparation_view(b$dependencies)
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
    maximum<-brohn_report_package_task_limits()$max_panels
    b$preparation<-.brohn_rpk_preparation_view(deps,resolved$panel_count,maximum)
    if(!is.null(resolved$panel_count)&&resolved$panel_count>maximum){
      b$status<-"needs_attention";b$reason<-paste("These choices contain",resolved$panel_count,"figures; this profile supports",maximum,". Change the figure choices; all complete numerical evidence stays included.")
      b$preparation$reason_code<-"panel_limit"
      return(.brohn_rpk_intent_view(.brohn_rpk_put_intent(store,r,b)))
    }
    if(retrying)b$generation<-b$generation+1L
    b$status<-"ready_to_freeze";b$job_ref<-NULL;b$package_ref<-NULL;b$selection_ref<-NULL;r<-.brohn_rpk_put_intent(store,r,b)
    id<-brohn_id("report-selection")
    selection<-c(list(schema="brohn-report-package-selection/0.2",id=id,intent_ref=.brohn_rpk_ref(r),generation=b$generation),
      b$request[c("study_id","project_id","title","report_refs")],list(prepared_sources=.brohn_rpk_prepared_sources(deps),sections=resolved$sections),
      b$request[c("contents_policy","limits_profile","renderer_profile")],list(frozen_at=brohn_now(),coverage=list(
        full_platform_scope=list(capabilities=50L,packages=17L),profile_supported_adapters=as.list(c("gaze-context","explicit-distribution","paired-findings",.brohn_rpk_task_adapters)),
        numerical_evidence="complete_selected_reports",raw_recordings="excluded_by_profile",original_raw_bytes_reverified=FALSE)))
    saved<-brohn_put_entity(store,"report_package_selection",id,selection,0L,r$project_id);b<-r$body;b$selection_ref<-.brohn_rpk_ref(saved)
    r<-.brohn_rpk_put_intent(store,r,b);job<-brohn_queue_report_package(store,b$selection_ref,retry=FALSE)
    b<-r$body;b$status<-"assembly_queued";b$job_ref<-list(id=job$id,status=job$status)
    .brohn_rpk_intent_view(.brohn_rpk_put_intent(store,r,b))
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
