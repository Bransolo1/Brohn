# Draft duration arithmetic for prepared intervals, not raw eye-tracker processing.
analyze_gaze_intervals <- function(study, intervals) {
  a <- record_assert
  study_errors <- validate_study(study)
  a(!length(study_errors), paste(study_errors, collapse = "; "))
  asset_errors <- validate_stimulus_assets(study$stimulus_assets, study$stimulus_ids)
  a(!length(asset_errors), paste(asset_errors, collapse = "; "))
  a(setequal(vapply(study$stimulus_assets, function(asset) asset$stimulus_id,
                    character(1)), study$stimulus_ids),
    "analysis: attach a valid PNG to both stimuli")
  aoi_errors <- validate_study_aois(study)
  a(!length(aoi_errors), paste(aoi_errors, collapse = "; "))
  a(length(study$aois) > 0L, "analysis: at least one bound rectangle AOI required")

  fields <- c("participant_id", "stimulus_id", "start_ms", "end_ms", "x", "y", "valid", "phase")
  a(is.data.frame(intervals) && !anyDuplicated(names(intervals)) &&
      setequal(names(intervals), fields), "intervals: exact prepared interval columns required")
  intervals <- intervals[, fields, drop = FALSE]
  text_column <- function(x) is.character(x) && is.null(dim(x)) &&
    !anyNA(x) && all(nzchar(trimws(x)))
  real_column <- function(x) is.numeric(x) && !is.complex(x) && is.null(dim(x))
  a(text_column(intervals$participant_id) && text_column(intervals$stimulus_id),
    "intervals: nonempty participant and stimulus IDs required")
  a(all(intervals$stimulus_id %in% study$stimulus_ids), "intervals: unknown stimulus ID")
  a(real_column(intervals$start_ms) && real_column(intervals$end_ms) &&
      all(is.finite(intervals$start_ms)) && all(is.finite(intervals$end_ms)) &&
      all(intervals$start_ms >= 0) && all(intervals$end_ms > intervals$start_ms),
    "intervals: finite nonnegative times in ms with end_ms > start_ms required")
  a(is.logical(intervals$valid) && is.null(dim(intervals$valid)) && !anyNA(intervals$valid),
    "intervals: valid must be logical with no missing values")
  a(text_column(intervals$phase) &&
      all(intervals$phase %in% c("passive_viewing", "active_response")),
    "intervals: phase must be passive_viewing or active_response")
  a(real_column(intervals$x) && real_column(intervals$y), "intervals: numeric x and y required")
  eligible_coordinates <- function(x) {
    x <- x[intervals$valid]
    all(is.finite(x)) && all(x >= 0 & x <= 1)
  }
  a(eligible_coordinates(intervals$x) && eligible_coordinates(intervals$y),
    "intervals: valid coordinates must be finite normalized image coordinates in [0,1]")

  # Sorting makes aggregation independent of input order; IDs are never joined
  # using a delimiter that could also occur in a participant or stimulus ID.
  intervals <- intervals[order(intervals$participant_id,
    match(intervals$stimulus_id, study$stimulus_ids), intervals$start_ms,
    intervals$end_ms, method = "radix"), , drop = FALSE]
  participants <- sort(unique(intervals$participant_id), method = "radix")
  labels <- sort(unique(vapply(study$aois, function(region) trimws(region$label),
                              character(1))), method = "radix")
  input_quality <- data.frame(participant_id = character(), stimulus_id = character(),
    condition = character(), interval_count = integer(), recorded_duration_ms = double(),
    valid_passive_interval_count = integer(), valid_passive_duration_ms = double(),
    invalid_passive_interval_count = integer(), invalid_passive_duration_ms = double(),
    active_interval_count = integer(), active_duration_ms = double(),
    gap_duration_ms = double(), stringsAsFactors = FALSE)
  per_aoi <- data.frame(participant_id = character(), stimulus_id = character(),
    condition = character(), aoi_id = character(), aoi_label = character(),
    valid_duration_ms = double(), inside_duration_ms = double(), share_pct = double(),
    stringsAsFactors = FALSE)
  pairs <- data.frame(participant_id = character(), aoi_label = character(),
    share_pct_a = double(), share_pct_b = double(), difference_pp = double(),
    included = logical(), reason_a = character(), reason_b = character(),
    exclusion_reason = character(), stringsAsFactors = FALSE)
  summary <- data.frame(aoi_label = character(), complete_pair_count = integer(),
    excluded_pair_count = integer(), mean_difference_pp = double(), stringsAsFactors = FALSE)

  for (participant in participants) {
    for (condition_index in seq_along(study$stimulus_ids)) {
      stimulus <- study$stimulus_ids[condition_index]
      condition <- study$conditions[condition_index]
      rows <- intervals[intervals$participant_id == participant &
                          intervals$stimulus_id == stimulus, , drop = FALSE]
      n <- nrow(rows)
      a(n < 2L || all(rows$start_ms[-1L] >= rows$end_ms[-n]),
        "intervals: overlapping intervals within participant/stimulus are not allowed")
      duration <- rows$end_ms - rows$start_ms
      passive <- rows$phase == "passive_viewing"
      valid_passive <- rows$valid & passive
      invalid_passive <- !rows$valid & passive
      active <- !passive
      denominator <- sum(duration[valid_passive])
      input_quality[nrow(input_quality) + 1L, ] <- list(participant, stimulus, condition,
        n, sum(duration), sum(valid_passive), denominator, sum(invalid_passive),
        sum(duration[invalid_passive]), sum(active), sum(duration[active]),
        if (n < 2L) 0 else sum(rows$start_ms[-1L] - rows$end_ms[-n]))
      regions <- Filter(function(region) identical(region$stimulus_id, stimulus), study$aois)
      regions <- regions[order(vapply(regions, function(region) trimws(region$label),
                                     character(1)), method = "radix")]
      points <- rows[valid_passive, c("x", "y"), drop = FALSE]
      for (region in regions) {
        # Half-open rectangle edges partition adjacent AOIs. The outer image
        # edge at 1 is included; clamp permitted floating-point overshoot only.
        right <- min(1, region$x + region$width)
        bottom <- min(1, region$y + region$height)
        inside <- points$x >= region$x & points$y >= region$y &
          (points$x < right | (right == 1 & points$x == 1)) &
          (points$y < bottom | (bottom == 1 & points$y == 1))
        numerator <- sum(duration[valid_passive][inside])
        per_aoi[nrow(per_aoi) + 1L, ] <- list(participant, stimulus, condition,
          region$id, trimws(region$label), denominator, numerator,
          if (denominator > 0) 100 * (numerator / denominator) else NA_real_)
      }
    }
    for (label in labels) {
      shares <- c(NA_real_, NA_real_)
      reasons <- c(NA_character_, NA_character_)
      for (side in seq_along(study$conditions)) {
        condition <- study$conditions[side]
        value <- per_aoi[per_aoi$participant_id == participant &
          per_aoi$condition == condition & per_aoi$aoi_label == label, , drop = FALSE]
        quality <- input_quality[input_quality$participant_id == participant &
          input_quality$condition == condition, , drop = FALSE]
        if (!nrow(value)) reasons[side] <- "missing_aoi"
        else if (quality$interval_count == 0L) reasons[side] <- "missing_intervals"
        else if (value$valid_duration_ms == 0) reasons[side] <- "zero_valid_passive_duration"
        else shares[side] <- value$share_pct
      }
      included <- all(is.na(reasons))
      exclusion <- if (included) NA_character_ else paste(
        paste0(study$conditions[!is.na(reasons)], ": ", reasons[!is.na(reasons)]),
        collapse = "; ")
      pairs[nrow(pairs) + 1L, ] <- list(participant, label, shares[1L], shares[2L],
        if (included) shares[2L] - shares[1L] else NA_real_, included,
        reasons[1L], reasons[2L], exclusion)
    }
  }
  for (label in labels) {
    selected <- pairs[pairs$aoi_label == label, , drop = FALSE]
    complete_count <- sum(selected$included)
    summary[nrow(summary) + 1L, ] <- list(label, complete_count,
      sum(!selected$included),
      if (complete_count > 0L) mean(selected$difference_pp[selected$included]) else NA_real_)
  }
  list(method_id = "aoi-valid-gaze-time-share/0.1.0-draft", status = "unqualified",
       time_unit = "ms", contrast = "B-A", input_quality = input_quality,
       per_aoi = per_aoi, pairs = pairs, summary = summary)
}
