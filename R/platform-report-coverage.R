# Presentation of saved measurement support. Never recalculate scientific data.
brohn_measurement_coverage_supported <- function(a) {
  is.character(a$kind) && length(a$kind) == 1L &&
    a$kind %in% c("audio", "eeg", "eda", "ecg", "ppg", "respiration", "emg", "fnirs")
}
brohn_measurement_coverage_model <- function(a) {
  q <- a$quality
  if (!is.list(q)) q <- list()
  count <- function(value) is.numeric(value) && length(value) == 1L &&
    !is.na(value) && is.finite(value) && value >= 0 && value == floor(value)
  number <- function(value) format(value, digits = 17, scientific = FALSE, trim = TRUE, big.mark = ",")
  statements <- character()
  add <- function(text) statements <<- c(statements, text)
  pair <- function(numerator, denominator, text) {
    if (count(numerator) && count(denominator) && numerator <= denominator) {
      add(paste(number(numerator), "of", number(denominator), text)); TRUE
    } else FALSE
  }
  if (count(q$computed_channel_segments) && count(q$unavailable_channel_segments)) {
    add(paste(number(q$computed_channel_segments), if (q$computed_channel_segments == 1) "channel segment has processed results;" else "channel segments have processed results;",
      number(q$unavailable_channel_segments), "could not be processed with the saved settings."))
  }
  if (count(q$computed_recording_conditions) && count(q$unavailable_recording_conditions)) {
    add(paste(number(q$computed_recording_conditions), if (q$computed_recording_conditions == 1) "recording/condition combination has results;" else "recording/condition combinations have results;",
      number(q$unavailable_recording_conditions), "are unavailable."))
  }
  pair(q$retained_epoch_count, q$requested_event_count,
    "requested event epochs were retained. Repeated epochs are not independent people.")
  pair(q$computed_window_cells, q$requested_event_channel_cells,
    "requested event/channel windows have conductance summaries.")
  pair(q$computed_scr_cells, q$requested_event_channel_cells,
    "requested event/channel windows support a skin-conductance response estimate. Review each window's response and attribution status.")
  pair(q$channel_samples_retained, q$channel_samples_total,
    "channel samples were retained after the saved exclusions. Samples from different channels are counted separately.")
  if (count(q$missing_channel_samples) && q$missing_channel_samples > 0)
    add(paste(number(q$missing_channel_samples), "channel samples were missing."))
  if (count(q$invalid_amplitude_channel_samples) && q$invalid_amplitude_channel_samples > 0)
    add(paste(number(q$invalid_amplitude_channel_samples), "channel samples were outside the input profile's allowed amplitude range."))
  pair(q$invalid_or_missing_time_samples, q$source_time_samples,
    "source time points had missing or invalid selected-channel data.")
  if (identical(a$kind, "audio")) {
    if (identical(q$exact_silence, TRUE)) add("Every sample in the selected source channel is exactly zero.")
    if (count(q$full_scale_or_exceeding_samples) && q$full_scale_or_exceeding_samples > 0)
      add(paste(number(q$full_scale_or_exceeding_samples), "source samples reach or exceed digital full scale. Inspect the original waveform."))
  }
  complete <- Filter(function(item) is.list(item) && identical(item$complete, TRUE), a$artifacts)
  preview <- character()
  if (count(q$series_samples_displayed) && count(q$series_samples_total) && q$series_samples_displayed <= q$series_samples_total)
    preview <- c(preview, paste(number(q$series_samples_displayed), "of", number(q$series_samples_total),
      if (identical(a$kind, "audio")) "acoustic frame rows" else "processed series rows"))
  if (count(q$event_records_displayed) && count(q$event_records_total) && q$event_records_displayed <= q$event_records_total)
    preview <- c(preview, paste(number(q$event_records_displayed), "of", number(q$event_records_total), "saved event rows"))
  if (length(preview)) add(paste0("The report preview contains ", paste(preview, collapse = " and "), "."))
  if (length(complete)) add("Complete processed data remain available through the download controls; preview row counts do not limit the saved output.")
  if (!length(statements)) add("This saved report has no recognized summary counts. Inspect its original coverage details below.")
  list(statements = statements, quality = q,
    denominator_note = "Channel segments, samples, events and recording/condition combinations are different units; none is a count of independent participants.")
}
brohn_measurement_coverage_ui <- function(a) {
  model <- brohn_measurement_coverage_model(a)
  shiny::tagList(lapply(model$statements, shiny::p),
    shiny::p(class = "brohn-muted", model$denominator_note),
    shiny::tags$details(shiny::tags$summary("Inspect complete coverage details"),
      brohn_table(list(model$quality), label = "Complete saved measurement coverage")))
}
