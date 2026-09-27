# Pure figure primitives are independent of explorer controllers and source lookup.
.brohn_rpe_region <- function(content,label,key,minimum=900L) {
  brohn_require(brohn_text(label,5000)&&brohn_text(key,180)&&grepl("^[a-z][a-z0-9-]*$",key)&&brohn_number(minimum,600,1600,TRUE),"EDA figure/table region identity is invalid.")
  hint<-shiny::p(id=paste0(key,"-help"),class="brohn-eda-scroll-help","On a narrow screen, scroll horizontally for the full figure or table. Keyboard: focus this area, then use the left and right arrow keys.")
  scroll<-function(x,caption_id=NULL)shiny::div(id=key,role="group",tabindex="0",`aria-label`=label,`aria-describedby`=paste(c(paste0(key,"-help"),caption_id),collapse=" "),class="brohn-eda-scroll",
    style="overflow-x:auto;max-width:100%;border-radius:4px;",shiny::div(style=paste0("min-width:",minimum,"px;"),x))
  if(inherits(content,"shiny.tag")&&identical(content$name,"figure")){
    is_caption<-vapply(content$children,function(x)inherits(x,"shiny.tag")&&identical(x$name,"figcaption"),logical(1))
    captions<-content$children[is_caption];content$children<-c(list(hint,scroll(content$children[!is_caption])),captions);return(content)
  }
  if(inherits(content,"shiny.tag")&&identical(content$name,"div")&&identical(content$attribs$class,"table-scroll")){
    tables<-which(vapply(content$children,function(x)inherits(x,"shiny.tag")&&identical(x$name,"table"),logical(1)))
    if(length(tables)==1L){table<-content$children[[tables]];at<-which(vapply(table$children,function(x)inherits(x,"shiny.tag")&&identical(x$name,"caption"),logical(1)))
      if(length(at)==1L){caption<-table$children[[at]];caption$name<-"p";caption$attribs<-c(caption$attribs,list(id=paste0(key,"-caption"),class="brohn-eda-table-caption"))
        table$children<-table$children[-at];table$attribs[["aria-describedby"]]<-paste0(key,"-caption")
        return(shiny::tagList(caption,hint,scroll(table,paste0(key,"-caption"))))
      }
    }
  }
  shiny::tagList(hint,scroll(content))
}
.brohn_rpe_figure_style <- paste0(".brohn-eda-scroll:focus-visible{outline:3px solid #ade9d7;outline-offset:3px}.brohn-eda-scroll svg{min-width:900px;max-width:none!important}.brohn-eda-scroll table{table-layout:auto;min-width:900px}.brohn-eda-scroll td,.brohn-eda-scroll th{overflow-wrap:normal;word-break:normal}.brohn-eda-scroll-help,.brohn-eda-table-caption{font-size:.875rem;color:#bdcbd0}",
  "@media print{.brohn-eda-scroll{overflow:visible!important;max-width:100%!important}.brohn-eda-scroll>div{min-width:0!important}.brohn-eda-scroll svg{min-width:0!important;width:100%!important;max-width:100%!important;height:auto!important}.brohn-eda-scroll table{min-width:0!important;width:100%!important;table-layout:fixed;font-size:11px}.brohn-eda-scroll td,.brohn-eda-scroll th{overflow-wrap:anywhere;word-break:normal;padding:4px}.brohn-eda-scroll-help{display:none}.brohn-eda-table-caption{color:#222}}")
