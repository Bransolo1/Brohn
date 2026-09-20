# Unregistered until complete index/storage/UI acceptance. This adapter binds a
# derived browsing index to an existing report; it never requests new scoring.
.brohn_questionnaire_index_recipe <- "questionnaire-explorer-index/1.0"
.brohn_qexplorer_schema <- "brohn-saved-questionnaire-index/1.0"
.brohn_qexplorer_loaded <- stats::setNames(lapply(c("R/platform-questionnaire-explorer.R", "R/platform-questionnaire-index.R"),
  function(path) digest::digest(file = path, algo = "sha256")), c("R/platform-questionnaire-explorer.R", "R/platform-questionnaire-index.R"))
.brohn_qexplorer_catalog <- function(store, kind, id, revision, project_id) {
  rows <- DBI::dbGetQuery(store$con, "SELECT v.project_id,v.body_hash,e.project_id AS current_project_id FROM entity_versions v JOIN entities e ON e.kind=v.kind AND e.id=v.id WHERE v.kind=? AND v.id=? AND v.revision=?",
    params = list(kind, id, revision))
  brohn_require(nrow(rows) == 1L && identical(rows$project_id[[1L]], project_id) && identical(rows$current_project_id[[1L]], project_id), "This saved source revision is unavailable in the selected project.")
  rows$body_hash[[1L]]
}
.brohn_questionnaire_index_source <- function(store, report_id, report_revision, expected_report_hash, project_id, verify_bytes = TRUE) {
  brohn_require(brohn_valid_id(report_id) && brohn_number(report_revision, 1, 1e9, TRUE) &&
    .brohn_questionnaire_artifact_hash(expected_report_hash) && brohn_text(project_id, 96), "Choose the exact saved report and project before exploring its answers.")
  # Resolve project metadata before reading a report body or returning its title.
  catalog_hash <- .brohn_qexplorer_catalog(store, "report", report_id, report_revision, project_id)
  brohn_project(store, project_id)
  report <- brohn_get_entity(store, "report", report_id, report_revision)
  brohn_require(!is.null(report) && identical(brohn_hash(report$body), expected_report_hash), "The saved report changed after selection. Open its exact revision again.")
  body <- report$body
  brohn_require(identical(body$id, report_id) && identical(body$analysis$kind, "questionnaire") && brohn_text(body$origin, 128),
    "Choose a saved questionnaire report with its exact identity and origin.")
  brohn_require(is.list(body$provenance$design) && identical(brohn_hash(body$provenance$design), body$provenance$design_hash) &&
    identical(body$study_id, body$provenance$design$id), "The saved questionnaire report has inconsistent frozen study provenance.")
  if (!is.null(body$provenance$design$project_id)) brohn_require(identical(body$provenance$design$project_id, project_id), "The frozen study belongs to another project.")
  analysis_hash <- if (brohn_questionnaire_is_artifact(body$analysis)) body$analysis$questionnaire_artifact$analysis_sha256 else brohn_hash(body$analysis)
  brohn_require(.brohn_questionnaire_artifact_hash(analysis_hash), "The saved questionnaire analysis has no exact content identity.")
  retained_result <- body$result_object
  source_support <- if (is.null(retained_result)) "catalog_revision_without_retained_worker_envelope" else "catalog_revision_with_verified_retained_result"
  if (!is.null(retained_result) && verify_bytes) {
    original <- brohn_read_json_file(brohn_object_path(store, retained_result$hash, verify = TRUE))
    brohn_require(identical(original$schema, "brohn-analysis-output/1.0") && is.list(original$report) &&
      identical(brohn_hash(original$report), brohn_hash(body[setdiff(names(body), "result_object")])),
      "The saved questionnaire source differs from its retained result object.")
  }
  reference <- if (brohn_questionnaire_is_artifact(body$analysis)) brohn_questionnaire_report_artifact(body) else NULL
  path <- if (!is.null(reference)) brohn_object_path(store, reference$hash, verify = verify_bytes) else NULL
  binding <- list(workspace_id = store$workspace_id, project_id = project_id, report_id = report$id,
    report_revision = report$revision, report_hash = expected_report_hash, origin = body$origin, analysis_sha256 = analysis_hash)
  list(report = report, binding = binding, artifact_path = path, artifact = reference, source_support = source_support,
    catalog_hash = catalog_hash, result_object = retained_result, provenance_hash = brohn_hash(body$provenance))
}
brohn_prepare_questionnaire_index <- function(store, report_id, report_revision, expected_report_hash, project_id) {
  # Source bytes are verified by the supervised input resolver. The button only
  # checks small catalog metadata and file presence, keeping the UI responsive.
  source <- .brohn_questionnaire_index_source(store, report_id, report_revision, expected_report_hash, project_id, verify_bytes = FALSE)
  list(schema = "brohn-questionnaire-index-request/1.0", recipe = .brohn_questionnaire_index_recipe,
    project_id = project_id, report_id = report_id, report_revision = report_revision, report_hash = expected_report_hash,
    binding = source$binding, artifact = source$artifact, source_support = source$source_support,
    catalog_hash = source$catalog_hash, result_object = source$result_object, provenance_hash = source$provenance_hash,
    implementation = .brohn_qexplorer_loaded)
}
.brohn_qexplorer_latest <- function(store, request) {
  rows <- DBI::dbGetQuery(store$con, "SELECT * FROM jobs WHERE operation='questionnaire_index' AND request_hash=? ORDER BY created_at DESC,rowid DESC LIMIT 1",
    params = list(.brohn_store_hash(charToRaw(.brohn_store_json(request)))))
  if (!nrow(rows)) return(NULL)
  job <- .brohn_store_job(rows)
  brohn_require(identical(brohn_hash(job$request), brohn_hash(request)), "The saved-answer request hash is inconsistent.")
  job
}
.brohn_qexplorer_idle <- function(store) {
  pending <- brohn_list_jobs(store, limit = 1L, operation = "questionnaire_index", status = c("queued", "running"))
  brohn_require(!length(pending), "Another saved-answer view is being prepared. Let it finish or cancel it in Activity before preparing this one.")
}
brohn_queue_questionnaire_index <- function(store, report_id, report_revision, expected_report_hash, project_id, rebuild = FALSE) {
  brohn_require(is.logical(rebuild) && length(rebuild) == 1L && !is.na(rebuild), "Choose whether to reuse or explicitly rebuild this saved view.")
  request <- brohn_prepare_questionnaire_index(store, report_id, report_revision, expected_report_hash, project_id)
  key <- paste0("questionnaire-index:", brohn_hash(request))
  brohn_store_batch(store, function() {
    brohn_project(store, project_id)
    brohn_require(identical(.brohn_qexplorer_catalog(store, "report", report_id, report_revision, project_id), request$catalog_hash),
      "The selected report authority changed before the view could be queued.")
    if (!rebuild) {
      old <- .brohn_qexplorer_latest(store, request)
      if (!is.null(old)) return(old)
    }
    .brohn_qexplorer_idle(store)
    brohn_enqueue_job(store, "questionnaire_index", request, if (rebuild) paste0(key, ":", brohn_id("rebuild")) else key)
  })
}
brohn_questionnaire_index_input <- function(store, job) {
  r <- job$request
  brohn_fields(r, c("schema", "recipe", "project_id", "report_id", "report_revision", "report_hash", "binding", "artifact", "source_support",
    "catalog_hash", "result_object", "provenance_hash", "implementation"), label = "Saved-answer view request")
  brohn_require(identical(job$operation, "questionnaire_index") && identical(r$schema, "brohn-questionnaire-index-request/1.0") &&
    identical(r$recipe, .brohn_questionnaire_index_recipe), "Unsupported saved-answer view request.")
  source <- .brohn_questionnaire_index_source(store, r$report_id, r$report_revision, r$report_hash, r$project_id)
  brohn_require(identical(brohn_hash(source$binding), brohn_hash(r$binding)) &&
    identical(brohn_hash(source$artifact), brohn_hash(r$artifact)) && identical(source$source_support, r$source_support),
    "The pinned questionnaire source no longer matches this view request.")
  brohn_require(identical(source$catalog_hash, r$catalog_hash) && identical(brohn_hash(source$result_object), brohn_hash(r$result_object)) &&
    identical(source$provenance_hash, r$provenance_hash) && identical(brohn_hash(r$implementation), brohn_hash(.brohn_qexplorer_loaded)) &&
    all(vapply(names(r$implementation), function(path) identical(digest::digest(file = path, algo = "sha256"), r$implementation[[path]]), logical(1))),
    "The exact source or saved-answer implementation changed. Prepare a new view from the retained report.")
  list(schema = "brohn-analysis-input/1.0", operation = "questionnaire_index", project_id = r$project_id,
    index_input = list(schema = "brohn-questionnaire-index-input/1.0", binding = source$binding,
      report = source$report$body, artifact_path = source$artifact_path))
}

