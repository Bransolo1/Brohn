# Real SQLite intent/job lifecycle with explicit source and preparation spies.
# This test does not qualify scientific outputs, decimal parsing, native holds,
# report rendering, refusal validation, source-graph extraction or UI behavior.
# Rscript this-file <loader-root> <candidate-root> <fresh-evidence-directory>
args<-commandArgs(TRUE);stopifnot(length(args)==3L)
loader<-normalizePath(args[[1L]],winslash="/",mustWork=TRUE)
candidate<-normalizePath(args[[2L]],winslash="/",mustWork=TRUE)
out<-args[[3L]];stopifnot(!file.exists(out));dir.create(out,recursive=TRUE)
out<-normalizePath(out,winslash="/",mustWork=TRUE)
setwd(loader);source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=FALSE)
for(e in parse(file.path(candidate,"R/platform-report-package.R")))
  if(is.call(e)&&identical(e[[1L]],as.name("<-"))&&is.call(e[[3L]])&&identical(e[[3L]][[1L]],as.name("function")))eval(e,envir=.GlobalEnv)
source(file.path(candidate,"R/platform-report-package-preparation.R"),encoding="UTF-8")
source(file.path(candidate,"R/platform-report-package-authority.R"),encoding="UTF-8")
checks<-list()
check<-function(label,value){checks[[length(checks)+1L]]<<-list(label=label,passed=isTRUE(value));cat(if(isTRUE(value))"PASS"else"FAIL",label,"\n");if(!isTRUE(value))stop(label)}
reject<-function(expr)tryCatch({force(expr);FALSE},error=function(e)TRUE)
spy<-new.env();spy$ready<-list();spy$queues<-0L;spy$resolves<-0L;spy$graph_suffix<-"original";spy$metadata<-list()
implementation<-function(profile)list(profile=profile,hash=brohn_hash(list("lifecycle-boundary-fixture",profile)))
brohn_eda_display_implementation_ref<-function()implementation("saved-eda-display/0.1")
brohn_validate_eda_refusal<-function(refusal)invisible(TRUE)
brohn_task_display_implementation_ref<-function(preparation_profile="saved-task-display/0.1")implementation(preparation_profile)
brohn_choice_display_implementation_ref<-function()implementation("saved-choice-display/0.1")
.brohn_rpk_distribution_implementation_ref<-function(source_admission="task-findings/0.1"){
  stopifnot(source_admission %in% c("task-findings/0.1","task-choice-findings/0.1"))
  implementation(if(source_admission=="task-choice-findings/0.1")"saved-explicit-distribution/0.2"else"saved-explicit-distribution/0.1")
}
.brohn_rpk_renderer_implementation_ref<-function()implementation("static-complete-findings/0.1")
brohn_report_package_eda_limits<-function(){x<-brohn_report_package_limits();x$profile<-"controlled-task-choice-eda-report-package/0.1";x}
brohn_report_source_admission<-function(profile)switch(profile,
  "controlled-gaze-explicit-task-choice-eda-paired/0.1"="task-choice-eda-findings/0.1",
  "controlled-gaze-explicit-task-choice-paired/0.1"="task-choice-findings/0.1",
  "controlled-gaze-explicit-task-paired/0.1"="task-findings/0.1",
  "controlled-gaze-explicit-paired/0.1"="gaze-explicit-paired-findings/0.1",stop("unknown renderer"))
