# Frozen pre-optimization implementation from the published Brohn scorer.
# This differential oracle deliberately retains its repeated grouping calls.
# Independent closed-form arithmetic is tested separately in the test runner.
paired_aggregation_reference <- function(rows, conditions) {
  if (!nrow(rows) || !length(conditions)) return(list())
  controls <- Filter(function(c) c$role == "control", conditions)
  if (length(controls) != 1L) return(list())
  control <- controls[[1]]; tests <- Filter(function(c) c$role == "test", conditions)
  outputs <- list()
  for (metric_idx in brohn_group(rows, c("metric", "outcome_id", "unit"))) {
    values <- rows[metric_idx, , drop = FALSE]
    for (test in tests) {
      differences <- list()
      for (group in brohn_group(values, c("participant_id", "session_id"))) {
        session <- values[group, , drop = FALSE]
        a <- session$value[session$condition_id == control$id & is.finite(session$value)]
        b <- session$value[session$condition_id == test$id & is.finite(session$value)]
        if (length(a) && length(b)) differences[[length(differences)+1L]] <- data.frame(
          participant_id = session$participant_id[1], session_id = session$session_id[1], value = mean(b)-mean(a), stringsAsFactors = FALSE)
      }
      delta <- if (length(differences)) do.call(rbind, differences) else data.frame(participant_id=character(), session_id=character(), value=numeric())
      person <- vapply(brohn_group(delta, "participant_id"), function(ix) mean(delta$value[ix]), numeric(1))
      n <- length(person); estimate <- if (n) mean(person) else NA_real_
      se <- if (n >= 2) stats::sd(person)/sqrt(n) else NA_real_
      margin <- if (n >= 2) stats::qt(.975, df = n-1)*se else NA_real_
      outputs[[length(outputs)+1L]] <- list(metric = values$metric[1], outcome_id = values$outcome_id[1],
        unit = values$unit[1], control_id = control$id, control_label = control$label,
        test_id = test$id, test_label = test$label, estimate = brohn_nullable(estimate),
        participant_count = n, paired_session_count = nrow(delta),
        excluded_session_count = length(brohn_group(values, c("participant_id", "session_id")))-nrow(delta),
        interval95 = if (n >= 2) list(lower = estimate-margin, upper = estimate+margin,
          method = "Student t interval of equal-person paired differences", df = n-1L) else NULL,
        aggregation = "Equal exposure means per condition within session; paired session differences averaged within person; equal weight per person.",
        participant_differences = lapply(seq_along(person), function(i) list(participant_id = delta$participant_id[brohn_group(delta, "participant_id")[[i]][1]], value = unname(person[i]))))
    }
  }
  outputs
}
