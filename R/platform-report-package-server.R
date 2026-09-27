# This controller owns a view, never durable prerequisite state or authority.
`$<-.brohn_rpk_response_headers` <- function(x,name,value) {
  if(identical(name,"Content-Length")&&!is.null(value)) {
    if(is.numeric(value)) {
      stopifnot(length(value)==1L,!is.na(value),is.finite(value),value>=0,value==trunc(value))
      value<-format(value,scientific=FALSE,trim=TRUE,decimal.mark=".")
    }
    stopifnot(is.character(value),length(value)==1L,grepl("^[0-9]+$",value))
  }
  classes<-class(x);class(x)<-NULL;x[[name]]<-value;class(x)<-classes;x
}
# Shiny overwrites HEAD length after the callback. Keep only this response's
# headers typed so the later file.info() double is serialized as decimal digits.
registerS3method("$<-","brohn_rpk_response_headers",`$<-.brohn_rpk_response_headers`,envir=asNamespace("base"))
.brohn_rpk_download_response <- function(req,artifact=NULL,kind=NULL) {
  missing<-is.null(artifact);body<-charToRaw("Reopen the saved report to download its current evidence.")
  headers<-list("Cache-Control"="no-store","X-Content-Type-Options"="nosniff",
    "Content-Encoding"="identity","Content-Length"=format(if(missing)length(body)else artifact$bytes,scientific=FALSE,trim=TRUE,decimal.mark="."))
  if(!missing)headers[["Content-Disposition"]]<-paste0('attachment; filename="',
    switch(kind,html="report.html",zip="report.brohn-report.zip","manifest.json"),'"')
  # Shiny can normalize HEAD to GET before this callback. Identity encoding also
  # prevents its subsequently empty HEAD body from becoming a gzip payload.
  content<-if(identical(req$REQUEST_METHOD,"HEAD"))raw(0)else if(missing)body else list(file=artifact$path,owned=FALSE)
  structure(list(status=if(missing)404L else 200L,content_type=if(missing)"text/plain; charset=UTF-8"else artifact$media_type,
    content=content,headers=structure(headers,class=c("brohn_rpk_response_headers","list"))),class="httpResponse")
}
brohn_install_report_package_server <- function(input,output,session,store,state,current,attempt=NULL,
                                                message=NULL,refresh=NULL) {
  v<-shiny::reactiveValues(scope=NULL,choices=NULL,rows=list(),sections=list(),labels=list(),draft=NULL,
    editor_tick=0L,form_identity=NULL,intent=NULL,history=NULL,selector=NULL,issue=NULL,
    generation=0L,pending=NULL,focus_token=NULL,phase="idle",automatic=FALSE,dirty=FALSE,
    opened=NULL,urls=list(),open_attempt_key=NULL,request_command=NULL,request_snapshot=NULL,recommendation_note=NULL,
    task_options=list(),metadata_key=NULL)
  native<-new.env(parent=emptyenv());native$handle<-NULL
  cursors<-new.env(parent=emptyenv());cursors$sources<-list();cursors$history<-list();cursors$selector<-list()
  active<-function()identical(state$page,"report_package")&&!is.null(v$scope)
  require_active<-function(){brohn_require(active(),"Open this study's report preparation again.");brohn_hosted_require_session(store)}
  release<-function(){if(!is.null(native$handle))brohn_release_report_package_resources(native$handle)
    native$handle<-NULL;v$opened<-NULL;v$urls<-list()}
  clear_view<-function(){v$generation<-v$generation+1L;v$pending<-NULL;v$automatic<-FALSE;release()}
  fail<-function(e){release();v$issue<-substr(conditionMessage(e),1L,1000L);v$phase<-"failed";v$pending<-NULL;v$automatic<-FALSE}
  safe<-function(fn)tryCatch({require_active();fn()},error=fail)
  session$onSessionEnded(function(){if(!is.null(native$handle))brohn_release_report_package_resources(native$handle);native$handle<-NULL})
  shiny::observeEvent(state$page,{if(!identical(state$page,"report_package")&&!is.null(v$scope)){clear_view();v$scope<-NULL}},ignoreNULL=FALSE,priority=150)
  ref_key<-function(ref).brohn_rpv_key(ref)
  require_form<-function()brohn_require(identical(input$rpk_form_identity,v$form_identity),"Wait for the current report choices to appear.")
  load_history<-function(cursor=NULL){v$history<-brohn_report_package_catalog(store,v$scope$study_id,v$scope$project_id,cursor=cursor)}
  load_choices<-function(cursor=NULL){v$choices<-brohn_report_package_choices(store,v$scope$study_id,v$scope$project_id,cursor=cursor)}
  normalize_sections<-function(sections)lapply(seq_along(sections),function(i){s<-sections[[i]];s$order<-as.integer(i);s})
  make_draft<-function(title,policy=.brohn_rpv_policy())list(title=title,contents_policy=policy)
  editor<-function(){v$form_identity<-brohn_token();v$editor_tick<-v$editor_tick+1L}
  pages<-function(value){value<-trimws(brohn_default(value,""));if(!nzchar(value))return(NULL)
    brohn_require(nchar(value)<=512L&&grepl("^[0-9]+(\\s*,\\s*[0-9]+)*$",value),"Use page numbers separated by commas, or leave blank for all pages.")
    p<-as.numeric(trimws(strsplit(value,",",fixed=TRUE)[[1]]))
    brohn_require(length(p)<=100L&&!anyDuplicated(p)&&all(is.finite(p)&p>=1&p<=100000&p==floor(p)),"Choose distinct positive figure pages.")
    as.list(as.integer(p))}
  capture<-function(commit=TRUE){require_form();d<-v$draft
    title<-trimws(brohn_default(input$rpk_title,d$title));brohn_require(nzchar(title)&&nchar(title)<=200L,"Give this report a title of 1 to 200 characters.")
    d$title<-title;d$contents_policy$identifier_mode<-if(isTRUE(input$rpk_source_identifiers))"source_identifiers"else"package_aliases"
    d$contents_policy$stimulus_images<-if(isTRUE(input$rpk_images))"included"else"excluded_by_choice"
    sections<-lapply(v$sections,function(s){
      if(s$adapter=="gaze-context"){
        limit<-brohn_default(input[[paste0("rpk_limit_",s$id)]],s$display$candidate_limit)
        brohn_require(brohn_number(limit,1,1000,TRUE),"Choose between 1 and 1,000 illustrated gaze candidates per exposure.")
        s$display$candidate_limit<-as.integer(limit)
      }else{
        page_input<-input[[paste0("rpk_pages_",s$id)]]
        if(!is.null(page_input)){
          selected<-pages(page_input)
          s$display$pages<-if(is.null(selected))"all"else"selected"
          s$display$offsets<-NULL;s$display$page_numbers<-NULL
          if(s$adapter%in%c("task-trials","task-people"))s$display$page_numbers<-list()
          if(!is.null(selected))if(s$adapter=="explicit-distribution")s$display$offsets<-lapply(selected,function(p)(p-1L)*20L)else s$display$page_numbers<-selected
        }
        if(s$adapter=="paired-findings"){
          charts<-brohn_default(input[[paste0("rpk_charts_",s$id)]],unlist(s$display$charts))
          brohn_require(length(charts)>0L&&length(charts)<=2L&&!anyDuplicated(charts)&&all(charts%in%c("means","differences")),"Choose at least one paired figure.")
          s$display$charts<-as.list(charts)
        }
        if(s$adapter=="task-trials"){
          option<-v$task_options[[s$id]]
          scope<-brohn_default(input[[paste0("rpk_task_scope_",s$id)]],s$display$trial_scope)
          brohn_require(length(scope)==1L&&scope%in%c("all","scored"),"Choose all expected or profile test/scoring positions.")
          s$display$trial_scope<-scope
          if(!is.null(option)&&!startsWith(s$selector$scope,"all_")){
            measure<-brohn_default(input[[paste0("rpk_task_measure_",s$id)]],s$display$measure)
            brohn_require(length(measure)==1L&&measure%in%c("profile_default",unlist(option$compatible_measures)),"Choose a recorded-response measure available for this exact administration.")
            s$display$measure<-measure
            mode<-brohn_default(input[[paste0("rpk_task_mode_",s$id)]],if(identical(s$display$charts,"profile_default"))"profile_default"else"selected")
            brohn_require(length(mode)==1L&&mode%in%c("profile_default","selected"),"Choose task defaults or specific figure types.")
            if(mode=="profile_default")s$display$charts<-"profile_default"else{
              charts<-input[[paste0("rpk_task_charts_",s$id)]]
              if(is.null(charts)&&!identical(s$display$charts,"profile_default"))charts<-unlist(s$display$charts)
              brohn_require(length(charts)>0L&&!anyDuplicated(charts)&&all(charts%in%unlist(option$compatible_charts)),"Choose at least one available task figure.")
              s$display$charts<-as.list(charts)
            }
          }
        }
      };s})
    result<-list(draft=d,sections=normalize_sections(sections))
    if(commit){v$draft<-d;v$sections<-result$sections};result}
  dirty<-function(){clear_view();v$dirty<-TRUE;v$issue<-NULL;v$phase<-"idle";v$request_command<-NULL;v$request_snapshot<-NULL;v$recommendation_note<-NULL}
  request<-function(commit=TRUE){captured<-capture(commit);brohn_require(length(v$rows)>0L&&length(v$rows)<=8L,"Choose between one and eight saved reports.")
    brohn_require(length(captured$sections)>0L,"Choose at least one supported figure section.")
    task<-any(vapply(v$rows,function(row)isTRUE(row$source_family%in%c("native_questionnaire","imported_implicit","saved_task_cohort")),logical(1)))
    list(schema="brohn-report-package-intent-request/0.1",study_id=v$scope$study_id,project_id=v$scope$project_id,
      title=captured$draft$title,report_refs=unname(lapply(v$rows,`[[`,"ref")),requested_sections=unname(captured$sections),
      contents_policy=captured$draft$contents_policy,limits_profile=if(task)"controlled-task-report-package/0.1"else"controlled-report-package/0.1",
      renderer_profile=if(task)"controlled-gaze-explicit-task-paired/0.1"else"controlled-gaze-explicit-paired/0.1")}
  start<-function(action,payload=NULL,label,passive=FALSE){require_active();release();v$issue<-NULL
    if(!passive)v$focus_token<-brohn_token()
    if(action=="open")v$open_attempt_key<-.brohn_rpv_key(payload$package_ref)
    v$pending<-list(ticket=brohn_token(),generation=v$generation,action=action,payload=payload,label=label,passive=passive)
    v$phase<-"preparing"}
  adopt<-function(view){brohn_require(identical(view$request$study_id,v$scope$study_id)&&identical(view$request$project_id,v$scope$project_id),"This preparation belongs to another study.")
    v$intent<-view;v$dirty<-FALSE;v$phase<-if(view$status%in%c("failed","cancelled","needs_attention","needs_authority","superseded"))"failed"else if(view$status=="succeeded")"ready"else"waiting"
    if(view$status=="succeeded")v$automatic<-FALSE
    refresh_prepared(view)
    invisible(view)}
  hydrate<-function(view){v$recommendation_note<-NULL;v$rows<-lapply(view$request$report_refs,function(ref)brohn_report_package_report_choice(store,ref))
    v$sections<-view$request$requested_sections;v$draft<-make_draft(view$request$title,view$request$contents_policy);v$labels<-list();v$task_options<-list();v$selector<-NULL;editor();refresh_prepared(view)}
  prepared_sources<-function(view){if(is.null(view))return(list())
    prepared<-view$preparation$prepared_sources
    if(!is.null(prepared))return(prepared)
    # Legacy intents saved exact distribution references in their dependencies.
    # Preserve those identities; opening history must not discover a newer one.
    if(identical(view$request$renderer_profile,"controlled-gaze-explicit-paired/0.1"))return(lapply(
      Filter(function(d)!is.null(d$result_ref)&&!is.null(d$report_ref),view$dependencies),function(d)
        list(adapter="explicit-distribution",source_report_ref=d$report_ref,prepared_ref=d$result_ref)))
    list()}
  selector_preparation<-function(ref,adapter){
    if(identical(adapter,"explicit-distribution"))return("explicit-distribution")
    if(.brohn_rpv_task_adapter(adapter))return("task-display")
    row<-Filter(function(row).brohn_rpv_same(row$ref,ref),v$rows)
    task_source<-length(row)==1L&&isTRUE(row[[1]]$source_family%in%c("native_questionnaire","imported_implicit","saved_task_cohort"))
    if(identical(adapter,"paired-findings")&&task_source)"task-display"else NULL}
  refresh_prepared<-function(view){prepared<-prepared_sources(view)
    # A history adoption precedes hydration. Do not refresh the previous editor's
    # unrelated sources under the new intent, which may have different access.
    if(!.brohn_rpv_same(unname(lapply(v$rows,`[[`,"ref")),view$request$report_refs)){v$metadata_key<-NULL;return(invisible(NULL))}
    if(!length(prepared)){
      if(!is.null(v$metadata_key)||view$status%in%c("failed","needs_attention","needs_authority")){
        v$metadata_key<-NULL;v$task_options<-list()
        if(!is.null(v$selector)&&!is.null(selector_preparation(v$selector$report_ref,v$selector$adapter)))v$selector<-NULL
      }
      return(invisible(NULL))
    }
    key<-.brohn_rpv_key(list(view$intent_ref$id,prepared))
    if(identical(key,v$metadata_key))return(invisible(NULL))
    # Refresh only bounded source/catalog metadata. Never replace the requested
    # scopes/default policies with frozen resolved models during this repaint.
    v$rows<-lapply(v$rows,function(row)brohn_report_package_report_choice(store,row$ref))
    if(!is.null(v$selector)&&!is.null(selector_preparation(v$selector$report_ref,v$selector$adapter))){
      selected<-Filter(function(p)identical(p$adapter,selector_preparation(v$selector$report_ref,v$selector$adapter))&&
        .brohn_rpv_same(p$source_report_ref,v$selector$report_ref),prepared)
      binding<-if(length(selected)==1L)selected[[1L]]$prepared_ref else NULL
      cursor<-v$selector$cursor
      if(!.brohn_rpv_same(v$selector$prepared_ref,binding)){cursor<-NULL;cursors$selector<-list()}
      selector_load(v$selector$report_ref,v$selector$adapter,cursor)}
    v$metadata_key<-key
    invisible(NULL)}
  open_package<-function(view){require_active();brohn_require(!is.null(view$package_ref)&&view$status=="succeeded","This report package is not ready to open.")
    opened<-brohn_open_report_package_resources(store,view$package_ref,v$scope$project_id)
    native$handle<-opened$handle;v$opened<-opened$record
    generation<-v$generation;intent_id<-view$intent_ref$id;ref<-view$package_ref;token<-brohn_token()
    urls<-lapply(names(opened$artifacts),function(kind){artifact<-opened$artifacts[[kind]]
      uri<-session$registerDataObj(paste0("report-package-",kind),list(token=token),function(data,req)shiny::isolate(tryCatch({
        require_active();brohn_require(req$REQUEST_METHOD%in%c("GET","HEAD")&&identical(generation,v$generation)&&!isTRUE(v$dirty)&&
          !is.null(v$intent)&&identical(intent_id,v$intent$intent_ref$id)&&.brohn_rpv_same(ref,v$intent$package_ref)&&
          identical(shiny::parseQueryString(brohn_default(req$QUERY_STRING,""))$key,data$token)&&
          .brohn_rpv_same(request(FALSE),v$intent$request),"This report download has expired.")
        fresh<-brohn_report_package_resources_current(store,native$handle)
        brohn_require(.brohn_rpv_same(fresh$record,opened$record)&&.brohn_rpv_same(fresh$artifacts[[kind]],artifact),"This report package no longer matches the opened evidence.")
        .brohn_rpk_download_response(req,artifact,kind)
      },error=function(e).brohn_rpk_download_response(req))))
      paste0(uri,"&key=",token)})
    v$urls<-stats::setNames(urls,names(opened$artifacts));v$phase<-"ready";v$pending<-NULL}
  advance<-function(action="advance"){view<-brohn_continue_report_package_intent(store,v$intent$intent_ref,action=action);adopt(view)
    if(view$status=="succeeded")start("open",view,"Opening the saved report and checking current access.",passive=TRUE)}
  shiny::observeEvent(input$rpk_enter,tryCatch({brohn_hosted_require_session(store);command<-input$rpk_enter
    brohn_fields(command,c("study_id","project_id","report_ref"),label="Report preparation entry")
    clear_view();v$scope<-list(study_id=command$study_id,project_id=command$project_id);state$page<-"report_package"
    v$intent<-NULL;v$rows<-list();v$sections<-list();v$labels<-list();v$selector<-NULL;v$dirty<-FALSE;v$issue<-NULL;v$open_attempt_key<-NULL
    v$task_options<-list();v$metadata_key<-NULL
    cursors$sources<-list();cursors$history<-list();load_choices();load_history()
    entry<-if(!is.null(command$report_ref))brohn_report_package_report_choice(store,command$report_ref)else NULL
    refs<-if(is.null(entry))v$choices$recommended_refs else if(is.null(entry$recommended_refs))list(command$report_ref)else entry$recommended_refs
    v$recommendation_note<-if(is.null(entry))NULL else entry$recommendation_reason
    v$rows<-lapply(refs,function(ref)if(!is.null(entry)&&.brohn_rpv_same(ref,entry$ref))entry else brohn_report_package_report_choice(store,ref))
    v$sections<-.brohn_rpv_default_sections(v$rows)
    v$draft<-make_draft(paste(v$choices$study$title,"report"));editor();v$phase<-"idle"
    session$onFlushed(function()session$sendCustomMessage("brohn-focus","brohn-main"),once=TRUE)
  },error=fail))
  prepare<-function(new_version=FALSE){r<-request()
    if(new_version)brohn_require(!is.null(v$intent)&&identical(v$intent$next_action,"review"),"Review this preparation before creating a new version.")
    if(!new_version&&!is.null(v$intent)&&.brohn_rpv_same(r,v$intent$request)&&!isTRUE(v$dirty)){
      if(v$intent$status=="succeeded")start("open",v$intent,"Opening your saved report.")else v$issue<-"These choices already have a saved preparation. Review its status or use Resume below."
      return()
    }
    if(!is.null(v$pending)&&v$pending$action=="save"&&.brohn_rpv_same(v$pending$payload$request,r))return()
    if(new_version)clear_view()
    if(new_version||is.null(v$request_snapshot)||!.brohn_rpv_same(r,v$request_snapshot)){v$request_command<-brohn_token();v$request_snapshot<-r}
    prior<-if(!is.null(v$intent))v$intent$intent_ref else NULL
    start("save",list(command_id=v$request_command,request=r,prior=prior),"Saving your report choices.")
  }
  shiny::observeEvent(input$rpk_prepare,safe(function()prepare()))
  shiny::observeEvent(input$rpk_prepare_new,safe(function()prepare(TRUE)))
  shiny::observeEvent(input$rpk_prepare_ack,{p<-v$pending
    if(!active()||is.null(p)||p$generation!=v$generation||!identical(p$ticket,input$rpk_prepare_ack)||v$phase!="preparing")return()
    safe(function(){v$pending<-NULL
      if(p$action=="save"){
        x<-p$payload;view<-brohn_save_report_package_intent(store,x$command_id,x$request,
          expected_revision=if(is.null(x$prior))NULL else x$prior$revision,prior_intent_ref=x$prior)
        adopt(view);v$automatic<-TRUE;advance("advance");load_history()
      }else if(p$action=="open")open_package(p$payload)
      else if(p$action%in%c("resume","retry")){v$automatic<-TRUE;advance(brohn_default(p$payload$action,p$action));load_history()}
    })})
  shiny::observe({shiny::invalidateLater(1000,session);if(!active()||is.null(v$intent)||isTRUE(v$dirty)||!is.null(v$pending))return()
    safe(function(){view<-brohn_read_report_package_intent(store,v$intent$intent_ref$id,v$scope$project_id)
      if(!.brohn_rpv_same(view,v$intent)){adopt(view);load_history(if(is.null(v$history))NULL else v$history$cursor)}
      if(view$status=="succeeded"&&is.null(native$handle)&&!identical(v$open_attempt_key,.brohn_rpv_key(view$package_ref))){start("open",view,"Opening the saved report and checking current access.",passive=TRUE);return()}
      if(isTRUE(v$automatic)&&view$next_action=="continue")advance("advance")
      if(!is.null(native$handle))brohn_report_package_resources_current(store,native$handle)
    })})
  shiny::observeEvent(input$rpk_resume,safe(function(){brohn_require(!is.null(v$intent)&&v$intent$next_action%in%c("resume","retry","continue"),"Review this preparation's available next step.")
    action<-if(v$intent$next_action=="retry")"retry"else"resume"
    start(action,list(action=if(v$intent$next_action=="continue")"advance"else action),if(action=="retry")"Retrying the saved report choices."else"Resuming the saved report choices.")
  }))
  shiny::observeEvent(input$rpk_reopen,safe(function(){brohn_require(!is.null(v$intent)&&v$intent$status=="succeeded","Choose a completed saved report.")
    start("open",v$intent,"Reopening the saved report and checking current access.")}))
  shiny::observeEvent(input$rpk_cancel,safe(function(){
    if(!is.null(v$pending)){clear_view();v$phase<-"idle";v$issue<-"This preparation step was cancelled. Saved history is unchanged.";return()}
    brohn_require(!is.null(v$intent),"There is no saved preparation to cancel yet.")
    clear_view();adopt(brohn_cancel_report_package_intent(store,v$intent$intent_ref));load_history()}))
  shiny::observeEvent(input$rpk_back,safe(function(){id<-v$scope$study_id;study<-brohn_study(store,id);clear_view();current$study<-study;state$study_id<-id;state$page<-"study";state$stage<-"Results"
    if(is.function(refresh))refresh();session$sendCustomMessage("brohn-focus","brohn-main")}))
  shiny::observeEvent(input$rpk_source_toggle,safe(function(){capture();ref<-input$rpk_source_toggle
    found<-which(vapply(v$rows,function(r).brohn_rpv_same(r$ref,ref),logical(1)))
    row<-Filter(function(r).brohn_rpv_same(r$ref,ref),v$choices$reports)
    brohn_require(length(found)==1L||(length(row)==1L&&length(row[[1]]$adapters)>0L),"Choose selected findings or findings from the current catalog page.")
    dirty()
    if(length(found)){v$rows<-v$rows[-found];v$sections<-Filter(function(s)!.brohn_rpv_same(s$source_report_ref,ref),v$sections)}else{
      brohn_require(length(v$rows)<8L,"This report supports up to eight saved sources.");v$rows<-c(v$rows,row);v$sections<-c(v$sections,.brohn_rpv_default_sections(row))}
    v$sections<-normalize_sections(v$sections);v$selector<-NULL
  }))
  shiny::observeEvent(input$rpk_section_remove,safe(function(){capture();brohn_require(input$rpk_section_remove%in%vapply(v$sections,`[[`,character(1),"id"),"Choose a current figure section.")
    dirty();v$sections<-normalize_sections(Filter(function(s)s$id!=input$rpk_section_remove,v$sections))}))
  shiny::observeEvent(input$rpk_section_move,safe(function(){capture();x<-input$rpk_section_move;i<-which(vapply(v$sections,function(s)identical(s$id,x$id),logical(1)))
    brohn_require(length(i)==1L&&x$direction%in%c(-1L,1L)&&i+x$direction>=1L&&i+x$direction<=length(v$sections),"Choose a valid section position.")
    dirty();order<-seq_along(v$sections);order[c(i,i+x$direction)]<-order[c(i+x$direction,i)];v$sections<-normalize_sections(v$sections[order])}))
  selector_load<-function(ref,adapter,cursor=NULL){brohn_require(any(vapply(v$rows,function(r).brohn_rpv_same(r$ref,ref)&&adapter%in%unlist(r$adapters),logical(1))),"Choose a supported selected report.")
    preparation<-selector_preparation(ref,adapter)
    prepared<-Filter(function(p)identical(p$adapter,preparation)&&.brohn_rpv_same(p$source_report_ref,ref),prepared_sources(v$intent))
    saved_source<-!is.null(v$intent)&&any(vapply(v$intent$request$report_refs,function(r).brohn_rpv_same(r,ref),logical(1)))
    pinned_required<-identical(preparation,"task-display")||(!is.null(preparation)&&!is.null(v$intent)&&identical(v$intent$request$renderer_profile,"controlled-gaze-explicit-task-paired/0.1"))
    if(saved_source&&pinned_required&&!length(prepared)){
      v$selector<-list(report_ref=ref,adapter=adapter,items=list(),cursor=NULL,next_cursor=NULL,
        requires_display_preparation=TRUE,state="needs_preparation",prepared_ref=NULL,locked=TRUE,
        reason=paste("This saved preparation's exact views are not available for focused changes. Its requested choices are retained.",brohn_default(v$intent$reason,"Follow the preparation status above.")))
    }else if(!is.null(preparation)&&length(prepared)){
      brohn_require(length(prepared)==1L,"This source has ambiguous prepared evidence. Review the saved preparation.")
      page<-brohn_report_package_selector_catalog(store,ref,adapter,cursor=cursor,prepared_ref=prepared[[1]]$prepared_ref)
      # The generic catalog need not echo its optional input reference. Retain
      # the exact verified input to keep subsequent page refreshes bound to it.
      page$prepared_ref<-prepared[[1]]$prepared_ref;v$selector<-page
    }else v$selector<-brohn_report_package_selector_catalog(store,ref,adapter,cursor=cursor)
    if(.brohn_rpv_task_adapter(adapter))for(s in v$sections)if(.brohn_rpv_same(s$source_report_ref,ref)&&identical(s$adapter,adapter)&&!startsWith(s$selector$scope,"all_")){
      item<-Filter(function(item).brohn_rpv_same(item$selector,s$selector),v$selector$items)
      if(length(item)==1L){v$labels[[s$id]]<-item[[1]]$label;v$task_options[[s$id]]<-item[[1]]$details}
    }
  }
  shiny::observeEvent(input$rpk_selector_open,safe(function(){capture();x<-input$rpk_selector_open;cursors$selector<-list();selector_load(x$ref,x$adapter)}))
  shiny::observeEvent(input$rpk_selector_close,safe(function(){v$selector<-NULL}))
  set_selector<-function(x,all=FALSE){capture();p<-v$selector;brohn_require(!is.null(p)&&.brohn_rpv_same(x$ref,p$report_ref)&&identical(x$adapter,p$adapter),"Choose a view from the current figure list.")
    item<-if(all)NULL else Filter(function(item).brohn_rpv_same(item$selector,x$selector),p$items)
    brohn_require(!isTRUE(p$locked)&&!isTRUE(p$state%in%c("unavailable_source","needs_authority"))&&(all||length(item)==1L),"Choose an available saved view from this page.")
    s<-.brohn_rpv_section(x$ref,x$adapter,if(all)NULL else x$selector);dirty()
    keep<-Filter(function(old)!(.brohn_rpv_same(old$source_report_ref,x$ref)&&old$adapter==x$adapter&&
      (all||startsWith(old$selector$scope,"all_")||old$id==s$id)),v$sections)
    v$sections<-normalize_sections(c(keep,list(s)));v$labels[[s$id]]<-if(all)NULL else item[[1]]$label
    if(.brohn_rpv_task_adapter(s$adapter))v$task_options[[s$id]]<-if(all)NULL else item[[1]]$details}
  shiny::observeEvent(input$rpk_selector_choose,safe(function()set_selector(input$rpk_selector_choose)))
  shiny::observeEvent(input$rpk_selector_all,safe(function()set_selector(input$rpk_selector_all,TRUE)))
  page_next<-function(kind){capture_if<-kind!="history";if(capture_if)capture()
    p<-switch(kind,sources=v$choices,history=v$history,selector=v$selector);if(is.null(p)||is.null(p$next_cursor))return()
    cursors[[kind]]<-c(cursors[[kind]],list(p$cursor));switch(kind,sources=load_choices(p$next_cursor),history=load_history(p$next_cursor),selector=selector_load(p$report_ref,p$adapter,p$next_cursor))}
  page_previous<-function(kind){stack<-cursors[[kind]];if(!length(stack))return();if(kind!="history")capture()
    cursor<-stack[[length(stack)]];cursors[[kind]]<-head(stack,-1L)
    switch(kind,sources=load_choices(cursor),history=load_history(cursor),selector=selector_load(v$selector$report_ref,v$selector$adapter,cursor))}
  for(kind in c("sources","history","selector"))local({k<-kind
    shiny::observeEvent(input[[paste0("rpk_",k,"_next")]],safe(function()page_next(k)))
    shiny::observeEvent(input[[paste0("rpk_",k,"_previous")]],safe(function()page_previous(k)))})
  shiny::observeEvent(input$rpk_history_latest,safe(function(){cursors$history<-list();load_history()}))
  shiny::observeEvent(input$rpk_history_open,safe(function(){ref<-input$rpk_history_open
    brohn_require(any(vapply(v$history$items,function(item).brohn_rpv_same(item$intent_ref,ref),logical(1))),"Choose a preparation from the current history page.")
    clear_view();view<-brohn_read_report_package_intent(store,ref$id,v$scope$project_id);adopt(view);hydrate(view);v$selector<-NULL
    if(view$status=="succeeded")start("open",view,"Opening the exact saved report.")else{v$focus_token<-NULL;v$automatic<-FALSE}
  }))
  shiny::observe({
    if(!active()||isTRUE(v$dirty)||!identical(input$rpk_form_identity,v$form_identity))return()
    expected<-if(!is.null(v$pending)&&v$pending$action=="save")v$pending$payload$request else if(!is.null(v$intent))v$intent$request else NULL
    if(is.null(expected))return()
    fresh<-tryCatch(request(FALSE),error=function(e)NULL)
    if(is.null(fresh)||!.brohn_rpv_same(fresh,expected))dirty()
  },priority=100)
  output$rpk_context<-shiny::renderUI({if(!active()||is.null(v$choices))return(NULL)
    shiny::p(paste("Study:",v$choices$study$title,". Saved report versions determine the design and findings in this package."))})
  output$rpk_editor<-shiny::renderUI({if(!active())return(NULL);v$editor_tick
    shiny::isolate({if(is.null(v$draft))NULL else{d<-v$draft;d$form_identity<-v$form_identity;brohn_report_package_editor_ui(d)}})})
  output$rpk_contents<-shiny::renderUI({if(!active())return(NULL)
    task<-any(vapply(v$rows,function(row)isTRUE(row$source_family%in%c("native_questionnaire","imported_implicit","saved_task_cohort")),logical(1)))
    shiny::tagList(shiny::p(paste(length(v$rows),"saved reports and",length(v$sections),"figure sections selected. Complete numerical collections stay included, even when only selected figure pages are shown.")),
      if(task)shiny::tagList(shiny::p("Task scores and response patterns, liking and other answers, and saved comparisons are included where applicable. Task details are checked during preparation."),
        shiny::p("These findings are shown together; no relationship between task scores and liking has been calculated.")),
      if(!is.null(v$recommendation_note))shiny::p(v$recommendation_note))})
  output$rpk_sources<-shiny::renderUI({if(!active()||is.null(v$choices))return(NULL);brohn_report_package_sources_ui(v$choices,v$rows)})
  output$rpk_selected<-shiny::renderUI({if(!active())return(NULL);shiny::tags$ul(lapply(v$rows,function(row)shiny::tags$li(row$title," | ",row$origin," | saved version ",row$ref$revision,
    brohn_command(paste("Remove",row$title),"rpk_source_toggle",row$ref))))})
  output$rpk_figures<-shiny::renderUI({if(!active())return(NULL);brohn_report_package_figures_ui(v$sections,v$labels,v$task_options,v$rows)})
  output$rpk_material_scope<-shiny::renderUI({if(!active())return(NULL)
    gaze<-any(vapply(v$rows,function(row)"gaze-context"%in%unlist(row$adapters),logical(1)))
    task<-any(vapply(v$rows,function(row)isTRUE(row$source_family%in%c("native_questionnaire","imported_implicit","saved_task_cohort")),logical(1)))
    shiny::tagList(shiny::p(if(gaze)"This option embeds supported PNG/JPEG gaze stimulus images."else
      "No gaze source is selected. The gaze image option does not apply to this report."),
      if(task)shiny::p("Task material definitions and hashes are included as saved references. Task material image bytes are not embedded in this report version. Original study design and asset exports remain available from the study."))})
  output$rpk_selector<-shiny::renderUI({if(!active()||is.null(v$selector))return(NULL);brohn_report_package_selector_ui(v$selector)})
  output$rpk_history<-shiny::renderUI({if(!active()||is.null(v$history))return(NULL);brohn_report_package_history_ui(v$history)})
  output$rpk_feedback<-shiny::renderUI({if(!active())return(NULL);p<-v$pending;i<-v$intent
    label<-if(!is.null(v$issue))v$issue else if(!is.null(p))p$label else if(isTRUE(v$dirty))"Report choices changed. Prepare them to create a new saved version."else if(!is.null(i))paste(.brohn_rpv_status(i$status,i$dependencies),brohn_default(i$reason,""))else"Review the contents, then prepare your report."
    shiny::div(id="rpk_status",role="status",`aria-live`="polite",tabindex="-1",
      `data-rpk-ticket`=if(is.null(p))NULL else p$ticket,`data-rpk-focus`=v$focus_token,
      `data-rpk-phase`=v$phase,`data-rpk-passive`=if(!is.null(p)&&isTRUE(p$passive))"true"else"false",
       shiny::p(label),
       if(!is.null(i)&&!isTRUE(v$dirty)&&identical(i$preparation$reason_code,"panel_limit"))shiny::p(paste(
         "These choices need",i$preparation$resolved_panel_count,"illustrated panels; the limit is",paste0(i$preparation$maximum_panels,"."),
         "Open Change contents to choose fewer figure views or pages. Complete numerical evidence remains included.")),
       if(!is.null(i)&&!isTRUE(v$dirty)&&identical(i$next_action,"review"))shiny::tagList(
         shiny::p("Review the reason above. A new version uses current preparation code and keeps earlier saved versions available."),
         shiny::actionButton("rpk_prepare_new","Prepare these choices as a new version")),
       if(!is.null(i)&&!isTRUE(v$dirty)&&i$next_action%in%c("resume","retry","continue"))
        shiny::actionButton("rpk_resume",if(i$next_action=="retry")"Retry preparation"else"Resume preparation"),
      if(!is.null(i)&&i$status=="succeeded"&&is.null(native$handle)&&is.null(p)&&!isTRUE(v$dirty))shiny::actionButton("rpk_reopen","Reopen saved report"),
       if(!is.null(p)||(!is.null(i)&&i$status%in%c("prepared","waiting_for_display","ready_to_freeze","assembly_queued","needs_authority","failed","needs_attention")))shiny::actionButton("rpk_cancel","Cancel preparation"))})
  output$rpk_ready<-shiny::renderUI({if(!active())return(NULL);urls<-v$urls
    if(is.null(native$handle)||!length(urls)||isTRUE(v$dirty))return(NULL)
    shiny::tagList(shiny::h2("Your report is ready",tabindex="-1",`data-rpk-complete`=v$focus_token),
      shiny::p("The HTML contains the selected figures and bounded tables. The ZIP also contains every row in the included numerical collections and its evidence inventory."),
      shiny::div(class="brohn-toolbar",shiny::tags$a(class="btn btn-primary",href=urls$html,"Download report"),
        shiny::tags$a(class="btn btn-outline-secondary",href=urls$zip,"Download report + evidence")))})
  invisible(list(state=v))
}
