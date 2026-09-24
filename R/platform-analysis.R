brohn_validate_respiration_parameters <- function(parameters, unit) {
  brohn_require(is.list(parameters) && identical(parameters$recipe, "respiration-displacement-khodadad/1.0"),
    "Review the original respiration mapping: the new displacement recipe requires source quantity, inspiration direction and supporting evidence. Historical reports remain unchanged; airflow remains available as source data.")
  brohn_fields(parameters, c("recipe", "source_quantity", "polarity", "mapping_source"), "edge_exclusion_s", "Respiration parameters")
  brohn_require(isTRUE(parameters$source_quantity %in% c("belt_displacement", "lung_volume")) &&
    ((identical(parameters$source_quantity, "lung_volume") && identical(unit, "L")) ||
     (identical(parameters$source_quantity, "belt_displacement") && isTRUE(unit %in% c("a.u.", "V", "mV")))),
    "Choose confirmed belt displacement (a.u., V or mV) or calibrated lung volume (L). Airflow, including L/s, needs a separate onset-analysis method; preserve it without automatic analysis.")
  brohn_require(isTRUE(parameters$polarity %in% c("positive_inspiration", "negative_inspiration")) && brohn_text(parameters$mapping_source, 4000),
    "Declare which direction represents inspiration and the source evidence for this quantity and polarity; they cannot be inferred from a waveform.")
  brohn_require(is.null(parameters$edge_exclusion_s) || brohn_number(parameters$edge_exclusion_s, 5, 120), "Respiration edge exclusion must be 5 to 120 seconds.")
  invisible(parameters)
}

