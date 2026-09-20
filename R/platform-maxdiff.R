# Original object-case paired best-worst construction and likelihood.
# Method/source notes: docs/methods/MAXDIFF.md. No licensed item text is embedded.
brohn_maxdiff_new <- function(title = "Sample best-worst exercise", id = brohn_id("maxdiff")) {
  items <- lapply(1:4, function(i) list(id = paste0("item-", i), label = paste("Original example feature", i)))
  list(schema = "brohn-maxdiff-design/1.0", id = id, title = title, profile = "object-case-paired-maxdiff/1.0", origin = "synthetic",
    materials_rights = "Original synthetic example labels. Replace with reviewed research materials.", items = items,
    sets = lapply(1:4, function(i) list(id = paste0("set-", i), item_ids = as.list(brohn_ids(items)[-i]))), seed = 104729L,
    settings = list(prompt = "For this original example, which feature would matter most and least to you?", best_label = "Most important", worst_label = "Least important", required = TRUE,
      set_order = "seeded", item_order = "seeded", design_rationale = "Original complete four-item/triple-set example; review its burden and coverage for the intended study.",
      analysis = list(fit_aggregate = TRUE)))
}
.brohn_md_reach <- function(adjacency) {
  reach <- adjacency; diag(reach) <- TRUE
  for (k in seq_len(nrow(reach))) reach <- reach | outer(reach[, k], reach[k, ], `&`)
  reach
}
brohn_maxdiff_validate <- function(design) {
  brohn_fields(design, c("schema", "id", "title", "profile", "origin", "materials_rights", "items", "sets", "seed", "settings"), label = "MaxDiff design")
  brohn_require(identical(design$schema, "brohn-maxdiff-design/1.0") && identical(design$profile, "object-case-paired-maxdiff/1.0") &&
    brohn_valid_id(design$id) && brohn_text(design$title, 240), "Choose a supported object-case MaxDiff design identity/profile.")
  brohn_require(design$origin %in% c("synthetic", "researcher_supplied") && brohn_text(design$materials_rights, 4000), "Declare original item provenance and material rights.")
  brohn_require(brohn_array(design$items) && length(design$items) >= 3L && length(design$items) <= 60L, "MaxDiff requires 3 to 60 explicitly named items.")
  for (item in design$items) {brohn_fields(item, c("id", "label"), optional="illustration", label = "MaxDiff item")
    if("illustration" %in% names(item)) {brohn_require(exists("brohn_validate_illustration",mode="function"),"This exercise requires its illustration validator.");brohn_validate_illustration(item$illustration)}
    brohn_require(brohn_valid_id(item$id) && brohn_text(item$label, 1000), "An item needs a stable identity and nonempty label.")}
  ids <- brohn_ids(design$items); brohn_require(!anyDuplicated(ids), "MaxDiff item identities must be unique.")
  brohn_require(brohn_array(design$sets) && length(design$sets) >= 1L && length(design$sets) <= 200L, "Declare 1 to 200 original choice sets.")
  for (set in design$sets) {brohn_fields(set, c("id", "item_ids"), label = "MaxDiff set")
    brohn_require(brohn_valid_id(set$id) && brohn_array(set$item_ids) && length(set$item_ids) >= 3L && length(set$item_ids) <= 8L &&
      all(vapply(set$item_ids, brohn_text, logical(1), max = 96)) && all(unlist(set$item_ids) %in% ids) && !anyDuplicated(unlist(set$item_ids)),
      "Each MaxDiff set needs 3 to 8 distinct existing item IDs in an explicit order.")}
  brohn_require(!anyDuplicated(brohn_ids(design$sets)), "Choice set identities must be unique.")
  brohn_require(brohn_number(design$seed, 1, .Machine$integer.max, TRUE), "The allocation seed must be a positive whole integer.")
  s <- design$settings; brohn_fields(s, c("prompt", "best_label", "worst_label", "required", "set_order", "item_order", "design_rationale", "analysis"), label = "MaxDiff settings")
  brohn_require(brohn_text(s$prompt, 4000) && brohn_text(s$best_label, 100) && brohn_text(s$worst_label, 100) &&
    !identical(s$best_label, s$worst_label) && is.logical(s$required) && length(s$required) == 1L && !is.na(s$required),
    "Declare the question, distinct best/worst labels and whether an answer is required; these define the research framing.")
  brohn_require(s$set_order %in% c("fixed", "seeded") && s$item_order %in% c("fixed", "seeded") && brohn_text(s$design_rationale, 4000), "Declare set/item ordering and a design rationale.")
  brohn_fields(s$analysis, "fit_aggregate", label = "MaxDiff analysis")
  brohn_require(is.logical(s$analysis$fit_aggregate) && length(s$analysis$fit_aggregate) == 1L && !is.na(s$analysis$fit_aggregate), "Aggregate fitting must be explicitly enabled or disabled.")
  invisible(design)
}
brohn_maxdiff_design_review <- function(design) {
  brohn_maxdiff_validate(design); ids <- brohn_ids(design$items); n <- length(ids)
  exposure <- integer(n); pairs <- matrix(0L, n, n); positions <- matrix(0L, n, 8L)
  for (set in design$sets) {indices <- match(unlist(set$item_ids), ids); exposure[indices] <- exposure[indices]+1L
    pairs[indices, indices] <- pairs[indices, indices]+1L
    for (j in seq_along(indices)) positions[indices[[j]], j] <- positions[indices[[j]], j]+1L}
  diag(pairs) <- 0L; connected <- all(.brohn_md_reach(pairs > 0L)); sizes <- lengths(lapply(design$sets, `[[`, "item_ids"))
  positive_pairs <- pairs[upper.tri(pairs)]; duplicate_sets <- duplicated(vapply(design$sets, function(s) brohn_json(sort(unlist(s$item_ids))), character(1)))
  warnings <- character()
  if (any(exposure == 0L)) warnings <- c(warnings, "Some declared items are never offered.")
  if (!connected) warnings <- c(warnings, "The overall design is disconnected; one common relative utility scale is not identifiable.")
  if (length(unique(exposure)) > 1L) warnings <- c(warnings, "Item presentation counts differ; review exposure-adjusted counts and design precision.")
  if (length(unique(positive_pairs)) > 1L) warnings <- c(warnings, "Pair co-occurrence is not balanced; no balanced or optimal-design claim is made.")
  if (any(sizes > 5L)) warnings <- c(warnings, "Some sets contain more than five items; review comprehension and response burden.")
  if (any(sizes > n/2)) warnings <- c(warnings, "Some sets contain more than half the item universe; review middle-preference discrimination.")
  if (any(duplicate_sets)) warnings <- c(warnings, "Repeated item combinations are retained as separate named sets; review the intended replication.")
  if (design$settings$item_order == "fixed") warnings <- c(warnings, "Fixed item positions can confound position and item preference; position counts are descriptive, not a bias correction.")
  list(schema = "brohn-maxdiff-design-review/1.0", design_hash = brohn_hash(design), connected = connected,
    all_items_present = all(exposure > 0L), item_count = n, set_count = length(design$sets), set_sizes = as.list(sizes),
    item_coverage = lapply(seq_along(ids), function(i) list(item_id = ids[[i]], presentations = exposure[[i]], positions = as.list(positions[i, ]))),
    pair_coverage = unlist(lapply(seq_len(n-1L), function(i) lapply(seq.int(i+1L, n), function(j) list(first_id = ids[[i]], second_id = ids[[j]], cooccurrences = pairs[i, j]))), recursive = FALSE),
    equal_item_frequency = length(unique(exposure)) == 1L, equal_pair_frequency = length(unique(positive_pairs)) == 1L,
    declared_positions_only = TRUE, optimality_qualified = FALSE, warnings = as.list(warnings))
}
brohn_maxdiff_compile <- function(design, allocation_index = 1L) {
  review <- brohn_maxdiff_design_review(design)
  brohn_require(review$connected && review$all_items_present, "Review missing items or disconnected choice sets before serving this exercise.")
  brohn_require(brohn_number(allocation_index, 1, 1e9, TRUE), "Declare a positive whole allocation index.")
  trials <- brohn_seeded(((design$seed+allocation_index-2)%%(.Machine$integer.max-1))+1, function() {
    sets <- design$sets; if (design$settings$set_order == "seeded") sets <- sets[sample.int(length(sets))]
    lapply(seq_along(sets), function(i) {s <- sets[[i]]; order <- s$item_ids
      if (design$settings$item_order == "seeded") order <- order[sample.int(length(order))]
      list(id = paste0("md-", review$design_hash, "-", allocation_index, "-", i), set_id = s$id, position = i, item_order = order)})
  })
  list(schema = "brohn-maxdiff-protocol/1.0", design_hash = review$design_hash, design = design,
    allocation_index = allocation_index, trials = trials, design_review = review)
}

