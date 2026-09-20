# A single source-bound interval editor; calculations always use complete rows.
.brohn_interval_identity <- function(record) paste(record$id, record$revision, brohn_hash(record$body), sep = ":")
brohn_signal_windows_svg <- function(summary, measure, width=820) {
  rows <- Filter(function(r) identical(r$measure, measure), summary$summaries)
  brohn_require(length(rows) > 0L && length(rows) <= 64L, "Choose a saved interval measure.")
  available <- Filter(function(r) !is.null(r$mean), rows)
  if (!length(available)) return(NULL)
  extent <- unlist(lapply(available, function(r) r$mean + c(-1,1)*brohn_default(r$standard_deviation_sample, 0)))
  limits <- range(extent); padding <- max(diff(limits)*.08, abs(mean(limits))*.02, .001); limits <- limits+c(-padding,padding)
  compact<-width<560;left <- if(compact)72 else 205; right <- if(compact)250 else 690; height <- 85+length(rows)*38
  sx <- function(value) left+(value-limits[1])/diff(limits)*(right-left)
  shiny::tags$svg(xmlns="http://www.w3.org/2000/svg",viewBox=paste(0,0,width,height),width="100%",role="img",
    `aria-labelledby`=paste0("brohn-window-plot-title-",width," brohn-window-plot-description-",width),style="display:block;max-width:100%;background:#131d24;font-family:system-ui,sans-serif",
    shiny::tags$title(id=paste0("brohn-window-plot-title-",width),paste(brohn_signal_label(measure),"by saved interval")),
    shiny::tags$desc(id=paste0("brohn-window-plot-description-",width),"Dots are sample-weighted means; lines show one sample standard deviation, not confidence intervals. Exact values and eligible sample counts are provided in the accompanying table. Intervals may overlap."),
    lapply(seq(limits[1],limits[2],length.out=if(compact)3 else 5),function(value) shiny::tagList(
      shiny::tags$line(x1=sx(value),x2=sx(value),y1=20,y2=height-55,stroke="#3f5058"),
      shiny::tags$text(x=sx(value),y=height-32,`text-anchor`="middle",fill="#d2dedd",`font-size`=12,brohn_signal_number(value)))),
    lapply(seq_along(rows),function(i) {r<-rows[[i]];y<-22+i*38
      shiny::tagList(shiny::tags$text(x=left-12,y=y+4,`text-anchor`="end",fill="#edf5f3",`font-size`=13,
        if(nchar(r$label)>if(compact)8 else 24)paste0(substr(r$label,1,if(compact)6 else 21),"...")else r$label,shiny::tags$title(r$label)),
        if(is.null(r$mean))shiny::tags$text(x=left+12,y=y+4,fill="#d2dedd",`font-size`=13,"No eligible samples")else shiny::tagList(
          if(!is.null(r$standard_deviation_sample))shiny::tags$line(x1=sx(r$mean-r$standard_deviation_sample),x2=sx(r$mean+r$standard_deviation_sample),y1=y,y2=y,stroke="#a7e9d3",`stroke-width`=3),
          shiny::tags$circle(cx=sx(r$mean),cy=y,r=5,fill="#a7e9d3",shiny::tags$title(paste(r$label,"mean",brohn_signal_number(r$mean),r$unit,"eligible samples",r$eligible_rows)))),
        shiny::tags$text(x=right+15,y=y+4,fill="#d2dedd",`font-size`=if(compact)10 else 13,paste0("n = ",r$eligible_rows))) }),
    shiny::tags$text(x=(left+right)/2,y=height-9,`text-anchor`="middle",fill="#edf5f3",`font-size`=if(compact)12 else 14,
      if(compact)paste0("Mean (",rows[[1]]$unit,")")else paste(brohn_signal_label(measure),paste0("(",rows[[1]]$unit,")"))))
}
brohn_install_signal_annotations_ui <- function(input, output, session, store, state, attempt, message, prepare_download, context, catalog, table) {
  active <- shiny::reactiveVal(NULL); editing <- shiny::reactiveVal(NULL); revision_tick <- shiny::reactiveVal(0L)
  job_id <- shiny::reactiveVal(NULL); summary <- shiny::reactiveVal(NULL); issue <- shiny::reactiveVal(NULL)
  clear <- function() {active(NULL);editing(NULL);job_id(NULL);summary(NULL);issue(NULL)}
  shiny::observeEvent(list(state$page,state$report_id,input$signal_table),clear(),ignoreInit=FALSE,priority=100)
  protect <- function(fn) attempt(function() {issue(NULL);tryCatch(fn(),error=function(e){issue(conditionMessage(e));stop(e)})})
  selected <- function(form=FALSE) {
    record <- active();brohn_require(!is.null(record),"Create or open a saved interval set.")
    current <- tryCatch(brohn_signal_annotations(store,record$id,record$revision,brohn_hash(record$body)),error=function(e){clear();stop(e)})
    r<-context();t<-table()
    brohn_require(identical(current$body$report_id,r$id)&&identical(current$body$report_hash,brohn_hash(r$body))&&identical(current$body$table$table_id,t$table_id),"Reopen the interval set for this exact recording.")
    if(form)brohn_require(identical(input$interval_form_identity,.brohn_interval_identity(record)),"Wait for this saved interval version before applying changes.")
    current
  }
  command_record <- function(command) {
    r<-selected();brohn_require(identical(command$identity,.brohn_interval_identity(r)),"That action belongs to an earlier interval version. Use the current list.");r
  }
  output$signal_annotation_controls <- shiny::renderUI({
    r<-context();c<-catalog();t<-table();revision_tick()
    if(!identical(t$coordinates$axis,"time")||!identical(t$coordinate_column$unit,"s")||!identical(c$body$view$artifact$kind,"physiology-series"))return(NULL)
    sets<-brohn_list_entities(store,"signal_annotations",r$project_id,limit=100L,filters=list(report_id=r$id,"table.table_id"=t$table_id))
    choices<-c("Choose a saved set"="",setNames(vapply(sets,`[[`,character(1),"id"),vapply(sets,function(s)s$body$title,character(1))))
    brohn_card(title="Mark and compare recording intervals",subtitle="Save baseline, task or other named windows on this recording. Summaries read every eligible processed sample in each window.",
      shiny::tags$input(id="interval_source_identity",type="text",class="shiny-input-text",value=paste(r$id,c$id,t$table_id,sep=":"),hidden=NA),
      shiny::div(class="brohn-form-grid",shiny::textInput("interval_set_title","New interval set name","Recording intervals"),
        shiny::div(class="form-group",shiny::p("Create a versioned set"),shiny::actionButton("create_interval_set","Create interval set",class="btn-primary"))),
      if(length(sets))shiny::div(class="brohn-form-grid",shiny::selectInput("interval_set_choice","Saved interval sets (up to 100 most recent)",choices,selectize=FALSE),shiny::actionButton("open_interval_set","Open interval set")),
      shiny::uiOutput("signal_interval_reuse"),
      shiny::p(class="brohn-muted","Each set is linked to one recording, channel, person/session and original clock. This action does not align independent clocks or modify the scientific source."))
  })
  shiny::observeEvent(input$create_interval_set,protect(function(){r<-context();c<-catalog();t<-table()
    brohn_require(identical(input$interval_source_identity,paste(r$id,c$id,t$table_id,sep=":")),"Wait for the current recording before creating intervals.")
    value<-brohn_create_signal_annotations(store,c$id,t$table_id,input$interval_set_title);active(value);editing(NULL);summary(NULL);job_id(NULL);revision_tick(revision_tick()+1L);message("Interval set created; add a named window.")
  }))
  shiny::observeEvent(input$open_interval_set,protect(function(){r<-context();c<-catalog();t<-table()
    brohn_require(identical(input$interval_source_identity,paste(r$id,c$id,t$table_id,sep=":"))&&brohn_text(input$interval_set_choice,160),"Choose an interval set for the current recording.")
    value<-brohn_signal_annotations(store,input$interval_set_choice)
    brohn_require(identical(value$project_id,r$project_id)&&identical(value$body$report_id,r$id)&&identical(value$body$table$table_id,t$table_id),"This interval set belongs to another source.")
    active(value);editing(NULL);job_id(NULL)
    saved<-brohn_list_entities(store,"signal_windows",r$project_id,limit=1L,filters=list("annotation_source.id"=value$id))
    summary(if(length(saved))saved[[1L]]else NULL);message("Saved intervals opened.")
  }))
  output$signal_annotation_editor <- shiny::renderUI({r<-active();if(is.null(r))return(NULL);r<-selected();v<-r$body;identity<-.brohn_interval_identity(r)
    i<-Filter(function(x)identical(x$id,editing()),v$intervals);i<-if(length(i))i[[1L]]else NULL
    bounds<-v$table$coordinate_range;columns<-setNames(vapply(v$table$value_columns,`[[`,character(1),"name"),vapply(v$table$value_columns,function(c)paste(brohn_signal_label(c$name),paste0("(",c$unit,")")),character(1)))
    brohn_card(title=v$title,subtitle=paste("Saved version",r$revision,"with",length(v$intervals),"intervals. Earlier versions remain preserved."),
      shiny::tags$input(id="interval_form_identity",type="text",class="shiny-input-text",value=identity,hidden=NA),
      shiny::div(class="brohn-form-grid",shiny::textInput("interval_label","Interval label",brohn_default(i$label,"")),shiny::textInput("interval_category","Category (optional)",brohn_default(i$category,"")),
        shiny::numericInput("interval_start","Start in seconds (included)",brohn_signal_exact_number(brohn_default(i$start_s,if(length(bounds))bounds[[1]]else 0))),
        shiny::numericInput("interval_end","End in seconds (excluded)",brohn_signal_exact_number(brohn_default(i$end_s,if(length(bounds)&&bounds[[2]]>bounds[[1]])bounds[[2]]else 1)))),
      shiny::textAreaInput("interval_note","Notes (optional)",brohn_default(i$note,""),rows=2),
      shiny::div(class="brohn-toolbar",shiny::actionButton("save_signal_interval",if(is.null(i))"Add interval"else"Save interval changes",class="btn-primary"),
        if(!is.null(i))brohn_command("Cancel interval edit","signal_interval_command",list(action="cancel",identity=identity))),
      shiny::p(class="brohn-muted","The start is included and the end is excluded, so adjacent intervals do not count their shared boundary twice. Overlapping intervals deliberately reuse samples."),
      if(length(v$intervals))shiny::div(class="brohn-stack",lapply(v$intervals,function(x)brohn_card(title=x$label,subtitle=paste(brohn_signal_exact_number(x$start_s),"to",brohn_signal_exact_number(x$end_s),"seconds",if(nzchar(x$category))paste("|",x$category)),
        if(nzchar(x$note))shiny::p(x$note),shiny::div(class="brohn-toolbar",brohn_command("Edit interval","signal_interval_command",list(action="edit",identity=identity,id=x$id)),
          brohn_command("Remove interval","signal_interval_command",list(action="remove",identity=identity,id=x$id)))))),
      shiny::selectInput("interval_measures","Measures to summarize",columns,selected=head(unname(columns),1),multiple=TRUE,selectize=FALSE),
      shiny::div(class="brohn-toolbar",shiny::actionButton("summarize_signal_intervals","Calculate interval summaries",class="btn-primary"),shiny::downloadButton("signal_intervals_json","Download saved intervals",icon=NULL)),
      if(r$revision>1L)shiny::tags$details(shiny::tags$summary("Recover an earlier interval version"),
        shiny::p("Restoring saves a new current version. Existing summaries and every earlier version remain preserved."),
        shiny::numericInput("interval_restore_revision","Earlier version to review",r$revision-1L,min=1,max=r$revision-1L,step=1),
        shiny::actionButton("preview_interval_revision","Review earlier intervals"),shiny::uiOutput("signal_annotation_history")))
  })
  shiny::observeEvent(input$save_signal_interval,protect(function(){r<-selected(TRUE)
    value<-brohn_save_signal_interval(store,r$id,r$revision,input$interval_label,input$interval_category,input$interval_start,input$interval_end,input$interval_note,editing())
    active(value);editing(NULL);message("Interval saved as a new version.")
  }))
  shiny::observeEvent(input$signal_interval_command,protect(function(){command<-input$signal_interval_command;r<-command_record(command)
    brohn_require(command$action %in% c("edit","remove","cancel"),"Choose an available interval action.")
    if(command$action=="cancel")editing(NULL)else {
      brohn_require(command$id %in% brohn_ids(r$body$intervals),"Choose a current interval.")
      if(command$action=="edit")editing(command$id)else {active(brohn_remove_signal_interval(store,r$id,r$revision,command$id));editing(NULL);message("Interval removed; earlier saved versions are retained.")}
    }
  }))
  shiny::observeEvent(input$summarize_signal_intervals,protect(function(){r<-selected(TRUE)
    job<-brohn_queue_signal_windows(store,r$id,r$revision,brohn_hash(r$body),as.list(input$interval_measures))
    if(job$status %in% c("failed","cancelled"))job<-brohn_retry_processing(store,job$id)
    job_id(job$id);message("Calculating intervals from the complete processed recording.")
  }))
  history<-shiny::reactiveVal(NULL)
  shiny::observeEvent(active(),history(NULL),ignoreNULL=FALSE)
  shiny::observeEvent(input$preview_interval_revision,protect(function(){r<-selected(TRUE);version<-input$interval_restore_revision
    brohn_require(brohn_number(version,1,r$revision-1L,TRUE),"Choose an earlier saved version to review.")
    history(brohn_signal_annotations(store,r$id,as.integer(version)))
  }))
  output$signal_annotation_history<-shiny::renderUI({h<-history();if(is.null(h))return(NULL);r<-selected()
    brohn_require(identical(h$id,r$id)&&h$revision<r$revision,"Review a previous version of this interval set.")
    shiny::tagList(shiny::p(paste("Saved version",h$revision,"contains",length(h$body$intervals),"intervals.")),
      brohn_table(h$body$intervals,maximum=64L,label=paste("Intervals in saved version",h$revision)),
      brohn_command(paste("Restore version",h$revision),"restore_signal_intervals",list(identity=.brohn_interval_identity(r),revision=h$revision,hash=brohn_hash(h$body))))
  })
  shiny::observeEvent(input$restore_signal_intervals,protect(function(){cmd<-input$restore_signal_intervals;r<-command_record(cmd)
    active(brohn_restore_signal_intervals(store,r$id,r$revision,cmd$revision,cmd$hash));editing(NULL);message("Earlier intervals restored as a new saved version.")
  }))
  job<-shiny::reactive({if(is.null(job_id()))return(NULL);selected();shiny::invalidateLater(1000,session);brohn_get_job(store,job_id())})
  shiny::observe({j<-job();if(!is.null(j)&&identical(j$status,"succeeded")) {r<-brohn_get_entity(store,"signal_windows",j$result$signal_windows_id);if(!identical(summary(),r))summary(r)}})
  output$signal_annotation_progress <- shiny::renderUI({j<-job();error<-issue()
    shiny::tagList(if(!is.null(error))shiny::div(class="brohn-alert brohn-alert-error",role="alert",error),
      if(!is.null(j)&&j$status!="succeeded")brohn_card(title="Interval summary progress",shiny::p(switch(j$status,queued="Queued",running="Reading complete saved samples",failed="Calculation needs attention",cancelled="Calculation cancelled",j$status)),
        if(!is.null(j$error))shiny::p(j$error$message),if(j$status %in% c("queued","running"))brohn_command("Cancel interval calculation","cancel_processing",j$id),
        if(j$status %in% c("failed","cancelled"))shiny::p("Saved intervals and the original report remain available. Calculate again to retry the saved selection.")))
  })
  result<-shiny::reactive({r<-summary();shiny::req(r);a<-selected()
    brohn_require(identical(r$project_id,a$project_id)&&identical(r$body$report_id,a$body$report_id)&&identical(r$body$annotation_source$id,a$id),"Reopen the saved summary for this recording.")
    brohn_signal_annotations(store,a$id,r$body$annotation_source$revision,r$body$annotation_source$hash);r
  })
  output$signal_annotation_summary <- shiny::renderUI({r<-summary();if(is.null(r))return(NULL);r<-result();v<-r$body$summary
    choices<-setNames(unlist(v$selection$value_columns),vapply(v$selection$value_columns,brohn_signal_label,character(1)))
    brohn_card(title="Saved interval comparison",subtitle=paste("Calculated from interval version",r$body$annotation_source$revision,"and the complete processed source."),
      shiny::p("Means describe the retained samples in each interval. Lines in the chart show one sample standard deviation, not confidence or statistical significance."),
      shiny::selectInput("signal_window_plot_measure","Measure to compare",choices,selectize=FALSE),shiny::uiOutput("signal_annotation_chart"),
      brohn_table(v$summaries,columns=c("label","measure","mean","unit","standard_deviation_sample","eligible_rows","missing_value_rows","excluded_support_rows"),
        labels=c("Interval","Measure","Mean","Unit","Sample SD","Eligible samples","Missing values","Excluded samples"),maximum=1024L,label="Exact interval values and eligible sample counts"),
      shiny::div(class="brohn-toolbar",shiny::downloadButton("signal_windows_csv","Download comparison table",icon=NULL),
        shiny::downloadButton("signal_windows_json","Download results + provenance",icon=NULL),shiny::downloadButton("signal_windows_svg","Download comparison chart",icon=NULL)),
      shiny::tags$details(shiny::tags$summary("Method and support"),shiny::p(v$parameters$aggregation),shiny::p(v$parameters$standard_deviation),lapply(v$limitations,shiny::p)))
  })
  chosen_measure<-function(){r<-result();measure<-input$signal_window_plot_measure;brohn_require(brohn_text(measure,500)&&measure %in% unlist(r$body$summary$selection$value_columns),"Choose a saved measure for this chart.");measure}
  output$signal_annotation_chart <- shiny::renderUI({shiny::req(input$signal_window_plot_measure);v<-result()$body$summary;svg<-brohn_signal_windows_svg(v,chosen_measure())
    if(is.null(svg))shiny::p("No eligible samples are available for this measure in the saved intervals.")else shiny::div(role="region",`aria-label`="Interval comparison chart",
      shiny::div(class="brohn-signal-wide",svg),shiny::div(class="brohn-signal-compact",brohn_signal_windows_svg(v,chosen_measure(),320)))
  })
  output$signal_intervals_json<-shiny::downloadHandler(filename=function()paste0(selected()$id,"-v",selected()$revision,".json"),content=function(file)prepare_download(function()brohn_write_json_file(selected()$body,file)),contentType="application/json")
  output$signal_windows_json<-shiny::downloadHandler(filename=function()paste0(result()$id,".json"),content=function(file)prepare_download(function()brohn_copy_object_download(store,result()$body$result_object$hash,file)),contentType="application/json")
  output$signal_windows_csv<-shiny::downloadHandler(filename=function()paste0(result()$id,".csv"),content=function(file)prepare_download(function(){r<-result();rows<-lapply(r$body$summary$summaries,function(row)c(list(report_id=r$body$report_id,annotation_id=r$body$annotation_source$id,annotation_revision=r$body$annotation_source$revision,annotation_hash=r$body$annotation_source$hash,source_artifact_hash=r$body$summary$artifact$sha256),row));brohn_export_report_csv(list(analysis=list(observations=rows)),file)}),contentType="text/csv")
  output$signal_windows_svg<-shiny::downloadHandler(filename=function()paste0(result()$id,".svg"),content=function(file)prepare_download(function(){svg<-brohn_signal_windows_svg(result()$body$summary,chosen_measure());brohn_require(!is.null(svg),"This measure has no eligible comparison chart.");writeLines(enc2utf8(as.character(svg)),file,useBytes=TRUE)}),contentType="image/svg+xml")
  reuse<-brohn_install_signal_interval_reuse_ui(input,output,session,store,state,protect,message,context,catalog,table,
    function(value){active(value);editing(NULL);summary(NULL);job_id(NULL);revision_tick(revision_tick()+1L)})
  invisible(list(active=active,editing=editing,summary=summary,job_id=job_id,history=history,reuse=reuse))
}
