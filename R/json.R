# Keep wire arrays as arrays even when a study has only one selected measure.
.study_to_wire <- function(study) {
  for (field in c("conditions", "stimulus_ids", "measures")) study[[field]] <- I(study[[field]])
  study$questions <- lapply(study$questions, function(q) {
    for (field in c("option_ids", "codes", "labels")) q[[field]] <- I(q[[field]])
    q
  })
  study
}

# Validation precedes encoding and use.
bundle_to_json <- function(x, pretty = FALSE) {
  errors <- validate_bundle(x)
  record_assert(!length(errors), paste(errors, collapse = "; "))
  x$study <- .study_to_wire(x$study)
  x$events <- lapply(x$events, function(e) {
    if (!is.null(e$response)) e$response$displayed_option_ids <- I(e$response$displayed_option_ids)
    e
  })
  as.character(jsonlite::toJSON(x, auto_unbox = TRUE, null = "null", digits = 17,
                                pretty = pretty))
}

.wire_array_vector <- function(v, type) {
    record_assert(record_array(v) && length(v) > 0L &&
      all(vapply(v, function(y) length(y) == 1L &&
        if (type == "character") is.character(y) else is.numeric(y), logical(1))),
      paste("JSON: flat", type, "array required"))
    unlist(v, use.names = FALSE)
}

.study_from_wire <- function(study) {
  record_assert(is.list(study), "JSON: study object required")
  for (field in c("conditions", "stimulus_ids", "measures"))
    study[[field]] <- .wire_array_vector(study[[field]], "character")
  record_assert(record_array(study$questions), "JSON: questions array required")
  study$questions <- lapply(study$questions, function(q) {
    record_assert(is.list(q), "JSON: question object required")
    for (field in c("option_ids", "labels")) q[[field]] <- .wire_array_vector(q[[field]], "character")
    q$codes <- .wire_array_vector(q$codes, "numeric")
    q
  })
  study
}

bundle_from_json <- function(text) {
  record_assert(scalar_text(text), "JSON: one string required")
  record_assert(jsonlite::validate(text), "JSON: valid JSON text required; file and URL references are not accepted")
  x <- jsonlite::fromJSON(text, simplifyVector = FALSE)
  record_assert(is.list(x) && is.list(x$study), "JSON: bundle/study object required")
  x$study <- .study_from_wire(x$study)
  record_assert(record_array(x$events), "JSON: events array required")
  x$events <- lapply(x$events, function(e) {
    record_assert(is.list(e), "JSON: event object required")
    if (!is.null(e$response)) {
      record_assert(is.list(e$response), "JSON: response object required")
      e$response$displayed_option_ids <- .wire_array_vector(e$response$displayed_option_ids, "character")
    }
    e
  })
  errors <- validate_bundle(x)
  record_assert(!length(errors), paste(errors, collapse = "; "))
  x
}
