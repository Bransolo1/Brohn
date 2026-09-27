# Exact saved-result source access. Metadata discovery never substitutes a new
# head for an explicitly pinned historical report and never supplies science.
.brohn_rpk_same <- function(a,b) identical(brohn_json(a),brohn_json(b))
.brohn_rpk_hash <- function(x) is.character(x)&&length(x)==1L&&!is.na(x)&&grepl("^[a-f0-9]{64}$",x)
.brohn_rpk_ref <- function(record) list(kind=record$kind,id=record$id,revision=record$revision,
  body_hash=brohn_hash(record$body),project_id=record$project_id)
.brohn_rpk_ref_valid <- function(ref,kind=NULL) {
  brohn_fields(ref,c("kind","id","revision","body_hash","project_id"),label="Exact saved-report reference")
  brohn_require(brohn_valid_id(ref$kind)&&brohn_valid_id(ref$id)&&brohn_valid_id(ref$project_id)&&
    brohn_number(ref$revision,1,1e9,TRUE)&&.brohn_rpk_hash(ref$body_hash)&&
    (is.null(kind)||ref$kind %in% kind),"Choose an exact saved source identity, revision and hash.")
  invisible(ref)
}
.brohn_rpk_ref_catalog <- function(store,ref,kind=NULL) {
  .brohn_rpk_ref_valid(ref,kind)
  brohn_report_package_queue_authority(store,"report_package",ref$project_id)
  brohn_require(identical(.brohn_qexplorer_catalog(store,ref$kind,ref$id,ref$revision,ref$project_id),ref$body_hash),
    "The exact saved source is unavailable or changed; no newer version was substituted.")
  invisible(ref)
}
.brohn_rpk_record <- function(store,ref,kind=NULL) {
  .brohn_rpk_ref_catalog(store,ref,kind)
  record<-brohn_get_entity(store,ref$kind,ref$id,ref$revision)
  brohn_require(!is.null(record)&&.brohn_rpk_same(.brohn_rpk_ref(record),ref),"The saved source differs from its exact reference.")
  record
}
.brohn_rpk_parse_optional <- function(x,maximum=16*1024^2) {
  if(length(x)==0L||is.null(x)||is.na(x))NULL else brohn_parse(x,maximum)
}
.brohn_rpk_report_metadata <- function(store,ref) {
  .brohn_rpk_ref_catalog(store,ref,"report")
  row<-DBI::dbGetQuery(store$con,paste(
    "SELECT json_extract(body_json,'$.id') AS body_id,json_extract(body_json,'$.title') AS title,",
    "json_extract(body_json,'$.study_id') AS study_id,json_extract(body_json,'$.origin') AS origin,",
    "json_extract(body_json,'$.analysis.kind') AS analysis_kind,json_extract(body_json,'$.analysis.schema') AS analysis_schema,",
    "coalesce(json_array_length(body_json,'$.analysis.contrasts'),0) AS contrast_count,json_extract(body_json,'$.provenance.design_hash') AS design_hash,",
    "coalesce(json_array_length(body_json,'$.analysis.task_scores'),0)+coalesce(json_extract(body_json,'$.analysis.questionnaire_artifact.counts.task_scores'),0) task_score_count,",
    "coalesce(json_array_length(body_json,'$.analysis.choice_tasks'),0)+coalesce(json_extract(body_json,'$.analysis.questionnaire_artifact.counts.choice_tasks'),0) choice_task_count,",
    "json_extract(body_json,'$.provenance.design') AS design,json_extract(body_json,'$.provenance.selection') AS sources,",
    "json_extract(body_json,'$.provenance.source') AS original_source,json_extract(body_json,'$.dataset_id') AS dataset_id,json_extract(body_json,'$.provenance.run_evidence.runs') AS run_sources,",
    "json_extract(body_json,'$.analysis.artifacts') AS artifacts,json_extract(body_json,'$.analysis.questionnaire_artifact') AS questionnaire_artifact,json_extract(body_json,'$.result_object') AS result_object,",
    "json_extract(body_json,'$.processing') AS processing FROM entity_versions WHERE kind='report' AND id=? AND revision=? AND project_id=?"),
    params=list(ref$id,ref$revision,ref$project_id))
  brohn_require(nrow(row)==1L,"This exact saved report is unavailable.")
  scalar<-function(key){x<-row[[key]][[1L]];if(is.na(x))NULL else x}
  metadata<-list(ref=ref,id=scalar("body_id"),title=scalar("title"),study_id=scalar("study_id"),origin=scalar("origin"),
    kind=scalar("analysis_kind"),schema=scalar("analysis_schema"),design_hash=scalar("design_hash"),
    contrast_count=as.integer(row$contrast_count[[1L]]),
    task_score_count=as.integer(row$task_score_count[[1L]]),choice_task_count=as.integer(row$choice_task_count[[1L]]),
    design=.brohn_rpk_parse_optional(row$design[[1L]]),sources=.brohn_rpk_parse_optional(row$sources[[1L]]),
    original_source=.brohn_rpk_parse_optional(row$original_source[[1L]]),dataset_id=scalar("dataset_id"),
    run_sources=brohn_default(.brohn_rpk_parse_optional(row$run_sources[[1L]]),list()),
    artifacts=brohn_default(.brohn_rpk_parse_optional(row$artifacts[[1L]]),list()),
    questionnaire_artifact=.brohn_rpk_parse_optional(row$questionnaire_artifact[[1L]]),
    result_object=.brohn_rpk_parse_optional(row$result_object[[1L]]),processing=.brohn_rpk_parse_optional(row$processing[[1L]]))
  metadata$questionnaire_artifact<-NULL
  if(identical(metadata$schema,"brohn-questionnaire-report-preview/1.0")){
    complete<-Filter(function(a)identical(a$kind,"questionnaire-analysis"),metadata$artifacts)
    brohn_require(length(complete)==1L,"This questionnaire preview has no unique complete retained artifact.")
    metadata$questionnaire_artifact<-complete[[1L]]
  }
  .brohn_td_augment_metadata(store,metadata)
}
.brohn_rpk_study <- function(store,id,project_id) {
  brohn_report_package_queue_authority(store,"report_package",project_id)
  .brohn_tc_study(store,id,project_id)
}
.brohn_rpk_object <- function(store,object,maximum=256*1024^2) {
  brohn_require(is.list(object),"The saved source lacks its retained object descriptor.")
  hash<-brohn_default(object$hash,object$sha256);bytes<-brohn_default(object$bytes,object$size)
  brohn_require(.brohn_rpk_hash(hash)&&brohn_number(bytes,1,maximum,TRUE)&&brohn_text(object$media_type,128),
    "The saved source object exceeds this profile or lacks an exact byte identity.")
  if(!is.null(object$hash)&&!is.null(object$sha256))brohn_require(identical(object$hash,object$sha256),"Source hash aliases disagree.")
  if(!is.null(object$bytes)&&!is.null(object$size))brohn_require(object$bytes==object$size,"Source size aliases disagree.")
  path<-brohn_object_path(store,hash,FALSE)
  brohn_require(as.numeric(file.info(path)$size)==bytes,"The saved source byte count changed.")
  list(hash=hash,bytes=as.numeric(bytes),media_type=object$media_type,path=path)
}
.brohn_rpk_report_proof <- function(store,m,require_job=TRUE,task_enabled=FALSE) {
  brohn_require(is.null(.brohn_rpk_unsupported(m,task_enabled)),brohn_default(.brohn_rpk_unsupported(m,task_enabled),"Choose a supported complete report."))
  brohn_require(identical(m$id,m$ref$id)&&brohn_valid_id(m$study_id)&&brohn_text(m$origin,128)&&
    m$kind %in% c("gaze","questionnaire","multimodal",if(isTRUE(task_enabled))c("implicit","implicit_cohort"))&&is.list(m$design)&&
    identical(m$design$id,m$study_id)&&(is.null(m$design$project_id)||identical(m$design$project_id,m$ref$project_id))&&
    identical(brohn_hash(m$design),m$design_hash),"This report has no supported exact study/design provenance.")
  .brohn_rpk_study(store,m$study_id,m$ref$project_id)
  object<-.brohn_rpk_object(store,m$result_object,16*1024^2)
  if(require_job) {
    p<-m$processing;brohn_require(is.list(p)&&brohn_valid_id(p$job_id)&&brohn_number(p$attempt,1,1e9,TRUE),
      "This package profile requires the report's retained successful worker proof.")
    job<-brohn_get_job(store,p$job_id)
    brohn_require(!is.null(job)&&job$status=="succeeded"&&job$attempt==p$attempt&&
      identical(job$result$report_id,m$ref$id)&&identical(job$result$output_hash,object$hash),
      "The saved report no longer matches its original successful worker receipt.")
  }
  # A newer dataset mapping does not rewrite a historical report. Its present
  # project/source visibility is still a dependency, without re-reading raw data.
  if(!is.null(m$dataset_id)) {
    owner<-DBI::dbGetQuery(store$con,"SELECT e.project_id,coalesce(json_extract(v.body_json,'$.archived'),0) archived FROM entities e JOIN entity_versions v ON v.kind=e.kind AND v.id=e.id AND v.revision=e.revision WHERE e.kind='dataset' AND e.id=?",params=list(m$dataset_id))
    brohn_require(nrow(owner)==1L&&identical(owner$project_id[[1L]],m$ref$project_id)&&owner$archived[[1L]]==0L,"The report's original dataset is archived or no longer available in this project.")
  }
  for(run in m$run_sources){
    current<-DBI::dbGetQuery(store$con,paste("SELECT r.study_id,r.completion_status,r.transfer_status,r.acked_sequence,d.project_id FROM delivery_runs r",
      "JOIN delivery_deployments d ON d.id=r.deployment_id WHERE r.id=?"),params=list(run$run_id))
    brohn_require(nrow(current)==1L&&identical(current$study_id[[1L]],m$study_id)&&identical(current$project_id[[1L]],m$ref$project_id)&&
      identical(current$completion_status[[1L]],"completed")&&identical(current$transfer_status[[1L]],"saved")&&current$acked_sequence[[1L]]==run$final_sequence,
      "An original completed administration is unavailable, withdrawn or differs from its saved final receipt.")
  }
  object
}
.brohn_rpk_unsupported <- function(m,task_enabled=FALSE) {
  if(isTRUE(task_enabled)&&!is.null(m$source_family))return(.brohn_td_unsupported(m))
  if(!m$kind %in% c("gaze","questionnaire","multimodal"))return("This report family has no complete-findings package adapter yet. Its existing saved report and exports remain available.")
  if(!is.null(m$schema)&&!(identical(m$kind,"questionnaire")&&identical(m$schema,"brohn-questionnaire-report-preview/1.0")))return("This scientific schema has no qualified complete-findings package adapter yet. Use its existing saved report and complete export.")
  if(m$task_score_count>0L)return("This saved report includes task scores whose complete package adapter is not enabled yet. Use its existing complete export.")
  if(m$choice_task_count>0L)return("This saved report includes choice-task evidence whose complete package adapter is not enabled yet. Use its existing complete export.")
  if(length(m$artifacts)&&!identical(m$schema,"brohn-questionnaire-report-preview/1.0"))return("This report includes scientific artifacts whose complete package adapter is not enabled yet. Use its existing complete export.")
  NULL
}
.brohn_rpk_required_source_fit <- function(store,metadata,task_enabled=FALSE) {
  seen<-character()
  walk<-function(m,root=FALSE){
    key<-brohn_hash(m$ref);if(key %in% seen)return(NULL);seen<<-c(seen,key)
    if(length(seen)>32L)return("The required saved-source dependency closure exceeds this package profile.")
    reason<-.brohn_rpk_unsupported(m,task_enabled)
    if(!is.null(reason))return(if(root)reason else paste("A required selected source cannot be included completely.",reason))
    if(!identical(m$study_id,metadata$study_id))return("A required selected source belongs to a different study and cannot be included in this package.")
    for(ref in .brohn_td_parent_refs(m)){
      parent<-tryCatch(.brohn_rpk_report_metadata(store,ref),error=function(e)NULL)
      if(is.null(parent))return("A required selected source is unavailable at its saved identity in this project. Reopen the source report before preparing this package.")
      reason<-walk(parent);if(!is.null(reason))return(reason)
    }
    NULL
  }
  walk(metadata,TRUE)
}
brohn_report_package_report_choice <- function(store,report_ref) {
  m<-.brohn_rpk_report_metadata(store,report_ref)
  .brohn_rpk_study(store,m$study_id,report_ref$project_id)
  adapters<-list()
  if(identical(m$kind,"gaze"))adapters<-c(adapters,list("gaze-context"))
  if(identical(m$kind,"questionnaire"))adapters<-c(adapters,list("explicit-distribution"))
  # Only metadata is inspected here; full saved contrast agreement is a worker gate.
  if(m$kind %in% c("gaze","questionnaire","multimodal")&&
    (m$contrast_count>0L||identical(m$schema,"brohn-questionnaire-report-preview/1.0")))adapters<-c(adapters,list("paired-findings"))
  if(isTRUE(m$source_family %in% c("native_questionnaire","imported_implicit")))adapters<-c(adapters,list("task-scores","task-trials"))
  if(identical(m$source_family,"saved_task_cohort"))adapters<-c(adapters,list("task-people"))
  unsupported<-.brohn_rpk_required_source_fit(store,m,TRUE);if(!is.null(unsupported))adapters<-list()
  recommendations<-tryCatch({
    selected<-list(report_ref)
    if(identical(m$kind,"multimodal"))for(s in brohn_default(m$sources,list()))if(identical(s$state,"selected")){
      linked<-list(kind="report",id=s$id,revision=s$revision,body_hash=s$hash,project_id=report_ref$project_id)
      parent<-.brohn_rpk_report_metadata(store,linked);.brohn_rpk_report_proof(store,parent)
      brohn_require(identical(parent$study_id,m$study_id)&&parent$kind %in% c("gaze","questionnaire"),"Choose the applicable saved parent reports explicitly.")
      if(!any(vapply(selected,function(x).brohn_rpk_same(x,linked),logical(1))))selected<-c(selected,list(linked))
    }
    brohn_require(length(selected)<=8L,"Choose up to eight exact saved source reports.")
    list(refs=selected,reason=if(length(selected)>1L)"Includes this saved combined report and its exact gaze/explicit source reports, with complete numerical evidence. You can change the selected reports."else "Includes this exact saved report and all its applicable findings.")
  },error=function(e)list(refs=list(),reason="Linked source recommendations are unavailable. Choose the exact saved reports to include."))
  if(!length(adapters))recommendations<-list(refs=list(),reason=brohn_default(unsupported,"This saved report has no enabled complete-findings package adapter."))
  list(ref=report_ref,title=brohn_default(m$title,report_ref$id),origin=m$origin,kind=m$kind,source_family=m$source_family,
    design_hash=m$design_hash,adapters=adapters,status=if(length(adapters))"available"else"unsupported_package_adapter",
    reason=if(length(adapters))NULL else brohn_default(unsupported,"This saved report has no enabled complete-findings package adapter."),
    recommended_refs=recommendations$refs,recommendation_reason=recommendations$reason)
}
.brohn_rpk_cursor <- function(cursor,scope) {
  if(is.null(cursor))return(NULL)
  brohn_fields(cursor,c("scope","updated_at","id"),label="Saved-report page cursor")
  brohn_require(identical(cursor$scope,scope)&&brohn_text(cursor$updated_at,128)&&brohn_valid_id(cursor$id),"Reopen the requested saved-report page.")
  cursor
}
brohn_report_package_choices <- function(store,study_id,project_id,cursor=NULL,limit=25L) {
  study<-.brohn_rpk_study(store,study_id,project_id)
  brohn_require(brohn_number(limit,1,100,TRUE),"Choose a report page of 1 to 100 items.")
  scope<-brohn_hash(list("report_package_choices",study_id,project_id));cursor<-.brohn_rpk_cursor(cursor,scope)
  sql<-paste("SELECT v.id,v.revision,v.body_hash,e.updated_at FROM entities e JOIN entity_versions v",
    "ON v.kind=e.kind AND v.id=e.id AND v.revision=e.revision WHERE e.kind='report' AND e.project_id=?",
    "AND json_extract(v.body_json,'$.study_id')=?")
  params<-list(project_id,study_id)
  if(!is.null(cursor)){sql<-paste(sql,"AND (e.updated_at<? OR (e.updated_at=? AND e.id>?))");params<-c(params,list(cursor$updated_at,cursor$updated_at,cursor$id))}
  rows<-DBI::dbGetQuery(store$con,paste(sql,"ORDER BY e.updated_at DESC,e.id ASC LIMIT ?"),params=c(params,list(limit+1L)))
  more<-nrow(rows)>limit;rows<-head(rows,limit)
  reports<-lapply(seq_len(nrow(rows)),function(i)brohn_report_package_report_choice(store,
    list(kind="report",id=rows$id[[i]],revision=rows$revision[[i]],body_hash=rows$body_hash[[i]],project_id=project_id)))
  next_cursor<-if(more)list(scope=scope,updated_at=tail(rows$updated_at,1),id=tail(rows$id,1))else NULL
  list(study=list(id=study$id,title=study$body$title,project_id=project_id),reports=reports,cursor=cursor,
    next_cursor=next_cursor,recommended_refs=list(),needs_choice=TRUE)
}

