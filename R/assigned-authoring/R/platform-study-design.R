# Version-aware authoring facade. The legacy/domain validators remain leaves;
# projections below are temporary editing values, never saved source documents.
brohn_validate_study_design <- function(design, publish = FALSE) {
  brohn_require(is.list(design) && is.character(design$schema_version) &&
    length(design$schema_version) == 1L && !is.na(design$schema_version),
    "Choose a supported saved study design.")
  validator <- switch(design$schema_version,
    "brohn-design/1.0.0" = "brohn_validate_design",
    "brohn-design/1.1.0" = "brohn_validate_evidence_design",
    "brohn-design/1.2.0" = "brohn_validate_variant_design", NULL)
  brohn_require(!is.null(validator) && exists(validator, mode = "function"),
    "This design requires its installed versioned reader. No design was migrated.")
  get(validator, mode = "function")(design, publish = publish)
  invisible(design)
}
brohn_study_design_issues <- function(design, publish = FALSE)
  tryCatch({brohn_validate_study_design(design, publish); character()},
    error = function(e) conditionMessage(e))
.brohn_study_evidence <- function(design) identical(design$schema_version, "brohn-design/1.1.0") ||
  (identical(design$schema_version, "brohn-design/1.2.0") && identical(design$evidence_mode, "retained_1.1"))
.brohn_study_operational <- function(design) {
  result <- design
  result$evidence_mode <- result$stimulus_assignment <- NULL
  result$method_evidence <- result$method_evidence_implementations <- NULL
  result$schema_version <- "brohn-design/1.0.0"
  result
}
.brohn_study_restore <- function(original, operational) {
  operational$schema_version <- original$schema_version
  for (key in c("evidence_mode", "stimulus_assignment", "method_evidence", "method_evidence_implementations"))
    if (key %in% names(original)) operational[key] <- original[key]
  operational
}

brohn_clone_study_design <- function(design, title = paste(design$title, "copy"),
                                     project_id = design$project_id, evidence_source = NULL,
                                     operation = "clone_design", via = list(kind = "direct_clone")) {
  brohn_validate_study_design(design)
  if (identical(design$schema_version, "brohn-design/1.0.0"))
    return(brohn_clone_design(design, title, project_id))
  operational <- .brohn_study_operational(design)
  retained <- .brohn_study_evidence(design)
  # Task identifiers are local to each study. Keep the complete original task
  # graph when its evidence binds those exact inputs, rather than relabeling it.
  if (retained) operational$blocks <- list()
  result <- brohn_clone_design(operational, title, project_id)
  stimulus_map <- stats::setNames(brohn_ids(result$stimuli), brohn_ids(design$stimuli))
  result <- .brohn_study_restore(design, result)
  result$lineage$design_hash <- brohn_hash(design)
  if (retained) {
    brohn_require(!is.null(evidence_source), "Cloning saved method evidence needs its original source provenance.")
    .brohn_study_check_provenance(evidence_source, design, evidence_source$design_ref$revision)
    result$blocks <- design$blocks
    result$method_evidence <- brohn_method_evidence_inherit(design$method_evidence,
      evidence_source, design$method_evidence$current, operation, via)
    # Same current and all historical resolver references; no supplied code loads.
    brohn_method_evidence_inventory_validate(result$method_evidence_implementations, result$method_evidence)
  }
  if (identical(design$schema_version, "brohn-design/1.2.0")) {
    a <- design$stimulus_assignment
    remap <- function(items, prefix) stats::setNames(vapply(items, function(x) brohn_id(prefix), character(1)), brohn_ids(items))
    concepts <- remap(a$concepts, "concept"); sets <- remap(a$sets, "set"); arms <- remap(a$arms, "arm")
    a$concepts <- lapply(a$concepts, function(x) {x$id <- unname(concepts[[x$id]]); x})
    a$sets <- lapply(a$sets, function(x) {
      x$id <- unname(sets[[x$id]]); x$concept_id <- unname(concepts[[x$concept_id]])
      x$members <- lapply(x$members, function(m) {m$stimulus_id <- unname(stimulus_map[[m$stimulus_id]]); m}); x
    })
    a$arms <- lapply(a$arms, function(x) {
      x$id <- unname(arms[[x$id]])
      x$choices <- lapply(x$choices, function(c) {
        c$set_id <- unname(sets[[c$set_id]]); c$stimulus_id <- unname(stimulus_map[[c$stimulus_id]]); c
      }); x
    })
    result$stimulus_assignment <- a
  }
  brohn_validate_study_design(result)
  result
}

