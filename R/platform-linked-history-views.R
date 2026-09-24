# External candidate: the disclosure and controls stay mounted while rows change.
brohn_linked_history_ui <- function() shiny::tags$details(
  shiny::tags$summary("Saved linked reviews"),
  shiny::p("Reopen a saved source selection and window without running analysis again."),
  shiny::div(class="brohn-toolbar",shiny::actionButton("linked_history_newer","Newer saved reviews"),
    shiny::actionButton("linked_history_older","Older saved reviews"),
    shiny::actionButton("linked_history_latest","Show latest reviews")),
  shiny::uiOutput("linked_history_status"),shiny::uiOutput("linked_history_rows"))
brohn_install_linked_history <- function(input,output,session,store,scope,on_open,attempt) {
  cursor<-shiny::reactiveVal(NULL);previous<-shiny::reactiveVal(list());issue<-shiny::reactiveVal(NULL)
  current<-shiny::reactiveVal(NULL)
  context<-shiny::reactive({s<-scope();if(is.null(s))return(NULL);brohn_hash(s)})
  focus_status<-function()session$onFlushed(function()session$sendCustomMessage("brohn-focus","linked_history_summary"),once=TRUE)
  refresh<-function(focus=FALSE){s<-scope();if(is.null(s)){current(NULL);return(invisible(NULL))}
    if(focus)on.exit(focus_status(),add=TRUE)
    value<-tryCatch(brohn_linked_history_page(store,s$dataset_ref,s$project_id,s$import_ref,cursor()),
      error=function(e){current(NULL);issue(conditionMessage(e));stop(e)})
    # Retain the initial watermark instead of letting passive refresh add rows.
    if(is.null(cursor()))cursor(value$cursor)
    current(value);invisible(value)}
  shiny::observeEvent(context(),{cursor(NULL);previous(list());current(NULL);issue(NULL)
    tryCatch(shiny::isolate(refresh()),error=function(e){current(NULL);issue(conditionMessage(e))})},ignoreNULL=FALSE,priority=110)
  output$linked_history_status<-shiny::renderUI({p<-current();s<-issue()
    shiny::div(id="linked_history_summary",tabindex="-1",role="status",`aria-live`="polite",if(!is.null(s))shiny::p(class="brohn-alert",s),
      if(!is.null(p))shiny::tagList(shiny::p(if(p$total)paste("Showing",p$first,"to",p$last,"of",p$total,"saved views.")else"No saved linked reviews in this selection."),
        shiny::p("Show latest includes newly saved reviews. Unavailable views may leave this list."),
        shiny::p(paste(if(!length(previous()))"At newest page."else"Newer pages are available.",if(p$has_next)"Older pages are available."else"At oldest page."))))})
  output$linked_history_rows<-shiny::renderUI({p<-current();if(is.null(p))return(NULL)
    lapply(p$records,function(r)shiny::div(
      shiny::div(class="brohn-toolbar",shiny::span(paste(r$start_s,"to",r$end_s,"seconds |",r$tracks,"channels |",
        switch(r$status,available="Ready",empty_window="Empty window",requires_alignment="Needs alignment",r$status),"| Saved",
        format(as.POSIXct(r$created_at,format="%Y-%m-%dT%H:%M:%OSZ",tz="UTC"),"%d %b %Y, %H:%M UTC",tz="UTC"))),
        brohn_command("Reopen","linked_history_open",r$reference)),
      shiny::tags$details(shiny::tags$summary("Source details"),
        shiny::p(paste("Cursor:",r$cursor_s,"seconds;",r$selected_rows,"selected observations; origin:",r$origin)),
        shiny::p(paste("Preserved import:",r$import_id,"revision",r$import_revision,"| Clock:",r$clock_id,"| Exact row offset:",r$exact_row_offset)),
        shiny::tags$pre(style="white-space:pre-wrap;overflow-wrap:anywhere",brohn_json(r$reference)))))})
  shiny::observeEvent(input$linked_history_older,attempt(function(){p<-current();if(is.null(p)){refresh(TRUE);return()}
    if(is.null(p$next_cursor)){refresh(TRUE);issue("You are at the oldest saved-review page.");return()}
    previous(c(previous(),list(p$cursor)));cursor(p$next_cursor);issue(NULL);refresh(TRUE)}))
  shiny::observeEvent(input$linked_history_newer,attempt(function(){stack<-previous()
    if(!length(stack)){refresh(TRUE);issue("You are at the newest page in this snapshot. Use Show latest for new reviews.");return()}
    cursor(stack[[length(stack)]]);previous(head(stack,-1L));issue(NULL);refresh(TRUE)}))
  shiny::observeEvent(input$linked_history_latest,attempt(function(){cursor(NULL);previous(list());issue(NULL);refresh(TRUE)}))
  shiny::observeEvent(input$linked_history_open,attempt(function(){s<-scope();brohn_require(!is.null(s),"Reopen this recording before choosing a saved view.")
    p<-refresh();brohn_require(!is.null(p)&&any(vapply(p$records,function(r)identical(brohn_hash(r$reference),brohn_hash(input$linked_history_open)),logical(1))),
      "Choose a review from the currently displayed page. Show latest if it changed.")
    saved<-brohn_linked_history_open(store,input$linked_history_open,s$dataset_ref,s$project_id,s$import_ref)
    on_open(saved);issue(NULL)}))
  invisible(list(page=current,previous=previous,cursor=cursor,issue=issue,refresh=refresh))
}
