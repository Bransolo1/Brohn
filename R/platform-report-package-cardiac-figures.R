# Pure presentation of validated saved cardiac models; no source I/O or science.
.brohn_rpc_require <- function(value,message)if(!isTRUE(value))stop(paste("Cardiac figure:",message),call.=FALSE)
.brohn_rpc_num <- function(x)is.numeric(x)&&length(x)==1L&&!is.na(x)&&is.finite(x)
.brohn_rpc_finite <- function(x){if(is.numeric(x)).brohn_rpc_require(all(is.finite(x)),"nonfinite saved or display value.")else if(is.list(x))invisible(lapply(x,.brohn_rpc_finite));invisible(TRUE)}
.brohn_rpc_exact <- function(x){.brohn_rpc_require(.brohn_rpc_num(x),"numeric coordinate required.");if(x==0&&is.infinite(1/x)&&1/x<0)"-0"else format(x,digits=17,scientific=TRUE,trim=TRUE)}
.brohn_rpc_label <- function(x){.brohn_rpc_require(.brohn_rpc_num(x),"numeric label required.");if(x==0)"0"else format(signif(x,4),digits=4,trim=TRUE,scientific=abs(x)>=1e6||abs(x)<.001)}
.brohn_rpc_tick <- function(x){
 compact<-function(v)gsub("e([+-])0+","e\\1",gsub("e\\+","e",v))
 v<-compact(format(signif(x,3),digits=3,scientific=x!=0&&(abs(x)>=1e5||abs(x)<.001),trim=TRUE))
 if(nchar(v)>7L)v<-compact(format(signif(x,1),digits=1,scientific=TRUE,trim=TRUE))
 v
}
.brohn_rpc_same <- function(a,b)identical(brohn_json(a),brohn_json(b))
.brohn_rpc_reason <- function(a,fallback="No saved result is available.")if(!is.null(a$original_reason)&&nzchar(a$original_reason))gsub("_"," ",a$original_reason)else if(!is.null(a$reason_code))gsub("_"," ",a$reason_code)else fallback
.brohn_rpc_id <- function(x).brohn_rpc_require(is.character(x)&&length(x)==1L&&grepl("^[a-z][a-z0-9-]*$",x),"unique ASCII figure prefix required.")

brohn_cardiac_figure_style <- function()paste0(
 ".cardiac-report{min-width:0}.cardiac-report h3,.cardiac-report h4{line-height:1.35;overflow-wrap:anywhere}.cardiac-report h4{margin:12px 0 6px;font-size:1rem}",
 ".cardiac-cell{margin:24px 0;padding:16px;border:1px solid #60717c;border-radius:8px;min-width:0}.cardiac-report p,.cardiac-report figcaption,.cardiac-report summary{font-size:1rem;line-height:1.55;overflow-wrap:anywhere}",
 ".cardiac-report figure{margin:12px 0 20px;min-width:0}.cardiac-report svg{display:block;width:100%;max-width:640px;height:auto;background:#fff;color:#17212b;border:1px solid #819099;border-radius:4px}",
 ".cardiac-report .cardiac-caption{margin:6px 0 12px}.cardiac-report .cardiac-support{border-left:3px solid #80b5ca;padding-left:12px}.cardiac-report details{margin:16px 0}.cardiac-report pre{white-space:pre-wrap;overflow-wrap:anywhere;font-size:.9rem}",
 ".cardiac-report summary:focus-visible{outline:3px solid #86d8f2;outline-offset:4px}.cardiac-report .cardiac-ledger{padding:12px;border:1px solid #819099}",
 "@media(max-width:560px){.cardiac-report{margin-inline:-8px}.cardiac-cell{padding:0;margin:16px 0;border:0}.cardiac-report p,.cardiac-report figcaption,.cardiac-report summary{font-size:1rem}}",
 "@media print{.cardiac-report{color:#111}.cardiac-cell{border-color:#555;break-inside:auto}.cardiac-report figure{break-inside:avoid}.cardiac-report svg{max-width:520px;border-color:#555}.cardiac-report details{display:block}.cardiac-report details::details-content{content-visibility:visible;display:block}.cardiac-report details>*{display:block}.cardiac-report summary{font-weight:bold;outline:none}}")

