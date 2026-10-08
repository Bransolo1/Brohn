# Inactive pure projection/translation. No loader, renderer or receiver changes.
.brohn_pvt_profiles <- c("iat-gnb2003-d1/1.0", "biat-nosek2014-goodfocal/1.0", "aat-keyboard-cue-balanced/1.0",
  "rt-deary-liewald-simple/1.0", "rt-deary-liewald-choice/1.0", "sciat-brohn-response-window-im100/1.0", "gnat-brohn-single-target/1.0")
.brohn_pvt_get <- function(x, name) x[[name, exact = TRUE]]
.brohn_pvt_key <- function(x, prefix = "pvt") brohn_text(x, 68L) && nchar(x, type = "bytes") == 68L &&
  grepl(paste0("^", prefix, "-[a-f0-9]{64}$"), x)
.brohn_pvt_sha <- function(x) brohn_text(x, 64L) && nchar(x, type = "bytes") == 64L && grepl("^[a-f0-9]{64}$", x)
.brohn_pvt_plain <- function(x) {
  .brohn_vad_domain(x)
  brohn_require(nchar(brohn_json(x), type = "bytes") <= 16 * 1024^2, "Task projection exceeds its original16MiB bound.")
  invisible(TRUE)
}
.brohn_pvt_bool <- function(x) is.logical(x) && length(x) == 1L && !is.na(x)
.brohn_pvt_special <- function(profile) profile %in% .brohn_pvt_profiles[6:7]
.brohn_pvt_lookup <- function(rows, field, value) {
  matches <- Filter(function(x) identical(.brohn_pvt_get(x, field), value), rows)
  brohn_require(length(matches) == 1L, "Task identity is unavailable in this scope."); matches[[1L]]
}
.brohn_pvt_trial_fields <- function(profile) {
  common <- c("mode", "allowed_codes", "correct_code", "timeout_ms", "foreperiod_ms", "box_count", "position", "material", "forced_correction", "intertrial_ms")
  if (profile %in% .brohn_pvt_profiles[1:2]) return(c(common, "left_label", "right_label"))
  if (profile == .brohn_pvt_profiles[[3L]]) return(c(common, "cue", "action", "zoom_duration_ms"))
  if (profile %in% .brohn_pvt_profiles[4:5]) return(common)
  if (profile == .brohn_pvt_profiles[[6L]]) return(c("task_profile", "forced_correction", "timeout_ms", "response_feedback_ms", "omission_feedback_ms", "post_feedback_blank_ms", "correct_code", "left_label", "right_label", "material"))
  c("task_profile", "mode", "expected_action", "phase", "timeout_ms", "feedback_ms", "offset_to_next_onset_min_ms", "forced_correction", "allowed_codes", "go_labels", "material")
}

