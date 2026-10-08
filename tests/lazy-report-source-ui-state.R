# Portable Shiny controller contract tests using explicit in-memory backend spies.
# Rscript tests/report-package-ui-state.R <source-root> <fresh-evidence-directory>
# External packet alternative: <packet-directory> <fresh-evidence-directory> <loader-root>
args<-commandArgs(TRUE);stopifnot(length(args)%in%c(2L,3L))
root<-normalizePath(args[[1]],winslash="/",mustWork=TRUE)
loader<-if(length(args)==3L)normalizePath(args[[3]],winslash="/",mustWork=TRUE)else root
candidate<-if(file.exists(file.path(root,"R","platform-report-package-server.R")))file.path(root,"R")else root
stopifnot(file.exists(file.path(loader,"R","platform-load.R")))
folder<-args[[2]];stopifnot(!file.exists(folder));dir.create(folder,recursive=TRUE)
folder<-normalizePath(folder,winslash="/",mustWork=TRUE)
setwd(loader);source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=TRUE)
for(f in c("platform-report-package-source-catalog.R","platform-report-package-views.R","platform-report-package-server.R"))source(file.path(candidate,f),encoding="UTF-8")
checks<-list();scenarios<-list();check<-function(ok,label){checks[[length(checks)+1L]]<<-list(label=label,passed=isTRUE(ok));cat(if(isTRUE(ok))"PASS"else"FAIL",label,"\n");if(!isTRUE(ok))stop(label,call.=FALSE)}
mock<-new.env();mock$intents<-list();mock$saves<-0L;mock$advances<-0L;mock$opens<-0L;mock$releases<-0L;mock$authority<-TRUE;mock$reader<-TRUE;mock$session_checks<-0L;mock$current_reads<-0L;mock$cancels<-0L;mock$lookups<-list()
ref<-function(id,kind="report",revision=1L)list(kind=kind,id=id,revision=revision,body_hash=brohn_hash(list(id,revision)),project_id="default")
rows<-list(list(ref=ref("gaze-original"),title="Saved controlled gaze",origin="sample",kind="gaze",design_hash="design-old",adapters=list("gaze-context","paired-findings"),status="available",reason=NULL),
 list(ref=ref("liking-original"),title="Saved explicit liking",origin="sample",kind="questionnaire",design_hash="design-old",adapters=list("explicit-distribution","paired-findings"),status="available",reason=NULL),
 list(ref=ref("gaze-history",revision=2L),title="Earlier gaze report",origin="sample",kind="gaze",design_hash="design-older",adapters=list("gaze-context"),status="available",reason=NULL),
 list(ref=ref("combined-original"),title="Reviewed combined report",origin="sample",kind="multimodal",design_hash="design-older",adapters=list("paired-findings"),status="available",reason=NULL))
mock$recommendations<-list();mock$choice_failure<-FALSE;mock$scope_refusal<-FALSE;mock$after_full_scope_refusal<-FALSE
.brohn_rpk_study<-function(store,id,project_id){stopifnot(mock$authority,mock$reader,identical(id,"study"),identical(project_id,"default"));list(id=id,project_id=project_id,body=list(title="Study"))}
.brohn_rpk_choice_descriptor<-function(store,ref,study_id,project_id){
 .brohn_rpk_study(store,study_id,project_id);stopifnot(!mock$scope_refusal)
 found<-Filter(function(r).brohn_rpv_same(r$ref,ref),rows);stopifnot(length(found)==1L)
 row<-found[[1]];list(schema="brohn-report-package-choice-descriptor/0.1",ref=ref,title=row$title,origin=row$origin,availability="unchecked")}
brohn_report_package_choice_descriptors<-function(store,study_id,project_id,cursor=NULL,limit=25L){
 .brohn_rpk_study(store,study_id,project_id)
 list(study=list(id=study_id,title="Original packaging study",project_id=project_id),
  reports=lapply(if(is.null(cursor))rows[1:2]else rows[3],function(r).brohn_rpk_choice_descriptor(store,r$ref,study_id,project_id)),
  cursor=cursor,next_cursor=if(is.null(cursor))"page2"else NULL,recommended_refs=list(),needs_choice=TRUE)}
