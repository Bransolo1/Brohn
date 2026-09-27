# Durable report preparation. New files are externally qualified before any
# operation or researcher UI is registered in the application.
.brohn_rpk_intent_schema <- "brohn-report-package-intent/0.1"
.brohn_rpk_selection_schema <- "brohn-report-package-selection/0.1"
.brohn_rpk_intent_states <- c("prepared","waiting_for_display","ready_to_freeze","assembly_queued","succeeded",
  "needs_authority","needs_attention","failed","cancelled","superseded")
.brohn_rpk_active_states <- c("prepared","waiting_for_display","ready_to_freeze","assembly_queued","needs_authority","needs_attention","failed")
.brohn_rpk_contents <- function(policy) {
  brohn_fields(policy,c("profile","audience","identifier_mode","stimulus_images","complete_selected_numerical_evidence",
    "include_original_evidence","include_raw_recordings"),label="Complete report contents")
  brohn_require(identical(policy$profile,"complete-findings/0.1"),"Original byte evidence is not enabled in this package version. Choose complete findings with full numerical evidence.")
  brohn_require(identical(policy$audience,"research_team")&&policy$identifier_mode %in% c("package_aliases","source_identifiers")&&
    policy$stimulus_images %in% c("included","excluded_by_choice")&&isTRUE(policy$complete_selected_numerical_evidence)&&
    identical(policy$include_original_evidence,FALSE)&&identical(policy$include_raw_recordings,FALSE),"Choose the supported complete-findings contents profile.")
  invisible(policy)
}
.brohn_rpk_section <- function(section,refs) {
  brohn_fields(section,c("id","adapter","adapter_version","source_report_ref","selector","display","order"),label="Report section")
  brohn_require(brohn_valid_id(section$id)&&section$adapter %in% c("gaze-context","explicit-distribution","paired-findings","task-scores","task-trials","task-people","choice-counts","choice-utilities","eda-events","eda-continuous")&&
    identical(section$adapter_version,"0.1")&&brohn_number(section$order,1,100,TRUE),"Choose a supported ordered report section.")
  .brohn_rpk_ref_valid(section$source_report_ref,"report")
  brohn_require(any(vapply(refs,function(r).brohn_rpk_same(r,section$source_report_ref),logical(1))),"A section must belong to an exact selected report.")
  if(section$adapter %in% c("task-scores","task-trials","task-people"))return(.brohn_rpk_task_section(section))
  if(section$adapter %in% c("choice-counts","choice-utilities"))return(.brohn_rpk_choice_section(section))
  if(section$adapter %in% c("eda-events","eda-continuous"))return(.brohn_rpk_eda_section(section))
  s<-section$selector;d<-section$display
  if(section$adapter=="gaze-context") {
    brohn_require(is.list(s)&&s$scope %in% c("all_exposures","exact_exposure"),"Choose all gaze exposures or an exact exposure.")
    brohn_fields(s,if(s$scope=="all_exposures")"scope"else c("scope","exposure_key"),label="Gaze section selector")
    if(s$scope=="exact_exposure")brohn_require(.brohn_rpk_hash(s$exposure_key),"Choose an exact saved gaze exposure key.")
    brohn_fields(d,"candidate_limit",label="Gaze display")
    brohn_require(brohn_number(d$candidate_limit,1,1000,TRUE),"Choose a gaze diagram limit from 1 to 1,000 candidates.")
  }else if(section$adapter=="explicit-distribution") {
    brohn_require(is.list(s)&&s$scope %in% c("all_groups","exact_item_condition"),"Choose saved response groups.")
    brohn_fields(s,if(s$scope=="all_groups")"scope"else c("scope","family","item_id","condition_id"),label="Response section selector")
    if(s$scope=="exact_item_condition")brohn_require(s$family %in% c("question","scale")&&brohn_text(s$item_id,1024)&&
      (is.null(s$condition_id)||brohn_text(s$condition_id,1024)),"Choose an exact saved item and condition.")
    brohn_require(is.list(d)&&d$pages %in% c("all","selected"),"Choose all or selected response figure pages.")
    brohn_fields(d,if(d$pages=="all")"pages"else c("pages","offsets"),label="Response display")
    if(d$pages=="selected")brohn_require(brohn_array(d$offsets)&&length(d$offsets)>0L&&length(d$offsets)<=100L&&
      all(vapply(d$offsets,function(n)brohn_number(n,0,10000,TRUE)&&n%%20==0,logical(1)))&&!anyDuplicated(unlist(d$offsets)),"Choose distinct 20-row response figure offsets.")
  }else{
    brohn_require(is.list(s)&&s$scope %in% c("all_comparisons","exact_comparison"),"Choose saved paired comparisons.")
    brohn_fields(s,if(s$scope=="all_comparisons")"scope"else c("scope","comparison_id","contrast_hash"),label="Paired section selector")
    if(s$scope=="exact_comparison")brohn_require(brohn_text(s$comparison_id,128)&&.brohn_rpk_hash(s$contrast_hash),"Choose an exact saved contrast and hash.")
    brohn_require(is.list(d)&&d$pages %in% c("all","selected"),"Choose all or selected paired figure pages.")
    brohn_fields(d,if(d$pages=="all")c("charts","pages")else c("charts","pages","page_numbers"),label="Paired display")
    brohn_require(brohn_array(d$charts)&&length(d$charts)>0L&&length(d$charts)<=2L&&
      all(vapply(d$charts,function(x)is.character(x)&&length(x)==1L&&x %in% c("means","differences"),logical(1)))&&!anyDuplicated(unlist(d$charts)),"Choose distinct saved paired chart types.")
    if(d$pages=="selected")brohn_require(brohn_array(d$page_numbers)&&length(d$page_numbers)>0L&&length(d$page_numbers)<=100L&&
      all(vapply(d$page_numbers,brohn_number,logical(1),min=1,max=2000,integer=TRUE))&&!anyDuplicated(unlist(d$page_numbers)),"Choose distinct paired figure pages.")
  }
  invisible(section)
}
.brohn_rpk_request <- function(store,request) {
  brohn_fields(request,c("schema","study_id","project_id","title","report_refs","requested_sections","contents_policy","limits_profile","renderer_profile",if(.brohn_rpk_eda_profile(request))"eda_display_requests"),label="Saved report preparation")
  brohn_require(identical(request$schema,"brohn-report-package-intent-request/0.1")&&brohn_text(request$title,500)&&
    ((identical(request$limits_profile,"controlled-report-package/0.1")&&identical(request$renderer_profile,"controlled-gaze-explicit-paired/0.1"))||
     (identical(request$limits_profile,"controlled-task-report-package/0.1")&&identical(request$renderer_profile,"controlled-gaze-explicit-task-paired/0.1"))||
     (identical(request$limits_profile,"controlled-task-choice-report-package/0.1")&&identical(request$renderer_profile,"controlled-gaze-explicit-task-choice-paired/0.1"))||
     (identical(request$limits_profile,"controlled-task-choice-eda-report-package/0.1")&&.brohn_rpk_eda_profile(request))),"Use the supported complete-findings preparation profile.")
  .brohn_rpk_study(store,request$study_id,request$project_id);.brohn_rpk_contents(request$contents_policy)
  refs<-request$report_refs
  brohn_require(brohn_array(refs)&&length(refs)>=1L&&length(refs)<=8L,"Select one to eight exact saved reports.")
  for(ref in refs){.brohn_rpk_ref_valid(ref,"report");brohn_require(identical(ref$project_id,request$project_id),"All selected reports must belong to this project.")
    m<-.brohn_rpk_report_metadata(store,ref);brohn_require(identical(m$study_id,request$study_id),"All selected reports must belong to this study.")
    if(!.brohn_rpk_prepared_profile(request))brohn_require(!m$kind %in% c("implicit","implicit_cohort")&&m$task_score_count==0L,
      "Complete task evidence requires the task-capable report profile, even when task figures are hidden.")
    if(!.brohn_rpk_choice_profile(request))brohn_require(!"choice" %in% unlist(m$source_components)&&!identical(m$kind,"explicit_choice")&&
      (is.null(m$choice_task_count)||m$choice_task_count==0L),"Complete choice evidence requires the choice-capable report profile, even when choice figures are hidden.")
    if(!.brohn_rpk_eda_profile(request))brohn_require(is.null(m$eda_source_family)&&!identical(m$kind,"eda")&&!"eda" %in% unlist(m$source_components),
      "Complete EDA evidence requires the EDA-capable report profile, even when its figures are hidden.")
  }
  if(.brohn_rpk_eda_profile(request)){
    brohn_require(.brohn_rpk_same(request$eda_display_requests,.brohn_rpk_normalize_eda_requests(request$eda_display_requests,refs)),"Normalize and retain the exact EDA window choices before saving.")
    for(x in request$eda_display_requests){m<-.brohn_rpk_report_metadata(store,x$report_ref)
      brohn_require(identical(m$eda_source_family,"continuous"),"Display time windows apply only to a selected saved continuous EDA source.")}
  }
  brohn_require(!anyDuplicated(vapply(refs,brohn_hash,character(1))),"Select each exact saved report once.")
  sections<-request$requested_sections
  brohn_require(brohn_array(sections)&&length(sections)>=(if(.brohn_rpk_eda_profile(request))0L else 1L)&&length(sections)<=100L,
    "Choose up to 100 supported report sections; earlier profiles require at least one.")
  for(s in sections).brohn_rpk_section(s,refs)
  if(!.brohn_rpk_prepared_profile(request))brohn_require(!any(vapply(sections,function(s)s$adapter %in% c("task-scores","task-trials","task-people"),logical(1))),"Task findings require the task-capable report profile.")
  if(!.brohn_rpk_choice_profile(request))brohn_require(!any(vapply(sections,function(s)s$adapter %in% c("choice-counts","choice-utilities"),logical(1))),"Choice findings require the choice-capable report profile.")
  if(!.brohn_rpk_eda_profile(request))brohn_require(!any(vapply(sections,function(s)s$adapter %in% c("eda-events","eda-continuous"),logical(1))),"EDA findings require the EDA-capable report profile.")
  brohn_require(!anyDuplicated(vapply(sections,`[[`,character(1),"id"))&&!anyDuplicated(vapply(sections,`[[`,numeric(1),"order")),"Report section identities and order must be unique.")
  brohn_require(nchar(brohn_json(request),type="bytes")<=256*1024,"This report preparation exceeds its bounded metadata profile.")
  invisible(request)
}
.brohn_rpk_intent <- function(store,ref,current=TRUE) {
  r<-.brohn_rpk_record(store,ref,"report_package_intent")
  brohn_require(identical(r$body$schema,.brohn_rpk_intent_schema)&&identical(r$body$id,r$id)&&r$body$status %in% .brohn_rpk_intent_states,
    "This saved report preparation is unavailable.")
  if(current){head<-brohn_get_entity(store,r$kind,r$id);brohn_require(head$revision==r$revision,"This preparation changed. Reopen its current state.")}
  .brohn_rpk_study(store,r$body$request$study_id,r$project_id);r
}
.brohn_rpk_intent_view <- function(record) {
  b<-record$body
  action<-switch(b$status,prepared="continue",waiting_for_display="continue",ready_to_freeze="continue",assembly_queued="wait",
    succeeded="download",needs_authority="resume",needs_attention="review",failed="retry",cancelled="retry",superseded="none")
  list(intent_ref=.brohn_rpk_ref(record),status=b$status,request=b$request,dependencies=b$dependencies,
    selection_ref=b$selection_ref,job_ref=b$job_ref,package_ref=b$package_ref,next_action=action,reason=b$reason,
    preparation=b$preparation)
}
brohn_read_report_package_intent <- function(store,intent_id,project_id) {
  brohn_report_package_queue_authority(store,"report_package",project_id)
  row<-DBI::dbGetQuery(store$con,paste("SELECT e.revision,v.body_hash FROM entities e JOIN entity_versions v ON v.kind=e.kind AND v.id=e.id AND v.revision=e.revision",
    "WHERE e.kind='report_package_intent' AND e.id=? AND e.project_id=?"),params=list(intent_id,project_id))
  brohn_require(nrow(row)==1L,"This saved preparation is unavailable in this project.")
  .brohn_rpk_intent_view(.brohn_rpk_reconcile(store,.brohn_rpk_intent(store,list(kind="report_package_intent",id=intent_id,revision=row$revision[[1L]],body_hash=row$body_hash[[1L]],project_id=project_id))))
}
brohn_save_report_package_intent <- function(store,command_id,request,expected_revision=NULL,prior_intent_ref=NULL) {
  brohn_require(brohn_text(command_id,256),"Retain this preparation command identity for retry.")
  if(.brohn_rpk_eda_profile(request)){
    request$eda_display_requests<-.brohn_rpk_normalize_eda_requests(request$eda_display_requests,request$report_refs)
    request$requested_sections<-lapply(request$requested_sections,function(s)
      if(s$adapter %in% c("eda-events","eda-continuous")) .brohn_rpk_eda_section(s) else s)
  }
  .brohn_rpk_request(store,request)
  if(!is.null(prior_intent_ref)){.brohn_rpk_ref_valid(prior_intent_ref,"report_package_intent")
    brohn_require(identical(prior_intent_ref$project_id,request$project_id)&&
      (is.null(expected_revision)||expected_revision==prior_intent_ref$revision),"Edit the exact prior preparation revision.")
  }else brohn_require(is.null(expected_revision),"An edit revision requires its prior preparation reference.")
  fingerprint<-brohn_hash(list(request=request,prior_intent_ref=prior_intent_ref))
  id<-paste0("report-intent-",substr(brohn_hash(list(project_id=request$project_id,command_id=command_id)),1,40))
  brohn_store_batch(store,function(){
    old<-brohn_get_entity(store,"report_package_intent",id)
    if(!is.null(old)){brohn_require(identical(old$project_id,request$project_id)&&identical(old$body$command_fingerprint,fingerprint),"This preparation command already belongs to different contents.")
      return(.brohn_rpk_intent_view(old))}
    generation<-1L
    if(!is.null(prior_intent_ref)){
      prior<-.brohn_rpk_intent(store,prior_intent_ref);generation<-prior$body$generation+1L
      if(prior$body$status %in% .brohn_rpk_active_states){b<-prior$body;b$status<-"superseded";b$reason<-"A new preparation preserves your edited contents.";b$superseded_by<-id
        brohn_put_entity(store,prior$kind,prior$id,b,prior$revision,prior$project_id)}
    }
    body<-list(schema=.brohn_rpk_intent_schema,id=id,generation=generation,status="prepared",request=request,
      command_id=command_id,command_fingerprint=fingerprint,prior_intent_ref=prior_intent_ref,dependencies=list(),
      selection_ref=NULL,job_ref=NULL,package_ref=NULL,reason=NULL,superseded_by=NULL,created_at=brohn_now())
    if(.brohn_rpk_eda_profile(request))body$source_requirements<-.brohn_rpk_eda_requirements(store,request$report_refs,brohn_report_source_admission(request$renderer_profile))
    if(.brohn_rpk_prepared_profile(request)){body$execution_plan<-.brohn_rpk_execution_plan(request);body["preparation"]<-list(NULL)}
    .brohn_rpk_intent_view(brohn_put_entity(store,"report_package_intent",id,body,0L,request$project_id))
  })
}
brohn_report_package_catalog <- function(store,study_id,project_id,cursor=NULL,limit=25L) {
  .brohn_rpk_study(store,study_id,project_id);brohn_require(brohn_number(limit,1,100,TRUE),"Choose a history page of 1 to 100 items.")
  scope<-brohn_hash(list("report_package_history",study_id,project_id));cursor<-.brohn_rpk_cursor(cursor,scope)
  sql<-paste("SELECT e.id,e.revision,e.updated_at,v.body_hash,json_extract(v.body_json,'$.status') AS status,",
    "json_extract(v.body_json,'$.request.title') AS title,json_extract(v.body_json,'$.package_ref') AS package_ref,",
    "json_extract(v.body_json,'$.reason') AS reason FROM entities e JOIN entity_versions v ON v.kind=e.kind AND v.id=e.id AND v.revision=e.revision",
    "WHERE e.kind='report_package_intent' AND e.project_id=? AND json_extract(v.body_json,'$.request.study_id')=?")
  params<-list(project_id,study_id)
  if(!is.null(cursor)){sql<-paste(sql,"AND (e.updated_at<? OR (e.updated_at=? AND e.id>?))");params<-c(params,list(cursor$updated_at,cursor$updated_at,cursor$id))}
  rows<-DBI::dbGetQuery(store$con,paste(sql,"ORDER BY e.updated_at DESC,e.id ASC LIMIT ?"),params=c(params,list(limit+1L)))
  more<-nrow(rows)>limit;rows<-head(rows,limit)
  items<-lapply(seq_len(nrow(rows)),function(i)list(intent_ref=list(kind="report_package_intent",id=rows$id[[i]],revision=rows$revision[[i]],body_hash=rows$body_hash[[i]],project_id=project_id),
    status=rows$status[[i]],title=rows$title[[i]],updated_at=rows$updated_at[[i]],package_ref=.brohn_rpk_parse_optional(rows$package_ref[[i]]),reason=if(is.na(rows$reason[[i]]))NULL else rows$reason[[i]]))
  list(items=items,cursor=cursor,next_cursor=if(more)list(scope=scope,updated_at=tail(rows$updated_at,1),id=tail(rows$id,1))else NULL)
}

