# Brohn domain 1.0: explicit new contracts; legacy 0.1 readers remain separate.
brohn_version <- "1.0.0"
brohn_now <- function() format(Sys.time(), "%Y-%m-%dT%H:%M:%OS3Z", tz = "UTC")
brohn_id <- function(prefix = "id") paste0(prefix, "-", paste(format(openssl::rand_bytes(16)), collapse = ""))
brohn_token <- function() paste(format(openssl::rand_bytes(32)), collapse = "")
brohn_stop <- function(message) stop(message, call. = FALSE)
brohn_require <- function(ok, message) if (!isTRUE(ok)) brohn_stop(message)
brohn_text <- function(x, max = 10000, empty = FALSE) is.character(x) && length(x) == 1L &&
  !is.na(x) && nchar(x, type = "bytes") <= max && (empty || nzchar(trimws(x)))
brohn_number <- function(x, min = -Inf, max = Inf, integer = FALSE) is.numeric(x) &&
  length(x) == 1L && !is.na(x) && is.finite(x) && x >= min && x <= max && (!integer || x == floor(x))
brohn_valid_id <- function(x) brohn_text(x, 96) && grepl("^[A-Za-z][A-Za-z0-9_-]*$", x)
brohn_array <- function(x) is.list(x) && is.null(names(x))
brohn_ids <- function(x) vapply(x, function(v) v$id, character(1))
brohn_find <- function(items, id) { hits <- Filter(function(x) identical(x$id, id), items); if (length(hits)) hits[[1L]] else NULL }
brohn_default <- function(x, fallback) if (is.null(x)) fallback else x
brohn_fields <- function(x, required, optional = character(), label = "Record") {
  brohn_require(is.list(x) && !is.null(names(x)) && !anyDuplicated(names(x)), paste(label, "must be an object with unique fields."))
  brohn_require(all(required %in% names(x)), paste(label, "is missing:", paste(setdiff(required, names(x)), collapse = ", ")))
  brohn_require(all(names(x) %in% c(required, optional)), paste(label, "has unsupported fields:", paste(setdiff(names(x), c(required, optional)), collapse = ", ")))
}
brohn_canonical <- function(x, depth = 0L) {
  brohn_require(depth < 64L, "Record nesting exceeds 64 levels.")
  brohn_require(is.null(dim(x)) && (!is.object(x) || inherits(x, "AsIs")), "Convert structured R objects to explicit records before JSON encoding.")
  if (is.list(x)) {
    if (!is.null(names(x))) {
      brohn_require(!anyNA(names(x)) && !anyDuplicated(names(x)) && all(nzchar(names(x))), "Invalid or duplicate object keys.")
      x <- x[order(names(x), method = "radix")]
    }
    return(lapply(x, brohn_canonical, depth = depth + 1L))
  }
  if (is.character(x)) { brohn_require(!anyNA(x), "Missing text must use explicit null, not NA."); return(enc2utf8(x)) }
  brohn_require(is.null(x) || is.logical(x) || is.numeric(x), "Unsupported record value.")
  brohn_require(is.null(x) || (!anyNA(x) && (!is.numeric(x) || all(is.finite(x)))), "Missing values use null; NaN and infinity are not valid JSON.")
  x
}
brohn_json <- function(x, pretty = FALSE) as.character(jsonlite::toJSON(brohn_canonical(x),
  auto_unbox = TRUE, null = "null", digits = 17, pretty = pretty, force = TRUE))
brohn_parse <- function(text, max_bytes = 16 * 1024^2) {
  brohn_require(brohn_text(text, max_bytes), "JSON is empty or exceeds its size limit.")
  value <- jsonlite::fromJSON(text, simplifyVector = FALSE)
  brohn_canonical(value)
}
brohn_hash <- function(x) digest::digest(charToRaw(enc2utf8(brohn_json(x))), algo = "sha256", serialize = FALSE)
brohn_seeded <- function(seed, fn) {
  exists <- exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)
  if (exists) previous <- get(".Random.seed", envir = .GlobalEnv)
  on.exit(if (exists) assign(".Random.seed", previous, envir = .GlobalEnv) else if (exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)) rm(".Random.seed", envir = .GlobalEnv))
  set.seed(as.integer(seed)); fn()
}

