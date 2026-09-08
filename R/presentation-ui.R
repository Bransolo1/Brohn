presentation_preview_ui <- function(study) {
  sequences <- preview_presentation(study)
  shiny::div(class = "panel", shiny::span(class = "eyebrow", "PRESENTATION PLAN - PREVIEW ONLY"),
    shiny::h2("See the order before anyone takes part."),
    shiny::p(if (length(sequences) == 2) "Plan both orders: one starts with A and the other with B. Participant allocation has not been implemented." else
      "This plan uses a fixed order. Consider whether seeing one design first could influence the comparison."),
    shiny::div(class = "future-grid", lapply(names(sequences), function(name) {
      rows <- sequences[[name]]
      shiny::div(class = "sequence-card", shiny::h3(paste("Order", name)),
        shiny::tags$ol(lapply(seq_len(nrow(rows)), function(i) {
          row <- rows[i, ]
          shiny::tags$li(if (row$phase == "passive_viewing")
            paste("View design", row$condition, paste0("(", row$role, ")"), "for", row$planned_duration_ms / 1000, "seconds") else
              paste("Answer liking question about design", row$condition, "at the participant's pace"))
        })))
    })),
    shiny::p(class = "muted", "This is a plan, not a running session. Actual exposure timing, order assignment and device checks must be implemented and verified before recording."))
}
