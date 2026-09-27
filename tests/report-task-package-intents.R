# Isolated intent/storage contract. Real SQLite intents/jobs; explicit source,
# implementation and renderer spies. Not task-display/scientific acceptance.
# Rscript tests/report-task-package-intents.R <checkout> <fresh-evidence>
# During integration: <loader-checkout> <candidate-checkout> <fresh-evidence>
args<-commandArgs(TRUE);stopifnot(length(args)%in%c(2L,3L))
loader<-normalizePath(args[[1]],winslash="/",mustWork=TRUE)
candidate<-normalizePath(if(length(args)==3L)args[[2]]else args[[1]],winslash="/",mustWork=TRUE)
out<-args[[length(args)]];stopifnot(!file.exists(out));dir.create(out,recursive=TRUE);out<-normalizePath(out,winslash="/",mustWork=TRUE)
setwd(loader);source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=FALSE)
# Exercise the candidate function definitions with the stable loader. New
# cross-module code identities are qualified later in the integrated checkout.
for(p in c("platform-report-package.R","platform-report-package-distributions.R"))for(e in parse(file.path(candidate,"R",p)))
  if(is.call(e)&&identical(e[[1L]],as.name("<-"))&&is.call(e[[3L]])&&identical(e[[3L]][[1L]],as.name("function")))eval(e,envir=.GlobalEnv)
source(file.path(candidate,"R/platform-report-package-preparation.R"),encoding="UTF-8")
checks<-list();check<-function(label,value){checks[[length(checks)+1L]]<<-list(label=label,passed=isTRUE(value));cat(if(isTRUE(value))"PASS"else"FAIL",label,"\n");if(!isTRUE(value))stop(label)}
reject<-function(expr)tryCatch({force(expr);FALSE},error=function(e)TRUE)
spy<-new.env();spy$ready<-list();spy$queues<-0L;spy$resolves<-0L;spy$panels<-2L;spy$renderer<-brohn_hash("fixture-renderer-1")
impl<-list(profile="saved-task-display/0.1",hash=brohn_hash("fixture-task-code"))
brohn_task_display_implementation_ref<-function()impl
.brohn_rpk_renderer_implementation_ref<-function()list(profile="static-complete-findings/0.1",hash=spy$renderer)
brohn_report_package_task_limits<-brohn_report_package_limits
.brohn_task_display_request<-function(store,report_ref,implementation_ref){
  r<-list(report_ref=report_ref,implementation_ref=implementation_ref,project_id=report_ref$project_id)
  r$content_fingerprint<-brohn_hash(r);r
}
brohn_find_task_display<-function(store,report_ref,preparation_profile,implementation_ref){stopifnot(identical(preparation_profile,impl$profile),.brohn_rpk_same(implementation_ref,impl));spy$ready[[report_ref$id]]}
brohn_queue_task_display<-function(store,report_ref,retry=FALSE,implementation_ref=NULL){
  r<-.brohn_task_display_request(store,report_ref,implementation_ref);old<-.brohn_rpk_latest_job(store,"task_display",r$content_fingerprint)
  if(!is.null(old)&&(!retry||old$status %in% c("queued","running","succeeded")))return(old)
  spy$queues<-spy$queues+1L;brohn_enqueue_job(store,"task_display",r,paste0("task-fixture-",spy$queues))
}
.brohn_rpk_selection_sources<-function(store,selection)list(report_refs=selection$report_refs,prepared_sources=selection$prepared_sources)
brohn_task_display_catalog<-function(store,display_ref,cursor=NULL,limit=25L)list(items=list(list(key=brohn_hash("fixture-model"))),next_cursor=NULL)
brohn_resolve_task_report_section<-function(section,catalog){spy$resolves<-spy$resolves+1L
  section$resolved_models<-list(list(key=brohn_hash("fixture-model"),model_hash=brohn_hash("complete-original-model"),measure="first_response_ms",charts=list("chronology","distribution")))
  list(section=section,panel_count=if(section$adapter=="task-scores")0L else spy$panels)
}
store<-brohn_open_store(file.path(out,"store"))
invisible(brohn_put_entity(store,"project","default",list(id="default",title="Fixture research",archived=FALSE)))
design<-brohn_new_design("Intent contract fixture","survey","study-intent-fixture");invisible(brohn_put_entity(store,"study",design$id,design))
source_ref<-function(id,kind="questionnaire"){
  body<-list(id=id,study_id=design$id,title=id,origin="sample",analysis=list(kind=kind,task_scores=list(list(profile="fixture"))),
    provenance=list(design=design,design_hash=brohn_hash(design)))
  .brohn_rpk_ref(brohn_put_entity(store,"report",id,body,0L,"default"))
}
native<-source_ref("report-native-fixture");imported<-source_ref("report-import-fixture","implicit")
section<-function(ref,id="task-section",adapter="task-trials",order=1L)list(id=id,adapter=adapter,adapter_version="0.1",source_report_ref=ref,
  selector=list(scope="all_administrations"),display=if(adapter=="task-scores")list(pages="all")else list(measure="profile_default",trial_scope="all",charts="profile_default",pages="all"),order=order)
