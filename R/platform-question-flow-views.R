brohn_question_logic_summary_ui <- function(design, question) {
  shiny::tags$details(shiny::tags$summary("Display logic"),
    shiny::p(brohn_flow_summary(question$show_if,design$questions)),
    brohn_command("Edit display logic","question_flow_open",question$id))
}

brohn_flow_tree_ui <- function(rule, questions, editor_id, version, selected = integer(), path = integer(), siblings = 1L) {
  if (is.null(rule)) return(shiny::p("Always show this question. Add an answer condition to start a rule."))
  command <- function(label,event,extra=list()) brohn_command(label,event,c(list(editor_id=editor_id,version=version,path=as.list(path)),extra))
  label <- switch(rule$op,and="All conditions",or="Any condition",not="Not",brohn_flow_summary(rule,questions,180L))
  children <- brohn_flow_children(rule)
  shiny::tags$li(shiny::div(class="brohn-toolbar",shiny::tags$button(type="button",class=if(identical(as.integer(selected),as.integer(path))) "btn btn-primary" else "btn btn-outline-secondary",
    `data-brohn-event`="flow_select",`data-brohn-value`=brohn_json(list(editor_id=editor_id,version=version,path=as.list(path))),
    `aria-controls`="question_flow_node",label),
    if(length(path) && tail(path,1L)>1L) command("Move up","flow_move",list(direction=-1L)),
    if(length(path) && tail(path,1L)<siblings) command("Move down","flow_move",list(direction=1L)),
    command("Remove","flow_remove")),
    if(length(children)) shiny::tags$ol(lapply(seq_along(children),function(i) brohn_flow_tree_ui(children[[i]],questions,editor_id,version,selected,c(path,i),length(children)))))
}

brohn_flow_leaf_fields_ui <- function(question, node) {
  operators <- brohn_flow_operators(question)
  if (!is.null(node$op) && !node$op %in% c("and","or","not") && identical(node$question_id,question$id) && !node$op %in% unname(operators))
    operators <- c(operators,stats::setNames(node$op,paste("Saved operation:",node$op,"(review answer type)")))
  operation <- if(!is.null(node$op) && node$op %in% unname(operators)) node$op else "answered"
  numeric <- is.numeric(node$value); boolean <- is.logical(node$value); textual <- is.character(node$value)
  value_type <- if(boolean) "boolean" else if(textual) "text" else "number"
  options <- if(question$type %in% c("rating","single_choice","dropdown","multiple_choice","matrix","ranking")) question$options else list()
  selected_option <- if(length(options)) which(vapply(options,function(o) identical(brohn_json(brohn_flow_option_value(question,o)),brohn_json(node$value)),logical(1))) else integer()
  source <- if(length(selected_option) || (length(options) && is.null(node$value))) "option" else "typed"
  shiny::tagList(shiny::selectInput("flow_leaf_op","Comparison",operators,operation),
    if(question$type == "information") shiny::p("An information screen has no participant answer. Choose an earlier response question for an answer condition."),
    shiny::conditionalPanel("input.flow_leaf_op !== 'answered'",
      shiny::selectInput("flow_value_source","Compare using",c(if(length(options)) c("An answer option"="option"),"An exact typed value"="typed"),source),
      if(length(options)) shiny::conditionalPanel("input.flow_value_source === 'option'",shiny::selectInput("flow_option","Answer option",
        stats::setNames(brohn_ids(options),vapply(options,function(o) paste(substr(o$label,1,180),"|",brohn_flow_value_label(brohn_flow_option_value(question,o))),character(1))),
        if(length(selected_option)) options[[selected_option[[1L]]]]$id else options[[1L]]$id)),
      shiny::conditionalPanel("input.flow_value_source === 'typed'",
        shiny::selectInput("flow_value_type","Value type",c("Number"="number","Text (exact characters)"="text","Boolean"="boolean"),value_type),
        shiny::conditionalPanel("input.flow_value_type === 'number'",shiny::numericInput("flow_number","Numeric value",if(numeric) node$value else NA_real_)),
        shiny::conditionalPanel("input.flow_value_type === 'text'",shiny::textInput("flow_text","Exact text value",if(textual) node$value else "")),
        shiny::conditionalPanel("input.flow_value_type === 'boolean'",shiny::selectInput("flow_boolean","Boolean value",c("True"="true","False"="false"),if(boolean && !node$value) "false" else "true"))),
      shiny::conditionalPanel("input.flow_leaf_op === 'greater' || input.flow_leaf_op === 'less'",shiny::p("Ordered comparisons require a numeric answer and a numeric threshold."))))
}