brohn_question <- function(prompt = "How much do you like this concept?", type = "rating", scope = "after_each", id = brohn_id("q")) {
  list(id = id, type = type, prompt = prompt, required = TRUE, scope = scope,
    options = lapply(1:7, function(i) list(id = paste0("option-", i), label = if (i == 1) "Not at all" else if (i == 7) "Very much" else as.character(i), value = i)),
    rows = list(), min = 1, max = 7, step = 1, show_if = NULL, randomize_options = FALSE,
    option_assignment = "participant-sha256/1.0")
}
brohn_new_design <- function(title = "Untitled study", template = "comparison", id = brohn_id("study"), project_id = "default") {
  brohn_require(template %in% c("comparison", "survey", "blank"), "Choose a supported starting design.")
  comparison <- identical(template, "comparison")
  list(schema_version = "brohn-design/1.0.0", id = id, project_id = project_id,
    title = title, description = "", template = template, archived = FALSE, tags = list(),
    conditions = if (comparison) list(list(id = "condition-a", label = "Control", role = "control"), list(id = "condition-b", label = "Test", role = "test")) else list(),
    stimuli = if (comparison) lapply(1:2, function(i) list(id = paste0("stimulus-", letters[i]),
      title = paste("Concept", LETTERS[i]), condition_id = paste0("condition-", letters[i]),
      type = "text", content = "", asset = NULL, duration_ms = 5000, aois = list())) else list(),
    questions = if (comparison) list(brohn_question(id = "q-liking")) else list(),
    order = "counterbalanced", seed = 104729, baseline_ms = 0, fixation_ms = 500,
    instructions = "Look at each concept naturally, then answer the questions.",
    consent = list(title = "Taking part in this study", text = "Please read the study information provided by your researcher. Participation is voluntary. You can stop at any time.", required = TRUE),
    debrief = "Thank you for taking part. Contact your researcher if you have questions about the study.",
    appearance = list(background = "#FFFFFF", foreground = "#111111"),
    measures = if (comparison) list("gaze", "questionnaire") else list("questionnaire"),
    methods = list(), blocks = list(), lineage = NULL)
}

