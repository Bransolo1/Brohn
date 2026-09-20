source("R/platform-load.R", encoding = "UTF-8"); brohn_load()
local({
  checks <- 0L
  check <- function(name, value) {if (!isTRUE(value)) stop("Cardiac spectrum QA: ", name, call. = FALSE); checks <<- checks+1L}
  evidence <- normalizePath(file.path("../../work/test-runs", "brohn-cardiac-spectrum-20260920"), winslash = "/", mustWork = FALSE)
  dir.create(evidence, recursive = TRUE, showWarnings = FALSE)
  scratch <- tempfile("brohn-cardiac-spectrum-"); dir.create(scratch)
  store <- brohn_open_store(file.path(scratch, "workspace")); brohn_initialise_library(store)
  on.exit({brohn_close_store(store); actual <- normalizePath(scratch, winslash = "/", mustWork = FALSE)
    stopifnot(startsWith(tolower(actual), paste0(tolower(normalizePath(tempdir(), winslash = "/")), "/")), startsWith(basename(actual), "brohn-cardiac-spectrum-"))
    unlink(actual, recursive = TRUE)}, add = TRUE)
  processx::run(brohn_python_profile("ecg"), c("tests/workers/cardiac_spectrum.py", "--fixture", scratch), windows_hide_window = TRUE)
  run_job <- function(queued, type) {
    force(queued)
    claim <- brohn_claim_job(store, "cardiac-spectrum-qa", lease_seconds = 120)
    stopifnot(identical(queued$id, claim$id)); brohn_process_job(store, claim, timeout_seconds = 120)
    job <- brohn_get_job(store, queued$id)
    if (!identical(job$status, "succeeded")) stop("Actual cardiac supervisor failed: ", brohn_json(job$error))
    brohn_get_entity(store, type, job$result[[if (type == "report") "report_id" else "signal_view_id"]])
  }
  saved <- list()
  for (modality in c("ecg", "ppg")) {
    imported <- brohn_ingest_dataset(store, file.path(scratch, paste0(modality, ".csv")), paste("Original synthetic", modality, "spectrum"), modality = modality, origin = "sample")
    mapping <- list(time_column = "time", time_unit = "s", sampling_rate = if (modality == "ecg") 250 else 100,
      value_columns = list(modality), unit = if (modality == "ecg") "mV" else "a.u.", origin = "sample",
      origin_statement = "Original analytic pulse train with 0.1 Hz and 0.25 Hz interval modulation; no physical device or participant.")
    accepted <- brohn_curate_dataset(store, imported$id, mapping, imported$revision)
    report <- run_job(brohn_queue_dataset(store, accepted$id), "report")
    before <- brohn_hash(report$body); analysis <- report$body$analysis
    artifact <- Filter(function(a) a$kind == "physiology-events", analysis$artifacts)[[1L]]
    lines <- readLines(brohn_object_path(store, artifact$hash), warn = FALSE)
    records <- lapply(lines, jsonlite::fromJSON, simplifyVector = FALSE)
    table <- Filter(function(r) identical(r$type, "table") && identical(r$coordinates$axis, "frequency"), records)[[1L]]
    chunks <- Filter(function(r) identical(r$type, "rows") && identical(r$table_id, table$table_id), records)
    rows <- unlist(lapply(chunks, `[[`, "rows"), recursive = FALSE)
    frequencies <- vapply(rows, function(r) r[[2L]], numeric(1)); density <- vapply(rows, function(r) r[[3L]], numeric(1))
    spec <- table$support$interval_spectrum
    prefix <- if (modality == "ecg") "detected_rr" else "detected_prv"
    metric <- function(name) Filter(function(f) f$name == paste0(prefix, "_", name, "_candidate"), analysis$features)[[1L]]$value
    check(paste(modality, "complete typed spectral artifact"), length(rows) == 257L && identical(range(frequencies), c(0, 2)) && spec$density_unit == "ms^2/Hz")
    check(paste(modality, "artifact and reported LF integrate identical bins"), abs(sum(density[frequencies >= .04 & frequencies < .15])/128-metric("lf_power")) < 1e-9)
    check(paste(modality, "artifact and reported HF integrate identical bins"), abs(sum(density[frequencies >= .15 & frequencies <= .4])/128-metric("hf_power")) < 1e-9)
    check(paste(modality, "rhythm basis is explicit and unqualified"), !spec$normal_to_normal_confirmed && identical(spec$interval_basis,
      if (modality == "ecg") "detected_r_peak_intervals_rr" else "detected_pulse_intervals_prv"))
    check(paste(modality, "worker and artifact-writer provenance captured"), analysis$engine$worker_sha256 == .brohn_store_hash("scripts/workers/physiology.py", file = TRUE) &&
      analysis$engine$artifact_writer_sha256 == .brohn_store_hash("scripts/workers/physiology_artifacts.py", file = TRUE))
    catalog <- run_job(brohn_queue_signal_view(store, report$id, artifact$kind), "signal_view")
    descriptor <- Filter(function(t) t$coordinates$axis == "frequency", catalog$body$view$tables)[[1L]]
    check(paste(modality, "complete catalog exposes interval spectrum"), descriptor$rows == 257L && identical(descriptor$value_columns[[1L]]$name, "density_ms2_hz"))
    choice <- list(table_ids = list(descriptor$table_id), recording_id = descriptor$identity$recording_id, channel = descriptor$identity$channel,
      value_column = "density_ms2_hz", range = NULL)
    preview <- run_job(brohn_queue_signal_view(store, report$id, artifact$kind, choice), "signal_view")
    view <- preview$body$view
    check(paste(modality, "saved preview uses every actual spectrum row"), view$full_range$rows == 257L && view$selected_range$eligible_value_rows == 257L &&
      identical(view$axis$kind, "frequency") && identical(view$axis$unit, "Hz") && identical(view$axis$value_unit, "ms^2/Hz"))
    plotted <- unlist(lapply(view$envelopes, `[[`, "points"), recursive = FALSE)
    check(paste(modality, "plotted values originate in exact full spectrum"), all(vapply(plotted, function(p) any(abs(frequencies-p$x) < 1e-12 & abs(density-p$y) < 1e-9), logical(1))))
    html <- as.character(brohn_signal_plot_ui(preview)); svg <- as.character(brohn_signal_svg(view))
    check(paste(modality, "plot shows method support bands and basis"), all(vapply(c("Detected interval power spectrum", spec$rhythm_basis, "ms^2/Hz", "Full spectrum band power", "128 s", "not a stress"),
      function(x) grepl(x, html, fixed = TRUE), logical(1))) && grepl("Frequency (Hz)", svg, fixed = TRUE) && grepl("LF band", svg, fixed = TRUE))
    writeLines(paste0('<!doctype html><html lang="en"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Brohn original ',
      modality, ' spectrum fixture</title><style>.container-fluid{padding:12px}body{margin:0}</style></head><body><main class="container-fluid"><div class="brohn-app">',
      '<h1>Original ', toupper(modality), ' spectrum fixture</h1>', html, '</div></main></body></html>'), file.path(evidence, paste0(modality, ".html")), useBytes = TRUE)
    brohn_write_json_file(view, file.path(evidence, paste0(modality, "-view.json")))
    writeLines(svg, file.path(evidence, paste0(modality, ".svg")), useBytes = TRUE)
    saved[[modality]] <- list(id = report$id, hash = before, view_id = preview$id, view_hash = brohn_hash(preview$body), artifact = artifact$hash)
    check(paste(modality, "exploration leaves report and source intact"), identical(brohn_hash(brohn_get_entity(store, "report", report$id)$body), before) &&
      .brohn_store_hash(brohn_object_path(store, imported$body$source$hash), file = TRUE) == imported$body$source$hash)
  }
  brohn_close_store(store); store <- brohn_open_store(file.path(scratch, "workspace"))
  for (item in saved) check("saved spectrum and view survive reopening", identical(brohn_hash(brohn_get_entity(store, "report", item$id)$body), item$hash) &&
    identical(brohn_hash(brohn_get_entity(store, "signal_view", item$view_id)$body), item$view_hash))
  brohn_write_json_file(list(checks = checks, evidence_origin = "original_synthetic_software_fixture", physical_validation = FALSE), file.path(evidence, "worker-results.json"))
  cat(sprintf("PASS: %d cardiac spectrum checks (six supervised jobs, exact bins, RR/PRV, immutable artifacts, saved plots, reopen)\n", checks))
})
