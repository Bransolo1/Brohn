# Inactive stored-view semantic admission. No loader, authority or delivery route.
.brohn_pvx_get <- function(x, name) x[[name, exact = TRUE]]
.brohn_pvx_expect <- function(actual, expected, label) {
  brohn_require(.brohn_ph_equal(actual, expected), paste("Stored participant projection differs:", label))
  invisible(TRUE)
}
.brohn_pvx_array <- function(value, count, label) {
  brohn_require(brohn_array(value) && length(value) == count, paste("Incomplete participant mapping:", label))
}
.brohn_pvx_keys <- function(rows, field) vapply(rows, function(x) .brohn_pvx_get(x, field), character(1))
.brohn_pvx_document <- function(document) {
  brohn_require(typeof(document) == "list" && identical(names(attributes(document)), "names"),
    "A stored participant document must be a plain descriptor.")
  brohn_fields(document, c("codec", "json", "bytes", "sha256"), label = "Stored participant document")
  for (name in names(document)) brohn_require(is.null(attributes(document[[name, exact = TRUE]])),
    "Stored document scalars must be plain values.")
  brohn_require(identical(document$codec, "brohn-participant-json-bytes/0.1") &&
    is.character(document$json) && length(document$json) == 1L && !is.na(document$json) &&
    Encoding(document$json) %in% c("unknown", "UTF-8") && validUTF8(document$json) &&
    brohn_number(document$bytes, 1, 16 * 1024^2, TRUE) && .brohn_ph_sha(document$sha256),
    "Unsupported encoded participant document.")
  brohn_require(nchar(document$json, type = "bytes") == document$bytes, "Stored participant byte length differs.")
  raw <- charToRaw(document$json)
  brohn_require(identical(raw, charToRaw(enc2utf8(document$json))) &&
    identical(digest::digest(raw, algo = "sha256", serialize = FALSE), document$sha256),
    "Stored participant original-byte digest differs.")
  # Exact actual bytes are hashed above. Re-emission is only an admission check
  # for this canonical server-storage codec, never a new source identity.
  value <- jsonlite::fromJSON(document$json, simplifyVector = FALSE)
  encoded <- brohn_participant_json_bytes(value)
  brohn_require(identical(charToRaw(encoded$json), raw) && identical(encoded$sha256, document$sha256),
    "Stored participant JSON is not the declared canonical codec.")
  value
}

