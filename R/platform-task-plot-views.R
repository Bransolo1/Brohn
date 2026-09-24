# Responsive SVGs use complete selected arrays, never a table preview.
.brohn_tp_gnat <- function(view) identical(view$model$kind,"trials")&&identical(view$model$profile,"gnat-brohn-single-target/1.0")
.brohn_tp_gnat_outcomes <- function(view,width) {
  states<-c("hit","miss","false_alarm","correct_rejection","interrupted","not_presented","absent_source")
  labels<-c("Hit","Miss","False alarm","Correct rejection","Interrupted","Not presented","Absent source")
  colours<-c("#a7e9d3","#f4c67a","#f4c67a","#a7e9d3","#eaa8c4","#b7c4c9","#b7c4c9")
  height<-390L;left<-113;right<-width-18;top<-55;bottom<-283
  sx<-function(p)left+(p-1)/max(1,length(view$model$rows)-1)*(right-left)
  sy<-function(state)top+(match(state,states)-1)*(bottom-top)/6
  number<-function(x)formatC(x,format="f",digits=3,decimal.mark=".")
  text<-function(x,y,label,...)shiny::tags$text(x=number(x),y=number(y),fill="#edf2f2",`font-size`=12,...,label)
  id<-paste0("tp-gnat-",substr(brohn_hash(list(view$model$source_hash,view$scope,width)),1,18))
  shiny::tags$svg(xmlns="http://www.w3.org/2000/svg",viewBox=paste(0,0,width,height),role="img",focusable="false",
    `aria-labelledby`=paste(id,paste0(id,"-desc")),style="display:block;width:100%;height:auto;max-width:100%;background:#11171c;border-radius:8px;font-family:system-ui,sans-serif",
    shiny::tags$title(id=id,"Go/No-Go outcomes in frozen trial order"),
    shiny::tags$desc(id=paste0(id,"-desc"),paste(length(view$rows),"selected positions.",paste(vapply(view$outcome_counts,function(c)paste(gsub("_"," ",c$outcome),c$count),character(1)),collapse="; "),
      "Correct rejections and misses retain observed withholding with no response latency. Interrupted, unpresented and absent source positions occupy separate rows. No score is recalculated.")),
    text(width/2,22,"Go / No-Go outcomes",`text-anchor`="middle"),
    lapply(seq_along(states),function(i)shiny::tagList(shiny::tags$line(x1=left,x2=right,y1=number(sy(states[[i]])),y2=number(sy(states[[i]])),stroke="#415057"),
      text(left-7,sy(states[[i]])+4,labels[[i]],`text-anchor`="end"))),
    lapply(view$rows,function(r){k<-match(r$outcome_state,states);brohn_require(!is.na(k),"A saved GNAT position needs an explicit outcome or source-support state.")
      title<-paste("Trial",r$position,r$trial_id,"|",labels[[k]],"|",r$phase,brohn_default(r$cell_id,"training"),"|",r$expected_action,
        "|",if(isTRUE(r$profile_scored))"Test position"else"Training or practice", "|",r$disposition)
      shiny::tags$circle(cx=number(sx(r$position)),cy=number(sy(r$outcome_state)),r=2.5,fill=if(isTRUE(r$profile_scored))colours[[k]]else"none",stroke=colours[[k]],shiny::tags$title(title))}),
    lapply(unique(round(seq(1,max(2,length(view$model$rows)),length.out=3))),function(p)text(sx(p),310,p,`text-anchor`="middle")),
    text((left+right)/2,333,"Frozen trial position",`text-anchor`="middle"),
    text(width/2,356,"Filled = test; hollow = training / practice",`text-anchor`="middle"),
    text(width/2,376,"Withholding is observed, not missing data",`text-anchor`="middle"))
}
brohn_task_plot_svg <- function(view,chart="chronology",width=680L) {
  brohn_require(chart %in% c("chronology","distribution","outcomes")&&width %in% c(320L,680L),"Choose a supported task figure.")
  gnat<-.brohn_tp_gnat(view)
  if(identical(chart,"outcomes")){brohn_require(gnat,"Outcome lanes are available for the saved GNAT procedure.");return(.brohn_tp_gnat_outcomes(view,width))}
  people<-view$model$kind=="people";histogram<-!people&&chart=="distribution"
  height<-390L;left<-65;right<-width-18;top<-38;bottom<-258
  values<-view$values;finite<-values[is.finite(values)]
  xr<-if(histogram&&length(view$bins))range(unlist(lapply(view$bins,function(b)c(b$lower_ms,b$upper_ms))))else c(1,max(2,length(view$model$rows)))
  yr<-if(histogram)c(0,max(1,vapply(view$bins,`[[`,numeric(1),"count")))else if(people&&view$unit=="proportion")c(0,1)else range(c(0,finite))
  if(diff(xr)==0)xr<-xr+c(-.5,.5)
  if(diff(yr)==0)yr<-if(people&&(identical(view$unit,"D")||identical(view$model$metric,"keyboard_aat_relative_approach_advantage")))c(-1,1)else c(0,1)
  sx<-function(x)left+(x-xr[[1L]])/diff(xr)*(right-left);sy<-function(y)bottom-(y-yr[[1L]])/diff(yr)*(bottom-top)
  n<-function(x)formatC(x,format="f",digits=3,decimal.mark=".")
  title<-paste(if(histogram)"Latency distribution"else if(people)"Person outcomes"else"Trial chronology",view$label,sep=" | ")
  id<-paste0("tp-",substr(brohn_hash(list(view$model$source_hash,view$measure,view$scope,chart,width)),1,18))
  text<-function(x,y,label,...)shiny::tags$text(x=n(x),y=n(y),fill="#edf2f2",`font-size`=12,...,label)
  yt<-pretty(yr,n=3);yt<-yt[yt>=yr[[1L]]&yt<=yr[[2L]]]
  xt<-if(histogram)seq(xr[[1L]],xr[[2L]],length.out=3)else unique(round(seq(xr[[1L]],xr[[2L]],length.out=3)))
  marks<-if(histogram)lapply(view$bins,function(b)shiny::tags$rect(x=n(sx(b$lower_ms)),y=n(sy(b$count)),
    width=n(max(.1,sx(b$upper_ms)-sx(b$lower_ms)-1)),height=n(bottom-sy(b$count)),fill="#a7e9d3",
    shiny::tags$title(paste(.brohn_tp_num(b$lower_ms),"to",.brohn_tp_num(b$upper_ms),"ms:",b$count,"recorded values")))) else
    lapply(seq_along(view$rows),function(i){r<-view$rows[[i]];v<-values[[i]];x<-sx(r$position);y<-if(is.finite(v))sy(v)else bottom+20
      wrong<-!people&&!is.null(r$response_code)&&!isTRUE(r$first_correct);missing<-!is.finite(v)
      withheld<-gnat&&isTRUE(r$withholding_observed)
      label<-paste(if(people)r$person_id else r$trial_id,"|",view$label,if(withheld)"withheld; no response time"else if(missing)"unavailable"else paste(.brohn_tp_num(v),view$unit),
        if(!people)paste("|",brohn_default(r$outcome,"missing source"),"|",r$disposition))
      colour<-if(!people&&!isTRUE(r$profile_scored))"#b7c4c9"else if(wrong)"#f4c67a"else "#a7e9d3"
      if(withheld)shiny::tags$line(x1=n(x-2.5),x2=n(x+2.5),y1=n(y),y2=n(y),stroke=colour,`stroke-width`=2,shiny::tags$title(label))else if(missing)shiny::tags$rect(x=n(x-2.5),y=n(y-2.5),width=5,height=5,fill="none",stroke=colour,shiny::tags$title(label))else if(wrong)
        shiny::tags$path(d=paste("M",n(x),n(y-3.5),"L",n(x+3.5),n(y),n(x),n(y+3.5),n(x-3.5),n(y),"Z"),fill=colour,shiny::tags$title(label))else
        shiny::tags$circle(cx=n(x),cy=n(y),r=2.7,fill=if(!people&&!isTRUE(r$profile_scored))"none"else colour,stroke=colour,shiny::tags$title(label))})
  shiny::tags$svg(xmlns="http://www.w3.org/2000/svg",viewBox=paste(0,0,width,height),role="img",focusable="false",
    `aria-labelledby`=paste(id,paste0(id,"-desc")),style="display:block;width:100%;height:auto;max-width:100%;background:#11171c;border-radius:8px;font-family:system-ui,sans-serif",
    shiny::tags$title(id=id,title),shiny::tags$desc(id=paste0(id,"-desc"),paste(view$available,"available values;",if(gnat)paste(view$withheld,"observed withholding without latency;"),view$missing,"unavailable out of",length(view$rows),
      "selected positions. Every selected finite value is represented. Unavailable values are not zero. Numerical alternatives and complete source download accompany this chart. Report",view$model$report_hash,"source",view$model$source_hash)),
    text(width/2,20,view$label,`text-anchor`="middle"),
    lapply(yt,function(t)shiny::tagList(shiny::tags$line(x1=left,x2=right,y1=n(sy(t)),y2=n(sy(t)),stroke="#415057"),text(left-8,sy(t)+4,.brohn_tp_num(t),`text-anchor`="end"))),
    lapply(xt,function(t)text(sx(t),bottom+44,.brohn_tp_num(t),`text-anchor`="middle")),marks,
    text((left+right)/2,326,if(histogram)"Recorded latency (ms)"else if(people)"Person index (saved order)"else"Frozen trial position",`text-anchor`="middle"),
    text(width/2,353,if(histogram)paste(view$available,"values in 20 equal-width bins")else if(people)"One dot per person; square = unavailable"else if(gnat)"Circle = hit; diamond = false alarm"else"Circle = correct first; diamond = wrong first",`text-anchor`="middle"),
    if(!histogram&&!people)text(width/2,373,if(gnat)"Dash = withheld; square = unavailable"else"Grey = non-scoring position; square = unavailable",`text-anchor`="middle"),
    shiny::tags$text(x=17,y=(top+bottom)/2,transform=paste0("rotate(-90 17 ",(top+bottom)/2,")"),fill="#edf2f2",`font-size`=12,`text-anchor`="middle",
      if(histogram)"Recorded values"else view$unit))
}
.brohn_tp_figure <- function(view,chart)shiny::div(class="brohn-task-figure",
  shiny::div(class="brohn-signal-wide",brohn_task_plot_svg(view,chart,680L)),
  shiny::div(class="brohn-signal-compact",brohn_task_plot_svg(view,chart,320L)))
