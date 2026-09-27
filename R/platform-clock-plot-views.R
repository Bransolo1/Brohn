# Pure presentation of an already qualified complete clock-plot artifact.
# Current reader/source authority and object verification belong to its caller.
# Screen positions use bounded display_x/display_y only; exact times and values
# are displayed as strings and are never converted into R double coordinates.
.brohn_cpv_require <- function(ok,message)if(!isTRUE(ok))stop(message,call.=FALSE)
.brohn_cpv_text <- function(value,fallback="Unavailable")if(is.null(value)||length(value)!=1L||is.na(value))fallback else as.character(value)
.brohn_cpv_fraction <- function(value)paste(.brohn_cpv_text(value$numerator),.brohn_cpv_text(value$denominator),sep="/")
.brohn_cpv_number <- function(value)formatC(value,format="f",digits=4L,decimal.mark=".")
.brohn_cpv_position <- function(value){.brohn_cpv_require(is.numeric(value)&&length(value)==1L&&is.finite(value)&&value>=0&&value<=1,
 "Reopen a qualified clock plot with bounded display positions.");value}
.brohn_cpv_points <- function(lane)unlist(lapply(lane$runs,function(run)unlist(lapply(run$groups,`[[`,"points"),recursive=FALSE)),recursive=FALSE)
.brohn_cpv_name <- function(lane)paste(if(identical(lane$recording_side,"source"))"Source"else"Reference",.brohn_cpv_text(lane$channel$label,lane$channel$id),sep=" \u00b7 ")
.brohn_cpv_unit <- function(lane).brohn_cpv_text(lane$unit,"unit not declared")
.brohn_cpv_short <- function(text,limit=160L){text<-.brohn_cpv_text(text);if(nchar(text)>limit)paste0(substr(text,1L,limit),"\u2026 (full value in original exports)")else text}
.brohn_cpv_colour <- function(lane)if(identical(lane$recording_side,"source"))"#A7E9D3"else"#A8C8FB"
.brohn_cpv_axis <- function(plot)htmltools::tagList(
 htmltools::tags$div(class="brohn-clock-plot-axis",`aria-hidden`="true",lapply(plot$axis$ticks[c(1L,3L,5L)],function(t)
   htmltools::tags$code(.brohn_cpv_text(t$display_offset_label)))),
 htmltools::tags$p(class="brohn-clock-plot-note",paste("Seconds after the displayed base",plot$axis$display_base_exact_decimal,"(reference-relative seconds).")))

