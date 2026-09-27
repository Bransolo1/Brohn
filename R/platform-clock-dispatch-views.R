brohn_install_clock_review_dispatch <- function(input,output,session,store,v,native,dataset,selections,form,start,safe,release,accept_page) {
  valid<-function(p)!is.null(p)&&isTRUE(v$enabled)&&identical(p$generation,v$generation)
  set_map<-function(ref){m<-.brohn_cm_record(store,"clock_map",ref,dataset()$project_id,FALSE)
    request<-list(schema="brohn-clock-window-job/0.1",project_id=m$project_id,map=ref,
      selection=brohn_clock_initial_window(m$body$result$mapping),implementation=.brohn_clock_window_loaded)
    .brohn_cw_context(store,request,FALSE,FALSE,FALSE)
    v$map<-m;shiny::updateTextInput(session,"clock_name",value=m$body$title);m}
  active<-function(){brohn_require(isTRUE(v$enabled)&&!is.null(v$window)&&!is.null(native$handle),"Reopen the exact saved measurement window.")
    p<-v$pending;brohn_require(is.null(p)||identical(p$phase,"ready"),"Wait until the selected measurement window is ready.")
    r<-v$window;dataset();brohn_require(identical(input$clock_window_start,r$body$request$selection$start_s)&&
      identical(input$clock_window_end,r$body$request$selection$end_s),"Apply the edited measurement window before exporting.")
    brohn_clock_window_resources_current(store,native$handle)}
  plot_review<-brohn_install_clock_plot_review(input,output,session,store,v,native,active,safe)
  open_window<-function(ref){release();opened<-brohn_open_clock_window_resources(store,ref,dataset()$project_id)
    native$handle<-opened$handle;v$window<-opened$record;v$map<-.brohn_cm_record(store,"clock_map",opened$record$body$map,dataset()$project_id,FALSE)
    token<-brohn_token();generation<-v$generation;urls<-list()
    for(a in opened$artifacts)local({a<-a
      uri<-session$registerDataObj(paste0("clock-",a$kind),list(token=token,ref=ref),function(data,req)shiny::isolate(tryCatch({
        brohn_require(req$REQUEST_METHOD%in%c("GET","HEAD")&&identical(v$generation,generation)&&
          identical(shiny::parseQueryString(brohn_default(req$QUERY_STRING,""))$key,data$token),"Expired alignment download.")
        fresh<-active();brohn_require(.brohn_cm_same(.brohn_cm_ref(fresh$record),data$ref),"The saved measurement window changed.")
        expected<-Filter(function(x)identical(x$kind,a$kind),fresh$artifacts)
        brohn_require(length(expected)==1L&&.brohn_cm_same(expected[[1L]],a),"The original download descriptor changed.")
        structure(list(status=200L,content_type=a$media_type,content=list(file=a$path,owned=FALSE),
          headers=list("Cache-Control"="no-store","X-Content-Type-Options"="nosniff",
            "Content-Disposition"=paste0('attachment; filename="',a$file,'"'))),class="httpResponse")
      },error=function(e)structure(list(status=404L,content_type="text/plain",content="This download is no longer current. Reopen the saved measurement window."),class="httpResponse"))))
      urls[[a$kind]]<<-paste0(uri,"&key=",token)
    })
    v$urls<-urls;invisible(opened$record)}
  fail<-function(p,e){if(!valid(p))return();p$phase<-"failed";p$error<-conditionMessage(e);v$pending<-p;v$issue<-p$error}
  ready<-function(p){if(!valid(p))return();p$phase<-"ready";v$pending<-p;v$result_ticket<-p$ticket;v$result_kind<-p$action;v$issue<-NULL}
  queue_window<-function(p,map){selection<-brohn_clock_initial_window(map$body$result$mapping)
    j<-brohn_queue_clock_window(store,.brohn_cm_ref(map),selection,map$project_id)
    p$action<-"window";p$payload<-list(map=.brohn_cm_ref(map),selection=selection);p$jobs<-list(window=j$id)
    p$phase<-"waiting";p$label<-"Alignment saved. Preparing original measurements for its full supported span.";v$pending<-p}
  dispatch<-function(p){if(!valid(p))return();project<-dataset()$project_id;payload<-p$payload
    tryCatch({
      if(p$action=="events"){
        brohn_require(.brohn_cm_same(v$selections,selections()),"The selected recordings changed. Load their events again.")
        p$jobs<-brohn_store_batch(store,function()lapply(v$selections,function(s)brohn_queue_clock_events(store,s,project)$id))
      }else if(p$action=="eventpage"){
        brohn_require(.brohn_cm_same(v$selections,selections()),"The selected recordings changed. Load their events again.")
        p$jobs<-stats::setNames(list(brohn_queue_clock_events(store,v$selections[[payload$side]],project,payload$query,payload$offset)$id),payload$side)
      }else if(p$action=="preview"){
        brohn_require(.brohn_cm_same(form(),payload),"Event choices changed before preparation. Preview the current choices.")
        p$jobs<-list(preview=brohn_clock_selected_preview(store,payload$selections$source,payload$selections$reference,
          payload$anchors,payload$checks,payload$review,project,enqueue=TRUE)$id)
      }else if(p$action=="save"){
        brohn_require(!is.null(v$preview)&&.brohn_cm_same(form(),v$preview$form)&&.brohn_cm_same(.brohn_cm_ref(v$preview$record),payload$preview),
          "The accepted event preview changed. Review the updated pairs before saving.")
        p$jobs<-list(save=brohn_queue_clock_map_save(store,payload$preview,payload$title,project,payload$map_id,payload$revision,payload$operation_id)$id)
      }else if(p$action=="window"){
        release();p$jobs<-list(window=brohn_queue_clock_window(store,payload$map,payload$selection,project)$id)
      }else if(p$action=="map"){
        release();set_map(payload$ref);v$editing<-NULL;ready(p);return()
      }else if(p$action=="open"){
        open_window(payload$ref);ready(p);plot_review$begin();return()
      }else stop("Unknown alignment step.")
      p$phase<-"waiting";v$pending<-p
    },error=function(e)fail(p,e))}
  shiny::observeEvent(input$clock_review_prepare_ack,{p<-v$pending
    if(valid(p)&&identical(p$phase,"preparing")&&identical(input$clock_review_prepare_ack,p$ticket))dispatch(p)})
  shiny::observe({shiny::invalidateLater(900,session);p<-v$pending;if(!valid(p)||!identical(p$phase,"waiting"))return()
    tryCatch({jobs<-lapply(p$jobs,function(id)brohn_get_job(store,id));brohn_require(all(vapply(jobs,function(j)!is.null(j),logical(1))),"An alignment processing receipt is unavailable.")
      bad<-Filter(function(j)j$status%in%c("failed","cancelled"),jobs)
      if(length(bad))stop(paste("Alignment step",bad[[1L]]$status,.brohn_clock_job_error(bad[[1L]],"The original source is retained.")))
      if(!all(vapply(jobs,function(j)identical(j$status,"succeeded"),logical(1))))return()
      if(p$action%in%c("events","eventpage")){
        brohn_require(.brohn_cm_same(v$selections,selections()),"The recording or channel selection changed while events were loading.")
        for(side in names(jobs)){record<-brohn_get_entity(store,"clock_events",jobs[[side]]$result$clock_events_id)
          accept_page(side,brohn_clock_events_record(store,.brohn_cm_ref(record),dataset()$project_id,FALSE))}
      }else if(p$action=="preview"){
        brohn_require(.brohn_cm_same(form(),p$payload),"The selected events changed while the preview was being prepared. Preview the updated pairs.")
        record<-brohn_get_entity(store,"clock_preview",jobs[[1L]]$result$clock_preview_id)
        record<-.brohn_cm_record(store,"clock_preview",.brohn_cm_ref(record),dataset()$project_id,FALSE)
        brohn_clock_preview_input(store,record$body$request,FALSE);v$preview<-list(record=record,form=p$payload)
      }else if(p$action=="save"){
        v$last_save<-list(form=p$payload$form,title=p$payload$title,preview=p$payload$preview,map=jobs[[1L]]$result$clock_map)
        brohn_require(.brohn_cm_same(form(),p$payload$form)&&identical(input$clock_name,p$payload$title),"The saved alignment is retained in history, but the draft changed while saving. Review the current event choices before replacing this draft.")
        map<-set_map(jobs[[1L]]$result$clock_map);v$editing<-.brohn_cm_ref(map);queue_window(p,map);return()
      }else if(p$action=="window"){
        brohn_require(identical(input$clock_window_start,p$payload$selection$start_s)&&identical(input$clock_window_end,p$payload$selection$end_s),
          "The completed window is retained in history. Apply the newly edited bounds to review those measurements.")
        record<-brohn_get_entity(store,"clock_window",jobs[[1L]]$result$clock_window_id);open_window(.brohn_cm_ref(record))
      }
      ready(p);if(identical(p$action,"window"))plot_review$begin()
    },error=function(e)fail(p,e))})
  shiny::observeEvent(input$clock_cancel,safe(function(){p<-v$pending;if(!valid(p))return()
    for(id in p$jobs){j<-brohn_get_job(store,id);if(j$status%in%c("queued","running"))brohn_cancel_job(store,id)}
    p$phase<-"failed";p$error<-"This step was cancelled. Original recordings and completed results are retained.";v$pending<-p;v$issue<-p$error}))
  shiny::observeEvent(input$clock_retry,safe(function(){p<-v$pending;brohn_require(valid(p)&&identical(p$phase,"failed"),"Choose a failed or cancelled alignment step to retry.")
    if(!length(p$jobs)){start(p$action,p$payload,p$label);return()}
    p$jobs<-brohn_store_batch(store,function(){ids<-p$jobs
      for(name in names(ids)){j<-brohn_get_job(store,ids[[name]]);if(j$status%in%c("failed","cancelled")){
        r<-brohn_clock_retry_request(store,j);ids[[name]]<-brohn_enqueue_job(store,j$operation,r,paste0("clock-retry:",j$id,":",brohn_id("request")))$id}}
      ids})
    p$phase<-"waiting";p$error<-NULL;v$pending<-p;v$issue<-NULL}))
  output$clock_status<-shiny::renderUI({p<-v$pending;issue<-v$issue
    if(is.null(p))return(if(!is.null(issue))shiny::p(role="status",class="brohn-alert",issue)else NULL)
    shiny::div(tabindex="-1",role="status",`aria-live`="polite",`data-clock-review-ticket`=p$ticket,`data-clock-review-phase`=p$phase,
      shiny::p(if(p$phase=="ready")"Alignment step ready."else if(p$phase=="failed")brohn_default(p$error,issue)else p$label),
      if(!is.null(issue)&&p$phase!="failed")shiny::p(issue),
      if(p$phase%in%c("preparing","waiting"))shiny::actionButton("clock_cancel","Cancel current step"),
      if(p$phase=="failed")shiny::actionButton("clock_retry","Retry this step"))})
  output$clock_map_details<-shiny::renderUI({m<-v$map;if(is.null(m))return(NULL)
    names<-lapply(m$body$request$selections,function(s){d<-brohn_get_entity(store,"dataset",s$dataset_id)
      brohn_require(!is.null(d)&&identical(d$project_id,m$project_id)&&!isTRUE(d$body$archived),"The original recording is unavailable.");d$body$title})
    shiny::div(shiny::h3(`data-clock-review-complete`=if(identical(v$result_kind,"map"))v$result_ticket else NULL,tabindex="-1",paste(m$body$title,"| version",m$revision)),
      shiny::p(paste("Source:",names$source,"| Reference:",names$reference)),
      shiny::p("This reviewed affine mapping changes the review coordinate only. It does not establish physical synchronization or alter original measurements."),
      shiny::actionButton("clock_edit_map","Revise event pairs as a new version"))})
  output$clock_window_controls<-shiny::renderUI({m<-v$map;if(is.null(m))return(NULL);r<-v$window
    selected<-if(is.null(r))brohn_clock_initial_window(m$body$result$mapping)else r$body$request$selection
    shiny::tagList(shiny::div(class="brohn-form-grid",shiny::textInput("clock_window_start","Window start (reference-relative seconds)",selected$start_s),
      shiny::textInput("clock_window_end","Window end (exclusive, reference-relative seconds)",selected$end_s)),
      shiny::actionButton("clock_window_apply","Review original measurements",class="btn-primary"))})
  submit_window<-function(offset=0L){brohn_require(!is.null(v$map),"Save or reopen an alignment first.")
    selection<-list(start_s=brohn_default(input$clock_window_start,""),end_s=brohn_default(input$clock_window_end,""),offset=as.integer(offset))
    .brohn_cw_selection(selection);start("window",list(map=.brohn_cm_ref(v$map),selection=selection),"Preparing the selected original measurement window.")}
  shiny::observeEvent(input$clock_window_apply,safe(function()submit_window()))
  shiny::observeEvent(input$clock_rows_next,safe(function(){r<-active()$record;b<-r$body$result$result;next_offset<-b$selection$offset+100L
    brohn_require(next_offset<b$counts$selected_rows,"This is the last numerical page.");submit_window(next_offset)}))
  shiny::observeEvent(input$clock_rows_previous,safe(function(){r<-active()$record;offset<-r$body$result$result$selection$offset
    brohn_require(offset>0L,"This is the first numerical page.");submit_window(max(0L,offset-100L))}))
  output$clock_window_result<-shiny::renderUI({r<-v$window;if(is.null(r))return(NULL);b<-r$body$result$result
    if(!identical(input$clock_window_start,b$selection$start_s)||!identical(input$clock_window_end,b$selection$end_s))return(
      shiny::p(role="status","The window bounds changed. Apply the edited window to review or export those measurements."))
    titles<-c(selected_original_rows="Download all selected original rows (CSV)",all_source_unplaced_rows="Download all unplaced source rows (CSV)",
      complete_original_segments="Download complete segment evidence (JSONL)",clock_window_manifest="Download mapping and window evidence (JSON)")
    shown<-lapply(b$rows,function(row){track<-Filter(function(t)identical(t$track_id,row$track_id)&&identical(t$recording_side,row$recording_side),b$tracks)
      display<-row;display$track_id<-if(length(track)==1L)track[[1L]]$channel$label else row$channel_id
      shiny::tags$tr(lapply(c("recording_side","track_id","source_sequence","source_timestamp","timestamp_unit","value_json"),
      function(field)shiny::tags$td(style="overflow-wrap:anywhere",brohn_default(display[[field]],"Unavailable"))),
      shiny::tags$td(paste(row$reference_relative_seconds_numerator,row$reference_relative_seconds_denominator,sep="/")))})
    shiny::div(shiny::h3(`data-clock-review-complete`=if(v$result_kind%in%c("open","window"))v$result_ticket else NULL,tabindex="-1","Original measurements on the reviewed timeline"),
      shiny::uiOutput("clock_plot_status"),shiny::uiOutput("clock_plot_result"),
      shiny::p(if(b$counts$selected_rows==0L)"No original observations fall inside this window."else paste(b$counts$selected_rows,"original observations in the complete selected window.")),
      shiny::p(paste(b$counts$unplaced_rows,"source rows have no original observed time; no window membership is assigned to them.")),
      shiny::p("Start is included; end is excluded. Rows are shown by recording and track, preserving their original sequence. No resampling, interpolation or scientific scoring is performed."),
      shiny::div(class="brohn-toolbar",lapply(names(v$urls),function(kind)shiny::tags$a(class="btn btn-outline-secondary",href=v$urls[[kind]],titles[[kind]]))),
      shiny::p(paste("Numerical page:",length(b$rows),"rows, starting at",if(length(b$rows))b$selection$offset+1L else 0L,"of",b$counts$selected_rows,"selected rows. Complete exports include every selected row.")),
      shiny::div(style="overflow-x:auto",tabindex="0",role="region",`aria-label`="Original measurement table",
        shiny::tags$table(class="table",shiny::tags$thead(shiny::tags$tr(lapply(c("Recording","Track","Original row","Original time","Unit","Original value","Reference-relative seconds (exact fraction)"),shiny::tags$th))),shiny::tags$tbody(shown))),
      shiny::div(class="brohn-toolbar",shiny::actionButton("clock_rows_previous","Previous 100 rows"),shiny::actionButton("clock_rows_next","Next 100 rows")),
      shiny::tags$details(shiny::tags$summary("Coverage and exact processing evidence"),shiny::tags$pre(style="white-space:pre-wrap;overflow-wrap:anywhere",brohn_json(b[c("counts","tracks","mapping_support","unplaced_scope","binding")],TRUE))))})
  invisible(list(active=active,dispatch=dispatch))
}