brohn_maxdiff_validate_responses <- function(design, responses) {
  brohn_maxdiff_validate(design); hash <- brohn_hash(design)
  brohn_require(brohn_array(responses) && length(responses) <= 20000L, "MaxDiff responses must be an array of at most 20,000 explicit exposure records.")
  keys <- new.env(hash = TRUE, parent = emptyenv()); ids <- new.env(hash = TRUE, parent = emptyenv())
  for (r in responses) {
    brohn_fields(r, c("id", "participant_id", "participant_linkage", "session_id", "exposure_id", "design_hash", "set_id", "item_order", "presented", "status", "best_id", "worst_id", "missing_reason"), label = "MaxDiff exposure")
    brohn_require(all(vapply(r[c("id", "participant_id", "session_id", "exposure_id")], brohn_text, logical(1), max = 240)) && identical(r$design_hash, hash), "Each exposure needs explicit person/session/occurrence identity and the exact design hash.")
    brohn_require(is.logical(r$participant_linkage) && length(r$participant_linkage) == 1L && !is.na(r$participant_linkage),
      "Declare whether the source participant code links a person; anonymous run IDs cannot establish unique people.")
    set <- brohn_find(design$sets, r$set_id)
    brohn_require(!is.null(set) && brohn_array(r$item_order) && all(vapply(r$item_order, brohn_text, logical(1), max = 96)) &&
      !anyDuplicated(unlist(r$item_order)) && setequal(unlist(r$item_order), unlist(set$item_ids)), "The recorded item order must exactly preserve the actual offered set.")
    brohn_require(is.logical(r$presented) && length(r$presented) == 1L && !is.na(r$presented) && r$status %in% c("answered", "missing", "not_presented"), "Declare presentation and complete/missing outcome status.")
    for (value in r[c("best_id", "worst_id")]) brohn_require(is.null(value) || brohn_text(value, 96) && value %in% unlist(r$item_order), "Best/worst selections must be typed IDs from the presented set or explicit nulls.")
    if (r$status == "answered") brohn_require(isTRUE(r$presented) && !is.null(r$best_id) && !is.null(r$worst_id) && r$best_id != r$worst_id && is.null(r$missing_reason), "An answered MaxDiff exposure needs two distinct complete choices and no missing reason.") else {
      brohn_require(brohn_text(r$missing_reason, 1000) && identical(r$presented, r$status == "missing"), "Missing/unpresented exposures need an explicit reason and matching presentation state.")
      if (!r$presented) brohn_require(is.null(r$best_id) && is.null(r$worst_id), "An unpresented set cannot carry a response.")
      brohn_require(is.null(r$best_id) || is.null(r$worst_id), "A complete pair must be labelled answered; missing records retain only genuine incomplete evidence.")
    }
    key <- brohn_hash(r[c("participant_id", "session_id", "exposure_id")])
    brohn_require(!exists(r$id, ids, inherits = FALSE) && !exists(key, keys, inherits = FALSE), "Duplicate response or person/session/exposure identities cannot silently double-count a choice.")
    assign(r$id, TRUE, ids); assign(key, TRUE, keys)
  }
  invisible(responses)
}

