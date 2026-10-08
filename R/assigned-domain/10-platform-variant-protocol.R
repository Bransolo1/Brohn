# Inactive prospective design1.2 compiler. No saved reader or delivery dispatch.
brohn_compile_variant_design <- function(design, allocation_index = 1L) {
  brohn_validate_variant_design(design, publish = TRUE)
  brohn_require(brohn_number(allocation_index, 1, 1e9, TRUE) && is.null(attributes(allocation_index)),
    "Allocation index must be an exact unclassed integer from 1 to 1,000,000,000.")
  brohn_require(!length(design$blocks) || exists("brohn_task_compile", mode = "function"),
    "Enable the registered task compiler before releasing this design.")
  if (length(design$methods)) {
    brohn_require(exists("brohn_resolve_methods", mode = "function"),
      "Analysis recipe settings need a registered resolver before release.")
    brohn_resolve_methods(design$methods)
  }
  receipt <- .brohn_vas_receipt(design, allocation_index)
  indices <- match(unlist(receipt$realized_stimulus_order, use.names = FALSE), brohn_ids(design$stimuli))
  brohn_require(!anyNA(indices) && !anyDuplicated(indices), "Assigned stimuli must resolve to distinct original design records.")
  protocol <- .brohn_compile_assignment_validated(design, allocation_index, indices,
    receipt$design_hash, "brohn-protocol/1.2.0")
  brohn_require(identical(protocol$realized_stimulus_order, receipt$realized_stimulus_order) &&
    identical(protocol$design_hash, receipt$design_hash), "Complete protocol and assignment receipt disagree.")
  protocol$stimulus_assignment <- receipt
  # Keep the complete original design, receipt, timeline and nested task values.
  # Existing limits are applied to the complete prospective value, not a view.
  brohn_require(nchar(brohn_json(protocol), type = "bytes") <= 16 * 1024^2,
    "The complete variant protocol exceeds the existing 16 MiB source limit.")
  .brohn_store_json(protocol)
  protocol
}

.brohn_revision_decorate_variant_validated <- function(protocol) {
  # Only the private prospective assembly calls this, after complete validation.
  # This schema fence does not authorize historical data or participant events.
  brohn_require(identical(protocol[["schema_version", exact = TRUE]], "brohn-protocol/1.2.0") &&
    identical(protocol[["design", exact = TRUE]][["schema_version", exact = TRUE]], "brohn-design/1.2.0") &&
    identical(protocol[["design_hash", exact = TRUE]], brohn_hash(protocol[["design", exact = TRUE]])),
    "Prospective variant decoration requires the exact complete1.2 design and protocol hash.")
  .brohn_revision_decorate_validated(protocol)
}