# Identity-only normalization spy: test inputs are already canonical decimals.
brohn_normalize_eda_display_request<-function(request=NULL){
  if(is.null(request))return(list(schema="brohn-eda-display-request/0.1",continuous_windows=list()))
  brohn_fields(request,c("schema","continuous_windows"));stopifnot(request$schema=="brohn-eda-display-request/0.1",brohn_array(request$continuous_windows));request
}
meta<-.brohn_rpk_report_metadata
.brohn_rpk_report_metadata<-function(store,ref){m<-meta(store,ref);extra<-spy$metadata[[brohn_hash(ref)]];for(k in names(extra))m[k]<-extra[k];m}
.brohn_rpk_selection_sources<-function(store,selection)list(report_refs=selection$report_refs,prepared_sources=selection$prepared_sources)
.brohn_rpk_eda_section<-function(section)invisible(section)
brohn_eda_display_catalog<-function(store,display_ref,cursor=NULL,limit=25L)list(items=list(list(key=brohn_hash("catalog-cell"))),next_cursor=NULL)
brohn_resolve_eda_report_section<-function(section,catalog){spy$resolves<-spy$resolves+1L;section$resolved_models<-catalog;list(section=section,panel_count=1L)}
.brohn_rpk_group_ids<-function(store,ref,selector)list("response-fixture")
.brohn_rpk_explicit_panel_count<-function(store,section)1L
key<-function(kind,ref,request=NULL)brohn_hash(list(kind=kind,ref=ref,display_request=request))
prepare_request<-function(kind,ref,impl,display_request=NULL,admission=NULL){
  r<-list(project_id=ref$project_id,report_ref=ref,implementation_ref=impl,display_request=display_request,admission=admission)
  r$content_fingerprint<-brohn_hash(r);r
}
.brohn_eda_display_request<-function(store,report_ref,display_request=NULL,implementation_ref=NULL)
  prepare_request("eda_display",report_ref,implementation_ref,brohn_normalize_eda_display_request(display_request))
brohn_find_eda_display<-function(store,report_ref,display_request=NULL,preparation_profile="saved-eda-display/0.1",implementation_ref=brohn_eda_display_implementation_ref()){
  stopifnot(preparation_profile==implementation_ref$profile)
  spy$ready[[key("eda_display",report_ref,brohn_normalize_eda_display_request(display_request))]]
}
enqueue<-function(store,kind,r,retry){
  old<-.brohn_rpk_latest_job(store,kind,r$content_fingerprint)
  if(!is.null(old)&&(!retry||old$status %in% c("queued","running","succeeded")))return(old)
  spy$queues<-spy$queues+1L;brohn_enqueue_job(store,kind,r,paste0("eda-lifecycle-",spy$queues))
}
brohn_queue_eda_display<-function(store,report_ref,display_request=NULL,retry=FALSE,implementation_ref=NULL)
  enqueue(store,"eda_display",.brohn_eda_display_request(store,report_ref,display_request,implementation_ref),retry)
.brohn_rpk_distribution_request<-function(store,report_ref,implementation_ref=NULL,source_admission=NULL){
  stopifnot(identical(source_admission,"task-choice-findings/0.1"));r<-prepare_request("explicit_distributions",report_ref,implementation_ref,admission=source_admission);r$content_fingerprint<-NULL;r
}
.brohn_rpk_find_pinned_distribution<-function(store,report_ref,implementation_ref,source_admission){
  stopifnot(source_admission=="task-choice-findings/0.1");spy$ready[[key("explicit_distributions",report_ref)]]
}
brohn_queue_explicit_distributions_ref<-function(store,report_ref,retry=FALSE,implementation_ref=NULL,source_admission=NULL){
  r<-.brohn_rpk_distribution_request(store,report_ref,implementation_ref,source_admission);r$content_fingerprint<-brohn_hash(r)
  enqueue(store,"explicit_distributions",r,retry)
}
store<-brohn_open_store(file.path(out,"store"))
invisible(brohn_put_entity(store,"project","default",list(id="default",title="EDA lifecycle boundary fixture",archived=FALSE)))
design<-brohn_new_design("EDA lifecycle boundary fixture","survey","study-eda-lifecycle")
invisible(brohn_put_entity(store,"study",design$id,design))
source_ref<-function(id,kind,family=NULL,existing=NULL){
  body<-list(id=id,study_id=design$id,title=id,origin="sample",analysis=list(kind=kind),provenance=list(design=design,design_hash=brohn_hash(design)))
  r<-.brohn_rpk_ref(brohn_put_entity(store,"report",id,body,if(is.null(existing))0L else existing$revision,"default"))
  spy$metadata[[brohn_hash(r)]]<-list(source_components=as.list(if(kind=="eda")"eda"else if(kind=="questionnaire")"explicit"else"paired"),eda_source_family=family)
  r
}
continuous<-source_ref("report-continuous-fixture","eda","continuous")
event<-source_ref("report-event-fixture","eda","event")
liking<-source_ref("report-liking-fixture","questionnaire")
pair<-source_ref("report-pair-fixture","multimodal")
# Graph extraction is an explicit fixture boundary; exact persistence is real.
.brohn_rpk_eda_requirements<-function(store,report_refs,source_admission){
  stopifnot(source_admission=="task-choice-eda-findings/0.1")
  direct<-Filter(function(r)!is.null(spy$metadata[[brohn_hash(r)]]$eda_source_family),report_refs)
  roots<-Filter(function(r).brohn_rpk_same(r,pair),report_refs)
  related<-if(length(roots)&&!any(vapply(direct,function(r).brohn_rpk_same(r,continuous),logical(1))))list(list(source_ordinal=length(report_refs)+1L,report_ref=continuous,required_by=roots,parent_edges=list()))else list()
  graph<-list(schema="brohn-report-source-identity-graph/0.1",root_refs=report_refs,nodes=list(),edges=list(),fixture_version=spy$graph_suffix)
  list(required_eda_refs=c(direct,lapply(related,`[[`,"report_ref")),related_eda_refs=related,source_identity_graph_binding=graph)
}
section<-function(ref,adapter="eda-continuous",order=1L)list(id=paste0("section-",order),adapter=adapter,adapter_version="0.1",source_report_ref=ref,
  selector=list(scope=if(adapter=="explicit-distribution")"all_groups"else"all_cells"),
  display=if(adapter=="explicit-distribution")list(pages="all")else list(components=list("phasic_us"),pages="all",page_numbers=list(),marker_pages=list(pages="all",page_numbers=list())),order=order)
