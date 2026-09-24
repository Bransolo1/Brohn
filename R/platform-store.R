# Local durable catalog. The caller selects the workspace root and loads the
# pinned DBI/RSQLite library. This module does not load a user profile or run jobs.
.brohn_store_error <- function(message, code = "invalid") {
  stop(structure(list(message = message, call = NULL, code = code),
    class = c(paste0("brohn_store_", code), "brohn_store_error", "error", "condition")))
}
.brohn_store_assert <- function(ok, message, code = "invalid") {
  if (!isTRUE(ok)) .brohn_store_error(message, code)
}
.brohn_store_text <- function(x, label, maximum = 256L) {
  .brohn_store_assert(is.character(x) && length(x) == 1L && !is.na(x) &&
    nzchar(x) && nchar(x, type = "bytes") <= maximum &&
    !is.na(iconv(x, from = "", to = "UTF-8")), paste(label, "must be nonempty text."))
  enc2utf8(x)
}
.brohn_store_integer <- function(x, label, minimum = 0, maximum = .Machine$integer.max) {
  .brohn_store_assert(is.numeric(x) && length(x) == 1L && is.finite(x) &&
    x == floor(x) && x >= minimum && x <= maximum, paste(label, "is out of range."))
  as.integer(x)
}
.brohn_store_now <- function() as.numeric(Sys.time())
.brohn_store_stamp <- function(now = .brohn_store_now()) {
  format(as.POSIXct(now, origin = "1970-01-01", tz = "UTC"),
    "%Y-%m-%dT%H:%M:%OS6Z", tz = "UTC", usetz = FALSE)
}
.brohn_store_id <- function(con, prefix) {
  # SQLite randomness supplies collision-resistant internal identities. These
  # identifiers are not participant access secrets or authentication tokens.
  paste0(prefix, "_", DBI::dbGetQuery(con, "SELECT lower(hex(randomblob(16))) AS id")$id[[1]])
}
.brohn_store_hash <- function(x, file = FALSE) {
  digest::digest(x, algo = "sha256", serialize = FALSE, file = file)
}

