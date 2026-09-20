source("R/platform-participant-equipment.R") # Registered optional new-draft policy.
# Pure-domain evidence; shared compiler/browser hooks are intentionally separate.
for (module in c("platform-core", "platform-scales", "platform-question-sections")) source(paste0("R/", module, ".R"), encoding = "UTF-8")
source("tests/fixtures/question-sections-original.R")
local({
  checks <- 0L
  check <- function(label, value) {if (!isTRUE(value)) stop("FAIL: ", label); checks <<- checks+1L}
  rejects <- function(expr, pattern = NULL) {
    error <- tryCatch({force(expr); NULL}, error = conditionMessage)
    !is.null(error) && (is.null(pattern) || grepl(pattern, error, fixed = TRUE))
  }
  ids <- function(plan) vapply(plan$entries, function(e) e$question$id, character(1))
  original <- brohn_sections_fixture(); original_hash <- brohn_hash(original)
  legacy <- brohn_question_sections_plan(original, 1, "before")
  check("absent sections preserve exact flat question records and omit metadata", identical(lapply(legacy$entries, `[[`, "question"), Filter(function(q) q$scope == "before", original$questions)) && is.null(legacy$manifest) && all(vapply(legacy$entries, function(e) is.null(e$questionnaire), logical(1))))
  d <- original; d$questionnaire_sections <- brohn_question_sections_new(d)
  check("enabling groups preserves source without mutation", identical(brohn_hash(original), original_hash))
  for (scope in c("before", "after_each", "end")) check(paste("enabling preserves exact authored scope order", scope),
    identical(ids(brohn_question_sections_plan(d, 1, scope, if (scope == "after_each") "stimulus-a" else NULL)), brohn_ids(Filter(function(q) q$scope == scope, d$questions))))
  check("constructor keeps driver and nested conditional follow-up together", identical(d$questionnaire_sections$sections[[1]]$groups[[2]]$question_ids, list("q-driver", "q-follow")))
  interleaved <- original; interleaved$questions[[4]]$show_if <- list(op = "answered", question_id = "q-start")
  grouped <- brohn_question_sections_new(interleaved)
  check("interleaved dependency spans merge without reordering intervening items", identical(grouped$sections[[1]]$groups[[1]]$question_ids, as.list(brohn_ids(interleaved$questions)[1:4])))
  empty <- brohn_new_design("Original empty sections", "blank"); empty$questionnaire_sections <- brohn_question_sections_new(empty)
  check("empty enabled questionnaire is allowed only for empty question list", length(empty$questionnaire_sections$sections) == 0L && length(brohn_question_sections_plan(empty, 1, "before")$entries) == 0L && rejects(brohn_validate_question_sections(empty$questionnaire_sections, original), "Place every question"))
  bad <- d; bad$questionnaire_sections <- NULL
  bad["questionnaire_sections"] <- list(NULL)
  check("explicit null does not silently disable an enabled layout", rejects(brohn_question_sections_plan(bad, 1, "before")))
  ordered <- brohn_sections_order_fixture(); brohn_validate_question_sections(ordered$questionnaire_sections, ordered)
  oracle <- brohn_parse(paste(readLines("tests/fixtures/question-sections-oracle.json", warn = FALSE), collapse = "\n"))
  for (allocation in 1:12) {
    expected <- Filter(function(r) r$allocation_index == allocation, oracle$rows)
    check(paste("independent nested hash/anchor oracle across all scopes, allocation", allocation), all(vapply(expected, function(row) {
      plan <- brohn_question_sections_plan(ordered, allocation, row$scope, row$stimulus_id)
      identical(as.list(ids(plan)), row$question_order) && identical(plan$manifest$realized_section_order, row$section_order) &&
        all(vapply(plan$manifest$sections, function(s) identical(s$realized_group_order, row$group_orders[[s$id]]), logical(1)))
    }, logical(1))))
  }
  plans <- lapply(1:12, function(i) brohn_question_sections_plan(ordered, i, "before"))
  check("prespecified allocations vary without claiming counterbalance", length(unique(vapply(plans, function(p) paste(ids(p), collapse = "/"), character(1)))) > 1L)
  check("fixed section and group slots remain exact even across intervening shuffle slots", all(vapply(plans, function(p) {
    sections <- p$manifest$sections; choice <- brohn_find(sections, "section-choices")
    identical(p$manifest$realized_section_order[c(1,3,5)], list("section-first", "section-middle", "section-last")) && identical(choice$realized_group_order[[3]], "group-anchor")
  }, logical(1))))
  check("parent/follow-up remain adjacent and ordered in every assignment", all(vapply(plans, function(p) match("q-follow", ids(p)) == match("q-driver", ids(p))+1L, logical(1))))
  check("typed question records and source design remain unchanged by plan", all(vapply(plans[[1]]$entries, function(e) identical(e$question, brohn_find(ordered$questions, e$question$id)), logical(1))) && identical(brohn_hash(ordered), brohn_hash(brohn_sections_order_fixture())))
  p <- plans[[7]]
  check("already-validated compiler path is byte-identical to public plan", identical(brohn_json(p), brohn_json(.brohn_question_sections_plan_validated(ordered, 7, "before", NULL, brohn_hash(ordered), brohn_hash(ordered$questionnaire_sections)))))
  check("manifest binds design/config hashes and exact hierarchy, step metadata stays sibling", identical(p$manifest$design_hash, brohn_hash(ordered)) && identical(p$manifest$sections_hash, brohn_hash(ordered$questionnaire_sections)) && all(vapply(p$entries, function(e) identical(e$questionnaire$assignment_id, p$manifest$assignment_id) && !"questionnaire" %in% names(e$question), logical(1))))
  changed <- ordered; changed$title <- "Original changed title"; changed$instructions <- "Different instruction"; changed$baseline_ms <- 900L
  changed$questionnaire_sections$sections[[2]]$label <- "Changed section label"
  check("labels/instructions/timing alter provenance but not assignment", identical(ids(brohn_question_sections_plan(changed, 7, "before")), ids(p)) && !identical(brohn_question_sections_plan(changed, 7, "before")$manifest$assignment_id, p$manifest$assignment_id))
  unrelated <- ordered; info <- brohn_question("Original unrelated end item", "information", "end", "q-other-end")
  unrelated <- brohn_question_sections_add(unrelated, info)
  check("unrelated scope question does not disturb existing before assignment", identical(ids(brohn_question_sections_plan(unrelated, 7, "before")), ids(p)))
  reordered <- ordered; reordered$stimuli <- rev(reordered$stimuli)
  check("after-each order binds stimulus identity rather than presentation position", identical(ids(brohn_question_sections_plan(ordered, 7, "after_each", "stimulus-a")), ids(brohn_question_sections_plan(reordered, 7, "after_each", "stimulus-a"))))
  check("repeated planning and JSON transport preserve exact assignment manifest", identical(brohn_json(p), brohn_json(brohn_question_sections_plan(ordered, 7, "before"))) && identical(brohn_json(p), brohn_json(brohn_parse(brohn_json(p)))))
  set.seed(21); state <- .Random.seed; invisible(brohn_question_sections_plan(ordered, 7, "before"))
  check("planning does not consume global R randomness", identical(state, .Random.seed))
  for (value in list(0, 1.5, NA_real_, Inf, "1")) check("invalid participant allocations fail", rejects(brohn_question_sections_plan(ordered, value, "before")))
  check("scope identity cannot be guessed or combined", rejects(brohn_question_sections_plan(ordered, 1, "after_each")) && rejects(brohn_question_sections_plan(ordered, 1, "before", "stimulus-a")) && rejects(brohn_question_sections_plan(ordered, 1, "after_each", "unknown")))

  invalid <- function(change, text = NULL) {x <- ordered; x <- change(x); rejects(brohn_validate_question_sections(x$questionnaire_sections, x), text)}
  check("unknown section schema/assignment fail", invalid(function(x) {x$questionnaire_sections$assignment <- "future"; x}) && invalid(function(x) {x$questionnaire_sections$schema_version <- "unknown"; x}))
  check("extra config fields fail", invalid(function(x) {x$questionnaire_sections$subset <- 2; x}))
  check("missing question membership has an actionable name", invalid(function(x) {x$questionnaire_sections$sections <- x$questionnaire_sections$sections[-1]; x}, "Original question q-start"))
  check("duplicate membership rejected", invalid(function(x) {x$questionnaire_sections$sections[[1]]$groups[[1]]$question_ids <- list("q-start", "q-start"); x}, "exactly one"))
  check("foreign question membership rejected", invalid(function(x) {x$questionnaire_sections$sections[[1]]$groups[[1]]$question_ids <- list("unknown"); x}, "no longer"))
  check("cross-scope member rejected", invalid(function(x) {x$questionnaire_sections$sections[[1]]$groups[[1]]$question_ids <- list("q-after"); x}, "different assessment scope"))
  check("empty group/section rejected", invalid(function(x) {x$questionnaire_sections$sections[[1]]$groups[[1]]$question_ids <- list(); x}) && invalid(function(x) {x$questionnaire_sections$sections[[1]]$groups <- list(); x}))
  check("duplicate section and global group IDs rejected", invalid(function(x) {x$questionnaire_sections$sections[[2]]$id <- x$questionnaire_sections$sections[[1]]$id; x}) && invalid(function(x) {x$questionnaire_sections$sections[[2]]$groups[[1]]$id <- "group-start"; x}))
  check("unsupported placements are not silently fixed", invalid(function(x) {x$questionnaire_sections$sections[[1]]$placement <- "random"; x}))
  check("section count bound enforced before traversal", invalid(function(x) {x$questionnaire_sections$sections <- rep(x$questionnaire_sections$sections[1], 201); x}))
  check("reversing a dependent group fails before assignment", invalid(function(x) {x$questionnaire_sections$sections[[2]]$groups[[1]]$question_ids <- list("q-follow", "q-driver"); x}, "needs"))
  check("unsafe shuffled group reference fails even if one seed happens to order safely", invalid(function(x) {x$questions[[4]]$show_if <- list(op = "answered", question_id = "q-driver"); x}, "Keep them in one ordered group"))
  check("fixed anchor dependency rejects a shuffle that can cross it", invalid(function(x) {x$questions[[6]]$show_if <- list(op = "answered", question_id = "q-anchor"); x}, "needs"))
  check("unsafe cross-section dependency rejected", invalid(function(x) {at <- match("q-extra", brohn_ids(x$questions)); x$questions[[at]]$show_if <- list(op = "answered", question_id = "q-driver"); x}, "needs"))
  safe <- ordered; at <- match("q-last", brohn_ids(safe$questions)); safe$questions[[at]]$show_if <- list(op = "answered", question_id = "q-driver")
  check("guaranteed earlier shuffled section can feed a later fixed anchor", !rejects(brohn_validate_question_sections(safe$questionnaire_sections, safe)))
  safe <- ordered; safe$questions[[4]]$show_if <- list(op = "answered", question_id = "q-start")
  check("earlier fixed section can feed any later shuffled group", !rejects(brohn_validate_question_sections(safe$questionnaire_sections, safe)))

  scale_design <- brohn_new_design("Original scale spans", "survey", "study-scale-sections")
  scale_design$questions <- lapply(1:5, function(i) brohn_question(paste("Original item", i), "rating", "before", paste0("item-", i)))
  scale <- function(id, indices) list(schema = "brohn-questionnaire-scale/1.0", id = id, label = paste("Original scale", id), version = "original/1", source = "Original synthetic arithmetic fixture", scope = "before",
    items = lapply(indices, function(i) list(question_id = paste0("item-", i), reverse = FALSE, min = 1, max = 7)),
    scoring = list(aggregation = "mean", missing = "complete", minimum_answered = length(indices), prorate = FALSE), conversion = NULL)
  scale_design$scales <- list(scale("scale-a", c(3,1)), scale("scale-b", c(2,4)))
  scale_design$questionnaire_sections <- brohn_question_sections_new(scale_design)
  check("overlapping scale spans merge while preserving presentation rather than key order", identical(scale_design$questionnaire_sections$sections[[1]]$groups[[1]]$question_ids, as.list(paste0("item-", 1:4))))
  split <- scale_design; first <- split$questionnaire_sections$sections[[1]]$groups[[1]]; first$question_ids <- list("item-1")
  rest <- first; rest$id <- "split-group"; rest$question_ids <- as.list(paste0("item-", 2:4))
  split$questionnaire_sections$sections[[1]]$groups <- c(list(first, rest), split$questionnaire_sections$sections[[1]]$groups[-1])
  check("scale fragmentation fails with instrument name", rejects(brohn_validate_question_sections(split$questionnaire_sections, split), "Original scale scale-a"))
  backwards <- scale_design; backwards$questionnaire_sections$sections[[1]]$groups[[1]]$question_ids <- rev(backwards$questionnaire_sections$sections[[1]]$groups[[1]]$question_ids)
  check("scale presentation order cannot silently follow scoring-key order", rejects(brohn_validate_question_sections(backwards$questionnaire_sections, backwards), "authored question order"))

  map <- stats::setNames(paste0("copied-", brohn_ids(ordered$questions)), brohn_ids(ordered$questions))
  cloned <- brohn_clone_question_sections(ordered$questionnaire_sections, map)
  clone_design <- ordered; clone_design$questions <- lapply(clone_design$questions, function(q) {
    rewrite <- function(rule) {if (is.null(rule)) return(NULL); if (!is.null(rule$question_id)) rule$question_id <- unname(map[[rule$question_id]]); if (!is.null(rule$rules)) rule$rules <- lapply(rule$rules, rewrite); if (!is.null(rule[["rule"]])) rule$rule <- rewrite(rule[["rule"]]); rule}
    q$id <- unname(map[[q$id]]); q["show_if"] <- list(rewrite(q$show_if)); q
  }); clone_design$questionnaire_sections <- cloned
  check("clone remaps every question and creates fresh section/group identities", !rejects(brohn_validate_question_sections(cloned, clone_design)) && !any(brohn_ids(cloned$sections) %in% brohn_ids(ordered$questionnaire_sections$sections)) && !identical(cloned, ordered$questionnaire_sections))
  check("incomplete or ambiguous clone maps fail", rejects(brohn_clone_question_sections(ordered$questionnaire_sections, map[-1])) && rejects(brohn_clone_question_sections(ordered$questionnaire_sections, setNames(rep("duplicate", length(map)), names(map)))))
  added <- brohn_question_sections_add(empty, brohn_question("Original first item", "text", "end", "first-item"))
  check("adding to enabled empty design creates fixed section/group membership", added$questionnaire_sections$sections[[1]]$placement == "fixed" && identical(added$questionnaire_sections$sections[[1]]$groups[[1]]$question_ids, list("first-item")))
  removed <- brohn_question_sections_remove(added, "first-item")
  check("removing last question cleans empty groups and sections", length(removed$questions) == 0L && length(removed$questionnaire_sections$sections) == 0L)
  appended <- brohn_question_sections_add(ordered, brohn_question("Original new before question", "text", "before", "q-new"))
  check("new question is a fixed final group after authored same-scope items", identical(tail(ids(brohn_question_sections_plan(appended, 7, "before")), 1), "q-new"))
  shuffled_last <- ordered; shuffled_last$questionnaire_sections$sections[[5]]$placement <- "shuffle"
  appended <- brohn_question_sections_add(shuffled_last, brohn_question("Original fixed new tail", "text", "before", "q-tail"))
  check("shuffled final section receives a separate fixed tail for new question", identical(tail(ids(brohn_question_sections_plan(appended, 7, "before")), 1), "q-tail"))
  check("remove driver rejects broken logic without changing source", rejects(brohn_question_sections_remove(ordered, "q-driver"), "earlier question") && identical(brohn_hash(ordered), brohn_hash(brohn_sections_order_fixture())))
  check("remove scale item rejects broken instrument reference", rejects(brohn_question_sections_remove(scale_design, "item-1"), "still uses"))
  check("flat add/remove never silently enables sections", !"questionnaire_sections" %in% names(brohn_question_sections_add(original, brohn_question("Original extra", "text", "end", "extra"))) && !"questionnaire_sections" %in% names(brohn_question_sections_remove(original, "q-end")))
  cat(sprintf("PASS: %d questionnaire section domain checks (independent nested orders, dependency refusal, scale grouping, clone/add/remove)\n", checks))
})
