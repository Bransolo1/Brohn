# Storage contract integration tests: actual SQLite files, two open connections,
# restart, immutable bytes and deterministic lease time. No participant data.
# Use the exact inherited library selected by the configured QA runner.
source("R/platform-store.R")
local({
  directory <- tempfile("brohn-platform-store-")
  dir.create(directory)
  cleanup_root <- normalizePath(directory, winslash = "/", mustWork = TRUE)
  store <- NULL
  second <- NULL
  original_clock <- .brohn_store_now
  on.exit({
    assign(".brohn_store_now", original_clock, envir = .GlobalEnv)
    brohn_close_store(second)
    brohn_close_store(store)
    if (dir.exists(directory)) {
      stopifnot(identical(normalizePath(directory, winslash = "/", mustWork = TRUE), cleanup_root),
        startsWith(cleanup_root, paste0(normalizePath(tempdir(), winslash = "/"), "/")))
      Sys.chmod(list.files(directory, recursive = TRUE, full.names = TRUE, all.files = TRUE), "0666")
      unlink(directory, recursive = TRUE)
    }
  }, add = TRUE)
  checks <- character()
  check <- function(name, value) {
    if (!isTRUE(value)) stop("FAIL: ", name)
    checks <<- c(checks, name)
  }
  rejects <- function(expr, code = NULL) {
    outcome <- tryCatch({ force(expr); NULL }, error = function(e) e)
    inherits(outcome, if (is.null(code)) "error" else paste0("brohn_store_", code))
  }
  store <- brohn_open_store(directory)
  identity <- store$workspace_id
  second <- brohn_open_store(directory)
  check("workspace identity stable across connections", identical(second$workspace_id, identity))
  check("WAL and foreign keys enabled", DBI::dbGetQuery(store$con, "PRAGMA journal_mode")[[1]] == "wal" &&
    DBI::dbGetQuery(store$con, "PRAGMA foreign_keys")[[1]] == 1L)
  check("FULL durability and busy timeout enabled", DBI::dbGetQuery(store$con, "PRAGMA synchronous")[[1]] == 2L &&
    DBI::dbGetQuery(store$con, "PRAGMA busy_timeout")[[1]] == 5000L)
  check("catalog schemas cannot load native extensions", DBI::dbGetQuery(store$con, "PRAGMA trusted_schema")[[1]] == 0L &&
    rejects(DBI::dbGetQuery(store$con, "SELECT load_extension('not-a-library')")))
  check("missing entities and jobs are explicit NULL", is.null(brohn_get_entity(store, "study", "missing")) &&
    is.null(brohn_get_job(store, "missing")))
  body <- list(title = "Control and candidate", nested = list(list(tick = "9007199254740993",
    missing = NULL, zero = 0, no = FALSE, selected = list("only"))), empty = list(),
    object = structure(list(), names = character()), unicode = "caf\u00e9 \u03bcV")
  first <- brohn_put_entity(store, "study", "one", body, operation_id = "save-one")
  check("first revision begins at one", identical(first$revision, 1L))
  check("nested null, zero, false and tick text survive", is.null(first$body$nested[[1]]$missing) &&
    "missing" %in% names(first$body$nested[[1]]) && identical(first$body$nested[[1]]$no, FALSE) &&
    first$body$nested[[1]]$zero == 0 && identical(first$body$nested[[1]]$tick, "9007199254740993"))
  check("one item and empty arrays remain arrays", is.list(first$body$nested) && length(first$body$nested) == 1L &&
    is.list(first$body$nested[[1]]$selected) && is.null(names(first$body$empty)))
  wire <- DBI::dbGetQuery(store$con, "SELECT body_json FROM entity_versions WHERE id='one'")$body_json[[1]]
  check("empty object distinct from empty array in persisted JSON", grepl('"object":{}', wire, fixed = TRUE) &&
    grepl('"empty":[]', wire, fixed = TRUE))
  check("Unicode survives canonical serialization", identical(first$body$unicode, body$unicode))
  body_reordered <- body[rev(names(body))]
  check("identical idempotent request returns original revision", identical(
    brohn_put_entity(second, "study", "one", body_reordered, operation_id = "save-one"), first))
  check("changed idempotent payload rejected", rejects(brohn_put_entity(store, "study", "one",
    list(title = "Different"), operation_id = "save-one"), "idempotency_conflict"))
  check("cross-record idempotency collision rejected", rejects(brohn_put_entity(store, "study", "two", body,
    operation_id = "save-one"), "idempotency_conflict"))
  check("stale revision from another connection rejected", rejects(brohn_put_entity(second, "study", "one",
    body, expected_revision = 0L), "revision_conflict"))
  revised <- body
  revised$title <- "Revised title"
  next_record <- brohn_put_entity(second, "study", "one", revised, expected_revision = 1L,
    operation_id = "save-two", project_id = "consumer")
  check("second connection update has revision two", identical(next_record$revision, 2L) &&
    identical(brohn_get_entity(store, "study", "one")$body$title, "Revised title"))
  check("original history survives update", identical(brohn_get_entity(store, "study", "one", 1L), first))
  check("history ordered newest first", identical(vapply(brohn_entity_history(store, "study", "one"),
    `[[`, integer(1), "revision"), c(2L, 1L)))
  check("historic operation replay returns its exact revision", identical(
    brohn_put_entity(store, "study", "one", body, operation_id = "save-one"), first))
  check("project-filtered catalog uses current ownership", length(brohn_list_entities(store, "study", "default")) == 0L &&
    length(brohn_list_entities(store, "study", "consumer")) == 1L)
  literal <- "quote'; DROP TABLE entities; --"
  brohn_put_entity(store, "study", literal, list(title = literal))
  check("SQL values are parameterized", identical(brohn_get_entity(store, "study", literal)$body$title, literal) &&
    length(brohn_list_entities(store, "study")) == 2L)
  check("immutable revisions reject direct updates", rejects(DBI::dbExecute(store$con,
    "UPDATE entity_versions SET body_json='{}' WHERE id='one'")))
  check("immutable revisions reject direct deletion", rejects(DBI::dbExecute(store$con,
    "DELETE FROM entity_versions WHERE id='one'")))
  check("foreign key rejects orphan revision", rejects(DBI::dbExecute(store$con,
    paste("INSERT INTO entity_versions (kind,id,revision,project_id,body_json,body_hash,created_at,updated_at)",
      "VALUES ('study','absent',1,'default','{}','x','now','now')"))))
  check("NA, infinity and duplicate keys rejected", rejects(brohn_put_entity(store, "study", "invalid", list(x = NA))) &&
    rejects(brohn_put_entity(store, "study", "invalid", list(x = Inf))) &&
    rejects(brohn_put_entity(store, "study", "invalid", structure(list(1, 2), names = c("x", "x")))))
  check("non-JSON classes rejected", rejects(brohn_put_entity(store, "study", "invalid", list(date = Sys.Date()))))
  check("payload and list bounds enforced", rejects(.brohn_store_json(list(x = strrep("x", 50)), maximum = 20), "too_large") &&
    rejects(brohn_list_entities(store, "study", limit = 0)))
  vector_record <- brohn_put_entity(store, "fixture", "vectors", list(vector = c("a", "b"), scalar_array = I("only")))
  check("ordinary vectors and forced scalar arrays preserved", identical(vector_record$body$vector, list("a", "b")) &&
    identical(vector_record$body$scalar_array, list("only")))
  # A genuine mid-transaction failure must undo the mutable head and the history.
  DBI::dbExecute(store$con, paste("CREATE TRIGGER test_fail_audit BEFORE INSERT ON audit_log",
    "WHEN NEW.target='study/rollback' BEGIN SELECT RAISE(ABORT,'injected audit failure'); END"))
  check("injected transaction failure surfaces", rejects(brohn_put_entity(store, "study", "rollback", list(title = "x"))))
  DBI::dbExecute(store$con, "DROP TRIGGER test_fail_audit")
  check("failed transaction leaves no head or revision", is.null(brohn_get_entity(store, "study", "rollback")) &&
    length(brohn_entity_history(store, "study", "rollback")) == 0L)
  brohn_put_entity(store, "fixture", "process-cas", list(writer = "parent"))
  rscript <- file.path(R.home("bin"), "Rscript.exe")
  if (!file.exists(rscript)) rscript <- file.path(R.home("bin"), "Rscript")
  child_script <- file.path(directory, "cross-process.R")
  as_code <- function(value) paste(deparse(value), collapse = "")
  writeLines(c(paste0(".libPaths(", as_code(.libPaths()), ")"),
    paste0("source(", as_code(normalizePath("R/platform-store.R", winslash = "/")), ")"),
    paste0("store <- brohn_open_store(", as_code(store$root), ")"),
    "brohn_put_entity(store, 'fixture', 'process-cas', list(writer = 'child'), expected_revision = 1L)",
    "brohn_close_store(store)"), child_script)
  child <- processx::run(rscript, c("--vanilla", child_script), error_on_status = FALSE, timeout = 15000,
    windows_hide_window = TRUE)
  check("separate process commits revision visible to parent", child$status == 0L &&
    identical(brohn_get_entity(store, "fixture", "process-cas")$body$writer, "child"))
  check("cross-process stale revision rejected", rejects(brohn_put_entity(store, "fixture", "process-cas",
    list(writer = "stale-parent"), expected_revision = 1L), "revision_conflict"))

  content <- charToRaw("synthetic source bytes\n9007199254740993")
  object <- brohn_store_object(store, bytes = content, media_type = "text/plain")
  object_path <- brohn_object_path(store, object$hash)
  check("content address matches independent digest", identical(object$hash,
    digest::digest(content, algo = "sha256", serialize = FALSE)) && object$size == length(content))
  check("object is readable with verified bytes", identical(readBin(object_path, "raw", n = length(content)), content))
  check("object deduplicates across connections", identical(brohn_store_object(second, bytes = content,
    media_type = "text/plain"), object))
  check("source file object upload deduplicates", identical(brohn_store_object(second, path = object_path,
    media_type = "text/plain"), object))
  batched <- brohn_store_batch(store, function() {
    item <- brohn_store_object(store, bytes = charToRaw("successful batch"))
    brohn_put_entity(store, "fixture", "batch-success", list(object = item$hash))
  })
  check("batch commits nested object and entity writes", batched$revision == 1L &&
    file.exists(brohn_object_path(store, batched$body$object)))
  orphan_batch <- digest::digest(charToRaw("rolled back batch"), algo = "sha256", serialize = FALSE)
  check("outer batch failure rolls back nested writes", rejects(brohn_store_batch(store, function() {
    item <- brohn_store_object(store, bytes = charToRaw("rolled back batch"))
    brohn_put_entity(store, "fixture", "batch-rollback", list(object = item$hash))
    stop("injected outer failure")
  })) && is.null(brohn_get_entity(store, "fixture", "batch-rollback")) &&
    rejects(brohn_object_path(store, orphan_batch), "not_found"))
  check("batch orphan bytes can safely reconcile", identical(brohn_store_object(store,
    bytes = charToRaw("rolled back batch"))$hash, orphan_batch))
  check("traversal hash rejected", rejects(brohn_object_path(store, "../catalog.sqlite"), "path"))
  check("unregistered hash cannot be read", rejects(brohn_object_path(store, strrep("0", 64)), "not_found"))
  check("object metadata immutable", rejects(DBI::dbExecute(store$con, "UPDATE objects SET media_type='changed'")))
  # A same-size external corruption must fail by hash, not only byte count.
  damaged <- brohn_store_object(store, bytes = charToRaw("original"))
  damaged_path <- brohn_object_path(store, damaged$hash)
  Sys.chmod(damaged_path, "0666")
  writeBin(charToRaw("tampered"), damaged_path)
  check("same-size object corruption detected", rejects(brohn_object_path(store, damaged$hash), "corrupt"))
  check("upload never overwrites corrupt registered object", rejects(brohn_store_object(store,
    bytes = charToRaw("original")), "corrupt") && identical(readBin(damaged_path, "raw", n = 8L), charToRaw("tampered")))
  # Reconcile a valid orphan left between filesystem publish and catalog commit.
  orphan_bytes <- charToRaw("interrupted publish")
  orphan_hash <- digest::digest(orphan_bytes, algo = "sha256", serialize = FALSE)
  orphan_path <- file.path(directory, "objects", "sha256", substr(orphan_hash, 1, 2), orphan_hash)
  dir.create(dirname(orphan_path), showWarnings = FALSE)
  writeBin(orphan_bytes, orphan_path)
  check("valid interrupted-publish orphan reconciles", identical(brohn_store_object(store,
    bytes = orphan_bytes)$hash, orphan_hash) && file.exists(brohn_object_path(store, orphan_hash)))

  test_clock <- 1000
  assign(".brohn_store_now", function() test_clock, envir = .GlobalEnv)
  job <- brohn_enqueue_job(store, "analyze", list(source = object$hash, tick = "9007199254740993"), "analysis-one")
  check("job starts queued and unclaimed", identical(job$status, "queued") && identical(job$attempt, 0L) && is.null(job$token))
  check("job enqueue is canonically idempotent", identical(brohn_enqueue_job(second, "analyze",
    list(tick = "9007199254740993", source = object$hash), "analysis-one"), job))
  check("job payload or operation reuse rejected", rejects(brohn_enqueue_job(store, "analyze", list(x = 1),
    "analysis-one"), "idempotency_conflict") && rejects(brohn_enqueue_job(store, "different", job$request,
    "analysis-one"), "idempotency_conflict"))
  attempt <- brohn_claim_job(second, "worker-a", lease_seconds = 10)
  check("job receives first attempt and lease", identical(attempt$id, job$id) && identical(attempt$attempt, 1L) &&
    identical(attempt$token, "1") && attempt$lease_until == 1010)
  check("another worker cannot claim active lease", is.null(brohn_claim_job(store, "worker-b")))
  check("wrong worker cannot publish", rejects(brohn_complete_job(store, job$id, "worker-b", attempt$token,
    list(value = 99)), "stale_attempt"))
  check("wrong token cannot publish", rejects(brohn_complete_job(store, job$id, "worker-a", "0",
    list(value = 99)), "stale_attempt"))
  check("foreign worker cannot renew lease", rejects(brohn_renew_job(store, job$id, "worker-b",
    attempt$token), "stale_attempt"))
  renewed <- brohn_renew_job(store, job$id, "worker-a", attempt$token, lease_seconds = 5)
  check("legitimate renewal does not shorten an existing lease", renewed$lease_until == 1010 && identical(renewed$token, attempt$token))
  test_clock <- 1010
  check("expired worker cannot publish even before reclaim", rejects(brohn_complete_job(store, job$id,
    "worker-a", attempt$token, list(value = 99)), "stale_attempt"))
  check("expired worker cannot resurrect lease", rejects(brohn_renew_job(store, job$id, "worker-a",
    attempt$token), "stale_attempt"))
  reclaimed <- brohn_claim_job(store, "worker-b", lease_seconds = 10)
  check("expired job reclaimed with higher fencing token", identical(reclaimed$attempt, 2L) &&
    identical(reclaimed$token, "2") && identical(reclaimed$id, job$id))
  check("old attempt cannot fail new lease", rejects(brohn_fail_job(second, job$id, "worker-a",
    attempt$token, list(message = "late error")), "stale_attempt"))
  check("superseded attempt cannot renew newer lease", rejects(brohn_renew_job(second, job$id, "worker-a",
    attempt$token), "stale_attempt"))
  extended <- brohn_renew_job(store, job$id, "worker-b", reclaimed$token, lease_seconds = 60)
  check("active worker extends its own fenced lease", extended$lease_until == 1070 && identical(extended$token, reclaimed$token))
  completed <- brohn_complete_job(store, job$id, "worker-b", reclaimed$token, list(value = 0, missing = NULL))
  check("valid completion atomically publishes result", identical(completed$status, "succeeded") &&
    completed$result$value == 0 && "missing" %in% names(completed$result) && is.null(completed$lease_until))
  check("completed result cannot be overwritten", rejects(brohn_complete_job(store, job$id, "worker-b",
    reclaimed$token, list(value = 99)), "stale_attempt"))
  check("finished job cannot be cancelled", rejects(brohn_cancel_job(store, job$id), "state"))
  check("enqueue replay returns completed result", identical(brohn_enqueue_job(store, "analyze", job$request,
    "analysis-one"), completed))
  cancellation <- brohn_enqueue_job(store, "analyze", list(source = "cancel"), "analysis-cancel")
  claimed_cancel <- brohn_claim_job(store, "worker-c")
  cancelled <- brohn_cancel_job(second, cancellation$id)
  check("cancelled active lease rejects later output", identical(cancelled$status, "cancelled") &&
    rejects(brohn_complete_job(store, cancellation$id, "worker-c", claimed_cancel$token,
      list(value = 10)), "stale_attempt"))
  check("cancel is idempotent and cancelled jobs cannot reclaim", identical(brohn_cancel_job(store,
    cancellation$id), cancelled) && is.null(brohn_claim_job(store, "worker-d")))
  pending_cancel <- brohn_enqueue_job(store, "analyze", list(source = "queued"), "queued-cancel")
  check("queued job cancellation supported", brohn_cancel_job(store, pending_cancel$id)$status == "cancelled")
  failure <- brohn_enqueue_job(store, "analyze", list(source = "fail"), "analysis-fail")
  failed_attempt <- brohn_claim_job(store, "worker-e")
  failed <- brohn_fail_job(store, failure$id, "worker-e", failed_attempt$token,
    list(code = "input_quality", message = "No valid observation interval."))
  check("valid worker failure is durable and not a result", identical(failed$status, "failed") &&
    identical(failed$error$code, "input_quality") && is.null(failed$result))
  check("job listing retains all terminal states", length(brohn_list_jobs(store)) == 4L)
  check("audit is immutable and records major transitions", rejects(DBI::dbExecute(store$con, "DELETE FROM audit_log")) &&
    all(c("workspace.created", "entity.saved", "object.stored", "job.queued", "job.claimed", "job.cancelled",
      "job.succeeded", "job.failed") %in% DBI::dbGetQuery(store$con, "SELECT DISTINCT action FROM audit_log")$action))

  brohn_close_store(second)
  brohn_close_store(store)
  check("closed store rejects reads", rejects(brohn_get_entity(store, "study", "one"), "closed"))
  store <- brohn_open_store(directory)
  check("restart retains workspace identity and full history", identical(store$workspace_id, identity) &&
    length(brohn_entity_history(store, "study", "one")) == 2L &&
    identical(brohn_get_entity(store, "study", "one", 1L), first))
  check("restart retains completed and failed job outputs", identical(brohn_get_job(store, job$id), completed) &&
    identical(brohn_get_job(store, failure$id), failed))
  check("restart retains verified object address", identical(brohn_object_path(store, object$hash), object_path))
  check("database integrity and foreign key checks pass", identical(DBI::dbGetQuery(store$con,
    "PRAGMA integrity_check")[[1]], "ok") && nrow(DBI::dbGetQuery(store$con, "PRAGMA foreign_key_check")) == 0L)
  cat(sprintf("PASS: %d durable platform storage checks (catalog, immutable objects, fenced jobs, restart)\n", length(checks)))
})
