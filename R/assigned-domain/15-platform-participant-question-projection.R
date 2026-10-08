# Inactive pure kernel. No loader or legacy participant dispatch is changed.
.brohn_pvq_finite <- c("rating", "single_choice", "dropdown", "multiple_choice", "matrix", "ranking", "allocation")
.brohn_pvq_key <- function(x) is.character(x) && length(x) == 1L && !is.na(x) &&
  nchar(x, type = "bytes") == 68L && grepl("^pvq-[a-f0-9]{64}$", x)
.brohn_pvq_typed_equal <- function(a, b) identical(brohn_json(a), brohn_json(b))
.brohn_pvq_plain <- function(value) {
  # Reuse the accepted original-byte UTF8/plain-value boundary. No source or
  # validation flag is substituted; every supplied value is traversed here.
  .brohn_vad_domain(value)
  brohn_require(nchar(brohn_json(value), type = "bytes") <= 16 * 1024^2,
    "Questionnaire projection input exceeds its 16 MiB bound.")
  invisible(TRUE)
}

.brohn_pvq_questions <- function(questions) {
  .brohn_pvq_plain(questions)
  brohn_require(brohn_array(questions) && length(questions) <= 200L, "Unsupported question collection.")
  earlier <- list()
  for (q in questions) {
    brohn_require(brohn_text(q$type, 40L) && brohn_text(q$scope, 40L), "Question profile and scope must be scalar text.")
    allowed <- switch(q$scope, before = "before", after_each = c("before", "after_each"), end = c("before", "end"), character())
    brohn_validate_question(q, brohn_ids(Filter(function(p) p$scope %in% allowed, earlier)))
    earlier[[length(earlier) + 1L]] <- q
  }
  brohn_require(!anyDuplicated(brohn_ids(questions)), "Question identities must be unique.")
  invisible(questions)
}

brohn_participant_question_map <- function(questions) {
  .brohn_pvq_questions(questions)
  used <- new.env(parent = emptyenv(), hash = TRUE)
  source_ids <- c(brohn_ids(questions), unlist(lapply(questions, function(q) c(brohn_ids(q$options), brohn_ids(q$rows))), use.names = FALSE))
  for (id in source_ids) assign(id, TRUE, envir = used)
  key <- function() {
    value <- paste0("pvq-", brohn_token())
    brohn_require(.brohn_pvq_key(value) && !exists(value, envir = used, inherits = FALSE), "Participant key collision; no map was created.")
    assign(value, TRUE, envir = used); value
  }
  entries <- lapply(questions, function(q) list(source_id = q$id, type = q$type, scope = q$scope, question_key = key(),
    options = if (q$type %in% .brohn_pvq_finite) lapply(q$options, function(o)
      list(source_id = o$id, option_key = key(), source_value = o$value)) else list(),
    rows = if (identical(q$type, "matrix")) lapply(q$rows, function(r) list(source_id = r$id, row_key = key())) else list()))
  result <- list(schema = "participant-question-map/0.1", entries = entries)
  .brohn_pvq_validate_map(result)
  result
}