brohn_validate_rule <- function(rule, question_ids, depth = 0L) {
  if (is.null(rule)) return(invisible(TRUE))
  brohn_require(depth < 12L, "Question logic is nested too deeply.")
  brohn_require(is.list(rule) && brohn_text(rule$op), "Question logic needs an operation.")
  if (rule$op %in% c("and", "or")) {
    brohn_fields(rule, c("op", "rules"), label = "Logic")
    brohn_require(brohn_array(rule$rules) && length(rule$rules) >= 1L && length(rule$rules) <= 20L, "Logic requires 1 to 20 conditions.")
    for (r in rule$rules) { brohn_require(!is.null(r), "A nested logic condition cannot be null."); brohn_validate_rule(r, question_ids, depth + 1L) }
  } else if (rule$op == "not") {
    brohn_fields(rule, c("op", "rule"), label = "Logic"); brohn_require(!is.null(rule$rule), "A negated logic condition cannot be null."); brohn_validate_rule(rule$rule, question_ids, depth + 1L)
  } else {
    brohn_fields(rule, c("op", "question_id"), c("value"), "Logic")
    brohn_require(rule$op %in% c("equals", "not_equals", "contains", "greater", "less", "answered"), "Unsupported question logic operation.")
    brohn_require(rule$question_id %in% question_ids, "Question logic refers to an unavailable earlier question.")
    if (rule$op != "answered") {
      brohn_require("value" %in% names(rule) && !is.null(rule$value), "Question logic needs a comparison value.")
      scalar <- brohn_text(rule$value, 10000, TRUE) || brohn_number(rule$value) || (is.logical(rule$value) && length(rule$value) == 1L && !is.na(rule$value))
      brohn_require(scalar, "Question logic comparisons need a scalar value.")
      if (rule$op %in% c("greater", "less")) brohn_require(brohn_number(rule$value), "Ordered question logic needs a numeric comparison.")
    }
  }
  invisible(TRUE)
}
brohn_rule <- function(rule, answers) {
  if (is.null(rule)) return(TRUE)
  if (rule$op == "and") return(all(vapply(rule$rules, brohn_rule, logical(1), answers = answers)))
  if (rule$op == "or") return(any(vapply(rule$rules, brohn_rule, logical(1), answers = answers)))
  if (rule$op == "not") return(!brohn_rule(rule$rule, answers))
  value <- answers[[rule$question_id]]
  answered <- !is.null(value) && length(value) > 0 && !(is.character(value) && all(!nzchar(value)))
  if (rule$op == "answered") return(answered)
  if (!answered) return(FALSE)
  same <- function(a, b) {
    if (length(a) != 1L || length(b) != 1L || is.list(a) || is.list(b)) return(FALSE)
    matching_type <- (is.numeric(a) && is.numeric(b)) || (is.logical(a) && is.logical(b)) || (is.character(a) && is.character(b))
    matching_type && isTRUE(a == b)
  }
  flatten <- function(x) {
    if (is.null(x)) return(list())
    if (!is.list(x)) return(as.list(x))
    # Concatenating lists preserves scalar JSON types; unlist() coerces mixed
    # numeric, text and boolean option codes into a shared vector type.
    do.call(c, lapply(x, flatten))
  }
  switch(rule$op, equals = same(value, rule$value),
    not_equals = !same(value, rule$value),
    contains = any(vapply(flatten(value), same, logical(1), b = rule$value)),
    greater = brohn_number(value) && brohn_number(rule$value) && value > rule$value,
    less = brohn_number(value) && brohn_number(rule$value) && value < rule$value,
    FALSE)
}
brohn_validate_question <- function(q, earlier_ids) {
  brohn_fields(q, c("id", "type", "prompt", "required", "scope", "options", "rows", "min", "max", "step", "show_if", "randomize_options"), optional = "option_assignment", label = "Question")
  brohn_require(brohn_valid_id(q$id) && brohn_text(q$prompt, 12000), "Each question needs an ID and prompt.")
  brohn_require(q$type %in% c("rating", "single_choice", "multiple_choice", "dropdown", "text", "long_text", "number", "slider", "matrix", "ranking", "allocation", "information"), "Unsupported question type.")
  brohn_require(q$scope %in% c("before", "after_each", "end"), "Unsupported question placement.")
  brohn_require(is.logical(q$required) && length(q$required) == 1 && !is.na(q$required), "Required must be true or false.")
  brohn_require(is.logical(q$randomize_options) && length(q$randomize_options) == 1 && !is.na(q$randomize_options), "Option randomization must be true or false.")
  if ("option_assignment" %in% names(q)) brohn_require(brohn_text(q$option_assignment, 96) &&
    q$option_assignment %in% c("legacy-timeline-r/1.0", "participant-sha256/1.0"), "Unsupported question option-assignment version.")
  brohn_require(brohn_array(q$options) && length(q$options) <= 100, "Question options must be an array of at most 100 values.")
  for (option in q$options) {
    brohn_fields(option, c("id", "label", "value"), label = "Question option")
    brohn_require(brohn_valid_id(option$id) && brohn_text(option$label, 2000), "Each option needs an ID and label.")
    brohn_require(brohn_number(option$value) || brohn_text(option$value, 1000) || (is.logical(option$value) && length(option$value) == 1 && !is.na(option$value)), "Option values must be scalar codes.")
  }
  brohn_require(!anyDuplicated(brohn_ids(q$options)), "Option IDs must be unique within a question.")
  if (q$type %in% c("rating", "single_choice", "multiple_choice", "dropdown", "matrix")) {
    codes <- vapply(q$options, function(o) brohn_json(o$value), character(1))
    brohn_require(!anyDuplicated(codes), "Each answer option needs a distinct typed code so responses remain unambiguous.")
  }
  if (q$type %in% c("rating", "single_choice", "multiple_choice", "dropdown", "matrix", "ranking", "allocation")) brohn_require(length(q$options) >= 2, "This question needs at least two options.")
  brohn_require(brohn_array(q$rows) && length(q$rows) <= 100, "Matrix rows must be an array.")
  for (row in q$rows) { brohn_fields(row, c("id", "label"), label = "Matrix row"); brohn_require(brohn_valid_id(row$id) && brohn_text(row$label, 2000), "Invalid matrix row.") }
  brohn_require(!anyDuplicated(brohn_ids(q$rows)), "Matrix row IDs must be unique.")
  if (q$type == "matrix") brohn_require(length(q$rows) > 0, "A matrix needs at least one row.")
  brohn_require(brohn_number(q$min) && brohn_number(q$max) && q$min <= q$max && brohn_number(q$step, .000001), "Question range or step is invalid.")
  brohn_validate_rule(q$show_if, earlier_ids)
}
brohn_validate_design <- function(x, publish = FALSE) {
  brohn_fields(x, c("schema_version", "id", "project_id", "title", "description", "template", "archived", "tags", "conditions", "stimuli", "questions", "order", "seed", "baseline_ms", "fixation_ms", "instructions", "consent", "debrief", "appearance", "measures", "methods", "blocks", "lineage"), optional = c("analysis_plan", "camera", "scales", "maxdiff", "questionnaire_sections", "questionnaire_navigation"), label = "Design")
  if (!is.null(x$camera)) {
    brohn_require(exists("brohn_validate_camera_policy", mode = "function"), "This study requires its registered camera collection module.")
    brohn_validate_camera_policy(x$camera)
  }
  brohn_require(identical(x$schema_version, "brohn-design/1.0.0"), "Unsupported design schema. Import requires an explicit migration.")
  brohn_require(brohn_valid_id(x$id) && brohn_valid_id(x$project_id), "Invalid study or project identity.")
  brohn_require(brohn_text(x$title, 240) && brohn_text(x$description, 20000, TRUE), "Study title or description is invalid.")
  brohn_require(brohn_text(x$template, 96), "Template identity must be text.")
  brohn_validate_lineage(x$lineage)
  brohn_require(is.logical(x$archived) && length(x$archived) == 1 && !is.na(x$archived), "Archive status must be true or false.")
  for (field in c("conditions", "stimuli", "questions", "tags", "measures", "methods", "blocks")) brohn_require(brohn_array(x[[field]]), paste(field, "must be an array."))
  brohn_require(length(x$stimuli) <= 500 && length(x$questions) <= 200 && length(x$conditions) <= 100 && length(x$blocks) <= 200, "Study exceeds supported design limits.")
  if (length(x$blocks)) {
    brohn_require(exists("brohn_task_validate", mode = "function"), "This design needs its registered task profile module.")
    brohn_require(!anyDuplicated(brohn_ids(x$blocks)), "Task block IDs must be unique.")
    lapply(x$blocks, brohn_task_validate)
  }
  if (!is.null(x$maxdiff)) {
    brohn_require(exists("brohn_maxdiff_validate",mode="function") && brohn_array(x$maxdiff) && length(x$maxdiff)<=20L && !anyDuplicated(brohn_ids(x$maxdiff)),
      "Use up to 20 distinct best-worst exercises with their registered validator.")
    lapply(x$maxdiff,brohn_maxdiff_validate)
    if(publish) lapply(x$maxdiff,function(exercise) {
      review<-brohn_maxdiff_design_review(exercise)
      brohn_require(review$connected && review$all_items_present,"Connect and offer every item before releasing a best-worst exercise.")
    })
  }
  for (condition in x$conditions) {
    brohn_fields(condition, c("id", "label", "role"), label = "Condition")
    brohn_require(brohn_valid_id(condition$id) && brohn_text(condition$label, 240) && condition$role %in% c("control", "test", "neutral", "other"), "Invalid condition.")
  }
  brohn_require(!anyDuplicated(brohn_ids(x$conditions)) && !anyDuplicated(brohn_ids(x$stimuli)) && !anyDuplicated(brohn_ids(x$questions)), "Condition, stimulus and question IDs must be unique in their own namespace.")
  for (s in x$stimuli) {
    brohn_fields(s, c("id", "title", "condition_id", "type", "content", "asset", "duration_ms", "aois"), label = "Stimulus")
    brohn_require(brohn_valid_id(s$id) && brohn_text(s$title, 240) && s$condition_id %in% brohn_ids(x$conditions), "A stimulus needs a title and an existing condition.")
    brohn_require(s$type %in% c("text", "image", "audio", "video", "web"), "Unsupported stimulus type.")
    brohn_require(brohn_text(s$content, 20000, TRUE) && brohn_number(s$duration_ms, 100, 3600000, TRUE), "Stimulus content or duration is invalid.")
    if (!is.null(s$asset)) {
      brohn_fields(s$asset, c("hash", "size", "media_type"), c("filename", "width", "height"), "Asset")
      brohn_require(brohn_text(s$asset$hash, 64) && grepl("^[a-f0-9]{64}$", s$asset$hash) && brohn_number(s$asset$size, 1, 512*1024^2, TRUE) && brohn_text(s$asset$media_type, 120), "Invalid asset manifest.")
    }
    brohn_require(brohn_array(s$aois) && length(s$aois) <= 200, "AOIs must be an array of at most 200 regions.")
    for (a in s$aois) {
      brohn_fields(a, c("id", "label", "x", "y", "width", "height"), c("source", "asset_hash"), "AOI")
      brohn_require(brohn_valid_id(a$id) && brohn_text(a$label, 240), "AOI identity or label is invalid.")
      brohn_require(brohn_number(a$x, 0, 1) && brohn_number(a$y, 0, 1) && brohn_number(a$width, .000001, 1) && brohn_number(a$height, .000001, 1) && a$x+a$width <= 1.000000001 && a$y+a$height <= 1.000000001, "AOI must fit inside the stimulus coordinate frame.")
      if (!is.null(a$asset_hash)) brohn_require(!is.null(s$asset) && identical(a$asset_hash, s$asset$hash), "AOI refers to a replaced stimulus. Review the region.")
    }
    brohn_require(!anyDuplicated(brohn_ids(s$aois)), "AOI IDs must be unique within a stimulus.")
    if (publish) {
      if (s$type == "text") brohn_require(nzchar(trimws(s$content)), paste("Add content to", s$title))
      if (s$type %in% c("image", "audio", "video")) brohn_require(!is.null(s$asset), paste("Attach the media for", s$title))
      if (s$type == "web") brohn_require(grepl("^https://[^/[:space:]]+", s$content), "Web stimuli require an explicit HTTPS URL and supported delivery profile.")
    }
  }
  earlier <- list()
  for (q in x$questions) {
    allowed_scopes <- if (identical(q$scope, "before")) "before" else if (identical(q$scope, "after_each")) c("before", "after_each") else c("before", "end")
    ids <- brohn_ids(Filter(function(previous) previous$scope %in% allowed_scopes, earlier))
    brohn_validate_question(q, ids); earlier[[length(earlier)+1L]] <- q
    if (publish && q$scope == "after_each") brohn_require(length(x$stimuli) > 0, "After-each questions need at least one stimulus.")
  }
  brohn_require(x$order %in% c("fixed", "counterbalanced", "randomized"), "Unsupported stimulus order.")
  if (!is.null(x$scales)) {
    brohn_require(exists("brohn_validate_scales", mode = "function"), "This design requires its registered questionnaire-scale validator.")
    brohn_validate_scales(x$scales, x)
  }
  if ("questionnaire_sections" %in% names(x)) {
    brohn_require(exists("brohn_validate_question_sections", mode = "function"), "This design requires its registered questionnaire-section module.")
    brohn_validate_question_sections(x$questionnaire_sections, x)
  }
  if ("questionnaire_navigation" %in% names(x)) {
    brohn_require(exists("brohn_validate_questionnaire_navigation", mode = "function"), "This design requires its registered questionnaire answer-review module.")
    brohn_validate_questionnaire_navigation(x$questionnaire_navigation)
  }
  if (!is.null(x$analysis_plan)) {
    brohn_require(exists("brohn_validate_analysis_plan", mode = "function"), "This design requires its registered analysis-plan validator.")
    brohn_validate_analysis_plan(x$analysis_plan, x)
  }
  brohn_require(brohn_number(x$seed, 1, .Machine$integer.max, TRUE), "Randomization seed is invalid.")
  for (field in c("baseline_ms", "fixation_ms")) brohn_require(brohn_number(x[[field]], 0, 600000, TRUE), paste(field, "must be a supported whole duration."))
  brohn_require(brohn_text(x$instructions, 20000, TRUE) && brohn_text(x$debrief, 20000, TRUE), "Instructions or debrief exceed the supported text limit.")
  brohn_fields(x$consent, c("title", "text", "required"), label = "Consent")
  brohn_require(brohn_text(x$consent$title, 240) && brohn_text(x$consent$text, 40000) && is.logical(x$consent$required) && length(x$consent$required) == 1 && !is.na(x$consent$required), "Consent text and explicit required state are needed.")
  brohn_fields(x$appearance, c("background", "foreground"), label = "Participant appearance")
  brohn_require(all(vapply(x$appearance, function(v) brohn_text(v, 7) && grepl("^#[a-fA-F0-9]{6}$", v), logical(1))), "Participant colours must be explicit hexadecimal values.")
  known_measures <- c("gaze", "questionnaire", "eeg", "eda", "ecg", "ppg", "respiration", "emg", "eog", "fnirs", "temperature", "movement", "webcam_gaze", "facial_geometry", "facial_expression", "pose", "voice", "rt", "iat", "biat", "aat")
  brohn_require(all(vapply(x$measures, function(m) brohn_text(m, 96) && m %in% known_measures, logical(1))) && !anyDuplicated(unlist(x$measures)), "Invalid or duplicate selected measure.")
  brohn_require(length(x$tags) <= 30 && all(vapply(x$tags, brohn_text, logical(1), max = 80)), "Tags must be short text labels.")
  if (publish) brohn_require(length(x$stimuli) + length(x$questions) + length(x$blocks) + length(x$maxdiff) > 0, "Add stimuli, questions or a supported task before releasing the study.")
  invisible(x)
}
brohn_validate_lineage <- function(lineage) {
  if (is.null(lineage)) return(invisible(TRUE))
  brohn_require(is.list(lineage) && !is.null(names(lineage)) && brohn_text(lineage$operation, 80), "Design lineage requires a named operation.")
  fields <- switch(lineage$operation,
    clone_design = c("operation", "study_id", "design_hash", "source_revision"),
    legacy_import = c("operation", "study_id", "revision"),
    import_design = c("operation", "study_id", "revision", "design_hash", "package_hash"),
    use_template = c("operation", "template_id", "template_revision", "design_hash"),
    original_sample_design = c("operation", "origin"), NULL)
  brohn_require(!is.null(fields) && all(names(lineage) %in% fields), "Design lineage contains unsupported fields. Keep operational metadata outside portable designs.")
  for (field in intersect(names(lineage), c("study_id", "template_id"))) brohn_require(brohn_valid_id(lineage[[field]]), "Invalid source design identity.")
  for (field in intersect(names(lineage), c("revision", "source_revision", "template_revision"))) brohn_require(brohn_number(lineage[[field]], 1, .Machine$integer.max, TRUE), "Invalid source design revision.")
  for (field in intersect(names(lineage), c("design_hash", "package_hash"))) brohn_require(brohn_text(lineage[[field]], 64) && grepl("^[a-f0-9]{64}$", lineage[[field]]), "Invalid source design hash.")
  if (!is.null(lineage$origin)) brohn_require(identical(lineage$origin, "sample"), "The original example design must retain its sample origin.")
  invisible(TRUE)
}
brohn_design_issues <- function(x, publish = FALSE) tryCatch({brohn_validate_design(x, publish); character()}, error = function(e) conditionMessage(e))

