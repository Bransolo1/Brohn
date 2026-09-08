# Frozen multimodal synthesis. Explicit crosswalks link people; timestamps and
# coincident labels never create a join. Each outcome keeps its own denominator.
.brohn_mm_text <- function(x) if (brohn_text(x, 500)) x else NULL
.brohn_mm_key <- function(...) brohn_json(list(...))
brohn_measurement_design_hash <- function(design) {
  brohn_validate_design(design)
  projection <- design[setdiff(names(design), c("title", "description", "tags", "archived", "lineage"))]
  projection$stimuli <- lapply(projection$stimuli, function(s) s[setdiff(names(s), "aois")])
  brohn_hash(projection)
}
.brohn_mm_design_matches <- function(body, request) {
  full <- body$provenance$design_hash
  is.list(body$provenance$design) && identical(brohn_hash(body$provenance$design), full) &&
    if (identical(brohn_default(request$design_policy, "exact"), "exact")) identical(full, request$design_hash) else
      identical(brohn_measurement_design_hash(body$provenance$design), request$measurement_design_hash)
}
.brohn_mm_select <- function(store, study_id, report_ids, origin, design_policy = "exact") {
  study <- brohn_get_entity(store, "study", study_id)
  brohn_require(!is.null(study), "Select an existing study for synthesis.")
  brohn_require(brohn_array(report_ids) && length(report_ids) >= 1 && length(report_ids) <= 100 &&
    all(vapply(report_ids, brohn_text, logical(1), max = 96)) && !anyDuplicated(unlist(report_ids)), "Select 1 to 100 distinct saved reports.")
  brohn_require(origin %in% c("sample", "preview", "pilot", "live", "imported", "unspecified"), "Choose one explicit source origin for the synthesis.")
  brohn_require(design_policy %in% c("exact", "measurement_compatible_aoi_revision"), "Choose exact design matching or explicit compatible AOI-revision synthesis.")
  records <- lapply(report_ids, function(id) brohn_get_entity(store, "report", id))
  # Project ownership is checked before returning any title, state or contents.
  for (record in records) if (!is.null(record)) brohn_require(identical(record$project_id, study$project_id), "A selected report is outside this study's project.")
  available <- Filter(Negate(is.null), records)
  design <- if (length(available)) available[[1]]$body$provenance$design else study$body
  brohn_require(is.list(design) && identical(design$id, study_id) && identical(design$project_id, study$project_id), "Selected reports need their original study design and project provenance.")
  brohn_validate_design(design); hash <- brohn_hash(design)
  for (record in available) {
    body <- record$body
    brohn_require(identical(body$study_id, study_id) && identical(body$origin, origin), "Selected reports must belong to this study and the same declared origin.")
    brohn_require(.brohn_mm_design_matches(body, list(design_policy = design_policy, design_hash = hash, measurement_design_hash = brohn_measurement_design_hash(design))),
      "Selected reports use different or invalid frozen measurement designs. Choose one design version or explicitly compatible AOI revisions.")
  }
  list(study = study, design = design, design_hash = hash, records = records,
    references = lapply(seq_along(report_ids), function(i) {
      record <- records[[i]]
      list(id = report_ids[[i]], revision = if (is.null(record)) NULL else record$revision,
        hash = if (is.null(record)) NULL else brohn_hash(record$body), design_hash = if (is.null(record)) NULL else record$body$provenance$design_hash,
        state = if (is.null(record)) "missing_at_selection" else "selected")
    }))
}
.brohn_mm_validate_crosswalk <- function(crosswalk, report_ids) {
  brohn_require(brohn_array(crosswalk) && length(crosswalk) <= 20000, "Identity crosswalk must be a bounded array of reviewed mappings.")
  keys <- character()
  for (row in crosswalk) {
    brohn_fields(row, c("report_id", "source_participant_id", "source_session_id", "participant_id", "session_id"), label = "Identity crosswalk")
    brohn_require(all(vapply(row, brohn_text, logical(1), max = 500)) && row$report_id %in% report_ids, "Every crosswalk row needs a selected report and explicit source/target person and session identities.")
    keys <- c(keys, .brohn_mm_key(row$report_id, row$source_participant_id, row$source_session_id))
  }
  brohn_require(!anyDuplicated(keys), "A source person/session cannot be assigned more than once within a report.")
  invisible(TRUE)
}
.brohn_mm_validate_contrasts <- function(contrasts, report_ids, design, multiplicity) {
  brohn_require(brohn_array(contrasts) && length(contrasts) <= 100, "Declare up to 100 comparisons, or keep the synthesis descriptive.")
  ids <- character(); fingerprints <- character()
  for (contrast in contrasts) {
    brohn_fields(contrast, c("id", "report_ids", "modality", "metric", "outcome_id", "unit", "control_id", "test_id"), label = "Declared comparison")
    brohn_require(all(vapply(contrast[setdiff(names(contrast), "report_ids")], brohn_text, logical(1), max = 500)), "Each comparison needs explicit identities, measure, outcome and unit.")
    brohn_require(brohn_array(contrast$report_ids) && length(contrast$report_ids) >= 1 && !anyDuplicated(unlist(contrast$report_ids)) &&
      all(unlist(contrast$report_ids) %in% report_ids), "A comparison may use only explicitly selected, distinct source reports.")
    brohn_require(all(c(contrast$control_id, contrast$test_id) %in% brohn_ids(design$conditions)) && contrast$control_id != contrast$test_id, "Choose two distinct conditions from the frozen design.")
    ids <- c(ids, contrast$id); fingerprint <- contrast; fingerprint$id <- NULL; fingerprint$report_ids <- as.list(sort(unlist(fingerprint$report_ids)))
    fingerprints <- c(fingerprints, brohn_hash(fingerprint))
  }
  brohn_require(!anyDuplicated(ids) && !anyDuplicated(fingerprints), "Comparison IDs and hypotheses must be distinct.")
  brohn_fields(multiplicity, c("method", "alpha"), label = "Multiplicity policy")
  brohn_require(identical(multiplicity$method, "holm") && brohn_number(multiplicity$alpha, .0001, .2), "This recipe uses Holm correction across the full declared family; choose alpha explicitly.")
  invisible(TRUE)
}
brohn_prepare_multimodal <- function(store, study_id, report_ids, crosswalk, contrasts, origin,
    multiplicity = list(method = "holm", alpha = .05), identity_source, design_policy = "exact") {
  selected <- .brohn_mm_select(store, study_id, report_ids, origin, design_policy)
  brohn_require(brohn_text(identity_source, 4000), "Document the evidence used to link source identities across reports.")
  .brohn_mm_validate_crosswalk(crosswalk, unlist(report_ids))
  .brohn_mm_validate_contrasts(contrasts, unlist(report_ids), selected$design, multiplicity)
  list(schema = "brohn-multimodal-request/1.0", recipe = "multimodal-explicit-crosswalk/1.0-draft",
    study_id = study_id, project_id = selected$study$project_id, design = selected$design,
    design_hash = selected$design_hash, design_policy = design_policy, measurement_design_hash = brohn_measurement_design_hash(selected$design),
    origin = origin, reports = selected$references,
    crosswalk = crosswalk, contrasts = contrasts, multiplicity = multiplicity, identity_source = identity_source)
}
brohn_multimodal_input <- function(store, request) {
  brohn_require(identical(request$schema, "brohn-multimodal-request/1.0") && identical(request$recipe, "multimodal-explicit-crosswalk/1.0-draft"), "Unsupported multimodal request.")
  brohn_validate_design(request$design)
  brohn_require(brohn_default(request$design_policy, "exact") %in% c("exact", "measurement_compatible_aoi_revision"), "Unsupported frozen design compatibility policy.")
  brohn_require(identical(brohn_hash(request$design), request$design_hash) && identical(request$design$id, request$study_id) && identical(request$design$project_id, request$project_id), "Frozen synthesis design failed integrity verification.")
  brohn_require((is.null(request$measurement_design_hash) && identical(brohn_default(request$design_policy, "exact"), "exact")) ||
    identical(brohn_measurement_design_hash(request$design), request$measurement_design_hash), "Frozen measurement-design projection failed integrity verification.")
  report_ids <- vapply(request$reports, `[[`, character(1), "id")
  brohn_require(length(report_ids) >= 1 && length(report_ids) <= 100 && !anyDuplicated(report_ids), "Frozen report references are invalid.")
  .brohn_mm_validate_crosswalk(request$crosswalk, report_ids)
  .brohn_mm_validate_contrasts(request$contrasts, report_ids, request$design, request$multiplicity)
  sources <- lapply(request$reports, function(reference) {
    if (identical(reference$state, "missing_at_selection")) return(list(reference = reference, status = "missing", reason = "Report was absent when this selection was frozen.", body = NULL))
    brohn_require(identical(reference$state, "selected") && brohn_number(reference$revision, 1, integer = TRUE) && brohn_text(reference$hash, 64), "Frozen report reference is malformed.")
    record <- brohn_get_entity(store, "report", reference$id, reference$revision)
    if (!is.null(record)) brohn_require(identical(record$project_id, request$project_id), "A selected report is outside the permitted project.")
    if (is.null(record)) return(list(reference = reference, status = "integrity_issue", reason = "The pinned report revision is no longer available; no newer revision was substituted.", body = NULL))
    body <- record$body
    valid <- identical(brohn_hash(body), reference$hash) && identical(body$origin, request$origin) && identical(body$study_id, request$study_id) &&
      .brohn_mm_design_matches(body, request) && (is.null(reference$design_hash) || identical(body$provenance$design_hash, reference$design_hash))
    if (!valid) return(list(reference = reference, status = "integrity_issue", reason = "Pinned report content or study provenance failed verification.", body = NULL))
    if (!is.null(body$result_object$hash)) {
      verified <- tryCatch({ brohn_object_path(store, body$result_object$hash, verify = TRUE); TRUE }, error = function(e) FALSE)
      if (!verified) return(list(reference = reference, status = "integrity_issue", reason = "The report's retained result object is absent or corrupt.", body = NULL))
    }
    if (!is.list(body$analysis) || isFALSE(body$analysis$quality$usable) || isTRUE(body$analysis$status %in% c("error", "failed", "insufficient_support")))
      return(list(reference = reference, status = "unavailable", reason = "The selected analysis has no usable scientific support.", body = NULL))
    source <- list(reference = reference, status = "available", reason = NULL, body = body)
    if (brohn_questionnaire_is_artifact(body$analysis)) source$questionnaire_evidence <- brohn_questionnaire_source_reference(store, body)
    source
  })
  result <- list(schema = "brohn-multimodal-input/1.0", request = request, sources = sources)
  brohn_require(nchar(brohn_json(result), type = "bytes") <= 12*1024^2, "Selected synthesis reports exceed the 12 MiB frozen worker-input limit; select a smaller report set.")
  result
}
.brohn_mm_extract <- function(body, reference, design) {
  brohn_require(!brohn_questionnaire_is_artifact(body$analysis), "Read the complete questionnaire artifact before extracting scientific observations; preview rows are not evidence.")
  # Use each report's own AOI definition in compatible-revision synthesis.
  # Execution fields have already passed the explicitly selected match policy.
  design <- body$provenance$design
  a <- body$analysis; kind <- a$kind; rows <- list()
  emit <- function(source, index, container, modality, metric, outcome, unit, value, valid, reason, definition, support) {
    brohn_require(length(rows) < 100000L, "One source report exceeds 100,000 synthesis observations.")
    group <- brohn_default(source$group, source)
    condition <- .brohn_mm_text(source$condition_id)
    if (is.null(condition)) condition <- .brohn_mm_text(group$condition_id)
    if (!is.null(condition) && !condition %in% brohn_ids(design$conditions)) { valid <- FALSE; reason <- "condition_not_in_frozen_design" }
    if (!brohn_number(value)) { valid <- FALSE; reason <- brohn_default(reason, "missing_or_nonfinite_value"); value <- NULL }
    rows[[length(rows)+1L]] <<- list(source_report_id = reference$id, source_report_revision = reference$revision,
      source_report_hash = reference$hash, source_design_hash = body$provenance$design_hash,
      source_container = container, source_row = index, source_row_hash = brohn_hash(source),
      source_participant_id = .brohn_mm_text(group$participant_id), source_session_id = .brohn_mm_text(group$session_id),
      source_recording_id = .brohn_mm_text(source$recording_id), source_segment_id = .brohn_mm_text(brohn_default(source$segment_id, source$support_segment_id)),
      source_exposure_id = .brohn_mm_text(group$exposure_id), stimulus_id = .brohn_mm_text(source$stimulus_id),
      condition_id = condition, modality = modality, metric = metric, outcome_id = outcome, unit = unit, value = value,
      source_eligible = isTRUE(valid), source_missing_reason = if (isTRUE(valid)) NULL else brohn_default(reason, "unsupported_source_observation"),
      definition_hash = brohn_hash(definition), definition = definition, support = support, origin = body$origin)
  }
  if (identical(kind, "gaze")) {
    supported <- isTRUE(a$parameters$method %in% c("aoi-valid-gaze-time-share/0.1.0-draft", "brohn-adjacent-ray-ivt/0.1.0-draft"))
    for (i in seq_along(a$observations)) {
      source <- a$observations[[i]]
      stimulus <- brohn_find(design$stimuli, source$stimulus_id)
      aoi <- if (is.null(stimulus)) NULL else brohn_find(stimulus$aois, source$aoi_id)
      geometry <- !is.null(aoi) && identical(aoi$label, source$aoi_label) && identical(stimulus$condition_id, source$condition_id)
      valid <- supported && geometry && brohn_number(source$valid_ms, .Machine$double.eps) && brohn_number(source$inside_ms, 0, source$valid_ms) &&
        brohn_number(source$valid_share_percent, 0, 100) && abs(source$valid_share_percent-100*source$inside_ms/source$valid_ms) < 1e-6
      emit(source, i, "observations", "gaze", "valid_gaze_share", brohn_default(source$aoi_label, source$aoi_id), "percentage points",
        source$valid_share_percent, valid, if (valid) NULL else "unavailable_or_inconsistent_valid_gaze_support",
        list(method = a$parameters$method, denominator = source$denominator, coordinate_space = brohn_default(a$parameters$coordinate_space, "stimulus_normalized"),
          aoi_map = lapply(design$stimuli, function(s) list(stimulus_id = s$id, aois = Filter(function(a) identical(a$label, source$aoi_label), s$aois)))),
        list(valid_ms = source$valid_ms, inside_ms = source$inside_ms))
    }
  } else if (identical(kind, "questionnaire")) {
    brohn_require(exists(".brohn_delivery_answer", mode = "function"), "The shared typed-response validator is unavailable for synthesis.")
    for (i in seq_along(a$observations)) {
      source <- a$observations[[i]]; question <- brohn_find(design$questions, source$question_id)
      rating <- !is.null(question) && identical(question$type, "rating")
      quantitative <- !is.null(question) && question$type %in% c("rating", "number", "slider")
      valid <- quantitative && brohn_number(source$value) && is.null(source$missing_reason) &&
        tryCatch({.brohn_delivery_answer(question, list(value = source$value)); TRUE}, error = function(e) FALSE)
      emit(source, i, "observations", "questionnaire", if (rating) "explicit_rating" else "explicit_numeric_response", source$question_id,
        if (rating) "rating points" else "response units", source$value, valid,
        if (valid) NULL else if (!quantitative) "not_a_declared_quantitative_question" else "missing_or_invalid_numeric_response",
        list(question = question, method = if (rating) "declared_numeric_rating/1.0" else "declared_numeric_response/1.0"), list(question_type = brohn_default(question$type, "unknown")))
    }
  } else if (isTRUE(kind %in% c("temperature", "movement"))) {
    for (item in brohn_peripheral_synthesis_features(body)) {
      s <- item$source
      emit(s, item$index, "features", kind, s$name, s$channel, s$unit, s$value, item$valid,
        item$reason, item$definition, item$support)
    }
  } else if (isTRUE(kind %in% c("eda", "eeg", "ecg", "ppg", "respiration", "emg", "fnirs"))) {
    for (i in seq_along(a$features)) {
      source <- a$features[[i]]
      if (!brohn_text(source$name, 200) || !brohn_text(source$channel, 200) || !isTRUE(source$scope %in% c("recording", "recording_condition"))) next
      matched <- Filter(function(r) identical(r$recording_id, source$recording_id) &&
        (is.null(source$segment_id) || identical(r$segment_id, source$segment_id)) &&
        (is.null(r$channel) || identical(r$channel, source$channel)) &&
        (is.null(source$condition_id) || identical(r$condition_id, source$condition_id)), a$recordings)
      recipe <- a$parameters[[brohn_default(source$recording_id, "")]]
      if (is.null(recipe) && brohn_text(a$parameters$recipe, 200)) recipe <- a$parameters
      good <- length(matched) == 1L && identical(matched[[1]]$status, "computed") && brohn_text(source$unit, 120) && brohn_number(source$value) &&
        is.list(recipe) && brohn_text(recipe$recipe, 200)
      dimensions <- source[intersect(names(source), c("band_hz", "frequency_hz", "target_hz", "window_s", "polarity", "power"))]
      outcome <- if (length(dimensions)) paste0(source$channel, " | ", brohn_json(dimensions)) else source$channel
      emit(source, i, "features", kind, source$name, outcome, brohn_default(source$unit, "unit_missing"), source$value, good,
        if (good) NULL else "missing_or_ambiguous_computed_signal_support", list(recipe = recipe, dimensions = dimensions, scope = source$scope),
        if (length(matched) == 1L) matched[[1]] else list(status = "unavailable"))
    }
  }
  rows
}
brohn_multimodal_catalog <- function(store, study_id, report_ids, origin, design_policy = "exact") {
  request <- brohn_prepare_multimodal(store, study_id, report_ids, list(), list(), origin, identity_source = "Catalog inspection only; no identities linked.", design_policy = design_policy)
  input <- brohn_multimodal_input(store, request)
  records <- unlist(lapply(input$sources, function(s) if (s$status == "available") .brohn_mm_extract(brohn_complete_questionnaire_source(s), s$reference, request$design) else list()), recursive = FALSE)
  brohn_require(length(records) <= 200000L, "The source catalog exceeds 200,000 observations; choose fewer reports.")
  metrics <- list(); identities <- list(); metric_keys <- character(); identity_keys <- character()
  for (r in records) {
    key <- .brohn_mm_key(r$modality, r$metric, r$outcome_id, r$unit)
    if (!key %in% metric_keys) {
      brohn_require(length(metrics) < 1000L, "The source catalog exceeds 1,000 distinct measures; choose fewer reports.")
      same <- Filter(function(x) identical(.brohn_mm_key(x$modality, x$metric, x$outcome_id, x$unit), key), records)
      metrics[[length(metrics)+1L]] <- list(id = brohn_hash(brohn_parse(key)), label = paste(toupper(r$modality), gsub("_", " ", r$metric), r$outcome_id, paste0("(", r$unit, ")")),
        modality = r$modality, metric = r$metric, outcome_id = r$outcome_id, unit = r$unit,
        report_ids = as.list(unique(vapply(same, `[[`, character(1), "source_report_id"))), source_rows = length(same),
        eligible_source_rows = sum(vapply(same, `[[`, logical(1), "source_eligible")),
        definition_hashes = as.list(unique(vapply(same, `[[`, character(1), "definition_hash"))))
      metric_keys <- c(metric_keys, key)
    }
    if (is.null(r$source_participant_id) || is.null(r$source_session_id)) next
    key <- .brohn_mm_key(r$source_report_id, r$source_participant_id, r$source_session_id)
    if (!key %in% identity_keys) {
      brohn_require(length(identities) < 20000L, "The source catalog exceeds 20,000 identity mappings; choose fewer reports.")
      identities[[length(identities)+1L]] <- list(report_id = r$source_report_id, source_participant_id = r$source_participant_id,
        source_session_id = r$source_session_id, proposed_participant_id = r$source_participant_id,
        proposed_session_id = r$source_session_id, confirmed = FALSE)
      identity_keys <- c(identity_keys, key)
    }
  }
  list(study_id = study_id, design_hash = request$design_hash, design_policy = design_policy,
    measurement_design_hash = request$measurement_design_hash, origin = origin, metrics = metrics, identities = identities,
    sources = lapply(input$sources, function(s) list(report_id = s$reference$id, status = s$status, reason = s$reason)))
}
.brohn_mm_contrast <- function(spec, rows, design) {
  matched <- Filter(function(r) r$source_report_id %in% unlist(spec$report_ids) && identical(r$modality, spec$modality) &&
    identical(r$metric, spec$metric) && identical(r$outcome_id, spec$outcome_id) && identical(r$unit, spec$unit) &&
    isTRUE(r$condition_id %in% c(spec$control_id, spec$test_id)), rows)
  eligible <- Filter(function(r) isTRUE(r$eligible), matched)
  control <- brohn_find(design$conditions, spec$control_id); test <- brohn_find(design$conditions, spec$test_id)
  result <- c(spec, list(control_label = control$label, test_label = test$label, estimate = NULL, interval95 = NULL,
    participant_count = 0L, paired_session_count = 0L, excluded_session_count = 0L, candidate_source_rows = length(matched),
    eligible_source_rows = length(eligible), p_value = NULL, p_adjusted = NULL, rejects_null = NULL, status = "unavailable", reason = NULL,
    participant_differences = list(), session_differences = list(),
    aggregation = "Equal source observations per condition within reviewed person/session; paired session differences averaged within person; equal weight per person. No cross-modal complete-case deletion."))
  if (!length(eligible)) {result$reason <- "no_eligible_linked_observations"; return(result)}
  if (length(unique(vapply(eligible, `[[`, character(1), "definition_hash"))) != 1L) {result$reason <- "source_measure_definitions_disagree"; return(result)}
  duplicates <- vapply(eligible, function(r) .brohn_mm_key(r$participant_id, r$session_id, r$condition_id, r$exposure_id), character(1))
  if (anyDuplicated(duplicates)) {result$reason <- "duplicate_or_ambiguous_observation_identity"; return(result)}
  session_keys <- unique(vapply(eligible, function(r) .brohn_mm_key(r$participant_id, r$session_id), character(1)))
  sessions <- list()
  for (key in session_keys) {
    group <- Filter(function(r) identical(.brohn_mm_key(r$participant_id, r$session_id), key), eligible)
    a <- vapply(Filter(function(r) identical(r$condition_id, spec$control_id), group), `[[`, numeric(1), "value")
    b <- vapply(Filter(function(r) identical(r$condition_id, spec$test_id), group), `[[`, numeric(1), "value")
    if (!length(a) || !length(b)) next
    sessions[[length(sessions)+1L]] <- list(participant_id = group[[1]]$participant_id, session_id = group[[1]]$session_id,
      value = mean(b)-mean(a), control_observations = length(a), test_observations = length(b))
  }
  result$paired_session_count <- length(sessions); result$excluded_session_count <- length(session_keys)-length(sessions)
  if (!length(sessions)) {result$reason <- "no_within_session_condition_pairs"; return(result)}
  people <- unique(vapply(sessions, `[[`, character(1), "participant_id"))
  differences <- lapply(people, function(person) {
    visits <- Filter(function(s) identical(s$participant_id, person), sessions)
    list(participant_id = person, value = mean(vapply(visits, `[[`, numeric(1), "value")), session_count = length(visits))
  })
  values <- vapply(differences, `[[`, numeric(1), "value"); n <- length(values)
  result$participant_count <- n; result$estimate <- mean(values); result$participant_differences <- differences
  result$session_differences <- sessions; result$status <- "descriptive"
  if (n < 2L) {result$reason <- "at_least_two_people_needed_for_inference"; return(result)}
  sd <- stats::sd(values)
  if (!is.finite(sd) || sd <= .Machine$double.eps*max(1, max(abs(values)))) {result$reason <- "zero_or_negligible_between_person_variance"; return(result)}
  se <- sd/sqrt(n); margin <- stats::qt(.975, n-1L)*se
  result$interval95 <- list(lower = result$estimate-margin, upper = result$estimate+margin,
    method = "Unadjusted Student t interval of equal-person paired differences; Holm adjustment applies to p-values only", df = n-1L)
  result$p_value <- 2*stats::pt(-abs(result$estimate/se), df = n-1L)
  result$status <- "estimated"; result$reason <- NULL; result
}
brohn_analyse_multimodal <- function(input) {
  brohn_require(identical(input$schema, "brohn-multimodal-input/1.0"), "Unsupported multimodal input.")
  request <- input$request
  brohn_require(identical(brohn_hash(request$design), request$design_hash), "The synthesis design failed its worker integrity check.")
  brohn_require((is.null(request$measurement_design_hash) && identical(brohn_default(request$design_policy, "exact"), "exact")) ||
    identical(brohn_measurement_design_hash(request$design), request$measurement_design_hash), "The synthesis measurement projection failed its worker integrity check.")
  .brohn_mm_validate_crosswalk(request$crosswalk, vapply(request$reports, `[[`, character(1), "id"))
  .brohn_mm_validate_contrasts(request$contrasts, vapply(request$reports, `[[`, character(1), "id"), request$design, request$multiplicity)
  rows <- list(); statuses <- list(); crosswalk <- new.env(parent = emptyenv(), hash = TRUE)
  for (entry in request$crosswalk) assign(.brohn_mm_key(entry$report_id, entry$source_participant_id, entry$source_session_id), entry, envir = crosswalk)
  brohn_require(length(input$sources) == length(request$reports) && !anyDuplicated(vapply(input$sources, function(s) s$reference$id, character(1))), "Frozen synthesis sources must match their report selection exactly.")
  for (source in input$sources) {
    reference <- source$reference; available <- identical(source$status, "available")
    pinned <- Filter(function(r) identical(r$id, reference$id), request$reports)
    brohn_require(length(pinned) == 1L && identical(brohn_hash(pinned[[1]]), brohn_hash(reference)), "Source reference differs from the frozen selection.")
    if (available && (!identical(brohn_hash(source$body), reference$hash) || !identical(source$body$origin, request$origin) ||
      !.brohn_mm_design_matches(source$body, request) || (!is.null(reference$design_hash) && !identical(source$body$provenance$design_hash, reference$design_hash)))) {
      available <- FALSE; source$status <- "integrity_issue"; source$reason <- "Report content changed after the frozen worker input was prepared."
    }
    extracted <- if (available) .brohn_mm_extract(brohn_complete_questionnaire_source(source), reference, request$design) else list()
    for (i in seq_along(extracted)) {
      r <- extracted[[i]]
      mapped <- get0(.brohn_mm_key(r$source_report_id, r$source_participant_id, r$source_session_id), envir = crosswalk, inherits = FALSE)
      r$participant_id <- if (!is.null(mapped)) mapped$participant_id else NULL
      r$session_id <- if (!is.null(mapped)) mapped$session_id else NULL
      r$exposure_id <- brohn_default(r$source_exposure_id, paste0("source:", r$source_recording_id, ":", brohn_default(r$source_segment_id, "whole-recording")))
      # Gaze/questionnaire exposures must be actual source exposures. A absent
      # source identity cannot be replaced with row number or nearest timestamp.
      identity_support <- !is.null(r$source_exposure_id) || (!is.null(r$source_recording_id) && r$modality != "gaze" && r$modality != "questionnaire")
      r$eligible <- r$source_eligible && !is.null(mapped) && identity_support
      r$missing_reason <- if (!r$source_eligible) r$source_missing_reason else if (is.null(mapped)) "identity_not_explicitly_linked" else if (!identity_support) "source_observation_identity_unavailable" else NULL
      brohn_require(length(rows) < 200000L, "Synthesis exceeds 200,000 source observations; select fewer reports.")
      rows[[length(rows)+1L]] <- r
    }
    statuses[[length(statuses)+1L]] <- list(source_report_id = reference$id, revision = reference$revision, hash = reference$hash,
      status = if (available && !length(extracted)) "unsupported_measure" else source$status,
      reason = if (available && !length(extracted)) "This source contains no registered synthesis measure." else source$reason,
      extracted_rows = length(extracted), eligible_rows = sum(vapply(tail(rows, length(extracted)), function(r) isTRUE(r$eligible), logical(1))))
  }
  brohn_require(length(rows) <= 200000L, "Synthesis exceeds 200,000 source observations; select fewer reports.")
  contrasts <- lapply(request$contrasts, .brohn_mm_contrast, rows = rows, design = request$design)
  observed <- which(vapply(contrasts, function(c) brohn_number(c$p_value, 0, 1), logical(1)))
  if (length(observed)) {
    adjusted <- stats::p.adjust(vapply(contrasts[observed], `[[`, numeric(1), "p_value"), method = "holm", n = length(contrasts))
    for (i in seq_along(observed)) {
      index <- observed[[i]]; contrasts[[index]]$p_adjusted <- adjusted[[i]]
      contrasts[[index]]$rejects_null <- adjusted[[i]] <= request$multiplicity$alpha
    }
  }
  for (i in seq_along(contrasts)) {
    contrasts[[i]]$multiplicity <- list(method = "holm", family_size = length(contrasts),
      available_tests = length(observed), alpha = request$multiplicity$alpha,
      missing_hypotheses = "retained in declared family; unavailable p-values treated as larger than observed p-values for Holm adjustment")
    contrasts[[i]]$unavailable_sources <- Filter(function(s) s$source_report_id %in% unlist(contrasts[[i]]$report_ids) && !identical(s$status, "available"), statuses)
  }
  measures <- list(); keys <- unique(vapply(rows, function(r) .brohn_mm_key(r$modality, r$metric, r$outcome_id, r$unit), character(1)))
  for (key in keys) {
    group <- Filter(function(r) identical(.brohn_mm_key(r$modality, r$metric, r$outcome_id, r$unit), key), rows)
    usable <- Filter(function(r) isTRUE(r$eligible), group); first <- group[[1]]
    measures[[length(measures)+1L]] <- list(modality = first$modality, metric = first$metric, outcome_id = first$outcome_id, unit = first$unit,
      source_rows = length(group), eligible_rows = length(usable), excluded_rows = length(group)-length(usable),
      participant_count = length(unique(vapply(usable, `[[`, character(1), "participant_id"))),
      session_count = length(unique(vapply(usable, function(r) .brohn_mm_key(r$participant_id, r$session_id), character(1)))))
  }
  usable <- sum(vapply(rows, function(r) isTRUE(r$eligible), logical(1)))
  analysis <- list(kind = "multimodal", title = "Measures together, with explicit identity links", features = measures, observations = rows,
    contrasts = contrasts, recordings = statuses, status = if (usable) "completed" else "insufficient_support",
    quality = list(usable = usable > 0, scientifically_qualified = FALSE, selected_report_count = length(statuses),
      available_report_count = sum(vapply(statuses, function(s) identical(s$status, "available"), logical(1))),
      source_observation_count = length(rows), eligible_observation_count = usable, unlinked_observation_count = sum(vapply(rows, function(r) identical(r$missing_reason, "identity_not_explicitly_linked"), logical(1))),
      declared_comparison_count = length(contrasts), estimable_comparison_count = length(observed), cross_modal_complete_case_filter = FALSE),
    parameters = list(method = request$recipe, design_policy = brohn_default(request$design_policy, "exact"),
      measurement_design_hash = request$measurement_design_hash, identity_source = request$identity_source, multiplicity = request$multiplicity,
      family_size = length(contrasts), inference_unit = "equal person", observation_weighting = "equal eligible source observation within condition/session"),
    limitations = list("Cross-source identities use only the reviewed crosswalk. Matching labels, row position and timestamps do not establish person/session equivalence.",
      "Each measure retains its own eligible observations and sample size. Missing EEG, gaze or ratings do not remove another measure's otherwise eligible people.",
      "Source observations receive equal weight within condition/session. Repeated session differences are averaged within person. Recording-summary weighting is explicit and is not duration weighting.",
      "Different measure definitions or duplicate observation identities make the affected contrast unavailable. They are never silently pooled or deduplicated.",
      "Paired t inference assumes independent people and an appropriate difference distribution/design. Source rows, trials and repeat sessions are not additional people.",
      "Holm correction includes every declared hypothesis, including unavailable tests. Displayed 95 percent intervals are unadjusted and do not claim simultaneous coverage.",
      "These are parallel conditional comparisons, not temporal sensor fusion, a validated composite, a hierarchical model or a universal emotion/attention score."))
  list(title = paste(request$design$title, "multimodal synthesis"), study_id = request$study_id, dataset_id = NULL,
    origin = request$origin, project_id = request$project_id, provenance = list(design = request$design, design_hash = request$design_hash,
      selection = request$reports, crosswalk = request$crosswalk, crosswalk_hash = brohn_hash(request$crosswalk),
      identity_source = request$identity_source, declared_contrasts = request$contrasts, request_hash = brohn_hash(request)), analysis = analysis)
}
brohn_queue_multimodal <- function(store, study_id, report_ids, crosswalk, contrasts, origin,
    multiplicity = list(method = "holm", alpha = .05), identity_source, design_policy = "exact") {
  request <- brohn_prepare_multimodal(store, study_id, report_ids, crosswalk, contrasts, origin, multiplicity, identity_source, design_policy)
  brohn_enqueue_job(store, "analyse_multimodal", request, paste0("multimodal:", brohn_hash(request)))
}
