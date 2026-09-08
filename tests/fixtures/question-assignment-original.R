# Original synthetic mixed-code questionnaire, independent of saved workspaces.
brohn_assignment_fixture <- function() {
  d <- brohn_new_design("Original option assignment fixture", "comparison", "study-assignment")
  d$instructions <- ""; d$fixation_ms <- 0L; d$order <- "fixed"
  for (i in seq_along(d$stimuli)) {
    d$stimuli[[i]]$content <- paste("Original concept", i)
    d$stimuli[[i]]$duration_ms <- 100L
  }
  q <- brohn_question("Choose an original typed answer", "single_choice", "before", "q-original")
  q$option_assignment <- NULL # Deliberately emulate the pre-policy schema.
  q$randomize_options <- TRUE
  codes <- list(0, FALSE, "0", "1", 1, TRUE)
  labels <- c("Number zero", "Boolean false", "Text zero", "Text one", "Number one", "Boolean true")
  q$options <- lapply(seq_along(codes), function(i) list(id = paste0("choice", i), label = labels[[i]], value = codes[[i]]))
  after <- q; after$id <- "q-after"; after$scope <- "after_each"; after$prompt <- "Choose after this concept"
  end <- q; end$id <- "q-end"; end$scope <- "end"; end$prompt <- "Choose at the end"
  d$questions <- list(q, after, end)
  d
}
