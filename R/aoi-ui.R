study_regions <- function(x, stimulus_id) {
  Filter(function(a) identical(a$stimulus_id, stimulus_id), x$study$aois)
}

aoi_dialog <- function(x, index) {
  stimulus_id <- x$study$stimulus_ids[[index]]
  asset <- Filter(function(a) identical(a$stimulus_id, stimulus_id), x$study$stimulus_assets)[[1]]
  regions <- study_regions(x, stimulus_id)
  selected <- if (length(regions)) regions[[1]] else NULL
  coords <- if (is.null(selected)) rep(0, 4) else unlist(selected[c("x", "y", "width", "height")])
  choices <- c("New area" = "", setNames(vapply(regions, function(a) a$id, character(1)),
                                       vapply(regions, function(a) a$label, character(1))))
  shiny::modalDialog(title = paste("Areas of interest - design", c("A", "B")[[index]]), size = "l",
    shiny::p("Draw around the part of the image you want to study, such as a logo or a price. Give matching areas the same name in both designs."),
    shiny::div(role = "alert", class = "error-panel aoi-error", shiny::textOutput("aoi_error")),
    shiny::selectInput("aoi_selection", "Area to edit", choices, selected = if (is.null(selected)) "" else selected$id, selectize = FALSE),
    shiny::textInput("aoi_label", "Area name", if (is.null(selected)) "Target" else selected$label),
    shiny::div(class = "aoi-canvas-wrap", shiny::tags$svg(
      id = "aoi_canvas", `data-aoi-editor` = "true", `data-image-width` = asset$width, `data-image-height` = asset$height,
      viewBox = paste(0, 0, asset$width, asset$height), width = asset$width, height = asset$height,
      role = "img", `aria-label` = "Image with selected area overlay. Use the percentage fields below as a keyboard alternative.",
      style = paste0("width:100%;height:auto;max-width:", min(640, 440 * asset$width / asset$height), "px;"),
      shiny::tags$image(href = paste0("data:image/png;base64,", asset$data_base64), x = 0, y = 0, width = asset$width, height = asset$height),
      shiny::tags$rect(id = "aoi_rectangle", x = coords[[1]] * asset$width, y = coords[[2]] * asset$height,
        width = coords[[3]] * asset$width, height = coords[[4]] * asset$height,
        fill = "#ffd43b", `fill-opacity` = "0.22", stroke = "#49359e", `stroke-width` = "2", `vector-effect` = "non-scaling-stroke"))),
    shiny::p(class = "muted", "Drag on the image, or enter percentages below. Left and top are measured from the image's top-left corner."),
    shiny::div(class = "aoi-fields",
      shiny::numericInput("aoi_x", "Left (%)", coords[[1]] * 100, min = 0, max = 100, step = 0.1),
      shiny::numericInput("aoi_y", "Top (%)", coords[[2]] * 100, min = 0, max = 100, step = 0.1),
      shiny::numericInput("aoi_width", "Width (%)", coords[[3]] * 100, min = 0, max = 100, step = 0.1),
      shiny::numericInput("aoi_height", "Height (%)", coords[[4]] * 100, min = 0, max = 100, step = 0.1)),
    shiny::p(class = "muted", "Areas are attached to this exact image. Replacing it clears its areas. This is manual region definition; no gaze analysis has been run."),
    footer = shiny::tagList(shiny::actionButton("remove_aoi", "Remove selected area", class = "btn-outline-danger"),
      shiny::modalButton("Cancel"), shiny::actionButton("save_aoi", "Save area", class = "btn-primary")))
}

