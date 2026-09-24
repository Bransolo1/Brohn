source("R/platform-load.R", encoding = "UTF-8"); brohn_load(ui = TRUE)
source("R/platform-report-coverage.R", encoding = "UTF-8")
local({
  checks <- character()
  check <- function(label, value) {stopifnot(isTRUE(value)); checks <<- c(checks, label); cat("PASS", label, "\n")}
  text <- function(a) paste(brohn_measurement_coverage_model(a)$statements, collapse = " ")
  a <- list(kind = "emg", quality = list(computed_channel_segments = 2, unavailable_channel_segments = 1,
    channel_samples_retained = 1600, channel_samples_total = 2000, missing_channel_samples = 300,
    invalid_amplitude_channel_samples = 10, series_samples_displayed = 100, series_samples_total = 1700,
    event_records_displayed = 0, event_records_total = 0), artifacts = list(list(complete = TRUE)))
  check("Saved channel support is expressed without inventing person counts", grepl("2 channel segments.*1 could not", text(a)))
  check("Sample numerator and denominator remain exact and channel-specific", grepl("1,600 of 2,000 channel samples", text(a), fixed = TRUE))
  check("Missing and inadmissible samples keep separate recorded counts", grepl("300 channel samples were missing", text(a), fixed = TRUE) && grepl("10 channel samples were outside", text(a), fixed = TRUE))
  check("A zero event count remains zero saved rows, not no physiological activity", grepl("0 of 0 saved event rows", text(a), fixed = TRUE) && !grepl("no activity", text(a), fixed = TRUE))
  check("Bounded preview and complete stored output are explicitly separate", grepl("100 of 1,700 processed series rows", text(a), fixed = TRUE) && grepl("Complete processed data remain available", text(a), fixed = TRUE))
  a$artifacts <- list(list(complete = FALSE)); check("Incomplete artifacts never promise complete downloads", !grepl("Complete processed data remain available", text(a), fixed = TRUE))
  a$quality$channel_samples_retained <- 2001
  check("Contradictory sample totals are not presented as a valid ratio", !grepl("channel samples were retained", text(a), fixed = TRUE))
  invalid <- list(missing = NULL, unknown = NA_real_, infinite = Inf, negative = -1,
    fractional = .5, boolean = TRUE, text = "10", multiple = c(1, 2))
  for (name in names(invalid)) {
    value <- invalid[[name]]
    b <- list(kind = "emg", quality = list(computed_channel_segments = value, unavailable_channel_segments = 1))
    check(paste("Absent or invalid count is not invented:", name), !grepl("channel segments have", text(b), fixed = TRUE))
  }
  audio <- list(kind = "audio", quality = list(series_samples_displayed = 20, series_samples_total = 30,
    exact_silence = TRUE, full_scale_or_exceeding_samples = 2))
  check("Audio frame rows are not mislabeled raw source samples", grepl("20 of 30 acoustic frame rows", text(audio), fixed = TRUE))
  check("Saved silence and full-scale evidence retain literal meanings", grepl("exactly zero", text(audio), fixed = TRUE) && grepl("2 source samples reach or exceed digital full scale", text(audio), fixed = TRUE))
  eeg <- list(kind = "eeg", quality = list(computed_recording_conditions = 3, unavailable_recording_conditions = 1,
    retained_epoch_count = 6, requested_event_count = 8))
  check("Epoch and recording/condition denominators remain distinct", grepl("3 recording/condition combinations", text(eeg), fixed = TRUE) && grepl("6 of 8 requested event epochs", text(eeg), fixed = TRUE))
  eda <- list(kind = "eda", quality = list(computed_window_cells = 4, computed_scr_cells = 2, requested_event_channel_cells = 5))
  check("EDA conductance-window and SCR support remain distinct", grepl("4 of 5 requested event/channel windows have conductance summaries", text(eda), fixed = TRUE) && grepl("2 of 5 requested event/channel windows support", text(eda), fixed = TRUE))
  fnirs <- list(kind = "fnirs", quality = list(invalid_or_missing_time_samples = 2, source_time_samples = 100))
  check("fNIRS missing time points are not counted as independent channels", grepl("2 of 100 source time points", text(fnirs), fixed = TRUE))
  unknown <- list(kind = "eda", quality = list(original_future_field = "<script>unsafe</script>"))
  rendered <- htmltools::renderTags(brohn_measurement_coverage_ui(unknown))$html
  check("Historical unknown counts explain absence without guessing zero", grepl("no recognized summary counts", rendered, fixed = TRUE) && !grepl("0 of", rendered, fixed = TRUE))
  check("Unknown source fields remain escaped in expandable exact details", grepl("<details>", rendered, fixed = TRUE) && grepl("&lt;script&gt;", rendered, fixed = TRUE) && !grepl("<script>unsafe", rendered, fixed = TRUE))
  check("Unrelated task and questionnaire profiles retain their existing coverage", !brohn_measurement_coverage_supported(list(kind = "questionnaire")) && !brohn_measurement_coverage_supported(list(kind = "implicit")))
  original <- list(kind = "audio", quality = list(series_samples_total = 1000, series_samples_displayed = 100))
  saved <- brohn_hash(original); invisible(brohn_measurement_coverage_ui(original))
  check("Coverage rendering leaves every original value unchanged", identical(saved, brohn_hash(original)))
  folder <- Sys.getenv("BROHN_REPORT_COVERAGE_TEST_ROOT", tempfile("brohn-report-coverage-"))
  stopifnot(!dir.exists(folder)); dir.create(folder, recursive = TRUE)
  brohn_write_json_file(list(passed = TRUE, checks = as.list(checks), scope = "Pure presentation of independently authored saved support; no scoring or device claim",
    source_sha256 = digest::digest(file = "R/platform-report-coverage.R", algo = "sha256")), file.path(folder, "results.json"))
  cat(length(checks), "checks passed;", folder, "\n")
})
