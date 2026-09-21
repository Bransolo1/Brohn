# Source-bound saved pupil/blink catalogs and exact-window views; no rescoring.
.brohn_gt_recipe <- "saved-gaze-trace-view/1.0"
.brohn_gt_dependencies <- c("R/platform-gaze-trace-jobs.R", "R/platform-gaze-traces.R", "R/platform-gaze-trace-views.R", "scripts/workers/gaze_trace.py", "scripts/workers/physiology_artifacts.py")
.brohn_gt_loaded <- stats::setNames(lapply(.brohn_gt_dependencies, function(path) digest::digest(file = path, algo = "sha256")), .brohn_gt_dependencies)
.brohn_gt_same <- function(a, b) identical(brohn_hash(a), brohn_hash(b))

.brohn_gt_retained <- function(store, record, report = FALSE, verify = TRUE) {
  ref <- record$body$result_object
  brohn_require(is.list(ref) && brohn_text(ref$hash, 64) && brohn_number(ref$size, 1, 16*1024^2, TRUE), "The saved trace source lacks its retained result envelope.")
  path <- brohn_object_path(store, ref$hash, verify = verify)
  if (verify) {
    saved <- brohn_read_json_file(path)
    if (report) saved <- saved$report
    brohn_require(.brohn_gt_same(saved, record$body[setdiff(names(record$body), "result_object")]), "Saved trace source differs from its retained envelope.")
  }
  list(hash = ref$hash, bytes = ref$size)
}

brohn_gaze_trace_job_input <- function(store, job, verify = TRUE) {
  r <- job$request
  brohn_fields(r, c("report_id", "report_revision", "report_hash", "project_id", "artifact", "catalog", "selection", "recipe", "implementation"), label = "Saved gaze trace request")
  brohn_require(job$operation %in% c("gaze_trace_catalog", "gaze_trace_preview") && identical(r$recipe, .brohn_gt_recipe), "Choose a registered saved gaze trace operation.")
  brohn_require(brohn_valid_id(r$report_id) && brohn_number(r$report_revision, 1, 2^53-1, TRUE) && brohn_text(r$report_hash, 64), "Choose an exact saved gaze report revision.")
  .brohn_qexplorer_catalog(store, "report", r$report_id, r$report_revision, r$project_id)
  brohn_project(store, r$project_id)
  report <- brohn_get_entity(store, "report", r$report_id, r$report_revision)
  brohn_require(identical(brohn_hash(report$body), r$report_hash) && identical(report$body$analysis$kind, "gaze") &&
    identical(report$body$analysis$parameters$trace_profile, "gaze-pupil-source-trace/1.0") &&
    identical(report$body$analysis$parameters$blink_boundary_policy, "source-labelled-blink-boundaries/1.1"),
    "This report has no complete versioned pupil/blink source trace. Run a fresh original analysis; historical summaries cannot reconstruct samples.")
  p <- report$body$provenance
  brohn_require(is.list(p$design) && identical(brohn_hash(p$design), p$design_hash) && identical(report$body$study_id, p$design$id), "The pinned gaze study provenance changed.")
  artifact <- brohn_signal_artifact(report, "physiology-series")
  brohn_require(.brohn_gt_same(artifact, r$artifact), "The complete pupil/blink artifact changed after selection.")
  brohn_require(.brohn_gt_same(r$implementation, .brohn_gt_loaded) &&
    all(vapply(names(.brohn_gt_loaded), function(path) identical(digest::digest(file = path, algo = "sha256"), .brohn_gt_loaded[[path]]), logical(1))),
    "The saved-trace reader changed. Restart the service and prepare a fresh view from the original retained report.")
  refs <- list(list(hash = artifact$sha256, bytes = artifact$bytes), .brohn_gt_retained(store, report, report = TRUE, verify = verify))
  table <- NULL
  if (identical(job$operation, "gaze_trace_catalog")) brohn_require(is.null(r$catalog) && is.null(r$selection), "A complete trace catalog has no exposure or time selection.") else {
    brohn_fields(r$catalog, c("id", "revision", "hash"), label = "Saved gaze trace catalog")
    .brohn_qexplorer_catalog(store, "gaze_trace_view", r$catalog$id, r$catalog$revision, r$project_id)
    catalog <- brohn_get_entity(store, "gaze_trace_view", r$catalog$id, r$catalog$revision)
    brohn_require(identical(brohn_hash(catalog$body), r$catalog$hash) && identical(catalog$body$operation, "gaze_trace_catalog") &&
      .brohn_gt_same(catalog$body$request[c("report_id", "report_revision", "report_hash", "project_id", "artifact")], r[c("report_id", "report_revision", "report_hash", "project_id", "artifact")]),
      "The trace catalog belongs to another report, source or project.")
    brohn_fields(r$selection, c("table_id", "identity", "start_ms", "end_ms"), label = "Exact trace window")
    found <- Filter(function(t) identical(t$table_id, r$selection$table_id), catalog$body$result$tables)
    brohn_require(length(found) == 1L && .brohn_gt_same(found[[1L]]$identity, r$selection$identity), "Choose one exact exposure from this complete catalog.")
    table <- found[[1L]]
    brohn_require((is.null(r$selection$start_ms) && is.null(r$selection$end_ms)) ||
      brohn_number(r$selection$start_ms, 0, 1e12) && brohn_number(r$selection$end_ms, 0, 1e12) && r$selection$start_ms < r$selection$end_ms,
      "Enter two increasing finite source times in milliseconds, or explicitly select the full range.")
    refs[[length(refs)+1L]] <- .brohn_gt_retained(store, catalog, verify = verify)
  }
  list(schema = "brohn-analysis-input/1.0", operation = job$operation, project_id = r$project_id, origin = report$body$origin,
    binding = r[c("report_id", "report_revision", "report_hash", "project_id", "catalog", "selection")],
    artifact = artifact, source_path = brohn_object_path(store, artifact$sha256, verify = verify), source_objects = refs,
    original_source_hash = p$source$hash, table = table, selection = r$selection)
}

