# Actual catalog -> peripheral child -> immutable artifacts -> signal explorer.
source("R/platform-load.R"); brohn_load(ui = TRUE)
local({
  checks <- 0L
  check <- function(name, ok) {if (!isTRUE(ok)) stop("Peripheral integration QA: ", name, call. = FALSE); checks <<- checks+1L}
  rejects <- function(expr) inherits(try(force(expr), silent = TRUE), "try-error")
  root <- tempfile("brohn-peripheral-integration-"); dir.create(root); root <- normalizePath(root, winslash = "/")
  store <- brohn_open_store(file.path(root, "workspace")); brohn_initialise_library(store)
  on.exit({brohn_close_store(store); actual <- normalizePath(root, winslash = "/", mustWork = FALSE)
    stopifnot(startsWith(tolower(actual), paste0(tolower(normalizePath(tempdir(), winslash = "/")), "/")), grepl("^brohn-peripheral-integration-", basename(actual)))
    unlink(actual, recursive = TRUE, force = TRUE)}, add = TRUE)
  rows <- data.frame(time = c(0,1,2,3,4,5,10,11,0,1,2,0,1), temperature = c(20,21,22,NA,24,25,30,31,40,41,42,50,51),
    person = c(rep("original-p",11),rep("original-q",2)), visit = "original-visit", reset = c(rep("first",8),rep("reset",5)),
    condition = c(rep("original-control",8),rep("original-test",5)), exposure = c(rep("original-a",8),rep("original-b",3),rep("original-c",2)))
  path <- file.path(root, "original-temperature.csv"); utils::write.csv(rows, path, row.names = FALSE, na = "", fileEncoding = "UTF-8")
  m <- list(time_column = "time", time_unit = "s", sampling_rate = 1, value_columns = list("temperature"), unit = "degC",
    participant_column = "person", session_column = "visit", segment_column = "reset", condition_column = "condition", exposure_column = "exposure",
    origin_statement = "Original synthetic thermal arithmetic with a missing sample, clock gap, declared reset and different person code.",
    calibration_source = "Original generator emits degrees Celsius.", sensor_site = "Original synthetic site", acquisition_filters = "None; original generator.",
    recording_conditions = "Original numerical fixture; no physical ambient, sensor contact or equilibration exposure.",
    parameters = list(threshold = list(metric = "temperature_c", direction = "above", on = 21, off = 20, minimum_duration_s = 1,
      source = "Original operational threshold for independent interval/censoring arithmetic.")))
  dataset <- brohn_ingest_dataset(store, path, "Original peripheral integration fixture", modality = "temperature", origin = "sample")
  source_hash <- dataset$body$source$hash
  check("original calibrated source is retained before review", dataset$body$status == "needs_mapping" && digest::digest(file = brohn_object_path(store, source_hash), algo = "sha256") == source_hash)
  bad <- m; bad$unit <- "V"
  check("wrong units fail before changing mapping revision or queue", rejects(brohn_curate_dataset(store, dataset$id, bad, dataset$revision)) &&
    brohn_get_entity(store, "dataset", dataset$id)$revision == dataset$revision && !length(brohn_list_jobs(store)))
  bad <- m; bad$recording_conditions <- ""
  check("missing temperature conditions fail before accepted status", rejects(brohn_curate_dataset(store, dataset$id, bad, dataset$revision)) &&
    brohn_get_entity(store, "dataset", dataset$id)$body$status == "needs_mapping")
  accepted <- brohn_curate_dataset(store, dataset$id, m, dataset$revision)
  job <- brohn_queue_dataset(store, accepted$id)
  check("same frozen peripheral request deduplicates", job$id == brohn_queue_dataset(store, accepted$id)$id)
  later <- m; later$calibration_source <- "Later source note amendment; original synthetic numbers unchanged."
  latest <- brohn_curate_dataset(store, dataset$id, later, accepted$revision)
  run_job <- function(job, succeeds = TRUE) {
    force(job); claim <- brohn_claim_job(store, "peripheral-integration-qa", lease_seconds = 120)
    stopifnot(!is.null(claim), claim$id == job$id)
    brohn_process_job(store, claim, timeout_seconds = 120)
    done <- brohn_get_job(store, job$id)
    if (succeeds && done$status != "succeeded") stop("Actual peripheral integration child failed: ", brohn_json(done$error), call. = FALSE)
    done
  }
  done <- run_job(job); report <- brohn_get_entity(store, "report", done$result$report_id); a <- report$body$analysis
  values <- function(name) vapply(Filter(function(f) identical(f$name, name), a$features), `[[`, numeric(1), "value")
  check("real report reproduces five independent segment means", identical(values("temperature_mean"), c(21,24.5,30.5,41,50.5)))
  check("each observed linear segment retains its own exact slope", all(abs(values("temperature_linear_slope")-60) < 1e-10))
  check("missingness, gap and support denominators cover all source rows", a$quality$source_rows == 13L && a$quality$valid_samples == 12L &&
    a$quality$invalid_samples == 1L && a$quality$usable_samples == 12L && a$quality$recording_count == 3L && a$quality$supported_observed_span_s == 7 && a$quality$time_gap_count == 1L)
  check("declared events are separated and retain boundary censoring", a$quality$event_count == 5L && length(a$events) == 5L &&
    all(vapply(a$events, function(e) isTRUE(e$right_censored), logical(1))) && !a$events[[1L]]$left_censored && sum(vapply(a$events, `[[`, numeric(1), "observed_span_s")) == 6)
  check("source codes and explicit conditions remain scoped without pooling", a$features[[1L]]$group$participant_id == "original-p" &&
    tail(a$features,1)[[1]]$group$participant_id == "original-q" && tail(a$features,1)[[1]]$group$exposure_id == "original-c" && is.null(a$quality$participant_count))
  check("queued mapping and calibration are frozen despite later source review", report$body$provenance$dataset_revision == accepted$revision &&
    report$body$provenance$dataset_hash == brohn_hash(accepted$body) && report$body$provenance$mapping$calibration_source == m$calibration_source &&
    brohn_get_entity(store, "dataset", dataset$id)$revision == latest$revision)
  check("actual source/profile origin and worker identity are retained", a$source$sha256 == source_hash && a$source$origin == "sample" &&
    a$operation == "peripheral" && a$engine$worker_sha256 == digest::digest(file = "scripts/workers/peripheral.py", algo = "sha256") &&
    all(c("R/platform-peripheral.R", "scripts/workers/peripheral.py", "scripts/workers/physiology_artifacts.py") %in% names(report$body$processing$code_hashes)))
  check("full processed streams pass complete artifact verification and publication", length(a$artifacts) == 2L && a$artifact_verification$status == "verified" &&
    all(vapply(a$artifacts, function(item) isTRUE(item$complete) && !is.null(item$hash) && is.null(item$path) &&
      digest::digest(file = brohn_object_path(store, item$hash), algo = "sha256") == item$hash, logical(1))))
  full_series <- Filter(function(item) item$kind == "physiology-series", a$artifacts)[[1L]]
  full_events <- Filter(function(item) item$kind == "physiology-events", a$artifacts)[[1L]]
  check("full series and event counts are retained independently of compact views", full_series$rows == 13 && full_series$tables == 3 && full_events$rows == 5 && full_events$tables == 3)
  check("new complete report has exact numeric parity with its immutable envelope", brohn_hash(brohn_read_json_file(brohn_object_path(store, report$body$result_object$hash))$report$analysis) == brohn_hash(a))

  catalog_done <- run_job(brohn_queue_signal_view(store, report$id, "physiology-series"))
  catalog <- brohn_get_entity(store, "signal_view", catalog_done$result$signal_view_id)
  table <- catalog$body$view$tables[[1L]]
  check("real signal catalog exposes all complete source groups and typed temperature", catalog$body$view$pagination$total_tables == 3 && table$rows == 8 &&
    "temperature_c" %in% vapply(table$value_columns, `[[`, character(1), "name") && table$support$source$sampling_rate == 1)
  selection <- list(table_ids = list(table$table_id), recording_id = table$identity$recording_id, channel = table$identity$channel, value_column = "temperature_c", range = NULL)
  preview_done <- run_job(brohn_queue_signal_view(store, report$id, "physiology-series", selection, max_bins = 1L))
  preview <- brohn_get_entity(store, "signal_view", preview_done$result$signal_view_id)
  view <- preview$body$view
  check("full-artifact explorer does not connect missing data or the clock gap", length(view$fragments) == 3L && view$selected_range$rows == 8L &&
    view$selected_range$eligible_value_rows == 7L && view$selected_range$missing_value_rows == 1L)
  check("source-bound preview keeps complete original report identity", preview$body$report_hash == brohn_hash(report$body) &&
    preview$body$artifact_hash == full_series$hash && !view$quality$scientific_resampling)
  event_catalog_done <- run_job(brohn_queue_signal_view(store, report$id, "physiology-events"))
  event_catalog <- brohn_get_entity(store, "signal_view", event_catalog_done$result$signal_view_id)
  event_table <- event_catalog$body$view$tables[[1L]]
  check("event catalog has one onset coordinate and full censored spans", event_table$coordinate_column$name == "time_s" && event_table$rows == 3L &&
    "observed_span_s" %in% vapply(event_table$value_columns, `[[`, character(1), "name"))
  event_selection <- list(table_ids = list(event_table$table_id), recording_id = event_table$identity$recording_id,
    channel = event_table$identity$channel, value_column = "observed_span_s", range = NULL)
  event_preview_done <- run_job(brohn_queue_signal_view(store, report$id, "physiology-events", event_selection))
  event_preview <- brohn_get_entity(store, "signal_view", event_preview_done$result$signal_view_id)
  check("actual event explorer presents observed events as unconnected points", event_preview$body$view$selected_range$eligible_value_rows == 3L &&
    all(vapply(event_preview$body$view$fragments, function(f) identical(f$connection_policy, "none"), logical(1))))
  report_hash <- brohn_hash(report$body)
  downloads <- list(source = source_hash, series = full_series$hash, events = full_events$hash, report = report$body$result_object$hash, preview = preview$body$result_object$hash)
  check("all complete downloads preserve exact immutable bytes and are writable", all(vapply(names(downloads), function(name) {
    destination <- file.path(root, paste0("download-", name)); brohn_copy_object_download(store, downloads[[name]], destination)
    digest::digest(file = destination, algo = "sha256") == downloads[[name]] && file.access(destination, 2L) == 0L
  }, logical(1))))
  html <- file.path(root, "report.html"); brohn_export_report_html(report$body, html, store)
  csv <- file.path(root, "features.csv"); brohn_export_report_csv(report$body, csv)
  check("HTML and numeric feature exports are available without source mutation", file.info(html)$size > 1000 && nrow(brohn_read_table(csv, "csv")) == length(a$features) &&
    brohn_hash(brohn_get_entity(store, "report", report$id)$body) == report_hash)

  movement_path <- file.path(root, "original-movement.csv")
  utils::write.csv(data.frame(time = 0:4, x = 0, y = 0, z = 1), movement_path, row.names = FALSE, fileEncoding = "UTF-8")
  movement <- brohn_ingest_dataset(store, movement_path, "Original static gravity", modality = "movement", origin = "sample")
  mm <- m; mm$value_columns <- list("x", "y", "z"); mm$unit <- "g"; mm$recording_conditions <- NULL
  for (name in c("participant_column", "session_column", "condition_column", "exposure_column", "segment_column")) mm[[name]] <- NULL
  mm$axis_labels <- list("positive right", "positive forward", "positive up"); mm$gravity_policy <- "included"; mm$parameters <- list(enmo = "zero_truncated")
  movement <- brohn_curate_dataset(store, movement$id, mm, movement$revision)
  movement_done <- run_job(brohn_queue_dataset(store, movement$id)); movement_report <- brohn_get_entity(store, "report", movement_done$result$report_id)
  mf <- function(name) Filter(function(f) f$name == name, movement_report$body$analysis$features)[[1L]]$value
  check("actual saved movement profile preserves independent gravity and derivative arithmetic", abs(mf("acceleration_magnitude_mean")-9.80665) < 1e-12 &&
    mf("enmo_mean") == 0 && mf("acceleration_vector_derivative_rms") == 0)
  check("unrequested movement detector is unavailable rather than zero events", is.null(movement_report$body$analysis$quality$event_count) &&
    !movement_report$body$analysis$quality$event_detection_requested && !movement_report$body$analysis$quality$physical_device_qualified)
  before <- length(brohn_list_entities(store, "report"))
  invalid_path <- file.path(root, "original-undeclared-clock-reset.csv")
  utils::write.csv(data.frame(time = c(0,1,0), x = 0, y = 0, z = 1), invalid_path, row.names = FALSE, fileEncoding = "UTF-8")
  invalid <- brohn_ingest_dataset(store, invalid_path, "Original invalid reset", modality = "movement", origin = "sample")
  invalid <- brohn_curate_dataset(store, invalid$id, mm, invalid$revision)
  rejected <- run_job(brohn_queue_dataset(store, invalid$id), succeeds = FALSE)
  check("undeclared reversed clock fails the real child without a false report", rejected$status == "failed" &&
    grepl("duplicated/reversed", brohn_json(rejected$error), fixed = TRUE) && length(brohn_list_entities(store, "report")) == before)
  # The publication guard intentionally retains small attempt receipts/logs.
  # Scientific attempt directories and unfinished object copies must be gone.
  scratch_files <- list.files(file.path(store$root, "scratch"), recursive = TRUE)
  scratch_children <- list.files(file.path(store$root, "scratch"))
  check("job cleanup removes scientific scratch and pending copies while full artifacts remain",
    all(scratch_children == "publication") && all(grepl(
      "^publication/attempt-[^/]+/(request\\.json|receipt\\.json|status\\.json|stdout\\.txt|stderr\\.txt)$", scratch_files)) &&
    file.exists(brohn_object_path(store, full_series$hash)) && file.exists(brohn_object_path(store, full_events$hash)))
  brohn_close_store(store); store <- brohn_open_store(file.path(root, "workspace"))
  check("new connection reopens exact saved report and full source streams", brohn_hash(brohn_get_entity(store, "report", report$id)$body) == report_hash &&
    digest::digest(file = brohn_object_path(store, full_series$hash), algo = "sha256") == full_series$hash &&
    digest::digest(file = brohn_object_path(store, source_hash), algo = "sha256") == source_hash)
  cat("Brohn peripheral integration: ", checks, " checks passed (actual scientific and signal-explorer jobs).\n", sep = "")
})
