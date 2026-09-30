# Portable Shiny controller contract tests using explicit in-memory backend spies.
# Rscript tests/report-choice-package-ui-state.R <source-root> <fresh-evidence-directory>
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
rows<-list(
 list(ref=ref("mixed-task-choice"),title="Tasks, MaxDiff, liking and scales",origin="sample",kind="questionnaire",source_family="native_questionnaire",source_components=list("explicit","task","choice"),choice_source_family="native_questionnaire",adapters=list("task-scores","task-trials","choice-counts","choice-utilities","explicit-distribution","paired-findings"),status="available",reason=NULL),
 list(ref=ref("choice-explicit"),title="MaxDiff and liking without a task",origin="sample",kind="questionnaire",source_components=list("explicit","choice"),choice_source_family="native_questionnaire",adapters=list("choice-counts","choice-utilities","explicit-distribution","paired-findings"),status="available",reason=NULL),
 list(ref=ref("task-only"),title="Original IAT",origin="import",kind="implicit",source_family="imported_implicit",source_components=list("task"),adapters=list("task-scores","task-trials"),status="available",reason=NULL),
 list(ref=ref("imported-choice"),title="Imported MaxDiff",origin="import",kind="explicit_choice",source_components=list("choice"),choice_source_family="imported_choice",adapters=list("choice-counts","choice-utilities"),status="available",reason=NULL))
mock$prepared<-FALSE;mock$catalog_reads<-list();mock$full_reads<-0L;mock$denied_preparation<-NULL
choice_ref<-function(source,revision=1L)ref(paste0("choice-display-",source$id),"choice_display",revision)
task_ref<-function(source)ref(paste0("task-display-",source$id),"task_display")
distribution_ref<-function(source)ref(paste0("distribution-",source$id),"explicit_distributions")
brohn_report_package_choices<-function(store,study_id,project_id,cursor=NULL,limit=25L)list(study=list(id=study_id,title="Mixed choice research",project_id=project_id),reports=rows,cursor=cursor,next_cursor=NULL,recommended_refs=list(rows[[1]]$ref),needs_choice=FALSE)
brohn_open_choice_display_resources<-function(...){mock$full_reads<-mock$full_reads+1L;stop("Full choice artifact opened in Shiny")}
brohn_open_task_display_resources<-function(...){mock$full_reads<-mock$full_reads+1L;stop("Full task artifact opened in Shiny")}
catalog<-lapply(1:3,function(i)list(kind="exercise",key=brohn_hash(list("exercise",i)),index=i,exercise_id=paste0("exercise-",i),title=if(i<3)"Duplicate <exercise>"else"No complete pairs",profile="object-case-paired-maxdiff/1.0",item_count=if(i==1)60L else 3L,exposure_count=if(i==3)2L else 12L,
 counts=list(status=if(i==3)"no_complete_pairs"else"available",reason=if(i==3)"no_complete_pair_exposures"else NULL,row_count=if(i==1)60L else 3L),
 utilities=list(status=c("estimated","not_requested","unavailable")[[i]],reason=c("original fit", "Fitting disabled in saved analysis", "No complete pairs")[[i]],row_count=if(i==1)60L else 0L)))
brohn_report_package_selector_catalog<-function(store,report_ref,adapter,cursor=NULL,limit=25L,prepared_ref=NULL){
 mock$catalog_reads<-c(mock$catalog_reads,list(list(report_ref=report_ref,adapter=adapter,cursor=cursor,prepared_ref=prepared_ref)))
 if(!is.null(prepared_ref)&&identical(prepared_ref$id,mock$denied_preparation))stop("The exact saved preparation is no longer accessible.")
 available<-mock$prepared||!is.null(prepared_ref)
 if(.brohn_rpv_choice_adapter(adapter)){
  items<-if(!available)list()else lapply(catalog[if(is.null(cursor))1:2 else 3],function(d)list(selector=list(scope="exact_exercises",keys=list(d$key)),label=paste("Exercise",d$index,d$title),details=d))
 }else if(adapter=="paired-findings"){
  items<-if(!available)list()else list(list(selector=list(scope="exact_comparison",comparison_id=paste0("original-",if(is.null(cursor))1 else 2),contrast_hash=brohn_hash("contrast")),label="Original saved comparison",details="Exact companion metadata"))
 }else items<-list()
 # Generic API deliberately does not echo prepared_ref; controller must retain it.
 list(report_ref=report_ref,adapter=adapter,items=items,cursor=cursor,next_cursor=if(available&&is.null(cursor))"page2"else NULL,requires_display_preparation=!available,state=if(available)"ready"else"needs_preparation",reason=NULL)
}
base_continue<-brohn_continue_report_package_intent
brohn_continue_report_package_intent<-function(store,intent_ref,action="advance"){
 v<-base_continue(store,intent_ref,action)
 if(v$status=="waiting_for_display")v$dependencies<-list(list(kind="explicit_distributions",job_id="explicit",status="running"),list(kind="task_display",job_id="task",status="queued"),list(kind="choice_display",job_id="choice",status="queued"))
 mock$intents[[intent_ref$id]]$view<-v;v}
