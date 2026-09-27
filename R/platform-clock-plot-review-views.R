# Plot preparation has its own state: original-window downloads remain usable
# while this optional complete-export display is waiting, failed or cancelled.
.brohn_clock_job_error <- function(job,fallback) {
  detail<-if(is.list(job$error))job$error$message else NULL
  if(is.character(detail)&&length(detail)==1L&&!is.na(detail)&&nzchar(trimws(detail)))substr(detail,1L,1000L)else fallback
}
brohn_install_clock_plot_review <- function(input,output,session,store,v,native,active_window,safe) {
  valid<-function(p)!is.null(p)&&isTRUE(v$enabled)&&identical(p$generation,v$generation)&&
    !is.null(v$window)&&.brohn_cm_same(p$window,.brohn_cm_ref(v$window))
  current<-function(p){brohn_require(valid(p),"Open the original measurement window again.")
    active_window();brohn_require(identical(input$clock_window_start,v$window$body$request$selection$start_s)&&
      identical(input$clock_window_end,v$window$body$request$selection$end_s),"Apply the edited window before preparing its overview.")}
  failed<-function(p,e){if(!valid(p))return();p$phase<-"failed";p$error<-conditionMessage(e);v$plot_pending<-p}
  open<-function(ref,p){current(p)
    if(!is.null(native$plot_handle))brohn_release_clock_plot_resources(native$plot_handle)
    native$plot_handle<-NULL;v$plot<-NULL;v$plot_url<-NULL
    opened<-brohn_open_clock_plot_resources(store,ref,native$handle);native$plot_handle<-opened$handle
    token<-brohn_token();generation<-v$generation;artifact<-opened$artifact
    uri<-session$registerDataObj("clock-complete-plot",list(token=token,ref=ref),function(data,req)shiny::isolate(tryCatch({
      brohn_require(req$REQUEST_METHOD%in%c("GET","HEAD")&&identical(generation,v$generation)&&
        identical(shiny::parseQueryString(brohn_default(req$QUERY_STRING,""))$key,data$token),"Expired overview download.")
      current(v$plot_pending);fresh<-brohn_clock_plot_resources_current(store,native$plot_handle)
      brohn_require(.brohn_cm_same(.brohn_cm_ref(fresh$record),data$ref)&&.brohn_cm_same(fresh$artifact,artifact),"This overview no longer matches the opened original window.")
      brohn_http_identity_response(structure(list(status=200L,content_type=artifact$media_type,content=list(file=artifact$path,owned=FALSE),
        headers=list("Cache-Control"="no-store","X-Content-Type-Options"="nosniff","Content-Disposition"='attachment; filename="clock-overview.json"')),class="httpResponse"))
    },error=function(e)brohn_http_identity_response(structure(list(status=404L,content_type="text/plain",content="Reopen the saved original window to download its overview."),class="httpResponse")))))
    v$plot<-opened$plot;v$plot_url<-paste0(uri,"&key=",token);p$phase<-"ready";p$error<-NULL;v$plot_pending<-p
  }
  begin<-function(){brohn_require(!is.null(v$window),"Open a measurement window before its overview.")
    v$plot_pending<-list(ticket=brohn_token(),generation=v$generation,window=.brohn_cm_ref(v$window),phase="preparing",job=NULL,retry_job=NULL,error=NULL)}
  shiny::observeEvent(input$clock_plot_prepare_ack,{p<-v$plot_pending
    if(!valid(p)||!identical(p$phase,"preparing")||!identical(input$clock_plot_prepare_ack,p$ticket))return()
    tryCatch({current(p);ref<-brohn_find_clock_plot(store,p$window,v$window$project_id)
      if(!is.null(ref)){open(ref,p);return()}
      previous<-if(is.null(p$retry_job))NULL else brohn_get_job(store,p$retry_job)
      if(!is.null(previous)&&previous$status%in%c("failed","cancelled")){
        request<-brohn_clock_retry_request(store,previous)
        job<-brohn_enqueue_job(store,previous$operation,request,paste0("clock-plot-retry:",previous$id,":",brohn_id("request")))
      }else if(!is.null(previous)&&previous$status%in%c("queued","running")){job<-previous
      }else job<-brohn_queue_clock_plot(store,p$window,v$window$project_id)
      p$job<-job$id;p$phase<-"waiting";v$plot_pending<-p
    },error=function(e)failed(p,e))})
  shiny::observe({shiny::invalidateLater(900,session);p<-v$plot_pending
    if(!valid(p)||!identical(p$phase,"waiting"))return()
    tryCatch({current(p);job<-brohn_get_job(store,p$job);brohn_require(!is.null(job),"The overview processing receipt is unavailable.")
      if(job$status%in%c("failed","cancelled"))stop(paste("Overview",job$status,.brohn_clock_job_error(job,"Original window exports are still available.")))
      if(!identical(job$status,"succeeded"))return()
      record<-brohn_get_entity(store,"clock_plot",job$result$clock_plot_id);brohn_require(!is.null(record),"The saved overview is unavailable.")
      open(.brohn_cm_ref(record),p)
    },error=function(e)failed(p,e))})
  shiny::observeEvent(input$clock_plot_cancel,safe(function(){p<-v$plot_pending;brohn_require(valid(p)&&p$phase%in%c("preparing","waiting"),"There is no overview preparation to cancel.")
    if(!is.null(p$job)){job<-brohn_get_job(store,p$job);if(!is.null(job)&&job$status%in%c("queued","running"))brohn_cancel_job(store,p$job)}
    failed(p,simpleError("Overview preparation cancelled. Your original window and its four complete exports remain available."))}))
  shiny::observeEvent(input$clock_plot_retry,safe(function(){p<-v$plot_pending
    brohn_require(valid(p)&&identical(p$phase,"failed"),"Retry an unavailable overview.")
    # Publish fresh feedback first. Native/source/reader work runs only after
    # this ticket has painted, just as it does for initial plot preparation.
    p$ticket<-brohn_token();p$retry_job<-p$job;p$phase<-"preparing";p$error<-NULL;v$plot_pending<-p}))
  output$clock_plot_status<-shiny::renderUI({p<-v$plot_pending;if(!valid(p))return(NULL)
    if(!identical(input$clock_window_start,v$window$body$request$selection$start_s)||!identical(input$clock_window_end,v$window$body$request$selection$end_s))return(NULL)
    shiny::div(role="status",`aria-live`="polite",`data-clock-plot-ticket`=p$ticket,`data-clock-plot-phase`=p$phase,
      shiny::p(class=if(p$phase=="ready")"visually-hidden"else NULL,if(p$phase=="ready")"Complete-window overview ready."else if(p$phase=="failed")p$error else
        "Preparing an overview from every selected original row. The four original-data downloads are available below."),
      if(p$phase%in%c("preparing","waiting"))shiny::actionButton("clock_plot_cancel","Cancel overview preparation"),
      if(p$phase=="failed")shiny::actionButton("clock_plot_retry","Retry overview preparation"))})
  output$clock_plot_result<-shiny::renderUI({p<-v$plot_pending;if(!valid(p)||!identical(p$phase,"ready")||is.null(v$plot))return(NULL)
    tryCatch({current(p);brohn_clock_plot_resources_current(store,native$plot_handle)
      shiny::tagList(brohn_clock_plot_view(v$plot),shiny::tags$a(class="btn btn-outline-secondary",href=v$plot_url,"Download complete overview evidence (JSON)"))
    },error=function(e)shiny::p(role="status",paste("Reopen this original window to review its overview.",conditionMessage(e))))})
  invisible(list(begin=begin))
}
