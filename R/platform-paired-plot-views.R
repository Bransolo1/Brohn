# Source-bound paired displays; saved inference is never recalculated here.
.brohn_pp_reason <- function(reason) switch(brohn_default(reason,""),
  complete_source_disagrees_with_saved_comparison="Complete source observations do not reproduce the saved person differences and support counts. No pairs are drawn; preserve the report and review its original analysis.",
  duplicate_or_ambiguous_observation_identity="More than one eligible source record has the same person, visit, condition and observation identity. Pairing is ambiguous.",
  complete_observation_identity_unavailable="Complete exposure or assessment identities are missing. A source row number cannot create an observation identity.",
  paired_person_or_visit_identity_unavailable="An eligible record has no complete person and visit identity.",
  complete_observations_unavailable="The complete source observations behind this saved comparison are unavailable.",
  saved_person_differences_unavailable="The saved result lacks complete person differences needed to verify this plot.",
  unsupported_saved_comparison_recipe="This saved comparison has no registered paired-visual adapter.",
  if(exists(".brohn_contrast_reason",mode="function")) .brohn_contrast_reason(reason) else gsub("_"," ",brohn_default(reason,"Unavailable")))
brohn_paired_plot_svg <- function(model,page=1L,chart="means",width=680L) {
  brohn_require(identical(model$status,"verified")&&chart %in% c("means","differences")&&width %in% c(320L,680L),"Choose a verified paired-result figure.")
  selected<-brohn_paired_plot_page(model,page);rows<-selected$rows;c<-model$saved_contrast
  means<-chart=="means";height<-if(means)370L else max(220L,130L+24L*length(rows));top<-44;bottom<-if(means)272 else height-86
  left<-if(means)68 else 58;right<-width-24
  all_values<-unlist(lapply(model$people,function(p)if(means)c(p$control_mean,p$test_mean)else p$difference))
  domain<-range(c(all_values,if(!means)c(0,c$estimate,c$interval95$lower,c$interval95$upper)))
  if(diff(domain)==0)domain<-domain+c(-1,1)*max(1,abs(domain[[1L]])*.1)
  pad<-diff(domain)*.08;domain<-domain+c(-pad,pad)
  scale<-function(v)if(means)bottom-(v-domain[[1L]])/diff(domain)*(bottom-top)else left+(v-domain[[1L]])/diff(domain)*(right-left)
  n<-function(x)sprintf("%.3f",x);short<-function(x)format(signif(x,4),trim=TRUE,scientific=abs(x)>=1e6||(x!=0&&abs(x)<.001))
  title<-if(means)"Paired condition means"else"Person differences and saved uncertainty"
  id<-paste0("pp-",substr(brohn_hash(list(model$report_hash,model$id,page,chart,width)),1,20))
  text<-function(x,y,label,...)shiny::tags$text(x=n(x),y=n(y),fill="#edf2f2",`font-size`=12,...,label)
  ticks<-pretty(domain,n=3);ticks<-ticks[ticks>=domain[[1L]]&ticks<=domain[[2L]]]
  metadata<-list(schema="brohn-paired-figure/1.0",report_id=model$report_id,report_hash=model$report_hash,source_hash=model$source_hash,
    comparison_id=model$id,chart=chart,page=page,pages=selected$pages,total_people=selected$total,domain=as.list(domain),
    people=rows,saved_estimate=c$estimate,saved_interval95=c$interval95,unit=c$unit,aggregation=c$aggregation)
  shiny::tags$svg(xmlns="http://www.w3.org/2000/svg",viewBox=paste(0,0,width,height),role="img",focusable="false",
    `aria-labelledby`=paste(id,paste0(id,"-desc")),style="display:block;width:100%;height:auto;background:#11171c;border-radius:8px;font-family:system-ui,sans-serif",
    shiny::tags$title(id=id,title),shiny::tags$desc(id=paste0(id,"-desc"),paste("Page",page,"of",selected$pages,"showing",length(rows),"of",selected$total,"paired people.",
      if(means)"Each line joins one person's control and test means using only paired visits. Control circles are hollow; test diamonds are filled."else
        "Each circle is one person's saved test-minus-control difference. The separate bottom diamond and interval are the full saved comparison, including people on other pages.",
      "Units:",c$unit,".",model$interpretation,"Report SHA-256:",model$report_hash)),
    shiny::tags$metadata(brohn_json(metadata)),text(width/2,22,if(means)"Paired condition means"else"Test minus control",`text-anchor`="middle"),
    if(means)shiny::tagList(
      lapply(ticks,function(v)shiny::tagList(shiny::tags$line(x1=left,x2=right,y1=n(scale(v)),y2=n(scale(v)),stroke="#415057"),text(left-8,scale(v)+4,short(v),`text-anchor`="end"))),
      lapply(seq_along(rows),function(i){p<-rows[[i]];x1<-left+22;x2<-right-22;y1<-scale(p$control_mean);y2<-scale(p$test_mean)
        tip<-paste(p$participant_id,"| Control",.brohn_pp_num(p$control_mean),"| Test",.brohn_pp_num(p$test_mean),"| Difference",.brohn_pp_num(p$difference),c$unit,"|",p$paired_sessions,"paired visits")
        shiny::tags$g(`data-person`=p$participant_id,shiny::tags$title(tip),
          shiny::tags$line(x1=x1,x2=x2,y1=n(y1),y2=n(y2),stroke="#8297a0",`stroke-width`=1.2),
          shiny::tags$circle(cx=x1,cy=n(y1),r=3.5,fill="#11171c",stroke="#a7e9d3",`stroke-width`=1.8),
          shiny::tags$path(d=paste("M",x2,n(y2-4),"L",x2+4,n(y2),x2,n(y2+4),x2-4,n(y2),"Z"),fill="#a7e9d3"))}),
      text(left+22,bottom+25,"Control",`text-anchor`="middle"),text(right-22,bottom+25,"Test",`text-anchor`="middle"),
      text(width/2,327,c$unit,`text-anchor`="middle"),text(width/2,351,"Equal paired visits within each person",`text-anchor`="middle"))else shiny::tagList(
      lapply(ticks,function(v)shiny::tagList(shiny::tags$line(x1=n(scale(v)),x2=n(scale(v)),y1=top-10,y2=bottom+31,stroke=if(v==0)"#b7c4c9"else"#415057"),text(scale(v),bottom+53,short(v),`text-anchor`="middle"))),
      lapply(seq_along(rows),function(i){p<-rows[[i]];y<-top+(i-1)*24
        shiny::tagList(text(left-8,y+4,as.character((page-1L)*50L+i),`text-anchor`="end"),shiny::tags$circle(`data-person`=p$participant_id,
          cx=n(scale(p$difference)),cy=y,r=3.5,fill="#a7e9d3",shiny::tags$title(paste(p$participant_id,.brohn_pp_num(p$difference),c$unit,p$paired_sessions,"paired visits"))))}),
      text(left-8,bottom+28,"All",`text-anchor`="end"),
      if(!is.null(c$interval95))shiny::tags$line(x1=n(scale(c$interval95$lower)),x2=n(scale(c$interval95$upper)),y1=bottom+24,y2=bottom+24,stroke="#f4c67a",`stroke-width`=3,
        shiny::tags$title(paste(c$interval95$method,.brohn_pp_num(c$interval95$lower),"to",.brohn_pp_num(c$interval95$upper),c$unit))),
      shiny::tags$path(d=paste("M",n(scale(c$estimate)),bottom+19,"L",n(scale(c$estimate)+5),bottom+24,n(scale(c$estimate)),bottom+29,n(scale(c$estimate)-5),bottom+24,"Z"),fill="#f4c67a",
        shiny::tags$title(paste("Saved equal-person estimate",.brohn_pp_num(c$estimate),c$unit))),
      text(width/2,height-8,c$unit,`text-anchor`="middle")))
}
.brohn_pp_figure <- function(model,page,chart)shiny::tagList(
  shiny::div(class="brohn-signal-wide",brohn_paired_plot_svg(model,page,chart,680L)),
  shiny::div(class="brohn-signal-compact",brohn_paired_plot_svg(model,page,chart,320L)))