# Pure, explicit draft migration. Never write through to a deployment or run.
# Non-randomized items keep their existing policy/absence and authored order.
brohn_upgrade_option_assignment <- function(design, question_ids = NULL) {
  brohn_validate_design(design)
  if (is.null(question_ids)) question_ids <- brohn_ids(design$questions)
  brohn_require(is.character(question_ids) && !anyNA(question_ids) && !anyDuplicated(question_ids) &&
    all(question_ids %in% brohn_ids(design$questions)), "Choose distinct existing questions for the option-assignment upgrade.")
  design$questions <- lapply(design$questions, function(q) {
    if (q$id %in% question_ids && isTRUE(q$randomize_options)) q$option_assignment <- "participant-sha256/1.0"
    q
  })
  design
}

.brohn_participant_options <- function(q, seed, allocation_index, stimulus_id) {
  # The versioned canonical JSON uses decimal strings for the two bounded
  # integers. Full SHA-256 ranks avoid ambient RNG kind/state and timeline-index
  # coupling. IDs are ASCII; radix ordering also gives a deterministic tie-break.
  ranks <- vapply(q$options, function(option) brohn_hash(list(
    schema_version = "brohn-option-assignment/1.0", seed = sprintf("%.0f", seed),
    allocation_index = sprintf("%.0f", allocation_index), question_id = q$id,
    scope = q$scope, stimulus_id = stimulus_id, option_id = option$id)), character(1))
  q$options[order(ranks, brohn_ids(q$options), method = "radix")]
}