.brohn_tp_view_ui <- function(view,page=1L) {
  m<-view$model;people<-m$kind=="people";gnat<-.brohn_tp_gnat(view);pages<-max(1L,ceiling(length(view$rows)/50L))
  brohn_require(brohn_number(page,1,pages,TRUE),"Choose an available numerical page.")
  rows<-if(length(view$rows))view$rows[seq.int((page-1L)*50L+1L,min(length(view$rows),page*50L))]else list()
  brohn_card(title=if(people)"People behind this measure"else"Responses across this administration",subtitle=m$label,
    shiny::p(paste("Collection:",m$origin,"| Materials:",m$material_origin,"| Evidence:",gsub("_"," ",m$evidence_level))),
    shiny::p(if(gnat)paste(view$available,"actual Space-response latencies;",view$withheld,"observed withheld responses with no latency;",view$missing,
      "unavailable latencies among",length(view$rows),"selected positions of",length(m$rows),"expected. Administration:",m$completion)else
      if(people&&is.null(m$summary$selected_person_count))"Person-level values are unavailable because reviewed person/session linkage is incomplete."else
      paste(view$available,"available",if(people)"person values"else"recorded latencies","and",view$missing,"unavailable among",length(view$rows),
        if(people)"selected people for this measure."else paste("selected positions of",length(m$rows),"expected. Administration:",m$completion))),
    if(people)shiny::tagList(shiny::p(paste("Saved equal-person mean:",.brohn_tp_num(m$summary$mean),m$unit,".",brohn_default(m$summary$reason,""))),
      shiny::p(paste(m$summary$eligible_attempt_count,"eligible administrations and",brohn_default(m$summary$contributing_session_count,0),"contributing sessions for this measure.")),
      shiny::p(paste("Repeat policy:",if(m$repeat_policy=="one_selected_attempt_per_person")"One selected administration per person."else"Equal eligible administrations within sessions, then equal sessions within people.")),
      shiny::p("Each dot is one saved person-level value. No trials are pooled. People without this measure remain unavailable. No confidence interval or hypothesis test is added."))else
      shiny::tagList(shiny::p(paste("Showing",view$label,"from the original record.",if(view$scope=="scored")"Only profile-scored positions are selected."else"All expected positions, including practice and other unscored positions, are selected.")),
        if(!isTRUE(m$timing$definition_known))shiny::p(class="brohn-alert",role="status","The source timing or terminal-response definition is unknown. These are declared numbers; no qualified response-time interpretation or new score is supplied.")),
    if(gnat)shiny::tagList(shiny::h3("Go/No-Go outcome chronology"),.brohn_tp_figure(view,"outcomes"),
      shiny::p("A hit is Space for a Go word; a false alarm is Space for a No-Go word. Withholding for a Go word is a miss, and withholding for a No-Go word is a correct rejection. Neither withholding outcome has a response time."),
      brohn_table(lapply(view$outcome_counts,function(c)list(Outcome=gsub("_"," ",c$outcome),Positions=c$count)),maximum=7L,label="Complete selected GNAT outcome counts")),
    shiny::h3(if(people)"Individual values"else if(gnat)"Actual Space responses"else"Trial chronology"),
    if(length(view$rows)).brohn_tp_figure(view,"chronology")else shiny::p(brohn_default(m$summary$reason,"No source positions are available.")),
    if(!people)shiny::tags$details(shiny::tags$summary("Read the trial markers and scoring boundaries"),
      shiny::p(if(gnat)"Circles mark hits and diamonds mark false alarms. Dashes below the latency axis mark observed withholding, with no fabricated response time. Squares identify unavailable latency. Interrupted responses retain their original provisional value and separate interruption outcome; they are not completed-trial accuracy. Grey marks are training or practice. The outcome chart keeps interrupted, unpresented and absent evidence separate."else
        "Circles mark correct first responses; diamonds mark a wrong first response, including later corrections. Grey markers indicate positions outside the scoring plan, such as practice or warm-up. A coloured point can still be excluded from scoring; inspect its disposition below. Squares below the axis mark unavailable latency, including omissions and absent source rows; they are not zero."),
      shiny::p("Plot inclusion does not establish scoring inclusion. Out-of-window values remain visible; the separate disposition and scoring-latency fields retain exclusion, correction and clipping evidence.")),
    if(!people)shiny::tagList(shiny::h3("Latency distribution"),if(view$available).brohn_tp_figure(view,"distribution")else shiny::p("No recorded latency is available for this selection."),
      shiny::p(paste("Twenty equal-width bins use every selected recorded value. The first bin includes both edges; later bins exclude the lower edge and include the upper edge. Missing values do not enter bins.",if(gnat)"Withheld responses have no latency and do not enter bins.")),
      shiny::tags$details(shiny::tags$summary("Distribution counts and exact bin edges"),brohn_table(view$bins,maximum=20L,label="Exact latency distribution bins"))),
    shiny::h3("Exact numerical values"),shiny::p(paste("Page",page,"of",pages,"|",length(view$rows),"selected rows. Paging changes this table only; all charts and downloads retain the complete selection.")),
    brohn_table(rows,columns=if(people)c("position","person_id","value","unit","eligible_attempt_count","eligible_session_count","reason")else if(gnat)
      c("position","trial_id","phase","round_id","cell_id","expected_action","outcome_state","correct","response_ms","disposition","missing_reason")else
      c("position","trial_id","profile_scored","outcome","first_correct","first_response_ms","final_correct_ms","disposition","missing_reason"),maximum=50L,
      label=if(people)"Exact person outcomes and metric-specific support"else if(gnat)"Exact GNAT outcomes, withholding and actual Space-response latency"else"Exact trial outcomes and distinct first and final-correct latency"),
    shiny::tags$details(shiny::tags$summary("Source identity and interpretation"),shiny::p(paste("Source SHA-256:",m$source_hash)),shiny::p(paste("Report SHA-256:",m$report_hash)),
      shiny::p("Browser timing and declared import summaries do not qualify physical response timing or psychological constructs. Source aliases do not independently verify people."),
      if(!is.null(m$audit_policy))shiny::p(m$audit_policy),shiny::tags$pre(brohn_json(m$source,TRUE))))
}
brohn_task_plot_explorer_ui <- function(record) {
  if(!.brohn_tp_supported(record$body))return(NULL)
  shiny::tagList(brohn_card(title="Explore task responses",subtitle="Follow one complete saved administration, or compare the people supporting a cohort measure.",
    brohn_command("Open task plots","open_task_plots",list(report_id=record$id,revision=record$revision,report_hash=brohn_hash(record$body),project_id=record$project_id),id="task-plots-open")),
    shiny::uiOutput("task_plot_error"),shiny::uiOutput("task_plot_catalog"),shiny::uiOutput("task_plot_controls"),shiny::uiOutput("task_plot_view"))
}
brohn_task_plot_csv <- function(view,path) {
  rows<-lapply(view$rows,function(r)c(r,list(report_id=view$model$report_id,report_hash=view$model$report_hash,source_hash=view$model$source_hash,
    selected_measure=view$measure,selected_scope=view$scope,exact_record_json=brohn_json(r))))
  fields<-unique(unlist(lapply(rows,names),use.names=FALSE));if(!length(fields))fields<-c("position","person_id","metric","value","unit","reason","exact_record_json")
  con<-file(path,"wb");on.exit(close(con),add=TRUE)
  write_row<-function(cells)writeBin(charToRaw(enc2utf8(paste0(paste(paste0('"',gsub('"','""',cells,fixed=TRUE),'"'),collapse=","),"\r\n"))),con)
  write_row(fields)
  for(r in rows)write_row(vapply(fields,function(f){v<-r[[f]];s<-if(is.null(v))""else if(is.character(v))v else brohn_json(v)
    if(f!="exact_record_json"&&is.character(v)&&grepl("^[=+@\\t\\r]|^-[^0-9.]",s))paste0("'",s)else s},character(1)))
  invisible(path)
}
brohn_install_task_plots <- function(input,output,session,store,state,attempt,prepare_download) {
  opened<-shiny::reactiveVal(NULL);model<-shiny::reactiveVal(NULL);problem<-shiny::reactiveVal(NULL)
  close<-function(){opened(NULL);model(NULL)};session$onSessionEnded(close)
  shiny::observeEvent(list(state$page,state$report_id),{o<-opened();if(!is.null(o)&&(!identical(state$page,"report")||!identical(state$report_id,o$record$id))){close();problem(NULL)}},priority=100,ignoreInit=FALSE)
  guard<-function(){o<-opened();brohn_require(!is.null(o)&&identical(state$page,"report")&&identical(state$report_id,o$record$id),"Reopen the original saved report.")
    tryCatch(brohn_task_plot_check(store,o,model()),error=function(e){close();problem(conditionMessage(e));stop(e)});o}
  handle<-function(fn)attempt(function(){problem(NULL);tryCatch(fn(),error=function(e){problem(conditionMessage(e));stop(e)})})
  shiny::observeEvent(input$open_task_plots,handle(function(){c<-input$open_task_plots
    brohn_require(identical(state$page,"report")&&identical(state$report_id,c$report_id),"Open this saved report before requesting its plots.")
    close();o<-brohn_task_plot_report(store,c$report_id,c$revision,c$report_hash,c$project_id);opened(o)
  }))
  output$task_plot_error<-shiny::renderUI({if(!is.null(problem()))shiny::div(class="brohn-alert",role="alert",problem(),shiny::p("Choose a retained source and try again. The saved numerical report remains available."))})
  output$task_plot_catalog<-shiny::renderUI({o<-opened();shiny::req(o)
    brohn_card(title="Choose saved evidence",shiny::selectInput("task_plot_source","Administration or cohort measure",stats::setNames(vapply(o$catalog,`[[`,character(1),"id"),vapply(o$catalog,`[[`,character(1),"label")),selectize=FALSE),
      shiny::tags$input(id="task_plot_catalog_identity",type="text",class="shiny-input-text",value=brohn_hash(o$record$body),style="display:none",tabindex="-1",`aria-hidden`="true"),
      shiny::actionButton("task_plot_load","Show complete saved source"),shiny::p("Changing source does not update or recalculate the saved report."))})
  shiny::observeEvent(input$task_plot_load,handle(function(){o<-guard()
    brohn_require(identical(input$task_plot_catalog_identity,brohn_hash(o$record$body)),"Wait for this report's current source controls.")
    model(NULL);model(brohn_task_plot_load(store,o,input$task_plot_source))
  }))
  output$task_plot_controls<-shiny::renderUI({m<-model();shiny::req(m)
    brohn_card(title="Plot controls",shiny::tags$input(id="task_plot_identity",type="text",class="shiny-input-text",value=brohn_hash(list(m$report_hash,m$id,m$source_hash)),style="display:none",tabindex="-1",`aria-hidden`="true"),
      if(m$kind=="trials")shiny::div(class="brohn-form-grid",shiny::selectInput("task_plot_measure","Recorded latency",
        if(identical(m$profile,"gnat-brohn-single-target/1.0"))c("Actual Space response"="first_response_ms")else c("First response"="first_response_ms","Final correct response"="final_correct_ms"),selectize=FALSE),
        shiny::selectInput("task_plot_scope","Trial scope",c("All expected positions"="all","Profile-scored positions"="scored"),selectize=FALSE)),
      shiny::numericInput("task_plot_page","Numerical table page (50 rows per page)",1,min=1,step=1),
      shiny::div(class="brohn-toolbar",shiny::downloadButton("task_plot_svg",if(m$kind=="people")"Download person outcomes SVG"else"Download chronology SVG",icon=NULL),
        if(identical(m$profile,"gnat-brohn-single-target/1.0"))shiny::downloadButton("task_plot_outcomes_svg","Download Go/No-Go outcomes SVG",icon=NULL),
        if(m$kind=="trials")shiny::downloadButton("task_plot_hist_svg","Download distribution SVG",icon=NULL),
        shiny::downloadButton("task_plot_csv","Download every selected row CSV",icon=NULL),shiny::downloadButton("task_plot_json","Download all task values + provenance",icon=NULL)))})
  selected<-shiny::reactive({m<-model();shiny::req(m,identical(input$task_plot_identity,brohn_hash(list(m$report_hash,m$id,m$source_hash))))
    guard()
    if(m$kind=="trials")shiny::req(input$task_plot_measure,input$task_plot_scope)
    brohn_task_plot_selection(m,if(m$kind=="people")"first_response_ms"else input$task_plot_measure,if(m$kind=="people")"all"else input$task_plot_scope)})
  output$task_plot_view<-shiny::renderUI({tryCatch({v<-selected();guard();.brohn_tp_view_ui(v,min(brohn_default(input$task_plot_page,1L),max(1L,ceiling(length(v$rows)/50L))))},
    error=function(e){if(inherits(e,"shiny.silent.error"))stop(e);shiny::div(class="brohn-alert",role="alert",conditionMessage(e))})})
  verified_view<-function(){o<-guard();v<-selected();fresh<-brohn_task_plot_load(store,o,v$model$id)
    brohn_require(identical(fresh$source_hash,v$model$source_hash),"The complete saved source changed. Reopen its plots.");v}
  output$task_plot_json<-shiny::downloadHandler(filename=function()paste0(model()$report_id,"-task-source.json"),contentType="application/json",content=function(file)prepare_download(function()brohn_write_json_file(brohn_task_plot_export(verified_view()),file)))
  output$task_plot_csv<-shiny::downloadHandler(filename=function()paste0(model()$report_id,"-task-values.csv"),contentType="text/csv",content=function(file)prepare_download(function()brohn_task_plot_csv(verified_view(),file)))
  output$task_plot_svg<-shiny::downloadHandler(filename=function()paste0(model()$report_id,"-task-chronology.svg"),contentType="image/svg+xml",content=function(file)prepare_download(function()writeLines(enc2utf8(as.character(brohn_task_plot_svg(verified_view()))),file,useBytes=TRUE)))
  output$task_plot_hist_svg<-shiny::downloadHandler(filename=function()paste0(model()$report_id,"-task-distribution.svg"),contentType="image/svg+xml",content=function(file)prepare_download(function()writeLines(enc2utf8(as.character(brohn_task_plot_svg(verified_view(),"distribution"))),file,useBytes=TRUE)))
  output$task_plot_outcomes_svg<-shiny::downloadHandler(filename=function()paste0(model()$report_id,"-gnat-outcomes.svg"),contentType="image/svg+xml",content=function(file)prepare_download(function()writeLines(enc2utf8(as.character(brohn_task_plot_svg(verified_view(),"outcomes"))),file,useBytes=TRUE)))
  invisible(list(opened=opened,model=model,selected=selected,guard=guard))
}
