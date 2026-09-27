# Portable Shiny controller contract tests using explicit in-memory backend spies.
# Rscript tests/report-task-package-ui-state.R <source-root> <fresh-evidence-directory>
# External packet alternative: <packet-directory> <fresh-evidence-directory> <loader-root>
args<-commandArgs(TRUE);stopifnot(length(args)%in%c(2L,3L))
root<-normalizePath(args[[1]],winslash="/",mustWork=TRUE)
loader<-if(length(args)==3L)normalizePath(args[[3]],winslash="/",mustWork=TRUE)else root
candidate<-if(file.exists(file.path(root,"R","platform-report-package-server.R")))file.path(root,"R")else root
stopifnot(file.exists(file.path(loader,"R","platform-load.R")))
folder<-args[[2]];stopifnot(!file.exists(folder));dir.create(folder,recursive=TRUE)
folder<-normalizePath(folder,winslash="/",mustWork=TRUE)
setwd(loader);source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=TRUE)
for(f in c("platform-report-package-views.R","platform-report-package-server.R"))source(file.path(candidate,f),encoding="UTF-8")
checks<-list();scenarios<-list();check<-function(ok,label){checks[[length(checks)+1L]]<<-list(label=label,passed=isTRUE(ok));cat(if(isTRUE(ok))"PASS"else"FAIL",label,"\n");if(!isTRUE(ok))stop(label,call.=FALSE)}
mock<-new.env();mock$intents<-list();mock$saves<-0L;mock$advances<-0L;mock$opens<-0L;mock$releases<-0L;mock$authority<-TRUE;mock$reader<-TRUE;mock$session_checks<-0L;mock$current_reads<-0L;mock$cancels<-0L;mock$lookups<-list()
ref<-function(id,kind="report",revision=1L)list(kind=kind,id=id,revision=revision,body_hash=brohn_hash(list(id,revision)),project_id="default")
rows<-list(list(ref=ref("gaze-original"),title="Saved controlled gaze",origin="sample",kind="gaze",design_hash="design-old",adapters=list("gaze-context","paired-findings"),status="available",reason=NULL),
 list(ref=ref("liking-original"),title="Saved explicit liking",origin="sample",kind="questionnaire",design_hash="design-old",adapters=list("explicit-distribution","paired-findings"),status="available",reason=NULL),
 list(ref=ref("gaze-history",revision=2L),title="Earlier gaze report",origin="sample",kind="gaze",design_hash="design-older",adapters=list("gaze-context"),status="available",reason=NULL),
 list(ref=ref("combined-original"),title="Reviewed combined report",origin="sample",kind="multimodal",design_hash="design-older",adapters=list("paired-findings"),status="available",reason=NULL))
mock$recommendations<-list()
brohn_hosted_require_session<-function(store){mock$session_checks<-mock$session_checks+1L;stopifnot(mock$reader)}
brohn_report_package_choices<-function(store,study_id,project_id,cursor=NULL,limit=25L)list(study=list(id=study_id,title="Original packaging study",project_id=project_id),reports=if(is.null(cursor))rows[1:2]else rows[3],cursor=cursor,next_cursor=if(is.null(cursor))"page2"else NULL,recommended_refs=lapply(rows[1:2],`[[`,"ref"),needs_choice=FALSE)
brohn_report_package_report_choice<-function(store,report_ref){mock$lookups<-c(mock$lookups,list(report_ref));found<-Filter(function(r).brohn_rpv_same(r$ref,report_ref),rows);stopifnot(length(found)==1L);row<-found[[1]]
 recommendation<-mock$recommendations[[row$ref$id]];row$recommended_refs<-if(is.null(recommendation))list(row$ref)else recommendation$refs
 row$recommendation_reason<-if(is.null(recommendation))NULL else recommendation$reason;row}
brohn_report_package_selector_catalog<-function(store,report_ref,adapter,cursor=NULL,limit=25L){n<-if(is.null(cursor))1L else 14L
 selector<-switch(adapter,`gaze-context`=list(scope="exact_exposure",exposure_key=paste0("exposure-",n)),
  `paired-findings`=list(scope="exact_comparison",comparison_id="comparison-1",contrast_hash=brohn_hash("saved-contrast")),
  `explicit-distribution`=list(scope="exact_item_condition",family="question",item_id="liking",condition_id=NULL))
 list(report_ref=report_ref,adapter=adapter,items=list(list(selector=selector,label=paste("Saved view",n),details="Original saved context")),cursor=cursor,next_cursor=if(is.null(cursor))"page2"else NULL,requires_display_preparation=adapter=="explicit-distribution")}
