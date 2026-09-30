# Portable Shiny controller contract tests using explicit in-memory backend spies.
# Rscript tests/report-eda-package-ui-state.R <source-root> <fresh-evidence-directory>
# External packet alternative: <packet-directory> <fresh-evidence-directory> <loader-root>
args<-commandArgs(TRUE); if(length(args)==5L)args[4:5]<-vapply(args[4:5],normalizePath,character(1),winslash="/",mustWork=TRUE);stopifnot(length(args)%in%c(2L,3L,5L))
root<-normalizePath(args[[1]],winslash="/",mustWork=TRUE)
loader<-if(length(args)>=3L)normalizePath(args[[3]],winslash="/",mustWork=TRUE)else root
candidate<-if(file.exists(file.path(root,"R","platform-report-package-server.R")))file.path(root,"R")else root
stopifnot(file.exists(file.path(loader,"R","platform-load.R")))
folder<-args[[2]];stopifnot(!file.exists(folder));dir.create(folder,recursive=TRUE)
folder<-normalizePath(folder,winslash="/",mustWork=TRUE)
setwd(loader);source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=TRUE)
support_receipt<-list()
if(length(args)==5L){
 support_dir<-file.path(folder,"support-source-snapshot");dir.create(support_dir)
 for(support in args[4:5]){
  saved_support<-file.path(support_dir,basename(support));stopifnot(file.copy(support,saved_support,overwrite=FALSE))
  support_receipt<-c(support_receipt,list(list(file=basename(support),hash=digest::digest(file=saved_support,algo="sha256"))))
  source(saved_support,encoding="UTF-8")
 }
}
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
 list(ref=ref("event-source"),title="Event <EDA> & saved responses",origin="import",kind="eda",source_components=list("eda"),eda_source_family="event",has_required_eda=TRUE,adapters=list("eda-events"),status="available"),
 list(ref=ref("continuous-source"),title="Continuous conductance",origin="import",kind="eda",source_components=list("eda"),eda_source_family="continuous",has_required_eda=TRUE,adapters=list("eda-continuous"),status="available"),
 list(ref=ref("related-only"),title="Saved paired EDA findings",origin="import",kind="multimodal",source_components=list(),has_required_eda=TRUE,adapters=list("paired-findings"),status="available"),
 list(ref=ref("legacy-task"),title="Original IAT",origin="import",kind="implicit",source_components=list("task"),has_required_eda=FALSE,source_family="imported_implicit",adapters=list("task-scores","task-trials"),status="available"))
mock$prepared<-FALSE;mock$catalog_reads<-list();mock$full_reads<-0L;mock$denied_preparation<-NULL
mock$window_reads<-list();mock$window_authority<-TRUE;mock$window_generation<-1L;mock$window_foreign<-FALSE
eda_ref<-function(source,revision=1L)ref(paste0("eda-display-",source$id),"eda_display",revision)
key<-function(i)brohn_hash(paste0("original-cell-",i))
brohn_report_package_choices<-function(store,study_id,project_id,cursor=NULL,limit=25L)list(study=list(id=study_id,title="EDA research",project_id=project_id),reports=rows,cursor=cursor,next_cursor=NULL,recommended_refs=lapply(rows[1:2],`[[`,"ref"),needs_choice=FALSE)
brohn_open_eda_display_resources<-function(...){mock$full_reads<-mock$full_reads+1L;stop("Full EDA artifact opened in Shiny")}
cell<-function(i=1L,family="continuous")list(kind="eda_cell",key=key(i),source_family=family,identity=list(recording_id="recording",segment_id=if(i==3L)NULL else i,channel="EDA"),label=paste("Saved <cell>",i),source_record_index=i,focusable=family=="continuous"&&i!=3L,focus_reason=if(i==3L)"No observed segment"else NULL,
 original_default_bounds=if(i==3L)NULL else list(start_s="0",end_s="10"),requested_bounds=if(i==3L)NULL else list(start_s="0",end_s="10"),status=if(i==3L)"unavailable"else"available",reason=if(i==3L)"No usable samples"else NULL,original_status=if(i==3L)"unavailable"else"computed",descriptive_status=if(family=="event")"computed"else NULL,descriptive_reason=NULL,scr_status=if(family=="event")"unavailable"else NULL,scr_reason=if(family=="event")"Insufficient eligible response window"else NULL,model_hash=if(i==3L)NULL else brohn_hash(i),components=if(i==3L)list()else as.list(c("clean_us","tonic_us","phasic_us")),feature_count=12L,candidate_count=if(i==3L)0L else 125L,marker_count=if(i==3L)0L else 375L,observed_marker_count=if(i==3L)0L else 300L,unobserved_marker_count=if(i==3L)0L else 30L,out_of_view_marker_count=if(i==3L)0L else 45L,component_counts=list(),numerical_page_counts=list(points=list(clean_us=3L,tonic_us=3L,phasic_us=3L),candidates=3L),marker_page_count=if(i==3L)0L else 3L)