.brohn_pvt_validate_map <- function(map) {
  .brohn_pvt_plain(map)
  brohn_fields(map, c("schema", "task_id", "task_key", "profile", "source_design_hash", "allocation_index", "procedure", "blocks", "steps", "materials"), label = "Private task map")
  brohn_require(identical(map$schema, "participant-task-map/0.1") && brohn_text(map$task_id, 240) &&
    .brohn_pvt_key(map$task_key) && brohn_text(map$profile, 96) && map$profile %in% .brohn_pvt_profiles &&
    .brohn_pvt_sha(map$source_design_hash) && brohn_number(map$allocation_index, 1, 1e9, TRUE), "Unsupported private task map.")
  keys <- map$task_key; source_ids <- map$task_id
  for (field in c("blocks", "steps", "materials")) brohn_require(brohn_array(map[[field]]) && length(map[[field]]) <= 20000L, "Task map exceeds its declared shape.")
  brohn_require(length(map$blocks) > 0L && length(map$steps) > 0L, "Task map has no complete timeline.")
  for (b in map$blocks) {
    brohn_fields(b, c("source_id", "key"), label = "Private task block")
    brohn_require(brohn_text(b$source_id, 240) && .brohn_pvt_key(b$key), "Invalid task block identity.")
    keys <- c(keys, b$key); source_ids <- c(source_ids, b$source_id)
  }
  for (s in map$steps) {
    brohn_fields(s, c("source_id", "key", "type", "block_id", "block_key"), label = "Private task step")
    brohn_require(brohn_text(s$source_id, 240) && .brohn_pvt_key(s$key) && brohn_text(s$type, 40) &&
      s$type %in% c("task_instructions", "task_trial"), "Invalid task step identity.")
    b <- .brohn_pvt_lookup(map$blocks, "source_id", s$block_id)
    brohn_require(identical(s$block_key, b$key), "Task step changed its block binding.")
    keys <- c(keys, s$key); source_ids <- c(source_ids, s$source_id)
  }
  resource_keys <- character(); descriptors <- list()
  for (m in map$materials) {
    brohn_fields(m, c("source_id", "key", "resource_key", "asset"), label = "Private task material")
    brohn_require(brohn_text(m$source_id, 240) && .brohn_pvt_key(m$key), "Invalid task material identity.")
    if (is.null(m$resource_key)) brohn_require(is.null(m$asset), "Text material cannot hide a registered asset.") else {
      brohn_require(.brohn_pvt_key(m$resource_key, "pvr") && is.list(m$asset) && !is.null(names(m$asset)), "Invalid task resource registration.")
      brohn_fields(m$asset, c("hash", "size", "media_type"), c("filename", "width", "height"), "Private original task asset")
      brohn_require(.brohn_pvt_sha(m$asset$hash) && brohn_number(m$asset$size, 1, 20 * 1024^2, TRUE) &&
        brohn_text(m$asset$media_type, 64) && m$asset$media_type %in% c("image/png", "image/jpeg", "image/webp"), "Invalid original task asset descriptor.")
      previous <- match(m$resource_key, resource_keys)
      if (!is.na(previous)) brohn_require(identical(brohn_json(descriptors[[previous]]), brohn_json(m$asset)), "A resource key changed its original descriptor.") else {
        resource_keys <- c(resource_keys, m$resource_key); descriptors[[length(descriptors) + 1L]] <- m$asset
      }
    }
    keys <- c(keys, m$key); source_ids <- c(source_ids, m$source_id)
  }
  for (field in c("blocks", "steps", "materials")) brohn_require(!anyDuplicated(vapply(map[[field]], `[[`, character(1), "source_id")), "Task map repeats a scoped source identity.")
  if (.brohn_pvt_special(map$profile)) {
    brohn_fields(map$procedure, c("source_hash", "token"), label = "Private procedure token")
    brohn_require(.brohn_pvt_sha(map$procedure$source_hash) && .brohn_pvt_key(map$procedure$token, "pvp"), "Invalid procedure registration.")
    keys <- c(keys, map$procedure$token)
  } else brohn_require(is.null(map$procedure), "This task profile cannot acquire a procedure token.")
  keys <- c(keys, resource_keys)
  brohn_require(!anyDuplicated(keys) && !any(keys %in% source_ids), "Task public keys collide or reuse a source identity.")
  invisible(map)
}

brohn_project_participant_task <- function(compiled, source_block, allocation_index, resource_key = NULL, procedure_token = NULL) {
  .brohn_pvt_plain(compiled); .brohn_pvt_plain(source_block)
  brohn_validate_saved_task_table(compiled, source_block, allocation_index)
  brohn_require(brohn_text(compiled$profile, 96) && compiled$profile %in% .brohn_pvt_profiles, "Unsupported task renderer registration.")
  .brohn_pvt_project_validated(compiled, source_block, allocation_index, resource_key, procedure_token)
}

