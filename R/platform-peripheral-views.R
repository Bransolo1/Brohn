# Source review controls only. Shared Data forms own channel/timing/identity fields.
brohn_peripheral_settings_ui <- function(metadata, columns, modality) {
  brohn_peripheral_recipe_choices(modality)
  m <- brohn_default(metadata, list()); p <- brohn_peripheral_defaults(modality)
  for (name in intersect(names(m$parameters), names(p))) p[name] <- m$parameters[name]
  threshold <- p$threshold
  unit_choices <- if (modality == "temperature") c("Degrees Celsius" = "degC", "Kelvin" = "K", "Degrees Fahrenheit" = "degF") else
    c("Standard gravity (g)" = "g", "Metres per second squared" = "m/s2")
  display_number <- function(value) if (is.null(value)) "" else format(value, digits = 17, trim = TRUE, scientific = FALSE)
  axis_label <- function(index, axis) paste0("Signed ", axis, " axis (selected channel ", index, ")")
  shiny::tagList(
    shiny::tags$fieldset(shiny::tags$legend(if (modality == "temperature") "Calibrated temperature" else "Calibrated acceleration"),
      shiny::p("Confirm what these source values physically represent. These descriptions do not classify arousal, emotion or attention."),
      shiny::div(class = "brohn-form-grid",
        shiny::selectInput("map_unit", "Calibrated source unit", c("Choose the source unit" = "", unit_choices), selected = brohn_default(m$unit, "")),
        shiny::textInput("map_peripheral_site", "Sensor placement or site", brohn_default(m$sensor_site, ""))),
      shiny::textAreaInput("map_peripheral_calibration", "Calibration evidence and source", brohn_default(m$calibration_source, ""), rows = 3, width = "100%",
        placeholder = "Recorded calibration procedure, source documentation and any scaling already applied."),
      shiny::textAreaInput("map_peripheral_filters", "Filtering already applied by acquisition", brohn_default(m$acquisition_filters, ""), rows = 2, width = "100%",
        placeholder = "State none when the source is unfiltered; describe known acquisition filters."),
      if (modality == "temperature") shiny::textAreaInput("map_peripheral_conditions", "Recording conditions and settling time", brohn_default(m$recording_conditions, ""), rows = 3, width = "100%",
        placeholder = "Ambient conditions, sensor contact and settling/acclimatisation time. State unknown when the source does not document them."),
      if (modality == "movement") shiny::tagList(
        shiny::p("Select exactly three signal channels in X, Y, Z order in the shared channel selector. Describe each signed axis below; Brohn preserves that order."),
        shiny::div(class = "brohn-form-grid", lapply(seq_len(3L), function(i)
          shiny::textInput(paste0("map_peripheral_axis_", tolower(c("X", "Y", "Z")[[i]])), axis_label(i, c("X", "Y", "Z")[[i]]),
            if (length(m$axis_labels) >= i) m$axis_labels[[i]] else ""))),
        shiny::selectInput("map_peripheral_gravity", "Gravity in the source acceleration", c("Choose the recorded source policy" = "", "Source includes gravity" = "included", "Acquisition already removed gravity" = "removed"),
          selected = brohn_default(m$gravity_policy, "")),
        shiny::selectInput("map_peripheral_enmo", "Optional norm-minus-one-gravity (ENMO) description", c("Disabled" = "disabled", "Retain negative values" = "untruncated", "Set negative values to zero" = "zero_truncated"), selected = p$enmo),
        shiny::p(class = "brohn-muted", "ENMO requires gravity-included data and subtracts one standard g from vector magnitude. It is not a complete separation of gravity and movement.")),
      shiny::numericInput("map_peripheral_min_duration", "Minimum observed duration per continuous segment (seconds; blank is automatic)", brohn_default(m$parameters$minimum_duration_s, NA_real_), min = .0001, max = 86400, step = .1),
      shiny::p(class = "brohn-muted", "Automatic uses one second or one sample interval, whichever is longer. The resolved duration is saved with your mapping."),
      shiny::p(class = "brohn-muted", "This is a computation support setting. It does not establish that a recording is long enough for the research question. Gaps and invalid selected samples always break support.")),
    shiny::tags$fieldset(shiny::tags$legend("Optional threshold excursions"),
      shiny::checkboxInput("map_peripheral_threshold", "Detect protocol-defined threshold excursions", value = !is.null(threshold)),
      shiny::p(class = "brohn-muted", "Thresholds are explicit operational definitions, not a default physiological detector. Crossings never bridge missing data, clock gaps or source segments."),
      shiny::conditionalPanel(condition = "input.map_peripheral_threshold === true",
        shiny::div(class = "brohn-form-grid",
          shiny::selectInput("map_peripheral_threshold_metric", "Quantity and canonical threshold unit", c("Choose a quantity" = "",
            if (modality == "temperature") c("Temperature in degrees Celsius" = "temperature_c") else
              c("Vector magnitude in m/s2" = "vector_magnitude_ms2", "ENMO in g (enable ENMO above)" = "enmo_g")), selected = brohn_default(threshold$metric, "")),
          shiny::selectInput("map_peripheral_threshold_direction", "Excursion direction", c("Choose a direction" = "", "Above the threshold" = "above", "Below the threshold" = "below"), selected = brohn_default(threshold$direction, "")),
          shiny::textInput("map_peripheral_threshold_on", "Start boundary in the selected canonical unit", display_number(threshold$on)),
          shiny::textInput("map_peripheral_threshold_off", "Return boundary in the same unit", display_number(threshold$off)),
          shiny::textInput("map_peripheral_threshold_duration", "Minimum observed excursion duration (seconds)", display_number(threshold$minimum_duration_s))),
        shiny::textAreaInput("map_peripheral_threshold_source", "Protocol rationale for these thresholds", brohn_default(threshold$source, ""), rows = 3, width = "100%"),
        shiny::p(class = "brohn-muted", "Entry is at or above the start boundary (or at or below for a below excursion). Recovery must be strictly beyond the return boundary. Activity already present at the first sample or still present at the last sample is marked as censored; crossing times are not interpolated."))))
}
.brohn_peripheral_input_number <- function(value, label) {
  brohn_require(brohn_text(value, 200) && grepl("^[+-]?([0-9]+(\\.[0-9]*)?|\\.[0-9]+)([eE][+-]?[0-9]+)?$", trimws(value)), paste("Enter", label, "as a finite number in the selected unit."))
  number <- suppressWarnings(as.numeric(trimws(value)))
  brohn_require(brohn_number(number, -1e12, 1e12), paste(label, "is outside the supported numeric range.")); number
}
brohn_peripheral_input <- function(input, metadata, modality) {
  m <- metadata; m$unit <- input[["map_unit"]]
  m$sensor_site <- input[["map_peripheral_site"]]
  m$calibration_source <- input[["map_peripheral_calibration"]]
  m$acquisition_filters <- input[["map_peripheral_filters"]]
  if (modality == "temperature") m$recording_conditions <- input[["map_peripheral_conditions"]]
  p <- brohn_peripheral_defaults(modality)
  duration <- input[["map_peripheral_min_duration"]]
  # Shiny decodes an empty numeric input as logical NA; saved numeric values
  # may instead supply NA_real_. Both mean the visible automatic setting.
  duration_missing <- is.null(duration) || ((is.numeric(duration) || is.logical(duration)) &&
    length(duration) == 1L && is.na(duration))
  p$minimum_duration_s <- if (duration_missing) NULL else duration
  if (modality == "movement") {
    m$axis_labels <- lapply(c("x", "y", "z"), function(axis) input[[paste0("map_peripheral_axis_", axis)]])
    m$gravity_policy <- input[["map_peripheral_gravity"]]
    p$enmo <- input[["map_peripheral_enmo"]]
  }
  if (isTRUE(input[["map_peripheral_threshold"]])) p$threshold <- list(
    metric = input[["map_peripheral_threshold_metric"]], direction = input[["map_peripheral_threshold_direction"]],
    on = .brohn_peripheral_input_number(input[["map_peripheral_threshold_on"]], "the start boundary"),
    off = .brohn_peripheral_input_number(input[["map_peripheral_threshold_off"]], "the return boundary"),
    minimum_duration_s = .brohn_peripheral_input_number(input[["map_peripheral_threshold_duration"]], "the minimum excursion duration"),
    source = input[["map_peripheral_threshold_source"]])
  m$parameters <- p
  brohn_validate_peripheral_mapping(m, modality = modality)
  m$parameters <- brohn_peripheral_parameters(m, modality)
  m
}
