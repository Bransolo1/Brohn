# Operation-private optimistic preparation. No source proof or skip option is
# accepted by a public API. The read snapshot ends before the mutation batch.
.brohn_rptx_stale <- function() stop(structure(list(message="Preparation changed while its saved sources were being checked.",call=NULL),
  class=c("brohn_report_preflight_stale","error","condition")))
.brohn_rptx_snapshot <- function(store,fn) {
  .brohn_store_ready(store)
  brohn_require(!RSQLite::sqliteIsTransacting(store$con),"Start report preparation outside another saving operation.")
  previous<-DBI::dbGetQuery(store$con,"PRAGMA query_only")[[1L]][[1L]]
  begun<-FALSE;primary<-NULL;result<-NULL;cleanup_error<-NULL;cleaned<-FALSE
  cleanup<-function(){
    if(cleaned)return(invisible(NULL))
    if(begun)tryCatch(.brohn_store_transaction_statement(store,"ROLLBACK"),error=function(e)cleanup_error<<-e)
    tryCatch(DBI::dbExecute(store$con,if(previous==1L)"PRAGMA query_only=ON"else"PRAGMA query_only=OFF"),
      error=function(e){if(is.null(cleanup_error))cleanup_error<<-e})
    cleaned<<-TRUE;invisible(NULL)
  }
  # on.exit also covers interrupts, which are not ordinary error conditions.
  on.exit(cleanup(),add=TRUE)
  # Enforce the read boundary, rather than relying on helpers to avoid writes.
  # Restore the caller's exact connection setting even on failed BEGIN or read.
  result<-tryCatch({
    DBI::dbExecute(store$con,"PRAGMA query_only=ON")
    .brohn_store_transaction_statement(store,"BEGIN");begun<-TRUE
    withVisible(fn())
  },error=function(e){primary<<-e;NULL})
  cleanup()
  if(!is.null(primary))stop(primary)
  if(!is.null(cleanup_error))stop(cleanup_error)
  if(isTRUE(result$visible))result$value else invisible(result$value)
}
.brohn_rptx_equal <- function(a,b) identical(a,b,num.eq=FALSE,attrib.as.set=FALSE)
.brohn_rptx_rows_equal <- function(a,b) {
  if(!identical(attributes(a),attributes(b))||!identical(names(a),names(b)))return(FALSE)
  all(vapply(names(a),function(n){
    if(!is.character(a[[n]])||!is.character(b[[n]]))return(.brohn_rptx_equal(a[[n]],b[[n]]))
    if(!identical(is.na(a[[n]]),is.na(b[[n]])))return(FALSE)
    all(vapply(which(!is.na(a[[n]])),function(i)identical(charToRaw(a[[n]][[i]]),charToRaw(b[[n]][[i]])),logical(1)))
  },logical(1)))
}
.brohn_rptx_scope <- function(store) {
  parent<-environment(.brohn_rptx_scope);scope<-new.env(parent=parent)
  source<-prepared<-list()
  memo<-function(name,collection) {
    original<-get(name,envir=parent,inherits=TRUE);force(collection)
    function(current,ref) {
      brohn_require(identical(current$con,store$con)&&identical(current$workspace_id,store$workspace_id),"The preparation snapshot belongs to another store.")
      key<-paste(ref$kind,ref$id,ref$revision,ref$body_hash,ref$project_id,sep="/")
      values<-if(collection=="source")source else prepared
      if(!is.null(values[[key]]))return(values[[key]])
      # All calls occur within one read snapshot; commit refreshes authority and
      # the exact raw source rows, rather than trusting this in-memory value.
      f<-original;environment(f)<-scope;value<-f(current,ref)
      if(collection=="source")source[[key]]<<-value else prepared[[key]]<<-value
      value
    }
  }
  assign("brohn_cardiac_source_metadata",memo("brohn_cardiac_source_metadata","source"),scope)
  assign("brohn_cardiac_display_metadata",memo("brohn_cardiac_display_metadata","prepared"),scope)
  allowed<-c(".brohn_rpcc_requirement_sources",".brohn_rpcc_requirements",".brohn_rpcc_requirements_current",
    ".brohn_rpcc_dependency_specs",".brohn_rpk_task_dependency_specs","brohn_find_cardiac_display",
    ".brohn_cdd_queue_request",".brohn_rpcc_resolve_sections",".brohn_rpk_resolve_sections",
    ".brohn_rpcc_selection_sources",".brohn_rpk_selection_sources")
  for(n in allowed){f<-get(n,envir=parent,inherits=TRUE);environment(f)<-scope;assign(n,f,scope)}
  lockEnvironment(scope,bindings=TRUE)
  list(call=function(name,...)get(name,envir=scope,inherits=TRUE)(...),
    values=function()c(unname(source),unname(prepared)),
    objects=function()unlist(lapply(c(source,prepared),function(m)m$objects),recursive=FALSE))
}
# Capture only data reached by the existing validators. SQL rows remain raw:
# equality at commit does not parse, hash or re-traverse scientific documents.
.brohn_rptx_capture <- function(store,values,objects,study_id,project_id,extra_refs=list(),delivery_sources=list()) {
  refs<-heads<-job_ids<-runs<-datasets<-list()
  add_ref<-function(ref) {
    fields<-c("kind","id","revision","body_hash","project_id")
    if(!is.list(ref)||!all(fields %in% names(ref)))return(invisible(NULL))
    ref<-ref[fields];.brohn_rpk_ref_valid(ref)
    refs[[paste(ref$kind,ref$id,ref$revision,sep="/")]]<<-ref
    invisible(NULL)
  }
  walk<-function(x) {
    if(!is.list(x))return(invisible(NULL))
    if(all(c("kind","id","revision","body_hash","project_id") %in% names(x)))add_ref(x)
    if(brohn_text(x$job_id,256))job_ids[[x$job_id]]<<-x$job_id
    if(brohn_text(x$id,256)&&brohn_text(x$operation,128)&&!is.null(x$status))job_ids[[x$id]]<<-x$id
    if(is.list(x$ref)&&identical(x$ref$kind,"dataset")&&!is.null(x$lineage))datasets[[paste(x$ref$id,x$ref$revision)]]<<-x
    if(brohn_text(x$dataset_id,256))heads[[paste("dataset",x$dataset_id)]]<<-list(kind="dataset",id=x$dataset_id)
    for(v in x)if(is.list(v))walk(v)
    invisible(NULL)
  }
  walk(values);for(ref in extra_refs)add_ref(ref)
  # Only the existing complete legacy report validator admits participant
  # delivery provenance. Nested scientific run_id values (for example cardiac
  # exclusion fragments) do not name delivery administrations.
  for(m in delivery_sources)for(run in m[["run_sources",exact=TRUE]]) {
    id<-run[["run_id",exact=TRUE]]
    brohn_require(brohn_text(id,256),"An admitted delivery source has no exact run identity.")
    runs[[id]]<-id
  }
  heads[[paste("study",study_id)]]<-list(kind="study",id=study_id)
  rows<-list()
  capture<-function(sql,params) {
    rows[[length(rows)+1L]]<<-list(sql=sql,params=params,value=DBI::dbGetQuery(store$con,sql,params=params))
    invisible(NULL)
  }
  for(ref in refs){
    .brohn_rpk_ref_catalog(store,ref)
    capture("SELECT * FROM entity_versions WHERE kind=? AND id=? AND revision=?",list(ref$kind,ref$id,ref$revision))
    heads[[paste(ref$kind,ref$id)]]<-list(kind=ref$kind,id=ref$id)
  }
  for(h in heads)capture(paste("SELECT e.*,v.body_json,v.body_hash FROM entities e JOIN entity_versions v",
    "ON v.kind=e.kind AND v.id=e.id AND v.revision=e.revision WHERE e.kind=? AND e.id=?"),list(h$kind,h$id))
  for(id in job_ids)capture("SELECT * FROM jobs WHERE id=?",list(id))
  for(id in runs)capture(paste("SELECT r.*,d.project_id AS owner_project_id FROM delivery_runs r",
    "JOIN delivery_deployments d ON d.id=r.deployment_id WHERE r.id=?"),list(id))
  for(d in datasets){
    p<-d$lineage
    if(!is.null(p$ingestion_id))capture(paste("SELECT id,revision,body_hash FROM entity_versions WHERE kind='ingestion' AND id=? AND project_id=?",
      "AND json_extract(body_json,'$.status')='ready' AND json_extract(body_json,'$.dataset_id')=? AND json_extract(body_json,'$.source_object.hash')=? AND json_extract(body_json,'$.review_hash')=? ORDER BY revision"),
      list(p$ingestion_id,d$ref$project_id,d$ref$id,d$source$hash,p$review_hash))
    if(!is.null(p$parent_acquisition))capture(paste("SELECT id FROM jobs WHERE operation='acquisition_prepare' AND status='succeeded'",
      "AND json_extract(result_json,'$.dataset_id')=? AND json_extract(result_json,'$.acquisition_id')=? ORDER BY id"),list(d$ref$id,p$parent_acquisition$id))
  }
  unique_objects<-list()
  for(o in objects){
    old<-unique_objects[[o$hash]]
    brohn_require(is.null(old)||.brohn_rpk_same(old,o),"A preparation object has conflicting exact descriptors.")
    unique_objects[[o$hash]]<-o
  }
  for(o in unique_objects)capture("SELECT * FROM objects WHERE hash=?",list(o$hash))
  workspace<-store$workspace_id;connection<-store$con;root<-store$root
  # Return a closure solely to the operation that created it. No caller-supplied
  # metadata or opaque token can authorize a public queue operation.
  function(current) {
    brohn_require(identical(current$con,connection)&&identical(current$workspace_id,workspace)&&identical(current$root,root),"The preparation proof belongs to another workspace.")
    brohn_report_package_queue_authority(current,"report_package",project_id)
    for(ref in refs).brohn_rpk_ref_catalog(current,ref)
    for(row in rows)if(!.brohn_rptx_rows_equal(DBI::dbGetQuery(current$con,row$sql,params=row$params),row$value)).brohn_rptx_stale()
    for(o in unique_objects){
      path<-brohn_object_path(current,o$hash,FALSE)
      brohn_require(identical(path,o$path)&&identical(as.numeric(file.info(path)$size),as.numeric(o$bytes)),"A saved preparation source file changed before admission.")
    }
    invisible(TRUE)
  }
}
.brohn_rptx_job_state <- function(job) {
  if(is.null(job))return(NULL)
  job[c("id","operation","request","status","attempt","result","error")]
}
.brohn_rptx_pending_current <- function(store,old) {
  now<-brohn_get_job(store,old$id)
  if(is.null(now)||!now$status %in% c("queued","running")||
    !.brohn_rptx_equal(now[c("id","operation","request")],old[c("id","operation","request")])).brohn_rptx_stale()
  now
}
.brohn_rptx_enqueue <- function(store,kind,request,retry) {
  request$authority<-brohn_report_package_queue_authority(store,kind,request$project_id)
  previous<-.brohn_rpk_latest_job(store,kind,request$content_fingerprint)
  if(!is.null(previous)&&(!isTRUE(retry)||previous$status %in% c("queued","running","succeeded")))return(previous)
  prefix<-switch(kind,cardiac_display="cardiac-display:",task_display="task-display:",choice_display="choice-display:",eda_display="eda-display:",explicit_distributions="report-distribution:")
  brohn_require(!is.null(prefix),"Unsupported private preparation queue.")
  brohn_enqueue_job(store,kind,request,paste0(prefix,request$content_fingerprint,if(isTRUE(retry))paste0(":",brohn_id("retry"))else""))
}
.brohn_rptx_package_request <- function(selection_ref,selection) {
  request<-list(schema="brohn-report-package-job/0.1",project_id=selection_ref$project_id,selection_ref=selection_ref,
    implementation=.brohn_rpk_implementation(),limits=.brohn_rpk_limits(selection))
  request$content_fingerprint<-brohn_hash(request);request
}
.brohn_rptx_package_enqueue <- function(store,request,retry) {
  request$authority<-brohn_report_package_queue_authority(store,"report_package",request$project_id)
  brohn_enqueue_job(store,"report_package",request,paste0("report-package:",request$content_fingerprint,if(isTRUE(retry))paste0(":",brohn_id("retry"))else""))
}
.brohn_rptx_virtual <- function(record,body) {
  if(.brohn_rpk_same(record$body,body))return(record)
  record$body<-body;record$revision<-record$revision+1L;record
}
.brohn_rptx_selection <- function(record,body,resolved) {
  id<-brohn_id("report-selection");q<-body$request
  selection<-c(list(schema="brohn-report-package-selection/0.2",id=id,intent_ref=.brohn_rpk_ref(record),generation=body$generation),
    q[c("study_id","project_id","title","report_refs")],list(prepared_sources=.brohn_rpk_prepared_sources(body$dependencies),sections=resolved$sections),
    q[c("contents_policy","limits_profile","renderer_profile")],list(frozen_at=brohn_now(),coverage=list(
      full_platform_scope=list(capabilities=50L,packages=17L),profile_supported_adapters=list(),
      numerical_evidence="complete_selected_reports",raw_recordings="excluded_by_profile",original_raw_bytes_reverified=FALSE)))
  .brohn_rpcc_freeze(selection,q,body$source_requirements)
}
.brohn_rptx_prospective_evidence <- function(metadata,selection) {
  # Only the new-package callsite supplies this locally constructed selection.
  # Its intent ref names prospective output; every other nested ref is evidence.
  brohn_require(is.list(metadata)&&is.list(selection)&&
    is.list(metadata[["selection",exact=TRUE]])&&
    .brohn_rptx_equal(metadata[["selection",exact=TRUE]],selection),
    "The prospective selection differs from its exact admitted source metadata.")
  .brohn_rpk_ref_valid(selection[["intent_ref",exact=TRUE]],"report_package_intent")
  evidence<-metadata
  evidence[["selection"]][["intent_ref"]]<-NULL
  evidence
}
.brohn_rptx_legacy_metadata <- function(store,request,requirements) {
  refs<-requirements$noncardiac_report_refs
  if(!length(refs))return(NULL)
  .brohn_rpk_source_metadata(store,refs,source_admission=.brohn_rpk_profile_spec(request$renderer_profile)$legacy_admission)
}
.brohn_rptx_save <- function(store,command_id,request,fingerprint,id,prior_intent_ref=NULL) {
  plan<-.brohn_rptx_snapshot(store,function(){
    old<-brohn_get_entity(store,"report_package_intent",id)
    if(!is.null(old))return(list(existing=TRUE))
    scope<-.brohn_rptx_scope(store);generation<-1L;prior<-NULL
    if(!is.null(prior_intent_ref)){prior<-.brohn_rpk_intent(store,prior_intent_ref);generation<-prior$body$generation+1L}
    requirements<-scope$call(".brohn_rpcc_requirements",store,request)
    legacy<-.brohn_rptx_legacy_metadata(store,request,requirements)
    body<-list(schema=.brohn_rpk_intent_schema,id=id,generation=generation,status="prepared",request=request,
      command_id=command_id,command_fingerprint=fingerprint,prior_intent_ref=prior_intent_ref,dependencies=list(),
      selection_ref=NULL,job_ref=NULL,package_ref=NULL,reason=NULL,superseded_by=NULL,created_at=brohn_now(),
      source_requirements=requirements,execution_plan=.brohn_rpk_execution_plan(request),preparation=NULL)
    fence<-.brohn_rptx_capture(store,c(scope$values(),list(legacy)),c(scope$objects(),legacy$objects),request$study_id,request$project_id,
      if(is.null(prior))list()else list(prior_intent_ref),delivery_sources=legacy$reports)
    list(existing=FALSE,body=body,prior=prior,fence=fence)
  })
  brohn_store_batch(store,function(){
    brohn_report_package_queue_authority(store,"report_package",request$project_id)
    old<-brohn_get_entity(store,"report_package_intent",id)
    if(!is.null(old)){
      brohn_require(identical(old$project_id,request$project_id)&&identical(old$body$command_fingerprint,fingerprint),"This preparation command already belongs to different contents.")
      return(.brohn_rpk_intent_view(old))
    }
    if(isTRUE(plan$existing)).brohn_rptx_stale()
    plan$fence(store)
    prior<-plan$prior
    if(!is.null(prior)){
      # The fence compared its exact head and raw version. This ordinary check
      # retains the current intent schema/status and project contract as well.
      current<-.brohn_rpk_intent(store,prior_intent_ref)
      if(current$body$status %in% .brohn_rpk_active_states){b<-current$body;b$status<-"superseded";b$reason<-"A new preparation preserves your edited contents.";b$superseded_by<-id
        brohn_put_entity(store,current$kind,current$id,b,current$revision,current$project_id)}
    }
    .brohn_rpk_intent_view(brohn_put_entity(store,"report_package_intent",id,plan$body,0L,request$project_id))
  })
}
.brohn_rptx_prepare <- function(store,intent_ref,action) {
  scope<-.brohn_rptx_scope(store)
  r<-.brohn_rpk_intent(store,intent_ref);b<-r$body;q<-b$request
  if(action=="advance")brohn_require(b$status %in% c("prepared","waiting_for_display","ready_to_freeze"),"This preparation needs an explicit Resume or Retry.")
  if(action=="resume")brohn_require(b$status=="needs_authority","Only an authorization pause can be resumed.")
  if(action=="retry")brohn_require(b$status %in% c("failed","cancelled","needs_attention"),"Only a stopped preparation can be retried.")
  .brohn_rpk_request(store,q);.brohn_rpk_plan_valid(b$execution_plan,q)
  scope$call(".brohn_rpcc_requirements_current",store,b)
  legacy<-.brohn_rptx_legacy_metadata(store,q,b$source_requirements)
  values<-list(legacy);objects<-legacy$objects;entries<-list()
  seal<-function(mode,body=b,selection=NULL,package=NULL,retry=FALSE,ready=NULL) {
    list(mode=mode,record=r,body=body,entries=entries,selection=selection,package=package,retry=retry,ready=ready,
      fence=.brohn_rptx_capture(store,c(scope$values(),values),c(scope$objects(),objects),q$study_id,q$project_id,
        c(list(intent_ref),if(is.null(b$selection_ref))list()else list(b$selection_ref)),delivery_sources=legacy$reports))
  }
  if(!.brohn_rpk_same(b$execution_plan$renderer_implementation_ref,.brohn_rpk_renderer_implementation_ref())){
    b$status<-"needs_attention";b$reason<-"The report implementation changed since Prepare. Review your saved choices and prepare them as a new version; the original plan was preserved."
    b$preparation<-.brohn_rpk_preparation_view(b$dependencies,reason="implementation_changed")
    return(seal("update",b))
  }
  retrying<-action!="advance"
  if(retrying&&!is.null(b$selection_ref)){
    frozen<-.brohn_rpk_record(store,b$selection_ref,"report_package_selection")
    brohn_require(identical(frozen$body$intent_ref$id,r$id)&&frozen$body$generation==b$generation,"The retry no longer belongs to its original frozen contents.")
    metadata<-scope$call(".brohn_rpk_selection_sources",store,frozen$body)
    values<-c(values,list(metadata));objects<-c(objects,metadata$objects)
    b$status<-"ready_to_freeze";b$reason<-NULL;b$job_ref<-NULL;b$package_ref<-NULL
    return(seal("retry_package",b,package=.brohn_rptx_package_request(b$selection_ref,frozen$body),retry=TRUE))
  }
  deps<-list();waiting<-FALSE;admission<-.brohn_rpk_distribution_admission_for(q)
  for(spec in scope$call(".brohn_rpk_task_dependency_specs",store,q,b$execution_plan,b$source_requirements)){
    kind<-spec$kind;ref<-spec$report_ref;impl<-spec$implementation_ref
    old<-Filter(function(d)identical(d$slot,spec$slot),b$dependencies);old<-if(length(old))old[[1L]]else NULL
    if(kind=="cardiac_display"){
      pending<-.brohn_rpcc_pending_dependency(store,spec,old)
      if(!is.null(pending)){
        entries<-c(entries,list(list(type="pending",dependency=pending,job=brohn_get_job(store,pending$job_id))))
        deps<-c(deps,list(pending));waiting<-TRUE;next
      }
    }
    saved<-switch(kind,cardiac_display=scope$call("brohn_find_cardiac_display",store,ref,spec$display_request,impl),
      task_display=brohn_find_task_display(store,ref,impl$profile,impl),choice_display=brohn_find_choice_display(store,ref,impl$profile,impl),
      eda_display=brohn_find_eda_display(store,ref,spec$display_request,impl$profile,impl),
      explicit_distributions=.brohn_rpk_find_pinned_distribution(store,ref,impl,admission))
    d<-c(spec,list(job_id=if(is.null(old))NULL else old$job_id,created_for_intent=if(is.null(old))FALSE else old$created_for_intent,
      result_ref=saved,status=if(is.null(saved))NULL else"succeeded"))
    if(!is.null(saved)){
      metadata<-switch(kind,cardiac_display=scope$call("brohn_cardiac_display_metadata",store,saved),
        task_display=.brohn_td_metadata(store,saved),choice_display=.brohn_cd_metadata(store,saved),
        eda_display=.brohn_edd_metadata(store,saved),explicit_distributions=.brohn_rpk_distribution_metadata(store,saved))
      values<-c(values,list(metadata));objects<-c(objects,metadata$objects,Filter(Negate(is.null),list(metadata[["object",exact=TRUE]],metadata[["document",exact=TRUE]])))
      entries<-c(entries,list(list(type="saved",dependency=d)));deps<-c(deps,list(d));next
    }
    current<-switch(kind,cardiac_display=brohn_cardiac_display_implementation_ref(),task_display=brohn_task_display_implementation_ref(impl$profile),
      choice_display=brohn_choice_display_implementation_ref(),eda_display=brohn_eda_display_implementation_ref(impl$profile),explicit_distributions=.brohn_rpk_distribution_implementation_ref(admission))
    if(!.brohn_rpk_same(impl,current)){
      b$status<-"needs_attention";b$dependencies<-.brohn_rpk_retain_dependencies(deps,b$dependencies)
      b$reason<-"A pinned display implementation is unavailable. Prepare these saved choices as a new version; no different code was substituted."
      b$preparation<-.brohn_rpk_preparation_view(b$dependencies,reason="implementation_changed")
      return(seal("update",b))
    }
    request<-switch(kind,cardiac_display=scope$call(".brohn_cdd_queue_request",store,ref,spec$display_request,impl),
      task_display=.brohn_task_display_request(store,ref,impl),choice_display=.brohn_choice_display_request(store,ref,impl),
      eda_display=.brohn_eda_display_request(store,ref,spec$display_request,impl,impl$profile),explicit_distributions=.brohn_rpk_distribution_request(store,ref,impl,admission))
    if(kind=="explicit_distributions")request$content_fingerprint<-brohn_hash(request[setdiff(names(request),"authority")])
    values<-c(values,list(request$original_closure))
    previous<-.brohn_rpk_latest_job(store,kind,request$content_fingerprint)
    retry<-retrying||(is.null(old)&&!is.null(previous)&&identical(previous$status,"cancelled"))
    entries<-c(entries,list(list(type="queue",dependency=d,request=request,previous=previous,old=old,retry=retry)))
    # A stopped attached dependency retains its original explicit Retry rule.
    # Commit observes its fresh state before persisting the stopped intent.
    if(!is.null(previous)&&!retry&&previous$status %in% c("failed","cancelled"))return(seal("dependencies"))
    waiting<-TRUE
  }
  if(waiting)return(seal("dependencies"))
  b$dependencies<-deps;b$reason<-NULL;b$preparation<-.brohn_rpk_preparation_view(deps)
  resolved<-tryCatch(scope$call(".brohn_rpk_resolve_sections",store,q,deps),error=function(e)e)
  if(inherits(resolved,"error")){
    b$status<-"needs_attention";b$reason<-substr(conditionMessage(resolved),1L,2000L)
    b$preparation<-.brohn_rpk_preparation_view(deps,reason="selection_review");return(seal("update",b))
  }
  maximum<-.brohn_rpk_limits(q)$max_panels
  b$preparation<-.brohn_rpk_preparation_view(deps,resolved$panel_count,maximum)
  if(!is.null(resolved$panel_count)&&resolved$panel_count>maximum){
    b$status<-"needs_attention";b$reason<-paste("These choices contain",resolved$panel_count,"figures; this profile supports",maximum,". Change the figure choices; all complete numerical evidence stays included.")
    b$preparation$reason_code<-"panel_limit";return(seal("update",b))
  }
  if(retrying)b$generation<-b$generation+1L
  b$status<-"ready_to_freeze";b$job_ref<-NULL;b$package_ref<-NULL;b$selection_ref<-NULL
  ready<-.brohn_rptx_virtual(r,b);selection<-.brohn_rptx_selection(ready,b,resolved)
  metadata<-scope$call(".brohn_rpk_selection_sources",store,selection)
  values<-c(values,list(.brohn_rptx_prospective_evidence(metadata,selection)));objects<-c(objects,metadata$objects)
  selection_ref<-list(kind="report_package_selection",id=selection$id,revision=1L,body_hash=brohn_hash(selection),project_id=r$project_id)
  seal("package",b,selection,.brohn_rptx_package_request(selection_ref,selection),ready=ready)
}
.brohn_rptx_commit <- function(store,plan) {
  plan$fence(store);r<-plan$record;b<-plan$body
  # Check every live dependency before the first write, so a normal worker
  # completion never leaves a partly changed intent or an extra queue entry.
  live<-lapply(plan$entries,function(entry){
    if(entry$type %in% c("pending","queue"))
      brohn_report_package_queue_authority(store,entry$dependency$kind,entry$dependency$report_ref$project_id)
    if(entry$type=="pending")return(.brohn_rptx_pending_current(store,entry$job))
    if(entry$type!="queue")return(NULL)
    now<-.brohn_rpk_latest_job(store,entry$dependency$kind,entry$request$content_fingerprint);old<-entry$previous
    if(is.null(old)){
      if(!is.null(now)&&!now$status %in% c("queued","running")).brohn_rptx_stale()
    }else if(old$status %in% c("queued","running")){
      if(is.null(now)||!identical(now$id,old$id)||!now$status %in% c("queued","running")||
        !.brohn_rptx_equal(now$request,old$request)).brohn_rptx_stale()
    }else if(!.brohn_rptx_equal(.brohn_rptx_job_state(now),.brohn_rptx_job_state(old))).brohn_rptx_stale()
    now
  })
  if(plan$mode=="update")return(.brohn_rpk_intent_view(.brohn_rpk_put_intent(store,r,b)))
  if(plan$mode=="dependencies"){
    deps<-list()
    for(i in seq_along(plan$entries)){
      entry<-plan$entries[[i]];d<-entry$dependency
      if(entry$type=="pending")d$status<-live[[i]]$status
      if(entry$type=="queue"){
        j<-.brohn_rptx_enqueue(store,d$kind,entry$request,entry$retry);previous<-live[[i]];old<-entry$old
        d$job_id<-j$id;d$status<-j$status
        d$created_for_intent<-if(!is.null(old)&&identical(old$job_id,j$id))isTRUE(old$created_for_intent)else is.null(previous)||!identical(previous$id,j$id)
        if(j$status %in% c("failed","cancelled")){
          b$status<-j$status;b$dependencies<-.brohn_rpk_retain_dependencies(c(deps,list(d)),b$dependencies)
          b$reason<-.brohn_rpk_job_error(j,"Saved display preparation stopped. Review the source and explicitly retry.")
          b$preparation<-.brohn_rpk_preparation_view(b$dependencies)
          return(.brohn_rpk_intent_view(.brohn_rpk_put_intent(store,r,b)))
        }
        brohn_require(j$status %in% c("queued","running"),"A successful display job has no retained complete result.")
      }
      deps<-c(deps,list(d))
    }
    b$dependencies<-deps;b$reason<-NULL;b$preparation<-.brohn_rpk_preparation_view(deps);b$status<-"waiting_for_display"
    return(.brohn_rpk_intent_view(.brohn_rpk_put_intent(store,r,b)))
  }
  r<-.brohn_rpk_put_intent(store,r,b)
  if(plan$mode=="package"){
    brohn_require(.brohn_rpk_same(.brohn_rpk_ref(r),.brohn_rpk_ref(plan$ready)),"The ready preparation differs from its exact admitted selection.")
    s<-plan$selection;saved<-brohn_put_entity(store,"report_package_selection",s$id,s,0L,r$project_id)
    b<-r$body;b$selection_ref<-.brohn_rpk_ref(saved)
    brohn_require(.brohn_rpk_same(b$selection_ref,plan$package$selection_ref),"The saved selection differs from its preflighted package request.")
    r<-.brohn_rpk_put_intent(store,r,b)
  }
  job<-.brohn_rptx_package_enqueue(store,plan$package,plan$retry)
  b<-r$body;b$status<-"assembly_queued";b$job_ref<-list(id=job$id,status=job$status)
  .brohn_rpk_intent_view(.brohn_rpk_put_intent(store,r,b))
}
.brohn_rptx_continue <- function(store,intent_ref,action) {
  brohn_require(!RSQLite::sqliteIsTransacting(store$con),"Start report preparation outside another saving operation.")
  original<-.brohn_rpk_intent(store,intent_ref)
  if(original$body$status %in% c("succeeded","superseded","assembly_queued"))
    return(brohn_store_batch(store,function().brohn_rpk_intent_view(.brohn_rpk_reconcile(store,.brohn_rpk_intent(store,intent_ref)))))
  plan<-.brohn_rptx_snapshot(store,function().brohn_rptx_prepare(store,intent_ref,action))
  tryCatch(brohn_store_batch(store,function().brohn_rptx_commit(store,plan)),
    brohn_report_preflight_stale=function(e){
      # No durable failed state and no automatic replay of a write callback.
      # Ordinary polling may advance this current view with a new read phase.
      brohn_read_report_package_intent(store,intent_ref$id,intent_ref$project_id)
    })
}
