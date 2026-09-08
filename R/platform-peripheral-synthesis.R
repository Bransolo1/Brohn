# Preserve the original feature row and match its exact supported interval.
# Fragmented exposures remain duplicate observations in the shared contrast
# engine until an explicit within-exposure aggregation recipe is implemented.
brohn_peripheral_synthesis_features <- function(body) {
  a <- body$analysis; modality <- a$kind; m <- a$parameters$mapping; p <- a$parameters$recipe
  reviewed <- body$provenance$mapping
  settings_ok <- tryCatch({
    brohn_validate_peripheral_mapping(reviewed, modality = modality)
    identical(brohn_hash(brohn_peripheral_parameters(reviewed, modality)), brohn_hash(p)) &&
      identical(a$operation, "peripheral") && identical(a$source$origin, body$origin) &&
      identical(a$source$sha256, body$provenance$source$hash) &&
      identical(brohn_hash(m[setdiff(names(m), c("origin", "parameters"))]),
                brohn_hash(reviewed[setdiff(names(reviewed), c("origin", "parameters"))]))
  }, error = function(e) FALSE)
  definition <- list(method = "calibrated-peripheral-supported-segments/1.0", recipe = p,
    mapping = m[intersect(names(m), c("value_columns", "unit", "sampling_rate", "time_unit", "timestamp_tolerance_s",
      "calibration_source", "sensor_site", "acquisition_filters", "recording_conditions", "axis_labels", "gravity_policy"))],
    filtering = a$parameters$filtering, resampling = a$parameters$resampling,
    imputation = a$parameters$imputation, duration = a$parameters$segment_duration,
    threshold_timing = a$parameters$threshold_timing,
    aggregation = "One supported contiguous source interval per observation; repeated intervals within one exposure need a separate reviewed aggregation recipe.")
  lapply(seq_along(a$features), function(i) {
    source <- a$features[[i]]
    matched <- Filter(function(s) identical(s$recording_id, source$recording_id) &&
      identical(s$support_segment_id, source$support_segment_id) && identical(s$channel, source$channel) &&
      identical(brohn_hash(s$group), brohn_hash(source$group)), a$segments)
    support <- if (length(matched) == 1L) matched[[1L]] else list(status = "unavailable")
    valid <- isTRUE(settings_ok) && length(matched) == 1L && identical(support$status, "usable") &&
      brohn_text(source$recording_id, 200) && brohn_text(source$support_segment_id, 200) &&
      brohn_text(source$channel, 200) && brohn_text(source$name, 200) && brohn_text(source$unit, 120) &&
      identical(source$scope, "recording") && brohn_number(source$value) &&
      brohn_number(support$sample_count, 2, 1000000, TRUE) && brohn_number(support$observed_span_s, .Machine$double.eps) &&
      brohn_number(support$minimum_duration_s, .Machine$double.eps) &&
      support$observed_span_s+1e-12 >= support$minimum_duration_s &&
      identical(brohn_hash(source$support), brohn_hash(support[c("sample_count", "observed_span_s")]))
    list(source = source, index = i, valid = valid,
      reason = if (valid) NULL else "missing_or_inconsistent_peripheral_interval_support",
      definition = c(definition, list(feature = source[intersect(names(source),
        c("name", "unit", "denominator", "integration", "negative_policy"))])), support = support)
  })
}
