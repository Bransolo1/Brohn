# Versioned interval annotations refer to exact complete processed source tables.
.brohn_annotations_source <- function(store, body, project_id, verify = FALSE) {
  brohn_project(store, project_id)
  current <- brohn_get_entity(store, "report", body$report_id)
  report <- brohn_get_entity(store, "report", body$report_id, body$report_revision)
  brohn_require(!is.null(current) && !is.null(report) && identical(current$project_id, project_id) &&
    identical(report$project_id, project_id) && identical(brohn_hash(report$body), body$report_hash),
    "Reopen the original saved report; this annotation source is unavailable or changed project.")
  artifact <- brohn_signal_artifact(report, "physiology-series")
  brohn_require(identical(artifact$sha256, body$artifact_hash), "The annotations belong to another processed recording.")
  list(report = report, artifact = artifact, path = brohn_object_path(store, artifact$sha256, verify = verify))
}
brohn_validate_signal_intervals <- function(intervals, allow_empty = TRUE) {
  brohn_require(brohn_array(intervals) && length(intervals) <= 64L && (allow_empty || length(intervals) > 0L), "Save between 1 and 64 intervals before calculating summaries.")
  for (interval in intervals) {
    brohn_fields(interval, c("id", "label", "category", "start_s", "end_s", "note"), label = "Saved interval")
    brohn_require(brohn_valid_id(interval$id) && nchar(interval$id) <= 160 && brohn_text(interval$label, 240) && nzchar(trimws(interval$label)) &&
      brohn_text(interval$category, 120, TRUE) && brohn_text(interval$note, 4000, TRUE), "Give each interval a label and bounded category/note.")
    brohn_require(brohn_number(interval$start_s) && brohn_number(interval$end_s) && interval$start_s < interval$end_s,
      "Interval start must precede its exclusive end, in the saved recording's seconds.")
  }
  brohn_require(!anyDuplicated(brohn_ids(intervals)), "Saved interval identities must be distinct.")
  invisible(intervals)
}
brohn_create_signal_annotations <- function(store, catalog_id, table_id, title) {
  brohn_require(brohn_text(title, 240) && nzchar(trimws(title)), "Name this set of recording intervals.")
  catalog <- brohn_get_entity(store, "signal_view", catalog_id)
  brohn_require(!is.null(catalog) && identical(catalog$body$operation, "signal_catalog"), "Read the saved signal catalog before annotating a recording.")
  source <- .brohn_annotations_source(store, catalog$body, catalog$project_id)
  tables <- Filter(function(t) identical(t$table_id, table_id), catalog$body$view$tables)
  brohn_require(length(tables) == 1L && identical(tables[[1L]]$coordinates$axis, "time") && identical(tables[[1L]]$coordinate_column$unit, "s"),
    "Choose a time-series table in seconds; spectra and detected-event tables use different analyses.")
  id <- brohn_id("intervals")
  body <- list(schema_version = "brohn-signal-annotations/1.0", id = id, title = title,
    report_id = source$report$id, report_revision = source$report$revision, report_hash = brohn_hash(source$report$body),
    artifact_hash = source$artifact$sha256, origin = source$report$body$origin,
    catalog_id = catalog$id, catalog_revision = catalog$revision, catalog_hash = brohn_hash(catalog$body),
    table = tables[[1L]], intervals = list(), boundary = "start inclusive, end exclusive", created_at = brohn_now())
  brohn_put_entity(store, "signal_annotations", id, body, project_id = catalog$project_id)
}
brohn_signal_annotations <- function(store, id, revision = NULL, hash = NULL) {
  record <- brohn_get_entity(store, "signal_annotations", id, revision)
  latest <- brohn_get_entity(store, "signal_annotations", id)
  brohn_require(!is.null(record) && !is.null(latest) && identical(record$project_id, latest$project_id) &&
    identical(record$body$schema_version, "brohn-signal-annotations/1.0") && (is.null(hash) || identical(brohn_hash(record$body), hash)),
    "Reopen the saved interval set and its exact version.")
  .brohn_annotations_source(store, record$body, record$project_id)
  catalog <- brohn_get_entity(store, "signal_view", record$body$catalog_id, record$body$catalog_revision)
  brohn_require(!is.null(catalog) && identical(catalog$project_id, record$project_id) && identical(brohn_hash(catalog$body), record$body$catalog_hash),
    "The annotation set's original signal catalog is unavailable.")
  tables <- Filter(function(t) identical(t$table_id, record$body$table$table_id), catalog$body$view$tables)
  brohn_require(length(tables) == 1L && identical(brohn_hash(tables[[1L]]), brohn_hash(record$body$table)), "The saved table identity or clock context changed.")
  brohn_validate_signal_intervals(record$body$intervals)
  record
}
brohn_save_signal_interval <- function(store, id, expected_revision, label, category, start_s, end_s, note = "", interval_id = NULL) {
  record <- brohn_signal_annotations(store, id)
  brohn_require(identical(as.integer(expected_revision), record$revision), "These intervals changed. Reopen their current version before saving.")
  body <- record$body
  if (is.null(interval_id)) interval_id <- brohn_id("interval") else
    brohn_require(interval_id %in% brohn_ids(body$intervals), "Select an interval from this saved set before editing.")
  value <- list(id = interval_id, label = label, category = category, start_s = start_s, end_s = end_s, note = note)
  index <- match(interval_id, brohn_ids(body$intervals))
  if (is.na(index)) body$intervals[[length(body$intervals)+1L]] <- value else body$intervals[[index]] <- value
  brohn_validate_signal_intervals(body$intervals)
  brohn_put_entity(store, "signal_annotations", id, body, expected_revision = record$revision, project_id = record$project_id)
}
brohn_remove_signal_interval <- function(store, id, expected_revision, interval_id) {
  record <- brohn_signal_annotations(store, id)
  brohn_require(identical(as.integer(expected_revision), record$revision) && interval_id %in% brohn_ids(record$body$intervals),
    "Reopen the current interval before removing it; its earlier revision remains in history.")
  body <- record$body; body$intervals <- Filter(function(i) !identical(i$id, interval_id), body$intervals)
  brohn_put_entity(store, "signal_annotations", id, body, expected_revision = record$revision, project_id = record$project_id)
}
brohn_queue_signal_windows <- function(store, id, revision, hash, value_columns) {
  record <- brohn_signal_annotations(store, id, revision, hash)
  brohn_validate_signal_intervals(record$body$intervals, FALSE)
  brohn_require(brohn_array(value_columns) && length(value_columns) %in% 1:16 && !anyDuplicated(unlist(value_columns)) &&
    all(vapply(value_columns, function(v) brohn_text(v, 500) && v %in% vapply(record$body$table$value_columns, `[[`, character(1), "name"), logical(1))),
    "Choose up to 16 distinct numeric measures from this saved time-series table.")
  request <- list(annotation_id = id, annotation_revision = record$revision, annotation_hash = brohn_hash(record$body),
    project_id = record$project_id, value_columns = value_columns, recipe = "saved-signal-intervals/1.0.0")
  brohn_enqueue_job(store, "summarize_signal_windows", request, paste0("signal-windows:", brohn_hash(request)))
}
brohn_restore_signal_intervals <- function(store, id, expected_revision, source_revision, source_hash) {
  current <- brohn_signal_annotations(store,id)
  brohn_require(brohn_number(expected_revision,1,Inf,TRUE) && expected_revision==current$revision &&
    brohn_number(source_revision,1,current$revision-1L,TRUE), "Reopen the current set and review an earlier version before restoring.")
  previous <- brohn_signal_annotations(store,id,as.integer(source_revision),source_hash)
  body <- current$body; body$intervals <- previous$body$intervals
  brohn_validate_signal_intervals(body$intervals)
  brohn_put_entity(store,"signal_annotations",id,body,expected_revision=current$revision,project_id=current$project_id)
}
brohn_signal_windows_input <- function(store, job) {
  r <- job$request; record <- brohn_signal_annotations(store, r$annotation_id, r$annotation_revision, r$annotation_hash)
  brohn_require(identical(record$project_id, r$project_id) && identical(r$recipe, "saved-signal-intervals/1.0.0"), "The interval job belongs to another project or recipe.")
  source <- .brohn_annotations_source(store, record$body, record$project_id, verify = TRUE)
  brohn_validate_signal_intervals(record$body$intervals, FALSE)
  list(schema = "brohn-analysis-input/1.0", operation = job$operation, project_id = record$project_id,
    annotation_source = list(id = record$id, revision = record$revision, hash = brohn_hash(record$body)),
    report_id = source$report$id, report_revision = source$report$revision, report_hash = brohn_hash(source$report$body),
    origin = source$report$body$origin, artifact = source$artifact, source_path = source$path,
    verification_receipt = source$report$body$analysis$artifact_verification,
    selection = list(table_id = record$body$table$table_id, identity = record$body$table$identity,
      coordinates = record$body$table$coordinates, value_columns = r$value_columns), intervals = record$body$intervals)
}
brohn_validate_signal_windows_result <- function(result, input) {
  brohn_require(identical(result$schema, "brohn-signal-window-summary/1.0") && identical(result$status, "completed"), "The saved interval summary is unavailable.")
  for (field in c("annotation_source", "selection", "intervals"))
    brohn_require(identical(brohn_hash(result[[field]]), brohn_hash(input[[field]])), "The interval summary substituted a different source, selection or annotation version.")
  for (field in c("kind", "sha256", "bytes", "schema", "tables", "rows", "provenance_sha256"))
    brohn_require(identical(brohn_hash(result$artifact[[field]]), brohn_hash(input$artifact[[field]])), "The interval summary came from another processed source.")
  brohn_require(brohn_array(result$summaries) && length(result$summaries) == length(input$intervals)*length(input$selection$value_columns),
    "The interval summary omitted a requested interval or measure.")
  invisible(result)
}
brohn_analyse_signal_windows <- function(input, scratch) {
  request <- list(schema = "brohn-signal-window-request/1.0", artifact = c(input$artifact, list(path = normalizePath(input$source_path, winslash = "/", mustWork = TRUE))),
    verification_receipt = input$verification_receipt, selection = input$selection, annotation_source = input$annotation_source, intervals = input$intervals)
  request_path <- file.path(scratch, "signal-windows-request.json"); result_path <- file.path(scratch, "signal-windows-result.json")
  brohn_write_json_file(request, request_path, maximum = 2*1024^2)
  child <- processx::run(brohn_python_profile("eda"), c("scripts/workers/signal_windows.py", "--request", request_path, "--output", result_path),
    timeout = 300, error_on_status = FALSE, cleanup_tree = TRUE, windows_hide_window = TRUE)
  brohn_require(file.exists(result_path), paste("The saved intervals could not be summarized.", substr(child$stderr, 1, 1000)))
  result <- brohn_read_json_file(result_path)
  brohn_require(child$status == 0 && !identical(result$status, "error"), paste("Intervals need attention:", brohn_default(result$error$message, substr(child$stderr, 1, 1000))))
  brohn_validate_signal_windows_result(result, input)
  list(signal_window_summary = result)
}
brohn_publish_signal_windows <- function(store, output, scratch, job, input, output_path) {
  .brohn_publication_job(store, job)
  brohn_require(identical(brohn_hash(input), brohn_hash(brohn_signal_windows_input(store, job))), "Interval publication substituted its saved source or annotation revision.")
  result <- output$report$signal_window_summary; brohn_validate_signal_windows_result(result, input)
  id <- paste0("signal-windows-", sub("^job[-_]", "", job$id))
  body <- list(schema_version = "brohn-saved-signal-windows/1.0", id = id, report_id = input$report_id,
    report_revision = input$report_revision, report_hash = input$report_hash, origin = input$origin,
    annotation_source = input$annotation_source, summary = result, created_at = brohn_now(),
    processing = list(job_id = job$id, attempt = job$attempt, request_hash = brohn_hash(input),
      worker_output_hash = digest::digest(file = output_path, algo = "sha256"), code_hashes = output$code_identity))
  path <- file.path(scratch, "published-signal-windows.json"); brohn_write_json_file(body, path)
  brohn_publish_entity_result(store, job, input, output, "signal_windows", body, path,
    list(signal_windows_id = id, report_id = input$report_id, annotation_id = input$annotation_source$id))
}
