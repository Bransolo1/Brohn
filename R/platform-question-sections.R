# Pure questionnaire layout and assignment. No store, UI or participant effects.
.brohn_sections_source <- function(design) {
  base <- design; base$questionnaire_sections <- NULL
  # Removing only our extension avoids recursion when core adds its validator.
  brohn_validate_design(base)
  invisible(TRUE)
}
.brohn_sections_refs <- function(rule) {
  if (is.null(rule)) return(character())
  if (rule$op %in% c("and", "or")) return(unique(unlist(lapply(rule$rules, .brohn_sections_refs), use.names = FALSE)))
  if (rule$op == "not") return(.brohn_sections_refs(rule$rule))
  rule$question_id
}
.brohn_sections_bounds <- function(items) {
  eligible <- which(vapply(items, function(x) x$placement == "shuffle", logical(1)))
  lapply(seq_along(items), function(i) if (i %in% eligible) range(eligible) else c(i, i))
}
.brohn_sections_label <- function(scope) switch(scope, before = "Before the study", after_each = "After each stimulus", end = "At the end")

brohn_validate_question_sections <- function(config, design) {
  .brohn_sections_source(design)
  brohn_fields(config, c("schema_version", "assignment", "sections"), label = "Questionnaire sections")
  brohn_require(identical(config$schema_version, "brohn-questionnaire-sections/1.0") &&
    identical(config$assignment, "participant-sha256/1.0"), "Choose the registered questionnaire-section schema and assignment version.")
  brohn_require(brohn_array(config$sections) && length(config$sections) <= 200L,
    "Use at most 200 questionnaire sections.")
  locations <- list(); section_ids <- character(); group_ids <- character()
  for (section in config$sections) {
    brohn_fields(section, c("id", "label", "scope", "placement", "groups"), label = "Questionnaire section")
    brohn_require(brohn_valid_id(section$id) && brohn_text(section$label, 240), "Give every section a valid ID and readable name.")
    label <- paste0("Section '", section$label, "':")
    brohn_require(brohn_text(section$scope, 40) && section$scope %in% c("before", "after_each", "end"), paste(label, "choose one assessment scope."))
    brohn_require(brohn_text(section$placement, 40) && section$placement %in% c("fixed", "shuffle"), paste(label, "choose fixed or shuffle placement."))
    brohn_require(brohn_array(section$groups) && length(section$groups) >= 1L && length(section$groups) <= 200L,
      paste(label, "include at least one nonempty question group."))
    section_ids <- c(section_ids, section$id)
    for (gi in seq_along(section$groups)) {
      group <- section$groups[[gi]]
      brohn_fields(group, c("id", "label", "placement", "question_ids"), label = paste(label, "question group"))
      brohn_require(brohn_valid_id(group$id) && brohn_text(group$label, 240), paste(label, "give each group an ID and readable name."))
      group_label <- paste0(label, " group '", group$label, "':")
      brohn_require(brohn_text(group$placement, 40) && group$placement %in% c("fixed", "shuffle"), paste(group_label, "choose fixed or shuffle placement."))
      brohn_require(brohn_array(group$question_ids) && length(group$question_ids) >= 1L && length(group$question_ids) <= 200L &&
        all(vapply(group$question_ids, brohn_valid_id, logical(1))), paste(group_label, "select 1 to 200 existing question IDs."))
      group_ids <- c(group_ids, group$id)
      brohn_require(length(group_ids) <= 200L, "A questionnaire can have at most 200 groups in total.")
      for (qi in seq_along(group$question_ids)) {
        id <- group$question_ids[[qi]]; question <- brohn_find(design$questions, id)
        brohn_require(!is.null(question), paste(group_label, "question", id, "is no longer in the design."))
        brohn_require(identical(question$scope, section$scope), paste(group_label, "question", question$prompt, "belongs to a different assessment scope."))
        brohn_require(is.null(locations[[id]]), paste("Question", question$prompt, "must belong to exactly one group."))
        locations[[id]] <- list(scope = section$scope, section_id = section$id, section_label = section$label,
          group_id = group$id, group_label = group$label, group_position = gi, question_position = qi)
      }
    }
  }
  brohn_require(!anyDuplicated(section_ids) && !anyDuplicated(group_ids), "Section IDs and group IDs must each be unique across the questionnaire.")
  missing <- setdiff(brohn_ids(design$questions), names(locations))
  brohn_require(!length(missing), paste("Place every question in a section; missing:", paste(vapply(design$questions[brohn_ids(design$questions) %in% missing], `[[`, character(1), "prompt"), collapse = "; ")))
  for (scope in c("before", "after_each", "end")) {
    sections <- Filter(function(s) s$scope == scope, config$sections)
    sb <- .brohn_sections_bounds(sections)
    for (si in seq_along(sections)) {
      section <- sections[[si]]; gb <- .brohn_sections_bounds(section$groups)
      for (gi in seq_along(section$groups)) for (id in section$groups[[gi]]$question_ids) {
        locations[[id]]$section_bounds <- sb[[si]]; locations[[id]]$group_bounds <- gb[[gi]]
      }
    }
  }
  for (question in design$questions) for (reference in .brohn_sections_refs(question$show_if)) {
    from <- locations[[reference]]; to <- locations[[question$id]]
    safe <- if (!identical(from$scope, to$scope)) identical(from$scope, "before") && to$scope %in% c("after_each", "end") else
      if (!identical(from$section_id, to$section_id)) from$section_bounds[[2L]] < to$section_bounds[[1L]] else
      if (!identical(from$group_id, to$group_id)) from$group_bounds[[2L]] < to$group_bounds[[1L]] else
        from$question_position < to$question_position
    driver <- brohn_find(design$questions, reference)
    brohn_require(safe, paste0("Question '", question$prompt, "' needs '", driver$prompt,
      "' first. Keep them in one ordered group, or fix their groups/sections in a safe order (", from$section_label, " / ", to$section_label, ")."))
  }
  for (scale in brohn_default(design$scales, list())) {
    ids <- vapply(scale$items, `[[`, character(1), "question_id")
    groups <- vapply(locations[ids], `[[`, character(1), "group_id")
    positions <- vapply(locations[ids], `[[`, integer(1), "question_position")
    original <- match(ids, brohn_ids(design$questions))
    brohn_require(length(unique(groups)) == 1L && all(diff(positions[order(original)]) > 0L),
      paste0("Keep scale '", scale$label, "' in one group with its existing authored question order. Scoring-key item order does not define presentation order."))
  }
  invisible(TRUE)
}

