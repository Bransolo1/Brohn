# Connected, read-only participant evidence from one exact saved answer.
.brohn_as_label <- function(x)if(is.null(x)||identical(x,""))"Unavailable"else gsub("_"," ",as.character(x),fixed=TRUE)
.brohn_as_tabs <- function(received,assigned) {
  # These local display tabs do not use Shiny/Bootstrap's delayed tab binding.
  # Both evidence outputs remain bound; only the selected panel is displayed.
  activate<-"const t=event.target.closest('[role=tab]');if(t&&this.contains(t)){this.querySelectorAll('[role=tab]').forEach(x=>{const active=x===t;x.setAttribute('aria-selected',String(active));x.tabIndex=active?0:-1;document.getElementById(x.getAttribute('aria-controls')).hidden=!active;});}"
  keys<-"if(!event.defaultPrevented&&['ArrowRight','ArrowLeft','Home','End',' '].includes(event.key)){const a=[...this.querySelectorAll('[role=tab]')],i=a.indexOf(document.activeElement);if(i>=0){event.preventDefault();event.stopPropagation();const j=event.key==='Home'?0:event.key==='End'?a.length-1:event.key==='ArrowRight'?(i+1)%a.length:event.key==='ArrowLeft'?(i+a.length-1)%a.length:i;a[j].click();a[j].focus();}}"
  shiny::tagList(shiny::div(role="tablist",`aria-label`="Session evidence sections",class="brohn-session-tabs",onclick=activate,onkeydown=keys,
    shiny::tags$button(type="button",role="tab",id="answer-session-received-tab",`aria-controls`="answer-session-received-panel",`aria-selected`="true",tabindex="0","Received evidence"),
    shiny::tags$button(type="button",role="tab",id="answer-session-assigned-tab",`aria-controls`="answer-session-assigned-panel",`aria-selected`="false",tabindex="-1","Assigned sequence")),
    shiny::div(id="answer-session-received-panel",role="tabpanel",`aria-labelledby`="answer-session-received-tab",received),
    shiny::div(id="answer-session-assigned-panel",role="tabpanel",`aria-labelledby`="answer-session-assigned-tab",hidden="hidden",assigned))
}
brohn_install_answer_session <- function(input,output,session,store,state,attempt,message,prepare_download) {
  source<-shiny::reactiveVal(NULL);pending<-shiny::reactiveVal(NULL);record<-shiny::reactiveVal(NULL);issue<-shiny::reactiveVal(NULL);urls<-shiny::reactiveVal(NULL)
  pages<-shiny::reactiveValues(events=NULL,assigned=NULL,chunk=NULL);offsets<-new.env(parent=emptyenv());offsets$events<-list(0L);offsets$assigned<-list(0L)
  owned<-new.env(parent=emptyenv());owned$guards<-list();owned$con<-NULL;owned$process<-NULL;owned$verified<-NULL;owned$expected<-NULL
  release<-function(){if(!is.null(owned$process)&&owned$process$is_alive())owned$process$kill_tree();owned$process<-NULL
    if(!is.null(owned$con))DBI::dbDisconnect(owned$con);owned$con<-NULL
    for(g in owned$guards).brohn_qexplorer_release(g);owned$guards<-list();owned$verified<-NULL
    if(!is.null(owned$expected))unlink(owned$expected);owned$expected<-NULL;urls(NULL);pages$events<-NULL;pages$assigned<-NULL;pages$chunk<-NULL}
  close<-function(){s<-shiny::isolate(source());release();source(NULL);pending(NULL);record(NULL);issue(NULL);shiny::removeModal()
    if(!is.null(s))session$onFlushed(function()session$sendCustomMessage("brohn-focus",s$return_focus),once=TRUE)}
  session$onSessionEnded(release)
  selected<-function(){s<-source();brohn_require(!is.null(s)&&identical(state$page,"report")&&identical(state$report_id,s$request$binding$report_id),"Open this session through its original saved answer.")
    if(!is.null(s$validate_selection))s$validate_selection()
    c<-s$opened_index$context;brohn_check_questionnaire_index_context(store,s$opened_index,c$report_id,c$report_revision,c$report_hash,c$project_id)
    .brohn_as_authority(store,s$request);s}
  active<-function(){s<-selected();r<-record();brohn_require(!is.null(r)&&identical(owned$verified,r$id)&&!is.null(owned$con),"Wait for the complete session evidence to be verified.")
    for(g in owned$guards).Call(g$native$check,g$pointer)
    current<-brohn_answer_session_record(store,r$id,s$request);brohn_require(.brohn_as_same(current$body,r$body),"The session review changed; reopen the saved answer.");r}
  fail<-function(e){issue(conditionMessage(e));release();record(NULL);pending(NULL)}
  show<-function(){shiny::showModal(shiny::modalDialog(title="Participant session evidence",size="l",easyClose=FALSE,
    shiny::div(id="answer-session-review",style="min-width:0;overflow-wrap:anywhere",
      shiny::tags$style(shiny::HTML("#answer-session-review button,#answer-session-review a.btn,#answer-session-review .nav-link{min-height:44px;white-space:normal}#answer-session-review pre{white-space:pre-wrap;overflow-wrap:anywhere}#answer-session-review h3{line-height:1.5}#answer-session-review th{white-space:normal}#answer-session-review .nav-link{color:#9bd6c9}#answer-session-review .nav-link.active{color:#eef3f5!important;background:#24323a!important}#answer-session-review .brohn-table{max-width:100%;overflow-x:auto}#answer-session-review table{min-width:850px}#answer_session_events th:nth-child(2){width:150px;min-width:150px}#answer_session_events td:nth-child(2){overflow-wrap:normal;word-break:normal}#answer-session-review .radio-inline{min-height:44px;padding-top:8px}#answer-session-review th:first-child{min-width:98px;overflow-wrap:normal;white-space:nowrap}#answer-session-review [role=tabpanel][hidden]{display:none!important}#answer-session-review .brohn-session-tabs{display:flex;flex-wrap:wrap;gap:4px;border-bottom:1px solid #57717b;margin-bottom:12px}#answer-session-review [role=tab]{border:1px solid transparent;background:transparent;color:#9bd6c9;padding:10px 16px}#answer-session-review [role=tab][aria-selected=true]{color:#eef3f5;background:#24323a;border-color:#57717b}#answer-session-review [role=tab]:focus-visible{outline:3px solid #9bd6c9;outline-offset:2px}")),
      shiny::uiOutput("answer_session_status"),shiny::uiOutput("answer_session_body")),
    footer=shiny::actionButton("answer_session_close","Return to saved answer")))
  }
  open<-function(opened_index,record_key,record_hash,return_focus="qx-detail-heading",validate_selection=NULL){
    release();issue(NULL);record(NULL);job<-brohn_queue_answer_session(store,opened_index,record_key,record_hash)
    source(list(opened_index=opened_index,request=job$request,return_focus=return_focus,validate_selection=validate_selection));pending(job$id)
    offsets$events<-list(0L);offsets$assigned<-list(0L);show()
  }
  shiny::observeEvent(input$answer_session_close,close())
  shiny::observeEvent(list(state$page,state$report_id),{s<-source();if(!is.null(s)&&(!identical(state$page,"report")||!identical(state$report_id,s$request$binding$report_id)))close()},ignoreInit=FALSE,priority=115)
  shiny::observeEvent(input$answer_session_cancel,attempt(function(){selected();brohn_cancel_job(store,pending())}))
  shiny::observeEvent(input$answer_session_retry,attempt(function(){s<-selected();j<-brohn_get_job(store,pending());brohn_require(j$status %in% c("failed","cancelled"),"Only a failed or cancelled session review can retry.")
    job<-brohn_queue_answer_session(store,s$opened_index,s$request$record_key,s$request$record_hash,retry=TRUE);brohn_require(.brohn_as_same(job$request,s$request),"Session evidence changed; reopen the answer instead.")
    pending(job$id);issue(NULL)}))
  shiny::observe({id<-pending();if(is.null(id)||!is.null(record()))return();shiny::invalidateLater(750,session)
    shiny::isolate(tryCatch({s<-selected();j<-brohn_get_job(store,id)
      if(j$status=="succeeded")record(brohn_answer_session_record(store,j$result$answer_session_id,s$request))
    },error=fail))})
  # All whole-object hashing is outside Shiny; native handles retain the verified
  # immutable objects until close, navigation, selection change or session end.
  shiny::observe({r<-record();if(is.null(r))return();shiny::invalidateLater(1000,session)
    shiny::isolate(tryCatch({s<-selected()
      if(is.null(owned$verified)&&is.null(owned$process)){
        i<-brohn_answer_session_input(store,list(operation="answer_session",request=s$request),verify=FALSE)
        refs<-c(i$source_objects,lapply(r$body$exports,function(x)list(hash=x$hash,bytes=x$size)),list(list(hash=r$body$result_object$hash,bytes=r$body$result_object$size)))
        refs<-unname(refs[!duplicated(vapply(refs,`[[`,character(1),"hash"))]);i$source_objects<-refs;owned$guards<-brohn_hold_signal_value_sources(store,i)
        paths<-lapply(refs,function(x)list(path=brohn_object_path(store,x$hash,verify=FALSE),sha256=x$hash))
        owned$expected<-tempfile("brohn-answer-session-envelope-",fileext=".json");brohn_write_json_file(r$body[setdiff(names(r$body),"result_object")],owned$expected)
        code<-paste(c("import hashlib,json,sys","for i in json.loads(sys.argv[1]):"," h=hashlib.sha256()"," with open(i['path'],'rb') as f:","  for b in iter(lambda:f.read(1048576),b''):h.update(b)"," if h.hexdigest()!=i['sha256']:raise RuntimeError('Saved session source or export changed.')",
          "a=json.load(open(sys.argv[2],encoding='utf-8'));b=json.load(open(sys.argv[3],encoding='utf-8'))","if a!=b:raise RuntimeError('Saved session envelope differs from the catalog.')"),collapse="\n")
        owned$process<-processx::process$new(.brohn_publication_python(),c("-B","-c",code,brohn_json(paths),owned$expected,brohn_object_path(store,r$body$result_object$hash,verify=FALSE)),stdout="|",stderr="|",cleanup_tree=TRUE,windows_hide_window=TRUE)
      }
      if(!is.null(owned$process)&&!owned$process$is_alive()){
        brohn_require(owned$process$get_exit_status()==0,paste("Session evidence verification failed:",substr(owned$process$read_all_error(),1,1000)))
        owned$process<-NULL;ref<-r$body$exports[["session-evidence.sqlite"]]
        owned$con<-DBI::dbConnect(RSQLite::SQLite(),brohn_object_path(store,ref$hash,verify=FALSE),flags=RSQLite::SQLITE_RO,loadable.extensions=FALSE)
        DBI::dbExecute(owned$con,"PRAGMA query_only=ON");owned$verified<-r$id
        pages$events<-brohn_answer_session_page(owned$con,"events");pages$assigned<-brohn_answer_session_page(owned$con,"assigned")
        links<-lapply(setdiff(names(r$body$exports),"session-evidence.sqlite"),function(name){ref<-r$body$exports[[name]];path<-brohn_object_path(store,ref$hash,verify=FALSE);token<-brohn_token()
          url<-session$registerDataObj(paste0("answer-session-",name),list(id=r$id,token=token),function(data,req)shiny::isolate(tryCatch({
            brohn_require(req$REQUEST_METHOD %in% c("GET","HEAD")&&identical(shiny::parseQueryString(brohn_default(req$QUERY_STRING,""))$key,data$token)&&identical(active()$id,data$id),"Expired session evidence export.")
            structure(list(status=200L,content_type=ref$media_type,content=list(file=path,owned=FALSE),headers=list("Cache-Control"="no-store","X-Content-Type-Options"="nosniff","Content-Disposition"=paste0('attachment; filename="',name,'"'))),class="httpResponse")
          },error=function(e)structure(list(status=404L,content_type="text/plain",content="Reopen this exact saved answer and its verified session."),class="httpResponse"))))
          list(name=name,url=paste0(url,"&key=",token))});urls(links)
        session$onFlushed(function()session$sendCustomMessage("brohn-focus","answer-session-heading"),once=TRUE)
      }
      for(g in owned$guards).Call(g$native$check,g$pointer)
    },error=fail))})
  output$answer_session_status<-shiny::renderUI({if(!is.null(issue()))return(shiny::p(role="alert",issue()))
    id<-pending();if(is.null(id))return(NULL);j<-brohn_get_job(store,id)
    if(j$status %in% c("queued","running"))shiny::invalidateLater(750,session)
    if(j$status=="succeeded")return(if(is.null(urls()))shiny::p(role="status","Verifying the retained journal and exports in the background.")else NULL)
    shiny::div(role="status",shiny::p(paste("Preparing complete session evidence:",j$status)),if(!is.null(j$error))shiny::p(j$error$message),
      if(j$status %in% c("queued","running"))shiny::actionButton("answer_session_cancel","Cancel session preparation")else if(j$status %in% c("failed","cancelled"))shiny::actionButton("answer_session_retry","Retry session preparation"))})
  controls<-function(collection,page){shiny::div(class="brohn-toolbar",if(length(offsets[[collection]])>1L)brohn_command(paste("Previous",collection),"answer_session_page",list(collection=collection,direction="previous")),
    if(!is.null(page$next_after))brohn_command(paste("Next",collection),"answer_session_page",list(collection=collection,direction="next")))}
  output$answer_session_body<-shiny::renderUI({r<-record();if(is.null(r)||is.null(urls()))return(NULL);b<-r$body$result;s<-b$binding$snapshot
    ending<-b$received$ending;resolved<-s$resolution
    shiny::tagList(shiny::h3(id="answer-session-heading",tabindex="-1","What this participant session sent"),
      shiny::p(paste("Participant code:",s$run$participant_alias,"| origin:",s$run$origin,"| saved answer:",.brohn_as_label(b$binding$answer$status))),
      shiny::p(paste(b$received$events,"received events;",b$received$step_finish_count,if(b$received$step_finish_count==1L)"distinct step with a received finish event;"else"distinct steps with a received finish event;",b$assigned$steps,"assigned steps.")),
      shiny::p(if(is.null(ending))"No participant ending event was received."else paste("Received participant ending:",.brohn_as_label(ending$outcome),"(event",ending$sequence,").")),
      shiny::p(paste("Original delivery receipt:",.brohn_as_label(s$run$completion_status),"/",s$run$transfer_status,"; final acknowledgment",if(length(s$final_receipts))"received."else"not received.")),
      if(!is.null(resolved))shiny::div(class="brohn-alert",shiny::p(paste("Separate researcher decision:",.brohn_as_label(resolved$body$effective_resolution))),shiny::p(resolved$body$operator$reason),shiny::p("This decision does not replace the participant's original ending or receipt.")),
      shiny::p(if(is.null(s$capture))if(b$assigned$camera_requested)"Recording was requested, but no camera decision or bytes were received."else"No camera recording was requested."else paste("Recording receipt:",.brohn_as_label(s$capture$status),";",s$capture$acked_sequence,"chunks and",format(s$capture$total_bytes,big.mark=",",scientific=FALSE),"bytes received.",
        if(is.null(s$capture$final)||identical(s$capture$final$reason,"page_reload_recording_end_unobserved"))"A recording endpoint is not established."else"A recording final receipt was received.","Receipt metadata alone does not establish decoding or scientific eligibility.")),
      shiny::p("Final answers and their acknowledged revisions remain in the saved-answer explorer. A change or confirmation is not an additional independent response. This session review does not rescore them."),
      shiny::div(class="brohn-toolbar",lapply(urls(),function(u)shiny::tags$a(href=u$url,download=u$name,class="btn btn-primary",switch(u$name,`received-events.json`="Download complete received events",`received-event-timeline.csv`="Download received timeline CSV",`assigned-protocol.json`="Download assigned protocol"))),shiny::downloadButton("answer_session_manifest","Download review provenance",icon=NULL)),
      .brohn_as_tabs(received=shiny::tagList(shiny::radioButtons("answer_session_scope","Events to inspect",c("All received events"="all","Only this saved answer's step"="answer"),selected="all",inline=TRUE),
        shiny::p("Browser timestamps retain their original clock and page instance. They are not physical onset measurements or a cross-device alignment."),shiny::uiOutput("answer_session_events")),
        assigned=shiny::tagList(shiny::p("These steps were assigned at session start. Assignment does not prove that a step was displayed, answered or completed. The full protocol download preserves all content and conditions."),shiny::uiOutput("answer_session_assigned"))),
      shiny::uiOutput("answer_session_event_detail"),shiny::tags$details(shiny::tags$summary("Exact source binding"),shiny::p(paste("Saved report:",b$binding$binding$report_id,"revision",b$binding$binding$report_revision)),shiny::p(paste("Session:",s$run$id)),shiny::p(paste("Original received events SHA-256:",b$received$events_hash)),shiny::p(paste(b$verified_history_events,"saved questionnaire revision events match their original local events.")),shiny::p(b$policy),shiny::p("CSV text beginning with formula characters has a leading apostrophe. Complete JSON preserves the original types and values.")))
  })
  output$answer_session_events<-shiny::renderUI({p<-pages$events;if(is.null(p))return(NULL)
    ids<-unique(unlist(lapply(p$rows,`[[`,"step_id"),use.names=FALSE));titles<-list()
    if(length(ids)){t<-DBI::dbGetQuery(owned$con,paste0("SELECT step_id,substr(title,1,160) AS title FROM assigned WHERE step_id IN (",paste(rep("?",length(ids)),collapse=","),")"),params=as.list(ids));titles<-stats::setNames(as.list(t$title),t$step_id)}
    label<-function(e)if(e$event_type=="questionnaire_event")switch(e$kind,visit="Question opened",commit="Answer acknowledged",acknowledge="Information acknowledged",seal="Answer review confirmed",.brohn_as_label(e$kind))else .brohn_as_label(e$event_type)
    shiny::tagList(shiny::p(paste("Showing",length(p$rows),"received records after sequence",p$after,".")),
      shiny::div(class="brohn-table",tabindex="0",role="region",`aria-label`="Received participant events",shiny::tags$table(shiny::tags$thead(shiny::tags$tr(lapply(c("Sequence","Received evidence","Assigned step","Clock value and instance","Inspect"),function(x)shiny::tags$th(scope="col",x)))),
        shiny::tags$tbody(lapply(p$rows,function(e){clock<-brohn_parse(e$clock_json);shiny::tags$tr(shiny::tags$td(e$sequence),shiny::tags$td(label(e)),shiny::tags$td(if(!is.null(e$step_id))titles[[e$step_id]],shiny::p(class="brohn-muted",.brohn_as_label(e$step_id))),shiny::tags$td(paste(clock$value,clock$unit),shiny::p(brohn_default(clock$instance_id,"instance unavailable"))),shiny::tags$td(brohn_command("Open received event","answer_session_event",list(sequence=e$sequence,event_hash=e$event_hash))))})))),controls("events",p))})
  output$answer_session_assigned<-shiny::renderUI({p<-pages$assigned;if(is.null(p))return(NULL)
    shiny::tagList(shiny::p("Titles longer than 240 characters are abbreviated here; the assigned protocol download contains the complete original content."),brohn_table(lapply(p$rows,function(x)x[c("ordinal","step_id","type","title")]),maximum=25L,label="Assigned participant sequence"),controls("assigned",p))})
  step_filter<-function()if(identical(input$answer_session_scope,"answer"))source()$request$answer$step_id else NULL
  shiny::observeEvent(input$answer_session_scope,attempt(function(){if(is.null(urls()))return();active();offsets$events<-list(0L);pages$events<-brohn_answer_session_page(owned$con,"events",step_id=step_filter());pages$chunk<-NULL}),ignoreInit=TRUE)
  shiny::observeEvent(input$answer_session_page,attempt(function(){active();c<-input$answer_session_page;brohn_require(c$collection %in% c("events","assigned")&&c$direction %in% c("previous","next"),"Choose a current evidence page.")
    p<-pages[[c$collection]];stack<-offsets[[c$collection]]
    if(c$direction=="next"){brohn_require(!is.null(p$next_after),"There is no next page.");stack<-c(stack,list(p$next_after))}else{brohn_require(length(stack)>1L,"There is no previous page.");stack<-head(stack,-1L)}
    offsets[[c$collection]]<-stack;pages[[c$collection]]<-brohn_answer_session_page(owned$con,c$collection,tail(stack,1L)[[1L]],if(c$collection=="events")step_filter()else NULL);pages$chunk<-NULL}))
  shiny::observeEvent(input$answer_session_event,attempt(function(){active();c<-input$answer_session_event;matches<-Filter(function(e)e$sequence==c$sequence&&identical(e$event_hash,c$event_hash),pages$events$rows)
    brohn_require(length(matches)==1L,"Choose an event from the current received-evidence page.");pages$chunk<-brohn_answer_session_event_chunk(owned$con,c$sequence,c$event_hash)
    session$onFlushed(function()session$sendCustomMessage("brohn-focus","answer-session-event-heading"),once=TRUE)}))
  shiny::observeEvent(input$answer_session_chunk,attempt(function(){active();e<-pages$chunk;brohn_require(!is.null(e)&&input$answer_session_chunk %in% c("next","previous"),"Open a received event first.")
    pages$chunk<-brohn_answer_session_event_chunk(owned$con,e$sequence,e$event_hash,e$offset+if(input$answer_session_chunk=="next")4000L else -4000L)}))
  output$answer_session_event_detail<-shiny::renderUI({e<-pages$chunk;if(is.null(e))return(NULL)
    shiny::tags$section(shiny::h3(id="answer-session-event-heading",tabindex="-1",paste("Original received event",e$sequence)),shiny::p(paste("Characters",e$offset+1L,"to",min(e$offset+4000L,e$characters),"of",e$characters,". This is the original typed event, not another response.")),
      shiny::tags$pre(tabindex="0",role="region",`aria-label`="Original received event JSON",e$text),shiny::div(class="brohn-toolbar",if(e$offset>0L)brohn_command("Previous event text","answer_session_chunk","previous"),if(e$more)brohn_command("Next event text","answer_session_chunk","next")))})
  output$answer_session_manifest<-shiny::downloadHandler(filename=function()paste0(active()$id,".json"),contentType="application/json",content=function(file)prepare_download(function()brohn_write_json_file(active()$body,file)))
  invisible(list(open=open,close=close,selected=selected))
}
