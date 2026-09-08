# Browser-only retained-report fixture. setup adds a separately labelled original
# arithmetic source report; it does not rewrite the accepted-run boundary study.
# No worker or participant service is launched by this helper.
args <- commandArgs(trailingOnly = TRUE); mode <- args[[1L]]
source("R/platform-load.R", encoding = "UTF-8"); brohn_load(ui = TRUE)
folder <- normalizePath(args[[2L]], winslash = "/", mustWork = TRUE)
stopifnot(startsWith(basename(folder), "brohn-questionnaire-artifact-ui-"))
config_path <- file.path(folder, "fixture.json")
if (mode == "serve") {
  config <- brohn_read_json_file(config_path)
  Sys.setenv(BROHN_WORKSPACE = config$workspace, BROHN_APP_MODE = "platform")
  stop_owned <- function() if (file.exists(file.path(folder, "stop.request"))) shiny::stopApp() else later::later(stop_owned, .2)
  later::later(stop_owned, .2)
  shiny::runApp(".", host = "127.0.0.1", port = config$port, launch.browser = FALSE)
} else local({
  config <- if (file.exists(config_path)) brohn_read_json_file(config_path) else NULL
  workspace <- if (mode == "setup") normalizePath(args[[3L]], winslash = "/", mustWork = TRUE) else config$workspace
  store <- brohn_open_store(workspace); on.exit(brohn_close_store(store), add = TRUE)
  if (mode == "setup") {
    stopifnot(is.null(config))
    report <- brohn_get_entity(store, "report", args[[4L]])
    stopifnot(!is.null(report), brohn_questionnaire_is_artifact(report$body$analysis))
    pending <- brohn_list_jobs(store, limit = 10000L, status = c("queued", "running"))
    stopifnot(!length(pending))
    study <- brohn_study(store, report$body$study_id)
    reference <- brohn_questionnaire_report_artifact(report$body)
    source_runs <- lapply(report$body$provenance$runs, function(pin) {
      rows <- DBI::dbGetQuery(store$con, "SELECT sequence,event_id,event_hash,event_json FROM delivery_events WHERE run_id=? ORDER BY sequence", params = list(pin$run_id))
      stopifnot(nrow(rows) > 0L, all(vapply(seq_len(nrow(rows)), function(i) identical(.brohn_delivery_hash(rows$event_json[[i]]), rows$event_hash[[i]]), logical(1))))
      events <- lapply(rows$event_json, brohn_parse)
      commits <- Filter(function(e) identical(e$type, "questionnaire_event") && identical(e$payload$kind, "commit"), events)
      final <- list()
      for (e in commits) final[e$step_id] <- list(list(step_id = e$step_id, question_id = e$question_id, event_id = e$id,
        value_sha256 = digest::digest(charToRaw(enc2utf8(brohn_json(e$payload$value))), algo = "sha256", serialize = FALSE),
        text = if (is.character(e$payload$value)) list(utf8_bytes = nchar(e$payload$value, type = "bytes"),
          sha256 = digest::digest(charToRaw(enc2utf8(e$payload$value)), algo = "sha256", serialize = FALSE)) else NULL))
      list(run_id = pin$run_id, event_count = nrow(rows), row_hashes = as.list(rows$event_hash), committed_answer_count = length(commits),
        final_answers = unname(final), protocol_hash = DBI::dbGetQuery(store$con, "SELECT protocol_hash FROM delivery_runs WHERE id=?", params = list(pin$run_id))$protocol_hash[[1L]])
    })
    # A separate original source graph: the first twelve rows contain no
    # quantitative outcome. Six later rows give differences 2,4,6; mean4, n3.
    design <- brohn_new_design("Original beyond-preview questionnaire evidence", "comparison", brohn_id("study-artifact-oracle"))
    text_question <- brohn_question("Original context note", "text", "end", "q-artifact-context")
    number_question <- brohn_question("Original ease-of-use quantity", "number", "after_each", "q-artifact-quantity")
    number_question$min <- 0; number_question$max <- 20; number_question$step <- 1
    design$questions <- list(text_question, number_question); design$measures <- list("questionnaire")
    brohn_put_entity(store, "study", design$id, design)
    responses <- lapply(seq_len(12L), function(i) list(participant_id = paste0("context-", i), session_id = "visit-1", question_id = text_question$id,
      prompt = text_question$prompt, stimulus_id = NULL, exposure_id = NULL, condition_id = NULL, value = paste("Original context row", i), missing_reason = NULL))
    for (i in seq_len(3L)) for (condition in 1:2) {
      stimulus <- design$stimuli[[condition]]
      responses[[length(responses)+1L]] <- list(participant_id = paste0("person-", i), session_id = "visit-1", question_id = number_question$id,
        prompt = number_question$prompt, stimulus_id = stimulus$id, exposure_id = paste0("exposure-", condition), condition_id = stimulus$condition_id,
        value = if (condition == 1L) i else 3*i, missing_reason = NULL)
    }
    body <- list(schema_version = "brohn-report/1.0.0", id = brohn_id("report-artifact-oracle"), title = "Original source beyond the display preview",
      study_id = design$id, dataset_id = NULL, origin = "sample", status = "Available", created_at = brohn_now(),
      provenance = list(design = design, design_hash = brohn_hash(design),
        fixture = list(kind = "original_synthetic_arithmetic_source", observed_people = FALSE, scientific_worker = FALSE,
          purpose = "Independently specified source rows test complete artifact hydration by later actual synthesis.")),
      analysis = brohn_questionnaire_analysis(responses, design))
    staging <- file.path(folder, "original-oracle"); dir.create(staging)
    packed <- brohn_pack_questionnaire_report(body, staging, threshold = 1024L)
    artifact <- packed$analysis$artifacts[[1L]]; object <- brohn_store_object(store, path = artifact$path, media_type = "application/x-ndjson")
    published <- c(artifact[setdiff(names(artifact), c("path", "sha256", "bytes"))], object[c("hash", "size", "media_type")])
    packed$analysis$artifacts <- list(published)
    oracle <- brohn_put_entity(store, "report", packed$id, packed)
    stopifnot(length(packed$analysis$preview$observations) == 10L, !any(vapply(packed$analysis$preview$observations, function(o) identical(o$question_id, number_question$id), logical(1))))
    config <- list(workspace = workspace, workspace_id = store$workspace_id, port = httpuv::randomPort(min = 20000L, max = 49000L),
      boundary = list(report_id = report$id, report_hash = brohn_hash(report$body), study_id = study$id, study_title = study$body$title,
        study_hash = brohn_hash(study$body), artifact = reference, counts = report$body$analysis$questionnaire_artifact$counts,
        preview = report$body$analysis$preview, source_runs = source_runs, original_result = report$body$result_object),
      oracle = list(report_id = oracle$id, report_hash = brohn_hash(oracle$body), study_id = design$id, study_title = design$title,
        artifact = published, question_id = number_question$id, question_prompt = number_question$prompt, response_count = 18L, numeric_rows = 6L,
        first_numeric_source_row = 13L, paired_people = 3L, paired_sessions = 3L, difference = 4, person_differences = list(2, 4, 6)),
      evidence_limits = list("Boundary sessions were generated by the earlier receiver fixture, not observed human participants.",
        "The beyond-preview source is independently constructed arithmetic data, not a prior scientific-worker publication."))
    brohn_write_json_file(config, config_path)
  }
  report_summary <- function(id) {
    record <- brohn_get_entity(store, "report", id); if (is.null(record)) return(NULL)
    body <- record$body
    envelope_exact <- if (is.null(body$result_object)) NULL else {
      path <- brohn_object_path(store, body$result_object$hash, verify = TRUE)
      envelope <- brohn_read_json_file(path)
      identical(brohn_hash(envelope$report), brohn_hash(body[setdiff(names(body), "result_object")]))
    }
    list(id = id, hash = brohn_hash(body), body = body, envelope_exact = envelope_exact,
      artifacts_valid = all(vapply(body$analysis$artifacts, function(a) identical(digest::digest(file = brohn_object_path(store, a$hash), algo = "sha256"), a$hash), logical(1))))
  }
  snapshot <- list(workspace_id = store$workspace_id, boundary = report_summary(config$boundary$report_id), oracle = report_summary(config$oracle$report_id),
    boundary_study_hash = brohn_hash(brohn_study(store, config$boundary$study_id)$body),
    source_runs = lapply(config$boundary$source_runs, function(pin) list(run_id = pin$run_id,
      row_hashes = as.list(DBI::dbGetQuery(store$con, "SELECT event_hash FROM delivery_events WHERE run_id=? ORDER BY sequence", params = list(pin$run_id))$event_hash))),
    jobs = lapply(brohn_list_jobs(store, limit = 10000L), function(job) job[c("id", "operation", "status", "request", "result", "error")]),
    combined = lapply(brohn_search_related(store, "study_reports", config$oracle$study_id, limit = 40L)$records,
      function(record) if (identical(record$body$analysis$kind, "multimodal")) report_summary(record$id) else NULL))
  snapshot$combined <- Filter(Negate(is.null), snapshot$combined)
  brohn_write_json_file(snapshot, file.path(folder, "snapshot.json"))
})
