brohn_tasks_ui <- function(design) {
  profiles <- brohn_task_profiles()
  choices <- setNames(names(profiles), vapply(profiles, `[[`, character(1), "label"))
  shiny::tagList(brohn_maxdiff_summary_ui(design), brohn_card(title = "Implicit and reaction-time tasks", subtitle = "Each task uses a named procedure with its own trial structure and scoring rules. Timed tasks run after the stimulus sequence, followed by best-worst exercises and end-of-study questions.",
    shiny::selectInput("task_profile", "Research procedure", choices), shiny::actionButton("add_task", "Add procedure", class = "btn-primary")),
    if (!length(design$blocks)) brohn_empty("A procedure that fits your question", "Choose a task, review the target/control relationship, and replace demonstration materials before research use."),
    lapply(seq_along(design$blocks), function(i) {
      task <- design$blocks[[i]]; profile <- brohn_task_profile(task$profile)
      brohn_card(title = task$title, subtitle = paste(profile$label, "\u00b7", sum(profile$trial_counts), "trials"),
        actions = brohn_command(paste("Remove", task$title), "remove_task", task$id),
        shiny::textInput(paste0("task_title_", i), paste("Task", i, "name"), task$title),
        shiny::p(profile$scoring),
        shiny::selectInput(paste0("task_origin_", i), paste("Task", i, "materials"), c("Original demonstration / synthetic" = "synthetic", "Researcher-supplied and reviewed" = "researcher_supplied"), task$origin),
        shiny::textAreaInput(paste0("task_control_", i), paste("Task", i, "comparison and control rationale"), task$settings$control_rationale, rows = 3),
        shiny::textAreaInput(paste0("task_rights_", i), paste("Task", i, "materials provenance and permission"), task$materials_rights, rows = 2),
        if (length(task$categories)) lapply(seq_along(task$categories), function(j) {
          category <- task$categories[[j]]
          indices <- which(vapply(task$materials, function(m) identical(m$category_id, category$id), logical(1)))
          shiny::tags$details(open = NA, shiny::tags$summary(paste(gsub("_", " ", category$role), "\u2014", category$label)),
            shiny::textInput(paste0("task_category_", i, "_", j), paste("Task", i, "category", j, "label"), category$label),
            lapply(indices, function(k) {
              material <- task$materials[[k]]
              shiny::div(class = "brohn-material-exemplar-card",
                if (material$type == "text") shiny::textInput(paste0("task_material_", i, "_", k), paste("Task", i, "exemplar", k), material$content) else
                  shiny::h3(paste("Exemplar", k)),
                brohn_material_card_ui(design, "exemplar", material, task$id))
            }))
        }),
        shiny::tags$details(shiny::tags$summary("Timing and randomization"),
          shiny::numericInput(paste0("task_seed_", i), paste("Task", i, "seed"), task$seed, 1, .Machine$integer.max),
          shiny::numericInput(paste0("task_interval_", i), paste("Task", i, "intertrial interval (ms)"), task$settings$intertrial_ms, 100, 2000, 50),
          shiny::numericInput(paste0("task_timeout_", i), paste("Task", i, "timeout (ms)"), task$settings$trial_timeout_ms, 1000, 60000, 100),
          shiny::p("Browser-observed timing is retained with first responses and corrections. Interrupted timed tasks are not replayed or silently rescored.")))
    }))
}
