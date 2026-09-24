# Local vision evidence, immutable artifacts, and explicit researcher review.
brohn_vision_profiles <- function() list(
  list(id = "face_geometry_v1", label = "Face geometry and native blendshapes", channels = list("face")),
  list(id = "face_pose_hands_v1", label = "Face, body and hand geometry", channels = list("face", "pose", "hands")),
  list(id = "custom_v1", label = "Selected geometry channels", channels = list("face", "pose", "hands")),
  list(id = "facial_au_expression_pyfeat_v1", label = "Native facial action units and expression categories", channels = list()))

brohn_validate_vision_mapping <- function(dataset) {
  if (identical(dataset$metadata$profile,"facial_au_expression_pyfeat_v1")) return(brohn_validate_facial_mapping(dataset))
  brohn_require(identical(dataset$modality, "video") && dataset$source$format %in% c("mp4", "mov", "mkv", "webm", "avi"),
    "Imported video geometry needs an MP4/MOV, Matroska/WebM or AVI recording.")
  m <- dataset$metadata
  brohn_require(is.list(m) && brohn_text(m$origin_statement, 4000), "Describe the video source and how it was collected.")
  brohn_require(all(names(m) %in% c("origin_statement", "profile", "channels", "start_s", "end_s", "max_support_gap_s")),
    "This video profile contains an unregistered setting.")
  profile <- brohn_default(m$profile, "face_geometry_v1")
  brohn_require(profile %in% vapply(brohn_vision_profiles(), `[[`, character(1), "id"), "Choose a registered video geometry profile.")
  if (identical(profile, "custom_v1")) {
    brohn_require(brohn_array(m$channels) && length(m$channels) > 0L && length(m$channels) <= 3L &&
      all(unlist(m$channels, use.names = FALSE) %in% c("face", "pose", "hands")) && !anyDuplicated(unlist(m$channels)),
      "Select distinct face, pose or hands channels.")
  } else brohn_require(is.null(m$channels), "Custom channel selection requires the custom profile.")
  for (field in c("start_s", "end_s")) if (!is.null(m[[field]])) brohn_require(brohn_number(m[[field]], 0, 600), "Video interval times must be between 0 and 600 seconds.")
  if (!is.null(m$end_s)) brohn_require(m$end_s > brohn_default(m$start_s, 0), "Video interval end must follow its start.")
  if (!is.null(m$max_support_gap_s)) brohn_require(brohn_number(m$max_support_gap_s, .001, 10), "Video time-support gap must be between 0.001 and 10 seconds.")
  invisible(dataset)
}

brohn_vision_request <- function(input, scratch) {
  operation <- if (identical(input$operation, "segment_aoi")) "segment_aoi" else "analyse_video"
  if (identical(operation, "analyse_video")) {
    brohn_validate_vision_mapping(input$dataset)
    metadata <- input$dataset$metadata; metadata$origin_statement <- NULL
    if (is.null(metadata$profile)) metadata$profile <- "face_geometry_v1"
    source_hash <- input$dataset$source$hash
  } else {metadata <- list(prompt = input$prompt); source_hash <- input$source_hash}
  directory <- file.path(scratch, "artifacts")
  brohn_require(dir.exists(directory) || dir.create(directory), "Cannot prepare the isolated artifact directory.")
  list(schema = "brohn-vision-request/1.0", operation = operation,
    source_path = normalizePath(input$source_path, winslash = "/", mustWork = TRUE), source_hash = source_hash,
    metadata = metadata, output_directory = normalizePath(directory, winslash = "/", mustWork = TRUE))
}

brohn_run_vision <- function(input, scratch) {
  if (identical(input$operation,"analyse_dataset") && identical(input$dataset$metadata$profile,"facial_au_expression_pyfeat_v1")) return(brohn_run_facial_expression(input,scratch))
  request <- brohn_vision_request(input, scratch)
  request_path <- file.path(scratch, "vision-request.json"); result_path <- file.path(scratch, "vision-result.json")
  brohn_write_json_file(request, request_path)
  process <- processx::run(brohn_python_profile(if (request$operation == "segment_aoi") "segmentation" else "video"),
    c("scripts/workers/vision.py", "--request", request_path, "--output", result_path),
    timeout = 30*60, echo = FALSE, error_on_status = FALSE, cleanup_tree = TRUE, windows_hide_window = TRUE)
  brohn_require(file.exists(result_path), paste("The vision worker returned no result.", substr(process$stderr, 1, 1000)))
  result <- brohn_read_json_file(result_path)
  brohn_require(identical(result$schema, "brohn-vision-result/1.0") && identical(result$operation, request$operation), "Vision worker returned an incompatible result.")
  message <- brohn_default(result$error$message, substr(process$stderr, 1, 1500))
  brohn_require(process$status == 0 && !identical(result$status, "error"), paste("Vision analysis needs attention:", message))
  brohn_require(identical(result$source$sha256, request$source_hash), "Vision worker source identity changed.")
  result$kind <- if (request$operation == "segment_aoi") "aoi_proposal" else "video"
  result$title <- if (request$operation == "segment_aoi") "AOI proposal for review" else "Video geometry and native model outputs"
  result$contrasts <- list()
  result
}

