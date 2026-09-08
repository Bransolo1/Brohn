# Unregistered, read-only questionnaire explorer index. Authorization, job
# supervision and immutable publication belong to the calling coordinator.
.brohn_qindex_schema <- "brohn-questionnaire-index/1.0"
.brohn_qindex_recipe <- "questionnaire-explorer-index/1.0"
.brohn_qindex_collections <- c("questions", "distribution", "answers", "history", "invalidations")
.brohn_qindex_select <- paste(c("record_key", "collection", "ordinal", "source_path", "source_hash", "parent_key", "run_id", "occurrence_id", "step_id", "question_id",
  "participant_id", "session_id", "stimulus_id", "condition_id", "status", "substr(prompt,1,241) AS prompt", "summary_json", "value_kind", "value_hash",
  "substr(value_text,1,241) AS value_text"), collapse = ",")
.brohn_qindex_binding <- function(binding) {
  brohn_fields(binding, c("workspace_id", "project_id", "report_id", "report_revision", "report_hash", "origin", "analysis_sha256"), label = "Questionnaire index binding")
  brohn_require(all(vapply(binding[c("workspace_id", "project_id", "report_id", "origin")], brohn_text, logical(1), max = 128)) &&
    brohn_number(binding$report_revision, 1, 1e9, TRUE) &&
    all(vapply(binding[c("report_hash", "analysis_sha256")], .brohn_questionnaire_artifact_hash, logical(1))),
    "Questionnaire index source identities are incomplete.")
  invisible(TRUE)
}
.brohn_qindex_limits <- function(limits) {
  defaults <- list(max_rows = 1000000L, max_index_bytes = 1024^3, max_analysis_bytes = 512*1024^2, max_response_bytes = 512*1024)
  brohn_require(is.list(limits) && (!length(limits) || (!is.null(names(limits)) && !anyDuplicated(names(limits)) && all(names(limits) %in% names(defaults)))),
    "Choose named questionnaire index resource limits.")
  for (key in names(limits)) defaults[[key]] <- limits[[key]]
  maxima <- c(max_rows = 1000000, max_index_bytes = 1024^3, max_analysis_bytes = 512*1024^2, max_response_bytes = 512*1024)
  minima <- c(max_rows = 1, max_index_bytes = 16384, max_analysis_bytes = 1024, max_response_bytes = 16384)
  brohn_require(all(vapply(names(defaults), function(k) brohn_number(defaults[[k]], minima[[k]], maxima[[k]], TRUE), logical(1))), "Questionnaire index limits exceed the qualified bounded profile.")
  defaults
}
.brohn_qindex_text <- function(value, maximum = 1024L) {
  if (is.null(value)) return(NA_character_)
  brohn_require(brohn_text(value, maximum, TRUE) && validUTF8(value), "An index identity or search label is not valid bounded UTF-8 text.")
  enc2utf8(value)
}
.brohn_qindex_path <- function(...) lapply(list(...), function(part) if (is.numeric(part)) list(index = part) else list(key = part))
.brohn_qindex_kind <- function(value, present) {
  if (!present) "absent" else if (is.null(value)) "null" else if (is.character(value) && length(value) == 1L) "text" else
    if (is.logical(value) && length(value) == 1L) "boolean" else if (is.numeric(value) && length(value) == 1L) "number" else "structured"
}
.brohn_qindex_short <- function(value, limit = 240L) {
  if (is.null(value) || is.na(value)) return(NULL)
  text <- enc2utf8(value); long <- nchar(text, type = "chars") > limit
  list(text = if (long) paste0(substr(text, 1L, limit), "...") else text, truncated = long)
}

