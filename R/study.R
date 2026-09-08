# Sprint 1: pure, dependency-free draft contracts. No acquisition or scoring.
contract_version <- "0.1.0"
measure_registry <- function() {
  data.frame(
    id = c("eye", "eeg", "eda", "rt", "aat", "biat", "questionnaire",
           "webcam_gaze", "facial_geometry", "facial_expression"),
    maturity = "planned", stringsAsFactors = FALSE
  )
}

scalar_text <- function(x) {
  is.character(x) && length(x) == 1L && !is.na(x) && nzchar(trimws(x))
}
positive_integer <- function(x) {
  is.numeric(x) && length(x) == 1L && !is.na(x) && is.finite(x) &&
    x >= 1 && x == floor(x)
}

new_study <- function(id = "sample-study", include_liking = TRUE,
                      title = "Compare two designs") {
  stopifnot(is.logical(include_liking), length(include_liking) == 1L,
            !is.na(include_liking))
  question <- list(
    id = "q-liking", revision = 1L, type = "single_choice",
    prompt = "How much do you like this design?",
    scope = "after_each_stimulus", required = FALSE,
    option_ids = paste0("like-", 1:7), codes = 1:7,
    labels = c("Not at all", "2", "3", "4", "5", "6", "Very much")
  )
  study <- list(
    schema_version = contract_version, id = id, title = title, revision = 1L,
    design = "paired_two_images", conditions = c("A", "B"),
    stimulus_ids = c("stimulus-a", "stimulus-b"),
    measures = c("eye", if (include_liking) "questionnaire"),
    questions = if (include_liking) list(question) else list(),
    analysis = list(method_id = "aoi-valid-gaze-time-share/0.1.0-draft",
                    contrast = "B-A", status = "unqualified")
  )
  errors <- validate_study(study)
  if (length(errors)) stop(paste(errors, collapse = "; "), call. = FALSE)
  study
}

validate_study <- function(x) {
  if (!is.list(x)) return("study: expected a named list")
  errors <- character()
  check <- function(ok, message) {
    if (!isTRUE(ok)) errors <<- c(errors, message)
  }
  check(identical(x$schema_version, contract_version), "schema_version: unsupported")
  check(scalar_text(x$id), "id: nonempty string required")
  if ("title" %in% names(x)) check(scalar_text(x$title), "title: nonempty text required")
  check(positive_integer(x$revision), "revision: positive integer required")
  check(identical(x$design, "paired_two_images"), "design: only paired_two_images is implemented")
  check(identical(x$conditions, c("A", "B")), "conditions: ordered A/B required")
  valid_ids <- function(v, n) is.character(v) && length(v) == n &&
    !anyNA(v) && all(nzchar(trimws(v))) && !anyDuplicated(v)
  check(valid_ids(x$stimulus_ids, 2L), "stimulus_ids: two distinct IDs required")
  measures_ok <- is.character(x$measures) && length(x$measures) > 0L &&
    !anyNA(x$measures) && !anyDuplicated(x$measures) &&
    all(x$measures %in% measure_registry()$id) && "eye" %in% x$measures
  check(measures_ok, "measures: unique known IDs including eye required")
  check(is.list(x$questions), "questions: list required")
  if (measures_ok && is.list(x$questions)) {
    expected <- if ("questionnaire" %in% x$measures) 1L else 0L
    check(length(x$questions) == expected, "questions: must match questionnaire selection")
    if (length(x$questions) == 1L) {
      q <- x$questions[[1L]]
      if (!is.list(q)) check(FALSE, "question: expected list") else {
        check(scalar_text(q$id) && positive_integer(q$revision), "question: stable ID/revision required")
        check(identical(q$type, "single_choice") && scalar_text(q$prompt), "question: supported type and prompt required")
        check(identical(q$scope, "after_each_stimulus"), "question.scope: after_each_stimulus required")
        check(is.logical(q$required) && length(q$required) == 1L && !is.na(q$required), "question.required: boolean required")
        check(valid_ids(q$option_ids, 7L) && is.numeric(q$codes) && identical(as.numeric(q$codes), as.numeric(1:7)), "question: seven unique options and ordered codes 1..7 required")
        check(is.character(q$labels) && length(q$labels) == 7L && !anyNA(q$labels) && all(nzchar(trimws(q$labels))), "question.labels: seven nonempty labels required")
      }
    }
  }
  if (!is.list(x$analysis)) check(FALSE, "analysis: list required") else {
    check(identical(x$analysis$method_id, "aoi-valid-gaze-time-share/0.1.0-draft"), "analysis.method_id: draft method required")
    check(identical(x$analysis$contrast, "B-A"), "analysis.contrast: B-A required")
    check(identical(x$analysis$status, "unqualified"), "analysis.status: qualification not implemented")
  }
  if ("comparison" %in% names(x)) errors <- c(errors, validate_comparison(x))
  if ("presentation" %in% names(x)) errors <- c(errors, validate_presentation(x))
  errors
}

new_session <- function(study, id, participant_id, mode = "sample") {
  errors <- validate_study(study)
  if (length(errors)) stop(paste(errors, collapse = "; "), call. = FALSE)
  if (!scalar_text(id) || !scalar_text(participant_id) ||
      !scalar_text(mode) || !mode %in% c("sample", "preview", "pilot", "live"))
    stop("session: IDs and a supported origin mode required", call. = FALSE)
  list(schema_version = contract_version, id = id, participant_id = participant_id,
       study_id = study$id, study_revision = study$revision, mode = mode,
       execution = "not_started", capture = "not_started",
       transfer = "not_started", review = "not_started")
}
