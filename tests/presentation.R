source("R/study.R")
source("R/records.R")
source("R/json.R")
source("R/comparison.R")
source("R/presentation.R")

presentation_checks <- 0L
expect_presentation <- function(ok) {
  stopifnot(isTRUE(ok)); presentation_checks <<- presentation_checks + 1L
}
presentation_rejected <- function(expr) inherits(try(expr, silent = TRUE), "try-error")
presentation_study <- new_study()
presentation_bundle <- new_bundle(presentation_study,
  new_session(presentation_study, "presentation-draft", "not-enrolled", "preview"))
expect_presentation(identical(presentation_settings(presentation_study),
  list(order = "counterbalanced_ab_ba", viewing_duration_ms = 5000)))
expect_presentation(!length(validate_presentation(presentation_study)))
expect_presentation(identical(revise_presentation(presentation_bundle,
  "counterbalanced_ab_ba", 5000L), presentation_bundle))
expect_presentation(!"presentation" %in% names(presentation_bundle$study))

plans <- preview_presentation(presentation_study)
expect_presentation(identical(names(plans), c("AB", "BA")))
expected_columns <- c("position", "stimulus_id", "condition", "role", "phase", "planned_duration_ms")
for (order in names(plans)) {
  plan <- plans[[order]]
  expect_presentation(is.data.frame(plan) && identical(names(plan), expected_columns))
  expect_presentation(identical(plan$position, 1:4))
  expect_presentation(identical(plan$condition,
    if (order == "AB") c("A", "A", "B", "B") else c("B", "B", "A", "A")))
  expect_presentation(identical(plan$stimulus_id,
    if (order == "AB") c("stimulus-a", "stimulus-a", "stimulus-b", "stimulus-b") else
      c("stimulus-b", "stimulus-b", "stimulus-a", "stimulus-a")))
  expect_presentation(identical(plan$phase,
    c("passive_viewing", "active_response", "passive_viewing", "active_response")))
  expect_presentation(identical(plan$planned_duration_ms, c(5000, NA_real_, 5000, NA_real_)))
  expect_presentation(identical(plan$role, rep("comparison", 4)))
}
for (order in c("fixed_ab", "fixed_ba")) {
  revised <- revise_presentation(presentation_bundle, order, 12345)
  expected_order <- if (order == "fixed_ab") "AB" else "BA"
  plan <- preview_presentation(revised$study)
  expect_presentation(identical(names(plan), expected_order))
  expect_presentation(identical(plan[[1]]$condition, plans[[expected_order]]$condition))
  expect_presentation(identical(plan[[1]]$planned_duration_ms, c(12345, NA_real_, 12345, NA_real_)))
  expect_presentation(revised$study$revision == 2 && revised$session$study_revision == 2)
  expect_presentation(identical(revised$study$stimulus_ids, presentation_study$stimulus_ids))
  expect_presentation(identical(revised$study$conditions, presentation_study$conditions))
  expect_presentation(identical(revised$study$analysis, presentation_study$analysis))
  expect_presentation(identical(revised$study$questions, presentation_study$questions))
  expect_presentation(identical(revise_presentation(revised, order, 12345L), revised))
  expect_presentation(isTRUE(all.equal(bundle_from_json(bundle_to_json(revised)), revised)))
}
without_question <- preview_presentation(new_study(include_liking = FALSE))
for (plan in without_question) {
  expect_presentation(nrow(plan) == 2 && identical(plan$position, 1:2))
  expect_presentation(identical(plan$phase, rep("passive_viewing", 2)))
  expect_presentation(identical(plan$planned_duration_ms, c(5000, 5000)))
  expect_presentation(setequal(plan$condition, c("A", "B")) && !anyDuplicated(plan$stimulus_id))
}
controlled <- revise_comparison(presentation_bundle, "A", "Existing design")
reversed <- revise_presentation(controlled, "fixed_ba", 9000)
control_plan <- preview_presentation(reversed$study)$BA
expect_presentation(identical(control_plan$role, c("test", "test", "control", "control")))
expect_presentation(identical(control_plan$condition, c("B", "B", "A", "A")))
expect_presentation(identical(control_plan$stimulus_id,
  c("stimulus-b", "stimulus-b", "stimulus-a", "stimulus-a")))
expect_presentation(identical(reversed$study$comparison, controlled$study$comparison))
expect_presentation(identical(reversed$study$analysis$contrast, "B-A"))
expect_presentation(reversed$study$revision == 3 && reversed$session$study_revision == 3)
controlled_b <- revise_comparison(presentation_bundle, "B")
expect_presentation(identical(preview_presentation(controlled_b$study)$AB$role,
  c("test", "test", "control", "control")))

