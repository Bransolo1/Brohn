# Read-only views of immutable gaze outputs. No detector or score runs here.
.brohn_gaze_view_number <- function(x, unit = "") {
  if (!is.numeric(x) || length(x) != 1L || !is.finite(x)) return("Unavailable")
  paste0(format(signif(x, 6), trim = TRUE, scientific = FALSE), if (nzchar(unit)) paste0(" ", unit) else "")
}
.brohn_gaze_view_key <- function(row) brohn_hash(lapply(c("participant_id", "session_id", "stimulus_id", "exposure_id"), function(k) row[[k]]))
.brohn_gaze_view_finite <- function(x) is.numeric(x) && length(x) == 1L && is.finite(x)

brohn_gaze_report_model <- function(report) {
  a <- report$analysis
  brohn_require(identical(a$kind, "gaze"), "This saved report does not contain gaze analysis.")
  raw <- identical(a$parameters$input, "raw_gaze_samples") && identical(a$parameters$method, "brohn-adjacent-ray-ivt/0.1.0-draft")
  prepared <- identical(a$parameters$input, "prepared_gaze_intervals") && identical(a$parameters$method, "aoi-valid-gaze-time-share/0.1.0-draft")
  brohn_require(raw || prepared, "This gaze recipe has no declared visual-report adapter. Its saved tables remain available.")
  p <- report$provenance; design <- p$design
  brohn_require(is.list(design) && identical(brohn_hash(design), p$design_hash), "The report's pinned study design failed its integrity check.")
  brohn_validate_design(design)
  brohn_require(identical(a$parameters$coordinate_space, "stimulus_normalized") && identical(p$mapping$unit, "stimulus_normalized"),
    "The saved coordinate mapping does not establish the rendered stimulus rectangle.")
  phase <- if (brohn_text(p$mapping$phase_column, 500) && brohn_text(p$mapping$phase_value, 500))
    paste("Only source phase", brohn_json(p$mapping$phase_value), "in column", brohn_json(p$mapping$phase_column), "is eligible.") else
    if (identical(p$mapping$source_phase, "passive_viewing_only")) "The source was explicitly declared passive viewing only." else NULL
  brohn_require(!is.null(phase), "The report does not retain a passive-viewing phase declaration.")
  observations <- brohn_default(a$observations, list()); features <- brohn_default(a$features, list())
  brohn_require(length(observations) <= 100000L && length(features) <= 100000L, "This report exceeds the bounded gaze-view record limit.")
  rows <- c(observations, features)
  for (row in rows) {
    brohn_require(all(vapply(c("participant_id", "session_id", "stimulus_id", "exposure_id"), function(k) brohn_text(row[[k]], 500), logical(1))),
      "A gaze record is missing its participant, session, stimulus or exposure identity.")
    stimulus <- brohn_find(design$stimuli, row$stimulus_id)
    brohn_require(!is.null(stimulus) && identical(row$condition_id, stimulus$condition_id), "A saved gaze record disagrees with its pinned stimulus condition.")
  }
  keys <- unique(vapply(rows, .brohn_gaze_view_key, character(1)))
  brohn_require(length(keys) <= 10000L, "This report exceeds 10,000 exposure views. Use its complete numerical export.")
  observation_keys <- vapply(observations, .brohn_gaze_view_key, character(1)); feature_keys <- vapply(features, .brohn_gaze_view_key, character(1))
  report_hash <- brohn_hash(report)
  groups <- lapply(keys, function(key) {
    obs <- observations[observation_keys == key]; events <- features[feature_keys == key]; identity <- c(obs, events)[[1L]]
    stimulus <- brohn_find(design$stimuli, identity$stimulus_id)
    brohn_require(!anyDuplicated(vapply(obs, function(o) o$aoi_id, character(1))), "An exposure contains duplicate AOI summaries.")
    for (row in obs) {
      brohn_require(row$aoi_id %in% brohn_ids(stimulus$aois), "An AOI summary has no matching pinned region.")
      for (field in c("valid_ms", "inside_ms", "fixation_dwell_ms", "valid_share_percent"))
        brohn_require(is.null(row[[field]]) || .brohn_gaze_view_finite(row[[field]]) && row[[field]] >= 0,
          "A saved AOI measure is outside its declared numerical range.")
      brohn_require(is.null(row$valid_share_percent) || row$valid_share_percent <= 100, "A saved single-AOI time share exceeds 100 percent.")
    }
    summaries <- Filter(function(e) identical(e$record_type, "exposure_summary"), events)
    brohn_require(length(summaries) <= 1L, "An exposure contains duplicate support summaries.")
    fixations <- Filter(function(e) identical(e$record_type, "fixation_candidate"), events)
    eligible <- vapply(fixations, function(e) all(vapply(e[c("x", "y", "start_ms", "end_ms", "duration_ms")], .brohn_gaze_view_finite, logical(1))) &&
      length(e[c("x", "y", "start_ms", "end_ms", "duration_ms")]) == 5L && e$end_ms > e$start_ms && e$duration_ms > 0 && identical(e$qualified, FALSE), logical(1))
    ordered <- !length(fixations) || all(eligible) && (length(fixations) == 1L || all(vapply(fixations[-1L], `[[`, numeric(1), "start_ms") >=
      vapply(fixations[-length(fixations)], `[[`, numeric(1), "end_ms")))
    list(key = key, selector = paste(report_hash, key, sep = ":"), identity = identity[c("participant_id", "session_id", "stimulus_id", "exposure_id", "condition_id")],
      stimulus = stimulus, observations = obs, events = events, summary = if (length(summaries)) summaries[[1L]] else NULL,
      fixations = fixations, ordered = ordered,
      label = paste(stimulus$title, "| participant", identity$participant_id, "| session", identity$session_id, "| exposure", identity$exposure_id))
  })
  list(report_hash = report_hash, source_hash = p$source$hash, design_hash = p$design_hash, design_revision = p$study_revision,
    raw = raw, groups = groups, phase = phase, mapping = p$mapping, parameters = a$parameters, quality = a$quality, origin = report$origin)
}

