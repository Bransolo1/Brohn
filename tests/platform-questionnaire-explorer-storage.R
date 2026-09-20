# Original synthetic saved reports; actual Windows publication/SQLite adapters.
# This suite does not claim participant, scientific-worker or browser acceptance.
source("R/platform-load.R", encoding = "UTF-8"); brohn_load(ui = FALSE)
source("R/platform-questionnaire-index.R", encoding = "UTF-8")
source("R/platform-questionnaire-explorer.R", encoding = "UTF-8")
local({
  checks <- 0L; opened <- list()
  folder <- tempfile("irp-questionnaire-explorer-storage-"); dir.create(folder)
  store <- brohn_open_store(file.path(folder, "workspace")); brohn_initialise_library(store)
  on.exit({for (x in opened) try(brohn_close_questionnaire_index(x), silent = TRUE); brohn_close_store(store)}, add = TRUE)
  check <- function(label, result) {if (!isTRUE(result)) stop("FAIL: ", label); checks <<- checks+1L; cat("PASS", label, "\n"); flush.console()}
  reject <- function(label, expression, pattern = NULL) {
    error <- tryCatch({force(expression); NULL}, error = conditionMessage)
    if (is.null(error) || (!is.null(pattern) && !grepl(pattern, error, fixed = TRUE))) cat("Unexpected rejection outcome:", error, "\n")
    check(label, !is.null(error) && (is.null(pattern) || grepl(pattern, error, fixed = TRUE)))
  }
  saved <- function(id, packed = FALSE, retained = FALSE, project = "default") {
    design <- brohn_new_design("Original explorer storage fixture", id = paste0(id, "-study"), project_id = project)
    observations <- lapply(seq_len(65L), function(i) list(question_id = paste0("q-", i), prompt = paste("Original question", i),
      participant_id = paste0("alias-P", i %% 3L), session_id = paste0("session-", i), value = if (i == 65L) "Original complete last answer \u6f22 <script>" else i,
      status = "answered", stimulus_id = "repeated-label", condition_id = "condition-original"))
    full <- list(schema_version = "brohn-report/1.0.0", id = id, title = "Original saved source", study_id = design$id, dataset_id = NULL,
      origin = "sample", status = "Available", created_at = brohn_now(), provenance = list(design = design, design_hash = brohn_hash(design)),
      analysis = list(kind = "questionnaire", title = "Original synthetic answers", features = lapply(seq_len(12L), function(i)
        list(question_id = paste0("q-", i), prompt = paste("Original summary", i), response_count = 65, answered_count = 65, missing_count = 0)),
        observations = observations, quality = list(response_count = 65, usable = TRUE), limitations = list("Original synthetic storage fixture only.")))
    body <- full
    if (packed) {
      scratch <- file.path(store$root, "scratch", paste0(id, "-source")); dir.create(scratch, recursive = TRUE)
      body <- brohn_pack_questionnaire_report(body, scratch, threshold = 1024)
      verified <- .brohn_check_worker_artifacts(store, body$analysis, scratch)
      body$analysis <- .brohn_worker_artifact_analysis(body$analysis, lapply(verified, function(item)
        c(list(kind = item$kind), brohn_store_object(store, path = item$path, media_type = "application/x-ndjson"), item$metadata)))
    }
    if (retained) body$result_object <- brohn_store_object(store, bytes = charToRaw(enc2utf8(brohn_json(
      list(schema = "brohn-analysis-output/1.0", report = body)))), media_type = "application/json")
    record <- brohn_put_entity(store, "report", id, body, project_id = project)
    list(record = record, full = full, hash = brohn_hash(record$body), project = project)
  }
  queue <- function(f, rebuild = FALSE) brohn_queue_questionnaire_index(store, f$record$id, f$record$revision, f$hash, f$project, rebuild)
  prepare <- function(f, rebuild = TRUE) {
    q <- queue(f, rebuild); j <- brohn_claim_job(store, "original-storage-fixture", 300)
    stopifnot(identical(j$id, q$id)); input <- brohn_questionnaire_index_input(store, j)
    scratch <- file.path(store$root, "scratch", paste0(j$id, "-attempt-", j$attempt)); dir.create(scratch, recursive = TRUE)
    report <- brohn_analyse_questionnaire_index(input, scratch)
    paths <- c("R/platform-publication.R", names(.brohn_qexplorer_loaded), "scripts/workers/publication.py", "src/publication_guard.c")
    identity <- stats::setNames(lapply(paths, function(path) digest::digest(file = path, algo = "sha256")), paths)
    output <- list(schema = "brohn-analysis-output/1.0", code_identity = identity, report = report)
    path <- file.path(scratch, "output.json"); brohn_write_json_file(output, path)
    list(job = j, input = input, scratch = scratch, output = output, path = path)
  }
  publish <- function(p) brohn_publish_questionnaire_index(store, p$output, p$scratch, p$job, p$input, p$path)
  open_view <- function(f, receipt) {
    value <- brohn_open_questionnaire_index(store, receipt$result$questionnaire_index_id, receipt$result$index_hash,
      f$record$id, f$record$revision, f$hash, f$project)
    opened[[length(opened)+1L]] <<- value; value
  }
  valid <- function(f, value) brohn_check_questionnaire_index_context(store, value, f$record$id, f$record$revision, f$hash, f$project)
  count <- function(kind) DBI::dbGetQuery(store$con, "SELECT count(*) AS n FROM entities WHERE kind=?", params = list(kind))$n[[1L]]
  mutate_sql <- function(sql, params, expression, undo, undo_params = params) {
    DBI::dbExecute(store$con, sql, params = params)
    on.exit(DBI::dbExecute(store$con, undo, params = undo_params), add = TRUE)
    force(expression)
  }
  inline <- saved("original-inline"); artifact <- saved("original-artifact", TRUE, TRUE)
  request <- brohn_prepare_questionnaire_index(store, inline$record$id, 1L, inline$hash, "default")
  check("historical inline sources retain explicit non-worker support", request$source_support == "catalog_revision_without_retained_worker_envelope")
  check("artifact sources bind retained result and original artifact", brohn_prepare_questionnaire_index(store, artifact$record$id, 1L, artifact$hash, "default")$source_support == "catalog_revision_with_verified_retained_result")
  reject("foreign project rejects before source return", brohn_prepare_questionnaire_index(store, inline$record$id, 1L, inline$hash, "foreign"), "selected project")
  reject("wrong report hash rejects", brohn_prepare_questionnaire_index(store, inline$record$id, 1L, brohn_hash("foreign"), "default"), "changed")
  q <- queue(inline); check("repeated request reuses exact latest queued job", identical(queue(inline)$id, q$id))
  reject("another build is refused while the workspace slot is occupied", queue(artifact), "Another saved-answer")
  reject("foreign project cannot cancel another job", brohn_cancel_questionnaire_index(store, q$id, "foreign"))
  brohn_cancel_questionnaire_index(store, q$id, "default")
  check("cancelled exact request remains visible until retry or rebuild", identical(queue(inline)$id, q$id) && queue(inline)$status == "cancelled")
  retry <- brohn_retry_questionnaire_index(store, q$id, "default")
  check("retry has new job identity and identical frozen request", retry$id != q$id && identical(brohn_hash(retry$request), brohn_hash(q$request)))
  check("repeated old retry reuses latest replacement", identical(brohn_retry_questionnaire_index(store, q$id, "default")$id, retry$id))
  brohn_cancel_questionnaire_index(store, retry$id, "default")
  rebuild <- queue(inline, TRUE)
  check("explicit rebuild supersedes earlier retries for future reuse", rebuild$id != retry$id && identical(queue(inline)$id, rebuild$id))
  brohn_cancel_questionnaire_index(store, rebuild$id, "default")
  p <- prepare(inline)
  changed_job <- p$job; changed_job$request$catalog_hash <- brohn_hash("another-catalog-revision")
  reject("input resolver refuses a stale original catalog hash", brohn_questionnaire_index_input(store, changed_job))
  changed_job <- p$job; changed_job$request$source_support <- "catalog_revision_with_verified_retained_result"
  reject("input resolver cannot promote historical support", brohn_questionnaire_index_input(store, changed_job))
  changed_job <- p$job; changed_job$request$provenance_hash <- brohn_hash("another-frozen-design")
  reject("input resolver refuses substituted provenance identity", brohn_questionnaire_index_input(store, changed_job))
  changed_job <- p$job; changed_job$request$implementation[[1L]] <- brohn_hash("different-code")
  reject("input resolver refuses changed index implementation identity", brohn_questionnaire_index_input(store, changed_job))
  altered <- p$input; altered$index_input$binding$origin <- "live"
  reject("publisher rejects substituted pinned input", brohn_publish_questionnaire_index(store, p$output, p$scratch, p$job, altered, p$path), "substituted")
  altered <- p$output; altered$report$questionnaire_index$index$binding$origin <- "live"
  reject("publisher rejects output differing from retained worker file", brohn_publish_questionnaire_index(store, altered, p$scratch, p$job, p$input, p$path), "substituted")
  receipt <- publish(p); first <- open_view(inline, receipt)
  check("actual native publication creates derived entity and completes one job", receipt$status == "succeeded" && count("questionnaire_index") == 1L && count("report") == 2L)
  check("published view retains all 65 answers and 12 saved summaries", first$record$body$counts$answers == 65L && first$record$body$counts$questions == 12L)
  check("opened view passes exact context and native identity probe", isTRUE(valid(inline, first)))
  page <- brohn_questionnaire_index_page(first$handle, "answers", list(question_id = "q-65"))
  check("stored index reads beyond preview without recalculation", page$matching_total == 1L && page$rows[[1L]]$question_id == "q-65" && page$source_total == 65L)
  check("completed matching request reuses published result", identical(queue(inline)$result$index_hash, receipt$result$index_hash))
  reject("foreign report cannot open a saved view", brohn_open_questionnaire_index(store, receipt$result$questionnaire_index_id, receipt$result$index_hash,
    artifact$record$id, 1L, artifact$hash, "default"))
  reject("foreign project cannot open a saved view", brohn_open_questionnaire_index(store, receipt$result$questionnaire_index_id, receipt$result$index_hash,
    inline$record$id, 1L, inline$hash, "foreign"))
  changed <- first; changed$record$body$origin <- "live"
  reject("changed opened record rejected before query", valid(inline, changed))
  changed <- first; changed$context$index_id <- "another-index"
  reject("changed context rejected before query", valid(inline, changed))
  changed <- first; changed$guard <- new.env(parent = emptyenv())
  reject("substituted native guard rejected", valid(inline, changed))
  changed <- first; changed$authority <- NULL
  reject("missing opened authority rejected", valid(inline, changed))
  receipt2 <- publish(prepare(artifact)); second <- open_view(artifact, receipt2)
  check("artifact source publishes complete second derived view", second$record$body$counts$answers == 65L && isTRUE(valid(artifact, second)))
  changed <- first; changed$handle <- second$handle
  reject("foreign open handle cannot be combined with original context", valid(inline, changed))
  changed <- first; changed$record <- second$record
  reject("foreign record cannot be combined with original handle", valid(inline, changed))
  reject("one view cannot authorize actions on another report", valid(artifact, first))
  job_row <- DBI::dbGetQuery(store$con, "SELECT result_json FROM jobs WHERE id=?", params = list(receipt$id))$result_json[[1L]]
  altered_receipt <- receipt$result; altered_receipt$artifact_hash <- brohn_hash("foreign-index")
  mutate_sql("UPDATE jobs SET result_json=? WHERE id=?", list(.brohn_store_json(altered_receipt), receipt$id),
    reject("reopen refuses a mismatched completed artifact receipt", open_view(inline, receipt)),
    "UPDATE jobs SET result_json=? WHERE id=?", list(job_row, receipt$id))
  before <- brohn_hash(brohn_get_entity(store, "report", inline$record$id)$body)
  p <- prepare(inline); brohn_cancel_questionnaire_index(store, p$job$id, "default")
  reject("late cancelled output cannot publish", publish(p), "lease")
  check("cancelled build leaves source and derived catalog unchanged", count("questionnaire_index") == 2L && identical(before, brohn_hash(brohn_get_entity(store, "report", inline$record$id)$body)))
  p <- prepare(inline)
  DBI::dbExecute(store$con, "UPDATE jobs SET lease_until=? WHERE id=?", params = list(as.numeric(Sys.time())-1, p$job$id))
  fresh <- brohn_claim_job(store, "original-new-owner", 300)
  check("reclaimed job changes its fenced attempt", fresh$id == p$job$id && fresh$attempt == p$job$attempt+1L && fresh$token != p$job$token)
  reject("stale attempt cannot publish", publish(p), "lease")
  brohn_cancel_questionnaire_index(store, fresh$id, "default")
  p <- prepare(inline); object_count <- DBI::dbGetQuery(store$con, "SELECT count(*) AS n FROM objects")$n[[1L]]
  DBI::dbExecute(store$con, "CREATE TEMP TRIGGER explorer_rollback BEFORE INSERT ON entity_versions WHEN NEW.kind='questionnaire_index' BEGIN SELECT RAISE(ABORT,'original controlled explorer rollback'); END")
  reject("SQL failure rolls back staged index publication", publish(p), "controlled explorer rollback")
  DBI::dbExecute(store$con, "DROP TRIGGER explorer_rollback")
  check("rollback leaves no partial entity or object catalog and job uncompleted", count("questionnaire_index") == 2L &&
    DBI::dbGetQuery(store$con, "SELECT count(*) AS n FROM objects")$n[[1L]] == object_count && brohn_get_job(store, p$job$id)$status == "running")
  brohn_cancel_questionnaire_index(store, p$job$id, "default")
  check("failed publication releases all helper/native publication lifetimes", length(ls(.brohn_publication_handles)) == 0L)
  # Metadata corruption is restored immediately so independent failures cannot
  # become the reason a later assertion happens to reject.
  raw <- DBI::dbGetQuery(store$con, "SELECT body_hash FROM entity_versions WHERE kind='report' AND id=? AND revision=1", params = list(inline$record$id))$body_hash[[1L]]
  reject("normal SQL cannot mutate immutable report revisions", DBI::dbExecute(store$con,
    "UPDATE entity_versions SET body_hash=? WHERE kind='report' AND id=? AND revision=1", params = list(brohn_hash("tampered"), inline$record$id)), "immutable")
  # Deliberately bypass only this fixture database's SQL immutability trigger
  # to prove the opener independently detects corrupted catalog identities.
  immutable_trigger <- DBI::dbGetQuery(store$con, "SELECT sql FROM sqlite_master WHERE type='trigger' AND name='versions_no_update'")$sql[[1L]]
  DBI::dbExecute(store$con, "DROP TRIGGER versions_no_update")
  tryCatch(mutate_sql("UPDATE entity_versions SET body_hash=? WHERE kind='report' AND id=? AND revision=1", list(brohn_hash("tampered"), inline$record$id), {
      reject("catalog-hash tampering blocks existing opened context", valid(inline, first))
      reject("catalog-hash tampering blocks new preparation", queue(inline))
    }, "UPDATE entity_versions SET body_hash=? WHERE kind='report' AND id=? AND revision=1", list(raw, inline$record$id)),
    finally = DBI::dbExecute(store$con, immutable_trigger))
  mutate_sql("UPDATE entities SET project_id=? WHERE kind='report' AND id=?", list("foreign", inline$record$id), {
    reject("changed current project authority blocks old revision access", valid(inline, first))
    reject("changed current project authority blocks preparation", queue(inline))
  }, "UPDATE entities SET project_id=? WHERE kind='report' AND id=?", list("default", inline$record$id))
  project <- brohn_get_entity(store, "project", "default"); archived <- project$body; archived$archived <- TRUE
  brohn_put_entity(store, "project", "default", archived, expected_revision = project$revision)
  reject("archived project revokes existing open context", valid(inline, first))
  reject("archived project refuses source preparation", queue(inline))
  brohn_put_entity(store, "project", "default", project$body, expected_revision = project$revision+1L)
  check("restored project and unchanged metadata recover existing view", isTRUE(valid(inline, first)))
  newer <- inline$record$body; newer$title <- "A later retained report revision"
  brohn_put_entity(store, "report", inline$record$id, newer, expected_revision = 1L)
  check("a newer report revision does not silently replace the frozen source", isTRUE(valid(inline, first)) &&
    identical(open_view(inline, receipt)$record$body$report_revision, 1L))
  # Read sharing must deny writes independently of the read-only attribute.
  write_probe <- function(path) processx::run(.brohn_publication_python(), c("-B", "-c",
    "import os,stat,sys; p=sys.argv[1];os.chmod(p,stat.S_IREAD|stat.S_IWRITE)\ntry:\n f=open(p,'r+b');f.write(b'X');f.close()\nexcept PermissionError: print('denied');sys.exit(0)\nsys.exit(3)", path),
    timeout = 10, error_on_status = FALSE, cleanup_tree = TRUE, windows_hide_window = TRUE)$status
  check("open native view denies same-size overwrite", write_probe(first$handle$path) == 0L)
  source_request <- brohn_prepare_questionnaire_index(store, artifact$record$id, 1L, artifact$hash, "default")
  holds <- .brohn_qexplorer_source_guards(store, source_request)
  check("retained result and original artifact guards deny mutation", length(holds) == 2L && all(vapply(holds, function(h) write_probe(h$path) == 0L, logical(1))))
  for (h in holds) .brohn_qexplorer_release(h)
  corrupt_source <- function(reference, expression) {
    path <- brohn_object_path(store, reference$hash); bytes <- readBin(path, "raw", file.info(path)$size)
    Sys.chmod(path, "0666"); writeBin(c(bytes, as.raw(10L)), path)
    on.exit(writeBin(bytes, path), add = TRUE); force(expression)
  }
  corrupt_source(artifact$record$body$result_object, reject("reopen refuses corrupt retained worker envelope", open_view(artifact, receipt2)))
  corrupt_source(brohn_questionnaire_report_artifact(artifact$record$body), reject("reopen refuses corrupt original complete artifact", open_view(artifact, receipt2)))
  check("restored exact source bytes reopen correctly", isTRUE(valid(artifact, open_view(artifact, receipt2))))
  for (x in opened) if (identical(x$record$id, first$record$id)) brohn_close_questionnaire_index(x)
  reject("closed view cannot authorize another query", valid(inline, first))
  # No open handles remain for this index while corruption is exercised.
  path <- brohn_object_path(store, first$record$body$index$hash); original <- readBin(path, "raw", file.info(path)$size)
  Sys.chmod(path, "0666"); writeBin(c(original, as.raw(0L)), path)
  reject("reopen refuses corrupt derived index bytes", open_view(inline, receipt))
  writeBin(original, path)
  reopened <- open_view(inline, receipt)
  check("reopening exact immutable view recovers same all-record count", isTRUE(valid(inline, reopened)) && brohn_questionnaire_index_page(reopened$handle, "answers")$source_total == 65L)
  for (x in opened) brohn_close_questionnaire_index(x)
  brohn_close_store(store); store <- brohn_open_store(file.path(folder, "workspace"))
  restarted <- open_view(artifact, receipt2)
  check("store restart reuses same complete saved index and receipt", isTRUE(valid(artifact, restarted)) && identical(queue(artifact)$id, receipt2$id))
  check("exploring never rewrites original report bodies", identical(brohn_hash(brohn_get_entity(store, "report", inline$record$id, 1L)$body), inline$hash) &&
    identical(brohn_hash(brohn_get_entity(store, "report", artifact$record$id, 1L)$body), artifact$hash))
  cat("Questionnaire explorer storage:", checks, "checks passed; two actual native publications; isolated fixture:", folder, "\n")
})
