# Frozen planning inputs only. The digest detects changes; it proves no authorship.
.protocol_registry <- function(study) {
  settings <- presentation_settings(study)
  trials <- lapply(1:2, function(i) list(id = paste0("trial-", letters[i]),
    condition = study$conditions[i], stimulus_id = study$stimulus_ids[i],
    exposure_id = paste0("exposure-", letters[i])))
  exposures <- lapply(trials, function(t) list(id = t$exposure_id,
    trial_id = t$id, stimulus_id = t$stimulus_id))
  epochs <- list()
  for (i in 1:2) {
    t <- trials[[i]]
    epochs[[length(epochs) + 1L]] <- list(id = paste0("epoch-", letters[i], "-view"),
      trial_id = t$id, exposure_id = t$exposure_id, stimulus_id = t$stimulus_id,
      phase = "passive_viewing", planned_duration_ms = settings$viewing_duration_ms,
      question_id = NULL, question_revision = NULL)
    if (length(study$questions)) {
      q <- study$questions[[1L]]
      epochs[[length(epochs) + 1L]] <- list(id = paste0("epoch-", letters[i], "-response"),
        trial_id = t$id, exposure_id = t$exposure_id, stimulus_id = t$stimulus_id,
        phase = "active_response", planned_duration_ms = NULL,
        question_id = q$id, question_revision = q$revision)
    }
  }
  orders <- switch(settings$order, counterbalanced_ab_ba = c("AB", "BA"),
                   fixed_ab = "AB", fixed_ba = "BA")
  list(trials = trials, exposures = exposures, epochs = epochs,
    orders = lapply(orders, function(id) list(id = id,
      trial_ids = paste0("trial-", tolower(strsplit(id, "", fixed = TRUE)[[1L]])))))
}

# Normalize object keys only; array order remains meaningful. R integer and
# double storage are equivalent on the wire. No unknown fields are discarded.
.protocol_normalize <- function(x) {
  if (is.list(x)) {
    if (!is.null(names(x))) {
      record_assert(!anyNA(names(x)) && !anyDuplicated(names(x)) &&
        all(nzchar(names(x))), "protocol: duplicate or invalid object fields")
      x <- x[order(names(x), method = "radix")]
    }
    return(lapply(x, .protocol_normalize))
  }
  if (is.character(x)) return(enc2utf8(x))
  if (is.numeric(x)) return(as.numeric(x))
  x
}

.protocol_wire <- function(protocol) {
  protocol <- .protocol_normalize(protocol)
  protocol$study <- .study_to_wire(protocol$study)
  protocol$registry$orders <- lapply(protocol$registry$orders, function(order) {
    order$trial_ids <- I(order$trial_ids)
    order
  })
  protocol
}

.protocol_encode <- function(protocol, pretty = FALSE) {
  enc2utf8(as.character(jsonlite::toJSON(.protocol_wire(protocol), auto_unbox = TRUE,
    null = "null", digits = 17, pretty = pretty)))
}

.protocol_hash <- function(protocol) {
  protocol$content_sha256 <- NULL
  digest::digest(charToRaw(.protocol_encode(protocol)), algo = "sha256", serialize = FALSE)
}

# Structural equality rejects duplicate/extra fields, objects used as arrays,
# wrong scalar types and dangling references, while ignoring object key order.
.protocol_equal <- function(actual, expected) {
  if (is.null(expected)) return(is.null(actual))
  if (is.list(expected)) {
    if (!is.list(actual) || length(actual) != length(expected)) return(FALSE)
    if (is.null(names(expected))) {
      if (!is.null(names(actual))) return(FALSE)
    } else {
      if (!record_fields(actual, names(expected))) return(FALSE)
      actual <- actual[names(expected)]
    }
    return(all(vapply(seq_along(expected), function(i)
      .protocol_equal(actual[[i]], expected[[i]]), logical(1))))
  }
  if (!is.null(attributes(actual)) || length(actual) != length(expected)) return(FALSE)
  if (is.numeric(expected)) return(is.numeric(actual) && !anyNA(actual) &&
    all(is.finite(actual)) && identical(as.numeric(actual), as.numeric(expected)))
  identical(actual, expected)
}

validate_protocol <- function(protocol) {
  tryCatch({
    a <- record_assert
    a(record_fields(protocol, c("schema_version", "status", "study", "registry", "content_sha256")),
      "protocol: fields")
    a(identical(protocol$schema_version, "study-protocol/0.1.0"), "protocol: unsupported version")
    a(identical(protocol$status, "planned"), "protocol: status must be planned")
    # This temporary envelope invokes all strict study/image/AOI checks; it is
    # never retained and describes no actual participant or recording session.
    study <- protocol$study
    envelope <- list(schema_version = contract_version, study = study,
      session = new_session(study, "protocol-validation", "not-enrolled", "preview"),
      clocks = list(), streams = list(), events = list())
    errors <- validate_bundle(envelope)
    a(!length(errors), paste(errors, collapse = "; "))
    a(length(study$stimulus_assets) == 2L, "protocol: upload both stimulus PNGs before freezing")
    a(.protocol_equal(protocol$registry, .protocol_registry(study)),
      "protocol: registry differs from the frozen study plan")
    a(is.character(protocol$content_sha256) && length(protocol$content_sha256) == 1L &&
      !is.na(protocol$content_sha256) && is.null(attributes(protocol$content_sha256)) &&
      grepl("^[0-9a-f]{64}$", protocol$content_sha256), "protocol: lowercase SHA-256 required")
    a(identical(protocol$content_sha256, .protocol_hash(protocol)), "protocol: content SHA-256 mismatch")
    character()
  }, error = function(e) paste("protocol:", conditionMessage(e)))
}

create_protocol <- function(bundle) {
  errors <- validate_bundle(bundle)
  record_assert(!length(errors), paste(errors, collapse = "; "))
  protocol <- list(schema_version = "study-protocol/0.1.0", status = "planned",
    study = bundle$study, registry = .protocol_registry(bundle$study))
  protocol$content_sha256 <- .protocol_hash(protocol)
  errors <- validate_protocol(protocol)
  record_assert(!length(errors), paste(errors, collapse = "; "))
  protocol
}

protocol_to_json <- function(protocol, pretty = FALSE) {
  errors <- validate_protocol(protocol)
  record_assert(!length(errors), paste(errors, collapse = "; "))
  .protocol_encode(protocol, pretty)
}

protocol_from_json <- function(text) {
  record_assert(scalar_text(text), "protocol JSON: one string required")
  record_assert(jsonlite::validate(text),
    "protocol JSON: valid JSON text required; file and URL references are not accepted")
  protocol <- jsonlite::fromJSON(text, simplifyVector = FALSE)
  record_assert(record_fields(protocol, c("schema_version", "status", "study", "registry", "content_sha256")),
    "protocol JSON: fields")
  protocol$study <- .study_from_wire(protocol$study)
  record_assert(record_fields(protocol$registry, c("trials", "exposures", "epochs", "orders")),
    "protocol JSON: registry fields")
  record_assert(all(vapply(protocol$registry, record_array, logical(1))),
    "protocol JSON: registry arrays required")
  protocol$registry$orders <- lapply(protocol$registry$orders, function(order) {
    record_assert(record_fields(order, c("id", "trial_ids")), "protocol JSON: order fields")
    order$trial_ids <- .wire_array_vector(order$trial_ids, "character")
    order
  })
  errors <- validate_protocol(protocol)
  record_assert(!length(errors), paste(errors, collapse = "; "))
  protocol
}