brohn_hosted_require_session<-function(store){mock$session_checks<-mock$session_checks+1L;stopifnot(mock$reader)}
brohn_report_package_choices<-function(store,study_id,project_id,cursor=NULL,limit=25L)list(study=list(id=study_id,title="Original packaging study",project_id=project_id),reports=if(is.null(cursor))rows[1:2]else rows[3],cursor=cursor,next_cursor=if(is.null(cursor))"page2"else NULL,recommended_refs=lapply(rows[1:2],`[[`,"ref"),needs_choice=FALSE)
brohn_report_package_report_choice<-function(store,report_ref){mock$lookups<-c(mock$lookups,list(report_ref));if(mock$choice_failure)stop("Original retained source is unavailable. Restore its original data.",call.=FALSE);if(mock$after_full_scope_refusal)mock$scope_refusal<-TRUE;found<-Filter(function(r).brohn_rpv_same(r$ref,report_ref),rows);stopifnot(length(found)==1L);row<-found[[1]]
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
scenario<-function(label,code){mock$authority<-TRUE;mock$reader<-TRUE;mock$choice_failure<-FALSE;mock$scope_refusal<-FALSE;mock$after_full_scope_refusal<-FALSE;cat("SCENARIO",label,"\n");failure<-NULL
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

ready<-quote({
 session$setInputs(rpk_enter=list(study_id="study",project_id="default",report_ref=rows[[1]]$ref));bind()
 session$setInputs(rpk_prepare=1L);ack();set_status("succeeded","download");ack()
 check(identical(controller$state$phase,"ready")&&length(controller$state$urls)>0L,"Controlled original ready report is held")
})
editor_fixture<-function(kind){
 if(identical(kind,"window_editor"))return(list(token="original-window",ref=rows[[1]]$ref,key="controlled-cell",label="Controlled recording",
  bounds=list(start_s="0",end_s="10"),requested=list(start_s="0",end_s="10")))
 list(token="original-cardiac",ref=rows[[1]]$ref,cell=list(source_record_index=1L,identity=list(recording="controlled"),focusable=TRUE,
  original_bounds=list(start_s="0",end_s="10")),choice=list(time_focus=NULL,waveform_windows=list(mode="first",numbers=list()),
  marker_pages=list(mode="first",numbers=list()),interval_pages=list(mode="first",numbers=list()),numerical_pages=list(mode="first",numbers=list())))
}
scenario("entry is unchecked and does not walk source bodies",{
 before<-length(mock$lookups);eval(setup)
 check(length(mock$lookups)==before&&!length(controller$state$rows),"Catalogue entry invokes no complete source admission and selects no unverified source")
 html<-output$rpk_sources$html
 check(grepl("Add",html,fixed=TRUE)&&grepl("checked",html,fixed=TRUE),"Unchecked cards explain validation and offer the simple Add action")
 n<-mock$saves;session$setInputs(rpk_source_toggle=rows[[1]]$ref);ticket<-controller$state$pending$ticket
 check(identical(controller$state$phase,"preparing")&&length(mock$lookups)==before&&mock$saves==n,"Add creates pending feedback before source reads or writes")
 session$setInputs(rpk_source_toggle=rows[[1]]$ref)
 check(identical(ticket,controller$state$pending$ticket),"Duplicate Add joins the same pending selection")
 session$setInputs(rpk_prepare_ack="stale")
 check(length(mock$lookups)==before&&!length(controller$state$rows),"A stale acknowledgement adopts nothing")
 ack();check(length(mock$lookups)==before+1L&&length(controller$state$rows)==1L&&.brohn_rpv_same(controller$state$rows[[1]]$ref,rows[[1]]$ref),"Matching acknowledgement performs original source admission for the exact selected revision")
 check(mock$saves==n&&length(controller$state$sections)>0L,"Adding supported findings creates ordinary figure choices without creating a job")
})
scenario("replacement, paging and navigation reject old tickets",{
 eval(setup);before<-length(mock$lookups)
 session$setInputs(rpk_source_toggle=rows[[1]]$ref);old<-controller$state$pending$ticket
 session$setInputs(rpk_source_toggle=rows[[2]]$ref);new<-controller$state$pending$ticket
 session$setInputs(rpk_prepare_ack=old)
 check(!identical(old,new)&&length(mock$lookups)==before,"Replacing Add rejects the first ticket before any full source walk")
 session$setInputs(rpk_sources_next=1L);session$setInputs(rpk_prepare_ack=new)
 check(is.null(controller$state$pending)&&!length(controller$state$rows)&&length(mock$lookups)==before,"Changing the source page cancels its pending selection")
 session$setInputs(rpk_source_toggle=rows[[3]]$ref);ticket<-controller$state$pending$ticket
 state$page<-"home";session$flushReact();session$setInputs(rpk_prepare_ack=ticket)
 check(is.null(controller$state$scope)&&length(mock$lookups)==before,"Leaving the report makes a later acknowledgement inert")
})
scenario("raw invalid edits cannot be overwritten",{
 eval(setup);before<-length(mock$lookups)
 session$setInputs(rpk_source_toggle=rows[[1]]$ref);ticket<-controller$state$pending$ticket
 session$setInputs(rpk_title="");session$setInputs(rpk_prepare_ack=ticket)
 check(identical(input$rpk_title,"")&&is.null(controller$state$pending)&&!length(controller$state$rows)&&length(mock$lookups)==before,"An invalid title cancels selection and remains the user's unmodified input")
 session$setInputs(rpk_source_toggle=rows[[1]]$ref)
 check(is.null(controller$state$pending)&&length(mock$lookups)==before,"Add cannot hide an invalid draft behind source validation")
 session$setInputs(rpk_title="Edited report");session$setInputs(rpk_source_toggle=rows[[1]]$ref);ack()
 check(identical(controller$state$draft$title,"Edited report")&&length(controller$state$rows)==1L,"A deliberate new Add retains the corrected draft")
})
scenario("cancel and failed admission retain the exact current report",{
 eval(setup);eval(ready)
 before<-list(draft=controller$state$draft,rows=controller$state$rows,sections=controller$state$sections,intent=controller$state$intent,
  urls=controller$state$urls,opened=controller$state$opened,releases=mock$releases,saves=mock$saves,cancels=mock$cancels)
 session$setInputs(rpk_source_toggle=rows[[2]]$ref);ticket<-controller$state$pending$ticket
 session$setInputs(rpk_cancel=1L);session$setInputs(rpk_prepare_ack=ticket)
 check(identical(controller$state$phase,"ready")&&identical(controller$state$urls,before$urls)&&mock$releases==before$releases&&mock$cancels==before$cancels,"Cancelling only Add preserves the original handle, download URLs and saved preparation")
 mock$choice_failure<-TRUE;session$setInputs(rpk_source_toggle=rows[[2]]$ref);ack()
 check(identical(controller$state$draft,before$draft)&&identical(controller$state$rows,before$rows)&&identical(controller$state$sections,before$sections)&&identical(controller$state$intent,before$intent)&&identical(controller$state$opened,before$opened),"Original admission failure leaves the current contents, policies, intent and opened identity exact")
 check(identical(controller$state$urls,before$urls)&&mock$releases==before$releases&&mock$saves==before$saves&&download(before$urls$html)$status==200L,"Preserved download still passes the ordinary fresh reader check; no job was created")
 check(grepl("Restore its original data",output$rpk_sources$html,fixed=TRUE),"The failed source card shows its original actionable reason")
 lookups<-length(mock$lookups);mock$choice_failure<-FALSE;session$setInputs(rpk_source_toggle=rows[[2]]$ref);ack()
 check(length(mock$lookups)==lookups+1L&&length(controller$state$rows)==2L&&!length(controller$state$source_outcomes),"Retry Add validates afresh, adopts the exact source and clears only its failure outcome")
 check(!length(controller$state$urls)&&mock$releases==before$releases+1L,"Successful source change releases the prior report so it cannot represent the new draft")
})
scenario("original scope must still hold at acknowledgement and after full read",{
 eval(setup);before<-length(mock$lookups);session$setInputs(rpk_source_toggle=rows[[1]]$ref);mock$scope_refusal<-TRUE;ack()
 check(!length(controller$state$rows)&&length(mock$lookups)==before,"A changed historical study/project scope refuses before full source admission")
 mock$scope_refusal<-FALSE;session$setInputs(rpk_source_toggle=rows[[1]]$ref);mock$after_full_scope_refusal<-TRUE;ack()
 check(!length(controller$state$rows)&&length(mock$lookups)==before+1L,"A scope change during full source reading is caught before adoption")
})
scenario("authority revocation cannot preserve a former download",{
 eval(setup);eval(ready);url<-controller$state$urls$html;releases<-mock$releases
 session$setInputs(rpk_source_toggle=rows[[2]]$ref);mock$authority<-FALSE;ack()
 check(identical(controller$state$phase,"failed")&&!length(controller$state$urls)&&mock$releases==releases+1L,"Revoked study/project authority releases the current held report")
 check(download(url)$status==404L,"A formerly issued URL cannot retain access after authority failure")
})
scenario("pending recording edits block stale Add actions",{
 eval(setup);before<-length(mock$lookups)
 for(editor in c("window_editor","cardiac_editor")){
  original<-editor_fixture(editor)
  controller$state[[editor]]<-original;session$setInputs(rpk_source_toggle=rows[[1]]$ref)
  check(identical(controller$state[[editor]],original)&&is.null(controller$state$pending)&&length(mock$lookups)==before,paste(editor,"survives Add with no source work"))
  controller$state[[editor]]<-NULL
 }
})
scenario("recording editors opened after Add keep their unapplied input",{
 eval(setup);before<-length(mock$lookups)
 for(editor in c("window_editor","cardiac_editor")){
  session$setInputs(rpk_source_toggle=rows[[1]]$ref);ticket<-controller$state$pending$ticket
  original<-editor_fixture(editor)
  controller$state[[editor]]<-original
  if(editor=="window_editor")session$setInputs(rpk_eda_start="not-yet-valid")else session$setInputs(rpk_cardiac_focus_start="not-yet-valid")
  session$setInputs(rpk_prepare_ack=ticket)
  check(identical(controller$state[[editor]],original)&&is.null(controller$state$pending)&&!length(controller$state$rows)&&length(mock$lookups)==before,
   paste(editor,"opened after pending Add survives acknowledgement without admission or adoption"))
  check(identical(if(editor=="window_editor")input$rpk_eda_start else input$rpk_cardiac_focus_start,"not-yet-valid"),
   paste(editor,"retains its unapplied invalid input"))
  controller$state[[editor]]<-NULL
 }
})
scenario("unavailable selected sources remain removable",{
 eval(setup);session$setInputs(rpk_source_toggle=rows[[1]]$ref);ack();bind()
 selected<-controller$state$rows;selected[[1]]$adapters<-list();selected[[1]]$reason<-"Original source unavailable"
 html<-as.character(brohn_report_package_sources_ui(controller$state$choices,selected))
 check(grepl("Remove",html,fixed=TRUE),"Remove takes precedence over the selected source's missing adapters")
 controller$state$rows<-selected;before<-length(mock$lookups);session$setInputs(rpk_source_toggle=rows[[1]]$ref)
 check(!length(controller$state$rows)&&!length(controller$state$sections)&&length(mock$lookups)==before,"Removing an unavailable selection does not require reading its unavailable source")
})
scenario("legacy direct entry retains original complete source path",{
 eval(setup);before<-length(mock$lookups);session$setInputs(rpk_enter=list(study_id="study",project_id="default",report_ref=rows[[1]]$ref));bind()
 check(length(mock$lookups)==before+1L&&.brohn_rpv_same(controller$state$rows[[1]]$ref,rows[[1]]$ref)&&length(controller$state$sections)>0L,"Direct report entry retains the original source admission and original default sections")
})
brohn_write_json_file(list(passed=all(vapply(scenarios,`[[`,logical(1),"passed")),checks=checks,scenarios=scenarios,
 source_hashes=setNames(lapply(c("platform-report-package-source-catalog.R","platform-report-package-views.R","platform-report-package-server.R"),function(f)digest::digest(file=file.path(candidate,f),algo="sha256")),c("catalog","views","server")),
 scope="Actual Shiny controller with explicit original-derived authority/source/resource spies; no native sealed report, scientific source validation, browser paint, actual cancellation during synchronous R, worker or speed claim."),file.path(folder,"results.json"))
if(any(!vapply(scenarios,`[[`,logical(1),"passed")))quit(status=1L)