.brohn_study_source_provenance <- function(store, record) {
  .brohn_store_ready(store)
  brohn_require(identical(record$kind, "study") && identical(record$id, record$body$id) &&
    identical(record$project_id, record$body$project_id), "Study record and complete design identity disagree.")
  identity <- DBI::dbGetQuery(store$con, "SELECT value FROM metadata WHERE key='workspace_id'")
  brohn_require(nrow(identity) == 1L && identical(identity$value[[1L]], store$workspace_id),
    "The workspace identity changed. Reopen the study before continuing.")
  row <- DBI::dbGetQuery(store$con,
    "SELECT body_json,body_hash,project_id FROM entity_versions WHERE kind=? AND id=? AND revision=?",
    params = list(record$kind, record$id, record$revision))
  brohn_require(nrow(row) == 1L && identical(row$project_id[[1L]], record$project_id) &&
    .brohn_meb_equal(.brohn_store_decode(row$body_json[[1L]],
    row$body_hash[[1L]]), record$body), "The original study revision changed.")
  list(origin_workspace_id = store$workspace_id,
    design_ref = list(kind = "study", id = record$id, project_id = record$project_id,
      revision = record$revision, body_hash = row$body_hash[[1L]]),
    design_value_hash = brohn_method_evidence_design_value_hash(record$body))
}
.brohn_study_check_provenance <- function(provenance, design, revision) {
  if (!.brohn_study_evidence(design)) {
    brohn_require(is.null(provenance), "A design without saved evidence cannot supply evidence provenance.")
    return(invisible(TRUE))
  }
  .brohn_mea_source(provenance)
  brohn_require(identical(provenance$design_ref$id, design$id) &&
    identical(provenance$design_ref$project_id, design$project_id) &&
    provenance$design_ref$revision == revision &&
    identical(provenance$design_value_hash, brohn_method_evidence_design_value_hash(design)),
    "Evidence provenance disagrees with the complete original study revision.")
  invisible(TRUE)
}
.brohn_study_save_guard <- function(original, draft) {
  brohn_require(identical(original$archived, draft$archived),
    "Use Archive or Restore to change study availability; ordinary Save cannot change recruitment state.")
  # Upgrading a draft to explicit assignment may retain evidence, never erase it.
  allowed <- identical(original$schema_version, draft$schema_version) ||
    (original$schema_version %in% c("brohn-design/1.0.0", "brohn-design/1.1.0") &&
       identical(draft$schema_version, "brohn-design/1.2.0"))
  brohn_require(allowed, "Changing this saved design schema requires an explicit supported draft operation.")
  brohn_require(identical(.brohn_study_evidence(original), .brohn_study_evidence(draft)),
    "Ordinary Save must preserve the study's saved method evidence.")
  if (.brohn_study_evidence(original)) {
    brohn_require(.brohn_meb_equal(original$method_evidence, draft$method_evidence) &&
      .brohn_meb_equal(original$method_evidence_implementations, draft$method_evidence_implementations),
      "Ordinary Save cannot replace saved evidence or its implementation inventory.")
    brohn_require(.brohn_meb_equal(original$blocks, draft$blocks),
      "Changing evidence-bound tasks needs the installed evidence preparation workflow; the saved task was retained.")
  }
  invisible(TRUE)
}

