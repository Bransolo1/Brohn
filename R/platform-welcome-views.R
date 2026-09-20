# Researcher authoring is separate from the participant renderer and its colours.
brohn_welcome_authoring_ui <- function(store, design) {
  welcome <- brohn_default(design$welcome, brohn_new_welcome())
  command <- list(study_id = design$id)
  brohn_card(class = "brohn-welcome-authoring", title = "Welcome your participants",
    subtitle = "Introduce the study before its separate information and consent page. This optional opening is saved with the design.",
    shiny::checkboxInput("welcome_enabled", "Include a welcome page before consent", !is.null(design$welcome)),
    shiny::conditionalPanel("input.welcome_enabled === true",
      shiny::textInput("welcome_title", "Welcome heading", welcome$title),
      shiny::textAreaInput("welcome_text", "Welcome message", welcome$text, rows = 4),
      if (!is.null(welcome$asset)) shiny::tags$figure(class = "brohn-welcome-image",
        shiny::tags$img(src = brohn_asset_data_uri(store, welcome$asset), alt = welcome$image_alt),
        shiny::tags$figcaption(welcome$asset$filename)),
      shiny::textInput("welcome_image_alt", "Image description for participants who cannot see it", welcome$image_alt),
      shiny::div(class = "brohn-toolbar",
        brohn_command(if (is.null(welcome$asset)) "Add welcome image" else "Replace welcome image", "welcome_image_open", command),
        if (!is.null(welcome$asset)) brohn_command("Remove welcome image", "welcome_image_remove", command),
        brohn_command("Preview saved welcome", "welcome_preview", command, id = "welcome-preview-open")),
      shiny::p(class = "brohn-muted", "Use a PNG image up to 5 MiB. Image uploads keep their original bytes; later replacements do not change an existing participant release.")),
    shiny::p(class = "brohn-muted", "Welcome introduces the study. Consent records the participation choice. Instructions prepare the participant after consent; debrief closes the session."))
}

.brohn_welcome_preview_document <- function(store, record) {
  welcome <- record$body$welcome
  brohn_validate_welcome(welcome)
  payload <- list(welcome = welcome, consent = record$body$consent, appearance = record$body$appearance,
    image_source = if (is.null(welcome$asset)) NULL else brohn_asset_data_uri(store, welcome$asset))
  # Literal JSON in an inert script element: escape HTML delimiters and Unicode
  # line separators before constructing srcdoc. No authored HTML is executable.
  json <- brohn_json(payload)
  json <- gsub("<", "\\u003c", json, fixed = TRUE); json <- gsub(">", "\\u003e", json, fixed = TRUE)
  paste0('<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">',
    '<title>Saved welcome preview | Brohn</title><link rel="stylesheet" href="participant/runner.css">',
    '<link rel="stylesheet" href="participant/welcome.css"><script src="participant/welcome.js" defer></script>',
    '<script src="participant/welcome-preview.js" defer></script></head><body><div id="participant-app">',
    '<main id="content" tabindex="-1" aria-label="Participant page preview"></main><p id="preview-status" role="status" aria-live="polite"></p></div>',
    '<script type="application/json" id="welcome-preview-data">', json, '</script></body></html>')
}

