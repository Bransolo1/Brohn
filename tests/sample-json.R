for (path in c("study", "comparison", "presentation", "records", "json", "assets", "aois", "drafts", "analysis", "sample-analysis"))
  source(paste0("R/", path, ".R"))
local({
  bundle <- create_draft("sample")
  bundle <- revise_draft(bundle, "Portable example", FALSE)
  bundle <- revise_comparison(bundle, "A", "Current design, same viewing task")
  bundle <- revise_presentation(bundle, "counterbalanced_ab_ba", 6000)
  report <- build_sample_report(bundle)
  report$analysis$summary$mean_difference_pp <- 999 # Encoder must recompute stale tables.
  wire <- sample_report_to_json(report)
  parsed <- jsonlite::fromJSON(wire, simplifyVector = FALSE)
  stopifnot(is.list(parsed$study$measures), identical(parsed$study$measures[[1]], "eye"),
    identical(parsed$study$questions, list()), is.list(parsed$prepared_intervals),
    is.null(parsed$prepared_intervals[[3]]$x),
    identical(parsed$study$comparison$control_condition, "A"), parsed$study$presentation$viewing_duration_ms == 6000)
  study <- .study_from_wire(parsed$study)
  intervals <- jsonlite::fromJSON(wire)$prepared_intervals
  recomputed <- analyze_gaze_intervals(study, intervals)
  stopifnot(isTRUE(all.equal(recomputed, build_sample_report(bundle)$analysis)),
    parsed$analysis$summary[[1]]$mean_difference_pp == 20)
  if (nzchar(Sys.getenv("CONTRACT_FIXTURE_DIR")))
    writeLines(wire, file.path(Sys.getenv("CONTRACT_FIXTURE_DIR"), "sample-report.json"))
})
cat("PASS: portable sample export and independent recalculation\n")