.brohn_pvx_question_binding <- function(protocol, map) {
  .brohn_pvq_validate_map(map)
  assigned <- Filter(function(s) identical(s$type, "question"), protocol$timeline)
  ids <- vapply(assigned, function(s) s$question$id, character(1))
  originals <- Filter(function(q) q$id %in% ids, protocol$design$questions)
  .brohn_pvx_array(map$entries, length(originals), "question collection")
  for (i in seq_along(originals)) {
    q <- originals[[i]]; entry <- map$entries[[i]]
    options <- if (q$type %in% .brohn_pvq_finite) q$options else list()
    rows <- if (identical(q$type, "matrix")) q$rows else list()
    .brohn_pvx_array(entry$options, length(options), "question options")
    .brohn_pvx_array(entry$rows, length(rows), "question rows")
    expected <- list(source_id = q$id, type = q$type, scope = q$scope, question_key = entry$question_key,
      options = lapply(seq_along(options), function(j) list(source_id = options[[j]]$id,
        option_key = entry$options[[j]]$option_key, source_value = options[[j]]$value)),
      rows = lapply(seq_along(rows), function(j) list(source_id = rows[[j]]$id, row_key = entry$rows[[j]]$row_key)))
    .brohn_pvx_expect(entry, expected, "complete original question/option/row mapping")
  }
  invisible(TRUE)
}
.brohn_pvx_choice_binding <- function(protocol, map) {
  .brohn_pvm_validate_map(map)
  .brohn_pvx_expect(map$source_design_hash, protocol$design_hash, "choice full-design hash")
  .brohn_pvx_expect(map$allocation_index, protocol$allocation_index, "choice allocation")
  choices <- lapply(Filter(function(s) identical(s$type, "maxdiff"), protocol$timeline), function(s) s$choice)
  ids <- unique(vapply(choices, function(c) c$exercise_id, character(1)))
  .brohn_pvx_array(map$exercises, length(ids), "choice exercises")
  for (i in seq_along(ids)) {
    entry <- map$exercises[[i]]
    rows <- Filter(function(c) identical(c$exercise_id, ids[[i]]), choices)
    offered <- unique(unlist(lapply(rows, function(c) c$item_order), use.names = FALSE))
    .brohn_pvx_array(entry$items, length(offered), "offered choice items")
    .brohn_pvx_array(entry$trials, length(rows), "choice trials")
    expected <- list(source_id = ids[[i]], exercise_key = entry$exercise_key,
      items = lapply(seq_along(offered), function(j) list(source_id = offered[[j]], item_key = entry$items[[j]]$item_key)),
      trials = lapply(seq_along(rows), function(j) {
        c <- rows[[j]]; saved <- entry$trials[[j]]
        list(source_set_id = c$set_id, set_key = saved$set_key, source_trial_id = c$trial_id,
          trial_key = saved$trial_key, source_choice_hash = .brohn_ph_hash(c), required = c$required, item_order = c$item_order)
      }))
    .brohn_pvx_expect(entry, expected, "complete offered original choice mapping")
  }
  invisible(TRUE)
}
.brohn_pvx_task_binding <- function(protocol, entries) {
  originals <- Filter(function(s) identical(s$type, "task"), protocol$timeline)
  .brohn_pvx_array(entries, length(originals), "outer task entries")
  for (i in seq_along(originals)) {
    outer <- originals[[i]]; entry <- entries[[i]]; compiled <- outer$task
    brohn_fields(entry, c("outer_step_id", "map"), label = "Outer task mapping")
    .brohn_pvx_expect(entry$outer_step_id, outer$id, "task outer step")
    map <- entry$map; .brohn_pvt_validate_map(map)
    source <- .brohn_pvc_lookup(protocol$design$blocks, "id", compiled$id)
    .brohn_pvx_expect(map$task_id, compiled$id, "original task identity")
    .brohn_pvx_expect(map$profile, compiled$profile, "original task profile")
    .brohn_pvx_expect(map$source_design_hash, compiled$design_hash, "nested original task hash")
    .brohn_pvx_expect(map$allocation_index, protocol$allocation_index, "task allocation")
    .brohn_pvx_array(map$blocks, length(compiled$blocks), "task blocks")
    .brohn_pvx_array(map$steps, length(compiled$timeline), "task steps")
    .brohn_pvx_expect(map$blocks, lapply(seq_along(compiled$blocks), function(j)
      list(source_id = compiled$blocks[[j]]$id, key = map$blocks[[j]]$key)), "ordered original task blocks")
    .brohn_pvx_expect(map$steps, lapply(seq_along(compiled$timeline), function(j) {
      s <- compiled$timeline[[j]]
      list(source_id = s$id, key = map$steps[[j]]$key, type = s$type, block_id = s$block_id,
        block_key = .brohn_pvt_lookup(map$blocks, "source_id", s$block_id)$key)
    }), "ordered original task steps and block associations")
    ids <- unique(vapply(Filter(function(s) !is.null(.brohn_pvx_get(s, "material")), compiled$timeline),
      function(s) s$material$id, character(1)))
    .brohn_pvx_array(map$materials, length(ids), "used task materials")
    .brohn_pvx_expect(map$materials, lapply(seq_along(ids), function(j) {
      material <- .brohn_pvt_lookup(source$materials, "id", ids[[j]])
      image <- identical(material$type, "image")
      list(source_id = material$id, key = map$materials[[j]]$key,
        resource_key = if (image) map$materials[[j]]$resource_key else NULL,
        asset = if (image) material$asset else NULL)
    }), "exact original used task materials")
    if (.brohn_pvt_special(compiled$profile)) .brohn_pvx_expect(map$procedure$source_hash,
      compiled$procedure_hash, "original task procedure hash")
  }
  invisible(TRUE)
}