brohn_save_report_package_intent<-function(store,command_id,request,expected_revision=NULL,prior_intent_ref=NULL){
 stopifnot(mock$authority);existing<-Filter(function(i)identical(i$command_id,command_id),mock$intents)
 if(length(existing)){stopifnot(.brohn_rpv_same(existing[[1]]$request,request));return(existing[[1]]$view)}
 if(!is.null(prior_intent_ref)){prior<-mock$intents[[prior_intent_ref$id]];stopifnot(prior$view$intent_ref$revision==expected_revision);prior$view$status<-"superseded";prior$view$next_action<-"none";mock$intents[[prior_intent_ref$id]]<-prior}
 mock$saves<-mock$saves+1L;id<-paste0("intent-",mock$saves);v<-list(intent_ref=ref(id,"report_package_intent"),status="prepared",request=request,dependencies=list(),selection_ref=NULL,job_ref=NULL,package_ref=NULL,next_action="continue",reason=NULL)
 mock$intents[[id]]<-list(command_id=command_id,request=request,view=v);v}
brohn_continue_report_package_intent<-function(store,intent_ref,action="advance"){
 stopifnot(mock$authority);mock$advances<-mock$advances+1L;v<-mock$intents[[intent_ref$id]]$view
 if(v$status%in%c("failed","needs_authority","cancelled")){stopifnot(action%in%c("resume","retry"));v$status<-"prepared"}
 if(v$status=="prepared"){v$status<-"waiting_for_display";v$dependencies<-list(list(job_id="display-job"));v$next_action<-"wait"}
 else if(v$status=="ready_to_freeze"){v$status<-"assembly_queued";v$selection_ref<-ref("selection-old","report_package_selection");v$job_ref<-list(id="package-job",status="queued");v$next_action<-"wait"}
 mock$intents[[intent_ref$id]]$view<-v;v}
brohn_read_report_package_intent<-function(store,intent_id,project_id){stopifnot(mock$reader);mock$intents[[intent_id]]$view}
brohn_cancel_report_package_intent<-function(store,intent_ref){mock$cancels<-mock$cancels+1L;v<-mock$intents[[intent_ref$id]]$view;v$status<-"cancelled";v$next_action<-"retry";mock$intents[[intent_ref$id]]$view<-v;v}
brohn_report_package_catalog<-function(store,study_id,project_id,cursor=NULL,limit=25L)list(items=unname(lapply(mock$intents,function(i)list(intent_ref=i$view$intent_ref,status=i$view$status,title=i$request$title,updated_at="2026-09-27",package_ref=i$view$package_ref,reason=NULL))),cursor=cursor,next_cursor=NULL)
artifact_dir<-file.path(folder,"artifacts");dir.create(artifact_dir)
artifacts<-setNames(lapply(c("html","zip","manifest"),function(k){p<-file.path(artifact_dir,paste0(k,".txt"));writeLines(paste("controller fixture",k),p);list(file=basename(p),path=p,hash=digest::digest(file=p,algo="sha256"),bytes=file.info(p)$size,media_type="text/plain")}),c("html","zip","manifest"))
brohn_open_report_package_resources<-function(store,ref,project_id){mock$opens<-mock$opens+1L;stopifnot(mock$reader);h<-new.env();h$closed<-FALSE;h$record<-list(id=ref$id,revision=ref$revision,project_id=project_id,body=list(ref=ref));list(record=h$record,handle=h,manifest=list(),artifacts=artifacts)}
brohn_report_package_resources_current<-function(store,handle){mock$current_reads<-mock$current_reads+1L;stopifnot(mock$reader,!is.null(handle),!handle$closed);list(record=handle$record,artifacts=artifacts)}
brohn_release_report_package_resources<-function(handle){if(!handle$closed){handle$closed<-TRUE;mock$releases<-mock$releases+1L}}
brohn_study<-function(store,id)list(id=id,project_id="default",body=list(title="Study"))
server<-function(input,output,session){state<-shiny::reactiveValues(page="home",study_id=NULL,stage="Plan");current<-new.env();current$study<-NULL;routes<-new.env()
 session$registerDataObj<-function(name,data,filterFunc){routes[[name]]<-list(data=data,filter=filterFunc);paste0("/mock-resource/",name,"?fixture=1")}
 controller<-brohn_install_report_package_server(input,output,session,list(),state,current)}
scenario<-function(label,code){cat("SCENARIO",label,"\n");failure<-NULL
 expr<-substitute(shiny::testServer(server,EXPR),list(EXPR=substitute(code)))
 tryCatch(eval(expr,envir=parent.frame()),error=function(e){failure<<-conditionMessage(e);cat("ERROR",failure,"\n")})
 scenarios[[length(scenarios)+1L]]<<-list(label=label,passed=is.null(failure),failure=failure)}
