# Research-only upstream reproduction; run from the repository root with --vanilla.
# Optional --install writes only to ../../work/r-library-methods. No app integration.
args <- commandArgs(trailingOnly = TRUE)
methods_lib <- normalizePath("../../work", mustWork = TRUE)
methods_lib <- file.path(methods_lib, "r-library-methods")
dir.create(methods_lib, showWarnings = FALSE, recursive = TRUE)
.libPaths(c(methods_lib, normalizePath("../../work/r-library", mustWork = TRUE), .libPaths()))
commit <- "bb55d203a09eb6b942058d08f4df697bdb440486"
if ("--install" %in% args) {
  options(timeout = 180)
  zoom_archive <- tempfile(fileext = ".tar.gz")
  download.file("https://cloud.r-project.org/src/contrib/zoom_2.0.6.tar.gz", zoom_archive, mode = "wb")
  install.packages(zoom_archive, repos = NULL, type = "source", lib = methods_lib)
  upstream_zip <- tempfile(fileext = ".zip")
  download.file(paste0("https://codeload.github.com/tmalsburg/saccades/zip/", commit), upstream_zip, mode = "wb")
  unpacked <- tempfile("gaze-source-")
  dir.create(unpacked)
  unzip(upstream_zip, exdir = unpacked)
  source_dir <- file.path(unpacked, paste0("saccades-", commit), "saccades")
  install.packages(source_dir, repos = NULL, type = "source", lib = methods_lib)
}
stopifnot(as.character(packageVersion("saccades")) == "0.2.1",
          as.character(packageVersion("zoom")) == "2.0.6")
stopifnot(startsWith(normalizePath(find.package("saccades")), normalizePath(methods_lib)))
stopifnot(requireNamespace("jsonlite", quietly = TRUE), requireNamespace("digest", quietly = TRUE))
settings <- list(lambda = 6, smooth.coordinates = FALSE, smooth.saccades = TRUE)
fixture <- new.env(parent = emptyenv())
utils::data("samples", package = "saccades", envir = fixture)
samples <- fixture$samples
checks <- list()
check <- function(name, value) {
  checks[[name]] <<- isTRUE(value)
  if (!isTRUE(value)) stop(paste("Failed:", name), call. = FALSE)
}
method_functions <- c("detect.fixations", "detect.saccades", "aggregate.fixations", "label.blinks.artifacts")
method_code <- lapply(method_functions, function(name) {
  f <- getFromNamespace(name, "saccades")
  list(name = name, formals = formals(f), body = deparse(body(f)))
})
method_hash <- digest::digest(method_code, algo = "sha256")
check("pinned_detector_and_helpers", identical(method_hash, "26f3ac2176e74f40b4bfd01759bd9bdb3365352884ab66beca453b19930b1c16"))
check("documented_columns", all(c("time", "x", "y", "trial") %in% names(samples)))
check("finite_fixture_coordinates_and_times", all(is.finite(as.matrix(samples[c("time", "x", "y")]))))
check("nonmissing_trial_ids", all(!is.na(samples$trial)))
groups <- split(samples, samples$trial)
check("strictly_increasing_time_within_trial", all(vapply(groups, function(x) all(diff(x$time) > 0), logical(1))))
check("track_loss_sentinel_present", any(samples$x == 0 & samples$y == 0))

# Reproduce the package's complete bundled example without pretending its heuristic
# blink labels establish validity. Filtering spans row boundaries in upstream code.
started <- proc.time()[["elapsed"]]
direct <- do.call(saccades::detect.fixations, c(list(samples = samples), settings))
direct_elapsed <- proc.time()[["elapsed"]] - started

