source("R/platform-load.R", encoding = "UTF-8"); brohn_load(ui = FALSE)
for (name in c("candidate", "delivery", "score")) source(paste0("R/platform-sciat-window-", name, ".R"), encoding = "UTF-8")
source("R/platform-sciat-window.R", encoding = "UTF-8")
source("tests/fixtures/sciat-window-journal.R", encoding = "UTF-8")
checks <- list()
check <- function(name, value) { stopifnot(isTRUE(value)); checks[[length(checks) + 1L]] <<- list(name = name, pass = TRUE) }
reject <- function(expr) inherits(tryCatch({force(expr); NULL}, error = identity), "error")
near <- function(a, b) is.numeric(a) && is.numeric(b) && length(a) == length(b) && all(abs(a - b) < 1e-10)
block <- brohn_sciat_window_new(id = "scoring-test-task")
compiled <- brohn_sciat_window_compile(block)
trials <- Filter(function(t) t$type == "task_trial", compiled$timeline)
responses <- lapply(trials, function(t) list(trial_id = t$id, outcome = "response", response_outcome = "response",
  response_code = t$correct_code, response_ms = 500 + t$trial_index + if(t$mapping == "B")120 else 0, correct = TRUE))
original_hash <- brohn_hash(list(compiled, responses))
score <- brohn_sciat_window_score(compiled, responses)
expected_sd <- sqrt((2 * (72 * (72^2 - 1) / 12) + 2 * 72 * 60^2) / 143)
check("Full 192-trial result uses the explicit score recipe", score$eligible && score$status == "computed" && score$scoring_recipe == "brohn-sciat-response-window-score/1.0")
check("Practice is retained separately from all 144 test trials", score$counts$practice == 48 && score$counts$scored == 144 && score$counts$retained == 144)
check("Closed-form uniform-series variance agrees with the pooled original correct SD", near(score$scoring_audit$pooled_correct_sample_sd_ms, expected_sd))
check("Target-positive D agrees with independently derived mapping contrast", near(score$metrics[[1L]]$value, 120 / expected_sd))
check("Reference-package sign remains explicit", near(score$scoring_audit$reference_package_d, -120 / expected_sd))
check("Mapping means retain their exact source populations", near(score$scoring_audit$mapping$A$adjusted_mean_ms, 536.5) && near(score$scoring_audit$mapping$B$adjusted_mean_ms, 656.5))
check("Scoring leaves original design and responses unchanged", identical(original_hash, brohn_hash(list(compiled, responses))))
other <- brohn_sciat_window_compile(block, 2L)
other_trials <- Filter(function(t) t$type == "task_trial", other$timeline)
other_responses <- lapply(other_trials, function(t) list(trial_id = t$id, outcome = "response", response_outcome = "response",
  response_code = t$correct_code, response_ms = 500 + t$trial_index + if(t$mapping == "B")120 else 0, correct = TRUE))