brohn_compile <- function(design, allocation_index = 1L) {
  brohn_validate_design(design, publish = TRUE)
  brohn_require(brohn_number(allocation_index, 1, 1e9, TRUE), "Allocation index must be a positive whole number.")
  brohn_require(!length(design$blocks) || exists("brohn_task_compile", mode = "function"), "Enable the registered task compiler before releasing this design.")
  if (length(design$methods)) {
    brohn_require(exists("brohn_resolve_methods", mode = "function"), "Analysis recipe settings need a registered resolver before release.")
    brohn_resolve_methods(design$methods)
  }
  order <- seq_along(design$stimuli)
  if (length(order) && design$order == "counterbalanced") order <- c(order, order)[seq.int(((allocation_index-1L) %% length(order))+1L, length.out=length(order))]
  if (length(order) && design$order == "randomized") order <- brohn_seeded(((design$seed + allocation_index - 2) %% (.Machine$integer.max-1))+1, function() sample(order))
  timeline <- list(); questionnaire_assignments <- list(); design_hash <- brohn_hash(design)
  sectioned <- "questionnaire_sections" %in% names(design)
  sections_hash <- if (sectioned) brohn_hash(design$questionnaire_sections) else NULL
  append_step <- function(step) {
    step$id <- paste0("step-", length(timeline)+1L)
    timeline[[length(timeline)+1L]] <<- step
  }
  append_questions <- function(scope, stimulus = NULL) {
    plan <- if (sectioned) .brohn_question_sections_plan_validated(design, allocation_index, scope,
      if (is.null(stimulus)) NULL else stimulus$id, design_hash, sections_hash) else
      list(entries = lapply(Filter(function(q) q$scope == scope, design$questions), function(q) list(question = q, questionnaire = NULL)), manifest = NULL)
    if (!is.null(plan$manifest)) questionnaire_assignments[[length(questionnaire_assignments)+1L]] <<- plan$manifest
    for (entry in plan$entries) {
      q <- entry$question
      if (q$randomize_options && length(q$options)) {
        if (identical(q$option_assignment, "participant-sha256/1.0")) {
          q$options <- .brohn_participant_options(q, design$seed, allocation_index, if (is.null(stimulus)) NULL else stimulus$id)
        } else {
          # Missing policy is the original compiler contract. Preserve it for
          # future enrollments on old releases as well as saved run replay.
          q$options <- brohn_seeded(((design$seed + length(timeline)) %% (.Machine$integer.max-1))+1, function() sample(q$options))
        }
      }
      step <- list(type = "question", phase = "active_response", question = q,
        stimulus_id = if (is.null(stimulus)) NULL else stimulus$id,
        condition_id = if (is.null(stimulus)) NULL else stimulus$condition_id)
      if (!is.null(entry$questionnaire)) step$questionnaire <- entry$questionnaire
      append_step(step)
    }
  }
  if (nzchar(trimws(design$instructions))) append_step(list(type = "instructions", phase = "instructions", text = design$instructions))
  append_questions("before")
  for (i in order) {
    s <- design$stimuli[[i]]
    if (design$baseline_ms > 0) append_step(list(type = "baseline", phase = "baseline", duration_ms = design$baseline_ms, stimulus_id = s$id, condition_id = s$condition_id))
    if (design$fixation_ms > 0) append_step(list(type = "fixation", phase = "fixation", duration_ms = design$fixation_ms, stimulus_id = s$id, condition_id = s$condition_id))
    append_step(list(type = "stimulus", phase = "passive_viewing", stimulus = s, stimulus_id = s$id, condition_id = s$condition_id, duration_ms = s$duration_ms))
    append_questions("after_each", s)
  }
  for (block in design$blocks) append_step(list(type = "task", phase = "implicit_task", task = brohn_task_compile(block, allocation_index)))
  for (exercise in design$maxdiff) for (step in brohn_maxdiff_steps(exercise,allocation_index)) append_step(step)
  append_questions("end")
  total_steps <- length(timeline) + sum(vapply(Filter(function(s) s$type == "task", timeline), function(s) length(s$task$timeline), integer(1)))
  brohn_require(total_steps <= 20000L, "The complete protocol exceeds 20,000 supported steps.")
  protocol <- list(schema_version = "brohn-protocol/1.0.0", design = design, design_hash = design_hash,
    allocation_index = allocation_index, realized_stimulus_order = as.list(vapply(design$stimuli[order], function(s) s$id, character(1))),
    timeline = timeline, timing_evidence = "browser_observation_not_physical_qualification")
  if (sectioned) protocol$questionnaire_assignments <- questionnaire_assignments
  if ("questionnaire_navigation" %in% names(design)) protocol <- brohn_questionnaire_revision_decorate(protocol)
  protocol
}