# Loaded identities are captured once; queueing does not hash source files or
# launch Python. The execution boundary rechecks every pinned implementation.
.brohn_rpk_files <- c("R/platform-report-package.R","R/platform-report-package-sources.R","R/platform-report-package-authority.R",
  "R/platform-report-package-preparation.R","R/platform-report-package-tasks.R","R/platform-task-display.R","R/platform-task-display-sources.R",
  "R/platform-report-package-choice.R","R/platform-choice-display.R","R/platform-choice-display-sources.R","R/platform-load.R",
  "R/platform-eda-display.R","R/platform-eda-display-sources.R","R/platform-eda-continuous-review.R","R/platform-report-package-eda.R","R/platform-report-package-eda-figures.R",
  "scripts/workers/eda_display.py","scripts/workers/report_package_eda.py","scripts/workers/eda_review.py","scripts/workers/eda_continuous_review.py","scripts/workers/physiology_artifacts.py",
  "R/platform-report-package-distributions.R","R/platform-report-package-render.R","R/platform-report-package-tables.R",
  "scripts/workers/report_package_archive.py","scripts/workers/report_package_raster.py","R/platform-jobs.R","scripts/analysis-worker.R",
  "R/platform-explicit-distributions.R","R/platform-explicit-distribution-views.R","R/platform-gaze-report-views.R",
  "R/platform-paired-plots.R","R/platform-paired-plot-views.R","R/platform-questionnaire-artifacts.R","R/platform-questionnaire-index.R",
  "R/platform-core.R","R/platform-analysis-plan.R","R/platform-camera-analysis.R","R/platform-capture.R","R/platform-delivery.R",
  "R/platform-facial-expression.R","R/platform-maxdiff.R","R/platform-maxdiff-platform.R","R/platform-maxdiff-import.R","R/platform-maxdiff-plots.R","R/platform-participant-equipment.R","R/platform-question-materials.R",
  "R/platform-question-revision.R","R/platform-question-sections.R","R/platform-questionnaire-artifact-storage.R",
  "R/platform-scale-comparisons.R","R/platform-scales.R","R/platform-store.R","R/platform-welcome.R",
  "R/platform-library.R","R/platform-task-cohort-storage.R","R/platform-questionnaire-explorer.R","R/platform-hosted-profile.R",
  "R/platform-publication.R","R/platform-signal-values.R","R/platform-clock-map.R","R/platform-run-evidence.R","R/platform-task-evidence.R",
  "R/platform-task-plots.R","R/platform-task-plot-views.R","R/platform-task-import.R","R/platform-gnat-import.R","scripts/readiness/report-package-runtime.json")
