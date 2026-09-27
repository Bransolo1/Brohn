# Exact saved task-display preparation and pure evidence validation. No source
# scientific reads, jobs or subprocess probes occur merely by loading this module.
# Source/runtime identity is captured once, before any request can be queued.
.brohn_td_profile <- "saved-task-display/0.1"
.brohn_td_version <- function(profile) {brohn_require(profile %in% c("saved-task-display/0.1","saved-task-display/0.2"),"Choose a registered task preparation profile.");sub("saved-task-display/","",profile,fixed=TRUE)}
.brohn_td_schema <- function(prefix,profile)paste0(prefix,"/",.brohn_td_version(profile))
.brohn_td_admission <- function(profile)if(.brohn_td_version(profile)=="0.2")"task-choice-findings/0.1"else"task-findings/0.1"
.brohn_td_families <- c("native_questionnaire","imported_implicit","saved_task_cohort")
.brohn_td_profiles <- c("iat-gnb2003-d1/1.0","biat-nosek2014-goodfocal/1.0","aat-keyboard-cue-balanced/1.0",
  "rt-deary-liewald-simple/1.0","rt-deary-liewald-choice/1.0","sciat-brohn-response-window-im100/1.0","gnat-brohn-single-target/1.0")
.brohn_td_files <- c("R/platform-task-display.R","R/platform-task-display-sources.R","R/platform-core.R","R/platform-store.R",
  "R/platform-methods.R","R/platform-task-import.R","R/platform-gnat.R","R/platform-gnat-import.R",
  "R/platform-sciat-window.R","R/platform-sciat-window-delivery.R","R/platform-sciat-window-score.R",
  "R/platform-task-evidence.R","R/platform-task-cohort.R","R/platform-task-cohort-storage.R","R/platform-task-plots.R",
  "R/platform-run-evidence.R","R/platform-delivery.R","R/platform-question-revision.R","R/platform-question-revision-delivery.R",
  "R/platform-participant-equipment.R","R/platform-signal-values.R","R/platform-questionnaire-artifacts.R",
  "R/platform-report-package-sources.R","R/platform-report-package-authority.R","R/platform-publication.R","R/platform-paired-plots.R",
  "R/platform-scales.R","R/platform-scale-comparisons.R","R/platform-task-delivery.R","R/platform-question-materials.R",
  "R/platform-question-sections.R","R/platform-task-import-storage.R","R/platform-library.R","R/platform-questionnaire-artifact-storage.R",
  "R/platform-questionnaire-index.R","R/platform-questionnaire-explorer.R","R/platform-clock-map.R","R/platform-hosted-profile.R",
  "R/platform-choice-display.R","R/platform-choice-display-sources.R","R/platform-maxdiff.R","R/platform-maxdiff-import.R","R/platform-maxdiff-platform.R","R/platform-maxdiff-plots.R")
