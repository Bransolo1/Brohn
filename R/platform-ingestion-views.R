# Pending imports remain visible independently of an unfinished dataset record.
brohn_ingestion_history <- function(store, project_id = "default", study_id = NULL, offset = 0L) {
  brohn_project(store, project_id)
  brohn_require(brohn_number(offset, 0, 1e8, TRUE), "Choose an import history page.")
  from <- paste("FROM entities e JOIN entity_versions v ON e.kind=v.kind AND e.id=v.id AND e.revision=v.revision",
    "WHERE e.kind='ingestion' AND e.project_id=?")
  parameters <- list(project_id)
  if (!is.null(study_id)) {
    brohn_require(identical(brohn_study(store, study_id)$project_id, project_id), "Choose a study in this project.")
    from <- paste(from, "AND json_extract(v.body_json,'$.review.study_id')=?"); parameters <- c(parameters, list(study_id))
  }
  read <- function() {
    total <- as.numeric(DBI::dbGetQuery(store$con, paste("SELECT count(*) AS n", from), params = parameters)$n[[1L]])
    actual <- if (total) min(offset, floor((total-1)/40)*40) else 0L
    rows <- DBI::dbGetQuery(store$con, paste("SELECT e.id", from, "ORDER BY e.updated_at DESC,e.id ASC LIMIT 40 OFFSET ?"), params = c(parameters, list(actual)))
    list(records = lapply(rows$id, function(id) brohn_ingestion(store, id)), total = total, offset = actual,
      has_previous = actual > 0, has_next = actual+nrow(rows) < total, project_id = project_id, study_id = study_id)
  }
  if (RSQLite::sqliteIsTransacting(store$con)) read() else DBI::dbWithTransaction(store$con, read())
}
brohn_ingestion_state_label <- function(status) switch(status, queued = "Waiting to preserve source",
  preserving_source = "Checking and preserving source", ready = "Source saved", cancelled = "Import cancelled",
  failed = "Import needs attention", needs_attention = "Review and upload again", gsub("_", " ", status))
