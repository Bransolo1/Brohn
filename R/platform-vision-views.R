brohn_aoi_prompt_ui <- function(store, stimulus) shiny::tagList(
  shiny::p("Select a point inside the object you want to study. Brohn will propose its outline and a surrounding rectangle for your review."),
  shiny::div(class = "brohn-aoi-editor",
    shiny::tags$svg(id = "brohn-aoi-prompt", viewBox = paste(0, 0, stimulus$asset$width, stimulus$asset$height),
      role = "img", `aria-label` = paste("Select a point on", stimulus$title), tabindex = "0",
      shiny::tags$title(paste("Select a point on", stimulus$title)),
      shiny::tags$image(href = brohn_asset_data_uri(store, stimulus$asset), width = stimulus$asset$width, height = stimulus$asset$height),
      shiny::tags$circle(id = "brohn-aoi-prompt-marker", cx = stimulus$asset$width/2, cy = stimulus$asset$height/2, r = min(stimulus$asset$width, stimulus$asset$height)*.015,
        fill = "#97d8c4", stroke = "#11171c", `stroke-width` = "3", `vector-effect` = "non-scaling-stroke"))),
  shiny::p("Keyboard: arrow keys move the point. You can also enter its coordinates."),
  shiny::div(class = "brohn-form-grid", shiny::numericInput("aoi_prompt_x", "Point from left (0 to 1)", .5, 0, 1, .01),
    shiny::numericInput("aoi_prompt_y", "Point from top (0 to 1)", .5, 0, 1, .01)))

brohn_proposals_ui <- function(store, study_id) {
  proposals <- brohn_aoi_proposals(store, study_id)
  jobs <- brohn_list_jobs(store, request_filters = list(study_id = study_id), operation = "segment_aoi")
  pending <- Filter(function(j) j$status %in% c("queued", "running", "failed", "cancelled"), jobs)
  if (!length(proposals) && !length(pending)) return(NULL)
  study <- brohn_study(store, study_id)
  brohn_card(title = "Suggested areas", subtitle = "Review the image and the proposed rectangle before using it in a study.",
    lapply(pending, function(j) shiny::div(class = "brohn-toolbar", brohn_badge(j$status),
      shiny::span(brohn_default(brohn_find(study$body$stimuli, j$request$stimulus_id)$title, "Earlier stimulus")),
      if (!is.null(j$error$message)) shiny::p(j$error$message))),
    lapply(proposals, function(p) shiny::div(class = "brohn-toolbar",
      shiny::span(brohn_default(brohn_find(study$body$stimuli, p$body$stimulus_id)$title, "Earlier stimulus")),
      brohn_badge(gsub("_", " ", p$body$status), if (p$body$status == "needs_review") "warning" else "neutral"),
      brohn_command(if (p$body$status == "needs_review" && !isTRUE(study$body$archived)) "Review suggestion" else "Inspect suggestion", "review_aoi_proposal", p$id))))
}
brohn_proposal_review_ui <- function(store, record, stimulus) {
  p <- record$body$proposal
  if (is.null(p$mask_object)) return(shiny::tagList(shiny::p("The model did not return a usable region at this point."), shiny::tags$pre(brohn_json(p, TRUE))))
  mask <- brohn_asset_data_uri(store, p$mask_object)
  shiny::tagList(
    shiny::p("The mask shows the model's proposal. The editable rectangle is the area that will be used for analysis; it can include background outside the mask."),
    shiny::tags$details(shiny::tags$summary("Inspect the saved model mask"),
      shiny::tags$img(src = mask, alt = "Binary model mask for this suggestion", class = "brohn-stimulus-image"),
      shiny::downloadButton("proposal_mask", "Download mask", icon = NULL)),
    brohn_aoi_editor(store, stimulus, c(list(label = "Reviewed area"), p[c("x", "y", "width", "height")])),
    shiny::textAreaInput("proposal_review_note", "Review note (optional)", "", rows = 2, width = "100%"))
}
