# Draft planning only: no allocation, display runner, timing or acquisition.
validate_presentation <- function(study) {
  tryCatch({
    if (!is.list(study)) return("presentation: study list required")
    if (!"presentation" %in% names(study)) return(character())
    if (sum(names(study) == "presentation", na.rm = TRUE) != 1L)
      return("presentation: duplicate field")
    value <- study[["presentation", exact = TRUE]]
    fields <- c("order", "viewing_duration_ms")
    if (!is.list(value) || is.null(names(value)) || anyNA(names(value)) ||
        anyDuplicated(names(value)) || !setequal(names(value), fields))
      return("presentation: exactly order and viewing_duration_ms fields required")
    errors <- character()
    order <- value$order
    if (!is.character(order) || length(order) != 1L || is.na(order) ||
        !is.null(dim(order)) ||
        !order %in% c("counterbalanced_ab_ba", "fixed_ab", "fixed_ba"))
      errors <- c(errors, "presentation.order: choose counterbalanced_ab_ba, fixed_ab or fixed_ba")
    duration <- value$viewing_duration_ms
    if (!is.numeric(duration) || length(duration) != 1L || is.na(duration) ||
        !is.null(dim(duration)) || !is.finite(duration) ||
        duration < 500 || duration > 600000 || duration != floor(duration))
      errors <- c(errors, "presentation.viewing_duration_ms: integer from 500 to 600000 required")
    errors
  }, error = function(e) paste("presentation:", conditionMessage(e)))
}

presentation_settings <- function(study) {
  errors <- validate_presentation(study)
  if (length(errors)) stop(paste(errors, collapse = "; "), call. = FALSE)
  # This editable starting preset is not a scientific recommendation.
  if (!"presentation" %in% names(study))
    return(list(order = "counterbalanced_ab_ba", viewing_duration_ms = 5000))
  list(order = unname(study$presentation$order),
       viewing_duration_ms = as.numeric(study$presentation$viewing_duration_ms))
}

revise_presentation <- function(bundle, order, viewing_duration_ms) {
  record_assert(!length(validate_bundle(bundle)), "Open a valid draft first.")
  old <- presentation_settings(bundle$study)
  record_assert(!length(bundle$events) && !length(bundle$streams) && !length(bundle$clocks),
                "This bundle contains recording metadata. Create a new study to change its presentation.")
  record_assert(bundle$session$mode %in% c("sample", "preview"),
                "Only sample and preview drafts can be edited here.")
  proposed <- list(order = order, viewing_duration_ms = viewing_duration_ms)
  errors <- validate_presentation(list(presentation = proposed))
  record_assert(!length(errors), paste(errors, collapse = "; "))
  proposed <- presentation_settings(list(presentation = proposed))
  if (identical(old, proposed)) return(bundle)
  bundle$study$presentation <- proposed
  bundle$study$revision <- bundle$study$revision + 1
  bundle$session$study_revision <- bundle$study$revision
  errors <- validate_bundle(bundle)
  record_assert(!length(errors), paste(errors, collapse = "; "))
  bundle
}

preview_presentation <- function(study) {
  errors <- validate_study(study)
  if (length(errors)) stop(paste(errors, collapse = "; "), call. = FALSE)
  settings <- presentation_settings(study)
  control <- comparison_settings(study)$control_condition
  orders <- switch(settings$order, counterbalanced_ab_ba = c("AB", "BA"),
                   fixed_ab = "AB", fixed_ba = "BA")
  plans <- lapply(orders, function(order) {
    conditions <- strsplit(order, "", fixed = TRUE)[[1L]]
    phases <- c("passive_viewing", if (length(study$questions)) "active_response")
    condition <- rep(conditions, each = length(phases))
    phase <- rep(phases, times = length(conditions))
    role <- if (control == "none") rep("comparison", length(condition)) else
      ifelse(condition == control, "control", "test")
    data.frame(position = seq_along(condition),
      stimulus_id = study$stimulus_ids[match(condition, study$conditions)],
      condition = condition, role = role, phase = phase,
      planned_duration_ms = ifelse(phase == "passive_viewing",
                                   settings$viewing_duration_ms, NA_real_),
      stringsAsFactors = FALSE)
  })
  setNames(plans, orders)
}