brohn_ingestion_history_ui <- function(page) {
  if (!page$total) return(NULL)
  brohn_card(title = "Source import history",
    shiny::p(role = "status", paste("Showing", page$offset+1, "to", page$offset+length(page$records), "of", page$total, "imports")),
    lapply(page$records, function(r) shiny::div(class = "brohn-toolbar", shiny::strong(r$body$review$title),
      shiny::span(r$body$review$filename), brohn_badge(brohn_ingestion_state_label(r$body$effective_status)),
      brohn_command("Inspect import", "open_ingestion", r$id))),
    shiny::div(class = "brohn-toolbar",
      if (page$has_previous) brohn_command("Previous imports", "ingestion_page", list(offset = page$offset, direction = -1, study_id = page$study_id)),
      if (page$has_next) brohn_command("Next imports", "ingestion_page", list(offset = page$offset, direction = 1, study_id = page$study_id))))
}
brohn_ingestion_detail_ui <- function(store, record) {
  b <- record$body; status <- b$effective_status; review <- b$review
  ready <- identical(status, "ready")
  owner_alive <- .brohn_ingestion_owner_alive(b$source_snapshot$owner)
  brohn_card(title = brohn_ingestion_state_label(status),
    shiny::div(style = "display:none", shiny::textInput("ingestion_form_identity", NULL, paste(record$id, record$revision, sep = ":"))),
    shiny::p(role = "status", if (ready) "The complete original is saved. Confirm its columns and settings to start scientific analysis." else if (is.null(b$source_snapshot))
      "Source capture did not complete. Review the original local file and select it again; this attempt has no verified incoming source." else if (status == "preserving_source")
      "The worker is checking and preserving the original. It may complete under its own file guard even if the upload server has restarted. Wait for the recorded outcome before retrying." else if (!owner_alive)
      "Brohn restarted before this import completed. The incoming file is retained, but its original upload guard is no longer available. Review your original file and upload it again from Data. This attempt will not be silently resumed." else if (status == "cancelled")
      "This import was cancelled. Its incoming original remains preserved for an explicit retry while this Brohn server stays open." else if (status == "failed")
      "Source preparation stopped. Review the reason below before retrying the same original or uploading a corrected file." else
      "Brohn is checking the full original and preparing a small column preview in the background. You can continue using the workspace; analysis starts after you confirm the mapping."),
    shiny::p(paste("File:", review$filename, "\u00b7", format(round(review$size/1024^2, 2), trim = TRUE), "MiB")),
    shiny::p(paste("Data family:", review$modality, "\u00b7 Origin:", review$origin)),
    if (!is.null(review$study_id)) shiny::p(paste("Linked study:", brohn_study(store, review$study_id, review$study_revision)$body$title,
      "\u00b7 saved revision", review$study_revision)) else shiny::p("No study link. You can choose one when reviewing the saved source."),
    if (!is.null(b$job_error$message)) shiny::div(class = "brohn-alert", role = "note", shiny::p(b$job_error$message)),
    if (!is.null(b$error) && is.null(b$source_snapshot)) shiny::p(b$error),
    if (ready) shiny::tagList(shiny::p(class = "brohn-muted", paste("SHA-256", b$source_object$hash)),
      brohn_command("Review source mapping", "open_dataset", b$dataset_id, "btn btn-primary")),
    if (status %in% c("queued", "preserving_source")) brohn_command("Cancel source import", "cancel_ingestion", list(id = record$id, revision = record$revision)),
    if (status %in% c("failed", "cancelled") && owner_alive) brohn_command("Retry this original", "retry_ingestion", list(id = record$id, revision = record$revision)),
    shiny::tags$details(shiny::tags$summary("Import receipt and attempts"),
      shiny::p(paste("Import identity:", record$id)), shiny::p(paste("Saved", record$created_at)),
      shiny::p(paste(length(b$attempts), "processing attempts retained. Source preservation does not qualify its scientific measurements."))))
}
brohn_install_ingestion_ui <- function(input, output, session, store, state, current, attempt, refresh, message) {
  uploads <- new.env(parent = emptyenv()); state$ingestion_offset <- 0L
  context <- function() {
    study <- if (identical(state$page, "study") && !is.null(current$study)) brohn_study(store, current$study$id) else NULL
    list(project_id = if (is.null(study)) "default" else study$project_id, study_id = if (is.null(study)) NULL else study$id,
      study_revision = if (is.null(study)) NULL else study$revision)
  }
  visible <- function() identical(state$page, "datasets") || (identical(state$page, "study") && identical(state$stage, "Collect"))
  upload_revision <- shiny::reactiveVal(0L)
  review_fields <- function() list(title = input$dataset_title, modality = input$dataset_modality, origin = brohn_default(input$dataset_origin, "imported"))
  upload_identity <- function(receipt, destination) brohn_hash(list(reference = receipt$reference, destination = destination, review = review_fields()))
  # Transfer completion does not silently choose the current study or origin.
  # The subsequent displayed review identifies the exact upload and destination.
  shiny::observeEvent(input$dataset_upload, attempt(function() {
    upload <- input$dataset_upload; shiny::req(upload$datapath)
    key <- brohn_hash(list(path = upload$datapath, name = upload$name, size = upload$size))
    if (!exists(key, envir = uploads, inherits = FALSE)) assign(key, list(reference = brohn_id("upload"), operation = brohn_id("import"), file = upload), envir = uploads)
    uploads$selected <- key; upload_revision(upload_revision()+1L)
    message("File transfer complete. Review its destination and choose Import this file.")
  }))
  output$ingestion_upload_review <- shiny::renderUI({
    upload_revision(); state$refresh; shiny::req(visible(), uploads$selected)
    receipt <- get(uploads$selected, envir = uploads, inherits = FALSE); destination <- context()
    existing <- brohn_get_entity(store, "ingestion", paste0("ingestion-", substr(brohn_hash(list(project_id = destination$project_id, operation_id = receipt$operation)), 1, 32)))
    if (!is.null(existing)) return(shiny::tagList(shiny::p(paste("This transfer already created an import:", receipt$file$name)),
      brohn_command("Inspect source import", "open_ingestion", existing$id)))
    shiny::tagList(
      shiny::div(style = "display:none", shiny::textInput("ingestion_upload_review_identity", NULL, upload_identity(receipt, destination))),
      shiny::p(shiny::strong(paste("Ready to import:", receipt$file$name))),
      shiny::p(if (is.null(destination$study_id)) "Destination: Data library, with no study link yet." else paste("Destination:",
        brohn_study(store, destination$study_id, destination$study_revision)$body$title, "\u00b7 saved revision", destination$study_revision)),
      shiny::p(paste("Dataset:", brohn_default(input$dataset_title, ""), "\u00b7 Family:", brohn_default(input$dataset_modality, ""),
        "\u00b7 Origin:", brohn_default(input$dataset_origin, ""))),
      shiny::actionButton("start_source_import", "Import this file", class = "btn-primary"))
  })
  shiny::observeEvent(input$start_source_import, attempt(function() {
    brohn_require(visible() && !is.null(uploads$selected), "Open Data or your study's Collect stage and review a completed file transfer.")
    receipt <- get(uploads$selected, envir = uploads, inherits = FALSE); destination <- context(); upload <- receipt$file
    brohn_require(identical(input$ingestion_upload_review_identity, upload_identity(receipt, destination)),
      "The selected file or destination changed. Review the current upload details before importing.")
    record <- brohn_queue_ingestion(store, list(path = upload$datapath, name = basename(upload$name), size = upload$size, reference = receipt$reference),
      title = input$dataset_title, modality = input$dataset_modality, origin = brohn_default(input$dataset_origin, "imported"),
      study_id = destination$study_id, project_id = destination$project_id, operation_id = receipt$operation)
    state$ingestion_id <- record$id; state$ingestion_auto_open <- record$id; state$page <- "ingestion"
    refresh(); message("Source import queued. Full-file checks are running in the background.")
  }))
  shiny::observeEvent(input$open_ingestion, attempt(function() {
    r <- brohn_ingestion(store, input$open_ingestion); brohn_project(store, r$project_id)
    state$ingestion_id <- r$id; state$ingestion_auto_open <- NULL; state$page <- "ingestion"; refresh()
  }))
  current_command <- function(command) {
    brohn_require(is.list(command) && identical(state$page, "ingestion") && identical(command$id, state$ingestion_id), "Open this import before changing it.")
    r <- brohn_ingestion(store, command$id)
    brohn_require(identical(input$ingestion_form_identity, paste(r$id, r$revision, sep = ":")) && identical(as.integer(command$revision), r$revision),
      "The import changed. Review its current state before continuing.")
    r
  }
  shiny::observeEvent(input$cancel_ingestion, attempt(function() {
    r <- current_command(input$cancel_ingestion); brohn_cancel_ingestion(store, r$id, r$revision)
    state$ingestion_auto_open <- NULL; refresh(); message("Import cancelled; the incoming original is retained.")
  }))
  shiny::observeEvent(input$retry_ingestion, attempt(function() {
    r <- current_command(input$retry_ingestion)
    brohn_retry_ingestion(store, r$id, r$revision, paste0("ui-retry:", r$id, ":", r$revision))
    state$ingestion_auto_open <- r$id; refresh(); message("The same original is queued again with its saved destination.")
  }))
  shiny::observeEvent(input$ingestion_page, attempt(function() {
    command <- input$ingestion_page; destination <- context()
    brohn_require((state$page == "datasets" || (state$page == "study" && state$stage == "Collect")) &&
      identical(command$study_id, destination$study_id) && brohn_number(command$direction, -1, 1, TRUE) && abs(command$direction) == 1,
      "Use the import history controls in the current study or Data library.")
    page <- brohn_ingestion_history(store, destination$project_id, destination$study_id, state$ingestion_offset)
    brohn_require(identical(as.numeric(command$offset), as.numeric(page$offset)), "This history page changed. Use its current controls.")
    state$ingestion_offset <- max(0, page$offset+40*command$direction)
  }))
  output$ingestion_history <- shiny::renderUI({
    shiny::invalidateLater(2000, session); state$refresh
    shiny::req(state$page == "datasets" || (state$page == "study" && state$stage == "Collect"))
    destination <- context(); brohn_ingestion_history_ui(brohn_ingestion_history(store, destination$project_id, destination$study_id, state$ingestion_offset))
  })
  output$ingestion_detail <- shiny::renderUI({
    shiny::invalidateLater(1500, session); state$refresh; shiny::req(state$page == "ingestion", state$ingestion_id)
    brohn_ingestion_detail_ui(store, brohn_ingestion(store, state$ingestion_id))
  })
  shiny::observe({
    shiny::invalidateLater(1500, session)
    attempt(function() {
      brohn_reap_ingestion_guards(store)
      if (identical(state$page, "ingestion") && identical(state$ingestion_id, state$ingestion_auto_open) && !is.null(state$ingestion_id)) {
        r <- brohn_ingestion(store, state$ingestion_id)
        if (identical(r$body$effective_status, "ready")) {
          state$dataset_id <- r$body$dataset_id; state$ingestion_auto_open <- NULL; state$page <- "dataset"
          refresh(); message("Original source saved. Confirm the suggested mapping to analyse it.")
        }
      }
    }, clear_error = FALSE)
  })
}
