for (module in c("study", "comparison", "presentation", "records", "json", "storage", "assets", "aois", "drafts", "analysis", "sample-analysis", "gaze-import", "import-report"))
  source(paste0("R/", module, ".R"))
local({
  directory <- tempfile("prepared-report-tests-")
  dir.create(directory)
  on.exit(unlink(directory, recursive = TRUE), add = TRUE)
  bundle <- revise_draft(create_draft("sample"), "Reproduction fixture", FALSE)
  csv <- file.path(directory, "original.csv")
  intervals <- sample_gaze_intervals(bundle)
  intervals$valid <- tolower(as.character(intervals$valid))
  write.table(intervals, csv, sep = ",", row.names = FALSE, na = "", fileEncoding = "UTF-8")
  report <- build_prepared_report(bundle, csv)
  stopifnot(report$origin == "imported_prepared", report$status == "unqualified",
    report$analysis$summary$mean_difference_pp == 20,
    identical(jsonlite::base64_dec(report$source$data_base64), readBin(csv, "raw", file.info(csv)$size)))
  path <- file.path(directory, "report.json")
  save_prepared_report(report, path)
  before <- readBin(path, "raw", file.info(path)$size)
  stopifnot(inherits(try(save_prepared_report(report, path), silent = TRUE), "try-error"),
    identical(before, readBin(path, "raw", file.info(path)$size)))
  parsed <- jsonlite::fromJSON(rawToChar(before), simplifyVector = FALSE)
  stopifnot(isTRUE(all.equal(read_prepared_report(path, local_limits = TRUE), report)))
  too_many_areas <- report
  too_many_areas$study$aois <- lapply(1:41, function(i) {
    area <- report$study$aois[[1]]; area$id <- paste0("area-", i); area$label <- paste("Area", i); area
  })
  larger <- file.path(directory, "larger.json")
  writeLines(prepared_report_to_json(too_many_areas), larger)
  stopifnot(inherits(try(read_prepared_report(larger, local_limits = TRUE), silent = TRUE), "try-error"))
  stopifnot(is.list(parsed$study$measures), identical(parsed$study$questions, list()),
    is.null(parsed$prepared_intervals[[3]]$x))
  reopened <- read_prepared_report(path)
  stopifnot(isTRUE(all.equal(reopened, report)),
    is.data.frame(reopened$prepared_intervals),
    is.data.frame(reopened$analysis$summary),
    identical(names(reopened$source), c("media_type", "encoding", "sha256", "byte_count", "row_count", "data_base64")))
  stale <- report; stale$analysis$summary$mean_difference_pp <- 999
  stopifnot(jsonlite::fromJSON(prepared_report_to_json(stale))$analysis$summary$mean_difference_pp == 20)
  corrupt <- report; corrupt$source$sha256 <- strrep("0", 64)
  stopifnot(inherits(try(prepared_report_to_json(corrupt), silent = TRUE), "try-error"))

  rejects <- function(expression) stopifnot(inherits(try(force(expression), silent = TRUE), "try-error"))
  wire_path <- file.path(directory, "modified.json")
  write_wire <- function(value) {
    writeBin(charToRaw(as.character(jsonlite::toJSON(value, auto_unbox = TRUE,
      null = "null", na = "null", digits = NA))), wire_path)
    wire_path
  }
  check_bad <- function(edit) {
    result <- try(read_prepared_report(write_wire(edit(parsed))), silent = TRUE)
    if (!inherits(result, "try-error")) stop("Expected rejection: ", paste(deparse(body(edit)), collapse = " "))
  }
  # Cached values, including their shapes and any claimed qualification, are
  # disposable; reopening restores tables and limitations from frozen inputs.
  cached <- parsed
  cached$prepared_intervals <- "stale"
  cached$analysis <- list(status = "qualified", summary = list(mean_difference_pp = 999))
  cached$limitations <- list("An unsupported cached claim")
  rebuilt <- read_prepared_report(write_wire(cached))
  stopifnot(isTRUE(all.equal(rebuilt, report)))
  for (edit in list(
    function(x) { x$schema_version <- "prepared-gaze-report/1.0.0"; x },
    function(x) { x$origin <- "sample"; x },
    function(x) { x$status <- "qualified"; x },
    function(x) { x$input_path <- "../original.csv"; x },
    function(x) { x$source$path <- "../original.csv"; x },
    function(x) { x$source$media_type <- "application/json"; x },
    function(x) { x$source$encoding <- "latin1"; x },
    function(x) { x$source$sha256 <- strrep("0", 64); x },
    function(x) { x$source$sha256 <- toupper(x$source$sha256); x },
    function(x) { x$source$sha256 <- "0"; x },
    function(x) { x$source$data_base64 <- paste0(x$source$data_base64, "\n"); x },
    function(x) { x$source$data_base64 <- "!!!!"; x },
    function(x) { x$source$data_base64 <- strrep("A", 7 * 1024^2 + 1); x },
    function(x) { x$source$data_base64 <- NULL; x },
    function(x) { x$source$byte_count <- as.character(x$source$byte_count); x },
    function(x) { x$source$byte_count <- x$source$byte_count + 1; x },
    function(x) { x$source$byte_count <- 5 * 1024^2 + 1; x },
    function(x) { x$source$row_count <- x$source$row_count + 1; x },
    function(x) { x$source$row_count <- list(x$source$row_count); x },
    function(x) { x$source$row_count <- 1.5; x },
    function(x) { x$source$row_count <- TRUE; x },
    function(x) { x$source$row_count <- 100001; x },
    function(x) { x$source <- "malformed"; x },
    function(x) { x$study$path <- "../study.json"; x },
    function(x) { x$study$analysis$extra <- TRUE; x },
    function(x) { x$study$revision <- 1e16; x },
    function(x) { x$study$conditions <- list("B", "A"); x },
    function(x) { x$study$measures <- "eye"; x },
    function(x) { x$study$questions <- list(unexpected = "object"); x },
    function(x) { x$study$stimulus_assets[[1]]$path <- "../image.png"; x },
    function(x) { x$limitations <- "scalar"; x },
    function(x) { x$limitations <- list(42); x },
    function(x) { x$analysis <- NULL; x },
    function(x) { c(x, list(status = "unqualified")) },
    function(x) { x$source <- c(x$source, list(encoding = "UTF-8")); x },
    function(x) { x$study <- c(x$study, list(id = "duplicate")); x }
  )) check_bad(edit)
  # A self-consistent hash still cannot make invalid CSV bytes acceptable.
  for (bad_byte in as.raw(c(0, 255))) {
    damaged <- parsed
    embedded <- jsonlite::base64_dec(damaged$source$data_base64)
    embedded[1] <- bad_byte
    damaged$source$sha256 <- digest::digest(embedded, algo = "sha256", serialize = FALSE)
    damaged$source$data_base64 <- jsonlite::base64_enc(embedded)
    rejects(read_prepared_report(write_wire(damaged)))
  }
  # Unknown properties must also be rejected by the serializer.
  extra <- report; extra$source$path <- csv
  rejects(prepared_report_to_json(extra))
  rejects(read_prepared_report(path, max_bytes = length(before) - 1L))
  for (limit in list(0, -1, 1.5, NA_real_, Inf, TRUE, "64", 64 * 1024^2 + 1))
    rejects(read_prepared_report(path, max_bytes = limit))
  for (bytes in list(raw(), as.raw(c(123, 0, 125)), as.raw(c(123, 34, 255, 34, 58, 49, 125)),
                     charToRaw("{broken"), charToRaw(path), charToRaw("[]"))) {
    writeBin(bytes, wire_path)
    rejects(read_prepared_report(wire_path))
  }
  oversize <- file.path(directory, "oversize.json")
  connection <- file(oversize, "wb")
  seek(connection, where = 64 * 1024^2, rw = "write")
  writeBin(as.raw(32), connection)
  close(connection)
  rejects(read_prepared_report(oversize))

  # Caller-selected lower import limits apply before a report can be built.
  stopifnot(isTRUE(all.equal(build_prepared_report(bundle, csv,
    max_bytes = report$source$byte_count, max_rows = report$source$row_count), report)))
  rejects(build_prepared_report(bundle, csv, max_bytes = report$source$byte_count - 1))
  rejects(build_prepared_report(bundle, csv, max_rows = report$source$row_count - 1))
  rejects(build_prepared_report(bundle, csv, max_bytes = 5 * 1024^2 + 1))
  rejects(build_prepared_report(bundle, csv, max_rows = 100001))

  # JSON and CSV quoting retain text as data, including newline and UTF-8 IDs.
  quoted_bundle <- revise_draft(bundle, 'A "quoted" <title> & caf\u00e9', FALSE)
  quoted_intervals <- intervals
  quoted_intervals$participant_id[quoted_intervals$participant_id == unique(intervals$participant_id)[1]] <-
    'p "quoted", caf\u00e9\nline'
  quoted_csv <- file.path(directory, "quoted.csv")
  write.table(quoted_intervals, quoted_csv, sep = ",", row.names = FALSE, na = "",
    fileEncoding = "UTF-8", qmethod = "double")
  quoted_report <- build_prepared_report(quoted_bundle, quoted_csv)
  quoted_path <- file.path(directory, "quoted-report.json")
  save_prepared_report(quoted_report, quoted_path)
  stopifnot(isTRUE(all.equal(read_prepared_report(quoted_path), quoted_report)))
  # Reproduction uses original bytes, even after the initial external CSV is gone.
  copied <- file.path(directory, "embedded.csv")
  unlink(csv)
  stopifnot(isTRUE(all.equal(read_prepared_report(path), report)))
  local({
    original_directory <- setwd(directory)
    on.exit(setwd(original_directory), add = TRUE)
    stopifnot(isTRUE(all.equal(read_prepared_report("report.json"), report)))
  })
  writeBin(jsonlite::base64_dec(parsed$source$data_base64), copied)
  recomputed <- read_prepared_gaze_csv(copied, .study_from_wire(parsed$study))
  stopifnot(isTRUE(all.equal(recomputed$analysis, report$analysis)))
  if (nzchar(Sys.getenv("CONTRACT_FIXTURE_DIR"))) {
    .write_draft_bytes(bundle_to_json(bundle), file.path(Sys.getenv("CONTRACT_FIXTURE_DIR"), "import-study.json"))
    file.copy(copied, file.path(Sys.getenv("CONTRACT_FIXTURE_DIR"), "import-gaze.csv"), overwrite = TRUE)
    writeLines(prepared_report_to_json(report), file.path(Sys.getenv("CONTRACT_FIXTURE_DIR"), "import-report.json"))
  }
})
cat("PASS: prepared reports reopen, validate bounded frozen inputs, replace cached tables and reproduce without source files\n")