brohn_build_questionnaire_index <- function(input, output_path, limits = list()) {
  brohn_fields(input, c("schema", "binding", "report"), "artifact_path", label = "Questionnaire index input")
  brohn_require(identical(input$schema, "brohn-questionnaire-index-input/1.0"), "Unsupported questionnaire index input.")
  .brohn_qindex_binding(input$binding); limits <- .brohn_qindex_limits(limits)
  report <- input$report; binding <- input$binding
  brohn_require(is.list(report) && identical(report$id, binding$report_id) && identical(report$origin, binding$origin) &&
    identical(brohn_hash(report), binding$report_hash), "The saved report differs from the questionnaire index binding.")
  if (!is.null(report$provenance$design$project_id)) brohn_require(identical(report$provenance$design$project_id, binding$project_id), "The frozen design belongs to a different project.")
  source <- brohn_questionnaire_artifact_source(report)
  packed <- identical(report$analysis$schema, .brohn_questionnaire_preview_schema)
  artifact <- NULL
  if (packed) {
    brohn_require(brohn_text(input$artifact_path, 32768), "The complete questionnaire artifact is required for indexing.")
    candidates <- Filter(function(a) identical(a$kind, .brohn_questionnaire_artifact_kind), report$analysis$artifacts)
    brohn_require(length(candidates) == 1L, "The report must identify one complete questionnaire artifact.")
    artifact <- candidates[[1L]]
    full <- brohn_read_questionnaire_artifact(input$artifact_path, artifact, expected_source = source, max_bytes = limits$max_analysis_bytes)
    brohn_validate_questionnaire_preview(report$analysis, full, source)
  } else {
    brohn_require(is.null(input$artifact_path), "An inline questionnaire source cannot substitute an external artifact.")
    full <- report$analysis
  }
  brohn_require(identical(full$kind, "questionnaire") && identical(brohn_hash(full), binding$analysis_sha256) &&
    nchar(brohn_json(full), type = "bytes") <= limits$max_analysis_bytes, "The complete questionnaire analysis exceeds its profile or differs from the expected source.")
  brohn_require(brohn_text(output_path, 32768) && !file.exists(output_path) && dir.exists(dirname(output_path)), "Choose a new index file inside an existing owned output directory.")
  destination <- file.path(normalizePath(dirname(output_path), winslash = "/", mustWork = TRUE), basename(output_path))
  partial <- tempfile("questionnaire-index-", tmpdir = dirname(destination), fileext = ".partial.sqlite")
  con <- NULL
  on.exit({if (!is.null(con) && DBI::dbIsValid(con)) DBI::dbDisconnect(con)
    for (path in paste0(partial, c("", "-journal", "-wal", "-shm"))) if (file.exists(path)) unlink(path)
  }, add = TRUE)
  con <- DBI::dbConnect(RSQLite::SQLite(), partial, loadable.extensions = FALSE)
  DBI::dbExecute(con, "PRAGMA journal_mode=DELETE"); DBI::dbExecute(con, "PRAGMA synchronous=FULL")
  DBI::dbExecute(con, "PRAGMA cache_size=-8192"); DBI::dbExecute(con, "PRAGMA temp_store=FILE")
  DBI::dbExecute(con, "CREATE TABLE manifest (id INTEGER PRIMARY KEY CHECK(id=1), body_json TEXT NOT NULL)")
  DBI::dbExecute(con, paste("CREATE TABLE records (record_key TEXT PRIMARY KEY, collection TEXT NOT NULL, ordinal INTEGER NOT NULL,",
    "source_path TEXT NOT NULL, source_hash TEXT NOT NULL, parent_key TEXT, run_id TEXT, occurrence_id TEXT, step_id TEXT, question_id TEXT,",
    "participant_id TEXT, session_id TEXT, stimulus_id TEXT, condition_id TEXT, status TEXT, prompt TEXT, search_text TEXT NOT NULL,",
    "row_json TEXT NOT NULL, links_json TEXT NOT NULL, summary_json TEXT NOT NULL, value_kind TEXT NOT NULL, value_json TEXT, value_text TEXT, value_hash TEXT,",
    "UNIQUE(collection,ordinal))"))
  counts <- stats::setNames(as.list(rep(0L, length(.brohn_qindex_collections))), .brohn_qindex_collections)
  binding_hash <- brohn_hash(binding); total <- 0L
  columns <- c("record_key", "collection", "ordinal", "source_path", "source_hash", "parent_key", "run_id", "occurrence_id", "step_id", "question_id",
    "participant_id", "session_id", "stimulus_id", "condition_id", "status", "prompt", "search_text", "row_json", "links_json", "summary_json", "value_kind", "value_json", "value_text", "value_hash")
  insert <- paste0("INSERT INTO records (", paste(columns, collapse = ","), ") VALUES (", paste(rep("?", length(columns)), collapse = ","), ")")
  add <- function(collection, row, path, identity = row, parent = NULL, links = list(), value_present = "value" %in% names(row), value = row[["value"]]) {
    brohn_require(is.list(row) && !is.null(names(row)) && !anyDuplicated(names(row)), "An indexed source record must have named original fields.")
    total <<- total+1L; brohn_require(total <= limits$max_rows, "The complete questionnaire index exceeds its row profile; no partial index was published.")
    counts[[collection]] <<- counts[[collection]]+1L
    key <- paste0("qr-", brohn_hash(list(binding = binding_hash, source_path = path)))
    text_fields <- c("run_id", "occurrence_id", "step_id", "question_id", "participant_id", "session_id", "stimulus_id", "condition_id", "status")
    ids <- lapply(text_fields, function(k) .brohn_qindex_text(identity[[k]])); names(ids) <- text_fields
    prompt <- .brohn_qindex_text(identity[["prompt"]], 20000L)
    search <- paste(c(if (!is.na(prompt)) prompt, unlist(ids[!vapply(ids, is.na, logical(1))], use.names = FALSE)), collapse = "\n")
    kind <- .brohn_qindex_kind(value, value_present)
    value_json <- if (value_present) brohn_json(value) else NA_character_
    value_text <- if (identical(kind, "text")) enc2utf8(value) else value_json
    summary <- row[intersect(names(row), c("response_count", "answered_count", "missing_count", "numeric_response_mean", "numeric_summary_status", "count", "label", "information", "participant_linkage", "revision_count", "response_time_ms", "active_segment_response_ms", "resumed"))]
    # Long labels remain in the source row/value APIs; page summaries stay small.
    if (!is.null(summary$label)) summary$label <- .brohn_qindex_short(summary$label)
    values <- c(list(key, collection, counts[[collection]], brohn_json(path), brohn_hash(row), .brohn_qindex_text(parent)), ids,
      list(prompt, search, brohn_json(row), brohn_json(links), brohn_json(summary), kind, value_json, value_text,
        if (value_present) brohn_hash(value) else NA_character_))
    DBI::dbExecute(con, insert, params = unname(values))
    if (total %% 50L == 0L) brohn_require(as.numeric(file.info(partial)$size) <= limits$max_index_bytes, "The complete questionnaire index exceeds its disk profile; no partial index was published.")
    key
  }
  DBI::dbWithTransaction(con, {
    for (i in seq_along(full$features)) {
      feature <- full$features[[i]]; parent <- add("questions", feature, .brohn_qindex_path("features", i))
      for (j in seq_along(feature$counts)) add("distribution", feature$counts[[j]], .brohn_qindex_path("features", i, "counts", j), identity = feature, parent = parent)
    }
    revisions <- full$questionnaire_revision$runs
    if (!is.null(full$questionnaire_revision)) brohn_require(identical(full$questionnaire_revision$schema, "brohn-questionnaire-revision-results/1.0") && brohn_array(revisions), "Unsupported questionnaire revision source shape.")
    answer_map <- new.env(parent = emptyenv()); observation_keys <- character()
    if (length(revisions)) {
      run_ids <- vapply(revisions, function(r) .brohn_qindex_text(r$run_id), character(1))
      brohn_require(!anyNA(run_ids) && !anyDuplicated(run_ids), "Revision runs need distinct exact run identities.")
      for (r in seq_along(revisions)) {
        revision <- revisions[[r]]; records <- revision$effective_records; refs <- revision$history_records; events <- revision$history_events
        brohn_require(identical(revision$schema, "brohn-questionnaire-revision-projection/1.0") && brohn_array(records) && brohn_array(refs) && brohn_array(events) &&
          identical(brohn_hash(records), revision$projection_hash) && length(refs) == length(events), "Final questionnaire projection or complete history is inconsistent.")
        event_ids <- vapply(events, function(e) .brohn_qindex_text(e$id), character(1))
        brohn_require(!anyNA(event_ids) && !anyDuplicated(event_ids), "Questionnaire history has missing or duplicate source event IDs.")
        event_map <- stats::setNames(events, event_ids); ref_ids <- vapply(refs, function(e) .brohn_qindex_text(e$event_id), character(1))
        brohn_require(!anyNA(ref_ids) && !anyDuplicated(ref_ids) && setequal(ref_ids, event_ids), "Questionnaire history references do not cover its complete retained events.")
        for (i in seq_along(records)) {
          row <- records[[i]]
          brohn_require(all(vapply(row[c("occurrence_id", "step_id", "question_id", "session_id", "participant_id")], brohn_text, logical(1), max = 1024)) &&
            all(c("occurrence_id", "step_id", "question_id", "session_id", "participant_id") %in% names(row)) &&
            identical(row$session_id, revision$run_id) && identical(row$origin, binding$origin), "An effective answer is missing its exact run, occurrence or source identity.")
          composite <- brohn_hash(list(revision$run_id, row$occurrence_id, row$step_id))
          brohn_require(!exists(composite, envir = answer_map, inherits = FALSE), "Duplicate effective questionnaire assessment identity.")
          if (!is.null(row$event_id)) {
            event <- event_map[[row$event_id]]
            brohn_require(!is.null(event) && identical(event$payload$kind, "commit") && identical(event$step_id, row$step_id) &&
              identical(event$payload$occurrence_id, row$occurrence_id) && identical(brohn_hash(event$payload$value), brohn_hash(row$value)), "A final answer has no exact matching retained commit.")
          }
          identity <- row; identity$run_id <- revision$run_id
          key <- add("answers", row, .brohn_qindex_path("questionnaire_revision", "runs", r, "effective_records", i), identity)
          assign(composite, list(key = key, row = row), envir = answer_map)
          if (row$status %in% c("answered", "optional_omission") && !isTRUE(row$information)) observation_keys <- c(observation_keys, brohn_hash(row))
        }
        previous_sequence <- 0
        for (i in seq_along(refs)) {
          ref <- refs[[i]]; event <- event_map[[ref$event_id]]
          brohn_require(!is.null(event) && identical(brohn_hash(event), ref$source_event_hash) && brohn_number(ref$sequence, previous_sequence+1, integer = TRUE) &&
            event$sequence == ref$sequence && identical(event$type, "questionnaire_event") && identical(event$payload$kind, ref$kind) &&
            identical(event$step_id, ref$step_id) && identical(event$payload$occurrence_id, ref$occurrence_id), "Questionnaire history event/hash/sequence binding failed.")
          previous_sequence <- ref$sequence
          composite <- brohn_hash(list(revision$run_id, ref$occurrence_id, ref$step_id))
          answer <- if (exists(composite, envir = answer_map, inherits = FALSE)) get(composite, envir = answer_map, inherits = FALSE) else NULL
          identity <- if (is.null(answer)) list() else answer$row
          identity$run_id <- revision$run_id; identity$session_id <- revision$run_id; identity$occurrence_id <- ref$occurrence_id; identity$step_id <- ref$step_id; identity$status <- ref$kind
          event_index <- match(ref$event_id, event_ids)
          add("history", event, .brohn_qindex_path("questionnaire_revision", "runs", r, "history_events", event_index), identity,
            parent = if (is.null(answer)) NULL else answer$key,
            links = list(reference = ref, reference_path = .brohn_qindex_path("questionnaire_revision", "runs", r, "history_records", i), reference_hash = brohn_hash(ref)),
            value_present = "value" %in% names(event$payload), value = event$payload$value)
        }
        for (i in seq_along(revision$invalidations)) {
          inv <- revision$invalidations[[i]]; cause <- event_map[[inv$cause_event_id]]
          old <- if (is.null(inv$previous_head_event_id)) NULL else event_map[[inv$previous_head_event_id]]
          composite <- brohn_hash(list(revision$run_id, inv$occurrence_id, inv$step_id))
          brohn_require(exists(composite, envir = answer_map, inherits = FALSE) && !is.null(cause) && identical(cause$payload$kind, "commit") &&
            identical(cause$payload$occurrence_id, inv$occurrence_id) && (is.null(inv$previous_head_event_id) || (!is.null(old) &&
              identical(old$step_id, inv$step_id) && identical(old$payload$occurrence_id, inv$occurrence_id) && old$sequence < cause$sequence)),
            "A dependency invalidation has no exact retained cause or prior answer.")
          answer <- get(composite, envir = answer_map, inherits = FALSE); identity <- answer$row; identity$run_id <- revision$run_id; identity$status <- "dependency_invalidated"
          add("invalidations", inv, .brohn_qindex_path("questionnaire_revision", "runs", r, "invalidations", i), identity, answer$key,
            links = list(cause_event_hash = brohn_hash(cause), previous_event_hash = if (is.null(old)) NULL else brohn_hash(old)))
        }
      }
      observed <- vapply(full$observations, brohn_hash, character(1))
      brohn_require(identical(sort(observed), sort(observation_keys)), "Recorded observations do not exactly match the final revision response subset; mixed sources cannot be silently omitted.")
    } else for (i in seq_along(full$observations)) add("answers", full$observations[[i]], .brohn_qindex_path("observations", i),
      links = list(history_status = "not_retained_for_this_source"))
    manifest <- list(schema = .brohn_qindex_schema, recipe = .brohn_qindex_recipe, binding = binding, binding_hash = binding_hash,
      source = source, source_hash = brohn_hash(source), source_artifact = if (is.null(artifact)) NULL else .brohn_questionnaire_reference(artifact, limits$max_analysis_bytes),
      counts = counts, original_counts = .brohn_questionnaire_counts(full), answer_source = if (length(revisions)) "revision_effective_records" else "recorded_observations",
      limits = limits, search = "literal_case_sensitive_utf8", ordering = "original_source_ordinal", qualified = FALSE)
    DBI::dbExecute(con, "INSERT INTO manifest VALUES(1,?)", params = list(brohn_json(manifest)))
  })
  DBI::dbExecute(con, "CREATE INDEX records_page ON records(collection,ordinal)")
  DBI::dbExecute(con, "CREATE INDEX records_parent ON records(collection,parent_key,ordinal)")
  DBI::dbExecute(con, "CREATE INDEX records_identity ON records(collection,question_id,session_id,ordinal)")
  brohn_require(identical(DBI::dbGetQuery(con, "PRAGMA integrity_check")[[1L]], "ok") &&
    as.numeric(file.info(partial)$size) <= limits$max_index_bytes, "The complete questionnaire index failed integrity or disk limits; no partial index was published.")
  DBI::dbDisconnect(con); con <- NULL
  brohn_require(!file.exists(destination) && file.rename(partial, destination), "The complete index could not be moved to its new owned output path.")
  descriptor <- list(path = normalizePath(destination, winslash = "/", mustWork = TRUE), sha256 = digest::digest(file = destination, algo = "sha256"),
    bytes = as.numeric(file.info(destination)$size), schema = .brohn_qindex_schema, binding = binding, recipe = .brohn_qindex_recipe,
    counts = counts, manifest_hash = brohn_hash(manifest), media_type = "application/vnd.sqlite3")
  list(schema = "brohn-questionnaire-index-result/1.0", status = "complete", index = descriptor, parameters = limits,
    limitations = list("Derived read-only view; original questionnaire artifacts remain the scientific source.",
      "Build uses complete analysis in R memory; the coordinator must enforce process memory and time limits.",
      "No scientific score, person linkage or missing history is inferred."))
}

