# New researcher command for an explicitly saved design1.2. This never migrates
# or filters a design, and never accepts executable files from study data.
.brohn_assigned_publish_preflight <- function(store, design) {
  brohn_validate_variant_design(design, publish = TRUE)
  .brohn_delivery_require(!isTRUE(design$archived), "Restore this study before creating a release.", 409L, "archived")
  .brohn_delivery_require(!length(design$blocks) && !length(design$maxdiff),
    "This player does not yet support implicit-task or best-worst study screens. Keep the design and use its supported collection route.", 422L, "unsupported_method")
  .brohn_delivery_require(is.null(design$camera) && is.null(design$participant_equipment),
    "The assigned player cannot yet run the camera or equipment setup declared by this study.", 422L, "unsupported_equipment")
  .brohn_delivery_require(!length(design$methods),
    "Method-specific collection and automatic analysis must be connected before releasing this design.", 422L, "unsupported_method")
  # Declared live measurement must not become an unnoticed text/image-only run.
  # Imported multimodal analysis remains a separate preserved workflow.
  .brohn_delivery_require(all(unlist(design$measures, use.names = FALSE) %in% c("questionnaire")),
    "This study declares measurement streams that are not yet connected to this participant player.", 422L, "unsupported_measure")
  .brohn_delivery_require(all(vapply(design$stimuli, function(s) s$type %in% c("text", "image"), logical(1))),
    "Audio and video presentation need their joined media evidence path before release. Your original materials are retained.", 422L, "unsupported_stimulus")
  allowed_questions <- c("rating", "single_choice", "multiple_choice", "dropdown", "text", "long_text",
    "number", "slider", "matrix", "ranking", "allocation", "information")
  .brohn_delivery_require(all(vapply(design$questions, function(q) q$type %in% allowed_questions, logical(1))),
    "One or more question types do not yet have a connected participant screen.", 422L, "unsupported_question")
  .brohn_delivery_require(!length(design$questions) || !is.null(design$questionnaire_navigation),
    "Questionnaire delivery requires this study's explicit saved review and navigation policy.", 422L, "unsupported_questionnaire_navigation")
  # Check all declared assets, including versions not chosen by allocation1.
  materials <- design$stimuli
  if (!is.null(design$welcome$asset)) materials <- c(materials, list(list(type = "image", asset = design$welcome$asset)))
  if (brohn_has_illustrations(design)) {
    brohn_verify_study_illustrations(store, design)
    materials <- c(materials, brohn_study_illustrations(design))
  }
  for (material in materials) if (!is.null(material$asset)) {
    a <- material$asset
    .brohn_delivery_require(a$media_type %in% c("image/png", "image/jpeg", "image/webp", "image/gif"),
      "A declared image cannot be served by this participant player.", 422L, "unsafe_media")
    path <- brohn_object_path(store, a$hash, verify = TRUE)
    .brohn_delivery_require(identical(as.numeric(file.info(path)$size), as.numeric(a$size)),
      "A saved study image differs from its declared size.", 409L, "source_changed")
  }
  protocol <- brohn_compile_variant_design(design, 1L)
  .brohn_delivery_require(all(vapply(protocol$timeline, function(step)
    step$type %in% c("instructions", "baseline", "fixation", "stimulus", "question", "questionnaire_review"), logical(1))),
    "The compiled design includes a screen that is not yet connected to this player.", 422L, "unsupported_screen")
  .brohn_delivery_require(length(protocol$timeline) <= 20000L,
    "Compiled study exceeds the supported 20,000-screen delivery limit.", 422L, "study_limit")
  invisible(protocol)
}

brohn_assigned_release_issues <- function(store, design) {
  tryCatch({.brohn_assigned_runtime_installed(); .brohn_assigned_publish_preflight(store, design); character()},
    error = function(e) conditionMessage(e))
}

.brohn_assigned_publish_source <- function(store, study_id, expected_revision = NULL) {
  .brohn_pvds_ready(store)
  .brohn_delivery_require(!isTRUE(store$hosted_participant), "Only a researcher can publish a study.", 403L, "unauthorized")
  .brohn_delivery_require(brohn_valid_id(study_id), "Choose a saved study.")
  entity <- brohn_get_entity(store, "study", study_id)
  .brohn_delivery_require(!is.null(entity), "Study was not found.", 404L, "not_found")
  if (!is.null(expected_revision)) .brohn_delivery_require(brohn_number(expected_revision, 1, .Machine$integer.max, TRUE) &&
    entity$revision == expected_revision, "The study changed. Review its current saved revision before releasing it.", 409L, "revision_conflict")
  .brohn_delivery_require(identical(entity$body$id, study_id) && identical(entity$body$project_id, entity$project_id),
    "The study body differs from its saved owner.", 409L, "source_changed")
  brohn_project(store, entity$project_id)
  row <- DBI::dbGetQuery(store$con, paste("SELECT body_hash,CAST(body_json AS BLOB) AS body FROM entity_versions",
    "WHERE kind='study' AND id=? AND revision=? AND project_id=?"), params = list(study_id, entity$revision, entity$project_id))
  .brohn_delivery_require(nrow(row) == 1L && is.raw(row$body[[1L]]) &&
    identical(.brohn_runner_hash(row$body[[1L]]), row$body_hash[[1L]]),
    "The original saved study bytes are unavailable.", 409L, "source_changed")
  list(entity = entity, raw = row$body[[1L]], raw_hash = row$body_hash[[1L]])
}