bind_aoi_editor <- function(input, output, session, state, capture_changes, persist, attempt) {
  context <- shiny::reactiveValues(stimulus_id = NULL, error = NULL,
                                   initial_selection = "", selection_initialized = FALSE)
  modal_attempt <- function(action) tryCatch({ action(); context$error <- NULL },
    error = function(e) context$error <- conditionMessage(e))
  output$aoi_error <- shiny::renderText(if (is.null(context$error)) "" else context$error)
  for (i in 1:2) local({
    index <- i
    shiny::observeEvent(input[[paste0("edit_aoi_", c("a", "b")[[index]])]], attempt(function() {
      x <- capture_changes()
      assert_aoi_draft_editable(x)
      context$stimulus_id <- x$study$stimulus_ids[[index]]
      record_assert(any(vapply(x$study$stimulus_assets, function(a) identical(a$stimulus_id, context$stimulus_id), logical(1))), "Attach an image first.")
      persist(x)
      context$error <- NULL
      regions <- study_regions(x, context$stimulus_id)
      context$initial_selection <- if (length(regions)) regions[[1]]$id else ""
      context$selection_initialized <- FALSE
      shiny::showModal(aoi_dialog(state$bundle, index))
    }))
  })
  shiny::observeEvent(input$aoi_selection, {
    shiny::req(context$stimulus_id)
    if (!context$selection_initialized) {
      context$selection_initialized <- TRUE
      if (identical(input$aoi_selection, context$initial_selection)) return()
    }
    regions <- study_regions(state$bundle, context$stimulus_id)
    selected <- Filter(function(a) identical(a$id, input$aoi_selection), regions)
    if (length(selected)) {
      a <- selected[[1]]
      shiny::updateTextInput(session, "aoi_label", value = a$label)
      values <- unlist(a[c("x", "y", "width", "height")]) * 100
    } else if (identical(input$aoi_selection, "")) {
      shiny::updateTextInput(session, "aoi_label", value = "Target")
      values <- rep(0, 4)
    } else return()
    for (i in 1:4) shiny::updateNumericInput(session, c("aoi_x", "aoi_y", "aoi_width", "aoi_height")[[i]], value = values[[i]])
    context$error <- NULL
  }, ignoreNULL = TRUE)
  shiny::observeEvent(input$aoi_draw, {
    shiny::req(context$stimulus_id)
    coordinates <- input$aoi_draw[c("x", "y", "width", "height")]
    if (length(coordinates) != 4 || !all(vapply(coordinates, function(v) is.numeric(v) && length(v) == 1 && is.finite(v), logical(1)))) return()
    for (i in 1:4) shiny::updateNumericInput(session, c("aoi_x", "aoi_y", "aoi_width", "aoi_height")[[i]], value = round(coordinates[[i]] * 100, 2))
  })
  shiny::observe({
    values <- list(x = input$aoi_x, y = input$aoi_y, width = input$aoi_width, height = input$aoi_height)
    if (all(vapply(values, function(v) is.numeric(v) && length(v) == 1 && is.finite(v), logical(1))))
      session$sendCustomMessage("aoi-preview", lapply(values, function(v) v / 100))
  })
  selected_id <- function() {
    id <- input$aoi_selection
    record_assert(scalar_text(id), "Choose an existing area first.")
    record_assert(any(vapply(study_regions(state$bundle, context$stimulus_id), function(a) identical(a$id, id), logical(1))), "Choose an area on this image.")
    id
  }
  shiny::observeEvent(input$save_aoi, modal_attempt(function() {
    shiny::req(context$stimulus_id)
    x <- capture_changes()
    id <- if (identical(input$aoi_selection, "")) NULL else selected_id()
    region <- new_rectangle_aoi(x$study, context$stimulus_id, input$aoi_label,
      input$aoi_x / 100, input$aoi_y / 100, input$aoi_width / 100, input$aoi_height / 100, id)
    persist(set_study_aoi(x, region))
    shiny::removeModal()
  }))
  shiny::observeEvent(input$remove_aoi, modal_attempt(function() {
    persist(remove_study_aoi(capture_changes(), selected_id()))
    shiny::removeModal()
  }))
  invisible(NULL)
}