.brohn_pvx_global_keys <- function(protocol, map) {
  keys <- map$public_run_id
  brohn_require(.brohn_pvc_key(map$public_run_id, "pvu"), "Invalid stored public run key.")
  add <- function(values, prefix) {
    brohn_require(all(vapply(values, .brohn_pvc_key, logical(1), prefix = prefix)), "Invalid stored participant key prefix.")
    keys <<- c(keys, values)
  }
  add(.brohn_pvx_keys(map$steps, "key"), "pvs"); add(.brohn_pvx_keys(map$stimuli, "key"), "pvi")
  add(.brohn_pvx_keys(map$occurrences, "key"), "pvo")
  for (q in map$questions$entries) {
    add(q$question_key, "pvq"); add(.brohn_pvx_keys(q$options, "option_key"), "pvq"); add(.brohn_pvx_keys(q$rows, "row_key"), "pvq")
  }
  for (c in map$choices$exercises) {
    add(c$exercise_key, "pvm"); add(.brohn_pvx_keys(c$items, "item_key"), "pvm")
    add(.brohn_pvx_keys(c$trials, "set_key"), "pvm"); add(.brohn_pvx_keys(c$trials, "trial_key"), "pvm")
  }
  for (t in map$tasks) {
    add(t$map$task_key, "pvt")
    for (name in c("blocks", "steps", "materials")) add(.brohn_pvx_keys(t$map[[name, exact = TRUE]], "key"), "pvt")
  }
  add(.brohn_pvx_keys(map$resources, "key"), "pvr"); add(.brohn_pvx_keys(map$policies, "token"), "pvp")
  brohn_require(!anyDuplicated(keys), "Stored participant definitions collide across components.")
  reserved <- new.env(parent = emptyenv(), hash = TRUE)
  for (key in keys) assign(key, TRUE, reserved)
  walk <- function(value) {
    if (is.list(value)) {
      for (name in names(value)) brohn_require(!exists(name, reserved, inherits = FALSE), "Participant key collides with an original object key.")
      for (item in value) walk(item)
    } else if (is.character(value) && .brohn_pvc_key(value)) brohn_require(!exists(value, reserved, inherits = FALSE), "Participant key collides with an original value.")
    invisible(NULL)
  }
  walk(protocol)
  invisible(TRUE)
}