# Test-only seam: isolate one trial per call and refuse malformed coordinates/time.
# This deliberately does not silently delete missing samples and bridge the gap.
isolated <- function(x) {
  if (!all(c("time", "x", "y", "trial") %in% names(x))) stop("missing_columns")
  if (any(!is.finite(as.matrix(x[c("time", "x", "y")])))) stop("nonfinite_sample")
  if (length(unique(x$trial)) != 1L) stop("multiple_trials")
  if (any(diff(x$time) <= 0)) stop("nonincreasing_time")
  # Factors can retain unused levels and aggregate as integer codes upstream.
  x$trial <- as.character(x$trial)
  do.call(saccades::detect.fixations, c(list(samples = x), settings))
}
by_trial <- lapply(groups, isolated)
events <- do.call(rbind, by_trial)
check("nonempty_events", nrow(events) > 0L)
check("duration_equals_end_minus_start", all(events$dur == events$end - events$start))
check("finite_nonnegative_event_duration", all(is.finite(events$dur) & events$dur >= 0))
check("events_within_source_time_bounds", all(vapply(seq_along(groups), function(i) {
  x <- groups[[i]]; e <- by_trial[[i]]
  all(e$start >= min(x$time) & e$end <= max(x$time))
}, logical(1))))
check("event_coordinates_within_source_bounds", all(vapply(seq_along(groups), function(i) {
  x <- groups[[i]]; e <- by_trial[[i]]
  all(e$x >= min(x$x) & e$x <= max(x$x) & e$y >= min(x$y) & e$y <= max(x$y))
}, logical(1))))
check("events_do_not_overlap_within_trial", all(vapply(by_trial, function(e) {
  if (nrow(e) < 2L) return(TRUE)
  all(head(e$end, -1L) <= tail(e$start, -1L))
}, logical(1))))
check("group_identity_preserved", all(vapply(seq_along(groups), function(i) {
  all(by_trial[[i]]$trial == groups[[i]]$trial[1L])
}, logical(1))))
first <- groups[[1L]]
shifted <- first
shifted$time <- shifted$time + 100000
shifted_events <- isolated(shifted)
check("timestamp_translation_preserves_durations", identical(by_trial[[1L]]$dur, shifted_events$dur))
check("timestamp_translation_preserves_boundaries", all(shifted_events$start - 100000 == by_trial[[1L]]$start & shifted_events$end - 100000 == by_trial[[1L]]$end))
rejects <- function(x, expected) {
  result <- tryCatch({isolated(x); "accepted"}, error = function(e) conditionMessage(e))
  identical(result, expected)
}
missing <- first; missing$x[10L] <- NA_real_
check("missing_coordinate_rejected_without_bridging", rejects(missing, "nonfinite_sample"))
duplicate <- first; duplicate$time[10L] <- duplicate$time[9L]
check("duplicate_time_rejected", rejects(duplicate, "nonincreasing_time"))
check("mixed_trials_rejected", rejects(samples, "multiple_trials"))
check("reversed_time_rejected", rejects(first[nrow(first):1L, ], "nonincreasing_time"))

# Missingness is a raw-data quality summary, not a claim that sentinel intervals
# were excluded from the detector above. The final sample has no inferred tail.
track_loss_duration <- sum(vapply(groups, function(x) {
  lost <- x$x == 0 & x$y == 0
  sum(diff(x$time)[head(lost, -1L)])
}, numeric(1)))
recorded_duration <- sum(vapply(groups, function(x) diff(range(x$time)), numeric(1)))
check("track_loss_duration_bounded_by_observed_duration", track_loss_duration >= 0 && track_loss_duration <= recorded_duration)
summary_events <- function(x) list(
  event_count = nrow(x), event_label_counts = as.list(table(x$event)),
  zero_duration_events = sum(x$dur == 0),
  total_event_duration_ms = sum(x$dur),
  fixation_count = sum(x$event == "fixation"),
  fixation_duration_ms = sum(x$dur[x$event == "fixation"]),
  median_fixation_duration_ms = unname(median(x$dur[x$event == "fixation"]))
)
out <- list(
  schema = "gaze-reference-benchmark/0.1.0", recorded_date = "2026-09-08",
  status = "research_reference_only_unqualified",
  execution = list(r_version = as.character(getRversion()), platform = R.version$platform),
  package = list(name = "saccades", version = as.character(packageVersion("saccades")),
    upstream_commit = commit, license = "GPL-2", dependency_zoom = as.character(packageVersion("zoom")),
    detector_and_helpers_sha256 = method_hash),
  settings = settings,
  fixture = list(source = paste0("https://github.com/tmalsburg/saccades/tree/", commit, "/saccades"),
    name = "samples", kind = "bundled_upstream_recording_not_independently_labelled_ground_truth",
    raw_data_in_repository = FALSE, time_unit = "ms", coordinates = "screen_pixels",
    sample_object_sha256 = digest::digest(samples, algo = "sha256"),
    samples = nrow(samples), trials = length(groups),
    within_trial_step_range_ms = range(unlist(lapply(groups, function(x) diff(x$time)))),
    recorded_duration_ms = recorded_duration,
    track_loss_sentinel = "x==0 and y==0 is fixture-specific; do not generalize",
    track_loss_sample_count = sum(samples$x == 0 & samples$y == 0),
    track_loss_observed_interval_duration_ms = track_loss_duration),
  direct_upstream = c(summary_events(direct), list(elapsed_seconds = unname(direct_elapsed))),
  isolated_trials = summary_events(events),
  checks = checks, passed = all(unlist(checks)),
  limitations = c("Upstream blink/artifact labels are heuristic; no calibration or device qualification.",
    "Raw track-loss sentinels remain in this upstream reproduction; this is not a cleaned valid-gaze recipe.",
    "One-call and trial-isolated outputs may differ because upstream filtering and thresholds share samples.",
    "No stimulus mapping, AOI results, prepared-interval import, or physiological interpretation is asserted.",
    "Function hash records the installed detector; version number alone does not identify the upstream revision.")
)
destination <- "docs/methods/reuse/gaze-reference-results.json"
dir.create(dirname(destination), showWarnings = FALSE, recursive = TRUE)
jsonlite::write_json(out, destination, pretty = TRUE, auto_unbox = TRUE, digits = 17, null = "null")
cat(sprintf("Gaze reference: %d checks passed; %d source samples; %d isolated fixation events.\n", length(checks), nrow(samples), sum(events$event == "fixation")))