.brohn_pvq_validate_map <- function(map) {
  .brohn_pvq_plain(map)
  brohn_fields(map, c("schema", "entries"), label = "Private participant question map")
  brohn_require(identical(map$schema, "participant-question-map/0.1") && brohn_array(map$entries) && length(map$entries) <= 200L,
    "Unsupported private question map.")
  keys <- character(); ids <- character(); source_ids <- character()
  for (q in map$entries) {
    brohn_fields(q, c("source_id", "type", "scope", "question_key", "options", "rows"), label = "Private question mapping")
    brohn_require(brohn_valid_id(q$source_id) && .brohn_pvq_key(q$question_key) && brohn_text(q$type, 40L) && brohn_text(q$scope, 40L) &&
      q$type %in% c(.brohn_pvq_finite, "number", "slider", "text", "long_text", "information") &&
      q$scope %in% c("before", "after_each", "end") &&
      brohn_array(q$options) && length(q$options) <= 100L && brohn_array(q$rows) && length(q$rows) <= 100L,
      "Invalid private question mapping.")
    keys <- c(keys, q$question_key); ids <- c(ids, q$source_id)
    option_ids <- row_ids <- character()
    for (o in q$options) {
      brohn_fields(o, c("source_id", "option_key", "source_value"), label = "Private option mapping")
      brohn_require(brohn_valid_id(o$source_id) && .brohn_pvq_key(o$option_key) &&
        (brohn_number(o$source_value) || brohn_text(o$source_value, 1000L) ||
          (is.logical(o$source_value) && length(o$source_value) == 1L && !is.na(o$source_value))), "Invalid private option mapping.")
      keys <- c(keys, o$option_key); option_ids <- c(option_ids, o$source_id)
    }
    for (r in q$rows) {
      brohn_fields(r, c("source_id", "row_key"), label = "Private row mapping")
      brohn_require(brohn_valid_id(r$source_id) && .brohn_pvq_key(r$row_key), "Invalid private row mapping.")
      keys <- c(keys, r$row_key); row_ids <- c(row_ids, r$source_id)
    }
    brohn_require(!anyDuplicated(option_ids) && !anyDuplicated(row_ids), "Private question mapping repeats a source identity.")
    source_ids <- c(source_ids, q$source_id, option_ids, row_ids)
    if (q$type %in% c("rating", "single_choice", "dropdown", "multiple_choice", "matrix"))
      brohn_require(!anyDuplicated(vapply(q$options, function(o) brohn_json(o$source_value), character(1))), "Private option mapping repeats a typed code.")
    brohn_require(if (q$type %in% .brohn_pvq_finite) length(q$options) >= 2L else !length(q$options), "Option mapping differs from question type.")
    brohn_require(if (q$type == "matrix") length(q$rows) >= 1L else !length(q$rows), "Row mapping differs from question type.")
  }
  brohn_require(!anyDuplicated(keys) && !anyDuplicated(ids), "Private question mapping repeats a key or question.")
  brohn_require(!any(keys %in% source_ids), "Private question mapping reuses a source identity as a participant key.")
  invisible(map)
}

.brohn_pvq_lookup <- function(items, field, value) {
  hits <- Filter(function(item) identical(item[[field, exact = TRUE]], value), items)
  brohn_require(length(hits) == 1L, "Questionnaire key is unavailable in this scope.")
  hits[[1L]]
}

.brohn_pvq_rule <- function(rule, map) {
  if (is.null(rule)) return(NULL)
  if (rule$op %in% c("and", "or")) return(list(kind = if (rule$op == "and") "all" else "any",
    rules = lapply(rule$rules, .brohn_pvq_rule, map = map)))
  if (rule$op == "not") return(list(kind = "not", rule = .brohn_pvq_rule(rule$rule, map)))
  q <- .brohn_pvq_lookup(map$entries, "source_id", rule$question_id)
  if (rule$op == "answered") return(list(kind = "answered", question_key = q$question_key))
  constant <- function(value) list(kind = "answered_constant", question_key = q$question_key, result = value)
  if (q$type == "information") return(constant(FALSE))
  if (q$type %in% c("multiple_choice", "matrix", "ranking", "allocation") && rule$op != "contains")
    return(constant(identical(rule$op, "not_equals")))
  if (q$type == "allocation") {
    if (!brohn_number(rule$value)) return(constant(FALSE))
    return(list(kind = "input_compare", question_key = q$question_key, op = rule$op, value = rule$value))
  }
  if (q$type %in% .brohn_pvq_finite) {
    passing <- Filter(function(o) {
      value <- if (q$type == "ranking") o$source_id else o$source_value
      brohn_rule(rule, setNames(list(value), q$source_id))
    }, q$options)
    return(list(kind = "token_match", question_key = q$question_key,
      shape = if (q$type == "matrix") "row_values" else if (q$type %in% c("multiple_choice", "ranking")) "array" else "scalar",
      keys = lapply(passing, `[[`, "option_key")))
  }
  list(kind = "input_compare", question_key = q$question_key, op = rule$op, value = rule$value)
}

