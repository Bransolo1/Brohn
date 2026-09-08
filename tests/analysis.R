# Standalone, hand-calculated checks for draft prepared-interval arithmetic.
source("R/study.R")
source("R/records.R")
source("R/assets.R")
source("R/aois.R")
source("R/analysis.R")

local({
  checks <- 0L
  expect <- function(ok) {
    if (!isTRUE(ok)) stop(sprintf("prepared-gaze check %d failed", checks + 1L))
    checks <<- checks + 1L
  }
  near <- function(actual, expected) isTRUE(all.equal(actual, expected, tolerance = 1e-12))
  rejects <- function(expression, pattern) {
    message <- tryCatch({ force(expression); "" }, error = function(e) conditionMessage(e))
    nzchar(message) && grepl(pattern, message, fixed = TRUE)
  }
  path <- tempfile(fileext = ".png")
  on.exit(unlink(path), add = TRUE)
  png::writePNG(array(seq(0, 1, length.out = 18), c(3, 2, 3)), path)
  study <- new_study(include_liking = FALSE)
  study$stimulus_assets <- lapply(study$stimulus_ids, function(id) new_png_asset(path, id))
  study$aois <- list()
  study$aois <- lapply(seq_along(study$stimulus_ids), function(side) {
    new_rectangle_aoi(study, study$stimulus_ids[side], "Logo", 0, 0, 0.5, 1,
                      id = paste0("logo-", side))
  })
  study$aois[[1L]]$label <- " Logo " # Pair by trimmed label, not by AOI ID.
  row <- function(p, s, start, end, x, y = 0.25, valid = TRUE,
                  phase = "passive_viewing") {
    data.frame(participant_id = p, stimulus_id = study$stimulus_ids[match(s, c("A", "B"))],
      start_ms = start, end_ms = end, x = x, y = y, valid = valid, phase = phase,
      stringsAsFactors = FALSE)
  }
  intervals <- rbind(
    row("p1", "A", 0, 100, 0.25), row("p1", "A", 100, 400, 0.75),
    row("p1", "A", 400, 500, 0.25, phase = "active_response"),
    row("p1", "A", 650, 700, NA_real_, NA_real_, FALSE),
    row("p1", "B", 0, 300, 0.25), row("p1", "B", 300, 400, 0.75),
    row("p2", "A", 0, 100, 0.25), row("p2", "B", 0, 100, 0.75),
    row("missing-b", "A", 0, 100, 0.25),
    row("zero-b", "A", 0, 100, 0.25),
    row("zero-b", "B", 0, 200, NA_real_, NA_real_, FALSE),
    row("missing-a", "B", 0, 100, 0.75),
    row("zero-a", "A", 0, 120, 0.25, phase = "active_response"),
    row("zero-a", "B", 0, 100, 0.75)
  )
  result <- analyze_gaze_intervals(study, intervals)
  aoi <- function(p, s) result$per_aoi[result$per_aoi$participant_id == p &
    result$per_aoi$condition == s, , drop = FALSE]
  quality <- function(p, s) result$input_quality[result$input_quality$participant_id == p &
    result$input_quality$condition == s, , drop = FALSE]
  pair <- function(p) result$pairs[result$pairs$participant_id == p, , drop = FALSE]

  expect(identical(result$method_id, "aoi-valid-gaze-time-share/0.1.0-draft") &&
    identical(result$status, "unqualified") && identical(result$time_unit, "ms") &&
    identical(result$contrast, "B-A")) # 1
  expect(aoi("p1", "A")$valid_duration_ms == 400 &&
    aoi("p1", "A")$inside_duration_ms == 100 && aoi("p1", "A")$share_pct == 25) # 2
  expect(aoi("p1", "B")$valid_duration_ms == 400 &&
    aoi("p1", "B")$inside_duration_ms == 300 && aoi("p1", "B")$share_pct == 75) # 3
  q <- quality("p1", "A")
  expect(identical(as.numeric(q[1L, -(1:3)]), c(4, 550, 2, 400, 1, 50, 1, 100, 150))) # 4
  expect(pair("p1")$difference_pp == 50 && pair("p2")$difference_pp == -100 &&
    pair("p1")$included && pair("p2")$included && is.na(pair("p1")$exclusion_reason)) # 5
  expect(result$summary$complete_pair_count == 2L &&
    result$summary$excluded_pair_count == 4L && result$summary$mean_difference_pp == -25) # 6
  expect(pair("missing-b")$reason_b == "missing_intervals" &&
    pair("missing-b")$share_pct_a == 100 && is.na(pair("missing-b")$share_pct_b) &&
    !pair("missing-b")$included && is.na(pair("missing-b")$difference_pp)) # 7
  expect(pair("zero-b")$reason_b == "zero_valid_passive_duration" &&
    quality("zero-b", "B")$interval_count == 1L &&
    quality("zero-b", "B")$valid_passive_duration_ms == 0) # 8
  expect(pair("missing-a")$reason_a == "missing_intervals" &&
    pair("missing-a")$share_pct_b == 0 && !pair("missing-a")$included) # 9
  expect(pair("zero-a")$reason_a == "zero_valid_passive_duration" &&
    quality("zero-a", "A")$active_duration_ms == 120 && !pair("zero-a")$included) # 10
  expect(is.na(aoi("missing-b", "B")$share_pct) &&
    aoi("missing-b", "B")$valid_duration_ms == 0 &&
    is.na(aoi("zero-b", "B")$share_pct) && aoi("zero-b", "B")$inside_duration_ms == 0) # 11
  expect(identical(analyze_gaze_intervals(study,
    intervals[rev(seq_len(nrow(intervals))), rev(names(intervals))]), result)) # 12
  empty <- analyze_gaze_intervals(study, intervals[FALSE, ])
  expect(nrow(empty$input_quality) == 0 && nrow(empty$per_aoi) == 0 &&
    nrow(empty$pairs) == 0 && empty$summary$complete_pair_count == 0 &&
    is.na(empty$summary$mean_difference_pp)) # 13
  other <- study; other$aois[[2L]]$label <- "Other"
  unmatched <- analyze_gaze_intervals(other, intervals)
  expect(all(!unmatched$pairs$included) &&
    all(unmatched$pairs$reason_b[unmatched$pairs$aoi_label == "Logo"] == "missing_aoi") &&
    all(unmatched$pairs$reason_a[unmatched$pairs$aoi_label == "Other"] == "missing_aoi")) # 14

  # Four quadrants partition the image. Four interior/shared-edge points give
  # each quadrant exactly 10 ms; five outer-edge points give 0/20/20/10 ms.
  boundary_study <- study; boundary_study$aois <- list()
  quadrant_names <- c("top-left", "top-right", "bottom-left", "bottom-right")
  quadrant_x <- c(0, 0.5, 0, 0.5); quadrant_y <- c(0, 0, 0.5, 0.5)
  boundary_study$aois <- lapply(1:4, function(i) new_rectangle_aoi(boundary_study,
    "stimulus-a", quadrant_names[i], quadrant_x[i], quadrant_y[i], 0.5, 0.5,
    id = paste0("quadrant-", i)))
  boundary_intervals <- row("edges", "A", seq(0, 30, 10), seq(10, 40, 10),
                            c(0, 0.5, 0, 0.5), c(0, 0, 0.5, 0.5))
  boundary_result <- analyze_gaze_intervals(boundary_study, boundary_intervals)$per_aoi
  expect(near(boundary_result$inside_duration_ms[match(quadrant_names,
    boundary_result$aoi_label)], rep(10, 4))) # 15
  boundary_intervals <- row("edges", "A", seq(0, 40, 10), seq(10, 50, 10),
                            c(1, 1, 0.25, 1, 0), c(1, 0.25, 1, 0, 1))
  boundary_result <- analyze_gaze_intervals(boundary_study, boundary_intervals)$per_aoi
  expect(near(boundary_result$inside_duration_ms[match(quadrant_names,
    boundary_result$aoi_label)], c(0, 20, 20, 10))) # 16

  bad <- intervals; bad$stimulus_id[1L] <- "unknown"
  expect(rejects(analyze_gaze_intervals(study, bad), "unknown stimulus")) # 17
  bad <- intervals; bad$x[3L] <- 1.1 # Active but marked valid: still invalid coordinates.
  expect(rejects(analyze_gaze_intervals(study, bad), "normalized image coordinates")) # 18
  bad <- intervals; bad$start_ms[2L] <- 99
  expect(rejects(analyze_gaze_intervals(study, bad), "overlapping intervals")) # 19
  bad <- intervals; bad$end_ms[1L] <- Inf
  expect(rejects(analyze_gaze_intervals(study, bad), "finite nonnegative times")) # 20
  expect(rejects(analyze_gaze_intervals(study, rbind(intervals, intervals[1L, ])),
    "overlapping intervals")) # 21
  bad <- intervals; bad$valid <- as.integer(bad$valid)
  expect(rejects(analyze_gaze_intervals(study, bad), "valid must be logical")) # 22
  bad <- intervals; bad$valid[1L] <- NA
  expect(rejects(analyze_gaze_intervals(study, bad), "valid must be logical")) # 23
  bad <- intervals; bad$phase[1L] <- "fixation"
  expect(rejects(analyze_gaze_intervals(study, bad), "phase must be")) # 24
  bad <- intervals; bad$duration_ms <- bad$end_ms - bad$start_ms
  expect(rejects(analyze_gaze_intervals(study, bad), "exact prepared interval columns")) # 25
  bad <- intervals; bad$participant_id[1L] <- " "
  expect(rejects(analyze_gaze_intervals(study, bad), "nonempty participant")) # 26
  bad_study <- study; bad_study$stimulus_assets[[1L]]$sha256 <- strrep("0", 64)
  expect(rejects(analyze_gaze_intervals(bad_study, intervals), "SHA-256 mismatch")) # 27
  bad_study <- study; bad_study$aois[[1L]]$asset_sha256 <- strrep("0", 64)
  expect(rejects(analyze_gaze_intervals(bad_study, intervals), "binding mismatch")) # 28
  bad <- intervals; bad$y[1L] <- NaN
  expect(rejects(analyze_gaze_intervals(study, bad), "normalized image coordinates")) # 29
  expect(all(vapply(list(c(-1, 100), c(100, 100), c(101, 100)), function(times) {
    bad <- intervals; bad$start_ms[1L] <- times[1L]; bad$end_ms[1L] <- times[2L]
    rejects(analyze_gaze_intervals(study, bad), "finite nonnegative times")
  }, logical(1)))) # 30
  cat(sprintf("PASS: %d prepared-gaze mathematical checks (unqualified draft)\n", checks))
})