brohn_publish_assigned_view <- function(store, study_id, origin = "pilot", quota = 100,
    alias_required = FALSE, expected_revision = NULL) {
  .brohn_delivery_require(brohn_text(origin, 16L) && origin %in% c("pilot", "live", "sample"), "Choose pilot, live or sample origin.")
  .brohn_delivery_require(brohn_number(quota, 1, 1000000, TRUE) && is.logical(alias_required) &&
    length(alias_required) == 1L && !is.na(alias_required), "Quota or alias policy is invalid.")
  .brohn_pvds_tables(store)
  installed <- .brohn_assigned_runtime_installed()
  original <- .brohn_pvds_readonly(store, function() .brohn_assigned_publish_source(store, study_id, expected_revision))
  .brohn_assigned_publish_preflight(store, original$entity$body)
  # The outer transaction includes the existing nested runtime publisher and
  # the new registration. A failed final registration rolls back the release,
  # credentials, runtime row and all audit rows. Content-addressed files already
  # materialized on disk may remain unreferenced; they cannot enroll anyone.
  .brohn_store_tx(store, function() {
    .brohn_delivery_require(!.brohn_store_execution_paused(store),
      "This restored workspace is paused. Resume it before creating a release.", 409L, "workspace_paused")
    current <- .brohn_assigned_publish_source(store, study_id, original$entity$revision)
    .brohn_delivery_require(identical(original$raw, current$raw) && identical(original$raw_hash, current$raw_hash) &&
      identical(original$entity$project_id, current$entity$project_id),
      "The saved design changed during release preparation. Review it and retry.", 409L, "source_changed")
    registration <- .brohn_pvds_registration()
    .brohn_delivery_require(identical(registration, installed$registration),
      "The participant player changed during preparation. Restart the matching service.", 503L, "renderer_unavailable")
    release <- brohn_runner_assets_publish(store, installed$prepared, function() {
      design <- current$entity$body; id <- brohn_id("release"); token <- brohn_token(); stamp <- brohn_now()
      DBI::dbExecute(store$con, paste("INSERT INTO delivery_deployments",
        "(id,study_id,project_id,title,origin,status,quota,alias_required,design_revision,design_json,design_hash,created_at,updated_at)",
        "VALUES (?,?,?,?,?,'open',?,?,?,?,?,?,?)"), params = list(id, study_id, current$entity$project_id, design$title,
        origin, as.integer(quota), as.integer(alias_required), current$entity$revision,
        .brohn_pvds_text(current$raw), brohn_hash(design), stamp, stamp))
      DBI::dbExecute(store$con, "INSERT INTO delivery_deployment_credentials VALUES (?,?,?)",
        params = list(id, token, .brohn_delivery_hash(token)))
      if (!is.null(store$hosted_profile)) brohn_hosted_register_release(store, id)
      .brohn_store_audit(store, "deployment.published", id,
        list(study_id = study_id, origin = origin, design_revision = current$entity$revision))
      list(id = id)
    })
    DBI::dbExecute(store$con, "INSERT INTO delivery_view_releases VALUES (?,?,?,?,?)",
      params = c(list(release$id), unname(registration), list(brohn_now())))
    .brohn_store_audit(store, "deployment.assigned_view_registered", release$id, registration)
    .brohn_delivery_deployment(store, .brohn_delivery_deployment_row(store, id = release$id), TRUE)
  })
}

# One researcher action; route selection follows the original saved schema.
# No participant or portable-design field supplies a runtime path or code.
brohn_release_study <- function(store, study_id, origin = "pilot", quota = 100,
    alias_required = FALSE, expected_revision = NULL) {
  source <- .brohn_assigned_publish_source(store, study_id, expected_revision)
  if (identical(source$entity$body$schema_version, "brohn-design/1.2.0"))
    return(brohn_publish_assigned_view(store, study_id, origin, quota, alias_required, source$entity$revision))
  .brohn_delivery_require(identical(source$entity$body$schema_version, "brohn-design/1.0.0"),
    "This saved study version needs its matching participant publisher.", 422L, "unsupported_design")
  .brohn_store_tx(store, function() {
    current <- .brohn_assigned_publish_source(store, study_id, source$entity$revision)
    .brohn_delivery_require(identical(source$raw, current$raw), "The study changed during preparation.", 409L, "source_changed")
    brohn_publish(store, study_id, origin, quota, alias_required)
  })
}
