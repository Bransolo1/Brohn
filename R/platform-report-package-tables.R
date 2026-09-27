# Pure typed projection and complete collection export. No store/source lookup.
.brohn_rp_hash <- function(x) brohn_text(x,64)&&grepl("^[a-f0-9]{64}$",x)
.brohn_rp_same <- function(a,b) identical(brohn_hash(a),brohn_hash(b))
.brohn_rp_ref <- function(x,kind=NULL) {
  brohn_fields(x,c("kind","id","revision","body_hash","project_id"),label="Package source reference")
  brohn_require(brohn_valid_id(x$id)&&brohn_valid_id(x$project_id)&&brohn_number(x$revision,1,integer=TRUE)&&
    .brohn_rp_hash(x$body_hash)&&brohn_text(x$kind,64)&&(is.null(kind)||identical(x$kind,kind)),"Invalid exact package reference.")
  invisible(x)
}
brohn_report_package_limits <- function() list(profile="controlled-report-package/0.1",max_reports=8L,max_panels=100L,
  max_html_bytes=32*1024^2,max_payload_bytes=256*1024^2,max_members=1024L,max_image_bytes=5*1024^2,
  max_image_total_bytes=16*1024^2,max_model_bytes=128*1024^2,max_rows=100000L,max_questionnaire_bytes=64*1024^2,
  max_paired_questionnaire_bytes=12*1024^2)
brohn_report_package_task_limits <- function() {
  value<-brohn_report_package_limits();value$profile<-"controlled-task-report-package/0.1";value
}
.brohn_rp_limits <- function(value) {
  defaults<-if(identical(value$profile,"controlled-task-choice-eda-report-package/0.1"))brohn_report_package_eda_limits()else if(identical(value$profile,"controlled-task-choice-report-package/0.1"))brohn_report_package_choice_limits()else if(identical(value$profile,"controlled-task-report-package/0.1"))brohn_report_package_task_limits()else brohn_report_package_limits()
  brohn_fields(value,names(defaults),label="Package limits")
  brohn_require(identical(value$profile,defaults$profile)&&all(vapply(setdiff(names(defaults),"profile"),function(k)
    brohn_number(value[[k]],1,defaults[[k]],TRUE),logical(1))),"Report limits exceed the supported profile.")
  value
}
.brohn_rp_write <- function(value,path,json=FALSE) {
  brohn_require(!file.exists(path),"A report payload already exists.")
  dir.create(dirname(path),recursive=TRUE,showWarnings=FALSE)
  bytes<-if(json)charToRaw(enc2utf8(paste0(brohn_json(value),"\n")))else if(is.raw(value))value else charToRaw(enc2utf8(value))
  con<-file(path,"wb");on.exit(close(con),add=TRUE);writeBin(bytes,con);invisible(path)
}
.brohn_rp_file <- function(root,path,type,role) {
  brohn_require(brohn_text(path,180)&&grepl("^[a-z0-9][a-z0-9._/-]*$",path)&&
    !any(strsplit(path,"/",fixed=TRUE)[[1L]] %in% c("",".","..")),"Invalid generated payload name.")
  file<-file.path(root,path);brohn_require(file.exists(file)&&!dir.exists(file),"A required report payload is missing.")
  list(path=path,sha256=digest::digest(file=file,algo="sha256"),bytes=as.numeric(file.info(file)$size),media_type=type,role=role)
}
.brohn_rp_csv <- function(rows,path) {
  brohn_require(brohn_array(rows),"Complete CSV rows must be an array.")
  for(r in rows)brohn_require(is.list(r)&&!is.null(names(r))&&!anyDuplicated(names(r))&&
    !any(c("record_json","source_order") %in% names(r)),"CSV rows need original named fields without reserved projection columns.")
  columns<-unique(c("source_order",unlist(lapply(rows,names),use.names=FALSE),"record_json"))
  dir.create(dirname(path),recursive=TRUE,showWarnings=FALSE);brohn_require(!file.exists(path),"A CSV payload already exists.")
  con<-file(path,"wb");on.exit(close(con),add=TRUE)
  line<-function(cells)writeBin(charToRaw(enc2utf8(paste0(paste(paste0('"',gsub('"','""',enc2utf8(cells),fixed=TRUE),'"'),collapse=","),"\r\n"))),con)
  encode<-function(x)if(is.null(x))""else if(is.character(x)&&length(x)==1L){
    if(grepl("^[[:space:]]*[=+@-]",x))paste0("'",x)else x
  }else brohn_json(x)
  line(columns)
  for(i in seq_along(rows)){
    row<-rows[[i]];canonical<-brohn_json(row)
    line(vapply(columns,function(k)if(k=="source_order")as.character(i)else if(k=="record_json")canonical else encode(row[[k]]),character(1)))
  }
  invisible(path)
}