setup<-quote({
 session$flushReact();session$setInputs(rpk_enter=list(study_id="study",project_id="default",report_ref=NULL))
 bind<-function(){x<-list(rpk_form_identity=controller$state$form_identity,rpk_title=controller$state$draft$title,rpk_source_identifiers=FALSE,rpk_images=FALSE)
  for(s in controller$state$sections){if(s$adapter=="paired-findings")x[[paste0("rpk_charts_",s$id)]]<-unlist(s$display$charts)
   if(s$adapter%in%c("paired-findings","explicit-distribution"))x[[paste0("rpk_pages_",s$id)]]<-""}
  do.call(session$setInputs,x)}
 bind();ack<-function()session$setInputs(rpk_prepare_ack=controller$state$pending$ticket)
 saved<-function()controller$state$intent$intent_ref$id
 set_status<-function(status,action){id<-saved();mock$intents[[id]]$view$status<-status;mock$intents[[id]]$view$next_action<-action
  if(status=="succeeded")mock$intents[[id]]$view$package_ref<-ref(paste0("package-",id),"report_package");session$elapse(1001);session$flushReact()}
 download<-function(url,method="GET"){name<-sub("\\?.*$","",sub("^/mock-resource/","",url));r<-routes[[name]]
  r$filter(r$data,list(REQUEST_METHOD=method,QUERY_STRING=sub("^[^?]*\\?","",url)))}
})
profiles<-c("iat-gnb2003-d1/1.0","biat-nosek2014-goodfocal/1.0","aat-keyboard-cue-balanced/1.0",
 "rt-deary-liewald-simple/1.0","rt-deary-liewald-choice/1.0","sciat-brohn-response-window-im100/1.0","gnat-brohn-single-target/1.0")
catalog<-lapply(seq_along(profiles),function(i)list(key=brohn_hash(paste0("admin-",i)),kind="administration",label=paste("Saved task",i),profile=profiles[[i]],
 completion=if(i==5L)"incomplete"else"completed",metric=NULL,score_index=i,
 compatible_charts=if(i==7L)list("chronology","distribution","outcomes")else list("chronology","distribution"),
 compatible_measures=if(i==7L)list("first_response_ms")else list("first_response_ms","final_correct_ms"),
 default_measure=if(i%in%1:2)"final_correct_ms"else"first_response_ms",expected_positions=40L,
 reason=if(i==5L)"One correct response and 39 omissions; SD unavailable."else NULL))
rows<-list(list(ref=ref("native-task-liking"),title="Native tasks, liking and scales",origin="participant cohort",kind="questionnaire",
 source_family="native_questionnaire",adapters=list("task-scores","task-trials","explicit-distribution","paired-findings"),status="available",reason=NULL),
 list(ref=ref("imported-iat"),title="Imported declared IAT trials",origin="import",kind="implicit",source_family="imported_implicit",adapters=list("task-scores","task-trials"),status="available",reason=NULL),
 list(ref=ref("cohort-original",revision=2L),title="Saved repeated-visit cohort",origin="cohort",kind="implicit_cohort",source_family="saved_task_cohort",adapters=list("task-people"),status="available",reason="Person linkage was not saved; person counts are unknown."))
mock$prepared<-FALSE;mock$catalog_reads<-list();mock$full_reads<-0L
mock$prepared_ref<-ref("task-display-original","task_display",2L)
mock$distribution_ref<-ref("distribution-original","explicit_distributions",2L)
mock$newer_distribution_ref<-ref("distribution-original","explicit_distributions",3L)
brohn_report_package_choices<-function(store,study_id,project_id,cursor=NULL,limit=25L)list(study=list(id=study_id,title="Task and liking study",project_id=project_id),reports=rows,cursor=cursor,next_cursor=NULL,recommended_refs=list(rows[[1]]$ref),needs_choice=FALSE)
base_choice<-brohn_report_package_report_choice
brohn_report_package_report_choice<-function(store,report_ref){stopifnot(is.null(mock$denied_ref)||!identical(mock$denied_ref,report_ref$id));row<-base_choice(store,report_ref);row$task_state<-if(mock$prepared)"ready"else"needs_preparation";row}
brohn_open_task_display_resources<-function(...){mock$full_reads<-mock$full_reads+1L;stop("A complete artifact was opened in the UI")}
brohn_report_package_selector_catalog<-function(store,report_ref,adapter,cursor=NULL,limit=25L,prepared_ref=NULL){
 mock$catalog_reads<-c(mock$catalog_reads,list(list(report_ref=report_ref,adapter=adapter,cursor=cursor,prepared_ref=prepared_ref)))
 if(.brohn_rpv_task_adapter(adapter)){
  available<-mock$prepared||!is.null(prepared_ref)
  if(!is.null(prepared_ref))stopifnot(.brohn_rpv_same(prepared_ref,mock$prepared_ref))
  indices<-if(is.null(cursor))1:6 else 7L
  items<-if(!available)list()else if(adapter=="task-people")list(list(selector=list(scope="exact_metrics",metrics=list("RT_mean_ms")),label="Saved mean response time",details=list(kind="cohort_metric",reason="Person linkage was not saved; counts remain unknown.")))else
    lapply(catalog[indices],function(d)list(selector=list(scope="exact_administrations",keys=list(d$key)),label=d$label,details=d))
  list(report_ref=report_ref,adapter=adapter,items=items,cursor=cursor,next_cursor=if(available&&is.null(cursor)&&adapter!="task-people")"page2"else NULL,
   requires_display_preparation=!available,state=if(available)"ready"else"needs_preparation",prepared_ref=if(available)mock$prepared_ref else NULL,reason=NULL)
 }else if(adapter%in%c("explicit-distribution","paired-findings")){
  available<-mock$prepared||!is.null(prepared_ref)
  old<-!is.null(prepared_ref)
  if(old)stopifnot(.brohn_rpv_same(prepared_ref,if(adapter=="explicit-distribution")mock$distribution_ref else mock$prepared_ref))
  selector<-if(adapter=="explicit-distribution")list(scope="exact_item_condition",family="question",item_id=if(old)"original-liking"else"newer-liking",condition_id=if(is.null(cursor))NULL else"control")else
    list(scope="exact_comparison",comparison_id=if(old)"original-comparison"else"newer-comparison",contrast_hash=brohn_hash(if(old)"old-contrast"else"newer-contrast"))
  list(report_ref=report_ref,adapter=adapter,items=if(available)list(list(selector=selector,label=if(old)"Exact historical view"else"Newer preparation view",details="Bounded saved metadata"))else list(),
   cursor=cursor,next_cursor=if(available&&is.null(cursor))"page2"else NULL,requires_display_preparation=!available,state=if(available)"ready"else"needs_preparation",prepared_ref=prepared_ref)
 }else list(report_ref=report_ref,adapter=adapter,items=list(),cursor=cursor,next_cursor=NULL,requires_display_preparation=TRUE)
}
base_continue<-brohn_continue_report_package_intent
brohn_continue_report_package_intent<-function(store,intent_ref,action="advance"){
 v<-base_continue(store,intent_ref,action)
 if(v$status=="waiting_for_display")v$dependencies<-list(list(kind="task_display",job_id="task",status="running"),list(kind="explicit_distributions",job_id="explicit",status="queued"))
 mock$intents[[intent_ref$id]]$view<-v;v
}
prepared_summary<-function(reason=NULL)list(prepared_sources=list(list(adapter="task-display",source_report_ref=rows[[1]]$ref,prepared_ref=mock$prepared_ref,
 implementation_ref=list(profile="saved-task-display/0.1",hash=brohn_hash("original implementation")))),resolved_panel_count=88L,maximum_panels=50L,reason_code=reason)
