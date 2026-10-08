# Current reference guidance only. This component never changes a protocol,
# assesses the user's settings, runs an analysis or rewrites historical evidence.
.brohn_me_source_link <- function(url, title) {
  if (!is.character(url) || length(url) != 1L || is.na(url) ||
      !grepl("^https://[^[:space:]<>]+$", url)) return(NULL)
  shiny::tags$a(href = url, target = "_blank", rel = "noopener noreferrer", title)
}
.brohn_me_review_label <- function(value) {
  labels <- c(discovered = "Located; supporting text not yet reviewed",
    screened = "References screened; applicability still under review",
    full_text_reviewed = "Supporting text reviewed; applicability needs a separate decision",
    applicability_reviewed = "Applicability review recorded; qualification is separate",
    disputed = "Evidence is disputed", superseded = "Historical guidance; superseded")
  if (is.character(value) && length(value) == 1L && value %in% names(labels))
    unname(labels[[value]]) else "Review status unavailable"
}
.brohn_me_depth_label <- function(value) {
  labels <- c(bibliographic_only = "Bibliographic record only", abstract_screened = "Abstract screened",
    selected_sections_screened = "Selected sections screened", full_text_reviewed = "Full text reviewed")
  if (is.character(value) && length(value) == 1L && value %in% names(labels))
    unname(labels[[value]]) else "See the recorded review scope"
}
brohn_method_evidence_ui <- function(registry, method_ref, original_source = NULL) {
  model <- if (is.null(registry)) NULL else brohn_method_evidence_cards(registry, method_ref)
  if (is.null(model) || !length(model$cards)) return(shiny::div(class = "brohn-method-evidence",
    shiny::p("Method evidence is still being linked for this exact procedure."),
    shiny::tags$details(shiny::tags$summary("Procedure reference and review status"),
      shiny::p("A procedure reference describes its source. It does not establish that every Brohn setting or consumer use has been validated."),
      .brohn_me_source_link(original_source, "Open the procedure's original reference"),
      shiny::p(class = "brohn-muted", "No option-level evidence entry is available for this exact version."),
      shiny::tags$code(method_ref))))

  shiny::div(class = "brohn-method-evidence",
    shiny::p("Method evidence is under review. Check the assumptions before interpreting a result."),
    shiny::tags$details(shiny::tags$summary("Why this method? Sources and limits"),
      shiny::p(class = "brohn-muted", "Current guidance for this exact procedure version. These notes are not an evidence snapshot saved with this study."),
      lapply(model$cards, function(card) shiny::tags$section(class = "brohn-method-evidence-claim",
        shiny::h3(card$title), shiny::p(card$statement),
        shiny::p(shiny::strong("Research question: "), card$question),
        shiny::p(shiny::strong("Measured quantity: "), card$observed_quantity),
        shiny::p(shiny::strong("Outcome: "), card$estimand),
        shiny::p(shiny::strong("Review: "), .brohn_me_review_label(card$review$state)),
        if (length(card$nonclaims)) shiny::tags$ul(lapply(card$nonclaims, shiny::tags$li)),
        if (length(card$context$prerequisites)) shiny::tagList(shiny::h4("Requirements to consider"),
          shiny::tags$ul(lapply(card$context$prerequisites, shiny::tags$li))),
        if (length(card$gaps)) shiny::tagList(shiny::h4("Evidence still needed"),
          shiny::tags$ul(lapply(card$gaps, shiny::tags$li))),
        shiny::h4("Academic sources"),
        shiny::tags$ol(lapply(card$sources, function(link) shiny::tags$li(
          .brohn_me_source_link(link$source$url, link$source$title),
          shiny::p(class = "brohn-muted", paste0(link$source$authors, " (", link$source$year, ").")),
          shiny::p(link$contribution), shiny::p(shiny::strong("Limits: "), link$limits),
          shiny::p(class = "brohn-muted", paste(.brohn_me_depth_label(link$depth), link$locator, sep = ". "))))),
        shiny::p(class = "brohn-muted", card$independence$detail),
        shiny::tags$details(shiny::tags$summary("Exact option and evidence scope"),
          shiny::p("This describes the documented implementation, not an assessment of your study's chosen settings."),
          shiny::p(shiny::tags$code(card$binding$option_path)),
          shiny::p(card$binding$admission),
          shiny::p(shiny::tags$code(paste(unlist(card$method_refs), collapse = ", ")))))),
      .brohn_me_source_link(original_source, "Original procedure reference")))
}
