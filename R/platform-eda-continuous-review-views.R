.brohn_ecr_view_hash <- function(body)digest::digest(body,algo="sha256",serialize=TRUE)
.brohn_ecr_number <- function(x)if(is.null(x))"Unavailable"else sprintf("%.17g",x)
.brohn_ecr_tick <- function(x)format(signif(x,3),scientific=abs(x)>=10000||(x!=0&&abs(x)<.001),trim=TRUE)
.brohn_ecr_axis_labels <- function(values,max_chars=12L) {
  values<-unique(values)
  if(!length(values))return(list(values=numeric(),labels=character(),offset=NULL))
  labels_for<-function(x) {
    scientific<-any(abs(x)>=10000|(x!=0&abs(x)<.001))
    for(digits in 3:17){labels<-trimws(format(signif(x,digits),digits=digits,scientific=scientific,trim=TRUE));if(!anyDuplicated(labels))return(labels)}
    vapply(x,.brohn_ecr_shortest,character(1))
  }
  labels<-labels_for(values);offset<-NULL
  if(max(nchar(labels))>max_chars){offset<-values[[1]];labels<-labels_for(values-offset)}
  brohn_require(!anyDuplicated(labels),"Choose a display span with distinguishable tick positions.")
  list(values=values,labels=labels,offset=offset)
}
.brohn_ecr_axis_ticks <- function(lower,upper,compact=FALSE)
  .brohn_ecr_axis_labels(unique(seq(lower,upper,length.out=if(compact)3 else 5)))
