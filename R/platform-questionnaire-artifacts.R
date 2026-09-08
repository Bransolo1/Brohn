# Lossless, bounded-line questionnaire analysis storage. No catalog access.
# The preview is presentation-only; scientific readers must hydrate the artifact.
.brohn_questionnaire_artifact_schema <- "brohn-questionnaire-analysis-artifact/1.0"
.brohn_questionnaire_preview_schema <- "brohn-questionnaire-report-preview/1.0"
.brohn_questionnaire_artifact_kind <- "questionnaire-analysis"
.brohn_questionnaire_line_bytes <- 256L*1024L
.brohn_questionnaire_artifact_bytes <- 512*1024^2
.brohn_questionnaire_node_limit <- 1000000L

brohn_questionnaire_artifact_source <- function(report) {
  brohn_require(is.list(report) && !is.null(names(report)) && !anyDuplicated(names(report)) &&
    brohn_text(report[["origin"]], 64) && is.list(report[["provenance"]]),
    "Questionnaire artifacts require the saved report origin and provenance.")
  for (field in c("study_id", "dataset_id")) brohn_require(is.null(report[[field]]) || brohn_text(report[[field]], 128),
    "Questionnaire artifact source identities must be explicit strings or null.")
  list(schema = "brohn-questionnaire-artifact-source/1.0", study_id = report[["study_id"]],
    dataset_id = report[["dataset_id"]], origin = report[["origin"]], provenance_hash = brohn_hash(report[["provenance"]]))
}
.brohn_questionnaire_artifact_hash <- function(value) brohn_text(value, 64) && grepl("^[a-f0-9]{64}$", value)
.brohn_questionnaire_source_check <- function(source) {
  brohn_fields(source, c("schema", "study_id", "dataset_id", "origin", "provenance_hash"), label = "Questionnaire artifact source")
  brohn_require(identical(source$schema, "brohn-questionnaire-artifact-source/1.0") && brohn_text(source$origin, 64) &&
    .brohn_questionnaire_artifact_hash(source$provenance_hash) &&
    all(vapply(source[c("study_id", "dataset_id")], function(x) is.null(x) || brohn_text(x, 128), logical(1))),
    "Questionnaire artifact source binding is malformed.")
  invisible(TRUE)
}
.brohn_questionnaire_counts <- function(analysis) {
  revisions <- analysis[["questionnaire_revision"]][["runs"]]
  list(features = length(analysis[["features"]]), observations = length(analysis[["observations"]]),
    feature_counts = sum(vapply(analysis[["features"]], function(f) length(f[["counts"]]), integer(1))),
    revision_runs = length(revisions), revision_effective = sum(vapply(revisions, function(r) length(r[["effective_records"]]), integer(1))),
    revision_history = sum(vapply(revisions, function(r) length(r[["history_events"]]), integer(1))),
    revision_history_refs = sum(vapply(revisions, function(r) length(r[["history_records"]]), integer(1))),
    revision_invalidations = sum(vapply(revisions, function(r) length(r[["invalidations"]]), integer(1))),
    scale_observations = length(analysis[["scales"]][["observations"]]), task_scores = length(analysis[["task_scores"]]),
    choice_tasks = length(analysis[["choice_tasks"]]))
}
.brohn_questionnaire_category <- function(path) {
  keys <- vapply(Filter(function(x) "key" %in% names(x), path), function(x) x$key, character(1))
  if (!length(keys)) return("analysis")
  if (identical(keys[[1L]], "questionnaire_revision")) {
    if ("effective_records" %in% keys) return("revision_effective")
    if ("history_events" %in% keys) return("revision_history")
    if ("history_records" %in% keys) return("revision_history_refs")
    if ("invalidations" %in% keys) return("revision_invalidations")
    return("revision_metadata")
  }
  if (keys[[1L]] %in% c("observations", "features", "scales", "task_scores", "choice_tasks")) keys[[1L]] else "analysis_metadata"
}
.brohn_questionnaire_force_open <- function(path, value) {
  if (!is.list(value)) return(FALSE)
  if (!length(path)) return(TRUE)
  last <- tail(path, 1L)[[1L]]
  is.null(names(value)) || (!is.null(last$key) && last$key %in% c("questionnaire_revision", "scales"))
}
.brohn_questionnaire_reference <- function(reference, maximum) {
  brohn_require(is.list(reference) && !is.null(names(reference)) && !anyDuplicated(names(reference)), "Choose a complete questionnaire artifact reference.")
  hash <- reference[["sha256"]]; if (is.null(hash)) hash <- reference[["hash"]]
  size <- reference[["bytes"]]; if (is.null(size)) size <- reference[["size"]]
  if (!is.null(reference[["sha256"]]) && !is.null(reference[["hash"]])) brohn_require(identical(reference$sha256, reference$hash), "Artifact hash aliases disagree.")
  if (!is.null(reference[["bytes"]]) && !is.null(reference[["size"]])) brohn_require(brohn_number(reference$bytes, 1, maximum, TRUE) &&
    brohn_number(reference$size, 1, maximum, TRUE) && identical(as.numeric(reference$bytes), as.numeric(reference$size)), "Artifact size aliases disagree.")
  brohn_require(identical(reference[["kind"]], .brohn_questionnaire_artifact_kind) && identical(reference[["schema"]], .brohn_questionnaire_artifact_schema) &&
    .brohn_questionnaire_artifact_hash(hash) && brohn_number(size, 1, maximum, TRUE) &&
    brohn_number(reference[["node_count"]], 1, .brohn_questionnaire_node_limit, TRUE) &&
    .brohn_questionnaire_artifact_hash(reference[["analysis_sha256"]]) && brohn_number(reference[["analysis_bytes"]], 1, maximum, TRUE) &&
    brohn_number(reference[["line_bytes"]], .brohn_questionnaire_line_bytes, .brohn_questionnaire_line_bytes, TRUE), "Questionnaire artifact reference exceeds its supported profile or is incomplete.")
  .brohn_questionnaire_source_check(reference[["source_binding"]])
  brohn_require(identical(reference[["source_binding_sha256"]], brohn_hash(reference[["source_binding"]])), "Questionnaire source binding hash differs from its declared source.")
  counts <- reference[["counts"]]
  expected <- names(.brohn_questionnaire_counts(list()))
  brohn_fields(counts, expected, label = "Questionnaire artifact counts")
  brohn_require(all(vapply(counts, brohn_number, logical(1), min = 0, max = .brohn_questionnaire_node_limit*100, integer = TRUE)), "Questionnaire artifact counts are invalid.")
  c(reference[c("schema", "node_count", "analysis_sha256", "analysis_bytes", "source_binding", "source_binding_sha256", "counts", "line_bytes")],
    list(kind = .brohn_questionnaire_artifact_kind, sha256 = hash, bytes = as.numeric(size)))
}
.brohn_questionnaire_read_lines <- function(file, maximum_line) {
  con <- file(file, "rb"); buffer <- raw(); finished <- FALSE; closed <- FALSE
  close_reader <- function() {if (!closed) {close(con); closed <<- TRUE}; invisible(NULL)}
  next_line <- function() {
    repeat {
      newline <- which(buffer == as.raw(10L))
      if (length(newline)) {
        at <- newline[[1L]]; brohn_require(at-1L <= maximum_line && at > 1L, "Questionnaire artifact line is empty or exceeds its byte limit.")
        line <- rawToChar(buffer[seq_len(at-1L)]); Encoding(line) <- "UTF-8"
        buffer <<- if (at < length(buffer)) buffer[(at+1L):length(buffer)] else raw()
        value <- brohn_parse(line, maximum_line)
        brohn_require(identical(enc2utf8(line), enc2utf8(brohn_json(value))), "Questionnaire artifact lines must use canonical JSON with exact typed values.")
        return(value)
      }
      brohn_require(length(buffer) <= maximum_line, "Questionnaire artifact line exceeds its byte limit.")
      if (finished) {brohn_require(!length(buffer), "Questionnaire artifact has an incomplete final line."); return(NULL)}
      bytes <- readBin(con, "raw", 65536L)
      if (!length(bytes)) finished <<- TRUE else buffer <<- c(buffer, bytes)
    }
  }
  list(next_line = next_line, close = close_reader)
}