brohn_queue_aoi_proposal <- function(store, study_id, stimulus_id, prompt, revision = NULL) {
  study <- brohn_study(store, study_id, revision)
  brohn_require(!isTRUE(brohn_study(store, study_id)$body$archived), "Restore this study before proposing an AOI.")
  brohn_project(store, study$project_id)
  stimulus <- brohn_find(study$body$stimuli, stimulus_id)
  brohn_require(!is.null(stimulus) && identical(stimulus$type, "image") && identical(stimulus$asset$media_type, "image/png"),
    "Choose a saved PNG image stimulus before proposing an AOI.")
  brohn_require(is.list(prompt) && identical(sort(names(prompt)), c("x", "y")) &&
    brohn_number(prompt$x, 0, 1) && brohn_number(prompt$y, 0, 1), "Choose a point inside the image.")
  brohn_object_path(store, stimulus$asset$hash)
  request <- list(study_id = study_id, study_revision = study$revision, study_hash = brohn_hash(study$body),
    stimulus_id = stimulus_id, source_hash = stimulus$asset$hash, prompt = prompt, recipe = "magictouch-v1-click-proposal/1.0.0")
  brohn_enqueue_job(store, "segment_aoi", request, paste0("aoi-proposal:", brohn_hash(request)))
}

brohn_aoi_proposal_input <- function(store, job) {
  r <- job$request
  study <- brohn_study(store, r$study_id, r$study_revision)
  brohn_require(identical(brohn_hash(study$body), r$study_hash), "Pinned AOI study revision failed its integrity check.")
  stimulus <- brohn_find(study$body$stimuli, r$stimulus_id)
  brohn_require(!is.null(stimulus) && identical(stimulus$type, "image") && identical(stimulus$asset$media_type, "image/png") &&
    identical(stimulus$asset$hash, r$source_hash), "Pinned AOI stimulus failed its integrity check.")
  list(schema = "brohn-analysis-input/1.0", operation = "segment_aoi", project_id = study$project_id,
    design = study$body, design_revision = study$revision, stimulus_id = stimulus$id,
    source_hash = r$source_hash, source_path = brohn_object_path(store, r$source_hash), prompt = r$prompt)
}

brohn_analyse_aoi_proposal <- function(input, scratch) list(title = "AOI proposal for review", study_id = input$design$id,
  dataset_id = NULL, origin = "design_artifact", analysis = brohn_run_vision(input, scratch),
  provenance = list(study_id = input$design$id, study_revision = input$design_revision,
    design_hash = brohn_hash(input$design), stimulus_id = input$stimulus_id, source_hash = input$source_hash,
    prompt = input$prompt, design = input$design))

brohn_checked_artifact_path <- function(store, path, scratch) {
  brohn_require(brohn_text(path, 4096) && file.exists(path) && !dir.exists(path), "Worker artifact file is unavailable.")
  canonical <- .brohn_store_contained(store, path)
  directory <- normalizePath(file.path(scratch, "artifacts"), winslash = "/", mustWork = TRUE)
  check_path <- canonical; check_directory <- directory
  if (.Platform$OS.type == "windows") {check_path <- tolower(check_path); check_directory <- tolower(check_directory)}
  brohn_require(startsWith(check_path, paste0(check_directory, "/")), "Worker artifact leaves this attempt's artifact directory.")
  canonical
}