.brohn_ecr_label <- function(e)paste(e$recording_id,brohn_default(e$segment_id,"no supported segment"),e$channel,e$status,sep=" | ")
brohn_eda_continuous_review_panel <- function(body) {
  if(!brohn_eda_continuous_review_supported(body))return(NULL)
  brohn_card(title="Continuous EDA and candidates",subtitle="Inspect saved cleaned, tonic and phasic conductance, with saved spontaneous candidates.",
    brohn_command("Review continuous EDA","open_eda_continuous_review",list(report_id=body$id,report_hash=.brohn_sv_hash(body))),
    shiny::uiOutput("eda_continuous_review_controls"),shiny::uiOutput("eda_continuous_review_selection_support"),shiny::uiOutput("eda_continuous_review_status"),
    shiny::uiOutput("eda_continuous_review_result"),shiny::uiOutput("eda_continuous_review_history"))
}
brohn_eda_continuous_review_svg <- function(result,width=900L,candidate_offset=0L) {
  compact<-width<500;left<-if(compact)74 else 90;right<-width-20;height<-680;plot_height<-205
  esc<-function(x)as.character(htmltools::htmlEscape(as.character(x)))
  lo<-as.numeric(result$selection$start_s);hi<-as.numeric(result$selection$end_s);x<-function(t)left+(t-lo)/(hi-lo)*(right-left)
  axis<-.brohn_ecr_axis_ticks(lo,hi,compact)
  n<-length(result$candidates);ids<-if(n&&candidate_offset<n)seq.int(candidate_offset+1,min(n,candidate_offset+50))else integer()
  candidates<-result$candidates[ids];rows<-vapply(candidates,`[[`,numeric(1),"table_row_index")
  markers<-Filter(function(m)m$candidate_table_row_index%in%rows,result$markers)
  prefix<-paste0("ecr-",width,"-");meta<-list(binding=result$binding,selection=result$selection,recording=result$recording,parameters=result$parameters,
    counts=result$counts,raw_available=FALSE,candidates=candidates,markers=markers,candidate_offset=candidate_offset,verification=result$verification)
  parts<-c(sprintf('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %s %s" role="img" aria-labelledby="%stitle %sdesc" style="width:100%%;height:auto;display:block">',width,height,prefix,prefix),
    sprintf('<title id="%stitle">Saved clean, tonic and phasic EDA</title><desc id="%sdesc">Aligned source-time axes show exact saved conductance in microsiemens. Candidate onset, peak and half-recovery markers use exact original retained sample positions where available. Solid samples are retained; dashed samples are excluded processing edges. Gaps are not joined. Exact numerical exports are available.</desc>',prefix,prefix),
    paste0('<metadata>',esc(brohn_json(meta)),'</metadata>'),sprintf('<rect width="%s" height="%s" fill="#12202a"/>',width,height))
  components<-c("clean_us","tonic_us","phasic_us");labels<-c("Clean conductance (uS)","Tonic conductance (uS)","Phasic conductance (uS)");colors<-c("#b9cbd9","#9bdccc","#c8bddb")
  for(i in seq_along(components)) {
    component<-components[[i]];offset<-(i-1L)*plot_height;top<-offset+43;bottom<-offset+157
    groups<-result$series[[component]];values<-unlist(lapply(groups,function(g)vapply(g$points,`[[`,numeric(1),"value")),use.names=FALSE)
    extra<-if(component=="phasic_us")vapply(Filter(function(m)isTRUE(m$in_view),markers),`[[`,numeric(1),"phasic_us")else numeric()
    span<-if(length(c(values,extra)))range(c(values,extra))else c(0,1);if(diff(span)==0)span<-span+c(-.5,.5)
    pad<-diff(span)*.08;span<-span+c(-pad,pad);y<-function(v)bottom-(v-span[[1]])/diff(span)*(bottom-top)
    ticks<-pretty(span,n=2);ticks<-ticks[ticks>=span[[1]]&ticks<=span[[2]]];if(length(ticks)<2L)ticks<-unique(seq(span[[1]],span[[2]],length.out=3));value_axis<-.brohn_ecr_axis_labels(ticks,8L)
    parts<-c(parts,sprintf('<g data-component="%s"><text x="%s" y="%s" fill="%s" font-size="13">%s</text>',component,left,offset+24,colors[[i]],labels[[i]]))
    support<-c(result$recording$start_time_s,result$recording$end_time_s)
    for(pair in list(c(lo,min(hi,support[[1]])),c(max(lo,support[[2]]),hi)))if(pair[[2]]>pair[[1]])parts<-c(parts,sprintf('<rect data-outside-segment="true" x="%.9f" y="%s" width="%.9f" height="%s" fill="#74838c" opacity=".18"/>',x(pair[[1]]),top,x(pair[[2]])-x(pair[[1]]),bottom-top))
    for(g in groups)if(length(g$points))parts<-c(parts,sprintf('<polyline data-retained="%s" points="%s" fill="none" stroke="%s" stroke-width="1.4"%s/>',tolower(as.character(g$retained)),paste(vapply(g$points,function(p)sprintf("%.9f,%.9f",x(p$time_s),y(p$value)),character(1)),collapse=" "),if(g$retained)colors[[i]]else"#a7aab8",if(g$retained)""else' stroke-dasharray="4 4"'))
    if(component=="phasic_us")for(m in markers)if(isTRUE(m$in_view)) {
      shape<-if(m$kind=="peak")"#f1d597"else if(m$kind=="onset")"#a9e7d7"else"#f0b4ce"
      parts<-c(parts,sprintf('<circle data-marker="%s" data-candidate-row="%s" data-source-time="%.17g" data-source-index="%s" cx="%.9f" cy="%.9f" r="3.5" fill="%s"><title>%s</title></circle>',m$kind,m$candidate_table_row_index,m$time_s,m$source_sample_index,x(m$time_s),y(m$phasic_us),shape,esc(paste(m$kind,"source time",.brohn_ecr_number(m$time_s),"phasic",.brohn_ecr_number(m$phasic_us),"uS"))))
    }
    if(!length(values))parts<-c(parts,sprintf('<text x="%s" y="%s" fill="#e7edf1" font-size="12">No samples in this window.</text>',left,offset+100))
    for(j in seq_along(value_axis$values)){v<-value_axis$values[[j]];parts<-c(parts,sprintf('<text data-value-tick="%.17g" x="%s" y="%.9f" text-anchor="end" fill="#bdcdd6" font-size="12">%s</text>',v,left-8,y(v)+4,esc(value_axis$labels[[j]])))}
    parts<-c(parts,sprintf('<path d="M%s,%sV%sH%s" fill="none" stroke="#79909e"/>',left,top,bottom,right))
    for(j in seq_along(axis$values)){v<-axis$values[[j]];parts<-c(parts,sprintf('<text data-time-tick="%.17g" x="%.9f" y="%s" text-anchor="%s" fill="#bdcdd6" font-size="12">%s</text>',v,x(v),offset+181,if(v==lo)"start"else if(v==hi)"end"else"middle",esc(axis$labels[[j]])))}
    if(!is.null(value_axis$offset))parts<-c(parts,sprintf('<text data-value-offset="%.17g" x="%s" y="%s" text-anchor="middle" fill="#e7edf1" font-size="10">%s</text>',value_axis$offset,width/2,offset+200,esc(paste("Add",.brohn_ecr_shortest(value_axis$offset),"uS to Y labels"))))
    parts<-c(parts,'</g>')
  }
  parts<-c(parts,sprintf('<text x="%s" y="640" text-anchor="middle" fill="#e7edf1" font-size="12">%s</text>',width/2,if(is.null(axis$offset))"Original recording time (s)"else"Source time offset (s)"))
  if(!is.null(axis$offset))parts<-c(parts,sprintf('<text data-time-offset="%.17g" x="%s" y="659" text-anchor="middle" fill="#e7edf1" font-size="11">%s</text>',axis$offset,width/2,esc(paste("Add",.brohn_ecr_shortest(axis$offset),"s to labels"))))
  parts<-c(parts,'</svg>')
  paste(parts,collapse="")
}
brohn_install_eda_continuous_review <- function(input,output,session,store,state,attempt,message,prepare_download) {
  pending_record<-function(id,report_id,project_id).brohn_ecr_record_source(store,id,report_id,project_id)$record
  source<-shiny::reactiveVal(NULL);opened<-shiny::reactiveVal(NULL);pending<-shiny::reactiveVal(NULL);issue<-shiny::reactiveVal(NULL)
  restored_selection<-shiny::reactiveVal(NULL)
  urls<-shiny::reactiveVal(NULL);page<-shiny::reactiveVal(0L);markers_page<-shiny::reactiveVal(0L);history_tick<-shiny::reactiveVal(0L)
  native<-new.env(parent=emptyenv());native$guards<-list();native$process<-NULL;native$id<-NULL;native$expected<-NULL
  release<-function(){if(!is.null(native$process)&&native$process$is_alive())native$process$kill_tree();native$process<-NULL
    for(g in native$guards).brohn_qexplorer_release(g);native$guards<-list();native$id<-NULL
    if(!is.null(native$expected))unlink(native$expected);native$expected<-NULL;urls(NULL)}
  session$onSessionEnded(release)
  current<-function(){s<-source();brohn_require(!is.null(s)&&identical(state$page,"report")&&identical(state$report_id,s$id),"Reopen the original EDA report.")
    .brohn_qexplorer_catalog(store,"report",s$id,s$revision,s$project_id)
    r<-brohn_get_entity(store,"report",s$id);brohn_require(r$revision==s$revision&&identical(.brohn_sv_hash(r$body),.brohn_sv_hash(s$body)),"The current EDA report changed. Reopen its saved waveform review.");r}
  choice<-function(validate=TRUE){s<-current();value<-input$eda_continuous_review_recording;brohn_require(brohn_text(value,4000),"Choose a saved continuous segment and channel.")
    sel<-c(jsonlite::fromJSON(value,simplifyVector=FALSE),list(start_s=input$eda_continuous_review_start,end_s=input$eda_continuous_review_end));if(validate)brohn_eda_continuous_review_selection(s$body$analysis,sel);sel}
  same<-function(r)!is.null(r)&&isTRUE(tryCatch(.brohn_ecr_same(choice(FALSE),r$body$request$selection),error=function(e)FALSE))
  active<-function(){s<-current();r<-opened();brohn_require(same(r)&&identical(native$id,r$id)&&!is.null(urls()),"Reopen the verified current EDA candidate window before exporting.")
    for(g in native$guards).Call(g$native$check,g$pointer)
    saved<-pending_record(r$id,s$id,s$project_id);brohn_require(identical(.brohn_ecr_view_hash(saved$body),.brohn_ecr_view_hash(r$body)),"The saved EDA review changed.");saved}
  shiny::observeEvent(list(state$page,state$report_id),{source(NULL);opened(NULL);pending(NULL);issue(NULL);release()},ignoreInit=FALSE,priority=110)
  shiny::observeEvent(input$open_eda_continuous_review,attempt(function(){c<-input$open_eda_continuous_review;brohn_require(identical(state$page,"report")&&identical(c$report_id,state$report_id),"Open the selected EDA report first.")
    r<-brohn_get_entity(store,"report",c$report_id);brohn_require(identical(.brohn_sv_hash(r$body),c$report_hash)&&brohn_eda_continuous_review_supported(r$body),"Reopen the current EDA report.")
    source(r);opened(NULL);pending(NULL);issue(NULL);page(0L);release();history_tick(history_tick()+1L)}))
  output$eda_continuous_review_controls<-shiny::renderUI({s<-source();if(is.null(s))return(NULL);events<-s$body$analysis$recordings;offset<-page();selected<-events[seq.int(offset+1,min(length(events),offset+25))]
    choices<-stats::setNames(vapply(selected,function(e)brohn_json(e[c("recording_id","segment_id","channel")]),character(1)),vapply(selected,.brohn_ecr_label,character(1)))
    brohn_card(title="Choose a continuous segment",subtitle=paste("Saved recording/channel segments",offset+1,"to",min(offset+25,length(events)),"of",length(events)),
      shiny::selectInput("eda_continuous_review_recording","Saved recording and continuous segment",choices,selectize=FALSE),
      shiny::div(class="brohn-form-grid",shiny::textInput("eda_continuous_review_start","Window start (source seconds)","0"),shiny::textInput("eda_continuous_review_end","Window end (source seconds)","60")),
      shiny::numericInput("eda_continuous_review_candidate_start","First saved candidate to display",value=1,min=1,step=50),
      shiny::div(class="brohn-toolbar",if(offset>0)brohn_command("Previous EDA segments","eda_continuous_review_event_page",offset-25),if(offset+25<length(events))brohn_command("Next EDA segments","eda_continuous_review_event_page",offset+25)),
      shiny::p("Source-time bounds are decimal seconds. This window selects complete saved samples; it does not rerun filtering, detection or scores. At most 50 saved candidates overlay the chart at once; complete CSVs include every selected candidate."))})
  shiny::observeEvent(input$eda_continuous_review_recording,{
    tryCatch({s<-current();id<-jsonlite::fromJSON(input$eda_continuous_review_recording,simplifyVector=FALSE);rs<-Filter(function(e).brohn_ecr_same(e[c("recording_id","segment_id","channel")],id),s$body$analysis$recordings)
      restored<-restored_selection();restored_selection(NULL)
      if(!is.null(restored)&&.brohn_ecr_same(id,restored[c("recording_id","segment_id","channel")])){shiny::updateTextInput(session,"eda_continuous_review_start",value=restored$start_s);shiny::updateTextInput(session,"eda_continuous_review_end",value=restored$end_s);return(invisible(NULL))}
      if(length(rs)==1L&&!is.null(rs[[1]]$start_time_s)){r<-rs[[1]];shiny::updateTextInput(session,"eda_continuous_review_start",value=.brohn_ecr_number(r$start_time_s));shiny::updateTextInput(session,"eda_continuous_review_end",value=.brohn_ecr_number(min(r$end_time_s,r$start_time_s+60)))}}
    ,error=function(e)NULL)
  },ignoreInit=TRUE)
  output$eda_continuous_review_selection_support<-shiny::renderUI({if(is.null(source()))return(NULL);s<-current();v<-input$eda_continuous_review_recording;if(is.null(v))return(NULL)
    id<-jsonlite::fromJSON(v,simplifyVector=FALSE);rs<-Filter(function(e).brohn_ecr_same(e[c("recording_id","segment_id","channel")],id),s$body$analysis$recordings);if(length(rs)!=1L)return(NULL);r<-rs[[1]]
    if(!identical(r$status,"computed"))return(shiny::p(`data-segment`=brohn_json(id),role="status",class="brohn-alert",paste("This segment has no processed waveform:",r$reason,"Choose a computed segment or inspect the original source. No zero conductance or no-response result is inferred.")))
    shiny::div(`data-segment`=brohn_json(id),shiny::p(paste("Selected continuous support:",.brohn_ecr_number(r$start_time_s),"to",.brohn_ecr_number(r$end_time_s),"source seconds.",r$samples,"processed samples. Other segments and missing intervals are not joined.")),shiny::actionButton("eda_continuous_review_prepare","Prepare candidate window",class="btn-primary"))})
  shiny::observeEvent(input$eda_continuous_review_event_page,attempt(function(){s<-current();value<-input$eda_continuous_review_event_page;brohn_require(brohn_number(value,0,length(s$body$analysis$recordings)-1,TRUE)&&value%%25==0,"Choose an available source page.");page(value);opened(NULL);release()}))
  submit<-function(retry=FALSE){s<-current();j<-brohn_queue_eda_continuous_review(store,s$id,s$revision,.brohn_sv_hash(s$body),choice(),retry);opened(NULL);release();issue(NULL);pending(j$id);markers_page(0L);shiny::updateNumericInput(session,"eda_continuous_review_candidate_start",value=1)}
  shiny::observeEvent(input$eda_continuous_review_prepare,attempt(function()submit()))
  shiny::observeEvent(input$eda_continuous_review_retry,attempt(function(){j<-brohn_get_job(store,pending());brohn_require(j$status %in% c("failed","cancelled"),"Only failed or cancelled reviews can retry.")
    brohn_require(.brohn_ecr_same(choice(),j$request$selection),"Choose the original failed window to retry, or prepare the newly selected segment or window.");submit(TRUE)}))
  shiny::observeEvent(input$eda_continuous_review_cancel,attempt(function(){current();brohn_cancel_job(store,pending())}))
  shiny::observe({id<-pending();if(is.null(id))return();shiny::invalidateLater(1000,session);shiny::isolate(tryCatch({s<-current();j<-brohn_get_job(store,id)
    if(j$status=="succeeded"){opened(pending_record(j$result$eda_continuous_review_id,s$id,s$project_id));pending(NULL);history_tick(history_tick()+1L)}
  },error=function(e){issue(conditionMessage(e));pending(NULL)}))})
  output$eda_continuous_review_status<-shiny::renderUI({if(!is.null(issue()))return(shiny::p(role="status",class="brohn-alert",issue()));id<-pending();if(is.null(id))return(NULL)
    j<-brohn_get_job(store,id);if(j$status %in% c("queued","running"))shiny::invalidateLater(1000,session)
    shiny::div(role="status",shiny::p(paste("EDA candidate review:",j$status)),if(!is.null(j$error))shiny::p(j$error$message),
      if(j$status %in% c("queued","running"))shiny::actionButton("eda_continuous_review_cancel","Cancel EDA review")else if(j$status %in% c("failed","cancelled"))shiny::actionButton("eda_continuous_review_retry","Retry EDA review"))})
  # Native handles seal every source/export while hashes are checked outside Shiny.
  shiny::observe({r<-opened();if(is.null(r))return();shiny::invalidateLater(1000,session);shiny::isolate(tryCatch({
    if(!same(r)){release();return()};s<-current();saved<-pending_record(r$id,s$id,s$project_id)
    brohn_require(identical(.brohn_ecr_view_hash(saved$body),.brohn_ecr_view_hash(r$body)),"Saved EDA review authority changed.")
    if(is.null(native$id)&&is.null(native$process)) {
      i<-brohn_eda_continuous_review_input(store,list(operation="eda_continuous_review",request=r$body$request),verify=FALSE)
      refs<-c(i$source_objects,lapply(r$body$exports,function(x)list(hash=x$hash,bytes=x$size)),list(list(hash=r$body$result_object$hash,bytes=r$body$result_object$size)))
      refs<-unname(refs[!duplicated(vapply(refs,`[[`,character(1),"hash"))]);i$source_objects<-refs;native$guards<-brohn_hold_signal_value_sources(store,i)
      paths<-lapply(refs,function(x)list(path=brohn_object_path(store,x$hash,verify=FALSE),sha256=x$hash))
      native$expected<-tempfile("brohn-eda-continuous-envelope-",fileext=".rds")
      saveRDS(list(body=r$body[setdiff(names(r$body),"result_object")],input=i,paths=paths,retained_path=brohn_object_path(store,r$body$result_object$hash,verify=FALSE)),native$expected)
      code<-'source("R/platform-load.R",encoding="UTF-8");brohn_load();.brohn_ecr_verify_snapshot(commandArgs(trailingOnly=TRUE)[[1L]])'
      native$process<-processx::process$new(brohn_rscript(),c("--vanilla","-e",code,native$expected),stdout="|",stderr="|",cleanup_tree=TRUE,windows_hide_window=TRUE)

    }
    if(!is.null(native$process)&&!native$process$is_alive()) {
      brohn_require(native$process$get_exit_status()==0,paste("Unable to verify EDA source:",substr(native$process$read_all_error(),1,1000)));native$process<-NULL
      fresh<-pending_record(r$id,current()$id,current()$project_id)
      brohn_require(same(r)&&identical(.brohn_ecr_view_hash(fresh$body),.brohn_ecr_view_hash(r$body)),"The EDA source or selection changed while verification ran.")
      for(g in native$guards).Call(g$native$check,g$pointer)
      native$id<-r$id
      links<-lapply(names(r$body$exports),function(name){ref<-r$body$exports[[name]];token<-brohn_token();path<-brohn_object_path(store,ref$hash,verify=FALSE)
        url<-session$registerDataObj(paste0("eda-continuous-",name),list(id=r$id,token=token),function(data,req)shiny::isolate(tryCatch({
          brohn_require(req$REQUEST_METHOD %in% c("GET","HEAD")&&identical(shiny::parseQueryString(brohn_default(req$QUERY_STRING,""))$key,data$token),"Expired EDA export.")
          brohn_require(identical(active()$id,data$id),"EDA selection changed.")
          structure(list(status=200L,content_type="text/csv; charset=utf-8",content=list(file=path,owned=FALSE),headers=list("Cache-Control"="no-store","X-Content-Type-Options"="nosniff","Content-Disposition"=paste0('attachment; filename="',name,'"'))),class="httpResponse")
        },error=function(e)structure(list(status=404L,content_type="text/plain",content="Reopen the current verified EDA waveform review."),class="httpResponse"))))
        list(name=name,url=paste0(url,"&key=",token))});urls(links)
      session$onFlushed(function()session$sendCustomMessage("brohn-focus","eda-continuous-result-heading"),once=TRUE)
    }
    for(g in native$guards).Call(g$native$check,g$pointer)
  },error=function(e){issue(conditionMessage(e));opened(NULL);release()}))})
  candidate_offset<-function(r){v<-input$eda_continuous_review_candidate_start;brohn_require(brohn_number(v,1,max(1,length(r$body$result$candidates)),TRUE),"Choose an existing saved candidate index to display.");as.integer(v-1L)}
  output$eda_continuous_review_result<-shiny::renderUI({r<-opened();if(is.null(r))return(NULL);if(!same(r))return(shiny::p(role="status","The source selection or time window changed. Prepare its window to inspect or export it."))
    if(is.null(urls()))return(shiny::p(role="status","Verifying the retained source and complete EDA exports in the background."))
    b<-r$body$result;e<-b$recording;offset<-tryCatch(candidate_offset(r),error=function(e)NULL);if(is.null(offset))return(shiny::p(role="status","Choose a first saved candidate between 1 and the available candidate count."));n<-length(b$candidates)
    picked<-if(n)b$candidates[seq.int(offset+1,min(n,offset+50))]else list();rows<-function(xs)lapply(xs,function(row)lapply(row,function(x)if(is.numeric(x)).brohn_ecr_number(x)else if(is.null(x))"Unavailable"else if(is.list(x))brohn_json(x)else x))
    shiny::div(style="min-width:0;overflow-wrap:anywhere",`data-review-id`=r$id,`data-start`=b$selection$start_s,`data-end`=b$selection$end_s,shiny::h3(id="eda-continuous-result-heading",tabindex="-1","Saved EDA waveform review"),shiny::p(.brohn_ecr_label(e)),
      shiny::p(paste(b$counts$selected_samples,"complete saved samples in this closed window:",b$counts$retained_samples,"retained;",b$counts$excluded_samples,"excluded processing edges.",n,"intersecting candidates retain their full original boundaries, even outside the viewport.")),
      shiny::p(paste("Showing candidate overlays",if(n)offset+1 else 0,"to",min(offset+50,n),"of",n,". Change First saved candidate to display for another page; no analysis runs again.")),
      shiny::div(class="brohn-signal-wide",shiny::HTML(brohn_eda_continuous_review_svg(b,candidate_offset=offset))),shiny::div(class="brohn-signal-compact",shiny::HTML(brohn_eda_continuous_review_svg(b,320L,offset))),
      shiny::p("The three traces share the same source-time window. Mint onset, gold peak and pink half-recovery markers show saved sample positions on the phasic trace. Missing endpoints remain unavailable. Solid traces are retained; dashed traces are excluded processing edges. Shaded areas lie outside this segment; other segments and gaps are never joined."),
      shiny::p(paste("Original source unit:",e$source_unit,"| declared scale to uS:",.brohn_ecr_number(e$scale_factor),"| cleaner: NeuroKit 3 Hz, order 4 | high-pass decomposition:",.brohn_ecr_number(b$parameters$phasic_cutoff_hz),"Hz.")),
      shiny::p("The saved processed tables contain clean, tonic and phasic samples. Raw samples are available through the original dataset download; no raw overlay is reconstructed."),
      shiny::p(paste("Saved relative-prominence setting:",.brohn_ecr_number(b$parameters$amplitude_min_relative_prominence),"(dimensionless); processing edge:",.brohn_ecr_number(b$parameters$edge_exclusion_s),"seconds per side. This is not an absolute uS threshold. No threshold line, stimulus attribution or emotion label is inferred.")),
      shiny::p(paste("Whole segment:",b$counts$segment_candidates,"candidates;",b$counts$segment_amplitude_available,"with available amplitude;",b$counts$segment_onset_missing,"missing onsets and",b$counts$segment_recovery_missing,"missing recoveries. Conditional amplitude uses its original available-onset denominator.")),
      shiny::div(class="brohn-toolbar",shiny::downloadButton("eda_continuous_review_svg","Download EDA window SVG",icon=NULL),lapply(urls(),function(u)shiny::tags$a(href=u$url,download=u$name,class="btn btn-primary",switch(u$name,`eda-samples.csv`="Download every window sample",`eda-candidates.csv`="Download every saved candidate",`eda-markers.csv`="Download every candidate marker"))),shiny::downloadButton("eda_continuous_review_manifest","Download EDA review provenance",icon=NULL)),
      shiny::tags$details(shiny::tags$summary("Exact saved candidate measurements"),brohn_table(rows(picked),maximum=50L,label="Saved complete candidate measurements")),
      shiny::tags$details(shiny::tags$summary("Original whole-segment measurements"),shiny::p("These are the original report measurements, unchanged by this viewport."),brohn_table(rows(b$features),maximum=50L,label="Original EDA segment measurements")),
      shiny::tags$details(shiny::tags$summary("Exact saved sample preview"),shiny::p(paste("First",length(b$rows),"of",b$counts$selected_samples,"selected rows. Complete CSVs preserve every original processed value and source index.")),brohn_table(rows(b$rows),maximum=50L,label="Exact saved EDA samples")),
      shiny::tags$details(shiny::tags$summary("Source, filter and candidate interpretation"),shiny::p(paste("Clock origin:",e$source_time_origin,"| recipe:",b$parameters$recipe)),shiny::p(b$display_policy),lapply(b$limitations,shiny::p)))})
  output$eda_continuous_review_svg<-shiny::downloadHandler(filename=function()paste0(active()$id,".svg"),contentType="image/svg+xml",content=function(file)prepare_download(function(){r<-active();writeLines(brohn_eda_continuous_review_svg(r$body$result,candidate_offset=candidate_offset(r)),file,useBytes=TRUE)}))
  output$eda_continuous_review_manifest<-shiny::downloadHandler(filename=function()paste0(active()$id,".json"),contentType="application/json",content=function(file)prepare_download(function()brohn_write_json_file(active()$body,file)))
  output$eda_continuous_review_history<-shiny::renderUI({history_tick();s<-source();if(is.null(s))return(NULL);records<-brohn_list_entities(store,"eda_continuous_review",s$project_id,limit=40L,filters=list(report_id=s$id))
    if(!length(records))return(NULL);shiny::tags$details(shiny::tags$summary("Saved EDA candidate windows"),lapply(records,function(r)shiny::div(class="brohn-toolbar",shiny::span(style="overflow-wrap:anywhere;min-width:0",paste(.brohn_ecr_label(r$body$result$recording),"|",r$body$request$selection$start_s,"to",r$body$request$selection$end_s,"source seconds | saved",r$body$created_at)),brohn_command("Reopen EDA window","eda_continuous_review_reopen",list(id=r$id,hash=.brohn_ecr_view_hash(r$body))))))})
  shiny::observeEvent(input$eda_continuous_review_reopen,attempt(function(){s<-current();c<-input$eda_continuous_review_reopen;r<-pending_record(c$id,s$id,s$project_id);brohn_require(identical(.brohn_ecr_view_hash(r$body),c$hash),"Reopen the current saved EDA view.")
    events<-s$body$analysis$recordings;index<-which(vapply(events,function(e).brohn_ecr_same(e[c("recording_id","segment_id","channel")],r$body$request$selection[c("recording_id","segment_id","channel")]),logical(1)))
    brohn_require(length(index)==1L,"The original saved EDA segment changed.");page(as.integer((index-1)%/%25*25));release();issue(NULL);pending(NULL);opened(r);markers_page(0L);shiny::updateNumericInput(session,"eda_continuous_review_candidate_start",value=1)
    restored_selection(r$body$request$selection)
    session$onFlushed(function(){shiny::updateSelectInput(session,"eda_continuous_review_recording",selected=brohn_json(r$body$request$selection[c("recording_id","segment_id","channel")]));shiny::updateTextInput(session,"eda_continuous_review_start",value=r$body$request$selection$start_s);shiny::updateTextInput(session,"eda_continuous_review_end",value=r$body$request$selection$end_s)},once=TRUE)}))
  invisible(NULL)
}
