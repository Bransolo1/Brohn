source("R/platform-core.R")
source("R/platform-eda-events.R")
source("R/platform-eda-events-views.R")
local({
  checks <- 0L
  check <- function(name, value) { if (!isTRUE(value)) stop(paste("FAILED:", name)); checks <<- checks+1L }
  rejects <- function(expr) inherits(tryCatch({ force(expr); NULL }, error = identity), "error")
  p <- list(recipe = "eda-event-highpass/1.0", event_codes = list(A = "control", B = "test"), nuisance_codes = list(),
    event_source = "Shared-clock measured onset fixture", settings_source = "Independent EDA event test protocol",
    baseline_s = list(-2, 0), response_s = list(0, 6), onset_latency_s = list(.5, 4), recovery_end_s = 10,
    nuisance_effect_s = list(0, 8), overlap_policy = "exclude", response_selection = "first_onset",
    minimum_scr_amplitude_us = .05, relative_prominence = .1, edge_exclusion_s = 10, minimum_segment_s = 40)
  m <- list(value_columns = list("conductance"), time_column = "time", time_unit = "s", sampling_rate = 25, unit = "uS", origin = "sample",
    participant_column = "person", session_column = "session", condition_column = "condition", exposure_column = "exposure",
    event_column = "onset", parameters = p)
  columns <- c("conductance", "time", "person", "session", "condition", "exposure", "onset", "valid", "reset")
  check("complete continuous/event source contract accepted", identical(brohn_validate_eda_events_mapping(m, columns, "csv"), m))
  route <- brohn_eda_events_worker_request(m, "csv", columns)
  check("declared event recipe selects independent worker", route$operation == "eda_events" && route$script == "scripts/workers/eda_events.py" && identical(route$parameters, p))
  check("legacy route remains compatible", brohn_eda_events_worker_request(list())$operation == "physiology")
  legacy <- list(parameters = list(recipe = "eda-neurokit-highpass/1.0", edge_exclusion_s = 12))
  check("existing recording settings retained", identical(brohn_eda_events_worker_request(legacy)$parameters, legacy$parameters))
  check("unknown recipe cannot silently use recording analysis", rejects(brohn_eda_events_worker_request(list(parameters = list(recipe = "fictional")))))
  for (field in c("participant_column", "session_column", "exposure_column")) {
    bad <- m; bad[[field]] <- NULL
    check(paste("required identity", field), rejects(brohn_validate_eda_events_mapping(bad)))
  }
  check("absent source identity rejected", rejects(brohn_validate_eda_events_mapping(m, setdiff(columns, "session"), "csv")))
  bad <- m; bad$valid_column <- "conductance"
  check("source-validity column cannot equal conductance", rejects(brohn_validate_eda_events_mapping(bad)))
  bad <- m; bad$unit <- "ohm"
  check("resistance is not implicitly conductance", rejects(brohn_validate_eda_events_mapping(bad)))
  bad <- m; bad$sampling_rate <- 4
  check("low-rate cleaner bypass rejected", rejects(brohn_validate_eda_events_mapping(bad)))
  bad <- m; bad$time_unit <- "ns"
  check("only implemented event clock units allowed", rejects(brohn_validate_eda_events_mapping(bad)))
  check("native unsupported event format rejected", rejects(brohn_validate_eda_events_mapping(m, source_format = "edf")))
  for (change in list(list(field = "baseline_s", value = list(-2, .1)), list(field = "response_s", value = list(0, 6.001)),
                     list(field = "onset_latency_s", value = list(.5, 7)), list(field = "edge_exclusion_s", value = 2),
                     list(field = "minimum_segment_s", value = 20), list(field = "recovery_end_s", value = 5),
                     list(field = "relative_prominence", value = 0), list(field = "minimum_scr_amplitude_us", value = 0),
                     list(field = "settings_source", value = ""), list(field = "alpha", value = .1))) {
    bad <- m; bad$parameters[[change$field]] <- change$value
    check(paste("invalid method setting", change$field), rejects(brohn_validate_eda_events_mapping(bad)))
  }
  bad <- m; bad$parameters$baseline_s <- c(-2, 0)
  check("JSON array shape must remain explicit", rejects(brohn_validate_eda_events_mapping(bad)))
  bad <- m; bad$parameters$nuisance_codes <- list("A")
  check("same code cannot be target and nuisance", rejects(brohn_validate_eda_events_mapping(bad)))
  bad <- m; bad$parameters$event_tolerance_s <- .03
  check("event alignment cannot exceed half a sample", rejects(brohn_validate_eda_events_mapping(bad)))
  cvx <- m; cvx$parameters$recipe <- "eda-event-cvxeda-defaults/1.0"
  check("verified cvx defaults route accepted", brohn_eda_events_worker_request(cvx)$operation == "eda_events")
  design <- list(conditions = list(list(id = "control"), list(id = "test")), stimuli = list(list(id = "card")))
  check("frozen design condition mapping accepted", identical(brohn_validate_eda_events_mapping(m, design = design), m))
  bad <- m; bad$parameters$event_codes$A <- "not-in-study"
  check("code cannot identify missing study condition", rejects(brohn_validate_eda_events_mapping(bad, design = design)))
  check("readable mapping preserves exact code names", identical(brohn_eda_events_code_map("A = control\nB = test"), p$event_codes))
  check("duplicate readable codes rejected", rejects(brohn_eda_events_code_map("A = control\nA = test")))
  events <- brohn_eda_events_event_list("time_s,code,exposure_id,recording_id\n20,A,trial-1,recording-1\n40,B,trial-2,recording-1")
  explicit <- m; explicit$event_column <- NULL; explicit$events <- events
  check("typed explicit event list accepted", identical(brohn_validate_eda_events_mapping(explicit), explicit))
  check("CSV preserves numeric seconds and trial identity", identical(events[[1]], list(time_s = 20, code = "A", exposure_id = "trial-1", recording_id = "recording-1")))
  check("unknown event CSV fields rejected", rejects(brohn_eda_events_event_list("time_s,code,script\n20,A,ignored")))
  bad <- explicit; bad$events[[1]]$exposure_id <- NULL
  check("target explicit event requires exposure", rejects(brohn_validate_eda_events_mapping(bad)))
  bad <- explicit; bad$events[[2]]$exposure_id <- "trial-1"
  check("duplicate trial identities rejected", rejects(brohn_validate_eda_events_mapping(bad)))
  bad <- explicit; bad$events[[2]]$time_s <- 20
  check("simultaneous event codes rejected", rejects(brohn_validate_eda_events_mapping(bad)))
  bad <- explicit; bad$events[[1]]$condition_id <- "test"
  check("explicit condition must match code mapping", rejects(brohn_validate_eda_events_mapping(bad)))
  bad <- explicit; bad$events[[1]]$stimulus_id <- "absent"
  check("explicit stimulus must exist in frozen design", rejects(brohn_validate_eda_events_mapping(bad, design = design)))
  input <- list(map_eda_event_recipe = p$recipe, map_eda_event_event_mode = "column", map_eda_event_event_column = "onset",
    map_eda_event_event_codes = "A = control\nB = test", map_eda_event_nuisance_codes = "", map_eda_event_event_source = p$event_source,
    map_eda_event_settings_source = p$settings_source, map_eda_event_baseline_start = -2, map_eda_event_baseline_end = 0,
    map_eda_event_response_start = 0, map_eda_event_response_end = 6, map_eda_event_latency_start = .5, map_eda_event_latency_end = 4,
    map_eda_event_recovery_end = 10, map_eda_event_nuisance_start = 0, map_eda_event_nuisance_end = 8,
    map_eda_event_overlap = "exclude", map_eda_event_selection = "first_onset", map_eda_event_minimum_amplitude = .05,
    map_eda_event_relative_prominence = .1, map_eda_event_edge = 10, map_eda_event_context = 40,
    map_eda_event_alignment = "half_sample", map_eda_event_recording_column = "", map_eda_event_valid_column = "")
  mapped <- brohn_eda_events_input(input, m, "csv")
  check("UI creates exact validated mapping", identical(mapped, m))
  roundtrip <- brohn_parse(brohn_json(mapped))
  check("single-channel and empty nuisance arrays survive serializer", brohn_array(roundtrip$value_columns) && length(roundtrip$value_columns) == 1 && brohn_array(roundtrip$parameters$nuisance_codes) && !length(roundtrip$parameters$nuisance_codes))
  array_input <- input; array_input$map_eda_event_event_mode <- "array"
  array_input$map_eda_event_events <- "time_s,code,exposure_id\n20,A,trial-1\n40,B,trial-2"
  check("UI supports a measured event list", length(brohn_eda_events_input(array_input, m)$events) == 2)
  reset_input <- input; reset_input$map_eda_event_recording_column <- "reset"; reset_input$map_eda_event_valid_column <- "valid"
  check("UI retains reset and source validity mapping", brohn_eda_events_input(reset_input, m)$recording_column == "reset" && brohn_eda_events_input(reset_input, m)$valid_column == "valid")
  legacy_input <- input; legacy_input$map_eda_event_recipe <- "eda-neurokit-highpass/1.0"
  back <- brohn_eda_events_input(legacy_input, mapped)
  check("changing to recording recipe removes stale event settings", identical(back$parameters, list(recipe = "eda-neurokit-highpass/1.0")) && is.null(back$event_column) && is.null(back$events))
  html <- htmltools::renderTags(brohn_eda_events_settings_ui(m, columns, "csv"))$html
  check("accessible disclosure UI renders labelled controls", grepl('for="map_eda_event_event_codes"', html, fixed = TRUE) && grepl("<summary>", html, fixed = TRUE) && grepl("map_eda_event_valid_column", html, fixed = TRUE))
  check("blank new protocol windows are not invented", grepl('id="map_eda_event_baseline_start"', htmltools::renderTags(brohn_eda_events_settings_ui(list(), columns))$html, fixed = TRUE))
  # Exercise actual R serializer -> pinned scientific runtime -> full receipt.
  scratch <- tempfile("brohn-eda-event-r-"); dir.create(scratch)
  scratch <- normalizePath(scratch, winslash = "/", mustWork = TRUE)
  brohn_require(startsWith(scratch, paste0(normalizePath(tempdir(), winslash = "/"), "/")), "Test cleanup must remain in its fresh temporary directory.")
  on.exit(unlink(scratch, recursive = TRUE), add = TRUE)
  times <- (0:1499)/25; dt <- pmax(times-21, 0)
  values <- 5+.001*times+exp(-dt/2)-exp(-dt/.7)
  condition <- ifelse((0:1499) %/% 50 %% 2 == 0, "control", "test")
  condition[c(501,1001)] <- c("control", "test")
  onset <- exposure <- rep("", 1500); onset[c(501,1001)] <- c("A", "B"); exposure[c(501,1001)] <- c("trial-1", "trial-2")
  csv <- file.path(scratch, "signal.csv")
  utils::write.csv(data.frame(time = times, conductance = values, person = "p1", session = "s1", condition = condition, onset = onset, exposure = exposure), csv, row.names = FALSE)
  request <- list(schema = "brohn-worker-request/1.0", operation = route$operation, modality = "eda", source_path = csv,
    format = "csv", metadata = mapped, parameters = route$parameters)
  request_path <- file.path(scratch, "request.json"); output_path <- file.path(scratch, "result.json")
  writeLines(brohn_json(request), request_path, useBytes = TRUE)
  python <- normalizePath("../../work/tooling/methods-venv/Scripts/python.exe", mustWork = TRUE)
  process <- processx::run(python, c(route$script, "--request", request_path, "--output", output_path), error_on_status = FALSE, timeout = 60000, windows_hide_window = TRUE)
  check("real R to Python request completes", process$status == 0 && file.exists(output_path))
  result <- brohn_parse(paste(readLines(output_path, warn = FALSE, encoding = "UTF-8"), collapse = "\n"))
  check("short source labels retain one full continuous segment", length(result$segments) == 1 && result$segments[[1]]$samples == 1500 && result$quality$computed_window_cells == 2)
  amplitude <- Filter(function(f) f$name == "scr_response_magnitude" && f$exposure_id == "trial-1", result$features)[[1]]
  check("actual SCR matches checked independent pulse fixture", abs(amplitude$value-.3584385402737451) < 1e-8 && amplitude$eligible && amplitude$origin == "sample")
  support <- brohn_eda_events_support(result)
  check("support preserves measure-specific available denominators", length(support$rows) == 2 && all(vapply(support$measures, function(x) identical(x$denominator_scope, "event/channel support; not independent people"), logical(1))))
  support_html <- htmltools::renderTags(brohn_eda_events_support_ui(result))$html
  check("support table has accessible row/column headers and receipt identities", grepl('scope="col"', support_html, fixed = TRUE) && grepl('scope="row"', support_html, fixed = TRUE) && grepl("trial-1", support_html, fixed = TRUE))
  # A supported window does not make an unavailable SCR eligible in the summary.
  bad_result <- result
  target <- which(vapply(bad_result$features, function(f) f$name == "scr_response_magnitude", logical(1)))[1]
  bad_result$features[[target]]$eligible <- FALSE; bad_result$features[[target]]$support_status <- "unavailable"
  bad_result$features[[target]]$missing_reason <- "ambiguous_overlapping_events"
  summary <- Filter(function(x) x$name == "scr_response_magnitude", brohn_eda_events_support(bad_result)$measures)[[1]]
  check("finite stale values cannot override unavailable eligibility", summary$eligible_event_channel_cells == 1 && summary$unavailable_event_channel_cells == 1)
  for (module in c("platform-store", "platform-publication", "platform-methods", "platform-delivery", "platform-library", "platform-analysis", "platform-physiology-artifacts", "platform-vision", "platform-jobs")) source(paste0("R/", module, ".R"), encoding = "UTF-8")
  for (module in c("questionnaire-artifacts", "questionnaire-artifact-storage")) source(paste0("R/platform-",module,".R"),encoding="UTF-8")
  store <- brohn_open_store(file.path(scratch, "workspace"))
  on.exit(brohn_close_store(store), add = TRUE, after = FALSE)
  brohn_initialise_library(store)
  one <- utils::read.csv(csv, colClasses = "character", check.names = FALSE)
  second <- one; second$person <- "p2"
  full_csv <- file.path(scratch, "two-continuous-people.csv")
  utils::write.csv(rbind(one, second), full_csv, row.names = FALSE)
  imported <- brohn_ingest_dataset(store, full_csv, "Synthetic continuous-context EDA", modality = "eda", origin = "sample")
  mapped$origin_statement <- "Synthetic conductance and measured onset arithmetic fixture; no empirical participants or device claim."
  accepted <- brohn_curate_dataset(store, imported$id, mapped, imported$revision)
  queued <- brohn_queue_dataset(store, accepted$id)
  claim <- brohn_claim_job(store, "eda-event-qa", lease_seconds = 60)
  brohn_process_job(store, claim, timeout_seconds = 60)
  finished <- brohn_get_job(store, queued$id)
  if (!identical(finished$status, "succeeded")) stop(paste("Durable EDA job failed:", brohn_json(finished$error)))
  check("fenced supervisor publishes EDA event job", identical(finished$status, "succeeded"))
  saved <- brohn_get_entity(store, "report", finished$result$report_id)
  amplitude <- Filter(function(f) f$name == "scr_response_magnitude" && f$exposure_id == "trial-1", saved$body$analysis$features)[[1]]
  check("saved report preserves full continuous context and qualified event amplitude", abs(amplitude$value-.3584385402737451) < 1e-8 &&
    length(saved$body$analysis$segments) == 2 && identical(saved$body$analysis$parameters$`recording-1`$recipe, "eda-event-highpass/1.0"))
  artifacts <- saved$body$analysis$artifacts
  complete <- Filter(function(a) a$kind == "physiology-series", artifacts)[[1]]
  check("full immutable artifact exceeds bounded report preview", complete$rows == 3000 && complete$tables == 2 &&
    length(saved$body$analysis$series) == 2000 && isTRUE(complete$complete) && is.null(complete$path) && complete$media_type == "application/x-ndjson")
  complete_path <- brohn_object_path(store, complete$hash)
  header <- brohn_parse(readLines(complete_path, n = 1, encoding = "UTF-8", warn = FALSE))
  check("processed artifact binds source hash and explicit clock provenance", identical(header$provenance$source_sha256, accepted$body$source$hash) &&
    identical(header$provenance_sha256, complete$provenance_sha256) && identical(header$schema, "brohn-physiology-tables/1.0"))
  artifact_bytes <- readBin(complete_path, "raw", n = complete$size)
  check("stored complete artifact bytes match immutable object receipt", length(artifact_bytes) == complete$size &&
    identical(digest::digest(artifact_bytes, algo = "sha256", serialize = FALSE), complete$hash))
  validation <- saved$body$analysis
  validation$artifacts <- lapply(validation$artifacts, function(a) { a$sha256 <- a$hash; a$bytes <- a$size; a })
  check("typed verification receipt matches complete manifest", identical(brohn_validate_physiology_artifact_receipt(validation), TRUE))
  missing <- validation; missing$artifact_verification <- NULL
  check("missing verification receipt rejected", rejects(brohn_validate_physiology_artifact_receipt(missing)))
  tampered <- validation; tampered$artifact_verification$artifacts[[1]]$rows <- 1
  check("tampered verification row count rejected", rejects(brohn_validate_physiology_artifact_receipt(tampered)))
  tampered <- validation; tampered$artifact_verification$artifacts[[1]]$sha256 <- paste(rep("a", 64), collapse = "")
  check("swapped artifact verification hash rejected", rejects(brohn_validate_physiology_artifact_receipt(tampered)))
  hash <- brohn_hash(saved$body)
  brohn_close_store(store); store <- brohn_open_store(file.path(scratch, "workspace"))
  reopened <- brohn_get_entity(store, "report", saved$id)
  check("EDA event report and source survive restart with verified hashes", identical(brohn_hash(reopened$body), hash) &&
    identical(digest::digest(file = brohn_object_path(store, accepted$body$source$hash), algo = "sha256"), accepted$body$source$hash))
  check("saved immutable result matches fenced receipt", identical(saved$body$result_object$hash, finished$result$output_hash) &&
    identical(digest::digest(file = brohn_object_path(store, finished$result$output_hash), algo = "sha256"), finished$result$output_hash))
  reopened_artifact <- Filter(function(a) a$kind == "physiology-series", reopened$body$analysis$artifacts)[[1]]
  download <- file.path(scratch, "downloaded-complete-signal.ndjson")
  brohn_require(file.copy(brohn_object_path(store, reopened_artifact$hash), download, overwrite = FALSE), "Test artifact download copy failed.")
  check("reopened processed artifact downloads byte-for-byte", identical(readBin(download, "raw", n = reopened_artifact$size), artifact_bytes))
  cat(sprintf("Brohn EDA event mapping: %d checks passed.\n", checks))
})