request<-function(refs=list(continuous,liking),sections=list(section(continuous),section(liking,"explicit-distribution",2L)),windows=list())
  list(schema="brohn-report-package-intent-request/0.1",study_id=design$id,project_id="default",title="EDA lifecycle fixture",report_refs=refs,requested_sections=sections,
    eda_display_requests=windows,contents_policy=list(profile="complete-findings/0.1",audience="research_team",identifier_mode="package_aliases",stimulus_images="excluded_by_choice",complete_selected_numerical_evidence=TRUE,include_original_evidence=FALSE,include_raw_recordings=FALSE),
    limits_profile="controlled-task-choice-eda-report-package/0.1",renderer_profile="controlled-gaze-explicit-task-choice-eda-paired/0.1")
create<-function(id,r=request())brohn_save_report_package_intent(store,id,r)
ready<-function(dep){r<-.brohn_rpk_ref(brohn_put_entity(store,dep$kind,brohn_id("prepared-fixture"),list(schema="explicit-lifecycle-boundary",source=dep$report_ref),0L,"default"))
  spy$ready[[key(dep$kind,dep$report_ref,dep$display_request)]]<-r
}
a<-create("first");body<-brohn_get_entity(store,"report_package_intent",a$intent_ref$id)$body;plan<-body$execution_plan
check("Save pins EDA plan and source requirements before queuing",a$status=="prepared"&&spy$queues==0L&&plan$schema=="brohn-eda-report-execution-plan/0.1"&&length(body$source_requirements$required_eda_refs)==1L)
check("Plan reuses exact task choice and distribution family versions",plan$task_display_implementation_ref$profile=="saved-task-display/0.2"&&plan$choice_display_implementation_ref$profile=="saved-choice-display/0.1"&&plan$explicit_distribution_implementation_ref$profile=="saved-explicit-distribution/0.2"&&plan$eda_display_implementation_ref$profile=="saved-eda-display/0.1")
check("Duplicate command retains exact intent and source snapshot",.brohn_rpk_same(a$intent_ref,create("first")$intent_ref)&&spy$queues==0L)
bad<-plan;bad$source_admission<-"task-choice-findings/0.1"
check("EDA execution plan cannot lower source admission",reject(.brohn_rpk_plan_valid(bad,request())))
bad<-plan;bad$eda_display_implementation_ref<-NULL
check("EDA plan requires its own pinned implementation",reject(.brohn_rpk_plan_valid(bad,request())))
old<-request(list(liking),list(section(liking,"explicit-distribution")));old$renderer_profile<-"controlled-gaze-explicit-task-choice-paired/0.1";old$limits_profile<-"controlled-task-choice-report-package/0.1"
check("Earlier profiles reject EDA sidecar fields",reject(create("old-fields",old)))
old$eda_display_requests<-NULL;old$report_refs<-list(continuous);old$requested_sections<-list(section(continuous))
check("Earlier profiles refuse direct EDA even before queuing",reject(create("old-eda",old)))
a<-brohn_continue_report_package_intent(store,a$intent_ref)
check("Mixed EDA and liking creates only exact display prerequisites",a$status=="waiting_for_display"&&identical(vapply(a$dependencies,`[[`,character(1),"kind"),c("eda_display","explicit_distributions")))
b<-create("shared");b<-brohn_continue_report_package_intent(store,b$intent_ref)
check("Second intent shares exact source-window jobs",spy$queues==2L&&all(!vapply(b$dependencies,`[[`,logical(1),"created_for_intent")))
a<-brohn_cancel_report_package_intent(store,a$intent_ref)
check("Cancelling one owner preserves another intent's EDA prerequisite",all(vapply(b$dependencies,function(d)brohn_get_job(store,d$job_id)$status=="queued",logical(1))))
invisible(lapply(b$dependencies,ready));b<-brohn_continue_report_package_intent(store,b$intent_ref)
selection<-brohn_get_entity(store,"report_package_selection",b$selection_ref$id)$body
check("Ready sources freeze new selection with complete graph and windows",b$status=="assembly_queued"&&selection$schema=="brohn-report-package-selection/0.3"&&identical(selection$eda_display_requests,list())&&.brohn_rpk_same(selection$source_identity_graph_binding,body$source_requirements$source_identity_graph_binding))
check("Prepared source tags and manifest include exact EDA ref",identical(selection$prepared_sources[[1L]]$adapter,"eda-display")&&length(.brohn_rpk_manifest_sources(selection)$eda_displays)==1L)
frozen<-b$selection_ref;counts<-c(spy$queues,spy$resolves);b<-brohn_cancel_report_package_intent(store,b$intent_ref);b<-brohn_continue_report_package_intent(store,b$intent_ref,"retry")
check("Assembly retry preserves exact selection without new display jobs",.brohn_rpk_same(frozen,b$selection_ref)&&identical(counts,c(spy$queues,spy$resolves)))
hidden<-create("evidence-only",request(list(continuous),list()));hidden<-brohn_continue_report_package_intent(store,hidden$intent_ref)
hs<-brohn_get_entity(store,"report_package_selection",hidden$selection_ref$id)$body
check("Zero figures still binds complete EDA preparation",hidden$status=="assembly_queued"&&length(hidden$dependencies)==1L&&!length(hs$sections)&&hidden$preparation$resolved_panel_count==0L)
related<-create("related-only",request(list(pair),list()));related<-brohn_continue_report_package_intent(store,related$intent_ref)
rs<-brohn_get_entity(store,"report_package_selection",related$selection_ref$id)$body
check("Paired-only selection prepares required EDA without automatic figures",related$status=="assembly_queued"&&length(related$dependencies)==1L&&.brohn_rpk_same(related$dependencies[[1L]]$report_ref,continuous)&&length(rs$related_eda_refs)==1L&&!length(rs$sections))
both<-create("parent-selected",request(list(pair,continuous),list()));both<-brohn_continue_report_package_intent(store,both$intent_ref)
check("Selected and required EDA source has one prerequisite",length(both$dependencies)==1L&&!length(brohn_get_entity(store,"report_package_selection",both$selection_ref$id)$body$related_eda_refs))
w<-list(schema="brohn-eda-display-request/0.1",continuous_windows=list(list(key=brohn_hash("continuous-cell"),start_s="1",end_s="2")))
windows<-list(list(report_ref=continuous,display_request=w))
focus<-create("focused",request(list(continuous),list(section(continuous)),windows));focus<-brohn_continue_report_package_intent(store,focus$intent_ref)
check("Changed continuous window queues distinct display job",focus$status=="waiting_for_display"&&spy$queues==3L&&!identical(focus$dependencies[[1L]]$job_id,a$dependencies[[1L]]$job_id))
same<-create("focused-hidden",request(list(continuous),list(),windows));same<-brohn_continue_report_package_intent(store,same$intent_ref)
check("Hiding focused figures preserves window and shares job",spy$queues==3L&&identical(same$dependencies[[1L]]$job_id,focus$dependencies[[1L]]$job_id)&&.brohn_rpk_same(same$request$eda_display_requests,windows))
check("Duplicate window source is refused",reject(create("duplicate-windows",request(list(continuous),list(),c(windows,windows)))))
check("Window request on a foreign source is refused",reject(create("foreign-window",request(list(event),list(),windows))))
check("Event method windows cannot acquire a continuous override",reject(create("event-window",request(list(event),list(),list(list(report_ref=event,display_request=w))))))
check("Explicit default request collapses to empty sidecar",identical(.brohn_rpk_normalize_eda_requests(list(list(report_ref=continuous,display_request=brohn_normalize_eda_display_request())),list(continuous)),list()))
drift<-create("source-drift",request(list(pair),list()));before<-spy$queues;spy$graph_suffix<-"changed"
check("Changed source closure refuses before queuing or rebinding",reject(brohn_continue_report_package_intent(store,drift$intent_ref))&&spy$queues==before&&brohn_get_entity(store,"report_package_intent",drift$intent_ref$id)$body$source_requirements$source_identity_graph_binding$fixture_version=="original")
spy$graph_suffix<-"original"
new_revision<-source_ref(continuous$id,"eda","continuous",continuous)
revision_request<-request(list(continuous,new_revision),list())
revision_plan<-.brohn_rpk_execution_plan(revision_request)
specs<-.brohn_rpk_task_dependency_specs(store,revision_request,revision_plan)
check("Equal bodies at different revisions retain distinct dependency slots",continuous$body_hash==new_revision$body_hash&&length(specs)==2L&&!identical(specs[[1L]]$slot,specs[[2L]]$slot))
check("EDA job authority names exact operation",brohn_report_package_queue_authority(store,"eda_display","default")$operation=="eda_display")
target<-focus$dependencies[[1L]]$job_id
repeat{
  claimed<-brohn_claim_job(store,"lifecycle-refusal-fixture",lease_seconds=3600)
  stopifnot(!is.null(claimed))
  if(claimed$id==target)break
}
failure<-list(schema="brohn-eda-report-refusal/0.1",reason_code="window_sample_limit",source=continuous,
  resource="window_samples",measured=500001,maximum=500000,recovery_scope="smaller_window",
  message="This saved display window exceeds the sample limit. Choose a smaller display window.")