.brohn_pvt_project_validated <- function(compiled, source_block, allocation_index, resource_key, procedure_token) {
  used <- new.env(parent = emptyenv(), hash = TRUE)
  source_ids <- unique(c(compiled$id, brohn_ids(compiled$blocks), brohn_ids(compiled$timeline), brohn_ids(source_block$materials), brohn_ids(source_block$categories)))
  for (id in source_ids) assign(id, TRUE, envir = used)
  reserve <- function(value, prefix) {
    brohn_require(.brohn_pvt_key(value, prefix) && !exists(value, used, inherits = FALSE), "Task key collision; no projection was created.")
    assign(value, TRUE, envir = used); value
  }
  key <- function() reserve(paste0("pvt-", brohn_token()), "pvt")
  procedure <- NULL
  if (.brohn_pvt_special(compiled$profile)) {
    brohn_require(is.function(procedure_token), "A registered procedure-token callback is required.")
    token <- reserve(procedure_token(compiled$procedure_hash, compiled$id, compiled$profile), "pvp")
    procedure <- list(source_hash = compiled$procedure_hash, token = token)
  }
  blocks <- lapply(compiled$blocks, function(b) list(source_id = b$id, key = key()))
  steps <- lapply(compiled$timeline, function(s) list(source_id = s$id, key = key(), type = s$type,
    block_id = s$block_id, block_key = .brohn_pvt_lookup(blocks, "source_id", s$block_id)$key))
  material_ids <- unique(vapply(Filter(function(s) !is.null(s$material), compiled$timeline), function(s) s$material$id, character(1)))
  material_entries <- list(); resource_descriptors <- list()
  for (id in material_ids) {
    m <- .brohn_pvt_lookup(source_block$materials, "id", id); resource <- NULL; asset <- NULL
    brohn_require(brohn_text(m$type, 16) && m$type %in% c("text", "image"), "Task material type must be a registered scalar string.")
    if (identical(m$type, "image")) {
      brohn_require(is.function(resource_key), "An assigned task-image resource callback is required.")
      resource <- resource_key(m$asset, compiled$id, m$id)
      brohn_require(.brohn_pvt_key(resource, "pvr"), "Invalid assigned task resource key.")
      previous <- resource_descriptors[[resource, exact = TRUE]]
      if (is.null(previous)) { reserve(resource, "pvr"); resource_descriptors[[resource]] <- m$asset } else
        brohn_require(identical(brohn_json(previous), brohn_json(m$asset)), "A resource key changed its original descriptor.")
      asset <- m$asset
    }
    material_entries[[length(material_entries) + 1L]] <- list(source_id = id, key = key(), resource_key = resource, asset = asset)
  }
  map <- list(schema = "participant-task-map/0.1", task_id = compiled$id, task_key = key(), profile = compiled$profile,
    source_design_hash = compiled$design_hash, allocation_index = allocation_index, procedure = procedure,
    blocks = blocks, steps = steps, materials = material_entries)
  .brohn_pvt_validate_map(map)
  view <- .brohn_pvt_render_mapped_validated(compiled, map)
  list(view = view, private_map = map)
}

.brohn_pvt_render_mapped_validated <- function(compiled, map) {
  procedure <- map[["procedure", exact = TRUE]]
  material_view <- function(m) {
    if (is.null(m)) return(NULL)
    binding <- .brohn_pvt_lookup(map$materials, "source_id", m$id)
    if (identical(m$type, "text")) return(list(material_key = binding$key, type = "text", content = m$content))
    alt <- if ("image_alt" %in% names(m)) m$image_alt else if (nzchar(m$content)) m$content else "Task image"
    list(material_key = binding$key, type = "image", image_alt = alt, resource_key = binding$resource_key)
  }
  timeline <- lapply(seq_along(compiled$timeline), function(i) {
    s <- compiled$timeline[[i]]; b <- map$steps[[i]]
    result <- list(task_step_key = b$key, type = s$type, block_key = b$block_key)
    if (identical(s$type, "task_instructions")) {
      result$text <- s$text
      if (compiled$profile == .brohn_pvt_profiles[[7L]]) result$phase <- s$phase
    } else {
      result <- c(result, s[.brohn_pvt_trial_fields(compiled$profile)])
      result["material"] <- list(material_view(s$material))
      if (compiled$profile == .brohn_pvt_profiles[[7L]]) {
        brohn_require(is.null(s$round_id) || identical(s$round_id, "r1") || identical(s$round_id, "r2"), "Unknown GNAT semantic round.")
        result["round"] <- list(if (is.null(s$round_id)) NULL else if (s$round_id == "r1") 1L else 2L)
      }
    }
    result
  })
  view <- list(task_key = map$task_key, profile = map$profile, title = compiled$title, timeline = timeline)
  if (!is.null(procedure)) view$procedure_token <- procedure$token
  .brohn_pvt_plain(view)
  view
}

