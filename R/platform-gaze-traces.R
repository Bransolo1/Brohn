# Streaming retention only: the gaze recipe supplies its already computed masks.
# This module does not calculate pupil summaries or infer source blink labels.
.brohn_gaze_trace_json <- function(value) {
  # 17 significant digits preserve R binary64 values through the Python bridge.
  # The usual report serializer intentionally targets small human-readable JSON.
  if (is.null(value)) return("null")
  if (is.list(value)) {
    parts <- vapply(value, .brohn_gaze_trace_json, character(1))
    if (!is.null(names(value))) {
      brohn_require(!anyDuplicated(names(value)) && all(nzchar(names(value))), "Trace JSON needs unique named fields.")
      keys <- vapply(names(value), function(x) as.character(jsonlite::toJSON(x, auto_unbox = TRUE)), character(1))
      return(paste0("{", paste0(keys, ":", parts, collapse = ","), "}"))
    }
    return(paste0("[", paste(parts, collapse = ","), "]"))
  }
  if (length(value) != 1L) return(.brohn_gaze_trace_json(unname(as.list(value))))
  if (is.na(value)) return("null")
  if (is.numeric(value)) {
    brohn_require(is.finite(value), "Trace numeric values must be finite or explicitly missing.")
    formatted <- sprintf("%.17g", value)
    # JSON -0 is an integer token and Python's int parser loses its sign.
    if (is.double(value) && !grepl("[.eE]", formatted)) formatted <- paste0(formatted, ".0")
    return(formatted)
  }
  as.character(jsonlite::toJSON(unname(value), auto_unbox = TRUE))
}

