# Original typed analysis fixtures; no application services/scientific workers.
source("R/platform-core.R", encoding = "UTF-8")
source("R/platform-questionnaire-artifacts.R", encoding = "UTF-8")
local({
  count <- 0L; check <- function(label, value) {if (!isTRUE(value)) stop("FAIL: ", label); count <<- count+1L; cat("PASS ", label, "\n", sep = "")}
  reject <- function(label, fn, pattern = NULL) {
    error <- tryCatch({fn(); NULL}, error = conditionMessage)
    check(label, !is.null(error) && (is.null(pattern) || grepl(pattern, error, fixed = TRUE)))
  }
  scratch <- tempfile("brohn-questionnaire-artifacts-"); dir.create(scratch)
  source <- list(study_id = "study-original", dataset_id = NULL, origin = "sample", provenance = list(
    design_hash = strrep("a", 64), runs = list(list(run_id = "run-original", origin = "sample", events_hash = strrep("b", 64)))))
  report <- c(list(title = "Original lossless answer evidence"), source, list(analysis = list(kind = "questionnaire", title = "Explicit responses",
    features = list(), observations = list(), empty_array = list(), empty_object = structure(list(), names = character()),
    typed = list(number = 0, false = FALSE, text = "0", null = NULL, near = 1+1e-10, third = 1/3,
      smallest = .Machine$double.xmin, vector = c(1/3, 2/3), matrix = list(path = list(NULL, FALSE, 0, "0"))))))
  before <- brohn_json(report)
  small <- brohn_pack_questionnaire_report(report, scratch)
  check("small report object and canonical bytes are unchanged", identical(small, report) && identical(brohn_json(small), before))
  check("small report creates no files", !length(list.files(scratch)))
  reject("invalid preview bounds are rejected", function() brohn_pack_questionnaire_report(report, scratch, preview_rows = 51))
  reject("unbounded packing threshold is rejected", function() brohn_pack_questionnaire_report(report, scratch, threshold = 32*1024^2))
  tiny <- brohn_pack_questionnaire_report(report, scratch, threshold = 1024)
  ref <- tiny$analysis$artifacts[[1L]]; expected <- brohn_questionnaire_artifact_source(report)
  check("final artifact is contained in the owned scratch artifacts directory", identical(tolower(dirname(ref$path)), tolower(normalizePath(file.path(scratch, "artifacts"), winslash = "/"))))
  check("successful packing removes its owned temporary body", !any(grepl("\\.partial$", list.files(scratch))))
  restored <- brohn_read_questionnaire_artifact(ref$path, ref, expected)
  check("typed primitives, structured user path key and empty containers reconstruct exactly", identical(brohn_json(restored), brohn_json(report$analysis)))
  check("zero, false, text zero and null remain distinct", identical(restored$typed$false, FALSE) && is.numeric(restored$typed$number) && restored$typed$number == 0 && identical(restored$typed$text, "0") && is.null(restored$typed$null))
  check("binary64 values retain exact equality through canonical storage", restored$typed$near == 1+1e-10 && restored$typed$third == 1/3 && restored$typed$smallest == .Machine$double.xmin)
  check("empty arrays and objects retain their JSON types", identical(brohn_json(restored$empty_array), "[]") && identical(brohn_json(restored$empty_object), "{}"))
  check("artifact header and reference bind original analysis and report source", identical(ref$analysis_sha256, brohn_hash(report$analysis)) && identical(ref$source_binding_sha256, brohn_hash(expected)))
  check("new preview schema has no full scientific arrays at top level", identical(tiny$analysis$schema, "brohn-questionnaire-report-preview/1.0") && !any(c("features", "observations", "scales", "task_scores", "questionnaire_revision") %in% names(tiny$analysis)))
  check("verified complete analysis independently reconstructs its exact compact representation", isTRUE(brohn_validate_questionnaire_preview(tiny$analysis, restored, expected)))
  check("packing an already compact report is byte-stable", identical(brohn_pack_questionnaire_report(tiny, scratch), tiny))
  needs_review <- report; needs_review$analysis$status <- "needs_review"
  needs_review$analysis$quality <- list(usable = FALSE, status = "insufficient_support", response_count = 0L, participant_count = NULL,
    full_original_diagnostic = list(raw = strrep("d", 10000L)))
  needs_preview <- brohn_pack_questionnaire_report(needs_review, scratch, threshold = 1024)
  check("artifact representation never upgrades original needs-review or unusable status", identical(needs_preview$analysis$status, "needs_review") &&
    identical(needs_preview$analysis$quality$usable, FALSE) && identical(needs_preview$analysis$quality$status, "insufficient_support") &&
    identical(needs_preview$analysis$representation_status, "complete_analysis_in_artifact"))
  check("bounded quality counts preserve zero and null while large diagnostics remain in full source", identical(needs_preview$analysis$quality$response_count, 0L) &&
    "participant_count" %in% names(needs_preview$analysis$quality) && is.null(needs_preview$analysis$quality$participant_count) &&
    !"full_original_diagnostic" %in% names(needs_preview$analysis$quality))
  needs_ref <- needs_preview$analysis$artifacts[[1L]]
  check("hydration restores the complete original quality diagnostics", identical(brohn_json(brohn_read_questionnaire_artifact(needs_ref$path, needs_ref,
    brohn_questionnaire_artifact_source(needs_review))), brohn_json(needs_review$analysis)))
  for (field in c("status", "quality", "title", "count", "extra", "source", "preview")) {
    altered <- needs_preview$analysis
    if (field == "status") altered$status <- "computed"
    if (field == "quality") altered$quality$usable <- TRUE
    if (field == "title") altered$title <- "Qualified outcome"
    if (field == "count") altered$questionnaire_artifact$counts$observations <- 999L
    if (field == "extra") altered$observations <- list(list(value = 999L))
    if (field == "source") altered$questionnaire_artifact$source_binding$origin <- "live"
    if (field == "preview") altered$preview$observations <- list(list(value_display = "999"))
    reject(paste("compact-only", field, "cannot differ from complete scientific evidence"),
      function() brohn_validate_questionnaire_preview(altered, needs_review$analysis, brohn_questionnaire_artifact_source(needs_review)), "compact questionnaire preview differs")
  }
  altered <- needs_preview$analysis; altered$artifacts[[1L]]$analysis_sha256 <- strrep("d", 64)
  reject("preview verifier also rejects a foreign artifact reference", function() brohn_validate_questionnaire_preview(altered,
    needs_review$analysis, brohn_questionnaire_artifact_source(needs_review)), "artifact reference differs")
  altered <- needs_preview$analysis; altered$preview$rows_per_table <- 51L
  reject("preview verifier refuses an expanded display bound", function() brohn_validate_questionnaire_preview(altered,
    needs_review$analysis, brohn_questionnaire_artifact_source(needs_review)), "bounded questionnaire preview")
  published <- ref; published$path <- NULL; published$hash <- published$sha256; published$sha256 <- NULL; published$size <- published$bytes; published$bytes <- NULL
  check("published hash/size descriptor needs no scratch path", identical(brohn_hash(brohn_read_questionnaire_artifact(ref$path, published, expected)), brohn_hash(report$analysis)))
  wrong <- expected; wrong$origin <- "live"
  reject("another declared origin cannot hydrate the artifact", function() brohn_read_questionnaire_artifact(ref$path, ref, wrong), "another saved report")
  wrong <- expected; wrong$provenance_hash <- strrep("e", 64)
  reject("another source provenance cannot hydrate the artifact", function() brohn_read_questionnaire_artifact(ref$path, ref, wrong), "another saved report")
  wrong <- ref; wrong$hash <- strrep("f", 64)
  reject("conflicting worker/published hash aliases are rejected", function() brohn_read_questionnaire_artifact(ref$path, wrong), "aliases")
  wrong <- ref; wrong$size <- wrong$bytes+1
  reject("conflicting worker/published byte aliases are rejected", function() brohn_read_questionnaire_artifact(ref$path, wrong), "aliases")
  wrong <- ref; wrong$line_bytes <- as.character(wrong$line_bytes)
  reject("numeric profile fields never accept text coercion", function() brohn_read_questionnaire_artifact(ref$path, wrong), "profile")
  wrong <- ref; wrong$counts$observations <- 999
  reject("changed reference row counts are rejected", function() brohn_read_questionnaire_artifact(ref$path, wrong), "header differs")
  reject("caller artifact size bound is enforced before reading", function() brohn_read_questionnaire_artifact(ref$path, ref, max_bytes = 1024), "profile")
  original_lines <- readLines(ref$path, encoding = "UTF-8", warn = FALSE)
  mutate <- function(label, change, pattern = NULL) {
    nodes <- lapply(original_lines, brohn_parse); nodes <- change(nodes)
    target <- tempfile(paste0("altered-", label), tmpdir = scratch, fileext = ".jsonl")
    con <- file(target, "wb"); for (node in nodes) writeBin(c(charToRaw(enc2utf8(brohn_json(node))), as.raw(10L)), con); close(con)
    current <- ref; current$sha256 <- digest::digest(file = target, algo = "sha256"); current$bytes <- as.numeric(file.info(target)$size)
    reject(label, function() brohn_read_questionnaire_artifact(target, current, expected), pattern)
  }
  mutate("reordered typed nodes rejected even with a new whole-file hash", function(nodes) {nodes[c(2,3)] <- nodes[c(3,2)]; nodes}, "reordered")
  mutate("missing node rejected even with a new whole-file hash", function(nodes) nodes[-3L], "reordered")
  mutate("trailing node rejected", function(nodes) c(nodes, tail(nodes, 1L)), "trailing")
  mutate("foreign node path rejected", function(nodes) {nodes[[3L]]$path <- list(list(key = "foreign")); nodes}, "foreign path")
  mutate("foreign semantic category rejected", function(nodes) {nodes[[3L]]$category <- "observations"; nodes}, "foreign path")
  mutate("duplicate object keys rejected", function(nodes) {nodes[[2L]]$keys[[2L]] <- nodes[[2L]]$keys[[1L]]; nodes}, "keys")
  mutate("forged array allocation exceeds remaining node budget", function(nodes) {i <- which(vapply(nodes, function(n) identical(n$type, "array"), logical(1)))[[1L]]; nodes[[i]]$length <- 1000000; nodes}, "array length")
  mutate("altered scalar rejected by original full analysis hash", function(nodes) {
    i <- which(vapply(nodes, function(n) identical(n$type, "value") && identical(n$value, "questionnaire"), logical(1)))[[1L]]
    nodes[[i]]$value <- "other"; nodes
  }, "questionnaire analysis")
  # Header-compatible but noncanonical whitespace is not silently accepted.
  tampered <- tempfile(tmpdir = scratch); writeBin(charToRaw(paste0(original_lines[[1L]], "\n ", paste(original_lines[-1L], collapse = "\n"), "\n")), tampered)
  altered <- ref; altered$sha256 <- digest::digest(file = tampered, algo = "sha256"); altered$bytes <- as.numeric(file.info(tampered)$size)
  reject("noncanonical JSON line is rejected", function() brohn_read_questionnaire_artifact(tampered, altered), "canonical JSON")
  tampered <- tempfile(tmpdir = scratch); writeBin(charToRaw(paste0(original_lines[[1L]], "\n", strrep(" ", .brohn_questionnaire_line_bytes+1L), "\n")), tampered)
  altered <- ref; altered$sha256 <- digest::digest(file = tampered, algo = "sha256"); altered$bytes <- as.numeric(file.info(tampered)$size)
  reject("overlong line is rejected by the bounded binary reader", function() brohn_read_questionnaire_artifact(tampered, altered), "line")
  # Quotes/newlines escape to >256KiB despite the original string having only
  # 190,000 UTF-8 bytes. This must be preserved through ordered string parts.
  escaped <- report; escaped$analysis$escaped <- paste0(strrep("\"", 95000L), strrep("\n", 95000L))
  escaped$analysis$unicode <- paste0(strrep("\u00e9\u6f22\U0001f512", 10000L), "\t\n")
  escaped_packed <- brohn_pack_questionnaire_report(escaped, scratch, threshold = 1024)
  escaped_ref <- escaped_packed$analysis$artifacts[[1L]]
  escaped_lines <- readLines(escaped_ref$path, encoding = "UTF-8", warn = FALSE)
  check("all escaped-text artifact lines remain at most256KiB", max(nchar(escaped_lines, type = "bytes")) <= .brohn_questionnaire_line_bytes)
  check("oversized scalar uses explicit typed string parts", any(grepl('"type":"string_part"', escaped_lines, fixed = TRUE)))
  escaped_read <- brohn_read_questionnaire_artifact(escaped_ref$path, escaped_ref, brohn_questionnaire_artifact_source(escaped))
  check("complete escaped and Unicode text reconstructs exactly", identical(brohn_json(escaped_read), brohn_json(escaped$analysis)))
  part_nodes <- lapply(escaped_lines, brohn_parse)
  part_index <- which(vapply(part_nodes, function(n) identical(n$type, "string_part"), logical(1)))[[1L]]
  part_nodes[[part_index]]$part <- as.character(part_nodes[[part_index]]$part)
  part_file <- tempfile(tmpdir = scratch); con <- file(part_file, "wb")
  for (n in part_nodes) writeBin(c(charToRaw(enc2utf8(brohn_json(n))), as.raw(10L)), con)
  close(con); part_ref <- escaped_ref; part_ref$sha256 <- digest::digest(file = part_file, algo = "sha256"); part_ref$bytes <- as.numeric(file.info(part_file)$size)
  reject("string fragment indices keep strict numeric types", function() brohn_read_questionnaire_artifact(part_file, part_ref), "out of order")
  whitespace <- report; whitespace$analysis$original_fields <- stats::setNames(list(strrep("\"", 140000L), FALSE), c(" ", "\u00e9"))
  white_pack <- brohn_pack_questionnaire_report(whitespace, scratch, threshold = 1024); white_ref <- white_pack$analysis$artifacts[[1L]]
  check("valid whitespace and Unicode object keys are reconstructed without renaming", identical(brohn_json(brohn_read_questionnaire_artifact(white_ref$path, white_ref)), brohn_json(whitespace$analysis)))
  # Mirror the accepted large-report shape without replaying a scientific or
  # delivery job:200 current strings are duplicated in counts/observations and
  # two400-event history representations, all of which must stay complete.
  large <- report; text <- strrep("b", 19000L)
  observations <- lapply(seq_len(200L), function(i) list(participant_id = "original-person", session_id = "original-session", question_id = paste0("q-", i),
    step_id = paste0("step-", i), prompt = paste("Original question", i), value = paste(text, i), origin = "sample", status = "answered", revision_count = 1))
  large$analysis$observations <- observations
  large$analysis$features <- lapply(observations, function(row) list(question_id = row$question_id, prompt = row$prompt, response_count = 1L, answered_count = 1L,
    missing_count = 0L, numeric_response_mean = NULL, counts = list(list(value = row$value, label = brohn_json(row$value), count = 1L))))
  large$analysis$questionnaire_revision <- list(schema = "brohn-questionnaire-revision-results/1.0", runs = list(list(run_id = "original-session",
    effective_records = observations, history_events = lapply(seq_len(400L), function(i) list(id = paste0("history-", i), sequence = i, value = paste(text, i))),
    history_records = lapply(seq_len(400L), function(i) list(event_id = paste0("history-", i), sequence = i)),
    invalidations = list(list(cause_event_id = "original-cause", previous_head_event_id = "original-old", question_id = "q-1")))))
  large$analysis$scales <- list(observations = list(list(value = 5, items = list(6, 4), missing = NULL)))
  large$analysis$task_scores <- list(list(profile = "original-descriptive", value = 1/3))
  large_bytes <- nchar(brohn_json(large), type = "bytes"); check("original large analysis reproduces report-envelope size pressure", large_bytes > 16*1024^2)
  compact <- brohn_pack_questionnaire_report(large, scratch); full_ref <- compact$analysis$artifacts[[1L]]
  compact_bytes <- nchar(brohn_json(compact), type = "bytes")
  check("large full features/observations/history become a bounded compact report", compact_bytes < 1024^2 && full_ref$analysis_bytes > 16*1024^2)
  check("full source counts remain explicit instead of pretending previews are complete", full_ref$counts$observations == 200L && full_ref$counts$features == 200L &&
    full_ref$counts$feature_counts == 200L && full_ref$counts$revision_effective == 200L && full_ref$counts$revision_history == 400L && full_ref$counts$revision_history_refs == 400L && full_ref$counts$revision_invalidations == 1L)
  check("preview tables have labelled truncation and bounded rows", length(compact$analysis$preview$observations) == 10L && length(compact$analysis$preview$features) == 10L &&
    compact$analysis$preview$observations[[1L]]$value_truncated && nchar(compact$analysis$preview$observations[[1L]]$value_display) <= 243L)
  hydrated <- brohn_read_questionnaire_artifact(full_ref$path, full_ref, brohn_questionnaire_artifact_source(large))
  check("full large analysis including features/counts/history/scales/tasks reconstructs losslessly", identical(brohn_json(hydrated), brohn_json(large$analysis)))
  check("hydration preserves actual scale mean and full source observations", hydrated$scales$observations[[1L]]$value == (6+4)/2 && length(hydrated$observations) == 200L)
  check("packed report retains exact original outer provenance and origin", identical(compact$provenance, large$provenance) && identical(compact$origin, "sample"))
  huge_source <- report; huge_source$provenance$original_declared_context <- strrep("x", 17*1024^2)
  files <- list.files(scratch)
  reject("oversized provenance alone gets an actionable failure without truncation", function() brohn_pack_questionnaire_report(huge_source, scratch), "provenance/design")
  check("provenance-only rejection creates no partial output", identical(list.files(scratch), files))
  clean <- tempfile("brohn-questionnaire-provenance-only-"); dir.create(clean)
  reject("provenance rejection precedes creation of an artifacts directory", function() brohn_pack_questionnaire_report(huge_source, clean), "provenance/design")
  check("provenance rejection leaves its empty scratch untouched", !length(list.files(clean)))
  canary <- file.path(scratch, "original-canary.txt"); writeLines("Original unrelated source stays present.", canary)
  impossible <- report; impossible$analysis$original_fields <- stats::setNames(list(1), strrep("k", .brohn_questionnaire_line_bytes))
  reject("unsupported oversized object key fails without partial output", function() brohn_pack_questionnaire_report(impossible, scratch, threshold = 1024), "line length")
  check("failed packing removes only owned partial files and preserves sibling source", identical(readLines(canary), "Original unrelated source stays present.") && !any(grepl("\\.partial$", list.files(scratch))))
  cat(sprintf("PASS: %d questionnaire artifact checks; original large report%d bytes -> compact%d bytes; no workers launched.\n", count, large_bytes, compact_bytes))
})