brohn_question_sections_new <- function(design) {
  .brohn_sections_source(design)
  sections <- list()
  for (scope in c("before", "after_each", "end")) {
    questions <- Filter(function(q) q$scope == scope, design$questions)
    if (!length(questions)) next
    ids <- brohn_ids(questions); joins <- rep(FALSE, max(0L, length(ids)-1L))
    join_span <- function(indices) {
      if (length(indices) < 2L) return(invisible(NULL))
      ends <- range(indices)
      if (ends[[2L]] > ends[[1L]]) joins[seq.int(ends[[1L]], ends[[2L]]-1L)] <<- TRUE
    }
    for (i in seq_along(questions)) {
      refs <- match(.brohn_sections_refs(questions[[i]]$show_if), ids); refs <- refs[!is.na(refs)]
      for (ref in refs) join_span(c(ref, i))
    }
    for (scale in Filter(function(s) s$scope == scope, brohn_default(design$scales, list())))
      join_span(match(vapply(scale$items, `[[`, character(1), "question_id"), ids))
    starts <- c(1L, which(!joins)+1L); ends <- c(starts[-1L]-1L, length(ids))
    groups <- lapply(seq_along(starts), function(i) {
      selected <- seq.int(starts[[i]], ends[[i]])
      label <- substr(questions[[selected[[1L]]]]$prompt, 1L, 120L)
      if (length(selected) > 1L) label <- paste0(label, " (+", length(selected)-1L, " grouped questions)")
      list(id = brohn_id("qgroup"), label = label, placement = "fixed", question_ids = as.list(ids[selected]))
    })
    sections[[length(sections)+1L]] <- list(id = brohn_id("qsection"), label = .brohn_sections_label(scope),
      scope = scope, placement = "fixed", groups = groups)
  }
  config <- list(schema_version = "brohn-questionnaire-sections/1.0", assignment = "participant-sha256/1.0", sections = sections)
  brohn_validate_question_sections(config, design); config
}