brohn_queue_gaze_trace <- function(store, report_id, report_revision, report_hash, project_id, catalog = NULL, selection = NULL, retry = FALSE) {
  .brohn_qexplorer_catalog(store, "report", report_id, report_revision, project_id)
  report <- brohn_get_entity(store, "report", report_id, report_revision)
  request <- list(report_id = report_id, report_revision = report_revision, report_hash = report_hash, project_id = project_id,
    artifact = brohn_signal_artifact(report, "physiology-series"), catalog = catalog, selection = selection,
    recipe = .brohn_gt_recipe, implementation = .brohn_gt_loaded)
  operation <- if (is.null(catalog)) "gaze_trace_catalog" else "gaze_trace_preview"
  brohn_gaze_trace_job_input(store, list(operation = operation, request = request), verify = FALSE)
  brohn_enqueue_job(store, operation, request, paste0(operation, ":", brohn_hash(request), if (retry) paste0(":", brohn_id("retry")) else ""))
}

brohn_hold_gaze_trace_sources <- function(store, input) {
  brohn_require(.Platform$OS.type == "windows", "Saved gaze trace publication requires the qualified native Windows read guard.")
  guards <- list(); success <- FALSE; seen <- character()
  on.exit(if (!success) for (guard in guards) .brohn_qexplorer_release(guard), add = TRUE)
  for (ref in input$source_objects) if (!ref$hash %in% seen) {
    guards[[length(guards)+1L]] <- .brohn_qexplorer_hold(brohn_object_path(store, ref$hash, verify = FALSE), ref$bytes)
    seen <- c(seen, ref$hash)
  }
  success <- TRUE; guards
}

brohn_validate_gaze_trace_result <- function(result, input) {
  brohn_require(identical(result$schema, "brohn-gaze-trace-preview/1.0") && identical(result$trace_profile, "gaze-pupil-source-trace/1.0") &&
    .brohn_gt_same(result$binding, input$binding), "The saved trace result substituted its exact source binding.")
  for (field in c("kind", "sha256", "bytes", "schema", "provenance_sha256"))
    brohn_require(.brohn_gt_same(result$artifact[[field]], input$artifact[[field]]), "The trace result belongs to another complete artifact.")
  brohn_require(identical(result$source_provenance$source_sha256, input$original_source_hash) && identical(result$source_provenance$operation, "gaze"),
    "The trace artifact does not belong to this report's original source bytes.")
  if (identical(input$operation, "gaze_trace_catalog")) {
    brohn_require(identical(result$operation, "catalog") && isTRUE(result$complete) && result$source_rows == input$artifact$rows &&
      brohn_array(result$tables) && length(result$tables) == input$artifact$tables && length(result$tables) <= 10000L,
      "The complete trace catalog was truncated or changed its source denominator.")
    ids <- character(); total <- 0
    for (t in result$tables) {
      brohn_require(brohn_text(t$table_id, 160) && !t$table_id %in% ids && is.list(t$identity) &&
        brohn_number(t$rows, 2, 2000000, TRUE) && brohn_number(t$start_ms, 0, 1e12) && brohn_number(t$end_ms, t$start_ms, 1e12) && t$end_ms > t$start_ms &&
        t$initial_window$start_ms == t$start_ms && brohn_number(t$initial_window$end_ms, t$start_ms, t$end_ms) &&
        t$initial_window$rows == min(t$rows, 5000), "Trace catalog coordinates or exact row counts are invalid.")
      ids <- c(ids, t$table_id); total <- total+t$rows
    }
    brohn_require(total == input$artifact$rows, "The complete trace catalog lost source rows.")
  } else {
    brohn_require(identical(result$table$table_id, input$selection$table_id) && .brohn_gt_same(result$table$identity, input$selection$identity) &&
      result$table$expected_rows == input$table$rows && .brohn_gt_same(result$range$start_ms, input$selection$start_ms) &&
      .brohn_gt_same(result$range$end_ms, input$selection$end_ms) && identical(result$range$boundary, "both endpoints included"),
      "The trace preview changed its selected exposure or source time bounds.")
    brohn_gaze_trace_plot_model(result)
    for (row in result$rows) {
      brohn_require(brohn_text(row$exact_record_json, 2*1024^2), "Exact trace rows require their native JSON representation.")
      native <- brohn_parse(row$exact_record_json, max_bytes = 2*1024^2)
      for (field in c("source_row", "analysis_time_ms", "pupil", "pupil_minus_baseline", "phase", "pupil_text", "source_blink", "effective_pupil_valid")) {
        a <- row[[field]]; b <- native[[field]]
        same <- if (field %in% c("source_row", "analysis_time_ms", "pupil", "pupil_minus_baseline"))
          is.null(a) && is.null(b) || .brohn_gaze_trace_finite(a) && .brohn_gaze_trace_finite(b) && a == b else .brohn_gt_same(a, b)
        brohn_require(same, "A chart convenience field disagrees with its exact saved source row.")
      }
    }
  }
  no_paths <- function(x) !is.list(x) || (!any(names(x) %in% c("path", "source_path", "output_path", "exchange_path")) && all(vapply(x, no_paths, logical(1))))
  brohn_require(no_paths(result), "Private worker paths cannot enter a saved trace result.")
  invisible(result)
}

