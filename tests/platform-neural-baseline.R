source("R/platform-load.R", encoding = "UTF-8"); brohn_load()
local({
  checks <- 0L
  check <- function(name, value) {if (!isTRUE(value)) stop("Neural baseline QA: ", name, call. = FALSE); checks <<- checks+1L}
  rejects <- function(expr) inherits(try(force(expr), silent = TRUE), "try-error")
  scratch <- tempfile("brohn-neural-baseline-"); dir.create(scratch); scratch <- normalizePath(scratch, winslash = "/")
  store <- brohn_open_store(file.path(scratch, "workspace")); brohn_initialise_library(store)
  on.exit({brohn_close_store(store); stopifnot(startsWith(tolower(normalizePath(scratch, winslash = "/")),
    paste0(tolower(normalizePath(tempdir(), winslash = "/")), "/"))); unlink(scratch, recursive = TRUE)}, add = TRUE)
  time <- (0:1799)/100; markers <- rep("", length(time)); markers[c(301, 801, 1301)] <- "A"
  path <- file.path(scratch, "stationary.csv")
  utils::write.csv(data.frame(time = time, Cz = 20*sin(2*pi*10*time), marker = markers), path, row.names = FALSE)
  source_hash <- .brohn_store_hash(path, file = TRUE)
  metadata <- list(time_column = "time", time_unit = "s", sampling_rate = 100, value_columns = list("Cz"), unit = "uV", origin = "sample",
    origin_statement = "Independent stationary synthetic sine; no physical device or empirical participant claim.")
  input <- list(map_neural_recipe = "eeg-morlet-epochs/1.1", map_neural_event_mode = "column", map_neural_event_column = "marker",
    map_neural_event_codes = "A = condition-a", map_neural_event_source = "Synthetic exact sample onsets at 3, 8 and 13 seconds",
    map_neural_epoch_start = -2, map_neural_epoch_end = 2, map_neural_voltage_baseline = "none", map_neural_reference = "acquisition",
    map_neural_reference_source = "Synthetic zero reference", map_neural_filter = "none", map_neural_reject_start = -2, map_neural_reject_end = 2,
    map_neural_reject_peak = TRUE, map_neural_peak_uv = 100, map_neural_reject_flat = FALSE, map_neural_minimum_trials = 2,
    map_neural_overlap = "reject", map_neural_settings_source = "Independent constant-amplitude sine; expected baseline power ratio is one",
    map_neural_frequencies = "10, 20", map_neural_cycles = "3, 3", map_neural_power = "total", map_neural_summary_start = 0, map_neural_summary_end = .5,
    map_neural_power_baseline = "ratio", map_neural_power_baseline_start = -1, map_neural_power_baseline_end = -.5,
    map_neural_power_floor = 1e-20, map_neural_baseline_minimum_cycles = 4,
    map_neural_baseline_rationale = "Four cycles required for this stationary-sine test; not a general EEG duration recommendation.")
  mapping <- brohn_neural_input(input, metadata, "csv")
  check("new UI freezes explicit version, duration policy and rationale", mapping$parameters$recipe == "eeg-morlet-epochs/1.1" &&
    mapping$parameters$power_baseline$adequacy$minimum_cycles == 4 && identical(mapping$parameters$power_baseline$adequacy$rationale, input$map_neural_baseline_rationale))
  check("new recipe dispatches to neural worker", brohn_neural_worker_request(mapping, "csv")$operation == "neural")
  check("new selection lists only the reviewed Morlet version", "eeg-morlet-epochs/1.1" %in% unname(brohn_neural_recipe_choices()) && !"eeg-morlet-epochs/1.0" %in% unname(brohn_neural_recipe_choices()))
  for (v in list(NULL, 0, TRUE, "4", Inf)) {
    bad <- mapping; bad$parameters$power_baseline$adequacy["minimum_cycles"] <- list(v)
    check("invalid or omitted duration cannot become a threshold", rejects(brohn_validate_neural_mapping(bad)))
  }
  bad <- mapping; bad$parameters$power_baseline$adequacy$rationale <- ""
  check("duration rationale is required", rejects(brohn_validate_neural_mapping(bad)))
  bad <- mapping; bad$parameters$power_baseline$adequacy$policy <- "invented"
  check("unknown baseline policy is refused", rejects(brohn_validate_neural_mapping(bad)))
  legacy <- mapping; legacy$parameters$recipe <- "eeg-morlet-epochs/1.0"; legacy$parameters$power_baseline$adequacy <- NULL
  check("historical explicit version remains reproducible", brohn_neural_worker_request(legacy)$parameters$recipe == "eeg-morlet-epochs/1.0")
  html <- as.character(brohn_neural_settings_ui(legacy, c("time", "Cz", "marker")))
  check("migration is explicit and duration has no invented default", grepl("original settings", html, fixed = TRUE) && grepl("baseline_minimum_cycles", html, fixed = TRUE) &&
    grepl("there is no universal cycle threshold", html, fixed = TRUE) && grepl("earlier baseline", html, fixed = TRUE))
  imported <- brohn_ingest_dataset(store, path, "Stationary Morlet baseline oracle", modality = "eeg", origin = "sample")
  accepted <- brohn_curate_dataset(store, imported$id, mapping, imported$revision)
  execute <- function(dataset) {
    queued <- brohn_queue_dataset(store, dataset$id)
    claim <- brohn_claim_job(store, "neural-baseline-qa", lease_seconds = 120)
    brohn_process_job(store, claim, timeout_seconds = 90)
    job <- brohn_get_job(store, queued$id)
    if (!identical(job$status, "succeeded")) stop("Actual baseline supervisor failed: ", brohn_json(job$error))
    brohn_get_entity(store, "report", job$result$report_id)
  }
  saved <- execute(accepted); report <- saved$body; before <- brohn_hash(report)
  f <- Filter(function(f) f$name == "morlet_power_mean" && f$frequency_hz == 10, report$analysis$features)[[1L]]
  check("actual fenced worker matches independent stationary ratio oracle", abs(f$value-1) < 1e-7 && f$trial_count == 3)
  d <- report$analysis$recordings[[1L]]$derived_settings$baseline_support
  check("actual saved baseline spans 51 centres and five cycles", d$baseline_sample_count == 51 && d$sample_span_s == .5 && d$cycles_at_lowest_frequency == 5 && d$status == "eligible")
  check("successful computation remains scientifically unqualified", identical(report$analysis$quality$scientifically_qualified, FALSE))
  model <- brohn_neural_plot_model(report); view <- brohn_neural_plot_selection(model)
  check("reviewed recipe plots actual frozen values", view$cell$parameters$recipe == "eeg-morlet-epochs/1.1" && length(view$x) > 100 && view$unit == "ratio")
  rendered <- as.character(brohn_neural_report_plots(report))
  check("duration, cycles, support and limitations are prominent", grepl("51 samples", rendered, fixed = TRUE) && grepl("5 cycles", rendered, fixed = TRUE) &&
    grepl("Temporal sigma:", rendered, fixed = TRUE) && grepl("Latest contributing sample:", rendered, fixed = TRUE) && grepl("zero-phase", rendered, fixed = TRUE) && grepl("not scientific validation", rendered, fixed = TRUE))
  csv <- file.path(scratch, "channel.csv"); brohn_neural_plot_csv(model, model$cells[[1L]]$selector, csv)
  exported <- utils::read.csv(csv)
  check("complete numerical download includes frozen baseline diagnostics", nrow(exported) == 2*length(view$x) && all(exported$recipe == "eeg-morlet-epochs/1.1") &&
    all(grepl("complete-pre-event-wavelet-support/1.0", exported$baseline_support_json, fixed = TRUE)))
  check("standalone chart carries the baseline support record", grepl("sample_span_s", as.character(brohn_neural_plot_svg(view)), fixed = TRUE))
  bad <- report; bad$analysis$recordings[[1L]]$derived_settings$baseline_support$sample_span_s <- .51
  check("altered duration cannot support a plausible-looking plot", rejects(brohn_neural_plot_model(bad)))
  bad <- report; bad$analysis$recordings[[1L]]$derived_settings$baseline_support$frequencies[[1L]]$latest_kernel_sample_s <- 0
  check("altered kernel separation cannot support the plotted result", rejects(brohn_neural_plot_model(bad)))
  bad <- report; bad$analysis$recordings[[1L]]$derived_settings$baseline_support <- NULL
  check("new recipe cannot silently omit its baseline diagnostic", rejects(brohn_neural_plot_model(bad)))
  # A second actual job preserves an inadequate reference as unavailable, with
  # the exact sampled diagnostics and actionable choices in the saved report.
  changed <- mapping; changed$parameters$power_baseline$window_s <- list(-.02, -.01)
  changed$parameters$power_baseline$adequacy$minimum_cycles <- .1
  current <- brohn_get_entity(store, "dataset", accepted$id)
  revised <- brohn_curate_dataset(store, current$id, changed, current$revision)
  unavailable <- execute(revised)
  check("event-reaching baseline publishes an honest unavailable result", unavailable$body$analysis$status == "insufficient_support" && length(unavailable$body$analysis$series) == 0)
  r <- unavailable$body$analysis$recordings[[1L]]
  check("unavailable report retains exact contamination reason and support", r$derived_settings$baseline_support$duration_criterion_met &&
    !r$derived_settings$baseline_support$frequencies[[1L]]$strictly_before_event && grepl("earlier baseline", r$reason, fixed = TRUE))
  rendered <- as.character(brohn_neural_report_plots(unavailable$body))
  check("unavailable result has visible remediation and no invented trace", grepl("Power baseline support: unavailable", rendered, fixed = TRUE) &&
    grepl("lengthen the epoch", rendered, fixed = TRUE) && !grepl("<polyline", rendered, fixed = TRUE))
  check("new run leaves source and earlier report unchanged", identical(.brohn_store_hash(path, file = TRUE), source_hash) && identical(brohn_hash(brohn_get_entity(store, "report", saved$id)$body), before))
  brohn_close_store(store); store <- brohn_open_store(file.path(scratch, "workspace"))
  reopened <- brohn_get_entity(store, "report", saved$id)
  check("reopen preserves recipe and reviewed plot support", identical(brohn_hash(reopened$body), before) && length(brohn_neural_plot_model(reopened$body)$cells) == 1)
  cat("platform-neural-baseline:", checks, "checks passed\n")
})
