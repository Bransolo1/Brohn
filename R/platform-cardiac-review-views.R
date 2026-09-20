# Source-bound cardiac exclusions. No display points enter numerical analysis.
.brohn_cardiac_ui_identity <- function(r) paste(r$id,r$revision,brohn_hash(r$body),sep=":")
.brohn_cardiac_action <- function(label,action,payload=list(),primary=FALSE) shiny::tags$button(type="button",
  class=if(primary)"btn btn-primary"else"btn btn-outline-secondary",`data-cardiac-action`=action,
  `data-cardiac-payload`=brohn_json(payload),label)
.brohn_cardiac_reason <- function(x) switch(x,signal_loss="Signal loss",clipping="Clipping",movement_or_distortion="Movement or distortion",researcher_exclusion="Researcher exclusion",x)
.brohn_cardiac_rows <- function(spans) lapply(spans,function(x) list(start_sample=brohn_signal_exact_number(x$start_sample),
  end_sample=brohn_signal_exact_number(x$end_sample),samples=brohn_signal_exact_number(x$end_sample-x$start_sample),
  first_time_s=brohn_signal_exact_number(x$first_time_s),last_time_s=brohn_signal_exact_number(x$last_time_s),reason=.brohn_cardiac_reason(x$reason),note=x$note))
.brohn_cardiac_runs <- function(runs) lapply(seq_along(runs),function(i){x<-runs[[i]]
  fields<-c("start_sample","end_sample","samples","first_time_s","last_time_s","predicted_retained_samples")
  c(list(run=paste("Run",i)),setNames(lapply(x[fields],brohn_signal_exact_number),fields),
    list(status=switch(x$status,ready_to_attempt="Ready to calculate",insufficient_support="Insufficient support",brohn_signal_label(x$status)),reason=brohn_default(x$reason,"\u2014")))})
.brohn_cardiac_table <- function(...) shiny::tagList(shiny::p(class="brohn-muted","Scroll the table horizontally to see every exact value. Keyboard: focus the table, then use the arrow keys."),brohn_table(...))

brohn_cardiac_input_svg <- function(preview,width=820) {
  fragments<-preview$fragments;points<-unlist(lapply(fragments,`[[`,"points"),recursive=FALSE)
  if(!length(points))return(shiny::p("No input samples available in this preview."))
  xs<-vapply(points,`[[`,numeric(1),"time_s");ys<-vapply(points,`[[`,numeric(1),"value")
  xr<-range(xs);yr<-range(ys);if(diff(xr)==0)xr<-xr+c(-.5,.5);if(diff(yr)==0)yr<-yr+c(-.5,.5)
  yr<-yr+c(-1,1)*diff(yr)*.06;left<-65;right<-width-20;top<-22;bottom<-240
  sx<-function(x)left+(x-xr[[1]])/diff(xr)*(right-left);sy<-function(y)bottom-(y-yr[[1]])/diff(yr)*(bottom-top)
  colors<-c(parent_retained="#a7e9d3",parent_filter_edge="#e8c87a",researcher_excluded="#fa9a91")
  labels<-c(parent_retained="Input within parent's retained support",parent_filter_edge="Input at parent's filter edge",researcher_excluded="Researcher excluded input")
  shiny::tags$svg(xmlns="http://www.w3.org/2000/svg",viewBox=paste(0,0,width,300),width="100%",role="img",
    `aria-label`="Original cardiac input with distinct researcher exclusions and parent filter edges",style="display:block;max-width:100%;background:#131d24;font-family:system-ui,sans-serif",
    shiny::tags$desc("Each path contains only observed input samples within one status fragment. Paths never join across exclusions. The complete source, not this display, supplies the calculation."),
    lapply(seq(yr[[1]],yr[[2]],length.out=4),function(y)shiny::tagList(shiny::tags$line(x1=left,x2=right,y1=sy(y),y2=sy(y),stroke="#3f5058"),
      shiny::tags$text(x=left-8,y=sy(y)+4,`text-anchor`="end",fill="#d2dedd",`font-size`=11,brohn_signal_number(y)))),
    lapply(fragments,function(f){p<-f$points;if(!length(p))return(NULL);color<-colors[[f$status]]
      coordinates<-vapply(p,function(a)paste(format(sx(a$time_s),digits=12,trim=TRUE),format(sy(a$value),digits=12,trim=TRUE),sep=","),character(1))
      shiny::tagList(shiny::tags$polyline(points=paste(coordinates,collapse=" "),fill="none",stroke=color,`stroke-width`=1.6,
        shiny::tags$title(paste(labels[[f$status]],"| source rows",f$source_start_sample,"to",f$source_end_sample,"(end excluded)"))),
        if(length(p)==1L)shiny::tags$circle(cx=sx(p[[1]]$time_s),cy=sy(p[[1]]$value),r=3,fill=color))}),
    lapply(seq(xr[[1]],xr[[2]],length.out=if(width<560)2 else 5),function(x)shiny::tags$text(x=sx(x),y=264,`text-anchor`="middle",fill="#d2dedd",`font-size`=11,brohn_signal_number(x))),
    shiny::tags$text(x=(left+right)/2,y=289,`text-anchor`="middle",fill="#edf5f3",`font-size`=13,"Recording-relative time (s)"),
    shiny::tags$text(x=left,y=14,fill="#edf5f3",`font-size`=12,paste("Input (",preview$unit,")")))
}

