# Inactive MaxDiff presentation kernel. Complete source authority, resource
# registration, durable binding and receiver timing remain integration concerns.
.brohn_pvm_key <- function(x) brohn_text(x, 68L) && nchar(x, type = "bytes") == 68L && grepl("^pvm-[a-f0-9]{64}$", x)
.brohn_pvm_lookup <- function(items, field, value) {
  hits <- Filter(function(x) identical(x[[field, exact = TRUE]], value), items)
  brohn_require(length(hits) == 1L, "Best-worst identity is unavailable in this exact scope.")
  hits[[1L]]
}
.brohn_pvm_validate_map <- function(map) {
  .brohn_pvq_plain(map)
  brohn_fields(map, c("schema", "source_design_hash", "allocation_index", "exercises"), label = "Private best-worst map")
  brohn_require(identical(map$schema, "participant-choice-map/0.1") && .brohn_ph_sha(map$source_design_hash) &&
    brohn_number(map$allocation_index, 1, 1e9, TRUE) && brohn_array(map$exercises) && length(map$exercises) <= 20L,
    "Invalid private best-worst source context.")
  keys <- source_ids <- exercise_ids <- character()
  for (exercise in map$exercises) {
    brohn_fields(exercise, c("source_id", "exercise_key", "items", "trials"), label = "Private best-worst exercise")
    brohn_require(brohn_valid_id(exercise$source_id) && .brohn_pvm_key(exercise$exercise_key) &&
      brohn_array(exercise$items) && length(exercise$items) >= 3L && length(exercise$items) <= 60L &&
      brohn_array(exercise$trials) && length(exercise$trials) >= 1L && length(exercise$trials) <= 200L,
      "Invalid private best-worst exercise.")
    keys <- c(keys, exercise$exercise_key); exercise_ids <- c(exercise_ids, exercise$source_id)
    item_ids <- trial_ids <- set_ids <- character(); offered <- character()
    for (item in exercise$items) {
      brohn_fields(item, c("source_id", "item_key"), label = "Private best-worst item")
      brohn_require(brohn_valid_id(item$source_id) && .brohn_pvm_key(item$item_key), "Invalid private best-worst item.")
      item_ids <- c(item_ids, item$source_id); keys <- c(keys, item$item_key)
    }
    brohn_require(!anyDuplicated(item_ids), "Private best-worst item identities repeat.")
    for (trial in exercise$trials) {
      brohn_fields(trial, c("source_set_id", "set_key", "source_trial_id", "trial_key", "source_choice_hash", "required", "item_order"), label = "Private best-worst trial")
      brohn_require(brohn_valid_id(trial$source_set_id) && brohn_text(trial$source_trial_id, 160L) &&
        .brohn_pvm_key(trial$set_key) && .brohn_pvm_key(trial$trial_key) && .brohn_ph_sha(trial$source_choice_hash) &&
        is.logical(trial$required) && length(trial$required) == 1L && !is.na(trial$required) &&
        brohn_array(trial$item_order) && length(trial$item_order) >= 3L && length(trial$item_order) <= 8L &&
        all(vapply(trial$item_order, brohn_valid_id, logical(1))), "Invalid private best-worst trial.")
      order <- unlist(trial$item_order, use.names = FALSE)
      brohn_require(!anyDuplicated(order) && all(order %in% item_ids), "Private best-worst trial has unknown or repeated offered items.")
      offered <- c(offered, order); trial_ids <- c(trial_ids, trial$source_trial_id); set_ids <- c(set_ids, trial$source_set_id)
      keys <- c(keys, trial$set_key, trial$trial_key)
    }
    brohn_require(!anyDuplicated(trial_ids) && !anyDuplicated(set_ids) && setequal(offered, item_ids),
      "Private best-worst map repeats trials/sets or retains unoffered items.")
    source_ids <- c(source_ids, exercise$source_id, item_ids, set_ids, trial_ids)
  }
  brohn_require(!anyDuplicated(keys) && !anyDuplicated(exercise_ids) && !any(keys %in% source_ids),
    "Private best-worst map repeats a key, exercise or original identity.")
  invisible(map)
}

