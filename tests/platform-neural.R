source("R/platform-core.R")
source("R/platform-neural.R")
source("R/platform-neural-views.R")
local({
  checks <- 0L
  check <- function(name, value) { if (!isTRUE(value)) stop(paste("FAILED:", name)); checks <<- checks+1L }
  rejects <- function(expr) inherits(tryCatch({ force(expr); NULL }, error = identity), "error")
  close <- function(a, b, tol = 1e-8) is.numeric(a) && abs(a-b) < tol
  p <- list(recipe = "eeg-erp-epochs/1.0", event_codes = list(A = "condition-a"),
    event_source = "Synthetic measured sample onsets", epoch_s = list(-.2, .6), baseline_s = list(-.2, -.01),
    reference = list(mode = "acquisition", source = "Synthetic reference"), filter = list(mode = "none"),
    rejection = list(window_s = list(-.2, .6), peak_to_peak_uv = 100, flat_uv = NULL),
    minimum_trials = 2, overlap_policy = "reject", settings_source = "Independent evoked-pulse test specification",
    amplitude_window_s = list(.2, .39), peak_polarity = "none")
  m <- list(value_columns = list("Cz"), time_column = "time", time_unit = "s", sampling_rate = 100,
    unit = "uV", origin = "sample", event_column = "marker", parameters = p)
  check("ERP mapping accepts explicit complete contract", identical(brohn_validate_neural_mapping(m, c("time", "Cz", "marker"), "csv"), m))
  route <- brohn_neural_worker_request(m, "csv", c("time", "Cz", "marker"))
  check("ERP request selects bounded neural worker", route$operation == "neural" && route$script == "scripts/workers/neural.py" && identical(route$parameters, p))
  check("existing empty metadata retains Welch compatibility", identical(brohn_neural_worker_request(list())$operation, "physiology"))
  welch <- list(parameters = list(recipe = "eeg-welch-channel/1.0", window_s = 4))
  check("Welch retains configured settings", identical(brohn_neural_worker_request(welch)$parameters, welch$parameters))
  bad <- m; bad$parameters$recipe <- "invented"
  check("unknown recipe cannot silently fall back to Welch", rejects(brohn_neural_worker_request(bad)))
  bad <- m; bad$parameters$settings_source <- ""
  check("protocol provenance required", rejects(brohn_validate_neural_mapping(bad, source_format = "csv")))
  bad <- m; bad$parameters$baseline_s <- NULL
  check("omitted baseline setting differs from explicit null", rejects(brohn_validate_neural_mapping(bad)))
  none <- m; none$parameters["baseline_s"] <- list(NULL)
  check("explicit disabled baseline accepted", identical(brohn_validate_neural_mapping(none), none))
  bad <- m; bad$parameters$epoch_s <- list(-.205, .6)
  check("off-grid epoch boundaries rejected", rejects(brohn_validate_neural_mapping(bad)))
  bad <- m; bad$parameters$epoch_s <- c(-.2, .6)
  check("named/scalar arrays cannot change JSON shape", rejects(brohn_validate_neural_mapping(bad)))
  bad <- m; bad$parameters$unexpected <- TRUE
  check("unimplemented settings rejected", rejects(brohn_validate_neural_mapping(bad)))
  bad <- m; bad$parameters$reference <- list(mode = "average", source = "declared")
  check("single-channel average reference rejected", rejects(brohn_validate_neural_mapping(bad)))
  bad <- m; bad$parameters$reference <- list(mode = "channels", source = "declared", channels = list("missing"))
  check("absent reference channels rejected", rejects(brohn_validate_neural_mapping(bad)))
  bad <- m; bad$parameters$filter <- list(mode = "butterworth_bandpass", low_hz = 1, high_hz = 30, order = 4, edge_exclusion_s = 2)
  check("unsupported short filter edges rejected", rejects(brohn_validate_neural_mapping(bad)))
  bad$parameters$filter$edge_exclusion_s <- 3
  check("explicit supported filter accepted", identical(brohn_validate_neural_mapping(bad), bad))
  bad <- m; bad$events <- list(list(time_s = 2, code = "A"))
  check("two competing event sources rejected", rejects(brohn_validate_neural_mapping(bad)))
  bad <- m; bad$event_column <- "Cz"
  check("signal channel cannot become onset codes", rejects(brohn_validate_neural_mapping(bad)))
  check("absent event column rejected", rejects(brohn_validate_neural_mapping(m, c("time", "Cz"), "csv")))
  bad <- m; bad$participant_column <- "person"
  check("participant and session identities must be paired", rejects(brohn_validate_neural_mapping(bad, source_format = "csv")))
  check("unsupported native event-related format rejected", rejects(brohn_validate_neural_mapping(m, source_format = "set")))
  codes <- brohn_neural_code_map("A = condition-a\nB = condition-b")
  check("readable source-code mapping produces exact object", identical(codes, list(A = "condition-a", B = "condition-b")))
  check("duplicate readable codes rejected", rejects(brohn_neural_code_map("A = one\nA = two")))
  events <- brohn_neural_event_list("time_s,code,recording_id\n2,A,recording-1\n5,B,recording-1")
  check("readable event CSV preserves time code and recording", length(events) == 2 && events[[2]]$time_s == 5 && events[[2]]$code == "B")
  check("event CSV cannot smuggle unknown fields", rejects(brohn_neural_event_list("time_s,code,script\n2,A,ignored")))
  check("nonfinite event times rejected", rejects(brohn_neural_event_list("time_s,code\nNaN,A")))
  explicit <- m; explicit$event_column <- NULL; explicit$events <- events
  check("explicit event route validates", identical(brohn_validate_neural_mapping(explicit), explicit))
  explicit$events <- rev(events)
  check("reversed explicit events rejected", rejects(brohn_validate_neural_mapping(explicit)))
  tf <- m; tf$parameters <- p[!names(p) %in% c("amplitude_window_s", "peak_polarity")]
  tf$parameters$recipe <- "eeg-morlet-epochs/1.0"; tf$parameters$epoch_s <- list(-2, 2)
  tf$parameters$frequencies_hz <- list(10, 20); tf$parameters$n_cycles <- list(3, 3)
  tf$parameters$power <- "total"; tf$parameters$summary_window_s <- list(0, .5)
  tf$parameters$power_baseline <- list(mode = "db", window_s = list(-1, -.5), minimum_power_uv2 = 0)
  check("Morlet declared settings accepted", brohn_neural_worker_request(tf)$operation == "neural")
  bad <- tf; bad$parameters$n_cycles <- list(3)
  check("one cycle count required per frequency", rejects(brohn_validate_neural_mapping(bad)))
  bad <- tf; bad$parameters$power_baseline$window_s <- list(0, .5)
  check("post-onset baseline rejected", rejects(brohn_validate_neural_mapping(bad)))
  tag <- m; tag$parameters <- p[!names(p) %in% c("amplitude_window_s", "peak_polarity")]
  tag$parameters$recipe <- "eeg-frequency-tagging/1.0"; tag$parameters$epoch_s <- list(-2, 2)
  tag$parameters$spectral_window_s <- list(0, 2); tag$parameters$tag_frequencies_hz <- list(10)
  tag$parameters$harmonics <- list(1, 2); tag$parameters$window <- "hann"
  tag$parameters$noise_neighbor_bins <- 2; tag$parameters$noise_skip_bins <- 1; tag$parameters$max_bin_offset_hz <- 0
  check("frequency-tagging declared settings accepted", brohn_neural_worker_request(tag)$operation == "neural")
  bad <- tag; bad$parameters$harmonics <- list(1, 5)
  check("Nyquist harmonic rejected", rejects(brohn_validate_neural_mapping(bad)))
  input <- list(map_neural_recipe = p$recipe, map_neural_event_mode = "column", map_neural_event_column = "marker",
    map_neural_event_codes = "A = condition-a", map_neural_event_source = p$event_source,
    map_neural_epoch_start = -.2, map_neural_epoch_end = .6, map_neural_voltage_baseline = "subtract",
    map_neural_baseline_start = -.2, map_neural_baseline_end = -.01, map_neural_reference = "acquisition",
    map_neural_reference_source = p$reference$source, map_neural_filter = "none", map_neural_reject_start = -.2, map_neural_reject_end = .6,
    map_neural_reject_peak = TRUE, map_neural_peak_uv = 100, map_neural_reject_flat = FALSE,
    map_neural_minimum_trials = 2, map_neural_overlap = "reject", map_neural_settings_source = p$settings_source,
    map_neural_amplitude_start = .2, map_neural_amplitude_end = .39, map_neural_polarity = "none")
  mapped <- brohn_neural_input(input, m, "csv")
  check("UI input creates exact declared recipe", identical(mapped, m))
  roundtrip <- brohn_parse(brohn_json(mapped))
  check("single channels, codes and explicit null survive JSON", length(roundtrip$value_columns) == 1 && brohn_array(roundtrip$value_columns) &&
    "flat_uv" %in% names(roundtrip$parameters$rejection) && is.null(roundtrip$parameters$rejection$flat_uv))
  back <- input; back$map_neural_recipe <- "eeg-welch-channel/1.0"
  converted <- brohn_neural_input(back, mapped)
  check("switching to Welch removes stale epoch parameters and events", identical(converted$parameters, list(recipe = "eeg-welch-channel/1.0")) && is.null(converted$events) && is.null(converted$event_column))
  html <- htmltools::renderTags(brohn_neural_settings_ui(m, c("time", "Cz", "marker"), "csv"))$html
  check("disclosure UI renders all explicit recipes and labelled controls", grepl("Event-related response", html, fixed = TRUE) &&
    grepl('for="map_neural_event_codes"', html, fixed = TRUE) && grepl("<summary>", html, fixed = TRUE) && grepl("map_neural_filter_edge", html, fixed = TRUE))
  native_html <- htmltools::renderTags(brohn_neural_settings_ui(list(), source_format = "fif"))$html
  check("native UI requests header rate and explicit events", grepl("map_neural_native_rate", native_html, fixed = TRUE) && !grepl('id="map_neural_event_column"', native_html, fixed = TRUE))
  # Real R -> JSON -> Python integration verifies serializer, dispatch and a
  # numerically independent pulse, rather than stopping at a mocked request.
  scratch <- tempfile("brohn-neural-r-"); dir.create(scratch)
  scratch <- normalizePath(scratch, winslash = "/", mustWork = TRUE)
  brohn_require(startsWith(scratch, paste0(normalizePath(tempdir(), winslash = "/"), "/")), "Test cleanup must remain under its temporary directory.")
  on.exit(unlink(scratch, recursive = TRUE), add = TRUE)
  signal <- rep(5, 1100); markers <- rep("", 1100)
  for (onset in c(200, 500, 800)) { signal[onset+(21:40)] <- 15; markers[onset+1] <- "A" }
  source <- file.path(scratch, "signal.csv"); utils::write.csv(data.frame(time = (0:1099)/100, Cz = signal, marker = markers), source, row.names = FALSE)
  request <- list(schema = "brohn-worker-request/1.0", operation = route$operation, modality = "eeg", source_path = source,
    format = "csv", metadata = mapped, parameters = route$parameters)
  request_path <- file.path(scratch, "request.json"); output_path <- file.path(scratch, "result.json")
  writeLines(brohn_json(request), request_path, useBytes = TRUE)
  python <- normalizePath("../../work/tooling/methods-venv/Scripts/python.exe", mustWork = TRUE)
  result <- processx::run(python, c(route$script, "--request", request_path, "--output", output_path), error_on_status = FALSE, timeout = 60000)
  check("real R request executes without serializer/schema errors", result$status == 0L && file.exists(output_path))
  report <- brohn_parse(paste(readLines(output_path, warn = FALSE, encoding = "UTF-8"), collapse = "\n"))
  mean <- Filter(function(f) f$name == "erp_mean_amplitude", report$features)[[1]]
  check("real R-to-Python ERP matches independent pulse arithmetic", close(mean$value, 10) && mean$trial_count == 3 && mean$origin == "sample")
  check("neural report keeps trial counts distinct from participant inference", identical(report$quality$participant_inference_performed, FALSE) && identical(report$series[[1]]$sem_scope, "within_recording_trials; not participant inference"))
  # Full durable application route: pinned source -> accepted mapping -> fenced
  # R supervisor -> neural child -> immutable report and receipt -> reopen.
  for (module in c("platform-store", "platform-publication", "platform-methods", "platform-delivery", "platform-library", "platform-analysis", "platform-jobs")) source(paste0("R/", module, ".R"), encoding = "UTF-8")
  for (module in c("questionnaire-artifacts", "questionnaire-artifact-storage")) source(paste0("R/platform-",module,".R"),encoding="UTF-8")
  store <- brohn_open_store(file.path(scratch, "workspace"))
  on.exit(brohn_close_store(store), add = TRUE, after = FALSE)
  brohn_initialise_library(store)
  imported <- brohn_ingest_dataset(store, source, "Synthetic ERP integration", modality = "eeg", origin = "sample")
  mapped$origin_statement <- "Synthetic independently calculated pulse and exact marker fixture. No empirical participant or device claim."
  accepted <- brohn_curate_dataset(store, imported$id, mapped, imported$revision)
  queued <- brohn_queue_dataset(store, accepted$id)
  claim <- brohn_claim_job(store, "neural-qa", lease_seconds = 60)
  brohn_process_job(store, claim, timeout_seconds = 60)
  finished <- brohn_get_job(store, queued$id)
  if (!identical(finished$status, "succeeded")) stop(paste("Durable neural job failed:", brohn_json(finished$error)))
  check("durable neural supervisor publishes a succeeded fenced job", identical(finished$status, "succeeded"))
  saved <- brohn_get_entity(store, "report", finished$result$report_id)
  mean <- Filter(function(f) f$name == "erp_mean_amplitude", saved$body$analysis$features)[[1]]
  check("saved neural report retains exact ERP result and measured recipe", close(mean$value, 10) &&
    saved$body$analysis$parameters$`recording-1`$recipe == "eeg-erp-epochs/1.0" && mean$origin == "sample")
  hash <- brohn_hash(saved$body)
  brohn_close_store(store); store <- brohn_open_store(file.path(scratch, "workspace"))
  reopened <- brohn_get_entity(store, "report", saved$id)
  check("neural report and source survive restart with verified hashes", identical(brohn_hash(reopened$body), hash) &&
    identical(digest::digest(file = brohn_object_path(store, accepted$body$source$hash), algo = "sha256"), accepted$body$source$hash))
  check("saved result object agrees with fenced completion receipt", identical(saved$body$result_object$hash, finished$result$output_hash) &&
    identical(digest::digest(file = brohn_object_path(store, finished$result$output_hash), algo = "sha256"), finished$result$output_hash))
  cat(sprintf("PASS: %d neural R contract, accessible disclosure and real-worker checks\n", checks))
})
