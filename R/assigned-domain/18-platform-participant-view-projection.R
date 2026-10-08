# Inactive pure composition. Source byte authority and durable delivery binding
# are deliberately separate; no public route or legacy loader uses this module.
.brohn_pvc_get <- function(x, name) x[[name, exact = TRUE]]
.brohn_pvc_key <- function(x, prefix = NULL) {
  brohn_text(x, 68L) && nchar(x, type = "bytes") == 68L &&
    grepl(if (is.null(prefix)) "^pv[usioqmvtrp]-[a-f0-9]{64}$" else paste0("^", prefix, "-[a-f0-9]{64}$"), x)
}
.brohn_pvc_lookup <- function(rows, field, value) {
  found <- Filter(function(row) identical(.brohn_pvc_get(row, field), value), rows)
  brohn_require(length(found) == 1L, "Participant presentation has no unique assigned identity.")
  found[[1L]]
}
.brohn_pvc_renderer <- function(value) {
  .brohn_pvq_plain(value)
  brohn_fields(value, c("schema", "id", "manifest_hash"), label = "Participant renderer identity")
  brohn_require(identical(value$schema, "participant-renderer-identity/0.1") &&
    brohn_text(value$id, 120L) && grepl("^[a-z]", value$id) && !grepl("[^a-z0-9./-]", value$id) &&
    .brohn_ph_sha(value$manifest_hash), "Supply the registered renderer identity and manifest digest.")
  invisible(value)
}