brohn_clone_design <- function(design, title = paste(design$title, "copy"), project_id = design$project_id) {
  brohn_validate_design(design)
  source <- list(study_id = design$id, design_hash = brohn_hash(design), operation = "clone_design")
  result <- design; result$id <- brohn_id("study"); result$title <- title; result$project_id <- project_id; result$archived <- FALSE; result$lineage <- source
  remap <- function(items, prefix) setNames(vapply(items, function(x) brohn_id(prefix), character(1)), brohn_ids(items))
  condition_map <- remap(result$conditions, "condition"); stimulus_map <- remap(result$stimuli, "stimulus"); question_map <- remap(result$questions, "q")
  map_rule <- function(rule) {
    if (is.null(rule)) return(NULL)
    if (!is.null(rule[["question_id"]])) rule$question_id <- unname(question_map[[rule[["question_id"]]]])
    if (!is.null(rule[["rules"]])) rule$rules <- lapply(rule[["rules"]], map_rule)
    if (!is.null(rule[["rule"]])) rule$rule <- map_rule(rule[["rule"]])
    rule
  }
  result$conditions <- lapply(result$conditions, function(x) {x$id <- unname(condition_map[[x$id]]); x})
  result$stimuli <- lapply(result$stimuli, function(s) {
    s$id <- unname(stimulus_map[[s$id]]); s$condition_id <- unname(condition_map[[s$condition_id]])
    s$aois <- lapply(s$aois, function(a) {a$id <- brohn_id("aoi"); a}); s
  })
  result$questions <- lapply(result$questions, function(q) {q$id <- unname(question_map[[q$id]]); q["show_if"] <- list(map_rule(q$show_if)); q})
  if ("questionnaire_sections" %in% names(result)) result$questionnaire_sections <- brohn_clone_question_sections(result$questionnaire_sections, question_map)
  scale_map <- character()
  if (!is.null(result$scales)) {
    original_ids <- brohn_ids(result$scales)
    result$scales <- brohn_clone_scales(result$scales, question_map)
    scale_map <- stats::setNames(brohn_ids(result$scales), original_ids)
  }
  if (!is.null(result$analysis_plan)) result$analysis_plan <- brohn_clone_analysis_plan(result$analysis_plan, condition_map, question_map, scale_map)
  if (length(result$blocks)) {
    brohn_require(exists("brohn_task_clone", mode = "function"), "Cloning this task graph requires its registered identity mapper.")
    result$blocks <- lapply(result$blocks, brohn_task_clone)
  }
  if (!is.null(result$maxdiff)) result$maxdiff <- lapply(result$maxdiff,brohn_maxdiff_clone)
  brohn_validate_design(result); result
}

