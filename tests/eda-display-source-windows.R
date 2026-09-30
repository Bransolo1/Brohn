# Runs only on an owned fresh copy of an explicit closed prepared fixture.
args<-commandArgs(TRUE);stopifnot(length(args)==3L)
repo<-normalizePath(args[[1L]],winslash="/",mustWork=TRUE)
prepared<-normalizePath(args[[2L]],winslash="/",mustWork=TRUE)
out<-args[[3L]];stopifnot(!file.exists(out));dir.create(out,recursive=TRUE);out<-normalizePath(out,winslash="/",mustWork=TRUE)
stopifnot(dir.exists(file.path(prepared,"workspace")),file.copy(file.path(prepared,"workspace"),out,recursive=TRUE))
for(name in c("continuous-report.json","event-report.json"))if(file.exists(file.path(prepared,name)))stopifnot(file.copy(file.path(prepared,name),out,overwrite=FALSE))
stopifnot(file.copy(file.path(prepared,"results.json"),file.path(out,"original-results.json"),overwrite=FALSE))
config<-list(checkout=repo,out=out)
setwd(repo);source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=FALSE)
local({
 store<-brohn_open_store(file.path(config$out,"workspace"));checks<-list();passed<-FALSE;failure<-NULL
 on.exit({brohn_write_json_file(list(passed=passed,checks=checks,failure=failure),file.path(config$out,"results.json"));brohn_close_store(store)},add=TRUE)
 check<-function(x,label){stopifnot(isTRUE(x));checks[[length(checks)+1L]]<<-label;cat("PASS",label,"\n")}
 rows<-function(t)DBI::dbGetQuery(store$con,paste("SELECT * FROM",t,"ORDER BY rowid"))
 before<-lapply(c("jobs","entities","entity_versions","objects"),rows)
 tryCatch({
  check(identical(.brohn_ed_recipe,"explicit-saved-distributions/1.0")&&identical(names(.brohn_ed_loaded),"R/platform-explicit-distributions.R")&&is.function(.brohn_edd_recipe),"cold loader keeps legacy explicit namespace separate from new EDA")
  source<-brohn_eda_read_json_file(file.path(config$out,"continuous-report.json"),16*1024^2);ref<-.brohn_rpk_ref(source)
  original<-brohn_read_json_file(file.path(config$out,"original-results.json"))$prepared$continuous$display_ref
  prepared<-brohn_eda_display_catalog(store,original)$items
  env<-environment(brohn_eda_source_windows);path<-get("brohn_object_path",env);reader<-get("brohn_eda_read_json_file",env)
  tryCatch({
   assign("brohn_object_path",function(store,hash,verify=FALSE){if(isTRUE(verify))stop("unexpected source-window hash");path(store,hash,verify)},env)
   assign("brohn_eda_read_json_file",function(...)stop("unexpected source-window full scientific file read"),env)
   pages<-list();cursor<-NULL;repeat{page<-brohn_eda_source_windows(store,ref,cursor,1L);pages<-c(pages,list(page));cursor<-page$next_cursor;if(is.null(cursor))break}
   items<-unlist(lapply(pages,`[[`,"items"),recursive=FALSE)
   check(length(items)==length(prepared)&&length(pages)==3L,"cold original window metadata is paged without evidence file read or rehash")
   check(identical(vapply(items,`[[`,character(1),"key"),vapply(prepared,`[[`,character(1),"key")),"original metadata keys equal exact genuine prepared cell keys")
   check(.brohn_rpk_same(lapply(items,`[[`,"original_default_bounds"),lapply(prepared,`[[`,"original_default_bounds")),"original exact bounds equal genuine prepared default bounds")
   check(!items[[3L]]$focusable&&is.null(items[[3L]]$original_default_bounds)&&identical(items[[3L]]$focus_reason,prepared[[3L]]$focus_reason),"unavailable original segment remains explanatory and cannot receive invented bounds")
   check(all(vapply(pages,function(x)identical(x$source_binding_hash,pages[[1L]]$source_binding_hash)&&identical(x$report_ref,ref),logical(1))),"all metadata pages retain one exact source ref and closure binding")
   check(!any(c("prepared_ref","model","model_hash","coverage") %in% names(pages[[1L]]))&&!any(c("model","model_hash","component_counts") %in% names(items[[1L]])),"cold window page does not invent a prepared model or figure counts")
   bad<-pages[[1L]]$next_cursor;bad$scope<-paste(rep("0",64),collapse="")
   check(inherits(try(brohn_eda_source_windows(store,ref,bad),silent=TRUE),"try-error"),"source-window cursor refuses another source/closure")
   DBI::dbBegin(store$con);denied<-tryCatch({stopifnot(DBI::dbExecute(store$con,"UPDATE jobs SET status='failed' WHERE id=?",params=list(source$body$processing$job_id))==1L);inherits(try(brohn_eda_source_windows(store,ref),silent=TRUE),"try-error")},finally=DBI::dbRollback(store$con))
   check(denied,"fresh window catalog refuses revoked original scientific producer")
   badref<-ref;badref$body_hash<-paste(rep("0",64),collapse="")
   check(inherits(try(brohn_eda_source_windows(store,badref),silent=TRUE),"try-error"),"window catalog refuses wrong historical body hash")
  },finally={assign("brohn_object_path",path,env);assign("brohn_eda_read_json_file",reader,env)})
  event<-brohn_eda_read_json_file(file.path(config$out,"event-report.json"),16*1024^2)
  check(inherits(try(brohn_eda_source_windows(store,.brohn_rpk_ref(event)),silent=TRUE),"try-error"),"event sources refuse continuous window editing")
  after<-lapply(c("jobs","entities","entity_versions","objects"),rows)
  check(identical(before,after),"metadata-only window and namespace qualification leaves all tables unchanged")
  passed<-TRUE
 },error=function(e){failure<<-conditionMessage(e);stop(e)})
})