brohn_project_participant_view <- function(protocol, source_protocol_hash, renderer_identity) {
  brohn_require(.brohn_ph_sha(source_protocol_hash), "Supply the original protocol-byte SHA256 declaration.")
  .brohn_pvc_renderer(renderer_identity)
  # This is the only admission seam. The private component helpers below do not
  # accept a caller-provided passed/validated flag or replace historical reading.
  brohn_validate_saved_variant_protocol(protocol)
  d <- protocol$design
  used <- new.env(parent = emptyenv(), hash = TRUE)
  reserve_source <- function(x) {
    if (is.list(x)) {
      for (name in names(x)) if (.brohn_pvc_key(name)) assign(name, TRUE, used)
      for (item in x) reserve_source(item)
    } else if (is.character(x) && .brohn_pvc_key(x)) assign(x, TRUE, used)
    invisible(NULL)
  }
  reserve_source(protocol)
  claim <- function(value) {
    brohn_require(.brohn_pvc_key(value) && !exists(value, used, inherits = FALSE),
      "Participant identity collision; no complete presentation was created.")
    assign(value, TRUE, used); value
  }
  key <- function(prefix) claim(paste0(prefix, "-", brohn_token()))
  run_id <- key("pvu")
  steps <- lapply(seq_along(protocol$timeline), function(i) {
    s <- protocol$timeline[[i]]
    list(source_id = s$id, key = key("pvs"), index = i, type = s$type, phase = s$phase,
      stimulus_id = .brohn_pvc_get(s, "stimulus_id"), condition_id = .brohn_pvc_get(s, "condition_id"),
      question_id = if (s$type == "question") s$question$id else NULL,
      occurrence_id = .brohn_pvc_get(s, "questionnaire_occurrence_id"))
  })
  step_key <- function(id) .brohn_pvc_lookup(steps, "source_id", id)$key
  stimuli <- lapply(protocol$realized_stimulus_order, function(id) list(source_id = id, key = key("pvi")))
  stimulus_key <- function(id) if (is.null(id)) NULL else .brohn_pvc_lookup(stimuli, "source_id", id)$key
  occurrences <- lapply(.brohn_pvc_get(protocol, "questionnaire_occurrences"), function(o)
    list(source_id = o$id, key = key("pvo"), scope = o$scope, stimulus_id = o$stimulus_id,
      stimulus_step_id = o$stimulus_step_id, question_step_ids = o$question_step_ids, review_step_id = o$review_step_id))
  occurrence_key <- function(id) .brohn_pvc_lookup(occurrences, "source_id", id)$key
  actual_questions <- vapply(Filter(function(s) s$type == "question", protocol$timeline), function(s) s$question$id, character(1))
  questions <- brohn_participant_question_map(Filter(function(q) q$id %in% actual_questions, d$questions))
  for (q in questions$entries) {
    claim(q$question_key)
    for (o in q$options) claim(o$option_key)
    for (r in q$rows) claim(r$row_key)
  }
  choices <- .brohn_pvm_map_validated(protocol)
  for (exercise in choices$exercises) {
    claim(exercise$exercise_key)
    for (item in exercise$items) claim(item$item_key)
    for (trial in exercise$trials) { claim(trial$set_key); claim(trial$trial_key) }
  }
  resources <- list(); resource_values <- character(); policies <- list(); tasks <- list()
  register_resource <- function(asset, use) {
    # The source reader already checks profile-specific media constraints. The
    # public descriptor has a smaller closed shape; optional dimensions must
    # actually be usable numbers before copying them to the participant.
    brohn_fields(asset, c("hash", "size", "media_type"), c("filename", "width", "height"), "Assigned resource descriptor")
    brohn_require(.brohn_ph_sha(asset$hash) && brohn_number(asset$size, 1, 512 * 1024^2, TRUE) &&
      brohn_text(asset$media_type, 120L), "Assigned resource has invalid source metadata.")
    for (name in intersect(c("width", "height"), names(asset)))
      brohn_require(brohn_number(asset[[name, exact = TRUE]], 1, 2147483647, TRUE), "Assigned resource dimensions must be positive whole pixels.")
    value <- brohn_json(asset); position <- match(value, resource_values)
    if (is.na(position)) {
      position <- length(resources) + 1L
      resources[[position]] <<- list(key = key("pvr"), asset = asset, uses = list())
      resource_values[[position]] <<- value
    }
    entry <- resources[[position]]
    # Repeated exposures remain distinct uses; an identical callback at one use
    # needs only one membership record, never a deployment-wide asset grant.
    if (!any(vapply(entry$uses, function(old) identical(old, use), logical(1))))
      entry$uses[[length(entry$uses) + 1L]] <- use
    resources[[position]] <<- entry
    entry$key
  }
  register_policy <- function(kind, source_hash, outer_step_id = NULL, task_id = NULL, profile = NULL) {
    brohn_require(.brohn_ph_sha(source_hash), "A participant policy needs its original full digest.")
    entry <- list(kind = kind, token = key("pvp"), source_hash = source_hash,
      outer_step_id = outer_step_id, task_id = task_id, profile = profile)
    policies[[length(policies) + 1L]] <<- entry
    entry$token
  }
  public_steps <- lapply(seq_along(protocol$timeline), function(i) {
    s <- protocol$timeline[[i]]
    result <- list(step_key = steps[[i]]$key, type = s$type, phase = s$phase)
    if (s$type %in% c("baseline", "fixation", "stimulus", "question", "questionnaire_review"))
      result["stimulus_key"] <- list(stimulus_key(s$stimulus_id))
    if ("questionnaire_occurrence_id" %in% names(s)) result$occurrence_key <- occurrence_key(s$questionnaire_occurrence_id)
    use <- function(kind, source_id = NULL, parent_id = NULL) list(outer_step_id = s$id, kind = kind, source_id = source_id, parent_id = parent_id)
    if (s$type == "instructions") result$text <- s$text else if (s$type %in% c("baseline", "fixation")) result$duration_ms <- s$duration_ms else if (s$type == "stimulus") {
      material <- s$stimulus
      brohn_require(material$type %in% c("text", "image", "audio", "video"), "This stimulus has no registered participant delivery profile.")
      result$duration_ms <- s$duration_ms
      result$material <- if (material$type == "text") list(type = "text", content = material$content) else {
        m <- list(type = material$type, resource_key = register_resource(material$asset, use("stimulus", material$id)))
        if ("image_alt" %in% names(material)) m$image_alt <- material$image_alt
        m
      }
    } else if (s$type == "question") {
      result$question <- brohn_project_participant_question(s$question, questions,
        function(asset) register_resource(asset, use("question_illustration", s$question$id)))
      result$question_key <- result$question$question_key
      if ("questionnaire" %in% names(s)) result$section_label <- s$questionnaire$section_label
    } else if (s$type == "questionnaire_review") {
      brohn_require("occurrence_key" %in% names(result), "A review screen needs its assigned questionnaire occurrence.")
    } else if (s$type == "maxdiff") {
      result$choice <- brohn_project_participant_choice(s$choice, choices,
        function(asset) register_resource(asset, use("maxdiff_illustration", s$choice$trial_id, s$choice$exercise_id)))
    } else if (s$type == "task") {
      original_block <- .brohn_pvc_lookup(d$blocks, "id", s$task$id)
      projected <- .brohn_pvt_project_validated(s$task, original_block, protocol$allocation_index,
        function(asset, task_id, material_id) register_resource(asset, use("task_material", material_id, task_id)),
        function(hash, task_id, profile) register_policy("task_procedure", hash, s$id, task_id, profile))
      m <- projected$private_map
      claim(m$task_key)
      for (b in m$blocks) claim(b$key)
      for (t in m$steps) claim(t$key)
      for (material in m$materials) claim(material$key)
      tasks[[length(tasks) + 1L]] <<- list(outer_step_id = s$id, map = m)
      result$task <- projected$view
    } else stop("Unsupported saved participant step; no presentation was created.", call. = FALSE)
    result
  })
  navigation <- if (!"questionnaire_occurrences" %in% names(protocol)) NULL else list(
    schema = "participant-navigation/0.1", occurrences = lapply(occurrences, function(o) list(
      occurrence_key = o$key, scope = o$scope,
      stimulus_step_key = if (is.null(o$stimulus_step_id)) NULL else step_key(o$stimulus_step_id),
      question_step_keys = lapply(o$question_step_ids, step_key), review_step_key = step_key(o$review_step_id))))
  equipment <- NULL
  if ("equipment" %in% names(protocol)) {
    original <- protocol$equipment
    equipment <- c(list(schema = "participant-equipment-view/0.1",
      policy_token = register_policy("equipment", original$policy_hash)),
      original[c("camera", "audio", "required_codes", "controls", "freshness_ms", "first_write_wait_ms")])
  }
  camera <- NULL
  if (!is.null(d[["camera", exact = TRUE]])) {
    original <- d$camera
    brohn_require(original$schema %in% c("brohn-camera-policy/1.0", "brohn-camera-policy/1.1"), "Unknown saved camera presentation policy.")
    camera <- c(list(schema = "participant-camera-view/0.1", policy_token = register_policy("camera", .brohn_ph_hash(original)),
      source_policy_version = original$schema), original[c("required", "audio", "consent_text", "retention_text",
        "width", "height", "frame_rate", "max_duration_s", "max_bytes")])
    camera$analysis <- if (original$schema == "brohn-camera-policy/1.0") list(mode = "legacy_recording", profile = original$analysis_profile) else
      c(list(mode = "named_facial_1.1", notice = original$analysis_notice), original$analysis_settings[c("start_s", "end_s", "frame_stride")])
  }
  view <- list(schema = "brohn-participant-view/0.1", run_id = run_id, source_protocol_hash = source_protocol_hash,
    renderer_identity = renderer_identity, presentation = list(title = d$title,
      appearance = d$appearance[c("background", "foreground")], consent = d$consent[c("title", "text", "required")], debrief = d$debrief,
      navigation = navigation, equipment = equipment, camera = camera,
      resources = lapply(resources, function(r) c(list(resource_key = r$key, bytes = r$asset$size, media_type = r$asset$media_type),
        r$asset[intersect(c("width", "height"), names(r$asset))]))), steps = public_steps)
  private_map <- list(schema = "participant-projection-map/0.1", public_run_id = run_id,
    source_protocol_hash = source_protocol_hash, source_design_hash = protocol$design_hash,
    allocation_index = protocol$allocation_index, renderer_identity = renderer_identity,
    steps = steps, stimuli = stimuli, occurrences = occurrences, questions = questions, choices = choices,
    tasks = tasks, resources = resources, policies = policies)
  .brohn_pvq_plain(view); .brohn_pvq_plain(private_map)
  list(view = view, private_map = private_map)
}
