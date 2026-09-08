source("R/platform-load.R", encoding = "UTF-8"); brohn_load()
local({
  checks <- 0L
  check <- function(name, ok) {if (!isTRUE(ok)) stop("FAILED: ", name); checks <<- checks+1L}
  root <- tempfile("brohn-peripheral-synthesis-"); dir.create(root)
  store <- brohn_open_store(file.path(root, "workspace")); on.exit(brohn_close_store(store), add = TRUE)
  brohn_initialise_library(store); study <- brohn_create_study(store, "Original temperature comparison fixture")
  design <- study$body
  visits <- list(list(p = "P1", v = "V1", change = 2), list(p = "P1", v = "V2", change = 6), list(p = "P2", v = "V1", change = -2))
  rows <- list()
  for (visit in visits) for (condition in 1:2) for (time in 0:2) rows[[length(rows)+1L]] <- data.frame(
    person = visit$p, visit = visit$v, condition = design$conditions[[condition]]$id,
    exposure = paste(visit$v, condition, sep = ":"), time = time, temperature = 30+if (condition == 2) visit$change else 0)
  path <- file.path(root, "original.csv"); utils::write.csv(do.call(rbind, rows), path, row.names = FALSE, quote = TRUE)
  source <- brohn_ingest_dataset(store, path, "Original temperature intervals", "temperature", study$id, origin = "sample")
  metadata <- list(time_column = "time", time_unit = "s", sampling_rate = 1, value_columns = list("temperature"), unit = "degC",
    participant_column = "person", session_column = "visit", condition_column = "condition", exposure_column = "exposure",
    origin_statement = "Original synthetic arithmetic and workflow fixture; no device or participants.",
    calibration_source = "Fixture numbers already in Celsius", sensor_site = "Declared fictional site",
    acquisition_filters = "none", recording_conditions = "Original synthetic fixture; no ambient or settling measurement")
  dataset <- brohn_curate_dataset(store, source$id, metadata, source$revision, study$id, study$revision)
  scratch <- file.path(root, "scratch"); dir.create(scratch)
  input <- list(schema = "brohn-analysis-input/1.0", operation = "analyse_dataset", dataset = dataset$body,
    dataset_revision = dataset$revision, design = design, design_revision = study$revision,
    source_path = brohn_object_path(store, dataset$body$source$hash))
  calculated <- brohn_analyse_input(input, scratch)
  body <- c(list(schema_version = "brohn-report/1.0.0", id = "report-peripheral-fixture", status = "Available", created_at = brohn_now()), calculated)
  saved <- brohn_put_entity(store, "report", body$id, body)
  reference <- list(id = saved$id, revision = saved$revision, hash = brohn_hash(saved$body))
  extracted <- .brohn_mm_extract(saved$body, reference, design)
  means <- Filter(function(r) r$metric == "temperature_mean", extracted)
  check("actual Python intervals enter reviewed synthesis with intact support", length(means) == 6 && all(vapply(means, `[[`, logical(1), "source_eligible")))
  check("original feature hashes and support interval identities are retained", all(vapply(extracted, function(r)
    identical(r$source_row_hash, brohn_hash(body$analysis$features[[r$source_row]])) && brohn_text(r$source_segment_id, 200), logical(1))))
  check("source conditions and person/session identities survive actual processing", length(unique(vapply(means, `[[`, character(1), "condition_id"))) == 2 &&
    length(unique(vapply(means, `[[`, character(1), "source_participant_id"))) == 2)
  links <- lapply(visits, function(v) list(report_id = saved$id, source_participant_id = v$p,
    source_session_id = v$v, participant_id = v$p, session_id = v$v))
  spec <- list(id = "temperature-contrast", report_ids = list(saved$id), modality = "temperature", metric = "temperature_mean",
    outcome_id = "temperature", unit = "degC", control_id = design$conditions[[1]]$id, test_id = design$conditions[[2]]$id)
  request <- brohn_prepare_multimodal(store, study$id, list(saved$id), links, list(spec), "sample",
    identity_source = "Explicit fictional person/session links for the test.", multiplicity = list(method = "holm", alpha = .05))
  result <- brohn_analyse_multimodal(brohn_multimodal_input(store, request))$analysis
  c <- result$contrasts[[1]]
  check("repeat visits contribute equal people, not independent samples", abs(c$estimate-1) < 1e-12 && c$participant_count == 2 && c$paired_session_count == 3)
  no_links <- request; no_links$crosswalk <- list()
  unlinked <- brohn_analyse_multimodal(brohn_multimodal_input(store, no_links))$analysis
  check("matching source names never create identity links", is.null(unlinked$contrasts[[1]]$estimate) && all(vapply(unlinked$observations, function(r) !r$eligible, logical(1))))
  probe <- function(changed) .brohn_mm_extract(changed, reference, design)[[1L]]
  altered <- body; altered$analysis$segments[[1]]$sample_count <- 1
  check("unsupported interval cannot inherit recording-wide eligibility", !probe(altered)$source_eligible)
  altered <- body; altered$analysis$segments <- c(altered$analysis$segments, altered$analysis$segments[1])
  check("ambiguous duplicate support is rejected", !probe(altered)$source_eligible)
  altered <- body; altered$analysis$segments[[1]]$group$participant_id <- "another-person"
  check("support cannot cross source participant identity", !probe(altered)$source_eligible)
  altered <- body; altered$analysis$source$sha256 <- brohn_hash("other source")
  check("peripheral source provenance must match its frozen report", !probe(altered)$source_eligible)
  altered <- body; altered$analysis$parameters$recipe$minimum_duration_s <- 2
  check("changed effective settings cannot inherit the reviewed mapping", !probe(altered)$source_eligible)
  first <- Filter(function(r) r$metric == "temperature_mean", result$observations)[[1]]
  duplicate <- first; duplicate$source_segment_id <- "a-second-fragment"; duplicate$source_row_hash <- brohn_hash("different retained fragment")
  duplicate_result <- .brohn_mm_contrast(spec, c(result$observations, list(duplicate)), design)
  check("two fragments of one exposure need a reviewed pooling rule", is.null(duplicate_result$estimate) && duplicate_result$reason == "duplicate_or_ambiguous_observation_identity")
  altered <- body
  altered$analysis$parameters$mapping$recording_conditions <- "Different declared environment"
  altered$provenance$mapping$recording_conditions <- "Different declared environment"
  changed <- probe(altered); original <- probe(body)
  check("environment and settling declarations belong to the measure definition", changed$source_eligible && original$definition_hash != changed$definition_hash)
  check("ordered source channels are part of the comparison definition", identical(original$definition$mapping$value_columns, metadata$value_columns))
  ui <- as.character(brohn_peripheral_report_ui(body$analysis))
  check("readable report names intervals and disabled detector", grepl("Threshold detection was disabled", ui, fixed = TRUE) && grepl("not independent people", ui, fixed = TRUE))
  unavailable <- body$analysis; unavailable$quality$usable <- FALSE; unavailable$quality$event_detection_requested <- TRUE; unavailable$quality$event_count <- NULL
  check("requested detector without usable support stays unavailable", grepl("number of events is unavailable", as.character(brohn_peripheral_report_ui(unavailable)), fixed = TRUE))
  low_rate <- metadata; low_rate$sampling_rate <- .1
  automatic <- brohn_peripheral_input(list(map_unit = "degC", map_peripheral_site = metadata$sensor_site,
    map_peripheral_calibration = metadata$calibration_source, map_peripheral_filters = "none", map_peripheral_conditions = metadata$recording_conditions,
    map_peripheral_min_duration = NA_real_, map_peripheral_threshold = FALSE), low_rate, "temperature")
  check("blank UI duration freezes the appropriate low-rate support", automatic$parameters$minimum_duration_s == 10)
  blank_input <- list(map_unit = "degC", map_peripheral_site = metadata$sensor_site,
    map_peripheral_calibration = metadata$calibration_source, map_peripheral_filters = "none", map_peripheral_conditions = metadata$recording_conditions,
    map_peripheral_min_duration = NA, map_peripheral_threshold = FALSE)
  check("Shiny logical NA blank duration freezes low-rate support", brohn_peripheral_input(blank_input, low_rate, "temperature")$parameters$minimum_duration_s == 10)
  for (invalid in list(FALSE, TRUE, "", "10", c(NA_real_, 10), 1)) {
    invalid_input <- blank_input; invalid_input$map_peripheral_min_duration <- invalid
    check("explicit malformed or unsupported durations are not automatic", inherits(try(brohn_peripheral_input(invalid_input, low_rate, "temperature"), silent = TRUE), "try-error"))
  }
  check("peripheral plot quantities have readable labels", brohn_signal_label("vector_magnitude_ms2") == "Acceleration vector magnitude" && brohn_signal_label("temperature_c") == "Temperature")
  cat(sprintf("PASS: %d actual-worker peripheral synthesis and report checks\n", checks))
})
