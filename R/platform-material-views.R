brohn_material_card_ui <- function(design, kind, material, task_id = NULL) {
  illustration<-kind %in% c("question","maxdiff_item")
  command <- list(study_id = design$id, kind = kind, material_id = material$id, task_id = task_id)
  open <- function(label, mode) brohn_command(label, "material_open", c(command, list(mode = mode)))
  shiny::div(class = "brohn-material-card",
    if (!is.null(material$asset)) shiny::tagList(
      shiny::p(class = "brohn-material-filename", shiny::strong(brohn_default(material$asset$filename, "Saved media"))),
      shiny::p(class = "brohn-muted", paste(material$asset$media_type, "\u00b7", format(material$asset$size/1024, digits = 4), "KiB",
        if (!is.null(material$asset$width)) paste0(" \u00b7 ", material$asset$width, " \u00d7 ", material$asset$height, " px") else "")),
      if (material$type == "image") shiny::p(if ("image_alt" %in% names(material)) material$image_alt else "Open Edit material to review the participant image description.")),
    shiny::div(class = "brohn-toolbar", if(!illustration||!is.null(material$asset))open(if(illustration)"Preview illustration" else "Preview material", "preview"),
      open(if(illustration) {if(is.null(material$asset))"Add illustration" else "Edit image"} else if (is.null(material$asset)) "Add image" else "Edit material", "edit")))
}

.brohn_material_response <- function(status, type = "text/plain; charset=utf-8", content = "Material preview is unavailable.") {
  structure(list(status = as.integer(status), content_type = type, content = content,
    headers = list("Cache-Control" = "no-store", "X-Content-Type-Options" = "nosniff")), class = "httpResponse")
}

