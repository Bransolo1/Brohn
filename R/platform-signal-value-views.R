# Presentation of typed source rows. Measurement decimals arrive as exact strings.
.brohn_sv_action <- function(label,action,payload,primary=FALSE) shiny::tags$button(type="button",
  class=if(primary)"btn btn-primary"else"btn btn-outline-secondary",`data-signal-values-action`=action,
  `data-signal-values-payload`=brohn_json(payload),label)
.brohn_sv_identity <- function(r)paste(r$id,r$revision,.brohn_sv_hash(r$body),sep=":")
.brohn_sv_retention_label <- function(x)switch(x,retained="Retained",excluded="Excluded",unknown="Unknown",not_declared="Not declared",x)
.brohn_sv_count <- function(x)format(x,digits=17,scientific=FALSE,trim=TRUE,big.mark=",")
.brohn_sv_selection_text <- function(v) {
  t<-v$table;s<-v$selection;unit<-Filter(function(c)identical(c$name,s$value_column),t$columns)[[1L]]$unit
  paste(brohn_signal_label(s$value_column),paste0("(",brohn_default(unit,"unit not declared"),")"),"from",s$channel,
    if(is.null(s$range))"across the complete source range, including rows without a coordinate."else paste("from",brohn_signal_exact_number(s$range[[1]]),"to",brohn_signal_exact_number(s$range[[2]]),Filter(function(c)identical(c$role,"coordinate"),t$columns)[[1L]]$unit,"(both included)."))
}
brohn_signal_values_page_ui <- function(record,source) {
  v<-record$body$result;p<-v$page;t<-v$table
  coordinate<-Filter(function(c)identical(c$role,"coordinate"),t$columns)[[1L]]
  measure<-Filter(function(c)identical(c$name,v$selection$value_column),t$columns)[[1L]]
  pin<-list(source=source,result=record$id,result_hash=.brohn_sv_hash(record$body))
  shiny::div(class="brohn-exact-values",id="signal-exact-values",`data-values-id`=record$id,
    shiny::h3("Exact processed values"),shiny::p(class="brohn-exact-selection",.brohn_sv_selection_text(v)),
    shiny::p(shiny::strong(paste(.brohn_sv_count(p$total_rows),"selected source rows."))," Missing measurements and excluded or unknown retention remain included. No plot filtering is applied."),
    if(v$unplaceable_coordinate_rows>0)shiny::p(class="brohn-alert brohn-alert-warning",paste(.brohn_sv_count(v$unplaceable_coordinate_rows),"source rows have no coordinate and cannot be placed in this numeric range. Choose the complete range to include them.")),
    shiny::div(class="brohn-toolbar",if(!is.null(p$previous_offset)).brohn_sv_action("Previous values","page",c(pin,list(offset=p$previous_offset))),
      if(!is.null(p$next_offset)).brohn_sv_action("Next values","page",c(pin,list(offset=p$next_offset))),
      .brohn_sv_action("Prepare complete selected CSV","export",pin),.brohn_sv_action("Close exact values","close",pin)),
    if(!length(v$rows))shiny::p(role="status",if(p$total_rows==0)"No saved source rows fall in this selection. The complete source remains available."else"This page begins after the selected source rows. Return to an earlier page."),
    if(length(v$rows))shiny::tagList(
      shiny::p(id="signal-values-scroll-help",class="brohn-muted","On a narrow screen, scroll the table horizontally to inspect every column. Row and sample indices are zero-based."),
      shiny::div(class="brohn-exact-scroll",role="region",tabindex="0",`aria-label`="Exact processed-value table",`aria-describedby`="signal-values-scroll-help",
        shiny::tags$table(class="table brohn-exact-table",shiny::tags$caption(paste("Saved source rows",.brohn_sv_count(p$offset+1),"to",.brohn_sv_count(p$offset+p$returned),"of",.brohn_sv_count(p$total_rows))),
          shiny::tags$thead(shiny::tags$tr(lapply(c("Source row",paste0(brohn_signal_label(coordinate$name)," (",coordinate$unit,")"),paste0(brohn_signal_label(measure$name)," (",measure$unit,")"),"Source sample","Retention","Original fields"),function(x)shiny::tags$th(scope="col",x)))),
          shiny::tags$tbody(lapply(v$rows,function(row)shiny::tags$tr(
            shiny::tags$th(scope="row",class="brohn-exact-number",as.character(row$table_row_index)),
            shiny::tags$td(class="brohn-exact-number",if(row$coordinate_is_null)"Unavailable"else row$coordinate_text),
            shiny::tags$td(class="brohn-exact-number",if(row$value_is_null)"Unavailable"else row$value_text),
            shiny::tags$td(class="brohn-exact-number",if(is.null(row$source_sample_index))"Not supplied"else brohn_signal_exact_number(row$source_sample_index)),
            shiny::tags$td(.brohn_sv_retention_label(row$retention)),shiny::tags$td(.brohn_sv_action(paste("Inspect row",row$table_row_index),"detail",c(pin,list(row=row$table_row_index))))))))),
      if(isTRUE(p$byte_limited))shiny::p("This page contains fewer rows to keep large source records readable. Next values continues at the following source row.")),
    shiny::tags$details(shiny::tags$summary("Source support and exact value meaning"),
      shiny::p("Unavailable is a saved null, not zero. Retention is a saved support flag: unknown differs from explicitly excluded, and not declared means this table has no such flag. This view does not classify or correct samples."),
      brohn_table(lapply(c("Complete table","Selected range"),function(label){s<-if(label=="Complete table")v$full_source else v$selected_source
        list(scope=label,source_rows=.brohn_sv_count(s$rows),missing_coordinate=.brohn_sv_count(s$missing_coordinate_rows),missing_measure=.brohn_sv_count(s$missing_value_rows),
          retained=.brohn_sv_count(s$retained_rows),excluded=.brohn_sv_count(s$excluded_retention_rows),unknown_retention=.brohn_sv_count(s$unknown_retention_rows),no_retention_flag=.brohn_sv_count(s$undeclared_retention_rows))}),label="Exact processed-value support counts"),
      shiny::p(class="brohn-exact-selection",paste("Clock reference:",t$coordinates$reference,"; original origin:",brohn_default(t$coordinates$source_time_origin,"not supplied"),brohn_default(t$coordinates$source_time_unit,""))),
      shiny::p("Displayed measurement decimals and CSV values round-trip to their saved binary64 values, including signed zero. Complete row detail preserves typed null, false and empty text. CSV human text receives a leading apostrophe when needed to prevent spreadsheet formulas; exact original text remains in the JSON columns."),
      shiny::p(class="brohn-exact-selection",paste("Table:",t$table_id)),shiny::p(class="brohn-exact-selection",paste("Artifact SHA-256:",v$artifact$sha256))))
}