task_setup<-quote({eval(setup)
 bind_task<-function(){bind();x<-list();for(s in controller$state$sections)if(.brohn_rpv_task_adapter(s$adapter)){
  x[[paste0("rpk_pages_",s$id)]]<-if(s$display$pages=="all")""else paste(unlist(s$display$page_numbers),collapse=",")
  if(s$adapter=="task-trials"){
   x[[paste0("rpk_task_scope_",s$id)]]<-s$display$trial_scope
   x[[paste0("rpk_task_measure_",s$id)]]<-s$display$measure
   x[[paste0("rpk_task_mode_",s$id)]]<-if(identical(s$display$charts,"profile_default"))"profile_default"else"selected"
   if(!identical(s$display$charts,"profile_default"))x[[paste0("rpk_task_charts_",s$id)]]<-unlist(s$display$charts)
  }};if(length(x))do.call(session$setInputs,x)}
 bind_task()
 task_section<-function()Filter(function(s)s$adapter=="task-trials",controller$state$sections)[[1]]
 publish_view<-function(status,action,preparation=NULL,reason=NULL){id<-saved();view<-mock$intents[[id]]$view;view$status<-status;view$next_action<-action;view$preparation<-preparation;view$reason<-reason
  mock$intents[[id]]$view<-view;session$elapse(1001);session$flushReact()}
})
scenario("cold packed task metadata and one action",{
 mock$prepared<-FALSE;eval(task_setup);s<-task_section();before<-mock$saves;reads<-mock$full_reads
 check(identical(s$selector$scope,"all_administrations")&&identical(s$display$measure,"profile_default")&&identical(s$display$charts,"profile_default"),"Unknown packed metadata stores all-applicable policies, not invented administrations or concrete defaults")
 session$setInputs(rpk_selector_open=list(ref=s$source_report_ref,adapter=s$adapter))
 check(!length(controller$state$selector$items)&&grepl("Specific task choices become available",output$rpk_selector$html,fixed=TRUE),"Preparation-needed metadata stays unknown with a clear one-Prepare explanation")
 session$setInputs(rpk_prepare=1L);check(mock$saves==before&&controller$state$phase=="preparing","Task Prepare paints feedback before intent or dependency work")
 ack();r<-controller$state$intent$request
 check(mock$saves==before+1L&&identical(r$renderer_profile,"controlled-gaze-explicit-task-paired/0.1")&&identical(r$limits_profile,"controlled-task-report-package/0.1"),"One acknowledged task Prepare saves the explicit new renderer and limits profiles")
 check(grepl("Saved task views preparing; Response distributions preparing",output$rpk_feedback$html,fixed=TRUE)&&mock$full_reads==reads,"Mixed dependency progress is accurate and requires no full task reads")
 session$setInputs(rpk_prepare=2L);check(mock$saves==before+1L,"Duplicate Prepare does not create another task intent")
 original<-brohn_json(controller$state$sections);n<-length(mock$lookups)
 publish_view("needs_attention","review",prepared_summary("panel_limit"),"Choose fewer illustrated panels.")
 check(length(mock$lookups)>n&&identical(controller$state$selector$state,"ready")&&.brohn_rpv_same(tail(mock$catalog_reads,1)[[1]]$prepared_ref,mock$prepared_ref),"Panel-limit recovery refreshes bounded metadata against the exact prepared reference")
 check(identical(original,brohn_json(controller$state$sections))&&!controller$state$dirty&&identical(controller$state$intent$request,r),"Prepared catalog refresh preserves all requested policies and does not dirty or rewrite the saved request")
 check(grepl("88 illustrated panels",output$rpk_feedback$html,fixed=TRUE)&&grepl("limit is 50",output$rpk_feedback$html,fixed=TRUE),"The researcher sees the actual expanded panel count and limit")
 publish_view("needs_attention","review",NULL,"Original source binding is no longer available.")
 check(is.null(controller$state$selector)&&!length(controller$state$task_options),"Lost source preparation removes stale focused controls without rewriting the request")
})
scenario("seven profile choices and GNAT guard",{
 mock$prepared<-TRUE;eval(task_setup);s<-task_section();session$setInputs(rpk_selector_open=list(ref=s$source_report_ref,adapter=s$adapter))
 page1<-controller$state$selector;session$setInputs(rpk_selector_next=1L);p<-controller$state$selector
 check(length(page1$items)==6L&&p$items[[1]]$details$profile==profiles[[7]]&&identical(task_section()$selector$scope,"all_administrations"),"Seven profile metadata entries are paged without narrowing the all-applicable request")
 session$setInputs(rpk_selector_choose=list(ref=p$report_ref,adapter=p$adapter,selector=p$items[[1]]$selector));bind_task();s<-task_section()
 html<-output$rpk_figures$html
 check(identical(s$selector$keys,list(catalog[[7]]$key))&&identical(s$display$measure,"profile_default")&&grepl("Response outcomes",html,fixed=TRUE)&&!grepl('value="final_correct_ms"',html,fixed=TRUE),"Exact GNAT controls include outcomes and never offer final-correct latency")
 bad<-setNames(list("final_correct_ms"),paste0("rpk_task_measure_",s$id));do.call(session$setInputs,bad);before<-mock$saves;session$setInputs(rpk_prepare=1L)
 check(mock$saves==before&&grepl("available for this exact administration",controller$state$issue,fixed=TRUE),"A forged incompatible GNAT measure is rejected before saving")
 good<-setNames(list("first_response_ms","scored","selected",c("outcomes","distribution"),"2, 3"),paste0(c("rpk_task_measure_","rpk_task_scope_","rpk_task_mode_","rpk_task_charts_","rpk_pages_"),s$id));do.call(session$setInputs,good)
 session$setInputs(rpk_prepare=2L);ack();chosen<-Filter(function(s)s$adapter=="task-trials",controller$state$intent$request$requested_sections)[[1]]
 check(identical(chosen$display$measure,"first_response_ms")&&identical(chosen$display$trial_scope,"scored")&&identical(chosen$display$page_numbers,list(2L,3L))&&identical(chosen$display$charts,list("outcomes","distribution")),"Exact administration, recorded measure, position scope, charts and numerical pages persist as typed requested choices")
 check(grepl("Numerical table pages",html,fixed=TRUE)&&grepl("Task charts still cover the whole selected scope",html,fixed=TRUE),"Task page controls disclose table paging without pretending to crop the chart or full export")
 defaults<-vapply(catalog,`[[`,character(1),"default_measure")
 check(identical(defaults,c(rep("final_correct_ms",2),rep("first_response_ms",5))),"The bounded seven-profile fixture describes two final-correct and five first-response defaults without UI resolution")
})
scenario("code-change review creates only an explicit new plan",{
 mock$prepared<-FALSE;eval(task_setup);session$setInputs(rpk_prepare=1L);ack();old<-saved();r<-controller$state$intent$request;before<-mock$saves;adv<-mock$advances
 publish_view("needs_attention","review",NULL,"The pinned preparation implementation is unavailable. Review before preparing with current code.")
 session$elapse(2001);check(mock$saves==before&&mock$advances==adv&&grepl("Prepare these choices as a new version",output$rpk_feedback$html,fixed=TRUE),"Code drift stops passive advance and offers an explicit new-version action")
 generation<-controller$state$generation
 session$setInputs(rpk_prepare_new=1L);check(mock$saves==before&&controller$state$pending$action=="save"&&controller$state$generation==generation+1L,"New-version action creates a fresh view generation and paints feedback before saving a new command")
 ack();check(mock$saves==before+1L&&saved()!=old&&identical(controller$state$intent$request,r)&&mock$intents[[old]]$view$status=="superseded","Explicit new version preserves exact requested choices and supersedes only the exact old intent")
})
scenario("hidden task figures and saved cohorts",{
 mock$prepared<-TRUE;eval(task_setup)
 for(s in Filter(function(s).brohn_rpv_task_adapter(s$adapter),controller$state$sections))session$setInputs(rpk_section_remove=s$id)
 bind_task();session$setInputs(rpk_prepare=1L);ack();r<-controller$state$intent$request
 check(identical(r$renderer_profile,"controlled-gaze-explicit-task-paired/0.1")&&length(r$report_refs)==1L&&!any(vapply(r$requested_sections,function(s).brohn_rpv_task_adapter(s$adapter),logical(1)))&&r$contents_policy$complete_selected_numerical_evidence,"Hiding task figures retains the task-capable complete-source request and numerical policy")
 session$setInputs(rpk_enter=list(study_id="study",project_id="default",report_ref=rows[[3]]$ref));bind_task()
 s<-controller$state$sections[[1]];check(identical(s$adapter,"task-people")&&identical(s$selector$scope,"all_metrics")&&identical(s$display$charts,list("people")),"A cohort requests all saved metrics and people views without fake trial administrations")
 session$setInputs(rpk_selector_open=list(ref=s$source_report_ref,adapter=s$adapter));p<-controller$state$selector
 check(grepl("counts remain unknown",output$rpk_selector$html,fixed=TRUE),"Unlinked cohort metadata explains unknown support rather than showing zero eligible people")
 session$setInputs(rpk_selector_choose=list(ref=p$report_ref,adapter=p$adapter,selector=p$items[[1]]$selector));bind_task();session$setInputs(rpk_prepare=2L);ack()
 check(identical(controller$state$intent$request$requested_sections[[1]]$selector,list(scope="exact_metrics",metrics=list("RT_mean_ms"))),"Exact saved cohort metric selection persists without a new estimator")
})
scenario("historical task metadata retains exact prepared identity",{
 mock$prepared<-TRUE;eval(task_setup);session$setInputs(rpk_prepare=1L);ack();id<-saved()
 publish_view("needs_attention","review",prepared_summary("panel_limit"),"Choose fewer views.")
 original<-controller$state$intent$request;session$setInputs(rpk_back=1L)
 session$setInputs(rpk_enter=list(study_id="study",project_id="default",report_ref=NULL));bind_task()
 session$setInputs(rpk_history_open=mock$intents[[id]]$view$intent_ref);bind_task();s<-task_section()
 before<-mock$advances;session$setInputs(rpk_selector_open=list(ref=s$source_report_ref,adapter=s$adapter))
 check(.brohn_rpv_same(tail(mock$catalog_reads,1)[[1]]$prepared_ref,mock$prepared_ref)&&identical(controller$state$intent$request,original)&&!controller$state$automatic&&mock$advances==before,"Restored preparation opens its pinned catalog without changing defaults or automatically advancing")
 session$setInputs(rpk_enter=list(study_id="study",project_id="default",report_ref=rows[[3]]$ref));bind_task()
 mock$denied_ref<-rows[[3]]$ref$id
 session$setInputs(rpk_history_open=mock$intents[[id]]$view$intent_ref);bind_task()
 check(is.null(controller$state$issue)&&identical(controller$state$rows[[1]]$ref,rows[[1]]$ref)&&identical(controller$state$intent$request,original),"Opening another saved intent never refreshes the previous editor's now-inaccessible source")
 mock$denied_ref<-NULL
})
scenario("unsupported evidence and safe task labels",{
 unsupported<-rows[[1]];unsupported$adapters<-list();unsupported$title<-"Task <script>unsafe</script>";unsupported$reason<-"This complete source contains unsupported choice-task evidence."
 html<-as.character(brohn_report_package_sources_ui(list(reports=list(unsupported),next_cursor=NULL),list()))
 check(!length(.brohn_rpv_default_sections(list(unsupported)))&&grepl("unsupported choice-task evidence",html,fixed=TRUE)&&!grepl("Include findings",html,fixed=TRUE),"Unsupported mixed scientific content offers no silently partial set of default adapters")
 check(grepl("&lt;script&gt;",html,fixed=TRUE)&&!grepl("<script>unsafe",html,fixed=TRUE),"Untrusted task source titles remain escaped")
 statuses<-.brohn_rpv_waiting(list(list(kind="task_display",status="succeeded"),list(kind="explicit_distributions",status="running")))
 check(identical(statuses,"Saved task views ready; Response distributions preparing"),"A ready task dependency is distinguished from a still-running explicit dependency")
 mock$prepared<-TRUE;eval(task_setup);s<-task_section();session$setInputs(rpk_selector_open=list(ref=s$source_report_ref,adapter=s$adapter));page<-controller$state$selector
 session$setInputs(rpk_selector_choose=list(ref=page$report_ref,adapter=page$adapter,selector=page$items[[5]]$selector));bind_task()
 check(grepl("One correct response and 39 omissions; SD unavailable",output$rpk_figures$html,fixed=TRUE)&&grepl("Native tasks, liking and scales | saved version 1",output$rpk_figures$html,fixed=TRUE),"Available administration controls preserve incomplete metric support and exact human source context")
})
scenario("failed and review preparations retain cancellation",{
 mock$prepared<-FALSE;eval(task_setup)
 for(status in c("failed","needs_attention")){
  if(status=="needs_attention"){session$setInputs(rpk_enter=list(study_id="study",project_id="default",report_ref=rows[[2]]$ref));bind_task()}
  session$setInputs(rpk_prepare=if(status=="failed")1L else 2L);ack()
  publish_view(status,if(status=="failed")"retry"else"review",NULL,"Another saved prerequisite is still queued.")
  before<-mock$cancels;original<-controller$state$intent$request
  check(grepl('id="rpk_cancel"',output$rpk_feedback$html,fixed=TRUE),paste(status,"with outstanding dependencies exposes the existing Cancel action"))
  session$setInputs(rpk_cancel=if(status=="failed")1L else 2L)
  check(mock$cancels==before+1L&&controller$state$intent$status=="cancelled"&&identical(controller$state$intent$request,original),paste(status,"cancellation delegates ownership handling to the existing backend without changing the request"))
 }
})
scenario("gaze image option distinguishes task material references",{
 mock$prepared<-FALSE;eval(task_setup)
 check(grepl("Include gaze stimulus images",output$rpk_editor$html,fixed=TRUE)&&grepl('id="rpk_images"',output$rpk_editor$html,fixed=TRUE),"The image label is gaze-specific while its existing input identity stays unchanged")
 check(grepl("No gaze source is selected",output$rpk_material_scope$html,fixed=TRUE)&&grepl("Task material image bytes are not embedded",output$rpk_material_scope$html,fixed=TRUE)&&grepl("definitions and hashes",output$rpk_material_scope$html,fixed=TRUE),"A task-only report marks the gaze option inapplicable and explains complete material references without claiming image embedding")
 session$setInputs(rpk_images=TRUE,rpk_prepare=1L);ack()
 check(identical(controller$state$intent$request$contents_policy$stimulus_images,"included"),"The scope disclosure leaves the existing contents command semantics unchanged")
 controller$state$rows<-c(controller$state$rows,list(list(ref=ref("gaze-note-fixture"),title="Gaze context",kind="gaze",adapters=list("gaze-context"))))
 session$flushReact()
 check(grepl("supported PNG/JPEG gaze stimulus images",output$rpk_material_scope$html,fixed=TRUE)&&!grepl("No gaze source is selected",output$rpk_material_scope$html,fixed=TRUE),"The applicability note updates from bounded selected-source metadata when gaze is included")
})
scenario("prepared explicit and packed paired catalogs stay exact through recovery and history",{
 mock$prepared<-FALSE;eval(task_setup)
 original_sections<-brohn_json(controller$state$sections)
 session$setInputs(rpk_selector_open=list(ref=rows[[1]]$ref,adapter="explicit-distribution"))
 check(!length(controller$state$selector$items)&&controller$state$selector$requires_display_preparation,"Cold explicit catalog does not invent response groups")
 session$setInputs(rpk_prepare=1L);ack();id<-saved();original<-controller$state$intent$request
 prepared<-prepared_summary("panel_limit");prepared$prepared_sources<-c(prepared$prepared_sources,list(list(adapter="explicit-distribution",source_report_ref=rows[[1]]$ref,prepared_ref=mock$distribution_ref)))
 mock$prepared<-TRUE;publish_view("needs_attention","review",prepared,"Choose fewer illustrated views.")
 read<-tail(mock$catalog_reads,1)[[1]]
 check(.brohn_rpv_same(read$prepared_ref,mock$distribution_ref)&&controller$state$selector$items[[1]]$selector$item_id=="original-liking","An open explicit catalog refreshes to the exact completed historical preparation, not the newer available groups")
 check(identical(original_sections,brohn_json(controller$state$sections))&&identical(original,controller$state$intent$request)&&!controller$state$dirty,"Refreshing explicit prepared metadata preserves requested defaults and saved policy")
 session$setInputs(rpk_selector_next=1L);read<-tail(mock$catalog_reads,1)[[1]]
 check(identical(read$cursor,"page2")&&.brohn_rpv_same(read$prepared_ref,mock$distribution_ref)&&controller$state$selector$items[[1]]$selector$condition_id=="control","Explicit pagination keeps the same pinned preparation reference")
 session$setInputs(rpk_back=1L);session$setInputs(rpk_enter=list(study_id="study",project_id="default",report_ref=NULL));bind_task()
 session$setInputs(rpk_history_open=mock$intents[[id]]$view$intent_ref);bind_task()
 session$setInputs(rpk_selector_open=list(ref=rows[[1]]$ref,adapter="explicit-distribution"));read<-tail(mock$catalog_reads,1)[[1]]
 check(.brohn_rpv_same(read$prepared_ref,mock$distribution_ref)&&controller$state$selector$items[[1]]$selector$item_id=="original-liking","Reopened history uses its exact explicit artifact even when a newer preparation is available")
 session$setInputs(rpk_selector_open=list(ref=rows[[1]]$ref,adapter="paired-findings"));read<-tail(mock$catalog_reads,1)[[1]]
 check(.brohn_rpv_same(read$prepared_ref,mock$prepared_ref)&&controller$state$selector$items[[1]]$selector$comparison_id=="original-comparison","Packed paired choices use the exact saved task-display companion catalog")
 session$setInputs(rpk_selector_next=2L);read<-tail(mock$catalog_reads,1)[[1]]
 check(.brohn_rpv_same(read$prepared_ref,mock$prepared_ref)&&identical(read$cursor,"page2")&&identical(controller$state$intent$request,original)&&mock$full_reads==0L,"Packed paired pagination remains pinned without opening full artifacts or rewriting choices")
})
scenario("missing pinned catalog cannot fall back after an unrelated edit",{
 mock$prepared<-TRUE;eval(task_setup);session$setInputs(rpk_prepare=1L);ack()
 publish_view("needs_attention","review",NULL,"Original prepared evidence is unavailable.")
 n<-length(mock$catalog_reads)
 for(adapter in c("explicit-distribution","paired-findings","task-trials")){
  session$setInputs(rpk_selector_open=list(ref=rows[[1]]$ref,adapter=adapter))
  check(isTRUE(controller$state$selector$locked)&&!length(controller$state$selector$items)&&length(mock$catalog_reads)==n,paste("Saved",adapter,"missing its exact preparation remains locked without a current catalog lookup"))
 }
 session$setInputs(rpk_title="Edited historical report title");session$setInputs(rpk_selector_open=list(ref=rows[[1]]$ref,adapter="paired-findings"))
 check(controller$state$dirty&&isTRUE(controller$state$selector$locked)&&length(mock$catalog_reads)==n,"An unrelated title edit cannot silently unlock a newer prepared paired catalog")
 session$setInputs(rpk_source_toggle=rows[[2]]$ref);bind_task();session$setInputs(rpk_selector_open=list(ref=rows[[2]]$ref,adapter="task-trials"))
 check(!isTRUE(controller$state$selector$locked)&&length(controller$state$selector$items)>0L&&length(mock$catalog_reads)==n+1L,"A genuinely newly added source still has the normal new-intent metadata flow")
})
scenario("new pinned preparation resets only the open catalog page",{
 mock$prepared<-TRUE;eval(task_setup)
 session$setInputs(rpk_selector_open=list(ref=rows[[1]]$ref,adapter="explicit-distribution"));session$setInputs(rpk_selector_next=1L)
 check(identical(controller$state$selector$cursor,"page2")&&is.null(tail(mock$catalog_reads,1)[[1]]$prepared_ref),"An unsaved editor can browse existing bounded groups without claiming an already pinned preparation")
 original<-brohn_json(controller$state$sections);session$setInputs(rpk_prepare=1L);ack()
 prepared<-prepared_summary("panel_limit");prepared$prepared_sources<-c(prepared$prepared_sources,list(list(adapter="explicit-distribution",source_report_ref=rows[[1]]$ref,prepared_ref=mock$distribution_ref)))
 publish_view("needs_attention","review",prepared,"Choose fewer views.");read<-tail(mock$catalog_reads,1)[[1]]
 check(is.null(read$cursor)&&.brohn_rpv_same(read$prepared_ref,mock$distribution_ref)&&.brohn_rpv_same(controller$state$selector$prepared_ref,mock$distribution_ref)&&identical(original,brohn_json(controller$state$sections)),"New prepared binding resets the catalog cursor while preserving the exact requested sections")
 n<-length(mock$catalog_reads);session$setInputs(rpk_selector_previous=1L)
 check(length(mock$catalog_reads)==n,"The previous-page stack cannot replay a cursor from another preparation")
})
legacy<-list(ref=ref("legacy-explicit-source"),title="Historical explicit answers",origin="sample",kind="questionnaire",adapters=list("explicit-distribution"),status="available",reason=NULL)
rows<-c(rows,list(legacy))
scenario("legacy explicit dependency metadata keeps historical selectors exact",{
 mock$prepared<-TRUE;eval(task_setup)
 session$setInputs(rpk_enter=list(study_id="study",project_id="default",report_ref=legacy$ref));bind_task()
 session$setInputs(rpk_prepare=1L);ack();id<-saved()
 mock$intents[[id]]$view$dependencies<-list(list(report_ref=legacy$ref,result_ref=mock$distribution_ref,job_id="saved-legacy-distribution"))
 publish_view("needs_attention","review",NULL,"Review the original legacy report.")
 session$setInputs(rpk_selector_open=list(ref=legacy$ref,adapter="explicit-distribution"));read<-tail(mock$catalog_reads,1)[[1]]
 check(identical(controller$state$intent$request$renderer_profile,"controlled-gaze-explicit-paired/0.1")&&.brohn_rpv_same(read$prepared_ref,mock$distribution_ref)&&controller$state$selector$items[[1]]$selector$item_id=="original-liking","Legacy explicit selectors use their retained dependency result ref without replacing the original renderer profile")
})
brohn_write_json_file(list(passed=all(vapply(scenarios,`[[`,logical(1),"passed")),checks=checks,scenarios=scenarios,
 source_hashes=setNames(lapply(c("platform-report-package-views.R","platform-report-package-server.R"),function(f)digest::digest(file=file.path(candidate,f),algo="sha256")),c("views","server")),
 scope="Task controller and HTML views with explicit bounded metadata/intent/resource spies. The seven-profile catalog is synthetic; no scientific resolution, actual worker, native authority or browser acceptance is claimed."),file.path(folder,"results.json"))
if(any(!vapply(scenarios,`[[`,logical(1),"passed")))quit(status=1L)
