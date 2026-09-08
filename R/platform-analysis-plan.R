# Declarative consumer-study comparisons. A design plan contains no dataset,
# participant, provider credential or executable R/Python expression.
brohn_analysis_plan_metrics <- function() list(
  list(id = "gaze_valid_share", modality = "gaze", metric = "valid_gaze_share", field = "valid_share_percent", unit = "percentage points", label = "Share of valid gaze time in an AOI"),
  list(id = "gaze_fixation_dwell", modality = "gaze", metric = "fixation_dwell", field = "fixation_dwell_ms", unit = "ms", label = "Fixation candidate dwell in an AOI"),
  list(id = "questionnaire_numeric", modality = "questionnaire", metric = "explicit_response", field = "value", unit = "response units", label = "Numeric questionnaire response"),
  list(id = "questionnaire_scale", modality = "questionnaire", metric = "assessment_scale_score", field = "value", unit = "scale points", label = "Questionnaire scale score"))
brohn_new_analysis_plan <- function() list(schema = "brohn-analysis-plan/1.0", recipe = "paired-consumer-comparisons/1.0-draft",
  rationale = "", comparisons = list(), multiplicity = list(method = "holm", alpha = .05))
brohn_validate_analysis_plan <- function(plan, design) {
  if (is.null(plan)) return(invisible(TRUE))
  brohn_fields(plan, c("schema", "recipe", "rationale", "comparisons", "multiplicity"), label = "Analysis plan")
  brohn_require(identical(plan$schema, "brohn-analysis-plan/1.0") && identical(plan$recipe, "paired-consumer-comparisons/1.0-draft"), "This analysis plan needs a registered recipe.")
  brohn_require(brohn_text(plan$rationale, 4000), "Explain the research question and why these comparisons answer it.")
  brohn_require(brohn_array(plan$comparisons) && length(plan$comparisons) <= 100, "Declare at most 100 comparisons, or choose a descriptive report.")
  ids <- character(); fingerprints <- character()
  for (comparison in plan$comparisons) {
    brohn_fields(comparison, c("id", "measure", "outcome_id", "control_id", "test_id"), label = "Planned comparison")
    brohn_require(brohn_valid_id(comparison$id) && brohn_text(comparison$outcome_id, 500), "Every comparison needs an identity and an outcome.")
    measure <- brohn_find(brohn_analysis_plan_metrics(), comparison$measure)
    brohn_require(!is.null(measure), "This measure has no registered comparison recipe.")
    brohn_require(all(c(comparison$control_id, comparison$test_id) %in% brohn_ids(design$conditions)) &&
      !identical(comparison$control_id, comparison$test_id), "Choose two different study conditions for each planned comparison.")
    if (identical(comparison$measure, "questionnaire_scale")) {
      brohn_require(exists("brohn_scale_plan_definition", mode = "function"), "Scale comparisons require the registered assessment comparison adapter.")
      brohn_scale_plan_definition(design, comparison$outcome_id)
    } else if (measure$modality == "questionnaire") {
      question <- brohn_find(design$questions, comparison$outcome_id)
      brohn_require(!is.null(question) && question$type %in% c("rating", "slider", "number") && question$scope == "after_each", "Paired questionnaire plans need a rating, slider or number question after each stimulus.")
      if (question$type == "rating") brohn_require(all(vapply(question$options, function(o) brohn_number(o$value), logical(1))), "A numeric questionnaire contrast needs numeric scale codes.")
    } else {
      aois <- unlist(lapply(design$stimuli, function(s) if (s$condition_id %in% c(comparison$control_id, comparison$test_id))
        lapply(s$aois, function(a) list(condition_id = s$condition_id, label = a$label)) else list()), recursive = FALSE)
      matched <- Filter(function(a) identical(a$label, comparison$outcome_id), aois)
      brohn_require(all(c(comparison$control_id, comparison$test_id) %in% vapply(matched, `[[`, character(1), "condition_id")), "The planned AOI label must occur in both selected conditions.")
    }
    ids <- c(ids, comparison$id); fingerprints <- c(fingerprints, brohn_hash(comparison[setdiff(names(comparison), "id")]))
  }
  brohn_require(!anyDuplicated(ids) && !anyDuplicated(fingerprints), "Planned comparison identities and hypotheses must be distinct.")
  brohn_fields(plan$multiplicity, c("method", "alpha"), label = "Planned multiplicity")
  brohn_require(identical(plan$multiplicity$method, "holm") && brohn_number(plan$multiplicity$alpha, .0001, .2), "Choose a Holm family error threshold between 0.0001 and 0.2.")
  invisible(TRUE)
}
brohn_clone_analysis_plan <- function(plan, condition_map, question_map, scale_map = character()) {
  if (is.null(plan)) return(NULL)
  plan$comparisons <- lapply(plan$comparisons, function(c) {
    c$id <- brohn_id("comparison"); c$control_id <- unname(condition_map[[c$control_id]]); c$test_id <- unname(condition_map[[c$test_id]])
    if (c$measure == "questionnaire_numeric") c$outcome_id <- unname(question_map[[c$outcome_id]])
    if (c$measure == "questionnaire_scale") {
      brohn_require(c$outcome_id %in% names(scale_map), "Cloning a scale comparison requires its scale identity mapping.")
      c$outcome_id <- unname(scale_map[[c$outcome_id]])
    }
    c
  })
  plan
}
brohn_analysis_plan_result <- function(analysis, design, identity_verified = TRUE, timing_evidence = "source_collection_timing_not_established") {
  plan <- design$analysis_plan
  if (is.null(plan)) return(analysis)
  brohn_validate_analysis_plan(plan, design)
  family <- length(plan$comparisons)
  applicable <- Filter(function(c) identical(brohn_find(brohn_analysis_plan_metrics(), c$measure)$modality, analysis$kind), plan$comparisons)
  contrasts <- lapply(applicable, function(spec) {
    measure <- brohn_find(brohn_analysis_plan_metrics(), spec$measure)
    reference <- brohn_find(design$conditions, spec$control_id); reference$role <- "control"
    test <- brohn_find(design$conditions, spec$test_id); test$role <- "test"
    scale <- identical(spec$measure, "questionnaire_scale")
    adapted <- if (scale) brohn_scale_comparison_source(analysis, design, spec) else NULL
    source <- if (scale) adapted$observations else Filter(function(r) identical(if (analysis$kind == "gaze") r$aoi_label else r$question_id, spec$outcome_id) &&
      isTRUE(r$condition_id %in% c(spec$control_id, spec$test_id)), analysis$observations)
    unit <- measure$unit; label <- spec$outcome_id
    if (scale) {unit <- adapted$unit; label <- adapted$label} else if (analysis$kind == "questionnaire") {
      q <- brohn_find(design$questions, spec$outcome_id); label <- q$prompt
      if (q$type == "rating") unit <- "rating points"
    }
    base <- list(id = spec$id, metric = measure$metric, outcome_id = spec$outcome_id, outcome_label = label,
      unit = unit, control_id = reference$id, control_label = reference$label, test_id = test$id, test_label = test$label,
      estimate = NULL, participant_count = 0L, paired_session_count = 0L, excluded_session_count = 0L,
      interval95 = NULL, p_value = NULL, p_adjusted = NULL, status = "unavailable", reason = "no_supported_observations",
      aggregation = "Equal exposure means per condition/session; equal paired sessions within person; equal people.")
    if (scale) {
      base$scale_source <- adapted$evidence
      base$aggregation <- "Equal eligible assessment means per condition within session; paired session differences averaged within person; equal weight per person."
      if (!is.null(adapted$reason)) {base$reason <- adapted$reason; return(base)}
    }
    if (!identity_verified) {base$reason <- "participant_identity_not_established"; return(base)}
    if (!length(source)) return(base)
    brohn_require(all(vapply(source, function(r) brohn_text(r$participant_id, 500) && brohn_text(r$session_id, 500), logical(1))), "A planned comparison requires actual source person/session identities.")
    values <- do.call(rbind, lapply(source, function(r) data.frame(participant_id = r$participant_id, session_id = r$session_id,
      condition_id = r$condition_id, metric = measure$metric, outcome_id = spec$outcome_id, unit = unit,
      value = if (brohn_number(r[[measure$field]]) && (analysis$kind != "questionnaire" || is.null(r$missing_reason)) &&
        (!scale || identical(r$status, "scored"))) r[[measure$field]] else NA_real_, stringsAsFactors = FALSE)))
    contrast <- brohn_paired_contrasts(values, list(reference, test))[[1L]]
    base[names(contrast)] <- contrast; base$id <- spec$id; base$outcome_label <- label
    if (scale) base$aggregation <- "Equal eligible assessment means per condition within session; paired session differences averaged within person; equal weight per person."
    # Reconstruct inference from independently defined person differences. A
    # zero observed SD does not justify a zero-width uncertainty claim.
    base$interval95 <- NULL
    if (is.null(base$estimate)) return(base)
    base$status <- "descriptive"; base$reason <- "at_least_two_people_needed_for_inference"
    differences <- vapply(base$participant_differences, `[[`, numeric(1), "value")
    if (length(differences) < 2L) return(base)
    sd <- stats::sd(differences)
    if (!is.finite(sd) || sd <= .Machine$double.eps*max(1, max(abs(differences)))) {base$reason <- "zero_or_negligible_between_person_variance"; return(base)}
    se <- sd/sqrt(length(differences)); df <- length(differences)-1L; margin <- stats::qt(.975, df)*se
    base$interval95 <- list(lower = base$estimate-margin, upper = base$estimate+margin, df = df, method = "Unadjusted Student t interval of equal-person differences")
    base$p_value <- 2*stats::pt(-abs(base$estimate/se), df); base$status <- "estimated"; base$reason <- NULL
    base
  })
  # A report may contain one modality of a multi-modality declared family.
  # Bonferroni is conservative with unknown other p-values; applying Holm to
  # a subset would misrepresent an unavailable joint ordering. Full Holm is
  # available only when every planned hypothesis belongs to this saved report.
  available <- which(vapply(contrasts, function(c) brohn_number(c$p_value, 0, 1), logical(1)))
  correction <- if (length(applicable) == family) "holm" else "bonferroni_incomplete_family"
  if (length(available)) {
    p <- vapply(contrasts[available], `[[`, numeric(1), "p_value")
    adjusted <- if (correction == "holm") stats::p.adjust(p, "holm", n = family) else pmin(1, p*family)
    for (i in seq_along(available)) {
      index <- available[[i]]; contrasts[[index]]$p_adjusted <- adjusted[[i]]
      contrasts[[index]]$rejects_null <- adjusted[[i]] <= plan$multiplicity$alpha
    }
  }
  for (i in seq_along(contrasts)) contrasts[[i]]$multiplicity <- list(method = correction, family_size = family,
    available_tests = length(available), alpha = plan$multiplicity$alpha)
  analysis$contrasts <- contrasts
  analysis$parameters$analysis_plan <- list(plan = plan, hash = brohn_hash(plan), timing_evidence = timing_evidence,
    correction = correction, hypotheses_in_report = length(applicable), declared_family_size = family)
  analysis$limitations <- c(analysis$limitations, list("The saved design declares the tested comparison family. This is not external preregistration or evidence of a confirmatory study.",
    "When other planned modalities are absent, the report uses conservative Bonferroni bounds for the full family. A complete combined analysis can apply Holm to its declared family.",
    "Unavailable planned observations remain unavailable. Missing and hidden responses are not zero; source rows and repeat visits are not independent people."))
  analysis
}
