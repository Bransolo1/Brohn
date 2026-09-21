# Independent arithmetic/source retention cases; no hardware/annotation qualification.
# Before wiring, BROHN_GAZE_STAGED_SOURCE may select the explicitly staged patch.
source("R/platform-participant-equipment.R")
for (module in c("platform-core", "platform-analysis", "platform-gaze", "platform-jobs", "platform-physiology-artifacts", "platform-gaze-traces", "platform-gaze-trace-views", "platform-gaze-trace-jobs"))
  source(paste0("R/", module, ".R"))
legacy_analysis <- brohn_raw_gaze_analysis
staged <- Sys.getenv("BROHN_GAZE_STAGED_SOURCE", "")
if (nzchar(staged)) source(staged)
local({
  checks <- 0L
  check <- function(name, value) { if (!isTRUE(value)) stop("FAIL: ", name); checks <<- checks+1L; cat("PASS ", name, "\n", sep = "") }
  close_number <- function(a, b) isTRUE(all.equal(a, b, tolerance = 1e-12, check.attributes = FALSE))
  rejected <- function(expr) inherits(try(force(expr), silent = TRUE), "try-error")
  args <- commandArgs(trailingOnly = TRUE)
  stopifnot(length(args) <= 1L)
  output <- if (length(args)) args[[1L]] else tempfile("brohn-gaze-traces-")
  stopifnot(!file.exists(output)); dir.create(output, recursive = TRUE)
  output <- normalizePath(output, winslash = "/")
  design <- brohn_new_design("Independent source trace fixture", id = "gaze-trace-test")
  m <- list(gaze_representation = "samples", unit = "stimulus_normalized", time_unit = "ms",
    time_column = "time", x_column = "x", y_column = "y", valid_column = "valid",
    participant_column = "participant", session_column = "session", stimulus_column = "stimulus",
    exposure_column = "exposure", condition_column = "condition", phase_column = "phase", phase_value = "view",
    exposure_start_column = "onset", exposure_end_column = "offset",
    pupil_column = "pupil", pupil_valid_column = "pupil_valid", pupil_unit = "mm", pupil_source = "Hand specified single-eye diameter",
    blink_column = "blink", blink_source = "Explicit test source labels; no detector",
    left_valid_column = "left", right_valid_column = "right",
    pupil_baseline = list(mode = "subtractive", phase_value = "baseline", start_column = "baseline_start", end_column = "baseline_end",
      minimum_coverage = .9, minimum_duration_ms = 90, source = "Independent 4 mm / 6 mm arithmetic; not physiological validation"),
    geometry = list(width_mm = 400, height_mm = 300, distance_mm = 600, center_x_mm = 0, center_y_mm = 0),
    geometry_source = "Fixed synthetic geometry",
    parameters = list(velocity_threshold_deg_s = 30, min_fixation_ms = 60, min_saccade_ms = 10, max_gap_ms = 20, threshold_source = "Synthetic threshold"))
  d <- data.frame(time = as.character(seq(0, 210, 10)), x = "0.25", y = "0.5", valid = " TRUE ", participant = "person-a",
    session = "session-a", stimulus = "stimulus-a", exposure = "clean", condition = "condition-a",
    phase = c(rep("baseline", 11), rep("view", 11)), onset = "110", offset = "210",
    pupil = c(rep("4", 11), rep("6", 11)), pupil_valid = "1", blink = "0", left = "TRUE", right = "false",
    baseline_start = "0", baseline_end = "100", stringsAsFactors = FALSE)
  pupil_summary <- function(x) Filter(function(e) identical(e$record_type, "pupil_summary"), x$features)[[1L]]
  captured <- list()
  collect <- list(emit = function(z, common, resolved) captured[[common$exposure_id]] <<- list(z = z, support = resolved))
  fresh <- brohn_raw_gaze_analysis(d, m, design, collect)
  old <- legacy_analysis(d, m, design)
  fresh_old <- fresh; fresh_old$parameters$blink_boundary_policy <- old$parameters$blink_boundary_policy
  check("original summary numbers and features unchanged on clean data", identical(fresh_old, old))
  summary <- pupil_summary(fresh)
  check("independent 4 mm baseline and 6 mm viewing subtract to 2", summary$baseline_mean == 4 && summary$mean_pupil == 6 && summary$baseline_corrected_mean == 2)
  check("independent interval membership is ten baseline and ten pupil intervals", identical(which(captured$clean$support$baseline_good), 1:10) &&
    identical(which(captured$clean$support$pupil_ok), 12:21) && sum(captured$clean$support$baseline_weights[captured$clean$support$baseline_good]) == 100)
  irregular <- d; irregular$time[2:10] <- as.character(c(3, 12, 21, 34, 48, 59, 73, 84, 97))
  irregular$pupil[1:11] <- as.character(4 + as.numeric(irregular$time[1:11])*.01)
  mm <- m; mm$parameters$max_gap_ms <- 30
  fit <- pupil_summary(brohn_raw_gaze_analysis(irregular, mm, design, collect))
  check("irregular samples preserve independent exact linear trapezoid mean", close_number(fit$baseline_mean, 4.5) && close_number(fit$baseline_corrected_mean, 1.5))
  bounded <- d; bounded$baseline_start <- "5"; bounded$baseline_end <- "95"
  mm <- m; mm$pupil_baseline$minimum_coverage <- 80/90; mm$pupil_baseline$minimum_duration_ms <- 80
  fit <- pupil_summary(brohn_raw_gaze_analysis(bounded, mm, design, collect))
  check("between-sample bounds retain exactly 80 of 90 ms without edge interpolation", fit$baseline_valid_ms == 80 && close_number(fit$baseline_coverage, 80/90) && fit$baseline_mean == 4)
  check("between-sample membership comes from original interior intervals", identical(which(captured$clean$support$baseline_good), 2:9))
  mm$pupil_baseline$minimum_duration_ms <- 81
  fit <- pupil_summary(brohn_raw_gaze_analysis(bounded, mm, design))
  check("insufficient baseline stays missing rather than corrected zero", is.null(fit$baseline_mean) && is.null(fit$baseline_corrected_mean) && fit$baseline_status == "excluded_insufficient_valid_baseline")

  bm <- m; bm$pupil_baseline <- list(mode = "none")
  bd <- d[1:5, ]; bd$time <- as.character(seq(0, 40, 10)); bd$phase <- c("baseline", "view", "view", "view", "response")
  bd$onset <- "10"; bd$offset <- "30"
  blink <- function(data) Filter(function(e) e$record_type == "source_labelled_blink", brohn_raw_gaze_analysis(data, bm, design)$features)
  cases <- list(onset = c(TRUE, TRUE, TRUE, FALSE, FALSE), offset = c(FALSE, FALSE, TRUE, TRUE, TRUE),
    both = rep(TRUE, 5), passive = c(FALSE, TRUE, TRUE, TRUE, FALSE), single = c(FALSE, FALSE, TRUE, FALSE, FALSE))
  expected <- list(onset = c(TRUE, FALSE), offset = c(FALSE, TRUE), both = c(TRUE, TRUE), passive = c(FALSE, FALSE), single = c(FALSE, FALSE))
  for (name in names(cases)) {
    candidate <- bd; candidate$blink <- as.character(cases[[name]]); ev <- blink(candidate)[[1L]]
    check(paste("independent source-label boundaries", name), identical(c(ev$onset_unobserved, ev$offset_unobserved), expected[[name]]))
    if (name == "single") check("single label remains a zero-span tick", ev$observed_duration_ms == 0 && ev$sample_count == 1L && ev$source_first_row == 3L)
  }
  candidate <- bd; candidate$blink <- c("1", "0", "0", "0", "1")
  check("baseline-only and response-only labels create no passive events", length(blink(candidate)) == 0L)
  candidate <- bd; candidate$phase <- "view"; candidate$onset <- "0"; candidate$offset <- "40"; candidate$blink <- "1"
  ev <- blink(candidate)[[1L]]
  check("record boundaries remain unknown", ev$onset_unobserved_reasons$record_boundary && ev$offset_unobserved_reasons$record_boundary)
  candidate$time <- c("0", "10", "50", "60", "70"); candidate$offset <- "70"
  ev <- blink(candidate)
  check("gap splits labelled runs with two unsupported adjacent boundaries", length(ev) == 2L && ev[[1]]$offset_unobserved_reasons$unsupported_gap && ev[[2]]$onset_unobserved_reasons$unsupported_gap)
  check("historical false flags are explicitly disclosed without mutation", grepl("did not account", brohn_gaze_blink_policy_disclosure(list()), fixed = TRUE) &&
    grepl("account for", brohn_gaze_blink_policy_disclosure(fresh$parameters), fixed = TRUE))

  dirty <- d; dirty$participant <- "person-b"; dirty$session <- "session-b"; dirty$exposure <- "dirty"
  dirty$pupil[12:18] <- c("0", "-1", "null", " 6.0000000000000009 ", "6", "6", "-0")
  dirty$pupil_valid[[16L]] <- "0"; dirty$blink[[17L]] <- "1"
  no_view <- d[1:3, ]; no_view$participant <- "person-c"; no_view$exposure <- "baseline-only"
  no_view$pupil <- c("0", "4", "4"); no_view$blink <- c("0", "1", "0")
  all_data <- rbind(d, dirty, no_view)
  # Interleaved source positions differ from exposure-local row indices.
  all_data <- all_data[order(as.numeric(all_data$time), all_data$participant), ]; rownames(all_data) <- NULL
  write.csv(all_data, file.path(output, "source.csv"), row.names = FALSE, na = "")
  brohn_write_json_file(list(design = design, mapping = m, source_file = "source.csv", source_rows = nrow(all_data),
    expectations = list(clean_baseline_mean = 4, clean_pupil_mean = 6, clean_corrected_mean = 2, tables = 3)), file.path(output, "fixture.json"))
  provenance <- list(source_sha256 = digest::digest(file = file.path(output, "source.csv"), algo = "sha256"),
    engine = list(name = "R sampled gaze recipe with complete trace retention", worker_sha256 = digest::digest(file = if (nzchar(staged)) staged else "R/platform-gaze.R", algo = "sha256")),
    operation = "gaze", origin = "synthetic", parameters = list(mapping = m, design_hash = brohn_hash(design)))
  sink <- brohn_gaze_trace_sink(output, all_data, m); on.exit(sink$abort(), add = TRUE)
  saved <- brohn_raw_gaze_analysis(all_data, m, design, sink)
  saved <- sink$finish(saved, provenance)
  check("actual R sink and typed writer retain every source row including no-passive group", saved$quality$trace_source_rows == nrow(all_data) && saved$quality$trace_tables == 3L &&
    saved$artifacts[[1]]$rows == nrow(all_data) && saved$artifact_verification$status == "verified")
  check("report has no second inline sample list", !any(c("samples", "trace_rows", "trace_points") %in% names(saved)))
  request <- function(operation, ...) {
    payload <- c(list(schema = "brohn-gaze-trace-preview/1.0", operation = operation, artifact = saved$artifacts[[1]]), list(...))
    request_file <- tempfile("request-", tmpdir = output, fileext = ".json"); result_file <- tempfile("result-", tmpdir = output, fileext = ".json")
    writeBin(charToRaw(enc2utf8(.brohn_gaze_trace_json(payload))), request_file)
    proc <- processx::run(brohn_python_profile("gaze"), c("scripts/workers/gaze_trace.py", "--request", request_file, "--output", result_file),
      timeout = 60000, error_on_status = FALSE, windows_hide_window = TRUE)
    if (proc$status != 0) stop(paste(readLines(result_file), collapse = "\n"))
    brohn_read_json_file(result_file, maximum = 16*1024^2)
  }
  catalog <- request("catalog")
  check("complete metadata-first catalog includes no-passive exposure without inline points", catalog$complete && length(catalog$tables) == 3L && catalog$source_rows == 47L && is.null(catalog$rows))
  views <- lapply(catalog$tables, function(t) request("preview", table_id = t$table_id, identity = t$identity))
  names(views) <- vapply(catalog$tables, function(t) t$identity$exposure_id, character(1))
  rv <- views$dirty$rows
  check("original raw numeric values and text remain distinct", rv[[12]]$pupil == 0 && rv[[13]]$pupil == -1 && is.null(rv[[14]]$pupil) && rv[[14]]$pupil_text == "null" &&
    rv[[15]]$pupil_text == " 6.0000000000000009 ")
  # R's ordinary JSON reader preserves the binary64 decimal and negative zero.
  check("difficult binary64 and signed zero round-trip through real R to Python artifact", identical(rv[[15]]$pupil, 6 + 2^-50) && identical(1/rv[[18]]$pupil, -Inf))
  check("original flags and effective masks remain separate", rv[[16]]$source_pupil_valid == FALSE && rv[[16]]$pupil == 6 && !rv[[16]]$effective_pupil_valid &&
    rv[[17]]$source_blink && !rv[[17]]$effective_pupil_valid && rv[[17]]$source_gaze_valid && rv[[17]]$source_gaze_valid_text == " TRUE ")
  check("exact global source rows survive interleaving", identical(as.integer(vapply(rv, `[[`, numeric(1), "source_row")), which(all_data$exposure == "dirty")))
  last <- tail(rv, 1L)[[1L]]
  check("terminal sample has no invented following interval", all(vapply(last[c("following_time_ms", "following_duration_ms", "pupil_interval_eligible", "baseline_interval_eligible")], is.null, logical(1))))
  check("separate left and right labels preserved", rv[[1]]$left_available && !rv[[1]]$right_available)
  clean_view <- views$clean
  check("per-sample correction retains actual 2 mm and separate interval support", clean_view$rows[[12]]$pupil_minus_baseline == 2 && clean_view$rows[[12]]$pupil_interval_eligible &&
    clean_view$rows[[22]]$pupil_minus_baseline == 2 && is.null(clean_view$rows[[22]]$pupil_interval_eligible))
  check("no-passive source group retains labels without fabricated baseline", views[["baseline-only"]]$selected_rows == 3L &&
    views[["baseline-only"]]$table$support$baseline$status == "no_passive_phase" && views[["baseline-only"]]$rows[[2]]$source_blink &&
    is.null(views[["baseline-only"]]$rows[[2]]$pupil_minus_baseline))
  check("resolved baseline boundaries and declaration stay source-bound", clean_view$table$support$baseline$start_ms == 0 && clean_view$table$support$baseline$end_ms == 100 &&
    clean_view$table$support$baseline$start_source_text[[1]] == "0" && clean_view$table$support$baseline$declaration$start_column == "baseline_start")
  check("generic line previews are explicitly forbidden by trace support", identical(clean_view$table$support$generic_line_preview, "forbidden_use_dedicated_gaze_adapter"))
  plot <- brohn_gaze_trace_plot_model(views$dirty)
  check("dedicated raw line mask independently splits phase and invalid endpoints", identical(plot$raw$segments, list(1:11, 15L, 19:22)))
  check("corrected line mask keeps isolated arithmetic point without duration", identical(plot$corrected$segments, list(15L, 19:22)))
  check("excluded finite values remain distinct unconnected observations", sum(!vapply(plot$raw$points, `[[`, logical(1), "valid")) == 5L)
  svg <- brohn_gaze_trace_svg(plot)
  check("actual SVG preserves single labelled sample as tick", length(plot$blink_ticks) == 1L && grepl('data-gaze-blink="true"', svg, fixed = TRUE))
  altered <- views$clean
  altered$rows[[5]]$following_gap <- TRUE
  altered$rows[[5]]$following_duration_ms <- 100
  gap_model <- brohn_gaze_trace_plot_model(altered)
  check("renderer refuses to bridge an explicitly unsupported interval", identical(gap_model$raw$segments, list(1:5, 6:11, 12:22)))
  altered <- views$clean; altered$rows[[2]]$row_index <- 999
  check("reordered selected table rows cannot produce a trace", rejected(brohn_gaze_trace_plot_model(altered)))
  markup <- htmltools::renderTags(brohn_gaze_trace_ui(views$dirty))$html
  writeLines(paste0('<!doctype html><html lang="en"><head><meta name="viewport" content="width=device-width, initial-scale=1"><title>Saved gaze trace component</title>',
    '<style>body{font:16px system-ui;margin:20px;color:#162f45;max-width:1080px}p{line-height:1.5}summary{padding:12px;cursor:pointer}td,th{padding:8px;text-align:left}table{border-collapse:collapse}td{border-top:1px solid #ddd}</style></head><body><main><h1>Saved gaze report</h1>',
    markup, '</main></body></html>'), file.path(output, "trace-component.html"), useBytes = TRUE)
  check("actual UI provides numerical alternative and honest denominator", grepl("Exact values and saved support", markup, fixed = TRUE) && grepl("22 source rows in this window", markup, fixed = TRUE))
  # Source flags remain nullable when their mapping is absent, including blink-only traces.
  variants <- file.path(output, "variants"); dir.create(variants)
  run_variant <- function(name, data, mapping) {
    scratch <- file.path(variants, name); dir.create(scratch)
    write.csv(data, file.path(scratch, "source.csv"), row.names = FALSE, na = "")
    variant_provenance <- provenance
    variant_provenance$source_sha256 <- digest::digest(file = file.path(scratch, "source.csv"), algo = "sha256")
    variant_provenance$parameters$mapping <- mapping
    s <- brohn_gaze_trace_sink(scratch, data, mapping); on.exit(s$abort(), add = TRUE)
    a <- s$finish(brohn_raw_gaze_analysis(data, mapping, design, s), variant_provenance)
    req <- list(schema = "brohn-gaze-trace-preview/1.0", operation = "catalog", artifact = a$artifacts[[1]])
    rq <- file.path(scratch, "catalog-request.json"); ro <- file.path(scratch, "catalog-result.json")
    writeBin(charToRaw(enc2utf8(.brohn_gaze_trace_json(req))), rq)
    proc <- processx::run(brohn_python_profile("gaze"), c("scripts/workers/gaze_trace.py", "--request", rq, "--output", ro), windows_hide_window = TRUE)
    catalog <- brohn_read_json_file(ro); t <- catalog$tables[[1L]]
    req$operation <- "preview"; req$table_id <- t$table_id; req$identity <- t$identity
    rq <- file.path(scratch, "preview-request.json"); ro <- file.path(scratch, "preview-result.json")
    writeBin(charToRaw(enc2utf8(.brohn_gaze_trace_json(req))), rq)
    proc <- processx::run(brohn_python_profile("gaze"), c("scripts/workers/gaze_trace.py", "--request", rq, "--output", ro), windows_hide_window = TRUE)
    brohn_read_json_file(ro)
  }
  missing_map <- m; missing_map$pupil_valid_column <- NULL; missing_map$blink_column <- NULL; missing_map$left_valid_column <- NULL; missing_map$right_valid_column <- NULL
  unmapped <- run_variant("unmapped-flags", d, missing_map)
  check("unmapped labels stay null rather than observed false", all(vapply(unmapped$rows[[1]][c("source_pupil_valid", "source_blink", "left_available", "right_available")], is.null, logical(1))))
  blink_only <- m; for (field in c("pupil_column", "pupil_valid_column", "pupil_unit", "pupil_source", "pupil_baseline")) blink_only[[field]] <- NULL
  only <- run_variant("blink-only", dirty, blink_only)
  check("blink-only trace retains true labels without a pupil measurement", only$rows[[17]]$source_blink && all(vapply(only$rows, function(r) is.null(r$pupil), logical(1))) &&
    !brohn_gaze_trace_plot_model(only)$pupil_mapped)
  sec_data <- d; for (field in c("time", "onset", "offset", "baseline_start", "baseline_end")) sec_data[[field]] <- sprintf("%.17g", as.numeric(sec_data[[field]])/1000)
  sec_mapping <- m; sec_mapping$time_unit <- "s"; sec_mapping$pupil_unit <- "device_units"
  seconds <- run_variant("seconds-unit", sec_data, sec_mapping)
  check("seconds conversion retains original text and declared device units", seconds$rows[[12]]$source_time_text == sec_data$time[[12]] &&
    seconds$rows[[12]]$analysis_time_ms == 110 && seconds$rows[[12]]$pupil_minus_baseline == 2 && seconds$table$support$pupil_unit == "device_units")
  reader_catalog <- brohn_gaze_trace_read(saved$artifacts[[1]], output)
  chosen <- reader_catalog$tables[[1L]]
  reader_view <- brohn_gaze_trace_read(saved$artifacts[[1]], output, chosen, chosen$initial_window$start_ms, chosen$initial_window$end_ms)
  check("internal complete reader applies explicit initial saved bounds", reader_catalog$complete && reader_view$status == "available" && reader_view$selected_rows == chosen$rows)
  native <- brohn_parse(rv[[18]]$exact_record_json)
  check("exact native preview fields preserve signed zero through generic catalog JSON", identical(1/native$pupil, -Inf) &&
    identical(brohn_parse(brohn_json(list(exact = rv[[18]]$exact_record_json)))$exact, rv[[18]]$exact_record_json) && rv[[18]]$pupil_decimal == "-0.0")
  direct <- list(operation = "gaze_trace_catalog", artifact = saved$artifacts[[1]][setdiff(names(saved$artifacts[[1]]), "path")],
    source_path = saved$artifacts[[1]]$path, original_source_hash = provenance$source_sha256,
    binding = list(report_id = "report-synthetic", report_revision = 1L, report_hash = strrep("a", 64), project_id = "project-test", catalog = NULL, selection = NULL))
  direct_folder <- file.path(output, "direct-domain"); dir.create(direct_folder)
  direct_catalog <- brohn_analyse_gaze_trace(direct, direct_folder)$gaze_trace_view
  check("domain catalog validator reconciles complete source and binding", direct_catalog$complete && identical(direct_catalog$binding$report_id, "report-synthetic"))
  wrong <- direct_catalog; wrong$source_provenance$source_sha256 <- strrep("f", 64)
  check("domain refuses substituted original source provenance", rejected(brohn_validate_gaze_trace_result(wrong, direct)))
  t <- Filter(function(t) t$identity$exposure_id == "dirty", direct_catalog$tables)[[1L]]
  direct$operation <- "gaze_trace_preview"; direct$table <- t
  direct$selection <- list(table_id = t$table_id, identity = t$identity, start_ms = t$initial_window$start_ms, end_ms = t$initial_window$end_ms)
  direct$binding$selection <- direct$selection
  direct_preview <- brohn_analyse_gaze_trace(direct, direct_folder)$gaze_trace_view
  check("saved-domain serialization preserves signed zero in exact native row despite numeric display normalization", direct_preview$rows[[18]]$pupil_decimal == "-0.0" &&
    identical(1/brohn_parse(direct_preview$rows[[18]]$exact_record_json)$pupil, -Inf))
  wrong <- direct_preview; wrong$range$end_ms <- wrong$range$end_ms-1
  check("domain refuses mismatched displayed and saved time bounds", rejected(brohn_validate_gaze_trace_result(wrong, direct)))
  exported <- brohn_gaze_trace_export_svg(direct_preview)
  check("standalone SVG embeds exact report and artifact source bindings", grepl(direct$binding$report_hash, exported, fixed = TRUE) &&
    grepl(direct$artifact$sha256, exported, fixed = TRUE) && grepl('id="brohn-gaze-trace-source"', exported, fixed = TRUE) &&
    grepl('viewBox="0 0 940 590"', exported, fixed = TRUE))
  hostile <- direct_preview; hostile$table$identity$participant_id <- "<script>alert(1)</script>"
  check("SVG source metadata escapes source text instead of injecting markup", !grepl("<script>", brohn_gaze_trace_export_svg(hostile), fixed = TRUE) &&
    grepl("&lt;script&gt;", brohn_gaze_trace_export_svg(hostile), fixed = TRUE))
  check("exact-value scroll region has keyboard and accessible-name semantics", grepl('tabindex="0"', markup, fixed = TRUE) &&
    grepl('aria-label="Exact pupil and blink values, horizontally scrollable"', markup, fixed = TRUE))
  brohn_write_json_file(list(checks = checks, source_rows = nrow(all_data), artifact = saved$artifacts[[1]], catalog = catalog,
    qualification = "independent software retention/arithmetic cases; no device or annotated blink qualification"), file.path(output, "acceptance.json"))
  cat(sprintf("PASS: %d gaze trace checks. Evidence: %s\n", checks, output))
})
