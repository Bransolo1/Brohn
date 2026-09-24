# Released browser code is a stored research dependency. These helpers do not
# infer which code a historic participant executed, nor alter frozen protocols.
.brohn_runner_require <- function(ok, message, status = 409L) {
  .brohn_delivery_require(ok, message, status, "runner_integrity")
}
.brohn_runner_hash <- function(bytes) digest::digest(bytes, algo = "sha256", serialize = FALSE)
.brohn_runner_type <- function(path) {
  if (identical(path, "brand/brohn-app-icon.svg")) return("image/svg+xml")
  extension <- tools::file_ext(path)
  unname(c(html = "text/html; charset=utf-8", js = "application/javascript; charset=utf-8",
    css = "text/css; charset=utf-8")[[extension]])
}
.brohn_runner_paths <- function() c("brand/brohn-app-icon.svg", paste0("participant/", sort(c(
  "index.html", "runner.js", "runner.css", "tasks.js", "sciat-window-core.js", "sciat-window.js", "gnat-core.js", "gnat.js",
  "camera.js", "equipment.js", "audio-worklet.js", "maxdiff.js", "maxdiff.css", "question-revision.js",
  "illustrations.js", "welcome.js", "welcome.css", "event-batch.js"), method = "radix")))
.brohn_runner_manifest <- function(manifest, expected_hash = NULL) {
  brohn_fields(manifest, c("schema", "files"), label = "Participant runtime manifest")
  .brohn_runner_require(identical(manifest$schema, "brohn-participant-runtime/1.0") &&
    is.list(manifest$files) && length(manifest$files) >= 3L && length(manifest$files) <= 64L,
    "Participant runtime manifest is invalid.")
  paths <- character()
  for (item in manifest$files) {
    brohn_fields(item, c("path", "hash", "size", "media_type"), label = "Participant runtime file")
    .brohn_runner_require(brohn_text(item$path, 160L) &&
      (grepl("^participant/[a-z][a-z0-9-]*\\.(html|js|css)$", item$path) ||
       identical(item$path, "brand/brohn-app-icon.svg")), "Participant runtime file path is invalid.")
    .brohn_runner_require(brohn_text(item$hash, 64L) && grepl("^[a-f0-9]{64}$", item$hash) &&
      brohn_number(item$size, 1, 1024^2, TRUE) && identical(item$media_type, .brohn_runner_type(item$path)),
      "Participant runtime file metadata is invalid.")
    paths <- c(paths, item$path)
  }
  .brohn_runner_require(!anyDuplicated(paths) && identical(paths, sort(paths, method = "radix")) &&
    all(c("participant/index.html", "participant/runner.js", "participant/runner.css") %in% paths) &&
    sum(vapply(manifest$files, function(x) x$size, numeric(1))) <= 8 * 1024^2,
    "Participant runtime file inventory is invalid.")
  hash <- brohn_hash(manifest)
  if (!is.null(expected_hash)) .brohn_runner_require(identical(hash, expected_hash),
    "Participant runtime manifest changed.")
  invisible(hash)
}
brohn_runner_assets_prepare <- function(static_root = "www/participant") {
  .brohn_runner_require(brohn_text(static_root, 4096L) && dir.exists(static_root),
    "Participant interface files are unavailable.", 503L)
  root <- normalizePath(static_root, winslash = "/", mustWork = TRUE)
  site <- normalizePath(dirname(root), winslash = "/", mustWork = TRUE)
  paths <- .brohn_runner_paths()
  sources <- vapply(paths, function(path) {
    source <- if (startsWith(path, "participant/")) file.path(root, substring(path, 13L)) else file.path(site, path)
    .brohn_runner_require(file.exists(source) && !dir.exists(source),
      paste0("Participant interface file is missing: ", path), 503L)
    source <- normalizePath(source, winslash = "/", mustWork = TRUE)
    compared_source <- if (.Platform$OS.type == "windows") tolower(source) else source
    compared_site <- if (.Platform$OS.type == "windows") tolower(site) else site
    .brohn_runner_require(startsWith(compared_source, paste0(compared_site, "/")),
      "Participant interface files must stay within their distribution.", 503L)
    source
  }, character(1))
  read_source <- function(path) {
    size <- file.info(path)$size
    .brohn_runner_require(is.finite(size) && size > 0 && size <= 1024^2,
      "Participant interface file exceeds the supported size.", 503L)
    bytes <- readBin(path, "raw", n = size + 1L)
    .brohn_runner_require(length(bytes) == size, "Participant interface changed while being read.", 503L)
    bytes
  }
  bytes <- lapply(sources, read_source)
  manifest <- list(schema = "brohn-participant-runtime/1.0", files = unname(lapply(seq_along(paths), function(i)
    list(path = paths[[i]], hash = .brohn_runner_hash(bytes[[i]]), size = length(bytes[[i]]),
      media_type = .brohn_runner_type(paths[[i]])))))
  hash <- .brohn_runner_manifest(manifest)
  # A release must not silently omit a newly referenced entry asset. Relative
  # paths remain byte-identical because the stored URL retains the site layout.
  html <- rawToChar(bytes[["participant/index.html"]])
  references <- regmatches(html, gregexpr("(?:src|href)=[\"'][^\"']+[\"']", html, perl = TRUE))[[1L]]
  references <- sub("^[^=]+=[\"']", "", sub("[\"']$", "", references))
  references <- references[!startsWith(references, "#")]
  logical_paths <- ifelse(startsWith(references, "../brand/"), substring(references, 4L), paste0("participant/", references))
  .brohn_runner_require(all(logical_paths %in% paths), "Participant entry references an unregistered interface asset.", 503L)
  for (i in seq_along(sources)) .brohn_runner_require(identical(read_source(sources[[i]]), bytes[[i]]),
    "Participant interface changed while preparing the release. Retry after the update finishes.", 503L)
  list(manifest = manifest, hash = hash, bytes = bytes)
}
.brohn_runner_schema <- function(store) {
  .brohn_delivery_schema(store)
  .brohn_store_tx(store, function() {
    sql <- c(
      "CREATE INDEX IF NOT EXISTS delivery_runtime_audit ON audit_log(action,target) WHERE action='deployment.runtime_pinned'",
      "CREATE TABLE IF NOT EXISTS delivery_runtimes (deployment_id TEXT PRIMARY KEY, manifest_hash TEXT NOT NULL, manifest_json TEXT NOT NULL, created_at TEXT NOT NULL, FOREIGN KEY(deployment_id) REFERENCES delivery_deployments(id))",
      "CREATE TABLE IF NOT EXISTS delivery_run_runtimes (run_id TEXT PRIMARY KEY, deployment_id TEXT NOT NULL, manifest_hash TEXT NOT NULL, created_at TEXT NOT NULL, FOREIGN KEY(run_id) REFERENCES delivery_runs(id), FOREIGN KEY(deployment_id) REFERENCES delivery_runtimes(deployment_id))",
      "CREATE TRIGGER IF NOT EXISTS delivery_runtime_no_update BEFORE UPDATE ON delivery_runtimes BEGIN SELECT RAISE(ABORT,'Released participant code is immutable'); END",
      "CREATE TRIGGER IF NOT EXISTS delivery_runtime_no_delete BEFORE DELETE ON delivery_runtimes BEGIN SELECT RAISE(ABORT,'Released participant code is immutable'); END",
      "CREATE TRIGGER IF NOT EXISTS delivery_run_runtime_no_update BEFORE UPDATE ON delivery_run_runtimes BEGIN SELECT RAISE(ABORT,'Assigned participant code is immutable'); END",
      "CREATE TRIGGER IF NOT EXISTS delivery_run_runtime_no_delete BEFORE DELETE ON delivery_run_runtimes BEGIN SELECT RAISE(ABORT,'Assigned participant code is immutable'); END",
      "CREATE TRIGGER IF NOT EXISTS delivery_run_runtime_match BEFORE INSERT ON delivery_run_runtimes WHEN NOT EXISTS (SELECT 1 FROM delivery_runs r JOIN delivery_runtimes d ON d.deployment_id=r.deployment_id WHERE r.id=NEW.run_id AND r.deployment_id=NEW.deployment_id AND d.manifest_hash=NEW.manifest_hash) BEGIN SELECT RAISE(ABORT,'Assigned participant code does not match its release'); END"
    )
    for (statement in sql) DBI::dbExecute(store$con, statement)
  })
  invisible(NULL)
}
.brohn_runner_expected <- function(con, deployment_id = NULL) {
  if (!"audit_log" %in% DBI::dbListTables(con)) return(data.frame(target = character(), detail_json = character()))
  if (is.null(deployment_id)) DBI::dbGetQuery(con,
    "SELECT target,detail_json FROM audit_log WHERE action='deployment.runtime_pinned'") else
    DBI::dbGetQuery(con, "SELECT target,detail_json FROM audit_log WHERE action='deployment.runtime_pinned' AND target=?", params = list(deployment_id))
}
.brohn_runner_expected_match <- function(expected, hash, files) {
  .brohn_runner_require(nrow(expected) == 1L, "Preserved participant code has no unique publication record.")
  detail <- .brohn_store_decode(expected$detail_json[[1L]])
  .brohn_runner_require(identical(detail$manifest_hash, hash) && brohn_number(detail$files, 3, 64, TRUE) &&
    detail$files == files, "Preserved participant code differs from its original publication record.")
}
brohn_runner_assets_read <- function(store, deployment_id) {
  # Static resource reads must not acquire a SQLite writer merely to rerun
  # schema creation. Publication/initialization creates these tables explicitly.
  tables <- DBI::dbListTables(store$con)
  .brohn_runner_require("delivery_deployments" %in% tables, "Study release was not found.", 404L)
  .brohn_runner_require(brohn_valid_id(deployment_id) &&
    nrow(.brohn_delivery_deployment_row(store, id = deployment_id)) == 1L, "Study release was not found.", 404L)
  expected <- .brohn_runner_expected(store$con, deployment_id)
  .brohn_runner_require(nrow(expected) <= 1L, "Participant runtime publication history is inconsistent.")
  if (!any(c("delivery_runtimes", "delivery_run_runtimes") %in% tables))
    { .brohn_runner_require(nrow(expected) == 0L, "Preserved participant code catalog is missing.")
      return(list(status = "legacy_unpinned", manifest_hash = NULL, manifest = NULL)) }
  .brohn_runner_require(all(c("delivery_runtimes", "delivery_run_runtimes") %in% tables),
    "Participant runtime catalog is incomplete.")
  row <- DBI::dbGetQuery(store$con, "SELECT * FROM delivery_runtimes WHERE deployment_id=?", params = list(deployment_id))
  if (!nrow(row)) {
    .brohn_runner_require(nrow(expected) == 0L, "Preserved participant code is missing for this release.")
    return(list(status = "legacy_unpinned", manifest_hash = NULL, manifest = NULL))
  }
  manifest <- .brohn_store_decode(row$manifest_json[[1L]], row$manifest_hash[[1L]])
  .brohn_runner_manifest(manifest, row$manifest_hash[[1L]])
  .brohn_runner_expected_match(expected, row$manifest_hash[[1L]], length(manifest$files))
  list(status = "pinned", manifest_hash = row$manifest_hash[[1L]], manifest = manifest)
}
brohn_runner_assets_publish <- function(store, prepared, create) {
  .brohn_runner_schema(store)
  brohn_fields(prepared, c("manifest", "hash", "bytes"), label = "Prepared participant runtime")
  .brohn_runner_manifest(prepared$manifest, prepared$hash)
  paths <- vapply(prepared$manifest$files, function(x) x$path, character(1))
  .brohn_runner_require(is.list(prepared$bytes) && identical(names(prepared$bytes), paths),
    "Prepared participant runtime file inventory changed.")
  for (i in seq_along(paths)) {
    item <- prepared$manifest$files[[i]]; bytes <- prepared$bytes[[i]]
    .brohn_runner_require(is.raw(bytes) && length(bytes) == item$size && identical(.brohn_runner_hash(bytes), item$hash),
      "Prepared participant runtime bytes changed.")
  }
  .brohn_runner_require(is.function(create), "A new release publication is required.")
  .brohn_store_tx(store, function() {
    # The new row must be created inside this transaction. A zero-participant
    # historical release still cannot acquire invented historical code identity.
    before <- DBI::dbGetQuery(store$con, "SELECT coalesce(max(rowid),0) AS n FROM delivery_deployments")$n[[1L]]
    release <- create()
    .brohn_runner_require(is.list(release) && brohn_valid_id(release$id), "New release publication did not return a release.")
    deployment_id <- release$id
    created <- DBI::dbGetQuery(store$con, "SELECT id FROM delivery_deployments WHERE rowid>?", params = list(before))
    .brohn_runner_require(nrow(created) == 1L && identical(created$id[[1L]], deployment_id),
      "Participant code must be preserved during a new release publication.")
    count <- DBI::dbGetQuery(store$con, "SELECT count(*) AS n FROM delivery_runs WHERE deployment_id=?", params = list(deployment_id))$n[[1L]]
    .brohn_runner_require(count == 0L, "Participant code cannot be assigned retrospectively to an existing session.")
    for (i in seq_along(paths)) {
      item <- prepared$manifest$files[[i]]
      stored <- brohn_store_object(store, bytes = prepared$bytes[[i]], media_type = item$media_type)
      .brohn_runner_require(identical(stored$hash, item$hash) && stored$size == item$size, "Stored participant code failed verification.")
    }
    DBI::dbExecute(store$con, "INSERT INTO delivery_runtimes VALUES (?,?,?,?)", params =
      list(deployment_id, prepared$hash, .brohn_store_json(prepared$manifest), brohn_now()))
    .brohn_store_audit(store, "deployment.runtime_pinned", deployment_id, list(manifest_hash = prepared$hash, files = length(paths)))
    release$participant_runtime <- brohn_runner_assets_read(store, deployment_id)
    release
  })
}
brohn_runner_catalog_integrity <- function(con) {
  tables <- DBI::dbListTables(con)
  expected <- .brohn_runner_expected(con)
  if (!any(c("delivery_runtimes", "delivery_run_runtimes") %in% tables)) {
    .brohn_runner_require(nrow(expected) == 0L, "Preserved participant code catalog is missing.")
    return(invisible(TRUE))
  }
  .brohn_runner_require(all(c("delivery_runtimes", "delivery_run_runtimes", "delivery_deployments", "delivery_runs", "objects") %in% tables),
    "Participant runtime catalog is incomplete.")
  rows <- DBI::dbGetQuery(con, "SELECT * FROM delivery_runtimes")
  .brohn_runner_require(!anyDuplicated(expected$target) && setequal(expected$target, rows$deployment_id),
    "Preserved participant code inventory differs from its original publication history.")
  for (i in seq_len(nrow(rows))) {
    manifest <- .brohn_store_decode(rows$manifest_json[[i]], rows$manifest_hash[[i]])
    .brohn_runner_manifest(manifest, rows$manifest_hash[[i]])
    .brohn_runner_expected_match(expected[expected$target == rows$deployment_id[[i]], , drop = FALSE],
      rows$manifest_hash[[i]], length(manifest$files))
    .brohn_runner_require(nrow(DBI::dbGetQuery(con, "SELECT id FROM delivery_deployments WHERE id=?", params = list(rows$deployment_id[[i]]))) == 1L,
      "Participant runtime release is missing.")
    for (item in manifest$files) {
      object <- DBI::dbGetQuery(con, "SELECT size FROM objects WHERE hash=?", params = list(item$hash))
      .brohn_runner_require(nrow(object) == 1L && object$size[[1L]] == item$size, "Participant runtime object reference is invalid.")
    }
  }
  mismatched <- DBI::dbGetQuery(con, paste("SELECT count(*) AS n FROM delivery_run_runtimes b",
    "LEFT JOIN delivery_runs r ON r.id=b.run_id LEFT JOIN delivery_runtimes d ON d.deployment_id=b.deployment_id",
    "WHERE r.id IS NULL OR d.deployment_id IS NULL OR r.deployment_id<>b.deployment_id OR b.manifest_hash<>d.manifest_hash"))$n[[1L]]
  .brohn_runner_require(mismatched == 0L, "Participant runtime assignment differs from its original release.")
  missing <- DBI::dbGetQuery(con, paste("SELECT count(*) AS n FROM delivery_runs r JOIN delivery_runtimes d ON d.deployment_id=r.deployment_id",
    "LEFT JOIN delivery_run_runtimes b ON b.run_id=r.id WHERE b.run_id IS NULL"))$n[[1L]]
  .brohn_runner_require(missing == 0L, "A participant session is missing its preserved code assignment.")
  invisible(TRUE)
}
brohn_runner_start_identity <- function(store, deployment_id, runtime_hash = NULL, required = FALSE) {
  runtime <- brohn_runner_assets_read(store, deployment_id)
  if (identical(runtime$status, "legacy_unpinned")) {
    .brohn_runner_require(is.null(runtime_hash), "This historic release has no preserved participant interface.")
    return(NULL)
  }
  if (isTRUE(required) || !is.null(runtime_hash)) .brohn_runner_require(
    brohn_text(runtime_hash, 64L) && identical(runtime_hash, runtime$manifest_hash),
    "Open the original participant study link to use the interface preserved with this release.")
  runtime$manifest_hash
}
brohn_runner_run_read <- function(store, run_id) {
  .brohn_runner_require(brohn_valid_id(run_id), "Participant session was not found.", 404L)
  row <- DBI::dbGetQuery(store$con, "SELECT id,deployment_id FROM delivery_runs WHERE id=?", params = list(run_id))
  .brohn_runner_require(nrow(row) == 1L, "Participant session was not found.", 404L)
  runtime <- brohn_runner_assets_read(store, row$deployment_id[[1L]])
  if ("delivery_run_runtimes" %in% DBI::dbListTables(store$con)) {
    bound <- DBI::dbGetQuery(store$con, "SELECT * FROM delivery_run_runtimes WHERE run_id=?", params = list(run_id))
    if (identical(runtime$status, "pinned")) .brohn_runner_require(nrow(bound) == 1L &&
      identical(bound$deployment_id[[1L]], row$deployment_id[[1L]]) && identical(bound$manifest_hash[[1L]], runtime$manifest_hash),
      "Participant session code assignment is missing or differs from its release.") else
      .brohn_runner_require(nrow(bound) == 0L, "A historic session has an unexpected participant code assignment.")
  }
  c(list(run_id = run_id, deployment_id = row$deployment_id[[1L]]), runtime)
}
brohn_runner_asset <- function(store, deployment_id, manifest_hash, path) {
  runtime <- brohn_runner_assets_read(store, deployment_id)
  .brohn_runner_require(identical(runtime$status, "pinned") && identical(runtime$manifest_hash, manifest_hash),
    "Participant code was not found for this release.", 404L)
  .brohn_runner_require(brohn_text(path, 160L), "Participant interface asset was not found.", 404L)
  items <- Filter(function(x) identical(x$path, path), runtime$manifest$files)
  .brohn_runner_require(length(items) == 1L, "Participant interface asset was not found.", 404L)
  item <- items[[1L]]
  file <- brohn_object_path(store, item$hash, verify = TRUE)
  bytes <- readBin(file, "raw", n = item$size + 1L)
  .brohn_runner_require(length(bytes) == item$size && identical(.brohn_runner_hash(bytes), item$hash),
    "Stored participant code failed verification.", 503L)
  list(body = bytes, type = item$media_type, hash = item$hash)
}
brohn_runner_bind_run <- function(store, run_id, manifest_hash) {
  .brohn_runner_schema(store)
  .brohn_store_tx(store, function() {
    row <- DBI::dbGetQuery(store$con, "SELECT * FROM delivery_runs WHERE id=?", params = list(run_id))
    .brohn_runner_require(nrow(row) == 1L, "Participant session was not found.", 404L)
    runtime <- brohn_runner_assets_read(store, row$deployment_id[[1L]])
    .brohn_runner_require(identical(runtime$status, "pinned") && identical(runtime$manifest_hash, manifest_hash),
      "Participant interface does not match this release.")
    old <- DBI::dbGetQuery(store$con, "SELECT * FROM delivery_run_runtimes WHERE run_id=?", params = list(run_id))
    if (nrow(old)) {
      .brohn_runner_require(identical(old$manifest_hash[[1L]], manifest_hash) && identical(old$deployment_id[[1L]], row$deployment_id[[1L]]),
        "Participant interface assignment changed.")
      return(invisible(manifest_hash))
    }
    .brohn_runner_require(row$acked_sequence[[1L]] == 0L && identical(row$completion_status[[1L]], "in_progress"),
      "Participant code cannot be assigned after collection has begun.")
    DBI::dbExecute(store$con, "INSERT INTO delivery_run_runtimes VALUES (?,?,?,?)", params =
      list(run_id, row$deployment_id[[1L]], manifest_hash, brohn_now()))
    invisible(manifest_hash)
  })
}
.brohn_runner_query_identity <- function(query = "", required = FALSE) {
  .brohn_runner_require(brohn_text(query, 4096L, TRUE), "Study link query is invalid.", 400L)
  # httpuv retains the leading '?' while direct dispatcher callers may omit it.
  # Strip only that delimiter; identities still pass the same duplicate checks.
  if (startsWith(query, "?")) query <- substring(query, 2L)
  fields <- if (nzchar(query)) strsplit(query, "&", fixed = TRUE)[[1L]] else character()
  identities <- character()
  for (field in fields) {
    split <- regexpr("=", field, fixed = TRUE)[[1L]]
    key <- if (split < 0L) field else substr(field, 1L, split - 1L)
    value <- if (split < 0L) "" else substring(field, split + 1L)
    key <- utils::URLdecode(gsub("+", " ", key, fixed = TRUE))
    if (key %in% c("token", "study")) identities <- c(identities, utils::URLdecode(gsub("+", " ", value, fixed = TRUE)))
  }
  .brohn_runner_require(length(identities) <= 1L && (!required || length(identities) == 1L),
    "Use a study link with exactly one release identity.", 400L)
  if (!length(identities)) return(NULL)
  .brohn_runner_require(grepl("^[a-f0-9]{64}$", identities[[1L]]), "Study link identity is invalid.", 400L)
  identities[[1L]]
}
# Called only after the participant service's existing origin/edge validation.
# Generic code remains available to existing run recovery after recruitment
# closes. This function grants no study, media, enrollment or participant access.
brohn_runner_route <- function(store, req) {
  if (!identical(toupper(brohn_default(req$REQUEST_METHOD, "GET")), "GET")) return(NULL)
  path <- brohn_default(req$PATH_INFO, "/")
  if (path %in% c("/participant", "/participant/")) {
    token <- .brohn_runner_query_identity(brohn_default(req$QUERY_STRING, ""))
    if (is.null(token)) return(NULL)
    row <- .brohn_delivery_deployment_row(store, token = token)
    .brohn_runner_require(nrow(row) == 1L, "Study link was not found.", 404L)
    runtime <- brohn_runner_assets_read(store, row$id[[1L]])
    if (identical(runtime$status, "legacy_unpinned")) return(NULL)
    response <- .brohn_delivery_response(302L, body = raw(), type = "text/html; charset=utf-8")
    response$headers[["Location"]] <- paste0("/api/runtime/", token, "/", runtime$manifest_hash,
      "/participant/index.html?token=", token)
    return(response)
  }
  if (!startsWith(path, "/api/runtime/")) return(NULL)
  parts <- strsplit(sub("^/", "", path), "/", fixed = TRUE)[[1L]]
  .brohn_runner_require(length(parts) == 6L && grepl("^[a-f0-9]{64}$", parts[[3L]]) &&
    grepl("^[a-f0-9]{64}$", parts[[4L]]), "Participant interface asset was not found.", 404L)
  token <- parts[[3L]]; hash <- parts[[4L]]; logical_path <- paste(parts[[5L]], parts[[6L]], sep = "/")
  row <- .brohn_delivery_deployment_row(store, token = token)
  .brohn_runner_require(nrow(row) == 1L, "Participant interface asset was not found.", 404L)
  if (identical(logical_path, "participant/index.html")) {
    query_token <- .brohn_runner_query_identity(brohn_default(req$QUERY_STRING, ""), required = TRUE)
    .brohn_runner_require(identical(query_token, token), "Study link and preserved participant interface do not match.", 400L)
  }
  asset <- brohn_runner_asset(store, row$id[[1L]], hash, logical_path)
  .brohn_delivery_response(body = asset$body, type = asset$type)
}
