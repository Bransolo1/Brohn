# The researcher shell is deliberately separate from the participant renderer.
brohn_icon <- function(name, class = "") {
  allowed <- c("plan", "questions", "collect", "review", "results", "eye", "eeg",
    "eda", "heart", "breath", "emg", "camera", "face", "motion", "audio",
    "implicit", "aoi", "control", "clock", "link", "check", "warning", "info",
    "upload", "download", "play", "pause", "undo", "settings", "study",
    "compare", "spark")
  if (length(name) != 1L || is.na(name) || !name %in% allowed) {
    stop("Unknown Brohn icon.", call. = FALSE)
  }
  shiny::tags$svg(class = trimws(paste("brohn-icon", class)), viewBox = "0 0 24 24",
    `aria-hidden` = "true", focusable = "false",
    shiny::tags$use(href = paste0("brand/icons.svg#brohn-", name)))
}

brohn_badge <- function(text, tone = "neutral") {
  tone <- match.arg(tone, c("neutral", "success", "warning", "error", "info", "lavender"))
  shiny::span(class = paste("brohn-badge", paste0("brohn-badge-", tone)), text)
}

brohn_card <- function(..., title = NULL, subtitle = NULL, actions = NULL, class = NULL) {
  shiny::div(class = trimws(paste("brohn-card", class)),
    if (!is.null(title) || !is.null(subtitle) || !is.null(actions)) {
      shiny::div(class = "brohn-card-heading",
        shiny::div(
          if (!is.null(title)) shiny::h2(class = "brohn-card-title", title),
          if (!is.null(subtitle)) shiny::p(class = "brohn-muted", subtitle)),
        actions)
    },
    ...)
}

brohn_empty <- function(title, text, action = NULL) {
  shiny::div(class = "brohn-empty",
    shiny::tags$img(src = "brand/empty-study.svg", alt = "", `aria-hidden` = "true",
      class = "brohn-empty-art"),
    shiny::h2(title), shiny::p(class = "brohn-muted", text), action)
}

brohn_page <- function(title, subtitle = NULL, ..., actions = NULL) {
  shiny::div(class = "brohn-page",
    shiny::div(class = "brohn-page-heading",
      shiny::div(class = "brohn-page-intro", shiny::h1(title),
        if (!is.null(subtitle)) shiny::p(class = "brohn-page-subtitle", subtitle)),
      if (!is.null(actions)) shiny::div(class = "brohn-page-actions", actions)),
    ...)
}

brohn_shell_ui <- function() {
  nav_button <- function(id, label, icon, current = FALSE) {
    shiny::actionButton(paste0("nav_", id),
      label = shiny::tagList(brohn_icon(icon), shiny::span(label)),
      class = "brohn-nav-button", `data-page` = id,
      `aria-current` = if (current) "page" else NULL)
  }
  shiny::fluidPage(title = "Brohn - Research workspace", lang = "en",
    theme = bslib::bs_theme(version = 5),
    shiny::tags$head(
      shiny::tags$link(rel = "icon", type = "image/svg+xml", href = "brand/brohn-app-icon.svg"),
      shiny::tags$link(rel = "stylesheet", href = "brand/tokens.css"),
      shiny::tags$link(rel = "stylesheet", href = "brohn.css"),
      shiny::tags$script(src = "platform-ui.js", defer = NA),
      shiny::tags$script(src = "platform-aoi.js", defer = NA)),
    shiny::div(class = "brohn-app",
      shiny::tags$a(href = "#brohn-main", class = "brohn-skip-link", "Skip to main content"),
      shiny::div(class = "brohn-shell",
        shiny::tags$aside(class = "brohn-sidebar", `aria-label` = "Workspace navigation",
          shiny::tags$header(class = "brohn-brand",
            shiny::tags$img(src = "brand/brohn-lockup.svg", alt = "Brohn", width = "130", height = "38"),
            shiny::p("Research, connected.")),
          shiny::tags$nav(class = "brohn-primary-nav", `aria-label` = "Primary",
            nav_button("home", "Home", "spark", TRUE),
            nav_button("studies", "Studies", "study"),
            nav_button("datasets", "Data library", "collect"),
            nav_button("designs", "Design library", "plan"),
            nav_button("activity", "Activity", "clock"),
            nav_button("settings", "Settings", "settings")),
          shiny::div(class = "brohn-sidebar-foot",
            shiny::p("A question. A study. Understanding."))),
        shiny::div(class = "brohn-workspace",
          shiny::tags$header(class = "brohn-topbar", role = "banner",
            shiny::span(class = "brohn-workspace-label", "Research workspace"),
            shiny::div(class = "brohn-status", role = "status", `aria-live` = "polite",
              `aria-atomic` = "true", shiny::textOutput("platform_status", inline = TRUE))),
          shiny::tags$main(id = "brohn-main", class = "brohn-main", tabindex = "-1",
            shiny::uiOutput("platform_error"),
            shiny::uiOutput("service_health"),
            shiny::uiOutput("platform_content"))))))
}
