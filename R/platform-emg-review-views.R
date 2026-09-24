# Saved surface-EMG voltage and threshold bursts, without detection or rescoring.
brohn_emg_settings_ui <- function(parameters=NULL) {
  p<-parameters
  brohn_card(title="Surface EMG processing",subtitle="Choose the saved filtering and RMS settings. A burst threshold is optional and must be supplied explicitly in microvolts.",
    shiny::div(class="brohn-form-grid",
      shiny::numericInput("map_emg_highpass","High-pass frequency (Hz)",brohn_default(p$highpass_hz,20),min=5),
      shiny::numericInput("map_emg_lowpass","Low-pass frequency (Hz; blank uses recipe default)",brohn_default(p$lowpass_hz,NA_real_),min=6),
      shiny::numericInput("map_emg_rms_window","RMS window (seconds)",brohn_default(p$rms_window_s,.05),min=.005,max=2,step=.005),
      shiny::numericInput("map_emg_edge","Excluded processing edge (seconds)",brohn_default(p$edge_exclusion_s,.25),min=.25,max=120,step=.05)),
    shiny::p("The default low-pass is the smaller of 450 Hz and 40% of the declared sample rate. The filter is fourth-order Butterworth, applied forward and backward. This is a surface-EMG voltage recipe; muscle/site, electrode placement, bandwidth and source-unit evidence belong in the recording notes."),
    shiny::checkboxInput("map_emg_burst_enabled","Use an explicit RMS burst threshold",!is.null(p$burst_threshold_uv)),
    shiny::conditionalPanel("input.map_emg_burst_enabled",shiny::div(class="brohn-form-grid",
      shiny::numericInput("map_emg_threshold","RMS burst threshold (uV)",brohn_default(p$burst_threshold_uv,NA_real_),min=.000001),
      shiny::numericInput("map_emg_burst_duration","Minimum burst duration (seconds)",brohn_default(p$burst_min_duration_s,.1),min=.001,max=60,step=.01))),
    shiny::p("No MVC normalization, fatigue, emotion or startle interpretation is added. An unspecified threshold leaves burst outcomes unavailable."))
}
brohn_emg_input <- function(input) {
  p<-list(recipe="emg-butterworth-rms/1.0",highpass_hz=input$map_emg_highpass,rms_window_s=input$map_emg_rms_window,edge_exclusion_s=input$map_emg_edge)
  brohn_require(brohn_number(p$highpass_hz,5)&&brohn_number(p$rms_window_s,.005,2)&&brohn_number(p$edge_exclusion_s,.25,120),"Enter supported EMG filter, RMS window and processing-edge settings.")
  low<-input$map_emg_lowpass;if(!is.null(low)&&!is.na(low)){brohn_require(brohn_number(low,p$highpass_hz+1),"EMG low-pass must exceed the high-pass frequency.");p$lowpass_hz<-low}
  if(isTRUE(input$map_emg_burst_enabled)) {
    brohn_require(brohn_number(input$map_emg_threshold,.000001,1e9)&&brohn_number(input$map_emg_burst_duration,.001,60),"Supply an explicit positive RMS threshold in uV and minimum burst duration, or turn the threshold off.")
    p$burst_threshold_uv<-input$map_emg_threshold;p$burst_min_duration_s<-input$map_emg_burst_duration
  }
  p
}
.brohn_mr_number <- function(x)if(is.null(x))"Unavailable"else .brohn_mr_shortest(x)
.brohn_mr_axis_labels <- function(values,max_chars=12L) {
  values<-unique(values)
  if(!length(values))return(list(values=numeric(),labels=character(),offset=NULL))
  labels_for<-function(x) {
    scientific<-any(abs(x)>=10000|(x!=0&abs(x)<.001))
    for(digits in 3:17){labels<-trimws(format(signif(x,digits),digits=digits,scientific=scientific,trim=TRUE));if(!anyDuplicated(labels))return(labels)}
    vapply(x,.brohn_mr_shortest,character(1))
  }
  labels<-labels_for(values);offset<-NULL
  if(max(nchar(labels))>max_chars){offset<-values[[1]];labels<-labels_for(values-offset)}
  brohn_require(!anyDuplicated(labels),"Choose a display span with distinguishable tick positions.")
  list(values=values,labels=labels,offset=offset)
}
.brohn_mr_axis_ticks <- function(lower,upper,compact=FALSE)
  .brohn_mr_axis_labels(unique(seq(lower,upper,length.out=if(compact)3 else 5)))