.brohn_pvt_clock_shape <- function(clock) {
  brohn_fields(clock, c("id", "unit", "value", "instance_id", "time_origin_ms"), label = "Task observed clock")
  brohn_require(identical(clock$id, "browser-monotonic") && identical(clock$unit, "ms") && brohn_text(clock$instance_id, 128) &&
    brohn_text(clock$value, 64) && grepl("^[0-9]+([.][0-9]+)?$", clock$value) &&
    brohn_text(clock$time_origin_ms, 64) && grepl("^[0-9]+([.][0-9]+)?$", clock$time_origin_ms), "Task clock shape differs from its source.")
}
.brohn_pvt_observation_shape <- function(data, kind, profile) {
  special <- .brohn_pvt_special(profile); gnat <- profile == .brohn_pvt_profiles[[7L]]
  .brohn_pvt_clock_shape(data$clock)
  numeric_fields <- c("observed_foreperiod_ms", "scheduled_foreperiod_ms", "observed_gap_since_previous_response_ms", "first_response_ms", "final_correct_ms", "onset_ms", "foreperiod_start_ms", "anticipatory_count", "frame_count", "max_frame_gap_ms", "zoom_feedback_observed_ms", "response_ms", "deadline_ms", "response_closed_ms", "feedback_start_ms", "feedback_end_ms", "blank_end_ms", "deadline_timer_ms", "deadline_frame_ms")
  for (field in intersect(names(data), numeric_fields)) brohn_require(is.null(data[[field]]) || brohn_number(data[[field]]), "Task observed number changed type.")
  for (field in intersect(names(data), c("first_correct", "correct", "visible", "focused"))) brohn_require(is.null(data[[field]]) || .brohn_pvt_bool(data[[field]]), "Task observed flag changed type.")
  for (field in intersect(names(data), c("outcome", "response_outcome", "response_code", "final_code", "clock_instance_id", "interruption_reason", "reason", "timing_reference")))
    brohn_require(is.null(data[[field]]) || brohn_text(data[[field]], 500, TRUE), "Task observed text changed type.")
  numbers <- function(x, fields) { brohn_fields(x, fields, label = "Task observation"); brohn_require(all(vapply(x, brohn_number, logical(1))), "Task geometry must contain actual numbers.") }
  if ("viewport" %in% names(data)) numbers(data$viewport, c("width", "height", "device_pixel_ratio"))
  if ("stimulus_rect" %in% names(data)) numbers(data$stimulus_rect, c("x", "y", "width", "height"))
  strings <- function(x, maximum) brohn_require(brohn_array(x) && length(x) <= maximum && all(vapply(x, brohn_text, logical(1), max = 64)), "Task key list is invalid.")
  if ("held_codes" %in% names(data)) strings(data$held_codes, if (gnat) 128L else 2L)
  visibility <- function(rows) {
    brohn_require(brohn_array(rows) && length(rows) <= 1000L, "Task visibility evidence exceeds its shape.")
    for (v in rows) { brohn_fields(v, c("observed_ms", "visible", "focused"), label = "Task visibility"); brohn_require(brohn_number(v$observed_ms) && .brohn_pvt_bool(v$visible) && .brohn_pvt_bool(v$focused), "Invalid task visibility types.") }
  }
  key <- function(k, raw = FALSE) {
    fields <- if (!special) c("code", "clock", "rt_ms", "accepted", "phase", "correct", "ignored_reason") else
      c("type", "code", "event_ms", "observed_ms", "repeat", "trusted", "modifiers", if (!raw) c("response_open", "accepted", "ignored_reason"))
    brohn_fields(k, fields, label = "Task key evidence")
    brohn_require(brohn_text(k$code, 64), "Task semantic key code changed type.")
    if (!special) {
      .brohn_pvt_clock_shape(k$clock)
      brohn_require((is.null(k$rt_ms) || brohn_number(k$rt_ms)) && .brohn_pvt_bool(k$accepted) && .brohn_pvt_bool(k$correct) && brohn_text(k$phase, 40), "Invalid classic key types.")
    } else {
      brohn_require(brohn_text(k$type, 8) && k$type %in% c("down", "up") && brohn_number(k$event_ms) && brohn_number(k$observed_ms) &&
        .brohn_pvt_bool(k[["repeat", exact = TRUE]]) && .brohn_pvt_bool(k$trusted) && .brohn_pvt_bool(k$modifiers), "Invalid task key types.")
      if (!raw) brohn_require(.brohn_pvt_bool(k$response_open) && .brohn_pvt_bool(k$accepted), "Invalid task response flags.")
    }
    if ("ignored_reason" %in% names(k)) brohn_require(is.null(k$ignored_reason) || brohn_text(k$ignored_reason, 500), "Invalid task ignored reason.")
  }
  list_keys <- function(rows, raw = FALSE) {
    brohn_require(brohn_array(rows) && length(rows) <= if (special) 5000L else 2000L, "Task key evidence exceeds its shape.")
    for (k in rows) key(k, raw)
  }
  if ("keypresses" %in% names(data)) list_keys(data$keypresses)
  if ("keys" %in% names(data)) list_keys(data$keys)
  if ("visibility" %in% names(data)) visibility(data$visibility)
  if ("release_wait" %in% names(data) && !is.null(data$release_wait)) {
    w <- data$release_wait; brohn_fields(w, c("start_ms", "end_ms", "held_codes", "keys", "visibility"), label = "GNAT release wait")
    brohn_require(brohn_number(w$start_ms) && (is.null(w$end_ms) || brohn_number(w$end_ms)), "Invalid release wait times.")
    strings(w$held_codes, 128L); list_keys(w$keys, TRUE); visibility(w$visibility)
  }
  if ("contradiction" %in% names(data) && !is.null(data$contradiction)) key(data$contradiction$key)
  invisible(TRUE)
}