.brohn_rpc_axis <- function(axis,unit=NULL){
 .brohn_rpc_require(is.list(axis)&&all(vapply(axis[c("minimum","maximum","observed_minimum","observed_maximum")],.brohn_rpc_num,logical(1))),"finite prepared axis required.")
 .brohn_rpc_require(is.finite(axis$maximum-axis$minimum)&&axis$maximum>axis$minimum&&axis$observed_maximum>=axis$observed_minimum&&axis$observed_minimum>=axis$minimum&&axis$observed_maximum<=axis$maximum,"prepared axis is not ordered or enclosing.")
 if(!is.null(unit)).brohn_rpc_require(identical(axis$unit,unit),"prepared axis uses another unit.")
 invisible(axis)
}
.brohn_rpc_x <- function(values){
 .brohn_rpc_require(length(values)>0L&&all(is.finite(values)),"finite horizontal coordinates required.")
 bounds<-range(values);if(bounds[[1L]]==bounds[[2L]])bounds<-bounds+c(-.5,.5)
 .brohn_rpc_require(is.finite(diff(bounds))&&diff(bounds)>0,"horizontal display range is not representable.");bounds
}
.brohn_rpc_plot <- function(key,title,desc,xr,axis,xlabel,unit,marks){
 .brohn_rpc_id(key);.brohn_rpc_axis(axis,unit)
 .brohn_rpc_require(length(xr)==2L&&all(is.finite(xr))&&is.finite(diff(xr))&&diff(xr)>0,"horizontal range is not finite and increasing.")
 xx<-function(v){.brohn_rpc_require(.brohn_rpc_num(v)&&v>=xr[[1L]]&&v<=xr[[2L]],"point lies outside its saved horizontal range.");48+(v-xr[[1L]])/diff(xr)*280}
 yy<-function(v){.brohn_rpc_require(.brohn_rpc_num(v)&&v>=axis$minimum&&v<=axis$maximum,"point lies outside its prepared vertical range.");174-(v-axis$minimum)/(axis$maximum-axis$minimum)*150}
 nodes<-list(shiny::tags$title(id=paste0(key,"-title"),title),shiny::tags$desc(id=paste0(key,"-desc"),desc),shiny::tags$rect(x=0,y=0,width=340,height=232,fill="#ffffff"),
   shiny::tags$rect(x=48,y=24,width=280,height=150,fill="none",stroke="#7c8990",`data-plot-area`="true"))
 xt<-seq(xr[[1L]],xr[[2L]],length.out=4L)
 for(i in seq_along(xt)){v<-xt[[i]];nodes<-c(nodes,list(shiny::tags$text(x=xx(v),y=194,`text-anchor`=if(i==1L)"start"else if(i==length(xt))"end"else"middle",fill="#17212b",`font-size`=13,.brohn_rpc_tick(v))))}
 for(v in seq(axis$minimum,axis$maximum,length.out=3L))nodes<-c(nodes,list(shiny::tags$text(x=42,y=yy(v)+4,`text-anchor`="end",fill="#17212b",`font-size`=12,.brohn_rpc_tick(v))))
 nodes<-c(nodes,list(shiny::tags$text(x=48,y=16,fill="#17212b",`font-size`=13,unit),shiny::tags$text(x=188,y=220,`text-anchor`="middle",fill="#17212b",`font-size`=13,xlabel)),marks(xx,yy))
 shiny::tags$svg(xmlns="http://www.w3.org/2000/svg",width=340,height=232,viewBox="0 0 340 232",role="img",`aria-labelledby`=paste0(key,"-title"),`aria-describedby`=paste0(key,"-desc"),
   `data-axis-min`=.brohn_rpc_exact(axis$minimum),`data-axis-max`=.brohn_rpc_exact(axis$maximum),`data-observed-min`=.brohn_rpc_exact(axis$observed_minimum),`data-observed-max`=.brohn_rpc_exact(axis$observed_maximum),`data-axis-scope`=axis$scope,nodes)
}
.brohn_rpc_wave <- function(cell,view,component,markers,key){
 cat<-cell$catalogue;axis<-view[[paste0(component,"_axis")]];.brohn_rpc_axis(axis,cat$unit)
 bounds<-view$window$requested;xr<-as.numeric(c(bounds$start_s,bounds$end_s))
 title<-paste(if(component=="raw")"Input waveform"else"Cleaned waveform",cat$unit,sep=" \u2014 ")
 .brohn_rpc_plot(key,title,"Saved representative waveform points. Separate fragments are never connected. Solid trace: retained samples; dashed trace: excluded processing edges. Symbols are exact saved detections on the cleaned waveform, positioned using joined original samples.",xr,axis,"Original recording seconds",cat$unit,function(xx,yy){
   nodes<-list();fragments<-view[[component]]
   for(i in seq_along(fragments)){
     f<-fragments[[i]];.brohn_rpc_require(is.logical(f$retained)&&length(f$retained)==1L&&!is.na(f$retained),"fragment retention must be boolean.")
     p<-f$representative_points;.brohn_rpc_require(length(p)>0L,"empty waveform fragment.")
     points<-vapply(p,function(p)paste(xx(p$time_s),yy(p$value),sep=","),character(1))
     content<-if(length(points)==1L)shiny::tags$circle(cx=xx(p[[1L]]$time_s),cy=yy(p[[1L]]$value),r=2,fill="#155e75")else shiny::tags$polyline(points=paste(points,collapse=" "),fill="none",stroke=if(f$retained)"#155e75"else"#596169",`stroke-width`=1.6,`stroke-dasharray`=if(f$retained)NULL else"5 4")
     nodes<-c(nodes,list(shiny::tags$g(`data-fragment`=i,`data-break-before`=f$break_before,`data-retained`=tolower(as.character(f$retained)),`data-representative-count`=length(p),shiny::tags$title(paste("Fragment",i,"\u2014",f$source_rows,"original rows;",f$break_before)),content)))
   }
   for(mark in markers){x<-xx(mark$time_s);y<-yy(mark[[component]])
     nodes<-c(nodes,list(shiny::tags$circle(cx=x,cy=y,r=3.5,fill="#ffffff",stroke="#8b3b12",`stroke-width`=1.8,`data-marker-row`=mark$event_row_index,`data-source-sample-index`=mark$source_sample_index,`data-time-s`=.brohn_rpc_exact(mark$time_s),`data-value`=.brohn_rpc_exact(mark[[component]]),shiny::tags$title(paste("Saved detection at source sample",mark$source_sample_index,";",.brohn_rpc_exact(mark$time_s),"s;",.brohn_rpc_exact(mark[[component]]),cat$unit)))))
   };nodes
 })
}
.brohn_rpc_intervals <- function(cell,view,key){
 .brohn_rpc_require(identical(view$connection_policy,"none")&&identical(view$basis,"saved_previous_interval_at_ending_peak"),"interval plot must use unconnected saved previous intervals.")
 .brohn_rpc_require(length(view$points)==view$plotted&&length(view$points)>0L,"interval scatter count does not match saved points.")
 xr<-.brohn_rpc_x(vapply(view$points,function(p)p$time_s,numeric(1)));.brohn_rpc_axis(view$axis,"ms")
 .brohn_rpc_plot(key,"Saved detected intervals","Each mark is a saved previous interval at its ending peak. Circles: saved plausible interval. Crosses: saved implausible interval. No connecting line or invented first interval.",xr,view$axis,"Ending peak: original seconds","ms",function(xx,yy){
   lapply(view$points,function(p){.brohn_rpc_require(is.logical(p$plausible)&&length(p$plausible)==1L&&!is.na(p$plausible),"interval plausibility must be a boolean.")
     x<-xx(p$time_s);y<-yy(p$interval_ms);shape<-if(p$plausible)shiny::tags$circle(cx=x,cy=y,r=3.3,fill="#155e75")else shiny::tagList(shiny::tags$line(x1=x-4,y1=y-4,x2=x+4,y2=y+4,stroke="#8b3b12",`stroke-width`=2),shiny::tags$line(x1=x-4,y1=y+4,x2=x+4,y2=y-4,stroke="#8b3b12",`stroke-width`=2))
     shiny::tags$g(`data-event-row`=p$event_row_index,`data-time-s`=.brohn_rpc_exact(p$time_s),`data-interval-ms`=.brohn_rpc_exact(p$interval_ms),`data-plausible`=tolower(as.character(p$plausible)),shiny::tags$title(paste(if(p$plausible)"Saved plausible"else"Saved implausible",.brohn_rpc_exact(p$interval_ms),"ms at",.brohn_rpc_exact(p$time_s),"s")),shape)
   })
 })
}
.brohn_rpc_spectrum <- function(view,key){
 .brohn_rpc_require(identical(view$availability$status,"available")&&identical(view$values_reestimated,FALSE)&&length(view$rows)>0L&&length(view$rows)==view$plotted_bins&&length(view$bin_row_indices)==length(view$rows),"saved spectrum coverage is inconsistent.")
 .brohn_rpc_require(all(vapply(view$rows,function(r)length(r)==3L&&identical(r[[1L]],"interval_psd_bin")&&.brohn_rpc_num(r[[2L]])&&r[[2L]]>=0&&.brohn_rpc_num(r[[3L]])&&r[[3L]]>=0,logical(1))),"saved spectrum rows must contain finite nonnegative frequency and density.")
 xr<-.brohn_rpc_x(vapply(view$rows,function(r)r[[2L]],numeric(1)));.brohn_rpc_axis(view$axis,"ms^2/Hz")
 .brohn_rpc_plot(key,"Saved interval power spectrum","Exact saved density bins. Available zero power is drawn at zero; an unavailable spectrum has no axes. No spectral values are recomputed.",xr,view$axis,"Frequency (Hz)","ms^2/Hz",function(xx,yy){
   # Axis uses the source unit spelling; SVG uses a readable label below.
   lapply(seq_along(view$rows),function(i){r<-view$rows[[i]];shiny::tags$circle(cx=xx(r[[2L]]),cy=yy(r[[3L]]),r=1.7,fill="#155e75",`data-bin-row`=view$bin_row_indices[[i]],`data-frequency-hz`=.brohn_rpc_exact(r[[2L]]),`data-density-ms2-hz`=.brohn_rpc_exact(r[[3L]]),shiny::tags$title(paste(.brohn_rpc_exact(r[[2L]]),"Hz;",.brohn_rpc_exact(r[[3L]]),"ms\u00b2/Hz")))})
 })
}

