# Portable shared-dependency regression: real SQLite job/intent state, explicit
# source/preparation spies. No scientific jobs, native guards or services.
# Rscript tests/report-choice-shared-cancellation.R <source-root> <fresh-evidence> [<loader-root>]
args<-commandArgs(TRUE);stopifnot(length(args)%in%c(2L,3L))
candidate<-normalizePath(args[[1]],winslash="/",mustWork=TRUE)
loader<-if(length(args)==3L)normalizePath(args[[3]],winslash="/",mustWork=TRUE)else candidate
out<-args[[2]];stopifnot(!file.exists(out));dir.create(out,recursive=TRUE)
out<-normalizePath(out,winslash="/",mustWork=TRUE)
setwd(loader);source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=FALSE)
for(p in c("platform-report-package.R","platform-report-package-distributions.R"))for(e in parse(file.path(candidate,"R",p)))
  if(is.call(e)&&identical(e[[1L]],as.name("<-"))&&is.call(e[[3L]])&&identical(e[[3L]][[1L]],as.name("function")))eval(e,envir=.GlobalEnv)
source(file.path(candidate,"R/platform-report-package-preparation.R"),encoding="UTF-8")
source(file.path(candidate,"R/platform-report-package-authority.R"),encoding="UTF-8")
.brohn_rpk_distribution_choice_schema<-"brohn-report-package-distribution-job/0.2"
checks<-list()
check<-function(label,value){checks[[length(checks)+1L]]<<-list(label=label,passed=isTRUE(value));cat(if(isTRUE(value))"PASS"else"FAIL",label,"\n");if(!isTRUE(value))stop(label)}
reject<-function(expr)tryCatch({force(expr);FALSE},error=function(e)TRUE)
spy<-new.env();spy$ready<-list();spy$queues<-0L;spy$resolves<-0L;spy$panels<-1L;spy$renderer<-brohn_hash("fixture-renderer-1")
implementation<-function(profile)list(profile=profile,hash=brohn_hash(list("explicit-fixture",profile)))
brohn_task_display_implementation_ref<-function(preparation_profile="saved-task-display/0.1")implementation(preparation_profile)
brohn_choice_display_implementation_ref<-function()implementation("saved-choice-display/0.1")
.brohn_rpk_distribution_implementation_ref<-function(source_admission="task-findings/0.1")implementation(if(source_admission=="task-choice-findings/0.1")"saved-explicit-distribution/0.2"else"saved-explicit-distribution/0.1")
.brohn_rpk_renderer_implementation_ref<-function()list(profile="static-complete-findings/0.1",hash=spy$renderer)
brohn_report_package_task_limits<-brohn_report_package_limits
brohn_report_package_choice_limits<-function(){x<-brohn_report_package_limits();x$profile<-"controlled-task-choice-report-package/0.1";x}
# Only A's mapping and source-component metadata boundary are replaced here.
brohn_report_source_admission<-function(renderer_profile)switch(renderer_profile,
  "controlled-gaze-explicit-paired/0.1"="gaze-explicit-paired-findings/0.1",
  "controlled-gaze-explicit-task-paired/0.1"="task-findings/0.1",
  "controlled-gaze-explicit-task-choice-paired/0.1"="task-choice-findings/0.1",stop("unknown renderer"))
metadata<-.brohn_rpk_report_metadata
.brohn_rpk_report_metadata<-function(store,ref){m<-metadata(store,ref)
  m$source_components<-as.list(c(if(m$kind=="questionnaire")"explicit",if(m$task_score_count>0L||m$kind %in% c("implicit","implicit_cohort"))"task",if(m$choice_task_count>0L||m$kind=="explicit_choice")"choice"));m}
key<-function(kind,ref)paste(kind,ref$id,sep=":")
prepare_request<-function(kind,ref,impl,admission=NULL){r<-list(project_id=ref$project_id,report_ref=ref,implementation_ref=impl,admission=admission)
  r$content_fingerprint<-brohn_hash(r);r}
