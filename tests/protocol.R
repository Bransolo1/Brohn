for (module in c("study", "comparison", "presentation", "records", "json", "assets", "aois", "drafts", "protocol"))
  source(paste0("R/", module, ".R"))
protocol_checks <- 0L
expect_protocol <- function(ok) {
  stopifnot(isTRUE(ok)); protocol_checks <<- protocol_checks + 1L
}
protocol_rejected <- function(expr) inherits(try(expr, silent = TRUE), "try-error")
local({
  study <- new_study("protocol-fixture", title = "Frozen caf\u00e9 study")
  study$stimulus_assets <- lapply(1:2, function(i) new_png_asset(
    file.path("examples", "stimuli", paste0("sample-design-", letters[i], ".png")),
    study$stimulus_ids[i]))
  bundle <- new_bundle(study, new_session(study, "draft-only", "not-enrolled", "preview"))
  bundle <- revise_comparison(bundle, "A", "Current design")
  protocol <- create_protocol(bundle)
  expect_protocol(!length(validate_protocol(protocol)))
  expect_protocol(identical(protocol$study, bundle$study))
  expect_protocol(identical(names(protocol), c("schema_version", "status", "study", "registry", "content_sha256")))
  expect_protocol(identical(protocol$status, "planned") && !"aois" %in% names(protocol$study))
  expect_protocol(identical(protocol, create_protocol(bundle)))
  registry <- protocol$registry
  expect_protocol(length(registry$trials) == 2L && length(registry$exposures) == 2L &&
    length(registry$epochs) == 4L && length(registry$orders) == 2L)
  expect_protocol(identical(vapply(registry$trials, `[[`, "", "id"), c("trial-a", "trial-b")))
  expect_protocol(identical(vapply(registry$exposures, `[[`, "", "id"), c("exposure-a", "exposure-b")))
  expect_protocol(identical(vapply(registry$epochs, `[[`, "", "id"),
    c("epoch-a-view", "epoch-a-response", "epoch-b-view", "epoch-b-response")))
  expect_protocol(identical(registry$orders[[1]], list(id = "AB", trial_ids = c("trial-a", "trial-b"))))
  expect_protocol(identical(registry$orders[[2]], list(id = "BA", trial_ids = c("trial-b", "trial-a"))))
  for (i in 1:2) {
    trial <- registry$trials[[i]]; exposure <- registry$exposures[[i]]
    viewing <- registry$epochs[[2 * i - 1]]; response <- registry$epochs[[2 * i]]
    expect_protocol(identical(trial$stimulus_id, study$stimulus_ids[i]) &&
      identical(exposure$stimulus_id, trial$stimulus_id) &&
      identical(viewing$stimulus_id, trial$stimulus_id) && identical(response$stimulus_id, trial$stimulus_id))
    expect_protocol(identical(exposure$trial_id, trial$id) && identical(exposure$id, trial$exposure_id) &&
      identical(viewing$trial_id, trial$id) && identical(response$exposure_id, exposure$id))
    expect_protocol(identical(viewing$phase, "passive_viewing") && viewing$planned_duration_ms == 5000 &&
      is.null(viewing$question_id) && is.null(viewing$question_revision))
    expect_protocol(identical(response$phase, "active_response") && is.null(response$planned_duration_ms) &&
      identical(response$question_id, study$questions[[1]]$id) &&
      response$question_revision == study$questions[[1]]$revision)
  }
  before <- protocol_to_json(protocol)
  changed <- revise_presentation(revise_draft(bundle, "Edited draft", TRUE, "New prompt"), "fixed_ba", 8000)
  changed <- revise_comparison(changed, "B", "Replacement design")
  expect_protocol(identical(protocol_to_json(protocol), before))
  expect_protocol(!identical(create_protocol(changed)$content_sha256, protocol$content_sha256))
  expect_protocol(identical(comparison_settings(protocol$study)$control_condition, "A"))
  expect_protocol(identical(preview_presentation(protocol$study)$BA$role, c("test", "test", "control", "control")))
  changed$study$stimulus_assets[[1]]$sha256 <- strrep("0", 64)
  expect_protocol(identical(protocol_to_json(protocol), before))
  expect_protocol(protocol_rejected(create_protocol(changed)))

  decoded <- protocol_from_json(before)
  expect_protocol(.protocol_equal(decoded, protocol))
  expect_protocol(identical(protocol_to_json(decoded), before))
  expect_protocol(identical(protocol_from_json(protocol_to_json(protocol, TRUE))$content_sha256,
    protocol$content_sha256))
  reorder <- function(value) {
    if (!is.list(value)) return(value)
    if (!is.null(names(value))) value <- value[rev(seq_along(value))]
    lapply(value, reorder)
  }
  reordered <- reorder(protocol)
  expect_protocol(!length(validate_protocol(reordered)))
  expect_protocol(identical(protocol_to_json(reordered), before))
  integer_variant <- protocol
  integer_variant$study$revision <- as.numeric(integer_variant$study$revision)
  integer_variant$registry$epochs[[1]]$planned_duration_ms <- 5000L
  expect_protocol(identical(protocol_to_json(integer_variant), before))
  for (fixed in c("fixed_ab", "fixed_ba")) {
    frozen <- create_protocol(revise_presentation(bundle, fixed, 12345))
    wire <- jsonlite::fromJSON(protocol_to_json(frozen), simplifyVector = FALSE)
    expect_protocol(record_array(wire$registry$orders) && length(wire$registry$orders) == 1L)
    expect_protocol(record_array(wire$registry$trials) && record_array(wire$registry$orders[[1]]$trial_ids))
    expect_protocol(identical(frozen$registry$orders[[1]]$id, if (fixed == "fixed_ab") "AB" else "BA"))
    expect_protocol(identical(protocol_to_json(protocol_from_json(protocol_to_json(frozen))), protocol_to_json(frozen)))
  }
  no_question <- create_protocol(revise_draft(bundle, "No question", FALSE))
  wire <- jsonlite::fromJSON(protocol_to_json(no_question), simplifyVector = FALSE)
  expect_protocol(identical(wire$study$questions, list()) && identical(wire$study$measures, list("eye")))
  expect_protocol(length(wire$registry$epochs) == 2 && all(vapply(wire$registry$epochs,
    function(e) identical(e$phase, "passive_viewing") && is.null(e$question_id) &&
      is.null(e$question_revision), logical(1))))
  expect_protocol(!length(validate_protocol(protocol_from_json(protocol_to_json(no_question)))))

  # Every malformed shape must produce character errors rather than throwing.
  for (bad in list(NULL, TRUE, 42, "protocol", new.env(), list(), list(registry = registry))) {
    errors <- validate_protocol(bad)
    expect_protocol(is.character(errors) && length(errors) > 0)
  }
  for (edit in list(
    function(x) { x$schema_version <- "study-protocol/1.0.0"; x },
    function(x) { x$status <- "qualified"; x },
    function(x) { x$session <- bundle$session; x },
    function(x) { x$timestamp <- "2026-09-05"; x },
    function(x) { c(x, list(status = "planned")) },
    function(x) { x$study$extra <- TRUE; x },
    function(x) { x$study$analysis$status <- "qualified"; x },
    function(x) { x$study$analysis$extra <- TRUE; x },
    function(x) { x$study$questions[[1]]$extra <- TRUE; x },
    function(x) { x$study$stimulus_assets[[1]]$sha256 <- strrep("0", 64); x },
    function(x) { x$study$stimulus_assets[[1]]$stimulus_id <- "missing"; x },
    function(x) { x$registry <- NULL; x },
    function(x) { x$registry$extra <- list(); x },
    function(x) { x$registry$trials <- x$registry$trials[1]; x },
    function(x) { x$registry$trials <- rev(x$registry$trials); x },
    function(x) { names(x$registry$trials) <- c("a", "b"); x },
    function(x) { x$registry$trials[[2]] <- x$registry$trials[[1]]; x },
    function(x) { x$registry$trials[[1]]$extra <- TRUE; x },
    function(x) { x$registry$trials[[1]] <- c(x$registry$trials[[1]], list(id = "trial-a")); x },
    function(x) { x$registry$trials[[1]]$condition <- "B"; x },
    function(x) { x$registry$trials[[1]]$stimulus_id <- "stimulus-b"; x },
    function(x) { x$registry$exposures[[1]]$trial_id <- "missing"; x },
    function(x) { x$registry$epochs[[1]]$exposure_id <- "exposure-b"; x },
    function(x) { x$registry$epochs[[1]]$phase <- "active_response"; x },
    function(x) { x$registry$epochs[[1]]$planned_duration_ms <- 6000; x },
    function(x) { x$registry$epochs[[1]]$planned_duration_ms <- "5000"; x },
    function(x) { x$registry$epochs[[1]]$planned_duration_ms <- NA_real_; x },
    function(x) { x$registry$epochs[[1]]$planned_duration_ms <- matrix(5000); x },
    function(x) { x$registry$epochs[[1]]$question_id <- "q-liking"; x },
    function(x) { x$registry$epochs[[2]]$question_revision <- 2; x },
    function(x) { x$registry$epochs[[2]]$planned_duration_ms <- 5000; x },
    function(x) { x$registry$epochs[[2]]$planned_duration_ms <- NULL; x },
    function(x) { x$registry$orders[[1]]$id <- "BA"; x },
    function(x) { x$registry$orders[[1]]$trial_ids <- c("trial-a", "trial-a"); x },
    function(x) { x$registry$orders[[1]]$trial_ids <- "trial-a"; x },
    function(x) { x$registry$orders[[1]]$trial_ids <- list("trial-a", "trial-b"); x },
    function(x) { x$content_sha256 <- strrep("0", 64); x },
    function(x) { x$content_sha256 <- toupper(x$content_sha256); x }
  )) {
    bad <- edit(protocol)
    errors <- validate_protocol(bad)
    expect_protocol(is.character(errors) && length(errors) > 0L)
    expect_protocol(protocol_rejected(protocol_to_json(bad)))
  }
  for (count in 0:1) {
    missing <- bundle; missing$study$stimulus_assets <- missing$study$stimulus_assets[seq_len(count)]
    expect_protocol(!length(validate_bundle(missing)))
    expect_protocol(protocol_rejected(create_protocol(missing)))
  }
  bad_source <- bundle; bad_source$session$study_revision <- 999
  expect_protocol(protocol_rejected(create_protocol(bad_source)))
  custom <- bundle; custom$study$stimulus_ids <- c("original-design", "new-design")
  for (i in 1:2) custom$study$stimulus_assets[[i]]$stimulus_id <- custom$study$stimulus_ids[i]
  expect_protocol(identical(vapply(create_protocol(custom)$registry$trials, `[[`, "", "stimulus_id"),
    c("original-design", "new-design")))
  mutated <- protocol; mutated$study$title <- "Changed source"
  expect_protocol(any(grepl("SHA-256 mismatch", validate_protocol(mutated), fixed = TRUE)))
  # Rehashing valid edits is possible: integrity is neither signature nor qualification.
  mutated$content_sha256 <- .protocol_hash(mutated)
  expect_protocol(!length(validate_protocol(mutated)))
  wrong_registry <- protocol; wrong_registry$registry$epochs[[1]]$trial_id <- "missing"
  wrong_registry$content_sha256 <- .protocol_hash(wrong_registry)
  expect_protocol(any(grepl("registry differs", validate_protocol(wrong_registry), fixed = TRUE)))

  for (text in list("R/protocol.R", "https://example.com/protocol.json", "{broken", "null", "[]",
    "{}", "true", "42", "\"R/protocol.R\"", NA_character_, c(before, before)))
    expect_protocol(protocol_rejected(protocol_from_json(text)))
  for (edit in list(
    function(x) { x$study$measures <- "eye"; x },
    function(x) { x$study$questions <- list(id = "object"); x },
    function(x) { x$registry$trials <- x$registry$trials[[1]]; x },
    function(x) { x$registry$epochs[[1]]$question_id <- list(); x },
    function(x) { x$registry$epochs[[1]]$question_revision <- 0; x },
    function(x) { x$registry$orders <- x$registry$orders[[1]]; x },
    function(x) { x$registry$orders[[1]]$trial_ids <- "trial-a"; x },
    function(x) { x$registry$orders[[1]] <- c(x$registry$orders[[1]], list(id = "AB")); x },
    function(x) { x$study <- c(x$study, list(id = "duplicate")); x },
    function(x) { x$registry$epochs[[2]]$question_revision <- 9007199254740992; x }
  )) {
    wire <- edit(jsonlite::fromJSON(before, simplifyVector = FALSE))
    json <- as.character(jsonlite::toJSON(wire, auto_unbox = TRUE, null = "null", digits = 17))
    expect_protocol(protocol_rejected(protocol_from_json(json)))
  }
  large <- bundle
  large$study$revision <- 1234567890123456
  large$session$study_revision <- large$study$revision
  large$study$questions[[1]]$revision <- 9007199254740991
  fixture <- create_protocol(large)
  roundtrip <- protocol_from_json(protocol_to_json(fixture))
  expect_protocol(roundtrip$study$revision == 1234567890123456 &&
    roundtrip$registry$epochs[[2]]$question_revision == 9007199254740991)
  expect_protocol(identical(protocol_to_json(roundtrip), protocol_to_json(fixture)))
  if (nzchar(Sys.getenv("CONTRACT_FIXTURE_DIR")))
    writeBin(charToRaw(protocol_to_json(fixture)), file.path(Sys.getenv("CONTRACT_FIXTURE_DIR"), "protocol.json"))
})
cat(sprintf("PASS: %d protocol checks\n", protocol_checks))
