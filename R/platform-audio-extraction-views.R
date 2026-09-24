# Source track selection and derivation, with explicit acoustic mapping next.
brohn_audio_extraction_dataset_ui<-function(store,record) {
  b<-record$body;p<-b$source_provenance
  if(!identical(b$modality,"video")&&!identical(p$acquisition,"video_audio_extraction"))return(NULL)
  derived<-identical(p$acquisition,"video_audio_extraction")
  shiny::tagList(brohn_card(title=if(derived)"Audio from an original video"else"Use this recording's audio",
    subtitle=if(derived)"This WAV preserves the chosen stream's decoded samples and original channel order. Confirm a channel below before acoustic analysis."else
      "Inspect the saved recording, choose an audio track, then continue with Brohn's acoustic analysis.",
    if(derived)shiny::tagList(shiny::p(paste("Parent video:",p$parent_dataset$id,"| stream",p$recording$stream_index,"|",p$recording$sampling_rate,"Hz |",p$recording$channels,"channels")),
      brohn_command("Open original video","open_dataset",p$parent_dataset$id),brohn_command("Review audio derivation","audio_extraction_open_saved",list(id=p$extraction$id,host=.brohn_ax_ref(record))))else
      brohn_command("Inspect audio tracks","audio_extraction_open",.brohn_ax_ref(record)),
    shiny::p("No channel mixing or resampling. Container timestamps do not establish synchronization with study events. These samples do not identify emotion, speech or calibrated sound pressure.")),
    shiny::uiOutput("audio_extraction_status"),shiny::uiOutput("audio_extraction_tracks"),shiny::uiOutput("audio_extraction_result"),shiny::uiOutput("audio_extraction_history"))
}
brohn_install_audio_extraction<-function(input,output,session,store,state,attempt,message,refresh,prepare_download) {
  context<-shiny::reactiveVal(NULL);catalog<-shiny::reactiveVal(NULL);opened<-shiny::reactiveVal(NULL);pending<-shiny::reactiveVal(NULL);issue<-shiny::reactiveVal(NULL);urls<-shiny::reactiveVal(NULL)
  native<-new.env(parent=emptyenv());native$guards<-list();native$id<-NULL
  release<-function(){for(g in native$guards).brohn_qexplorer_release(g);native$guards<-list();native$id<-NULL;urls(NULL)}
  session$onSessionEnded(release)
  current<-function(){c<-context();brohn_require(!is.null(c)&&identical(state$page,"dataset")&&identical(state$dataset_id,c$host$id),"Reopen the current source dataset.")
    host<-brohn_get_entity(store,"dataset",c$host$id)
    brohn_require(!is.null(host)&&host$revision==c$host$revision&&identical(.brohn_sv_hash(host$body),c$host$hash)&&identical(host$project_id,c$project_id),"The dataset changed. Reopen its current source and track selection.")
    if(identical(host$body$source_provenance$acquisition,"video_audio_extraction"))brohn_audio_extraction_lineage(store,host)
    brohn_audio_extraction_source(store,c$source$id,c$source$revision,c$source$hash,c$project_id,verify=FALSE)}
  selection_matches<-function(r){if(is.null(r))return(FALSE);if(!identical(context()$host$id,context()$source$id))return(TRUE)
    !identical(r$body$request$operation,"audio_extract")||identical(as.character(r$body$request$selection$stream_index),input$audio_extraction_stream)}
  active<-function(){s<-current();r<-opened();brohn_require(!is.null(r)&&selection_matches(r)&&identical(native$id,r$id)&&length(native$guards)>0,"Choose the current saved extraction before downloading.")
    for(g in native$guards).Call(g$native$check,g$pointer)
    brohn_audio_extraction_record(store,r$id,s$dataset$project_id)}
  reset<-function(){context(NULL);catalog(NULL);opened(NULL);pending(NULL);issue(NULL);release()}
  shiny::observeEvent(list(state$page,state$dataset_id),reset(),ignoreInit=FALSE,priority=110)
  begin<-function(host,source){brohn_require(identical(state$page,"dataset")&&identical(state$dataset_id,host$id),"Open the selected recording first.")
    selected<-brohn_get_entity(store,"dataset",host$id)
    brohn_require(!is.null(selected)&&selected$revision==host$revision&&identical(.brohn_sv_hash(selected$body),host$hash),"This dataset selection is stale.")
    context(list(host=host,source=source,project_id=selected$project_id));catalog(NULL);opened(NULL);pending(NULL);issue(NULL);release();current()}
  shiny::observeEvent(input$audio_extraction_open,attempt(function(){ref<-input$audio_extraction_open;s<-begin(ref,ref)
    j<-brohn_queue_audio_extraction(store,s$dataset$id,s$dataset$revision,.brohn_sv_hash(s$dataset$body),s$dataset$project_id)
    pending(list(id=j$id,operation="audio_tracks"))}))
  shiny::observeEvent(input$audio_extraction_open_saved,attempt(function(){v<-input$audio_extraction_open_saved;host<-brohn_get_entity(store,"dataset",v$host$id)
    brohn_require(!is.null(host),"This audio dataset is unavailable.");lineage<-brohn_audio_extraction_lineage(store,host)
    brohn_require(!is.null(lineage)&&identical(lineage$binding$extraction$id,v$id),"This derived recording belongs to another extraction.")
    begin(v$host,lineage$binding$parent_dataset);opened(brohn_audio_extraction_record(store,v$id,host$project_id))}))
  submit<-function(retry=FALSE){s<-current();c<-catalog();brohn_require(!is.null(c)&&brohn_text(input$audio_extraction_stream,12)&&grepl("^[0-9]+$",input$audio_extraction_stream),"Choose one of this source's inspected audio tracks.")
    j<-brohn_queue_audio_extraction(store,s$dataset$id,s$dataset$revision,.brohn_sv_hash(s$dataset$body),s$dataset$project_id,"audio_extract",.brohn_ax_ref(c),as.numeric(input$audio_extraction_stream),retry)
    opened(NULL);release();issue(NULL);pending(list(id=j$id,operation="audio_extract"))}
  shiny::observeEvent(input$audio_extraction_apply,attempt(function()submit()))
  shiny::observeEvent(input$audio_extraction_cancel,attempt(function(){current();p<-pending();brohn_require(!is.null(p),"No audio task is pending.");brohn_cancel_job(store,p$id)}))
  shiny::observeEvent(input$audio_extraction_retry,attempt(function(){s<-current();p<-pending();brohn_require(!is.null(p),"Choose a failed audio task.")
    j<-brohn_get_job(store,p$id);brohn_require(j$status%in%c("failed","cancelled"),"Only failed or cancelled tasks can retry.")
    if(p$operation=="audio_extract")submit(TRUE)else{
      j<-brohn_queue_audio_extraction(store,s$dataset$id,s$dataset$revision,.brohn_sv_hash(s$dataset$body),s$dataset$project_id,retry=TRUE)
      pending(list(id=j$id,operation="audio_tracks"));issue(NULL)}}))
  shiny::observe({shiny::invalidateLater(1000,session);p<-pending();if(is.null(p)||is.null(context()))return()
    j<-brohn_get_job(store,p$id);if(j$status=="succeeded")tryCatch({s<-current();r<-brohn_audio_extraction_record(store,j$result$audio_extraction_id,s$dataset$project_id)
      if(p$operation=="audio_tracks")catalog(r)else opened(r);pending(NULL)},error=function(e){issue(conditionMessage(e));pending(NULL);release()})})
  output$audio_extraction_status<-shiny::renderUI({shiny::invalidateLater(1000,session);if(!is.null(issue()))return(shiny::p(role="status",class="brohn-alert",issue()))
    p<-pending();if(is.null(p))return(NULL);j<-brohn_get_job(store,p$id)
    shiny::div(role="status",shiny::p(paste(if(p$operation=="audio_tracks")"Audio track inspection:"else"Audio source extraction:",j$status)),
      if(!is.null(j$error))shiny::p(j$error$message),if(j$status%in%c("queued","running"))shiny::actionButton("audio_extraction_cancel","Cancel audio task")else
        if(j$status%in%c("failed","cancelled"))shiny::actionButton("audio_extraction_retry","Retry audio task"))})
  output$audio_extraction_tracks<-shiny::renderUI({r<-catalog();if(is.null(r))return(NULL);tracks<-r$body$result$tracks
    if(!length(tracks))return(brohn_card(title="No audio track in this recording",shiny::p("The original video is retained. No acoustic dataset or substituted samples were created.")))
    labels<-vapply(tracks,function(t)paste("Stream",t$stream_index,"|",t$codec,"|",t$sampling_rate,"Hz |",t$channels,"channels"),character(1))
    values<-vapply(tracks,function(t)as.character(t$stream_index),character(1))
    brohn_card(title="Choose an original audio track",brohn_table(tracks,label="Original audio track inventory"),
      shiny::selectInput("audio_extraction_stream","Audio track to preserve",c("Choose an audio track"="",stats::setNames(values,labels)),""),
      shiny::p("The next step retains every decoded sample and a complete frame timestamp ledger. Gaps beyond the declared container precision need separate continuous segments; Brohn will not fill or hide them."),
      shiny::actionButton("audio_extraction_apply","Create audio dataset",class="btn-primary"))})
  # Each action rechecks live catalog authority. Guards pin source/receipt/export
  # bytes for the lifetime of a session URL; changing its context revokes it.
  shiny::observe({shiny::invalidateLater(1000,session);r<-opened();if(is.null(r))return()
    if(!selection_matches(r)){release();return()}
    tryCatch({s<-current();r<-brohn_audio_extraction_record(store,r$id,s$dataset$project_id)
      if(!identical(native$id,r$id)){
        release();i<-brohn_audio_extraction_input(store,list(operation=r$body$request$operation,request=r$body$request),verify=FALSE,require_head=FALSE)
        refs<-.brohn_ax_refs(c(i$source_objects,list(.brohn_sv_retained(store,r,"audio_extraction",FALSE)),lapply(r$body$artifacts,function(a)list(hash=a$hash,bytes=a$size))))
        ok<-FALSE;on.exit(if(!ok)release(),add=TRUE)
        for(ref in refs){path<-brohn_object_path(store,ref$hash,verify=FALSE);native$guards[[length(native$guards)+1L]]<-.brohn_qexplorer_hold(path,ref$bytes)
          brohn_require(identical(digest::digest(file=path,algo="sha256"),ref$hash),"Audio derivation source or export bytes changed.")}
        .brohn_sv_retained(store,r,"audio_extraction",TRUE);native$id<-r$id;ok<-TRUE
        links<-lapply(r$body$artifacts,function(a){token<-brohn_token();path<-brohn_object_path(store,a$hash,verify=FALSE)
          uri<-session$registerDataObj(paste0("audio-extraction-",a$kind),list(id=r$id,token=token),function(data,req)shiny::isolate(tryCatch({
            brohn_require(req$REQUEST_METHOD%in%c("GET","HEAD")&&identical(shiny::parseQueryString(brohn_default(req$QUERY_STRING,""))$key,data$token),"Expired audio derivation download.")
            saved<-active();brohn_require(identical(saved$id,data$id),"The audio derivation changed.")
            structure(list(status=200L,content_type=a$media_type,content=list(file=path,owned=FALSE),headers=list("Cache-Control"="no-store","X-Content-Type-Options"="nosniff",
              "Content-Disposition"=paste0('attachment; filename="',if(a$kind=="decoded-audio")"decoded-audio.wav"else"audio-frames.csv",'"'))),class="httpResponse")
          },error=function(e)structure(list(status=404L,content_type="text/plain",content="This source download is no longer current. Reopen its saved derivation."),class="httpResponse"))))
          list(kind=a$kind,url=paste0(uri,"&key=",token))});urls(links)
      }
      for(g in native$guards).Call(g$native$check,g$pointer)
    },error=function(e){issue(conditionMessage(e));opened(NULL);release()})})
  output$audio_extraction_result<-shiny::renderUI({r<-opened();if(is.null(r))return(NULL)
    if(!selection_matches(r))return(shiny::p(role="status","The selected stream changed. Create or reopen its exact audio dataset before exporting."))
    if(is.null(urls()))return(shiny::p(role="status","Verifying the original video and retained audio derivation."))
    b<-r$body;rec<-b$result$recording
    brohn_card(title="Audio dataset ready for acoustic mapping",subtitle=paste(rec$samples_per_channel,"samples per channel |",rec$channels,"original channels |",rec$sampling_rate,"Hz"),
      brohn_command("Open audio dataset","open_dataset",b$derived_dataset_id),shiny::p(paste("Parent video:",b$parent_dataset_id,"| stream",rec$stream_index,"| codec",rec$codec)),
      shiny::p(paste("Sample zero is the first retained decoded sample. Original PTS origin:",rec$source_start_pts_ticks,"ticks at",rec$time_base,"seconds per tick.")),
      shiny::p(paste("Maximum timestamp residual:",rec$maximum_pts_residual_s,"seconds; declared consistency tolerance:",rec$pts_consistency_tolerance_s,"seconds.")),
      shiny::div(class="brohn-toolbar",lapply(urls(),function(u)shiny::tags$a(href=u$url,download=if(u$kind=="decoded-audio")"decoded-audio.wav"else"audio-frames.csv",class="btn btn-primary",
        if(u$kind=="decoded-audio")"Download complete decoded audio"else"Download full frame timestamp ledger")),shiny::downloadButton("audio_extraction_manifest","Download audio derivation receipt",icon=NULL)),
      shiny::tags$details(shiny::tags$summary("Exact source and decoder evidence"),shiny::p(paste("Original SHA-256:",b$request$source_hash)),
        brohn_table(list(rec),label="Exact audio derivation dimensions and timing"),shiny::tags$pre(brohn_json(b$result$engine,TRUE)),
        if(!is.null(b$request$camera))shiny::p(paste("Consented camera:",b$request$camera$capture_id,"| participant run:",b$request$camera$run_id)),
        shiny::tags$ul(lapply(b$result$limitations,shiny::tags$li))))})
  output$audio_extraction_manifest<-shiny::downloadHandler(filename=function()paste0(active()$id,".json"),contentType="application/json",content=function(file)prepare_download(function()brohn_write_json_file(active()$body,file)))
  records<-function(){c<-context();if(is.null(c))return(list());Filter(function(r)identical(r$body$request$operation,"audio_extract"),brohn_list_entities(store,"audio_extraction",c$project_id,limit=40L,filters=list(parent_dataset_id=c$source$id)))}
  history<-shiny::reactivePoll(1200,session,checkFunc=function()brohn_hash(lapply(records(),.brohn_ax_ref)),valueFunc=records)
  output$audio_extraction_history<-shiny::renderUI({rows<-history();if(!length(rows))return(NULL);shiny::tags$details(shiny::tags$summary("Saved audio derivations"),lapply(rows,function(r)
    shiny::div(class="brohn-toolbar",shiny::span(paste(r$created_at,"| stream",r$body$request$selection$stream_index)),brohn_command("Reopen audio derivation","audio_extraction_reopen",r$id))))})
  shiny::observeEvent(input$audio_extraction_reopen,attempt(function(){s<-current();r<-brohn_audio_extraction_record(store,input$audio_extraction_reopen,s$dataset$project_id)
    brohn_require(identical(r$body$parent_dataset_id,s$dataset$id),"This derivation belongs to another source.")
    release();pending(NULL);issue(NULL);if(identical(context()$host$id,context()$source$id)){
      c<-brohn_audio_extraction_record(store,r$body$request$catalog$id,s$dataset$project_id);catalog(c)
      session$onFlushed(function()shiny::updateSelectInput(session,"audio_extraction_stream",selected=as.character(r$body$request$selection$stream_index)),once=TRUE)}
    opened(r)}))
  invisible(list(active=active))
}