brohn_project_participant_question <- function(question, map, resource_key = NULL) {
  .brohn_pvq_validate_map(map)
  .brohn_pvq_plain(question)
  q <- .brohn_pvq_lookup(map$entries, "source_id", question$id)
  brohn_require(identical(q$type, question$type) && identical(q$scope, question$scope), "Question profile or scope differs from its private map.")
  position <- which(vapply(map$entries, function(entry) identical(entry$source_id, question$id), logical(1)))
  prior <- map$entries[seq_len(position - 1L)]
  allowed <- switch(question$scope, before = "before", after_each = c("before", "after_each"), end = c("before", "end"))
  prior <- Filter(function(entry) entry$scope %in% allowed, prior)
  brohn_validate_question(question, vapply(prior, `[[`, character(1), "source_id"))
  result <- list(question_key = q$question_key, type = question$type, prompt = question$prompt,
    required = question$required, scope = question$scope)
  if (question$type %in% .brohn_pvq_finite) {
    brohn_require(setequal(brohn_ids(question$options), vapply(q$options, `[[`, character(1), "source_id")), "Question options differ from their private map.")
    result$options <- lapply(question$options, function(o) {
      entry <- .brohn_pvq_lookup(q$options, "source_id", o$id)
      brohn_require(.brohn_pvq_typed_equal(o$value, entry$source_value), "Typed option code differs from its private map.")
      list(option_key = entry$option_key, label = o$label)
    })
  }
  if (question$type == "matrix") {
    brohn_require(setequal(brohn_ids(question$rows), vapply(q$rows, `[[`, character(1), "source_id")), "Question rows differ from their private map.")
    result$rows <- lapply(question$rows, function(r) list(row_key = .brohn_pvq_lookup(q$rows, "source_id", r$id)$row_key, label = r$label))
  }
  if (question$type %in% c("number", "slider")) result <- c(result, question[c("min", "max", "step")])
  if (question$type == "allocation") result <- c(result, question[c("max", "step")])
  result["rule"] <- list(.brohn_pvq_rule(question$show_if, map))
  if ("illustration" %in% names(question)) {
    brohn_require(is.function(resource_key), "An assigned illustration resource mapper is required.")
    key <- resource_key(question$illustration$asset)
    brohn_require(is.character(key) && length(key) == 1L && !is.na(key) && nchar(key, type = "bytes") == 68L &&
      grepl("^pvr-[a-f0-9]{64}$", key), "Invalid assigned illustration resource key.")
    result$illustration <- list(resource_key = key, image_alt = question$illustration$image_alt)
  }
  result
}

# Bidirectional shape/identity transformation only. Final source answer/replay
# validation stays authoritative and is required separately by future ingestion.
brohn_translate_participant_answer <- function(map, question_key, value, direction = c("to_source", "to_view")) {
  direction <- match.arg(direction); .brohn_pvq_validate_map(map)
  q <- .brohn_pvq_lookup(map$entries, "question_key", question_key)
  .brohn_pvq_plain(value)
  if (is.null(value)) return(NULL)
  incoming <- identical(direction, "to_source")
  option <- function(value, id = FALSE) {
    if (incoming) {
      brohn_require(.brohn_pvq_key(value), "An answer requires a scoped option key.")
      found <- .brohn_pvq_lookup(q$options, "option_key", value)
      if (id) found$source_id else found$source_value
    } else {
      found <- if (id) .brohn_pvq_lookup(q$options, "source_id", value) else {
        hits <- Filter(function(o) .brohn_pvq_typed_equal(o$source_value, value), q$options)
        brohn_require(length(hits) == 1L, "Typed response has no unique option mapping."); hits[[1L]]
      }
      found$option_key
    }
  }
  if (q$type %in% c("rating", "single_choice", "dropdown")) return(option(value))
  if (q$type %in% c("multiple_choice", "ranking")) {
    brohn_require(brohn_array(value) && length(value) <= length(q$options), "Selected answers must be a bounded array.")
    result <- lapply(value, option, id = q$type == "ranking")
    brohn_require(!anyDuplicated(vapply(result, brohn_json, character(1))), "Selected answers repeat an option.")
    return(result)
  }
  if (q$type %in% c("matrix", "allocation")) {
    entries <- if (q$type == "matrix") q$rows else q$options
    public <- if (q$type == "matrix") "row_key" else "option_key"
    brohn_require(is.list(value) && !is.null(names(value)) && !anyNA(names(value)) && !anyDuplicated(names(value)) && length(value) <= length(entries),
      "Structured answers require unique scoped keys.")
    output_keys <- vapply(names(value), function(name) {
      entry <- .brohn_pvq_lookup(entries, if (incoming) public else "source_id", name)
      entry[[if (incoming) "source_id" else public]]
    }, character(1), USE.NAMES = FALSE)
    result <- lapply(value, function(v) {
      if (is.null(v)) return(NULL)
      if (q$type == "matrix") return(option(v))
      brohn_require(brohn_number(v), "An allocation entry must retain an actual finite number or null."); v
    })
    names(result) <- output_keys; return(result)
  }
  if (q$type %in% c("number", "slider")) {
    brohn_require(brohn_number(value), "A numeric answer must retain an actual finite number."); return(value)
  }
  if (q$type %in% c("text", "long_text")) {
    brohn_require(brohn_text(value, if (q$type == "text") 20000 else 200000, TRUE), "A text answer must retain its actual text."); return(value)
  }
  brohn_stop("Information acknowledgments do not contain a scored answer.")
}
