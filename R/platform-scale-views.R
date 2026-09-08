# Explicit Save/Cancel questionnaire scale editor, scoped to its frozen study.
brohn_scales_summary_ui <- function(design) {
  scales<-brohn_default(design$scales,list())
  brohn_card(title="Questionnaire scales",subtitle="Combine selected quantitative items using a saved scoring key.",
    shiny::p("Each scale is calculated separately for the opening questionnaire, each stimulus assessment, or the final questionnaire."),
    if(!length(scales)) shiny::p("No multi-item scale is configured.") else shiny::tags$ul(lapply(scales,function(s)
      shiny::tags$li(shiny::strong(s$label),paste0(" - ",length(s$items)," items; ",s$scope,"; version ",s$version," "),brohn_command("Edit scale","scale_edit",s$id)))),
    shiny::actionButton("scale_add","Add a scale"),
    if(length(scales)) shiny::tagList(shiny::p(class="brohn-muted","Saved scales protect their item bounds and placement. To change a keyed question, edit or remove its scale key first."),
      shiny::actionButton("scale_restore_questions","Discard unsaved question edits")))
}
brohn_scale_editor_current <- function(draft,current,state,input) {
  isTRUE(draft$active) && !is.null(current$study) && identical(current$study$id,draft$study_id) &&
    identical(as.numeric(current$study$revision),as.numeric(draft$revision)) && identical(brohn_hash(current$study$body),draft$design_hash) &&
    identical(state$page,"study") && identical(state$stage,"Questions") &&
    identical(input$study_form_identity,paste(draft$study_id,"Questions",sep=":")) &&
    identical(input$scale_form_identity,draft$token)
}
brohn_scale_picker_id <- function(scope) if(identical(scope,"end")) "scale_question_ids" else paste0("scale_question_ids_",scope)
brohn_scale_selection_ui <- function(design,scale,token) {
  # Each input is constructed once when the modal opens. Membership and scope
  # only change client-side visibility: an in-flight render cannot replace a
  # checkbox after the researcher has changed it. Hidden scope drafts survive
  # switching placement and removing/reselecting an item within this modal.
  choices<-list();keys<-list()
  for(scope in c("end","before","after_each")) {
    questions<-Filter(function(q) identical(q$scope,scope) && !inherits(try(brohn_scale_question_bounds(q),silent=TRUE),"try-error"),design$questions)
    ids<-brohn_ids(questions);selected<-intersect(vapply(scale$items,function(i) i$question_id,character(1)),ids)
    picker<-brohn_scale_picker_id(scope);scope_condition<-paste0("input.scale_scope === ",brohn_json(scope))
    choices[[length(choices)+1L]]<-shiny::conditionalPanel(scope_condition,
      shiny::selectInput(picker,"Items in this scale",stats::setNames(ids,vapply(questions,`[[`,character(1),"prompt")),selected=selected,multiple=TRUE),
      if(length(questions)<2) shiny::p("Add at least two quantitative questions at this placement first. Category, matrix and text answers are kept separately."))
    for(q in questions) {
      bounds<-brohn_scale_question_bounds(q);prior<-Filter(function(i) identical(i$question_id,q$id),scale$items)
      visible<-paste0(scope_condition," && [].concat(input.",picker," || []).indexOf(",brohn_json(q$id),") !== -1")
      keys[[length(keys)+1L]]<-shiny::conditionalPanel(visible,
        shiny::tags$fieldset(shiny::tags$legend(q$prompt),shiny::p(paste("Declared numeric response bounds:",bounds[1],"to",bounds[2])),
          shiny::checkboxInput(paste0("scale_reverse_",token,"_",q$id),"Reverse score this item",length(prior)>0 && isTRUE(prior[[1]]$reverse))))
    }
  }
  list(choices=shiny::div(id="scale_question_choices",choices),
    keys=shiny::div(id="scale_reverse_keys",keys,shiny::p("Reverse scoring uses lower bound + upper bound - the original answer. The raw answer is retained.")))
}
brohn_install_scale_ui <- function(input,output,session,current,state,attempt,capture,update_study) {
  draft<-shiny::reactiveValues(active=FALSE,study_id=NULL,revision=NULL,design_hash=NULL,token=NULL,scale=NULL,design=NULL)
  guard<-function() brohn_require(brohn_scale_editor_current(draft,current,state,input),"This scale editor belongs to an earlier study or revision. Cancel and reopen it before saving.")
  reverse_id<-function(qid) paste0("scale_reverse_",draft$token,"_",qid)
  open_editor<-function(id=NULL) {
    brohn_require(!is.null(current$study) && identical(state$page,"study") && identical(state$stage,"Questions") &&
      identical(input$study_form_identity,paste(current$study$id,"Questions",sep=":")),"Open scale scoring from this study's Questions page.")
    capture();design<-current$study$body
    brohn_require(!isTRUE(design$archived),"Restore this study before editing its scales.")
    scale<-if(is.null(id)) NULL else brohn_find(brohn_default(design$scales,list()),id)
    brohn_require(is.null(id)||!is.null(scale),"This scale no longer exists in the current study.")
    if(is.null(scale)) scale<-list(schema="brohn-questionnaire-scale/1.0",id=brohn_id("scale"),label="",version="1.0",source="",scope="end",items=list(),
      scoring=list(aggregation="mean",missing="complete",minimum_answered=2,prorate=FALSE),conversion=NULL)
    draft$active<-TRUE;draft$study_id<-design$id;draft$revision<-current$study$revision;draft$design_hash<-brohn_hash(design)
    draft$token<-brohn_id("scale-form");draft$scale<-scale;draft$design<-design
    selections<-brohn_scale_selection_ui(design,scale,draft$token)
    shiny::showModal(shiny::modalDialog(title=if(is.null(id)) "Add a questionnaire scale" else "Edit questionnaire scale",size="l",easyClose=FALSE,
      shiny::div(hidden=NA,shiny::textInput("scale_form_identity",NULL,draft$token)),
      shiny::textInput("scale_label","Scale name",scale$label),
      shiny::div(class="brohn-form-grid",shiny::textInput("scale_version","Scoring version",scale$version),
        shiny::selectInput("scale_scope","When is this assessment made?",c("Final questionnaire"="end","Before the study"="before","After each stimulus"="after_each"),scale$scope)),
      shiny::textAreaInput("scale_source","Scoring source and adaptation notes",scale$source,rows=3,width="100%",
        placeholder="Cite the scoring instructions or describe your original scale, its target context and any adaptations."),
      selections$choices,selections$keys,
      shiny::tags$details(open=NA,shiny::tags$summary("Scoring and missing answers"),
        shiny::selectInput("scale_aggregation","Combine keyed answers using",c("Mean"="mean","Sum"="sum"),scale$scoring$aggregation),
        shiny::selectInput("scale_missing","If an item is missing",c("Require every item"="complete","Use a declared minimum answered count"="minimum_answered"),scale$scoring$missing),
        shiny::conditionalPanel("input.scale_missing === 'minimum_answered'",
          shiny::numericInput("scale_minimum","Minimum answered items",scale$scoring$minimum_answered,min=1,max=100,step=1),
          shiny::p("Partial scores require the same lower and upper response bounds for every item. Invalid or duplicate answers make the assessment unscoreable."),
          shiny::conditionalPanel("input.scale_aggregation === 'sum'",shiny::checkboxInput("scale_prorate","Estimate a complete sum from the answered-item mean",isTRUE(scale$scoring$prorate))))),
      shiny::tags$details(shiny::tags$summary("Optional score conversion"),
        shiny::checkboxInput("scale_convert","Convert the theoretical score range to another bounded range",!is.null(scale$conversion)),
        shiny::conditionalPanel("input.scale_convert",shiny::div(class="brohn-form-grid",
          shiny::numericInput("scale_conversion_min","Converted minimum",brohn_default(scale$conversion$min,0),min=-1e9,max=1e9),
          shiny::numericInput("scale_conversion_max","Converted maximum",brohn_default(scale$conversion$max,100),min=-1e9,max=1e9))),
        shiny::p("Conversion is linear and does not create percentiles, clinical thresholds or evidence that a named scale was administered correctly.")),
      footer=shiny::tagList(if(!is.null(id)) shiny::actionButton("scale_delete","Remove scale"),
        shiny::actionButton("scale_cancel","Cancel"),shiny::actionButton("scale_save","Save scale",class="btn-primary"))))
  }
  shiny::observeEvent(input$scale_add,attempt(function() open_editor()))
  shiny::observeEvent(input$scale_edit,attempt(function() open_editor(input$scale_edit)))
  shiny::observeEvent(input$scale_restore_questions,attempt(function() {
    brohn_require(!is.null(current$study) && identical(state$page,"study") && identical(state$stage,"Questions") &&
      identical(input$study_form_identity,paste(current$study$id,"Questions",sep=":")),"Return to this study's Questions page before discarding unsaved edits.")
    # Deliberately bypass capture(): its pending form may violate a saved scale
    # key. Redraw the saved current design without changing any catalog revision.
    draft$active<-FALSE;state$error<-NULL;state$status<-"Saved questions restored. You can now edit the scale key."
    state$refresh<-state$refresh+1L
  }))
  make_scale<-function() {
    ids<-brohn_default(input[[brohn_scale_picker_id(input$scale_scope)]],character());s<-draft$scale
    s$label<-input$scale_label;s$version<-input$scale_version;s$source<-input$scale_source;s$scope<-input$scale_scope
    s$items<-lapply(ids,function(id) {
      q<-brohn_find(draft$design$questions,id);bounds<-brohn_scale_question_bounds(q)
      list(question_id=id,reverse=isTRUE(input[[reverse_id(id)]]),min=bounds[1],max=bounds[2])
    })
    s$scoring<-list(aggregation=input$scale_aggregation,missing=input$scale_missing,
      minimum_answered=if(input$scale_missing=="complete") length(ids) else input$scale_minimum,
      prorate=identical(input$scale_missing,"minimum_answered") && identical(input$scale_aggregation,"sum") && isTRUE(input$scale_prorate))
    s["conversion"]<-list(if(isTRUE(input$scale_convert)) list(min=input$scale_conversion_min,max=input$scale_conversion_max) else NULL)
    brohn_validate_scales(list(s),draft$design);s
  }
  close_editor<-function() {draft$active<-FALSE;shiny::removeModal()}
  shiny::observeEvent(input$scale_cancel,close_editor())
  shiny::observeEvent(input$scale_save,attempt(function() {
    guard();s<-make_scale();design<-current$study$body;scales<-brohn_default(design$scales,list())
    at<-match(s$id,brohn_ids(scales));if(is.na(at)) scales[[length(scales)+1L]]<-s else scales[[at]]<-s
    design$scales<-scales;brohn_validate_scales(scales,design);update_study(design);close_editor()
  }))
  shiny::observeEvent(input$scale_delete,attempt(function() {
    guard();design<-current$study$body;design$scales<-Filter(function(s) !identical(s$id,draft$scale$id),brohn_default(design$scales,list()))
    update_study(design);close_editor()
  }))
  invisible(TRUE)
}
brohn_scale_results_ui <- function(result) {
  if(is.null(result)) return(NULL)
  brohn_card(title="Questionnaire scale scores",subtitle="Saved keys applied to separate assessments with original item evidence retained.",
    brohn_table(result$features,maximum=32L,label="Scale scoring coverage"),
    shiny::p(paste(length(result$observations),"assessment scores are saved. This preview shows up to 30; download Scale scores CSV for every assessment or the full JSON for item evidence.")),
    brohn_table(lapply(result$observations,function(r) list(scale=r$label,participant=r$participant_id,session=r$session_id,
      assessment=r$assessment_id,stimulus=r$stimulus_id,status=r$status,score=r$value,answered=r$answered_items,total=r$total_items,
      prorated=r$prorated,reason=r$missing_reason)),maximum=30L,label="Assessment scale scores"),
    if(result$quality$unassigned_response_count>0) shiny::p(class="brohn-alert brohn-alert-warning",
      paste(result$quality$unassigned_response_count,"response rows could not be assigned to an explicit assessment. Review the saved import mapping; no score was inferred from row order.")),
    shiny::tags$details(shiny::tags$summary("Scoring evidence and interpretation"),
      shiny::p("The full saved report retains scale versions, item bounds, reverse keys, raw/keyed answers, missing reasons and source references. Repeated assessments are separate rows."),
      shiny::tags$ul(lapply(result$limitations,shiny::tags$li))))
}