# Canonical JSON: named lists are objects with sorted keys; unnamed lists are
# arrays even at length one. Scalar values unbox; I(value) forces an array.
# JSON null is R NULL. Non-finite/NA values and unsupported R classes are rejected
# instead of silently becoming missing data. Large clock integers stay strings.
.brohn_store_json <- function(body, maximum = 16 * 1024 * 1024) {
  # These are the same primitive formatters used by the pinned jsonlite 2.0.0
  # toJSON methods. Resolve once per document, avoiding full option/S4 dispatch
  # for every key and scalar. The frozen-original regression pins exact bytes.
  escape <- get("deparse_vector", asNamespace("jsonlite"), inherits = FALSE)
  number <- get("num_to_char", asNamespace("jsonlite"), inherits = FALSE)
  encode <- function(x, depth = 0L) {
    .brohn_store_assert(depth <= 64L, "JSON nesting exceeds 64 levels.")
    if (is.null(x)) return("null")
    if (is.list(x) && !is.object(x)) {
      n <- names(x)
      if (!is.null(n)) {
        .brohn_store_assert(!anyNA(n) && all(nzchar(n)) && !anyDuplicated(n),
          "JSON object keys must be nonempty and unique.")
        order <- order(enc2utf8(n), method = "radix")
        if (length(n)) {
          .brohn_store_assert(depth + 1L <= 64L, "JSON nesting exceeds 64 levels.")
          .brohn_store_assert(!anyNA(iconv(enc2utf8(n), from = "", to = "UTF-8")),
            "JSON text must be valid UTF-8.")
        }
        entries <- if (length(n)) paste0(escape(enc2utf8(n[order])), ":",
          vapply(x[order], encode, character(1), depth = depth + 1L)) else character()
        return(paste0("{", paste(entries, collapse = ","), "}"))
      }
      return(paste0("[", paste(vapply(x, encode, character(1), depth = depth + 1L),
        collapse = ","), "]"))
    }
    force_array <- inherits(x, "AsIs")
    if (force_array) x <- unclass(x)
    .brohn_store_assert(!is.object(x) && is.null(dim(x)) && is.null(names(x)) &&
      (is.character(x) || is.logical(x) || is.numeric(x)), "Unsupported JSON value; use plain lists and scalars.")
    .brohn_store_assert(!anyNA(x) && (!is.numeric(x) || all(is.finite(x))),
      "JSON values cannot contain NA or non-finite numbers; use explicit NULL.")
    if (is.character(x)) .brohn_store_assert(!anyNA(iconv(x, from = "", to = "UTF-8")),
      "JSON text must be valid UTF-8.")
    if (length(x) != 1L || force_array) {
      return(paste0("[", paste(vapply(as.list(x), encode, character(1), depth = depth + 1L),
        collapse = ","), "]"))
    }
    # Match the protocol/report encoder's binary64 precision. jsonlite's NA
    # setting rounds to about fifteen significant digits in this pinned build.
    if (is.character(x)) escape(enc2utf8(x)) else if (is.logical(x)) {
      if (x) "true" else "false"
    } else number(x, digits = 17, na_as_string = TRUE, use_signif = FALSE, always_decimal = FALSE)
  }
  value <- encode(body)
  .brohn_store_assert(nchar(value, type = "bytes") <= maximum,
    "JSON payload exceeds the catalog limit; store bulk data as objects.", "too_large")
  value
}
.brohn_store_decode <- function(text, hash = NULL) {
  if (!is.null(hash)) .brohn_store_assert(identical(.brohn_store_hash(charToRaw(text)), hash),
    "Stored JSON failed its integrity check.", "corrupt")
  jsonlite::fromJSON(text, simplifyVector = FALSE)
}
.brohn_store_ready <- function(store) {
  .brohn_store_assert(is.list(store) && inherits(store$con, "DBIConnection") &&
    DBI::dbIsValid(store$con) && dir.exists(store$root), "Workspace is not open.", "closed")
  if (!is.null(store$hosted_profile)) brohn_hosted_require_session(store)
  invisible(TRUE)
}
.brohn_store_execution_paused <- function(store) {
  value <- DBI::dbGetQuery(store$con, "SELECT value FROM metadata WHERE key='execution_paused'")
  nrow(value) == 1L && identical(value$value[[1]], "1")
}
.brohn_store_transaction_statement <- function(store, sql) {
  # RSQLite currently supplies simpleError without a native error code. Limit
  # this translation to our own transaction-control statement at the DBI call
  # boundary. Callback/domain errors, even with the same text, are untouched.
  tryCatch(DBI::dbExecute(store$con, sql), error = function(e) {
    if (inherits(store$con, "SQLiteConnection") && inherits(e, "simpleError") &&
        conditionMessage(e) %in% c("database is locked", "database table is locked"))
      .brohn_store_error("The workspace is temporarily busy saving another request. Retry the same operation shortly.", "busy")
    stop(e)
  })
}
.brohn_store_tx <- function(store, fn) {
  .brohn_store_ready(store)
  nested <- RSQLite::sqliteIsTransacting(store$con)
  savepoint <- if (nested) .brohn_store_id(store$con, "batch") else NULL
  .brohn_store_transaction_statement(store, if (nested) paste("SAVEPOINT", savepoint) else "BEGIN IMMEDIATE")
  committed <- FALSE
  on.exit(if (!committed) {
    if (nested) {
      try(DBI::dbExecute(store$con, paste("ROLLBACK TO SAVEPOINT", savepoint)), silent = TRUE)
      try(DBI::dbExecute(store$con, paste("RELEASE SAVEPOINT", savepoint)), silent = TRUE)
    } else try(DBI::dbExecute(store$con, "ROLLBACK"), silent = TRUE)
  }, add = TRUE)
  result <- fn()
  .brohn_store_transaction_statement(store, if (nested) paste("RELEASE SAVEPOINT", savepoint) else "COMMIT")
  committed <- TRUE
  result
}
brohn_store_batch <- function(store, fn) {
  .brohn_store_assert(is.function(fn), "A batch requires a zero-argument function.")
  .brohn_store_tx(store, fn)
}
.brohn_store_audit <- function(store, action, target, detail = list()) {
  if (!is.null(store$hosted_context)) detail$actor <- brohn_hosted_actor(store)
  DBI::dbExecute(store$con,
    "INSERT INTO audit_log (occurred_at, action, target, detail_json) VALUES (?, ?, ?, ?)",
    params = list(.brohn_store_stamp(), action, target, .brohn_store_json(detail)))
  invisible(NULL)
}