brohn_clock_plot_svg <- function(plot,lane,kind=c("signal","events"),id="clock-plot-figure") {
 kind<-match.arg(kind);.brohn_cpv_require(is.character(id)&&length(id)==1L&&grepl("^[A-Za-z][A-Za-z0-9_-]{0,100}$",id),"Use a distinct safe plot element identity.")
 width<-720L;height<-if(kind=="signal")180L else 100L;left<-12;right<-708;top<-12;bottom<-height-12
 x<-function(value).brohn_cpv_number(left+.brohn_cpv_position(value)*(right-left))
 y<-function(value).brohn_cpv_number(bottom-.brohn_cpv_position(value)*(bottom-top))
 n<-.brohn_cpv_number;colour<-.brohn_cpv_colour(lane);title<-.brohn_cpv_name(lane)
 grid<-lapply(c(0,.25,.5,.75,1),function(p)htmltools::tags$line(x1=x(p),x2=x(p),y1=top,y2=bottom,stroke="#354650",`stroke-width`="1",`vector-effect`="non-scaling-stroke"))
 marks<-list()
 if(kind=="signal"){
  .brohn_cpv_require(length(lane$runs)<=8192L,"The clock plot exceeds its qualified continuity bound.")
  marks<-lapply(lane$runs,function(run){points<-unlist(lapply(run$groups,`[[`,"points"),recursive=FALSE)
   .brohn_cpv_require(length(points)>0L,"A saved continuity run has no original representatives.")
   tip<-paste("Original rows",run$first_sequence,"to",run$last_sequence,"|",run$represented_rows,"supported observations;",length(points),"display representatives. Connections are display guides only.")
   if(length(points)==1L)return(htmltools::tags$circle(cx=x(points[[1L]]$display_x),cy=y(points[[1L]]$display_y),r="3",fill=colour,
     `data-clock-plot-run`=run$run_id,`data-original-sequence`=points[[1L]]$source_sequence,htmltools::tags$title(tip)))
   coordinates<-vapply(points,function(p)paste(x(p$display_x),y(p$display_y),sep=","),character(1))
   htmltools::tags$polyline(points=paste(coordinates,collapse=" "),fill="none",stroke=colour,`stroke-width`="1.5",`vector-effect`="non-scaling-stroke",
     `data-clock-plot-run`=run$run_id,`data-first-sequence`=run$first_sequence,`data-last-sequence`=run$last_sequence,
     `data-representatives`=length(points),htmltools::tags$title(tip))})
  points<-.brohn_cpv_points(lane);extrema<-unique(vapply(Filter(Negate(is.null),lane$exact_y_range[c("minimum","maximum")]),function(a)a$original_row_reference$source_sequence,numeric(1)))
  extreme_points<-Filter(function(p)p$source_sequence%in%extrema,points)
  marks<-c(marks,lapply(extreme_points,function(p)htmltools::tags$circle(cx=x(p$display_x),cy=y(p$display_y),r="3.2",fill="#111A21",stroke=colour,
    `stroke-width`="1.7",`vector-effect`="non-scaling-stroke",`data-clock-plot-extreme`=p$source_sequence,
    htmltools::tags$title(paste("Original row",p$source_sequence,"|",p$value_json,.brohn_cpv_unit(lane))))))
  description<-paste(lane$display_counts$numeric_observed,"supported original observations;",lane$display_counts$representatives,"actual representatives in",
    length(lane$runs),"separate continuity runs.",lane$display_counts$saved_missing,"missing values;",lane$display_counts$exact_export_only,
    "values available only in the original export. Runs are never joined across gaps or changed identity context. Each signal has its own value scale.")
 }else if(identical(lane$mode,"individual")){
  .brohn_cpv_require(length(lane$events)<=2000L,"The saved individual-event display exceeds its qualified bound.")
  marks<-lapply(lane$events,function(e)htmltools::tags$line(x1=x(e$display_x),x2=x(e$display_x),y1=30,y2=70,stroke=colour,`stroke-width`="1.25",`vector-effect`="non-scaling-stroke",
    `data-clock-plot-event`=e$original_row_reference$source_sequence,
    htmltools::tags$title(paste("Original event row",e$original_row_reference$source_sequence,"|",if(!identical(e$value_state,"observed"))"Value unavailable"else
      if(identical(e$display_label_state,"exact_export_only"))"Value available in the original export"else .brohn_cpv_short(e$value_json)))))
  description<-paste(lane$selected_rows,"original events, drawn at their saved display positions. Repeated simultaneous events can overlap.",lane$missing_selected_values,"event values are unavailable.")
 }else{
  .brohn_cpv_require(identical(lane$mode,"counted_bins")&&length(lane$bins)<=512L,"Use the qualified event count display.")
  high<-max(1,vapply(lane$bins,`[[`,numeric(1),"count"))
  marks<-lapply(lane$bins,function(b){.brohn_cpv_require(is.numeric(b$bin)&&b$bin>=0&&b$bin<=511&&b$bin==floor(b$bin)&&is.numeric(b$count)&&b$count>=1,"Invalid saved event count bin.")
   h<-b$count/high*(bottom-top)
   htmltools::tags$rect(x=x(b$bin/512),y=n(bottom-h),width=n((right-left)/512),height=n(h),fill=colour,
    `data-clock-plot-event-bin`=b$bin,`data-event-count`=b$count,
    htmltools::tags$title(paste(b$count,"original events in time bin",b$bin+1L,"of 512 | first row",b$first$original_row_reference$source_sequence,
      "| last row",b$last$original_row_reference$source_sequence,"|",b$missing_values,"unavailable values. Bin width does not describe a single event's duration.")))})
  description<-paste(lane$selected_rows,"original events counted across",length(lane$bins),"occupied bins of 512 equal time bins. Height is event count, not signal amplitude or event duration.",
    lane$missing_selected_values,"event values are unavailable. All selected events contribute to the counts.")
 }
 htmltools::tags$svg(xmlns="http://www.w3.org/2000/svg",viewBox=paste(0,0,width,height),role="img",focusable="false",
  `aria-labelledby`=paste(paste0(id,"-title"),paste0(id,"-desc")),class="brohn-clock-plot-svg",`data-clock-plot-kind`=kind,
  htmltools::tags$title(id=paste0(id,"-title"),title),htmltools::tags$desc(id=paste0(id,"-desc"),description),grid,marks)
}