brohn_read_questionnaire_artifact <- function(file, reference, expected_source = NULL, max_bytes = .brohn_questionnaire_artifact_bytes) {
  brohn_require(brohn_number(max_bytes, 1024, .brohn_questionnaire_artifact_bytes, TRUE), "Choose a bounded questionnaire artifact read profile.")
  ref <- .brohn_questionnaire_reference(reference, max_bytes)
  brohn_require(brohn_text(file, 32768) && file.exists(file) && !dir.exists(file) &&
    as.numeric(file.info(file)$size) == ref$bytes && identical(digest::digest(file = file, algo = "sha256"), ref$sha256),
    "The complete questionnaire artifact bytes differ from their immutable reference.")
  if (!is.null(expected_source)) {
    .brohn_questionnaire_source_check(expected_source)
    brohn_require(identical(brohn_hash(expected_source), ref$source_binding_sha256), "The questionnaire artifact belongs to another saved report source.")
  }
  reader <- .brohn_questionnaire_read_lines(file, ref$line_bytes); on.exit(reader$close(), add = TRUE)
  header <- reader$next_line()
  fields <- c("schema", "record_type", "kind", "node_count", "analysis_sha256", "analysis_bytes", "source_binding", "source_binding_sha256", "counts", "line_bytes")
  brohn_fields(header, fields, label = "Questionnaire artifact header")
  brohn_require(identical(header$record_type, "header") && identical(header$kind, ref$kind) &&
    all(vapply(setdiff(fields, c("record_type", "kind")), function(field) identical(brohn_hash(header[[field]]), brohn_hash(ref[[field]])), logical(1))),
    "Questionnaire artifact header differs from its source-bound reference.")
  sequence <- 0L
  next_node <- function(path) {
    item <- reader$next_line(); sequence <<- sequence+1L
    brohn_require(!is.null(item) && sequence <= ref$node_count && is.list(item) &&
      identical(item[["record_type"]], "node") && brohn_number(item[["sequence"]], 1, ref$node_count, TRUE) && item$sequence == sequence &&
      identical(brohn_json(item[["path"]]), brohn_json(path)) && identical(item[["category"]], .brohn_questionnaire_category(path)),
      "Questionnaire artifact nodes are missing, reordered or assigned to a foreign path.")
    item
  }
  decode <- function(path = list(), depth = 0L) {
    brohn_require(depth < 64L, "Questionnaire artifact nesting exceeds the supported analysis profile.")
    item <- next_node(path); common <- c("record_type", "sequence", "path", "category", "type")
    if (identical(item$type, "value")) {
      brohn_fields(item, c(common, "value"), label = "Questionnaire value node")
      return(item[["value"]])
    }
    if (identical(item$type, "array")) {
      brohn_fields(item, c(common, "length"), label = "Questionnaire array node")
      brohn_require(brohn_number(item$length, 0, ref$node_count-sequence, TRUE), "Questionnaire artifact array length is invalid.")
      value <- vector("list", item$length)
      for (i in seq_len(item$length)) value[i] <- list(decode(c(path, list(list(index = i))), depth+1L))
      return(value)
    }
    if (identical(item$type, "object")) {
      brohn_fields(item, c(common, "keys"), label = "Questionnaire object node")
      brohn_require(brohn_array(item$keys) && length(item$keys) <= ref$node_count-sequence &&
        all(vapply(item$keys, function(key) brohn_text(key, ref$line_bytes, TRUE) && nzchar(key), logical(1))) && !anyDuplicated(unlist(item$keys, use.names = FALSE)), "Questionnaire artifact object keys are invalid.")
      keys <- as.character(unlist(item$keys, use.names = FALSE))
      brohn_require(identical(keys, sort(keys, method = "radix")), "Questionnaire object keys are not in canonical order.")
      value <- stats::setNames(vector("list", length(keys)), keys)
      for (key in keys) value[key] <- list(decode(c(path, list(list(key = key))), depth+1L))
      return(value)
    }
    if (identical(item$type, "string")) {
      brohn_fields(item, c(common, "parts", "utf8_bytes", "utf8_sha256"), label = "Questionnaire split string")
      brohn_require(brohn_number(item$parts, 1, ref$node_count-sequence, TRUE) && brohn_number(item$utf8_bytes, 1, ref$analysis_bytes, TRUE) &&
        .brohn_questionnaire_artifact_hash(item$utf8_sha256), "Questionnaire split-string dimensions are invalid.")
      pieces <- character(item$parts); observed <- 0
      for (i in seq_len(item$parts)) {
        part <- next_node(path); brohn_fields(part, c(common, "part", "text"), label = "Questionnaire string part")
        brohn_require(identical(part$type, "string_part") && brohn_number(part$part, 1, item$parts, TRUE) && part$part == i && brohn_text(part$text, ref$line_bytes, TRUE) && nchar(part$text, type = "bytes") > 0L,
          "Questionnaire string fragments are missing, empty or out of order.")
        pieces[[i]] <- part$text; observed <- observed+nchar(part$text, type = "bytes")
        brohn_require(observed <= item$utf8_bytes, "Questionnaire string exceeds its declared original byte count.")
      }
      value <- paste0(pieces, collapse = "")
      brohn_require(observed == item$utf8_bytes && identical(digest::digest(charToRaw(enc2utf8(value)), algo = "sha256", serialize = FALSE), item$utf8_sha256),
        "Questionnaire string fragments differ from the complete original text.")
      return(value)
    }
    brohn_stop("Questionnaire artifact uses an unsupported typed node.")
  }
  result <- decode()
  brohn_require(is.list(result) && !is.null(names(result)) && identical(result[["kind"]], "questionnaire"), "The complete artifact is not a questionnaire analysis.")
  brohn_require(sequence == ref$node_count && is.null(reader$next_line()), "Questionnaire artifact contains missing or trailing nodes.")
  json <- brohn_json(result)
  brohn_require(nchar(json, type = "bytes") == ref$analysis_bytes && identical(brohn_hash(result), ref$analysis_sha256) &&
    identical(brohn_hash(.brohn_questionnaire_counts(result)), brohn_hash(ref$counts)), "Questionnaire reconstruction differs from the exact original analysis or full record counts.")
  brohn_require(identical(digest::digest(file = file, algo = "sha256"), ref$sha256), "Questionnaire artifact changed while it was being read.")
  result
}