.brohn_gaze_view_image <- function(store, stimulus, budget) {
  asset <- stimulus$asset
  if (is.null(asset)) return(list(uri = NULL, reason = "No pinned raster image is available. The diagram shows the normalized stimulus frame; text layout is not reconstructed."))
  if (is.null(store)) return(list(uri = NULL, reason = "Open this report in its original workspace to access the pinned stimulus image."))
  tryCatch({
    brohn_require(asset$media_type %in% c("image/png", "image/jpeg"), "This stimulus is not a supported static PNG or JPEG image.")
    brohn_require(.brohn_gaze_view_finite(asset$size) && asset$size > 0 && asset$size <= 5*1024^2 && budget$bytes + asset$size <= 16*1024^2,
      "The image exceeds this view's inline-media budget; its pinned source remains retained.")
    path <- brohn_object_path(store, asset$hash)
    prefix <- readBin(path, "raw", n = 8L)
    png <- identical(prefix, as.raw(c(137, 80, 78, 71, 13, 10, 26, 10)))
    jpg <- length(prefix) >= 3L && identical(prefix[1:3], as.raw(c(255, 216, 255)))
    brohn_require((asset$media_type == "image/png" && png) || (asset$media_type == "image/jpeg" && jpg), "Pinned image bytes disagree with their declared raster type.")
    uri <- brohn_asset_data_uri(store, asset); budget$bytes <- budget$bytes + asset$size
    list(uri = uri, reason = NULL)
  }, error = function(e) list(uri = NULL, reason = paste("Pinned image unavailable:", conditionMessage(e))))
}