brohn_clock_plot_view <- function(plot,id_prefix="clock-plot-view") {
 .brohn_cpv_require(is.list(plot)&&identical(plot$schema,"brohn-clock-plot/0.1")&&plot$status%in%c("available","empty_window","no_supported_numeric_signal")&&
  identical(plot$physical_synchronization,"not_established")&&identical(plot$uncertainty,"unknown")&&identical(plot$scientific_scoring,"not_performed"),
  "Open a qualified complete original-measurement plot.")
 .brohn_cpv_require(is.character(id_prefix)&&length(id_prefix)==1L&&grepl("^[A-Za-z][A-Za-z0-9_-]{0,80}$",id_prefix),"Use a distinct safe clock plot identity.")
 .brohn_cpv_require(length(plot$lanes)<=4L&&length(plot$events)<=2L&&length(plot$axis$ticks)==5L&&
  sum(vapply(plot$lanes,function(l)length(.brohn_cpv_points(l)),integer(1)))<=32768L,"The plot exceeds its qualified presentation bound.")
 tags<-htmltools::tags;coverage<-plot$coverage
 signal_card<-function(lane,index){range<-lane$exact_y_range;counts<-lane$display_counts
  label<-if(isTRUE(range$constant))paste("Constant original value:",range$minimum$value_json,.brohn_cpv_unit(lane))else if(is.null(range$minimum))"No supported numeric observations in this window."else
    paste("Original range:",range$minimum$value_json,"to",range$maximum$value_json,.brohn_cpv_unit(lane))
  tags$article(class="brohn-clock-plot-lane",`data-clock-plot-lane`=lane$track_id,
   tags$h4(.brohn_cpv_name(lane)),tags$p(class="brohn-clock-plot-range",label),
   tags$p(class="brohn-clock-plot-note",paste(counts$numeric_observed,"supported original observations \u00b7",counts$representatives,"representatives \u00b7",length(lane$runs),"continuity runs")),
   if(counts$numeric_observed>0L)brohn_clock_plot_svg(plot,lane,"signal",paste0(id_prefix,"-signal-",index))else tags$p(class="brohn-clock-plot-empty","No signal line is drawn for unavailable values."),
   .brohn_cpv_axis(plot),tags$p(class="brohn-clock-plot-note",paste(counts$saved_missing,"missing values \u00b7",counts$exact_export_only,"values available only in original exports \u00b7",
      length(lane$breaks),"retained breaks. Separate runs are never connected."))) }
 event_card<-function(lane,index)tags$article(class="brohn-clock-plot-lane",`data-clock-plot-lane`=lane$track_id,
  tags$h4(paste(.brohn_cpv_name(lane),"\u00b7 recorded events")),
  tags$p(class="brohn-clock-plot-note",paste(lane$selected_rows,"original events \u00b7",if(identical(lane$mode,"individual"))"individual marks; simultaneous events can overlap"else"counts in 512 equal time bins")),
  if(lane$selected_rows>0L)brohn_clock_plot_svg(plot,lane,"events",paste0(id_prefix,"-events-",index))else tags$p(class="brohn-clock-plot-empty","No original events fall inside this window."),
  .brohn_cpv_axis(plot),tags$p(class="brohn-clock-plot-note",paste(lane$missing_selected_values,"unavailable values \u00b7",lane$exact_export_only_values,"labels available only in original exports.")))
 rows<-c(lapply(plot$lanes,function(l)list(name=.brohn_cpv_name(l),kind="Signal",unit=.brohn_cpv_unit(l),selected=l$display_counts$selected_rows,
  represented=l$display_counts$numeric_observed,missing=l$display_counts$saved_missing,export_only=l$display_counts$exact_export_only,
  min=.brohn_cpv_text(l$exact_y_range$minimum$value_json),max=.brohn_cpv_text(l$exact_y_range$maximum$value_json),
  display=paste(l$display_counts$representatives,"representatives;",length(l$runs),"separate runs"))),
  lapply(plot$events,function(l)list(name=.brohn_cpv_name(l),kind="Events",unit="event count",selected=l$selected_rows,represented=l$selected_rows,
    missing=l$missing_selected_values,export_only=l$exact_export_only_values,min="Not a signal amplitude",max="Not a signal amplitude",
    display=if(identical(l$mode,"individual"))paste(length(l$events),"individual marks")else paste(length(l$bins),"occupied time bins"))))
 summary<-tags$details(tags$summary("Numerical overview and exact time labels"),
  tags$p("This table summarizes every displayed lane. Plot representatives summarize supported signal values; original exports retain every selected observation and its provenance."),
  tags$div(class="brohn-clock-plot-table",tabindex="0",role="region",`aria-label`="Complete lane numerical overview",
   tags$table(tags$caption("Complete selected-window lane counts and original ranges"),
    tags$thead(tags$tr(lapply(c("Recording / channel","Kind","Unit","Selected rows","Represented observations","Unavailable values","Export-only values / labels","Minimum original value","Maximum original value","Display reduction"),function(t)tags$th(scope="col",t)))),
    tags$tbody(lapply(rows,function(row)tags$tr(lapply(row,function(value)tags$td(.brohn_cpv_text(value)))))))),
  tags$p(paste("Exact relative base:",plot$axis$display_base_exact_decimal,"seconds. Original reference start event:",.brohn_cpv_fraction(plot$axis$reference_anchor_seconds),"seconds.")),
  tags$div(class="brohn-clock-plot-table",tabindex="0",role="region",`aria-label`="Exact horizontal axis values",
   tags$table(tags$caption("Horizontal display positions and retained exact seconds"),tags$thead(tags$tr(tags$th(scope="col","Position"),tags$th(scope="col","Displayed offset (approximate seconds)"),tags$th(scope="col","Exact relative seconds"))),
    tags$tbody(lapply(plot$axis$ticks,function(t)tags$tr(tags$td(paste0(.brohn_cpv_position(t$position)*100,"%")),tags$td(.brohn_cpv_text(t$display_offset_label)),tags$td(.brohn_cpv_fraction(t$relative_seconds))))))))
 css<-paste0("#",id_prefix,"{color:#EDF2F2;font-family:system-ui,sans-serif;line-height:1.5;overflow-wrap:anywhere;min-width:0}",
  "#",id_prefix," .brohn-clock-plot-lane{background:#111A21;border:1px solid #34464F;border-radius:12px;padding:16px;margin:16px 0;min-width:0}",
  "#",id_prefix," h3{font-size:1.4rem;line-height:1.3}#",id_prefix," h4{font-size:1.08rem;margin:0 0 8px}",
  "#",id_prefix," p{margin:8px 0}#",id_prefix," .brohn-clock-plot-note{color:#BACAD0;font-size:.9rem}",
  "#",id_prefix," .brohn-clock-plot-range{font-weight:600}#",id_prefix," .brohn-clock-plot-svg{display:block;width:100%;height:auto;min-height:90px;background:#0D151B;border-radius:6px}",
  "#",id_prefix," .brohn-clock-plot-axis{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:8px;font-size:.85rem;margin:4px 5px}",
  "#",id_prefix," .brohn-clock-plot-axis>*:nth-child(2){text-align:center}#",id_prefix," .brohn-clock-plot-axis>*:last-child{text-align:right}",
  "#",id_prefix," code{color:inherit;font-family:ui-monospace,monospace;white-space:normal}#",id_prefix," details{margin:16px 0}#",id_prefix," summary{cursor:pointer;padding:10px 0;font-weight:600}",
  "#",id_prefix," .brohn-clock-plot-table{overflow-x:auto;max-width:100%;margin:12px 0}#",id_prefix," table{border-collapse:collapse;width:100%;font-size:.9rem}",
  "#",id_prefix," th,#",id_prefix," td{padding:9px;border-bottom:1px solid #34464F;text-align:left;vertical-align:top;min-width:100px}",
  "#",id_prefix," caption{text-align:left;font-weight:600;margin-bottom:8px}#",id_prefix," :focus-visible{outline:3px solid #A7E9D3;outline-offset:3px}")
 tags$section(id=id_prefix,`aria-labelledby`=paste0(id_prefix,"-heading"),tags$style(htmltools::HTML(css)),
  tags$h3(id=paste0(id_prefix,"-heading"),tabindex="-1","Original measurements across the complete window"),
  tags$p(paste(coverage$complete_selected_rows_read,"selected original rows \u00b7",coverage$numeric_observations_represented,"supported signal observations \u00b7",
    coverage$signal_representatives,"signal representatives.")),
  if(identical(plot$status,"empty_window"))tags$p(role="status","No original observations fall inside this window. No zero-valued signal is substituted.")else
   if(identical(plot$status,"no_supported_numeric_signal"))tags$p(role="status","This window has no supported numeric signal observations. Recorded events and unavailable-value counts remain visible."),
  tags$p(class="brohn-clock-plot-note","All lanes share the displayed time window. Signal lanes have separate original units and value scales; their heights cannot be compared as a common amplitude. Connections are display guides, never interpolated measurements."),
  lapply(seq_along(plot$lanes),function(i)signal_card(plot$lanes[[i]],i)),lapply(seq_along(plot$events),function(i)event_card(plot$events[[i]],i)),
  tags$p(paste(coverage$complete_unplaced_rows_read,"whole-source rows have no placeable original time. They receive no invented plot position; their original export remains available.")),
  tags$p(class="brohn-clock-plot-note","The reviewed mapping does not establish physical synchronization. Timing uncertainty is unknown. No scientific score is calculated by this overview."),summary)
}
