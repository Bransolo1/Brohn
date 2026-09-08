# Derived visual views preserve a complete processed artifact and its source report.
brohn_signal_artifact <- function(report, kind) {
  items <- Filter(function(a) identical(a$kind, kind) && a$kind %in% c("physiology-series", "physiology-events"), report$body$analysis$artifacts)
  brohn_require(length(items) == 1L && isTRUE(items[[1L]]$complete), "Choose a complete processed artifact from this report.")
  a <- items[[1L]]
  manifest <- c(list(kind = a$kind, sha256 = a$hash, bytes = a$size), a[c("schema", "tables", "rows", "provenance_sha256", "complete")])
  brohn_validate_physiology_artifact_receipt(list(artifacts = list(manifest), artifact_verification = list(
    schema = report$body$analysis$artifact_verification$schema, status = report$body$analysis$artifact_verification$status,
    artifacts = Filter(function(r) identical(r$kind, kind), report$body$analysis$artifact_verification$artifacts))))
  manifest
}
brohn_queue_signal_view <- function(store, report_id, kind, selection = NULL, offset = 0L, max_bins = 800L) {
  report <- brohn_get_entity(store, "report", report_id)
  brohn_require(!is.null(report), "Choose a saved report before exploring its signals.")
  brohn_project(store, report$project_id)
  artifact <- brohn_signal_artifact(report, kind)
  brohn_object_path(store, artifact$sha256)
  operation <- if (is.null(selection)) "signal_catalog" else "signal_preview"
  brohn_require(brohn_number(offset, 0, 10000, TRUE) && brohn_number(max_bins, 1, 2000, TRUE), "Choose a supported page and plot detail.")
  request <- list(report_id = report$id, report_revision = report$revision, report_hash = brohn_hash(report$body),
    project_id = report$project_id, artifact = artifact, recipe = "processed-signal-view/1.0.0")
  if (operation == "signal_catalog") request$page <- list(offset = as.integer(offset), limit = 100L) else {
    brohn_require(is.list(selection) && identical(sort(names(selection)), sort(c("table_ids", "recording_id", "channel", "value_column", "range"))), "Select the table, channel, measure and range to view.")
    brohn_require(brohn_array(selection$table_ids) && length(selection$table_ids) %in% 1:50 &&
      !anyDuplicated(unlist(selection$table_ids)) && all(vapply(selection$table_ids, brohn_text, logical(1), max = 160)), "Choose up to 50 distinct processed tables.")
    for (field in c("recording_id", "channel", "value_column")) brohn_require(brohn_text(selection[[field]], 500), "Choose an exact recording, channel and measure.")
    bounds <- selection$range
    brohn_require(is.null(bounds) || (brohn_array(bounds) && length(bounds) == 2L && all(vapply(bounds, brohn_number, logical(1))) && bounds[[1L]] < bounds[[2L]]), "Enter two increasing finite coordinates or choose the full recording.")
    request$selection <- selection; request$parameters <- list(max_bins = as.integer(max_bins))
  }
  brohn_enqueue_job(store, operation, request, paste0(operation, ":", brohn_hash(request)))
}
brohn_signal_input <- function(store, job) {
  r <- job$request; report <- brohn_get_entity(store, "report", r$report_id, r$report_revision)
  brohn_require(!is.null(report) && identical(report$project_id, r$project_id) && identical(brohn_hash(report$body), r$report_hash), "The frozen source report failed its integrity check.")
  artifact <- brohn_signal_artifact(report, r$artifact$kind)
  brohn_require(identical(brohn_hash(artifact), brohn_hash(r$artifact)), "The selected processed artifact changed.")
  list(schema = "brohn-analysis-input/1.0", operation = job$operation, project_id = report$project_id,
    report_id = report$id, report_revision = report$revision, report_hash = r$report_hash, origin = report$body$origin,
    artifact = artifact, source_path = brohn_object_path(store, artifact$sha256),
    verification_receipt = report$body$analysis$artifact_verification,
    page = r$page, selection = r$selection, parameters = r$parameters)
}
brohn_validate_signal_result <- function(result, input) {
  schema <- if (input$operation == "signal_catalog") "brohn-signal-catalog/1.0" else "brohn-signal-preview/1.0"
  brohn_require(identical(result$schema, schema) && result$status %in% c("completed", "empty_range"), "The processed signal view returned an incompatible document.")
  for (field in c("kind", "sha256", "bytes", "schema", "tables", "rows", "provenance_sha256"))
    brohn_require(identical(brohn_hash(result$artifact[[field]]), brohn_hash(input$artifact[[field]])), "This view belongs to a different processed artifact.")
  brohn_require(brohn_array(result$tables), "The signal view has no typed table list.")
  if (input$operation == "signal_catalog") {
    p <- result$pagination
    brohn_require(identical(as.numeric(p$offset), as.numeric(input$page$offset)) && identical(as.numeric(p$limit), as.numeric(input$page$limit)) &&
      length(result$tables) <= p$limit && p$returned == length(result$tables) && p$total_tables == input$artifact$tables,
      "The processed table catalog returned inconsistent pagination.")
  } else {
    brohn_require(identical(brohn_hash(result$selection), brohn_hash(input$selection)) &&
      identical(as.numeric(result$parameters$max_bins), as.numeric(input$parameters$max_bins)), "The signal view substituted another selection or range.")
    brohn_require(brohn_array(result$envelopes) && length(result$envelopes) <= 10000 && brohn_array(result$fragments) && length(result$fragments) <= 2000,
      "The processed plot exceeds its visual support limit.")
    if (result$status != "empty_range") brohn_require(isTRUE(result$quality$verified_twice) && identical(result$quality$scientific_resampling, FALSE) &&
      result$quality$envelope_rows == result$selected_range$eligible_value_rows, "The processed plot did not account for all selected eligible rows.")
  }
  # Private worker paths are never part of a saved view or its download.
  no_paths <- function(x) !is.list(x) || (!any(names(x) %in% c("path", "source_path", "output_path")) && all(vapply(x, no_paths, logical(1))))
  brohn_require(no_paths(result), "A signal view contains a private filesystem path.")
  invisible(result)
}
brohn_analyse_signal <- function(input, scratch) {
  request <- list(schema = "brohn-signal-preview-request/1.0", operation = input$operation,
    artifact = c(input$artifact, list(path = normalizePath(input$source_path, winslash = "/", mustWork = TRUE))),
    verification_receipt = input$verification_receipt)
  if (input$operation == "signal_catalog") request$page <- input$page else {request$selection <- input$selection; request$parameters <- input$parameters}
  request_path <- file.path(scratch, "signal-request.json"); result_path <- file.path(scratch, "signal-result.json")
  brohn_write_json_file(request, request_path, maximum = 2*1024^2)
  child <- processx::run(brohn_python_profile("eda"), c("scripts/workers/signal_preview.py", "--request", request_path, "--output", result_path),
    timeout = 15*60, error_on_status = FALSE, cleanup_tree = TRUE, windows_hide_window = TRUE)
  brohn_require(file.exists(result_path), paste("The processed signal could not be read.", substr(child$stderr, 1, 1000)))
  result <- brohn_read_json_file(result_path)
  brohn_require(child$status == 0 && !identical(result$status, "error"), paste("Signal view needs attention:", brohn_default(result$error$message, substr(child$stderr, 1, 1000))))
  brohn_validate_signal_result(result, input)
  list(signal_view = result)
}
brohn_publish_signal_view <- function(store, output, scratch, job, input, output_path) {
  brohn_require(!RSQLite::sqliteIsTransacting(store$con), "Prepare processed views outside the publication transaction.")
  .brohn_publication_job(store,job)
  brohn_require(identical(brohn_hash(input), brohn_hash(brohn_signal_input(store, job))), "Signal view publication substituted different saved inputs.")
  result <- output$report$signal_view; brohn_validate_signal_result(result, input)
  id <- paste0("signal-view-", sub("^job-", "", job$id))
  body <- list(schema_version = "brohn-saved-signal-view/1.0.0", id = id, report_id = input$report_id,
    report_revision = input$report_revision, report_hash = input$report_hash, origin = input$origin,
    operation = input$operation, artifact_hash = input$artifact$sha256, view = result, created_at = brohn_now(),
    processing = list(job_id = job$id, attempt = job$attempt, request_hash = brohn_hash(input),
      worker_output_hash = digest::digest(file = output_path, algo = "sha256"), code_hashes = output$code_identity))
  body$processing$publication <- list(mode=if(.Platform$OS.type=="windows")"staged-windows-parent-read-seal/1.0"else"legacy-transactional-copy",
    native_seal=.Platform$OS.type=="windows",native_build=if(.Platform$OS.type=="windows").brohn_publication_native()$identity else NULL)
  publication <- file.path(scratch, "published-signal-view.json"); brohn_write_json_file(body, publication)
  brohn_publish_entity_result(store,job,input,output,"signal_view",body,publication,list(signal_view_id=id,report_id=input$report_id))
}
