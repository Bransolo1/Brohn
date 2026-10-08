# Inactive saved1.2 completed-run analysis. No route, loader or legacy dispatch.
.brohn_vra_profile <- "saved-variant-run-analysis/0.1"
.brohn_vra_get <- function(x, name) x[[name, exact = TRUE]]
.brohn_vra_membership <- function(operation, request) {
  .brohn_ph_domain(request)
  brohn_require(identical(.brohn_vra_get(request, "analysis_profile"), .brohn_vra_profile),
    "Choose the explicit saved variant analysis profile.")
  legacy <- request; legacy$analysis_profile <- NULL
  # Only the exact new member is removed for the unchanged closed membership
  # grammar. The complete original request remains in every hash/receipt/job.
  .brohn_run_evidence_membership(operation, legacy)
}
.brohn_vra_decode <- function(bytes) {
  brohn_require(is.raw(bytes) && length(bytes) >= 1L && length(bytes) <= 16*1024^2 &&
    !any(bytes == as.raw(0)), "Original variant JSON exceeds its byte bound.")
  text <- rawToChar(bytes); Encoding(text) <- "UTF-8"
  brohn_require(validUTF8(text), "Original variant JSON is not valid UTF-8.")
  value <- jsonlite::parse_json(text, simplifyVector = FALSE, simplifyDataFrame = FALSE,
    simplifyMatrix = FALSE, bigint_as_char = FALSE)
  .brohn_vad_domain(value); .brohn_ph_domain(value); value
}
.brohn_vra_path <- function(scratch, relative, index, kind) {
  brohn_require(kind %in% c("release", "study"), "Unsupported original variant source kind.")
  expected <- sprintf("input-evidence/run-%08d.%s.json", index, kind)
  brohn_require(identical(relative, expected), "Original variant source path differs from its member.")
  root <- normalizePath(scratch, winslash = "/", mustWork = TRUE)
  brohn_require(dir.exists(root), "The independently supplied variant scratch is unavailable.")
  cursor <- root
  for (piece in strsplit(relative, "/", fixed = TRUE)[[1L]]) {
    cursor <- file.path(cursor, piece); link <- Sys.readlink(cursor)
    brohn_require(is.na(link) || !nzchar(link), "Variant source paths cannot contain symbolic links.")
  }
  path <- normalizePath(cursor, winslash = "/", mustWork = TRUE)
  expected_path <- paste0(root, "/", relative)
  lhs <- path; rhs <- expected_path
  if (.Platform$OS.type == "windows") {lhs <- tolower(lhs); rhs <- tolower(rhs)}
  brohn_require(identical(lhs, rhs) && file.exists(path) && !dir.exists(path),
    "Variant source paths cannot leave their generated location or use junction aliases.")
  path
}
.brohn_vra_write_originals <- function(saved, scratch, index) {
  brohn_require(identical(saved$schema, "brohn-original-variant-run-source/0.1"),
    "Use the named original variant source reader.")
  result <- list(schema = "brohn-variant-original-source/0.1", source = saved$source)
  for (kind in c("release", "study")) {
    bytes <- saved[[paste0(kind, "_bytes"), exact = TRUE]]
    brohn_require(is.raw(bytes) && length(bytes) >= 1L && length(bytes) <= 16*1024^2 &&
      identical(.brohn_run_evidence_hash(bytes), saved$raw_sha256[[kind, exact = TRUE]]),
      "Original variant source bytes changed before transport.")
    relative <- sprintf("input-evidence/run-%08d.%s.json", index, kind)
    destination <- file.path(scratch, relative)
    brohn_require(!file.exists(destination), "Do not replace an original variant transport file.")
    writeBin(bytes, destination)
    result[[kind]] <- list(path = relative, bytes = length(bytes), sha256 = saved$raw_sha256[[kind]])
  }
  result
}
.brohn_vra_original <- function(metadata, bodies) {
  brohn_fields(metadata, c("run_id", "deployment_id", "study_id", "origin", "allocation_index",
    "protocol_hash", "project_id", "design_revision", "design_hash", "study_body_hash",
    "protocol_bytes", "release_bytes", "study_bytes"), label = "Original variant source metadata")
  brohn_fields(bodies, c("protocol", "release", "study"), label = "Original variant source bodies")
  for (kind in names(bodies)) brohn_require(is.raw(bodies[[kind]]) &&
    brohn_number(metadata[[paste0(kind, "_bytes")]], 1, 16*1024^2, TRUE) &&
    length(bodies[[kind]]) == metadata[[paste0(kind, "_bytes")]], "Original variant byte lengths disagree.")
  hashes <- .brohn_epr_integrity(list(metadata = metadata, bodies = bodies))
  values <- lapply(bodies, .brohn_vra_decode)
  brohn_validate_saved_variant_protocol(values$protocol)
  p <- values$protocol
  brohn_require(.brohn_ph_equal(p$design, values$release) && .brohn_ph_equal(values$release, values$study),
    "The full original variant run, release and released revision differ.")
  brohn_require(identical(p$design$id, metadata$study_id) && identical(p$design$project_id, metadata$project_id) &&
    identical(p$design_hash, metadata$design_hash) && .brohn_ph_equal(p$allocation_index, metadata$allocation_index),
    "The original variant protocol differs from its study, project, release or allocation.")
  list(protocol = p, hashes = as.list(hashes))
}
.brohn_vra_read_originals <- function(item, protocol_raw, scratch, index) {
  x <- item$original
  brohn_fields(x, c("schema", "source", "release", "study"), label = "Variant original-source descriptor")
  brohn_require(identical(x$schema, "brohn-variant-original-source/0.1"), "Unsupported variant original-source descriptor.")
  bodies <- list(protocol = protocol_raw)
  for (kind in c("release", "study")) {
    d <- x[[kind]]
    brohn_fields(d, c("path", "bytes", "sha256"), label = "Original source file")
    brohn_require(brohn_number(d$bytes, 1, 16*1024^2, TRUE) && .brohn_ph_sha(d$sha256),
      "Original source file descriptor exceeds its bound.")
    path <- .brohn_vra_path(scratch, d$path, index, kind)
    brohn_require(file.info(path)$size == d$bytes, "Original source file size changed.")
    raw <- readBin(path, "raw", n = 16*1024^2 + 1L)
    brohn_require(length(raw) == d$bytes && identical(.brohn_run_evidence_hash(raw), d$sha256),
      "Original source file failed its retained raw hash.")
    bodies[[kind]] <- raw
  }
  result <- .brohn_vra_original(x$source, bodies)
  m <- item$metadata; s <- x$source
  brohn_require(identical(s$run_id, m$id) && identical(s$protocol_hash, item$protocol$sha256) &&
    .brohn_ph_equal(s[c("study_id", "deployment_id", "origin", "allocation_index", "design_revision", "design_hash")],
      m[c("study_id", "deployment_id", "origin", "allocation_index", "design_revision", "design_hash")]),
    "Original variant metadata differs from its completed-run source.")
  result
}

