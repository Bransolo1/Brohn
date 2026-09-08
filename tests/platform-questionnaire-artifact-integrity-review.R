# Independent compact-only corruption probes. No services or workers.
source("R/platform-core.R", encoding = "UTF-8")
source("R/platform-store.R", encoding = "UTF-8")
source("R/platform-vision.R", encoding = "UTF-8")
source("R/platform-questionnaire-artifacts.R", encoding = "UTF-8")
source("R/platform-questionnaire-artifact-storage.R", encoding = "UTF-8")
local({
  store <- brohn_open_store(tempfile("brohn-artifact-integrity-"))
  on.exit(brohn_close_store(store), add = TRUE)
  scratch <- file.path(store$root, "scratch", "original-compact-integrity")
  dir.create(scratch, recursive = TRUE)
  original <- list(title = "Original compact integrity probe", study_id = "study-original", dataset_id = NULL,
    origin = "sample", provenance = list(design_hash = strrep("a", 64), source_hash = strrep("b", 64)),
    analysis = list(kind = "questionnaire", title = "Original insufficient support", status = "needs_review",
      quality = list(usable = FALSE, response_count = 1, participant_count = NULL),
      features = list(list(question_id = "q-original", prompt = "Original quantity", response_count = 1,
        answered_count = 1, missing_count = 0, numeric_response_mean = 1/3,
        counts = list(list(value = 1/3, label = "Original third", count = 1)))),
      observations = list(list(question_id = "q-original", prompt = "Original quantity", value = 1/3))))
  packed <- brohn_pack_questionnaire_report(original, scratch, threshold = 1024)
  stopifnot(isTRUE(brohn_verify_questionnaire_worker_report(store, packed, scratch)))
  mutations <- list(
    scientific_status = function(a) {a$status <- "computed"; a},
    scientific_usability = function(a) {a$quality$usable <- TRUE; a},
    false_count = function(a) {a$questionnaire_artifact$counts$observations <- 0; a},
    false_preview_value = function(a) {a$preview$observations[[1L]]$value_display <- "999"; a},
    false_preview_mean = function(a) {a$preview$features[[1L]]$numeric_response_mean <- 999; a},
    foreign_title = function(a) {a$title <- "Qualified complete population result"; a},
    extra_scientific_array = function(a) {a$observations <- list(list(value = 999)); a})
  outcomes <- lapply(names(mutations), function(name) {
    changed <- packed; changed$analysis <- mutations[[name]](changed$analysis)
    error <- tryCatch({brohn_verify_questionnaire_worker_report(store, changed, scratch); NULL}, error = conditionMessage)
    list(case = name, rejected = !is.null(error), reason = error)
  })
  for (row in outcomes) cat(if (row$rejected) "PASS" else "FAIL", row$case, "\n")
  stopifnot(all(vapply(outcomes, `[[`, logical(1), "rejected")))
  rejected <- function(expr) inherits(try(force(expr), silent = TRUE), "try-error")
  stopifnot(rejected(brohn_promote_worker_artifacts(store, packed$analysis, scratch, NULL)))
  cat("PASS direct promotion requires the frozen report context\n")
  changed <- packed; changed$analysis$quality$usable <- TRUE
  stopifnot(rejected(brohn_promote_worker_artifacts(store, packed$analysis, scratch, NULL, report = changed)))
  cat("PASS direct promotion rejects a different analysis context\n")
  concealed <- packed$analysis; concealed$schema <- "brohn-other-analysis/1.0"; concealed$kind <- "gaze"
  stopifnot(rejected(.brohn_check_worker_artifacts(store, concealed, scratch)))
  cat("PASS staged manifest validation cannot disguise a questionnaire artifact as another family\n")
  cat("PASS: 10 compact integrity boundaries; original accepted; no scientific workers.\n")
})
