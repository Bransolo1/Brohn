# Inactive assigned-study opening. A release link exposes only opening content;
# experimental resources require a separately admitted participant assignment.
.brohn_pven_snapshot <- function(store, release_token) {
  .brohn_pvds_require(.brohn_pvds_hash(release_token),
    "Use the original study link.", "unauthorized", 403L)
  .brohn_pvds_readonly(store, function() {
    m <- .brohn_pvds_release_meta(store, token = release_token)
    brohn_hosted_require_release(store, m$deployment_id, "entry")
    list(metadata = m, bodies = .brohn_pvds_release_bodies(store, m),
      workspace_paused = .brohn_store_execution_paused(store))
  })
}

.brohn_pven_current <- function(store, release_token, original) {
  .brohn_pvds_readonly(store, function() {
    current <- .brohn_pvds_release_meta(store, token = release_token)
    brohn_hosted_require_release(store, current$deployment_id, "entry")
    .brohn_pvds_release_equal(store, original, current)
    # These recruitment fields are deliberately excluded from immutable source
    # pins. The opening response must still describe their current values.
    fields <- c("status", "quota", "alias_required")
    .brohn_pvds_require(identical(current[fields], original$metadata[fields]) &&
      identical(.brohn_store_execution_paused(store), original$workspace_paused),
      "Study availability changed while this page was loading. Open the link again.", "state_changed")
    invisible(TRUE)
  })
}

.brohn_participant_view_entry_response <- function(store, release_token) {
  original <- .brohn_pven_snapshot(store, release_token)
  design <- .brohn_pvds_release_integrity(original, validate_design = TRUE)
  welcome <- NULL
  if (!is.null(design$welcome)) {
    w <- design$welcome
    # Do not publish the content hash, filename, private design, or asset registry.
    # The dedicated endpoint always selects this release's sole welcome image.
    welcome <- list(schema = "participant-welcome/0.1", title = w$title,
      text = w$text, image_alt = w$image_alt, image = if (is.null(w$asset)) NULL else
        list(url = paste0("/api/view/welcome/", release_token),
          media_type = w$asset$media_type, width = w$asset$width, height = w$asset$height))
  }
  m <- original$metadata
  value <- list(schema = "participant-view-entry/0.1", title = design$title,
    origin = m$origin, release_status = m$status, workspace_paused = original$workspace_paused,
    alias_required = as.logical(m$alias_required), consent = design$consent,
    appearance = design$appearance, welcome = welcome,
    renderer_identity = .brohn_pvds_renderer(m$registration))
  # Status is informational; first-start remains the authoritative quota,
  # enrolment and consent transaction. Opening a page reserves no participant.
  document <- brohn_participant_json_bytes(value, maximum_bytes = 4 * 1024^2)
  .brohn_pven_current(store, release_token, original)
  document
}

.brohn_participant_view_welcome_response <- function(store, release_token) {
  original <- .brohn_pven_snapshot(store, release_token)
  design <- .brohn_pvds_release_integrity(original, validate_design = TRUE)
  .brohn_pvds_require(!is.null(design$welcome$asset),
    "This study has no welcome image.", "not_found", 404L)
  asset <- design$welcome$asset
  # Original welcome validation requires PNG <=5 MiB, dimensions and alt text.
  # There is no caller-selected hash or assigned-resource key in this interface.
  brohn_validate_welcome(design$welcome)
  source <- brohn_object_path(store, asset$hash, verify = FALSE)
  .brohn_pvds_require(identical(as.numeric(file.info(source)$size), as.numeric(asset$size)),
    "The welcome image differs from its released size.", "resource_integrity")
  snapshot <- tempfile(pattern = "brohn-welcome-resource-")
  transferred <- FALSE
  on.exit(if (!transferred && file.exists(snapshot)) unlink(snapshot), add = TRUE)
  .brohn_pvres_snapshot(source, snapshot, asset$size)
  .brohn_pvds_require(identical(as.numeric(file.info(snapshot)$size), as.numeric(asset$size)) &&
    identical(digest::digest(file = snapshot, algo = "sha256"), asset$hash),
    "The welcome image could not be prepared intact.", "resource_integrity")
  .brohn_pven_current(store, release_token, original)
  response <- .brohn_delivery_response(body = list(file = snapshot, owned = TRUE), type = asset$media_type)
  response$headers[["Content-Length"]] <- sprintf("%.0f", asset$size)
  response$headers[["Accept-Ranges"]] <- "none"
  transferred <- TRUE
  response
}