.brohn_questionnaire_display <- function(value, max_chars = 240L) {
  text <- if (is.null(value)) "null" else brohn_json(value)
  clipped <- nchar(text, type = "chars") > max_chars
  list(text = if (clipped) paste0(substr(text, 1L, max_chars), "...") else text, truncated = clipped)
}
.brohn_questionnaire_preview <- function(analysis, rows) {
  short <- function(value) {
    if (is.null(value)) return(NULL)
    if (is.character(value) && length(value) == 1L) return(if (nchar(value, type = "chars") > 240L) paste0(substr(value, 1L, 240L), "...") else value)
    .brohn_questionnaire_display(value)$text
  }
  record <- function(row) {
    display <- .brohn_questionnaire_display(row[["value"]])
    list(participant_id = short(row[["participant_id"]]), session_id = short(row[["session_id"]]),
      question_id = short(row[["question_id"]]), step_id = short(row[["step_id"]]),
      prompt = short(row[["prompt"]]), stimulus_id = short(row[["stimulus_id"]]), condition_id = short(row[["condition_id"]]),
      scope = short(row[["scope"]]), status = short(row[["status"]]), origin = short(row[["origin"]]),
      revision_count = row[["revision_count"]], value_display = display$text, value_truncated = display$truncated)
  }
  features <- lapply(head(analysis[["features"]], rows), function(feature) {
    list(question_id = short(feature[["question_id"]]), prompt = short(feature[["prompt"]]),
      condition_label = short(feature[["condition_label"]]), response_count = feature[["response_count"]],
      answered_count = feature[["answered_count"]], missing_count = feature[["missing_count"]],
      numeric_response_mean = feature[["numeric_response_mean"]], numeric_summary_status = short(feature[["numeric_summary_status"]]),
      count_rows = length(feature[["counts"]]), counts_preview = lapply(head(feature[["counts"]], 5L), function(item) {
        value <- .brohn_questionnaire_display(item[["value"]]); label <- .brohn_questionnaire_display(item[["label"]])
        list(value_display = value$text, value_truncated = value$truncated, label_display = label$text, label_truncated = label$truncated, count = item[["count"]])
      }))
  })
  effective <- list()
  for (run in analysis[["questionnaire_revision"]][["runs"]]) {
    if (length(effective) >= rows) break
    effective <- c(effective, lapply(head(run[["effective_records"]], rows-length(effective)), record))
  }
  list(rows_per_table = rows, features = features, observations = lapply(head(analysis[["observations"]], rows), record), revision_effective = effective)
}

