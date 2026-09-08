# Section editor draft operations preserve complete groups and validate before
# exposing a new state. Saving remains the application's revision-CAS operation.
brohn_sections_editor_change <- function(design, command) {
  brohn_require(is.list(command) && brohn_text(command$op, 60), "Choose a section editing action.")
  result <- design
  if (command$op == "enable") {
    result$questionnaire_sections <- brohn_question_sections_new(result)
  } else if (command$op == "flat") {
    result$questionnaire_sections <- NULL
  } else {
    brohn_validate_question_sections(result$questionnaire_sections, result)
    sections <- result$questionnaire_sections$sections
    si <- match(command$section_id, brohn_ids(sections))
    brohn_require(length(si) == 1L && !is.na(si), "Select a current section.")
    section <- sections[[si]]
    gi <- if (!is.null(command$group_id)) match(command$group_id, brohn_ids(section$groups)) else NA_integer_
    if (command$op %in% c("group_fields", "move_group", "transfer_group", "new_section", "scope"))
      brohn_require(length(gi) == 1L && !is.na(gi), "Select a current complete question group.")
    if (command$op %in% c("section_fields", "group_fields")) {
      brohn_require(brohn_text(command$label, 240) && brohn_text(command$placement, 40) && command$placement %in% c("fixed", "shuffle"),
        "Name the selected section/group and choose fixed or varying placement.")
      if (command$op == "section_fields") {sections[[si]]$label <- command$label; sections[[si]]$placement <- command$placement} else {
        sections[[si]]$groups[[gi]]$label <- command$label; sections[[si]]$groups[[gi]]$placement <- command$placement
      }
    } else if (command$op == "move_section") {
      brohn_require(brohn_number(command$direction) && command$direction %in% c(-1, 1), "Choose an adjacent section direction.")
      same <- which(vapply(sections, function(s) s$scope == section$scope, logical(1)))
      next_position <- match(si, same)+command$direction
      brohn_require(next_position %in% seq_along(same), "This section has no neighbour in that direction at this placement.")
      other <- same[[next_position]]; sections[c(si, other)] <- sections[c(other, si)]
    } else if (command$op == "move_group") {
      brohn_require(brohn_number(command$direction) && command$direction %in% c(-1, 1), "Choose an adjacent group direction.")
      other <- gi+command$direction
      brohn_require(other %in% seq_along(section$groups), "This group has no neighbour in that direction.")
      sections[[si]]$groups[c(gi, other)] <- sections[[si]]$groups[c(other, gi)]
    } else if (command$op %in% c("transfer_group", "new_section", "scope")) {
      group <- section$groups[[gi]]; sections[[si]]$groups <- sections[[si]]$groups[-gi]
      if (command$op == "transfer_group") {
        target <- match(command$target_id, brohn_ids(sections))
        brohn_require(length(target) == 1L && !is.na(target) && target != si && identical(sections[[target]]$scope, section$scope),
          "Choose another section at the same assessment placement.")
        sections[[target]]$groups[[length(sections[[target]]$groups)+1L]] <- group
      } else if (command$op == "new_section") {
        brohn_require(brohn_text(command$label, 240), "Give the new section a name.")
        added <- list(id = brohn_id("qsection"), label = command$label, scope = section$scope, placement = "fixed", groups = list(group))
        sections <- append(sections, list(added), after = si)
      } else {
        brohn_require(brohn_text(command$scope, 40) && command$scope %in% c("before", "after_each", "end") && !identical(command$scope, section$scope),
          "Choose a different assessment placement for the complete group.")
        ids <- unlist(group$question_ids, use.names = FALSE)
        result$questions <- lapply(result$questions, function(q) {if (q$id %in% ids) q$scope <- command$scope; q})
        if (!is.null(result$scales)) result$scales <- lapply(result$scales, function(scale) {
          items <- vapply(scale$items, `[[`, character(1), "question_id")
          if (any(items %in% ids)) {
            brohn_require(all(items %in% ids), paste("Move every item in scale", scale$label, "together."))
            scale$scope <- command$scope
          }; scale
        })
        targets <- which(vapply(sections, function(s) s$scope == command$scope && length(s$groups) > 0L, logical(1)))
        group$placement <- "fixed"
        if (length(targets) && identical(sections[[tail(targets, 1L)]]$placement, "fixed")) {
          target <- tail(targets, 1L); sections[[target]]$groups[[length(sections[[target]]$groups)+1L]] <- group
        } else sections[[length(sections)+1L]] <- list(id = brohn_id("qsection"), label = .brohn_sections_label(command$scope),
          scope = command$scope, placement = "fixed", groups = list(group))
      }
      sections <- Filter(function(s) length(s$groups) > 0L, sections)
    } else brohn_stop("Unsupported section editing action.")
    result$questionnaire_sections$sections <- sections
  }
  tryCatch(.brohn_sections_source(result), error = function(e) {
    if (identical(command$op, "scope")) brohn_stop(paste0("Cannot move group '", group$label, "' to ",
      .brohn_sections_label(command$scope), ": ", conditionMessage(e),
      " Keep its current placement, or revise the dependent display logic/scale design first."))
    stop(e)
  })
  if ("questionnaire_sections" %in% names(result)) brohn_validate_question_sections(result$questionnaire_sections, result)
  result
}

