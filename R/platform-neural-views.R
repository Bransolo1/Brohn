# Accessible disclosure controls for the explicit EEG recipe contract.
brohn_neural_settings_ui <- function(m, columns = character(), source_format = "csv") {
  p <- brohn_default(m$parameters, list()); native <- !source_format %in% c("csv", "tsv")
  recipe <- brohn_default(p$recipe, "eeg-welch-channel/1.0")
  id <- function(name) paste0("map_neural_", name)
  num <- function(name, label, value, fallback = NA_real_, min = NA, max = NA, step = NA) shiny::numericInput(id(name), label, brohn_default(value, fallback), min, max, step)
  txt <- function(name, label, value = NULL, placeholder = NULL) shiny::textInput(id(name), label, brohn_default(value, ""), placeholder = placeholder)
  select <- function(name, label, choices, value, fallback) shiny::selectInput(id(name), label, choices, brohn_default(value, fallback))
  pair <- function(start, end, label, value, fallback) shiny::div(class = "brohn-form-grid",
    num(start, paste(label, "start (s)"), value[[1]], fallback[[1]]), num(end, paste(label, "end (s)"), value[[2]], fallback[[2]]))
  condition <- function(expr, ...) shiny::conditionalPanel(expr, ...)
  codes <- p$event_codes
  codes_text <- if (is.null(codes)) "" else if (any(grepl("=", c(names(codes), unlist(codes))))) brohn_json(codes, TRUE) else
    paste(paste(names(codes), "=", unlist(codes)), collapse = "\n")
  event_text <- if (is.null(m$events)) "" else brohn_json(m$events, TRUE)
  baseline_on <- !is.null(p$baseline_s)
  shiny::tagList(shiny::h3("What would you like to measure?"),
    select("recipe", "EEG analysis", brohn_neural_recipe_choices(), recipe, "eeg-welch-channel/1.0"),
    condition("input.map_neural_recipe === 'eeg-welch-channel/1.0'",
      shiny::p("Summarise channel spectra across usable recording segments. This route does not need event markers and keeps the acquisition reference.")),
    condition("input.map_neural_recipe !== 'eeg-welch-channel/1.0'",
      shiny::p("Event-related analysis aligns repeated observations to measured onsets. The starting values below are editable; use the settings specified for your study."),
      if (native) shiny::div(class = "brohn-form-grid",
        num("native_rate", "Sampling rate from the native header (Hz)", m$sampling_rate, min = 1, max = 100000),
        txt("participant", "Participant identity (optional)", m$participant_id), txt("session", "Session identity (with participant)", m$session_id)),
      shiny::tags$details(open = NA, shiny::tags$summary("1. Align events with the conditions"),
        select("event_mode", "Where are event onsets recorded?", if (native) c("Measured event list" = "array") else
          c("A column in this recording" = "column", "Measured event list" = "array"), if (native || !is.null(m$events)) "array" else "column", "column"),
        if (!native) condition("input.map_neural_event_mode === 'column'", shiny::selectInput(id("event_column"), "Onset code column (blank between events)",
          c("Choose a column" = "", stats::setNames(columns, columns)), brohn_default(m$event_column, ""))),
        condition("input.map_neural_event_mode === 'array'",
          shiny::textAreaInput(id("events"), "Measured event list", event_text, rows = 5, width = "100%", placeholder = "time_s,code\n2.000,A\n5.000,B"),
          shiny::p(class = "brohn-muted", "Use time_s and code columns. Times are seconds from sample zero of this recording. For multiple recording segments, add recording_id (for example recording-1). Saved structured event lists are also accepted.")),
        shiny::textAreaInput(id("event_codes"), "Match source codes to condition IDs", codes_text, rows = 3, width = "100%", placeholder = "A = condition-a\nB = condition-b"),
        shiny::textAreaInput(id("event_source"), "How were these event times measured and aligned?", brohn_default(p$event_source, ""), rows = 2, width = "100%",
          placeholder = "Marker channel or event export, clock alignment and any known timing uncertainty.")),
      shiny::tags$details(open = NA, shiny::tags$summary("2. Choose the observation and baseline windows"),
        pair("epoch_start", "epoch_end", "Epoch", p$epoch_s, list(-.2, .8)),
        shiny::p(class = "brohn-muted", "Negative times are before onset. Longer epochs are needed to keep time-frequency calculations away from wavelet edges."),
        select("voltage_baseline", "Voltage baseline", c("Keep original voltage offset" = "none", "Subtract a pre-onset mean" = "subtract"), if (baseline_on) "subtract" else "none", "none"),
        condition("input.map_neural_voltage_baseline === 'subtract'", pair("baseline_start", "baseline_end", "Voltage baseline", p$baseline_s, list(-.2, 0))),
        shiny::div(class = "brohn-form-grid", num("minimum_trials", "Minimum usable trials per condition", p$minimum_trials, 20, 1, 10000, 1),
          select("overlap", "When observation windows overlap", c("Exclude the later overlapping epoch" = "reject", "Keep overlaps specified by the protocol" = "allow"), p$overlap_policy, "reject"))),
      shiny::tags$details(shiny::tags$summary("3. Reference, filtering and artifact rules"),
        select("reference", "EEG reference", c("Retain acquisition reference" = "acquisition", "Average selected channels" = "average", "Named reference channels" = "channels"), p$reference$mode, "acquisition"),
        condition("input.map_neural_reference === 'channels'", txt("reference_channels", "Reference channel names, comma separated", paste(unlist(p$reference$channels), collapse = ", "))),
        txt("reference_source", "Acquisition reference and selected reference rationale", p$reference$source),
        select("filter", "Additional filtering", c("No additional filter" = "none", "Explicit Butterworth bandpass" = "butterworth_bandpass"), p$filter$mode, "none"),
        condition("input.map_neural_filter === 'butterworth_bandpass'", shiny::div(class = "brohn-form-grid",
          num("filter_low", "High-pass cutoff (Hz)", p$filter$low_hz, min = .01, max = 10000),
          num("filter_high", "Low-pass cutoff (Hz)", p$filter$high_hz, min = .1, max = 40000),
          num("filter_order", "Butterworth order", p$filter$order, 4, 1, 8, 1),
          num("filter_edge", "Discard at each continuous span edge (s)", p$filter$edge_exclusion_s, min = 0, max = 600)),
          shiny::p(class = "brohn-muted", "The edge exclusion must cover at least three cycles of the high-pass cutoff. Filtering never bridges missing data.")),
        pair("reject_start", "reject_end", "Artifact screening", p$rejection$window_s, list(-.2, .8)),
        shiny::checkboxInput(id("reject_peak"), "Reject trials with excessive peak-to-peak amplitude", !is.null(p$rejection$peak_to_peak_uv)),
        condition("input.map_neural_reject_peak", num("peak_uv", "Maximum peak-to-peak amplitude (microvolts)", p$rejection$peak_to_peak_uv, min = .000001, max = 1e9)),
        shiny::checkboxInput(id("reject_flat"), "Reject flat trials", !is.null(p$rejection$flat_uv)),
        condition("input.map_neural_reject_flat", num("flat_uv", "Minimum peak-to-peak amplitude (microvolts)", p$rejection$flat_uv, min = .000001, max = 1e9)),
        shiny::p(class = "brohn-muted", "A trial is excluded across selected channels when one fails the chosen rule. Source gaps and native bad annotations are always retained as unavailable support.")),
      condition("input.map_neural_recipe === 'eeg-erp-epochs/1.0'",
        shiny::tags$details(open = NA, shiny::tags$summary("4. Summarise the event-related response"),
          pair("amplitude_start", "amplitude_end", "Mean-amplitude window", p$amplitude_window_s, list(.3, .5)),
          select("polarity", "Optional peak measurement in the same window", c("Do not extract a peak" = "none", "Positive peak" = "positive", "Negative peak" = "negative", "Largest absolute peak" = "absolute"), p$peak_polarity, "none"),
          shiny::p(class = "brohn-muted", "The full average waveform is retained. Peak and window choices should come from your protocol, before comparing condition results."))),
      condition("input.map_neural_recipe === 'eeg-morlet-epochs/1.0'",
        shiny::tags$details(open = NA, shiny::tags$summary("4. Describe the time-frequency response"),
          txt("frequencies", "Frequencies (Hz), comma separated", paste(unlist(p$frequencies_hz), collapse = ", "), "8, 10, 12"),
          txt("cycles", "Wavelet cycles, one value per frequency", paste(unlist(p$n_cycles), collapse = ", "), "5, 5, 5"),
          select("power", "Power to describe", c("Total trial power" = "total", "Induced power after subtracting the average response" = "induced"), p$power, "total"),
          pair("summary_start", "summary_end", "Power summary", p$summary_window_s, list(.3, .5)),
          select("power_baseline", "Power baseline correction", c("None" = "none", "Subtract baseline power" = "subtract", "Divide by baseline power" = "ratio", "Percent change" = "percent", "Decibels (10 log10 ratio)" = "db"), p$power_baseline$mode, "none"),
          condition("input.map_neural_power_baseline !== 'none'", pair("power_baseline_start", "power_baseline_end", "Power baseline", p$power_baseline$window_s, list(-1, -.5)),
            num("power_floor", "Minimum usable baseline power (microvolts squared)", p$power_baseline$minimum_power_uv2, min = 0, max = 1e12)),
          shiny::p(class = "brohn-muted", "Power and baseline windows need complete wavelet support. Unsupported edges are excluded. Phase consistency is reported separately with retained trial counts."))),
      condition("input.map_neural_recipe === 'eeg-frequency-tagging/1.0'",
        shiny::tags$details(open = NA, shiny::tags$summary("4. Describe the tagged-frequency response"),
          pair("spectral_start", "spectral_end", "Spectral window (end excluded)", p$spectral_window_s, list(0, .8)),
          txt("tags", "Stimulus tag frequencies (Hz), comma separated", paste(unlist(p$tag_frequencies_hz), collapse = ", "), "10, 12"),
          txt("harmonics", "Harmonic numbers, comma separated", paste(unlist(p$harmonics), collapse = ", "), "1, 2"),
          select("taper", "Spectral taper", c("Hann" = "hann", "Boxcar" = "boxcar"), p$window, "hann"),
          shiny::div(class = "brohn-form-grid", num("neighbors", "Noise bins on each side", p$noise_neighbor_bins, 2, 1, 100, 1),
            num("skip_bins", "Skip bins next to each target", p$noise_skip_bins, 1, 0, 100, 1),
            num("bin_tolerance", "Largest allowed target-bin offset (Hz)", p$max_bin_offset_hz, 0, 0, 50000)),
          shiny::p(class = "brohn-muted", "The observed window determines frequency resolution. A target or noise neighborhood without suitable support remains unavailable; zero noise never produces infinite SNR."))),
      shiny::textAreaInput(id("settings_source"), "Protocol version and rationale for these settings", brohn_default(p$settings_source, ""), rows = 3, width = "100%",
        placeholder = "Record the method, analysis plan or reviewed device profile supporting the selected windows and thresholds.")))
}