.brohn_pvx_expected_view <- function(protocol, map) {
  d <- protocol$design
  step_key <- function(id) .brohn_pvc_lookup(map$steps, "source_id", id)$key
  stimulus_key <- function(id) if (is.null(id)) NULL else .brohn_pvc_lookup(map$stimuli, "source_id", id)$key
  occurrence_key <- function(id) .brohn_pvc_lookup(map$occurrences, "source_id", id)$key
  resources <- list(); resource_values <- character(); policies <- list()
  register_resource <- function(asset, use) {
    brohn_fields(asset, c("hash", "size", "media_type"), c("filename", "width", "height"), "Assigned resource descriptor")
    brohn_require(.brohn_ph_sha(asset$hash) && brohn_number(asset$size, 1, 512 * 1024^2, TRUE) &&
      brohn_text(asset$media_type, 120L), "Assigned resource has invalid source metadata.")
    for (name in intersect(c("width", "height"), names(asset))) brohn_require(
      brohn_number(asset[[name, exact = TRUE]], 1, 2147483647, TRUE), "Assigned resource dimensions must be positive whole pixels.")
    value <- brohn_json(asset); position <- match(value, resource_values)
    if (is.na(position)) {
      position <- length(resources) + 1L
      brohn_require(position <= length(map$resources), "Stored resource registry omits an assigned descriptor.")
      resources[[position]] <<- list(key = map$resources[[position]]$key, asset = asset, uses = list())
      resource_values[[position]] <<- value
    }
    entry <- resources[[position]]
    if (!any(vapply(entry$uses, function(old) identical(old, use), logical(1)))) entry$uses[[length(entry$uses) + 1L]] <- use
    resources[[position]] <<- entry
    entry$key
  }
  register_policy <- function(kind, source_hash, outer_step_id = NULL, task_id = NULL, profile = NULL) {
    position <- length(policies) + 1L
    brohn_require(position <= length(map$policies), "Stored policy registry omits an original policy.")
    entry <- list(kind = kind, token = map$policies[[position]]$token, source_hash = source_hash,
      outer_step_id = outer_step_id, task_id = task_id, profile = profile)
    policies[[position]] <<- entry
    entry$token
  }
  public_steps <- lapply(seq_along(protocol$timeline), function(i) {
    s <- protocol$timeline[[i]]
    result <- list(step_key = map$steps[[i]]$key, type = s$type, phase = s$phase)
    if (s$type %in% c("baseline", "fixation", "stimulus", "question", "questionnaire_review")) result["stimulus_key"] <- list(stimulus_key(s$stimulus_id))
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
      result$question <- brohn_project_participant_question(s$question, map$questions,
        function(asset) register_resource(asset, use("question_illustration", s$question$id)))
      result$question_key <- result$question$question_key
      if ("questionnaire" %in% names(s)) result$section_label <- s$questionnaire$section_label
    } else if (s$type == "questionnaire_review") {
      brohn_require("occurrence_key" %in% names(result), "A review screen needs its assigned questionnaire occurrence.")
    } else if (s$type == "maxdiff") {
      result$choice <- brohn_project_participant_choice(s$choice, map$choices,
        function(asset) register_resource(asset, use("maxdiff_illustration", s$choice$trial_id, s$choice$exercise_id)))
    } else if (s$type == "task") {
      task_map <- .brohn_pvc_lookup(map$tasks, "outer_step_id", s$id)$map
      source_block <- .brohn_pvc_lookup(d$blocks, "id", s$task$id)
      if (.brohn_pvt_special(s$task$profile)) .brohn_pvx_expect(task_map$procedure$token,
        register_policy("task_procedure", s$task$procedure_hash, s$id, s$task$id, s$task$profile), "task procedure registry token")
      for (m in task_map$materials) if (!is.null(m$resource_key)) {
        original <- .brohn_pvt_lookup(source_block$materials, "id", m$source_id)
        .brohn_pvx_expect(m$resource_key, register_resource(original$asset, use("task_material", original$id, s$task$id)), "task resource registry key")
      }
      result$task <- .brohn_pvt_render_mapped_validated(s$task, task_map)
    } else stop("Unsupported saved participant step; no context was created.", call. = FALSE)
    result
  })
  navigation <- if (!"questionnaire_occurrences" %in% names(protocol)) NULL else list(
    schema = "participant-navigation/0.1", occurrences = lapply(map$occurrences, function(o) list(
      occurrence_key = o$key, scope = o$scope, stimulus_step_key = if (is.null(o$stimulus_step_id)) NULL else step_key(o$stimulus_step_id),
      question_step_keys = lapply(o$question_step_ids, step_key), review_step_key = step_key(o$review_step_id))))
  equipment <- NULL
  if ("equipment" %in% names(protocol)) {
    original <- protocol$equipment
    equipment <- c(list(schema = "participant-equipment-view/0.1", policy_token = register_policy("equipment", original$policy_hash)),
      original[c("camera", "audio", "required_codes", "controls", "freshness_ms", "first_write_wait_ms")])
  }
  camera <- NULL
  if (!is.null(d[["camera", exact = TRUE]])) {
    original <- d$camera
    brohn_require(original$schema %in% c("brohn-camera-policy/1.0", "brohn-camera-policy/1.1"), "Unknown saved camera presentation policy.")
    camera <- c(list(schema = "participant-camera-view/0.1", policy_token = register_policy("camera", .brohn_ph_hash(original)),
      source_policy_version = original$schema), original[c("required", "audio", "consent_text", "retention_text", "width", "height", "frame_rate", "max_duration_s", "max_bytes")])
    camera$analysis <- if (original$schema == "brohn-camera-policy/1.0") list(mode = "legacy_recording", profile = original$analysis_profile) else
      c(list(mode = "named_facial_1.1", notice = original$analysis_notice), original$analysis_settings[c("start_s", "end_s", "frame_stride")])
  }
  .brohn_pvx_expect(map$resources, resources, "complete assigned resource registry and uses")
  .brohn_pvx_expect(map$policies, policies, "complete original policy registry")
  list(schema = "brohn-participant-view/0.1", run_id = map$public_run_id, source_protocol_hash = map$source_protocol_hash,
    renderer_identity = map$renderer_identity, presentation = list(title = d$title,
      appearance = d$appearance[c("background", "foreground")], consent = d$consent[c("title", "text", "required")], debrief = d$debrief,
      navigation = navigation, equipment = equipment, camera = camera,
      resources = lapply(resources, function(r) c(list(resource_key = r$key, bytes = r$asset$size, media_type = r$asset$media_type),
        r$asset[intersect(c("width", "height"), names(r$asset))]))), steps = public_steps)
}

