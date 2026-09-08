# Local synthetic fixtures only; independent 20 percentage point arithmetic.
source("R/study.R")
source("R/records.R")
source("R/assets.R")
source("R/aois.R")
source("R/analysis.R")
source("R/gaze-import.R")

local({
  checks <- 0L
  expect <- function(ok) {
    if (!isTRUE(ok)) stop(sprintf("prepared CSV check %d failed", checks + 1L))
    checks <<- checks + 1L
  }
  rejects <- function(expression, pattern) {
    message <- tryCatch({ force(expression); "" }, error = function(e) conditionMessage(e))
    nzchar(message) && grepl(pattern, message, fixed = TRUE)
  }
  directory <- tempfile("gaze-import-")
  dir.create(directory)
  on.exit(unlink(directory, recursive = TRUE), add = TRUE)
  png_path <- file.path(directory, "stimulus.png")
  png::writePNG(array(seq(0, 1, length.out = 18), c(3, 2, 3)), png_path)
  study <- new_study(include_liking = FALSE)
  study$stimulus_assets <- lapply(study$stimulus_ids, function(id) new_png_asset(png_path, id))
  study$aois <- lapply(seq_along(study$stimulus_ids), function(side) {
    new_rectangle_aoi(study, study$stimulus_ids[side], "Logo", 0, 0, 0.5, 1,
      id = paste0("logo-", side))
  })
  header <- "participant_id,stimulus_id,start_ms,end_ms,x,y,valid,phase"
  rows <- c("001,stimulus-a,0,20,0.25,0.25,true,passive_viewing",
    "001,stimulus-a,20,100,0.75,0.25,true,passive_viewing",
    "001,stimulus-b,0,40,0.25,0.25,true,passive_viewing",
    "001,stimulus-b,40,100,0.75,0.25,true,passive_viewing",
    "001,stimulus-a,100,150,,,false,passive_viewing",
    "001,stimulus-a,150,200,0.25,0.25,true,active_response")
  fixture <- paste(c(header, rows), collapse = "\n")
  path <- file.path(directory, "prepared.csv")
  write_fixture <- function(value = fixture) {
    if (!is.raw(value)) value <- charToRaw(enc2utf8(value))
    writeBin(value, path)
    path
  }
  read_fixture <- function(value = fixture, ...) {
    tryCatch(read_prepared_gaze_csv(write_fixture(value), study, ...),
      error = function(e) stop(sprintf("After %d checks: %s", checks, conditionMessage(e)),
        call. = FALSE))
  }
  result <- read_fixture()
  expect(identical(names(result), c("schema_version", "source_sha256", "byte_count",
    "row_count", "intervals", "analysis", "origin", "status")))
  expect(identical(result$schema_version, "prepared-gaze-import/0.1.0") &&
    identical(result$origin, "imported_prepared") && identical(result$status, "unqualified"))
  expect(result$byte_count == nchar(fixture, type = "bytes") && result$row_count == 6L &&
    identical(result$source_sha256, digest::digest(charToRaw(fixture),
      algo = "sha256", serialize = FALSE)))
  expect(identical(result$intervals$participant_id, rep("001", 6L)))
  expect(is.na(result$intervals$x[5L]) && is.na(result$intervals$y[5L]) &&
    identical(result$intervals$valid, c(TRUE, TRUE, TRUE, TRUE, FALSE, TRUE)))
  expect(identical(result$analysis$status, "unqualified") &&
    result$analysis$pairs$share_pct_a == 20 && result$analysis$pairs$share_pct_b == 40 &&
    result$analysis$summary$mean_difference_pp == 20)
  expect(identical(result$analysis, analyze_gaze_intervals(study, result$intervals)))
  expect(identical(read_fixture(paste0(gsub("\n", "\r\n", fixture), "\r\n"))$intervals,
    result$intervals))
  expect(identical(read_fixture(paste0(fixture, "\n"))$intervals, result$intervals))
  utf8_id <- paste0("001-", intToUtf8(c(233, 945)), ",\"id\"\r\n next ")
  quoted_id <- paste0('"', gsub('"', '""', utf8_id, fixed = TRUE), '"')
  special <- read_fixture(gsub("001", quoted_id, fixture, fixed = TRUE))
  expect(identical(special$intervals$participant_id, rep(utf8_id, 6L)))
  expect(identical(read_fixture(gsub("001", " 001 ", fixture, fixed = TRUE))$
    intervals$participant_id, rep(" 001 ", 6L)))
  reordered <- paste(c(paste(rev(strsplit(header, ",", fixed = TRUE)[[1L]]), collapse = ","),
    vapply(strsplit(rows, ",", fixed = TRUE), function(x) paste(rev(x), collapse = ","),
      character(1))), collapse = "\n")
  expect(identical(read_fixture(reordered)$intervals, result$intervals))

  bad_header <- c(sub("participant_id", "participant", header),
    sub("stimulus_id", "participant_id", header), paste0(header, ",duration_ms"),
    sub(",phase", "", header), sub("participant_id", " participant_id", header))
  for (value in bad_header) expect(rejects(read_fixture(paste(value, rows[1L], sep = "\n")),
    if (length(strsplit(value, ",", fixed = TRUE)[[1L]]) == 8L) "header" else "eight fields"))
  for (value in c(paste0(rows[1L], ",extra"), sub(",passive_viewing", "", rows[1L]),
    paste0('"', rows[1L]), sub("001", '00"1', rows[1L]),
    sub("001", '"001"tail', rows[1L]), paste0(rows[1L], '\n"unfinished'),
    paste0(rows[1L], "\n"), paste0(rows[1L], "\rgarbage"))) {
    # An extra newline becomes a blank record here because a further row follows.
    expect(rejects(read_fixture(paste(header, value, rows[3L], sep = "\n")), "prepared CSV:"))
  }
  expect(rejects(read_fixture(raw()), "empty file"))
  expect(rejects(read_fixture(header), "at least one data row"))
  expect(rejects(read_fixture(c(charToRaw(fixture), as.raw(0))), "NUL"))
  expect(rejects(read_fixture(c(charToRaw(fixture), as.raw(255))), "UTF-8"))
  expect(rejects(read_fixture(c(as.raw(c(239, 187, 191)), charToRaw(fixture))), "header"))
  expect(rejects(read_fixture(max_bytes = nchar(fixture, type = "bytes") - 1L), "byte limit"))
  expect(read_fixture(max_bytes = nchar(fixture, type = "bytes"), max_rows = 6)$row_count == 6L)
  expect(rejects(read_fixture(max_rows = 5), "limit"))
  expect(identical(read_fixture(max_participants = 1), result) &&
    identical(read_fixture(max_participants = Inf), result))
  two_participants <- paste(c(header, rows, sub("001", " 001 ", rows, fixed = TRUE)),
    collapse = "\n")
  expect(read_fixture(two_participants, max_participants = 2)$analysis$
    summary$complete_pair_count == 2L)
  expect(rejects(read_fixture(two_participants, max_participants = 1), "participant limit"))
  expect(rejects(read_prepared_gaze_csv(write_fixture(two_participants), list(),
    max_participants = 1), "participant limit")) # Before invoking the kernel.
  for (limit in list(0, -1, -Inf, 1.5, NA_real_, "100", TRUE, numeric(), 1+1i, c(1, 2))) {
    expect(rejects(read_fixture(max_participants = limit), "max_participants must be"))
  }
  for (limit in list(0, -1, 1.5, NA_real_, Inf, "100", TRUE, numeric(), 1+1i)) {
    expect(rejects(read_fixture(max_bytes = limit), "positive integer limits"))
    expect(rejects(read_fixture(max_rows = limit), "positive integer limits"))
  }
  single <- function(start = "0", end = "20", x = "0.25", y = "0.25",
                     valid = "true", phase = "passive_viewing", id = "001", stimulus = "stimulus-a") {
    paste(header, paste(id, stimulus, start, end, x, y, valid, phase, sep = ","), sep = "\n")
  }
  for (value in c("NA", "NaN", "Inf", "-Inf", "1e2", "0x10", " 1", "1 ", "1,2", ".", "--1",
                  '"1\n"', '"1\r\n"', '"1\t"')) {
    expect(rejects(read_fixture(single(start = value)), "prepared CSV:"))
    expect(rejects(read_fixture(single(x = value, valid = "false")), "prepared CSV:"))
  }
  expect(rejects(read_fixture(single(end = strrep("9", 400))), "must be finite"))
  expect(rejects(read_fixture(single(start = "")), "strict decimal"))
  expect(rejects(read_fixture(single(x = "")), "normalized image coordinates"))
  expect(is.na(read_fixture(single(x = "", y = "", valid = "false"))$intervals$x))
  expect(is.na(read_fixture(single(x = '""', y = '""', valid = "false"))$intervals$x))
  expect(identical(read_fixture(single(id = "NA"))$intervals$participant_id, "NA"))
  expect(rejects(read_fixture(single(phase = "")), "phase must be"))
  expect(read_fixture(single(start = "+0.0", end = "20.", x = ".25"))$intervals$x == 0.25)
  for (value in c("TRUE", "FALSE", "1", "0", "True", "true ", "", "NA")) {
    expect(rejects(read_fixture(single(valid = value)), "lowercase true or false"))
  }
  expect(rejects(read_fixture(single(phase = "fixation")), "phase must be"))
  expect(rejects(read_fixture(single(start = "-1")), "finite nonnegative times"))
  expect(rejects(read_fixture(single(start = "20")), "finite nonnegative times"))
  expect(rejects(read_fixture(single(end = "0")), "finite nonnegative times"))
  expect(rejects(read_fixture(single(x = "1.01")), "normalized image coordinates"))
  expect(rejects(read_fixture(single(stimulus = "unknown")), "unknown stimulus"))
  expect(rejects(read_fixture(single(id = " ")), "nonempty participant"))
  expect(rejects(read_fixture(paste(c(header, rows, rows[1L]), collapse = "\n")), "overlapping"))
  expect(rejects(read_fixture(sub("20,100", "19,100", fixture, fixed = TRUE)), "overlapping"))
  bad_study <- study; bad_study$aois[[1L]]$asset_sha256 <- strrep("0", 64)
  expect(rejects(read_prepared_gaze_csv(write_fixture(), bad_study), "binding mismatch"))
  expect(rejects(read_prepared_gaze_csv(write_fixture(), list()), "schema_version"))
  cat(sprintf("PASS: %d canonical prepared CSV checks (unqualified draft)\n", checks))
})
