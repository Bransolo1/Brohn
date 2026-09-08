# Transparent offline sampled-gaze recipe. Fixed adjacent-ray I-VT produces
# candidates, not device-qualified fixations or an implementation of Tobii I-VT.
.brohn_gaze_boolean <- function(value, name) {
  text <- tolower(trimws(as.character(value)))
  brohn_require(!anyNA(text) && all(text %in% c("true", "false", "1", "0")),
    paste(name, "needs explicit true/false or 1/0 values for every sample."))
  text %in% c("true", "1")
}
.brohn_gaze_nullable <- function(value) if (!length(value) || !is.finite(value)) NULL else unname(value)
.brohn_gaze_runs <- function(indices) {
  if (!length(indices)) return(list())
  split(indices, cumsum(c(TRUE, diff(indices) != 1L)))
}
.brohn_gaze_inside <- function(x, y, aoi) {
  inside <- is.finite(x) & is.finite(y) & x >= aoi$x & x < aoi$x + aoi$width &
    y >= aoi$y & y < aoi$y + aoi$height
  inside[is.na(inside)] <- FALSE
  inside
}
.brohn_gaze_angles <- function(x, y, geometry) {
  rays <- cbind((x-.5)*geometry$width_mm + geometry$center_x_mm,
    (.5-y)*geometry$height_mm + geometry$center_y_mm, geometry$distance_mm)
  if (nrow(rays) < 2L) return(numeric())
  a <- rays[-nrow(rays), , drop = FALSE]; b <- rays[-1L, , drop = FALSE]
  cross <- cbind(a[, 2]*b[, 3]-a[, 3]*b[, 2], a[, 3]*b[, 1]-a[, 1]*b[, 3], a[, 1]*b[, 2]-a[, 2]*b[, 1])
  atan2(sqrt(rowSums(cross^2)), rowSums(a*b))*180/pi
}
brohn_validate_raw_gaze_mapping <- function(metadata, columns = NULL) {
  m <- metadata
  brohn_require(identical(m$gaze_representation, "samples") && identical(m$unit, "stimulus_normalized"),
    "Raw gaze requires sampled observations in the rendered stimulus-normalized frame.")
  brohn_require(m$time_unit %in% c("s", "ms"), "Raw gaze time must be relative seconds or milliseconds.")
  required <- c("time_column", "x_column", "y_column", "valid_column", "participant_column", "session_column", "stimulus_column", "exposure_column")
  optional <- c("condition_column", "phase_column", "exposure_start_column", "exposure_end_column", "pupil_column", "pupil_valid_column", "blink_column", "left_valid_column", "right_valid_column")
  for (field in c(required, optional)) {
    value <- m[[field]]
    if (field %in% required || !is.null(value) && !identical(value, ""))
      brohn_require(brohn_text(value, 500) && (is.null(columns) || value %in% columns), paste("Map a source column for", field))
  }
  brohn_require((brohn_text(m$phase_column, 500) && brohn_text(m$phase_value, 500)) || identical(m$source_phase, "passive_viewing_only"),
    "Map passive-viewing phases or explicitly declare a passive-viewing-only source.")
  has_start <- brohn_text(m$exposure_start_column, 500); has_end <- brohn_text(m$exposure_end_column, 500)
  brohn_require(identical(has_start, has_end), "Exposure onset and offset columns must be supplied together.")
  p <- m$parameters; g <- m$geometry
  brohn_require(is.list(p) && brohn_number(p$velocity_threshold_deg_s, .01, 10000) &&
    brohn_number(p$min_fixation_ms, 1, 10000) && brohn_number(p$min_saccade_ms, .1, 1000) &&
    brohn_number(p$max_gap_ms, .01, 1000) && brohn_text(p$threshold_source, 4000),
    "Declare the angular velocity threshold, fixation/saccade minimum durations, maximum sample gap and threshold provenance.")
  brohn_require(is.list(g) && brohn_number(g$width_mm, .01, 100000) && brohn_number(g$height_mm, .01, 100000) &&
    brohn_number(g$distance_mm, 1, 100000) && brohn_number(g$center_x_mm, -100000, 100000) &&
    brohn_number(g$center_y_mm, -100000, 100000) && brohn_text(m$geometry_source, 4000),
    "Declare rendered stimulus width/height, viewing distance, eye-relative center offsets and geometry provenance in millimeters.")
  if (brohn_text(m$blink_column, 500)) brohn_require(brohn_text(m$blink_source, 4000), "Explicit blink labels need their detector/source provenance; track loss alone is not a blink.")
  if (brohn_text(m$pupil_column, 500)) {
    brohn_require(m$pupil_unit %in% c("mm", "mm2", "pixels", "pixels2", "device_units") && brohn_text(m$pupil_source, 4000), "Declare the actual pupil measurement unit and source.")
    b <- m$pupil_baseline
    brohn_require(is.list(b) && b$mode %in% c("none", "subtractive"), "Declare pupil baseline mode: none or subtractive.")
    if (b$mode == "subtractive") {
      brohn_require(brohn_text(m$phase_column, 500) && brohn_text(b$phase_value, 500) && !identical(b$phase_value, m$phase_value) &&
        brohn_text(b$start_column, 500) && brohn_text(b$end_column, 500) &&
        (is.null(columns) || all(c(b$start_column, b$end_column) %in% columns)) &&
        brohn_number(b$minimum_coverage, .01, 1) && brohn_number(b$minimum_duration_ms, 1, 600000) &&
        brohn_text(b$source, 4000), "Subtractive pupil correction requires a separate baseline phase/window, minimum coverage/duration and provenance.")
    }
  }
  invisible(TRUE)
}