.brohn_questionnaire_compact_analysis <- function(analysis, source, preview_rows) {
  .brohn_questionnaire_source_check(source)
  brohn_require(brohn_number(preview_rows, 0, 50, TRUE), "Choose a bounded questionnaire preview row count.")
  original <- brohn_canonical(analysis)
  brohn_require(is.list(original) && !is.null(names(original)) && identical(original[["kind"]], "questionnaire") &&
    !identical(original[["schema"]], .brohn_questionnaire_preview_schema), "A compact questionnaire preview needs the complete original analysis.")
  metadata <- list(analysis_sha256 = brohn_hash(original), analysis_bytes = nchar(brohn_json(original), type = "bytes"),
    source_binding = source, source_binding_sha256 = brohn_hash(source), counts = .brohn_questionnaire_counts(original))
  status <- original[["status"]]
  brohn_require(is.null(status) || brohn_text(status, 96), "The original questionnaire analysis status must remain an explicit bounded value.")
  summary_fields <- c("usable", "status", "response_count", "participant_count", "missing_response_count", "unlinked_session_count",
    "session_count", "source_response_count", "assessment_count")
  quality <- original[["quality"]][intersect(summary_fields, names(original[["quality"]]))]
  brohn_require(all(vapply(quality, function(value) is.null(value) || (is.logical(value) && length(value) == 1L && !is.na(value)) ||
    brohn_number(value) || brohn_text(value, 512, TRUE), logical(1))), "Questionnaire quality summaries must remain bounded scalars; full quality evidence is retained in the artifact.")
  list(schema = .brohn_questionnaire_preview_schema, kind = "questionnaire", title = original[["title"]],
    status = status, quality = quality, representation_status = "complete_analysis_in_artifact", questionnaire_artifact = metadata,
    preview = .brohn_questionnaire_preview(original, as.integer(preview_rows)), artifacts = list())
}

