# Source-bound adapters only. Shared loaders, worker dispatch and report rendering
# must register these functions explicitly; no automatic processing on source().
.brohn_tc_study <- function(store,id,project_id=NULL) {
  brohn_require(brohn_valid_id(id),"Choose an existing study for task participants.")
  row<-DBI::dbGetQuery(store$con,"SELECT project_id FROM entities WHERE kind='study' AND id=?",params=list(id))
  brohn_require(nrow(row)==1L&&(is.null(project_id)||identical(row$project_id[[1L]],project_id)),"The selected study is outside this project or unavailable.")
  brohn_get_entity(store,"study",id)
}
brohn_task_cohort_report_catalog <- function(store,study_id,project_id=NULL,limit=40L,offset=0L) {
  study<-.brohn_tc_study(store,study_id,project_id)
  brohn_require(brohn_number(limit,1,100,TRUE)&&brohn_number(offset,0,1e8,TRUE),"Choose a bounded saved task-report page.")
  from<-paste("FROM entities e JOIN entity_versions v ON e.kind=v.kind AND e.id=v.id AND e.revision=v.revision",
    "WHERE e.kind='report' AND e.project_id=? AND json_extract(v.body_json,'$.study_id')=?",
    "AND ((json_type(v.body_json,'$.analysis.task_attempts')='array' AND json_array_length(v.body_json,'$.analysis.task_attempts')>0)",
    "OR (json_type(v.body_json,'$.analysis.task_scores')='array' AND json_array_length(v.body_json,'$.analysis.task_scores')>0))")
  parameters<-list(study$project_id,study_id)
  read<-function() {
    total<-DBI::dbGetQuery(store$con,paste("SELECT count(*) AS n",from),params=parameters)$n[[1L]]
    actual<-if(total)min(offset,floor((total-1L)/limit)*limit)else 0L
    query<-paste("SELECT e.id,e.revision,e.project_id,e.updated_at,",
      "json_extract(v.body_json,'$.title') AS title,json_extract(v.body_json,'$.origin') AS origin,",
      "json_extract(v.body_json,'$.created_at') AS created_at,",
      "coalesce(json_array_length(v.body_json,'$.analysis.task_attempts'),0) AS attempt_count,",
      "coalesce(json_array_length(v.body_json,'$.analysis.task_scores'),0) AS score_count",from,
      "ORDER BY e.updated_at DESC,e.id ASC LIMIT ? OFFSET ?")
    rows<-DBI::dbGetQuery(store$con,query,params=c(parameters,list(limit,actual)))
    records<-lapply(seq_len(nrow(rows)),function(i) {
      r<-as.list(rows[i,,drop=FALSE]);r<-lapply(r,function(x)if(is.na(x))NULL else unname(x))
      r$status<-if(r$attempt_count>0)"requires_source_verification" else "unsupported_source"
      r$reason<-if(r$attempt_count>0)NULL else "This report has summary task scores without canonical source-bound administrations. Export trials and registry, then import the declared summary; that import does not inherit native replay qualification."
      r
    })
    list(study_id=study_id,project_id=study$project_id,total=total,limit=limit,offset=actual,records=records,
      has_previous=actual>0L,has_next=actual+length(records)<total,
      qualification="Metadata discovery only; selected report objects and administrations are verified during review.")
  }
  if(RSQLite::sqliteIsTransacting(store$con))read()else DBI::dbWithTransaction(store$con,read())
}
.brohn_tc_report <- function(store,study,id,reference=NULL) {
  brohn_require(brohn_valid_id(id),"Choose a valid saved report identity.")
  owner<-DBI::dbGetQuery(store$con,"SELECT project_id FROM entities WHERE kind='report' AND id=?",params=list(id))
  # Never decode foreign report contents or return foreign titles/status.
  brohn_require(nrow(owner)==1L&&identical(owner$project_id[[1L]],study$project_id),"A selected report is unavailable or outside this study's project.")
  record<-brohn_get_entity(store,"report",id,if(is.null(reference))NULL else reference$revision)
  brohn_require(!is.null(record)&&identical(record$project_id,study$project_id),"The frozen report revision is unavailable; no newer report was substituted.")
  body<-record$body
  brohn_require(identical(body$study_id,study$id)&&is.list(body$provenance$design)&&
    identical(body$provenance$design$id,study$id)&&identical(body$provenance$design$project_id,study$project_id),"Choose reports belonging to this exact study and project.")
  brohn_validate_design(body$provenance$design)
  brohn_require(identical(body$provenance$design_hash,brohn_hash(body$provenance$design)),"The source report's frozen study design failed integrity verification.")
  object<-body$result_object
  brohn_require(is.list(object)&&.brohn_task_cohort_hash(object$hash)&&brohn_number(object$size,1,16*1024^2,TRUE),"The selected report needs its bounded retained full result object; no summary-only replacement is permitted.")
  path<-brohn_object_path(store,object$hash,verify=TRUE)
  brohn_require(identical(as.numeric(file.info(path)$size),as.numeric(object$size)),"The retained report byte count differs from its frozen result reference.")
  envelope<-brohn_read_json_file(path,16*1024^2)
  brohn_require(identical(envelope$schema,"brohn-analysis-output/1.0")&&is.list(envelope$report)&&
    identical(envelope$report$study_id,body$study_id)&&identical(envelope$report$origin,body$origin)&&
    identical(brohn_hash(envelope$report$provenance),brohn_hash(body$provenance))&&
    identical(brohn_hash(envelope$report$analysis),brohn_hash(body$analysis)),
    "The catalog and retained full result analysis differ. Preserve the original evidence and reanalyse explicitly; no precision or source repair is automatic.")
  observed<-list(id=id,revision=record$revision,body_hash=brohn_hash(body),result_object_hash=object$hash,
    result_object_size=object$size,design_hash=body$provenance$design_hash)
  if(!is.null(reference))brohn_require(identical(brohn_json(reference),brohn_json(observed)),"A frozen source report changed or failed integrity verification; no latest version was substituted.")
  list(record=record,reference=observed)
}
.brohn_tc_source <- function(selected,task_id=NULL,store,verified) {
  record<-selected$record;body<-record$body;attempts<-body$analysis$task_attempts
  supported<-identical(body$analysis$kind,"implicit")&&brohn_array(attempts)&&length(attempts)>0L
  reason<-if(supported)NULL else "This report has no supported canonical imported task administrations. Native summary reports need an explicit trial export and declared-summary import first; replay qualification is not inherited."
  if(supported) {
    brohn_require(length(attempts)<=5000L,"One source exceeds the supported administration count; choose an explicitly smaller source report.")
    for(a in attempts) {
      .brohn_task_cohort_attempt(a)
      for(hash in c(a$source$original_hash,a$source$registry_object_hash))if(!exists(hash,envir=verified,inherits=FALSE)) {
        brohn_object_path(store,hash,verify=TRUE);assign(hash,TRUE,envir=verified)
      }
      task<-brohn_find(body$provenance$design$blocks,a$task_id)
      brohn_require(!is.null(task)&&identical(brohn_hash(task),a$task_definition_hash)&&identical(a$collection_origin,body$origin),"A source administration does not match its report's exact frozen task or collection origin.")
      brohn_require(identical(a$evidence_level,"declared_trial_summary"),"This adapter currently accepts declared imported trial summaries only; native evidence requires its separately qualified canonical adapter.")
    }
    if(!is.null(task_id)) {
      brohn_require(brohn_text(task_id,96),"Choose an exact task identity.")
      attempts<-Filter(function(a)identical(a$task_id,task_id),attempts)
      if(!length(attempts)){supported<-FALSE;reason<-"This selected report contains no administration of the explicitly selected task."}
    }
  }
  list(report_id=record$id,title=body$title,origin=body$origin,status=if(supported)"supported"else"unsupported_source",
    reason=reason,reference=selected$reference,attempts=if(supported)attempts else list(),design=body$provenance$design)
}
brohn_task_cohort_catalog <- function(store,study_id,report_ids,task_id=NULL) {
  study<-.brohn_tc_study(store,study_id)
  brohn_require(brohn_array(report_ids)&&length(report_ids)>=1L&&length(report_ids)<=100L&&
    all(vapply(report_ids,brohn_valid_id,logical(1)))&&!anyDuplicated(unlist(report_ids)),"Select 1 to 100 distinct saved task reports.")
  verified<-new.env(parent=emptyenv())
  sources<-lapply(report_ids,function(id).brohn_tc_source(.brohn_tc_report(store,study,id),task_id,store,verified))
  attempts<-unlist(lapply(sources,`[[`,"attempts"),recursive=FALSE,use.names=FALSE)
  brohn_require(length(attempts)<=5000L,"Selected reports exceed 5,000 administrations; explicitly select fewer sources.")
  bindings<-unlist(lapply(sources,function(s)lapply(s$attempts,function(a)list(report_id=s$report_id,attempt_id=a$id,attempt_hash=brohn_hash(a)))),recursive=FALSE,use.names=FALSE)
  groups<-list();group_keys<-character()
  for(a in attempts) {
    key<-brohn_hash(.brohn_task_cohort_identity(a))
    if(!key %in% group_keys){group_keys<-c(group_keys,key);groups[[length(groups)+1L]]<-list(id=key,homogeneous=.brohn_task_cohort_identity(a),attempt_count=0L)}
    at<-match(key,group_keys);groups[[at]]$attempt_count<-groups[[at]]$attempt_count+1L
  }
  references<-lapply(sources,`[[`,"reference")
  list(schema="brohn-task-cohort-catalog/1.0",study_id=study_id,project_id=study$project_id,
    reports=lapply(sources,function(s)s[c("report_id","title","origin","status","reason","reference")]),
    report_ids=report_ids,task_id=task_id,attempts=attempts,bindings=bindings,groups=groups,
    design=if(length(sources))sources[[1L]]$design else NULL,
    identities=if(length(attempts))brohn_task_cohort_identity_rows(attempts)else NULL,
    selection_hash=brohn_hash(list(study_id=study_id,project_id=study$project_id,reports=references,bindings=bindings,task_id=task_id)))
}
.brohn_tc_validate_report_title <- function(title) {
  if(is.null(title))return(invisible(NULL))
  brohn_require(brohn_text(title,240)&&validUTF8(enc2utf8(title))&&nchar(enc2utf8(title),type="bytes")<=240L&&
    !any(utf8ToInt(enc2utf8(title)) %in% c(0:31,127:159)),"Use a nonblank report name of at most 240 UTF-8 bytes without control characters.")
  invisible(title)
}
brohn_prepare_task_cohort <- function(store,study_id,report_ids,attempt_ids,identity_map,repeat_policy,description,expected_selection_hash,task_id=NULL,report_title=NULL) {
  .brohn_tc_validate_report_title(report_title)
  catalog<-brohn_task_cohort_catalog(store,study_id,report_ids,task_id)
  brohn_require(identical(catalog$selection_hash,expected_selection_hash),"The saved report selection changed after review. Review the exact sources again.")
  brohn_require(all(vapply(catalog$reports,function(r)r$status=="supported",logical(1))),"Remove unsupported source reports explicitly; they cannot be silently dropped from this selection.")
  brohn_require(brohn_array(attempt_ids)&&length(attempt_ids)>0L&&length(attempt_ids)<=5000L&&
    all(vapply(attempt_ids,brohn_text,logical(1),max=240))&&!anyDuplicated(unlist(attempt_ids)),"Select distinct exact administrations, including any unavailable ones you intend to retain.")
  available<-vapply(catalog$attempts,`[[`,character(1),"id")
  brohn_require(!anyDuplicated(available),"Selected source reports repeat an administration. Remove the duplicate report before reviewing membership.")
  brohn_require(all(unlist(attempt_ids) %in% available),"A selected administration is absent from the reviewed reports.")
  chosen<-catalog$attempts[match(unlist(attempt_ids),available)]
  bindings<-Filter(function(b)b$attempt_id %in% unlist(attempt_ids),catalog$bindings)
  brohn_require(setequal(vapply(bindings,`[[`,character(1),"report_id"),unlist(report_ids)),"Every selected report must contribute an explicitly selected administration; remove unused reports.")
  plan<-list(schema="brohn-task-cohort-plan/1.0",description=description,
    membership=lapply(chosen,function(a)list(attempt_id=a$id,attempt_hash=brohn_hash(a))),
    homogeneous=.brohn_task_cohort_identity(chosen[[1L]]),repeat_policy=repeat_policy)
  # Full pure validation and identity/repeat preview happen before any queue write.
  brohn_task_cohort(chosen,plan,identity_map)
  references<-lapply(catalog$reports,`[[`,"reference")
  request<-list(schema="brohn-task-cohort-request/1.0",recipe="brohn-task-cohort-descriptive/1.0",study_id=study_id,project_id=catalog$project_id,
    design=catalog$design,design_hash=brohn_hash(catalog$design),origin=plan$homogeneous$collection_origin,
    reports=references,bindings=bindings,plan=plan,plan_hash=brohn_hash(plan),identity_map=identity_map,
    identity_map_hash=brohn_hash(identity_map),selection_hash=catalog$selection_hash,task_id=task_id)
  if(!is.null(report_title))request$report_title<-report_title
  brohn_require(nchar(brohn_json(request),type="bytes")<=4*1024^2,"The frozen cohort request exceeds 4 MiB; explicitly select a smaller group.")
  request
}
brohn_queue_task_cohort <- function(store,study_id,report_ids,attempt_ids,identity_map,repeat_policy,description,expected_selection_hash,task_id=NULL,report_title=NULL) {
  request<-brohn_prepare_task_cohort(store,study_id,report_ids,attempt_ids,identity_map,repeat_policy,description,expected_selection_hash,task_id,report_title)
  brohn_enqueue_job(store,"analyse_task_cohort",request,paste0("task-cohort:",brohn_hash(request)))
}
brohn_task_cohort_input <- function(store,request) {
  brohn_fields(request,c("schema","recipe","study_id","project_id","design","design_hash","origin","reports","bindings","plan","plan_hash","identity_map","identity_map_hash","selection_hash","task_id"),optional="report_title",label="Frozen task cohort request")
  .brohn_tc_validate_report_title(request$report_title)
  brohn_require(identical(request$schema,"brohn-task-cohort-request/1.0")&&identical(request$recipe,"brohn-task-cohort-descriptive/1.0"),"Unsupported frozen task cohort recipe.")
  brohn_require(identical(request$plan_hash,brohn_hash(request$plan))&&identical(request$identity_map_hash,brohn_hash(request$identity_map)),
    "The frozen task plan or identity map changed after review.")
  study<-.brohn_tc_study(store,request$study_id,request$project_id)
  brohn_validate_design(request$design)
  brohn_require(identical(request$design_hash,brohn_hash(request$design))&&identical(request$design$id,study$id)&&identical(request$design$project_id,study$project_id),"The frozen cohort study failed identity verification.")
  brohn_require(brohn_array(request$reports)&&length(request$reports)>0L&&length(request$reports)<=100L&&brohn_array(request$bindings),"Frozen task cohort references are invalid.")
  report_ids<-vapply(request$reports,function(ref){brohn_fields(ref,c("id","revision","body_hash","result_object_hash","result_object_size","design_hash"),label="Frozen report reference");brohn_require(brohn_valid_id(ref$id)&&brohn_number(ref$revision,1,.Machine$integer.max,TRUE),"Invalid frozen report revision.");ref$id},character(1))
  brohn_require(!anyDuplicated(report_ids),"Frozen report identities cannot repeat.")
  verified<-new.env(parent=emptyenv())
  sources<-lapply(request$reports,function(ref).brohn_tc_source(.brohn_tc_report(store,study,ref$id,ref),request$task_id,store,verified))
  brohn_require(all(vapply(sources,function(s)s$status=="supported",logical(1))),"A frozen source no longer supplies canonical imported administrations; no replacement was selected.")
  all_attempts<-unlist(lapply(sources,`[[`,"attempts"),recursive=FALSE,use.names=FALSE)
  all_bindings<-unlist(lapply(sources,function(s)lapply(s$attempts,function(a)list(report_id=s$report_id,attempt_id=a$id,attempt_hash=brohn_hash(a)))),recursive=FALSE,use.names=FALSE)
  expected_selection<-brohn_hash(list(study_id=study$id,project_id=study$project_id,reports=lapply(sources,`[[`,"reference"),bindings=all_bindings,task_id=request$task_id))
  brohn_require(identical(expected_selection,request$selection_hash),"The full reviewed selection failed its frozen hash; no source was substituted.")
  selected_ids<-vapply(request$plan$membership,`[[`,character(1),"attempt_id");available<-vapply(all_attempts,`[[`,character(1),"id")
  brohn_require(!anyDuplicated(available)&&all(selected_ids %in% available),"Selected canonical administration evidence is missing or duplicated.")
  expected_bindings<-Filter(function(b)b$attempt_id %in% selected_ids,all_bindings)
  brohn_require(identical(brohn_json(expected_bindings),brohn_json(request$bindings))&&setequal(vapply(expected_bindings,`[[`,character(1),"report_id"),report_ids),"Source-report administration bindings changed or omit a selected report.")
  selected<-all_attempts[match(selected_ids,available)]
  brohn_require(identical(request$origin,request$plan$homogeneous$collection_origin),"The cohort collection origin differs from its frozen plan.")
  brohn_task_cohort(selected,request$plan,request$identity_map)
  input<-list(schema="brohn-task-cohort-input/1.0",request=request,attempts=selected)
  brohn_require(nchar(brohn_json(input),type="bytes")<=12*1024^2,"The complete frozen cohort input exceeds 12 MiB; select fewer original administrations.")
  input
}
brohn_analyse_task_cohort <- function(input) {
  brohn_fields(input,c("schema","request","attempts"),label="Task cohort analysis input")
  brohn_require(identical(input$schema,"brohn-task-cohort-input/1.0"),"Unsupported task cohort input.")
  request<-input$request
  .brohn_tc_validate_report_title(request$report_title)
  brohn_require(identical(request$recipe,"brohn-task-cohort-descriptive/1.0")&&identical(brohn_hash(request$design),request$design_hash)&&
    identical(request$plan_hash,brohn_hash(request$plan))&&identical(request$identity_map_hash,brohn_hash(request$identity_map)),
    "Frozen task cohort recipe, design, plan or identity map failed verification.")
  analysis<-brohn_task_cohort(input$attempts,request$plan,request$identity_map)
  usable<-any(vapply(analysis$summaries,function(s)!is.null(s$mean),logical(1)))
  analysis$status<-if(usable)"completed"else "needs_review";analysis$quality$usable<-usable
  list(title=brohn_default(request$report_title,paste(request$design$title,"task participants")),study_id=request$study_id,dataset_id=NULL,origin=request$origin,
    provenance=list(design=request$design,design_hash=request$design_hash,source_reports=request$reports,
      source_administrations=request$bindings,plan=request$plan,identity_map=request$identity_map,request_hash=brohn_hash(request)),analysis=analysis)
}
