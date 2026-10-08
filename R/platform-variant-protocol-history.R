# Inactive saved1.2 reader. No prospective compiler/current allocator or registry.
# Historical SHA ranking below checks the explicitly registered0.1 receipt;
# legacy randomized task/section/options are only validated as retained tables.
.brohn_vph_decimal <- function(x) sprintf("%.0f", x)
.brohn_vph_policy_01 <- function(d) {
  a <- d$stimulus_assignment
  list(schema = "brohn-assignment-policy/0.1", seed = .brohn_vph_decimal(d$seed),
    allocation = a$allocation, presentation = a$presentation, order = d$order,
    stimuli = as.list(brohn_ids(d$stimuli)),
    sets = lapply(a$sets, function(s) list(id = s$id, concept_id = s$concept_id, selection = s$selection,
      members = lapply(s$members, `[[`, "stimulus_id"))),
    arms = lapply(a$arms, function(a) list(id = a$id, choices = a$choices)))
}
.brohn_vph_rank_01 <- function(messages, ids) {
  hashes <- vapply(messages, .brohn_ph_hash, character(1))
  order(hashes, ids, method = "radix")
}
.brohn_vph_receipt_validated <- function(p) {
  d <- p$design; a <- d$stimulus_assignment; r <- p$stimulus_assignment
  brohn_fields(r, c("schema", "policy_hash", "design_hash", "allocation", "allocation_index", "arm_id",
    "block", "slot", "sets", "always_stimulus_ids", "selected_stimulus_ids", "realized_stimulus_order"), label = "Saved assignment receipt")
  policy_hash <- .brohn_ph_hash(.brohn_vph_policy_01(d))
  index <- .brohn_vph_decimal(p$allocation_index)
  arm <- NULL; block <- NULL; slot <- NULL
  if (!identical(a$allocation, "all/0.1")) {
    ids <- brohn_ids(a$arms)
    if (identical(a$allocation, "blocked-arm-sha256/0.1")) {
      block <- floor((p$allocation_index - 1) / length(ids))
      slot <- (p$allocation_index - 1) %% length(ids)
      messages <- lapply(ids, function(id) list(schema = "brohn-arm-block/0.1", policy_hash = policy_hash,
        block = .brohn_vph_decimal(block), arm_id = id))
      selected_position <- .brohn_vph_rank_01(messages, ids)[[slot + 1L]]
    } else {
      # The complete design validator already refuses unknown allocation versions.
      brohn_require(identical(a$allocation, "arm-sha256/0.1"), "Unknown saved allocation version.")
      messages <- lapply(ids, function(id) list(schema = "brohn-arm-draw/0.1", policy_hash = policy_hash,
        allocation_index = index, arm_id = id))
      selected_position <- .brohn_vph_rank_01(messages, ids)[[1L]]
    }
    arm <- a$arms[[selected_position]]
  }
  authored <- brohn_ids(d$stimuli)
  grouped <- unlist(lapply(a$sets, function(s) vapply(s$members, `[[`, character(1), "stimulus_id")), use.names = FALSE)
  always <- authored[!authored %in% grouped]
  sets <- lapply(a$sets, function(s) {
    if (identical(s$selection, "all")) ids <- vapply(s$members, `[[`, character(1), "stimulus_id") else {
      choice <- Filter(function(c) identical(c$set_id, s$id), arm$choices)
      brohn_require(length(choice) == 1L, "Saved arm has no unique declared choice.")
      ids <- choice[[1L]]$stimulus_id
    }
    list(set_id = s$id, concept_id = s$concept_id, selection = s$selection, selected_stimulus_ids = as.list(ids))
  })
  chosen <- c(always, unlist(lapply(sets, `[[`, "selected_stimulus_ids"), use.names = FALSE))
  selected <- authored[authored %in% chosen]
  order <- selected
  if (length(order) && identical(d$order, "counterbalanced")) {
    start <- ((p$allocation_index - 1) %% length(order)) + 1L
    order <- c(order, order)[seq.int(start, length.out = length(order))]
  } else if (length(order) && identical(d$order, "randomized")) {
    messages <- lapply(selected, function(id) list(schema = "brohn-selected-order/0.1", policy_hash = policy_hash,
      allocation_index = index, stimulus_id = id))
    order <- selected[.brohn_vph_rank_01(messages, selected)]
  }
  expected <- list(schema = "brohn-run-stimulus-assignment/0.1", policy_hash = policy_hash,
    design_hash = p$design_hash, allocation = a$allocation, allocation_index = index,
    arm_id = if (is.null(arm)) NULL else arm$id,
    block = if (is.null(block)) NULL else .brohn_vph_decimal(block),
    slot = if (is.null(slot)) NULL else .brohn_vph_decimal(slot), sets = sets,
    always_stimulus_ids = as.list(always), selected_stimulus_ids = as.list(selected), realized_stimulus_order = as.list(order))
  .brohn_ph_expect(r, expected, "complete registered0.1 assignment receipt")
  .brohn_ph_expect(p$realized_stimulus_order, expected$realized_stimulus_order, "selected-only realized order")
  order
}

