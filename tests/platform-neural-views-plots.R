source("R/platform-load.R", encoding = "UTF-8"); brohn_load()
source("R/platform-neural-views-plots.R", encoding = "UTF-8")
local({
  checks <- 0L
  check <- function(name, value) {if (!isTRUE(value)) stop("Neural plot QA: ", name, call. = FALSE); checks <<- checks+1L}
  rejects <- function(expr) inherits(try(force(expr), silent = TRUE), "try-error")
  close <- function(a, b, tolerance = 1e-8) isTRUE(all.equal(a, b, tolerance = tolerance, check.attributes = FALSE))
  root <- tempfile("brohn-neural-plots-"); dir.create(root); root <- normalizePath(root, winslash = "/")
  store <- brohn_open_store(file.path(root, "workspace")); brohn_initialise_library(store)
  on.exit({brohn_close_store(store); stopifnot(startsWith(tolower(normalizePath(root, winslash = "/")),
    paste0(tolower(normalizePath(tempdir(), winslash = "/")), "/"))); unlink(root, recursive = TRUE)}, add = TRUE)
  # Use the independently specified original pulse/sine fixtures and the actual
  # numerical worker, not hand-drawn UI numbers. Keep each source before reuse.
  fixture <- paste(
    "import importlib.util,json,sys,shutil; from pathlib import Path",
    "s=importlib.util.spec_from_file_location('neural_fixtures','tests/workers/neural.py'); m=importlib.util.module_from_spec(s); s.loader.exec_module(m)",
    "x=m.NeuralTests(); x.root=Path(sys.argv[1])",
    "for name,recipe in [('erp','eeg-erp-epochs/1.0'),('morlet','eeg-morlet-epochs/1.0'),('tag','eeg-frequency-tagging/1.0')]:",
    "    q=x.request(x.pulse()) if name=='erp' else x.sine_request(recipe)",
    "    result=m.worker.run(q); original=x.root/(name+'.csv'); shutil.copyfile(q['source_path'],original); q['source_path']=str(original)",
    "    (x.root/(name+'.json')).write_text(json.dumps({'request':q,'result':result},allow_nan=False),encoding='utf-8')", sep = "\n")
  processx::run(brohn_python_profile("eeg"), c("-B", "-c", fixture, root), timeout = 60000, windows_hide_window = TRUE)
  records <- lapply(c("erp", "morlet", "tag"), function(name) {
    x <- brohn_read_json_file(file.path(root, paste0(name, ".json"))); object <- brohn_store_object(store, path = x$request$source_path, media_type = "text/csv")
    body <- list(id = paste0("report-neural-", name), title = paste("Original", name, "fixture"), origin = "sample", created_at = "2026-09-08",
      analysis = c(list(kind = "eeg"), x$result), provenance = list(source = object, mapping = c(x$request$metadata, list(parameters = x$request$parameters))),
      processing = list(code_hashes = list(neural = x$result$engine$worker_sha256)))
    brohn_put_entity(store, "report", body$id, body, expected_revision = 0L, project_id = "default")
  }); names(records) <- c("erp", "morlet", "tag")
  reports <- lapply(records, `[[`, "body"); before <- lapply(reports, brohn_hash)
  models <- lapply(reports, brohn_neural_plot_model); erp <- models$erp; morlet <- models$morlet; tag <- models$tag
  e <- brohn_neural_plot_selection(erp); m <- brohn_neural_plot_selection(morlet); t <- brohn_neural_plot_selection(tag)
  check("actual evoked pulse stays 10 uV with three trials", max(e$y) == 10 && e$cell$support$retained_trials == 3 && max(e$sem) < 1e-10)
  check("absent condition remains an unavailable support row, not a trace", length(erp$cells) == 1L && length(erp$recordings) == 2L && erp$recordings[[2L]]$retained_trials == 0)
  check("actual stationary Morlet summary is retained near one", close(Filter(function(f) f$name == "morlet_power_mean" && f$frequency_hz == 10,
    m$cell$features)[[1L]]$value, 1, 1e-7) && m$unit == "ratio" && m$frequency_hz == 10)
  check("actual phase consistency is read from original saved total signal", close(brohn_neural_plot_selection(morlet, metric = "itc")$y, rep(1, length(m$y))))
  check("frequency by time axes are neither flattened nor transposed", identical(m$y, as.numeric(unlist(reports$morlet$analysis$series[[1L]]$transformed_power[[1L]]))) &&
    identical(brohn_neural_plot_selection(morlet, frequency_hz = 20)$y, as.numeric(unlist(reports$morlet$analysis$series[[1L]]$transformed_power[[2L]]))))
  check("actual tag peak is independently known 400 uV-squared per Hz at 10 Hz", close(t$y[[which(t$x == 10)]], 400) && t$unit == "uV^2/Hz")
  check("repeated labels never select another report", rejects(brohn_neural_plot_selection(morlet, erp$cells[[1L]]$selector)))
  check("unobserved intermediate frequency cannot be fabricated", rejects(brohn_neural_plot_selection(morlet, frequency_hz = 15)))
  check("wrong recipe measure cannot leak through stale controls", rejects(brohn_neural_plot_selection(erp, metric = "itc")))
  small <- brohn_neural_plot_selection(erp, start_index = 5L, maximum_points = 7L)
  check("window is seven exact contiguous samples without score change", identical(small$indices, 5:11) && identical(small$y, e$y[5:11]) && small$total_points == length(e$y))
  check("out-of-range and excessive windows fail explicitly", rejects(brohn_neural_plot_selection(erp, start_index = 0)) && rejects(brohn_neural_plot_selection(erp, maximum_points = 2001)))
  residual <- e; residual$y[[1L]] <- -8.47033e-16
  residual_svg <- as.character(brohn_neural_plot_svg(residual, 320))
  check("tiny native baseline residual does not become an overflowing axis endpoint label", !grepl(">-8.47033e-16<", residual_svg, fixed = TRUE) && grepl('x="68"', residual_svg, fixed = TRUE))
  check("tick formatting leaves tiny retained voltages unchanged", identical(residual$y[[1L]], -8.47033e-16))
  for (name in names(models)) {
    model <- models[[name]]; html <- as.character(brohn_neural_report_plots(reports[[name]])); svg <- as.character(brohn_neural_plot_svg(brohn_neural_plot_selection(model), 320))
    check(paste(name, "accessible compact SVG, numerical alternative and frozen support"), grepl('viewBox="0 0 320 330"', svg, fixed = TRUE) && grepl('role="img"', svg, fixed = TRUE) &&
      grepl("Neural waveform numerical alternative", html, fixed = TRUE) && grepl("minimum 2", html, fixed = TRUE) && grepl(model$source_hash, svg, fixed = TRUE))
    check(paste(name, "self-contained responsive export without external media"), grepl("@media(max-width:600px)", html, fixed = TRUE) && !grepl('src="https?://|href="https?://|<script', html, perl = TRUE))
    path <- file.path(root, paste0(name, "-full.csv")); brohn_neural_plot_csv(model, model$cells[[1L]]$selector, path)
    csv <- utils::read.csv(path, check.names = FALSE, stringsAsFactors = FALSE)
    check(paste(name, "download includes every sample/frequency beyond chart preview"), nrow(csv) == length(model$cells[[1L]]$axis)*if (name == "morlet") 2L else 1L)
    check(paste(name, "download preserves immutable lineage"), all(csv$report_sha256 == model$report_hash) && all(csv$source_sha256 == model$source_hash))
  }
  nulls <- reports$morlet; nulls$analysis$series[[1L]]$transformed_power[[1L]][10L] <- list(NULL)
  nm <- brohn_neural_plot_model(nulls); nv <- brohn_neural_plot_selection(nm)
  check("null trace sample disconnects two actual support paths", lengths(regmatches(as.character(brohn_neural_plot_svg(nv)), gregexpr("<polyline", as.character(brohn_neural_plot_svg(nv)), fixed = TRUE))) == 2L && is.na(nv$y[[10L]]))
  nulls$analysis$series[[1L]]$transformed_power[[1L]] <- rep(list(NULL), length(nv$y)); nm <- brohn_neural_plot_model(nulls); nv <- brohn_neural_plot_selection(nm)
  check("unavailable transform draws no zero line", is.null(brohn_neural_plot_svg(nv)) && grepl("no zero-valued response", as.character(brohn_neural_report_plots(nulls)), fixed = TRUE))
  path <- file.path(root, "null.csv"); brohn_neural_plot_csv(nm, nm$cells[[1L]]$selector, path); empty <- utils::read.csv(path)
  check("full CSV preserves missing transform and other retained metrics", all(is.na(empty$transformed_power[empty$frequency_hz == 10])) && all(is.finite(empty$power_uv2)))
  bad <- reports$erp; bad$analysis$source$sha256 <- paste(rep("a", 64), collapse = "")
  check("source mismatch refuses view", rejects(brohn_neural_plot_model(bad)))
  bad <- reports$erp; bad$analysis$series[[1L]]$trial_count <- 2L
  check("trial count mismatch refuses view", rejects(brohn_neural_plot_model(bad)))
  bad <- reports$erp; bad$analysis$series[[1L]]$time_s[[10L]] <- bad$analysis$series[[1L]]$time_s[[10L]]+0.001
  check("irregular event-relative grid is not silently connected", rejects(brohn_neural_plot_model(bad)))
  bad <- reports$morlet; bad$analysis$series[[1L]]$array_axes <- list("time", "frequency")
  check("reversed matrix axes refuse plausible-looking plot", rejects(brohn_neural_plot_model(bad)))
  bad <- reports$morlet; bad$analysis$series[[1L]]$transformed_unit <- "uV"
  check("wrong baseline-transform units refuse plot", rejects(brohn_neural_plot_model(bad)))
  for (value in list(TRUE, "1", Inf)) {
    bad <- reports$erp; bad$analysis$series[[1L]]$mean_uv[1L] <- list(value)
    check("typed/nonfinite values never coerced into voltage", rejects(brohn_neural_plot_model(bad)))
  }
  repeated <- reports$erp; for (i in 1:3) {
    s <- repeated$analysis$series[[1L]]; s$group <- switch(i, list(participant_id = "another-person", session_id = "visit"),
      list(participant_id = "same-person", session_id = "another-visit"), list(participant_id = "same-person", session_id = "visit", segment_id = "reset-two"))
    r <- repeated$analysis$recordings[[1L]]; r$group <- s$group; repeated$analysis$series <- c(repeated$analysis$series, list(s)); repeated$analysis$recordings <- c(repeated$analysis$recordings, list(r))
  }
  check("same labels across source people/session/segments remain four distinct cells", length(brohn_neural_plot_model(repeated)$cells) == 4L)
  bad <- reports$erp; bad$analysis$series <- c(bad$analysis$series, bad$analysis$series)
  check("duplicate exact cell refuses silent pooling", rejects(brohn_neural_plot_model(bad)))
  injected <- reports$erp; injected$analysis$series[[1L]]$channel <- "=bad<script>alert(1)</script>"
  ih <- as.character(brohn_neural_report_plots(injected)); im <- brohn_neural_plot_model(injected)
  check("source channel text is escaped in plot and labels", !grepl("<script>", ih, fixed = TRUE) && grepl("&lt;script&gt;", ih, fixed = TRUE))
  path <- file.path(root, "safe.csv"); brohn_neural_plot_csv(im, im$cells[[1L]]$selector, path)
  check("CSV protects source text against spreadsheet formula interpretation", startsWith(utils::read.csv(path)$channel[[1L]], "'=bad"))
  check("all rendering leaves immutable reports and source objects unchanged", identical(lapply(reports, brohn_hash), before) && all(vapply(records, function(r)
    identical(brohn_hash(brohn_get_entity(store, "report", r$id)$body), brohn_hash(r$body)), logical(1))))
  # Actual Shiny reactive source switching and download guards.
  server <- function(input, output, session) {
    state <- shiny::reactiveValues(page = "report", report_id = records$erp$id)
    api <- brohn_install_neural_plots(input, output, session, store, state, function(fn) fn(), function(...) NULL, function(fn) fn())
  }
  shiny::testServer(server, {
    session$setInputs(neural_plot_cell = erp$cells[[1L]]$selector, neural_plot_form = erp$cells[[1L]]$selector, neural_plot_start = 1)
    check("Shiny renders exact first stored ERP", identical(api$selected()$y, e$y))
    state$report_id <- records$morlet$id; session$flushReact()
    check("old selector cannot be downloaded on new report", rejects(api$selected()))
    session$setInputs(neural_plot_cell = morlet$cells[[1L]]$selector); session$flushReact()
    check("old form cannot apply to freshly selected Morlet cell", rejects(api$selected()))
    session$setInputs(neural_plot_form = morlet$cells[[1L]]$selector, neural_plot_start = 11,
      neural_plot_metric = "itc", neural_plot_frequency = "2")
    check("Shiny preserves exact frequency/metric/window selection", api$selected()$frequency_hz == 20 && api$selected()$metric == "itc" && min(api$selected()$indices) == 11)
    session$setInputs(neural_plot_start = 999999)
    check("invalid window is actionable without replacing saved support", rejects(api$selected()) && grepl("Choose a saved sample index", output$neural_plot_view$html, fixed = TRUE))
    state$page <- "home"; session$flushReact()
    check("navigated-away report cannot serve stale selection downloads", rejects(api$selected()))
  })
  cat(sprintf("PASS: %d neural plot checks using actual ERP/Morlet/tagging outputs, typed arrays, full downloads and Shiny guards\n", checks))
})
