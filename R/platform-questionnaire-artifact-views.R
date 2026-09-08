brohn_questionnaire_artifact_preview_ui <- function(analysis) {
  if (!brohn_questionnaire_is_artifact(analysis)) return(NULL)
  counts <- analysis$questionnaire_artifact$counts; preview <- analysis$preview
  shiny::tagList(
    brohn_card(title = "Complete questionnaire results", subtitle = "The full analysis is saved in a verified evidence file.",
      shiny::p(paste(counts$observations, "response records;", counts$features, "question summaries;",
        counts$revision_effective, "final questionnaire records;", counts$revision_history, "acknowledged questionnaire events.")),
      shiny::p("These tables are bounded display previews. Long text is abbreviated here. Download observations for every complete response, JSON + provenance for the complete analysis, or the complete artifact for the original typed evidence file."),
      if (counts$scale_observations > 0L) shiny::p(paste(counts$scale_observations, "scale assessments are retained in full; use Download scale scores CSV for their complete values and support.")),
      if (counts$task_scores > 0L) shiny::p(paste(counts$task_scores, "task administrations are retained in full; use Download task scores CSV for their complete measures and scoring support.")),
      shiny::tags$details(shiny::tags$summary("Complete analysis identity"), shiny::p(analysis$questionnaire_artifact$analysis_sha256))),
    if (length(preview$features)) shiny::tagList(shiny::h2("Question summary preview"),
      shiny::p(class = "brohn-muted", paste("Showing", length(preview$features), "of", counts$features, "question summaries.")),
      lapply(seq_along(preview$features), function(i) {feature <- preview$features[[i]]; brohn_card(title = feature$prompt, subtitle = feature$condition_label,
        shiny::p(paste(feature$response_count, "responses;", feature$answered_count, "answered;", feature$missing_count, "missing.")),
        if (!is.null(feature$numeric_response_mean)) shiny::p(paste("Mean:", format(feature$numeric_response_mean, digits = 8))),
        if (length(feature$counts_preview)) shiny::tagList(shiny::p(class = "brohn-muted", paste("Showing", length(feature$counts_preview), "of", feature$count_rows, "distinct responses; text may be abbreviated.")),
          brohn_table(feature$counts_preview, columns = c("label_display", "count", "label_truncated"), maximum = 5L, label = paste("Abbreviated response frequencies for question", i))))})),
    if (length(preview$observations)) brohn_card(title = "Response preview",
      shiny::p(paste("Showing", length(preview$observations), "of", counts$observations, "complete response records. Downloads retain every row and the full text.")),
      brohn_table(preview$observations, columns = c("session_id", "prompt", "value_display", "value_truncated"), maximum = 50L, label = "Abbreviated questionnaire responses")),
    if (length(preview$revision_effective)) brohn_card(title = "Final answer preview",
      shiny::p(paste("Showing", length(preview$revision_effective), "of", counts$revision_effective, "final records. The full analysis preserves hidden, omitted and revised-answer evidence separately.")),
      brohn_table(preview$revision_effective, columns = c("session_id", "prompt", "status", "value_display", "revision_count", "value_truncated"), maximum = 50L, label = "Abbreviated final questionnaire records")))
}