.brohn_sections_order <- function(items, seed, allocation_index, scope, stimulus_id, level, parent_id = NULL) {
  eligible <- which(vapply(items, function(x) x$placement == "shuffle", logical(1)))
  if (length(eligible) < 2L) return(items)
  ranks <- vapply(items[eligible], function(item) brohn_hash(list(schema_version = "brohn-questionnaire-order/1.0",
    seed = sprintf("%.0f", seed), allocation_index = sprintf("%.0f", allocation_index), scope = scope,
    stimulus_id = stimulus_id, level = level, parent_id = parent_id, item_id = item$id)), character(1))
  items[eligible] <- items[eligible][order(ranks, brohn_ids(items[eligible]), method = "radix")]
  items
}

brohn_question_sections_plan <- function(design, allocation_index, scope, stimulus_id = NULL) {
  .brohn_sections_source(design)
  brohn_require(brohn_number(allocation_index, 1, 1e9, TRUE) && brohn_text(scope, 40) && scope %in% c("before", "after_each", "end"),
    "Choose a valid participant allocation and questionnaire scope.")
  if (scope == "after_each") brohn_require(brohn_valid_id(stimulus_id) && stimulus_id %in% brohn_ids(design$stimuli),
    "An after-stimulus section needs its exact existing stimulus ID.") else brohn_require(is.null(stimulus_id), "Before/end sections do not take a stimulus identity.")
  enabled <- "questionnaire_sections" %in% names(design)
  if (enabled) brohn_validate_question_sections(design$questionnaire_sections, design)
  .brohn_question_sections_plan_validated(design, allocation_index, scope, stimulus_id,
    if (enabled) brohn_hash(design) else NULL, if (enabled) brohn_hash(design$questionnaire_sections) else NULL)
}

# Compiler-only fast path: caller already validated the entire design/context
# once and pins these hashes once. It does not weaken the public entry point.
.brohn_question_sections_plan_validated <- function(design, allocation_index, scope, stimulus_id, design_hash, sections_hash) {
  if (!"questionnaire_sections" %in% names(design)) return(list(entries = lapply(Filter(function(q) q$scope == scope, design$questions),
    function(q) list(question = q, questionnaire = NULL)), manifest = NULL))
  config <- design$questionnaire_sections
  selected <- Filter(function(s) s$scope == scope, config$sections)
  selected <- .brohn_sections_order(selected, design$seed, allocation_index, scope, stimulus_id, "section")
  context <- list(schema_version = "brohn-questionnaire-assignment/1.0", assignment = config$assignment,
    design_hash = design_hash, sections_hash = sections_hash, seed = sprintf("%.0f", design$seed),
    allocation_index = sprintf("%.0f", allocation_index), scope = scope, stimulus_id = stimulus_id)
  assignment_id <- paste0("questionnaire-", brohn_hash(context))
  entries <- list(); realized <- list()
  for (si in seq_along(selected)) {
    section <- selected[[si]]
    groups <- .brohn_sections_order(section$groups, design$seed, allocation_index, scope, stimulus_id, "group", section$id)
    group_records <- list()
    for (gi in seq_along(groups)) {
      group <- groups[[gi]]
      group_records[[gi]] <- list(id = group$id, label = group$label, placement = group$placement, position = gi, question_ids = group$question_ids)
      for (qi in seq_along(group$question_ids)) entries[[length(entries)+1L]] <- list(question = brohn_find(design$questions, group$question_ids[[qi]]),
        questionnaire = list(schema_version = "brohn-questionnaire-step/1.0", assignment_id = assignment_id, section_id = section$id,
          section_label = section$label, section_position = si, group_id = group$id, group_label = group$label,
          group_position = gi, question_position = qi, scope = scope, stimulus_id = stimulus_id))
    }
    realized[[si]] <- list(id = section$id, label = section$label, placement = section$placement, position = si,
      realized_group_order = as.list(brohn_ids(groups)), groups = group_records)
  }
  list(entries = entries, manifest = c(context, list(assignment_id = assignment_id,
    realized_section_order = as.list(brohn_ids(selected)), sections = realized,
    realized_question_order = as.list(vapply(entries, function(e) e$question$id, character(1))))))
}

