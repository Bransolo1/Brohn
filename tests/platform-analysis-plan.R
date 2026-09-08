source("R/platform-load.R"); brohn_load(ui = FALSE)
source("R/platform-analysis-plan.R")
local({
  count <- 0L
  check <- function(label, value) {if (!isTRUE(value)) stop(label); count <<- count+1L}
  refuses <- function(expr) inherits(tryCatch(force(expr), error = identity), "error")
  design <- brohn_new_design()
  plan <- brohn_new_analysis_plan(); plan$rationale <- "Compare declared liking after each controlled concept."
  plan$comparisons <- list(list(id = "comparison-liking", measure = "questionnaire_numeric", outcome_id = "q-liking", control_id = "condition-a", test_id = "condition-b"))
  design$analysis_plan <- plan
  brohn_validate_analysis_plan(plan, design)
  rows <- list()
  visits <- list(list(person = "P1", session = "V1", delta = 1), list(person = "P1", session = "V2", delta = 3),
    list(person = "P2", session = "V1", delta = 1), list(person = "P3", session = "V1", delta = NULL))
  for (visit in visits) for (condition in c("condition-a", "condition-b")) rows[[length(rows)+1L]] <- list(participant_id = visit$person,
    session_id = visit$session, condition_id = condition, question_id = "q-liking", value = if (condition == "condition-a") 3 else if (is.null(visit$delta)) NULL else 3+visit$delta,
    missing_reason = if (condition == "condition-b" && is.null(visit$delta)) "optional_omission" else NULL)
  analysis <- list(kind = "questionnaire", observations = rows, contrasts = list(), parameters = list(), limitations = list())
  result <- brohn_analysis_plan_result(analysis, design); comparison <- result$contrasts[[1L]]
  check("equal-person comparison keeps repeated visits inside person", identical(comparison$estimate, 1.5) && comparison$participant_count == 2 && comparison$paired_session_count == 3)
  check("missing paired response is excluded without a zero replacement", comparison$excluded_session_count == 1 && length(result$observations) == 8)
  check("one-hypothesis p-value independently matches t=3 with one df", abs(comparison$p_value-2*stats::pt(-3,1)) < 1e-14 && comparison$p_adjusted == comparison$p_value)
  check("saved plan hash binds declared outcome and rationale", identical(result$parameters$analysis_plan$hash, brohn_hash(plan)))
  no_plan <- design; no_plan$analysis_plan <- NULL
  check("older design without plan retains its exact analysis", identical(brohn_analysis_plan_result(analysis, no_plan), analysis))
  descriptive <- design; descriptive$analysis_plan$comparisons <- list()
  check("explicit descriptive plan suppresses undeclared tests, retains observations", length(brohn_analysis_plan_result(analysis, descriptive)$contrasts) == 0 && identical(brohn_analysis_plan_result(analysis, descriptive)$observations, rows))
  unknown <- brohn_analysis_plan_result(analysis, design, identity_verified = FALSE)
  check("unverified participant IDs cannot generate planned inference", unknown$contrasts[[1]]$reason == "participant_identity_not_established" && is.null(unknown$contrasts[[1]]$estimate))
  flat <- analysis
  for (i in seq_along(flat$observations)) if (!is.null(flat$observations[[i]]$value)) flat$observations[[i]]$value <- if (flat$observations[[i]]$condition_id == "condition-a") 3 else 4
  flat_result <- brohn_analysis_plan_result(flat, design)$contrasts[[1]]
  check("constant observed difference retains estimate with unavailable uncertainty", flat_result$estimate == 1 && is.null(flat_result$interval95) && is.null(flat_result$p_value) && flat_result$reason == "zero_or_negligible_between_person_variance")
  for (i in 1:2) design$stimuli[[i]]$aois <- list(list(id = paste0("area-", i), label = "Brand", x = .2, y = .2, width = .2, height = .2))
  design$analysis_plan$comparisons[[2]] <- list(id = "comparison-brand", measure = "gaze_valid_share", outcome_id = "Brand", control_id = "condition-a", test_id = "condition-b")
  mixed <- brohn_analysis_plan_result(analysis, design)
  check("absent modality remains in planned family and uses conservative bound", length(mixed$contrasts) == 1 && mixed$contrasts[[1]]$multiplicity$family_size == 2 &&
    mixed$contrasts[[1]]$multiplicity$method == "bonferroni_incomplete_family" && abs(mixed$contrasts[[1]]$p_adjusted-min(1,2*comparison$p_value)) < 1e-14)
  bad <- plan; bad$comparisons <- c(bad$comparisons, bad$comparisons); bad$comparisons[[2]]$id <- "comparison-duplicate"
  check("duplicate scientific hypothesis cannot inflate family", refuses(brohn_validate_analysis_plan(bad, design)))
  bad <- plan; bad$comparisons[[1]]$control_id <- "missing"
  check("missing reference condition rejected", refuses(brohn_validate_analysis_plan(bad, design)))
  bad <- plan; bad$comparisons[[1]]$measure <- "invented-emotion-score"
  check("unregistered recipe cannot execute", refuses(brohn_validate_analysis_plan(bad, design)))
  bad_design <- design; bad_design$questions[[1]]$scope <- "end"
  check("whole-study liking cannot become per-stimulus contrast", refuses(brohn_validate_analysis_plan(plan, bad_design)))
  bad <- plan; bad$execute <- "system('command')"
  check("uploaded executable settings are outside declarative contract", refuses(brohn_validate_analysis_plan(bad, design)))
  cloned <- brohn_clone_analysis_plan(plan, c("condition-a" = "new-control", "condition-b" = "new-test"), c("q-liking" = "new-question"))
  check("clone remaps conditions/question and comparison identity", cloned$comparisons[[1]]$control_id == "new-control" && cloned$comparisons[[1]]$outcome_id == "new-question" && cloned$comparisons[[1]]$id != "comparison-liking")
  cat(sprintf("PASS: %d declarative analysis-plan checks\n", count))
})