prepared_summary<-function(source=rows[[1]]$ref,task=TRUE,choice=TRUE,revision=1L,reason=NULL){
 p<-list(list(adapter="explicit-distribution",source_report_ref=source,prepared_ref=distribution_ref(source)))
 if(task)p<-c(p,list(list(adapter="task-display",source_report_ref=source,prepared_ref=task_ref(source))))
 if(choice)p<-c(p,list(list(adapter="choice-display",source_report_ref=source,prepared_ref=choice_ref(source,revision))))
 list(prepared_sources=p,resolved_panel_count=102L,maximum_panels=100L,reason_code=reason)}
choice_setup<-quote({eval(setup)
 bind_choice<-function(){bind();x<-list();for(s in controller$state$sections)if(.brohn_rpv_choice_adapter(s$adapter))x[[paste0("rpk_pages_",s$id)]]<-if(s$display$pages=="all")""else paste(unlist(s$display$page_numbers),collapse=",");if(length(x))do.call(session$setInputs,x)}
 bind_choice();section<-function(adapter)Filter(function(s)s$adapter==adapter,controller$state$sections)[[1]]
 publish_view<-function(status,action,preparation=NULL,reason=NULL){id<-saved();view<-mock$intents[[id]]$view;view$status<-status;view$next_action<-action;view$preparation<-preparation;view$reason<-reason
  mock$intents[[id]]$view<-view;session$elapse(1001);session$flushReact()}
})
scenario("mixed cold defaults and one acknowledged action",{
 mock$prepared<-FALSE;eval(choice_setup);before<-mock$saves
 adapters<-vapply(controller$state$sections,`[[`,character(1),"adapter")
 check(identical(adapters,c("task-scores","task-trials","choice-counts","choice-utilities","explicit-distribution","paired-findings")),"Mixed source retains task, choice, explicit and paired default sections together")
 check(all(vapply(Filter(function(s).brohn_rpv_choice_adapter(s$adapter),controller$state$sections),function(s)identical(s$selector,list(scope="all_exercises"))&&identical(s$display,list(pages="all",page_numbers=list())),logical(1))),"Both choice defaults persist all exercises and empty all-page arrays before metadata exists")
 session$setInputs(rpk_selector_open=list(ref=rows[[1]]$ref,adapter="choice-utilities"))
 check(!length(controller$state$selector$items)&&grepl("Prepare report includes every saved exercise",output$rpk_selector$html,fixed=TRUE),"Unknown packed choices stay unknown and require no separate preparation action")
 session$setInputs(rpk_prepare=1L);check(mock$saves==before&&controller$state$phase=="preparing","Choice Prepare paints before saving or advancing")
 ack();request<-controller$state$intent$request
 check(request$renderer_profile=="controlled-gaze-explicit-task-choice-paired/0.1"&&request$limits_profile=="controlled-task-choice-report-package/0.1","One acknowledged Prepare selects only the choice-capable renderer for choice evidence")
 check(grepl("Saved best-worst views preparing",output$rpk_feedback$html,fixed=TRUE)&&grepl("Saved task views",output$rpk_feedback$html,fixed=TRUE)&&grepl("Response distributions",output$rpk_feedback$html,fixed=TRUE),"Progress distinguishes all three real dependency kinds")
 session$setInputs(rpk_prepare=2L);check(mock$saves==before+1L&&mock$full_reads==0L,"Duplicate Prepare cannot create another intent or read full source artifacts")
 check(grepl("without refitting",output$rpk_contents$html,fixed=TRUE)&&grepl("choice material image bytes are not embedded",output$rpk_material_scope$html,fixed=TRUE),"Mixed report copy does not promise new models, associations or task/choice image bytes")
})
scenario("catalog status, exact exercises and numerical pages",{
 mock$prepared<-TRUE;eval(choice_setup)
 session$setInputs(rpk_selector_open=list(ref=rows[[1]]$ref,adapter="choice-utilities"))
 html<-output$rpk_selector$html
 check(grepl("60 saved items",html,fixed=TRUE)&&grepl("Model fitting was not requested",html,fixed=TRUE)&&grepl("&lt;exercise&gt;",html,fixed=TRUE),"Bounded choices retain true item counts, no-fit status and escaped duplicate titles")
 first<-controller$state$selector$items[[1]]
 session$setInputs(rpk_selector_choose=list(ref=rows[[1]]$ref,adapter="choice-utilities",selector=first$selector));bind_choice();s<-section("choice-utilities")
 do.call(session$setInputs,setNames(list("2"),paste0("rpk_pages_",s$id)));session$setInputs(rpk_prepare=1L);ack()
 selected<-Filter(function(s)s$adapter=="choice-utilities",controller$state$intent$request$requested_sections)[[1]]
 check(.brohn_rpv_same(selected$selector,first$selector)&&identical(selected$display,list(pages="selected",page_numbers=list(2L))),"Exact exercise key and selected numerical page persist without trimming complete source policies")
 check(grepl("Choice charts cover every saved item",output$rpk_figures$html,fixed=TRUE),"Choice controls disclose that page selection does not crop a full item chart")
 publish_view("needs_attention","review",prepared_summary(reason="panel_limit"),"Choose fewer figures")
 session$setInputs(rpk_selector_open=list(ref=rows[[1]]$ref,adapter="choice-utilities"));session$setInputs(rpk_selector_next=1L)
 last<-tail(mock$catalog_reads,1)[[1]]
 check(.brohn_rpv_same(last$prepared_ref,choice_ref(rows[[1]]$ref))&&last$cursor=="page2","Choice catalog pagination remains pinned to its exact prepared reference")
 check(grepl("saved choice model is unavailable",output$rpk_selector$html,fixed=TRUE)&&grepl("3 saved items",output$rpk_selector$html,fixed=TRUE),"Unavailable utility with zero model rows does not masquerade as zero items")
 unavailable_selector<-controller$state$selector$items[[1]]$selector
 session$setInputs(rpk_selector_choose=list(ref=rows[[1]]$ref,adapter="choice-utilities",selector=unavailable_selector))
 unavailable<-Filter(function(s)s$adapter=="choice-utilities"&&.brohn_rpv_same(s$selector,unavailable_selector),controller$state$sections)
 check(length(unavailable)==1L&&identical(unavailable[[1]]$display,list(pages="all",page_numbers=list())),"Unavailable saved exercise remains selectable with its explanatory default rather than disappearing")
})
scenario("source components fix paired companion precedence",{
 mock$prepared<-FALSE;eval(choice_setup);session$setInputs(rpk_prepare=1L);ack()
 publish_view("waiting_for_display","wait",prepared_summary(task=FALSE,choice=TRUE));n<-length(mock$catalog_reads)
 session$setInputs(rpk_selector_open=list(ref=rows[[1]]$ref,adapter="paired-findings"))
 check(isTRUE(controller$state$selector$locked)&&length(mock$catalog_reads)==n,"Mixed source waits for its missing exact task companion even when choice preparation finished first")
 original<-brohn_json(controller$state$sections)
 publish_view("needs_attention","review",prepared_summary(reason="panel_limit"),"Reduce illustrated panels")
 check(.brohn_rpv_same(tail(mock$catalog_reads,1)[[1]]$prepared_ref,task_ref(rows[[1]]$ref))&&identical(original,brohn_json(controller$state$sections)),"Completing the required task companion refreshes bounded paired metadata without replacing requested sections")
 mock$denied_preparation<-task_ref(rows[[1]]$ref)$id;n<-length(mock$catalog_reads)
 session$setInputs(rpk_selector_open=list(ref=rows[[1]]$ref,adapter="paired-findings"))
 check(length(mock$catalog_reads)==n+1L&&grepl("no longer accessible",controller$state$issue,fixed=TRUE),"Revoked historical task preparation refuses rather than falling back to an available choice companion")
 mock$denied_preparation<-NULL
 session$setInputs(rpk_enter=list(study_id="study",project_id="default",report_ref=rows[[2]]$ref));bind_choice();session$setInputs(rpk_prepare=2L);ack()
 publish_view("needs_attention","review",prepared_summary(rows[[2]]$ref,task=FALSE),"Review saved views")
 session$setInputs(rpk_selector_open=list(ref=rows[[2]]$ref,adapter="paired-findings"));session$setInputs(rpk_selector_next=1L)
 check(.brohn_rpv_same(tail(mock$catalog_reads,1)[[1]]$prepared_ref,choice_ref(rows[[2]]$ref)),"Choice without a task uses its exact choice companion for packed paired pagination")
})
scenario("panel recovery binding, history and profile changes",{
 mock$prepared<-TRUE;eval(choice_setup)
 session$setInputs(rpk_selector_open=list(ref=rows[[1]]$ref,adapter="choice-counts"));session$setInputs(rpk_selector_next=1L)
 original<-brohn_json(controller$state$sections);session$setInputs(rpk_prepare=1L);ack()
 publish_view("needs_attention","review",prepared_summary(revision=2L,reason="panel_limit"),"Reduce illustrated panels")
 read<-tail(mock$catalog_reads,1)[[1]]
 check(is.null(read$cursor)&&.brohn_rpv_same(read$prepared_ref,choice_ref(rows[[1]]$ref,2L))&&identical(original,brohn_json(controller$state$sections)),"Panel recovery resets only stale catalog pagination and retains original default policies")
 n<-length(mock$catalog_reads);session$setInputs(rpk_selector_previous=1L);check(length(mock$catalog_reads)==n,"A prior-page cursor cannot cross to a new prepared artifact")
 old_id<-saved();old_request<-brohn_json(controller$state$intent$request);session$setInputs(rpk_history_open=controller$state$intent$intent_ref);bind_choice()
 session$setInputs(rpk_selector_open=list(ref=rows[[1]]$ref,adapter="choice-counts"))
 check(.brohn_rpv_same(tail(mock$catalog_reads,1)[[1]]$prepared_ref,choice_ref(rows[[1]]$ref,2L))&&identical(old_request,brohn_json(controller$state$intent$request)),"History restores the exact prepared choice ref and original requested renderer/defaults")
 for(adapter in c("choice-counts","choice-utilities"))session$setInputs(rpk_section_remove=section(adapter)$id)
 session$setInputs(rpk_prepare=2L);ack()
 check(controller$state$intent$request$renderer_profile=="controlled-gaze-explicit-task-choice-paired/0.1","Hiding both choice figures cannot downgrade complete choice-source admission")
 session$setInputs(rpk_source_toggle=rows[[3]]$ref);session$setInputs(rpk_source_toggle=rows[[1]]$ref)
 before<-mock$saves;session$setInputs(rpk_prepare=3L)
 check(mock$saves==before&&controller$state$pending$payload$request$renderer_profile=="controlled-gaze-explicit-task-paired/0.1","Only explicit new Prepare derives the task profile after removing the last choice-bearing source")
 ack();check(identical(old_request,brohn_json(mock$intents[[old_id]]$request)),"Creating a different-profile version never rewrites the historical request")
})
scenario("explicit retry and new-version review preserve choice request",{
 mock$prepared<-FALSE;eval(choice_setup);session$setInputs(rpk_prepare=1L);ack();old<-brohn_json(controller$state$intent$request)
 publish_view("needs_attention","review",prepared_summary(),"Installed preparation code changed")
 check(grepl("Prepare these choices as a new version",output$rpk_feedback$html,fixed=TRUE)&&grepl("Cancel preparation",output$rpk_feedback$html,fixed=TRUE),"Code drift has explicit new-version and cancellation controls without silent reauthorization")
 before<-mock$saves;session$setInputs(rpk_prepare_new=1L);check(mock$saves==before&&controller$state$phase=="preparing","New version paints before saving or queuing")
 ack();check(identical(old,brohn_json(controller$state$intent$request)),"Explicit code-version renewal retains exact requested exercise/page policies")
 publish_view("failed","retry",prepared_summary(),"Choice preparation failed")
 before<-mock$advances;session$setInputs(rpk_resume=1L);check(mock$advances==before&&controller$state$pending$action=="retry","Retry paints and remains the existing durable action")
 ack();check(identical(old,brohn_json(controller$state$intent$request))&&mock$full_reads==0L,"Retry does not edit choice defaults or read full scientific arrays in the UI")
})
brohn_write_json_file(list(passed=all(vapply(scenarios,`[[`,logical(1),"passed")),checks=checks,scenarios=scenarios,
 source_hashes=setNames(lapply(c("platform-report-package-views.R","platform-report-package-server.R"),function(f)digest::digest(file=file.path(candidate,f),algo="sha256")),c("views","server")),
 scope="Choice controller/views with explicit in-memory bounded catalog, intent and resource spies. No actual source preparation, scientific resolution, native authority, worker or browser qualification."),file.path(folder,"results.json"))
if(any(!vapply(scenarios,`[[`,logical(1),"passed")))quit(status=1L)
