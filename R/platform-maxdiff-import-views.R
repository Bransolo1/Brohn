# Exact study and column selection for original best-worst response files.
brohn_maxdiff_mapping_input <- function(input) {
  fields<-c("exercise_id","origin_statement",.brohn_maxdiff_import_columns(),"exercise_column","origin_column")
  ids<-stats::setNames(paste0("map_md_",fields),fields)
  ids[["origin_statement"]]<-"map_origin"
  values<-lapply(ids,function(id)input[[id]])
  Filter(function(value)!is.null(value) && !(is.character(value)&&length(value)==1L&&identical(value,"")),values)
}
brohn_maxdiff_mapping_study <- function(store,dataset,input) {
  brohn_require(!is.null(dataset) && identical(dataset$body$modality,"maxdiff") &&
    identical(input$dataset_form_identity,paste(dataset$id,dataset$revision,sep=":")),"Reopen the current best-worst dataset before linking its design.")
  brohn_require(brohn_valid_id(input$map_study),"Choose the original study containing this best-worst exercise.")
  revision<-input$map_study_revision
  brohn_require(brohn_text(revision,32),"Wait for the selected study version before choosing an exercise.")
  if (identical(revision,"current")) revision<-NULL else {
    revision<-suppressWarnings(as.numeric(revision))
    brohn_require(brohn_number(revision,1,.Machine$integer.max,TRUE),"Choose an available saved study revision.")
  }
  study<-brohn_study(store,input$map_study,revision)
  brohn_require(identical(study$project_id,dataset$project_id),"The selected study belongs to another project.")
  brohn_require(length(study$body$maxdiff)>0L,"This study version has no best-worst exercises. Choose the original design used for these responses.")
  study
}
brohn_maxdiff_mapping_identity <- function(dataset,study) paste(dataset$id,dataset$revision,study$id,study$revision,brohn_hash(study$body),sep=":")
brohn_install_maxdiff_import_ui <- function(input,output,session,store,state) {
  output$maxdiff_mapping_exercise<-shiny::renderUI({
    shiny::req(state$page=="dataset",state$dataset_id)
    dataset<-brohn_get_entity(store,"dataset",state$dataset_id)
    shiny::req(!is.null(dataset),identical(dataset$body$modality,"maxdiff"))
    tryCatch({
      study<-brohn_maxdiff_mapping_study(store,dataset,input)
      exercises<-study$body$maxdiff
      previous<-if(identical(dataset$body$study_id,study$id) && identical(as.numeric(dataset$body$study_revision),as.numeric(study$revision))) dataset$body$metadata$exercise_id else NULL
      selected<-if(!is.null(previous)&&previous %in% brohn_ids(exercises)) previous else if(length(exercises)==1L)exercises[[1]]$id else ""
      shiny::tagList(shiny::div(style="display:none",shiny::textInput("maxdiff_mapping_design_identity",NULL,brohn_maxdiff_mapping_identity(dataset,study))),
        shiny::selectInput("map_md_exercise_id","Exercise used for these responses",c("Choose an exercise"="",stats::setNames(brohn_ids(exercises),vapply(exercises,`[[`,character(1),"title"))),selected),
        shiny::p(class="brohn-muted",paste("Analysis will use saved revision",study$revision,"and its exact item IDs, offered sets and question wording.")))
    },error=function(e)shiny::p(class="brohn-muted",conditionMessage(e)))
  })
}
brohn_maxdiff_dataset_ui <- function(store,record) {
  d<-record$body;m<-d$metadata;columns<-unlist(d$columns,use.names=FALSE)
  column<-function(field,label,candidate) {
    selected<-brohn_default(m[[field]],if(candidate %in% columns)candidate else "")
    shiny::selectInput(paste0("map_md_",field),label,c("Choose a column"="",stats::setNames(columns,columns)),selected)
  }
  brohn_page(d$title,paste("Best-worst choices (MaxDiff)",d$source$filename,"revision",record$revision,sep=" \u00b7 "),
    brohn_card(title="Your original responses are retained",shiny::p(d$source_provenance$imported_at),
      shiny::p(class="brohn-muted",paste("SHA-256",d$source$hash)),brohn_badge(d$status),brohn_badge(d$origin),
      shiny::downloadButton("dataset_original_download","Download original source",icon=NULL),
      if(length(d$preview))shiny::tags$details(shiny::tags$summary("Inspect source columns"),brohn_table(d$preview,maximum=20))),
    brohn_card(title="Link the original exercise",subtitle="Choose its saved study version, then confirm the source columns. Brohn suggests matching names from its own exports.",
      shiny::div(style="display:none",shiny::textInput("dataset_form_identity",NULL,paste(record$id,record$revision,sep=":"))),
      shiny::selectizeInput("map_study","Link to a study design",choices=NULL,options=list(placeholder="Search studies in this project",maxOptions=100)),
      shiny::uiOutput("mapping_study_revision"),shiny::uiOutput("maxdiff_mapping_exercise"),
      shiny::div(class="brohn-form-grid",
        column("best_column","Best choice item ID","best_id"),column("worst_column","Worst choice item ID","worst_id"),
        column("status_column","Response status (answered, missing or not_presented)","status"),column("missing_reason_column","Reason for an omitted response","missing_reason")),
      shiny::tags$details(shiny::tags$summary("Participant, session and offered-set evidence"),
        shiny::p("Each row must preserve the offered item order as a JSON array. Missing and unpresented rows stay in the report; they do not enter complete-pair scores."),
        shiny::div(class="brohn-form-grid",
          column("participant_column","Participant code","participant_id"),column("session_column","Session ID","session_id"),
          column("exposure_column","Set presentation ID","exposure_id"),column("participant_linkage_column","Participant codes link repeated sessions (true/false)","participant_linkage"),
          column("design_hash_column","Exact exercise design hash","design_hash"),column("set_column","Offered set ID","set_id"),
          column("item_order_column","Offered item order (JSON array)","item_order"),column("presented_column","Set was presented (true/false)","presented"))),
      shiny::tags$details(shiny::tags$summary("Files containing several exercises or origins"),
        shiny::p("An exercise column selects only the chosen exercise and retains every excluded row's identity and reason. An origin column must match this dataset's declared origin for all selected rows."),
        shiny::div(class="brohn-form-grid",column("exercise_column","Exercise ID column (optional)","exercise_id"),column("origin_column","Recording origin column (optional)","origin"))),
      shiny::textAreaInput("map_origin","Recording provenance and collection notes",brohn_default(m$origin_statement,""),width="100%",rows=3,
        placeholder="Original collection platform, participant code policy and study version used."),
      shiny::p(class="brohn-muted","Supports up to 20,000 source rows. This is explicit choice analysis; imported rows do not establish response-time or implicit scores."),
      shiny::actionButton("accept_dataset","Confirm mapping and analyse",class="btn-primary"),
      if(d$status %in% c("accepted","analysed"))shiny::actionButton("analyse_dataset","Run a new analysis")),
    shiny::uiOutput("dataset_reports"))
}
