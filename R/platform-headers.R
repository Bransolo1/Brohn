# Header inspection is queued metadata preparation, never a scientific report.
brohn_header_formats <- function() c("edf", "bdf", "fif", "set", "snirf", "wav")

brohn_parse_native_channel_input <- function(value) {
  if (is.null(value) || !nzchar(trimws(value))) return(character())
  brohn_require(brohn_text(value, 30000), "Enter native channel names or a JSON array of exact names.")
  value <- trimws(value)
  if (startsWith(value, "[")) {
    parsed <- tryCatch(brohn_parse(value), error = function(e) NULL)
    brohn_require(is.list(parsed) && is.null(names(parsed)) && all(vapply(parsed, brohn_text, logical(1), max = 200)),
      "Use a JSON array of quoted channel names when names contain commas.")
    channels <- unlist(parsed, use.names = FALSE)
  } else {
    channels <- trimws(strsplit(value, ",", fixed = TRUE)[[1L]])
    channels <- channels[nzchar(channels)]
  }
  brohn_require(length(channels) <= 512L && !anyDuplicated(channels) && all(vapply(as.list(channels), brohn_text, logical(1), max = 200)),
    "Native channel names must be unique, nonempty and no longer than 200 characters.")
  channels
}

brohn_native_channel_input_text <- function(channels) {
  # JSON is used only when plain comma-separated text would lose an identity.
  if (any(grepl(",|[\r\n]|^\\s*\\[", channels)) || any(channels != trimws(channels))) brohn_json(as.list(channels)) else paste(channels, collapse = ", ")
}

brohn_queue_header_inspection <- function(store, dataset_id, revision = NULL, force = FALSE) {
  record <- brohn_get_entity(store, "dataset", dataset_id, revision)
  brohn_require(!is.null(record), "Choose an available recording revision.")
  brohn_project(store, record$project_id)
  brohn_require(record$body$source$format %in% brohn_header_formats(), "This format does not have a native header inspector.")
  brohn_object_path(store, record$body$source$hash)
  request <- list(dataset_id = record$id, dataset_revision = record$revision, dataset_hash = brohn_hash(record$body),
    source_hash = record$body$source$hash, project_id = record$project_id, recipe = "native-header-inspection/1.0.0")
  brohn_enqueue_job(store, "inspect_header", request, paste0("native-header:", brohn_hash(request), if (isTRUE(force)) paste0(":", brohn_id("retry")) else ""))
}

brohn_header_input <- function(store, job) {
  r <- job$request; record <- brohn_get_entity(store, "dataset", r$dataset_id, r$dataset_revision)
  brohn_require(!is.null(record) && identical(record$project_id, r$project_id) && identical(brohn_hash(record$body), r$dataset_hash) &&
    identical(record$body$source$hash, r$source_hash), "The pinned native recording failed its integrity check.")
  brohn_require(record$body$source$format %in% brohn_header_formats(), "This format has no native header adapter.")
  list(schema = "brohn-analysis-input/1.0", operation = "inspect_header", dataset = record$body,
    dataset_revision = record$revision, project_id = record$project_id, source_path = brohn_object_path(store, r$source_hash))
}

brohn_header_request <- function(input) list(schema = "brohn-header-request/1.0", operation = "inspect_header",
  source_path = normalizePath(input$source_path, winslash = "/", mustWork = TRUE), source_hash = input$dataset$source$hash, format = input$dataset$source$format)

brohn_validate_header_result <- function(result, input) {
  brohn_require(identical(result$schema, "brohn-header-result/1.0") && identical(result$operation, "inspect_header") &&
    result$status %in% c("inspected", "needs_attention"), "The native header inspector returned an incompatible result.")
  brohn_require(identical(result$source$sha256, input$dataset$source$hash) && identical(result$source$format, input$dataset$source$format) &&
    identical(as.numeric(result$source$bytes), as.numeric(input$dataset$source$size)), "The inspected header refers to different source bytes.")
  h <- result$header
  brohn_require(is.list(h$channels) && length(h$channels) >= 1L && length(h$channels) <= 512L &&
    identical(as.numeric(h$channel_count), as.numeric(length(h$channels))), "The inspected channel manifest is incomplete.")
  for (channel in h$channels) {
    brohn_require(brohn_text(channel$name, 200) && brohn_number(channel$index, 0, 511) &&
      brohn_text(channel$type, 200) && (is.null(channel$source_unit) || brohn_text(channel$source_unit, 200)) &&
      (is.null(channel$analysis_unit) || brohn_text(channel$analysis_unit, 200)), "The inspected native channel metadata is invalid.")
    brohn_require((is.null(channel$sampling_rate_hz) || brohn_number(channel$sampling_rate_hz, 1e-9, 1e9)) &&
      brohn_number(channel$sample_count, 0, 1e12), "The inspected channel rate or sample count is invalid.")
  }
  brohn_require(length(h$annotations$preview) <= 100L && (is.null(h$annotations$count) || brohn_number(h$annotations$count, 0, 100000)), "The annotation preview is oversized.")
  brohn_require(identical(h$quality$signal_processing_applied, FALSE) && identical(h$quality$identities_inferred, FALSE) &&
    isTRUE(h$quality$source_hash_verified), "Header inspection must not process signals or infer identities.")
  invisible(result)
}

