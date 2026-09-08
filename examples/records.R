source("R/study.R")
source("R/comparison.R")
source("R/presentation.R")
source("R/records.R")
source("R/json.R")
source("R/assets.R")
source("R/aois.R")

sample_bundle <- function(include_liking = TRUE) {
  study <- new_study(include_liking = include_liking)
  run <- new_session(study, "sample-run", "synthetic-participant", "sample")
  clock <- new_clock("browser-clock", "browser-navigation-1", unit = "ns")
  stream <- new_stream("browser-runner", run, clock, "segment-1",
                       if (include_liking) "questionnaire" else "eye")
  events <- if (include_liking) lapply(seq_len(3), function(i) {
    status <- c("unanswered", "skipped", "answered")[[i]]
    response <- new_response(study$questions[[1]], status,
                             if (status == "answered") "like-6" else NULL)
    new_event(run, stream, clock, i, paste0("123456789012345678", i),
              "trial-a", "exposure-a", "stimulus-a", "rating-epoch",
              "active_response", "response_observed", response)
  }) else list()
  new_bundle(study, run, list(clock), list(stream), events)
}
# Fixtures only: no participant actions, completed sessions or recording implied.