brohn_open_store <- function(root) {
  root <- .brohn_store_text(root, "Workspace root", 4096L)
  for (package in c("DBI", "RSQLite", "jsonlite", "digest")) {
    .brohn_store_assert(requireNamespace(package, quietly = TRUE),
      paste("Required storage dependency is unavailable:", package), "dependency")
  }
  if (!dir.exists(root)) .brohn_store_assert(dir.create(root, recursive = TRUE), "Cannot create workspace root.")
  root <- normalizePath(root, winslash = "/", mustWork = TRUE)
  object_root <- file.path(root, "objects", "sha256")
  if (!dir.exists(object_root)) .brohn_store_assert(dir.create(object_root, recursive = TRUE), "Cannot create object store.")
  con <- DBI::dbConnect(RSQLite::SQLite(), file.path(root, "catalog.sqlite"), loadable.extensions = FALSE)
  opened <- FALSE
  on.exit(if (!opened) DBI::dbDisconnect(con), add = TRUE)
  DBI::dbExecute(con, "PRAGMA busy_timeout=5000")
  DBI::dbExecute(con, "PRAGMA trusted_schema=OFF")
  DBI::dbExecute(con, "PRAGMA foreign_keys=ON")
  mode <- DBI::dbGetQuery(con, "PRAGMA journal_mode=WAL")[[1]][[1]]
  .brohn_store_assert(identical(tolower(mode), "wal"), "Workspace filesystem does not support SQLite WAL.")
  DBI::dbExecute(con, "PRAGMA synchronous=FULL")
  version <- DBI::dbGetQuery(con, "PRAGMA user_version")[[1]][[1]]
  .brohn_store_assert(version %in% c(0L, 1L), "Unsupported workspace schema version.", "schema")
  store <- list(root = root, con = con, workspace_id = NULL)
  .brohn_store_tx(store, function() {
    # Recheck under the write lock: another process may have initialized it.
    version <- DBI::dbGetQuery(con, "PRAGMA user_version")[[1]][[1]]
    if (version == 0L) {
      statements <- c(
        "CREATE TABLE metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL)",
        "CREATE TABLE entities (kind TEXT NOT NULL, id TEXT NOT NULL, project_id TEXT NOT NULL, revision INTEGER NOT NULL CHECK(revision > 0), created_at TEXT NOT NULL, updated_at TEXT NOT NULL, PRIMARY KEY(kind,id))",
        "CREATE TABLE entity_versions (kind TEXT NOT NULL, id TEXT NOT NULL, revision INTEGER NOT NULL CHECK(revision > 0), project_id TEXT NOT NULL, body_json TEXT NOT NULL, body_hash TEXT NOT NULL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL, PRIMARY KEY(kind,id,revision), FOREIGN KEY(kind,id) REFERENCES entities(kind,id))",
        "CREATE TABLE entity_operations (operation_id TEXT PRIMARY KEY, request_hash TEXT NOT NULL, kind TEXT NOT NULL, id TEXT NOT NULL, revision INTEGER NOT NULL, FOREIGN KEY(kind,id,revision) REFERENCES entity_versions(kind,id,revision))",
        "CREATE INDEX entities_project ON entities(kind,project_id,updated_at)",
        "CREATE TABLE objects (hash TEXT PRIMARY KEY, size REAL NOT NULL CHECK(size >= 0), media_type TEXT NOT NULL, created_at TEXT NOT NULL)",
        "CREATE TABLE jobs (id TEXT PRIMARY KEY, operation TEXT NOT NULL, request_json TEXT NOT NULL, request_hash TEXT NOT NULL, idempotency_key TEXT NOT NULL UNIQUE, status TEXT NOT NULL CHECK(status IN ('queued','running','succeeded','failed','cancelled')), attempt INTEGER NOT NULL DEFAULT 0, worker TEXT, token TEXT, lease_until REAL, result_json TEXT, error_json TEXT, created_at TEXT NOT NULL, updated_at TEXT NOT NULL)",
        "CREATE INDEX jobs_claim ON jobs(status,lease_until,created_at)",
        "CREATE TABLE audit_log (sequence INTEGER PRIMARY KEY AUTOINCREMENT, occurred_at TEXT NOT NULL, action TEXT NOT NULL, target TEXT NOT NULL, detail_json TEXT NOT NULL)",
        "CREATE TRIGGER versions_no_update BEFORE UPDATE ON entity_versions BEGIN SELECT RAISE(ABORT,'Entity revisions are immutable'); END",
        "CREATE TRIGGER versions_no_delete BEFORE DELETE ON entity_versions BEGIN SELECT RAISE(ABORT,'Entity revisions are immutable'); END",
        "CREATE TRIGGER operations_no_update BEFORE UPDATE ON entity_operations BEGIN SELECT RAISE(ABORT,'Idempotency records are immutable'); END",
        "CREATE TRIGGER operations_no_delete BEFORE DELETE ON entity_operations BEGIN SELECT RAISE(ABORT,'Idempotency records are immutable'); END",
        "CREATE TRIGGER objects_no_update BEFORE UPDATE ON objects BEGIN SELECT RAISE(ABORT,'Object metadata is immutable'); END",
        "CREATE TRIGGER objects_no_delete BEFORE DELETE ON objects BEGIN SELECT RAISE(ABORT,'Object metadata is immutable'); END",
        "CREATE TRIGGER audit_no_update BEFORE UPDATE ON audit_log BEGIN SELECT RAISE(ABORT,'Audit entries are immutable'); END",
        "CREATE TRIGGER audit_no_delete BEFORE DELETE ON audit_log BEGIN SELECT RAISE(ABORT,'Audit entries are immutable'); END"
      )
      for (sql in statements) DBI::dbExecute(con, sql)
      DBI::dbExecute(con, "INSERT INTO metadata (key,value) VALUES ('workspace_id',?)",
        params = list(.brohn_store_id(con, "workspace")))
      DBI::dbExecute(con, "PRAGMA user_version=1")
      .brohn_store_audit(store, "workspace.created", "workspace")
    } else .brohn_store_assert(version == 1L, "Unsupported workspace schema version.", "schema")
    invisible(NULL)
  })
  identity <- DBI::dbGetQuery(con, "SELECT value FROM metadata WHERE key='workspace_id'")
  .brohn_store_assert(nrow(identity) == 1L, "Workspace identity is missing.", "corrupt")
  store$workspace_id <- identity$value[[1]]
  opened <- TRUE
  store
}