brohn_install_materials <- function(input, output, session, store, current, state, attempt, capture, update_study,
    register_resource = function(name, data, filter) session$registerDataObj(name, data, filter),can_open=function(kind)TRUE) {
  dialog <- shiny::reactiveVal(NULL); error <- shiny::reactiveVal(NULL); blocked <- shiny::reactiveVal(NULL)
  resource <- shiny::reactiveVal(NULL); reload <- shiny::reactiveVal(0L)
  close <- function() {dialog(NULL); resource(NULL); blocked(NULL); error(NULL); shiny::removeModal()}
  record <- function(command = NULL) {
    pin <- dialog(); brohn_require(!is.null(pin), "Reopen this material before continuing.")
    if (!is.null(command)) brohn_require(identical(command$token, pin$token) && identical(input$material_dialog_identity, pin$token), "Use the current material dialog.")
    brohn_require(identical(state$page, "study") && identical(state$stage, pin$stage) && identical(state$study_id, pin$id) &&
      !is.null(current$study) && identical(current$study$id, pin$id), "Reopen this material in its original study.")
    saved <- brohn_study(store, pin$id); brohn_project(store, saved$project_id)
    brohn_require(!isTRUE(saved$body$archived) && identical(saved$project_id, pin$project_id) &&
      identical(saved$revision, pin$revision) && identical(brohn_hash(saved$body), pin$design_hash) &&
      identical(current$study$revision, pin$revision) && identical(brohn_hash(current$study$body), pin$design_hash),
      "This saved study changed. Close the dialog and reopen the material before saving.")
    target <- brohn_material_target(saved$body, pin$kind, pin$material_id, pin$task_id)
    brohn_require(identical(brohn_hash(brohn_default(target$owner,target$material)), pin$target_hash), "This material changed. Reopen its current revision.")
    saved
  }
  apply <- function(command, fn) attempt(function() tryCatch({
    error(NULL); saved <- record(command); pin <- dialog()
    brohn_require(identical(pin$mode, "edit"), "Open Edit material before making changes.")
    brohn_store_batch(store, function() update_study(fn(saved$body, pin)))
    close()
  }, error = function(e) {error(conditionMessage(e)); stop(e)}))
  output$material_error <- shiny::renderUI({value <- brohn_default(blocked(), error()); if (!is.null(value)) shiny::div(class = "brohn-alert brohn-alert-error", role = "alert", value)})
  output$material_saved_preview <- shiny::renderUI({
    pin <- dialog(); shiny::req(pin); reload()
    if (!is.null(blocked())) return(shiny::p(class = "brohn-muted", "The saved preview is unavailable until this material is reopened."))
    tryCatch({
      saved <- record(); target <- brohn_material_target(saved$body, pin$kind, pin$material_id, pin$task_id); m <- target$material
      type <- brohn_material_preview_type(m)
      stage <- shiny::div(class = paste("brohn-material-stage", if (pin$kind == "exemplar") "brohn-material-exemplar" else ""),
        style = paste0("background:", saved$body$appearance$background, ";color:", saved$body$appearance$foreground, ";"),
        if (type == "text") shiny::p(class = "brohn-material-text", if (nzchar(m$content)) m$content else "This material has no participant text yet.") else {
          uri <- paste0(resource(), "&render=", reload())
          switch(type, image = shiny::tags$img(src = uri, alt = brohn_material_description(m, pin$kind), `data-material-media` = "image"),
            audio = shiny::tags$audio(src = uri, controls = NA, preload = "metadata", `aria-label` = paste("Saved audio:", target$title), `data-material-media` = "audio"),
            video = shiny::tags$video(src = uri, controls = NA, preload = "metadata", playsinline = NA, `aria-label` = paste("Saved video:", target$title), `data-material-media` = "video"))
        })
      shiny::tagList(stage, if (type != "text") shiny::tagList(shiny::p(id = "material_media_status", role = "status", `aria-live` = "polite", "Loading the saved material..."),
        brohn_command("Retry saved preview", "material_retry", list(token = pin$token))),
        shiny::p(class = "brohn-muted", "Saved material and study colours. This preview does not start a participant session or rehearse the timed procedure."))
    }, error = function(e) shiny::div(class = "brohn-alert brohn-alert-warning", role = "status", conditionMessage(e)))
  })
  shiny::observeEvent(input$material_open, attempt(function() {
    command <- input$material_open
    brohn_require(is.list(command) && command$mode %in% c("preview", "edit") && !is.null(current$study) &&
      identical(command$study_id, current$study$id) && identical(state$page, "study"), "Open the material from its current study.")
    brohn_require(isTRUE(can_open(command$kind)),"Save or cancel the current best-worst exercise before editing its saved item images.")
    target <- brohn_material_target(current$study$body, command$kind, command$material_id, command$task_id)
    brohn_require(identical(state$stage, target$stage) && identical(input$study_form_identity, paste(current$study$id, target$stage, sep = ":")), "Wait for this study's current material controls.")
    capture(); saved <- brohn_study(store, current$study$id); brohn_project(store, saved$project_id)
    brohn_require(!isTRUE(saved$body$archived) && identical(current$study$revision, saved$revision) && identical(brohn_hash(current$study$body), brohn_hash(saved$body)), "Reopen the current saved study before preparing its materials.")
    target <- brohn_material_target(saved$body, command$kind, command$material_id, command$task_id); m <- target$material
    pin <- c(command, list(id = saved$id, revision = saved$revision, design_hash = brohn_hash(saved$body), project_id = saved$project_id,
      target_hash = brohn_hash(brohn_default(target$owner,m)), stage = target$stage, token = brohn_token(), previous_path = input$material_file$datapath))
    dialog(pin); error(NULL); blocked(NULL); reload(0L)
    uri <- register_resource("brohn-material", list(token = pin$token), function(data, req) {
      shiny::isolate(tryCatch({
        query <- shiny::parseQueryString(brohn_default(req$QUERY_STRING, ""))
        brohn_require(req$REQUEST_METHOD %in% c("GET", "HEAD") && identical(query$material_key, data$token) &&
          !is.null(dialog()) && identical(dialog()$token, data$token), "This preview link is no longer active.")
        current_record <- record(); active <- dialog(); selected <- brohn_material_target(current_record$body, active$kind, active$material_id, active$task_id)$material
        brohn_require(brohn_material_preview_type(selected) != "text", "There is no media to preview.")
        path <- brohn_object_path(store, selected$asset$hash, verify = TRUE)
        brohn_require(identical(as.numeric(file.info(path)$size), as.numeric(selected$asset$size)), "The saved material size changed.")
        .brohn_material_response(200, selected$asset$media_type, list(file = path, owned = FALSE))
      }, error = function(e) .brohn_material_response(404)))
    })
    resource(paste0(uri, "&material_key=", pin$token))
    cmd <- function(label, event, ...) brohn_command(label, event, list(token = pin$token), ...)
    shiny::showModal(shiny::modalDialog(title = if (command$mode == "preview") paste("Preview", target$title) else paste("Edit", target$title), size = "l", easyClose = FALSE,
      shiny::div(class = "brohn-material-dialog", `data-material-dialog` = pin$token,
        shiny::div(hidden = NA, shiny::textInput("material_dialog_identity", NULL, pin$token)),
        shiny::tags$script(src = "material-preview.js"), shiny::uiOutput("material_error"),
        shiny::p(class = "brohn-muted", paste("Saved revision", saved$revision)), shiny::uiOutput("material_saved_preview"),
        if (command$mode == "edit") shiny::tagList(
          shiny::h3("Participant image description"), shiny::textAreaInput("material_alt", "Describe what the image shows", brohn_default(m$image_alt, ""), rows = 2, width = "100%"),
          shiny::p(class = "brohn-muted", "Use your own description. It is delivered exactly as written; task categories are not added automatically."),
          if (m$type == "image" && !is.null(m$asset)) cmd("Save description", "material_describe"),
          shiny::tags$details(open = if (is.null(m$asset)) NA else NULL, shiny::tags$summary(if (is.null(m$asset)) "Attach an image" else "Replace with a PNG image"),
            shiny::fileInput("material_file", "PNG image", accept = ".png"),
            shiny::p("PNG up to 5 MiB; at most 4096 pixels per side and 8 million pixels. The original bytes are retained."),
            if (pin$kind == "stimulus" && length(m$aois)) shiny::p(class = "brohn-alert brohn-alert-warning", "Replacing this image with different bytes clears its current areas. Earlier revisions keep their image and areas."),
            cmd("Attach selected PNG", "material_attach", class = "btn btn-primary", id = "material_attach_button", disabled = "disabled")),
          if(pin$kind %in% c("question","maxdiff_item")&&!is.null(m$asset))shiny::tags$details(shiny::tags$summary("Remove illustration"),
            shiny::p(if(pin$kind=="question")"Keep this question's wording, answers and display rules. Earlier releases retain their illustration." else "Keep this item's label and all choice sets. Earlier releases retain their illustration."),cmd("Remove this illustration","material_remove_illustration")),
          if (!pin$kind %in% c("question","maxdiff_item")&&!is.null(m$asset)) shiny::tags$details(shiny::tags$summary("Remove media and use text"),
            shiny::textAreaInput("material_text", "Replacement participant text", m$content, rows = 3, width = "100%"),
            shiny::p(if (pin$kind == "exemplar") "The exemplar stays in its category. Supply its replacement text before removing the image." else "The current image and its areas will be removed. Add participant text before releasing this study."),
            cmd("Remove media and use this text", "material_use_text")))),
      footer = cmd(if (command$mode == "preview") "Close preview" else "Close editor", "material_close")))
  }))
  shiny::observeEvent(input$material_attach, apply(input$material_attach, function(d, pin) {
    file <- input$material_file
    brohn_require(!is.null(file) && brohn_text(file$datapath, 4096) && file.exists(file$datapath) && !identical(file$datapath, pin$previous_path), "Choose a new PNG in this dialog before attaching it.")
    brohn_material_attach_png(store, d, pin$kind, pin$material_id, pin$task_id, file$datapath, file$name, input$material_alt)
  }))
  shiny::observeEvent(input$material_describe, apply(input$material_describe, function(d, pin) brohn_material_describe(d, pin$kind, pin$material_id, pin$task_id, input$material_alt)))
  shiny::observeEvent(input$material_use_text, apply(input$material_use_text, function(d, pin) brohn_material_use_text(d, pin$kind, pin$material_id, pin$task_id, input$material_text)))
  shiny::observeEvent(input$material_remove_illustration,apply(input$material_remove_illustration,function(d,pin){brohn_require(pin$kind %in% c("question","maxdiff_item"),"Choose a question or choice illustration.");if(pin$kind=="question")brohn_remove_question_illustration(d,pin$material_id)else brohn_remove_maxdiff_illustration(d,pin$task_id,pin$material_id)}))
  shiny::observeEvent(input$material_retry, attempt(function() tryCatch({record(input$material_retry); blocked(NULL); error(NULL); reload(reload()+1L)}, error = function(e) {error(conditionMessage(e)); stop(e)})))
  shiny::observeEvent(input$material_close, if (!is.null(dialog()) && identical(input$material_close$token, dialog()$token)) close())
  shiny::observeEvent(input$material_cancel, if (!is.null(dialog()) && identical(input$material_cancel$token, dialog()$token)) close())
  shiny::observe({
    pin <- dialog(); if (is.null(pin)) return()
    if (!identical(state$page, "study") || !identical(state$study_id, pin$id) || !identical(state$stage, pin$stage)) {close(); return()}
    shiny::invalidateLater(2000, session)
    # Keep typed recovery fields but clear the rendered media if authority or
    # the exact saved revision changes while the dialog is open.
    rejected <- tryCatch({record(); NULL}, error = function(e) conditionMessage(e)); blocked(rejected)
  })
  invisible(list(dialog = dialog, error = error, resource = resource, record = record, close = close))
}
