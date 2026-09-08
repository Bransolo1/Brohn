# A control designation is researcher-authored study intent, not causal evidence.
validate_comparison <- function(study) {
  tryCatch({
    if (!is.list(study)) return("comparison: study list required")
    if (!"comparison" %in% names(study)) return(character())
    if (sum(names(study) == "comparison", na.rm = TRUE) != 1L)
      return("comparison: duplicate field")
    value <- study[["comparison", exact = TRUE]]
    fields <- c("control_condition", "rationale")
    if (!is.list(value) || is.null(names(value)) || anyNA(names(value)) ||
        anyDuplicated(names(value)) || !setequal(names(value), fields))
      return("comparison: exactly control_condition and rationale fields required")
    errors <- character()
    condition <- value$control_condition
    if (!is.character(condition) || length(condition) != 1L || is.na(condition) ||
        !condition %in% c("none", "A", "B"))
      errors <- c(errors, "comparison.control_condition: choose none, A or B")
    rationale <- value$rationale
    if (!is.character(rationale) || length(rationale) != 1L || is.na(rationale) ||
        nchar(rationale, type = "chars") > 2000L)
      errors <- c(errors, "comparison.rationale: text of at most 2000 characters required")
    errors
  }, error = function(e) paste("comparison:", conditionMessage(e)))
}

comparison_settings <- function(study) {
  errors <- validate_comparison(study)
  if (length(errors)) stop(paste(errors, collapse = "; "), call. = FALSE)
  if (!"comparison" %in% names(study))
    return(list(control_condition = "none", rationale = ""))
  list(control_condition = unname(study$comparison$control_condition),
       rationale = unname(study$comparison$rationale))
}

revise_comparison <- function(bundle, control_condition, rationale = "") {
  record_assert(!length(validate_bundle(bundle)), "Open a valid draft first.")
  old <- comparison_settings(bundle$study)
  record_assert(!length(bundle$events) && !length(bundle$streams) && !length(bundle$clocks),
                "This bundle contains recording metadata. Create a new study to change its control.")
  record_assert(bundle$session$mode %in% c("sample", "preview"),
                "Only sample and preview drafts can be edited here.")
  record_assert(is.character(rationale) && length(rationale) == 1L && !is.na(rationale),
                "comparison.rationale: text of at most 2000 characters required")
  proposed <- list(control_condition = control_condition, rationale = trimws(rationale))
  errors <- validate_comparison(list(comparison = proposed))
  record_assert(!length(errors), paste(errors, collapse = "; "))
  proposed <- comparison_settings(list(comparison = proposed))
  if (identical(old, proposed)) return(bundle)
  bundle$study$comparison <- proposed
  bundle$study$revision <- bundle$study$revision + 1
  bundle$session$study_revision <- bundle$study$revision
  errors <- validate_bundle(bundle)
  record_assert(!length(errors), paste(errors, collapse = "; "))
  bundle
}

comparison_caption <- function(study) {
  condition <- comparison_settings(study)$control_condition
  direction <- switch(condition,
    A = "B minus A means test minus control (B is test; A is control).",
    B = "B minus A means control minus test (B is control; A is test).",
    none = "B minus A compares design B with design A; no designated control.")
  paste(direction, "A control designation records the researcher's intent and does not establish causality.")
}
