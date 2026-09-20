source("R/platform-participant-equipment.R") # Registered optional new-draft policy.
# Independent researcher-QA assertions; no actual participant/device evidence.
# Run from the repository root with the prepared Brohn R library.
source("R/platform-core.R", encoding = "UTF-8")

local({
  checks <- 0L
  failures <- character()
  check <- function(name, expression) {
    checks <<- checks + 1L
    outcome <- tryCatch(isTRUE(force(expression)), error = function(e) {
      failures <<- c(failures, paste(name, "unexpected error:", conditionMessage(e)))
      NA
    })
    if (identical(outcome, FALSE)) failures <<- c(failures, name)
    invisible(outcome)
  }
  rejects <- function(expression) inherits(try(force(expression), silent = TRUE), "try-error")
  rejects_design <- function(label, field, value, base) {
    bad <- base; bad[field] <- list(value)
    check(label, rejects(brohn_validate_design(bad)))
  }
  fixture <- brohn_new_design("Researcher QA controlled packaging", id = "study-rqa")
  fixture$stimuli[[1]]$content <- "Current package: logo A"
  fixture$stimuli[[2]]$content <- "Revised package: logo B"
  fixture$baseline_ms <- 10000
  check("controlled original validates for release", !length(brohn_design_issues(fixture, TRUE)))
  original_hash <- brohn_hash(fixture)
  protocol <- brohn_compile(fixture, 1)
  viewing <- Filter(function(x) x$phase == "passive_viewing", protocol$timeline)
  baselines <- Filter(function(x) x$phase == "baseline", protocol$timeline)
  questions <- Filter(function(x) x$type == "question", protocol$timeline)
  check("control and test roles remain explicit", identical(fixture$conditions[[1]]$role, "control") && identical(fixture$conditions[[2]]$role, "test"))
  check("baseline is its own phase rather than a third condition", length(baselines) == 2 && length(protocol$design$conditions) == 2 && all(vapply(baselines, function(x) x$duration_ms == 10000, logical(1))))
  check("viewing remains five seconds per condition", length(viewing) == 2 && all(vapply(viewing, function(x) x$duration_ms == 5000, logical(1))))
  check("liking stays active response", length(questions) == 2 && all(vapply(questions, function(x) x$phase == "active_response", logical(1))))
  check("liking linked to actual presented stimulus", identical(vapply(questions, function(x) x$stimulus_id, character(1)), c("stimulus-a", "stimulus-b")))
  question_positions <- which(vapply(protocol$timeline, function(x) x$type == "question", logical(1)))
  check("liking follows corresponding passive presentation", all(vapply(question_positions, function(i) identical(protocol$timeline[[i-1]]$type, "stimulus") && identical(protocol$timeline[[i-1]]$stimulus_id, protocol$timeline[[i]]$stimulus_id), logical(1))))
  check("compile does not modify source design", identical(original_hash, brohn_hash(fixture)))
  check("protocol hash pins original design", identical(protocol$design_hash, original_hash))
  amended <- fixture; amended$title <- "Amended after release"
  check("later draft edits leave compiled revision untouched", identical(protocol$design$title, fixture$title) && !identical(brohn_hash(amended), protocol$design_hash))
  check("participant appearance frozen explicitly", identical(protocol$design$appearance, fixture$appearance))
  check("timing claim stays limited", identical(protocol$timing_evidence, "browser_observation_not_physical_qualification"))

  order_for <- function(x, index) unlist(brohn_compile(x, index)$realized_stimulus_order, use.names = FALSE)
  check("allocation 1 AB", identical(order_for(fixture, 1), c("stimulus-a", "stimulus-b")))
  check("allocation 2 BA", identical(order_for(fixture, 2), c("stimulus-b", "stimulus-a")))
  check("allocation 3 AB", identical(order_for(fixture, 3), c("stimulus-a", "stimulus-b")))
  fixed <- fixture; fixed$order <- "fixed"
  check("fixed order ignores allocation index", identical(order_for(fixed, 1), order_for(fixed, 9)))
  three <- fixture
  three$conditions[[3]] <- list(id = "condition-c", label = "Reference", role = "neutral")
  three$stimuli[[3]] <- three$stimuli[[1]]
  three$stimuli[[3]]$id <- "stimulus-c"; three$stimuli[[3]]$condition_id <- "condition-c"
  check("three stimuli allocation 1 ABC", identical(order_for(three, 1), c("stimulus-a", "stimulus-b", "stimulus-c")))
  check("three stimuli allocation 2 BCA", identical(order_for(three, 2), c("stimulus-b", "stimulus-c", "stimulus-a")))
  check("three stimuli allocation 3 CAB", identical(order_for(three, 3), c("stimulus-c", "stimulus-a", "stimulus-b")))
  check("three stimuli cycle wraps", identical(order_for(three, 4), order_for(three, 1)))
  cycle <- lapply(1:3, function(i) order_for(three, i))
  check("each condition appears first and last once in three allocation cycle", setequal(vapply(cycle, `[`, character(1), 1), brohn_ids(three$stimuli)) && setequal(vapply(cycle, `[`, character(1), 3), brohn_ids(three$stimuli)))
  for (invalid in list(0, -1, 1.5, NA_real_, Inf, "1", c(1, 2))) check(paste("reject invalid allocation", paste(invalid, collapse = ",")), rejects(brohn_compile(fixture, invalid)))

  randomized <- three; randomized$order <- "randomized"
  set.seed(906); previous_seed <- .Random.seed
  random_first <- order_for(randomized, 7)
  check("compile randomized order preserves global RNG state", identical(previous_seed, .Random.seed))
  check("same design and allocation reproducible", identical(random_first, order_for(randomized, 7)))
  check("randomized order is exact stimulus permutation", setequal(random_first, brohn_ids(randomized$stimuli)) && !anyDuplicated(random_first))
  seeded_question <- fixture; seeded_question$questions[[1]]$randomize_options <- TRUE
  invisible(brohn_compile(seeded_question, 2))
  check("question randomization preserves global RNG state", identical(previous_seed, .Random.seed))
  rm(".Random.seed", envir = .GlobalEnv)
  invisible(order_for(randomized, 7))
  check("compile preserves absent global RNG state", !exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE))
  assign(".Random.seed", previous_seed, envir = .GlobalEnv)
  invisible(try(brohn_seeded(10, function() stop("intentional fixture")), silent = TRUE))
  check("seed restoration survives thrown error", identical(previous_seed, .Random.seed))

  rule <- function(op, value = NULL) {
    out <- list(op = op, question_id = "q-source")
    if (!is.null(value)) out$value <- value
    out
  }
  check("zero counts as answered", brohn_rule(rule("answered"), list(`q-source` = 0)))
  check("false counts as answered", brohn_rule(rule("answered"), list(`q-source` = FALSE)))
  check("zero equality remains true", brohn_rule(rule("equals", 0), list(`q-source` = 0)))
  check("false equality remains true", brohn_rule(rule("equals", FALSE), list(`q-source` = FALSE)))
  check("zero is not false under typed equality", !brohn_rule(rule("equals", FALSE), list(`q-source` = 0)))
  check("missing is not answered", !brohn_rule(rule("answered"), list()))
  check("empty string is not answered", !brohn_rule(rule("answered"), list(`q-source` = "")))
  check("not equals does not make missing answered", !brohn_rule(rule("not_equals", 0), list()))
  check("contains respects multi-select values", brohn_rule(rule("contains", "B"), list(`q-source` = list("A", "B"))))
  check("numeric greater is strictly greater", !brohn_rule(rule("greater", 3), list(`q-source` = 3)) && brohn_rule(rule("greater", 3), list(`q-source` = 4)))
  check("conjunction combines independent clauses", brohn_rule(list(op = "and", rules = list(rule("answered"), rule("equals", FALSE))), list(`q-source` = FALSE)))
  check("nested not is evaluated", brohn_rule(list(op = "not", rule = rule("equals", TRUE)), list(`q-source` = FALSE)))
  check("unknown rule reference rejected", rejects(brohn_validate_rule(rule("equals", 0), "q-other")))
  check("unknown rule operator rejected", rejects(brohn_validate_rule(rule("execute", "x"), "q-source")))
  check("missing comparator rejected", rejects(brohn_validate_rule(rule("equals"), "q-source")))
  check("non-scalar comparator rejected", rejects(brohn_validate_rule(rule("equals", list(command = "unexpected")), "q-source")))
  check("nonfinite comparator rejected", rejects(brohn_validate_rule(rule("greater", Inf), "q-source")))
  check("negated null condition rejected", rejects(brohn_validate_rule(list(op = "not", rule = NULL), character())))
  check("null conjunction operand rejected", rejects(brohn_validate_rule(list(op = "and", rules = list(NULL)), character())))

  with_logic <- fixture
  driver <- brohn_question("Have you seen this package?", "single_choice", "before", "q-source")
  driver$options <- list(list(id = "yes", label = "Yes", value = TRUE), list(id = "no", label = "No", value = FALSE))
  followup <- brohn_question("Explain the unfamiliar package", "text", "before", "q-follow")
  followup$show_if <- rule("equals", FALSE)
  with_logic$questions <- list(driver, followup, fixture$questions[[1]])
  check("legitimate earlier-question branch validates", !length(brohn_design_issues(with_logic, TRUE)))
  future <- with_logic; future$questions <- rev(future$questions)
  check("forward list reference rejected", rejects(brohn_validate_design(future)))
  self <- with_logic; self$questions[[2]]$show_if$question_id <- "q-follow"
  check("self reference rejected", rejects(brohn_validate_design(self)))
  unknown <- with_logic; unknown$questions[[2]]$show_if$question_id <- "q-unknown"
  check("unknown question reference rejected", rejects(brohn_validate_design(unknown)))
  scope_hazard <- with_logic; scope_hazard$questions[[1]]$scope <- "end"
  check("scope execution order prevents future answer dependency", rejects(brohn_validate_design(scope_hazard)))
  each_hazard <- with_logic; each_hazard$questions[[1]]$scope <- "after_each"
  check("before question cannot depend on later per-stimulus answer", rejects(brohn_validate_design(each_hazard)))

  aoi <- list(id = "aoi-logo", label = "Logo", x = 0, y = 0, width = 0.5, height = 1)
  with_logic$stimuli[[1]]$aois <- list(aoi)
  before_clone <- brohn_json(with_logic)
  cloned <- brohn_clone_design(with_logic, "Replication copy", "new-project")
  check("clone leaves source unchanged", identical(before_clone, brohn_json(with_logic)))
  check("clone creates fresh study identity", !identical(cloned$id, with_logic$id))
  check("clone uses requested project and title", identical(cloned$project_id, "new-project") && identical(cloned$title, "Replication copy"))
  check("clone regenerates condition stimulus and question IDs", !any(brohn_ids(cloned$conditions) %in% brohn_ids(with_logic$conditions)) && !any(brohn_ids(cloned$stimuli) %in% brohn_ids(with_logic$stimuli)) && !any(brohn_ids(cloned$questions) %in% brohn_ids(with_logic$questions)))
  check("clone rewrites stimulus condition foreign keys", all(vapply(cloned$stimuli, function(s) s$condition_id %in% brohn_ids(cloned$conditions), logical(1))))
  check("clone rewrites logic dependency", identical(cloned$questions[[2]]$show_if$question_id, cloned$questions[[1]]$id))
  check("clone preserves false comparison value", identical(cloned$questions[[2]]$show_if$value, FALSE))
  check("clone regenerates AOI identity and retains geometry", !identical(cloned$stimuli[[1]]$aois[[1]]$id, aoi$id) && identical(cloned$stimuli[[1]]$aois[[1]]$width, 0.5))
  check("clone preserves control and baseline separately", identical(cloned$conditions[[1]]$role, "control") && identical(cloned$baseline_ms, 10000))
  check("clone lineage records source hash", identical(cloned$lineage$study_id, with_logic$id) && identical(cloned$lineage$design_hash, brohn_hash(with_logic)))
  check("clone contains no runtime or result properties", !any(c("participants", "responses", "runs", "allocations", "reports", "invitations", "deployments", "tokens", "results") %in% names(cloned)))
  check("clone remains compilable", !rejects(brohn_compile(cloned, 2)))
  injected <- with_logic; injected$results <- list(value = 100)
  check("design with injected results is rejected before clone", rejects(brohn_clone_design(injected)))

  wire <- list(one = list("single"), empty = list(), no_value = NULL,
    tick = "9007199254740993", flag = FALSE, count = 0)
  decoded <- brohn_parse(brohn_json(wire))
  check("single element JSON array remains array", brohn_array(decoded$one) && length(decoded$one) == 1 && identical(decoded$one[[1]], "single"))
  check("empty array remains array", brohn_array(decoded$empty) && length(decoded$empty) == 0)
  check("null field retained distinctly from omission", "no_value" %in% names(decoded) && is.null(decoded$no_value))
  check("large tick string survives exactly", identical(decoded$tick, "9007199254740993"))
  check("JSON false remains false", identical(decoded$flag, FALSE))
  check("JSON zero remains zero", is.numeric(decoded$count) && decoded$count == 0)
  check("canonical object key order hash invariant", identical(brohn_hash(list(a = 1, b = 2)), brohn_hash(list(b = 2, a = 1))))
  check("array order hash remains meaningful", !identical(brohn_hash(list("a", "b")), brohn_hash(list("b", "a"))))
  check("duplicate object keys rejected", rejects(brohn_parse('{"x":1,"x":2}')))
  check("numeric NA rejected rather than silently null", rejects(brohn_json(list(value = NA_real_))))
  check("character NA rejected rather than silently null", rejects(brohn_json(list(value = NA_character_))))
  check("nonfinite values rejected", rejects(brohn_json(list(value = Inf))))
  check("matrix cannot silently become an inferred JSON shape", rejects(brohn_json(list(value = matrix(1:4, 2)))))
  check("oversized JSON input rejected", rejects(brohn_parse('{"x":"large"}', max_bytes = 5)))
  rejects_design("unsupported schema rejected", "schema_version", "future/99", fixture)
  # Exercise complete ingress, not only individual field predicates.
  rejects_design("unknown top-level field rejected", "unrecognized", TRUE, fixture)
  rejects_design("named object cannot substitute conditions array", "conditions", list(first = fixture$conditions[[1]]), fixture)
  rejects_design("duplicate condition IDs rejected", "conditions", list(fixture$conditions[[1]], fixture$conditions[[1]]), fixture)
  rejects_design("unknown order rejected", "order", "convenience_sort", fixture)
  rejects_design("nonintegral baseline rejected", "baseline_ms", 1.5, fixture)
  rejects_design("unknown measure rejected", "measures", list("questionnaire", "arbitrary_unknown_measure"), fixture)
  rejects_design("duplicate selected measure rejected", "measures", list("gaze", "gaze"), fixture)
  bad_stimulus <- fixture; bad_stimulus$stimuli[[1]]$condition_id <- "nonexistent"
  check("unknown stimulus condition rejected", rejects(brohn_validate_design(bad_stimulus)))
  bad_aoi <- with_logic; bad_aoi$stimuli[[1]]$aois[[1]]$width <- 2
  check("out-of-image AOI rejected", rejects(brohn_validate_design(bad_aoi)))
  bad_asset <- fixture; bad_asset$stimuli[[1]]$asset <- list(hash = "not-a-hash", size = 1, media_type = "image/png")
  check("invalid asset hash rejected", rejects(brohn_validate_design(bad_asset)))
  empty <- brohn_new_design("Empty", "blank", id = "empty-study")
  check("blank draft allowed", !length(brohn_design_issues(empty)))
  check("empty study cannot be released", rejects(brohn_compile(empty)))
  unsupported <- fixture; unsupported$blocks <- list(list(id = "unsupported-task"))
  check("task blocks cannot be silently dropped by compiler", rejects(brohn_compile(unsupported)))
  check("task graph cannot be silently unmapped by clone", rejects(brohn_clone_design(unsupported)))
  unregistered_recipe <- fixture; unregistered_recipe$methods <- list(list(id = "unknown-unregistered-recipe"))
  check("unregistered analysis settings cannot be silently ignored", rejects(brohn_compile(unregistered_recipe)))

  source("R/study.R"); source("R/comparison.R"); source("R/presentation.R")
  legacy <- new_study()
  legacy$comparison <- list(control_condition = "B", rationale = "Current package B")
  legacy$presentation <- list(order = "fixed_ba", viewing_duration_ms = 6000)
  migrated <- brohn_legacy_design(legacy)
  check("legacy fixed BA migration keeps first stimulus B", identical(migrated$stimuli[[1]]$id, "stimulus-b") && identical(migrated$order, "fixed"))
  check("legacy control B not silently relabelled A", identical(migrated$conditions[[2]]$role, "control") && identical(migrated$conditions[[1]]$role, "test"))
  check("legacy viewing duration retained", all(vapply(migrated$stimuli, function(s) s$duration_ms == 6000, logical(1))))
  check("legacy optional liking remains optional", identical(migrated$questions[[1]]$required, FALSE))
  check("legacy lineage retained", identical(migrated$lineage$study_id, legacy$id) && migrated$lineage$revision == legacy$revision)
  no_control <- new_study(include_liking = FALSE)
  imported_none <- brohn_legacy_design(no_control)
  check("legacy no designated control remains no designated control", !any(vapply(imported_none$conditions, function(c) c$role == "control", logical(1))))
  check("legacy absent liking stays absent", length(imported_none$questions) == 0)

  if (length(failures)) {
    cat(sprintf("FAIL: %d of %d independent platform core assertions\n", length(failures), checks))
    cat(paste0(" - ", failures, collapse = "\n"), "\n")
    stop("Independent platform core acceptance failed", call. = FALSE)
  }
  cat(sprintf("PASS: %d independent platform core assertions (synthetic service execution only)\n", checks))
})
