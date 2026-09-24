# Exact processed-row views and immutable complete CSVs; no scientific scoring.
.brohn_signal_values_recipe <- "processed-exact-values/1.0"
.brohn_signal_values_loaded <- setNames(list(digest::digest(file="R/platform-signal-values.R",algo="sha256")),"R/platform-signal-values.R")
# Cache canonical hash computation, never source records or permission decisions.
# The fingerprint includes the current complete R value, so in-place edits,
# nested mutations and same-revision catalog corruption still get fresh checks.
# Only 128 digest pairs are retained; no report body or artifact bytes are cached.
.brohn_sv_hash <- local({
  values<-new.env(hash=TRUE,parent=emptyenv());order<-character()
  function(value) {
    key<-digest::digest(value,algo="sha256",serialize=TRUE,serializeVersion=2)
    if(exists(key,envir=values,inherits=FALSE))return(values[[key]])
    result<-brohn_hash(value)
    if(length(order)>=128L){rm(list=order[[1L]],envir=values);order<<-order[-1L]}
    values[[key]]<-result;order<<-c(order,key);result
  }
})
.brohn_sv_same <- function(a,b) identical(.brohn_sv_hash(a),.brohn_sv_hash(b))
brohn_validate_signal_value_selection <- function(selection) {
  brohn_fields(selection,c("table_id","recording_id","channel","value_column","range","row_policy"),label="Exact processed-value selection")
  brohn_require(all(vapply(selection[c("table_id","recording_id","channel","value_column")],brohn_text,logical(1),max=500))&&
    identical(selection$row_policy,"all_source_rows"),"Choose one exact table and measure; all selected source rows remain included.")
  r<-selection$range
  brohn_require(is.null(r)||(brohn_array(r)&&length(r)==2L&&all(vapply(r,brohn_number,logical(1)))&&r[[1]]<=r[[2]]),
    "Enter an inclusive finite range or select the complete range.")
  invisible(selection)
}
.brohn_sv_retained <- function(store,record,kind,verify) {
  ref<-record$body$result_object
  if(is.null(ref))return(NULL)
  path<-brohn_object_path(store,ref$hash,verify=verify)
  if(verify) {
    original<-brohn_read_json_file(path)
    retained<-if(kind=="report"&&!is.null(original$report))original$report else original
    brohn_require(.brohn_sv_same(retained,record$body[setdiff(names(record$body),"result_object")]),"The retained source envelope differs from its saved catalog.")
  }
  list(hash=ref$hash,bytes=ref$size)
}
brohn_signal_values_input <- function(store,job,verify=TRUE) {
  r<-job$request
  brohn_fields(r,c("report_id","report_revision","report_hash","project_id","catalog_id","catalog_revision","catalog_hash","artifact","selection","recipe","page"),label="Exact-value job request")
  brohn_require(job$operation %in% c("signal_values_page","signal_values_export")&&identical(r$recipe,.brohn_signal_values_recipe),"Choose a registered exact-value operation.")
  brohn_validate_signal_value_selection(r$selection)
  for(kind in c("report","catalog")) {
    id<-r[[paste0(kind,"_id")]];revision<-r[[paste0(kind,"_revision")]]
    brohn_require(brohn_valid_id(id)&&brohn_number(revision,1,2^53-1,TRUE),"The source identity is invalid.")
    .brohn_qexplorer_catalog(store,if(kind=="catalog")"signal_view"else kind,id,revision,r$project_id)
  }
  brohn_project(store,r$project_id)
  report<-brohn_get_entity(store,"report",r$report_id,r$report_revision)
  lineage<-brohn_signal_audio_lineage(store,report,verify)
  catalog<-brohn_get_entity(store,"signal_view",r$catalog_id,r$catalog_revision)
  brohn_require(identical(.brohn_sv_hash(report$body),r$report_hash)&&identical(.brohn_sv_hash(catalog$body),r$catalog_hash)&&
    identical(catalog$body$operation,"signal_catalog")&&identical(catalog$body$report_id,r$report_id)&&
    .brohn_sv_same(catalog$body$report_revision,r$report_revision)&&identical(catalog$body$report_hash,r$report_hash),
    "The saved table catalog belongs to another report or revision. Reopen its exact source.")
  artifact<-brohn_signal_artifact(report,r$artifact$kind)
  brohn_require(.brohn_sv_same(artifact,r$artifact)&&identical(catalog$body$artifact_hash,artifact$sha256)&&
    .brohn_sv_same(catalog$body$view$artifact,artifact[setdiff(names(artifact),"complete")]),"The catalog and complete processed artifact disagree.")
  found<-Filter(function(t)identical(t$table_id,r$selection$table_id),catalog$body$view$tables)
  brohn_require(length(found)==1L,"Choose an exact table from this catalog page.");table<-found[[1L]]
  brohn_require(identical(table$identity$recording_id,r$selection$recording_id)&&identical(table$identity$channel,r$selection$channel)&&
    r$selection$value_column %in% vapply(table$value_columns,`[[`,character(1),"name"),"The selected measure belongs to another table or recording.")
  if(job$operation=="signal_values_page")brohn_require(is.list(r$page)&&identical(sort(names(r$page)),c("limit","offset"))&&
    brohn_number(r$page$offset,0,20000000,TRUE)&&isTRUE(r$page$limit %in% c(25,50,100)),"Choose 25, 50 or 100 rows and a valid starting row.")else
    brohn_require(is.null(r$page),"Complete exports do not accept a page limit.")
  source_objects<-list(list(hash=artifact$sha256,bytes=artifact$bytes))
  for(pair in list(list(record=report,kind="report"),list(record=catalog,kind="signal_view"))) {
    ref<-.brohn_sv_retained(store,pair$record,pair$kind,verify)
    if(!is.null(ref))source_objects[[length(source_objects)+1L]]<-ref
  }
  if(!is.null(lineage))source_objects<-c(source_objects,lineage$source_refs)
  # The streaming child verifies every artifact byte; parent hashing is optional
  # only for small context checks and final metadata-only transaction checks.
  path<-brohn_object_path(store,artifact$sha256,verify=FALSE)
  binding<-r[c("report_id","report_revision","report_hash","project_id","catalog_id","catalog_revision","catalog_hash")]
  binding$selection_hash<-brohn_hash(r$selection)
  result<-list(schema="brohn-analysis-input/1.0",operation=job$operation,project_id=r$project_id,origin=report$body$origin,
    binding=binding,artifact=artifact,source_path=path,source_objects=source_objects,
    verification_receipt=report$body$analysis$artifact_verification,table=table,selection=r$selection,page=r$page)
  if(!is.null(lineage))result$derived_audio_lineage<-lineage
  result
}
brohn_queue_signal_values <- function(store,catalog_id,selection,mode="page",offset=0L,limit=50L,catalog_revision=NULL,catalog_hash=NULL,retry=FALSE) {
  brohn_require(mode %in% c("page","export"),"Choose exact values or complete CSV preparation.")
  catalog<-brohn_get_entity(store,"signal_view",catalog_id,catalog_revision)
  brohn_require(!is.null(catalog)&&identical(catalog$body$operation,"signal_catalog"),"Open a saved processed-table catalog first.")
  if(!is.null(catalog_hash))brohn_require(identical(.brohn_sv_hash(catalog$body),catalog_hash),"This catalog changed. Reopen its current saved source.")
  r<-list(report_id=catalog$body$report_id,report_revision=catalog$body$report_revision,report_hash=catalog$body$report_hash,
    project_id=catalog$project_id,catalog_id=catalog$id,catalog_revision=catalog$revision,catalog_hash=.brohn_sv_hash(catalog$body),
    artifact=c(catalog$body$view$artifact,list(complete=TRUE)),selection=selection,recipe=.brohn_signal_values_recipe,
    page=if(mode=="page")list(offset=offset,limit=limit)else NULL)
  operation<-paste0("signal_values_",mode)
  brohn_signal_values_input(store,list(operation=operation,request=r),verify=FALSE)
  brohn_enqueue_job(store,operation,r,paste0(operation,":",brohn_hash(r),if(retry)paste0(":",brohn_id("retry"))else""))
}
brohn_hold_signal_value_sources <- function(store,input) {
  brohn_require(.Platform$OS.type=="windows","Exact processed-value publication requires the qualified Windows source read guard.")
  guards<-list();success<-FALSE;seen<-character()
  on.exit(if(!success)for(g in guards).brohn_qexplorer_release(g),add=TRUE)
  for(ref in input$source_objects)if(!ref$hash %in% seen) {
    guards[[length(guards)+1L]]<-.brohn_qexplorer_hold(brohn_object_path(store,ref$hash,verify=FALSE),ref$bytes);seen<-c(seen,ref$hash)
  }
  success<-TRUE;guards
}
brohn_validate_signal_values <- function(result,input) {
  brohn_require(identical(result$schema,"brohn-signal-values/1.0")&&result$status %in% c("completed","empty_range")&&
    identical(result$operation,input$operation)&&.brohn_sv_same(result$binding,input$binding)&&.brohn_sv_same(result$selection,input$selection)&&
    .brohn_sv_same(result$artifact,input$artifact[setdiff(names(input$artifact),"complete")]),"The exact-value result substituted its source or selection.")
  t<-result$table
  brohn_require(identical(t$table_id,input$table$table_id)&&.brohn_sv_same(t$identity,input$table$identity)&&
    .brohn_sv_same(t$coordinates,input$table$coordinates)&&.brohn_sv_same(t$expected_rows,input$table$rows)&&brohn_array(t$columns),
    "The returned table changed its declared source identity or clock.")
  f<-result$full_source;s<-result$selected_source
  for(v in list(f,s))brohn_require(brohn_number(v$rows,0,input$artifact$rows,TRUE)&&
    all(vapply(v[c("observed_coordinate_rows","observed_value_rows","eligible_value_rows","excluded_retention_rows","unknown_retention_rows","retained_rows","undeclared_retention_rows","missing_value_rows","missing_coordinate_rows")],brohn_number,logical(1),min=0,max=v$rows,integer=TRUE))&&
    v$observed_coordinate_rows+v$missing_coordinate_rows==v$rows&&v$observed_value_rows+v$missing_value_rows==v$rows&&
    v$excluded_retention_rows+v$unknown_retention_rows+v$retained_rows+v$undeclared_retention_rows==v$rows,"Exact-value support counts do not reconcile.")
  brohn_require(f$rows==t$expected_rows&&s$rows<=f$rows&&identical(result$status,if(s$rows==0)"empty_range"else"completed"),"Selected rows or empty status disagree with complete source support.")
  if(input$operation=="signal_values_page") {
    p<-result$page;rows<-result$rows
    brohn_require(.brohn_sv_same(p$offset,input$page$offset)&&.brohn_sv_same(p$limit,input$page$limit)&&p$total_rows==s$rows&&
      brohn_array(rows)&&length(rows)<=p$limit&&p$returned==length(rows),"Exact-value pagination was truncated or substituted.")
    next_offset<-p$offset+length(rows)
    brohn_require(.brohn_sv_same(p$next_offset,if(length(rows)&&next_offset<s$rows)next_offset else NULL)&&
      .brohn_sv_same(p$previous_offset,if(p$offset>0)max(0,p$offset-p$limit)else NULL),"Exact-value continuation is inconsistent.")
    indices<-numeric()
    for(i in seq_along(rows)) {
      row<-rows[[i]]
      brohn_require(brohn_number(row$table_row_index,0,max(0,f$rows-1),TRUE)&&row$selected_row_index==p$offset+i-1&&
        brohn_text(row$coordinate_text,100,TRUE)&&brohn_text(row$value_text,100,TRUE)&&
        all(vapply(row[c("coordinate_is_null","value_is_null","plot_eligible")],function(x)is.logical(x)&&length(x)==1L&&!is.na(x),logical(1)))&&
        row$retention %in% c("not_declared","retained","excluded","unknown")&&brohn_text(row$exact_record_json,3*1024^2),"An exact-value row lacks its typed support or source index.")
      native<-brohn_parse(row$exact_record_json,max_bytes=3*1024^2)
      brohn_require(setequal(names(native),vapply(t$columns,`[[`,character(1),"name")),"Exact row detail has different declared columns.")
      indices<-c(indices,row$table_row_index)
    }
    brohn_require(!length(indices)||all(diff(indices)>0),"Source rows were reordered or duplicated.")
  } else {
    c<-result$csv
    brohn_require(brohn_text(c$sha256,64)&&grepl("^[a-f0-9]{64}$",c$sha256)&&brohn_number(c$bytes,1,2*1024^3,TRUE)&&
      c$rows==s$rows&&identical(c$media_type,"text/csv; charset=utf-8")&&brohn_array(c$columns)&&length(c$columns)>0L,
      "The complete CSV has no exact byte/count receipt.")
  }
  no_paths<-function(x)!is.list(x)||(!any(names(x)%in%c("path","source_path","output_path","export_path"))&&all(vapply(x,no_paths,logical(1))))
  brohn_require(no_paths(result),"An exact-value result contains a private filesystem path.")
  invisible(result)
}
brohn_analyse_signal_values <- function(input,scratch) {
  request<-list(schema="brohn-signal-values-request/1.0",operation=input$operation,
    artifact=c(input$artifact,list(path=normalizePath(input$source_path,winslash="/",mustWork=TRUE))),verification_receipt=input$verification_receipt,
    binding=input$binding,table=input$table,selection=input$selection)
  if(input$operation=="signal_values_page")request$page<-input$page else {
    brohn_require(dir.create(file.path(scratch,"artifacts")),"Cannot prepare a new exact-value export directory.")
    request$export_path<-normalizePath(file.path(scratch,"artifacts","exact-values.csv"),winslash="/",mustWork=FALSE)
  }
  request_path<-file.path(scratch,"exact-values-request.json");result_path<-file.path(scratch,"exact-values-result.json")
  brohn_write_json_file(request,request_path,maximum=4*1024^2)
  child<-processx::run(brohn_python_profile("eda"),c("scripts/workers/signal_values.py","--request",request_path,"--output",result_path),
    timeout=15*60,error_on_status=FALSE,cleanup_tree=TRUE,windows_hide_window=TRUE)
  brohn_require(file.exists(result_path),paste("Exact values could not be read.",substr(child$stderr,1,1000)))
  result<-brohn_read_json_file(result_path)
  brohn_require(child$status==0&&!identical(result$status,"error"),paste("Exact values need attention:",brohn_default(result$error$message,substr(child$stderr,1,1000))))
  brohn_validate_signal_values(result,input)
  list(signal_values=result)
}
brohn_publish_signal_values <- function(store,output,scratch,job,input,output_path) {
  brohn_require(!RSQLite::sqliteIsTransacting(store$con),"Prepare exact-value results outside the writer transaction.")
  .brohn_publication_output_identity(output,.brohn_signal_values_loaded);.brohn_publication_job(store,job)
  if(!is.null(input$derived_audio_lineage)).brohn_publication_output_identity(output,.brohn_audio_extraction_loaded["R/platform-audio-extraction.R"])
  guards<-brohn_hold_signal_value_sources(store,input)
  on.exit(for(g in guards).brohn_qexplorer_release(g),add=TRUE)
  brohn_require(.brohn_sv_same(input,brohn_signal_values_input(store,job))&&.brohn_sv_same(brohn_read_json_file(output_path),output),"The exact-value publication changed its pinned input or output.")
  result<-output$report$signal_values;brohn_validate_signal_values(result,input)
  csv<-NULL;document<-NULL;committed<-FALSE
  on.exit({if(!is.null(document))brohn_close_publication(document$guard,committed);if(!is.null(csv))brohn_close_publication(csv$guard,committed)},add=TRUE)
  if(input$operation=="signal_values_export") {
    path<-brohn_checked_artifact_path(store,file.path(scratch,"artifacts","exact-values.csv"),scratch)
    csv<-.brohn_publication_stage(store,job,list(list(key="exact-values",kind="signal-values-csv",path=path,
      sha256=result$csv$sha256,bytes=result$csv$bytes,media_type=result$csv$media_type)))
  }
  id<-paste0("signal-values-",sub("^job-","",job$id))
  body<-list(schema="brohn-saved-signal-values/1.0",id=id,report_id=input$binding$report_id,origin=input$origin,
    operation=job$operation,request=job$request,result=result,csv_object=if(is.null(csv))NULL else csv$descriptors[[1L]][c("hash","size","media_type")],
    created_at=brohn_now(),processing=list(job_id=job$id,attempt=job$attempt,worker_output_hash=digest::digest(file=output_path,algo="sha256"),code_hashes=output$code_identity))
  document<-.brohn_publication_stage_json(store,job,body,file.path(scratch,"published-exact-values.json"))
  receipt<-brohn_store_batch(store,function() {
    brohn_require(.brohn_sv_same(input,brohn_signal_values_input(store,job,verify=FALSE)),"Source or project authority changed before publication.")
    for(g in guards).Call(g$native$check,g$pointer)
    .brohn_publication_job(store,job)
    if(!is.null(csv)).brohn_publication_register(store,csv)
    body$result_object<-.brohn_publication_register(store,document)[[1L]][c("hash","size","media_type")]
    brohn_put_entity(store,"signal_values",id,body,expected_revision=0L,project_id=input$project_id)
    brohn_complete_job(store,job$id,job$worker,job$token,list(signal_values_id=id,report_id=input$binding$report_id,output_hash=body$result_object$hash))
  })
  committed<-TRUE;receipt
}
brohn_signal_values_record <- function(store,id,expected_hash=NULL,verify=FALSE) {
  record<-brohn_get_entity(store,"signal_values",id)
  brohn_require(!is.null(record)&&identical(record$body$schema,"brohn-saved-signal-values/1.0"),"The saved exact-value result is unavailable.")
  if(!is.null(expected_hash))brohn_require(identical(.brohn_sv_hash(record$body),expected_hash),"This exact-value result changed. Reopen it.")
  input<-brohn_signal_values_input(store,list(operation=record$body$operation,request=record$body$request),verify=verify)
  brohn_require(identical(record$project_id,input$project_id),"The exact-value result belongs to another project.")
  if(verify) {
    body<-brohn_read_json_file(brohn_object_path(store,record$body$result_object$hash))
    brohn_require(.brohn_sv_same(body,record$body[setdiff(names(record$body),"result_object")]),"Saved exact values differ from their retained publication.")
    brohn_validate_signal_values(record$body$result,input)
  }
  record
}