brohn_clone_question_sections <- function(config, question_map) {
  brohn_require(is.list(config) && identical(config$schema_version, "brohn-questionnaire-sections/1.0") &&
    identical(config$assignment, "participant-sha256/1.0") && brohn_array(config$sections), "Clone a validated questionnaire-section configuration.")
  brohn_require(is.character(question_map) && !is.null(names(question_map)) && !anyNA(question_map) &&
    !anyNA(names(question_map)) && !anyDuplicated(names(question_map)) && !anyDuplicated(question_map) &&
    all(vapply(as.list(question_map), brohn_valid_id, logical(1))) && all(vapply(as.list(names(question_map)), brohn_valid_id, logical(1))),
    "Cloning sections needs distinct original and replacement question identities.")
  result <- config
  result$sections <- lapply(result$sections, function(section) {
    section$id <- brohn_id("qsection")
    section$groups <- lapply(section$groups, function(group) {
      group$id <- brohn_id("qgroup")
      brohn_require(all(unlist(group$question_ids, use.names = FALSE) %in% names(question_map)), "Cloning sections requires every member question mapping.")
      group$question_ids <- lapply(group$question_ids, function(id) unname(question_map[[id]])); group
    }); section
  })
  result
}

brohn_question_sections_add <- function(design, question) {
  .brohn_sections_source(design)
  if ("questionnaire_sections" %in% names(design)) brohn_validate_question_sections(design$questionnaire_sections, design)
  brohn_require(is.list(question) && brohn_valid_id(question$id) && !question$id %in% brohn_ids(design$questions), "Add a question with a new unique ID.")
  result <- design; result$questions[[length(result$questions)+1L]] <- question
  .brohn_sections_source(result)
  if (!"questionnaire_sections" %in% names(result)) return(result)
  sections <- result$questionnaire_sections$sections
  matches <- which(vapply(sections, function(s) s$scope == question$scope, logical(1)))
  group <- list(id = brohn_id("qgroup"), label = substr(question$prompt, 1L, 120L), placement = "fixed", question_ids = list(question$id))
  if (length(matches) && identical(sections[[tail(matches, 1L)]]$placement, "fixed")) {
    index <- tail(matches, 1L); sections[[index]]$groups[[length(sections[[index]]$groups)+1L]] <- group
  } else {
    sections[[length(sections)+1L]] <- list(id = brohn_id("qsection"), label = .brohn_sections_label(question$scope),
      scope = question$scope, placement = "fixed", groups = list(group))
  }
  result$questionnaire_sections$sections <- sections
  brohn_validate_question_sections(result$questionnaire_sections, result); result
}

brohn_question_sections_remove <- function(design, question_id) {
  .brohn_sections_source(design)
  if ("questionnaire_sections" %in% names(design)) brohn_validate_question_sections(design$questionnaire_sections, design)
  brohn_require(brohn_valid_id(question_id) && question_id %in% brohn_ids(design$questions), "Choose an existing question to remove.")
  result <- design; result$questions <- Filter(function(q) q$id != question_id, result$questions)
  .brohn_sections_source(result) # Existing logic/scale validators reject broken references.
  if (!"questionnaire_sections" %in% names(result)) return(result)
  result$questionnaire_sections$sections <- Filter(function(s) length(s$groups) > 0L,
    lapply(result$questionnaire_sections$sections, function(section) {
      section$groups <- Filter(function(g) length(g$question_ids) > 0L, lapply(section$groups, function(group) {
        group$question_ids <- Filter(function(id) id != question_id, group$question_ids); group
      })); section
    }))
  brohn_validate_question_sections(result$questionnaire_sections, result); result
}