brohn_eda_source_windows<-function(store,report_ref,cursor=NULL,limit=25L){
 mock$window_reads<-c(mock$window_reads,list(list(report_ref=report_ref,cursor=cursor)))
 if(!mock$window_authority)stop("The saved original source is no longer accessible.")
 stopifnot(.brohn_rpv_same(report_ref,rows[[2]]$ref),is.null(cursor)||identical(cursor,"windows-page2"))
 list(schema="brohn-eda-source-windows/0.1",report_ref=if(mock$window_foreign)ref("foreign-source")else report_ref,
  source_family="continuous",source_binding_hash=brohn_hash(list(report_ref,mock$window_generation)),total=4L,
  items=lapply(if(is.null(cursor))1:2 else 3:4,function(i){d<-cell(i);d<-d[c("key","identity","source_record_index","label","original_default_bounds","focusable","focus_reason","original_status")];d$kind<-"eda_source_window";d}),
  cursor=cursor,next_cursor=if(is.null(cursor))"windows-page2"else NULL)
}
brohn_report_package_selector_catalog<-function(store,report_ref,adapter,cursor=NULL,limit=25L,prepared_ref=NULL){
 mock$catalog_reads<-c(mock$catalog_reads,list(list(report_ref=report_ref,adapter=adapter,cursor=cursor,prepared_ref=prepared_ref)))
 if(!is.null(prepared_ref)&&identical(prepared_ref$id,mock$denied_preparation))stop("The exact historical display is no longer accessible.")
 available<-mock$prepared||!is.null(prepared_ref)
 items<-if(!available)list()else lapply(if(is.null(cursor))1:2 else 3,function(i){d<-cell(i,if(adapter=="eda-events")"event"else"continuous");list(selector=list(scope="exact_cells",keys=list(d$key)),label=d$label,details=d)})
 list(report_ref=report_ref,adapter=adapter,items=items,cursor=cursor,next_cursor=if(available&&is.null(cursor))"page2"else NULL,requires_display_preparation=!available,state=if(available)"ready"else"needs_preparation",reason=NULL)
}
base_continue<-brohn_continue_report_package_intent
brohn_continue_report_package_intent<-function(store,intent_ref,action="advance"){
 v<-base_continue(store,intent_ref,action)
 if(v$status=="waiting_for_display")v$dependencies<-lapply(v$request$report_refs,function(r)list(kind="eda_display",report_ref=r,job_id=paste0("eda-",r$id),status="queued"))
 mock$intents[[intent_ref$id]]$view<-v;v}
