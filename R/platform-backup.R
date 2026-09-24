# Verified local folder backups. A pinned SQLite read transaction plus its online
# backup API captures one committed catalog view while WAL writers may continue.
# Every registered immutable object in that view is copied and hashed. Unregistered
# scratch/orphan files are deliberately excluded. Atomic same-parent directory
# publication protects the absent destination; failed attempts stay unpublished.
# These private backups are not encrypted and include participant credentials.
# Hash verification detects corruption; it is not a signature/authenticity claim.
# This does not implement privacy purges, external retention-ledger reconciliation,
# cloud backup, or qualified filesystem fsync/power-loss durability.

.brohn_backup_require <- function(ok, message) if (!isTRUE(ok)) stop(message, call. = FALSE)
.brohn_backup_prefix <- function(path) paste0(sub("/+$", "", path), "/")
.brohn_backup_inside <- function(path, root) {
  if (.Platform$OS.type == "windows") { path <- tolower(path); root <- tolower(root) }
  identical(path, root) || startsWith(path, .brohn_backup_prefix(root))
}
.brohn_backup_walk <- function(root) {
  root <- normalizePath(root, winslash = "/", mustWork = TRUE)
  queue <- root; files <- character()
  while (length(queue)) {
    directory <- queue[[1]]; queue <- queue[-1L]
    entries <- list.files(directory, full.names = TRUE, all.files = TRUE, no.. = TRUE)
    for (entry in entries) {
      link <- Sys.readlink(entry)
      .brohn_backup_require(is.na(link) || !nzchar(link), "Backup paths cannot contain symbolic links or junctions.")
      canonical <- normalizePath(entry, winslash = "/", mustWork = TRUE)
      .brohn_backup_require(.brohn_backup_inside(canonical, root), "Backup path leaves its artifact directory.")
      if (dir.exists(canonical)) queue <- c(queue, canonical) else files <- c(files, canonical)
    }
    .brohn_backup_require(length(files) + length(queue) <= 100100L, "Backup inventory exceeds the supported file count.")
  }
  files
}
.brohn_backup_remove_stage <- function(stage, parent) {
  if (!dir.exists(stage)) return(invisible(NULL))
  canonical <- normalizePath(stage, winslash = "/", mustWork = TRUE)
  .brohn_backup_require(identical(dirname(canonical), parent) && startsWith(basename(canonical), ".brohn-") &&
    identical(canonical, stage), "Refusing cleanup outside the verified temporary directory.")
  files <- .brohn_backup_walk(stage)
  if (length(files)) Sys.chmod(files, "0666")
  unlink(stage, recursive = TRUE)
  invisible(NULL)
}
.brohn_backup_destination <- function(destination, protected) {
  .brohn_backup_require(brohn_text(destination, 4096), "Choose an absent backup or restore destination.")
  parent <- normalizePath(dirname(destination), winslash = "/", mustWork = TRUE)
  name <- basename(destination)
  .brohn_backup_require(nzchar(name) && !name %in% c(".", ".."), "Destination needs a new directory name.")
  destination <- file.path(parent, name)
  .brohn_backup_require(!file.exists(destination) && !dir.exists(destination), "Destination already exists; nothing was overwritten.")
  .brohn_backup_require(!.brohn_backup_inside(destination, protected), "Destination must be outside the source workspace or backup.")
  list(path = destination, parent = parent)
}
.brohn_backup_stage <- function(parent, operation) {
  stage <- tempfile(paste0(".brohn-", operation, "-"), tmpdir = parent)
  .brohn_backup_require(dir.create(stage, mode = "0700"), "Cannot create the private staging directory.")
  normalizePath(stage, winslash = "/", mustWork = TRUE)
}
.brohn_backup_publish <- function(stage, destination) {
  .brohn_backup_require(!file.exists(destination) && !dir.exists(destination), "Destination appeared during the operation; it was not overwritten.")
  .brohn_backup_require(file.rename(stage, destination), "Could not atomically publish the verified directory.")
  normalizePath(destination, winslash = "/", mustWork = TRUE)
}
.brohn_backup_hash <- function(path) digest::digest(file = path, algo = "sha256")
.brohn_backup_copy <- function(from, to) {
  if (!dir.exists(dirname(to))) .brohn_backup_require(dir.create(dirname(to), recursive = TRUE), "Cannot create a backup object directory.")
  .brohn_backup_require(!file.exists(to) && file.copy(from, to, overwrite = FALSE), "Cannot copy a required backup file.")
  invisible(to)
}
.brohn_backup_connect <- function(path, readonly = TRUE) {
  con <- DBI::dbConnect(RSQLite::SQLite(), path,
    flags = if (readonly) RSQLite::SQLITE_RO else RSQLite::SQLITE_RWC, loadable.extensions = FALSE)
  DBI::dbExecute(con, "PRAGMA busy_timeout=5000")
  DBI::dbExecute(con, "PRAGMA trusted_schema=OFF")
  con
}
.brohn_backup_online_copy <- function(source, destination) {
  RSQLite::sqliteCopyDatabase(source, destination)
}
.brohn_backup_check_rows <- function(con, table, json_column, hash_column, semantic = FALSE) {
  query <- DBI::dbSendQuery(con, paste("SELECT", DBI::dbQuoteIdentifier(con, json_column), ",",
    DBI::dbQuoteIdentifier(con, hash_column), "FROM", DBI::dbQuoteIdentifier(con, table)))
  on.exit(DBI::dbClearResult(query), add = TRUE)
  repeat {
    rows <- DBI::dbFetch(query, n = 10L)
    if (!nrow(rows)) break
    for (i in seq_len(nrow(rows))) {
      text <- rows[[json_column]][[i]]
      value <- .brohn_store_decode(text)
      hash <- if (semantic) brohn_hash(value) else digest::digest(charToRaw(text), algo = "sha256", serialize = FALSE)
      .brohn_backup_require(identical(hash, rows[[hash_column]][[i]]), paste("Catalog integrity failed in", table))
      if (table == "delivery_runs") .brohn_backup_require(identical(brohn_hash(value$design), value$design_hash), "A frozen run design failed integrity verification.")
    }
  }
}
.brohn_backup_catalog <- function(path) {
  con <- .brohn_backup_connect(path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  .brohn_backup_require(identical(DBI::dbGetQuery(con, "PRAGMA integrity_check")[[1]], "ok"), "SQLite integrity check failed.")
  .brohn_backup_require(nrow(DBI::dbGetQuery(con, "PRAGMA foreign_key_check")) == 0L, "SQLite foreign-key check failed.")
  version <- DBI::dbGetQuery(con, "PRAGMA user_version")[[1]][[1]]
  .brohn_backup_require(identical(as.integer(version), 1L), "Unsupported workspace catalog schema.")
  tables <- DBI::dbListTables(con)
  required <- c("metadata", "entities", "entity_versions", "entity_operations", "objects", "jobs", "audit_log")
  .brohn_backup_require(all(required %in% tables), "Workspace catalog is incomplete.")
  identity <- DBI::dbGetQuery(con, "SELECT value FROM metadata WHERE key='workspace_id'")
  .brohn_backup_require(nrow(identity) == 1L && brohn_text(identity$value[[1]], 128), "Workspace identity is missing.")
  dangling <- DBI::dbGetQuery(con, paste("SELECT count(*) AS n FROM entities e LEFT JOIN entity_versions v",
    "ON v.kind=e.kind AND v.id=e.id AND v.revision=e.revision WHERE v.id IS NULL"))$n[[1]]
  .brohn_backup_require(dangling == 0L, "A catalog head has no immutable revision.")
  .brohn_backup_check_rows(con, "entity_versions", "body_json", "body_hash")
  .brohn_backup_check_rows(con, "jobs", "request_json", "request_hash")
  if ("delivery_deployments" %in% tables) .brohn_backup_check_rows(con, "delivery_deployments", "design_json", "design_hash", TRUE)
  if ("delivery_runs" %in% tables) .brohn_backup_check_rows(con, "delivery_runs", "protocol_json", "protocol_hash")
  if ("camera_captures" %in% tables) {
    .brohn_backup_require(exists("brohn_capture_catalog_integrity", mode = "function"), "This backup needs the camera recording integrity module.")
    brohn_capture_catalog_integrity(con)
  }
  if (any(c("delivery_runtimes", "delivery_run_runtimes") %in% tables) ||
      DBI::dbGetQuery(con, "SELECT count(*) AS n FROM audit_log WHERE action='deployment.runtime_pinned'")$n[[1L]] > 0L) {
    .brohn_backup_require(exists("brohn_runner_catalog_integrity", mode = "function"), "This backup needs the participant code integrity module.")
    brohn_runner_catalog_integrity(con)
  }
  if ("delivery_events" %in% tables) .brohn_backup_check_rows(con, "delivery_events", "event_json", "event_hash")
  objects <- DBI::dbGetQuery(con, "SELECT hash,size,media_type FROM objects ORDER BY hash")
  .brohn_backup_require(nrow(objects) <= 100000L && !anyDuplicated(objects$hash) &&
    all(grepl("^[a-f0-9]{64}$", objects$hash)) && all(is.finite(objects$size) & objects$size >= 0 & objects$size == floor(objects$size)),
    "Catalog object inventory is invalid or exceeds 100,000 objects.")
  inventory <- lapply(seq_len(nrow(objects)), function(i) list(hash = objects$hash[[i]], size = objects$size[[i]],
    media_type = objects$media_type[[i]], path = paste0("objects/sha256/", substr(objects$hash[[i]], 1, 2), "/", objects$hash[[i]])))
  counts <- setNames(lapply(sort(tables), function(table) DBI::dbGetQuery(con,
    paste("SELECT count(*) AS n FROM", DBI::dbQuoteIdentifier(con, table)))$n[[1]]), sort(tables))
  list(workspace_id = identity$value[[1]], schema_version = as.integer(version), objects = inventory, table_counts = counts)
}
.brohn_backup_manifest_hash <- function(manifest) {
  manifest$content_sha256 <- NULL
  digest::digest(charToRaw(.brohn_store_json(manifest, maximum = 64 * 1024^2)), algo = "sha256", serialize = FALSE)
}
.brohn_backup_read_manifest <- function(path) {
  manifest_path <- file.path(path, "manifest.json")
  .brohn_backup_require(file.exists(manifest_path) && !dir.exists(manifest_path), "Backup manifest is missing.")
  connection <- file(manifest_path, open = "rb"); on.exit(close(connection), add = TRUE)
  bytes <- readBin(connection, "raw", n = 64 * 1024^2 + 1)
  .brohn_backup_require(length(bytes) > 0L && length(bytes) <= 64 * 1024^2, "Backup manifest is empty or too large.")
  text <- rawToChar(bytes); Encoding(text) <- "UTF-8"
  .brohn_backup_require(!is.na(iconv(text, from = "UTF-8", to = "UTF-8")), "Backup manifest is not valid UTF-8.")
  manifest <- jsonlite::fromJSON(text, simplifyVector = FALSE)
  brohn_fields(manifest, c("schema_version", "id", "created_at", "workspace_id", "catalog", "objects", "table_counts", "privacy", "content_sha256"), label = "Backup manifest")
  .brohn_backup_require(identical(manifest$schema_version, "brohn-backup/1.0.0") && brohn_valid_id(manifest$id) &&
    brohn_text(manifest$workspace_id, 128), "Unsupported backup manifest identity or schema.")
  .brohn_backup_require(identical(.brohn_backup_manifest_hash(manifest), manifest$content_sha256), "Backup manifest integrity check failed.")
  manifest
}
brohn_verify_backup <- function(path) {
  path <- normalizePath(path, winslash = "/", mustWork = TRUE)
  .brohn_backup_require(dir.exists(path), "Choose a Brohn backup directory.")
  files <- .brohn_backup_walk(path)
  manifest <- .brohn_backup_read_manifest(path)
  brohn_fields(manifest$catalog, c("path", "hash", "size", "schema_version"), label = "Backup catalog")
  .brohn_backup_require(identical(manifest$catalog$path, "catalog.sqlite") &&
    brohn_text(manifest$catalog$hash, 64) && grepl("^[a-f0-9]{64}$", manifest$catalog$hash) &&
    brohn_number(manifest$catalog$size, 1, 2^53, TRUE) && manifest$catalog$schema_version == 1L,
    "Backup catalog entry is invalid.")
  .brohn_backup_require(brohn_array(manifest$objects) && length(manifest$objects) <= 100000L, "Backup object inventory is invalid.")
  inventory <- manifest$objects
  for (item in inventory) {
    brohn_fields(item, c("hash", "size", "media_type", "path"), label = "Backup object")
    .brohn_backup_require(brohn_text(item$hash, 64) && grepl("^[a-f0-9]{64}$", item$hash) &&
      brohn_number(item$size, 0, 2^53, TRUE) && brohn_text(item$media_type, 256) &&
      identical(item$path, paste0("objects/sha256/", substr(item$hash, 1, 2), "/", item$hash)), "Backup object path or metadata is invalid.")
  }
  paths <- vapply(inventory, `[[`, character(1), "path")
  .brohn_backup_require(!anyDuplicated(paths), "Backup contains duplicate object identities.")
  relative_files <- substring(files, nchar(.brohn_backup_prefix(path)) + 1L)
  .brohn_backup_require(setequal(relative_files, c("manifest.json", "catalog.sqlite", paths)), "Backup file inventory is incomplete or contains unexpected files.")
  verify_file <- function(relative, hash, size) {
    file <- file.path(path, relative)
    .brohn_backup_require(identical(as.numeric(file.info(file)$size), as.numeric(size)) &&
      identical(.brohn_backup_hash(file), hash), paste("Backup file failed verification:", relative))
  }
  verify_file("catalog.sqlite", manifest$catalog$hash, manifest$catalog$size)
  catalog <- .brohn_backup_catalog(file.path(path, "catalog.sqlite"))
  .brohn_backup_require(identical(catalog$workspace_id, manifest$workspace_id) &&
    identical(.brohn_store_json(catalog$objects, maximum = 64 * 1024^2), .brohn_store_json(inventory, maximum = 64 * 1024^2)) &&
    identical(.brohn_store_json(catalog$table_counts), .brohn_store_json(manifest$table_counts)), "Manifest and captured catalog membership disagree.")
  for (item in inventory) verify_file(item$path, item$hash, item$size)
  list(path = path, manifest = manifest, verified = TRUE, object_count = length(inventory),
    total_bytes = manifest$catalog$size + sum(vapply(inventory, `[[`, numeric(1), "size")))
}
brohn_backup_workspace <- function(store, destination) {
  if (!is.null(store$hosted_profile)) brohn_hosted_require_action(store, "backup")
  .brohn_store_ready(store)
  .brohn_backup_require(!RSQLite::sqliteIsTransacting(store$con), "Start backup outside an active application transaction.")
  target <- .brohn_backup_destination(destination, store$root)
  stage <- .brohn_backup_stage(target$parent, "backup")
  on.exit(.brohn_backup_remove_stage(stage, target$parent), add = TRUE)
  snapshot_path <- file.path(stage, "catalog.sqlite")
  source <- .brohn_backup_connect(file.path(store$root, "catalog.sqlite"))
  copied <- .brohn_backup_connect(snapshot_path, readonly = FALSE)
  connections_closed <- FALSE
  on.exit(if (!connections_closed) {
    try(DBI::dbDisconnect(copied), silent = TRUE)
    try(DBI::dbDisconnect(source), silent = TRUE)
  }, add = TRUE, after = FALSE)
  DBI::dbExecute(source, "BEGIN")
  DBI::dbGetQuery(source, "SELECT value FROM metadata WHERE key='workspace_id'")
  # sqliteCopyDatabase wraps SQLite's online backup API; copying catalog.sqlite
  # with file.copy would lose WAL commits and would not be a consistent snapshot.
  .brohn_backup_online_copy(source, copied)
  DBI::dbExecute(source, "ROLLBACK")
  DBI::dbGetQuery(copied, "PRAGMA journal_mode=DELETE")
  DBI::dbDisconnect(copied); DBI::dbDisconnect(source); connections_closed <- TRUE
  catalog <- .brohn_backup_catalog(snapshot_path)
  for (item in catalog$objects) {
    source_path <- brohn_object_path(store, item$hash, verify = TRUE)
    .brohn_backup_copy(source_path, file.path(stage, item$path))
    .brohn_backup_require(identical(.brohn_backup_hash(file.path(stage, item$path)), item$hash), "Object changed or could not be copied intact.")
  }
  manifest <- list(schema_version = "brohn-backup/1.0.0", id = brohn_id("backup"), created_at = brohn_now(),
    workspace_id = catalog$workspace_id,
    catalog = list(path = "catalog.sqlite", hash = .brohn_backup_hash(snapshot_path),
      size = as.numeric(file.info(snapshot_path)$size), schema_version = catalog$schema_version),
    objects = catalog$objects, table_counts = catalog$table_counts,
    privacy = list(encrypted = FALSE, includes_participant_data = TRUE, includes_private_credentials = TRUE,
      excluded = list("unregistered_orphan_objects", "temporary_worker_files", "external_files_not_in_the_catalog")))
  manifest$content_sha256 <- .brohn_backup_manifest_hash(manifest)
  writeBin(charToRaw(.brohn_store_json(manifest, maximum = 64 * 1024^2)), file.path(stage, "manifest.json"))
  verified <- brohn_verify_backup(stage)
  path <- .brohn_backup_publish(stage, target$path)
  list(path = path, backup_id = manifest$id, workspace_id = manifest$workspace_id,
    manifest_hash = manifest$content_sha256, format = "folder", verified = TRUE,
    object_count = verified$object_count, total_bytes = verified$total_bytes)
}
.brohn_backup_metadata <- function(store, key, value) {
  DBI::dbExecute(store$con, "INSERT INTO metadata(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value",
    params = list(key, value))
}
brohn_workspace_execution_status <- function(store) {
  .brohn_store_ready(store)
  values <- DBI::dbGetQuery(store$con, "SELECT key,value FROM metadata WHERE key IN ('execution_paused','restore_id','restore_source_workspace_id','restore_backup_id')")
  data <- setNames(as.list(values$value), values$key)
  list(paused = identical(data$execution_paused, "1"), restore_id = data$restore_id,
    source_workspace_id = data$restore_source_workspace_id, backup_id = data$restore_backup_id)
}
brohn_resume_workspace <- function(store) {
  if (!is.null(store$hosted_profile)) brohn_hosted_require_action(store, "resume_workspace")
  .brohn_store_tx(store, function() {
    status <- brohn_workspace_execution_status(store)
    if (isTRUE(status$paused)) {
      .brohn_backup_metadata(store, "execution_paused", "0")
      .brohn_store_audit(store, "workspace.execution_resumed", store$workspace_id, list(restore_id = status$restore_id))
    }
    brohn_workspace_execution_status(store)
  })
}
brohn_restore_workspace <- function(backup, destination) {
  verified <- brohn_verify_backup(backup)
  target <- .brohn_backup_destination(destination, verified$path)
  stage <- .brohn_backup_stage(target$parent, "restore")
  on.exit(.brohn_backup_remove_stage(stage, target$parent), add = TRUE)
  .brohn_backup_copy(file.path(verified$path, "catalog.sqlite"), file.path(stage, "catalog.sqlite"))
  .brohn_backup_require(identical(.brohn_backup_hash(file.path(stage, "catalog.sqlite")), verified$manifest$catalog$hash), "Catalog changed while restoring.")
  for (item in verified$manifest$objects) {
    path <- file.path(stage, item$path)
    .brohn_backup_copy(file.path(verified$path, item$path), path)
    .brohn_backup_require(identical(.brohn_backup_hash(path), item$hash), "Object changed while restoring.")
    Sys.chmod(path, "0444")
  }
  restored <- brohn_open_store(stage)
  closed <- FALSE
  on.exit(if (!closed) brohn_close_store(restored), add = TRUE, after = FALSE)
  restore_id <- brohn_id("restore"); new_identity <- brohn_id("workspace")
  changes <- .brohn_store_tx(restored, function() {
    .brohn_backup_metadata(restored, "workspace_id", new_identity)
    .brohn_backup_metadata(restored, "execution_paused", "1")
    .brohn_backup_metadata(restored, "restore_id", restore_id)
    .brohn_backup_metadata(restored, "restore_source_workspace_id", verified$manifest$workspace_id)
    .brohn_backup_metadata(restored, "restore_backup_id", verified$manifest$id)
    .brohn_backup_metadata(restored, "restore_manifest_hash", verified$manifest$content_sha256)
    tables <- DBI::dbListTables(restored$con)
    deployments <- 0L; credentials <- 0L
    if ("delivery_deployments" %in% tables) deployments <- DBI::dbExecute(restored$con,
      "UPDATE delivery_deployments SET status='closed',updated_at=? WHERE status<>'closed'", params = list(brohn_now()))
    for (table in intersect(c("delivery_deployment_credentials", "delivery_run_credentials"), tables)) {
      id_column <- if (table == "delivery_deployment_credentials") "deployment_id" else "run_id"
      ids <- DBI::dbGetQuery(restored$con, paste("SELECT", id_column, "FROM", table))[[1]]
      for (id in ids) {
        token <- brohn_token()
        DBI::dbExecute(restored$con, paste("UPDATE", table, "SET token=?,token_hash=? WHERE", id_column, "=?"),
          params = list(token, digest::digest(charToRaw(token), algo = "sha256", serialize = FALSE), id))
        credentials <- credentials + 1L
      }
    }
    running <- DBI::dbExecute(restored$con,
      "UPDATE jobs SET status='queued',worker=NULL,token=NULL,lease_until=NULL,updated_at=? WHERE status='running'", params = list(brohn_now()))
    .brohn_store_audit(restored, "workspace.restored", new_identity, list(restore_id = restore_id,
      source_workspace_id = verified$manifest$workspace_id, backup_id = verified$manifest$id,
      manifest_hash = verified$manifest$content_sha256, deployments_closed = deployments,
      credentials_rotated = credentials, running_jobs_requeued = running, execution_paused = TRUE))
    list(deployments_closed = deployments, credentials_rotated = credentials, jobs_requeued = running)
  })
  # Collapse WAL before publishing a portable workspace directory. The restored
  # destination is unpublished and has no worker/server attached during this step.
  DBI::dbGetQuery(restored$con, "PRAGMA wal_checkpoint(TRUNCATE)")
  brohn_close_store(restored); closed <- TRUE
  catalog <- .brohn_backup_catalog(file.path(stage, "catalog.sqlite"))
  .brohn_backup_require(identical(catalog$workspace_id, new_identity) &&
    identical(.brohn_store_json(catalog$objects, maximum = 64 * 1024^2), .brohn_store_json(verified$manifest$objects, maximum = 64 * 1024^2)),
    "Restored workspace failed final catalog verification.")
  path <- .brohn_backup_publish(stage, target$path)
  c(list(root = path, workspace_id = new_identity, source_workspace_id = verified$manifest$workspace_id,
    restore_id = restore_id, verified = TRUE, execution_paused = TRUE, object_count = verified$object_count), changes)
}
