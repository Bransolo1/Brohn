# Consumer numerical answers must retain their scale, typed validity and the
# participant denominator when synthesized alongside other research measures.
source("R/platform-load.R", encoding = "UTF-8"); brohn_load(ui = FALSE)
local({
  checks <- 0L
  check <- function(name, ok) {if (!isTRUE(ok)) stop("FAILED: ", name); checks <<- checks+1L}
  root <- tempfile("brohn-numeric-synthesis-")
  store <- brohn_open_store(root); on.exit(brohn_close_store(store), add = TRUE)
  brohn_initialise_library(store)
  design <- brohn_new_design("Numerical consumer response oracle")
  numeric_question <- function(id, type, minimum, maximum, step) {
    q <- design$questions[[1L]]; q$id <- id; q$type <- type; q$prompt <- paste("Original", type, "fixture")
    q$options <- list(); q$min <- minimum; q$max <- maximum; q$step <- step; q$required <- FALSE; q
  }
  number <- numeric_question("q-price-change", "number", -10, 10, .25)
  slider <- numeric_question("q-intensity", "slider", 0, 100, .5)
  nominal <- design$questions[[1L]]; nominal$id <- "q-product-code"; nominal$type <- "single_choice"
  design$questions <- list(number, slider, nominal)
  brohn_validate_design(design); brohn_put_entity(store, "study", design$id, design)
  # Price change: P1's visit effects 2 and 6 average to 4, P2's is -2;
  # the equal-person estimate is 1 (not the three-visit average of 2).
  # Intensity: P1's 10 and 30 average to 20, P2's is 40; estimate = 30.
  visits <- list(list(person = "P1", visit = "V1", prices = c(0, 2), intensity = c(0, 10)),
    list(person = "P1", visit = "V2", prices = c(-1, 5), intensity = c(5, 35)),
    list(person = "P2", visit = "V1", prices = c(2, 0), intensity = c(10, 50)))
  observations <- list(); links <- list()
  for (v in visits) {
    links[[length(links)+1L]] <- list(report_id = "report-numeric", source_participant_id = v$person,
      source_session_id = v$visit, participant_id = v$person, session_id = v$visit)
    for (i in 1:2) for (q in c("price", "intensity")) {
      observations[[length(observations)+1L]] <- list(participant_id = v$person, session_id = v$visit,
        condition_id = design$conditions[[i]]$id, stimulus_id = design$stimuli[[i]]$id,
        exposure_id = paste(v$visit, i, sep = "-"), question_id = if (q == "price") number$id else slider$id,
        value = if (q == "price") v$prices[[i]] else v$intensity[[i]], missing_reason = NULL)
    }
  }
  body <- list(schema_version = "brohn-report/1.0.0", id = "report-numeric", title = "Original numerical fixture",
    study_id = design$id, dataset_id = "dataset-original", origin = "sample", status = "Available",
    analysis = list(kind = "questionnaire", observations = observations, features = list(), quality = list()),
    provenance = list(design = design, design_hash = brohn_hash(design), source = list(hash = brohn_hash("original numerical fixture"))))
  source_report <- brohn_put_entity(store, "report", body$id, body)
  contrast <- function(id, q) list(id = id, report_ids = list(body$id), modality = "questionnaire", metric = "explicit_numeric_response",
    outcome_id = q, unit = "response units", control_id = design$conditions[[1L]]$id, test_id = design$conditions[[2L]]$id)
  comparisons <- list(contrast("price-change", number$id), contrast("intensity", slider$id))
  frozen <- brohn_prepare_multimodal(store, design$id, list(body$id), links, comparisons, "sample",
    identity_source = "Explicit original fixture participant and visit linkage", multiplicity = list(method = "holm", alpha = .05))
  result <- brohn_analyse_multimodal(brohn_multimodal_input(store, frozen))$analysis
  first <- result$contrasts[[1L]]; second <- result$contrasts[[2L]]
  check("number answers use equal participants across repeat visits", abs(first$estimate-1) < 1e-12 && first$participant_count == 2 && first$paired_session_count == 3)
  check("slider answers use their own declared numerical scale", abs(second$estimate-30) < 1e-12 && second$participant_count == 2 && second$unit == "response units")
  check("zero and negative number responses survive as eligible observations", any(vapply(result$observations, function(x) isTRUE(x$eligible) && brohn_number(x$value) && x$value == 0, logical(1))) &&
    any(vapply(result$observations, function(x) isTRUE(x$eligible) && brohn_number(x$value) && x$value == -1, logical(1))))
  check("numeric measurements remain distinct from declared rating points", all(vapply(result$observations, function(x) x$metric == "explicit_numeric_response" && x$unit == "response units", logical(1))))
  # Invalid observations remain retained for review, but cannot become numbers
  # simply because a category code, string, boolean or out-of-scale value looks numeric.
  probe <- observations[[1L]]
  invalid <- list(list(q = number$id, value = "2"), list(q = number$id, value = FALSE), list(q = number$id, value = 11),
    list(q = number$id, value = .1), list(q = slider$id, value = 100.5), list(q = slider$id, value = .25),
    list(q = nominal$id, value = nominal$options[[1L]]$value), list(q = number$id, value = NULL))
  altered <- body
  altered$analysis$observations <- lapply(invalid, function(x) {r <- probe; r$question_id <- x$q; r["value"] <- list(x$value); r})
  reference <- list(id = source_report$id, revision = source_report$revision, hash = brohn_hash(altered))
  rows <- .brohn_mm_extract(altered, reference, design)
  check("typed invalid and nominal numerical codes are excluded without coercion", length(rows) == length(invalid) && all(vapply(rows, function(x) !x$source_eligible, logical(1))))
  check("numeric categorical code has an explicit non-quantitative reason", rows[[7L]]$source_missing_reason == "not_a_declared_quantitative_question")
  check("missing answer remains null rather than zero", is.null(rows[[8L]]$value) && rows[[8L]]$source_missing_reason == "missing_or_invalid_numeric_response")
  check("synthesis preserves pinned questionnaire source and exact definitions", identical(brohn_hash(brohn_study(store, design$id)$body$questions), brohn_hash(design$questions)) &&
    identical(brohn_hash(brohn_get_entity(store, "report", body$id)$body), brohn_hash(body)))
  cat(sprintf("PASS: %d independent number/slider synthesis checks\n", checks))
})
