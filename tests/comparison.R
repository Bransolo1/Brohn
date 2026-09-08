source("R/study.R")
source("R/records.R")
source("R/json.R")
source("R/comparison.R")

comparison_checks <- 0L
expect_comparison <- function(ok) {
  stopifnot(isTRUE(ok)); comparison_checks <<- comparison_checks + 1L
}
comparison_rejected <- function(expr) inherits(try(expr, silent = TRUE), "try-error")
comparison_study <- new_study()
comparison_bundle <- new_bundle(comparison_study,
  new_session(comparison_study, "control-draft", "not-enrolled", "preview"))
expect_comparison(identical(comparison_settings(comparison_study),
                           list(control_condition = "none", rationale = "")))
expect_comparison(!length(validate_comparison(comparison_study)))
expect_comparison(identical(revise_comparison(comparison_bundle, "none"), comparison_bundle))
expect_comparison(!"comparison" %in% names(comparison_bundle$study))
expect_comparison(isTRUE(all.equal(bundle_from_json(bundle_to_json(comparison_bundle)), comparison_bundle)))

for (value in list(NULL, "A", list(), list(control_condition = "A"),
  list(control_condition = "A", rationale = "", extra = TRUE),
  list(control_condition = "A", rationale = "", rationale = "again"))) {
  malformed <- comparison_study; malformed["comparison"] <- list(value)
  errors <- validate_comparison(malformed)
  expect_comparison(is.character(errors) && length(errors) > 0L)
  expect_comparison(comparison_rejected(comparison_settings(malformed)))
}
for (value in list("C", "a", "", " A ", NA_character_, NULL, 1, TRUE, c("A", "B"), list("A"))) {
  malformed <- comparison_study
  malformed$comparison <- list(control_condition = value, rationale = "")
  expect_comparison(length(validate_comparison(malformed)) > 0L)
}
for (value in list(NA_character_, NULL, 2, FALSE, c("a", "b"), list("a"), strrep("x", 2001))) {
  malformed <- comparison_study
  malformed$comparison <- list(control_condition = "A", rationale = value)
  expect_comparison(length(validate_comparison(malformed)) > 0L)
}
for (value in list(NULL, TRUE, 42, "study", new.env())) {
  errors <- validate_comparison(value)
  expect_comparison(is.character(errors) && length(errors) > 0L)
}
duplicate <- c(comparison_study, list(comparison = list(control_condition = "none", rationale = ""),
                                    comparison = list(control_condition = "A", rationale = "")))
expect_comparison(length(validate_comparison(duplicate)) > 0L)

designated <- revise_comparison(comparison_bundle, "A", "  Existing package  ")
expect_comparison(identical(designated$study$comparison,
                           list(control_condition = "A", rationale = "Existing package")))
expect_comparison(designated$study$revision == 2 && designated$session$study_revision == 2)
expect_comparison(identical(designated$session$mode, "preview"))
expect_comparison(identical(designated$study$analysis, comparison_bundle$study$analysis))
expect_comparison(identical(designated$study$stimulus_ids, comparison_bundle$study$stimulus_ids))
expect_comparison(identical(revise_comparison(designated, "A", " Existing package "), designated))
explanation <- revise_comparison(designated, "A", "Baseline package")
expect_comparison(explanation$study$revision == 3 && explanation$session$study_revision == 3)
switched <- revise_comparison(explanation, "B", "Baseline package")
expect_comparison(switched$study$revision == 4 && switched$session$study_revision == 4)
expect_comparison(identical(switched$study$analysis$contrast, "B-A"))
cleared <- revise_comparison(switched, "none")
expect_comparison(cleared$study$revision == 5 && identical(comparison_settings(cleared$study)$control_condition, "none"))
expect_comparison(identical(revise_comparison(cleared, "none", " "), cleared))
expect_comparison(isTRUE(all.equal(bundle_from_json(bundle_to_json(designated)), designated)))
expect_comparison(!length(validate_comparison(list(comparison =
  list(control_condition = "B", rationale = strrep("x", 2000))))))
expect_comparison(comparison_rejected(revise_comparison(designated, "A", strrep("x", 2001))))
expect_comparison(comparison_rejected(revise_comparison(designated, "C")))
expect_comparison(comparison_rejected(revise_comparison(designated, "A", NA_character_)))

for (mode in c("sample", "preview")) {
  editable <- comparison_bundle; editable$session$mode <- mode
  expect_comparison(identical(revise_comparison(editable, "B")$session$mode, mode))
}
for (mode in c("pilot", "live")) {
  readonly <- comparison_bundle; readonly$session$mode <- mode
  expect_comparison(comparison_rejected(revise_comparison(readonly, "A")))
  expect_comparison(comparison_rejected(revise_comparison(readonly, "none")))
}
clock <- new_clock("control-clock", "control-domain")
metadata <- comparison_bundle; metadata$clocks <- list(clock)
expect_comparison(!length(validate_bundle(metadata)))
expect_comparison(comparison_rejected(revise_comparison(metadata, "A")))
metadata$streams <- list(new_stream("control-stream", metadata$session, clock, "segment-1", "eye"))
expect_comparison(!length(validate_bundle(metadata)))
expect_comparison(comparison_rejected(revise_comparison(metadata, "A")))
metadata$events <- list(new_event(metadata$session, metadata$streams[[1]], clock,
  1, "0", "trial-1", "exposure-1", metadata$study$stimulus_ids[[1]],
  "epoch-1", "passive_viewing", "source_sample"))
expect_comparison(!length(validate_bundle(metadata)))
expect_comparison(comparison_rejected(revise_comparison(metadata, "A")))
invalid <- comparison_bundle; invalid$session$study_revision <- 999
expect_comparison(comparison_rejected(revise_comparison(invalid, "A")))
expect_comparison(comparison_rejected(revise_comparison(NULL, "A")))
expect_comparison(grepl("test minus control", comparison_caption(designated$study), fixed = TRUE))
expect_comparison(grepl("control minus test", comparison_caption(switched$study), fixed = TRUE))
expect_comparison(grepl("no designated control", comparison_caption(comparison_study), fixed = TRUE))
expect_comparison(grepl("does not establish causality", comparison_caption(designated$study), fixed = TRUE))
cat(sprintf("PASS: %d comparison checks\n", comparison_checks))
