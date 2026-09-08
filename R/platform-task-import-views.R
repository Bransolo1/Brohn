brohn_task_import_evidence_ui <- function(analysis) {
  if (!identical(analysis$kind,"implicit") || !length(analysis$task_attempts)) return(NULL)
  shiny::tags$details(shiny::tags$summary("Review original trial support"),
    shiny::p("Each administration keeps its source rows, expected missing trials and scoring exclusions. A candidate trial may still belong to an excluded administration; inspect its task result above."),
    lapply(head(analysis$task_attempts,40L),function(a)shiny::tags$details(
      shiny::tags$summary(paste("Participant",a$participant_id,"\u00b7 session",a$session_id,"\u00b7 attempt",a$source_attempt_id)),
      shiny::p(paste("Recorded outcome:",a$completion_status)),
      shiny::p(if(isTRUE(a$timing_quality$definitions_known)) "The source declares the required response-time and completion definitions." else "The source timing or completion definition is unknown; these responses cannot be scored."),
      if(length(a$missing_reasons))shiny::tags$ul(lapply(a$missing_reasons,shiny::tags$li)),
      brohn_table(a$trial_audit,columns=c("trial_id","source_row","derived","profile_scored","disposition","declared_latency_ms","scoring_latency_ms","missing_reason"),
        maximum=100L,label=paste("Trial support for",a$id)))),
    if(length(analysis$task_attempts)>40L)shiny::p(paste("Showing 40 of",length(analysis$task_attempts),"administrations. JSON + provenance contains every complete source and trial audit.")))
}
brohn_task_import_mapping_input <- function(input) {
  fields <- c("task_id","source_collection_id","origin_statement","source_software","source_rt_definition","terminal_response_rule",.brohn_task_import_columns())
  result <- setNames(lapply(fields,function(f) input[[paste0("map_task_",f)]]),fields)
  if (identical(result$source_software,"")) result["source_software"] <- list(NULL)
  result$evidence_level <- "declared_trial_summary"
  for (f in c("task_column","origin_column")) if(brohn_text(input[[paste0("map_task_",f)]],500))result[[f]] <- input[[paste0("map_task_",f)]]
  result
}
brohn_task_import_study <- function(store,dataset,input) {
  brohn_require(!is.null(dataset) && identical(dataset$body$modality,"implicit") &&
    identical(input$dataset_form_identity,paste(dataset$id,dataset$revision,sep=":")), "Reopen the current task dataset before linking its original design.")
  brohn_require(brohn_valid_id(input$map_study) && brohn_text(input$map_study_revision,32), "Choose the original study and wait for its saved version.")
  revision <- if(identical(input$map_study_revision,"current")) NULL else suppressWarnings(as.numeric(input$map_study_revision))
  brohn_require(is.null(revision)||brohn_number(revision,1,.Machine$integer.max,TRUE), "Choose an available saved study version.")
  study <- brohn_study(store,input$map_study,revision)
  brohn_require(identical(study$project_id,dataset$project_id) && length(study$body$blocks)>0L, "Choose an original task study in this dataset's project.")
  study
}
brohn_install_task_import_ui <- function(input,output,session,store,state,attempt,message) {
  attached <- shiny::reactiveVal(NULL)
  selection <- function(bound=TRUE) {
    brohn_require(identical(state$page,"dataset"), "Open the original task dataset before changing this mapping.")
    dataset <- brohn_get_entity(store,"dataset",state$dataset_id)
    study <- brohn_task_import_study(store,dataset,input)
    task <- .brohn_task_import_task(study$body,input$map_task_task_id)
    identity <- brohn_hash(list(dataset_id=dataset$id,dataset_revision=dataset$revision,study_id=study$id,
      study_revision=study$revision,study_hash=brohn_hash(study$body),task_id=task$id,task_hash=brohn_hash(task)))
    if(bound)brohn_require(identical(input$task_registry_identity,identity), "The selected task or study version changed. Wait for its protocol panel before continuing.")
    list(dataset=dataset,study=study,task=task,identity=identity)
  }
  registry <- function(selected) {
    candidate <- attached()
    if(!is.null(candidate)&&identical(candidate$identity,selected$identity))return(candidate$reference)
    d <- selected$dataset$body
    if(identical(d$study_id,selected$study$id) && identical(as.numeric(d$study_revision),as.numeric(selected$study$revision)) &&
      identical(d$metadata$task_id,selected$task$id) && identical(d$metadata$protocol_registry$task_definition_hash,brohn_hash(selected$task))) d$metadata$protocol_registry else NULL
  }
  output$task_mapping_task <- shiny::renderUI({
    shiny::req(state$page=="dataset",state$dataset_id)
    tryCatch({
      dataset <- brohn_get_entity(store,"dataset",state$dataset_id); shiny::req(identical(dataset$body$modality,"implicit"))
      study <- brohn_task_import_study(store,dataset,input); tasks <- study$body$blocks
      prior <- dataset$body$metadata$task_id
      selected <- if(!is.null(prior)&&prior %in% brohn_ids(tasks))prior else if(length(tasks)==1L)tasks[[1]]$id else ""
      shiny::tagList(shiny::selectInput("map_task_task_id","Task used for these responses",c("Choose a task"="",stats::setNames(brohn_ids(tasks),vapply(tasks,`[[`,character(1),"title"))),selected),
        shiny::p(class="brohn-muted",paste("Using saved study revision",study$revision,"and its original task definition.")))
    },error=function(e)shiny::p(class="brohn-muted",conditionMessage(e)))
  })
  output$task_mapping_registry <- shiny::renderUI({
    shiny::req(state$page=="dataset",state$dataset_id)
    tryCatch({
      selected <- selection(FALSE); reference <- registry(selected)
      shiny::tagList(shiny::div(hidden=NA,shiny::textInput("task_registry_identity",NULL,selected$identity)),
        if(!is.null(reference))shiny::p(role="status",paste("Original protocol file ready:",reference$filename)) else
          shiny::p("Attach the original Brohn task protocol registry. It fixes each trial's order, keys, timing rules and scoring membership."),
        shiny::fileInput("task_registry_upload","Original task protocol registry JSON",accept=".json"),
        shiny::actionButton("attach_task_registry","Use this protocol file"),
        if(!is.null(reference))shiny::tags$details(shiny::tags$summary("Protocol file identity"),shiny::p(reference$hash)))
    },error=function(e)shiny::p(class="brohn-muted",conditionMessage(e)))
  })
  shiny::observeEvent(input$attach_task_registry,attempt(function() {
    selected <- selection(); file <- input$task_registry_upload
    brohn_require(is.data.frame(file)&&nrow(file)==1L, "Choose one completed protocol JSON upload.")
    reference <- brohn_stage_task_registry(store,file$datapath[[1L]],file$name[[1L]],selected$dataset$id,selected$dataset$revision,
      selected$study$id,selected$study$revision,selected$task$id)
    attached(list(identity=selected$identity,reference=reference)); message("Original task protocol checked and retained. Confirm the source definitions and mapping to analyse.")
  }))
  mapping <- function() {
    selected <- selection(); m <- brohn_task_import_mapping_input(input); m$protocol_registry <- registry(selected)
    d <- selected$dataset$body; d$metadata <- m; d$study_id <- selected$study$id; d$study_revision <- selected$study$revision
    brohn_validate_task_import_mapping(d,selected$study$body)
    list(metadata=m,study=selected$study,dataset=selected$dataset)
  }
  invisible(list(selection=selection,mapping=mapping,registry=registry))
}
brohn_task_import_dataset_ui <- function(store,record) {
  d <- record$body; m <- d$metadata; columns <- unlist(d$columns,use.names=FALSE)
  column <- function(field,label,candidate)shiny::selectInput(paste0("map_task_",field),label,c("Choose a column"="",stats::setNames(columns,columns)),
    brohn_default(m[[field]],if(candidate %in% columns)candidate else ""))
  brohn_page(d$title,paste("Implicit / reaction-time trials",d$source$filename,"revision",record$revision,sep=" \u00b7 "),
    brohn_card(title="Your original trial source is retained",brohn_badge(d$origin),brohn_badge(d$status),
      shiny::downloadButton("dataset_original_download","Download original source",icon=NULL),
      shiny::tags$details(shiny::tags$summary("Inspect original source columns"),brohn_table(d$preview,maximum=20)),
      shiny::p(class="brohn-muted",paste("SHA-256",d$source$hash))),
    brohn_card(title="Link the original task",subtitle="One exact procedure, original trial order and explicit response definitions.",
      shiny::div(hidden=NA,shiny::textInput("dataset_form_identity",NULL,paste(record$id,record$revision,sep=":"))),
      shiny::selectizeInput("map_study","Link to a study design",choices=NULL,options=list(placeholder="Search studies in this project",maxOptions=100)),
      shiny::uiOutput("mapping_study_revision"),shiny::uiOutput("task_mapping_task"),shiny::uiOutput("task_mapping_registry"),
      shiny::textInput("map_task_source_collection_id","Original collection ID or namespace",brohn_default(m$source_collection_id,"")),
      shiny::textAreaInput("map_task_origin_statement","Recording provenance and collection notes",brohn_default(m$origin_statement,""),rows=3),
      shiny::textInput("map_task_source_software","Original collection software and version (leave empty if unknown)",brohn_default(m$source_software,"")),
      shiny::selectInput("map_task_source_rt_definition","What do the response-time columns measure?",c("Unknown; retain evidence without a score"="unknown",
        "First and final-correct milliseconds from target onset"="first_and_final_correct_ms_from_target_onset"),brohn_default(m$source_rt_definition,"unknown")),
      shiny::selectInput("map_task_terminal_response_rule","When did each trial end?",c("Unknown; retain evidence without a score"="unknown",
        "First response or fixed deadline (RT / keyboard approach-avoidance)"="first_response_or_fixed_deadline",
        "Final correct response or fixed deadline (IAT / Brief IAT)"="corrected_response_or_fixed_deadline"),brohn_default(m$terminal_response_rule,"unknown")),
      shiny::tags$details(shiny::tags$summary("Response and timing columns"),shiny::div(class="brohn-form-grid",
        column("outcome_column","Trial outcome","outcome"),column("first_code_column","First accepted response key","first_code"),
        column("final_code_column","Final correct response key","final_code"),column("first_correct_column","First response was correct (true/false)","first_correct"),
        column("first_response_ms_column","First-response milliseconds","first_response_ms"),column("final_correct_ms_column","Final-correct milliseconds","final_correct_ms"),
        column("presented_column","Trial was presented (true/false)","presented"),column("missing_reason_column","Missing or interrupted response reason","missing_reason"))),
      shiny::tags$details(shiny::tags$summary("Participant and original trial identities"),shiny::div(class="brohn-form-grid",
        column("participant_column","Participant code","participant_id"),column("participant_linkage_column","Codes link repeated sessions (true/false)","participant_linkage"),
        column("session_column","Session ID","session_id"),column("attempt_column","Task administration ID","attempt_id"),
        column("protocol_column","Original protocol registry entry ID","protocol_id"),column("presentation_index_column","Original trial presentation ordinal","presentation_index"),
        column("trial_column","Frozen trial ID","trial_id"))),
      shiny::tags$details(shiny::tags$summary("Files containing several tasks"),shiny::p("An explicit task column selects this task. Every excluded row is retained. Selected row origins must agree with the saved dataset origin."),
        column("task_column","Task ID column (optional)","task_id"),column("origin_column","Collection origin column (optional)","origin")),
      shiny::p(class="brohn-muted","Supports 20,000 source rows and expected trial positions. Imported summaries retain their declared timing; they do not acquire a replayed browser journal or physical timing qualification."),
      shiny::actionButton("accept_dataset","Confirm mapping and analyse",class="btn-primary"),
      if(d$status %in% c("accepted","analysed"))shiny::actionButton("analyse_dataset","Run a new analysis")),shiny::uiOutput("dataset_reports"))
}