brohn_close_store <- function(store) {
  if (is.list(store) && inherits(store$con, "DBIConnection") && DBI::dbIsValid(store$con))
    DBI::dbDisconnect(store$con)
  invisible(NULL)
}
.brohn_store_entity <- function(row) {
  if (!nrow(row)) return(NULL)
  list(id = row$id[[1]], kind = row$kind[[1]], project_id = row$project_id[[1]],
    revision = as.integer(row$revision[[1]]),
    body = .brohn_store_decode(row$body_json[[1]], row$body_hash[[1]]),
    created_at = row$created_at[[1]], updated_at = row$updated_at[[1]])
}
brohn_get_entity <- function(store, kind, id, revision = NULL) {
  .brohn_store_ready(store)
  kind <- .brohn_store_text(kind, "Entity kind")
  id <- .brohn_store_text(id, "Entity identity")
  if (is.null(revision)) {
    row <- DBI::dbGetQuery(store$con, paste(
      "SELECT v.* FROM entity_versions v JOIN entities e ON",
      "v.kind=e.kind AND v.id=e.id AND v.revision=e.revision WHERE e.kind=? AND e.id=?"),
      params = list(kind, id))
  } else {
    revision <- .brohn_store_integer(revision, "Revision", 1L)
    row <- DBI::dbGetQuery(store$con, "SELECT * FROM entity_versions WHERE kind=? AND id=? AND revision=?",
      params = list(kind, id, revision))
  }
  if (nrow(row) && !is.null(store$hosted_profile)) brohn_hosted_require_project(store, row$project_id[[1L]])
  .brohn_store_entity(row)
}
# Fixed-column, parameterized JSON selection. Filter values and JSON paths never
# become SQL syntax; callers can select an old parent or active state before the
# bounded result window without reading every stored scientific result.
.brohn_store_filters <- function(filters, column = "v.body_json") {
  .brohn_store_assert(column %in% c("v.body_json", "request_json"), "Invalid catalog filter column.")
  .brohn_store_assert(is.list(filters) && length(filters) <= 16L &&
    (!length(filters) || (!is.null(names(filters)) && !anyDuplicated(names(filters)) &&
      all(grepl("^[a-z][a-z0-9_]*(\\.[a-z][a-z0-9_]*)*$", names(filters))))), "Invalid catalog filters.")
  sql <- ""; params <- list()
  for (field in names(filters)) {
    values <- filters[[field]]
    .brohn_store_assert((is.character(values) || is.numeric(values) || is.logical(values)) &&
      length(values) >= 1L && length(values) <= 32L && !anyNA(values) &&
      (!is.numeric(values) || all(is.finite(values))), "Catalog filters need finite scalar values or a bounded selection.")
    type <- if (is.character(values)) "text" else if (is.logical(values)) "boolean" else "number"
    type_sql <- switch(type, text = "json_type(%s,?)='text'", boolean = "json_type(%s,?) IN ('true','false')", number = "json_type(%s,?) IN ('integer','real')")
    sql <- paste0(sql, " AND ", sprintf(type_sql, column), " AND json_extract(", column, ",?) IN (", paste(rep("?", length(values)), collapse = ","), ")")
    params <- c(params, list(paste0("$.", field), paste0("$.", field)), as.list(if (is.logical(values)) as.integer(values) else values))
  }
  list(sql = sql, params = params)
}
brohn_list_entities <- function(store, kind, project_id = NULL, limit = 500, filters = list(), offset = 0L) {
  .brohn_store_ready(store)
  if (!is.null(store$hosted_profile)) {
    if (is.null(project_id)) project_id <- store$hosted_profile$project_id
    brohn_hosted_require_project(store, project_id)
  }
  kind <- .brohn_store_text(kind, "Entity kind")
  limit <- .brohn_store_integer(limit, "Result limit", 1L, 10000L)
  offset <- .brohn_store_integer(offset, "Result offset", 0L, 100000000L)
  query <- paste("SELECT v.* FROM entity_versions v JOIN entities e ON",
    "v.kind=e.kind AND v.id=e.id AND v.revision=e.revision WHERE e.kind=?")
  params <- list(kind)
  if (!is.null(project_id)) {
    query <- paste(query, "AND e.project_id=?")
    params <- c(params, list(.brohn_store_text(project_id, "Project identity")))
  }
  selected <- .brohn_store_filters(filters)
  query <- paste0(query, selected$sql, " ORDER BY e.updated_at DESC, e.id ASC LIMIT ? OFFSET ?")
  rows <- DBI::dbGetQuery(store$con, query, params = c(params, selected$params, list(limit, offset)))
  lapply(seq_len(nrow(rows)), function(i) .brohn_store_entity(rows[i, , drop = FALSE]))
}
brohn_entity_history <- function(store, kind, id) {
  .brohn_store_ready(store)
  rows <- DBI::dbGetQuery(store$con,
    "SELECT * FROM entity_versions WHERE kind=? AND id=? ORDER BY revision DESC",
    params = list(.brohn_store_text(kind, "Entity kind"), .brohn_store_text(id, "Entity identity")))
  if (!is.null(store$hosted_profile)) for (project in unique(rows$project_id)) brohn_hosted_require_project(store, project)
  lapply(seq_len(nrow(rows)), function(i) .brohn_store_entity(rows[i, , drop = FALSE]))
}
brohn_put_entity <- function(store, kind, id, body, expected_revision = 0L,
                             project_id = "default", operation_id = NULL) {
  .brohn_store_ready(store)
  if (!is.null(store$hosted_profile)) brohn_hosted_require_project(store, project_id)
  kind <- .brohn_store_text(kind, "Entity kind")
  id <- .brohn_store_text(id, "Entity identity")
  project_id <- .brohn_store_text(project_id, "Project identity")
  expected_revision <- .brohn_store_integer(expected_revision, "Expected revision", 0L, .Machine$integer.max - 1L)
  if (!is.null(operation_id)) operation_id <- .brohn_store_text(operation_id, "Operation identity", 512L)
  # Legacy replay can expand decimal spellings without creating a new row.
  # Bound that comparison separately; every new revision still has the same
  # sixteen-MiB catalog limit. Eight covers scalar 15-to-17-digit expansion.
  json_limit <- 16*1024*1024
  json <- .brohn_store_json(body,maximum=if(is.null(operation_id))json_limit else 8*json_limit)
  hash <- .brohn_store_hash(charToRaw(json))
  request_hash <- .brohn_store_hash(charToRaw(.brohn_store_json(list(kind = kind, id = id,
    project_id = project_id, expected_revision = expected_revision, body_hash = hash))))
  .brohn_store_tx(store, function() {
    if (!is.null(operation_id)) {
      old <- DBI::dbGetQuery(store$con, "SELECT * FROM entity_operations WHERE operation_id=?",
        params = list(operation_id))
      if (nrow(old)) {
        prior <- DBI::dbGetQuery(store$con,"SELECT body_json,body_hash,project_id FROM entity_versions WHERE kind=? AND id=? AND revision=?",
          params=list(old$kind[[1]],old$id[[1]],old$revision[[1]]))
        .brohn_store_assert(identical(old$kind[[1]],kind) && identical(old$id[[1]],id) &&
          identical(as.integer(old$revision[[1]]),expected_revision+1L) && nrow(prior)==1L && identical(prior$project_id[[1]],project_id),
          "Operation identity already belongs to another record, project or revision.","idempotency_conflict")
        same_request <- identical(old$request_hash[[1]], request_hash)
        if (!same_request) {
          # Older revisions keep their original JSON and hash. A replay of the
          # exact values that old record actually retained can use that hash;
          # new or previously rounded-away numeric values cannot alias it.
          if (nrow(prior)==1L && nchar(prior$body_json[[1]],type="bytes")<=json_limit &&
              identical(.brohn_store_json(.brohn_store_decode(prior$body_json[[1]],prior$body_hash[[1]]),maximum=8*json_limit),json)) {
            preserved_request <- .brohn_store_hash(charToRaw(.brohn_store_json(list(kind=kind,id=id,
              project_id=project_id,expected_revision=expected_revision,body_hash=prior$body_hash[[1]]))))
            same_request <- identical(old$request_hash[[1]],preserved_request)
          }
        }
        .brohn_store_assert(same_request,
          "Operation identity was already used with a different request.", "idempotency_conflict")
        return(brohn_get_entity(store, old$kind[[1]], old$id[[1]], old$revision[[1]]))
      }
    }
    .brohn_store_assert(nchar(json,type="bytes")<=json_limit,"JSON payload exceeds the catalog limit; store bulk data as objects.","too_large")
    head <- DBI::dbGetQuery(store$con, "SELECT * FROM entities WHERE kind=? AND id=?", params = list(kind, id))
    if (nrow(head) && !is.null(store$hosted_profile)) brohn_hosted_require_project(store, head$project_id[[1L]])
    current <- if (nrow(head)) head$revision[[1]] else 0L
    .brohn_store_assert(current == expected_revision,
      "This record changed since it was opened. Reload it before saving.", "revision_conflict")
    revision <- current + 1L
    stamp <- .brohn_store_stamp()
    created <- if (nrow(head)) head$created_at[[1]] else stamp
    if (!nrow(head)) {
      DBI::dbExecute(store$con, "INSERT INTO entities (kind,id,project_id,revision,created_at,updated_at) VALUES (?,?,?,?,?,?)",
        params = list(kind, id, project_id, revision, created, stamp))
    } else {
      count <- DBI::dbExecute(store$con, "UPDATE entities SET project_id=?,revision=?,updated_at=? WHERE kind=? AND id=? AND revision=?",
        params = list(project_id, revision, stamp, kind, id, current))
      .brohn_store_assert(count == 1L, "Concurrent revision update was rejected.", "revision_conflict")
    }
    DBI::dbExecute(store$con, paste("INSERT INTO entity_versions",
      "(kind,id,revision,project_id,body_json,body_hash,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?)"),
      params = list(kind, id, revision, project_id, json, hash, created, stamp))
    if (!is.null(operation_id)) DBI::dbExecute(store$con,
      "INSERT INTO entity_operations (operation_id,request_hash,kind,id,revision) VALUES (?,?,?,?,?)",
      params = list(operation_id, request_hash, kind, id, revision))
    .brohn_store_audit(store, "entity.saved", paste(kind, id, sep = "/"),
      list(revision = revision, body_hash = hash, project_id = project_id))
    brohn_get_entity(store, kind, id, revision)
  })
}