invisible(brohn_fail_job(store,claimed$id,claimed$worker,claimed$token,c(failure,list(source_preserved=TRUE))))
focus<-brohn_continue_report_package_intent(store,focus$intent_ref)
check("Typed display refusal survives job-to-intent recovery metadata",focus$status=="failed"&&focus$preparation$reason_code==failure$reason_code&&
  .brohn_rpk_same(focus$preparation$source,continuous)&&focus$preparation$measured==500001&&focus$preparation$maximum==500000&&focus$preparation$recovery_scope=="smaller_window")
check("Refused preparation retains exact requested window and original dependency",.brohn_rpk_same(focus$request$eda_display_requests,windows)&&identical(focus$dependencies[[1L]]$job_id,target)&&is.null(focus$selection_ref))
ordinary<-.brohn_rpk_preparation_failure(focus$dependencies,list(error=list(message="Temporary worker timeout")),focus$preparation)
check("A later ordinary error cannot inherit an earlier limit diagnosis",is.null(ordinary$reason_code)&&is.null(ordinary$source)&&is.null(ordinary$resource)&&is.null(ordinary$measured)&&is.null(ordinary$maximum)&&is.null(ordinary$recovery_scope))
before<-spy$queues;focus<-brohn_continue_report_package_intent(store,focus$intent_ref,"retry")
check("Explicit retry creates one new attempt with unchanged source-window request",focus$status=="waiting_for_display"&&spy$queues==before+1L&&
  !identical(focus$dependencies[[1L]]$job_id,target)&&.brohn_rpk_same(focus$dependencies[[1L]]$display_request,w))
jobs<-DBI::dbGetQuery(store$con,"SELECT id FROM jobs WHERE status IN ('queued','running')")
for(id in jobs$id)invisible(brohn_cancel_job(store,id))
brohn_close_store(store)
files<-c("R/platform-report-package.R","R/platform-report-package-preparation.R","R/platform-report-package-authority.R")
brohn_write_json_file(list(schema="brohn-eda-root-lifecycle-checks/0.1",scope="Real SQLite lifecycle with explicit source graph, normalization, refusal validator, display, authority-source and renderer boundary spies; not scientific, native-worker, export or UI acceptance",checks=checks,
  source_hashes=setNames(lapply(files,function(p)digest::digest(file=file.path(candidate,p),algo="sha256")),files)),file.path(out,"results.json"))
cat(length(checks),"lifecycle checks passed\n")
