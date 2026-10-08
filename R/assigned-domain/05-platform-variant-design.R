# Inactive EF02/EF03 prototype. No legacy override, loader or persistence hook.
.brohn_vad_get <- function(x, name) x[[name, exact = TRUE]]
.brohn_vad_required <- c("schema_version", "id", "project_id", "title", "description", "template", "archived", "tags",
  "conditions", "stimuli", "questions", "order", "seed", "baseline_ms", "fixation_ms", "instructions", "consent",
  "debrief", "appearance", "measures", "methods", "blocks", "lineage", "evidence_mode", "stimulus_assignment")
.brohn_vad_optional <- c("analysis_plan", "camera", "scales", "maxdiff", "questionnaire_sections",
  "questionnaire_navigation", "welcome", "participant_equipment", "method_evidence", "method_evidence_implementations")

# Validate original bytes before any native-encoding conversion. Explicitly
# tagged Latin-1 has a defined mapping for every non-NUL byte; unmarked strings
# must already be UTF-8. Byte-tagged values are never text in this domain.
.brohn_vad_text_encoding <- function(x) {
  if (!is.character(x) || anyNA(x)) return(FALSE)
  encoding <- Encoding(x)
  if (any(!encoding %in% c("unknown", "UTF-8", "latin1"))) return(FALSE)
  if (!all(encoding == "latin1" | validUTF8(x))) return(FALSE)
  all(validUTF8(enc2utf8(x)))
}

.brohn_vad_domain <- function(value) {
  # Lower-bound byte accounting stops oversized trees before canonical encoding.
  # The exact existing 16 MiB codec limit is checked separately below.
  bytes <- 0
  add <- function(n) {
    bytes <<- bytes + n
    brohn_require(bytes <= 16 * 1024^2, "The complete variant design exceeds the 16 MiB input limit.")
  }
  visit <- function(x, depth = 0L) {
    brohn_require(depth < 64L, "Variant design nesting exceeds 64 levels.")
    attrs <- attributes(x)
    brohn_require(is.null(attrs) || (typeof(x) == "list" && identical(names(attrs), "names")),
      "Variant values require plain JSON types without attributes.")
    if (is.null(x)) { add(4); return(invisible(NULL)) }
    if (typeof(x) == "list") {
      keys <- names(x)
      if (!is.null(keys)) {
        brohn_require(!anyNA(keys) && all(nzchar(keys)) && .brohn_vad_text_encoding(keys) &&
          !anyDuplicated(enc2utf8(keys)), "Variant object keys must be valid, nonempty and unique.")
        add(sum(nchar(enc2utf8(keys), type = "bytes")) + 3 * length(keys))
      }
      add(2 + length(x))
      for (v in x) visit(v, depth + 1L)
      return(invisible(NULL))
    }
    brohn_require(typeof(x) %in% c("character", "logical", "integer", "double") && length(x) == 1L && !is.na(x),
      "Variant JSON scalars must be finite single values; arrays use lists.")
    if (is.character(x)) {
      brohn_require(.brohn_vad_text_encoding(x), "Variant text must be valid UTF-8.")
      add(2 + nchar(enc2utf8(x), type = "bytes"))
    } else {
      brohn_require(!is.numeric(x) || is.finite(x), "Variant JSON numbers must be finite.")
      add(1)
    }
    invisible(NULL)
  }
  visit(value)
  invisible(TRUE)
}

.brohn_vad_array <- function(x, minimum, maximum, label) {
  brohn_require(typeof(x) == "list" && is.null(names(x)) && length(x) >= minimum && length(x) <= maximum,
    paste(label, "must be an array with", minimum, "to", maximum, "entries."))
}
.brohn_vad_text <- function(x, label) brohn_require(brohn_text(x, 240), paste(label, "requires nonempty text of at most 240 bytes."))
.brohn_vad_enum <- function(x, values, label) brohn_require(is.character(x) && length(x) == 1L &&
  !is.na(x) && x %in% values, paste(label, "must be one supported scalar text value."))
.brohn_vad_unique_ids <- function(items, label) {
  ids <- vapply(items, function(x) .brohn_vad_get(x, "id"), character(1))
  brohn_require(all(vapply(as.list(ids), brohn_valid_id, logical(1))) && !anyDuplicated(ids), paste(label, "IDs must be valid and unique."))
  ids
}

