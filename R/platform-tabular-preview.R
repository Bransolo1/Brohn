# Completeness only: R's native parser owns quote/record semantics. No values
# from this check replace read.table's result. Stop at header plus20 records.
.brohn_tabular_preview_complete <- function(path, format, blank_lines_skip) {
  prefix <- local({con <- file(path, "rb"); on.exit(close(con)); readBin(con, "raw", 3L)})
  connection <- file(path, "r"); on.exit(close(connection))
  if (identical(prefix, as.raw(c(0xef, 0xbb, 0xbf)))) seek(connection, where = 3L, origin = "start")
  records <- 0L
  withCallingHandlers(while (records < 21L) {
    before <- seek(connection, where = NA)
    fields <- scan(connection, what = "", sep = if (format == "csv") "," else "\t",
      quote = "\"", nlines = 1L, quiet = TRUE, strip.white = FALSE,
      blank.lines.skip = blank_lines_skip, na.strings = character(), comment.char = "",
      allowEscapes = FALSE, encoding = "UTF-8", skipNul = FALSE)
    if (length(fields)) {
      records <- records + 1L
    } else {
      after <- seek(connection, where = NA)
      if (identical(before, after)) break
      # A skipped blank record advances the file; EOF does not. Never count
      # skipped records or continue a zero-progress EOF loop.
      brohn_require(is.finite(after) && after > before, "The tabular preview cannot track its bounded records.")
    }
  }, warning = function(warning) {
    message <- conditionMessage(warning)
    if (grepl("embedded nul|EOF within quoted|invalid input|invalid multibyte|incomplete multibyte|number of items read", message, ignore.case = TRUE))
      brohn_stop(paste("The tabular preview cannot be read without changing its contents:", message))
  })
  invisible(NULL)
}

# Bounded intake display only. Scientific readers and source bytes are unchanged.
brohn_tabular_preview <- function(path, format, blank_lines_skip = TRUE) {
  brohn_require(is.character(format) && length(format) == 1L && !is.na(format) &&
    format %in% c("csv", "tsv"), "This preview needs a CSV or TSV source.")
  brohn_require(is.logical(blank_lines_skip) && length(blank_lines_skip) == 1L &&
    !is.na(blank_lines_skip), "Declare the preview's blank-line policy.")
  prefix <- local({con <- file(path, "rb"); on.exit(close(con)); readBin(con, "raw", 3L)})
  connection <- file(path, "r"); on.exit(close(connection), add = TRUE)
  if (identical(prefix, as.raw(c(0xef, 0xbb, 0xbf)))) seek(connection, where = 3L, origin = "start")
  # Mark retained source bytes as UTF-8; fileEncoding would convert them to the
  # process locale and can reject/alter valid text under the normal Windows C
  # locale. Keep each caller's existing blank-line and derived fill behavior.
  incomplete_line <- FALSE
  data <- withCallingHandlers(utils::read.table(connection, header = TRUE,
    sep = if (format == "csv") "," else "\t", nrows = 20L, colClasses = "character",
    check.names = FALSE, comment.char = "", quote = "\"", encoding = "UTF-8",
    na.strings = character(), blank.lines.skip = blank_lines_skip), warning = function(warning) {
      message <- conditionMessage(warning)
      if (grepl("incomplete final line found by readTableHeader", message, fixed = TRUE)) {
        incomplete_line <<- TRUE
        invokeRestart("muffleWarning")
      }
      if (grepl("embedded nul|EOF within quoted|invalid input|invalid multibyte|incomplete multibyte|number of items read", message, ignore.case = TRUE))
        brohn_stop(paste("The tabular preview cannot be read without changing its contents:", message))
    })
  # readTableHeader can drop an unfinished quoted record and issue only this
  # warning. A valid final record without newline issues it too; native scan
  # distinguishes them without requiring a newline or reconstructing the table.
  if (incomplete_line) .brohn_tabular_preview_complete(path, format, blank_lines_skip)
  brohn_require(all(validUTF8(names(data))) && all(vapply(data, function(column) all(validUTF8(column)), logical(1))),
    "The tabular preview contains malformed UTF-8. Preserve the original and export a valid UTF-8 CSV or TSV.")
  brohn_require(ncol(data) > 0L && ncol(data) <= 1024L && !anyDuplicated(names(data)) && all(nzchar(names(data))),
    "Data columns must have unique nonempty names.")
  # Header-only sources remain reviewable. This is at most20 parsed records;
  # successfully displaying them makes no whole-file validation claim.
  data
}