brohn_prepare_variant_run_evidence_input <- function(store, job, scratch) {
  .brohn_store_ready(store); .brohn_run_evidence_job(store, job)
  members <- .brohn_vra_membership(job$operation, job$request)
  scope <- .brohn_run_evidence_source_scope(store, members[[1L]])
  .brohn_vra_prepare_transport(store, job, scratch, members, scope)
}
.brohn_vra_run_binding <- function(run, input, admitted) {
  entry <- admitted[[run$id, exact = TRUE]]
  brohn_require(!is.null(entry) && .brohn_ph_equal(entry$run, run) &&
    .brohn_ph_equal(entry$events, input$events[[run$id, exact = TRUE]]) &&
    identical(run$protocol$design_hash, .brohn_ph_hash(input$design)) &&
    .brohn_ph_equal(run$protocol$design, input$design), "Keep the complete admitted run, journal and original design.")
  invisible(TRUE)
}
.brohn_vra_admit_runs <- function(input) {
  admitted <- list()
  for (i in seq_along(input$runs)) {
    run <- input$runs[[i]]; events <- input$events[[run$id, exact = TRUE]]
    p <- run$protocol; source <- input$run_evidence$runs[[i]]
    brohn_require(identical(run$id, source$metadata$id) && .brohn_ph_equal(p$design, input$design),
      "Variant analysis members have different original designs.")
    context <- if ("questionnaire_navigation" %in% names(p$design))
      brohn_variant_revision_context(p, source$protocol$sha256) else {
        brohn_validate_saved_variant_protocol(p); NULL
      }
    state <- .brohn_delivery_replay(p, events, context)
    brohn_require(isTRUE(state$run_finished) && identical(state$ending_outcome, "completed") && !isTRUE(state$withdrawn),
      "Variant automatic analysis requires the original complete non-withdrawn journal.")
    projection <- .brohn_vra_revision_values(run, events, context, state)
    admitted[run$id] <- list(list(run = run, events = events, context = context, state = state, projection = projection))
  }
  admitted
}
.brohn_vra_scale_values <- function(input, admitted) {
  prepared <- .brohn_vra_scale_responses(input, admitted)
  prepared$source$variant_source <- .brohn_vra_provenance(input)
  brohn_score_scales(prepared$responses, input$design, prepared$assessments, prepared$source)
}
.brohn_vra_provenance <- function(input) list(schema = "brohn-variant-analysis-source/0.1",
  analysis_profile = .brohn_vra_profile, source_codec = "brohn-protocol-json/0.1",
  saved_design_hash = .brohn_ph_hash(input$design), evidence_mode = input$design$evidence_mode,
  membership = .brohn_vra_membership(input$operation, input$run_evidence$request),
  runs = lapply(seq_along(input$runs), function(i) {
    run <- input$runs[[i]]; source <- input$run_evidence$runs[[i]]
    list(run_id = run$id, original_source = source$original$source,
      protocol = source$protocol[c("bytes", "sha256")], release = source$original$release[c("bytes", "sha256")],
      study = source$original$study[c("bytes", "sha256")], journal = source$journal[setdiff(names(source$journal), "path")],
      assignment = run$protocol$stimulus_assignment)
  }))
brohn_analyse_variant_input <- function(input, scratch) {
  # Public inactive entry always reads/authenticates original bytes and admits
  # the complete saved model. No hydrated-input or passed-validation alternative.
  prepared <- .brohn_vra_read_transport(input, scratch, input$operation)
  admitted <- .brohn_vra_admit_runs(prepared)
  report <- .brohn_vra_run_values(prepared, admitted)
  report$analysis_profile <- .brohn_vra_profile
  report$provenance$variant_source <- .brohn_vra_provenance(prepared)
  if (!is.null(prepared$design$analysis_plan)) {
    linked <- all(vapply(prepared$runs, function(r) isTRUE(r$participant_alias_supplied), logical(1)))
    report$analysis <- brohn_analysis_plan_result(report$analysis, prepared$design, linked,
      "plan_frozen_before_these_participant_sessions")
  }
  report
}
