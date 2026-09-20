brohn_acquisition_selection_input <- function(discovery,observed,i,input,require_review=TRUE) {
  channels<-lapply(seq_along(observed$channels),function(j)list(id=paste0("channel-",j),label=brohn_default(observed$channels[[j]]$label,paste("Channel",j)),
    type=brohn_default(observed$channels[[j]]$type,brohn_default(observed$type,"unclassified")),unit=input[[paste0("acq_unit_",i,"_",j)]],value_type=observed$value_type))
  gap<-input[[paste0("acq_gap_",i)]];if(is.null(gap)||is.na(gap))gap<-NULL
  readiness<-list(schema="brohn-acquisition-readiness/1.1",modality=input[[paste0("acq_measurement_",i)]],acquisition_checks=brohn_acquisition_checks_input(input,i,channels,require_review),
    channels=lapply(seq_along(channels),function(j){item<-list(id=channels[[j]]$id,role=input[[paste0("acq_role_",i,"_",j)]])
      for(rail in c("min","max")){value<-input[[paste0("acq_rail_",rail,"_",i,"_",j)]];if(!is.null(value)&&!is.na(value))item[[paste0("rail_",rail)]]<-value};item}),
    preview_channels=as.list(paste0("channel-",input[[paste0("acq_preview_",i)]])))
  for(field in c("reference","site","calibration","frame","gravity_policy","wavelengths","task_identity")) {
    key<-if(field=="gravity_policy")"gravity"else field;readiness[[field]]<-input[[paste0("acq_",key,"_",i)]]
  }
  if(isTRUE(input[[paste0("acq_gaze_enabled_",i)]]))readiness$gaze<-list(eye=input[[paste0("acq_gaze_eye_",i)]],
    unit=input[[paste0("acq_gaze_unit_",i)]],frame=readiness$frame,origin=input[[paste0("acq_gaze_origin_",i)]],valid_value=input[[paste0("acq_gaze_valid_",i)]])
  if(!is.null(readiness$gaze)&&identical(readiness$gaze$unit,"px")) {
    readiness$gaze$width<-input[[paste0("acq_gaze_width_",i)]];readiness$gaze$height<-input[[paste0("acq_gaze_height_",i)]]
  }
  notes<-input$acq_provenance
  if(!require_review&&!brohn_text(notes,1000))notes<-"Pending equipment settings; collection provenance must be reviewed separately."
  brohn_lsl_selection(discovery,observed$uid,paste0("stream-",i),input[[paste0("acq_clock_",i)]],
    input[[paste0("acq_clock_kind_",i)]],input[[paste0("acq_kind_",i)]],channels,notes,gap,readiness)
}
brohn_equipment_check_form_values <- function(configuration,i) {
  values<-list()
  for(j in seq_along(configuration$readiness$acquisition_checks)) {
    rule<-configuration$readiness$acquisition_checks[[j]];prefix<-paste0("acq_check_",i,"_",j,"_")
    for(field in c("name","version","kind","lower","upper","minimum_samples","minimum_span_s","maximum_age_s","source","rationale"))
      if(!is.null(rule[[field]]))values[[paste0(prefix,field)]]<-rule[[field]]
    values[[paste0(prefix,"channel")]]<-match(rule$channel_id,vapply(configuration$channels,`[[`,character(1),"id"))
    values[[paste0(prefix,"fraction")]]<-rule$minimum_fraction
    values[[paste0(prefix,"codes")]]<-paste(unlist(rule$accepted_values),collapse="\n")
    values[[paste0(prefix,"reviewed")]]<-FALSE
  }
  values
}
brohn_install_equipment_setup_server <- function(input,output,session,store,current_study,latest,chosen,reviewed_checks,attempt,message) {
  applied<-shiny::reactiveValues();seeds<-shiny::reactiveValues();library_version<-shiny::reactiveVal(0L)
  library_study<-NULL
  shiny::observe({s<-current_study();if(!identical(library_study,s$id)) {
    library_study<<-s$id;library_version(shiny::isolate(library_version())+1L)
  }})
  consumed<-new.env(parent=emptyenv());whole_review<-shiny::reactiveVal(NULL)
  binding_key<-function(uid){d<-latest();paste(d$id,d$body$result_hash,uid,sep=":")}
  token<-function(record)paste(record$id,record$revision,brohn_hash(record$body),sep="|")
  selected_setup<-function(i) {
    parts<-strsplit(brohn_default(input[[paste0("acq_setup_choice_",i)]],""),"|",fixed=TRUE)[[1L]]
    brohn_require(length(parts)==3L,"Choose a saved equipment setup revision.")
    brohn_equipment_setup(store,parts[[1L]],as.integer(parts[[2L]]),parts[[3L]])
  }
  current<-function(i) {
    s<-current_study();d<-latest();sources<-chosen()
    brohn_require(!is.null(d)&&length(sources)>=i&&identical(input$acq_form_identity,paste(s$id,s$revision,d$id,d$body$result_hash,sep=":")),
      "This source form changed. Reopen and review its current study and discovery.")
    list(study=s,discovery=d,observed=sources[[i]])
  }
  clear_review<-function(i) {
    whole_review(NULL);shiny::updateCheckboxInput(session,"acq_reviewed",value=FALSE)
    for(j in seq_len(8L)){reviewed_checks[[paste(i,j,sep="_")]]<-NULL;shiny::updateCheckboxInput(session,paste0("acq_check_",i,"_",j,"_reviewed"),value=FALSE)}
  }
  for(index in seq_len(16L))local({i<-index
    output[[paste0("acq_setup_controls_",i)]]<-shiny::renderUI({
      # The enclosing source form owns mounting/unmounting. Depending on chosen()
      # here causes a second nested replacement to erase a just-selected setup
      # during study navigation. Only a library revision rebuilds these controls.
      library_version();records<-brohn_equipment_setups(store)
      choices<-c("Choose a saved setup"="",stats::setNames(vapply(records,token,character(1)),vapply(records,function(r)paste(r$body$title,"- revision",r$revision),character(1))))
      prior<-shiny::isolate(input[[paste0("acq_setup_choice_",i)]])
      shiny::tags$details(shiny::tags$summary("Reusable equipment setup"),
        shiny::div(class="brohn-stack",style="min-width:0;grid-template-columns:minmax(0,1fr)",
        shiny::p("Save measurement settings for reuse across studies. Applying a setup only fills this source form; review the current source and every acquisition check before recording."),
        shiny::selectInput(paste0("acq_setup_choice_",i),"Saved equipment setup",choices,selected=if(length(prior)==1L&&prior %in% choices)prior else ""),
        shiny::uiOutput(paste0("acq_setup_comparison_",i)),
        shiny::actionButton(paste0("acq_setup_apply_",i),"Apply settings to this source"),
        shiny::textInput(paste0("acq_setup_title_",i),"Equipment setup name",shiny::isolate(brohn_default(input[[paste0("acq_setup_title_",i)]],""))),
        shiny::div(class="brohn-toolbar",shiny::actionButton(paste0("acq_setup_save_",i),"Save as new equipment setup"),
          shiny::actionButton(paste0("acq_setup_revise_",i),"Save new revision of selected setup")),
        shiny::actionButton(paste0("acq_setup_detach_",i),"Detach setup reference and review current settings"),
        shiny::uiOutput(paste0("acq_setup_applied_",i))))
    })
    output[[paste0("acq_setup_comparison_",i)]]<-shiny::renderUI({
      streams<-chosen();shiny::req(length(streams)>=i)
      if(!nzchar(brohn_default(input[[paste0("acq_setup_choice_",i)]],"")))return(NULL)
      tryCatch({r<-selected_setup(i);comparison<-brohn_compare_equipment_source(r,streams[[i]])
        if(comparison$matches)shiny::p("The stable source descriptor and complete ordered channel metadata match. The current outlet identity and all reviews will be checked again.") else
          shiny::tagList(shiny::p(class="brohn-alert brohn-alert-warning","Source metadata differs. Applying these channel maps is blocked; review this current source manually and save a new revision."),
            shiny::tags$dl(lapply(comparison$differences,function(change)shiny::tagList(shiny::tags$dt(change$field),
              shiny::tags$dd(style="margin-bottom:16px;overflow-wrap:anywhere",
                shiny::div(shiny::strong("Saved: "),if(is.null(change$saved))"Not declared"else as.character(change$saved)),
                shiny::div(shiny::strong("Current: "),if(is.null(change$current))"Not declared"else as.character(change$current)))))))
      },error=function(e)shiny::p(class="brohn-alert brohn-alert-warning",conditionMessage(e)))
    })
    output[[paste0("acq_setup_applied_",i)]]<-shiny::renderUI({
      streams<-chosen();shiny::req(length(streams)>=i);a<-applied[[binding_key(streams[[i]]$uid)]]
      if(is.null(a))return(NULL)
      shiny::p(class="brohn-muted",paste("Pending settings from",a$title,"revision",a$reference$revision,". No approval was copied. Current edits and source review are frozen separately when recording starts."))
    })
    shiny::observeEvent(input[[paste0("acq_setup_apply_",i)]],attempt(function() {
      c<-current(i);r<-selected_setup(i);a<-brohn_apply_equipment_setup(store,r$id,r$revision,brohn_hash(r$body),c$discovery$id,c$observed$uid)
      clear_review(i);applied[[binding_key(c$observed$uid)]]<-c(a,list(title=r$body$title));config<-a$configuration;readiness<-config$readiness
      text<-function(field,value)shiny::updateTextInput(session,paste0("acq_",field,"_",i),value=brohn_default(value,""))
      select<-function(field,value)shiny::updateSelectInput(session,paste0("acq_",field,"_",i),selected=value)
      number<-function(field,value)shiny::updateNumericInput(session,paste0("acq_",field,"_",i),value=brohn_default(value,NA_real_))
      select("kind",config$kind);select("clock_kind",config$clock_kind);select("measurement",readiness$modality)
      for(j in seq_along(config$channels)) {
        shiny::updateTextInput(session,paste0("acq_unit_",i,"_",j),value=brohn_default(config$channels[[j]]$unit,""))
        shiny::updateSelectInput(session,paste0("acq_role_",i,"_",j),selected=readiness$channels[[j]]$role)
        for(rail in c("min","max"))shiny::updateNumericInput(session,paste0("acq_rail_",rail,"_",i,"_",j),value=brohn_default(readiness$channels[[j]][[paste0("rail_",rail)]],NA_real_))
      }
      select("preview",sub("^channel-","",unlist(readiness$preview_channels)))
      for(field in c("reference","site","calibration","frame","gravity_policy","wavelengths","task_identity"))text(if(field=="gravity_policy")"gravity"else field,readiness[[field]])
      shiny::updateCheckboxInput(session,paste0("acq_gaze_enabled_",i),value=!is.null(readiness$gaze))
      for(field in c("eye","unit","origin"))select(paste0("gaze_",field),brohn_default(readiness$gaze[[field]],switch(field,eye="left",unit="normalized",origin="unspecified")))
      for(field in c("width","height"))number(paste0("gaze_",field),readiness$gaze[[field]])
      number("gaze_valid",readiness$gaze$valid_value);number("gap",config$gap_threshold_s)
      seeds[[as.character(i)]]<-list(nonce=brohn_id("prefill"),configuration=config)
      shiny::updateNumericInput(session,paste0("acq_checks_count_",i),value=length(readiness$acquisition_checks))
      shiny::updateTextInput(session,paste0("acq_setup_title_",i),value=r$body$title)
      message("Equipment settings filled for this exact current source. Review the source, units and every acquisition check before starting.")
    }))
    save<-function(revise=FALSE) {
      c<-current(i);selection<-brohn_acquisition_selection_input(c$discovery,c$observed,i,input,FALSE)
      prior<-if(revise)selected_setup(i) else NULL
      saved<-brohn_save_equipment_setup(store,input[[paste0("acq_setup_title_",i)]],c$discovery$id,c$observed$uid,selection,
        if(is.null(prior))NULL else prior$id,if(is.null(prior))0L else prior$revision)
      library_version(shiny::isolate(library_version())+1L)
      message(paste("Saved equipment setup",saved$body$title,"revision",saved$revision,". Recording identities and approvals are not part of the setup."))
    }
    shiny::observeEvent(input[[paste0("acq_setup_save_",i)]],attempt(function()save(FALSE)))
    shiny::observeEvent(input[[paste0("acq_setup_revise_",i)]],attempt(function()save(TRUE)))
    shiny::observeEvent(input[[paste0("acq_setup_detach_",i)]],attempt(function(){c<-current(i);applied[[binding_key(c$observed$uid)]]<-NULL;clear_review(i)
      message("Setup reference detached. Current source settings remain in the form and require review before recording.")}))
  })
  references<-function(validate=FALSE) {
    streams<-chosen();d<-latest();refs<-list()
    for(i in seq_along(streams)) {
      a<-applied[[binding_key(streams[[i]]$uid)]];if(is.null(a))next
      expected<-list(discovery_id=d$id,discovery_hash=d$body$result_hash,uid=streams[[i]]$uid,metadata_sha256=streams[[i]]$metadata_sha256)
      if(validate)brohn_require(identical(brohn_hash(a$binding),brohn_hash(expected)),"The applied equipment setup belongs to an earlier discovery. Apply it to the current source and review again.")
      refs[[paste0("stream-",i)]]<-a$reference
    }
    refs
  }
  signature<-function() {
    refs<-references(TRUE);if(!length(refs))return(NULL)
    d<-latest();streams<-chosen()
    brohn_hash(list(references=refs,discovery=d$body$result_hash,streams=lapply(seq_along(streams),function(i){s<-streams[[i]]
      list(uid=s$uid,metadata=s$metadata_sha256,configuration=brohn_equipment_configuration(brohn_acquisition_selection_input(d,s,i,input,FALSE)))})))
  }
  shiny::observeEvent(input$acq_reviewed,{whole_review(if(isTRUE(input$acq_reviewed))tryCatch(signature(),error=function(e)NULL)else NULL)},ignoreInit=TRUE)
  shiny::observe({prior<-whole_review();if(is.null(prior))return();now<-tryCatch(signature(),error=function(e)NULL)
    if(!identical(prior,now)){whole_review(NULL);shiny::updateCheckboxInput(session,"acq_reviewed",value=FALSE)}})
  list(check_seed=function(i){seed<-seeds[[as.character(i)]];if(is.null(seed)||identical(consumed[[as.character(i)]],seed$nonce))return(NULL)
      consumed[[as.character(i)]]<-seed$nonce;seed$configuration},
    references=function(){refs<-references(TRUE);if(length(refs))brohn_require(isTRUE(input$acq_reviewed)&&identical(whole_review(),signature())&&!is.null(whole_review()),
      "The equipment settings changed or have not been reviewed for this source. Review the current recording form again.");refs})
}
