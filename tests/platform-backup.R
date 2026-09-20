source("R/platform-participant-equipment.R") # Registered optional new-draft policy.
.libPaths(c(normalizePath("../../work/r-library-brohn", winslash = "/", mustWork = FALSE), .libPaths()))
for (module in c("platform-core", "platform-store", "platform-delivery", "platform-backup")) source(paste0("R/", module, ".R"))
local({
  directory <- tempfile("brohn-backup-test-"); dir.create(directory)
  cleanup_root <- normalizePath(directory, winslash = "/")
  source <- brohn_open_store(file.path(directory, "source")); restored <- NULL
  original_copy <- .brohn_backup_copy; original_online <- .brohn_backup_online_copy
  on.exit({
    assign(".brohn_backup_copy", original_copy, envir = .GlobalEnv)
    assign(".brohn_backup_online_copy", original_online, envir = .GlobalEnv)
    brohn_close_store(source); brohn_close_store(restored)
    stopifnot(identical(normalizePath(directory, winslash = "/"), cleanup_root),
      startsWith(cleanup_root, paste0(normalizePath(tempdir(), winslash = "/"), "/")))
    Sys.chmod(list.files(directory, recursive = TRUE, full.names = TRUE, all.files = TRUE), "0666")
    unlink(directory, recursive = TRUE)
  }, add = TRUE)
  checks <- 0L
  check <- function(name, value) { if (!isTRUE(value)) stop("FAIL: ", name); checks <<- checks + 1L }
  rejects <- function(expr) inherits(try(force(expr), silent = TRUE), "try-error")
  design <- brohn_new_design("Backup comparison fixture", id = "study-backup")
  design$stimuli[[1]]$content <- "Control"; design$stimuli[[2]]$content <- "Candidate"
  brohn_put_entity(source, "study", design$id, design)
  design$description <- "Frozen source description"
  brohn_put_entity(source, "study", design$id, design, expected_revision = 1L)
  content <- charToRaw("synthetic raw source\n9007199254740993")
  item <- brohn_store_object(source, bytes = content, media_type = "text/plain")
  release <- brohn_publish(source, design$id, quota = 5)
  session <- .brohn_delivery_start(source, release$token, list(consented = TRUE, client_id = "client-backup",
    operation_id = "start-backup", participant_alias = "P-backup"))
  step <- session$protocol$timeline[[1]]
  event <- list(sequence = 1L, id = "event-backup", type = "step_started", step_id = step$id,
    stimulus_id = NULL, condition_id = NULL, question_id = NULL, phase = step$phase,
    clock = list(id = "browser-monotonic", unit = "ms", value = "123.456789", instance_id = "page-backup"), payload = structure(list(), names = character()))
  .brohn_delivery_receive(source, session$run_id, session$access_token, list(events = list(event), operation_id = "event-backup"))
  finished <- brohn_enqueue_job(source, "fixture", list(value = "9007199254740993"), "finished-fixture")
  first_claim <- brohn_claim_job(source, "worker-finished")
  brohn_complete_job(source, finished$id, "worker-finished", first_claim$token, list(value = 0, missing = NULL))
  running <- brohn_enqueue_job(source, "fixture", list(value = 2), "running-fixture")
  running_claim <- brohn_claim_job(source, "original-worker", lease_seconds = 3600)
  brohn_put_entity(source, "fixture", "concurrent", list(version = "before"))
  source_identity <- source$workspace_id
  # A separate process writes after the read snapshot is pinned and before the
  # SQLite online-copy call. WAL permits its commit; the backup must retain the
  # earlier complete view, not merge its head/history revisions.
  child <- file.path(directory, "concurrent-writer.R")
  code <- function(x) paste(deparse(x), collapse = "")
  writeLines(c(paste0(".libPaths(", code(.libPaths()), ")"),
    paste0("source(", code(normalizePath("R/platform-store.R", winslash = "/")), ")"),
    paste0("store <- brohn_open_store(", code(source$root), ")"),
    "brohn_put_entity(store,'fixture','concurrent',list(version='after'),expected_revision=1L)",
    "brohn_close_store(store)"), child)
  rscript <- file.path(R.home("bin"), "Rscript.exe")
  if (!file.exists(rscript)) rscript <- file.path(R.home("bin"), "Rscript")
  wrote <- FALSE
  assign(".brohn_backup_online_copy", function(from, to) {
    result <- processx::run(rscript, c("--vanilla", child), timeout = 15000,
      error_on_status = FALSE, windows_hide_window = TRUE)
    if (result$status != 0L) stop(result$stderr)
    wrote <<- TRUE
    original_online(from, to)
  }, envir = .GlobalEnv)
  path <- file.path(directory, "research.brohn-backup")
  backup <- brohn_backup_workspace(source, path)
  assign(".brohn_backup_online_copy", original_online, envir = .GlobalEnv)
  check("backup publishes a verified folder", backup$verified && dir.exists(path) && backup$object_count == 1L)
  check("WAL writer can commit while source snapshot is pinned", wrote && brohn_get_entity(source, "fixture", "concurrent")$revision == 2L)
  captured <- .brohn_backup_connect(file.path(path, "catalog.sqlite"))
  old_revision <- DBI::dbGetQuery(captured, "SELECT revision FROM entities WHERE kind='fixture' AND id='concurrent'")$revision[[1]]
  DBI::dbDisconnect(captured)
  check("online backup captures one consistent pre-writer revision", old_revision == 1L)
  verification <- brohn_verify_backup(path)
  check("private backup declares credential and data contents", verification$verified &&
    isTRUE(verification$manifest$privacy$includes_private_credentials) && !verification$manifest$privacy$encrypted)
  check("backup rejects existing destination without changes", rejects(brohn_backup_workspace(source, path)) &&
    identical(brohn_verify_backup(path)$manifest$content_sha256, backup$manifest_hash))
  check("backup refuses source-nested destination", rejects(brohn_backup_workspace(source, file.path(source$root, "backup"))))
  destination <- file.path(directory, "restored")
  restoration <- brohn_restore_workspace(path, destination)
  restored <- brohn_open_store(destination)
  check("restore publishes a verified distinct workspace identity", restoration$verified &&
    !identical(restored$workspace_id, source_identity) && identical(restoration$source_workspace_id, source_identity))
  check("restore preserves immutable study revisions", length(brohn_entity_history(restored, "study", design$id)) == 2L &&
    identical(brohn_get_entity(restored, "study", design$id)$body, brohn_get_entity(source, "study", design$id)$body))
  check("restore preserves exact registered object bytes", identical(readBin(brohn_object_path(restored, item$hash), "raw", n = length(content)), content))
  check("restore preserves frozen run and event evidence", identical(brohn_run(restored, session$run_id)$protocol,
    brohn_run(source, session$run_id)$protocol) && identical(brohn_run_events(restored, session$run_id), brohn_run_events(source, session$run_id)))
  check("restore closes releases while source stays open", brohn_deployment(restored, release$id)$status == "closed" &&
    brohn_deployment(source, release$id)$status == "open")
  check("restored participant credentials rotate", !identical(brohn_deployment(restored, release$id)$token, release$token) &&
    rejects(.brohn_delivery_authorize(restored, session$run_id, session$access_token)))
  check("restore retains final job result exactly", identical(brohn_get_job(restored, finished$id)$result,
    brohn_get_job(source, finished$id)$result))
  check("running jobs are requeued with old lease fenced", brohn_get_job(restored, running$id)$status == "queued" &&
    is.null(brohn_get_job(restored, running$id)$token) && rejects(brohn_complete_job(restored, running$id,
      "original-worker", running_claim$token, list(value = 10))))
  check("restored queue and participant delivery start paused", brohn_workspace_execution_status(restored)$paused &&
    is.null(brohn_claim_job(restored, "restored-worker")) && rejects(brohn_publish(restored, design$id)))
  brohn_resume_workspace(restored)
  resumed_claim <- brohn_claim_job(restored, "restored-worker")
  check("explicit resume enables queued analysis with a new attempt", !brohn_workspace_execution_status(restored)$paused &&
    identical(resumed_claim$id, running$id) && resumed_claim$attempt > running_claim$attempt)
  check("resume never reopens restored releases", brohn_deployment(restored, release$id)$status == "closed")
  check("restore refuses existing destination", rejects(brohn_restore_workspace(path, destination)))
  check("restore source artifact remains unchanged", identical(brohn_verify_backup(path)$manifest$content_sha256, backup$manifest_hash))
  # Copy a backup into independent test artifacts for integrity/security cases.
  copy_artifact <- function(name) {
    out <- file.path(directory, name); dir.create(out)
    for (file in .brohn_backup_walk(path)) original_copy(file, file.path(out,
      substring(file, nchar(.brohn_backup_prefix(path)) + 1L)))
    out
  }
  corrupt <- copy_artifact("corrupt")
  corrupt_object <- file.path(corrupt, verification$manifest$objects[[1]]$path)
  Sys.chmod(corrupt_object, "0666"); writeBin(as.raw(rep(1L, length(content))), corrupt_object)
  check("same-size object corruption rejected", rejects(brohn_verify_backup(corrupt)) &&
    rejects(brohn_restore_workspace(corrupt, file.path(directory, "rejected-corrupt"))))
  check("invalid restore never publishes a destination", !dir.exists(file.path(directory, "rejected-corrupt")))
  traversal <- copy_artifact("traversal")
  manifest <- .brohn_backup_read_manifest(traversal)
  manifest$objects[[1]]$path <- "../outside-file"
  manifest$content_sha256 <- .brohn_backup_manifest_hash(manifest)
  writeBin(charToRaw(.brohn_store_json(manifest)), file.path(traversal, "manifest.json"))
  check("path traversal rejected even with recomputed manifest hash", rejects(brohn_verify_backup(traversal)))
  missing <- copy_artifact("missing")
  missing_path <- file.path(missing, verification$manifest$objects[[1]]$path)
  Sys.chmod(missing_path, "0666"); unlink(missing_path)
  check("incomplete backup object inventory rejected", rejects(brohn_verify_backup(missing)))
  extra <- copy_artifact("extra"); writeLines("unexpected", file.path(extra, "untracked.txt"))
  check("unlisted backup files rejected", rejects(brohn_verify_backup(extra)))
  bad_schema <- copy_artifact("bad-schema")
  con <- .brohn_backup_connect(file.path(bad_schema, "catalog.sqlite"), FALSE)
  DBI::dbExecute(con, "PRAGMA user_version=99"); DBI::dbDisconnect(con)
  manifest <- .brohn_backup_read_manifest(bad_schema)
  manifest$catalog$hash <- .brohn_backup_hash(file.path(bad_schema, "catalog.sqlite"))
  manifest$catalog$size <- as.numeric(file.info(file.path(bad_schema, "catalog.sqlite"))$size)
  manifest$content_sha256 <- .brohn_backup_manifest_hash(manifest)
  writeBin(charToRaw(.brohn_store_json(manifest)), file.path(bad_schema, "manifest.json"))
  check("unsupported catalog schema rejected after valid hashes", rejects(brohn_verify_backup(bad_schema)))
  assign(".brohn_backup_copy", function(from, to) { original_copy(from, to); stop("injected copy interruption") }, envir = .GlobalEnv)
  interrupted_backup <- file.path(directory, "interrupted-backup")
  interrupted_restore <- file.path(directory, "interrupted-restore")
  check("interrupted backup cannot publish partial artifact", rejects(brohn_backup_workspace(source, interrupted_backup)) && !dir.exists(interrupted_backup))
  check("interrupted restore cannot publish partial workspace", rejects(brohn_restore_workspace(path, interrupted_restore)) && !dir.exists(interrupted_restore))
  assign(".brohn_backup_copy", original_copy, envir = .GlobalEnv)
  check("failed stages are cleaned only within temporary parent", !length(list.files(directory, pattern = "^\\.brohn-", all.files = TRUE)))
  source_object <- brohn_object_path(source, item$hash); Sys.chmod(source_object, "0666"); unlink(source_object)
  absent_destination <- file.path(directory, "absent-source-object")
  check("missing source object prevents backup publication", rejects(brohn_backup_workspace(source, absent_destination)) && !dir.exists(absent_destination))
  check("source catalog and release remain intact after failures", identical(source$workspace_id, source_identity) &&
    brohn_deployment(source, release$id)$status == "open" && length(brohn_entity_history(source, "study", design$id)) == 2L)
  cat(sprintf("PASS: %d verified workspace backup/restore checks (WAL snapshot, private history, object integrity, paused restore, failure containment)\n", checks))
})
