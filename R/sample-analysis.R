# Fixed, fictional prepared gaze intervals for demonstrating the draft arithmetic.
# Coordinates refer to the packaged sample images; they are not observed gaze.
sample_gaze_intervals <- function(bundle) {
  record_assert(!length(validate_bundle(bundle)), "Open a valid sample first.")
  record_assert(identical(bundle$session$mode, "sample"), "The demonstration runs only on a sample study.")
  paths <- file.path("examples", "stimuli", c("sample-design-a.png", "sample-design-b.png"))
  for (i in 1:2) {
    expected <- new_png_asset(paths[[i]], bundle$study$stimulus_ids[[i]])
    actual <- Filter(function(a) identical(a$stimulus_id, expected$stimulus_id), bundle$study$stimulus_assets)
    record_assert(length(actual) == 1 && identical(actual[[1]]$sha256, expected$sha256),
                  "This demonstration belongs to the packaged sample images. Open a fresh guided sample to run it.")
  }
  inside <- matrix(c(200, 400, 300, 600, 400, 500), nrow = 3, byrow = TRUE)
  rows <- list()
  for (participant in 1:3) for (stimulus in 1:2) {
    duration <- inside[participant, stimulus]
    rows[[length(rows) + 1L]] <- data.frame(
      participant_id = paste0("synthetic-", participant), stimulus_id = bundle$study$stimulus_ids[[stimulus]],
      start_ms = c(0, duration, 1000, 1200), end_ms = c(duration, 1000, 1200, 1500),
      x = c(0.5, 0.8, NA_real_, 0.5), y = c(0.47, 0.8, NA_real_, 0.47),
      valid = c(TRUE, TRUE, FALSE, TRUE),
      phase = c("passive_viewing", "passive_viewing", "passive_viewing", "active_response"),
      stringsAsFactors = FALSE)
  }
  do.call(rbind, rows)
}

build_sample_report <- function(bundle) {
  intervals <- sample_gaze_intervals(bundle)
  result <- analyze_gaze_intervals(bundle$study, intervals)
  list(schema_version = "sample-report/0.1.0", origin = "synthetic_demonstration",
       study = bundle$study, prepared_intervals = intervals, analysis = result,
       limitations = c("Fictional data; no participant recording.",
         "Prepared interval arithmetic only; no raw-device preprocessing or clock qualification.",
         "Unqualified draft method; no inferential statistics or causal interpretation.",
         "Fixed fictional intervals do not simulate the planned presentation order or duration."))
}

sample_report_to_json <- function(report, pretty = FALSE) {
  record_assert(identical(report$schema_version, "sample-report/0.1.0") &&
    identical(report$origin, "synthetic_demonstration"), "A synthetic sample report is required.")
  # Recompute rather than trusting cached output tables supplied by the caller.
  report$analysis <- analyze_gaze_intervals(report$study, report$prepared_intervals)
  report$study <- .study_to_wire(report$study)
  report$limitations <- I(report$limitations)
  as.character(jsonlite::toJSON(report, auto_unbox = TRUE, dataframe = "rows",
    na = "null", null = "null", digits = 17, pretty = pretty))
}

