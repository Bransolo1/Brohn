# Saved displacement extrema, without detection, source-sign substitution or rescoring.
.brohn_rr_number <- function(x)if(is.null(x))"Unavailable"else .brohn_rr_shortest(x)
.brohn_rr_axis_labels <- function(values,max_chars=12L) {
  values<-unique(values)
  if(!length(values))return(list(values=numeric(),labels=character(),offset=NULL))
  labels_for<-function(x) {
    scientific<-any(abs(x)>=10000|(x!=0&abs(x)<.001))
    for(digits in 3:17){labels<-trimws(format(signif(x,digits),digits=digits,scientific=scientific,trim=TRUE));if(!anyDuplicated(labels))return(labels)}
    vapply(x,.brohn_rr_shortest,character(1))
  }
  labels<-labels_for(values);offset<-NULL
  if(max(nchar(labels))>max_chars){offset<-values[[1]];labels<-labels_for(values-offset)}
  brohn_require(!anyDuplicated(labels),"Choose a display span with distinguishable tick positions.")
  list(values=values,labels=labels,offset=offset)
}
.brohn_rr_axis_ticks <- function(lower,upper,compact=FALSE)
  .brohn_rr_axis_labels(unique(seq(lower,upper,length.out=if(compact)3 else 5)))
.brohn_rr_label <- function(e)paste(e$recording_id,brohn_default(e$segment_id,"no supported segment"),e$channel,e$status,sep=" | ")
brohn_respiration_review_panel <- function(body) {
  if(!brohn_respiration_review_supported(body))return(NULL)
  brohn_card(title="Respiration cycles and phases",subtitle="Review the exact saved normalized waveform and displacement extrema together.",
    brohn_command("Review respiration cycles","open_respiration_review",list(report_id=body$id,report_hash=.brohn_sv_hash(body))),
    shiny::uiOutput("respiration_review_controls"),shiny::uiOutput("respiration_review_selection_support"),shiny::uiOutput("respiration_review_status"),
    shiny::uiOutput("respiration_review_result"),shiny::uiOutput("respiration_review_history"))
}
brohn_respiration_review_svg <- function(result,width=900L,cycle_offset=0L) {
  compact<-width<500;left<-if(compact)74 else 90;right<-width-20;top<-105;bottom<-290;height<-405
  esc<-function(x)as.character(htmltools::htmlEscape(as.character(x)))
  lo<-as.numeric(result$selection$start_s);hi<-as.numeric(result$selection$end_s);x<-function(t)left+(t-lo)/(hi-lo)*(right-left)
  axis<-.brohn_rr_axis_ticks(lo,hi,compact)
  values<-unlist(lapply(result$series,function(g)vapply(g$points,`[[`,numeric(1),"clean")),use.names=FALSE)
  span<-if(length(values))range(values)else c(0,1);if(diff(span)==0)span<-span+c(-.5,.5)
  pad<-diff(span)*.08;span<-span+c(-pad,pad);y<-function(v)bottom-(v-span[[1]])/diff(span)*(bottom-top)
  ticks<-pretty(span,n=3);ticks<-ticks[ticks>=span[[1]]&ticks<=span[[2]]];if(length(ticks)<2L)ticks<-unique(seq(span[[1]],span[[2]],length.out=3));value_axis<-.brohn_rr_axis_labels(ticks,8L)
  n<-length(result$cycles);ids<-if(n&&cycle_offset<n)seq.int(cycle_offset+1,min(n,cycle_offset+50))else integer()
  cyc<-result$cycles[ids];marker_ids<-unlist(lapply(ids,function(i)seq.int(3*i-2,3*i)),use.names=FALSE);markers<-result$markers[marker_ids]
  prefix<-paste0("rr-",width,"-");meta<-list(binding=result$binding,selection=result$selection,recording=result$recording,parameters=result$parameters,counts=result$counts,cycles=cyc,markers=markers,cycle_offset=cycle_offset,verification=result$verification)
  parts<-c(sprintf('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %s %s" role="img" aria-labelledby="%stitle %sdesc" style="width:100%%;height:auto;display:block">',width,height,prefix,prefix),
    sprintf('<title id="%stitle">Saved normalized respiration waveform</title><desc id="%sdesc">Exact source-time positions. Green phase bars indicate saved inspiration; purple indicate expiration. Solid samples are retained; dashed samples are excluded processing edges. Gaps are not joined. Exact complete numerical exports are available.</desc>',prefix,prefix),
    paste0('<metadata>',esc(brohn_json(meta)),'</metadata>'),sprintf('<rect width="%s" height="%s" fill="#12202a"/>',width,height),
    sprintf('<text x="%s" y="24" fill="#e7edf1" font-size="13">Clean normalized (%s)</text>',left,esc(result$unit)),
    sprintf('<text x="%s" y="47" fill="#9bdccc" font-size="12">Inspiration</text><text x="%s" y="65" fill="#c8bddb" font-size="12">Expiration</text>',left,left))
  support<-c(result$recording$start_time_s,result$recording$end_time_s)
  for(pair in list(c(lo,min(hi,support[[1]])),c(max(lo,support[[2]]),hi)))if(pair[[2]]>pair[[1]])parts<-c(parts,sprintf('<rect data-outside-segment="true" x="%.9f" y="%s" width="%.9f" height="%s" fill="#74838c" opacity=".18"/>',x(pair[[1]]),top,x(pair[[2]])-x(pair[[1]]),bottom-top))
  for(cycle in cyc)for(k in c("inspiration","expiration")) {
    a<-if(k=="inspiration")cycle$time_s else cycle$peak_time_s;b<-if(k=="inspiration")cycle$peak_time_s else cycle$end_time_s
    if(b>=lo&&a<=hi)parts<-c(parts,sprintf('<rect data-phase="%s" data-cycle-row="%s" data-start="%.17g" data-end="%.17g" x="%.9f" y="%s" width="%.9f" height="8" fill="%s"><title>%s</title></rect>',k,cycle$table_row_index,a,b,x(max(lo,a)),if(k=="inspiration")78 else 91,max(0,x(min(hi,b))-x(max(lo,a))),if(k=="inspiration")"#9bdccc"else"#c8bddb",esc(paste(k,.brohn_rr_number(a),"to",.brohn_rr_number(b),"seconds; saved duration",.brohn_rr_number(cycle[[paste0(k,"_s")]])))))
  }
  for(g in result$series)if(length(g$points))parts<-c(parts,sprintf('<polyline data-retained="%s" points="%s" fill="none" stroke="%s" stroke-width="1.8"%s/>',tolower(as.character(g$retained)),paste(vapply(g$points,function(p)sprintf("%.9f,%.9f",x(p$time_s),y(p$clean)),character(1)),collapse=" "),if(g$retained)"#9bdccc"else"#a7aab8",if(g$retained)""else' stroke-dasharray="4 4"'))
  for(m in markers)if(isTRUE(m$in_view))parts<-c(parts,sprintf('<circle data-marker="%s" data-source-time="%.17g" data-source-index="%s" cx="%.9f" cy="%.9f" r="3.5" fill="%s"><title>%s</title></circle>',m$kind,m$time_s,m$source_sample_index,x(m$time_s),y(m$clean),if(m$kind=="expiration_start")"#c8bddb"else"#f1d597",esc(paste(gsub("_"," ",m$kind),"source time",.brohn_rr_number(m$time_s),"normalized",.brohn_rr_number(m$clean),result$unit))))
  if(!length(values))parts<-c(parts,sprintf('<text x="%s" y="210" fill="#e7edf1" font-size="12">No processed samples in this window.</text>',left))
  for(j in seq_along(value_axis$values)){v<-value_axis$values[[j]];parts<-c(parts,sprintf('<text data-value-tick="%.17g" x="%s" y="%.9f" text-anchor="end" fill="#bdcdd6" font-size="12">%s</text>',v,left-8,y(v)+4,esc(value_axis$labels[[j]])))}
  parts<-c(parts,sprintf('<path d="M%s,%sV%sH%s" fill="none" stroke="#79909e"/>',left,top,bottom,right))
  for(j in seq_along(axis$values)){v<-axis$values[[j]];parts<-c(parts,sprintf('<text data-time-tick="%.17g" x="%.9f" y="315" text-anchor="%s" fill="#bdcdd6" font-size="12">%s</text>',v,x(v),if(v==lo)"start"else if(v==hi)"end"else"middle",esc(axis$labels[[j]])))}
  parts<-c(parts,sprintf('<text x="%s" y="342" text-anchor="middle" fill="#e7edf1" font-size="12">%s</text>',width/2,if(is.null(axis$offset))"Original recording time (s)"else"Source time offset (s)"))
  if(!is.null(axis$offset))parts<-c(parts,sprintf('<text data-time-offset="%.17g" x="%s" y="362" text-anchor="middle" fill="#e7edf1" font-size="11">%s</text>',axis$offset,width/2,esc(paste("Add",.brohn_rr_shortest(axis$offset),"s to labels"))))
  if(!is.null(value_axis$offset))parts<-c(parts,sprintf('<text data-value-offset="%.17g" x="%s" y="385" text-anchor="middle" fill="#e7edf1" font-size="10">%s</text>',value_axis$offset,width/2,esc(paste("Add",.brohn_rr_shortest(value_axis$offset),result$unit,"to Y labels"))))
  parts<-c(parts,'</svg>')
  paste(parts,collapse="")
}
brohn_install_respiration_review <- function(input,output,session,store,state,attempt,message,prepare_download) {
  source<-shiny::reactiveVal(NULL);opened<-shiny::reactiveVal(NULL);pending<-shiny::reactiveVal(NULL);issue<-shiny::reactiveVal(NULL)
  restored_selection<-shiny::reactiveVal(NULL)
  urls<-shiny::reactiveVal(NULL);page<-shiny::reactiveVal(0L);markers_page<-shiny::reactiveVal(0L);history_tick<-shiny::reactiveVal(0L)
  native<-new.env(parent=emptyenv());native$guards<-list();native$process<-NULL;native$id<-NULL;native$expected<-NULL
  release<-function(){if(!is.null(native$process)&&native$process$is_alive())native$process$kill_tree();native$process<-NULL
    for(g in native$guards).brohn_qexplorer_release(g);native$guards<-list();native$id<-NULL
    if(!is.null(native$expected))unlink(native$expected);native$expected<-NULL;urls(NULL)}
  session$onSessionEnded(release)
  current<-function(){s<-source();brohn_require(!is.null(s)&&identical(state$page,"report")&&identical(state$report_id,s$id),"Reopen the original respiration report.")
    .brohn_qexplorer_catalog(store,"report",s$id,s$revision,s$project_id)
    r<-brohn_get_entity(store,"report",s$id);brohn_require(r$revision==s$revision&&identical(.brohn_sv_hash(r$body),.brohn_sv_hash(s$body)),"The current respiration report changed. Reopen its saved event review.");r}
  choice<-function(validate=TRUE){s<-current();value<-input$respiration_review_recording;brohn_require(brohn_text(value,4000),"Choose a saved continuous segment and channel.")
    sel<-c(jsonlite::fromJSON(value,simplifyVector=FALSE),list(start_s=input$respiration_review_start,end_s=input$respiration_review_end));if(validate)brohn_respiration_review_selection(s$body$analysis,sel);sel}
  same<-function(r)!is.null(r)&&isTRUE(tryCatch(.brohn_rr_same(choice(FALSE),r$body$request$selection),error=function(e)FALSE))
  active<-function(){s<-current();r<-opened();brohn_require(same(r)&&identical(native$id,r$id)&&!is.null(urls()),"Reopen the verified current respiration cycle window before exporting.")
    for(g in native$guards).Call(g$native$check,g$pointer)
    saved<-brohn_respiration_review_record(store,r$id,s$id,s$project_id);brohn_require(identical(.brohn_sv_hash(saved$body),.brohn_sv_hash(r$body)),"The saved respiration review changed.");saved}
  shiny::observeEvent(list(state$page,state$report_id),{source(NULL);opened(NULL);pending(NULL);issue(NULL);release()},ignoreInit=FALSE,priority=110)
  shiny::observeEvent(input$open_respiration_review,attempt(function(){c<-input$open_respiration_review;brohn_require(identical(state$page,"report")&&identical(c$report_id,state$report_id),"Open the selected respiration report first.")
    r<-brohn_get_entity(store,"report",c$report_id);brohn_require(identical(.brohn_sv_hash(r$body),c$report_hash)&&brohn_respiration_review_supported(r$body),"Reopen the current respiration report.")
    source(r);opened(NULL);pending(NULL);issue(NULL);page(0L);release();history_tick(history_tick()+1L)}))
  output$respiration_review_controls<-shiny::renderUI({s<-source();if(is.null(s))return(NULL);events<-s$body$analysis$recordings;offset<-page();selected<-events[seq.int(offset+1,min(length(events),offset+25))]
    choices<-stats::setNames(vapply(selected,function(e)brohn_json(e[c("recording_id","segment_id","channel")]),character(1)),vapply(selected,.brohn_rr_label,character(1)))
    brohn_card(title="Choose a continuous segment",subtitle=paste("Saved recording/channel segments",offset+1,"to",min(offset+25,length(events)),"of",length(events)),
      shiny::selectInput("respiration_review_recording","Saved recording and continuous segment",choices,selectize=FALSE),
      shiny::div(class="brohn-form-grid",shiny::textInput("respiration_review_start","Window start (source seconds)","0"),shiny::textInput("respiration_review_end","Window end (source seconds)","20")),
      shiny::numericInput("respiration_review_cycle_start","First saved cycle to display",value=1,min=1,step=50),
      shiny::div(class="brohn-toolbar",if(offset>0)brohn_command("Previous respiration segments","respiration_review_event_page",offset-25),if(offset+25<length(events))brohn_command("Next respiration segments","respiration_review_event_page",offset+25)),
      shiny::p("Source-time bounds are decimal seconds. This window selects complete saved samples; it does not rerun filtering, detection or scores. At most 50 saved cycles overlay the chart at once; complete CSVs include every selected cycle."))})
  shiny::observeEvent(input$respiration_review_recording,{
    tryCatch({s<-current();id<-jsonlite::fromJSON(input$respiration_review_recording,simplifyVector=FALSE);rs<-Filter(function(e).brohn_rr_same(e[c("recording_id","segment_id","channel")],id),s$body$analysis$recordings)
      restored<-restored_selection();restored_selection(NULL)
      if(!is.null(restored)&&.brohn_rr_same(id,restored[c("recording_id","segment_id","channel")])){shiny::updateTextInput(session,"respiration_review_start",value=restored$start_s);shiny::updateTextInput(session,"respiration_review_end",value=restored$end_s);return(invisible(NULL))}
      if(length(rs)==1L&&!is.null(rs[[1]]$start_time_s)){r<-rs[[1]];shiny::updateTextInput(session,"respiration_review_start",value=.brohn_rr_number(r$start_time_s));shiny::updateTextInput(session,"respiration_review_end",value=.brohn_rr_number(min(r$end_time_s,r$start_time_s+20)))}}
    ,error=function(e)NULL)
  },ignoreInit=TRUE)
  output$respiration_review_selection_support<-shiny::renderUI({if(is.null(source()))return(NULL);s<-current();v<-input$respiration_review_recording;if(is.null(v))return(NULL)
    id<-jsonlite::fromJSON(v,simplifyVector=FALSE);rs<-Filter(function(e).brohn_rr_same(e[c("recording_id","segment_id","channel")],id),s$body$analysis$recordings);if(length(rs)!=1L)return(NULL);r<-rs[[1]]
    if(!identical(r$status,"computed"))return(shiny::p(`data-segment`=brohn_json(id),role="status",class="brohn-alert",paste("This segment has no processed waveform:",r$reason,"Choose a computed segment or inspect the original source. No zero breathing result is inferred.")))
    shiny::div(`data-segment`=brohn_json(id),shiny::p(paste("Selected continuous support:",.brohn_rr_number(r$start_time_s),"to",.brohn_rr_number(r$end_time_s),"source seconds.",r$samples,"processed samples;",r$complete_cycle_count,"saved complete cycles. Other segments and missing intervals are not joined.")),shiny::actionButton("respiration_review_prepare","Prepare cycle window",class="btn-primary"))})
  shiny::observeEvent(input$respiration_review_event_page,attempt(function(){s<-current();value<-input$respiration_review_event_page;brohn_require(brohn_number(value,0,length(s$body$analysis$recordings)-1,TRUE)&&value%%25==0,"Choose an available source page.");page(value);opened(NULL);release()}))
  submit<-function(retry=FALSE){s<-current();j<-brohn_queue_respiration_review(store,s$id,s$revision,.brohn_sv_hash(s$body),choice(),retry);opened(NULL);release();issue(NULL);pending(j$id);markers_page(0L);shiny::updateNumericInput(session,"respiration_review_cycle_start",value=1)}
  shiny::observeEvent(input$respiration_review_prepare,attempt(function()submit()))
  shiny::observeEvent(input$respiration_review_retry,attempt(function(){j<-brohn_get_job(store,pending());brohn_require(j$status %in% c("failed","cancelled"),"Only failed or cancelled reviews can retry.")
    brohn_require(.brohn_rr_same(choice(),j$request$selection),"Choose the original failed window to retry, or prepare the newly selected segment or window.");submit(TRUE)}))
  shiny::observeEvent(input$respiration_review_cancel,attempt(function(){current();brohn_cancel_job(store,pending())}))
  shiny::observe({id<-pending();if(is.null(id))return();shiny::invalidateLater(1000,session);shiny::isolate(tryCatch({s<-current();j<-brohn_get_job(store,id)
    if(j$status=="succeeded"){opened(brohn_respiration_review_record(store,j$result$respiration_review_id,s$id,s$project_id));pending(NULL);history_tick(history_tick()+1L)}
  },error=function(e){issue(conditionMessage(e));pending(NULL)}))})
  output$respiration_review_status<-shiny::renderUI({if(!is.null(issue()))return(shiny::p(role="status",class="brohn-alert",issue()));id<-pending();if(is.null(id))return(NULL)
    j<-brohn_get_job(store,id);if(j$status %in% c("queued","running"))shiny::invalidateLater(1000,session)
    shiny::div(role="status",shiny::p(paste("Respiration cycle review:",j$status)),if(!is.null(j$error))shiny::p(j$error$message),
      if(j$status %in% c("queued","running"))shiny::actionButton("respiration_review_cancel","Cancel respiration review")else if(j$status %in% c("failed","cancelled"))shiny::actionButton("respiration_review_retry","Retry respiration review"))})
  # Native handles seal every source/export while hashes are checked outside Shiny.
  shiny::observe({r<-opened();if(is.null(r))return();shiny::invalidateLater(1000,session);shiny::isolate(tryCatch({
    if(!same(r)){release();return()};s<-current();saved<-brohn_respiration_review_record(store,r$id,s$id,s$project_id)
    brohn_require(identical(.brohn_sv_hash(saved$body),.brohn_sv_hash(r$body)),"Saved respiration review authority changed.")
    if(is.null(native$id)&&is.null(native$process)) {
      i<-brohn_respiration_review_input(store,list(operation="respiration_review",request=r$body$request),verify=FALSE)
      refs<-c(i$source_objects,lapply(r$body$exports,function(x)list(hash=x$hash,bytes=x$size)),list(list(hash=r$body$result_object$hash,bytes=r$body$result_object$size)))
      refs<-unname(refs[!duplicated(vapply(refs,`[[`,character(1),"hash"))]);i$source_objects<-refs;native$guards<-brohn_hold_signal_value_sources(store,i)
      paths<-lapply(refs,function(x)list(path=brohn_object_path(store,x$hash,verify=FALSE),sha256=x$hash))
      native$expected<-tempfile("brohn-respiration-envelope-",fileext=".json");brohn_write_json_file(r$body[setdiff(names(r$body),"result_object")],native$expected)
      code<-paste(c("import hashlib,json,sys", "for i in json.loads(sys.argv[1]):", " h=hashlib.sha256()", " with open(i['path'],'rb') as f:", "  for b in iter(lambda:f.read(1048576),b''):h.update(b)", " if h.hexdigest()!=i['sha256']:raise RuntimeError('respiration source or export bytes changed.')", "a=json.load(open(sys.argv[2],encoding='utf-8'));b=json.load(open(sys.argv[3],encoding='utf-8'))", "if a!=b:raise RuntimeError('Retained respiration review differs from its catalog.')"),collapse="\n")
      native$process<-processx::process$new(.brohn_publication_python(),c("-B","-c",code,brohn_json(paths),native$expected,brohn_object_path(store,r$body$result_object$hash,verify=FALSE)),stdout="|",stderr="|",cleanup_tree=TRUE,windows_hide_window=TRUE)
    }
    if(!is.null(native$process)&&!native$process$is_alive()) {
      brohn_require(native$process$get_exit_status()==0,paste("Unable to verify respiration source:",substr(native$process$read_all_error(),1,1000)));native$process<-NULL;native$id<-r$id
      links<-lapply(names(r$body$exports),function(name){ref<-r$body$exports[[name]];token<-brohn_token();path<-brohn_object_path(store,ref$hash,verify=FALSE)
        url<-session$registerDataObj(paste0("respiration-",name),list(id=r$id,token=token),function(data,req)shiny::isolate(tryCatch({
          brohn_require(req$REQUEST_METHOD %in% c("GET","HEAD")&&identical(shiny::parseQueryString(brohn_default(req$QUERY_STRING,""))$key,data$token),"Expired respiration export.")
          brohn_require(identical(active()$id,data$id),"respiration selection changed.")
          structure(list(status=200L,content_type="text/csv; charset=utf-8",content=list(file=path,owned=FALSE),headers=list("Cache-Control"="no-store","X-Content-Type-Options"="nosniff","Content-Disposition"=paste0('attachment; filename="',name,'"'))),class="httpResponse")
        },error=function(e)structure(list(status=404L,content_type="text/plain",content="Reopen the current verified respiration event review."),class="httpResponse"))))
        list(name=name,url=paste0(url,"&key=",token))});urls(links)
    }
    for(g in native$guards).Call(g$native$check,g$pointer)
  },error=function(e){issue(conditionMessage(e));opened(NULL);release()}))})
  cycle_offset<-function(r){v<-input$respiration_review_cycle_start;brohn_require(brohn_number(v,1,max(1,length(r$body$result$cycles)),TRUE),"Choose an existing saved cycle index to display.");as.integer(v-1L)}
  output$respiration_review_result<-shiny::renderUI({r<-opened();if(is.null(r))return(NULL);if(!same(r))return(shiny::p(role="status","The source selection or time window changed. Prepare its window to inspect or export it."))
    if(is.null(urls()))return(shiny::p(role="status","Verifying the retained source and complete respiration exports in the background."))
    b<-r$body$result;e<-b$recording;offset<-tryCatch(cycle_offset(r),error=function(e)NULL);if(is.null(offset))return(shiny::p(role="status","Choose a first saved cycle between 1 and the available cycle count."));n<-length(b$cycles)
    picked<-if(n)b$cycles[seq.int(offset+1,min(n,offset+50))]else list();rows<-function(xs)lapply(xs,function(row)lapply(row,function(x)if(is.numeric(x)).brohn_rr_number(x)else if(is.null(x))"Unavailable"else if(is.list(x))brohn_json(x)else x))
    shiny::div(style="min-width:0;overflow-wrap:anywhere",`data-review-id`=r$id,`data-start`=b$selection$start_s,`data-end`=b$selection$end_s,shiny::h3("Saved respiration cycle review"),shiny::p(.brohn_rr_label(e)),
      shiny::p(paste(b$counts$selected_samples,"complete saved samples in this closed window:",b$counts$retained_samples,"retained;",b$counts$excluded_samples,"excluded processing edges.",n,"intersecting cycles retain their full original extrema, even outside the viewport.")),
      shiny::p(paste("Showing cycle overlays",if(n)offset+1 else 0,"to",min(offset+50,n),"of",n,". Change First saved cycle to display for another page; no analysis runs again.")),
      shiny::div(class="brohn-signal-wide",shiny::HTML(brohn_respiration_review_svg(b,cycle_offset=offset))),shiny::div(class="brohn-signal-compact",shiny::HTML(brohn_respiration_review_svg(b,320L,offset))),
      shiny::p("Green bars: inspiration between saved trough and peak. Purple bars: expiration between peak and next trough. Gold points: cycle boundaries; purple points: peaks. Solid waveform: retained samples; dashed waveform: excluded processing edges. Shaded blank areas lie outside this segment."),
      shiny::p(paste("Quantity:",gsub("_"," ",b$parameters$source_quantity),"| original inspiration direction:",gsub("_"," ",b$parameters$polarity),"| original unit:",e$source_unit,"| processed amplitude unit:",b$unit)),
      shiny::p("The cleaned waveform is polarity normalized. It is not the original signed source overlay. Cycle amplitude is the saved normalized peak minus trough; a belt amplitude is not automatically tidal volume."),
      shiny::div(class="brohn-toolbar",shiny::downloadButton("respiration_review_svg","Download respiration window SVG",icon=NULL),lapply(urls(),function(u)shiny::tags$a(href=u$url,download=u$name,class="btn btn-primary",switch(u$name,`respiration-samples.csv`="Download every window sample",`respiration-cycles.csv`="Download every saved cycle",`respiration-markers.csv`="Download every cycle boundary"))),shiny::downloadButton("respiration_review_manifest","Download respiration review provenance",icon=NULL)),
      shiny::tags$details(shiny::tags$summary("Exact saved cycle measurements"),brohn_table(rows(picked),maximum=50L,label="Saved complete cycle measurements")),
      shiny::tags$details(shiny::tags$summary("Exact saved sample preview"),shiny::p(paste("First",length(b$rows),"of",b$counts$selected_samples,"selected rows. Complete CSVs preserve every original processed value and source index.")),brohn_table(rows(b$rows),maximum=50L,label="Exact saved respiration samples")),
      shiny::tags$details(shiny::tags$summary("Source and phase interpretation"),shiny::p(paste("Clock origin:",e$source_time_origin,"| recipe:",b$parameters$recipe)),shiny::p(b$parameters$mapping_source),shiny::p(b$display_policy),shiny::p(b$duration_policy),lapply(b$limitations,shiny::p)))})
  output$respiration_review_svg<-shiny::downloadHandler(filename=function()paste0(active()$id,".svg"),contentType="image/svg+xml",content=function(file)prepare_download(function(){r<-active();writeLines(brohn_respiration_review_svg(r$body$result,cycle_offset=cycle_offset(r)),file,useBytes=TRUE)}))
  output$respiration_review_manifest<-shiny::downloadHandler(filename=function()paste0(active()$id,".json"),contentType="application/json",content=function(file)prepare_download(function()brohn_write_json_file(active()$body,file)))
  output$respiration_review_history<-shiny::renderUI({history_tick();s<-source();if(is.null(s))return(NULL);records<-brohn_list_entities(store,"respiration_review",s$project_id,limit=40L,filters=list(report_id=s$id))
    if(!length(records))return(NULL);shiny::tags$details(shiny::tags$summary("Saved respiration cycle windows"),lapply(records,function(r)shiny::div(class="brohn-toolbar",shiny::span(style="overflow-wrap:anywhere;min-width:0",paste(.brohn_rr_label(r$body$result$recording),"|",r$body$request$selection$start_s,"to",r$body$request$selection$end_s,"source seconds | saved",r$body$created_at)),brohn_command("Reopen respiration window","respiration_review_reopen",list(id=r$id,hash=.brohn_sv_hash(r$body))))))})
  shiny::observeEvent(input$respiration_review_reopen,attempt(function(){s<-current();c<-input$respiration_review_reopen;r<-brohn_respiration_review_record(store,c$id,s$id,s$project_id);brohn_require(identical(.brohn_sv_hash(r$body),c$hash),"Reopen the current saved respiration view.")
    events<-s$body$analysis$recordings;index<-which(vapply(events,function(e).brohn_rr_same(e[c("recording_id","segment_id","channel")],r$body$request$selection[c("recording_id","segment_id","channel")]),logical(1)))
    brohn_require(length(index)==1L,"The original saved respiration segment changed.");page(as.integer((index-1)%/%25*25));release();issue(NULL);pending(NULL);opened(r);markers_page(0L);shiny::updateNumericInput(session,"respiration_review_cycle_start",value=1)
    restored_selection(r$body$request$selection)
    session$onFlushed(function(){shiny::updateSelectInput(session,"respiration_review_recording",selected=brohn_json(r$body$request$selection[c("recording_id","segment_id","channel")]));shiny::updateTextInput(session,"respiration_review_start",value=r$body$request$selection$start_s);shiny::updateTextInput(session,"respiration_review_end",value=r$body$request$selection$end_s)},once=TRUE)}))
  invisible(NULL)
}