.brohn_check_worker_artifacts <- function(store, analysis, scratch, verify_hashes = TRUE) {
    items <- brohn_default(analysis$artifacts, list())
    brohn_require(brohn_array(items) && length(items) <= 8L, "Worker artifact manifest is too large.")
    if (any(vapply(items, function(a) a$kind %in% c("physiology-series", "physiology-events"), logical(1)))) brohn_validate_physiology_artifact_receipt(analysis)
    if (any(vapply(items, function(a) a$kind %in% c("facial-observations", "facial-values"), logical(1)))) brohn_validate_facial_artifact_manifest(analysis)
    checked <- lapply(items, function(item) {
      brohn_require(item$kind %in% c("aoi-mask", "vision-observations", "facial-observations", "facial-values", "physiology-series", "physiology-events", "questionnaire-analysis") && brohn_text(item$sha256, 64) &&
        grepl("^[a-f0-9]{64}$", item$sha256) && brohn_number(item$bytes, 1, 2*1024^3, TRUE), "Worker artifact manifest is invalid.")
      path <- brohn_checked_artifact_path(store, item$path, scratch)
      brohn_require(identical(as.numeric(file.info(path)$size), as.numeric(item$bytes)) &&
        (!verify_hashes || identical(digest::digest(file = path, algo = "sha256"), item$sha256)), "Worker artifact failed its size or SHA-256 check.")
      metadata <- list()
      if (item$kind %in% c("facial-observations", "facial-values")) metadata <- item[c("schema", "complete")]
      if (identical(item$kind, "questionnaire-analysis")) {
        brohn_require(brohn_questionnaire_is_artifact(analysis), "Questionnaire evidence requires its complete verified report preview schema.")
        normalized <- .brohn_questionnaire_reference(item, .brohn_questionnaire_artifact_bytes)
        metadata <- normalized[c("schema", "node_count", "analysis_sha256", "analysis_bytes", "source_binding", "source_binding_sha256", "counts", "line_bytes")]
      }
      if (item$kind %in% c("physiology-series", "physiology-events")) {
        brohn_require(identical(item$schema, "brohn-physiology-tables/1.0") && isTRUE(item$complete) &&
          brohn_number(item$tables, 1, 100000, TRUE) && brohn_number(item$rows, 0, 1e9, TRUE) &&
          brohn_text(item$provenance_sha256, 64) && grepl("^[a-f0-9]{64}$", item$provenance_sha256), "Complete processed artifact counts or provenance are invalid.")
        metadata <- item[intersect(names(item), c("schema", "tables", "rows", "provenance_sha256", "complete", "preview_rows", "preview_policy"))]
      }
      list(path = path, kind = item$kind, hash = item$sha256, size = item$bytes, metadata = metadata)
    })
    brohn_require(!anyDuplicated(vapply(checked, `[[`, character(1), "kind")), "Worker returned duplicate artifact kinds.")
    checked
}
.brohn_worker_artifact_analysis <- function(analysis, promoted) {
    analysis$artifacts <- promoted
    if (!is.null(analysis$proposal)) {
      masks <- Filter(function(a) identical(a$kind, "aoi-mask"), promoted)
      if (identical(analysis$proposal$status, "needs_review")) {
        brohn_require(length(masks) == 1L && identical(masks[[1]]$hash, analysis$proposal$mask_sha256), "AOI proposal does not match its preserved mask.")
        analysis$proposal$mask_object <- masks[[1]]
      } else brohn_require(length(masks) == 0L && identical(analysis$proposal$status, "no_proposal"), "Unexpected AOI artifact state.")
      analysis$proposal$mask_path <- NULL
    }
    has_path <- function(x) {
      if (!is.list(x)) return(FALSE)
      any(names(x) %in% c("path", "source_path", "output_directory", "mask_path")) || any(vapply(x, has_path, logical(1)))
    }
    brohn_require(!has_path(analysis), "Worker output contains an unregistered filesystem path.")
    analysis
}
brohn_promote_worker_artifacts <- function(store, analysis, scratch, job, report = NULL) {
  # Compatibility entry point retains full checks and its historical transaction
  # semantics. Generic report jobs use the staged route in platform-jobs.R;
  # direct legacy callers must not claim the staged route's contention bound.
  if (any(vapply(brohn_default(analysis$artifacts, list()), function(a) identical(a$kind, "questionnaire-analysis"), logical(1)))) {
    brohn_require(is.list(report) && identical(brohn_hash(analysis), brohn_hash(report$analysis)) &&
      brohn_questionnaire_is_artifact(analysis), "Questionnaire promotion requires the complete frozen report context.")
    brohn_verify_questionnaire_worker_report(store, report, scratch)
  }
  brohn_store_batch(store, function() {
    brohn_renew_job(store, job$id, job$worker, job$token, 60)
    checked <- .brohn_check_worker_artifacts(store, analysis, scratch, verify_hashes = TRUE)
    # Validate the full manifest before copying any bytes into the object store.
    promoted <- lapply(checked, function(item) {
      object <- brohn_store_object(store, path = item$path,
        media_type = if (item$kind == "aoi-mask") "image/png" else if (item$kind == "facial-values") "text/csv" else "application/x-ndjson")
      brohn_require(identical(object$hash, item$hash) && identical(as.numeric(object$size), as.numeric(item$size)), "Artifact changed while publishing immutable bytes.")
      c(list(kind = item$kind), object, item$metadata)
    })
    analysis <- .brohn_worker_artifact_analysis(analysis, promoted)
    brohn_renew_job(store, job$id, job$worker, job$token, 60)
    analysis
  })
}

