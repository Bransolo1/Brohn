# Root lifecycle component qualification. Real SQLite intents/jobs and exact
# source references; explicit boundary spies for source science/preparations.
# This does not qualify display workers, native guards or complete exports.
args<-commandArgs(TRUE);stopifnot(length(args)%in%c(2L,3L))
loader<-normalizePath(args[[1]],winslash="/",mustWork=TRUE)
candidate<-normalizePath(if(length(args)==3L)args[[2]]else args[[1]],winslash="/",mustWork=TRUE)
out<-args[[length(args)]];stopifnot(!file.exists(out));dir.create(out,recursive=TRUE)
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
a<-create("first");plan<-brohn_get_entity(store,"report_package_intent",a$intent_ref$id)$body$execution_plan
check("Prepare saves the choice plan before any dependent job",a$status=="prepared"&&spy$queues==0L&&plan$schema=="brohn-task-choice-report-execution-plan/0.1")
check("plan pins exact source admission and separate0.2 task/distribution profiles",plan$source_admission=="task-choice-findings/0.1"&&plan$task_display_implementation_ref$profile=="saved-task-display/0.2"&&plan$explicit_distribution_implementation_ref$profile=="saved-explicit-distribution/0.2"&&plan$choice_display_implementation_ref$profile=="saved-choice-display/0.1")
check("duplicate command preserves original plan without queuing",.brohn_rpk_same(a$intent_ref,create("first")$intent_ref)&&spy$queues==0L)
bad<-plan;bad$task_display_implementation_ref$profile<-"saved-task-display/0.1"
check("choice plans reject opportunistic old task preparation",reject(.brohn_rpk_plan_valid(bad,request())))
bad<-plan;bad$source_admission<-"task-findings/0.1"
check("source admission cannot be lowered inside a saved choice plan",reject(.brohn_rpk_plan_valid(bad,request())))
old<-request(list(task_only),list(section(task_only,"task-scores")));old$renderer_profile<-"controlled-gaze-explicit-task-paired/0.1";old$limits_profile<-"controlled-task-report-package/0.1"
old_intent<-create("old-task",old);old_plan<-brohn_get_entity(store,"report_package_intent",old_intent$intent_ref$id)$body$execution_plan
check("old task plans retain their field set and0.1 profiles",old_plan$schema=="brohn-task-report-execution-plan/0.1"&&is.null(old_plan$source_admission)&&is.null(old_plan$choice_display_implementation_ref)&&old_plan$task_display_implementation_ref$profile=="saved-task-display/0.1")
bad<-request(list(mixed),list(section(mixed,"task-scores")));bad$renderer_profile<-old$renderer_profile;bad$limits_profile<-old$limits_profile
check("hidden choice evidence still refuses the old task renderer",reject(create("hidden-old",bad)))
bad<-request();bad$execution_plan<-plan
check("clients cannot replace a server-authored preparation plan",reject(create("client-plan",bad)))
bad<-section(mixed,"choice-counts");bad$display<-list(pages="selected",page_numbers=list(1L,1L))
check("duplicate choice table pages fail before any source work",reject(.brohn_rpk_choice_section(bad)))
bad$display$page_numbers<-list(3L)
check("choice pages beyond the sixty-item profile fail before preparation",reject(.brohn_rpk_choice_section(bad)))
a<-brohn_continue_report_package_intent(store,a$intent_ref)
check("dependencies follow selected source then explicit/task/choice order",a$status=="waiting_for_display"&&identical(vapply(a$dependencies,`[[`,character(1),"kind"),c("explicit_distributions","task_display","choice_display","choice_display"))&&identical(vapply(a$dependencies,function(d)d$report_ref$id,character(1)),c(mixed$id,mixed$id,mixed$id,imported$id)))
check("all prerequisites retain the exact implementation selected in the original plan",all(vapply(a$dependencies,function(d).brohn_rpk_same(d$implementation_ref,switch(d$kind,explicit_distributions=plan$explicit_distribution_implementation_ref,task_display=plan$task_display_implementation_ref,choice_display=plan$choice_display_implementation_ref)),logical(1))))
b<-create("shared");b<-brohn_continue_report_package_intent(store,b$intent_ref)
check("second intent reuses all four jobs without cancellation ownership",spy$queues==4L&&all(!vapply(b$dependencies,`[[`,logical(1),"created_for_intent")))
a<-brohn_cancel_report_package_intent(store,a$intent_ref)
check("cancelling the owner preserves shared preparation jobs",all(vapply(b$dependencies,function(d)brohn_get_job(store,d$job_id)$status=="queued",logical(1))))
hidden<-create("hidden-choice",request(list(mixed),list(section(mixed,"task-scores"))));hidden<-brohn_continue_report_package_intent(store,hidden$intent_ref)
check("hiding choice figures still requires complete choice preparation",identical(vapply(hidden$dependencies,`[[`,character(1),"kind"),c("task_display","choice_display")))
pending_ids<-vapply(b$dependencies,`[[`,character(1),"job_id")
invisible(brohn_cancel_job(store,pending_ids[[1L]]))
b<-brohn_continue_report_package_intent(store,b$intent_ref)
check("an early stopped prerequisite retains all later exact dependencies",b$status=="cancelled"&&identical(vapply(b$dependencies,`[[`,character(1),"job_id"),pending_ids))
b<-brohn_continue_report_package_intent(store,b$intent_ref,"retry")
check("explicit retry replaces only the cancelled prerequisite",b$status=="waiting_for_display"&&spy$queues==5L&&identical(vapply(b$dependencies[-1L],`[[`,character(1),"job_id"),pending_ids[-1L]))
invisible(lapply(b$dependencies,ready));b<-brohn_continue_report_package_intent(store,b$intent_ref)
saved<-brohn_get_entity(store,"report_package_selection",b$selection_ref$id)$body
check("all preparations freeze into one existing assembly lifecycle",b$status=="assembly_queued"&&saved$schema=="brohn-report-package-selection/0.2"&&length(saved$prepared_sources)==4L)
check("choice sections retain requested defaults beside exact prepared references",all(vapply(saved$sections[3:5],function(s)s$source_ref$kind=="choice_display"&&s$selector$scope=="all_exercises"&&!length(s$display$page_numbers)&&length(s$resolved_models)==1L,logical(1))))
check("unrequested utility models remain selected explanatory panels",b$preparation$resolved_panel_count==4L&&all(vapply(saved$sections[3:5],function(s)s$resolved_models[[1L]]$utilities$status=="not_requested",logical(1))))
manifest<-.brohn_rpk_manifest_sources(saved)
check("source manifest includes every choice andtask preparation with selected order",length(manifest$choice_displays)==2L&&length(manifest$task_displays)==1L&&length(manifest$distributions)==1L)
old_sources<-.brohn_rpk_manifest_sources(list(renderer_profile=old$renderer_profile,report_refs=list(task_only),prepared_sources=list()))
check("old task manifest does not acquire an empty choice field",!"choice_displays" %in% names(old_sources))
selection<-b$selection_ref;before<-c(spy$queues,spy$resolves)
b<-brohn_cancel_report_package_intent(store,b$intent_ref);b<-brohn_continue_report_package_intent(store,b$intent_ref,"retry")
check("assembly retry preserves the exact selection without resolving or preparing again",.brohn_rpk_same(selection,b$selection_ref)&&identical(before,c(spy$queues,spy$resolves)))
spy$panels<-101L;limit<-create("figure-limit",request(list(imported),list(section(imported,"choice-utilities"))));limit<-brohn_continue_report_package_intent(store,limit$intent_ref)
check("panel overflow becomes review and retains all numerical preparation",limit$status=="needs_attention"&&limit$preparation$reason_code=="panel_limit"&&length(limit$preparation$prepared_sources)==1L&&is.null(limit$selection_ref))
spy$panels<-1L;drift<-create("implementation-drift");pinned<-brohn_get_entity(store,"report_package_intent",drift$intent_ref$id)$body$execution_plan
before<-spy$queues;spy$renderer<-brohn_hash("fixture-renderer-2");drift<-brohn_continue_report_package_intent(store,drift$intent_ref)
check("implementation drift requires explicit review without new jobs or rewritten plan",drift$status=="needs_attention"&&drift$preparation$reason_code=="implementation_changed"&&spy$queues==before&&.brohn_rpk_same(pinned,brohn_get_entity(store,"report_package_intent",drift$intent_ref$id)$body$execution_plan))
# Exercise the actual distribution schema/admission helper independently of
# queue spies; these are original schema shapes, not producer receipts.
untagged<-list(schema=.brohn_rpk_distribution_schema)
tagged<-c(untagged,list(preparation_implementation_ref=implementation("saved-explicit-distribution/0.1")))
new<-list(schema=.brohn_rpk_distribution_choice_schema,source_admission="task-choice-findings/0.1",preparation_implementation_ref=implementation("saved-explicit-distribution/0.2"))
check("historical distribution schema determines its original admission",.brohn_rpk_distribution_admission(untagged)=="gaze-explicit-paired-findings/0.1"&&.brohn_rpk_distribution_admission(tagged)=="task-findings/0.1"&&.brohn_rpk_distribution_admission(new)=="task-choice-findings/0.1")
bad<-tagged;bad$source_admission<-new$source_admission
check("old distribution schemas reject a new admission field",reject(.brohn_rpk_distribution_admission(bad)))
bad<-new;bad$preparation_implementation_ref<-tagged$preparation_implementation_ref
check("choice distributions reject an old preparation profile",reject(.brohn_rpk_distribution_admission(bad)))
check("choice authority is issued for the actual operation",brohn_report_package_queue_authority(store,"choice_display","default")$operation=="choice_display")
brohn_close_store(store)
files<-c("R/platform-report-package.R","R/platform-report-package-preparation.R","R/platform-report-package-distributions.R","R/platform-report-package-authority.R")
brohn_write_json_file(list(schema="brohn-choice-root-intent-contract/0.1",scope="Real SQLite intents/jobs with explicit metadata/science/preparation/renderer spies; not worker, source authority, export or browser acceptance",checks=checks,
  files=setNames(lapply(files,function(p)digest::digest(file=file.path(candidate,p),algo="sha256")),files)),file.path(out,"results.json"))
cat(length(checks),"checks passed\n")
