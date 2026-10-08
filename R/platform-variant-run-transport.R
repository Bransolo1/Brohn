# Inactive1.2 parent transport. Original functions remain unchanged.
.brohn_vra_prepare_transport <- function(store, job, scratch, members, scope) {
  .brohn_store_ready(store); .brohn_run_evidence_job(store, job)
  brohn_require(job$operation %in% c("analyse_run","analyse_cohort") && identical(job$request$analysis_profile, .brohn_vra_profile), "This operation does not use completed-run evidence.")
  .brohn_run_evidence_transport_members(members); .brohn_run_evidence_scope(scope)
  brohn_require(!RSQLite::sqliteIsTransacting(store$con), "Prepare run evidence outside a catalog write or read transaction.")
  scratch <- .brohn_store_contained(store, scratch)
  brohn_require(dir.exists(scratch), "Create the job's owned scratch directory before preparing run evidence.")
  directory <- file.path(scratch, "input-evidence")
  brohn_require(!file.exists(directory), "This input-evidence directory has already been used.")
  brohn_require(dir.create(directory), "Could not create the owned run-evidence directory.")
  handles <- list()
  on.exit(for (handle in handles) handle$close(), add = TRUE)
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
    runs <- list(); project_id <- scope$project_id
    for (i in seq_along(members)) {
      progress()
      row <- heads[[i]]$run
      retained <- DBI::dbGetQuery(store$con, "SELECT protocol_json FROM delivery_runs WHERE id=? AND length(CAST(protocol_json AS BLOB))<=?", params = list(members[[i]], 16*1024^2))
      brohn_require(nrow(retained) == 1L, "Retained run protocol became unavailable.")
      row$protocol_json <- retained$protocol_json
      run <- .brohn_delivery_run(row); metadata <- run[setdiff(names(run), "protocol")]
      deployment <- heads[[i]]$deployment
      brohn_require(nrow(deployment) == 1L && identical(deployment$study_id[[1]], run$study_id) && identical(deployment$origin[[1]], run$origin), "Run and original release identities disagree.")
      brohn_require(identical(deployment$project_id[[1]], project_id) && identical(deployment$design_hash[[1]], scope$design_hash) &&
        identical(run$origin, scope$origin) && identical(run$deployment_id, scope$deployment_id) && identical(run$study_id,scope$study_id) &&
        (is.null(job$request$deployment_id) || identical(job$request$deployment_id, run$deployment_id)) &&
        (is.null(job$request$project_id) || identical(job$request$project_id, project_id)) && (is.null(job$request$study_id) || identical(job$request$study_id, run$study_id)), "The requested run is outside this frozen release, study, project or origin.")
      metadata$design_revision <- deployment$design_revision[[1]]; metadata$design_hash <- deployment$design_hash[[1]]
      handle <- brohn_open_variant_run_protocol(store, run$id, run$study_id, project_id)
      handles[[i]] <<- handle
      saved <- handle$read()
      brohn_require(.brohn_ph_equal(run$protocol, saved$protocol), "Original source differs from its complete saved reader.")
      protocol <- .brohn_vra_protocol_index(saved$protocol, metadata, project_id)
      protocol_bytes <- charToRaw(enc2utf8(row$protocol_json[[1]])); protocol_hash <- row$protocol_hash[[1]]
      brohn_require(identical(protocol_bytes, saved$protocol_bytes) && identical(protocol_hash, saved$raw_sha256$protocol),
        "Original protocol bytes changed before transport.")
      originals <- .brohn_vra_write_originals(saved, scratch, i)
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
      handle$current()
      runs[[i]] <- list(metadata = metadata, original = originals, protocol = list(path = protocol_relative, sha256 = protocol_hash, bytes = length(protocol_bytes)),
        journal = list(path = journal_relative, sha256 = .brohn_store_hash(journal_path, file = TRUE), bytes = bytes,
          event_count = sequence, final_sequence = metadata$acked_sequence, rows_hash = chain))
    }
    input <- list(schema = "brohn-analysis-input/1.0", operation = job$operation, project_id = project_id,
      run_evidence = list(schema = "brohn-variant-run-evidence-input/0.1", workspace_id = store$workspace_id, job_id = job$id, attempt = job$attempt,
        request = job$request, request_hash = brohn_hash(job$request), runs = runs))
    input$run_evidence$binding_hash <- .brohn_run_evidence_binding(input)
    brohn_require(nchar(brohn_json(input), type = "bytes") <= 16*1024^2, "The frozen run evidence manifest exceeds its input bound.")
    input
  }
  result <- prepare()
  progress(TRUE)
  for (handle in handles) handle$current()
  result
}