# Registered scientific-record vocabulary for this bounded first profile.
# Free typed response values are data, so their object keys are never interpreted
# as field names or identities. Unsupported new scientific fields fail closed.
.brohn_rp_scientific_keys <- strsplit(paste(
  "schema schema_version kind title status features observations contrasts quality parameters limitations scales questionnaire_revision artifacts task_scores choice_tasks recordings",
  "participant_id session_id run_id source_participant_id source_session_id proposed_participant_id proposed_session_id participant_linkage",
  "stimulus_id exposure_id assessment_id assessment_exposure_id event_id first_answer_event_id last_answer_event_id visit_id occurrence_id step_id instance_id",
  "source_exposure_id source_recording_id source_segment_id source_report_id report_id source_report_hash source_row_hash source_row source_index source_container source_record",
  "condition_id aoi_id aoi_label valid_ms inside_ms valid_share_percent crossing_interval_ms fixation_candidate_count fixation_dwell_ms mean_fixation_duration_ms",
  "first_observed_candidate_from_recorded_start_ms first_observed_candidate_from_exposure_ms ttff_ms ttff_status censor_time_ms exposure_duration_ms observed_span_ms complete_observation valid_coverage denominator aoi_assignment",
  "first_observed_aoi_contact_ms first_contact_status unobserved_ms retained_interval_count invalid_interval_count observation_span_ms",
  "record_type x y start_ms end_ms duration_ms qualified boundary_truncated sample_count source_first_row source_last_row aoi_ids peak_velocity_deg_s mean_velocity_deg_s amplitude_deg",
  "reason from_aoi to_aoi from_end_ms to_start_ms observed_duration_ms onset_unobserved offset_unobserved onset_unobserved_reasons offset_unobserved_reasons record_boundary unsupported_gap label_continues_outside_passive_phase boundary_policy source",
  "unit valid_pupil_ms valid_pupil_coverage mean_pupil baseline_mean baseline_valid_ms baseline_coverage baseline_status baseline_corrected_mean integration",
  "passive_sample_count invalid_passive_sample_count valid_interval_ms unobserved_interval_ms saccade_candidate_count median_sample_interval_ms maximum_sample_interval_ms left_eye_unavailable_samples right_eye_unavailable_samples",
  "question_id prompt value missing_reason information scope ever_visited invalidated dependency_generation answer_version revision_count sequence response_time_ms active_segment_response_ms resumed origin",
  "condition_label scale_description response_count answered_count numeric_summary_status missing_count numeric_response_mean counts label count",
  "metric outcome_id outcome_label control_id test_id control_label test_label estimate interval95 lower upper method participant_count paired_session_count excluded_session_count p_value p_adjusted rejects_null aggregation participant_differences session_differences session_count value control_observations test_observations",
  "multiplicity family_size alpha valid_hypothesis_count unavailable_hypothesis_count adjusted_hypothesis_count interpretation confidence level tail degrees_freedom standard_error standard_deviation statistic",
  "report_ids modality candidate_source_rows eligible_source_rows unavailable_sources definition_hash definition_hashes source_rows eligible_rows excluded_rows eligible source_eligible source_missing_reason original_source_report_hash original_source_row_hash original_source_row",
  "source_count usable scientifically_qualified selected_report_count available_report_count source_observation_count eligible_observation_count unlinked_observation_count declared_comparison_count estimable_comparison_count cross_modal_complete_case_filter",
  "passive_rows invalid_passive_samples candidate_records retained_passive_rows excluded_other_phase_rows missing_outcome_count missing_response_count unlinked_session_count",
  "input thresholds geometry geometry_source coordinate_space time_unit interpolation smoothing merging blink_boundary_policy terminal_sample edge_policy pupil_baseline phase_column phase_value source_phase",
  "width_mm height_mm distance_mm center_x_mm center_y_mm velocity_threshold_deg_s min_fixation_ms min_saccade_ms max_gap_ms",
  "mode start_column end_column minimum_duration_ms minimum_coverage inference_unit missing analysis_plan design_policy measurement_design_hash identity_source observation_weighting",
  "recipe provenance design_hash scales_hash scale_id scale_version scale_hash scoring conversion items question_id reverse min max aggregation missing minimum_answered prorate converted_value raw_value answered_items missing_items item_values item_count answered_count required_count score status reason",
  "runs protocol_hash policy_hash events_hash projection_hash effective_records history_records history_events invalidations history_values final_sequence event_count visit_count occurrence_count sealed_occurrence_count",
  "id type payload clock monotonic_ms time_origin_ms time_ms timestamp_ms clock_id unit value instance_id kind state_version confirmation source_event_hash",
  "invalidated_by_event_id invalidated_event_id trigger_event_id invalidated_step_id invalidated_question_id invalidated_value previous_value from_step_id to_step_id",
  "assessment_count known_assessments unassigned_records repeated_assessment_records participant_linkage_complete source_records usable_records invalid_or_unsupported descriptive_unit quantitative summary categories bins states scale_key family item_id",
  "n mean median minimum maximum value_kind value_json upper_inclusive analysis_sha256 report_hash binding project_id source_binding",
  "paired control_mean test_mean difference paired_sessions unavailable_observations source_id source_report_ids source_hash comparison_id report_revision result_object artifact",
  "usable_outcome_count evidence eligible_count complete_count total_count source_row_count row_count source_unit status reason definition",
  "selected design_revision study_revision study_id dataset_id revision hash source_metadata_hash original_origin compatibility design_compatibility_policy material_identity",
  "observed_timing visibility_event_count allocation_index finalized_at deployment_id protocol_sha256 protocol_bytes journal_sha256 journal_bytes journal_rows_hash",
  "displayed acknowledged committed invalidation_count source_event_count scope title prompt items values assessment_scope item_scores item_support missingness missing_policy value_before_conversion answer_hash",
  "mean_difference sample_sd df t critical_value family tested available declared_outcome_count executed_comparison_count hypothesis_count correction hypotheses alpha confidence_level",
  "interval_span_ms available_tests missing_hypotheses aoi_map aois asset_hash height width source_design_hash source_report_revision support question option_assignment options randomize_options required rows show_if step question_type extracted_rows",
  "clock_segment_id from_visit_id phase previous_answer_event_id cause_event_id previous_head_event_id rule_hash source_projection_hash not_scoreable_count scored_assessment_count item_evidence invalid keyed_value input_row response_hash score_id prorated raw_aggregate raw_max raw_min total_items questionnaire responses_hash version answer_projection_hash questionnaire_policy_hash source_response_count unassigned unassigned_response_count",
  sep=" ")," +")[[1L]]

