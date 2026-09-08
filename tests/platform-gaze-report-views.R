for (module in c("platform-core", "platform-store", "platform-methods", "platform-library", "platform-analysis", "platform-gaze", "platform-shell", "platform-data-views", "platform-gaze-report-views"))
  source(paste0("R/", module, ".R"), encoding = "UTF-8")
local({
  checks <- 0L
  check <- function(name, value) {if (!isTRUE(value)) stop("Gaze report QA failed: ", name, call. = FALSE); checks <<- checks + 1L}
  rejects <- function(expr) inherits(try(force(expr), silent = TRUE), "try-error")
  root <- tempfile("brohn-gaze-view-"); store <- brohn_open_store(root)
  on.exit({brohn_close_store(store); unlink(root, recursive = TRUE)}, add = TRUE)
  brohn_initialise_library(store)
  d <- brohn_new_design("Original gaze visual fixture", id = "study-gaze-view")
  asset <- brohn_store_object(store, path = "examples/stimuli/sample-design-a.png", media_type = "image/png")
  asset$width <- 800; asset$height <- 600
  for (i in 1:2) {
    d$stimuli[[i]]$asset <- asset; d$stimuli[[i]]$type <- "image"
    d$stimuli[[i]]$aois <- list(list(id = "left", label = "Left <script>alert(1)</script>", x = 0, y = 0, width = .5, height = 1),
      list(id = "right", label = "Right", x = .5, y = 0, width = .5, height = 1),
      list(id = "unused", label = "Unvisited", x = .9, y = 0, width = .05, height = .1))
  }
  brohn_validate_design(d)
  m <- list(gaze_representation = "samples", unit = "stimulus_normalized", time_unit = "ms", time_column = "time", x_column = "x", y_column = "y", valid_column = "valid",
    participant_column = "participant", session_column = "session", stimulus_column = "stimulus", exposure_column = "exposure", condition_column = "condition",
    phase_column = "phase", phase_value = "view", exposure_start_column = "onset", exposure_end_column = "offset",
    geometry = list(width_mm = 400, height_mm = 300, distance_mm = 600, center_x_mm = 0, center_y_mm = 0),
    geometry_source = "Original synthetic 400 by 300 mm fixture, not a measured device geometry",
    parameters = list(velocity_threshold_deg_s = 30, min_fixation_ms = 60, min_saccade_ms = 10, max_gap_ms = 20,
      threshold_source = "Original synthetic fixture, not a device recommendation"))
  data <- data.frame(time = seq(0, 410, 10), x = c(rep(.25, 21), rep(.75, 21)), y = .5, valid = TRUE,
    participant = "person|one", session = "session-one", stimulus = "stimulus-a", exposure = "same-label", condition = "condition-a",
    phase = "view", onset = 0, offset = 410, stringsAsFactors = FALSE)
  source <- brohn_store_object(store, bytes = charToRaw(paste(capture.output(utils::write.csv(data, row.names = FALSE)), collapse = "\n")), media_type = "text/csv")
  report_for <- function(data, mapping = m, design = d, raw = TRUE) list(id = "report-gaze", title = "Original synthetic gaze report", created_at = "2026-09-08",
    origin = "sample", status = "usable", analysis = if (raw) brohn_raw_gaze_analysis(data, mapping, design) else brohn_gaze_analysis(data, mapping, design),
    provenance = list(design = design, design_hash = brohn_hash(design), study_revision = 1L, source = source, mapping = mapping))
  report <- report_for(data)
  record <- brohn_put_entity(store, "report", report$id, report, project_id = "default")
  saved <- brohn_get_entity(store, "report", report$id)$body; original_hash <- brohn_hash(saved)
  model <- brohn_gaze_report_model(saved); group <- model$groups[[1L]]; points <- brohn_gaze_report_points(group)
  check("actual saved analysis retains one exposure and both centroids", length(model$groups) == 1L && length(points) == 2L && points[[1L]]$x == .25 && points[[2L]]$x == .75)
  check("direct transition is tied to saved exact candidate bounds", length(brohn_gaze_report_links(group, points)) == 1L && brohn_gaze_report_links(group, points)[[1L]]$from_end_ms == 200)
  html <- as.character(brohn_gaze_report_ui(store, saved))
  check("saved image is embedded without filesystem or remote URLs", grepl("data:image/png;base64,", html, fixed = TRUE) && !grepl("file://|https?://(?!www.w3.org)", html, perl = TRUE))
  check("map uses saved rendered aspect and centroid scale", grepl('viewBox="0 0 1000 750.000"', html, fixed = TRUE) && grepl('cx="250.000" cy="375.000"', html, fixed = TRUE))
  check("user text is escaped in SVG and tables", !grepl("<script>", html, fixed = TRUE) && grepl("&lt;script&gt;", html, fixed = TRUE))
  check("map and bars have accessible roles and a numerical alternative", grepl('role="img"', html, fixed = TRUE) && grepl("Fixation candidate numerical alternative", html, fixed = TRUE) && grepl('scope="col"', html, fixed = TRUE))
  check("complete saved support and method limits are readable", grepl("410 ms", html, fixed = TRUE) && grepl("42", html, fixed = TRUE) && grepl('source phase "view"', html, fixed = TRUE) && grepl("have not been qualified", html, fixed = TRUE))
  check("saved TTFF missingness and censoring statuses survive", grepl("left_boundary_candidate_onset_unknown", html, fixed = TRUE) && grepl("right_censored_no_fixation_candidate", html, fixed = TRUE) && grepl("Unavailable", html, fixed = TRUE))
  check("visualization does not change report or saved metrics", identical(brohn_hash(saved), original_hash) && identical(group$observations, saved$analysis$observations) &&
    identical(brohn_hash(brohn_get_entity(store, "report", report$id)$body), original_hash))
  missing <- data; missing$valid[[11L]] <- FALSE; missing$x[[11L]] <- NA; missing$y[[11L]] <- NA
  gap <- data; gap$time[22:42] <- gap$time[22:42]+100; gap$offset <- 510
  phase <- data; phase$phase[[11L]] <- "response"
  for (case in list(missing, gap, phase)) {
    view <- brohn_gaze_report_model(report_for(case))$groups[[1L]]
    links <- brohn_gaze_report_links(view, brohn_gaze_report_points(view))
    # A later supported direct transition may remain; no link may bridge a mask.
    masks <- Filter(function(e) identical(e$record_type, "quality_mask"), view$events)
    check("missing/phase/gap support is never bridged", !any(vapply(links, function(link) any(vapply(masks, function(mask)
      mask$start_ms < link$to_start_ms && mask$end_ms > link$from_end_ms, logical(1))), logical(1))))
  }
  injected <- group; injected$events[[length(injected$events)+1L]] <- list(record_type = "quality_mask", reason = "sample_gap", start_ms = 202, end_ms = 208)
  check("conflicting saved exclusion mask suppresses transition link", length(brohn_gaze_report_links(injected, points)) == 0L)
  reverse <- group; reverse$fixations <- rev(reverse$fixations); altered <- saved
  indices <- which(vapply(altered$analysis$features, function(e) identical(e$record_type, "fixation_candidate"), logical(1)))
  altered$analysis$features[indices] <- rev(altered$analysis$features[indices])
  wrongorder <- brohn_gaze_report_model(altered)$groups[[1L]]
  check("unsorted candidates are not silently repaired", !wrongorder$ordered && length(brohn_gaze_report_points(wrongorder)) == 0L)
  malformed <- saved; malformed$analysis$features[[indices[[1L]]]]$x <- NULL
  check("missing coordinate disables candidate geometry", !brohn_gaze_report_model(malformed)$groups[[1L]]$ordered)
  off <- data; off$x <- -1
  outside <- brohn_gaze_report_model(report_for(off))$groups[[1L]]; offpoints <- brohn_gaze_report_points(outside)
  check("off-stimulus coordinates are never clamped or dropped from support", length(offpoints) == 1L && offpoints[[1L]]$x == -1 && !offpoints[[1L]]$in_frame && outside$summary$valid_interval_ms == 410)
  no_valid <- data; no_valid$valid <- FALSE; no_valid$x <- NA; no_valid$y <- NA
  absent <- report_for(no_valid); absent_html <- as.character(brohn_gaze_report_ui(store, absent))
  check("unavailable gaze share is not drawn as zero-percent bar", grepl("Unavailable", absent_html, fixed = TRUE) && !grepl('viewBox="0 0 500 18"', absent_html, fixed = TRUE))
  repeated <- rbind(data, transform(data, participant = "another-person"), transform(data, session = "another-session"), transform(data, stimulus = "stimulus-b", condition = "condition-b", exposure = "other-exposure"))
  many <- report_for(repeated); many_model <- brohn_gaze_report_model(many)
  check("same exposure labels across people sessions stimuli remain separate", length(many_model$groups) == 4L && length(unique(vapply(many_model$groups, `[[`, character(1), "selector"))) == 4L)
  one_html <- as.character(brohn_gaze_report_ui(store, many, exposure_key = many_model$groups[[2L]]$selector))
  check("selector renders one exact composite exposure", grepl("another-person", one_html, fixed = TRUE) && !grepl("Participant person|one", one_html, fixed = TRUE))
  stale <- as.character(brohn_gaze_report_ui(store, saved, exposure_key = many_model$groups[[1L]]$selector))
  check("stale selector cannot cross saved reports", grepl("Choose an exposure belonging to this exact saved report", stale, fixed = TRUE))
  limited <- as.character(brohn_gaze_report_ui(store, many, maximum_exposures = 1L, maximum_points = 1L))
  check("preview limits disclose total exposures and candidates", grepl("Showing 1 of 4", limited, fixed = TRUE) && grepl("Showing 1 of 2 saved fixation candidates", limited, fixed = TRUE))
  intervals <- data.frame(participant = "person-one", session = "session-one", stimulus = "stimulus-a", exposure = "prepared", condition = "condition-a",
    start = c(0, 200), end = c(200, 400), x = c(.25, .75), y = .5, valid = TRUE, phase = "view")
  prepared_mapping <- m; prepared_mapping$start_column <- "start"; prepared_mapping$end_column <- "end"
  prepared <- report_for(intervals, prepared_mapping, raw = FALSE)
  prepared_html <- as.character(brohn_gaze_report_ui(store, prepared))
  check("prepared summaries never create synthetic fixation maps or heatmaps", grepl("No fixation map or heatmap is inferred", prepared_html, fixed = TRUE) && !grepl("<circle", prepared_html, fixed = TRUE))
  broken <- saved; broken$provenance$design$stimuli[[1L]]$title <- "Later edit"
  check("changed pinned design rejects visualization", rejects(brohn_gaze_report_model(broken)))
  unmapped <- saved; unmapped$provenance$mapping$unit <- "display_normalized"
  check("display coordinates cannot masquerade as stimulus coordinates", rejects(brohn_gaze_report_model(unmapped)))
  no_phase <- saved; no_phase$provenance$mapping$phase_column <- NULL; no_phase$provenance$mapping$phase_value <- NULL
  check("missing passive phase evidence rejects visualization", rejects(brohn_gaze_report_model(no_phase)))
  old <- brohn_put_entity(store, "study", d$id, d, project_id = "default"); updated <- d; updated$stimuli[[1L]]$title <- "Current study changed"
  updated$stimuli[[1L]]["asset"] <- list(NULL); updated$stimuli[[1L]]$type <- "text"; updated$stimuli[[1L]]$content <- "New image is absent"
  brohn_save_study(store, updated, old$revision)
  check("later study revisions do not change pinned report geometry", identical(brohn_gaze_report_model(saved)$groups[[1L]]$stimulus$asset$hash, asset$hash) &&
    grepl("data:image/png;base64,", as.character(brohn_gaze_report_ui(store, saved)), fixed = TRUE))
  # Standalone document remains usable offline; no store path is copied into HTML.
  path <- file.path(root, "gaze-report.html")
  writeLines(paste0("<!doctype html><html lang='en'><head><meta charset='UTF-8'><title>Original gaze visual QA</title></head><body>", html, "</body></html>"), path)
  exported <- paste(readLines(path, warn = FALSE), collapse = "\n")
  check("offline export embeds exact pinned PNG and provenance", grepl(gsub("[\r\n]", "", jsonlite::base64_enc(readBin(brohn_object_path(store, asset$hash), "raw", n = asset$size))), exported, fixed = TRUE) &&
    grepl(asset$hash, exported, fixed = TRUE) && !grepl(store$root, exported, fixed = TRUE))
  shiny::testServer(function(input, output, session) {
    state <- shiny::reactiveValues(page = "report", report_id = report$id)
    brohn_install_gaze_report_server(input, output, session, store, state)
  }, {
    session$setInputs(gaze_report_exposure = model$groups[[1L]]$selector)
    check("real Shiny output renders immutable exposure selection", grepl("data:image/png;base64,", output$gaze_report_view$html, fixed = TRUE))
    session$setInputs(gaze_report_exposure = many_model$groups[[1L]]$selector)
    check("real Shiny rejects stale selection without leaking prior view", grepl("Choose an exposure belonging", output$gaze_report_view$html, fixed = TRUE))
  })
  # Integrity failure is explicit; it never loads the current study image instead.
  object_path <- brohn_object_path(store, asset$hash); Sys.chmod(object_path, "0666"); bytes <- readBin(object_path, "raw", n = asset$size)
  bytes[[length(bytes)]] <- as.raw(bitwXor(as.integer(bytes[[length(bytes)]]), 1L)); writeBin(bytes, object_path)
  corrupted <- as.character(brohn_gaze_report_ui(store, saved))
  check("corrupt source image is withheld while supported numeric results remain", grepl("SHA-256 integrity check", corrupted, fixed = TRUE) && !grepl("data:image/png;base64,", corrupted, fixed = TRUE) && grepl("410 ms", corrupted, fixed = TRUE))
  cat("PASS: ", checks, " gaze report assertions (saved geometry, support, identity isolation, offline images, exclusions and Shiny selection)\n", sep = "")
})