brohn_gaze_trace_sink <- function(scratch, data, metadata) {
  brohn_require(is.data.frame(data) && nrow(data) >= 2L && nrow(data) <= 2000000L,
    "Trace source must contain 2 to 2,000,000 original rows.")
  brohn_require(dir.exists(scratch), "Create an owned trace attempt directory first.")
  brohn_require(brohn_text(metadata$pupil_column, 500) || brohn_text(metadata$blink_column, 500),
    "Complete pupil/blink traces require a mapped pupil measurement or source blink labels.")
  exchange <- file.path(scratch, "gaze-trace-exchange.ndjson")
  brohn_require(!file.exists(exchange), "A trace attempt cannot overwrite an existing exchange.")
  connection <- file(exchange, open = "wb")
  closed <- FALSE; finished <- FALSE; bytes <- 0; rows <- 0L; tables <- 0L
  abort <- function() { if (!closed) { close(connection); closed <<- TRUE }; invisible(NULL) }
  write <- function(record) {
    brohn_require(!closed, "The gaze trace exchange is already closed.")
    raw <- charToRaw(enc2utf8(paste0(.brohn_gaze_trace_json(record), "\n")))
    brohn_require(length(raw) <= 2*1024^2 && bytes + length(raw) <= 2*1024^3,
      "Complete pupil/blink trace exceeds its 2 MiB record or 2 GiB exchange limit; split the source.")
    writeBin(raw, connection); bytes <<- bytes + length(raw)
  }
  write(list(type = "header", schema = "brohn-gaze-trace-exchange/1.0", source_rows = nrow(data)))
  m <- metadata
  text_column <- function(field, indices) {
    name <- m[[field]]
    if (brohn_text(name, 500)) as.character(data[[name]][indices]) else rep(NA_character_, length(indices))
  }
  source_flag <- function(field, indices) {
    if (brohn_text(m[[field]], 500)) .brohn_gaze_boolean(text_column(field, indices), field) else rep(NA, length(indices))
  }
  boundary <- function(field, indices) {
    name <- m[[field]]
    list(column = if (brohn_text(name, 500)) name else NULL,
      source_text = if (brohn_text(name, 500)) unname(as.list(unique(as.character(data[[name]][indices])))) else list())
  }
  emit <- function(z, common, resolved) {
    brohn_require(!finished && is.data.frame(z) && nrow(z) >= 2L && tables < 10000L,
      "Gaze trace table count or source group is unsupported.")
    n <- nrow(z); original <- z$source_row
    brohn_require(all(c("exposure", "pupil_ok", "duration", "baseline_good", "baseline_weights", "baseline_window",
      "baseline_mean", "baseline_ms", "baseline_coverage", "baseline_status") %in% names(resolved)),
      "Trace sink needs the recipe's actual resolved interval and baseline support.")
    for (field in c("pupil_ok", "duration", "baseline_good", "baseline_weights"))
      brohn_require(length(resolved[[field]]) == n-1L, "Trace interval support does not match the source group.")
    table_id <- paste0("gaze_", brohn_hash(common))
    identity <- c(list(recording_id = paste0("gaze_", brohn_hash(common[c("participant_id", "session_id", "exposure_id")])),
      channel = if (brohn_text(m$pupil_column, 500)) m$pupil_column else m$blink_column), common)
    baseline <- m$pupil_baseline
    support <- list(trace_profile = "gaze-pupil-source-trace/1.0", blink_boundary_policy = "source-labelled-blink-boundaries/1.1",
      generic_line_preview = "forbidden_use_dedicated_gaze_adapter", source_rows = n, source_row_base = 1L, table_row_base = 0L,
      time_start_ms = z$time[[1L]], time_end_ms = z$time[[n]],
      initial_window = list(start_ms = z$time[[1L]], end_ms = z$time[[min(n, 5000L)]], rows = min(n, 5000L),
        scope = if (n <= 5000L) "complete_table" else "initial_saved_time_window; full table is longer"),
      source_time_unit = m$time_unit, analysis_time_unit = "ms", seconds_conversion = "saved analysis_time_ms / 1000; no added clock precision or synchronization",
      pupil_column = m$pupil_column, pupil_unit = m$pupil_unit, pupil_source = m$pupil_source,
      pupil_valid_column = m$pupil_valid_column, gaze_valid_column = m$valid_column,
      blink_column = m$blink_column, blink_source = m$blink_source,
      passive_phase = if (brohn_text(m$phase_column, 500)) m$phase_value else "passive", phase_column = m$phase_column,
      exposure_start_ms = if (is.null(resolved$exposure)) NULL else unname(resolved$exposure[[1L]]),
      exposure_end_ms = if (is.null(resolved$exposure)) NULL else unname(resolved$exposure[[2L]]),
      exposure_boundary_basis = if (is.null(resolved$exposure)) "no_passive_phase" else if (brohn_text(m$exposure_start_column, 500)) "declared_source_window" else "observed_passive_sample_span",
      exposure_start_source = boundary("exposure_start_column", original), exposure_end_source = boundary("exposure_end_column", original),
      baseline = list(declaration = baseline, start_ms = if (is.null(resolved$baseline_window)) NULL else unname(resolved$baseline_window[[1L]]),
        end_ms = if (is.null(resolved$baseline_window)) NULL else unname(resolved$baseline_window[[2L]]),
        start_source_text = if (brohn_text(baseline$start_column, 500)) unname(as.list(unique(as.character(data[[baseline$start_column]][original])))) else list(),
        end_source_text = if (brohn_text(baseline$end_column, 500)) unname(as.list(unique(as.character(data[[baseline$end_column]][original])))) else list(),
        mean = resolved$baseline_mean, valid_ms = resolved$baseline_ms, coverage = resolved$baseline_coverage,
        status = resolved$baseline_status, eligibility_meaning = "declared duration and coverage only; not physiological or artifact qualification"),
      maximum_gap_ms = m$parameters$max_gap_ms, interpolation = "none", smoothing = "none", terminal_interval = "null; no inferred tail",
      pupil_valid_samples = sum(z$pupil_valid), pupil_supported_intervals = sum(resolved$pupil_ok),
      pupil_supported_ms = sum(resolved$duration[resolved$pupil_ok]), baseline_supported_intervals = sum(resolved$baseline_good))
    write(list(type = "table", table_id = table_id, identity = identity,
      coordinates = list(axis = "time", reference = "original per-exposure source clock; analysis milliseconds converted to seconds",
        source_time_origin = NULL, source_time_unit = m$time_unit), support = support, expected_rows = n))
    # Only a bounded chunk of original text/typed fields is materialized at once.
    for (begin in seq.int(1L, n, by = 64L)) {
      at <- seq.int(begin, min(n, begin + 63L)); src <- original[at]
      flags <- list(source_gaze_valid = "valid_column", source_pupil_valid = "pupil_valid_column", source_blink = "blink_column",
        left_available = "left_valid_column", right_available = "right_valid_column")
      raw_flags <- lapply(flags, text_column, indices = src); parsed_flags <- lapply(flags, source_flag, indices = src)
      raw_time <- text_column("time_column", src); raw_pupil <- text_column("pupil_column", src)
      records <- lapply(seq_along(at), function(j) {
        i <- at[[j]]; terminal <- i == n; later <- if (terminal) NA_integer_ else i+1L
        eligible_correction <- isTRUE(z$passive[[i]]) && isTRUE(z$pupil_valid[[i]]) &&
          identical(resolved$baseline_status, "eligible") && is.finite(resolved$baseline_mean)
        in_window <- function(window) if (is.null(window)) NA else z$time[[i]] >= window[[1L]] && z$time[[i]] <= window[[2L]]
        row <- list(source_row = z$source_row[[i]], time_s = z$time[[i]]/1000, analysis_time_ms = z$time[[i]],
          source_time_text = raw_time[[j]], phase = z$phase[[i]], pupil = z$pupil[[i]], pupil_text = raw_pupil[[j]])
        for (field in names(flags)) {
          row[[field]] <- parsed_flags[[field]][[j]]
          row[[paste0(field, "_text")]] <- raw_flags[[field]][[j]]
        }
        c(row, list(pupil_finite = is.finite(z$pupil[[i]]), pupil_positive = is.finite(z$pupil[[i]]) && z$pupil[[i]] > 0,
          effective_pupil_valid = z$pupil_valid[[i]], passive = z$passive[[i]],
          baseline_member = in_window(resolved$baseline_window), exposure_member = in_window(resolved$exposure),
          following_time_ms = if (terminal) NA_real_ else z$time[[later]],
          following_duration_ms = if (terminal) NA_real_ else z$time[[later]]-z$time[[i]],
          pupil_interval_duration_ms = if (terminal) NA_real_ else if (resolved$pupil_ok[[i]]) resolved$duration[[i]] else 0,
          baseline_interval_duration_ms = if (terminal) NA_real_ else if (resolved$baseline_good[[i]]) resolved$baseline_weights[[i]] else 0,
          following_gap = if (terminal) NA else z$time[[later]]-z$time[[i]] > m$parameters$max_gap_ms,
          following_phase_change = if (terminal) NA else z$phase[[later]] != z$phase[[i]],
          following_invalid_pupil = if (terminal) NA else !(z$pupil_valid[[i]] && z$pupil_valid[[later]]),
          pupil_interval_eligible = if (terminal) NA else resolved$pupil_ok[[i]],
          baseline_interval_eligible = if (terminal) NA else resolved$baseline_good[[i]],
          pupil_minus_baseline = if (eligible_correction) z$pupil[[i]]-resolved$baseline_mean else NA_real_,
          correction_status = if (!isTRUE(z$passive[[i]])) "outside_passive_phase" else if (!isTRUE(z$pupil_valid[[i]])) "invalid_pupil_sample" else
            if (!identical(resolved$baseline_status, "eligible")) resolved$baseline_status else "arithmetic_subtraction; interval_support_is_separate"))
      })
      write(list(type = "rows", table_id = table_id, offset = begin-1L, rows = records))
    }
    write(list(type = "table_end", table_id = table_id, rows = n))
    rows <<- rows+n; tables <<- tables+1L
    invisible(table_id)
  }
  finish <- function(analysis, source_provenance) {
    force(analysis) # R promises may contain the analysis call which emits rows.
    brohn_require(!finished && rows == nrow(data) && tables > 0L, "Complete gaze trace does not reconcile with every original source row.")
    write(list(type = "complete", tables = tables, rows = rows)); abort()
    directory <- file.path(scratch, "artifacts")
    brohn_require(!file.exists(directory) || dir.exists(directory), "Artifact destination is not a directory.")
    if (!dir.exists(directory)) dir.create(directory)
    request <- file.path(scratch, "gaze-trace-request.json"); output <- file.path(scratch, "gaze-trace-result.json")
    brohn_require(!file.exists(request) && !file.exists(output), "Use a fresh gaze trace attempt.")
    payload <- list(schema = "brohn-gaze-trace-exchange/1.0", operation = "write", exchange_path = normalizePath(exchange, winslash = "/"),
      exchange_sha256 = digest::digest(file = exchange, algo = "sha256"), source_rows = rows,
      output_directory = normalizePath(directory, winslash = "/"), provenance = source_provenance)
    writeBin(charToRaw(enc2utf8(.brohn_gaze_trace_json(payload))), request)
    checked <- processx::run(brohn_python_profile("gaze"), c("scripts/workers/gaze_trace.py", "--request", request, "--output", output),
      timeout = 10*60, error_on_status = FALSE, echo = FALSE, cleanup_tree = TRUE, windows_hide_window = TRUE)
    brohn_require(file.exists(output), paste("Complete gaze trace retention failed.", substr(checked$stderr, 1, 1000)))
    result <- brohn_read_json_file(output, maximum = 2*1024^2)
    brohn_require(checked$status == 0L && identical(result$status, "complete"),
      paste("Complete gaze trace needs attention:", brohn_default(result$error$message, "artifact writer failed")))
    analysis$artifacts <- result$artifacts
    analysis$parameters$trace_profile <- "gaze-pupil-source-trace/1.0"
    analysis$quality$trace_source_rows <- rows
    analysis$quality$trace_tables <- tables
    analysis <- brohn_verify_physiology_artifacts(analysis, scratch, "gaze")
    finished <<- TRUE
    analysis
  }
  list(emit = emit, finish = finish, abort = abort)
}