# Full paired alternatives: x(best,worst) = e_best - e_worst. The last item is
# temporarily fixed at zero, then all estimated utilities are centred on zero.
.brohn_md_problem <- function(design, responses) {
  ids <- brohn_ids(design$items); n <- length(ids)
  answered <- Filter(function(r) r$status == "answered", responses)
  sets <- list()
  for (set in design$sets) {
    rows <- Filter(function(r) identical(r$set_id, set$id), answered); if (!length(rows)) next
    indices <- match(unlist(set$item_ids), ids)
    alternatives <- expand.grid(best = indices, worst = indices); alternatives <- alternatives[alternatives$best != alternatives$worst, ]
    x <- diag(n)[alternatives$best, , drop = FALSE]-diag(n)[alternatives$worst, , drop = FALSE]; x <- x[, seq_len(n-1L), drop = FALSE]
    observed <- numeric(n); for (r in rows) {observed[match(r$best_id, ids)] <- observed[match(r$best_id, ids)]+1; observed[match(r$worst_id, ids)] <- observed[match(r$worst_id, ids)]-1}
    sets[[length(sets)+1L]] <- list(set_id = set$id, alternatives = alternatives, x = x, observed = observed[-n], count = length(rows))
  }
  list(ids = ids, sets = sets, answered_count = length(answered))
}
.brohn_md_evaluate <- function(problem, beta, information = FALSE, retain_probabilities = FALSE) {
  ids <- problem$ids; n <- length(ids)
  brohn_require(is.numeric(beta) && length(beta) == n-1L && all(is.finite(beta)) && max(abs(beta)) <= 10000, "Provide finite bounded reference-coded item utilities.")
  objective <- 0; gradient <- numeric(n-1L); hessian <- matrix(0, n-1L, n-1L); probabilities <- list()
  for (s in problem$sets) {
    x <- s$x; eta <- as.vector(x %*% beta); shift <- max(eta); weights <- exp(eta-shift); probability <- weights/sum(weights); log_denominator <- shift+log(sum(weights))
    objective <- objective + s$count*log_denominator-sum(s$observed*beta)
    expected <- colSums(x*probability); gradient <- gradient+s$count*expected-s$observed
    if (information) hessian <- hessian+s$count*(crossprod(x, x*probability)-tcrossprod(expected))
    if (retain_probabilities) probabilities[[length(probabilities)+1L]] <- list(set_id = s$set_id, answered_exposures = s$count,
      alternatives = lapply(seq_len(nrow(s$alternatives)), function(i) list(best_id = ids[[s$alternatives$best[[i]]]], worst_id = ids[[s$alternatives$worst[[i]]]], probability = probability[[i]])))
  }
  list(negative_log_likelihood = objective, gradient = gradient, information = hessian, probabilities = probabilities, answered_count = problem$answered_count)
}
brohn_maxdiff_likelihood <- function(design, responses, beta = NULL, information = FALSE) {
  brohn_maxdiff_validate_responses(design, responses); problem <- .brohn_md_problem(design, responses)
  if (is.null(beta)) beta <- rep(0, length(problem$ids)-1L)
  .brohn_md_evaluate(problem, beta, information, TRUE)
}

