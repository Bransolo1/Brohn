# Guided authoring operates only on empty drafts; recorded evidence is read-only.
draft_title <- function(x) {
  if (scalar_text(x$study$title)) x$study$title else x$study$id
}

create_draft <- function(mode = "preview") {
  record_assert(text_choice(mode, c("sample", "preview")), "Choose sample or preview for a draft.")
  id <- paste0("study-", format(Sys.time(), "%Y%m%d-%H%M%S"), "-",
               paste(sample(c(letters, 0:9), 8, replace = TRUE), collapse = ""))
  study <- new_study(id, title = if (mode == "sample") "Design comparison \u00b7 sample" else "Untitled study")
  if (mode == "sample") {
    paths <- file.path("examples", "stimuli", c("sample-design-a.png", "sample-design-b.png"))
    if (all(file.exists(paths))) {
      study$stimulus_assets <- lapply(1:2, function(i) new_png_asset(paths[[i]], study$stimulus_ids[[i]]))
      study$aois <- lapply(1:2, function(i) new_rectangle_aoi(study, study$stimulus_ids[[i]],
        "Brand mark", 343 / 800, c(238, 208)[[i]] / 600, 114 / 800, 114 / 600,
        id = paste0("sample-brand-mark-", c("a", "b")[[i]])))
    }
  }
  run <- new_session(study, paste0(id, "-draft"), "not-enrolled", mode)
  new_bundle(study, run)
}

revise_draft <- function(x, title, include_liking, prompt = "How much do you like this design?") {
  record_assert(!length(validate_bundle(x)), "Open a valid draft first.")
  record_assert(!length(x$events) && !length(x$streams) && !length(x$clocks),
                "This bundle contains recording metadata. Open it read-only; create a new study to change the design.")
  record_assert(x$session$mode %in% c("sample", "preview"), "Only sample and preview drafts can be edited here.")
  defaults <- new_study(x$study$id, include_liking, title = trimws(title))
  record_assert(scalar_text(title), "Give the study a name before saving.")
  proposed <- x$study
  proposed$title <- trimws(title)
  proposed$measures <- if (include_liking) unique(c(x$study$measures, "questionnaire")) else setdiff(x$study$measures, "questionnaire")
  proposed$questions <- if (include_liking) defaults$questions else list()
  if (include_liking) {
    record_assert(scalar_text(prompt), "Write a question before saving.")
    proposed$questions[[1]]$prompt <- trimws(prompt)
    if (length(x$study$questions)) {
      old <- x$study$questions[[1]]
      proposed$questions[[1]] <- old
      proposed$questions[[1]]$prompt <- trimws(prompt)
      proposed$questions[[1]]$revision <- old$revision + as.integer(!identical(old$prompt, trimws(prompt)))
    } else {
      # Re-adding an item receives a new ID, so removed question revisions cannot collide.
      proposed$questions[[1]]$id <- paste0("q-liking-r", x$study$revision + 1)
    }
  }
  proposed$revision <- x$study$revision
  if (isTRUE(all.equal(proposed, x$study))) return(x)
  proposed$revision <- x$study$revision + 1
  x$study <- proposed
  x$session$study_revision <- proposed$revision
  record_assert(!length(validate_bundle(x)), "The revised draft is invalid.")
  x
}

list_drafts <- function(directory) {
  paths <- if (dir.exists(directory)) list.files(directory, pattern = "\\.json$", full.names = TRUE) else character()
  if (length(paths)) paths <- normalizePath(paths, winslash = "/", mustWork = TRUE)
  lapply(paths, function(path) tryCatch({
    x <- read_bundle(path)
    list(path = path, title = draft_title(x), mode = x$session$mode, valid = TRUE)
  }, error = function(e) list(path = path, title = basename(path), mode = "unreadable", valid = FALSE)))
}