request<-function(refs=list(native),sections=list(section(native)))list(schema="brohn-report-package-intent-request/0.1",study_id=design$id,project_id="default",title="Saved intent fixture",
  report_refs=refs,requested_sections=sections,contents_policy=list(profile="complete-findings/0.1",audience="research_team",identifier_mode="package_aliases",stimulus_images="excluded_by_choice",
    complete_selected_numerical_evidence=TRUE,include_original_evidence=FALSE,include_raw_recordings=FALSE),limits_profile="controlled-task-report-package/0.1",renderer_profile="controlled-gaze-explicit-task-paired/0.1")
create<-function(command,req=request(),prior=NULL)brohn_save_report_package_intent(store,command,req,if(is.null(prior))NULL else prior$revision,prior)
ready<-function(ref){spy$ready[[ref$id]]<-.brohn_rpk_ref(brohn_put_entity(store,"task_display",paste0("display-",ref$id),list(schema="fixture-display",source_ref=ref),0L,"default"))}
a<-create("first");record<-brohn_get_entity(store,"report_package_intent",a$intent_ref$id)
check("one explicit Prepare persists a server-authored plan before any job",a$status=="prepared"&&spy$queues==0L&&!is.null(record$body$execution_plan))
plan<-record$body$execution_plan;again<-create("first")
check("duplicate command retains the same original plan and intent",identical(a$intent_ref,again$intent_ref)&&.brohn_rpk_same(plan,brohn_get_entity(store,"report_package_intent",a$intent_ref$id)$body$execution_plan))
bad<-request();bad$execution_plan<-plan
check("client cannot supply a replacement execution plan",reject(create("malicious-plan",bad)))
bad<-request();bad$renderer_profile<-"controlled-gaze-explicit-paired/0.1";bad$limits_profile<-"controlled-report-package/0.1"
check("old request profile cannot enable task sections",reject(create("old-profile-task",bad)))
bad<-section(native);bad$display$pages<-"selected";bad$display$page_numbers<-list(1L,1L)
check("duplicate numerical pages rejected before any source work",reject(.brohn_rpk_task_section(bad)))
bad<-section(native);bad$display$charts<-list("people")
check("trial charts cannot accept cohort-only people",reject(.brohn_rpk_task_section(bad)))
a<-brohn_continue_report_package_intent(store,a$intent_ref)
check("first continuation queues one genuine durable task job",a$status=="waiting_for_display"&&spy$queues==1L&&a$dependencies[[1]]$created_for_intent)
b<-create("shared");b<-brohn_continue_report_package_intent(store,b$intent_ref)
check("a second intent reuses the job without claiming cancellation ownership",spy$queues==1L&&!b$dependencies[[1]]$created_for_intent&&identical(a$dependencies[[1]]$job_id,b$dependencies[[1]]$job_id))
a<-brohn_cancel_report_package_intent(store,a$intent_ref)
check("cancelling owning intent preserves another active user's shared job",brohn_get_job(store,b$dependencies[[1]]$job_id)$status=="queued")
ready(native);b<-brohn_continue_report_package_intent(store,b$intent_ref)
frozen<-brohn_get_entity(store,"report_package_selection",b$selection_ref$id)$body
check("ready task evidence freezes version0.2 and queues assembly",b$status=="assembly_queued"&&identical(frozen$schema,"brohn-report-package-selection/0.2")&&is.null(frozen$display_refs))
check("frozen selection preserves requested defaults beside exact model resolution",identical(frozen$sections[[1]]$display$measure,"profile_default")&&length(frozen$sections[[1]]$resolved_models)==1L)
check("successful preparation metadata remains available for recovery",length(b$preparation$prepared_sources)==1L&&b$preparation$resolved_panel_count==2L)
selection_ref<-b$selection_ref;queues<-spy$queues;resolved_count<-spy$resolves
b<-brohn_cancel_report_package_intent(store,b$intent_ref);b<-brohn_continue_report_package_intent(store,b$intent_ref,"retry")
check("assembly retry retains the same selection without preparation or resolution",.brohn_rpk_same(selection_ref,b$selection_ref)&&spy$queues==queues&&spy$resolves==resolved_count)
spy$panels<-101L;c<-create("over-limit");c<-brohn_continue_report_package_intent(store,c$intent_ref)
check("known figure limit becomes review before assembly",c$status=="needs_attention"&&c$next_action=="review"&&is.null(c$selection_ref)&&identical(c$preparation$reason_code,"panel_limit"))
check("limit refusal retains the exact prepared source and original request",length(c$preparation$prepared_sources)==1L&&c$preparation$resolved_panel_count==101L&&.brohn_rpk_same(c$request,request()))
spy$panels<-2L;reduced<-request(sections=list(section(native,adapter="task-scores")))
d<-create("reduced",reduced,c$intent_ref);d<-brohn_continue_report_package_intent(store,d$intent_ref)
check("changed figures reuse preparation and retain full task source",d$status=="assembly_queued"&&spy$queues==queues&&d$preparation$resolved_panel_count==0L&&length(d$preparation$prepared_sources)==1L)
check("edited intent supersedes the previous review version",brohn_get_entity(store,"report_package_intent",c$intent_ref$id)$body$status=="superseded")
e<-create("code-change");saved_plan<-brohn_get_entity(store,"report_package_intent",e$intent_ref$id)$body$execution_plan
spy$renderer<-brohn_hash("fixture-renderer-2");e<-brohn_continue_report_package_intent(store,e$intent_ref)
check("code drift becomes explicit review without enqueuing",e$status=="needs_attention"&&e$next_action=="review"&&spy$queues==queues&&e$preparation$reason_code=="implementation_changed")
check("code drift never rewrites the originally pinned plan",.brohn_rpk_same(saved_plan,brohn_get_entity(store,"report_package_intent",e$intent_ref$id)$body$execution_plan))
f<-create("new-code-version",request(),e$intent_ref)
check("explicit new version captures the new server implementation",!identical(saved_plan$renderer_implementation_ref$hash,brohn_get_entity(store,"report_package_intent",f$intent_ref$id)$body$execution_plan$renderer_implementation_ref$hash))
g<-create("hidden-figures",request(list(native,imported),list(section(native,adapter="task-scores"))))
g<-brohn_continue_report_package_intent(store,g$intent_ref)
check("task report without figures still requires complete prepared evidence",g$status=="waiting_for_display"&&length(g$dependencies)==2L&&spy$queues==queues+1L)
check("prepared dependency order follows selected report order",identical(vapply(g$dependencies,function(x)x$report_ref$id,character(1)),c(native$id,imported$id)))
resolver<-brohn_resolve_task_report_section
brohn_resolve_task_report_section<-function(...)stop("The exact selected numerical page is unavailable.")
x<-create("invalid-resolved-choice");x<-brohn_continue_report_package_intent(store,x$intent_ref)
check("resolved selection refusal is durable review instead of an auto-advance loop",x$status=="needs_attention"&&x$preparation$reason_code=="selection_review")
check("selection refusal retains completed exact catalogs",length(x$preparation$prepared_sources)==1L&&is.null(x$selection_ref))
brohn_resolve_task_report_section<-resolver
# Cancel only this isolated fixture's pending work so the next actual lease is
# the deliberately tested assembly. No participant/source work executes here.
pending<-DBI::dbGetQuery(store$con,"SELECT id FROM jobs WHERE status IN ('queued','running')")
for(id in pending$id)invisible(brohn_cancel_job(store,id))
paired<-list(id="paired-section",adapter="paired-findings",adapter_version="0.1",source_report_ref=native,
  selector=list(scope="all_comparisons"),display=list(charts=list("means"),pages="all"),order=2L)