brohn_analyse_header <- function(input, scratch) {
  request <- brohn_header_request(input)
  request_path <- file.path(scratch, "header-request.json"); output_path <- file.path(scratch, "header-result.json")
  brohn_write_json_file(request, request_path)
  python <- brohn_python_profile(if (request$format == "snirf") "fnirs" else if (request$format == "wav") "audio" else "eeg")
  process <- processx::run(python, c("scripts/workers/headers.py", "--request", request_path, "--output", output_path),
    timeout = 120, error_on_status = FALSE, echo = FALSE, cleanup_tree = TRUE, windows_hide_window = TRUE)
  brohn_require(file.exists(output_path), paste("The recording header could not be inspected.", substr(process$stderr, 1, 1000)))
  result <- brohn_read_json_file(output_path, maximum = 2*1024^2)
  brohn_require(process$status == 0 && !identical(result$status, "error"), paste("Native header needs attention:",
    brohn_default(result$error$message, substr(process$stderr, 1, 2000))))
  brohn_validate_header_result(result, input)
  list(title = paste(input$dataset$title, "recording header"), dataset_id = input$dataset$id,
    dataset_revision = input$dataset_revision, source_hash = input$dataset$source$hash, origin = input$dataset$origin, header_inspection = result)
}

brohn_publish_header_inspection <- function(store, output, scratch, job, input, output_path) {
  brohn_require(!RSQLite::sqliteIsTransacting(store$con), "Prepare native header results outside the publication transaction.")
  .brohn_publication_job(store,job)
  brohn_require(identical(input$dataset$id, job$request$dataset_id) && identical(brohn_hash(input$dataset), job$request$dataset_hash) &&
    identical(as.numeric(input$dataset_revision), as.numeric(job$request$dataset_revision)) && identical(input$project_id, job$request$project_id),
    "Header publication cannot substitute another source revision.")
  result <- output$report$header_inspection
  brohn_validate_header_result(result, input)
  id <- paste0("header-", sub("^job-", "", job$id))
  body <- list(schema_version = "brohn-header-inspection/1.0.0", id = id, title = output$report$title,
    dataset_id = input$dataset$id, dataset_revision = input$dataset_revision, source_hash = input$dataset$source$hash,
    source = input$dataset$source, origin = input$dataset$origin, status = result$status, inspection = result, created_at = brohn_now(),
    processing = list(job_id = job$id, attempt = job$attempt, recipe = "native-header-inspection/1.0.0",
      request_hash = brohn_hash(input), worker_output_hash = digest::digest(file = output_path, algo = "sha256"), code_hashes = output$code_identity))
  body$processing$publication <- list(mode=if(.Platform$OS.type=="windows")"staged-windows-parent-read-seal/1.0"else"legacy-transactional-copy",
    native_seal=.Platform$OS.type=="windows",native_build=if(.Platform$OS.type=="windows").brohn_publication_native()$identity else NULL)
  publication <- file.path(scratch, "published-header.json")
  brohn_write_json_file(list(schema = "brohn-analysis-output/1.0", code_identity = output$code_identity, header_inspection = body), publication)
  brohn_publish_entity_result(store,job,input,output,"header_inspection",body,publication,list(header_id=id,status=result$status))
}
brohn_header_inspections <- function(store, dataset_id, source_hash = NULL, limit = 500L) {
  filters <- list(dataset_id = dataset_id)
  if (!is.null(source_hash)) filters$source_hash <- source_hash
  brohn_list_entities(store, "header_inspection", limit = limit, filters = filters)
}

brohn_header_for_dataset <- function(store, record) {
  records <- brohn_header_inspections(store, record$id, record$body$source$hash)
  if (length(records)) records[[1L]] else NULL
}

brohn_header_mapping_defaults <- function(inspection, channel_names = NULL) {
  # The UI applies these only after an explicit researcher confirmation.
  result <- inspection$body$inspection; h <- result$header
  names <- vapply(h$channels, `[[`, character(1), "name")
  brohn_require(!anyDuplicated(names), "Duplicate source names need a reader-name mapping before channels can be selected.")
  if (is.null(channel_names)) channel_names <- character()
  brohn_require(is.character(channel_names) && length(channel_names) <= 64L && !anyDuplicated(channel_names) &&
    all(channel_names %in% names), "Select available native channels from this recording header.")
  selected <- h$channels[match(channel_names, names)]
  if (result$source$format %in% c("edf", "bdf")) brohn_require(all(vapply(selected, function(c)
    c$source_unit %in% c("V", "mV", "uV") && isTRUE(c$calibration_evidence$valid_linear_range), logical(1))),
    "The selected EDF/BDF channels need declared voltage units and valid calibration ranges before this EEG mapping can use them.")
  rates <- unique(unlist(lapply(selected, `[[`, "sampling_rate_hz"), use.names = FALSE))
  brohn_require(length(rates) <= 1L, "The selected channels have different native rates. Select channels sharing a rate or specify a qualified conversion.")
  list(value_columns = as.list(channel_names), sampling_rate = if (length(rates)) rates[[1L]] else h$recording$sampling_rate_hz,
    unit = if (result$source$format == "wav") "FS" else "native", requires_confirmation = TRUE,
    header_id = inspection$id, source_hash = inspection$body$source_hash)
}