brohn_save_aoi_proposal_result <- function(store, report, job, project_id) {
  p <- report$analysis$proposal
  brohn_require(is.list(p) && p$status %in% c("needs_review", "no_proposal") && identical(p$accepted, FALSE), "Worker attempted to bypass researcher AOI review.")
  brohn_require(identical(p$source_hash, job$request$source_hash), "Proposal source does not match its frozen job.")
  id <- paste0("aoi-proposal-", sub("^job-", "", job$id))
  body <- list(schema_version = "brohn-aoi-proposal/1.0.0", id = id, status = p$status,
    study_id = job$request$study_id, study_revision = job$request$study_revision, study_hash = job$request$study_hash,
    stimulus_id = job$request$stimulus_id, source_hash = job$request$source_hash, prompt = job$request$prompt,
    proposal = p, engine = report$analysis$engine, parameters = report$analysis$parameters,
    limitations = report$analysis$limitations, report_id = report$id, job_id = job$id, created_at = brohn_now(), review = NULL)
  brohn_put_entity(store, "aoi_proposal", id, body, project_id = project_id)
  id
}

brohn_aoi_proposals <- function(store, study_id, limit = 500) {
  study <- brohn_study(store, study_id)
  brohn_list_entities(store, "aoi_proposal", study$project_id, limit, filters = list(study_id = study_id))
}

brohn_proposal_mask_path <- function(store, proposal_id) {
  record <- brohn_get_entity(store, "aoi_proposal", proposal_id)
  brohn_require(!is.null(record) && !is.null(record$body$proposal$mask_object), "This proposal has no preserved mask.")
  brohn_object_path(store, record$body$proposal$mask_object$hash)
}

brohn_review_aoi_proposal <- function(store, proposal_id, action, label = NULL,
                                       expected_revision, study_revision = NULL, rectangle = NULL, note = "") {
  brohn_require(action %in% c("accept_rectangle", "reject"), "Choose whether to accept an explicit rectangle or reject the proposal.")
  brohn_require(brohn_text(note, 4000, TRUE), "Keep the review note within 4,000 characters.")
  brohn_store_batch(store, function() {
    record <- brohn_get_entity(store, "aoi_proposal", proposal_id)
    brohn_require(!is.null(record) && record$revision == expected_revision && identical(record$body$status, "needs_review"), "This proposal changed or has already been reviewed.")
    body <- record$body
    review <- list(action = action, at = brohn_now(), note = note, accepted_shape = NULL, study_revision = NULL, aoi_id = NULL)
    if (identical(action, "accept_rectangle")) {
      brohn_require(brohn_text(label, 240), "Name the intended research region.")
      study <- brohn_study(store, body$study_id)
      brohn_require(!isTRUE(study$body$archived), "Restore this study before accepting an AOI.")
      brohn_project(store, study$project_id)
      brohn_require(!is.null(study_revision) && study$revision == study_revision, "The study changed. Reload it before accepting an AOI.")
      index <- match(body$stimulus_id, brohn_ids(study$body$stimuli))
      brohn_require(!is.na(index) && identical(study$body$stimuli[[index]]$asset$hash, body$source_hash), "The stimulus image changed. Generate a new proposal for the current image.")
      brohn_proposal_mask_path(store, proposal_id)
      if (is.null(rectangle)) rectangle <- body$proposal[c("x", "y", "width", "height")]
      brohn_require(is.list(rectangle) && identical(sort(names(rectangle)), sort(c("x", "y", "width", "height"))), "A reviewed rectangle needs x, y, width and height.")
      aoi <- c(list(id = brohn_id("aoi"), label = label), rectangle,
        list(source = paste0("researcher_reviewed_proposal_rectangle:", proposal_id), asset_hash = body$source_hash))
      stimulus <- study$body$stimuli[[index]]
      brohn_require(!label %in% vapply(stimulus$aois, `[[`, character(1), "label"), "Use a distinct AOI label within this stimulus.")
      stimulus$aois <- c(stimulus$aois, list(aoi)); study$body$stimuli[[index]] <- stimulus
      saved <- brohn_save_study(store, study$body, study$revision)
      body$status <- "accepted_rectangle"
      review$accepted_shape <- aoi; review$study_revision <- saved$revision; review$aoi_id <- aoi$id
    } else body$status <- "rejected"
    body$review <- review
    brohn_put_entity(store, "aoi_proposal", proposal_id, body, expected_revision, record$project_id)
  })
}
