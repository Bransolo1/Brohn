brohn_linked_review_svg <- function(result,width=900L) {
  escape<-function(x)as.character(htmltools::htmlEscape(as.character(x)))
  n<-length(result$tracks);if(!n)return(NULL)
  start<-as.numeric(result$selection$start_s);end<-as.numeric(result$selection$end_s);cursor<-as.numeric(result$selection$cursor_s)
  compact<-width==320L;left<-if(compact)58 else 90;right<-width-20
  x<-function(v)left+(v-start)/(end-start)*(right-left)
  pieces<-c(sprintf('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %s %s" role="img" aria-labelledby="linked-plot-title-%s linked-plot-description-%s" style="width:100%%;height:auto">',width,70+n*210,width,width),
    sprintf('<title id="linked-plot-title-%s">Measurements and event markers on one declared source clock</title>',width),
    sprintf('<desc id="linked-plot-description-%s">Each signal retains its own unit and vertical scale. Lines do not cross recorded segments or missing values. The orange line is the shared cursor. Complete exact observations are available below and in CSV.</desc>',width))
  for(i in seq_along(result$tracks)) {
    t<-result$tracks[[i]];top<-25+(i-1)*210;bottom<-top+160
    label<-if(compact)substr(t$channel$label,1,24)else substr(t$channel$label,1,70)
    pieces<-c(pieces,sprintf('<text x="8" y="%s" fill="#e7edf1" font-size="%s">%s \u00b7 %s</text>',top,if(compact)14 else 17,escape(label),escape(brohn_default(t$channel$unit,if(t$kind=="markers")"event"else"unit not declared"))),
      sprintf('<line x1="%s" x2="%s" y1="%s" y2="%s" stroke="#657985"/>',left,right,bottom,bottom),
      sprintf('<line x1="%s" x2="%s" y1="%s" y2="%s" stroke="#f1c785" stroke-width="2" stroke-dasharray="5 4"/>',x(cursor),x(cursor),top+15,bottom))
    if(t$kind=="markers") {
      for(m in t$markers)pieces<-c(pieces,sprintf('<line x1="%s" x2="%s" y1="%s" y2="%s" stroke="#b29fd8"/><circle cx="%s" cy="%s" r="5" fill="#b29fd8"><title>%s seconds: %s</title></circle>',
        x(m$x),x(m$x),top+45,bottom,x(m$x),top+45,escape(m$time_s),escape(m$label)))
    } else if(length(t$points)) {
      values<-vapply(t$points,`[[`,numeric(1),"y");bounds<-range(values);if(diff(bounds)==0)bounds<-bounds+c(-1,1)*max(1,abs(bounds[[1L]])*.05)
      y<-function(v)bottom-15-(v-bounds[[1L]])/diff(bounds)*110
      pieces<-c(pieces,sprintf('<text x="8" y="%s" fill="#a9bcc8" font-size="13">%s</text>',top+48,escape(format(bounds[[2L]],digits=4))),
        sprintf('<text x="8" y="%s" fill="#a9bcc8" font-size="13">%s</text>',bottom-15,escape(format(bounds[[1L]],digits=4))))
      for(run in unique(vapply(t$points,`[[`,numeric(1),"run"))) {
        points<-Filter(function(p)p$run==run,t$points)
        xy<-vapply(points,function(p)paste(x(p$x),y(p$y),sep=","),character(1))
        pieces<-c(pieces,sprintf('<polyline data-source-run="%s" fill="none" stroke="#86cbc5" stroke-width="2" points="%s"/>',run,paste(xy,collapse=" ")))
        if(length(points)==1L)pieces<-c(pieces,sprintf('<circle cx="%s" cy="%s" r="3" fill="#86cbc5"/>',x(points[[1L]]$x),y(points[[1L]]$y)))
      }
    }
    if(!t$selected_rows||t$display_limited)pieces<-c(pieces,sprintf('<text x="%s" y="%s" fill="#e7edf1" font-size="13">%s</text>',left,top+95,
      if(t$display_limited)"Use narrower window or CSV."else"No observations in this window."))
    for(v in seq(start,end,length.out=if(compact)3 else 5))pieces<-c(pieces,sprintf('<text x="%s" y="%s" text-anchor="%s" fill="#a9bcc8" font-size="13">%s</text>',x(v),bottom+21,if(v==start)"start"else if(v==end)"end"else"middle",escape(format(v,digits=6))))
  }
  pieces<-c(pieces,sprintf('<text x="%s" y="%s" text-anchor="middle" fill="#e7edf1" font-size="14">Seconds from the source anchor</text>',width/2,n*210+45),'</svg>')
  shiny::HTML(paste(pieces,collapse=""))
}
brohn_install_linked_review <- function(input,output,session,store,state,attempt,message,refresh,prepare_download) {
  opened<-shiny::reactiveVal(NULL);pending<-shiny::reactiveVal(NULL);offset<-shiny::reactiveVal(0L);issue<-shiny::reactiveVal(NULL);csv_url<-shiny::reactiveVal(NULL)
  native<-new.env(parent=emptyenv());native$guard<-NULL
  restoration<-new.env(parent=emptyenv());restoration$value<-NULL
  draft_state<-new.env(parent=emptyenv());draft_state$context<-NULL
  release<-function(){if(!is.null(native$guard)).brohn_qexplorer_release(native$guard);native$guard<-NULL;csv_url(NULL)}
  session$onSessionEnded(release)
  dataset<-function(){brohn_require(identical(state$page,"dataset"),"Open the original multistream recording before linked review.")
    d<-brohn_get_entity(store,"dataset",state$dataset_id);brohn_require(!is.null(d)&&identical(d$body$modality,"multimodal"),"Open a preserved multistream recording.");d}
  catalogs<-shiny::reactivePoll(1200,session,checkFunc=function(){if(!identical(state$page,"dataset")||is.null(state$dataset_id))return(NULL)
    d<-brohn_get_entity(store,"dataset",state$dataset_id);if(is.null(d)||!identical(d$body$modality,"multimodal"))return(NULL)
    brohn_hash(list(d$id,lapply(brohn_stream_imports(store,d$id,d$project_id,100),.brohn_linked_ref)))},valueFunc=function(){d<-dataset();brohn_linked_choices(store,d$id,d$project_id)})
  track_choices<-function(c,import_id){
    streams<-brohn_streams(store,import_id=import_id,project_id=c$dataset$project_id)
    choices<-character();for(s in streams)if(s$body$manifest$kind %in% c("signal","markers"))for(ch in s$body$manifest$channels){
      value<-brohn_json(list(stream_id=s$id,channel_id=ch$id));label<-paste(s$body$title,"/",ch$label,"\u00b7",brohn_default(ch$unit,"event/unlabelled unit"),"\u00b7 clock",s$body$manifest$clock$id)
      choices<-c(choices,stats::setNames(value,label))}
    choices}
  # Read the current draft only when its catalogue/context genuinely changes.
  # Typing and checking a track must not recreate the enclosing input controls.
  draft_snapshot<-shiny::reactive({shiny::req(identical(state$page,"dataset"));c<-catalogs()
    shiny::req(identical(c$dataset$id,state$dataset_id));if(!length(c$imports))return(NULL)
    ids<-vapply(c$imports,`[[`,character(1),"id");context<-list(dataset_id=c$dataset$id,project_id=c$dataset$project_id)
    current<-shiny::isolate(list(import=input$linked_import,tracks=brohn_default(input$linked_tracks,character()),
      start=brohn_default(input$linked_start,"0"),end=brohn_default(input$linked_end,"10"),cursor=brohn_default(input$linked_cursor,"0"),
      rationale=brohn_default(input$linked_clock_rationale,""),confirmed=isTRUE(input$linked_confirm)))
    preserve<-identical(draft_state$context,context)&&length(current$import)==1L&&current$import %in% ids&&
      all(current$tracks %in% unname(track_choices(c,current$import)))
    draft_state$context<-context
    if(!preserve){restoration$value<-NULL;opened(NULL);pending(NULL);offset(0L);issue(NULL);release()}
    values<-if(preserve)current else list(import=ids[[1L]],tracks=character(),start="0",end="10",cursor="0",rationale="",confirmed=FALSE)
    list(catalog=c,values=values,reset=!preserve,previous_import=current$import)})
  output$linked_review_entry<-shiny::renderUI({draft<-draft_snapshot();if(is.null(draft))return(NULL);c<-draft$catalog;v<-draft$values
    brohn_card(title="Review measurements with recorded events",subtitle="Inspect source-declared shared clocks with one time window and cursor. Synchronization accuracy remains unverified.",
      shiny::selectInput("linked_import","Preserved recording version",stats::setNames(vapply(c$imports,`[[`,character(1),"id"),vapply(c$imports,function(r)paste(r$body$created_at,substr(r$id,nchar(r$id)-7,nchar(r$id))),character(1))),selected=v$import,selectize=FALSE),
      shiny::uiOutput("linked_track_choices"),shiny::textAreaInput("linked_clock_rationale","Evidence that the selected tracks share this recording clock",value=v$rationale,rows=2),
      shiny::checkboxInput("linked_confirm","I reviewed the source clock and identity declarations; this does not establish physical synchronization accuracy.",v$confirmed),
      shiny::div(class="brohn-form-grid",shiny::textInput("linked_start","Window start (relative seconds)",v$start),
        shiny::textInput("linked_end","Window end (exclusive, relative seconds)",v$end),shiny::textInput("linked_cursor","Shared cursor (relative seconds)",v$cursor)),
      shiny::p("The first selected track supplies the exact original timestamp anchor. Different clock IDs, participant/session identities or ambiguous reset epochs require alignment; close timestamps do not qualify."),
      shiny::actionButton("linked_apply","Apply linked window",class="btn-primary"),shiny::uiOutput("linked_review_status"),shiny::uiOutput("linked_review_result"),brohn_linked_history_ui())})
  output$linked_track_choices<-shiny::renderUI({draft<-draft_snapshot();shiny::req(!is.null(draft));c<-draft$catalog
    reset<-draft$reset&&identical(input$linked_import,draft$previous_import)
    import_id<-if(reset)draft$values$import else input$linked_import;shiny::req(import_id)
    brohn_require(import_id %in% vapply(c$imports,`[[`,character(1),"id"),"Choose a preserved recording version.")
    choices<-track_choices(c,import_id)
    selected<-if(reset)character()else shiny::isolate(brohn_default(input$linked_tracks,character()));restore<-restoration$value
    if(!is.null(restore)&&identical(restore$dataset_id,state$dataset_id)&&identical(restore$import_id,input$linked_import)) {
      brohn_require(all(restore$tracks %in% unname(choices)),"The saved tracks are unavailable in this preserved recording version.")
      selected<-restore$tracks
    }
    shiny::checkboxGroupInput("linked_tracks","Signal and event tracks (choose 2 to 4)",choices,selected=selected[selected %in% unname(choices)])})
  # Acknowledgement changes no reactive dependency: it must not recreate the
  # checkbox group and overwrite the researcher's next edit.
  shiny::observeEvent(input$linked_tracks,{restore<-restoration$value
    if(!is.null(restore)&&identical(state$dataset_id,restore$dataset_id)&&identical(input$linked_import,restore$import_id)&&
      identical(as.list(input$linked_tracks),as.list(restore$tracks)))restoration$value<-NULL},ignoreNULL=FALSE)
  shiny::observeEvent(input$linked_import,{restore<-restoration$value
    if(!is.null(restore)&&!identical(input$linked_import,restore$import_id))restoration$value<-NULL},ignoreInit=TRUE)
  form<-function(){list(start_s=brohn_default(input$linked_start,""),end_s=brohn_default(input$linked_end,""),cursor_s=brohn_default(input$linked_cursor,""),offset=offset(),
    clock_rationale=brohn_default(input$linked_clock_rationale,""),confirmed=isTRUE(input$linked_confirm))}
  same<-function(record){isTRUE(identical(state$page,"dataset")&&identical(state$dataset_id,record$body$dataset_id)&&
    identical(input$linked_import,record$body$request$imported$id)&&identical(brohn_hash(form()),brohn_hash(record$body$request$selection))&&
    identical(brohn_hash(as.list(brohn_default(input$linked_tracks,character()))),brohn_hash(lapply(record$body$request$tracks,function(t)brohn_json(list(stream_id=t$stream$id,channel_id=t$channel_id))))))}
  active<-function(){r<-opened();brohn_require(!is.null(r)&&same(r),"Apply the current linked window or reopen its saved view before exporting.")
    d<-dataset();brohn_linked_history_open(store,.brohn_linked_ref(r),.brohn_linked_ref(d),d$project_id)}
  submit<-function(){d<-dataset();shiny::req(input$linked_import);tracks<-lapply(as.list(input$linked_tracks),brohn_parse)
    job<-brohn_queue_linked_review(store,d$id,input$linked_import,tracks,form(),d$project_id);pending(list(id=job$id,dataset_id=d$id));opened(NULL);release();issue(NULL)}
  shiny::observeEvent(input$linked_apply,attempt(function(){offset(0L);submit()}))
  shiny::observeEvent(input$linked_exact_page,attempt(function(){r<-active();next_offset<-input$linked_exact_page
    brohn_require(brohn_number(next_offset,0,max(0,r$body$result$selected_rows-1),TRUE)&&next_offset%%100==0,"Choose a current exact-value page.");offset(next_offset);submit()}))
  shiny::observeEvent(list(state$page,state$dataset_id),{opened(NULL);pending(NULL);offset(0L);issue(NULL);restoration$value<-NULL;draft_state$context<-NULL;release()},ignoreInit=FALSE,priority=110)
  shiny::observe({shiny::invalidateLater(1000,session);p<-pending();if(is.null(p)||!identical(state$page,"dataset")||!identical(state$dataset_id,p$dataset_id))return()
    j<-brohn_get_job(store,p$id);if(j$status=="succeeded"){d<-dataset();opened(brohn_linked_review_record(store,j$result$linked_review_id,d$id,d$project_id));pending(NULL)}
  })
  shiny::observeEvent(input$linked_retry,attempt(function(){p<-pending();brohn_require(!is.null(p)&&identical(state$dataset_id,p$dataset_id),"Reopen this recording before retrying.")
    j<-brohn_get_job(store,p$id);brohn_require(j$status %in% c("failed","cancelled"),"Only failed/cancelled linked views can retry.")
    retry<-brohn_enqueue_job(store,"linked_review",j$request,paste0("retry-linked:",j$id,":",brohn_id("request")));pending(list(id=retry$id,dataset_id=p$dataset_id))}))
  shiny::observeEvent(input$linked_cancel,attempt(function(){p<-pending();brohn_require(!is.null(p)&&identical(state$dataset_id,p$dataset_id),"Reopen this recording before cancelling.");brohn_cancel_job(store,p$id)}))
  output$linked_review_status<-shiny::renderUI({shiny::invalidateLater(1000,session);p<-pending()
    if(!is.null(issue()))return(shiny::p(class="brohn-alert",role="status",issue()))
    if(is.null(p))return(NULL);j<-brohn_get_job(store,p$id)
    shiny::div(role="status",shiny::p(paste("Linked review:",j$status)),if(!is.null(j$error))shiny::p(j$error$message),
      if(j$status %in% c("queued","running"))shiny::actionButton("linked_cancel","Cancel linked view")else if(j$status %in% c("failed","cancelled"))shiny::actionButton("linked_retry","Retry linked view"))})
  shiny::observeEvent(opened(),{release();r<-opened();if(is.null(r)||is.null(r$body$csv_object))return()
    ref<-r$body$csv_object;path<-brohn_object_path(store,ref$hash,verify=FALSE);native$guard<-.brohn_qexplorer_hold(path,ref$size)
    brohn_require(identical(digest::digest(file=path,algo="sha256"),ref$hash),"The prepared linked CSV failed its sealed hash check.")
    token<-brohn_token();uri<-session$registerDataObj("linked-window",list(id=r$id,token=token),function(data,req)shiny::isolate(tryCatch({
      brohn_require(req$REQUEST_METHOD %in% c("GET","HEAD")&&identical(shiny::parseQueryString(brohn_default(req$QUERY_STRING,""))$key,data$token),"Expired linked download.")
      saved<-active();brohn_require(identical(saved$id,data$id)&&!is.null(native$guard),"The linked window changed.");.Call(native$guard$native$check,native$guard$pointer)
      structure(list(status=200L,content_type="text/csv; charset=utf-8",content=list(file=path,owned=FALSE),headers=list("Cache-Control"="no-store","X-Content-Type-Options"="nosniff","Content-Disposition"='attachment; filename="linked-window.csv"')),class="httpResponse")
    },error=function(e)structure(list(status=404L,content_type="text/plain",content="This linked-window download is no longer current. Reopen the saved view."),class="httpResponse"))))
    csv_url(paste0(uri,"&key=",token))},ignoreNULL=TRUE)
  output$linked_review_result<-shiny::renderUI({r<-opened();if(is.null(r))return(NULL);if(!same(r))return(shiny::p(role="status","The selection changed. Apply linked window to inspect or export those inputs."))
    b<-r$body$result
    if(b$status=="requires_alignment")return(shiny::div(class="brohn-alert",role="status",shiny::h3("These tracks require alignment"),
      shiny::tags$ul(lapply(b$issues,function(i)shiny::tags$li(i$reason))),shiny::p("Remove the ambiguous track or provide a recording with retained shared epoch/alignment evidence. This view does not fit a clock map or export an invented overlay.")))
    shiny::tagList(shiny::h3("Linked source timeline"),shiny::p(paste("Source-declared shared clock",b$clock$id,"\u00b7",r$body$origin,"\u00b7 synchronization accuracy unverified")),
      shiny::p(paste("Exact source anchor:",b$anchor_timestamp,b$anchor_unit,". Window is start-inclusive and end-exclusive. No correction, resampling or interpolation was applied.")),
      shiny::div(class="brohn-linked-plot",shiny::div(class="brohn-signal-wide",brohn_linked_review_svg(b)),
        shiny::div(class="brohn-signal-compact",brohn_linked_review_svg(b,320L))),
      lapply(b$tracks,function(t)shiny::div(shiny::h4(paste(t$title,"/",t$channel$label)),
        shiny::p(paste(t$selected_rows,"window rows of",t$source_rows,"source rows;",t$missing_values,"missing values in this window;",t$unplaced_source_rows,"source rows have no observed placeable timestamp.")),
        shiny::p(paste(length(t$segments),"source segments in this window.",t$display_policy)),
        if(t$kind=="markers"&&length(t$markers))brohn_table(lapply(t$markers,function(m)list(time_s=m$time_s,event=m$label)),
          label="Recorded event context",maximum=200L),
        if(length(t$segments))brohn_table(lapply(t$segments,function(s)s[c("id","first_sequence","last_sequence","boundary_reasons")]),label=paste("Recorded boundaries for",t$channel$label),maximum=10L),
        shiny::tags$details(shiny::tags$summary(paste("Recorded observations around the shared cursor:",t$channel$label)),
          shiny::p("Before/after are observed samples within the selected window, not an interpolated value or verified event latency."),brohn_table(Filter(Negate(is.null),t$cursor),columns=c("source_sequence","relative_time_s","value_json","value_state"),label=paste("Cursor observations for",t$channel$label))))),
      shiny::h3("Exact selected observations"),shiny::p(paste("Showing",if(length(b$rows))b$selection$offset+1 else 0,"to",b$selection$offset+length(b$rows),"of",b$selected_rows,"rows in track order. Complete CSV retains every selected row and its native source timestamp.")),
      brohn_table(b$rows,columns=c("track_id","source_sequence","relative_time_s","value_json","value_state","unit"),maximum=100L,label="Exact linked window observations"),
      shiny::div(class="brohn-toolbar",if(b$selection$offset>0)brohn_command("Previous exact observations","linked_exact_page",b$selection$offset-100),
        if(b$selection$offset+length(b$rows)<b$selected_rows)brohn_command("Next exact observations","linked_exact_page",b$selection$offset+100),
        if(!is.null(csv_url()))shiny::tags$a(href=csv_url(),download="linked-window.csv",class="btn btn-primary","Download complete linked CSV"),
        shiny::downloadButton("linked_manifest","Download linked source manifest",icon=NULL)))})
  output$linked_manifest<-shiny::downloadHandler(filename=function()paste0(active()$id,".json"),contentType="application/json",content=function(file)prepare_download(function()brohn_write_json_file(active()$body,file)))
  restore_saved<-function(r){s<-r$body$request$selection
    tracks<-vapply(r$body$request$tracks,function(t)brohn_json(list(stream_id=t$stream$id,channel_id=t$channel_id)),character(1))
    same_import<-identical(input$linked_import,r$body$request$imported$id)
    restoration$value<-if(same_import&&identical(as.list(input$linked_tracks),as.list(tracks)))NULL else
      list(dataset_id=r$body$dataset_id,import_id=r$body$request$imported$id,tracks=tracks)
    shiny::updateSelectInput(session,"linked_import",selected=r$body$request$imported$id)
    # When the import changes its newly rendered checkbox group receives the
    # selected values directly. Do not race an update against that replacement.
    if(same_import)shiny::updateCheckboxGroupInput(session,"linked_tracks",selected=tracks)
    shiny::updateTextInput(session,"linked_start",value=s$start_s);shiny::updateTextInput(session,"linked_end",value=s$end_s);shiny::updateTextInput(session,"linked_cursor",value=s$cursor_s)
    shiny::updateTextAreaInput(session,"linked_clock_rationale",value=s$clock_rationale);shiny::updateCheckboxInput(session,"linked_confirm",value=TRUE);offset(s$offset);pending(NULL);opened(r)}
  history_scope<-shiny::reactive({if(!identical(state$page,"dataset")||is.null(state$dataset_id))return(NULL)
    d<-brohn_get_entity(store,"dataset",state$dataset_id);if(is.null(d)||!identical(d$body$modality,"multimodal"))return(NULL)
    list(dataset_ref=.brohn_linked_ref(d),project_id=d$project_id,import_ref=NULL)})
  history<-brohn_install_linked_history(input,output,session,store,history_scope,restore_saved,attempt)
  invisible(list(active=active,history=history))
}