.brohn_pvt_event_fields <- function(profile, kind) {
  special <- .brohn_pvt_special(profile); gnat <- profile == .brohn_pvt_profiles[[7L]]
  identity <- c("task_id", if (kind %in% c("task_instructions", "task_interrupted")) "step_id" else "trial_id", if (kind != "task_interrupted") "block_id", if (special) "procedure_hash", "clock")
  required <- switch(kind,
    task_instructions = character(), task_interrupted = "reason",
    task_trial_started = if (special) c("held_codes", "timing_reference", "viewport", "stimulus_rect", if (gnat) c("release_wait", "visible", "focused")) else c("observed_foreperiod_ms", "scheduled_foreperiod_ms", "observed_gap_since_previous_response_ms", "timing_reference", "viewport", "stimulus_rect"),
    task_trial_finished = if (special) c("outcome", "response_outcome", "response_code", "response_ms", "correct", "onset_ms", "deadline_ms", "response_closed_ms", "feedback_start_ms", "feedback_end_ms", "blank_end_ms", "keys", "interruption_reason", "frame_count", "max_frame_gap_ms", if (gnat) c("deadline_timer_ms", "deadline_frame_ms", "visibility")) else c("outcome", "response_code", "final_code", "first_correct", "first_response_ms", "final_correct_ms", "clock_instance_id", "onset_ms", "foreperiod_start_ms", "observed_foreperiod_ms", "anticipatory_count", "keypresses", "frame_count", "max_frame_gap_ms"))
  optional <- if (kind == "task_interrupted" && gnat) c("contradiction", "release_wait") else if (kind == "task_trial_finished" && profile == .brohn_pvt_profiles[[3L]]) "zoom_feedback_observed_ms" else character()
  list(required = c(identity, required), optional = optional)
}
brohn_translate_participant_task_data <- function(private_map, kind, data, direction = c("to_source", "to_view"), sealed_trial_keys) {
  direction <- match.arg(direction); .brohn_pvt_validate_map(private_map); .brohn_pvt_plain(data)
  map <- private_map; incoming <- identical(direction, "to_source")
  brohn_require(brohn_text(kind, 40) && kind %in% c("task_instructions", "task_trial_started", "task_trial_finished", "task_interrupted"), "Unsupported task evidence kind.")
  rename <- c(task_id = "task_key", step_id = "task_step_key", trial_id = "trial_key", block_id = "block_key", procedure_hash = "procedure_token")
  public_names <- function(fields) vapply(fields, function(n) if (n %in% names(rename)) rename[[n]] else n, character(1), USE.NAMES = FALSE)
  fields <- .brohn_pvt_event_fields(map$profile, kind)
  brohn_fields(data, if (incoming) public_names(fields$required) else fields$required, fields$optional, "Task evidence data")
  result <- data
  for (source in intersect(names(rename), fields$required)) {
    from <- if (incoming) rename[[source]] else source; to <- if (incoming) source else rename[[source]]; value <- data[[from, exact = TRUE]]
    converted <- if (source == "task_id") {
      brohn_require(identical(value, if (incoming) map$task_key else map$task_id), "Task evidence belongs to another task."); if (incoming) map$task_id else map$task_key
    } else if (source == "procedure_hash") {
      brohn_require(identical(value, if (incoming) map$procedure$token else map$procedure$source_hash), "Task evidence belongs to another procedure."); if (incoming) map$procedure$source_hash else map$procedure$token
    } else if (is.null(value) && kind == "task_interrupted" && source == "step_id") NULL else {
      rows <- if (source == "block_id") map$blocks else map$steps
      row <- .brohn_pvt_lookup(rows, if (incoming) "key" else "source_id", value)
      if (source == "trial_id") brohn_require(identical(row$type, "task_trial"), "Trial evidence requires a trial key.")
      if (source == "step_id" && kind == "task_instructions") brohn_require(identical(row$type, "task_instructions"), "Instruction evidence requires an instruction key.")
      if (incoming) row$source_id else row$key
    }
    names(result)[names(result) == from] <- to; result[to] <- list(converted)
  }
  source_data <- if (incoming) result else data
  if ("block_id" %in% names(source_data)) {
    id <- .brohn_pvt_get(source_data, if (kind == "task_instructions") "step_id" else "trial_id")
    brohn_require(identical(.brohn_pvt_lookup(map$steps, "source_id", id)$block_id, source_data$block_id), "Task evidence changed its step/block association.")
  }
  if ("contradiction" %in% names(data) && !is.null(data$contradiction)) {
    c <- data$contradiction; brohn_fields(c, c(if (incoming) "trial_key" else "trial_id", "key"), label = "GNAT contradiction")
    brohn_require(!missing(sealed_trial_keys), "GNAT contradiction requires caller-retained sealed trial membership.")
    .brohn_pvt_plain(sealed_trial_keys)
    brohn_require(brohn_array(sealed_trial_keys) && length(sealed_trial_keys) <= length(map$steps) && !anyDuplicated(unlist(sealed_trial_keys)), "Invalid sealed trial key list.")
    for (k in sealed_trial_keys) brohn_require(identical(.brohn_pvt_lookup(map$steps, "key", k)$type, "task_trial"), "Sealed membership contains a nontrial key.")
    row <- .brohn_pvt_lookup(map$steps, if (incoming) "key" else "source_id", c[[if (incoming) "trial_key" else "trial_id", exact = TRUE]])
    brohn_require(identical(row$type, "task_trial") && row$key %in% unlist(sealed_trial_keys) && identical(source_data$step_id, row$source_id), "GNAT contradiction must name its actual sealed trial.")
    result$contradiction <- setNames(list(if (incoming) row$source_id else row$key, c$key), c(if (incoming) "trial_id" else "trial_key", "key"))
  }
  .brohn_pvt_observation_shape(source_data, kind, map$profile)
  result
}

