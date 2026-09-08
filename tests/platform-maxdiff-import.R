for (module in c("core", "maxdiff", "maxdiff-platform", "analysis", "data-views", "maxdiff-import")) source(paste0("R/platform-", module, ".R"))
local({
  checks <- 0L
  check <- function(name, value) {if (!isTRUE(value)) stop("MaxDiff import QA: ", name, call. = FALSE); checks <<- checks+1L}
  rejects <- function(expr) inherits(try(force(expr), silent = TRUE), "try-error")
  close <- function(a, b) isTRUE(all.equal(a, b, tolerance = 1e-8, check.attributes = FALSE))
  root <- tempfile("brohn-maxdiff-import-"); dir.create(root); root <- normalizePath(root, winslash = "/")
  on.exit({resolved <- normalizePath(root, winslash = "/", mustWork = FALSE)
    stopifnot(startsWith(tolower(resolved), paste0(tolower(normalizePath(tempdir(), winslash = "/")), "/")), grepl("^brohn-maxdiff-import-", basename(resolved)))
    unlink(resolved, recursive = TRUE, force = TRUE)}, add = TRUE)
  exercise <- brohn_maxdiff_new(id = "original-import-choice"); exercise$items <- head(exercise$items, 3L)
  exercise$sets <- list(list(id = "original-all-three", item_ids = as.list(brohn_ids(exercise$items))))
  design <- brohn_new_design("Original import reference", "survey", id = "original-import-study"); design$maxdiff <- list(exercise)
  pairs <- list(c(1L,2L), c(1L,3L), c(2L,1L), c(2L,3L), c(3L,1L), c(3L,2L))
  rows <- lapply(seq_along(pairs), function(i) list(id = paste0("original-response-", i), participant_id = "original-participant", participant_linkage = TRUE,
    session_id = "original-session", exposure_id = paste0("original-exposure-", i), design_hash = brohn_hash(exercise), set_id = exercise$sets[[1L]]$id,
    item_order = if (i %% 2L) exercise$sets[[1L]]$item_ids else rev(exercise$sets[[1L]]$item_ids), presented = TRUE, status = "answered",
    best_id = paste0("item-", pairs[[i]][[1L]]), worst_id = paste0("item-", pairs[[i]][[2L]]), missing_reason = NULL))
  original <- brohn_maxdiff_analysis(exercise, rows, list(hash = strrep("a", 64), origin = "sample", id = "original-ledger", revision = 1L))
  csv <- file.path(root, "actual-brohn-export.csv")
  brohn_export_report_csv(list(analysis = list(choice_tasks = list(original))), csv)
  table <- brohn_read_table(csv, "csv", 20000L)
  source <- list(hash = digest::digest(file = csv, algo = "sha256"), origin = "sample", id = "original-csv-dataset", revision = 1L)
  metadata <- list(exercise_id = exercise$id, origin_statement = "Original synthetic six-pair reference, exported by Brohn for arithmetic verification.",
    participant_column = "participant_id", session_column = "session_id", exposure_column = "exposure_id", design_hash_column = "design_hash", set_column = "set_id",
    item_order_column = "item_order", presented_column = "presented", status_column = "status", best_column = "best_id", worst_column = "worst_id",
    missing_reason_column = "missing_reason", participant_linkage_column = "participant_linkage", exercise_column = "exercise_id", origin_column = "origin")
  dataset <- list(id = source$id, modality = "maxdiff", source = list(format = "csv", hash = source$hash), origin = source$origin,
    study_id = design$id, study_revision = 1L, columns = as.list(names(table)), metadata = metadata)
  check("strict mapped dataset accepts its exact pinned study exercise", identical(brohn_validate_maxdiff_mapping(dataset, design), dataset))
  imported <- brohn_import_maxdiff_analysis(table, metadata, design, source); result <- imported$choice_tasks[[1L]]
  check("actual Brohn CSV round-trip reaches the canonical explicit-choice scorer", imported$kind == "explicit_choice" && result$schema == "brohn-maxdiff-result/1.0" && identical(result$source, source))
  check("six balanced ordered pairs have exact independent NLL six log six", result$model$status == "estimated" && close(result$model$diagnostics$negative_log_likelihood, 6*log(6)) &&
    all(abs(vapply(result$model$utilities, `[[`, numeric(1), "utility")) < 1e-10))
  check("balanced complete-pair counts use six exposures with no made-up missingness", all(vapply(result$items, function(i) i$best_count == 2 && i$worst_count == 2 && i$answered_exposures == 6 && i$exposure_adjusted_score == 0, logical(1))))
  check("declared actual offered orders survive JSON text and are never sorted", all(vapply(seq_along(rows), function(i) identical(rows[[i]]$item_order, result$exposures[[i]]$item_order), logical(1))))
  check("source row identities and complete hashes are stable", identical(imported, brohn_import_maxdiff_analysis(table, metadata, design, source)) &&
    imported$source_rows_hash == brohn_hash(imported$source_rows) && all(vapply(seq_len(nrow(table)), function(i) imported$source_rows[[i]]$source_row_hash == brohn_hash(lapply(as.list(table[i, , drop = FALSE]), unname)), logical(1))))
  check("one explicit person and session do not become six independent people", imported$quality$participant_count == 1L && imported$quality$session_count == 1L && result$quality$repeated_set_exposures == 5L)
  check("selected raw mapped cells preserve boolean and order source text", imported$source_rows[[1L]]$mapped_cells$presented == "true" && imported$source_rows[[1L]]$mapped_cells$item_order == table$item_order[[1L]])
  changed_source <- source; changed_source$hash <- strrep("b", 64)
  check("another immutable source creates distinct row response identities", brohn_import_maxdiff_analysis(table, metadata, design, changed_source)$observations[[1L]]$id != imported$observations[[1L]]$id)
  tsv <- file.path(root, "original-tabs.tsv"); utils::write.table(table, tsv, sep = "\t", row.names = FALSE, quote = TRUE, qmethod = "double", fileEncoding = "UTF-8")
  tab_source <- source; tab_source$hash <- digest::digest(file = tsv, algo = "sha256")
  tabbed <- brohn_import_maxdiff_analysis(brohn_read_table(tsv, "tsv", 20000L), metadata, design, tab_source)
  check("actual TSV preserves the same typed choice likelihood", close(tabbed$choice_tasks[[1L]]$model$diagnostics$negative_log_likelihood, 6*log(6)))
  bools <- table; bools$presented <- c("true", "TRUE", "1", "true", "TRUE", "1"); bools$participant_linkage <- c("false", "FALSE", "0", "false", "FALSE", "0")
  anonymous <- brohn_import_maxdiff_analysis(bools, metadata, design, source)
  check("explicit CSV boolean encodings retain unlinked codes without guessing people", is.null(anonymous$quality$participant_count) && anonymous$quality$participant_linkage == "unavailable" && anonymous$quality$session_count == 1L)
  bools$participant_linkage[[1L]] <- "1"
  check("mixed linked and unlinked declarations withhold person count", is.null(brohn_import_maxdiff_analysis(bools, metadata, design, source)$quality$participant_count))
  missing <- table[1:3, , drop = FALSE]; missing$exposure_id <- paste0("missing-exposure-", 1:3); missing$status <- c("missing", "not_presented", "missing")
  missing$presented <- c("1", "0", "true"); missing$best_id <- c("item-1", "", ""); missing$worst_id <- c("", "", "item-2"); missing$missing_reason <- c("Partial best retained", "Not reached", "Partial worst retained")
  retained <- brohn_import_maxdiff_analysis(rbind(table, missing), metadata, design, source)
  check("missing and unpresented rows retain honest source/exposure counts", retained$quality$source_row_count == 9L && retained$quality$complete_pairs == 6L && retained$quality$missing_pairs == 2L && retained$quality$unpresented_exposures == 1L)
  check("partial choices remain evidence without entering complete-pair counts", retained$observations[[7L]]$best_id == "item-1" && is.null(retained$observations[[7L]]$worst_id) &&
    retained$observations[[9L]]$worst_id == "item-2" && all(vapply(retained$choice_tasks[[1L]]$items, function(i) i$answered_exposures == 6L && i$missing_exposures == 2L && i$best_count == 2L, logical(1))))
  only_missing <- brohn_import_maxdiff_analysis(missing, metadata, design, source)
  check("an entirely incomplete source gives unavailable scores instead of zeros", !only_missing$quality$usable && only_missing$choice_tasks[[1L]]$model$reason == "no_complete_pairs" &&
    all(vapply(only_missing$choice_tasks[[1L]]$items, function(i) is.null(i$exposure_adjusted_score), logical(1))))
  other <- table[1L, , drop = FALSE]; other$exercise_id <- "other-explicit-exercise"; other$design_hash <- strrep("d", 64); other$origin <- "pilot"
  other$best_id <- "Other unvalidated item"; other$presented <- "not parsed"; other$item_order <- "not a selected JSON array"
  mixed <- brohn_import_maxdiff_analysis(rbind(other, table), metadata, design, source)
  check("explicit exercise selector excludes other rows with original positions and hashes", mixed$quality$excluded_row_count == 1L && mixed$quality$selected_row_count == 6L &&
    !mixed$source_rows[[1L]]$selected && mixed$source_rows[[1L]]$reason == "different_exercise" && mixed$source_rows[[1L]]$declared_origin == "pilot" &&
    mixed$source_rows[[2L]]$source_row == 2L && is.null(mixed$source_rows[[1L]]$response_id))
  without_selector <- metadata; without_selector$exercise_column <- NULL
  check("mixed source hashes without a mapped exercise selector fail closed", rejects(brohn_import_maxdiff_analysis(rbind(other, table), without_selector, design, source)))
  no_matches <- table; no_matches$exercise_id <- "other-explicit-exercise"
  check("an explicit selector with no matching row is an actionable error", rejects(brohn_import_maxdiff_analysis(no_matches, metadata, design, source)))
  bad <- table; bad$origin[[1L]] <- "live"
  check("a selected row cannot upgrade or conflict with dataset origin", rejects(brohn_import_maxdiff_analysis(bad, metadata, design, source)))
  bad_source <- source; bad_source$origin <- "imported"
  check("synthetic material cannot be relabelled imported to bypass source policy", rejects(brohn_import_maxdiff_analysis(table, metadata, design, bad_source)))
  bad_dataset <- dataset; bad_dataset$origin <- "live"
  check("mapping preview enforces known synthetic origin before worker dispatch", rejects(brohn_validate_maxdiff_mapping(bad_dataset, design)))
  no_origin <- metadata; no_origin$origin_column <- NULL
  check("unmapped origin remains an explicit source-declaration-only policy", brohn_import_maxdiff_analysis(table, no_origin, design, source)$parameters$origin_verification == "immutable_source_declaration_only")
  bad <- table; bad$design_hash[[1L]] <- strrep("e", 64)
  check("selected wrong revision hash is rejected", rejects(brohn_import_maxdiff_analysis(bad, metadata, design, source)))
  bad <- table; bad$set_id[[1L]] <- "not-offered"
  check("foreign set identity is not resolved by row position", rejects(brohn_import_maxdiff_analysis(bad, metadata, design, source)))
  bad <- table; bad$best_id[[1L]] <- bad$worst_id[[1L]]
  check("same best/worst pair is not scored", rejects(brohn_import_maxdiff_analysis(bad, metadata, design, source)))
  bad <- table; bad$item_order[[1L]] <- '[1,"item-2","item-3"]'
  check("numeric offered IDs cannot be coerced from item-order JSON", rejects(brohn_import_maxdiff_analysis(bad, metadata, design, source)))
  bad <- table; bad$item_order[[1L]] <- '{"first":"item-1"}'
  check("JSON object is not treated as an ordered offered array", rejects(brohn_import_maxdiff_analysis(bad, metadata, design, source)))
  bad <- table; bad$item_order[[1L]] <- '["item-1","item-1","item-3"]'
  check("duplicate offered IDs cannot create another exposure", rejects(brohn_import_maxdiff_analysis(bad, metadata, design, source)))
  bad <- table; bad$participant_id[[1L]] <- ""
  check("participant identity is never inferred from row or filename", rejects(brohn_import_maxdiff_analysis(bad, metadata, design, source)))
  check("repeated person/session/exposure tuple cannot silently double-count", rejects(brohn_import_maxdiff_analysis(rbind(table, table[1L, ]), metadata, design, source)))
  bad <- table; bad$participant_id[[1L]] <- NA_character_
  check("already-converted missing R text is rejected rather than decoded as an ID", rejects(brohn_import_maxdiff_analysis(bad, metadata, design, source)))
  bad <- table; bad$participant_id <- seq_len(nrow(bad))
  check("inferred numeric source columns require a character-preserving reread", rejects(brohn_import_maxdiff_analysis(bad, metadata, design, source)))
  for (value in c("yes", "NA", "null", "", " true ")) {
    bad <- table; bad$participant_linkage[[1L]] <- value
    check(paste("undocumented participant-linkage boolean rejected:", value), rejects(brohn_import_maxdiff_analysis(bad, metadata, design, source)))
  }
  bad <- table; bad$best_id[[1L]] <- "NA"
  check("literal NA is not silently interpreted as a missing best item", rejects(brohn_import_maxdiff_analysis(bad, metadata, design, source)))
  literal_design <- design; literal_design$maxdiff[[1L]]$items[[1L]]$id <- "NA"; literal_design$maxdiff[[1L]]$sets[[1L]]$item_ids[[1L]] <- "NA"
  literal <- table; literal$design_hash <- brohn_hash(literal_design$maxdiff[[1L]]); literal$best_id[literal$best_id == "item-1"] <- "NA"; literal$worst_id[literal$worst_id == "item-1"] <- "NA"
  literal$item_order <- vapply(rows, function(r) brohn_json(lapply(r$item_order, function(id) if (id == "item-1") "NA" else id)), character(1))
  literal_result <- brohn_import_maxdiff_analysis(literal, metadata, literal_design, source)
  check("literal NA remains a valid explicitly offered string identity", literal_result$observations[[1L]]$best_id == "NA" && literal_result$choice_tasks[[1L]]$model$status == "estimated")
  bad_metadata <- metadata; bad_metadata$best_column <- metadata$worst_column
  bad_dataset <- dataset; bad_dataset$metadata <- bad_metadata
  check("mapping cannot alias best and worst to the same source field", rejects(brohn_validate_maxdiff_mapping(bad_dataset, design)))
  bad_dataset <- dataset; bad_dataset$study_revision <- NULL
  check("study revision must be pinned before source mapping is accepted", rejects(brohn_validate_maxdiff_mapping(bad_dataset)))
  bad_dataset <- dataset; bad_dataset$source$format <- "json"
  check("unsupported transport is not silently parsed as CSV", rejects(brohn_validate_maxdiff_mapping(bad_dataset, design)))
  bad_metadata <- metadata; bad_metadata$origin_statement <- ""
  check("source origin requires an explicit collection statement", rejects(brohn_import_maxdiff_analysis(table, bad_metadata, design, source)))
  too_many <- table[rep(1L, 20001L), , drop = FALSE]
  check("twenty-thousand row bound is explicit without a truncated score", rejects(brohn_import_maxdiff_analysis(too_many, metadata, design, source)))
  changed_design <- design; changed_design$maxdiff[[1L]]$settings$best_label <- "Most preferred"
  check("changed research framing is not a compatible source hash", rejects(brohn_import_maxdiff_analysis(table, metadata, changed_design, source)))
  shifted <- table; shifted$participant_id <- rep("'@original-person", 6L)
  check("spreadsheet-safe apostrophe prefixes remain literal declared source IDs", brohn_import_maxdiff_analysis(shifted, metadata, design, source)$observations[[1L]]$participant_id == "'@original-person")
  check("base result schema is retained intact with full exposure evidence", setequal(names(result), names(original)) && length(imported$observations) == 6L && length(result$exposures) == 6L)
  cat("Brohn MaxDiff import:", checks, "checks passed\n")
})
