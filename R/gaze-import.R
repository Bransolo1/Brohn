# Canonical prepared intervals only: milliseconds and normalized coordinates.
# No device parsing, sampling assumptions, unit conversion or qualification.
read_prepared_gaze_csv <- function(path, study, max_bytes = 5 * 1024^2,
                                   max_rows = 100000, max_participants = Inf) {
  withCallingHandlers({
    a <- record_assert
    limit <- function(x) is.numeric(x) && !is.complex(x) && length(x) == 1L && !is.na(x) &&
      is.finite(x) && x >= 1 && x == floor(x) && x < .Machine$integer.max
    a(limit(max_bytes) && limit(max_rows), "prepared CSV: positive integer limits required")
    a(is.numeric(max_participants) && !is.complex(max_participants) &&
      length(max_participants) == 1L && !is.na(max_participants) &&
      max_participants >= 1 && (is.infinite(max_participants) ||
        max_participants == floor(max_participants)),
      "prepared CSV: max_participants must be Inf or a positive integer")
    a(scalar_text(path) && file.exists(path) && !dir.exists(path),
      "prepared CSV: choose a readable file")
    size <- file.info(path)$size
    a(!is.na(size) && size > 0 && size <= max_bytes,
      "prepared CSV: empty file or byte limit exceeded")
    connection <- file(path, open = "rb")
    on.exit(close(connection), add = TRUE)
    bytes <- readBin(connection, "raw", n = max_bytes + 1)
    a(length(bytes) == size && length(bytes) <= max_bytes,
      "prepared CSV: file changed while reading or byte limit exceeded")
    a(!any(bytes == as.raw(0)), "prepared CSV: NUL bytes are not allowed")
    text <- rawToChar(bytes)
    a(!is.na(iconv(text, from = "UTF-8", to = "UTF-8", sub = NA)),
      "prepared CSV: valid UTF-8 required")
    Encoding(text) <- "UTF-8"

    # Each match starts exactly where the previous field ended. Quoting must
    # enclose the entire field; only doubled quotes escape quotes. Complete
    # final records need no newline. Bare CR separators and recovery are forbidden.
    grammar <- '\\G(?:"[^"]*(?:""[^"]*)*"|[^",\\r\\n]*)(?:,|\\r?\\n|\\z)'
    positions <- gregexpr(grammar, text, perl = TRUE, useBytes = TRUE)[[1L]]
    widths <- attr(positions, "match.length")
    a(positions[1L] == 1L && sum(widths) == length(bytes),
      "prepared CSV: malformed or incomplete CSV quoting/record")
    # Bound token work before extracting fields or copying the match vectors.
    # gregexpr may include one zero-width match at the end of the file.
    a(length(positions) <= 8 * (max_rows + 1) + 1,
      "prepared CSV: row or field limit exceeded")
    # A final comma contributes a real empty field. A final newline does not.
    keep <- widths > 0L
    positions <- positions[keep]; widths <- widths[keep]
    if (bytes[length(bytes)] == as.raw(44)) {
      positions <- c(positions, length(bytes) + 1); widths <- c(widths, 0L)
    }
    a(length(positions) <= 8 * (max_rows + 1), "prepared CSV: row or field limit exceeded")
    endings <- positions + widths - 1L
    record_ends <- which(widths > 0L & bytes[endings] == as.raw(10))
    if (!length(record_ends) || tail(record_ends, 1L) != length(positions)) {
      record_ends <- c(record_ends, length(positions))
    }
    a(all(diff(c(0L, record_ends)) == 8L),
      "prepared CSV: every record must have exactly eight fields")
    row_count <- length(record_ends) - 1L
    a(row_count >= 1L && row_count <= max_rows,
      "prepared CSV: at least one data row required and row limit must not be exceeded")
    attr(positions, "match.length") <- widths
    attr(positions, "useBytes") <- TRUE
    attr(positions, "index.type") <- "bytes"
    fields <- regmatches(text, list(positions))[[1L]]
    Encoding(fields) <- "UTF-8"
    fields <- sub('(,|\\r?\\n)$', "", fields, perl = TRUE)
    quoted <- startsWith(fields, '"')
    fields[quoted] <- gsub('""', '"',
      substring(fields[quoted], 2L, nchar(fields[quoted]) - 1L), fixed = TRUE)
    headers <- fields[seq_len(8L)]
    expected <- c("participant_id", "stimulus_id", "start_ms", "end_ms", "x", "y", "valid", "phase")
    a(!anyDuplicated(headers) && setequal(headers, expected),
      "prepared CSV: exact header names required; duplicate, unknown or missing headers")
    intervals <- as.data.frame(matrix(fields[-seq_len(8L)], ncol = 8L, byrow = TRUE,
      dimnames = list(NULL, headers)), stringsAsFactors = FALSE, check.names = FALSE)
    intervals <- intervals[, expected, drop = FALSE]
    decimal <- function(values, name, allow_blank = FALSE) {
      blank <- values == ""
      a(all((allow_blank & blank) |
          grepl("\\A[+-]?(?:[0-9]+(?:\\.[0-9]*)?|\\.[0-9]+)\\z", values, perl = TRUE)),
        paste0("prepared CSV: ", name, " requires strict decimal numbers",
          if (allow_blank) " or blank" else ""))
      parsed <- rep(NA_real_, length(values))
      parsed[!blank] <- as.numeric(values[!blank])
      a(all(is.finite(parsed[!blank])), paste0("prepared CSV: ", name, " must be finite"))
      parsed
    }
    for (name in c("start_ms", "end_ms", "x", "y")) {
      intervals[[name]] <- decimal(intervals[[name]], name, name %in% c("x", "y"))
    }
    a(all(intervals$valid %in% c("true", "false")),
      "prepared CSV: valid must be exactly lowercase true or false")
    intervals$valid <- intervals$valid == "true"
    a(length(unique(intervals$participant_id)) <= max_participants,
      "prepared CSV: participant limit exceeded")
    analysis <- analyze_gaze_intervals(study, intervals)
    list(schema_version = "prepared-gaze-import/0.1.0",
      source_sha256 = digest::digest(bytes, algo = "sha256", serialize = FALSE),
      byte_count = length(bytes), row_count = row_count, intervals = intervals,
      analysis = analysis, origin = "imported_prepared", status = "unqualified")
  }, warning = function(w) stop("prepared CSV: ", conditionMessage(w), call. = FALSE))
}