brohn_maxdiff_fit <- function(design, responses, maximum_iterations = 500L) {
  brohn_maxdiff_validate_responses(design, responses)
  brohn_require(brohn_number(maximum_iterations, 1, 5000, TRUE), "Numerical iteration limit must be 1 to 5,000.")
  ids <- brohn_ids(design$items); n <- length(ids); answered <- Filter(function(r) r$status == "answered", responses)
  adjacency <- matrix(FALSE, n, n); preference <- adjacency
  for (r in answered) {indices <- match(unlist(r$item_order), ids); adjacency[indices, indices] <- TRUE
    b <- match(r$best_id, ids); w <- match(r$worst_id, ids); preference[b, indices] <- TRUE; preference[indices, w] <- TRUE}
  # A separation direction must put every observed best above its other items
  # and every observed worst below its other items. A strongly connected graph
  # forces every such direction to be constant. These inequalities are used
  # only to diagnose finite-MLE existence, never as added likelihood responses.
  identifiable <- all(.brohn_md_reach(adjacency)); finite <- all(.brohn_md_reach(preference))
  settings <- list(model = "paired_best_worst_mnl", likelihood = "exp(u_best-u_worst) divided by sum over all distinct ordered pairs in the actually offered set",
    reference_item = tail(ids, 1L), output_constraint = "sum_zero", weights = "one per complete observed pair", optimiser = "R stats::optim BFGS analytic gradient",
    maximum_iterations = maximum_iterations, relative_tolerance = 1e-12, mean_gradient_tolerance = 1e-6, maximum_information_condition = 1e10,
    uncertainty = "not_estimated; repeated choices and sessions are not independent participants")
  empty <- function(status, reason, diagnostics = list()) list(status = status, reason = reason, utilities = list(), parameters = settings,
    diagnostics = c(list(answered_exposures = length(answered), connected_answered_design = identifiable, finite_mle_graph = finite), diagnostics))
  if (!length(answered)) return(empty("unavailable", "no_complete_pairs"))
  if (!identifiable) return(empty("unavailable", "disconnected_answered_item_design"))
  if (!finite) return(empty("unavailable", "complete_or_quasi_separation; no finite unpenalised aggregate MLE"))
  total <- length(answered)
  problem <- .brohn_md_problem(design, responses)
  # Cache the last evaluation: optim commonly requests its value and gradient
  # at the same point. No response weights or source rows are changed.
  cache <- new.env(parent = emptyenv()); cache$beta <- NULL
  evaluate <- function(beta) {if (!identical(cache$beta, beta)) {cache$beta <- beta; cache$value <- .brohn_md_evaluate(problem, beta)}; cache$value}
  fitted <- tryCatch(stats::optim(rep(0, n-1L), function(b) evaluate(b)$negative_log_likelihood/total,
    gr = function(b) evaluate(b)$gradient/total, method = "BFGS", control = list(maxit = maximum_iterations, reltol = 1e-12)), error = identity)
  if (inherits(fitted, "error")) return(empty("unavailable", "numerical_failure", list(message = conditionMessage(fitted))))
  final <- .brohn_md_evaluate(problem, fitted$par, information = TRUE, retain_probabilities = TRUE)
  eigenvalues <- eigen(final$information, symmetric = TRUE, only.values = TRUE)$values
  condition <- if (min(eigenvalues) > 0) max(eigenvalues)/min(eigenvalues) else Inf
  diagnostics <- list(convergence_code = fitted$convergence, mean_gradient_maximum = max(abs(final$gradient))/total,
    negative_log_likelihood = final$negative_log_likelihood, null_negative_log_likelihood = .brohn_md_evaluate(problem, rep(0, n-1L))$negative_log_likelihood,
    minimum_information_eigenvalue = min(eigenvalues), information_condition = if (is.finite(condition)) condition else NULL,
    evaluations = as.list(fitted$counts))
  if (fitted$convergence != 0L || diagnostics$mean_gradient_maximum > 1e-6) return(empty("unavailable", "nonconvergence", diagnostics))
  if (!is.finite(condition) || condition > 1e10 || min(eigenvalues) <= 1e-8) return(empty("unavailable", "insufficient_numerical_information", diagnostics))
  raw <- c(fitted$par, 0); centred <- raw-mean(raw)
  result <- empty("estimated", NULL, diagnostics)
  result$utilities <- lapply(seq_along(ids), function(i) list(item_id = ids[[i]], utility = centred[[i]], unit = "relative_logit_utility", scope = "aggregate_observed_complete_pairs", standard_error = NULL))
  result$probabilities <- final$probabilities
  result
}

