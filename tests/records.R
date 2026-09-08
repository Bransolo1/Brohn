source("examples/records.R")
b <- sample_bundle()
expect(!length(validate_bundle(b)))
bad_bundle <- function(change) expect(length(validate_bundle(change(b))) > 0L)
bad_bundle(function(x) { x$session$study_revision <- 2; x })
bad_bundle(function(x) { x$session$mode <- "live"; x })
bad_bundle(function(x) { x$events[[1]]$study_revision <- 2; x })
bad_bundle(function(x) { x$events[[1]]$source_time$unit <- "ms"; x })
bad_bundle(function(x) { x$events[[1]]$source_time$domain_id <- "another-clock"; x })
for (value in list(123, "NaN", "Inf", "1e9", "01", NA_character_)) {
  bad_bundle(function(x) { x$events[[1]]$source_time$value <- value; x })
}
bad_bundle(function(x) { x$events[[1]]$stimulus_id <- "unknown"; x })
bad_bundle(function(x) { x$events[[3]]$response$question_revision <- 2; x })
bad_bundle(function(x) { x$events[[3]]$response$value <- 5; x })
bad_bundle(function(x) { x$events[[3]]$response$option_id <- "unknown"; x })
bad_bundle(function(x) { x$events[[3]]$response["option_id"] <- list(NULL); x })
bad_bundle(function(x) { x$events[[1]]$response$value <- 0; x })
bad_bundle(function(x) { x$events[[1]]$response$option_id <- "like-4"; x })
bad_bundle(function(x) { x$study$questions[[1]]$required <- TRUE; x })
bad_bundle(function(x) { x$events[[3]]$phase <- "passive_viewing"; x })
bad_bundle(function(x) { x$events[[3]]$response$displayed_option_ids[1] <- "like-2"; x })
bad_bundle(function(x) { x$events[[3]]$response$value <- NULL; x })
bad_bundle(function(x) { x$events[[2]]$sequence <- 1; x })
bad_bundle(function(x) { x$events[[2]]$sequence <- 9007199254740992; x })
bad_bundle(function(x) { x$events[[2]]$segment_id <- "unknown"; x })
bad_bundle(function(x) { x$streams[[2]] <- x$streams[[1]]; x })
bad_bundle(function(x) { x$clocks[[2]] <- x$clocks[[1]]; x })
bad_bundle(function(x) { x$events[[1]]$mapped_time <- 0; x })
bad_bundle(function(x) { x$study$unexpected <- TRUE; x })
bad_bundle(function(x) { x$study$questions[[1]]$unexpected <- TRUE; x })
bad_bundle(function(x) { x$study <- c(x$study, list(id = "other-study")); x })
bad_bundle(function(x) { x$study$questions[[1]] <- c(x$study$questions[[1]], list(id = "other-question")); x })
bad_bundle(function(x) { x$study$analysis <- c(x$study$analysis, list(status = "qualified")); x })
# Local sequence identity permits a reset in a declared segment and another source.
for (field in c("segment_id", "id")) {
  z <- b; z$streams[[2]] <- z$streams[[1]]; z$streams[[2]][[field]] <- "second"
  z$events[[4]] <- z$events[[1]]
  z$events[[4]][[if (field == "id") "source_id" else field]] <- "second"
  z$events[[4]]$source_time$value <- "0"
  expect(!length(validate_bundle(z)))
}
z <- b; z$events <- rev(z$events)
expect(!length(validate_bundle(z))) # Arrival order is not a completeness claim.
wire <- bundle_to_json(b)
decoded <- bundle_from_json(wire)
local({
  reference <- tempfile(fileext = ".json")
  on.exit(unlink(reference), add = TRUE)
  writeLines(wire, reference)
  # A draft payload must never turn into an implicit read of another local file.
  expect(inherits(try(bundle_from_json(reference), silent = TRUE), "try-error"))
})
expect(isTRUE(all.equal(decoded, b)))
expect(identical(decoded$events[[3]]$source_time$value, "1234567890123456783"))
expect(identical(decoded$session$mode, "sample"))
expect(is.null(decoded$events[[2]]$response$value))
expect(identical(decoded$events[[2]]$response$status, "skipped"))
expect(isTRUE(all.equal(bundle_from_json(bundle_to_json(sample_bundle(FALSE))), sample_bundle(FALSE))))
z <- b; z$events[[3]]$response$displayed_option_ids <- rev(z$events[[3]]$response$displayed_option_ids)
expect(isTRUE(all.equal(bundle_from_json(bundle_to_json(z)), z)))
for (malformed in c(sub('"schema_version":"0.1.0"', '"schema_version":"99"', wire, fixed = TRUE),
                    sub('"id":"sample-study"', '"id":"sample-study","id":"other-study"', wire, fixed = TRUE),
                    sub('"value":null', '"value":0', wire, fixed = TRUE),
                    sub('"codes":[1,2,3,4,5,6,7]', '"codes":[[1],2,3,4,5,6,7]', wire, fixed = TRUE),
                    sub('"conditions":["A","B"]', '"conditions":{"a":"A","b":"B"}', wire, fixed = TRUE))) {
  expect(inherits(try(bundle_from_json(malformed), silent = TRUE), "try-error"))
}
if (nzchar(Sys.getenv("CONTRACT_FIXTURE_DIR"))) {
  dir.create(Sys.getenv("CONTRACT_FIXTURE_DIR"), recursive = TRUE, showWarnings = FALSE)
  writeLines(wire, file.path(Sys.getenv("CONTRACT_FIXTURE_DIR"), "bundle.json"))
  writeLines(bundle_to_json(sample_bundle(FALSE)), file.path(Sys.getenv("CONTRACT_FIXTURE_DIR"), "empty.json"))
}

# JSON must preserve every accepted portable integer, not just typical revisions.
precision <- b
precision$study$revision <- 9007199254740991
precision$session$study_revision <- precision$study$revision
precision$study$questions[[1]]$revision <- 1234567890123456
precision$events <- lapply(precision$events, function(event) {
  event$study_revision <- precision$study$revision
  event$response$question_revision <- precision$study$questions[[1]]$revision
  event
})
precision$events[[3]]$sequence <- 9007199254740991
expect(!length(validate_bundle(precision)))
decoded_precision <- bundle_from_json(bundle_to_json(precision))
expect(identical(decoded_precision$study$revision, precision$study$revision))
expect(identical(decoded_precision$study$questions[[1]]$revision, precision$study$questions[[1]]$revision))
expect(identical(decoded_precision$events[[3]]$sequence, precision$events[[3]]$sequence))
if (nzchar(Sys.getenv("CONTRACT_FIXTURE_DIR")))
  writeLines(bundle_to_json(precision), file.path(Sys.getenv("CONTRACT_FIXTURE_DIR"), "precision.json"))