.brohn_vad_assignment <- function(a, stimulus_ids) {
  brohn_fields(a, c("schema", "concepts", "sets", "arms", "allocation", "presentation"), label = "Stimulus assignment")
  brohn_require(identical(a$schema, "brohn-stimulus-assignment/0.1") &&
    identical(a$presentation, "selected-stimulus-order/0.1"), "Unsupported stimulus-assignment schema or presentation policy.")
  .brohn_vad_array(a$concepts, 1L, 250L, "Concepts")
  .brohn_vad_array(a$sets, 1L, 250L, "Variant sets")
  .brohn_vad_array(a$arms, 0L, 500L, "Allocation arms")
  for (x in a$concepts) { brohn_fields(x, c("id", "label"), label = "Concept"); .brohn_vad_text(x$label, "Concept label") }
  concept_ids <- .brohn_vad_unique_ids(a$concepts, "Concept")
  members <- character(); concepts <- character()
  for (s in a$sets) {
    brohn_fields(s, c("id", "concept_id", "label", "selection", "members"), label = "Variant set")
    .brohn_vad_text(s$label, "Set label")
    brohn_require(brohn_valid_id(s$concept_id) && s$concept_id %in% concept_ids,
      "A variant set needs one existing concept.")
    .brohn_vad_enum(s$selection, c("all", "one"), "Set selection")
    .brohn_vad_array(s$members, 2L, 500L, "Set members")
    for (m in s$members) {
      brohn_fields(m, c("stimulus_id", "variant_label"), label = "Set member")
      brohn_require(brohn_valid_id(m$stimulus_id) && m$stimulus_id %in% stimulus_ids, "Set member references an unavailable stimulus.")
      .brohn_vad_text(m$variant_label, "Variant label")
    }
    ids <- vapply(s$members, `[[`, character(1), "stimulus_id")
    labels <- vapply(s$members, function(m) enc2utf8(m$variant_label), character(1))
    brohn_require(!anyDuplicated(ids) && !anyDuplicated(labels), "Each set needs distinct stimulus IDs and variant labels.")
    members <- c(members, ids); concepts <- c(concepts, s$concept_id)
  }
  set_ids <- .brohn_vad_unique_ids(a$sets, "Variant set")
  brohn_require(!anyDuplicated(members), "A stimulus may belong to only one variant set.")
  brohn_require(!anyDuplicated(concepts) && setequal(concepts, concept_ids), "Each concept must own exactly one set; orphan concepts are unsupported.")
  one_sets <- Filter(function(s) identical(s$selection, "one"), a$sets)
  one_ids <- vapply(one_sets, `[[`, character(1), "id")
  .brohn_vad_enum(a$allocation, c("all/0.1", "blocked-arm-sha256/0.1", "arm-sha256/0.1"), "Allocation policy")
  if (!length(one_sets)) {
    brohn_require(!length(a$arms) && identical(a$allocation, "all/0.1"), "Show-all designs require no arms and allocation all/0.1.")
  } else {
    brohn_require(length(a$arms) >= 2L && a$allocation %in% c("blocked-arm-sha256/0.1", "arm-sha256/0.1"),
      "Show-one designs require at least two complete arms and a registered arm policy.")
  }
  brohn_require(sum(vapply(a$arms, function(x) length(.brohn_vad_get(x, "choices")), integer(1))) <= 125000L,
    "Allocation exceeds 125,000 explicit choice cells.")
  signatures <- character(); offered <- setNames(vector("list", length(one_ids)), one_ids)
  for (arm in a$arms) {
    brohn_fields(arm, c("id", "label", "choices"), label = "Allocation arm")
    .brohn_vad_text(arm$label, "Arm label")
    .brohn_vad_array(arm$choices, length(one_ids), length(one_ids), "Arm choices")
    for (j in seq_along(one_ids)) {
      choice <- arm$choices[[j]]
      brohn_fields(choice, c("set_id", "stimulus_id"), label = "Arm choice")
      brohn_require(identical(choice$set_id, one_ids[[j]]) && brohn_valid_id(choice$stimulus_id) &&
        choice$stimulus_id %in% vapply(one_sets[[j]]$members, `[[`, character(1), "stimulus_id"),
        "Each arm must choose one existing member for each show-one set, in declared set order.")
      offered[[j]] <- c(offered[[j]], choice$stimulus_id)
    }
    signatures <- c(signatures, paste(vapply(arm$choices, `[[`, character(1), "stimulus_id"), collapse = "|"))
  }
  .brohn_vad_unique_ids(a$arms, "Allocation arm")
  brohn_require(!anyDuplicated(signatures), "Allocation arms must have distinct complete choice vectors.")
  for (j in seq_along(one_ids)) brohn_require(setequal(offered[[j]], vapply(one_sets[[j]]$members, `[[`, character(1), "stimulus_id")),
    paste("Every member must be reachable in allocation arms for set", one_ids[[j]]))
  invisible(TRUE)
}

