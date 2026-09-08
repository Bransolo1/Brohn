.libPaths(c(normalizePath("../../work/r-library-brohn", winslash = "/", mustWork = FALSE), .libPaths()))
for (module in c("platform-core", "platform-analysis", "platform-gaze")) source(paste0("R/", module, ".R"))
local({
  checks <- 0L
  check <- function(name, value) { if (!isTRUE(value)) stop("FAIL: ", name); checks <<- checks+1L }
  close <- function(a, b, tolerance = 1e-8) isTRUE(all.equal(a, b, tolerance = tolerance, check.attributes = FALSE))
  rejects <- function(expr) inherits(try(force(expr), silent = TRUE), "try-error")
  design <- brohn_new_design("Declared-geometry gaze fixture", id = "study-raw-gaze")
  for (i in 1:2) design$stimuli[[i]]$aois <- list(
    list(id = "left", label = "Left", x = 0, y = 0, width = .5, height = 1),
    list(id = "right", label = "Right", x = .5, y = 0, width = .5, height = 1),
    list(id = "unused", label = "Unused", x = .9, y = 0, width = .05, height = .1))
  metadata <- list(gaze_representation = "samples", unit = "stimulus_normalized", time_unit = "ms",
    time_column = "time", x_column = "x", y_column = "y", valid_column = "valid",
    participant_column = "participant", session_column = "session", stimulus_column = "stimulus",
    exposure_column = "exposure", condition_column = "condition", phase_column = "phase", phase_value = "view",
    exposure_start_column = "onset", exposure_end_column = "offset",
    geometry = list(width_mm = 400, height_mm = 300, distance_mm = 600, center_x_mm = 0, center_y_mm = 0),
    geometry_source = "Synthetic fixture: stationary eye at origin; 400 by 300 mm centered stimulus plane 600 mm away.",
    parameters = list(velocity_threshold_deg_s = 30, min_fixation_ms = 60, min_saccade_ms = 10,
      max_gap_ms = 20, threshold_source = "Synthetic fixture threshold, not a device recommendation."))
  data <- data.frame(time = seq(0, 410, 10), x = c(rep(.25, 21), rep(.75, 21)), y = .5,
    valid = TRUE, participant = "person-one", session = "session-one", stimulus = "stimulus-a",
    exposure = "exposure-a", condition = "condition-a", phase = "view", onset = 0, offset = 410,
    stringsAsFactors = FALSE)
  result <- brohn_raw_gaze_analysis(data, metadata, design)
  features <- function(x, type) Filter(function(r) identical(r$record_type, type), x$features)
  aoi <- function(x, id) Filter(function(r) identical(r$aoi_id, id), x$observations)[[1]]
  fix <- features(result, "fixation_candidate"); sac <- features(result, "saccade_candidate")
  check("hand fixture produces two fixation candidates", length(fix) == 2L && close(vapply(fix, `[[`, numeric(1), "duration_ms"), c(200, 200)))
  check("hand fixture retains observed saccade interval", length(sac) == 1L && close(sac[[1]]$duration_ms, 10))
  expected_angle <- 2*atan(100/600)*180/pi
  check("3D ray angle matches independent tangent formula", close(sac[[1]]$angular_path_deg, expected_angle) &&
    close(sac[[1]]$peak_velocity_deg_s, expected_angle/.01))
  check("detector is explicitly unqualified", identical(result$parameters$method, "brohn-adjacent-ray-ivt/0.1.0-draft") && !result$quality$qualified && !fix[[1]]$qualified)
  check("valid gaze denominator includes the crossing interval", close(aoi(result, "left")$valid_ms, 410) &&
    close(aoi(result, "left")$inside_ms, 200) && close(aoi(result, "left")$valid_share_percent, 100*200/410))
  check("AOI crossing remains unassigned and explicit", close(aoi(result, "left")$crossing_interval_ms, 10) &&
    close(aoi(result, "right")$crossing_interval_ms, 10))
  check("fixation dwell comes from candidate events", close(aoi(result, "left")$fixation_dwell_ms, 200) &&
    aoi(result, "left")$fixation_candidate_count == 1L)
  check("later first fixation candidate has actual-onset latency", close(aoi(result, "right")$ttff_ms, 210) &&
    identical(aoi(result, "right")$ttff_status, "observed_fixation_candidate"))
  check("left-boundary onset is not invented as zero TTFF", is.null(aoi(result, "left")$ttff_ms) &&
    aoi(result, "left")$first_observed_candidate_from_exposure_ms == 0 &&
    identical(aoi(result, "left")$ttff_status, "left_boundary_candidate_onset_unknown"))
  check("never-fixated AOI right-censors only with complete exposure evidence", is.null(aoi(result, "unused")$ttff_ms) &&
    close(aoi(result, "unused")$censor_time_ms, 410) && aoi(result, "unused")$complete_observation)
  check("observed AOI transition is retained", length(features(result, "aoi_transition")) == 1L)
  missing_geometry <- metadata; missing_geometry$geometry$distance_mm <- NULL
  check("missing physical geometry is rejected", rejects(brohn_raw_gaze_analysis(data, missing_geometry, design)))
  no_threshold_source <- metadata; no_threshold_source$parameters$threshold_source <- ""
  check("threshold provenance cannot be omitted", rejects(brohn_raw_gaze_analysis(data, no_threshold_source, design)))
  invalid <- data; invalid$valid[[11]] <- FALSE; invalid$x[[11]] <- NA; invalid$y[[11]] <- NA
  lost <- brohn_raw_gaze_analysis(invalid, metadata, design)
  check("missing sample removes both neighboring intervals", close(aoi(lost, "left")$valid_ms, 390) &&
    length(features(lost, "fixation_candidate")) == 3L)
  check("missing prior observation suppresses TTFF", is.null(aoi(lost, "right")$ttff_ms) &&
    identical(aoi(lost, "right")$ttff_status, "unavailable_missing_prior_observation"))
  check("missing exposure observation suppresses right censoring", is.null(aoi(lost, "unused")$censor_time_ms) &&
    identical(aoi(lost, "unused")$ttff_status, "unavailable_incomplete_observation"))
  check("invalid sample mask is represented", any(vapply(features(lost, "quality_mask"), function(x) x$reason == "invalid_gaze" && x$duration_ms == 20, logical(1))))
  invalid$valid[[11]] <- TRUE
  check("declared-valid missing coordinates fail explicitly", rejects(brohn_raw_gaze_analysis(invalid, metadata, design)))
  gap <- data; gap$time[22:42] <- gap$time[22:42]+100; gap$offset <- 510
  gapped <- brohn_raw_gaze_analysis(gap, metadata, design)
  check("large timestamp gap cannot become a saccade", length(features(gapped, "saccade_candidate")) == 0L &&
    length(features(gapped, "aoi_transition")) == 0L && close(aoi(gapped, "left")$valid_ms, 400))
  phase <- data; phase$phase[[11]] <- "response"
  phased <- brohn_raw_gaze_analysis(phase, metadata, design)
  check("discarded phase rows cannot bridge fixation candidates", close(aoi(phased, "left")$valid_ms, 390) &&
    length(features(phased, "fixation_candidate")) == 3L)
  duplicate <- data; duplicate$time[[10]] <- duplicate$time[[9]]
  check("duplicate and reversed time are rejected", rejects(brohn_raw_gaze_analysis(duplicate, metadata, design)) &&
    rejects(brohn_raw_gaze_analysis(data[nrow(data):1L, ], metadata, design)))
  no_bounds <- metadata; no_bounds$exposure_start_column <- NULL; no_bounds$exposure_end_column <- NULL
  unanchored <- brohn_raw_gaze_analysis(data, no_bounds, design)
  check("sample span cannot masquerade as actual exposure clock", is.null(aoi(unanchored, "right")$ttff_ms) &&
    identical(aoi(unanchored, "right")$ttff_status, "unavailable_no_exposure_clock"))
  seconds <- metadata; seconds$time_unit <- "s"
  seconds_data <- data; seconds_data$time <- seconds_data$time/1000; seconds_data$offset <- seconds_data$offset/1000
  in_seconds <- brohn_raw_gaze_analysis(seconds_data, seconds, design)
  check("seconds and milliseconds yield equivalent scientific features", close(aoi(in_seconds, "right")$ttff_ms, 210) &&
    close(aoi(in_seconds, "left")$fixation_dwell_ms, 200))
  shifted <- data; shifted$time <- shifted$time+100000; shifted$onset <- shifted$onset+100000; shifted$offset <- shifted$offset+100000
  translated <- brohn_raw_gaze_analysis(shifted, metadata, design)
  check("clock translation does not change TTFF or dwell", close(aoi(translated, "right")$ttff_ms, 210) && close(aoi(translated, "left")$fixation_dwell_ms, 200))
  off <- data; off$x <- -1
  outside <- brohn_raw_gaze_analysis(off, metadata, design)
  check("off-stimulus gaze stays in the denominator", close(aoi(outside, "left")$valid_ms, 410) && aoi(outside, "left")$valid_share_percent == 0)
  edge <- data; edge$x <- .5
  edged <- brohn_raw_gaze_analysis(edge, metadata, design)
  check("AOI edges remain half open", aoi(edged, "left")$inside_ms == 0 && aoi(edged, "right")$inside_ms == 410)
  unavailable <- data; unavailable$valid <- FALSE; unavailable$x <- NA; unavailable$y <- NA
  empty <- brohn_raw_gaze_analysis(unavailable, metadata, design)
  check("zero valid duration is missing share, not zero effect", is.null(aoi(empty, "left")$valid_share_percent) &&
    is.null(aoi(empty, "left")$fixation_dwell_ms) && is.null(aoi(empty, "left")$ttff_ms) && length(features(empty, "fixation_candidate")) == 0L)
  eyes <- data; eyes$left <- TRUE; eyes$right <- TRUE; eyes$left[11:13] <- FALSE
  eye_mapping <- metadata; eye_mapping$left_valid_column <- "left"; eye_mapping$right_valid_column <- "right"
  eye_result <- brohn_raw_gaze_analysis(eyes, eye_mapping, design)
  check("per-eye availability remains an explicit separate mask", any(vapply(features(eye_result, "quality_mask"),
    function(e) e$reason == "left_eye_unavailable", logical(1))) && features(eye_result, "exposure_summary")[[1]]$left_eye_unavailable_samples == 3L)
  blink_data <- data; blink_data$blink <- FALSE; blink_data$blink[11:13] <- TRUE
  blink_mapping <- metadata; blink_mapping$blink_column <- "blink"; blink_mapping$blink_source <- "Synthetic externally labelled blink fixture"
  blinks <- brohn_raw_gaze_analysis(blink_data, blink_mapping, design)
  check("only explicit source labels become blink records", length(features(blinks, "source_labelled_blink")) == 1L &&
    close(features(blinks, "source_labelled_blink")[[1]]$observed_duration_ms, 20) &&
    length(features(lost, "source_labelled_blink")) == 0L)
  # Independent pupil fixture: 100 ms baseline at 4 mm and 100 ms exposure at
  # 6 mm. No interpolation crosses the phase boundary; correction is 2 mm.
  pupil <- data[rep(1, 22), ]; pupil$time <- seq(0, 210, 10); pupil$phase <- c(rep("baseline", 11), rep("view", 11))
  pupil$x <- .25; pupil$pupil <- c(rep(4, 11), rep(6, 11)); pupil$onset <- 110; pupil$offset <- 210
  pupil$baseline_start <- 0; pupil$baseline_end <- 100; pupil$pupil_valid <- TRUE
  pupil_mapping <- metadata; pupil_mapping$pupil_column <- "pupil"; pupil_mapping$pupil_valid_column <- "pupil_valid"
  pupil_mapping$pupil_unit <- "mm"; pupil_mapping$pupil_source <- "Synthetic pupil diameter fixture"
  pupil_mapping$pupil_baseline <- list(mode = "subtractive", phase_value = "baseline", start_column = "baseline_start",
    end_column = "baseline_end", minimum_coverage = .9, minimum_duration_ms = 90,
    source = "Independent hand calculation; this is not a clinical or device validation.")
  pupil_result <- features(brohn_raw_gaze_analysis(pupil, pupil_mapping, design), "pupil_summary")[[1]]
  check("pupil subtraction matches independent reference arithmetic", close(pupil_result$baseline_mean, 4) &&
    close(pupil_result$mean_pupil, 6) && close(pupil_result$baseline_corrected_mean, 2))
  bounded_pupil <- pupil; bounded_pupil$baseline_start <- 5; bounded_pupil$baseline_end <- 95
  bounded_mapping <- pupil_mapping; bounded_mapping$pupil_baseline$minimum_coverage <- .8
  bounded_mapping$pupil_baseline$minimum_duration_ms <- 80
  bounded_result <- features(brohn_raw_gaze_analysis(bounded_pupil, bounded_mapping, design), "pupil_summary")[[1]]
  check("pupil baseline boundaries never invent partial sample intervals", close(bounded_result$baseline_valid_ms, 80) &&
    close(bounded_result$baseline_coverage, 80/90) && close(bounded_result$baseline_mean, 4))
  pupil$pupil_valid[[6]] <- FALSE
  bad_baseline <- features(brohn_raw_gaze_analysis(pupil, pupil_mapping, design), "pupil_summary")[[1]]
  check("insufficient baseline cannot produce corrected pupil score", close(bad_baseline$baseline_coverage, .8) &&
    is.null(bad_baseline$baseline_corrected_mean) && identical(bad_baseline$baseline_status, "excluded_insufficient_valid_baseline"))
  repeated <- rbind(data, transform(data, exposure = "second-exposure", time = time+1000, onset = onset+1000, offset = offset+1000))
  repeated_result <- brohn_raw_gaze_analysis(repeated, metadata, design)
  check("repeated exposures retain separate detector boundaries", length(features(repeated_result, "exposure_summary")) == 2L &&
    length(features(repeated_result, "fixation_candidate")) == 4L)
  other <- data; other$stimulus <- "stimulus-b"; other$condition <- "condition-b"; other$exposure <- "exposure-b"
  paired <- brohn_raw_gaze_analysis(rbind(data, other), metadata, design)
  check("paired condition contrasts retain participant rather than exposure N", length(paired$contrasts) > 0 &&
    all(vapply(paired$contrasts, function(c) c$participant_count == 1L && is.null(c$interval95) && c$estimate == 0, logical(1))))
  # Contextual upstream comparison, not numerical equivalence: the installed
  # Engbert-Kliegl relative-threshold detector and this fixed angular detector
  # have different definitions. A declared synthetic two-cluster recording
  # supplies no external participant data or unreported physical geometry.
  methods_library <- normalizePath("../../work/r-library-methods", winslash = "/", mustWork = TRUE)
  old_library_paths <- .libPaths()
  on.exit(.libPaths(old_library_paths), add = TRUE)
  .libPaths(c(methods_library, .libPaths()))
  check("upstream comparison uses pinned saccades package", as.character(utils::packageVersion("saccades")) == "0.2.1")
  method_functions <- c("detect.fixations", "detect.saccades", "aggregate.fixations", "label.blinks.artifacts")
  method_code <- lapply(method_functions, function(name) {
    f <- getFromNamespace(name, "saccades")
    list(name = name, formals = formals(f), body = deparse(body(f)))
  })
  check("upstream detector and helper code match the reference pin", identical(digest::digest(method_code, algo = "sha256"),
    "26f3ac2176e74f40b4bfd01759bd9bdb3365352884ab66beca453b19930b1c16"))
  index <- seq_len(300)
  compare <- data[rep(1, 300), ]; compare$time <- (index-1)*10; compare$offset <- 2990
  compare$x <- c(rep(.25, 150), rep(.75, 150)) + .0002*sin(index)
  compare$y <- .5 + .0002*cos(index)
  upstream <- saccades::detect.fixations(data.frame(time = compare$time, x = compare$x*1600,
    y = compare$y*1200, trial = "synthetic"), lambda = 6, smooth.coordinates = FALSE, smooth.saccades = TRUE)
  native <- brohn_raw_gaze_analysis(compare, metadata, design)
  check("both explicit detectors find the synthetic stationary clusters", sum(upstream$event == "fixation") >= 2L &&
    length(features(native, "fixation_candidate")) == 2L)
  check("upstream comparison retains bounded independent event durations", all(upstream$dur >= 0) && all(upstream$start >= 0 & upstream$end <= 2990))
  cat(sprintf("PASS: %d raw gaze checks (geometry, candidates, AOIs, missingness, clocks, pupil, explicit blinks, upstream comparison)\n", checks))
  cat(sprintf("Upstream context: saccades 0.2.1 labelled %d fixations; fixed angular recipe found %d candidates. Different methods, not an agreement/qualification claim.\n",
    sum(upstream$event == "fixation"), length(features(native, "fixation_candidate"))))
})