# Only a persisted, direct AOI transition may join two consecutive candidates.
# The dashed line encodes this event; it is not the sampled eye trajectory.
brohn_gaze_report_links <- function(group, displayed) {
  if (!group$ordered || length(displayed) < 2L) return(list())
  events <- Filter(function(e) identical(e$record_type, "aoi_transition"), group$events)
  masks <- Filter(function(e) identical(e$record_type, "quality_mask") && e$reason %in% c("invalid_gaze", "sample_gap", "phase_boundary"), group$events)
  links <- list()
  for (i in seq_len(length(displayed)-1L)) {
    a <- displayed[[i]]; b <- displayed[[i+1L]]
    if (b$number != a$number+1L || !a$in_frame || !b$in_frame || length(a$aoi_ids) != 1L || length(b$aoi_ids) != 1L) next
    match <- Filter(function(e) identical(e$from_aoi, a$aoi_ids[[1L]]) && identical(e$to_aoi, b$aoi_ids[[1L]]) &&
      identical(e$from_end_ms, a$end_ms) && identical(e$to_start_ms, b$start_ms), events)
    blocked <- any(vapply(masks, function(m) .brohn_gaze_view_finite(m$start_ms) && .brohn_gaze_view_finite(m$end_ms) &&
      m$start_ms < b$start_ms && m$end_ms > a$end_ms, logical(1)))
    if (length(match) == 1L && !blocked) links[[length(links)+1L]] <- list(from = a$number, to = b$number,
      x1 = a$x, y1 = a$y, x2 = b$x, y2 = b$y, from_end_ms = a$end_ms, to_start_ms = b$start_ms)
  }
  links
}

brohn_gaze_report_points <- function(group, maximum = 200L) {
  brohn_require(brohn_number(maximum, 1, 1000, TRUE), "Choose a gaze-point display limit from 1 to 1,000.")
  if (!group$ordered) return(list())
  lapply(seq_len(min(length(group$fixations), maximum)), function(i) {
    point <- group$fixations[[i]]; point$number <- i
    point$in_frame <- point$x >= 0 && point$x <= 1 && point$y >= 0 && point$y <= 1
    point
  })
}