brohn_question_sections_ui <- function(design) {
  enabled <- "questionnaire_sections" %in% names(design)
  config <- design$questionnaire_sections
  shiny::div(class = "brohn-card", shiny::h2("Questionnaire sections"),
    shiny::singleton(shiny::tags$script(src = "question-sections-ui.js")),
    shiny::p(if (enabled) "Named groups keep related questions together. Fixed positions and participant variation are saved with each release." else
      "Organise related questions into sections. Enabling preserves the current order and keeps dependent follow-ups and scale items together."),
    if (enabled) shiny::tags$ul(lapply(config$sections, function(s) shiny::tags$li(shiny::strong(s$label),
      paste0(" \u2014 ", .brohn_sections_label(s$scope), "; ", length(s$groups), " groups; ", if (s$placement == "fixed") "fixed section position" else "varies across eligible positions")))),
    brohn_command(if (enabled) "Edit questionnaire sections" else "Enable questionnaire sections", "question_sections_open",
      list(study_id = design$id, design_hash = brohn_hash(design))))
}

brohn_install_question_sections_ui <- function(input, output, session, current, state, capture, update_study, attempt, message) {
  edit <- shiny::reactiveValues(active = FALSE, design = NULL, editor_id = NULL, version = 0L,
    study_id = NULL, base_hash = NULL, base_revision = NULL, section_id = NULL, group_id = NULL, error = NULL)
  context <- function() list(editor_id = edit$editor_id, version = edit$version)
  selected <- function() {
    section <- brohn_find(edit$design$questionnaire_sections$sections, edit$section_id)
    list(section = section, group = if (is.null(section) || is.null(edit$group_id)) NULL else brohn_find(section$groups, edit$group_id))
  }
  identity <- function() {
    node <- selected(); paste(edit$editor_id, edit$version, edit$section_id, brohn_default(edit$group_id, ""),
      brohn_hash(if (is.null(node$group)) node$section else node$group), sep = ":")
  }
  guard <- function(command = NULL, source = TRUE) {
    brohn_require(isTRUE(edit$active), "Reopen the questionnaire section editor.")
    if (!is.null(command)) brohn_require(is.list(command) && identical(command$editor_id, edit$editor_id) &&
      brohn_number(command$version, 0, 1e9, TRUE) && command$version == edit$version, "The section draft changed. Use its current controls.")
    if (source) brohn_require(!is.null(current$study) && identical(current$study$id, edit$study_id) &&
      identical(current$study$revision, edit$base_revision) && identical(brohn_hash(current$study$body), edit$base_hash) && !isTRUE(current$study$body$archived),
      "The underlying study changed. Cancel and reopen sections for its latest revision.")
    if (source) brohn_require(identical(state$page, "study") && identical(state$stage, "Questions") &&
      identical(input$study_form_identity, paste(edit$study_id, "Questions", sep = ":")), "Return to this study's current Questions page before editing sections.")
  }
  execute <- function(fn) attempt(function() {
    edit$error <- NULL
    tryCatch(fn(), error = function(e) {edit$error <- conditionMessage(e); stop(e)})
  })
  set_design <- function(design) {
    edit$design <- design; edit$version <- edit$version+1L
    sections <- design$questionnaire_sections$sections
    # Track a transferred group's actual new parent, including generated sections.
    if (!is.null(edit$group_id)) {
      matches <- Filter(function(s) edit$group_id %in% brohn_ids(s$groups), sections)
      if (length(matches)) edit$section_id <- matches[[1L]]$id else edit$group_id <- NULL
    }
    if (is.null(brohn_find(sections, edit$section_id))) {edit$section_id <- if (length(sections)) sections[[1L]]$id else NULL; edit$group_id <- NULL}
  }
  apply_form <- function(required = TRUE, commit = TRUE, form = NULL) {
    node <- selected(); if (is.null(node$section)) return(edit$design)
    fields <- if (is.null(form)) list(node_identity = input$sections_node_identity,
      label = input$sections_label, placement = input$sections_placement) else form
    bound <- identical(fields$node_identity, identity())
    if (!required && !bound) return(edit$design)
    brohn_require(bound, "The selected group changed. Wait for its current fields before applying changes.")
    item <- if (is.null(node$group)) node$section else node$group
    result <- edit$design
    if (!identical(fields$label, item$label) || !identical(fields$placement, item$placement)) {
      result <- brohn_sections_editor_change(result, list(op = if (is.null(node$group)) "section_fields" else "group_fields",
        section_id = node$section$id, group_id = if (is.null(node$group)) NULL else node$group$id, label = fields$label, placement = fields$placement))
      if (commit) set_design(result)
    }
    result
  }
  candidate <- function(command) tryCatch({brohn_sections_editor_change(edit$design, command); NULL}, error = conditionMessage)
  action <- function(label, command) {
    error <- candidate(command)
    if (is.null(error)) brohn_command(label, "sections_action", c(context(), command)) else
      shiny::div(shiny::tags$button(type = "button", class = "btn btn-outline-secondary", disabled = "disabled", label),
        shiny::p(class = "brohn-muted", paste(label, "unavailable:", error)))
  }
  shiny::observeEvent(input$question_sections_open, execute(function() {
    command <- input$question_sections_open; capture()
    brohn_require(!is.null(current$study) && !isTRUE(current$study$body$archived) && is.list(command) &&
      identical(command$study_id, current$study$id) && identical(command$design_hash, brohn_hash(current$study$body)),
      "The question form changed. Open sections from the current saved study.")
    brohn_require(identical(state$page, "study") && identical(state$stage, "Questions") &&
      identical(input$study_form_identity, paste(current$study$id, "Questions", sep = ":")), "Open sections from this study's current Questions page.")
    d <- current$study$body
    edit$active <- TRUE; edit$editor_id <- brohn_id("sections-editor"); edit$version <- 0L
    edit$study_id <- d$id; edit$base_hash <- brohn_hash(d); edit$base_revision <- current$study$revision
    edit$design <- if ("questionnaire_sections" %in% names(d)) d else brohn_sections_editor_change(d, list(op = "enable"))
    sections <- edit$design$questionnaire_sections$sections
    edit$section_id <- if (length(sections)) sections[[1L]]$id else NULL; edit$group_id <- NULL
    shiny::showModal(shiny::modalDialog(title = "Questionnaire sections", size = "l", easyClose = FALSE,
      shiny::p("Edit this draft, then Save. Move complete groups to preserve follow-ups and scale order. Existing participant releases keep their original layout."),
      shiny::uiOutput("sections_editor_error"), shiny::uiOutput("sections_editor_tree"), shiny::uiOutput("sections_editor_node"),
      footer = shiny::uiOutput("sections_editor_footer")))
  }))
  shiny::observeEvent(input$sections_select, execute(function() {
    command <- input$sections_select; guard(command)
    section <- brohn_find(edit$design$questionnaire_sections$sections, command$section_id)
    brohn_require(!is.null(section) && (is.null(command$group_id) || !is.null(brohn_find(section$groups, command$group_id))), "Select a current section or group.")
    apply_form(FALSE)
    edit$section_id <- command$section_id; edit$group_id <- command$group_id; edit$version <- edit$version+1L
  }))
  shiny::observeEvent(input$sections_apply, execute(function() {guard(input$sections_apply); apply_form(); message("Section fields updated in the draft.")}))
  shiny::observeEvent(input$sections_action, execute(function() {
    command <- input$sections_action; guard(command)
    bound_action <- command$op %in% c("new_section", "transfer_group")
    if (bound_action) {
      brohn_require(is.list(command$form) && identical(command$node_identity, identity()) &&
        identical(command$form$node_identity, identity()) && identical(command$section_id, edit$section_id) &&
        !is.null(edit$group_id) && identical(command$group_id, edit$group_id),
        "The selected group changed. Use the name and destination fields for the current group.")
      if (command$op == "new_section") command$label <- command$form$new_label else command$target_id <- command$form$target_id
    }
    prepared <- apply_form(bound_action, commit = FALSE, form = if (bound_action) command$form else NULL)
    set_design(brohn_sections_editor_change(prepared, command)); message("Questionnaire layout updated in the draft.")
  }))
  shiny::observeEvent(input$sections_cancel, execute(function() {
    brohn_require(isTRUE(edit$active) && is.list(input$sections_cancel) && identical(input$sections_cancel$editor_id, edit$editor_id),
      "Choose Cancel from the current section editor.")
    edit$active <- FALSE; edit$editor_id <- NULL; shiny::removeModal(); message("Questionnaire section draft discarded.")
  }))
  shiny::observeEvent(input$sections_save, execute(function() {
    guard(input$sections_save); prepared <- apply_form(commit = FALSE); capture(); guard()
    update_study(prepared); edit$active <- FALSE; edit$editor_id <- NULL; shiny::removeModal(); message("Questionnaire sections saved in a new study revision.")
  }))
  output$sections_editor_error <- shiny::renderUI({if (!is.null(edit$error)) shiny::div(class = "brohn-alert brohn-alert-error", role = "alert", edit$error)})
  output$sections_editor_footer <- shiny::renderUI({shiny::req(edit$active); shiny::tagList(
    brohn_command("Cancel", "sections_cancel", context()), brohn_command("Save questionnaire sections", "sections_save", context(), "btn btn-primary"))})
  output$sections_editor_tree <- shiny::renderUI({
    shiny::req(edit$active); sections <- edit$design$questionnaire_sections$sections
    shiny::tagList(shiny::p(role = "status", paste("Draft version", edit$version, "\u2014", length(sections), "sections.")),
      if (!"questionnaire_sections" %in% names(edit$design)) shiny::p("Flat order selected: questions will use the saved question-list order within each placement.") else
        if (!length(sections)) shiny::p("No questions yet. Save this empty layout, then add questions to create fixed groups."),
      shiny::tags$ol(lapply(sections, function(s) shiny::tags$li(
        brohn_command(paste(s$label, "\u2014", .brohn_sections_label(s$scope)), "sections_select", c(context(), list(section_id = s$id, group_id = NULL))),
        shiny::p(if (s$placement == "fixed") "Fixed section position" else "Varies among eligible section positions"),
        shiny::tags$ol(lapply(s$groups, function(g) shiny::tags$li(
          brohn_command(g$label, "sections_select", c(context(), list(section_id = s$id, group_id = g$id))),
          shiny::p(if (g$placement == "fixed") "Fixed group position; member order stays fixed" else "Varies among eligible group positions; member order stays fixed"),
          shiny::tags$ol(lapply(g$question_ids, function(id) shiny::tags$li(brohn_find(edit$design$questions, id)$prompt))))))))),
      if ("questionnaire_sections" %in% names(edit$design)) action("Use flat question order instead", list(op = "flat")) else action("Enable sections in this draft", list(op = "enable")))
  })
  output$sections_editor_node <- shiny::renderUI({
    shiny::req(edit$active); node <- selected(); if (is.null(node$section)) return(NULL)
    section <- node$section; group <- node$group; item <- if (is.null(group)) section else group
    base <- list(section_id = section$id, group_id = if (is.null(group)) NULL else group$id)
    move <- function(direction) c(base, list(op = if (is.null(group)) "move_section" else "move_group", direction = direction))
    targets <- Filter(function(s) s$scope == section$scope && s$id != section$id, edit$design$questionnaire_sections$sections)
    scopes <- setdiff(c("before", "after_each", "end"), section$scope)
    shiny::div(class = "brohn-card", shiny::h3(if (is.null(group)) "Selected section" else "Selected question group"),
      shiny::div(style = "display:none", shiny::textInput("sections_node_identity", NULL, identity())),
      shiny::textInput("sections_label", "Name", item$label),
      shiny::selectInput("sections_placement", "Position policy", c("Keep this position fixed" = "fixed", "Vary among eligible positions" = "shuffle"), item$placement),
      shiny::p("Variation is deterministic per participant. Fixed slots remain in place; equal position counts are not guaranteed."),
      brohn_command("Apply name and position", "sections_apply", context()),
      shiny::div(class = "brohn-toolbar", action("Move up", move(-1L)), action("Move down", move(1L))),
      if (!is.null(group)) shiny::tagList(
        shiny::p(paste("Move all", length(group$question_ids), "questions together. Their internal order stays unchanged.")),
        if (length(targets)) shiny::tagList(shiny::selectInput("sections_target", "Move to section at this placement", setNames(brohn_ids(targets), vapply(targets, `[[`, character(1), "label"))),
          shiny::uiOutput("sections_transfer_control")),
        shiny::textInput("sections_new_label", "New section name", paste(group$label, "section")),
        shiny::uiOutput("sections_new_control"),
        shiny::p("Moving placement changes every member question and its contained scale assessment placement. The group becomes a fixed group at the end of that placement. Existing releases stay unchanged."),
        lapply(scopes, function(scope) action(paste("Move whole group to", .brohn_sections_label(scope)), c(base, list(op = "scope", scope = scope))))))
  })
  output$sections_transfer_control <- shiny::renderUI({
    shiny::req(edit$active); node <- selected(); shiny::req(!is.null(node$group))
    brohn_command("Move group to section", "sections_action", c(context(), list(op = "transfer_group",
      section_id = node$section$id, group_id = node$group$id, node_identity = identity())), `data-brohn-sections-form` = "true")
  })
  output$sections_new_control <- shiny::renderUI({
    shiny::req(edit$active); node <- selected(); shiny::req(!is.null(node$group))
    brohn_command("Create section from this group", "sections_action", c(context(), list(op = "new_section",
      section_id = node$section$id, group_id = node$group$id, node_identity = identity())), `data-brohn-sections-form` = "true")
  })
  invisible(list(context = shiny::reactive(c(context(), list(active = edit$active, study_id = edit$study_id,
    base_hash = edit$base_hash, base_revision = edit$base_revision, section_id = edit$section_id, group_id = edit$group_id,
    node_identity = if (edit$active) identity() else NULL, error = edit$error))), design = shiny::reactive(edit$design)))
}