# Explicit research choices; untouched drafts stay in their original schema.
# Adding a show-one group expands existing arms, preserving their earlier choices.
brohn_group_stimuli <- function(design, stimulus_ids, label, selection = "all",
                                allocation = "blocked-arm-sha256/0.1") {
  brohn_validate_study_design(design)
  brohn_require(!isTRUE(design$archived), "Restore this study before changing stimulus assignment.")
  brohn_require(is.character(stimulus_ids) && length(stimulus_ids) >= 2L &&
    !anyNA(stimulus_ids) && !anyDuplicated(stimulus_ids) && all(stimulus_ids %in% brohn_ids(design$stimuli)),
    "Choose at least two distinct existing stimuli for this group.")
  brohn_require(brohn_text(label, 240) && selection %in% c("all", "one") && length(selection) == 1L,
    "Name the group and choose whether each participant sees all versions or one version.")
  brohn_require(is.character(allocation) && length(allocation) == 1L && allocation %in%
    c("blocked-arm-sha256/0.1", "arm-sha256/0.1"), "Choose a supported participant allocation.")
  a <- if (identical(design$schema_version, "brohn-design/1.2.0")) design$stimulus_assignment else
    list(schema = "brohn-stimulus-assignment/0.1", presentation = "selected-stimulus-order/0.1",
      concepts = list(), sets = list(), arms = list(), allocation = "all/0.1")
  grouped <- unlist(lapply(a$sets, function(s) vapply(s$members, `[[`, character(1), "stimulus_id")), use.names = FALSE)
  brohn_require(!any(stimulus_ids %in% grouped), "A selected stimulus already belongs to a group. Keep each stimulus in one group.")
  # Authoring order controls presentation; selection click order must not change it.
  selected <- Filter(function(s) s$id %in% stimulus_ids, design$stimuli)
  concept <- list(id = brohn_id("concept"), label = label)
  set <- list(id = brohn_id("set"), concept_id = concept$id, label = label, selection = selection,
    members = lapply(seq_along(selected), function(i) list(stimulus_id = selected[[i]]$id,
      variant_label = paste0("Version ", i))))
  a$concepts <- c(a$concepts, list(concept)); a$sets <- c(a$sets, list(set))
  if (identical(selection, "one")) {
    old <- if (length(a$arms)) a$arms else list(list(choices = list()))
    brohn_require(length(old) * length(selected) <= 500L, "This group would exceed 500 complete participant assignments.")
    arms <- list()
    for (arm in old) for (member in set$members) {
      n <- length(arms) + 1L
      arms[[n]] <- list(id = brohn_id("arm"), label = paste("Participant group", n),
        choices = c(arm$choices, list(list(set_id = set$id, stimulus_id = member$stimulus_id))))
    }
    a$arms <- arms
    if (identical(a$allocation, "all/0.1")) a$allocation <- allocation
  }
  if (!identical(design$schema_version, "brohn-design/1.2.0")) {
    design$evidence_mode <- if (.brohn_study_evidence(design)) "retained_1.1" else "none"
    design$schema_version <- "brohn-design/1.2.0"
  }
  design$stimulus_assignment <- a
  # Validates every arm and the original paired comparison plan; never prunes it.
  brohn_validate_study_design(design)
  design
}

brohn_add_study_stimulus_version <- function(design, stimulus_id, title,
    condition_id = NULL, new_condition_role = "test", assignment = "always") {
  brohn_validate_study_design(design)
  brohn_require(brohn_text(assignment, 96), "Choose who will see the new version.")
  base <- brohn_add_stimulus_version(.brohn_study_operational(design), stimulus_id,
    title, condition_id, new_condition_role)
  result <- .brohn_study_restore(design, base)
  if (!identical(assignment, "always")) {
    brohn_require(identical(design$schema_version, "brohn-design/1.2.0"), "Create a version group before assigning its new member.")
    a <- result$stimulus_assignment; i <- match(assignment, brohn_ids(a$sets))
    brohn_require(!is.na(i), "Choose a current version group.")
    s <- a$sets[[i]]
    brohn_require(stimulus_id %in% vapply(s$members, `[[`, character(1), "stimulus_id"),
      "The selected group must contain the original stimulus.")
    version <- result$stimuli[[length(result$stimuli)]]
    existing_labels <- vapply(s$members, `[[`, character(1), "variant_label")
    number <- length(s$members) + 1L
    while (paste("Version", number) %in% existing_labels) number <- number + 1L
    s$members <- c(s$members, list(list(stimulus_id = version$id, variant_label = paste("Version", number))))
    if (identical(s$selection, "one")) {
      # Add the new choice once for each existing combination of other groups.
      # Existing authored correlations and complete choice order stay intact.
      contexts <- character(); extra <- list()
      for (arm in a$arms) {
        j <- match(s$id, vapply(arm$choices, `[[`, character(1), "set_id"))
        fingerprint <- brohn_hash(arm$choices[-j])
        if (fingerprint %in% contexts) next
        contexts <- c(contexts, fingerprint)
        choices <- arm$choices; choices[[j]]$stimulus_id <- version$id
        extra[[length(extra)+1L]] <- list(id = brohn_id("arm"),
          label = paste("Participant group", length(a$arms)+length(extra)+1L), choices = choices)
      }
      brohn_require(length(a$arms)+length(extra) <= 500L, "This version would exceed 500 complete participant assignments.")
      a$arms <- c(a$arms, extra)
    }
    a$sets[[i]] <- s; result$stimulus_assignment <- a
  }
  brohn_validate_study_design(result)
  result
}