brohn_gaze_report_svg <- function(group, model, image, points) {
  width <- 1000; geometry <- model$parameters$geometry
  ratio <- if (model$raw && .brohn_gaze_view_finite(geometry$width_mm) && .brohn_gaze_view_finite(geometry$height_mm)) geometry$height_mm/geometry$width_mm else
    if (.brohn_gaze_view_finite(group$stimulus$asset$width) && .brohn_gaze_view_finite(group$stimulus$asset$height)) group$stimulus$asset$height/group$stimulus$asset$width else 1
  brohn_require(is.finite(ratio) && ratio >= .05 && ratio <= 20, "This stimulus aspect ratio is outside the bounded diagram profile.")
  height <- width*ratio; n <- function(x) formatC(x, format = "f", digits = 3, decimal.mark = ".")
  in_frame <- Filter(function(p) isTRUE(p$in_frame), points); links <- brohn_gaze_report_links(group, points)
  title <- paste(if (model$raw) "Pinned stimulus and numbered fixation candidates:" else "Pinned stimulus and region definitions:", group$label)
  description <- paste("Top-left is x=0, y=0; bottom-right is x=1, y=1.",
    if (model$raw) paste(length(in_frame), "candidate locations shown. Equal-size numbered markers show order, not duration. Dashed links show only saved direct AOI transitions, not the eye's trajectory.") else
      "This saved prepared-interval report does not retain fixation coordinates. Region outlines do not imply observed gaze locations.",
    "The following tables provide the numerical alternative.")
  scale <- max(.6, min(1.8, sqrt(ratio)))
  svg <- shiny::tags$svg(xmlns = "http://www.w3.org/2000/svg", viewBox = paste(0, 0, width, n(height)), width = "100%",
    style = "display:block;width:100%;height:auto;max-height:75vh;border:1px solid #65767e;border-radius:8px;background:#edf2f2",
    role = "img", `aria-label` = title,
    shiny::tags$title(title), shiny::tags$desc(description),
    shiny::tags$rect(x = 0, y = 0, width = width, height = n(height), fill = "#edf2f2"),
    if (!is.null(image$uri)) shiny::tags$image(href = image$uri, x = 0, y = 0, width = width, height = n(height), preserveAspectRatio = "none"),
    lapply(seq_along(group$stimulus$aois), function(i) {
      a <- group$stimulus$aois[[i]]; x <- a$x*width; y <- a$y*height
      shiny::tagList(shiny::tags$rect(x = n(x), y = n(y), width = n(a$width*width), height = n(a$height*height), fill = "none", stroke = "#11171c", `stroke-width` = 5, `vector-effect` = "non-scaling-stroke"),
        shiny::tags$rect(x = n(x), y = n(y), width = n(a$width*width), height = n(a$height*height), fill = "none", stroke = "#fff", `stroke-width` = 2, `vector-effect` = "non-scaling-stroke"),
        shiny::tags$text(x = n(x+8), y = n(y+27*scale), fill = "#fff", stroke = "#11171c", `stroke-width` = 4*scale, `paint-order` = "stroke", `font-size` = 22*scale, `font-family` = "system-ui,sans-serif", paste("AOI", i), shiny::tags$title(a$label)))
    }),
    lapply(links, function(link) shiny::tags$line(x1 = n(link$x1*width), y1 = n(link$y1*height), x2 = n(link$x2*width), y2 = n(link$y2*height),
      stroke = "#11171c", `stroke-width` = 3, `stroke-dasharray` = "8 6", `vector-effect` = "non-scaling-stroke",
      shiny::tags$title(paste("Saved direct AOI transition from candidate", link$from, "to", link$to)))),
    lapply(in_frame, function(p) shiny::tags$g(
      shiny::tags$circle(cx = n(p$x*width), cy = n(p$y*height), r = 16*scale, fill = "#11171c", stroke = "#fff", `stroke-width` = 2*scale),
      shiny::tags$text(x = n(p$x*width), y = n(p$y*height+5*scale), `text-anchor` = "middle", fill = "#fff", `font-size` = 15*scale, `font-weight` = 700,
        `font-family` = "system-ui,sans-serif", p$number),
      shiny::tags$title(paste("Candidate", p$number, "x", .brohn_gaze_view_number(p$x), "y", .brohn_gaze_view_number(p$y),
        "duration", .brohn_gaze_view_number(p$duration_ms, "ms"))))))
  shiny::tags$figure(style = "margin:0;min-width:0", svg, shiny::tags$figcaption(shiny::p(description),
    shiny::p(if (model$raw) "Image proportions follow the saved rendered-stimulus geometry. No screen-to-stimulus transform, crop or head-motion correction is inferred." else
      "The pinned raster is shown at its recorded image aspect ratio. Participant screen placement is not reconstructed."),
    if (!is.null(image$reason)) shiny::p(class = "brohn-muted", image$reason)))
}

.brohn_gaze_share_bar <- function(row) {
  value <- row$valid_share_percent
  label <- paste(row$aoi_label, ":", .brohn_gaze_view_number(value, "% of valid gaze time"))
  shiny::div(style = "margin:12px 0", shiny::strong(label),
    if (!is.null(value)) shiny::tags$svg(viewBox = "0 0 500 18", width = "100%", style = "display:block;height:18px;margin-top:6px", role = "img", `aria-label` = label,
      shiny::tags$title(label), shiny::tags$rect(x = 0, y = 0, width = 500, height = 18, fill = "#3b4a52"),
      shiny::tags$rect(x = 0, y = 0, width = formatC(value*5, format = "f", digits = 3, decimal.mark = "."), height = 18, fill = "#97d8c4")))
}

