# Original synthetic objects and independent arithmetic; no scientific children.
source("R/platform-load.R", encoding = "UTF-8"); brohn_load(ui = TRUE)
local({
  checks <- 0L
  check <- function(name, ok) {if (!isTRUE(ok)) stop("Artifact integration: ", name); checks <<- checks+1L}
  rejects <- function(expr) inherits(tryCatch({force(expr); NULL}, error = identity), "error")
  root <- tempfile("brohn-artifact-integration-"); store <- brohn_open_store(root)
  on.exit(brohn_close_store(store), add = TRUE); brohn_initialise_library(store)
  design <- brohn_new_design("Original complete response integration", id = "artifact-integration-study")
  note <- brohn_question("Original context", "text", "end", "q-context")
  number <- brohn_question("Original quantity", "number", "after_each", "q-quantity")
  number$min <- 0; number$max <- 20; number$step <- 1
  design$questions <- list(note, number); brohn_put_entity(store, "study", design$id, design)
  observations <- lapply(1:12, function(i) list(participant_id = paste0("note-", i), session_id = "visit-1", question_id = note$id,
    prompt = note$prompt, value = paste("Original text", i), missing_reason = NULL))
  for (i in 1:3) for (j in 1:2) observations[[length(observations)+1L]] <- list(participant_id = paste0("P", i), session_id = "visit-1",
    exposure_id = paste(i, j, sep = "-"), question_id = number$id, prompt = number$prompt,
    condition_id = design$conditions[[j]]$id, stimulus_id = design$stimuli[[j]]$id, value = i*c(1,3)[[j]], missing_reason = NULL)
  full <- list(schema_version = "brohn-report/1.0.0", id = "artifact-source-report", title = "Original complete evidence", status = "Available",
    study_id = design$id, dataset_id = NULL, origin = "sample", created_at = brohn_now(),
    provenance = list(design = design, design_hash = brohn_hash(design)), analysis = list(kind = "questionnaire", title = "Original responses",
      observations = observations, features = list(), quality = list(usable = TRUE, response_count = 18),
      limitations = list("Original synthetic arithmetic only."), parameters = list(method = "typed-explicit-responses/1.0.0-draft")))
  scratch <- file.path(store$root, "scratch", "original-artifact"); dir.create(scratch, recursive = TRUE)
  packed <- brohn_pack_questionnaire_report(full, scratch, threshold = 1024)
  check("preview cannot contain any of the six quantitative source rows", length(packed$analysis$preview$observations) == 10L &&
    all(vapply(packed$analysis$preview$observations, function(row) row$question_id == note$id, logical(1))))
  check("worker report verifier accepts the complete matching original source", isTRUE(brohn_verify_questionnaire_worker_report(store, packed, scratch)))
  check("analysis-only direct promotion rejects questionnaire evidence before accessing job", rejects(brohn_promote_worker_artifacts(store, packed$analysis, scratch, NULL)))
  changed <- packed; changed$provenance$design_hash <- brohn_hash("other design")
  check("worker verifier rejects changed frozen provenance", rejects(brohn_verify_questionnaire_worker_report(store, changed, scratch)))
  changed <- packed; changed$analysis$quality$usable <- FALSE
  check("worker verifier rejects a preview-only eligibility change", rejects(brohn_verify_questionnaire_worker_report(store, changed, scratch)))
  checked <- .brohn_check_worker_artifacts(store, packed$analysis, scratch)
  references <- lapply(checked, function(item) c(list(kind = item$kind), brohn_store_object(store, path = item$path, media_type = "application/x-ndjson"), item$metadata))
  packed$analysis <- .brohn_worker_artifact_analysis(packed$analysis, references)
  check("generic promotion descriptors preserve full typed counts and source binding", identical(references[[1L]]$counts$observations, 18L) &&
    identical(references[[1L]]$source_binding_sha256, brohn_hash(brohn_questionnaire_artifact_source(full))))
  packed$result_object <- brohn_store_object(store, bytes = charToRaw(enc2utf8(brohn_json(list(schema = "brohn-analysis-output/1.0", report = packed)))), media_type = "application/json")
  saved <- brohn_put_entity(store, "report", packed$id, packed)
  saved_hash <- brohn_hash(saved$body); journal_hash <- brohn_hash(brohn_get_entity(store, "report", packed$id, 1L)$body)
  restored <- brohn_complete_questionnaire_report(store, saved$body)
  check("saved hydration returns all18 exact source observations and full settings", identical(brohn_json(restored$analysis), brohn_json(full$analysis)))
  check("small report hydration leaves all original bytes alone", identical(brohn_complete_questionnaire_report(store, full), full))
  exported <- file.path(root, "full.json"); brohn_export_complete_questionnaire_report(store, saved$body, exported)
  downloaded <- brohn_read_json_file(exported)
  check("full JSON restores complete analysis and declares saved report identity", identical(brohn_hash(downloaded$analysis), brohn_hash(full$analysis)) &&
    identical(downloaded$export$saved_report_hash, saved_hash) && identical(downloaded$export$artifact$hash, references[[1L]]$hash))
  csv <- file.path(root, "full.csv"); brohn_export_report_csv(restored, csv)
  rows <- utils::read.csv(csv, colClasses = "character", check.names = FALSE)
  check("CSV contains every beyond-preview numeric response in original order", nrow(rows) == 18L && identical(tail(rows$value, 6L), c("1","3","2","6","3","9")))
  small_export <- file.path(root, "small.json"); expected_export <- file.path(root, "expected.json")
  brohn_export_complete_questionnaire_report(store, full, small_export); writeLines(enc2utf8(brohn_json(full, TRUE)), expected_export, useBytes = TRUE)
  check("legacy JSON download retains its exact existing file representation", identical(digest::digest(file = small_export, algo = "sha256"), digest::digest(file = expected_export, algo = "sha256")))
  selected <- list(packed$id)
  catalog <- brohn_multimodal_catalog(store, design$id, selected, "sample")
  check("Combine source discovery finds the numeric measure absent from every preview row", any(vapply(catalog$metrics, function(x) x$metric == "explicit_numeric_response" && x$outcome_id == number$id, logical(1))))
  crosswalk <- lapply(1:3, function(i) list(report_id = packed$id, source_participant_id = paste0("P",i), source_session_id = "visit-1", participant_id = paste0("person-",i), session_id = "visit-1"))
  contrast <- list(id = "original-difference", report_ids = selected, modality = "questionnaire", metric = "explicit_numeric_response", outcome_id = number$id,
    unit = "response units", control_id = design$conditions[[1L]]$id, test_id = design$conditions[[2L]]$id)
  request <- brohn_prepare_multimodal(store, design$id, selected, crosswalk, list(contrast), "sample", identity_source = "Independent original synthetic person register.")
  input <- brohn_multimodal_input(store, request)
  check("synthesis input retains compact frozen report and verified evidence reference", brohn_questionnaire_is_artifact(input$sources[[1L]]$body$analysis) &&
    !is.null(input$sources[[1L]]$questionnaire_evidence) && identical(input$sources[[1L]]$reference$hash, saved_hash))
  check("direct preview extraction is rejected instead of scoring zero rows", rejects(.brohn_mm_extract(packed, input$sources[[1L]]$reference, design)))
  output <- brohn_analyse_multimodal(input)$analysis
  check("complete source computes independent equal-person difference4 across all3 people", output$contrasts[[1L]]$estimate == 4 && output$contrasts[[1L]]$participant_count == 3 && output$contrasts[[1L]]$paired_session_count == 3)
  check("scientific row references retain original rows13through18 and frozen report hash", identical(as.integer(vapply(tail(output$observations,6), `[[`, numeric(1), "source_row")), 13:18) &&
    all(vapply(output$observations, function(r) identical(r$source_report_hash, saved_hash), logical(1))))
  changed <- input$sources[[1L]]; changed$questionnaire_evidence$source$origin <- "live"
  check("synthesis hydration rejects another evidence source binding", rejects(brohn_complete_questionnaire_source(changed)))
  changed <- saved$body; changed$analysis$preview$observations[[1L]]$value_display <- "forged"
  check("saved report hydration rejects a changed displayed answer", rejects(brohn_complete_questionnaire_report(store, changed)))
  html <- paste(as.character(brohn_report_detail_ui(store, saved$id)), collapse = "")
  check("report UI labels preview and complete18 response records", grepl("18 response records",html,fixed=TRUE) && grepl("bounded display previews",html,fixed=TRUE))
  offline <- file.path(root, "report.html"); brohn_export_report_html(saved$body, offline)
  check("offline report labels its preview and full evidence download requirement", grepl("18 response records", paste(readLines(offline,warn=FALSE),collapse=""),fixed=TRUE))
  # Mixed-report controls are driven by complete source counts, not absent
  # top-level arrays. This original display fixture does not claim scoring.
  mixed <- full; mixed$id <- "artifact-mixed-controls"
  mixed$analysis$scales <- list(observations = list(list(scale_id = "original-scale", value = 5)))
  mixed$analysis$task_scores <- list(list(task_id = "original-task", metrics = list(list(name = "original-value", value = 500))))
  mixed$analysis$choice_tasks <- list(list(task_id = "original-choice"))
  mixed <- brohn_pack_questionnaire_report(mixed, scratch, threshold = 1024)
  checked_mixed <- .brohn_check_worker_artifacts(store, mixed$analysis, scratch)
  mixed$analysis <- .brohn_worker_artifact_analysis(mixed$analysis, lapply(checked_mixed, function(item)
    c(list(kind = item$kind), brohn_store_object(store, path = item$path, media_type = "application/x-ndjson"), item$metadata)))
  brohn_put_entity(store, "report", mixed$id, mixed)
  mixed_html <- paste(as.character(brohn_report_detail_ui(store,mixed$id)),collapse="")
  check("mixed artifact offers all three complete score exports from source counts", all(vapply(c("report_scale_csv","report_task_csv","report_maxdiff_csv"),
    function(id) grepl(paste0('id="',id,'"'),mixed_html,fixed=TRUE),logical(1))))
  complete_mixed <- brohn_complete_questionnaire_report(store,mixed)$analysis
  check("mixed artifact hydration restores complete scale task and choice arrays", complete_mixed$scales$observations[[1L]]$value == 5 &&
    complete_mixed$task_scores[[1L]]$metrics[[1L]]$value == 500 && length(complete_mixed$choice_tasks)==1L)
  check("exports and synthesis leave immutable history byte-identical", identical(brohn_hash(brohn_get_entity(store,"report",saved$id)$body),saved_hash) &&
    identical(brohn_hash(brohn_get_entity(store,"report",saved$id,1L)$body),journal_hash))
  path <- brohn_object_path(store, references[[1L]]$hash)
  bytes <- readBin(path,"raw",file.info(path)$size); changed_path <- file.path(root,"corrupt.jsonl"); writeBin(c(bytes,as.raw(10L)),changed_path)
  changed <- input$sources[[1L]]; changed$questionnaire_evidence$path <- changed_path
  check("complete synthesis fails closed on corrupt retained bytes", rejects(brohn_complete_questionnaire_source(changed)))
  cat("Questionnaire artifact storage checks passed:",checks,"; no scientific children.\n")
})
