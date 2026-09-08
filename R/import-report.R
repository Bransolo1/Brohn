# Portable derived artifact. Original CSV bytes and a frozen study travel with it.
build_prepared_report <- function(bundle, csv_path, max_bytes = 5 * 1024^2,
                                  max_rows = 100000, max_participants = Inf) {
  record_assert(!length(validate_bundle(bundle)), "A valid study bundle is required.")
  record_assert(.prepared_report_limit(max_bytes, 5 * 1024^2) &&
    .prepared_report_limit(max_rows, 100000), "Prepared report: invalid CSV limits.")
  imported <- read_prepared_gaze_csv(csv_path, bundle$study,
    max_bytes = max_bytes, max_rows = max_rows, max_participants = max_participants)
  connection <- file(csv_path, "rb")
  on.exit(close(connection), add = TRUE)
  bytes <- readBin(connection, "raw", n = max_bytes + 1)
  record_assert(length(bytes) <= max_bytes && length(bytes) == imported$byte_count &&
    identical(digest::digest(bytes, algo = "sha256", serialize = FALSE), imported$source_sha256),
    "The CSV changed during import; try again with a stable file.")
  list(schema_version = "prepared-gaze-report/0.1.0", origin = "imported_prepared",
    status = "unqualified", study = bundle$study,
    source = list(media_type = "text/csv", encoding = "UTF-8", sha256 = imported$source_sha256,
      byte_count = imported$byte_count, row_count = imported$row_count,
      data_base64 = jsonlite::base64_enc(bytes)),
    prepared_intervals = imported$intervals, analysis = imported$analysis,
    limitations = .prepared_report_limitations())
}

.prepared_report_limit <- function(value, maximum) {
  is.numeric(value) && !is.complex(value) && length(value) == 1L &&
    !is.na(value) && is.finite(value) && value >= 1 &&
    value == floor(value) && value <= maximum
}

.prepared_report_fields <- c("schema_version", "origin", "status", "study", "source",
  "prepared_intervals", "analysis", "limitations")

.prepared_report_limitations <- function() {
  c("Imported prepared intervals; source recording origin is not independently verified.",
    "No raw-device preprocessing, exposure registry, calibration or clock alignment is implemented.",
    "The draft method is unqualified; no inferential or causal claim.",
    "Presentation settings describe the design plan, not observed delivery.")
}

# Both encoding and reopening validate the frozen inputs and rebuild derived values.
# The temporary validation bundle is never stored in the imported report.
.normalize_prepared_report <- function(report, local_limits = FALSE) {
  withCallingHandlers({
    record_assert(is.logical(local_limits) && length(local_limits) == 1L && !is.na(local_limits), "Choose valid local report limits.")
    record_assert(record_fields(report, .prepared_report_fields), "Prepared report: fields.")
    record_assert(identical(report$schema_version, "prepared-gaze-report/0.1.0") &&
      identical(report$origin, "imported_prepared") && identical(report$status, "unqualified"),
      "An unqualified prepared-data report is required.")
    new_bundle(report$study,
      new_session(report$study, "prepared-report-validation", "not-enrolled", "preview"))
    record_assert(record_fields(report$source,
      c("media_type", "encoding", "sha256", "byte_count", "row_count", "data_base64")),
      "Prepared report: source fields.")
    record_assert(identical(report$source$media_type, "text/csv") &&
      identical(report$source$encoding, "UTF-8"), "Prepared report: CSV media type and UTF-8 encoding required.")
    record_assert(scalar_text(report$source$sha256) &&
      grepl("\\A[0-9a-f]{64}\\z", report$source$sha256, perl = TRUE) &&
      .prepared_report_limit(report$source$byte_count, 5 * 1024^2) &&
      .prepared_report_limit(report$source$row_count, 100000),
      "Prepared report: invalid source hash or counters.")
    record_assert(is.character(report$limitations) && length(report$limitations) > 0L &&
      all(vapply(report$limitations, scalar_text, logical(1))), "Prepared report: limitations array required.")
    record_assert(scalar_text(report$source$data_base64) && nchar(report$source$data_base64, type = "bytes") <= 7 * 1024^2,
      "The embedded CSV is missing or too large.")
    record_assert(!grepl("[^A-Za-z0-9+/=\n]", report$source$data_base64),
      "The embedded CSV requires canonical base64.")
    bytes <- jsonlite::base64_dec(report$source$data_base64)
    record_assert(identical(jsonlite::base64_enc(bytes), report$source$data_base64) &&
      length(bytes) <= 5 * 1024^2 && length(bytes) == report$source$byte_count &&
      identical(digest::digest(bytes, algo = "sha256", serialize = FALSE), report$source$sha256),
      "The embedded CSV does not match its content hash or byte count.")
    csv <- tempfile(fileext = ".csv")
    on.exit(unlink(csv), add = TRUE)
    writeBin(bytes, csv)
    if (local_limits) record_assert(length(report$study$aois) <= 40, "Local reports support up to 40 areas.")
    imported <- read_prepared_gaze_csv(csv, report$study,
      max_bytes = if (local_limits) 1024^2 else 5 * 1024^2,
      max_rows = if (local_limits) 20000 else 100000,
      max_participants = if (local_limits) 500 else Inf)
    record_assert(imported$row_count == report$source$row_count, "The CSV row count does not match the source record.")
    # Derived tables are replaceable; original source bytes are the authority.
    report$prepared_intervals <- imported$intervals
    report$analysis <- imported$analysis
    report$limitations <- .prepared_report_limitations()
    report
  }, warning = function(w) stop("Prepared report: ", conditionMessage(w), call. = FALSE))
}

