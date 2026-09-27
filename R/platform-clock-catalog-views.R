brohn_clock_catalog_ui <- function(id,title,search=TRUE) shiny::tags$details(
  shiny::tags$summary(title),
  if(search)shiny::tagList(shiny::textInput(paste0(id,"_query"),paste("Search",tolower(title)),""),
    shiny::actionButton(paste0(id,"_search"),"Search")),
  shiny::div(class="brohn-toolbar",shiny::actionButton(paste0(id,"_newer"),"Newer"),
    shiny::actionButton(paste0(id,"_older"),"Older"),shiny::actionButton(paste0(id,"_latest"),"Show latest")),
  shiny::uiOutput(paste0(id,"_status")),shiny::uiOutput(paste0(id,"_rows")))

brohn_install_clock_catalog <- function(id,input,output,session,store,scope,on_select,attempt) {
  current<-shiny::reactiveVal(NULL);cursor<-shiny::reactiveVal(NULL);previous<-shiny::reactiveVal(list())
  query<-shiny::reactiveVal("");issue<-shiny::reactiveVal(NULL)
  context<-shiny::reactive({s<-scope();if(is.null(s))NULL else brohn_hash(s)})
  refresh<-function(focus=FALSE){s<-scope();if(is.null(s)){current(NULL);return(NULL)}
    p<-if(identical(s$kind,"versions"))brohn_clock_map_versions(store,s$map_id,s$project_id,cursor())else
      brohn_clock_catalog_page(store,s$project_id,s$kind,query(),s$map_ref,cursor(),dataset_ref=s$dataset_ref)
    if(is.null(cursor()))cursor(p$cursor);current(p);issue(NULL)
    if(focus)session$onFlushed(function()session$sendCustomMessage("brohn-focus",paste0(id,"_summary")),once=TRUE)
    p}
  reset<-function(){cursor(NULL);previous(list());current(NULL);issue(NULL);refresh()}
  shiny::observeEvent(context(),tryCatch(reset(),error=function(e){current(NULL);issue(conditionMessage(e))}),ignoreNULL=FALSE,priority=110)
  output[[paste0(id,"_status")]]<-shiny::renderUI({p<-current();shiny::div(id=paste0(id,"_summary"),role="status",tabindex="-1",
    if(!is.null(issue()))shiny::p(issue()),if(!is.null(p))shiny::p(paste(length(p$records),"choices on this page;",p$total,"in this snapshot.",
      if(p$has_next)"Older choices are available."else"At oldest page.")))})
  output[[paste0(id,"_rows")]]<-shiny::renderUI({p<-current();if(is.null(p))return(NULL)
    kind<-scope()$kind
    lapply(p$records,function(r)shiny::div(class="brohn-stack",shiny::strong(style="overflow-wrap:anywhere",
      if(identical(kind,"windows"))paste("Measurements from",r$start_s,"to",r$end_s,"seconds")else
        brohn_default(r$title,if(identical(kind,"imports"))"Preserved recording import"else"Saved recording")),
      shiny::p(paste(if(identical(kind,"windows"))"Alignment version"else"Version",brohn_default(r$map_revision,r$reference$revision),"|",
        format(as.POSIXct(r$created_at,format="%Y-%m-%dT%H:%M:%OSZ",tz="UTC"),"%d %b %Y, %H:%M UTC",tz="UTC"))),
      brohn_command("Choose",paste0(id,"_choose"),r$reference)))})
  shiny::observeEvent(input[[paste0(id,"_search")]],attempt(function(){query(brohn_default(input[[paste0(id,"_query")]],""));reset()}))
  shiny::observeEvent(input[[paste0(id,"_latest")]],attempt(reset))
  shiny::observeEvent(input[[paste0(id,"_older")]],attempt(function(){p<-current();if(is.null(p)||is.null(p$next_cursor))return()
    previous(c(previous(),list(p$cursor)));cursor(p$next_cursor);refresh(TRUE)}))
  shiny::observeEvent(input[[paste0(id,"_newer")]],attempt(function(){p<-previous();if(!length(p))return()
    cursor(p[[length(p)]]);previous(head(p,-1L));refresh(TRUE)}))
  shiny::observeEvent(input[[paste0(id,"_choose")]],attempt(function(){p<-refresh();ref<-input[[paste0(id,"_choose")]]
    brohn_require(!is.null(p)&&any(vapply(p$records,function(r).brohn_cm_same(r$reference,ref),logical(1))),
      "Choose an item from the current page. Show latest if the catalog changed.")
    on_select(ref)}))
  invisible(list(refresh=refresh,reset=reset,page=current))
}