brohn_maxdiff_analysis <- function(design, responses, source = NULL) {
  brohn_maxdiff_validate_responses(design, responses); review <- brohn_maxdiff_design_review(design); ids <- brohn_ids(design$items)
  if (!is.null(source)) {brohn_fields(source, c("hash", "origin"), c("id", "revision"), "MaxDiff source")
    brohn_require(brohn_text(source$hash, 64) && grepl("^[a-f0-9]{64}$", source$hash) && source$origin %in% c("sample", "preview", "pilot", "live", "imported"), "Declare a pinned source hash and its actual origin.")
    brohn_require(design$origin != "synthetic" || source$origin %in% c("sample", "preview"), "Synthetic MaxDiff material cannot be upgraded to a live/pilot research source by this adapter.")}
  items <- lapply(seq_along(ids), function(i) {
    id <- ids[[i]]; offered <- Filter(function(r) isTRUE(r$presented) && id %in% unlist(r$item_order), responses); complete <- Filter(function(r) r$status == "answered", offered)
    best <- sum(vapply(complete, function(r) identical(r$best_id, id), logical(1))); worst <- sum(vapply(complete, function(r) identical(r$worst_id, id), logical(1)))
    list(item_id = id, label = design$items[[i]]$label, presented_exposures = length(offered), answered_exposures = length(complete), missing_exposures = length(offered)-length(complete),
      best_count = best, worst_count = worst, best_minus_worst = best-worst,
      exposure_adjusted_score = if (length(complete)) (best-worst)/length(complete) else NULL,
      denominator = "complete_pair_exposures_containing_this_item", observed_positions = as.list(tabulate(vapply(offered, function(r) match(id, unlist(r$item_order)), integer(1)), nbins = 8L)))
  })
  people <- unique(vapply(responses, function(r) r$participant_id, character(1)))
  linkage <- vapply(responses, function(r) r$participant_linkage, logical(1))
  linked <- length(linkage) > 0L && all(linkage)
  sessions <- unique(vapply(responses, function(r) brohn_hash(r[c("participant_id", "session_id")]), character(1)))
  repeats <- table(vapply(Filter(function(r) isTRUE(r$presented), responses), function(r) brohn_hash(r[c("participant_id", "session_id", "set_id")]), character(1)))
  model <- if (isTRUE(design$settings$analysis$fit_aggregate)) brohn_maxdiff_fit(design, responses) else list(status = "not_requested", utilities = list(), reason = "aggregate_fit_disabled")
  list(schema = "brohn-maxdiff-result/1.0", kind = "maxdiff", profile = design$profile, design_hash = review$design_hash, responses_hash = brohn_hash(responses),
    source = source, design = design, design_review = review, items = items, exposures = responses, model = model,
    quality = list(exposure_records = length(responses), presented_exposures = sum(vapply(responses, function(r) isTRUE(r$presented), logical(1))),
      answered_exposures = sum(vapply(responses, function(r) r$status == "answered", logical(1))), missing_exposures = sum(vapply(responses, function(r) r$status == "missing", logical(1))),
      participant_count = if (linked) length(people) else NULL, participant_linkage = if (linked) "all_declared" else if (any(linkage)) "mixed" else "unavailable",
      session_count = length(sessions), session_identity_policy = "source participant-code/session-ID tuple; anonymous codes do not establish people",
      repeated_set_exposures = sum(pmax(0, repeats-1L)),
      utility_estimated = identical(model$status, "estimated"), individual_utilities = FALSE, participant_inference_performed = FALSE, scientifically_qualified = FALSE),
    limitations = list("Object-case best-worst choices are explicit stated preferences, not an implicit association or emotion measure.",
      "Incomplete pairs are preserved but excluded as complete outcomes; per-item missing exposure counts remain visible and are never interpreted as indifference.",
      "Aggregate utilities use the paired best-worst likelihood, not independent best/worst, marginal or sequential alternatives. Each complete pair has equal weight; participants with more answered exposures contribute more choices.",
      "A connected item design and finite numerical fit do not prove a suitable experimental design, reliable preferences or freedom from position effects.",
      "Utilities are relative on a sum-zero logit scale. No hierarchical Bayes, individual preferences, market shares, psychological labels or population confidence intervals are estimated.",
      "Repeated sessions/exposures remain source evidence. Their presence does not create additional independent participants; uncertainty needs a separately reviewed participant-aware method."))
}
