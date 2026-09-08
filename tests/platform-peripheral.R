source("R/platform-core.R"); source("R/platform-peripheral.R"); source("R/platform-peripheral-views.R")
local({
  checks <- 0L
  check <- function(label, ok) {if (!isTRUE(ok)) stop("Peripheral R QA: ", label, call. = FALSE); checks <<- checks+1L}
  rejects <- function(expr) inherits(try(force(expr), silent = TRUE), "try-error")
  m <- list(time_column = "time", time_unit = "s", sampling_rate = 1, value_columns = list("temperature"), unit = "degC",
    origin_statement = "Original synthetic numerical fixture; no physical device or participant.",
    calibration_source = "Original generator explicitly declares Celsius values.", sensor_site = "Synthetic peripheral site",
    acquisition_filters = "No source filters", recording_conditions = "Original numerical fixture; no physical ambient/contact/settling period.", parameters = list())
  check("calibrated temperature mapping validates without inventing source origin", identical(brohn_validate_peripheral_mapping(m, c("time", "temperature"), "csv", "temperature"), m))
  spec <- brohn_peripheral_worker_request(m, "csv", c("time", "temperature"), "temperature")
  check("dispatch uses a dedicated peripheral profile and methods environment", spec$operation == "peripheral" && spec$python_profile == "methods" &&
    spec$script == "scripts/workers/peripheral.py" && spec$parameters$recipe == "temperature-calibrated-descriptive/1.0" && is.null(spec$parameters$threshold))
  slow <- m; slow$sampling_rate <- .1
  check("omitted defaults support recorded low-frequency temperature", brohn_peripheral_worker_request(slow, modality = "temperature")$parameters$minimum_duration_s == 10)
  slow$parameters$minimum_duration_s <- 1
  check("explicit invalid low-rate duration is not silently corrected", rejects(brohn_peripheral_worker_request(slow, modality = "temperature")))
  for (unit in c("degC", "K", "degF")) {x <- m; x$unit <- unit; check(paste("explicit unit", unit), !rejects(brohn_validate_peripheral_mapping(x, modality = "temperature")))}
  x <- m; x$unit <- "V"; check("voltage is not silently calibrated temperature", rejects(brohn_validate_peripheral_mapping(x, modality = "temperature")))
  x <- m; x$calibration_source <- ""; check("calibration provenance is required", rejects(brohn_validate_peripheral_mapping(x, modality = "temperature")))
  x <- m; x$sensor_site <- ""; check("placement is required", rejects(brohn_validate_peripheral_mapping(x, modality = "temperature")))
  x <- m; x$acquisition_filters <- ""; check("source filtering policy is required", rejects(brohn_validate_peripheral_mapping(x, modality = "temperature")))
  x <- m; x$recording_conditions <- ""; check("temperature recording conditions cannot be silently assumed", rejects(brohn_validate_peripheral_mapping(x, modality = "temperature")))
  x <- m; x$participant_column <- "person"; check("participant and session mapping must be paired", rejects(brohn_validate_peripheral_mapping(x, modality = "temperature")))
  x$session_column <- "visit"; x$segment_column <- "reset"
  check("explicit identities and reset segment column are supported", !rejects(brohn_validate_peripheral_mapping(x, c("time", "temperature", "person", "visit", "reset"), "tsv", "temperature")))
  x$segment_column <- "temperature"; check("measurement cannot double as identity", rejects(brohn_validate_peripheral_mapping(x, modality = "temperature")))
  x <- m; x$sampling_rate <- TRUE; check("boolean cannot become sample rate", rejects(brohn_validate_peripheral_mapping(x, modality = "temperature")))
  x <- m; x$timestamp_tolerance_s <- .4; check("timing tolerance is bounded", rejects(brohn_validate_peripheral_mapping(x, modality = "temperature")))
  check("missing source column fails mapping review", rejects(brohn_validate_peripheral_mapping(m, "time", "csv", "temperature")))
  check("unsupported native reader does not use a generic analysis", rejects(brohn_validate_peripheral_mapping(m, source_format = "edf", modality = "temperature")))
  check("EOG cannot enter a generic shared detector", rejects(brohn_peripheral_worker_request(m, modality = "eog")))
  x <- m; x$parameters <- list(recipe = "generic-arousal")
  check("unknown scientific profile fails closed", rejects(brohn_validate_peripheral_mapping(x, modality = "temperature")))
  movement <- m; movement$value_columns <- list("x", "y", "z"); movement$unit <- "g"
  movement$recording_conditions <- NULL
  movement$axis_labels <- list("positive right", "positive forward", "positive up"); movement$gravity_policy <- "included"
  check("explicit ordered tri-axial source validates", !rejects(brohn_validate_peripheral_mapping(movement, c("time", "x", "y", "z"), "csv", "movement")))
  movement$parameters <- list(enmo = "untruncated")
  check("named ENMO handling preserves negative values when declared", brohn_peripheral_worker_request(movement, modality = "movement")$parameters$enmo == "untruncated")
  movement$gravity_policy <- "removed"
  check("gravity cannot be subtracted a second time", rejects(brohn_validate_peripheral_mapping(movement, modality = "movement")))
  movement$parameters$enmo <- "disabled"
  check("gravity-removed source still supports descriptive acceleration", !rejects(brohn_validate_peripheral_mapping(movement, modality = "movement")))
  movement$value_columns <- list("x", "z"); check("missing axis cannot fabricate a vector", rejects(brohn_validate_peripheral_mapping(movement, modality = "movement")))
  h <- list(metric = "temperature_c", direction = "above", on = 22, off = 21, minimum_duration_s = 1, source = "Original operational threshold.")
  x <- m; x$parameters <- list(threshold = h)
  check("threshold is an explicit opt-in with rationale", identical(brohn_peripheral_parameters(x, "temperature")$threshold, h))
  x$parameters$threshold$off <- 23; check("inconsistent hysteresis fails", rejects(brohn_validate_peripheral_mapping(x, modality = "temperature")))
  x$parameters$threshold <- h; x$parameters$threshold$source <- ""; check("threshold interpretation requires its protocol source", rejects(brohn_validate_peripheral_mapping(x, modality = "temperature")))

  html <- as.character(brohn_peripheral_settings_ui(m, c("time", "temperature"), "temperature"))
  check("settings use one labelled canonical unit control and grouped fields", length(gregexpr('id="map_unit"', html, fixed = TRUE)[[1L]]) == 1L &&
    grepl("<fieldset>", html, fixed = TRUE) && grepl('for="map_peripheral_calibration"', html, fixed = TRUE))
  check("threshold numeric values and scientific cutoffs are initially blank", grepl('id="map_peripheral_threshold_on" type="text" class="shiny-input-text form-control" value=""', html, fixed = TRUE) &&
    !grepl('id="map_peripheral_threshold" type="checkbox" checked', html, fixed = TRUE))
  inputs <- list(map_unit = "degC", map_peripheral_site = m$sensor_site, map_peripheral_calibration = m$calibration_source,
    map_peripheral_filters = m$acquisition_filters, map_peripheral_conditions = m$recording_conditions, map_peripheral_min_duration = 1, map_peripheral_threshold = FALSE,
    map_peripheral_enmo = "stale-movement-value", map_peripheral_threshold_on = "stale-not-numeric")
  captured <- brohn_peripheral_input(inputs, m, "temperature")
  check("disabled threshold and another family cannot leak stale controls", is.null(captured$parameters$threshold) && is.null(captured$parameters$enmo) &&
    identical(captured$origin_statement, m$origin_statement) && captured$unit == "degC")
  inputs$map_peripheral_threshold <- TRUE
  check("enabled threshold requires its actual numeric entries", rejects(brohn_peripheral_input(inputs, m, "temperature")))
  inputs$map_peripheral_threshold_metric <- "temperature_c"; inputs$map_peripheral_threshold_direction <- "above"
  inputs$map_peripheral_threshold_on <- "22.5"; inputs$map_peripheral_threshold_off <- "21"; inputs$map_peripheral_threshold_duration <- "1e0"
  inputs$map_peripheral_threshold_source <- "Original operational threshold reference."
  captured <- brohn_peripheral_input(inputs, m, "temperature")
  check("threshold capture produces explicit numeric canonical settings", captured$parameters$threshold$on == 22.5 && captured$parameters$threshold$off == 21 &&
    captured$parameters$threshold$minimum_duration_s == 1 && captured$parameters$threshold$metric == "temperature_c")
  inputs$map_peripheral_threshold <- FALSE
  check("unchecking threshold intentionally clears a previously saved detector", is.null(brohn_peripheral_input(inputs, captured, "temperature")$parameters$threshold))
  movement$value_columns <- list("x", "y", "z"); movement$gravity_policy <- "included"
  mi <- inputs; mi$map_unit <- "g"; mi$map_peripheral_axis_x <- "positive right"; mi$map_peripheral_axis_y <- "positive forward"; mi$map_peripheral_axis_z <- "positive up"
  mi$map_peripheral_gravity <- "included"; mi$map_peripheral_enmo <- "untruncated"
  captured_movement <- brohn_peripheral_input(mi, movement, "movement")
  check("movement capture preserves ordered selected channels and signed axes", identical(captured_movement$value_columns, list("x", "y", "z")) &&
    identical(captured_movement$axis_labels, list("positive right", "positive forward", "positive up")) && captured_movement$parameters$enmo == "untruncated")
  movement_html <- as.character(brohn_peripheral_settings_ui(captured_movement, c("time", "x", "y", "z"), "movement"))
  check("saved movement view restores gravity and ENMO choices without relabelling channels", grepl('value="included" selected', movement_html, fixed = TRUE) &&
    grepl('value="untruncated" selected', movement_html, fixed = TRUE) && grepl("selected channel 1", movement_html, fixed = TRUE))

  root <- tempfile("brohn-peripheral-r-"); dir.create(root); root <- normalizePath(root, winslash = "/")
  on.exit({actual <- normalizePath(root, winslash = "/", mustWork = FALSE)
    stopifnot(startsWith(tolower(actual), paste0(tolower(normalizePath(tempdir(), winslash = "/")), "/")), grepl("^brohn-peripheral-r-", basename(actual)))
    unlink(actual, recursive = TRUE, force = TRUE)}, add = TRUE)
  python <- Sys.getenv("BROHN_PYTHON_METHODS", "../../work/tooling/methods-venv/Scripts/python.exe")
  brohn_require(file.exists(python), "Configure the prepared methods environment before the actual R-to-Python check.")
  run_worker <- function(modality, metadata, rows, format = "csv") {
    directory <- file.path(root, paste0(modality, "-", format)); dir.create(directory); dir.create(file.path(directory, "artifacts"))
    source <- file.path(directory, paste0("original.", format)); utils::write.table(rows, source, sep = if (format == "tsv") "\t" else ",",
      row.names = FALSE, quote = TRUE, qmethod = "double", na = "", fileEncoding = "UTF-8")
    dispatch <- brohn_peripheral_worker_request(metadata, format, names(rows), modality)
    metadata <- dispatch$metadata
    metadata$origin <- "sample"
    request <- list(schema = "brohn-worker-request/1.0", operation = dispatch$operation, modality = modality,
      format = format, source_path = source, source_hash = digest::digest(file = source, algo = "sha256"), metadata = metadata,
      parameters = dispatch$parameters, artifact_directory = file.path(directory, "artifacts"))
    request_path <- file.path(directory, "request.json"); result_path <- file.path(directory, "result.json")
    writeBin(charToRaw(brohn_json(request)), request_path)
    process <- processx::run(python, c("-B", dispatch$script, "--request", request_path, "--output", result_path),
      timeout = 30000, error_on_status = FALSE, windows_hide_window = TRUE)
    result <- brohn_parse(paste(readLines(result_path, warn = FALSE), collapse = "\n"))
    if (process$status != 0) stop("Actual peripheral worker failed: ", brohn_json(result$error), call. = FALSE)
    list(result = result, request = request)
  }
  generated <- data.frame(time = 0:4, temperature = 20:24)
  actual <- run_worker("temperature", m, generated)
  feature <- function(result, name) Filter(function(f) identical(f$name, name), result$features)[[1L]]$value
  check("actual R JSON dispatch reproduces original temperature slope", abs(feature(actual$result, "temperature_linear_slope")-60) < 1e-12 &&
    abs(feature(actual$result, "temperature_mean")-22) < 1e-12 && actual$result$source$sha256 == actual$request$source_hash)
  check("actual worker retains both complete typed artifact streams", length(actual$result$artifacts) == 2L && all(vapply(actual$result$artifacts, function(a)
    file.exists(a$path) && digest::digest(file = a$path, algo = "sha256") == a$sha256 && isTRUE(a$complete), logical(1))))
  x <- m; x$unit <- "K"; generated$temperature <- generated$temperature+273.15
  tabbed <- run_worker("temperature", x, generated, "tsv")
  check("actual TSV calibration matches Celsius reference", abs(feature(tabbed$result, "temperature_time_weighted_mean")-22) < 1e-10)
  movement$value_columns <- list("x", "y", "z"); movement$gravity_policy <- "included"; movement$parameters$enmo <- "zero_truncated"
  acceleration <- run_worker("movement", movement, data.frame(time = 0:4, x = 0, y = 0, z = 1))
  check("actual R movement dispatch preserves static gravity and zero ENMO", abs(feature(acceleration$result, "acceleration_magnitude_mean")-9.80665) < 1e-12 &&
    feature(acceleration$result, "enmo_mean") == 0 && feature(acceleration$result, "acceleration_vector_derivative_rms") == 0)
  check("reported support avoids fabricated participant and physical-device claims", is.null(acceleration$result$quality$participant_count) &&
    !acceleration$result$quality$physical_device_qualified && !acceleration$result$quality$scientifically_qualified && acceleration$result$quality$usable_samples == 5)
  cat("Brohn peripheral R: ", checks, " checks passed (including actual isolated Python CLI dispatch).\n", sep = "")
})