brohn_install_signal_values <- function(input,output,session,store,state,attempt,message,prepare_download,context,catalog,table,
    register_resource=function(name,data,filter)session$registerDataObj(name,data,filter)) {
  active<-shiny::reactiveVal(NULL);ready<-shiny::reactiveVal(NULL);exported<-shiny::reactiveVal(NULL)
  detail<-shiny::reactiveVal(NULL);issue<-shiny::reactiveVal(NULL);page_job<-shiny::reactiveVal(NULL);export_job<-shiny::reactiveVal(NULL)
  download<-shiny::reactiveVal(NULL);checks<-new.env(parent=emptyenv());checking<-shiny::reactiveVal(FALSE)
  release_check<-function(which){v<-checks[[which]];if(!is.null(v)){if(!is.null(v$process)&&v$process$is_alive())v$process$kill_tree();for(g in v$guards).brohn_qexplorer_release(g)};checks[[which]]<-NULL}
  release_download<-function(){release_check("export");download(NULL)}
  clear<-function(){active(NULL);ready(NULL);exported(NULL);detail(NULL);page_job(NULL);export_job(NULL);release_check("page");release_download();checking(FALSE)}
  session$onSessionEnded(function(){release_check("page");release_check("export")})
  start_check<-function(which,record){
    release_check(which)
    data<-brohn_signal_values_input(store,list(operation=record$body$operation,request=record$body$request),verify=FALSE)
    refs<-c(data$source_objects,list(list(hash=record$body$result_object$hash,bytes=record$body$result_object$size)))
    if(which=="export")refs<-c(refs,list(list(hash=record$body$csv_object$hash,bytes=record$body$csv_object$size)))
    refs<-refs[!duplicated(vapply(refs,`[[`,character(1),"hash"))]
    data$source_objects<-refs;guards<-brohn_hold_signal_value_sources(store,data);success<-FALSE
    on.exit(if(!success)for(g in guards).brohn_qexplorer_release(g),add=TRUE)
    paths<-lapply(refs,function(r)list(path=brohn_object_path(store,r$hash,verify=FALSE),sha256=r$hash))
    code<-paste(c("import hashlib,json,sys", "for item in json.loads(sys.argv[1]):", " h=hashlib.sha256()", " with open(item['path'],'rb') as f:", "  for b in iter(lambda:f.read(1048576),b''):h.update(b)", " if h.hexdigest()!=item['sha256']:raise RuntimeError('Saved source bytes changed; reopen the exact report.')", "print('verified')"),collapse="\n")
    process<-processx::process$new(.brohn_publication_python(),c("-B","-c",code,brohn_json(paths)),stdout="|",stderr="|",cleanup_tree=TRUE,windows_hide_window=TRUE)
    checks[[which]]<-list(process=process,guards=guards,record=record,started=Sys.time());success<-TRUE;checking(TRUE)
  }
  shiny::observeEvent(list(state$page,state$report_id,input$signal_table),{clear();issue(NULL)},ignoreInit=FALSE,priority=110)
  source_key<-shiny::reactive({paste(.brohn_sv_identity(context()),.brohn_sv_identity(catalog()),.brohn_sv_hash(table()),sep="|")})
  shiny::observeEvent(source_key(),{p<-active();if(!is.null(p)&&!identical(p$source,source_key()))clear()},ignoreInit=TRUE,priority=105)
  guard<-function(pin)tryCatch({
    brohn_require(!is.null(pin)&&identical(state$page,"report")&&identical(state$report_id,pin$report_id)&&identical(source_key(),pin$source),"Reopen the exact values for this recording.")
    r<-brohn_get_entity(store,"report",pin$report_id);c<-brohn_get_entity(store,"signal_view",pin$catalog_id)
    brohn_require(identical(.brohn_sv_identity(r),pin$report_identity)&&identical(.brohn_sv_identity(c),pin$catalog_identity),"The saved source changed. Reopen its current exact values.")
    brohn_project(store,pin$project_id)
    brohn_signal_values_input(store,list(operation="signal_values_page",request=pin$request),verify=FALSE)
    invisible(pin)
  },error=function(e){clear();stop(e)})
  protect<-function(fn)attempt(function(){issue(NULL);tryCatch(fn(),error=function(e){issue(conditionMessage(e));stop(e)})})
  queue<-function(mode,offset=0,retry=FALSE) {
    p<-active();guard(p)
    j<-brohn_queue_signal_values(store,p$catalog_id,p$request$selection,mode,offset,p$request$page$limit,
      p$request$catalog_revision,p$request$catalog_hash,retry=retry)
    if(mode=="page"){page_job(j);ready(NULL);detail(NULL);release_check("page")}else{export_job(j);exported(NULL);release_download()}
    message(if(mode=="page")"Reading exact values from the complete saved table."else"Preparing every selected source row as an exact CSV in the background.")
    invisible(j)
  }
  output$signal_values_controls<-shiny::renderUI({t<-table();if(!length(t$value_columns))return(NULL)
    shiny::div(class="brohn-exact-values",shiny::tags$script(src="signal-values-ui.js"),
      shiny::tags$style(shiny::HTML(".brohn-exact-values{min-width:0;max-width:100%}.brohn-exact-values button,.brohn-exact-values a,.brohn-exact-values select,.brohn-exact-values summary{min-height:44px}.brohn-exact-values summary{display:flex;align-items:center}.brohn-exact-scroll{max-width:100%;overflow-x:auto;border:1px solid #44555b;border-radius:.5rem}.brohn-exact-scroll:focus-visible{outline:3px solid #a7e9d3;outline-offset:3px}.brohn-exact-values table.brohn-exact-table{width:100%;min-width:54rem;table-layout:auto;margin-bottom:0}.brohn-exact-values .brohn-exact-table th,.brohn-exact-values .brohn-exact-table td{word-break:normal;overflow-wrap:normal;min-width:7rem;vertical-align:middle}.brohn-exact-values .brohn-exact-table .brohn-exact-number{white-space:nowrap;font-variant-numeric:tabular-nums}.brohn-exact-values caption{caption-side:top;color:inherit;padding:.75rem;font-weight:600;white-space:nowrap}.brohn-exact-values pre{white-space:pre;overflow:auto;max-height:32rem;padding:1rem;background:#111b22;color:#edf5f3}.brohn-exact-values .brohn-exact-selection{max-width:100%;overflow-wrap:anywhere}")),
      shiny::tags$style(shiny::HTML(".brohn-exact-values .brohn-table table{min-width:64rem;table-layout:auto}.brohn-exact-values .brohn-table th,.brohn-exact-values .brohn-table td{white-space:nowrap;word-break:normal;overflow-wrap:normal}.brohn-exact-values .brohn-table{overflow-x:auto;max-width:100%}")),
      brohn_card(title="Inspect or export exact values",shiny::p("Use the recording, processed measure and range selected above. Exact values include missing and analysis-excluded rows from the saved source."),
        shiny::selectInput("signal_values_limit","Rows per value page",c("25"=25,"50"=50,"100"=100),selected=50,width="12rem",selectize=FALSE),
        .brohn_sv_action("Show exact values","open",list(source=source_key()),TRUE)))
  })
  shiny::observeEvent(input$signal_values_action,protect(function(){
    cmd<-input$signal_values_action
    brohn_require(is.list(cmd)&&identical(cmd$source,source_key()),"Use the current recording's exact-value controls.")
    if(identical(cmd$action,"open")) {
      f<-cmd$fields;r<-context();c<-catalog();t<-table()
      brohn_require(identical(c$body$report_id,r$id)&&.brohn_sv_same(c$body$report_revision,r$revision)&&identical(c$body$report_hash,.brohn_sv_hash(r$body)),
        "Reopen the processed-table catalog for this current report before inspecting exact values.")
      brohn_require(is.list(f)&&identical(f$form,paste(r$id,c$id,sep=":"))&&identical(f$measure_form,paste(c$id,t$table_id,sep=":")),"Wait for the current recording and measure controls.")
      brohn_require(brohn_text(f$measure,500)&&f$measure %in% vapply(t$value_columns,`[[`,character(1),"name")&&f$limit %in% c("25","50","100")&&is.logical(f$full_range)&&length(f$full_range)==1L,"Choose one measure and 25, 50 or 100 rows.")
      number<-function(x){brohn_require(brohn_text(x,100)&&grepl("^[+-]?([0-9]+([.][0-9]*)?|[.][0-9]+)([eE][+-]?[0-9]+)?$",x),"Enter a finite start and end, or choose the complete range.");n<-as.numeric(x);brohn_require(brohn_number(n),"Enter finite range values.");n}
      selection<-list(table_id=t$table_id,recording_id=t$identity$recording_id,channel=t$identity$channel,value_column=f$measure,
        range=if(isTRUE(f$full_range))NULL else list(number(f$start),number(f$end)),row_policy="all_source_rows")
      brohn_validate_signal_value_selection(selection)
      j<-brohn_queue_signal_values(store,c$id,selection,"page",limit=as.numeric(f$limit),catalog_revision=c$revision,catalog_hash=.brohn_sv_hash(c$body))
      clear();active(list(source=cmd$source,report_id=r$id,report_identity=.brohn_sv_identity(r),catalog_id=c$id,
        catalog_identity=.brohn_sv_identity(c),project_id=r$project_id,request=j$request));page_job(j)
      message("Reading exact values from the complete saved table.");return(invisible(NULL))
    }
    pin<-active();guard(pin)
    if(identical(cmd$action,"close")){clear();return(invisible(NULL))}
    if(cmd$action %in% c("retry_page","retry_export")){queue(if(cmd$action=="retry_page")"page"else"export",offset=if(cmd$action=="retry_page")brohn_default(page_job()$request$page$offset,0)else 0,retry=TRUE);return(invisible(NULL))}
    record<-ready();brohn_require(!is.null(record)&&identical(cmd$result,record$id)&&identical(cmd$result_hash,.brohn_sv_hash(record$body)),"This value page changed. Use its current controls.")
    brohn_signal_values_record(store,record$id,cmd$result_hash)
    if(cmd$action=="page"){
      p<-record$body$result$page;allowed<-unlist(list(p$previous_offset,p$next_offset),use.names=FALSE)
      brohn_require(brohn_number(cmd$offset,0,20000000,TRUE)&&cmd$offset %in% allowed,"Use a continuation from the current value page.");queue("page",cmd$offset)
    }else if(cmd$action=="export")queue("export")else if(cmd$action=="detail"){
      rows<-Filter(function(row)identical(as.numeric(row$table_row_index),as.numeric(cmd$row)),record$body$result$rows)
      brohn_require(length(rows)==1L,"Choose an original row from this current page.");detail(rows[[1L]])
    }else brohn_stop("Choose an available exact-value action.")
  }))
  shiny::observe({p<-active();if(is.null(p))return();shiny::invalidateLater(1000,session)
    tryCatch(shiny::isolate({guard(p)
      for(which in c("page","export")) {
        slot<-if(which=="page")page_job else export_job;j<-slot();if(is.null(j))next
        fresh<-brohn_get_job(store,j$id);slot(fresh)
        target<-if(which=="page")ready else exported
        if(!identical(fresh$status,"succeeded")||is.null(fresh$result$signal_values_id)||!is.null(target()))next
        v<-checks[[which]]
        if(is.null(v)){
          record<-brohn_signal_values_record(store,fresh$result$signal_values_id,verify=TRUE)
          brohn_require(.brohn_sv_same(record$body$request,fresh$request),"The saved result differs from this queued selection.")
          start_check(which,record)
        }else if(!v$process$is_alive()){
          brohn_require(identical(v$process$get_exit_status(),0L)&&identical(trimws(v$process$read_all_output()),"verified"),"The saved source or prepared values failed their integrity check. Reopen the report and prepare them again.")
          for(g in v$guards).Call(g$native$check,g$pointer)
          target(v$record);v$process<-NULL;checks[[which]]<-v
        }else brohn_require(as.numeric(difftime(Sys.time(),v$started,units="secs"))<900,"Source verification took too long. Reopen the report and retry this selection.")
      }
      checking(any(vapply(as.list(checks),function(v)!is.null(v$process),logical(1))))
    }),error=function(e){clear();issue(conditionMessage(e))})
  })
  output$signal_values_progress<-shiny::renderUI({
    jobs<-Filter(function(j)!is.null(j)&&j$status!="succeeded",list(page=page_job(),export=export_job()))
    if(is.null(issue())&&!checking()&&!length(jobs))return(NULL)
    shiny::div(class="brohn-exact-values",if(!is.null(issue()))shiny::div(class="brohn-alert brohn-alert-error",role="alert",issue()),
      if(checking())shiny::tagList(shiny::p(role="status","Verifying saved source bytes in the background before opening exact values."),.brohn_sv_action("Close exact values","close",list(source=active()$source))),
      lapply(jobs,function(j){
        shiny::div(class="brohn-stack",role="status",shiny::strong(if(j$operation=="signal_values_page")"Exact values"else"Complete selected CSV"),
          shiny::p(switch(j$status,queued="Queued. Your report remains available.",running="Reading and verifying the complete saved source.",cancelled="Cancelled. The original report and source are unchanged.",failed=paste("Could not prepare these values:",j$error$message),j$status)),
          if(j$status %in% c("queued","running"))brohn_command("Cancel exact-value processing","cancel_processing",j$id),
          if(j$status %in% c("failed","cancelled")) .brohn_sv_action("Retry exact-value processing",if(j$operation=="signal_values_page")"retry_page"else"retry_export",list(source=active()$source))) }))
  })
  output$signal_values_table<-shiny::renderUI({r<-ready();if(is.null(r))return(NULL);brohn_signal_values_page_ui(r,active()$source)})
  output$signal_values_detail<-shiny::renderUI({r<-detail();if(is.null(r))return(NULL)
    shiny::div(class="brohn-exact-values",shiny::h4(paste("Original typed fields for source row",r$table_row_index)),
      shiny::p("This unmodified row is from the complete saved artifact. Its JSON preserves native fields, null, boolean false and empty text."),
      shiny::tags$pre(tabindex="0",`aria-label`=paste("Exact original row",r$table_row_index),shiny::tags$span(r$exact_record_json)))})
  shiny::observeEvent(exported(),{r<-exported();if(is.null(r))return();download(NULL)
    # This route streams the immutable file through httpuv; no multi-GiB R copy,
    # parse or reserialization blocks active collection in the researcher session.
    token<-brohn_token();uri<-register_resource("brohn-exact-values",list(token=token,id=r$id,hash=.brohn_sv_hash(r$body)),function(data,req)shiny::isolate(tryCatch({
      brohn_require(req$REQUEST_METHOD %in% c("GET","HEAD")&&identical(shiny::parseQueryString(brohn_default(req$QUERY_STRING,""))$values_key,data$token),"This download link is no longer active.")
      guard(active());saved<-brohn_signal_values_record(store,data$id,data$hash)
      brohn_require(!is.null(exported())&&identical(exported()$id,saved$id),"Reopen the current prepared CSV.")
      ref<-saved$body$csv_object;path<-brohn_object_path(store,ref$hash,verify=FALSE);verified<-checks[["export"]]
      brohn_require(!is.null(verified)&&is.null(verified$process)&&identical(verified$record$id,saved$id),"Verify the prepared export before downloading.")
      for(g in verified$guards).Call(g$native$check,g$pointer)
      structure(list(status=200L,content_type="text/csv; charset=utf-8",content=list(file=path,owned=FALSE),headers=list(
        "Content-Disposition"=paste0('attachment; filename="',saved$id,'.csv"'),"Cache-Control"="no-store","X-Content-Type-Options"="nosniff")),class="httpResponse")
    },error=function(e){issue(conditionMessage(e));structure(list(status=404L,content_type="text/plain; charset=utf-8",content="This exact source download is unavailable. Reopen its report and prepare it again."),class="httpResponse")})))
    download(paste0(uri,"&values_key=",token))
  },ignoreNULL=TRUE)
  output$signal_values_download<-shiny::renderUI({r<-exported();url<-download();if(is.null(r)||is.null(url))return(NULL)
    shiny::div(class="brohn-exact-values",shiny::h3("Complete selected CSV ready"),shiny::p(class="brohn-exact-selection",.brohn_sv_selection_text(r$body$result)),
      shiny::p(paste(.brohn_sv_count(r$body$result$csv$rows),"source rows;",.brohn_sv_count(r$body$result$csv$bytes),"exact bytes.")),
      shiny::a(class="btn btn-primary",href=url,download=paste0(r$id,".csv"),"Download complete selected CSV"),
      shiny::downloadButton("signal_values_manifest","Download CSV source and schema",icon=NULL))})
  output$signal_values_manifest<-shiny::downloadHandler(filename=function()paste0(exported()$id,".json"),contentType="application/json",
    content=function(file)prepare_download(function(){guard(active());r<-brohn_signal_values_record(store,exported()$id,.brohn_sv_hash(exported()$body),verify=TRUE);brohn_copy_object_download(store,r$body$result_object$hash,file)}))
  invisible(list(clear=clear,active=active,ready=ready,exported=exported,detail=detail))
}
