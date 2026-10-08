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
mock$recommendations<-list()
# Controlled catalogue-only seams. These rows confer no scientific admission.
# The real new admission wrapper still calls the original full-choice spy below.
mock$descriptor_reads<-0L;mock$descriptor_checks<-0L;mock$project_authority<-TRUE
.brohn_rpk_study<-function(store,id,project_id){
 stopifnot(mock$project_authority,mock$reader,identical(id,"study"),identical(project_id,"default"))
 list(id=id,project_id=project_id,body=list(title="Study"))}
.brohn_rpk_choice_descriptor<-function(store,ref,study_id,project_id,allow_unavailable=FALSE){
 .brohn_rpk_study(store,study_id,project_id);mock$descriptor_checks<-mock$descriptor_checks+1L
 found<-Filter(function(r).brohn_rpv_same(r$ref,ref),rows);stopifnot(length(found)==1L)
 row<-found[[1]];list(schema="brohn-report-package-choice-descriptor/0.1",ref=ref,
  title=row$title,origin=row$origin,availability="unchecked",reason=NULL)}
brohn_report_package_choice_descriptors<-function(store,study_id,project_id,cursor=NULL,limit=25L){
 .brohn_rpk_study(store,study_id,project_id);mock$descriptor_reads<-mock$descriptor_reads+1L
 stopifnot(identical(limit,25L),is.null(cursor)||identical(cursor,"page2"))
 list(schema="brohn-report-package-choice-page/0.1",
  study=list(id=study_id,title="Original packaging study",project_id=project_id),
  reports=lapply(if(is.null(cursor))rows[1:2]else rows[3],function(r).brohn_rpk_choice_descriptor(store,r$ref,study_id,project_id)),
  cursor=cursor,next_cursor=if(is.null(cursor))"page2"else NULL,recommended_refs=list(),needs_choice=TRUE)}
