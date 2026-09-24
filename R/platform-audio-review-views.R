# Accessible source waveform/spectrum review. No playback, SPL or emotion claim.
.brohn_ar_num <- function(x) if(is.null(x))"Unavailable"else sprintf("%.17g",x)
.brohn_ar_tick <- function(x) format(signif(x,4),scientific=abs(x)>=10000||(x!=0&&abs(x)<.001),trim=TRUE)
brohn_audio_review_entry_ui <- function(record) {
  if(!.brohn_ar_supported(record$body))return(NULL)
  shiny::tagList(brohn_card(title="Inspect original audio",subtitle="Review the saved source channel as a waveform and spectrum alongside its existing acoustic measurements.",
    brohn_command("Review original audio","audio_review_open_source",list(id=record$id,revision=record$revision,hash=.brohn_sv_hash(record$body))),
    shiny::p("Digital full scale (FS) is not calibrated sound pressure or perceived loudness. Spectral energy is not speech, emotion or attention.")),
    shiny::uiOutput("audio_review_controls"),shiny::uiOutput("audio_review_status"),shiny::uiOutput("audio_review_result"),shiny::uiOutput("audio_review_history"))
}
brohn_audio_review_svg <- function(result,kind="waveform",width=920L) {
  brohn_require(kind %in% c("waveform","spectrum"),"Choose a waveform or spectrum figure.")
  esc<-function(x)as.character(htmltools::htmlEscape(as.character(x),attribute=TRUE))
  compact<-width<500;left<-if(compact)65 else 105;right<-width-22;top<-42;bottom<-250;height<-310
  s<-result$support;rate<-result$source$sampling_rate;start<-s$first_sample/rate;end<-s$stop_sample/rate
  x<-function(v)left+(v-start)/(end-start)*(right-left)
  title<-if(kind=="waveform")"Original audio waveform (FS)"else"Original audio power density (FS^2/Hz)"
  desc<-if(kind=="waveform")"Each mark connects a contiguous source bin's minimum and maximum at their exact source sample times. No samples were resampled. Exact numerical bins and full sample CSV accompany this figure."else
    "Each rectangle is the arithmetic mean of native spectral cells in its stated frame/frequency group. Linear color scale from zero to the displayed maximum; complete native density cells are exported. Full-scale squared per hertz is not sound pressure."
  identity<-paste0(kind,"-",width)
  p<-c(sprintf('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %s %s" role="img" aria-labelledby="ar-%s-title ar-%s-desc" style="width:100%%;height:auto"><title id="ar-%s-title">%s</title><desc id="ar-%s-desc">%s</desc>',width,height,identity,identity,identity,esc(title),identity,esc(desc)),
    paste0('<metadata>',esc(brohn_json(list(schema="brohn-audio-review-figure/1.0",source_hash=result$source_hash,binding=result$binding,selection=result$selection,support=s,parameters=result$parameters))),'</metadata>'),
    sprintf('<rect width="%s" height="%s" fill="#14202b"/><text x="%s" y="23" fill="#e7edf1" font-size="14">%s</text>',width,height,left,esc(if(compact)if(kind=="waveform")"Amplitude (FS)"else"Density (FS^2/Hz)"else title)))
  if(kind=="waveform") {
    bounds<-range(unlist(lapply(result$waveform,function(w)c(w$minimum_fs,w$maximum_fs))),0)
    if(diff(bounds)==0)bounds<-c(-1,1)
    y<-function(v)bottom-(v-bounds[[1]])/diff(bounds)*(bottom-top)
    p<-c(p,sprintf('<line x1="%s" x2="%s" y1="%s" y2="%s" stroke="#526471"/>',left,right,y(0),y(0)))
    for(w in result$waveform)p<-c(p,sprintf('<line data-first-sample="%s" data-stop-sample="%s" data-minimum-sample="%s" data-maximum-sample="%s" x1="%.9f" x2="%.9f" y1="%.9f" y2="%.9f" stroke="#86cbc5" stroke-width="1.5" stroke-linecap="round"><title>%s</title></line>',
      w$first_sample,w$stop_sample,w$minimum_sample,w$maximum_sample,x(w$minimum_sample/rate),x(w$maximum_sample/rate),y(w$minimum_fs),y(w$maximum_fs),
      esc(paste("Samples",w$first_sample,"to",w$stop_sample-1,"minimum",.brohn_ar_num(w$minimum_fs),"FS at",w$minimum_sample,"maximum",.brohn_ar_num(w$maximum_fs),"FS at",w$maximum_sample))))
    ticks<-seq(bounds[[1]],bounds[[2]],length.out=3)
    for(v in ticks)p<-c(p,sprintf('<text x="%s" y="%s" text-anchor="end" fill="#b4c4ce" font-size="12">%s</text>',left-8,y(v)+4,esc(.brohn_ar_tick(v))))
  } else {
    ceiling_hz<-rate/2;y<-function(v)bottom-v/ceiling_hz*(bottom-top)
    maximum<-max(c(0,unlist(lapply(result$spectrogram,function(t)vapply(t$cells,`[[`,numeric(1),"mean_power_fs2_per_hz")))))
    if(!length(result$spectrogram))p<-c(p,sprintf('<text x="%s" y="130" fill="#e7edf1" font-size="13">No complete spectral frame.</text>',left))else for(t in result$spectrogram)for(c in t$cells) {
      low<-max(0,(c$first_bin-.5)*rate/result$selection$frame_length_samples)
      high<-min(ceiling_hz,(c$stop_bin-.5)*rate/result$selection$frame_length_samples)
      fraction<-if(maximum==0)0 else c$mean_power_fs2_per_hz/maximum
      rgb<-round(c(24,41,56)+fraction*(c(141,218,195)-c(24,41,56)))
      color<-sprintf("#%02x%02x%02x",rgb[[1]],rgb[[2]],rgb[[3]])
      p<-c(p,sprintf('<rect data-first-frame="%s" data-stop-frame="%s" data-first-bin="%s" data-stop-bin="%s" data-mean-power="%.17g" x="%.9f" y="%.9f" width="%.9f" height="%.9f" fill="%s"><title>%s</title></rect>',
        t$first_frame,t$stop_frame,c$first_bin,c$stop_bin,c$mean_power_fs2_per_hz,x(t$plot_left_s),y(high),x(t$plot_right_s)-x(t$plot_left_s),y(low)-y(high),color,
        esc(paste("Frames",t$first_frame,"to",t$stop_frame-1,"frequency bins",c$first_bin,"to",c$stop_bin-1,"mean density",.brohn_ar_num(c$mean_power_fs2_per_hz),"FS^2/Hz"))))
    }
    for(v in seq(0,ceiling_hz,length.out=3))p<-c(p,sprintf('<text x="%s" y="%s" text-anchor="end" fill="#b4c4ce" font-size="12">%s Hz</text>',left-8,y(v)+4,esc(.brohn_ar_tick(v))))
    p<-c(p,sprintf('<text x="%s" y="%s" fill="#b4c4ce" font-size="12">%s</text>',left,height-8,esc(paste("Linear color: 0 to",.brohn_ar_tick(maximum),"FS^2/Hz"))))
  }
  p<-c(p,sprintf('<path d="M%s,%sV%sH%s" fill="none" stroke="#79909e"/>',left,top,bottom,right))
  for(v in seq(start,end,length.out=if(compact)3 else 5))p<-c(p,sprintf('<text x="%s" y="273" text-anchor="%s" fill="#b4c4ce" font-size="12">%s</text>',x(v),if(v==start)"start"else if(v==end)"end"else"middle",esc(.brohn_ar_tick(v))))
  p<-c(p,sprintf('<text x="%s" y="291" text-anchor="middle" fill="#e7edf1" font-size="13">Seconds from source start</text></svg>',(left+right)/2))
  paste(p,collapse="")
}
.brohn_ar_rows <- function(result,kind) {
  if(kind=="waveform")return(lapply(result$waveform,function(w)lapply(w,function(x)if(is.numeric(x)).brohn_ar_num(x)else x)))
  unlist(lapply(result$spectrogram,function(t)lapply(t$cells,function(c)list(first_frame=t$first_frame,stop_frame=t$stop_frame,
    first_bin=c$first_bin,stop_bin=c$stop_bin,lowest_hz=.brohn_ar_num(c$lowest_hz),highest_hz=.brohn_ar_num(c$highest_hz),
    source_cells=c$source_cells,mean_power_fs2_per_hz=.brohn_ar_num(c$mean_power_fs2_per_hz)))),recursive=FALSE)
}
brohn_install_audio_review <- function(input,output,session,store,state,attempt,message,refresh,prepare_download,open_media=NULL) {
  source<-shiny::reactiveVal(NULL);opened<-shiny::reactiveVal(NULL);pending<-shiny::reactiveVal(NULL);issue<-shiny::reactiveVal(NULL)
  urls<-shiny::reactiveVal(NULL);wave_page<-shiny::reactiveVal(0L);spectrum_page<-shiny::reactiveVal(0L)
  expanded<-shiny::reactiveValues(waveform=FALSE,spectrum=FALSE)
  reset_pages<-function(){wave_page(0L);spectrum_page(0L);expanded$waveform<-FALSE;expanded$spectrum<-FALSE}
  native<-new.env(parent=emptyenv());native$guards<-list();native$id<-NULL
  release<-function(){for(g in native$guards).brohn_qexplorer_release(g);native$guards<-list();native$id<-NULL;urls(NULL)}
  session$onSessionEnded(release)
  current<-function(){s<-source();brohn_require(!is.null(s)&&identical(state$page,"report")&&identical(state$report_id,s$report$id),"Reopen the audio report in its project.")
    head<-brohn_get_entity(store,"report",s$report$id)
    brohn_require(!is.null(head)&&head$revision==s$report$revision&&identical(.brohn_sv_hash(head$body),.brohn_sv_hash(s$report$body)),"The current audio report changed. Reopen its exact saved view.")
    brohn_audio_review_source(store,s$report$id,s$report$revision,.brohn_sv_hash(s$report$body),s$report$project_id,verify=FALSE)}
  form<-function()list(start_s=brohn_default(input$audio_review_start,""),end_s=brohn_default(input$audio_review_end,""))
  same<-function(r)isTRUE(!is.null(r)&&identical(form()$start_s,r$body$request$selection$start_s)&&identical(form()$end_s,r$body$request$selection$end_s))
  active<-function(){s<-current();r<-opened();brohn_require(same(r),"Apply the current audio window before exporting.")
    brohn_require(identical(native$id,r$id)&&length(native$guards)>0,"The audio source is no longer sealed. Reopen this view.")
    for(g in native$guards).Call(g$native$check,g$pointer)
    brohn_audio_review_record(store,r$id,s$report$id,s$report$project_id,verify=FALSE)}
  shiny::observeEvent(input$audio_review_media,attempt(function(){r<-active();c<-input$audio_review_media
    brohn_require(is.function(open_media)&&.brohn_sv_same(c,.brohn_ar_ref(r))&&!is.null(r$body$request$extraction_lineage),"Open media from this exact video-derived audio window.")
    open_media(c,function()active())}))
  shiny::observeEvent(list(state$page,state$report_id),{source(NULL);opened(NULL);pending(NULL);issue(NULL);release()},ignoreInit=FALSE,priority=110)
  shiny::observeEvent(input$audio_review_open_source,attempt(function(){c<-input$audio_review_open_source
    brohn_require(identical(state$page,"report")&&identical(state$report_id,c$id),"Open the selected audio report first.")
    selected<-brohn_get_entity(store,"report",state$report_id)
    brohn_require(!is.null(selected)&&selected$revision==c$revision&&identical(.brohn_sv_hash(selected$body),c$hash),"Reopen the current exact report before reviewing audio.")
    source(brohn_audio_review_source(store,c$id,c$revision,c$hash,selected$project_id,verify=FALSE));opened(NULL);pending(NULL);issue(NULL);release();reset_pages()}))
  output$audio_review_controls<-shiny::renderUI({s<-source();if(is.null(s))return(NULL);selection<-brohn_audio_review_selection(s);r<-s$report
    brohn_card(title="Original source channel",subtitle=paste("Channel",s$channel,"(zero based)","|",s$header$sampling_rate,"Hz |",s$header$frames,"samples |",r$body$origin),
      shiny::div(class="brohn-form-grid",shiny::textInput("audio_review_start","Audio window start (seconds)",selection$start_s),
        shiny::textInput("audio_review_end","Audio window end (exclusive seconds)",selection$end_s)),
      shiny::p(paste("Periodic Hann density;",selection$frame_length_samples,"samples per spectral frame; hop",selection$frame_hop_samples,"samples. Same frame length and hop as the saved acoustic analysis. No detrending, padding or resampling.")),
      shiny::actionButton("audio_review_apply","Apply audio window",class="btn-primary"),
      shiny::div(class="brohn-toolbar",brohn_command("Inspect saved RMS and spectral centroid","open_signal_catalog",list(report_id=r$id,report_hash=.brohn_sv_hash(r$body),kind="physiology-series")),
        brohn_command("Inspect saved pitch and periodicity","open_signal_catalog",list(report_id=r$id,report_hash=.brohn_sv_hash(r$body),kind="physiology-events"))))})
  submit<-function(retry=FALSE){s<-current();f<-form();job<-brohn_queue_audio_review(store,s$report$id,s$report$revision,.brohn_sv_hash(s$report$body),s$report$project_id,f$start_s,f$end_s,retry)
    opened(NULL);release();issue(NULL);pending(list(id=job$id,report_id=s$report$id));reset_pages()}
  shiny::observeEvent(input$audio_review_apply,attempt(function()submit()))
  shiny::observeEvent(input$audio_review_retry,attempt(function(){p<-pending();brohn_require(!is.null(p),"Choose a failed audio review.");j<-brohn_get_job(store,p$id)
    brohn_require(j$status %in% c("failed","cancelled"),"Only failed or cancelled reviews can retry.");submit(TRUE)}))
  shiny::observeEvent(input$audio_review_cancel,attempt(function(){current();p<-pending();brohn_require(!is.null(p),"No audio review is pending.");brohn_cancel_job(store,p$id)}))
  shiny::observe({shiny::invalidateLater(1000,session);p<-pending();if(is.null(p)||is.null(source()))return()
    if(!identical(state$report_id,p$report_id))return();j<-brohn_get_job(store,p$id)
    if(j$status=="succeeded") {s<-current();r<-brohn_audio_review_record(store,j$result$audio_review_id,s$report$id,s$report$project_id);opened(r);pending(NULL)}})
  output$audio_review_status<-shiny::renderUI({shiny::invalidateLater(1000,session);if(!is.null(issue()))return(shiny::p(class="brohn-alert",role="status",issue()))
    p<-pending();if(is.null(p))return(NULL);j<-brohn_get_job(store,p$id)
    shiny::div(role="status",shiny::p(paste("Audio source review:",j$status)),if(!is.null(j$error))shiny::p(j$error$message),
      if(j$status %in% c("queued","running"))shiny::actionButton("audio_review_cancel","Cancel audio review")else if(j$status %in% c("failed","cancelled"))shiny::actionButton("audio_review_retry","Retry audio review"))})
  # Refresh authority, never rebuild controls on this poll. A changed selection
  # revokes every old URL before a replacement job can expose its result.
  shiny::observe({shiny::invalidateLater(1000,session);r<-opened();if(is.null(r))return()
    if(!same(r)){release();return()}
    tryCatch({s<-current();r<-brohn_audio_review_record(store,r$id,s$report$id,s$report$project_id)
      if(!identical(native$id,r$id)) {
        release();i<-brohn_audio_review_input(store,list(operation="audio_review",request=r$body$request),verify=FALSE)
        refs<-c(i$source_objects,lapply(r$body$csv_objects,function(o)list(hash=o$hash,bytes=o$size)),list(list(hash=r$body$result_object$hash,bytes=r$body$result_object$size)))
        ok<-FALSE;on.exit(if(!ok)release(),add=TRUE)
        for(ref in refs){path<-brohn_object_path(store,ref$hash,verify=FALSE);native$guards[[length(native$guards)+1L]]<-.brohn_qexplorer_hold(path,ref$bytes)
          brohn_require(identical(digest::digest(file=path,algo="sha256"),ref$hash),"An audio source or export failed its saved byte identity.")}
        .brohn_sv_retained(store,r,"audio_review",TRUE);native$id<-r$id;ok<-TRUE
        links<-lapply(r$body$csv_objects,function(o){token<-brohn_token();path<-brohn_object_path(store,o$hash,verify=FALSE)
          uri<-session$registerDataObj(paste0("audio-",o$kind),list(id=r$id,token=token),function(data,req)shiny::isolate(tryCatch({
            brohn_require(req$REQUEST_METHOD %in% c("GET","HEAD")&&identical(shiny::parseQueryString(brohn_default(req$QUERY_STRING,""))$key,data$token),"Expired audio export.")
            saved<-active();brohn_require(identical(saved$id,data$id),"The audio view changed.")
            structure(list(status=200L,content_type="text/csv; charset=utf-8",content=list(file=path,owned=FALSE),headers=list("Cache-Control"="no-store","X-Content-Type-Options"="nosniff","Content-Disposition"=paste0('attachment; filename="',o$kind,'.csv"'))),class="httpResponse")
          },error=function(e)structure(list(status=404L,content_type="text/plain",content="This audio export is no longer current. Reopen the saved view."),class="httpResponse"))))
          list(kind=o$kind,url=paste0(uri,"&key=",token))});urls(links)
      }
      for(g in native$guards).Call(g$native$check,g$pointer)
    },error=function(e){issue(conditionMessage(e));opened(NULL);release()})})
  for(kind in c("waveform","spectrum"))local({k<-kind;page<-if(k=="waveform")wave_page else spectrum_page
    shiny::observeEvent(input[[paste0("audio_review_page_",k)]],attempt(function(){r<-active();n<-length(.brohn_ar_rows(r$body$result,k));value<-input[[paste0("audio_review_page_",k)]]
      brohn_require(brohn_number(value,0,max(0,n-1),TRUE)&&value%%50==0,"Choose an available audio values page.");expanded[[k]]<-TRUE;page(as.integer(value))
      session$onFlushed(function()session$sendCustomMessage("brohn-focus",paste0("audio_review_values_content_",k)),once=TRUE)}))
    output[[paste0("audio_review_values_",k)]]<-shiny::renderUI({r<-opened();if(is.null(r)||!same(r)||is.null(urls()))return(NULL)
      table_ui(r$body$result,k,page(),expanded[[k]])})
    output[[paste0("audio_review_svg_",k)]]<-shiny::downloadHandler(filename=function()paste0(active()$id,"-",k,".svg"),contentType="image/svg+xml",content=function(file)prepare_download(function()writeLines(brohn_audio_review_svg(active()$body$result,k),file,useBytes=TRUE)))
  })
  table_ui<-function(r,kind,page,is_open){rows<-.brohn_ar_rows(r,kind);n<-length(rows);selected<-if(n)rows[seq.int(page+1,min(page+50,n))]else list()
    shiny::tags$details(open=if(is_open)"open"else NULL,shiny::tags$summary(if(kind=="waveform")"Exact waveform display bins"else"Exact spectrum display bins"),
      shiny::div(id=paste0("audio_review_values_content_",kind),tabindex="-1",role="region",`aria-label`=paste("Audio",kind,"display values page"),
      shiny::p(paste("Showing",if(n)page+1 else 0,"to",min(page+50,n),"of",n,"display bins. Complete CSV retains every unaggregated sample or spectral cell.")),
      brohn_table(selected,maximum=50L,label=paste("Audio",kind,"display values")),
      shiny::div(class="brohn-toolbar",if(page>0)brohn_command(paste("Previous",kind,"values"),paste0("audio_review_page_",kind),page-50),
        if(page+50<n)brohn_command(paste("Next",kind,"values"),paste0("audio_review_page_",kind),page+50))))
  }
  output$audio_review_result<-shiny::renderUI({r<-opened();if(is.null(r))return(NULL);if(!same(r))return(shiny::p(role="status","The audio interval changed. Apply the window to inspect or export those inputs."))
    if(is.null(urls()))return(shiny::p(role="status","Verifying the retained audio source and exact exports."));b<-r$body$result;s<-b$support
    shiny::tagList(shiny::h3("Saved audio source review"),shiny::p(paste("Source samples",s$first_sample,"to",s$stop_sample-1,"(zero based);",s$selected_samples,"samples.",s$spectral_frames,"complete spectral frames;",s$trailing_samples_without_full_spectral_frame,"trailing samples outside a complete spectral frame.")),
      shiny::p(paste(s$full_scale_or_exceeding_samples,"samples at or beyond digital full scale.",if(s$exact_silence)"Every selected sample is exactly zero."else"")),
      lapply(c("waveform","spectrum"),function(k)shiny::tagList(shiny::div(class="brohn-signal-wide",shiny::HTML(brohn_audio_review_svg(b,k))),
        shiny::div(class="brohn-signal-compact",shiny::HTML(brohn_audio_review_svg(b,k,320L))),shiny::uiOutput(paste0("audio_review_values_",k)),
        shiny::downloadButton(paste0("audio_review_svg_",k),paste("Download",k,"SVG"),icon=NULL))),
      shiny::div(class="brohn-toolbar",lapply(urls(),function(u)shiny::tags$a(href=u$url,download=paste0(u$kind,".csv"),class="btn btn-primary",
        if(u$kind=="audio-source-samples")"Download every selected audio sample"else"Download every native spectral cell")),shiny::downloadButton("audio_review_manifest","Download audio review provenance",icon=NULL)),
      if(is.function(open_media)&&!is.null(r$body$request$extraction_lineage))brohn_command("Review video with this audio window","audio_review_media",.brohn_ar_ref(r)),
      shiny::tags$details(shiny::tags$summary("Source, method and interpretation"),shiny::p(paste("Report",r$body$report_id,"| source SHA-256",b$source_hash,"| origin",r$body$origin)),
        shiny::p(b$parameters$waveform_display),shiny::p(b$parameters$spectrogram_display),shiny::tags$ul(lapply(b$limitations,shiny::tags$li))))})
  output$audio_review_manifest<-shiny::downloadHandler(filename=function()paste0(active()$id,".json"),contentType="application/json",content=function(file)prepare_download(function()brohn_write_json_file(active()$body,file)))
  records<-function(){s<-source();if(is.null(s))return(list());brohn_list_entities(store,"audio_review",s$report$project_id,limit=40L,filters=list(report_id=s$report$id))}
  history<-shiny::reactivePoll(1200,session,checkFunc=function()brohn_hash(lapply(records(),.brohn_ar_ref)),valueFunc=records)
  output$audio_review_history<-shiny::renderUI({r<-history();if(!length(r))return(NULL);shiny::tags$details(shiny::tags$summary("Saved audio windows"),lapply(r,function(x)
    shiny::div(class="brohn-toolbar",shiny::span(paste(x$created_at,"|",x$body$request$selection$start_s,"to",x$body$request$selection$end_s,"seconds")),brohn_command("Reopen audio window","audio_review_reopen",x$id))))})
  shiny::observeEvent(input$audio_review_reopen,attempt(function(){s<-current();r<-brohn_audio_review_record(store,input$audio_review_reopen,s$report$id,s$report$project_id)
    release();pending(NULL);issue(NULL);reset_pages();shiny::updateTextInput(session,"audio_review_start",value=r$body$request$selection$start_s)
    shiny::updateTextInput(session,"audio_review_end",value=r$body$request$selection$end_s);opened(r)}))
  invisible(list(active=active))
}
