# Portable draft records. These are not a recorder or a durable event journal.
record_fields <- function(x, fields) {
  is.list(x) && !is.null(names(x)) && !anyDuplicated(names(x)) &&
    setequal(names(x), fields)
}
record_assert <- function(ok, message) {
  if (!isTRUE(ok)) stop(message, call. = FALSE)
}
text_choice <- function(x, choices) scalar_text(x) && x %in% choices
safe_integer <- function(x) positive_integer(x) && x <= 9007199254740991
record_array <- function(x) is.list(x) && is.null(names(x))

new_clock <- function(id, domain_id, domain = "browser_monotonic", unit = "ms") {
  list(id = id, domain_id = domain_id, domain = domain, unit = unit)
}
new_stream <- function(id, session, clock, segment_id, modality) {
  list(id = id, run_id = session$id, clock_id = clock$id,
       segment_id = segment_id, modality = modality)
}
new_response <- function(question, status = "unanswered", option_id = NULL,
                         displayed_option_ids = question$option_ids) {
  code <- if (identical(status, "answered") && scalar_text(option_id))
    question$codes[match(option_id, question$option_ids)] else NULL
  list(question_id = question$id, question_revision = question$revision,
       status = status, option_id = option_id, value = code,
       displayed_option_ids = displayed_option_ids)
}
new_event <- function(session, stream, clock, sequence, raw_time, trial_id,
                      exposure_id, stimulus_id, epoch_id, phase, meaning,
                      response = NULL) {
  list(run_id = session$id, study_id = session$study_id,
       study_revision = session$study_revision, mode = session$mode,
       source_id = stream$id, segment_id = stream$segment_id, sequence = sequence,
       event_type = if (is.null(response)) "observation" else "question.response_state",
       source_time = list(clock_id = clock$id, domain_id = clock$domain_id,
                          value = raw_time, unit = clock$unit, meaning = meaning),
       trial_id = trial_id, exposure_id = exposure_id, stimulus_id = stimulus_id,
       epoch_id = epoch_id, phase = phase, response = response)
}
new_bundle <- function(study, session, clocks = list(), streams = list(), events = list()) {
  x <- list(schema_version = contract_version, study = study, session = session,
            clocks = clocks, streams = streams, events = events)
  errors <- validate_bundle(x)
  record_assert(!length(errors), paste(errors, collapse = "; "))
  x
}