brohn_questionnaire_index_open <- function(path, reference, expected_binding) {
  .brohn_qindex_binding(expected_binding)
  hash <- if (!is.null(reference$sha256)) reference$sha256 else reference$hash
  bytes <- if (!is.null(reference$bytes)) reference$bytes else reference$size
  brohn_require(identical(reference$schema, .brohn_qindex_schema) && identical(reference$recipe, .brohn_qindex_recipe) &&
    identical(brohn_hash(reference$binding), brohn_hash(expected_binding)) && .brohn_questionnaire_artifact_hash(hash) && brohn_number(bytes, 1, 1024^3, TRUE) &&
    brohn_text(path, 32768) && file.exists(path) && !dir.exists(path) && file.info(path)$size == bytes &&
    identical(digest::digest(file = path, algo = "sha256"), hash), "The questionnaire index bytes or expected source binding differ.")
  brohn_require((is.null(reference$sha256) || is.null(reference$hash) || identical(reference$sha256, reference$hash)) &&
    (is.null(reference$bytes) || is.null(reference$size) || (brohn_number(reference$size, 1, 1024^3, TRUE) && reference$bytes == reference$size)), "Questionnaire index reference aliases disagree.")
  con <- DBI::dbConnect(RSQLite::SQLite(), path, flags = RSQLite::SQLITE_RO, loadable.extensions = FALSE)
  success <- FALSE; on.exit(if (!success) DBI::dbDisconnect(con), add = TRUE)
  DBI::dbExecute(con, "PRAGMA query_only=ON"); DBI::dbExecute(con, "PRAGMA trusted_schema=OFF")
  rows <- DBI::dbGetQuery(con, "SELECT body_json FROM manifest WHERE id=1")
  brohn_require(nrow(rows) == 1L, "The questionnaire index has no unique manifest.")
  manifest <- brohn_parse(rows$body_json[[1L]], 1024*1024)
  brohn_require(identical(manifest$schema, .brohn_qindex_schema) && identical(manifest$recipe, .brohn_qindex_recipe) &&
    identical(brohn_hash(manifest), reference$manifest_hash) && identical(brohn_hash(manifest$binding), brohn_hash(expected_binding)) &&
    identical(brohn_hash(manifest$counts), brohn_hash(reference$counts)), "The questionnaire index manifest differs from its immutable reference.")
  actual <- DBI::dbGetQuery(con, "SELECT collection,count(*) AS n FROM records GROUP BY collection")
  for (name in .brohn_qindex_collections) brohn_require(sum(actual$n[actual$collection == name]) == manifest$counts[[name]], "The questionnaire index record counts disagree with its manifest.")
  handle <- new.env(parent = emptyenv()); handle$con <- con; handle$path <- normalizePath(path, winslash = "/", mustWork = TRUE)
  handle$hash <- hash; handle$bytes <- bytes; handle$manifest <- manifest; handle$stamp <- file.info(handle$path)[c("size", "mtime", "ctime")]
  class(handle) <- "brohn_questionnaire_index_handle"; lockEnvironment(handle, bindings = TRUE); success <- TRUE; handle
}
brohn_questionnaire_index_close <- function(handle) {
  if (inherits(handle, "brohn_questionnaire_index_handle") && DBI::dbIsValid(handle$con)) DBI::dbDisconnect(handle$con)
  invisible(NULL)
}
.brohn_qindex_live <- function(handle) {
  brohn_require(inherits(handle, "brohn_questionnaire_index_handle") && environmentIsLocked(handle) && DBI::dbIsValid(handle$con) &&
    file.exists(handle$path) && identical(file.info(handle$path)[c("size", "mtime", "ctime")], handle$stamp),
    "The source-bound questionnaire index is closed or changed; reopen the verified immutable view.")
  invisible(TRUE)
}
.brohn_qindex_response <- function(handle, response) {
  brohn_require(nchar(brohn_json(response), type = "bytes") <= handle$manifest$limits$max_response_bytes, "This questionnaire view exceeds its response budget; choose a smaller page or read the complete value in chunks.")
  response
}
.brohn_qindex_metadata <- function(row) {
  nullable <- function(k) if (is.na(row[[k]])) NULL else row[[k]]
  fields <- c("record_key", "collection", "ordinal", "source_hash", "parent_key", "run_id", "occurrence_id", "step_id", "question_id", "participant_id", "session_id", "stimulus_id", "condition_id", "status", "value_kind", "value_hash")
  out <- lapply(fields, nullable); names(out) <- fields
  out$prompt <- .brohn_qindex_short(nullable("prompt")); out$value_preview <- .brohn_qindex_short(nullable("value_text"))
  out$summary <- brohn_parse(row$summary_json); out
}