.brohn_store_contained <- function(store, path, must_work = TRUE) {
  canonical <- normalizePath(path, winslash = "/", mustWork = must_work)
  root <- store$root
  lhs <- canonical
  if (.Platform$OS.type == "windows") { lhs <- tolower(lhs); root <- tolower(root) }
  .brohn_store_assert(startsWith(lhs, paste0(root, "/")), "Object path leaves this workspace.", "path")
  relative <- substring(canonical, nchar(store$root) + 2L)
  cursor <- store$root
  for (piece in strsplit(relative, "/", fixed = TRUE)[[1]]) {
    cursor <- file.path(cursor, piece)
    link <- Sys.readlink(cursor)
    .brohn_store_assert(is.na(link) || !nzchar(link), "Object paths cannot contain symbolic links.", "path")
  }
  canonical
}
.brohn_store_object_row <- function(store, hash) {
  DBI::dbGetQuery(store$con, "SELECT * FROM objects WHERE hash=?", params = list(hash))
}
brohn_object_path <- function(store, hash, verify = TRUE) {
  .brohn_store_ready(store)
  .brohn_store_assert(is.character(hash) && length(hash) == 1L && !is.na(hash) &&
    grepl("^[a-f0-9]{64}$", hash), "A lowercase SHA-256 object hash is required.", "path")
  .brohn_store_assert(is.logical(verify) && length(verify) == 1L && !is.na(verify), "verify must be TRUE or FALSE.")
  row <- .brohn_store_object_row(store, hash)
  .brohn_store_assert(nrow(row) == 1L, "Object is not registered in this workspace.", "not_found")
  path <- file.path(store$root, "objects", "sha256", substr(hash, 1L, 2L), hash)
  .brohn_store_assert(file.exists(path) && !dir.exists(path), "Stored object is missing.", "corrupt")
  path <- .brohn_store_contained(store, path)
  .brohn_store_assert(identical(as.numeric(file.info(path)$size), as.numeric(row$size[[1]])),
    "Stored object size changed.", "corrupt")
  if (verify) .brohn_store_assert(identical(.brohn_store_hash(path, file = TRUE), hash),
    "Stored object failed its SHA-256 integrity check.", "corrupt")
  path
}
brohn_store_object <- function(store, path = NULL, bytes = NULL, media_type = "application/octet-stream") {
  .brohn_store_ready(store)
  .brohn_store_assert(xor(is.null(path), is.null(bytes)), "Supply exactly one source: path or bytes.")
  media_type <- .brohn_store_text(media_type, "Media type", 256L)
  if (!is.null(path)) {
    path <- .brohn_store_text(path, "Source path", 4096L)
    .brohn_store_assert(file.exists(path) && !dir.exists(path), "Source object was not found.", "not_found")
  } else .brohn_store_assert(is.raw(bytes) && length(bytes) <= 64 * 1024 * 1024,
    "Inline object bytes must be raw and no larger than 64 MiB; use a file path for larger objects.")
  staging_root <- .brohn_store_contained(store, file.path(store$root, "objects", "sha256"))
  temporary <- tempfile(".pending-", tmpdir = staging_root)
  on.exit(unlink(temporary), add = TRUE)
  if (!is.null(path)) .brohn_store_assert(file.copy(path, temporary, overwrite = FALSE), "Cannot stage source object.")
  else writeBin(bytes, temporary)
  hash <- .brohn_store_hash(temporary, file = TRUE)
  size <- as.numeric(file.info(temporary)$size)
  .brohn_store_tx(store, function() {
    row <- .brohn_store_object_row(store, hash)
    if (nrow(row)) {
      brohn_object_path(store, hash)
      return(list(hash = hash, size = row$size[[1]], media_type = row$media_type[[1]]))
    }
    directory <- file.path(staging_root, substr(hash, 1L, 2L))
    if (!dir.exists(directory)) .brohn_store_assert(dir.create(directory), "Cannot create object directory.")
    directory <- .brohn_store_contained(store, directory)
    destination <- file.path(directory, hash)
    # A prior interrupted transaction may have published these exact bytes before
    # committing metadata. Reconcile that orphan without overwriting any file.
    if (file.exists(destination)) {
      destination <- .brohn_store_contained(store, destination)
      .brohn_store_assert(!dir.exists(destination) && identical(.brohn_store_hash(destination, file = TRUE), hash),
        "Existing object bytes do not match their content address.", "corrupt")
    } else .brohn_store_assert(file.rename(temporary, destination), "Cannot publish immutable object.")
    Sys.chmod(destination, mode = "0444")
    DBI::dbExecute(store$con, "INSERT INTO objects (hash,size,media_type,created_at) VALUES (?,?,?,?)",
      params = list(hash, size, media_type, .brohn_store_stamp()))
    .brohn_store_audit(store, "object.stored", hash, list(size = size, media_type = media_type))
    list(hash = hash, size = size, media_type = media_type)
  })
}

