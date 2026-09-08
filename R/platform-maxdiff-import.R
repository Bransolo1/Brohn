# Original CSV/TSV adapter. The coordinator verifies the immutable source bytes
# before supplying character-preserved rows; this module never guesses a design.
.brohn_maxdiff_import_columns <- function() c("participant_column", "session_column", "exposure_column", "design_hash_column", "set_column",
  "item_order_column", "presented_column", "status_column", "best_column", "worst_column", "missing_reason_column", "participant_linkage_column")
.brohn_maxdiff_import_mapping <- function(metadata, columns) {
  required <- .brohn_maxdiff_import_columns()
  brohn_fields(metadata, c("exercise_id", "origin_statement", required), c("exercise_column", "origin_column"), "Best-worst import mapping")
  brohn_require(brohn_valid_id(metadata$exercise_id) && brohn_text(metadata$origin_statement, 4000), "Select the saved best-worst exercise and describe the original collection source.")
  brohn_require(is.character(columns) && length(columns) > 0L && length(columns) <= 1024L && !anyNA(columns) && !anyDuplicated(columns) && all(nzchar(columns)), "Best-worst source columns must have distinct nonempty names.")
  mapped <- character()
  for (field in c(required, "exercise_column", "origin_column")) {
    value <- metadata[[field]]
    if (!field %in% required && (is.null(value) || identical(value, ""))) next
    brohn_require(brohn_text(value, 500) && value %in% columns, paste("Map a source column for", gsub("_", " ", field), "before analysis."))
    mapped <- c(mapped, value)
  }
  brohn_require(!anyDuplicated(mapped), "Use separate columns for participant, session, exposure, choices and their declared evidence; one column cannot stand for different fields.")
  invisible(metadata)
}
.brohn_maxdiff_import_exercise <- function(design, id) {
  brohn_require(is.list(design) && brohn_array(design$maxdiff) && !anyDuplicated(brohn_ids(design$maxdiff)), "Link the exact saved study revision containing these best-worst exercises.")
  exercise <- brohn_find(design$maxdiff, id)
  brohn_require(!is.null(exercise), "The selected exercise is absent from this pinned study revision.")
  brohn_maxdiff_validate(exercise); exercise
}
.brohn_maxdiff_import_origin <- function(exercise, origin) {
  brohn_require(brohn_text(origin, 30) && origin %in% c("sample", "preview", "pilot", "live", "imported"), "The immutable best-worst source has an unsupported origin.")
  brohn_require(exercise$origin != "synthetic" || origin %in% c("sample", "preview"), "Original synthetic best-worst materials must remain sample or preview data; importing a file cannot upgrade their origin.")
  invisible(origin)
}
brohn_validate_maxdiff_mapping <- function(dataset, design = NULL) {
  brohn_require(is.list(dataset) && identical(dataset$modality, "maxdiff") && dataset$source$format %in% c("csv", "tsv"), "Best-worst import needs an explicitly mapped CSV or TSV dataset.")
  .brohn_maxdiff_import_mapping(dataset$metadata, unlist(dataset$columns, use.names = FALSE))
  brohn_require(brohn_valid_id(dataset$study_id) && brohn_number(dataset$study_revision, 1, .Machine$integer.max, TRUE), "Link the exact study revision before mapping best-worst choices.")
  if (!is.null(design)) {
    brohn_require(identical(design$id, dataset$study_id), "The supplied design does not belong to the linked study.")
    .brohn_maxdiff_import_origin(.brohn_maxdiff_import_exercise(design, dataset$metadata$exercise_id), dataset$origin)
  }
  invisible(dataset)
}
brohn_import_maxdiff_analysis <- function(data, metadata, design, source) {
  brohn_require(is.data.frame(data) && nrow(data) >= 1L && nrow(data) <= 20000L && ncol(data) <= 1024L,
    "Best-worst import accepts 1 to 20,000 source rows. Split larger files explicitly; no rows are truncated.")
  .brohn_maxdiff_import_mapping(metadata, names(data))
  brohn_require(all(vapply(data, function(column) is.character(column) && !anyNA(column), logical(1))),
    "Read best-worst CSV/TSV as character columns with na.strings=character(). Missing R values or inferred numeric/factor columns cannot establish original cell identities.")
  brohn_fields(source, c("hash", "origin", "id", "revision"), label = "Immutable best-worst import source")
  brohn_require(brohn_text(source$hash, 64) && grepl("^[a-f0-9]{64}$", source$hash) && brohn_text(source$id, 240) &&
    brohn_number(source$revision, 1, .Machine$integer.max, TRUE), "Pin the original source hash, dataset identity and revision before analysis.")
  exercise <- .brohn_maxdiff_import_exercise(design, metadata$exercise_id); exercise_hash <- brohn_hash(exercise)
  .brohn_maxdiff_import_origin(exercise, source$origin)
  mapped <- function(field) !is.null(metadata[[field]]) && !identical(metadata[[field]], "")
  exercise_values <- if (mapped("exercise_column")) data[[metadata$exercise_column]] else rep(metadata$exercise_id, nrow(data))
  selected <- if (mapped("exercise_column")) exercise_values == metadata$exercise_id else rep(TRUE, nrow(data))
  brohn_require(any(selected), "No source rows match the explicitly selected best-worst exercise.")
  origin_values <- if (mapped("origin_column")) data[[metadata$origin_column]] else rep(source$origin, nrow(data))
  brohn_require(all(data[[metadata$design_hash_column]][selected] == exercise_hash),
    "Selected row design hashes differ from the exact saved exercise. Map an exercise selector for a multi-exercise file; never substitute a later design.")
  if (mapped("origin_column")) brohn_require(all(origin_values[selected] == source$origin), "Selected row origins conflict with the immutable dataset origin; review the source declaration instead of relabelling the evidence.")
  boolean <- function(value, field, row) {
    brohn_require(value %in% c("true", "false", "TRUE", "FALSE", "1", "0"), paste("Source row", row, "has an invalid", field, "boolean. Use true/false or 1/0."))
    value %in% c("true", "TRUE", "1")
  }
  nullable <- function(value) if (identical(value, "")) NULL else value
  responses <- list(); evidence <- vector("list", nrow(data))
  for (i in seq_len(nrow(data))) {
    row <- lapply(as.list(data[i, , drop = FALSE]), unname)
    row_hash <- brohn_hash(row)
    identity <- paste0("md-source-row-", brohn_hash(list(source_hash = source$hash, source_row = i)))
    evidence[[i]] <- list(source_row = i, source_row_hash = row_hash, selected = selected[[i]], response_id = if (selected[[i]]) identity else NULL,
      reason = if (selected[[i]]) "selected_exercise" else "different_exercise", declared_exercise_id = exercise_values[[i]],
      declared_origin = if (mapped("origin_column")) origin_values[[i]] else NULL)
    if (!selected[[i]]) next
    cell <- function(field) data[[metadata[[field]]]][[i]]
    order <- tryCatch(brohn_parse(cell("item_order_column"), 8192L), error = function(e) brohn_stop(paste("Source row", i, "needs an exact JSON array of offered item IDs:", conditionMessage(e))))
    brohn_require(brohn_array(order) && length(order) >= 3L && length(order) <= 8L && all(vapply(order, brohn_text, logical(1), max = 96)),
      paste("Source row", i, "item order must be a JSON array of 3 to 8 string IDs, without numeric conversion."))
    response <- list(id = identity, participant_id = cell("participant_column"), participant_linkage = boolean(cell("participant_linkage_column"), "participant linkage", i),
      session_id = cell("session_column"), exposure_id = cell("exposure_column"), design_hash = cell("design_hash_column"), set_id = cell("set_column"), item_order = order,
      presented = boolean(cell("presented_column"), "presentation", i), status = cell("status_column"), best_id = nullable(cell("best_column")), worst_id = nullable(cell("worst_column")),
      missing_reason = nullable(cell("missing_reason_column")))
    # The canonical scorer validates all rows and identity duplicates together.
    # Do not rehash/revalidate a potentially 200-set design once for every row.
    responses[[length(responses)+1L]] <- response
    evidence[[i]]$mapped_cells <- row[unlist(metadata[.brohn_maxdiff_import_columns()], use.names = FALSE)]
  }
  result <- brohn_maxdiff_analysis(exercise, responses, source)
  list(kind = "explicit_choice", title = paste("Best-worst choices:", exercise$title), choice_tasks = list(result),
    observations = responses, source_rows = evidence, source_rows_hash = brohn_hash(evidence),
    quality = list(source_row_count = nrow(data), selected_row_count = sum(selected), excluded_row_count = sum(!selected),
      complete_pairs = result$quality$answered_exposures, missing_pairs = result$quality$missing_exposures,
      unpresented_exposures = result$quality$exposure_records-result$quality$presented_exposures, participant_count = result$quality$participant_count,
      participant_linkage = result$quality$participant_linkage, session_count = result$quality$session_count,
      usable = result$quality$answered_exposures > 0L, scientifically_qualified = FALSE),
    parameters = list(schema = "brohn-maxdiff-csv-import/1.0", mapping = metadata, source = source, selected_exercise_hash = exercise_hash,
      row_limit = 20000L, identity_policy = "source hash plus original one-based source row", position_policy = "exact declared item-order JSON; no inferred positions",
      boolean_tokens = list("true", "false", "TRUE", "FALSE", "1", "0"), missing_cell_policy = "only the empty best/worst/reason cell becomes null; literal NA remains text",
      origin_verification = if (mapped("origin_column")) "selected_rows_match_immutable_source" else "immutable_source_declaration_only"),
    limitations = c(result$limitations, list("Imported choices preserve declared people, sessions, exposures and offered order; they do not establish browser onset or response-time evidence.",
      "Rows for other exercises are excluded only when an exercise selector is explicitly mapped. Their original row hashes and exclusion reasons remain visible; the immutable source retains every original byte.",
      "Spreadsheet-safe apostrophe prefixes remain literal source text. This adapter does not guess or remove a prefix to reconstruct an upstream identity.")))
}