.brohn_gaze_group_ui <- function(store, model, group, budget, maximum_points = 200L) {
  image <- .brohn_gaze_view_image(store, group$stimulus, budget)
  points <- brohn_gaze_report_points(group, maximum_points)
  summary <- group$summary; observations <- group$observations
  support <- if (!is.null(summary)) summary else if (length(observations)) observations[[1L]] else list()
  valid <- if (model$raw) support$valid_interval_ms else support$valid_ms
  missing <- if (model$raw) support$unobserved_interval_ms else support$unobserved_ms
  denominator <- if (length(observations)) unique(vapply(observations, function(o) brohn_default(o$denominator, "Unavailable"), character(1))) else "Valid adjacent-sample interval time; off-stimulus gaze retained."
  aoi_rows <- lapply(seq_along(group$stimulus$aois), function(i) c(list(region = paste("AOI", i)), group$stimulus$aois[[i]]))
  candidate_rows <- lapply(points, function(p) c(list(number = p$number, location = if (p$in_frame) "Within stimulus frame" else "Off stimulus; not plotted"),
    p[c("x", "y", "start_ms", "end_ms", "duration_ms", "sample_count", "source_first_row", "source_last_row", "aoi_ids", "boundary_truncated")]))
  shiny::tagList(shiny::h3(group$stimulus$title), shiny::p(paste("Participant", group$identity$participant_id, "\u00b7 session", group$identity$session_id,
    "\u00b7 exposure", group$identity$exposure_id, "\u00b7 condition", group$identity$condition_id)),
    shiny::p(paste("Valid gaze support:", .brohn_gaze_view_number(valid, "ms"), "\u00b7 unsupported time:", .brohn_gaze_view_number(missing, "ms"))),
    shiny::p(if (model$raw) paste("Source samples in this exposure:", .brohn_gaze_view_number(summary$sample_count), "\u00b7 passive samples:",
      .brohn_gaze_view_number(summary$passive_sample_count), "\u00b7 invalid passive samples:", .brohn_gaze_view_number(summary$invalid_passive_sample_count)) else
      "This prepared-interval report retains AOI summaries. Per-exposure sample counts and fixation coordinates were not saved."),
    shiny::p(model$phase), shiny::p(paste("Denominator:", paste(denominator, collapse = "; "))),
    shiny::p(if (isTRUE(support$complete_observation)) "Saved support covers the declared exposure. A left-boundary candidate still has unknown fixation onset." else
      "Full exposure coverage is not established. Missing observation is not treated as zero gaze or zero latency."),
    if (model$raw && !group$ordered) shiny::div(class = "brohn-alert", role = "status", "Candidate coordinates or their saved order are unavailable/inconsistent. No fixation locations or transition links are drawn."),
    brohn_gaze_report_svg(group, model, image, points),
    if (model$raw) shiny::p(paste("Showing", length(points), "of", length(group$fixations), "saved fixation candidates;",
      sum(vapply(points, function(p) !p$in_frame, logical(1))), "of the displayed candidates are off stimulus and remain in the numerical table."
    )) else shiny::p("No fixation map or heatmap is inferred from AOI summaries. The image shows only the pinned region definitions."),
    if (length(group$fixations) > length(points)) shiny::p(class = "brohn-muted", "The diagram and candidate table are a bounded preview. All candidates remain in the full report JSON; AOI measures below use their complete saved support."),
    shiny::tags$details(shiny::tags$summary("Region coordinates and labels"), brohn_table(aoi_rows, c("region", "label", "x", "y", "width", "height"), maximum = 200L, label = "Pinned AOI geometry")),
    if (length(candidate_rows)) shiny::tags$details(shiny::tags$summary("Candidate locations, times and source rows"),
      brohn_table(candidate_rows, maximum = maximum_points, label = "Fixation candidate numerical alternative")),
    shiny::h3("AOI gaze time"), shiny::p(paste("Each bar uses the same 0 to 100% scale. Regions are evaluated independently; overlapping regions can sum above 100%.",
      if (model$raw) "Crossing and off-stimulus intervals remain in valid time without being assigned to a region." else
        "Prepared interval locations define region membership. Off-stimulus observations remain in valid time.")),
    if (length(observations)) shiny::tagList(lapply(observations, .brohn_gaze_share_bar),
      brohn_table(observations, columns = c("aoi_label", "valid_ms", "inside_ms", "valid_share_percent", if (model$raw)
        c("crossing_interval_ms", "fixation_candidate_count", "fixation_dwell_ms", "mean_fixation_duration_ms", "ttff_ms", "ttff_status", "censor_time_ms") else c("first_observed_aoi_contact_ms", "first_contact_status")),
        maximum = 200L, label = "Saved AOI time measures and denominator")) else shiny::p("This exposure has no saved AOI summaries."),
    if (model$raw) shiny::p("Fixation dwell is the saved sum of candidate durations; it is distinct from endpoint-assigned gaze time. TTFF and censoring statuses are preserved, including unavailable values. These candidates have not been qualified against device or annotated ground truth."),
    shiny::tags$details(shiny::tags$summary("Exposure support and source versions"),
      brohn_table(list(support), maximum = 1L, label = "Complete saved exposure support"),
      shiny::p(paste("Report SHA-256:", model$report_hash)), shiny::p(paste("Source SHA-256:", model$source_hash)),
      shiny::p(paste("Design SHA-256:", model$design_hash, "\u00b7 revision", model$design_revision)),
      if (!is.null(group$stimulus$asset)) shiny::p(paste("Stimulus image SHA-256:", group$stimulus$asset$hash)),
      shiny::p("Coordinates refer to the actual rendered stimulus rectangle. Display-normalized or cropped source coordinates require a separately verified transform before analysis.")))
}

