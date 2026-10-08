# Portable test: candidate checkout, fresh output directory. Run under LC_ALL=C.
# Uses one fresh owned store; no worker jobs, services or participant scoring.
local({
  args <- commandArgs(TRUE); stopifnot(length(args) == 2L)
  checkout <- normalizePath(args[[1L]], winslash = "/", mustWork = TRUE)
  output <- args[[2L]]; stopifnot(!file.exists(output)); dir.create(output, recursive = TRUE)
  output <- normalizePath(output, winslash = "/", mustWork = TRUE)
  setwd(checkout); source("R/platform-load.R", local = .GlobalEnv, encoding = "UTF-8")
  brohn_load(envir = .GlobalEnv, ui = FALSE)
  passed <- FALSE; checks <- character(); store <- NULL; closed <- FALSE
  started <- proc.time()[["elapsed"]]; original_store_object <- brohn_store_object
  scientific_reader_hash <- digest::digest(file = "R/platform-analysis.R", algo = "sha256")
  source_paths <- c("R/platform-tabular-preview.R", "R/platform-library.R", "R/platform-ingestion.R", "R/platform-load.R", "scripts/analysis-worker.R", "R/platform-analysis.R")
  hashes <- lapply(source_paths, function(p) list(path = p, sha256 = digest::digest(file = p, algo = "sha256")))
  on.exit({
    assign("brohn_store_object", original_store_object, envir = .GlobalEnv)
    if (!closed && !is.null(store)) {brohn_close_store(store); closed <- TRUE}
    result <- list(passed = passed, checks = as.list(checks), elapsed_s = proc.time()[["elapsed"]] - started,
      locale = Sys.getlocale(), source_files = hashes, store_closed = closed,
      scope = "UTF-8 bounded preview, actual synchronous import and catalog rollback; queued preview helper/publication identity tested without native worker/service or whole-file validation claim.")
    writeLines(as.character(jsonlite::toJSON(result, auto_unbox = TRUE, null = "null", pretty = TRUE)), file.path(output, "RESULTS.json"), useBytes = TRUE)
  }, add = TRUE)
  check <- function(label, ok) {stopifnot(isTRUE(ok)); checks <<- c(checks, label); cat("PASS ", label, "\n", sep = "")}
  refuse <- function(label, expr) {error <- tryCatch({force(expr); NULL}, error = function(e) e); check(label, inherits(error, "error"))}
  bytes <- function(text) charToRaw(enc2utf8(text))
  write_source <- function(name, value) {path <- file.path(output, name); writeBin(if (is.raw(value)) value else bytes(value), path); path}
  read_raw <- function(path) {con <- file(path, "rb"); on.exit(close(con)); readBin(con, "raw", n = file.info(path)$size)}
  same_table <- function(a, b) identical(names(a), names(b)) && identical(nrow(a), nrow(b)) &&
    identical(lapply(a, enc2utf8), lapply(b, enc2utf8))
  old_preview <- function(path, fmt, skip = TRUE) suppressWarnings(utils::read.table(path,
    header = TRUE, sep = if (fmt == "csv") "," else "\t", nrows = 20L, colClasses = "character",
    check.names = FALSE, comment.char = "", quote = "\"", fileEncoding = "UTF-8", na.strings = character(), blank.lines.skip = skip))
  check("normal qualified C character locale is active", identical(Sys.getlocale("LC_CTYPE"), "C"))
  text <- 'participant,\u00e9tiquette,value\nqa-\u00e9,"Cr\u00e8me, \u6771\u4eac",001\n0007,"a ""quote""",NA\n9007199254740993,\u03bc,NaN\n'
  csv <- write_source("unicode.csv", text)
  parsed <- brohn_tabular_preview(csv, "csv", TRUE)
  legacy <- tryCatch(old_preview(csv, "csv"), error = function(e) e)
  check("original fileEncoding path reproduces C-locale refusal or source alteration", inherits(legacy, "error") || !same_table(legacy, parsed))
  check("UTF-8 header and qa-e-acute identifier survive exact code points", identical(enc2utf8(names(parsed)), c("participant", "\u00e9tiquette", "value")) && identical(enc2utf8(parsed$participant[[1L]]), "qa-\u00e9"))
  check("CSV quote delimiters Unicode values and literal strings are preserved", identical(enc2utf8(parsed[[2L]]), c("Cr\u00e8me, \u6771\u4eac", 'a "quote"', "\u03bc")) &&
    identical(parsed$participant, c(enc2utf8("qa-\u00e9"), "0007", "9007199254740993")) && identical(parsed$value, c("001", "NA", "NaN")))
  check("queued preview shares exact UTF-8 values", same_table(parsed, brohn_tabular_preview(csv, "csv", FALSE)))
  tsv <- write_source("unicode.tsv", 'participant\t\u00e9tiquette\tvalue\nqa-\u00e9\t"Cr\u00e8me\t\u6771\u4eac"\t0002\n')
  tabbed <- brohn_tabular_preview(tsv, "tsv", FALSE)
  check("TSV uses original tab delimiter and quotes without locale conversion", identical(enc2utf8(tabbed[[2L]][[1L]]), "Cr\u00e8me\t\u6771\u4eac") && identical(tabbed$value, "0002"))
  bom <- write_source("bom.csv", c(as.raw(c(0xef, 0xbb, 0xbf)), read_raw(csv)))
  bom_original <- read_raw(bom)
  check("UTF-8 BOM removed only from parser prefix", same_table(parsed, brohn_tabular_preview(bom, "csv", TRUE)))
  check("BOM and complete original file bytes remain untouched", identical(read_raw(bom), bom_original))
  embedded_bom <- write_source("embedded-bom.csv", "id,value\n1,\ufeffretained\n")
  check("non-prefix BOM in a value remains original text", identical(enc2utf8(brohn_tabular_preview(embedded_bom, "csv")$value), "\ufeffretained"))
  header <- write_source("header.csv", "participant,\u00e9tiquette\n")
  check("header-only source remains zero-row preview", nrow(brohn_tabular_preview(header, "csv", TRUE)) == 0L && nrow(brohn_tabular_preview(header, "csv", FALSE)) == 0L)
  no_final_line <- write_source("no-final-line.csv", "id,value\nqa-\u00e9,NA")
  check("valid final record need not end with newline", identical(enc2utf8(brohn_tabular_preview(no_final_line, "csv")$id), "qa-\u00e9"))
  literals <- write_source("literal.csv", 'id,value\n0001,\n0002,""\n0003,null\n0004,N/A\n0005,NA\n')
  check("empty values and NA-like literals stay character strings", identical(brohn_tabular_preview(literals, "csv")$value, c("", "", "null", "N/A", "NA")))
  multiline <- write_source("multiline.csv", 'id,value\n1,"first\nsecond"\n2,last\n')
  check("quoted multiline cells remain one record", nrow(brohn_tabular_preview(multiline, "csv")) == 2L && identical(brohn_tabular_preview(multiline, "csv")$value[[1L]], "first\nsecond"))
  blank <- write_source("blank.csv", "id,value\n1,a\n\n2,b\n")
  for (skip in c(TRUE, FALSE)) check(paste("ASCII blank-line legacy behavior matches with skip", skip), same_table(old_preview(blank, "csv", skip), brohn_tabular_preview(blank, "csv", skip)))
  short <- write_source("short.csv", "id,value\n1\n2,b\n")
  check("queued fill default remains linked to blank.lines.skip FALSE", same_table(old_preview(short, "csv", FALSE), brohn_tabular_preview(short, "csv", FALSE)))
  refuse("synchronous short rows retain non-fill refusal", brohn_tabular_preview(short, "csv", TRUE))
  many <- write_source("many.csv", paste0("id,value\n", paste0(seq_len(25L), ",v", seq_len(25L), "\n", collapse = "")))
  check("both callers parse at most original20 records without sentinel21", nrow(brohn_tabular_preview(many, "csv", TRUE)) == 20L && nrow(brohn_tabular_preview(many, "csv", FALSE)) == 20L &&
    identical(brohn_tabular_preview(many, "csv")$id, as.character(seq_len(20L))))
  first20 <- bytes(paste0("id,value\n", paste0(seq_len(20L), ",v", seq_len(20L), "\n", collapse = "")))
  invalid_tail <- write_source("invalid-after-preview.csv", c(first20, bytes("21,"), as.raw(0xff), bytes("\n")))
  check("bounded preview does not claim to validate malformed text after its rows", nrow(brohn_tabular_preview(invalid_tail, "csv")) == 20L)
  refuse("unchanged scientific reader still detects malformed full-file tail", brohn_read_table(invalid_tail, "csv"))
  # The guard uses scan only for completeness, never as a replacement table.
  guard <- function(path, skip = TRUE, format = "csv") .brohn_tabular_preview_complete(path, format, skip)
  header_no_newline <- write_source("header-no-newline.csv", "id,value")
  check("header without terminal newline remains a zero-row source", nrow(brohn_tabular_preview(header_no_newline, "csv")) == 0L)
  final_multiline <- write_source("final-multiline.csv", 'id,value\n1,"first\nsecond"')
  check("complete final multiline record without newline is preserved", identical(brohn_tabular_preview(final_multiline, "csv")$value, "first\nsecond"))
  crlf <- write_source("crlf.csv", 'id,value\r\n1,"first\r\nsecond"\r\n2,"a ""quote"""\r\n')
  for (skip in c(TRUE, FALSE)) check(paste("CRLF multiline and doubled quotes retain native semantics", skip), same_table(old_preview(crlf, "csv", skip), brohn_tabular_preview(crlf, "csv", skip)))
  leading_blanks <- write_source("leading-blanks.csv", '\n\nid,value\n1,ok\n\n2,last')
  check("leading and middle skipped blank lines retain final values", identical(brohn_tabular_preview(leading_blanks, "csv", TRUE)$id, c("1", "2")))
  mixed_bad <- write_source("mixed-bad.csv", 'id,value\n1,valid\nqa,"unfinished\n')
  for (skip in c(TRUE, FALSE)) refuse(paste("header warning cannot silently discard mixed valid and unfinished rows", skip), brohn_tabular_preview(mixed_bad, "csv", skip))
  quote20 <- write_source("quote20.csv", paste0("id,value\n", paste0(seq_len(19L), ",ok\n", collapse = ""), '20,"unfinished\n'))
  quote21 <- write_source("quote21.csv", c(first20, bytes('21,"unfinished\n')))
  for (skip in c(TRUE, FALSE)) {
    refuse(paste("unfinished twentieth logical record refuses", skip), brohn_tabular_preview(quote20, "csv", skip))
    refuse(paste("native completeness guard refuses record20", skip), guard(quote20, skip))
    check(paste("unfinished record21 is outside preview and guard", skip), nrow(brohn_tabular_preview(quote21, "csv", skip)) == 20L && is.null(guard(quote21, skip)))
    check(paste("invalid UTF8 record21 remains outside guard", skip), is.null(guard(invalid_tail, skip)))
  }
  long_multiline <- write_source("long-multiline.csv", paste0('id,value\n1,"', paste(rep("line", 30L), collapse = "\n"), '"\n2,last'))
  check("physical multiline count does not truncate logical records", nrow(brohn_tabular_preview(long_multiline, "csv")) == 2L && is.null(guard(long_multiline)))
  blank_boundary <- write_source("blank-boundary.csv", paste0("id,value\n1,ok\n\n", paste0(2:20, ",ok\n", collapse = ""), '21,"unfinished\n'))
  quoted_blank_boundary <- write_source("quoted-blank-boundary.csv", paste0('id,value\n""\n""\n', paste0(1:20, ",ok\n", collapse = ""), '21,"unfinished\n'))
  for (skip in c(TRUE, FALSE)) for (path in c(blank_boundary, quoted_blank_boundary)) check(paste("empty and quoted-empty records share native preview boundary", basename(path), skip),
    same_table(old_preview(path, "csv", skip), brohn_tabular_preview(path, "csv", skip)) && is.null(guard(path, skip)))
  whitespace_boundary <- write_source("whitespace-boundary.csv", paste0("id\n \t\n", paste0(1:19, "\n", collapse = ""), '"unfinished\n'))
  for (skip in c(TRUE, FALSE)) check(paste("whitespace-only field counts with original separated-field rules", skip), nrow(brohn_tabular_preview(whitespace_boundary, "csv", skip)) == 20L && is.null(guard(whitespace_boundary, skip)))
  many_blanks_bad <- write_source("many-blanks-bad.csv", paste0("id,value\n", paste(rep("\n", 30L), collapse = ""), '1,"unfinished\n'))
  refuse("skipped blank records cannot hide unfinished first data record", brohn_tabular_preview(many_blanks_bad, "csv", TRUE))
  check("non-skipping policy retains20 blank records and no sentinel", nrow(brohn_tabular_preview(many_blanks_bad, "csv", FALSE)) == 20L && is.null(guard(many_blanks_bad, FALSE)))
  check("native guard leaves valid TSV and BOM values to read.table", is.null(guard(tsv, FALSE, "tsv")) && is.null(guard(bom, TRUE)))
  invalid <- list(
    malformed_value = write_source("bad-value.csv", c(bytes("id,value\nqa,"), as.raw(0xff), bytes("\n"))),
    malformed_header = write_source("bad-header.csv", c(bytes("id,"), as.raw(0xff), bytes("\nqa,x\n"))),
    nul = write_source("nul.csv", c(bytes("id,value\nqa,a"), as.raw(0), bytes("b\n"))),
    unterminated_quote = write_source("quote.csv", 'id,value\nqa,"unfinished\n'),
    duplicate_header = write_source("duplicate.csv", "id,id\n1,2\n"),
    empty_header = write_source("empty-header.csv", "id,\n1,2\n"),
    empty_file = write_source("empty.csv", raw()))
  for (name in names(invalid)) for (skip in c(TRUE, FALSE)) refuse(paste("malformed preview refuses", name, skip), brohn_tabular_preview(invalid[[name]], "csv", skip))
  refuse("unsupported delimiter profile refuses", brohn_tabular_preview(csv, "txt"))
  refuse("ambiguous blank-line policy refuses", brohn_tabular_preview(csv, "csv", NA))

  store <- brohn_open_store(file.path(output, "workspace")); brohn_initialise_library(store)
  counts <- function() lapply(c("entities", "entity_versions", "objects", "jobs"), function(name) DBI::dbGetQuery(store$con, paste0("SELECT count(*) AS n FROM ", name))$n[[1L]])
  initial <- counts()
  for (name in c("malformed_value", "nul", "unterminated_quote", "duplicate_header")) {
    refuse(paste("actual synchronous import refuses", name), brohn_ingest_dataset(store, invalid[[name]], "Malformed preview", "ecg", origin = "sample"))
    check(paste("preview failure rolls back all registered entities objects and jobs", name), identical(counts(), initial))
  }
  dataset <- brohn_ingest_dataset(store, bom, "UTF-8 retained source", "ecg", origin = "sample")
  check("actual dataset retains original UTF-8 preview", identical(enc2utf8(dataset$body$preview[[1L]]$participant), "qa-\u00e9") && identical(enc2utf8(unlist(dataset$body$columns)), enc2utf8(names(parsed))))
  check("actual import keeps entire BOM source object bytes and original hash", identical(read_raw(brohn_object_path(store, dataset$body$source$hash)), bom_original) &&
    identical(dataset$body$source$hash, digest::digest(bom_original, algo = "sha256", serialize = FALSE)))
  header_dataset <- brohn_ingest_dataset(store, header, "Header-only retained source", "ecg", origin = "sample")
  check("actual header-only dataset remains available for review", length(header_dataset$body$preview) == 0L && length(header_dataset$body$columns) == 2L)
  many_dataset <- brohn_ingest_dataset(store, many, "Whole source beyond preview", "ecg", origin = "sample")
  check("20-row dataset preview preserves all25 original source rows", length(many_dataset$body$preview) == 20L && identical(read_raw(brohn_object_path(store, many_dataset$body$source$hash)), read_raw(many)))

  mutable_upload <- write_source("mutable-upload.csv", text)
  original_upload <- read_raw(mutable_upload)
  assign("brohn_store_object", function(store, path = NULL, ...) {
    object <- original_store_object(store, path = path, ...)
    if (identical(path, mutable_upload)) writeBin(bytes("id,value\nreplaced,upload\n"), mutable_upload)
    object
  }, envir = .GlobalEnv)
  captured_dataset <- brohn_ingest_dataset(store, mutable_upload, "Captured object authority", "ecg", origin = "sample")
  assign("brohn_store_object", original_store_object, envir = .GlobalEnv)
  check("preview uses exact captured object when upload path changes after capture", identical(enc2utf8(captured_dataset$body$preview[[1L]]$participant), "qa-\u00e9") &&
    identical(read_raw(brohn_object_path(store, captured_dataset$body$source$hash)), original_upload) && !identical(read_raw(mutable_upload), original_upload))
  check("synchronous imports created no jobs", DBI::dbGetQuery(store$con, "SELECT count(*) AS n FROM jobs")$n[[1L]] == 0L)

  expected_identity <- list("R/platform-publication.R" = .brohn_publication_r_hash,
    "R/platform-ingestion.R" = .brohn_ingestion_module_hash, "R/platform-tabular-preview.R" = .brohn_ingestion_preview_hash,
    "scripts/workers/ingestion_snapshot.py" = .brohn_ingestion_snapshot_hash,
    "scripts/workers/publication.py" = digest::digest(file = "scripts/workers/publication.py", algo = "sha256"),
    "src/publication_guard.c" = digest::digest(file = "src/publication_guard.c", algo = "sha256"))
  loaded <- expected_identity[c("R/platform-ingestion.R", "R/platform-tabular-preview.R", "scripts/workers/ingestion_snapshot.py")]
  check("queued publication identity includes the exact new decoder source", isTRUE(.brohn_publication_output_identity(list(code_identity = expected_identity), loaded)))
  wrong <- expected_identity; wrong[["R/platform-tabular-preview.R"]] <- paste(rep("0", 64L), collapse = "")
  refuse("foreign helper byte identity cannot publish queued intake", .brohn_publication_output_identity(list(code_identity = wrong), loaded))
  check("scientific reader and all test checkout source files remain byte-exact", identical(digest::digest(file = "R/platform-analysis.R", algo = "sha256"), scientific_reader_hash) &&
    all(vapply(hashes, function(s) identical(digest::digest(file = s$path, algo = "sha256"), s$sha256), logical(1))))
  brohn_close_store(store); closed <- TRUE
  passed <- TRUE
})
