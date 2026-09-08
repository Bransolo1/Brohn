source("R/platform-load.R", encoding = "UTF-8"); brohn_load(ui = TRUE)
local({
  count <- 0L
  check <- function(value, label) {if (!isTRUE(value)) stop(label, call. = FALSE); count <<- count + 1L}
  score <- list(task_id = "original-task", title = "=Original title", profile = "rt-deary-liewald-choice/1.0",
    origin = "synthetic", design_hash = paste(rep("a", 64), collapse = ""), schema_version = "brohn-task-score/1.1",
    scoring_recipe = "brohn-rt-metric-support/1.0", status = "partial", eligible = TRUE, reason = "Insufficient SD support",
    participant_id = "001", participant_linkage = TRUE, session_id = "visit-original", counts = list(expected = 48, retained_correct = 1),
    metrics = list(list(name = "correct_test_rt_sd", value = NULL, unit = "ms", eligible = FALSE, reason = "Two responses needed",
      support = list(eligible_count = 1, minimum_count = 2)), list(name = "test_omission_rate", value = 39/40, unit = "proportion", eligible = TRUE,
      support = list(numerator = 39, denominator = 40))))
  report <- list(id = "original-mixed-report", origin = "sample", analysis = list(task_scores = list(score),
    observations = list(list(question_id = "original-rating", value = 5))))
  before <- brohn_hash(report); rows <- brohn_task_score_export_rows(report)
  check(length(rows) == 2L && all(vapply(rows, function(r) !anyDuplicated(names(r)), logical(1))), "No task/metric duplicate eligibility or reason keys")
  check(isTRUE(rows[[1]]$task_eligible) && identical(rows[[1]]$metric_eligible, FALSE) && is.null(rows[[1]]$value), "Unavailable SD stays unavailable in partially eligible administration")
  check(rows[[2]]$metric_support$denominator == 40 && rows[[2]]$value == 39/40, "Known omission fraction keeps exact support")
  check(rows[[1]]$collection_origin == "sample" && rows[[1]]$material_origin == "synthetic", "Collection and material origin remain distinct")
  path <- tempfile(fileext = ".csv"); general <- tempfile(fileext = ".csv")
  on.exit(unlink(c(path, general)), add = TRUE)
  brohn_export_task_scores_csv(report, path)
  table <- utils::read.csv(path, colClasses = "character", na.strings = character(), check.names = FALSE)
  check(nrow(table) == 2L && identical(table$participant_id, c("001", "001")), "Dedicated mixed-report export retains task rows and exact participant text")
  check(identical(table$metric_eligible, c("false", "true")) && identical(table$task_eligible, c("true", "true")), "CSV does not substitute administration eligibility for metric eligibility")
  check(table$value[[1]] == "" && as.numeric(table$value[[2]]) == 39/40, "Nullable unavailable value and numeric precision survive CSV")
  check(table$title[[1]] == "'=Original title", "Spreadsheet formula guard stays explicit in display CSV")
  check(brohn_parse(table$metric_support[[2]])$denominator == 40, "Nested support remains complete JSON in CSV")
  brohn_export_report_csv(report, general)
  check(nrow(utils::read.csv(general)) == 1L && "question_id" %in% names(utils::read.csv(general)), "General mixed observations export remains unchanged")
  only_tasks <- report; only_tasks$analysis$observations <- NULL
  brohn_export_report_csv(only_tasks, general)
  check(identical(readBin(path, "raw", n = file.info(path)$size), readBin(general, "raw", n = file.info(general)$size)), "Task-only fallback uses the same unambiguous fields")
  legacy <- score; legacy$metrics <- list(list(name = "IAT_D1", value = 0.12345678901234566, unit = "D")); legacy$scoring_audit <- list(original_count = 120L, retained_count = 119L)
  old <- report; old$analysis$task_scores <- list(legacy)
  old_rows <- brohn_task_score_export_rows(old)
  check(old_rows[[1]]$metric_eligibility_evidence == "legacy_task_eligibility_and_saved_value" && old_rows[[1]]$metric_eligible, "Legacy eligibility derivation is named rather than invented saved metadata")
  check(old_rows[[1]]$scoring_audit$retained_count == 119L, "Full legacy scorer audit is retained")
  unavailable <- score; unavailable$metrics <- list(); unavailable$eligible <- FALSE; unavailable$status <- "unavailable"
  old$analysis$task_scores <- list(unavailable)
  empty <- brohn_task_score_export_rows(old)
  check(length(empty) == 1L && !empty[[1]]$metric_eligible && is.null(empty[[1]]$metric), "Completely unavailable administrations are not silently dropped")
  check(identical(before, brohn_hash(report)), "All exports preserve immutable saved report")
  cat(sprintf("PASS: %d task-score export checks\n", count))
})