.brohn_task_display_request<-function(store,report_ref,implementation_ref)prepare_request("task_display",report_ref,implementation_ref)
.brohn_choice_display_request<-function(store,report_ref,implementation_ref)prepare_request("choice_display",report_ref,implementation_ref)
distribution_request<-.brohn_rpk_distribution_request
.brohn_rpk_distribution_request<-function(store,report_ref,implementation_ref=NULL,source_admission=NULL){r<-prepare_request("explicit_distributions",report_ref,implementation_ref,source_admission);r$content_fingerprint<-NULL;r}
find_saved<-function(kind,ref,profile,impl){stopifnot(identical(profile,impl$profile));spy$ready[[key(kind,ref)]]}
brohn_find_task_display<-function(store,report_ref,preparation_profile,implementation_ref)find_saved("task_display",report_ref,preparation_profile,implementation_ref)
brohn_find_choice_display<-function(store,report_ref,preparation_profile,implementation_ref)find_saved("choice_display",report_ref,preparation_profile,implementation_ref)
.brohn_rpk_find_pinned_distribution<-function(store,report_ref,implementation_ref,source_admission){stopifnot(identical(source_admission,"task-choice-findings/0.1"));find_saved("explicit_distributions",report_ref,implementation_ref$profile,implementation_ref)}
queue<-function(store,kind,ref,retry,impl,admission=NULL){r<-prepare_request(kind,ref,impl,admission)
  old<-.brohn_rpk_latest_job(store,kind,r$content_fingerprint)
  if(!is.null(old)&&(!retry||old$status %in% c("queued","running","succeeded")))return(old)
  spy$queues<-spy$queues+1L;brohn_enqueue_job(store,kind,r,paste0("choice-intent-fixture-",spy$queues))}
brohn_queue_task_display<-function(store,report_ref,retry=FALSE,implementation_ref=NULL)queue(store,"task_display",report_ref,retry,implementation_ref)
brohn_queue_choice_display<-function(store,report_ref,retry=FALSE,implementation_ref=NULL)queue(store,"choice_display",report_ref,retry,implementation_ref)
brohn_queue_explicit_distributions_ref<-function(store,report_ref,retry=FALSE,implementation_ref=NULL,source_admission=NULL)queue(store,"explicit_distributions",report_ref,retry,implementation_ref,source_admission)
.brohn_rpk_selection_sources<-function(store,selection)list(report_refs=selection$report_refs,prepared_sources=selection$prepared_sources)
brohn_task_display_catalog<-function(store,display_ref,cursor=NULL,limit=25L)list(items=list(list(key=brohn_hash("task-model"))),next_cursor=NULL)
brohn_choice_display_catalog<-function(store,display_ref,cursor=NULL,limit=25L)list(items=list(list(key=brohn_hash("choice-model"),utilities=list(status="not_requested",row_count=0L,panel_cost=1L))),next_cursor=NULL)
brohn_resolve_task_report_section<-function(section,catalog){spy$resolves<-spy$resolves+1L;section$resolved_models<-catalog;list(section=section,panel_count=0L)}
brohn_resolve_choice_report_section<-function(section,catalog){spy$resolves<-spy$resolves+1L;section$resolved_models<-catalog;list(section=section,panel_count=spy$panels)}
.brohn_rpk_group_ids<-function(store,ref,selector)list("fixture-response-group")
.brohn_rpk_explicit_panel_count<-function(store,section)1L
store<-brohn_open_store(file.path(out,"store"))
invisible(brohn_put_entity(store,"project","default",list(id="default",title="Choice lifecycle fixture",archived=FALSE)))
design<-brohn_new_design("Choice lifecycle fixture","survey","study-choice-intents");invisible(brohn_put_entity(store,"study",design$id,design))
source_ref<-function(id,kind="questionnaire",task=FALSE,choice=FALSE){body<-list(id=id,study_id=design$id,title=id,origin="sample",
  analysis=list(kind=kind,task_scores=if(task)list(list(profile="fixture-only"))else list(),choice_tasks=if(choice)list(list(profile="fixture-only"))else list()),
  provenance=list(design=design,design_hash=brohn_hash(design)))
  .brohn_rpk_ref(brohn_put_entity(store,"report",id,body,0L,"default"))}
mixed<-source_ref("report-mixed-fixture",task=TRUE,choice=TRUE)
imported<-source_ref("report-choice-import-fixture","explicit_choice",choice=TRUE)
task_only<-source_ref("report-task-fixture","implicit",task=TRUE)
section<-function(ref,adapter,order=1L)list(id=paste0("section-",order),adapter=adapter,adapter_version="0.1",source_report_ref=ref,
  selector=list(scope=if(adapter=="task-scores")"all_administrations"else if(adapter=="explicit-distribution")"all_groups"else"all_exercises"),
  display=if(adapter %in% c("task-scores","explicit-distribution"))list(pages="all")else list(pages="all",page_numbers=list()),order=order)
