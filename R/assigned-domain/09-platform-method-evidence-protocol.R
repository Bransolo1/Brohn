# Inactive prospective compiler only. No historical protocol/source admission.
brohn_compile_evidence_design <- function(design, allocation_index = 1L) {
  brohn_validate_evidence_design(design, publish = TRUE)
  .brohn_compile_after_design_validation(design, allocation_index, "brohn-protocol/1.1.0")
}

# Called only by shared compilation after full evidence-design validation and
# assignment with that complete design's hash. Never use as a history validator.
.brohn_revision_decorate_evidence_validated <- function(protocol) {
  brohn_require(identical(protocol[["schema_version", exact = TRUE]], "brohn-protocol/1.1.0") &&
    identical(protocol[["design", exact = TRUE]][["schema_version", exact = TRUE]], "brohn-design/1.1.0"),
    "Prospective evidence decoration requires the complete1.1 design and protocol.")
  .brohn_revision_decorate_validated(protocol)
}