brohn_install_cardiac_review_ui <- function(input,output,session,store,state,attempt,message,prepare_download,context,catalog,table) {
  active<-shiny::reactiveVal(NULL);editing<-shiny::reactiveVal(NULL);epoch<-shiny::reactiveVal(0L);tick<-shiny::reactiveVal(0L)
  preview<-shiny::reactiveVal(NULL);resolution<-shiny::reactiveVal(NULL);history<-shiny::reactiveVal(NULL);result<-shiny::reactiveVal(NULL)
  saved_results<-shiny::reactiveVal(list())
  pending<-shiny::reactiveVal(NULL);issue<-shiny::reactiveVal(NULL);visible<-shiny::reactiveVal(NULL)
  clear<-function(){active(NULL);editing(NULL);preview(NULL);resolution(NULL);history(NULL);result(NULL);saved_results(list());pending(NULL);issue(NULL);visible(NULL)}
  shiny::observeEvent(list(state$page,state$report_id,input$signal_table),clear(),ignoreInit=FALSE,priority=100)
  source_key<-shiny::reactive({r<-context();c<-catalog();t<-table();paste(.brohn_cardiac_ui_identity(r),.brohn_cardiac_ui_identity(c),brohn_hash(t),sep="|" )})
  eligible<-function(){r<-context();c<-catalog();t<-table();r$body$analysis$kind%in%c("ecg","ppg")&&is.null(r$body$analysis$exclusion_review)&&
    identical(c$body$view$artifact$kind,"physiology-series")&&identical(t$coordinates$axis,"time")}
  # Cache only the render snapshot. Every mutation/queue and download separately
  # reopens the domain record so authority and current revision remain checked.
  selected<-shiny::reactive({r<-active();brohn_require(!is.null(r),"Create or open an artifact review first.")
    saved<-brohn_cardiac_review(store,r$id,r$revision,brohn_hash(r$body));c<-context();t<-table()
    brohn_require(identical(saved$project_id,c$project_id)&&identical(saved$body$report_id,c$id)&&identical(saved$body$report_hash,brohn_hash(c$body))&&
      identical(brohn_hash(saved$body$table),brohn_hash(t)),"Reopen the artifact review for this exact recording.");saved})
  authorized_selected<-function(){r<-selected();brohn_cardiac_review(store,r$id,r$revision,brohn_hash(r$body))}
  baseline<-function(){r<-selected();span<-Filter(function(x)identical(x$id,editing()),r$body$spans);span<-if(length(span))span[[1]]else NULL;s<-r$body$table$support$source
    list(mode=if(is.null(span))"time"else"samples",start_time="",end_time="",start_sample=brohn_signal_exact_number(brohn_default(span$start_sample,s$source_row_start)),
      end_sample=brohn_signal_exact_number(brohn_default(span$end_sample,s$source_row_start+1)),reason=brohn_default(span$reason,"signal_loss"),note=brohn_default(span$note,""))}
  form_key<-function(){r<-selected();paste(.brohn_cardiac_ui_identity(r),brohn_default(editing(),"new"),epoch(),sep="|")}
  protect<-function(fn)attempt(function(){issue(NULL);tryCatch(fn(),error=function(e){issue(conditionMessage(e));stop(e)})})
  command_record<-function(cmd,unchanged=FALSE){brohn_require(is.list(cmd)&&identical(cmd$source,source_key()),"That action belongs to another recording. Reopen its review.")
    r<-selected();brohn_require(identical(cmd$form,form_key()),"The review or editor changed. Use the current saved version.")
    latest<-brohn_cardiac_review(store,r$id);brohn_require(identical(.brohn_cardiac_ui_identity(latest),.brohn_cardiac_ui_identity(r)),"This review changed in another action. Open its current saved version before continuing.")
    brohn_fields(cmd$fields,names(baseline()),label="Visible exclusion form")
    brohn_require(all(vapply(cmd$fields,is.character,logical(1)))&&cmd$fields$mode%in%c("time","samples"),"Wait for the complete exclusion editor.")
    if(unchanged)brohn_require(identical(brohn_hash(cmd$fields),brohn_hash(baseline())),"Save or cancel the visible exclusion edits before previewing or recalculating saved decisions.")
    visible(cmd$fields);r}
  activate<-function(r){active(r);editing(NULL);epoch(epoch()+1L);preview(NULL);resolution(NULL);history(NULL);result(NULL);pending(NULL);visible(NULL);tick(tick()+1L)
    results<-brohn_list_entities(store,"report",r$project_id,limit=100L,filters=list("analysis.exclusion_review.review_source.id"=r$id))
    saved_results(results);matching<-Filter(function(x)identical(brohn_hash(x$body$analysis$exclusion_review$review_source),brohn_hash(list(id=r$id,revision=r$revision,hash=brohn_hash(r$body)))),results)
    if(length(matching))result(matching[[1L]])}
  start_job<-function(job,kind,cmd){if(job$status%in%c("failed","cancelled"))job<-brohn_retry_processing(store,job$id)
    pending(list(id=job$id,kind=kind,source=source_key(),form=form_key(),fields=cmd$fields,review=.brohn_cardiac_ui_identity(selected())));job}
  resume_resolution<-function(cmd){p<-pending();if(is.null(p)||!identical(p$kind,"resolve")||!identical(p$source,source_key())||!identical(p$form,form_key())||!identical(brohn_hash(p$fields),brohn_hash(cmd$fields)))return(FALSE)
    j<-brohn_get_job(store,p$id);if(j$status%in%c("failed","cancelled")){j<-brohn_retry_processing(store,j$id);p$id<-j$id;pending(p);return(TRUE)}
    j$status%in%c("queued","running")}
  output$signal_cardiac_review<-shiny::renderUI({if(!eligible())return(NULL);r<-context();t<-table();tick()
    if(!identical(t$support$raw_source_omitted,FALSE))return(brohn_card(title="Review cardiac artifacts",shiny::p("This historical report has no preserved input waveform. Run a new original analysis before creating exclusions.")))
    records<-brohn_list_entities(store,"cardiac_review",r$project_id,limit=100L,filters=list(report_id=r$id,"table.table_id"=t$table_id))
    shiny::div(id="cardiac-review-ui",`data-source`=source_key(),class="brohn-stack",style="min-width:0;grid-template-columns:minmax(0,1fr)",
      shiny::tags$script(src="cardiac-review-ui.js"),
      shiny::tags$style("#cardiac-review-ui .shiny-html-output {min-width:0} #cardiac-review-ui .brohn-stack {grid-template-columns:minmax(0,1fr)} #cardiac-review-ui p {overflow-wrap:anywhere} #cardiac-review-ui .brohn-table table {min-width:700px;table-layout:auto} #cardiac-review-ui th,#cardiac-review-ui td {white-space:nowrap;overflow-wrap:normal;word-break:normal}"),
      brohn_card(title="Review cardiac artifacts",subtitle="Exclude clearly identified input spans and calculate a separate report. Original sources and earlier reports stay preserved.",
        shiny::p(paste("Selected channel:",brohn_default(t$identity$channel,"Unspecified"),"|",brohn_default(t$identity$recording_id,"Selected recording"))),
        shiny::div(class="brohn-form-grid",shiny::textInput("cardiac_title","New artifact review name","Artifact review"),
          shiny::div(class="form-group",shiny::p("Start a separate review"),.brohn_cardiac_action("Create artifact review","create",primary=TRUE))),
        if(length(records))shiny::div(class="brohn-form-grid",shiny::selectInput("cardiac_choice","Saved artifact reviews (up to 100 most recent)",
          c("Choose a saved review"="",setNames(vapply(records,`[[`,character(1),"id"),vapply(records,function(x)paste(x$body$title,"| version",x$revision),character(1)))),selectize=FALSE),
          .brohn_cardiac_action("Open artifact review","open")),
        shiny::p(class="brohn-muted","ECG remains detected RR; PPG remains detected PRV. Excluding samples does not confirm normal beats or physiological validity.")),
      shiny::uiOutput("cardiac_review_editor"),shiny::uiOutput("cardiac_review_progress"),shiny::uiOutput("cardiac_review_resolution"),shiny::uiOutput("cardiac_review_preview"),shiny::uiOutput("cardiac_review_result"))
  })
  output$cardiac_review_editor<-shiny::renderUI({if(is.null(active()))return(NULL);r<-selected();b<-baseline();identity<-form_key();s<-r$body$table$support$source
    brohn_card(title=r$body$title,subtitle=paste("Saved version",r$revision,"|",length(r$body$spans),"exclusions"),
      shiny::div(`data-cardiac-form`=identity,
        shiny::selectInput("cardiac_mode","Exclusion boundaries",c("Recording-relative seconds"="time","Exact source rows (advanced)"="samples"),selected=b$mode,selectize=FALSE),
        shiny::conditionalPanel("input.cardiac_mode == 'time'",shiny::div(class="brohn-form-grid",shiny::textInput("cardiac_start_time","Start time in seconds (included)",b$start_time),shiny::textInput("cardiac_end_time","End time in seconds (excluded)",b$end_time)),
          shiny::p(class="brohn-muted","Enter decimal seconds relative to this recording's declared source origin, as on its waveform axis. Preview resolves actual source rows. Use source rows to include the final observed sample.")),
        shiny::conditionalPanel("input.cardiac_mode == 'samples'",shiny::div(class="brohn-form-grid",shiny::textInput("cardiac_start_sample","First source row (included)",b$start_sample),shiny::textInput("cardiac_end_sample","End source row (excluded)",b$end_sample)),
          shiny::p(class="brohn-muted",paste("Zero-based analysis-input rows, excluding the CSV header. Available bounds:",brohn_signal_exact_number(s$source_row_start),"to",brohn_signal_exact_number(s$source_row_end_exclusive),"(end excluded). Curated acquisition sequence numbers are separate."))),
        shiny::selectInput("cardiac_reason","Reason for this exclusion",c("Signal loss"="signal_loss","Clipping"="clipping","Movement or distortion"="movement_or_distortion","Researcher exclusion"="researcher_exclusion"),b$reason,selectize=FALSE),
        shiny::textAreaInput("cardiac_note","Exclusion note (required for researcher exclusion)",b$note,rows=2),
        shiny::div(class="brohn-toolbar",shiny::conditionalPanel("input.cardiac_mode == 'time'",.brohn_cardiac_action("Preview exclusion","resolve",primary=TRUE)),
          shiny::conditionalPanel("input.cardiac_mode == 'samples'",.brohn_cardiac_action(if(is.null(editing()))"Save source-row exclusion"else"Save exclusion changes","save_samples",primary=TRUE)),
          .brohn_cardiac_action("Cancel exclusion edits","reset")),
        if(length(r$body$spans))shiny::tags$details(open=NA,shiny::tags$summary("Saved exclusions"),
          lapply(r$body$spans,function(x)shiny::div(class="brohn-stack",shiny::strong(paste(.brohn_cardiac_reason(x$reason),"| rows",brohn_signal_exact_number(x$start_sample),"to",brohn_signal_exact_number(x$end_sample),"(end excluded)")),
            if(nzchar(x$note))shiny::p(x$note),shiny::div(class="brohn-toolbar",.brohn_cardiac_action("Edit exclusion","edit",list(id=x$id)),.brohn_cardiac_action("Remove exclusion","remove",list(id=x$id)))))),
        shiny::div(class="brohn-toolbar",.brohn_cardiac_action("Preview recalculation","preview",primary=TRUE),shiny::downloadButton("cardiac_review_json","Download saved exclusions",icon=NULL)),
        shiny::p(class="brohn-muted","Save visible edits first. The preview reads the complete original input and reports remaining separate runs, including new filter edges. It predicts available support, not cardiac scores."),
        if(r$revision>1L)shiny::tags$details(shiny::tags$summary("Review or restore earlier exclusions"),
          shiny::textInput("cardiac_history_revision","Earlier saved version",as.character(r$revision-1L)),.brohn_cardiac_action("Inspect earlier version","history"),shiny::uiOutput("cardiac_review_history")),
        shiny::tags$details(shiny::tags$summary("Source, clock and review attribution"),shiny::p(r$body$review_attribution),
          brohn_table(list(list(report=r$body$report_id,report_revision=r$body$report_revision,dataset=r$body$dataset_id,dataset_revision=r$body$dataset_revision,
            table=r$body$table$table_id,clock=brohn_json(r$body$table$coordinates),review_hash=brohn_hash(r$body))),label="Exact cardiac review source and version"))))
  })
  shiny::observeEvent(input$cardiac_ui_dirty,{cmd<-input$cardiac_ui_dirty;if(is.null(active()))return()
    valid<-tryCatch(identical(cmd$source,source_key())&&identical(cmd$form,form_key()),error=function(e)FALSE)
    if(valid){visible(cmd$fields);preview(NULL);resolution(NULL)}
  },ignoreInit=TRUE,priority=100)
  shiny::observeEvent(input$cardiac_ui_action,protect(function(){cmd<-input$cardiac_ui_action
    brohn_require(is.list(cmd)&&identical(cmd$source,source_key())&&eligible(),"Reopen the exact cardiac recording before this action.")
    if(cmd$action=="create"){r<-brohn_create_cardiac_review(store,catalog()$id,table()$table_id,cmd$title);activate(r);message("Artifact review created. Choose an exclusion or preview the original support.");return()}
    if(cmd$action=="open"){r<-brohn_cardiac_review(store,cmd$choice);brohn_require(identical(r$project_id,context()$project_id)&&identical(r$body$report_id,context()$id)&&identical(brohn_hash(r$body$table),brohn_hash(table())),"Choose a review of this exact recording.");activate(r);message("Saved artifact review opened.");return()}
    r<-command_record(cmd,cmd$action%in%c("preview","recalculate","history","restore"));f<-cmd$fields
    if(cmd$action=="reset"){editing(NULL);epoch(epoch()+1L);preview(NULL);resolution(NULL);visible(NULL);return()}
    if(cmd$action%in%c("edit","remove")){brohn_require(cmd$payload$id%in%brohn_ids(r$body$spans),"Choose a saved exclusion.")
      if(cmd$action=="remove")activate(brohn_remove_cardiac_span(store,r$id,r$revision,cmd$payload$id))else{editing(cmd$payload$id);epoch(epoch()+1L);preview(NULL);resolution(NULL);visible(NULL)};return()}
    if(cmd$action=="save_samples"){brohn_require(identical(f$mode,"samples")&&grepl("^[0-9]+$",f$start_sample)&&grepl("^[0-9]+$",f$end_sample),"Enter whole source row bounds.")
      activate(brohn_save_cardiac_span(store,r$id,r$revision,as.numeric(f$start_sample),as.numeric(f$end_sample),f$reason,f$note,editing()));message("Exclusion saved as a new review version.");return()}
    if(cmd$action=="resolve"){brohn_require(identical(f$mode,"time"),"Choose original recording seconds before resolving times.")
      resolution(NULL);preview(NULL);if(resume_resolution(cmd)){message("Retrying the same saved time-resolution request.");return()};job<-brohn_queue_cardiac_resolution(store,r$id,r$revision,brohn_hash(r$body),f$start_time,f$end_time,f$reason,f$note,editing());start_job(job,"resolve",cmd);message("Resolving exact source rows for these original times.");return()}
    if(cmd$action=="accept_resolution"){v<-resolution();brohn_require(!is.null(v)&&identical(cmd$payload$id,v$record$id)&&identical(brohn_hash(f),brohn_hash(v$fields)),"The visible exclusion changed. Preview it again before saving.")
      activate(brohn_accept_cardiac_resolution(store,v$record$id,r$revision));message("Resolved exclusion saved as a new version.");return()}
    if(cmd$action=="preview"){preview(NULL);resolution(NULL);job<-brohn_queue_cardiac_review(store,r$id,r$revision,brohn_hash(r$body));start_job(job,"preview",cmd);message("Previewing complete input and remaining support.");return()}
    if(cmd$action=="recalculate"){p<-preview();brohn_require(!is.null(p)&&identical(cmd$payload$id,p$id)&&identical(brohn_hash(p$body$review_source),brohn_hash(list(id=r$id,revision=r$revision,hash=brohn_hash(r$body)))),"Preview this exact saved review before recalculating.")
      job<-brohn_queue_cardiac_review(store,r$id,r$revision,brohn_hash(r$body),p$id);start_job(job,"recalculate",cmd);message("Recalculating separate surviving runs from original input.");return()}
    if(cmd$action=="history"){brohn_require(grepl("^[0-9]+$",cmd$history)&&brohn_number(as.numeric(cmd$history),1,r$revision-1,TRUE),"Choose an earlier saved version.");history(brohn_cardiac_review(store,r$id,as.numeric(cmd$history)));return()}
    if(cmd$action=="restore"){h<-history();brohn_require(!is.null(h)&&identical(cmd$payload$hash,brohn_hash(h$body))&&identical(cmd$payload$revision,h$revision),"Inspect this earlier version before restoring.")
      activate(brohn_restore_cardiac_review(store,r$id,r$revision,h$revision,brohn_hash(h$body)));message("Earlier exclusions restored as a new current version.");return()}
    brohn_require(FALSE,"Choose an available artifact review action.")
  }))
  output$cardiac_review_history<-shiny::renderUI({h<-history();if(is.null(h))return(NULL);r<-selected()
    brohn_require(identical(h$id,r$id)&&h$revision<r$revision,"Inspect an earlier version of this review.")
    shiny::tagList(shiny::p(paste("Version",h$revision,"has",length(h$body$spans),"exclusions. Restore creates a new version and preserves existing reports.")),
      .brohn_cardiac_table(.brohn_cardiac_rows(h$body$spans),columns=c("start_sample","end_sample","samples","reason","note"),labels=c("First source row","End row (excluded)","Samples","Reason","Note"),maximum=64L,label=paste("Exclusions in cardiac review version",h$revision)),
      .brohn_cardiac_action(paste("Restore exclusion version",h$revision),"restore",list(revision=h$revision,hash=brohn_hash(h$body))))
  })
  job<-shiny::reactive({p<-pending();if(is.null(p))return(NULL);j<-brohn_get_job(store,p$id);if(j$status%in%c("queued","running"))shiny::invalidateLater(800,session);j})
  shiny::observe({j<-job();if(is.null(j)||j$status!="succeeded")return();p<-pending();if(isTRUE(p$handled))return()
    current<-tryCatch(identical(p$source,source_key())&&identical(p$form,form_key())&&identical(p$review,.brohn_cardiac_ui_identity(selected()))&&
      identical(p$review,.brohn_cardiac_ui_identity(brohn_cardiac_review(store,selected()$id)))&&
      identical(brohn_hash(p$fields),brohn_hash(brohn_default(visible(),baseline()))),error=function(e)FALSE)
    if(!current)return()
    if(p$kind=="recalculate"){value<-brohn_get_entity(store,"report",j$result$report_id);if(!identical(result(),value)){result(value);saved_results(c(list(value),Filter(function(x)!identical(x$id,value$id),saved_results())))}}else{
      value<-brohn_get_entity(store,"cardiac_review_preview",j$result$cardiac_preview_id)
      if(p$kind=="resolve"){v<-list(record=value,fields=p$fields);if(!identical(resolution(),v))resolution(v)}else if(!identical(preview(),value))preview(value)
    }
    p$handled<-TRUE;pending(p)
  })
  output$cardiac_review_progress<-shiny::renderUI({j<-job();error<-issue();shiny::tagList(
    if(!is.null(error))shiny::div(class="brohn-alert brohn-alert-error",role="alert",error),
    if(!is.null(j)&&j$status!="succeeded")brohn_card(title="Artifact review progress",shiny::p(switch(j$status,queued="Queued",running="Reading complete original samples",failed="Calculation needs attention",cancelled="Calculation cancelled",j$status)),
      if(!is.null(j$error))shiny::p(j$error$message),if(j$status%in%c("queued","running"))brohn_command("Cancel artifact calculation","cancel_processing",j$id),
      if(j$status%in%c("failed","cancelled"))shiny::p("The saved exclusions and original report remain available. Repeat the same action to retry its frozen request.")))})
  output$cardiac_review_resolution<-shiny::renderUI({v<-resolution();if(is.null(v))return(NULL);r<-selected();x<-v$record$body$preview$resolved_exclusion
    brohn_require(!is.null(x)&&identical(v$record$body$review_source$id,r$id)&&v$record$body$review_source$revision==r$revision,"Resolve this saved review version again.")
    shiny::div(`data-cardiac-current-preview`="resolution",brohn_card(title="Resolved exclusion",shiny::p(paste("Exactly",x$samples,"source samples. Check the actual first and last included samples before saving.")),
      .brohn_cardiac_table(list(list(first_source_row=brohn_signal_exact_number(x$span$start_sample),end_source_row_excluded=brohn_signal_exact_number(x$span$end_sample),first_time_s=brohn_default(x$first_time_s_text,brohn_signal_exact_number(x$first_time_s)),last_time_s=brohn_default(x$last_time_s_text,brohn_signal_exact_number(x$last_time_s)),reason=.brohn_cardiac_reason(x$span$reason),note=x$span$note)),labels=c("First source row","End row (excluded)","First time (s)","Last time (s)","Reason","Note"),label="Exact resolved exclusion samples and original times"),
      .brohn_cardiac_action("Save resolved exclusion","accept_resolution",list(id=v$record$id),TRUE)))
  })
  valid_preview<-function(){p<-preview();r<-selected();brohn_require(!is.null(p)&&identical(p$project_id,r$project_id)&&identical(brohn_hash(p$body$review_source),brohn_hash(list(id=r$id,revision=r$revision,hash=brohn_hash(r$body)))),"Preview the current saved review version.");p}
  output$cardiac_review_preview<-shiny::renderUI({if(is.null(preview()))return(NULL);p<-valid_preview();v<-p$body$preview;l<-v$ledger;s<-l$support
    shiny::div(`data-cardiac-current-preview`="calculation",brohn_card(title="Recalculation preview",subtitle=paste("Saved review version",p$body$review_source$revision,"|",s$excluded_samples,"excluded of",s$input_samples,"input samples"),
      shiny::p(paste(length(l$runs),"separate remaining runs;",s$predicted_retained_samples,"samples predicted after independent filter edges. This is support, not a predicted cardiac score.")),
      shiny::div(class="brohn-signal-wide",brohn_cardiac_input_svg(v$input_preview)),shiny::div(class="brohn-signal-compact",brohn_cardiac_input_svg(v$input_preview,340)),
      shiny::p("Mint: input within the parent's retained support. Amber: original input at the parent's filter edge. Coral: researcher excluded input. Separate paths preserve those boundaries."),
      .brohn_cardiac_table(.brohn_cardiac_rows(l$spans),columns=c("start_sample","end_sample","samples","first_time_s","last_time_s","reason","note"),labels=c("First source row","End row (excluded)","Samples","First time (s)","Last time (s)","Reason","Note"),maximum=64L,label="Every resolved saved exclusion and its observed times"),
      .brohn_cardiac_table(.brohn_cardiac_runs(l$runs),columns=c("run","start_sample","end_sample","samples","first_time_s","last_time_s","predicted_retained_samples","status","reason"),labels=c("Remaining run","First source row","End row (excluded)","Samples","First time (s)","Last time (s)","Predicted retained samples","Support","Restriction"),maximum=65L,label="Separate remaining runs and predicted support"),
      if(length(l$spans)) .brohn_cardiac_action("Save and recalculate separate report","recalculate",list(id=p$id),TRUE)else shiny::p("Save at least one exclusion to recalculate a separate report."),
      shiny::div(class="brohn-toolbar",shiny::downloadButton("cardiac_preview_json","Download exact preview + decisions",icon=NULL)),
      shiny::tags$details(shiny::tags$summary("Preview sampling and interpretation"),shiny::p(v$input_preview$definition),shiny::p(v$input_preview$sampling),
        shiny::p(paste(v$input_preview$displayed_samples,"displayed points from",v$input_preview$complete_samples,"complete input samples.")),
        shiny::p(paste("Each run uses the parent's",s$edge_guard_seconds,"second edge guard. This engineering policy does not prove artifact removal, normal beats or physiological validity.")),
        shiny::p("No intervals bridge an exclusion. Results stay separate per run; short runs do not pool into a longer spectral estimate."))))
  })
  valid_result<-function(){x<-result();r<-selected();brohn_require(!is.null(x)&&identical(x$project_id,r$project_id)&&identical(brohn_hash(x$body$analysis$exclusion_review$review_source),brohn_hash(list(id=r$id,revision=r$revision,hash=brohn_hash(r$body)))),"Open the matching saved result for this review.");x}
  fresh_saved<-function(value,kind){r<-authorized_selected();current<-brohn_get_entity(store,kind,value$id)
    brohn_require(!is.null(current)&&identical(current$project_id,r$project_id)&&identical(current$revision,value$revision)&&identical(brohn_hash(current$body),brohn_hash(value$body)),"This saved output changed or is no longer available in the review's project. Reopen it before downloading.");current}
  output$cardiac_review_result<-shiny::renderUI({if(is.null(active()))return(NULL);older<-Filter(function(x)is.null(result())||!identical(x$id,result()$id),saved_results())
    current<-if(is.null(result()))NULL else {r<-valid_result();l<-r$body$analysis$exclusion_review
    brohn_card(title="Separate recalculated report saved",shiny::p(paste(r$body$title,"|",r$body$analysis$status)),
      shiny::p(paste("Review version",l$review_source$revision,"excluded",l$support$excluded_samples,"input samples. Its separate run endpoints have different support from the whole parent report.")),
      shiny::div(class="brohn-toolbar",brohn_command("Open recalculated report","open_report",r$id,"btn btn-primary"),brohn_command("Open original parent report","open_report",selected()$body$report_id),
        shiny::downloadButton("cardiac_result_json","Download recalculated report",icon=NULL)),shiny::p("Detections remain unreviewed; no normal-to-normal or physiological qualification is implied."))}
    shiny::tagList(current,if(length(older))shiny::tags$details(shiny::tags$summary("Reports from earlier exclusion decisions"),shiny::p("These saved reports keep their original review versions and support; they do not use current edits."),
      lapply(older,function(x)shiny::div(class="brohn-toolbar",shiny::span(paste(x$body$title,"| review version",x$body$analysis$exclusion_review$review_source$revision)),brohn_command("Open earlier exclusion report","open_report",x$id)))))})
  output$cardiac_review_json<-shiny::downloadHandler(filename=function()paste0(selected()$id,"-v",selected()$revision,".json"),content=function(file)prepare_download(function()brohn_write_json_file(authorized_selected()$body,file)),contentType="application/json")
  output$cardiac_preview_json<-shiny::downloadHandler(filename=function()paste0(valid_preview()$id,".json"),content=function(file)prepare_download(function()brohn_write_json_file(fresh_saved(valid_preview(),"cardiac_review_preview")$body,file)),contentType="application/json")
  output$cardiac_result_json<-shiny::downloadHandler(filename=function()paste0(valid_result()$id,".json"),content=function(file)prepare_download(function()brohn_write_json_file(fresh_saved(valid_result(),"report")$body,file)),contentType="application/json")
  invisible(list(active=active,editing=editing,preview=preview,resolution=resolution,history=history,result=result,pending=pending,issue=issue,source_key=source_key,form_key=form_key,baseline=baseline))
}