.brohn_rpk_loaded <- setNames(lapply(.brohn_rpk_files,function(p)digest::digest(file=p,algo="sha256")),.brohn_rpk_files)
.brohn_rpk_runtime <- brohn_read_json_file("scripts/readiness/report-package-runtime.json",maximum=8192)
brohn_require(identical(.brohn_rpk_runtime$schema,"brohn-report-package-runtime-profile/0.1")&&
  identical(.brohn_rpk_runtime$runtime$Python$implementation,"CPython")&&brohn_text(.brohn_rpk_runtime$runtime$Python$version,64)&&
  brohn_text(.brohn_rpk_runtime$runtime$Pillow,64),"The report assembly runtime profile is unavailable.")
.brohn_rpk_check_code <- function(hashes) {
  brohn_require(.brohn_rpk_same(hashes,.brohn_rpk_loaded)&&all(vapply(names(hashes),function(p)identical(digest::digest(file=p,algo="sha256"),hashes[[p]]),logical(1))),"The saved-report implementation changed. Start a new preparation with the current installation.")
  invisible(TRUE)
}
.brohn_rpk_implementation <- function() list(schema="brohn-report-package-implementation/0.1",profile="static-complete-findings/0.1",
  sources=.brohn_rpk_loaded,runtime=c(list(R=as.character(getRversion()),jsonlite=as.character(utils::packageVersion("jsonlite")),htmltools=as.character(utils::packageVersion("htmltools")),
    packages=setNames(lapply(c("shiny","base64enc","digest","DBI","RSQLite","processx"),function(p)as.character(utils::packageVersion(p))),c("shiny","base64enc","digest","DBI","RSQLite","processx")),
    required_profile=.brohn_rpk_runtime$profile,required_runtime=.brohn_rpk_runtime$runtime),.brohn_rpk_runtime$runtime),
  archive_python=brohn_python_profile("eeg"),archive_script=normalizePath("scripts/workers/report_package_archive.py",winslash="/",mustWork=TRUE),
  raster_script=normalizePath("scripts/workers/report_package_raster.py",winslash="/",mustWork=TRUE))