# Call after the artifact reader has verified its complete bytes. A valid
# artifact alone does not authorize a different scientific status, count, title
# or displayed result in the compact report that refers to it.
brohn_validate_questionnaire_preview <- function(analysis, full, expected_source) {
  brohn_require(is.list(analysis) && identical(analysis[["schema"]], .brohn_questionnaire_preview_schema) &&
    brohn_array(analysis[["artifacts"]]) && length(analysis[["artifacts"]]) == 1L,
    "The compact questionnaire report requires exactly one complete analysis artifact.")
  expected <- .brohn_questionnaire_compact_analysis(full, expected_source, analysis[["preview"]][["rows_per_table"]])
  ref <- .brohn_questionnaire_reference(analysis[["artifacts"]][[1L]], .brohn_questionnaire_artifact_bytes)
  fields <- names(expected[["questionnaire_artifact"]])
  brohn_require(identical(brohn_hash(ref[fields]), brohn_hash(expected[["questionnaire_artifact"]])),
    "The questionnaire artifact reference differs from the complete analysis or expected report source.")
  brohn_require(identical(brohn_hash(analysis[setdiff(names(analysis), "artifacts")]),
    brohn_hash(expected[setdiff(names(expected), "artifacts")])),
    "The compact questionnaire preview differs from its complete scientific analysis; preserve the source and reanalyse explicitly.")
  invisible(TRUE)
}