.brohn_rpe_component_label <- function(x)switch(x,clean_us="cleaned conductance",tonic_us="tonic conductance",phasic_us="phasic conductance")
.brohn_rpe_reason <- function(reason) {
  if(is.null(reason))return(NULL)
  labels<-c(ambiguous_overlapping_events="Overlapping events prevent clear response attribution",
    incomplete_baseline_response_or_continuous_context="The baseline, response window or surrounding recording is incomplete",
    missing_gap_filter_edge_or_short_continuous_context="Missing data, a gap, processing edge or short recording limits support",
    no_qualifying_response="No response met the saved detection criteria",
    half_recovery_not_observed_in_retained_segment="Half recovery was not observed in the retained recording",
    half_recovery_after_declared_boundary="Half recovery occurs after the saved observation limit",
    another_event_precedes_half_recovery="Another event occurs before half recovery",
    unobserved_or_preexisting_scr_onset="Response onset is unobserved or precedes the permitted latency window",
    scr_detector_failed="The saved response detector did not produce usable results")
  if(reason%in%names(labels))unname(labels[[reason]])else gsub("_"," ",reason,fixed=TRUE)
}
.brohn_rpe_support_text <- function(c) {
  r<-c$original_support
  if(is.null(c$model))return(paste("No supported processed trace was saved for this cell.",.brohn_rpe_reason(c$reason)))
  if(identical(c$status,"no_processed_samples"))return("No processed samples fall within this saved view. The original model, whole-source measures and complete evidence remain available; no waveform is invented.")
  if(is.null(r$scr_status))return("The trace shows this saved segment/window. Whole-segment measures remain unchanged when the illustrated window is smaller; these continuous candidates are not event-attributed responses.")
  paste(if(r$status=="computed")"The saved baseline and response window support descriptive measures."else"The processed trace can be viewed, but its descriptive response-window measures are unavailable.",
    if(r$scr_status!="computed")"A response cannot be attributed to this event under the saved method."else if(isTRUE(r$nonresponse))"No response met the saved criteria: zero response magnitude is distinct from unavailable responder amplitude."else"The original saved response met this event's declared criteria.",
    paste(unique(Filter(Negate(is.null),lapply(list(r$reason,r$scr_reason,r$recovery_missing_reason),.brohn_rpe_reason))),collapse=". "))
}

