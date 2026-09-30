# Guarded read-only export of the original sources for an actual browser download.
# Run only after the owner has closed the browser journey and its local services.
args<-commandArgs(TRUE);stopifnot(length(args)==4L)
base<-normalizePath(args[[1]],winslash="/",mustWork=TRUE)
config_path<-normalizePath(args[[2]],winslash="/",mustWork=TRUE);result_path<-normalizePath(args[[3]],winslash="/",mustWork=TRUE)
out<-args[[4]];stopifnot(!file.exists(out));dir.create(out,recursive=TRUE);out<-normalizePath(out,winslash="/",mustWork=TRUE)
setwd(base);source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=FALSE)
local({
  cfg<-brohn_read_json_file(config_path,maximum=4*1024^2);initial<-brohn_read_json_file(result_path,maximum=4*1024^2)
  stopifnot(initial$passed,is.character(cfg$workspace),dir.exists(cfg$workspace))
  checks<-list();passed<-FALSE;failure<-NULL;store<-NULL;opened<-NULL
  check<-function(ok,label){stopifnot(isTRUE(ok));checks[[length(checks)+1L]]<<-label}
  on.exit({
    if(!is.null(opened))brohn_release_report_package_resources(opened$handle)
    if(!is.null(store))brohn_close_store(store)
    brohn_eda_write_json_file(list(passed=passed,checks=checks,failure=failure,count=length(checks),scope="Guarded original-source export for immutable external oracle; no jobs, reprocessing or package regeneration"),file.path(out,"results.json"))
  },add=TRUE)
  tryCatch({
    store<-brohn_open_store(cfg$workspace)
    snapshot<-function(){tables<-sort(DBI::dbListTables(store$con));setNames(lapply(tables,function(t)digest::digest(DBI::dbReadTable(store$con,t),algo="sha256")),tables)}
    before<-snapshot()
    intent_ref<-initial$new_history$intent_ref;intent<-brohn_get_entity(store,"report_package_intent",intent_ref$id,intent_ref$revision)
    check(identical(brohn_hash(intent$body),intent_ref$body_hash)&&identical(intent$body$status,"succeeded"),"Exact browser-saved successful intent remains available")
    opened<-brohn_open_report_package_resources(store,intent$body$package_ref,"default")
    current<-brohn_report_package_resources_current(store,opened$handle)
    check(identical(current$artifacts$html$hash,initial$new_history$html_sha256)&&identical(current$artifacts$zip$hash,initial$new_history$zip_sha256),"Guarded saved artifacts bind the exact browser HTML and ZIP")
    selection_ref<-opened$record$body$selection_ref;selection<-brohn_get_entity(store,"report_package_selection",selection_ref$id,selection_ref$revision)$body
    producer<-brohn_get_job(store,opened$record$body$processing$job_id)
    sources<-.brohn_rpk_complete_sources(store,opened$handle$source_handle)
    bundle<-c(list(schema="brohn-report-package-render-input/0.1",selection=selection),sources,list(implementation=producer$request$implementation,limits=producer$request$limits))
    brohn_eda_write_json_file(bundle,file.path(out,"original-source-bundle.json"),maximum=128*1024^2)
    check(identical(snapshot(),before),"All logical SQLite tables remain unchanged during guarded source export")
    check(length(bundle$reports)==3L&&length(bundle$eda_displays)==2L&&identical(selection$renderer_profile,"controlled-gaze-explicit-task-choice-eda-paired/0.2"),"Complete original bundle covers the actual three-source renderer0.2 browser package")
    passed<-TRUE
  },error=function(e){failure<<-conditionMessage(e);stop(e)})
  cat(length(checks),"read-only original bundle checks passed\n")
})
