source("tests/platform-methods-rt-support.R", encoding = "UTF-8")
source("R/platform-load.R", encoding = "UTF-8"); brohn_load(ui = TRUE)
local({
  count <- 0L
  check <- function(value, label) {if (!isTRUE(value)) stop(label, call. = FALSE); count <<- count + 1L}
  html <- function(value) htmltools::renderTags(value)$html
  report_for <- function(task) list(id = "original-rt-support-report", title = "Original RT support example",
    origin = "sample", status = "ready", analysis = list(kind = "questionnaire", task_scores = list(task),
      quality = list(), limitations = list()), provenance = list(), processing = list())
  original <- report_for(one_score); before <- brohn_hash(original)
  rendered <- html(brohn_report_content(original))
  check(grepl("Some measures unavailable", rendered, fixed = TRUE), "Partial task is visibly distinguished from complete support")
  check(grepl("97.5%", rendered, fixed = TRUE) && grepl("39 of 40 scored test trials had no response.", rendered, fixed = TRUE), "Omission percentage retains its exact test denominator")
  check(grepl("0 of 1 answered test trials had a wrong first answer.", rendered, fixed = TRUE), "Error denominator never silently becomes all test trials")
  check(grepl("500 ms", rendered, fixed = TRUE) && grepl("1 retained correct test responses; 1 needed for this measure.", rendered, fixed = TRUE), "One-response descriptive RT has visible support")
  check(grepl("At least two retained correct test responses", rendered, fixed = TRUE) && grepl("Unavailable", rendered, fixed = TRUE), "Missing sample SD has a comprehensible reason")
  check(grepl("brohn-rt-metric-support/1.0", rendered, fixed = TRUE) && grepl("sample_sd_divisor", rendered, fixed = TRUE), "Recipe and complete per-measure support remain inspectable")
  check(identical(before, brohn_hash(original)), "Rendering preserves exact report values and provenance")
  path <- tempfile(fileext = ".html"); on.exit(unlink(path), add = TRUE)
  brohn_export_report_html(original, path)
  offline <- paste(readLines(path, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  check(grepl("39 of 40 scored test trials", offline, fixed = TRUE) && grepl("Some measures unavailable", offline, fixed = TRUE), "Downloaded report keeps partial support explanations")
  no_answer <- metric(brohn_task_score(compiled, all_omitted), "test_first_response_error_rate")
  check(is.null(no_answer$value) && grepl("the error rate is unavailable", html(.brohn_task_metric_support_ui(no_answer)), fixed = TRUE), "No answers does not display a known zero error rate")
  legacy <- original
  legacy$analysis$task_scores[[1]]$status <- "computed"
  legacy$analysis$task_scores[[1]]$scoring_recipe <- NULL
  legacy$analysis$task_scores[[1]]$support_policy <- NULL
  legacy$analysis$task_scores[[1]]$metrics <- list(list(name = "IAT_D1", value = 0.5, unit = "D"))
  legacy_before <- brohn_hash(legacy); old_html <- html(brohn_report_content(legacy))
  check(grepl("0.5 D", old_html, fixed = TRUE) && !grepl("needed for this measure", old_html, fixed = TRUE), "Legacy metrics do not gain invented support counts")
  check(identical(legacy_before, brohn_hash(legacy)), "Historical report has no rendering migration")
  injected <- no_answer; injected$reason <- "<script>untrusted</script>"
  check(grepl("&lt;script&gt;", html(.brohn_task_metric_support_ui(injected)), fixed = TRUE), "Saved support explanations remain escaped")
  cat(sprintf("PASS: %d reaction-time report support checks\n", count))
})