.brohn_td_same <- function(a,b)identical(brohn_json(a),brohn_json(b))
.brohn_td_bool <- function(x)is.logical(x)&&length(x)==1L&&!is.na(x)
.brohn_td_sha <- function(x)is.character(x)&&length(x)==1L&&!is.na(x)&&grepl("^[a-f0-9]{64}$",x)
.brohn_td_object_ref <- function(x)list(hash=brohn_default(x$hash,x$sha256),bytes=brohn_default(x$bytes,x$size),media_type=x$media_type)
.brohn_td_loaded <- stats::setNames(lapply(.brohn_td_files,function(p)if(file.exists(p))digest::digest(file=p,algo="sha256")else NULL),.brohn_td_files)
.brohn_td_runtime <- list(R=as.character(getRversion()),jsonlite=as.character(utils::packageVersion("jsonlite")),digest=as.character(utils::packageVersion("digest")))
brohn_task_display_implementation <- function(preparation_profile=.brohn_td_profile) {
  .brohn_td_version(preparation_profile)
  brohn_require(all(vapply(.brohn_td_loaded,.brohn_td_sha,logical(1))),"The saved-task display installation is incomplete. Restart after installing its exact source files.")
  list(schema=.brohn_td_schema("brohn-task-display-implementation",preparation_profile),profile=preparation_profile,sources=.brohn_td_loaded,runtime=.brohn_td_runtime)
}
.brohn_td_check_code <- function(implementation) {
  brohn_require(.brohn_td_same(implementation,brohn_task_display_implementation(implementation$profile))&&all(vapply(names(implementation$sources),function(p)
    file.exists(p)&&identical(digest::digest(file=p,algo="sha256"),implementation$sources[[p]]),logical(1))),
    "The task preparation installation changed after loading. Restart with the intended code and prepare a new report version.")
  invisible(TRUE)
}
.brohn_td_implementation_ref <- function(x)list(profile=x$profile,hash=brohn_hash(x))
brohn_task_display_implementation_ref <- function(preparation_profile=.brohn_td_profile) .brohn_td_implementation_ref(brohn_task_display_implementation(preparation_profile))
.brohn_td_family <- function(analysis) {
  if(identical(analysis$kind,"questionnaire")&&length(analysis$task_scores)>0L)return("native_questionnaire")
  if(identical(analysis$kind,"implicit")&&identical(analysis$parameters$schema,"brohn-implicit-csv-import/1.0"))return("imported_implicit")
  if(identical(analysis$kind,"implicit_cohort")&&identical(analysis$schema,"brohn-task-cohort/1.0"))return("saved_task_cohort")
  stop("This exact source has no registered complete task-display family.",call.=FALSE)
}
.brohn_td_score <- function(score) {
  brohn_require(is.list(score)&&score$profile %in% .brohn_td_profiles&&.brohn_td_bool(score$eligible)&&brohn_array(score$metrics)&&
    score$status %in% c("unavailable","excluded","computed","partial"),"Saved task score identity/status is unsupported.")
  profile<-score$profile;recipe<-score$scoring_recipe
  accepted<-identical(score$schema_version,"brohn-task-score/1.0")&&is.null(recipe)
  if(grepl("^rt-",profile))accepted<-accepted||(identical(score$schema_version,"brohn-task-score/1.1")&&identical(recipe,"brohn-rt-metric-support/1.0"))
  if(startsWith(profile,"sciat-"))accepted<-identical(score$schema_version,"brohn-task-score/1.0")&&identical(recipe,"brohn-sciat-response-window-score/1.0")
  if(startsWith(profile,"gnat-"))accepted<-identical(score$schema_version,"brohn-task-score/1.0")&&identical(recipe,"brohn-gnat-single-target-score/1.0")
  brohn_require(accepted&&.brohn_td_sha(score$design_hash),"Preserve a supported exact saved score version and task definition.")
  required<-c("schema_version","task_id","profile","origin","design_hash","status","eligible","metrics","counts","limitations")
  allowed<-union(.brohn_td_field_contract()[[paste0("score:",profile)]][["$"]],"reason")
  brohn_fields(score,required,setdiff(allowed,required),"Exact saved task score")
  .brohn_td_closed_fields(score,paste0("score:",profile))
  specs<-.brohn_task_cohort_specs(profile);names<-vapply(score$metrics,function(m){
    matches<-Filter(function(s)identical(s$name,m$name),specs)
    brohn_require(length(matches)==1L&&identical(m$unit,matches[[1L]]$unit)&&(is.null(m$value)||brohn_number(m$value)),"Saved metric name/unit/value is invalid.")
    if(identical(score$schema_version,"brohn-task-score/1.1"))brohn_require(.brohn_td_bool(m$eligible)&&is.list(m$support)&&(!isTRUE(m$eligible)||!is.null(m$value)),"Saved RT metric needs its independent explicit support.")
    m$name},character(1))
  brohn_require(!anyDuplicated(names),"Saved task metrics cannot duplicate a measure.")
  if(identical(score$schema_version,"brohn-task-score/1.1"))brohn_require(identical(score$eligible,any(vapply(score$metrics,function(m)isTRUE(m$eligible),logical(1)))),"Saved RT aggregate and metric support disagree.")
  invisible(score)
}
.brohn_td_trial_rows <- function(model,audits,responses,profile) {
  brohn_require(identical(model$schema,"brohn-task-trial-plot/1.0")&&identical(model$kind,"trials")&&identical(model$profile,profile)&&
    brohn_array(model$rows)&&length(model$rows)==length(audits)&&length(audits)>0L&&length(audits)<=20000L,"Complete task model does not cover every original position.")
  ids<-vapply(audits,`[[`,character(1),"trial_id");rid<-vapply(responses,`[[`,character(1),"trial_id")
  brohn_require(!anyDuplicated(ids)&&!anyDuplicated(rid)&&all(rid %in% ids),"Original task response/audit identities are invalid.")
  for(i in seq_along(audits)){
    audit<-audits[[i]];row<-model$rows[[i]];j<-match(audit$trial_id,rid);r<-if(is.na(j))NULL else responses[[j]]
    brohn_require(.brohn_td_bool(audit$derived)&&.brohn_td_bool(audit$profile_scored)&&.brohn_td_bool(row$derived_missing)&&.brohn_td_bool(row$profile_scored)&&
      identical(audit$derived,is.null(r))&&identical(row$derived_missing,audit$derived)&&identical(row$profile_scored,audit$profile_scored)&&row$position==i,
      "Task display position, missingness or profile flag differs from its exact source.")
    for(key in c("trial_id","block_id","source_row","score_block","category_id","action","disposition","scoring_latency_ms","original_fast_below_300"))
      brohn_require(.brohn_td_same(row[[key]],audit[[key]]),paste("Task display altered saved audit field",key))
    for(key in c("presented","outcome","first_correct","response_code","final_code","first_response_ms","final_correct_ms","first_response_ms_source","final_correct_ms_source"))
      brohn_require(.brohn_td_same(row[[key]],r[[key]]),paste("Task display altered original response field",key))
    if(!is.null(r)){
      brohn_require(.brohn_td_bool(r$presented)&&r$outcome %in% c("correct","incorrect","timeout","interrupted","not_presented","hit","miss","false_alarm","correct_rejection"),"Saved response outcome/presentation is invalid.")
      for(key in c("first_response_ms","final_correct_ms"))brohn_require(is.null(r[[key]])||brohn_number(r[[key]],0),"Original task latency is neither finite nor absent.")
      if(identical(profile,"gnat-brohn-single-target/1.0")){
        withheld<-isTRUE(r$presented)&&r$outcome %in% c("miss","correct_rejection")
        brohn_require(.brohn_td_bool(row$withholding_observed)&&identical(row$withholding_observed,withheld),"GNAT withholding flag is not its original observed outcome.")
        if(withheld)brohn_require(is.null(r$response_ms)&&is.null(r$first_response_ms)&&is.null(r$response_code)&&is.null(r$final_correct_ms)&&
          identical(r$correct,r$outcome=="correct_rejection"),"Observed GNAT withholding cannot gain a key, latency or changed accuracy.")
      }else brohn_require(.brohn_td_bool(r$first_correct),"Task response first accuracy must remain an explicit boolean.")
    }
  }
  invisible(TRUE)
}
.brohn_td_build_evidence <- function(report,native_evidence,implementation) {
  a<-report$complete_analysis;b<-report$saved_body;family<-.brohn_td_family(a)
  source<-list(report_ref=report$ref,analysis_hash=brohn_hash(a),result_object=.brohn_td_object_ref(b$result_object))
  admins<-models<-list();received<-0L
  if(family=="saved_task_cohort")models<-lapply(a$summaries,function(s)list(key=brohn_hash(list(report_ref=report$ref,metric=s$metric)),metric=s$metric,plot_model=brohn_task_plot_people(a,s$metric))) else {
    for(i in seq_along(a$task_scores)){
      score<-a$task_scores[[i]];.brohn_td_score(score)
      binding<-list(index=i,hash=brohn_hash(score),task_id=score$task_id,task_definition_hash=score$design_hash,profile=score$profile,schema_version=score$schema_version,scoring_recipe=score$scoring_recipe,attempt_index=NULL,attempt_hash=NULL)
      if(family=="imported_implicit"){
        indices<-which(vapply(a$task_attempts,function(x)identical(x$id,score$attempt_id)&&.brohn_td_same(x$score,score),logical(1)))
        brohn_require(length(indices)==1L,"The original task score has no unique exact canonical administration.")
        binding$attempt_index<-indices[[1L]];attempt<-a$task_attempts[[indices[[1L]]]];binding$attempt_hash<-brohn_hash(attempt)
        model<-brohn_task_plot_attempt(attempt);ex<-NULL;kind<-"imported";received<-received+length(attempt$responses)
        identity<-list(kind=kind,canonical_attempt_id=attempt$id,source_attempt_id=attempt$source_attempt_id,source_collection_id=attempt$source_collection_id,participant_id=attempt$participant_id,session_id=attempt$session_id,participant_linkage=attempt$participant_linkage)
        key<-brohn_hash(list(report_ref=report$ref,source_kind=kind,run_id=NULL,task_id=attempt$task_id,attempt_id=attempt$id));origin<-"saved_import_audit"
        policy<-"Display uses the original saved import trial audit and declared summary responses; no journal replay or score recalculation."
      }else{
        matching<-Filter(function(x)identical(x$run_id,score$session_id)&&identical(x$task_id,score$task_id),native_evidence)
        brohn_require(length(matching)==1L,"The saved native score has no unique original terminal evidence.")
        ex<-matching[[1L]];reference<-Filter(function(x)identical(x$run_id,score$session_id),b$provenance$runs)
        brohn_require(length(reference)==1L,"The native source run is ambiguous.")
        model<-brohn_task_plot_native(ex,b,reference[[1L]]);kind<-"native";received<-received+length(ex$rows)
        identity<-list(kind=kind,run_id=ex$run_id,task_id=ex$task_id,task_step_id=ex$task_step_id,score_person_id=score$participant_id,evidence_person_id=ex$rows[[1L]]$participant_id,
          participant_linkage=score$participant_linkage,score_session_id=score$session_id,evidence_session_id=ex$rows[[1L]]$session_id)
        key<-brohn_hash(list(report_ref=report$ref,source_kind=kind,run_id=ex$run_id,task_id=ex$task_id,attempt_id=NULL));origin<-"prepared_registered_rules"
        policy<-model$audit_policy
      }
      admins[[length(admins)+1L]]<-list(key=key,source_kind=kind,score_binding=binding,identity_binding=identity,terminal_evidence=ex,plot_model=model,
        display_audit=list(origin=origin,implementation_hash=brohn_hash(implementation),source_binding_hash=brohn_hash(list(source=source,score_binding=binding)),policy=policy))
    }
  }
  cohort<-family=="saved_task_cohort"
  coverage<-list(saved_analysis=list(state="complete",analysis_hash=brohn_hash(a)),score_count=length(a$task_scores),administration_count=length(admins),
    expected_position_count=if(cohort)NULL else sum(vapply(admins,function(x)length(x$plot_model$rows),integer(1))),received_response_count=if(cohort)NULL else received,
    cohort_metric_count=length(models),terminal_evidence=list(state=if(cohort)"not_applicable"else"complete",reason=if(cohort)"Original administration reports are not implicitly selected for full trial export."else NULL),
    original_journal_bytes_included=FALSE,raw_recordings_included=FALSE)
  result<-list(schema=.brohn_td_schema("brohn-task-display-evidence",implementation$profile),source_family=family,source=source,implementation=implementation,administrations=admins,cohort_models=models,coverage=coverage)
  brohn_validate_task_display_evidence(result,report);result
}
.brohn_td_catalog <- function(evidence,report) {
  if(evidence$source_family=="saved_task_cohort")return(lapply(evidence$cohort_models,function(item){m<-item$plot_model
    list(key=item$key,kind="cohort_metric",label=m$label,profile=report$complete_analysis$provenance$homogeneous$profile,completion=NULL,metric=item$metric,score_index=NULL,
      compatible_charts=list("people"),compatible_measures=list(),default_measure=NULL,expected_positions=NULL,reason=m$summary$reason,
      model_hash=brohn_hash(m),row_counts=list(all=length(m$rows),scored=NULL,score_rows=NULL))}))
  lapply(evidence$administrations,function(item){m<-item$plot_model;s<-report$complete_analysis$task_scores[[item$score_binding$index]]
    gnat<-identical(m$profile,"gnat-brohn-single-target/1.0");final<-grepl("^(iat-|biat-)",m$profile)
    list(key=item$key,kind="administration",label=m$label,profile=m$profile,completion=m$completion,metric=NULL,score_index=item$score_binding$index,
      compatible_charts=if(gnat)list("chronology","distribution","outcomes")else list("chronology","distribution"),
      compatible_measures=if(gnat)list("first_response_ms")else list("first_response_ms","final_correct_ms"),default_measure=if(final)"final_correct_ms"else"first_response_ms",
      expected_positions=length(m$rows),reason=s$reason,model_hash=brohn_hash(m),row_counts=list(all=length(m$rows),scored=sum(vapply(m$rows,`[[`,logical(1),"profile_scored")),score_rows=max(1L,length(s$metrics))))})
}
.brohn_td_companion_catalog <- function(report) {
  b<-report$saved_body;b$analysis<-report$complete_analysis
  if(!length(b$analysis$contrasts))return(list())
  lapply(.brohn_pp_catalog(b),function(c){m<-brohn_paired_plot_model(b,c$id,report$ref$body_hash)
    list(comparison_id=c$id,contrast_hash=brohn_hash(m$saved_contrast),model_hash=brohn_hash(m),status=m$status,
      people_count=length(m$people),session_count=length(m$sessions),observation_count=length(m$observations),label=m$label,reason=m$reason)})
}
.brohn_td_context <- function(store,report_ref,preparation_profile=.brohn_td_profile) {
  m<-.brohn_rpk_source_metadata(store,list(report_ref),source_admission=.brohn_td_admission(preparation_profile))
  selected<-Filter(function(x).brohn_td_same(x$ref,report_ref),m$reports)
  brohn_require(length(selected)==1L&&!is.null(selected[[1L]]$source_family),"Choose an exact supported task report.")
  fields<-c("ref","study_id","origin","design_hash","source_family","result_object","questionnaire_artifact","native_runs","run_sources","import_source","registry","cohort_sources","cohort_administrations")
  list(metadata=m,selected=selected[[1L]],closure=list(reports=lapply(m$reports,function(x)stats::setNames(lapply(fields,function(k)x[[k]]),fields)),
    objects=lapply(m$objects,.brohn_td_object_ref)))
}
.brohn_task_display_request <- function(store,report_ref,implementation_ref=NULL) {
  authority<-brohn_report_package_queue_authority(store,"task_display",report_ref$project_id)
  preparation_profile<-if(is.null(implementation_ref)).brohn_td_profile else implementation_ref$profile
  implementation<-brohn_task_display_implementation(preparation_profile);actual<-.brohn_td_implementation_ref(implementation)
  if(!is.null(implementation_ref))brohn_require(.brohn_td_same(implementation_ref,actual),"The pinned task preparation code changed. Review and prepare a new report intent explicitly.")
  c<-.brohn_td_context(store,report_ref,preparation_profile);m<-c$selected
  r<-list(schema=.brohn_td_schema("brohn-task-display-job",preparation_profile),project_id=report_ref$project_id,study_id=m$study_id,report_ref=report_ref,source_family=m$source_family,
    analysis_descriptor=list(result_object=.brohn_td_object_ref(m$result_object),packed=m$questionnaire_artifact),original_closure=c$closure,
    preparation_profile=preparation_profile,implementation=implementation,authority=authority)
  r$content_fingerprint<-brohn_hash(r[setdiff(names(r),"authority")]);r
}
brohn_queue_task_display <- function(store,report_ref,retry=FALSE,implementation_ref=NULL) {
  r<-.brohn_task_display_request(store,report_ref,implementation_ref)
  brohn_store_batch(store,function(){old<-.brohn_rpk_latest_job(store,"task_display",r$content_fingerprint)
    if(!is.null(old)&&(!isTRUE(retry)||old$status %in% c("queued","running","succeeded")))return(old)
    brohn_enqueue_job(store,"task_display",r,paste0("task-display:",r$content_fingerprint,if(isTRUE(retry))paste0(":",brohn_id("retry"))else""))})
}
brohn_task_display_input <- function(store,job,verify=FALSE) {
  store<-brohn_report_package_job_authorize(store,job);r<-job$request
  brohn_fields(r,c("schema","project_id","study_id","report_ref","source_family","analysis_descriptor","original_closure","preparation_profile","implementation","authority","content_fingerprint"),label="Task display request")
  brohn_require(identical(job$operation,"task_display")&&identical(r$schema,.brohn_td_schema("brohn-task-display-job",r$preparation_profile))&&
    .brohn_td_same(r$implementation,brohn_task_display_implementation(r$preparation_profile))&&identical(r$content_fingerprint,brohn_hash(r[setdiff(names(r),c("authority","content_fingerprint"))])),"Task preparation source/code identity changed.")
  c<-.brohn_td_context(store,r$report_ref,r$preparation_profile);brohn_require(.brohn_td_same(c$closure,r$original_closure),"Exact original task sources or current permission changed.")
  list(schema="brohn-analysis-input/1.0",operation="task_display",project_id=r$project_id,report_ref=r$report_ref,content_fingerprint=r$content_fingerprint)
}
.brohn_td_transport_receipts <- function(transport,report) {
  b<-report$saved_body;items<-transport$run_evidence$runs;expected<-b$provenance$run_evidence$runs
  brohn_require(length(items)==length(expected)&&length(items)==length(b$provenance$runs),"Native snapshot does not cover exact original producer membership.")
  total<-0
  for(item in items){i<-Filter(function(x)identical(x$run_id,item$metadata$id),expected)
    brohn_require(length(i)==1L,"Native snapshot run is absent or duplicated in original scientific evidence.");i<-i[[1L]]
    actual<-list(run_id=item$metadata$id,protocol_sha256=item$protocol$sha256,protocol_bytes=item$protocol$bytes,journal_sha256=item$journal$sha256,journal_bytes=item$journal$bytes,journal_rows_hash=item$journal$rows_hash,event_count=item$journal$event_count,final_sequence=item$journal$final_sequence)
    brohn_require(.brohn_td_same(actual,i)&&item$journal$bytes<=64*1024^2,"Native snapshot differs from original producer bytes or exceeds the per-run bound.");total<-total+item$journal$bytes
  }
  brohn_require(total<=256*1024^2,"Native original journals exceed the complete task-display profile.");invisible(TRUE)
}
.brohn_td_import_binding <- function(report,registry=NULL) {
  a<-report$complete_analysis;m<-a$parameters$mapping;src<-a$parameters$source
  brohn_require(identical(a$parameters$schema,"brohn-implicit-csv-import/1.0")&&identical(brohn_hash(a$source_rows),a$source_rows_hash),"Complete original import rows changed.")
  for(i in seq_along(a$source_rows)){
    row<-a$source_rows[[i]]
    brohn_require(row$source_row==i&&.brohn_td_bool(row$selected)&&identical(row$source_row_hash,brohn_hash(row$original_cells))&&
      identical(row$id,paste0("task-row-",brohn_hash(list(source_hash=src$hash,source_row=i)))),"Original imported row identity/hash/order changed.")
  }
  if(!is.null(registry))brohn_require(identical(brohn_hash(registry),a$parameters$registry_canonical_hash)&&
    identical(brohn_hash(registry$task),a$parameters$selected_task_hash),"Exact original imported task registry changed.")
  used<-integer()
  for(attempt in a$task_attempts){
    rows<-unlist(attempt$source$selected_original_rows,use.names=FALSE)
    brohn_require(length(rows)==length(attempt$responses)&&!anyDuplicated(rows)&&all(rows>=1&rows<=length(a$source_rows))&&
      all(vapply(a$source_rows[rows],`[[`,logical(1),"selected"))&&identical(brohn_hash(a$source_rows[rows]),attempt$source$selected_rows_hash)&&
      identical(attempt$source$mapping_hash,brohn_hash(m))&&identical(attempt$source$original_hash,src$hash)&&
      identical(attempt$source$registry_object_hash,src$registry_object_hash),"Original administration row/mapping/registry closure changed.")
    used<-c(used,rows)
    if(is.null(registry))next
    tables<-Filter(function(x)identical(x$id,attempt$protocol_id),registry$protocols)
    brohn_require(length(tables)==1L&&identical(tables[[1L]]$compiled_hash,attempt$compiled_hash)&&
      identical(brohn_hash(tables[[1L]]$compiled),attempt$compiled_hash),"Imported administration lost its exact compiled protocol.")
    trials<-Filter(function(x)identical(x$type,"task_trial"),tables[[1L]]$compiled$timeline)
    brohn_require(length(trials)==length(attempt$trial_audit),"Original import audit omits expected positions.")
    for(j in seq_along(trials)){
      trial<-trials[[j]];audit<-attempt$trial_audit[[j]]
      brohn_require(identical(audit$trial_id,trial$id)&&identical(audit$block_id,trial$block_id)&&identical(audit$profile_scored,isTRUE(trial$scored)),"Original import audit differs from its frozen trial identity.")
    }
    for(j in seq_along(rows)){
      i<-rows[[j]];raw<-a$source_rows[[i]]$original_cells
      fields<-.brohn_task_import_columns(m$adapter);cells<-lapply(fields,function(k)raw[[m[[k]]]]);names(cells)<-sub("_column$","",fields)
      brohn_require(all(vapply(cells,function(x)is.character(x)&&length(x)==1L&&!is.na(x),logical(1)))&&
        identical(cells$participant,attempt$participant_id)&&identical(cells$session,attempt$session_id)&&identical(cells$attempt,attempt$source_attempt_id)&&
        identical(cells$protocol,attempt$protocol_id)&&identical(.brohn_task_import_boolean(cells$participant_linkage,"participant linkage",i),attempt$participant_linkage),"Mapped original import identity fields changed.")
      ordinal<-match(cells$trial,vapply(trials,`[[`,character(1),"id"))
      brohn_require(!is.na(ordinal)&&identical(as.numeric(cells$presentation_index),as.numeric(ordinal)),"Mapped original import position changed.")
      response<-if(identical(attempt$profile,"gnat-brohn-single-target/1.0"))
        .brohn_gnat_import_response(cells,trials[[ordinal]],i,isTRUE(attempt$timing_quality$definitions_known))else
        .brohn_task_import_response(cells,trials[[ordinal]],i,isTRUE(attempt$timing_quality$definitions_known))
      brohn_require(.brohn_td_same(response,attempt$responses[[j]]),"Saved imported response differs from its mapped original cells; no recalculation is substituted.")
    }
  }
  brohn_require(!anyDuplicated(used)&&setequal(used,which(vapply(a$source_rows,`[[`,logical(1),"selected"))),"Complete imported administration inventory omits or duplicates selected source rows.")
  invisible(TRUE)
}
.brohn_td_complete_source_check <- function(reports,registries=list(),source_admission="task-findings/0.1") {
  byref<-stats::setNames(reports,vapply(reports,function(x)brohn_hash(x$ref),character(1)))
  for(report in reports){a<-report$complete_analysis;b<-report$saved_body
    if(identical(source_admission,"task-choice-findings/0.1"))brohn_validate_complete_report_analysis(report,source_admission)
    if(identical(a$kind,"implicit")) .brohn_td_import_binding(report,registries[[a$parameters$source$registry_object_hash]])
    if(identical(a$kind,"implicit_cohort")){
      brohn_require(.brohn_td_same(a$provenance$plan,b$provenance$plan)&&.brohn_td_same(a$provenance$identity_map,b$provenance$identity_map)&&
        identical(a$provenance$plan_hash,brohn_hash(b$provenance$plan))&&identical(a$provenance$identity_map_hash,brohn_hash(b$provenance$identity_map)),"Saved cohort original plan/crosswalk changed.")
      for(source in b$provenance$source_reports){
        key<-brohn_hash(list(kind="report",id=source$id,revision=source$revision,body_hash=source$body_hash,project_id=report$ref$project_id));parent<-byref[[key]]
        brohn_require(!is.null(parent)&&identical(parent$saved_body$study_id,b$study_id)&&identical(parent$saved_body$provenance$design_hash,source$design_hash)&&
          identical(parent$saved_body$result_object$hash,source$result_object_hash)&&parent$saved_body$result_object$size==source$result_object_size,"Saved cohort lost an exact historical source report or original worker object.")
      }
      brohn_require(length(b$provenance$source_administrations)==length(a$membership)&&length(a$membership)==length(b$provenance$plan$membership),"Saved cohort administration inventory differs from its selected original plan.")
      for(i in seq_along(b$provenance$source_administrations)){
        link<-b$provenance$source_administrations[[i]];member<-a$membership[[i]];selected<-b$provenance$plan$membership[[i]]
        exact<-Filter(function(s)identical(s$id,link$report_id),b$provenance$source_reports)
        brohn_require(length(exact)==1L,"Saved cohort administration has no unique original source report reference.")
        e<-exact[[1L]];parent<-byref[[brohn_hash(list(kind="report",id=e$id,revision=e$revision,body_hash=e$body_hash,project_id=report$ref$project_id))]]
        attempts<-Filter(function(x)identical(x$id,link$attempt_id),parent$complete_analysis$task_attempts)
        brohn_require(length(attempts)==1L&&identical(brohn_hash(attempts[[1L]]),link$attempt_hash)&&
          .brohn_td_same(selected,link[c("attempt_id","attempt_hash")])&&identical(member$attempt_id,link$attempt_id)&&identical(member$attempt_hash,link$attempt_hash)&&
          .brohn_td_same(member$source,attempts[[1L]]$source),"Saved cohort source administration differs from its frozen membership/attempt hash.")
      }
    }
  };invisible(TRUE)
}
brohn_prepare_task_display_execution <- function(store,job,input,scratch) {
  store<-brohn_report_package_job_authorize(store,job)
  .brohn_td_check_code(job$request$implementation)
  brohn_require(.brohn_td_same(input,brohn_task_display_input(store,job,FALSE)),"Task display input changed before preparation.")
  c<-.brohn_td_context(store,job$request$report_ref,job$request$preparation_profile);handle<-.brohn_rpk_hold_sources(store,c$metadata);ok<-FALSE
  on.exit(if(!ok).brohn_rpk_release(handle),add=TRUE)
  all<-.brohn_rpk_complete_sources(store,handle,TRUE)$reports;.brohn_td_complete_source_check(all,source_admission=.brohn_td_admission(job$request$preparation_profile))
  report<-Filter(function(x).brohn_td_same(x$ref,job$request$report_ref),all)[[1L]];family<-.brohn_td_family(report$complete_analysis)
  native<-NULL
  if(family=="native_questionnaire"){
    refs<-report$saved_body$provenance$runs;first<-refs[[1L]]
    scope<-list(study_id=job$request$study_id,project_id=job$request$project_id,deployment_id=first$deployment_id,design_hash=first$design_hash,origin=report$saved_body$origin)
    native<-brohn_prepare_run_evidence_transport(store,job,scratch,lapply(refs,`[[`,"run_id"),scope);.brohn_td_transport_receipts(native,report)
    for(item in native$run_evidence$runs)for(descriptor in list(item$protocol,item$journal)){
      path<-file.path(scratch,descriptor$path);state<-handle$state;state$extra_guards<-c(state$extra_guards,list(.brohn_qexplorer_hold(path,descriptor$bytes)))
    }
  }
  registries<-list()
  for(m in c$metadata$reports)if(identical(m$source_family,"imported_implicit")){
    hash<-m$import_source$registry_object_hash
    if(is.null(registries[[hash]]))registries[[hash]]<-brohn_read_json_file(brohn_object_path(store,hash,FALSE),maximum=16*1024^2)
  }
  .brohn_td_complete_source_check(all,registries,.brohn_td_admission(job$request$preparation_profile))
  bundle<-list(schema=.brohn_td_schema("brohn-task-display-input-bundle",job$request$preparation_profile),report=report,guarded_reports=all,registries=registries,native_transport=native,implementation=job$request$implementation,request_hash=brohn_hash(job$request))
  path<-file.path(scratch,"task-display-input.json");brohn_require(!file.exists(path),"The task-display bundle already exists.")
  brohn_write_json_file(bundle,path,maximum=128*1024^2);state<-handle$state;state$extra_guards<-c(state$extra_guards,list(.brohn_qexplorer_hold(path,file.info(path)$size)))
  input$task_display<-list(schema=.brohn_td_schema("brohn-task-display-prepared-input",job$request$preparation_profile),bundle=list(file="task-display-input.json",sha256=digest::digest(file=path,algo="sha256"),bytes=as.numeric(file.info(path)$size)))
  brohn_report_package_sources_current(store,handle);brohn_report_package_job_authorize(store,job);ok<-TRUE;list(input=input,handle=handle)
}
brohn_task_display_sources_current <- function(store,handle)brohn_report_package_sources_current(store,handle)
brohn_release_task_display_sources <- function(handle).brohn_rpk_release(handle)
.brohn_td_bundle <- function(input,scratch) {
  descriptor<-input$task_display;brohn_fields(descriptor,c("schema","bundle"),label="Prepared task input")
  d<-descriptor$bundle;brohn_fields(d,c("file","sha256","bytes"),label="Sealed task bundle")
  brohn_require(descriptor$schema %in% c("brohn-task-display-prepared-input/0.1","brohn-task-display-prepared-input/0.2")&&identical(d$file,"task-display-input.json")&&.brohn_td_sha(d$sha256)&&brohn_number(d$bytes,1,128*1024^2,TRUE),"Prepared task bundle descriptor is invalid.")
  path<-normalizePath(file.path(scratch,d$file),winslash="/",mustWork=TRUE);root<-normalizePath(scratch,winslash="/",mustWork=TRUE)
  link<-Sys.readlink(path)
  brohn_require(identical(dirname(path),root)&&(is.na(link)||!nzchar(link))&&file.info(path)$size==d$bytes&&identical(digest::digest(file=path,algo="sha256"),d$sha256),"Prepared task bundle changed or left owned scratch.")
  bundle<-brohn_read_json_file(path,maximum=128*1024^2)
  brohn_require(identical(bundle$schema,.brohn_td_schema("brohn-task-display-input-bundle",bundle$implementation$profile))&&identical(descriptor$schema,.brohn_td_schema("brohn-task-display-prepared-input",bundle$implementation$profile))&&.brohn_td_same(bundle$report$ref,input$report_ref),"Prepared task bundle belongs to another report.");bundle
}
brohn_analyse_task_display <- function(input,scratch) {
  bundle<-.brohn_td_bundle(input,scratch);.brohn_td_check_code(bundle$implementation);report<-bundle$report;native<-list()
  if(!is.null(bundle$native_transport)){
    .brohn_td_transport_receipts(bundle$native_transport,report)
    original<-brohn_read_run_evidence_transport(bundle$native_transport,scratch,"task_display")
    for(run in original$runs){
      reference<-Filter(function(r)identical(r$run_id,run$id),report$saved_body$provenance$runs)
      brohn_require(length(reference)==1L&&identical(brohn_hash(original$events[[run$id]]),reference[[1L]]$events_hash),"Original parsed journal differs from its scientific report.")
      scores<-Filter(function(s)identical(s$session_id,run$id),report$complete_analysis$task_scores)
      for(score in scores){ex<-brohn_task_evidence_from_run(run,original$events[[run$id]],score$task_id)
        ex$evidence$saved_protocol_bytes_hash<-Filter(function(x)identical(x$metadata$id,run$id),bundle$native_transport$run_evidence$runs)[[1L]]$protocol$sha256
        native[[length(native)+1L]]<-ex}
    }
  }
  .brohn_td_complete_source_check(bundle$guarded_reports,bundle$registries,.brohn_td_admission(bundle$implementation$profile))
  evidence<-.brohn_td_build_evidence(report,native,bundle$implementation)
  brohn_require(sum(vapply(evidence$administrations,function(x)length(x$plot_model$rows),integer(1)))<=20000L,"Complete task positions exceed this display profile; no partial display was saved.")
  directory<-file.path(scratch,"artifacts");dir.create(directory,showWarnings=FALSE)
  path<-file.path(directory,"task-display.json");brohn_write_json_file(evidence,path,maximum=32*1024^2)
  list(task_display=list(schema=.brohn_td_schema("brohn-task-display-worker-result",bundle$implementation$profile),source_family=evidence$source_family,source=evidence$source,implementation=bundle$implementation,
    coverage=evidence$coverage,catalog=.brohn_td_catalog(evidence,report),companion_catalog=.brohn_td_companion_catalog(report),input_binding_hash=input$content_fingerprint,
    artifact=list(file="task-display.json",sha256=digest::digest(file=path,algo="sha256"),bytes=as.numeric(file.info(path)$size),media_type="application/json")))
}
brohn_publish_task_display <- function(store,output,scratch,job,input,output_path) {
  store<-brohn_report_package_job_authorize(store,job,"publish");.brohn_publication_job(store,job)
  .brohn_td_check_code(job$request$implementation)
  .brohn_publication_output_identity(output,job$request$implementation$sources)
  brohn_task_display_input(store,job,FALSE);bundle<-.brohn_td_bundle(input,scratch)
  brohn_require(identical(bundle$request_hash,brohn_hash(job$request))&&.brohn_td_same(bundle$implementation,job$request$implementation),"Prepared task input lost the original queued request identity.")
  m<-.brohn_td_context(store,job$request$report_ref,job$request$preparation_profile);sources<-.brohn_rpk_hold_sources(store,m$metadata)
  on.exit(.brohn_rpk_release(sources),add=TRUE)
  reports<-.brohn_rpk_complete_sources(store,sources,TRUE)$reports;.brohn_td_complete_source_check(reports,bundle$registries,.brohn_td_admission(job$request$preparation_profile))
  report<-Filter(function(x).brohn_td_same(x$ref,job$request$report_ref),reports)[[1L]]
  brohn_require(.brohn_td_same(report,bundle$report),"Task artifact source differs from its sealed original report.")
  output_guard<-.brohn_qexplorer_hold(output_path,file.info(output_path)$size);on.exit(.brohn_qexplorer_release(output_guard),add=TRUE)
  brohn_require(.brohn_td_same(brohn_read_json_file(output_path),output),"Task worker result changed before publication.")
  result<-output$report$task_display;brohn_fields(result,c("schema","source_family","source","implementation","coverage","catalog","companion_catalog","input_binding_hash","artifact"),label="Task worker result")
  brohn_require(identical(result$schema,.brohn_td_schema("brohn-task-display-worker-result",job$request$preparation_profile))&&identical(result$input_binding_hash,job$request$content_fingerprint)&&
    .brohn_td_same(result$implementation,job$request$implementation),"Task worker result has a foreign source/preparation identity.")
  a<-result$artifact;brohn_fields(a,c("file","sha256","bytes","media_type"),label="Complete task artifact")
  brohn_require(identical(a$file,"task-display.json")&&identical(a$media_type,"application/json")&&brohn_number(a$bytes,1,32*1024^2,TRUE)&&.brohn_td_sha(a$sha256),"Complete task artifact exceeds its bound or has an invalid identity.")
  path<-brohn_checked_artifact_path(store,file.path(scratch,"artifacts",a$file),scratch)
  guard<-.brohn_qexplorer_hold(path,a$bytes);on.exit(.brohn_qexplorer_release(guard),add=TRUE)
  brohn_require(file.info(path)$size==a$bytes&&identical(digest::digest(file=path,algo="sha256"),a$sha256),"Complete task artifact failed its exact byte identity.")
  evidence<-brohn_read_json_file(path,maximum=32*1024^2);brohn_validate_task_display_evidence(evidence,report)
  brohn_require(.brohn_td_same(evidence$source,result$source)&&identical(evidence$source_family,result$source_family)&&.brohn_td_same(evidence$implementation,result$implementation)&&
    .brohn_td_same(evidence$coverage,result$coverage)&&.brohn_td_same(.brohn_td_catalog(evidence,report),result$catalog)&&.brohn_td_same(.brohn_td_companion_catalog(report),result$companion_catalog),"Task worker metadata differs from its full verified artifact.")
  staged<-document<-NULL;committed<-FALSE
  on.exit({if(!is.null(document))brohn_close_publication(document$guard,committed);if(!is.null(staged))brohn_close_publication(staged$guard,committed)},add=TRUE)
  staged<-.brohn_publication_stage(store,job,list(list(key="task-display",kind="task-display",path=path,sha256=a$sha256,bytes=a$bytes,media_type=a$media_type)))
  id<-paste0("task-display-",sub("^job[_-]","",job$id));object<-staged$descriptors[[1L]]
  body<-list(schema=.brohn_td_schema("brohn-saved-task-display",job$request$preparation_profile),study_id=job$request$study_id,project_id=job$request$project_id,source_family=result$source_family,source=result$source,
    preparation_profile=job$request$preparation_profile,implementation=result$implementation,implementation_hash=brohn_hash(result$implementation),input_binding_hash=job$request$content_fingerprint,
    artifact=.brohn_td_object_ref(object),artifact_schema=.brohn_td_schema("brohn-task-display-evidence",job$request$preparation_profile),catalog=result$catalog,companion_catalog=result$companion_catalog,coverage=result$coverage,
    producer=list(job_id=job$id,attempt=job$attempt,request_hash=brohn_hash(job$request),worker_result_hash=digest::digest(file=output_path,algo="sha256")))
  brohn_require(nchar(brohn_json(body),type="bytes")<=2*1024^2,"Task catalog exceeds its complete metadata bound.")
  document<-.brohn_publication_stage_json(store,job,body,file.path(scratch,"published-task-display.json"))
  receipt<-brohn_store_batch(store,function(){
    brohn_report_package_sources_current(store,sources);brohn_report_package_job_fence(store,job)
    brohn_require(.brohn_td_same(.brohn_td_context(store,job$request$report_ref,job$request$preparation_profile)$closure,job$request$original_closure),"Task source authority changed before commit.")
    .brohn_cm_guard_check(list(output_guard,guard));.brohn_publication_register(store,staged)
    body$retained_document<-.brohn_td_object_ref(.brohn_publication_register(store,document)[[1L]])
    brohn_put_entity(store,"task_display",id,body,0L,job$request$project_id)
    brohn_complete_job(store,job$id,job$worker,job$token,list(task_display_id=id,report_id=job$request$report_ref$id,output_hash=body$retained_document$hash))
  });committed<-TRUE;receipt
}
.brohn_td_native_responses <- function(evidence) {
  trials<-Filter(function(t)identical(t$type,"task_trial"),evidence$registry$protocols[[1L]]$compiled$timeline)
  brohn_require(length(trials)==length(evidence$rows)&&identical(brohn_ids(trials),vapply(evidence$rows,`[[`,character(1),"trial_id")),"Native terminal evidence is not the complete original trial order.")
  nullable<-function(x)if(is.null(x)||identical(x,""))NULL else x
  responses<-lapply(seq_along(evidence$rows),function(i){r<-evidence$rows[[i]]
    if(identical(evidence$registry$task$profile,"gnat-brohn-single-target/1.0")){
      fields<-c(participant="participant_id",session="session_id",attempt="attempt_id",protocol="protocol_id",trial="trial_id")
      columns<-sub("_column$","",.brohn_gnat_import_columns())
      cells<-stats::setNames(lapply(columns,function(key)r[[if(key %in% names(fields))fields[[key]]else key]]),columns)
      return(.brohn_gnat_import_response(cells,trials[[i]],i,TRUE))
    }
    brohn_require(r$presented %in% c("true","false")&&r$first_correct %in% c("true","false"),"Native interchange boolean changed its representation.")
    list(trial_id=r$trial_id,presented=identical(r$presented,"true"),outcome=r$outcome,response_code=nullable(r$first_code),final_code=nullable(r$final_code),
      first_correct=identical(r$first_correct,"true"),first_response_ms=.brohn_task_import_decimal(r$first_response_ms,"first response",i),
      final_correct_ms=.brohn_task_import_decimal(r$final_correct_ms,"final correct",i),first_response_ms_source=r$first_response_ms,final_correct_ms_source=r$final_correct_ms,missing_reason=nullable(r$missing_reason))
  });list(trials=trials,responses=responses)
}
brohn_validate_task_display_evidence <- function(evidence,report) {
  brohn_fields(evidence,c("schema","source_family","source","implementation","administrations","cohort_models","coverage"),label="Saved task display evidence")
  brohn_require(identical(evidence$schema,.brohn_td_schema("brohn-task-display-evidence",evidence$implementation$profile))&&evidence$source_family %in% .brohn_td_families,
    "Unsupported saved task display evidence.")
  a<-report$complete_analysis;b<-report$saved_body
  admission<-.brohn_td_admission(evidence$implementation$profile)
  .brohn_td_analysis_fields(a,admission)
  if(admission=="task-choice-findings/0.1")brohn_validate_complete_report_analysis(report,admission)
  brohn_require(.brohn_td_same(evidence$source$report_ref,report$ref)&&identical(evidence$source_family,.brohn_td_family(a))&&
    identical(evidence$source$analysis_hash,brohn_hash(a))&&.brohn_td_same(evidence$source$result_object,.brohn_td_object_ref(b$result_object)),"Task evidence does not bind this exact complete scientific report.")
  brohn_fields(evidence$implementation,c("schema","profile","sources","runtime"),label="Saved preparation identity")
  brohn_require(identical(evidence$implementation$schema,.brohn_td_schema("brohn-task-display-implementation",evidence$implementation$profile))&&
    is.list(evidence$implementation$sources)&&length(evidence$implementation$sources)>0L&&all(vapply(evidence$implementation$sources,.brohn_td_sha,logical(1))),"Saved task preparation identity is invalid.")
  brohn_require(brohn_array(evidence$administrations)&&brohn_array(evidence$cohort_models),"Keep task administrations and cohort models as distinct arrays.")
  if(identical(evidence$source_family,"saved_task_cohort")){
    brohn_require(!length(evidence$administrations)&&length(evidence$cohort_models)==length(a$summaries),"Cohort display must cover every saved summary without inventing trial administrations.")
    for(i in seq_along(a$summaries)){
      item<-evidence$cohort_models[[i]];s<-a$summaries[[i]];model<-item$plot_model
      brohn_fields(item,c("key","metric","plot_model"),label="Saved cohort model")
      brohn_require(identical(item$key,brohn_hash(list(report_ref=report$ref,metric=s$metric)))&&identical(item$metric,s$metric)&&
        identical(model$schema,"brohn-task-person-plot/1.0")&&identical(model$source_hash,brohn_hash(a))&&.brohn_td_same(model$summary,s),"Saved cohort model changed a source metric or summary.")
      original<-Filter(function(p)identical(p$metric,s$metric),a$per_person)
      expected<-lapply(seq_along(original),function(j)c(list(position=j),original[[j]]))
      brohn_require(.brohn_td_same(model$rows,expected)&&.brohn_td_same(model$source,a$provenance),"Cohort display changed original person evidence or provenance.")
    }
  }else{
    brohn_require(length(evidence$administrations)==length(a$task_scores)&&length(a$task_scores)>0L&&!length(evidence$cohort_models),"Task display must cover every original saved score.")
    seen<-character()
    for(item in evidence$administrations){
      brohn_fields(item,c("key","source_kind","score_binding","identity_binding","terminal_evidence","plot_model","display_audit"),label="Saved task administration")
      sb<-item$score_binding;brohn_fields(sb,c("index","hash","task_id","task_definition_hash","profile","schema_version","scoring_recipe","attempt_index","attempt_hash"),label="Original saved score binding")
      brohn_require(brohn_number(sb$index,1,length(a$task_scores),TRUE),"Task display score index is invalid.")
      score<-a$task_scores[[sb$index]];.brohn_td_score(score)
      brohn_require(identical(sb$hash,brohn_hash(score))&&identical(sb$task_id,score$task_id)&&identical(sb$task_definition_hash,score$design_hash)&&
        identical(sb$profile,score$profile)&&identical(sb$schema_version,score$schema_version)&&.brohn_td_same(sb$scoring_recipe,score$scoring_recipe),"Original scientific score binding was altered.")
      seen<-c(seen,as.character(sb$index));id<-item$identity_binding;m<-item$plot_model
      brohn_require(identical(item$display_audit$implementation_hash,brohn_hash(evidence$implementation))&&
        identical(item$display_audit$source_binding_hash,brohn_hash(list(source=evidence$source,score_binding=sb))),"Prepared display audit lost its separate implementation/source identity.")
      if(identical(evidence$source_family,"imported_implicit")){
        brohn_require(identical(item$source_kind,"imported")&&identical(id$kind,"imported")&&is.null(item$terminal_evidence)&&brohn_number(sb$attempt_index,1,length(a$task_attempts),TRUE),"Imported display must refer to its complete canonical attempt.")
        attempt<-a$task_attempts[[sb$attempt_index]];.brohn_task_cohort_attempt(attempt)
        brohn_require(identical(sb$attempt_hash,brohn_hash(attempt))&&.brohn_td_same(attempt$score,score)&&.brohn_td_same(m$saved_score,score)&&identical(m$source_hash,brohn_hash(attempt))&&
          .brohn_td_same(id,list(kind="imported",canonical_attempt_id=attempt$id,source_attempt_id=attempt$source_attempt_id,source_collection_id=attempt$source_collection_id,participant_id=attempt$participant_id,session_id=attempt$session_id,participant_linkage=attempt$participant_linkage)),"Imported canonical/source/person identity differs from its exact score.")
        key<-brohn_hash(list(report_ref=report$ref,source_kind="imported",run_id=NULL,task_id=attempt$task_id,attempt_id=attempt$id))
        .brohn_td_trial_rows(m,attempt$trial_audit,attempt$responses,score$profile)
        brohn_require(identical(item$display_audit$origin,"saved_import_audit"),"Imported saved audit cannot claim a native replay.")
      }else{
        ex<-item$terminal_evidence
        brohn_require(identical(item$source_kind,"native")&&identical(id$kind,"native")&&is.null(sb$attempt_index)&&is.null(sb$attempt_hash)&&
          identical(ex$schema,"brohn-native-task-export/1.0")&&identical(ex$task_id,score$task_id)&&identical(ex$run_id,score$session_id),"Native terminal evidence differs from its saved score/run/task.")
        run<-Filter(function(r)identical(r$run_id,ex$run_id),b$provenance$runs)
        brohn_require(length(run)==1L&&identical(ex$evidence$events_hash,run[[1L]]$events_hash)&&identical(brohn_hash(ex$registry$task),score$design_hash)&&
          identical(m$source_hash,brohn_hash(ex))&&identical(m$profile,score$profile),"Native original journal/task/terminal model binding changed.")
        person<-unique(vapply(ex$rows,`[[`,character(1),"participant_id"));session<-unique(vapply(ex$rows,`[[`,character(1),"session_id"))
        brohn_require(length(person)==1L&&length(session)==1L&&.brohn_td_same(id,list(kind="native",run_id=ex$run_id,task_id=ex$task_id,task_step_id=ex$task_step_id,score_person_id=score$participant_id,evidence_person_id=person[[1L]],participant_linkage=score$participant_linkage,score_session_id=score$session_id,evidence_session_id=session[[1L]])),"Native score and terminal identity edge is invalid.")
        parsed<-.brohn_td_native_responses(ex);brohn_require(length(m$rows)==length(parsed$trials),"Native model omits terminal rows.")
        # Original producer audit remains in score. Prepared dispositions are
        # separately saved; validate their source/flags without rebuilding them.
        audits<-lapply(seq_along(m$rows),function(i){r<-m$rows[[i]];t<-parsed$trials[[i]]
          brohn_require(.brohn_td_bool(t$scored)&&identical(r$profile_scored,t$scored)&&identical(r$trial_id,t$id)&&identical(r$block_id,t$block_id),"Native model altered frozen profile positions.")
          c(r[c("trial_id","block_id","source_row","score_block","category_id","action","disposition","scoring_latency_ms","original_fast_below_300","profile_scored")],list(derived=FALSE))})
        .brohn_td_trial_rows(m,audits,parsed$responses,score$profile)
        brohn_require(identical(item$display_audit$origin,"prepared_registered_rules"),"Native display audit must remain separate from original scoring evidence.")
        key<-brohn_hash(list(report_ref=report$ref,source_kind="native",run_id=ex$run_id,task_id=ex$task_id,attempt_id=NULL))
      }
      brohn_require(identical(item$key,key),"Task administration key lost its full source identity.")
    }
    brohn_require(!anyDuplicated(seen),"A task display duplicated one score and omitted another.")
  }
  cov<-evidence$coverage
  brohn_fields(cov,c("saved_analysis","score_count","administration_count","expected_position_count","received_response_count","cohort_metric_count","terminal_evidence","original_journal_bytes_included","raw_recordings_included"),label="Complete task coverage")
  brohn_fields(cov$terminal_evidence,c("state","reason"),label="Task terminal coverage")
  cohort<-identical(evidence$source_family,"saved_task_cohort")
  brohn_require(cov$score_count==length(a$task_scores)&&cov$administration_count==length(evidence$administrations)&&cov$cohort_metric_count==length(evidence$cohort_models)&&
    identical(cov$terminal_evidence$state,if(cohort)"not_applicable"else"complete"),"Task collection coverage counts or applicability changed.")
  if(cohort)brohn_require(is.null(cov$expected_position_count)&&is.null(cov$received_response_count),"Cohort summaries cannot invent terminal-trial counts.")else{
    expected<-sum(vapply(evidence$administrations,function(x)length(x$plot_model$rows),integer(1)))
    received<-sum(vapply(evidence$administrations,function(x)if(x$source_kind=="native")length(x$terminal_evidence$rows)else length(a$task_attempts[[x$score_binding$attempt_index]]$responses),integer(1)))
    brohn_require(cov$expected_position_count==expected&&cov$received_response_count==received,"Task collection coverage differs from complete original rows.")
  }
  brohn_require(.brohn_td_same(cov$saved_analysis,list(state="complete",analysis_hash=brohn_hash(a)))&&identical(cov$original_journal_bytes_included,FALSE)&&identical(cov$raw_recordings_included,FALSE),"Task coverage cannot claim original journal bytes or alter saved-analysis completeness.")
  invisible(TRUE)
}
.brohn_td_closed_fields <- function(value,family) {
  fields<-.brohn_td_field_contract()[[family]];brohn_require(is.list(fields),"This exact task source family has no fixed field contract.")
  walk<-function(x,path="$"){
    if(is.null(x))return(invisible(NULL))
    allowed<-fields[[path]]
    # Existing producer assigns $reason <- NULL for eligible IAT/BIAT/SC-IAT,
    # which removes the field. Early exits retain it. Both are exact originals.
    if((startsWith(family,"score:")&&identical(path,"$"))||path %in% c("$.task_scores[]","$.task_attempts[].score"))allowed<-union(allowed,"reason")
    if(identical(allowed,"__mapped_original_cells__")){
      brohn_require(is.list(x)&&!is.null(names(x))&&!anyDuplicated(names(x))&&all(vapply(x,function(v)is.character(v)&&length(v)==1L&&!is.na(v),logical(1))),"Original CSV cells must retain their exact named text values.")
      return(invisible(NULL))
    }
    if(is.list(x)){
      if(!is.null(names(x))){
        brohn_require(!is.null(allowed)&&!anyDuplicated(names(x))&&all(names(x) %in% allowed),paste("Unregistered task scientific fields at",path))
        for(key in names(x))walk(x[[key]],paste0(path,".",key))
      }else for(item in x)walk(item,paste0(path,"[]"))
    }else brohn_require(is.null(allowed),paste("Expected the original scientific object at",path))
    invisible(NULL)
  };walk(value);invisible(TRUE)
}
.brohn_td_analysis_fields <- function(a,source_admission="task-findings/0.1") {
  source_admission<-.brohn_rpk_admission(source_admission)
  family<-.brohn_td_family(a)
  if(family=="native_questionnaire"){
    brohn_fields(a,c("kind","title","features","observations","contrasts","parameters","quality","limitations","task_scores"),c("scales","questionnaire_revision","choice_tasks"),"Complete native task questionnaire")
    brohn_require(identical(source_admission,"task-choice-findings/0.1")||!length(a$choice_tasks),"Choice-task scientific evidence needs its own complete adapter.")
  }else{
    allowed<-.brohn_td_field_contract()[[a$kind]][["$"]]
    brohn_fields(a,allowed,label="Complete imported/cohort task source")
    .brohn_td_closed_fields(a,a$kind)
  }
  brohn_require(brohn_array(a$task_scores)||family=="saved_task_cohort","Complete task scores must be an array.")
  if(family=="imported_implicit")brohn_require(brohn_array(a$task_attempts)&&brohn_array(a$source_rows)&&identical(brohn_hash(a$source_rows),a$source_rows_hash),"Original complete imported source rows changed.")
  if(family=="saved_task_cohort")brohn_require(.brohn_td_bool(a$quality$fully_linked)&&identical(a$quality$inference_performed,FALSE)&&
    (isTRUE(a$quality$fully_linked)||(is.null(a$quality$selected_person_count)&&!length(a$per_person)&&!length(a$per_session))),"Saved cohort linkage cannot invent a person count or new inference.")
  invisible(TRUE)
}