.brohn_qexplorer_job <- function(store, job_id, project_id) {
  brohn_require(brohn_text(job_id, 96) && brohn_text(project_id, 96), "Choose the saved-answer request in this project.")
  brohn_project(store, project_id)
  rows <- DBI::dbGetQuery(store$con, "SELECT id FROM jobs WHERE id=? AND operation='questionnaire_index' AND json_extract(request_json,'$.project_id')=?",
    params = list(job_id, project_id))
  brohn_require(nrow(rows) == 1L, "This saved-answer request is unavailable in the selected project.")
  brohn_get_job(store, job_id)
}
brohn_cancel_questionnaire_index <- function(store, job_id, project_id) {
  job <- .brohn_qexplorer_job(store, job_id, project_id)
  brohn_require(job$status %in% c("queued", "running", "cancelled"), "Only an active saved-answer request can be cancelled.")
  brohn_cancel_job(store, job_id)
}
brohn_retry_questionnaire_index <- function(store, job_id, project_id) {
  old <- .brohn_qexplorer_job(store, job_id, project_id)
  brohn_require(old$status %in% c("failed", "cancelled"), "Only a failed or cancelled saved-answer request can be retried.")
  # Full source verification remains in the supervised input resolver.
  request <- brohn_prepare_questionnaire_index(store, old$request$report_id, old$request$report_revision, old$request$report_hash, project_id)
  brohn_require(identical(brohn_hash(request), brohn_hash(old$request)), "The old view uses another implementation or source. Explicitly rebuild from the retained report.")
  brohn_store_batch(store, function() {
    brohn_project(store, project_id)
    brohn_require(identical(.brohn_qexplorer_catalog(store, "report", request$report_id, request$report_revision, project_id), request$catalog_hash),
      "The selected report authority changed before the view could be retried.")
    latest <- .brohn_qexplorer_latest(store, request)
    if (!identical(latest$id, old$id)) return(latest)
    .brohn_qexplorer_idle(store)
    job <- brohn_enqueue_job(store, "questionnaire_index", old$request, paste0("questionnaire-index-retry:", old$id, ":", brohn_id("retry")))
    brohn_put_entity(store, "job_retry", brohn_id("retry"), list(source_job_id = old$id, new_job_id = job$id,
      at = brohn_now(), policy = "same_frozen_inputs_new_attempt"), project_id = project_id)
    job
  })
}
brohn_analyse_questionnaire_index <- function(input, scratch) {
  brohn_fields(input, c("schema", "operation", "project_id", "index_input"), label = "Questionnaire explorer input")
  brohn_require(identical(input$schema, "brohn-analysis-input/1.0") && identical(input$operation, "questionnaire_index") &&
    identical(input$project_id, input$index_input$binding$project_id), "Unsupported source-bound questionnaire index input.")
  directory <- file.path(scratch, "artifacts"); brohn_require(!dir.exists(directory) && dir.create(directory), "Choose a new owned index-build directory.")
  list(questionnaire_index = brohn_build_questionnaire_index(input$index_input, file.path(directory, "questionnaire-index.sqlite")))
}

