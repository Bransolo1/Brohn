# Exact task-source metadata and native holds. No eager cross-file calls.
.brohn_td_augment_metadata <- function(store,m) {
  row<-DBI::dbGetQuery(store$con,paste("SELECT json_extract(body_json,'$.analysis.parameters.schema') import_schema,",
    "json_extract(body_json,'$.analysis.parameters.source') import_source,json_extract(body_json,'$.analysis.parameters.mapping.protocol_registry') registry,",
    "json_extract(body_json,'$.provenance.runs') native_runs,json_extract(body_json,'$.provenance.source_reports') cohort_sources,",
    "json_extract(body_json,'$.provenance.source_administrations') cohort_administrations FROM entity_versions WHERE kind='report' AND id=? AND revision=? AND project_id=?"),params=list(m$ref$id,m$ref$revision,m$ref$project_id))
  brohn_require(nrow(row)==1L,"Exact task source metadata is unavailable.")
  field<-function(key).brohn_rpk_parse_optional(row[[key]][[1L]],2*1024^2)
  m$import_schema<-if(is.na(row$import_schema[[1L]]))NULL else row$import_schema[[1L]]
  m$import_source<-field("import_source");m$registry<-field("registry");m$native_runs<-brohn_default(field("native_runs"),list())
  m$cohort_sources<-brohn_default(field("cohort_sources"),list());m$cohort_administrations<-brohn_default(field("cohort_administrations"),list())
  m$source_family<-if(identical(m$kind,"questionnaire")&&m$task_score_count>0L)"native_questionnaire"else if(identical(m$kind,"implicit"))"imported_implicit"else if(identical(m$kind,"implicit_cohort"))"saved_task_cohort"else NULL
  m$choice_source_family<-if(identical(m$kind,"questionnaire")&&m$choice_task_count>0L)"native_questionnaire"else if(identical(m$kind,"explicit_choice"))"imported_choice"else NULL
  m$source_components<-c(if(identical(m$kind,"questionnaire"))list("explicit")else list(),if(!is.null(m$source_family))list("task")else list(),if(!is.null(m$choice_source_family))list("choice")else list())
  m
}
.brohn_td_unsupported <- function(m,source_admission="task-findings/0.1") {
  source_admission<-.brohn_rpk_admission(source_admission)
  if(is.null(m$source_family))return("This report has no complete task source family.")
  if(m$choice_task_count>0L&&!identical(source_admission,"task-choice-findings/0.1"))return("This saved report also includes choice-task evidence; its complete package adapter is not enabled yet.")
  if(length(m$artifacts)&&!identical(m$schema,"brohn-questionnaire-report-preview/1.0"))return("This saved report also includes unsupported scientific artifacts; all selected evidence must be supported.")
  if(m$source_family=="native_questionnaire"){
    if(!is.null(m$schema)&&!identical(m$schema,"brohn-questionnaire-report-preview/1.0"))return("This native task report has an unsupported saved analysis schema.")
    if(!length(m$native_runs)||length(m$native_runs)!=length(m$run_sources))return("This legacy native report lacks complete original protocol/journal receipts for its saved administrations. Its existing score export remains available.")
    if(!length(m$design$blocks)||!all(vapply(m$design$blocks,function(t)t$profile %in% .brohn_td_profiles,logical(1))))return("A frozen task profile is unsupported by this complete package adapter.")
  }else if(m$source_family=="imported_implicit"){
    if(!is.null(m$schema)||!identical(m$import_schema,"brohn-implicit-csv-import/1.0")||is.null(m$import_source)||is.null(m$registry))return("This imported task report lacks supported complete source/mapping/registry evidence.")
  }else if(!identical(m$schema,"brohn-task-cohort/1.0")||!length(m$cohort_sources)||!length(m$cohort_administrations))return("This cohort lacks its exact saved source administrations and reports.")
  NULL
}
.brohn_td_parent_refs <- function(m) {
  refs<-lapply(Filter(function(s)identical(s$state,"selected"),brohn_default(m$sources,list())),function(s)list(kind="report",id=s$id,revision=s$revision,body_hash=s$hash,project_id=m$ref$project_id))
  if(identical(m$source_family,"saved_task_cohort"))refs<-c(refs,lapply(m$cohort_sources,function(s)list(kind="report",id=s$id,revision=s$revision,body_hash=s$body_hash,project_id=m$ref$project_id)))
  refs
}
.brohn_td_extra_objects <- function(store,m) {
  result<-list()
  if(identical(m$source_family,"imported_implicit")){
    original_hash<-m$import_source$hash;registry_hash<-brohn_default(m$registry$hash,m$import_source$registry_object_hash)
    brohn_require(.brohn_td_sha(original_hash)&&.brohn_td_sha(registry_hash)&&identical(registry_hash,m$import_source$registry_object_hash),"Imported original and registry identities disagree.")
    result<-lapply(c(original_hash,registry_hash),function(hash){row<-DBI::dbGetQuery(store$con,"SELECT size,media_type FROM objects WHERE hash=?",params=list(hash))
      brohn_require(nrow(row)==1L,"An original task source object is no longer retained.")
      .brohn_rpk_object(store,list(hash=hash,bytes=row$size[[1L]],media_type=row$media_type[[1L]]),64*1024^2)})
  }
  # Task raster bytes are not packaged by this profile. Their frozen source
  # references still belong to the original authority/retention closure.
  if(!is.null(m$source_family))for(task in m$design$blocks)for(material in task$materials)if(!is.null(material$asset))
    result<-c(result,list(.brohn_rpk_object(store,material$asset,20*1024^2)))
  result
}
.brohn_td_metadata <- function(store,ref) {
  .brohn_rpk_ref_catalog(store,ref,"task_display")
  bounded<-DBI::dbGetQuery(store$con,"SELECT length(CAST(body_json AS BLOB)) bytes FROM entity_versions WHERE kind='task_display' AND id=? AND revision=? AND project_id=?",params=list(ref$id,ref$revision,ref$project_id))
  brohn_require(nrow(bounded)==1L&&bounded$bytes[[1L]]<=2*1024^2,"Saved task metadata exceeds its bounded reader.")
  record<-.brohn_rpk_record(store,ref,"task_display");b<-record$body
  brohn_require(nchar(brohn_json(b),type="bytes")<=2*1024^2&&identical(b$schema,.brohn_td_schema("brohn-saved-task-display",b$preparation_profile))&&identical(b$artifact_schema,.brohn_td_schema("brohn-task-display-evidence",b$preparation_profile))&&
    identical(b$project_id,ref$project_id)&&b$source_family %in% .brohn_td_families&&identical(b$implementation_hash,brohn_hash(b$implementation)),"Unsupported or oversized saved task display metadata.")
  source<-.brohn_rpk_report_metadata(store,b$source$report_ref);.brohn_rpk_report_proof(store,source,source_admission=.brohn_td_admission(b$preparation_profile))
  brohn_require(identical(b$study_id,source$study_id)&&identical(source$source_family,b$source_family)&&
    .brohn_td_same(b$source$result_object,.brohn_td_object_ref(source$result_object)),"Saved task display lost its exact original report identity.")
  object<-.brohn_rpk_object(store,b$artifact,32*1024^2);document<-.brohn_rpk_object(store,b$retained_document,2*1024^2)
  p<-b$producer;j<-brohn_get_job(store,p$job_id)
  brohn_require(!is.null(j)&&identical(j$operation,"task_display")&&identical(j$status,"succeeded")&&j$attempt==p$attempt&&
    identical(j$result$task_display_id,ref$id)&&identical(j$result$output_hash,document$hash)&&identical(brohn_hash(j$request),p$request_hash)&&
    .brohn_td_same(j$request$report_ref,b$source$report_ref)&&identical(j$request$schema,.brohn_td_schema("brohn-task-display-job",b$preparation_profile))&&identical(j$request$preparation_profile,b$preparation_profile)&&.brohn_td_same(j$request$implementation,b$implementation),"Saved task display does not match its original successful producer proof.")
  list(ref=ref,record=record,report_ref=b$source$report_ref,object=object,document=document)
}
brohn_find_task_display <- function(store,report_ref,preparation_profile=.brohn_td_profile,implementation_ref=brohn_task_display_implementation_ref(preparation_profile)) {
  .brohn_rpk_ref_catalog(store,report_ref,"report")
  brohn_require(preparation_profile %in% c(.brohn_td_profile,"saved-task-display/0.2")&&identical(implementation_ref$profile,preparation_profile)&&.brohn_td_sha(implementation_ref$hash),"Choose an exact supported task preparation identity.")
  rows<-DBI::dbGetQuery(store$con,paste("SELECT v.id,v.revision,v.body_hash FROM entities e JOIN entity_versions v ON e.kind=v.kind AND e.id=v.id AND e.revision=v.revision",
    "WHERE e.kind='task_display' AND e.project_id=? AND json_extract(v.body_json,'$.source.report_ref.id')=? AND json_extract(v.body_json,'$.source.report_ref.revision')=?",
    "AND json_extract(v.body_json,'$.source.report_ref.body_hash')=? AND json_extract(v.body_json,'$.preparation_profile')=?",
    "AND json_extract(v.body_json,'$.implementation_hash')=? ORDER BY e.updated_at DESC,e.id DESC LIMIT 1"),params=list(report_ref$project_id,report_ref$id,report_ref$revision,report_ref$body_hash,preparation_profile,implementation_ref$hash))
  if(!nrow(rows))return(NULL)
  ref<-list(kind="task_display",id=rows$id[[1L]],revision=rows$revision[[1L]],body_hash=rows$body_hash[[1L]],project_id=report_ref$project_id)
  .brohn_td_metadata(store,ref);ref
}
brohn_task_display_catalog <- function(store,display_ref,cursor=NULL,limit=25L) {
  m<-.brohn_td_metadata(store,display_ref);b<-m$record$body
  brohn_require(brohn_number(limit,1,100,TRUE),"Choose a bounded task catalog page.")
  scope<-brohn_hash(display_ref);offset<-0L
  if(!is.null(cursor)){brohn_fields(cursor,c("scope","offset"),label="Task catalog page");brohn_require(identical(cursor$scope,scope)&&brohn_number(cursor$offset,0,100000,TRUE),"Reopen this exact task catalog page.");offset<-cursor$offset}
  rows<-b$catalog;indices<-seq.int(offset+1L,min(length(rows),offset+limit))
  items<-if(offset>=length(rows))list()else rows[indices]
  list(report_ref=b$source$report_ref,source_family=b$source_family,state="ready",prepared_ref=display_ref,items=items,cursor=cursor,
    next_cursor=if(offset+length(items)<length(rows))list(scope=scope,offset=offset+length(items))else NULL,requires_display_preparation=FALSE,reason=NULL,dependency=NULL)
}
brohn_task_display_choices <- function(store,report_ref,cursor=NULL,limit=25L) {
  m<-.brohn_rpk_report_metadata(store,report_ref);profile<-if("choice" %in% unlist(m$source_components))"saved-task-display/0.2"else .brohn_td_profile
  admission<-.brohn_td_admission(profile);reason<-.brohn_td_unsupported(m,admission)
  if(is.null(reason)){.brohn_rpk_report_proof(store,m,source_admission=admission);ref<-brohn_find_task_display(store,report_ref,profile,brohn_task_display_implementation_ref(profile))
    if(!is.null(ref))return(brohn_task_display_catalog(store,ref,cursor,limit))}
  brohn_require(is.null(cursor),"Task selector pages become available after exact source preparation.")
  state<-if(is.null(reason))"needs_preparation"else"unavailable_source";dependency<-NULL
  if(is.null(reason)){
    request<-.brohn_task_display_request(store,report_ref,brohn_task_display_implementation_ref(profile));job<-.brohn_rpk_latest_job(store,"task_display",request$content_fingerprint)
    if(!is.null(job)){
      state<-switch(job$status,queued="queued",running="preparing",failed="failed",cancelled="cancelled","needs_preparation")
      if(job$status %in% c("queued","running")){
        authorized<-tryCatch({brohn_report_package_job_authorize(store,job);TRUE},error=function(e)FALSE)
        if(!authorized){state<-"needs_authority";reason<-"Sign in and explicitly retry this original preparation."}
      }
      if(job$status=="failed")reason<-if(is.list(job$error))brohn_default(job$error$message,"Task preparation failed.")else brohn_default(job$error,"Task preparation failed.")
      dependency<-list(job_id=job$id,operation="task_display",status=job$status)
    }
  }
  list(report_ref=report_ref,source_family=m$source_family,state=state,prepared_ref=NULL,items=list(),cursor=NULL,next_cursor=NULL,requires_display_preparation=is.null(reason),reason=reason,dependency=dependency)
}
.brohn_td_selector_catalog <- function(store,report_ref,adapter,cursor,limit,prepared_ref=NULL) {
  c<-if(is.null(prepared_ref))brohn_task_display_choices(store,report_ref,cursor,limit)else brohn_task_display_catalog(store,prepared_ref,cursor,limit)
  brohn_require(.brohn_td_same(c$report_ref,report_ref),"The task catalog belongs to another exact report.")
  c$items<-lapply(c$items,function(item)list(selector=if(item$kind=="cohort_metric")list(scope="exact_metrics",metrics=list(item$metric))else list(scope="exact_administrations",keys=list(item$key)),label=item$label,details=item))
  c$adapter<-adapter;c
}
.brohn_rpk_selection_sources <- function(store,selection) {
  s<-selection;admission<-brohn_report_source_admission(s$renderer_profile)
  if(identical(s$schema,"brohn-report-package-selection/0.2")){
    brohn_require(is.null(s$display_refs)&&brohn_array(s$prepared_sources)&&admission!="gaze-explicit-paired-findings/0.1","Prepared report selections need their typed source inventory.")
    get<-function(adapter)lapply(Filter(function(x)identical(x$adapter,adapter),s$prepared_sources),`[[`,"prepared_ref")
    distributions<-get("explicit-distribution");tasks<-get("task-display");choices<-get("choice-display")
    brohn_require(length(distributions)+length(tasks)+length(choices)==length(s$prepared_sources)&&(!length(choices)||admission=="task-choice-findings/0.1"),"Unsupported prepared report source adapter.")
    metadata<-.brohn_rpk_source_metadata(store,s$report_refs,distributions,identical(s$contents_policy$stimulus_images,"included"),tasks,source_admission=admission,choice_refs=choices)
    for(binding in s$prepared_sources){
      candidates<-switch(binding$adapter,"task-display"=metadata$task_displays,"choice-display"=metadata$choice_displays,metadata$distributions)
      item<-Filter(function(x).brohn_td_same(x$ref,binding$prepared_ref),candidates)
      brohn_require(length(item)==1L&&.brohn_td_same(item[[1L]]$report_ref,binding$source_report_ref),"The selected preparation belongs to another exact source report.")
      actual<-if(binding$adapter %in% c("task-display","choice-display")).brohn_td_implementation_ref(item[[1L]]$record$body$implementation)else item[[1L]]$preparation_implementation_ref
      brohn_require(.brohn_td_same(actual,binding$implementation_ref),"The selected preparation differs from its frozen original implementation.")
      expected<-switch(binding$adapter,"task-display"=if(admission=="task-choice-findings/0.1")"saved-task-display/0.2"else"saved-task-display/0.1","choice-display"="saved-choice-display/0.1",if(admission=="task-choice-findings/0.1")"saved-explicit-distribution/0.2"else"saved-explicit-distribution/0.1")
      brohn_require(identical(actual$profile,expected),"This renderer requires the exact compatible preparation version.")
    }
    # A hidden figure never removes a present scientific component.
    for(ref in s$report_refs){m<-Filter(function(x).brohn_td_same(x$ref,ref),metadata$reports)[[1L]]
      for(component in intersect(unlist(m$source_components),c("task","choice"))){adapter<-paste0(component,"-display")
        matches<-Filter(function(x)identical(x$adapter,adapter)&&.brohn_td_same(x$source_report_ref,ref),s$prepared_sources)
        brohn_require(length(matches)==1L,"Every selected task/choice source requires one complete exact preparation, even when its figures are hidden.")}
    }
    return(metadata)
  }
  brohn_require(identical(s$schema,"brohn-report-package-selection/0.1")&&identical(admission,"gaze-explicit-paired-findings/0.1"),"Unsupported saved report selection version.")
  .brohn_rpk_source_metadata(store,s$report_refs,s$display_refs,identical(s$contents_policy$stimulus_images,"included"),source_admission=admission)
}
brohn_release_task_display_resources <- function(handle) {
  if(is.environment(handle)&&inherits(handle,"brohn_task_display_resources")&&is.environment(handle$state)&&!isTRUE(handle$state$closed)){
    state<-handle$state;state$closed<-TRUE;.brohn_rpk_release(handle$source_handle)
  };invisible(NULL)
}
brohn_open_task_display_resources <- function(store,display_ref,project_id) {
  brohn_require(identical(display_ref$project_id,project_id),"Choose the task display's exact project.")
  meta<-.brohn_td_metadata(store,display_ref)
  source<-.brohn_rpk_source_metadata(store,list(meta$report_ref),task_refs=list(display_ref),source_admission=.brohn_td_admission(meta$record$body$preparation_profile))
  handle<-.brohn_rpk_hold_sources(store,source);ok<-FALSE;on.exit(if(!ok).brohn_rpk_release(handle),add=TRUE)
  complete<-.brohn_rpk_complete_sources(store,handle);item<-complete$task_displays[[1L]]
  brohn_require(.brohn_td_same(.brohn_td_metadata(store,display_ref),meta),"Task display authority changed while opening.")
  h<-new.env(parent=emptyenv());class(h)<-"brohn_task_display_resources";h$state<-new.env(parent=emptyenv());h$state$closed<-FALSE
  h$ref<-display_ref;h$metadata<-meta;h$workspace_id<-store$workspace_id;h$source_handle<-handle
  lockEnvironment(h,bindings=TRUE);reg.finalizer(h,brohn_release_task_display_resources,onexit=TRUE);ok<-TRUE
  list(record=meta$record,handle=h,evidence=item$evidence,artifact=c(list(file="task-display.json"),meta$object))
}
brohn_task_display_resources_current <- function(store,handle) {
  brohn_require(is.environment(handle)&&inherits(handle,"brohn_task_display_resources")&&environmentIsLocked(handle)&&!isTRUE(handle$state$closed)&&identical(handle$workspace_id,store$workspace_id),"Reopen this closed or different-workspace task display.")
  brohn_report_package_sources_current(store,handle$source_handle);m<-.brohn_td_metadata(store,handle$ref)
  brohn_require(.brohn_td_same(m,handle$metadata),"Task display or original source authority changed.")
  list(record=m$record,artifact=c(list(file="task-display.json"),m$object))
}
