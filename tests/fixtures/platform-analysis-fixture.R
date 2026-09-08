# Independent original acceptance data, derived from the declared researcher
# oracle rather than from an implementation output. All observations synthetic.
researcher_analysis_fixture <- function() {
  f <- brohn_read_json_file("tests/fixtures/researcher-scenarios.json")
  design <- brohn_new_design("Independent controlled packaging QA", id = "researcher-analysis")
  design$baseline_ms <- 10000
  for (i in 1:2) {
    design$stimuli[[i]]$content <- c("Current package", "Revised package")[[i]]
    design$stimuli[[i]]$aois <- list(list(id = paste0("logo-", i), label = "Logo", x = 0, y = 0, width = 0.5, height = 1))
  }
  gaze <- list(); explicit <- list()
  for (session in f$sessions) for (condition in c("A", "B")) {
    source <- session[[condition]]; stimulus <- paste0("stimulus-", tolower(condition))
    exposure <- paste0(session$session_id, "-", condition)
    row <- function(start, end, x, valid = TRUE, phase = "passive_viewing") data.frame(
      participant = session$participant_id, session = session$session_id, stimulus = stimulus,
      condition = paste0("condition-", tolower(condition)), exposure = exposure,
      start = start, end = end, x = x, y = if (valid) 0.5 else NA_real_, valid = if (valid) "true" else "false",
      phase = phase, stringsAsFactors = FALSE)
    if (session$session_id == "P01-S1" && condition == "A") {
      # Original independently specified mid-viewing gap and response period.
      for (interval in f$gaze_interval_oracle$intervals) gaze[[length(gaze)+1L]] <- row(
        interval$start, interval$end, if (is.null(interval$x)) NA_real_ else interval$x,
        interval$valid, interval$phase)
    } else {
      valid_ms <- source$valid_gaze_ms; inside <- source$logo_gaze_ms
      if (inside > 0) gaze[[length(gaze)+1L]] <- row(0, inside, 0.25)
      if (valid_ms > inside) gaze[[length(gaze)+1L]] <- row(inside, valid_ms, 0.75)
      if (valid_ms < 5000) gaze[[length(gaze)+1L]] <- row(valid_ms, 5000, NA_real_, FALSE)
      gaze[[length(gaze)+1L]] <- row(5000, 7000, 0.25, TRUE, "active_response")
    }
    explicit[[length(explicit)+1L]] <- data.frame(participant=session$participant_id,
      session=session$session_id, condition=paste0("condition-",tolower(condition)),
      stimulus=stimulus, exposure=exposure, question="q-liking", value=as.character(source$liking), stringsAsFactors=FALSE)
  }
  gaze <- do.call(rbind, gaze); explicit <- do.call(rbind, explicit)
  gaze_mapping <- list(origin_statement="Original fictional researcher QA data; not participant/device observations.",
    participant_column="participant",session_column="session",condition_column="condition",stimulus_column="stimulus",
    exposure_column="exposure",start_column="start",end_column="end",x_column="x",y_column="y",valid_column="valid",
    phase_column="phase",phase_value="passive_viewing",time_unit="ms",unit="stimulus_normalized")
  response_mapping <- list(origin_statement="Original fictional explicit ratings.",participant_column="participant",
    session_column="session",condition_column="condition",stimulus_column="stimulus",exposure_column="exposure",
    question_column="question",value_columns=list("value"),time_unit="ms",unit="numeric_rating")
  # Core import paths read strings; retain empty invalid coordinates explicitly.
  character_gaze <- as.data.frame(lapply(gaze, function(x) {x <- as.character(x); x[is.na(x)] <- ""; x}), stringsAsFactors=FALSE)
  list(design=design,gaze=character_gaze,responses=explicit,gaze_mapping=gaze_mapping,
    response_mapping=response_mapping,expected=f$expected_comparisons)
}
