if (identical(Sys.getenv("BROHN_APP_MODE", "platform"), "platform")) {
  source("R/platform-load.R", local = TRUE, encoding = "UTF-8")
  brohn_load(environment())
  shiny::shinyApp(ui = brohn_shell_ui(), server = brohn_server)
} else {
for (path in c("R/study.R", "R/comparison.R", "R/presentation.R", "R/presentation-ui.R", "R/records.R", "R/json.R", "R/storage.R", "R/drafts.R", "R/assets.R", "R/aois.R", "R/aoi-ui.R", "R/analysis.R", "R/sample-analysis.R", "R/gaze-import.R", "R/import-report.R", "R/import-ui.R", "R/protocol.R", "R/protocol-storage.R", "R/app.R")) {
  source(path, local = TRUE, encoding = "UTF-8")
}

shiny::shinyApp(ui = research_ui(), server = research_server)
}