.brohn_pp_view_ui <- function(model,people_page=1L,table_kind="people",table_page=1L) {
  if(table_kind=="people")table_page<-people_page
  c<-model$saved_contrast;selected<-brohn_paired_plot_page(model,table_page,table_kind)
  exact<-lapply(selected$rows,function(r)lapply(r,function(v)if(is.numeric(v)&&length(v)==1L).brohn_pp_num(v)else v))
  columns<-switch(table_kind,people=c("participant_id","control_mean","test_mean","difference","unit","paired_sessions"),
    sessions=c("participant_id","session_id","control_mean","test_mean","difference","unit","control_observations","test_observations","unavailable_observations","paired","reason"),
    observations=c("source_index","source_report_id","participant_id","session_id","observation_id","condition_id","value","unit","eligible","missing_reason"))
  brohn_card(title="People behind this comparison",subtitle=paste(model$label,model$condition_label,sep=" | "),
    shiny::p(paste("Collection origin:",model$origin,"| Saved equal-person estimate:",.brohn_pp_num(c$estimate),c$unit)),
    shiny::p(paste(c$participant_count,"paired people;",c$paired_session_count,"paired visits;",c$excluded_session_count,"visits excluded by the saved method.")),
    if(!is.null(c$interval95))shiny::p(paste("Saved 95% interval (rounded):",format(signif(c$interval95$lower,6),trim=TRUE),"to",format(signif(c$interval95$upper,6),trim=TRUE),c$unit,". Exact values and method are in Source identity below."))else shiny::p("No saved confidence interval is available. No interval has been added."),
    if(!is.null(c$multiplicity))shiny::p(paste("Saved adjusted p:",.brohn_pp_num(c$p_adjusted),"|",gsub("_"," ",c$multiplicity$method),"| declared family",c$multiplicity$family_size,". Multiplicity adjustment applies to saved p-values, not these intervals.")),
    if(model$status=="verified")shiny::tagList(shiny::h3("Paired condition means"),
      shiny::p(paste("Control:",c$control_label,"| Test:",c$test_label,". One line per person, averaging only visits with both conditions.")),
      shiny::p(paste("Figure page",people_page,"of",max(1L,ceiling(length(model$people)/50L)),". Figures and people table share this page; axis bounds use all paired people.")),
      .brohn_pp_figure(model,people_page,"means"),shiny::h3("Person differences and saved uncertainty"),.brohn_pp_figure(model,people_page,"differences"),
      shiny::p("Numbered rows follow this page's people table. All marks the full saved estimate and interval, including people on other pages."))else
        shiny::div(class="brohn-alert",role="status",.brohn_pp_reason(model$reason)),
    shiny::h3("Exact numerical evidence"),shiny::p(paste("Table page",selected$page,"of",selected$pages,"|",selected$total,table_kind,". Missing is unavailable, never zero. All numerical cells preserve round-trip double precision.")),
    brohn_table(exact,columns=columns,maximum=50L,label="Exact paired comparison evidence"),
    shiny::tags$details(shiny::tags$summary("Source identity, support and interpretation"),
      shiny::p(c$aggregation),shiny::p(model$interpretation),
      if(!is.null(c$interval95))shiny::p(paste("Exact saved 95% interval:",.brohn_pp_num(c$interval95$lower),"to",.brohn_pp_num(c$interval95$upper),c$unit,".",c$interval95$method)),
      shiny::p(paste("Report SHA-256:",model$report_hash)),shiny::p(paste("Complete analysis and provenance SHA-256:",model$source_hash)),
      shiny::p(paste("Selected source reports:",paste(unlist(model$source_report_ids),collapse=", "))),
      shiny::p("Source rows include typed missing reasons and original records in the full exports. Person identifiers are the report's declared or reviewed linkage; the plot does not independently verify identity. Different modalities keep their own eligible people and units."),
      shiny::p("Values and condition lines do not establish device timing, synchronization, a validated psychological construct or a clinically qualified effect."),
      shiny::tags$pre(brohn_json(list(saved_contrast=c,artifact=model$artifact),TRUE))))
}
brohn_paired_plot_explorer_ui <- function(record) {
  if(!.brohn_pp_supported(record$body))return(NULL)
  shiny::tagList(brohn_card(title="Review paired results",subtitle="See the people, repeat visits and missing observations behind a saved condition comparison.",
    brohn_command("Open paired results","open_paired_plots",list(report_id=record$id,revision=record$revision,report_hash=brohn_hash(record$body),project_id=record$project_id),id="paired-plots-open")),
    shiny::uiOutput("paired_plot_error"),shiny::uiOutput("paired_plot_progress"),shiny::uiOutput("paired_plot_sources"),shiny::uiOutput("paired_plot_comparisons"),
    shiny::uiOutput("paired_plot_controls"),shiny::uiOutput("paired_plot_view"))
}
brohn_install_paired_plots <- function(input,output,session,store,state,attempt,prepare_download) {
  opened<-shiny::reactiveVal(NULL);model<-shiny::reactiveVal(NULL);problem<-shiny::reactiveVal(NULL)
  pending<-shiny::reactiveVal(NULL);links<-shiny::reactiveVal(NULL);retained<-new.env(parent=emptyenv());retained$handle<-NULL;retained$exports<-NULL
  cancel<-function(){p<-shiny::isolate(pending());pending(NULL);if(!is.null(p)).brohn_pp_async_release(p$handle)}
  clear_model<-function(){model(NULL);links(NULL);.brohn_pp_async_release(retained$handle);retained$handle<-NULL;retained$exports<-NULL}
  close<-function(){cancel();opened(NULL);clear_model()};session$onSessionEnded(close)
  shiny::observeEvent(list(state$page,state$report_id),{o<-opened();if(!is.null(o)&&(!identical(state$page,"report")||!identical(state$report_id,o$record$id))){close();problem(NULL)}},priority=100,ignoreInit=FALSE)
  guard<-function(){o<-opened();brohn_require(!is.null(o)&&identical(state$page,"report")&&identical(state$report_id,o$record$id),"Reopen this saved report's paired results.")
    tryCatch(brohn_paired_plot_check(store,o),error=function(e){close();problem(conditionMessage(e));stop(e)});o}
  handle<-function(fn)attempt(function(){problem(NULL);tryCatch(fn(),error=function(e){problem(conditionMessage(e));stop(e)})})
  shiny::observeEvent(input$open_paired_plots,handle(function(){c<-input$open_paired_plots
    brohn_require(identical(state$page,"report")&&identical(state$report_id,c$report_id),"Open the exact saved report before reviewing paired results.")
    close();pending(list(handle=.brohn_pp_async_start(store,"open",list(report_id=c$report_id,revision=c$revision,report_hash=c$report_hash,project_id=c$project_id)),report_id=c$report_id))
  }))
  output$paired_plot_error<-shiny::renderUI({if(!is.null(problem()))shiny::div(class="brohn-alert",role="alert",problem())})
  output$paired_plot_progress<-shiny::renderUI({p<-pending();if(!is.null(p))shiny::div(role="status",
    shiny::p(if(p$handle$operation=="open")"Verifying the complete saved report in the background."else"Preparing complete paired observations and exports in the background. Your saved report remains available."),
    shiny::actionButton("paired_plot_cancel","Cancel paired preparation"))})
  shiny::observeEvent(input$paired_plot_cancel,{cancel();problem("Paired preparation cancelled. The saved report is unchanged. Open paired results or review the selected observations to retry.")})
  output$paired_plot_sources<-shiny::renderUI({o<-opened();shiny::req(o)
    if(!length(o$catalog))return(shiny::p("The complete saved report has no condition comparisons. Declare a comparison in the study and analyse it explicitly."))
    sources<-o$catalog[!duplicated(vapply(o$catalog,`[[`,character(1),"source_id"))]
    brohn_card(title="Choose a saved measure",shiny::selectInput("paired_plot_source","Source measure",stats::setNames(vapply(sources,`[[`,character(1),"source_id"),vapply(sources,`[[`,character(1),"source_label")),selectize=FALSE),
      shiny::tags$input(id="paired_plot_catalog_identity",type="text",class="shiny-input-text",value=o$report_hash,style="display:none",tabindex="-1",`aria-hidden`="true"))})
  output$paired_plot_comparisons<-shiny::renderUI({o<-opened();shiny::req(o,input$paired_plot_source)
    choices<-Filter(function(c)identical(c$source_id,input$paired_plot_source),o$catalog);shiny::req(length(choices)>0L)
    brohn_card(title="Choose saved conditions",shiny::selectInput("paired_plot_comparison","Condition comparison",stats::setNames(vapply(choices,`[[`,character(1),"id"),vapply(choices,`[[`,character(1),"condition_label")),selectize=FALSE),
      shiny::actionButton("paired_plot_load","Review paired observations"),shiny::p("Only comparisons already saved by the analysis are available. Changing a selection clears the previous plot."))})
  shiny::observeEvent(list(input$paired_plot_source,input$paired_plot_comparison),{p<-pending();if(!is.null(p)&&p$handle$operation=="load")cancel();clear_model()},priority=100,ignoreInit=TRUE)
  shiny::observeEvent(input$paired_plot_load,handle(function(){o<-guard();cancel();clear_model()
    brohn_require(identical(input$paired_plot_catalog_identity,o$report_hash),"Wait for this report's current source controls.")
    c<-brohn_find(o$catalog,input$paired_plot_comparison);brohn_require(!is.null(c)&&identical(c$source_id,input$paired_plot_source),"Choose conditions belonging to the current source measure.")
    pending(list(handle=.brohn_pp_async_start(store,"load",list(opened=o,comparison_id=c$id)),report_id=o$record$id,source_id=c$source_id,comparison_id=c$id))
  }))
  shiny::observe({p<-pending();if(is.null(p))return();shiny::invalidateLater(200,session)
    tryCatch(shiny::isolate({
      brohn_require(identical(state$page,"report")&&identical(state$report_id,p$report_id),"Reopen the selected saved report.")
      result<-.brohn_pp_async_poll(p$handle);if(is.null(result))return()
      if(p$handle$operation=="open") {
        brohn_paired_plot_check(store,result$value);opened(result$value);pending(NULL);.brohn_pp_async_release(p$handle)
      } else {
        guard();brohn_require(identical(input$paired_plot_source,p$source_id)&&identical(input$paired_plot_comparison,p$comparison_id),"The paired selection changed during preparation.")
        retained$handle<-p$handle;retained$exports<-result$exports;pending(NULL)
        m<-result$value;m$download_token<-brohn_id("paired-export");model(m)
      }
    }),error=function(e){cancel();clear_model();problem(conditionMessage(e))})
  })
  current<-shiny::reactive({m<-model();shiny::req(m,identical(m$source_id,input$paired_plot_source),identical(m$id,input$paired_plot_comparison));guard();m})
  output$paired_plot_controls<-shiny::renderUI({m<-current();urls<-links();shiny::req(urls)
    brohn_card(title="Evidence and downloads",
      if(m$status=="verified")shiny::numericInput("paired_plot_people_page","Figure page (50 paired people)",1,min=1,max=max(1L,ceiling(length(m$people)/50L)),step=1),
      shiny::selectInput("paired_plot_table","Numerical evidence",c("People"="people","Visits, including unpaired visits"="sessions","Complete selected source observations"="observations"),selectize=FALSE),
      shiny::conditionalPanel("input.paired_plot_table !== 'people'",shiny::numericInput("paired_plot_table_page","Evidence table page (50 records)",1,min=1,step=1)),
      shiny::div(class="brohn-toolbar",if(m$status=="verified")shiny::tagList(shiny::tags$a(class="btn btn-default",href=urls$means,download="paired-means.svg","Download paired means SVG"),shiny::tags$a(class="btn btn-default",href=urls$differences,download="person-differences.svg","Download person differences SVG")),
        shiny::tags$a(class="btn btn-default",href=urls$csv,download="paired-evidence.csv","Download all paired evidence CSV"),shiny::tags$a(class="btn btn-default",href=urls$json,download="paired-source.json","Download paired source and provenance")))})
  people_page<-function(m)min(brohn_default(input$paired_plot_people_page,1L),max(1L,ceiling(length(m$people)/50L)))
  output$paired_plot_view<-shiny::renderUI({tryCatch({m<-current();kind<-brohn_default(input$paired_plot_table,"people");page<-min(brohn_default(input$paired_plot_table_page,1L),max(1L,ceiling(length(m[[kind]])/50L)))
    .brohn_pp_view_ui(m,people_page(m),kind,page)},error=function(e){if(inherits(e,"shiny.silent.error"))stop(e);shiny::div(class="brohn-alert",role="alert",conditionMessage(e))})})
  # Fixed resource slots plus exact opening tokens revoke old URLs. CSV/JSON
  # stream files prepared off-session; a bounded figure is rendered on demand.
  shiny::observeEvent(model(),{m<-model();shiny::req(m);urls<-list()
    for(kind in c("json","csv","means","differences")) {
      uri<-session$registerDataObj(paste0("brohn-paired-",kind),list(token=m$download_token,kind=kind),function(data,req)shiny::isolate(tryCatch({
        brohn_require(req$REQUEST_METHOD %in% c("GET","HEAD")&&identical(shiny::parseQueryString(brohn_default(req$QUERY_STRING,""))$paired_key,data$token),"This paired export link is no longer active.")
        v<-current();brohn_require(identical(v$download_token,data$token),"Reopen the current paired selection.");guard()
        if(data$kind %in% c("json","csv")) {
          ref<-retained$exports[[data$kind]];brohn_require(!is.null(ref)&&file.exists(ref$path)&&identical(as.numeric(file.info(ref$path)$size),ref$size)&&identical(digest::digest(file=ref$path,algo="sha256"),ref$hash),"The prepared paired evidence is unavailable.")
          content<-list(file=ref$path,owned=FALSE);type<-if(data$kind=="json")"application/json"else"text/csv";suffix<-paste0("paired-evidence.",data$kind)
        }else{content<-enc2utf8(as.character(brohn_paired_plot_svg(v,people_page(v),data$kind)));type<-"image/svg+xml";suffix<-paste0("paired-",data$kind,"-page-",people_page(v),".svg")}
        structure(list(status=200L,content_type=type,content=content,headers=list("Content-Disposition"=paste0('attachment; filename="',v$report_id,'-',suffix,'"'),"Cache-Control"="no-store","X-Content-Type-Options"="nosniff")),class="httpResponse")
      },error=function(e)structure(list(status=404L,content_type="text/plain",content="This exact paired export is unavailable. Reopen its saved report and current selection."),class="httpResponse"))))
      urls[[kind]]<-paste0(uri,"&paired_key=",m$download_token)
    }
    links(urls)
  },ignoreNULL=TRUE,priority=50)
  invisible(list(opened=opened,model=model,current=current,guard=guard))
}