for (value in list(NULL, "fixed_ab", list(), list(order = "fixed_ab"),
  list(order = "fixed_ab", viewing_duration_ms = 5000, extra = TRUE),
  list(order = "fixed_ab", viewing_duration_ms = 5000, order = "fixed_ba"))) {
  malformed <- presentation_study; malformed["presentation"] <- list(value)
  errors <- validate_presentation(malformed)
  expect_presentation(is.character(errors) && length(errors) > 0L)
  expect_presentation(presentation_rejected(presentation_settings(malformed)))
  expect_presentation(presentation_rejected(preview_presentation(malformed)))
}
for (order in list("AB", "random", " fixed_ab ", NA_character_, NULL, 1, TRUE,
                   c("fixed_ab", "fixed_ba"), matrix("fixed_ab"))) {
  expect_presentation(presentation_rejected(revise_presentation(presentation_bundle, order, 5000)))
}
for (duration in list(499, 600001, 500.5, Inf, -Inf, NaN, NA_real_, NULL,
                     "5000", TRUE, c(5000, 6000), matrix(5000), 1 + 1i)) {
  malformed <- presentation_study
  malformed$presentation <- list(order = "fixed_ab", viewing_duration_ms = duration)
  errors <- validate_presentation(malformed)
  expect_presentation(is.character(errors) && length(errors) > 0L)
  expect_presentation(presentation_rejected(revise_presentation(presentation_bundle, "fixed_ab", duration)))
}
for (duration in c(500, 600000)) {
  boundary <- revise_presentation(presentation_bundle, "counterbalanced_ab_ba", duration)
  expect_presentation(!length(validate_presentation(boundary$study)))
  expect_presentation(all(vapply(preview_presentation(boundary$study), function(plan)
    identical(plan$planned_duration_ms[c(1, 3)], rep(duration, 2)), logical(1))))
}
for (value in list(NULL, TRUE, 42, "study", new.env())) {
  errors <- validate_presentation(value)
  expect_presentation(is.character(errors) && length(errors) > 0L)
}
duplicate <- c(presentation_study,
  list(presentation = list(order = "fixed_ab", viewing_duration_ms = 5000),
       presentation = list(order = "fixed_ba", viewing_duration_ms = 5000)))
expect_presentation(length(validate_presentation(duplicate)) > 0L)
invalid_study <- presentation_study; invalid_study$conditions <- c("B", "A")
expect_presentation(presentation_rejected(preview_presentation(invalid_study)))
for (mode in c("sample", "preview")) {
  editable <- presentation_bundle; editable$session$mode <- mode
  expect_presentation(identical(revise_presentation(editable, "fixed_ab", 5000)$session$mode, mode))
}
for (mode in c("pilot", "live")) {
  readonly <- presentation_bundle; readonly$session$mode <- mode
  expect_presentation(presentation_rejected(revise_presentation(readonly, "fixed_ab", 5000)))
  expect_presentation(presentation_rejected(revise_presentation(readonly, "counterbalanced_ab_ba", 5000)))
}
clock <- new_clock("presentation-clock", "presentation-domain")
metadata <- presentation_bundle; metadata$clocks <- list(clock)
expect_presentation(!length(validate_bundle(metadata)))
expect_presentation(presentation_rejected(revise_presentation(metadata, "fixed_ab", 5000)))
metadata$streams <- list(new_stream("presentation-stream", metadata$session, clock, "segment-1", "eye"))
expect_presentation(!length(validate_bundle(metadata)))
expect_presentation(presentation_rejected(revise_presentation(metadata, "fixed_ab", 5000)))
metadata$events <- list(new_event(metadata$session, metadata$streams[[1]], clock,
  1, "0", "trial-1", "exposure-1", metadata$study$stimulus_ids[[1]],
  "epoch-1", "passive_viewing", "source_sample"))
expect_presentation(!length(validate_bundle(metadata)))
expect_presentation(presentation_rejected(revise_presentation(metadata, "fixed_ab", 5000)))
invalid_bundle <- presentation_bundle; invalid_bundle$session$study_revision <- 999
expect_presentation(presentation_rejected(revise_presentation(invalid_bundle, "fixed_ab", 5000)))
expect_presentation(presentation_rejected(revise_presentation(NULL, "fixed_ab", 5000)))
cat(sprintf("PASS: %d presentation checks\n", presentation_checks))