# Frozen conservative field inventory; generated from SCIENTIFIC-FIELD-INVENTORY.json.
# This fixed literal cannot be extended by incoming report data.
.brohn_td_field_contract <- local({
  fields <- list(
    "implicit" = list(
      "$" = c("kind","limitations","parameters","quality","source_rows","source_rows_hash","task_attempts","task_scores","title"),
      "$.parameters" = c("expected_trial_limit","identity_policy","mapping","missing_cell_policy","origin_verification","registry_canonical_hash","registry_size","registry_verification","row_limit","schema","selected_task_hash","source","source_row_order"),
      "$.parameters.mapping" = c("adapter","attempt_column","cell_id_column","correct_column","evidence_level","expected_action_column","final_code_column","final_correct_ms_column","first_code_column","first_correct_column","first_response_ms_column","missing_reason_column","origin_column","origin_statement","outcome_column","participant_column","participant_linkage_column","phase_column","presentation_index_column","presented_column","protocol_column","protocol_registry","response_code_column","response_ms_column","response_outcome_column","round_id_column","session_column","source_collection_id","source_rt_definition","source_software","task_column","task_id","terminal_response_rule","trial_column"),
      "$.parameters.mapping.protocol_registry" = c("bytes","canonical_hash","filename","hash","media_type","task_definition_hash"),
      "$.parameters.source" = c("hash","id","origin","registry_object_hash","revision"),
      "$.quality" = c("attempt_count","completed_attempt_count","derived_missing_trial_count","eligible_attempt_count","excluded_row_count","expected_trial_count","participant_count","participant_linkage","scientifically_qualified","selected_row_count","session_count","source_row_count","usable"),
      "$.source_rows[]" = c("declared_origin","declared_task_id","id","original_cells","reason","selected","source_row","source_row_hash"),
      "$.source_rows[].original_cells" = c("__mapped_original_cells__"),
      "$.task_attempts[]" = c("attempt_id","collection_origin","compiled_hash","completion_status","evidence_level","id","logical_evidence_key","material_origin","missing_reasons","participant_id","participant_linkage","profile","protocol_id","responses","schema","score","session_id","source","source_attempt_id","source_collection_id","task_definition_hash","task_id","timing_quality","trial_audit"),
      "$.task_attempts[].responses[]" = c("cell_id","correct","expected_action","final_code","final_correct_ms","final_correct_ms_source","first_correct","first_response_ms","first_response_ms_source","missing_reason","outcome","phase","presented","response_code","response_ms","response_outcome","round_id","trial_id"),
      "$.task_attempts[].score" = c("attempt_id","cells","collection_origin","counts","design_hash","eligible","evidence_level","limitations","metrics","origin","participant_id","participant_linkage","procedure_hash","profile","reason","schema_version","scoring_audit","scoring_recipe","sequence_hash","session_id","status","support_policy","task_id","title"),
      "$.task_attempts[].score.cells[]" = c("approach_mean_ms","approach_n","avoid_mean_ms","avoid_minus_approach_ms","avoid_n","category_id"),
      "$.task_attempts[].score.counts" = c("errors","expected","expected_practice","expected_test","expected_training","first_response_errors","interrupted","outside_rt_window","practice","received","removed_fast","retained","retained_correct","retained_errors","scored","scored_responded","scored_timeouts","test","timeouts","training"),
      "$.task_attempts[].score.metrics[]" = c("direction","eligible","name","reason","support","unit","value"),
      "$.task_attempts[].score.metrics[].support" = c("cell_id","deadline_ms","denominator","denominator_definition","eligible","eligible_count","minimum_count","noise","numerator","pooled_correct_responses","population","retained_responses","rt_max_ms","rt_min_ms","sample_sd_divisor","signal","test_trials"),
      "$.task_attempts[].score.scoring_audit" = c("cells","context","counts","direction","displayed_d","eligible","endpoint_recipe","error_base","error_penalty_ms","fast_denominator","fast_fraction","fast_numerator","mapping","mapping_order","minimum_retained_ms","original_count","pairs","pooled_correct_sample_sd_ms","qc","reason","reference","reference_package_d","reference_sign","response_window_ms","retained_count","round_order","rounds","rows","schema","slow_count","target","timing_known","training_order","unit","value"),
      "$.task_attempts[].score.scoring_audit.cells[]" = c("correct_rejections","corrected_rates","criterion","d_prime","deadline_ms","endpoint_adjustments","expected_noise","expected_signal","false_alarms","flags","hits","id","misses","pairing","raw_rates","reason","received_test","response_rt","round_id","status"),
      "$.task_attempts[].score.scoring_audit.cells[].corrected_rates" = c("false_alarm","hit"),
      "$.task_attempts[].score.scoring_audit.cells[].endpoint_adjustments" = c("false_alarm","hit"),
      "$.task_attempts[].score.scoring_audit.cells[].raw_rates" = c("false_alarm","hit"),
      "$.task_attempts[].score.scoring_audit.cells[].response_rt" = c("false_alarm","hit"),
      "$.task_attempts[].score.scoring_audit.cells[].response_rt.false_alarm" = c("mean_ms","median_ms","n","sd_ms"),
      "$.task_attempts[].score.scoring_audit.cells[].response_rt.hit" = c("mean_ms","median_ms","n","sd_ms"),
      "$.task_attempts[].score.scoring_audit.context" = c("kind","label","rationale"),
      "$.task_attempts[].score.scoring_audit.counts" = c("omitted","presented","removed_fast","responded","retained","retained_correct","retained_errors"),
      "$.task_attempts[].score.scoring_audit.mapping" = c("A","B"),
      "$.task_attempts[].score.scoring_audit.mapping.A" = c("accuracy_among_responses","accuracy_among_retained","adjusted_mean_ms","correct_fraction_of_presented","error_replacement_base_ms","mapping","omitted","presented","removed_fast","responded","retained","retained_correct","retained_errors"),
      "$.task_attempts[].score.scoring_audit.mapping.B" = c("accuracy_among_responses","accuracy_among_retained","adjusted_mean_ms","correct_fraction_of_presented","error_replacement_base_ms","mapping","omitted","presented","removed_fast","responded","retained","retained_correct","retained_errors"),
      "$.task_attempts[].score.scoring_audit.pairs[]" = c("combined_sample_sd_ms","d","mapping_a_mean_ms","mapping_a_n","mapping_b_mean_ms","mapping_b_n","pair"),
      "$.task_attempts[].score.scoring_audit.qc" = c("below_75pct_response_accuracy","exclusion_applied"),
      "$.task_attempts[].score.scoring_audit.reference" = c("package","procedure","source","version"),
      "$.task_attempts[].score.scoring_audit.rounds[]" = c("contrast","deadline_ms","id","negative_cell","pairing_order","positive_cell","status"),
      "$.task_attempts[].score.scoring_audit.rows[]" = c("block_id","category_role","cell_id","correct","expected_action","latency_ms","mapping","outcome","phase","reason","response_code","response_ms","response_outcome","round_id","scoring_latency_ms","trial_id"),
      "$.task_attempts[].score.scoring_audit.target" = c("id","label"),
      "$.task_attempts[].score.support_policy" = c("aggregate_eligible_definition","compatibility","complete_trial_evidence_required","mean_median_minimum_correct","sample_sd_minimum_correct"),
      "$.task_attempts[].source" = c("dataset_id","mapping_hash","original_hash","registry_canonical_hash","registry_object_hash","revision","selected_original_rows","selected_rows_hash"),
      "$.task_attempts[].timing_quality" = c("anticipatory_count","definitions_known","frame_observations","journal_replayed","key_history","onset_observations","physical_timing_qualified","source_clock","source_rt_definition","source_software","terminal_response_rule"),
      "$.task_attempts[].trial_audit[]" = c("action","block_id","category_id","cell_id","correct","declared_latency_ms","derived","disposition","expected_action","missing_reason","original_fast_below_300","outcome","phase","profile_scored","round_id","score_block","scoring_basis","scoring_latency_ms","source_row","trial_id"),
      "$.task_scores[]" = c("attempt_id","cells","collection_origin","counts","design_hash","eligible","evidence_level","limitations","metrics","origin","participant_id","participant_linkage","procedure_hash","profile","reason","schema_version","scoring_audit","scoring_recipe","sequence_hash","session_id","status","support_policy","task_id","title"),
      "$.task_scores[].cells[]" = c("approach_mean_ms","approach_n","avoid_mean_ms","avoid_minus_approach_ms","avoid_n","category_id"),
      "$.task_scores[].counts" = c("errors","expected","expected_practice","expected_test","expected_training","first_response_errors","interrupted","outside_rt_window","practice","received","removed_fast","retained","retained_correct","retained_errors","scored","scored_responded","scored_timeouts","test","timeouts","training"),
      "$.task_scores[].metrics[]" = c("direction","eligible","name","reason","support","unit","value"),
      "$.task_scores[].metrics[].support" = c("cell_id","deadline_ms","denominator","denominator_definition","eligible","eligible_count","minimum_count","noise","numerator","pooled_correct_responses","population","retained_responses","rt_max_ms","rt_min_ms","sample_sd_divisor","signal","test_trials"),
      "$.task_scores[].scoring_audit" = c("cells","context","counts","direction","displayed_d","eligible","endpoint_recipe","error_base","error_penalty_ms","fast_denominator","fast_fraction","fast_numerator","mapping","mapping_order","minimum_retained_ms","original_count","pairs","pooled_correct_sample_sd_ms","qc","reason","reference","reference_package_d","reference_sign","response_window_ms","retained_count","round_order","rounds","rows","schema","slow_count","target","timing_known","training_order","unit","value"),
      "$.task_scores[].scoring_audit.cells[]" = c("correct_rejections","corrected_rates","criterion","d_prime","deadline_ms","endpoint_adjustments","expected_noise","expected_signal","false_alarms","flags","hits","id","misses","pairing","raw_rates","reason","received_test","response_rt","round_id","status"),
      "$.task_scores[].scoring_audit.cells[].corrected_rates" = c("false_alarm","hit"),
      "$.task_scores[].scoring_audit.cells[].endpoint_adjustments" = c("false_alarm","hit"),
      "$.task_scores[].scoring_audit.cells[].raw_rates" = c("false_alarm","hit"),
      "$.task_scores[].scoring_audit.cells[].response_rt" = c("false_alarm","hit"),
      "$.task_scores[].scoring_audit.cells[].response_rt.false_alarm" = c("mean_ms","median_ms","n","sd_ms"),
      "$.task_scores[].scoring_audit.cells[].response_rt.hit" = c("mean_ms","median_ms","n","sd_ms"),
      "$.task_scores[].scoring_audit.context" = c("kind","label","rationale"),
      "$.task_scores[].scoring_audit.counts" = c("omitted","presented","removed_fast","responded","retained","retained_correct","retained_errors"),
      "$.task_scores[].scoring_audit.mapping" = c("A","B"),
      "$.task_scores[].scoring_audit.mapping.A" = c("accuracy_among_responses","accuracy_among_retained","adjusted_mean_ms","correct_fraction_of_presented","error_replacement_base_ms","mapping","omitted","presented","removed_fast","responded","retained","retained_correct","retained_errors"),
      "$.task_scores[].scoring_audit.mapping.B" = c("accuracy_among_responses","accuracy_among_retained","adjusted_mean_ms","correct_fraction_of_presented","error_replacement_base_ms","mapping","omitted","presented","removed_fast","responded","retained","retained_correct","retained_errors"),
      "$.task_scores[].scoring_audit.pairs[]" = c("combined_sample_sd_ms","d","mapping_a_mean_ms","mapping_a_n","mapping_b_mean_ms","mapping_b_n","pair"),
      "$.task_scores[].scoring_audit.qc" = c("below_75pct_response_accuracy","exclusion_applied"),
      "$.task_scores[].scoring_audit.reference" = c("package","procedure","source","version"),
      "$.task_scores[].scoring_audit.rounds[]" = c("contrast","deadline_ms","id","negative_cell","pairing_order","positive_cell","status"),
      "$.task_scores[].scoring_audit.rows[]" = c("block_id","category_role","cell_id","correct","expected_action","latency_ms","mapping","outcome","phase","reason","response_code","response_ms","response_outcome","round_id","scoring_latency_ms","trial_id"),
      "$.task_scores[].scoring_audit.target" = c("id","label"),
      "$.task_scores[].support_policy" = c("aggregate_eligible_definition","compatibility","complete_trial_evidence_required","mean_median_minimum_correct","sample_sd_minimum_correct")
    ),
    "implicit_cohort" = list(
      "$" = c("attempt_metrics","contrasts","kind","limitations","membership","per_person","per_session","provenance","quality","schema","status","summaries","title"),
      "$.attempt_metrics[]" = c("attempt_id","eligibility_policy","eligible","metric","person_id","reason","reported_value","session_id","source_attempt_hash","support","unit","value"),
      "$.attempt_metrics[].support" = c("denominator","denominator_definition","eligible_count","minimum_count","numerator","population","rt_max_ms","rt_min_ms","sample_sd_divisor"),
      "$.membership[]" = c("attempt_hash","attempt_id","compiled_hash","completion_status","linkage_reason","linked","logical_evidence_key","missing_reasons","original_participant_linkage","person_id","protocol_id","score_status","session_id","source","source_attempt_id","source_collection_id","source_participant_id","source_session_id","timing_quality"),
      "$.membership[].source" = c("dataset_id","mapping_hash","original_hash","registry_canonical_hash","registry_object_hash","revision","selected_original_rows","selected_rows_hash"),
      "$.membership[].timing_quality" = c("anticipatory_count","definitions_known","frame_observations","journal_replayed","key_history","onset_observations","physical_timing_qualified","source_clock","source_rt_definition","source_software","terminal_response_rule"),
      "$.per_person[]" = c("contributing_session_ids","eligible_attempt_count","eligible_session_count","metric","person_id","reason","selected_attempt_count","selected_session_count","unit","value"),
      "$.per_session[]" = c("attempt_ids","contributing_attempt_ids","eligible_attempt_count","metric","person_id","reason","selected_attempt_count","session_id","unit","value"),
      "$.provenance" = c("duplicate_policy","homogeneous","identity_map","identity_map_hash","identity_policy","plan","plan_hash","recipe","selected_attempt_hashes"),
      "$.provenance.homogeneous" = c("collection_origin","evidence_level","material_origin","profile","score_schema","scoring_recipe","task_definition_hash","task_id"),
      "$.provenance.identity_map" = c("linkage_statement","participants","schema","sessions"),
      "$.provenance.identity_map.participants[]" = c("participant_id","person_id","source_collection_id"),
      "$.provenance.identity_map.sessions[]" = c("equivalence_statement","participant_id","session_id","source_collection_id","source_session_id"),
      "$.provenance.plan" = c("description","homogeneous","membership","repeat_policy","schema"),
      "$.provenance.plan.homogeneous" = c("collection_origin","evidence_level","material_origin","profile","score_schema","scoring_recipe","task_definition_hash","task_id"),
      "$.provenance.plan.membership[]" = c("attempt_hash","attempt_id"),
      "$.quality" = c("completed_attempt_count","fully_linked","inference_performed","scientifically_qualified","selected_attempt_count","selected_person_count","unlinked_attempt_count","usable"),
      "$.summaries[]" = c("between_person_sd","contributing_person_count","contributing_session_count","eligible_attempt_count","estimand","mean","metric","reason","sd_reason","selected_attempt_count","selected_person_count","status","unit")
    ),
    "score:aat-keyboard-cue-balanced/1.0" = list(
      "$" = c("attempt_id","cells","collection_origin","counts","design_hash","eligible","evidence_level","limitations","metrics","origin","participant_id","participant_linkage","profile","reason","schema_version","session_id","status","task_id","title"),
      "$.cells[]" = c("approach_mean_ms","approach_n","avoid_mean_ms","avoid_minus_approach_ms","avoid_n","category_id"),
      "$.counts" = c("errors","expected","first_response_errors","outside_rt_window","received","retained_correct","scored","timeouts"),
      "$.metrics[]" = c("direction","name","unit","value")
    ),
    "score:biat-nosek2014-goodfocal/1.0" = list(
      "$" = c("attempt_id","collection_origin","counts","design_hash","eligible","evidence_level","limitations","metrics","origin","participant_id","participant_linkage","profile","schema_version","scoring_audit","session_id","status","task_id","title"),
      "$.counts" = c("expected","first_response_errors","received","timeouts"),
      "$.metrics[]" = c("direction","name","unit","value"),
      "$.scoring_audit" = c("direction","eligible","fast_denominator","fast_fraction","fast_numerator","original_count","pairs","reason","retained_count","slow_count","unit","value"),
      "$.scoring_audit.pairs[]" = c("combined_sample_sd_ms","d","mapping_a_mean_ms","mapping_a_n","mapping_b_mean_ms","mapping_b_n","pair")
    ),
    "score:gnat-brohn-single-target/1.0" = list(
      "$" = c("attempt_id","collection_origin","counts","design_hash","eligible","evidence_level","limitations","metrics","origin","participant_id","participant_linkage","procedure_hash","profile","reason","schema_version","scoring_audit","scoring_recipe","sequence_hash","session_id","status","task_id","title"),
      "$.counts" = c("expected","expected_practice","expected_test","expected_training","interrupted","practice","received","test","training"),
      "$.metrics[]" = c("direction","name","support","unit","value"),
      "$.metrics[].support" = c("cell_id","deadline_ms","eligible","noise","signal","test_trials"),
      "$.scoring_audit" = c("cells","context","endpoint_recipe","round_order","rounds","rows","schema","target","timing_known","training_order"),
      "$.scoring_audit.cells[]" = c("correct_rejections","corrected_rates","criterion","d_prime","deadline_ms","endpoint_adjustments","expected_noise","expected_signal","false_alarms","flags","hits","id","misses","pairing","raw_rates","reason","received_test","response_rt","round_id","status"),
      "$.scoring_audit.cells[].corrected_rates" = c("false_alarm","hit"),
      "$.scoring_audit.cells[].endpoint_adjustments" = c("false_alarm","hit"),
      "$.scoring_audit.cells[].raw_rates" = c("false_alarm","hit"),
      "$.scoring_audit.cells[].response_rt" = c("false_alarm","hit"),
      "$.scoring_audit.cells[].response_rt.false_alarm" = c("mean_ms","median_ms","n","sd_ms"),
      "$.scoring_audit.cells[].response_rt.hit" = c("mean_ms","median_ms","n","sd_ms"),
      "$.scoring_audit.context" = c("kind","label","rationale"),
      "$.scoring_audit.rounds[]" = c("contrast","deadline_ms","id","negative_cell","pairing_order","positive_cell","status"),
      "$.scoring_audit.rows[]" = c("block_id","category_role","cell_id","correct","expected_action","outcome","phase","response_code","response_ms","response_outcome","round_id","trial_id"),
      "$.scoring_audit.target" = c("id","label")
    ),
    "score:iat-gnb2003-d1/1.0" = list(
      "$" = c("attempt_id","collection_origin","counts","design_hash","eligible","evidence_level","limitations","metrics","origin","participant_id","participant_linkage","profile","schema_version","scoring_audit","session_id","status","task_id","title"),
      "$.counts" = c("expected","first_response_errors","received","timeouts"),
      "$.metrics[]" = c("direction","name","unit","value"),
      "$.scoring_audit" = c("direction","eligible","fast_denominator","fast_fraction","fast_numerator","original_count","pairs","reason","retained_count","slow_count","unit","value"),
      "$.scoring_audit.pairs[]" = c("combined_sample_sd_ms","d","mapping_a_mean_ms","mapping_a_n","mapping_b_mean_ms","mapping_b_n","pair")
    ),
    "score:rt-deary-liewald-choice/1.0" = list(
      "$" = c("attempt_id","collection_origin","counts","design_hash","eligible","evidence_level","limitations","metrics","origin","participant_id","participant_linkage","profile","reason","schema_version","scoring_recipe","session_id","status","support_policy","task_id","title"),
      "$.counts" = c("errors","expected","first_response_errors","outside_rt_window","received","retained_correct","scored","scored_responded","scored_timeouts","timeouts"),
      "$.metrics[]" = c("eligible","name","reason","support","unit","value"),
      "$.metrics[].support" = c("denominator","denominator_definition","eligible_count","minimum_count","numerator","population","rt_max_ms","rt_min_ms","sample_sd_divisor"),
      "$.support_policy" = c("aggregate_eligible_definition","compatibility","complete_trial_evidence_required","mean_median_minimum_correct","sample_sd_minimum_correct")
    ),
    "score:rt-deary-liewald-simple/1.0" = list(
      "$" = c("attempt_id","collection_origin","counts","design_hash","eligible","evidence_level","limitations","metrics","origin","participant_id","participant_linkage","profile","reason","schema_version","scoring_recipe","session_id","status","support_policy","task_id","title"),
      "$.counts" = c("errors","expected","first_response_errors","outside_rt_window","received","retained_correct","scored","scored_responded","scored_timeouts","timeouts"),
      "$.metrics[]" = c("eligible","name","reason","support","unit","value"),
      "$.metrics[].support" = c("denominator","denominator_definition","eligible_count","minimum_count","numerator","population","rt_max_ms","rt_min_ms","sample_sd_divisor"),
      "$.support_policy" = c("aggregate_eligible_definition","compatibility","complete_trial_evidence_required","mean_median_minimum_correct","sample_sd_minimum_correct")
    ),
    "score:sciat-brohn-response-window-im100/1.0" = list(
      "$" = c("attempt_id","collection_origin","counts","design_hash","eligible","evidence_level","limitations","metrics","origin","participant_id","participant_linkage","procedure_hash","profile","schema_version","scoring_audit","scoring_recipe","sequence_hash","session_id","status","task_id","title"),
      "$.counts" = c("expected","practice","received","removed_fast","retained","retained_correct","retained_errors","scored","scored_responded","scored_timeouts"),
      "$.metrics[]" = c("direction","name","support","unit","value"),
      "$.metrics[].support" = c("pooled_correct_responses","retained_responses","sample_sd_divisor","test_trials"),
      "$.scoring_audit" = c("counts","displayed_d","error_base","error_penalty_ms","mapping","mapping_order","minimum_retained_ms","pooled_correct_sample_sd_ms","qc","reference","reference_package_d","reference_sign","response_window_ms","rows","schema"),
      "$.scoring_audit.counts" = c("omitted","presented","removed_fast","responded","retained","retained_correct","retained_errors"),
      "$.scoring_audit.mapping" = c("A","B"),
      "$.scoring_audit.mapping.A" = c("accuracy_among_responses","accuracy_among_retained","adjusted_mean_ms","correct_fraction_of_presented","error_replacement_base_ms","mapping","omitted","presented","removed_fast","responded","retained","retained_correct","retained_errors"),
      "$.scoring_audit.mapping.B" = c("accuracy_among_responses","accuracy_among_retained","adjusted_mean_ms","correct_fraction_of_presented","error_replacement_base_ms","mapping","omitted","presented","removed_fast","responded","retained","retained_correct","retained_errors"),
      "$.scoring_audit.qc" = c("below_75pct_response_accuracy","exclusion_applied"),
      "$.scoring_audit.reference" = c("package","procedure","source","version"),
      "$.scoring_audit.rows[]" = c("correct","latency_ms","mapping","outcome","reason","scoring_latency_ms","trial_id")
    )
  )
  function() fields
})
