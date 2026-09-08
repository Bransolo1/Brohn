# Standalone checks for the fictional guided sample and report recalculation.
source("R/study.R")
source("R/records.R")
source("R/assets.R")
source("R/aois.R")
source("R/drafts.R")
source("R/analysis.R")
source("R/sample-analysis.R")

local({
  checks <- 0L
  expect <- function(ok) {
    if (!isTRUE(ok)) stop(sprintf("sample-report check %d failed", checks + 1L))
    checks <<- checks + 1L
  }
  near <- function(actual, expected) isTRUE(all.equal(actual, expected, tolerance = 1e-12))
  rejects <- function(expression, pattern) {
    message <- tryCatch({ force(expression); "" }, error = function(e) conditionMessage(e))
    nzchar(message) && grepl(pattern, message, fixed = TRUE)
  }
  sample <- create_draft("sample")
  expect(!length(validate_bundle(sample)) && length(sample$study$stimulus_assets) == 2L &&
    length(sample$study$aois) == 2L &&
    all(vapply(sample$study$aois, function(aoi) aoi$label == "Brand mark", logical(1))))

  report <- build_sample_report(sample)
  result <- report$analysis
  pairs <- result$pairs[match(paste0("synthetic-", 1:3), result$pairs$participant_id), ]
  expect(identical(report$origin, "synthetic_demonstration") &&
    identical(report$study, sample$study) &&
    identical(result$method_id, "aoi-valid-gaze-time-share/0.1.0-draft") &&
    identical(result$status, "unqualified") && identical(result$contrast, "B-A"))
  expect(nrow(pairs) == 3L && all(pairs$aoi_label == "Brand mark") &&
    near(pairs$share_pct_a, c(20, 30, 40)) && near(pairs$share_pct_b, c(40, 60, 50)) &&
    near(pairs$difference_pp, c(20, 30, 10)) && all(pairs$included))
  expect(nrow(result$summary) == 1L && result$summary$complete_pair_count == 3L &&
    result$summary$excluded_pair_count == 0L && near(result$summary$mean_difference_pp, 20))
  expect(sum(result$input_quality$valid_passive_duration_ms) == 6000 &&
    sum(result$input_quality$invalid_passive_duration_ms) == 1200 &&
    sum(result$input_quality$active_duration_ms) == 1800)
  expect(nrow(report$prepared_intervals) == 24L &&
    identical(build_sample_report(sample), report))

  expect(rejects(build_sample_report(create_draft()), "only on a sample study"))
  path <- tempfile(fileext = ".png")
  on.exit(unlink(path), add = TRUE)
  png::writePNG(array(seq(0, 1, length.out = 18), c(3, 2, 3)), path)
  replacement <- set_stimulus_asset(sample, new_png_asset(path, sample$study$stimulus_ids[1L]))
  expect(!length(validate_bundle(replacement)) &&
    rejects(build_sample_report(replacement), "packaged sample images"))

  # Expanding B to the full image yields 100% B for each fictional participant.
  old_b <- sample$study$aois[[2L]]
  full_b <- new_rectangle_aoi(sample$study, old_b$stimulus_id, old_b$label,
                            0, 0, 1, 1, id = old_b$id)
  edited <- set_study_aoi(sample, full_b)
  recalculated <- build_sample_report(edited)
  expect(identical(recalculated$prepared_intervals, report$prepared_intervals) &&
    identical(recalculated$study, edited$study) &&
    recalculated$study$revision == report$study$revision + 1L)
  expect(near(recalculated$analysis$pairs$share_pct_b, rep(100, 3)) &&
    near(recalculated$analysis$pairs$difference_pp, c(80, 70, 60)) &&
    near(recalculated$analysis$summary$mean_difference_pp, 70))

  missing <- build_sample_report(remove_study_aoi(sample, old_b$id))$analysis
  expect(nrow(missing$pairs) == 3L && all(!missing$pairs$included) &&
    all(is.na(missing$pairs$share_pct_b)) && all(is.na(missing$pairs$difference_pp)) &&
    all(missing$pairs$reason_b == "missing_aoi") &&
    all(missing$pairs$exclusion_reason == "B: missing_aoi"))
  expect(missing$summary$complete_pair_count == 0L &&
    missing$summary$excluded_pair_count == 3L && is.na(missing$summary$mean_difference_pp))

  renamed_b <- old_b; renamed_b$label <- "Other area"
  unmatched <- build_sample_report(set_study_aoi(sample, renamed_b))$analysis
  brand <- unmatched$pairs[unmatched$pairs$aoi_label == "Brand mark", ]
  other <- unmatched$pairs[unmatched$pairs$aoi_label == "Other area", ]
  expect(nrow(unmatched$pairs) == 6L && all(!unmatched$pairs$included) &&
    all(brand$exclusion_reason == "B: missing_aoi") &&
    all(other$exclusion_reason == "A: missing_aoi") &&
    all(is.na(unmatched$summary$mean_difference_pp)))
  cat(sprintf("PASS: %d fictional sample-report checks (unqualified draft)\n", checks))
})
