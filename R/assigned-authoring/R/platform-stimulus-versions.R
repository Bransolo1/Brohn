# Draft authoring only. Every participant still sees every saved stimulus once.
# A copied material receives its own identity; this is not a variant allocator.
brohn_add_stimulus_version <- function(design, stimulus_id, title,
                                      condition_id = NULL, new_condition_role = "test") {
  brohn_validate_design(design)
  brohn_require(!isTRUE(design$archived), "Restore this study before adding a stimulus version.")
  source <- brohn_find(design$stimuli, stimulus_id)
  brohn_require(!is.null(source), "Choose a current stimulus to create another version.")
  brohn_require(brohn_text(title, 240), "Give this stimulus version a name.")
  brohn_require(length(design$stimuli) < 500L, "This study already has the supported maximum of 500 stimuli.")
  if (is.null(condition_id)) {
    brohn_require(length(design$conditions) < 100L, "This study already has 100 conditions. Choose an existing condition or revise the design.")
    brohn_require(is.character(new_condition_role) && length(new_condition_role) == 1L &&
      !is.na(new_condition_role) && new_condition_role %in% c("control", "test", "neutral", "other"),
      "Choose a role for the new condition.")
    condition_id <- brohn_id("condition")
    design$conditions <- c(design$conditions, list(list(id = condition_id, label = title, role = new_condition_role)))
  } else {
    brohn_require(brohn_valid_id(condition_id) && condition_id %in% brohn_ids(design$conditions),
      "Choose an existing condition in this study.")
  }
  version <- source
  version$id <- brohn_id("stimulus")
  version$title <- title
  version$condition_id <- condition_id
  # Coordinates/source annotations stay bound to the identical original asset.
  # Replacement uses the existing material editor and its AOI invalidation rules.
  version$aois <- lapply(source$aois, function(area) {area$id <- brohn_id("aoi"); area})
  design$stimuli <- c(design$stimuli, list(version))
  brohn_validate_design(design)
  design
}

brohn_stimulus_version_name <- function(stimulus, stimuli) {
  # At most 48 Unicode characters leaves room under the 240-byte title bound.
  stem <- substr(enc2utf8(stimulus$title), 1L, 48L)
  existing <- vapply(stimuli, function(x) x$title, character(1))
  index <- 2L
  repeat {
    title <- paste0(stem, " \u2014 version ", index)
    if (!title %in% existing) return(title)
    index <- index + 1L
  }
}
