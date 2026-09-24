brohn_collection_inventory_ui <- function(body, offset=0L,store=NULL,project_id=NULL,frozen=FALSE) {
  sessions <- body$sessions; total <- length(sessions)
  offset <- if(total)min(offset,floor((total-1L)/40L)*40L)else 0L
  selected <- if(total)sessions[seq.int(offset+1L,min(total,offset+40L))]else list()
  resolutions<-brohn_default(body$resolutions,list())
  resolution_ref<-function(run){refs<-Filter(function(r)identical(r$run_id,run$id),resolutions)
    brohn_require(length(refs)<=1L,"A collection session has conflicting researcher resolution references.")
    if(length(refs))refs[[1L]]else NULL}
  resolution_label<-function(run){ref<-resolution_ref(run);if(is.null(ref))return("None recorded")
    brohn_session_resolution_label(list(body=list(effective_resolution=ref$effective_resolution,participant_ending=list(outcome=ref$participant_ending))))}
  recovery<-function(run){if(is.null(store)||is.null(project_id))return(NULL)
    ref<-resolution_ref(run);if(frozen&&is.null(ref))return(NULL)
    if(!is.null(ref)) {
      record<-brohn_get_entity(store,"session_resolution",ref$id,ref$revision)
      brohn_require(!is.null(record)&&identical(record$project_id,project_id)&&identical(record$body$run_id,run$id)&&
        identical(brohn_hash(record$body),ref$hash),"The collection's saved researcher resolution is unavailable or changed. Preserve its manifest reference.")
    }
    selected_run<-run;selected_run$deployment_id<-brohn_default(run$deployment_id,body$release$id)
    brohn_session_resolution_command(store,selected_run,body$release$study_id,project_id)}
  shiny::tagList(
    shiny::p(paste("Design revision",body$release$design_revision,"\u00b7",body$release$origin,"\u00b7",total,"started sessions")),
    shiny::p("Counts describe sessions, not unique people. A completed session is not automatically usable for every research measure."),
    if(length(resolutions))shiny::p(paste(length(resolutions),"separate researcher decisions:",
      sum(vapply(resolutions,function(r)r$effective_resolution=="researcher_interrupted",logical(1))),"researcher interruptions;",
      sum(vapply(resolutions,function(r)r$effective_resolution=="received_completion_confirmed",logical(1))),"received completions confirmed;",
      sum(vapply(resolutions,function(r)r$effective_resolution=="participant_ending_preserved",logical(1))),"participant endings preserved. Original ending and transfer receipts below remain unchanged.")),
    shiny::p("This inventory covers participant receipts and their linked processing in this release. Separately imported datasets and external device recordings remain in the Data library."),
    if(!total)shiny::p("No participant sessions started in this release."),
    if(total)shiny::div(class="brohn-table",tabindex="0",role="region",`aria-label`="Collection sessions",
      shiny::tags$table(shiny::tags$thead(shiny::tags$tr(lapply(c("Session","Original ending","Original transfer","Researcher decision","Reports","Recovery"),function(x)shiny::tags$th(scope="col",x)))),
        shiny::tags$tbody(lapply(selected,function(s)shiny::tags$tr(shiny::tags$td(paste("Session",s$allocation_index)),
          shiny::tags$td(gsub("_"," ",s$completion_status)),shiny::tags$td(s$transfer_status),shiny::tags$td(resolution_label(s)),
          shiny::tags$td(length(Filter(function(r)identical(r$run_id,s$id),body$reports))),shiny::tags$td(recovery(s))))))),
    if(total)shiny::p(paste("Showing sessions",offset+1L,"to",min(total,offset+40L),"of",total)),
    shiny::div(class="brohn-toolbar",if(offset>0L)brohn_command("Previous collection sessions","collection_session_page",offset-40L),
      if(offset+40L<total)brohn_command("Next collection sessions","collection_session_page",offset+40L)))
}
brohn_install_collection_history <- function(input,output,session,store,state,current,attempt,message,refresh,prepare_download,open_runtime=NULL) {
  selected <- shiny::reactiveVal(NULL); offsets <- new.env(parent=emptyenv())
  valid_study <- function(study_id=NULL) {
    brohn_require(identical(state$page,"study") && state$stage %in% c("Collect","History") && !is.null(current$study) &&
      (is.null(study_id)||identical(study_id,current$study$id)),"Return to this study's Collect or History page to review its collection.")
    brohn_study(store,current$study$id)
  }
  binding <- function(release_id)list(study_id=current$study$id,release_id=release_id)
  list_ui <- function(history=FALSE) {
    state$refresh; study <- valid_study()
    key <- paste(study$id,history,sep=":"); offset <- brohn_default(offsets[[key]],0L)
    page <- brohn_collection_page(store,study$id,study$project_id,offset)
    if(!page$total)return(if(history)brohn_card(title="Finalized collections",shiny::p("Close recruitment in Collect, resolve remaining sessions and processing, then finalize the saved session and report inventory."))else NULL)
    brohn_card(title=if(history)"Finalized collections and closed releases"else "Finish closed collections",
      subtitle="Review the final receipts and reports once, then preserve the exact collection in History.",
      lapply(page$records,function(r)shiny::div(class="brohn-toolbar",shiny::span(paste(r$origin,"\u00b7 design revision",r$design_revision,"\u00b7",r$created_at)),
        if(!is.na(r$collection_id))brohn_command("Open finalized collection","collection_open",binding(r$id))else brohn_command("Review collection closure","collection_review",binding(r$id)))),
      shiny::p(paste("Showing",page$offset+1L,"to",page$offset+length(page$records),"of",page$total,"closed releases")),
      shiny::div(class="brohn-toolbar",if(page$offset>0L)brohn_command("Previous closed releases","collection_history_page",page$offset-page$limit),
        if(page$offset+page$limit<page$total)brohn_command("Next closed releases","collection_history_page",page$offset+page$limit)))
  }
  output$collection_close <- shiny::renderUI({shiny::req(identical(state$page,"study"),identical(state$stage,"Collect"));list_ui(FALSE)})
  output$collection_history <- shiny::renderUI({shiny::req(identical(state$page,"study"),identical(state$stage,"History"));list_ui(TRUE)})
  selection <- function() {
    s <- selected();brohn_require(!is.null(s),"Open a collection first.");study<-valid_study(s$study_id)
    brohn_require(identical(study$project_id,s$project_id),"The collection project changed.");s
  }
  show <- function(s) {
    frozen <- !is.null(s$record); body <- if(frozen)s$record$body else s$review$inventory
    shiny::showModal(shiny::modalDialog(title=if(frozen)"Finalized collection"else "Review collection closure",size="l",easyClose=FALSE,
      shiny::div(id="collection-review-content",
        if(frozen)shiny::p(paste("Finalized",body$finalized_at,"\u00b7 this saved inventory will not change when you collect or analyse again.")),
        brohn_collection_inventory_ui(body,s$offset,store,s$project_id,frozen),
        if(is.function(open_runtime))shiny::tags$details(shiny::tags$summary("Participant code"),
          shiny::p("Review the release's separate code-preservation record. This does not change the saved collection inventory."),
          shiny::actionButton("collection_participant_code","Review collection participant code")),
        if(!frozen && length(s$review$blockers))shiny::div(class="brohn-alert brohn-alert-warning",role="status",
          shiny::h3("Resolve before finalizing"),shiny::tags$ul(lapply(s$review$blockers,function(b)shiny::tags$li(b$text))),
          shiny::div(class="brohn-toolbar",shiny::actionButton("collection_review_sessions","Review participant sessions"),shiny::actionButton("collection_review_jobs","Open processing"))),
        if(!frozen && s$review$ready)shiny::p(if(length(body$resolutions))
          "Every started session has a supported saved receipt or a separate researcher resolution, and its linked processing is resolved. Finalize to preserve these exact original receipts and decisions; further collection requires a new release."else
          "Every started session has a final saved outcome and its linked processing is resolved. Finalize to preserve this exact inventory; further collection requires a new release."),
        if(frozen && length(body$reports))shiny::tags$details(shiny::tags$summary("Reports saved with this collection"),
          shiny::tags$ul(lapply(body$reports,function(r)shiny::tags$li(r$title," ",brohn_command("Open saved report","collection_report",r$id))))),
        if(frozen)shiny::p("Clone this released design to run another study with no participants or results copied. To collect another release in this study, restore it if archived and use Collect; this release remains closed.")),
      footer=shiny::tagList(
        if(frozen)shiny::downloadButton("collection_download","Download collection manifest",icon=NULL),
        if(frozen)shiny::actionButton("collection_clone","Clone released design"),
        if(!frozen)shiny::actionButton("collection_refresh","Refresh collection review"),
        if(!frozen && s$review$ready)shiny::actionButton("collection_finalize","Finalize collection",class="btn-primary"),
        shiny::actionButton("collection_close_modal","Close collection"))))
  }
  open <- function(command,frozen=FALSE) {
    brohn_fields(command,c("study_id","release_id"),label="Collection selection");study<-valid_study(command$study_id)
    record<-brohn_collection_record(store,command$release_id,study$id,study$project_id)
    brohn_require(!frozen||!is.null(record),"This release has not been finalized.")
    s<-list(study_id=study$id,project_id=study$project_id,release_id=command$release_id,record=record,offset=0L)
    if(is.null(record))s$review<-brohn_collection_review(store,command$release_id,study$id,study$project_id)
    selected(s);show(s)
  }
  shiny::observeEvent(input$collection_review,attempt(function()open(input$collection_review,FALSE)))
  shiny::observeEvent(input$collection_open,attempt(function()open(input$collection_open,TRUE)))
  shiny::observeEvent(input$collection_refresh,attempt(function(){s<-selection();open(list(study_id=s$study_id,release_id=s$release_id),FALSE)}))
  shiny::observeEvent(input$collection_finalize,attempt(function(){s<-selection();brohn_require(is.null(s$record),"This collection is already finalized.")
    s$record<-brohn_finalize_collection(store,s$release_id,s$study_id,s$project_id,s$review$hash);s$review<-NULL;selected(s);refresh();show(s);message("Collection finalized and preserved in History")}))
  shiny::observeEvent(input$collection_session_page,attempt(function(){s<-selection();brohn_require(brohn_number(input$collection_session_page,0,2000,TRUE)&&input$collection_session_page%%40==0,"Choose a current collection page.")
    s$offset<-as.integer(input$collection_session_page);selected(s);show(s)}))
  shiny::observeEvent(input$collection_history_page,attempt(function(){study<-valid_study();brohn_require(brohn_number(input$collection_history_page,0,1e8,TRUE)&&input$collection_history_page%%20==0,"Choose a collection history page.")
    offsets[[paste(study$id,identical(state$stage,"History"),sep=":")]]<-input$collection_history_page;refresh()}))
  shiny::observeEvent(input$collection_close_modal,{selected(NULL);shiny::removeModal()})
  shiny::observeEvent(input$collection_participant_code,attempt(function(){
    s<-selection();brohn_require(is.function(open_runtime),"Participant-code review is unavailable.")
    open_runtime(list(kind="release",id=s$release_id,study_id=s$study_id),return_view=function()show(selection()))
  }))
  shiny::observeEvent(input$collection_review_sessions,attempt(function(){selection();selected(NULL);shiny::removeModal();state$stage<-"Review";refresh()}))
  shiny::observeEvent(input$collection_review_jobs,attempt(function(){selection();selected(NULL);shiny::removeModal();state$page<-"activity";refresh()}))
  frozen <- function(){s<-selection();brohn_require(!is.null(s$record),"Open a finalized collection first.");record<-brohn_collection_record(store,s$release_id,s$study_id,s$project_id)
    brohn_require(identical(brohn_hash(record$body),brohn_hash(s$record$body)),"The saved collection identity changed.");record}
  output$collection_download<-shiny::downloadHandler(filename=function()paste0(frozen()$id,".json"),contentType="application/json",
    content=function(file)prepare_download(function()brohn_write_json_file(frozen()$body,file)))
  shiny::observeEvent(input$collection_report,attempt(function(){record<-frozen();report<-brohn_collection_report(store,record,input$collection_report)
    selected(NULL);shiny::removeModal();state$report_id<-report$id;state$page<-"report";refresh()}))
  shiny::observeEvent(input$collection_clone,attempt(function(){record<-frozen();release<-record$body$release
    copy<-brohn_clone_study(store,record$body$study_id,paste(release$title,"collection copy"),revision=release$design_revision,project_id=record$project_id)
    selected(NULL);shiny::removeModal();current$study<-copy;state$study_id<-copy$id;state$page<-"study";state$stage<-"Plan";refresh();message("Released design cloned. No sessions or results were copied.")}))
  invisible(list(selection=selection,open=open))
}
