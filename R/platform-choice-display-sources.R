# Choice source metadata, exact historical authority, and sealed resource handles.
# All cross-file dependencies are called lazily; Shiny's alphabetical loading is safe.
.brohn_cd_unsupported <- function(m) {
 if(is.null(m$choice_source_family))return("This saved report has no complete choice source family.")
 if(length(m$artifacts)&&!identical(m$schema,"brohn-questionnaire-report-preview/1.0"))return("This choice report also contains unsupported scientific artifacts; its original complete export remains available.")
 if(m$choice_source_family=="native_questionnaire"){
  if(!is.null(m$schema)&&!identical(m$schema,"brohn-questionnaire-report-preview/1.0"))return("This native choice analysis schema is unsupported.")
  if(!length(m$native_runs)||length(m$native_runs)!=length(m$run_sources))return("This native choice report lacks complete original protocol/journal receipts. Its existing saved score export remains available.")
  if(!length(m$design$maxdiff)||length(m$design$maxdiff)>20L||!all(vapply(m$design$maxdiff,function(d)identical(d$profile,"object-case-paired-maxdiff/1.0"),logical(1))))return("This saved choice design has no registered complete report adapter.")
 }else if(!is.null(m$schema)||!identical(m$import_schema,"brohn-maxdiff-csv-import/1.0")||is.null(m$import_source)||!brohn_valid_id(m$dataset_id))return("This imported choice source lacks its supported complete mapping/source evidence.")
 NULL
}
.brohn_cd_extra_objects <- function(store,m) {
 result<-list()
 if(identical(m$choice_source_family,"imported_choice")){
  hash<-m$import_source$hash;brohn_require(.brohn_td_sha(hash),"The original imported choice file has no exact retained identity.")
  row<-DBI::dbGetQuery(store$con,"SELECT size,media_type FROM objects WHERE hash=?",params=list(hash))
  brohn_require(nrow(row)==1L,"The original imported choice file is no longer retained.")
  result<-list(.brohn_rpk_object(store,list(hash=hash,bytes=row$size[[1L]],media_type=row$media_type[[1L]]),64*1024^2))
 }
 if(!is.null(m$choice_source_family))for(exercise in m$design$maxdiff)for(item in exercise$items)if(!is.null(item$illustration)){
  brohn_validate_illustration(item$illustration);result<-c(result,list(.brohn_rpk_object(store,item$illustration$asset,5*1024^2)))
 }
 result
}
.brohn_cd_metadata <- function(store,ref) {
 .brohn_rpk_ref_catalog(store,ref,"choice_display")
 row<-DBI::dbGetQuery(store$con,"SELECT length(CAST(body_json AS BLOB)) bytes FROM entity_versions WHERE kind='choice_display' AND id=? AND revision=? AND project_id=?",params=list(ref$id,ref$revision,ref$project_id))
 brohn_require(nrow(row)==1L&&row$bytes[[1L]]<=2*1024^2,"Saved choice metadata exceeds its bounded reader.")
 record<-.brohn_rpk_record(store,ref,"choice_display");b<-record$body
 brohn_fields(b,c("schema","study_id","project_id","source_family","source","preparation_profile","implementation","implementation_hash","input_binding_hash","coverage","catalog","companion_catalog","artifact","artifact_schema","retained_document","producer"),label="Saved choice display metadata")
 .brohn_cd_model_identity(b$implementation)
 brohn_require(identical(b$schema,"brohn-saved-choice-display/0.1")&&identical(b$artifact_schema,"brohn-choice-display-evidence/0.1")&&identical(b$preparation_profile,.brohn_cd_profile)&&identical(b$project_id,ref$project_id)&&b$source_family %in% c("native_questionnaire","imported_choice")&&identical(b$implementation_hash,brohn_hash(b$implementation)),"Saved choice preparation identity is unsupported.")
 source<-.brohn_rpk_report_metadata(store,b$source$report_ref);.brohn_rpk_report_proof(store,source,source_admission="task-choice-findings/0.1")
 brohn_require(identical(b$study_id,source$study_id)&&identical(b$source_family,source$choice_source_family)&&.brohn_td_same(b$source$result_object,.brohn_td_object_ref(source$result_object)),"Saved choice display lost its exact original source identity.")
 object<-.brohn_rpk_object(store,b$artifact,64*1024^2);document<-.brohn_rpk_object(store,b$retained_document,2*1024^2)
 p<-b$producer;brohn_fields(p,c("job_id","attempt","request_hash","worker_result_hash"),label="Choice producer proof");j<-brohn_get_job(store,p$job_id)
 brohn_require(!is.null(j)&&identical(j$operation,"choice_display")&&identical(j$status,"succeeded")&&j$attempt==p$attempt&&identical(j$result$choice_display_id,ref$id)&&identical(j$result$output_hash,document$hash)&&identical(brohn_hash(j$request),p$request_hash)&&identical(j$request$schema,"brohn-choice-display-job/0.1")&&identical(j$request$preparation_profile,.brohn_cd_profile)&&.brohn_td_same(j$request$report_ref,b$source$report_ref)&&.brohn_td_same(j$request$implementation,b$implementation),"Saved choice display differs from its original successful producer proof.")
 list(ref=ref,record=record,report_ref=b$source$report_ref,object=object,document=document)
}
brohn_find_choice_display <- function(store,report_ref,preparation_profile=.brohn_cd_profile,implementation_ref=brohn_choice_display_implementation_ref()) {
 .brohn_rpk_ref_catalog(store,report_ref,"report")
 brohn_require(identical(preparation_profile,.brohn_cd_profile)&&identical(implementation_ref$profile,preparation_profile)&&.brohn_td_sha(implementation_ref$hash),"Choose an exact choice preparation identity.")
 rows<-DBI::dbGetQuery(store$con,paste("SELECT v.id,v.revision,v.body_hash FROM entities e JOIN entity_versions v ON e.kind=v.kind AND e.id=v.id AND e.revision=v.revision",
  "WHERE e.kind='choice_display' AND e.project_id=? AND json_extract(v.body_json,'$.source.report_ref.id')=? AND json_extract(v.body_json,'$.source.report_ref.revision')=?",
  "AND json_extract(v.body_json,'$.source.report_ref.body_hash')=? AND json_extract(v.body_json,'$.preparation_profile')=? AND json_extract(v.body_json,'$.implementation_hash')=? ORDER BY e.updated_at DESC,e.id DESC LIMIT 1"),params=list(report_ref$project_id,report_ref$id,report_ref$revision,report_ref$body_hash,preparation_profile,implementation_ref$hash))
 if(!nrow(rows))return(NULL)
 ref<-list(kind="choice_display",id=rows$id[[1L]],revision=rows$revision[[1L]],body_hash=rows$body_hash[[1L]],project_id=report_ref$project_id);.brohn_cd_metadata(store,ref);ref
}
brohn_choice_display_catalog <- function(store,display_ref,cursor=NULL,limit=25L) {
 meta<-.brohn_cd_metadata(store,display_ref);b<-meta$record$body
 brohn_require(brohn_number(limit,1,100,TRUE),"Choose a bounded choice catalog page.")
 scope<-brohn_hash(display_ref);offset<-0L
 if(!is.null(cursor)){brohn_fields(cursor,c("scope","offset"),label="Choice catalog page");brohn_require(identical(cursor$scope,scope)&&brohn_number(cursor$offset,0,100000,TRUE),"Reopen this exact choice catalog page.");offset<-cursor$offset}
 items<-if(offset>=length(b$catalog))list()else b$catalog[seq.int(offset+1L,min(length(b$catalog),offset+limit))]
 list(report_ref=b$source$report_ref,source_family=b$source_family,state="ready",prepared_ref=display_ref,items=items,cursor=cursor,next_cursor=if(offset+length(items)<length(b$catalog))list(scope=scope,offset=offset+length(items))else NULL,requires_display_preparation=FALSE,reason=NULL,dependency=NULL)
}
.brohn_cd_choices <- function(store,report_ref,cursor=NULL,limit=25L) {
 m<-.brohn_rpk_report_metadata(store,report_ref);reason<-.brohn_rpk_unsupported(m,source_admission="task-choice-findings/0.1")
 if(is.null(reason)){.brohn_rpk_report_proof(store,m,source_admission="task-choice-findings/0.1");ref<-brohn_find_choice_display(store,report_ref)
  if(!is.null(ref))return(brohn_choice_display_catalog(store,ref,cursor,limit))}
 brohn_require(is.null(cursor)&&brohn_number(limit,1,100,TRUE),"Choice selector pages become available after exact preparation.")
 state<-if(is.null(reason))"needs_preparation"else"unavailable_source";dependency<-NULL
 if(is.null(reason)){
  request<-.brohn_choice_display_request(store,report_ref,NULL);j<-.brohn_rpk_latest_job(store,"choice_display",request$content_fingerprint)
  if(!is.null(j)){state<-switch(j$status,queued="queued",running="preparing",failed="failed",cancelled="cancelled","needs_preparation")
   if(j$status %in% c("queued","running")&&!tryCatch({brohn_report_package_job_authorize(store,j);TRUE},error=function(e)FALSE)){state<-"needs_authority";reason<-"Sign in and explicitly retry this original preparation."}
   if(j$status=="failed")reason<-if(is.list(j$error))brohn_default(j$error$message,"Choice preparation failed.")else brohn_default(j$error,"Choice preparation failed.")
   dependency<-list(job_id=j$id,operation="choice_display",status=j$status)
  }
 }
 list(report_ref=report_ref,source_family=m$choice_source_family,state=state,prepared_ref=NULL,items=list(),cursor=NULL,next_cursor=NULL,requires_display_preparation=is.null(reason),reason=reason,dependency=dependency)
}
.brohn_cd_selector_catalog <- function(store,report_ref,adapter,cursor,limit,prepared_ref=NULL) {
 brohn_require(adapter %in% c("choice-counts","choice-utilities"),"Choose a registered choice figure family.")
 c<-if(is.null(prepared_ref)).brohn_cd_choices(store,report_ref,cursor,limit)else brohn_choice_display_catalog(store,prepared_ref,cursor,limit)
 brohn_require(.brohn_td_same(c$report_ref,report_ref),"The choice catalog belongs to another exact report.")
 c$items<-lapply(c$items,function(item)list(selector=list(scope="exact_exercises",keys=list(item$key)),label=item$title,details=item));c$adapter<-adapter;c
}
brohn_release_choice_display_sources <- function(handle).brohn_rpk_release(handle)
brohn_choice_display_sources_current <- function(store,handle)brohn_report_package_sources_current(store,handle)
brohn_release_choice_display_resources <- function(handle) {
 if(is.environment(handle)&&inherits(handle,"brohn_choice_display_resources")&&is.environment(handle$state)&&!isTRUE(handle$state$closed)){state<-handle$state;state$closed<-TRUE;.brohn_rpk_release(handle$source_handle)};invisible(NULL)
}
brohn_open_choice_display_resources <- function(store,ref,project_id) {
 brohn_require(identical(ref$project_id,project_id),"Choose this choice display's exact project.")
 meta<-.brohn_cd_metadata(store,ref);m<-.brohn_rpk_source_metadata(store,list(meta$report_ref),source_admission="task-choice-findings/0.1",choice_refs=list(ref))
 handle<-.brohn_rpk_hold_sources(store,m);ok<-FALSE;on.exit(if(!ok).brohn_rpk_release(handle),add=TRUE)
 full<-.brohn_rpk_complete_sources(store,handle)$choice_displays[[1L]]
 brohn_require(.brohn_td_same(.brohn_cd_metadata(store,ref),meta),"Choice authority changed while opening its complete evidence.")
 h<-new.env(parent=emptyenv());class(h)<-"brohn_choice_display_resources";h$state<-new.env(parent=emptyenv());h$state$closed<-FALSE
 h$ref<-ref;h$metadata<-meta;h$source_handle<-handle;h$workspace_id<-store$workspace_id
 lockEnvironment(h,bindings=TRUE);reg.finalizer(h,brohn_release_choice_display_resources,onexit=TRUE);ok<-TRUE
 list(record=meta$record,handle=h,evidence=full$evidence,artifact=c(list(file="choice-display.json"),meta$object))
}
brohn_choice_display_resources_current <- function(store,handle) {
 brohn_require(is.environment(handle)&&inherits(handle,"brohn_choice_display_resources")&&environmentIsLocked(handle)&&!isTRUE(handle$state$closed)&&identical(handle$workspace_id,store$workspace_id),"Reopen this closed or different-workspace choice display.")
 brohn_report_package_sources_current(store,handle$source_handle);m<-.brohn_cd_metadata(store,handle$ref)
 brohn_require(.brohn_td_same(m,handle$metadata),"Choice display or current original-source authority changed.")
 list(record=m$record,artifact=c(list(file="choice-display.json"),m$object))
}