brohn_gaze_blink_policy_disclosure <- function(parameters) {
  if (identical(parameters$blink_boundary_policy, "source-labelled-blink-boundaries/1.1"))
    "Source-labelled blink boundaries account for recording edges, unsupported gaps and labels continuing outside viewing. Labels do not establish exact physiological closure times."
  else "Historical blink-boundary flags did not account for labels continuing outside viewing. A false legacy flag does not establish a fully observed blink. Original saved flags are unchanged."
}

# Internal reader only. The coordinator must first resolve the exact report's
# artifact, hold source guards, and recheck current authority before publication.
brohn_gaze_trace_read <- function(artifact, scratch, table = NULL, start_ms = NULL, end_ms = NULL) {
  brohn_require(dir.exists(scratch), "Create an owned trace-reader attempt directory first.")
  operation <- if (is.null(table)) "catalog" else "preview"
  if (!is.null(table)) brohn_require(brohn_text(table$table_id, 160) && is.list(table$identity), "Choose an exact catalog table identity.")
  request <- tempfile("gaze-trace-read-", tmpdir = scratch, fileext = ".json")
  output <- tempfile("gaze-trace-read-result-", tmpdir = scratch, fileext = ".json")
  payload <- list(schema = "brohn-gaze-trace-preview/1.0", operation = operation, artifact = artifact)
  if (!is.null(table)) {
    payload$table_id <- table$table_id; payload$identity <- table$identity
    payload$start_ms <- start_ms; payload$end_ms <- end_ms
  }
  writeBin(charToRaw(enc2utf8(.brohn_gaze_trace_json(payload))), request)
  checked <- processx::run(brohn_python_profile("gaze"), c("scripts/workers/gaze_trace.py", "--request", request, "--output", output),
    timeout = 10*60, error_on_status = FALSE, echo = FALSE, cleanup_tree = TRUE, windows_hide_window = TRUE)
  brohn_require(file.exists(output), paste("Saved gaze trace could not be verified.", substr(checked$stderr, 1, 1000)))
  result <- brohn_read_json_file(output, maximum = 16*1024^2)
  brohn_require(checked$status == 0L && identical(result$schema, "brohn-gaze-trace-preview/1.0"),
    paste("Saved gaze trace needs attention:", brohn_default(result$error$message, "complete trace reader failed")))
  result
}