brohn_pack_questionnaire_report <- function(report, scratch, threshold = 4*1024^2, preview_rows = 10L) {
  brohn_require(brohn_number(threshold, 1024, 8*1024^2, TRUE) && brohn_number(preview_rows, 0, 50, TRUE), "Choose bounded questionnaire packing and preview settings.")
  envelope_size <- function(report) nchar(brohn_json(list(schema = "brohn-analysis-output/1.0", report = report)), type = "bytes")+128*1024
  analysis <- report[["analysis"]]
  if (!identical(analysis[["kind"]], "questionnaire") || identical(analysis[["schema"]], .brohn_questionnaire_preview_schema)) return(report)
  if (envelope_size(report) <= threshold) return(report)
  source <- brohn_questionnaire_artifact_source(report); .brohn_questionnaire_source_check(source)
  original <- brohn_canonical(analysis); json <- brohn_json(original); analysis_bytes <- nchar(json, type = "bytes")
  brohn_require(analysis_bytes <= .brohn_questionnaire_artifact_bytes, "The complete questionnaire analysis exceeds the explicit 512 MiB artifact profile. Preserve the source and choose a smaller cohort.")
  compact <- .brohn_questionnaire_compact_analysis(original, source, preview_rows)
  metadata <- compact[["questionnaire_artifact"]]
  packed <- report; packed$analysis <- compact
  brohn_require(envelope_size(packed)+65536 < 16*1024^2,
    "The report's provenance/design or compact preview alone exceeds the 16 MiB publication envelope. No source data was truncated; this input needs a separate provenance artifact or a smaller cohort.")
  brohn_require(brohn_text(scratch, 32768) && dir.exists(scratch), "Choose the owned worker scratch directory for questionnaire artifacts.")
  directory <- normalizePath(scratch, winslash = "/", mustWork = TRUE)
  artifact_directory <- file.path(directory, "artifacts")
  brohn_require(!file.exists(artifact_directory) || dir.exists(artifact_directory), "The worker artifacts path is not a directory.")
  brohn_require(dir.exists(artifact_directory) || dir.create(artifact_directory), "The owned questionnaire artifact directory could not be created.")
  artifact_directory <- normalizePath(artifact_directory, winslash = "/", mustWork = TRUE)
  brohn_require(identical(tolower(dirname(artifact_directory)), tolower(directory)), "Questionnaire artifact output must remain inside the owned worker scratch directory.")
  body_file <- tempfile("questionnaire-body-", tmpdir = directory, fileext = ".partial")
  final_file <- tempfile("questionnaire-analysis-", tmpdir = artifact_directory, fileext = ".jsonl")
  con <- file(body_file, "wb"); open <- TRUE; success <- FALSE
  on.exit({if (open) close(con); unlink(body_file); if (!success) unlink(final_file)}, add = TRUE)
  sequence <- 0L; body_bytes <- 0
  emit <- function(path, type, data = list()) {
    sequence <<- sequence+1L
    item <- c(list(record_type = "node", sequence = sequence, path = path, category = .brohn_questionnaire_category(path), type = type), data)
    line <- charToRaw(enc2utf8(brohn_json(item)))
    brohn_require(sequence <= .brohn_questionnaire_node_limit && length(line) <= .brohn_questionnaire_line_bytes,
      "Questionnaire artifact node exceeds its bounded record count or line length; complete source data has not been truncated.")
    body_bytes <<- body_bytes+length(line)+1L
    brohn_require(body_bytes+.brohn_questionnaire_line_bytes <= .brohn_questionnaire_artifact_bytes, "The complete typed questionnaire artifact exceeds its explicit 512 MiB profile.")
    writeBin(c(line, as.raw(10L)), con); invisible(NULL)
  }
  encode <- function(value, path = list(), depth = 0L) {
    brohn_require(depth < 64L, "Questionnaire analysis nesting exceeds the supported artifact profile.")
    candidate <- list(record_type = "node", sequence = sequence+1L, path = path, category = .brohn_questionnaire_category(path), type = "value", value = value)
    if (!.brohn_questionnaire_force_open(path, value) && nchar(brohn_json(candidate), type = "bytes") <= .brohn_questionnaire_line_bytes) {
      emit(path, "value", list(value = value)); return(invisible(NULL))
    }
    if (is.list(value)) {
      if (is.null(names(value))) {
        emit(path, "array", list(length = length(value)))
        for (i in seq_along(value)) encode(value[[i]], c(path, list(list(index = i))), depth+1L)
      } else {
        emit(path, "object", list(keys = as.list(names(value))))
        for (key in names(value)) encode(value[[key]], c(path, list(list(key = key))), depth+1L)
      }
      return(invisible(NULL))
    }
    if (is.character(value) && length(value) == 1L) {
      # Split on character boundaries, then independently verify exact UTF-8
      # bytes. Quotes, newlines and supplementary Unicode never get truncated.
      size <- nchar(value, type = "chars"); chunk <- 16384L
      starts <- seq.int(1L, size, by = chunk); pieces <- substring(value, starts, pmin(size, starts+chunk-1L))
      emit(path, "string", list(parts = length(pieces), utf8_bytes = nchar(value, type = "bytes"),
        utf8_sha256 = digest::digest(charToRaw(enc2utf8(value)), algo = "sha256", serialize = FALSE)))
      for (i in seq_along(pieces)) emit(path, "string_part", list(part = i, text = pieces[[i]]))
      return(invisible(NULL))
    }
    if ((is.numeric(value) || is.logical(value) || is.character(value)) && length(value) != 1L) {
      # Canonical JSON arrays may originate as ordinary R atomic vectors.
      emit(path, "array", list(length = length(value)))
      for (i in seq_along(value)) encode(value[[i]], c(path, list(list(index = i))), depth+1L)
      return(invisible(NULL))
    }
    brohn_stop("A questionnaire scalar or path exceeds the supported typed-line profile.")
  }
  encode(original); close(con); open <- FALSE
  header <- c(list(schema = .brohn_questionnaire_artifact_schema, record_type = "header", kind = .brohn_questionnaire_artifact_kind,
    node_count = sequence, line_bytes = .brohn_questionnaire_line_bytes), metadata)
  header_bytes <- charToRaw(enc2utf8(brohn_json(header)))
  brohn_require(length(header_bytes) <= .brohn_questionnaire_line_bytes, "Questionnaire artifact header exceeds its supported line profile.")
  con <- file(final_file, "wb"); open <- TRUE; writeBin(c(header_bytes, as.raw(10L)), con)
  body <- file(body_file, "rb"); on.exit(try(close(body), silent = TRUE), add = TRUE)
  repeat {bytes <- readBin(body, "raw", 65536L); if (!length(bytes)) break; writeBin(bytes, con)}
  close(body); close(con); open <- FALSE
  descriptor <- c(list(kind = .brohn_questionnaire_artifact_kind, path = normalizePath(final_file, winslash = "/"),
    sha256 = digest::digest(file = final_file, algo = "sha256"), bytes = as.numeric(file.info(final_file)$size),
    schema = .brohn_questionnaire_artifact_schema, node_count = sequence, line_bytes = .brohn_questionnaire_line_bytes), metadata)
  packed$analysis$artifacts <- list(descriptor)
  brohn_require(envelope_size(packed) < 16*1024^2, "The compact questionnaire report still exceeds its publication envelope; full data was not truncated.")
  success <- TRUE
  packed
}
