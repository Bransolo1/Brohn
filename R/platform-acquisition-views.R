# Researcher-reviewed local acquisition; no device is started by rendering UI.
brohn_acquisition_quality_text <- function(inspection) {
  if(identical(inspection$quality_evidence,"verified_final_manifest") &&
     identical(inspection$quality_qualified,FALSE) && identical(inspection$signal_quality,"not_qualified"))
    "Signal quality: not qualified. Review the recorded signals before research analysis."
  else "Signal quality: not evaluated here. Final quality evidence is unavailable; review the preserved source before research analysis."
}
brohn_acquisition_ui <- function(store, study) {
  brohn_card(title="Record local research streams", subtitle="Choose the sources, confirm their units and participant identity, then record into this study's history.",
    shiny::p(class="brohn-muted","This local profile supports one recording at a time. An LSL source application must already be running. Device calibration and physical timing still require their own evidence."),
    shiny::uiOutput("acquisition_manager_status"),
    shiny::textInput("acq_lsl_session","LSL session (must match the source application)","default"),
    shiny::textAreaInput("acq_source_ids","Exact source IDs, one per line (optional)","",rows=3),
    shiny::checkboxInput("acq_discovery_confirm","Discover metadata from local sources in this session",FALSE),
    shiny::actionButton("acq_discover","Find local sources",class="btn-primary"),
    shiny::uiOutput("acquisition_discovery_review"),shiny::uiOutput("acquisition_selection_review"),
    shiny::uiOutput("acquisition_recordings"))
}