brohn_analyse_gaze_trace <- function(input, scratch) {
  artifact <- c(input$artifact, list(path = normalizePath(input$source_path, winslash = "/", mustWork = TRUE)))
  result <- if (identical(input$operation, "gaze_trace_catalog")) brohn_gaze_trace_read(artifact, scratch) else
    brohn_gaze_trace_read(artifact, scratch, input$table, input$selection$start_ms, input$selection$end_ms)
  result$binding <- input$binding
  # Catalog JSON uses numeric convenience fields; exact_record_json and decimal
  # strings preserve every native binary64 value, including signed zero.
  result <- brohn_parse(brohn_json(result))
  brohn_validate_gaze_trace_result(result, input)
  list(gaze_trace_view = result)
}

brohn_publish_gaze_trace <- function(store, output, scratch, job, input, output_path) {
  brohn_require(!RSQLite::sqliteIsTransacting(store$con), "Prepare saved trace publication outside its final writer transaction.")
  .brohn_publication_output_identity(output, .brohn_gt_loaded); .brohn_publication_job(store, job)
  guards <- brohn_hold_gaze_trace_sources(store, input)
  on.exit(for (guard in guards) .brohn_qexplorer_release(guard), add = TRUE)
  brohn_require(.brohn_gt_same(input, brohn_gaze_trace_job_input(store, job)) && .brohn_gt_same(brohn_read_json_file(output_path), output),
    "The saved trace's pinned input or worker output changed before publication.")
  result <- output$report$gaze_trace_view; brohn_validate_gaze_trace_result(result, input)
  id <- paste0("gaze-trace-", sub("^job-", "", job$id))
  body <- list(schema = "brohn-saved-gaze-trace-view/1.0", id = id, operation = job$operation, origin = input$origin,
    report_id = input$binding$report_id, request = job$request, result = result, created_at = brohn_now(),
    processing = list(job_id = job$id, attempt = job$attempt, worker_output_hash = digest::digest(file = output_path, algo = "sha256"), code_hashes = output$code_identity))
  document <- .brohn_publication_stage_json(store, job, body, file.path(scratch, "published-gaze-trace.json"))
  committed <- FALSE; on.exit(brohn_close_publication(document$guard, committed), add = TRUE)
  receipt <- brohn_store_batch(store, function() {
    brohn_require(.brohn_gt_same(input, brohn_gaze_trace_job_input(store, job, verify = FALSE)), "Trace source or project authority changed before publication.")
    for (guard in guards) .Call(guard$native$check, guard$pointer)
    .brohn_publication_job(store, job)
    body$result_object <- .brohn_publication_register(store, document)[[1L]][c("hash", "size", "media_type")]
    brohn_put_entity(store, "gaze_trace_view", id, body, expected_revision = 0L, project_id = input$project_id)
    brohn_complete_job(store, job$id, job$worker, job$token, list(gaze_trace_view_id = id, report_id = input$binding$report_id, output_hash = body$result_object$hash))
  })
  committed <- TRUE; receipt
}

brohn_gaze_trace_record <- function(store, id, expected_hash = NULL, verify = FALSE) {
  record <- brohn_get_entity(store, "gaze_trace_view", id)
  brohn_require(!is.null(record) && identical(record$body$schema, "brohn-saved-gaze-trace-view/1.0"), "The saved gaze trace view is unavailable.")
  if (!is.null(expected_hash)) brohn_require(identical(brohn_hash(record$body), expected_hash), "The saved trace view changed. Reopen it.")
  .brohn_qexplorer_catalog(store, "gaze_trace_view", record$id, record$revision, record$project_id)
  input <- brohn_gaze_trace_job_input(store, list(operation = record$body$operation, request = record$body$request), verify = verify)
  brohn_require(identical(record$project_id, input$project_id), "The saved trace view belongs to another project.")
  if (verify) { .brohn_gt_retained(store, record, verify = TRUE); brohn_validate_gaze_trace_result(record$body$result, input) }
  record
}
