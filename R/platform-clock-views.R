# Connected researcher flow. All source inspection and map/window publication
# goes through the supervised clock operations; controls retain original refs.
brohn_clock_review_ui <- function() shiny::tagList(
  shiny::tags$script(src="clock-review-ui.js"),
  shiny::tags$details(id="clock_review_panel",shiny::tags$summary("Align another recording"),
    shiny::p("Match two recorded events to put another recording on a shared review timeline. Original measurements stay intact."),
    shiny::actionButton("clock_begin","Choose recordings"),shiny::actionButton("clock_close","Close alignment"),
    shiny::uiOutput("clock_status"),shiny::uiOutput("clock_content")))

brohn_install_clock_review <- function(input,output,session,store,state,attempt) {
  v<-shiny::reactiveValues(enabled=FALSE,generation=0L,source=NULL,reference=NULL,source_import=NULL,reference_import=NULL,
    selections=NULL,source_events=NULL,reference_events=NULL,pool=list(source=list(),reference=list()),checks=0L,
    preview=NULL,map=NULL,editing=NULL,window=NULL,pending=NULL,issue=NULL,urls=list(),result_ticket=NULL,result_kind=NULL,channel_defaults=list(),last_save=NULL,
    plot=NULL,plot_pending=NULL,plot_url=NULL)
  native<-new.env(parent=emptyenv());native$handle<-NULL;native$plot_handle<-NULL
  dataset<-function(){brohn_require(identical(state$page,"dataset"),"Open a preserved recording first.")
    d<-brohn_get_entity(store,"dataset",state$dataset_id)
    brohn_require(!is.null(d)&&identical(d$body$modality,"multimodal"),"Open a preserved multistream recording.");d}
  release<-function(){if(!is.null(native$plot_handle))brohn_release_clock_plot_resources(native$plot_handle)
    native$plot_handle<-NULL;v$plot<-NULL;v$plot_pending<-NULL;v$plot_url<-NULL
    if(!is.null(native$handle))brohn_release_clock_window_resources(native$handle);native$handle<-NULL;v$urls<-list();v$window<-NULL}
  invalidate<-function(clear_events=TRUE){v$generation<-v$generation+1L;v$pending<-NULL;v$preview<-NULL;v$result_ticket<-NULL;v$result_kind<-NULL;release()
    if(clear_events){v$selections<-NULL;v$source_events<-NULL;v$reference_events<-NULL;v$pool<-list(source=list(),reference=list());v$checks<-0L}}
  close<-function(){invalidate();v$enabled<-FALSE;v$source<-NULL;v$reference<-NULL;v$source_import<-NULL;v$reference_import<-NULL;v$map<-NULL;v$editing<-NULL;v$issue<-NULL}
  session$onSessionEnded(function(){if(!is.null(native$plot_handle))brohn_release_clock_plot_resources(native$plot_handle)
    if(!is.null(native$handle))brohn_release_clock_window_resources(native$handle)})
  shiny::observeEvent(list(state$page,state$dataset_id),close(),ignoreNULL=FALSE,priority=120)
  safe<-function(fn)tryCatch({brohn_hosted_require_session(store);fn()},error=function(e){v$issue<-conditionMessage(e);NULL})
  scope<-function(kind,side=NULL){if(!isTRUE(v$enabled))return(NULL);d<-dataset();s<-list(project_id=d$project_id,kind=kind)
    if(kind=="imports"){ref<-v[[side]];if(is.null(ref))return(NULL);s$dataset_ref<-ref}
    if(kind=="windows"){if(is.null(v$map))return(NULL);s$map_ref<-.brohn_cm_ref(v$map)}
    if(kind=="versions"){if(is.null(v$map))return(NULL);s$map_id<-v$map$id};s}
  one_import<-function(side){ref<-v[[side]];if(is.null(ref))return();p<-brohn_clock_catalog_page(store,dataset()$project_id,"imports",dataset_ref=ref)
    if(p$total==1L)v[[paste0(side,"_import")]]<-p$records[[1L]]$reference}
  select_import<-function(side,ref){invalidate();v[[paste0(side,"_import")]]<-ref;v$map<-NULL;v$editing<-NULL;v$issue<-NULL}
  brohn_install_clock_catalog("clock_recordings",input,output,session,store,function()scope("recordings"),function(ref){
    brohn_require(ref$id!=v$source$id,"Choose another recording as the reference.")
    invalidate();v$reference<-ref;v$reference_import<-NULL;v$map<-NULL;v$editing<-NULL;one_import("reference")},safe)
  for(side in c("source","reference"))local({side<-side
    brohn_install_clock_catalog(paste0("clock_",side,"_imports"),input,output,session,store,function()scope("imports",side),function(ref)select_import(side,ref),safe)
  })
  start<-function(action,payload=list(),label){brohn_require(is.null(v$pending)||v$pending$phase%in%c("ready","failed"),"Wait for the current step, or cancel it before starting another.");v$issue<-NULL;v$result_ticket<-NULL
    v$pending<-list(ticket=brohn_token(),generation=v$generation,action=action,payload=payload,label=label,phase="preparing",jobs=list())}
  brohn_install_clock_catalog("clock_maps",input,output,session,store,function()scope("maps"),function(ref)start("map",list(ref=ref),"Opening the saved alignment and checking its original sources."),safe)
  brohn_install_clock_catalog("clock_versions",input,output,session,store,function()scope("versions"),function(ref)start("map",list(ref=ref),"Opening the exact saved alignment version."),safe)
  brohn_install_clock_catalog("clock_windows",input,output,session,store,function()scope("windows"),function(ref)start("open",list(ref=ref),"Opening saved original measurements and checking current access."),safe)
  shiny::observeEvent(input$clock_begin,safe(function(){close();d<-dataset();v$source<-.brohn_cm_ref(d);v$enabled<-TRUE;one_import("source")}))
  shiny::observeEvent(input$clock_close,close())
  shiny::observeEvent(input$clock_panel_closed,close())
  output$clock_content<-shiny::renderUI({if(!isTRUE(v$enabled))return(NULL)
    shiny::tagList(shiny::h3("1. Choose original recordings"),shiny::uiOutput("clock_recording_names"),
      brohn_clock_catalog_ui("clock_recordings","Reference recordings"),
      brohn_clock_catalog_ui("clock_source_imports","Source import history",FALSE),
      brohn_clock_catalog_ui("clock_reference_imports","Reference import history",FALSE),
      shiny::uiOutput("clock_source_channels"),shiny::uiOutput("clock_reference_channels"),
      shiny::actionButton("clock_events_load","Load recorded events",class="btn-primary"),
      shiny::h3("2. Match recorded events"),
      shiny::p("Choose corresponding start and end events from each recording. Matching text alone does not establish that two events are the same occurrence."),
      lapply(c("source","reference"),function(side)shiny::tags$details(shiny::tags$summary(paste(tools::toTitleCase(side),"event search and pages")),
        shiny::textInput(paste0("clock_",side,"_query"),paste("Search",side,"event values"),""),
        shiny::actionButton(paste0("clock_",side,"_search"),"Search original events"),
        shiny::actionButton(paste0("clock_",side,"_previous"),"Previous events"),
        shiny::actionButton(paste0("clock_",side,"_next"),"Next events"),shiny::uiOutput(paste0("clock_",side,"_event_status")))),
      shiny::uiOutput("clock_pairs"),shiny::actionButton("clock_check_add","Add independent event check"),
      shiny::actionButton("clock_check_remove","Remove last independent check"),
      shiny::textAreaInput("clock_rationale","Why do these event pairs correspond?",rows=2),
      shiny::checkboxInput("clock_confirm","I reviewed the original event pairs and their recording identities.",FALSE),
      shiny::actionButton("clock_preview","Preview alignment",class="btn-primary"),
      shiny::uiOutput("clock_preview_result"),
      shiny::h3("3. Save and review measurements"),shiny::textInput("clock_name","Alignment name",""),
      shiny::actionButton("clock_save","Save and review",class="btn-primary"),
      shiny::uiOutput("clock_map_details"),shiny::uiOutput("clock_window_controls"),shiny::uiOutput("clock_window_result"),
      brohn_clock_catalog_ui("clock_maps","Saved alignments"),brohn_clock_catalog_ui("clock_versions","Alignment versions",FALSE),
      brohn_clock_catalog_ui("clock_windows","Saved measurement windows",FALSE))})
  output$clock_recording_names<-shiny::renderUI({shiny::tagList(lapply(c("source","reference"),function(side){ref<-v[[side]];imp<-v[[paste0(side,"_import")]]
    if(is.null(ref))return(shiny::p(paste(tools::toTitleCase(side),": choose a recording.")))
    d<-.brohn_cm_pin(store,"dataset",ref,dataset()$project_id)
    imported<-if(is.null(imp))NULL else .brohn_cm_pin(store,"stream_import",imp,d$project_id)
    shiny::p(paste(tools::toTitleCase(side),":",d$body$title,"|",d$body$origin,"|",if(is.null(imported))"Choose a preserved import."else
      paste("Preserved",substr(imported$created_at,1L,10L),"from source revision",imported$body$dataset_revision)))}))})
  for(side in c("source","reference"))local({side<-side
    output[[paste0("clock_",side,"_channels")]]<-shiny::renderUI({ref<-v[[side]];imp<-v[[paste0(side,"_import")]];if(is.null(ref)||is.null(imp))return(NULL)
      c<-brohn_clock_channel_choices(store,ref,imp,dataset()$project_id);defaults<-v$channel_defaults[[side]]
      restore<-!is.null(defaults)&&identical(defaults$dataset_id,ref$id)&&identical(defaults$import_id,imp$id)
      shiny::tagList(shiny::selectInput(paste0("clock_",side,"_marker"),paste(tools::toTitleCase(side),"recorded event channel"),c$marker,
        selected=if(restore)brohn_json(defaults$marker)else if(length(c$marker)==1L)unname(c$marker)else "",selectize=FALSE),
        shiny::checkboxGroupInput(paste0("clock_",side,"_tracks"),paste(tools::toTitleCase(side),"measurements (one or two)"),c$tracks,
          selected=if(restore)vapply(defaults$tracks,brohn_json,character(1))else if(length(c$tracks)==1L)unname(c$tracks)else character()))})
  })
  selections<-function(){out<-lapply(c("source","reference"),function(side){ref<-v[[side]];imp<-v[[paste0(side,"_import")]]
    brohn_require(!is.null(ref)&&!is.null(imp),"Choose both original recordings and their preserved imports.")
    marker<-input[[paste0("clock_",side,"_marker")]];tracks<-input[[paste0("clock_",side,"_tracks")]]
    brohn_require(length(marker)==1L&&nzchar(marker)&&length(tracks)>=1L&&length(tracks)<=2L,"Choose one event channel and one or two measurement channels for each recording.")
    list(dataset_id=ref$id,import_id=imp$id,marker=brohn_parse(marker),tracks=lapply(as.list(tracks),brohn_parse))});stats::setNames(out,c("source","reference"))}
  shiny::observe({fresh<-tryCatch(selections(),error=function(e)NULL)
    if(!is.null(v$selections)&&!.brohn_cm_same(fresh,v$selections))shiny::isolate({invalidate();v$map<-NULL;v$editing<-NULL;v$issue<-"The recording or channel selection changed. Load the selected recordings' original events again."})})
  check_slots<-function()if(v$checks>0L)paste0("check",seq_len(v$checks))else character()
  selected_keys<-function(side)unlist(lapply(c("start","end",check_slots()),function(slot)input[[paste0("clock_",side,"_",slot)]]),use.names=FALSE)
  accept_page<-function(side,record){pool<-v$pool;old<-pool[[side]];kept<-selected_keys(side);old<-old[names(old)%in%kept]
    for(e in record$body$result$events)if(isTRUE(e$selectable)){
      same_row<-Filter(function(item)identical(item$event$source_sequence,e$source_sequence),old)
      if(length(same_row)){
        brohn_require(all(vapply(same_row,function(item).brohn_cm_same(item$event,e),logical(1))),
          "Overlapping pages disagree about an original event. Load the recording again before selecting it.")
        next
      }
      choice<-list(page=.brohn_cm_ref(record),sequence=e$source_sequence)
      old[[brohn_json(choice)]]<-list(choice=choice,event=e,label=brohn_clock_event_label(e))}
    pool[[side]]<-old;v$pool<-pool;v[[paste0(side,"_events")]]<-record}
  for(side in c("source","reference"))local({side<-side
    output[[paste0("clock_",side,"_event_status")]]<-shiny::renderUI({p<-v[[paste0(side,"_events")]];if(is.null(p))return(shiny::p("Load recorded events to choose original rows."));r<-p$body$result
      shiny::p(paste(length(r$events),"rows on this page;",r$matched_rows,"matches across",r$source_rows,"original rows;",r$selectable_source_rows,"can define an anchor.",
        "Rows without original observed time/value cannot be selected."))})
    event_page<-function(offset,query){brohn_require(!is.null(v$selections),"Load both recordings first.")
      start("eventpage",list(side=side,offset=offset,query=query),paste("Loading original",side,"events."))}
    shiny::observeEvent(input[[paste0("clock_",side,"_search")]],safe(function()event_page(0L,brohn_default(input[[paste0("clock_",side,"_query")]],""))))
    shiny::observeEvent(input[[paste0("clock_",side,"_next")]],safe(function(){p<-v[[paste0(side,"_events")]];brohn_require(!is.null(p)&&isTRUE(p$body$result$has_next),"There are no later events in this search.");event_page(p$body$result$next_offset,p$body$result$query)}))
    shiny::observeEvent(input[[paste0("clock_",side,"_previous")]],safe(function(){p<-v[[paste0(side,"_events")]];brohn_require(!is.null(p)&&p$body$result$offset>0,"This is the first event page.");event_page(max(0,p$body$result$offset-p$body$result$limit),p$body$result$query)}))
  })
  output$clock_pairs<-shiny::renderUI({if(is.null(v$source_events)||is.null(v$reference_events))return(NULL)
    slots<-c("start","end",check_slots())
    shiny::div(shiny::h4(`data-clock-review-complete`=if(v$result_kind%in%c("events","eventpage"))v$result_ticket else NULL,tabindex="-1",
      "Choose original event pairs"),lapply(seq_along(slots),function(i)shiny::tags$fieldset(shiny::tags$legend(if(i==1L)"Start event pair"else if(i==2L)"End event pair"else paste("Independent check",i-2L)),
      lapply(c("source","reference"),function(side){pool<-v$pool[[side]];id<-paste0("clock_",side,"_",slots[[i]]);selected<-shiny::isolate(input[[id]])
        options<-c("Choose an original event"="",stats::setNames(names(pool),vapply(pool,`[[`,character(1),"label")))
        shiny::selectInput(id,tools::toTitleCase(side),options,selected=if(length(selected)==1L&&selected%in%names(pool))selected else "",selectize=FALSE)}))))})
  shiny::observeEvent(input$clock_check_add,safe(function(){brohn_require(v$checks<16L,"Use at most sixteen independent event checks.");v$checks<-v$checks+1L}))
  shiny::observeEvent(input$clock_check_remove,{if(v$checks>0L)v$checks<-v$checks-1L})
  form<-function(){pair<-function(slot)stats::setNames(lapply(c("source","reference"),function(side){key<-input[[paste0("clock_",side,"_",slot)]]
    brohn_require(length(key)==1L&&nzchar(key)&&key%in%names(v$pool[[side]]),"Choose each original defining event and every added independent check.")
    v$pool[[side]][[key]]$choice}),c("source","reference"))
    list(selections=selections(),anchors=lapply(c("start","end"),pair),checks=lapply(check_slots(),pair),
      review=list(confirmed=isTRUE(input$clock_confirm),rationale=brohn_default(input$clock_rationale,"")))}
  shiny::observeEvent(input$clock_events_load,safe(function(){s<-selections();invalidate();v$selections<-s;start("events",label="Loading both recordings' original events.")}))
  shiny::observeEvent(input$clock_preview,safe(function(){f<-form();v$preview<-NULL;release();start("preview",f,"Preparing the reviewed event alignment.")}))
  shiny::observe({f<-tryCatch(form(),error=function(e)NULL);if(!is.null(v$preview)&&!.brohn_cm_same(f,v$preview$form))shiny::isolate({v$preview<-NULL;v$issue<-"Event choices or rationale changed. Preview the updated pairs before saving."})})
  output$clock_preview_result<-shiny::renderUI({p<-v$preview;if(is.null(p))return(NULL);s<-brohn_clock_preview_summary(p$record)
    shiny::div(shiny::h3(`data-clock-review-complete`=if(identical(v$result_kind,"preview"))v$result_ticket else NULL,tabindex="-1","Alignment preview"),
      shiny::p(paste("Supported review span: 0 to",s$span_seconds,"seconds from the reference start event.")),
      shiny::p(s$uncertainty),if(length(s$checks))shiny::tags$ul(lapply(s$checks,function(c)shiny::tags$li(paste("Rows",c$source_row,"and",c$reference_row,
        "| mapped minus reference:",c$approximate_residual_seconds,"seconds (approximate); exact",c$signed_residual_seconds)))),
      shiny::tags$details(shiny::tags$summary("Exact mapping and source evidence"),shiny::tags$pre(style="white-space:pre-wrap;overflow-wrap:anywhere",brohn_json(p$record$body,TRUE))))})
  shiny::observeEvent(input$clock_save,safe(function(){p<-v$preview;brohn_require(!is.null(p)&&.brohn_cm_same(form(),p$form),"Preview the current original-event choices before saving.")
    title<-brohn_default(input$clock_name,"");brohn_require(brohn_text(title,240)&&nzchar(trimws(title)),"Give this alignment a name.")
    previous<-v$last_save
    if(!is.null(previous)&&identical(title,previous$title)&&.brohn_cm_same(p$form,previous$form)&&.brohn_cm_same(.brohn_cm_ref(p$record),previous$preview)){
      v$issue<-paste("This alignment is already saved as version",previous$map$revision,". Open it from saved alignments to review it again.");return()}
    old<-v$editing;start("save",list(preview=.brohn_cm_ref(p$record),form=p$form,title=title,map_id=if(is.null(old))brohn_id("alignment")else old$id,
      revision=if(is.null(old))0L else old$revision,operation_id=brohn_id("save")),"Saving the reviewed alignment and preparing original measurements.")}))
  shiny::observeEvent(input$clock_edit_map,safe(function(){map<-v$map;brohn_require(!is.null(map),"Open a named alignment before revising it.")
    b<-map$body;brohn_require(identical(b$request$selections$source$dataset_id,dataset()$id),"Open this alignment's original source recording before revising its event pairs.")
    invalidate();v$channel_defaults<-b$request$selections
    for(side in c("source","reference")){r<-b$request$recordings[[side]];v[[side]]<-.brohn_cm_ref(brohn_get_entity(store,"dataset",r$dataset$id));v[[paste0(side,"_import")]]<-r$imported}
    v$editing<-.brohn_cm_ref(map);v$issue<-"Choose and preview the revised event pairs. Saving will create a new version of this alignment."}))
  # Dispatch and saved-window resources are installed separately below so their
  # exact-source lifetime can be tested without replacing the researcher form.
  brohn_install_clock_review_dispatch(input,output,session,store,v,native,dataset,selections,form,start,safe,release,accept_page)
  invisible(list(state=v,close=close,form=form,selections=selections))
}
