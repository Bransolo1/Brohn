# A text-only continuation using complete previously saved plot sources.
source("R/platform-load.R", encoding = "UTF-8"); brohn_load(ui = TRUE)
args <- commandArgs(trailingOnly = TRUE); stopifnot(length(args) == 3L)
folder <- normalizePath(args[[1L]], winslash = "/", mustWork = TRUE)
plots <- normalizePath(args[[2L]], winslash = "/", mustWork = TRUE)
accepted <- normalizePath(args[[3L]], winslash = "/", mustWork = TRUE)
before <- new.env(parent = globalenv()); sys.source(file.path(folder, "before-views.R"), envir = before)
old <- readLines(file.path(folder, "before-views.R"), warn = FALSE)
new <- readLines("R/platform-task-plot-views.R", warn = FALSE)
old_legend <- "Square = unavailable; grey = unscored"
new_legend <- "Grey = non-scoring position; square = unavailable"
old_explanation <- "Grey markers indicate practice or other unscored positions."
new_explanation <- "Grey markers indicate positions outside the scoring plan, such as practice or warm-up. A coloured point can still be excluded from scoring; inspect its disposition below."
expected <- gsub(old_legend, new_legend, old, fixed = TRUE)
expected <- gsub(old_explanation, new_explanation, expected, fixed = TRUE)
stopifnot(identical(expected, new), sum(old != new) == 2L)
source_hashes <- brohn_read_json_file(file.path(accepted, "source-hashes.json"))
phase <- brohn_read_json_file(file.path(accepted, "failure.json"))
stopifnot(length(phase$checks) == 13L, length(phase$scans) == 12L,
  all(vapply(phase$scans, function(x) x$violations == 0L && !x$overflow, logical(1))))
# The original harness pinned task-plots.R but omitted this separate view file.
# Do not invent an earlier file identity: compare its reproduced complete SVG
# bytes to the actual downloaded artifact instead.
checks <- list("Exactly two display strings changed from the retained 13-check report/import phase; its later cohort selector failure remains recorded")
for (alias in c("ORIGINAL-SCIAT-001", "ORIGINAL-SCIAT-002", "ORIGINAL-SCIAT-EDGE", "ORIGINAL-SCIAT-FAST")) {
  source <- brohn_read_json_file(file.path(plots, paste0(alias, "-plot-source.json")))
  for (scope in c("all", "scored")) {
    view <- brohn_task_plot_selection(source$complete_source, source$selection$measure, scope)
    for (width in c(320L, 680L)) {
      old_svg <- as.character(before$brohn_task_plot_svg(view, "chronology", width))
      new_svg <- as.character(brohn_task_plot_svg(view, "chronology", width))
      if (scope == source$selection$scope && width == 680L) stopifnot(identical(old_svg,
        paste(readLines(file.path(plots, paste0(alias, "-chronology.svg")), warn = FALSE), collapse = "\n")))
      stopifnot(identical(gsub(old_legend, new_legend, old_svg, fixed = TRUE), new_svg))
      if (alias == "ORIGINAL-SCIAT-FAST" && scope == "all") writeLines(new_svg,
        file.path(folder, paste0("fast-", width, ".svg")), useBytes = TRUE)
    }
    old_ui <- as.character(before$.brohn_tp_view_ui(view))
    expected_ui <- gsub(old_legend, new_legend, old_ui, fixed = TRUE)
    expected_ui <- gsub(old_explanation, new_explanation, expected_ui, fixed = TRUE)
    stopifnot(identical(expected_ui, as.character(.brohn_tp_view_ui(view))))
    checks[[length(checks) + 1L]] <- paste(alias, scope, "complete chronology geometry, values, distributions and numerical table unchanged")
  }
}
for (profile in head(names(brohn_task_profiles()), 5L)) {
  compiled <- brohn_task_compile(brohn_task_new(profile, id = "task-legend-fixture"), 1L)
  trials <- Filter(function(x) identical(x$type, "task_trial"), compiled$timeline)
  rows <- lapply(seq_along(trials), function(i) list(position = i, trial_id = trials[[i]]$id,
    profile_scored = trials[[i]]$scored, first_correct = TRUE, response_code = trials[[i]]$correct_code,
    first_response_ms = 500, outcome = "correct", disposition = if (isTRUE(trials[[i]]$scored)) "candidate_for_task_scoring" else "unscored_by_profile"))
  view <- brohn_task_plot_selection(list(kind = "trials", profile = profile, rows = rows,
    source_hash = brohn_hash(compiled), report_hash = strrep("a", 64L)))
  for (width in c(320L, 680L)) stopifnot(identical(
    gsub(old_legend, new_legend, as.character(before$brohn_task_plot_svg(view, width = width)), fixed = TRUE),
    as.character(brohn_task_plot_svg(view, width = width))))
  if (brohn_task_profile(profile)$kind == "biat") {
    block <- Filter(function(x) x$block_index == 2L, trials)
    stopifnot(any(vapply(block, function(x) isTRUE(x$scored), logical(1))),
      any(vapply(block, function(x) !isTRUE(x$scored), logical(1))))
  }
  checks[[length(checks) + 1L]] <- paste(profile, "all compiled position markers unchanged at both widths; wording covers within-block exclusions")
}
brohn_write_json_file(list(passed = TRUE, checks = checks,
  source_phase_sha256 = digest::digest(file = file.path(accepted, "failure.json"), algo = "sha256"),
  before_sha256 = digest::digest(file = file.path(folder, "before-views.R"), algo = "sha256"),
  after_sha256 = digest::digest(file = "R/platform-task-plot-views.R", algo = "sha256"),
  prior_identity_limit = "Original browser phase omitted the view-file hash; reproduced original full SVGs are checked against all four actual downloads.",
  scope = "Text-only rendering continuation. No study, original events, saved analysis, scoring, jobs or source selection changed."),
  file.path(folder, "results.json"))
cat("PASS14 task plot wording and exact rendering checks\n")