brohn_legacy_design <- function(study, project_id = "default") {
  errors <- validate_study(study); if (length(errors)) brohn_stop(paste(errors, collapse = "; "))
  result <- brohn_new_design(brohn_default(study$title, "Imported legacy study"), id = brohn_id("study"), project_id = project_id)
  settings <- presentation_settings(study)
  result$order <- if (settings$order == "counterbalanced_ab_ba") "counterbalanced" else "fixed"
  indices <- if (settings$order == "fixed_ba") 2:1 else 1:2
  control <- comparison_settings(study)$control_condition
  result$conditions <- lapply(1:2, function(i) list(id = paste0("condition-", tolower(study$conditions[i])), label = study$conditions[i], role = if (control == "none") "other" else if (study$conditions[i] == control) "control" else "test"))
  result$stimuli <- lapply(indices, function(i) list(id = study$stimulus_ids[i], title = paste("Design", study$conditions[i]), condition_id = result$conditions[[i]]$id,
    type = "image", content = "", asset = NULL, duration_ms = settings$viewing_duration_ms, aois = list()))
  result$questions <- lapply(study$questions, function(q) {
    out <- brohn_question(q$prompt, "single_choice", "after_each", q$id); out$required <- q$required
    out$options <- lapply(seq_along(q$option_ids), function(i) list(id = q$option_ids[i], label = q$labels[i], value = q$codes[i])); out
  })
  result$lineage <- list(operation = "legacy_import", study_id = study$id, revision = study$revision)
  result
}