h<-create("worker-preflight",request(sections=list(section(native),paired)));h<-brohn_continue_report_package_intent(store,h$intent_ref)
check("unknown heterogeneous panel count stays unknown until supervised preflight",h$status=="assembly_queued"&&is.null(h$preparation$resolved_panel_count))
job<-brohn_claim_job(store,"fixture-preflight-publisher",lease_seconds=120)
stopifnot(identical(job$id,h$job_ref$id))
hs<-brohn_get_entity(store,"report_package_selection",h$selection_ref$id)$body
input<-list(selection_ref=h$selection_ref,limits=brohn_report_package_task_limits(),source_binding=brohn_hash(.brohn_rpk_selection_sources(store,hs)))
refusal<-list(schema="brohn-report-package-refusal/0.1",reason_code="panel_limit",resolved_panel_count=101L,maximum_panels=input$limits$max_panels,
  section_counts=list(list(section_id="task-section",panel_count=2L),list(section_id="paired-section",panel_count=99L)))
original_guard_check<-.brohn_cm_guard_check;.brohn_cm_guard_check<-function(guards)invisible(TRUE)
result<-.brohn_rpk_publish_panel_refusal(store,refusal,job,input,hs,list(),NULL)
.brohn_cm_guard_check<-original_guard_check
hr<-brohn_get_entity(store,"report_package_intent",h$intent_ref$id)$body
check("worker panel refusal atomically fails real assembly and saves review state",result$status=="failed"&&result$error$reason_code=="panel_limit"&&hr$status=="needs_attention")
check("worker refusal preserves frozen selection and exact prepared references",.brohn_rpk_same(hr$selection_ref,h$selection_ref)&&length(hr$preparation$prepared_sources)==1L&&hr$preparation$resolved_panel_count==101L)
check("worker refusal creates no successful report package",DBI::dbGetQuery(store$con,"SELECT count(*) n FROM entities WHERE kind='report_package'")$n[[1]]==0L)
brohn_close_store(store)
record<-list(schema="brohn-root-preparation-contract/0.1",scope="Real SQLite intents/jobs with explicit source/model/implementation spies; not integrated worker or scientific qualification",checks=checks,
  files=setNames(lapply(c("R/platform-report-package.R","R/platform-report-package-preparation.R","R/platform-report-package-distributions.R"),function(p)digest::digest(file=file.path(candidate,p),algo="sha256")),c("R/platform-report-package.R","R/platform-report-package-preparation.R","R/platform-report-package-distributions.R")))
brohn_write_json_file(record,file.path(out,"results.json"));cat(length(checks),"checks passed\n")
