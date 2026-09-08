# Completed-run input transport. Files contain original retained JSON bytes, not
# a new serialization of the participant journal. This removes the single JSON
# document limit; the existing scorer still hydrates its events into memory.
.brohn_run_evidence_hash <- function(bytes) digest::digest(bytes, algo = "sha256", serialize = FALSE)
.brohn_run_evidence_sha <- function(x) brohn_text(x, 64) && grepl("^[a-f0-9]{64}$", x)
.brohn_run_evidence_equal <- function(a, b) identical(brohn_json(a), brohn_json(b))
.brohn_run_evidence_chain <- function(previous, sequence, id, hash, bytes) brohn_hash(list(
  schema = "brohn-run-event-chain/1.0", previous = previous, sequence = sequence,
  event_id = id, sha256 = hash, bytes = bytes))
.brohn_run_evidence_seed <- function(metadata, protocol_hash) brohn_hash(list(
  schema = "brohn-run-event-chain/1.0", metadata = metadata, protocol_sha256 = protocol_hash))
.brohn_run_evidence_binding <- function(input) {
  evidence <- input$run_evidence; evidence$binding_hash <- NULL
  brohn_hash(list(schema = input$schema, operation = input$operation,
    project_id = input$project_id, run_evidence = evidence))
}
.brohn_run_evidence_path <- function(scratch, relative, index, kind) {
  expected <- sprintf("input-evidence/run-%08d.%s", index, if (kind == "protocol") "protocol.json" else "events.jsonl")
  brohn_require(identical(relative, expected), "Run evidence uses an unsupported or misdirected relative path.")
  root <- normalizePath(scratch, winslash = "/", mustWork = TRUE)
  brohn_require(dir.exists(root), "The independently supplied input scratch directory is unavailable.")
  # Check lexical ancestors as well as the resolved path: normalization alone
  # would disguise a symbolic link whose destination happens to stay in root.
  cursor <- root
  for (piece in strsplit(relative, "/", fixed = TRUE)[[1]]) {
    cursor <- file.path(cursor, piece); link <- Sys.readlink(cursor)
    brohn_require(is.na(link) || !nzchar(link), "Run evidence paths cannot contain symbolic links.")
  }
  path <- normalizePath(cursor, winslash = "/", mustWork = TRUE)
  lhs <- path; rhs <- root; expected_path <- paste0(root, "/", relative)
  if (.Platform$OS.type == "windows") {lhs <- tolower(lhs); rhs <- tolower(rhs); expected_path <- tolower(expected_path)}
  # Sys.readlink() does not expose NTFS junctions on every R build. Exact
  # resolved-versus-generated path equality also rejects in-root junctions.
  brohn_require(identical(lhs, expected_path), "Run evidence paths cannot contain symbolic links or junction aliases.")
  brohn_require(startsWith(lhs, paste0(rhs, "/")) && file.exists(path) && !dir.exists(path),
    "Run evidence leaves its independently supplied input directory.")
  path
}
.brohn_run_evidence_decode <- function(bytes, maximum) {
  brohn_require(length(bytes) > 0L && length(bytes) <= maximum && !any(bytes == as.raw(0)), "Run evidence JSON exceeds its bound or contains an invalid byte.")
  text <- rawToChar(bytes); Encoding(text) <- "UTF-8"
  brohn_require(!is.na(iconv(text, from = "UTF-8", to = "UTF-8")), "Run evidence is not valid UTF-8.")
  brohn_parse(text, maximum)
}
.brohn_run_evidence_event <- function(bytes, sequence, ids, protocol) {
  brohn_require(!any(bytes %in% as.raw(c(10L, 13L))), "Stored event JSON must occupy exactly one journal line.")
  event <- .brohn_run_evidence_decode(bytes, 4*1024^2)
  brohn_fields(event, c("sequence", "id", "type", "step_id", "stimulus_id", "condition_id", "question_id", "phase", "clock", "payload"), label = "Retained event")
  brohn_require(brohn_number(event$sequence, 1, 10000000, TRUE) && event$sequence == sequence && brohn_text(event$id, 128),
    "Retained event sequence or identity is invalid.")
  brohn_require(!exists(event$id, ids, inherits = FALSE), "Retained journal contains a duplicate event identity.")
  assign(event$id, TRUE, ids)
  brohn_require(brohn_text(event$type, 64) && event$type %in% c("step_started", "step_finished", "response", "task_event", "questionnaire_event", "visibility", "run_finished", "withdrawal") &&
    brohn_text(event$phase, 96) && is.list(event$payload) && !is.null(names(event$payload)) && is.list(event$clock), "Retained event has an invalid envelope.")
  if (!is.null(event$step_id)) {
    brohn_require(brohn_text(event$step_id, 128), "Retained event step identity is invalid.")
    step <- protocol$steps[[event$step_id]]
    brohn_require(!is.null(step) && identical(event$stimulus_id, step$stimulus_id) && identical(event$condition_id, step$condition_id) &&
      identical(event$question_id, if (identical(step$type, "question")) step$question$id else NULL), "Retained event belongs to a different protocol step.")
  } else brohn_require(is.null(event$stimulus_id) && is.null(event$condition_id) && is.null(event$question_id), "Unscoped retained event claims foreign study identities.")
  event
}
.brohn_run_evidence_protocol <- function(protocol, metadata, project_id) {
  brohn_fields(metadata, c("id", "run_id", "study_id", "deployment_id", "origin", "participant_alias", "participant_alias_supplied",
    "allocation_index", "completion_status", "transfer_status", "acked_sequence", "created_at", "updated_at", "finalized_at", "design_revision", "design_hash"), label = "Run source metadata")
  brohn_require(brohn_valid_id(metadata$id) && identical(metadata$id, metadata$run_id) && brohn_valid_id(metadata$study_id) &&
    brohn_valid_id(metadata$deployment_id) && metadata$origin %in% c("sample", "pilot", "live") &&
    brohn_text(metadata$participant_alias, 256) && is.logical(metadata$participant_alias_supplied) && length(metadata$participant_alias_supplied) == 1L && !is.na(metadata$participant_alias_supplied) &&
    brohn_number(metadata$allocation_index, 1, 1e9, TRUE) && brohn_number(metadata$acked_sequence, 1, 10000000, TRUE) &&
    brohn_number(metadata$design_revision, 1, .Machine$integer.max, TRUE) && .brohn_run_evidence_sha(metadata$design_hash) &&
    identical(metadata$completion_status, "completed") && identical(metadata$transfer_status, "saved") &&
    all(vapply(metadata[c("created_at", "updated_at", "finalized_at")], brohn_text, logical(1), max = 128)), "Run source metadata is not a completed, saved session.")
  brohn_require(is.list(protocol) && identical(protocol$schema_version, "brohn-protocol/1.0.0") && is.list(protocol$design) &&
    identical(protocol$design$id, metadata$study_id) && identical(protocol$design$project_id, project_id) &&
    identical(protocol$design_hash, metadata$design_hash) && .brohn_run_evidence_equal(protocol$allocation_index, metadata$allocation_index) && brohn_array(protocol$timeline),
    "Retained protocol does not match its frozen run, study, project or allocation.")
  # Do not recompile or demand a new encoder hash for an old stored protocol.
  # Original raw SHA is authoritative; design_hash is the original protocol ID.
  steps <- new.env(hash = TRUE, parent = emptyenv())
  for (step in protocol$timeline) {
    brohn_require(is.list(step) && brohn_text(step$id, 128) && !exists(step$id, steps, inherits = FALSE), "Retained protocol step identities are invalid.")
    assign(step$id, step, steps)
  }
  list(value = protocol, steps = steps)
}
.brohn_run_evidence_finish <- function(last, sequence, count) {
  brohn_require(sequence == count && !is.null(last) && identical(last$type, "run_finished") &&
    identical(brohn_default(last$payload$outcome, "completed"), "completed"), "Retained journal is incomplete or does not finish as completed.")
}
.brohn_run_evidence_job <- function(store, job) {
  current <- brohn_get_job(store, job$id)
  identity <- DBI::dbGetQuery(store$con, "SELECT value FROM metadata WHERE key='workspace_id'")
  brohn_require(nrow(identity) == 1L && identical(identity$value[[1]], store$workspace_id) && !is.null(current) &&
    identical(current$status, "running") && identical(current$operation, job$operation) && identical(current$worker, job$worker) &&
    identical(current$token, job$token) && .brohn_run_evidence_equal(current$attempt, job$attempt) &&
    .brohn_run_evidence_equal(current$request, job$request) && brohn_number(current$lease_until) && current$lease_until > .brohn_store_now(),
    "This run-evidence request does not hold the original workspace job lease.")
  current
}
.brohn_run_evidence_membership <- function(operation, request) {
  if (identical(operation, "analyse_run")) {
    brohn_fields(request, "run_id", c("project_id", "study_id"), "Run analysis request")
    ids <- list(request$run_id)
  } else {
    brohn_require(identical(operation, "analyse_cohort"), "This operation does not use completed-run evidence.")
    brohn_fields(request, c("deployment_id", "run_ids", "recipe"), c("project_id", "study_id"), "Cohort analysis request")
    brohn_require(brohn_valid_id(request$deployment_id) && identical(request$recipe, "typed-explicit-responses/1.0.0-draft") && brohn_array(request$run_ids), "The frozen cohort request is invalid.")
    ids <- request$run_ids
  }
  brohn_require(length(ids) > 0L && all(vapply(ids, brohn_valid_id, logical(1))) && !anyDuplicated(unlist(ids)), "Select distinct retained run identities.")
  for (field in intersect(names(request), c("project_id", "study_id"))) brohn_require(brohn_valid_id(request[[field]]), "The request's source scope is invalid.")
  ids
}
brohn_prepare_run_evidence_input <- function(store, job, scratch) {
  .brohn_store_ready(store); .brohn_run_evidence_job(store, job)
  brohn_require(!RSQLite::sqliteIsTransacting(store$con), "Prepare run evidence outside a catalog write or read transaction.")
  members <- .brohn_run_evidence_membership(job$operation, job$request)
  scratch <- .brohn_store_contained(store, scratch)
  brohn_require(dir.exists(scratch), "Create the job's owned scratch directory before preparing run evidence.")
  directory <- file.path(scratch, "input-evidence")
  brohn_require(!file.exists(directory), "This input-evidence directory has already been used.")
  brohn_require(dir.create(directory), "Could not create the owned run-evidence directory.")
  last_check <- -Inf
  progress <- function(force = FALSE) {
    now <- .brohn_store_now()
    if (force || now-last_check >= 2) {
      current <- .brohn_run_evidence_job(store, job)
      if (current$lease_until-now < 45) brohn_renew_job(store, job$id, job$worker, job$token, lease_seconds = 120)
      last_check <<- now
    }
  }
  progress(TRUE)
  columns <- paste("id,deployment_id,study_id,origin,participant_alias,participant_alias_supplied,protocol_hash,allocation_index,",
    "completion_status,transfer_status,acked_sequence,created_at,updated_at,finalized_at,length(CAST(protocol_json AS BLOB)) AS protocol_bytes")
  source_row <- function(id) DBI::dbGetQuery(store$con, paste("SELECT", columns, "FROM delivery_runs WHERE id=?"), params = list(id))
  deployment_row <- function(id) DBI::dbGetQuery(store$con, "SELECT id,study_id,project_id,origin,design_revision,design_hash FROM delivery_deployments WHERE id=?", params = list(id))
  # One short snapshot pins metadata and exact membership, without retaining any
  # large journal/protocol or holding a read transaction during lease renewal.
  heads <- DBI::dbWithTransaction(store$con, lapply(members, function(id) {
    head <- source_row(id)
    brohn_require(nrow(head) == 1L && head$protocol_bytes[[1]] <= 16*1024^2, "Run protocol is missing or exceeds its source bound.")
    list(run = head, deployment = deployment_row(head$deployment_id[[1]]))
  }))
  prepare <- function() {
    runs <- list(); project_id <- NULL; common_design <- NULL; common_origin <- NULL; common_deployment <- NULL
    for (i in seq_along(members)) {
      progress()
      row <- heads[[i]]$run
      retained <- DBI::dbGetQuery(store$con, "SELECT protocol_json FROM delivery_runs WHERE id=? AND length(CAST(protocol_json AS BLOB))<=?", params = list(members[[i]], 16*1024^2))
      brohn_require(nrow(retained) == 1L, "Retained run protocol became unavailable.")
      row$protocol_json <- retained$protocol_json
      run <- .brohn_delivery_run(row); metadata <- run[setdiff(names(run), "protocol")]
      deployment <- heads[[i]]$deployment
      brohn_require(nrow(deployment) == 1L && identical(deployment$study_id[[1]], run$study_id) && identical(deployment$origin[[1]], run$origin), "Run and original release identities disagree.")
      if (is.null(project_id)) {project_id <- deployment$project_id[[1]]; common_design <- deployment$design_hash[[1]]; common_origin <- run$origin; common_deployment <- run$deployment_id}
      brohn_require(identical(deployment$project_id[[1]], project_id) && identical(deployment$design_hash[[1]], common_design) && identical(run$origin, common_origin) && identical(run$deployment_id, common_deployment) &&
        (is.null(job$request$deployment_id) || identical(job$request$deployment_id, run$deployment_id)) &&
        (is.null(job$request$project_id) || identical(job$request$project_id, project_id)) && (is.null(job$request$study_id) || identical(job$request$study_id, run$study_id)), "The requested run is outside this frozen release, study, project or origin.")
      metadata$design_revision <- deployment$design_revision[[1]]; metadata$design_hash <- deployment$design_hash[[1]]
      protocol <- .brohn_run_evidence_protocol(run$protocol, metadata, project_id)
      protocol_bytes <- charToRaw(enc2utf8(row$protocol_json[[1]])); protocol_hash <- row$protocol_hash[[1]]
      protocol_relative <- sprintf("input-evidence/run-%08d.protocol.json", i)
      writeBin(protocol_bytes, file.path(scratch, protocol_relative))
      journal_relative <- sprintf("input-evidence/run-%08d.events.jsonl", i); journal_path <- file.path(scratch, journal_relative)
      connection <- file(journal_path, "wb")
      chain <- .brohn_run_evidence_seed(metadata, protocol_hash); ids <- new.env(hash = TRUE, parent = emptyenv()); sequence <- 0L; bytes <- 0; last <- NULL
      tryCatch({
        repeat {
          progress()
          lengths <- DBI::dbGetQuery(store$con, paste("SELECT sequence,length(CAST(event_json AS BLOB)) AS bytes FROM delivery_events",
            "WHERE run_id=? AND sequence>? ORDER BY sequence LIMIT 8"), params = list(run$id, sequence))
          if (!nrow(lengths)) break
          brohn_require(all(lengths$bytes > 0 & lengths$bytes <= 4*1024^2), "Retained event exceeds its four MiB source bound.")
          page <- DBI::dbGetQuery(store$con, paste("SELECT sequence,event_id,event_json,event_hash FROM delivery_events",
            "WHERE run_id=? AND sequence>? ORDER BY sequence LIMIT 8"), params = list(run$id, sequence))
          for (j in seq_len(nrow(page))) {
            sequence <- sequence + 1L; raw <- charToRaw(enc2utf8(page$event_json[[j]])); hash <- .brohn_run_evidence_hash(raw)
            brohn_require(page$sequence[[j]] == sequence && identical(hash, page$event_hash[[j]]), "Retained event sequence or original row hash failed verification.")
            event <- .brohn_run_evidence_event(raw, sequence, ids, protocol)
            brohn_require(identical(event$id, page$event_id[[j]]), "Retained event identity differs from its original row.")
            brohn_require(is.null(last) || !identical(last$type, "run_finished") || identical(event$type, "visibility"), "A retained completed journal contains study events after its ending.")
            writeBin(raw, connection); writeBin(as.raw(10L), connection)
            bytes <- bytes + length(raw) + 1L; chain <- .brohn_run_evidence_chain(chain, sequence, event$id, hash, length(raw))
            if (!identical(event$type, "visibility")) last <- event
          }
        }
      }, finally = close(connection))
      .brohn_run_evidence_finish(last, sequence, metadata$acked_sequence)
      # Completed metadata and received rows are immutable in normal operation.
      # An unexpected append, deletion or damaged catalog must still fail the
      # final source check rather than changing the frozen analysis membership.
      current <- DBI::dbWithTransaction(store$con, list(run = source_row(run$id), deployment = deployment_row(run$deployment_id),
        count = DBI::dbGetQuery(store$con, "SELECT count(*) AS n,max(sequence) AS last FROM delivery_events WHERE run_id=?", params = list(run$id))))
      brohn_require(identical(current$run, heads[[i]]$run) && identical(current$deployment, heads[[i]]$deployment) &&
        current$count$n[[1]] == sequence && current$count$last[[1]] == sequence, "Original run evidence changed while it was being prepared.")
      brohn_require(file.info(journal_path)$size == bytes, "Written run journal has an unexpected size.")
      runs[[i]] <- list(metadata = metadata, protocol = list(path = protocol_relative, sha256 = protocol_hash, bytes = length(protocol_bytes)),
        journal = list(path = journal_relative, sha256 = .brohn_store_hash(journal_path, file = TRUE), bytes = bytes,
          event_count = sequence, final_sequence = metadata$acked_sequence, rows_hash = chain))
    }
    input <- list(schema = "brohn-analysis-input/1.0", operation = job$operation, project_id = project_id,
      run_evidence = list(schema = "brohn-run-evidence-input/1.0", workspace_id = store$workspace_id, job_id = job$id, attempt = job$attempt,
        request = job$request, request_hash = brohn_hash(job$request), runs = runs))
    input$run_evidence$binding_hash <- .brohn_run_evidence_binding(input)
    brohn_require(nchar(brohn_json(input), type = "bytes") <= 16*1024^2, "The frozen run evidence manifest exceeds its input bound.")
    input
  }
  result <- prepare()
  progress(TRUE)
  result
}
.brohn_run_evidence_lines <- function(path, consume) {
  connection <- file(path, "rb"); on.exit(close(connection), add = TRUE); pending <- raw()
  repeat {
    chunk <- readBin(connection, "raw", n = 65536L)
    if (!length(chunk)) break
    combined <- c(pending, chunk); breaks <- which(combined == as.raw(10L)); start <- 1L
    for (end in breaks) {
      brohn_require(end > start && end-start <= 4*1024^2, "Run journal line is empty or exceeds four MiB.")
      consume(combined[seq.int(start, end-1L)]); start <- end+1L
    }
    pending <- if (start <= length(combined)) combined[seq.int(start, length(combined))] else raw()
    brohn_require(length(pending) <= 4*1024^2, "Run journal line exceeds four MiB.")
  }
  brohn_require(!length(pending), "Run journal is truncated before its final line receipt.")
  invisible(TRUE)
}
brohn_read_run_evidence_input <- function(input, scratch) {
  brohn_fields(input, c("schema", "operation", "project_id", "run_evidence"), label = "Run evidence input")
  evidence <- input$run_evidence
  brohn_fields(evidence, c("schema", "workspace_id", "job_id", "attempt", "request", "request_hash", "runs", "binding_hash"), label = "Run evidence manifest")
  brohn_require(identical(input$schema, "brohn-analysis-input/1.0") && identical(evidence$schema, "brohn-run-evidence-input/1.0") &&
    brohn_valid_id(input$project_id) && brohn_text(evidence$workspace_id, 128) && brohn_valid_id(evidence$job_id) && brohn_number(evidence$attempt, 1, .Machine$integer.max, TRUE) &&
    .brohn_run_evidence_sha(evidence$request_hash) && identical(evidence$request_hash, brohn_hash(evidence$request)) &&
    .brohn_run_evidence_sha(evidence$binding_hash) && identical(evidence$binding_hash, .brohn_run_evidence_binding(input)) && brohn_array(evidence$runs), "Run evidence manifest identity or integrity is invalid.")
  members <- .brohn_run_evidence_membership(input$operation, evidence$request)
  brohn_require(length(members) == length(evidence$runs), "Run evidence membership differs from the frozen request.")
  runs <- list(); events <- list(); common_design <- NULL; common_origin <- NULL; common_deployment <- NULL
  for (i in seq_along(evidence$runs)) {
    item <- evidence$runs[[i]]
    brohn_fields(item, c("metadata", "protocol", "journal"), label = "Run evidence source")
    brohn_fields(item$protocol, c("path", "sha256", "bytes"), label = "Protocol source")
    brohn_fields(item$journal, c("path", "sha256", "bytes", "event_count", "final_sequence", "rows_hash"), label = "Journal source")
    brohn_require(identical(item$metadata$id, members[[i]]) && .brohn_run_evidence_sha(item$protocol$sha256) &&
      brohn_number(item$protocol$bytes, 1, 16*1024^2, TRUE) && .brohn_run_evidence_sha(item$journal$sha256) && .brohn_run_evidence_sha(item$journal$rows_hash) &&
      brohn_number(item$journal$bytes, 1, 2^53-1, TRUE) && brohn_number(item$journal$event_count, 1, 10000000, TRUE) &&
      identical(item$journal$event_count, item$journal$final_sequence) && .brohn_run_evidence_equal(item$metadata$acked_sequence, item$journal$final_sequence), "Run evidence descriptor is invalid or belongs to another session.")
    protocol_path <- .brohn_run_evidence_path(scratch, item$protocol$path, i, "protocol")
    brohn_require(file.info(protocol_path)$size == item$protocol$bytes, "Run protocol size changed.")
    raw <- readBin(protocol_path, "raw", n = 16*1024^2+1L)
    brohn_require(length(raw) == item$protocol$bytes && identical(.brohn_run_evidence_hash(raw), item$protocol$sha256), "Run protocol failed its original byte hash.")
    protocol <- .brohn_run_evidence_protocol(.brohn_run_evidence_decode(raw, 16*1024^2), item$metadata, input$project_id)
    if (is.null(common_design)) {common_design <- protocol$value$design_hash; common_origin <- item$metadata$origin; common_deployment <- item$metadata$deployment_id}
    brohn_require(identical(protocol$value$design_hash, common_design) && identical(item$metadata$origin, common_origin) && identical(item$metadata$deployment_id, common_deployment) &&
      (is.null(evidence$request$deployment_id) || identical(evidence$request$deployment_id, item$metadata$deployment_id)) &&
      (is.null(evidence$request$project_id) || identical(evidence$request$project_id, input$project_id)) &&
      (is.null(evidence$request$study_id) || identical(evidence$request$study_id, item$metadata$study_id)), "Run evidence crosses the frozen cohort source boundary.")
    path <- .brohn_run_evidence_path(scratch, item$journal$path, i, "journal")
    brohn_require(file.info(path)$size == item$journal$bytes && identical(.brohn_store_hash(path, file = TRUE), item$journal$sha256), "Run journal failed its original whole-file hash.")
    chain <- .brohn_run_evidence_seed(item$metadata, item$protocol$sha256); ids <- new.env(hash = TRUE, parent = emptyenv()); sequence <- 0L; consumed <- 0; last <- NULL
    retained <- vector("list", item$journal$event_count)
    .brohn_run_evidence_lines(path, function(bytes) {
      sequence <<- sequence+1L
      brohn_require(sequence <= item$journal$event_count, "Run journal contains excess events.")
      event <- .brohn_run_evidence_event(bytes, sequence, ids, protocol)
      brohn_require(is.null(last) || !identical(last$type, "run_finished") || identical(event$type, "visibility"), "Run journal contains study events after its ending.")
      chain <<- .brohn_run_evidence_chain(chain, sequence, event$id, .brohn_run_evidence_hash(bytes), length(bytes))
      consumed <<- consumed+length(bytes)+1L; retained[[sequence]] <<- event
      if (!identical(event$type, "visibility")) last <<- event
    })
    .brohn_run_evidence_finish(last, sequence, item$journal$event_count)
    brohn_require(consumed == item$journal$bytes && identical(chain, item$journal$rows_hash), "Consumed journal bytes differ from the original retained row sequence.")
    run <- item$metadata[setdiff(names(item$metadata), c("design_revision", "design_hash"))]; run$protocol <- protocol$value
    runs[[i]] <- run; events[run$id] <- list(retained)
  }
  list(schema = input$schema, operation = input$operation, project_id = input$project_id,
    design = runs[[1]]$protocol$design, runs = runs, events = events, run_evidence = evidence)
}