brohn_raw_gaze_analysis <- function(data, metadata, design) {
  brohn_validate_design(design)
  brohn_require(is.data.frame(data) && nrow(data) >= 2L && nrow(data) <= 2000000L && !anyDuplicated(names(data)),
    "Raw gaze requires 2 to 2,000,000 samples with unique columns.")
  brohn_validate_raw_gaze_mapping(metadata, names(data))
  m <- metadata; p <- m$parameters; g <- m$geometry
  col <- function(name, fallback = "") if (brohn_text(m[[name]], 500)) data[[m[[name]]]] else rep(fallback, nrow(data))
  factor <- if (m$time_unit == "s") 1000 else 1
  d <- data.frame(source_row = seq_len(nrow(data)), participant_id = as.character(col("participant_column")),
    session_id = as.character(col("session_column")), stimulus_id = as.character(col("stimulus_column")),
    exposure_id = as.character(col("exposure_column")), condition_id = as.character(col("condition_column")),
    time = brohn_numeric(col("time_column"), "Sample times")*factor,
    x = brohn_numeric(col("x_column"), "Gaze x", TRUE), y = brohn_numeric(col("y_column"), "Gaze y", TRUE),
    valid = .brohn_gaze_boolean(col("valid_column"), "Gaze validity"),
    phase = if (brohn_text(m$phase_column, 500)) as.character(col("phase_column")) else "passive",
    stringsAsFactors = FALSE)
  for (field in c("participant_id", "session_id", "stimulus_id", "exposure_id", "phase"))
    brohn_require(!anyNA(d[[field]]) && all(nzchar(trimws(d[[field]]))), paste("Every sample needs", field))
  brohn_require(all(d$time >= 0 & d$time < 1e12), "Sample times need nonnegative relative clocks below 1e12 milliseconds.")
  brohn_require(all(!d$valid | is.finite(d$x) & is.finite(d$y)), "A sample declared valid has missing gaze coordinates. Correct its validity flag explicitly.")
  passive_value <- if (brohn_text(m$phase_column, 500)) m$phase_value else "passive"
  d$passive <- d$phase == passive_value
  brohn_require(any(d$passive), "No mapped passive-viewing samples are present.")
  d$blink <- if (brohn_text(m$blink_column, 500)) .brohn_gaze_boolean(col("blink_column"), "Blink labels") else FALSE
  d$valid <- d$valid & !d$blink
  for (side in c("left", "right")) {
    field <- paste0(side, "_valid_column")
    d[[paste0(side, "available")]] <- if (brohn_text(m[[field]], 500)) .brohn_gaze_boolean(col(field), paste(side, "eye availability")) else NA
  }
  pupil_present <- brohn_text(m$pupil_column, 500)
  d$pupil <- if (pupil_present) brohn_numeric(col("pupil_column"), "Pupil measurement", TRUE) else NA_real_
  d$pupil_valid <- if (pupil_present && brohn_text(m$pupil_valid_column, 500)) .brohn_gaze_boolean(col("pupil_valid_column"), "Pupil validity") else is.finite(d$pupil)
  d$pupil_valid <- d$pupil_valid & is.finite(d$pupil) & d$pupil > 0 & !d$blink
  features <- list(); observations <- list(); metric_rows <- list()
  emit <- function(record) {
    brohn_require(length(features) < 100000L, "Candidate/mask output exceeds 100,000 records; split the source into smaller recording jobs.")
    features[[length(features)+1L]] <<- record
  }
  common_for <- function(group, stimulus) list(participant_id = group$participant_id[[1]], session_id = group$session_id[[1]],
    exposure_id = group$exposure_id[[1]], stimulus_id = stimulus$id, condition_id = stimulus$condition_id)
  get_window <- function(group, start_name, end_name, name) {
    start <- brohn_numeric(data[[start_name]][group$source_row], paste(name, "starts"))*factor
    end <- brohn_numeric(data[[end_name]][group$source_row], paste(name, "ends"))*factor
    brohn_require(length(unique(start)) == 1L && length(unique(end)) == 1L && start[[1]] >= 0 && end[[1]] > start[[1]] && end[[1]] < 1e12,
      paste(name, "must have one declared nonnegative onset and later offset per exposure."))
    c(start = start[[1]], end = end[[1]])
  }
  for (ix in brohn_group(d, c("participant_id", "session_id", "exposure_id"))) {
    z <- d[ix, , drop = FALSE]
    brohn_require(length(unique(z$stimulus_id)) == 1L && z$stimulus_id[[1]] %in% brohn_ids(design$stimuli),
      "Each exposure must identify exactly one stimulus in the pinned study.")
    brohn_require(nrow(z) >= 2L && all(diff(z$time) > 0), "Sample clocks must strictly increase within each exposure. Duplicate/reversed samples cannot be silently sorted or merged.")
    stimulus <- brohn_find(design$stimuli, z$stimulus_id[[1]])
    brohn_require(all(!nzchar(z$condition_id) | z$condition_id == stimulus$condition_id), "Imported condition IDs disagree with the pinned stimulus.")
    if (!any(z$passive)) next
    common <- common_for(z, stimulus)
    brohn_require(!anyDuplicated(vapply(stimulus$aois, `[[`, character(1), "label")), "AOI labels must be distinct within a stimulus for comparisons.")
    n <- nrow(z); dt <- diff(z$time); left <- seq_len(n-1L); right <- left+1L
    declared <- brohn_text(m$exposure_start_column, 500)
    exposure <- if (declared) get_window(z, m$exposure_start_column, m$exposure_end_column, "Exposure") else
      c(start = min(z$time[z$passive]), end = max(z$time[z$passive]))
    brohn_require(exposure[[2]] > exposure[[1]], "Passive samples need a nonzero observed time span.")
    if (declared) brohn_require(all(z$time[z$passive] >= exposure[[1]] & z$time[z$passive] <= exposure[[2]]),
      "Passive samples fall outside the declared exposure window.")
    duration <- pmax(0, pmin(z$time[right], exposure[[2]])-pmax(z$time[left], exposure[[1]]))
    same_phase <- z$passive[left] & z$passive[right]
    observed <- same_phase & dt <= p$max_gap_ms & duration > 0
    usable <- observed & z$valid[left] & z$valid[right]
    angles <- .brohn_gaze_angles(z$x, z$y, g)
    velocity <- angles/dt*1000
    brohn_require(all(is.finite(velocity[usable])), "Declared geometry and valid coordinates do not yield finite angular velocities.")
    velocity[!usable] <- NA_real_
    classes <- rep("unusable", length(dt))
    classes[usable & velocity <= p$velocity_threshold_deg_s] <- "low_velocity"
    classes[usable & velocity > p$velocity_threshold_deg_s] <- "high_velocity"
    candidate_events <- list()
    for (classification in c("low_velocity", "high_velocity")) {
      minimum <- if (classification == "low_velocity") p$min_fixation_ms else p$min_saccade_ms
      for (segment in .brohn_gaze_runs(which(classes == classification))) {
        total <- sum(duration[segment])
        qualifies <- total + 1e-8 >= minimum
        kind <- if (classification == "low_velocity") "fixation_candidate" else "saccade_candidate"
        if (!qualifies) kind <- "short_unclassified_segment"
        weights <- duration[segment]
        x <- sum((z$x[segment]+z$x[segment+1L])/2*weights)/total
        y <- sum((z$y[segment]+z$y[segment+1L])/2*weights)/total
        aoi_ids <- lapply(Filter(function(a) .brohn_gaze_inside(x, y, a), stimulus$aois), `[[`, "id")
        record <- c(common, list(record_type = kind, classification = classification,
          start_ms = max(z$time[min(segment)], exposure[[1]]), end_ms = min(z$time[max(segment)+1L], exposure[[2]]),
          duration_ms = total, sample_count = length(segment)+1L,
          source_first_row = z$source_row[min(segment)], source_last_row = z$source_row[max(segment)+1L],
          x = x, y = y, peak_velocity_deg_s = max(velocity[segment]), angular_path_deg = sum(angles[segment]),
          aoi_ids = aoi_ids, qualified = FALSE,
          boundary_truncated = abs(z$time[min(segment)]-exposure[[1]]) < 1e-7 ||
            abs(z$time[max(segment)+1L]-exposure[[2]]) < 1e-7 ||
            (min(segment) > 1L && !usable[min(segment)-1L]) ||
            (max(segment) < length(usable) && !usable[max(segment)+1L])))
        candidate_events[[length(candidate_events)+1L]] <- record
        emit(record)
      }
    }
    if (length(candidate_events)) candidate_events <- candidate_events[order(vapply(candidate_events, `[[`, numeric(1), "start_ms"))]
    fixations <- Filter(function(e) e$record_type == "fixation_candidate", candidate_events)
    saccades <- Filter(function(e) e$record_type == "saccade_candidate", candidate_events)
    # Masks describe excluded source spans; nothing fills or joins across them.
    reasons <- list(invalid_gaze = observed & !(z$valid[left] & z$valid[right]),
      sample_gap = same_phase & dt > p$max_gap_ms & duration > 0,
      phase_boundary = xor(z$passive[left], z$passive[right]) & duration > 0)
    if (pupil_present) reasons$pupil_unavailable <- observed & !(z$pupil_valid[left] & z$pupil_valid[right])
    for (side in c("left", "right")) {
      availability <- z[[paste0(side, "available")]]
      if (!all(is.na(availability))) reasons[[paste0(side, "_eye_unavailable")]] <- observed &
        !(availability[left] & availability[right])
    }
    for (reason in names(reasons)) for (segment in .brohn_gaze_runs(which(reasons[[reason]])))
      emit(c(common, list(record_type = "quality_mask", reason = reason,
        start_ms = max(z$time[min(segment)], exposure[[1]]), end_ms = min(z$time[max(segment)+1L], exposure[[2]]),
        duration_ms = sum(duration[segment]))))
    valid_ms <- sum(duration[usable]); exposure_ms <- diff(exposure)[[1]]
    complete <- declared && abs(valid_ms-exposure_ms) < 1e-7
    for (aoi in stimulus$aois) {
      sample_hit <- .brohn_gaze_inside(z$x, z$y, aoi)
      inside_interval <- usable & sample_hit[left] & sample_hit[right]
      inside_ms <- sum(duration[inside_interval])
      crossing_ms <- sum(duration[usable & xor(sample_hit[left], sample_hit[right])])
      owned <- Filter(function(e) aoi$id %in% unlist(e$aoi_ids), fixations)
      dwell <- sum(vapply(owned, `[[`, numeric(1), "duration_ms"))
      first <- if (length(owned)) owned[[1]]$start_ms else NA_real_
      prior_ms <- if (is.finite(first)) sum(pmax(0, pmin(z$time[right], first)-pmax(z$time[left], exposure[[1]]))[usable]) else NA_real_
      prior_complete <- declared && is.finite(first) && abs(prior_ms-(first-exposure[[1]])) < 1e-7
      at_boundary <- is.finite(first) && abs(first-exposure[[1]]) < 1e-7
      status <- if (!declared) "unavailable_no_exposure_clock" else if (at_boundary) "left_boundary_candidate_onset_unknown" else
        if (is.finite(first) && prior_complete) "observed_fixation_candidate" else if (is.finite(first)) "unavailable_missing_prior_observation" else
          if (complete) "right_censored_no_fixation_candidate" else "unavailable_incomplete_observation"
      share <- if (valid_ms > 0) 100*inside_ms/valid_ms else NA_real_
      row <- c(common, list(aoi_id = aoi$id, aoi_label = aoi$label, valid_ms = valid_ms,
        inside_ms = inside_ms, valid_share_percent = .brohn_gaze_nullable(share), crossing_interval_ms = crossing_ms,
        fixation_candidate_count = length(owned), fixation_dwell_ms = if (valid_ms > 0) dwell else NULL,
        mean_fixation_duration_ms = if (length(owned)) dwell/length(owned) else NULL,
        first_observed_candidate_from_recorded_start_ms = if (is.finite(first)) first-min(z$time[z$passive]) else NULL,
        first_observed_candidate_from_exposure_ms = if (declared && is.finite(first)) first-exposure[[1]] else NULL,
        ttff_ms = if (status == "observed_fixation_candidate") first-exposure[[1]] else NULL,
        ttff_status = status, censor_time_ms = if (status == "right_censored_no_fixation_candidate") exposure_ms else NULL,
        exposure_duration_ms = if (declared) exposure_ms else NULL,
        observed_span_ms = max(z$time[z$passive])-min(z$time[z$passive]),
        complete_observation = complete, valid_coverage = valid_ms/exposure_ms,
        denominator = "valid adjacent-sample interval time; off-stimulus gaze retained",
        aoi_assignment = "both interval endpoints inside; crossing intervals remain unassigned; fixation candidates use duration-weighted centroid"))
      observations[[length(observations)+1L]] <- row
      for (metric in c("valid_gaze_share", "fixation_dwell")) metric_rows[[length(metric_rows)+1L]] <- data.frame(
        participant_id = common$participant_id, session_id = common$session_id, condition_id = common$condition_id,
        metric = metric, outcome_id = aoi$label, value = if (metric == "valid_gaze_share") share else if (valid_ms > 0) dwell else NA_real_,
        unit = if (metric == "valid_gaze_share") "percentage points" else "ms", stringsAsFactors = FALSE)
    }
    # Consecutive uniquely-owned fixation candidates may have an observed saccade
    # between them. Any missing/gap interval blocks the transition.
    if (length(fixations) > 1L) for (i in seq_len(length(fixations)-1L)) {
      from <- fixations[[i]]; to <- fixations[[i+1L]]
      between <- z$time[left] >= from$end_ms & z$time[right] <= to$start_ms
      if (length(from$aoi_ids) == 1L && length(to$aoi_ids) == 1L && !identical(from$aoi_ids, to$aoi_ids) &&
          all(usable[between])) emit(c(common, list(record_type = "aoi_transition", from_aoi = from$aoi_ids[[1]],
            to_aoi = to$aoi_ids[[1]], from_end_ms = from$end_ms, to_start_ms = to$start_ms)))
    }
    if (brohn_text(m$blink_column, 500)) for (segment in .brohn_gaze_runs(which(z$blink & z$passive))) {
      # Split an externally labelled run again at unsupported timestamp gaps.
      cuts <- split(segment, cumsum(c(TRUE, diff(z$time[segment]) > p$max_gap_ms)))
      for (block in cuts) emit(c(common, list(record_type = "source_labelled_blink", start_ms = z$time[min(block)],
        end_ms = z$time[max(block)], observed_duration_ms = z$time[max(block)]-z$time[min(block)],
        sample_count = length(block), onset_unobserved = min(block) == 1L || dt[min(block)-1L] > p$max_gap_ms,
        offset_unobserved = max(block) == n || dt[max(block)] > p$max_gap_ms, source = m$blink_source)))
    }
    if (pupil_present) {
      pupil_ok <- observed & z$pupil_valid[left] & z$pupil_valid[right]
      weight <- duration[pupil_ok]; means <- (z$pupil[left][pupil_ok]+z$pupil[right][pupil_ok])/2
      pupil_ms <- sum(weight); mean_pupil <- if (pupil_ms > 0) sum(means*weight)/pupil_ms else NA_real_
      baseline_mean <- NA_real_; baseline_coverage <- NA_real_; baseline_ms <- 0; baseline_status <- "not_requested"
      b <- m$pupil_baseline
      if (b$mode == "subtractive") {
        window <- get_window(z, b$start_column, b$end_column, "Pupil baseline")
        brohn_require(window[[2]] <= exposure[[1]], "The pupil baseline must precede the passive stimulus exposure.")
        weights <- pmax(0, pmin(z$time[right], window[[2]])-pmax(z$time[left], window[[1]]))
        good <- z$phase[left] == b$phase_value & z$phase[right] == b$phase_value & dt <= p$max_gap_ms &
          z$time[left] >= window[[1]] & z$time[right] <= window[[2]] &
          z$pupil_valid[left] & z$pupil_valid[right] & weights > 0
        baseline_ms <- sum(weights[good]); baseline_coverage <- baseline_ms/diff(window)[[1]]
        eligible <- baseline_ms >= b$minimum_duration_ms && baseline_coverage + 1e-8 >= b$minimum_coverage
        if (eligible) baseline_mean <- sum((z$pupil[left][good]+z$pupil[right][good])/2*weights[good])/baseline_ms
        baseline_status <- if (eligible) "eligible" else "excluded_insufficient_valid_baseline"
      }
      emit(c(common, list(record_type = "pupil_summary", unit = m$pupil_unit, source = m$pupil_source,
        valid_pupil_ms = pupil_ms, valid_pupil_coverage = pupil_ms/exposure_ms,
        mean_pupil = .brohn_gaze_nullable(mean_pupil), baseline_mean = .brohn_gaze_nullable(baseline_mean),
        baseline_valid_ms = baseline_ms, baseline_coverage = .brohn_gaze_nullable(baseline_coverage), baseline_status = baseline_status,
        baseline_corrected_mean = .brohn_gaze_nullable(mean_pupil-baseline_mean),
        integration = "trapezoid mean over adjacent valid samples wholly inside their window; no boundary/gap/blink interpolation")))
    }
    emit(c(common, list(record_type = "exposure_summary", sample_count = nrow(z), passive_sample_count = sum(z$passive),
      invalid_passive_sample_count = sum(z$passive & !z$valid), valid_interval_ms = valid_ms,
      unobserved_interval_ms = exposure_ms-valid_ms, complete_observation = complete,
      fixation_candidate_count = length(fixations), saccade_candidate_count = length(saccades),
      median_sample_interval_ms = stats::median(dt), maximum_sample_interval_ms = max(dt),
      left_eye_unavailable_samples = if (all(is.na(z$leftavailable))) NULL else sum(z$passive & !z$leftavailable),
      right_eye_unavailable_samples = if (all(is.na(z$rightavailable))) NULL else sum(z$passive & !z$rightavailable))))
  }
  values <- if (length(metric_rows)) do.call(rbind, metric_rows) else data.frame()
  list(kind = "gaze", title = "Raw gaze, fixation candidates and pupil responses", features = features,
    observations = observations, contrasts = if (nrow(values)) brohn_paired_contrasts(values, design$conditions) else list(),
    quality = list(source_rows = nrow(data), passive_rows = sum(d$passive), participant_count = length(unique(d$participant_id)),
      session_count = length(brohn_group(d, c("participant_id", "session_id"))),
      invalid_passive_samples = sum(d$passive & !d$valid), candidate_records = sum(vapply(features, function(e)
        e$record_type %in% c("fixation_candidate", "saccade_candidate"), logical(1))), qualified = FALSE),
    parameters = list(method = "brohn-adjacent-ray-ivt/0.1.0-draft", input = "raw_gaze_samples", thresholds = p,
      geometry = g, geometry_source = m$geometry_source, coordinate_space = "stimulus_normalized",
      time_unit = "ms", interpolation = "none", smoothing = "none", merging = "none",
      terminal_sample = "no inferred tail", edge_policy = "left/top included; right/bottom excluded",
      pupil_baseline = if (pupil_present) m$pupil_baseline else NULL),
    limitations = list("Fixed adjacent-ray I-VT candidates are not Tobii I-VT and are not device/annotation-qualified fixations or saccades.",
      "The declared rendered-stimulus geometry must apply to every exposure; moving heads, changing image placement and smooth pursuit need different profiles.",
      "No invalid sample or unsupported gap is interpolated. Sample intervals with only one valid endpoint are excluded and the final sample has no assumed duration.",
      "AOI gaze-time shares use endpoint-consistent intervals; crossing intervals are unassigned. Overlapping AOIs are evaluated independently, so shares can sum above 100 percent.",
      "TTFF requires an explicit actual exposure clock and adequate prior observation. A candidate already at the left boundary has unknown fixation onset; missing candidates never become zero latency.",
      "Blink outputs require external blink labels; generic track loss and unavailable eyes are not relabelled blinks. Pupil units and source validity remain explicit.",
      "Pupil differences depend on luminance, measurement geometry and protocol; these outputs do not supply universal attention, engagement or emotion scores."))
}