brohn_acquisition_form_current <- function(state, input) {
  identical(state$page,"study") && identical(state$stage,"Collect") &&
    brohn_valid_id(state$study_id) &&
    identical(input$study_form_identity,paste(state$study_id,"Collect",sep=":"))
}
brohn_install_acquisition_server <- function(input,output,session,store,state,attempt,refresh,message,prepare_download) {
  current_study <- shiny::reactive({
    state$refresh; shiny::req(brohn_acquisition_form_current(state,input))
    brohn_study(store,state$study_id)
  })
  pulse <- shiny::reactive({shiny::invalidateLater(1000,session); Sys.time()})
  discoveries <- shiny::reactiveVal(list())
  shiny::observe({
    pulse(); s<-current_study(); current<-brohn_lsl_discoveries(store,s$id)
    # Keep reviewed inputs mounted while status polling continues elsewhere.
    if(!identical(current,shiny::isolate(discoveries()))) discoveries(current)
  })
  latest <- shiny::reactive({
    found <- Filter(function(d) identical(d$body$status,"ready"),discoveries())
    if(length(found)) found[[1L]] else NULL
  })
  chosen <- shiny::reactive({
    d <- latest(); shiny::req(!is.null(d))
    ids <- brohn_default(input$acq_selected_uids,character())
    Filter(function(s) s$uid %in% ids,d$body$result$streams)
  })
  output$acquisition_manager_status <- shiny::renderUI({
    pulse()
    if(brohn_acquisition_ready(store$root)) brohn_badge("Local recorder ready","success") else
      shiny::p(class="brohn-alert brohn-alert-warning","The local acquisition manager is unavailable. Start Brohn with its integrated launcher before recording; queued requests remain saved.")
  })
  shiny::observeEvent(input$acq_discover,attempt(function() {
    s<-current_study()
    sources<-trimws(strsplit(brohn_default(input$acq_source_ids,""),"\n",fixed=TRUE)[[1L]]);sources<-sources[nzchar(sources)]
    brohn_queue_lsl_discovery(store,s$id,input$acq_lsl_session,sources,isTRUE(input$acq_discovery_confirm))
    message("Local source metadata discovery queued. Recording starts only after your review.")
  }))
  output$acquisition_discovery_review <- shiny::renderUI({
    all<-discoveries(); d<-latest()
    shiny::tagList(
      if(length(all)) shiny::p(paste("Latest discovery:",all[[1L]]$body$status)),
      if(length(all) && !is.null(all[[1L]]$body$error)) shiny::p(class="brohn-alert brohn-alert-warning",all[[1L]]$body$error),
      if(length(all) && all[[1L]]$body$status %in% c("interrupted","failed"))
        brohn_command("Retry these sources","acq_retry_discovery",list(id=all[[1L]]$id,revision=all[[1L]]$revision,request_hash=all[[1L]]$body$request_hash)),
      if(!is.null(d)) {
        streams<-d$body$result$streams
        supported<-Filter(function(s) isTRUE(s$supported),streams)
        choices<-stats::setNames(vapply(supported,`[[`,character(1),"uid"),vapply(supported,function(s)
          paste(s$name,"-",s$type,"-",s$channel_count,"channels"),character(1)))
        shiny::tagList(
          if(!length(streams)) shiny::p("No matching local source was found. Check the source application's LSL session and source ID."),
          shiny::selectInput("acq_selected_uids","Sources to record",choices,selected=character(),multiple=TRUE),
          shiny::tags$details(shiny::tags$summary("Source metadata and transport support"),brohn_table(lapply(streams,function(s)
            list(name=s$name,type=s$type,uid=s$uid,source_id=s$source_id,channels=s$channel_count,format=s$value_type,
              nominal_hz=s$nominal_srate,source_origin=s$source_origin,supported=s$supported,reason=s$support_reason)),maximum=64L,label="Local LSL sources")))
      })
  })
  shiny::observeEvent(input$acq_retry_discovery,attempt(function() {
    s<-current_study();command<-input$acq_retry_discovery;prior<-brohn_get_entity(store,"acquisition_discovery",command$id)
    brohn_require(!is.null(prior) && identical(prior$body$study_id,s$id) && identical(prior$body$request_hash,command$request_hash),
      "This retry control belongs to a different study or discovery request.")
    brohn_retry_lsl_discovery(store,prior$id,command$revision)
    message("A new discovery of the same reviewed source scope is queued. The interrupted request remains in history.")
  }))
  # The selected form depends on discovery identity and selection, not on the
  # one-second status pulse; editing units must not reset their inputs.
  stable_discovery <- shiny::reactive({d<-latest(); if(is.null(d)) NULL else list(id=d$id,hash=d$body$result_hash)})
  output$acquisition_selection_review <- shiny::renderUI({
    key<-stable_discovery(); shiny::req(!is.null(key)); selected<-chosen(); if(!length(selected)) return(NULL)
    study<-current_study()
    shiny::tagList(
      shiny::div(style="display:none",shiny::textInput("acq_form_identity",NULL,paste(study$id,study$revision,key$id,key$hash,sep=":"))),
      lapply(seq_along(selected),function(i) {s<-selected[[i]]
        shiny::tags$fieldset(class="brohn-stack",shiny::tags$legend(s$name),
          shiny::p(paste("Source declares",brohn_default(s$source_origin,"no collection origin"),"and",s$value_type,"samples.")),
          shiny::selectInput(paste0("acq_kind_",i),"Stream role",c("Signal"="signal","Event markers"="markers","Unclassified"="unclassified"),selected=if(s$value_type=="string") "markers" else "signal"),
          shiny::textInput(paste0("acq_clock_",i),"Source clock identity",paste0("lsl-",s$uid)),
          shiny::selectInput(paste0("acq_clock_kind_",i),"Source timestamp clock",c("Epoch not established"="unspecified_epoch","Monotonic clock"="monotonic","Device clock"="device","Unix clock"="unix")),
          lapply(seq_along(s$channels),function(j) {channel<-s$channels[[j]]
            shiny::textInput(paste0("acq_unit_",i,"_",j),paste(brohn_default(channel$label,paste("Channel",j)),"- original unit"),brohn_default(channel$unit,if(s$value_type=="string") "marker" else "unknown"))}),
          shiny::numericInput(paste0("acq_gap_",i),"Gap threshold in seconds (optional)",NA_real_,min=.000001,max=3600))}),
      shiny::textInput("acq_participant","Participant ID (explicit linkage)",""),
      shiny::textInput("acq_session_identity","Recording session ID", ""),
      shiny::selectInput("acq_run_id","Optional explicit participant-run binding",{
        runs<-Filter(function(r) identical(brohn_hash(r$protocol$design),brohn_hash(study$body)),brohn_runs(store,study$id))
        c("No participant-run binding"="",stats::setNames(vapply(runs,`[[`,character(1),"id"),vapply(runs,function(r)
          paste(r$participant_alias,r$created_at,r$origin,sep=" - "),character(1))))
      }),
      shiny::selectInput("acq_origin","Collection origin",c("Choose the origin"="","Synthetic / sample"="sample","Pilot"="pilot","Live research"="live")),
      shiny::textAreaInput("acq_provenance","Source and unit review notes", "",rows=3),
      shiny::numericInput("acq_duration","Stop after at most this many seconds",600,min=.1,max=86400),
      shiny::tags$details(shiny::tags$summary("Recording limits"),
        shiny::numericInput("acq_max_samples","Maximum received samples across all selected sources",100000,min=1,max=2000000),
        shiny::numericInput("acq_max_mib","Maximum sample-data MiB (plus bounded manifest overhead)",64,min=1,max=512),
        shiny::numericInput("acq_chunk","Samples per pull",256,min=1,max=512),
        shiny::numericInput("acq_buffer","Native inlet buffer: seconds for regular streams, hundreds of samples for irregular streams",5,min=1,max=60)),
      shiny::checkboxInput("acq_reviewed","I reviewed the selected source identities, every channel unit, source clocks, origin and participant/session IDs",FALSE),
      shiny::actionButton("acq_start","Start reviewed recording",class="btn-primary"))
  })
  shiny::observeEvent(input$acq_start,attempt(function() {
    s<-current_study();d<-latest();selected<-chosen()
    brohn_require(!is.null(d) && identical(input$acq_form_identity,paste(s$id,s$revision,d$id,d$body$result_hash,sep=":")),"This discovery or study changed. Reopen and review the source form.")
    selections<-lapply(seq_along(selected),function(i) {
      observed<-selected[[i]]
      channels<-lapply(seq_along(observed$channels),function(j) list(id=paste0("channel-",j),label=brohn_default(observed$channels[[j]]$label,paste("Channel",j)),
        type=brohn_default(observed$channels[[j]]$type,brohn_default(observed$type,"unclassified")),unit=input[[paste0("acq_unit_",i,"_",j)]],value_type=observed$value_type))
      gap<-input[[paste0("acq_gap_",i)]];if(is.null(gap)||is.na(gap)) gap<-NULL
      brohn_lsl_selection(d,observed$uid,paste0("stream-",i),input[[paste0("acq_clock_",i)]],input[[paste0("acq_clock_kind_",i)]],input[[paste0("acq_kind_",i)]],channels,input$acq_provenance,gap)
    })
    r<-brohn_queue_acquisition(store,s$id,d$id,selections,list(participant_id=input$acq_participant,session_id=input$acq_session_identity),input$acq_origin,input$acq_provenance,
      list(max_duration_s=input$acq_duration,max_samples=input$acq_max_samples,max_bytes=input$acq_max_mib*1024^2,chunk_samples=input$acq_chunk,inlet_buffer=input$acq_buffer),s$revision,isTRUE(input$acq_reviewed),
      run_id=if(is.null(input$acq_run_id)||!nzchar(input$acq_run_id)) NULL else input$acq_run_id)
    message("Recording queued for the independent local manager. Browser disconnection does not stop collection.");refresh()
  }))
  output$acquisition_recordings <- shiny::renderUI({
    pulse();s<-current_study();records<-brohn_acquisitions(store,s$id)
    if(!length(records)) return(NULL)
    shiny::tagList(shiny::h3("Recording history"),lapply(head(records,20L),function(record) {
      r<-brohn_acquisition(store,record$id);b<-r$body;snapshot<-r$live_snapshot
      brohn_card(title=b$title,subtitle=paste(b$created_at,"-",b$status),
        shiny::p(paste("Origin:",b$origin,". Participant:",b$request$identity$participant_id,". Session:",b$request$identity$session_id)),
        if(!is.null(snapshot)) shiny::p(paste(snapshot$samples,"received samples;",snapshot$chunks,"committed chunks.")),
        if(is.null(b$original)) shiny::p("Signal quality still requires review; live counts do not establish valid research data."),
        if(!is.null(b$error)) shiny::p(class="brohn-alert brohn-alert-warning",b$error),
        if(b$status %in% c("queued","starting","recording","stopping")) shiny::div(class="brohn-toolbar",
          brohn_command("Stop and save","acq_stop",list(id=r$id,request_hash=b$request_hash,cancel=FALSE)),
          brohn_command("Cancel recording","acq_stop",list(id=r$id,request_hash=b$request_hash,cancel=TRUE))),
        if(!is.null(b$original)) shiny::tagList(
          shiny::p(paste("Original preserved:",b$inspection$samples,"samples;",b$completion_status,". Full raw evidence and clock observations are retained.")),
          shiny::p(brohn_acquisition_quality_text(b$inspection)),
          brohn_command("Download original recording","acq_download",list(id=r$id,hash=b$original$hash)),
          if(is.null(b$import_dataset_id)) brohn_command(if(b$completion_status=="completed") "Prepare separate datasets" else "Review and import this incomplete subset",
            "acq_review",list(id=r$id,original_hash=b$original$hash,allow_incomplete=b$completion_status!="completed")),
          if(!is.null(b$review)) shiny::p(paste("Dataset preparation:",b$review$status,brohn_default(b$review$error,""))),
          if(!is.null(b$import_dataset_id)) brohn_command("Open prepared recording","open_dataset",b$import_dataset_id)))
    }),if(length(records)>20L) shiny::p(paste(length(records)-20L,"older recordings are retained in the workspace catalog.")))
  })
  shiny::observeEvent(input$acq_stop,attempt(function() {
    command<-input$acq_stop;r<-brohn_acquisition(store,command$id)
    brohn_require(identical(r$body$study_id,current_study()$id) && identical(r$body$request_hash,command$request_hash),"This stop control belongs to another recording.")
    brohn_stop_acquisition(store,r$id,r$revision,isTRUE(command$cancel));message("Stop request saved for this exact recording.")
  }))
  shiny::observeEvent(input$acq_review,attempt(function() {
    command<-input$acq_review;r<-brohn_acquisition(store,command$id)
    brohn_require(identical(r$body$study_id,current_study()$id) && identical(r$body$original$hash,command$original_hash),"This review belongs to another original recording.")
    brohn_review_acquisition(store,r$id,r$revision,isTRUE(command$allow_incomplete));message("The verified original will be exported into separate curatable datasets, preserving clocks.")
  }))
  download <- shiny::reactiveVal(NULL)
  shiny::observeEvent(input$acq_download,attempt(function() {
    command<-input$acq_download;r<-brohn_acquisition(store,command$id)
    brohn_require(identical(r$body$study_id,current_study()$id)&&identical(r$body$original$hash,command$hash),"This download belongs to another original recording.")
    download(r);shiny::showModal(shiny::modalDialog(title="Download original recording",shiny::p("Includes the full original recording, explicit participant/session IDs and clock evidence. Keep it private."),
      shiny::downloadButton("acquisition_original_download","Download verified original",icon=NULL),easyClose=TRUE))
  }))
  output$acquisition_original_download <- shiny::downloadHandler(filename=function() paste0(download()$id,".brohn-acquisition.zip"),content=function(file) {
    prepare_download(function() {r<-download();shiny::req(!is.null(r));brohn_copy_object_download(store,r$body$original$hash,file)})
  },contentType="application/zip")
  invisible(NULL)
}
