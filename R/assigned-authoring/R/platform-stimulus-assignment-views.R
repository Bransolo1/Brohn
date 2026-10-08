# Research decisions in Plan; runtime/profile selection remains an app concern.
brohn_stimulus_assignment_ui <- function(design) {
  a <- design$stimulus_assignment
  grouped <- if (is.null(a)) character() else unlist(lapply(a$sets, function(s)
    vapply(s$members, `[[`, character(1), "stimulus_id")), use.names = FALSE)
  available <- Filter(function(s) !s$id %in% grouped, design$stimuli)
  labels <- function(ids) vapply(ids, function(id) brohn_find(design$stimuli, id)$title, character(1))
  shiny::tagList(brohn_card(title = "Who sees each version?",
    subtitle = "Group alternatives explicitly. Stimuli outside groups are shown to every participant, including any shared control.",
    if (identical(design$schema_version, "brohn-design/1.2.0") &&
        (!is.null(design$camera) || !is.null(design$participant_equipment)))
      shiny::div(class = "brohn-alert brohn-alert-warning",
        shiny::p(shiny::strong("Review participant setup before publishing")),
        shiny::p("Versioned studies cannot yet collect camera recordings or run participant equipment checks. Your saved requirements are retained."),
        shiny::p("If this study does not need those features, explicitly turn them off in participant setup. Keep any checks required by your research design."),
        brohn_command("Review participant setup", "edit_camera_policy", design$id)),
    if (is.null(a)) shiny::p("Every participant currently sees every saved stimulus once.") else shiny::tagList(
      if (length(available)) shiny::p(shiny::strong("Everyone sees: "), paste(vapply(available, `[[`, character(1), "title"), collapse = "; ")),
      lapply(a$sets, function(s) shiny::div(class = "brohn-subsection",
        shiny::h3(s$label), shiny::p(if (s$selection == "all") "Everyone sees all versions in this group." else "Each participant sees one version in this group."),
        shiny::tags$ul(lapply(s$members, function(m) shiny::tags$li(labels(m$stimulus_id)))),
        if (s$selection == "one") shiny::p(class = "brohn-muted", "Use Add version on a member stimulus to extend this group."))),
      if (length(a$arms)) shiny::tags$details(shiny::tags$summary(paste("Review", length(a$arms), "complete participant assignments")),
        shiny::p(if (a$allocation == "blocked-arm-sha256/0.1")
          "Each complete enrollment block allocates all groups once in a reproducibly shuffled order. Dropout can leave completed groups unequal." else
          "Each enrollment independently selects a reproducible group. Equal group sizes are not guaranteed."),
        shiny::tags$ol(lapply(a$arms, function(arm) shiny::tags$li(paste(labels(vapply(arm$choices, `[[`, character(1), "stimulus_id")), collapse = " + ")))))),
    if (length(available) >= 2L) shiny::tagList(
      shiny::textInput("stimulus_group_label", "Version group name", "Packaging alternatives"),
      shiny::checkboxGroupInput("stimulus_group_members", "Stimuli in this group",
        stats::setNames(brohn_ids(available), vapply(available, `[[`, character(1), "title"))),
      shiny::selectInput("stimulus_group_selection", "For each participant",
        c("Show all versions" = "all", "Show one version" = "one"), selected = "all", selectize = FALSE),
      if (is.null(a) || !length(a$arms)) shiny::conditionalPanel("input.stimulus_group_selection === 'one'",
        shiny::selectInput("stimulus_group_allocation", "Assign participants to versions",
          c("Balanced shuffled enrollment blocks" = "blocked-arm-sha256/0.1", "Independent random assignment" = "arm-sha256/0.1"), selectize = FALSE)),
      shiny::p(class = "brohn-muted", "A new show-one group combines with the existing assignments. Paired comparisons require both comparison conditions within every assignment."),
      brohn_command("Save version group", "save_stimulus_group", list(study_id = design$id,
        design_hash = brohn_hash(design)), class = "btn btn-primary")) else
      shiny::p(class = "brohn-muted", "Add at least two ungrouped stimuli to create another version group.")))
}

brohn_install_stimulus_assignment <- function(input, output, session, current, state, capture, update_study, attempt, message) {
  shiny::observeEvent(input$save_stimulus_group, attempt(function() {
    command <- input$save_stimulus_group
    brohn_fields(command, c("study_id", "design_hash"), label = "Version group action")
    brohn_require(identical(state$page, "study") && identical(state$stage, "Plan") &&
      !is.null(current$study) && identical(command$study_id, current$study$id) &&
      identical(input$study_form_identity, paste(current$study$id, "Plan", sep = ":")) &&
      identical(command$design_hash, brohn_hash(current$study$body)), "Reopen the current Plan before saving a version group.")
    capture()
    design <- brohn_group_stimuli(current$study$body, input$stimulus_group_members,
      input$stimulus_group_label, input$stimulus_group_selection,
      brohn_default(input$stimulus_group_allocation, "blocked-arm-sha256/0.1"))
    update_study(design); message("Version group saved. Review who sees each version before releasing the study.")
  }), ignoreInit = TRUE)
  invisible(TRUE)
}