.brohn_rpk_runtime_check <- function(implementation,scratch) {
  output<-file.path(scratch,"runtime.json");error<-file.path(scratch,"runtime.err")
  script<-paste0("import json,platform,PIL;print(json.dumps({'Python':{'implementation':platform.python_implementation(),'version':platform.python_version()},'Pillow':PIL.__version__}))")
  result<-processx::run(implementation$archive_python,c("-B","-c",script),stdout=output,stderr=error,timeout=15,error_on_status=FALSE,cleanup_tree=TRUE,windows_hide_window=TRUE)
  brohn_require(result$status==0L&&file.exists(output)&&file.info(output)$size<=8192&&file.exists(error)&&file.info(error)$size<=8192,
    "This installation could not verify the qualified report assembly runtime.")
  observed<-brohn_read_json_file(output,maximum=8192)
  brohn_require(.brohn_rpk_same(observed,implementation$runtime$required_runtime)&&
    .brohn_rpk_same(observed$Python,implementation$runtime$Python)&&identical(observed$Pillow,implementation$runtime$Pillow),
    "Report assembly requires the declared qualified CPython and Pillow versions. Prepare the supported runtime before retrying.")
  invisible(observed)
}
.brohn_rpk_put_intent <- function(store,record,body) {
  if(.brohn_rpk_same(record$body,body))return(record)
  brohn_put_entity(store,record$kind,record$id,body,record$revision,record$project_id)
}
.brohn_rpk_job_error <- function(job,fallback) {
  value<-job$error
  if(is.list(value))value<-value$message
  if(is.character(value)&&length(value)==1L&&!is.na(value)&&nzchar(value))substr(value,1L,2000L)else fallback
}
.brohn_rpk_reconcile <- function(store,record) {
  b<-record$body
  if(b$status=="assembly_queued"&&!is.null(b$job_ref)){
    j<-brohn_get_job(store,b$job_ref$id)
    if(is.null(j)||j$status %in% c("failed","cancelled")){
      b$status<-if(!is.null(j)&&j$status=="cancelled")"cancelled"else"failed"
      b$reason<-if(is.null(j))"The saved preparation job is unavailable."else .brohn_rpk_job_error(j,"Preparation stopped. Review the saved sources and explicitly retry.")
      b$job_ref<-if(is.null(j))b$job_ref else list(id=j$id,status=j$status)
      if(.brohn_rpk_eda_profile(b$request)&&!is.null(j))b$preparation<-.brohn_rpk_preparation_failure(b$dependencies,j,b$preparation)
      record<-.brohn_rpk_put_intent(store,record,b)
    }
  };record
}
.brohn_rpk_dependency_users <- function(store,job_id,except_id) {
  DBI::dbGetQuery(store$con,paste("SELECT count(*) n FROM entities e JOIN entity_versions v ON e.kind=v.kind AND e.id=v.id AND e.revision=v.revision,",
    "json_each(v.body_json,'$.dependencies') d WHERE e.kind='report_package_intent' AND e.id<>?",
    "AND json_extract(v.body_json,'$.status') IN ('prepared','waiting_for_display','ready_to_freeze','assembly_queued','needs_authority','needs_attention','failed')",
    "AND json_extract(d.value,'$.job_id')=?"),params=list(except_id,job_id))$n[[1L]]
}
brohn_cancel_report_package_intent <- function(store,intent_ref) {
  brohn_store_batch(store,function(){r<-.brohn_rpk_intent(store,intent_ref);b<-r$body
    if(b$status %in% c("cancelled","superseded","succeeded"))return(.brohn_rpk_intent_view(r))
    b$status<-"cancelled";b$reason<-"Preparation cancelled. Earlier saved packages remain available."
    r<-.brohn_rpk_put_intent(store,r,b)
    for(d in b$dependencies)if(isTRUE(d$created_for_intent)&&!is.null(d$job_id)&&.brohn_rpk_dependency_users(store,d$job_id,r$id)==0L){j<-brohn_get_job(store,d$job_id);if(!is.null(j)&&j$status %in% c("queued","running"))brohn_cancel_job(store,j$id)}
    if(!is.null(b$job_ref)){j<-brohn_get_job(store,b$job_ref$id);if(!is.null(j)&&j$status %in% c("queued","running"))brohn_cancel_job(store,j$id)}
    .brohn_rpk_intent_view(r)
  })
}
.brohn_rpk_group_ids <- function(store,ref,selector) {
  .brohn_rpk_distribution_metadata(store,ref)
  rows<-DBI::dbGetQuery(store$con,paste("SELECT json_extract(j.value,'$.id') id,json_extract(j.value,'$.family') family,json_extract(j.value,'$.item_id') item_id,json_extract(j.value,'$.condition_id') condition_id",
    "FROM entity_versions v,json_each(v.body_json,'$.result.groups') j WHERE v.kind=? AND v.id=? AND v.revision=? AND v.project_id=? ORDER BY CAST(j.key AS INTEGER)"),params=list(ref$kind,ref$id,ref$revision,ref$project_id))
  brohn_require(nrow(rows)<=10000L,"This saved explicit report has too many groups for one package.")
  if(selector$scope=="exact_item_condition"){
    condition<-if(is.null(selector$condition_id))is.na(rows$condition_id)else !is.na(rows$condition_id)&rows$condition_id==selector$condition_id
    rows<-rows[rows$family==selector$family&rows$item_id==selector$item_id&condition,,drop=FALSE]
    brohn_require(nrow(rows)==1L,"The chosen explicit item and condition are not exactly one saved group.")
  };as.list(rows$id)
}
.brohn_rpk_selection_live <- function(store,selection_ref,job=NULL) {
  selection<-.brohn_rpk_record(store,selection_ref,"report_package_selection")
  s<-selection$body;intent<-brohn_get_entity(store,"report_package_intent",s$intent_ref$id)
  brohn_require(!is.null(intent)&&identical(intent$project_id,selection_ref$project_id)&&intent$body$generation==s$generation&&
    intent$body$status %in% c("ready_to_freeze","assembly_queued")&&.brohn_rpk_same(intent$body$selection_ref,selection_ref),"This preparation was cancelled, superseded or replaced before it could publish.")
  if(!is.null(job))brohn_require(identical(intent$body$job_ref$id,job$id),"A newer assembly attempt owns this preparation.")
  list(selection=selection,intent=intent)
}
brohn_queue_report_package <- function(store,selection_ref,retry=FALSE) {
  authority<-brohn_report_package_queue_authority(store,"report_package",selection_ref$project_id)
  live<-.brohn_rpk_selection_live(store,selection_ref);s<-live$selection$body
  .brohn_rpk_selection_sources(store,s)
  if(.brohn_rpk_prepared_profile(s))brohn_require(.brohn_rpk_same(live$intent$body$execution_plan$renderer_implementation_ref,
    .brohn_rpk_renderer_implementation_ref()),"The pinned report renderer changed. Prepare these choices as a new version.")
  r<-list(schema="brohn-report-package-job/0.1",project_id=selection_ref$project_id,selection_ref=selection_ref,
    implementation=.brohn_rpk_implementation(),limits=.brohn_rpk_limits(s),authority=authority)
  r$content_fingerprint<-brohn_hash(r[setdiff(names(r),"authority")])
  brohn_enqueue_job(store,"report_package",r,paste0("report-package:",r$content_fingerprint,if(isTRUE(retry))paste0(":",brohn_id("retry"))else""))
}
brohn_continue_report_package_intent <- function(store,intent_ref,action="advance") {
  brohn_require(action %in% c("advance","resume","retry"),"Choose Continue, Resume or Retry explicitly.")
  original<-.brohn_rpk_intent(store,intent_ref)
  if(.brohn_rpk_prepared_profile(original$body$request))return(.brohn_rpk_continue_task_intent(store,intent_ref,action))
  brohn_store_batch(store,function(){
    r<-.brohn_rpk_intent(store,intent_ref);r<-.brohn_rpk_reconcile(store,r);b<-r$body
    if(b$status %in% c("succeeded","superseded","assembly_queued"))return(.brohn_rpk_intent_view(r))
    if(action=="advance")brohn_require(b$status %in% c("prepared","waiting_for_display","ready_to_freeze"),"This preparation needs an explicit Resume or Retry.")
    if(action=="resume")brohn_require(b$status=="needs_authority","Only an authorization pause can be resumed.")
    if(action=="retry")brohn_require(b$status %in% c("failed","cancelled","needs_attention"),"Only a stopped preparation can be retried.")
    .brohn_rpk_request(store,b$request)
    retrying<-action!="advance";deps<-list();waiting<-FALSE
    if(retrying&&!is.null(b$selection_ref)){
      # Explicit assembly retries preserve the exact frozen content. Only a new
      # edited intent may choose newer sources or another display prerequisite.
      frozen<-.brohn_rpk_record(store,b$selection_ref,"report_package_selection")
      brohn_require(identical(frozen$body$intent_ref$id,r$id)&&frozen$body$generation==b$generation,"The retry no longer belongs to its original frozen contents.")
      b$status<-"ready_to_freeze";b$reason<-NULL;b$job_ref<-NULL;b$package_ref<-NULL;r<-.brohn_rpk_put_intent(store,r,b)
      job<-brohn_queue_report_package(store,b$selection_ref,retry=TRUE);b<-r$body;b$status<-"assembly_queued";b$job_ref<-list(id=job$id,status=job$status)
      return(.brohn_rpk_intent_view(.brohn_rpk_put_intent(store,r,b)))
    }
    explicit<-Filter(function(s)s$adapter=="explicit-distribution",b$request$requested_sections)
    unique_refs<-list();for(section in explicit)unique_refs[[brohn_hash(section$source_report_ref)]]<-section$source_report_ref
    for(key in names(unique_refs)){
      ref<-unique_refs[[key]];saved<-.brohn_rpk_find_distribution(store,ref)
      old<-Filter(function(d)identical(d$slot,key),b$dependencies);old<-if(length(old))old[[1L]]else NULL
      if(!is.null(saved)){deps[[length(deps)+1L]]<-list(slot=key,report_ref=ref,job_id=if(is.null(old))NULL else old$job_id,created_for_intent=if(is.null(old))FALSE else old$created_for_intent,result_ref=saved);next}
      before<-.brohn_rpk_distribution_request(store,ref);fingerprint<-brohn_hash(before[setdiff(names(before),"authority")]);existing<-.brohn_rpk_latest_job(store,"explicit_distributions",fingerprint)
      j<-brohn_queue_explicit_distributions_ref(store,ref,retry=retrying)
      created<-if(!is.null(old)&&identical(old$job_id,j$id))isTRUE(old$created_for_intent)else is.null(existing)||!identical(existing$id,j$id)
      deps[[length(deps)+1L]]<-list(slot=key,report_ref=ref,job_id=j$id,created_for_intent=created,result_ref=NULL)
      if(j$status %in% c("failed","cancelled")){b$status<-"failed";b$dependencies<-deps;b$reason<-.brohn_rpk_job_error(j,"The saved distribution prerequisite stopped. Explicitly retry when ready.");return(.brohn_rpk_intent_view(.brohn_rpk_put_intent(store,r,b)))}
      brohn_require(j$status %in% c("queued","running"),"A successful distribution job has no retained complete result.");waiting<-TRUE
    }
    b$dependencies<-deps;b$reason<-NULL
    if(waiting){b$status<-"waiting_for_display";return(.brohn_rpk_intent_view(.brohn_rpk_put_intent(store,r,b)))}
    display_refs<-lapply(deps,`[[`,"result_ref")
    sections<-lapply(b$request$requested_sections,function(section){
      section$source_ref<-section$source_report_ref
      if(section$adapter=="explicit-distribution"){
        d<-Filter(function(d).brohn_rpk_same(d$report_ref,section$source_report_ref),deps)[[1L]];section$source_ref<-d$result_ref
        section$resolved_group_ids<-.brohn_rpk_group_ids(store,d$result_ref,section$selector)
      };section
    })
    # A prerequisite retry has not yet frozen content. Once frozen, retries use
    # the branch above and never replace those exact source/display references.
    if(retrying)b$generation<-b$generation+1L
    b$status<-"ready_to_freeze";b$job_ref<-NULL;b$package_ref<-NULL;b$selection_ref<-NULL;r<-.brohn_rpk_put_intent(store,r,b)
    id<-brohn_id("report-selection")
    selection<-c(list(schema="brohn-report-package-selection/0.1",id=id,intent_ref=.brohn_rpk_ref(r),generation=b$generation),
      b$request[c("study_id","project_id","title","report_refs")],list(display_refs=display_refs,sections=sections),
      b$request[c("contents_policy","limits_profile","renderer_profile")],list(frozen_at=brohn_now(),coverage=list(
        full_platform_scope=list(capabilities=50L,packages=17L),profile_supported_adapters=as.list(c("gaze-context","explicit-distribution","paired-findings")),
        numerical_evidence="complete_selected_reports",raw_recordings="excluded_by_profile",original_raw_bytes_reverified=FALSE)))
    saved<-brohn_put_entity(store,"report_package_selection",id,selection,0L,r$project_id);b<-r$body;b$selection_ref<-.brohn_rpk_ref(saved)
    r<-.brohn_rpk_put_intent(store,r,b);job<-brohn_queue_report_package(store,b$selection_ref,retry=FALSE)
    b<-r$body;b$status<-"assembly_queued";b$job_ref<-list(id=job$id,status=job$status)
    .brohn_rpk_intent_view(.brohn_rpk_put_intent(store,r,b))
  })
}
brohn_report_package_input <- function(store,job,verify=FALSE) {
  store<-brohn_report_package_job_authorize(store,job);r<-job$request
  brohn_fields(r,c("schema","project_id","selection_ref","implementation","limits","authority","content_fingerprint"),label="Saved report package job")
  brohn_require(identical(job$operation,"report_package")&&identical(r$schema,"brohn-report-package-job/0.1")&&
    .brohn_rpk_same(r$implementation,.brohn_rpk_implementation()),"The package implementation or profile changed.")
  live<-.brohn_rpk_selection_live(store,r$selection_ref,job)
  brohn_require(.brohn_rpk_same(r$limits,.brohn_rpk_limits(live$selection$body)),"The package limits profile changed.")
  list(schema="brohn-analysis-input/1.0",operation="report_package",project_id=r$project_id,selection_ref=r$selection_ref,
    content_fingerprint=r$content_fingerprint,implementation=r$implementation,limits=r$limits)
}
brohn_prepare_report_package_execution <- function(store,job,input,scratch,pulse=NULL) {
  .brohn_rpk_source_pulse(pulse)
  store<-brohn_report_package_job_authorize(store,job);brohn_require(.brohn_rpk_same(input,brohn_report_package_input(store,job,FALSE)),"The package input changed before assembly.")
  .brohn_rpk_source_pulse(pulse)
  .brohn_rpk_check_code(job$request$implementation$sources);s<-.brohn_rpk_selection_live(store,input$selection_ref,job)$selection$body
  .brohn_rpk_runtime_check(input$implementation,scratch)
  .brohn_rpk_source_pulse(pulse)
  m<-.brohn_rpk_selection_sources(store,s);handle<-.brohn_rpk_hold_sources(store,m,pulse=pulse);ok<-FALSE
  on.exit(if(!ok).brohn_rpk_release(handle),add=TRUE)
  sources<-.brohn_rpk_complete_sources(store,handle,pulse=pulse)
  # Historical renderer inputs keep their original closed schema. The shared
  # reader's empty task collection is applicable only to the task profile.
  if(!.brohn_rpk_prepared_profile(s))sources$task_displays<-NULL
  if(!.brohn_rpk_choice_profile(s))sources$choice_displays<-NULL
  if(!.brohn_rpk_eda_profile(s))for(field in c("eda_displays","related_eda_sources","source_identity_graph"))sources[[field]]<-NULL
  bundle<-c(list(schema="brohn-report-package-render-input/0.1",selection=s),sources,list(implementation=input$implementation,limits=input$limits))
  path<-file.path(scratch,"report-package-bundle.json");brohn_require(!file.exists(path),"The assembly scratch bundle already exists.")
  if(.brohn_rpk_eda_profile(s))brohn_eda_write_json_file(bundle,path,maximum=input$limits$max_model_bytes)
  else brohn_write_json_file(bundle,path,maximum=input$limits$max_model_bytes)
  .brohn_rpk_source_pulse(pulse)
  seal<-.brohn_qexplorer_hold(path,file.info(path)$size);state<-handle$state;state$extra_guards<-list(seal)
  input$bundle<-list(schema=bundle$schema,path=normalizePath(path,winslash="/",mustWork=TRUE),sha256=digest::digest(file=path,algo="sha256"),bytes=as.numeric(file.info(path)$size),max_bytes=input$limits$max_model_bytes)
  input$source_binding<-brohn_hash(m)
  .brohn_rpk_source_pulse(pulse)
  brohn_report_package_sources_current(store,handle);brohn_report_package_job_authorize(store,job);ok<-TRUE;list(input=input,handle=handle)
}
brohn_analyse_report_package <- function(input,scratch) {
  brohn_fields(input$bundle,c("schema","path","sha256","bytes","max_bytes"),label="Sealed complete report bundle")
  b<-input$bundle
  brohn_require(identical(input$operation,"report_package")&&identical(b$schema,"brohn-report-package-render-input/0.1")&&
    brohn_number(b$max_bytes,1,128*1024^2,TRUE)&&brohn_number(b$bytes,1,b$max_bytes,TRUE)&&file.exists(b$path)&&file.info(b$path)$size==b$bytes&&
    identical(digest::digest(file=b$path,algo="sha256"),b$sha256),"The sealed report bundle is unavailable or changed.")
  root<-normalizePath(scratch,winslash="/",mustWork=TRUE);path<-normalizePath(b$path,winslash="/",mustWork=TRUE)
  brohn_require(identical(dirname(path),root)&&identical(basename(path),"report-package-bundle.json"),"The report bundle is outside this worker's owned scratch.")
  bundle<-if(identical(input$limits$profile,"controlled-task-choice-eda-report-package/0.1"))
    brohn_eda_read_json_file(path,maximum=b$max_bytes)else brohn_read_json_file(path,maximum=b$max_bytes)
  brohn_require(.brohn_rpk_same(bundle$implementation,input$implementation)&&.brohn_rpk_same(bundle$limits,input$limits)&&identical(brohn_hash(bundle$selection),input$selection_ref$body_hash),"The bundle differs from its frozen selection or implementation.")
  list(report_package=brohn_render_report_package(bundle,file.path(scratch,"artifacts")))
}
brohn_publish_report_package <- function(store,output,scratch,job,input,output_path,pulse=NULL) {
  .brohn_rpk_source_pulse(pulse)
  store<-brohn_report_package_job_authorize(store,job,"publish");.brohn_publication_job(store,job)
  .brohn_publication_output_identity(output,.brohn_rpk_loaded)
  base<-input[setdiff(names(input),c("bundle","source_binding"))]
  brohn_require(.brohn_rpk_same(base,brohn_report_package_input(store,job,FALSE)),"The package no longer matches its queued input.")
  .brohn_rpk_source_pulse(pulse)
  live<-.brohn_rpk_selection_live(store,input$selection_ref,job);s<-live$selection$body
  m<-.brohn_rpk_selection_sources(store,s)
  brohn_require(identical(brohn_hash(m),input$source_binding),"Source authority changed since the complete evidence was prepared.")
  .brohn_rpk_source_pulse(pulse)
  source_guards<-brohn_hold_signal_value_sources(store,list(source_objects=lapply(m$objects,function(o)o[c("hash","bytes")])))
  on.exit(for(g in source_guards).brohn_qexplorer_release(g),add=TRUE)
  output_guard<-.brohn_qexplorer_hold(output_path,file.info(output_path)$size);on.exit(.brohn_qexplorer_release(output_guard),add=TRUE)
  brohn_require(.brohn_rpk_same(brohn_read_json_file(output_path),output),"The worker output changed before publication.")
  .brohn_rpk_source_pulse(pulse)
  result<-output$report$report_package
  if(.brohn_rpk_eda_profile(s)&&identical(result$schema,"brohn-eda-report-refusal/0.1"))
    return(.brohn_rpk_publish_eda_refusal(store,result,job,input,s,source_guards,output_guard))
  if(.brohn_rpk_prepared_profile(s)&&identical(result$schema,"brohn-report-package-refusal/0.1"))
    return(.brohn_rpk_publish_panel_refusal(store,result,job,input,s,source_guards,output_guard))
  brohn_fields(result,c("schema","profile","manifest","files","coverage"),label="Complete report package result")
  brohn_require(identical(result$schema,"brohn-report-package-render-result/0.1")&&identical(result$profile,"complete-findings/0.1")&&
    brohn_array(result$files)&&length(result$files)>=3L&&length(result$files)<=input$limits$max_members&&
    .brohn_rpk_same(result$manifest$selection,s[setdiff(names(s),c("intent_ref","generation"))])&&
    .brohn_rpk_same(result$manifest$sources,.brohn_rpk_manifest_sources(s))&&
    .brohn_rpk_same(result$manifest$coverage,result$coverage),"Package results changed their frozen complete contents.")
  files<-result$files;names<-vapply(files,`[[`,character(1),"path")
  brohn_require(!anyDuplicated(names)&&all(c("report.html","manifest.json","report.brohn-report.zip") %in% names),"Required package artifacts are missing or duplicated.")
  for(f in files){.brohn_rpk_source_pulse(pulse);brohn_fields(f,c("path","sha256","bytes","media_type","role"),label="Generated package member")
    brohn_require(brohn_text(f$path,180)&&grepl("^[a-z0-9][a-z0-9._/-]*$",f$path)&&!any(strsplit(f$path,"/",fixed=TRUE)[[1L]] %in% c("",".",".."))&&
      .brohn_rpk_hash(f$sha256)&&brohn_number(f$bytes,0,512*1024^2,TRUE)&&brohn_text(f$media_type,128)&&brohn_text(f$role,128),"A generated package member has an invalid bounded descriptor.")}
  payloads<-files[!names %in% c("manifest.json","report.brohn-report.zip")]
  brohn_require(.brohn_rpk_same(payloads,result$manifest$files)&&sum(vapply(payloads,`[[`,numeric(1),"bytes"))<=input$limits$max_payload_bytes,"The portable inventory omits or changes a complete payload.")
  keys<-c(html="report.html",zip="report.brohn-report.zip",manifest="manifest.json")
  selected<-lapply(keys,function(name)files[[match(name,names)]])
  specs<-lapply(names(keys),function(key){f<-selected[[key]];list(key=key,kind="report-package",path=normalizePath(file.path(scratch,"artifacts",f$path),winslash="/",mustWork=TRUE),sha256=f$sha256,bytes=f$bytes,media_type=f$media_type)})
  .brohn_rpk_source_pulse(pulse)
  staged<-.brohn_publication_stage(store,job,specs);committed<-FALSE;on.exit(brohn_close_publication(staged$guard,committed),add=TRUE)
  manifest<-brohn_read_json_file(staged$paths[["manifest"]],maximum=4*1024^2)
  brohn_require(.brohn_rpk_same(manifest,result$manifest),"The sealed manifest bytes differ from the worker's exact package result.")
  id<-paste0("report-package-",sub("^job[_-]","",job$id))
  artifacts<-setNames(lapply(names(keys),function(key){d<-Filter(function(d)identical(d$key,key),staged$descriptors)[[1L]];c(list(file=keys[[key]]),d[c("hash","size","media_type")])}),names(keys))
  body<-list(schema="brohn-saved-report-package/0.1",id=id,study_id=s$study_id,title=s$title,selection_ref=input$selection_ref,
    profile=result$profile,coverage=result$coverage,manifest=result$manifest,artifacts=artifacts,created_at=brohn_now(),
    processing=list(job_id=job$id,attempt=job$attempt,content_fingerprint=input$content_fingerprint,code_hashes=output$code_identity,publication=.brohn_publication_processing(staged)))
  document<-.brohn_publication_stage_json(store,job,body,file.path(scratch,"published-report-package.json"));on.exit(brohn_close_publication(document$guard,committed),add=TRUE)
  .brohn_rpk_source_pulse(pulse)
  receipt<-brohn_store_batch(store,function(){
    current<-.brohn_rpk_selection_sources(store,s)
    brohn_require(identical(brohn_hash(current),input$source_binding),"Sources or permission changed before atomic package publication.")
    .brohn_cm_guard_check(c(source_guards,list(output_guard)));brohn_report_package_job_fence(store,job)
    current_intent<-.brohn_rpk_selection_live(store,input$selection_ref,job)$intent
    .brohn_publication_register(store,staged)
    body$result_object<-.brohn_publication_register(store,document)[[1L]][c("hash","size","media_type")]
    record<-brohn_put_entity(store,"report_package",id,body,0L,input$project_id)
    b<-current_intent$body;b$status<-"succeeded";b$reason<-NULL;b$job_ref<-list(id=job$id,status="succeeded");b$package_ref<-.brohn_rpk_ref(record)
    .brohn_rpk_put_intent(store,current_intent,b)
    brohn_complete_job(store,job$id,job$worker,job$token,list(report_package_id=id,output_hash=body$result_object$hash,selection_ref=input$selection_ref))
  });committed<-TRUE;receipt
}
