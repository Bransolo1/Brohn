brohn_session_resolution_label <- function(record) {
  if(is.null(record))return(NULL)
  switch(record$body$effective_resolution,researcher_interrupted="Researcher interruption",
    received_completion_confirmed="Received completion confirmed by researcher",
    paste("Participant",record$body$participant_ending$outcome,"ending preserved; delivery resolved"))
}
brohn_session_resolution_command <- function(store,run,study_id,project_id) {
  brohn_require(all(vapply(list(run$id,run$deployment_id,study_id,project_id),brohn_valid_id,logical(1))),"Choose an existing session within this study and project.")
  rows<-DBI::dbGetQuery(store$con,"SELECT id,status,study_id,project_id FROM delivery_deployments WHERE id=?",params=list(run$deployment_id))
  if(nrow(rows)!=1L)return(NULL)
  release<-as.list(rows[1L,,drop=FALSE])
  if(release$status!="closed"||release$study_id!=study_id||release$project_id!=project_id)return(NULL)
  record<-brohn_session_resolution(store,run$id)
  shiny::tagList(if(!is.null(record))shiny::p(class="brohn-muted",brohn_session_resolution_label(record)),
    brohn_command(if(is.null(record))"Review session recovery"else"View researcher resolution","session_resolution_open",
      list(study_id=study_id,release_id=release$id,run_id=run$id)))
}
brohn_install_session_resolution <- function(input,output,session,store,state,current,attempt,message,refresh,prepare_download,return_to_collection=NULL) {
  selected<-shiny::reactiveVal(NULL)
  validate<-function(command){
    brohn_require(identical(state$page,"study")&&state$stage %in% c("Collect","Review","History")&&!is.null(current$study)&&identical(current$study$id,command$study_id),"Open this session from its study's Collect, Review or History page.")
    study<-brohn_study(store,current$study$id);list(study_id=study$id,project_id=study$project_id,release_id=command$release_id,run_id=command$run_id)
  }
  read<-function(binding)do.call(brohn_session_resolution_review,c(list(store=store),binding))
  show<-function(binding){
    review<-read(binding);s<-list(binding=binding,review=review);selected(s)
    source<-review$review$source;record<-review$existing
    title<-paste("Session",source$allocation_index,if(is.null(record))"recovery review"else"researcher resolution")
    ending<-if(is.null(source$participant_ending))"No participant ending was received."else paste("Received participant ending:",source$participant_ending$outcome,".")
    shiny::showModal(shiny::modalDialog(title=title,size="l",easyClose=FALSE,
      shiny::div(id="session-resolution-review",`data-session-id`=source$run_id,
        shiny::tags$style(shiny::HTML("#session-resolution-review button,#session-resolution-review textarea{min-height:44px}#session-resolution-review .checkbox label{min-height:44px;display:flex;align-items:center}#session-resolution-review input[type=checkbox]{min-height:0;height:18px;width:18px}#session-resolution-review h3{line-height:1.5}#session-resolution-review{min-width:0;overflow-wrap:anywhere}")),
        shiny::p(paste("This exact closed release contains",source$origin,"sessions. Original responses and recording bytes will be retained.")),
        shiny::h3("What was received"),shiny::p(ending),
        shiny::p(paste(source$received_sequence,"acknowledged events;",source$completed_steps,"of",source$planned_steps,"study steps have received finish events.")),
        shiny::p(paste("Original participant receipt:",gsub("_"," ",source$original_receipt$completion_status),"/",source$original_receipt$transfer_status,".")),
        shiny::p(if(source$camera$status=="not_requested")"No recording was requested."else paste("Recording:",gsub("_"," ",source$camera$status),";",format(source$camera$bytes,big.mark=",",scientific=FALSE),"bytes received.",if(isTRUE(source$camera$end_observed))"The original recording endpoint is retained."else"No recording endpoint will be invented.")),
        if(!isTRUE(source$camera_support$eligible))shiny::p("Recording support is incomplete. Received bytes remain retained; this decision does not create a complete or decodable recording."),
        if(is.null(record))shiny::tagList(shiny::h3("What this decision does"),
          shiny::p(if(is.null(source$participant_ending))"Record a researcher interruption, without claiming participant withdrawal or completion."else if(review$eligible_analysis)
            "Confirm the actual received completion. A separate analysis can use its complete supported source; the missing participant final acknowledgment stays explicit."else
              "Preserve the participant's actual ending and close further delivery. This does not make incomplete source evidence scientifically complete."),
          shiny::p("After resolution, new responses or recording chunks cannot be added. Exact retries of already-received evidence remain acknowledged. Unsent browser data are not deleted or claimed as received."),
          if(length(review$active_jobs))shiny::p(role="status","Processing is still active. Inspect or cancel it in Activity, then refresh this review."),
          if(!review$ready&&!length(review$active_jobs))shiny::p(role="status","This session does not currently need a new recovery decision."),
          shiny::textAreaInput("session_resolution_reason","Reason for researcher resolution",value="",rows=3,width="100%",placeholder="For example: participant browser was lost and recruitment has closed."),
          shiny::checkboxInput("session_resolution_confirm","I reviewed this session and understand that new uploads will be closed.",FALSE))else
            shiny::tagList(shiny::h3(brohn_session_resolution_label(record)),shiny::p(record$body$operator$reason),
              shiny::p(paste("Recorded",record$body$operator$decided_at,". Original participant events, final receipts and recording bytes are unchanged.")),
              if(isTRUE(record$body$received_completion_analysis_eligible))shiny::p("The complete received completion is eligible for its separate, source-bound analysis. It is not silently added to normal completed-session cohorts.")),
        if(!is.null(record)&&length(record$body$processing_review))shiny::tags$details(shiny::tags$summary("Processing at the time of resolution"),
          shiny::tags$ul(lapply(record$body$processing_review,function(j)shiny::tags$li(paste(gsub("_"," ",j$operation),"-",j$status))))),
        shiny::uiOutput("session_resolution_processing")),
      footer=shiny::tagList(shiny::actionButton("session_resolution_close","Close"),shiny::actionButton("session_resolution_return","Return to collection closure"),
        if(is.null(record))shiny::actionButton("session_resolution_refresh","Refresh session review"),
        if(is.null(record)&&review$ready)shiny::actionButton("session_resolution_save","Record researcher resolution",class="btn-primary"),
        if(!is.null(record))shiny::downloadButton("session_resolution_download","Download resolution evidence",icon=NULL),
        if(!is.null(record)&&isTRUE(record$body$received_completion_analysis_eligible))shiny::actionButton("session_resolution_analyse","Analyse confirmed completion",class="btn-primary"))))
  }
  selection<-function(){s<-selected();brohn_require(!is.null(s),"Open a current session recovery review.");validate(s$binding);s}
  shiny::observeEvent(input$session_resolution_open,attempt(function()show(validate(input$session_resolution_open))))
  shiny::observeEvent(input$session_resolution_refresh,attempt(function()show(selection()$binding)))
  shiny::observeEvent(input$session_resolution_save,attempt(function(){s<-selection();brohn_require(isTRUE(input$session_resolution_confirm),"Confirm that you reviewed this exact session before recording its resolution.")
    do.call(brohn_resolve_session,c(list(store=store),s$binding,list(expected_hash=s$review$hash,reason=input$session_resolution_reason)))
    refresh();show(s$binding);message("Researcher resolution saved. Original participant evidence is unchanged.")}))
  shiny::observeEvent(input$session_resolution_close,{selected(NULL);shiny::removeModal()})
  shiny::observeEvent(input$session_resolution_return,attempt(function(){s<-selection();selected(NULL);shiny::removeModal();state$stage<-"Collect";refresh()
    if(!is.null(return_to_collection))return_to_collection(list(study_id=s$binding$study_id,release_id=s$binding$release_id))}))
  analysis_job<-shiny::reactiveVal(NULL)
  shiny::observeEvent(input$session_resolution_analyse,attempt(function(){s<-selection();record<-brohn_session_resolution(store,s$binding$run_id)
    analysis_job(brohn_queue_resolved_session_analysis(store,record$id,brohn_hash(record$body)));message("Confirmed completion analysis queued from its exact received source.")}))
  output$session_resolution_processing<-shiny::renderUI({s<-selected();j<-analysis_job();if(is.null(s)||is.null(j)||!identical(j$request$run_id,s$binding$run_id))return(NULL)
    if(j$status %in% c("queued","running")){shiny::invalidateLater(1000,session);j<-brohn_get_job(store,j$id);shiny::isolate(analysis_job(j))}
    shiny::p(role="status",paste("Confirmed completion analysis:",j$status),if(j$status=="succeeded")brohn_command("Open confirmed completion report","session_resolution_report",j$result$report_id))})
  shiny::observeEvent(input$session_resolution_report,attempt(function(){s<-selection();j<-analysis_job();brohn_require(!is.null(j)&&j$status=="succeeded"&&identical(j$request$run_id,s$binding$run_id)&&identical(input$session_resolution_report,j$result$report_id),"Choose this exact confirmed completion report.")
    selected(NULL);shiny::removeModal();state$report_id<-j$result$report_id;state$page<-"report";refresh()}))
  output$session_resolution_download<-shiny::downloadHandler(filename=function()paste0(selection()$binding$run_id,"-researcher-resolution.json"),contentType="application/json",content=function(file)prepare_download(function(){s<-selection();r<-brohn_session_resolution(store,s$binding$run_id);brohn_require(!is.null(r),"Record the resolution before exporting it.");brohn_write_json_file(r$body,file)}))
  invisible(list(show=show,selection=selection))
}
