# R owns reviewed calibrated peripheral mappings; numerical work runs outside UI.
brohn_peripheral_recipe_choices <- function(modality) {
  brohn_require(modality %in% c("temperature", "movement"), "Choose calibrated temperature or tri-axial acceleration. EOG requires a separate montage and detector profile.")
  if (modality == "temperature") c("Calibrated temperature descriptions" = "temperature-calibrated-descriptive/1.0") else
    c("Calibrated tri-axial acceleration descriptions" = "acceleration-calibrated-triaxial/1.0")
}
brohn_peripheral_defaults <- function(modality) {
  result <- list(recipe = unname(brohn_peripheral_recipe_choices(modality)), minimum_duration_s = 1, threshold = NULL)
  if (modality == "movement") result$enmo <- "disabled"
  result
}
brohn_peripheral_parameters <- function(m, modality) {
  p <- brohn_peripheral_defaults(modality); supplied <- brohn_default(m$parameters, list())
  brohn_require(is.list(supplied), "Peripheral settings must be an object.")
  if (length(supplied)) brohn_fields(supplied, character(), names(p), "Peripheral settings")
  for (name in names(supplied)) p[name] <- supplied[name]
  brohn_require(identical(p$recipe, unname(brohn_peripheral_recipe_choices(modality))), "Choose the supported named peripheral recipe.")
  fs <- m$sampling_rate
  brohn_require(brohn_number(fs, .1, if (modality == "temperature") 1000 else 10000), "Declare the peripheral sampling rate in Hz.")
  if (!"minimum_duration_s" %in% names(supplied)) p$minimum_duration_s <- max(1, 1/fs)
  brohn_require(brohn_number(p$minimum_duration_s, 1/fs, 86400), "Minimum contiguous support must be between one sample interval and one day.")
  if (modality == "movement") {
    brohn_require(p$enmo %in% c("disabled", "untruncated", "zero_truncated"), "Choose explicit ENMO negative-value handling or disable it.")
    brohn_require(p$enmo == "disabled" || identical(m$gravity_policy, "included"), "ENMO subtracts one standard g and needs gravity-included source acceleration.")
  }
  if (!is.null(p$threshold)) {
    h <- p$threshold
    brohn_fields(h, c("metric", "direction", "on", "off", "minimum_duration_s", "source"), label = "Opt-in threshold excursion")
    allowed <- if (modality == "temperature") "temperature_c" else c("vector_magnitude_ms2", if (p$enmo != "disabled") "enmo_g")
    brohn_require(h$metric %in% allowed && h$direction %in% c("above", "below") && brohn_text(h$source, 4000), "Declare an available threshold metric, direction and protocol rationale.")
    brohn_require(brohn_number(h$on, -1e12, 1e12) && brohn_number(h$off, -1e12, 1e12) &&
      if (h$direction == "above") h$on >= h$off else h$on <= h$off, "Threshold off boundary must return toward the inactive side.")
    brohn_require(brohn_number(h$minimum_duration_s, 1/fs, 86400), "Threshold duration needs at least one observed sample interval and at most one day.")
  }
  p
}
brohn_validate_peripheral_mapping <- function(m, columns = NULL, source_format = NULL, modality) {
  brohn_peripheral_recipe_choices(modality)
  brohn_require(is.null(source_format) || source_format %in% c("csv", "tsv"), "Calibrated peripheral features currently accept CSV or TSV. Native transports need their own reader.")
  required <- c("time_column", "time_unit", "sampling_rate", "value_columns", "unit", "origin_statement", "calibration_source", "sensor_site", "acquisition_filters")
  if (modality == "movement") required <- c(required, "axis_labels", "gravity_policy")
  else required <- c(required, "recording_conditions")
  groups <- paste0(c("participant", "session", "condition", "exposure", "segment"), "_column")
  brohn_fields(m, required, c(groups, "origin", "timestamp_tolerance_s", "parameters"), "Peripheral mapping")
  for (field in c("time_column", "origin_statement", "calibration_source", "sensor_site", "acquisition_filters"))
    brohn_require(brohn_text(m[[field]], if (field == "time_column") 500 else 4000), paste("Declare", field, "before analysis."))
  if (modality == "temperature") brohn_require(brohn_text(m$recording_conditions, 4000), "Describe recording conditions and settling time; explicitly state unknown when unavailable.")
  if (!is.null(m[["origin"]])) brohn_require(m[["origin"]] %in% c("sample", "preview", "pilot", "live", "imported"), "The immutable source origin is unavailable.")
  count <- if (modality == "temperature") 1L else 3L
  brohn_require(brohn_array(m$value_columns) && length(m$value_columns) == count &&
    all(vapply(m$value_columns, brohn_text, logical(1), max = 500)) && !anyDuplicated(unlist(m$value_columns)), paste("Select exactly", count, "distinct channels; acceleration order is source x, y, z."))
  mapped_groups <- Filter(Negate(is.null), m[groups])
  brohn_require(all(vapply(mapped_groups, brohn_text, logical(1), max = 500)) &&
    identical(is.null(m$participant_column), is.null(m$session_column)), "Map participant/session together and keep all grouping identities distinct.")
  selected <- c(m$time_column, unlist(m$value_columns, use.names = FALSE), unlist(mapped_groups, use.names = FALSE))
  brohn_require(!anyDuplicated(selected), "Time, selected signals and identity columns must be distinct.")
  if (!is.null(columns)) brohn_require(is.character(columns) && length(columns) <= 1024 && !anyNA(columns) &&
    !anyDuplicated(columns) && all(nzchar(columns)) && all(selected %in% columns), "A declared peripheral column is absent or the source header is ambiguous.")
  brohn_require(m$time_unit %in% c("s", "ms", "us", "ns", "sample"), "Declare the source clock unit.")
  fs <- m$sampling_rate
  brohn_require(brohn_number(fs, .1, if (modality == "temperature") 1000 else 10000), "Declare the source sampling rate; this recipe does not resample.")
  if (!is.null(m$timestamp_tolerance_s)) brohn_require(brohn_number(m$timestamp_tolerance_s, 0, .25/fs), "Timestamp tolerance cannot exceed one quarter of a sample interval.")
  if (modality == "temperature") brohn_require(m$unit %in% c("degC", "K", "degF"), "Temperature needs calibrated degC, K or degF, not raw sensor counts or voltage.") else {
    brohn_require(m$unit %in% c("g", "m/s2"), "Acceleration needs calibrated g or m/s2, not raw counts or voltage.")
    brohn_require(brohn_array(m$axis_labels) && length(m$axis_labels) == 3L &&
      all(vapply(m$axis_labels, brohn_text, logical(1), max = 500)) && !anyDuplicated(unlist(m$axis_labels)), "Describe the three distinct signed source axes in their recorded order.")
    brohn_require(m$gravity_policy %in% c("included", "removed"), "Declare whether acquisition already removed gravity.")
  }
  brohn_peripheral_parameters(m, modality)
  invisible(m)
}
brohn_peripheral_worker_request <- function(m, source_format = NULL, columns = NULL, modality) {
  brohn_validate_peripheral_mapping(m, columns, source_format, modality)
  parameters <- brohn_peripheral_parameters(m, modality)
  m$parameters <- parameters
  list(operation = "peripheral", script = "scripts/workers/peripheral.py", python_profile = "methods",
       parameters = parameters, metadata = m)
}
