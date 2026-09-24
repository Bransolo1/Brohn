brohn_run_protocol_ui <- function(snapshot, offset = 0L) {
  steps <- snapshot$protocol$timeline; total <- length(steps)
  offset <- max(0L, min(as.integer(offset), max(0L, (ceiling(total/40)-1L)*40L)))
  indices <- if (total) seq.int(offset+1L, min(total, offset+40L)) else integer()
  command <- function(label, next_offset) brohn_command(label, "run_protocol_page",
    list(run_id = snapshot$run$id, hash = snapshot$hash, offset = next_offset))
  shiny::tagList(
    shiny::div(style = "display:none", shiny::textInput("run_protocol_identity", NULL, paste(snapshot$run$id, snapshot$hash, sep = ":"))),
    shiny::p(paste("Participant:", snapshot$run$participant_alias, "\u00b7", "Origin:", snapshot$run$origin,
      "\u00b7", "Assignment:", snapshot$run$allocation_index)),
    shiny::p(paste("Session:", snapshot$run$completion_status, "\u00b7", "Transfer:", snapshot$run$transfer_status)),
    shiny::p("This is the sequence assigned when the session started. Conditional questions may be skipped; assignment alone does not establish what was viewed or completed."),
    shiny::p("The download includes the full saved design and assigned sequence, with references to the study's media files."),
    shiny::tags$details(shiny::tags$summary("Saved protocol identity"), shiny::p(paste("Session:", snapshot$run$id)),
      shiny::p(paste("Protocol SHA-256:", snapshot$hash)), shiny::p(paste("Design SHA-256:", snapshot$protocol$design_hash))),
    if (identical(snapshot$run$completion_status,"completed") && identical(snapshot$run$transfer_status,"saved") &&
        any(vapply(steps,function(s)identical(s$type,"task"),logical(1)))) {
      tasks <- Filter(function(s)identical(s$type,"task"),steps)
      values <- vapply(tasks,function(s)brohn_json(list(run_id=snapshot$run$id,protocol_hash=snapshot$hash,task_id=s$task$id)),character(1))
      shiny::tags$details(shiny::tags$summary("Export original task trials"),
        shiny::selectInput("run_task_selection","Completed task to export",stats::setNames(values,vapply(tasks,function(s)s$task$title,character(1)))),
        shiny::p("Use the registry and machine trial CSV together for software import. Export notes retain the original collection identity, timing definitions and source hashes."),
        shiny::div(class="brohn-toolbar",shiny::downloadButton("run_task_registry","Download task registry JSON",icon=NULL),
          shiny::downloadButton("run_task_trials","Download task trials CSV",icon=NULL),
          shiny::downloadButton("run_task_notes","Download task export notes JSON",icon=NULL)))
    },
    shiny::p(paste("Showing assigned steps", if (total) offset+1L else 0L, "to", min(total, offset+40L), "of", total)),
    shiny::div(class = "brohn-table", tabindex = "0", role = "region", `aria-label` = "Assigned participant steps",
      shiny::tags$table(shiny::tags$thead(shiny::tags$tr(lapply(c("Step", "Type", "Content", "Assigned answer options"), function(label) shiny::tags$th(scope = "col", label)))),
        shiny::tags$tbody(lapply(indices, function(i) {
          step <- steps[[i]]
          title <- if (identical(step$type, "question")) step$question$prompt else if (identical(step$type, "stimulus")) step$stimulus$title else
            if (identical(step$type, "instructions")) step$text else if (identical(step$type, "task")) step$task$title else brohn_default(step$phase, step$type)
          shiny::tags$tr(shiny::tags$td(step$id), shiny::tags$td(gsub("_", " ", step$type, fixed = TRUE)),
            shiny::tags$td(if (!is.null(step[["questionnaire"]])) shiny::p(class = "brohn-muted", paste(step[["questionnaire"]]$section_label, "\u00b7", step[["questionnaire"]]$group_label)), title),
            shiny::tags$td(if (identical(step$type, "question") && length(step$question$options))
              shiny::tags$ol(lapply(step$question$options, function(option) shiny::tags$li(option$label, " (code: ", shiny::tags$code(brohn_json(option$value)), ")"))) else "\u2014"))
        })))),
    shiny::div(class = "brohn-toolbar", if (offset > 0L) command("Previous assigned steps", offset-40L),
      if (offset+40L < total) command("Next assigned steps", offset+40L)))
}
brohn_install_run_protocol_ui <- function(input, output, session, store, current, state, attempt, prepare_download, open_runtime = NULL) {
  review <- new.env(parent = emptyenv()); review$selection <- NULL; review$offset <- 0L
  selected <- function(require_bound = TRUE) {
    selection <- review$selection
    brohn_require(!is.null(selection) && identical(state$page, "study") && !is.null(current$study) &&
      state$stage %in% c("Collect", "Review") && identical(current$study$id, selection$study_id), "Open the session's assigned protocol before downloading it.")
    if (require_bound) brohn_require(identical(input$run_protocol_identity, paste(selection$run_id, selection$hash, sep = ":")), "The selected protocol changed. Reopen the session before downloading it.")
    snapshot <- brohn_run_protocol(store, selection$run_id, selection$study_id, current$study$project_id)
    brohn_require(identical(snapshot$hash, selection$hash), "The stored assigned protocol changed unexpectedly.")
    snapshot
  }
  show <- function(snapshot) shiny::showModal(shiny::modalDialog(title = "Assigned participant protocol", size = "l", easyClose = FALSE,
    brohn_run_protocol_ui(snapshot, review$offset),
    if(is.function(open_runtime))shiny::tags$details(shiny::tags$summary("Participant code"),
      shiny::p("Inspect the separate record of application code assigned to this session."),
      shiny::actionButton("run_protocol_code","Review assigned participant code")),
    brohn_participant_equipment_evidence_ui(brohn_equipment_evidence(store, snapshot$run$id)), footer = shiny::tagList(
      shiny::downloadButton("run_protocol_download", "Download assigned protocol JSON", icon = NULL),
      shiny::actionButton("close_run_protocol", "Close protocol"))))
  shiny::observeEvent(input$view_run_protocol, attempt(function() {
    command <- input$view_run_protocol
    brohn_fields(command, c("run_id", "study_id"), label = "Participant protocol selection")
    brohn_require(identical(state$page, "study") && state$stage %in% c("Collect", "Review") &&
      !is.null(current$study) && identical(command$study_id, current$study$id), "Select a session in the currently open study.")
    snapshot <- brohn_run_protocol(store, command$run_id, current$study$id, current$study$project_id)
    review$selection <- list(run_id = command$run_id, study_id = current$study$id, hash = snapshot$hash)
    review$offset <- 0L; show(snapshot)
  }))
  shiny::observeEvent(input$run_protocol_page, attempt(function() {
    snapshot <- selected(); command <- input$run_protocol_page
    brohn_fields(command, c("run_id", "hash", "offset"), label = "Assigned protocol page")
    brohn_require(identical(command$run_id, snapshot$run$id) && identical(command$hash, snapshot$hash) &&
      brohn_number(command$offset, 0, 20000, TRUE) && command$offset %% 40 == 0, "Choose a current assigned protocol page.")
    review$offset <- as.integer(command$offset); show(snapshot)
  }))
  shiny::observeEvent(input$close_run_protocol, {review$selection <- NULL; shiny::removeModal()})
  shiny::observeEvent(input$run_protocol_code, attempt(function() {
    snapshot<-selected();brohn_require(is.function(open_runtime),"Participant-code review is unavailable.")
    open_runtime(list(kind="run",id=snapshot$run$id,study_id=snapshot$run$study_id),return_view=function()show(selected(FALSE)))
  }))
  output$run_protocol_download <- shiny::downloadHandler(filename = function() paste0(selected()$run$id, "-assigned-protocol.json"),
    contentType = "application/json", content = function(file) prepare_download(function() brohn_export_run_protocol(selected(), file)))
  output$run_equipment_download <- shiny::downloadHandler(filename = function() paste0(selected()$run$id, "-equipment-evidence.json"),
    contentType = "application/json", content = function(file) prepare_download(function() brohn_write_json_file(brohn_equipment_evidence(store, selected()$run$id), file)))
  task_evidence <- function() {
    snapshot <- selected()
    brohn_require(brohn_text(input$run_task_selection,2000), "Choose a completed task from this assigned protocol.")
    choice <- brohn_parse(input$run_task_selection,2000)
    brohn_fields(choice,c("run_id","protocol_hash","task_id"),label="Task export selection")
    brohn_require(identical(choice$run_id,snapshot$run$id)&&identical(choice$protocol_hash,snapshot$hash), "The task export selection belongs to a different session.")
    brohn_task_run_evidence(store,snapshot$run$id,current$study$id,current$study$project_id,choice$task_id)
  }
  output$run_task_registry <- shiny::downloadHandler(filename=function()paste0(selected()$run$id,"-task-registry.json"),contentType="application/json",
    content=function(file)prepare_download(function()brohn_export_task_registry(task_evidence(),file)))
  output$run_task_trials <- shiny::downloadHandler(filename=function()paste0(selected()$run$id,"-task-trials.csv"),contentType="text/csv",
    content=function(file)prepare_download(function()brohn_export_task_trial_csv(task_evidence(),file)))
  output$run_task_notes <- shiny::downloadHandler(filename=function()paste0(selected()$run$id,"-task-export-notes.json"),contentType="application/json",
    content=function(file)prepare_download(function(){e<-task_evidence();e$registry<-NULL;e$rows<-NULL;brohn_write_json_file(e,file)}))
  invisible(list(selected = selected))
}
