# Adapt complete saved assessment scores to the declared paired comparison
# family. This adapter performs no additional item scoring or reliability model.
brohn_scale_plan_definition <- function(design, scale_id) {
  brohn_validate_scales(brohn_default(design$scales, list()), design)
  scale <- brohn_find(design$scales, scale_id)
  brohn_require(!is.null(scale) && identical(scale$scope, "after_each"),
    "A condition comparison needs a saved scale administered after each stimulus.")
  scale
}
brohn_scale_comparison_source <- function(analysis, design, spec) {
  scale <- brohn_scale_plan_definition(design, spec$outcome_id)
  result <- analysis$scales
  output <- list(observations = list(), label = scale$label,
    unit = if (is.null(scale$conversion)) "scale points" else "converted scale points",
    participant_linkage = FALSE, reason = "scale_results_not_available", evidence = NULL)
  if (is.null(result)) return(output)
  brohn_require(identical(result$schema, "brohn-questionnaire-scale-results/1.0") &&
    identical(result$provenance$design_hash, brohn_hash(design)) &&
    identical(result$provenance$scales_hash, brohn_hash(design$scales)) &&
    identical(brohn_hash(result$provenance$scales), brohn_hash(design$scales)),
    "Scale comparisons require the exact saved design and scoring keys.")
  brohn_require(brohn_array(result$observations), "Scale results need explicit assessment records.")
  all_rows <- Filter(function(r) identical(r$scale_id, scale$id), result$observations)
  brohn_require(all(vapply(all_rows, function(r) identical(r$scale_hash, brohn_hash(scale)) &&
    identical(r$scope, "after_each") && identical(r$unit, output$unit), logical(1))),
    "A scale assessment has a different key, placement or score unit.")
  brohn_require(!anyDuplicated(vapply(all_rows, function(r) brohn_json(list(r$participant_id, r$session_id, r$assessment_id)), character(1))),
    "Duplicate assessment scores cannot enter a condition comparison.")
  selected <- Filter(function(r) isTRUE(r$condition_id %in% c(spec$control_id, spec$test_id)), all_rows)
  origins <- unique(vapply(selected, function(r) brohn_default(r$origin, ""), character(1)))
  brohn_require(length(origins) <= 1L, "Scale comparisons must keep distinct recording origins separate.")
  supported <- vapply(selected, function(r) identical(r$status, "scored") && is.null(r$missing_reason) && brohn_number(r$value), logical(1))
  output$observations <- selected
  output$participant_linkage <- all(vapply(selected, function(r) isTRUE(r$participant_linkage), logical(1)))
  output$reason <- if (!length(selected)) "no_supported_observations" else if (!output$participant_linkage) "participant_identity_not_established" else NULL
  output$evidence <- list(recipe = "paired-assessment-scale-comparison/1.0", scale_id = scale$id,
    scale_hash = brohn_hash(scale), scales_hash = result$provenance$scales_hash,
    responses_hash = result$provenance$responses_hash, score_records_hash = brohn_hash(selected),
    source = result$provenance$source, scale_assessment_count = length(all_rows),
    comparison_assessment_count = length(selected), scored_assessment_count = sum(supported),
    unavailable_assessment_count = sum(!supported), other_condition_assessment_count = length(all_rows)-length(selected))
  output
}
