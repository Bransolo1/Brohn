# Pure, explicitly selected administration summaries. No storage discovery,
# trial pooling, identity inference, confidence intervals or scientific rescoring.
.brohn_task_cohort_hash <- function(x) brohn_text(x,64) && grepl("^[a-f0-9]{64}$",x)
.brohn_task_cohort_key <- function(...) brohn_hash(list(...))
.brohn_task_cohort_bool <- function(x) is.logical(x) && length(x)==1L && !is.na(x)
.brohn_task_cohort_specs <- function(profile) {
  kind<-brohn_task_profile(profile)$kind
  names<-switch(kind,iat="IAT_D1",biat="BIAT_D",aat="keyboard_aat_relative_approach_advantage",
    c("correct_test_rt_mean","correct_test_rt_median","correct_test_rt_sd","test_first_response_error_rate","test_omission_rate"))
  units<-if(kind %in% c("iat","biat"))"D" else if(kind=="aat")"ms" else c("ms","ms","ms","proportion","proportion")
  Map(function(name,unit)list(name=name,unit=unit),names,units)
}
.brohn_task_cohort_identity <- function(a) list(task_id=a$task_id,task_definition_hash=a$task_definition_hash,
  profile=a$profile,collection_origin=a$collection_origin,material_origin=a$material_origin,
  score_schema=a$score$schema_version,scoring_recipe=a$score$scoring_recipe,evidence_level=a$evidence_level)
