# Renderer checks use independent exact-sample fixtures and actual saved jobs.
args <- commandArgs(trailingOnly = TRUE); stopifnot(length(args) == 3L)
source("R/platform-load.R", encoding = "UTF-8"); brohn_load()
local({
  checks <- 0L
  check <- function(name, value) {if (!isTRUE(value)) stop("Cardiac marker view QA: ", name, call. = FALSE); checks <<- checks+1L}
  root <- normalizePath(args[[1L]], winslash = "/", mustWork = TRUE)
  reference <- normalizePath(args[[2L]], winslash = "/", mustWork = TRUE)
  output <- normalizePath(args[[3L]], winslash = "/", mustWork = FALSE); dir.create(output, recursive = TRUE, showWarnings = FALSE)
  stopifnot(startsWith(basename(output), "brohn-cardiac-marker-ui-"))
  read <- function(path) brohn_read_json_file(path)
  save <- function(name, view) {
    body <- list(body = list(view = view)); html <- as.character(brohn_signal_plot_ui(body))
    writeLines(paste0('<!doctype html><html lang="en"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Brohn detection review</title>',
      '<style>body{margin:0}.container-fluid{padding:12px}</style></head><body><main class="container-fluid"><div class="brohn-app"><h1>Saved detection review fixture</h1>',
      html, '</div></main></body></html>'), file.path(output, paste0(name, ".html")), useBytes = TRUE)
    svg <- brohn_signal_svg(view)
    if (!is.null(svg)) writeLines(as.character(svg), file.path(output, paste0(name, ".svg")), useBytes = TRUE)
    brohn_write_json_file(view, file.path(output, paste0(name, "-view.json")))
    html
  }
  for (modality in c("ecg", "ppg")) {
    view <- read(file.path(root, paste0(modality, "-view.json"))); original <- brohn_hash(view)
    svg <- as.character(brohn_signal_svg(view)); html <- save(modality, view)
    marker_tags <- regmatches(svg, gregexpr('<circle class="brohn-cardiac-marker"[^>]*>', svg))[[1L]]
    check(paste(modality, "all four exact detections drawn once"), length(marker_tags) == 4L && all(vapply(c(501,503,505,507), function(i) any(grepl(paste0('data-source-sample="', i, '"'), marker_tags, fixed = TRUE)), logical(1))))
    check(paste(modality, "markers omitted by extrema line still appear"), !505 %in% unlist(lapply(view$envelopes, function(b) vapply(b$points, `[[`, numeric(1), "source_sample_index"))) && grepl('data-source-sample="505"', svg, fixed = TRUE))
    check(paste(modality, "independent sample coordinates use exact observed values"), grepl('cx="193.750" cy="279.429"', marker_tags[[1L]], fixed = TRUE) && grepl('cx="592.750" cy="85.143"', marker_tags[[3L]], fixed = TRUE))
    check(paste(modality, "source indices and null/false interval states remain visible"), all(vapply(c("Unavailable", "Not available", "Outside declared bounds", "Within declared bounds", "Previous interval (ms)", "zero-based", "before this displayed window"), function(x) grepl(x, html, fixed = TRUE), logical(1))))
    check(paste(modality, "SVG standalone accessibility carries unreviewed semantics"), grepl('role="img"', svg, fixed = TRUE) && grepl("unreviewed algorithm detections", svg, fixed = TRUE) && grepl("cleaned waveform", svg, fixed = TRUE))
    check(paste(modality, "modality and original value units retained"), grepl(if (modality == "ecg") "Unreviewed R-peak detections" else "Unreviewed pulse-peak detections", html, fixed = TRUE) &&
      grepl(paste0("Cleaned value (", view$axis$value_unit, ")"), html, fixed = TRUE) && grepl(if (modality == "ecg") "normal-to-normal" else "PRV", html, fixed = TRUE))
    check(paste(modality, "all table rows present without default hundred-row truncation"), !grepl("Showing 100", html, fixed = TRUE) && grepl("Inspect all 4 selected detections", html, fixed = TRUE))
    check(paste(modality, "rendering leaves exact saved view unchanged"), identical(brohn_hash(view), original))
    legacy <- view; legacy$marker_overlay <- NULL
    check(paste(modality, "historical view does not acquire inferred markers"), !grepl("brohn-cardiac-marker", as.character(brohn_signal_svg(legacy)), fixed = TRUE) && is.null(brohn_signal_marker_ui(legacy)))
  }
  view <- read(file.path(reference, "reference108-view.json")); html <- save("reference108", view)
  check("recorded failed detector displays all seven unchanged selected events", view$marker_overlay$selected_marker_count == 7 && lengths(regmatches(as.character(brohn_signal_svg(view)), gregexpr('class="brohn-cardiac-marker"', as.character(brohn_signal_svg(view)), fixed = TRUE))) == 7)
  check("recorded table retains full precision and exact imported unit", grepl(brohn_signal_exact_number(view$marker_overlay$markers[[1L]]$time_s), html, fixed = TRUE) && grepl("Cleaned value (uV)", html, fixed = TRUE))
  # These are outputs of the same independently defined artifact fixture,
  # processed by the actual artifact reader; no hand-built marker status.
  code <- paste("import importlib.util,json,sys;from pathlib import Path",
    "s=importlib.util.spec_from_file_location('cases','tests/workers/cardiac_markers.py');m=importlib.util.module_from_spec(s);s.loader.exec_module(m)",
    "root=Path(sys.argv[1])",
    "for name,options in [('limit',dict(n=5005,indices=list(range(1,5005,2)))),('empty',dict(indices=[]))]:",
    " folder=root/name;folder.mkdir(exist_ok=True);v=m.worker.run(m.fixture(folder,**options));(root/(name+'-view.json')).write_text(json.dumps(v),encoding='utf-8')", sep = "\n")
  processx::run(brohn_python_profile("ecg"), c("-B", "-c", code, output), windows_hide_window = TRUE)
  limit <- read(file.path(output, "limit-view.json")); limit_html <- save("limit", limit)
  check("actual excess-marker output explains all-or-none display and recovery", limit$marker_overlay$selected_marker_count == 2502 &&
    !grepl('class="brohn-cardiac-marker"', as.character(brohn_signal_svg(limit)), fixed = TRUE) && grepl("2000-marker display limit", limit_html, fixed = TRUE) && grepl("enter a shorter start and end", limit_html, fixed = TRUE))
  check("excess event count does not claim checked waveform alignment", identical(limit$marker_overlay$alignment, "not_checked_display_limit_exceeded") &&
    grepl("waveform positions have not been checked", limit_html, fixed = TRUE) && grepl("check each source sample", limit_html, fixed = TRUE))
  empty <- read(file.path(output, "empty-view.json")); empty_html <- save("empty", empty)
  check("actual empty event table retains waveform without claiming absent beats", !is.null(brohn_signal_svg(empty)) && grepl("does not imply absent heartbeats", empty_html, fixed = TRUE) && !grepl("Inspect all", empty_html, fixed = TRUE))
  corrupt <- view; corrupt$marker_overlay$review_status <- "reviewed"
  check("renderer refuses invented reviewed state", inherits(try(brohn_signal_svg(corrupt), silent = TRUE), "try-error"))
  corrupt <- view; corrupt$marker_overlay$selected_marker_count <- 8
  check("renderer refuses partial marker support", inherits(try(brohn_signal_svg(corrupt), silent = TRUE), "try-error"))
  brohn_write_json_file(list(checks = checks, reference_origin = "published_reference_recording", detector_accuracy_qualified = FALSE), file.path(output, "renderer-results.json"))
  cat(sprintf("PASS: %d cardiac marker rendering checks; evidence %s\n", checks, output))
})
