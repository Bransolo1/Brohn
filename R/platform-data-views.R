brohn_table <- function(rows, columns = NULL, labels = NULL, maximum = 100L, label = "Source data") {
  if (!length(rows)) return(shiny::p(class = "brohn-muted", "No observations in this view."))
  if (is.null(columns)) columns <- unique(unlist(lapply(rows, names), use.names = FALSE))
  if (is.null(labels)) labels <- gsub("_", " ", columns)
  display <- function(x, column) {
    if (is.null(x)) return(if (column == "missing_reason") "Not missing" else if (column %in% c("condition_id", "stimulus_id")) "Whole study" else "Unavailable")
    if (is.numeric(x) && length(x) == 1L) return(format(signif(x, 6), trim = TRUE, scientific = FALSE))
    if (is.character(x) && length(x) == 1L) return(x)
    text <- brohn_json(x)
    if (nchar(text) > 350L) shiny::tags$details(shiny::tags$summary(paste("Inspect structured value", paste0("(", length(x), " entries)"))),
      shiny::tags$pre(style = "max-height:20rem;overflow:auto", tabindex = "0", `aria-label` = paste("Complete structured value for", gsub("_", " ", column)), text)) else text
  }
  shiny::tagList(shiny::div(class = "brohn-table", tabindex = "0", role = "region", `aria-label` = paste0(label, "; scroll horizontally for more columns"),
    shiny::tags$table(shiny::tags$thead(shiny::tags$tr(lapply(labels, function(l) shiny::tags$th(scope = "col", l)))),
      shiny::tags$tbody(lapply(head(rows, maximum), function(row) shiny::tags$tr(lapply(columns, function(column) shiny::tags$td(display(row[[column]], column)))))))),
    if (length(rows) > maximum) shiny::p(class = "brohn-muted", paste("Showing", maximum, "of", length(rows), "rows. Download the report for retained observations.")))
}
brohn_respiration_input <- function(input, prefix = "map_respiration") {
  list(source_quantity = input[[paste0(prefix, "_quantity")]], polarity = input[[paste0(prefix, "_polarity")]],
    mapping_source = input[[paste0(prefix, "_source")]])
}
brohn_respiration_settings_ui <- function(parameters = NULL, prefix = "map_respiration") {
  shiny::tagList(
    shiny::p("Breathing phase estimates require belt displacement or calibrated lung volume. Airflow peaks have a different meaning and cannot use this analysis. The original recording stays available."),
    shiny::selectInput(paste0(prefix, "_quantity"), "What does the respiratory channel measure?",
      c("Choose from source documentation" = "", "Belt displacement (a.u., V or mV)" = "belt_displacement", "Calibrated lung volume (L)" = "lung_volume"), brohn_default(parameters$source_quantity, "")),
    shiny::selectInput(paste0(prefix, "_polarity"), "During inspiration, the recorded value",
      c("Confirm the direction" = "", "Increases" = "positive_inspiration", "Decreases" = "negative_inspiration"), brohn_default(parameters$polarity, "")),
    shiny::textAreaInput(paste0(prefix, "_source"), "Evidence for quantity and inspiration direction", brohn_default(parameters$mapping_source, ""), rows = 2, width = "100%",
      placeholder = "Sensor/export documentation and reviewed breathing maneuver. A waveform alone does not establish physiological direction."),
    shiny::p(class = "brohn-muted", "The saved recipe estimates phases between displacement extrema, with Khodadad cleaning/detection and at least 5 seconds excluded at each edge. Flow onsets and breath holds need a different method."))
}
brohn_dataset_base_mapping <- function(input, dataset) {
  if (identical(dataset$modality,"maxdiff")) return(brohn_maxdiff_mapping_input(input))
  # Shiny retains values for controls removed by navigation. Read only controls
  # that belong to this source format/family so old mappings cannot leak in.
  fields <- c(origin_statement = "map_origin")
  tabular <- dataset$source$format %in% c("csv", "tsv")
  gaze <- dataset$modality %in% c("gaze", "prepared_gaze")
  if (tabular) {
    fields <- c(fields, participant_column = "map_participant", session_column = "map_session", condition_column = "map_condition",
      stimulus_column = "map_stimulus", exposure_column = "map_exposure", unit = "map_unit")
    if (gaze) {
      fields <- c(fields, x_column = "map_x", y_column = "map_y", valid_column = "map_valid", phase_column = "map_phase", phase_value = "map_phase_value", time_unit = "map_time_unit")
      fields <- c(fields, if (identical(input$map_gaze_representation, "samples")) c(time_column = "map_time") else c(start_column = "map_start", end_column = "map_end"))
    } else if (dataset$modality == "questionnaire") fields <- c(fields, question_column = "map_question", assessment_column = "map_assessment", assessment_exposure_column = "map_assessment_exposure") else
      fields <- c(fields, time_column = "map_time", time_unit = "map_time_unit", sampling_rate = "map_sampling_rate", segment_column = "map_segment")
  } else if (!dataset$modality %in% c("video", "multimodal")) fields <- c(fields, unit = "map_unit", sampling_rate = "map_sampling_rate")
  m <- lapply(fields, function(id) input[[id]])
  if (dataset$modality %in% c("temperature", "movement")) m$stimulus_column <- NULL
  if (tabular && !gaze) m$value_columns <- as.list(brohn_default(input$map_values, character()))
  if (gaze && isTRUE(input$map_passive_only)) m$source_phase <- "passive_viewing_only"
  if (identical(dataset$modality, "respiration")) m$parameters <- c(list(recipe = "respiration-displacement-khodadad/1.0",
    edge_exclusion_s = brohn_default(dataset$metadata$parameters$edge_exclusion_s, 5)), brohn_respiration_input(input))
  if (identical(dataset$modality,"emg")) m$parameters <- brohn_emg_input(input)
  # Empty Shiny numeric controls produce a logical NA, not necessarily NA_real_.
  # Preserve typed zero/FALSE while omitting any missing scalar before JSON.
  Filter(function(v) !(is.null(v) || (is.character(v) && length(v) == 1L && identical(v, "")) || (is.atomic(v) && length(v) == 1L && is.na(v))), m)
}
brohn_dataset_detail_ui <- function(store, id) {
  r <- brohn_get_entity(store, "dataset", id)
  if (is.null(r)) return(brohn_empty("Dataset unavailable", "Choose a dataset from the library."))
  if (identical(r$body$modality,"maxdiff")) return(brohn_maxdiff_dataset_ui(store,r))
  if (identical(r$body$modality,"implicit")) return(brohn_task_import_dataset_ui(store,r))
  if (identical(r$body$modality, "multimodal")) return(brohn_interchange_dataset_ui(store, r))
  brohn_audio_extraction_lineage(store,r)
  d <- r$body; m <- d$metadata; columns <- unlist(d$columns, use.names = FALSE)
  selected <- function(field, candidates = character()) {
    if (!is.null(m[[field]])) return(m[[field]])
    match <- candidates[candidates %in% columns]
    if (length(match)) match[1] else ""
  }
  column <- function(id, label, field, candidates = character()) shiny::selectInput(id, label,
    c("Choose a column" = "", stats::setNames(columns, columns)), selected(field, candidates))
  gaze <- d$modality %in% c("gaze", "prepared_gaze"); questionnaire <- d$modality == "questionnaire"; video <- d$modality == "video"
  peripheral <- d$modality %in% c("temperature", "movement")
  tabular <- d$source$format %in% c("csv", "tsv")
  unit <- if (!tabular) if (d$modality == "audio") "FS" else "native" else if (gaze) "stimulus_normalized" else if (questionnaire) "numeric_rating" else
    switch(d$modality, eda = "uS", eeg = "uV", ecg = "mV", emg = "mV", "a.u.")
  brohn_page(d$title, paste(d$modality, "\u00b7", d$source$filename, "\u00b7", "revision", r$revision),
    brohn_card(title = "Your original source is retained", shiny::p(d$source_provenance$imported_at),
      shiny::p(class = "brohn-muted", paste("SHA-256", d$source$hash)), brohn_badge(d$status),
      shiny::downloadButton("dataset_original_download", "Download original source", icon = NULL),
      if (length(d$preview)) shiny::tags$details(open = NA, shiny::tags$summary("Inspect source columns"), brohn_table(d$preview, maximum = 20))),
    brohn_camera_dataset_ui(store, r),
    brohn_audio_extraction_dataset_ui(store, r),
    brohn_curated_stream_dataset_ui(store, r),
    if (!tabular && !video) brohn_native_header_ui(store, r),
    brohn_card(title = "Confirm what the columns mean", subtitle = "Suggested matches are a starting point. Confirm identities, units and recording provenance before processing.",
      shiny::div(style = "display:none", shiny::textInput("dataset_form_identity", NULL, paste(r$id, r$revision, sep = ":"))),
      shiny::selectizeInput("map_study", "Link to a study design", choices = NULL, options = list(placeholder = "Search studies in this project", maxOptions = 100)),
      shiny::uiOutput("mapping_study_revision"),
      if (video) shiny::tagList(
        shiny::selectInput("map_video_profile", "Video observations", stats::setNames(vapply(brohn_vision_profiles(), `[[`, character(1), "id"), vapply(brohn_vision_profiles(), `[[`, character(1), "label")), brohn_default(m$profile, "face_geometry_v1")),
        shiny::conditionalPanel("input.map_video_profile === 'custom_v1'", shiny::checkboxGroupInput("map_video_channels", "Geometry channels", c("Face" = "face", "Body pose" = "pose", "Hands" = "hands"), selected = unlist(brohn_default(m$channels, list("face"))))),
        shiny::conditionalPanel("input.map_video_profile === 'facial_au_expression_pyfeat_v1'", brohn_facial_mapping_ui(m)),
        shiny::conditionalPanel("input.map_video_profile !== 'facial_au_expression_pyfeat_v1'",
        shiny::p("Face geometry and blendshape scores describe model outputs. They are not calibrated gaze, emotional states or attention scores."),
        shiny::tags$details(shiny::tags$summary("Time interval and support"),
          shiny::div(class = "brohn-form-grid",
            shiny::numericInput("map_video_start", "Start after first video timestamp (seconds; optional)", brohn_default(m$start_s, NA_real_), min = 0, max = 600),
            shiny::numericInput("map_video_end", "End after first video timestamp (seconds; optional)", brohn_default(m$end_s, NA_real_), min = 0, max = 600),
            shiny::numericInput("map_video_gap", "Largest supported frame interval (seconds)", brohn_default(m$max_support_gap_s, .25), min = .001, max = 10)),
          shiny::p("Frame timing comes from the video presentation timestamps. Larger gaps remain unsupported time in the report.")))),
      if (gaze) shiny::selectInput("map_gaze_representation", "What does each gaze row describe?", c("An interval already prepared by an exporter" = "intervals", "A timestamped gaze sample" = "samples"), brohn_default(m$gaze_representation, "intervals")),
      if (!tabular && d$modality %in% c("eeg", "fnirs")) shiny::textInput("map_native_values", "Native channel names (comma separated or exact JSON array)", brohn_native_channel_input_text(unlist(m$value_columns))),
      if (!tabular && d$modality == "audio") shiny::numericInput("map_audio_channel", "Audio channel (0 is first)", brohn_default(m$channel_index, 0), min = 0, max = 64, step = 1),
      if (!tabular && d$modality == "fnirs") shiny::div(class = "brohn-form-grid",
        shiny::numericInput("map_ppf_1", "Partial pathlength factor for first wavelength", brohn_default(m$parameters$ppf[[1]], NA_real_), min = .1, max = 100),
        shiny::numericInput("map_ppf_2", "Partial pathlength factor for second wavelength", brohn_default(m$parameters$ppf[[2]], NA_real_), min = .1, max = 100)),
      if (tabular) shiny::div(class = "brohn-form-grid",
        column("map_participant", "Participant identity", "participant_column", c("participant_id", "participant")),
        column("map_session", "Session identity", "session_column", c("session_id", "session")),
        column("map_condition", if (peripheral) "Condition ID (optional; explicit source labels)" else "Condition ID (optional if derived from stimulus)", "condition_column", c("condition_id", "condition")),
        if (!peripheral) column("map_stimulus", "Stimulus ID", "stimulus_column", c("stimulus_id", "stimulus")),
        column("map_exposure", "Exposure ID (for repeated presentations)", "exposure_column", c("exposure_id", "trial_id")),
        if (!gaze && d$modality != "questionnaire") column("map_segment", "Recording segment (keeps resets and interruptions separate)", "segment_column", c("brohn_segment_id")),
        if (gaze) shiny::tagList(shiny::conditionalPanel("input.map_gaze_representation !== 'samples'", column("map_start", "Interval start", "start_column", c("start_ms", "start_s", "start")),
          column("map_end", "Interval end", "end_column", c("end_ms", "end_s", "end"))),
          shiny::conditionalPanel("input.map_gaze_representation === 'samples'", column("map_time", "Sample time", "time_column", c("time", "time_s", "time_ms", "timestamp"))),
          column("map_x", "Gaze x coordinate", "x_column", c("x", "gaze_x")),
          column("map_y", "Gaze y coordinate", "y_column", c("y", "gaze_y")),
          column("map_valid", "Gaze valid (true/false or 1/0)", "valid_column", c("valid", "validity")),
          column("map_phase", "Phase column (when multiple phases are present)", "phase_column", c("phase")),
          shiny::textInput("map_phase_value", "Passive-viewing value in the phase column", brohn_default(m$phase_value, "passive_viewing")),
          shiny::checkboxInput("map_passive_only", "I confirm this source contains passive-viewing observations only", identical(m$source_phase, "passive_viewing_only"))) else if (questionnaire)
          shiny::tagList(column("map_question", "Question ID", "question_column", c("question_id", "question")),
            column("map_assessment", "Assessment ID (shared by items answered together)", "assessment_column", c("assessment_id")),
            column("map_assessment_exposure", "Shared stimulus occurrence ID for this assessment (optional)", "assessment_exposure_column", c("assessment_exposure_id")),
            shiny::p(class = "brohn-muted", "Scale scoring needs an explicit assessment ID for each questionnaire occasion. Item exposure IDs and row order do not establish which answers belong together. Leave unmapped to retain item summaries without inventing scale assessments.")) else
            column("map_time", "Sample time", "time_column", c("time", "time_s", "time_ms", "timestamp")),
        if (!gaze) shiny::selectInput("map_values", if (questionnaire) "Response value column" else "Signal channels", columns,
          selected = unlist(brohn_default(m$value_columns, list())), multiple = !questionnaire),
        if (!questionnaire) shiny::selectInput("map_time_unit", "Source time unit", c("Choose time unit" = "", "Seconds" = "s", "Milliseconds" = "ms",
          if (peripheral) c("Microseconds" = "us", "Nanoseconds" = "ns", "Sample index at the declared rate" = "sample")), brohn_default(m$time_unit, "")),
        if (!gaze && !questionnaire) shiny::numericInput("map_sampling_rate", "Sampling rate (Hz)", brohn_default(m$sampling_rate, NA_real_), min = if (peripheral) .1 else 1, max = 100000)),
      if (gaze) shiny::selectInput("map_unit", "Coordinate frame", c("Confirm coordinate frame" = "", "Stimulus-normalized coordinates (0 to 1)" = "stimulus_normalized"), brohn_default(m$unit, "")) else
        if (questionnaire) shiny::selectInput("map_unit", "Response values", c("Numeric rating codes" = "numeric_rating", "Text" = "text", "Typed JSON" = "json"), brohn_default(m$unit, unit)) else
          if (!video && !peripheral) shiny::textInput("map_unit", if (tabular) "Calibrated signal unit" else "Native unit policy", brohn_default(m$unit, unit)),
      if (gaze) brohn_raw_gaze_settings_ui(m, columns),
      if (d$modality == "eeg") brohn_neural_settings_ui(m, columns, d$source$format),
      if (d$modality == "eda") brohn_eda_events_settings_ui(m, columns, d$source$format),
      if (d$modality == "respiration") brohn_respiration_settings_ui(m$parameters),
      if (d$modality == "emg") brohn_emg_settings_ui(m$parameters),
      if (peripheral) brohn_peripheral_settings_ui(m, columns, d$modality),
      shiny::textAreaInput("map_origin", "Recording provenance and collection notes", brohn_default(m$origin_statement, ""), width = "100%", rows = 3,
        placeholder = "Device/export, collection setting, identity scheme, preprocessing already applied and known gaps."),
      shiny::actionButton("accept_dataset", "Confirm mapping and analyse", class = "btn-primary"),
      if (d$status %in% c("accepted", "analysed")) shiny::actionButton("analyse_dataset", "Run a new analysis")),
    shiny::uiOutput("dataset_reports"))
}
brohn_dataset_reports_ui <- function(store, id, state = NULL) {
  reports_page <- brohn_search_related(store,"dataset_reports",id,offset=brohn_related_offset(state,"dataset_reports",id))
  jobs_page <- brohn_search_related(store,"dataset_jobs",id,offset=brohn_related_offset(state,"dataset_jobs",id))
  reports <- reports_page$records; jobs <- jobs_page$records
  brohn_card(title = "Analysis progress and saved reports",
    if (!length(jobs)) shiny::p("Confirm the mapping to start processing.") else lapply(jobs, function(job) shiny::div(class = "brohn-toolbar",
      brohn_badge(job$status, if (job$status == "failed") "error" else if (job$status == "succeeded") "success" else "neutral"),
      shiny::span(job$updated_at), if (!is.null(job$error)) shiny::p(job$error$message),
      if (job$status %in% c("queued", "running")) brohn_command("Cancel processing", "cancel_processing", job$id),
      if (job$status %in% c("failed", "cancelled")) brohn_command("Retry saved inputs", "retry_processing", job$id))),
    brohn_related_page_ui(jobs_page),
    lapply(reports, function(report) shiny::div(class = "brohn-toolbar", shiny::span(report$created_at),
      brohn_command("Open report", "open_report", report$id, "btn btn-primary"))),brohn_related_page_ui(reports_page))
}
.brohn_contrast_label <- function(contrast, design = NULL) {
  present <- function(value) is.character(value) && length(value) == 1L && !is.na(value) && nzchar(trimws(value))
  if (present(contrast$outcome_label)) return(contrast$outcome_label)
  if (present(contrast$outcome_id)) {
    questionnaire <- is.null(contrast$modality) || identical(contrast$modality, "questionnaire")
    question_metric <- isTRUE(contrast$metric %in% c("explicit_rating", "explicit_numeric_response", "explicit_response"))
    scale_metric <- identical(contrast$metric, "assessment_scale_score") || identical(contrast$measure, "questionnaire_scale")
    question <- if (questionnaire && question_metric && !scale_metric) Filter(function(q) identical(q$id, contrast$outcome_id), design$questions) else list()
    if (length(question) == 1L && present(question[[1]]$prompt)) return(question[[1]]$prompt)
    scale <- if (questionnaire && scale_metric) Filter(function(s) identical(s$id, contrast$outcome_id), design$scales) else list()
    if (length(scale) == 1L && present(scale[[1]]$label)) return(scale[[1]]$label)
  }
  labels <- c(temperature_mean = "Mean temperature", temperature_sd = "Temperature variability (standard deviation)",
    temperature_time_weighted_mean = "Time-weighted mean temperature", temperature_endpoint_change = "Temperature change within recorded intervals",
    temperature_linear_slope = "Linear temperature trend within recorded intervals", acceleration_magnitude_mean = "Mean acceleration magnitude",
    acceleration_magnitude_rms = "Acceleration magnitude (root mean square)", acceleration_vector_derivative_rms = "Rate of vector change (root mean square)",
    enmo_mean = "Mean norm-minus-one-gravity (ENMO)", explicit_rating = "Explicit rating")
  if (present(contrast$metric) && contrast$metric %in% names(labels)) return(unname(labels[[contrast$metric]]))
  if (present(contrast$outcome_id)) return(paste("Recorded measure:", contrast$outcome_id))
  if (present(contrast$metric)) return(paste("Recorded measure:", contrast$metric))
  "Recorded measure"
}
.brohn_contrast_unit <- function(unit) {
  labels <- c(degC = "\u00b0C", degF = "\u00b0F", `m/s2` = "m/s\u00b2", `m/s3` = "m/s\u00b3", `degC/min` = "\u00b0C/min")
  if (is.character(unit) && length(unit) == 1L && !is.na(unit) && unit %in% names(labels)) unname(labels[[unit]]) else brohn_default(unit, "")
}
.brohn_contrast_support_ui <- function(reason) {
  if (is.null(reason)) return(NULL)
  known <- list(
    duplicate_or_ambiguous_observation_identity = c("Multiple records share the same participant, session, condition and exposure identity. These records have not been combined.",
      "Review the source intervals and exposure identities before preparing a new comparison. Fragments of one presentation must retain that presentation's identity."),
    no_eligible_linked_observations = c("No eligible observations with reviewed participant and session links support this comparison.",
      "Review the selected reports, their usable data and the participant links."),
    source_measure_definitions_disagree = c("The selected source reports use different definitions or processing settings for this measure.",
      "Review the source settings and select reports that measure the same defined outcome."),
    no_within_session_condition_pairs = c("No session supplies eligible observations for both compared conditions.",
      "Review condition labels and missing data in the source sessions."),
    no_supported_observations = c("The saved sources do not contain supported observations for this outcome.",
      "Review the source data and the outcome selected in the analysis plan."),
    participant_identity_not_established = c("Participant identities have not been established, so a comparison between people is unavailable.",
      "Review the source participant codes and their identity evidence before preparing a new analysis."),
    at_least_two_people_needed_for_inference = c("The descriptive difference is available, but an uncertainty interval needs at least two eligible people.",
      "Interpret this as a description of the recorded people."),
    zero_or_negligible_between_person_variance = c("The descriptive differences have zero or negligible variation between people, so an uncertainty interval was not estimated.",
      "Review the recorded differences and measurement resolution; the displayed difference remains descriptive."))
  if (is.character(reason) && length(reason) == 1L && !is.na(reason) && reason %in% names(known)) {
    text <- known[[reason]]
    return(shiny::tagList(shiny::p(text[[1]]), shiny::p(class = "brohn-muted", text[[2]])))
  }
  shiny::p(paste("Recorded support reason:", reason))
}
.brohn_multimodal_coverage_ui <- function(a) {
  q <- a$quality
  count <- function(value) is.numeric(value) && length(value) == 1L && !is.na(value) && is.finite(value) && value >= 0
  shiny::tagList(
    if (count(q$available_report_count) && count(q$selected_report_count)) shiny::p(paste(q$available_report_count, "of", q$selected_report_count, "selected source reports are available.")),
    if (count(q$estimable_comparison_count) && count(q$declared_comparison_count)) shiny::p(paste(q$estimable_comparison_count, "of", q$declared_comparison_count,
      "declared comparisons have an uncertainty interval and p-value. Each card shows its eligible people and paired sessions; descriptive-only or unavailable results are explained there.")),
    if (identical(q$cross_modal_complete_case_filter, FALSE)) shiny::p("Each measure keeps its own eligible people and sessions. Missing data in one measure does not remove otherwise eligible data from another."),
    if (count(q$unlinked_observation_count) && q$unlinked_observation_count > 0) shiny::p(paste(q$unlinked_observation_count,
      "source observations have no reviewed participant/session link and cannot enter a comparison. Review the identity mapping if those observations should be linked.")),
    shiny::p(class = "brohn-muted", "Source rows, features and recording intervals are not counts of independent people."),
    shiny::tags$details(shiny::tags$summary("Inspect complete coverage counts"), brohn_table(list(q), label = "Complete combined-report coverage and eligibility")))
}
brohn_contrast_ui <- function(c, design = NULL) {
  available <- !is.null(c$estimate)
  unit <- .brohn_contrast_unit(c$unit)
  brohn_card(title = paste(c$test_label, "compared with", c$control_label), subtitle = .brohn_contrast_label(c, design),
    shiny::p(class = "brohn-result-number", if (available) paste0(if (c$estimate > 0) "+" else "", format(signif(c$estimate, 4), trim = TRUE), " ", unit) else "Comparison unavailable"),
    if (!available && nzchar(unit)) shiny::p(class = "brohn-muted", paste("Measure unit:", unit)),
    shiny::p(paste(c$participant_count, "eligible people", "\u00b7", c$paired_session_count, "paired sessions")),
    if (!is.null(c$interval95)) shiny::p(paste("95% interval:", format(signif(c$interval95$lower, 4), trim = TRUE), "to", format(signif(c$interval95$upper, 4), trim = TRUE), unit)),
    .brohn_contrast_support_ui(c$reason),
    if (!is.null(c$p_adjusted)) shiny::p(paste(if (identical(c$multiplicity$method, "bonferroni_incomplete_family")) "Conservative Bonferroni p-value:" else "Holm-adjusted p-value:", format(signif(c$p_adjusted, 4), trim = TRUE), "across", c$multiplicity$family_size, "declared comparisons.")),
    if (!is.null(c$multiplicity)) shiny::p("Intervals are unadjusted. Missing comparisons remain part of the declared testing family."),
    shiny::tags$details(shiny::tags$summary("How this comparison was calculated"), shiny::p(c$aggregation),
      shiny::p(paste("Source measure identity:", c$outcome_id, "\u00b7", "Metric:", c$metric, "\u00b7", "Stored unit:", c$unit)),
      if (!is.null(c$reason)) shiny::p(paste("Stored support reason:", c$reason)),
      if (!is.null(c$scale_source)) shiny::p(paste(c$scale_source$scored_assessment_count, "eligible scale assessments from",
        c$scale_source$comparison_assessment_count, "assessments in these conditions;", c$scale_source$unavailable_assessment_count,
        "could not be scored. Complete item keys, assessment scores and source evidence remain in this report.")),
      shiny::p(paste(c$excluded_session_count, "sessions did not supply an eligible pair for this outcome.")),
      shiny::p("The interval uses variation between people. Its interpretation depends on sampling, design and distribution assumptions; it is not a causal or population guarantee.")))
}
.brohn_task_metric_support_ui <- function(metric) {
  support <- metric$support
  if (identical(metric$name, "SCIAT_target_positive_D")) return(shiny::p(paste(
    support$retained_responses, "of", support$test_trials, "test responses enter this comparison;",
    support$pooled_correct_responses, "correct responses support its variability estimate.")))
  shiny::tagList(
    if (!is.null(metric$reason)) shiny::p(class = "brohn-muted", metric$reason),
    if (!is.null(support)) shiny::tagList(
      if (identical(metric$unit, "proportion")) shiny::p(paste(
        support$numerator, "of", support$denominator,
        switch(metric$name, test_omission_rate = "scored test trials had no response.",
          test_first_response_error_rate = "answered test trials had a wrong first answer.",
          "eligible observations."))) else shiny::p(paste(
            support$eligible_count, "retained correct test responses;", support$minimum_count, "needed for this measure.")),
      shiny::tags$details(shiny::tags$summary("Inspect this measure's support"), shiny::tags$pre(brohn_json(support, TRUE)))))
}
brohn_report_content <- function(report) {
  a <- report$analysis
  shiny::tagList(shiny::div(class = "brohn-toolbar", brohn_badge(report$origin, if (report$origin == "live") "neutral" else "warning"),
    brohn_badge(report$status)),
    brohn_scale_results_ui(a$scales),
    brohn_facial_report_ui(a),
    if(length(a$choice_tasks)) lapply(seq_along(a$choice_tasks),function(i)brohn_maxdiff_result_ui(a$choice_tasks[[i]],exercise_number=i)),
    brohn_task_import_evidence_ui(a),
    brohn_questionnaire_artifact_preview_ui(a),
    brohn_question_revision_report_ui(a),
    brohn_task_cohort_report_ui(a),
    if (length(a$task_scores)) lapply(a$task_scores, function(task) brohn_card(title = task$title, subtitle = task$profile,
      brohn_badge(if (identical(task$status, "partial")) "Some measures unavailable" else task$status,
        if (isTRUE(task$eligible) && !identical(task$status, "partial")) "success" else "warning"),
      shiny::p(paste("Materials:", task$origin, "\u00b7", "Session:", task$session_id)),
      if (!is.null(task$reason)) shiny::p(task$reason),
      shiny::p(paste(task$counts$received, "recorded trials of", task$counts$expected, "expected")),
      if (!is.null(task$counts$retained_correct)) shiny::p(paste(task$counts$retained_correct, "correct test trials retained for the response-time summary.")),
      lapply(task$metrics, function(metric) shiny::div(shiny::h3(switch(metric$name,
        SCIAT_target_positive_D = "Single-category association score", correct_test_rt_mean = "Mean test response time", correct_test_rt_median = "Median test response time", correct_test_rt_sd = "Response-time variability (standard deviation)",
        test_first_response_error_rate = "Wrong first answers among answered test trials", test_omission_rate = "Missed test responses",
        keyboard_aat_relative_approach_advantage = "Relative keyboard approach advantage", IAT_D1 = "IAT D1 score", BIAT_D = "Brief IAT D score", gsub("_", " ", metric$name))),
        shiny::p(class = "brohn-result-number", if (is.null(metric$value)) "Unavailable" else if (metric$unit == "proportion") paste0(format(signif(metric$value*100, 4), trim = TRUE), "%") else paste(format(signif(metric$value, 5), trim = TRUE), metric$unit)),
        if (!is.null(metric$direction)) shiny::p(if (identical(metric$name, "SCIAT_target_positive_D"))
          "Positive scores mean faster responses when the target shares a key with positive attributes." else metric$direction), .brohn_task_metric_support_ui(metric))),
      shiny::tags$details(shiny::tags$summary("Scoring counts and interpretation"), shiny::tags$pre(brohn_json(task$counts, TRUE)),
        if (identical(task$scoring_recipe, "brohn-sciat-response-window-score/1.0")) brohn_sciat_window_score_ui(task) else
          if (!is.null(task$scoring_audit)) shiny::tagList(shiny::h3("Pair scores and exclusions"), shiny::tags$pre(brohn_json(task$scoring_audit, TRUE))),
        if (!is.null(task$cells)) shiny::tagList(shiny::h3("Target and response support"), shiny::tags$pre(brohn_json(task$cells, TRUE))),
        if (!is.null(task$scoring_recipe)) shiny::p(paste("Scoring recipe:", task$scoring_recipe)),
        if (!is.null(task$support_policy)) shiny::tags$pre(brohn_json(task$support_policy, TRUE)),
        shiny::tags$ul(lapply(task$limitations, shiny::tags$li))))),
    if (length(a$contrasts)) shiny::div(class = "brohn-grid", lapply(a$contrasts, function(contrast) brohn_contrast_ui(contrast, report$provenance$design))),
    if (!is.null(a$parameters$analysis_plan)) brohn_card(title = "The saved analysis plan",
      shiny::p(a$parameters$analysis_plan$plan$rationale),
      shiny::p(paste(a$parameters$analysis_plan$declared_family_size, "comparisons declared;", a$parameters$analysis_plan$hypotheses_in_report, "belong to this report.")),
      shiny::p(if (a$parameters$analysis_plan$timing_evidence == "plan_frozen_before_these_participant_sessions") "This plan was frozen before these participant sessions. It is not external preregistration." else "The plan is saved with the design. Its timing relative to source collection is not established.")),
    if (identical(a$operation, "eda_events")) brohn_eda_events_support_ui(a),
    if (identical(a$operation, "peripheral")) brohn_peripheral_report_ui(a),
    if (!brohn_facial_supported(a)) brohn_card(title = if (identical(a$kind,"implicit")) "Trial source coverage" else if (length(a$task_scores)) "Questionnaire coverage" else "What this result covers",
      if (identical(a$kind,"implicit")) shiny::p("These counts describe the retained trial source. Each task result has its own completeness and scoring eligibility.") else
        if (length(a$task_scores)) shiny::p("These counts describe explicit questionnaire answers. The task cards above retain their own trial counts and scoring eligibility."),
      if (identical(a$kind, "multimodal")) .brohn_multimodal_coverage_ui(a) else
        if (brohn_measurement_coverage_supported(a)) brohn_measurement_coverage_ui(a) else
        brohn_table(list(a$quality), label = if (identical(a$kind,"implicit")) "Trial source coverage and eligibility" else if (length(a$task_scores)) "Questionnaire coverage and eligibility" else "Coverage and eligibility")),
    if (length(a$features) && a$kind == "questionnaire") lapply(a$features, function(q) brohn_card(title = q$prompt,
      subtitle = paste(brohn_default(q$condition_label, q$condition_id), "\u00b7", brohn_default(q$scale_description, "Explicit responses")),
      shiny::p(paste(q$answered_count, "answered;", q$missing_count, "missing")),
      if (!is.null(q$numeric_response_mean)) shiny::p(paste("Mean response:", format(signif(q$numeric_response_mean, 4), trim = TRUE))),
      shiny::tags$ul(lapply(q$counts, function(option) shiny::tags$li(paste(brohn_default(option$label, brohn_json(option$value)), "\u2014", option$count, "responses")))))),
    if (length(a$features) && a$kind != "questionnaire" && !brohn_facial_supported(a)) shiny::tags$details(shiny::tags$summary(paste("Inspect recording features", paste0("(", length(a$features), " rows)"))),
      brohn_table(a$features, maximum = 100, label = "Recording features")),
    if (length(a$observations)) shiny::tags$details(shiny::tags$summary(paste("Inspect retained observations", paste0("(", length(a$observations), " rows)"))),
      brohn_table(a$observations, maximum = 50, label = "Retained observations")),
    if (length(a$recordings)) shiny::tags$details(shiny::tags$summary(paste("Inspect recording support", paste0("(", length(a$recordings), " recordings)"))),
      brohn_table(a$recordings, maximum = 100, label = "Signal support")),
    brohn_card(title = "Interpretation and limitations", if (brohn_questionnaire_is_artifact(a))
      shiny::p("This display is a preview. Review the complete JSON analysis for all method settings, exclusions and interpretation limits before interpreting these results.") else shiny::tags$ul(lapply(a$limitations, shiny::tags$li))),
    shiny::tags$details(shiny::tags$summary("Method, settings and provenance"),
      shiny::h2("Effective settings"), shiny::tags$pre(brohn_json(a$parameters, TRUE)),
      shiny::h2("Source versions"), shiny::tags$pre(brohn_json(report$provenance, TRUE)),
      shiny::h2("Processing record"), shiny::tags$pre(brohn_json(report$processing, TRUE))))
}
brohn_report_detail_ui <- function(store, id) {
  r <- brohn_get_entity(store, "report", id)
  if (is.null(r)) return(brohn_empty("Report unavailable", "Choose a saved report from a study or dataset."))
  brohn_signal_audio_lineage(store,r,verify=FALSE)
  camera_authority<-brohn_camera_analysis_report_source(store,r,verify=FALSE)
  complete_counts <- r$body$analysis$questionnaire_artifact$counts
  htmltools::tagAppendAttributes(brohn_page(r$body$title, paste("Saved", r$created_at, "\u00b7", "Immutable analysis"),
    actions = shiny::tagList(shiny::downloadButton("report_html", "Download report", icon = NULL),
      shiny::downloadButton("report_csv", if (identical(r$body$analysis$schema, "brohn-task-cohort/1.0")) "Download cohort outcomes" else if (brohn_facial_supported(r$body$analysis)) "Download summary CSV" else "Download observations", icon = NULL), shiny::downloadButton("report_download", "JSON + provenance", icon = NULL),
      if (!is.null(r$body$analysis$scales) || isTRUE(complete_counts$scale_observations > 0L)) shiny::downloadButton("report_scale_csv", "Download scale scores CSV", icon = NULL),
      if (length(r$body$analysis$task_scores) || isTRUE(complete_counts$task_scores > 0L)) shiny::downloadButton("report_task_csv", "Download task scores CSV", icon = NULL),
      if(length(r$body$analysis$choice_tasks) || isTRUE(complete_counts$choice_tasks > 0L)) shiny::downloadButton("report_maxdiff_csv","Download best-worst choices CSV",icon=NULL)),
    if (identical(r$body$analysis$schema, "brohn-task-cohort/1.0")) brohn_card(title = "Cohort evidence",
      shiny::tags$details(shiny::tags$summary("Download cohort evidence"),
        shiny::div(class = "brohn-toolbar", shiny::downloadButton("report_task_cohort_people_csv", "Person outcomes CSV", icon = NULL),
          shiny::downloadButton("report_task_cohort_sessions_csv", "Session outcomes CSV", icon = NULL),
          shiny::downloadButton("report_task_cohort_attempts_csv", "Administration measures CSV", icon = NULL),
          shiny::downloadButton("report_task_cohort_membership_csv", "Selected membership CSV", icon = NULL)))),
    if (length(r$body$analysis$artifacts)) brohn_card(title = "Complete processing artifacts", subtitle = "Download the full retained output, including observations beyond the on-screen preview.",
      shiny::selectInput("report_artifact_kind", "Saved artifact", stats::setNames(vapply(r$body$analysis$artifacts, `[[`, character(1), "kind"), gsub("-", " ", vapply(r$body$analysis$artifacts, `[[`, character(1), "kind")))),
      shiny::downloadButton("report_artifact", "Download complete artifact", icon = NULL)),
    if(!is.null(camera_authority))brohn_camera_authority_ui(camera_authority),
    if(exists("brohn_runner_report_entry_ui",mode="function"))brohn_runner_report_entry_ui(r),
    brohn_questionnaire_explorer_ui(r), brohn_explicit_distribution_entry_ui(r$body), brohn_paired_plot_explorer_ui(r), brohn_task_plot_explorer_ui(r), brohn_gaze_explorer_ui(r$body), brohn_gaze_trace_report_ui(r$body), brohn_vision_explorer_ui(r), brohn_facial_review_entry_ui(r), brohn_audio_review_entry_ui(r), brohn_eda_review_entry_ui(r$body), brohn_respiration_review_panel(r$body), brohn_emg_review_panel(r$body), brohn_eda_continuous_review_panel(r$body), brohn_signal_explorer_ui(r), brohn_neural_explorer_ui(r$body), brohn_report_content(r$body)), class = "brohn-report-page")
}
brohn_export_report_html <- function(report, path, store = NULL) {
  # All user text is escaped by htmltools. No external content or executable
  # research expression is inserted in the exported report.
  page <- shiny::tagList(shiny::tags$head(shiny::tags$meta(charset = "UTF-8"),
    shiny::tags$title(paste("Brohn", report$title)), shiny::tags$meta(name = "viewport", content = "width=device-width, initial-scale=1"),
    shiny::tags$style(htmltools::HTML("body{font-family:system-ui,sans-serif;background:#11171c;color:#edf2f2;max-width:1080px;margin:auto;padding:32px;line-height:1.6;overflow-wrap:anywhere}main,header,footer,.brohn-card,.brohn-grid>*{min-width:0;max-width:100%}h1,h2{line-height:1.25}h2{font-size:1.2rem}.brohn-card{background:#192229;border:1px solid #415057;border-radius:16px;padding:24px;margin:24px 0}.brohn-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(280px,1fr));gap:16px}.brohn-badge{display:inline-block;border:1px solid #65767e;border-radius:20px;padding:4px 12px;margin-right:8px}.brohn-muted{color:#b7c4c9}.brohn-table{overflow:auto;max-width:100%}table{border-collapse:collapse;min-width:100%}td,th{padding:10px;text-align:left;border-bottom:1px solid #415057;vertical-align:top;overflow-wrap:normal;word-break:normal}pre{white-space:pre-wrap;overflow-wrap:anywhere}img,svg{max-width:100%}.brohn-signal-compact{display:none}@media(max-width:560px){.brohn-signal-wide{display:none}.brohn-signal-compact{display:block}}summary{cursor:pointer}.brohn-result-number{color:#97d8c4;font-size:1.8rem}*{box-sizing:border-box}:focus-visible{outline:3px solid #97d8c4;outline-offset:3px}@media(max-width:600px){body{padding:16px}h1{font-size:1.8rem}.brohn-card{padding:16px}.brohn-grid{grid-template-columns:minmax(0,1fr)}}"))),
    shiny::tags$body(shiny::tags$header(shiny::h1(report$title), shiny::p("Brohn research report"), shiny::p(report$created_at)),
      shiny::tags$main(if (!is.null(store)) brohn_gaze_report_ui(store, report), brohn_neural_report_plots(report), brohn_report_content(report)), shiny::tags$footer(shiny::p(paste("Report identity:", report$id)))))
  # htmltools hoists head tags out of the body. Serialize both parts explicitly:
  # as.character(tag) discards the hoisted metadata and page styles.
  rendered <- htmltools::renderTags(page)
  writeLines(enc2utf8(paste0('<!doctype html>\n<html lang="en">\n<head>\n', rendered$head,
    '\n</head>\n', rendered$html, '\n</html>')), path, useBytes = TRUE)
  invisible(path)
}
brohn_task_score_export_rows <- function(report) {
  unlist(lapply(report$analysis$task_scores, function(task) {
    metrics <- task$metrics
    if (!length(metrics)) metrics <- list(list(name = NULL, value = NULL, unit = NULL))
    lapply(metrics, function(metric) {
      explicit <- "eligible" %in% names(metric)
      list(export_schema = "brohn-task-score-csv/1.0", report_id = report$id, participant_id = task$participant_id, participant_linkage = task$participant_linkage,
        session_id = task$session_id, attempt_id = task$attempt_id, evidence_level = task$evidence_level,
        task_id = task$task_id, title = task$title, profile = task$profile,
        collection_origin = report$origin, material_origin = task$origin, task_definition_hash = task$design_hash,
        score_schema = task$schema_version, scoring_recipe = task$scoring_recipe,
        task_status = task$status, task_eligible = task$eligible, task_reason = task$reason,
        metric = metric$name, value = metric$value, unit = metric$unit, direction = metric$direction,
        metric_eligible = if (explicit) metric$eligible else isTRUE(task$eligible) && brohn_number(metric$value),
        metric_eligibility_evidence = if (explicit) "saved_metric_eligibility" else "legacy_task_eligibility_and_saved_value",
        metric_reason = if (explicit) metric$reason else task$reason,
        metric_support = metric$support, task_counts = task$counts, scoring_audit = task$scoring_audit,
        cell_support = task$cells, support_policy = task$support_policy)
    })
  }), recursive = FALSE)
}
brohn_export_task_scores_csv <- function(report, path) {
  brohn_require(length(report$analysis$task_scores) > 0L, "Choose a saved report containing task scores.")
  brohn_export_report_csv(list(analysis = list(observations = brohn_task_score_export_rows(report))), path)
}
brohn_export_report_csv <- function(report, path) {
  rows <- report$analysis$observations
  questionnaire_rows <- identical(report$analysis$kind, "questionnaire") && length(rows) > 0L
  if (questionnaire_rows) {
    # Display cells remain spreadsheet-safe. This separate canonical row is the
    # reusable scientific record: zero/false/text/null/empty values and original
    # formula-like text retain their exact native types and source identities.
    brohn_require(all(vapply(rows, function(row) is.list(row) && !is.null(names(row)) &&
      !"response_record_json" %in% names(row), logical(1))),
      "Questionnaire observation rows require named fields without the reserved response_record_json export column.")
    rows <- lapply(rows, function(row) c(row, list(response_record_json = brohn_json(row))))
  }
  if (!length(rows)) rows <- report$analysis$features
  if (!length(rows) && length(report$analysis$choice_tasks)) rows <- brohn_maxdiff_export_rows(report$analysis$choice_tasks)
  if (!length(rows) && length(report$analysis$task_scores)) rows <- brohn_task_score_export_rows(report)
  columns <- unique(unlist(lapply(rows, names), use.names = FALSE))
  encode <- function(x) if (is.null(x)) "" else if (is.numeric(x) && length(x) == 1L) brohn_json(x) else if (is.character(x) && length(x) == 1) x else brohn_json(x)
  table <- as.data.frame(setNames(lapply(columns, function(column) vapply(rows, function(r) encode(r[[column]]), character(1))), columns), stringsAsFactors = FALSE)
  # Machine CSV preserves exact typed/source values. Text cells use an explicit
  # spreadsheet-safe prefix where formula interpretation could occur.
  for (column in names(table)) table[[column]] <- ifelse(grepl("^[=+@\\t\\r]", table[[column]], perl = TRUE) | grepl("^-[^0-9.]", table[[column]]), paste0("'", table[[column]]), table[[column]])
  # Explicit UTF-8 bytes preserve every measurement's researcher labels under
  # Windows C locale. All fields are encoded strings; retain quoted CSV syntax.
  con <- file(path, "wb"); on.exit(close(con), add = TRUE)
  write_row <- function(cells) {
    quoted <- paste0('"', gsub('"', '""', enc2utf8(cells), fixed = TRUE), '"')
    writeBin(charToRaw(enc2utf8(paste0(paste(quoted, collapse = ","), if (.Platform$OS.type == "windows") "\r\n" else "\n"))), con)
  }
  write_row(names(table))
  for (i in seq_len(nrow(table))) write_row(vapply(table, `[[`, character(1), i))
  invisible(path)
}