# Explicit import mappings and transparent report arithmetic. Heavy processing
# is performed by the worker process, never by the Shiny session.
brohn_rows <- function(table) lapply(seq_len(nrow(table)), function(i) {
  row <- as.list(table[i, , drop = FALSE])
  lapply(row, function(x) if (length(x) == 1L && is.na(x)) NULL else unname(x))
})
brohn_group <- function(table, fields) {
  if (!nrow(table)) return(list())
  keys <- vapply(seq_len(nrow(table)), function(i) brohn_json(as.list(unname(unlist(table[i, fields, drop = FALSE], use.names = FALSE)))), character(1))
  split(seq_len(nrow(table)), factor(keys, levels = unique(keys)))
}
brohn_nullable <- function(x) if (!length(x) || !is.finite(x)) NULL else unname(x)
brohn_numeric <- function(x, name, missing = FALSE) {
  blank <- is.na(x) | trimws(x) %in% c("", "NA", "NaN", "null")
  value <- suppressWarnings(as.numeric(x))
  brohn_require(all(blank | is.finite(value)), paste(name, "contains values that are not finite numbers."))
  if (!missing) brohn_require(!any(blank), paste(name, "contains missing values."))
  value[blank] <- NA_real_; value
}
brohn_read_table <- function(path, format, max_rows = 2000000L) {
  brohn_require(format %in% c("csv", "tsv"), "This analysis needs a tabular source.")
  prefix <- local({con <- file(path, "rb"); on.exit(close(con)); readBin(con, "raw", 3L)})
  connection <- file(path, "r"); on.exit(close(connection), add = TRUE)
  if (identical(prefix, as.raw(c(0xef, 0xbb, 0xbf)))) seek(connection, where = 3L, origin = "start")
  # A source cannot contain more records than bytes. Avoid reserving millions
  # of rows per column for a tiny file while keeping the max_rows+1 sentinel.
  read_rows <- min(max_rows + 1, as.numeric(file.info(path)$size) + 1)
  data <- withCallingHandlers(utils::read.table(connection, header = TRUE, sep = if (format == "csv") "," else "\t",
    colClasses = "character", check.names = FALSE, comment.char = "", quote = "\"",
    encoding = "UTF-8", na.strings = character(), nrows = read_rows), warning = function(warning) {
      message <- conditionMessage(warning)
      if (grepl("incomplete final line found by readTableHeader", message, fixed = TRUE)) invokeRestart("muffleWarning")
      if (grepl("embedded nul|EOF within quoted|invalid input|invalid multibyte|incomplete multibyte|number of items read", message, ignore.case = TRUE))
        brohn_stop(paste("The tabular source cannot be read without changing its contents:", message))
    })
  # Mark the original bytes as UTF-8 instead of converting them to the process
  # locale. Native conversion under Windows C locale can alter valid source
  # text. Invalid sequences must fail, never be repaired or transliterated.
  brohn_require(all(validUTF8(names(data))) && all(vapply(data, function(column) all(validUTF8(column)), logical(1))),
    "The tabular source contains malformed UTF-8. Preserve the original and export a valid UTF-8 CSV or TSV.")
  brohn_require(nrow(data) > 0L && nrow(data) <= max_rows && ncol(data) <= 1024L &&
    !anyDuplicated(names(data)) && all(nzchar(names(data))), paste("Source needs uniquely named columns and 1 to",format(max_rows,big.mark=",",scientific=FALSE,trim=TRUE),"rows."))
  data
}
brohn_validate_dataset_mapping <- function(dataset) {
  m <- dataset$metadata; columns <- unlist(dataset$columns, use.names = FALSE)
  brohn_require(is.list(m), "Confirm the source mapping first.")
  brohn_require(brohn_text(m$origin_statement, 4000), "Describe where this recording came from and how it was collected.")
  if (identical(dataset$modality, "maxdiff")) return(brohn_validate_maxdiff_mapping(dataset))
  if (identical(dataset$modality, "implicit")) return(brohn_validate_task_import_mapping(dataset))
  if (identical(dataset$modality, "video")) return(brohn_validate_vision_mapping(dataset))
  if (identical(dataset$modality, "multimodal")) return(brohn_validate_interchange_mapping(dataset))
  if (dataset$modality %in% c("temperature", "movement"))
    return(brohn_validate_peripheral_mapping(m, columns, dataset$source$format, dataset$modality))
  if (identical(dataset$modality, "eda") && brohn_eda_events_is_event(m)) return(brohn_validate_eda_events_mapping(m, columns, dataset$source$format))
  column <- function(field, required = TRUE) {
    v <- m[[field]]
    if (is.null(v) || identical(v, "")) {brohn_require(!required, paste("Map", gsub("_", " ", field))); return(invisible())}
    brohn_require(brohn_text(v, 500) && v %in% columns, paste("The mapped", gsub("_", " ", field), "is absent from the source."))
  }
  tabular <- dataset$source$format %in% c("csv", "tsv")
  if (tabular) {
    for (f in c("participant_column", "session_column", "condition_column", "stimulus_column", "exposure_column")) column(f, FALSE)
    if (dataset$modality != "questionnaire") brohn_require(m$time_unit %in% c("s", "ms"), "Choose seconds or milliseconds; native ticks require an explicit clock adapter.")
  }
  if (dataset$modality %in% c("gaze", "prepared_gaze")) {
    brohn_require(tabular, "Gaze analysis needs sampled gaze or prepared intervals in CSV or TSV.")
    brohn_require(!is.null(dataset$study_id), "Link gaze to the study revision whose stimuli and AOIs match this recording.")
    if (identical(m$gaze_representation, "samples")) {
      brohn_validate_raw_gaze_mapping(m, columns)
      return(invisible(dataset))
    }
    brohn_require(is.null(m$gaze_representation) || identical(m$gaze_representation, "intervals"), "Choose sampled gaze or prepared intervals.")
    for (f in c("participant_column", "session_column", "stimulus_column", "start_column", "end_column", "x_column", "y_column", "valid_column")) column(f)
    brohn_require(identical(m$unit, "stimulus_normalized"), "Confirm gaze coordinates use the stimulus-normalized 0 to 1 frame.")
    brohn_require(!is.null(dataset$study_id), "Link gaze to the study revision whose stimuli and AOIs match this recording.")
    column("phase_column", FALSE)
    brohn_require((brohn_text(m$phase_column, 500) && brohn_text(m$phase_value, 500)) ||
      identical(m$source_phase, "passive_viewing_only"), "Identify passive-viewing rows or explicitly confirm this file contains only passive-viewing intervals.")
  } else if (dataset$modality == "questionnaire") {
    brohn_require(tabular, "Questionnaire import needs CSV or TSV.")
    for (f in c("participant_column", "session_column", "question_column")) column(f)
    for (f in c("assessment_column", "assessment_exposure_column")) column(f, FALSE)
    if (!is.null(m$assessment_column)) brohn_require(!m$assessment_column %in% unlist(m[c("question_column", "value_columns")], use.names = FALSE),
      "Assessment identity must be declared separately from the question ID or response value.")
    brohn_require(length(m$value_columns) == 1L && m$value_columns[[1]] %in% columns, "Map one response-value column.")
    brohn_require(m$unit %in% c("numeric_rating", "text", "json"), "Declare whether response values are numeric ratings, text or typed JSON.")
  } else if (dataset$modality %in% c("eda", "eeg", "ecg", "ppg", "respiration", "emg", "audio", "fnirs")) {
    if (dataset$modality == "respiration") brohn_validate_respiration_parameters(m$parameters, m$unit)
    if (dataset$modality == "eeg") brohn_validate_neural_mapping(m, columns, dataset$source$format)
    if (tabular) {
      column("time_column")
      column("segment_column", FALSE)
      if (!is.null(m$segment_column)) brohn_require(!m$segment_column %in% unlist(m[c("time_column", "value_columns", "participant_column", "session_column", "condition_column", "exposure_column")], use.names = FALSE),
        "A recording segment needs its own identity column, separate from time, signal and participant fields.")
      brohn_require(brohn_array(m$value_columns) && length(m$value_columns) > 0L &&
        all(unlist(m$value_columns) %in% columns) && !anyDuplicated(unlist(m$value_columns)), "Choose distinct signal columns from this recording.")
      brohn_require(brohn_number(m$sampling_rate, 1, 100000), "Declare the recording sample rate in Hz.")
      brohn_require(brohn_text(m$unit, 80), "Declare the calibrated signal unit.")
    } else {
      brohn_require((dataset$modality == "eeg" && dataset$source$format %in% c("edf", "bdf", "fif", "set")) ||
        (dataset$modality == "audio" && dataset$source$format == "wav") || (dataset$modality == "fnirs" && dataset$source$format == "snirf"),
        "This native format does not have an enabled analysis recipe for the selected family.")
      if (dataset$modality %in% c("eeg", "fnirs")) brohn_require(length(m$value_columns) > 0L && all(vapply(m$value_columns, brohn_text, logical(1), max = 200)), "Select the native channel names from the recording header.")
      brohn_require(identical(m$unit, if (dataset$modality == "audio") "FS" else "native"), "Native physiology uses header scaling; audio uses full-scale units. Confirm the native unit policy.")
      if (dataset$modality == "fnirs") brohn_require(length(m$parameters$ppf) == 2 && all(vapply(m$parameters$ppf, brohn_number, logical(1), min = .1, max = 100)), "fNIRS needs two wavelength-specific partial pathlength factors from the selected protocol.")
    }
  } else brohn_stop("This recording can be retained in the library, but its analysis adapter is still being integrated. No generic score will be substituted.")
  invisible(dataset)
}
brohn_queue_dataset <- function(store, id, revision = NULL, force = FALSE, prepared_id = NULL) {
  record <- brohn_get_entity(store, "dataset", id, revision)
  brohn_require(!is.null(record), "Dataset revision is unavailable.")
  brohn_require(record$body$status %in% c("accepted", "analysed"), "Inspect and confirm the source mapping before analysis.")
  brohn_validate_dataset_mapping(record$body)
  study <- if (is.null(record$body$study_id)) NULL else brohn_study(store, record$body$study_id, record$body$study_revision)
  if (identical(record$body$modality,"implicit")) brohn_read_task_registry(store,record$body,study$body)
  if (identical(record$body$modality,"maxdiff")) brohn_validate_maxdiff_mapping(record$body,study$body)
  if (identical(record$body$modality, "eda") && brohn_eda_events_is_event(record$body$metadata))
    brohn_validate_eda_events_mapping(record$body$metadata, unlist(record$body$columns, use.names = FALSE), record$body$source$format, if (!is.null(study)) study$body else NULL)
  request <- list(dataset_id = id, dataset_revision = record$revision,
    dataset_hash = brohn_hash(record$body), study_id = if (is.null(study)) NULL else study$id,
    study_revision = if (is.null(study)) NULL else study$revision,
    study_hash = if (is.null(study)) NULL else brohn_hash(study$body), recipe = "brohn-analysis/1.0.0-draft")
  key <- paste0("dataset:", brohn_hash(request), if (force) paste0(":", brohn_id("rerun")) else "")
  brohn_enqueue_job(store, "analyse_dataset", request, key, prepared_id = prepared_id)
}
brohn_analysis_provenance <- function(dataset, revision, design = NULL, design_revision = NULL) {
  list(dataset_id = dataset$id, dataset_revision = revision, source = dataset$source,
    mapping = dataset$metadata, origin = dataset$origin, dataset_hash = brohn_hash(dataset),
    study_id = if (is.null(design)) NULL else design$id,
    study_revision = design_revision, design_hash = if (is.null(design)) NULL else brohn_hash(design),
    design = design, engine = list(name = "Brohn R", version = "1.0.0-draft", r_version = as.character(getRversion())))
}
brohn_paired_contrasts <- function(rows, conditions) {
  if (!nrow(rows) || !length(conditions)) return(list())
  controls <- Filter(function(c) c$role == "control", conditions)
  if (length(controls) != 1L) return(list())
  control <- controls[[1]]; tests <- Filter(function(c) c$role == "test", conditions)
  outputs <- list()
  for (metric_idx in brohn_group(rows, c("metric", "outcome_id", "unit"))) {
    values <- rows[metric_idx, , drop = FALSE]
    for (test in tests) {
      differences <- list()
      session_groups <- brohn_group(values, c("participant_id", "session_id"))
      for (group in session_groups) {
        session <- values[group, , drop = FALSE]
        a <- session$value[session$condition_id == control$id & is.finite(session$value)]
        b <- session$value[session$condition_id == test$id & is.finite(session$value)]
        if (length(a) && length(b)) differences[[length(differences)+1L]] <- data.frame(
          participant_id = session$participant_id[1], session_id = session$session_id[1], value = mean(b)-mean(a), stringsAsFactors = FALSE)
      }
      delta <- if (length(differences)) do.call(rbind, differences) else data.frame(participant_id=character(), session_id=character(), value=numeric())
      # Reuse the same ordered indices for values and identities. Rebuilding
      # every person's full index here made the saved summary quadratic.
      person_groups <- brohn_group(delta, "participant_id")
      person <- vapply(person_groups, function(ix) mean(delta$value[ix]), numeric(1))
      n <- length(person); estimate <- if (n) mean(person) else NA_real_
      se <- if (n >= 2) stats::sd(person)/sqrt(n) else NA_real_
      margin <- if (n >= 2) stats::qt(.975, df = n-1)*se else NA_real_
      outputs[[length(outputs)+1L]] <- list(metric = values$metric[1], outcome_id = values$outcome_id[1],
        unit = values$unit[1], control_id = control$id, control_label = control$label,
        test_id = test$id, test_label = test$label, estimate = brohn_nullable(estimate),
        participant_count = n, paired_session_count = nrow(delta),
        excluded_session_count = length(session_groups)-nrow(delta),
        interval95 = if (n >= 2) list(lower = estimate-margin, upper = estimate+margin,
          method = "Student t interval of equal-person paired differences", df = n-1L) else NULL,
        aggregation = "Equal exposure means per condition within session; paired session differences averaged within person; equal weight per person.",
        participant_differences = lapply(seq_along(person), function(i) list(participant_id = delta$participant_id[person_groups[[i]][1]], value = unname(person[i]))))
    }
  }
  outputs
}
brohn_gaze_analysis <- function(data, metadata, design) {
  m <- metadata
  source_rows <- nrow(data)
  if (brohn_text(m$phase_column, 500)) {
    brohn_require(m$phase_column %in% names(data) && brohn_text(m$phase_value, 500), "Map the passive-viewing phase column and value.")
    data <- data[!is.na(data[[m$phase_column]]) & data[[m$phase_column]] == m$phase_value, , drop = FALSE]
  } else brohn_require(identical(m$source_phase, "passive_viewing_only"), "Confirm the imported intervals describe passive viewing only.")
  brohn_require(nrow(data) > 0, "The source contains no mapped passive-viewing observations.")
  col <- function(field, fallback = "") if (is.null(m[[field]]) || !nzchar(m[[field]])) rep(fallback, nrow(data)) else data[[m[[field]]]]
  factor <- if (m$time_unit == "s") 1000 else 1
  start <- brohn_numeric(col("start_column"), "Interval starts")*factor
  end <- brohn_numeric(col("end_column"), "Interval ends")*factor
  brohn_require(all(start >= 0 & end > start & end < 1e12), "Gaze intervals need nonnegative, increasing times in a supported relative clock range.")
  raw_valid <- tolower(trimws(col("valid_column")))
  brohn_require(all(raw_valid %in% c("true", "false", "1", "0")), "Validity must be an explicit true/false or 1/0 for every interval.")
  valid <- raw_valid %in% c("true", "1")
  x <- brohn_numeric(col("x_column"), "Gaze x", missing = TRUE); y <- brohn_numeric(col("y_column"), "Gaze y", missing = TRUE)
  brohn_require(all(!valid | (is.finite(x) & is.finite(y))), "Valid gaze intervals require finite coordinates; mark missing observations invalid.")
  # Off-stimulus gaze is valid observation outside every stimulus AOI; never clamp.
  d <- data.frame(participant_id = col("participant_column"), session_id = col("session_column"),
    stimulus_id = col("stimulus_column"), exposure_id = col("exposure_column"), start = start, end = end,
    x = x, y = y, valid = valid, stringsAsFactors = FALSE)
  brohn_require(all(nzchar(d$participant_id) & nzchar(d$session_id) & nzchar(d$stimulus_id)), "Every interval needs participant, session and stimulus identities.")
  d$exposure_id[!nzchar(d$exposure_id)] <- d$stimulus_id[!nzchar(d$exposure_id)]
  brohn_require(all(d$stimulus_id %in% brohn_ids(design$stimuli)), "Some interval stimulus IDs do not exist in this pinned study design.")
  rows <- list(); metrics <- list()
  for (ix in brohn_group(d, c("participant_id", "session_id", "exposure_id"))) {
    g <- d[ix, , drop = FALSE]; g <- g[order(g$start, g$end), , drop = FALSE]
    brohn_require(length(unique(g$stimulus_id)) == 1, "An exposure identity cannot refer to multiple stimuli.")
    brohn_require(nrow(g) == 1 || all(g$start[-1] >= g$end[-nrow(g)]), "Gaze intervals overlap within an exposure. Provide separate exposure IDs for repeated presentations and remove duplicate intervals explicitly.")
    stimulus <- brohn_find(design$stimuli, g$stimulus_id[1])
    condition <- col("condition_column")[ix]; condition <- condition[nzchar(condition)]
    brohn_require(!length(condition) || all(condition == stimulus$condition_id), "Imported condition labels disagree with the pinned stimulus mapping. Map condition IDs explicitly.")
    brohn_require(!anyDuplicated(vapply(stimulus$aois, function(a) a$label, character(1))), "AOI labels must be distinct within each stimulus for this comparison recipe.")
    duration <- g$end-g$start; valid_ms <- sum(duration[g$valid]); span <- max(g$end)-min(g$start)
    observed <- sum(duration); complete <- all(g$valid) && abs(observed-span) < 1e-7
    for (a in stimulus$aois) {
      hit <- g$valid & !is.na(g$x) & !is.na(g$y) & g$x >= a$x & g$x < a$x+a$width & g$y >= a$y & g$y < a$y+a$height
      hit[is.na(hit)] <- FALSE
      inside <- sum(duration[hit]); share <- if (valid_ms > 0) 100*inside/valid_ms else NA_real_
      common <- list(participant_id = g$participant_id[1], session_id = g$session_id[1], exposure_id = g$exposure_id[1],
        stimulus_id = stimulus$id, condition_id = stimulus$condition_id, aoi_id = a$id, aoi_label = a$label)
      rows[[length(rows)+1L]] <- c(common, list(valid_ms = valid_ms, inside_ms = inside, interval_span_ms = span,
        unobserved_ms = span-valid_ms, valid_share_percent = brohn_nullable(share),
        first_observed_aoi_contact_ms = if (complete && any(hit)) min(g$start[hit])-min(g$start) else NULL,
        first_contact_status = if (!complete) "unavailable_incomplete_observation" else if (!any(hit)) "right_censored_no_contact" else "observed_interval_contact",
        denominator = "valid gaze interval time; off-stimulus observations retained", edge_policy = "left/top included; right/bottom excluded"))
      metrics[[length(metrics)+1L]] <- data.frame(participant_id=g$participant_id[1], session_id=g$session_id[1],
        condition_id=stimulus$condition_id, metric="valid_gaze_share", outcome_id=a$label, value=share, unit="percentage points", stringsAsFactors=FALSE)
    }
  }
  brohn_require(length(rows) > 0, "No AOIs are defined on the imported stimuli. Add and review regions before calculating gaze share.")
  values <- do.call(rbind, metrics)
  list(kind = "gaze", title = "Gaze and areas of interest", features = list(), observations = rows,
    contrasts = brohn_paired_contrasts(values, design$conditions),
    quality = list(source_rows = source_rows, retained_passive_rows = nrow(d), excluded_other_phase_rows = source_rows-nrow(d), participant_count = length(unique(d$participant_id)),
      session_count = length(brohn_group(d, c("participant_id", "session_id"))), invalid_interval_count = sum(!valid),
      missing_outcome_count = sum(!is.finite(values$value))),
    parameters = list(method = "aoi-valid-gaze-time-share/0.1.0-draft", coordinate_space = m$unit, input = "prepared_gaze_intervals", edge_policy = "half_open", phase_column = m$phase_column, phase_value = m$phase_value, source_phase = m$source_phase),
    limitations = list("Prepared intervals are not a fixation detector. First observed AOI contact is not time to first fixation.",
      "Observation spans do not establish full stimulus exposure or clock synchronization. Gaps and invalid intervals cannot be filled by assuming gaze stayed in place.",
      "AOI labels match outcomes across stimuli. Confirm those labels describe comparable regions.",
      "Intervals quantify this dataset. Population or causal interpretation requires the sampling and experimental design to support it."))
}
brohn_questionnaire_analysis <- function(responses, design = NULL) {
  # Response rows retain typed null/array/object values; only explicit numeric
  # items participate in means. Each committed exposure response is one row.
  summaries <- list(); values <- list()
  keys <- unique(vapply(responses, function(r) brohn_json(list(r$question_id, r$condition_id)), character(1)))
  for (key in keys) {
    group <- Filter(function(r) identical(brohn_json(list(r$question_id, r$condition_id)), key), responses)
    first <- group[[1]]; numeric <- vapply(group, function(r) if (brohn_number(r$value)) r$value else NA_real_, numeric(1))
    question <- if (is.null(design)) NULL else brohn_find(design$questions, first$question_id)
    quantitative <- is.null(question) || question$type %in% c("rating", "number", "slider")
    if (!quantitative) numeric[] <- NA_real_
    condition <- if (is.null(design) || is.null(first$condition_id)) NULL else brohn_find(design$conditions, first$condition_id)
    scale <- if (!is.null(question) && question$type == "rating") paste("Rating from", min(unlist(lapply(question$options, `[[`, "value"))), "to", max(unlist(lapply(question$options, `[[`, "value")))) else "Declared response values"
    answered <- Filter(function(r) !is.null(r$value), group)
    codes <- vapply(answered, function(r) brohn_json(r$value), character(1)); counts <- table(codes)
    summaries[[length(summaries)+1L]] <- list(question_id = first$question_id, prompt = first$prompt,
      condition_id = first$condition_id, condition_label = if (is.null(condition)) "Whole study" else condition$label,
      scale_description = scale, response_count = length(group), answered_count = length(answered),
      numeric_summary_status = if (!quantitative) "unavailable_categorical_or_structured_question" else if (is.null(question)) "source_numeric_values_without_design" else "declared_quantitative_question",
      missing_count = length(group)-length(answered), numeric_response_mean = if (any(is.finite(numeric))) mean(numeric[is.finite(numeric)]) else NULL,
      counts = lapply(names(counts), function(code) {
        options <- if (is.null(question)) list() else Filter(function(o) identical(brohn_json(o$value), code), question$options)
        list(value = brohn_parse(code), label = if (length(options)) options[[1]]$label else code, count = as.integer(counts[[code]]))
      }))
    for (i in seq_along(group)) {
      r <- group[[i]]
      if (quantitative && !is.null(r$condition_id) && nzchar(r$condition_id)) values[[length(values)+1L]] <- data.frame(
        participant_id = r$participant_id, session_id = r$session_id, condition_id = r$condition_id,
        metric = "explicit_response", outcome_id = r$question_id, value = numeric[i], unit = "response units", stringsAsFactors = FALSE)
    }
  }
  contrasts <- if (length(values) && !is.null(design)) brohn_paired_contrasts(do.call(rbind, values), design$conditions) else list()
  contrasts <- lapply(contrasts, function(c) {
    q <- brohn_find(design$questions, c$outcome_id); c$outcome_label <- if (is.null(q)) c$outcome_id else q$prompt
    if (!is.null(q) && q$type == "rating") c$unit <- "rating points"
    c
  })
  list(kind = "questionnaire", title = "Explicit responses", features = summaries, observations = responses,
    contrasts = contrasts,
    quality = list(response_count = length(responses), participant_count = length(unique(vapply(responses, `[[`, character(1), "participant_id"))),
      missing_response_count = sum(vapply(responses, function(r) is.null(r$value), logical(1)))),
    parameters = list(method = "typed-explicit-responses/1.0.0-draft", inference_unit = "participant", missing = "null excluded per outcome, never zero"),
    limitations = list("Numeric response means describe declared codes; they do not establish a validated psychological scale.",
      "Condition contrasts average paired session differences within each person. A repeated session is not an additional participant.",
      "Automatic reports retain response distributions; optional omissions and conditionally hidden questions must remain distinguishable in the response history."))
}
brohn_import_responses <- function(data, m, design = NULL) {
  get <- function(field, i, fallback = NULL) if (is.null(m[[field]]) || !nzchar(m[[field]])) fallback else data[[m[[field]]]][i]
  seen <- character()
  lapply(seq_len(nrow(data)), function(i) {
    participant <- get("participant_column", i); session <- get("session_column", i); qid <- get("question_column", i)
    brohn_require(all(vapply(list(participant, session, qid), brohn_text, logical(1), max = 500)), "Response rows require participant, session and question identities.")
    stimulus <- get("stimulus_column", i); condition <- get("condition_column", i)
    exposure <- get("exposure_column", i, stimulus)
    assessment <- get("assessment_column", i)
    key <- brohn_json(list(participant, session, qid, exposure, assessment))
    brohn_require(!key %in% seen, "Multiple committed responses share an exposure identity. Provide distinct exposure IDs or explicitly curate revisions before analysis.")
    seen <<- c(seen, key)
    raw <- data[[m$value_columns[[1]]]][i]
    value <- if (is.na(raw) || !nzchar(raw)) NULL else if (m$unit == "numeric_rating") brohn_nullable(brohn_numeric(raw, "Response")) else if (m$unit == "json") brohn_parse(raw) else raw
    q <- if (is.null(design)) NULL else brohn_find(design$questions, qid)
    if (!is.null(design)) {
      brohn_require(!is.null(q), "Imported question IDs do not match the pinned study design.")
      if (q$scope == "after_each") brohn_require(brohn_text(stimulus, 96), "After-each responses require their stimulus identity.") else
        brohn_require((is.null(stimulus) || !nzchar(stimulus)) && (is.null(condition) || !nzchar(condition)), "Before/end responses cannot be silently assigned to a stimulus condition.")
      if (!is.null(stimulus) && nzchar(stimulus)) {
        s <- brohn_find(design$stimuli, stimulus); brohn_require(!is.null(s), "Imported response references an unknown stimulus.")
        brohn_require(is.null(condition) || !nzchar(condition) || identical(condition, s$condition_id), "Response condition and stimulus mapping disagree.")
        condition <- s$condition_id
      }
      if (!is.null(value)) {
        brohn_require(exists(".brohn_delivery_answer", mode = "function"), "The shared typed-response validator is unavailable.")
        .brohn_delivery_answer(q, list(value = value))
      }
    }
    list(participant_id = participant, session_id = session, question_id = qid,
      prompt = if (is.null(q)) qid else q$prompt, stimulus_id = stimulus, exposure_id = exposure,
      assessment_id = assessment, assessment_exposure_id = get("assessment_exposure_column", i), participant_linkage = TRUE,
      condition_id = condition, value = value, missing_reason = if (is.null(value)) "imported_missing" else NULL,
      response_time_ms = NULL, source_row = i)
  })
}