brohn_cardiac_report_figures <- function(evidence,joined_markers,analysis,prefix,figure=NULL){
 .brohn_rpc_id(prefix);.brohn_rpc_finite(evidence);.brohn_rpc_finite(joined_markers);.brohn_rpc_finite(analysis)
 .brohn_rpc_require(identical(evidence$schema,"brohn-cardiac-display-evidence/0.1")&&identical(evidence$scientific_processing_performed,FALSE)&&evidence$outcome$cell_count==length(evidence$cells),"validated saved evidence and exact outcome count required.")
 .brohn_rpc_require(is.list(joined_markers)&&is.list(analysis)&&analysis$kind%in%c("ecg","ppg"),"admitted cardiac analysis and marker arrays required.")
 if(is.null(figure))figure<-function(svg,key,metadata)shiny::tags$figure(id=paste0(key,"-figure"),svg)
 .brohn_rpc_require(is.function(figure),"figure callback must be a function.")
 emitted<-list();cells<-list()
 draw<-function(svg,key,meta){meta<-c(list(source_ref=evidence$source_ref),meta);emitted[[length(emitted)+1L]]<<-c(list(key=key),meta);figure(svg,key,meta)}
 status<-evidence$outcome$source_status
 outcome<-if(!length(evidence$cells))"No surviving recording cells are saved in this report. No waveform, detection or interval is invented."else paste("Saved report:",gsub("_"," ",status),"\u2014",length(evidence$cells),"original recording/run records.")
 nodes<-list(shiny::p(class="cardiac-support",outcome))
 if(!is.null(evidence$outcome$original_reason))nodes<-c(nodes,list(shiny::p("Saved reason: ",evidence$outcome$original_reason)))
 if(!is.null(evidence$outcome$exclusion_review_object))nodes<-c(nodes,list(shiny::p(class="cardiac-ledger","This is a saved analysis after researcher exclusions. The exact accepted review, predicted surviving support and actual run outcomes remain in the complete ledger evidence; exclusion does not establish artifact or normal-beat classification.")))
 nodes<-c(nodes,list(shiny::p(class="cardiac-interpretation",if(analysis$kind=="ecg")"Intervals are between detected ECG R peaks; normal-to-normal beats are not established."else"Intervals are between detected PPG pulse peaks (PRV); they are not ECG RR intervals or confirmed normal-to-normal beats."),
   shiny::tags$details(class="cardiac-method",shiny::tags$summary("Saved method and full interpretation limits"),
   shiny::p("Figures use saved input/cleaned samples, detections, previous intervals and spectrum bins. They do not repeat filtering, detection, interval estimation or spectral analysis. Complete evidence remains separate from the selected figures."),
   shiny::h4("Saved effective settings and implementation"),shiny::tags$pre(brohn_json(list(parameters=analysis$parameters,engine=analysis$engine),TRUE)),
   shiny::tags$ul(lapply(analysis$limitations,function(x)shiny::tags$li(x))))))
 for(i in seq_along(evidence$cells)){
   cell<-evidence$cells[[i]];cat<-cell$catalogue;key<-paste0(prefix,"-cell-",i);parts<-list(shiny::h3(paste(toupper(cat$modality),"recording",cat$source_record_index)),
     shiny::p(class="cardiac-support",paste("Saved status:",cat$source_status)),
     shiny::tags$details(class="cardiac-source-context",shiny::tags$summary("Exact source identity and coordinates"),
       shiny::p("Saved source label: ",cat$label),shiny::tags$pre(brohn_json(cat$identity,TRUE)),
       shiny::p(class="cardiac-caption",paste("Original source samples [",cat$source_sample_start,", ",cat$source_sample_end_exclusive,"); clock origin ",cat$source_time_origin," ",cat$source_time_unit,". Times below are original recording seconds; source indices are zero-based.",sep="")),
       shiny::p("Axis and summary labels are rounded for presentation only; these exact source bounds and every saved scientific value remain unchanged.")))
   base<-list(cell_key=cat$key,source_record_index=cat$source_record_index,model_hash=cat$model_hash)
   if(!is.null(cat$original_reason))parts<-c(parts,list(shiny::p("Original saved reason: ",cat$original_reason)))
   if(cat$figure_state=="evidence_only"){
     .brohn_rpc_require(!length(cell$waveform_views)&&!length(cell$interval_views)&&is.null(cell$spectrum_view),"evidence-only cell contains illustrated geometry.")
     parts<-c(parts,list(shiny::p("Figures were omitted by the saved display selection. Original support, measures, complete streams and exact detection joins remain in the included evidence.")))
   }else if(cat$figure_state=="unavailable"){
     .brohn_rpc_require(!length(cell$waveform_views)&&!length(cell$interval_views),"unavailable cell contains waveform or interval geometry.")
     parts<-c(parts,list(shiny::p("Saved recording unavailable: ",if(is.null(cat$original_reason))"No supported processed recording is saved."else cat$original_reason)))
   }else{
     .brohn_rpc_require(identical(cat$figure_state,"illustrated")&&isTRUE(cat$all_marker_joins_checked),"illustrated cell must retain complete join verification.")
     marks<-joined_markers[[cat$key]];if(is.null(marks))marks<-list()
     ids<-vapply(marks,function(m)m$event_row_index,numeric(1));.brohn_rpc_require(!anyDuplicated(ids),"duplicate joined marker row.")
     for(view in cell$waveform_views){
       w<-view$window;wk<-paste0(key,"-window-",w$number)
       parts<-c(parts,list(shiny::h4(paste("Waveform window",w$number)),shiny::p(class="cardiac-caption",paste(.brohn_rpc_label(as.numeric(w$requested$start_s)),"to",.brohn_rpc_label(as.numeric(w$requested$end_s)),"original seconds;",w$selected_samples,"saved samples.")),
         shiny::tags$details(class="cardiac-source-context",shiny::tags$summary("Exact window bounds and sample support"),
           shiny::p(paste("Requested",w$requested$start_s,"to",w$requested$end_s,"seconds;",w$boundary,"boundary.")),
           if(!is.null(w$observed))shiny::p(paste("Observed source samples",w$first_source_sample_index,"through",w$last_source_sample_index,"(inclusive); saved observed times",w$observed$start_s,"to",w$observed$end_s,"seconds.")))))
       if(w$state=="empty_range"){parts<-c(parts,list(shiny::p("No saved samples lie in this selected time range. No waveform or axes are invented.")));next}
       .brohn_rpc_require(identical(w$state,"available")&&isTRUE(view$markers$all_source_joins_checked),"waveform window or join status is invalid.")
       parts<-c(parts,list(shiny::p(paste("Saved detections:",view$markers$in_window,"in this window;",view$markers$source_total,"in the complete source;",view$markers$outside_window,"outside. Omitted marker pages:",if(length(view$markers$omitted_page_numbers))paste(unlist(view$markers$omitted_page_numbers),collapse=", ")else"none","."))))
       .brohn_rpc_require(identical(view$raw_axis$unit,view$clean_axis$unit)&&identical(view$raw_axis$unit,cat$unit),"input and cleaned waveforms require the same saved unit.")
       if(view$scale_mode=="shared").brohn_rpc_require(view$raw_axis$minimum==view$clean_axis$minimum&&view$raw_axis$maximum==view$clean_axis$maximum,"shared waveform axes differ.")else .brohn_rpc_require(view$scale_mode=="separate_labelled","unknown waveform scale mode.")
       parts<-c(parts,list(shiny::p(if(view$scale_mode=="shared")paste("Input and cleaned waveforms share a vertical scale in",cat$unit,".")else paste("Input and cleaned waveforms use separate labelled vertical scales in",cat$unit,"; compare axis values, not trace heights."))))
       page_numbers<-unlist(view$markers$resolved_page_numbers,use.names=FALSE);available<-vapply(view$markers$pages,`[[`,numeric(1),"number")
       .brohn_rpc_require(!anyDuplicated(page_numbers)&&!anyDuplicated(available)&&all(page_numbers%in%available),"selected marker page is absent or duplicated.")
       pages<-if(length(page_numbers))lapply(page_numbers,function(n)view$markers$pages[[match(n,available)]])else list(NULL)
       for(page in pages){selected<-list();page_no<-if(is.null(page))NULL else page$number
         if(!is.null(page)){
           rows<-unlist(page$event_rows,use.names=FALSE);.brohn_rpc_require(!anyDuplicated(rows)&&all(rows%in%ids)&&length(rows)==page$plotted,"selected marker row is absent, duplicated or miscounted.")
           selected<-marks[match(rows,ids)]
           for(m in selected).brohn_rpc_require(.brohn_rpc_same(m$event_table_ref,cat$tables$peaks)&&.brohn_rpc_same(m$series_table_ref,cat$tables$samples)&&identical(m$alignment,"exact_source_sample_and_recorded_time")&&identical(m$detection_basis,"saved_cleaned_waveform")&&m$source_sample_index>=w$first_source_sample_index&&m$source_sample_index<=w$last_source_sample_index,"selected marker does not match its exact source/window binding.")
         }
         pk<-paste0(wk,"-page-",if(is.null(page_no))"none"else page_no)
         parts<-c(parts,list(shiny::p(if(is.null(page_no))if(view$markers$in_window==0)"No saved detections in this window."else"Detection marks omitted by the saved page selection."else paste("Detection page",page_no,"of",length(available),"\u2014",length(selected),"shown;",page$on_other_pages,"on other pages."))))
         for(component in c("raw","clean")){fk<-paste0(pk,"-",component);parts<-c(parts,list(shiny::h4(if(component=="raw")"Input waveform"else"Cleaned waveform"),draw(.brohn_rpc_wave(cell,view,component,selected,fk),fk,c(base,list(kind="waveform",component=component,window=w,marker_page=page_no,event_rows=if(is.null(page))list()else page$event_rows))))) }
       }
       parts<-c(parts,list(shiny::p("Solid: retained samples. Dashed: excluded processing edges. Gaps and separate fragments stay disconnected. Open circles: exact saved detections, detected on the cleaned waveform and joined to both waveforms.")))
     }
     for(view in cell$interval_views){parts<-c(parts,list(shiny::h4(paste("Saved intervals \u2014 page",view$number))))
       if(!length(view$points)){parts<-c(parts,list(shiny::p("This page contains no saved finite previous intervals. A first detection has no invented interval.")));next}
       fk<-paste0(key,"-intervals-",view$number);parts<-c(parts,list(draw(.brohn_rpc_intervals(cell,view,fk),fk,c(base,list(kind="intervals",page=view$number,event_rows=lapply(view$points,`[[`,"event_row_index")))),shiny::p(class="cardiac-caption",paste("Circles: saved plausible intervals. Crosses: saved implausible intervals. No connecting line.",view$plotted,"saved values;",length(view$null_interval_rows),"rows without an interval remain unplotted."))))
     }
     if(!length(cell$interval_views))parts<-c(parts,list(shiny::p("Interval figure: ",.brohn_rpc_reason(cat$intervals,"No interval page was selected; complete saved intervals remain in evidence."))))
     spectrum<-cell$spectrum_view;parts<-c(parts,list(shiny::h4("Saved interval power spectrum")))
     if(!is.null(spectrum)&&identical(spectrum$availability$status,"available")){
       fk<-paste0(key,"-spectrum");zero<-length(spectrum$rows)>0L&&all(vapply(spectrum$rows,function(r)r[[3L]]==0,logical(1)))
       # Use the exact source spelling for axis validation and a readable HTML unit.
       svg<-.brohn_rpc_spectrum(spectrum,fk)
       parts<-c(parts,list(draw(svg,fk,c(base,list(kind="spectrum",bin_rows=spectrum$bin_row_indices))),shiny::p(class="cardiac-caption",paste(spectrum$plotted_bins,"of",spectrum$total_bins,"saved density bins;",spectrum$omitted_bins,"omitted by the saved display selection. Density unit: ms\u00b2/Hz."))))
       if(zero)parts<-c(parts,list(shiny::p("Available spectrum with every displayed saved bin exactly zero. This is a saved numerical result, not an unavailable spectrum or a physiological claim.")))
       if(!is.null(spectrum$axis$display_padding_reason))parts<-c(parts,list(shiny::p(paste("Vertical range is padded for display. Saved observed density range:",.brohn_rpc_label(spectrum$axis$observed_minimum),"to",.brohn_rpc_label(spectrum$axis$observed_maximum),"ms^2/Hz."))))
       support<-spectrum$saved_support;if(!is.null(support$integrated_bands_ms2))parts<-c(parts,list(shiny::p(paste("Saved LF power:",.brohn_rpc_label(support$integrated_bands_ms2$LF),"ms\u00b2; saved HF power:",.brohn_rpc_label(support$integrated_bands_ms2$HF),"ms\u00b2. These values are copied from saved support, not integrated by this renderer."))))
       ratio<-Filter(function(f)grepl("_lf_hf_ratio_candidate$",f$name),cell$original_features)
       if(length(ratio)==1L&&is.null(ratio[[1L]]$value))parts<-c(parts,list(shiny::p("Saved LF/HF ratio unavailable: ",if(is.null(ratio[[1L]]$unavailable_reason))"No saved ratio."else gsub("_"," ",ratio[[1L]]$unavailable_reason))))
     }else parts<-c(parts,list(shiny::p("Spectrum unavailable: ",.brohn_rpc_reason(if(is.null(spectrum))cat$spectrum else spectrum$availability))))
   }
   cells[[i]]<-list(key=cat$key,figure_state=cat$figure_state,source_record_index=cat$source_record_index)
   nodes<-c(nodes,list(shiny::tags$section(id=key,class="cardiac-cell",parts)))
 }
 list(nodes=list(shiny::div(class="cardiac-report",nodes)),coverage=list(cells=cells,figures=emitted,figure_count=length(emitted),scientific_values_changed=FALSE,complete_tables_owner="host_adapter"))
}
