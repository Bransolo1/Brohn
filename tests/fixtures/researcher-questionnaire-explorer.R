# Original, explicitly synthetic complete-answer sources in a fresh QA workspace.
# No participant service, capture hardware or scientific scoring is started.
args <- commandArgs(trailingOnly = TRUE); mode <- args[[1L]]
source("R/platform-load.R", encoding = "UTF-8"); brohn_load(ui = TRUE)
folder <- normalizePath(args[[2L]], winslash = "/", mustWork = TRUE)
stopifnot(startsWith(basename(folder), "irp-questionnaire-explorer-"))
config_path <- file.path(folder, "fixture.json")
if (mode == "serve") {
  config <- brohn_read_json_file(config_path)
  Sys.setenv(BROHN_WORKSPACE = config$workspace, BROHN_APP_MODE = "platform")
  stop_owned <- function() if (file.exists(file.path(folder, "stop.request"))) shiny::stopApp() else later::later(stop_owned, .2)
  later::later(stop_owned, .2)
  shiny::runApp(".", host = "127.0.0.1", port = config$port, launch.browser = FALSE)
} else local({
  config <- if (file.exists(config_path)) brohn_read_json_file(config_path) else NULL
  stopifnot(mode != "setup" || is.null(config))
  store <- brohn_open_store(file.path(folder, "workspace")); on.exit(brohn_close_store(store), add = TRUE)
  if (mode == "setup") {
    brohn_initialise_library(store)
    design <- brohn_new_design("IRP complete-answer demonstration", "survey", "study-explorer-original")
    design$questions <- lapply(1:12, function(i) brohn_question(paste("Original question", i), "text", "end", paste0("q-original-", i)))
    brohn_put_entity(store, "study", design$id, design)
    long <- paste0(strrep("\u00e9\u6f22\U0001f512\n", 20000), "END OF ORIGINAL COMPLETE ANSWER")
    values <- c(list(0, FALSE, "0", NULL, "", list(0, FALSE, NULL), "<script>window.IRP_UNSAFE=true</script>", "=1+1", long), as.list(paste("Original answer", 10:720)))
    for (i in seq(12, 720, 12)) values[[i]] <- paste("Distinct saved value", i/12)
    observations <- lapply(seq_len(720), function(i) list(participant_id = if (i %% 2L) "unlinked:visit-a" else "alias:repeat-code",
      participant_linkage = i %% 2L == 0, session_id = paste0("visit-", if (i <= 360) "a" else "b"),
      question_id = paste0("q-original-", (i-1L) %% 12L+1L), prompt = paste("Original question", (i-1L) %% 12L+1L),
      occurrence_id = paste0("assessment-", i), step_id = paste0("step-", i), condition_id = "whole-study", stimulus_id = "repeated-label",
      origin = "sample", status = if (is.null(values[[i]])) "optional_omission" else "answered", value = values[[i]]))
    features <- lapply(1:12, function(i) list(question_id = paste0("q-original-", i), prompt = paste("Original question", i),
      condition_id = "whole-study", response_count = 60L, answered_count = if (i == 4) 59L else 60L, missing_count = if (i == 4) 1L else 0L,
      numeric_summary_status = "unavailable_categorical_or_structured_question", numeric_response_mean = NULL,
      counts = if (i == 12) lapply(1:60, function(j) list(value = paste("Distinct saved value", j), label = paste("Distinct saved value", j), count = 1L)) else list()))
    # Known distribution is specified independently of the adapter under test.
    body <- list(schema_version = "brohn-report/1.0.0", id = "report-explorer-original", title = "Complete saved answers - original synthetic fixture",
      study_id = design$id, dataset_id = NULL, origin = "sample", status = "Available", created_at = brohn_now(),
      provenance = list(design = design, design_hash = brohn_hash(design), fixture = "Independent original typed-record and distribution inspection fixture; no observed people or scientific qualification"),
      analysis = list(kind = "questionnaire", title = "Original complete records", observations = observations, features = features,
        quality = list(usable = TRUE, response_count = 720), limitations = list("Synthetic inspection fixture; not observed participant responses.")))
    staging <- file.path(folder, "source-staging"); dir.create(staging)
    packed <- brohn_pack_questionnaire_report(body, staging, threshold = 1024)
    a <- packed$analysis$artifacts[[1L]]; object <- brohn_store_object(store, path = a$path, media_type = "application/x-ndjson")
    packed$analysis$artifacts <- list(c(a[setdiff(names(a), c("path", "sha256", "bytes"))], object))
    report <- brohn_put_entity(store, "report", packed$id, packed)
    config <- list(schema = "irp-explorer-qa/1.0", workspace = store$root, port = httpuv::randomPort(min = 20000L, max = 49000L),
      original = list(study_id = design$id, study_title = design$title, report_id = report$id, report_hash = brohn_hash(report$body),
        answers = 720L, summaries = 12L, distribution = 60L, long_value_hash = digest::digest(charToRaw(enc2utf8(long)), algo = "sha256", serialize = FALSE)))
    # Optional retained receiver source is imported byte-for-byte into the fresh
    # store. It remains synthetic and never modifies the original QA workspace.
    if (length(args) >= 3L) {
      retained <- brohn_read_json_file(args[[3L]])
      old <- brohn_open_store(retained$workspace); on.exit(brohn_close_store(old), add = TRUE)
      saved <- brohn_get_entity(old, "report", retained$boundary$report_id)
      stopifnot(identical(saved$body$origin, "sample"))
      for (ref in c(saved$body$analysis$artifacts, list(saved$body$result_object))) if (!is.null(ref))
        stopifnot(identical(brohn_store_object(store, path = brohn_object_path(old, ref$hash), media_type = ref$media_type)$hash, ref$hash))
      study <- brohn_get_entity(old, "study", saved$body$study_id)
      brohn_put_entity(store, "study", study$id, study$body, project_id = study$project_id)
      copy <- brohn_put_entity(store, "report", saved$id, saved$body, project_id = saved$project_id)
      config$revision <- list(study_id = study$id, study_title = study$body$title, report_id = copy$id, report_hash = brohn_hash(copy$body),
        answers = 200L, history = 803L, source_artifact_bytes = retained$boundary$artifact$size,
        evidence = "Exact retained synthetic receiver output; source workspace untouched; source run is not present in this QA workspace")
    }
    brohn_write_json_file(config, config_path)
  } else if (mode == "inspect") {
    brohn_write_json_file(list(jobs = brohn_list_jobs(store, limit = 1000), indexes = brohn_list_entities(store, "questionnaire_index"),
      source_hash = brohn_hash(brohn_get_entity(store, "report", config$original$report_id)$body),
      resources = brohn_rows(DBI::dbGetQuery(store$con, "SELECT * FROM audit_log WHERE action='questionnaire_index.resources'"))), file.path(folder, "snapshot.json"))
  } else if (mode == "worker") {
    checks <- 0L; check <- function(label, ok) {stopifnot(isTRUE(ok)); checks <<- checks+1L; cat("PASS", label, "\n"); flush.console()}
    profile <- .brohn_questionnaire_worker_profile()
    rejects <- function(expr) inherits(try(force(expr), silent = TRUE), "try-error")
    check("Resident memory excess is rejected", rejects(.brohn_questionnaire_worker_check(profile, 0, 1024^3+1, 0)))
    check("Scratch excess is rejected", rejects(.brohn_questionnaire_worker_check(profile, 0, 0, 1024^3+1)))
    check("Deadline excess is rejected", rejects(.brohn_questionnaire_worker_check(profile, 301, 0, 0)))
    for (key in c("original", if (!is.null(config$revision)) "revision")) {
      source <- config[[key]]; report <- brohn_get_entity(store, "report", source$report_id)
      queued <- brohn_queue_questionnaire_index(store, report$id, report$revision, brohn_hash(report$body), report$project_id)
      claimed <- brohn_claim_job(store, paste0("qa-explorer-", key), 60)
      stopifnot(identical(claimed$id, queued$id)); t <- proc.time()[[3L]]
      brohn_process_job(store, claimed)
      job <- brohn_get_job(store, queued$id); if (job$status != "succeeded") stop(brohn_json(job$error))
      check(paste(key, "actual supervised index publication"), job$status == "succeeded")
      opened <- brohn_open_questionnaire_index(store, job$result$questionnaire_index_id, job$result$index_hash, report$id, report$revision, brohn_hash(report$body), report$project_id)
      page <- brohn_questionnaire_index_page(opened$handle, "answers"); keys <- character()
      repeat {keys <- c(keys, vapply(page$rows, `[[`, character(1), "record_key")); if (is.null(page$next_cursor)) break
        page <- brohn_questionnaire_index_page(opened$handle, "answers", cursor = page$next_cursor)}
      check(paste(key, "complete independently known source count with unique pages"), length(keys) == source$answers && !anyDuplicated(keys))
      check(paste(key, "reopening does not queue scientific work"), identical(brohn_queue_questionnaire_index(store, report$id, report$revision, brohn_hash(report$body), report$project_id)$id, job$id))
      check(paste(key, "original report unchanged"), identical(brohn_hash(brohn_get_entity(store, "report", report$id)$body), source$report_hash))
      brohn_close_questionnaire_index(opened)
      cat("MEASURE", key, "wall_seconds", proc.time()[[3L]]-t, "index_bytes", brohn_get_entity(store, "questionnaire_index", job$result$questionnaire_index_id)$body$index$size, "\n")
    }
    report <- brohn_get_entity(store, "report", config$original$report_id)
    retry <- brohn_queue_questionnaire_index(store, report$id, report$revision, brohn_hash(report$body), report$project_id, rebuild = TRUE)
    claimed <- brohn_claim_job(store, "qa-deadline", 60); before <- length(brohn_list_entities(store, "questionnaire_index"))
    brohn_process_job(store, claimed, timeout_seconds = .001)
    check("Actual child deadline failure publishes no partial index", brohn_get_job(store, retry$id)$status == "failed" && length(brohn_list_entities(store, "questionnaire_index")) == before)
    check("Complete source downloads survive failed preparation", identical(brohn_hash(brohn_complete_questionnaire_report(store, report$body)$analysis), report$body$analysis$questionnaire_artifact$analysis_sha256))
    brohn_write_json_file(list(passed = TRUE, checks = checks, jobs = brohn_list_jobs(store),
      resources = brohn_rows(DBI::dbGetQuery(store$con, "SELECT * FROM audit_log WHERE action='questionnaire_index.resources'"))), file.path(folder, "worker-evidence.json"))
    cat("PASS", checks, "actual-worker and resource assertions\n")
  } else stop("Unknown fixture mode")
})