.brohn_rp_validate_scientific <- function(x,path="analysis",depth=0L) {
  brohn_require(depth<60L,"Scientific projection nesting exceeds its bound.")
  if(!is.list(x)){brohn_canonical(x);return(invisible(TRUE))}
  if(!is.null(names(x))){
    brohn_require(!anyDuplicated(names(x))&&all(nzchar(names(x))),"Scientific projection has duplicate/empty field names.")
    unknown<-setdiff(names(x),.brohn_rp_scientific_keys)
    brohn_require(!length(unknown),paste("Unsupported required scientific fields at",path,":",paste(unknown,collapse=", ")))
    for(k in names(x)){
      if(k %in% c("value","previous_value","invalidated_value","item_values","value_before_conversion")){brohn_canonical(x[[k]]);next}
      .brohn_rp_validate_scientific(x[[k]],paste0(path,"/",k),depth+1L)
    }
  }else for(i in seq_along(x)).brohn_rp_validate_scientific(x[[i]],paste0(path,"/*"),depth+1L)
  invisible(TRUE)
}
.brohn_rp_alias_context <- function(mode,reports) {
  maps<-new.env(parent=emptyenv());counts<-new.env(parent=emptyenv())
  registry<-list();relations<-list();owners<-new.env(parent=emptyenv());scores<-new.env(parent=emptyenv())
  register<-function(id,hash,revision,project_id,kind="report",key=NULL){
    brohn_require(brohn_text(id,96)&&.brohn_rp_hash(hash)&&brohn_number(revision,1,integer=TRUE)&&brohn_text(project_id,96)&&identical(kind,"report"),"Source identity needs its exact saved report/project/revision/hash.")
    hit<-Filter(function(r)identical(r$id,id)&&identical(r$hash,hash)&&r$revision==revision&&identical(r$project_id,project_id)&&identical(r$kind,kind),registry)
    if(length(hit)){
      brohn_require(is.null(key)||identical(key,hit[[1L]]$key),"An exact selected source report is duplicated.");return(hit[[1L]]$key)
    }
    if(is.null(key))key<-sprintf("related-source-%02d",length(registry)+1L)
    registry[[length(registry)+1L]]<<-list(id=id,hash=hash,revision=revision,project_id=project_id,kind=kind,key=key);key
  }
  for(i in seq_along(reports)){
    ref<-reports[[i]]$ref;register(ref$id,ref$body_hash,ref$revision,ref$project_id,ref$kind,sprintf("report-%02d",i))
  }
  for(i in seq_along(reports)){
    key<-sprintf("report-%02d",i);r<-reports[[i]];edges<-list(list(id=r$ref$id,hash=r$ref$body_hash,revision=r$ref$revision,project_id=r$ref$project_id,kind=r$ref$kind,key=key))
    for(s in r$saved_body$provenance$selection)if(!is.null(s$hash))edges[[length(edges)+1L]]<-list(id=s$id,hash=s$hash,revision=s$revision,project_id=r$ref$project_id,kind="report",
      key=register(s$id,s$hash,s$revision,r$ref$project_id))
    for(s in r$saved_body$provenance$source_reports)edges[[length(edges)+1L]]<-list(id=s$id,hash=s$body_hash,revision=s$revision,project_id=r$ref$project_id,kind="report",
      key=register(s$id,s$body_hash,s$revision,r$ref$project_id))
    relations[[key]]<-edges
  }
  resolve<-function(namespace,id,hash=NULL,revision=NULL){
    if(is.null(id))return(namespace)
    own<-Filter(function(r)identical(r$key,namespace),registry);brohn_require(length(own)==1L,"An alias namespace has no exact source identity.")
    matches<-function(r)identical(r$id,id)&&identical(r$project_id,own[[1L]]$project_id)&&identical(r$kind,"report")&&
      (is.null(hash)||identical(r$hash,hash))&&(is.null(revision)||r$revision==revision)
    bound<-Filter(function(r)identical(r$id,id),relations[[namespace]])
    candidates<-if(length(bound))Filter(matches,bound)else Filter(matches,registry)
    keys<-unique(vapply(candidates,`[[`,character(1),"key"))
    brohn_require(length(keys)==1L,paste("A source identity has no unambiguous exact report binding:",namespace,brohn_json(id)));keys[[1L]]
  }
  remember<-function(namespace,person,session){
    if(is.null(person)||is.null(session))return(invisible(NULL))
    key<-brohn_json(list(namespace,session));prior<-get0(key,owners,ifnotfound=character())
    assign(key,unique(c(prior,person)),owners);invisible(NULL)
  }
  scan<-function(x,namespace,person=NULL,session=NULL){
    if(!is.list(x))return(invisible(NULL))
    if(is.null(names(x))){for(z in x)scan(z,namespace,person,session);return(invisible(NULL))}
    person<-brohn_default(x$participant_id,person);session<-brohn_default(x$session_id,brohn_default(x$run_id,session));remember(namespace,person,session)
    needs_source<-any(c("source_participant_id","source_session_id","source_exposure_id","source_recording_id","source_segment_id")%in%names(x))
    src<-if(needs_source&&!is.null(x[["source_report_id"]]))resolve(namespace,x[["source_report_id"]],x[["source_report_hash"]],x[["source_report_revision"]])else if(!is.null(x[["report_id"]])&&!is.null(x$source_participant_id))resolve(namespace,x[["report_id"]])else namespace
    remember(src,x$source_participant_id,x$source_session_id)
    for(k in setdiff(names(x),c("value","previous_value","invalidated_value","item_values","value_before_conversion","design")))scan(x[[k]],namespace,person,session)
  }
  for(i in seq_along(reports)){
    ns<-sprintf("report-%02d",i);scan(reports[[i]]$complete_analysis,ns);scan(reports[[i]]$saved_body$provenance,ns)
    for(score in reports[[i]]$complete_analysis$scales$observations){
      key<-brohn_json(list(ns,score$id));brohn_require(!exists(key,scores,inherits=FALSE),"Duplicate original scale score identity.")
      assign(key,list(person=score$participant_id,session=score$session_id),scores)
    }
  }
  score_context<-function(namespace,id){
    key<-brohn_json(list(namespace,id));brohn_require(exists(key,scores,inherits=FALSE),"Scale item evidence has no complete original assessment score.");get(key,scores,inherits=FALSE)
  }
  owner<-function(namespace,session,person=NULL){
    if(!is.null(person)||is.null(session))return(person)
    candidates<-get0(brohn_json(list(namespace,session)),owners,ifnotfound=character())
    brohn_require(length(candidates)<=1L,"A person-free run reference is ambiguous across saved people.")
    if(length(candidates))candidates[[1L]]else NULL
  }
  label<-function(namespace,kind,id,person=NULL,session=NULL){
    if(is.null(id))return(NULL)
    brohn_require(brohn_text(id,4096,TRUE),"An identity cannot be projected as a scalar string.")
    if(mode=="source_identifiers")return(id)
    if(kind=="session")person<-owner(namespace,id,person)
    else if(kind!="person")person<-owner(namespace,session,person)
    key<-brohn_json(list(namespace,kind,person,session,id));counter<-paste(namespace,kind,sep="|")
    if(!exists(key,maps,inherits=FALSE)){
      n<-if(exists(counter,counts,inherits=FALSE))get(counter,counts)else 0L;n<-n+1L;assign(counter,n,counts)
      assign(key,paste0(namespace,"-",kind,"-",sprintf("%04d",n)),maps)
    };get(key,maps,inherits=FALSE)
  }
  list(mode=mode,label=label,resolve=resolve,owner=owner,score_context=score_context)
}
.brohn_rp_project <- function(x,aliases,namespace,path="analysis",person=NULL,session=NULL) {
  eda_own<-aliases$eda_states[[namespace]]
  if(!is.null(eda_own)&&grepl("/(original_source_row|original_source_record)(/|$)",path))return(eda_own$project(x,path))
  if(!is.list(x))return(x)
  if(is.null(names(x)))return(lapply(x,.brohn_rp_project,aliases=aliases,namespace=namespace,path=paste0(path,"/*"),person=person,session=session))
  original_person<-brohn_default(x$participant_id,person)
  original_session<-brohn_default(x$session_id,brohn_default(x$run_id,session))
  if(!is.null(x[["score_id"]])&&grepl("/item_evidence/",paste0(path,"/"),fixed=TRUE)){
    context<-aliases$score_context(namespace,x[["score_id"]]);original_person<-context$person;original_session<-context$session
  }
  if(is.null(original_person)&&length(x$effective_records))original_person<-x$effective_records[[1L]]$participant_id
  original_person<-aliases$owner(namespace,original_session,original_person)
  needs_source<-any(c("source_participant_id","source_session_id","source_exposure_id","source_recording_id","source_segment_id")%in%names(x))||is.list(x[["original_source_row"]])||is.list(x[["original_source_record"]])
  source_namespace<-if(needs_source&&!is.null(x[["source_report_id"]]))aliases$resolve(namespace,x[["source_report_id"]],x[["source_report_hash"]],x[["source_report_revision"]])else
    if(!is.null(x[["report_id"]])&&grepl("crosswalk",path,fixed=TRUE))aliases$resolve(namespace,x[["report_id"]])else namespace
  source_person<-if("source_participant_id"%in%names(x))x[["source_participant_id"]]else if(source_namespace==namespace)original_person else NULL
  source_session<-if("source_session_id"%in%names(x))x[["source_session_id"]]else if(source_namespace==namespace)original_session else NULL
  eda_source<-aliases$eda_states[[source_namespace]]
  out<-x
  person_keys<-c("participant_id","proposed_participant_id")
  session_keys<-c("session_id","run_id","proposed_session_id")
  identity_kind<-c(exposure_id="exposure",assessment_exposure_id="exposure",assessment_id="assessment",event_id="event",
    first_answer_event_id="event",last_answer_event_id="event",visit_id="visit",step_id="step",occurrence_id="occurrence",instance_id="clock-instance",
    from_step_id="step",to_step_id="step",invalidated_by_event_id="event",invalidated_event_id="event",trigger_event_id="event",
    previous_answer_event_id="event",cause_event_id="event",previous_head_event_id="event",from_visit_id="visit",clock_segment_id="clock-instance")
  for(k in names(x)){
    if(k %in% c("value","previous_value","invalidated_value","item_values","value_before_conversion"))next
    if(k %in% person_keys)out[k]<-list(aliases$label(namespace,"person",x[[k]]))
    else if(k %in% session_keys)out[k]<-list(aliases$label(namespace,"session",x[[k]],original_person))
    else if(k=="source_participant_id")out[k]<-list(aliases$label(source_namespace,"person",x[[k]]))
    else if(k=="source_session_id")out[k]<-list(aliases$label(source_namespace,"session",x[[k]],source_person))
    else if(k %in% c("source_exposure_id","source_recording_id","source_segment_id"))out[k]<-list(if(is.null(eda_source))aliases$label(source_namespace,sub("_id$","",sub("^source_","",k)),x[[k]],source_person,source_session)else
      eda_source$label(sub("_id$","",sub("^source_","",k)),x[[k]],x$source_recording_id,brohn_default(x$support$channel,x$outcome_id),list(participant_id=source_person,session_id=source_session)))
    else if(k=="support"&&!is.null(eda_source)&&!is.null(x$source_recording_id))out[k]<-list(eda_source$project(x[[k]],"source_support",x$source_recording_id,brohn_default(x$support$channel,x$outcome_id),list(participant_id=source_person,session_id=source_session)))
    else if(k %in% names(identity_kind))out[k]<-list(aliases$label(namespace,unname(identity_kind[[k]]),x[[k]],original_person,original_session))
    else if(k=="id"&&grepl("/history_events/",paste0(path,"/"),fixed=TRUE))out[k]<-list(aliases$label(namespace,"event",x[[k]],original_person,original_session))
    else if(k=="id"&&grepl("^provenance/(run_evidence/)?runs/\\*$",path))out[k]<-list(aliases$label(namespace,"session",x[[k]],original_person))
    # A paired model source_record is a row of its current analysis (possibly
    # multimodal); only explicitly original source records change namespace.
    else if(k%in%c("original_source_row","original_source_record")&&is.list(x[[k]]))out[k]<-list(.brohn_rp_project(x[[k]],aliases,source_namespace,paste0(path,"/",k),x$source_participant_id,x$source_session_id))
    else out[k]<-list(.brohn_rp_project(x[[k]],aliases,namespace,paste0(path,"/",k),original_person,original_session))
  }
  out
}
.brohn_rp_projection <- function(item,aliases,namespace,task_evidence=NULL,choice_evidence=NULL,source_admission=NULL) {
  body<-item$saved_body;a<-item$complete_analysis
  brohn_fields(body,c("id","title","origin","analysis","provenance"),c("schema_version","created_at","status","study_id","dataset_id","project_id","processing","result_object","session_quality"),"Saved report projection")
  if(!is.null(choice_evidence)){
    brohn_validate_complete_report_analysis(item,"task-choice-findings/0.1")
    brohn_validate_choice_display_evidence(choice_evidence,item)
    brohn_require((length(a$task_scores)>0L)==!is.null(task_evidence),"Mixed native task/choice evidence requires both complete prepared components.")
    if(!is.null(task_evidence)){
      brohn_require(identical(task_evidence$schema,"brohn-task-display-evidence/0.2"),"Choice-capable source requires the explicitly wider task preparation.")
      brohn_validate_task_display_evidence(task_evidence,item)
    }
  }else if(is.null(task_evidence)){
  brohn_fields(a,c("kind","features","observations","contrasts","parameters","quality","limitations"),
    c("title","schema","status","scales","questionnaire_revision","artifacts","task_scores","choice_tasks","recordings"),"Complete scientific analysis")
  brohn_require(a$kind %in% c("gaze","questionnaire","multimodal")&&!brohn_questionnaire_is_artifact(a),"Complete findings require a supported full analysis, not its catalog preview.")
  brohn_require(!length(a$artifacts)&&!length(a$task_scores)&&!length(a$choice_tasks),
    "This complete analysis also contains artifact/task/choice evidence without a package adapter. Keep its original export or choose a report fully supported by this profile.")
  if(identical(source_admission,"task-choice-eda-findings/0.1")&&identical(a$kind,"multimodal"))brohn_validate_complete_report_analysis(item,source_admission)else .brohn_rp_validate_scientific(a)
  }else{
    brohn_validate_task_display_evidence(task_evidence,item)
    if(identical(a$kind,"questionnaire")){
      classic<-a;classic$task_scores<-list();.brohn_rp_validate_scientific(classic)
      brohn_require(!length(a$artifacts)&&!length(a$choice_tasks),"Task projection does not silently omit artifact or choice-task evidence.")
    }
  }
  p<-body$provenance
  brohn_fields(p,c("design","design_hash"),c("engine","origin","study_id","study_revision","source","mapping","dataset_id","dataset_revision","dataset_hash","runs","cohort_policy","run_evidence","selection","crosswalk","crosswalk_hash","identity_source","declared_contrasts","request_hash",
    if(!is.null(task_evidence))c("source_reports","source_administrations","plan","identity_map")),"Scientific provenance")
  brohn_require(identical(brohn_hash(p$design),p$design_hash),"Saved design hash is inconsistent.")
  brohn_validate_design(p$design)
  projected<-if(is.null(task_evidence)).brohn_rp_project(a,aliases,namespace)else .brohn_rpt_analysis(item,task_evidence,aliases,namespace)
  if(!is.null(choice_evidence))projected<-.brohn_rpc_analysis(item,projected,aliases,namespace)
  provenance<-p
  if(!is.null(provenance$source)){
    brohn_fields(provenance$source,c("hash"),c("size","bytes","media_type","format","filename","path","name"),"Original source descriptor")
    provenance$source<-provenance$source[intersect(c("hash","size","bytes","media_type","format"),names(provenance$source))]
  }
  if(!is.null(provenance$run_evidence)){
    brohn_fields(provenance$run_evidence,c("binding_hash","runs"),c("schema","request_hash","workspace_id","job_id","attempt"),"Run evidence provenance")
    provenance$run_evidence<-provenance$run_evidence[intersect(c("schema","request_hash","binding_hash","runs"),names(provenance$run_evidence))]
  }
  for(i in seq_along(provenance$design$stimuli))if(!is.null(provenance$design$stimuli[[i]]$asset)){
    asset<-provenance$design$stimuli[[i]]$asset;provenance$design$stimuli[[i]]$asset<-asset[setdiff(names(asset),c("filename","path"))]
  }
  # Only these registered provenance containers carry person/session identities.
  for(k in intersect(c("runs","crosswalk","run_evidence"),names(provenance)))provenance[k]<-list(.brohn_rp_project(provenance[[k]],aliases,namespace,paste0("provenance/",k)))
  if(!is.null(task_evidence))provenance<-.brohn_rpt_provenance(provenance,item,task_evidence,aliases,namespace)
  processing<-body$processing
  if(!is.null(processing))brohn_fields(processing,c("recipe"),c("code_hashes","output_hash","request_hash","attempt","job_id","publication"),"Saved report producer")
  producer<-if(is.null(processing))NULL else processing[intersect(c("recipe","code_hashes","output_hash","request_hash"),names(processing))]
  list(schema="brohn-portable-numerical-evidence/0.1",source_ref=item$ref,
    source_analysis_sha256=brohn_hash(a),source_result_object=body$result_object,
    projection_profile="scientific-values-and-local-labels/0.1",identifier_mode=aliases$mode,
    counts=c(if(!is.null(choice_evidence)&&identical(a$kind,"explicit_choice"))list(choice_tasks=length(a$choice_tasks),observations=length(a$observations),source_rows=length(a$source_rows))else if(is.null(task_evidence)).brohn_questionnaire_counts(a)else .brohn_rpt_counts(a),list(contrasts=length(a$contrasts),recordings=length(a$recordings),scale_item_evidence=length(a$scales$item_evidence),
      scale_source_references=sum(vapply(a$scales$item_evidence,function(e)sum(vapply(e$items,function(i)length(i$source),integer(1))),integer(1))))),
    report=body[intersect(c("id","title","origin","schema_version","created_at","status","study_id","dataset_id"),names(body))],
    analysis=projected,provenance=provenance,producer=producer,
    session_quality=.brohn_rp_project(body$session_quality,aliases,namespace,"session_quality"),
    policy=list(scientific_values="Complete saved typed values and ordering; no scoring or inference added.",
      identifiers="Labels are scoped to exact source report; saved crosswalk relationships remain explicit. This is not anonymization; free text remains verbatim.",
      omitted_operational_paths=c(list("report.processing except recipe/code_hashes/output_hash/request_hash","report.project_id",
        "provenance.source filename/path/name","provenance.run_evidence workspace_id/job_id/attempt","provenance.design.stimuli[].asset filename/path"),
        if(!is.null(task_evidence))list("provenance.design.blocks[].materials[].asset filename/path","protocol registry descriptors filename/path")),
      original_raw_bytes_reverified=FALSE))
}