.brohn_rpe_points <- function(model,component) {
  out<-list()
  for(gi in seq_along(model$series[[component]])){
    g<-model$series[[component]][[gi]]
    for(p in g$points)out[[length(out)+1L]]<-c(list(group_index=gi,table_id=g$table_id,retained=g$retained,group_source_rows=g$source_rows),p)
  };out
}
.brohn_rpe_axis <- function(cells,component,scope) {
  values<-unlist(lapply(cells,function(c)vapply(.brohn_rpe_points(c$model,component),`[[`,numeric(1),"value")),use.names=FALSE)
  brohn_require(length(values)>0L&&all(is.finite(values)),"EDA axis requires actual finite displayed samples.")
  observed<-range(values);bounds<-observed
  if(component=="phasic_us")bounds<-range(c(0,bounds))
  padding<-if(diff(bounds)>0)diff(bounds)*.04 else max(1,abs(bounds[[1L]])*.05)
  bounds<-bounds+c(-padding,padding)
  list(scope=scope,unit="uS",bounds=as.list(bounds),observed_bounds=as.list(observed),cell_keys=lapply(cells,`[[`,"key"))
}
.brohn_rpe_svg <- function(cell,component,marker_page,key,axis=NULL) {
  m<-cell$model;title<-if(is.null(component))"Saved EDA support"else switch(component,clean_us="Cleaned conductance",tonic_us="Tonic conductance",phasic_us="Phasic conductance")
  label<-paste(title,"\u2014",cell$identity$channel)
  if(is.null(m)||identical(cell$status,"no_processed_samples"))return(shiny::tags$svg(xmlns="http://www.w3.org/2000/svg",width=900,height=160,viewBox="0 0 900 160",role="img",`aria-labelledby`=paste0(key,"-title"),
    shiny::tags$title(id=paste0(key,"-title"),"Saved EDA support is unavailable"),shiny::tags$desc("No numerical waveform is invented. The complete original support and values remain in evidence."),shiny::tags$rect(width=900,height=160,fill="#14202b"),
    shiny::tags$text(x=24,y=56,fill="#e2ebe8",`font-size`=18,"No supported processed trace in this saved view")))
  points<-.brohn_rpe_points(m,component);brohn_require(length(points)>0L,"A real EDA component has no representative points.")
  xr<-if(!is.null(m$range_s))unlist(m$range_s)else as.numeric(c(m$selection$start_s,m$selection$end_s))
  if(is.null(axis))axis<-.brohn_rpe_axis(list(cell),component,"individual_view")
  yr<-unlist(axis$bounds,use.names=FALSE)
  brohn_require(length(xr)==2L&&all(is.finite(xr))&&diff(xr)>0&&all(is.finite(yr)),"EDA display axes are not finite and increasing.")
  xx<-function(v)80+(v-xr[[1L]])/diff(xr)*780;yy<-function(v)340-(v-yr[[1L]])/diff(yr)*220
  tags<-list(shiny::tags$title(id=paste0(key,"-title"),label),shiny::tags$desc(id=paste0(key,"-desc"),"Actual representative samples preserve separate contiguous support runs. Numerical alternatives describe displayed points; complete source samples remain in the evidence files."),
    shiny::tags$rect(width=900,height=510,fill="#14202b"),shiny::tags$text(x=80,y=26,fill="#e2ebe8",`font-size`=18,label),shiny::tags$rect(x=80,y=120,width=780,height=220,fill="none",stroke="#576861"))
  if(!is.null(m$event)){
    for(window in c("baseline","response")){
      bounds<-unlist(m$parameters[[paste0(window,"_s")]]);a<-max(xr[[1L]],bounds[[1L]]);b<-min(xr[[2L]],bounds[[2L]]);complete<-isTRUE(m$event[[paste0(window,"_support")]]$complete)
      if(a<b){tags<-c(tags,list(shiny::tags$rect(x=xx(a),y=120,width=xx(b)-xx(a),height=220,fill=if(window=="baseline")"#6887b2"else"#74b5a5",`fill-opacity`=.15,`data-window`=window,`data-complete`=tolower(as.character(complete)))))
        if(!complete)for(pos in seq(xx(a),xx(b),by=10))tags<-c(tags,list(shiny::tags$line(x1=pos,x2=min(pos+8,xx(b)),y1=340,y2=120,stroke="#9e8f74",`stroke-opacity`=.24)))
      }
      tags<-c(tags,list(shiny::tags$text(x=80,y=if(window=="baseline")47 else 65,fill="#d7e4ea",`font-size`=12,paste(tools::toTitleCase(window),paste(vapply(bounds,.brohn_rp_text,character(1)),collapse=" to "),"s",if(!complete)"(incomplete)"else"(complete)"))))
    }
    latency<-unlist(m$parameters$onset_latency_s)
    tags<-c(tags,list(shiny::tags$text(x=80,y=84,fill="#d7e4ea",`font-size`=12,paste("Permitted onset latency:",paste(vapply(latency,.brohn_rp_text,character(1)),collapse=" to "),"s; right edge is the saved recovery limit.")),
      shiny::tags$line(x1=xx(0),x2=xx(0),y1=120,y2=340,stroke="#e7edf1",`stroke-dasharray`="3 3",`data-measured-onset`="0"),
      shiny::tags$line(x1=xx(latency[[1L]]),x2=xx(latency[[2L]]),y1=110,y2=110,stroke="#c8bddb",`stroke-width`=3,`data-latency-window`="true")))
    for(event in m$source_events){time<-event$time_s-m$event$time_s
      if(event$type=="nuisance_event"){
        bounds<-time+unlist(m$parameters$nuisance_effect_s);a<-max(xr[[1L]],bounds[[1L]]);b<-min(xr[[2L]],bounds[[2L]])
        if(a<b)tags<-c(tags,list(shiny::tags$rect(x=xx(a),y=120,width=xx(b)-xx(a),height=220,fill="#db9d70",`fill-opacity`=.10,`data-nuisance-event`=event$id,shiny::tags$title("Saved nuisance-effect interval"))))
      }
      if(time>=xr[[1L]]&&time<=xr[[2L]])tags<-c(tags,list(shiny::tags$line(x1=xx(time),x2=xx(time),y1=92,y2=105,stroke=if(identical(event$id,m$event$event_id))"#e7edf1"else"#ddad8d",`stroke-width`=2,`data-source-event`=event$id,shiny::tags$title(paste(event$type,event$code,"at",.brohn_rp_text(time),"seconds")))))
    }
  }
  for(t in seq(xr[[1L]],xr[[2L]],length.out=5L))tags<-c(tags,list(shiny::tags$text(x=xx(t),y=365,`text-anchor`="middle",fill="#c4d2cc",`font-size`=12,.brohn_rp_text(t))))
  offset<-if(max(abs(yr))>0&&diff(yr)/max(abs(yr))<.0001)yr[[1L]]else 0
  for(t in seq(yr[[1L]],yr[[2L]],length.out=5L))tags<-c(tags,list(shiny::tags$text(x=70,y=yy(t)+4,`text-anchor`="end",fill="#c4d2cc",`font-size`=12,format(t-offset,digits=4,trim=TRUE))))
  tags<-c(tags,list(shiny::tags$text(x=470,y=391,`text-anchor`="middle",fill="#c4d2cc",`font-size`=13,if(!is.null(m$event))"Seconds from measured event onset"else"Original recording seconds"),shiny::tags$text(x=12,y=104,fill="#c4d2cc",`font-size`=13,if(offset==0)"uS"else paste("uS +",format(offset,digits=17,trim=TRUE)))))
  for(gi in seq_along(m$series[[component]])){
    g<-m$series[[component]][[gi]];coords<-vapply(g$points,function(p)paste(format(xx(p$time_s),digits=12,trim=TRUE),format(yy(p$value),digits=12,trim=TRUE),sep=","),character(1))
    tags<-c(tags,list(shiny::tags$polyline(points=paste(coords,collapse=" "),fill="none",stroke=if(isTRUE(g$retained))"#ade9d7"else"#adabb3",`stroke-width`=1.8,`stroke-dasharray`=if(isTRUE(g$retained))NULL else"4 3",`data-group`=gi,
      shiny::tags$title(paste("Support run",gi,"\u2014",g$source_rows,"original rows; retained",g$retained)))))
  }
  if(component=="phasic_us"){
    lo<-(marker_page-1L)*50L;selected<-utils::head(utils::tail(m$candidates,max(0L,length(m$candidates)-lo)),50L)
    belongs<-function(mark){if(is.null(m$event))mark$candidate_table_row_index%in%vapply(selected,`[[`,numeric(1),"table_row_index")else mark$candidate_source_peak_sample%in%vapply(selected,`[[`,numeric(1),"source_peak_sample")}
    marks<-Filter(function(mark)belongs(mark)||isTRUE(mark$selected_for_event),m$markers)
    for(mark in marks){time<-if(is.null(m$event))mark$time_s else mark$relative_time_s
      if(isTRUE(mark$in_view)&&is.numeric(time)&&is.numeric(mark$phasic_us)&&is.finite(time)&&is.finite(mark$phasic_us)){
        valid<-isTRUE(mark$selected_for_event)&&isTRUE(mark$event_measure_usable);x<-xx(time);y<-yy(mark$phasic_us);color<-if(valid)"#f1d597"else"#b5bfcb";size<-if(valid)5 else 3.5
        shape<-switch(mark$kind,onset=shiny::tags$polygon(points=paste(paste(x,y-size,sep=","),paste(x+size,y+size,sep=","),paste(x-size,y+size,sep=",")),fill=color),
          peak=shiny::tags$polygon(points=paste(paste(x,y-size,sep=","),paste(x+size,y,sep=","),paste(x,y+size,sep=","),paste(x-size,y,sep=",")),fill=color),
          recovery=shiny::tags$circle(cx=x,cy=y,r=size,fill="#14202b",stroke=color,`stroke-width`=2))
        tags<-c(tags,list(shiny::tags$g(`data-marker-kind`=mark$kind,`data-page-member`=tolower(as.character(belongs(mark))),`data-reference-anchor`=tolower(as.character(isTRUE(mark$selected_for_event))),`data-event-measure-usable`=tolower(as.character(valid)),
          shiny::tags$title(paste(if(valid)"Original selected response"else"Saved candidate endpoint (not a supported selected event measure)",mark$kind,"at",.brohn_rp_text(time),"seconds;",.brohn_rp_text(mark$phasic_us),"uS")),shape)))
      }
    }
    tags<-c(tags,list(shiny::tags$text(x=80,y=421,fill="#c4d2cc",`font-size`=12,paste("Candidate marker page",marker_page,"\u2014",length(selected),"of",length(m$candidates),"candidates. Missing endpoints have no invented marks.")),
      shiny::tags$text(x=80,y=444,fill="#c4d2cc",`font-size`=12,"Triangle: onset. Diamond: peak. Open circle: half recovery. Gray: saved candidate endpoint."),
      shiny::tags$text(x=80,y=467,fill="#f1d597",`font-size`=12,if(is.null(m$event))"Continuous candidate evidence does not select an event-attributed response."else"Gold: supported original selected-response anchors, repeated separately on every marker page.")))
  }
  tags<-c(tags,list(shiny::tags$text(x=80,y=492,fill="#c4d2cc",`font-size`=12,"Solid trace: retained samples. Dashed trace: excluded processing edges. Separate support runs never join.")))
  shiny::tags$svg(xmlns="http://www.w3.org/2000/svg",width=900,height=510,viewBox="0 0 900 510",role="img",`aria-labelledby`=paste0(key,"-title"),`aria-describedby`=paste0(key,"-desc"),`data-y-axis-scope`=axis$scope,`data-y-min`=format(yr[[1L]],digits=17,trim=TRUE),`data-y-max`=format(yr[[2L]],digits=17,trim=TRUE),`data-y-label-offset`=format(offset,digits=17,trim=TRUE),tags)
}
.brohn_rpe_section <- function(s,p,prefix,figure,friendly,sections=list(s)) {
  eda<-p$eda;brohn_require(!is.null(eda)&&.brohn_rp_same(s$source_ref,eda$entry$ref),"EDA section source differs from the saved preparation.")
  resolved<-brohn_resolve_eda_report_section(s,eda$entry$body$catalog)
  brohn_require(.brohn_rpe_same(resolved$section$resolved_models,s$resolved_models),"Frozen EDA figure resolution changed.")
  nodes<-list();coverage<-list()
  for(ci in seq_along(s$resolved_models)){
    r<-s$resolved_models[[ci]];at<-which(vapply(eda$display$cells,function(c)identical(c$key,r$key),logical(1)));brohn_require(length(at)==1L,"Exact EDA cell is absent.")
    c<-eda$display$cells[[at]];key<-paste0(prefix,"-cell-",sprintf("%04d",at));m<-c$model
    context_label<-if(s$adapter=="eda-events")paste(if(friendly).brohn_rp_friendly(c$original_support$exposure_id)else c$original_support$exposure_id,
      c$original_support$condition_id,paste("measured onset",.brohn_rp_text(c$original_support$time_s),"s"),sep=" | ")else paste("Segment",at)
    nodes<-c(nodes,list(shiny::h3(paste(context_label,"\u2014",c$identity$channel)),
      shiny::p(.brohn_rpe_support_text(c))))
    if(isTRUE(c$original_support$exact_flatline))nodes<-c(nodes,list(shiny::p("The saved recording is flagged as exactly flat. Its saved detector candidates need method review and must not be treated as physiological responses. The original flag, candidate values and calculations are preserved without rescoring.")))
    if(s$adapter=="eda-events"&&!is.null(m))nodes<-c(nodes,list(shiny::p("Blue shading is the baseline; green is the response window. Hatching means incomplete saved support. The white line marks measured onset, top ticks mark saved events, the purple bar is permitted onset latency, and orange shading marks a saved nuisance-effect interval when present."),
      shiny::p("Triangle: onset. Diamond: peak. Open circle: half recovery. Gold marks supported original selected-response anchors, repeated on every marker page separately from page membership. Gray endpoints do not imply a supported event response."),
      shiny::tags$details(shiny::tags$summary("View exact saved event windows and support"),.brohn_rp_table(lapply(c("baseline","response"),function(k)c(list(window=k),c$original_support[[paste0(k,"_support")]])),"Saved event-window support",maximum=2L),shiny::tags$pre(brohn_json(m$parameters,TRUE)))))
    if(is.null(m)||identical(c$status,"no_processed_samples"))nodes<-c(nodes,list(.brohn_rpe_region(figure(.brohn_rpe_svg(c,NULL,NULL,key),key,list(source=p$item$ref,cell_key=c$key,status=c$status,reason=c$reason,original_model_hash=c$model_hash)),paste("Unavailable EDA support",key),paste0(key,"-support"))))
    if(!is.null(m)){
      for(component in r$components){
        comparable<-list(c);scope<-"individual_segment_window"
        if(s$adapter=="eda-events"){
          keys<-unique(unlist(lapply(Filter(function(x)x$adapter=="eda-events"&&.brohn_rp_same(x$source_report_ref,s$source_report_ref),sections),function(x)lapply(Filter(function(z)component%in%unlist(z$components),x$resolved_models),`[[`,"key")),use.names=FALSE))
          comparable<-Filter(function(x)x$key%in%keys&&!is.null(x$model)&&identical(x$identity$channel,c$identity$channel)&&!identical(x$status,"no_processed_samples"),eda$display$cells)
          scope<-"selected_events_same_source_channel_component"
        }
        axis<-.brohn_rpe_axis(comparable,component,scope)
        nodes<-c(nodes,list(shiny::p(if(s$adapter=="eda-events")paste("Shared vertical scale for all",length(comparable),"selected event views of this source, channel and",.brohn_rpe_component_label(component),"component. Compare saved magnitudes as well as waveform shape; figure metadata retains the exact bounds.")else"This segment/window has its own vertical scale. Compare saved conductance measures before comparing trace heights across segments; figure metadata retains the exact bounds.")))
        pages<-if(component=="phasic_us")r$marker_pages else list(1L)
        for(page in pages){fk<-paste0(key,"-",gsub("_","-",component),"-page-",page)
          nodes<-c(nodes,list(.brohn_rpe_region(figure(.brohn_rpe_svg(c,component,page,fk,axis),fk,list(source=p$item$ref,cell_key=c$key,original_model_hash=c$model_hash,projected_model_value_hash=c$projected_model_value_hash,component=component,axis=axis,marker_page=if(component=="phasic_us")page else NULL)),paste("Saved EDA",.brohn_rpe_component_label(component),"cell",at,"marker page",page,prefix),paste0(fk,"-scroll"))))
        }
        rows<-.brohn_rpe_points(m,component);point_pages<-list()
        for(page in r$numerical_pages$points[[component]]){
          slice<-utils::head(utils::tail(rows,max(0L,length(rows)-(page-1L)*50L)),50L);tk<-paste0(key,"-",gsub("_","-",component),"-numbers-",page)
          point_pages<-c(point_pages,list(shiny::tags$details(shiny::tags$summary(paste("Numerical page",page,"\u2014",length(slice),"representative points")),.brohn_rpe_region(.brohn_rp_table(slice,"Representative displayed points; complete samples are in NDJSON/CSV",maximum=50L),paste("Representative EDA points",tk),tk))))
        }
        if(length(point_pages))nodes<-c(nodes,list(shiny::tags$details(shiny::tags$summary(paste("View",.brohn_rpe_component_label(component),"representative values \u2014",length(rows),"points;",length(point_pages),"selected numerical pages")),point_pages)))
      }
      candidate_pages<-list()
      for(page in r$numerical_pages$candidates){slice<-utils::head(utils::tail(m$candidates,max(0L,length(m$candidates)-(page-1L)*50L)),50L);tk<-paste0(key,"-candidates-",page)
        candidate_pages<-c(candidate_pages,list(shiny::tags$details(shiny::tags$summary(paste("Candidate numerical page",page)),.brohn_rpe_region(.brohn_rp_table(slice,"Saved candidate values in this selected window",maximum=50L),paste("EDA candidate values",tk),tk))))}
      if(length(candidate_pages))nodes<-c(nodes,list(shiny::tags$details(shiny::tags$summary(paste("View saved candidate values \u2014",length(m$candidates),"candidates;",length(candidate_pages),"selected numerical pages")),candidate_pages)))
    }
    features<-p$projection$analysis$features[unlist(c$feature_indices)]
    nodes<-c(nodes,list(shiny::tags$details(shiny::tags$summary(paste("View all",length(features),"saved cell measures and support")),.brohn_rpe_region(.brohn_rp_table(features,"Complete saved cell measures",c("name","value","unit","eligible","missing_reason","support_status"),maximum=100000L),paste("EDA cell measures",key),paste0(key,"-measures")))))
    coverage[[ci]]<-list(key=c$key,source_record_index=c$source_record_index,status=c$status,original_status=c$original_status,model_hash=c$model_hash,selected=r,complete_feature_count=length(features))
  }
  list(nodes=nodes,coverage=list(full_cells=length(eda$display$cells),selected_cells=length(coverage),cells=coverage,complete_evidence_preserved=TRUE))
}