.brohn_store_job <- function(row) {
  if (!nrow(row)) return(NULL)
  optional <- function(name) if (is.na(row[[name]][[1]])) NULL else row[[name]][[1]]
  result <- optional("result_json")
  error <- optional("error_json")
  list(id = row$id[[1]], operation = row$operation[[1]],
    request = .brohn_store_decode(row$request_json[[1]], row$request_hash[[1]]),
    idempotency_key = row$idempotency_key[[1]], status = row$status[[1]],
    attempt = as.integer(row$attempt[[1]]), worker = optional("worker"), token = optional("token"),
    lease_until = optional("lease_until"), result = if (is.null(result)) NULL else .brohn_store_decode(result),
    error = if (is.null(error)) NULL else .brohn_store_decode(error),
    created_at = row$created_at[[1]], updated_at = row$updated_at[[1]])
}
brohn_get_job <- function(store, id) {
  .brohn_store_ready(store)
  .brohn_store_job(DBI::dbGetQuery(store$con, "SELECT * FROM jobs WHERE id=?",
    params = list(.brohn_store_text(id, "Job identity"))))
}
brohn_list_jobs <- function(store, limit = 100, request_filters = list(), operation = NULL, status = NULL, offset = 0L) {
  .brohn_store_ready(store)
  limit <- .brohn_store_integer(limit, "Result limit", 1L, 10000L)
  offset <- .brohn_store_integer(offset, "Result offset", 0L, 100000000L)
  selected <- .brohn_store_filters(request_filters, "request_json")
  sql <- paste0("SELECT * FROM jobs WHERE 1=1", selected$sql); params <- selected$params
  for (field in c("operation", "status")) {
    values <- if (field == "operation") operation else status
    if (is.null(values)) next
    .brohn_store_assert(is.character(values) && length(values) >= 1L && length(values) <= 32L && !anyNA(values) && all(nzchar(values)), "Invalid job selection.")
    sql <- paste0(sql, " AND ", field, " IN (", paste(rep("?", length(values)), collapse = ","), ")")
    params <- c(params, as.list(values))
  }
  rows <- DBI::dbGetQuery(store$con, paste0(sql, " ORDER BY created_at DESC,id ASC LIMIT ? OFFSET ?"), params = c(params, list(limit, offset)))
  lapply(seq_len(nrow(rows)), function(i) .brohn_store_job(rows[i, , drop = FALSE]))
}
brohn_enqueue_job <- function(store, operation, request, idempotency_key, prepared_id = NULL) {
  .brohn_store_ready(store)
  if (!is.null(store$hosted_profile) && identical(operation, "backup_workspace")) brohn_hosted_require_action(store, "backup")
  operation <- .brohn_store_text(operation, "Job operation")
  idempotency_key <- .brohn_store_text(idempotency_key, "Idempotency key", 512L)
  if(!is.null(prepared_id)) {
    prepared_id <- .brohn_store_text(prepared_id, "Prepared job identity", 36L)
    .brohn_store_assert(grepl("^job_[a-f0-9]{32}$",prepared_id),"Prepared job identity must use the internal job UUID format.")
  }
  json_limit <- 4*1024*1024
  json <- .brohn_store_json(request, maximum = 8*json_limit)
  hash <- .brohn_store_hash(charToRaw(json))
  .brohn_store_tx(store, function() {
    old <- DBI::dbGetQuery(store$con, "SELECT * FROM jobs WHERE idempotency_key=?", params = list(idempotency_key))
    if (nrow(old)) {
      .brohn_store_assert(nchar(old$request_json[[1]],type="bytes")<=json_limit,"Stored job request exceeds its catalog limit.","corrupt")
      retained_request <- .brohn_store_decode(old$request_json[[1]],old$request_hash[[1]])
      .brohn_store_assert(identical(old$operation[[1]], operation) &&
        (identical(old$request_hash[[1]], hash) || identical(.brohn_store_json(retained_request,maximum=8*json_limit),json)),
        "Job idempotency key was already used with a different request.", "idempotency_conflict")
      return(.brohn_store_job(old))
    }
    .brohn_store_assert(nchar(json,type="bytes")<=json_limit,"JSON payload exceeds the catalog limit; store bulk data as objects.","too_large")
    id <- if(is.null(prepared_id)) .brohn_store_id(store$con, "job") else prepared_id
    .brohn_store_assert(!nrow(DBI::dbGetQuery(store$con,"SELECT id FROM jobs WHERE id=?",params=list(id))),
      "Prepared job identity already belongs to another operation.","conflict")
    stamp <- .brohn_store_stamp()
    DBI::dbExecute(store$con, paste("INSERT INTO jobs",
      "(id,operation,request_json,request_hash,idempotency_key,status,created_at,updated_at) VALUES (?,?,?,?,?,'queued',?,?)"),
      params = list(id, operation, json, hash, idempotency_key, stamp, stamp))
    .brohn_store_audit(store, "job.queued", id, list(operation = operation, request_hash = hash))
    brohn_get_job(store, id)
  })
}
brohn_claim_job <- function(store, worker, lease_seconds = 60) {
  worker <- .brohn_store_text(worker, "Worker identity")
  .brohn_store_assert(is.numeric(lease_seconds) && length(lease_seconds) == 1L &&
    is.finite(lease_seconds) && lease_seconds > 0 && lease_seconds <= 86400, "Lease duration must be in (0, 86400] seconds.")
  .brohn_store_tx(store, function() {
    if (.brohn_store_execution_paused(store)) return(NULL)
    now <- .brohn_store_now()
    rows <- DBI::dbGetQuery(store$con, paste("SELECT * FROM jobs WHERE operation NOT IN ('acquisition_preserve','acquisition_prepare') AND (status='queued' OR",
      "(status='running' AND lease_until<=?)) ORDER BY created_at ASC,id ASC LIMIT 1"), params = list(now))
    if (!nrow(rows)) return(NULL)
    attempt <- .brohn_store_integer(rows$attempt[[1]] + 1L, "Job attempt", 1L)
    token <- as.character(attempt)
    id <- rows$id[[1]]
    DBI::dbExecute(store$con, paste("UPDATE jobs SET status='running',attempt=?,worker=?,token=?,lease_until=?,updated_at=?",
      "WHERE id=?"), params = list(attempt, worker, token, now + lease_seconds, .brohn_store_stamp(now), id))
    .brohn_store_audit(store, "job.claimed", id, list(attempt = attempt, worker = worker, reclaimed = rows$status[[1]] == "running"))
    brohn_get_job(store, id)
  })
}
brohn_renew_job <- function(store, id, worker, token, lease_seconds = 60) {
  id <- .brohn_store_text(id, "Job identity")
  worker <- .brohn_store_text(worker, "Worker identity")
  token <- .brohn_store_text(token, "Fencing token")
  .brohn_store_assert(is.numeric(lease_seconds) && length(lease_seconds) == 1L &&
    is.finite(lease_seconds) && lease_seconds > 0 && lease_seconds <= 86400,
    "Lease duration must be in (0, 86400] seconds.")
  .brohn_store_tx(store, function() {
    job <- brohn_get_job(store, id)
    .brohn_store_assert(!is.null(job), "Job was not found.", "not_found")
    now <- .brohn_store_now()
    .brohn_store_assert(identical(job$status, "running") && identical(job$worker, worker) &&
      identical(job$token, token) && !is.null(job$lease_until) && job$lease_until > now,
      "This attempt no longer holds a valid lease and cannot renew it.", "stale_attempt")
    lease_until <- max(job$lease_until, now + lease_seconds)
    DBI::dbExecute(store$con, "UPDATE jobs SET lease_until=?,updated_at=? WHERE id=?",
      params = list(lease_until, .brohn_store_stamp(now), id))
    .brohn_store_audit(store, "job.renewed", id, list(attempt = job$attempt, worker = worker, lease_until = lease_until))
    brohn_get_job(store, id)
  })
}
.brohn_store_finish_job <- function(store, id, worker, token, payload, status) {
  id <- .brohn_store_text(id, "Job identity")
  worker <- .brohn_store_text(worker, "Worker identity")
  token <- .brohn_store_text(token, "Fencing token")
  json <- .brohn_store_json(payload, maximum = 4 * 1024 * 1024)
  .brohn_store_tx(store, function() {
    job <- brohn_get_job(store, id)
    .brohn_store_assert(!is.null(job), "Job was not found.", "not_found")
    .brohn_store_assert(identical(job$status, "running") && identical(job$worker, worker) &&
      identical(job$token, token) && !is.null(job$lease_until) && job$lease_until > .brohn_store_now(),
      "This job attempt no longer holds a valid lease; its output was not published.", "stale_attempt")
    column <- if (identical(status, "succeeded")) "result_json" else "error_json"
    # The column is selected only from the two literals above, never user SQL.
    DBI::dbExecute(store$con, paste0("UPDATE jobs SET status=?,", column,
      "=?,lease_until=NULL,updated_at=? WHERE id=?"), params = list(status, json, .brohn_store_stamp(), id))
    .brohn_store_audit(store, paste0("job.", status), id, list(attempt = job$attempt, worker = worker))
    brohn_get_job(store, id)
  })
}
brohn_complete_job <- function(store, id, worker, token, result) {
  .brohn_store_finish_job(store, id, worker, token, result, "succeeded")
}
brohn_fail_job <- function(store, id, worker, token, error) {
  .brohn_store_finish_job(store, id, worker, token, error, "failed")
}
brohn_cancel_job <- function(store, id) {
  id <- .brohn_store_text(id, "Job identity")
  .brohn_store_tx(store, function() {
    job <- brohn_get_job(store, id)
    .brohn_store_assert(!is.null(job), "Job was not found.", "not_found")
    if (identical(job$status, "cancelled")) return(job)
    .brohn_store_assert(job$status %in% c("queued", "running"), "A finished job cannot be cancelled.", "state")
    DBI::dbExecute(store$con, "UPDATE jobs SET status='cancelled',lease_until=NULL,updated_at=? WHERE id=?",
      params = list(.brohn_store_stamp(), id))
    .brohn_store_audit(store, "job.cancelled", id, list(attempt = job$attempt))
    brohn_get_job(store, id)
  })
}