brohn_publish_questionnaire_index <- function(store, output, scratch, job, input, output_path) {
  brohn_require(.Platform$OS.type == "windows", "Saved-answer index publication currently requires the qualified Windows native file guard.")
  brohn_require(!RSQLite::sqliteIsTransacting(store$con), "Prepare complete indexes outside the metadata transaction.")
  .brohn_publication_output_identity(output, .brohn_qexplorer_loaded); .brohn_publication_job(store, job)
  output_path <- .brohn_store_contained(store, output_path)
  brohn_require(file.exists(output_path) && !dir.exists(output_path) &&
    identical(tolower(dirname(output_path)), tolower(normalizePath(scratch, winslash = "/", mustWork = TRUE))),
    "The questionnaire worker output leaves its owned attempt directory.")
  # Hold retained source objects before re-verifying them, through the final
  # catalog commit. Their initial input verification alone is not a lifetime seal.
  source_guards <- .brohn_qexplorer_source_guards(store, job$request)
  on.exit(for (guard in source_guards) .brohn_qexplorer_release(guard), add = TRUE)
  brohn_require(identical(brohn_hash(input), brohn_hash(brohn_questionnaire_index_input(store, job))) &&
    identical(brohn_hash(brohn_read_json_file(output_path)), brohn_hash(output)), "Questionnaire view publication substituted its pinned input or output.")
  result <- output$report$questionnaire_index
  brohn_fields(result, c("schema", "status", "index", "parameters", "limitations"), label = "Questionnaire index result")
  brohn_require(identical(result$schema, "brohn-questionnaire-index-result/1.0") && identical(result$status, "complete"), "The complete questionnaire index is unavailable.")
  ref <- result$index
  brohn_fields(ref, c("path", "sha256", "bytes", "schema", "binding", "recipe", "counts", "manifest_hash", "media_type"), label = "Questionnaire index descriptor")
  brohn_require(identical(ref$media_type, "application/vnd.sqlite3") && identical(ref$recipe, .brohn_questionnaire_index_recipe) &&
    identical(brohn_hash(ref$binding), brohn_hash(input$index_input$binding)), "The derived index changed its exact source binding.")
  path <- brohn_checked_artifact_path(store, ref$path, scratch)
  context <- .brohn_publication_stage(store, job, list(list(key = "questionnaire-index", kind = "questionnaire-index", path = path,
    sha256 = ref$sha256, bytes = ref$bytes, media_type = ref$media_type)))
  document <- NULL; committed <- FALSE
  on.exit({if (!is.null(document)) brohn_close_publication(document$guard, committed); brohn_close_publication(context$guard, committed)}, add = TRUE)
  checkpoint <- .brohn_publication_checkpoint(store, job)
  handle <- brohn_questionnaire_index_open(context$paths[["questionnaire-index"]], ref, input$index_input$binding)
  on.exit(brohn_questionnaire_index_close(handle), add = TRUE)
  brohn_require(identical(brohn_hash(handle$manifest$source), brohn_hash(brohn_questionnaire_artifact_source(input$index_input$report))) &&
    identical(brohn_hash(handle$manifest$limits), brohn_hash(result$parameters)), "The index changed its source provenance or resource recipe.")
  manifest <- handle$manifest; brohn_questionnaire_index_close(handle); checkpoint(TRUE)
  index <- c(ref[setdiff(names(ref), c("path", "sha256", "bytes"))], context$descriptors[[1L]][c("hash", "size")])
  id <- paste0("questionnaire-index-", sub("^job_", "", job$id))
  body <- list(schema = .brohn_qexplorer_schema, id = id, recipe = .brohn_questionnaire_index_recipe,
    report_id = job$request$report_id, report_revision = job$request$report_revision, report_hash = job$request$report_hash,
    origin = job$request$binding$origin, binding = job$request$binding, source_support = job$request$source_support,
    request = job$request, request_hash = brohn_hash(job$request), index = index, counts = manifest$counts,
    original_counts = manifest$original_counts, answer_source = manifest$answer_source, search = manifest$search,
    ordering = manifest$ordering, parameters = result$parameters, limitations = result$limitations, created_at = brohn_now(),
    processing = list(job_id = job$id, attempt = job$attempt, worker_output_hash = digest::digest(file = output_path, algo = "sha256"),
      code_hashes = output$code_identity, publication = .brohn_publication_processing(context)))
  document <- .brohn_publication_stage_json(store, job, body, file.path(scratch, "published-questionnaire-index.json"))
  receipt <- brohn_store_batch(store, function() {
    # Immutable revision metadata is sufficient here; full bytes were checked
    # outside SQL and held through this commit. No analysis/large file is read.
    brohn_require(identical(.brohn_qexplorer_catalog(store, "report", body$report_id, body$report_revision, input$project_id), job$request$catalog_hash),
      "The original saved report revision is no longer available for this publication.")
    brohn_project(store, input$project_id)
    for (guard in source_guards) .Call(guard$native$check, guard$pointer)
    .brohn_publication_register(store, context)
    body$result_object <- .brohn_publication_register(store, document)[[1L]][c("hash", "size", "media_type")]
    brohn_put_entity(store, "questionnaire_index", id, body, expected_revision = 0L, project_id = input$project_id)
    brohn_complete_job(store, job$id, job$worker, job$token, list(questionnaire_index_id = id, report_id = body$report_id,
      index_hash = brohn_hash(body), artifact_hash = index$hash, output_hash = body$result_object$hash))
  })
  committed <- TRUE; receipt
}