.brohn_mr_label <- function(e)paste(e$recording_id,brohn_default(e$segment_id,"no supported segment"),e$channel,e$status,sep=" | ")
brohn_emg_review_panel <- function(body) {
  if(!brohn_emg_review_supported(body))return(NULL)
  brohn_card(title="EMG waveform and bursts",subtitle="Inspect saved input voltage, clean voltage, RMS envelope and configured threshold bursts.",
    brohn_command("Review EMG waveform","open_emg_review",list(report_id=body$id,report_hash=.brohn_sv_hash(body))),
    shiny::uiOutput("emg_review_controls"),shiny::uiOutput("emg_review_selection_support"),shiny::uiOutput("emg_review_status"),
    shiny::uiOutput("emg_review_result"),shiny::uiOutput("emg_review_history"))
}
brohn_emg_review_svg <- function(result,width=900L,burst_offset=0L) {
  compact<-width<500;left<-if(compact)74 else 90;right<-width-20;height<-680;plot_height<-205
  esc<-function(x)as.character(htmltools::htmlEscape(as.character(x)))
  lo<-as.numeric(result$selection$start_s);hi<-as.numeric(result$selection$end_s);x<-function(t)left+(t-lo)/(hi-lo)*(right-left)
  axis<-.brohn_mr_axis_ticks(lo,hi,compact)
  n<-length(result$bursts);ids<-if(n&&burst_offset<n)seq.int(burst_offset+1,min(n,burst_offset+50))else integer()
  bursts<-result$bursts[ids];marker_ids<-unlist(lapply(ids,function(i)seq.int(3*i-2,3*i)),use.names=FALSE);markers<-result$markers[marker_ids]
  prefix<-paste0("mr-",width,"-");meta<-list(binding=result$binding,selection=result$selection,recording=result$recording,parameters=result$parameters,
    counts=result$counts,raw_available=result$raw_available,bursts=bursts,markers=markers,burst_offset=burst_offset,verification=result$verification)
  parts<-c(sprintf('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %s %s" role="img" aria-labelledby="%stitle %sdesc" style="width:100%%;height:auto;display:block">',width,height,prefix,prefix),
    sprintf('<title id="%stitle">Saved EMG voltage and RMS envelope</title><desc id="%sdesc">Aligned source-time axes show exact saved input voltage when available, cleaned voltage and RMS envelope in microvolts. Threshold and burst overlays use saved settings. Solid samples are retained; dashed samples are excluded processing edges. Gaps are not joined. Exact numerical exports are available.</desc>',prefix,prefix),
    paste0('<metadata>',esc(brohn_json(meta)),'</metadata>'),sprintf('<rect width="%s" height="%s" fill="#12202a"/>',width,height))
  components<-c("raw_uv","clean_uv","rms_uv");labels<-c("Input voltage (uV)","Clean voltage (uV)","RMS envelope (uV)");colors<-c("#b9cbd9","#9bdccc","#c8bddb")
  for(i in seq_along(components)) {
    component<-components[[i]];offset<-(i-1L)*plot_height;top<-offset+43;bottom<-offset+157
    groups<-result$series[[component]];values<-unlist(lapply(groups,function(g)vapply(g$points,`[[`,numeric(1),"value")),use.names=FALSE)
    threshold<-if(component=="rms_uv")result$parameters$burst_threshold_uv else NULL
    span<-if(length(values))range(c(values,threshold))else c(0,1);if(diff(span)==0)span<-span+c(-.5,.5)
    pad<-diff(span)*.08;span<-span+c(-pad,pad);y<-function(v)bottom-(v-span[[1]])/diff(span)*(bottom-top)
    ticks<-pretty(span,n=2);ticks<-ticks[ticks>=span[[1]]&ticks<=span[[2]]];if(length(ticks)<2L)ticks<-unique(seq(span[[1]],span[[2]],length.out=3));value_axis<-.brohn_mr_axis_labels(ticks,8L)
    parts<-c(parts,sprintf('<g data-component="%s"><text x="%s" y="%s" fill="%s" font-size="13">%s</text>',component,left,offset+24,colors[[i]],labels[[i]]))
    support<-c(result$recording$start_time_s,result$recording$end_time_s)
    for(pair in list(c(lo,min(hi,support[[1]])),c(max(lo,support[[2]]),hi)))if(pair[[2]]>pair[[1]])parts<-c(parts,sprintf('<rect data-outside-segment="true" x="%.9f" y="%s" width="%.9f" height="%s" fill="#74838c" opacity=".18"/>',x(pair[[1]]),top,x(pair[[2]])-x(pair[[1]]),bottom-top))
    if(component=="rms_uv") {
      if(!is.null(threshold)&&length(values))parts<-c(parts,sprintf('<path data-threshold="%.17g" d="M%.9f,%.9fH%.9f" fill="none" stroke="#f1d597" stroke-dasharray="3 5"><title>Saved explicit RMS threshold: %s uV</title></path>',threshold,left,y(threshold),right,esc(.brohn_mr_number(threshold))))
      for(burst in bursts)if(burst$end_time_s>lo&&burst$time_s<=hi)parts<-c(parts,sprintf('<rect data-burst-row="%s" data-boundary-truncated="%s" x="%.9f" y="%s" width="%.9f" height="7" fill="#c8bddb" stroke="%s"><title>%s</title></rect>',burst$table_row_index,tolower(as.character(burst$boundary_truncated)),x(max(lo,burst$time_s)),offset+32,max(0,x(min(hi,burst$end_time_s))-x(max(lo,burst$time_s))),if(burst$boundary_truncated)"#f1d597"else"#c8bddb",esc(paste("Saved burst",.brohn_mr_number(burst$time_s),"to",.brohn_mr_number(burst$end_time_s),"seconds; end exclusive; boundary truncated",burst$boundary_truncated))))
    }
    for(g in groups)if(length(g$points))parts<-c(parts,sprintf('<polyline data-retained="%s" points="%s" fill="none" stroke="%s" stroke-width="1.4"%s/>',tolower(as.character(g$retained)),paste(vapply(g$points,function(p)sprintf("%.9f,%.9f",x(p$time_s),y(p$value)),character(1)),collapse=" "),if(g$retained)colors[[i]]else"#a7aab8",if(g$retained)""else' stroke-dasharray="4 4"'))
    if(component=="rms_uv")for(m in markers)if(isTRUE(m$in_view)) {
      if(m$kind=="end_boundary")parts<-c(parts,sprintf('<path data-marker="end_boundary" data-anchor-source-index="%s" d="M%.9f,%sV%s" stroke="#f1d597" stroke-dasharray="2 3"><title>Exclusive end boundary, anchored after the last active sample</title></path>',m$anchor_source_sample_index,x(m$time_s),top,bottom))else parts<-c(parts,sprintf('<circle data-marker="%s" data-source-time="%.17g" data-source-index="%s" cx="%.9f" cy="%.9f" r="3" fill="#f1d597"><title>%s</title></circle>',m$kind,m$time_s,m$source_sample_index,x(m$time_s),y(m$rms_uv),esc(paste(gsub("_"," ",m$kind),"source time",.brohn_mr_number(m$time_s),"RMS",.brohn_mr_number(m$rms_uv),"uV"))))
    }
    if(component=="raw_uv"&&!result$raw_available)parts<-c(parts,sprintf('<text x="%s" y="%s" fill="#e7edf1" font-size="12">Input samples were not saved.</text><text x="%s" y="%s" fill="#e7edf1" font-size="12">Clean/RMS remain available.</text>',left,offset+92,left,offset+111))else if(!length(values))parts<-c(parts,sprintf('<text x="%s" y="%s" fill="#e7edf1" font-size="12">No samples in this window.</text>',left,offset+100))
    for(j in seq_along(value_axis$values)){v<-value_axis$values[[j]];parts<-c(parts,sprintf('<text data-value-tick="%.17g" x="%s" y="%.9f" text-anchor="end" fill="#bdcdd6" font-size="12">%s</text>',v,left-8,y(v)+4,esc(value_axis$labels[[j]])))}
    parts<-c(parts,sprintf('<path d="M%s,%sV%sH%s" fill="none" stroke="#79909e"/>',left,top,bottom,right))
    for(j in seq_along(axis$values)){v<-axis$values[[j]];parts<-c(parts,sprintf('<text data-time-tick="%.17g" x="%.9f" y="%s" text-anchor="%s" fill="#bdcdd6" font-size="12">%s</text>',v,x(v),offset+181,if(v==lo)"start"else if(v==hi)"end"else"middle",esc(axis$labels[[j]])))}
    if(!is.null(value_axis$offset))parts<-c(parts,sprintf('<text data-value-offset="%.17g" x="%s" y="%s" text-anchor="middle" fill="#e7edf1" font-size="10">%s</text>',value_axis$offset,width/2,offset+200,esc(paste("Add",.brohn_mr_shortest(value_axis$offset),"uV to Y labels"))))
    parts<-c(parts,'</g>')
  }
  parts<-c(parts,sprintf('<text x="%s" y="640" text-anchor="middle" fill="#e7edf1" font-size="12">%s</text>',width/2,if(is.null(axis$offset))"Original recording time (s)"else"Source time offset (s)"))
  if(!is.null(axis$offset))parts<-c(parts,sprintf('<text data-time-offset="%.17g" x="%s" y="659" text-anchor="middle" fill="#e7edf1" font-size="11">%s</text>',axis$offset,width/2,esc(paste("Add",.brohn_mr_shortest(axis$offset),"s to labels"))))
  parts<-c(parts,'</svg>')
  paste(parts,collapse="")
}
brohn_install_emg_review <- function(input,output,session,store,state,attempt,message,prepare_download) {
  source<-shiny::reactiveVal(NULL);opened<-shiny::reactiveVal(NULL);pending<-shiny::reactiveVal(NULL);issue<-shiny::reactiveVal(NULL)
  restored_selection<-shiny::reactiveVal(NULL)
  urls<-shiny::reactiveVal(NULL);page<-shiny::reactiveVal(0L);markers_page<-shiny::reactiveVal(0L);history_tick<-shiny::reactiveVal(0L)
  native<-new.env(parent=emptyenv());native$guards<-list();native$process<-NULL;native$id<-NULL;native$expected<-NULL
  release<-function(){if(!is.null(native$process)&&native$process$is_alive())native$process$kill_tree();native$process<-NULL
    for(g in native$guards).brohn_qexplorer_release(g);native$guards<-list();native$id<-NULL
    if(!is.null(native$expected))unlink(native$expected);native$expected<-NULL;urls(NULL)}
  session$onSessionEnded(release)
  current<-function(){s<-source();brohn_require(!is.null(s)&&identical(state$page,"report")&&identical(state$report_id,s$id),"Reopen the original EMG report.")
    .brohn_qexplorer_catalog(store,"report",s$id,s$revision,s$project_id)
    r<-brohn_get_entity(store,"report",s$id);brohn_require(r$revision==s$revision&&identical(.brohn_sv_hash(r$body),.brohn_sv_hash(s$body)),"The current EMG report changed. Reopen its saved waveform review.");r}
  choice<-function(validate=TRUE){s<-current();value<-input$emg_review_recording;brohn_require(brohn_text(value,4000),"Choose a saved continuous segment and channel.")
    sel<-c(jsonlite::fromJSON(value,simplifyVector=FALSE),list(start_s=input$emg_review_start,end_s=input$emg_review_end));if(validate)brohn_emg_review_selection(s$body$analysis,sel);sel}
  same<-function(r)!is.null(r)&&isTRUE(tryCatch(.brohn_mr_same(choice(FALSE),r$body$request$selection),error=function(e)FALSE))
  active<-function(){s<-current();r<-opened();brohn_require(same(r)&&identical(native$id,r$id)&&!is.null(urls()),"Reopen the verified current EMG burst window before exporting.")
    for(g in native$guards).Call(g$native$check,g$pointer)
    saved<-brohn_emg_review_record(store,r$id,s$id,s$project_id);brohn_require(identical(.brohn_sv_hash(saved$body),.brohn_sv_hash(r$body)),"The saved EMG review changed.");saved}
  shiny::observeEvent(list(state$page,state$report_id),{source(NULL);opened(NULL);pending(NULL);issue(NULL);release()},ignoreInit=FALSE,priority=110)
  shiny::observeEvent(input$open_emg_review,attempt(function(){c<-input$open_emg_review;brohn_require(identical(state$page,"report")&&identical(c$report_id,state$report_id),"Open the selected EMG report first.")
    r<-brohn_get_entity(store,"report",c$report_id);brohn_require(identical(.brohn_sv_hash(r$body),c$report_hash)&&brohn_emg_review_supported(r$body),"Reopen the current EMG report.")
    source(r);opened(NULL);pending(NULL);issue(NULL);page(0L);release();history_tick(history_tick()+1L)}))
  output$emg_review_controls<-shiny::renderUI({s<-source();if(is.null(s))return(NULL);events<-s$body$analysis$recordings;offset<-page();selected<-events[seq.int(offset+1,min(length(events),offset+25))]
    choices<-stats::setNames(vapply(selected,function(e)brohn_json(e[c("recording_id","segment_id","channel")]),character(1)),vapply(selected,.brohn_mr_label,character(1)))
    brohn_card(title="Choose a continuous segment",subtitle=paste("Saved recording/channel segments",offset+1,"to",min(offset+25,length(events)),"of",length(events)),
      shiny::selectInput("emg_review_recording","Saved recording and continuous segment",choices,selectize=FALSE),
      shiny::div(class="brohn-form-grid",shiny::textInput("emg_review_start","Window start (source seconds)","0"),shiny::textInput("emg_review_end","Window end (source seconds)","20")),
      shiny::numericInput("emg_review_burst_start","First saved burst to display",value=1,min=1,step=50),
      shiny::div(class="brohn-toolbar",if(offset>0)brohn_command("Previous EMG segments","emg_review_event_page",offset-25),if(offset+25<length(events))brohn_command("Next EMG segments","emg_review_event_page",offset+25)),
      shiny::p("Source-time bounds are decimal seconds. This window selects complete saved samples; it does not rerun filtering, detection or scores. At most 50 saved bursts overlay the chart at once; complete CSVs include every selected burst."))})
  shiny::observeEvent(input$emg_review_recording,{
    tryCatch({s<-current();id<-jsonlite::fromJSON(input$emg_review_recording,simplifyVector=FALSE);rs<-Filter(function(e).brohn_mr_same(e[c("recording_id","segment_id","channel")],id),s$body$analysis$recordings)
      restored<-restored_selection();restored_selection(NULL)
      if(!is.null(restored)&&.brohn_mr_same(id,restored[c("recording_id","segment_id","channel")])){shiny::updateTextInput(session,"emg_review_start",value=restored$start_s);shiny::updateTextInput(session,"emg_review_end",value=restored$end_s);return(invisible(NULL))}
      if(length(rs)==1L&&!is.null(rs[[1]]$start_time_s)){r<-rs[[1]];shiny::updateTextInput(session,"emg_review_start",value=.brohn_mr_number(r$start_time_s));shiny::updateTextInput(session,"emg_review_end",value=.brohn_mr_number(min(r$end_time_s,r$start_time_s+20)))}}
    ,error=function(e)NULL)
  },ignoreInit=TRUE)
  output$emg_review_selection_support<-shiny::renderUI({if(is.null(source()))return(NULL);s<-current();v<-input$emg_review_recording;if(is.null(v))return(NULL)
    id<-jsonlite::fromJSON(v,simplifyVector=FALSE);rs<-Filter(function(e).brohn_mr_same(e[c("recording_id","segment_id","channel")],id),s$body$analysis$recordings);if(length(rs)!=1L)return(NULL);r<-rs[[1]]
    if(!identical(r$status,"computed"))return(shiny::p(`data-segment`=brohn_json(id),role="status",class="brohn-alert",paste("This segment has no processed waveform:",r$reason,"Choose a computed segment or inspect the original source. No zero muscle-activity result is inferred.")))
    shiny::div(`data-segment`=brohn_json(id),shiny::p(paste("Selected continuous support:",.brohn_mr_number(r$start_time_s),"to",.brohn_mr_number(r$end_time_s),"source seconds.",r$samples,"processed samples. Other segments and missing intervals are not joined.")),shiny::actionButton("emg_review_prepare","Prepare burst window",class="btn-primary"))})
  shiny::observeEvent(input$emg_review_event_page,attempt(function(){s<-current();value<-input$emg_review_event_page;brohn_require(brohn_number(value,0,length(s$body$analysis$recordings)-1,TRUE)&&value%%25==0,"Choose an available source page.");page(value);opened(NULL);release()}))
  submit<-function(retry=FALSE){s<-current();j<-brohn_queue_emg_review(store,s$id,s$revision,.brohn_sv_hash(s$body),choice(),retry);opened(NULL);release();issue(NULL);pending(j$id);markers_page(0L);shiny::updateNumericInput(session,"emg_review_burst_start",value=1)}
  shiny::observeEvent(input$emg_review_prepare,attempt(function()submit()))
  shiny::observeEvent(input$emg_review_retry,attempt(function(){j<-brohn_get_job(store,pending());brohn_require(j$status %in% c("failed","cancelled"),"Only failed or cancelled reviews can retry.")
    brohn_require(.brohn_mr_same(choice(),j$request$selection),"Choose the original failed window to retry, or prepare the newly selected segment or window.");submit(TRUE)}))
  shiny::observeEvent(input$emg_review_cancel,attempt(function(){current();brohn_cancel_job(store,pending())}))
  shiny::observe({id<-pending();if(is.null(id))return();shiny::invalidateLater(1000,session);shiny::isolate(tryCatch({s<-current();j<-brohn_get_job(store,id)
    if(j$status=="succeeded"){opened(brohn_emg_review_record(store,j$result$emg_review_id,s$id,s$project_id));pending(NULL);history_tick(history_tick()+1L)}
  },error=function(e){issue(conditionMessage(e));pending(NULL)}))})
  output$emg_review_status<-shiny::renderUI({if(!is.null(issue()))return(shiny::p(role="status",class="brohn-alert",issue()));id<-pending();if(is.null(id))return(NULL)
    j<-brohn_get_job(store,id);if(j$status %in% c("queued","running"))shiny::invalidateLater(1000,session)
    shiny::div(role="status",shiny::p(paste("EMG burst review:",j$status)),if(!is.null(j$error))shiny::p(j$error$message),
      if(j$status %in% c("queued","running"))shiny::actionButton("emg_review_cancel","Cancel EMG review")else if(j$status %in% c("failed","cancelled"))shiny::actionButton("emg_review_retry","Retry EMG review"))})
  # Native handles seal every source/export while hashes are checked outside Shiny.
  shiny::observe({r<-opened();if(is.null(r))return();shiny::invalidateLater(1000,session);shiny::isolate(tryCatch({
    if(!same(r)){release();return()};s<-current();saved<-brohn_emg_review_record(store,r$id,s$id,s$project_id)
    brohn_require(identical(.brohn_sv_hash(saved$body),.brohn_sv_hash(r$body)),"Saved EMG review authority changed.")
    if(is.null(native$id)&&is.null(native$process)) {
      i<-brohn_emg_review_input(store,list(operation="emg_review",request=r$body$request),verify=FALSE)
      refs<-c(i$source_objects,lapply(r$body$exports,function(x)list(hash=x$hash,bytes=x$size)),list(list(hash=r$body$result_object$hash,bytes=r$body$result_object$size)))
      refs<-unname(refs[!duplicated(vapply(refs,`[[`,character(1),"hash"))]);i$source_objects<-refs;native$guards<-brohn_hold_signal_value_sources(store,i)
      paths<-lapply(refs,function(x)list(path=brohn_object_path(store,x$hash,verify=FALSE),sha256=x$hash))
      native$expected<-tempfile("brohn-emg-envelope-",fileext=".json");brohn_write_json_file(r$body[setdiff(names(r$body),"result_object")],native$expected)
      code<-paste(c("import hashlib,json,sys", "for i in json.loads(sys.argv[1]):", " h=hashlib.sha256()", " with open(i['path'],'rb') as f:", "  for b in iter(lambda:f.read(1048576),b''):h.update(b)", " if h.hexdigest()!=i['sha256']:raise RuntimeError('emg source or export bytes changed.')", "a=json.load(open(sys.argv[2],encoding='utf-8'));b=json.load(open(sys.argv[3],encoding='utf-8'))", "if a!=b:raise RuntimeError('Retained emg review differs from its catalog.')"),collapse="\n")
      native$process<-processx::process$new(.brohn_publication_python(),c("-B","-c",code,brohn_json(paths),native$expected,brohn_object_path(store,r$body$result_object$hash,verify=FALSE)),stdout="|",stderr="|",cleanup_tree=TRUE,windows_hide_window=TRUE)
    }
    if(!is.null(native$process)&&!native$process$is_alive()) {
      brohn_require(native$process$get_exit_status()==0,paste("Unable to verify EMG source:",substr(native$process$read_all_error(),1,1000)));native$process<-NULL;native$id<-r$id
      links<-lapply(names(r$body$exports),function(name){ref<-r$body$exports[[name]];token<-brohn_token();path<-brohn_object_path(store,ref$hash,verify=FALSE)
        url<-session$registerDataObj(paste0("emg-",name),list(id=r$id,token=token),function(data,req)shiny::isolate(tryCatch({
          brohn_require(req$REQUEST_METHOD %in% c("GET","HEAD")&&identical(shiny::parseQueryString(brohn_default(req$QUERY_STRING,""))$key,data$token),"Expired EMG export.")
          brohn_require(identical(active()$id,data$id),"EMG selection changed.")
          structure(list(status=200L,content_type="text/csv; charset=utf-8",content=list(file=path,owned=FALSE),headers=list("Cache-Control"="no-store","X-Content-Type-Options"="nosniff","Content-Disposition"=paste0('attachment; filename="',name,'"'))),class="httpResponse")
        },error=function(e)structure(list(status=404L,content_type="text/plain",content="Reopen the current verified EMG waveform review."),class="httpResponse"))))
        list(name=name,url=paste0(url,"&key=",token))});urls(links)
    }
    for(g in native$guards).Call(g$native$check,g$pointer)
  },error=function(e){issue(conditionMessage(e));opened(NULL);release()}))})
  burst_offset<-function(r){v<-input$emg_review_burst_start;brohn_require(brohn_number(v,1,max(1,length(r$body$result$bursts)),TRUE),"Choose an existing saved burst index to display.");as.integer(v-1L)}
  output$emg_review_result<-shiny::renderUI({r<-opened();if(is.null(r))return(NULL);if(!same(r))return(shiny::p(role="status","The source selection or time window changed. Prepare its window to inspect or export it."))
    if(is.null(urls()))return(shiny::p(role="status","Verifying the retained source and complete EMG exports in the background."))
    b<-r$body$result;e<-b$recording;offset<-tryCatch(burst_offset(r),error=function(e)NULL);if(is.null(offset))return(shiny::p(role="status","Choose a first saved burst between 1 and the available burst count."));n<-length(b$bursts)
    picked<-if(n)b$bursts[seq.int(offset+1,min(n,offset+50))]else list();rows<-function(xs)lapply(xs,function(row)lapply(row,function(x)if(is.numeric(x)).brohn_mr_number(x)else if(is.null(x))"Unavailable"else if(is.list(x))brohn_json(x)else x))
    shiny::div(style="min-width:0;overflow-wrap:anywhere",`data-review-id`=r$id,`data-start`=b$selection$start_s,`data-end`=b$selection$end_s,shiny::h3("Saved EMG waveform review"),shiny::p(.brohn_mr_label(e)),
      shiny::p(paste(b$counts$selected_samples,"complete saved samples in this closed window:",b$counts$retained_samples,"retained;",b$counts$excluded_samples,"excluded processing edges.",n,"intersecting bursts retain their full original boundaries, even outside the viewport.")),
      shiny::p(paste("Showing burst overlays",if(n)offset+1 else 0,"to",min(offset+50,n),"of",n,". Change First saved burst to display for another page; no analysis runs again.")),
      shiny::div(class="brohn-signal-wide",shiny::HTML(brohn_emg_review_svg(b,burst_offset=offset))),shiny::div(class="brohn-signal-compact",shiny::HTML(brohn_emg_review_svg(b,320L,offset))),
      shiny::p("The three traces share the same source-time window. Purple bars show saved threshold bursts; a gold outline flags a burst truncated at a retained-segment boundary. Gold points mark saved onset and first maximum; vertical dashed lines mark exclusive end boundaries, not observed samples. Solid traces are retained; dashed traces are excluded processing edges. Shaded blank areas lie outside this segment."),
      shiny::p(paste("Original source unit:",e$source_unit,"| declared scale to uV:",.brohn_mr_number(e$scale_factor),"| filter:",.brohn_mr_number(b$parameters$highpass_hz),"to",.brohn_mr_number(b$parameters$lowpass_hz),"Hz | RMS window:",.brohn_mr_number(b$parameters$rms_window_s),"seconds.")),
      shiny::p(if(b$raw_available)"Input voltage is the saved unit-converted source before cleaning. Original file bytes remain authoritative."else"This historical report did not retain complete input voltage. Its clean/RMS evidence is available; no raw overlay is reconstructed."),
      shiny::p(if(b$threshold_status=="configured")paste("Saved RMS threshold:",.brohn_mr_number(b$parameters$burst_threshold_uv),"uV; minimum burst duration:",.brohn_mr_number(b$parameters$burst_min_duration_s),"seconds. This viewport does not rerun burst detection or change whole-segment scores.")else"No burst threshold was configured. Burst count and active-time outcomes are unavailable; an empty burst table does not mean zero muscle activity."),
      shiny::p("Voltage is not automatically MVC-normalized muscle activation, fatigue, facial emotion or a startle response."),
      shiny::div(class="brohn-toolbar",shiny::downloadButton("emg_review_svg","Download EMG window SVG",icon=NULL),lapply(urls(),function(u)shiny::tags$a(href=u$url,download=u$name,class="btn btn-primary",switch(u$name,`emg-samples.csv`="Download every window sample",`emg-bursts.csv`="Download every saved burst",`emg-markers.csv`="Download every burst boundary"))),shiny::downloadButton("emg_review_manifest","Download EMG review provenance",icon=NULL)),
      shiny::tags$details(shiny::tags$summary("Exact saved burst measurements"),brohn_table(rows(picked),maximum=50L,label="Saved complete burst measurements")),
      shiny::tags$details(shiny::tags$summary("Original whole-segment measurements"),shiny::p("These are the original report measurements, unchanged by this viewport."),brohn_table(rows(b$features),maximum=50L,label="Original EMG segment measurements")),
      shiny::tags$details(shiny::tags$summary("Exact saved sample preview"),shiny::p(paste("First",length(b$rows),"of",b$counts$selected_samples,"selected rows. Complete CSVs preserve every original processed value and source index.")),brohn_table(rows(b$rows),maximum=50L,label="Exact saved EMG samples")),
      shiny::tags$details(shiny::tags$summary("Source, filter and burst interpretation"),shiny::p(paste("Clock origin:",e$source_time_origin,"| recipe:",b$parameters$recipe)),shiny::p(b$display_policy),shiny::p(b$duration_policy),lapply(b$limitations,shiny::p)))})
  output$emg_review_svg<-shiny::downloadHandler(filename=function()paste0(active()$id,".svg"),contentType="image/svg+xml",content=function(file)prepare_download(function(){r<-active();writeLines(brohn_emg_review_svg(r$body$result,burst_offset=burst_offset(r)),file,useBytes=TRUE)}))
  output$emg_review_manifest<-shiny::downloadHandler(filename=function()paste0(active()$id,".json"),contentType="application/json",content=function(file)prepare_download(function()brohn_write_json_file(active()$body,file)))
  output$emg_review_history<-shiny::renderUI({history_tick();s<-source();if(is.null(s))return(NULL);records<-brohn_list_entities(store,"emg_review",s$project_id,limit=40L,filters=list(report_id=s$id))
    if(!length(records))return(NULL);shiny::tags$details(shiny::tags$summary("Saved EMG burst windows"),lapply(records,function(r)shiny::div(class="brohn-toolbar",shiny::span(style="overflow-wrap:anywhere;min-width:0",paste(.brohn_mr_label(r$body$result$recording),"|",r$body$request$selection$start_s,"to",r$body$request$selection$end_s,"source seconds | saved",r$body$created_at)),brohn_command("Reopen EMG window","emg_review_reopen",list(id=r$id,hash=.brohn_sv_hash(r$body))))))})
  shiny::observeEvent(input$emg_review_reopen,attempt(function(){s<-current();c<-input$emg_review_reopen;r<-brohn_emg_review_record(store,c$id,s$id,s$project_id);brohn_require(identical(.brohn_sv_hash(r$body),c$hash),"Reopen the current saved EMG view.")
    events<-s$body$analysis$recordings;index<-which(vapply(events,function(e).brohn_mr_same(e[c("recording_id","segment_id","channel")],r$body$request$selection[c("recording_id","segment_id","channel")]),logical(1)))
    brohn_require(length(index)==1L,"The original saved EMG segment changed.");page(as.integer((index-1)%/%25*25));release();issue(NULL);pending(NULL);opened(r);markers_page(0L);shiny::updateNumericInput(session,"emg_review_burst_start",value=1)
    restored_selection(r$body$request$selection)
    session$onFlushed(function(){shiny::updateSelectInput(session,"emg_review_recording",selected=brohn_json(r$body$request$selection[c("recording_id","segment_id","channel")]));shiny::updateTextInput(session,"emg_review_start",value=r$body$request$selection$start_s);shiny::updateTextInput(session,"emg_review_end",value=r$body$request$selection$end_s)},once=TRUE)}))
  invisible(NULL)
}