brohn_validate_saved_variant_protocol <- function(protocol) {
  # Core02's original-byte encoding check precedes any historical conversion.
  .brohn_vad_domain(protocol)
  .brohn_ph_domain(protocol)
  brohn_fields(protocol, c("schema_version", "design", "design_hash", "allocation_index", "realized_stimulus_order",
    "timeline", "timing_evidence", "stimulus_assignment"), c("questionnaire_assignments", "questionnaire_occurrences", "equipment"), "Saved variant protocol")
  brohn_require(identical(protocol$schema_version, "brohn-protocol/1.2.0"), "This reader accepts only saved variant protocol1.2.")
  brohn_validate_variant_design(protocol$design, publish = TRUE)
  p <- protocol; d <- p$design
  brohn_require(.brohn_ph_sha(p$design_hash) && brohn_number(p$allocation_index, 1, 1e9, TRUE),
    "Keep the original full1.2 design hash and allocation.")
  .brohn_ph_expect(p$design_hash, .brohn_ph_hash(d), "complete retained1.2 design protocol-json/0.1 binding")
  .brohn_ph_expect(p$timing_evidence, "browser_observation_not_physical_qualification", "timing evidence status")
  sectioned <- "questionnaire_sections" %in% names(d); navigation <- "questionnaire_navigation" %in% names(d)
  for (f in c("questionnaire_assignments", "questionnaire_occurrences", "equipment")) {
    expected <- switch(f, questionnaire_assignments = sectioned, questionnaire_occurrences = navigation,
      equipment = !is.null(d[["participant_equipment", exact = TRUE]]))
    brohn_require(identical(f %in% names(p), expected), paste("Saved optional field presence differs:", f))
    if (expected && f != "equipment") brohn_require(brohn_array(p[[f, exact = TRUE]]), paste("Saved", f, "must be an array."))
  }
  brohn_require(brohn_array(p$timeline) && length(p$timeline) <= 20000L, "Saved timeline exceeds the supported step bound.")
  for (s in p$timeline) brohn_require(is.list(s) && brohn_text(s$type, 64) && brohn_valid_id(s$id), "Saved step has no valid identity/type.")
  brohn_require(!anyDuplicated(brohn_ids(p$timeline)), "Saved timeline repeats a step identity.")
  order <- .brohn_vph_receipt_validated(p)
  .brohn_ph_timeline_validated(protocol, order)
}

brohn_variant_revision_context <- function(protocol, original_protocol_hash) {
  brohn_require(.brohn_ph_sha(original_protocol_hash), "Supply the declared original protocol-byte SHA256.")
  brohn_validate_saved_variant_protocol(protocol)
  brohn_require("questionnaire_navigation" %in% names(protocol$design), "This protocol uses forward-only questionnaire delivery.")
  .brohn_revision_context_maps(protocol, original_protocol_hash, .brohn_ph_hash(protocol$design$questionnaire_navigation))
}
