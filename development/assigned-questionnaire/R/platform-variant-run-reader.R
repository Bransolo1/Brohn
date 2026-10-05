# Private complete original-byte reader for the literal saved1.2 profile.
.brohn_vra_read_transport <- function(input, scratch, expected_operation) {
  brohn_fields(input, c("schema", "operation", "project_id", "run_evidence"), label = "Run evidence input")
  brohn_require(brohn_text(expected_operation,64) && expected_operation %in% c("analyse_run","analyse_cohort") &&
    identical(input$operation,expected_operation), "Run evidence operation differs from its explicit caller.")
  evidence <- input$run_evidence
  brohn_fields(evidence, c("schema", "workspace_id", "job_id", "attempt", "request", "request_hash", "runs", "binding_hash"), label = "Run evidence manifest")
  brohn_require(identical(input$schema, "brohn-analysis-input/1.0") && identical(evidence$schema, "brohn-variant-run-evidence-input/0.1") &&
    brohn_valid_id(input$project_id) && brohn_text(evidence$workspace_id, 128) && brohn_valid_id(evidence$job_id) && brohn_number(evidence$attempt, 1, .Machine$integer.max, TRUE) &&
    .brohn_run_evidence_sha(evidence$request_hash) && identical(evidence$request_hash, brohn_hash(evidence$request)) &&
    .brohn_run_evidence_sha(evidence$binding_hash) && identical(evidence$binding_hash, .brohn_run_evidence_binding(input)) && brohn_array(evidence$runs), "Run evidence manifest identity or integrity is invalid.")
  members <- .brohn_vra_membership(input$operation, evidence$request)
  brohn_require(identical(members, lapply(evidence$runs, function(item) item$metadata$id)), "Variant membership differs from its frozen request.")
  .brohn_run_evidence_transport_members(members)
  runs <- list(); events <- list(); common_design <- NULL; common_origin <- NULL; common_deployment <- NULL; common_study <- NULL
  for (i in seq_along(evidence$runs)) {
    item <- evidence$runs[[i]]
    brohn_fields(item, c("metadata", "original", "protocol", "journal"), label = "Run evidence source")
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
    original <- .brohn_vra_read_originals(item, raw, scratch, i)
    protocol <- .brohn_vra_protocol_index(original$protocol, item$metadata, input$project_id)
    if (is.null(common_design)) {common_design <- protocol$value$design_hash; common_origin <- item$metadata$origin; common_deployment <- item$metadata$deployment_id; common_study <- item$metadata$study_id}
    brohn_require(identical(protocol$value$design_hash, common_design) && identical(item$metadata$origin, common_origin) && identical(item$metadata$deployment_id, common_deployment) &&
      identical(item$metadata$study_id,common_study) &&
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

