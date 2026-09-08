brohn_aoi_editor <- function(store, stimulus, area = NULL) {
  brohn_require(stimulus$type == "image" && !is.null(stimulus$asset), "Attach an image before defining an area. Text, moving media and scene regions need their own coordinate profile.")
  a <- if (is.null(area)) list(label = "New area", x = .2, y = .25, width = .6, height = .5) else area
  shiny::tagList(shiny::p("Draw a rectangle over the image, or enter its position and size below. The region stays in the image's coordinate frame."),
    shiny::div(class = "brohn-aoi-editor", `data-initial-region` = brohn_json(a),
      shiny::tags$svg(id = "brohn-aoi-canvas", viewBox = paste(0, 0, stimulus$asset$width, stimulus$asset$height),
        role = "img", `aria-label` = paste("Area preview on", stimulus$title), tabindex = "0",
        shiny::tags$title(paste("Area preview on", stimulus$title)),
        shiny::tags$image(href = brohn_asset_data_uri(store, stimulus$asset), width = stimulus$asset$width, height = stimulus$asset$height),
        shiny::tags$rect(id = "brohn-aoi-selection", x = a$x*stimulus$asset$width, y = a$y*stimulus$asset$height,
          width = a$width*stimulus$asset$width, height = a$height*stimulus$asset$height, fill = "#97d8c440", stroke = "#11171c", `stroke-width` = "3", `vector-effect` = "non-scaling-stroke"),
        shiny::tags$rect(id = "brohn-aoi-outline", x = a$x*stimulus$asset$width, y = a$y*stimulus$asset$height,
          width = a$width*stimulus$asset$width, height = a$height*stimulus$asset$height, fill = "none", stroke = "#ffffff", `stroke-width` = "1.5", `vector-effect` = "non-scaling-stroke"))),
    shiny::p(class = "brohn-muted", "Keyboard: arrow keys move the region; Shift + arrows resize it. Numeric fields provide the same control."),
    shiny::textInput("aoi_label", "Area name", a$label),
    shiny::div(class = "brohn-form-grid", shiny::numericInput("aoi_x", "Left (0 to 1)", a$x, 0, 1, .01),
      shiny::numericInput("aoi_y", "Top (0 to 1)", a$y, 0, 1, .01),
      shiny::numericInput("aoi_width", "Width (0 to 1)", a$width, .001, 1, .01),
      shiny::numericInput("aoi_height", "Height (0 to 1)", a$height, .001, 1, .01)),
    shiny::tags$button(type = "button", class = "btn btn-outline-secondary", id = "brohn-aoi-undo", "Undo region change"),
    shiny::tags$span(id = "brohn-aoi-announcement", role = "status", `aria-live` = "polite", class = "brohn-muted"))
}