brohn_install_welcome_ui <- function(input, output, session, store, state, current, attempt, capture, update_study) {
  upload <- shiny::reactiveVal(NULL); preview <- shiny::reactiveVal(NULL); upload_error <- shiny::reactiveVal(NULL)
  output$welcome_upload_error <- shiny::renderUI(if (!is.null(upload_error())) shiny::div(class = "brohn-alert brohn-alert-error", role = "alert", upload_error()))
  author <- function(command) {
    brohn_require(identical(state$page, "study") && identical(state$stage, "Plan") && !is.null(current$study) &&
      identical(command$study_id, current$study$id) && identical(input$study_form_identity, paste(current$study$id, "Plan", sep = ":")),
      "Open this study's current Plan before preparing its welcome page.")
    brohn_require(!isTRUE(current$study$body$archived), "Restore this study before editing its welcome page.")
    capture()
    record <- current$study; saved <- brohn_study(store, record$id); brohn_project(store, record$project_id)
    brohn_require(identical(record$revision, saved$revision) && identical(brohn_hash(record$body), brohn_hash(saved$body)),
      "The saved study changed. Reopen Plan before continuing.")
    brohn_require(!is.null(record$body$welcome), "Enable the welcome page before preparing its image or preview.")
    record
  }
  upload_record <- function() {
    expected <- upload()
    brohn_require(!is.null(expected) && identical(state$page, "study") && identical(state$stage, "Plan") &&
      identical(state$study_id, expected$id) && !is.null(current$study) && identical(current$study$id, expected$id), "Reopen the image action in the original study.")
    record <- brohn_study(store, expected$id); brohn_project(store, record$project_id)
    brohn_require(!isTRUE(record$body$archived) && identical(record$revision, expected$revision) &&
      identical(brohn_hash(record$body), expected$hash) && identical(current$study$revision, expected$revision),
      "The study changed while the image dialog was open. Reopen it before attaching an image.")
    record
  }
  shiny::observeEvent(input$welcome_image_open, attempt(function() {
    record <- author(input$welcome_image_open)
    upload(list(id = record$id, revision = record$revision, hash = brohn_hash(record$body), previous_path = input$welcome_image_file$datapath)); upload_error(NULL)
    shiny::showModal(shiny::modalDialog(title = "Add the welcome image", size = "m",
      shiny::p("Choose the exact image participants should see before consent. Add a useful description of its content."), shiny::uiOutput("welcome_upload_error"),
      shiny::tags$script(shiny::HTML("(function(){if(window.brohnWelcomeUploadBound)return;window.brohnWelcomeUploadBound=true;document.addEventListener('change',function(e){if(e.target.id==='welcome_image_file'){var b=document.getElementById('welcome_image_save');if(b)b.disabled=true;}},true);jQuery(document).on('shiny:inputchanged.brohnWelcomeUpload',function(e){if(e.name==='welcome_image_file'){var b=document.getElementById('welcome_image_save');if(b)b.disabled=!e.value;}});})();")),
      shiny::fileInput("welcome_image_file", "Welcome image (PNG)", accept = ".png"),
      shiny::textAreaInput("welcome_upload_alt", "Image description", record$body$welcome$image_alt, rows = 2),
      shiny::p(class = "brohn-muted", "PNG, up to 5 MiB; no more than 4096 pixels per side or 8 million pixels in total."),
      footer = shiny::tagList(shiny::modalButton("Cancel"), shiny::actionButton("welcome_image_save", "Attach image", class = "btn-primary", disabled = "disabled"))))
  }))
  shiny::observeEvent(input$welcome_image_save, attempt(function() tryCatch({
    upload_error(NULL)
    record <- upload_record(); file <- input$welcome_image_file
    brohn_require(!is.null(file) && brohn_text(file$datapath, 4096) && file.exists(file$datapath) && !identical(file$datapath, upload()$previous_path), "Choose a PNG image in this dialog before attaching it.")
    brohn_store_batch(store, function() {
      design <- brohn_attach_welcome_png(store, record$body, file$datapath, file$name, input$welcome_upload_alt)
      update_study(design)
    })
    upload(NULL); shiny::removeModal()
    session$onFlushed(function() session$sendCustomMessage("brohn-focus", "welcome-preview-open"), once = TRUE)
  }, error = function(e) {upload_error(conditionMessage(e)); stop(e)})))
  shiny::observeEvent(input$welcome_image_remove, attempt(function() {
    record <- author(input$welcome_image_remove); d <- record$body
    d$welcome["asset"] <- list(NULL); d$welcome$image_alt <- ""; update_study(d)
  }))
  shiny::observeEvent(input$welcome_preview, attempt(function() {
    record <- author(input$welcome_preview)
    preview(list(id = record$id, revision = record$revision, hash = brohn_hash(record$body)))
    shiny::showModal(shiny::modalDialog(title = "Preview your saved welcome", size = "l",
      shiny::p(paste("Saved design revision", record$revision, "\u00b7 the participant renderer and saved colours are used below.")),
      shiny::tags$iframe(title = "Saved participant welcome preview", class = "brohn-welcome-preview", sandbox = "allow-scripts",
        srcdoc = .brohn_welcome_preview_document(store, record)),
      shiny::p(class = "brohn-muted", "This preview creates no participant session. Continue shows the saved study information; accepting consent and starting the study are disabled here."),
      footer = shiny::actionButton("welcome_preview_close", "Close welcome preview"), easyClose = FALSE))
  }))
  shiny::observeEvent(input$welcome_preview_close, {preview(NULL); shiny::removeModal(); session$sendCustomMessage("brohn-focus", "welcome-preview-open")})
  shiny::observeEvent(list(state$page, state$study_id, state$stage), {
    context <- brohn_default(upload(), preview())
    if (!is.null(context) && (!identical(state$page, "study") || !identical(state$study_id, context$id) || !identical(state$stage, "Plan"))) {
      upload(NULL); preview(NULL); shiny::removeModal()
    }
  }, ignoreInit = FALSE)
  invisible(list(upload = upload, preview = preview))
}
