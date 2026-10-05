# Inactive explicit profile parent. Original process body retained except recorded seams.
brohn_process_variant_job <- function(store, job, timeout_seconds = 1900) {
  .brohn_vra_membership(job$operation, job$request)
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
  explorer <- job$operation %in% c("report_package", "task_display", "choice_display", "eda_display", "cardiac_display", "questionnaire_index", "explicit_distributions", "preview_clock_alignment", "clock_window", "clock_plot", "clock_event_page", "save_clock_map", "linked_review", "analyse_resolved_run", "audio_review", "audio_tracks", "audio_extract", "media_tracks", "media_review", "facial_review", "facial_frame", "eda_review", "answer_session", "respiration_review", "emg_review", "eda_continuous_review")
  profile <- if (explorer) .brohn_questionnaire_worker_profile() else NULL
  peak_rss <- 0; peak_scratch <- 0; started <- as.numeric(Sys.time())
  if (explorer) on.exit(tryCatch(.brohn_store_audit(store, paste0(job$operation,".resources"), job$id,
    list(profile = profile, elapsed_seconds = as.numeric(Sys.time())-started,
      sampled_peak_rss_bytes = peak_rss, sampled_peak_scratch_bytes = peak_scratch,
      operation = job$operation, attempt = job$attempt)), error = function(e) NULL), add = TRUE)
  tryCatch({
    if (explorer) brohn_require(requireNamespace("ps", quietly = TRUE), "Complete-source review requires process memory monitoring.")
    # Keep one renewal clock across parent preparation, the child and verified
    # publication. A short child must not reset time already spent preparing.
    pulse <- NULL
    if (job$operation %in% c("eda_display","cardiac_display") ||
        (identical(job$operation,"report_package") &&
         job$request$limits$profile %in% c("controlled-task-choice-eda-report-package/0.1","controlled-task-choice-eda-cardiac-report-package/0.1"))) {
      lease_checkpoint <- .brohn_publication_checkpoint(store,job)
      pulse <- function() {
        brohn_require(as.numeric(Sys.time())-started <= min(timeout_seconds,profile$deadline_seconds),
          if(identical(job$operation,"report_package")) .brohn_report_package_deadline_message(min(timeout_seconds,profile$deadline_seconds)) else
            "Report preparation exceeded its declared time limit. Original findings remain intact.")
        lease_checkpoint(TRUE)
      }
      pulse()
    }
    input <- if (identical(job$operation,"clock_plot")) brohn_clock_plot_input(store,job,FALSE) else if (job$operation %in% c("analyse_run", "analyse_cohort")) brohn_prepare_variant_run_evidence_input(store, job, scratch) else brohn_job_input(store, job)
    if (!is.null(pulse)) pulse()
    if (identical(job$operation,"task_display")) {
      task_display_execution <- brohn_prepare_task_display_execution(store,job,input,scratch)
      input <- task_display_execution$input
      on.exit({
        if (!is.null(child) && child$is_alive()) child$kill_tree()
        brohn_release_task_display_sources(task_display_execution$handle)
      },add=TRUE,after=FALSE)
    } else if (identical(job$operation,"choice_display")) {
      choice_display_execution <- brohn_prepare_choice_display_execution(store,job,input,scratch)
      input <- choice_display_execution$input
      on.exit({
        if (!is.null(child) && child$is_alive()) child$kill_tree()
        brohn_release_choice_display_sources(choice_display_execution$handle)
      },add=TRUE,after=FALSE)
    } else if (identical(job$operation,"cardiac_display")) {
      cardiac_execution <- brohn_prepare_cardiac_display_execution(store,job,input,scratch,pulse=pulse)
      input <- cardiac_execution$input
      on.exit({
        if (!is.null(child) && child$is_alive()) child$kill_tree()
        brohn_release_cardiac_display_execution(cardiac_execution$handle)
      },add=TRUE,after=FALSE)
    } else if (identical(job$operation,"eda_display")) {
      eda_display_execution <- brohn_prepare_eda_display_execution(store,job,input,scratch,pulse=pulse)
      input <- eda_display_execution$input
      on.exit({
        if (!is.null(child) && child$is_alive()) child$kill_tree()
        brohn_release_eda_display_sources(eda_display_execution$handle)
      },add=TRUE,after=FALSE)
    } else if (identical(job$operation,"report_package")) {
      package_execution <- if(is.null(pulse))brohn_prepare_report_package_execution(store,job,input,scratch)else
        brohn_prepare_report_package_execution(store,job,input,scratch,pulse=pulse)
      input <- package_execution$input
      on.exit({
        if (!is.null(child) && child$is_alive()) child$kill_tree()
        brohn_release_report_package_sources(package_execution$handle)
      },add=TRUE,after=FALSE)
    } else if (identical(job$operation,"explicit_distributions") && isTRUE(job$request$schema %in% c("brohn-report-package-distribution-job/0.1","brohn-report-package-distribution-job/0.2"))) {
      distribution_execution <- brohn_prepare_report_distribution_execution(store,job,input,scratch)
      input <- distribution_execution$input
      on.exit({
        if (!is.null(child) && child$is_alive()) child$kill_tree()
        brohn_release_report_distribution_sources(distribution_execution$handle)
      },add=TRUE,after=FALSE)
    }
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
    if (identical(job$operation,"analyse_dataset") && identical(input$dataset$modality,"video") && brohn_is_facial_profile(input$dataset$metadata)) {
      refs<-if(!is.null(input$camera_analysis_authority))input$camera_analysis_authority$source_refs else list(list(hash=input$dataset$source$hash,bytes=input$dataset$source$size))
      facial_source_guards <- brohn_hold_signal_value_sources(store,list(source_objects=refs))
      on.exit(for(g in facial_source_guards).brohn_qexplorer_release(g),add=TRUE)
      brohn_require(identical(brohn_hash(input),brohn_hash(brohn_job_input(store,job))),"The facial recording or its authority changed before its processing read guard was established.")
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
    if(job$operation %in% c("preview_clock_alignment", "clock_window", "clock_plot", "clock_event_page", "save_clock_map", "audio_tracks", "audio_extract", "audio_review", "media_tracks", "media_review", "facial_review", "facial_frame", "eda_review", "respiration_review", "emg_review", "eda_continuous_review", "answer_session", "signal_catalog", "signal_preview", "summarize_signal_windows") ||
        (identical(job$operation,"analyse_dataset") && !is.null(input$derived_audio_lineage))) {
      # Keep every immutable parent readable but unwritable throughout the child
      # read, not only when publishing its output. Re-resolve authority after all
      # handles are held so a change during acquisition cannot be accepted.
      refs <- if (identical(job$operation,"analyse_dataset")) input$derived_audio_lineage$source_refs else input$source_objects
      brohn_require(is.list(refs) && length(refs)>0L,"This processing request has no sealed original-source references.")
      processing_source_guards <- brohn_hold_signal_value_sources(store,list(source_objects=refs))
      on.exit(for(g in processing_source_guards).brohn_qexplorer_release(g),add=TRUE)
      brohn_require(identical(brohn_hash(input),brohn_hash(brohn_job_input(store,job))),
        "The saved source or its authority changed before its processing read guards were established.")
    }
    request_path <- file.path(scratch, "request.json"); result_path <- file.path(scratch, "result.json")
    if (!is.null(pulse)) pulse()
    brohn_write_json_file(input, request_path)
    expected_worker <- .brohn_vra_worker_identity()
    executable <- brohn_rscript()
    child <- processx::process$new(executable, c("--vanilla", "scripts/variant-analysis-worker.R", "--request", request_path, "--output", result_path, "--scratch", scratch),
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
        .brohn_questionnaire_worker_check(profile, now-started, rss, disk, operation=job$operation)
      }
      brohn_require(now-started <= timeout_seconds,
        if(identical(job$operation,"report_package")) .brohn_report_package_deadline_message(timeout_seconds) else
          "Analysis exceeded its declared time limit. The source and earlier reports remain intact.")
      current <- brohn_get_job(store, job$id)
      brohn_require(current$status == "running" && identical(current$token, job$token) && identical(current$worker, job$worker), "This processing attempt was cancelled or replaced.")
      for (log in c("stdout.txt", "stderr.txt")) brohn_require(file.info(file.path(scratch, log))$size <= 4*1024^2, "Analysis exceeded its diagnostic output limit.")
      if (!is.null(pulse)) pulse() else if (now-renewal >= 15) {brohn_renew_job(store, job$id, job$worker, job$token, 60); renewal <- now}
    }
    if (!is.null(pulse)) pulse()
    brohn_require(child$get_exit_status() == 0 && file.exists(result_path), paste("Analysis did not complete.",
      paste(head(readLines(file.path(scratch, "stderr.txt"), warn = FALSE, encoding = "UTF-8"), 8), collapse = " ")))
    if (explorer) {
      files <- list.files(scratch, full.names = TRUE, recursive = TRUE, all.files = TRUE)
      peak_scratch <- max(peak_scratch, sum(file.info(files)$size, na.rm = TRUE))
      .brohn_questionnaire_worker_check(profile, as.numeric(Sys.time())-started, peak_rss, peak_scratch, operation=job$operation)
    }
    brohn_require(file.exists(result_path) && !dir.exists(result_path) && file.info(result_path)$size <= 16*1024^2,
      "Variant result exceeds its original JSON output bound.")
    result <- .brohn_vra_decode(readBin(result_path, "raw", n=16*1024^2+1L))
    .brohn_vra_worker_output(result, expected_worker)
    brohn_require(identical(result$schema, "brohn-analysis-output/1.0") && is.list(result$report), "Analysis returned an invalid result document.")
    brohn_require(is.list(result$code_identity) && "scripts/variant-analysis-worker.R" %in% names(result$code_identity) &&
      all(vapply(result$code_identity, function(hash) brohn_text(hash, 64) && grepl("^[a-f0-9]{64}$", hash), logical(1))), "Analysis returned no verifiable implementation identity.")
    if (identical(job$operation, "ingest_source"))
      return(brohn_publish_ingestion(store, result, scratch, job, input, result_path))
    if (identical(job$operation,"questionnaire_index")) return(brohn_publish_questionnaire_index(store, result, scratch, job, input, result_path))
    if (identical(job$operation,"answer_session")) return(brohn_publish_answer_session(store, result, scratch, job, input, result_path))
    if (identical(job$operation,"report_package")) return(if(is.null(pulse))brohn_publish_report_package(store,result,scratch,job,input,result_path)else
      brohn_publish_report_package(store,result,scratch,job,input,result_path,pulse=pulse))
    if (identical(job$operation,"task_display")) return(brohn_publish_task_display(store,result,scratch,job,input,result_path))
    if (identical(job$operation,"choice_display")) return(brohn_publish_choice_display(store,result,scratch,job,input,result_path))
    if (identical(job$operation,"eda_display")) return(brohn_publish_eda_display(store,result,scratch,job,input,result_path,pulse=pulse))
    if (identical(job$operation,"cardiac_display")) return(brohn_publish_cardiac_display(store,result,scratch,job,input,result_path,pulse=pulse))
    if (identical(job$operation,"explicit_distributions") && isTRUE(job$request$schema %in% c("brohn-report-package-distribution-job/0.1","brohn-report-package-distribution-job/0.2"))) return(brohn_publish_report_distribution(store,result,scratch,job,input,result_path))
    if (identical(job$operation,"explicit_distributions")) return(brohn_publish_explicit_distributions(store, result, scratch, job, input, result_path))
    if (identical(job$operation,"save_clock_map")) return(brohn_publish_clock_map_save(store, result, scratch, job, input, result_path))
    if (identical(job$operation,"clock_plot")) return(brohn_publish_clock_plot(store, result, scratch, job, input, result_path))
    if (identical(job$operation,"clock_window")) return(brohn_publish_clock_window(store, result, scratch, job, input, result_path))
    if (identical(job$operation,"clock_event_page")) return(brohn_publish_clock_events(store, result, scratch, job, input, result_path))
    if (identical(job$operation,"preview_clock_alignment")) return(brohn_publish_clock_preview(store, result, scratch, job, input, result_path))
    if (identical(job$operation,"linked_review")) return(brohn_publish_linked_review(store, result, scratch, job, input, result_path))
    if (identical(job$operation,"analyse_resolved_run")) return(brohn_publish_resolved_session(store, result, scratch, job, input, result_path))
    if (identical(job$operation,"audio_review")) return(brohn_publish_audio_review(store, result, scratch, job, input, result_path))
    if (job$operation %in% c("audio_tracks","audio_extract")) return(brohn_publish_audio_extraction(store, result, scratch, job, input, result_path))
    if (job$operation %in% c("media_tracks","media_review")) return(brohn_publish_media_review(store, result, scratch, job, input, result_path))
    if (identical(job$operation,"facial_review")) return(brohn_publish_facial_review(store, result, scratch, job, input, result_path))
    if (identical(job$operation,"facial_frame")) return(brohn_publish_facial_frame(store, result, scratch, job, input, result_path))
    if (identical(job$operation,"eda_review")) return(brohn_publish_eda_review(store, result, scratch, job, input, result_path))
    if (identical(job$operation,"respiration_review")) return(brohn_publish_respiration_review(store, result, scratch, job, input, result_path))
    if (identical(job$operation,"emg_review")) return(brohn_publish_emg_review(store, result, scratch, job, input, result_path))
    if (identical(job$operation,"eda_continuous_review")) return(brohn_publish_eda_continuous_review(store, result, scratch, job, input, result_path))
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
    brohn_publish_variant_analysis(store, job, input, result, scratch, result_path, timeout_seconds = min(remaining, 7200))
  }, error = function(e) {
    if (!is.null(child) && child$is_alive()) child$kill_tree()
    failure<-list(message=substr(conditionMessage(e),1,4000),source_preserved=TRUE)
    if(inherits(e,"brohn_eda_refusal")&&
      (identical(job$operation,"eda_display")||
       (identical(job$operation,"report_package")&&job$request$limits$profile %in% c("controlled-task-choice-eda-report-package/0.1","controlled-task-choice-eda-cardiac-report-package/0.1")))){
      typed<-tryCatch({brohn_validate_eda_refusal(e$refusal);e$refusal},error=function(ignored)NULL)
      if(!is.null(typed))failure<-c(typed,list(source_preserved=TRUE))
    }
    if(inherits(e,"brohn_cardiac_refusal")&&identical(job$operation,"cardiac_display")){
      typed <- tryCatch({brohn_validate_cardiac_refusal(e$refusal);e$refusal},error=function(ignored)NULL)
      if(!is.null(typed))failure <- c(typed,list(source_preserved=TRUE))
    }
    tryCatch(brohn_fail_job(store, job$id, job$worker, job$token, failure), error = function(ignored) NULL)
    invisible(NULL)
  })
}
