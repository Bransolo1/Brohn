brohn_peripheral_report_ui <- function(a) {
  if (!identical(a$operation, "peripheral")) return(NULL)
  q <- a$quality; temperature <- identical(a$kind, "temperature")
  rows <- lapply(a$segments, function(s) {
    features <- Filter(function(f) identical(f$recording_id, s$recording_id) &&
      identical(f$support_segment_id, s$support_segment_id), a$features)
    value <- function(name) {
      matched <- Filter(function(f) identical(f$name, name), features)
      if (length(matched) == 1L) matched[[1L]]$value else NULL
    }
    base <- list(participant = s$group$participant_id, session = s$group$session_id,
      condition = s$group$condition_id, exposure = s$group$exposure_id,
      interval = s$support_segment_id, support = if (s$status == "usable") "Available" else gsub("_", " ", s$reason),
      observed_seconds = s$observed_span_s, samples = s$sample_count)
    if (temperature) c(base, list(mean_c = value("temperature_mean"), sd_c = value("temperature_sd"),
      endpoint_change_c = value("temperature_endpoint_change"))) else c(base, list(
      mean_magnitude_ms2 = value("acceleration_magnitude_mean"), rms_magnitude_ms2 = value("acceleration_magnitude_rms"),
      rms_vector_derivative_ms3 = value("acceleration_vector_derivative_rms")))
  })
  brohn_card(title = if (temperature) "Temperature in the recorded intervals" else "Acceleration in the recorded intervals",
    shiny::p(if (isTRUE(q$usable)) paste(q$usable_samples, "usable samples across", format(signif(q$supported_observed_span_s, 6), trim = TRUE),
      "seconds of supported intervals. Each interval remains separate below.") else "No interval has enough usable data for these calculations. Missing results remain unavailable."),
    shiny::p(paste(q$invalid_samples, "invalid or missing samples;", q$insufficient_duration_samples, "valid samples in intervals shorter than the selected minimum.")),
    shiny::p(if (!isTRUE(q$event_detection_requested)) "Threshold detection was disabled." else if (is.null(q$event_count))
      "Threshold detection was requested, but no interval has usable support. The number of events is unavailable." else
      paste(q$event_count, "excursions met your declared threshold and observed-duration settings. Boundaries and censoring are retained in the complete event artifact.")),
    shiny::p(class = "brohn-muted", if (temperature) "Values are converted to degrees Celsius. Endpoint change compares the last and first observed sample within an interval; it is not a physiological baseline contrast." else
      "Values are converted to m/s2. Magnitude and vector derivative can include gravity, rotation and sensor noise; they do not establish displacement or activity intensity."),
    brohn_table(rows, maximum = 40, label = "Calibrated peripheral intervals"),
    shiny::p(class = "brohn-muted", "Counts describe samples and intervals, not independent people. Use reviewed identity links and declared comparisons to combine this report with other study measures."))
}