# Probe only exact local file metadata, then hold the parent native handle before
# hashing/opening SQLite. A path replacement between probe and open is rejected
# by the native volume/file-index check, and no helper lifetime is trusted.
.brohn_qexplorer_hold <- function(path, bytes) {
  if (.Platform$OS.type != "windows") return(NULL)
  code <- paste(c("import ctypes,json,sys", "from ctypes import wintypes as w",
    "class Info(ctypes.Structure):", " _fields_=[('attr',w.DWORD),('creation',w.FILETIME),('access',w.FILETIME),('write',w.FILETIME),('volume',w.DWORD),('sizehi',w.DWORD),('sizelo',w.DWORD),('links',w.DWORD),('indexhi',w.DWORD),('indexlo',w.DWORD)]",
    "k=ctypes.WinDLL('kernel32',use_last_error=True)", "k.CreateFileW.argtypes=[w.LPCWSTR,w.DWORD,w.DWORD,w.LPVOID,w.DWORD,w.DWORD,w.HANDLE];k.CreateFileW.restype=w.HANDLE",
    "k.GetFileInformationByHandle.argtypes=[w.HANDLE,ctypes.POINTER(Info)];k.GetFileInformationByHandle.restype=w.BOOL",
    "k.CloseHandle.argtypes=[w.HANDLE];k.CloseHandle.restype=w.BOOL",
    "p=sys.argv[1];slash=chr(92);prefix=slash*2+'?'+slash;p=p if p.startswith(prefix) else prefix+p.replace('/',slash)",
    "h=k.CreateFileW(p,0x80000000,1,None,3,0x00200000,None)", "assert h not in (None,ctypes.c_void_p(-1).value),ctypes.get_last_error()",
    "try:", " i=Info();assert k.GetFileInformationByHandle(h,ctypes.byref(i)),ctypes.get_last_error()",
    " assert not i.attr&0x410", " print(json.dumps({'volume':str(i.volume),'file_index':str((i.indexhi<<32)|i.indexlo),'bytes':str((i.sizehi<<32)|i.sizelo)}))",
    "finally:k.CloseHandle(h)"), collapse = "\n")
  process <- processx::run(.brohn_publication_python(), c("-B", "-c", code, path), timeout = 10,
    error_on_status = FALSE, cleanup_tree = TRUE, windows_hide_window = TRUE)
  brohn_require(!isTRUE(process$timeout) && identical(process$status, 0L) && nchar(process$stdout, type = "bytes") <= 2048,
    "The local saved-answer file identity probe failed. Reopen the verified view.")
  identity <- brohn_parse(process$stdout, 2048); native <- .brohn_publication_native()
  brohn_require(identical(identity$bytes, sprintf("%.0f", bytes)), "The derived index file size changed before opening.")
  guard <- new.env(parent = emptyenv()); guard$native <- native
  guard$pointer <- .Call(native$open, path, identity$volume, identity$file_index, identity$bytes)
  guard$path <- normalizePath(path, winslash = "/", mustWork = TRUE)
  lockBinding("native", guard); lockBinding("path", guard)
  guard
}
.brohn_qexplorer_release <- function(guard) {
  if (is.environment(guard) && !is.null(guard$pointer)) {
    .Call(guard$native$close, guard$pointer); guard$pointer <- NULL
  }
  invisible(NULL)
}
.brohn_qexplorer_source_guards <- function(store, request) {
  guards <- list(); success <- FALSE
  on.exit(if (!success) for (guard in guards) .brohn_qexplorer_release(guard), add = TRUE)
  for (reference in list(request$result_object, request$artifact)) if (!is.null(reference)) {
    path <- brohn_object_path(store, reference$hash, verify = FALSE)
    size <- if (!is.null(reference$size)) reference$size else reference$bytes
    brohn_require(brohn_number(size, 1, 1024^3, TRUE), "The retained questionnaire source has no exact byte size.")
    guards[[length(guards)+1L]] <- .brohn_qexplorer_hold(path, size)
  }
  success <- TRUE; guards
}
brohn_close_questionnaire_index <- function(opened) {
  if (is.list(opened)) {
    # Cleanup owns the handles opened by this view even if a caller has
    # accidentally mixed its public record/handle fields with another view.
    owner <- if (is.environment(opened$authority) && environmentIsLocked(opened$authority)) opened$authority else opened
    if (!is.null(owner$handle)) brohn_questionnaire_index_close(owner$handle)
    .brohn_qexplorer_release(owner$guard)
  }
  invisible(NULL)
}
brohn_open_questionnaire_index <- function(store, index_id, expected_index_hash, report_id, report_revision, expected_report_hash, project_id) {
  brohn_require(brohn_valid_id(index_id) && .brohn_questionnaire_artifact_hash(expected_index_hash), "Choose the exact saved-answer index.")
  row <- DBI::dbGetQuery(store$con, "SELECT revision,project_id FROM entities WHERE kind='questionnaire_index' AND id=?", params = list(index_id))
  brohn_require(nrow(row) == 1L && identical(row$project_id[[1L]], project_id), "This saved-answer view is unavailable in the selected project.")
  record <- brohn_get_entity(store, "questionnaire_index", index_id); b <- record$body
  brohn_require(identical(b$schema, .brohn_qexplorer_schema) && identical(brohn_hash(b), expected_index_hash) &&
    identical(b$report_id, report_id) && b$report_revision == report_revision && identical(b$report_hash, expected_report_hash),
    "This index belongs to another saved report revision. Reopen that exact report.")
  source <- .brohn_questionnaire_index_source(store, report_id, report_revision, expected_report_hash, project_id)
  brohn_require(identical(brohn_hash(b$binding), brohn_hash(source$binding)) && identical(b$request$catalog_hash, source$catalog_hash) &&
    identical(b$source_support, source$source_support), "The index source authority no longer matches the selected report.")
  job <- .brohn_qexplorer_job(store, b$processing$job_id, project_id)
  brohn_require(identical(job$status, "succeeded") && identical(job$result$questionnaire_index_id, index_id) &&
    identical(job$result$index_hash, expected_index_hash) && identical(brohn_hash(job$request), b$request_hash) &&
    identical(brohn_hash(b$request), b$request_hash) && identical(job$result$artifact_hash, b$index$hash) &&
    identical(job$result$output_hash, b$result_object$hash), "The saved index has no matching completed derived-view receipt.")
  envelope <- brohn_read_json_file(brohn_object_path(store, b$result_object$hash))
  brohn_require(identical(brohn_hash(envelope), brohn_hash(b[setdiff(names(b), "result_object")])), "The derived view differs from its retained publication document.")
  path <- brohn_object_path(store, b$index$hash, verify = FALSE)
  opened <- list(record = record, handle = NULL, guard = NULL, context = list(workspace_id = store$workspace_id, root = store$root,
    project_id = project_id, report_id = report_id, report_revision = report_revision, report_hash = expected_report_hash,
    report_catalog_hash = source$catalog_hash, index_id = index_id, index_revision = record$revision, index_hash = expected_index_hash,
    index_catalog_hash = .brohn_qexplorer_catalog(store, "questionnaire_index", index_id, record$revision, project_id)))
  success <- FALSE; on.exit(if (!success) brohn_close_questionnaire_index(opened), add = TRUE)
  opened$guard <- .brohn_qexplorer_hold(path, b$index$size)
  opened$handle <- brohn_questionnaire_index_open(path, b$index, b$binding)
  authority <- new.env(parent = emptyenv())
  authority$context_hash <- brohn_hash(opened$context); authority$record_hash <- brohn_hash(record)
  authority$handle <- opened$handle; authority$guard <- opened$guard
  lockEnvironment(authority, bindings = TRUE); opened$authority <- authority
  success <- TRUE; opened
}
brohn_check_questionnaire_index_context <- function(store, opened, report_id, report_revision, expected_report_hash, project_id) {
  a <- opened$authority
  brohn_require(is.environment(a) && environmentIsLocked(a) && identical(a$handle, opened$handle) && identical(a$guard, opened$guard) &&
    identical(a$context_hash, brohn_hash(opened$context)) && identical(a$record_hash, brohn_hash(opened$record)),
    "The opened answer view no longer matches its verified source and handle. Reopen it.")
  c <- opened$context
  brohn_require(is.list(c) && identical(c$workspace_id, store$workspace_id) && identical(c$root, store$root) &&
    identical(c$project_id, project_id) && identical(c$report_id, report_id) && identical(as.numeric(c$report_revision), as.numeric(report_revision)) &&
    identical(c$report_hash, expected_report_hash), "Reopen this saved-answer view in its original report and project.")
  brohn_project(store, project_id)
  brohn_require(identical(.brohn_qexplorer_catalog(store, "report", report_id, report_revision, project_id), c$report_catalog_hash) &&
    identical(.brohn_qexplorer_catalog(store, "questionnaire_index", c$index_id, c$index_revision, project_id), c$index_catalog_hash),
    "The selected saved-answer source is unavailable or changed.")
  if (.Platform$OS.type == "windows") {
    brohn_require(is.environment(opened$guard) && !is.null(opened$guard$pointer) && identical(opened$guard$path, opened$handle$path), "Reopen the closed immutable answer view.")
    .Call(opened$guard$native$check, opened$guard$pointer)
  } else brohn_require(identical(digest::digest(file = opened$handle$path, algo = "sha256"), opened$handle$hash),
    "The immutable index changed. This platform re-verifies bytes for each action.")
  .brohn_qindex_live(opened$handle); invisible(TRUE)
}
