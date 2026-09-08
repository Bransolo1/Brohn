# Draft rectangles use normalized image coordinates with a top-left origin.
# Each region is bound to the exact PNG bytes, not just the stimulus slot.
aoi_fields <- function() {
  c("id", "stimulus_id", "label", "shape", "x", "y", "width", "height", "asset_sha256")
}

validate_study_aois <- function(study) {
  tryCatch({
    a <- record_assert
    a(is.list(study), "AOIs: study required")
    if (!"aois" %in% names(study)) return(character())
    a(record_array(study$aois), "AOIs: unnamed array required")
    ids <- character(); labels <- list()
    finite_scalar <- function(x) {
      is.numeric(x) && !is.complex(x) && length(x) == 1L && !is.na(x) && is.finite(x)
    }
    for (region in study$aois) {
      a(record_fields(region, aoi_fields()), "AOI: fields")
      a(scalar_text(region$id) && !region$id %in% ids, "AOI: unique nonempty ID required")
      ids <- c(ids, region$id)
      a(text_choice(region$stimulus_id, study$stimulus_ids), "AOI: unknown stimulus ID")
      a(scalar_text(region$label), "AOI: nonempty label required")
      label_key <- list(region$stimulus_id, trimws(region$label))
      a(!any(vapply(labels, identical, logical(1), label_key)),
        "AOI: duplicate label within stimulus")
      labels[[length(labels) + 1L]] <- label_key
      a(identical(region$shape, "rectangle"), "AOI: only rectangle is supported")
      a(all(vapply(region[c("x", "y", "width", "height")], finite_scalar, logical(1))),
        "AOI: finite numeric scalar coordinates required")
      a(region$x >= 0 && region$x <= 1 && region$y >= 0 && region$y <= 1 &&
          region$width > 0 && region$width <= 1 && region$height > 0 && region$height <= 1,
        "AOI: normalized coordinates and positive dimensions required")
      # Permit only floating-point addition noise at the right/bottom edge.
      tolerance <- 8 * .Machine$double.eps
      a(region$x + region$width <= 1 + tolerance &&
          region$y + region$height <= 1 + tolerance, "AOI: rectangle exceeds image bounds")
      a(record_array(study$stimulus_assets), "AOI: attach a PNG to the stimulus first")
      matching <- Filter(function(asset) is.list(asset) &&
        identical(asset$stimulus_id, region$stimulus_id), study$stimulus_assets)
      a(length(matching) == 1L, "AOI: attach a PNG to the stimulus first")
      a(scalar_text(region$asset_sha256) && grepl("^[0-9a-f]{64}$", region$asset_sha256) &&
          identical(matching[[1L]]$media_type, "image/png") &&
          identical(region$asset_sha256, matching[[1L]]$sha256),
        "AOI: image SHA-256 binding mismatch")
    }
    character()
  }, error = function(e) conditionMessage(e))
}

new_rectangle_aoi <- function(study, stimulus_id, label, x, y, width, height, id = NULL) {
  a <- record_assert
  errors <- validate_study_aois(study)
  a(!length(errors), paste(errors, collapse = "; "))
  a(text_choice(stimulus_id, study$stimulus_ids), "AOI: unknown stimulus ID")
  a(scalar_text(label), "AOI: nonempty label required")
  regions <- study$aois
  if (is.null(regions)) regions <- list()
  if (is.null(id)) {
    existing_ids <- vapply(regions, function(region) region$id, character(1))
    repeat {
      id <- paste0("aoi-", paste(sample(c(letters, 0:9), 16, replace = TRUE), collapse = ""))
      if (!id %in% existing_ids) break
    }
  }
  a(scalar_text(id), "AOI: nonempty ID required")
  a(record_array(study$stimulus_assets), "AOI: attach a PNG to the stimulus first")
  matching <- Filter(function(asset) is.list(asset) &&
    identical(asset$stimulus_id, stimulus_id), study$stimulus_assets)
  a(length(matching) == 1L, "AOI: attach a PNG to the stimulus first")
  region <- list(id = id, stimulus_id = stimulus_id, label = trimws(label),
                 shape = "rectangle", x = x, y = y, width = width, height = height,
                 asset_sha256 = matching[[1L]]$sha256)
  # An explicit existing ID proposes an edit while retaining its identity.
  study$aois <- c(Filter(function(old) !identical(old$id, id), regions), list(region))
  errors <- validate_study_aois(study)
  a(!length(errors), paste(errors, collapse = "; "))
  region
}

assert_aoi_draft_editable <- function(bundle) {
  record_assert(!length(validate_bundle(bundle)), "Open a valid draft first.")
  record_assert(!length(bundle$events) && !length(bundle$streams) && !length(bundle$clocks),
                "This bundle contains recording metadata. Create a new study to change regions.")
  record_assert(bundle$session$mode %in% c("sample", "preview"),
                "Only sample and preview drafts can be edited here.")
}

set_study_aoi <- function(bundle, aoi) {
  assert_aoi_draft_editable(bundle)
  record_assert(record_fields(aoi, aoi_fields()) && scalar_text(aoi$id), "AOI: fields/identity")
  regions <- bundle$study$aois
  if (is.null(regions)) regions <- list()
  index <- which(vapply(regions, function(region) identical(region$id, aoi$id), logical(1)))
  if (length(index) && isTRUE(all.equal(regions[[index]][aoi_fields()],
                                      aoi[aoi_fields()], tolerance = 0))) return(bundle)
  if (!length(index)) index <- length(regions) + 1L
  regions[[index]] <- aoi
  bundle$study$aois <- regions
  errors <- validate_study_aois(bundle$study)
  record_assert(!length(errors), paste(errors, collapse = "; "))
  bundle$study$revision <- bundle$study$revision + 1
  bundle$session$study_revision <- bundle$study$revision
  errors <- validate_bundle(bundle)
  record_assert(!length(errors), paste(errors, collapse = "; "))
  bundle
}

remove_study_aoi <- function(bundle, id) {
  assert_aoi_draft_editable(bundle)
  record_assert(scalar_text(id), "AOI: nonempty ID required")
  regions <- bundle$study$aois
  index <- which(vapply(regions, function(region) identical(region$id, id), logical(1)))
  if (!length(index)) return(bundle)
  bundle$study$aois <- regions[-index]
  bundle$study$revision <- bundle$study$revision + 1
  bundle$session$study_revision <- bundle$study$revision
  errors <- validate_bundle(bundle)
  record_assert(!length(errors), paste(errors, collapse = "; "))
  bundle
}
