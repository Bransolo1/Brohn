# Accessible, source-bound event windows. This renderer never detects or scores.
.brohn_er_number <- function(x)if(is.null(x))"Unavailable"else sprintf("%.17g",x)
.brohn_er_tick <- function(x)format(signif(x,3),scientific=abs(x)>=10000||(x!=0&&abs(x)<.001),trim=TRUE)
.brohn_er_reason <- function(reason) {
  if(is.null(reason))return(NULL)
  phrases<-c(ambiguous_overlapping_events="Overlapping events prevent clear response attribution",
    incomplete_baseline_response_or_continuous_context="The baseline, response or surrounding recording is incomplete",
    missing_gap_filter_edge_or_short_continuous_context="Missing data, a gap, processing edge or short recording limits support",
    no_qualifying_response="No response met the declared detection criteria",
    half_recovery_not_observed_in_retained_segment="Half recovery was not observed in the retained recording",
    half_recovery_after_declared_boundary="Half recovery occurs after the declared observation limit",
    another_event_precedes_half_recovery="Another event occurs before half recovery",
    unobserved_or_preexisting_scr_onset="A response onset is unobserved or precedes the permitted latency window",
    scr_detector_failed="The saved response detector did not produce usable results")
  if(reason %in% names(phrases))unname(phrases[[reason]])else gsub("_"," ",reason,fixed=TRUE)
}
brohn_eda_review_entry_ui <- function(report) {
  if(!brohn_eda_review_supported(report))return(NULL)
  shiny::tagList(brohn_card(title="Understand each EDA response",subtitle="Inspect the saved baseline, response window and detected response alongside the original measurements.",
    brohn_command("Review EDA event windows","open_eda_review",list(report_id=report$id,report_hash=.brohn_sv_hash(report)))),
    shiny::uiOutput("eda_review_controls"),shiny::uiOutput("eda_review_status"),shiny::uiOutput("eda_review_result"),shiny::uiOutput("eda_review_history"))
}
brohn_eda_review_svg <- function(result,component="phasic_us",width=900L) {
  brohn_require(component %in% c("phasic_us","tonic_us","clean_us"),"Choose a saved conductance component.")
  esc<-function(x)as.character(htmltools::htmlEscape(as.character(x),attribute=TRUE))
  compact<-width<500L;left<-if(compact)66 else 96;right<-width-22;top<-111;bottom<-314;height<-400
  e<-result$event;p<-result$parameters;range<-unlist(result$range_s);paths<-result$series[[component]]
  values<-unlist(lapply(paths,function(g)lapply(g$points,`[[`,"value")),use.names=FALSE)
  limits<-if(length(values))base::range(values)else c(-1,1)
  if(diff(limits)==0)limits<-limits+c(-1,1)*max(.001,abs(limits[[1]])*.02)
  # Keep near-flat tonic ticks distinct without long labels on a phone.
  yticks<-seq(limits[[1]],limits[[2]],length.out=3)
  tick_labels<-vapply(yticks,.brohn_er_tick,character(1));yoffset<-0
  if(anyDuplicated(tick_labels)||any(nchar(tick_labels)>8L)) {
    yoffset<-signif(limits[[1]],5);tick_labels<-vapply(yticks-yoffset,.brohn_er_tick,character(1))
  }
  x<-function(v)left+(v-range[[1]])/diff(range)*(right-left)
  y<-function(v)bottom-(v-limits[[1]])/diff(limits)*(bottom-top)
  id<-paste(component,width,sep="-");label<-switch(component,phasic_us="Phasic conductance",tonic_us="Tonic conductance",clean_us="Clean conductance")
  desc<-paste("Actual saved samples in microsiemens against seconds from the measured event onset. Separate source segments and excluded edges never join. Hatched windows lack complete saved baseline or response support. Markers are saved detector candidates; highlighted markers belong to the original selected response. Unavailable values remain unavailable.",result$display_policy)
  parts<-c(sprintf('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %s %s" role="img" aria-labelledby="er-%s-title er-%s-desc" style="width:100%%;height:auto;font-family:system-ui,Segoe UI,sans-serif"><title id="er-%s-title">%s</title><desc id="er-%s-desc">%s</desc>',width,height,id,id,id,esc(paste(label,"event window")),id,esc(desc)),
    paste0('<metadata>',esc(brohn_json(list(schema="brohn-eda-review-figure/1.0",binding=result$binding,event=e,parameters=p,component=component,counts=result$counts,range_s=result$range_s,markers=result$markers,display_axis_offset_us=yoffset,display_value_bounds=as.list(limits)))),'</metadata>'),
    sprintf('<defs><pattern id="er-hatch-%s" width="8" height="8" patternUnits="userSpaceOnUse"><path d="M0,8L8,0" stroke="#9e8f74" stroke-width="1"/></pattern></defs><rect width="%s" height="%s" fill="#14202b"/><text x="%s" y="23" fill="#e7edf1" font-size="14">%s (uS)</text>',id,width,height,left,esc(if(compact)sub(" conductance","",label)else label)))
  if(yoffset!=0)parts<-c(parts,sprintf('<text x="%s" y="389" fill="#d7e4ea" font-size="11" data-axis-offset="%.17g">Add %s uS to axis ticks</text>',left,yoffset,esc(format(yoffset,digits=6,trim=TRUE))))
  for(window in c("baseline","response")) {
    bounds<-unlist(p[[paste0(window,"_s")]]);support<-e[[paste0(window,"_support")]];valid<-isTRUE(support$complete)
    color<-if(window=="baseline")"#6887b2"else"#74b5a5";text_y<-if(window=="baseline")45 else 65
    parts<-c(parts,sprintf('<rect data-window="%s" data-complete="%s" x="%.9f" y="%s" width="%.9f" height="%s" fill="%s" fill-opacity=".13"/>',window,tolower(as.character(valid)),x(bounds[[1]]),top,x(bounds[[2]])-x(bounds[[1]]),bottom-top,color))
    if(!valid)parts<-c(parts,sprintf('<rect x="%.9f" y="%s" width="%.9f" height="%s" fill="url(#er-hatch-%s)" fill-opacity=".55"/>',x(bounds[[1]]),top,x(bounds[[2]])-x(bounds[[1]]),bottom-top,id))
    parts<-c(parts,sprintf('<text x="%s" y="%s" fill="#d7e4ea" font-size="12">%s: %s to %s s%s</text>',left,text_y,tools::toTitleCase(window),esc(.brohn_er_tick(bounds[[1]])),esc(.brohn_er_tick(bounds[[2]])),if(valid)""else" (incomplete)"))
  }
  parts<-c(parts,sprintf('<text x="%s" y="85" fill="#d7e4ea" font-size="12">Onset latency: %s to %s s</text>',left,esc(.brohn_er_tick(p$onset_latency_s[[1]])),esc(.brohn_er_tick(p$onset_latency_s[[2]]))),
    sprintf('<line x1="%.9f" x2="%.9f" y1="%s" y2="%s" stroke="#d5dfeb" stroke-dasharray="3 3" data-measured-onset="0"/>',x(0),x(0),top,bottom),
    sprintf('<line x1="%.9f" x2="%.9f" y1="100" y2="100" stroke="#c8bddb" stroke-width="3" data-latency-window="true"/>',x(p$onset_latency_s[[1]]),x(p$onset_latency_s[[2]])))
  for(event in result$source_events)if(event$time_s-e$time_s>=range[[1]]&&event$time_s-e$time_s<=range[[2]])parts<-c(parts,sprintf('<line x1="%.9f" x2="%.9f" y1="92" y2="108" stroke="%s" stroke-width="2" data-source-event="%s"><title>%s</title></line>',x(event$time_s-e$time_s),x(event$time_s-e$time_s),if(identical(event$id,e$event_id))"#f2f3f4"else"#ddad8d",esc(event$id),esc(paste(event$type,event$code,"at",.brohn_er_number(event$time_s-e$time_s),"seconds"))))
  for(g in paths) {
    points<-vapply(g$points,function(pt)sprintf("%.9f,%.9f",x(pt$time_s),y(pt$value)),character(1))
    if(length(points))parts<-c(parts,sprintf('<polyline data-table="%s" data-retained="%s" points="%s" fill="none" stroke="%s" stroke-width="1.8"%s/>',esc(g$table_id),tolower(as.character(g$retained)),paste(points,collapse=" "),if(g$retained)"#9bdccc"else"#a7aab8",if(g$retained)""else' stroke-dasharray="4 4"'))
  }
  if(component=="phasic_us")for(m in result$markers)if(isTRUE(m$in_view)&&!is.null(m$phasic_us)) {
    xx<-x(m$relative_time_s);yy<-y(m$phasic_us);selected<-isTRUE(m$selected_for_event)&&isTRUE(m$event_measure_usable)
    if(!selected&&m$kind!="peak")next
    title<-esc(paste(if(selected)"Original selected response"else"Saved detector candidate",m$kind,"at",.brohn_er_number(m$relative_time_s),"s;",.brohn_er_number(m$phasic_us),"uS"))
    if(selected&&m$kind=="peak")shape<-sprintf('<path d="M%.9f,%.9f l5,5 -5,5 -5,-5 Z" fill="#f1d597"/>',xx,yy-5)else if(selected&&m$kind=="onset")shape<-sprintf('<path d="M%.9f,%.9f l5,8 -10,0 Z" fill="#bdb1ed"/>',xx,yy-5)else shape<-sprintf('<circle cx="%.9f" cy="%.9f" r="%s" fill="%s" stroke="%s" stroke-width="2"/>',xx,yy,if(selected)4 else 3,if(selected)"#14202b"else"#a7aab8",if(selected)"#f1d597"else"#a7aab8")
    parts<-c(parts,sprintf('<g data-marker="%s" data-selected="%s" data-source-time="%.17g"><title>%s</title>%s</g>',m$kind,tolower(as.character(selected)),m$source_time_s,title,shape))
  }
  if(!length(values))parts<-c(parts,sprintf('<text x="%s" y="215" fill="#e7edf1" font-size="12">No processed samples in this window.</text>',left))
  for(index in seq_along(yticks))parts<-c(parts,sprintf('<text x="%s" y="%.9f" text-anchor="end" fill="#bdcdd6" font-size="12">%s</text>',left-8,y(yticks[[index]])+4,esc(tick_labels[[index]])))
  parts<-c(parts,sprintf('<path d="M%s,%sV%sH%s" fill="none" stroke="#79909e"/>',left,top,bottom,right))
  for(v in seq(range[[1]],range[[2]],length.out=if(compact)3 else 5))parts<-c(parts,sprintf('<text x="%.9f" y="337" text-anchor="%s" fill="#bdcdd6" font-size="12">%s</text>',x(v),if(v==range[[1]])"start"else if(v==range[[2]])"end"else"middle",esc(.brohn_er_tick(v))))
  parts<-c(parts,sprintf('<text x="%s" y="362" text-anchor="middle" fill="#e7edf1" font-size="12">Seconds from measured onset</text></svg>',(left+right)/2))
  paste(parts,collapse="")
}
.brohn_er_label <- function(e)paste(e$exposure_id,e$condition_id,e$channel,paste0("at ",.brohn_er_tick(e$time_s),"s"),sep=" | ")
brohn_install_eda_review <- function(input,output,session,store,state,attempt,message,prepare_download) {
  source<-shiny::reactiveVal(NULL);opened<-shiny::reactiveVal(NULL);pending<-shiny::reactiveVal(NULL);issue<-shiny::reactiveVal(NULL)
  urls<-shiny::reactiveVal(NULL);page<-shiny::reactiveVal(0L);markers_page<-shiny::reactiveVal(0L);history_tick<-shiny::reactiveVal(0L)
  native<-new.env(parent=emptyenv());native$guards<-list();native$process<-NULL;native$id<-NULL;native$expected<-NULL
  release<-function(){if(!is.null(native$process)&&native$process$is_alive())native$process$kill_tree();native$process<-NULL
    for(g in native$guards).brohn_qexplorer_release(g);native$guards<-list();native$id<-NULL
    if(!is.null(native$expected))unlink(native$expected);native$expected<-NULL;urls(NULL)}
  session$onSessionEnded(release)
  current<-function(){s<-source();brohn_require(!is.null(s)&&identical(state$page,"report")&&identical(state$report_id,s$id),"Reopen the original EDA report.")
    .brohn_qexplorer_catalog(store,"report",s$id,s$revision,s$project_id)
    r<-brohn_get_entity(store,"report",s$id);brohn_require(r$revision==s$revision&&identical(.brohn_sv_hash(r$body),.brohn_sv_hash(s$body)),"The current EDA report changed. Reopen its saved event review.");r}
  choice<-function(){s<-current();value<-input$eda_review_event;brohn_require(brohn_text(value,4000),"Choose a saved EDA event and channel.")
    sel<-jsonlite::fromJSON(value,simplifyVector=FALSE);brohn_eda_review_selection(s$body$analysis,sel);sel}
  same<-function(r)!is.null(r)&&!is.null(input$eda_review_event)&&identical(input$eda_review_event,brohn_json(r$body$request$selection))
  active<-function(){s<-current();r<-opened();brohn_require(same(r)&&identical(native$id,r$id)&&!is.null(urls()),"Reopen the verified current EDA event before exporting.")
    for(g in native$guards).Call(g$native$check,g$pointer)
    saved<-brohn_eda_review_record(store,r$id,s$id,s$project_id);brohn_require(identical(.brohn_sv_hash(saved$body),.brohn_sv_hash(r$body)),"The saved EDA review changed.");saved}
  shiny::observeEvent(list(state$page,state$report_id),{source(NULL);opened(NULL);pending(NULL);issue(NULL);release()},ignoreInit=FALSE,priority=110)
  shiny::observeEvent(input$open_eda_review,attempt(function(){c<-input$open_eda_review;brohn_require(identical(state$page,"report")&&identical(c$report_id,state$report_id),"Open the selected EDA report first.")
    r<-brohn_get_entity(store,"report",c$report_id);brohn_require(identical(.brohn_sv_hash(r$body),c$report_hash)&&brohn_eda_review_supported(r$body),"Reopen the current EDA report.")
    source(r);opened(NULL);pending(NULL);issue(NULL);page(0L);release();history_tick(history_tick()+1L)}))
  output$eda_review_controls<-shiny::renderUI({s<-source();if(is.null(s))return(NULL);events<-s$body$analysis$recordings;offset<-page();selected<-events[seq.int(offset+1,min(length(events),offset+25))]
    choices<-stats::setNames(vapply(selected,function(e)brohn_json(e[c("recording_id","event_id","channel")]),character(1)),vapply(selected,.brohn_er_label,character(1)))
    brohn_card(title="Choose an event and channel",subtitle=paste("Saved event/channel cells",offset+1,"to",min(offset+25,length(events)),"of",length(events)),
      shiny::selectInput("eda_review_event","Saved event and channel",choices,selectize=FALSE),
      shiny::div(class="brohn-toolbar",if(offset>0)brohn_command("Previous EDA events","eda_review_event_page",offset-25),if(offset+25<length(events))brohn_command("Next EDA events","eda_review_event_page",offset+25),
        shiny::actionButton("eda_review_prepare","Prepare event window",class="btn-primary")),shiny::p("Uses the original measured onset, recipe and complete saved conductance artifacts. No filtering, detection or scoring runs again."))})
  shiny::observeEvent(input$eda_review_event_page,attempt(function(){s<-current();value<-input$eda_review_event_page;brohn_require(brohn_number(value,0,length(s$body$analysis$recordings)-1,TRUE)&&value%%25==0,"Choose an available event page.");page(value);opened(NULL);release()}))
  submit<-function(retry=FALSE){s<-current();j<-brohn_queue_eda_review(store,s$id,s$revision,.brohn_sv_hash(s$body),choice(),retry);opened(NULL);release();issue(NULL);pending(j$id);markers_page(0L)}
  shiny::observeEvent(input$eda_review_prepare,attempt(function()submit()))
  shiny::observeEvent(input$eda_review_retry,attempt(function(){j<-brohn_get_job(store,pending());brohn_require(j$status %in% c("failed","cancelled"),"Only failed or cancelled reviews can retry.")
    brohn_require(.brohn_er_same(choice(),j$request$selection),"Choose the original failed event to retry, or prepare the newly selected event.");submit(TRUE)}))
  shiny::observeEvent(input$eda_review_cancel,attempt(function(){current();brohn_cancel_job(store,pending())}))
  shiny::observe({id<-pending();if(is.null(id))return();shiny::invalidateLater(1000,session);shiny::isolate(tryCatch({s<-current();j<-brohn_get_job(store,id)
    if(j$status=="succeeded"){opened(brohn_eda_review_record(store,j$result$eda_review_id,s$id,s$project_id));pending(NULL);history_tick(history_tick()+1L)}
  },error=function(e){issue(conditionMessage(e));pending(NULL)}))})
  output$eda_review_status<-shiny::renderUI({if(!is.null(issue()))return(shiny::p(role="status",class="brohn-alert",issue()));id<-pending();if(is.null(id))return(NULL)
    j<-brohn_get_job(store,id);if(j$status %in% c("queued","running"))shiny::invalidateLater(1000,session)
    shiny::div(role="status",shiny::p(paste("EDA event review:",j$status)),if(!is.null(j$error))shiny::p(j$error$message),
      if(j$status %in% c("queued","running"))shiny::actionButton("eda_review_cancel","Cancel EDA review")else if(j$status %in% c("failed","cancelled"))shiny::actionButton("eda_review_retry","Retry EDA review"))})
  # Native handles seal every source/export while hashes are checked outside Shiny.
  shiny::observe({r<-opened();if(is.null(r))return();shiny::invalidateLater(1000,session);shiny::isolate(tryCatch({
    if(!same(r)){release();return()};s<-current();saved<-brohn_eda_review_record(store,r$id,s$id,s$project_id)
    brohn_require(identical(.brohn_sv_hash(saved$body),.brohn_sv_hash(r$body)),"Saved EDA review authority changed.")
    if(is.null(native$id)&&is.null(native$process)) {
      i<-brohn_eda_review_input(store,list(operation="eda_review",request=r$body$request),verify=FALSE)
      refs<-c(i$source_objects,lapply(r$body$exports,function(x)list(hash=x$hash,bytes=x$size)),list(list(hash=r$body$result_object$hash,bytes=r$body$result_object$size)))
      refs<-unname(refs[!duplicated(vapply(refs,`[[`,character(1),"hash"))]);i$source_objects<-refs;native$guards<-brohn_hold_signal_value_sources(store,i)
      paths<-lapply(refs,function(x)list(path=brohn_object_path(store,x$hash,verify=FALSE),sha256=x$hash))
      native$expected<-tempfile("brohn-eda-envelope-",fileext=".json");brohn_write_json_file(r$body[setdiff(names(r$body),"result_object")],native$expected)
      code<-paste(c("import hashlib,json,sys", "for i in json.loads(sys.argv[1]):", " h=hashlib.sha256()", " with open(i['path'],'rb') as f:", "  for b in iter(lambda:f.read(1048576),b''):h.update(b)", " if h.hexdigest()!=i['sha256']:raise RuntimeError('EDA source or export bytes changed.')", "a=json.load(open(sys.argv[2],encoding='utf-8'));b=json.load(open(sys.argv[3],encoding='utf-8'))", "if a!=b:raise RuntimeError('Retained EDA review differs from its catalog.')"),collapse="\n")
      native$process<-processx::process$new(.brohn_publication_python(),c("-B","-c",code,brohn_json(paths),native$expected,brohn_object_path(store,r$body$result_object$hash,verify=FALSE)),stdout="|",stderr="|",cleanup_tree=TRUE,windows_hide_window=TRUE)
    }
    if(!is.null(native$process)&&!native$process$is_alive()) {
      brohn_require(native$process$get_exit_status()==0,paste("Unable to verify EDA source:",substr(native$process$read_all_error(),1,1000)));native$process<-NULL;native$id<-r$id
      links<-lapply(names(r$body$exports),function(name){ref<-r$body$exports[[name]];token<-brohn_token();path<-brohn_object_path(store,ref$hash,verify=FALSE)
        url<-session$registerDataObj(paste0("eda-",name),list(id=r$id,token=token),function(data,req)shiny::isolate(tryCatch({
          brohn_require(req$REQUEST_METHOD %in% c("GET","HEAD")&&identical(shiny::parseQueryString(brohn_default(req$QUERY_STRING,""))$key,data$token),"Expired EDA export.")
          brohn_require(identical(active()$id,data$id),"EDA selection changed.")
          structure(list(status=200L,content_type="text/csv; charset=utf-8",content=list(file=path,owned=FALSE),headers=list("Cache-Control"="no-store","X-Content-Type-Options"="nosniff","Content-Disposition"=paste0('attachment; filename="',name,'"'))),class="httpResponse")
        },error=function(e)structure(list(status=404L,content_type="text/plain",content="Reopen the current verified EDA event review."),class="httpResponse"))))
        list(name=name,url=paste0(url,"&key=",token))});urls(links)
    }
    for(g in native$guards).Call(g$native$check,g$pointer)
  },error=function(e){issue(conditionMessage(e));opened(NULL);release()}))})
  shiny::observeEvent(input$eda_review_markers_page,attempt(function(){r<-active();value<-input$eda_review_markers_page;brohn_require(brohn_number(value,0,max(0,length(r$body$result$markers)-1),TRUE)&&value%%50==0,"Choose an available marker page.");markers_page(value)}))
  output$eda_review_result<-shiny::renderUI({r<-opened();if(is.null(r))return(NULL);if(!same(r))return(shiny::p(role="status","The selected event changed. Prepare its window to inspect or export it."))
    if(is.null(urls()))return(shiny::p(role="status","Verifying the retained source and complete EDA exports in the background."))
    b<-r$body$result;e<-b$event;component<-brohn_default(input$eda_review_component,"phasic_us");offset<-markers_page();n<-length(b$markers)
    rows<-function(xs)lapply(xs,function(row)lapply(row,function(x)if(is.numeric(x)).brohn_er_number(x)else if(is.null(x))"Unavailable"else if(is.list(x))brohn_json(x)else x))
    shiny::div(style="min-width:0;overflow-wrap:anywhere",shiny::h3("Saved EDA event review"),shiny::p(.brohn_er_label(e)),
      shiny::p(paste("Original result:",e$status,"| SCR:",e$scr_status,"|",brohn_default(.brohn_er_reason(e$reason),brohn_default(.brohn_er_reason(e$scr_reason),"Measured support available")))),
      shiny::p(paste(b$counts$selected_rows,"complete saved samples in this window:",b$counts$retained_rows,"retained;",b$counts$excluded_rows,"excluded processing-edge samples.","This is one event within a person/session, not an independent-person estimate.")),
      shiny::selectInput("eda_review_component","Conductance component",c("Phasic"="phasic_us","Tonic"="tonic_us","Clean"="clean_us"),selected=component,selectize=FALSE),
      shiny::div(class="brohn-signal-wide",shiny::HTML(brohn_eda_review_svg(b,component))),shiny::div(class="brohn-signal-compact",shiny::HTML(brohn_eda_review_svg(b,component,320L))),
      shiny::p("Blue shading: baseline. Green shading: response. Hatching: incomplete saved window. Solid trace: retained samples; dashed trace: excluded edges. White vertical line: measured onset; top ticks: other saved events. Purple top bar: permitted onset latency. The right boundary is the declared recovery limit."),
      if(component=="phasic_us")shiny::p("Triangle: original selected SCR onset. Diamond: selected peak. Open circle: supported selected half recovery. Gray dots: other saved detector candidates. Unsupported recovery is never marked as a valid event measure."),
      if(!is.null(e$recovery_missing_reason))shiny::p(class="brohn-alert",paste("Half recovery unavailable:",.brohn_er_reason(e$recovery_missing_reason))),
      shiny::div(class="brohn-toolbar",shiny::downloadButton("eda_review_svg","Download EDA window SVG",icon=NULL),lapply(urls(),function(u)shiny::tags$a(href=u$url,download=u$name,class="btn btn-primary",switch(u$name,`eda-window-samples.csv`="Download every window sample",`eda-event-features.csv`="Download original event measures",`eda-response-markers.csv`="Download every response marker"))),shiny::downloadButton("eda_review_manifest","Download EDA review provenance",icon=NULL)),
      shiny::tags$details(shiny::tags$summary("Original measurements and denominators"),brohn_table(rows(b$features),maximum=30L,label="Original saved event measurements")),
      shiny::tags$details(shiny::tags$summary("Baseline and response support"),brohn_table(rows(lapply(c("baseline","response"),function(k)c(list(window=k),e[[paste0(k,"_support")]]))),label="Saved EDA window support"),shiny::p(paste("Same continuous segment:",e$same_continuous_segment,"| overlapping saved event IDs:",paste(unlist(e$overlapping_event_ids),collapse=", ")))),
      shiny::tags$details(shiny::tags$summary("Exact saved sample preview"),shiny::p(paste("First",length(b$rows),"of",b$counts$selected_rows,"selected rows. Download every window sample for the complete unaggregated values. Source indices are zero based; null is unavailable.")),brohn_table(rows(b$rows),maximum=50L,label="Exact saved EDA sample preview")),
      shiny::tags$details(shiny::tags$summary("Detected response markers"),shiny::p(paste("Showing",if(n)offset+1 else 0,"to",min(offset+50,n),"of",n,"saved marker positions.")),brohn_table(rows(if(n)b$markers[seq.int(offset+1,min(offset+50,n))]else list()),maximum=50L,label="Saved EDA response markers"),
        shiny::div(class="brohn-toolbar",if(offset>0)brohn_command("Previous response markers","eda_review_markers_page",offset-50),if(offset+50<n)brohn_command("Next response markers","eda_review_markers_page",offset+50))),
      shiny::tags$details(shiny::tags$summary("Source and interpretation"),shiny::p(paste("Clock origin:",e$source_time_origin,"| original unit:",e$source_unit,"| analysis unit: uS | recipe:",b$parameters$recipe)),shiny::p(b$display_policy),shiny::p("Conductance and detector candidates are physiological measurements, not emotion labels. No event alignment, response attribution or independent-participant inference is added by this view.")))})
  output$eda_review_svg<-shiny::downloadHandler(filename=function()paste0(active()$id,"-",brohn_default(input$eda_review_component,"phasic_us"),".svg"),contentType="image/svg+xml",content=function(file)prepare_download(function()writeLines(brohn_eda_review_svg(active()$body$result,brohn_default(input$eda_review_component,"phasic_us")),file,useBytes=TRUE)))
  output$eda_review_manifest<-shiny::downloadHandler(filename=function()paste0(active()$id,".json"),contentType="application/json",content=function(file)prepare_download(function()brohn_write_json_file(active()$body,file)))
  output$eda_review_history<-shiny::renderUI({history_tick();s<-source();if(is.null(s))return(NULL);records<-brohn_list_entities(store,"eda_review",s$project_id,limit=40L,filters=list(report_id=s$id))
    if(!length(records))return(NULL);shiny::tags$details(shiny::tags$summary("Saved EDA event windows"),lapply(records,function(r)shiny::div(class="brohn-toolbar",shiny::span(.brohn_er_label(r$body$result$event)),brohn_command("Reopen EDA window","eda_review_reopen",list(id=r$id,hash=.brohn_sv_hash(r$body))))))})
  shiny::observeEvent(input$eda_review_reopen,attempt(function(){s<-current();c<-input$eda_review_reopen;r<-brohn_eda_review_record(store,c$id,s$id,s$project_id);brohn_require(identical(.brohn_sv_hash(r$body),c$hash),"Reopen the current saved EDA view.")
    events<-s$body$analysis$recordings;index<-which(vapply(events,function(e).brohn_er_same(e[c("recording_id","event_id","channel")],r$body$request$selection),logical(1)))
    brohn_require(length(index)==1L,"The original saved EDA event changed.");page(as.integer((index-1)%/%25*25));release();issue(NULL);pending(NULL);opened(r);markers_page(0L)
    session$onFlushed(function()shiny::updateSelectInput(session,"eda_review_event",selected=brohn_json(r$body$request$selection)),once=TRUE)}))
  invisible(NULL)
}