sample_results_ui <- function(report) {
  synthetic <- identical(report$origin, "synthetic_demonstration")
  result <- report$analysis
  summary <- result$summary
  rows <- lapply(seq_len(nrow(summary)), function(i) {
    row <- summary[i, ]
    shiny::div(class = "result-card",
      shiny::span(class = "eyebrow", row$aoi_label),
      shiny::div(class = "result-value", if (is.na(row$mean_difference_pp)) "Not comparable" else
        paste0(if (row$mean_difference_pp > 0) "+" else "", format(round(row$mean_difference_pp, 2), trim = TRUE), " pp")),
      shiny::p(if (row$complete_pair_count) paste("Average B minus A across", row$complete_pair_count, if (synthetic) "fictional participants." else "included participants.") else
        "Both designs need a matching named area and valid viewing intervals."))
  })
  table <- result$pairs[, c("participant_id", "aoi_label", "share_pct_a", "share_pct_b", "difference_pp", "included")]
  names(table) <- c(if (synthetic) "Fictional participant" else "Participant ID", "Area", "A (%)", "B (%)", "B - A (pp)", "Included")
  total_rows <- nrow(table)
  table <- head(table, 100)
  format_cell <- function(v) {
    if (is.na(v)) "Unavailable" else if (is.logical(v)) if (v) "Yes" else "No" else if (is.numeric(v)) format(round(v, 2), trim = TRUE) else as.character(v)
  }
  shiny::div(class = "panel", shiny::span(class = "eyebrow", if (synthetic) "5 / RESULTS - SYNTHETIC DEMONSTRATION" else "5 / RESULTS - IMPORTED PREPARED DATA"),
    shiny::h2("A result you can follow back to its inputs."),
    shiny::div(class = "info-note", if (synthetic) "These results use fictional gaze intervals and a draft calculation. They are not findings from people, a calibrated device or a scientifically qualified method." else
      "These calculations use your imported prepared intervals. Device calibration, source origin, clock alignment and preprocessing have not been independently verified. The method remains an unqualified draft."),
    shiny::div(class = "result-grid", rows),
    shiny::p(shiny::strong(comparison_caption(report$study))),
    shiny::p("For each participant, the calculation divides valid viewing time inside the area by all eligible valid viewing time. It then compares B with A in percentage points (pp). Invalid intervals and question periods are excluded."),
    shiny::div(class = "table-scroll", tabindex = "0", role = "region", `aria-label` = "Participant calculation table", shiny::tags$table(class = "table",
      shiny::tags$caption(if (synthetic) "Participant-level calculations for the synthetic sample" else "Participant-level calculations from prepared intervals"),
      shiny::tags$thead(shiny::tags$tr(lapply(names(table), function(n) shiny::tags$th(scope = "col", n)))),
      shiny::tags$tbody(lapply(seq_len(nrow(table)), function(i) shiny::tags$tr(lapply(table[i, ], function(v) shiny::tags$td(format_cell(v)))))))),
    if (total_rows > 100) shiny::p(class = "muted", paste("Showing the first 100 of", total_rows, "participant/area rows. The export contains every row.")),
    shiny::tags$details(shiny::tags$summary("What was included and excluded?"),
      shiny::p(paste(sum(result$input_quality$valid_passive_duration_ms), "ms of valid viewing included;",
        sum(result$input_quality$invalid_passive_duration_ms), "ms of invalid viewing excluded;",
        sum(result$input_quality$active_duration_ms), "ms of question periods excluded.")),
      shiny::p("Unrecorded gaps are never filled. An unavailable or zero-valid-duration side is excluded from the paired comparison, rather than reported as zero attention."),
      if (any(!result$pairs$included)) shiny::tags$ul(lapply(head(which(!result$pairs$included), 100), function(i)
        shiny::tags$li(paste(result$pairs$participant_id[[i]], result$pairs$aoi_label[[i]], result$pairs$exclusion_reason[[i]])))),
      if (sum(!result$pairs$included) > 100) shiny::p("Showing the first 100 exclusion reasons. Every reason is included in the export.")),
    shiny::downloadButton(if (synthetic) "export_sample_report" else "export_import_report", if (synthetic) "Export reproducible sample JSON" else "Export reproducible report", icon = NULL, class = "btn-outline-primary"),
    shiny::p(class = "muted", if (synthetic) "The export includes the images, areas, fictional intervals and calculated tables. The fixed fictional inputs do not simulate the planned order or viewing duration. Editing the draft invalidates the displayed calculation; returning to Results recalculates it." else
      paste("Saved on this computer. The export includes the original CSV, content hash, study snapshot and calculated tables.", report$source$row_count, "intervals were imported. Changing the draft requires a new calculation.")))
}
