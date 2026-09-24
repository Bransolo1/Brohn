# Read-only plots of complete saved evidence. No scorer or cohort estimator runs
# here. A native source is opened lazily; questionnaire preview rows are unused.
.brohn_tp_supported <- function(r) identical(r$analysis$schema,"brohn-task-cohort/1.0") ||
  length(r$analysis$task_attempts)>0L || (length(r$provenance$runs)>0L && length(r$provenance$design$blocks)>0L)
.brohn_tp_label <- function(metric) switch(metric,correct_test_rt_mean="Individual mean test response time",
  correct_test_rt_median="Individual median test response time",correct_test_rt_sd="Individual response-time standard deviation",
  test_first_response_error_rate="Individual first-response error proportion",test_omission_rate="Individual no-response proportion",
  keyboard_aat_relative_approach_advantage="Relative keyboard approach advantage",IAT_D1="IAT D1 score",BIAT_D="Brief IAT D score",SCIAT_target_positive_D="SC-IAT target-positive D score",metric)
.brohn_tp_num <- function(x) if(is.null(x))"Unavailable" else format(signif(x,6),trim=TRUE)
.brohn_tp_catalog <- function(report) {
  a<-report$analysis
  if(identical(a$schema,"brohn-task-cohort/1.0"))return(lapply(a$summaries,function(s)
    list(id=paste0("metric:",s$metric),kind="people",metric=s$metric,label=.brohn_tp_label(s$metric))))
  if(length(a$task_attempts))return(lapply(a$task_attempts,function(x)list(id=x$id,kind="imported",attempt_id=x$id,
    label=paste(x$participant_id,x$session_id,x$attempt_id,x$profile,sep=" | "))))
  unlist(lapply(report$provenance$runs,function(r)lapply(report$provenance$design$blocks,function(t)
    list(id=brohn_hash(list(r$run_id,t$id)),kind="native",run_id=r$run_id,task_id=t$id,
      label=paste(r$run_id,t$title,t$profile,sep=" | ")))),recursive=FALSE,use.names=FALSE)
}
brohn_task_plot_report <- function(store,report_id,revision,report_hash,project_id) {
  brohn_project(store,project_id)
  owner<-DBI::dbGetQuery(store$con,"SELECT project_id FROM entities WHERE kind='report' AND id=?",params=list(report_id))
  brohn_require(nrow(owner)==1L&&identical(owner$project_id[[1L]],project_id),"This saved task report is unavailable in the current project.")
  r<-brohn_get_entity(store,"report",report_id,revision)
  brohn_require(!is.null(r)&&identical(r$project_id,project_id)&&identical(brohn_hash(r$body),report_hash),"This saved report changed. Reopen its task plots.")
  study<-.brohn_tc_study(store,r$body$study_id,project_id)
  verified<-.brohn_tc_report(store,study,report_id)
  brohn_require(identical(as.numeric(verified$record$revision),as.numeric(revision))&&identical(brohn_hash(verified$record$body),report_hash),"No newer report can replace the opened task source.")
  brohn_require(.brohn_tp_supported(r$body),"This report has no complete supported task evidence.")
  list(record=r,catalog=.brohn_tp_catalog(r$body),reference=verified$reference,
    catalog_hash=.brohn_qexplorer_catalog(store,"report",r$id,r$revision,project_id))
}
brohn_task_plot_check <- function(store,opened,model=NULL) {
  r<-opened$record;brohn_project(store,r$project_id)
  current<-DBI::dbGetQuery(store$con,"SELECT revision,project_id FROM entities WHERE kind='report' AND id=?",params=list(r$id))
  brohn_require(nrow(current)==1L&&current$revision[[1L]]==r$revision&&identical(current$project_id[[1L]],r$project_id)&&
    identical(.brohn_qexplorer_catalog(store,"report",r$id,r$revision,r$project_id),opened$catalog_hash),"The opened task report changed or is unavailable. Reopen its current saved source.")
  owner<-DBI::dbGetQuery(store$con,"SELECT project_id FROM entities WHERE kind='study' AND id=?",params=list(r$body$study_id))
  brohn_require(nrow(owner)==1L&&identical(owner$project_id[[1L]],r$project_id),"The source study is no longer available in this project.")
  brohn_object_path(store,r$body$result_object$hash,verify=TRUE)
  if(!is.null(model)&&model$kind=="trials") {
    if(identical(model$evidence_level,"brohn_journal_replayed")) {
      rows<-DBI::dbGetQuery(store$con,paste("SELECT r.protocol_hash FROM delivery_runs r JOIN delivery_deployments d ON r.deployment_id=d.id",
        "WHERE r.id=? AND r.study_id=? AND d.study_id=? AND d.project_id=? AND r.completion_status='completed' AND r.transfer_status='saved'"),
        params=list(model$identity$run_id,r$body$study_id,r$body$study_id,r$project_id))
      brohn_require(nrow(rows)==1L&&identical(rows$protocol_hash[[1L]],model$source$saved_protocol_bytes_hash),"The original participant session is no longer available under its saved authority.")
    } else for(hash in c(model$source$original_hash,model$source$registry_object_hash))brohn_object_path(store,hash,verify=TRUE)
  }
  invisible(TRUE)
}
# Original raw response fields remain distinct from the saved scoring audit.
.brohn_tp_trial_rows <- function(audits,responses) {
  brohn_require(brohn_array(audits)&&length(audits)>0L&&length(audits)<=20000L&&brohn_array(responses),"A complete administration needs 1 to 20,000 expected positions.")
  ids<-vapply(audits,`[[`,character(1),"trial_id");rids<-vapply(responses,`[[`,character(1),"trial_id")
  brohn_require(!anyDuplicated(ids)&&!anyDuplicated(rids)&&all(rids %in% ids),"Trial identities are duplicated or absent from the frozen order.")
  lapply(seq_along(audits),function(i){a<-audits[[i]];j<-match(a$trial_id,rids);r<-if(is.na(j))NULL else responses[[j]]
    for(f in c("first_response_ms","final_correct_ms"))brohn_require(is.null(r[[f]])||brohn_number(r[[f]],0),"A recorded latency must be finite, nonnegative or unavailable.")
    brohn_require(isTRUE(a$derived)==is.null(r),"Missing source positions disagree with their retained response evidence.")
    list(position=i,trial_id=a$trial_id,source_row=a$source_row,derived_missing=isTRUE(a$derived),block_id=a$block_id,
      profile_scored=isTRUE(a$profile_scored),score_block=a$score_block,category_id=a$category_id,action=a$action,
      presented=r$presented,outcome=r$outcome,first_correct=r$first_correct,response_code=r$response_code,final_code=r$final_code,
      first_response_ms=r$first_response_ms,final_correct_ms=r$final_correct_ms,
      first_response_ms_source=r$first_response_ms_source,final_correct_ms_source=r$final_correct_ms_source,
      disposition=a$disposition,missing_reason=brohn_default(a$missing_reason,r$missing_reason),
      scoring_latency_ms=a$scoring_latency_ms,original_fast_below_300=a$original_fast_below_300)
  })
}
brohn_task_plot_attempt <- function(a) {
  .brohn_task_cohort_attempt(a)
  brohn_require(length(a$trial_audit)==a$score$counts$expected,"The saved trial audit does not contain every expected position. A bounded preview cannot become a complete plot.")
  list(schema="brohn-task-trial-plot/1.0",kind="trials",id=a$id,label=paste(a$participant_id,a$session_id,a$profile,sep=" | "),
    profile=a$profile,origin=a$collection_origin,material_origin=a$material_origin,completion=a$completion_status,
    rows=.brohn_tp_trial_rows(a$trial_audit,a$responses),source=a$source,source_hash=brohn_hash(a),
    timing=a$timing_quality,evidence_level=a$evidence_level,saved_score=a$score,
    identity=a[c("id","task_id","task_definition_hash","compiled_hash","participant_id","participant_linkage","session_id","attempt_id")])
}
brohn_task_plot_native <- function(evidence,report,reference) {
  brohn_require(identical(evidence$schema,"brohn-native-task-export/1.0")&&identical(evidence$run_id,reference$run_id)&&
    identical(evidence$evidence$events_hash,reference$events_hash),"The complete original journal differs from this report's saved session evidence.")
  task<-evidence$registry$task;frozen<-brohn_find(report$provenance$design$blocks,task$id)
  brohn_require(!is.null(frozen)&&identical(brohn_hash(task),brohn_hash(frozen)),"The native task differs from the report's frozen definition.")
  compiled<-evidence$registry$protocols[[1L]]$compiled;trials<-Filter(function(t)identical(t$type,"task_trial"),compiled$timeline)
  brohn_require(length(trials)==length(evidence$rows)&&identical(brohn_ids(trials),vapply(evidence$rows,`[[`,character(1),"trial_id")),"Every native terminal row must match the exact original trial order.")
  nullable<-function(x)if(is.null(x)||identical(x,""))NULL else x
  responses<-lapply(evidence$rows,function(r)list(trial_id=r$trial_id,presented=identical(r$presented,"true"),outcome=r$outcome,
    response_code=nullable(r$first_code),final_code=nullable(r$final_code),first_correct=identical(r$first_correct,"true"),
    first_response_ms=if(is.null(nullable(r$first_response_ms)))NULL else as.numeric(r$first_response_ms),
    final_correct_ms=if(is.null(nullable(r$final_correct_ms)))NULL else as.numeric(r$final_correct_ms),
    first_response_ms_source=r$first_response_ms,final_correct_ms_source=r$final_correct_ms,missing_reason=nullable(r$missing_reason)))
  audits<-lapply(seq_along(trials),function(i).brohn_task_import_trial_audit(trials[[i]],responses[[i]],i,task$profile,TRUE))
  list(schema="brohn-task-trial-plot/1.0",kind="trials",id=brohn_hash(list(evidence$run_id,task$id)),label=paste(evidence$run_id,task$title,sep=" | "),
    profile=task$profile,origin=evidence$collection_origin,material_origin=evidence$material_origin,completion="completed",
    rows=.brohn_tp_trial_rows(audits,responses),source=evidence$evidence,source_hash=brohn_hash(evidence),evidence_level=evidence$evidence$level,
    timing=list(definition_known=TRUE,source_rt_definition=evidence$declarations$source_rt_definition,physical_timing_qualified=FALSE),
    identity=list(run_id=evidence$run_id,task_id=task$id,compiled_hash=evidence$evidence$compiled_hash),
    audit_policy="Trial dispositions describe the current registered profile rules, separately from the immutable saved score; no score is recalculated.")
}
brohn_task_plot_people <- function(a,metric) {
  brohn_require(identical(a$schema,"brohn-task-cohort/1.0"),"Choose a saved descriptive task cohort.")
  hit<-Filter(function(s)identical(s$metric,metric),a$summaries)
  brohn_require(length(hit)==1L,"Choose one exact saved cohort measure.");s<-hit[[1L]]
  rows<-Filter(function(p)identical(p$metric,metric),a$per_person)
  brohn_require(length(rows)<=5000L&&!anyDuplicated(vapply(rows,`[[`,character(1),"person_id")),"The person plot needs unique complete metric rows within the saved 5,000-person bound.")
  for(p in rows)brohn_require(identical(p$unit,s$unit)&&(is.null(p$value)||brohn_number(p$value))&&
    (is.null(p$value)||isTRUE(p$eligible_session_count>0L)&&isTRUE(p$eligible_attempt_count>0L)),"A person value has inconsistent unit or metric-specific support.")
  available<-sum(vapply(rows,function(p)!is.null(p$value),logical(1)))
  brohn_require(if(isTRUE(a$quality$fully_linked))length(rows)==s$selected_person_count&&available==s$contributing_person_count else !length(rows)&&is.null(s$mean),
    "Person rows do not cover this saved measure's complete linkage and support.")
  list(schema="brohn-task-person-plot/1.0",kind="people",id=paste0("metric:",metric),label=.brohn_tp_label(metric),metric=metric,unit=s$unit,
    rows=lapply(seq_along(rows),function(i)c(list(position=i),rows[[i]])),summary=s,source=a$provenance,source_hash=brohn_hash(a),
    origin=a$provenance$homogeneous$collection_origin,material_origin=a$provenance$homogeneous$material_origin,
    evidence_level=a$provenance$homogeneous$evidence_level,repeat_policy=a$provenance$plan$repeat_policy)
}
brohn_task_plot_load <- function(store,opened,selector) {
  hit<-Filter(function(x)identical(x$id,selector),opened$catalog);brohn_require(length(hit)==1L,"Choose a source in this exact saved report.")
  c<-hit[[1L]];r<-opened$record;b<-r$body
  if(c$kind=="people")model<-brohn_task_plot_people(b$analysis,c$metric) else if(c$kind=="imported") {
    a<-Filter(function(x)identical(x$id,c$attempt_id),b$analysis$task_attempts)[[1L]]
    task<-brohn_find(b$provenance$design$blocks,a$task_id)
    brohn_require(!is.null(task)&&identical(brohn_hash(task),a$task_definition_hash)&&identical(a$collection_origin,b$origin),"This administration differs from the report's frozen task or collection origin.")
    for(hash in c(a$source$original_hash,a$source$registry_object_hash))brohn_object_path(store,hash,verify=TRUE)
    model<-brohn_task_plot_attempt(a)
  } else {
    ref<-Filter(function(x)identical(x$run_id,c$run_id),b$provenance$runs);brohn_require(length(ref)==1L,"The saved native run identity is ambiguous.");ref<-ref[[1L]]
    snapshot<-brohn_run_protocol(store,c$run_id,b$study_id,r$project_id)
    brohn_require(identical(snapshot$protocol$design_hash,ref$design_hash)&&identical(snapshot$protocol$design_hash,b$provenance$design_hash)&&
      identical(as.numeric(snapshot$run$allocation_index),as.numeric(ref$allocation_index)),"The retained native protocol differs from this saved report.")
    hashes<-Filter(function(x)identical(x$run_id,c$run_id),b$provenance$run_evidence$runs)
    if(length(hashes))brohn_require(length(hashes)==1L&&identical(hashes[[1L]]$protocol_sha256,snapshot$hash),"The retained protocol bytes differ from the report's original evidence.")
    model<-brohn_task_plot_native(brohn_task_run_evidence(store,c$run_id,b$study_id,r$project_id,c$task_id),b,ref)
  }
  model$report_id<-r$id;model$report_revision<-r$revision;model$report_hash<-brohn_hash(b);model
}
brohn_task_plot_selection <- function(model,measure="first_response_ms",scope="all") {
  brohn_require(measure %in% c("first_response_ms","final_correct_ms")&&scope %in% c("all","scored"),"Choose a labelled recorded latency and trial scope.")
  rows<-if(model$kind=="people")model$rows else Filter(function(r)scope=="all"||isTRUE(r$profile_scored),model$rows)
  values<-vapply(rows,function(r){v<-if(model$kind=="people")r$value else r[[measure]];if(is.null(v))NA_real_ else v},numeric(1))
  finite<-values[is.finite(values)];bins<-list()
  if(length(finite)&&model$kind=="trials") {
    range<-range(finite);if(diff(range)==0)range<-c(max(0,range[[1L]]-.5),range[[2L]]+.5)
    # Twenty fixed equal-width descriptive bins over every selected raw value.
    breaks<-seq(range[[1L]],range[[2L]],length.out=21L)
    # Exact right-closed intervals, without histogram boundary fuzz. Clamp only
    # the known minimum into the inclusive first bin; no measurement changes.
    counts<-tabulate(findInterval(finite,breaks,left.open=TRUE,all.inside=TRUE),nbins=20L)
    bins<-lapply(seq_along(counts),function(i)list(lower_ms=breaks[[i]],upper_ms=breaks[[i+1L]],count=counts[[i]],lower_inclusive=i==1L,upper_inclusive=TRUE))
  }
  list(model=model,measure=if(model$kind=="people")model$metric else measure,scope=scope,rows=rows,values=values,bins=bins,available=length(finite),missing=sum(!is.finite(values)),
    label=if(model$kind=="people")model$label else if(measure=="first_response_ms")"First-response latency" else
      if(identical(model$profile,"sciat-brohn-response-window-im100/1.0"))"Correct first-response latency" else "Final-correct latency",
    unit=if(model$kind=="people")model$unit else "ms")
}
brohn_task_plot_export <- function(view) list(schema="brohn-task-plot-export/1.0",report_id=view$model$report_id,
  report_revision=view$model$report_revision,report_hash=view$model$report_hash,source_hash=view$model$source_hash,
  selection=list(source_id=view$model$id,measure=view$measure,scope=view$scope),
  complete_source=view$model,selected_rows=view$rows,distribution_bins=if(view$model$kind=="trials")view$bins else NULL,
  interpretation="Plots preserve saved raw values and missing support. They do not rescore a task, pool people and trials, or add inference.")
