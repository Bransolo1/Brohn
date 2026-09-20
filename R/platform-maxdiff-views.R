# Explicit-choice authoring. Draft structure is redrawn only on an acknowledged
# command; typing never replaces a live input. IDs survive labels and reordering.
brohn_maxdiff_summary_ui <- function(design) {
  exercises <- brohn_default(design$maxdiff, list())
  brohn_card(title = "Best-worst choices (MaxDiff)", subtitle = "Ask an explicit question about which items matter most and least.",
    shiny::p("Each exercise uses your exact choice sets and framing. Review item coverage and replace original example materials before research use."),
    if (!length(exercises)) shiny::p("No best-worst exercise is configured.") else shiny::tags$ul(lapply(exercises, function(d)
      shiny::tags$li(shiny::strong(d$title), paste0(" - ", length(d$items), " items, ", length(d$sets), " sets "), brohn_command("Edit exercise", "maxdiff_edit", d$id)))),
    shiny::actionButton("maxdiff_add", "Add best-worst exercise"))
}
brohn_maxdiff_review_ui <- function(design,region_context=design$title) {
  review <- brohn_maxdiff_design_review(design)
  label <- function(id) brohn_find(design$items, id)$label
  shiny::tagList(shiny::p(shiny::strong(if (review$connected && review$all_items_present) "All items are connected in this design." else "Review missing items or disconnected sets before collection.")),
    shiny::p(paste(review$item_count, "items in", review$set_count, "sets.", "These counts describe coverage; they do not certify an optimal design.")),
    if (length(review$warnings)) shiny::tags$ul(lapply(review$warnings, shiny::tags$li)),
    brohn_table(lapply(review$item_coverage, function(r) list(item = label(r$item_id), presentations = r$presentations,
      declared_positions = paste(unlist(r$positions), collapse = ", "))), maximum = 60L, label = paste("Declared item and position coverage",region_context,sep=" - ")),
    shiny::p(class = "brohn-muted", "Position columns follow positions 1 to 8 in the saved sets. Seeded participant order is retained separately; these are not observed participant positions."),
    shiny::tags$details(shiny::tags$summary("Pair coverage"), brohn_table(lapply(review$pair_coverage, function(r)
      list(first_item = label(r$first_id), second_item = label(r$second_id), cooccurrences = r$cooccurrences)), maximum = 1770L, label = paste("All declared item-pair co-occurrences",region_context,sep=" - "))))
}
brohn_maxdiff_editor_current <- function(draft, current, state, input) {
  isTRUE(draft$active) && !is.null(current$study) && identical(current$study$id, draft$study_id) &&
    identical(as.numeric(current$study$revision), as.numeric(draft$revision)) && identical(brohn_hash(current$study$body), draft$design_hash) &&
    !isTRUE(current$study$body$archived) && identical(state$page, "study") && identical(state$stage, "Tasks") &&
    identical(input$study_form_identity, paste(draft$study_id, "Tasks", sep = ":")) && identical(input$maxdiff_form_identity, draft$token)
}
brohn_maxdiff_field_id <- function(token, version, kind, id) paste("md", kind, token, version, id, sep = "_")
brohn_maxdiff_structure_ui <- function(design, token, version) {
  field <- function(kind, id) brohn_maxdiff_field_id(token, version, kind, id)
  command <- function(label, action, extra = list()) brohn_command(label, "maxdiff_structure_command", c(list(token = token, version = version, action = action), extra))
  choices <- stats::setNames(brohn_ids(design$items), vapply(design$items, function(i) if (nzchar(i$label)) i$label else paste("Unnamed item", i$id), character(1)))
  shiny::div(`data-maxdiff-version` = version,
    shiny::div(hidden = NA, shiny::textInput("maxdiff_structure_identity", NULL, paste(token, version, sep = ":"))),
    shiny::tags$details(open = NA, shiny::tags$summary(paste("Items (", length(design$items), ")", sep = "")),
      shiny::p("Item identities stay the same when you edit a label. Remove an item from every set before deleting it."),
      shiny::tags$ol(lapply(seq_along(design$items), function(i) {item <- design$items[[i]]
        shiny::tags$li(shiny::textInput(field("label", item$id), paste("Item", i, "label"), item$label, width = "100%"),
          command(paste("Remove item", i), "remove_item", list(id = item$id)))})),
      command("Add item", "add_item")),
    shiny::tags$details(open = NA, shiny::tags$summary(paste("Choice sets (", length(design$sets), ")", sep = "")),
      shiny::p("Select 3 to 8 items in each set. Selected items retain their sequence; new selections append. Apply selections to refresh labels, inspect the ordered list and use its Move buttons. All order changes remain draft until Save."),
      shiny::tags$ol(lapply(seq_along(design$sets), function(i) {set <- design$sets[[i]]
        shiny::tags$li(shiny::tags$fieldset(shiny::tags$legend(paste("Choice set", i)),
          shiny::selectInput(field("members", set$id), paste("Items in set", i), choices, selected = unlist(set$item_ids), multiple = TRUE),
          shiny::tags$ol(lapply(seq_along(set$item_ids), function(j) {id <- set$item_ids[[j]]; item <- brohn_find(design$items, id)
            shiny::tags$li(shiny::span(brohn_default(item$label, id)), shiny::div(class = "brohn-toolbar",
              if (j > 1L) command(paste("Move position", j, "up in set", i), "move_member", list(id = set$id, item_id = id, direction = -1L)),
              if (j < length(set$item_ids)) command(paste("Move position", j, "down in set", i), "move_member", list(id = set$id, item_id = id, direction = 1L))))})),
          shiny::div(class = "brohn-toolbar", if (i > 1L) command(paste("Move set", i, "up"), "move_set", list(id = set$id, direction = -1L)),
            if (i < length(design$sets)) command(paste("Move set", i, "down"), "move_set", list(id = set$id, direction = 1L)),
            command(paste("Remove set", i), "remove_set", list(id = set$id)))))})),
      shiny::div(class = "brohn-toolbar", command("Apply selections and labels", "refresh"), command("Add choice set", "add_set"))))
}
brohn_install_maxdiff_ui <- function(input, output, session, current, state, attempt, capture, update_study) {
  draft <- shiny::reactiveValues(active = FALSE, token = NULL, version = 0L, study_id = NULL, revision = NULL, design_hash = NULL, exercise = NULL, reviewed = NULL)
  guard <- function(command = NULL, structure = FALSE) {
    brohn_require(brohn_maxdiff_editor_current(draft, current, state, input), "This best-worst editor belongs to an earlier study, revision or page. Cancel and reopen it before saving.")
    if (!is.null(command)) brohn_require(is.list(command) && identical(command$token, draft$token), "This command belongs to an earlier best-worst editor.")
    if (structure) brohn_require(identical(as.numeric(command$version), as.numeric(draft$version)) &&
      identical(input$maxdiff_structure_identity, paste(draft$token, draft$version, sep = ":")), "Wait for the current item/set controls, then select the command again.")
  }
  capture_structure <- function() {
    brohn_require(identical(input$maxdiff_structure_identity, paste(draft$token, draft$version, sep = ":")), "The item/set form is still changing. Wait for it before applying or saving.")
    d <- draft$exercise
    for (i in seq_along(d$items)) {v <- input[[brohn_maxdiff_field_id(draft$token, draft$version, "label", d$items[[i]]$id)]]
      brohn_require(is.character(v) && length(v) == 1L && !is.na(v), "Wait for every item field to load before saving."); d$items[[i]]$label <- v}
    for (i in seq_along(d$sets)) {v <- brohn_default(input[[brohn_maxdiff_field_id(draft$token, draft$version, "members", d$sets[[i]]$id)]], character())
      brohn_require(is.character(v) && !anyNA(v) && !anyDuplicated(v) && all(v %in% brohn_ids(d$items)), "Review the selected item identities.")
      # Membership changes append new selections. Existing sequence is changed
      # only by the explicit Move buttons, not selectize's display ordering.
      prior <- unlist(d$sets[[i]]$item_ids); d$sets[[i]]$item_ids <- as.list(c(prior[prior %in% v], v[!v %in% prior]))}
    d
  }
  capture_framing <- function(d) {
    d$title <- input$maxdiff_title; d$origin <- input$maxdiff_origin; d$materials_rights <- input$maxdiff_rights; d$seed <- input$maxdiff_seed
    d$settings$prompt <- input$maxdiff_prompt; d$settings$best_label <- input$maxdiff_best; d$settings$worst_label <- input$maxdiff_worst
    d$settings$required <- input$maxdiff_required; d$settings$set_order <- input$maxdiff_set_order; d$settings$item_order <- input$maxdiff_item_order
    d$settings$design_rationale <- input$maxdiff_rationale; d$settings$analysis$fit_aggregate <- input$maxdiff_fit
    brohn_maxdiff_validate(d); d
  }
  open_editor <- function(id = NULL) {
    brohn_require(!is.null(current$study) && identical(state$page, "study") && identical(state$stage, "Tasks") &&
      identical(input$study_form_identity, paste(current$study$id, "Tasks", sep = ":")), "Open best-worst choices from this study's Tasks page.")
    capture(); design <- current$study$body
    brohn_require(!isTRUE(design$archived), "Restore this study before editing best-worst choices.")
    exercise <- if (is.null(id)) brohn_maxdiff_new() else brohn_find(brohn_default(design$maxdiff, list()), id)
    brohn_require(!is.null(exercise), "This best-worst exercise no longer exists.")
    draft$active <- TRUE; draft$study_id <- current$study$id; draft$revision <- current$study$revision; draft$design_hash <- brohn_hash(design)
    draft$token <- brohn_id("maxdiff-form"); draft$version <- 1L; draft$exercise <- exercise; draft$reviewed <- NULL
    cmd <- function(label, event, class = "btn btn-outline-secondary") brohn_command(label, event, list(token = draft$token), class)
    shiny::showModal(shiny::modalDialog(title = if (is.null(id)) "Add best-worst exercise" else "Edit best-worst exercise", size = "l", easyClose = FALSE,
      shiny::div(hidden = NA, shiny::textInput("maxdiff_form_identity", NULL, draft$token)),
      shiny::textInput("maxdiff_title", "Exercise name", exercise$title),
      shiny::textAreaInput("maxdiff_prompt", "Question and participant instructions", exercise$settings$prompt, rows = 3, width = "100%"),
      shiny::div(class = "brohn-form-grid", shiny::textInput("maxdiff_best", "Best-choice label", exercise$settings$best_label),
        shiny::textInput("maxdiff_worst", "Worst-choice label", exercise$settings$worst_label)),
      shiny::checkboxInput("maxdiff_required", "Require a complete pair to continue", exercise$settings$required),
      shiny::p(class = "brohn-muted", "Participants can still withdraw. Best and worst must be different items; partial choices remain missing outcomes."),
      shiny::tags$details(shiny::tags$summary("Materials and ordering"),
        shiny::selectInput("maxdiff_origin", "Materials source", c("Original example / synthetic" = "synthetic", "Researcher supplied and reviewed" = "researcher_supplied"), exercise$origin),
        shiny::textAreaInput("maxdiff_rights", "Material provenance and permission", exercise$materials_rights, rows = 2, width = "100%"),
        shiny::textAreaInput("maxdiff_rationale", "Choice-set design rationale", exercise$settings$design_rationale, rows = 3, width = "100%"),
        shiny::div(class = "brohn-form-grid", shiny::selectInput("maxdiff_set_order", "Set order", c("Seeded participant order" = "seeded", "Fixed saved order" = "fixed"), exercise$settings$set_order),
          shiny::selectInput("maxdiff_item_order", "Items within each set", c("Seeded participant order" = "seeded", "Fixed saved order" = "fixed"), exercise$settings$item_order)),
        shiny::numericInput("maxdiff_seed", "Reproducible allocation seed", exercise$seed, 1, .Machine$integer.max, 1)),
      shiny::uiOutput("maxdiff_structure"),
      shiny::checkboxInput("maxdiff_fit", "Also fit aggregate paired MaxDiff utilities when identifiable", exercise$settings$analysis$fit_aggregate),
      shiny::p("Counts are always retained. Aggregate utilities weight each complete choice equally; they do not estimate individual preferences or participant-level uncertainty."),
      cmd("Check design coverage", "maxdiff_review"), shiny::uiOutput("maxdiff_review_output"),
      footer = shiny::tagList(if (!is.null(id)) cmd("Remove exercise", "maxdiff_delete"), cmd("Cancel", "maxdiff_cancel"), cmd("Save exercise", "maxdiff_save", "btn btn-primary"))))
  }
  output$maxdiff_structure <- shiny::renderUI({if (!isTRUE(draft$active)) return(NULL); brohn_maxdiff_structure_ui(draft$exercise, draft$token, draft$version)})
  output$maxdiff_review_output <- shiny::renderUI({if (!isTRUE(draft$active) || is.null(draft$reviewed)) return(NULL)
    shiny::tags$details(open = NA, shiny::tags$summary("Last checked draft coverage"), brohn_maxdiff_review_ui(draft$reviewed),
      shiny::p(class = "brohn-muted", "This review reflects the last Check design coverage command. Save validates the current form again."))})
  shiny::observeEvent(input$maxdiff_add, attempt(function() open_editor()))
  shiny::observeEvent(input$maxdiff_edit, attempt(function() open_editor(input$maxdiff_edit)))
  shiny::observeEvent(input$maxdiff_structure_command, attempt(function() {
    cmd <- input$maxdiff_structure_command; guard(cmd, TRUE); d <- capture_structure()
    action <- cmd$action; brohn_require(brohn_text(action, 30), "Choose an item/set action.")
    move <- function(values, at, direction) {brohn_require(brohn_number(direction, -1, 1, TRUE) && direction != 0 && !is.na(at) && at+direction >= 1L && at+direction <= length(values), "This item is already at the requested edge.")
      order <- seq_along(values); order[c(at, at+direction)] <- order[c(at+direction, at)]; values[order]}
    if (action == "add_item") {brohn_require(length(d$items) < 60L, "This profile supports at most 60 items."); d$items[[length(d$items)+1L]] <- list(id = brohn_id("md-item"), label = "")
    } else if (action == "remove_item") {brohn_require(!is.null(brohn_find(d$items, cmd$id)), "Choose an existing item.")
      brohn_require(!any(vapply(d$sets, function(s) cmd$id %in% unlist(s$item_ids), logical(1))), "Remove this item from every choice set first.")
      d$items <- Filter(function(i) !identical(i$id, cmd$id), d$items)
    } else if (action == "add_set") {brohn_require(length(d$sets) < 200L && length(d$items) >= 3L, "Add at least three items; this profile supports at most 200 sets.")
      d$sets[[length(d$sets)+1L]] <- list(id = brohn_id("md-set"), item_ids = as.list(head(brohn_ids(d$items), 3L)))
    } else if (action == "remove_set") {brohn_require(!is.null(brohn_find(d$sets, cmd$id)), "Choose an existing set."); d$sets <- Filter(function(s) !identical(s$id, cmd$id), d$sets)
    } else if (action == "move_set") {d$sets <- move(d$sets, match(cmd$id, brohn_ids(d$sets)), cmd$direction)
    } else if (action == "move_member") {at <- match(cmd$id, brohn_ids(d$sets)); brohn_require(!is.na(at), "Choose an existing set.")
      d$sets[[at]]$item_ids <- move(d$sets[[at]]$item_ids, match(cmd$item_id, unlist(d$sets[[at]]$item_ids)), cmd$direction)
    } else brohn_require(action == "refresh", "This item/set action is not supported.")
    draft$exercise <- d; draft$version <- draft$version+1L; draft$reviewed <- NULL
  }))
  close <- function() {draft$active <- FALSE; draft$reviewed <- NULL; shiny::removeModal()}
  shiny::observeEvent(input$maxdiff_cancel, attempt(function() {
    brohn_require(isTRUE(draft$active) && identical(input$maxdiff_cancel$token, draft$token), "This Cancel command belongs to an earlier best-worst editor."); close()
  }))
  shiny::observeEvent(input$maxdiff_review, attempt(function() {guard(input$maxdiff_review); draft$reviewed <- capture_framing(capture_structure())}))
  save_guard <- function(command) {guard(command); capture(); guard(command)}
  shiny::observeEvent(input$maxdiff_save, attempt(function() {
    save_guard(input$maxdiff_save); exercise <- capture_framing(capture_structure()); design <- current$study$body
    exercises <- brohn_default(design$maxdiff, list()); at <- match(exercise$id, brohn_ids(exercises))
    if (is.na(at)) exercises[[length(exercises)+1L]] <- exercise else exercises[[at]] <- exercise
    design$maxdiff <- exercises; update_study(design); close()
  }))
  shiny::observeEvent(input$maxdiff_delete, attempt(function() {
    save_guard(input$maxdiff_delete); design <- current$study$body
    design$maxdiff <- Filter(function(d) !identical(d$id, draft$exercise$id), brohn_default(design$maxdiff, list())); update_study(design); close()
  }))
  invisible(list(context = function() if (isTRUE(draft$active)) list(token = draft$token, version = draft$version, study_id = draft$study_id, exercise = draft$exercise) else NULL))
}
brohn_maxdiff_result_ui <- function(result,exercise_number=1L) {
  if (is.null(result)) return(NULL)
  brohn_require(identical(result$schema, "brohn-maxdiff-result/1.0") && identical(result$design_hash, brohn_hash(result$design)) &&
    identical(result$responses_hash, brohn_hash(result$exposures)), "The saved best-worst result does not match its retained design/response evidence.")
  quality <- result$quality; model <- result$model
  region_context<-paste0("Exercise ",exercise_number,": ",result$design$title)
  region_label<-function(label)paste(label,region_context,sep=" - ")
  brohn_card(title = paste("Best-worst choices:", result$design$title), subtitle = result$design$settings$prompt,
    shiny::p(paste0("Best: ", result$design$settings$best_label, ". Worst: ", result$design$settings$worst_label, ".")),
    shiny::p(paste(quality$answered_exposures, "complete choices;", quality$missing_exposures, "presented incomplete choices;",
      quality$exposure_records-quality$presented_exposures, "not presented;", quality$session_count, "source sessions.")),
    shiny::p(if (is.null(quality$participant_count)) "Unique people are unavailable: anonymous or mixed source codes do not establish participant linkage." else paste(quality$participant_count, "source-linked participant codes; this is a descriptive aggregate choice-weighted analysis.")),
    shiny::p("The exposure-adjusted score is (best - worst) divided by complete-pair exposures containing that item. Missing choices are shown separately; no eligible choices yields Unavailable."),
    brohn_maxdiff_plot_ui(result,"adjusted",exercise_number),
    brohn_table(lapply(result$items, function(i) list(item = i$label, best = i$best_count, worst = i$worst_count, presented = i$presented_exposures,
      complete_pair_denominator = i$answered_exposures, missing = i$missing_exposures, adjusted_score = i$exposure_adjusted_score)), maximum = 60L, label = region_label("Complete-pair counts and denominators")),
    if (identical(model$status, "estimated")) shiny::tagList(shiny::h3("Aggregate paired utilities"),
      shiny::p("Relative logit utilities sum to zero. Each complete pair has equal weight; more answered choices contribute more to the fit. Individual preferences and population confidence intervals are unavailable."),
      brohn_maxdiff_plot_ui(result,"utility",exercise_number),
      brohn_table(lapply(model$utilities, function(u) list(item = brohn_find(result$design$items, u$item_id)$label, utility = u$utility, unit = u$unit,
        standard_error = u$standard_error)), maximum = 60L, label = region_label("Saved aggregate paired MaxDiff utilities"))) else
      shiny::p(class = "brohn-alert brohn-alert-warning", paste("Aggregate utilities:", gsub("_", " ", model$status), "-", gsub("_", " ", brohn_default(model$reason, "No usable saved fit.")))),
    shiny::tags$details(shiny::tags$summary("Model, source and repeated-choice evidence"),
      shiny::p(paste(quality$repeated_set_exposures, "repeated set exposures within the same source participant-code/session tuple. These are retained choices, not extra independent people.")),
      if (length(model$diagnostics)) brohn_table(list(model$diagnostics), label = region_label("Saved model diagnostics")),
      if (length(model$parameters)) brohn_table(list(model$parameters), label = region_label("Saved model parameters")),
      shiny::p(paste("Design SHA-256:", result$design_hash)), shiny::p(paste("Response ledger SHA-256:", result$responses_hash)),
      if (!is.null(result$source)) brohn_table(list(result$source), label = region_label("Pinned best-worst source")),
      shiny::tags$ul(lapply(result$limitations, shiny::tags$li))),
    shiny::tags$details(shiny::tags$summary("Saved design coverage"), brohn_maxdiff_review_ui(result$design,region_context)))
}