request<-function(refs=list(mixed,imported),sections=list(section(mixed,"explicit-distribution"),section(mixed,"task-scores",2L),section(mixed,"choice-counts",3L),section(mixed,"choice-utilities",4L),section(imported,"choice-utilities",5L)))
  list(schema="brohn-report-package-intent-request/0.1",study_id=design$id,project_id="default",title="Saved mixed choice intent fixture",report_refs=refs,requested_sections=sections,
  contents_policy=list(profile="complete-findings/0.1",audience="research_team",identifier_mode="package_aliases",stimulus_images="excluded_by_choice",complete_selected_numerical_evidence=TRUE,include_original_evidence=FALSE,include_raw_recordings=FALSE),
  limits_profile="controlled-task-choice-report-package/0.1",renderer_profile="controlled-gaze-explicit-task-choice-paired/0.1")
create<-function(id,req=request(),prior=NULL)brohn_save_report_package_intent(store,id,req,if(is.null(prior))NULL else prior$revision,prior)
ready<-function(dep){id<-paste0("display-",gsub("_","-",dep$kind),"-",dep$report_ref$id)
  spy$ready[[key(dep$kind,dep$report_ref)]]<-.brohn_rpk_ref(brohn_put_entity(store,dep$kind,id,list(schema="fixture-preparation",source=dep$report_ref),0L,"default"))}
a<-create("owner",request(list(mixed),list(section(mixed,"explicit-distribution"),section(mixed,"task-scores",2L),section(mixed,"choice-counts",3L))))
a<-brohn_continue_report_package_intent(store,a$intent_ref)
b<-create("shared-with-own-extra");b<-brohn_continue_report_package_intent(store,b$intent_ref)
shared<-vapply(a$dependencies,`[[`,character(1),"job_id")
extra<-setdiff(vapply(b$dependencies,`[[`,character(1),"job_id"),shared)
stopifnot(length(shared)==3L,length(extra)==1L)
claimed<-list()
for(i in 1:4){j<-brohn_claim_job(store,paste0("peer-state-only-",i),lease_seconds=3600);claimed[[j$id]]<-j}
j<-claimed[[extra]];invisible(brohn_fail_job(store,j$id,j$worker,j$token,list(message="Independent second-source preparation failed")))
b<-brohn_continue_report_package_intent(store,b$intent_ref)
before<-vapply(shared,function(id)brohn_get_job(store,id)$status,character(1))
users<-vapply(shared,function(id).brohn_rpk_dependency_users(store,id,a$intent_ref$id),numeric(1))
a<-brohn_cancel_report_package_intent(store,a$intent_ref)
after<-vapply(shared,function(id)brohn_get_job(store,id)$status,character(1))
failed_status<-b$status
b<-brohn_cancel_report_package_intent(store,b$intent_ref)
cancelled_users<-vapply(shared,function(id).brohn_rpk_dependency_users(store,id,a$intent_ref$id),numeric(1))
result<-list(scope="Real SQLite job/intent state with explicit source/preparation spies; no scientific execution or native worker process",owner_status=a$status,consumer_status=b$status,
 consumer_retained_dependencies=vapply(b$dependencies,`[[`,character(1),"job_id"),shared_jobs=shared,other_consumers_counted=users,before=before,after=after,
 failed_consumer_status=failed_status,failed_consumer_shared_jobs_preserved=identical(before,after),explicitly_cancelled_consumer_counted=cancelled_users,
 passed=identical(failed_status,"failed")&&length(b$dependencies)==4L&&all(before=="running")&&identical(before,after)&&all(users==1L)&&b$status=="cancelled"&&all(cancelled_users==0L),source_hash=digest::digest(file=file.path(candidate,"R/platform-report-package.R"),algo="sha256"))
for(id in shared)invisible(brohn_cancel_job(store,id))
result$fixture_cleanup_terminal<-all(vapply(c(shared,extra),function(id)brohn_get_job(store,id)$status%in%c("cancelled","failed"),logical(1)))
brohn_write_json_file(result,file.path(out,"results.json"));brohn_close_store(store)
cat(brohn_json(result),"\n")
if(!isTRUE(result$passed)||!isTRUE(result$fixture_cleanup_terminal))quit(status=1L)