brohn_report_package_selector_catalog <- function(store,report_ref,adapter,cursor=NULL,limit=25L,prepared_ref=NULL) {
  if(adapter %in% c("task-scores","task-trials","task-people"))return(.brohn_td_selector_catalog(store,report_ref,adapter,cursor,limit,prepared_ref))
  m<-.brohn_rpk_report_metadata(store,report_ref);choice<-brohn_report_package_report_choice(store,report_ref)
  brohn_require(adapter %in% unlist(choice$adapters)&&brohn_number(limit,1,100,TRUE),"Choose a supported report figure family.")
  scope<-brohn_hash(if(is.null(prepared_ref))list(report_ref,adapter)else list(report_ref=report_ref,adapter=adapter,prepared_ref=prepared_ref));offset<-0L
  if(!is.null(cursor)){brohn_fields(cursor,c("scope","offset"),label="Figure page");brohn_require(identical(cursor$scope,scope)&&brohn_number(cursor$offset,0,100000,TRUE),"Reopen this exact figure page.");offset<-cursor$offset}
  base<-"SELECT body_json FROM entity_versions WHERE kind='report' AND id=? AND revision=? AND project_id=?"
  args<-list(report_ref$id,report_ref$revision,report_ref$project_id);items<-list();more<-FALSE;needs<-FALSE
  if(adapter=="gaze-context") {
    rows<-DBI::dbGetQuery(store$con,paste0("WITH source AS (",base,"), records AS (SELECT j.value FROM source,json_each(source.body_json,'$.analysis.observations') j UNION ALL SELECT j.value FROM source,json_each(source.body_json,'$.analysis.features') j) SELECT DISTINCT json_extract(value,'$.participant_id') participant_id,json_extract(value,'$.session_id') session_id,json_extract(value,'$.stimulus_id') stimulus_id,json_extract(value,'$.exposure_id') exposure_id FROM records ORDER BY participant_id,session_id,stimulus_id,exposure_id LIMIT ? OFFSET ?"),params=c(args,list(limit+1L,offset)))
    more<-nrow(rows)>limit;rows<-head(rows,limit)
    items<-lapply(seq_len(nrow(rows)),function(i){r<-as.list(rows[i,,drop=FALSE]);brohn_require(all(vapply(r,brohn_text,logical(1),max=1024)),"A saved exposure has incomplete identity.");stim<-brohn_find(m$design$stimuli,r$stimulus_id)
      list(selector=list(scope="exact_exposure",exposure_key=.brohn_gaze_view_key(r)),label=paste(brohn_default(stim$title,r$stimulus_id),r$participant_id,r$session_id,r$exposure_id,sep=" | "),details=list(stimulus_id=r$stimulus_id))})
  }else if(adapter=="paired-findings") {
    if(!is.null(prepared_ref)&&identical(prepared_ref$kind,"task_display")){
      prepared<-.brohn_td_metadata(store,prepared_ref)
      brohn_require(.brohn_td_same(prepared$report_ref,report_ref),"The prepared comparison catalog belongs to another exact report.")
      all<-prepared$record$body$companion_catalog;more<-length(all)>offset+limit
      picked<-if(offset>=length(all))list()else all[seq.int(offset+1L,min(length(all),offset+limit))]
      items<-lapply(picked,function(c)list(selector=list(scope="exact_comparison",comparison_id=c$comparison_id,contrast_hash=c$contrast_hash),label=c$label,details=c))
    }else if(identical(m$schema,"brohn-questionnaire-report-preview/1.0")){needs<-TRUE}else{
      rows<-DBI::dbGetQuery(store$con,paste0("WITH source AS (",base,") SELECT j.key ordinal,CASE WHEN length(CAST(j.value AS BLOB))<=262144 THEN j.value ELSE NULL END value FROM source,json_each(source.body_json,'$.analysis.contrasts') j ORDER BY CAST(j.key AS INTEGER) LIMIT ? OFFSET ?"),params=c(args,list(limit+1L,offset)))
      more<-nrow(rows)>limit;rows<-head(rows,limit)
      items<-lapply(seq_len(nrow(rows)),function(i){brohn_require(!is.na(rows$value[[i]]),"This comparison needs saved display preparation before focused figure selection.");c<-brohn_parse(rows$value[[i]],262144)
        list(selector=list(scope="exact_comparison",comparison_id=paste0("comparison-",rows$ordinal[[i]]+1L),contrast_hash=brohn_hash(c)),label=paste(brohn_default(c$outcome_label,c$outcome_id),c$metric,c$test_label,"minus",c$control_label),details=list(unit=c$unit))})
    }
  }else{
    ref<-if(is.null(prepared_ref)).brohn_rpk_find_distribution(store,report_ref)else prepared_ref
    if(is.null(ref)){needs<-TRUE}else{
      exact<-.brohn_rpk_distribution_metadata(store,ref)
      brohn_require(.brohn_rpk_same(exact$report_ref,report_ref),"The response catalog belongs to another exact source report.")
      rows<-DBI::dbGetQuery(store$con,paste("SELECT json_extract(j.value,'$.family') family,json_extract(j.value,'$.item_id') item_id,json_extract(j.value,'$.condition_id') condition_id,",
        "json_extract(j.value,'$.label') label,json_extract(j.value,'$.condition_label') condition_label FROM entity_versions v,json_each(v.body_json,'$.result.groups') j",
        "WHERE v.kind='explicit_distributions' AND v.id=? AND v.revision=? AND v.project_id=? ORDER BY CAST(j.key AS INTEGER) LIMIT ? OFFSET ?"),params=list(ref$id,ref$revision,ref$project_id,limit+1L,offset))
      more<-nrow(rows)>limit;rows<-head(rows,limit)
      items<-lapply(seq_len(nrow(rows)),function(i)list(selector=list(scope="exact_item_condition",family=rows$family[[i]],item_id=rows$item_id[[i]],condition_id=if(is.na(rows$condition_id[[i]]))NULL else rows$condition_id[[i]]),label=paste(rows$label[[i]],rows$condition_label[[i]],sep=" | "),details=list()))
    }
  }
  list(report_ref=report_ref,adapter=adapter,items=items,cursor=cursor,next_cursor=if(more)list(scope=scope,offset=offset+limit)else NULL,requires_display_preparation=needs)
}
.brohn_rpk_distribution_metadata <- function(store,ref) {
  .brohn_rpk_ref_catalog(store,ref,"explicit_distributions")
  row<-DBI::dbGetQuery(store$con,paste("SELECT json_extract(body_json,'$.schema') schema,json_extract(body_json,'$.request') request,",
    "json_extract(body_json,'$.processing') processing,json_extract(body_json,'$.preparation_implementation_ref') preparation_implementation_ref,json_extract(body_json,'$.result_object') result_object FROM entity_versions WHERE kind=? AND id=? AND revision=? AND project_id=?"),params=list(ref$kind,ref$id,ref$revision,ref$project_id))
  brohn_require(nrow(row)==1L&&identical(row$schema[[1L]],"brohn-saved-explicit-distributions/1.0"),"Choose a complete saved distribution.")
  r<-brohn_parse(row$request[[1L]]);p<-brohn_parse(row$processing[[1L]]);object<-.brohn_rpk_object(store,brohn_parse(row$result_object[[1L]]),12*1024^2)
  report_ref<-list(kind="report",id=r$report_id,revision=r$report_revision,body_hash=r$report_hash,project_id=r$project_id)
  .brohn_rpk_ref_catalog(store,report_ref,"report")
  job<-brohn_get_job(store,p$job_id)
  brohn_require(!is.null(job)&&job$status=="succeeded"&&job$attempt==p$attempt&&job$operation=="explicit_distributions"&&
    identical(job$result$explicit_distributions_id,ref$id)&&identical(job$result$output_hash,object$hash),"Saved distributions no longer match their successful original worker proof.")
  implementation_ref<-.brohn_rpk_parse_optional(row$preparation_implementation_ref[[1L]],1024)
  if(!is.null(implementation_ref))brohn_require(.brohn_td_same(implementation_ref,job$request$preparation_implementation_ref)&&
    .brohn_td_same(report_ref,job$request$report_ref),"Saved pinned distributions differ from their original producer preparation identity.")
  list(ref=ref,report_ref=report_ref,request=r,processing=p,object=object,preparation_implementation_ref=implementation_ref)
}
.brohn_rpk_find_distribution <- function(store,report_ref) {
  .brohn_rpk_ref_catalog(store,report_ref,"report")
  rows<-DBI::dbGetQuery(store$con,paste("SELECT v.id,v.revision,v.body_hash FROM entity_versions v JOIN entities e ON e.kind=v.kind AND e.id=v.id AND e.revision=v.revision",
    "WHERE v.kind='explicit_distributions' AND v.project_id=? AND json_extract(v.body_json,'$.request.report_id')=?",
    "AND json_extract(v.body_json,'$.request.report_revision')=? AND json_extract(v.body_json,'$.request.report_hash')=? ORDER BY e.updated_at DESC,e.id LIMIT 1"),params=list(report_ref$project_id,report_ref$id,report_ref$revision,report_ref$body_hash))
  if(!nrow(rows))return(NULL)
  ref<-list(kind="explicit_distributions",id=rows$id[[1L]],revision=rows$revision[[1L]],body_hash=rows$body_hash[[1L]],project_id=report_ref$project_id)
  .brohn_rpk_distribution_metadata(store,ref);ref
}
.brohn_rpk_source_metadata <- function(store,report_refs,display_refs=list(),images=FALSE,task_refs=list(),task_enabled=FALSE) {
  objects<-list();reports<-list();seen<-character();active<-character();assets<-list()
  add_object<-function(o){previous<-objects[[o$hash]];if(!is.null(previous))brohn_require(.brohn_rpk_same(previous,o),"An original object has conflicting descriptors.");objects[[o$hash]]<<-o}
  walk<-function(ref){
    key<-brohn_hash(ref);brohn_require(!key %in% active,"The saved report source graph contains a cycle.");if(key %in% seen)return(invisible(NULL));seen<<-c(seen,key);active<<-c(active,key);on.exit(active<<-setdiff(active,key),add=TRUE)
    brohn_require(length(seen)<=32L,"The saved-report dependency closure exceeds this package profile.")
    m<-.brohn_rpk_report_metadata(store,ref);o<-.brohn_rpk_report_proof(store,m,task_enabled=task_enabled);reports[[key]]<<-m;add_object(o)
    if(isTRUE(task_enabled))for(extra in .brohn_td_extra_objects(store,m))add_object(extra)
    if(!is.null(m$questionnaire_artifact)){a<-m$questionnaire_artifact;if(is.null(a$media_type))a$media_type<-"application/x-ndjson";add_object(.brohn_rpk_object(store,a,64*1024^2))}
    for(parent in .brohn_td_parent_refs(m))walk(parent)
  }
  for(ref in report_refs)walk(ref)
  brohn_require(length(unique(vapply(reports,`[[`,character(1),"study_id")))==1L,"Every exact report and retained source must belong to the same study.")
  distributions<-lapply(display_refs,function(ref){m<-.brohn_rpk_distribution_metadata(store,ref);walk(m$report_ref);add_object(m$object);m})
  task_displays<-lapply(task_refs,function(ref){m<-.brohn_td_metadata(store,ref);walk(m$report_ref);add_object(m$object);add_object(m$document);m})
  if(isTRUE(images))for(ref in report_refs){m<-reports[[brohn_hash(ref)]];if(m$kind!="gaze")next
    for(stim in m$design$stimuli)if(!is.null(stim$asset)){
      a<-.brohn_rpk_object(store,stim$asset,5*1024^2);brohn_require(a$media_type %in% c("image/png","image/jpeg"),"Choose supported saved PNG/JPEG stimuli or exclude their images.");add_object(a)
      old<-assets[[a$hash]];if(is.null(old))old<-list(ref=a[c("hash","bytes","media_type")],path=a$path,stimulus_refs=list())
      old$stimulus_refs<-c(old$stimulus_refs,list(list(report_ref=ref,stimulus_id=stim$id)));assets[[a$hash]]<-old
    }
  }
  brohn_require(sum(vapply(assets,function(x)x$ref$bytes,numeric(1)))<=16*1024^2,"The chosen saved stimuli exceed the 16 MiB image profile. Exclude images or select fewer source reports.")
  list(report_refs=report_refs,display_refs=display_refs,task_refs=task_refs,task_enabled=isTRUE(task_enabled),images=isTRUE(images),reports=unname(reports),distributions=distributions,task_displays=task_displays,objects=unname(objects),assets=unname(assets))
}
.brohn_rpk_release <- function(handle) {
  if(is.environment(handle)&&inherits(handle,"brohn_report_source_resources")&&is.environment(handle$state)&&!isTRUE(handle$state$closed)){
    state<-handle$state;state$closed<-TRUE
    for(g in c(handle$guards,state$extra_guards))tryCatch(.brohn_qexplorer_release(g),error=function(e)NULL)
  };invisible(NULL)
}
brohn_release_report_package_sources <- .brohn_rpk_release
.brohn_rpk_hold_sources <- function(store,metadata) {
  guards<-list();ok<-FALSE;on.exit(if(!ok)for(g in guards).brohn_qexplorer_release(g),add=TRUE)
  guards<-brohn_hold_signal_value_sources(store,list(source_objects=lapply(metadata$objects,function(o)o[c("hash","bytes")])))
  current<-.brohn_rpk_source_metadata(store,metadata$report_refs,metadata$display_refs,metadata$images,metadata$task_refs,metadata$task_enabled)
  brohn_require(.brohn_rpk_same(current,metadata),"Saved-report sources changed while establishing their read seals.")
  for(o in metadata$objects)brohn_object_path(store,o$hash,TRUE)
  handle<-new.env(parent=emptyenv());class(handle)<-"brohn_report_source_resources"
  handle$metadata<-metadata;handle$workspace_id<-store$workspace_id;handle$guards<-guards;handle$state<-new.env(parent=emptyenv());handle$state$closed<-FALSE;handle$state$extra_guards<-list()
  lockEnvironment(handle,bindings=TRUE);reg.finalizer(handle,.brohn_rpk_release,onexit=TRUE);ok<-TRUE;handle
}
brohn_report_package_sources_current <- function(store,handle) {
  brohn_require(is.environment(handle)&&inherits(handle,"brohn_report_source_resources")&&environmentIsLocked(handle)&&!isTRUE(handle$state$closed)&&identical(store$workspace_id,handle$workspace_id),"Reopen the closed or different-workspace report sources.")
  .brohn_cm_guard_check(c(handle$guards,handle$state$extra_guards))
  m<-handle$metadata;current<-.brohn_rpk_source_metadata(store,m$report_refs,m$display_refs,m$images,m$task_refs,m$task_enabled)
  brohn_require(.brohn_rpk_same(current,m),"Saved-report source permission, retained proof or exact identity changed.")
  .brohn_cm_guard_check(c(handle$guards,handle$state$extra_guards));invisible(current)
}
.brohn_rpk_complete_sources <- function(store,handle,all_reports=FALSE) {
  m<-brohn_report_package_sources_current(store,handle);complete<-list()
  for(meta in m$reports){
    record<-.brohn_rpk_record(store,meta$ref,"report");b<-record$body
    retained<-brohn_read_json_file(brohn_object_path(store,b$result_object$hash,FALSE),maximum=16*1024^2)
    brohn_require(identical(retained$schema,"brohn-analysis-output/1.0")&&.brohn_rpk_same(retained$report,b[setdiff(names(b),"result_object")]),"Saved report catalog contents differ from their sealed original worker envelope.")
    full<-if(brohn_questionnaire_is_artifact(b$analysis)){
      a<-brohn_questionnaire_report_artifact(b);f<-brohn_read_questionnaire_artifact(brohn_object_path(store,a$hash,FALSE),a,brohn_questionnaire_artifact_source(b),max_bytes=64*1024^2)
      brohn_validate_questionnaire_preview(b$analysis,f,brohn_questionnaire_artifact_source(b));f
    }else b$analysis
    complete[[brohn_hash(meta$ref)]]<-list(ref=meta$ref,saved_body=b,complete_analysis=full)
  }
  distributions<-lapply(m$distributions,function(meta){r<-.brohn_rpk_record(store,meta$ref,"explicit_distributions");original<-brohn_read_json_file(meta$object$path,maximum=12*1024^2)
    brohn_require(.brohn_rpk_same(original,r$body[setdiff(names(r$body),"result_object")]),"Saved distribution catalog and sealed original document disagree.");list(ref=meta$ref,body=r$body)})
  task_displays<-lapply(m$task_displays,function(meta){r<-.brohn_rpk_record(store,meta$ref,"task_display")
    original<-brohn_read_json_file(meta$document$path,maximum=2*1024^2)
    brohn_require(.brohn_td_same(original,r$body[setdiff(names(r$body),"retained_document")]),"Task display metadata differs from its sealed publication document.")
    evidence<-brohn_read_json_file(meta$object$path,maximum=32*1024^2)
    brohn_validate_task_display_evidence(evidence,complete[[brohn_hash(meta$report_ref)]])
    list(ref=meta$ref,body=r$body,evidence=evidence)})
  brohn_report_package_sources_current(store,handle)
  list(reports=if(isTRUE(all_reports))unname(complete)else lapply(m$report_refs,function(ref)complete[[brohn_hash(ref)]]),distributions=distributions,task_displays=task_displays,assets=m$assets)
}
.brohn_rpk_package_metadata <- function(store,ref,project_id) {
  brohn_require(identical(ref$project_id,project_id),"Choose this package's exact project.")
  r<-.brohn_rpk_record(store,ref,"report_package");b<-r$body
  brohn_require(identical(b$schema,"brohn-saved-report-package/0.1")&&identical(b$id,r$id)&&identical(b$profile,"complete-findings/0.1"),"Choose a saved complete-findings package.")
  selection<-.brohn_rpk_record(store,b$selection_ref,"report_package_selection");s<-selection$body
  .brohn_rpk_ref_catalog(store,s$intent_ref,"report_package_intent")
  brohn_require(identical(s$study_id,b$study_id)&&.brohn_rpk_same(b$manifest$selection,s[setdiff(names(s),c("intent_ref","generation"))])&&
    .brohn_rpk_same(b$manifest$coverage,b$coverage),"The saved package no longer binds its original frozen contents.")
  .brohn_rpk_study(store,b$study_id,project_id)
  p<-b$processing;j<-brohn_get_job(store,p$job_id)
  doc<-.brohn_rpk_object(store,b$result_object,16*1024^2)
  brohn_require(!is.null(j)&&j$status=="succeeded"&&j$operation=="report_package"&&j$attempt==p$attempt&&
    identical(j$result$report_package_id,r$id)&&identical(j$result$output_hash,doc$hash)&&
    .brohn_rpk_same(j$request$selection_ref,b$selection_ref)&&identical(j$request$content_fingerprint,p$content_fingerprint),"Saved package proof differs from its original successful worker receipt.")
  # Only current-reader policy is evaluated here. The old producer's session may
  # have expired without invalidating its successfully published saved result.
  brohn_fields(b$artifacts,c("html","zip","manifest"),label="Saved package downloads")
  expected<-c(html="report.html",zip="report.brohn-report.zip",manifest="manifest.json")
  arts<-lapply(names(expected),function(k){a<-b$artifacts[[k]];brohn_require(identical(a$file,expected[[k]]),"A saved package download changed its file identity.");o<-.brohn_rpk_object(store,a,512*1024^2);c(list(file=a$file),o)})
  names(arts)<-names(expected)
  source<-.brohn_rpk_selection_sources(store,s)
  list(record=r,artifacts=arts,document=doc,source=source)
}
brohn_release_report_package_resources <- function(handle) {
  if(is.environment(handle)&&inherits(handle,"brohn_report_package_resources")&&is.environment(handle$state)&&!isTRUE(handle$state$closed)){
    state<-handle$state;state$closed<-TRUE
    for(g in handle$guards)tryCatch(.brohn_qexplorer_release(g),error=function(e)NULL)
    .brohn_rpk_release(handle$source_handle)
  };invisible(NULL)
}
brohn_open_report_package_resources <- function(store,ref,project_id) {
  m<-.brohn_rpk_package_metadata(store,ref,project_id);guards<-list();sources<-NULL;ok<-FALSE
  on.exit(if(!ok){for(g in guards)tryCatch(.brohn_qexplorer_release(g),error=function(e)NULL);.brohn_rpk_release(sources)},add=TRUE)
  # Seal the complete package and publication before reading either JSON. Source
  # resources get their own all-before-verification lifetime as well.
  objects<-c(unname(m$artifacts),list(m$document))
  guards<-brohn_hold_signal_value_sources(store,list(source_objects=lapply(objects,function(o)o[c("hash","bytes")])))
  sources<-.brohn_rpk_hold_sources(store,m$source)
  for(o in objects)brohn_object_path(store,o$hash,TRUE)
  manifest<-brohn_read_json_file(m$artifacts$manifest$path,maximum=4*1024^2)
  original<-brohn_read_json_file(m$document$path,maximum=16*1024^2)
  brohn_require(.brohn_rpk_same(manifest,m$record$body$manifest)&&.brohn_rpk_same(original,m$record$body[setdiff(names(m$record$body),"result_object")]),"The sealed package differs from its retained manifest or original publication.")
  current<-.brohn_rpk_package_metadata(store,ref,project_id);brohn_require(.brohn_rpk_same(current,m),"The saved package or source authority changed while opening.")
  .brohn_cm_guard_check(guards);brohn_report_package_sources_current(store,sources)
  h<-new.env(parent=emptyenv());class(h)<-"brohn_report_package_resources";h$state<-new.env(parent=emptyenv());h$state$closed<-FALSE
  h$ref<-ref;h$project_id<-project_id;h$metadata<-m;h$guards<-guards;h$source_handle<-sources;h$workspace_id<-store$workspace_id
  lockEnvironment(h,bindings=TRUE);reg.finalizer(h,brohn_release_report_package_resources,onexit=TRUE);ok<-TRUE
  list(record=m$record,handle=h,manifest=manifest,artifacts=m$artifacts)
}
brohn_report_package_resources_current <- function(store,handle) {
  brohn_require(is.environment(handle)&&inherits(handle,"brohn_report_package_resources")&&environmentIsLocked(handle)&&
    !isTRUE(handle$state$closed)&&identical(handle$workspace_id,store$workspace_id),"Reopen this closed or different-workspace package.")
  .brohn_cm_guard_check(handle$guards);brohn_report_package_sources_current(store,handle$source_handle)
  current<-.brohn_rpk_package_metadata(store,handle$ref,handle$project_id)
  brohn_require(.brohn_rpk_same(current,handle$metadata),"The opened package or current-reader source authority changed.")
  .brohn_cm_guard_check(handle$guards);list(record=current$record,artifacts=current$artifacts)
}