brohn_install_question_flow_server <- function(input, output, session, current, state, capture, update_study, attempt, message) {
  flow <- shiny::reactiveValues(active=FALSE,draft=NULL,path=integer(),version=0L,editor_id=NULL,question_id=NULL,study_id=NULL,base_hash=NULL,earlier=list())
  usable <- function() Filter(function(q) q$type!="information",flow$earlier)
  node_identity <- function() paste(flow$editor_id,paste(flow$path,collapse="."),brohn_hash(brohn_flow_get(flow$draft,flow$path)),sep=":")
  guard <- function(command=NULL) {
    brohn_require(isTRUE(flow$active) && !is.null(current$study) && identical(current$study$id,flow$study_id),"Reopen display logic for the current study.")
    brohn_require(!isTRUE(current$study$body$archived),"Restore the study before editing display logic.")
    if(!is.null(command)) brohn_require(is.list(command) && identical(command$editor_id,flow$editor_id) &&
      identical(as.numeric(command$version),as.numeric(flow$version)),"The rule draft changed. Select its current controls again.")
  }
  set_draft <- function(rule,path=flow$path) {
    brohn_validate_rule(rule,brohn_ids(flow$earlier)); brohn_flow_nodes(rule)
    flow$draft <- rule; flow$path <- as.integer(unlist(path,use.names=FALSE)); flow$version <- flow$version+1L
  }
  condition_from_input <- function() {
    question <- brohn_find(flow$earlier,input$flow_question)
    brohn_require(!is.null(question) && question$type!="information","Choose an earlier response question available at this placement.")
    value <- switch(input$flow_value_type,number=input$flow_number,text=input$flow_text,boolean=input$flow_boolean,NULL)
    brohn_flow_condition(question,input$flow_leaf_op,brohn_default(input$flow_value_source,"typed"),input$flow_option,input$flow_value_type,value,
      existing=brohn_flow_get(flow$draft,flow$path))
  }
  apply_form <- function(required=TRUE) {
    if(is.null(flow$draft)) return(invisible(NULL))
    valid <- identical(input$flow_node_identity,node_identity())
    if(!required && !valid) return(invisible(NULL))
    brohn_require(valid,"The selected rule changed. Select it again before applying its fields.")
    node <- brohn_flow_get(flow$draft,flow$path); kind <- input$flow_kind
    condition <- if(identical(kind,"condition")) condition_from_input() else NULL
    replacement <- brohn_flow_kind(node,kind,condition)
    if(!identical(brohn_hash(node),brohn_hash(replacement))) set_draft(brohn_flow_replace(flow$draft,flow$path,replacement))
    invisible(NULL)
  }
  shiny::observeEvent(input$question_flow_open,attempt(function() {
    capture(); brohn_require(!is.null(current$study),"Choose a study first.")
    brohn_require(!isTRUE(current$study$body$archived),"Restore the study before editing display logic.")
    d <- current$study$body; q <- brohn_find(d$questions,input$question_flow_open)
    brohn_require(!is.null(q),"Choose a current question."); brohn_flow_nodes(q$show_if)
    flow$active <- TRUE; flow$draft <- q$show_if; flow$path <- integer(); flow$version <- 0L
    flow$editor_id <- brohn_id("flow-editor"); flow$study_id <- d$id; flow$question_id <- q$id; flow$base_hash <- brohn_hash(d)
    flow$earlier <- brohn_flow_earlier(d,q$id)
    shiny::showModal(shiny::modalDialog(title=paste("Display logic:",substr(q$prompt,1,120)),size="l",
      shiny::p("Build the condition below. Saving keeps the rule with this study revision; participant releases retain their frozen version."),
      shiny::uiOutput("question_flow_tree"),shiny::uiOutput("question_flow_node"),
      footer=shiny::tagList(brohn_command("Cancel","cancel_question_flow",list(editor_id=flow$editor_id)),
        brohn_command("Save display logic","save_question_flow",list(editor_id=flow$editor_id),"btn btn-primary"))))
  }))
  shiny::observeEvent(input$flow_select,attempt(function() {
    command <- input$flow_select; guard(command); apply_form(FALSE)
    brohn_flow_get(flow$draft,command$path); flow$path <- as.integer(unlist(command$path,use.names=FALSE))
  }))
  shiny::observeEvent(input$flow_apply,attempt(function() {guard(); apply_form(); message("Condition updated in the draft.")}))
  shiny::observeEvent(input$flow_add,attempt(function() {
    guard(input$flow_add); apply_form(FALSE); earlier <- usable(); brohn_require(length(earlier)>0L,"No earlier response is available at this question's placement.")
    added <- list(op="answered",question_id=earlier[[1L]]$id)
    if(is.null(flow$draft)) set_draft(added,integer()) else {
      node <- brohn_flow_get(flow$draft,flow$path)
      if(node$op %in% c("and","or")) {node$rules[[length(node$rules)+1L]] <- added; next_path <- c(flow$path,length(node$rules))} else {
        node <- list(op="and",rules=list(node,added)); next_path <- c(flow$path,2L)
      }
      set_draft(brohn_flow_replace(flow$draft,flow$path,node),next_path)
    }
  }))
  shiny::observeEvent(input$flow_remove,attempt(function() {command <- input$flow_remove; guard(command); set_draft(brohn_flow_remove(flow$draft,command$path),integer())}))
  shiny::observeEvent(input$flow_move,attempt(function() {
    command <- input$flow_move; guard(command); apply_form(FALSE)
    path <- as.integer(unlist(command$path,use.names=FALSE)); moved <- path; moved[length(moved)] <- tail(path,1L)+command$direction
    set_draft(brohn_flow_move(flow$draft,path,command$direction),moved)
  }))
  shiny::observeEvent(input$flow_clear,attempt(function() {guard(input$flow_clear); set_draft(NULL,integer())}))
  shiny::observeEvent(input$cancel_question_flow,attempt(function() {
    guard(); brohn_require(is.list(input$cancel_question_flow) && identical(input$cancel_question_flow$editor_id,flow$editor_id),"Choose the current editor's Cancel button.")
    flow$active <- FALSE; shiny::removeModal(); message("Display-logic draft discarded.")
  }))
  shiny::observeEvent(input$save_question_flow,attempt(function() {
    guard(); brohn_require(is.list(input$save_question_flow) && identical(input$save_question_flow$editor_id,flow$editor_id),"Choose the current editor's Save button.")
    apply_form(FALSE); capture()
    brohn_require(identical(brohn_hash(current$study$body),flow$base_hash),"The study changed while this rule was open. Reopen display logic to apply it to the latest questions.")
    design <- brohn_flow_set_question(current$study$body,flow$question_id,flow$draft)
    update_study(design); flow$active <- FALSE; shiny::removeModal(); message("Display logic saved with exact typed answer codes.")
  }))
  output$question_flow_tree <- shiny::renderUI({
    shiny::req(flow$active)
    command <- list(editor_id=flow$editor_id,version=flow$version)
    shiny::tagList(shiny::div(class="brohn-alert brohn-alert-info",role="status",brohn_flow_summary(flow$draft,current$study$body$questions,2500L)),
      shiny::div(class="brohn-toolbar",if(length(usable())) brohn_command("Add condition","flow_add",command),
        if(!is.null(flow$draft)) brohn_command("Always show instead","flow_clear",command)),
      if(!length(usable())) shiny::p("There is no earlier answer available at this placement. The question can always be shown."),
      if(is.null(flow$draft)) brohn_flow_tree_ui(NULL,list(),flow$editor_id,flow$version) else
        shiny::div(class="brohn-table",role="region",tabindex="0",`aria-label`="Ordered display rule tree",
          shiny::tags$ol(brohn_flow_tree_ui(flow$draft,current$study$body$questions,flow$editor_id,flow$version,flow$path))))
  })
  output$question_flow_node <- shiny::renderUI({
    shiny::req(flow$active,!is.null(flow$draft)); node <- brohn_flow_get(flow$draft,flow$path)
    kind <- if(node$op %in% c("and","or","not")) node$op else "condition"
    choices <- usable(); if(!length(choices)) choices <- flow$earlier
    selected <- if(!is.null(node$question_id)) node$question_id else if(length(choices)) choices[[1L]]$id else ""
    shiny::div(class="brohn-card",shiny::h3("Selected rule"),
      shiny::div(style="display:none",shiny::textInput("flow_node_identity",NULL,node_identity())),
      shiny::selectInput("flow_kind","Rule type",c("An answer condition"="condition","All conditions (AND)"="and","Any condition (OR)"="or","Not this rule"="not"),kind),
      shiny::conditionalPanel("input.flow_kind === 'condition'",
        if(kind!="condition") shiny::p("Replacing this group with one condition removes its children from the draft."),
        shiny::selectInput("flow_question","Earlier response question",stats::setNames(brohn_ids(choices),vapply(choices,function(q)
          paste0("Q",match(q$id,brohn_ids(current$study$body$questions)),". ",substr(q$prompt,1,180)," [",gsub("_"," ",q$scope),"]"),character(1))),selected),
        shiny::uiOutput("question_flow_leaf")),
      shiny::conditionalPanel("input.flow_kind === 'not'",shiny::p("Not reverses the entire nested rule, including its result when an answer is missing. Add a Has an answer condition when missing responses should stay excluded.")),
      shiny::conditionalPanel("input.flow_kind === 'and' || input.flow_kind === 'or'",shiny::p("All requires every child condition. Any requires at least one. Use Add condition to extend the selected group.")),
      shiny::actionButton("flow_apply","Apply to draft"))
  })
  output$question_flow_leaf <- shiny::renderUI({
    shiny::req(flow$active,!is.null(flow$draft)); node <- brohn_flow_get(flow$draft,flow$path)
    question <- brohn_find(flow$earlier,brohn_default(input$flow_question,node$question_id))
    shiny::req(!is.null(question)); brohn_flow_leaf_fields_ui(question,node)
  })
  invisible(list(draft=shiny::reactive(flow$draft),node_identity=shiny::reactive(node_identity()),
    context=shiny::reactive(list(editor_id=flow$editor_id,version=flow$version,path=as.list(flow$path),active=flow$active))))
}