# This deliberately populated fixture uses direct report entry and the unchanged
# full-choice recommendation spy. Ordinary descriptor-only entry remains empty.
# Restore recommendations before other scenarios/direct entries can observe them.
fixture_enter<-function(session){prior<-mock$recommendations;on.exit(mock$recommendations<-prior)
 refs<-lapply(rows[1:2],`[[`,"ref")
 mock$recommendations[[rows[[1]]$ref$id]]<-list(refs=refs,reason=NULL)
 session$setInputs(rpk_enter=list(study_id="study",project_id="default",report_ref=rows[[1]]$ref))}
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
 session$flushReact();fixture_enter(session)
 bind<-function(){x<-list(rpk_form_identity=controller$state$form_identity,rpk_title=controller$state$draft$title,rpk_source_identifiers=FALSE,rpk_images=FALSE)
  for(s in controller$state$sections){if(s$adapter=="paired-findings")x[[paste0("rpk_charts_",s$id)]]<-unlist(s$display$charts)
   if(s$adapter%in%c("paired-findings","explicit-distribution"))x[[paste0("rpk_pages_",s$id)]]<-""}
  do.call(session$setInputs,x)}
 bind();ack<-function()session$setInputs(rpk_prepare_ack=controller$state$pending$ticket)

 add_source<-function(report_ref){
  refs<-lapply(controller$state$rows,`[[`,"ref");reads<-length(mock$lookups);saves<-mock$saves;advances<-mock$advances
  stopifnot(!any(vapply(refs,function(r).brohn_rpv_same(r,report_ref),logical(1))))
  session$setInputs(rpk_source_toggle=report_ref)
  check(identical(controller$state$pending$action,"include_source")&&
   .brohn_rpv_same(controller$state$pending$payload$ref,report_ref)&&length(mock$lookups)==reads&&
   .brohn_rpv_same(lapply(controller$state$rows,`[[`,"ref"),refs),
   "Add sets pending feedback before the original full-choice spy and leaves selected sources unchanged")
  ack()
  check(is.null(controller$state$pending)&&length(mock$lookups)==reads+1L&&
   .brohn_rpv_same(tail(mock$lookups,1L)[[1]],report_ref)&&
   .brohn_rpv_same(lapply(controller$state$rows,`[[`,"ref"),c(refs,list(report_ref)))&&
   mock$saves==saves&&mock$advances==advances,
   "Acknowledged Add invokes the original full-choice spy once and adds the exact source without saving or queuing")
 }
 saved<-function()controller$state$intent$intent_ref$id
 set_status<-function(status,action){id<-saved();mock$intents[[id]]$view$status<-status;mock$intents[[id]]$view$next_action<-action
  if(status=="succeeded")mock$intents[[id]]$view$package_ref<-ref(paste0("package-",id),"report_package");session$elapse(1001);session$flushReact()}
 download<-function(url,method="GET"){name<-sub("\\?.*$","",sub("^/mock-resource/","",url));r<-routes[[name]]
  r$filter(r$data,list(REQUEST_METHOD=method,QUERY_STRING=sub("^[^?]*\\?","",url)))}
})
scenario("HTTP representation lengths use decimal digits",{
 values<-c(100000,1e6,1e8)
 check(all(vapply(values,function(bytes){
   artifact<-artifacts$html;artifact$bytes<-as.numeric(bytes)
   responses<-lapply(c("GET","HEAD"),function(method).brohn_rpk_download_response(list(REQUEST_METHOD=method),artifact,"html"))
    all(vapply(responses,function(r){x<-r$headers[["Content-Length"]];h<-as.list(r$headers);h$`Content-Length`<-as.numeric(bytes);h$`Content-Type`<-"text/html";y<-h$`Content-Length`;grepl("^[0-9]+$",x)&&identical(as.numeric(x),bytes)&&identical(x,y)&&identical(h$`Content-Type`,"text/html")},logical(1)))
  },logical(1))),"Power-of-ten byte counts stay decimal on GET and HEAD after Shiny's numeric header overwrite")
})
scenario("one action and visible prerequisites",{
 eval(setup);ready_before<-output$rpk_ready;before<-mock$saves;opened<-mock$opens;session$setInputs(rpk_prepare=1L)
 check(controller$state$phase=="preparing"&&mock$saves==before&&mock$opens==opened,"Preparation feedback exists before intent/queue or resource work")
 session$setInputs(rpk_prepare_ack="stale");check(mock$saves==before,"Stale painted acknowledgement creates no intent")
 ack();check(mock$saves==before+1L&&controller$state$intent$status=="waiting_for_display","One matching acknowledgement saves the intent and starts its explicit display stage")
 count<-mock$saves;session$setInputs(rpk_prepare=2L);check(mock$saves==count,"Repeating unchanged Prepare does not duplicate saved work")
 set_status("ready_to_freeze","continue");check(controller$state$intent$status=="assembly_queued","The current authorized controller advances the same intent after the display prerequisite")
 set_status("succeeded","download");check(mock$opens==opened&&controller$state$pending$passive,"Complete package waits for passive painted feedback before opening bytes")
 ack();url<-controller$state$urls$html;check(download(url)$status==200L&&download(url,"HEAD")$status==200L&&download(url,"POST")$status==404L,"Opened package installs exact GET/HEAD capabilities and refuses other methods")
 reads<-mock$current_reads;head<-download(url,"HEAD");get<-download(url)
 check(head$status==200L&&is.raw(head$content)&&length(head$content)==0L&&as.numeric(head$headers[["Content-Length"]])==file.info(get$content$file)$size&&
   identical(readBin(get$content$file,"raw",n=file.info(get$content$file)$size),readBin(artifacts$html$path,"raw",n=artifacts$html$bytes))&&
   mock$current_reads==reads+2L&&identical(head$headers[["Content-Encoding"]],"identity"),
   "Successful HEAD returns no body and exact representation length after fresh access checks, while GET retains the original bytes")
 check(is.null(ready_before)&&!is.null(output$rpk_ready)&&grepl("Your report is ready",output$rpk_ready$html,fixed=TRUE)&&grepl("Download report + evidence",output$rpk_ready$html,fixed=TRUE),"The initially empty rendered output invalidates to show the heading and both download links after opening")
 session$setInputs(rpk_title="Changed title");check(controller$state$dirty&&download(url)$status==404L&&!length(controller$state$urls)&&is.null(output$rpk_ready),"Editing the form immediately revokes prior capabilities and cannot show the old report as the new draft")
})
scenario("historical choices and exact exposure beyond first page",{
 eval(setup);n<-length(controller$state$rows);session$setInputs(rpk_sources_next=1L)
 check(length(controller$state$rows)==n&&controller$state$choices$reports[[1]]$ref$revision==2L,"Source paging preserves selected reports and exposes exact historical metadata")
 s<-Filter(function(s)s$adapter=="gaze-context",controller$state$sections)[[1]]
 session$setInputs(rpk_selector_open=list(ref=s$source_report_ref,adapter=s$adapter));session$setInputs(rpk_selector_next=1L)
 p<-controller$state$selector;session$setInputs(rpk_selector_choose=list(ref=p$report_ref,adapter=p$adapter,selector=p$items[[1]]$selector))
 exact<-Filter(function(s)s$adapter=="gaze-context",controller$state$sections)
 check(length(exact)==1L&&exact[[1]]$selector$exposure_key=="exposure-14"&&controller$state$draft$contents_policy$complete_selected_numerical_evidence,"Exposure14 replaces the all-exposure figure selector while complete numerical evidence stays required")
 bind();session$setInputs(rpk_prepare=1L);ack();check(controller$state$intent$request$requested_sections[[length(controller$state$sections)]]$selector$exposure_key=="exposure-14","The exact original exposure key is persisted in the request")
})
scenario("navigation and restart resume preserve durable intent",{
 eval(setup);session$setInputs(rpk_prepare=1L);ack();id<-saved();advances<-mock$advances;cancels<-mock$cancels
 state$page<-"home";session$flushReact();session$elapse(2001)
 check(mock$advances==advances&&mock$cancels==cancels&&mock$intents[[id]]$view$status=="waiting_for_display","Navigation pauses browser continuation without cancelling its durable prerequisite")
 session$setInputs(rpk_enter=list(study_id="study",project_id="default",report_ref=NULL));bind();row<-Filter(function(i)i$intent_ref$id==id,controller$state$history$items)[[1]]
 session$setInputs(rpk_history_open=row$intent_ref);ack();bind();mock$intents[[id]]$view$status<-"ready_to_freeze";mock$intents[[id]]$view$next_action<-"continue";session$elapse(1001)
 check(mock$advances==advances&&!controller$state$automatic,"Reopening unfinished history reads its current state without silently queuing continuation")
 session$setInputs(rpk_resume=1L);check(mock$advances==advances&&controller$state$phase=="preparing","Explicit Resume paints feedback before advancing")
 ack();check(controller$state$intent$status=="assembly_queued"&&mock$advances==advances+1L,"Explicit Resume advances the exact persisted intent")
 session$setInputs(rpk_cancel=1L);check(controller$state$intent$status=="cancelled"&&mock$cancels==cancels+1L,"Cancel calls the backend durable dependency-ownership operation")
})
scenario("stale initial acknowledgement and fresh access after paint",{
 eval(setup);count<-mock$saves;session$setInputs(rpk_prepare=1L);ticket<-controller$state$pending$ticket
 session$setInputs(rpk_title="Later title",rpk_prepare_ack=ticket)
 check(mock$saves==count&&controller$state$dirty,"A changed form cannot save stale frozen inputs after the old paint acknowledgement")
 session$setInputs(rpk_prepare=2L);mock$authority<-FALSE;ack();mock$authority<-TRUE
 check(mock$saves==count&&controller$state$phase=="failed","Current backend authority is checked after preparation feedback, before any new intent")
})
scenario("reader revocation and bounded reopen attempts",{
 eval(setup);session$setInputs(rpk_prepare=1L);ack();set_status("succeeded","download");ack();url<-controller$state$urls$zip
 mock$reader<-FALSE;reads<-mock$session_checks;head<-download(url,"HEAD");refused<-download(url)$status
 check(head$status==404L&&is.raw(head$content)&&length(head$content)==0L&&mock$session_checks==reads+2L&&
   identical(head$headers[["Content-Encoding"]],"identity")&&identical(head$headers[["Cache-Control"]],"no-store"),
   "Refused HEAD returns an empty no-store identity response and still performs the current-reader check")
 session$elapse(1001);mock$reader<-TRUE
 check(refused==404L&&!length(controller$state$urls),"Current reader revocation refuses the live capability and clears the opened UI resource")
 opens<-mock$opens;session$elapse(4001);check(mock$opens==opens&&is.null(controller$state$pending),"A failed current read is not retried automatically every poll")
 session$setInputs(rpk_reopen=1L);ack();check(length(controller$state$urls)==3L&&mock$opens==opens+1L&&!is.null(output$rpk_ready),"An authorized explicit reopen gets fresh resource capabilities without creating an intent")
})
scenario("exact paired choices, edit generation and cancel before acknowledgement",{
 eval(setup);s<-Filter(function(s)s$adapter=="paired-findings",controller$state$sections)[[1]]
 session$setInputs(rpk_selector_open=list(ref=s$source_report_ref,adapter=s$adapter));p<-controller$state$selector
 session$setInputs(rpk_selector_choose=list(ref=p$report_ref,adapter=p$adapter,selector=p$items[[1]]$selector));bind()
 exact<-Filter(function(s)s$adapter=="paired-findings"&&s$selector$scope=="exact_comparison",controller$state$sections)[[1]]
 values<-list();values[[paste0("rpk_charts_",exact$id)]]<-"differences";values[[paste0("rpk_pages_",exact$id)]]<-"2, 3";do.call(session$setInputs,values)
 session$setInputs(rpk_prepare=1L);ack();id<-saved();section<-Filter(function(s)s$id==exact$id,controller$state$intent$request$requested_sections)[[1]]
 check(section$selector$contrast_hash==brohn_hash("saved-contrast")&&identical(section$display$charts,list("differences"))&&identical(section$display$page_numbers,list(2L,3L)),
  "Paired figure selection freezes the exact contrast hash, chart type and explicit pages")
 session$setInputs(rpk_title="Revised package title");session$setInputs(rpk_prepare=2L);ack()
 check(saved()!=id&&mock$intents[[id]]$view$status=="superseded"&&controller$state$intent$request$title=="Revised package title",
  "Changed report contents use a new command and exact prior intent CAS instead of retargeting old work")
 set_status("succeeded","download");saves<-mock$saves;cancels<-mock$cancels;ticket<-controller$state$pending$ticket
 session$setInputs(rpk_cancel=1L,rpk_prepare_ack=ticket);session$elapse(1001)
 check(mock$cancels==cancels&&mock$saves==saves&&!controller$state$dirty&&is.null(controller$state$pending),
  "Cancelling only a pending open preserves the ready package without marking its unchanged contents as a new draft")
 session$setInputs(rpk_prepare=3L);ack();check(mock$saves==saves&&length(controller$state$urls)==3L,
  "Prepare after cancelled opening reopens the identical saved package without another intent")
})
scenario("escaped metadata and stable source selection",{
 x<-rows[[1]];x$title<-'<script>alert("metadata")</script>'
 html<-as.character(brohn_report_package_sources_ui(list(reports=list(x),next_cursor=NULL),list()))
 check(grepl("&lt;script&gt;",html,fixed=TRUE)&&!grepl('<script>alert',html,fixed=TRUE),"Untrusted saved report titles are escaped in the source catalog")
 eval(setup);session$setInputs(rpk_prepare=1L);ticket<-controller$state$pending$ticket;n<-mock$saves
 state$page<-"home";session$flushReact();session$setInputs(rpk_prepare_ack=ticket)
 check(mock$saves==n,"A delayed first acknowledgement after navigation cannot create durable work")
})
scenario("exact linked recommendations apply only at initial entry",{
 eval(setup);mock$recommendations[[rows[[4]]$ref$id]]<-list(refs=list(rows[[4]]$ref,rows[[3]]$ref,rows[[2]]$ref),reason="Exact original parents selected.")
 session$setInputs(rpk_enter=list(study_id="study",project_id="default",report_ref=rows[[4]]$ref));bind()
 check(.brohn_rpv_same(lapply(controller$state$rows,`[[`,"ref"),list(rows[[4]]$ref,rows[[3]]$ref,rows[[2]]$ref)),
  "Combined entry selects its exact linked historical parents without substituting current gaze")
 session$setInputs(rpk_source_toggle=rows[[2]]$ref);bind();session$elapse(1001)
 check(length(controller$state$rows)==2L&&is.null(controller$state$recommendation_note),"Editing recommended contents retains the override and removes its stale recommendation note")
 session$setInputs(rpk_prepare=1L);ack();id<-saved();session$setInputs(rpk_enter=list(study_id="study",project_id="default",report_ref=NULL));bind()
 item<-Filter(function(i)i$intent_ref$id==id,controller$state$history$items)[[1]];session$setInputs(rpk_history_open=item$intent_ref);ack();bind()
 check(length(controller$state$rows)==2L&&!any(vapply(controller$state$rows,function(r).brohn_rpv_same(r$ref,rows[[2]]$ref),logical(1))),
  "Reopening saved intent restores exact overrides without expanding recommended sources")
 session$setInputs(rpk_source_toggle=rows[[3]]$ref)
 check(length(controller$state$rows)==1L&&.brohn_rpv_same(controller$state$rows[[1]]$ref,rows[[4]]$ref),
  "An exact selected historical parent can be removed even when it is absent from the current catalog page")
 mock$recommendations[[rows[[4]]$ref$id]]<-list(refs=list(),reason="One linked source is unavailable; choose exact findings.")
 session$setInputs(rpk_enter=list(study_id="study",project_id="default",report_ref=rows[[4]]$ref));bind()
 check(!length(controller$state$rows)&&identical(controller$state$recommendation_note,"One linked source is unavailable; choose exact findings."),
  "Ambiguous or unavailable recommendations stay empty with their reason instead of substituting a source")
 mock$recommendations<-list()
})
scenario("history feedback and cancellation before saved reads",{
 eval(setup);session$setInputs(rpk_prepare=1L);ack();id<-saved()
 session$setInputs(rpk_enter=list(study_id="study",project_id="default",report_ref=NULL));bind()
 item<-Filter(function(i)i$intent_ref$id==id,controller$state$history$items)[[1]]
 before<-length(mock$lookups);opened<-mock$opens;saves<-mock$saves;advanced<-mock$advances
 session$setInputs(rpk_history_open=item$intent_ref)
 ticket<-controller$state$pending$ticket
 check(controller$state$phase=="preparing"&&controller$state$pending$action=="history"&&
   length(mock$lookups)==before&&mock$opens==opened,
   "History shows its pending feedback before source hydration or resource opening")
 check(grepl("Opening this saved preparation",output$rpk_feedback$html,fixed=TRUE),
   "History feedback exposes the pending action to the live status region")
 session$setInputs(rpk_cancel=1L);session$setInputs(rpk_prepare_ack=ticket)
 check(is.null(controller$state$pending)&&length(mock$lookups)==before&&mock$opens==opened&&
   mock$saves==saves&&mock$advances==advanced,
   "Cancelling pending history invalidates its acknowledgement without reading or queuing work")
 session$setInputs(rpk_history_open=item$intent_ref);stale<-controller$state$pending$ticket
 session$setInputs(rpk_history_open=item$intent_ref);fresh<-controller$state$pending$ticket
 session$setInputs(rpk_prepare_ack=stale)
 check(identical(controller$state$pending$ticket,fresh)&&length(mock$lookups)==before,
   "A superseded history ticket cannot hydrate or replace the current preparation")
 ack();bind()
 check(identical(controller$state$intent$intent_ref$id,id)&&length(mock$lookups)>before&&
   mock$saves==saves&&mock$advances==advanced,
   "The current acknowledgement restores exact saved choices without saving or advancing them")
 before<-length(mock$lookups);session$setInputs(rpk_history_open=item$intent_ref)
 stale<-controller$state$pending$ticket;state$page<-"home";session$flushReact()
 session$setInputs(rpk_prepare_ack=stale)
 check(length(mock$lookups)==before&&is.null(controller$state$pending),
   "Leaving the page invalidates pending history before any saved source reads")
})
scenario("history acknowledgement keeps newly edited unsaved and dirty drafts",{
 eval(setup);session$setInputs(rpk_prepare=1L);ack();id<-saved()
 session$setInputs(rpk_enter=list(study_id="study",project_id="default",report_ref=NULL));bind()
 item<-Filter(function(i)i$intent_ref$id==id,controller$state$history$items)[[1]]
 check(is.null(controller$state$intent)&&!isTRUE(controller$state$dirty),"The fresh editor has no prior saved-intent comparison")
 before<-length(mock$lookups);session$setInputs(rpk_history_open=item$intent_ref)
 ticket<-controller$state$pending$ticket;session$setInputs(rpk_title="New unsaved title")
 session$setInputs(rpk_prepare_ack=ticket)
 check(is.null(controller$state$pending)&&isTRUE(controller$state$dirty)&&
   identical(input$rpk_title,"New unsaved title")&&length(mock$lookups)==before,
   "Editing a fresh draft while history awaits acknowledgement preserves the edit and cancels hydration")
 session$setInputs(rpk_history_open=item$intent_ref);ticket<-controller$state$pending$ticket
 session$setInputs(rpk_title="");session$setInputs(rpk_prepare_ack=ticket)
 check(is.null(controller$state$pending)&&isTRUE(controller$state$dirty)&&
   identical(input$rpk_title,"")&&length(mock$lookups)==before,
   "A further invalid edit in an already-dirty draft also cancels history without overwriting the input")
 session$setInputs(rpk_history_open=item$intent_ref);ticket<-controller$state$pending$ticket
 session$setInputs(rpk_images=TRUE);session$setInputs(rpk_prepare_ack=ticket)
 check(is.null(controller$state$pending)&&isTRUE(input$rpk_images)&&length(mock$lookups)==before,
   "Changing an export-content checkbox during pending history also preserves the draft")
 session$setInputs(rpk_history_open=item$intent_ref);ack();bind()
 check(identical(controller$state$intent$intent_ref$id,id)&&!isTRUE(controller$state$dirty),
   "Selecting history again deliberately restores its exact saved choices even from an invalid draft")
})
brohn_write_json_file(list(passed=all(vapply(scenarios,`[[`,logical(1),"passed")),checks=checks,scenarios=scenarios,
 source_hashes=setNames(lapply(c("platform-report-package-source-catalog.R","platform-report-package-views.R","platform-report-package-server.R"),function(f)digest::digest(file=file.path(candidate,f),algo="sha256")),c("catalog","views","server")),
 scope="Shiny controller with explicit in-memory backend/resource spies and tiny local capability artifacts. No genuine report preparation, scientific result, native seal, HTTP, browser or worker claim."),file.path(folder,"results.json"))
if(any(!vapply(scenarios,`[[`,logical(1),"passed")))quit(status=1L)