prepared_summary<-function(revision=1L,reason=NULL)list(prepared_sources=lapply(rows[1:2],function(r)list(adapter="eda-display",source_report_ref=r$ref,prepared_ref=eda_ref(r$ref,revision))),resolved_panel_count=102L,maximum_panels=100L,reason_code=reason)
eda_setup<-quote({eval(setup)
 bind_eda<-function(){bind();x<-list();for(s in controller$state$sections)if(.brohn_rpv_eda_adapter(s$adapter)){
  x[[paste0("rpk_pages_",s$id)]]<-if(s$display$pages=="all")""else paste(unlist(s$display$page_numbers),collapse=",")
  x[[paste0("rpk_eda_markers_",s$id)]]<-if(s$display$marker_pages$pages=="all")""else paste(unlist(s$display$marker_pages$page_numbers),collapse=",")
  x[[paste0("rpk_eda_components_",s$id)]]<-unlist(s$display$components)}
  if(length(x))do.call(session$setInputs,x)}
 bind_eda();section<-function(adapter)Filter(function(s)s$adapter==adapter,controller$state$sections)[[1]]
 publish_view<-function(status,action,preparation=NULL,reason=NULL){id<-saved();view<-mock$intents[[id]]$view;view$status<-status;view$next_action<-action;view$preparation<-preparation;view$reason<-reason
  mock$intents[[id]]$view<-view;session$elapse(1001);session$flushReact()}
 open_window<-function(i=1L){session$setInputs(rpk_selector_open=list(ref=rows[[2]]$ref,adapter="eda-continuous"));session$setInputs(rpk_eda_window_open=list(ref=rows[[2]]$ref,key=key(i)))
  e<-controller$state$window_editor;session$setInputs(rpk_eda_window_identity=e$token,rpk_eda_start=e$requested$start_s,rpk_eda_end=e$requested$end_s)}
 apply_window<-function(start="1.00000000000000000001",end="2.0",n=1L){session$setInputs(rpk_eda_start=start,rpk_eda_end=end,rpk_eda_window_apply=n)}
})
scenario("cold default and complete evidence",{
 mock$prepared<-FALSE;eval(eda_setup);before<-mock$saves
 check(identical(vapply(controller$state$sections,`[[`,character(1),"adapter"),c("eda-events","eda-continuous")),"Distinct event and continuous default sections include every saved cell")
 check(identical(section("eda-events")$display$components,list("phasic_us"))&&identical(section("eda-continuous")$display$components,list("tonic_us","phasic_us")),"Method-specific default components are explicit and marker pages default to all")
 session$setInputs(rpk_selector_open=list(ref=rows[[2]]$ref,adapter="eda-continuous"))
 check(!length(controller$state$selector$items)&&grepl("no separate preparation action",output$rpk_selector$html,fixed=TRUE),"Unknown cold cell metadata stays unknown without another mandatory button")
 session$setInputs(rpk_prepare=1L);check(mock$saves==before&&controller$state$phase=="preparing","EDA Prepare paints before any save or prerequisite advance")
 ack();r<-controller$state$intent$request
 check(.brohn_rpv_eda_profile(r$renderer_profile)&&r$limits_profile=="controlled-task-choice-eda-report-package/0.1"&&identical(r$eda_display_requests,list())&&!any(c("source_requirements","source_identity_graph_binding","related_eda_refs")%in%names(r)),"EDA request adds only canonical sidecar and exact new profiles, with no hidden source graph")
 check(grepl("Saved skin-conductance views preparing",output$rpk_feedback$html,fixed=TRUE)&&mock$full_reads==0L,"EDA-specific progress requires no full object reads in Shiny")
 check(grepl("Complete raw conductance series and raw input bytes are excluded",output$rpk_contents$html,fixed=TRUE)&&grepl("bounded raw preview",output$rpk_contents$html,fixed=TRUE)&&grepl("does not calculate a new EDA-liking relationship",output$rpk_contents$html,fixed=TRUE),"Coverage preserves raw previews and refuses an invented new association")
})
scenario("independent component marker and table controls",{
 mock$prepared<-TRUE;eval(eda_setup);s<-section("eda-continuous");x<-list();x[[paste0("rpk_eda_components_",s$id)]]<-c("phasic_us","clean_us");x[[paste0("rpk_eda_markers_",s$id)]]<-"3, 1";x[[paste0("rpk_pages_",s$id)]]<-"2";do.call(session$setInputs,x)
 session$setInputs(rpk_prepare=1L);ack();r<-controller$state$intent$request;d<-Filter(function(s)s$adapter=="eda-continuous",r$requested_sections)[[1]]$display
 check(identical(d$components,list("clean_us","phasic_us"))&&identical(d$marker_pages,list(pages="selected",page_numbers=list(1L,3L)))&&identical(d$page_numbers,list(2L)),"Component order and marker pages normalize independently from numerical pages")
 check(!length(r$eda_display_requests)&&grepl("not the complete sample series",output$rpk_figures$html,fixed=TRUE),"Figure choices do not invent window overrides or claim display points are full samples")
 before<-mock$saves;x[[paste0("rpk_eda_components_",s$id)]]<-"tonic_us";do.call(session$setInputs,x);session$setInputs(rpk_prepare=2L)
 check(mock$saves==before&&grepl("Candidate marker pages require",controller$state$issue,fixed=TRUE),"A selected marker-page policy without phasic refuses rather than silently disappearing")
})
scenario("catalog keeps unavailable cells and support distinctions",{
 mock$prepared<-TRUE;eval(eda_setup)
 session$setInputs(rpk_selector_open=list(ref=rows[[1]]$ref,adapter="eda-events"));html<-output$rpk_selector$html
 check(grepl("Processed trace available",html,fixed=TRUE)&&grepl("response measurements: unavailable",html,fixed=TRUE)&&grepl("&lt;cell&gt;",html,fixed=TRUE),"Available traces retain separate unavailable response inference and escaped labels")
 session$setInputs(rpk_selector_open=list(ref=rows[[2]]$ref,adapter="eda-continuous"));session$setInputs(rpk_selector_next=1L);p<-controller$state$selector
 check(length(p$items)==1L&&grepl("No observed segment",output$rpk_selector$html,fixed=TRUE)&&!grepl("Change display window",output$rpk_selector$html,fixed=TRUE),"Unavailable no-segment cell remains a real catalog row without an invented editable window")
 session$setInputs(rpk_selector_choose=list(ref=rows[[2]]$ref,adapter="eda-continuous",selector=p$items[[1]]$selector))
 check(identical(section("eda-continuous")$selector$keys,list(key(3L))),"Unavailable saved cell can be selected for its honest explanatory panel")
})
scenario("exact windows persist independently and explicit reset",{
 mock$prepared<-TRUE;eval(eda_setup);before<-mock$saves;open_window()
 session$setInputs(rpk_eda_start="1.0",rpk_eda_end="2.0");session$setInputs(rpk_prepare=1L)
 check(mock$saves==before&&grepl("Apply or cancel",controller$state$issue,fixed=TRUE),"Unapplied window edits cannot silently enter Prepare")
 apply_window();w<-controller$state$eda_display_requests[[1]]$display_request$continuous_windows[[1]]
 check(brohn_eda_decimal_compare(w$start_s,"1")>0L&&brohn_eda_decimal_compare(w$end_s,"2")==0L&&mock$saves==before&&is.null(controller$state$window_editor),"Apply preserves a sub-double decimal difference without enqueueing")
 frozen<-brohn_json(controller$state$eda_display_requests);s<-section("eda-continuous");session$setInputs(rpk_section_remove=s$id)
 check(identical(frozen,brohn_json(controller$state$eda_display_requests)),"Removing the last continuous figure preserves the source window override")
 session$setInputs(rpk_selector_open=list(ref=rows[[2]]$ref,adapter="eda-continuous"));session$setInputs(rpk_selector_all=list(ref=rows[[2]]$ref,adapter="eda-continuous"));bind_eda()
 check(identical(frozen,brohn_json(controller$state$eda_display_requests)),"Selecting all cells again retains the original draft window override")
 open_window();old<-controller$state$eda_display_requests;apply_window("-1","2",2L)
 check(.brohn_rpv_same(old,controller$state$eda_display_requests)&&grepl("within this saved segment",controller$state$issue,fixed=TRUE),"Bounds outside the real original segment are rejected before any queue")
 session$setInputs(rpk_eda_window_cancel=1L);session$setInputs(rpk_eda_override_reset=list(ref=rows[[2]]$ref,key=key(1L)))
 check(identical(controller$state$eda_display_requests,list()),"Explicit reset removes an empty source sidecar using the shared normalizer")
 open_window();apply_window("1.00","2e0",3L);open_window();before<-brohn_json(controller$state$eda_display_requests);apply_window("10e-1","2.000",4L)
 check(identical(before,brohn_json(controller$state$eda_display_requests)),"Equivalent decimal spellings have the same durable exact request")
 session$setInputs(rpk_source_toggle=rows[[2]]$ref)
 check(!length(controller$state$eda_display_requests),"Explicit source removal removes only that source's override")
})
scenario("history pins exact prep and canonical request",{
 mock$prepared<-TRUE;eval(eda_setup);open_window();apply_window("1.00","2e0");bind_eda();session$setInputs(rpk_prepare=1L);ack();old<-controller$state$intent$request
 publish_view("needs_attention","review",prepared_summary(reason="panel_limit"),"Too many panels")
 session$setInputs(rpk_selector_open=list(ref=rows[[2]]$ref,adapter="eda-continuous"));session$setInputs(rpk_selector_next=1L)
 check(.brohn_rpv_same(tail(mock$catalog_reads,1)[[1]]$prepared_ref,eda_ref(rows[[2]]$ref)),"History/catalog requests pass the exact original EDA preparation")
 publish_view("needs_attention","review",prepared_summary(2L,"panel_limit"),"Too many panels")
 last<-tail(mock$catalog_reads,1)[[1]]
 check(is.null(last$cursor)&&.brohn_rpv_same(last$prepared_ref,eda_ref(rows[[2]]$ref,2L))&&.brohn_rpv_same(old,controller$state$intent$request),"Prepared-ref refresh resets only cursor, preserving requested windows and figure policies")
 session$setInputs(rpk_history_latest=1L);session$setInputs(rpk_history_open=controller$state$intent$intent_ref);bind_eda()
 check(!isTRUE(controller$state$dirty)&&.brohn_rpv_same(controller$state$eda_display_requests,old$eda_display_requests),"Historical hydration restores canonical windows without immediately marking them edited")
 before<-mock$saves;session$setInputs(rpk_prepare_new=1L);check(mock$saves==before,"Code-drift renewal paints before saving");ack()
 check(.brohn_rpv_same(old,controller$state$intent$request),"Explicit new-code review retains exact requested EDA policies")
 publish_view("needs_attention","review",list(prepared_sources=list()),"Prepared evidence unavailable")
 session$setInputs(rpk_selector_open=list(ref=rows[[2]]$ref,adapter="eda-continuous"))
 check(isTRUE(controller$state$selector$locked)&&is.null(controller$state$selector$prepared_ref),"Unavailable historical preparation refuses focused changes without latest fallback")
})
scenario("related-only evidence and legacy shape",{
 mock$prepared<-FALSE;eval(eda_setup);session$setInputs(rpk_enter=list(study_id="study",project_id="default",report_ref=rows[[3]]$ref));bind_eda()
 check(.brohn_rpv_eda_profile(.brohn_rpv_profiles(controller$state$rows)$renderer_profile),"A required-only EDA parent selects the complete EDA profile without adding automatic figures")
 session$setInputs(rpk_section_remove=controller$state$sections[[1]]$id)
 check(grepl("No figures selected; complete numerical evidence",output$rpk_figures$html,fixed=TRUE)&&grepl("Choose Saved comparisons",output$rpk_selected$html,fixed=TRUE),"Evidence-only view explains zero figures and retains a way to add them back")
 session$setInputs(rpk_prepare=1L);ack();check(!length(controller$state$intent$request$requested_sections)&&identical(controller$state$intent$request$eda_display_requests,list()),"EDA evidence-only request is valid with related sources on default windows")
 session$setInputs(rpk_enter=list(study_id="study",project_id="default",report_ref=rows[[4]]$ref));bind_eda();session$setInputs(rpk_prepare=2L);ack()
 check(!"eda_display_requests"%in%names(controller$state$intent$request)&&identical(controller$state$intent$request$renderer_profile,"controlled-gaze-explicit-task-paired/0.1"),"Legacy task-only request retains its exact old field shape and profile")
})
scenario("current download guard and stale window editor",{
 mock$prepared<-TRUE;eval(eda_setup);open_window();apply_window("1.000","2.0");bind_eda();session$setInputs(rpk_prepare=1L);ack()
 publish_view("ready_to_freeze","continue",prepared_summary());set_status("succeeded","download");ack()
 url<-controller$state$urls$html
 check(length(controller$state$urls)>0L&&!isTRUE(controller$state$dirty)&&download(url)$status==200L,"A canonical exact window request opens the existing guarded resource without false dirty state")
 open_window();session$setInputs(rpk_eda_start="1e0",rpk_eda_end="20e-1",rpk_eda_window_apply=2L)
 check(!isTRUE(controller$state$dirty)&&download(url)$status==200L,"Applying equivalent window spelling preserves a valid saved download")
 open_window();session$setInputs(rpk_eda_start="1.5",rpk_eda_end="2",rpk_eda_window_apply=3L)
 check(isTRUE(controller$state$dirty)&&download(url)$status==404L&&!length(controller$state$urls),"A changed window immediately revokes old report capabilities before new preparation")
 session$setInputs(rpk_prepare=2L);ack();publish_view("needs_attention","review",prepared_summary());open_window();token<-controller$state$window_editor$token;old<-brohn_json(controller$state$eda_display_requests)
 publish_view("needs_attention","review",prepared_summary(2L));session$setInputs(rpk_eda_window_identity=token,rpk_eda_start="1.6",rpk_eda_end="2",rpk_eda_window_apply=4L)
 check(is.null(controller$state$window_editor)&&identical(old,brohn_json(controller$state$eda_display_requests)),"Late window submission after a prepared-reference change cannot modify the current draft")
})
scenario("typed refusal recovery does not invent figure remedies",{
 mock$prepared<-FALSE;eval(eda_setup);session$setInputs(rpk_prepare=1L);ack()
 for(scope in c("fewer_sources","smaller_window","repair_source","new_preparation","none")){
  p<-prepared_summary();p$reason_code<-"eda_limit";p$source<-rows[[2]]$ref;p$resource<-"complete_stream_bytes";p$measured<-100000;p$maximum<-90000;p$recovery_scope<-scope;p$message<-"Original complete evidence exceeds this resource."
  publish_view("needs_attention","review",p,p$message);html<-output$rpk_feedback$html
  check(grepl("100000",html,fixed=TRUE)&&grepl("90000",html,fixed=TRUE)&&!grepl("choose fewer figure",html,fixed=TRUE),paste("Typed",scope,"refusal shows actual resource counts without a false fewer-figures suggestion"))
 }
})
scenario("cold metadata windows are editable without preparing figures",{
 mock$prepared<-FALSE;mock$window_authority<-TRUE;mock$window_foreign<-FALSE;eval(eda_setup);before<-mock$saves;full<-mock$full_reads
 session$setInputs(rpk_selector_open=list(ref=rows[[2]]$ref,adapter="eda-continuous"));p<-controller$state$selector;html<-output$rpk_selector$html
 check(!length(p$items)&&length(p$source_windows$items)==2L&&grepl("Original recording windows",html,fixed=TRUE)&&!grepl("Include this view",html,fixed=TRUE),"Cold source metadata exposes windows without invented focused figure choices")
 check(!grepl("Observed markers:",html,fixed=TRUE)&&!grepl("Processed trace available",html,fixed=TRUE)&&grepl("&lt;cell&gt;",html,fixed=TRUE),"Metadata-only rows show escaped original labels without prepared counts or trace claims")
 session$setInputs(rpk_selector_choose=list(ref=rows[[2]]$ref,adapter="eda-continuous",selector=list(scope="exact_cells",keys=list(key(1L)))))
 check(grepl("Choose an available saved view",controller$state$issue,fixed=TRUE)&&section("eda-continuous")$selector$scope=="all_cells","Forged focused-figure selection cannot use metadata-only keys")
 open_window();before_reads<-length(mock$window_reads);apply_window()
 check(length(mock$window_reads)==before_reads+1L&&mock$saves==before&&mock$full_reads==full&&isTRUE(controller$state$dirty),"Cold Apply rechecks bounded authorized metadata and changes only the draft")
 check(brohn_eda_decimal_compare(controller$state$eda_display_requests[[1]]$display_request$continuous_windows[[1]]$start_s,"1")>0L,"Cold original window editing retains exact sub-double decimal bounds")
 open_window();session$setInputs(rpk_eda_window_reset=1L)
 check(!length(controller$state$eda_display_requests)&&mock$saves==before,"Cold Reset restores original defaults without preparing any source")
 session$setInputs(rpk_selector_next=1L);p<-controller$state$selector
 check(identical(tail(mock$window_reads,1)[[1]]$cursor,"windows-page2")&&length(p$source_windows$items)==2L&&grepl("No observed segment",output$rpk_selector$html,fixed=TRUE),"Window paging uses the metadata cursor and retains unavailable original rows")
 session$setInputs(rpk_eda_window_open=list(ref=rows[[2]]$ref,key=key(3L)))
 check(is.null(controller$state$window_editor)&&grepl("no editable",controller$state$issue,fixed=TRUE),"Unavailable metadata cells cannot fabricate editable bounds")
 session$setInputs(rpk_selector_previous=1L)
 check(is.null(tail(mock$window_reads,1)[[1]]$cursor),"Previous windows restores the original bounded metadata page")
})
scenario("size refusal recovery creates a new draft and explicit intent",{
 mock$prepared<-FALSE;eval(eda_setup);session$setInputs(rpk_prepare=1L);ack()
 p<-list(prepared_sources=list(),reason_code="eda_limit",source=rows[[2]]$ref,resource="display_samples",measured=500100L,maximum=500000L,recovery_scope="smaller_window",message="The default display exceeds the sample limit.")
 publish_view("needs_attention","review",p,p$message);old_id<-saved();old<-brohn_json(mock$intents[[old_id]]$view);before<-mock$saves
 open_window();check(isTRUE(controller$state$selector$locked)&&!is.null(controller$state$window_editor)&&!is.null(controller$state$selector$source_windows),"A failed preparation without prepared_ref keeps figure choices locked but enables original-window recovery")
 apply_window("1.25","2.5")
 check(isTRUE(controller$state$dirty)&&identical(old,brohn_json(mock$intents[[old_id]]$view))&&mock$saves==before,"Apply after refusal leaves the entire saved failed intent unchanged")
 bind_eda();session$setInputs(rpk_prepare=2L)
 check(mock$saves==before&&identical(old,brohn_json(mock$intents[[old_id]]$view)),"Recovery Prepare paints before creating or superseding any intent")
 ack();fresh<-controller$state$intent$request
 check(saved()!=old_id&&mock$intents[[old_id]]$view$status=="superseded"&&length(fresh$eda_display_requests)==1L&&fresh$requested_sections[[2]]$selector$scope=="all_cells","Explicit recovery Prepare creates a new intent with exact window override and unchanged all-cell policy")
 check(!any(c("source_binding_hash","source_windows")%in%names(fresh))&&mock$full_reads==0L,"Metadata recovery does not add hidden request fields or load full signals")
})
scenario("metadata authority and stale bindings refuse without draft mutation",{
 mock$prepared<-FALSE;mock$window_authority<-TRUE;eval(eda_setup);open_window();before<-brohn_json(controller$state$eda_display_requests);before_saves<-mock$saves
 mock$window_generation<-mock$window_generation+1L;apply_window()
 check(identical(before,brohn_json(controller$state$eda_display_requests))&&grepl("source windows changed",controller$state$issue,fixed=TRUE),"A changed source-closure binding refuses a stale window submission")
 session$setInputs(rpk_eda_window_cancel=1L);open_window();mock$window_authority<-FALSE;apply_window("1","2",2L)
 check(identical(before,brohn_json(controller$state$eda_display_requests))&&grepl("no longer accessible",controller$state$issue,fixed=TRUE)&&mock$saves==before_saves,"Revoked current source access blocks Apply before any new request")
 mock$window_authority<-TRUE;session$setInputs(rpk_eda_window_cancel=2L);open_window();token<-controller$state$window_editor$token
 session$setInputs(rpk_eda_window_identity=paste0(token,"stale"),rpk_eda_window_apply=3L)
 check(identical(before,brohn_json(controller$state$eda_display_requests))&&grepl("Reopen the current",controller$state$issue,fixed=TRUE),"A stale editor token cannot alter source windows")
 session$setInputs(rpk_eda_window_cancel=3L);foreign<-rows[[2]]$ref;foreign$project_id<-"other"
 session$setInputs(rpk_selector_open=list(ref=foreign,adapter="eda-continuous"))
 check(grepl("supported selected report",controller$state$issue,fixed=TRUE)&&mock$saves==before_saves,"A foreign-project source cannot open original window metadata")
 mock$window_foreign<-TRUE;session$setInputs(rpk_selector_open=list(ref=rows[[2]]$ref,adapter="eda-continuous"))
 check(grepl("do not match",controller$state$issue,fixed=TRUE),"Returned metadata for a different exact report is refused")
 mock$window_foreign<-FALSE
 p<-list(resource="display_samples",source=ref("unselected-related-eda"),recovery_scope="smaller_window")
 html<-as.character(.brohn_rpv_eda_refusal(p,rows[3]))
 check(grepl("Add that exact saved parent report",html,fixed=TRUE)&&grepl("Related sources that are not selected",html,fixed=TRUE),"Related-only refusal explains explicit parent selection instead of offering an unsaveable hidden override")
})
scenario("single complete-source capacity refusal blocks ineffective retries and preserves history",{
 mock$prepared<-TRUE;mock$window_authority<-TRUE;eval(eda_setup)
 session$setInputs(rpk_enter=list(study_id="study",project_id="default",report_ref=rows[[2]]$ref));bind_eda()
 session$setInputs(rpk_prepare=1L);ack()
 p<-list(prepared_sources=list(list(adapter="eda-display",source_report_ref=rows[[2]]$ref,prepared_ref=eda_ref(rows[[2]]$ref))),
  reason_code="eda_limit",source=NULL,resource="projection_bytes",measured=201416771,maximum=201326592,recovery_scope="fewer_sources",message="Complete evidence exceeds the report projection budget.")
 publish_view("needs_attention","review",p,p$message);old_id<-saved();old_ref<-controller$state$intent$intent_ref;old<-brohn_json(mock$intents[[old_id]]$view)
 before<-mock$saves;advanced<-mock$advances;html<-output$rpk_feedback$html
 check(grepl("This saved source's complete evidence exceeds",html,fixed=TRUE)&&grepl("Back to study",html,fixed=TRUE)&&!grepl("Choose fewer saved sources",html,fixed=TRUE),"Single-source capacity guidance identifies the unsatisfiable complete evidence and original exports, without a fewer-sources instruction")
 check(is.null(output$rpk_prepare_action)&&!grepl('id="rpk_prepare_new"',html,fixed=TRUE)&&!grepl('id="rpk_resume"',html,fixed=TRUE),"Single-source refusal removes persistent Prepare, new-version and resume actions")
 for(input_id in c("rpk_prepare","rpk_prepare_new","rpk_resume"))do.call(session$setInputs,setNames(list(9L),input_id))
 check(mock$saves==before&&mock$advances==advanced&&is.null(controller$state$pending)&&identical(old,brohn_json(mock$intents[[old_id]]$view)),"Stale direct Prepare/new-version/resume events cannot save, queue or rewrite the failed single-source intent")
 session$setInputs(rpk_title="A new title cannot shrink original evidence")
 check(is.null(output$rpk_prepare_action)&&!grepl("Prepare them to create",output$rpk_feedback$html,fixed=TRUE),"A title-only edit does not offer an ineffective preparation")
 session$setInputs(rpk_section_remove=controller$state$sections[[1]]$id)
 check(is.null(output$rpk_prepare_action)&&length(controller$state$sections)==0L,"Hiding every figure does not unlock complete-source capacity")
 open_window();apply_window("1","2")
 check(is.null(output$rpk_prepare_action)&&length(controller$state$eda_display_requests)==1L&&identical(old,brohn_json(mock$intents[[old_id]]$view)),"A smaller display changes the draft without claiming capacity recovery or rewriting failed history")
 session$setInputs(rpk_source_toggle=rows[[1]]$ref);bind_eda()
 check(length(controller$state$rows)==2L&&is.null(output$rpk_prepare_action),"Adding another source cannot bypass the known offending single-source bound")
 session$setInputs(rpk_history_open=old_ref);bind_eda()
 check(length(controller$state$rows)==1L&&is.null(output$rpk_prepare_action)&&identical(old,brohn_json(mock$intents[[old_id]]$view))&&!isTRUE(controller$state$dirty),"Reopening the historical failed intent restores exact choices and the same capacity guidance without mutation")
 session$setInputs(rpk_source_toggle=rows[[1]]$ref);bind_eda();session$setInputs(rpk_source_toggle=rows[[2]]$ref);bind_eda()
 check(length(controller$state$rows)==1L&&.brohn_rpv_same(controller$state$rows[[1]]$ref,rows[[1]]$ref)&&grepl('id="rpk_prepare"',output$rpk_prepare_action$html,fixed=TRUE),"Replacing the exact offending source restores ordinary preparation controls")
 session$setInputs(rpk_prepare=10L);ack()
 check(mock$saves==before+1L&&saved()!=old_id&&mock$intents[[old_id]]$view$status=="superseded","Explicit preparation after source replacement creates one new intent through the existing lifecycle")
})
scenario("multiple-source budgets and old smaller-window history keep valid recovery",{
 mock$prepared<-TRUE;eval(eda_setup);session$setInputs(rpk_prepare=1L);ack()
 p<-list(prepared_sources=list(),reason_code="eda_limit",source=NULL,resource="projection_bytes",measured=201416771,maximum=201326592,recovery_scope="fewer_sources",message="Complete evidence exceeds the report projection budget.")
 publish_view("needs_attention","review",p,p$message);before<-mock$saves;html<-output$rpk_feedback$html
 check(grepl("Choose fewer saved sources",html,fixed=TRUE)&&grepl('id="rpk_prepare_new"',html,fixed=TRUE)&&grepl('id="rpk_prepare"',output$rpk_prepare_action$html,fixed=TRUE),"A genuine multiple-source refusal retains its applicable fewer-sources recovery")
 session$setInputs(rpk_source_toggle=rows[[1]]$ref);bind_eda();session$setInputs(rpk_prepare=2L);ack()
 check(mock$saves==before+1L&&length(controller$state$intent$request$report_refs)==1L,"Removing a source from a multi-source refusal can prepare the reduced request")
 p$resource<-"display_samples";p$measured<-500100;p$maximum<-500000;p$recovery_scope<-"smaller_window";p$source<-rows[[2]]$ref;p$message<-"The default display exceeds the sample limit."
 publish_view("superseded","none",p,p$message);old<-brohn_json(controller$state$intent);old_ref<-controller$state$intent$intent_ref
 session$setInputs(rpk_enter=list(study_id="study",project_id="default",report_ref=rows[[1]]$ref));bind_eda();session$setInputs(rpk_history_open=old_ref);bind_eda()
 check(grepl("Change display window",output$rpk_feedback$html,fixed=TRUE)&&grepl('id="rpk_prepare"',output$rpk_prepare_action$html,fixed=TRUE),"Superseded original smaller-window history retains applicable window guidance and ordinary Prepare")
 open_window();session$setInputs(rpk_eda_window_cancel=1L)
 check(identical(old,brohn_json(controller$state$intent))&&is.null(controller$state$window_editor),"Opening and cancelling the original window editor does not alter saved historical choices or failure")
})
scenario("stale resume after source replacement still binds the original refused intent",{
 mock$prepared<-TRUE;eval(eda_setup)
 session$setInputs(rpk_enter=list(study_id="study",project_id="default",report_ref=rows[[2]]$ref));bind_eda()
 session$setInputs(rpk_prepare=1L);ack()
 p<-list(prepared_sources=list(),reason_code="eda_limit",source=NULL,resource="projection_bytes",measured=201416771,maximum=201326592,recovery_scope="fewer_sources",message="Complete evidence exceeds the report projection budget.")
 publish_view("needs_attention","review",p,p$message);old_id<-saved()
 session$setInputs(rpk_cancel=1L);old<-brohn_json(mock$intents[[old_id]]$view);before<-mock$saves;advanced<-mock$advances
 check(controller$state$intent$status=="cancelled"&&controller$state$intent$next_action=="retry","Normal cancellation retains the old capacity refusal on a retryable historical intent")
 session$setInputs(rpk_source_toggle=rows[[1]]$ref);bind_eda();session$setInputs(rpk_source_toggle=rows[[2]]$ref);bind_eda()
 check(grepl('id="rpk_prepare"',output$rpk_prepare_action$html,fixed=TRUE),"Replacing the oversized source enables preparation of the new draft")
 session$setInputs(rpk_resume=1L)
 if(!is.null(controller$state$pending))ack()else session$setInputs(rpk_prepare_ack="stale-original-resume")
 check(mock$saves==before&&mock$advances==advanced&&is.null(controller$state$pending)&&identical(old,brohn_json(mock$intents[[old_id]]$view)),"A stale Resume event after replacement cannot restart or mutate the original oversized intent")
 session$setInputs(rpk_prepare=2L);ack()
 check(mock$saves==before+1L&&mock$advances==advanced+1L&&saved()!=old_id&&.brohn_rpv_same(controller$state$intent$request$report_refs,list(rows[[1]]$ref)),"Ordinary Prepare still creates one new intent for the replacement source after stale Resume refusal")
})
scenario("new profile choice and exact old intent reopening",{
 mock$prepared<-TRUE;eval(eda_setup);session$setInputs(rpk_prepare=1L);ack();id<-saved()
 check(controller$state$intent$request$renderer_profile=="controlled-gaze-explicit-task-choice-eda-paired/0.2","A new old-science-only EDA package explicitly uses renderer 0.2")
 old<-mock$intents[[id]];old$request$renderer_profile<-"controlled-gaze-explicit-task-choice-eda-paired/0.1";old$view$request<-old$request;old$view$status<-"needs_attention";old$view$next_action<-"review";mock$intents[[id]]<-old
 session$setInputs(rpk_history_open=old$view$intent_ref);bind_eda();before<-mock$saves;advanced<-mock$advances
 check(controller$state$intent$request$renderer_profile=="controlled-gaze-explicit-task-choice-eda-paired/0.1"&&!isTRUE(controller$state$dirty)&&mock$saves==before,"Opening exact historical 0.1 choices does not migrate or mark them unsaved")
 session$setInputs(rpk_prepare_new=1L);ack()
 check(mock$saves==before+1L&&mock$advances==advanced+1L&&controller$state$intent$request$renderer_profile=="controlled-gaze-explicit-task-choice-eda-paired/0.2"&&mock$intents[[id]]$request$renderer_profile=="controlled-gaze-explicit-task-choice-eda-paired/0.1","Explicit new-version action creates 0.2 while keeping the original request's 0.1 identity")
})
coordinate_failure<-function(source=NULL)list(prepared_sources=list(),reason_code="coordinate_rows_limit",source=source,resource="coordinate_rows",measured=500100,maximum=500000,recovery_scope="none",message="The complete constant-signal coordinate view exceeds current capacity; a smaller response window is not a repair.")
scenario("constant coordinate limit blocks ineffective edits and stale original resume",{
 mock$prepared<-TRUE;eval(eda_setup);session$setInputs(rpk_enter=list(study_id="study",project_id="default",report_ref=rows[[2]]$ref));bind_eda();session$setInputs(rpk_prepare=1L);ack()
 p<-coordinate_failure(rows[[2]]$ref);publish_view("needs_attention","review",p,p$message);session$setInputs(rpk_cancel=1L)
 old_id<-saved();old<-brohn_json(mock$intents[[old_id]]$view);before<-mock$saves;advanced<-mock$advances
 check(is.null(output$rpk_prepare_action)&&!grepl('id="rpk_prepare_new"',output$rpk_feedback$html,fixed=TRUE)&&!grepl('id="rpk_resume"',output$rpk_feedback$html,fixed=TRUE)&&grepl("separate evidence exports",output$rpk_feedback$html,fixed=TRUE),"Constant coordinate refusal hides ineffective actions and points to original evidence exports")
 session$setInputs(rpk_title="Different title");session$setInputs(rpk_section_remove=controller$state$sections[[1]]$id);open_window();apply_window("1","2")
 check(is.null(output$rpk_prepare_action)&&identical(old,brohn_json(mock$intents[[old_id]]$view)),"Title, hidden figures and synthetic stale window edits cannot change constant capacity or saved history")
 session$setInputs(rpk_source_toggle=rows[[1]]$ref);bind_eda()
 check(is.null(output$rpk_prepare_action),"Adding another source does not evade a known single-source constant bound")
 for(input_id in c("rpk_prepare","rpk_prepare_new","rpk_resume"))do.call(session$setInputs,setNames(list(9L),input_id))
 check(mock$saves==before&&mock$advances==advanced&&is.null(controller$state$pending),"Stale direct actions cannot queue the unchanged constant source")
 session$setInputs(rpk_source_toggle=rows[[2]]$ref);bind_eda();session$setInputs(rpk_resume=10L)
 check(mock$saves==before&&mock$advances==advanced&&is.null(controller$state$pending)&&identical(old,brohn_json(mock$intents[[old_id]]$view)),"Removing the source still cannot resume the original refused intent")
 session$setInputs(rpk_prepare=10L);ack()
 check(mock$saves==before+1L&&saved()!=old_id&&.brohn_rpv_same(controller$state$intent$request$report_refs,list(rows[[1]]$ref)),"A replacement source can explicitly create a different report")
})
scenario("required constant parent and multiple-source recovery remain precise",{
 mock$prepared<-TRUE;eval(eda_setup);session$setInputs(rpk_enter=list(study_id="study",project_id="default",report_ref=rows[[3]]$ref));bind_eda();session$setInputs(rpk_prepare=1L);ack()
 p<-coordinate_failure(rows[[2]]$ref);publish_view("needs_attention","review",p,p$message)
 check(is.null(output$rpk_prepare_action)&&grepl("paired report can require",output$rpk_feedback$html,fixed=TRUE),"A sole paired source cannot retry a capacity failure of its required parent")
 session$setInputs(rpk_enter=list(study_id="study",project_id="default",report_ref=NULL));bind_eda();session$setInputs(rpk_prepare=2L);ack();publish_view("needs_attention","review",p,p$message)
 check(length(controller$state$rows)==2L&&is.null(output$rpk_prepare_action),"Multiple-source constant refusal blocks the unchanged selected source set")
 session$setInputs(rpk_title="Still the same sources");check(is.null(output$rpk_prepare_action),"A title change does not unlock a multiple-source coordinate refusal")
 before<-mock$saves;session$setInputs(rpk_source_toggle=rows[[2]]$ref);bind_eda();session$setInputs(rpk_prepare=3L);ack()
 check(mock$saves==before+1L&&length(controller$state$intent$request$report_refs)==1L,"Changing the selected source set can create a new report after a multiple-source refusal")
 p$reason_code<-"another_error";publish_view("needs_attention","review",p,p$message)
 check(!is.null(output$rpk_prepare_action),"Unrelated recovery_scope none errors are not blanket-blocked")
 p<-coordinate_failure();p$maximum<-600000;publish_view("needs_attention","review",p,p$message)
 check(!is.null(output$rpk_prepare_action),"An unregistered coordinate limit is not mistaken for the exact current constant capacity rule")
})
scenario("new EDA profile cannot substitute latest explicit distribution for absent pinned history",{
 original_rows<-rows;rows[[2]]$adapters<<-list("eda-continuous","explicit-distribution")
 tryCatch({mock$prepared<-TRUE;eval(eda_setup);session$setInputs(rpk_prepare=1L);ack();before<-length(mock$catalog_reads)
  session$setInputs(rpk_selector_open=list(ref=rows[[2]]$ref,adapter="explicit-distribution"))
  check(isTRUE(controller$state$selector$locked)&&length(mock$catalog_reads)==before&&controller$state$intent$request$renderer_profile=="controlled-gaze-explicit-task-choice-eda-paired/0.2","Saved 0.2 explicit choices without their pinned prerequisite stay locked instead of reading a current distribution")
 },finally={rows<<-original_rows})
})
brohn_write_json_file(list(passed=all(vapply(scenarios,`[[`,logical(1),"passed")),checks=checks,scenarios=scenarios,
 source_hashes=setNames(lapply(c("platform-report-package-views.R","platform-report-package-server.R"),function(f)digest::digest(file=file.path(candidate,f),algo="sha256")),c("views","server")),
 support_hashes=support_receipt,
 scope="EDA controller/views with explicit bounded metadata, intent and resource spies; real shared pure decimal and sidecar normalizers. No scientific source preparation, native authority, worker or browser qualification."),file.path(folder,"results.json"))
if(any(!vapply(scenarios,`[[`,logical(1),"passed")))quit(status=1L)