brohn_participant_view_context <- function(protocol, source_protocol_hash, view_document, map_document) {
  brohn_require(is.null(attributes(source_protocol_hash)) && .brohn_ph_sha(source_protocol_hash), "Supply the plain declared original protocol-byte SHA256.")
  view <- .brohn_pvx_document(view_document); map <- .brohn_pvx_document(map_document)
  # The public revision constructor includes the complete saved-source reader.
  # Choose one complete public admission here; never accept a caller validation
  # flag or reconstruct a previously saved assignment.
  design <- if (typeof(protocol) == "list" && !is.object(protocol)) protocol[["design", exact = TRUE]] else NULL
  revision <- if (typeof(design) == "list" && !is.object(design) &&
      "questionnaire_navigation" %in% names(design))
    brohn_variant_revision_context(protocol, source_protocol_hash) else {
      brohn_validate_saved_variant_protocol(protocol); NULL
    }
  brohn_fields(view, c("schema", "run_id", "source_protocol_hash", "renderer_identity", "presentation", "steps"), label = "Stored participant view")
  brohn_fields(map, c("schema", "public_run_id", "source_protocol_hash", "source_design_hash", "allocation_index", "renderer_identity",
    "steps", "stimuli", "occurrences", "questions", "choices", "tasks", "resources", "policies"), label = "Stored participant projection map")
  brohn_require(identical(view$schema, "brohn-participant-view/0.1") && identical(map$schema, "participant-projection-map/0.1"), "Unsupported stored participant projection schema.")
  .brohn_pvc_renderer(map$renderer_identity)
  .brohn_pvx_expect(view$renderer_identity, map$renderer_identity, "renderer identity")
  .brohn_pvx_expect(view$source_protocol_hash, source_protocol_hash, "view original-byte declaration")
  .brohn_pvx_expect(map$source_protocol_hash, source_protocol_hash, "map original-byte declaration")
  .brohn_pvx_expect(view$run_id, map$public_run_id, "public run identity")
  .brohn_pvx_expect(map$source_design_hash, protocol$design_hash, "complete retained design hash")
  .brohn_pvx_expect(map$allocation_index, protocol$allocation_index, "allocation index")
  .brohn_pvx_array(map$steps, length(protocol$timeline), "outer steps")
  .brohn_pvx_array(view$steps, length(protocol$timeline), "public steps")
  .brohn_pvx_expect(map$steps, lapply(seq_along(protocol$timeline), function(i) {
    s <- protocol$timeline[[i]]
    list(source_id = s$id, key = map$steps[[i]]$key, index = i, type = s$type, phase = s$phase,
      stimulus_id = .brohn_pvx_get(s, "stimulus_id"), condition_id = .brohn_pvx_get(s, "condition_id"),
      question_id = if (s$type == "question") s$question$id else NULL, occurrence_id = .brohn_pvx_get(s, "questionnaire_occurrence_id"))
  }), "complete ordered outer mapping")
  .brohn_pvx_array(map$stimuli, length(protocol$realized_stimulus_order), "assigned stimuli")
  .brohn_pvx_expect(map$stimuli, lapply(seq_along(protocol$realized_stimulus_order), function(i)
    list(source_id = protocol$realized_stimulus_order[[i]], key = map$stimuli[[i]]$key)), "exact realized stimulus order")
  occurrences <- .brohn_pvx_get(protocol, "questionnaire_occurrences")
  .brohn_pvx_array(map$occurrences, length(occurrences), "questionnaire occurrences")
  .brohn_pvx_expect(map$occurrences, lapply(seq_along(occurrences), function(i) {
    o <- occurrences[[i]]
    list(source_id = o$id, key = map$occurrences[[i]]$key, scope = o$scope, stimulus_id = o$stimulus_id,
      stimulus_step_id = o$stimulus_step_id, question_step_ids = o$question_step_ids, review_step_id = o$review_step_id)
  }), "complete original occurrence links")
  .brohn_pvx_question_binding(protocol, map$questions)
  .brohn_pvx_choice_binding(protocol, map$choices)
  .brohn_pvx_task_binding(protocol, map$tasks)
  brohn_require(brohn_array(map$resources) && brohn_array(map$policies), "Stored registries must be arrays.")
  for (r in map$resources) brohn_fields(r, c("key", "asset", "uses"), label = "Stored assigned resource")
  for (p in map$policies) brohn_fields(p, c("kind", "token", "source_hash", "outer_step_id", "task_id", "profile"), label = "Stored original policy")
  .brohn_pvx_global_keys(protocol, map)
  .brohn_pvx_expect(view, .brohn_pvx_expected_view(protocol, map), "complete public presentation")

  step <- function(public_key) {
    brohn_require(.brohn_pvc_key(public_key, "pvs"), "Supply an exact public step key.")
    m <- .brohn_pvc_lookup(map$steps, "key", public_key); i <- m$index
    list(source_step = protocol$timeline[[i]], public_step = view$steps[[i]], mapping = m)
  }
  question <- function(public_key) {
    brohn_require(.brohn_pvc_key(public_key, "pvq"), "Supply an exact public question key.")
    m <- .brohn_pvq_lookup(map$questions$entries, "question_key", public_key)
    associations <- lapply(Filter(function(s) identical(s$question_id, m$source_id), map$steps), function(s) {
      public <- view$steps[[s$index]]
      list(step_key = s$key, source_step_id = s$source_id, occurrence_key = .brohn_pvx_get(public, "occurrence_key"),
        source_occurrence_id = s$occurrence_id, stimulus_key = .brohn_pvx_get(public, "stimulus_key"), source_stimulus_id = s$stimulus_id)
    })
    list(source_question = .brohn_pvc_lookup(protocol$design$questions, "id", m$source_id), mapping = m, associations = associations)
  }
  task <- function(outer_step_key) {
    s <- step(outer_step_key); brohn_require(identical(s$mapping$type, "task"), "This outer step is not a task.")
    list(source_task = s$source_step$task, source_block = .brohn_pvc_lookup(protocol$design$blocks, "id", s$source_step$task$id),
      public_task = s$public_step$task, mapping = .brohn_pvc_lookup(map$tasks, "outer_step_id", s$source_step$id)$map)
  }
  choice <- function(outer_step_key) {
    s <- step(outer_step_key); brohn_require(identical(s$mapping$type, "maxdiff"), "This outer step is not best-worst choice.")
    exercise <- .brohn_pvm_lookup(map$choices$exercises, "source_id", s$source_step$choice$exercise_id)
    list(source_choice = s$source_step$choice, public_choice = s$public_step$choice, exercise_mapping = exercise,
      trial_mapping = .brohn_pvm_lookup(exercise$trials, "source_trial_id", s$source_step$choice$trial_id))
  }
  occurrence <- function(public_key) {
    brohn_require(.brohn_pvc_key(public_key, "pvo"), "Supply an exact public occurrence key.")
    m <- .brohn_pvc_lookup(map$occurrences, "key", public_key)
    list(source_occurrence = .brohn_pvc_lookup(occurrences, "id", m$source_id), mapping = m,
      public_occurrence = .brohn_pvc_lookup(view$presentation$navigation$occurrences, "occurrence_key", public_key))
  }
  resource <- function(public_key) {
    brohn_require(.brohn_pvc_key(public_key, "pvr"), "Supply an exact public resource key.")
    m <- .brohn_pvc_lookup(map$resources, "key", public_key)
    list(source_descriptor = m$asset, public_descriptor = .brohn_pvc_lookup(view$presentation$resources, "resource_key", public_key), uses = m$uses)
  }
  policy <- function(kind, token) {
    brohn_require(brohn_text(kind, 40L) && kind %in% c("task_procedure", "equipment", "camera") && .brohn_pvc_key(token, "pvp"), "Supply the exact policy kind and token.")
    m <- .brohn_pvc_lookup(map$policies, "token", token)
    brohn_require(identical(m$kind, kind), "Policy token belongs to another policy kind."); m
  }
  binding <- function() list(source_protocol_hash = source_protocol_hash, view_hash = view_document$sha256,
    map_hash = map_document$sha256, source_design_hash = protocol$design_hash, allocation_index = protocol$allocation_index,
    public_run_id = map$public_run_id, renderer_identity = map$renderer_identity)
  result <- new.env(parent = emptyenv())
  values <- list(schema = "participant-view-context/0.1", protocol = protocol, projection = list(view = view, private_map = map),
    source_protocol_hash = source_protocol_hash, view_hash = view_document$sha256, map_hash = map_document$sha256,
    view_document = view_document, map_document = map_document, revision_context = revision,
    binding = binding, step = step, question = question, task = task, choice = choice, occurrence = occurrence, resource = resource, policy = policy)
  for (name in names(values)) assign(name, values[[name]], result)
  lockEnvironment(result, bindings = TRUE)
  brohn_assert_participant_view_context(result)
  result
}

brohn_assert_participant_view_context <- function(context) {
  # Process-local interface assertion only. It is not source/current authority,
  # nor an attestation against arbitrary trusted R code forging environments.
  fields <- c("schema", "protocol", "projection", "source_protocol_hash", "view_hash", "map_hash", "view_document", "map_document",
    "revision_context", "binding", "step", "question", "task", "choice", "occurrence", "resource", "policy")
  brohn_require(is.environment(context) && environmentIsLocked(context) && identical(parent.env(context), emptyenv()) &&
    setequal(ls(context, all.names = TRUE), fields) && all(vapply(fields, bindingIsLocked, logical(1), env = context)) &&
    !any(vapply(fields, bindingIsActive, logical(1), env = context)), "Expected a locked process-local participant context.")
  brohn_require(identical(context$schema, "participant-view-context/0.1") && all(vapply(
    c("binding", "step", "question", "task", "choice", "occurrence", "resource", "policy"), function(name) is.function(get(name, context, inherits = FALSE)), logical(1))),
    "Unsupported participant context interface.")
  invisible(context)
}