prepared_report_to_json <- function(report, pretty = FALSE) {
  report <- .normalize_prepared_report(report)
  report$study <- .study_to_wire(report$study)
  report$limitations <- I(report$limitations)
  as.character(jsonlite::toJSON(report, auto_unbox = TRUE, dataframe = "rows",
    na = "null", null = "null", digits = 17, pretty = pretty))
}

read_prepared_report <- function(path, max_bytes = 64 * 1024^2, local_limits = FALSE) {
  withCallingHandlers({
    record_assert(.prepared_report_limit(max_bytes, 64 * 1024^2),
      "Prepared report: byte limit must be a positive integer up to 64 MiB.")
    record_assert(scalar_text(path) && file.exists(path) && !dir.exists(path),
      "Prepared report: choose a readable file.")
    size <- file.info(path)$size
    record_assert(!is.na(size) && size > 0 && size <= max_bytes,
      "Prepared report: empty file or byte limit exceeded.")
    connection <- file(path, "rb")
    on.exit(close(connection), add = TRUE)
    bytes <- readBin(connection, "raw", n = max_bytes + 1)
    record_assert(length(bytes) == size && length(bytes) <= max_bytes,
      "Prepared report: file changed while reading or byte limit exceeded.")
    record_assert(!any(bytes == as.raw(0)), "Prepared report: NUL bytes are not allowed.")
    text <- rawToChar(bytes)
    record_assert(!is.na(iconv(text, from = "UTF-8", to = "UTF-8", sub = NA)),
      "Prepared report: valid UTF-8 required.")
    Encoding(text) <- "UTF-8"
    # Validate JSON text before fromJSON, which can otherwise interpret a string
    # as an external filename or URL. Reports never load referenced input paths.
    record_assert(jsonlite::validate(text), "Prepared report: valid JSON required.")
    report <- jsonlite::fromJSON(text, simplifyVector = FALSE)
    record_assert(record_fields(report, .prepared_report_fields), "Prepared report: fields.")
    report$study <- .study_from_wire(report$study)
    report$limitations <- .wire_array_vector(report$limitations, "character")
    .normalize_prepared_report(report, local_limits = local_limits)
  }, warning = function(w) stop("Prepared report: ", conditionMessage(w), call. = FALSE))
}

save_prepared_report <- function(report, path) {
  text <- prepared_report_to_json(report, pretty = TRUE)
  record_assert(scalar_text(path) && dir.exists(dirname(path)), "Choose an existing destination folder.")
  path <- file.path(normalizePath(dirname(path), winslash = "/", mustWork = TRUE), basename(path))
  lock <- paste0(path, ".lock")
  record_assert(dir.create(lock, showWarnings = FALSE), "Another report save holds this destination lock.")
  on.exit(unlink(lock, recursive = TRUE), add = TRUE)
  record_assert(!file.exists(path), "A file already exists here. Choose a new report filename.")
  .atomic_draft_replace(text, path)
  invisible(path)
}