brohn_translate_participant_task_checkpoint <- function(private_map, checkpoint, direction = c("to_source", "to_view")) {
  direction <- match.arg(direction); .brohn_pvt_validate_map(private_map); .brohn_pvt_plain(checkpoint)
  map <- private_map; incoming <- identical(direction, "to_source")
  source <- c("task_id", "step_id", "resumable", "phase", "last_completed_trial_id")
  public <- c("task_key", "task_step_key", "resumable", "phase", "last_completed_trial_key")
  brohn_fields(checkpoint, if (incoming) public else source, label = "Task checkpoint")
  value <- setNames(checkpoint[if (incoming) public else source], source)
  brohn_require(identical(value$task_id, if (incoming) map$task_key else map$task_id) && .brohn_pvt_bool(value$resumable) &&
    brohn_text(value$phase, 40) && value$phase %in% c("instructions", "timed"), "Invalid task checkpoint context.")
  row <- .brohn_pvt_lookup(map$steps, if (incoming) "key" else "source_id", value$step_id)
  brohn_require(identical(row$type, if (value$phase == "instructions") "task_instructions" else "task_trial") &&
    identical(value$resumable, value$phase == "instructions" && !.brohn_pvt_special(map$profile)), "Task checkpoint changes the existing resume policy.")
  last <- value$last_completed_trial_id
  if (!is.null(last)) {
    previous <- .brohn_pvt_lookup(map$steps, if (incoming) "key" else "source_id", last)
    brohn_require(identical(previous$type, "task_trial"), "Last completed identity is not a trial.")
    last <- if (incoming) previous$source_id else previous$key
  }
  result <- list(if (incoming) map$task_id else map$task_key, if (incoming) row$source_id else row$key, value$resumable, value$phase, last)
  setNames(result, if (incoming) source else public)
}