brohn_gaze_report_ui <- function(store, report, exposure_key = NULL, maximum_exposures = 12L, maximum_points = 200L) {
  if (!identical(report$analysis$kind, "gaze")) return(NULL)
  tryCatch({
    brohn_require(brohn_number(maximum_exposures, 1, 100, TRUE), "Choose a gaze exposure preview limit from 1 to 100.")
    model <- brohn_gaze_report_model(report); groups <- model$groups
    if (!is.null(exposure_key)) {
      groups <- Filter(function(g) identical(g$selector, exposure_key), groups)
      brohn_require(length(groups) == 1L, "Choose an exposure belonging to this exact saved report.")
    }
    count <- length(groups); groups <- head(groups, maximum_exposures)
    budget <- new.env(parent = emptyenv()); budget$bytes <- 0
    brohn_card(title = "Gaze in context", subtitle = "Saved positions and regions on the exact pinned stimulus. Each exposure remains separate.",
      shiny::p(paste("Recording origin:", model$origin, "\u00b7", length(model$groups), "participant/session/stimulus/exposure combinations in this report.")),
      if (!length(groups)) shiny::p("No exposure-level gaze records were retained in this report."),
      lapply(groups, function(group) shiny::tags$section(style = "min-width:0;margin-top:24px", .brohn_gaze_group_ui(store, model, group, budget, maximum_points))),
      if (count > length(groups)) shiny::p(class = "brohn-muted", paste("Showing", length(groups), "of", count,
        "exposures in this static report. Use the workspace exposure selector for every saved exposure; JSON contains the complete observations.")))
  }, error = function(e) brohn_card(title = "Gaze view needs attention", shiny::p(conditionMessage(e)),
    shiny::p("The immutable numerical report is retained. This view does not substitute different imagery, recalculate scores or repair missing coordinates.")))
}

brohn_gaze_explorer_ui <- function(report) {
  if (!identical(report$analysis$kind, "gaze")) return(NULL)
  tryCatch({
    model <- brohn_gaze_report_model(report)
    if (!length(model$groups)) return(brohn_card(title = "Gaze exposures", shiny::p("No exposure-level records were saved.")))
    choices <- stats::setNames(vapply(model$groups, `[[`, character(1), "selector"), vapply(model$groups, `[[`, character(1), "label"))
    shiny::tagList(brohn_card(title = "Explore gaze by exposure",
      shiny::p("Choose one participant session and stimulus exposure. The view never combines repeated exposures or people."),
      shiny::selectInput("gaze_report_exposure", "Participant, session and exposure", choices, choices[[1L]])), shiny::uiOutput("gaze_report_view"))
  }, error = function(e) brohn_card(title = "Gaze view needs attention", shiny::p(conditionMessage(e))))
}

brohn_install_gaze_report_server <- function(input, output, session, store, state) {
  output$gaze_report_view <- shiny::renderUI({
    shiny::req(identical(state$page, "report"), state$report_id, input$gaze_report_exposure)
    record <- brohn_get_entity(store, "report", state$report_id); shiny::req(record)
    brohn_gaze_report_ui(store, record$body, exposure_key = input$gaze_report_exposure, maximum_exposures = 1L)
  })
  invisible(TRUE)
}