brohn_questionnaire_index_page <- function(handle, collection, filters = list(), cursor = NULL, limit = 50L) {
  .brohn_qindex_live(handle)
  brohn_require(brohn_text(collection, 64) && collection %in% .brohn_qindex_collections && brohn_number(limit, 1, 100, TRUE), "Choose a named questionnaire collection and a page of at most100 records.")
  allowed <- c("parent_key", "run_id", "occurrence_id", "step_id", "question_id", "participant_id", "session_id", "stimulus_id", "condition_id", "status", "search")
  brohn_require(is.list(filters) && (!length(filters) || (!is.null(names(filters)) && !anyDuplicated(names(filters)) && all(names(filters) %in% allowed))) &&
    all(vapply(filters, brohn_text, logical(1), max = 1024, empty = TRUE)), "Use bounded literal questionnaire filters, not expressions or SQL.")
  filters <- brohn_canonical(filters); query_hash <- brohn_hash(list(collection = collection, filters = filters, limit = limit, ordering = handle$manifest$ordering))
  after <- 0
  if (!is.null(cursor)) {
    brohn_fields(cursor, c("schema", "index_hash", "query_hash", "after"), label = "Questionnaire page cursor")
    brohn_require(identical(cursor$schema, "brohn-questionnaire-index-cursor/1.0") && identical(cursor$index_hash, handle$hash) &&
      identical(cursor$query_hash, query_hash) && brohn_number(cursor$after, 0, handle$manifest$counts[[collection]], TRUE), "This page cursor belongs to another source or query.")
    after <- cursor$after
  }
  where <- "collection=?"; params <- list(collection)
  for (name in names(filters)) {
    where <- paste(where, if (name == "search") "AND instr(search_text,?)>0" else paste0("AND ", name, "=?"))
    params <- c(params, list(filters[[name]]))
  }
  matching <- DBI::dbGetQuery(handle$con, paste("SELECT count(*) AS n FROM records WHERE", where), params = params)$n[[1L]]
  rows <- DBI::dbGetQuery(handle$con, paste("SELECT", .brohn_qindex_select, "FROM records WHERE", where, "AND ordinal>? ORDER BY ordinal LIMIT ?"), params = c(params, list(after, as.integer(limit)+1L)))
  more <- nrow(rows) > limit; rows <- head(rows, limit)
  output <- lapply(seq_len(nrow(rows)), function(i) .brohn_qindex_metadata(as.list(rows[i, , drop = FALSE])))
  next_cursor <- if (more) list(schema = "brohn-questionnaire-index-cursor/1.0", index_hash = handle$hash, query_hash = query_hash, after = tail(rows$ordinal, 1L)) else NULL
  .brohn_qindex_response(handle, list(schema = "brohn-questionnaire-index-page/1.0", index_hash = handle$hash, binding = handle$manifest$binding,
    answer_source = handle$manifest$answer_source, collection = collection, query_hash = query_hash, source_total = handle$manifest$counts[[collection]], matching_total = matching,
    returned = length(output), after = after, next_cursor = next_cursor, rows = output))
}
.brohn_qindex_row <- function(handle, key, expected_row_hash = NULL) {
  .brohn_qindex_live(handle); brohn_require(brohn_text(key, 80) && grepl("^qr-[a-f0-9]{64}$", key), "Choose an exact questionnaire record key.")
  rows <- DBI::dbGetQuery(handle$con, paste("SELECT", .brohn_qindex_select, ",links_json,length(CAST(row_json AS BLOB)) AS record_bytes,length(row_json) AS record_characters FROM records WHERE record_key=?"), params = list(key))
  brohn_require(nrow(rows) == 1L, "This questionnaire record is absent from the selected immutable index.")
  row <- as.list(rows[1L, , drop = FALSE])
  brohn_require(is.null(expected_row_hash) || identical(expected_row_hash, row$source_hash), "The selected questionnaire record has changed or has a different source hash.")
  row
}
brohn_questionnaire_index_record <- function(handle, key, expected_row_hash) {
  brohn_require(.brohn_questionnaire_artifact_hash(expected_row_hash), "Use the exact source hash from the questionnaire page.")
  row <- .brohn_qindex_row(handle, key, expected_row_hash)
  include <- row$record_bytes <= min(128*1024, handle$manifest$limits$max_response_bytes/2)
  original <- if (include) DBI::dbGetQuery(handle$con, "SELECT row_json FROM records WHERE record_key=?", params = list(key))$row_json[[1L]] else NULL
  if (include) brohn_require(identical(brohn_hash(brohn_parse(original, 128*1024)), row$source_hash), "The indexed source row failed its canonical hash check.")
  .brohn_qindex_response(handle, list(schema = "brohn-questionnaire-index-record/1.0", index_hash = handle$hash,
    answer_source = handle$manifest$answer_source, record = .brohn_qindex_metadata(row), source_path = brohn_parse(row$source_path), links = brohn_parse(row$links_json),
    record_json = original, record_chunked = !include, record_bytes = row$record_bytes, record_characters = row$record_characters))
}
brohn_questionnaire_index_value <- function(handle, key, expected_value_hash, offset = 0L, max_bytes = 65536L, field = "value") {
  row <- .brohn_qindex_row(handle, key)
  brohn_require(field %in% c("value", "record") && brohn_number(offset, 0, integer = TRUE) && brohn_number(max_bytes, 4, 65536, TRUE), "Choose a bounded complete-value chunk.")
  hash <- if (field == "record") row$source_hash else row$value_hash
  brohn_require(!is.na(hash) && .brohn_questionnaire_artifact_hash(expected_value_hash) && identical(hash, expected_value_hash), "The selected complete value has another source hash or is absent.")
  column <- if (field == "record") "row_json" else "value_text"
  values <- DBI::dbGetQuery(handle$con, paste0("SELECT length(", column, ") AS characters,length(CAST(", column,
    " AS BLOB)) AS bytes,substr(", column, ",?,?) AS fragment FROM records WHERE record_key=?"), params = list(offset+1, max_bytes, key))
  size <- values$characters[[1L]]; brohn_require(offset <= size, "This value cursor lies beyond the complete text.")
  text <- values$fragment[[1L]]; low <- 0; high <- nchar(text, type = "chars")
  while (low < high) {
    middle <- ceiling((low+high)/2)
    if (nchar(substr(text, 1, middle), type = "bytes") <= max_bytes) low <- middle else high <- middle-1
  }
  finish <- offset+low; fragment <- if (low == 0) "" else substr(text, 1, low)
  .brohn_qindex_response(handle, list(schema = "brohn-questionnaire-index-value/1.0", index_hash = handle$hash, record_key = key,
    field = field, value_hash = hash, value_kind = if (field == "record") "canonical_record_json" else row$value_kind,
    offset = offset, next_offset = if (finish < size) finish else NULL, total_characters = size, total_utf8_bytes = values$bytes[[1L]], text = fragment))
}