brohn_participant_choice_map <- function(protocol) {
  .brohn_pvq_plain(protocol)
  brohn_validate_saved_variant_protocol(protocol)
  .brohn_pvm_map_validated(protocol)
}
.brohn_pvm_map_validated <- function(protocol) {
  # Internal composition seam: only after complete saved1.2 admission by the
  # public entry or complete-view projector. Never a caller-provided valid flag.
  choices <- lapply(Filter(function(s) identical(s$type, "maxdiff"), protocol$timeline), function(s) s$choice)
  source_ids <- unique(unlist(lapply(choices, function(c) c(c$exercise_id, c$set_id, c$trial_id, unlist(c$item_order))), use.names = FALSE))
  used <- new.env(parent = emptyenv(), hash = TRUE)
  for (id in source_ids) assign(id, TRUE, envir = used)
  key <- function() {
    k <- paste0("pvm-", brohn_token())
    brohn_require(.brohn_pvm_key(k) && !exists(k, envir = used, inherits = FALSE), "Best-worst key collision; no map was created.")
    assign(k, TRUE, envir = used); k
  }
  ids <- unique(vapply(choices, function(c) c$exercise_id, character(1)))
  exercises <- lapply(ids, function(id) {
    rows <- Filter(function(c) identical(c$exercise_id, id), choices)
    offered <- unique(unlist(lapply(rows, function(c) c$item_order), use.names = FALSE))
    list(source_id = id, exercise_key = key(), items = lapply(offered, function(id) list(source_id = id, item_key = key())),
      trials = lapply(rows, function(c) list(source_set_id = c$set_id, set_key = key(), source_trial_id = c$trial_id,
        trial_key = key(), source_choice_hash = .brohn_ph_hash(c), required = c$required, item_order = c$item_order)))
  })
  result <- list(schema = "participant-choice-map/0.1", source_design_hash = protocol$design_hash,
    allocation_index = protocol$allocation_index, exercises = exercises)
  .brohn_pvm_validate_map(result); result
}

brohn_project_participant_choice <- function(choice, map, register_resource = NULL) {
  .brohn_pvm_validate_map(map); .brohn_pvq_plain(choice)
  brohn_fields(choice, c("exercise_id", "design_hash", "set_id", "trial_id", "position", "item_order", "items", "prompt", "best_label", "worst_label", "required"), label = "Original best-worst choice")
  exercise <- .brohn_pvm_lookup(map$exercises, "source_id", choice$exercise_id)
  trial <- .brohn_pvm_lookup(exercise$trials, "source_trial_id", choice$trial_id)
  brohn_require(identical(.brohn_ph_hash(choice), trial$source_choice_hash) &&
    identical(choice$set_id, trial$source_set_id) && identical(choice$required, trial$required) &&
    identical(choice$item_order, trial$item_order), "Best-worst screen differs from its exact mapped source.")
  item_key <- function(id) .brohn_pvm_lookup(exercise$items, "source_id", id)$item_key
  items <- lapply(choice$items, function(item) {
    result <- list(item_key = item_key(item$id), label = item$label)
    if ("illustration" %in% names(item)) {
      brohn_require(is.function(register_resource), "This best-worst illustration needs its assigned resource registrar.")
      brohn_validate_illustration(item$illustration)
      resource <- register_resource(item$illustration$asset)
      brohn_require(brohn_text(resource, 68L) && nchar(resource, type = "bytes") == 68L && grepl("^pvr-[a-f0-9]{64}$", resource),
        "The illustration registrar did not return a participant resource key.")
      result$illustration <- list(resource_key = resource, image_alt = item$illustration$image_alt)
    }
    result
  })
  list(exercise_key = exercise$exercise_key, set_key = trial$set_key, trial_key = trial$trial_key,
    position = choice$position, item_order = lapply(choice$item_order, item_key), items = items,
    prompt = choice$prompt, best_label = choice$best_label, worst_label = choice$worst_label, required = choice$required)
}

brohn_translate_participant_choice <- function(map, trial_key, value, direction = c("to_source", "to_view"), stage = c("answer", "draft")) {
  direction <- match.arg(direction); stage <- match.arg(stage)
  .brohn_pvm_validate_map(map); .brohn_pvq_plain(value)
  brohn_require(.brohn_pvm_key(trial_key), "Choose an exact participant choice trial.")
  matches <- Filter(function(exercise) any(vapply(exercise$trials, function(t) identical(t$trial_key, trial_key), logical(1))), map$exercises)
  brohn_require(length(matches) == 1L, "Best-worst trial is unavailable in this map.")
  exercise <- matches[[1L]]; trial <- .brohn_pvm_lookup(exercise$trials, "trial_key", trial_key)
  if (is.null(value)) {
    brohn_require(stage == "draft" || !trial$required, "This best-worst set requires a complete answer.")
    return(NULL)
  }
  from <- if (direction == "to_source") c("best_key", "worst_key") else c("best_id", "worst_id")
  to <- if (direction == "to_source") c("best_id", "worst_id") else c("best_key", "worst_key")
  brohn_fields(value, from, label = "Best-worst response mapping")
  result <- lapply(from, function(field) {
    x <- value[[field, exact = TRUE]]
    if (is.null(x)) return(NULL)
    brohn_require(if (direction == "to_source") .brohn_pvm_key(x) else brohn_valid_id(x), "Best-worst selection must be a scalar identity.")
    item <- .brohn_pvm_lookup(exercise$items, if (direction == "to_source") "item_key" else "source_id", x)
    brohn_require(item$source_id %in% unlist(trial$item_order, use.names = FALSE), "Best-worst item was not offered in this trial.")
    if (direction == "to_source") item$source_id else item$item_key
  })
  names(result) <- to
  complete <- !vapply(result, is.null, logical(1))
  brohn_require(stage == "draft" || all(complete), "A submitted best-worst answer needs both choices; use null only for an optional skip.")
  brohn_require(!all(complete) || !identical(result[[1L]], result[[2L]]), "Best and worst must be different offered items.")
  result
}