reversed <- brohn_sciat_window_score(other, other_responses)
check("Opposite assigned order keeps the contrast's meaning", near(reversed$metrics[[1L]]$value, 120 / expected_sd) && reversed$scoring_audit$mapping_order == "B_then_A")
practice <- which(!vapply(trials, `[[`, logical(1), "scored"))
modified <- responses
for(i in practice) modified[[i]]$response_ms <- 0
check("Fast practice responses do not change test arithmetic", near(brohn_sciat_window_score(compiled, modified)$metrics[[1L]]$value, score$metrics[[1L]]$value))
test <- which(vapply(trials, `[[`, logical(1), "scored")); first <- test[1L]
wrong <- responses; wrong[[first]]$response_code <- setdiff(c("KeyE", "KeyI"), trials[[first]]$correct_code); wrong[[first]]$correct <- FALSE
error_score <- brohn_sciat_window_score(compiled, wrong)
check("Error replacement uses all original retained mapping responses", near(error_score$scoring_audit$mapping$A$error_replacement_base_ms, 536.5))
check("Error replacement is mapping mean plus 400, without correction latency", near(error_score$scoring_audit$rows[[1L]]$scoring_latency_ms, 936.5) && error_score$counts$retained_errors == 1)
missing <- responses; missing[[first]] <- list(trial_id = trials[[first]]$id, outcome = "omission", response_outcome = "omission", response_code = NULL, response_ms = NULL, correct = NULL)
missing_score <- brohn_sciat_window_score(compiled, missing)
check("Explicit omission has a separate denominator and remains in the audit", missing_score$counts$scored_timeouts == 1 && missing_score$counts$retained == 143 && missing_score$scoring_audit$rows[[1L]]$reason == "explicit_omission")
bad <- missing; bad[[first]]$correct <- FALSE
check("Omission accuracy cannot be invented", reject(brohn_sciat_window_score(compiled, bad)))
for (boundary in c(0, 349.999, 350, 1500)) {
  x <- responses; x[[first]]$response_ms <- boundary; s <- brohn_sciat_window_score(compiled, x)
  check(paste("Inclusive latency support", boundary), s$counts$removed_fast == as.integer(boundary < 350) && s$eligible)
}
bad <- responses; bad[[first]]$response_ms <- 1500.001
check("A post-deadline response cannot enter arithmetic", reject(brohn_sciat_window_score(compiled, bad)))
bad <- responses; bad[[first]]$correct <- FALSE
check("Accuracy must agree with the frozen key", reject(brohn_sciat_window_score(compiled, bad)))
bad <- responses; bad[[first]]$response_code <- "Space"
check("Only frozen response keys are accepted", reject(brohn_sciat_window_score(compiled, bad)))
bad <- responses; bad[[first]]$response_ms <- NA_real_
check("Missing latency is not a zero response", reject(brohn_sciat_window_score(compiled, bad)))
bad <- responses; bad[[2L]]$trial_id <- bad[[1L]]$trial_id
check("Duplicate frozen trial identity is rejected", reject(brohn_sciat_window_score(compiled, bad)))
bad <- responses; bad[[first]]$trial_id <- "unknown-trial"
check("Unknown trial identity is rejected", reject(brohn_sciat_window_score(compiled, bad)))
check("A missing trial suppresses the result", !brohn_sciat_window_score(compiled, responses[-first])$eligible)
check("Incomplete outer evidence suppresses the result", !brohn_sciat_window_score(compiled, responses, FALSE)$eligible)
bad <- responses; bad[[first]]$outcome <- "interrupted"
check("An interrupted trial suppresses the result", !brohn_sciat_window_score(compiled, bad)$eligible)
bad_compiled <- compiled; bad_compiled$timeline[[2L]]$timeout_ms <- 2000
check("Changed frozen procedure is rejected", reject(brohn_sciat_window_score(bad_compiled, responses)))
constant <- lapply(responses, function(r) {r$response_ms <- 600; r})
zero <- brohn_sciat_window_score(compiled, constant)
check("Zero correct-response variance is unavailable, not zero D", !zero$eligible && is.null(zero$metrics[[1L]]$value) && zero$reason == "zero_or_nonfinite_correct_response_variance")
low_accuracy <- responses
for (i in test[1:20]) {low_accuracy[[i]]$correct <- FALSE; low_accuracy[[i]]$response_code <- setdiff(c("KeyE", "KeyI"), trials[[i]]$correct_code)}
low <- brohn_sciat_window_score(compiled, low_accuracy)
check("Low response accuracy is retained as a QC flag, without silent exclusion", low$eligible && low$scoring_audit$qc$below_75pct_response_accuracy && !low$scoring_audit$qc$exclusion_applied)
journal <- original_sciat_window_journal(compiled)
replay <- brohn_sciat_window_replay(compiled, journal)
native <- lapply(Filter(function(e) e$payload$kind == "task_trial_finished", journal), function(e)e$payload$data)
check("Complete independently replayed original journal feeds the scorer", replay$complete && brohn_sciat_window_score(compiled, native)$eligible)
imported <- brohn_sciat_window_import_response(list(trial_id = "test", outcome = "incorrect", response_code = "KeyE", first_response_ms = 640, first_correct = FALSE))
check("Wrong first-response summary stays an error", imported$outcome == "response" && !imported$correct && imported$response_ms == 640)
omission <- brohn_sciat_window_import_response(list(trial_id = "test", outcome = "timeout", response_code = NULL, first_response_ms = NULL, first_correct = FALSE))
check("Summary omission conversion adds no observed accuracy", omission$outcome == "omission" && is.null(omission$correct))
# Every supported arithmetic edge must also survive the durable report boundary.
roundtrip <- function(value) brohn_parse(brohn_json(value))
for (name in c("score", "reversed", "error_score", "missing_score", "zero", "low")) {
  original <- get(name); saved <- roundtrip(original)
  check(paste("Durable report roundtrip", name), identical(brohn_hash(original), brohn_hash(saved)))
}
missing_row <- roundtrip(missing_score)$scoring_audit$rows[[1L]]
check("Omission audit retains explicit null latency, accuracy and scoring value", is.null(missing_row$latency_ms) &&
  is.null(missing_row$correct) && is.null(missing_row$scoring_latency_ms) && missing_row$reason == "explicit_omission")
for (boundary in c(0, 349.999, 350, 1500)) {
  x <- responses; x[[first]]$response_ms <- boundary
  saved <- roundtrip(brohn_sciat_window_score(compiled, x)); row <- saved$scoring_audit$rows[[1L]]
  check(paste("Durable original and scoring latency", boundary), near(row$latency_ms, boundary) &&
    if (boundary < 350) is.null(row$scoring_latency_ms) else near(row$scoring_latency_ms, boundary))
}
all_omitted <- responses
for(i in test) all_omitted[[i]] <- list(trial_id=trials[[i]]$id,outcome="omission",response_outcome="omission",response_code=NULL,response_ms=NULL,correct=NULL)
empty_saved <- roundtrip(brohn_sciat_window_score(compiled, all_omitted))
check("A complete administration without test responses saves unavailable with full null audit", !empty_saved$eligible &&
  is.null(empty_saved$metrics[[1L]]$value) && empty_saved$counts$scored_timeouts == 144 && length(empty_saved$scoring_audit$rows) == 144)
all_fast <- lapply(responses,function(r){r$response_ms <- 100; r})
fast_saved <- roundtrip(brohn_sciat_window_score(compiled,all_fast))
check("A complete all-fast administration saves exclusions rather than failing publication", !fast_saved$eligible &&
  fast_saved$counts$removed_fast == 144 && all(vapply(fast_saved$scoring_audit$rows,function(r)is.null(r$scoring_latency_ms),logical(1))))
args <- commandArgs(trailingOnly = TRUE)
if(length(args)) {dir.create(dirname(args[1L]), recursive = TRUE, showWarnings = FALSE); brohn_write_json_file(list(status = "passed", count = length(checks), checks = checks), args[1L])}
cat(length(checks), "SC-IAT scoring checks passed\n")
