# Exact source frames alongside an existing saved waveform. No new scoring.
.brohn_mr_time<-function(x)if(is.null(x))"Unavailable"else x$display_s
brohn_media_review_waveform_svg<-function(audio,result,width=920L) {
  svg<-gsub("ar-waveform-","mr-waveform-",brohn_audio_review_svg(audio,"waveform",width),fixed=TRUE);s<-audio$support;rate<-audio$source$sampling_rate
  left<-if(width<500)65 else 105;right<-width-22
  x<-left+(result$selection$cursor_sample-s$first_sample)/(s$stop_sample-s$first_sample)*(right-left)
  cursor<-sprintf('<line data-media-cursor-sample="%s" x1="%.9f" x2="%.9f" y1="42" y2="250" stroke="#f0cb82" stroke-width="2"><title>Selected original audio sample %s</title></line>',result$selection$cursor_sample,x,x,result$selection$cursor_sample)
  metadata<-paste0('<metadata id="brohn-media-mapping">',as.character(htmltools::htmlEscape(brohn_json(list(schema="brohn-media-waveform-figure/1.0",binding=result$binding,mapping=result$mapping,coverage=result$coverage)))),'</metadata>')
  sub("</svg>",paste0(metadata,cursor,"</svg>"),svg,fixed=TRUE)
}
brohn_install_media_review<-function(input,output,session,store,state,attempt,message,refresh,prepare_download) {
  selection<-shiny::reactiveVal(NULL);catalog<-shiny::reactiveVal(NULL);opened<-shiny::reactiveVal(NULL);pending<-shiny::reactiveVal(NULL);issue<-shiny::reactiveVal(NULL)
  resources<-shiny::reactiveVal(NULL);identity<-shiny::reactiveVal(NULL);preparing<-shiny::reactiveVal(NULL)
  native<-new.env(parent=emptyenv());native$view<-NULL;native$ready<-FALSE
  release<-function(){if(!is.null(native$view))brohn_close_media_review(native$view);native$view<-NULL;native$ready<-FALSE;resources(NULL)}
  close<-function(){release();selection(NULL);catalog(NULL);opened(NULL);pending(NULL);identity(NULL);preparing(NULL)}
  session$onSessionEnded(close)
  current<-function(){s<-selection();brohn_require(!is.null(s)&&identical(state$page,"report")&&identical(state$report_id,s$report_id),"Reopen the saved acoustic report and audio window.")
    fresh<-s$callback();brohn_require(.brohn_mr_same(.brohn_mr_ref(fresh),s$ref),"The original audio window changed. Reopen its media review.")
    brohn_media_review_source(store,s$ref,s$project_id,FALSE)}
  form<-function(strict=FALSE){s<-selection();resolve<-function()brohn_media_cursor_seconds(brohn_default(input$media_review_seconds,""),s$rate,s$first_sample,s$stop_sample)
    cursor<-if(strict)resolve()else tryCatch(resolve(),error=function(e)NULL)
    list(video_stream_index=suppressWarnings(as.numeric(input$media_review_track)),cursor_sample=if(is.null(cursor))NA_real_ else cursor$sample,resolved=cursor)}
  same<-function(r){f<-form();!is.null(r)&&identical(r$body$request$operation,"media_review")&&
    isTRUE(f$video_stream_index==r$body$request$selection$video_stream_index)&&isTRUE(f$cursor_sample==r$body$request$selection$cursor_sample)}
  active<-function(){s<-current();r<-opened();brohn_require(same(r)&&native$ready&&!is.null(native$view)&&isTRUE(native$view$state$active)&&identical(native$view$record$id,r$id),"Apply or reopen this exact media cursor before using its exports.")
    for(g in native$view$guards).Call(g$native$check,g$pointer)
    brohn_media_review_record(store,r$id,s$review$id,s$review$project_id,FALSE)}
  show<-function(){shiny::showModal(shiny::modalDialog(title="Video and original audio",size="l",easyClose=FALSE,
    shiny::p("Inspect recorded pixels beside the saved waveform using original container timestamps. This does not establish physical synchronization or link external sensors."),
    shiny::uiOutput("media_review_controls"),shiny::uiOutput("media_review_status"),shiny::uiOutput("media_review_result"),shiny::uiOutput("media_review_history"),
    footer=shiny::actionButton("media_review_close","Back to audio review")))}
  open<-function(reference,callback){brohn_require(is.function(callback),"Keep the original audio-window selection attached to media review.")
    fresh<-callback();brohn_require(.brohn_mr_same(.brohn_mr_ref(fresh),reference)&&identical(state$page,"report")&&identical(state$report_id,fresh$body$report_id),"Open media from the exact saved acoustic window.")
    brohn_require(!is.null(fresh$body$request$extraction_lineage),"This saved audio window has no original video derivation.");close();issue(NULL)
    selection(list(ref=reference,callback=callback,project_id=fresh$project_id,report_id=fresh$body$report_id,
      rate=fresh$body$result$source$sampling_rate,first_sample=fresh$body$result$support$first_sample,stop_sample=fresh$body$result$support$stop_sample,
      start_s=fresh$body$request$selection$start_s,end_s=fresh$body$request$selection$end_s,report_ref=fresh$body$request$report,
      audio_catalog=.brohn_qexplorer_catalog(store,"audio_review",fresh$id,fresh$revision,fresh$project_id),
      report_catalog=.brohn_qexplorer_catalog(store,"report",fresh$body$request$report$id,fresh$body$request$report$revision,fresh$project_id)));identity(brohn_hash(reference));show()
    session$onFlushed(function()shiny::isolate({if(is.null(selection())||!identical(identity(),brohn_hash(reference)))return()
      tryCatch({brohn_hosted_require_session(store);existing<-brohn_list_entities(store,"media_review",fresh$project_id,limit=40L,filters=list(audio_review_id=fresh$id))
        inventories<-Filter(function(x)identical(x$body$request$operation,"media_tracks"),existing)
        if(length(inventories)){current();catalog(brohn_media_review_record(store,inventories[[1L]]$id,fresh$id,fresh$project_id,FALSE))}else submit("media_tracks")
      },error=function(e){issue(conditionMessage(e));pending(NULL);release()})
    }),once=TRUE)
  }
  shiny::observeEvent(input$media_review_close,attempt(function(){close();shiny::removeModal()}))
  shiny::observeEvent(list(state$page,state$report_id),close(),ignoreInit=TRUE,priority=110)
  output$media_review_controls<-shiny::renderUI({s<-selection();if(is.null(s))return(NULL);c<-catalog()
    if(is.null(c))return(if(!is.null(issue()))shiny::p("The source inspection needs attention. Review the message below or return to the saved audio window.")else shiny::p("Inspecting the original video tracks. No acoustic analysis is repeated; cancellation remains available below."))
    tracks<-Filter(function(t)!isTRUE(t$attached_picture),c$body$result$tracks)
    if(!length(tracks))return(shiny::p(role="status","This container has no supported video track; the original audio remains available."))
    choices<-setNames(vapply(tracks,function(t)as.character(t$stream_index),character(1)),vapply(tracks,function(t)paste("Stream",t$stream_index,"|",t$codec,"|",t$width,"x",t$height),character(1)))
    shiny::tagList(shiny::div(class="brohn-form-grid",shiny::selectInput("media_review_track","Original video stream",choices),
      shiny::textInput("media_review_seconds","Audio position (seconds)",sprintf("%.9f",s$first_sample/s$rate))),
      shiny::p(paste("Audio window:",s$start_s,"to",s$end_s,"seconds (end excluded). Positions snap to the nearest saved sample; exact half-sample ties move to the later sample.")),
      shiny::uiOutput("media_review_resolved_cursor"),
      shiny::actionButton("media_review_apply","Apply media cursor",class="btn-primary"))})
  output$media_review_resolved_cursor<-shiny::renderUI({if(is.null(selection())||is.null(catalog()))return(NULL);f<-form();if(is.null(f$resolved))return(shiny::p(role="status","Enter a supported time within this saved audio window."))
    shiny::p(paste("Selected source sample:",f$cursor_sample,"at",f$resolved$time_s,"seconds in the extracted audio."))})
  submit<-function(operation,retry=FALSE){s<-current();f<-if(operation=="media_review")form(TRUE)else list();c<-catalog();ref<-s$review
    job<-brohn_queue_media_review(store,ref$id,ref$revision,.brohn_sv_hash(ref$body),ref$project_id,operation,
      if(operation=="media_review").brohn_mr_ref(c)else NULL,if(operation=="media_review")f$video_stream_index else NULL,if(operation=="media_review")f$cursor_sample else NULL,retry)
    release();opened(NULL);issue(NULL);pending(list(id=job$id,operation=operation))}
  begin<-function(operation,retry=FALSE){s<-selection();brohn_require(!is.null(s)&&is.null(preparing()),"Wait for the selected source preparation or reopen its audio window.")
    ticket<-list(id=brohn_token(),reference=s$ref,report_id=s$report_id,operation=operation,
      form=if(operation=="media_review")form(TRUE)[c("video_stream_index","cursor_sample")]else NULL,
      catalog=if(operation=="media_review").brohn_mr_ref(catalog())else NULL)
    release();opened(NULL);pending(NULL);issue(NULL);preparing(ticket)
    session$onFlushed(function()shiny::isolate({p<-preparing();s<-selection()
      if(is.null(p)||!identical(p$id,ticket$id))return()
      if(is.null(s)||!identical(state$page,"report")||!identical(state$report_id,ticket$report_id)){preparing(NULL);return()}
      tryCatch({brohn_hosted_require_session(store)
        brohn_require(.brohn_mr_same(s$ref,ticket$reference),"The original audio window changed before preparation. Reopen it.")
        if(operation=="media_review")brohn_require(.brohn_mr_same(form(TRUE)[c("video_stream_index","cursor_sample")],ticket$form)&&.brohn_mr_same(.brohn_mr_ref(catalog()),ticket$catalog),"The media selection changed before preparation. Apply its current position again.")
        submit(operation,retry)
      },error=function(e){issue(conditionMessage(e));pending(NULL);release()})
      preparing(NULL)
    }),once=TRUE)
  }
  shiny::observeEvent(input$media_review_inspect,attempt(function()begin("media_tracks")))
  shiny::observeEvent(input$media_review_apply,attempt(function()begin("media_review")))
  pending_job<-function(){s<-selection();p<-pending();brohn_hosted_require_session(store)
    brohn_require(!is.null(s)&&!is.null(p)&&identical(state$page,"report")&&identical(state$report_id,s$report_id),"Reopen the exact pending source review.");brohn_project(store,s$project_id)
    brohn_require(identical(.brohn_qexplorer_catalog(store,"audio_review",s$ref$id,s$ref$revision,s$project_id),s$audio_catalog)&&
      identical(.brohn_qexplorer_catalog(store,"report",s$report_ref$id,s$report_ref$revision,s$project_id),s$report_catalog),"The pending review's saved source catalog changed.")
    j<-brohn_get_job(store,p$id);brohn_require(!is.null(j)&&identical(j$operation,p$operation)&&identical(j$request$project_id,s$project_id)&&
      .brohn_mr_same(j$request$audio_review,s$ref)&&.brohn_mr_same(j$request$report,s$report_ref),"This pending operation belongs to another source review.");j
  }
  shiny::observeEvent(input$media_review_cancel,attempt(function(){j<-pending_job();brohn_cancel_job(store,j$id)}))
  shiny::observeEvent(input$media_review_retry,attempt(function(){j<-pending_job();brohn_require(j$status%in%c("failed","cancelled"),"Only a failed or cancelled review may retry.");begin(j$operation,TRUE)}))
  shiny::observe({shiny::invalidateLater(750,session);p<-pending();if(is.null(p)||is.null(selection()))return()
    tryCatch({j<-pending_job();if(j$status=="succeeded"){s<-current()
      r<-brohn_media_review_record(store,j$result$media_review_id,s$review$id,s$review$project_id,FALSE)
      if(p$operation=="media_tracks")catalog(r)else opened(r);pending(NULL)
    }},error=function(e){issue(conditionMessage(e));release();pending(NULL)})})
  output$media_review_status<-shiny::renderUI({shiny::invalidateLater(750,session);if(!is.null(issue()))return(shiny::tagList(shiny::p(role="status",class="brohn-alert",issue()),if(is.null(catalog()))shiny::actionButton("media_review_inspect","Try media inspection again")))
    if(!is.null(preparing()))return(shiny::p(role="status","Preparing source review. Checking the selected window, original recording and current access before queueing."))
    p<-pending();if(is.null(p))return(NULL);j<-brohn_get_job(store,p$id)
    shiny::div(role="status",shiny::p(paste("Original media review:",j$status)),if(!is.null(j$error))shiny::p(j$error$message),
      if(j$status%in%c("queued","running"))shiny::actionButton("media_review_cancel","Cancel media review")else if(j$status%in%c("failed","cancelled"))shiny::actionButton("media_review_retry","Retry media review"))})
  register<-function(record,descriptor,kind,download=TRUE){token<-brohn_token();path<-brohn_object_path(store,descriptor$hash,FALSE)
    uri<-session$registerDataObj(paste0("media-",kind),list(id=record$id,token=token),function(data,req)shiny::isolate(tryCatch({
      brohn_hosted_require_session(store)
      brohn_require(req$REQUEST_METHOD%in%c("GET","HEAD")&&identical(shiny::parseQueryString(sub("^\\?","",brohn_default(req$QUERY_STRING,"")))$key,data$token),"Expired media source.")
      r<-active();brohn_require(identical(r$id,data$id),"The current media cursor changed.")
      headers<-list("Cache-Control"="no-store","X-Content-Type-Options"="nosniff")
      if(download)headers[["Content-Disposition"]]<-paste0('attachment; filename="',kind,if(grepl("png",descriptor$media_type))'.png"'else'.csv"')
      structure(list(status=200L,content_type=descriptor$media_type,content=list(file=path,owned=FALSE),headers=headers),class="httpResponse")
    },error=function(e)structure(list(status=404L,content_type="text/plain",content="This media source is no longer current. Reopen the saved review."),class="httpResponse"))))
    paste0(uri,"&key=",token)
  }
  shiny::observe({r<-opened();if(is.null(r)||is.null(selection()))return()
    if(!same(r)){release();return()}
    # Do not repeat complete source reconstruction on an idle350ms timer.
    # Every action and HTTP download still calls active/current with fresh authority;
    # reactive cursor/report changes revoke handles and opaque resource URLs.
    if(native$ready)return()
    shiny::invalidateLater(350,session)
    tryCatch({s<-current();if(is.null(native$view))native$view<-brohn_begin_media_review_open(store,r)
      if(!native$ready){verified<-brohn_poll_media_review_open(store,native$view);if(is.null(verified))return();native$ready<-TRUE
        items<-setNames(lapply(r$body$artifacts,function(a)register(r,a,a$kind,a$kind!="recorded-video-frame")),vapply(r$body$artifacts,`[[`,character(1),"kind"))
        items[["samples"]]<-register(r,s$samples,"original-selected-audio-samples")
        items[["audio_ledger"]]<-register(r,s$ledger,"original-audio-frame-ledger");resources(items)
      }
    },error=function(e){issue(conditionMessage(e));release();opened(NULL)})})
  output$media_review_result<-shiny::renderUI({r<-opened();if(is.null(r))return(NULL)
    if(!same(r))return(shiny::p(role="status","The cursor or track changed. Apply the selection before reviewing or exporting it."))
    links<-resources();if(is.null(links))return(shiny::p(role="status","Verifying complete original media and saved source exports."))
    s<-current();b<-r$body$result;m<-b$mapping;c<-b$coverage;f<-c$frame
    shiny::tagList(shiny::h3("Saved media cursor"),shiny::p(paste("Audio position:",format(signif(m$selected_sample/m$sampling_rate,7),trim=TRUE),"seconds. The frame below follows the original container timing for this saved audio position.")),
      if(is.null(f))shiny::p(role="status",class="brohn-alert",paste("No source frame is supported at this cursor:",gsub("_"," ",c$status),". No image is held across missing or ambiguous coverage."))else shiny::tagList(
        shiny::tags$img(src=links[["recorded-video-frame"]],alt=paste("Original encoded video frame",f$frame_index,"at PTS",f$pts_ticks,"ticks. No inference or autorotation."),style="max-width:100%;height:auto"),
        shiny::p(paste("Original video frame",f$frame_index,"at container time",f$pts_s,"seconds.",if(is.null(f$duration_ticks))"Duration is unknown; only this exact timestamp is supported."else"Frame duration is recorded in the timing details.")),
        if(isTRUE(f$precision_crosses_frame_boundary))shiny::p(class="brohn-alert","This cursor is near a frame boundary within the retained timestamp precision. The displayed frame follows the declared container mapping; physical simultaneity is not established.")),
      shiny::div(class="brohn-signal-wide",shiny::HTML(brohn_media_review_waveform_svg(s$review$body$result,b))),
      shiny::div(class="brohn-signal-compact",shiny::HTML(brohn_media_review_waveform_svg(s$review$body$result,b,320L))),
      shiny::p(paste(c$frame_count,"original video frames;",c$missing_pts,"without PTS;",c$unknown_duration_frames,"without declared duration;",c$gaps,"declared gaps;",c$overlapping_intervals,"overlapping intervals.")),
      shiny::div(class="brohn-toolbar",if(!is.null(f))shiny::tags$a(href=links[["recorded-video-frame"]],download="recorded-video-frame.png",class="btn btn-outline-secondary","Download exact recorded frame PNG"),shiny::tags$a(href=links[["video-frame-ledger"]],download="video-frames.csv",class="btn btn-primary","Download complete video frame ledger"),
        shiny::tags$a(href=links[["samples"]],download="audio-samples.csv",class="btn btn-outline-secondary","Download original selected audio samples"),
        shiny::tags$a(href=links[["audio_ledger"]],download="audio-frames.csv",class="btn btn-outline-secondary","Download original audio frame ledger"),
        shiny::downloadButton("media_review_manifest","Download media mapping and provenance",icon=NULL),shiny::downloadButton("media_review_svg","Download media waveform SVG",icon=NULL)),
      shiny::tags$details(style="overflow-wrap:anywhere",shiny::tags$summary("Clock mapping and coverage"),
        shiny::p(paste("Original audio sample",m$selected_sample,"| containing audio frame",m$audio_frame$decoder_frame_index,"| frame-local mapped container seconds",.brohn_mr_time(m$audio_frame$container_time))),
        if(!is.null(f))shiny::p(paste("Video PTS:",f$pts_ticks,"ticks | time base:",f$time_base,"seconds/tick | duration:",brohn_default(f$duration_ticks,"unknown"),"ticks")),
        shiny::p(paste("Audio timestamp consistency bound:",.brohn_mr_time(m$timestamp_consistency_bound),"seconds. Video tick:",.brohn_mr_time(c$video_time_quantum),"seconds. These describe stored timestamp precision, not measured physical synchronization.")),
        shiny::p(paste("Frame-local audio PTS residual relative to the continuous sample clock:",.brohn_mr_time(m$audio_frame$pts_residual),"seconds. Nominal origin-plus-sample time:",.brohn_mr_time(m$nominal_container_time),"seconds.")),
        shiny::p(paste("Original video SHA-256:",r$body$request$source$hash)),
        shiny::p("The audio waveform and complete sample export come from the original saved audio review. No acoustic scoring, resampling, gaze estimation or unrelated sensor-clock alignment is performed.")),
      shiny::tags$details(shiny::tags$summary("Original video timestamp rows"),brohn_table(b$rows,maximum=100L,label="Original video timestamp rows"),
        shiny::p(paste("Showing",length(b$rows),"of",c$frame_count,"frames. Complete CSV retains every frame including missing timestamps and unknown duration."))))})
  output$media_review_manifest<-shiny::downloadHandler(filename=function()shiny::isolate(paste0(active()$id,".json")),contentType="application/json",content=function(file)prepare_download(function()shiny::isolate(brohn_write_json_file(active()$body,file))))
  output$media_review_svg<-shiny::downloadHandler(filename=function()shiny::isolate(paste0(active()$id,".svg")),contentType="image/svg+xml",content=function(file)prepare_download(function()shiny::isolate({r<-active();s<-current();writeLines(brohn_media_review_waveform_svg(s$review$body$result,r$body$result),file,useBytes=TRUE)})))
  records<-function(){s<-selection();if(is.null(s))return(list());brohn_list_entities(store,"media_review",s$project_id,limit=40L,filters=list(audio_review_id=s$ref$id))}
  history<-shiny::reactivePoll(1200,session,checkFunc=function()brohn_hash(lapply(records(),.brohn_mr_ref)),valueFunc=records)
  output$media_review_history<-shiny::renderUI({rs<-history();if(!length(rs))return(NULL);shiny::tags$details(shiny::tags$summary("Saved media reviews"),lapply(rs,function(r)
    shiny::div(class="brohn-toolbar",shiny::span(paste(r$created_at,"|",if(r$body$request$operation=="media_tracks")"Video inventory"else paste("Sample",r$body$request$selection$cursor_sample))),brohn_command("Reopen saved media review","media_review_reopen",.brohn_mr_ref(r)))))})
  shiny::observeEvent(input$media_review_reopen,attempt(function(){s<-current();ref<-input$media_review_reopen;r<-brohn_media_review_record(store,ref$id,s$review$id,s$review$project_id,FALSE)
    brohn_require(.brohn_mr_same(.brohn_mr_ref(r),ref),"Reopen the exact saved media review.");release();pending(NULL);issue(NULL)
    if(r$body$request$operation=="media_tracks"){catalog(r);opened(NULL)}else {
      c<-brohn_media_review_record(store,r$body$request$catalog$id,s$review$id,s$review$project_id,FALSE);catalog(c)
      session$onFlushed(function(){shiny::updateSelectInput(session,"media_review_track",selected=as.character(r$body$request$selection$video_stream_index));shiny::updateTextInput(session,"media_review_seconds",value=sprintf("%.9f",r$body$request$selection$cursor_sample/s$review$body$result$source$sampling_rate));opened(r)},once=TRUE)
    }}))
  invisible(list(open=open,active=active))
}