validate_bundle <- function(x) {
  # Fail closed on malformed shapes before reading dependent fields.
  tryCatch({
    a <- record_assert
    a(record_fields(x, c("schema_version", "study", "session", "clocks", "streams", "events")), "bundle: fields")
    a(identical(x$schema_version, contract_version), "bundle: unsupported version")
    study_fields <- c("schema_version", "id", "revision", "design", "conditions", "stimulus_ids", "measures", "questions", "analysis")
    if ("title" %in% names(x$study)) study_fields <- c(study_fields, "title")
    if ("stimulus_assets" %in% names(x$study)) study_fields <- c(study_fields, "stimulus_assets")
    if ("aois" %in% names(x$study)) study_fields <- c(study_fields, "aois")
    if ("comparison" %in% names(x$study)) study_fields <- c(study_fields, "comparison")
    if ("presentation" %in% names(x$study)) study_fields <- c(study_fields, "presentation")
    a(record_fields(x$study, study_fields), "study: fields")
    a(!length(validate_study(x$study)), "bundle: invalid study")
    study <- x$study; run <- x$session
    if ("stimulus_assets" %in% names(study)) {
      asset_errors <- validate_stimulus_assets(study$stimulus_assets, study$stimulus_ids)
      a(!length(asset_errors), paste("study images:", paste(asset_errors, collapse = "; ")))
    }
    if ("aois" %in% names(study)) {
      aoi_errors <- validate_study_aois(study)
      a(!length(aoi_errors), paste("study areas:", paste(aoi_errors, collapse = "; ")))
    }
    a(record_array(study$questions), "study: questions array required")
    a(record_fields(study$analysis, c("method_id", "contrast", "status")), "analysis: fields")
    for (q in study$questions) a(record_fields(q, c("id", "revision", "type", "prompt", "scope", "required", "option_ids", "codes", "labels")), "question: fields")
    a(record_fields(run, c("schema_version", "id", "participant_id", "study_id", "study_revision", "mode", "execution", "capture", "transfer", "review")), "session: fields")
    a(identical(run$schema_version, contract_version) && scalar_text(run$id) && scalar_text(run$participant_id), "session: version/identity")
    a(identical(run$study_id, study$id) && safe_integer(run$study_revision) && run$study_revision == study$revision, "session: study revision mismatch")
    a(text_choice(run$mode, c("sample", "preview", "pilot", "live")), "session: mode")
    a(all(vapply(run[c("execution", "capture", "transfer", "review")], identical, logical(1), "not_started")), "session: lifecycle transitions not implemented")
    a(safe_integer(study$revision) && all(vapply(study$questions, function(q) safe_integer(q$revision), logical(1))), "study: revisions exceed portable integer range")
    a(all(vapply(x[c("clocks", "streams", "events")], record_array, logical(1))), "bundle: arrays required")
    clock_ids <- character()
    for (clock in x$clocks) {
      a(record_fields(clock, c("id", "domain_id", "domain", "unit")), "clock: fields")
      a(scalar_text(clock$id) && scalar_text(clock$domain_id), "clock: identity")
      a(text_choice(clock$domain, c("device_monotonic", "host_monotonic", "browser_monotonic", "utc")), "clock: domain")
      a(text_choice(clock$unit, c("s", "ms", "us", "ns")), "clock: unit")
      clock_ids <- c(clock_ids, clock$id)
    }
    a(!anyDuplicated(clock_ids), "clock: duplicate ID")
    stream_keys <- list()
    for (stream in x$streams) {
      a(record_fields(stream, c("id", "run_id", "clock_id", "segment_id", "modality")), "stream: fields")
      a(scalar_text(stream$id) && scalar_text(stream$segment_id) && identical(stream$run_id, run$id), "stream: identity/run")
      a(text_choice(stream$clock_id, clock_ids) && text_choice(stream$modality, study$measures), "stream: clock/modality")
      key <- list(stream$id, stream$segment_id)
      a(!any(vapply(stream_keys, identical, logical(1), key)), "stream: duplicate source/segment")
      stream_keys[[length(stream_keys) + 1L]] <- key
    }
    event_keys <- list()
    for (event in x$events) {
      a(record_fields(event, c("run_id", "study_id", "study_revision", "mode", "source_id", "segment_id", "sequence", "event_type", "source_time", "trial_id", "exposure_id", "stimulus_id", "epoch_id", "phase", "response")), "event: fields")
      a(identical(event$run_id, run$id) && identical(event$study_id, study$id) && safe_integer(event$study_revision) && event$study_revision == study$revision && identical(event$mode, run$mode), "event: origin/study mismatch")
      a(safe_integer(event$sequence), "event: sequence must be a safe positive integer")
      a(all(vapply(event[c("source_id", "segment_id", "trial_id", "exposure_id", "epoch_id")], scalar_text, logical(1))), "event: context IDs required")
      a(text_choice(event$stimulus_id, study$stimulus_ids), "event: unknown stimulus")
      stream_index <- which(vapply(stream_keys, identical, logical(1), list(event$source_id, event$segment_id)))
      a(length(stream_index) == 1L, "event: unknown source/segment")
      stream <- x$streams[[stream_index]]
      clock <- x$clocks[[match(stream$clock_id, clock_ids)]]
      tm <- event$source_time
      a(record_fields(tm, c("clock_id", "domain_id", "value", "unit", "meaning")), "event time: fields")
      a(identical(tm$clock_id, clock$id) && identical(tm$domain_id, clock$domain_id) && identical(tm$unit, clock$unit), "event time: clock provenance mismatch")
      a(scalar_text(tm$value) && grepl("^-?(0|[1-9][0-9]*)(\\.[0-9]+)?$", tm$value), "event time: raw decimal string required")
      a(text_choice(tm$meaning, c("source_sample", "host_arrival", "presentation_observed", "response_observed", "inference_complete")), "event time: meaning")
      a(text_choice(event$phase, c("passive_viewing", "active_response")), "event: phase")
      key <- list(event$run_id, event$source_id, event$segment_id, as.numeric(event$sequence))
      a(!any(vapply(event_keys, identical, logical(1), key)), "event: duplicate identity")
      event_keys[[length(event_keys) + 1L]] <- key
      if (is.null(event$response)) {
        a(identical(event$event_type, "observation"), "event: missing response")
      } else {
        a(identical(event$event_type, "question.response_state") && identical(event$phase, "active_response") && identical(tm$meaning, "response_observed") && identical(stream$modality, "questionnaire"), "response: event context")
        r <- event$response
        a(record_fields(r, c("question_id", "question_revision", "status", "option_id", "value", "displayed_option_ids")), "response: fields")
        a(length(study$questions) == 1L, "response: no question in study")
        q <- study$questions[[1L]]
        a(identical(r$question_id, q$id) && safe_integer(r$question_revision) && r$question_revision == q$revision, "response: stale/unknown question")
        a(is.character(r$displayed_option_ids) && !anyNA(r$displayed_option_ids) && !anyDuplicated(r$displayed_option_ids) && setequal(r$displayed_option_ids, q$option_ids), "response: displayed options must be a permutation")
        a(text_choice(r$status, c("unanswered", "skipped", "answered")), "response: status")
        if (identical(r$status, "answered")) {
          a(text_choice(r$option_id, q$option_ids), "response: unknown option")
          a(safe_integer(r$value) && r$value == q$codes[match(r$option_id, q$option_ids)], "response: option/code mismatch")
        } else {
          a(is.null(r$option_id) && is.null(r$value), "response: missingness requires explicit nulls")
          a(!(identical(r$status, "skipped") && q$required), "response: required question cannot be skipped")
        }
      }
    }
    character()
  }, error = function(e) conditionMessage(e))
}