.brohn_task_cohort_attempt <- function(a) {
  required<-c("schema","id","logical_evidence_key","source_collection_id","source_attempt_id","participant_id",
    "participant_linkage","session_id","attempt_id","task_id","task_definition_hash","protocol_id","compiled_hash",
    "profile","collection_origin","material_origin","completion_status","evidence_level","source","responses","trial_audit",
    "score","timing_quality","missing_reasons")
  brohn_fields(a,required,label="Canonical task administration")
  brohn_require(identical(a$schema,"brohn-task-attempt/1.0"),"Use canonical task administration version 1.0.")
  for(field in c("id","source_collection_id","source_attempt_id","participant_id","session_id","attempt_id","task_id","protocol_id","evidence_level"))
    brohn_require(brohn_text(a[[field]],240),paste("Administration needs an exact text",field,"identity."))
  for(field in c("logical_evidence_key","task_definition_hash","compiled_hash"))brohn_require(.brohn_task_cohort_hash(a[[field]]),paste("Invalid",field,"hash."))
  brohn_require(.brohn_task_cohort_bool(a$participant_linkage) && a$completion_status %in% c("completed","interrupted","incomplete"),"Administration needs explicit completion and original linkage evidence.")
  brohn_require(brohn_text(a$collection_origin,32) && brohn_text(a$material_origin,32),"Keep declared collection and material origins separate.")
  logical_key<-brohn_hash(list(source_collection_id=a$source_collection_id,participant_id=a$participant_id,
    session_id=a$session_id,attempt_id=a$attempt_id,task_definition_hash=a$task_definition_hash))
  brohn_require(identical(a$source_attempt_id,a$attempt_id) && identical(a$logical_evidence_key,logical_key),"The administration logical evidence key does not match its source identities.")
  s<-a$source
  brohn_require(is.list(s) && brohn_text(s$dataset_id,240) && brohn_number(s$revision,1,.Machine$integer.max,TRUE),"Retain original dataset identity and revision.")
  for(field in c("original_hash","mapping_hash","registry_object_hash","registry_canonical_hash","selected_rows_hash"))
    brohn_require(.brohn_task_cohort_hash(s[[field]]),paste("Retain exact source",field,"evidence."))
  brohn_require(brohn_array(s$selected_original_rows) && length(s$selected_original_rows)>0L &&
    all(vapply(s$selected_original_rows,function(x)brohn_number(x,1,20000,TRUE),logical(1))) &&
    !anyDuplicated(unlist(s$selected_original_rows)),"Original selected row identities must be a nonempty unique bounded array.")
  brohn_require(identical(a$id,paste0("task-attempt-",brohn_hash(list(original_source_hash=s$original_hash,logical_evidence_key=logical_key)))),
    "Administration ID must bind its original source and logical evidence key.")
  score<-a$score;kind<-brohn_task_profile(a$profile)$kind;rt<-kind %in% c("simple_rt","choice_rt")
  brohn_require(is.list(score) && identical(score$task_id,a$task_id) && identical(score$profile,a$profile) &&
    identical(score$origin,a$material_origin) && identical(score$design_hash,a$task_definition_hash),"The score does not belong to this exact task definition/profile/material origin.")
  brohn_require(identical(score$attempt_id,a$id)&&identical(score$participant_id,a$participant_id)&&
    identical(score$session_id,a$session_id)&&identical(score$participant_linkage,a$participant_linkage)&&
    identical(score$collection_origin,a$collection_origin)&&identical(score$evidence_level,a$evidence_level),
    "The score's administration/person/session/origin/evidence references disagree with its canonical administration.")
  allowed<-identical(score$schema_version,"brohn-task-score/1.0") && is.null(score$scoring_recipe)
  if(rt)allowed<-allowed || (identical(score$schema_version,"brohn-task-score/1.1") && identical(score$scoring_recipe,"brohn-rt-metric-support/1.0"))
  brohn_require(allowed && .brohn_task_cohort_bool(score$eligible) && brohn_array(score$metrics),"Use a supported exact score schema and recipe; do not reinterpret another scoring version.")
  brohn_require(brohn_array(a$responses) && brohn_array(a$trial_audit) && brohn_array(a$missing_reasons),"Keep administration response/audit evidence arrays.")
  specs<-.brohn_task_cohort_specs(a$profile);metric_names<-vapply(score$metrics,function(m){brohn_require(is.list(m)&&brohn_text(m$name,128),"A score metric needs a name.");m$name},character(1))
  brohn_require(!anyDuplicated(metric_names) && all(metric_names %in% vapply(specs,`[[`,character(1),"name")),"A score contains duplicate or unregistered metrics.")
  for(m in score$metrics) {
    spec<-specs[[match(m$name,vapply(specs,`[[`,character(1),"name"))]]
    brohn_require(identical(m$unit,spec$unit) && (is.null(m$value)||brohn_number(m$value)),"Metric units and finite numerical values must match the named profile.")
    if(identical(score$schema_version,"brohn-task-score/1.1"))brohn_require(.brohn_task_cohort_bool(m$eligible) && is.list(m$support),"RT 1.1 requires each metric's explicit eligibility and support.")
    eligible<-if(identical(score$schema_version,"brohn-task-score/1.1"))m$eligible else score$eligible
    brohn_require(!eligible || (!is.null(m$value) && identical(a$completion_status,"completed")),"An eligible metric requires a finite value and complete administration evidence.")
    brohn_require(!is.null(m$value)||!eligible,"An eligible metric cannot have a null value.")
    if(!is.null(m$value)&&spec$unit=="proportion")brohn_require(m$value>=0&&m$value<=1,"A proportion must lie between zero and one.")
    if(!is.null(m$value)&&spec$unit=="ms"&&kind!="aat")brohn_require(m$value>=0,"RT summaries cannot be negative.")
  }
  if(identical(score$schema_version,"brohn-task-score/1.1"))brohn_require(identical(score$eligible,
    any(vapply(score$metrics,function(m)isTRUE(m$eligible),logical(1)))),"RT aggregate eligibility must mean at least one explicitly eligible metric, never substitute for metric eligibility.")
  invisible(a)
}

