# Supervised jobs: child processes receive immutable inputs and no catalog handle.
brohn_read_json_file <- function(path, maximum = 16*1024^2) {
  brohn_require(file.exists(path) && !dir.exists(path) && file.info(path)$size <= maximum, "Worker document is absent or exceeds its size limit.")
  raw <- readBin(path, "raw", n = maximum + 1); value <- rawToChar(raw); Encoding(value) <- "UTF-8"
  brohn_parse(value, maximum)
}
brohn_write_json_file <- function(value, path, maximum = 16*1024^2) {
  bytes <- charToRaw(enc2utf8(brohn_json(value)))
  brohn_require(length(bytes) <= maximum, "Worker document exceeds its supported size limit.")
  writeBin(bytes, path); invisible(path)
}
brohn_rscript <- function() {
  candidates <- c(Sys.getenv("BROHN_RSCRIPT", ""), file.path(R.home("bin"), if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript"))
  available <- candidates[nzchar(candidates) & file.exists(candidates)]
  brohn_require(length(available) > 0L, "The R worker executable is unavailable.")
  normalizePath(available[1], winslash = "/", mustWork = TRUE)
}
brohn_python_profile <- function(modality) {
  profile <- if (modality %in% c("audio", "video")) "vision-audio" else if (modality == "segmentation") "segmentation" else if (modality %in% c("fnirs", "interchange")) "acquisition" else "methods"
  configured <- Sys.getenv(paste0("BROHN_PYTHON_", toupper(gsub("-", "_", profile))), "")
  candidate <- if (nzchar(configured)) configured else file.path("..", "..", "work", "tooling", paste0(profile, "-venv"),
    if (.Platform$OS.type == "windows") "Scripts/python.exe" else "bin/python")
  brohn_require(file.exists(candidate), paste("The", profile, "analysis environment is unavailable. Configure its Python executable in workspace setup."))
  normalizePath(candidate, winslash = "/", mustWork = TRUE)
}
brohn_gaze_retention_enabled <- function(input) {
  d<-input$dataset;m<-d$metadata
  identical(input$operation,"analyse_dataset")&&isTRUE(d$modality %in% c("gaze","prepared_gaze"))&&
    identical(m$gaze_representation,"samples")&&
    (brohn_text(m$pupil_column,500)||brohn_text(m$blink_column,500))
}
brohn_job_input <- function(store, job) {
  if (identical(job$operation, "vision_index")) return(brohn_vision_index_input(store, job))
  if (identical(job$operation, "vision_frame")) return(brohn_vision_frame_input(store, job))
  if (job$operation %in% c("gaze_trace_catalog", "gaze_trace_preview")) return(brohn_gaze_trace_job_input(store, job))
  if (job$operation %in% c("signal_values_page", "signal_values_export")) return(brohn_signal_values_input(store, job))
  if (job$operation %in% c("preview_cardiac_review", "reanalyse_cardiac")) return(brohn_cardiac_review_input(store, job))
  if (identical(job$operation, "summarize_signal_windows")) return(brohn_signal_windows_input(store, job))
  if (identical(job$operation, "questionnaire_index")) return(brohn_questionnaire_index_input(store, job))
  if (identical(job$operation, "explicit_distributions")) return(brohn_explicit_distribution_input(store, job))
  if (identical(job$operation, "linked_review")) return(brohn_linked_review_input(store, job))
  if (identical(job$operation, "analyse_resolved_run")) return(brohn_resolved_session_input(store, job))
  request <- job$request
  if (identical(job$operation, "analyse_task_cohort")) return(list(schema = "brohn-analysis-input/1.0", operation = job$operation,
    task_cohort = brohn_task_cohort_input(store, request), project_id = request$project_id))
  if (identical(job$operation, "ingest_source")) return(brohn_ingestion_input(store, job))
  if (identical(job$operation, "extract_stream")) return(brohn_stream_curation_input(store, job))
  if (identical(job$operation, "assemble_capture")) return(brohn_capture_input(store, job))
  if (job$operation %in% c("signal_catalog", "signal_preview")) return(brohn_signal_input(store, job))
  if (identical(job$operation, "inspect_header")) return(brohn_header_input(store, job))
  if (job$operation %in% c("normalise_dataset", "import_multistream")) {
    brohn_interchange_input(store, job)
  } else if (identical(job$operation, "segment_aoi")) {
    brohn_aoi_proposal_input(store, job)
  } else if (identical(job$operation, "backup_workspace")) {
    list(schema = "brohn-analysis-input/1.0", operation = job$operation, workspace_root = store$root,
      workspace_id = store$workspace_id, destination = request$destination, project_id = "default")
  } else if (identical(job$operation, "analyse_multimodal")) {
    list(schema = "brohn-analysis-input/1.0", operation = job$operation, multimodal = brohn_multimodal_input(store, request), project_id = request$project_id)
  } else if (identical(job$operation, "analyse_dataset")) {
    dataset <- brohn_get_entity(store, "dataset", request$dataset_id, request$dataset_revision)
    brohn_require(!is.null(dataset) && identical(brohn_hash(dataset$body), request$dataset_hash), "The pinned dataset version failed its integrity check.")
    design <- if (is.null(request$study_id)) NULL else brohn_study(store, request$study_id, request$study_revision)$body
    brohn_require(is.null(design) || identical(brohn_hash(design), request$study_hash), "The pinned design version failed its integrity check.")
    list(schema = "brohn-analysis-input/1.0", operation = job$operation, dataset = dataset$body,
      dataset_revision = dataset$revision, project_id = dataset$project_id, design = design,
      design_revision = request$study_revision, source_path = brohn_object_path(store, dataset$body$source$hash),
      registry_path = if (identical(dataset$body$modality,"implicit")) brohn_object_path(store,dataset$body$metadata$protocol_registry$hash,verify=TRUE) else NULL)
  } else if (identical(job$operation, "analyse_run")) {
    run <- brohn_run(store, request$run_id)
    brohn_require(!is.null(run) && identical(run$completion_status, "completed") && identical(run$transfer_status, "saved"), "Only a completed, durably saved run can enter automatic results.")
    # Each automatic receipt report describes its own frozen run. Cohort reports
    # use an explicitly frozen cohort request rather than changing on retries.
    list(schema = "brohn-analysis-input/1.0", operation = job$operation, runs = list(run),
      events = setNames(list(brohn_run_events(store, run$id)), run$id),
      project_id = run$protocol$design$project_id, design = run$protocol$design)
  } else if (identical(job$operation, "analyse_cohort")) {
    runs <- lapply(request$run_ids, function(id) brohn_run(store, id))
    brohn_require(length(runs) > 0 && all(vapply(runs, function(r) !is.null(r) && r$completion_status == "completed" && r$transfer_status == "saved", logical(1))), "The cohort contains a run that is no longer eligible.")
    brohn_require(length(unique(vapply(runs, function(r) r$protocol$design_hash, character(1)))) == 1L &&
      length(unique(vapply(runs, `[[`, character(1), "origin"))) == 1L, "Cohort reports require one frozen design and one declared origin.")
    list(schema = "brohn-analysis-input/1.0", operation = job$operation, runs = runs,
      events = setNames(lapply(runs, function(r) brohn_run_events(store, r$id)), vapply(runs, `[[`, character(1), "id")),
      project_id = runs[[1]]$protocol$design$project_id, design = runs[[1]]$protocol$design)
  } else brohn_stop("This job operation is not registered.")
}
brohn_queue_cohort <- function(store, deployment_id) {
  deployment <- brohn_deployment(store, deployment_id)
  brohn_require(!is.null(deployment), "Choose a saved release.")
  runs <- Filter(function(r) r$deployment_id == deployment_id && r$completion_status == "completed" && r$transfer_status == "saved", brohn_runs(store, deployment$study_id))
  brohn_require(length(runs) > 0L, "No completed sessions are available for this release yet.")
  request <- list(deployment_id = deployment_id, run_ids = as.list(sort(vapply(runs, `[[`, character(1), "id"))), recipe = "typed-explicit-responses/1.0.0-draft")
  brohn_enqueue_job(store, "analyse_cohort", request, paste0("cohort:", brohn_hash(request)))
}
brohn_retry_processing <- function(store, id) {
  job <- brohn_get_job(store, id)
  brohn_require(!is.null(job) && job$status %in% c("failed", "cancelled"), "Only failed or cancelled processing can be retried.")
  brohn_require(job$operation %in% c("analyse_dataset", "analyse_run", "analyse_cohort", "analyse_task_cohort", "analyse_multimodal", "segment_aoi", "normalise_dataset", "import_multistream", "inspect_header", "signal_catalog", "signal_preview", "signal_values_page", "signal_values_export", "gaze_trace_catalog", "gaze_trace_preview", "vision_index", "vision_frame", "summarize_signal_windows", "assemble_capture", "extract_stream", "preview_cardiac_review", "reanalyse_cardiac", "explicit_distributions", "linked_review", "analyse_resolved_run"), "Use the operation's setup screen to choose a new destination or source.")
  if(identical(job$operation,"linked_review"))brohn_linked_review_input(store,job)
  if(identical(job$operation,"analyse_resolved_run"))brohn_resolved_session_input(store,job)
  if(identical(job$operation,"explicit_distributions"))brohn_explicit_distribution_input(store,job)
  if(identical(job$operation,"vision_index"))brohn_vision_index_input(store,job)
  if(identical(job$operation,"vision_frame"))brohn_vision_frame_input(store,job)
  if(job$operation %in% c("signal_values_page", "signal_values_export"))brohn_signal_values_input(store,job)
  if(job$operation %in% c("gaze_trace_catalog", "gaze_trace_preview"))brohn_gaze_trace_job_input(store,job)
  if(job$operation %in% c("preview_cardiac_review", "reanalyse_cardiac"))brohn_cardiac_review_input(store,job)
  if(identical(job$operation,"summarize_signal_windows"))brohn_signal_windows_input(store,job)
  brohn_store_batch(store, function() {
    retried <- brohn_enqueue_job(store, job$operation, job$request, paste0("retry:", id, ":", brohn_id("request")))
    brohn_put_entity(store, "job_retry", brohn_id("retry"), list(source_job_id = id, new_job_id = retried$id, at = brohn_now(), policy = "same_frozen_inputs_new_attempt"))
    retried
  })
}
brohn_analyse_runs <- function(input) {
  responses <- list(); task_scores <- list(); provenance <- list(); quality <- list(); design <- input$design
  revisions <- list()
  linked <- vapply(input$runs, function(r) isTRUE(r$participant_alias_supplied), logical(1))
  for (run in input$runs) {
    events <- input$events[[run$id]]
    # Explicit aliases can link repeats within this frozen cohort. Otherwise the
    # run is an unidentified session; never label its count unique participants.
    participant <- if (isTRUE(run$participant_alias_supplied)) paste0("alias:", run$participant_alias) else paste0("unlinked:", run$id)
    revision <- if (!is.null(run$protocol$design$questionnaire_navigation)) brohn_questionnaire_run_projection(run, events) else NULL
    if (!is.null(revision)) {
      responses <- c(responses, Filter(function(r) !isTRUE(r$information) && r$status %in% c("answered", "optional_omission"), revision$effective_records))
      revisions[[length(revisions)+1L]] <- revision
    }
    for (event in if (is.null(revision)) Filter(function(e) e$type == "response", events) else list()) {
      step <- brohn_find(run$protocol$timeline, event$step_id)
      if (!is.null(step) && step$type=="maxdiff") next
      brohn_require(!is.null(step) && step$type == "question", "A response has no matching frozen question step.")
      q <- step$question
      responses[[length(responses)+1L]] <- list(participant_id = participant, session_id = run$id,
        question_id = q$id, prompt = q$prompt, stimulus_id = step$stimulus_id, exposure_id = step$id,
        condition_id = step$condition_id, value = event$payload$value,
        missing_reason = if (is.null(event$payload$value)) "optional_omission" else NULL,
        response_time_ms = event$payload$response_time_ms, resumed = isTRUE(event$payload$resumed),
        origin = run$origin, sequence = event$sequence)
    }
    for (step in Filter(function(s) s$type == "task", run$protocol$timeline)) {
      recorded <- Filter(function(e) identical(e$type, "task_event") && identical(e$step_id, step$id) && identical(e$payload$kind, "task_trial_finished"), events)
      score <- brohn_task_score(step$task, lapply(recorded, function(e) e$payload$data), completed = TRUE)
      score$title <- step$task$title; score$participant_id <- participant; score$session_id <- run$id
      score$participant_linkage <- isTRUE(run$participant_alias_supplied)
      task_scores[[length(task_scores)+1L]] <- score
    }
    provenance[[length(provenance)+1L]] <- list(run_id=run$id, deployment_id=run$deployment_id,
      origin=run$origin, design_hash=run$protocol$design_hash, allocation_index=run$allocation_index,
      events_hash=brohn_hash(events), final_sequence=run$acked_sequence, finalized_at=run$finalized_at)
    quality[[length(quality)+1L]] <- list(run_id=run$id,
      visibility_event_count=sum(vapply(events, function(e) e$type == "visibility", logical(1))),
      participant_linkage=if (isTRUE(run$participant_alias_supplied)) "supplied_alias_not_identity_verified" else "unlinked_session",
      observed_timing="browser_timing_not_physical_qualification")
  }
  analysis <- brohn_questionnaire_analysis(responses, design)
  if (length(revisions)) analysis$questionnaire_revision <- list(schema = "brohn-questionnaire-revision-results/1.0", runs = revisions,
    interpretation = "One final effective answer per question occurrence enters analysis. Full acknowledged edit history is retained separately; revised or resumed values do not claim initial uninterrupted response time.")
  if (length(design$scales)) analysis$scales <- brohn_score_run_scales(input)
  if (length(design$maxdiff)) analysis$choice_tasks <- brohn_score_run_maxdiff(input)
  analysis$task_scores <- task_scores
  if (any(!linked)) {
    # Counts and numeric distributions still describe responses. Unknown repeat
    # identity cannot justify an independent-person interval or paired inference.
    analysis$contrasts <- list()
    analysis$quality["participant_count"] <- list(NULL)
    analysis$quality$unlinked_session_count <- sum(!linked)
    analysis$limitations <- c(list("Some sessions have no participant alias. Their responses remain visible, but unique-person counts and inferential condition contrasts are unavailable."), analysis$limitations)
  }
  report <- list(title = if (length(task_scores)) "Task and questionnaire results" else if (length(input$runs) == 1L) "Session responses" else "Release cohort responses",
    study_id = design$id, dataset_id = NULL, origin = input$runs[[1]]$origin,
    provenance = list(design = design, design_hash = brohn_hash(design), runs = provenance,
      cohort_policy = "explicit frozen completed-run membership; origin and design kept separate"),
    analysis = analysis, session_quality = quality)
  if (!is.null(input$run_evidence)) {
    evidence <- input$run_evidence
    report$provenance$run_evidence <- list(schema = evidence$schema, workspace_id = evidence$workspace_id,
      job_id = evidence$job_id, attempt = evidence$attempt, request_hash = evidence$request_hash, binding_hash = evidence$binding_hash,
      runs = lapply(evidence$runs, function(item) list(run_id = item$metadata$id,
        protocol_sha256 = item$protocol$sha256, protocol_bytes = item$protocol$bytes,
        journal_sha256 = item$journal$sha256, journal_bytes = item$journal$bytes,
        journal_rows_hash = item$journal$rows_hash, event_count = item$journal$event_count, final_sequence = item$journal$final_sequence)))
  }
  report
}
brohn_analyse_input_unplanned <- function(input, scratch) {
  if (identical(input$operation, "vision_index")) return(brohn_analyse_vision_index(input, scratch))
  if (identical(input$operation, "vision_frame")) return(brohn_analyse_vision_frame(input, scratch))
  if (input$operation %in% c("gaze_trace_catalog", "gaze_trace_preview")) return(brohn_analyse_gaze_trace(input, scratch))
  if (input$operation %in% c("signal_values_page", "signal_values_export")) return(brohn_analyse_signal_values(input, scratch))
  if (input$operation %in% c("preview_cardiac_review", "reanalyse_cardiac")) return(brohn_analyse_cardiac_review(input, scratch))
  brohn_require(identical(input$schema, "brohn-analysis-input/1.0"), "Unsupported analysis worker input.")
  if (identical(input$operation, "summarize_signal_windows")) return(brohn_analyse_signal_windows(input, scratch))
  if (identical(input$operation, "questionnaire_index")) return(brohn_analyse_questionnaire_index(input, scratch))
  if (identical(input$operation, "explicit_distributions")) return(brohn_analyse_explicit_distributions(input, scratch))
  if (identical(input$operation, "linked_review")) return(brohn_analyse_linked_review(input, scratch))
  if (identical(input$operation, "analyse_resolved_run")) return(brohn_analyse_resolved_session(input, scratch))
  if (identical(input$operation, "analyse_task_cohort")) return(brohn_analyse_task_cohort(input$task_cohort))
  if (identical(input$operation, "ingest_source")) return(brohn_analyse_ingestion(input, scratch))
  if (identical(input$operation, "extract_stream")) return(brohn_analyse_stream_curation(input, scratch))
  if (identical(input$operation, "assemble_capture")) return(brohn_assemble_capture(input, scratch))
  if (input$operation %in% c("signal_catalog", "signal_preview")) return(brohn_analyse_signal(input, scratch))
  if (identical(input$operation, "inspect_header")) return(brohn_analyse_header(input, scratch))
  if (input$operation %in% c("normalise_dataset", "import_multistream")) return(brohn_analyse_interchange(input, scratch))
  if (identical(input$operation, "analyse_multimodal")) return(brohn_analyse_multimodal(input$multimodal))
  if (identical(input$operation, "backup_workspace")) {
    brohn_require(exists("brohn_backup_workspace", mode = "function"), "The verified backup module is unavailable.")
    store <- brohn_open_store(input$workspace_root); on.exit(brohn_close_store(store), add = TRUE)
    brohn_require(identical(store$workspace_id, input$workspace_id), "The backup source workspace changed.")
    return(list(operation_artifact = brohn_backup_workspace(store, input$destination)))
  }
  if (input$operation %in% c("analyse_run", "analyse_cohort")) return(brohn_analyse_runs(input))
  if (identical(input$operation, "segment_aoi")) return(brohn_analyse_aoi_proposal(input, scratch))
  brohn_require(identical(input$operation, "analyse_dataset"), "Unsupported analysis worker operation.")
  d <- input$dataset; m <- d$metadata; design <- input$design
  brohn_validate_dataset_mapping(d)
  brohn_require(identical(digest::digest(file = input$source_path, algo = "sha256"), d$source$hash), "Immutable source failed its worker integrity check.")
  if (identical(d$modality, "video")) {
    analysis <- brohn_run_vision(input, scratch)
  } else if (identical(d$modality,"maxdiff")) {
    brohn_validate_maxdiff_mapping(d,design)
    analysis <- brohn_import_maxdiff_analysis(brohn_read_table(input$source_path,d$source$format,max_rows=20000L),m,design,
      list(hash=d$source$hash,origin=d$origin,id=d$id,revision=input$dataset_revision))
  } else if (identical(d$modality,"implicit")) {
    registry <- brohn_task_registry_file(input$registry_path,m$protocol_registry)$registry
    analysis <- brohn_import_task_trials(brohn_read_table(input$source_path,d$source$format,max_rows=20000L),m,design,
      list(hash=d$source$hash,origin=d$origin,id=d$id,revision=input$dataset_revision,registry_object_hash=m$protocol_registry$hash),registry)
  } else if (d$modality %in% c("gaze", "prepared_gaze", "questionnaire")) {
    data <- brohn_read_table(input$source_path, d$source$format)
    analysis <- if (d$modality %in% c("gaze", "prepared_gaze")) {
      if (brohn_gaze_retention_enabled(input)) brohn_analyse_gaze_retained(data, m, design, input, scratch) else
        if (identical(m$gaze_representation, "samples")) brohn_raw_gaze_analysis(data, m, design) else brohn_gaze_analysis(data, m, design)
    } else {
      responses <- brohn_import_responses(data, m, design)
      result <- brohn_questionnaire_analysis(responses, design)
      if (length(design$scales)) {
        responses <- lapply(responses, function(r) {r$origin <- d$origin; r})
        result$scales <- brohn_score_scales(responses, design, source = list(kind = "mapped_questionnaire_import",
          dataset_id = d$id, dataset_revision = input$dataset_revision, source_hash = d$source$hash,
          mapping = m, origin = d$origin, participant_linkage = "researcher_declared_codes_not_identity_verified"))
      }
      result
    }
  } else {
    source <- file.path(scratch, paste0("source.", d$source$format))
    brohn_require(file.copy(input$source_path, source, overwrite = FALSE), "Cannot prepare the isolated native source.")
    worker <- list(operation = "physiology", script = "scripts/workers/physiology.py", parameters = brohn_default(m$parameters, list()))
    if (identical(d$modality, "eda")) {
      brohn_validate_eda_events_mapping(m, unlist(d$columns, use.names = FALSE), d$source$format, design)
      worker <- brohn_eda_events_worker_request(m, source_format = d$source$format, columns = unlist(d$columns, use.names = FALSE))
    }
    if (identical(d$modality, "eeg") && exists("brohn_neural_worker_request", mode = "function"))
      worker <- brohn_neural_worker_request(m, source_format = d$source$format, columns = unlist(d$columns, use.names = FALSE))
    else if (identical(d$modality, "eeg") && !is.null(m$parameters$recipe))
      brohn_require(identical(m$parameters$recipe, "eeg-welch-channel/1.0"), "The selected EEG recipe module is unavailable.")
    if (d$modality %in% c("temperature", "movement")) {
      worker <- brohn_peripheral_worker_request(m, source_format = d$source$format, columns = unlist(d$columns, use.names = FALSE), modality = d$modality)
      m <- worker$metadata
    }
    m$origin <- d$origin
    # An absent object is not a JSON array. Let the Python recipe supply its
    # explicit defaults instead of sending parameters: [] for an empty R list.
    m$parameters <- NULL
    request <- list(schema = "brohn-worker-request/1.0", operation = worker$operation, modality = d$modality,
      source_path = normalizePath(source, winslash = "/"), format = d$source$format, metadata = m)
    if (identical(worker$operation, "peripheral")) request$source_hash <- d$source$hash
    if (worker$operation %in% c("physiology", "eda_events", "peripheral")) {
      directory <- file.path(scratch, "artifacts")
      brohn_require(dir.exists(directory) || dir.create(directory), "Cannot create the processed artifact directory.")
      request$artifact_directory <- normalizePath(directory, winslash = "/", mustWork = TRUE)
    }
    if (length(worker$parameters)) request$parameters <- worker$parameters
    request_path <- file.path(scratch, "physiology-request.json"); result_path <- file.path(scratch, "physiology-result.json")
    brohn_write_json_file(request, request_path)
    process <- processx::run(brohn_python_profile(d$modality), c(worker$script, "--request", request_path, "--output", result_path),
      timeout = 30*60, echo = FALSE, error_on_status = FALSE, cleanup_tree = TRUE, windows_hide_window = TRUE)
    brohn_require(file.exists(result_path), paste("The scientific worker did not return a result.", substr(process$stderr, 1, 1500)))
    result <- brohn_read_json_file(result_path)
    brohn_require(identical(result$schema, "brohn-worker-result/1.0") && identical(result$modality, d$modality), "Scientific worker returned an incompatible result.")
    worker_error <- if (is.list(result$error)) result$error$message else result$error
    brohn_require(process$status == 0 && !identical(result$status, "error"), paste("Scientific analysis needs attention:", brohn_default(worker_error, substr(process$stderr, 1, 1500))))
    result <- brohn_verify_physiology_artifacts(result, scratch, d$modality)
    analysis <- c(list(kind = d$modality, title = paste(toupper(d$modality), "recording analysis"), observations = list(), contrasts = list()), result)
    analysis$limitations <- c(analysis$limitations, list("These recording features are not condition effects unless explicit event windows, person identities and baseline/contrast policies support that comparison."))
  }
  list(title = paste(d$title, "results"), study_id = d$study_id, dataset_id = d$id, origin = d$origin,
    provenance = brohn_analysis_provenance(d, input$dataset_revision, design, input$design_revision), analysis = analysis)
}
brohn_analyse_input <- function(input, scratch) {
  result <- brohn_analyse_input_unplanned(input, scratch)
  if (!is.null(input$design$analysis_plan) && !is.null(result$analysis) &&
      input$operation %in% c("analyse_dataset", "analyse_run", "analyse_cohort")) {
    browser <- input$operation %in% c("analyse_run", "analyse_cohort")
    verified <- !browser || all(vapply(input$runs, function(r) isTRUE(r$participant_alias_supplied), logical(1)))
    result$analysis <- brohn_analysis_plan_result(result$analysis, input$design, verified,
      if (browser) "plan_frozen_before_these_participant_sessions" else "source_collection_timing_not_established")
  }
  result
}
.brohn_publication_descriptors <- function(store, specifications) {
  # Registered metadata wins. For several new items with the same bytes, the
  # first specification deterministically selects the same media type as the
  # store API. A conflicting concurrent registration is checked at final commit.
  media <- new.env(parent = emptyenv())
  lapply(specifications, function(item) {
    if (!exists(item$sha256, envir = media, inherits = FALSE)) {
      row <- .brohn_store_object_row(store, item$sha256)
      if (nrow(row)) brohn_require(identical(as.numeric(row$size[[1]]), as.numeric(item$bytes)), "Existing content-address metadata has a different byte count.")
      assign(item$sha256, if (nrow(row)) row$media_type[[1]] else item$media_type, envir = media)
    }
    list(key = item$key, kind = item$kind, hash = item$sha256, size = as.numeric(item$bytes), media_type = get(item$sha256, envir = media, inherits = FALSE))
  })
}
brohn_publish_analysis_report <- function(store, job, input, result, scratch, result_path, timeout_seconds = 1900, before_commit = NULL) {
  if (brohn_gaze_retention_enabled(input)) {
    brohn_require(identical(result$report$analysis$parameters$trace_profile,"gaze-pupil-source-trace/1.0"),"This pupil/blink analysis did not retain its complete source trace.")
    gaze_source_guard<-brohn_hold_gaze_analysis_source(store,input)
    on.exit(.brohn_qexplorer_release(gaze_source_guard),add=TRUE)
    prior_before_commit<-before_commit
    before_commit<-function() {
      if(!is.null(prior_before_commit))prior_before_commit()
      brohn_check_gaze_analysis_source(store,input,verify_bytes=FALSE)
      .Call(gaze_source_guard$native$check,gaze_source_guard$pointer)
    }
  }
  report <- result$report; id <- paste0("report-", sub("^job-", "", job$id))
  report$schema_version <- "brohn-report/1.0.0"; report$id <- id; report$created_at <- brohn_now()
  report$status <- if (isTRUE(report$analysis$status %in% c("insufficient_support", "needs_review", "no_proposal"))) "Needs review" else "Available"
  report$processing <- list(job_id = job$id, attempt = job$attempt, request_hash = brohn_hash(input),
    recipe = "brohn-analysis/1.0.0-draft", output_hash = digest::digest(file = result_path, algo = "sha256"), code_hashes = result$code_identity)
  if (brohn_questionnaire_is_artifact(report$analysis) || any(vapply(brohn_default(report$analysis$artifacts, list()),
    function(a) identical(a$kind, "questionnaire-analysis"), logical(1)))) brohn_verify_questionnaire_worker_report(store, report, scratch)
  artifacts <- identical(report$analysis$schema, "brohn-vision-result/1.0") || length(report$analysis$artifacts) > 0L
  if (.Platform$OS.type != "windows") {
    # Existing behavior remains available without claiming a qualified native
    # seal on POSIX. Its writer transaction can still include bulk file I/O.
    report$processing$publication <- list(mode = "legacy-transactional-copy", native_seal = FALSE)
    return(brohn_store_batch(store, function() {
      if(!is.null(before_commit))before_commit()
      brohn_renew_job(store, job$id, job$worker, job$token, 60)
      publication_path <- result_path
      if (artifacts) {
        report$analysis <- brohn_promote_worker_artifacts(store, report$analysis, scratch, job, report = report)
        publication_path <- file.path(scratch, "published-result.json")
        brohn_write_json_file(list(schema = "brohn-analysis-output/1.0", report = report), publication_path)
      }
      report$result_object <- brohn_store_object(store, path = publication_path, media_type = "application/json")
      brohn_put_entity(store, "report", id, report, expected_revision = 0L, project_id = input$project_id)
      receipt <- list(report_id = id, output_hash = report$result_object$hash)
      if (identical(job$operation, "segment_aoi")) receipt$proposal_id <- brohn_save_aoi_proposal_result(store, report, job, input$project_id)
      brohn_complete_job(store, job$id, job$worker, job$token, receipt)
    }))
  }
  brohn_require(exists("brohn_prepare_publication", mode = "function"), "Load the registered publication module before processing reports.")
  brohn_require(!RSQLite::sqliteIsTransacting(store$con), "Prepare the report outside any enclosing store transaction.")
  .brohn_publication_job(store, job)
  implementation_paths <- c("R/platform-publication.R", "scripts/workers/publication.py", "src/publication_guard.c")
  brohn_require(all(vapply(implementation_paths, function(path) identical(result$code_identity[[path]], digest::digest(file = path, algo = "sha256")), logical(1))),
    "The publication implementation differs from the scientific job's frozen code identity.")
  # Typed table receipt/count/provenance validation happens here; the owned
  # preparation child then independently verifies complete expected byte hashes
  # through immutable read handles. Neither stage holds the SQL writer lock.
  checked <- if (artifacts) .brohn_check_worker_artifacts(store, report$analysis, scratch, verify_hashes = FALSE) else list()
  specifications <- lapply(checked, function(item) list(key = item$kind, kind = item$kind, path = item$path,
    sha256 = item$hash, bytes = item$size, media_type = if (item$kind == "aoi-mask") "image/png" else "application/x-ndjson"))
  handles <- .brohn_publication_descriptors(store, specifications)
  if (artifacts) report$analysis <- .brohn_worker_artifact_analysis(report$analysis, lapply(seq_along(checked), function(i)
    c(list(kind = checked[[i]]$kind), handles[[i]][c("hash", "size", "media_type")], checked[[i]]$metadata)))
  report$processing$publication <- list(mode = "staged-windows-parent-read-seal/1.0", native_seal = TRUE, native_build = .brohn_publication_native()$identity,
    artifact_count = length(specifications), artifact_bytes = sum(vapply(specifications, `[[`, numeric(1), "bytes")))
  publication_path <- file.path(scratch, "published-result.json")
  brohn_write_json_file(list(schema = "brohn-analysis-output/1.0", code_identity = result$code_identity, report = report), publication_path)
  specifications <- c(specifications, list(list(key = "report-result", kind = "report-result", path = publication_path,
    sha256 = digest::digest(file = publication_path, algo = "sha256"), bytes = as.numeric(file.info(publication_path)$size), media_type = "application/json")))
  predicted <- .brohn_publication_descriptors(store, specifications)
  # If metadata changed while the small JSON document was constructed, stop
  # before staging. Never freeze a JSON handle that differs from its catalog type.
  brohn_require(identical(brohn_hash(head(predicted, length(handles))), brohn_hash(handles)), "Object metadata changed while preparing the report. Retry this analysis.")
  prepared <- brohn_prepare_publication(store, job, specifications, timeout_seconds = timeout_seconds)
  committed <- FALSE
  on.exit(brohn_close_publication(prepared, committed = committed), add = TRUE)
  receipt <- brohn_store_batch(store, function() {
    if(!is.null(before_commit))before_commit()
    observed <- brohn_commit_prepared_objects(store, prepared)
    brohn_require(identical(brohn_hash(observed), brohn_hash(predicted)), "Concurrent object registration changed the frozen report handles. Retry this analysis.")
    report$result_object <- tail(observed, 1L)[[1]][c("hash", "size", "media_type")]
    brohn_put_entity(store, "report", id, report, expected_revision = 0L, project_id = input$project_id)
    receipt <- list(report_id = id, output_hash = report$result_object$hash)
    if (identical(job$operation, "segment_aoi")) receipt$proposal_id <- brohn_save_aoi_proposal_result(store, report, job, input$project_id)
    brohn_complete_job(store, job$id, job$worker, job$token, receipt)
  })
  committed <- TRUE
  receipt
}
brohn_publish_entity_result <- function(store,job,input,output,kind,body,publication_path,receipt,before_commit=NULL) {
  # Typed callers construct and validate their bounded JSON before this point.
  # Only immutable descriptors, the entity and job receipt enter the writer TX.
  brohn_require(!RSQLite::sqliteIsTransacting(store$con),"Prepare the derived result before opening its publication transaction.")
  .brohn_publication_job(store,job)
  brohn_require(brohn_text(kind,96) && brohn_valid_id(body$id) && is.list(receipt),"Derived result publication needs a typed entity and completion receipt.")
  prepared<-NULL;committed<-FALSE
  if(.Platform$OS.type=="windows") {
    paths<-c("R/platform-publication.R","scripts/workers/publication.py","src/publication_guard.c")
    brohn_require(all(vapply(paths,function(path)identical(output$code_identity[[path]],digest::digest(file=path,algo="sha256")),logical(1))),
      "The publication implementation differs from the derived job's frozen code identity.")
    prepared<-brohn_prepare_publication(store,job,list(list(key="derived-result",kind=kind,path=publication_path,
      sha256=digest::digest(file=publication_path,algo="sha256"),bytes=as.numeric(file.info(publication_path)$size),media_type="application/json")))
    on.exit(brohn_close_publication(prepared,committed=committed),add=TRUE)
  }
  result<-brohn_store_batch(store,function() {
    if(!is.null(before_commit))before_commit()
    brohn_renew_job(store,job$id,job$worker,job$token,60)
    body$result_object<-if(is.null(prepared))brohn_store_object(store,path=publication_path,media_type="application/json") else
      brohn_commit_prepared_objects(store,prepared)[[1]][c("hash","size","media_type")]
    brohn_put_entity(store,kind,body$id,body,expected_revision=0L,project_id=input$project_id)
    receipt$output_hash<-body$result_object$hash
    brohn_complete_job(store,job$id,job$worker,job$token,receipt)
  })
  committed<-TRUE;result
}
.brohn_questionnaire_worker_profile <- function() list(schema = "brohn-questionnaire-view-resources/1.0",
  max_rss_bytes = 1024^3, max_scratch_bytes = 1024^3, deadline_seconds = 300,
  monitoring = "polled resident memory; transient allocation spikes may precede termination")
.brohn_questionnaire_worker_check <- function(profile, elapsed, rss, scratch_bytes) {
  brohn_require(is.finite(elapsed) && is.finite(rss) && is.finite(scratch_bytes) &&
    elapsed <= profile$deadline_seconds && rss <= profile$max_rss_bytes && scratch_bytes <= profile$max_scratch_bytes,
    "This saved result exceeds this installation's interactive-view limit. Its original report and complete downloads remain available.")
  invisible(TRUE)
}
brohn_process_job <- function(store, job, timeout_seconds = 1900) {
  brohn_require(job$status == "running", "Claim the job before processing it.")
  scratch_parent <- file.path(store$root, "scratch")
  dir.create(scratch_parent, showWarnings = FALSE)
  scratch <- tempfile(paste0(job$id, "-"), tmpdir = scratch_parent)
  brohn_require(dir.create(scratch), "Cannot allocate analysis scratch space.")
  scratch <- normalizePath(scratch, winslash = "/", mustWork = TRUE)
  # No recursive removal from unverified paths; only this freshly created tree.
  on.exit({
    expected <- normalizePath(scratch_parent, winslash = "/", mustWork = TRUE)
    actual <- normalizePath(scratch, winslash = "/", mustWork = FALSE)
    if (startsWith(tolower(actual), paste0(tolower(expected), "/")) && startsWith(basename(actual), paste0(job$id, "-"))) unlink(actual, recursive = TRUE, force = TRUE)
  }, add = TRUE)
  child <- NULL
  on.exit(if (!is.null(child) && child$is_alive()) child$kill_tree(), add = TRUE)
  explorer <- job$operation %in% c("questionnaire_index", "explicit_distributions", "linked_review", "analyse_resolved_run")
  profile <- if (explorer) .brohn_questionnaire_worker_profile() else NULL
  peak_rss <- 0; peak_scratch <- 0; started <- as.numeric(Sys.time())
  if (explorer) on.exit(tryCatch(.brohn_store_audit(store, paste0(job$operation,".resources"), job$id,
    list(profile = profile, elapsed_seconds = as.numeric(Sys.time())-started,
      sampled_peak_rss_bytes = peak_rss, sampled_peak_scratch_bytes = peak_scratch,
      operation = job$operation, attempt = job$attempt)), error = function(e) NULL), add = TRUE)
  tryCatch({
    if (explorer) brohn_require(requireNamespace("ps", quietly = TRUE), "Complete-source review requires process memory monitoring.")
    input <- if (job$operation %in% c("analyse_run", "analyse_cohort")) brohn_prepare_run_evidence_input(store, job, scratch) else brohn_job_input(store, job)
    if(identical(job$operation,"vision_index")) {
      vision_source_guards<-.brohn_vexplorer_guards(store,job$request)
      on.exit(for(g in vision_source_guards).brohn_qexplorer_release(g),add=TRUE)
      brohn_require(identical(brohn_hash(input),brohn_hash(brohn_vision_index_input(store,job))),"Saved video sources changed before their processing read guards were established.")
    }
    if(identical(job$operation,"vision_frame")) {
      vision_frame_guards<-.brohn_vframe_guards(store,job$request)
      on.exit(for(g in vision_frame_guards).brohn_qexplorer_release(g),add=TRUE)
      brohn_require(identical(brohn_hash(input),brohn_hash(brohn_vision_frame_input(store,job))),"Recorded frame sources changed before their processing read guards were established.")
    }
    if(brohn_gaze_retention_enabled(input)) {
      gaze_analysis_guard<-brohn_hold_gaze_analysis_source(store,input)
      on.exit(.brohn_qexplorer_release(gaze_analysis_guard),add=TRUE)
    }
    if(job$operation %in% c("gaze_trace_catalog", "gaze_trace_preview")) {
      gaze_trace_guards<-brohn_hold_gaze_trace_sources(store,input)
      on.exit(for(g in gaze_trace_guards).brohn_qexplorer_release(g),add=TRUE)
      brohn_require(identical(brohn_hash(input),brohn_hash(brohn_gaze_trace_job_input(store,job))),"Pupil/blink source changed before its processing read guard was established.")
    }
    if(job$operation %in% c("preview_cardiac_review","reanalyse_cardiac")) {
      cardiac_source_guards<-.brohn_hold_cardiac_sources(store,input)
      on.exit(for(g in cardiac_source_guards).brohn_qexplorer_release(g),add=TRUE)
      brohn_require(identical(brohn_hash(input),brohn_hash(brohn_cardiac_review_input(store,job))),"Cardiac source changed before its processing read guard was established.")
    }
    if(job$operation %in% c("signal_values_page", "signal_values_export")) {
      value_source_guards<-brohn_hold_signal_value_sources(store,input)
      on.exit(for(g in value_source_guards).brohn_qexplorer_release(g),add=TRUE)
      brohn_require(identical(brohn_hash(input),brohn_hash(brohn_signal_values_input(store,job))),"Exact-value source changed before its processing read guard was established.")
    }
    request_path <- file.path(scratch, "request.json"); result_path <- file.path(scratch, "result.json")
    brohn_write_json_file(input, request_path)
    executable <- brohn_rscript()
    child <- processx::process$new(executable, c("--vanilla", "scripts/analysis-worker.R", "--request", request_path, "--output", result_path, "--scratch", scratch),
      stdout = file.path(scratch, "stdout.txt"), stderr = file.path(scratch, "stderr.txt"),
      env = c("current", R_LIBS_USER = paste(.libPaths(), collapse = .Platform$path.sep)),
      windows_hide_window = TRUE, cleanup_tree = TRUE)
    if (!explorer) started <- as.numeric(Sys.time())
    renewal <- as.numeric(Sys.time())
    process_handle <- if (explorer) ps::ps_handle(child$get_pid()) else NULL
    while (child$is_alive()) {
      child$wait(200)
      now <- as.numeric(Sys.time())
      if (explorer) {
        rss <- tryCatch(as.numeric(ps::ps_memory_info(process_handle)[["rss"]]), error = function(e) {
          if (child$is_alive()) stop(e) else 0
        })
        files <- list.files(scratch, full.names = TRUE, recursive = TRUE, all.files = TRUE)
        disk <- sum(file.info(files)$size, na.rm = TRUE)
        peak_rss <- max(peak_rss, rss); peak_scratch <- max(peak_scratch, disk)
        .brohn_questionnaire_worker_check(profile, now-started, rss, disk)
      }
      brohn_require(now-started <= timeout_seconds, "Analysis exceeded its declared time limit. The source and earlier reports remain intact.")
      current <- brohn_get_job(store, job$id)
      brohn_require(current$status == "running" && identical(current$token, job$token) && identical(current$worker, job$worker), "This processing attempt was cancelled or replaced.")
      for (log in c("stdout.txt", "stderr.txt")) brohn_require(file.info(file.path(scratch, log))$size <= 4*1024^2, "Analysis exceeded its diagnostic output limit.")
      if (now-renewal >= 15) {brohn_renew_job(store, job$id, job$worker, job$token, 60); renewal <- now}
    }
    brohn_require(child$get_exit_status() == 0 && file.exists(result_path), paste("Analysis did not complete.",
      paste(head(readLines(file.path(scratch, "stderr.txt"), warn = FALSE, encoding = "UTF-8"), 8), collapse = " ")))
    if (explorer) {
      files <- list.files(scratch, full.names = TRUE, recursive = TRUE, all.files = TRUE)
      peak_scratch <- max(peak_scratch, sum(file.info(files)$size, na.rm = TRUE))
      .brohn_questionnaire_worker_check(profile, as.numeric(Sys.time())-started, peak_rss, peak_scratch)
    }
    result <- brohn_read_json_file(result_path)
    brohn_require(identical(result$schema, "brohn-analysis-output/1.0") && is.list(result$report), "Analysis returned an invalid result document.")
    brohn_require(is.list(result$code_identity) && "scripts/analysis-worker.R" %in% names(result$code_identity) &&
      all(vapply(result$code_identity, function(hash) brohn_text(hash, 64) && grepl("^[a-f0-9]{64}$", hash), logical(1))), "Analysis returned no verifiable implementation identity.")
    if (identical(job$operation, "ingest_source"))
      return(brohn_publish_ingestion(store, result, scratch, job, input, result_path))
    if (identical(job$operation,"questionnaire_index")) return(brohn_publish_questionnaire_index(store, result, scratch, job, input, result_path))
    if (identical(job$operation,"explicit_distributions")) return(brohn_publish_explicit_distributions(store, result, scratch, job, input, result_path))
    if (identical(job$operation,"linked_review")) return(brohn_publish_linked_review(store, result, scratch, job, input, result_path))
    if (identical(job$operation,"analyse_resolved_run")) return(brohn_publish_resolved_session(store, result, scratch, job, input, result_path))
    if (identical(job$operation, "vision_index")) return(brohn_publish_vision_index(store, result, scratch, job, input, result_path))
    if (identical(job$operation, "vision_frame")) return(brohn_publish_vision_frame(store, result, scratch, job, input, result_path))
    if (identical(job$operation, "summarize_signal_windows")) return(brohn_publish_signal_windows(store, result, scratch, job, input, result_path))
    if (job$operation %in% c("preview_cardiac_review", "reanalyse_cardiac")) return(brohn_publish_cardiac_review(store, result, scratch, job, input, result_path))
    if (job$operation %in% c("normalise_dataset", "import_multistream"))
      return(brohn_publish_stream_import(store, result, scratch, job, input, result_path))
    if (job$operation %in% c("gaze_trace_catalog", "gaze_trace_preview"))
      return(brohn_publish_gaze_trace(store, result, scratch, job, input, result_path))
    if (job$operation %in% c("signal_values_page", "signal_values_export"))
      return(brohn_publish_signal_values(store, result, scratch, job, input, result_path))
    if (job$operation %in% c("signal_catalog", "signal_preview"))
      return(brohn_publish_signal_view(store, result, scratch, job, input, result_path))
    if (identical(job$operation, "assemble_capture"))
      return(brohn_publish_capture(store, result, scratch, job, input, result_path))
    if (identical(job$operation, "extract_stream"))
      return(brohn_publish_stream_curation(store, result, scratch, job, input, result_path))
    if (identical(job$operation, "inspect_header"))
      return(brohn_publish_header_inspection(store, result, scratch, job, input, result_path))
    if (identical(job$operation, "backup_workspace")) {
      artifact <- result$report$operation_artifact
      brohn_require(isTRUE(artifact$verified) && identical(normalizePath(artifact$path, winslash = "/"), normalizePath(input$destination, winslash = "/")), "The backup worker returned an unexpected artifact.")
      return(brohn_store_batch(store, function() {
        brohn_renew_job(store, job$id, job$worker, job$token, 60)
        brohn_put_entity(store, "backup", artifact$backup_id, c(artifact, list(created_at = brohn_now(), job_id = job$id)), project_id = "default")
        brohn_complete_job(store, job$id, job$worker, job$token, artifact)
      }))
    }
    remaining <- timeout_seconds - (as.numeric(Sys.time()) - started)
    brohn_require(remaining >= 1, "No time remains for verified report publication; the source is preserved.")
    brohn_publish_analysis_report(store, job, input, result, scratch, result_path, timeout_seconds = min(remaining, 7200))
  }, error = function(e) {
    if (!is.null(child) && child$is_alive()) child$kill_tree()
    tryCatch(brohn_fail_job(store, job$id, job$worker, job$token, list(message = substr(conditionMessage(e), 1, 4000), source_preserved = TRUE)), error = function(ignored) NULL)
    invisible(NULL)
  })
}