.brohn_vad_selected <- function(design, arm = NULL) {
  a <- design$stimulus_assignment
  grouped <- unlist(lapply(a$sets, function(s) vapply(s$members, `[[`, character(1), "stimulus_id")), use.names = FALSE)
  authored <- brohn_ids(design$stimuli)
  always <- authored[!authored %in% grouped]
  decisions <- lapply(a$sets, function(s) {
    ids <- if (identical(s$selection, "all")) vapply(s$members, `[[`, character(1), "stimulus_id") else {
      choices <- Filter(function(x) identical(x$set_id, s$id), arm$choices)
      brohn_require(length(choices) == 1L, "Validated arm lost its set choice.")
      choices[[1L]]$stimulus_id
    }
    list(set_id = s$id, concept_id = s$concept_id, selection = s$selection, selected_stimulus_ids = as.list(ids))
  })
  selected <- c(always, unlist(lapply(decisions, `[[`, "selected_stimulus_ids"), use.names = FALSE))
  brohn_require(!anyDuplicated(selected), "Assignment duplicated a stimulus identity.")
  list(always = always, selected = authored[authored %in% selected], sets = decisions)
}

.brohn_vad_plan <- function(design, operational) {
  plan <- .brohn_vad_get(operational, "analysis_plan")
  if (is.null(plan) || !length(plan$comparisons)) return(invisible(TRUE))
  arms <- design$stimulus_assignment$arms
  if (!length(arms)) arms <- list(NULL)
  for (arm in arms) {
    ids <- .brohn_vad_selected(design, arm)$selected
    projected <- operational
    projected$stimuli <- Filter(function(s) s$id %in% ids, operational$stimuli)
    conditions <- vapply(projected$stimuli, `[[`, character(1), "condition_id")
    for (comparison in plan$comparisons) brohn_require(all(c(comparison$control_id, comparison$test_id) %in% conditions),
      paste("Allocation arm", if (is.null(arm)) "all" else arm$id, "does not offer both conditions for paired comparison", comparison$id))
    # Existing validator also checks declared AOI outcome support in both conditions.
    brohn_validate_analysis_plan(plan, projected)
  }
  invisible(TRUE)
}

brohn_validate_variant_design <- function(design, publish = FALSE) {
  brohn_require(is.logical(publish) && length(publish) == 1L && !is.na(publish), "Declare the variant validation mode.")
  .brohn_vad_domain(design)
  brohn_fields(design, .brohn_vad_required, .brohn_vad_optional, "Variant design")
  brohn_require(identical(design$schema_version, "brohn-design/1.2.0"), "An explicit variant design1.2 is required.")
  .brohn_vad_enum(design$evidence_mode, c("none", "retained_1.1"), "Evidence mode")
  evidence <- c("method_evidence", "method_evidence_implementations")
  operational <- design[setdiff(names(design), c("evidence_mode", "stimulus_assignment"))]
  if (identical(design$evidence_mode, "none")) {
    brohn_require(!any(evidence %in% names(design)), "Evidence mode none requires absent evidence fields, not null placeholders.")
    operational$schema_version <- "brohn-design/1.0.0"
    brohn_validate_design(operational, publish = publish)
  } else {
    brohn_require(all(evidence %in% names(design)) && all(vapply(design[evidence], function(x) !is.null(x), logical(1))),
      "Retained evidence mode requires both complete original evidence fields.")
    brohn_require(exists("brohn_validate_evidence_design", mode = "function"), "Load the exact retained1.1 evidence validator before validating this inactive combination.")
    operational$schema_version <- "brohn-design/1.1.0"
    brohn_validate_evidence_design(operational, publish = publish)
  }
  .brohn_vad_assignment(design$stimulus_assignment, brohn_ids(design$stimuli))
  .brohn_vad_plan(design, operational)
  # Retain the stricter existing complete design/store codec ceiling. Do not save
  # or hash the internal operational projection in place of the full1.2 design.
  brohn_require(nchar(brohn_json(design), type = "bytes") <= 16 * 1024^2, "The complete variant design exceeds the 16 MiB JSON limit.")
  brohn_require(exists(".brohn_store_json", mode = "function"), "Load the existing bounded store codec for complete design validation.")
  .brohn_store_json(design)
  invisible(design)
}