# This helper proposes source rows only. NULL destinations never silently link.
brohn_task_cohort_identity_rows <- function(attempts) {
  brohn_require(brohn_array(attempts)&&length(attempts)>0L&&length(attempts)<=5000L,"Supply 1 to 5,000 explicitly selected canonical administrations.")
  participants<-sessions<-list();pk<-sk<-character()
  for(a in attempts) {
    .brohn_task_cohort_attempt(a)
    pkey<-.brohn_task_cohort_key(a$source_collection_id,a$participant_id)
    skey<-.brohn_task_cohort_key(a$source_collection_id,a$participant_id,a$session_id)
    if(!pkey %in% pk){pk<-c(pk,pkey);participants[[length(participants)+1L]]<-list(source_collection_id=a$source_collection_id,participant_id=a$participant_id,person_id=NULL)}
    if(!skey %in% sk){sk<-c(sk,skey);sessions[[length(sessions)+1L]]<-list(source_collection_id=a$source_collection_id,participant_id=a$participant_id,source_session_id=a$session_id,session_id=NULL,equivalence_statement=NULL)}
  }
  list(schema="brohn-task-cohort-identities/1.0",linkage_statement=NULL,participants=participants,sessions=sessions)
}

brohn_task_cohort <- function(attempts,plan,identity_map) {
  brohn_require(brohn_array(attempts)&&length(attempts)>0L&&length(attempts)<=5000L,"Supply 1 to 5,000 explicitly selected canonical administrations; no automatic latest-report selection.")
  brohn_fields(plan,c("schema","description","membership","homogeneous","repeat_policy"),label="Task cohort plan")
  brohn_require(identical(plan$schema,"brohn-task-cohort-plan/1.0")&&brohn_text(plan$description,5000)&&
    brohn_array(plan$membership)&&length(plan$membership)>0L&&length(plan$membership)<=5000L,"Name the cohort plan and freeze its complete bounded membership.")
  brohn_require(brohn_text(plan$repeat_policy,100)&&plan$repeat_policy %in% c("one_selected_attempt_per_person","equal_attempts_within_session_then_equal_sessions_within_person"),"Choose an explicit supported repeat policy.")
  pinned<-plan$homogeneous
  brohn_fields(pinned,c("task_id","task_definition_hash","profile","collection_origin","material_origin","score_schema","scoring_recipe","evidence_level"),label="Homogeneous task cohort")
  ids<-vapply(attempts,function(a){.brohn_task_cohort_attempt(a);a$id},character(1))
  brohn_require(!anyDuplicated(ids),"Duplicate administration IDs cannot add cohort observations.")
  member_ids<-vapply(plan$membership,function(m){brohn_fields(m,c("attempt_id","attempt_hash"),label="Frozen cohort member");brohn_require(brohn_text(m$attempt_id,240)&&.brohn_task_cohort_hash(m$attempt_hash),"Pin each administration and canonical hash.");m$attempt_id},character(1))
  brohn_require(!anyDuplicated(member_ids)&&setequal(ids,member_ids),"Supply exactly the frozen selected administrations, including unavailable ones; never substitute a latest result.")
  attempts<-attempts[match(member_ids,ids)]
  for(i in seq_along(attempts)) {
    brohn_require(identical(brohn_hash(attempts[[i]]),plan$membership[[i]]$attempt_hash),"A selected administration differs from its frozen membership hash.")
    brohn_require(identical(brohn_json(.brohn_task_cohort_identity(attempts[[i]])),brohn_json(pinned)),"Task definition, profile, origins, score recipe and evidence level must be one exact homogeneous group.")
  }
  logical_keys<-vapply(attempts,`[[`,character(1),"logical_evidence_key")
  physical_keys<-vapply(attempts,function(a).brohn_task_cohort_key(a$source$original_hash,a$task_definition_hash),character(1))
  brohn_require(!anyDuplicated(logical_keys),"Duplicate logical administration evidence includes repeated/reformatted exports; choose one source explicitly.")
  for(key in unique(physical_keys)) {
    rows<-unlist(lapply(attempts[physical_keys==key],function(a)a$source$selected_original_rows),use.names=FALSE)
    brohn_require(!anyDuplicated(rows),"The same original bytes and trial rows were selected more than once under different mappings or identities.")
  }
  brohn_fields(identity_map,c("schema","linkage_statement","participants","sessions"),label="Task cohort identity crosswalk")
  brohn_require(identical(identity_map$schema,"brohn-task-cohort-identities/1.0")&&brohn_array(identity_map$participants)&&brohn_array(identity_map$sessions)&&
    length(identity_map$participants)<=5000L&&length(identity_map$sessions)<=5000L,"Use a bounded explicit person and session crosswalk.")
  brohn_require(is.null(identity_map$linkage_statement)||brohn_text(identity_map$linkage_statement,5000),"The linkage statement must be explicit text or null.")
  pkeys<-skeys<-character();people<-sessions<-list()
  expected_p<-unique(vapply(attempts,function(a).brohn_task_cohort_key(a$source_collection_id,a$participant_id),character(1)))
  expected_s<-unique(vapply(attempts,function(a).brohn_task_cohort_key(a$source_collection_id,a$participant_id,a$session_id),character(1)))
  for(p in identity_map$participants) {
    brohn_fields(p,c("source_collection_id","participant_id","person_id"),label="Participant crosswalk row")
    brohn_require(brohn_text(p$source_collection_id,240)&&brohn_text(p$participant_id,240)&&(is.null(p$person_id)||brohn_text(p$person_id,240)),"Person identities must be exact text or explicitly unlinked null, never inferred numeric codes.")
    key<-.brohn_task_cohort_key(p$source_collection_id,p$participant_id)
    brohn_require(key %in% expected_p&&!key %in% pkeys,"Participant crosswalk rows must be unique selected source namespaces and codes.")
    pkeys<-c(pkeys,key);people[[key]]<-p
  }
  for(s in identity_map$sessions) {
    brohn_fields(s,c("source_collection_id","participant_id","source_session_id","session_id","equivalence_statement"),label="Session crosswalk row")
    brohn_require(all(vapply(s[c("source_collection_id","participant_id","source_session_id")],brohn_text,logical(1),max=240))&&
      (is.null(s$session_id)||brohn_text(s$session_id,240))&&(is.null(s$equivalence_statement)||brohn_text(s$equivalence_statement,5000)),"Session identities require explicit text and any declared equivalence statement.")
    key<-.brohn_task_cohort_key(s$source_collection_id,s$participant_id,s$source_session_id)
    brohn_require(key %in% expected_s&&!key %in% skeys,"One original session cannot be split across duplicate crosswalk rows or unselected namespaces.")
    skeys<-c(skeys,key);sessions[[key]]<-s
  }
  linked<-list();audit<-list()
  for(i in seq_along(attempts)) {
    a<-attempts[[i]];p<-people[[.brohn_task_cohort_key(a$source_collection_id,a$participant_id)]]
    s<-sessions[[.brohn_task_cohort_key(a$source_collection_id,a$participant_id,a$session_id)]]
    ok<-!is.null(p$person_id)&&!is.null(s$session_id)
    linked[[i]]<-list(person_id=p$person_id,session_id=s$session_id,eligible=ok,equivalence_statement=s$equivalence_statement)
    audit[[i]]<-list(attempt_id=a$id,attempt_hash=plan$membership[[i]]$attempt_hash,logical_evidence_key=a$logical_evidence_key,
      source_collection_id=a$source_collection_id,source_participant_id=a$participant_id,source_session_id=a$session_id,source_attempt_id=a$attempt_id,
      person_id=p$person_id,session_id=s$session_id,linked=ok,linkage_reason=if(ok)NULL else "Explicit person and session crosswalk entries are both required.",
      original_participant_linkage=a$participant_linkage,completion_status=a$completion_status,score_status=a$score$status,
      source=a$source,compiled_hash=a$compiled_hash,protocol_id=a$protocol_id,timing_quality=a$timing_quality,missing_reasons=a$missing_reasons)
  }
  assigned_people<-vapply(Filter(function(x)!is.null(x$person_id),linked),`[[`,character(1),"person_id")
  if(length(assigned_people))brohn_require(brohn_text(identity_map$linkage_statement,5000),"Document the researcher's explicit identity linkage assertion; source labels alone do not verify people.")
  if(plan$repeat_policy=="one_selected_attempt_per_person")brohn_require(!anyDuplicated(assigned_people),"The one-selected-attempt policy requires selecting exactly one administration per person before considering any metric eligibility.")
  # Collapsing source sessions requires an explicit shared declaration, including
  # across source namespaces. Distinct visits are otherwise never merged.
  pairs<-vapply(linked,function(x)if(x$eligible).brohn_task_cohort_key(x$person_id,x$session_id)else "",character(1))
  for(pair in unique(pairs[nzchar(pairs)])) {
    indices<-which(pairs==pair);source_sessions<-vapply(attempts[indices],function(a).brohn_task_cohort_key(a$source_collection_id,a$participant_id,a$session_id),character(1))
    if(length(unique(source_sessions))>1L) {
      declarations<-lapply(linked[indices],`[[`,"equivalence_statement")
      brohn_require(all(vapply(declarations,brohn_text,logical(1),max=5000))&&length(unique(unlist(declarations)))==1L,
        "Multiple original sessions cannot collapse into one person/session without the same explicit equivalence statement on each source session.")
    }
  }
  all_linked<-all(vapply(linked,`[[`,logical(1),"eligible"));specs<-.brohn_task_cohort_specs(pinned$profile)
  person_groups<-if(all_linked)split(seq_along(linked),factor(assigned_people,levels=unique(assigned_people)))else list()
  person_sessions<-lapply(person_groups,function(indices) {
    keys<-vapply(linked[indices],`[[`,character(1),"session_id")
    split(indices,factor(keys,levels=unique(keys)))
  })
  metric_rows<-per_session<-per_person<-summaries<-list()
  for(spec in specs) {
    rows<-lapply(seq_along(attempts),function(i) {
      a<-attempts[[i]];match_metric<-Filter(function(m)m$name==spec$name,a$score$metrics);m<-if(length(match_metric))match_metric[[1L]]else NULL
      modern<-identical(a$score$schema_version,"brohn-task-score/1.1")
      eligible<-!is.null(m)&&isTRUE(if(modern)m$eligible else a$score$eligible)&&!is.null(m$value)&&a$completion_status=="completed"
      list(attempt_id=a$id,person_id=linked[[i]]$person_id,session_id=linked[[i]]$session_id,metric=spec$name,unit=spec$unit,
        eligible=eligible,value=if(eligible)m$value else NULL,reported_value=if(is.null(m))NULL else m$value,
        reason=if(eligible)NULL else brohn_default(m$reason,brohn_default(a$score$reason,"This frozen score has no supported value for this metric.")),
        support=if(is.null(m))NULL else m$support,
        eligibility_policy=if(modern)"frozen_metric_specific" else "frozen_score_1.0_aggregate_gate",
        source_attempt_hash=plan$membership[[i]]$attempt_hash)
    })
    metric_rows<-c(metric_rows,rows);eligible_count<-sum(vapply(rows,`[[`,logical(1),"eligible"))
    sessions_for_metric<-people_for_metric<-list()
    if(all_linked) {
      for(person in names(person_groups)) {
        person_indices<-person_groups[[person]]
        this_person_sessions<-list()
        for(session in names(person_sessions[[person]])) {
          indices<-person_sessions[[person]][[session]]
          usable<-indices[vapply(rows[indices],`[[`,logical(1),"eligible")]
          item<-list(person_id=person,session_id=session,metric=spec$name,unit=spec$unit,
            value=if(length(usable))mean(vapply(rows[usable],`[[`,numeric(1),"value"))else NULL,
            selected_attempt_count=length(indices),eligible_attempt_count=length(usable),attempt_ids=as.list(member_ids[indices]),
            contributing_attempt_ids=as.list(member_ids[usable]),reason=if(length(usable))NULL else "No selected administration supports this metric in this session.")
          sessions_for_metric[[length(sessions_for_metric)+1L]]<-item;this_person_sessions[[length(this_person_sessions)+1L]]<-item
        }
        good<-Filter(function(s)!is.null(s$value),this_person_sessions)
        people_for_metric[[length(people_for_metric)+1L]]<-list(person_id=person,metric=spec$name,unit=spec$unit,
          value=if(length(good))mean(vapply(good,`[[`,numeric(1),"value"))else NULL,
          selected_attempt_count=length(person_indices),eligible_attempt_count=sum(vapply(rows[person_indices],`[[`,logical(1),"eligible")),
          selected_session_count=length(this_person_sessions),eligible_session_count=length(good),
          contributing_session_ids=lapply(good,`[[`,"session_id"),reason=if(length(good))NULL else "No selected session supports this metric for this person.")
      }
    }
    per_session<-c(per_session,sessions_for_metric);per_person<-c(per_person,people_for_metric)
    values<-vapply(Filter(function(p)!is.null(p$value),people_for_metric),`[[`,numeric(1),"value");n<-length(values)
    summaries[[length(summaries)+1L]]<-list(metric=spec$name,unit=spec$unit,
      status=if(!all_linked)"linkage_unavailable"else if(!n)"unavailable"else "descriptive",
      selected_attempt_count=length(attempts),eligible_attempt_count=eligible_count,
      selected_person_count=if(all_linked)length(unique(assigned_people))else NULL,
      contributing_person_count=if(all_linked)n else NULL,
      contributing_session_count=if(all_linked)sum(vapply(sessions_for_metric,function(s)!is.null(s$value),logical(1)))else NULL,
      mean=if(n)mean(values)else NULL,between_person_sd=if(n>=2L)stats::sd(values)else NULL,
      sd_reason=if(!all_linked)"Unique-person support is unavailable without complete explicit linkage."else if(n<2L)"At least two contributing people are required for a between-person sample SD."else NULL,
      reason=if(!all_linked)"At least one selected administration lacks explicit person/session linkage; no implicit linked subset was analysed."else if(!n)"No selected person has a supported value for this metric."else NULL,
      estimand=paste("Equal-person mean of",spec$name,"after the declared attempt/session averaging; not pooled trial arithmetic."))
  }
  list(schema="brohn-task-cohort/1.0",kind="implicit_cohort",title="Implicit task cohort",membership=audit,
    attempt_metrics=metric_rows,per_session=per_session,per_person=per_person,summaries=summaries,contrasts=list(),
    quality=list(selected_attempt_count=length(attempts),completed_attempt_count=sum(vapply(attempts,function(a)a$completion_status=="completed",logical(1))),
      fully_linked=all_linked,unlinked_attempt_count=sum(!vapply(linked,`[[`,logical(1),"eligible")),
      selected_person_count=if(all_linked)length(unique(assigned_people))else NULL,
      scientifically_qualified=FALSE,inference_performed=FALSE),
    provenance=list(plan=plan,plan_hash=brohn_hash(plan),identity_map=identity_map,identity_map_hash=brohn_hash(identity_map),
      homogeneous=pinned,selected_attempt_hashes=lapply(plan$membership,`[[`,"attempt_hash"),
      recipe="brohn-task-cohort-descriptive/1.0",identity_policy="Explicit researcher crosswalk; linkage assertion is not independent identity verification.",
      duplicate_policy="Reject exact original byte/row selections and repeated logical collection/person/session/attempt/task evidence."),
    limitations=list("Only explicitly selected frozen administration metrics are averaged; no scorer, material, timing or construct qualification is added.",
      "Equal weighting does not correct practice, carryover, selection bias or missingness. Every metric retains its own contributing support.",
      "A mean of per-person median RT outcomes is not a pooled-response median; within-attempt RT SD remains a separate outcome from between-person SD.",
      "Error and omission rates are means of administration proportions under the repeat policy; original trial numerators and denominators remain in attempt support.",
      "Reformatted copies retain their logical evidence key when source identities are truthfully preserved. Changed bytes plus falsified collection/attempt declarations cannot be detected from equal scores alone.",
      "No confidence interval, hypothesis test, clinical band, generic implicit composite, or population inference is performed."))
}
